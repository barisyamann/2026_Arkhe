# ASIC Olcum Gecmisi - SKY130A / LibreLane Classic

Ust modul: `soc_top` · Hedef saat: 50 MHz (20 ns) · PDK: sky130A
Standart hucre kutuphanesi: `sky130_fd_sc_hd`

---

## a1 - Ilk basarili sentez (20 Agustos 2026)

Ilk kez ASIC sentezine ulasildi. Onceki denemeler SRAM makrosu olmadigi
icin tamamlanamiyordu.

| Metrik | Deger |
|---|---|
| Standart hucre | 47.926 |
| Standart hucre alani | 0,631 mm2 |
| SRAM makrosu | **23** |
| Makro alani | 6,54 mm2 (23 x 0,285) |
| **Toplam cekirdek alani** | **~7,17 mm2** |
| Flip-flop | 10.908 |
| Lint hatasi | 0 |
| Lint uyarisi | 810 |

### Flip-flop dususu

    SRAM makrosu ONCESI : ~391.000  (butun bellekler cikarimsal dizi)
    SRAM makrosu SONRASI:   10.908

Makro entegrasyonu oncesinde Yosys/ABC 391 bin flip-flop uzerinde
calisiyordu ve sentez bir saatten fazla surede tamamlanamadi. Bu bir
performans sorunu degil, ASIC'te bellegin cikarimsal dizi olarak
birakilamayacaginin dogrudan kanitidir.

### En cok kullanilan hucreler

| Hucre | Adet | Pay |
|---|---|---|
| `sky130_fd_sc_hd__mux2_1` | 10.163 | %21,2 |
| `sky130_fd_sc_hd__dfxtp_2` | 5.748 | %12,0 |
| `sky130_fd_sc_hd__dfrtp_2` | 5.160 | %10,8 |
| `sky130_fd_sc_hd__a22o_2` | 2.762 | %5,8 |
| `sky130_fd_sc_hd__a21o_2` | 2.011 | %4,2 |

**mux2_1 hakimiyeti dikkat cekici** - tum hucrelerin besde biri.

Kaynagi bellek okuma coklayicilaridir: TCM'de 15 makro arasindan,
I-RAM ve D-RAM'de 4'er makro arasindan 32 bit genisliginde secim
yapiliyor. Kabaca:

    TCM   : 32 bit x 15 giris x 2 port
    I-RAM : 32 bit x  4 giris
    D-RAM : 32 bit x  4 giris

Bu, coklu makro kullanmanin kacinilmaz bedeli. Azaltmak icin daha az
sayida buyuk makro gerekirdi, ancak sky130'da 2 kB en buyuk 32-bit
genisligindeki secenek.

Optimizasyon dusunulurse: TCM'in ust adres bitleriyle makro secimi
yerine, coklayiciyi agac yapisina bolmek veya okuma yolunu boru hattina
almak degerlendirilebilir. Su an oncelik akisi tamamlamak.

---

## SRAM makrosu

| | |
|---|---|
| Makro | `sky130_sram_2kbyte_1rw1r_32x512_8` |
| Kaynak | SKY130A PDK, `libs.ref/sky130_sram_macros/` |
| Yapi | 512 kelime x 32 bit, Port0 RW + Port1 R |
| Fiziksel boyut | 683,1 x 416,54 um = 0,285 mm2 |
| Zamanlama modeli | TT_1p8V_25C (tek kose) |

Dagilim:

| Bellek | Kapasite | Makro |
|---|---|---|
| NPU TCM | 30 kB | 15 |
| I-RAM | 8 kB | 4 |
| D-RAM | 8 kB | 4 |

### Sartname dogrulamasi

> "SRAM makrosu sentez sonucunda optimize edilerek kaldirilmamali;
>  nihai gate level netlist, DEF ve GDSII ciktilarinda bulunmalidir."

Sentez netlist'inde dogrulandi:

    grep -c "sky130_sram_2kbyte_1rw1r_32x512_8" soc_top.nl.v
    23

DEF ve GDSII dogrulamasi akis tamamlandiginda yapilacak.

---

## Akisa ulasirken asilan engeller

Sentez adimina varmak sekiz ayri duzeltme gerektirdi. Ucu **gercek RTL
hatasiydi** ve aylardir kodda duruyordu; FPGA akisi hicbirinde
sikayet etmemisti.

| # | Sorun | Yakalayan |
|---|---|---|
| 1 | `VERILOG_FILES_FILE` diye anahtar yok | LibreLane |
| 2 | `--force-run-dir` dizini kendi olusturmuyor | LibreLane |
| 3 | Bozuk `ifdef` direktifi (backtick + bosluk) | **Verilator** |
| 4 | `sum_exp`'te bloklayan/bloklamayan atama karisimi | **slang** |
| 5 | Makro guc pinleri sabite baglanmis (elektriksel kisa) | **Verilator** |
| 6 | Makro modelinde `mem` bildiriminden once kullanim | Vivado |
| 7 | Makro modeli STA'da netlist saniliyor | OpenSTA |
| 8 | `remove_from_collection` OpenSTA'da yok | OpenSTA |

3, 4 ve 5 numaralilar Vivado'nun sessizce kabul ettigi gercek
kusurlardi.

---

## Acik maddeler

- **PVT koseleri**: akis uc kosede (tt/ff/ss) zamanlama yapiyor ama
  makronun yalnizca TT modeli var; uc kosede de ayni model okunuyor.
- **Saat kapisi**: `cv32e40p_sim_clock_gate.sv` simulasyon modelidir,
  PDK hucresiyle degistirilmelidir.
- **810 lint uyarisi** incelenmedi.
- **Dosya sistemi**: akis `/mnt/c` uzerinden kosuyor; yerlestirme ve
  yonlendirme icin WSL'in kendi diskine tasinmasi gerekebilir.
