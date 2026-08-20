# Verilator Lint Incelemesi - 810 Uyari

Kaynak: `asic/run/arkhe/01-verilator-lint/verilator-lint.log`
Verilator 5.044 · LibreLane v3.0.10 · 20 Agustos 2026

**Hata sayisi: 0.** Asagidakilerin hepsi uyaridir.

---

## 1. Uyarilar kime ait

Uyari sayisi tek basina anlamsizdir; once kaynagi ayrilmalidir.

| Kaynak | Adet | Pay |
|---|---|---|
| LibreLane'in urettigi PDK hucre dosyasi (`tmp/*.bb.v`) | 447 | %55,2 |
| Satici kodu - OpenHW CV32E40P | 223 | %27,5 |
| **Bizim yazdigimiz RTL** | **140** | **%17,3** |
| **Toplam** | **810** | |

447'nin tamami `TIMESCALEMOD`. LibreLane sky130 standart hucreleri icin
otomatik bir blackbox dosyasi uretiyor ve o dosyaya zaman olcegi
direktifi koymuyor. Bizim dosyalarimizda var; Verilator ikisinin
karisimini bildiriyor. Uzerinde islem yapilabilecek bir sey degil.

---

## 2. Bizim koddaki 140 uyari

| Tur | Adet | Degerlendirme |
|---|---|---|
| `UNUSEDSIGNAL` | 52 | Kullanilmayan sinyal - islevsel etkisi yok |
| `WIDTHEXPAND` | 26 | Dar -> genis genisletme, bilgi kaybi yok |
| `UNUSEDPARAM` | 23 | Kullanilmayan parametre |
| `PINCONNECTEMPTY` | 21 | Bilerek bos birakilan port |
| `UNOPTFLAT` | 6 | **Incelendi - dongu yok, bkz. 3.1** |
| `PINMISSING` | 4 | **Kasitli - bkz. 3.2** |
| `WIDTHTRUNC` | 3 | **Incelendi - kayip yok, bkz. 3.3** |
| `UNSIGNED` | 2 | Sabit dogru karsilastirma, bkz. 3.4 |
| `TIMESCALEMOD` | 1 | PDK dosyasiyla karisim |
| `BLKSEQ` | 1 | **Incelendi - bkz. 3.5** |
| `CASEINCOMPLETE` | 1 | **Incelendi - bkz. 3.6** |

### Dosya bazinda

| Dosya | Uyari |
|---|---|
| `rtl/Memory/soc_top.sv` | 34 |
| `rtl/Cevre_Birimleri/qspi_master.sv` | 24 |
| `rtl/npu/npu_compute_engine.sv` | 23 |
| `rtl/Memory/memory_map_pck.sv` | 12 |
| `rtl/Cevre_Birimleri/i2c_peripheral.sv` | 8 |
| `rtl/Memory/sram_module.sv` | 7 |
| `rtl/Cevre_Birimleri/jtag_debug.sv` | 6 |
| `rtl/Cevre_Birimleri/timer_peripheral.sv` | 4 |
| `rtl/Memory/axi_lite_interconnect.sv` | 3 |
| `rtl/Cevre_Birimleri/gpio_peripheral.sv` | 3 |
| digerleri | 16 |

`soc_top.sv` basi cekiyor cunku 13 slave'in butun AXI sinyallerini elle
bagliyor; kullanilmayan her sinyal bir uyari uretiyor.

---

## 3. Riskli gorunen uyarilarin tek tek incelemesi

Islevsel hataya donusebilecek yedi uyari ayri ayri denetlendi.
**Hicbiri gercek hata cikmadi.** Gerekceler asagidadir.

### 3.1 UNOPTFLAT - kombinasyonel dongu suphesi (6 adet)

    soc_top.sv:340  Circular combinational logic: soc_top.s0_arready
    soc_top.sv:347  ... s1_arready
    soc_top.sv:358  ... s3_awready     (ve 3 tane daha)

