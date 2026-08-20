# Arkhe SoC - ASIC Fiziksel Tasarim Akisi

TEKNOFEST 2026 Cip Tasarim Yarismasi - Mikrodenetleyici Tasarim Kategorisi
Takim ARKHE

Bu dizin **yalnizca** ASIC fiziksel tasarim akisina ait girdi, yapilandirma,
otomasyon, calisma alani, rapor ve ciktilari icerir. Tasarim RTL kaynaklari,
islevsel dogrulama ve testbench dosyalari ile FPGA uygulamasina ozgu dosyalar
deponun diger bolumlerindedir:

    rtl/          tasarim RTL kaynaklari
    tb/           testbench'ler
    sw_nexys/     gomulu yazilim
    vivado/       FPGA projesi
    evidence/     olcum ve dogrulama kanitlari

---

## Tasarim

| | |
|---|---|
| Ust modul | `soc_top` |
| Cekirdek | OpenHW Group CV32E40P, RV32IMC (`FPU = 0`) |
| Veri yolu | AMBA AXI4-Lite, 3 master / 13 slave |
| Hedef saat | 50 MHz (20 ns periyot) |
| PDK | SKY130A, `sky130_fd_sc_hd` |
| Akis | LibreLane Classic |

`soc_top` ve altindaki tum RTL **ASIC'e hazir** durumdadir:

- Sifir `inout` portu, sifir `'z` surumu. Ucdurumlu surucu halkasi bir ust
  katmandadir (FPGA'de `nexys_top`, ASIC'te pad halkasi). Cift yonlu pinler
  cikis / cikis-etkin / giris uclusu olarak disari verilir.
- YZ hizlandirici yerel bellegi (TCM) **tek yazan porta** indirilmistir:
  Port A okuma+yazma, Port B salt okuma. Bu yapi sky130'un 1RW+1R SRAM
  makrosuna dogrudan eslenebilir.

---

## Kurulum

ASIC akisi Nix tabanli LibreLane ortamini gerektirir.

    # Nix kurulumu (bir kez)
    curl -L https://nixos.org/nix/install | sh

    # LibreLane
    nix profile install github:librelane/librelane

Kullanilan surumler `environment/versions.txt` icindedir.

---

## Calistirma

Tum komutlar **`asic/` dizininden** calistirilir.

    make asic_run     # ZORUNLU HEDEF - tam LibreLane Classic akisi
    make lint         # yalnizca lint adimi
    make synth        # sentez adimina kadar
    make check        # filelist.f / config.yaml tutarlilik denetimi
    make collect      # ciktilari results/ ve reports/ altina topla
    make clean        # gecici calisma alanini sil

`make asic_run` sirasiyla sunlari yapar:

1. `check` - kaynak listesi tutarliligini dogrular
2. LibreLane Classic akisini kosar (`run/arkhe/` altinda)
3. `collect` - ciktilari sartnamenin istedigi agaca kopyalar

---

## Dizin duzeni

    config.yaml           LibreLane ana yapilandirmasi
    filelist.f            ASIC sentezinde kullanilan RTL kaynaklari (goreli yollar)
    Makefile              asic_run ve yardimci hedefler
    THIRD_PARTY.md        ucuncu taraf RTL/IP/makro bilgileri
    licenses/             ucuncu taraf lisanslari
    checksums/            teslim dosyalarinin checksum'lari
    scripts/              yardimci betikler
    environment/          Nix ortami ve surum bilgileri
    constraints/          design.sdc
    macros/               SRAM ve diger fiziksel makrolar
    reports/              akis raporlari (lint, sentez, timing, drc, lvs, ...)
    results/              nihai ciktilar (gds, def, lef, netlist, ...)
    config/resolved.json  akista fiilen kullanilan yapilandirma
    metrics/              metrics.csv ve metrics.json
    run/                  LibreLane gecici calisma alani

---

## Cikti konumlari

Akis tamamlandiginda degerlendirmede kullanilacak dosyalar:

| Cikti | Konum |
|---|---|
| GDSII | `results/gds/` |
| DEF | `results/def/` |
| LEF | `results/lef/` |
| Gate level netlist | `results/netlist/` |
| Kullanilan SDC | `results/sdc/` |
| SPEF | `results/spef/` |
| DRC raporu | `reports/drc/` |
| LVS raporu | `reports/lvs/` |
| Zamanlama (STA) | `reports/timing/` |
| Sentez / alan | `reports/synthesis/` |
| Lint | `reports/lint/` |
| Metrikler | `metrics/` |

---

## Kaynak listesi kurali

`filelist.f` icindeki yollar **gorelidir** ve akis `asic/` dizininden
baslatildiginda cozumlenir. ASIC akisinda kullanilan her RTL kaynagi bu
listede bulunur; listede olmayan kaynak kullanilmaz.

Listeye **girmeyenler** ve nedenleri:

| Dosya | Neden |
|---|---|
| `nexys_top.sv` | FPGA'e ozgu ust sarmalayici; ucdurumlu surucu halkasi ve kart pinleri icerir |
| `tb_*.sv`, `*_tb.sv` | testbench'ler |
| `spi_flash_model.sv` | yalnizca simulasyon modeli |
| `axil_protocol_checker.sv` | yalnizca SVA denetleyicisi, sentezlenmez |

`make check` bu kurallari otomatik denetler.
