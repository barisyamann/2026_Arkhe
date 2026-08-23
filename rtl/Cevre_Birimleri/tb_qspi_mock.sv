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

    // -------------------------------------------------------------------------
    // IKI FLASH MODELI - 3 bayt ve 4 bayt adres bekleyen
    //
    // Adres genisligi flash tarafinda derleme zamani parametresidir; tek
    // ornekle iki modu da deneyemeyiz. Bu yuzden iki model ayni veri yoluna
    // baglanir ve secim CS ile yapilir. Secilmeyen model cs_n=1 oldugu icin
    // io1'i yuksek empedansta birakir, yani hat cakismasi olmaz.
    // -------------------------------------------------------------------------
    logic sel_4byte = 1'b0;
    wire  cs_n_3b = sel_4byte ? 1'b1 : spi_cs_n;
    wire  cs_n_4b = sel_4byte ? spi_cs_n : 1'b1;

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

    // QSPI_STA bit 0 (done) yukselene kadar bekler
    task automatic bekle_bitti();
        logic [31:0] st;
        int          n;
        n = 0;
        forever begin
            axi_read(32'h0C, st);
            if (st[0]) break;
            if (n++ > 20000) begin
                $display("      [HATA] islem bitmedi - zaman asimi");
                error_count++;
                break;
            end
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // SCK PERIYODU OLCUMU  (23 Agustos 2026)
    //
    // Sartname s.1127-1132 prescaler'i su sekilde tanimlar:
    //
    //   "Bu alana yazan degerin BIR FAZLASI kadar saat frekansi bolunerek...
    //    '0' yazilirsa SCLK sistem saat hizinda olacaktir. '1' oldugu zaman
    //    SCLK sistem saat hizinin YARISINDA olacaktir."
    //
    // Yani beklenen:  SCLK = clk / (P+1)
    //   P=0 -> 50 MHz (20 ns periyot)
    //   P=1 -> 25 MHz (40 ns)
    //   P=4 -> 10 MHz (100 ns)
    //
    // Bu gorev GERCEK periyodu olcer. Boylece prescaler semantigi beyan
    // degil, olculmus bir deger olur.
    // =========================================================================
    task automatic sck_periyodu_olc(input logic [5:0] presc, output int periyot_ns);
        time t1, t2;
        int  n;
        // Prescaler'i CCR'ye yaz ve bir okuma islemi baslat
        axi_write(32'h04, 32'h0);                                  // ADR = 0
        axi_write(32'h00, {1'b1, presc, 1'b0, 8'h03, 5'b0, 2'b00, 1'b0, 8'h03});
        // Ilk yukselen kenari bekle, sonra iki kenar arasi sureyi olc
        n = 0;
        while (spi_sck !== 1'b1 && n < 5000) begin @(posedge clk); n++; end
        while (spi_sck !== 1'b0 && n < 5000) begin @(posedge clk); n++; end
        while (spi_sck !== 1'b1 && n < 5000) begin @(posedge clk); n++; end
        t1 = $time;
        while (spi_sck !== 1'b0 && n < 5000) begin @(posedge clk); n++; end
        while (spi_sck !== 1'b1 && n < 5000) begin @(posedge clk); n++; end
        t2 = $time;
        periyot_ns = int'(t2 - t1);
        bekle_bitti();
    endtask

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
        // 4-BAYT ADRESLEME MODU (CCR[24] = 1)
        //
        // Sartname s.24: "Tum flash alanini kapsamak icin 4-bayt adresleme
        // modu destegi bulunacaktir."
        //
        // Bu test AYIRT EDICIDIR: 4-bayt bekleyen flash'a yalnizca 3 bayt
        // adres gonderilirse model hala adres fazindadir ve ilk veri baytini
        // adresin son bayti sanip yutar. Okunan kelime kayar, denetim duser.
        //
        // Bayt adresi 8 -> kelime 2 -> 0xA5A50002 beklenir.
        // ---------------------------------------------------------------------
        sel_4byte = 1'b1;
        repeat (5) @(posedge clk);

        axi_write(32'h10, 32'h0000_0003);          // QSPI_FCR: iki FIFO'yu bosalt
        axi_write(32'h04, 32'h0000_0008);          // QSPI_ADR = 8
        axi_write(32'h00, 32'h8907_0103);          // CCR: ayni + bit24 (4 bayt)

        waited = 0;
        forever begin
            axi_read(32'h0C, v);
            if (v[0]) break;
            if (waited++ > 20000) break;
            @(posedge clk);
        end
        check("4-bayt: QSPI_STA done biti", {31'b0, v[0]}, 32'h1);

        axi_read(32'h08, v);
        check("4-bayt: flash kelime 2", v, 32'hA5A5_0002);

        axi_read(32'h08, v);
        check("4-bayt: flash kelime 3", v, 32'hA5A5_0003);

        // ---------------------------------------------------------------------
        // KOMUT KAPSAMI  (Sartname s.24)
        //
        // Onceki surum YALNIZCA READ (0x03) yolunu kosuyordu. Sartname su
        // komutlari zorunlu tutuyor ve hepsi RTL'de gerceklenmisti ama
        // dogrulanmamisti - kapsama olcumunde qspi_master %58,4 statement
        // ile en dusuk modulumuzdu.
        //
        // CCR alan kodlamasi:
        //   [7:0] komut  [9:8] veri modu (00 yok / 01 x1 / 10 x2 / 11 x4)
        //   [10] yaz(1)/oku(0)  [15:11] dummy  [23:16] bayt-1
        //   [24] 4-bayt adres   [30:25] prescaler  [31] durum temizle
        // ---------------------------------------------------------------------
        sel_4byte = 1'b0;                        // 3-bayt modeline geri don
        repeat (5) @(posedge clk);

        // --- RDID (0x9F): uretici/cihaz kimligi, 3 bayt tek hatli --------
        axi_write(32'h10, 32'h0000_0003);        // FIFO'lari bosalt
        axi_write(32'h00, 32'h8802_019F);
        bekle_bitti();
        axi_read(32'h08, v);
        // Model JEDEC_ID = 24'h01_02_19; baytlar dusuk-anlamliya dogru toplanir
        check("RDID = 01 02 19", v[23:0], 24'h1902_01);

        // --- WREN (0x06) -> RDSR1 (0x05): WEL biti 1 olmali --------------
        axi_write(32'h00, 32'h8800_0006);        // WREN, veri fazi yok
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h00, 32'h8800_0105);        // RDSR1, 1 bayt
        bekle_bitti();
        axi_read(32'h08, v);
        check("WREN sonrasi RDSR1.WEL", {31'b0, v[1]}, 32'h1);

        // --- WRDI (0x04) -> RDSR1: WEL biti 0 olmali ---------------------
        axi_write(32'h00, 32'h8800_0004);        // WRDI
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h00, 32'h8800_0105);
        bekle_bitti();
        axi_read(32'h08, v);
        check("WRDI sonrasi RDSR1.WEL", {31'b0, v[1]}, 32'h0);

        // --- QOR (0x6B): DORTLU hatli okuma, 8 dummy cevrim --------------
        //
        // DTR "Quad modunun donanimsal olarak desteklenmesi, boot suresini
        // teorik olarak %75 oraninda kisaltir" diyor - ama x4 yolu hic
        // test edilmemisti. Ayni veriyi x1 ile ayni sonucu vermeli.
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);        // adres 0
        axi_write(32'h00, 32'h8807_436B);        // QOR, x4, 8 dummy, 8 bayt
        bekle_bitti();
        axi_read(32'h08, v);
        check("QOR (x4) kelime 0", v, 32'hA5A5_0000);
        axi_read(32'h08, v);
        check("QOR (x4) kelime 1", v, 32'hA5A5_0001);

        // --- SE (0xD8): sektor sil -> her sey 0xFF ------------------------
        //
        // NOT: bundan SONRA flash icerigi bozulur, okuma testleri yukarida
        // bitmis olmali.
        axi_write(32'h00, 32'h8800_0006);        // WREN
        bekle_bitti();
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8800_00D8);        // SE
        bekle_bitti();

        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8803_0103);        // READ, 4 bayt
        bekle_bitti();
        axi_read(32'h08, v);
        check("SE sonrasi silinmis kelime", v, 32'hFFFF_FFFF);
        check("model SE sayaci", u_flash_3b.se_sayisi, 32'd1);

        // --- PP (0x02): sayfa programla -> geri oku -----------------------
        //
        // NOR flash yalnizca 1 -> 0 yapabilir; silme sonrasi 0xFF oldugu
        // icin istenen deger dogrudan yazilabilir.
        axi_write(32'h00, 32'h8800_0006);        // WREN
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h08, 32'h1234_5678);        // TX FIFO'ya veri
        axi_write(32'h00, 32'h8803_0502);        // PP, x1 yazma, 4 bayt
        bekle_bitti();
        check("model PP bayt sayaci", u_flash_3b.pp_bayt, 32'd4);

        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0000);
        axi_write(32'h00, 32'h8803_0103);        // READ, 4 bayt
        bekle_bitti();
        axi_read(32'h08, v);
        check("PP sonrasi geri okuma", v, 32'h1234_5678);

        // --- WEL olmadan PP yazmamali ------------------------------------
        //
        // WREN verilmeden yazma denenirse flash yok saymalidir. Bu, gercek
        // NOR flash davranisidir ve yazilim hatasini yakalar.
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0010);        // farkli adres (bayt 16)
        axi_write(32'h08, 32'h0000_0000);
        axi_write(32'h00, 32'h8803_0502);        // WREN YOK
        bekle_bitti();
        axi_write(32'h10, 32'h0000_0003);
        axi_write(32'h04, 32'h0000_0010);
        axi_write(32'h00, 32'h8803_0103);
        bekle_bitti();
        axi_read(32'h08, v);
        check("WEL yokken PP yazmadi", v, 32'hFFFF_FFFF);

        // ---------------------------------------------------------------------
        // PRESCALER - SCK PERIYODU OLCUMU
        //
        // Sartname: SCLK = clk / (P+1).  Sistem saati 50 MHz (20 ns).
        //   P=1 -> 40 ns    P=2 -> 60 ns    P=4 -> 100 ns
        //
        // Bu denetimler GERCEK olculen periyodu bekleneni karsilastirir.
        // Sapma varsa RTL'in prescaler semantigi sartnameden farklidir ve
        // bu ACIKCA gorunur - yorum satirinda gizli kalmaz.
        // ---------------------------------------------------------------------
        $display("  -- Prescaler SCK periyodu (sartname: clk/(P+1))");
        begin
            int olculen;

            sck_periyodu_olc(6'd1, olculen);
            $display("      prescaler=1  olculen=%0d ns  beklenen=40 ns", olculen);
            check("prescaler 1 -> 40 ns", olculen, 32'd40);

            sck_periyodu_olc(6'd2, olculen);
            $display("      prescaler=2  olculen=%0d ns  beklenen=60 ns", olculen);
            check("prescaler 2 -> 60 ns", olculen, 32'd60);

            sck_periyodu_olc(6'd4, olculen);
            $display("      prescaler=4  olculen=%0d ns  beklenen=100 ns", olculen);
            check("prescaler 4 -> 100 ns", olculen, 32'd100);
        end

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

    // 4-bayt adres bekleyen ikinci model
    spi_flash_model #(
        .INIT_FILE  (INIT_FILE),
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
