#!/usr/bin/env python3
# =============================================================================
#  trace_check.py - CV32E40P buyruk izi denetimi
#
#  NE YAPAR
#    Simulasyondan toplanan PC dizisini, DERLENMIS PROGRAMIN kendi
#    disassembly ciktisiyla karsilastirir:
#
#      1. Yurutulen her PC, programda gercekten var olan bir buyruk
#         adresi midir?  (hizali olmayan / gecersiz getirme yakalanir)
#      2. Ardisik her PC cifti mesru bir gecis midir?
#         - sirali  : pc + buyruk_uzunlugu  (2 bayt sikistirilmis, 4 bayt normal)
#         - dallanma: disassembly'de o adresteki dal/atlama hedefi
#
#  NEDEN BOYLE
#    Onceki surum (compare_trace.py) "Spike ISS referans modeli" adi altinda
#    ELLE YAZILMIS 20 adresli sabit bir dizi kullaniyordu. Spike hicbir zaman
#    kosulmadi. Ustelik o dizi guncel bootloader'a da uymuyordu: 0x8 ve 0xa
#    adreslerindeki SIKISTIRILMIS (2 baytlik) buyruklari hesaba katmiyor,
#    her buyrugu 4 bayt sayiyordu.
#
#    Bu surum referansi uydurmuyor - dogrudan .elf dosyasindan uretiyor.
#    Spike degil, ama gercek: karsilastirma noktasi CPU'nun kosmasi
#    beklenen programin ta kendisi.
# =============================================================================
import os
import re
import subprocess
import sys

OBJDUMP_ADAYLARI = [
    r"C:\xpack-riscv-none-elf-gcc-13.2.0-2\bin\riscv-none-elf-objdump.exe",
    "riscv-none-elf-objdump",
    "riscv64-unknown-elf-objdump",
    "riscv32-unknown-elf-objdump",
]

# Dal / atlama mnemonikleri - hedefi disassembly satirindan okunur
DAL_MNEMONIK = re.compile(
    r"^\s*(c\.)?(beq|bne|blt|bge|bltu|bgeu|beqz|bnez|blez|bgez|bltz|bgtz|"
    r"j|jal|jr|jalr|ret|mret|ecall|ebreak|call|tail)\b"
)
SATIR = re.compile(r"^\s*([0-9a-f]+):\s+([0-9a-f]+)\s+(.*)$")
HEDEF = re.compile(r"\b([0-9a-f]+)\s*<[^>]*>\s*$")


def objdump_bul():
    for aday in OBJDUMP_ADAYLARI:
        if os.path.exists(aday):
            return aday
        try:
            subprocess.run([aday, "--version"], capture_output=True, check=True)
            return aday
        except (OSError, subprocess.CalledProcessError):
            continue
    return None


def program_coz(elf_yolu):
    """ELF'i disassemble edip {adres: (uzunluk, mnemonik, hedef)} dondurur."""
    od = objdump_bul()
    if od is None:
        print("HATA: riscv objdump bulunamadi. Aranan yerler:")
        for a in OBJDUMP_ADAYLARI:
            print("  - %s" % a)
        return None

    ciktı = subprocess.run([od, "-d", elf_yolu],
                           capture_output=True, text=True).stdout

    program = {}
    for satir in ciktı.splitlines():
        m = SATIR.match(satir)
        if not m:
            continue
        adres = int(m.group(1), 16)
        # Kodlama alanindaki hex basamak sayisi buyruk uzunlugunu verir:
        # 4 basamak = 2 bayt (sikistirilmis), 8 basamak = 4 bayt
        uzunluk = len(m.group(2)) // 2
        govde = m.group(3).strip()
        mnemonik = govde.split()[0] if govde else ""

        hedef = None
        if DAL_MNEMONIK.match(govde):
            h = HEDEF.search(govde)
            if h:
                hedef = int(h.group(1), 16)
        program[adres] = (uzunluk, mnemonik, hedef)
    return program


