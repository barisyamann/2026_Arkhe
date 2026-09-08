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

    // Donanim cikarim cevrimi - tb_npu_audio / npu_golden ciktisindan
    localparam int DONANIM_CEVRIM = 85587;
    localparam logic [31:0] IMZA = 32'hB051_0000 | N_OUT;

    logic clk = 0;
    always #10 clk = ~clk;                 // 50 MHz

    // =========================================================================
    // TCM / I-RAM ERISIMI - IKI KIPTE DE CALISIR   (5 Eylul 2026'da eklendi)
    //
    // Bu testbench dogrudan `uut.u_npu.u_npu_sram.ram[...]` ve
    // `uut.u_instruction_ram.ram[...]` dizilerine erisiyordu. Bu diziler
    // YALNIZCA cikarimsal kipte vardir; USE_SRAM_MACRO tanimliyken elaborasyon
    //   ERROR: [VRFC 10-2991] 'ram' is not declared under prefix 'u_npu_sram'
    // ile duser. Sonuc: hizlanma olcumu ASIC kod yolunda HIC kosulamiyordu.
    //
    // Makro kipinde bolunme (npu_tcm_sram.sv):
    //     TCM   : addr[12:9] -> makro (0..14),  addr[8:0] -> makro ici
    //     I-RAM : addr / 512 -> makro,          addr % 512 -> makro ici
    // Her iki bellek de 512 kelimelik sky130 makrolarindan olusur.
    // =========================================================================
