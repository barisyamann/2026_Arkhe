# NPU Sorun Raporu

**Arkhe SoC — TEKNOFEST 2026 Cip Tasarim Yarismasi, Mikrodenetleyici Kategorisi**
Tarih: 22 Agustos 2026 · Teslim: 31 Agustos 2026 (9 gun)
Kapsam: `rtl/npu/` — compute engine, agirlik paketi, TCM, CSR

---

## Envanter

| # | Sorun | Etki | Durum |
|---|---|---|---|
| 1 | `fc_weights` ROM'u ASIC yonlendirmesini kilitliyor | **ASIC akisi tamamlanamiyor** | 🔴 ACIK |
| 2 | Gercek ses verisiyle dogrulama yok (EK-3) | Odul sarti, harfiyen uyum | ✅ COZULDU |
| 2b | Yazilim/donanim hizlanma orani olculmemis (EK-1) | Acik ister, puanlanan metrik | ✅ COZULDU |
| 3 | DTR cevrim sayisi ile olcum celiskisi | Sunum tutarliligi | ✅ COZULDU |
| 4 | Dogrulama yalnizca tek sinifi uyariyordu | Kapsam bosluğu | ✅ COZULDU |
| 5 | DTR agirlik yerlesimi anlatimi guncel degil | Belge sapmasi | 🟡 ACIK |
| 6 | Agirliklar RTL'e gomulu — calisma aninda degistirilemez | Mimari kisit | 🟡 KABUL |

Sartname referanslari: EK-1 (YZ Hizlandirici Isterleri), EK-3 (Dogrulama
Metotlari), Bolum 5.2 (Odul icin asgari basari kriterleri).

---

## 1. 🔴 `fc_weights` ROM'u ASIC yonlendirmesini kilitliyor

### Sorun

`fc_weights` tablosu 16.000 x 8 bit = 128 kbit. ASIC'te ROM hucresi yoktur;
Yosys bunu duz mantiga cevirir. Ortaya cikan adres cozucu, tek bir adres
biti uzerinde binlerce kapi suren dev bir ag yaratir. OpenROAD'un onarim
adimi buna tampon agaci kurmaya calisir, sonra global yonlendirici o
bolgede tikanir.

### Olcum

Ayni tasarim, **tek degisken** `fc_weights`:

| Adim | Bolunmemis | 4'e bolunmus | Stub (agirliksiz) |
|---|---|---|---|
| Sentez | 42:42 | 13:52 | 04:52 |
| Hucre sayisi | 109.963 | 77.442 | 67.422 |
| `fc_idx` fanout | **4.694** | **946** | — |
| Onarim (repairdesignpostgpl) | **2:00:44** | 28:11 | 08:02 |
| CTS | — | 02:57 | — |
| **Global yonlendirme** | **2:48 BITMEDI** | **2:20 BITMEDI** | **01:26** |
| Detayli yonlendirme | ulasilamadi | ulasilamadi | **44:51, 0 ihlal** |

Iki sayi belirleyici: **global yonlendirme agirliklar cikinca 2,5 saatten
86 saniyeye dusuyor.** Sikisiklik raporunda hicbir katmanda overflow yok
(en yuksek met1 %18,95) — yani die alani yeterli, sorun yerel yigilma.

`fc_weights`'in mantik maliyeti: bolunmemis ~42.500 hucre, 4'e bolunmus
~10.000 hucre.

### Denenmis ve ise yaramis

4'e bolme (sinif hizali: her sinifin 4000 agirligi ayri ROM'da).
`npu_compute_engine.sv` icinde `fc_idx` 14 bitten 12 bite indi, FSM
FC_MAC0..3 durumlarinda sirayla `fc_weights0..3` okuyor. Fanout 5 kat
dustu, onarim 4 kat hizlandi. **Ama global yonlendirme hala bitmiyor.**

### Secenekler

| | Yaklasim | Beklenen kazanc | Risk | Sure |
|---|---|---|---|---|
| **A2** | **16'ya bolme** | fanout ~240, onarim ~8 dk | **yok** | yarim gun |
| B | 8 SRAM makrosuna tasima | fanout ortadan kalkar | **yuksek** | 2-3 gun |
| D | INT4 kuantizasyon (16 kB -> 8 kB) | ROM yarilanir | orta | 1-2 gun |

