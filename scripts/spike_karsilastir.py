#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Spike ISS izi ile CV32E40P RTL izini karsilastirir.

NEDEN

  Sartname s.569:
    "CV32E40P RISC-V islemci cekirdeginin dogrulanmasinin bir buyruk kumesi
     benzetim araci (ISS) ile (Orn. Spike ISS) yapilmasi beklenmektedir."

  EK-3 "Cekirdek Testleri":
    "...komut izlerinin (instruction trace) TUR ve SIRA bakimindan eslesip
     eslesmedigini gormek adina Spike ISS ve yazilim testleri (C/assembly)
     kullanilarak yapilan CV32E40P cekirdeginin BIREYSEL testleri.
     Bu testler kendi kendini kontrol eden (self-checking) yapida olmali..."

  DTR'de "ilk 20 buyruk Spike ile 20/20 eslesti, %100 uyum" yaziyordu.
  Gercek Spike hic kosulmamisti; eski karsilastirma elle yazilmis bir PC
  listesine dayaniyordu. Bu betik o iddiayi gercek olcumle degistirir.

KARSILASTIRMA NEYI DENETLER

  1) TUR ve SIRA: Her retire edilen buyrugun PC'si ve makine kodu, IKI
     izde de AYNI SIRADA olmalidir.

  2) SONUC (12 Eylul 2026'da eklendi): Her buyrugun YAZDIGI yazmac
     numarasi ve DEGERI de karsilastirilir. Spike --log-commits ile
     commit satirlari uretir; CV32E40P tracer'i ayni bilgiyi "x2=deger"
     bicimiyle verir.

     NEDEN GEREKLI: Yalniz PC/kod karsilastirmasi cekirdegin dogru
     buyruklari dogru sirayla kostugunu gosterir ama SONUCLARI dogru
     hesaplayip hesaplamadigini GOSTERMEZ. ALU'da add yerine sub
     baglansaydi PC akisi ayni kalacagi icin eski karsilastirma
     GECERDI.

     Platform kimlik CSR'lari (mvendorid, marchid, mimpid, mhartid,
     misa) haric tutulur - bunlar cekirdek kimligidir, hesaplama
     hatasi degil. Ayri sayilir ve raporlanir, gizlenmez.

BASLANGIC NOKTASI FARKI

  Spike reset vektorunden (0x1000) baslar ve kendi onyukleyicisini kosar.
  RTL izi ise cekirdegin ilk retire ettigi buyruktan baslar; bizim
  testbench'imiz boot_addr_i'yi 0x01000000'a zorlar.

  Bu yuzden karsilastirma UYGULAMANIN GIRIS NOKTASINDAN (0x01000000)
  baslatilir; oncesi platform farkidir, cekirdek dogrulugu degildir.

KULLANIM

  python3 scripts/spike_iz_al.py                     # Spike izi
  (RTL izi: build/coretest/trace_core_00000000.log)
  python3 scripts/spike_karsilastir.py
"""
import argparse
import re
import sys
from pathlib import Path

KOK = Path(__file__).resolve().parents[1]

BASLANGIC_PC = "01000000"   # uygulamanin giris noktasi (_start)

# RTL tracer satiri:
#   260000   5 01000000 1f002117   auipc  x2, ...
RTL_SATIR = re.compile(r"^\s*\d+\s+\d+\s+([0-9a-f]{8})\s+([0-9a-f]{4,8})\s")

# 12 Eylul 2026: YAZMAC DUZEYI KARSILASTIRMA
#
# CV32E40P tracer'i buyrugun YAZDIGI yazmaci satir sonunda "x2=20002000"
# bicimiyle raporlar. Okunan yazmaclar "x2:20002000" (iki nokta) ile
# ayrilir - YAZILAN degeri aldigimiz icin yalniz '=' esleniyor.
#
# NEDEN GEREKLI
#   Onceki surum yalniz PC ve makine kodunu karsilastiriyordu. Yani
#   cekirdegin dogru SIRAYLA dogru BUYRUKLARI kostugu dogrulaniyor ama
#   SONUCLARI dogru hesaplayip hesaplamadigi DOGRULANMIYORDU.
#   Ornegin ALU'da add yerine sub baglansaydi, PC akisi ayni kalacagi
#   icin karsilastirma GECERDI.
RTL_YAZMAC = re.compile(r"\bx\s*(\d+)=([0-9a-fA-F]+)")


def spike_oku(yol):
    """Spike izini okur.

    Bicim (spike_iz_al.py ciktisi):
        "PC BUYRUK"              -> yazmaca yazmayan buyruk
        "PC BUYRUK xN DEGER"     -> yazmac yazmasi olan buyruk
    """
    iz = []
    with open(yol, encoding="ascii", errors="replace") as fh:
        for s in fh:
            p = s.split()
            if len(p) == 2:
                iz.append((p[0], p[1].lstrip("0") or "0", None, None))
            elif len(p) == 4 and p[2].startswith("x"):
                iz.append((p[0], p[1].lstrip("0") or "0",
                           p[2][1:], p[3].lstrip("0") or "0"))
    return iz


def rtl_oku(yol):
    """RTL tracer izini okur; yazilan yazmac degerini de cikarir."""
    iz = []
    with open(yol, encoding="utf-8", errors="replace") as fh:
        for s in fh:
            m = RTL_SATIR.match(s)
            if not m:
                continue
            # Satirin buyruk alanindan SONRASINDA yazmac yazmasi aranir.
            kuyruk = s[m.end():]
            my = RTL_YAZMAC.search(kuyruk)
            if my:
                iz.append((m.group(1), m.group(2).lstrip("0") or "0",
                           my.group(1), my.group(2).lstrip("0").lower() or "0"))
            else:
                iz.append((m.group(1), m.group(2).lstrip("0") or "0",
                           None, None))
    return iz


def hizala(iz, pc):
    """Verilen PC'nin ilk gorulusunden itibaren kes."""
    for i, kayit in enumerate(iz):
        if kayit[0] == pc:
            return iz[i:]
    return []


