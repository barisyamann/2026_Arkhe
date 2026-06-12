# Arkhe SoC — Donanımsal Entegrasyon ve Hata Giderme Raporu

Bu rapor, Arkhe RISC-V SoC (System-on-Chip) üzerinde gerçekleştirilen DMA/JTAG entegrasyonlarını, AXI-Lite veriyolu hakemlemesini (arbitration), çevre birimlerindeki hata giderme çalışmalarını ve simülasyon doğrulama sonuçlarını içermektedir.

---

## 1. Genel Mimari Değişikliği

### Eski Mimari (1 Master, 11 Slaves)
```
CPU Data Access ──► Interconnect ──► 11 Slave Birimi (ROM, RAM, GPIO, Timer, vb.)
```

### Yeni Mimari (3 Master, 13 Slaves)
```
CPU Data Access ─┐
JTAG Debug Master ┼──► 3-to-1 Master Arbiter ──► Interconnect ──► 13 Slave Birimi (Yeni DMA & JTAG CSR'ler dahil)
DMA Master ──────┘
```

> [!IMPORTANT]
> Veriyolu hakemlemesinde öncelik sırası **CPU > JTAG > DMA** şeklinde ayarlanmıştır. Bu sayede işlemci her zaman en yüksek önceliğe sahip olur.

---

## 2. Yapılan Değişiklikler ve Kod Detayları

### 2.1. Adres Haritası Güncellemesi (`memory_map_pck.sv`)
Yeni eklenen DMA ve JTAG kontrol birimleri (CSR) için adres alanları tanımlandı:
```systemverilog
// DMA Kontrol CSR Adres Alanı (s11)
localparam logic [ADDR_WIDTH-1:0] DMA_BASE        = 32'h4007_0000;

// JTAG/Debug CSR Adres Alanı (s12)
localparam logic [ADDR_WIDTH-1:0] JTAG_BASE       = 32'h4008_0000;
```

---

### 2.2. Tek Kanallı DMA Kontrolcüsü (`dma_controller.sv`)
**İşlev**: Bellek-bellek (Memory-to-Memory) ve UART-Stream ↔ NPU TCM arası veri transferlerini CPU müdahalesi olmadan gerçekleştiren donanımsal DMA birimi.

* **FSM State Makinesi**: `IDLE → READ_REQ → READ_WAIT → WRITE_REQ → WRITE_WAIT → DONE`
* **Register Haritası**:
  * `0x00`: `DMA_CTRL` (Bit 0: Start, Bit 1: Reset)
  * `0x04`: `DMA_STATUS` (Bit 0: Busy, Bit 1: Done, Bit 2: Error)
  * `0x08`: `DMA_SRC_ADDR` (Kaynak Başlangıç Adresi)
  * `0x0C`: `DMA_DST_ADDR` (Hedef Başlangıç Adresi)
  * `0x10`: `DMA_XFER_LEN` (Kelime Sayısı cinsinden uzunluk)

**FSM Akış Kod Bloğu:**
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dma_state <= DMA_IDLE;
        dma_done  <= 1'b0;
    end else if (dma_reset) begin
        dma_state <= DMA_IDLE;
    end else begin
        case (dma_state)
            DMA_IDLE: begin
                if (start_pulse) begin
                    dma_state  <= DMA_READ_REQ;
                    xfer_cnt   <= reg_xfer_len[12:0];
                    src_addr_q <= reg_src_addr;
                    dst_addr_q <= reg_dst_addr;
                end
            end
            DMA_READ_REQ:  if (m_axi_arready) dma_state <= DMA_READ_WAIT;
            DMA_READ_WAIT: if (m_axi_rvalid)  dma_state <= DMA_WRITE_REQ;
            DMA_WRITE_REQ: if (m_axi_awready && m_axi_wready) dma_state <= DMA_WRITE_WAIT;
            DMA_WRITE_WAIT: begin
                if (m_axi_bvalid) begin
                    src_addr_q <= src_addr_q + 4;
                    dst_addr_q <= dst_addr_q + 4;
                    if (xfer_cnt <= 1) dma_state <= DMA_DONE;
                    else begin
                        xfer_cnt  <= xfer_cnt - 1;
                        dma_state <= DMA_READ_REQ;
                    end
                end
            end
            DMA_DONE: begin
                dma_done  <= 1'b1;
                dma_state <= DMA_IDLE;
            end
        endcase
    end
