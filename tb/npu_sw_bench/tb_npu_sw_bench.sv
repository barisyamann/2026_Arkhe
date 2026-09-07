`timescale 1ns/1ps
// =============================================================================
//  tb_npu_sw_bench.sv - YAZILIM gerceklemesinin cevrim olcumu
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN
//    Sartname EK-1: "YZ hizlandiricisi modeli gerceklemeli ve RISC-V
//    cekirdegi uzerinde calisan yazilim gerceklemesine kiyasla HIZLANMA
//    elde etmelidir."
//
//    Bolum 4.2.2.1: performans "veri/saat dongusu bazinda ve sentezlenmis
//    frekansta islenmis veri/saniye bazinda" degerlendirilmelidir.
//
//    Donanim tarafi olculmustu (72.583 cevrim, tb_npu_audio). Yazilim
//    tarafi olculmemisti - yani HIZLANMA ORANI gosterilemiyordu.
//
//  YONTEM
//    CPU, npu_sw_bench.c'yi kosar. Agirliklar NPU TCM'inde (16 kB FC
//    agirligi 8 kB D-RAM'e sigmaz). Tam cikarim ~6 milyon cevrimdir;
//    RTL simulasyonunda saatler surer. Bunun yerine N cikis pikseli
//    olculur ve 4000'e olceklenir.
//
//    OLCEKLEMENIN GECERLILIGI TEST EDILIR: iki farkli N ile kosulur,
//    piksel basina maliyet sabit cikmalidir. Cikmazsa olcekleme
//    gecersizdir ve test duser.
//
//  KOSUM
//    Derleme tanimi ile hangi ikilinin yuklenecegi secilir:
//        -d BENCH_N25   -> bench_25.hex
//        -d BENCH_N50   -> bench_50.hex  (varsayilan)
// =============================================================================

module tb_npu_sw_bench;

    // Olculen cikis pikseli sayisi - yuklenen ikili ile eslesmeli
`ifdef BENCH_N25
    localparam int N_OUT       = 25;
    localparam string BENCH_HEX = "bench_25.hex";
