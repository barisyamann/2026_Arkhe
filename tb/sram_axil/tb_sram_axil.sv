`timescale 1ns / 1ps
//
// sram_module AXI-Lite okuma yolu hedefli oz-denetimli test
//
// Surucular negedge'de, el sikismalari posedge'de orneklenir: valid sinyali
// ancak kendisini tamamlayan posedge'den SONRA dusurulur.
//
module tb_sram_axil;
    localparam int DEPTH = 2048;   // 4 makro x 512 kelime
    localparam int AW = 32, DW = 32;
    localparam int GUARD = 200;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    logic [AW-1:0] awaddr = 0, araddr = 0;
    logic awvalid = 0, arvalid = 0, wvalid = 0, bready = 0, rready = 0;
    logic [DW-1:0] wdata = 0, rdata;
    logic [3:0] wstrb = 0;
    logic awready, wready, bvalid, arready, rvalid;
    logic [1:0] bresp, rresp;

    int errors = 0, checks = 0;
    bit bvalid_seen = 0;
    always @(posedge clk) if (bvalid && bready) bvalid_seen <= 1'b1;
    bit timeout_hit = 0;

    sram_module #(.AXI_ADDR_W(AW), .AXI_DATA_W(DW), .RAM_DEPTH(DEPTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid),
        .s_axil_wready(wready), .s_axil_bresp(bresp), .s_axil_bvalid(bvalid),
        .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid),
        .s_axil_rready(rready)
    );

    task automatic axi_write(input [AW-1:0] a, input [DW-1:0] d);
        int g;
        begin
            @(negedge clk);
            bvalid_seen = 1'b0;
            awaddr = a; awvalid = 1'b1;
            wdata  = d; wvalid  = 1'b1; wstrb = 4'hF;
            bready = 1'b1;

            g = 0;
            while ((awvalid || wvalid) && g < GUARD) begin
                @(negedge clk);          // NBA'lar oturmus, ready gercek degeri
                if (awvalid && awready) begin @(posedge clk); @(negedge clk); awvalid = 1'b0; end
                if (wvalid  && wready ) begin @(posedge clk); @(negedge clk); wvalid  = 1'b0; end
                g++;
            end
            if (g >= GUARD) begin timeout_hit = 1; $display("      [HATA] yazma AW/W zaman asimi"); return; end

            g = 0;
            while (!bvalid_seen && g < GUARD) begin @(negedge clk); g++; end
            if (g >= GUARD) begin timeout_hit = 1; $display("      [HATA] yazma BVALID zaman asimi"); return; end
            @(negedge clk); bready = 1'b0;
        end
    endtask

    task automatic axi_read(input [AW-1:0] a, output logic [DW-1:0] d,
                            input int rready_delay = 0);
        int g;
        begin
            d = 'x;
            @(negedge clk);
            araddr = a; arvalid = 1'b1; rready = 1'b0;

            g = 0;
            while (!arready && g < GUARD) begin @(negedge clk); g++; end
            if (g >= GUARD) begin timeout_hit = 1; $display("      [HATA] okuma ARREADY zaman asimi"); return; end
            @(posedge clk); @(negedge clk); arvalid = 1'b0;

            g = 0;
            while (!rvalid && g < GUARD) begin @(negedge clk); g++; end
            if (g >= GUARD) begin timeout_hit = 1; $display("      [HATA] okuma RVALID zaman asimi"); return; end

            repeat (rready_delay) begin @(posedge clk); @(negedge clk); end
            d = rdata;                   // cevrim ortasi: rvalid yuksek, NBA oturmus
            rready = 1'b1;
            @(posedge clk);              // el sikisma burada tamamlanir
            @(negedge clk); rready = 1'b0;
        end
    endtask

    task automatic check(input logic [DW-1:0] got, input logic [DW-1:0] exp, input string ad);
        begin
            checks++;
            if (got !== exp) begin
                errors++;
                $display("      [HATA] %s: beklenen %08h, gelen %08h", ad, exp, got);
            end else
                $display("      [OK]   %s = %08h", ad, got);
        end
    endtask

    logic [DW-1:0] rd;
    int unsigned a;

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("================================================");
        $display(" sram_module AXI-Lite okuma yolu testi");
        $display("================================================");

        $display(" --- 1) Makro sinirlari (4 makro x 512 kelime) ---");
        for (int m = 0; m < 4; m++) begin
            a = m*512 + m;
            axi_write(a*4, 32'hA0000000 + a);
        end
        for (int m = 0; m < 4; m++) begin
            a = m*512 + m;
            axi_read(a*4, rd);
            check(rd, 32'hA0000000 + a, $sformatf("makro%0d kelime %0d", m, a));
        end

        $display(" --- 2) Ardisik okuma (8 kelime) ---");
        for (int i = 0; i < 8; i++) axi_write(i*4, 32'hB0000000 + i);
        begin
            int bad = 0;
            for (int i = 0; i < 8; i++) begin
                axi_read(i*4, rd);
                checks++;
                if (rd !== 32'hB0000000 + i) begin
                    errors++; bad++;
                    $display("      [HATA] ardisik %0d: beklenen %08h, gelen %08h",
                             i, 32'hB0000000+i, rd);
                end
            end
            if (bad == 0) $display("      [OK]   8 ardisik okumanin hepsi dogru");
        end

        $display(" --- 3) Geciken rready (rdata_hold yolu) ---");
        axi_write(32'h40, 32'hC0FFEE01);
        axi_read(32'h40, rd, 0); check(rd, 32'hC0FFEE01, "rready gecikme 0");
        axi_read(32'h40, rd, 1); check(rd, 32'hC0FFEE01, "rready gecikme 1");
        axi_read(32'h40, rd, 3); check(rd, 32'hC0FFEE01, "rready gecikme 3");
        axi_read(32'h40, rd, 7); check(rd, 32'hC0FFEE01, "rready gecikme 7");

        $display(" --- 4) Son adres ---");
        axi_write((DEPTH-1)*4, 32'hDEADC0DE);
        axi_read((DEPTH-1)*4, rd);
        check(rd, 32'hDEADC0DE, $sformatf("kelime %0d", DEPTH-1));

        $display("================================================");
        if (errors == 0 && !timeout_hit)
            $display(" TEST BASARILI - %0d denetimin hepsi gecti", checks);
        else
            $display(" TEST BASARISIZ - %0d denetim, %0d hata%s",
                     checks, errors, timeout_hit ? " (zaman asimi da var)" : "");
        $display("================================================");
        $finish;
    end

    initial begin
        #2000000;
        $display(" TEST BASARISIZ - genel zaman asimi");
        $finish;
    end
endmodule
