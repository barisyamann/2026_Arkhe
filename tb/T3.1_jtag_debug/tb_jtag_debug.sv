`timescale 1ns / 1ps
// =============================================================================
//  tb_jtag_debug.sv - JTAG/Debug blok seviyesi self-checking testbench
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN YENIDEN YAZILDI (18 Agustos 2026):
//
//  Eski surum "jtag_debug_wrapper" modulunu ornekliyordu; bu modul depoda
//  YOK. Yani testbench hic derlenemiyordu. Sartname "butun testbench
//  kodlari"ni teslim isteri olarak sayiyor - derlenmeyen testbench teslim
//  etmek, hic teslim etmemekten kotudur.
//
//  Ayrica hicbir sey dogrulamiyordu: TAP uzerinden birkac bit kaydirip
//  KOSULSUZ olarak "Basarili: Simulasyon hatasiz tamamlandi" yazdiriyordu.
//  Denetimin B8 bulgusunun ("hata durumunda da BASARILI yaziyor") en net
//  ornegiydi.
//
//  KAPSAM SECIMI:
//  Sistem testbench'i (tb_soc_top) JTAG TAP yolunu zaten uctan uca
//  dogruluyor: IDCODE, CPU halt, bellek okuma/yazma, resume. Burada onu
//  tekrarlamak yerine, sistem testinin GOREMEDIGI seyler dogrulaniyor:
//
//    - CSR (AXI) arayuzu uzerinden yazmac erisimi
//    - Veri yolu hata yakalama yazmaclari (18 Agustos'ta eklendi)
//    - BUYRUK koprusu hata yolu - sistem testinde yalnizca VERI koprusu
//      tetikleniyor, buyruk koprusu hic sinanmiyor
//    - "Ilk hata saklanir" tasarim karari
// =============================================================================

module tb_jtag_debug;

    // Yazmac ofsetleri (jtag_debug.sv ile ayni)
    localparam logic [4:0] REG_DBG_CTRL   = 5'h00;
    localparam logic [4:0] REG_DBG_ADDR   = 5'h08;
    localparam logic [4:0] REG_DBG_DATA   = 5'h0C;
    localparam logic [4:0] REG_FAULT_ST   = 5'h14;
    localparam logic [4:0] REG_FAULT_ADDR = 5'h18;
    localparam logic [4:0] REG_FAULT_CLR  = 5'h1C;

    logic clk = 0;
    logic rst_n = 0;

    always #10 clk = ~clk;   // 50 MHz

    // JTAG pinleri - bu testte kullanilmiyor, guvenli durumda tutuluyor
    logic jtag_tms = 1'b1, jtag_tck = 1'b0, jtag_tdi = 1'b0, jtag_trst_n = 1'b1;
    logic jtag_tdo;
    logic debug_req;

    // Veri yolu hata girisleri
    logic        instr_bus_err = 1'b0;
    logic [31:0] instr_bus_err_addr = 32'h0;
    logic        data_bus_err = 1'b0;
    logic [31:0] data_bus_err_addr = 32'h0;
    logic        bus_fault_irq;

    // AXI4-Lite CSR
    logic [31:0] awaddr, wdata, araddr, rdata;
    logic        awvalid, wvalid, bready, arvalid, rready;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;

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

    // Gozcu - asili kalan test de basarisizdir
    initial begin
        #1_000_000;   // 1 ms
        $display("      [HATA] ZAMAN ASIMI - test 1 ms icinde bitmedi");
        $fatal(1, "JTAG blok testi zaman asimi");
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
        @(posedge clk);
    endtask

    task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        araddr <= addr; arvalid <= 1'b1; rready <= 1'b1;
        forever begin @(posedge clk); if (arready) break; end
        arvalid <= 1'b0;
        forever begin @(posedge clk); if (rvalid) break; end
        data = rdata;
        rready <= 1'b0;
        @(posedge clk);
    endtask

    // Bir cevrimlik hata darbesi uretir (kopruler boyle davranir)
    // =========================================================================
    // JTAG TAP SERI PROTOKOL SURUCUSU  (22 Agustos 2026'da eklendi)
    //
    // Bu blok testi TAP pinlerini bagliyordu ama HIC SURMUYORDU: 16 durumlu
    // TAP durum makinesi yalnizca sistem testinde calisiyordu, blok
    // kapsamasinda gorunmuyordu (%54,9 statement).
    // =========================================================================
    task automatic jtag_clock();
        jtag_tck = 1'b0; #100;
        jtag_tck = 1'b1; #100;
        jtag_tck = 1'b0;
    endtask

    task automatic jtag_reset();
        jtag_trst_n = 1'b0; #100;
        jtag_trst_n = 1'b1;
        jtag_tms = 1'b1;
        repeat (5) jtag_clock();      // TEST_LOGIC_RESET garanti
        jtag_tms = 1'b0;
        jtag_clock();                 // -> RUN_TEST_IDLE
    endtask

    task automatic jtag_shift_ir(input logic [3:0] ir_in);
        jtag_tms = 1'b1; jtag_clock();   // -> SELECT_DR_SCAN
        jtag_tms = 1'b1; jtag_clock();   // -> SELECT_IR_SCAN
        jtag_tms = 1'b0; jtag_clock();   // -> CAPTURE_IR
        jtag_tms = 1'b0; jtag_clock();   // -> SHIFT_IR
        for (int i = 0; i < 4; i++) begin
            jtag_tdi = ir_in[i];
            jtag_tms = (i == 3) ? 1'b1 : 1'b0;
            jtag_clock();
        end
        jtag_tms = 1'b1; jtag_clock();   // -> UPDATE_IR
        jtag_tms = 1'b0; jtag_clock();   // -> RUN_TEST_IDLE
    endtask

    task automatic jtag_shift_dr(input  logic [63:0] dr_in,
                                 input  int          len,
                                 output logic [63:0] dr_out);
        jtag_tms = 1'b1; jtag_clock();   // -> SELECT_DR_SCAN
        jtag_tms = 1'b0; jtag_clock();   // -> CAPTURE_DR
        jtag_tms = 1'b0; jtag_clock();   // -> SHIFT_DR
        for (int i = 0; i < len; i++) begin
            jtag_tdi = dr_in[i];
            jtag_tms = (i == len - 1) ? 1'b1 : 1'b0;
            jtag_clock();
            dr_out[i] = jtag_tdo;
        end
        jtag_tms = 1'b1; jtag_clock();   // -> UPDATE_DR
        jtag_tms = 1'b0; jtag_clock();   // -> RUN_TEST_IDLE
    endtask

    task automatic hata_darbesi(input bit buyruk, input logic [31:0] adres);
        @(posedge clk);
        if (buyruk) begin
            instr_bus_err      <= 1'b1;
            instr_bus_err_addr <= adres;
        end else begin
            data_bus_err      <= 1'b1;
            data_bus_err_addr <= adres;
        end
        @(posedge clk);
        instr_bus_err <= 1'b0;
        data_bus_err  <= 1'b0;
        @(posedge clk);
    endtask

    // =========================================================================
    // Test senaryosu
    // =========================================================================
    logic [31:0] v;

    initial begin
        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("================================================================");
        $display(" JTAG/DEBUG BLOK TESTI");
        $display("================================================================");

        // ---------------------------------------------------------------------
        // 1) CSR yazmac erisimi
        // ---------------------------------------------------------------------
        axi_write({27'b0, REG_DBG_ADDR}, 32'h2001_0000);
        axi_read ({27'b0, REG_DBG_ADDR}, v);
        check("REG_DBG_ADDR geri okuma", v, 32'h2001_0000);

        axi_write({27'b0, REG_DBG_DATA}, 32'hDEAD_BEEF);
        axi_read ({27'b0, REG_DBG_DATA}, v);
        check("REG_DBG_DATA geri okuma", v, 32'hDEAD_BEEF);

        // ---------------------------------------------------------------------
        // 2) CPU halt / resume (CSR uzerinden)
        // ---------------------------------------------------------------------
        axi_write({27'b0, REG_DBG_CTRL}, 32'h1);      // Halt
        repeat (3) @(posedge clk);
        check("Halt -> debug_req_o", {31'b0, debug_req}, 32'h1);

        axi_write({27'b0, REG_DBG_CTRL}, 32'h2);      // Resume
        repeat (3) @(posedge clk);
        check("Resume -> debug_req_o", {31'b0, debug_req}, 32'h0);

        // ---------------------------------------------------------------------
        // 3) VERI koprusu hatasi
        // ---------------------------------------------------------------------
        check("Baslangicta hata bayragi bos", {31'b0, bus_fault_irq}, 32'h0);

        hata_darbesi(1'b0, 32'h4001_0008);            // veri koprusu
        repeat (2) @(posedge clk);

        check("Veri hatasi -> kesme", {31'b0, bus_fault_irq}, 32'h1);
        axi_read({27'b0, REG_FAULT_ST}, v);
        check("FAULT_ST = veri koprusu (bit0+bit2)", v, 32'h5);
        axi_read({27'b0, REG_FAULT_ADDR}, v);
        check("FAULT_ADDR", v, 32'h4001_0008);

        // Temizle
        axi_write({27'b0, REG_FAULT_CLR}, 32'h1);
        repeat (2) @(posedge clk);
        check("Temizleme sonrasi kesme dustu", {31'b0, bus_fault_irq}, 32'h0);
        axi_read({27'b0, REG_FAULT_ST}, v);
        check("Temizleme sonrasi FAULT_ST", v, 32'h0);

        // ---------------------------------------------------------------------
        // 4) BUYRUK koprusu hatasi
        //
        // Sistem testinde bu yol HIC tetiklenmiyor: orada yalnizca CPU'nun
        // Boot ROM'a yazma denemesi (veri koprusu) hata uretiyor.
        // ---------------------------------------------------------------------
        hata_darbesi(1'b1, 32'h0000_0200);            // buyruk koprusu
        repeat (2) @(posedge clk);

        axi_read({27'b0, REG_FAULT_ST}, v);
        check("FAULT_ST = buyruk koprusu (bit0+bit1)", v, 32'h3);
        axi_read({27'b0, REG_FAULT_ADDR}, v);
        check("FAULT_ADDR (buyruk)", v, 32'h0000_0200);

        // ---------------------------------------------------------------------
        // 5) "Ilk hata saklanir" tasarim karari
        //
        // Ikincil hatalar genellikle birincinin sonucudur; asil bilgi ilk
        // adrestir. Bayrak temizlenmeden gelen ikinci hata UZERINE YAZMAMALI.
        // ---------------------------------------------------------------------
        hata_darbesi(1'b0, 32'hAAAA_BBBB);            // temizlemeden ikinci hata
        repeat (2) @(posedge clk);

        axi_read({27'b0, REG_FAULT_ADDR}, v);
        check("Ilk hata korundu (uzerine yazilmadi)", v, 32'h0000_0200);
        axi_read({27'b0, REG_FAULT_ST}, v);
        check("Ilk hata kaynagi korundu", v, 32'h3);

        axi_write({27'b0, REG_FAULT_CLR}, 32'h1);
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------------
        // JTAG TAP SERI PROTOKOLU
        //
        // Sartname EK-2 (JTAG, opsiyonel): "Islemcinin debug portuna
        // mikrodenetleyici icerisindeki bir JTAG TAP kontrolcusu uzerinden
        // erisilebilir."
        //
        // 16 durumlu TAP durum makinesi yalnizca sistem testinde
        // calisiyordu; blok kapsamasinda hic gorunmuyordu.
        // ---------------------------------------------------------------------
        begin
            logic [63:0] dr;

            $display("  -- JTAG TAP seri protokolu");
            jtag_reset();

            // --- IDCODE (IR = 0x1) ---
            jtag_shift_ir(4'h1);
            jtag_shift_dr(64'h0, 32, dr);
            check("TAP IDCODE", dr[31:0], 32'h4152_4B48);

            // --- Ikinci okuma ayni degeri vermeli (TAP kararliligi) ---
            jtag_shift_dr(64'h0, 32, dr);
            check("TAP IDCODE tekrar", dr[31:0], 32'h4152_4B48);

            // --- BYPASS (IR = 0xF): tek bitlik yazmac ---
            // BYPASS'ta TDI, bir cevrim gecikmeyle TDO'ya cikar. Ilk bit
            // her zaman 0'dir (yazmac reset degeri).
            jtag_shift_ir(4'hF);
            jtag_shift_dr(64'h0, 1, dr);
            check("TAP BYPASS ilk bit 0", {63'b0, dr[0]}, 64'h0);

            // --- TAP reset IR'i BYPASS'a dondurur ---
            // Sartname/IEEE 1149.1: TEST_LOGIC_RESET durumunda IR, IDCODE
            // veya BYPASS'a doner. Bu tasarimda IR_BYPASS'tir.
            jtag_reset();
            jtag_shift_dr(64'h0, 1, dr);
            check("TAP reset sonrasi BYPASS", {63'b0, dr[0]}, 64'h0);

            // --- DBG_CTRL uzerinden halt (IR = 0x4) ---
            //
            // TAP yolunda RTL dogrudan bit 0'i kullanir:
            //     dbg_halted <= jtag_dr_latched[0];
            // (CSR yolundan farkli: orada [0]=halt, [1]=resume ayri bitler.)
            //
            // Komut TCK alanindan CLK alanina iki asamali senkronizatorle
            // gecer; TCK periyodu 200 ns, sistem saati 20 ns. Bekleme
            // buna gore secilmeli - kisa beklemede test yaniltici sekilde
            // "bir islem geriden" gorunuyordu.
            // DR 64 bittir ve SAGA kayar:
            //     dr_reg <= {jtag_tdi, dr_reg[63:1]};
            // Yani TDI bit 63'ten girer. Bir degerin bit 0'a ulasmasi icin
            // TAM 64 bit kaydirmak gerekir. Kisa kaydirma denemesi bu
            // yuzden basarisiz olmustu - tasarim dogru, test eksikti.
            jtag_shift_ir(4'h4);
            jtag_shift_dr(64'h1, 64, dr);          // bit0 = 1 -> halt
            repeat (60) @(posedge clk);
            check("TAP DBG_CTRL halt", {31'b0, debug_req}, 32'h1);

            jtag_shift_dr(64'h0, 64, dr);          // bit0 = 0 -> resume
            repeat (60) @(posedge clk);
            check("TAP DBG_CTRL resume", {31'b0, debug_req}, 32'h0);
        end

        // ---------------------------------------------------------------------
        // Ozet
        // ---------------------------------------------------------------------
        $display("================================================================");
        if (error_count != 0) begin
            $display(" JTAG BLOK TESTI BASARISIZ - %0d hata / %0d denetim",
                     error_count, check_count);
            $display("================================================================");
            $fatal(1, "JTAG blok dogrulamasi basarisiz");
        end else begin
            $display(" JTAG BLOK TESTI GECTI - %0d denetim, 0 hata", check_count);
            $display("================================================================");
        end
        $finish;
    end

    // =========================================================================
    // DUT
    // =========================================================================
    jtag_debug dut (
        .clk                  (clk),
        .rst_n                (rst_n),

        .jtag_tms             (jtag_tms),
        .jtag_tck             (jtag_tck),
        .jtag_tdi             (jtag_tdi),
        .jtag_tdo             (jtag_tdo),
        .jtag_trst_n          (jtag_trst_n),

        .debug_req_o          (debug_req),

        .instr_bus_err_i      (instr_bus_err),
        .instr_bus_err_addr_i (instr_bus_err_addr),
        .data_bus_err_i       (data_bus_err),
        .data_bus_err_addr_i  (data_bus_err_addr),
        .bus_fault_irq_o      (bus_fault_irq),

        .s_axi_awaddr         (awaddr),  .s_axi_awvalid (awvalid), .s_axi_awready (awready),
        .s_axi_wdata          (wdata),   .s_axi_wstrb   (4'hF),
        .s_axi_wvalid         (wvalid),  .s_axi_wready  (wready),
        .s_axi_bresp          (bresp),   .s_axi_bvalid  (bvalid),  .s_axi_bready  (bready),
        .s_axi_araddr         (araddr),  .s_axi_arvalid (arvalid), .s_axi_arready (arready),
        .s_axi_rdata          (rdata),   .s_axi_rresp   (rresp),
        .s_axi_rvalid         (rvalid),  .s_axi_rready  (rready),

        // AXI master portu bu testte kullanilmiyor - guvenli sabitler
        .m_axi_awaddr  (), .m_axi_awvalid (), .m_axi_awready (1'b1),
        .m_axi_wdata   (), .m_axi_wstrb   (), .m_axi_wvalid  (), .m_axi_wready (1'b1),
        .m_axi_bresp   (2'b00), .m_axi_bvalid (1'b1), .m_axi_bready (),
        .m_axi_araddr  (), .m_axi_arvalid (), .m_axi_arready (1'b1),
        .m_axi_rdata   (32'h0), .m_axi_rresp (2'b00), .m_axi_rvalid (1'b1), .m_axi_rready ()
    );

endmodule
