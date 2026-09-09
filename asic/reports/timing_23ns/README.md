# Ek imzalama STA — 23 ns

Aynı d45_anten2 layout'u, **hiçbir fiziksel değişiklik yapılmadan**, farklı bir
imzalama saat periyoduyla yeniden analiz edildi. Sonuç: 23 ns (43,5 MHz)
periyotta **setup 9/9 köşede pozitif, 0 ihlalli yol**; hold 9/9 köşede pozitif
kalır.

## Bu ne DEĞİLDİR

Özgün koşunun yerine geçmez. `../timing/` altındaki 127 rapor d45_anten2'nin
**20 ns imzalamasının özgün akış çıktısıdır** ve olduğu gibi korunmuştur; o
periyotta üç SS köşesinde 115 ihlalli yol vardır ve bu gizlenmemiştir.

Yeni bir yerleştirme, yönlendirme veya optimizasyon yapılmamıştır. Yalnızca
zamanlama analizi tekrarlanmıştır. GDS, netlist, DRC, LVS, anten sonuçları ve
slew/kapasite/fanout sayıları değişmez — imzalama periyodu bunları etkilemez.

## Girdiler

Hepsi bu teslim paketinden alınmıştır, hiçbiri yeniden üretilmemiştir:

| Girdi | Yol |
|---|---|
| Netlist | `../../results/netlist/soc_top_pnr.v` |
| Parazitikler | `../../results/spef/{min,nom,max}/` |
| Zamanlama kütüphaneleri | sky130_fd_sc_hd (köşeye göre) + SRAM makro lib |
| Teknoloji/hücre LEF | sky130 techlef + std hücre + SRAM makro |

Kısıtlar `../../../constraints/signoff_50mhz_hedef.sdc` ile aynıdır: setup
belirsizliği 0,25 ns, hold belirsizliği 0,10 ns, saat geçişi 0,15 ns, JTAG
saati 100 ns ve ana saatle asenkron grup. Yalnızca `create_clock` periyodu
farklıdır.

## Periyot taraması — en kötü köşe (`max_ss_100C_1v60`)

| Periyot | Setup WNS | İhlalli yol |
|---:|---:|---:|
| 20,0 ns | −1,8149 ns | 115 |
| 22,0 ns | −0,4190 ns | 3 |
| 22,5 ns | −0,1691 ns | 1 |
| **23,0 ns** | **+0,0810 ns** | **0** |
| 24,0 ns | +0,5809 ns | 0 |

Tarama neden gerekliydi: WNS −1,8149 ns olduğu için 22 ns (+2,0 ns) yeterli
**görünüyordu**, ancak gerçek ölçüm −0,419 ns verdi. En kötü yolun kayması tek
başına belirleyici değildir; ara yollar da hesaba girer. Bu yüzden tahminle
yetinilmemiş, ölçüm yapılmıştır.

## Dokuz köşe — 23 ns

| Köşe | Setup WNS | Setup ihlal | Hold WNS | Hold ihlal |
|---|---:|---:|---:|---:|
| nom_tt_025C_1v80 | +4,9822 | 0 | +0,3204 | 0 |
| nom_ss_100C_1v60 | +0,5975 | 0 | +0,7504 | 0 |
| nom_ff_n40C_1v95 | +6,6872 | 0 | +0,1648 | 0 |
| min_tt_025C_1v80 | +5,5667 | 0 | +0,3196 | 0 |
| min_ss_100C_1v60 | +1,4208 | 0 | +0,7484 | 0 |
| min_ff_n40C_1v95 | +7,1483 | 0 | +0,1642 | 0 |
| max_tt_025C_1v80 | +4,4985 | 0 | +0,3195 | 0 |
| **max_ss_100C_1v60** | **+0,0810** | **0** | +0,7506 | 0 |
| max_ff_n40C_1v95 | +6,2395 | 0 | +0,1643 | 0 |

## Yeniden üretme

```bash
export PKG=<teslim paketi kökü>
export PDK=<open_pdks sky130 kökü>
export PERIOD=23.0
export CORNER=max_ss_100C_1v60
openroad -no_init -exit sta_tarama.tcl
```

`sta_tarama.tcl` bu dizindedir. Çıktı tek satırdır:
`SONUC|<köşe>|<periyot>|<setup WNS>|<setup TNS>|<setup ihlal>|<hold WNS>|<hold ihlal>`

Ham sonuç metni `sonuc.txt` içinde, aynı kayıt `evidence/asic/STA_23NS_20260909.txt`
altında da tutulur.

## Araç

OpenROAD (OpenSTA motoru), sürüm `dcf36133a369abc8f3c5e5738cd4d82e4903c0e0`,
9 Eylül 2026.
