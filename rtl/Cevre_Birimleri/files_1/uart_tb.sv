// =============================================================================
// uart_tb.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - UART & UART-Stream Doğrulama Testi
//
// Şartname EK-3 gereği:
//   - Yönlendirilmiş self-checking testler
//   - Temel UART (UART1) ve UART Stream (UART2) çevre birimlerini tam doğrular
//   - Icarus Verilog, Verilator ve Vivado tam uyumlu
// =============================================================================

`timescale 1ns/1ps

module uart_tb;

    import uart_pkg::*;

    localparam int SYS_CLK_HZ  = 50_000_000;
    localparam int CLK_PERIOD  = 20;           // 50 MHz → 20 ns
    localparam int BAUD_RATE   = 1_000_000;    // 1 Mbps
    localparam int CPB_VAL     = SYS_CLK_HZ / BAUD_RATE; // 50

    int test_pass = 0;
    int test_fail = 0;

    logic clk = 0;
    logic rst_n = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic reset_dut();
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5)  @(posedge clk);
    endtask

    // =========================================================================
    // AXI-Lite Ortak Hatları
    // =========================================================================
    logic [AXI_ADDR_W-1:0] awaddr;
    logic                  awvalid;
    logic [AXI_DATA_W-1:0] wdata;
    logic [3:0]            wstrb = 4'hF;
    logic                  wvalid;
    logic                  bready = 1'b1;
    logic [AXI_ADDR_W-1:0] araddr;
    logic                  arvalid;
    logic                  rready = 1'b1;

    // DUT 1: Temel UART
    logic        u1_awready, u1_wready, u1_bvalid, u1_arready, u1_rvalid;
    logic [1:0]  u1_bresp, u1_rresp;
    logic [31:0] u1_rdata;
    logic        u1_txd, u1_rxd, u1_irq;

    assign u1_rxd = u1_txd; // Loopback

    uart_peripheral #(
        .SYS_CLK_HZ   (SYS_CLK_HZ),
        .DEFAULT_BAUD  (BAUD_RATE)
    ) dut_uart (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awaddr  (awaddr),
        .s_axil_awvalid (awvalid),
        .s_axil_awready (u1_awready),
        .s_axil_wdata   (wdata),
        .s_axil_wstrb   (wstrb),
        .s_axil_wvalid  (wvalid),
        .s_axil_wready  (u1_wready),
        .s_axil_bresp   (u1_bresp),
        .s_axil_bvalid  (u1_bvalid),
        .s_axil_bready  (bready),
        .s_axil_araddr  (araddr),
        .s_axil_arvalid (arvalid),
        .s_axil_arready (u1_arready),
        .s_axil_rdata   (u1_rdata),
        .s_axil_rresp   (u1_rresp),
        .s_axil_rvalid  (u1_rvalid),
        .s_axil_rready  (rready),
        .uart_rxd       (u1_rxd),
        .uart_txd       (u1_txd),
        .uart_irq       (u1_irq)
    );

    // DUT 2: UART Stream
    logic        u2_awready, u2_wready, u2_bvalid, u2_arready, u2_rvalid;
    logic [1:0]  u2_bresp, u2_rresp;
    logic [31:0] u2_rdata;
    logic        u2_txd, u2_rxd, u2_irq, u2_fifo_empty, u2_fifo_full;

    assign u2_rxd = u2_txd; // Loopback

    uart_stream_peripheral #(
        .SYS_CLK_HZ   (SYS_CLK_HZ),
        .DEFAULT_BAUD  (BAUD_RATE),
        .FIFO_DEPTH    (STREAM_FIFO_DEPTH)
    ) dut_uart_stream (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awaddr  (awaddr),
        .s_axil_awvalid (awvalid),
        .s_axil_awready (u2_awready),
        .s_axil_wdata   (wdata),
        .s_axil_wstrb   (wstrb),
        .s_axil_wvalid  (wvalid),
        .s_axil_wready  (u2_wready),
        .s_axil_bresp   (u2_bresp),
        .s_axil_bvalid  (u2_bvalid),
        .s_axil_bready  (bready),
        .s_axil_araddr  (araddr),
        .s_axil_arvalid (arvalid),
        .s_axil_arready (u2_arready),
        .s_axil_rdata   (u2_rdata),
        .s_axil_rresp   (u2_rresp),
        .s_axil_rvalid  (u2_rvalid),
        .s_axil_rready  (rready),
        .uart_rxd       (u2_rxd),
        .uart_txd       (u2_txd),
        .uart_stream_irq(u2_irq),
        .fifo_empty     (u2_fifo_empty),
        .fifo_full      (u2_fifo_full)
    );

    // =========================================================================
    // AXI Görevleri (Birim Seçimli)
    // =========================================================================
    task automatic axil_write_u1(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        awaddr <= addr; awvalid <= 1'b1;
        wdata  <= data; wvalid  <= 1'b1;
        @(posedge clk);
        while (!u1_awready) @(posedge clk);
        awvalid <= 1'b0;
        while (!u1_wready) @(posedge clk);
        wvalid <= 1'b0;
        while (!u1_bvalid) @(posedge clk);
        @(posedge clk);
    endtask

    task automatic axil_read_u1(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        araddr <= addr; arvalid <= 1'b1;
        @(posedge clk);
        while (!u1_arready) @(posedge clk);
        arvalid <= 1'b0;
        while (!u1_rvalid) @(posedge clk);
        data = u1_rdata;
        @(posedge clk);
    endtask

    task automatic axil_write_u2(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        awaddr <= addr; awvalid <= 1'b1;
        wdata  <= data; wvalid  <= 1'b1;
        @(posedge clk);
        while (!u2_awready) @(posedge clk);
        awvalid <= 1'b0;
        while (!u2_wready) @(posedge clk);
        wvalid <= 1'b0;
        while (!u2_bvalid) @(posedge clk);
        @(posedge clk);
    endtask

    task automatic axil_read_u2(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        araddr <= addr; arvalid <= 1'b1;
        @(posedge clk);
        while (!u2_arready) @(posedge clk);
        arvalid <= 1'b0;
        while (!u2_rvalid) @(posedge clk);
        data = u2_rdata;
        @(posedge clk);
    endtask

    task automatic check(input string test_name, input logic condition, input string fail_msg = "");
        if (condition) begin
            $display("[PASS] %s", test_name);
            test_pass++;
        end else begin
            $display("[FAIL] %s | %s", test_name, fail_msg);
            test_fail++;
        end
    endtask

    // =========================================================================
    // Test Senaryoları
    // =========================================================================
    logic [31:0] rd_val;

    task automatic test_cpb_rw();
        $display("\n--- Test 1: UART1 CPB Yazma/Okuma ---");
        axil_write_u1(UART_CPB_OFFSET, 32'd50);
        axil_read_u1(UART_CPB_OFFSET, rd_val);
        check("CPB = 50 (1Mbps)", rd_val == 32'd50);

        axil_write_u1(UART_CPB_OFFSET, 32'd434);
        axil_read_u1(UART_CPB_OFFSET, rd_val);
        check("CPB = 434 (115200bps)", rd_val == 32'd434);

        axil_write_u1(UART_CPB_OFFSET, CPB_VAL);
    endtask

    task automatic test_stp_config();
        $display("\n--- Test 2: UART1 Stop Bit Konfigürasyonu ---");
        axil_write_u1(UART_STP_OFFSET, 32'h00);
        axil_read_u1(UART_STP_OFFSET, rd_val);
        check("STP = 00 (1 stop bit)", rd_val[1:0] == 2'b00);

        axil_write_u1(UART_STP_OFFSET, 32'h01);
        axil_read_u1(UART_STP_OFFSET, rd_val);
        check("STP = 01 (1.5 stop bit)", rd_val[1:0] == 2'b01);

        axil_write_u1(UART_STP_OFFSET, 32'h02);
        axil_read_u1(UART_STP_OFFSET, rd_val);
        check("STP = 10 (2 stop bit)", rd_val[1:0] == 2'b10);

        axil_write_u1(UART_STP_OFFSET, 32'h00);
    endtask

    task automatic test_tx_rx_loopback(input logic [7:0] tx_byte);
        int timeout;
        logic [31:0] cfg_val;
        $display("\n--- Test 3: UART1 TX→RX Loopback (0x%02h) ---", tx_byte);

        axil_write_u1(UART_CFG_OFFSET, 32'h00);
        axil_write_u1(UART_TDR_OFFSET, {24'b0, tx_byte});
        axil_write_u1(UART_CFG_OFFSET, 32'h1); // TX_EN

        timeout = 0;
        do begin
            axil_read_u1(UART_CFG_OFFSET, cfg_val);
            @(posedge clk);
            timeout++;
        end while (!(cfg_val[CFG_TX_DONE] && cfg_val[CFG_RX_DONE]) && timeout < 10000);

        check("TX_DONE bayrağı kuruldu", cfg_val[CFG_TX_DONE]);
        check("RX_DONE bayrağı kuruldu", cfg_val[CFG_RX_DONE]);

        axil_read_u1(UART_RDR_OFFSET, rd_val);
        check($sformatf("Alınan veri doğru (0x%02h)", tx_byte), rd_val[7:0] == tx_byte);

        axil_write_u1(UART_CFG_OFFSET, 32'h00);
    endtask

    task automatic test_stream_fifo_and_pack();
        int timeout;
        logic [31:0] cfg_val;
        $display("\n--- Test 4: UART Stream (UART2) FIFO ve 32-Bit Paket Okuma ---");

        // Önce FIFO'yu yazılımdan temizle (UARTS_FIFO_CLR = 1)
        axil_write_u2(UARTS_FIFO_CLR_OFFSET, 32'h1);
        repeat(5) @(posedge clk);

        // Temizlik sonrası FIFO boş olmalı
        check("UART Stream FIFO Empty başlangıçta 1", u2_fifo_empty == 1'b1);

        // 4 bayt göndererek FIFO'ya loopback yap: 0x11, 0x22, 0x33, 0x44
        for (int i = 1; i <= 4; i++) begin
            logic [7:0] b;
            b = (i == 1) ? 8'h11 : (i == 2) ? 8'h22 : (i == 3) ? 8'h33 : 8'h44;
            
            axil_write_u2(UART_CFG_OFFSET, 32'h00);
            axil_write_u2(UART_TDR_OFFSET, {24'b0, b});
            axil_write_u2(UART_CFG_OFFSET, 32'h1); // TX_EN

            timeout = 0;
            do begin
                axil_read_u2(UART_CFG_OFFSET, cfg_val);
                @(posedge clk);
                timeout++;
            end while (!cfg_val[CFG_TX_DONE] && timeout < 10000);
            
            // Baytın RX durum makinesinden geçip FIFO'ya yazılması için 1 bit süresi bekle
            #2000;
        end

        // FIFO Doluluk Seviyesini Oku (Beklenen: 4)
        axil_read_u2(UARTS_FIFO_LEVEL_OFFSET, rd_val);
        check("UARTS_FIFO_LEVEL = 4 bayt", rd_val == 32'd4, $sformatf("Gelen: %0d", rd_val));

        // UARTS_RDR32 (0x20) üzerinden 4 baytı tek 32-bit kelimede oku (Beklenen: 0x44332211)
        axil_read_u2(8'h20, rd_val);
        check("UARTS_RDR32 Paketli Okuma Doğru (0x44332211)", rd_val == 32'h4433_2211, 
              $sformatf("Beklenen: 0x44332211, Gelen: 0x%08h", rd_val));

        // Okuma sonrası FIFO seviyesi 0 olmalı
        axil_read_u2(UARTS_FIFO_LEVEL_OFFSET, rd_val);
        check("Paket okuma sonrası FIFO boş (seviye=0)", rd_val == 32'd0, $sformatf("Gelen: %0d", rd_val));
    endtask

    // =========================================================================
    // Ana Akış
    // =========================================================================
    initial begin
        awaddr = '0; awvalid = 0; wdata = '0; wvalid = 0;
        araddr = '0; arvalid = 0;

        $display("=======================================================");
        $display("  TEKNOFEST 2026 - UART & UART-STREAM DOĞRULAMA TESTİ ");
        $display("=======================================================");

        reset_dut();

        test_cpb_rw();
        test_stp_config();
        test_tx_rx_loopback(8'hA5);
        test_tx_rx_loopback(8'h3C);
        test_stream_fifo_and_pack();

        $display("\n=======================================================");
        $display("  SONUÇ: %0d PASS, %0d FAIL", test_pass, test_fail);
        $display("=======================================================");

        if (test_fail != 0) begin
            $fatal(1, "UART doğrulaması başarısız");
        end else begin
            $display("  TÜM UART TESTLERİ BAŞARIYLA GEÇTİ!");
        end
        $finish;
    end

    // Watchdog
    initial begin
        #10_000_000; // 10 ms
        $fatal(1, "UART testbench zaman aşımına uğradı");
    end

endmodule
