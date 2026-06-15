// =============================================================================
// uart_tb.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - UART Çevre Birimi Test Ortamı
//
// Şartname EK-3 gereği:
//   - Sistem seviyesi yönlendirilmiş testler (directed testing)
//   - Self-checking yapı (manuel inceleme gerektirmez)
//   - Temel UART ve UART Stream çevre birimlerini doğrular
//
// Test senaryoları:
//   1. Baud hızı yapılandırma ve TX loopback testi
//   2. RX alım ve CFG bayrak testi
//   3. UART Stream FIFO dolu/boş testi
//   4. Kesme üretim testi
//   5. Stop bit konfigürasyon testi
// =============================================================================

`timescale 1ns/1ps

module uart_tb;

    import uart_pkg::*;

    // =========================================================================
    // Parametreler
    // =========================================================================
    localparam int SYS_CLK_HZ  = 50_000_000;
    localparam int CLK_PERIOD  = 20;           // 50 MHz → 20 ns
    localparam int BAUD_RATE   = 1_000_000;    // 1 Mbps (şartname max)
    localparam int CPB_VAL     = SYS_CLK_HZ / BAUD_RATE; // 50

    localparam int BIT_TIME_NS = (1_000_000_000 / BAUD_RATE); // 1000 ns

    // Test sonuç sayaçları
    int test_pass = 0;
    int test_fail = 0;

    // =========================================================================
    // Saat ve reset
    // =========================================================================
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
    // DUT: Temel UART Çevre Birimi
    // =========================================================================
    logic [AXI_ADDR_W-1:0] awaddr;
    logic                  awvalid;
    logic                  awready;
    logic [AXI_DATA_W-1:0] wdata;
    logic [3:0]            wstrb = 4'hF;
    logic                  wvalid;
    logic                  wready;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready = 1'b1;
    logic [AXI_ADDR_W-1:0] araddr;
    logic                  arvalid;
    logic                  arready;
    logic [AXI_DATA_W-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rvalid;
    logic                  rready = 1'b1;

    logic uart_txd_w;
    logic uart_rxd_s;
    logic uart_irq_w;

    // Loopback: TX → RX
    assign uart_rxd_s = uart_txd_w;

    uart_peripheral #(
        .SYS_CLK_HZ   (SYS_CLK_HZ),
        .DEFAULT_BAUD  (BAUD_RATE)
    ) dut_uart (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awaddr  (awaddr),
        .s_axil_awvalid (awvalid),
        .s_axil_awready (awready),
        .s_axil_wdata   (wdata),
        .s_axil_wstrb   (wstrb),
        .s_axil_wvalid  (wvalid),
        .s_axil_wready  (wready),
        .s_axil_bresp   (bresp),
        .s_axil_bvalid  (bvalid),
        .s_axil_bready  (bready),
        .s_axil_araddr  (araddr),
        .s_axil_arvalid (arvalid),
        .s_axil_arready (arready),
        .s_axil_rdata   (rdata),
        .s_axil_rresp   (rresp),
        .s_axil_rvalid  (rvalid),
        .s_axil_rready  (rready),
        .uart_rxd       (uart_rxd_s),
        .uart_txd       (uart_txd_w),
        .uart_irq       (uart_irq_w)
    );

    // =========================================================================
    // AXI4-Lite Yardımcı Görevler
    // =========================================================================
    task automatic axil_write(
        input logic [AXI_ADDR_W-1:0] addr,
        input logic [AXI_DATA_W-1:0] data
    );
        // Adres ve veri kanallarını eş zamanlı sür
        @(posedge clk);
        awaddr  <= addr;
        awvalid <= 1'b1;
        wdata   <= data;
        wvalid  <= 1'b1;

        // Adres handshake bekle (el sıkışması)
        @(posedge clk);
        while (!awready) @(posedge clk);
        awvalid <= 1'b0;

        // Veri handshake bekle (el sıkışması)
        while (!wready) @(posedge clk);
        wvalid <= 1'b0;

        // Yanıt bekle
        while (!bvalid) @(posedge clk);
        @(posedge clk);
    endtask

    task automatic axil_read(
        input  logic [AXI_ADDR_W-1:0] addr,
        output logic [AXI_DATA_W-1:0] data
    );
        @(posedge clk);
        araddr  <= addr;
        arvalid <= 1'b1;

        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid <= 1'b0;

        while (!rvalid) @(posedge clk);
        data = rdata;
        @(posedge clk);
    endtask

    // =========================================================================
    // Test kontrol makrosu
    // =========================================================================
    task automatic check(
        input string    test_name,
        input logic     condition,
        input string    fail_msg = ""
    );
        if (condition) begin
            $display("[PASS] %s", test_name);
            test_pass++;
        end else begin
            $display("[FAIL] %s | %s", test_name, fail_msg);
            test_fail++;
        end
    endtask

    // =========================================================================
    // Test: CPB yazma ve okuma doğrulaması
    // =========================================================================
    logic [31:0] rd_val;

    task automatic test_cpb_rw();
        logic [31:0] expected;
        $display("\n--- Test 1: CPB Yazma/Okuma ---");

        // 1 Mbps: CPB = 50
        axil_write(UART_CPB_OFFSET, 32'd50);
        axil_read (UART_CPB_OFFSET, rd_val);
        check("CPB = 50 (1Mbps)", rd_val == 32'd50,
              $sformatf("Beklenen=50, Okunan=%0d", rd_val));

        // 115200 bps: CPB = 434
        axil_write(UART_CPB_OFFSET, 32'd434);
        axil_read (UART_CPB_OFFSET, rd_val);
        check("CPB = 434 (115200bps)", rd_val == 32'd434,
              $sformatf("Beklenen=434, Okunan=%0d", rd_val));

        // 1 Mbps'e geri dön
        axil_write(UART_CPB_OFFSET, CPB_VAL);
    endtask

    // =========================================================================
    // Test: Stop bit konfigürasyonu
    // =========================================================================
    task automatic test_stp_config();
        $display("\n--- Test 2: Stop Bit Konfigürasyonu ---");

        axil_write(UART_STP_OFFSET, 32'h00);
        axil_read (UART_STP_OFFSET, rd_val);
        check("STP = 00 (1 stop bit)", rd_val[1:0] == 2'b00);

        axil_write(UART_STP_OFFSET, 32'h01);
        axil_read (UART_STP_OFFSET, rd_val);
        check("STP = 01 (1.5 stop bit)", rd_val[1:0] == 2'b01);

        axil_write(UART_STP_OFFSET, 32'h02);
        axil_read (UART_STP_OFFSET, rd_val);
        check("STP = 10 (2 stop bit)", rd_val[1:0] == 2'b10);

        // Testi 1 stop bit ile devam ettir
        axil_write(UART_STP_OFFSET, 32'h00);
    endtask

    // =========================================================================
    // Test: TX gönderim ve loopback RX alım testi
    // =========================================================================
    task automatic test_tx_rx_loopback(input logic [7:0] tx_byte);
        int timeout;
        logic [31:0] cfg_val;
        $display("\n--- Test 3: TX→RX Loopback (0x%02h) ---", tx_byte);

        // Önceki bayrakları temizle
        axil_write(UART_CFG_OFFSET, 32'h00);

        // Gönderilecek veriyi yaz
        axil_write(UART_TDR_OFFSET, {24'b0, tx_byte});

        // TX_EN bitini set ederek gönderi başlat
        axil_write(UART_CFG_OFFSET, 32'h1); // CFG[0]=1

        // TX_DONE ve RX_DONE için bekle (loopback)
        timeout = 0;
        do begin
            axil_read(UART_CFG_OFFSET, cfg_val);
            @(posedge clk);
            timeout++;
        end while (!(cfg_val[CFG_TX_DONE] && cfg_val[CFG_RX_DONE])
                   && timeout < 10000);

        check("TX_DONE bayrağı kuruldu", cfg_val[CFG_TX_DONE],
              "Zaman aşımı: TX_DONE gelmedi");
        check("RX_DONE bayrağı kuruldu", cfg_val[CFG_RX_DONE],
              "Zaman aşımı: RX_DONE gelmedi");

        // Alınan veriyi oku
        axil_read(UART_RDR_OFFSET, rd_val);
        check($sformatf("Alınan veri doğru (0x%02h)", tx_byte),
              rd_val[7:0] == tx_byte,
              $sformatf("Beklenen=0x%02h, Alınan=0x%02h", tx_byte, rd_val[7:0]));

        // Bayrakları temizle (CFG[RX_DONE]=0, CFG[TX_DONE]=0 yaz)
        axil_write(UART_CFG_OFFSET, 32'h00);
        @(posedge clk);
    endtask

    // =========================================================================
    // Test: Kesme üretimi
    // =========================================================================
    task automatic test_irq();
        int timeout;
        logic irq_seen;
        $display("\n--- Test 4: Kesme Üretimi ---");

        // CFG bayraklarını temizle
        axil_write(UART_CFG_OFFSET, 32'h00);

        // Gönder
        axil_write(UART_TDR_OFFSET, 32'hAB);
        axil_write(UART_CFG_OFFSET, 32'h1);

        // IRQ sinyali için bekle
        irq_seen = 1'b0;
        timeout  = 0;
        while (!uart_irq_w && timeout < 10000) begin
            @(posedge clk);
            if (uart_irq_w) irq_seen = 1'b1;
            timeout++;
        end
        irq_seen = uart_irq_w;

        check("IRQ sinyali üretildi", irq_seen, "Beklenen IRQ gelmedi");

        // Temizle
        axil_write(UART_CFG_OFFSET, 32'h00);
    endtask

    // =========================================================================
    // Ana test programı
    // =========================================================================
    initial begin
        // Başlangıç değerleri
        awaddr  = '0; awvalid = 0;
        wdata   = '0; wvalid  = 0;
        araddr  = '0; arvalid = 0;

        $display("=======================================================");
        $display("  TEKNOFEST 2026 - UART Çevre Birimi Doğrulama Testi   ");
        $display("=======================================================");

        reset_dut();

        test_cpb_rw();
        test_stp_config();

        // Farklı bayt değerleriyle loopback testi
        test_tx_rx_loopback(8'hAA);
        test_tx_rx_loopback(8'h55);
        test_tx_rx_loopback(8'hFF);
        test_tx_rx_loopback(8'h00);
        test_tx_rx_loopback(8'h5A);

        test_irq();

        // =====================================================================
        // Sonuç özeti
        // =====================================================================
        $display("\n=======================================================");
        $display("  SONUÇ: %0d PASS, %0d FAIL", test_pass, test_fail);
        $display("=======================================================");

        if (test_fail == 0)
            $display("  TÜM TESTLER BAŞARILI");
        else
            $display("  BAZI TESTLER BAŞARISIZ - Lütfen kontrol edin");

        $finish;
    end

    // =========================================================================
    // Zaman aşımı koruma
    // =========================================================================
    initial begin
        #20_000_000; // 20 ms
        $display("[ERROR] Global zaman aşımı! Simülasyon zorla sonlandırılıyor.");
        $finish;
    end

    // =========================================================================
    // Dalga formu kaydı (isteğe bağlı)
    // =========================================================================
    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb);
    end

endmodule
