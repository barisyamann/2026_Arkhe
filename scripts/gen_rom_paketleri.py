#!/usr/bin/env python3
# =============================================================================
#  gen_rom_paketleri.py - ROM tablolarini SystemVerilog paketine gomer
#
#  NEDEN GOMULU
#    RTL'de tablolar $readmemh ile CIPLAK dosya adlarindan okunuyordu.
#    $readmemh dosyayi CALISMA DIZININE gore arar; LibreLane her adimi kendi
#    dizininde kosturdugu icin hicbirini bulamiyordu. Tablolar tanimsiz (X)
#    kaliyor ve Yosys onlari siliyordu - sessizce:
#
#        soc_top.u_boot_rom.rom_mem: removing const-x lane 0..31
#
#    Uretilecek cip acilmaz, NPU cop hesaplardi.
#
# -----------------------------------------------------------------------------
#  BICIM: PACKED VEKTOR + ERISIM FONKSIYONU
#
#    Unpacked localparam dizisi denendi; Verilator (0,4 sn) ve Yosys (20 dk)
#    sindirdi ama VIVADO xelab tek modulde 82 DAKIKA kosup bitiremedi.
#    Sebep: unpacked dizi elaboratore gore 16.000 AYRI NESNEDIR.
#
#        bicim                     Vivado xelab
#        unpacked localparam dizi  240 sn'de BITMEDI
#        packed vektor + fonksiyon 2,5 SANIYE
#
#    Verilator sayi sabitlerinde 65.536 BIT sinirina sahiptir (olculdu:
#    65.536 tamam, 98.304 "exceeds implementation limit").
#
# -----------------------------------------------------------------------------
#  BOLME - fanout sorunu
#
#    fc_weights tek parca halinde (16.000 giris, 14 bit adres) sentezlendiginde
#    adres cozucusu devasa bir fanout uretiyordu:
#
#        fc_idx[3] -> 4.694 kapi
#
#    Bunun bedeli olculdu (bkz. evidence/asic/DENEY_STUB.md):
#
#        adim                    fc_weights VAR   fc_weights YOK
#        sentez                     42:42            04:52
#        onarim (tampon agaci)    2:00:44            08:02
#        global yonlendirme       2:48 BITMEDI       01:26
#
#    Onarim adimi tamponlama yaptigi icin iki saat suruyordu.
#
#    COZUM: tabloyu ERISIM DESENINE gore bolmek. NPU'nun FC katmani dort
#    sinif icin dort ayri okuma yapar ve indeksler AYRIK araliklardadir:
#
#        fc_weights(fc_idx)           sinif 0 ->     0..3999
#        fc_weights(fc_idx + 4000)    sinif 1 ->  4000..7999
#        fc_weights(fc_idx + 8000)    sinif 2 ->  8000..11999
#        fc_weights(fc_idx + 12000)   sinif 3 -> 12000..15999
#
#    Tek 16.000'lik ROM yerine dort ayri 4.000'lik ROM kurulursa:
#      - her cozucunun adresi 12 bit (14 degil)
#      - her cozucu 4.000 giris tarar (16.000 degil)
#      - fanout kabaca DORTTE BIRE iner
#      - her parca 32.000 bit -> Verilator sinirinin altinda, ek bolme gerekmez
#
#    Cagri yerlerinde toplama da kalkar: fc_weights1(fc_idx) yeter.
#
# -----------------------------------------------------------------------------
#  DOGRULAMA
#    Betik uretimden sonra urettigi dosyayi GERI OKUR ve kaynak .mem ile
#    deger deger karsilastirir. Tek bit kaymasi bile yakalanir - boyle bir
#    kayma NPU'yu sessizce yanlis siniflandirir ve ancak donanimda fark
#    edilirdi.
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

