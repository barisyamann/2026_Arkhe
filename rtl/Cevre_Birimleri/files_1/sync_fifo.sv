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
    // Durum lojiği — YAZMAÇLI BAYRAKLAR (25 Ağustos 2026)
    //
    // ÖNCEKİ HÂLİ VE NEDEN DEĞİŞTİ
    //
    //     assign o_level = wr_ptr_r - rd_ptr_r;          // 9 bit çıkarma
    //     assign o_full  = (o_level == DEPTH[PTR_W:0]);  // 9 bit karşılaştırma
    //     ...
    //     if (i_wr_en && !o_full) mem[...] <= i_wr_data; // yazma izni
    //
    // Bu zincir şu yolu üretiyordu:
    //     rd_ptr_r → çıkarma → karşılaştırma → o_full → 256×8 = 2048
    //     flip-flop'un yazma izni
    //
    // 9. ASIC koşumunda ss köşesinin EN KÖTÜ YOLU tam olarak buydu:
    //     u_uart2.u_rx_fifo.rd_ptr_r[0] → u_uart2.u_rx_fifo.mem[25][0]
    //     98 hücre derinliğinde, slack -8,026 ns
    // En kötü sekiz bitiş noktasının tamamı bu FIFO'nun mem[...] hücreleriydi.
    //
    // ÇÖZÜM — İKİ AŞAMALI
    //
    // 1) Dolu/boş tespiti ÇIKARICIDAN AYRILDI. İşaretçiler fazladan bir
    //    sarma (wrap) biti taşıdığı ve DEPTH ikinin kuvveti olduğu için
    //    dolu durumu doğrudan karşılaştırmayla bulunabilir:
    //        dolu  = sarma bitleri FARKLI  ve  alt bitler AYNI
    //        boş   = işaretçiler tamamen AYNI
    //    Böylece 9 bitlik çıkarıcı kontrol yolundan çıkar.
    //
    // 2) Bayraklar YAZMAÇLANDI. Sonraki çevrimin işaretçi değerlerinden
    //    hesaplanıp bir yazmaca alınır. Yazma izni artık kombinasyonel
    //    zincirden değil, bir yazmaç çıkışından gelir; yol tamamen kopar.
    //
    // o_level yalnızca DURUM/İZLEME içindir ve kontrol yolunu beslemez —
    // tek doğruluk kaynağı işaretçilerdir, ayrı bir sayaçla ayrışamaz.
    //
    // DAVRANIŞ AYNIDIR: full_n/empty_n sonraki çevrimin işaretçilerinden
    // hesaplandığı için bayraklar bir çevrim geç kalmaz.
    // -------------------------------------------------------------------------

    // DEPTH ikinin kuvveti olmalıdır — sarma biti karşılaştırması bunu varsayar.
    if (DEPTH != (1 << PTR_W))
        $error("sync_fifo: DEPTH ikinin kuvveti olmali (DEPTH=%0d, PTR_W=%0d)",
               DEPTH, PTR_W);

    logic           full_r;
    logic           empty_r;
    logic [PTR_W:0] wr_ptr_n;
    logic [PTR_W:0] rd_ptr_n;
    logic           full_n;
    logic           empty_n;

    // Gerçekleşen işlemler — yazmaçlı bayraklar kullanılır
    wire yaz_ok = i_wr_en && !full_r;
    wire oku_ok = i_rd_en && !empty_r;

    // Sonraki çevrimin işaretçi değerleri
    assign wr_ptr_n = wr_ptr_r + {{PTR_W{1'b0}}, yaz_ok};
    assign rd_ptr_n = rd_ptr_r + {{PTR_W{1'b0}}, oku_ok};

    assign full_n  = (wr_ptr_n[PTR_W]     != rd_ptr_n[PTR_W]) &&
                     (wr_ptr_n[PTR_W-1:0] == rd_ptr_n[PTR_W-1:0]);
    assign empty_n = (wr_ptr_n == rd_ptr_n);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            full_r  <= 1'b0;
            empty_r <= 1'b1;
        end else begin
            full_r  <= full_n;
            empty_r <= empty_n;
        end
    end

    assign o_full  = full_r;
    assign o_empty = empty_r;
    assign o_level = wr_ptr_r - rd_ptr_r;   // yalnizca izleme, kontrol yolunu beslemez

    // -------------------------------------------------------------------------
    // Yazma işlemi — RAM (BRAM çıkarımı için reset içermez)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (yaz_ok) begin
            mem[wr_ptr_r[PTR_W-1:0]] <= i_wr_data;
        end
    end

    // Yazma pointer — reset'li
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_r <= '0;
        end else if (yaz_ok) begin
            wr_ptr_r <= wr_ptr_r + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Okuma işlemi — RAM (BRAM çıkarımı için reset içermez)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (oku_ok) begin
            o_rd_data <= mem[rd_ptr_r[PTR_W-1:0]];
        end
    end

    // Okuma pointer — reset'li
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr_r <= '0;
        end else if (oku_ok) begin
            rd_ptr_r <= rd_ptr_r + 1;
        end
    end

endmodule
