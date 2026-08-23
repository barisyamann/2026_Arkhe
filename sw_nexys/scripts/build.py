import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "src"
LINK_DIR = ROOT / "link"
BUILD_DIR = ROOT / "build"
CONFIG_FILE = ROOT / ".." / "teknotest" / "user_files" / "rv_toolchain.conf"
USER_FILES_DIR = ROOT / ".." / "teknotest" / "user_files"

# 1. asama: yukleyici -> Boot ROM (1 kB)
BOOT_HEX_DEST = ROOT / ".." / "rtl" / "boot" / "boot.hex"
BOOT_ROM_BYTES = 1024

# 2. asama: uygulama -> QSPI flash imaji, yukleyici I-RAM'e kopyalar
APP_HEX_DEST = ROOT / "build" / "app.hex"
APP_BIN_DEST = ROOT / "build" / "app.bin"
APP_IMAGE_BYTES = 8192

# Vivado simulasyon dizinleri - derleme sonunda app.hex buraya kopyalanir
SIM_DIRS_ROOT = ROOT / ".." / "vivado" / "vivado_nexys_project"

INCLUDE_DIRS = [
    SRC_DIR,
    USER_FILES_DIR,
]

ARCH_FLAGS = [
    # zicsr: kontrol/durum yazmaci komutlari (csrr, csrw, csrsi).
    # GCC 12'den itibaren temel 'i' uzantisindan ayrildi ve acikca
    # belirtilmesi gerekiyor. Kesme kurulumu bu komutlari kullaniyor.
    "-march=rv32imc_zicsr",
    "-mabi=ilp32",
    "-mcmodel=medlow",
]

COMMON_CFLAGS = [
    "-Os",
    "-ffreestanding",
    "-fno-builtin",
    "-Wall",
    "-Wextra",
]

ASM_FLAGS = ["-x", "assembler-with-cpp"]

LINK_FLAGS = [
    "-nostartfiles",
    "-nostdlib",
]


def load_local_config():
    namespace = {}
    if CONFIG_FILE.exists():
        code = CONFIG_FILE.read_text(encoding="utf-8")
        exec(code, namespace)
    return namespace


def resolve_toolchain_prefix():
    env_prefix = os.environ.get("RISCV_GCC_PREFIX")
    if env_prefix:
        return env_prefix

    cfg = load_local_config()
    cfg_prefix = cfg.get("RISCV_GCC_PREFIX")
    if cfg_prefix:
        return cfg_prefix

    gcc_path = shutil.which("riscv-none-elf-gcc") or shutil.which("riscv32-unknown-elf-gcc")
    if gcc_path:
        gcc_path = Path(gcc_path).resolve()
        return str(gcc_path.parent / gcc_path.name.replace("-gcc", ""))

    raise RuntimeError("RISC-V toolchain prefix could not be resolved.")


def resolve_executable(prefix, suffix):
    candidates = [f"{prefix}-{suffix}", f"{prefix}-{suffix}.exe"]
    for candidate in candidates:
        if shutil.which(candidate) or Path(candidate).exists():
            return str(Path(candidate))
    raise RuntimeError(f"Could not find executable for suffix: {suffix}")


def compile_source(gcc, source_file, output_file, extra_flags=None):
    inc_flags = []
    for inc in INCLUDE_DIRS:
        inc_flags += ["-I", str(inc)]
    cmd = [gcc] + ARCH_FLAGS + COMMON_CFLAGS + inc_flags
    if extra_flags:
        cmd += extra_flags
    cmd += ["-c", str(source_file), "-o", str(output_file)]
    print(f">> {' '.join(cmd)}")
    subprocess.check_call(cmd)


def link_objects(gcc, object_files, linker_script, elf_file, map_file):
    cmd = [gcc] + ARCH_FLAGS + LINK_FLAGS
    cmd += [str(obj) for obj in object_files]
    cmd += [
        f"-Wl,-T,{linker_script}",
        f"-Wl,-Map={map_file}",
        "-o", str(elf_file),
    ]
    print(f">> {' '.join(cmd)}")
    subprocess.check_call(cmd)


def to_hex_words(data, total_bytes):
    """Ham ikili veriyi $readmemh uyumlu 32-bit little-endian kelimelere cevirir."""
    if len(data) > total_bytes:
        raise ValueError(
            f"Imaj {len(data)} bayt, sinir {total_bytes} bayt. Tasma var."
        )
    padded = data + b"\x00" * (total_bytes - len(data))
    words = []
    for i in range(0, total_bytes, 4):
        val = int.from_bytes(padded[i:i + 4], byteorder="little", signed=False)
        words.append(f"{val:08x}")
    return words


