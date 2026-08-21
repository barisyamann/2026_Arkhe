# Ucuncu Taraf Lisanslari

Bu dizin, tasarimda kullanilan ucuncu taraf RTL, PDK, makro ve arac
lisanslarini icerir. Bilesenlerin surum ve degisiklik bilgileri
`asic/THIRD_PARTY.md` dosyasindadir.

---

## Dosyalar

| Dosya | Kapsadigi bilesenler |
|---|---|
| `cv32e40p-LICENSE` | CV32E40P islemci cekirdegi, PULP common cells |
| `Apache-2.0.txt` | SKY130 PDK, SRAM makrosu, LibreLane |

---

## Bilesen - lisans eslesmesi

| # | Bilesen | Lisans | SPDX | Lisans dosyasi |
|---|---|---|---|---|
| 1 | CV32E40P (OpenHW Group) | Solderpad Hardware License v0.51 | `SHL-0.51` | `cv32e40p-LICENSE` |
| 2 | PULP Platform Common Cells | Solderpad Hardware License v0.51 | `SHL-0.51` | `cv32e40p-LICENSE` |
| 3 | SKY130 PDK (open_pdks) | Apache License 2.0 | `Apache-2.0` | `Apache-2.0.txt` |
| 4 | `sky130_sram_2kbyte_1rw1r_32x512_8` | Apache License 2.0 | `Apache-2.0` | `Apache-2.0.txt` |
| 5 | LibreLane | Apache License 2.0 | `Apache-2.0` | `Apache-2.0.txt` |

---

## Notlar

**Solderpad v0.51**, Apache License 2.0 tabanlidir; donanim tasarimlari
icin uyarlanmistir. Metnin kendisi bunu ilk paragrafta belirtir:

> "This license is based closely on the Apache License Version 2.0, but is
>  not approved or endorsed by the Apache Foundation."

`cv32e40p-LICENSE` dosyasi saticidan geldigi haliyle, degistirilmeden
kopyalanmistir (`rtl/cv32e40p-master/LICENSE`).

**Apache-2.0.txt** standart, degistirilmemis Apache License 2.0 metnidir.
SKY130 PDK ve LibreLane kurulumlari lisans metnini ayri bir dosya olarak
dagitmadigi icin metin standart kaynaktan alinmistir; iceriginde projeye
ozel hicbir degisiklik yoktur.

**Makro model degisiklikleri:** SRAM makrosunun Verilog modelinde uc
degisiklik yapilmistir (`mem` bildiriminin yukari tasinmasi, `VERBOSE`
varsayilaninin 0 yapilmasi, `/// sta-blackbox` isareti). Ucu de dosya
icinde yorumla isaretlidir ve `THIRD_PARTY.md` bolum 5'te belgelenmistir.
Apache 2.0 degisiklige izin verir; degisiklikler belirtilmistir.