**A2 onerilir.** Bolme zaten olculmus bir kaldiractir; uretici betigi
(`scripts/gen_rom_paketleri.py`) bolme sayisini parametre olarak aliyor,
degisiklik tek sayidan ibaret. Compute engine tarafinda `fc_idx` 10 bite
iner ve 2 bitlik yigin seciciyle 4:1 mux eklenir.

**B'nin gizli maliyeti:** SRAM ucucudur. Agirliklar her aciliste flash'tan
yuklenmelidir — bootloader'a 16 kB kopyalama, yeni DMA akisi, yeni
dogrulama. Mimari olarak dogru, 9 gun kala yanlis zamanlama.

**D'nin maliyeti:** model dogrulugunu degistirir, EK-1 %10 penceresine
karsi yeniden dogrulama gerekir.

---

## 2. ✅ COZULDU — gercek ses verisiyle dogrulama

### Sartname ne istiyor

**EK-3**, YZ Hizlandirici Testleri'ni **Zorunlu\*** (odul sarti) isaretler:

> "Referans ses verilerini (ornekler TFLite Micro deposunda bulunabilir ve
> 1000 milisaniyelik mono kanalli WAV dosyalari da test verisine
> donusturulebilir) bellekten hizlandirici cekirdegine suren ve ciktilari
> kontrol eden YZ hizlandirici blogu icin tekil testler."

**EK-1** ayrica dogruluk penceresi ister:

> "yazilim ile gerceklenen modelin dogrulugunu (accuracy) %10'luk bir
> pencere dahilinde yakalamalidir."

### Bugun ne var

`tb/npu_audio/` altyapisi kuruldu (22 Agustos):

- `npu_ref_model.py` — yazilim referans modeli, altin referansla bit-birebir
- `gen_vectors.py` — dort sinifi da uyaran vektor arar
- `tb_npu_audio.sv` — 7 vektor x 11 denetim, self-checking
- `testdata/*.wav` — TFLite Micro resmi referans sesleri (indirildi)

Sonuc: **7/7 siniflandirma uyumu, 77 denetim, 0 hata.** Ayni girdide RTL ile
yazilim modeli **birebir** ayni cikti veriyor — yani EK-1 penceresi %10
degil, **%0 sapma** ile karsilaniyor.

### 22 Agustos aksami - COZULDU

On isleme zinciri `tb/npu_audio/micro_frontend.py` olarak NumPy ile
yazildi:

| Klip | Siniflandirma | Guven |
|---|---|---|
| `yes_1000ms.wav` | **YES** dogru | 3364/4096 = %82 |
| `no_1000ms.wav` | **NO** dogru | 2314/4096 = %56 |
| `silence_1000ms.wav` | belirsiz - asagi bkz. | |

`yes` ve `no` regresyona **gercek ses vektoru** olarak eklendi
(`ses_yes`, `ses_no`).

### Silence neden eklenmedi

Sebep tasarim degil, **modelin kendisi**: tamamen doygun bir girdi dort
sinifa da tam esit olasilik veriyor.

    tamamen -128 girdi  ->  probs = [1024, 1024, 1024, 1024]

Sonuc argmax'in beraberlik cozumune kaliyor. On islememiz sessizlik icin
`min=-128, max=-118` uretiyor; bu kucuk degisim beraberligi bozup sonucu
YES'e cekiyor. Regresyona bu kadar kirilgan bir denetim konmadi.

### Kalan sinir

Aritmetik **kayan noktadir**, C kutuphanesinin sabit nokta sonuclarina
bit-birebir esit degildir. PCAN kazanc olcegi
(`(1 << gain_bits) >> snr_shift`) kayan noktada kayboldugu icin
`PCAN_SCALE` ile ampirik verilmistir.

Bu kabul edilebilir cunku **on isleme cipte degildir**: sartname
mimarisinde ses verisi UART-stream uzerinden zaten islenmis gelir.

### Neden elle yazilmasi gerekti

Resmi on isleyici `audio_preprocessor_int8.tflite`, TFLM'e ozgu **ozel
islemciler** kullaniyor:

    SignalWindow          SignalFftAutoScale     SignalRfft
    SignalEnergy          SignalFilterBank       SignalFilterBankLog
    SignalPCAN            SignalFilterBankSquareRoot
    SignalFilterBankSpectralSubtraction

Standart TensorFlow / LiteRT bu islemcileri **tanimaz**. Calistirmak icin
`tflm_runtime` gerekir; kaynaktan derlenir, Windows icin hazir paketi
yoktur. Bu yuzden zincir microfrontend algoritmasina gore NumPy ile
yeniden yazildi.