def build_image(gcc, objcopy, size, name, c_sources, asm_sources,
                linker_script, image_bytes, hex_dest, bin_dest=None,
                extra_defs=None):
    print(f"\n=== {name} ===")
    obj_dir = BUILD_DIR / name
    obj_dir.mkdir(parents=True, exist_ok=True)

    object_files = []
    for src in c_sources:
        obj = obj_dir / (src.stem + ".o")
        compile_source(gcc, src, obj, extra_defs)
        object_files.append(obj)
    for src in asm_sources:
        obj = obj_dir / (src.stem + ".o")
        compile_source(gcc, src, obj, ASM_FLAGS)
        object_files.append(obj)

    elf_file = obj_dir / f"{name}.elf"
    map_file = obj_dir / f"{name}.map"
    tmp_bin = obj_dir / f"{name}.bin"

    link_objects(gcc, object_files, linker_script, elf_file, map_file)
    subprocess.check_call([size, str(elf_file)])
    subprocess.check_call([objcopy, "-O", "binary", str(elf_file), str(tmp_bin)])

    data = tmp_bin.read_bytes()
    print(f"Ham ikili boyut: {len(data)} bayt  (sinir {image_bytes})")

    words = to_hex_words(data, image_bytes)
    hex_dest.parent.mkdir(parents=True, exist_ok=True)
    hex_dest.write_text("\n".join(words) + "\n", encoding="ascii")
    print(f"Yazildi: {hex_dest}")

    if bin_dest is not None:
        bin_dest.parent.mkdir(parents=True, exist_ok=True)
        bin_dest.write_bytes(data + b"\x00" * (image_bytes - len(data)))
        print(f"Yazildi: {bin_dest}")

    return len(data)


def deploy_to_sim(hex_file):
    """app.hex'i Vivado'nun simulasyon dizinlerine kopyalar.

    Testbench $readmemh("app.hex", ...) cagirir ve Vivado bunu xsim
    calisma dizinine gore cozer. Bu adim atlanirsa simulasyon sessizce
    ESKI yazilimi kosar - 18 Agustos'ta tam olarak bu oldu ve hatanin
    RTL'de sanilmasina yol acti. Log'daki tek ipucu, kaynak kodda artik
    bulunmayan bir yazdirma satiriydi.

    Hedef dizin yoksa atlanir (proje henuz simule edilmemis olabilir).
    """
    targets = [
        SIM_DIRS_ROOT / p for p in (
            Path("Arkhe_SoC_Nexys.sim") / "sim_1" / "behav" / "xsim",
            Path("Arkhe_SoC_Nexys.ip_user_files") / "mem_init_files",
        )
    ]

    copied = 0
    for target in targets:
        if target.is_dir():
            shutil.copy2(hex_file, target / hex_file.name)
            copied += 1
    return copied


def main():
    prefix = resolve_toolchain_prefix()
    gcc = resolve_executable(prefix, "gcc")
    objcopy = resolve_executable(prefix, "objcopy")
    size = resolve_executable(prefix, "size")

    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # --- 1. asama: yukleyici (Boot ROM'da kalir, degistirilemez) ---
    boot_size = build_image(
        gcc, objcopy, size,
        name="bootloader",
        c_sources=[],
        asm_sources=[SRC_DIR / "bootloader.S"],
        linker_script=LINK_DIR / "bootloader.ld",
        image_bytes=BOOT_ROM_BYTES,
        hex_dest=BOOT_HEX_DEST,
    )

    # --- 2. asama: uygulama (QSPI flash'ta durur, I-RAM'e yuklenir) ---
    app_size = build_image(
        gcc, objcopy, size,
        name="app",
        c_sources=[SRC_DIR / "main.c"],
        asm_sources=[SRC_DIR / "crt0.S"],
        linker_script=LINK_DIR / "app.ld",
        image_bytes=APP_IMAGE_BYTES,
        hex_dest=APP_HEX_DEST,
        bin_dest=APP_BIN_DEST,
    )

    # -------------------------------------------------------------------------
    # SIMULASYON YAPIMI - app_sim.hex
    #
    # ARKHE_SIM tanimli: cikarimlar arasi bekleme 3 s yerine 2 ms.
    # Boylece "global reset olmadan iki cikarim" (REUSE) testi simulasyonda
    # kosulabiliyor - 3 saniye 150 milyon cevrim demek ve ~3,5 saat surerdi.
    #
    # BASKA HICBIR FARK YOKTUR: boot, DMA, NPU, ISR ve UART yollari iki
    # yapimda da birebir aynidir.
    # -------------------------------------------------------------------------
    build_image(
        gcc, objcopy, size,
        name="app_sim",
        c_sources=[SRC_DIR / "main.c"],
        asm_sources=[SRC_DIR / "crt0.S"],
        linker_script=LINK_DIR / "app.ld",
        image_bytes=APP_IMAGE_BYTES,
        hex_dest=BUILD_DIR / "app_sim.hex",
        extra_defs=["-DARKHE_SIM"],
    )

    copied = deploy_to_sim(APP_HEX_DEST)

    print("\n=== OZET ===")
    print(f"Yukleyici : {boot_size:5d} / {BOOT_ROM_BYTES} bayt  -> {BOOT_HEX_DEST.name}")
    print(f"Uygulama  : {app_size:5d} / {APP_IMAGE_BYTES} bayt  -> {APP_HEX_DEST.name}")
    if copied:
        print(f"Simulasyon dizinlerine kopyalandi ({copied} adet)")
    else:
        print("UYARI: simulasyon dizini bulunamadi, app.hex kopyalanmadi.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"\nHATA: {exc}")
        sys.exit(1)
