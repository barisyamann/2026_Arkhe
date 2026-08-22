# AXI4-Lite veriyolu incelemesi - interconnect, arbiter'lar, DMA

Tarih  : 22 Agustos 2026
Kapsam : `axi_lite_interconnect.sv` (607 satir), `axil_arbiter_3to1.sv` (216),
         `axil_arbiter_2to1.sv` (152), `dma_controller.sv` (365)
Yontem : Satir satir okuma; AXI4-Lite (ARM IHI 0022) kanal bagimsizligi,
         el sikisma kurallari ve kilitlenme yollari acisindan

Bu belge yalnizca **bulgulari** kaydeder. Uygulanan degisiklikler ayrica
`evidence/KARAR_GUNLUGU.md` icinde izlenir.

---

## Ozet

| No | Modul | Bulgu | Siddet | Durum |
|----|-------|-------|--------|-------|
| V1 | `dma_controller` | AW ve W'nin AYNI cevrimde kabulunu sart kosuyor | Orta | **COZULDU** |
| V2 | `axil_arbiter_2to1` | Okuma FSM'inde `default:` dali yok | Dusuk | **COZULDU** |
| V3 | `axi_lite_interconnect` | DTR "DECERR" diyor, RTL `SLVERR` donuyor | Dusuk (belge) | **COZULDU** |
| V4 | `axil_arbiter_2to1` | Surekli m1 trafiginde m0 aclik riski | Dusuk | KABUL |
| V5 | `dma_controller` | `reg_ctrl[1]` (reset) kendini temizlemiyor | Dusuk | KABUL |
| V6 | tum arbiter/interconnect | Islem basina 1 cevrim kabarcik | Bilgi | KABUL |

**Kilitlenmeye yol acan, veri bozan veya sartname ihlali olusturan bir
bulgu YOKTUR.** Isleyen tasarimda V1 latent kalirdi (asagiya bakiniz).

## Uygulama - 22 Agustos 2026

V1, V2 ve V3 duzeltildi. Regresyon duzeltmelerden sonra **8/8 test,
124 denetim** ile gecti; hicbir davranis degisikligi gozlenmedi - beklenen
sonuc, cunku ucu de bugun tetiklenmeyecek yollari kapatiyor.

    V1  dma_controller.sv       aw_done_q / w_done_q bayraklari
    V2  axil_arbiter_2to1.sv    default: r_state_d = R_IDLE;
    V3  axi_lite_interconnect.sv  2'b10 (SLVERR) -> 2'b11 (DECERR), iki kanal

## Protokol denetimi genisletildi - 22 Agustos 2026

V1 duzeltildi ama **regresyonda korunmuyordu**: `axil_protocol_checker`
YALNIZCA birlesik master arayuzune (arbiter cikisi -> interconnect)
bagliydi. Master portlarinin kendileri izlenmiyordu, yani bir master AXI
kuralini ihlal etse bile arbiter cikisinda duzelmis gorunebiliyordu.

Uc master portu da baglandi:

    u_pc_cpu    M0 - CPU veri portu (OBI -> AXI koprusu cikisi)
    u_pc_jtag   M1 - JTAG/Debug master
    u_pc_dma    M2 - DMA master        <- V1'in yasadigi yer

Denetleyicinin mevcut kurallari zaten dogru olani sinamaktaydi: kararlilik
ozellikleri sonuc kisminda `&& awvalid` / `&& wvalid` icerdigi icin
"valid, ready gelene kadar dusmemeli" kuralini da kapsiyor. Eksik olan
kural degil, KAPSAMDI.

Sartname Bolum 5.2 (odul icin asgari basari kriteri):
> "Cevre birimleri ve YZ hizlandiricinin {AXI or AXI-Lite} arayuzlerinin
> en azindan protocol check duzeyinde AXI agent'lariyla dogrulanmasi."

Dort denetleyici ile kosulan regresyonda ihlal gozlenmedi.

---

## V1 - DMA yazma kanalinda AW/W eszamanlilik varsayimi

**Konum:** `rtl/Cevre_Birimleri/dma_controller.sv`, `DMA_WRITE_REQ`

Birlesik mantik AW ve W'yi birlikte yukseltiyor:

    DMA_WRITE_REQ: begin
        m_axi_awvalid = 1'b1;
        m_axi_wvalid  = 1'b1;
    end

Sirali mantik ise durumdan yalnizca **ikisi birden** kabul edilirse cikiyor:

    DMA_WRITE_REQ: begin
        if (m_axi_awready && m_axi_wready) begin
            dma_state <= DMA_WRITE_WAIT;
        end
    end

AXI4-Lite'ta AW ve W **bagimsiz kanallardir**; bir slave adresi N.
cevrimde, veriyi N+1'de kabul edebilir. Bu tamamen gecerlidir.

Boyle bir slave'de ne olur:
- N. cevrim: `awvalid & awready` -> slave adresi TUKETIR
- N+1. cevrim: DMA hala `DMA_WRITE_REQ`'te, `awvalid` HALA yuksek
- Slave bunu **ikinci bir yazma islemi** olarak gorur

Ayni sey ters sirada W icin gecerlidir: veri iki kez gonderilir.

### Neden bugun patlamiyor

Mevcut sistemdeki tum slave'ler AW ve W hazir sinyallerini ayni cevrimde
yukseltiyor. Ornegin DMA'nin kendi CSR slave'i:

    if (s_axi_awvalid && !aw_valid_lat) s_axi_awready <= 1'b1;
    if (s_axi_wvalid  && !w_valid_lat)  s_axi_wready  <= 1'b1;

Iki bagimsiz `if`, ama iki valid de ayni anda geldigi icin iki ready de
ayni anda cikiyor. Interconnect'in cozme kabarcigi da her ikisini birlikte
geciktiriyor. Yani **tasarim su an dogru calisiyor; varsayim gizli.**

### Onerilen duzeltme

Kanal basina ayri "tamamlandi" bayragi (~10 satir):

    logic aw_done_q, w_done_q;
    // AW: awvalid = !aw_done_q;  awready gelince aw_done_q <= 1
    // W : wvalid  = !w_done_q;   wready  gelince w_done_q  <= 1
    // Ikisi de 1 olunca -> DMA_WRITE_WAIT

Bu, protokol denetleyicisinin (`axil_protocol_checker.sv`) DMA master
portuna baglanmasiyla birlikte regresyonda kalici olarak korunur.

---

## V2 - 2'ye 1 arbiter'da eksik `default:`

**Konum:** `rtl/Memory/axil_arbiter_2to1.sv`, okuma FSM'i

    typedef enum logic [1:0] { R_IDLE, R_BUSY0, R_BUSY1 } r_state_t;
    ...
    case (r_state_q)
        R_IDLE:  ...
        R_BUSY0: ...
        R_BUSY1: ...
    endcase                     // <- default yok

Durum kodlamasi 2 bit; `2'b11` erisilemez ama **kodlanabilir**. Tum
cikislar `case` oncesinde varsayilan deger aliyor, bu yuzden **latch
uretilmiyor** - islevsel hata yok. Ancak FSM bir sekilde `2'b11`'e
duserse (reset sirasinda X yayilimi, tek olay bozulmasi) orada kalir;
kurtulus yolu yoktur.

3'e 1 arbiter'da bu dal **mevcuttur**; tutarsizlik yalnizca 2'ye 1'de.

Duzeltme: `default: r_state_d = R_IDLE;` - tek satir.

---

## V3 - DECERR / SLVERR belge uyusmazligi

DTR Bolum 2.2.1 su iddiada bulunuyor:

> "...donduruken **DECERR** yaniti ile yazilim duzeyinde aninda istisna
> (exception) tetiklenmesi saglanmistir."

RTL'de varsayilan slave `2'b10` = **SLVERR** donuyor
(`axi_lite_interconnect.sv`, hem yazma hem okuma `default:` dallari).
DECERR `2'b11`'dir.

