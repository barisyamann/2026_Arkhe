# Spike ISS karsilastirmasi - 13 Eylul 2026 (HEAD)

Bu kosum **guncel HEAD** uzerinde alinmistir. Onceki kanit
(`evidence/spike_20260910`) 10 Eylul tarihlidir; 12-13 Eylul'de RTL ve
test tarafinda degisiklik yapildigi icin yenilenmistir.

## Uretim

```bash
python3 scripts/spike_iz_al.py        # Spike izi  (WSL, spike PATH'te)
python  scripts/run_regression.py --test cekirdek_izi   # RTL izi
python3 scripts/spike_karsilastir.py  # karsilastirma
```

Kullanilan ELF: `sw_nexys/build/core_test/core_test.elf`
Spike surumu: nix-profile (`~/.nix-profile/bin/spike`), `rv32imc`

## Sonuc

| Olcut | Deger |
|---|---|
| Karsilastirilan buyruk | **927** |
| PC uyusmazligi | **0** |
| Makine kodu uyusmazligi | **0** |
| Yazmac karsilastirilan | **765** |
| Yazmac NO uyusmazligi | **0** |
| Yazmac DEGER uyusmazligi | **0** |

`SONUC: 927 buyrukta PC dizisi BIREBIR ESLESTI.`

## Hata OLMAYAN farklar

**432 sikistirilmis buyrukta makine kodu gosterimi farkli.** Spike ham
16-bit RVC kodunu, CV32E40P tracer'i ise ACILMIS 32-bit karsiligini
raporlar. Ayni buyruk, farkli gosterim; PC esitligi dogru cozuldugunu
kanitlar.

**3 platform kimlik CSR farki:**

| # | PC | CSR | Spike | CV32E40P |
|---|---|---|---|---|
| 477 | `010002f4` | `mvendorid` | `0x0` | `0x602` |
| 481 | `01000302` | `marchid` | `0x5` | `0x4` |
| 489 | `0100031e` | `misa` | `0x40141104` | `0x40001104` |

Spike genel bir RISC-V modelidir; CV32E40P OpenHW Group cekirdegi kendi
vendor/arch kimligini raporlar. `misa` farki da beklenendir (Spike
`rv32imc` ile kosuldu).

## Dosyalar

| Dosya | Icerik |
|---|---|
| `spike_iz.txt` | Spike ISS izi (932 ham buyruk) |
| `rtl_iz.log` | CV32E40P RTL tracer cikti |
| `karsilastirma.txt` | Karsilastirma raporunun tam cikti |

**Ham 932 / karsilastirilan 927 farki:** Spike izi bootrom'dan baslar;
karsilastirma ortak baslangic PC'sinden itibaren yapilir.
