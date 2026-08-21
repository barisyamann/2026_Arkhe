#!/usr/bin/env python3
# =============================================================================
#  gen_rom_paketleri.py - ROM tablolarini SystemVerilog paketine gomer
#
#  NEDEN
#    RTL'de tablolar $readmemh ile dosyadan okunuyordu:
#
#        $readmemh("boot.hex", rom_mem);
#        $readmemh("fc_weights.mem", fc_weights);
#
#    Dosya adlari CIPLAK - yol yok. $readmemh dosyayi CALISMA DIZININE gore
#    arar. Vivado projeye eklenmis dosyayi cozer ve bulur; LibreLane ise her
#    adimi kendi dizininde kosturur (asic/run/arkhe/06-yosys-synthesis/) ve
#    oradan dosya gorunmez.
#
#    Sonuc: ASIC sentezinde ALTI tablonun hepsi tanimsiz (X) kaldi ve Yosys
#    onlari sildi:
#
#        soc_top.u_boot_rom.rom_mem: removing const-x lane 0..31
#
#    Uretilecek cip acilmaz, NPU cop hesaplardi. Hata verilmedi - sessiz.
#
#  COZUM
#    Degerleri dogrudan RTL'e gomek. Dosya bagimliligi tamamen kalkar;
#    hangi aracta kosarsan kos ayni sonucu verir.
#
#  DOGRULAMA
#    Bu betik uretim yaptiktan sonra urettigi dosyayi GERI OKUR ve kaynak
#    .mem dosyasiyla deger deger karsilastirir. Tek bit kaymasi bile
#    yakalanir - cunku boyle bir kayma NPU'yu sessizce yanlis siniflandirir
#    ve ancak donanimda fark edilirdi.
#
#  KULLANIM
#      python scripts/gen_rom_paketleri.py            uret + dogrula
#      python scripts/gen_rom_paketleri.py --denetle  yalnizca dogrula
#                                                     (uretilmis dosya guncel mi)
# =============================================================================

import io
import os
import re
import sys

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (paket_adi, cikti_yolu, [(sabit_adi, kaynak_dosya, adet, bit, isaretli), ...])
PAKETLER = [
    (
        "boot_rom_pkg",
        "rtl/boot/boot_rom_pkg.sv",
        u"Boot ROM icerigi - bootloader makine kodu (sw_nexys/src/bootloader.S)",
        [("BOOT_ROM_ICERIK", "rtl/boot/boot.hex", 256, 32, False)],
    ),
    (
        "npu_weights_pkg",
        "rtl/npu/npu_weights_pkg.sv",
        u"NPU egitilmis agirliklari, sapmalari ve softmax bakis tablosu",
        [
            ("DW_WEIGHTS",      "weights/dw_weights.mem",      640,    8, True),
            ("DW_BIAS",         "weights/dw_bias.mem",           8,   32, True),
            ("FC_WEIGHTS",      "weights/fc_weights.mem",    16000,    8, True),
            ("FC_BIAS",         "weights/fc_bias.mem",           4,   32, True),
            ("SOFTMAX_EXP_LUT", "weights/softmax_exp_lut.mem", 256,   13, False),
        ],
    ),
]

SATIR_BASINA = 8


def kaynak_oku(bagil_yol, adet, bit):
    """Bir .mem/.hex dosyasini okur, deger listesi dondurur."""
    yol = os.path.join(KOK, bagil_yol)
    if not os.path.isfile(yol):
        raise SystemExit("HATA: kaynak dosya yok: %s" % bagil_yol)

    degerler = []
    with io.open(yol, encoding="utf-8", errors="replace") as f:
        for satir_no, satir in enumerate(f, 1):
            # Yorumlari ve bos satirlari at
            s = satir.split("//")[0].split("#")[0].strip()
            if not s:
                continue
            for parca in s.split():
                try:
                    v = int(parca, 16)
                except ValueError:
                    raise SystemExit("HATA: %s:%d gecersiz hex: %r"
                                     % (bagil_yol, satir_no, parca))
                if v >= (1 << bit):
                    raise SystemExit("HATA: %s:%d deger %d bite sigmiyor: %s"
                                     % (bagil_yol, satir_no, bit, parca))
                degerler.append(v)

    if len(degerler) != adet:
        raise SystemExit("HATA: %s -> %d deger bekleniyordu, %d bulundu"
                         % (bagil_yol, adet, len(degerler)))
    return degerler