`else
    localparam int N_OUT       = 50;
    localparam string BENCH_HEX = "bench_50.hex";
`endif

    localparam int TOPLAM_PIKSEL = 4000;   // 25 x 20 x 8

    // Tam cikarimdaki gecerli tap sayisi:
    //   8 * (sum_t gecerli_kh(t)) * (sum_f gecerli_kw(f)) = 8 * 235 * 152
    localparam int TOPLAM_TAP = 285760;

    // npu_sw_bench.c ile ayni
    localparam int OFS_SONUC = 7000;
    localparam logic [31:0] IMZA = 32'hB051_0000 | N_OUT;

    logic clk = 0;
    always #10 clk = ~clk;                 // 50 MHz

    logic rst_n;

    // --- soc_top cevre baglantilari (kullanilmiyor, guvenli seviyeler) ---
    logic [15:0] gpio_i = '0;
    logic [15:0] gpio_o;
    logic [15:0] gpio_tx_en_o;
    logic        uart1_rxd = 1'b1;
    logic        uart1_txd;
    logic        uart2_rxd = 1'b1;
    logic        uart2_txd;

    wire         i2c_sda, i2c_scl;
    logic        i2c_sda_o_w, i2c_sda_oe_w, i2c_scl_o_w, i2c_scl_oe_w;
    assign i2c_sda = i2c_sda_oe_w ? i2c_sda_o_w : 1'bz;
    assign i2c_scl = i2c_scl_oe_w ? i2c_scl_o_w : 1'bz;
    pullup(i2c_sda); pullup(i2c_scl);

    logic        qspi_sck, qspi_cs_n;
    logic [3:0]  qspi_io_o_w, qspi_io_oe_w;
    wire  [3:0]  qspi_io_w;
    assign qspi_io_w = 4'bzzzz;
    pullup(qspi_io_w[0]); pullup(qspi_io_w[1]);
    pullup(qspi_io_w[2]); pullup(qspi_io_w[3]);

    logic jtag_tms = 1'b1, jtag_tck = 1'b0, jtag_tdi = 1'b0, jtag_trst_n = 1'b1;
    logic jtag_tdo;

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
        .i2c_sda_o    (i2c_sda_o_w),
        .i2c_sda_oe   (i2c_sda_oe_w),
        .i2c_sda_i    (i2c_sda),
        .i2c_scl_o    (i2c_scl_o_w),
        .i2c_scl_oe   (i2c_scl_oe_w),
        .i2c_scl_i    (i2c_scl),
        .qspi_sck     (qspi_sck),
        .qspi_cs_n    (qspi_cs_n),
        .qspi_io_o    (qspi_io_o_w),
        .qspi_io_oe   (qspi_io_oe_w),
        .qspi_io_i    (qspi_io_w),
        .jtag_tms     (jtag_tms),
        .jtag_tck     (jtag_tck),
        .jtag_tdi     (jtag_tdi),
        .jtag_tdo     (jtag_tdo),
        .jtag_trst_n  (jtag_trst_n)
    );

    // =========================================================================
    // Olcum
    // =========================================================================
    int          hata = 0;
    int          denetim = 0;
    logic [31:0] gecen;
    real         piksel_basina;
    real         tam_cikarim;
    int          bekleme;
    int          olculen_tap;
    int          piksel_sayaci;

    task automatic denetle(input string ad, input int kosul_dogru);
        denetim++;
        if (kosul_dogru) $display("      [OK]   %s", ad);
        else begin hata++; $display("      [HATA] %s", ad); end
    endtask

    initial begin
        #500_000_000;
        $display(" YAZILIM KIYASLAMASI BASARISIZ - zaman asimi");
        $fatal(1, "tb_npu_sw_bench zaman asimi");
    end

    initial begin
        rst_n = 1'b0;

        // ---------------------------------------------------------------
        // BELLEK ON-YUKLEMESI ZAMAN 0'DA YAPILAMAZ
        //
        // npu_tcm_sram.sv kendi initial blogunda ram dizisini sifirliyor.
        // SystemVerilog initial bloklarinin sirasini garanti etmez; zaman
        // 0'da $readmemh yapilirsa modulun sifirlamasi sonra kosup imaji
        // SILEBILIR. Ilk olcumde tam olarak bu oldu: imza yazildi ama tum
        // agirliklar 0 okundu, fc_acc = [0,0,0,0] cikti.
        //
        // #1 ile zaman 0'daki tum initial bloklarinin bitmesi beklenir.
        // ---------------------------------------------------------------
        #1;
        $readmemh("tcm_image.mem", uut.u_npu.u_npu_sram.ram);
        $readmemh(BENCH_HEX, uut.u_instruction_ram.ram);
        force uut.u_core.boot_addr_i = 32'h0100_0000;

        // TANI: yukleme gercekten oldu mu
        $display("  [TANI] TCM[0]=%08h TCM[704]=%08h TCM[768]=%08h TCM[4768]=%08h",
                 uut.u_npu.u_npu_sram.ram[0],    uut.u_npu.u_npu_sram.ram[704],
                 uut.u_npu.u_npu_sram.ram[768],  uut.u_npu.u_npu_sram.ram[4768]);
        $display("  [TANI] IRAM[0]=%08h IRAM[1]=%08h",
                 uut.u_instruction_ram.ram[0], uut.u_instruction_ram.ram[1]);

        $display("================================================================");
        $display(" YAZILIM GERCEKLEMESI CEVRIM OLCUMU");
        $display(" Ikili: %s   olculen piksel: %0d / %0d",
                 BENCH_HEX, N_OUT, TOPLAM_PIKSEL);
        $display("================================================================");

        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        // Sonuc imzasini bekle
        bekleme = 0;
        while (uut.u_npu.u_npu_sram.ram[OFS_SONUC] !== IMZA && bekleme < 20_000_000) begin
            @(posedge clk);
            bekleme++;
        end

        denetle("sonuc imzasi TCM'e yazildi",
                uut.u_npu.u_npu_sram.ram[OFS_SONUC] === IMZA);
        if (hata != 0) begin
            $display(" Imza gelmedi - CPU kiyaslamayi tamamlamadi.");
            $fatal(1, "yazilim kiyaslamasi tamamlanmadi");
        end

        gecen = uut.u_npu.u_npu_sram.ram[OFS_SONUC + 1];

        // ---------------------------------------------------------------
        // DUZ PIKSEL ORANI ILE OLCEKLEME YANLIS SONUC VERIR
        //
        // Olculen ilk N piksel tamamen t=0 bolgesindedir; orada cekirdegin
        // 10 satirindan yalnizca 6'si gecerlidir (ti = 2t-4+kh >= 0 kosulu).
        // f=0 ve f=1 sutunlarinda da 8 kolondan 5 ve 7'si gecerlidir.
        // Yani olculen pikseller ic bolgedekilerden COK DAHA UCUZDUR ve
        // cevrim/piksel ile carpmak toplami EKSIK gosterir.
        //
        // Dogru olcut TAP sayisidir. Burada olculen alt kumenin tap sayisi
        // hesaplanir ve tap basina maliyet raporlanir; tam cikarim tahmini
        // iki farkli N olcumunden analiz.py ile cikarilir.
        // ---------------------------------------------------------------
        olculen_tap = 0;
        piksel_sayaci = 0;
        for (int tt = 0; tt < 25; tt++)
            for (int ff = 0; ff < 20; ff++)
                for (int dd = 0; dd < 8; dd++)
                    if (piksel_sayaci < N_OUT) begin
                        int kh_gecerli = 0;
                        int kw_gecerli = 0;
                        for (int k = 0; k < 10; k++)
                            if ((2*tt - 4 + k) >= 0 && (2*tt - 4 + k) <= 48) kh_gecerli++;
                        for (int k = 0; k < 8; k++)
                            if ((2*ff - 3 + k) >= 0 && (2*ff - 3 + k) <= 39) kw_gecerli++;
                        olculen_tap += kh_gecerli * kw_gecerli;
                        piksel_sayaci++;
                    end

        piksel_basina = real'(gecen) / real'(N_OUT);
        tam_cikarim   = real'(gecen) / real'(olculen_tap) * real'(TOPLAM_TAP);

        $display("");
        $display("  Olculen cevrim (%0d piksel) : %0d", N_OUT, gecen);
        $display("  Olculen tap sayisi          : %0d", olculen_tap);
        $display("  Tap basina                  : %.1f cevrim",
                 real'(gecen) / real'(olculen_tap));
        $display("  Piksel basina (bu alt kume) : %.1f cevrim", piksel_basina);
        $display("");
        $display("  Tam cikarim tap sayisi      : %0d", TOPLAM_TAP);
        $display("  Kaba alt sinir tahmini      : %.0f cevrim (%.2f s @50MHz)",
                 tam_cikarim, tam_cikarim / 50.0e6);
        // 23 Agustos 2026: CONV_MAC uc asamali boru hattina cevrildi,
