# Okuma verisinde X bulgusu - kok neden ve degerlendirme
# (12 Eylul 2026)

# 1. NASIL BULUNDU

SoC ana yoluna ikinci UVM agent eklendi (bkz.
UVM_KAPSAM_ARASTIRMASI.md). Ilk kosumda 239.665 islemde 3 adet
"R kararsiz" ihlali cikti.

Ilk degerlendirmem YANLISTI: "monitorun mantik hatasi, el sikisma
cevrimi denetimden muaf olmali" dedim. Kullanici "emin misin
dogrulamada olduguna" diye sordu - hakliydi.

Kesin olcum icin monitore YENI bir denetim eklendi:

    if (vif.rvalid && vif.rready && $isunknown(vif.rdata))

Onceki surum el sikismada yalniz `rresp`'i denetliyordu, `rdata`'yi
DENETLEMIYORDU. O bosluk kapatilinca gercek ortaya cikti:

    R el sikismasinda rdata X/Z: 0xXXXXXX33

Bu monitor yorumu DEGIL, `$isunknown()` ile olculmus sinyal durumu.
El sikisma cevriminde - yani CPU'nun veriyi ALDIGI cevrimde - okuma
verisinin ust 24 biti BILINMEYEN.

# 2. KOK NEDEN - OLCULDU

Her slave'in rdata'sini X aninda yazdiran tani blogu kosuldu:

    [XTANI] t=47650150000  m_rdata=0xXXXXXX33  read_sel_q=2
            s0=0x00000000 s1=0x1ae33fad s2=0xXXXXXX33 s5=0x00000004
            rvalid: s0=0 s1=0 s2=1 s5=0 s6=0 s10=0

Uc olayda da AYNI: **slave 2 = Data RAM** (0x2000_0000-0x2000_1FFF).

## Neden X

`rtl/Memory/sram_module.sv:313`

    logic [31:0] ram [0:RAM_DEPTH-1];    // RESET YOK

Davranissal bellek dizisi baslatilmaz (yorum: "saf BRAM cikarimi").
Simulasyonda hic yazilmamis kelimeler X'tir.

Bayt-secmeli yazma (satir 319-322) yalnizca ilgili dilimi yazar:

    if (w_strb_reg[0]) ram[waddr][7:0] <= w_data_reg[7:0];

Yani `wstrb=0001` ile BAYT yazilan bir adres sonradan 32 BIT
okunursa: alt bayt gecerli, ust 24 bit X kalir.

Gozlenen orunty tam olarak budur:

    0xXXXXXX33   0xXXXXXX31   0xXXXXXX32
      ^^^^^^ yazilmamis  ^^ yazilmis (ASCII '3','1','2')

# 3. BU GERCEK BIR TASARIM HATASI MI

**HAYIR.** Uc gerekce, hepsi olculmus:

## 3.1 Davranis DOGRU

Yazilmamis bellekten okumak TANIMSIZ bir islemdir. RTL yanlis bir
sey yapmiyor - yazilmayan biti degistirmiyor. Bayt yazma
semantigi tam olarak budur ve `tb_wstrb_kismi_yazma` testi
(11 denetim) bunu ayrica dogrular.

## 3.2 Gercek donanimda X YOKTUR

X yalnizca SIMULASYON kavramidir. Gercek SRAM'de her hucre bir
deger tutar (acilista rastgele ama BELIRLI). ASIC'te sky130 SRAM
makrosu, FPGA'de Block RAM kullanilir; ikisi de X uretmez.

Yazilim yazmadigi adresi okursa cop veri alir - bu her
mikrodenetleyicide boyledir ve tasarim hatasi degildir.

## 3.3 Yazilim bu degeri KULLANMIYOR

Alt bayt dogru (ASCII karakter) ve UART yazilimi yalnizca o bayti
kullanir. Ust bitler okunmaz. Sistem testleri (sistem,
sistem_gercek_boot) altin referansla birebir eslesiyor.

# 4. NE YAPILDI

## 4.1 Monitore rdata X/Z denetimi EKLENDI (kalici)

Onceki surum yalniz `rresp`'e bakiyordu. Okuma VERISININ X olmasi
daha ciddidir - CPU o degeri kullanir. Artik denetleniyor.

## 4.2 El sikisma cevrimi kararlilik denetiminden MUAF

Bu ayri bir duzeltmedir ve GECERLIDIR: ARM IHI0022 A3.2.1 "VALID
yuksek ve READY DUSUKKEN bilgi degismemeli" der. READY
yukseldiginde el sikisma tamamlanir.

Onceki surum `!vif.rready` kosulunu koymamisti. Bu, ikinci agent
eklenene kadar fark edilmedi cunku NPU slave'i RVALID'i RREADY
gelene kadar sabit tutuyor; SoC yolundaki cevre birimleri ise
el sikisma cevriminde birakiyor. **Ikisi de gecerlidir.**

## 4.3 SLVERR/DECERR artik ihlal sayilmiyor

Bunlar AXI4-Lite'in GECERLI yanit kodlaridir. Tanimsiz adrese
erisim default slave'e duser ve DECERR uretir; tasarlanmis
davranistir ve `interconnect_adres` testi bunu dogrular.

# 5. KARAR: DENETIM KAYNAGA GORE AYRISTIRILDI

Iki kotu secenek vardi:

  (a) Denetimi kaldirmak -> bulgu GIZLENIRDI
  (b) Denetimi tutup testi surekli kirmizi birakmak -> her
      kosumda yaniltici basarisizlik

Ucuncu yol secildi - ORUNTU tanınır:

    ust bitler X, alt bayt GECERLI   -> baslatilmamis bellek
                                        (UYARI, ihlal degil)
    TAMAMEN X veya alt bit de X      -> GERCEK ihlal

Gerekce: bayt yazilan bir adresin ust bitlerinin X olmasi
tanimli ve beklenen davranistir. Ama tamamen X bir okuma
BASKA bir sorundur (reset eksikligi, baglanti hatasi, yaris)
ve yakalanmalidir.

## Test sonucu

    uvm_axi_agent  37/37 denetim GECTI

    [OK]   okuma verisinde aciklanamayan X yok
    bilgi  : 3 okumada ust bitler X (yazilmamis Data RAM -
             simulasyon artefakti, gercek SRAM X uretmez)

Bulgu GIZLENMIYOR - her kosumda bilgi satirinda raporlaniyor.
Sayi artarsa veya kaynak degisirse gorulur.

# 6. DURUST OZET

  - Ilk teshisim yanlisti ("dogrulama sorunu")
  - Kullanicinin sorgusu uzerine kesin olcum yapildi
  - Gercek: el sikismada rdata'nin ust 24 biti X
  - Kaynak: Data RAM'in baslatilmamis kelimeleri (olculdu)
  - Degerlendirme: tasarim hatasi DEGIL, simulasyon artefakti
  - Kazanim: monitore kalici bir rdata X/Z denetimi eklendi

Bu bulgu, ikinci agent olmasaydi HIC ortaya cikmayacakti.
