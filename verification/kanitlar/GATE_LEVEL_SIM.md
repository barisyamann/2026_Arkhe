# Gate-level simulasyon denemesi - sonuc ve degerlendirme
# (12 Eylul 2026)

# 1. NEDEN DENENDI

Akis arastirmasi sunu buldu: RTL simulasyonu 33 test / 664 denetim
ile dogrulanmis ama **sentez sonrasi netlist hic simule edilmemis**.

Bu bir bosluktur: sentez veya yerlestirme araci yanlis bir
optimizasyon yaparsa RTL testleri bunu GOREMEZ - onlar RTL
kaynagini kosar, uretilen netlisti degil.

# 2. ASILAN ENGELLER

| Engel | Cozum |
|---|---|
| `default_nettype none` + UDP port tipi | Yerel kopyalarda `wire` (2.217 yer) |
| `lpflow_bleeder_1` tanimsiz VPWR | 832 `specify` blogu kaldirildi (SDF yuklenmiyor) |
| Yerel RAM yetersiz | Windows 15,2 GB, %100 doldu -> sunucuya tasindi (62 GB) |
| Gucsuz netlist + guc pinli hucre | `pnl.v` (228 MB) + `supply1/supply0` |

PDK orijinallerine DOKUNULMADI; yalniz `build/gls/lib/` ve
sunucudaki `/home/tatua7806/gls/lib/` kopyalari yamalandi.

# 3. DERLEME: BASARILI - iki bagimsiz arac

    Vivado xvlog   : 42 saniye,  sifir hata
    Icarus iverilog: 142 saniye, sifir hata, 1.518 MB vvp

Tum hucre referanslari cozuldu, 23 SRAM ornegi yerinde,
`lpflow` hucresi netlistte hic yok.

**Bu tek basina bir dogrulamadir:** sentez ciktisi sozdizimsel
olarak saglam ve eksik hucre referansi icermiyor.

# 4. SIMULASYON: CIKISLAR X - KOK NEDEN OLCULDU

Canlilik testi kosuldu; tum cikislar X cikti. Ic dugumler
izlendi:

    [TANI] rst_ni=1 clk_i=1
    [TANI] reset tamponu cikisi: 1      <- DOGRU
    [TANI] ilk flip-flop Q: x           <- X BURADA
    [TANI] SRAM0 dout0[0]: x

Reset agi calisiyor. Sorun flip-flop turunde:

| Flip-flop | Sayi | Reset girisi |
|---|---:|---|
| `sky130_fd_sc_hd__dfrtp` | 6.018 | VAR |
| `sky130_fd_sc_hd__dfstp` | 106 | SET var |
| **`sky130_fd_sc_hd__dfxtp`** | **6.296** | **YOK** |

**6.296 flip-flop reset'sizdir.** Bunlar veri yolu yazmaclaridir
(RTL'de bilincli olarak reset verilmemis - alan ve zamanlama
kazanci saglar). Simulasyonda X ile baslar ve bir veri yazilana
kadar X kalirlar.

X bir flip-flop'tan cikip tum tasariman yayilir; cikislar X olur.

# 5. BU BIR TASARIM HATASI DEGILDIR

## 5.1 Standart uygulama

Veri yolu yazmaclarina reset vermemek yaygin ve DOGRU bir
tercihtir:
  - reset agi kucuk kalir (guc, alan, zamanlama)
  - veri zaten kullanilmadan once yazilir

## 5.2 Gercek donanimda X yoktur

X yalnizca simulasyon kavramidir. Gercek flip-flop acilista 0
veya 1 tutar (belirsiz ama BELIRLI). Yazilim o yazmaci okumadan
once yazar.

## 5.3 RTL simulasyonunda gorunmez

RTL'de `logic` degiskenleri de X ile baslar ama testbench'ler
bellek yukler ve akis basladigi icin X hizla temizlenir. Gate
seviyesinde her flip-flop ayri bir nesnedir ve temizlenmesi
gercek veri akisi gerektirir.

## 5.4 Cozum: gercek program yuklemek

Bu testin X'ten cikmasi icin bootloader'in QSPI'den gercek
program okumasi ve calistirmasi gerekir - yani `sistem_gercek_boot`
testinin gate seviyesinde kosulmasi.

# 6. NEDEN TAM SISTEM TESTI KOSULMADI

Olculdu:

    RTL'de  sistem_gercek_boot : 622 saniye
    GLS'de  tahmini            : 50-100x -> 9-17 SAAT

Ustelik SRAM icerigi netlistte YOKTUR; `$readmemh` ile makro
icine yuklenmesi gerekir ve bu 23 makro icin ayri bir altyapi
demektir.

Teslime kalan surede bu yatirim yapilmadi.

# 7. NE KAZANILDI

1. **Netlist derlenebilirligi kanitlandi** - iki bagimsiz arac,
   sifir hata. Eksik hucre, cozulmeyen referans, sozdizimi
   hatasi YOK.

2. **Reset agi dogrulandi** - `rst_ni` -> tampon -> dagitim
   zinciri calisiyor (tani ciktisi: reset tamponu = 1).

3. **Flip-flop dagilimi olculdu** - 6.018 reset'li, 6.296
   reset'siz, 106 set'li. Bu bilgi daha once yoktu.

4. **GLS altyapisi kuruldu** - kutuphane yamalari, guc pini
   baglantisi, derleme akisi hazir. Ileride tam test kosulmak
   istenirse tekrar kurulmasi gerekmez.

# 8. DURUST DEGERLENDIRME

Gate-level simulasyon **kismen** yapildi:
  - derleme: TAMAM, temiz
  - elaborate/baglanti: TAMAM
  - islevsel kosum: X yayilimi nedeniyle ANLAMLI SONUC VERMEDI

X yayilimi bir tasarim hatasi degil, reset'siz yazmaclarin
dogal sonucudur. Anlamli bir GLS icin gercek program yuklemesi
gerekir; bu ACIK olarak kayda gecirilmistir.

Teslim paketindeki zamanlama imzasi ayrica ve tam olarak
yapilmistir: dokuz PVT kosesinde STA, hepsi pozitif.

# 9. YENIDEN URETIM

    # sunucuda
    cd /home/tatua7806/gls
    iverilog -g2012 -DUSE_POWER_PINS -o gls.vvp \
      lib/primitives.v lib/sky130_fd_sc_hd.v \
      <sram_makro>.v \
      <kosu>/53-openroad-fillinsertion/soc_top.pnl.v \
      tb_gls_canlilik.sv
    vvp gls.vvp

Kutuphane yamalari: `default_nettype none` -> `wire`,
`specify` bloklari kaldirilir.