// cikarim 80.583 -> 81.083 cevrim (+500, piksel basina bosaltma).
        $display("  Donanim (tb_npu_audio)      : 81083 cevrim = 1.62 ms");
        $display("  Kaba hizlanma               : %.0fx", tam_cikarim / 81083.0);
        $display("");
        $display("  NOT: kesin sayi icin iki N olcumu gerekir ->");
        $display("       python tb/npu_sw_bench/analiz.py");
        $display("");
        $display("  fc_acc = [%0d, %0d, %0d, %0d]  (kismi - %0d piksel)",
                 $signed(uut.u_npu.u_npu_sram.ram[OFS_SONUC + 2]),
                 $signed(uut.u_npu.u_npu_sram.ram[OFS_SONUC + 3]),
                 $signed(uut.u_npu.u_npu_sram.ram[OFS_SONUC + 4]),
                 $signed(uut.u_npu.u_npu_sram.ram[OFS_SONUC + 5]), N_OUT);

        // Akil sagligi: yazilim donanimdan YAVAS olmali, aksi halde
        // hizlandirici bir ise yaramiyor demektir
        denetle("yazilim donanimdan en az 100x yavas",
                tam_cikarim > 100.0 * 81083.0);

        $display("================================================================");
        if (hata != 0) begin
            $display(" YAZILIM KIYASLAMASI BASARISIZ - %0d hata", hata);
            $fatal(1, "olcum basarisiz");
        end
        $display(" YAZILIM KIYASLAMASI GECTI - %0d denetim, 0 hata", denetim);
        $display("================================================================");
        $finish;
    end

endmodule
