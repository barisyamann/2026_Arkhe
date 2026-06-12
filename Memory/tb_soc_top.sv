`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 11.06.2026
// Design Name: tb_soc_top
// Module Name: tb_soc_top
// Description: Testbench to verify Arkhe SoC Top Integration in Vivado.
//              Generates a 50 MHz clock, handles system reset, and mocks
//              external peripheral pins to verify early CPU boot cycles.
// 
//////////////////////////////////////////////////////////////////////////////////

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
    );

    // --- Saat Üreteci (50 MHz -> 20ns Periyot) ---
    always begin
        clk = 1'b0;
        #10;
        clk = 1'b1;
        #10;
    end

    // --- Test Akışı ---
    initial begin
        $display("[%0t] SoC Simülasyonu Başlatıldı.", $time);
        
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

        $display("[%0t] Reset kaldırıldı. İşlemci çalışıyor...", $time);

        // İşlemcinin Boot ROM'dan kod çekmesini bekleyin ve simülasyonu izleyin
        #150000; // NPU çıkarımı için gereken zamanı kapsayacak şekilde simülasyon süresini artırdık

        // GPIO Pinlerini Değiştirip Test Etme
        @ (posedge clk);
        gpio_i = 16'hA5A5;
        $display("[%0t] GPIO girişleri 0xA5A5 olarak ayarlandı.", $time);

        #5000;
        $display("[%0t] SoC Simülasyonu Tamamlandı.", $time);
        $finish;
    end

    // --- İzleme (Monitoring) ---
    always @(posedge clk) begin
        if (rst_n) begin
            $display("[%0t] PC_ID=0x%h | x10(a0)=0x%h | x12(a2)=0x%h | x13(a3)=0x%h | x14(a4)=0x%h | x15(a5)=0x%h | awaddr=0x%h | awvalid=%b | rx_wr=%0d | rx_rd=%0d | rx_empty=%0b", 
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
                     uut.u_qspi.rx_empty);
        end
    end

    always @(gpio_o) begin
        $display("[%0t] GPIO Çıkışı Değişti: gpio_o = 16'h%h", $time, gpio_o);
    end

    // DMA Interrupt Monitoring
    always @(posedge clk) begin
        if (rst_n && uut.dma_irq) begin
            $display("[%0t] *** DMA Transfer Tamamlandı - IRQ aktif ***", $time);
        end
    end

    // I2C Interrupt Monitoring
    always @(posedge clk) begin
        if (rst_n && uut.i2c_irq) begin
            $display("[%0t] *** I2C İşlemi Tamamlandı - IRQ aktif ***", $time);
        end
    end

endmodule