def paket_uret(paket_adi, aciklama, tablolar):
    basamak = {}
    govde = []

    govde.append(u"// " + u"=" * 75)
    govde.append(u"//  %s.sv" % paket_adi)
    govde.append(u"//  %s" % aciklama)
    govde.append(u"//")
    govde.append(u"//  BU DOSYA URETILMISTIR - ELLE DUZENLEMEYIN.")
    govde.append(u"//")
    govde.append(u"//      python scripts/gen_rom_paketleri.py")
    govde.append(u"//")
    govde.append(u"//  Kaynak dosyalar degisirse betigi tekrar kosturun.")
    govde.append(u"//  Tutarliligi denetlemek icin:")
    govde.append(u"//      python scripts/gen_rom_paketleri.py --denetle")
    govde.append(u"//")
    govde.append(u"//  NEDEN GOMULU")
    govde.append(u"//    Onceden $readmemh ile dosyadan okunuyordu. Dosya adlari")
    govde.append(u"//    ciplakti ve $readmemh calisma dizinine gore arar; LibreLane")
    govde.append(u"//    her adimi kendi dizininde kosturdugu icin dosyalar")
    govde.append(u"//    bulunamiyordu. Tablolar tanimsiz kaliyor, Yosys de onlari")
    govde.append(u"//    siliyordu - sessizce. Uretilecek cip acilmazdi.")
    govde.append(u"// " + u"=" * 75)
    govde.append(u"")
    govde.append(u"package %s;" % paket_adi)
    govde.append(u"")

    for ad, kaynak, adet, bit, isaretli in tablolar:
        degerler = kaynak_oku(kaynak, adet, bit)
        basamak[ad] = degerler

        tip = u"logic signed [%d:0]" % (bit - 1) if isaretli \
            else u"logic [%d:0]" % (bit - 1)
        genislik = (bit + 3) // 4

        govde.append(u"    // %s" % kaynak)
        govde.append(u"    //   %d giris x %d bit = %d bit%s"
                     % (adet, bit, adet * bit,
                        u" (isaretli)" if isaretli else u""))
        govde.append(u"    localparam %s %s [0:%d] = '{" % (tip, ad, adet - 1))

        for i in range(0, adet, SATIR_BASINA):
            dilim = degerler[i:i + SATIR_BASINA]
            metin = u", ".join(u"%d'h%0*x" % (bit, genislik, v) for v in dilim)
            son = u"" if i + SATIR_BASINA >= adet else u","
            govde.append(u"        %s%s" % (metin, son))

        govde.append(u"    };")
        govde.append(u"")

    govde.append(u"endpackage")
    govde.append(u"")
    return u"\n".join(govde), basamak


DESEN = re.compile(r"(\d+)'h([0-9a-fA-F]+)")


def uretilen_oku(metin, ad, adet):
    """Uretilen paketten bir sabitin degerlerini geri okur."""
    bas = metin.find(u" %s [0:" % ad)
    if bas < 0:
        return None
    bas = metin.index(u"'{", bas)
    son = metin.index(u"};", bas)
    return [int(m.group(2), 16) for m in DESEN.finditer(metin[bas:son])]


def main():
    yalniz_denetle = "--denetle" in sys.argv
    hata = 0
    toplam_bit = 0

    print(u"=" * 70)
    print(u" ROM TABLOLARI -> SystemVerilog paketi")
    print(u"=" * 70)

    for paket_adi, cikti, aciklama, tablolar in PAKETLER:
        metin, kaynak_degerler = paket_uret(paket_adi, aciklama, tablolar)
        yol = os.path.join(KOK, cikti)

        if yalniz_denetle:
            if not os.path.isfile(yol):
                print(u"[HATA] %s yok - once uretin" % cikti)
                hata += 1
                continue
            mevcut = io.open(yol, encoding="utf-8").read()
            if mevcut.replace("\r\n", "\n") != metin:
                print(u"[HATA] %s guncel degil - kaynak dosyalar degismis" % cikti)
                hata += 1
                continue
            print(u"[OK]   %s guncel" % cikti)
        else:
            io.open(yol, "w", encoding="utf-8", newline="\n").write(metin)
            print(u"\n%s -> %s" % (paket_adi, cikti))

        # --- DOGRULAMA: uretileni geri oku, kaynakla karsilastir -------------
        geri = io.open(yol, encoding="utf-8").read()
        for ad, kaynak, adet, bit, _ in tablolar:
            beklenen = kaynak_degerler[ad]
            okunan = uretilen_oku(geri, ad, adet)
            toplam_bit += adet * bit

            if okunan is None:
                print(u"  [HATA] %-16s uretilen dosyada bulunamadi" % ad)
                hata += 1
                continue
            if len(okunan) != adet:
                print(u"  [HATA] %-16s %d deger bekleniyordu, %d okundu"
                      % (ad, adet, len(okunan)))
                hata += 1
                continue

            fark = [(i, a, b) for i, (a, b) in enumerate(zip(beklenen, okunan))
                    if a != b]
            if fark:
                print(u"  [HATA] %-16s %d deger uyusmuyor" % (ad, len(fark)))
                for i, a, b in fark[:5]:
                    print(u"           [%d] kaynak=%x uretilen=%x" % (i, a, b))
                hata += 1
                continue

            print(u"  [OK]   %-16s %6d deger x %2d bit  (%s)"
                  % (ad, adet, bit, kaynak))

    print(u"\n" + u"-" * 70)
    print(u"Toplam gomulen: %d bit = %.1f kbit = %.1f kB"
          % (toplam_bit, toplam_bit / 1024.0, toplam_bit / 8192.0))

    if hata:
        print(u"[BASARISIZ] %d sorun" % hata)
        return 1
    print(u"[BASARILI] butun tablolar kaynak dosyalarla birebir ayni.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