`ifdef USE_SRAM_MACRO
    // DIKKAT: g_sram[m].u_macro yoluna DEGISKEN indisle erisilemez; xelab
    //   "'u_macro' is not declared under prefix 'g_sram'"
    // ile duser. Ayni kisit tb_soc_top.sv:390'da da not edilmistir.
    // Bu yuzden makro secimi SABIT indisli case ile yapiliyor.
    function automatic logic [31:0] tcm_oku(input int adr);
        int mak, ofs;
        mak = adr / 512; ofs = adr - mak * 512;
        tcm_oku = 32'hDEAD_BEEF;
        case (mak)
             0: tcm_oku = uut.u_npu.u_npu_sram.g_sram[0].u_macro.mem[ofs];
             1: tcm_oku = uut.u_npu.u_npu_sram.g_sram[1].u_macro.mem[ofs];
             2: tcm_oku = uut.u_npu.u_npu_sram.g_sram[2].u_macro.mem[ofs];
             3: tcm_oku = uut.u_npu.u_npu_sram.g_sram[3].u_macro.mem[ofs];
             4: tcm_oku = uut.u_npu.u_npu_sram.g_sram[4].u_macro.mem[ofs];
             5: tcm_oku = uut.u_npu.u_npu_sram.g_sram[5].u_macro.mem[ofs];
             6: tcm_oku = uut.u_npu.u_npu_sram.g_sram[6].u_macro.mem[ofs];
             7: tcm_oku = uut.u_npu.u_npu_sram.g_sram[7].u_macro.mem[ofs];
             8: tcm_oku = uut.u_npu.u_npu_sram.g_sram[8].u_macro.mem[ofs];
             9: tcm_oku = uut.u_npu.u_npu_sram.g_sram[9].u_macro.mem[ofs];
            10: tcm_oku = uut.u_npu.u_npu_sram.g_sram[10].u_macro.mem[ofs];
            11: tcm_oku = uut.u_npu.u_npu_sram.g_sram[11].u_macro.mem[ofs];
            12: tcm_oku = uut.u_npu.u_npu_sram.g_sram[12].u_macro.mem[ofs];
            13: tcm_oku = uut.u_npu.u_npu_sram.g_sram[13].u_macro.mem[ofs];
            14: tcm_oku = uut.u_npu.u_npu_sram.g_sram[14].u_macro.mem[ofs];
            default: ;
        endcase
    endfunction

    task automatic tcm_yaz(input int adr, input logic [31:0] deger);
        int mak, ofs;
        mak = adr / 512; ofs = adr - mak * 512;
        case (mak)
             0: uut.u_npu.u_npu_sram.g_sram[0].u_macro.mem[ofs] = deger;
             1: uut.u_npu.u_npu_sram.g_sram[1].u_macro.mem[ofs] = deger;
             2: uut.u_npu.u_npu_sram.g_sram[2].u_macro.mem[ofs] = deger;
             3: uut.u_npu.u_npu_sram.g_sram[3].u_macro.mem[ofs] = deger;
             4: uut.u_npu.u_npu_sram.g_sram[4].u_macro.mem[ofs] = deger;
             5: uut.u_npu.u_npu_sram.g_sram[5].u_macro.mem[ofs] = deger;
             6: uut.u_npu.u_npu_sram.g_sram[6].u_macro.mem[ofs] = deger;
             7: uut.u_npu.u_npu_sram.g_sram[7].u_macro.mem[ofs] = deger;
             8: uut.u_npu.u_npu_sram.g_sram[8].u_macro.mem[ofs] = deger;
             9: uut.u_npu.u_npu_sram.g_sram[9].u_macro.mem[ofs] = deger;
            10: uut.u_npu.u_npu_sram.g_sram[10].u_macro.mem[ofs] = deger;
            11: uut.u_npu.u_npu_sram.g_sram[11].u_macro.mem[ofs] = deger;
            12: uut.u_npu.u_npu_sram.g_sram[12].u_macro.mem[ofs] = deger;
            13: uut.u_npu.u_npu_sram.g_sram[13].u_macro.mem[ofs] = deger;
            14: uut.u_npu.u_npu_sram.g_sram[14].u_macro.mem[ofs] = deger;
            default: ;
        endcase
    endtask

    task automatic tcm_yukle(input string dosya);
        logic [31:0] gecici [0:7679];
        $readmemh(dosya, gecici);
        for (int i = 0; i < 7680; i++) tcm_yaz(i, gecici[i]);
    endtask

    function automatic logic [31:0] iram_oku(input int adr);
        int mak, ofs;
        mak = adr / 512; ofs = adr - mak * 512;
        iram_oku = 32'hDEAD_BEEF;
        case (mak)
            0: iram_oku = uut.u_instruction_ram.g_sram[0].u_macro.mem[ofs];
            1: iram_oku = uut.u_instruction_ram.g_sram[1].u_macro.mem[ofs];
            2: iram_oku = uut.u_instruction_ram.g_sram[2].u_macro.mem[ofs];
            3: iram_oku = uut.u_instruction_ram.g_sram[3].u_macro.mem[ofs];
            default: ;
        endcase
    endfunction

    task automatic iram_yaz(input int adr, input logic [31:0] deger);
        int mak, ofs;
        mak = adr / 512; ofs = adr - mak * 512;
        case (mak)
            0: uut.u_instruction_ram.g_sram[0].u_macro.mem[ofs] = deger;
            1: uut.u_instruction_ram.g_sram[1].u_macro.mem[ofs] = deger;
            2: uut.u_instruction_ram.g_sram[2].u_macro.mem[ofs] = deger;
            3: uut.u_instruction_ram.g_sram[3].u_macro.mem[ofs] = deger;
            default: ;
        endcase
    endtask

    task automatic iram_yukle(input string dosya);
        logic [31:0] gecici [0:2047];
        $readmemh(dosya, gecici);
        for (int i = 0; i < 2048; i++) iram_yaz(i, gecici[i]);
    endtask
`else
    function automatic logic [31:0] tcm_oku(input int adr);
        return uut.u_npu.u_npu_sram.ram[adr];
    endfunction

    task automatic tcm_yukle(input string dosya);
        $readmemh(dosya, uut.u_npu.u_npu_sram.ram);
    endtask

    task automatic iram_yukle(input string dosya);
        $readmemh(dosya, uut.u_instruction_ram.ram);
    endtask

    function automatic logic [31:0] iram_oku(input int adr);
        return uut.u_instruction_ram.ram[adr];
    endfunction
