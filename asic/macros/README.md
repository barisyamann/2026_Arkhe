# Fiziksel Makrolar

Bu dizin, tasarimda kullanilan SRAM ve diger fiziksel makrolara ait
dosyalari icerir.

**DURUM: SRAM makrosu henuz secilmedi.** Bu dizin su an bos.

---

## Zorunluluk

Final ciktilar belgesi (s.10):

> "Zorunlu SRAM makrosu tasarim hiyerarsisi icerisinde instantiate edilmeli,
> tasarimin islevsel veri yoluna baglanmali ve islevsel dogrulama
> testlerinde kullanilmalidir. SRAM makrosu sentez sonucunda optimize
> edilerek kaldirilmamali; nihai gate level netlist, DEF ve GDSII
> ciktilarinda bulunmalidir."

> "Yalnizca Verilog modeli bulunan ve fiziksel gorunumleri bulunmayan
> SRAM'ler ASIC fiziksel tasarim akisinda kullanilamaz."

Yani makro icin **gds + lef + lib + spice** dosyalarinin tamami gereklidir;
sadece Verilog modeli yeterli degildir.

---

## Beklenen dizin duzeni

Her makro icin bagimsiz bir alt dizin acilir:

    macros/
      <makro_adi>/
        gds/          GDSII fiziksel gorunum
        lef/          LEF soyut fiziksel gorunum
        lib/          Liberty zamanlama modelleri (PVT koseleri)
        verilog/      islevsel ve gerekirse black-box Verilog modeli
        spice/        SPICE netlisti
        config/       OpenRAM veya diger uretim araci yapilandirmasi

---

## Hedef kullanim

YZ hizlandirici yerel bellegi - `rtl/npu/npu_tcm_sram.sv`

| | |
|---|---|
| Kapasite | 30 kB = 7680 kelime x 32 bit |
| Port A | okuma + yazma |
| Port B | **salt okuma** |
| Instance yolu | `u_soc/u_npu/u_npu_sram` |

Port B, 18 Agustos 2026'da salt-okunur hale getirildi. Oncesinde hesaplama
motoru softmax sonuclarini Port B uzerinden geri yaziyordu; yani IKI YAZAN
PORT vardi ve bu yapi sky130'un 1RW+1R makrolarina eslenemezdi. Sonuc
yazimlari `npu_accelerator` icinde Port A'ya yonlendirildi ve AXI erisimiyle
cakisma `npu_axi_controller`'a eklenen `stall_i` ile cozuldu (erisim
dusurulmez, dort cevrim ertelenir).

Bu degisiklik sonrasi modul dogrudan bir 1RW+1R makroya eslenebilir:
Port A -> RW, Port B -> R.

---

## Secim yapilirken dikkat edilecekler

1. **Kapasite** - 30 kB tek bir sky130 makrosuna sigmaz; onaylı makrolar
   1 KiB ve 2 KiB boyutlarindadir. Birden fazla makro yan yana dizilip
   adres kod cozucuyle birlestirilmelidir.

2. **Port yapisi** - 1RW + 1R gereklidir (Port A yazma+okuma, Port B okuma).

3. **Fiziksel gorunum** - gds/lef/lib/spice dosyalarinin tamami olmali.

4. **Lisans** - lisans dosyasi `asic/licenses/` altina konulmali, kaynak ve
   surum bilgisi `asic/THIRD_PARTY.md` icine yazilmalidir.

5. **Hayatta kalma** - makro sentezde optimize edilip kaldirilmamalidir.
   Akis sonrasi `results/netlist/` ve `results/gds/` icinde varligi
   dogrulanmalidir.

---

## Makro eklendiginde guncellenecek dosyalar

| Dosya | Ne eklenecek |
|---|---|
| `THIRD_PARTY.md` | makro adi, kaynak, instance adi, veri genisligi, kelime sayisi, lisans |
| `environment/versions.txt` | makro surumu, OpenRAM surumu (kullanildiysa) |
| `config.yaml` | `MACROS`, `EXTRA_LEFS`, `EXTRA_LIBS`, `EXTRA_GDS_FILES`, `EXTRA_VERILOG_MODELS` |
| `licenses/` | makro lisans dosyasi |
| `rtl/npu/npu_tcm_sram.sv` | cikarimsal dizi yerine makro ornekleme |
