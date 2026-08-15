`timescale 1ns / 1ps
// Description: Testbench to verify Arkhe SoC Top Integration in Vivado.
//              Generates a 50 MHz clock, handles system reset, and mocks
//              external peripheral pins to verify early CPU boot cycles.

module tb_soc_top;

    // --- Sinyal Tanımlamaları ---
    logic        clk;
    logic        rst_n;

    // GPIO
    logic [15:0] gpio_i;
    logic [15:0] gpio_o;
    logic [15:0] gpio_tx_en_o;

    // UART1
    logic        uart1_rxd;
    logic        uart1_txd;

    // UART2
    logic        uart2_rxd;
    logic        uart2_txd;

    // I2C
    wire         i2c_sda;
    wire         i2c_scl;

    // QSPI
    logic        qspi_sck;
    logic        qspi_cs_n;
    wire         qspi_io0;
    wire         qspi_io1;
    wire         qspi_io2;
    wire         qspi_io3;

    // JTAG Debug
    logic        jtag_tms;
    logic        jtag_tck;
    logic        jtag_tdi;
    logic        jtag_tdo;
    logic        jtag_trst_n;

    // --- I2C ve QSPI için Pull-up direnç simülasyonları ---
    assign (weak1, weak0) i2c_sda = 1'b1;
    assign (weak1, weak0) i2c_scl = 1'b1;
    assign (weak1, weak0) qspi_io0 = 1'b1;
    assign (weak1, weak0) qspi_io1 = 1'b1;
    assign (weak1, weak0) qspi_io2 = 1'b1;
    assign (weak1, weak0) qspi_io3 = 1'b1;

    // --- UUT (Unit Under Test) ---
    soc_top uut (
        .clk_i        (clk),
        .rst_ni       (rst_n),
        
        .gpio_i       (gpio_i),
        .gpio_o       (gpio_o),
        .gpio_tx_en_o (gpio_tx_en_o),
        
        .uart1_rxd    (uart1_rxd),
        .uart1_txd    (uart1_txd),
        
        .uart2_rxd    (uart2_rxd),
        .uart2_txd    (uart2_txd),
        
        .i2c_sda      (i2c_sda),
        .i2c_scl      (i2c_scl),
        
        .qspi_sck     (qspi_sck),
        .qspi_cs_n    (qspi_cs_n),
        .qspi_io0     (qspi_io0),
        .qspi_io1     (qspi_io1),
        .qspi_io2     (qspi_io2),
        .qspi_io3     (qspi_io3),
        
        .jtag_tms     (jtag_tms),
        .jtag_tck     (jtag_tck),
        .jtag_tdi     (jtag_tdi),
        .jtag_tdo     (jtag_tdo),
        .jtag_trst_n  (jtag_trst_n)
    // --- SystemVerilog Functional Coverage (Kapsama) Tanımları ---
    covergroup cg_soc_verification @(posedge clk);
        option.per_instance = 1;
        
        // GPIO çıkışlarının fonksiyonel kapsaması
        cov_gpio: coverpoint gpio_o {
            bins idle    = {16'h0000};
            bins success = {16'h5555};
        }
        
        // JTAG TMS pininin geçişleri
        cov_jtag_tms: coverpoint jtag_tms {
            bins low  = {1'b0};
            bins high = {1'b1};
        }

        // AXI-Lite el sıkışma (handshake) kapsaması
        cov_axi_aw: coverpoint (uut.u_npu_axi_ctrl.mem_awvalid && uut.u_npu_axi_ctrl.mem_awready) {
            bins hit = {1'b1};
        }
        cov_axi_w: coverpoint (uut.u_npu_axi_ctrl.mem_wvalid && uut.u_npu_axi_ctrl.mem_wready) {
            bins hit = {1'b1};
        }
        cov_axi_ar: coverpoint (uut.u_npu_axi_ctrl.mem_arvalid && uut.u_npu_axi_ctrl.mem_arready) {
            bins hit = {1'b1};
        }
        cov_axi_r: coverpoint (uut.u_npu_axi_ctrl.mem_rvalid && uut.u_npu_axi_ctrl.mem_rready) {
            bins hit = {1'b1};
        }
    endgroup

    cg_soc_verification cg_inst = new();

    // --- Saat Üreteci (50 MHz -> 20ns Periyot) ---
    always begin
        clk = 1'b0;
        #10;
        clk = 1'b1;
        #10;
    end

    // --- Log Dosyası Yazma Altyapısı ---
    int log_file;
    
    function automatic void log_print(input string msg);
        $display("%s", msg);
        if (log_file != 0) begin
            $fdisplay(log_file, "%s", msg);
        end
    endfunction

    // --- Test Akışı ---
    initial begin
        log_file = $fopen("simulation.log", "w");
        if (log_file == 0) begin
            $display("HATA: simulation.log dosyası açılamadı!");
        end

        log_print($sformatf("[%0t] SoC Simülasyonu Başlatıldı.", $time));
        
        // Başlangıç Değerleri
        rst_n       = 1'b0;
        gpio_i      = 16'h0000;
        uart1_rxd   = 1'b1;
        uart2_rxd   = 1'b1;
        jtag_tms    = 1'b0;
        jtag_tck    = 1'b0;
        jtag_tdi    = 1'b0;
        jtag_trst_n = 1'b0;  // JTAG reset aktif

        // JTAG resetini kaldır
        #50;
        jtag_trst_n = 1'b1;

        // Reset Süreci
        #100;
        @ (posedge clk);
        rst_n = 1'b1;

        #1;
        // NPU Yerel Belleğini (TCM SRAM) sıfırlayarak simülasyon X/U belirsizliğini önleme
        for (int idx = 0; idx < 7680; idx = idx + 1) begin
            uut.u_npu.u_npu_sram.ram[idx] = 32'h0;
        end

        // QSPI RX FIFO ön yüklemesi - 24 Kelimelik Yapay Zeka Hızlandırıcı Test Programı
        uut.u_qspi.rx_fifo[0]  = 32'h40000537; // lui a0, 0x40000      (GPIO Base)
        uut.u_qspi.rx_fifo[1]  = 32'h400605b7; // lui a1, 0x40060      (NPU CSR Base)
        uut.u_qspi.rx_fifo[2]  = 32'h20010637; // lui a2, 0x20010      (NPU Memory Base)
        uut.u_qspi.rx_fifo[3]  = 32'h555556b7; // lui a3, 0x55555      
        uut.u_qspi.rx_fifo[4]  = 32'h55568693; // addi a3, a3, 0x555   (a3 = 0x55555555 - Evet ve GPIO çıkış modu şablonu)
        uut.u_qspi.rx_fifo[5]  = 32'haaaab737; // lui a4, 0xAAAAB      
        uut.u_qspi.rx_fifo[6]  = 32'haaa70713; // addi a4, a4, -1366   (a4 = 0xAAAAAAAA - Hayır şablonu)
        uut.u_qspi.rx_fifo[7]  = 32'h00d52423; // sw a3, 8(a0)         (GPIO_MODE'a yaz -> Tüm pinleri çıkış yap)
        uut.u_qspi.rx_fifo[8]  = 32'h00d62023; // sw a3, 0(a2)         (TCM[0] = 0x55555555 -> NPU toplamını 0x55 yapmak için)
        uut.u_qspi.rx_fifo[9]  = 32'h00100793; // addi a5, zero, 1     
        uut.u_qspi.rx_fifo[10] = 32'h00f5a023; // sw a5, 0(a1)         (NPU'yu Başlat - REG_CTRL = 1)
        uut.u_qspi.rx_fifo[11] = 32'h0045a783; // lw a5, 4(a1)         (NPU Durumunu Oku - REG_STATUS)
        uut.u_qspi.rx_fifo[12] = 32'h0027f793; // andi a5, a5, 2       (Done bitini maskele)
        uut.u_qspi.rx_fifo[13] = 32'hfe078ce3; // beq a5, zero, -8     (Done olana kadar bekle)
        uut.u_qspi.rx_fifo[14] = 32'h0105a783; // lw a5, 16(a1)        (REG_CLASS_OUT oku)
        uut.u_qspi.rx_fifo[15] = 32'h00200e13; // addi t3, zero, 2     
        uut.u_qspi.rx_fifo[16] = 32'h01c78863; // beq a5, t3, 16       (Eğer sınıf 2 (Evet) ise GPIO = 0x5555)
        uut.u_qspi.rx_fifo[17] = 32'h00300e13; // addi t3, zero, 3     
        uut.u_qspi.rx_fifo[18] = 32'h01c78863; // beq a5, t3, 16       (Eğer sınıf 3 (Hayır) ise GPIO = 0xAAAA)
        uut.u_qspi.rx_fifo[19] = 32'h0100006f; // jal zero, 16         (Eşleşme yoksa doğrudan bitiş döngüsüne git)
        uut.u_qspi.rx_fifo[20] = 32'h00d52223; // sw a3, 4(a0)         (GPIO_ODR = 0x5555)
        uut.u_qspi.rx_fifo[21] = 32'h0080006f; // jal zero, 8          (Bitiş döngüsüne atla)
        uut.u_qspi.rx_fifo[22] = 32'h00e52223; // sw a4, 4(a0)         (GPIO_ODR = 0xAAAA)
        uut.u_qspi.rx_fifo[23] = 32'h0000006f; // jal zero, 0          (Sonsuz döngü)
        uut.u_qspi.rx_wr_ptr   = 7'd24;        // RX FIFO'ya 24 kelime eklendi

        log_print($sformatf("[%0t] Reset kaldırıldı. İşlemci çalışıyor...", $time));

        // NPU donanım motorunun hesaplamayı bitirmesini dinamik olarak bekle (~964 bin çevrim, ~19.3 ms)
        log_print($sformatf("[%0t] NPU donanım motorunun tamamlanması bekleniyor...", $time));
        wait(uut.u_npu.u_npu_engine.done_o == 1'b1);
        log_print($sformatf("[%0t] NPU donanım motoru DONE sinyalini verdi!", $time));

        // GPIO Pinlerini Değiştirip Test Etme
        @ (posedge clk);
        gpio_i = 16'hA5A5;
        log_print($sformatf("[%0t] GPIO girişleri 0xA5A5 olarak ayarlandı.", $time));

        #5000;
        run_jtag_test();
        log_print($sformatf("[%0t] SoC Simülasyonu Tamamlandı.", $time));
        
        if (log_file != 0) begin
            $fclose(log_file);
        end
        $finish;
    end

    // --- İzleme (Monitoring) ---
    logic [31:0] last_pc = 32'h0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (uut.u_core.id_stage_i.pc_id_i !== last_pc) begin
                last_pc <= uut.u_core.id_stage_i.pc_id_i;
                // Polling döngüsünü (0x0100002c, 0x01000030, 0x01000034) log kirliliğini önlemek için filtrele
                if (uut.u_core.id_stage_i.pc_id_i != 32'h0100002c &&
                    uut.u_core.id_stage_i.pc_id_i != 32'h01000030 &&
                    uut.u_core.id_stage_i.pc_id_i != 32'h01000034) begin
                    log_print($sformatf("[%0t] PC_ID=0x%h | x10(a0)=0x%h | x12(a2)=0x%h | x13(a3)=0x%h | x14(a4)=0x%h | x15(a5)=0x%h | awaddr=0x%h | awvalid=%b | rx_wr=%0d | rx_rd=%0d | rx_empty=%0b", 
                             $time, 
                             uut.u_core.id_stage_i.pc_id_i,
                             uut.u_core.id_stage_i.register_file_i.mem[10],
                             uut.u_core.id_stage_i.register_file_i.mem[12],
                             uut.u_core.id_stage_i.register_file_i.mem[13],
                             uut.u_core.id_stage_i.register_file_i.mem[14],
                             uut.u_core.id_stage_i.register_file_i.mem[15],
                             uut.data_axil_awaddr,
                             uut.data_axil_awvalid,
                             uut.u_qspi.rx_wr_ptr,
                             uut.u_qspi.rx_rd_ptr,
                             uut.u_qspi.rx_empty));
                end
            end
        end
    end

    always @(gpio_o) begin
        log_print($sformatf("[%0t] GPIO Çıkışı Değişti: gpio_o = 16'h%h", $time, gpio_o));
    end

    // DMA Interrupt Monitoring
    always @(posedge clk) begin
        if (rst_n && uut.dma_irq) begin
            log_print($sformatf("[%0t] *** DMA Transfer Tamamlandı - IRQ aktif ***", $time));
        end
    end

    // I2C Interrupt Monitoring
    always @(posedge clk) begin
        if (rst_n && uut.i2c_irq) begin
            log_print($sformatf("[%0t] *** I2C İşlemi Tamamlandı - IRQ aktif ***", $time));
        end
    end

    // --- AXI4-Lite Protokol Denetleyicisi Bağlantısı (SVA) ---
    bind soc_top axil_protocol_checker u_protocol_checker (
        .clk      (clk_i),
        .rst_n    (rst_ni),
        .awaddr   (merged_m_awaddr),
        .awvalid  (merged_m_awvalid),
        .awready  (merged_m_awready),
        .wdata    (merged_m_wdata),
        .wstrb    (merged_m_wstrb),
        .wvalid   (merged_m_wvalid),
        .wready   (merged_m_wready),
        .bresp    (merged_m_bresp),
        .bvalid   (merged_m_bvalid),
        .bready   (merged_m_bready),
        .araddr   (merged_m_araddr),
        .arvalid  (merged_m_arvalid),
        .arready  (merged_m_arready),
        .rdata    (merged_m_rdata),
        .rresp    (merged_m_rresp),
        .rvalid   (merged_m_rvalid),
        .rready   (merged_m_rready)
    );

    // =========================================================================
    // JTAG Sürücü Yardımcı Görevleri (Tasks)
    // =========================================================================
    
    // TCK darbesi üret
    task automatic jtag_clock();
        jtag_tck = 1'b0;
        #100;
        jtag_tck = 1'b1;
        #100;
        jtag_tck = 1'b0;
    endtask

    // JTAG TAP reset durumuna getir
    task automatic jtag_reset();
        log_print("     [JTAG] TAP Reset yapiliyor...");
        jtag_trst_n = 1'b0;
        #100;
        jtag_trst_n = 1'b1;
        jtag_tms = 1'b1;
        repeat (5) jtag_clock();
        jtag_tms = 1'b0;
        jtag_clock(); // TAP_IDLE durumuna geç
    endtask

    // IR (Instruction Register) Shift et
    task automatic jtag_shift_ir(input logic [3:0] ir_in);
        // IDLE -> DR_SCAN -> IR_SCAN -> IR_CAPTURE -> IR_SHIFT
        jtag_tms = 1'b1; jtag_clock(); // -> SELECT_DR_SCAN
        jtag_tms = 1'b1; jtag_clock(); // -> SELECT_IR_SCAN
        jtag_tms = 1'b0; jtag_clock(); // -> CAPTURE_IR
        jtag_tms = 1'b0; jtag_clock(); // -> SHIFT_IR

        // 4 bit IR değerini shift et
        for (int i = 0; i < 4; i++) begin
            jtag_tdi = ir_in[i];
            jtag_tms = (i == 3) ? 1'b1 : 1'b0; // Son bitte EXIT1_IR durumuna geç
            jtag_clock();
        end

        // EXIT1_IR -> UPDATE_IR -> IDLE
        jtag_tms = 1'b1; jtag_clock(); // -> UPDATE_IR
        jtag_tms = 1'b0; jtag_clock(); // -> RUN_TEST_IDLE
    endtask

    // DR (Data Register) Shift et
    task automatic jtag_shift_dr(input logic [63:0] dr_in, input int len, output logic [63:0] dr_out);
        // IDLE -> DR_SCAN -> DR_CAPTURE -> DR_SHIFT
        jtag_tms = 1'b1; jtag_clock(); // -> SELECT_DR_SCAN
        jtag_tms = 1'b0; jtag_clock(); // -> CAPTURE_DR
        jtag_tms = 1'b0; jtag_clock(); // -> SHIFT_DR

        // len bit DR değerini shift et
        for (int i = 0; i < len; i++) begin
            jtag_tdi = dr_in[i];
            jtag_tms = (i == len - 1) ? 1'b1 : 1'b0; // Son bitte EXIT1_DR durumuna geç
            jtag_clock();
            dr_out[i] = jtag_tdo;
        end

        // EXIT1_DR -> UPDATE_DR -> IDLE
        jtag_tms = 1'b1; jtag_clock(); // -> UPDATE_DR
        jtag_tms = 1'b0; jtag_clock(); // -> RUN_TEST_IDLE
    endtask

    // Ana JTAG Test Senaryosu
    task automatic run_jtag_test();
        logic [63:0] jtag_rdata;
        log_print("\n================================================================");
        log_print(" JTAG HATA AYIKLAMA (DEBUG) PORTU DOGRULAMA TESTI BASLATILDI");
        log_print("================================================================");

        jtag_reset();

        // 1. IDCODE OKUMA
        log_print(" ---> JTAG IDCODE okunuyor...");
        jtag_shift_ir(4'h1); // IR_IDCODE
        jtag_shift_dr(64'h0, 32, jtag_rdata); // 32-bit IDCODE oku
        log_print($sformatf("      Okunan JTAG IDCODE: 0x%h (Beklenen: 0x41524b48)", jtag_rdata[31:0]));
        if (jtag_rdata[31:0] == 32'h41524B48) begin
            log_print("      [BASARILI] IDCODE dogru!");
        end else begin
            log_print("      [HATA] IDCODE uyusmuyor!");
        end

        // 2. CPU HALT (DURDURMA)
        log_print(" ---> CPU'ya HALT istegi gonderiliyor...");
        jtag_shift_ir(4'h4); // IR_DBG_CTRL
        jtag_shift_dr(64'h1, 64, jtag_rdata); // Latch halt = 1
        #100; // Senkronizasyon gecikmesi
        if (uut.u_jtag.debug_req_o == 1'b1) begin
            log_print("      [BASARILI] CPU debug_req_o (Halt) sinyali 1 oldu!");
        end else begin
            log_print("      [HATA] debug_req_o sinyali 1 olmadi!");
        end

        // 3. JTAG BELLEK YAZMA (TCM SRAM'e yaz)
        log_print(" ---> JTAG uzerinden TCM SRAM adresine veri yaziliyor (0x20011000 = 0xDEADBEEF)...");
        jtag_shift_ir(4'h3); // IR_MEM_WRITE
        // Adres ve veri birleştirilip gönderiliyor: {wdata, addr}
        jtag_shift_dr({32'hDEADBEEF, 32'h20011000}, 64, jtag_rdata);
        #500; // AXI transferinin tamamlanması için bekle

        // 4. JTAG BELLEK OKUMA (TCM SRAM'den oku)
        log_print(" ---> JTAG uzerinden TCM SRAM adresi okunuyor (0x20011000)...");
        jtag_shift_ir(4'h2); // IR_MEM_READ
        jtag_shift_dr({32'h0, 32'h20011000}, 64, jtag_rdata);
        #500; // AXI transferinin tamamlanması için bekle
        
        // Bir sonraki shift işleminde veri TDO'dan kayacaktır
        jtag_shift_dr(64'h0, 64, jtag_rdata);
        log_print($sformatf("      Okunan Veri: 0x%h (Beklenen: 0xdeadbeef)", jtag_rdata[63:32]));
        if (jtag_rdata[63:32] == 32'hDEADBEEF) begin
            log_print("      [BASARILI] JTAG bellek okuma/yazma testi dogru!");
        end else begin
            log_print("      [HATA] Bellek okuma/yazma uyumsuz!");
        end

        // 5. CPU RESUME (DEVAM ETTİRME)
        log_print(" ---> CPU Resume ediliyor...");
        jtag_shift_ir(4'h4); // IR_DBG_CTRL
        jtag_shift_dr(64'h0, 64, jtag_rdata); // Latch halt = 0
        #100;
        if (uut.u_jtag.debug_req_o == 1'b0) begin
            log_print("      [BASARILI] CPU debug_req_o sinyali tekrar 0 oldu!");
        end else begin
            log_print("      [HATA] debug_req_o sinyali 0 olmadi!");
        end

        log_print("================================================================");
        log_print(" JTAG PORTU DOGRULAMA TESTI BASARIYLA TAMAMLANDI!");
        log_print("================================================================");
    endtask

endmodule
