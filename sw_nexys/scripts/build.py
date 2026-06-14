import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "src"
BUILD_DIR = ROOT / "build"
CONFIG_FILE = ROOT / ".." / "teknotest" / "user_files" / "rv_toolchain.conf"
LINKER_SCRIPT = ROOT / ".." / "teknotest" / "user_files" / "bootrom.ld"
USER_FILES_DIR = ROOT / ".." / "teknotest" / "user_files"
BOOT_HEX_DEST = ROOT / ".." / "rtl" / "boot" / "boot.hex"

PROJECT_NAME = "fpga_test"

C_SOURCES = [
    SRC_DIR / "main.c",
]

ASM_SOURCES = [
    SRC_DIR / "crt0.S",
]

INCLUDE_DIRS = [
    SRC_DIR,
    USER_FILES_DIR,
]

ARCH_FLAGS = [
    "-march=rv32imc",
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

ASM_FLAGS = [
    "-x", "assembler-with-cpp",
]

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
    candidates = [
        f"{prefix}-{suffix}",
        f"{prefix}-{suffix}.exe",
    ]
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
    print(f">> Executing: {' '.join(cmd)}")
    subprocess.check_call(cmd)


def link_objects(gcc, object_files, elf_file, map_file):
    cmd = [gcc] + ARCH_FLAGS + LINK_FLAGS
    cmd += [str(obj) for obj in object_files]
    cmd += [
        f"-Wl,-T,{LINKER_SCRIPT}",
        f"-Wl,-Map={map_file}",
        "-o", str(elf_file),
    ]
    print(f">> Executing: {' '.join(cmd)}")
    subprocess.check_call(cmd)


def main():
    prefix = resolve_toolchain_prefix()
    gcc = resolve_executable(prefix, "gcc")
    objcopy = resolve_executable(prefix, "objcopy")
    size = resolve_executable(prefix, "size")

    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    object_files = []
    for c_src in C_SOURCES:
        obj = BUILD_DIR / (c_src.stem + ".o")
        compile_source(gcc, c_src, obj)
        object_files.append(obj)

    for asm_src in ASM_SOURCES:
        obj = BUILD_DIR / (asm_src.stem + ".o")
        compile_source(gcc, asm_src, obj, ASM_FLAGS)
        object_files.append(obj)

    elf_file = BUILD_DIR / f"{PROJECT_NAME}.elf"
    map_file = BUILD_DIR / f"{PROJECT_NAME}.map"
    bin_file = BUILD_DIR / f"{PROJECT_NAME}.bin"

    link_objects(gcc, object_files, elf_file, map_file)

    # Print sizes
    subprocess.check_call([size, str(elf_file)])

    # Extract raw binary
    cmd_copy = [objcopy, "-O", "binary", str(elf_file), str(bin_file)]
    print(f">> Executing: {' '.join(cmd_copy)}")
    subprocess.check_call(cmd_copy)

    # Read binary and pad to exactly 1024 bytes (256 words)
    data = bin_file.read_bytes()
    bin_size = len(data)
    print(f"Raw binary size: {bin_size} bytes")
    if bin_size > 1024:
        raise ValueError(f"Error: Program size {bin_size} bytes exceeds Boot ROM size of 1024 bytes!")

    padded_data = data + b"\x00" * (1024 - bin_size)

    # Write formatted hex output for $readmemh (little-endian 32-bit words)
    words = []
    for i in range(0, 1024, 4):
        chunk = padded_data[i:i+4]
        # format as little-endian 32-bit hex word
        val = int.from_bytes(chunk, byteorder="little", signed=False)
        words.append(f"{val:08x}")

    BOOT_HEX_DEST.write_text("\n".join(words) + "\n", encoding="ascii")
    print(f"Successfully wrote padded Boot ROM image to: {BOOT_HEX_DEST}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"\nERROR: {exc}")
        sys.exit(1)
