# G07 - QSPI Kenar Hatasi ve TCM Tek Yazan Port (B2)

Tarih: 18 Agustos 2026

## 1. QSPI kenar anomalisi - kok neden bulundu

16 Agustos'ta yukleyici QSPI'dan komut gonderirken bit hizasi kayiyordu:
gonderilen 0x03 (READ) komutu flash tarafinda 0x01 olarak okunuyordu.
O gun prescaler 4'e cikarilarak GECICI olarak ortuldu; kok neden acik
kalmisti.

### Kok neden

qspi_master.sv icinde veri cikisi KAYITLIDIR:

    io_out[0] <= shift_out[7];

shift_out ise dusen kenarda guncellenir (sck_edge_fall). Yani yeni bit,
dusen kenardan BIR CEVRIM SONRA pine cikar.

Prescaler 0 iken:

    assign sck_half_period = (ccr_prescaler == 6'h0) ? 6'h0 : ccr_prescaler;

yarim periyot da tam BIR cevrimdi. Bu durumda dusen kenardan sonraki
yukselen kenar, io_out henuz guncellenmeden geliyordu ve kole ayni biti
IKI KEZ orneklerdi.

Aritmetik birebir eslesti:

    0x03 = 0,0,0,0,0,0,1,1   (b7..b0)
    b7 tekrarlaninca:
           0,0,0,0,0,0,0,1   = 0x01     <- gozlenen belirti

### Duzeltme

    assign sck_half_period = (ccr_prescaler == 6'h0) ? 6'h1 : ccr_prescaler;

Yarim periyot >= 2 cevrim oldugunda kayitli ciktinin bir cevrimlik
gecikmesi soguruluyor ve veri, orneklendigi yukselen kenarda kararli
oluyor.

Prescaler 4'un sorunu "cozmus" gorunmesinin sebebi de buydu - asil
duzeltme, sifir yarim periyoda hic izin vermemek.

Ust sinir: 50 MHz / (2 x 2) = 12,5 MHz SCK. Boot icin fazlasiyla yeterli.

### Not

Bootloader hala prescaler 4 kullaniyor (CCR_READ_256 = 0x88FF0103).
Artik prescaler 1 de guvenli ve boot suresini ~2,5 kat kisaltirdi;
ancak QSPI boot yolu varsayilan simulasyonda kosulmuyor (testbench
`ifndef REAL_BOOT` ile hizli acilis yapiyor). Degisiklik ancak REAL_BOOT
kosumuyla dogrulandiktan sonra yapilmali.

## 2. B2 - TCM tek yazan port

sky130 SRAM makrolari 1RW + 1R yapisindadir: yalnizca BIR port yazabilir.

### Beklenmeyen bulgu

Denetimde "Port B salt-okunur yapilacak" diye not dusulmustu. Kodu
inceleyince Port B'nin gercekten YAZDIGI ortaya cikti:

    npu_compute_engine.sv, WRITE_OUT_0..3 durumlari
      mem_we_b    = 4'hf;
      mem_wdata_b = 32'(probs[0..3]);

Hesaplama motoru softmax sonuclarini Port B uzerinden geri yaziyordu.
Yani iki yazan port vardi ve bu yapi makroya dogrudan eslenemezdi.

### Cozum

Motorun sonuc yazimlari npu_accelerator icinde Port A'ya yonlendirildi:

    assign eng_wr_req  = ram_en_b && (ram_we_b != 4'b0);
    assign tcm_en_a    = eng_wr_req ? 1'b1        : ram_en_a;
    assign tcm_we_a    = eng_wr_req ? ram_we_b    : ram_we_a;
    assign tcm_addr_a  = eng_wr_req ? ram_addr_b  : ram_addr_a;
    assign tcm_wdata_a = eng_wr_req ? ram_wdata_b : ram_wdata_a;

npu_tcm_sram'in Port B yazma yolu ve we_b/wdata_b portlari kaldirildi.
Modul artik dogrudan bir 1RW+1R makroya eslenebiliyor:
Port A -> RW, Port B -> R.

Motor yalnizca dort durumda, toplam DORT kelime yaziyor; geri kalan tum
Port B erisimi okuma.

### Cakisma cozumu - kestirme reddedildi

Ilk dusunce "motor sonuc yazarken NPU mesguldur, CPU wfi'da bekler, yani
AXI zaten sessizdir" idi. Bu bir YAZILIM DAVRANISIDIR ve donanim garantisi
yerine gecmez: yarin ISR'a bir TCM erisimi eklenirse sessizce bozulurdu.

Bunun yerine npu_axi_controller'a stall_i girisi eklendi:

    assign ram_en_o = !stall_i && (mem_do_write || (rstate == R_MEM));
    assign ram_we_o = (!stall_i && mem_do_write) ? mem_wstrb_lat : 4'b0000;
    // B kanali: if (mem_do_write && !stall_i)
    // Okuma FSM'i: R_MEM'de if (!stall_i) rstate <= R_CAPTURE;

Motor yazarken AXI erisimi DUSURULMEZ, yalnizca dort cevrim ertelenir.
Geri bastirma zaten AXI protokolunun dogru kullanimidir.

### Yol boyunca cikan hata

npu_accelerator'da coklayici bloku, npu_axi_controller ornekleme
noktasindan SONRA yazilmisti; eng_wr_req bildiriminden once
kullaniliyordu - ayni gun jtag_debug'da duzeltilen hatanin aynisi.
Bildirimler yukari tasindi.

## Dogrulama

Sistem testi ayni app.hex ile kosuldu. Uc degisiklik de normal akista
davranis degistirmemeliydi ve degistirmedi:

    Onceki kosum : 61.078150 ms, 0 hata
    Bu kosum     : 61.078150 ms, 0 hata   (BIREBIR AYNI)

EN KRITIK GOSTERGE - probs degerleri:

    Onceki : probs: [0]=0, [1]=1050, [2]=1050, [3]=1995
    Simdi  : probs: [0]=0, [1]=1050, [2]=1050, [3]=1995

Bu dort deger artik YENI YOLDAN (Port B yerine Port A) yaziliyor ve
motor tarafindan dogru adreslere ulasiyor. Degerlerin ozdes cikmasi,
yeniden yapilandirmanin sonucu bozmadiginin dogrudan kanitidir.

Ayrica JTAG'in TCM okuma/yazmasi (0x2001_1000 = 0xDEADBEEF) calismaya
devam ediyor - Port A'nin AXI yolu bozulmamis.

## Kapanan

  QSPI kenar anomalisi - kok neden bulundu ve duzeltildi
  B2'nin RTL yarisi - TCM tek yazan porta indirildi (1RW+1R uyumlu)
  npu_axi_controller - stall ile guvenli cakisma cozumu

## Acik kalan

  B2'nin ASIC yarisi - gercek sky130 SRAM makrosunun ornenklenmesi
  Tri-state ayrimi
  Bootloader prescaler 1'e cekilmesi (REAL_BOOT dogrulamasi gerekiyor)