def donguyu_kes(iz, esik=20):
    """Sonsuz donguye girildigi yerde izi keser.

    crt0 programin sonunda kendine dallanan bir dongude bekler. Simulasyon
    sabit bir sure kostugu icin RTL izi bu donguyu yuzlerce kez icerir;
    Spike izi de oyle. Karsilastirmadan once ikisi de kesilir.
    """
    son = None
    tekrar = 0
    for i, kayit in enumerate(iz):
        p = kayit[0]
        if p == son:
            tekrar += 1
            if tekrar >= esik:
                # Dongu PC'sinin ILK gorulusune kadar geri sar
                j = i
                while j > 0 and iz[j - 1][0] == p:
                    j -= 1
                return iz[:j + 1]
        else:
            tekrar = 0
            son = p
    return iz


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spike", default=str(KOK / "build/spike/spike_iz.txt"))
    # 4 Eylul 2026: varsayilan yol DUZELTILDI. Onceden
    # "build/coretest/trace_core_00000000.log" yaziyordu; o dizin elle
    # kosulan eski bir xsim denemesinden kalmaydi. Regresyon izi
    # build/regression/<test adi>/ altina yazar, dolayisiyla belgedeki
    # yeniden uretim adimlari (run_regression --test cekirdek_izi ->
    # spike_karsilastir) "iz bulunamadi" ile kesiliyordu.
    ap.add_argument("--rtl",
                    default=str(KOK / "build/regression/cekirdek_izi"
                                      "/trace_core_00000000.log"))
    ap.add_argument("--baslangic", default=BASLANGIC_PC)
    # --- 13 Eylul 2026: dis inceleme bulgusu ---
    # Once uzunluk farki ve tek tarafli yazmac bilgisi HATA SAYILMIYORDU:
    # Spike 927, RTL 800 buyruk olsa bile ilk 800 uyusuyorsa betik PASS
    # donuyordu. Self-checking dogrulama icin fazla gevsek.
    #
    # Artik ikisi de hata sayilir. Mesru bir fark varsa ACIKCA beyan
    # edilir; sessizce gecistirilmez.
    ap.add_argument("--izin-uzunluk-farki", type=int, default=0,
                    metavar="N",
                    help="Hizalama sonrasi izin verilen buyruk sayisi farki "
                         "(varsayilan 0 - fark HATADIR)")
    ap.add_argument("--izin-tek-tarafli", type=int, default=0,
                    metavar="N",
                    help="Izin verilen tek tarafli yazmac bilgisi sayisi "
                         "(varsayilan 0 - HATADIR)")
    a = ap.parse_args()

    for yol in (a.spike, a.rtl):
        if not Path(yol).is_file():
            sys.exit("iz bulunamadi: %s" % yol)

    ham_s = spike_oku(a.spike)
    ham_r = rtl_oku(a.rtl)
    print("Spike ham buyruk : %d" % len(ham_s))
    print("RTL   ham buyruk : %d" % len(ham_r))

    s = donguyu_kes(hizala(ham_s, a.baslangic))
    r = donguyu_kes(hizala(ham_r, a.baslangic))
    print("hizalama PC      : 0x%s" % a.baslangic)
    print("Spike (hizali)   : %d" % len(s))
    print("RTL   (hizali)   : %d" % len(r))
    print()

    if not s or not r:
        sys.exit("HATA: hizalama PC'si izlerden birinde bulunamadi")

    n = min(len(s), len(r))
    pc_hata = 0
    kod_hata = 0
    sikistirilmis = 0
    # --- 12 Eylul 2026: yazmac duzeyi sayaclar ---
    yazmac_karsilastirilan = 0   # iki izde de yazmac bilgisi olan buyruk
    yazmac_no_hata = 0           # farkli yazmac numarasi yazilmis
    yazmac_deger_hata = 0        # ayni yazmac, FARKLI deger
    yazmac_tek_tarafli = 0       # yalniz bir izde yazmac bilgisi var
    kimlik_csr_farki = []        # platform kimlik CSR'lari (hata degil)
    ilk_hatalar = []
    for i in range(n):
        spc, sk, syz, sdg = s[i]
        rpc, rk, ryz, rdg = r[i]

        if spc != rpc:
            pc_hata += 1
            if len(ilk_hatalar) < 10:
                ilk_hatalar.append(
                    "  #%-5d PC FARKLI  Spike %s   RTL %s" % (i, spc, rpc))
            continue

        # SIKISTIRILMIS BUYRUK FARKI - BEKLENEN DAVRANIS
        #
        # Spike ham 16-bit sikistirilmis kodu raporlar (orn. 4601).
        # CV32E40P tracer'i ise ACILMIS 32-bit karsiligini yazar (00000613).
        # Ayni buyruk, farkli gosterim.
        #
        # TESPIT: RISC-V'de bir buyruk 32-bit ise alt iki biti '11'dir.
        # Alt iki bit '11' DEGILSE buyruk sikistirilmistir. Bu, kodlamanin
        # kendi kurali - uzunluga bakmaktan guvenilir.
        #
        # (Ilk yazimda uzunluk karsilastirmasi kullaniliyordu; acilmis
        #  bicimin bastaki sifirlari kirpildigi icin 00000613 -> "613"
        #  olup sikistirilmis "4601"den KISA gorunuyordu ve 5 buyruk
        #  yanlislikla uyusmazlik sayiliyordu.)
        if (int(sk, 16) & 3) != 3:
            sikistirilmis += 1
            continue

        if sk != rk:
            kod_hata += 1
            if len(ilk_hatalar) < 10:
                ilk_hatalar.append(
                    "  #%-5d KOD FARKLI PC=%s  Spike %-8s RTL %-8s"
                    % (i, spc, sk, rk))

    # -------------------------------------------------------------------
    # YAZMAC DUZEYI KARSILASTIRMA  (12 Eylul 2026)
    #
    # PC/kod karsilastirmasi cekirdegin dogru BUYRUKLARI dogru SIRAYLA
    # kostugunu gosterir. Bu dongu ise SONUCLARIN dogru olup olmadigini
    # denetler: her buyrugun yazdigi yazmac numarasi ve DEGERI.
    #
    # Ayri dongude yapiliyor cunku yukaridaki dongu sikistirilmis
    # buyruklarda 'continue' ile atliyor; yazmac denetimi onlarda da
    # gecerlidir (sikistirilmis buyruk da yazmaca yazar).
    #
    # PLATFORM KIMLIK CSR'LARI HARIC TUTULUR
    #   Ilk kosumda uc uyusmazlik cikti ve incelendi - ucu de CSR okumasi:
    #       0xf11 mvendorid  Spike 0          CV32E40P 0x602
    #       0xf12 marchid    Spike 5          CV32E40P 4
    #       0x301 misa       Spike 0x40141104 CV32E40P 0x40001104
    #   Bunlar CEKIRDEK KIMLIGIDIR, hesaplama hatasi degil. Spike genel
    #   bir RISC-V modeli; CV32E40P OpenHW Group cekirdegi kendi vendor/
    #   arch kimligini raporlar. misa farki da beklenen: Spike rv32imc
    #   ile kosuldu, CV32E40P'nin uzanti bitleri farkli.
    #   Bu CSR'lar AYRI sayilir ve hata sayilmaz - ama GIZLENMEZ.
    # -------------------------------------------------------------------
    KIMLIK_CSR = {
        "f11": "mvendorid", "f12": "marchid", "f13": "mimpid",
        "f14": "mhartid",   "301": "misa",
    }
    # CSR buyrugunun hedef CSR'i makine kodunun ust 12 bitindedir.
    def csr_adi(kod):
        try:
            v = int(kod, 16)
        except ValueError:
            return None
        if (v & 0x7F) != 0x73:        # SYSTEM opcode degil
            return None
        if ((v >> 12) & 0x7) == 0:    # funct3 == 0 -> ecall/ebreak/mret
            return None
        return KIMLIK_CSR.get("%03x" % ((v >> 20) & 0xFFF))

    for i in range(n):
        spc, sk, syz, sdg = s[i]
        rpc, rk, ryz, rdg = r[i]
        if spc != rpc:
            continue                      # PC zaten uyusmuyor, atla
        if syz is None and ryz is None:
            continue                      # ikisi de yazmaca yazmiyor
        if syz is None or ryz is None:
            yazmac_tek_tarafli += 1
            continue
        ad = csr_adi(rk)
        if ad is not None and sdg != rdg:
            kimlik_csr_farki.append((i, spc, ad, sdg, rdg))
            continue
        yazmac_karsilastirilan += 1
        if syz != ryz:
            yazmac_no_hata += 1
            if len(ilk_hatalar) < 20:
                ilk_hatalar.append(
                    "  #%-5d YAZMAC NO FARKLI PC=%s  Spike x%s  RTL x%s"
                    % (i, spc, syz, ryz))
        elif sdg != rdg:
            yazmac_deger_hata += 1
            if len(ilk_hatalar) < 20:
                ilk_hatalar.append(
                    "  #%-5d DEGER FARKLI PC=%s x%-2s  Spike %-8s RTL %-8s"
                    % (i, spc, syz, sdg, rdg))

    # --- 13 Eylul 2026: iki yeni hata kalemi (dis inceleme) ---
    uzunluk_farki = abs(len(s) - len(r))
    uzunluk_hata = max(0, uzunluk_farki - a.izin_uzunluk_farki)
    tek_tarafli_hata = max(0, yazmac_tek_tarafli - a.izin_tek_tarafli)

    hata = (pc_hata + kod_hata + yazmac_no_hata + yazmac_deger_hata
            + uzunluk_hata + tek_tarafli_hata)

    print("=" * 66)
    print("KARSILASTIRMA")
    print("=" * 66)
    print("  karsilastirilan buyruk : %d" % n)
    print("  PC uyusmazligi         : %d" % pc_hata)
    print("  makine kodu uyusmazligi: %d" % kod_hata)
    print("  sikistirilmis (beklenen): %d" % sikistirilmis)
    print("  --- yazmac duzeyi (12 Eylul 2026) ---")
    print("  yazmac karsilastirilan : %d" % yazmac_karsilastirilan)
    print("  yazmac NO uyusmazligi  : %d" % yazmac_no_hata)
    print("  yazmac DEGER uyusmazligi: %d" % yazmac_deger_hata)
    print("  tek tarafli yazmac bilgisi: %d%s" %
          (yazmac_tek_tarafli,
           "  <-- HATA" if tek_tarafli_hata else
           ("  (izinli)" if yazmac_tek_tarafli else "")))
    if kimlik_csr_farki:
        print("  platform kimlik CSR farki : %d (hata DEGIL, asagida listeli)"
              % len(kimlik_csr_farki))
    if len(s) != len(r):
        print("  UZUNLUK FARKI          : Spike %d, RTL %d (fark %d)%s" %
              (len(s), len(r), uzunluk_farki,
               "  <-- HATA" if uzunluk_hata else "  (izinli)"))
        if uzunluk_hata:
            print("  Iki iz ayni sayida buyruk icermiyor. Bu, RTL'in erken")
            print("  durdugunu veya fazladan buyruk yuruttugunu gosterebilir.")
            print("  Mesru bir sebep varsa --izin-uzunluk-farki N ile ACIKCA")
            print("  beyan edin; sessizce gecistirmeyin.")
    print()

    if kimlik_csr_farki:
        print("platform kimlik CSR farklari (HATA DEGIL):")
        for i, pc, ad, sd, rd in kimlik_csr_farki:
            print("  #%-5d PC=%s  %-10s Spike 0x%-9s CV32E40P 0x%s"
                  % (i, pc, ad, sd, rd))
        print("  -> Spike genel bir RISC-V modelidir; CV32E40P OpenHW Group")
        print("     cekirdegi kendi vendor/arch kimligini raporlar. misa")
        print("     farki da beklenen: Spike rv32imc ile kosuldu.")
        print()

    if ilk_hatalar:
        print("ilk uyusmazliklar:")
        for h in ilk_hatalar:
            print(h)
        print()

    if hata == 0:
        print("SONUC: %d buyrukta PC dizisi BIREBIR ESLESTI." % n)
        print("       %d buyrukta YAZMAC DEGERI de birebir eslesti."
              % yazmac_karsilastirilan)
        print("       Spike ISS ile RTL izleri TUR ve SIRA bakimindan ayni.")
        if sikistirilmis:
            print()
            print("       %d buyrukta makine kodu gosterimi farkli: Spike ham" % sikistirilmis)
            print("       16-bit sikistirilmis kodu, CV32E40P tracer'i ise")
            print("       ACILMIS 32-bit karsiligini raporlar. Ayni buyruk,")
            print("       farkli gosterim - PC esitligi dogru cozuldugunu kanitlar.")
        return 0

    print("SONUC: %d/%d buyrukta uyusmazlik var." % (hata, n))
    return 1


if __name__ == "__main__":
    sys.exit(main())
