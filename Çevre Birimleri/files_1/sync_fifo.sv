// =============================================================================
// sync_fifo.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - Senkron FIFO
//
// Parametreli, senkron, ilk giren ilk çıkar bellek yapısı.
// UART Stream alıcı tampon belleği olarak kullanılır.
// =============================================================================

module sync_fifo #(
    parameter int DATA_W = 8,             // Bit cinsinden veri genişliği
    parameter int DEPTH  = 256,           // FIFO derinliği (girdi sayısı)
    parameter int PTR_W  = $clog2(DEPTH)  // İşaretçi genişliği
)(
    input  logic              clk,
    input  logic              rst_n,

    // Yazma arayüzü
    input  logic              i_wr_en,    // Yazma etkinleştir
    input  logic [DATA_W-1:0] i_wr_data, // Yazılacak veri

    // Okuma arayüzü
    input  logic              i_rd_en,   // Okuma etkinleştir
    output logic [DATA_W-1:0] o_rd_data, // Okunan veri

    // Durum sinyalleri
    output logic              o_full,    // FIFO dolu
    output logic              o_empty,   // FIFO boş
    output logic [PTR_W:0]    o_level    // Mevcut dolu sayısı
);

    // -------------------------------------------------------------------------
    // Bellek dizisi
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // İşaretçiler (fazladan bit taşma tespiti için)
    // -------------------------------------------------------------------------
    logic [PTR_W:0] wr_ptr_r;
    logic [PTR_W:0] rd_ptr_r;

    // -------------------------------------------------------------------------
    // Durum lojiği
    // -------------------------------------------------------------------------
    assign o_full  = (o_level == DEPTH[PTR_W:0]);
    assign o_empty = (o_level == '0);
    assign o_level = wr_ptr_r - rd_ptr_r;

    // -------------------------------------------------------------------------
    // Yazma işlemi
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_r <= '0;
        end else if (i_wr_en && !o_full) begin
            mem[wr_ptr_r[PTR_W-1:0]] <= i_wr_data;
            wr_ptr_r                 <= wr_ptr_r + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Okuma işlemi (senkron çıkış)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr_r <= '0;
            o_rd_data<= '0;
        end else if (i_rd_en && !o_empty) begin
            o_rd_data <= mem[rd_ptr_r[PTR_W-1:0]];
            rd_ptr_r  <= rd_ptr_r + 1;
        end
    end

endmodule