---

## 2b. ✅ COZULDU — hizlanma orani olculmemisti

Inceleme sirasinda **atlanmis bir zorunlu ister** cikti.

EK-1: *"RISC-V cekirdegi uzerinde calisan yazilim gerceklemesine kiyasla
hizlanma elde etmelidir."* Bolum 4.2.2.1: performans *"veri/saat dongusu
bazinda ve ... islenmis veri/saniye bazinda"* olculmelidir.

Donanim olculmustu (72.583 cevrim), **yazilim hic olculmemisti** - yani
oran gosterilemiyordu.

`sw_nexys/src/npu_sw_bench.c`: ayni model, ayni kuantizasyon aritmetigi,
C ile. Agirliklar TCM'de (16 kB FC agirligi 8 kB D-RAM'e sigmaz).

| | Cevrim | 50 MHz'de | Cikarim/saniye |
|---|---|---|---|
| **Yazilim (CV32E40P)** | 64.423.245 | **1,29 s** | 0,78 |
| **Donanim (NPU)** | 72.583 | **1,45 ms** | 689 |
| **HIZLANMA** | | | **888x** |

Metodoloji onemli: ilk denemede `cevrim / N * 4000` kullanildi ve **eksik
sonuc verdi**. Olculen ilk N piksel tamamen `t=0` bolgesindedir, orada
cekirdegin 10 satirindan yalnizca 6'si gecerlidir. Dogru olcut **tap**
sayisidir; iki farkli N olcumunden `cevrim = a*tap + b*piksel` cozulmustur.

Tam olcum: `evidence/npu/HIZLANMA_OLCUMU.md`

## 3. ✅ COZULDU — DTR cevrim sayisi celiskisi

### Belirti

| Kaynak | Cikarim suresi |
|---|---|
| DTR Bolum 4.5 | 964.077 cevrim = 19,28 ms |
| Bugun olculen | **72.583 cevrim = 1,45 ms** |

13 kat fark. Sartname: *"tasarim ciktilari kullanilarak sunumdaki sonuclar
dogrulanacak ve uyumsuz olan gruplar elenecektir."*

### Kaynak

Git gecmisi celiskiyi tamamen aciklyor:

    cdddd12  FC hesaplama yolu boru hattina ayrildi   964.071 -> 992.071
    85cbf8a  R4 asama 1: konvolusyonda kanal paylasimi        6,5x
    a432ef9  R4 asama 2: konvolusyon okuma boru hatti  toplam 13,7x

DTR yazildiginda motor `cdddd12` halindeydi (964.071 cevrim — DTR'deki
964.077 ile olcum gurultusu farki). Sonrasinda iki optimizasyon yapildi:

**Asama 1 — kanal paylasimi.** Girdi adresi `t_in = t_out*2 - 4 + kh`,
`f_in = f_out*2 - 3 + kw`. `d_out` adrese girmiyor; yani sekiz kanalin
hepsi **ayni** girdi piksellerini okuyordu ve ayni 10x8 pencere sekiz kez
taraniyordu. Piksel bir kez okunup sekiz kanala paralel dagitildi.
992.083 -> 152.083 cevrim (6,52x).

**Asama 2 — okuma boru hatti.** TCM okuma cikisi kayitli; eski FSM bunu uc
cevrime yayiyordu (READ_REQ -> READ_WAIT -> MAC). Iki asamali boru hattina
cevrildi. Toplam 13,7x.

Blok testi ve sistem testi **ayni sayiyi** veriyor:
sistem simulasyonunda 43.316.730.000 − 41.865.070.000 ps = 1,4517 ms =
72.583 cevrim.

Tam olcum: `evidence/r4_npu_hizlandirma.md`

### Gereken aksiyon

Bu bir hata degil, **DTR'den sonra yapilmis bir iyilestirmedir.** Final
sunumunda ve raporda acikca anlatilmalidir; aksi halde jurinin elindeki
DTR ile teslim edilen ciktilar uyusmaz gorunur.

Sartname puanlamasinda "Sistem performansi" ve "Kararlarin ardindaki
rasyonel" basliklari var — 13,7x hizlanma **puan kazandiran** bir
sonuctur, saklanacak degil one cikarilacak bir bulgudur.

---

## 4. ✅ COZULDU — dogrulama yalnizca tek sinifi uyariyordu