end
```

---

### 2.3. Basitleştirilmiş JTAG Debug Bridge (`jtag_debug.sv`)
**İşlev**: Harici debug pinleri (TMS, TCK, TDI, TDO, TRST_N) üzerinden AXI Master portunu kullanarak sisteme doğrudan bellek okuma/yazma erişimi sağlar. CPU'yu askıya alabilir (`debug_req_o` sinyali ile).

* **JTAG TAP Durum Makinesi**: `TAP_RESET → TAP_IDLE → TAP_DR_SHIFT → TAP_DR_UPDATE ...`
* **Multi-Driver Hatasının Giderilmesi**: `dbg_halted` sinyalinin hem JTAG FSM bloğundan hem de CSR AXI Slave bloğundan sürülmesini engellemek için atamaları modülün sonuna eklenen bağımsız bir `always_ff` bloğunda birleştirdik:
```systemverilog
// Dedicated always_ff block for dbg_halted
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dbg_halted <= 1'b0;
    end else begin
        if (csr_do_write && (csr_aw_addr_lat[4:0] == REG_DBG_CTRL)) begin
            if (csr_w_data_lat[0]) dbg_halted <= 1'b1;
            else if (csr_w_data_lat[1]) dbg_halted <= 1'b0;
        end else if (bus_state == BUS_IDLE && jtag_cmd_pulse && (jtag_ir_latched == IR_DBG_CTRL)) begin
            dbg_halted <= jtag_dr_latched[0];
        end
    end
end
```

---

### 2.4. 3-to-1 Master Arbiter (`axil_arbiter_3to1.sv`)
**İşlev**: CPU Data, JTAG Master ve DMA Master olmak üzere 3 master'ın AXI-Lite isteklerini Round-Robin öncelik mekanizmasıyla arbitre edip tek bir Interconnect master portuna yönlendirir.

* **Öncelik Algoritması**: CPU istekleri her zaman en yüksek önceliğe sahiptir. Boştayken sırasıyla JTAG ve DMA istekleri işleme alınır.

---

### 2.5. Interconnect ve En Üst Seviye Güncellemesi (`axi_lite_interconnect.sv`, `soc_top.sv`)
* **Interconnect Port Sayısı**: Slave port sayısı 11'den 13'e yükseltildi. 
  * `Slave 11`: DMA Kontrol CSR (Adres: `0x4007_0000 - 0x4007_0FFF`)
  * `Slave 12`: JTAG Kontrol CSR (Adres: `0x4008_0000 - 0x4008_0FFF`)
* **Kesme (Interrupt) Vektörü**: DMA ve I2C interrupt'ları `irq_vector` dizisine bağlandı.

---

### 2.6. NPU Sticky Done Hatasının Düzeltilmesi (`npu_compute_engine.sv`)
**Sorun**: Eski tasarımda NPU çıkarımı bitince `done_o` sinyali sadece 1 saat çevrimi (clock cycle) boyunca yüksek kalıyor, ardından doğrudan `IDLE` durumuna geçiyordu. CPU polling (bekleme) döngüsü çok hızlı dönmediğinde bu 1 çevrimlik sinyali kaçırıyor ve sonsuz döngüde asılı kalıyordu.
**Düzeltme**: `done_o` sinyali **sticky** (yapışkan) hale getirildi. NPU çıkarımı tamamlandıktan sonra `DONE` durumunda bekler. Yalnızca CPU'dan yeni bir `start` veya `npu_reset` sinyali geldiğinde `IDLE` durumuna döner.
```systemverilog
DONE: begin
    busy_o   <= 1'b0;
    done_o   <= 1'b1;
    class_o  <= detected_class;
    // done_o yüksek kalır, yeni start veya reset gelene kadar DONE'da bekler
    if (start_i || npu_reset_i) begin
        state  <= IDLE;
        done_o <= 1'b0;
    end
