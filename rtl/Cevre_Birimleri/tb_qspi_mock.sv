`timescale 1ns / 1ps
// =============================================================================
//  tb_qspi_mock.sv - QSPI Master blok seviyesi self-checking testbench
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN YENIDEN YAZILDI (18 Agustos 2026):
//
//  Eski surum iki nedenle HIC CALISAMIYORDU:
//
//    1. Satici flash modeli MT25QL256ABA8E12'yi ornekliyordu; bu modul
//       depoda YOK. Yani testbench derlenemiyordu bile. Sartname "butun
//       testbench kodlari"ni teslim isteri olarak sayiyor - derlenmeyen
//       testbench teslim etmek, hic teslim etmemekten kotudur.
//
//    2. qspi_io0..3 cift yonlu portlarini kullaniyordu. Tri-state ayrimi
//       sonrasi (ASIC uyumu) bu portlar qspi_io_o / _oe / _i uclusune
//       donustu.
//
//  Ayrica eski test Page Program (0x02) YAZMA deniyordu ve hicbir sey
//  dogrulamiyordu - yalnizca #5000 bekleyip $finish cagiriyordu.
//
//  Yeni test OKUMA (CMD 0x03) yolunu dogruluyor. Boot akisinin kullandigi
//  islem budur: yukleyici uygulamayi flash'tan bu komutla okur.
//  Kendi spi_flash_model'imiz kullaniliyor (tb/spi_flash_model.sv).
// =============================================================================

module tb_qspi_mock;

    // -------------------------------------------------------------------------
    // Test verisi: 8 kelime, bilinen desen
    //   word[i] = 32'hA5A50000 + i
    // Flash modeli kelimeleri little-endian bayt dizisine aciyor.
    // -------------------------------------------------------------------------
    localparam int TEST_WORDS = 8;
    localparam string INIT_FILE = "qspi_test_pattern.hex";  // tb/ altinda sabit dosya

    logic clk = 0;
    logic rst_n = 0;

    always #10 clk = ~clk;   // 50 MHz

    // AXI4-Lite
    logic [31:0] awaddr, wdata, araddr, rdata;
    logic        awvalid, wvalid, bready, arvalid, rready;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;
    logic        irq;

    // QSPI - ayrik yon sinyalleri (tri-state modul icinde DEGIL)
    logic        spi_sck, spi_cs_n;
    logic [3:0]  qspi_io_o, qspi_io_oe;
    wire  [3:0]  qspi_io_i;

    wire spi_io0, spi_io1, spi_io2, spi_io3;

    // Ucdurumlu surucu halkasi - ASIC'te bu katmanin yerini pad halkasi alir
    assign spi_io0 = qspi_io_oe[0] ? qspi_io_o[0] : 1'bz;
    assign spi_io1 = qspi_io_oe[1] ? qspi_io_o[1] : 1'bz;
    assign spi_io2 = qspi_io_oe[2] ? qspi_io_o[2] : 1'bz;
    assign spi_io3 = qspi_io_oe[3] ? qspi_io_o[3] : 1'bz;

    assign qspi_io_i = {spi_io3, spi_io2, spi_io1, spi_io0};

    // Harici pull-up'lar
    pullup(spi_io0); pullup(spi_io1); pullup(spi_io2); pullup(spi_io3);

    // =========================================================================
    // Self-checking altyapisi
    // =========================================================================
    int error_count = 0;
    int check_count = 0;

    task automatic check(input string ad, input logic [31:0] gercek,
                                          input logic [31:0] beklenen);
        check_count++;
        if (gercek === beklenen)
            $display("      [OK]   %s = 0x%08h", ad, gercek);
        else begin
            error_count++;
            $display("      [HATA] %s: beklenen=0x%08h gercek=0x%08h",
                     ad, beklenen, gercek);
        end
    endtask

    // Gozcu - test hicbir kosulda asili kalmamali
    initial begin
        #2_000_000;   // 2 ms
        $display("      [HATA] ZAMAN ASIMI - test 2 ms icinde bitmedi");
        $display(" QSPI TESTI BASARISIZ - zaman asimi");
        $fatal(1, "QSPI testbench zaman asimi");
    end

    // =========================================================================
    // AXI4-Lite gorevleri
    // =========================================================================
    task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk);
        awaddr <= addr; awvalid <= 1'b1;
        wdata  <= data; wvalid  <= 1'b1; bready <= 1'b1;
        forever begin @(posedge clk); if (awready) break; end
        awvalid <= 1'b0;
        forever begin if (wready) break; @(posedge clk); end
        wvalid <= 1'b0;
        forever begin @(posedge clk); if (bvalid) break; end
        bready <= 1'b0;
    endtask

    task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        araddr <= addr; arvalid <= 1'b1; rready <= 1'b1;
        forever begin @(posedge clk); if (arready) break; end
        arvalid <= 1'b0;
        forever begin @(posedge clk); if (rvalid) break; end
        data = rdata;
        rready <= 1'b0;
    endtask

    // =========================================================================
    // Test senaryosu
    // =========================================================================
    logic [31:0] v;
    int          waited;

    initial begin
        // NOT: Flash icerigi tb/qspi_test_pattern.hex dosyasindan gelir.
        //
        // Eskiden bu dosya testbench icinde $fopen ile URETILIYORDU ve bu
        // bir YARIS yaratiyordu: spi_flash_model da kendi initial blogunda
        // $readmemh yapiyor, SystemVerilog ise initial bloklarinin sirasini
        // garanti etmiyor. Dosya onceki kosumdan kalmissa test geciyor,
        // temiz dizinde ise flash sifir okuyordu.

        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        $display("================================================================");
        $display(" QSPI MASTER BLOK TESTI - OKUMA (CMD 0x03) YOLU");
        $display("================================================================");

        // ---------------------------------------------------------------------
        // Flash'tan 8 bayt oku: adres 0x000000, CMD 0x03, tek hatli mod
        //
        // CCR bit alanlari (qspi_master.sv):
        //   [7:0]   komut          = 0x03 (READ)
        //   [9:8]   veri modu      = 01 (tek hatli)
        //   [10]    write_read_n   = 0 (okuma)
        //   [23:16] bayt sayisi-1  = 7 (8 bayt)
        //   [30:25] prescaler      = 4
        //   [31]    durum temizle  = 1
        // ---------------------------------------------------------------------
        axi_write(32'h04, 32'h0000_0000);          // QSPI_ADR = 0
        axi_write(32'h00, 32'h8807_0103);          // QSPI_CCR -> motoru atesle

        // Islem bitisini bekle: QSPI_STA bit 0 = done
        waited = 0;
        forever begin
            axi_read(32'h0C, v);
            if (v[0]) break;
            if (waited++ > 20000) break;
            @(posedge clk);
        end
        check("QSPI_STA done biti", {31'b0, v[0]}, 32'h1);

        // ---------------------------------------------------------------------
        // RX FIFO'dan iki kelime oku ve flash icerigiyle karsilastir
        //
        // Flash modeli kelimeleri little-endian bayt dizisine aciyor;
        // QSPI master de baytlari ayni duzende kelimeye topluyor.
        // Dolayisiyla okunan kelimeler dosyadaki kelimelerle ayni olmali.
        // ---------------------------------------------------------------------
        axi_read(32'h08, v);
        check("Flash kelime 0", v, 32'hA5A5_0000);

        axi_read(32'h08, v);
        check("Flash kelime 1", v, 32'hA5A5_0001);

        // ---------------------------------------------------------------------
        // Ozet
        // ---------------------------------------------------------------------
        $display("================================================================");
        if (error_count != 0) begin
            $display(" QSPI TESTI BASARISIZ - %0d hata / %0d denetim",
                     error_count, check_count);
            $display("================================================================");
            $fatal(1, "QSPI dogrulamasi basarisiz");
        end else begin
            $display(" QSPI TESTI GECTI - %0d denetim, 0 hata", check_count);
            $display("================================================================");
        end
        $finish;
    end

    // =========================================================================
    // DUT
    // =========================================================================
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

    // Kendi flash modelimiz (satici modeli depoda yok)
    spi_flash_model #(
        .INIT_FILE  (INIT_FILE),
        .WORD_COUNT (TEST_WORDS)
    ) u_flash (
        .sck   (spi_sck),
        .cs_n  (spi_cs_n),
        .io0   (spi_io0),
        .io1   (spi_io1),
        .io2   (spi_io2),
        .io3   (spi_io3)
    );

endmodule
