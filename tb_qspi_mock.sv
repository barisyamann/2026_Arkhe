`timescale 1ns / 1ps
// =============================================================================
//  tb_qspi_mock.sv - QSPI Master blok seviyesi self-checking testbench
//  TEKNOFEST 2026 - Takim Arkhe
//  Icarus Verilog, Verilator ve Vivado Uyumlu Sürüm
// =============================================================================

module tb_qspi_mock;

    localparam int TEST_WORDS = 128;
    localparam string INIT_FILE = "qspi_test_pattern.hex";

    logic clk = 0;
    logic rst_n = 0;

    always #10 clk = ~clk;   // 50 MHz (20 ns)

    // AXI4-Lite
    logic [31:0] awaddr, wdata, araddr, rdata;
    logic        awvalid, wvalid, bready, arvalid, rready;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;
    logic        irq;

    // QSPI Ayrık Yön Sinyalleri
    logic        spi_sck, spi_cs_n;
    logic [3:0]  qspi_io_o, qspi_io_oe;
    wire  [3:0]  qspi_io_i;

    wire spi_io0, spi_io1, spi_io2, spi_io3;

    // Pad Halkası Sürücüleri
    assign spi_io0 = qspi_io_oe[0] ? qspi_io_o[0] : 1'bz;
    assign spi_io1 = qspi_io_oe[1] ? qspi_io_o[1] : 1'bz;
    assign spi_io2 = qspi_io_oe[2] ? qspi_io_o[2] : 1'bz;
    assign spi_io3 = qspi_io_oe[3] ? qspi_io_o[3] : 1'bz;

    assign qspi_io_i = {spi_io3, spi_io2, spi_io1, spi_io0};

    // Pull-up
    pullup(spi_io0); pullup(spi_io1); pullup(spi_io2); pullup(spi_io3);

    // Flash Model Seçimi (3-bayt vs 4-bayt)
    logic sel_4byte = 1'b0;
    wire  cs_n_3b = sel_4byte ? 1'b1 : spi_cs_n;
    wire  cs_n_4b = sel_4byte ? spi_cs_n : 1'b1;

    // Self-checking
    int error_count = 0;
    int check_count = 0;

    task automatic check(input string ad, input logic [31:0] gercek, input logic [31:0] beklenen);
        check_count++;
        if (gercek === beklenen)
            $display("      [OK]   %s = 0x%08h", ad, gercek);
        else begin
            error_count++;
            $display("      [HATA] %s: beklenen=0x%08h gercek=0x%08h", ad, beklenen, gercek);
        end
    endtask

    // Watchdog
    initial begin
        #2_000_000;   // 2 ms
        $display("      [HATA] ZAMAN ASIMI - test 2 ms icinde bitmedi");
        $display(" QSPI TESTI BASARISIZ - zaman asimi");
        $fatal(1, "QSPI testbench zaman asimi");
    end

    // =========================================================================
    // AXI4-Lite Görevleri (break'siz, Icarus uyumlu)
    // =========================================================================
    task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk);
        awaddr <= addr; awvalid <= 1'b1;
        wdata  <= data; wvalid  <= 1'b1; bready <= 1'b1;
        while (!awready) @(posedge clk);
        awvalid <= 1'b0;
        while (!wready) @(posedge clk);
        wvalid <= 1'b0;
        while (!bvalid) @(posedge clk);
        bready <= 1'b0;
    endtask

    task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        araddr <= addr; arvalid <= 1'b1; rready <= 1'b1;
        while (!arready) @(posedge clk);
        arvalid <= 1'b0;
        while (!rvalid) @(posedge clk);
        data = rdata;
        rready <= 1'b0;
    endtask

    task automatic bekle_bitti();
        logic [31:0] st;
        int          n;
        bit          done;
        n = 0;
        done = 1'b0;
        while (!done) begin
            axi_read(32'h0C, st);
            if (st[0]) begin
                done = 1'b1;
            end else if (n > 20000) begin
                $display("      [HATA] islem bitmedi - zaman asimi");
                error_count++;
                done = 1'b1;
            end
            n++;
            @(posedge clk);
        end
    endtask

    task automatic sck_periyodu_olc(input logic [5:0] presc, output int periyot_ns);
        time t1, t2;
        int timeout_cnt;
        
        axi_write(32'h04, 32'h0);
        axi_write(32'h00, {1'b1, presc, 1'b0, 8'h03, 5'b0, 2'b00, 1'b0, 8'h03});
        
        t1 = 0;
        t2 = 0;
        timeout_cnt = 0;

        // Ilk kenarlari bekle
        @(posedge spi_sck);
        @(posedge spi_sck);
        t1 = $time;
        @(posedge spi_sck);
        t2 = $time;

        periyot_ns = int'(t2 - t1);
        bekle_bitti();
    endtask

    // =========================================================================
    // Test Senaryosu
    // =========================================================================
    logic [31:0] v;

    initial begin
        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        $display("================================================================");
        $display(" QSPI MASTER BLOK TESTI - OKUMA (CMD 0x03) YOLU");
        $display("================================================================");

        // Flash 8 bayt oku (x1 mod)
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8807_0103);
        bekle_bitti();
        
        axi_read(32'h0C, v);
        check("QSPI_STA done biti", {31'b0, v[0]}, 32'h1);

        axi_read(32'h08, v);
        check("Flash kelime 0", v, 32'hA5A5_0000);

        axi_read(32'h08, v);
        check("Flash kelime 1", v, 32'hA5A5_0001);

        // 4-Bayt Adresleme Modu (CCR[24] = 1)
        sel_4byte = 1'b1;
        repeat (5) @(posedge clk);

        axi_write(32'h10, 32'h0000_0003); // FCR: Flush
        axi_write(32'h04, 32'h0000_0008);
        axi_write(32'h00, 32'h8907_0103);
        bekle_bitti();

        axi_read(32'h0C, v);
        check("4-bayt: QSPI_STA done biti", {31'b0, v[0]}, 32'h1);

        axi_read(32'h08, v);
        check("4-bayt: flash kelime 2", v, 32'hA5A5_0002);

        axi_read(32'h08, v);
        check("4-bayt: flash kelime 3", v, 32'hA5A5_0003);

        // Komut Kapsamı
        sel_4byte = 1'b0;
        repeat (5) @(posedge clk);

        // RDID (0x9F)
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h00, 32'h8802_019F);
        bekle_bitti();
        axi_read(32'h08, v);
        check("RDID = 01 02 19", v[23:0], 24'h1902_01);

        // WREN -> RDSR1
        axi_write(32'h00, 32'h8800_0006);
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h00, 32'h8800_0105);
        bekle_bitti();
        axi_read(32'h08, v);
        check("WREN sonrasi RDSR1.WEL", {31'b0, v[1]}, 32'h1);

        // WRDI -> RDSR1
        axi_write(32'h00, 32'h8800_0004);
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h00, 32'h8800_0105);
        bekle_bitti();
        axi_read(32'h08, v);
        check("WRDI sonrasi RDSR1.WEL", {31'b0, v[1]}, 32'h0);

        // QOR (0x6B) - Dört Hatlı Okuma (x4)
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8807_436B);
        bekle_bitti();
        axi_read(32'h08, v);
        check("QOR (x4) kelime 0", v, 32'hA5A5_0000);
        axi_read(32'h08, v);
        check("QOR (x4) kelime 1", v, 32'hA5A5_0001);

        // SE (0xD8) - Sektör Sil
        axi_write(32'h00, 32'h8800_0006);
        bekle_bitti();
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8800_00D8);
        bekle_bitti();

        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8803_0103);
        bekle_bitti();
        axi_read(32'h08, v);
        check("SE sonrasi silinmis kelime", v, 32'hFFFF_FFFF);

        // PP (0x02) - Sayfa Programla
        axi_write(32'h00, 32'h8800_0006);
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h08, 32'h1234_5678);
        axi_write(32'h00, 32'h8803_0502);
        bekle_bitti();

        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8803_0103);
        bekle_bitti();
        axi_read(32'h08, v);
        check("PP sonrasi geri okuma", v, 32'h1234_5678);

        // 256 Baytlık Tam Sayfa Programlama
        $display("  -- 256 baytlik tam sayfa programlama");
        begin
            logic [31:0] beklenen [0:63];
            int hatali;
            int pp_once;

            pp_once = u_flash_3b.pp_bayt;

            axi_write(32'h00, 32'h8800_0006);
            bekle_bitti();
            axi_write(32'h04, 32'h0000_0000);
            axi_write(32'h00, 32'h8800_00D8);
            bekle_bitti();

            axi_write(32'h00, 32'h8800_0006);
            bekle_bitti();
            axi_write(32'h10, 32'h0000_0003);
            axi_write(32'h04, 32'h0000_0100);
            for (int i = 0; i < 64; i++) begin
                beklenen[i] = {8'(i + 8'hC0), 8'(i + 8'h80),
                               8'(i + 8'h40), 8'(i)};
                axi_write(32'h08, beklenen[i]);
            end
            axi_write(32'h00, 32'h88FF_0502);
            bekle_bitti();

            check("256 bayt tam sayfa yazildi", u_flash_3b.pp_bayt - pp_once, 32'd256);

            axi_write(32'h10, 32'h0000_0003);
            axi_write(32'h04, 32'h0000_0100);
            axi_write(32'h00, 32'h88FF_0103);
            bekle_bitti();

            hatali = 0;
            for (int i = 0; i < 64; i++) begin
                axi_read(32'h08, v);
                if (v !== beklenen[i]) begin
                    if (hatali < 4)
                        $display("      [HATA] kelime %0d: beklenen=0x%08h gercek=0x%08h", i, beklenen[i], v);
                    hatali++;
                end
            end
            check("256 baytin TAMAMI dogru geri okundu", hatali, 32'd0);
        end

        // WEL yokken yazmama kontrolü
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0010);
        axi_write(32'h08, 32'h0000_0000);
        axi_write(32'h00, 32'h8803_0502);
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0010);
        axi_write(32'h00, 32'h8803_0103);
        bekle_bitti();
        axi_read(32'h08, v);
        check("WEL yokken PP yazmadi", v, 32'hFFFF_FFFF);

        // Prescaler Ölçümü
        $display("  -- Prescaler SCK periyodu (sartname: clk/(P+1))");
        begin
            int olculen;
            sck_periyodu_olc(6'd0, olculen);
            check("prescaler 0 -> 20 ns (sistem saati)", olculen, 32'd20);

            sck_periyodu_olc(6'd1, olculen);
            check("prescaler 1 -> 40 ns", olculen, 32'd40);

            sck_periyodu_olc(6'd2, olculen);
            check("prescaler 2 -> 60 ns", olculen, 32'd60);

            sck_periyodu_olc(6'd4, olculen);
            check("prescaler 4 -> 100 ns", olculen, 32'd100);
        end

        // Negatif Test: FIFO Boşken Okuma Hatası
        $display("  -- Negatif Test: FIFO Bosken Okuma");
        axi_write(32'h10, 32'h0000_0003);
        axi_read(32'h08, v);
        axi_read(32'h0C, v);
        check("FIFO Bos Okuma Hatasi (STA[11:8]==1)", {28'd0, v[11:8]}, 32'd1);

        axi_write(32'h00, 32'h8000_0000); // Clear error
        axi_read(32'h0C, v);
        check("Hata Temizlendi (STA[11:8]==0)", {28'd0, v[11:8]}, 32'd0);

        // Sonuç Özeti
        $display("================================================================");
        if (error_count != 0) begin
            $display(" QSPI TESTI BASARISIZ - %0d hata / %0d denetim", error_count, check_count);
            $display("================================================================");
            $fatal(1, "QSPI dogrulamasi basarisiz");
        end else begin
            $display(" QSPI TESTI GECTI - %0d denetim, 0 hata", check_count);
            $display("================================================================");
        end
        $finish;
    end

    // DUT
    qspi_master #(
        .FIFO_DEPTH (64),
        .AXI_AW     (32),
        .AXI_DW     (32)
    ) UUT (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awaddr  (awaddr),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),
        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (4'hF),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),
        .s_axi_araddr  (araddr),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready),
        .qspi_sck      (spi_sck),
        .qspi_cs_n     (spi_cs_n),
        .qspi_io_o     (qspi_io_o),
        .qspi_io_oe    (qspi_io_oe),
        .qspi_io_i     (qspi_io_i),
        .irq           (irq)
    );

    spi_flash_model #(
        .INIT_FILE  ("qspi_test_pattern.hex"),
        .WORD_COUNT (TEST_WORDS),
        .ADDR_BYTES (3)
    ) u_flash_3b (
        .sck   (spi_sck),
        .cs_n  (cs_n_3b),
        .io0   (spi_io0),
        .io1   (spi_io1),
        .io2   (spi_io2),
        .io3   (spi_io3)
    );

    spi_flash_model #(
        .INIT_FILE  ("qspi_test_pattern.hex"),
        .WORD_COUNT (TEST_WORDS),
        .ADDR_BYTES (4)
    ) u_flash_4b (
        .sck   (spi_sck),
        .cs_n  (cs_n_4b),
        .io0   (spi_io0),
        .io1   (spi_io1),
        .io2   (spi_io2),
        .io3   (spi_io3)
    );

endmodule