Islevsel sonuc ayni: CV32E40P her iki hata yanitinda da bus fault
istisnasi alir. Ancak teslim edilen raporda **olgusal bir yanlislik**
vardir. Final raporunda ya metin duzeltilmeli ya da RTL `2'b11`'e
cekilmelidir. Adres cozulemedigi icin dogru olan DECERR'dir.

---

## V4 - 2'ye 1 arbiter'da oncelik ve aclik

`R_IDLE` her cevrimde onceligi yeniden degerlendiriyor ve m1 (veri)
m0'dan (buyruk getirme) once geliyor. Surekli m1 trafigi teorik olarak
m0'i ac birakir.

Pratikte kendini sinirlar: CPU buyruk getirmeden yeni veri erisimi
uretemez. Ayrica boot sirasinda buyruklar Boot ROM'dan, veri yazmalari
I-RAM'e gider - farkli arbiter ornekleri. **Kabul edilmis kisittir.**

---

## V5 - DMA reset biti kendini temizlemiyor

`reg_ctrl[0]` (start) donanim tarafindan temizleniyor:

    if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0;

`reg_ctrl[1]` (reset) temizlenmiyor. `DMA_CTRL = 0x3` yazan bir yazilim
(start + reset birlikte) DMA'yi kalici resette tutar. Donanim hatasi
degil, yazilim tuzagi. Surucu belgesine not dusulmeli.

---

## V6 - Islem basina bir cevrim kabarcik

Hem 3'e 1 arbiter (`W_IDLE` hicbir ready yukseltmez) hem interconnect
(`write_sel_q == 13` iken cozum kaydediliyor) her islemde bir cevrim
gecikme ekliyor. Toplam gecikme ~2 cevrim.

Bu bilincli bir sadelestirme: cozumu kaydetmek adres cozucuyu kritik
yoldan cikarir. DTR'de "katı onceliklendirme... kritik yol gecikmesini
azaltmis ve sentez frekansini artirmistir" olarak zaten anlatiliyor.

---

## Dogrulanan ve SORUN OLMAYAN noktalar

Incelemede supheli gorunup **temiz cikan** yerler:

1. **Varsayilan slave gecerli adreslerde tetiklenmiyor.** `write_sel_q`
   reset degeri 13 (= varsayilan slave) ve `case` o dala giriyor. Ancak
   hata yanit ureteci ayrica adresi de denetliyor:

       if (write_sel_q == 4'd13 && m_awvalid && get_slave_id(m_awaddr) == 13)

   Gecerli adreste `err_awready`/`err_bvalid` sifir kalir; master yalnizca
   bir cevrim bekler. Sahte SLVERR **yoktur**.

2. **Adres haritasi bosluklari.** Cozucu araliklari (`get_slave_id`)
   `memory_map_pck.sv`, DTR Tablo 2.1.7 ve linker script ile birebir
   uyusuyor. NPU TCM 0x2001_0000-0x2001_77FF = 30720 bayt = 30 kB dogru.

3. **Cevre birimi adres aynalanmasi.** Cozucu 4 kB pencere aciyor, cevre
   birimleri yalnizca alt 8 biti kod cozuyor; ust adresler ayni
   yazmaclara aynalaniyor. Standart davranis, zarar yok.

4. **Okuma/yazma kanallarinin bagimsiz arbitrasyonu.** `write_sel_q` ve
   `read_sel_q` ayri. M0 yazma kanalinin sahibiyken M1 okuma kanalinin
   sahibi olabilir. AXI4-Lite'ta kanallar bagimsiz oldugu icin bu
   **gecerlidir** ve interconnect de ayni ayrimi koruyor.

5. **GPIO'daki "bloklayan atama"** onceki listede supheli isaretlenmisti.
   Yeniden bakildi: `pin_mode` bir `always_comb` icinde yerel degisken ve
   bloklayan atama orada **zorunlu** dogru stildir. Bulgu **geri
   cekilmistir**.

---

## Kaynaklar

- ARM IHI 0022E, AMBA AXI ve ACE Protokol Spesifikasyonu
- DTR Bolum 2.1.2, 2.2.1 (veriyolu yapisi ve arbitrasyon)
- `rtl/Memory/axil_protocol_checker.sv` (SVA denetleyicisi)
