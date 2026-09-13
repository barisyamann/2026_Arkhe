# Hatasiz kosu icin kapsamli arastirma (11 Eylul 2026)

Kullanici istegi: "cok iyi hatasiz bir kosu alabilmek icin hem
configure ayarlari hem de RTL'de neler yapilabilir, her seviyeyi
arastir".

Bu belge OLCULMUS verilere dayanir; olcum ile tahmin ayri isaretlidir.

# 1. MEVCUT DURUM (K_diyot, dogrulanmis)

## Temiz olanlar - dokunulmamali

| Denetim                  | Sonuc |
|--------------------------|-------|
| LVS (tum alt metrikler)  | 0 hata |
| KLayout imza DRC         | 0 |
| Detayli yonlendirme DRC  | 0 |
| Anten net / pin          | 0 / 0 |
| GDS XOR farki            | 0 |
| Guc dagitim agi          | 0 |
| Kritik baglantisiz pin   | 0 |
| Floating pin             | 0 |

## 23 ns'de zamanlama - DOKUZ KOSE POZITIF

| Kose             | Setup WNS | Setup TNS | Hold WNS |
|------------------|----------:|----------:|---------:|
| min_ss_100C_1v60 |   +1,5562 |       0,0 |  +1,1638 |
| nom_ss_100C_1v60 |   +0,7078 |       0,0 |  +1,1717 |
| max_ss_100C_1v60 |   +0,3965 |       0,0 |  +1,1817 |
| min_tt_025C_1v80 |   +5,7672 |       0,0 |  +0,5841 |
| nom_tt_025C_1v80 |   +5,2083 |       0,0 |  +0,5885 |
| max_tt_025C_1v80 |   +4,9112 |       0,0 |  +0,5943 |
| min_ff_n40C_1v95 |   +7,3622 |       0,0 |  +0,3738 |
| nom_ff_n40C_1v95 |   +6,8813 |       0,0 |  +0,3770 |
| max_ff_n40C_1v95 |   +6,3171 |       0,0 |  +0,3813 |

