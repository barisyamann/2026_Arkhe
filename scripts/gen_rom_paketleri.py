#!/usr/bin/env python3
# =============================================================================
#  gen_rom_paketleri.py - ROM tablolarini SystemVerilog paketine gomer
#
#  NEDEN GOMULU
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
# -----------------------------------------------------------------------------
#  NEDEN "PARCALI PACKED VEKTOR + ERISIM FONKSIYONU"
#
#    Ilk surum tablolari UNPACKED localparam dizisi olarak uretiyordu:
#
#        localparam logic signed [7:0] FC_WEIGHTS [0:15999] = '{...};
#
#    Verilator (0,4 sn) ve Yosys (20 dk, tam akis) bunu sorunsuz sindirdi.
#    VIVADO SINDIREMEDI: xelab tek bir modulde 82 DAKIKA kosup bitiremedi.
#
#    Sebep: unpacked dizi elaboratore gore 16.000 AYRI NESNEDIR. Vivado her
#    biri icin sembol tablosu girisi ve tip analizi yapar. Verilator ve Yosys
#    ic temsilde hemen duzlestirdigi icin etkilenmez.
#
#    Packed vektor tek nesnedir; dilimleme (W[i*8 +: 8]) sentezde adres
#    cozucuye doner. Olculdu:
#
#        bicim                     Vivado xelab
#        unpacked localparam dizi  240 sn'de BITMEDI
#        packed vektor + fonksiyon 2,5 SANIYE
#
#    PARCALAMA neden gerekli: Verilator sayi sabitlerinde 65.536 BIT sinirina
#    sahiptir. Olculdu:
#
#        65.536 bit  -> tamam
#        98.304 bit  -> "Width of number exceeds implementation limit"
#
#    fc_weights 128.000 bit oldugu icin tablolar parcalara bolunur; erisim
#    fonksiyonu ust adres bitleriyle dogru parcayi secer.
#
#    DERS: bir tasarim karari, o kararin kosacagi BUTUN araclarda
#    dogrulanmalidir. Hizli olan aracta gecmesi hicbir sey kanitlamaz.
#
# -----------------------------------------------------------------------------
#  DOGRULAMA
#    Bu betik uretim yaptiktan sonra urettigi dosyayi GERI OKUR ve kaynak
#    .mem dosyasiyla deger deger karsilastirir. Tek bit kaymasi bile
#    yakalanir - cunku boyle bir kayma NPU'yu sessizce yanlis siniflandirir
#    ve ancak donanimda fark edilirdi.
#
#  KULLANIM
#      python scripts/gen_rom_paketleri.py            uret + dogrula
#      python scripts/gen_rom_paketleri.py --denetle  yalnizca dogrula
# =============================================================================

