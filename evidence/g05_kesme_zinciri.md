# G05 - NPU Kesme Zinciri ve ISR

Tarih: 18 Agustos 2026

## Yapilan

Yoklama dongusu kaldirildi, yerine sartname s.16'nin istedigi kesme
mimarisi kuruldu:

    NPU done -> npu_csr irq_o -> irq_vector[22] -> CV32E40P irq_i
      -> mtvec (0x01000200) -> trap_handler
      -> sinif okunur, UART'tan yazdirilir, kesme sustururulur
      -> mret -> ana dongu devam eder

Yazilim tarafi (sw_nexys/src/main.c):

  - trap_handler: __attribute__((interrupt("machine"), aligned(256)))
    interrupt  -> derleyici yazmaclari saklar ve mret uretir
    aligned    -> CV32E40P mtvec yalnizca adresin [31:8] bitlerini
                  saklar, rutin 256 bayt hizali olmali
  - irq_init(): mtvec (dogrudan mod), mie bit 22, mstatus.MIE
  - ana dongu: while (!npu_done_flag) wfi;

## Yol boyunca cikan uc engel

### 1. CSR komutlari derlenmiyordu

    Error: unrecognized opcode `csrr a5,mcause',
           extension `zicsr' required

GCC 12'den itibaren zicsr uzantisi temel 'i' uzantisindan ayrildi.
build.py icinde -march=rv32imc -> -march=rv32imc_zicsr yapildi.

### 2. mstatus.MIE yazilamiyordu

`csrsi mstatus, 8` (anlik degerli set) komutu bu cekirdekte islemedi.
Olculdu: mie = 0x00400000 ve mtvec = 0x010002 dogru yazilmisti ama
mstatus.mie 0 kaldi. csrr/csrw ile oku-degistir-yaz kullanildi.

### 3. Kesme sonsuz donguye giriyordu

npu_csr.sv:

    end else if (reg_npu_reset || irq_clear_pulse || reg_start)
        done_sticky <= 1'b0;
    else if (done_i)
        done_sticky <= 1'b1;

Hesaplama motoru bittikten sonra DONE durumunda kalir ve done_i
surekli 1'dir. irq_clear darbesi done_sticky'yi bir cevrim sifirlar,
sonraki cevrimde done_i onu yeniden 1 yapar. Yani yapiskan bayrak
seviye tabanli bir kaynakla besleniyor ve yazilim onu temizleyemiyor.

Uygulanan cozum: ISR, irq_clear ile birlikte irq_enable bitini de
dusuruyor. irq_o = done_sticky && reg_irq_enable oldugu icin kesme
hatti duser. Ana dongu bir sonraki calistirmadan once yeniden aciyor.

Onerilen kalici cozum (G07): done_i'nin yukselen kenarini yakalamak.

    logic done_d;
    always_ff @(posedge clk) done_d <= done_i;
    ...
    else if (done_i && !done_d) done_sticky <= 1'b1;

## Testbench'e UART cozucu eklendi

tb_soc_top.sv artik uart1_txd hattini 115200 baud / 8N1 olarak cozup
satir satir loga yaziyor (bit suresi 434 x 20 ns = 8680 ns).

Iki kazanc:
  - ISR ciktisi gorunur oldu
  - UART TX yolu ILK KEZ dogrulandi; bugune kadar hicbir test bu
    hatti okumuyordu, GPIO uzerinden dolayli cikarim yapiliyordu

Ayrica uart_saw_irq bayragiyla "ISR gercekten UART'tan yazdirdi"
kontrolu eklendi; testbench bunu check ediyor.

Bu izleyici daha ilk kosumda bir sey yakaladi: ana donguda izolasyon
testinden kalan bir yazdirma satiri duruyordu ve "[IRQ] Class"
iki kez basiliyordu. UART gorunur olmasaydi fark edilmezdi.

## Olculen

    Sistem testi : TUM TESTLER GECTI - 0 hata, ~37 saniye
    NPU done -> GPIO yazimi : 2,06 ms
      (ISR'in "[IRQ] Class: 3" yazdirmasi ~1,2 ms,
       ana dongunun "-> NO" yazdirmasi ~0,5 ms)

## Kapanan bulgular

  R1 (kesme ayagi)     - NPU kesmesi + ISR + UART sonuc yazimi
  OTR'deki WFI iddiasi - artik gercekten kullaniliyor

## Acik kalan

mie yazmacinda yalnizca bit 22 (NPU) etkin. Diger kesme kaynaklari
(timer, gpio, uart1, uart2, qspi, i2c, dma) donanimda bagli ama
hicbir testte tetiklenmedi.