## Acik kalan sayisal kalemler

    Slew ihlali    16.442   (C_kapanis: 17.065 - K daha iyi)
    Cap ihlali      1.911   (C_kapanis: 1.911 - ayni)
    Fanout ihlali      81   (C_kapanis: 66 - K'da 15 fazla)
    Magic DRC       7.658   (makro kaynakli, C ile birebir ayni)


# 2. RTL SEVIYESI - EN YUKSEK GETIRILI BULGU

## 2.1 NPU SRAM BYPASS'I HALA ACIK  (kritik)

20 ns imzada olculen 28 ihlalin dagilimi:

    NPU SRAM makro cikisi ..... 26 ihlal   (%93)
    gpio_i[3] (hold) ..........  1
    clk_i -> qspi_sck .........  1

Ornek ihlaller (max_ss kosesi):

    u_npu.u_npu_sram.g_sram[0].u_macro/dout0[9]  -> _191794_/D : -1,367
    u_npu.u_npu_sram.g_sram[0].u_macro/dout0[31] -> _191816_/D : -1,181
    u_npu.u_npu_sram.g_sram[0].u_macro/dout0[9]  -> _189610_/D : -0,737

KOK NEDEN - rtl/npu/npu_tcm_sram.sv:197

    assign rdata_a = en_a_q ? (inr_a_q ? dout_a[sel_a_q] : 32'h0)
                            : rdata_a_hold;

Aktif okumada (en_a_q = 1) veri SRAM cikisindan 15 makroluk coklayici
uzerinden KOMBINASYONEL geciyor.

DIKKAT: Dosyanin 176-196. satirlarindaki yorum "6 Eylul 2026:
KOMBINASYONEL BYPASS KALDIRILDI" diyor ve "onceki hali" olarak TAM
OLARAK bu satiri gosteriyor. Yani yorum yaniltici; kod
degistirilmemis. Bu, 10 Eylul'de sram_module.sv icin duzeltilen
hatanin NPU'daki karsiligidir ve HALA ACIKTIR.

### Onerilen duzeltme

    assign rdata_a = rdata_a_hold;
    assign rdata_b = rdata_b_hold;

Ek yazmac maliyeti YOK - rdata_*_hold zaten her cevrim yaziliyor
(satir 172-173).

BEDELI: NPU okumasina bir cevrim eklenir.

  - npu_compute_engine.sv:146-147 yorumuna gore motor zaten
    "SRAM -> rdata_q" asamasini bekliyor; pipeline yapisi var.
  - Cikarim cevrim sayisi artar, hizlanma orani (753x) bir miktar
    duser.
  - DOGRULANMASI ZORUNLU: npu_dogruluk, npu_golden, npu_blok,
    npu_hizlanma ve sistem testleri yeniden kosulmali; altin
    referansla byte-birebir eslesme korunmali.

BEKLENEN KAZANC (TAHMIN, olculmedi): 26 setup ihlali kalkarsa 20 ns'de
setup kapanabilir. Dogrulanmasi icin tam kosum gerekir.

## 2.2 Ikincil RTL/SDC kalemleri

  - gpio_i[3] -> _191507_/D hold ihlali (-0,022 ns): GPIO asenkron
    girisi. SDC'de gercek arayuz sozlesmesi tanimlanmali (dis giris
    -> ilk senkronizator D yolu). Su an 0,2xT ile senkron giris gibi
    modellenmis.
  - clk_i -> qspi_sck setup (-0,614 ns): cikis yolu.
    set_output_delay gercek kart/flash zamanlamasiyla tanimlanmali.


# 3. KONFIGURASYON SEVIYESI

## 3.1 KANITLANMIS - degistirilmemeli

| Ayar | Deger | Gerekce |
|------|-------|---------|
| RUN_POST_GRT_DESIGN_REPAIR | false | LibreLane varsayilani. true iken RSZ-0090 ile akis oluyor. Olculdu: bu adim C ve G'de calisti ama imza slew'ine net katkisi ~%7; 17 bin ihlal yine kaldi. |
| GRT/DRT_ANTENNA_REPAIR_DIODE_ONLY | true | GRT-0183 jumper bugunu onler. K'da anten 0/0 ile kapandi. |
| CLOCK_PERIOD (PnR) | 14 ns | 10 ve 12 ns tikaniklik uretti (D_hold oldu, L_12ns durduruldu). 23 ns ise akisi gevsetip sonucu BOZDU (M_tek23). |

## 3.2 M_tek23 DERSI - PnR hedefi imza hedefine ESITLENMEMELI

Ayni 23 ns periyotta olculen iki kosum:

    K_diyot (PnR 14 ns) max_ss: setup +0,397  hold +1,182
    M_tek23 (PnR 23 ns) max_ss: setup -6,387  hold -1,377

Tampon sayilari neredeyse ayni (CTS 1659/1666, repair 26557/26678),
yani yapisal fark yok. Fark OPTIMIZASYON BASKISINDA: gevsek PnR
hedefi akisi az calistiriyor.

asic/README.md'deki ilke dogrulandi:
"Tek SDC'yi iki rol icin kullanmak dogru degildir."

## 3.3 DENENMEMIS - olculebilir adaylar

| Ayar | Su an | Aday | Hedef | Risk |
|------|-------|------|-------|------|
| CTS_SINK_CLUSTERING_SIZE | varsayilan | kucult | skew | orta |
| CTS_CLK_BUFFERS | 8/4/2 | buyut | saat gecikmesi | orta |
| PL_TARGET_DENSITY_PCT | 45 | 40 | tikaniklik payi | dusuk |
| GRT_ADJUSTMENT | 0.3 | 0.2 | yonlendirme kapasitesi | dusuk |
| DPL_CELL_PADDING | 0 | 1-2 | yonlendirilebilirlik | orta |
| CTS_MACRO_CLUSTERING_SIZE | null | 2 | makro/register asimetrisi | OLCULEMEDI |

Son satir: M_tek23'te denendi ama saat hedefi degisikligi baskin
ciktigi icin etkisi AYRISTIRILAMADI. Tek degiskenli tekrar gerekir.

## 3.4 Slew / cap / fanout icin

Bu uc kalem buyuk olcude MAKRO KAYNAKLIDIR:

  - SRAM Liberty'sinde bus(addr0), bus(addr1), bus(wmask0) icin
    max_transition 0.04 ns; sky130 std hucre en iyi 0.043 ns
    yapabiliyor -> ERISILEMEZ hedef (RSZ-0090'in sebebi).
  - Karakterizasyon araligi index_1 = "0.00125, 0.005, 0.04";
    yani 0.04 modelin GECERLILIK SINIRIDIR. Bu degeri buyutmek
    ekstrapolasyon olur, guvenilmez.

Yapilabilecekler:

  a) Makro giris pinlerini suren mantigi guclendirmek (daha buyuk
     surucu, daha kisa tel). Yerlesim etkisi olculmeli.
  b) Dogrulanmis Liberty temini veya karakterizasyon araligini
     genisleterek modeli yeniden uretmek (OpenRAM akisi gerekir).
  c) Fanout icin: K'da 81, C'de 66. Fark, atlanan adim 41'in
     bedeli. MAX_FANOUT_CONSTRAINT 16; sentezde fanout dagitimi
     zorlanabilir.


# 4. ONCELIK SIRASI (getiri / risk)

1. NPU SRAM bypass'ini kaldir (RTL, iki satir)
   Getiri: 28 ihlalin 26'si. En yuksek getirili tek degisiklik.
   Risk: NPU cevrim sayisi artar; tum NPU testleri + altin referans
   dogrulanmali.

2. SDC arayuz sozlesmelerini gerceklestir
   GPIO asenkron giris, QSPI cikis gecikmesi. Kalan iki ihlali
   hedefler. Risk dusuk; gercek kart/flash zamanlamasi bilinmeli.

3. CTS_MACRO_CLUSTERING_SIZE=2'yi TEK DEGISKENLI olc
   K_diyot yapilandirmasi + yalniz bu ayar. Risk dusuk, geri
   alinabilir.

4. Yerlesim gevsetme (PL_TARGET_DENSITY 45->40, GRT_ADJUSTMENT
   0.3->0.2). Tikaniklik payi artar; daha siki saat hedefleri
   denenebilir hale gelebilir. Risk dusuk; alan zaten bol
   (utilization %49,5).

5. Makro Liberty'si - en dogru ama en pahali; yukaridakiler yetmezse.


# 5. NE YAPILMAMALI

  - PnR hedefini imza hedefine esitlemek (M_tek23 kaniti).
  - Makro max_transition'i SDC istisnasiyla buyutmek
    (karakterizasyon sinirinin otesine ekstrapolasyon).
  - RUN_POST_GRT_DESIGN_REPAIR'i true yapmak (RSZ-0090 ile akis
    oluyor; kazanci olculdu ve kucuk).
  - Ayni kosumda birden cok degisken degistirmek (M_tek23'te iki
    degisken degisti ve makro kumeleme etkisi olculemedi).
