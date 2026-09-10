# H_yeniRTL erken olcum: duzeltme fiziksel olarak da ise yaradi
# (10 Eylul 2026, adim 12 - PnR oncesi STA)

Denetimin onerisi uygulandi: TAM KOSUM BEKLEMEDEN, sentez sonrasi
STA ile duzeltmenin etkisi olculdu.

## 1) BYPASS YOLU KESILDI  (asil soru)

`scripts/kritik_yol_kontrol.py` iki kosede de calistirildi:

    nom_ss_100C_1v60 -> SONUC: en kotu yol SRAM makrosundan gelmiyor
    nom_tt_025C_1v80 -> SONUC: en kotu yol SRAM makrosundan gelmiyor

G_saat'te ayni arac SU SONUCU vermisti:

    SONUC: SRAM -> CPU BYPASS YOLU HALA VAR
      makro cikisi: u_instruction_ram.g_sram[2].u_macro/dout
      CPU dugumu  : _131429_/D

Yani duzeltilmis sram_module.sv, denetimin gosterdigi
SRAM -> bank mux -> CPU ALU yolunu GERCEKTEN kesti. En kotu yol artik
saf register-to-register bir yol (_190605_ -> _180419_).

## 2) SETUP DOKUZ KOSEDE DE IYILESTI

Ayni adim (12-openroad-staprepnr), iki kosum yan yana:

| Kose             | G (10 ns, eski RTL) | H (14 ns, yeni RTL) | Fark    |
|------------------|--------------------:|--------------------:|--------:|
| nom_tt_025C_1v80 |            -5,4592  |            -1,0891  | +4,37   |
| nom_ss_100C_1v60 |           -17,1275  |           -13,2158  | +3,91   |
| nom_ff_n40C_1v95 |            +0,1114  |            +3,7415  | +3,63   |

Setup TNS (nom_tt): -20.662 -> **-2.389**, yaklasik 8,6 KAT iyilesme.
Toplam ihlal miktari, en kotu slack'ten daha cok duzeldi.

## 3) HOLD TEMIZ

    Hold Worst Slack : +0,1416 (overall)
    Hold TNS         : 0,0000
    Hold Vio Count   : 0        (dokuz kosede de)

G_saat'in imza STA'sinda hold dokuz kosenin altisinda ihlalliydi.
Burada henuz PnR/CTS yok, dolayisiyla bu SONUC DEGIL - ama kotu bir
baslangic da degil.

## OLCUMUN SINIRLARI (dogru okumak icin)

- Bu adim PnR ONCESIDIR: yerlesim, saat agaci ve gercek RC yok.
  Gecikmeler tahminidir. Setup ihlallerinin buyuk kismi yerlesim ve
  CTS'ten sonra kapanir.
- Iki kosum IKI DEGISKENDE farkli: RTL (bypass duzeltmesi) ve saat
  hedefi (10 -> 14 ns). Dolayisiyla yukaridaki iyilesmenin ne
  kadarinin RTL'den, ne kadarinin saat hedefinden geldigi bu tablodan
  AYRISTIRILAMAZ.
  Ancak (1) numarali bulgu tek degiskenlidir ve kesindir: kritik yolun
  SRAM'den gelip gelmedigi saat periyoduna bagli degildir.
- nom_ss kosesinde -13,2 ns hala buyuk bir acik. Bunun PnR sonrasi
  nereye gittigi izlenmelidir.

## SONUC

Denetimin en agir bulgusu (kosumlar eski RTL ile yapiliyordu)
duzeltildi ve duzeltmenin fiziksel etkisi OLCULDU. Kosu devam ediyor;
kesin hukum dokuz kose imza STA'sinda (adim 57) verilecek.

---

# H_yeniRTL COKTU - adim 41 (RSZ-0090)

    [RSZ-0090] Max transition time from SDC is 0.040ns.
    Best achievable transition time is 0.043ns with a load of 0.01pF

## KOK NEDEN: SRAM MAKROSUNUN LIB DOSYASI

Bizim SDC'miz 0,75 ns istiyor:

    set_max_transition 0.7500 [current_design]

Ama SRAM makrosunun Liberty dosyasinda:

    macros/sky130_sram_2kbyte_1rw1r_32x512_8/lib/*TT*.lib
        max_transition : 0.04;      <- UC pin grubunda (wmask, addr...)
        default_max_transition : 0.5;

Yani makro, GIRIS pinlerine 0,04 ns gecis suresi dayatiyor. sky130
standart hucre kutuphanesinin en iyi basarabildigi ise 0,043 ns.
Hedef FIZIKSEL OLARAK ERISILEMEZ.

Bu, daha once karsilastigimiz makro kaynakli kisitlarin ucuncusu:
  - nwell.4 DRC ihlalleri (7658, makro GDS icinden)
  - max_transition 0.5 (STA'da)
  - max_transition 0.04 (simdi, repair_design'i durduruyor)

## NEDEN C VE G GECTI DE H GECMEDI

Ayarlar birebir ayni (slew_margin 20, cap_margin 10 - config'ler
karsilastirildi). G ayni adimda 510 tampon ekleyip gecmisti.

Fark tasarimin kendisinde: duzeltilmis sram_module.sv okuma yolunu
kayitli hale getirdigi icin makro pinlerini suren mantik degisti.
Yeni bir yol o 0,04 ns'lik pinlere ulasiyor ve repair_design bunu
onarilamaz gorup durduruyor.

ONEMLI: Bu, duzeltmenin YANLIS oldugu anlamina GELMEZ. Kritik yol
olcumu (adim 12) bypass yolunun kesildigini, CTS sonrasi olcum
(adim 36) hem setup hem hold'un POZITIF oldugunu gosterdi:

    nom_tt adim 36:  setup +0,8637   hold +0,2641   skew -0,5456
    (G ayni adimda:  setup -0,5464   hold  0,0000   skew -0,7963)

Yani tasarim daha iyi durumda; akis bir MAKRO KISITINDA takildi.

## YONLENDIRME ZATEN TEMIZDI

Adim 41'in cokmeden onceki global yonlendirmesi:

    Total  6594686  1234425  18.72%   0 / 0 / 0
    Total wirelength: 10581881 um
    Routed nets: 116923

Tikaniklik YOK (0/0/0), kullanim %18,7. D_hold'u olduren sorun
burada yok.

## COZUM SECENEKLERI

1) `set_max_transition`'i makro pinleri icin ayri tanimlamak
   (SDC'de `-clock_path`/pin bazli istisna). En dogru yol ama
   makro pinlerini tek tek listelemek gerekir.
2) `GRT_DESIGN_REPAIR_MAX_SLEW_PCT`'i dusurmek - marj azalinca
   hedef gevser. Ama bu tum tasarimi etkiler.
3) Makro .lib'indeki 0.04 degerini duzeltilmis bir kopyayla
   degistirmek. Ucuncu taraf dosyasini degistirmek olur; teslimde
   beyan edilmeli.

Secenek 1 en temizi, 2 en hizlisi. Ikisi de OLCULEREK denenmeli.
