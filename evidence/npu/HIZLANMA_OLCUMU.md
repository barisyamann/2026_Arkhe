# NPU Hizlanma Olcumu - yazilim / donanim

Tarih: 22 Agustos 2026

## Neden olculdu

Sartname **EK-1**:
> "YZ hizlandiricisi modeli gerceklemeli ve RISC-V cekirdegi uzerinde
> calisan yazilim gerceklemesine kiyasla **hizlanma elde etmelidir**."

Sartname **Bolum 4.2.2.1**:
> "YZ hizlandiricilarin performanslari, testler kapsaminda **veri/saat
> dongusu** bazinda ve sentezlenmis frekansta **islenmis veri/saniye**
> bazinda test edilmeli ve degerlendirilmelidir."

Donanim tarafi olculmustu (72.583 cevrim). **Yazilim tarafi hic
olculmemisti**, yani hizlanma orani gosterilemiyordu - acik bir ister
karsilanmiyordu.

---

## Yontem

`sw_nexys/src/npu_sw_bench.c`, donanim motoruyla **ayni aritmetigi** C
ile gerceklestirir: ayni kuantizasyon carpanlari, ayni `gemmlowp`
yuvarlama ilkelleri, ayni akisli FC yapisi.

### Agirliklar neden TCM'de

FC agirliklari 16 kB'dir; D-RAM 8 kB'dir. Yazilim modeli agirliklari
D-RAM'e **sigdiramaz**. 30 kB'lik NPU TCM'i bu SoC uzerinde 16 kB
agirligi tutabilecek tek yerdir; CPU oraya AXI uzerinden erisir. Bu,
yapay bir kisit degil - bu cip uzerinde yazilim gerceklemesinin gercekci
tek senaryosudur.

### Neden alt kume olculuyor

Tam cikarim ~64 milyon cevrimdir; RTL simulasyonunda saatler surer.
Bunun yerine N cikis pikseli olculur.

### Duz oranla olcekleme NEDEN YANLIS

Ilk denemede `cevrim / N * 4000` kullanildi. **Bu eksik sonuc verir.**

Olculen ilk N piksel tamamen `t = 0` bolgesindedir. Orada cekirdegin
10 satirindan yalnizca **6'si** gecerlidir (`ti = 2t - 4 + kh`, gecerlilik
`0 <= ti <= 48`). Ayrica `f = 0` ve `f = 1` sutunlarinda 8 kolondan
sirasiyla **5** ve **7**'si gecerlidir. Yani olculen pikseller ic
bolgedekilerden cok daha ucuzdur.

Dogru olcut **tap** (bir MAC + iki TCM bayt okumasi) sayisidir:

    cevrim = a * tap + b * piksel

Iki bilinmeyen; iki farkli N olcumu kapali cozum verir.

---

## Olcumler

| N | tap | olculen cevrim |
|---|---|---|
| 25 | 1.008 | 252.625 |
| 50 | 2.208 | 542.273 |

Cozulen model:

    a  (tap basina)           = 192,8 cevrim
    b  (piksel basina sabit)  = 2.330 cevrim

`a`'nin buyuk olmasi beklenen: her tap iki ayri TCM baytini AXI uzerinden
okur, yani iki tam veriyolu islemi + kaydirma/maskeleme.

Tam cikarimdaki gecerli tap sayisi:

    8 * (sum_t gecerli_kh(t)) * (sum_f gecerli_kw(f))
      = 8 * 235 * 152
      = 285.760

---

## SONUC

| | Cevrim | 50 MHz'de | Cikarim/saniye |
|---|---|---|---|
| **Yazilim (CV32E40P)** | 64.423.245 | **1,29 s** | 0,78 |
| **Donanim (NPU)** | 81.583 | **1,63 ms** | 613 |
| **HIZLANMA** | | | **790x** |

### Cevrim sayisi neden 72.583'ten 81.583'e cikti

ASIC zamanlama kapanisi icin CONV boru hattina IKI ASAMA eklendi:

1. **SRAM cikisinin yazmaclanmasi** (CONV_MAC 3 asamali oldu). sky130 SRAM
   makrosunun Liberty dosyasi dout icin `timing_type: falling_edge` bildirir;
   veri dusen kenarda cikar ve MAC'e dogrudan girdiginde kalan butce yarim
   cevrime dusuyordu.
2. **Adres asamasinin yazmaclanmasi** (asama 0), boru hatti 4 derinlige cikti.

Her biri piksel basina +1 cevrim getirdi: 500 piksel x 2 = +1000 cevrim.
Toplam 80.583 -> 81.583.

Bu, nominal-tt kosesindeki 130 zamanlama ihlalini (WNS -4,00 ns) **sifira**
indirdi. Kayip %12,4 cevrim; kazanc kapanmis bir kose. Ayrintilar:
`evidence/asic/ZAMANLAMA_ANALIZI_RAPORU.md`.

**Olcum:** sistem testi kutugunden dogrudan, iki cikarim icin ozdes:
`(41876650000 - 40244990000) ps / 20000 ps = 81.583 cevrim`


Sartname EK-1'in istedigi "yazilim gerceklemesine kiyasla hizlanma"
**790 kat** olarak gosterilmistir.

---

## Yeniden uretme

    # Iki ikiliyi derle
    riscv-none-elf-gcc -march=rv32imc_zicsr -mabi=ilp32 -Os -ffreestanding \
        -fno-builtin -nostartfiles -nostdlib -DN_OUT=25 \
        -T sw_nexys/link/app.ld sw_nexys/src/crt0.S sw_nexys/src/npu_sw_bench.c \
        -o bench_25.elf
    # (N_OUT=50 icin tekrarla)

    # TCM imaji
    python tb/npu_sw_bench/gen_tcm_image.py

    # Simulasyon: xvlog -d BENCH_N25 / BENCH_N50 ; xelab ; xsim

    # Analiz
    python tb/npu_sw_bench/analiz.py

Regresyonda `npu_hizlanma` testi N=50 kosumunu otomatik yurutur ve
yazilimin donanimdan en az 100 kat yavas oldugunu dogrular.

---

## Olcum sirasinda cikan iki tuzak

Ikisi de kayda deger, cunku ayni hatalar baska testlerde de tekrarlanabilir.

**1. Sonuc imzasi EN SONA yazilmalidir.**
Testbench imzayi gorunce diger sonuc kelimelerini okur. Imza once
yazilirsa testbench, CPU henuz sonuclari yazmadan okur ve hepsi 0 cikar.
Ilk kosumda `cevrim = 0`, `fc_acc = [0,0,0,0]` gorulmesinin sebebi buydu -
donanimda bir sorun yoktu.

**DUZELTME (22 Agustos, timer blok testi sonrasi).** Bu belgede once
sifir cevrim sonucunun sebebi olarak `TIM_ARE`'nin ayarlanmamasi
gosterilmisti. **Bu teshis yanlisti.** `timer_peripheral.sv` icinde
`reg_tim_are` reset degeri `32'hFFFFFFFF`'dir, `0` degil - yani
zamanlayici ayarlanmadan da sayar. Tek gercek sebep yukaridaki imza
sirasi yarisiydi. Yanlis teshis, RTL okunmadan belirti uzerinden
cikarim yapmaktan dogdu; `tb/timer/tb_timer_peripheral.sv` yazilirken
reset degerleri olculunce ortaya cikti.

`npu_sw_bench.c` hala `TIM_ARE`'yi acikca yaziyor. Zararsiz ve acik
olmasi iyi; ancak zorunlu degil.

Ayrica `$readmemh` ile TCM on-yuklemesi **zaman 0'da yapilamaz**:
`npu_tcm_sram.sv` kendi `initial` blogunda diziyi sifirliyor ve
SystemVerilog `initial` bloklarinin sirasini garanti etmiyor. `#1`
sonrasina alindi. (Ayni tuzak `tb_qspi_mock.sv` icinde de belgeli.)
