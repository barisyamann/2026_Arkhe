# Deney: NPU agirliklari olmadan akis - 21/22 Agustos 2026

**Bu bir OLCUM kosumudur, teslim degildir.** `fc_weights` tablosu stub'dir;
NPU cop hesaplar. Amac tek bir degiskenin fiziksel tasarima etkisini
olcmektir.

---

## Neden yapildi

Alti ASIC kosumu detayli yonlendirmede takildi. 6. kosumda global
yonlendirme **2 saat 48 dakikada bitmedi** ve durduruldu. Log 0 bayt
kaldigi icin ic durum gorulemedi.

Supheli: `fc_weights` ROM'u (16.000 x 8 bit = 128 kbit). Kritik yol
raporunda adres bitinin fanout'u **4.694** olcuulmustu.

Ama bu bir hipotezdi. Olcmek gerekiyordu.

---

## Deney tasarimi

`NPU_WEIGHTS_STUB` tanimi yalnizca **65.536 bitten buyuk** tablolari devre
disi birakir. Bu esigi asan TEK tablo `fc_weights`.

| Tablo | Boyut | Deneyde |
|---|---|---|
| **`fc_weights`** | **128.000 bit** | **stub** |
| `dw_weights` | 5.120 bit | gercek |
| `softmax_exp_lut` | 3.328 bit | gercek |
| biaslar | 384 bit | gercek |
| `boot.hex` | 8.192 bit | gercek |

Stub, adres bagimliligini koruyan ucuz bir deger dondurur:

    function automatic logic signed [7:0] fc_weights(input logic [13:0] i);
        return 8'(i);
    endfunction

Boylece veri yolu canli kalir (carpici ve boru hatti optimize edilip
silinmez), yalnizca ROM ve adres cozucusu gider.

Ayri config kullanildi (`config_deney_stub.yaml`); teslim yapilandirmasina
dokunulmadi.

---

## SONUC - hipotez dogrulandi

| Adim | Gercek agirliklar | **Stub** | Fark |
|---|---|---|---|
| Sentez | 42:42 | **04:52** | -%89 |
| Sentez hucresi | 109.963 | **67.422** | -%39 |
| Global yerlestirme sonrasi | 223.456 | **180.915** | -%19 |
| **Onarim (repairdesignpostgpl)** | **2:00:44** | **08:02** | **-%93** |
| CTS sonrasi | 247.044 | 189.730 | -%23 |
| **Global yonlendirme** | **2:48:00 BITMEDI** | **01:26** | - |
| Detayli yonlendirme | hic ulasilamadi | **44:51, 0 IHLAL** | - |

Iki sayi belirleyici:

**Global yonlendirme 2 sa 48 dk'da bitmiyordu; agirliklar cikinca
1 dakika 26 saniye.**

**Onarim adimi 2 saat suruyordu; 8 dakikaya dustu.** Bu adim yuksek
fanout aglarina tampon agaci kurar - `fc_idx` ROM adres cozucusu o iki
saatin neredeyse tamamini yiyormus.

### Sikisiklik - hic overflow yok

    li1     %0,00    0
    met1   %18,95    0
    met2   %18,31    0
    met3   %11,31    0
    met4    %8,74    0
    met5    %5,31    0

### Detayli yonlendirme temiz

    [INFO DRT-0199]   Number of violations = 0.
    [INFO DRT-0198] Complete detail routing.
    soc_top.drc: 0 bayt

---

## Akisin ulastigi nokta

Ilk kez GDSII'ye varildi.

| Adim | Sure | Sonuc |
|---|---|---|
| 44 detayli yonlendirme | 44:51 | 0 DRC isareti |
| 54 RCX (parazitik) | 01:12 | SPEF uretildi |
| 55 **STAPostPNR** | 53:42 | **9 kose** (3 PVT x min/nom/max) |
| 56 IR-drop | 05:10 | `irdrop.rpt`, `net-VPWR.csv`, `net-VGND.csv` |
| 57 Magic streamout | 01:52 | `soc_top.gds` 330 MB |
| 58 KLayout streamout | 00:10 | `soc_top.klayout.gds` 184 MB |
| 59 KLayout render | **DUSTU** | bkz. asagi |

**IR-drop meselesi cozuldu:** `OpenROAD.IRDropReport` akista zaten vardi
(`RUN_IRDROP_REPORT` varsayilani True). Daha once o adima hic
ulasilamamisti.

---

## ACIK SORUN - 59. adimda dusus

    QObject::startTimer: Timers can only be used with threads started with QThread
    The layout has multiple top cells in Layout.top_cell

`KLayout.Render` GDS'te birden fazla ust hucre buldu ve akis durdu.

**Etkisi ciddi:** render'dan SONRA gelen adimlar kosamadi:

    Magic.WriteLEF
    KLayout.XOR / Checker.XOR
    Magic.DRC / KLayout.DRC
    Magic.SpiceExtraction
    Netgen.LVS

Yani sartnamenin zorunlu tuttugu **DRC, LVS ve XOR raporlari uretilemedi.**

**Muhtemel sebep:** 23 SRAM makrosunun GDS'leri tasarim GDS'ine gomulurken
kendi baslarina ust hucre olarak kaliyor olabilir.

`KLayout.Render` sartnamenin ZORUNLU listesinde degil - urettigi goruntu
"onerilen ek ciktilar" (Bolum 6.3) arasinda. Gerekirse atlanabilir; ancak
once sebebin anlasilmasi gerekir, cunku ayni yapisal sorun DRC ve LVS'yi
de etkileyebilir.

**Sonraki adim:** GDS hiyerarsisini inceleyip kac ust hucre oldugunu ve
hangilerinin oldugunu cikarmak.

---

## Cikarilan karar

`fc_weights` **SRAM makrosuna tasinmalidir.**

20 Agustos'ta "alan sigiyor, mantik olarak birakalim" denmisti. O karar
eksikti: alana bakildi, YONLENDIRILEBILIRLIGE bakilmadi. Bu deney o
eksigi kapatti.

| | Mantik | SRAM'e tasima |
|---|---|---|
| Sentez hucresi | 109.963 | ~70.000 |
| Yuksek fanout ag | 4.694 | yok (makro pini) |
| Onarim suresi | 2 saat | ~10 dk |
| Ek makro | 0 | +8 (toplam 31) |
| Die | 16,28 mm2 | ~19 mm2 |

SRAM'de adres cozucu **makronun icindedir**; disarida dev tampon agaci
gerekmez.

---

## Kanit dosyalari

    evidence/asic/ara_sonuclar/deney_stub/
        adim_sureleri.txt              adim adim sureler
        openroad-globalrouting.log     sikisiklik raporu
        soc_top.drc                    0 bayt - temiz yonlendirme
        irdrop.rpt                     IR-drop analizi
        klayout-render.log             dusus sebebi
        sta-nom_tt/                    9 koseden birinin tam raporlari