end
```

---

### 2.7. I2C Kesme Sinyali Ekleme (`i2c_peripheral.sv`)
**Düzeltme**: I2C modülünde eksik olan kesme çıkışı `i2c_irq` olarak eklendi. TX veya RX işlemlerinin başarıyla tamamlandığını gösteren durum register bitlerine (`reg_cfg[1]` ve `reg_cfg[3]`) bağlandı:
```systemverilog
assign i2c_irq = reg_cfg[1] | reg_cfg[3]; // TX_DONE | RX_DONE
```

---

## 3. Testbench Makine Kodu Hata Düzeltmeleri (`tb_soc_top.sv`)

QSPI Flash üzerinden işlemcinin çektiği yapay zeka çıkarım programında derleme (machine code) hataları bulunuyordu. Bu durum CPU'nun yanlış adreslere atlamasına ve çömesine sebep olmaktaydı:

* **Sınıf Karşılaştırma Dallanması (`beq`)**:
  * *Eski*: `32'h01cf8863` (Kural dışı olarak `rs1` için `a5` (15) yerine `t6` (31) yazmacını kullanıyordu. Dallanma asla gerçekleşmiyordu).
  * *Yeni (Düzeltilmiş)*: `32'h01c78863` (rs1 olarak doğru yazmaç `a5` atandı).
* **Dışarı Atlama ve Döngü (`jal`)**:
  * *Eski*: `32'h0200006f` (16 byte yerine `8192 byte` ileriye atlayarak RAM sınırlarının dışına çıkıyor ve exception fırlatıyordu).
  * *Yeni (Düzeltilmiş)*: `32'h0100006f` (Tam 16 byte ileriye, yani bitiş döngüsüne atlar).
  * *Eski*: `32'h0100006f` (16 byte atlama).
  * *Yeni (Düzeltilmiş)*: `32'h0080006f` (Tam 8 byte ileriye, sonsuz döngüye atlar).

Düzeltilmiş QSPI yükleme kodu:
```systemverilog
uut.u_qspi.rx_fifo[16] = 32'h01c78863; // beq a5, t3, 16  (Eğer sınıf 2 (Evet) ise GPIO = 0x5555)
uut.u_qspi.rx_fifo[17] = 32'h00300e13; // addi t3, zero, 3     
uut.u_qspi.rx_fifo[18] = 32'h01c78863; // beq a5, t3, 16  (Eğer sınıf 3 (Hayır) ise GPIO = 0xAAAA)
uut.u_qspi.rx_fifo[19] = 32'h0100006f; // jal zero, 16    (Eşleşme yoksa doğrudan bitişe git)
uut.u_qspi.rx_fifo[20] = 32'h00d52223; // sw a3, 4(a0)    (GPIO_ODR = 0x5555)
uut.u_qspi.rx_fifo[21] = 32'h0080006f; // jal zero, 8     (Bitişe atla)
```

---

## 4. Simülasyon Doğrulama Sonuçları

Manuel koşturulan testte elde edilen log çıktıları ve zamanlamaları şu şekildedir:

1. **Boot RAM Yükleme Aşaması (0ns - 9000ns)**:
   Boot ROM, QSPI Flash'tan 24 kelimelik kodu kelime kelime okuyup I-RAM'e yazar.
   `[5550000] [QSPI_MASTER] Read from RX_FIFO[14] = 0x0105a783`
2. **I-RAM Çalışması Başlangıcı (9210ns)**:
   İşlemci `0x0100_0000` adresinden programı koşturmaya başlar.
   `[9210000] PC_ID=0x01000000`
3. **NPU Hesaplama Aşaması (10.05us - 50.05us)**:
   CPU NPU'yu başlatır. NPU, TCM SRAM belleğindeki 1960 veriyi toplayarak hesaplamasını bitirir.
   `[49370000] [NPU_ENGINE] Computation finished. Accumulator=0x55555555`
4. **GPIO Güncellemesi ve Bitiş (50.09us)**:
   CPU `REG_CLASS_OUT` register'ından çıkarım sonucunu (Class=2 -> "Yes") okur. `beq` karar mekanizması başarıyla tetiklenir ve GPIO çıkışına `0x5555` verisi yazılır.
   **`[50090000] GPIO Çıkışı Değişti: gpio_o = 16'h5555`**
5. **Kararlı Sonsuz Döngü (50.25us - 155us)**:
   CPU programın sonundaki sonsuz döngüye girer. Hata fırlatma veya reset atma durumları olmadan simülasyon tamamlanır.
   `[155170000] SoC Simülasyonu Tamamlandı.`
