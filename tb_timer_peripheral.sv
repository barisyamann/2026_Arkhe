`timescale 1ns / 1ps

module tb_timer_peripheral();

    // Parametreler
    localparam S_AXI_ADDR_WIDTH = 12;
    localparam S_AXI_DATA_WIDTH = 32;
    localparam CLK_PERIOD = 20; // 50 MHz

    // Sinyaller
    logic s_axi_aclk;
    logic s_axi_aresetn;
    logic [S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [2:0] s_axi_awprot;
    logic s_axi_awvalid;
    logic s_axi_awready;
    logic [S_AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [(S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb;
    logic s_axi_wvalid;
    logic s_axi_wready;
    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid;
    logic s_axi_bready;
    logic [S_AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [2:0] s_axi_arprot;
    logic s_axi_arvalid;
    logic s_axi_arready;
    logic [S_AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0] s_axi_rresp;
    logic s_axi_rvalid;
    logic s_axi_rready;
    logic timer_irq;

    // Yazmaç Offsetleri
    localparam ADDR_TIM_PRE = 12'h000;
    localparam ADDR_TIM_ARE = 12'h004;
    localparam ADDR_TIM_CLR = 12'h008;
    localparam ADDR_TIM_ENA = 12'h00C;
    localparam ADDR_TIM_MOD = 12'h010;
    localparam ADDR_TIM_CNT = 12'h014;
    localparam ADDR_TIM_EVN = 12'h018;
    localparam ADDR_TIM_EVC = 12'h01C;

    // DUT (Device Under Test)
    timer_peripheral #(
        .S_AXI_ADDR_WIDTH(S_AXI_ADDR_WIDTH),
        .S_AXI_DATA_WIDTH(S_AXI_DATA_WIDTH)
    ) dut (
        .*
    );

    // Clock Üretimi
    initial begin
        s_axi_aclk = 0;
        forever #(CLK_PERIOD/2) s_axi_aclk = ~s_axi_aclk;
    end

    // AXI4-Lite Yazma Görevi (Task)
    task axi_write(input [S_AXI_ADDR_WIDTH-1:0] addr, input [S_AXI_DATA_WIDTH-1:0] data);
        begin
            @(posedge s_axi_aclk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_wvalid  = 1;
            s_axi_bready  = 1;

            wait(s_axi_awready && s_axi_wready);
            @(posedge s_axi_aclk);
            s_axi_awvalid = 0;
            s_axi_wvalid  = 0;

            wait(s_axi_bvalid);
            @(posedge s_axi_aclk);
            s_axi_bready = 0;
        end
    endtask

    // AXI4-Lite Okuma Görevi (Task)
    task axi_read(input [S_AXI_ADDR_WIDTH-1:0] addr, output [S_AXI_DATA_WIDTH-1:0] data);
        begin
            @(posedge s_axi_aclk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1;
            s_axi_rready  = 1;

            wait(s_axi_arready);
            @(posedge s_axi_aclk);
            s_axi_arvalid = 0;

            wait(s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge s_axi_aclk);
            s_axi_rready = 0;
        end
    endtask

    // Test Senaryosu
    logic [31:0] read_val;

    initial begin
        // 1. Reset Durumu
        s_axi_aresetn = 0;
        s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wvalid = 0;
        s_axi_bready = 0; s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        
        #(CLK_PERIOD * 5);
        s_axi_aresetn = 1;
        #(CLK_PERIOD * 5);

        // 2. Timer Konfigürasyonu
        axi_write(ADDR_TIM_PRE, 32'd2); // Clock'u 3'e böl
        axi_write(ADDR_TIM_ARE, 32'd5); // 5'e kadar say
        axi_write(ADDR_TIM_MOD, 32'd1); // Yukarı say
        
        // 3. Modülü Başlat
        axi_write(ADDR_TIM_ENA, 32'd1);
        
        // 4. Kesme (IRQ) Bekleme ve Doğrulama
        wait(timer_irq == 1'b1);
        
        axi_read(ADDR_TIM_EVN, read_val);
        if (read_val !== 32'd1) begin
            $error("HATA: Event yazmacı beklendiği gibi artmadı. Okunan: %0d", read_val);
            $stop;
        end
        
        // 5. Kesmeyi Temizleme (EVC)
        axi_write(ADDR_TIM_EVC, 32'd1);
        #(CLK_PERIOD * 2);
        
        if (timer_irq !== 1'b0) begin
            $error("HATA: EVC yazıldıktan sonra timer_irq LOW olmadı!");
            $stop;
        end

        // 6. Sayacı Donanımsal Temizleme (CLR)
        axi_write(ADDR_TIM_CLR, 32'd1);
        axi_read(ADDR_TIM_CNT, read_val);
        
        if (read_val !== 32'd0) begin
            $error("HATA: CLR komutu sayacı sıfırlamadı!");
            $stop;
        end

        $display("========================================");
        $display("TÜM TESTLER BAŞARIYLA TAMAMLANDI");
        $display("========================================");
        $finish;
    end

endmodule