def pc_dizisi_oku(log_yolu):
    kalip = re.compile(r"PC_ID=(0x[0-9a-fA-F]+)")
    pcler = []
    with open(log_yolu, "r", errors="replace") as f:
        for satir in f:
            m = kalip.search(satir)
            if m:
                pcler.append(int(m.group(1), 16))
    # Ardisik tekrarlari sik - CPU duraklarken ayni PC birden cok
    # cevrim boyunca ID asamasinda kalir; bu bir buyruk gecisi degildir.
    sikistirilmis = []
    for pc in pcler:
        if not sikistirilmis or sikistirilmis[-1] != pc:
            sikistirilmis.append(pc)
    return sikistirilmis


def main():
    kok = os.path.dirname(os.path.abspath(__file__))
    proje = os.path.dirname(os.path.dirname(kok))

    elf = os.environ.get("TRACE_ELF",
                         os.path.join(proje, "sw_nexys", "build",
                                      "bootloader", "bootloader.elf"))
    log = os.environ.get("TRACE_LOG", os.path.join(kok, "simulation.log"))
    if not os.path.exists(log):
        log = os.path.join(proje, "simulation.log")

    print("=" * 72)
    print(" CV32E40P BUYRUK IZI DENETIMI")
    print(" Referans: derlenmis programin disassembly ciktisi")
    print("=" * 72)
    print("ELF : %s" % elf)
    print("LOG : %s" % log)
    print()

    if not os.path.exists(elf):
        print("HATA: ELF bulunamadi: %s" % elf)
        return 2
    if not os.path.exists(log):
        print("HATA: simulation.log bulunamadi.")
        print("      Simulasyonu TRACE_ON tanimliyla kosun:")
        print("      Vivado > Simulation Settings > Verilog Defines > TRACE_ON")
        return 2

    program = program_coz(elf)
    if program is None:
        return 2
    print("Programda %d buyruk cozuldu." % len(program))

    pcler = pc_dizisi_oku(log)
    print("Izde %d benzersiz PC gecisi bulundu.\n" % len(pcler))
    if not pcler:
        print("HATA: Logda PC_ID kaydi yok. TRACE_ON tanimli miydi?")
        return 2

    gecersiz_adres = []
    gecersiz_gecis = []
    dal_sayisi = 0
    sirali_sayisi = 0

    for i, pc in enumerate(pcler):
        if pc not in program:
            gecersiz_adres.append((i, pc))
            continue
        if i + 1 >= len(pcler):
            break

        uzunluk, mnemonik, hedef = program[pc]
        sonraki = pcler[i + 1]

        if sonraki == pc + uzunluk:
            sirali_sayisi += 1
        elif hedef is not None and sonraki == hedef:
            dal_sayisi += 1
        elif mnemonik.endswith(("jr", "jalr", "ret", "mret")):
            # Hedef yazmactan gelir, disassembly'den bilinemez.
            # PC'nin gecerli bir buyruk olmasi denetimi yeterlidir.
            dal_sayisi += 1
        else:
            gecersiz_gecis.append((i, pc, sonraki, mnemonik))

    print("Sirali gecis     : %d" % sirali_sayisi)
    print("Dal / atlama     : %d" % dal_sayisi)
    print("Gecersiz adres   : %d" % len(gecersiz_adres))
    print("Gecersiz gecis   : %d" % len(gecersiz_gecis))
    print()

    for i, pc in gecersiz_adres[:10]:
        print("  [%d] PC=0x%08x programda yok" % (i, pc))
    for i, pc, sonraki, mn in gecersiz_gecis[:10]:
        print("  [%d] 0x%08x (%s) -> 0x%08x  beklenmeyen gecis"
              % (i, pc, mn, sonraki))

    hata = len(gecersiz_adres) + len(gecersiz_gecis)
    print("-" * 72)
    if hata == 0:
        print("[BASARILI] Yurutulen butun PC'ler derlenmis programla tutarli.")
        return 0
    print("[HATA] %d tutarsizlik." % hata)
    return 1


if __name__ == "__main__":
    sys.exit(main())
