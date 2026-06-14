`timescale 1ns / 1ps

module tb_gpio_peripheral();

    // --- Parametreler ve Sinyaller ---
    parameter int AXI_ADDR_W = 8;
    parameter int AXI_DATA_W = 32;

    logic                    clk;
    logic                    rst_n;
    logic [15:0]             gpio_i;
    logic [15:0]             gpio_o;
    logic [15:0]             gpio_tx_en_o;
    logic                    global_interrupt_o;

    logic [AXI_ADDR_W-1:0]   s_axil_awaddr;
    logic                    s_axil_awvalid;
    logic                    s_axil_awready;
    logic [AXI_DATA_W-1:0]   s_axil_wdata;
    logic [3:0]              s_axil_wstrb;
    logic                    s_axil_wvalid;
    logic                    s_axil_wready;
    logic [1:0]              s_axil_bresp;
    logic                    s_axil_bvalid;
    logic                    s_axil_bready;
    logic [AXI_ADDR_W-1:0]   s_axil_araddr;
    logic                    s_axil_arvalid;
    logic                    s_axil_arready;
    logic [AXI_DATA_W-1:0]   s_axil_rdata;
    logic [1:0]              s_axil_rresp;
    logic                    s_axil_rvalid;
    logic                    s_axil_rready;

    // --- DUT (Design Under Test) Bağlantısı ---
    gpio_peripheral #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_DATA_W(AXI_DATA_W)
    ) dut (
        .* // SystemVerilog wildcard bağlantısı (isimler aynı olduğu için)
    );

    // --- Saat Üretici (50 MHz) ---
    always #10 clk = ~clk;

    // --- AXI4-Lite Yazma Görevi (Task) ---
    task axi_write(input [AXI_ADDR_W-1:0] addr, input [AXI_DATA_W-1:0] data);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= 4'hF;
            s_axil_wvalid  <= 1'b1;
            s_axil_bready  <= 1'b1;

            // Adres ve veri kabul edilene kadar bekle
            wait(s_axil_awready && s_axil_wready);
            @(posedge clk);
            s_axil_awvalid <= 1'b0;
            s_axil_wvalid  <= 1'b0;

            // Yazma yanıtı (BVALID) bekle
            wait(s_axil_bvalid);
            @(posedge clk);
            s_axil_bready  <= 1'b0;
        end
    endtask

    // --- AXI4-Lite Okuma Görevi (Task) ---
    task axi_read(input [AXI_ADDR_W-1:0] addr, output [AXI_DATA_W-1:0] data);
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;

            // Adres kabul edilene kadar bekle
            wait(s_axil_arready);
            @(posedge clk);
            s_axil_arvalid <= 1'b0;

            // Veri gelene kadar bekle
            wait(s_axil_rvalid);
            data = s_axil_rdata; // Gelen veriyi kaydet
            @(posedge clk);
            s_axil_rready  <= 1'b0;
        end
    endtask

    // --- Test Senaryosu ---
    logic [31:0] read_val;

    initial begin
        // 1. Başlangıç Değerleri ve Reset
        clk = 0;
        rst_n = 0;
        gpio_i = 16'h0000;
        
        s_axil_awaddr = 0; s_axil_awvalid = 0;
        s_axil_wdata = 0;  s_axil_wstrb = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        s_axil_araddr = 0; s_axil_arvalid = 0; s_axil_rready = 0;
        
        #50 rst_n = 1; // Sistemi uyandır
        #20;

        // 2. Çıkış Testi: ODR (0x04) yazmacına değer yaz (Örn: 16'hA5A5)
        $display("TEST 1: ODR Yazmacina Veri Yaziliyor...");
        axi_write(8'h04, 32'h0000A5A5);
        #20;
        if (gpio_o !== 16'hA5A5) $error("HATA: gpio_o pini beklenen degeri almadi!");

        // 3. Giriş Testi: Fiziksel gpio_i pinlerine dışarıdan veri ver
        $display("TEST 2: Fiziksel Pinlerden Veri Okunuyor...");
        gpio_i = 16'h1234;
        #50; // Senkronizasyon (2-stage flip-flop) icin bekle
        
        // IDR (0x00) yazmacini islemci gibi oku
        axi_read(8'h00, read_val);
        if (read_val[15:0] !== 16'h1234) $error("HATA: IDR yazmacindan yanlis veri okundu!");

        // 4. Set/Clear/Toggle Testi: SET (0x0C) yazmacini kullanarak pini 1 yap
        $display("TEST 3: SET Yazmaci ile pin durumunu degistirme...");
        axi_write(8'h0C, 32'h00000011); // 0. ve 4. bitleri set et
        #20;
        
        $display("TEST BASARIYLA TAMAMLANDI. Dalga formunu (Waveform) inceleyin.");
        $finish;
    end

endmodule