AXI4-Lite'ta `ready` sinyalleri kolelerden yoneticiye kombinasyonel
gider. Verilator, ara baglayici ile kole arasindaki bu yolun kapali bir
cevrim olusturmadigini modul sinirinda kanitlayamiyor ve muhafazakar
davraniyor.

**Capraz denetim yapildi:** ne Yosys ne de OpenSTA hicbir kombinasyonel
dongu bildirdi.

    grep -iE "combinational loop|loop.*broken" run/arkhe/*/[a-z]*.log
    -> bos

OpenSTA butun yollari analiz etti ve zamanlama kapandi. Gercek bir dongu
olsaydi STA onu kirar ve raporlardi. **Yanlis pozitif.**

### 3.2 PINMISSING - guc pinleri (4 adet)

    sram_module.sv:179    Instance has missing pin: vccd1 / vssd1
    npu_tcm_sram.sv:102   Instance has missing pin: vccd1 / vssd1

**Kasitlidir ve RTL icinde yorumla belgelenmistir.** SRAM makrosunun guc
pinleri `inout` tipindedir; RTL'de sabit deger baglamak elektriksel kisa
devredir ve Verilator bunu dogru sekilde HATA sayar:

    %Error-PORTSHORT: Output port is connected to a constant pin

Makro guc baglantisi PDN (Power Distribution Network) adiminda fiziksel
olarak yapilir. Simulasyonda ilgili tanim yok oldugu icin bu portlar
zaten olusmaz. Baglamak yanlis olurdu.

### 3.3 WIDTHTRUNC - kirpma (3 adet)

**(a) `axi_lite_interconnect.sv:373` ve `:506`**

    write_sel_d = get_slave_id(m_awaddr);   // int (32 bit) -> logic [3:0]

`get_slave_id` bir SystemVerilog `int` dondurur, atanan sinyal 4 bittir.
Fonksiyonun dondurebilecegi butun degerler sayildi:

    0 Boot ROM · 1 I-RAM · 2 D-RAM · 3 GPIO · 4 Timer · 5 UART Genel
    6 UART Stream · 7 I2C · 8 QSPI · 9 NPU CSR · 10 NPU Bellek
    11 DMA CSR · 12 JTAG CSR · 13 varsayilan kole (hatali adres)

Araligin tamami **0..13**, 4 bit 0..15 tutar. **Bilgi kaybi yok.**
Kodda zaten belirtilmis: "4-bit yeterli cunku 0..13 araliginda".

**(b) `npu_compute_engine.sv:636`**

    fc_idx <= (t_out * 20 + f_out) * 8 + d_out;   // 32 bit -> logic [13:0]

Girdi araliklari bildirimlerden okundu:

    t_out : logic [4:0]  ->  0..24
    f_out : logic [4:0]  ->  0..19
    d_out : logic [3:0]  ->  0..7

En buyuk deger:

    (24 * 20 + 19) * 8 + 7  =  499 * 8 + 7  =  3999

`fc_idx` 14 bittir, 0..16383 tutar. **Tavan degerin dort katindan fazla
yer var.** Kodda zaten belirtilmis: "FC agirlik indeksi (0..3999)".

### 3.4 UNSIGNED - sabit dogru karsilastirma (2 adet)

    axi_lite_interconnect.sv:307   if (addr >= 32'h0000_0000 && ...)
    sram_module.sv:236             (raddr < RAM_DEPTH[...]) || ...

Isaretsiz bir degerin sifirdan buyuk-esit olmasi her zaman dogrudur. Bu
bir hata degil, okunabilirlik tercihidir: adres araliklari
`alt <= addr <= ust` bicimiyle tek duzen yazilmis, ilk araligin alt
siniri sifir oldugu icin o karsilastirma sabitlenmis. Sentez bunu eliyor.

### 3.5 BLKSEQ - sirali blokta blocking atama (1 adet)

    gpio_peripheral.sv:153   write_addr = s_axil_awaddr;

`always_ff` icinde `=` kullanimi genellikle simulasyon/sentez ayrismasina
yol acar. Burada acmiyor: `write_addr` bir gecici degiskendir, ayni blokta
atanip ayni blokta bir kez okunur.

    101:  logic [AXI_ADDR_W-1:0] write_addr;   // bildirim
    153:  write_addr = s_axil_awaddr;          // TEK atama
    155:  unique case (write_addr[7:0])        // TEK okuma

Baska kullanimi yoktur; non-blocking atama ile karisim yoktur. Sentez
bunu kombinasyonel bir tel olarak ele alir ve davranis ayni kalir.

**Yine de iyilestirilebilir:** gecici tamamen kaldirilip `case` dogrudan
`s_axil_awaddr[7:0]` uzerinde kurulabilir. Islevsel fark yok.

> Bu tur bir karisim daha once GERCEK hataya yol acmisti: NPU'daki
> `sum_exp` degiskeninde blocking ve non-blocking atama karismisti,
> Vivado sessizce kabul ediyordu, slang reddetti. Burada durum farkli -
> karisim yok - ama uyariyi ciddiye alma gerekcemiz budur.

### 3.6 CASEINCOMPLETE - eksik durum (1 adet)

    axil_arbiter_2to1.sv:99   Case values incompletely covered (0x3)

FSM durum tipi 2 bittir ama uc durum tanimlidir:

    typedef enum logic [1:0] { R_IDLE, R_BUSY0, R_BUSY1 } r_state_t;

Dorduncu kod (`2'b11`) tanimsizdir. **Latch olusmuyor**, cunku `case`ten
once satir 81'de varsayilan atama var:

    r_state_d = r_state_q;

Ancak bunun bir yan etkisi var: FSM bir sekilde tanimsiz duruma duserse
(isinlama kaynakli bit devrilmesi, guc dalgalanmasi) `r_state_d = r_state_q`
onu **kalici olarak orada tutar.** Kendi kendine toparlanamaz.

**Onerilen iyilestirme:** `case` icine `default: r_state_d = R_IDLE;`
eklemek. Maliyeti sifira yakin, kazanci FSM'in tanimsiz durumdan
cikabilmesi. Bir uzay/savunma uygulamasinda bu tercih edilir.

---

## 4. Sonuc ve karar

**Islevsel hata bulunmadi.** Riskli gorunen yedi uyarinin her biri
aritmetikle veya arac capraz denetimiyle kapatildi.

Iki saglamlik iyilestirmesi tespit edildi:

| # | Dosya | Degisiklik | Tur |
|---|---|---|---|
| 1 | `axil_arbiter_2to1.sv` | `case` icine `default: r_state_d = R_IDLE;` | Saglamlik |
| 2 | `gpio_peripheral.sv` | `write_addr` gecicisini kaldir | Uslup |

**Ikisi de simdilik UYGULANMADI.** Gerekce: bu inceleme yapilirken ASIC
akisi kosuyordu. RTL degistirilirse uretilen netlist, DEF ve GDSII artik
depodaki kaynak koda karsilik gelmez - degerlendirmede en can sikici
tutarsizlik budur. Ikisi de islevsel hata olmadigi icin akisi durdurup
bastan baslatmayi hak etmiyor.

**Karar: GDSII alindiktan sonra uygulanacak ve regresyon tekrar kosulacak.**

---

## 5. Tekrar uretme

    cd asic
    make lint

veya dogrudan:

    cd asic/run/arkhe/01-verilator-lint
    grep -c "%Warning" verilator-lint.log     # 810
    grep -c "%Error"   verilator-lint.log     # 0

Bolum 1 tablosu, log icindeki uyari basliklarinin dosya yoluna gore
siniflandirilmasiyla uretilmistir: PDK blackbox = `tmp/*.bb.v`,
satici = `cv32e40p-master/`, geri kalani bizim.