# (fonksiyon_adi, kaynak_dosya, adet, bit, isaretli, bolum)
#
#   bolum = kac AYRI ROM'a bolunecegi. 1 ise tek fonksiyon uretilir;
#           n > 1 ise <ad>0 .. <ad>(n-1) adinda n fonksiyon uretilir ve
#           her biri adet/n girisi tasir.
PAKETLER = [
    (
        "boot_rom_pkg",
        "rtl/boot/boot_rom_pkg.sv",
        u"Boot ROM icerigi - bootloader makine kodu (sw_nexys/src/bootloader.S)",
        [("boot_rom_icerik", "rtl/boot/boot.hex", 256, 32, False, 1)],
    ),
    (
        "npu_weights_pkg",
        "rtl/npu/npu_weights_pkg.sv",
        u"NPU egitilmis agirliklari, sapmalari ve softmax bakis tablosu",
        [
            ("dw_weights",      "weights/dw_weights.mem",      640,    8, True,  1),
            ("dw_bias",         "weights/dw_bias.mem",           8,   32, True,  1),
            # DORDE BOLUNDU - fanout icin. Bkz. baslikta "BOLME".
            ("fc_weights",      "weights/fc_weights.mem",    16000,    8, True,  4),
            ("fc_bias",         "weights/fc_bias.mem",           4,   32, True,  1),
            ("softmax_exp_lut", "weights/softmax_exp_lut.mem", 256,   13, False, 1),
        ],
    ),
]

# Verilator sayi sabiti siniri 65.536 bit; guvenli pay birakiyoruz.
# Bir bolum bu esigi asarsa kendi icinde ayrica parcalanir.
PARCA_TAVAN_BIT = 32768

