`timescale 1ns / 1ps
// =============================================================================
//  npu_tcm_axi_slave.sv
//  Hesaplama motorunun AXI4-Lite islemlerini TCM portlarina baglar.
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN VAR (23 Agustos 2026)
//
//    npu_engine_axi_master'in karsi tarafi. Ikisi arasindaki AXI4-Lite
//    hatlari GERCEK sinyallerdir: dalga formunda gorulur, SVA protokol
//    denetleyicisi baglanabilir, jüri islemleri sayabilir.
//
//    Sartname s.549-554: veri bellekten AXI ile hizlandiriciya cekilir,
//    sonuc yine AXI ile bellege yazilir.
//
//  YONLENDIRME
//
//    okuma  -> TCM Port B  (salt okunur port)
//    yazma  -> TCM Port A  (tek yazan port; disaridan gelen AXI erisimleri
//                           ile mux'lanir, motor onceliklidir)
//
//    Iki fiziksel port kullanilmasi sartnameye aykiri degildir: AXI
//    arayuzu TEKTIR, arkasindaki bellek gerceklemesi cift portludur.
//    "Ayni bellek uzerinde birden fazla master" da yoktur - motor bu
//    arayuzun tek master'idir.
//
//  BEKLEME CEVRIMI YOK
//
//    arready / awready / wready her cevrim yuksektir. AXI4-Lite bekleme
//    cevrimi zorunlu tutmaz. Boylece okuma gecikmesi senkron SRAM ile
//    AYNI kalir (adres N, veri N+1) ve CONV boru hattina yeni asama
//    eklemek gerekmez.
//
//  ADRES DENETIMI
//
//    TCM_WORDS disindaki adresler SLVERR doner. Motorun adres uretimi
//    dogruysa bu hic olusmaz; olusursa npu_engine_axi_master'daki yapiskan
//    hata bayragi yakalar. Sessizce yanlis veri okumaktan iyidir.
// =============================================================================

module npu_tcm_axi_slave #(
    parameter int TCM_WORDS = 7680,
    parameter int ADDR_W    = 13
) (
    input  logic              clk,
    input  logic              rst_n,

    // --- AXI4-Lite Slave ---
    input  logic [31:0]       s_axi_awaddr,
    input  logic              s_axi_awvalid,
    output logic              s_axi_awready,
    input  logic [31:0]       s_axi_wdata,
    input  logic [3:0]        s_axi_wstrb,
    input  logic              s_axi_wvalid,
    output logic              s_axi_wready,
    output logic [1:0]        s_axi_bresp,
    output logic              s_axi_bvalid,
    input  logic              s_axi_bready,

    input  logic [31:0]       s_axi_araddr,
    input  logic              s_axi_arvalid,
    output logic              s_axi_arready,
    output logic [31:0]       s_axi_rdata,
    output logic [1:0]        s_axi_rresp,
    output logic              s_axi_rvalid,
    input  logic              s_axi_rready,

    // --- TCM Port B (salt okunur) ---
    output logic              ram_en_b,
    output logic [ADDR_W-1:0] ram_addr_b,
    input  logic [31:0]       ram_rdata_b,

    // --- TCM Port A yazma istegi (ust seviyede mux'lanir) ---
    output logic              ram_wr_req,
    output logic [3:0]        ram_we_a,
    output logic [ADDR_W-1:0] ram_addr_a,
    output logic [31:0]       ram_wdata_a
);

    // Bayt adresinden kelime adresine
    wire [ADDR_W-1:0] ar_word = s_axi_araddr[ADDR_W+1:2];
    wire [ADDR_W-1:0] aw_word = s_axi_awaddr[ADDR_W+1:2];

    wire ar_gecerli = (s_axi_araddr[31:2] < TCM_WORDS);
    wire aw_gecerli = (s_axi_awaddr[31:2] < TCM_WORDS);

    // -------------------------------------------------------------------------
    // OKUMA - Port B
    //
    // arready her cevrim yuksek. Adres kabul edilen cevrimde Port B'ye
    // verilir, veri bir sonraki cevrimde hazir olur ve rvalid ile sunulur.
    // Bu, senkron SRAM okumasiyla BIREBIR ayni zamanlamadir.
    // -------------------------------------------------------------------------
    assign s_axi_arready = 1'b1;
    assign ram_en_b      = s_axi_arvalid;
    assign ram_addr_b    = ar_word;
    assign s_axi_rdata   = ram_rdata_b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
        end else begin
            // Yeni bir adres kabul edildiyse bir sonraki cevrim veri hazir.
            // Onceki rvalid henuz alinmadiysa (rready dusuk) korunur; ama
            // motorun rready'si hep yuksek oldugu icin bu durum olusmaz.
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= ar_gecerli ? 2'b00 : 2'b10;   // SLVERR
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // YAZMA - Port A
    //
    // AW ve W ayni cevrimde kabul edilir. Yazma istegi ust seviyeye
    // cikarilir; orada AXI slave'inin (dis erisim) istegiyle mux'lanir ve
    // motor onceliklidir.
    // -------------------------------------------------------------------------
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;

    wire yazma_kabul = s_axi_awvalid && s_axi_awready &&
                       s_axi_wvalid  && s_axi_wready;

    assign ram_wr_req  = yazma_kabul && aw_gecerli;
    assign ram_we_a    = s_axi_wstrb;
    assign ram_addr_a  = aw_word;
    assign ram_wdata_a = s_axi_wdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else begin
            if (yazma_kabul) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= aw_gecerli ? 2'b00 : 2'b10;   // SLVERR
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule
