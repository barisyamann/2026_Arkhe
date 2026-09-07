`timescale 1ns / 1ps
// =============================================================================
//  npu_engine_axi_master.sv
//  Hesaplama motorunun bellek erisimlerini AXI4-Lite islemlerine cevirir.
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN VAR (23 Agustos 2026)
//
//    Sartname s.549-554 acikca soyle diyor:
//
//      "...hizlandiriciya ozel bellek alanina yonlendirilmeli, BELLEKTEN AXI
//       ARAYUZU UZERINDEN hizlandirici uzerine cekilerek bu hizlandirici
//       uzerinde islenmeli ve kodlanmis veriler yine AXI ARAYUZU UZERINDEN
//       istenen bellek alanina geri yazilmalidir."
//
//    Onceki tasarimda Compute Engine, TCM'nin Port B'sine DOGRUDAN SRAM
//    sinyalleriyle (mem_en_b / mem_addr_b / mem_rdata_b) bagliydi; sonuc
//    yazimlari da Port A'ya dogrudan mux'lanıyordu. Yani hizlandiricinin
//    kendi veri trafigi AXI degildi - yalnizca DIS erisimler AXI'ydi.
//
//    Sartnamedeki su cumle bunu bir sure mugak birakti:
//
//      "YZ hizlandirici kendi bellek bolgesine sahip olacagi icin SoC'de
//       ayni bellek uzerinde birden fazla master bulunmasina gerek yoktur."
//
//    Ama bu cumle "AXI kullanma" demiyor; "IKINCI bir master gerekmez"
//    diyor. Hizlandiricinin kendisi master olabilir - olmamasi gereken sey
//    ayni bellek uzerinde ikinci bir master. Bu modulle motor tek master
//    olur ve her iki cumle de saglanir.
//
//  TASARIM - NEDEN TIMING'I BOZMUYOR
//
//    Bu bir "her cevrim bir islem" AXI4-Lite master'idir:
//
//      okuma  : arvalid adres cevriminde yukselir, slave AYNI cevrimde
//               arready verir, veri BIR SONRAKI cevrimde rvalid ile gelir.
//      yazma  : awvalid + wvalid ayni cevrimde, slave ikisini de kabul
//               eder, bvalid bir sonraki cevrimde doner.
//
//    Senkron SRAM okumasi da tam olarak boyle davranir: adres N'de,
//    veri N+1'de. Yani AXI'ye gecis motorun gordugu GECIKMEYI DEGISTIRMEZ
//    ve CONV boru hattina yeni bir asama eklemek gerekmez.
//
//    AXI4-Lite bekleme cevrimi ZORUNLU TUTMAZ; slave'in her cevrim ready
//    vermesi tamamen gecerlidir. Bu yuzden protokol uyumu ile basarim
//    arasinda takas yok.
//
//  DIKKAT - YAZMA YANITI
//
//    Motor sonuc yazarken (WRITE_OUT_0..3) her cevrim bir kelime yazar ve
//    yanit beklemez. Bu master B kanalini kendisi yutar (bready hep 1) ve
//    yazma hatasini bresp_err_o ile disariya bildirir. Boylece motorun
//    FSM'ine dokunmadan protokol tam kalir.
// =============================================================================

module npu_engine_axi_master #(
    parameter int ADDR_W = 13          // TCM kelime adresi genisligi
) (
    input  logic              clk,
    input  logic              rst_n,

    // --- Hesaplama motorunun basit bellek portu ---
    input  logic              eng_en,
    input  logic [3:0]        eng_we,
    input  logic [ADDR_W-1:0] eng_addr,
    input  logic [31:0]       eng_wdata,
    output logic [31:0]       eng_rdata,   // kombinasyonel

    // --- AXI4-Lite Master ---
    output logic [31:0]       m_axi_awaddr,
    output logic              m_axi_awvalid,
    input  logic              m_axi_awready,
    output logic [31:0]       m_axi_wdata,
    output logic [3:0]        m_axi_wstrb,
    output logic              m_axi_wvalid,
    input  logic              m_axi_wready,
    input  logic [1:0]        m_axi_bresp,
    input  logic              m_axi_bvalid,
    output logic              m_axi_bready,

    output logic [31:0]       m_axi_araddr,
    output logic              m_axi_arvalid,
    input  logic              m_axi_arready,
    input  logic [31:0]       m_axi_rdata,
    input  logic [1:0]        m_axi_rresp,
    input  logic              m_axi_rvalid,
    output logic              m_axi_rready,

    // --- Hata bildirimi (SLVERR/DECERR yakalanirsa yapiskan) ---
    output logic              bresp_err_o,
    output logic              rresp_err_o
);

    // -------------------------------------------------------------------------
    // Adres cevrimi
    //
    // Motor KELIME adresi verir (13 bit). AXI BAYT adresi bekler, bu yuzden
    // iki bit sola kaydiriliyor. TCM 7680 kelime = 30 kB, yani 15 bitlik
    // bayt adresi yeterli; ust bitler sifir.
    // -------------------------------------------------------------------------
    wire [31:0] bayt_adres = {17'b0, eng_addr, 2'b00};

    wire yazma = eng_en && (eng_we != 4'b0);
    wire okuma = eng_en && (eng_we == 4'b0);

    // -------------------------------------------------------------------------
    // Okuma kanali
    //
    // Motor adresi kombinasyonel olarak surer; arvalid de kombinasyoneldir.
    // Slave her cevrim arready verdigi icin el sikisma ayni cevrimde biter.
    // -------------------------------------------------------------------------
    assign m_axi_araddr  = bayt_adres;
    assign m_axi_arvalid = okuma;
    assign m_axi_rready  = 1'b1;          // motor veriyi her zaman alabilir

    // -------------------------------------------------------------------------
    // OKUNAN VERI KOMBINASYONEL GECER - YAZMACLANMAZ
    //
    // Ilk yazimda burada bir yazmac vardi ve sistem testleri dustu: NPU
    // sinif 0 (SILENCE) veriyordu, yani sifir/bayat veri okuyordu.
    //
    // Sebep: yazmac fazladan BIR CEVRIM gecikme ekliyordu.
    //   adres N -> TCM cikisi N+1 -> yazmac N+1 sonu -> motor N+2'de gorur
    // Oysa motorun boru hatti veriyi N+1'de bekler (senkron SRAM davranisi).
    //
    // Slave'in s_axi_rdata'si zaten TCM'nin YAZMACLI cikisindan geliyor,
    // yani burada ikinci bir yazmac gereksiz. Kombinasyonel gecis, AXI'ye
    // gecmeden onceki zamanlamayi BIREBIR korur.
    //
    // Kritik yol acisindan da sorun degil: CONV_MAC zaten bu veriyi kendi
    // rdata_q yazmacina aliyor (23 Agustos boru hatti duzeltmesi).
    // -------------------------------------------------------------------------
    assign eng_rdata = m_axi_rdata;

    // -------------------------------------------------------------------------
    // Yazma kanali
    //
    // AW ve W ayni cevrimde surulur. AXI4-Lite bunu gerektirmez ama izin
    // verir ve slave'imiz ikisini de her cevrim kabul eder.
    // -------------------------------------------------------------------------
    assign m_axi_awaddr  = bayt_adres;
    assign m_axi_awvalid = yazma;
    assign m_axi_wdata   = eng_wdata;
    assign m_axi_wstrb   = eng_we;
    assign m_axi_wvalid  = yazma;
    assign m_axi_bready  = 1'b1;          // yanitlari yut

    // -------------------------------------------------------------------------
    // Hata bayraklari - yapiskan, yalnizca reset temizler.
    //
    // Motorun FSM'i yaniti beklemedigi icin hata onu durduramaz; bunun
    // yerine disariya bildirilir ve sistem testinde denetlenebilir.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bresp_err_o <= 1'b0;
            rresp_err_o <= 1'b0;
        end else begin
            if (m_axi_bvalid && m_axi_bready && m_axi_bresp != 2'b00)
                bresp_err_o <= 1'b1;
            if (m_axi_rvalid && m_axi_rready && m_axi_rresp != 2'b00)
                rresp_err_o <= 1'b1;
        end
    end

endmodule