`tb_npu_golden` **tek** deterministik vektor kosuyordu ve yalnizca **NO**
sinifini uretiyordu. Karar mekanizmasinin diger uc dali — SILENCE,
UNKNOWN, YES — hicbir testte calismamisti. Blok testleri gectigi icin
"dogrulandi" saniliyordu.

22 Agustos'ta `tb_npu_audio` eklendi: dort sinifi da kapsayan 5 vektor.

Ek olarak bir vektor **beraberlik** durumunu yakaliyor:
`logits = [-22, 23, 25, 25]` — sinif 2 ve 3 esit. RTL'in argmax zinciri
`>=` ile sinif 0'dan basliyor, yani ilk kazanir:

    else if ($signed(fc_logits[2]) >= $signed(fc_logits[3])) class_o <= 2'd2;

Yazilim referansi da (`if lg[i] > lg[cls]`) ilk indisi koruyor. **Iki
gerceklemenin beraberlik cozumu ayni** — bu davranis artik regresyonla
korunuyor.

Regresyon: 7/7 test 66 denetimden **10/10 test 159 denetime** cikti.

---

## 5. 🟡 DTR agirlik yerlesimi anlatimi guncel degil

DTR Bolum 2.2.3 diyor ki:

> "Kullanilan FC agirliklari TFLite modelinden cikarilan fc_weights.mem
> dosyasindan ROM benzeri bicimde okunur."

Iki nokta degisti:

1. **`$readmemh` kaldirildi.** Agirliklar artik RTL paketine gomulu
   (`rtl/npu/npu_weights_pkg.sv`). Sebep: `$readmemh` calisma dizinine
   gore cozumleniyor ve LibreLane her adimi kendi dizininde kosuyordu —
   alti ROM tablosu ASIC netlistinde **sessizce bosaliyordu**. Kanit:
   `evidence/asic/READMEMH_BULGUSU.md`

2. **Tek ROM degil, dort ROM.** Yonlendirme icin sinif hizali bolundu.
   Adresleme mantigi ayni kaldi (`class * 4000 + flat_idx`), yalnizca
   fiziksel yerlesim degisti.

DTR'deki `[4, 4000]` sekil ve indeksleme formulu **hala dogru**. Yalnizca
saklama bicimi anlatimi guncellenmeli.

---

## 6. 🟡 KABUL — agirliklar RTL'e gomulu

Agirliklar sentez zamani sabitidir. Sonuclari:

- **Calisma aninda model degistirilemez.** Farkli bir model yuklemek
  yeniden sentez gerektirir.
- **Uretim sonrasi duzeltme yok.** Cipe donusen agirliklar kalicidir.
- Buna karsilik: acilista yukleme gerekmez, bootloader sade kalir,
  ucucu olmayan bellek gerekmez.

Yarisma kapsaminda model sabittir (TFLite Micro Speech), bu yuzden kisit
kabul edilmistir. **Ancak `fc_weights` SRAM'e tasinirsa (secenek B) bu
kisit zorunlu olarak kalkar ve acilista yukleme mimarisi gerekir** — iki
konu birbirine baglidir.

---

## Kapanmis ve acik ozet

**Kapandi**
- Cevrim sayisi celiskisi aciklandi ve belgelendi
- Dort sinif da dogrulama kapsamina alindi
- Beraberlik cozumu RTL ile referans arasinda esitlendi
- Aritmetik dogrulugu 5 vektorde bit-birebir

- Gercek ses on isleme zinciri yazildi; yes/no regresyonda
- Yazilim/donanim hizlanma orani olculdu: **888x**

**Acik**
- `fc_weights` yonlendirmeyi kilitliyor → **A2 (16'ya bolme) onerilir**
- DTR belge sapmalari final raporunda duzeltilmeli
- Sessizlik klibi belirsiz kaliyor (model ozelligi, tasarim degil)

**Karar bekleyen**
- A2 ne zaman uygulanacak (ASIC yeniden kosumundan once)

---

## Kanit dosyalari

    evidence/asic/DENEY_STUB.md              stub deneyi, tam olcum
    evidence/asic/READMEMH_BULGUSU.md        $readmemh bulgusu
    evidence/r4_npu_hizlandirma.md           13,7x hizlandirma
    evidence/asic/ara_sonuclar/bolunmus_rom/ 4'e bolme adim sureleri
    evidence/npu_csr_kesme_bulgusu.md        CSR kesme bulgusu
    tb/npu_audio/vectors_meta.json           dogruluk testi vektorleri
