// =============================================================================
//  tb_npu_accelerator.sv
//
//  NEDEN VAR
//    12 Eylul 2026 kapsam analizi sunu gosterdi:
//
//        npu_accelerator     stmt %0,0    <- HICBIR BLOK TESTINDE YOK
//
//    NPU blok testleri yalnizca `npu_compute_engine`'i ornekliyordu:
//        npu_blok      kaynak=[npu_weights_pkg, npu_compute_engine, tb]
//        npu_dogruluk  kaynak=[npu_weights_pkg, npu_compute_engine, tb]
//
//    `npu_accelerator` (335 satir) CSR, TCM, AXI denetleyici ve motoru
//    birbirine baglayan SARMALAYICI katmandir ve yalnizca SISTEM
//    testinde DOLAYLI calisiyordu.
//
//  NE KAPSAR - ve NE KAPSAMAZ
//
//    KAPSAR: dis bellek portundan (mem_*) TCM'e yazma/okuma yolu.
//    Bu yol npu_axi_controller -> tcm_* -> npu_tcm_sram uzerinden
//    gider ve DMA'nin girdi tensorunu yukledigi yoldur.
//
//    KAPSAMAZ: satir 204-209'daki TCM port A hakemliginin MOTOR
//    tarafi. Olculdu ve dogrulandi:
//
//        assign eng_wr_req = axi_ram_wr_req;
//
//    `axi_ram_wr_req` npu_tcm_axi_slave'den gelir; o modul MOTORUN
//    AXI master'ina baglidir (eng_* sinyalleri), dis mem_* portuna
//    DEGIL. Yani `eng_wr_req` yalnizca MOTOR CALISIRKEN yukselir.
//
//    Bu test motoru calistirmadigi icin hakemligin `eng_wr_req=1`
//    dali HIC secilmez. Hata enjeksiyonuyla dogrulandi: o dala
//    uygulanan mutasyon (tcm_wdata_a sifirlanmasi) bu test
//    tarafindan YAKALANMAZ.
//
//    O dalin kapsanmasi icin motorun bir cikarim kosmasi gerekir -
//    yani npu_dogruluk/npu_golden benzeri bir senaryo bu modul
//    seviyesinde kurulmalidir. Acik olarak kayda gecirilmistir
//    (evidence/denetim_20260910/KAPSAM_ANALIZI_20260912.md).
//
//  NE DOGRULAR
//    1. Reset sonrasi irq_o temiz
//    2. TCM'e dis porttan yazilan veri geri okunabiliyor
//    3. Ardisik AXI yazmalari birbirini bozmuyor
//    4. 16 kelimelik blok yazma/okuma butunlugu
//    5. Sinir adresleri (TCM[0] ve TCM[7679]) dogru
//    6. Uzak adresler KENDI yerinde duruyor (adres yolu ayrimi)
//    7. CSR portu bellek portundan BAGIMSIZ
// =============================================================================
`timescale 1ns/1ps

module tb_npu_accelerator;

    localparam int TCM_WORDS = 7680;        // 30 kB / 4

    logic clk = 1'b0, rst_n = 1'b0;
    always #5ns clk = ~clk;

    // --- CSR portu (0x4006_0000) ---
    logic [31:0] r_awaddr;  logic r_awvalid, r_awready;
    logic [31:0] r_wdata;   logic [3:0] r_wstrb; logic r_wvalid, r_wready;
    logic [1:0]  r_bresp;   logic r_bvalid, r_bready;
    logic [31:0] r_araddr;  logic r_arvalid, r_arready;
    logic [31:0] r_rdata;   logic [1:0] r_rresp; logic r_rvalid, r_rready;

    // --- Bellek portu (0x2001_0000) ---
    logic [31:0] m_awaddr;  logic m_awvalid, m_awready;
    logic [31:0] m_wdata;   logic [3:0] m_wstrb; logic m_wvalid, m_wready;
    logic [1:0]  m_bresp;   logic m_bvalid, m_bready;
    logic [31:0] m_araddr;  logic m_arvalid, m_arready;
    logic [31:0] m_rdata;   logic [1:0] m_rresp; logic m_rvalid, m_rready;

    logic irq_o;

    int pass_count = 0, fail_count = 0;

    npu_accelerator #(.TCM_WORDS(TCM_WORDS)) dut (
        .clk(clk), .rst_n(rst_n),
        .reg_awaddr(r_awaddr), .reg_awvalid(r_awvalid), .reg_awready(r_awready),
        .reg_wdata(r_wdata),   .reg_wstrb(r_wstrb),     .reg_wvalid(r_wvalid),
        .reg_wready(r_wready),
        .reg_bresp(r_bresp),   .reg_bvalid(r_bvalid),   .reg_bready(r_bready),
        .reg_araddr(r_araddr), .reg_arvalid(r_arvalid), .reg_arready(r_arready),
        .reg_rdata(r_rdata),   .reg_rresp(r_rresp),     .reg_rvalid(r_rvalid),
        .reg_rready(r_rready),
        .mem_awaddr(m_awaddr), .mem_awvalid(m_awvalid), .mem_awready(m_awready),
        .mem_wdata(m_wdata),   .mem_wstrb(m_wstrb),     .mem_wvalid(m_wvalid),
        .mem_wready(m_wready),
        .mem_bresp(m_bresp),   .mem_bvalid(m_bvalid),   .mem_bready(m_bready),
        .mem_araddr(m_araddr), .mem_arvalid(m_arvalid), .mem_arready(m_arready),
        .mem_rdata(m_rdata),   .mem_rresp(m_rresp),     .mem_rvalid(m_rvalid),
        .mem_rready(m_rready),
        .irq_o(irq_o)
    );

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    // -------------------------------------------------------------------
    //  BELLEK PORTU - yazma
    //
    //  negedge kalibi: RTL READY'yi bir cevrim gec yukseltir ve el
    //  sikisma posedge'inde dusurur (bkz. tb_sram_w_yakalama).
    // -------------------------------------------------------------------
    task automatic mem_yaz(input [31:0] adr, input [31:0] veri);
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
            @(negedge clk); m_bready = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic mem_oku(input [31:0] adr, output logic [31:0] veri);
        int g;
        begin
            @(negedge clk); m_araddr = adr; m_arvalid = 1'b1; m_rready = 1'b1;
            @(negedge clk);
            g = 0;
            while (!m_arready && g < 60) begin @(negedge clk); g++; end
            @(negedge clk); m_arvalid = 1'b0;
            g = 0;
            while (!m_rvalid && g < 60) begin @(negedge clk); g++; end
            veri = m_rdata;
            @(negedge clk); m_rready = 1'b0;
            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------
    //  CSR PORTU
    // -------------------------------------------------------------------
    task automatic csr_oku(input [31:0] adr, output logic [31:0] veri);
        int g;
        begin
            @(negedge clk); r_araddr = adr; r_arvalid = 1'b1; r_rready = 1'b1;
            @(negedge clk);
            g = 0;
            while (!r_arready && g < 60) begin @(negedge clk); g++; end
            @(negedge clk); r_arvalid = 1'b0;
            g = 0;
            while (!r_rvalid && g < 60) begin @(negedge clk); g++; end
            veri = r_rdata;
            @(negedge clk); r_rready = 1'b0;
            @(negedge clk);
        end
    endtask

    // CSR yazma (motoru baslatmak icin gerekli)
    task automatic csr_yaz(input [31:0] adr, input [31:0] veri);
        int g;
        begin
            r_bready = 1'b1;
            fork
                begin
                    @(negedge clk); r_awaddr = adr; r_awvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!r_awready && g < 60) begin @(negedge clk); g++; end
                    @(negedge clk); r_awvalid = 1'b0;
                end
                begin
                    @(negedge clk); r_wdata = veri; r_wstrb = 4'b1111; r_wvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!r_wready && g < 60) begin @(negedge clk); g++; end
                    @(negedge clk); r_wvalid = 1'b0;
                end
            join
            g = 0;
            while (!r_bvalid && g < 60) begin @(negedge clk); g++; end
            @(negedge clk); r_bready = 1'b0;
            @(negedge clk);
        end
    endtask

    logic [31:0] okunan, csr_deger;
    int i, dogru;

    // -------------------------------------------------------------------
    //  HAKEM GOZLEMCISI  (A1 - 13 Eylul 2026)
    //
    //  npu_accelerator satir 206-209'daki hakem:
    //      tcm_*_a = eng_wr_req ? <MOTOR yolu> : <CPU yolu>
    //
    //  Kapsam analizi (KAPSAM_ANALIZI_20260912.md) bu modulun sistem
    //  kosumunda %0,0 statement kapsamina sahip oldugunu, blok
    //  testinin de yalnizca CPU dalini uyardigini gostermisti.
    //  eng_wr_req hic yukselmiyordu -> MOTOR dali olu kaliyordu.
    //
    //  Bu gozlemci her iki dalin da fiilen secildigini SAYAR.
    // -------------------------------------------------------------------
    int motor_dali_sayaci = 0;   // eng_wr_req = 1 -> motor kazandi
    int cpu_dali_sayaci   = 0;   // eng_wr_req = 0 -> CPU yolu gecti
    int stall_sayaci      = 0;   // motor kazanirken AXI denetleyici bastirildi mi
    int veri_yolu_hatasi  = 0;   // hakem YANLIS kaynagi TCM'e verdi

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.eng_wr_req) begin
                motor_dali_sayaci++;
                if (dut.u_npu_axi_ctrl.stall_i) stall_sayaci++;

                // VERI YOLU DENETIMI
                //
                //   Yalnizca "dal secildi" saymak YETMEZ: hakem dali
                //   secip yine de YANLIS kaynagi TCM'e baglayabilir.
                //   Mutasyon denemesi bunu gosterdi - tcm_we_a'yi CPU
                //   yoluna sabitledigimizde sayaclar degismedi ama
                //   motorun yazmasi TCM'e ulasmadi.
                //
                //   Bu yuzden motor kazandigi her cevrimde TCM'in
                //   A portundaki DORT sinyalin de MOTOR kaynagini
                //   tasidigi dogrulanir.
                if (dut.tcm_we_a    !== dut.axi_ram_we_a   ||
                    dut.tcm_addr_a  !== dut.axi_ram_addr_a ||
                    dut.tcm_wdata_a !== dut.axi_ram_wdata_a||
                    dut.tcm_en_a    !== 1'b1)
                    veri_yolu_hatasi++;

            end else if (dut.ram_en_a) begin
                cpu_dali_sayaci++;

                // CPU kazanirken de TCM CPU kaynagini tasimali
                if (dut.tcm_we_a    !== dut.ram_we_a   ||
                    dut.tcm_addr_a  !== dut.ram_addr_a ||
                    dut.tcm_wdata_a !== dut.ram_wdata_a)
                    veri_yolu_hatasi++;
            end
        end
    end

    initial begin
        r_awaddr = 32'h0; r_awvalid = 1'b0;
        r_wdata  = 32'h0; r_wstrb = 4'b0; r_wvalid = 1'b0; r_bready = 1'b0;
        r_araddr = 32'h0; r_arvalid = 1'b0; r_rready = 1'b0;
        m_awaddr = 32'h0; m_awvalid = 1'b0;
        m_wdata  = 32'h0; m_wstrb = 4'b0; m_wvalid = 1'b0; m_bready = 1'b0;
        m_araddr = 32'h0; m_arvalid = 1'b0; m_rready = 1'b0;

        $display("================================================================");
        $display(" NPU ACCELERATOR SARMALAYICI - BLOK TESTI");
        $display("================================================================");
        $display("");
        $display("Bu modul kapsam analizinde %%0 statement gosteriyordu:");
        $display("hicbir blok testinde yoktu, yalniz sistem testinde");
        $display("dolayli calisiyordu.");
        $display("");

        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (6) @(posedge clk);

        // ===============================================================
        //  1. RESET SONRASI TEMIZ MI
        // ===============================================================
        $display("1. Reset sonrasi durum");
        kontrol(irq_o === 1'b0,
                $sformatf("reset sonrasi irq_o bostada (=%0b)", irq_o));

        // ===============================================================
        //  2. TCM'E AXI UZERINDEN YAZ, GERI OKU
        //
        //  Bu, npu_accelerator'un TCM yolunu (204-209) VE
        //  npu_tcm_axi_slave'i birlikte calistirir.
        // ===============================================================
        $display("2. TCM yazma / okuma (bellek portu)");

        mem_yaz(32'h0000_0000, 32'hDEAD_BEEF);
        mem_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'hDEAD_BEEF,
                $sformatf("TCM[0] yazildi ve okundu: 0x%08h", okunan));

        mem_yaz(32'h0000_0004, 32'hCAFE_BABE);
        mem_oku(32'h0000_0004, okunan);
        kontrol(okunan === 32'hCAFE_BABE,
                $sformatf("TCM[1] yazildi ve okundu: 0x%08h", okunan));

        // ===============================================================
        //  3. ONCEKI YAZMA BOZULMADI MI
        //
        //  Hakemlik mantigi yanlis olsa ikinci yazma birincinin
        //  adresine gidebilirdi.
        // ===============================================================
        $display("3. Ardisik yazmalar birbirini bozmuyor");

        mem_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'hDEAD_BEEF,
                $sformatf("TCM[0] hala dogru: 0x%08h (beklenen DEADBEEF)", okunan));

        // ===============================================================
        //  4. COKLU ARDISIK YAZMA
        // ===============================================================
        $display("4. Coklu ardisik yazma (16 kelime)");

        for (i = 0; i < 16; i++)
            mem_yaz(i * 4, 32'h1000_0000 + i);

        dogru = 0;
        for (i = 0; i < 16; i++) begin
            mem_oku(i * 4, okunan);
            if (okunan === (32'h1000_0000 + i)) dogru++;
            else $display("      TCM[%0d] = 0x%08h (beklenen 0x%08h)",
                          i, okunan, 32'h1000_0000 + i);
        end
        kontrol(dogru == 16,
                $sformatf("16/16 kelime dogru yazildi ve okundu (%0d dogru)", dogru));

        // ===============================================================
        //  5. SINIR ADRESLERI
        //
        //  TCM 7680 kelime = 30 kB. Son kelime indeks 7679.
        // ===============================================================
        $display("5. TCM sinir adresleri");

        mem_yaz((TCM_WORDS - 1) * 4, 32'hFEED_FACE);
        mem_oku((TCM_WORDS - 1) * 4, okunan);
        kontrol(okunan === 32'hFEED_FACE,
                $sformatf("TCM son kelime [%0d] = 0x%08h", TCM_WORDS - 1, okunan));

        // Ilk kelime hala dogru mu (son yazma onu bozmadi mi)
        mem_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'h1000_0000,
                $sformatf("son kelime yazmasi TCM[0]'i bozmadi: 0x%08h", okunan));

        // ===============================================================
        //  6. ADRES YOLU GERCEKTEN KULLANILIYOR MU  (hakemlik denetimi)
        //
        //  NEDEN BU DENETIM VAR
        //    Ilk surumde hata enjeksiyonu (npu_tcm_hakem mutasyonu:
        //    tcm_addr_a AXI adresi yerine motor adresini alir) test
        //    tarafindan KACIRILDI.
        //
        //    Sebep: testte motor calismadigi icin ram_addr_a sifirdi;
        //    mutasyon tum yazmalari TCM[0]'a yonlendiriyordu ve test
        //    zaten TCM[0]'i yaziyordu, fark gorunmuyordu.
        //
        //    Cozum: SIFIR OLMAYAN, BIRBIRINDEN UZAK adreslere yazip
        //    her birinin KENDI yerinde durdugunu dogrulamak. Mutasyon
        //    varsa hepsi TCM[0]'a yigilir ve bu denetim KALIR.
        // ===============================================================
        $display("6. Adres yolu ayrimi (hakemlik)");

        // Birbirinden uzak uc adrese FARKLI degerler yaz
        mem_yaz(32'h0000_0100, 32'h1111_1111);   // kelime 64
        mem_yaz(32'h0000_0200, 32'h2222_2222);   // kelime 128
        mem_yaz(32'h0000_0400, 32'h3333_3333);   // kelime 256

        dogru = 0;
        mem_oku(32'h0000_0100, okunan);
        if (okunan === 32'h1111_1111) dogru++;
        else $display("      kelime 64  = 0x%08h (beklenen 11111111)", okunan);

        mem_oku(32'h0000_0200, okunan);
        if (okunan === 32'h2222_2222) dogru++;
        else $display("      kelime 128 = 0x%08h (beklenen 22222222)", okunan);

        mem_oku(32'h0000_0400, okunan);
        if (okunan === 32'h3333_3333) dogru++;
        else $display("      kelime 256 = 0x%08h (beklenen 33333333)", okunan);

        kontrol(dogru == 3,
                $sformatf("3/3 uzak adres KENDI yerinde (%0d dogru) - adres yolu dogru",
                          dogru));

        // ===============================================================
        //  7. CSR PORTU BAGIMSIZ CALISIYOR
        //
        //  Bellek portu trafigi CSR portunu etkilememeli.
        // ===============================================================
        $display("6. CSR portu bagimsizligi");

        csr_oku(32'h0000_0000, csr_deger);
        kontrol(csr_deger !== 32'hxxxx_xxxx,
                $sformatf("CSR[0] okunabiliyor: 0x%08h (X/Z degil)", csr_deger));

        // Bellek trafigi sirasinda CSR yine okunabilmeli
        mem_yaz(32'h0000_0020, 32'hA0A0_A0A0);
        csr_oku(32'h0000_0000, csr_deger);
        kontrol(csr_deger !== 32'hxxxx_xxxx,
                $sformatf("bellek trafigi sonrasi CSR hala okunuyor: 0x%08h", csr_deger));

        mem_oku(32'h0000_0020, okunan);
        kontrol(okunan === 32'hA0A0_A0A0,
                $sformatf("CSR okumasi bellek verisini bozmadi: 0x%08h", okunan));

        // ===============================================================
        //  7. HAKEMLIGIN MOTOR DALI  (A1 - 13 Eylul 2026)
        //
        //  NEDEN BU TEST VAR
        //    Kapsam analizi npu_accelerator'un hakemlik mantiginda
        //    (satir 206-209) MOTOR dalinin hicbir testte uyarilmadigini
        //    gosterdi. CPU dali yukaridaki testlerle calisiyordu ama
        //    eng_wr_req hic 1 olmuyordu.
        //
        //  NASIL UYANDIRILIYOR
        //    NPU CSR uzerinden baslatilir (REG_CTRL bit0 = start).
        //    Hesaplama motoru sonucunu TCM'e yazmak istediginde
        //    npu_tcm_axi_slave uzerinden eng_wr_req yukselir; hakem
        //    TCM A portunu motora verir ve CPU yolunu bloklar.
        //
        //  NE DOGRULANIR
        //    1. Motor dali GERCEKTEN seciliyor (sayac > 0)
        //    2. Motor kazanirken hesaplama stall ediliyor (veri yarisi yok)
        //    3. CPU dali da hala calisiyor (iki dal birlikte yasiyor)
        //    4. Motor calismasi CPU verisini bozmuyor
        // ===============================================================
        $display("7. Hakemligin MOTOR dali (A1)");

        // Once bilinen bir deger yaz - motor sonrasi bozulmadigini görelim
        mem_yaz(32'h0000_0040, 32'h5A5A_1234);

        // Giris/cikis adreslerini kur ve motoru baslat
        csr_yaz(32'h08, 32'h0000_0000);   // REG_IN_ADDR
        csr_yaz(32'h0C, 32'h0000_0100);   // REG_OUT_ADDR
        // REG_CTRL bit4 = weights_ready (yapiskan), bit0 = start
        // npu_csr satir 76: start_o = reg_start && reg_weights_ready
        // Yalnizca start yazmak YETMEZ - motor calismaz.
        csr_yaz(32'h00, 32'h0000_0010);   // once weights_ready
        csr_yaz(32'h00, 32'h0000_0011);   // weights_ready + start

        // Motorun TCM'e yazma firsati bulmasi icin bekle
        // Tam cikarim ~85.587 cevrim surer (tb_npu_audio olcumu).
        // 120.000 cevrim WRITE_OUT asamasina ulasmak icin yeterli pay birakir.
        repeat (120000) @(posedge clk);

        $display("    motor dali secildi : %0d cevrim", motor_dali_sayaci);
        $display("    CPU dali secildi   : %0d cevrim", cpu_dali_sayaci);
        $display("    motor kazanirken stall: %0d cevrim", stall_sayaci);

        $display("    veri yolu hatasi   : %0d cevrim", veri_yolu_hatasi);

        kontrol(motor_dali_sayaci > 0,
                $sformatf("hakemligin MOTOR dali uyarildi (%0d cevrim)",
                          motor_dali_sayaci));

        kontrol(veri_yolu_hatasi == 0,
                $sformatf("hakem her cevrimde DOGRU kaynagi TCM'e bagladi (%0d hata)",
                          veri_yolu_hatasi));

        kontrol(cpu_dali_sayaci > 0,
                $sformatf("hakemligin CPU dali da calisiyor (%0d cevrim)",
                          cpu_dali_sayaci));

        // Motor kazandigi HER cevrimde hesaplama durdurulmali (satir 286)
        kontrol(stall_sayaci == motor_dali_sayaci,
                $sformatf("motor kazanirken hesaplama her cevrim durduruldu (%0d/%0d)",
                          stall_sayaci, motor_dali_sayaci));

        // Motor trafigi CPU verisini bozmamali
        mem_oku(32'h0000_0040, okunan);
        kontrol(okunan === 32'h5A5A_1234,
                $sformatf("motor calismasi CPU verisini bozmadi: 0x%08h", okunan));

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
        #8_000_000;
        $display("  [HATA] gozcu: test 5 ms icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
