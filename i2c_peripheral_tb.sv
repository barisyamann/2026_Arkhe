// =============================================================================
// TEKNOFEST 2026 - I2C Master Çevre Birimi Testbench (AXI4-Lite)
// Sanal I2C Slave (Sensör/EEPROM) Modeli İçerir
// =============================================================================
`timescale 1ns/1ps

module i2c_peripheral_tb;

    localparam CLK_PERIOD = 20.833; // 48 MHz
    
    logic        clk, rst_n;
    logic [7:0]  s_axil_awaddr;  logic s_axil_awvalid, s_axil_awready;
    logic [31:0] s_axil_wdata;   logic [3:0] s_axil_wstrb;
    logic        s_axil_wvalid,  s_axil_wready;
    logic [1:0]  s_axil_bresp;   logic s_axil_bvalid, s_axil_bready;
    logic [7:0]  s_axil_araddr;  logic s_axil_arvalid, s_axil_arready;
    logic [31:0] s_axil_rdata;   logic [1:0] s_axil_rresp;
    logic        s_axil_rvalid,  s_axil_rready;

    // I2C Fiziksel Pinleri
    wire         scl;
    wire         sda;
    
    // Testbench'in SDA hattını sürebilmesi için (Sanal Slave)
    logic        sda_drv;
    assign sda = sda_drv;
    
    // I2C Open-Drain Pull-up Dirençleri
    pullup(scl);
    pullup(sda);

    int pass_count = 0, fail_count = 0;

    // DUT (Test Edilecek Tasarım)
    i2c_peripheral #(
        .SYS_CLK_FREQ(48_000_000), 
        .I2C_FREQ(400_000)
    ) dut (.*);

    // Saat Sinyali
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // AXI-Lite Görevleri
    // =========================================================================
    task axil_write(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        s_axil_awaddr = addr; s_axil_awvalid = 1'b1;
        s_axil_wdata  = data; s_axil_wstrb   = 4'hF; s_axil_wvalid = 1'b1; s_axil_bready = 1'b1;
        fork
            begin wait(s_axil_awready); @(posedge clk); s_axil_awvalid = 1'b0; end
            begin wait(s_axil_wready);  @(posedge clk); s_axil_wvalid  = 1'b0; end
        join
        wait(s_axil_bvalid); @(posedge clk); s_axil_bready = 1'b0;
    endtask

    task axil_read(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        s_axil_araddr = addr; s_axil_arvalid = 1'b1; s_axil_rready = 1'b1;
        wait(s_axil_arready); @(posedge clk); s_axil_arvalid = 1'b0;
        wait(s_axil_rvalid); data = s_axil_rdata;
        @(posedge clk); s_axil_rready = 1'b0;
    endtask

    // =========================================================================
    // SANAL I2C SLAVE GÖREVLERİ (Master'a Yanıt Verir)
    // =========================================================================
    task wait_start();
        @(negedge sda iff scl === 1'b1);
    endtask

    task wait_stop();
        @(posedge sda iff scl === 1'b1);
    endtask

    task rx_byte_and_ack(output logic [7:0] data);
        for(int i=7; i>=0; i--) begin
            @(posedge scl);
            data[i] = sda;
        end
        @(negedge scl);
        sda_drv = 1'b0; // Slave ACK basıyor
        @(negedge scl);
        sda_drv = 1'bz; // Hattı serbest bırak
    endtask

    task tx_byte(input logic [7:0] data);
        for(int i=7; i>=0; i--) begin
            @(negedge scl);
            sda_drv = data[i];
        end
        @(negedge scl);
        sda_drv = 1'bz; // Master ACK/NACK basacak
        @(negedge scl); // Bir saykıl bekle
    endtask

    task check(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin $display("[PASS] %s", name); pass_count++; end
        else begin $display("[FAIL] %s: Got %h, Exp %h", name, got, exp); fail_count++; end
    endtask

    // =========================================================================
    // TEST SENARYOSU
    // =========================================================================
    initial begin
        logic [31:0] rdata;
        
        sda_drv = 1'bz;
        rst_n = 1'b0;
        s_axil_awvalid = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        s_axil_arvalid = 0; s_axil_rready = 0;
        
        repeat(10) @(posedge clk); rst_n = 1'b1; repeat(10) @(posedge clk);

        $display("--- I2C TEST BAŞLIYOR ---");

        // ---------------------------------------------------------------------
        // TEST 1: I2C MASTER YAZMA (TX) İŞLEMİ
        // ---------------------------------------------------------------------
        axil_write(8'h00, 32'd2);       // I2C_NBY = 2 Bayt
        axil_write(8'h04, 32'h5A);      // I2C_ADR = 0x5A
        axil_write(8'h0C, 32'hBEEF);    // I2C_TDR = 0xBEEF (LSB First: Önce EF, Sonra BE)
        axil_write(8'h10, 32'h01);      // I2C_CFG = 1 (TX_EN)

        // Sanal Slave: Master'ın gönderdiklerini dinliyor ve ACK veriyor
        begin
            logic [7:0] rbyte;
            wait_start();
            rx_byte_and_ack(rbyte); 
            check("TX Slave Addr + W", rbyte, (8'h5A << 1) | 8'h00); // 0xB4 beklenir
            
            rx_byte_and_ack(rbyte); 
            check("TX Byte 0", rbyte, 8'hEF); // LSB önce
            
            rx_byte_and_ack(rbyte); 
            check("TX Byte 1", rbyte, 8'hBE); // MSB sonra
            wait_stop();
        end

        // HW Flag Kontrolü
        axil_read(8'h10, rdata);
        check("TX_DONE (CFG[1]) HW Set", rdata[1], 1'b1);
        axil_write(8'h10, 32'h00); // Interrupt temizle

        // ---------------------------------------------------------------------
        // TEST 2: I2C MASTER OKUMA (RX) İŞLEMİ
        // ---------------------------------------------------------------------
        axil_write(8'h00, 32'd2);       // I2C_NBY = 2 Bayt
        axil_write(8'h04, 32'h5A);      // I2C_ADR = 0x5A
        axil_write(8'h10, 32'h04);      // I2C_CFG = 4 (RX_EN - Bit 2)

        // Sanal Slave: Master'a veri gönderiyor
        begin
            logic [7:0] rbyte;
            wait_start();
            rx_byte_and_ack(rbyte);
            check("RX Slave Addr + R", rbyte, (8'h5A << 1) | 8'h01); // 0xB5 beklenir
            
            tx_byte(8'h12); // Master'a 0x12 gönder
            tx_byte(8'h34); // Master'a 0x34 gönder
            wait_stop();
        end

        // HW Flag Kontrolü ve Veri Doğrulama
        axil_read(8'h10, rdata);
        check("RX_DONE (CFG[3]) HW Set", rdata[3], 1'b1);
        
        axil_read(8'h08, rdata);
        check("RX Data (RDR) Dogru", rdata[15:0], 16'h3412); // LSB first, 0x12 alt bayta
        
        axil_write(8'h10, 32'h00); // Interrupt temizle

        $display("--- ÖZET: %0d PASS, %0d FAIL ---", pass_count, fail_count);
        $finish;
    end
endmodule