# Bu esigin uzerindeki tablolar NPU_WEIGHTS_STUB ile devre disi
# birakilabilir (olcum deneyleri icin). Teslimde kullanilmaz.
STUB_ESIK_BIT = 65536


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
    return "%0*x" % ((len(degerler) * bit + 3) // 4, n)


def sabit_adi(fad, parca_sayisi, c):
    """Bir bolumun c'inci parcasinin sabit adi."""
    if parca_sayisi == 1:
        return "%s_DUZ" % fad.upper()
    return "%s_DUZ%d" % (fad.upper(), c)


def bolum_uret(g, fad, degerler, bit, isaretli, stub):
    """Tek bir erisim fonksiyonu ve sabitlerini uretir."""
    adet = len(degerler)
    pb = parca_boyu(bit)
    parca_sayisi = (adet + pb - 1) // pb
    aw = adres_biti(adet)
    pw = adres_biti(pb)
    tip = (u"logic signed [%d:0]" % (bit - 1)) if isaretli \
        else (u"logic [%d:0]" % (bit - 1))

    for c in range(parca_sayisi):
        dilim = degerler[c * pb:(c + 1) * pb]
        genislik = len(dilim) * bit
        g.append(u"    localparam logic [%d:0] %s = %d'h%s;"
                 % (genislik - 1, sabit_adi(fad, parca_sayisi, c),
                    genislik, duz_hex(dilim, bit)))
    g.append(u"")

    if stub:
        g.append(u"`ifdef NPU_WEIGHTS_STUB")
        g.append(u"    // OLCUM DENEYI - gercek tablo yerine adresten turetilen")
        g.append(u"    // ucuz bir deger. Veri yolu canli kalir, ROM yok.")
        g.append(u"    function automatic %s %s(input logic [%d:0] i);"
                 % (tip, fad, aw - 1))
        g.append(u"        return %d'(i);" % bit)
        g.append(u"    endfunction")
        g.append(u"`else")

    g.append(u"    function automatic %s %s(input logic [%d:0] i);"
             % (tip, fad, aw - 1))
    if parca_sayisi == 1:
        g.append(u"        return %s[i * %d +: %d];"
                 % (sabit_adi(fad, 1, 0), bit, bit))
    else:
        g.append(u"        logic [%d:0] o;" % (pw - 1))
        g.append(u"        o = i[%d:0];" % (pw - 1))
        g.append(u"        case (i[%d:%d])" % (aw - 1, pw))
        for c in range(parca_sayisi):
            etiket = u"default" if c == parca_sayisi - 1 \
                else (u"%d'd%d" % (aw - pw, c))
            g.append(u"            %s: return %s[o * %d +: %d];"
                     % (etiket, sabit_adi(fad, parca_sayisi, c), bit, bit))
        g.append(u"        endcase")
    g.append(u"    endfunction")
    if stub:
        g.append(u"`endif")
    g.append(u"")


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
    g.append(u"//  Tablolar packed vektorde tutulur, erisim dilimleme ile")
    g.append(u"//  yapilir. Indeks 0 vektorun EN DUSUK bitlerindedir.")
    g.append(u"//")
    g.append(u"//  fc_weights DORDE BOLUNMUSTUR (fc_weights0..3). NPU'nun FC")
    g.append(u"//  katmani dort sinif icin ayrik araliklardan okur; tek buyuk")
    g.append(u"//  ROM adres cozucusunde 4.694 fanout uretiyordu.")
    g.append(u"// " + u"=" * 74)
    g.append(u"")
    g.append(u"package %s;" % paket_adi)
    g.append(u"")

    for fad, kaynak, adet, bit, isaretli, bolum in tablolar:
        degerler = kaynak_oku(kaynak, adet, bit)
        kaynak_degerler[fad] = degerler
        stub = (adet * bit > STUB_ESIK_BIT)

        g.append(u"    // %s" % kaynak)
        g.append(u"    //   %d giris x %d bit = %d bit%s"
                 % (adet, bit, adet * bit, u" (isaretli)" if isaretli else u""))
        if bolum > 1:
            g.append(u"    //   %d BOLUM x %d giris - fanout icin ayrildi"
                     % (bolum, adet // bolum))
        g.append(u"")

        if bolum == 1:
            bolum_uret(g, fad, degerler, bit, isaretli, stub)
        else:
            n = adet // bolum
            for b in range(bolum):
                g.append(u"    // --- bolum %d: indeks %d..%d ---"
                         % (b, b * n, (b + 1) * n - 1))
                bolum_uret(g, "%s%d" % (fad, b), degerler[b * n:(b + 1) * n],
                           bit, isaretli, stub)

    g.append(u"endpackage")
    g.append(u"")
    return u"\n".join(g), kaynak_degerler


def bolum_oku(metin, fad, adet, bit):
    """Uretilen paketten tek bir bolumun degerlerini geri okur."""
    pb = parca_boyu(bit)
    parca_sayisi = (adet + pb - 1) // pb
    cikan = []
    maske = (1 << bit) - 1
    for c in range(parca_sayisi):
        dilim_adet = min(pb, adet - c * pb)
        genislik = dilim_adet * bit
        desen = (r"localparam logic \[%d:0\] %s = %d'h([0-9a-f]+);"
                 % (genislik - 1, sabit_adi(fad, parca_sayisi, c), genislik))
        m = re.search(desen, metin)
        if not m:
            return None
        n = int(m.group(1), 16)
        cikan += [(n >> (k * bit)) & maske for k in range(dilim_adet)]
    return cikan


def uretilen_oku(metin, fad, adet, bit, bolum):
    """Uretilen paketten bir tablonun tum degerlerini geri okur."""
    if bolum == 1:
        return bolum_oku(metin, fad, adet, bit)
    n = adet // bolum
    cikan = []
    for b in range(bolum):
        p = bolum_oku(metin, "%s%d" % (fad, b), n, bit)
        if p is None:
            return None
        cikan += p
    return cikan


def main():
    yalniz_denetle = "--denetle" in sys.argv
    hata = 0
    toplam_bit = 0

    print(u"=" * 72)
    print(u" ROM TABLOLARI -> SystemVerilog paketi")
    print(u"=" * 72)

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

        geri = io.open(yol, encoding="utf-8").read()
        for fad, kaynak, adet, bit, _, bolum in tablolar:
            beklenen = kaynak_degerler[fad]
            okunan = uretilen_oku(geri, fad, adet, bit, bolum)
            toplam_bit += adet * bit

            if okunan is None:
                print(u"  [HATA] %-16s uretilen dosyada bulunamadi" % fad)
                hata += 1
                continue

            fark = [(i, a, b) for i, (a, b) in enumerate(zip(beklenen, okunan))
                    if a != b]
            if fark:
                print(u"  [HATA] %-16s %d deger uyusmuyor" % (fad, len(fark)))
                for i, a, b in fark[:5]:
                    print(u"           [%d] kaynak=%x uretilen=%x" % (i, a, b))
                hata += 1
                continue

            ek = (u"  %d bolum" % bolum) if bolum > 1 else u""
            print(u"  [OK]   %-16s %6d deger x %2d bit%s  (%s)"
                  % (fad, adet, bit, ek, kaynak))

    print(u"\n" + u"-" * 72)
    print(u"Toplam gomulen: %d bit = %.1f kbit = %.1f kB"
          % (toplam_bit, toplam_bit / 1024.0, toplam_bit / 8192.0))

    if hata:
        print(u"[BASARISIZ] %d sorun" % hata)
        return 1
    print(u"[BASARILI] butun tablolar kaynak dosyalarla birebir ayni.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
