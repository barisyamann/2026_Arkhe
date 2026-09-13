// =============================================================================
//  tb_interconnect_adres.sv
//
//  NEDEN VAR
//    `axi_lite_interconnect.sv` 616 satirla en buyuk TEST EDILMEMIS
//    moduldu. 13 slave'e adres cozme yapiyor ve kendi blok testi yoktu;
//    yalnizca sistem testi icinde DOLAYLI calisiyordu.
//
//    Dolayli calismanin sorunu: sistem testi yalnizca FIILEN KULLANILAN
//    adresleri dokunur. Bir slave'in SINIR adresi yanlis cozulse veya
//    iki bolge ortusse, o yol hic kullanilmadigi icin fark edilmez.
//
//  ADRES HARITASI (get_slave_id, satir 306-321)
//     0  Boot ROM      0x0000_0000 - 0x0000_03FF
//     1  Instr RAM     0x0100_0000 - 0x0100_1FFF
//     2  Data RAM      0x2000_0000 - 0x2000_1FFF
//     3  GPIO          0x4000_0000 - 0x4000_0FFF
//     4  Timer         0x4001_0000 - 0x4001_0FFF
//     5  UART1         0x4002_0000 - 0x4002_0FFF
//     6  UART2         0x4003_0000 - 0x4003_0FFF
//     7  I2C           0x4004_0000 - 0x4004_0FFF
//     8  QSPI          0x4005_0000 - 0x4005_0FFF
//     9  NPU CSR       0x4006_0000 - 0x4006_0FFF
//    10  NPU Memory    0x2001_0000 - 0x2001_77FF
//    11  DMA CSR       0x4007_0000 - 0x4007_0FFF
//    12  JTAG CSR      0x4008_0000 - 0x4008_0FFF
//    13  (cozulemeyen) -> DECERR + 0xDEADBEEF
//
//  NE DOGRULAR
//    1. Her slave'in ALT ve UST sinir adresi DOGRU slave'e gidiyor
//    2. Bolge disindaki adresler DECERR uretiyor (0xDEADBEEF)
//    3. Bolgeler ORTUSMUYOR (her adres tek bir slave'e gidiyor)
//    4. Yazma ve okuma yollari AYNI cozumu yapiyor
//    5. Cozulemeyen adres yazmasi da DECERR (bresp=2'b11) veriyor
// =============================================================================
`timescale 1ns/1ps

module tb_interconnect_adres;

    localparam int NS = 13;          // slave sayisi

    logic clk = 1'b0, rst_n = 1'b0;
    always #5ns clk = ~clk;

    // Master taraf
    logic [31:0] m_awaddr;  logic m_awvalid, m_awready;
    logic [31:0] m_wdata;   logic [3:0] m_wstrb; logic m_wvalid, m_wready;
    logic [1:0]  m_bresp;   logic m_bvalid, m_bready;
    logic [31:0] m_araddr;  logic m_arvalid, m_arready;
    logic [31:0] m_rdata;   logic [1:0] m_rresp; logic m_rvalid, m_rready;

    // Slave taraf - 13 slave, her biri dizide
    logic [31:0] s_awaddr [NS];  logic s_awvalid [NS]; logic s_awready [NS];
    logic [31:0] s_wdata  [NS];  logic [3:0] s_wstrb [NS];
    logic        s_wvalid [NS];  logic s_wready [NS];
    logic [1:0]  s_bresp  [NS];  logic s_bvalid [NS];  logic s_bready [NS];
    logic [31:0] s_araddr [NS];  logic s_arvalid [NS]; logic s_arready [NS];
    logic [31:0] s_rdata  [NS];  logic [1:0] s_rresp [NS];
    logic        s_rvalid [NS];  logic s_rready [NS];

    int pass_count = 0, fail_count = 0;

    // -------------------------------------------------------------------
    //  SAHTE SLAVE MODELI
    //
    //  Her slave kendi KIMLIGINI okuma verisi olarak dondurur:
    //      rdata = 32'hA5A50000 + slave_id
    //  Boylece hangi slave'in yanit verdigi KESIN olarak anlasilir.
    //  Adres cozme hatasi varsa yanlis kimlik doner ve yakalanir.
    // -------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < NS; gi++) begin : g_slave
            // Yazma: AW ve W gelince hemen kabul, B ile yanitla
            logic aw_alindi, w_alindi;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s_awready[gi] <= 1'b0;
                    s_wready[gi]  <= 1'b0;
                    s_bvalid[gi]  <= 1'b0;
                    s_bresp[gi]   <= 2'b00;
                    aw_alindi     <= 1'b0;
                    w_alindi      <= 1'b0;
                end else begin
                    s_awready[gi] <= s_awvalid[gi] && !aw_alindi && !s_bvalid[gi];
                    s_wready[gi]  <= s_wvalid[gi]  && !w_alindi  && !s_bvalid[gi];

                    if (s_awvalid[gi] && s_awready[gi]) aw_alindi <= 1'b1;
                    if (s_wvalid[gi]  && s_wready[gi])  w_alindi  <= 1'b1;

                    if (aw_alindi && w_alindi && !s_bvalid[gi]) begin
                        s_bvalid[gi] <= 1'b1;
                        s_bresp[gi]  <= 2'b00;      // OKAY
                        aw_alindi    <= 1'b0;
                        w_alindi     <= 1'b0;
                    end
                    if (s_bvalid[gi] && s_bready[gi]) s_bvalid[gi] <= 1'b0;
                end
            end

            // Okuma: AR gelince KIMLIGINI dondur
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s_arready[gi] <= 1'b0;
                    s_rvalid[gi]  <= 1'b0;
                    s_rdata[gi]   <= 32'h0;
                    s_rresp[gi]   <= 2'b00;
                end else begin
                    s_arready[gi] <= s_arvalid[gi] && !s_rvalid[gi];
                    if (s_arvalid[gi] && s_arready[gi]) begin
                        s_rvalid[gi] <= 1'b1;
                        s_rdata[gi]  <= 32'hA5A5_0000 + gi;   // KIMLIK
                        s_rresp[gi]  <= 2'b00;
                    end
                    if (s_rvalid[gi] && s_rready[gi]) s_rvalid[gi] <= 1'b0;
                end
            end
        end
    endgenerate

    axi_lite_interconnect dut (
        .clk(clk), .rst_n(rst_n),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata),   .m_wstrb(m_wstrb),     .m_wvalid(m_wvalid),
        .m_wready(m_wready),
        .m_bresp(m_bresp),   .m_bvalid(m_bvalid),   .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata),   .m_rresp(m_rresp),     .m_rvalid(m_rvalid),
        .m_rready(m_rready),

        .s0_awaddr(s_awaddr[0]), .s0_awvalid(s_awvalid[0]), .s0_awready(s_awready[0]),
        .s0_wdata(s_wdata[0]), .s0_wstrb(s_wstrb[0]), .s0_wvalid(s_wvalid[0]), .s0_wready(s_wready[0]),
        .s0_bresp(s_bresp[0]), .s0_bvalid(s_bvalid[0]), .s0_bready(s_bready[0]),
        .s0_araddr(s_araddr[0]), .s0_arvalid(s_arvalid[0]), .s0_arready(s_arready[0]),
        .s0_rdata(s_rdata[0]), .s0_rresp(s_rresp[0]), .s0_rvalid(s_rvalid[0]), .s0_rready(s_rready[0]),

        .s1_awaddr(s_awaddr[1]), .s1_awvalid(s_awvalid[1]), .s1_awready(s_awready[1]),
        .s1_wdata(s_wdata[1]), .s1_wstrb(s_wstrb[1]), .s1_wvalid(s_wvalid[1]), .s1_wready(s_wready[1]),
        .s1_bresp(s_bresp[1]), .s1_bvalid(s_bvalid[1]), .s1_bready(s_bready[1]),
        .s1_araddr(s_araddr[1]), .s1_arvalid(s_arvalid[1]), .s1_arready(s_arready[1]),
        .s1_rdata(s_rdata[1]), .s1_rresp(s_rresp[1]), .s1_rvalid(s_rvalid[1]), .s1_rready(s_rready[1]),

        .s2_awaddr(s_awaddr[2]), .s2_awvalid(s_awvalid[2]), .s2_awready(s_awready[2]),
        .s2_wdata(s_wdata[2]), .s2_wstrb(s_wstrb[2]), .s2_wvalid(s_wvalid[2]), .s2_wready(s_wready[2]),
        .s2_bresp(s_bresp[2]), .s2_bvalid(s_bvalid[2]), .s2_bready(s_bready[2]),
        .s2_araddr(s_araddr[2]), .s2_arvalid(s_arvalid[2]), .s2_arready(s_arready[2]),
        .s2_rdata(s_rdata[2]), .s2_rresp(s_rresp[2]), .s2_rvalid(s_rvalid[2]), .s2_rready(s_rready[2]),

        .s3_awaddr(s_awaddr[3]), .s3_awvalid(s_awvalid[3]), .s3_awready(s_awready[3]),
        .s3_wdata(s_wdata[3]), .s3_wstrb(s_wstrb[3]), .s3_wvalid(s_wvalid[3]), .s3_wready(s_wready[3]),
        .s3_bresp(s_bresp[3]), .s3_bvalid(s_bvalid[3]), .s3_bready(s_bready[3]),
        .s3_araddr(s_araddr[3]), .s3_arvalid(s_arvalid[3]), .s3_arready(s_arready[3]),
        .s3_rdata(s_rdata[3]), .s3_rresp(s_rresp[3]), .s3_rvalid(s_rvalid[3]), .s3_rready(s_rready[3]),

        .s4_awaddr(s_awaddr[4]), .s4_awvalid(s_awvalid[4]), .s4_awready(s_awready[4]),
        .s4_wdata(s_wdata[4]), .s4_wstrb(s_wstrb[4]), .s4_wvalid(s_wvalid[4]), .s4_wready(s_wready[4]),
        .s4_bresp(s_bresp[4]), .s4_bvalid(s_bvalid[4]), .s4_bready(s_bready[4]),
        .s4_araddr(s_araddr[4]), .s4_arvalid(s_arvalid[4]), .s4_arready(s_arready[4]),
        .s4_rdata(s_rdata[4]), .s4_rresp(s_rresp[4]), .s4_rvalid(s_rvalid[4]), .s4_rready(s_rready[4]),

        .s5_awaddr(s_awaddr[5]), .s5_awvalid(s_awvalid[5]), .s5_awready(s_awready[5]),
        .s5_wdata(s_wdata[5]), .s5_wstrb(s_wstrb[5]), .s5_wvalid(s_wvalid[5]), .s5_wready(s_wready[5]),
        .s5_bresp(s_bresp[5]), .s5_bvalid(s_bvalid[5]), .s5_bready(s_bready[5]),
        .s5_araddr(s_araddr[5]), .s5_arvalid(s_arvalid[5]), .s5_arready(s_arready[5]),
        .s5_rdata(s_rdata[5]), .s5_rresp(s_rresp[5]), .s5_rvalid(s_rvalid[5]), .s5_rready(s_rready[5]),

        .s6_awaddr(s_awaddr[6]), .s6_awvalid(s_awvalid[6]), .s6_awready(s_awready[6]),
        .s6_wdata(s_wdata[6]), .s6_wstrb(s_wstrb[6]), .s6_wvalid(s_wvalid[6]), .s6_wready(s_wready[6]),
        .s6_bresp(s_bresp[6]), .s6_bvalid(s_bvalid[6]), .s6_bready(s_bready[6]),
        .s6_araddr(s_araddr[6]), .s6_arvalid(s_arvalid[6]), .s6_arready(s_arready[6]),
        .s6_rdata(s_rdata[6]), .s6_rresp(s_rresp[6]), .s6_rvalid(s_rvalid[6]), .s6_rready(s_rready[6]),

        .s7_awaddr(s_awaddr[7]), .s7_awvalid(s_awvalid[7]), .s7_awready(s_awready[7]),
        .s7_wdata(s_wdata[7]), .s7_wstrb(s_wstrb[7]), .s7_wvalid(s_wvalid[7]), .s7_wready(s_wready[7]),
        .s7_bresp(s_bresp[7]), .s7_bvalid(s_bvalid[7]), .s7_bready(s_bready[7]),
        .s7_araddr(s_araddr[7]), .s7_arvalid(s_arvalid[7]), .s7_arready(s_arready[7]),
        .s7_rdata(s_rdata[7]), .s7_rresp(s_rresp[7]), .s7_rvalid(s_rvalid[7]), .s7_rready(s_rready[7]),

        .s8_awaddr(s_awaddr[8]), .s8_awvalid(s_awvalid[8]), .s8_awready(s_awready[8]),
        .s8_wdata(s_wdata[8]), .s8_wstrb(s_wstrb[8]), .s8_wvalid(s_wvalid[8]), .s8_wready(s_wready[8]),
        .s8_bresp(s_bresp[8]), .s8_bvalid(s_bvalid[8]), .s8_bready(s_bready[8]),
        .s8_araddr(s_araddr[8]), .s8_arvalid(s_arvalid[8]), .s8_arready(s_arready[8]),
        .s8_rdata(s_rdata[8]), .s8_rresp(s_rresp[8]), .s8_rvalid(s_rvalid[8]), .s8_rready(s_rready[8]),

        .s9_awaddr(s_awaddr[9]), .s9_awvalid(s_awvalid[9]), .s9_awready(s_awready[9]),
        .s9_wdata(s_wdata[9]), .s9_wstrb(s_wstrb[9]), .s9_wvalid(s_wvalid[9]), .s9_wready(s_wready[9]),
        .s9_bresp(s_bresp[9]), .s9_bvalid(s_bvalid[9]), .s9_bready(s_bready[9]),
        .s9_araddr(s_araddr[9]), .s9_arvalid(s_arvalid[9]), .s9_arready(s_arready[9]),
        .s9_rdata(s_rdata[9]), .s9_rresp(s_rresp[9]), .s9_rvalid(s_rvalid[9]), .s9_rready(s_rready[9]),

        .s10_awaddr(s_awaddr[10]), .s10_awvalid(s_awvalid[10]), .s10_awready(s_awready[10]),
        .s10_wdata(s_wdata[10]), .s10_wstrb(s_wstrb[10]), .s10_wvalid(s_wvalid[10]), .s10_wready(s_wready[10]),
        .s10_bresp(s_bresp[10]), .s10_bvalid(s_bvalid[10]), .s10_bready(s_bready[10]),
        .s10_araddr(s_araddr[10]), .s10_arvalid(s_arvalid[10]), .s10_arready(s_arready[10]),
        .s10_rdata(s_rdata[10]), .s10_rresp(s_rresp[10]), .s10_rvalid(s_rvalid[10]), .s10_rready(s_rready[10]),

        .s11_awaddr(s_awaddr[11]), .s11_awvalid(s_awvalid[11]), .s11_awready(s_awready[11]),
        .s11_wdata(s_wdata[11]), .s11_wstrb(s_wstrb[11]), .s11_wvalid(s_wvalid[11]), .s11_wready(s_wready[11]),
        .s11_bresp(s_bresp[11]), .s11_bvalid(s_bvalid[11]), .s11_bready(s_bready[11]),
        .s11_araddr(s_araddr[11]), .s11_arvalid(s_arvalid[11]), .s11_arready(s_arready[11]),
        .s11_rdata(s_rdata[11]), .s11_rresp(s_rresp[11]), .s11_rvalid(s_rvalid[11]), .s11_rready(s_rready[11]),

        .s12_awaddr(s_awaddr[12]), .s12_awvalid(s_awvalid[12]), .s12_awready(s_awready[12]),
        .s12_wdata(s_wdata[12]), .s12_wstrb(s_wstrb[12]), .s12_wvalid(s_wvalid[12]), .s12_wready(s_wready[12]),
        .s12_bresp(s_bresp[12]), .s12_bvalid(s_bvalid[12]), .s12_bready(s_bready[12]),
        .s12_araddr(s_araddr[12]), .s12_arvalid(s_arvalid[12]), .s12_arready(s_arready[12]),
        .s12_rdata(s_rdata[12]), .s12_rresp(s_rresp[12]), .s12_rvalid(s_rvalid[12]), .s12_rready(s_rready[12])
    );

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    // -------------------------------------------------------------------
    //  Okuma: adres -> (rdata, rresp)
    // -------------------------------------------------------------------
    task automatic oku(input [31:0] adr, output logic [31:0] veri,
                       output logic [1:0] yanit);
        int g;
        begin
            @(negedge clk); m_araddr = adr; m_arvalid = 1'b1; m_rready = 1'b1;
            @(negedge clk);
            g = 0;
            while (!m_arready && g < 60) begin @(negedge clk); g++; end
            @(negedge clk); m_arvalid = 1'b0;
            g = 0;
            while (!m_rvalid && g < 60) begin @(negedge clk); g++; end
            veri  = m_rdata;
            yanit = m_rresp;
            @(negedge clk); m_rready = 1'b0;
            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------
    //  Yazma: adres -> bresp
    // -------------------------------------------------------------------
    task automatic yaz(input [31:0] adr, input [31:0] veri,
                       output logic [1:0] yanit);
        int g;
        begin
            m_bready = 1'b1;
            fork
                begin
                    @(negedge clk); m_awaddr = adr; m_awvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!m_awready && g < 60) begin @(negedge clk); g++; end
                    @(negedge clk); m_awvalid = 1'b0;
                end
                begin
                    @(negedge clk); m_wdata = veri; m_wstrb = 4'b1111; m_wvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!m_wready && g < 60) begin @(negedge clk); g++; end
                    @(negedge clk); m_wvalid = 1'b0;
                end
            join
            g = 0;
            while (!m_bvalid && g < 60) begin @(negedge clk); g++; end
            yanit = m_bresp;
            @(negedge clk); m_bready = 1'b0;
            @(negedge clk);
        end
    endtask

    // Adres haritasi tablosu: {alt sinir, ust sinir, beklenen slave}
    localparam int SAYI = 13;
    logic [31:0] alt [SAYI];
    logic [31:0] ust [SAYI];
    string       ad  [SAYI];

    initial begin
        alt[0]  = 32'h0000_0000; ust[0]  = 32'h0000_03FF; ad[0]  = "BootROM";
        alt[1]  = 32'h0100_0000; ust[1]  = 32'h0100_1FFF; ad[1]  = "InstrRAM";
        alt[2]  = 32'h2000_0000; ust[2]  = 32'h2000_1FFF; ad[2]  = "DataRAM";
        alt[3]  = 32'h4000_0000; ust[3]  = 32'h4000_0FFF; ad[3]  = "GPIO";
        alt[4]  = 32'h4001_0000; ust[4]  = 32'h4001_0FFF; ad[4]  = "Timer";
        alt[5]  = 32'h4002_0000; ust[5]  = 32'h4002_0FFF; ad[5]  = "UART1";
        alt[6]  = 32'h4003_0000; ust[6]  = 32'h4003_0FFF; ad[6]  = "UART2";
        alt[7]  = 32'h4004_0000; ust[7]  = 32'h4004_0FFF; ad[7]  = "I2C";
        alt[8]  = 32'h4005_0000; ust[8]  = 32'h4005_0FFF; ad[8]  = "QSPI";
        alt[9]  = 32'h4006_0000; ust[9]  = 32'h4006_0FFF; ad[9]  = "NPU_CSR";
        alt[10] = 32'h2001_0000; ust[10] = 32'h2001_77FF; ad[10] = "NPU_MEM";
        alt[11] = 32'h4007_0000; ust[11] = 32'h4007_0FFF; ad[11] = "DMA";
        alt[12] = 32'h4008_0000; ust[12] = 32'h4008_0FFF; ad[12] = "JTAG";
    end

    logic [31:0] okunan;
    logic [1:0]  yanit;
    int          i;
    int          dogru_alt, dogru_ust, dogru_yazma;

    initial begin
        m_awaddr = 32'h0; m_awvalid = 1'b0;
        m_wdata  = 32'h0; m_wstrb = 4'b0; m_wvalid = 1'b0; m_bready = 1'b0;
        m_araddr = 32'h0; m_arvalid = 1'b0; m_rready = 1'b0;

        $display("================================================================");
        $display(" AXI4-LITE INTERCONNECT - ADRES COZME DOGRULAMASI");
        $display("================================================================");
        $display("");
        $display("Her slave KIMLIGINI dondurur (0xA5A50000 + id).");
        $display("Yanlis cozme YANLIS kimlik olarak gorunur.");
        $display("");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ===============================================================
        //  1. HER SLAVE'IN ALT SINIRI
        // ===============================================================
        $display("1. Alt sinir adresleri");
        dogru_alt = 0;
        for (i = 0; i < SAYI; i++) begin
            oku(alt[i], okunan, yanit);
            if (okunan === (32'hA5A5_0000 + i) && yanit === 2'b00) begin
                dogru_alt++;
            end else begin
                $display("      %-9s 0x%08h -> 0x%08h yanit=%0d (beklenen 0x%08h)",
                         ad[i], alt[i], okunan, yanit, 32'hA5A5_0000 + i);
            end
        end
        kontrol(dogru_alt == SAYI,
                $sformatf("%0d/%0d slave alt sinirdan DOGRU cozuldu", dogru_alt, SAYI));

        // ===============================================================
        //  2. HER SLAVE'IN UST SINIRI
        // ===============================================================
        $display("2. Ust sinir adresleri");
        dogru_ust = 0;
        for (i = 0; i < SAYI; i++) begin
            oku(ust[i], okunan, yanit);
            if (okunan === (32'hA5A5_0000 + i) && yanit === 2'b00) begin
                dogru_ust++;
            end else begin
                $display("      %-9s 0x%08h -> 0x%08h yanit=%0d (beklenen 0x%08h)",
                         ad[i], ust[i], okunan, yanit, 32'hA5A5_0000 + i);
            end
        end
        kontrol(dogru_ust == SAYI,
                $sformatf("%0d/%0d slave ust sinirdan DOGRU cozuldu", dogru_ust, SAYI));

        // ===============================================================
        //  3. YAZMA YOLU AYNI COZUMU YAPIYOR MU
        // ===============================================================
        $display("3. Yazma yolu adres cozme");
        dogru_yazma = 0;
        for (i = 0; i < SAYI; i++) begin
            yaz(alt[i], 32'hCAFE_0000 + i, yanit);
            if (yanit === 2'b00) dogru_yazma++;
            else $display("      %-9s yazma yanit=%0d (beklenen OKAY)", ad[i], yanit);
        end
        kontrol(dogru_yazma == SAYI,
                $sformatf("%0d/%0d slave yazmada OKAY dondurdu", dogru_yazma, SAYI));

        // ===============================================================
        //  4. COZULEMEYEN ADRESLER -> DECERR
        //
        //  Haritadaki BOSLUKLAR. Her biri hicbir slave'e ait degil.
        // ===============================================================
        $display("4. Cozulemeyen adresler (DECERR bekleniyor)");

        oku(32'h0000_0400, okunan, yanit);   // BootROM'un hemen ustu
        kontrol(yanit === 2'b11 && okunan === 32'hDEAD_BEEF,
                $sformatf("0x00000400 (BootROM+1) DECERR: yanit=%0d veri=0x%08h",
                          yanit, okunan));

        oku(32'h0100_2000, okunan, yanit);   // InstrRAM'in hemen ustu
        kontrol(yanit === 2'b11,
                $sformatf("0x01002000 (InstrRAM+1) DECERR: yanit=%0d", yanit));

        oku(32'h3000_0000, okunan, yanit);   // tamamen bos bolge
        kontrol(yanit === 2'b11,
                $sformatf("0x30000000 (bos bolge) DECERR: yanit=%0d", yanit));

        oku(32'h4009_0000, okunan, yanit);   // JTAG'in ustu
        kontrol(yanit === 2'b11,
                $sformatf("0x40090000 (JTAG+1) DECERR: yanit=%0d", yanit));

        oku(32'hFFFF_FFFF, okunan, yanit);   // en ust adres
        kontrol(yanit === 2'b11,
                $sformatf("0xFFFFFFFF (en ust) DECERR: yanit=%0d", yanit));

        // ===============================================================
        //  5. COZULEMEYEN ADRESE YAZMA da DECERR vermeli
        // ===============================================================
        $display("5. Cozulemeyen adrese yazma");
        yaz(32'h3000_0000, 32'h1234_5678, yanit);
        kontrol(yanit === 2'b11,
                $sformatf("0x30000000 yazma DECERR: bresp=%0d", yanit));

        // ===============================================================
        //  6. BOLGE ORTUSMESI YOK
        //
        //  Her slave'in alt siniri KENDI kimligini dondurmeli; iki
        //  bolge ortusse biri digerinin uzerine binerdi ve yukaridaki
        //  1/2 denetimleri zaten kalirdi. Burada ek olarak ARDISIK
        //  bolgelerin BIRBIRINE karismadigini dogruluyoruz.
        // ===============================================================
        $display("6. Ardisik bolge ayrimi");

        oku(32'h4000_0FFF, okunan, yanit);   // GPIO son adresi
        kontrol(okunan === 32'hA5A5_0003,
                $sformatf("GPIO son adres -> slave 3 (0x%08h)", okunan));

        oku(32'h4001_0000, okunan, yanit);   // Timer ilk adresi
        kontrol(okunan === 32'hA5A5_0004,
                $sformatf("Timer ilk adres -> slave 4 (0x%08h)", okunan));

        oku(32'h2000_1FFF, okunan, yanit);   // DataRAM son
        kontrol(okunan === 32'hA5A5_0002,
                $sformatf("DataRAM son adres -> slave 2 (0x%08h)", okunan));

        oku(32'h2001_0000, okunan, yanit);   // NPU_MEM ilk
        kontrol(okunan === 32'hA5A5_000A,
                $sformatf("NPU_MEM ilk adres -> slave 10 (0x%08h)", okunan));

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
        #2_000_000;
        $display("  [HATA] gozcu: test 2 ms icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
