# Ikinci inceleme raporunun dogrulanmasi (10 Eylul 2026)

Dis bir inceleme raporu geldi. Her iddiasi kurulu arac ve kendi
loglarimiz uzerinden sinandi. Sonuc: **ana tezi dogru ve degerli,
iki teknik iddiasi yanlis.**

## DOGRULANAN 1: `-repair_clock_nets` gercekten var ve kullanilmiyor

Kurulu OpenROAD'a soruldu:

    $ echo "help clock_tree_synthesis" | openroad -no_splash
    clock_tree_synthesis [...] [-library] [-repair_clock_nets]
                                          [-no_insertion_delay]

Secenek MEVCUT. LibreLane `scripts/openroad/cts.tcl`:

    satir 89:  log_cmd clock_tree_synthesis {*}$arg_list     <- secenek YOK
    satir 96:  repair_clock_nets -max_wire_length ...        <- AYRI cagri

Rapor hakli: bu ikisi ayni sey degil. CTS ici onarim latency
ayarlamasindan ONCE saat aginda calisir; bagimsiz komutun kapsami
clock girisinden root buffer'a kadar olan teldir.

## DOGRULANAN 2 (EN ONEMLI): SKEW, HOLD IHLALINDEN BUYUK

Raporun "saat agina oncelik ver" tezi kendi metriklerimizle
dogrulandi. C_kapanis final/metrics.json:

| Kose             | Hold skew | Hold WNS | Skew/WNS |
|------------------|-----------|----------|---------:|
| max_ss_100C_1v60 |   -3,622  |  -0,320  |     11 x |
| nom_ss_100C_1v60 |   -3,257  |  -0,011  |    291 x |
| min_ss_100C_1v60 |   -3,023  |   0,000  |        - |
| max_tt_025C_1v80 |   -2,170  |  -0,653  |    3,3 x |
| nom_tt_025C_1v80 |   -1,793  |  -0,356  |    5,0 x |
| max_ff_n40C_1v95 |   -1,640  |  -0,646  |    2,5 x |
| min_ff_n40C_1v95 |   -1,118  |  -0,228  |    4,9 x |

Saat skew'i her kosede hold ihlalinden 2,5-291 KAT buyuk. Yani hold
ihlalleri, saat agi dengesizliginin kucuk bir artigidir.

BU BENIM ONCEKI TESHISIMI KISMEN CURUTUR. "Hold problemi tampon
butcesi tukendigi icin acik kaldi" tespiti adim-ici mekanizma olarak
dogruydu (26360 setup tamponuna karsi 5 hold tamponu olculdu), ama
KOK NEDEN degildi. Tampon eklemek semptomu kovalamaktir; skew
duzelmeden hold saglam kapanmaz.

Skew'in ss koselerinde (-3,0 ... -3,6) tt/ff'ye gore ikiye
katlanmasi da saat agi sorununa isaret eder: yavas silikonda dallar
arasi fark buyuyor.

## YANLIS 1: "GRT kapatma beklenen seyi yapmiyor"

Rapor, `rsz_timing_postgrt.tcl` basindaki GRT cagrisinin kosulsuz
oldugunu (satir 28-30 yorumlanmis) dogru tespit etmis, ama D'nin
LOGUNU KONTROL ETMEMIS. D_hold adim 44:

     18  + global_route   -> Total ... 20,09%   0 / 0 / 0   TEMIZ
   1077  + global_route   -> Total ... 19,94%   0 / 1 / 1
   2178  [ERROR GRT-0116]
   2179  Error: rsz_timing_postgrt.tcl, 68 GRT-0116
                                        ^^^^

Hata SATIR 68'de, yani script'in satir 66-68'deki KOSULLU blogunda:

    66  if { $::env(GRT_RESIZER_RUN_GRT) } {
    67      source .../grt.tcl
    68  }

Ilk (kosulsuz) GRT temiz gecti: 0/0/0. Dolayisiyla
`GRT_RESIZER_RUN_GRT=false` D'nin aldigi hatayi GERCEKTEN onlerdi.

Yine de raporun uyarisi yerinde: hata mesajini susturmak kapanis
sayilmaz. Bu ayar bir tani araci olarak kullanilmali, kok neden
(skew) ayrica cozulmeli.

## YANLIS 2: "F belirsiz sekilde sonlandi"

F_saglam sentezde kesildi cunku KULLANICI "bekle, bir sey baslatma"
dedi ve ben `pkill` ile durdurdum. Log'da sebep gorunmemesinin
nedeni budur; arac hatasi degil. Rapor bunu bilemezdi.

## KISMEN DOGRU: GRT-0183 tanisi

Rapor issue #10156/#10273'u ve PR #10711'in halen Open oldugunu
gosteriyor; "aracı guncelle, kesin cozulur" onerisinin
desteklenmedigi uyarisi HAKLI. Ben daha once PR #10743'un
2026-06-24'te merge edildigini soylemistim; bunu tek bir arama
sonucuna dayandirmistim ve merge durumunu dogrudan dogrulamadim.
Dolayisiyla "bilinen ve duzeltilmis hata" ifadem fazla kesindi.

Kesin olan: bizim OpenROAD commit'i dcf36133 (2026-02-17) ve bu
hata anten/diyot/jumper yogunlugunda tetikleniyor. diode-only
denemesi hala mantikli bir TEK DEGISKEN deneyidir, ama garanti
degildir.

## GUNCELLENMIS SIRA

1. CTS ici `-repair_clock_nets` deneyi (izole custom step).
   Once saat agi cap/slew, skew, setup/hold olc.
2. Skew duzelmezse makro kume boyutu 4 -> 2 -> 1, tek degisken.
3. Hold margin/tampon limitleri EN SON - skew olculdukten sonra.
4. diode-only anten deneyi, E'nin basarisiz state'inden.

Not: LibreLane'de `-repair_clock_nets` icin config anahtari YOK
(cts.tcl'de karsiligi bulunmuyor). Nix store'daki script
DEGISTIRILMEMELI; izole bir custom step gerekir.