import io
import os
import re
import sys

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (paket_adi, cikti_yolu, aciklama,
#  [(erisim_fonksiyonu_adi, kaynak_dosya, adet, bit, isaretli), ...])
PAKETLER = [
    (
        "boot_rom_pkg",
        "rtl/boot/boot_rom_pkg.sv",
        u"Boot ROM icerigi - bootloader makine kodu (sw_nexys/src/bootloader.S)",
        [("boot_rom_icerik", "rtl/boot/boot.hex", 256, 32, False)],
    ),
    (
        "npu_weights_pkg",
        "rtl/npu/npu_weights_pkg.sv",
        u"NPU egitilmis agirliklari, sapmalari ve softmax bakis tablosu",
        [
            ("dw_weights",      "weights/dw_weights.mem",      640,    8, True),
            ("dw_bias",         "weights/dw_bias.mem",           8,   32, True),
            ("fc_weights",      "weights/fc_weights.mem",    16000,    8, True),
            ("fc_bias",         "weights/fc_bias.mem",           4,   32, True),
            ("softmax_exp_lut", "weights/softmax_exp_lut.mem", 256,   13, False),
        ],
    ),
]

# Verilator sayi sabiti siniri 65.536 bit; guvenli pay birakiyoruz.
PARCA_TAVAN_BIT = 32768


def adres_biti(adet):
    """adet degeri icin gereken adres bit sayisi."""
    n = 1
    while (1 << n) < adet:
        n += 1
    return n


def parca_boyu(bit):
    """Parca basina giris sayisi - tavani asmayan en buyuk ikinin kuvveti."""
    n = 1
    while n * 2 * bit <= PARCA_TAVAN_BIT:
        n *= 2
    return n


def kaynak_oku(bagil_yol, adet, bit):
    """Bir .mem/.hex dosyasini okur, deger listesi dondurur."""
    yol = os.path.join(KOK, bagil_yol)
    if not os.path.isfile(yol):
        raise SystemExit("HATA: kaynak dosya yok: %s" % bagil_yol)

    degerler = []
    with io.open(yol, encoding="utf-8", errors="replace") as f:
        for satir_no, satir in enumerate(f, 1):
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


def duz_hex(degerler, bit):
    """Degerleri tek tamsayiya paketler; indeks 0 EN DUSUK bitlerde."""
    n = 0
    for k, v in enumerate(degerler):
        n |= v << (k * bit)
    genislik = (len(degerler) * bit + 3) // 4
    return "%0*x" % (genislik, n)


def sabit_adi(ad, parca_sayisi, c):
    if parca_sayisi == 1:
        return "%s_DUZ" % ad.upper()
    return "%s_DUZ%d" % (ad.upper(), c)


def paket_uret(paket_adi, aciklama, tablolar):
    kaynak_degerler = {}
    g = []

    g.append(u"// " + u"=" * 74)
    g.append(u"//  %s.sv" % paket_adi)
    g.append(u"//  %s" % aciklama)
    g.append(u"//")
    g.append(u"//  BU DOSYA URETILMISTIR - ELLE DUZENLEMEYIN.")
    g.append(u"//      python scripts/gen_rom_paketleri.py")
    g.append(u"//  Tutarlilik denetimi:")
    g.append(u"//      python scripts/gen_rom_paketleri.py --denetle")
    g.append(u"//")
    g.append(u"//  BICIM: parcali packed vektor + erisim fonksiyonu")
    g.append(u"//    UNPACKED localparam dizisi denendi; Vivado xelab tek")
    g.append(u"//    modulde 82 dakikada bitiremedi. Packed bicim ayni isi")
    g.append(u"//    2,5 saniyede yapiyor.")
    g.append(u"//")
    g.append(u"//    Parcalama gerekli: Verilator sayi sabitlerinde 65.536 bit")
    g.append(u"//    sinirina sahip. Parca basina tavan %d bit."
             % PARCA_TAVAN_BIT)
    g.append(u"//")
    g.append(u"//  Indeks 0 vektorun EN DUSUK bitlerindedir.")
    g.append(u"// " + u"=" * 74)
    g.append(u"")
    g.append(u"package %s;" % paket_adi)
    g.append(u"")

    for ad, kaynak, adet, bit, isaretli in tablolar:
        degerler = kaynak_oku(kaynak, adet, bit)
        kaynak_degerler[ad] = degerler

        pb = parca_boyu(bit)
        parca_sayisi = (adet + pb - 1) // pb
        aw = adres_biti(adet)
        pw = adres_biti(pb)
        if isaretli:
            tip = u"logic signed [%d:0]" % (bit - 1)
        else:
            tip = u"logic [%d:0]" % (bit - 1)

        g.append(u"    // %s" % kaynak)
        g.append(u"    //   %d giris x %d bit = %d bit%s"
                 % (adet, bit, adet * bit,
                    u" (isaretli)" if isaretli else u""))
        if parca_sayisi > 1:
            g.append(u"    //   %d parca x %d giris" % (parca_sayisi, pb))

        for c in range(parca_sayisi):
            dilim = degerler[c * pb:(c + 1) * pb]
            genislik = len(dilim) * bit
            g.append(u"    localparam logic [%d:0] %s = %d'h%s;"
                     % (genislik - 1, sabit_adi(ad, parca_sayisi, c),
                        genislik, duz_hex(dilim, bit)))
        g.append(u"")

        g.append(u"    function automatic %s %s(input logic [%d:0] i);"
                 % (tip, ad, aw - 1))
        if parca_sayisi == 1:
            g.append(u"        return %s_DUZ[i * %d +: %d];"
                     % (ad.upper(), bit, bit))
        else:
            g.append(u"        logic [%d:0] o;" % (pw - 1))
            g.append(u"        o = i[%d:0];" % (pw - 1))
            g.append(u"        case (i[%d:%d])" % (aw - 1, pw))
            for c in range(parca_sayisi):
                if c == parca_sayisi - 1:
                    etiket = u"default"
                else:
                    etiket = u"%d'd%d" % (aw - pw, c)
                g.append(u"            %s: return %s[o * %d +: %d];"
                         % (etiket, sabit_adi(ad, parca_sayisi, c), bit, bit))
            g.append(u"        endcase")
        g.append(u"    endfunction")
        g.append(u"")

    g.append(u"endpackage")
    g.append(u"")
    return u"\n".join(g), kaynak_degerler


def uretilen_oku(metin, ad, adet, bit):
    """Uretilen paketten bir tablonun degerlerini geri okur (parcali)."""
    pb = parca_boyu(bit)
    parca_sayisi = (adet + pb - 1) // pb
    cikan = []
    maske = (1 << bit) - 1

    for c in range(parca_sayisi):
        dilim_adet = min(pb, adet - c * pb)
        genislik = dilim_adet * bit
        desen = (r"localparam logic \[%d:0\] %s = %d'h([0-9a-f]+);"
                 % (genislik - 1, sabit_adi(ad, parca_sayisi, c), genislik))
        m = re.search(desen, metin)
        if not m:
            return None
        n = int(m.group(1), 16)
        cikan += [(n >> (k * bit)) & maske for k in range(dilim_adet)]

    return cikan


def main():
    yalniz_denetle = "--denetle" in sys.argv
    hata = 0
    toplam_bit = 0

    print(u"=" * 70)
    print(u" ROM TABLOLARI -> SystemVerilog paketi (parcali packed vektor)")
    print(u"=" * 70)

    for paket_adi, cikti, aciklama, tablolar in PAKETLER:
        metin, kaynak_degerler = paket_uret(paket_adi, aciklama, tablolar)
        yol = os.path.join(KOK, cikti)

        if yalniz_denetle:
            if not os.path.isfile(yol):
                print(u"[HATA] %s yok - once uretin" % cikti)
                hata += 1
                continue
            mevcut = io.open(yol, encoding="utf-8").read().replace("\r\n", "\n")
            if mevcut != metin:
                print(u"[HATA] %s guncel degil - kaynak dosyalar degismis"
                      % cikti)
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
            okunan = uretilen_oku(geri, ad, adet, bit)
            toplam_bit += adet * bit

            if okunan is None:
                print(u"  [HATA] %-16s uretilen dosyada bulunamadi" % ad)
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

            pb = parca_boyu(bit)
            ps = (adet + pb - 1) // pb
            ek = (u"  %d parca" % ps) if ps > 1 else u""
            print(u"  [OK]   %-16s %6d deger x %2d bit%s  (%s)"
                  % (ad, adet, bit, ek, kaynak))

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
