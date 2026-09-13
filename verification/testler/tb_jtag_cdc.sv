// =============================================================================
//  tb_jtag_cdc.sv
//
//  NEDEN VAR
//    12 Eylul 2026 akis arastirmasi sunu buldu:
//
//    Tasarimda IKI ASENKRON SAAT ALANI var:
//        clk_i     50 MHz  (sistem)
//        jtag_tck  bagimsiz (harici JTAG programlayici)
//
//    SDC bunlari acikca ayirir:
//        set_clock_groups -asynchronous -group {clk_i} -group {jtag_clk}
//
//    Mevcut `tb_jtag_debug.sv` TCK'yi ELLE darbeliyor:
//        jtag_tck = 1'b0; #100;
//        jtag_tck = 1'b1; #100;
//
//    Yani TCK periyodu 200 ns, clk 20 ns - TAM 10 KATI. Iki saat HER
//    ZAMAN HIZALI. Gercek asenkron iliski (kaymali faz, senkronizator
//    penceresi) HIC TEST EDILMIYOR.
//
//  NE TEST EDILIYOR
//    `jtag_debug.sv` iki kademeli senkronizator kullanir (satir 246-265):
//
//        jtag_cmd_valid_sync1 <= jtag_cmd_valid;      // TCK alanindan
//        jtag_cmd_valid_sync2 <= jtag_cmd_valid_sync1;
//        assign jtag_cmd_pulse = sync2 && !sync2_prev;
//
//    Veri (jtag_dr_latched, jtag_ir_latched) senkronize EDILMEZ; yalnizca
//    kontrol sinyali senkronize edilir ve veri o darbe geldiginde okunur.
//    Bu standart MCP (multi-cycle path) kalibidir ve DOGRUDUR - ama
//    dogrulanmamisti.
//
//  BU TEST NE YAPAR
//    TCK'yi clk ile aralarinda TAM SAYI ORANI OLMAYAN periyotlarla surer
//    ve her seferinde JTAG uzerinden bellek yazma/okuma yapar. Veri
//    dogru gecerse senkronizator calisiyor demektir.
//
//    Denenen periyotlar (clk = 20 ns) - HICBIRI TAM SAYI ORAN DEGIL:
//        34 ns  -> oran 1,70
//        46 ns  -> oran 2,30
//        74 ns  -> oran 3,70
//       106 ns  -> oran 5,30
//        26 ns  -> oran 1,30  (sistem saatine en yakin)
//    Ayrica her turda TCK fazi kaydirilir (0/3/6/9 ns).
// =============================================================================
`timescale 1ns/1ps

module tb_jtag_cdc;

    localparam int AW = 32;
    localparam int DW = 32;

    // Sistem saati - SABIT 50 MHz
    logic clk = 1'b0, rst_n = 1'b0;
    always #10 clk = ~clk;      // 20 ns = 50 MHz

    // JTAG pinleri
    logic jtag_tms = 1'b1, jtag_tck = 1'b0, jtag_tdi = 1'b0, jtag_trst_n = 1'b1;
    logic jtag_tdo;

    // TCK yarim periyodu - her turda DEGISIR
    int tck_yarim = 50;   // ns (TAM SAYI - yuvarlama yok)

    logic debug_req_o, bus_fault_irq_o;

    // AXI slave (CSR) - kullanilmiyor ama baglanmali
    logic [AW-1:0] s_awaddr = '0;  logic s_awvalid = 1'b0; logic s_awready;
    logic [DW-1:0] s_wdata = '0;   logic [3:0] s_wstrb = '0;
    logic s_wvalid = 1'b0;         logic s_wready;
    logic [1:0] s_bresp;           logic s_bvalid; logic s_bready = 1'b1;
    logic [AW-1:0] s_araddr = '0;  logic s_arvalid = 1'b0; logic s_arready;
    logic [DW-1:0] s_rdata;        logic [1:0] s_rresp; logic s_rvalid;
    logic s_rready = 1'b1;

    // AXI master (JTAG -> bellek)
    logic [AW-1:0] m_awaddr;  logic m_awvalid; logic m_awready;
    logic [DW-1:0] m_wdata;   logic [3:0] m_wstrb; logic m_wvalid; logic m_wready;
    logic [1:0] m_bresp;      logic m_bvalid;  logic m_bready;
    logic [AW-1:0] m_araddr;  logic m_arvalid; logic m_arready;
    logic [DW-1:0] m_rdata;   logic [1:0] m_rresp; logic m_rvalid; logic m_rready;

    int pass_count = 0, fail_count = 0;

    jtag_debug dut (
        .clk(clk), .rst_n(rst_n),
        .jtag_tms(jtag_tms), .jtag_tck(jtag_tck), .jtag_tdi(jtag_tdi),
        .jtag_tdo(jtag_tdo), .jtag_trst_n(jtag_trst_n),
        .debug_req_o(debug_req_o),
        .instr_bus_err_i(1'b0), .instr_bus_err_addr_i(32'h0),
        .data_bus_err_i(1'b0),  .data_bus_err_addr_i(32'h0),
        .bus_fault_irq_o(bus_fault_irq_o),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wvalid(s_wvalid),
        .s_axi_wready(s_wready),
        .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
        .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rvalid(s_rvalid),
        .s_axi_rready(s_rready),
        .m_axi_awaddr(m_awaddr), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_araddr(m_araddr), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp), .m_axi_rvalid(m_rvalid),
        .m_axi_rready(m_rready)
    );

    // -------------------------------------------------------------------
    //  BASIT BELLEK MODELI (JTAG master'in hedefi)
    //  Yazilan degeri saklar, okundugunda geri verir.
    // -------------------------------------------------------------------
    logic [31:0] bellek [0:15];
    logic        aw_alindi, w_alindi;
    logic [31:0] son_adres, son_veri;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awready <= 1'b0; m_wready <= 1'b0;
            m_bvalid  <= 1'b0; m_bresp  <= 2'b00;
            m_arready <= 1'b0; m_rvalid <= 1'b0;
            m_rdata   <= 32'h0; m_rresp <= 2'b00;
            aw_alindi <= 1'b0; w_alindi <= 1'b0;
        end else begin
            // --- yazma ---
            m_awready <= m_awvalid && !aw_alindi && !m_bvalid;
            m_wready  <= m_wvalid  && !w_alindi  && !m_bvalid;
            if (m_awvalid && m_awready) begin
                aw_alindi <= 1'b1;
                son_adres <= m_awaddr;
            end
            if (m_wvalid && m_wready) begin
                w_alindi <= 1'b1;
                son_veri <= m_wdata;
            end
            if (aw_alindi && w_alindi && !m_bvalid) begin
                bellek[son_adres[5:2]] <= son_veri;
                m_bvalid  <= 1'b1;
                m_bresp   <= 2'b00;
                aw_alindi <= 1'b0;
                w_alindi  <= 1'b0;
            end
            if (m_bvalid && m_bready) m_bvalid <= 1'b0;

            // --- okuma ---
            m_arready <= m_arvalid && !m_rvalid;
            if (m_arvalid && m_arready) begin
                m_rvalid <= 1'b1;
                m_rdata  <= bellek[m_araddr[5:2]];
                m_rresp  <= 2'b00;
            end
            if (m_rvalid && m_rready) m_rvalid <= 1'b0;
        end
    end

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    // -------------------------------------------------------------------
    //  JTAG TAP surme - TCK periyodu DEGISKEN
    //
    //  Mevcut testte sabit #100 kullaniliyordu; burada `tck_yarim`
    //  degiskeni her turda farkli bir degere ayarlanir.
    // -------------------------------------------------------------------
    task automatic jtag_clock();
        jtag_tck = 1'b0; #(tck_yarim);
        jtag_tck = 1'b1; #(tck_yarim);
        jtag_tck = 1'b0;
    endtask

    task automatic jtag_reset();
        jtag_trst_n = 1'b0; #(tck_yarim);
        jtag_trst_n = 1'b1;
        jtag_tms = 1'b1;
        repeat (5) jtag_clock();
        jtag_tms = 1'b0;
        jtag_clock();
    endtask

    task automatic jtag_shift_ir(input logic [3:0] ir_in);
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        for (int i = 0; i < 4; i++) begin
            jtag_tdi = ir_in[i];
            jtag_tms = (i == 3) ? 1'b1 : 1'b0;
            jtag_clock();
        end
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
    endtask

    task automatic jtag_shift_dr64(input logic [63:0] dr_in);
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        for (int i = 0; i < 64; i++) begin
            jtag_tdi = dr_in[i];
            jtag_tms = (i == 63) ? 1'b1 : 1'b0;
            jtag_clock();
        end
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
    endtask

    // -------------------------------------------------------------------
    //  Bir JTAG yazma islemi (IR=MEM_WRITE, DR = {veri, adres})
    // -------------------------------------------------------------------
    task automatic jtag_bellek_yaz(input [31:0] adr, input [31:0] veri);
        begin
            jtag_shift_ir(4'h3);                    // IR_MEM_WRITE
            jtag_shift_dr64({veri, adr});
            // clk alanindaki islemin tamamlanmasini bekle
            repeat (40) @(posedge clk);
        end
    endtask

    // Bir tur: belirli TCK periyodunda yaz ve dogrula
    task automatic tur_kos(input int yarim, input [31:0] adr,
                           input [31:0] veri, input string ad,
                           output bit basarili);
        begin
            tck_yarim = yarim;
            jtag_reset();
            jtag_bellek_yaz(adr, veri);
            basarili = (bellek[adr[5:2]] === veri);
            $display("    %-22s TCK=%0d ns (oran %0.2f)  bellek[%0d]=0x%08h",
                     ad, yarim * 2, real'(yarim * 2) / 20.0,
                     adr[5:2], bellek[adr[5:2]]);
        end
    endtask

    bit ok;
    int basari;

    initial begin
        $display("================================================================");
        $display(" JTAG SAAT ALANI GECISI (CDC) DOGRULAMASI");
        $display("================================================================");
        $display("");
        $display("Sistem saati sabit 50 MHz (20 ns).");
        $display("TCK her turda FARKLI periyotta - clk ile tam sayi orani YOK.");
        $display("Mevcut tb_jtag_debug TCK'yi 200 ns'de sabit tutuyordu (tam 10x).");
        $display("");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ===============================================================
        //  1. FARKLI TCK PERIYOTLARI - tam sayi orani YOK
        // ===============================================================
        $display("1. Asenkron TCK periyotlari");
        basari = 0;

        tur_kos(17, 32'h00000000, 32'hA5A5_0001, "TCK 34 ns", ok);
        if (ok) basari++;

        tur_kos(23, 32'h00000004, 32'hA5A5_0002, "TCK 46 ns", ok);
        if (ok) basari++;

        tur_kos(37, 32'h00000008, 32'hA5A5_0003, "TCK 74 ns", ok);
        if (ok) basari++;

        tur_kos(53, 32'h0000000C, 32'hA5A5_0004, "TCK 106 ns", ok);
        if (ok) basari++;

        kontrol(basari == 4,
                $sformatf("%0d/4 asenkron TCK periyodunda veri DOGRU gecti", basari));

        // ===============================================================
        //  2. FAZ KAYDIRMA - ayni periyot, farkli baslangic fazi
        //
        //  Senkronizator penceresi faza duyarliysa burada gorunur.
        // ===============================================================
        $display("");
        $display("2. Faz kaydirma (ayni TCK, farkli baslangic ani)");
        basari = 0;

        for (int f = 0; f < 4; f++) begin
            // clk'e gore kaymali bir noktada basla
            #(f * 3);
            tck_yarim = 17;
            jtag_reset();
            jtag_bellek_yaz(32'h00000000 + f*4, 32'hBEEF_0000 + f);
            if (bellek[f] === (32'hBEEF_0000 + f)) basari++;
            else $display("    faz %0d: bellek[%0d]=0x%08h (beklenen 0x%08h)",
                          f, f, bellek[f], 32'hBEEF_0000 + f);
        end

        kontrol(basari == 4,
                $sformatf("%0d/4 faz kaymasinda veri DOGRU gecti", basari));

        // ===============================================================
        //  3. COK HIZLI TCK - sistem saatine YAKIN
        //
        //  TCK clk'e yaklastikca senkronizator daha sik zorlanir.
        // ===============================================================
        $display("");
        $display("3. Hizli TCK (sistem saatine yakin)");

        tur_kos(13, 32'h00000010, 32'hFACE_0001, "TCK 26 ns", ok);
        kontrol(ok, "TCK 26 ns (clk'in 1,3 kati): veri dogru");

        // ===============================================================
        //  4. ARDISIK ISLEMLER - senkronizator arka arkaya zorlanir
        // ===============================================================
        $display("");
        $display("4. Ardisik islemler (ayni turda 4 yazma)");

        tck_yarim = 17;
        jtag_reset();
        basari = 0;
        for (int i = 0; i < 4; i++) begin
            jtag_bellek_yaz(32'h00000020 + i*4, 32'hC0DE_0000 + i);
            if (bellek[8 + i] === (32'hC0DE_0000 + i)) basari++;
            else $display("    islem %0d: bellek[%0d]=0x%08h (beklenen 0x%08h)",
                          i, 8+i, bellek[8+i], 32'hC0DE_0000 + i);
        end
        kontrol(basari == 4,
                $sformatf("%0d/4 ardisik islem DOGRU tamamlandi", basari));

        $display("");
        $display("================================================================");
        if (fail_count == 0)
            $display(" TB SONUC: GECTI  (%0d denetim)", pass_count);
        else
            $display(" TB SONUC: KALDI  (%0d gecti, %0d kaldi)", pass_count, fail_count);
        $display("================================================================");
        $finish;
    end

    // Gozcu
    initial begin
        #20_000_000;
        $display("  [HATA] gozcu: test 20 ms icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