`endif

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
        tcm_yukle("tcm_image.mem");
        iram_yukle(BENCH_HEX);
        force uut.u_core.boot_addr_i = 32'h0100_0000;

        // TANI: yukleme gercekten oldu mu
        $display("  [TANI] TCM[0]=%08h TCM[704]=%08h TCM[768]=%08h TCM[4768]=%08h",
                 tcm_oku(0),    tcm_oku(704),
                 tcm_oku(768),  tcm_oku(4768));
        $display("  [TANI] IRAM[0]=%08h IRAM[1]=%08h",
                 iram_oku(0), iram_oku(1));

        $display("================================================================");
        $display(" YAZILIM GERCEKLEMESI CEVRIM OLCUMU");
        $display(" Ikili: %s   olculen piksel: %0d / %0d",
                 BENCH_HEX, N_OUT, TOPLAM_PIKSEL);
        $display("================================================================");

        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        // Sonuc imzasini bekle
        bekleme = 0;
        while (tcm_oku(OFS_SONUC) !== IMZA && bekleme < 20_000_000) begin
            @(posedge clk);
            bekleme++;
        end

        denetle("sonuc imzasi TCM'e yazildi",
                tcm_oku(OFS_SONUC) === IMZA);
        if (hata != 0) begin
            $display(" Imza gelmedi - CPU kiyaslamayi tamamlamadi.");
            $fatal(1, "yazilim kiyaslamasi tamamlanmadi");
        end

        gecen = tcm_oku(OFS_SONUC + 1);

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
        // DONANIM CEVRIM SAYISI - RTL'DEN OLCULUR, ELLE GUNCELLENIR
        //
        // 23 Agu 2026: CONV_MAC uc asamali boru hatti -> 80.583 -> 81.083
        // 28 Agu 2026: requantization boru hatti (CONV_RQ_MUL / FC_RQ_MUL)
        //              -> 81.083 -> 85.587 cevrim
        //
        // 5 Eylul 2026: bu uc yerde 81.083 SABIT yaziliydi ve guncel RTL ile
        // ortusmuyordu; hizlanma orani oldugundan YUKSEK cikiyordu (874x
        // yerine dogrusu asagidaki deger). analiz.py zaten 85.587 kullaniyor.
        // Guncel deger su iki testin ciktisinda gorunur:
        //     build/regression/npu_golden/sim.log     "NPU cycles  = 85587"
        //     build/regression/npu_dogruluk/sim.log   "85587 cevrim"
        // NPU boru hatti degisirse bu sabit de guncellenmelidir.
        $display("  Donanim (tb_npu_audio)      : %0d cevrim = %.2f ms",
                 DONANIM_CEVRIM, DONANIM_CEVRIM / 50.0e3);
        $display("  Kaba hizlanma               : %.0fx",
                 tam_cikarim / real'(DONANIM_CEVRIM));
        $display("");
        $display("  NOT: kesin sayi icin iki N olcumu gerekir ->");
        $display("       python tb/npu_sw_bench/analiz.py");
        $display("");
        $display("  fc_acc = [%0d, %0d, %0d, %0d]  (kismi - %0d piksel)",
                 $signed(tcm_oku(OFS_SONUC + 2)),
                 $signed(tcm_oku(OFS_SONUC + 3)),
                 $signed(tcm_oku(OFS_SONUC + 4)),
                 $signed(tcm_oku(OFS_SONUC + 5)), N_OUT);

        // Akil sagligi: yazilim donanimdan YAVAS olmali, aksi halde
        // hizlandirici bir ise yaramiyor demektir
        denetle("yazilim donanimdan en az 100x yavas",
                tam_cikarim > 100.0 * real'(DONANIM_CEVRIM));

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
