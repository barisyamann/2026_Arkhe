// =============================================================================
// uart_stream_peripheral.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - UART Stream Çevre Birimi
//
// YZ hızlandırıcısına veri akışı sağlamak için kullanılır.
// Şartname gereği:
//   - Gelen UART verisi RX FIFO'ya yazılır
//   - CPU AXI4-Lite üzerinden FIFO'yu okur ve YZ belleğine aktarır
//   - FIFO eşiği aşılınca kesme üretir
//
// Yazmaç Haritası:
//   0x00  UART_CPB          Clock per bit (RW)
//   0x04  UART_STP          Stop bit konfigürasyonu (RW)
//   0x08  UART_RDR          Alım veri yazmacı - FIFO çıkışı (RO)
//   0x0C  UART_TDR          Gönderim veri yazmacı (RW)
//   0x10  UART_CFG          Konfigürasyon (RW)
//   0x14  UARTS_FIFO_LEVEL  RX FIFO doluluk seviyesi (RO)
//   0x18  UARTS_FIFO_CLR    FIFO temizleme (WO)
//   0x1C  UARTS_IRQ_EN      Kesme etkinleştirme (RW)
//
// FIFO Derinliği: uart_pkg::STREAM_FIFO_DEPTH (varsayılan 256 bayt)
// =============================================================================

module uart_stream_peripheral
    import uart_pkg::*;
#(
    parameter int SYS_CLK_HZ    = 50_000_000,
    parameter int DEFAULT_BAUD  = 115_200,
    parameter int FIFO_DEPTH    = STREAM_FIFO_DEPTH,
    parameter int FIFO_PTR_W    = $clog2(FIFO_DEPTH)
)(
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------
    // AXI4-Lite Slave Arayüzü (konfigürasyon ve veri okuma)
    // -------------------------------------------------------------------
    input  logic [AXI_ADDR_W-1:0] s_axil_awaddr,
    input  logic                  s_axil_awvalid,
    output logic                  s_axil_awready,

    input  logic [AXI_DATA_W-1:0] s_axil_wdata,
    input  logic [3:0]            s_axil_wstrb,
    input  logic                  s_axil_wvalid,
    output logic                  s_axil_wready,

    output logic [1:0]            s_axil_bresp,
    output logic                  s_axil_bvalid,
    input  logic                  s_axil_bready,

    input  logic [AXI_ADDR_W-1:0] s_axil_araddr,
    input  logic                  s_axil_arvalid,
    output logic                  s_axil_arready,

    output logic [AXI_DATA_W-1:0] s_axil_rdata,
    output logic [1:0]            s_axil_rresp,
    output logic                  s_axil_rvalid,
    input  logic                  s_axil_rready,

    // -------------------------------------------------------------------
    // Fiziksel UART hatları
    // -------------------------------------------------------------------
    input  logic uart_rxd,
    output logic uart_txd,

    // -------------------------------------------------------------------
    // Durum ve kesme çıkışları
    // -------------------------------------------------------------------
    output logic uart_stream_irq,   // FIFO eşiği veya TX tamamlandı kesmesi
    output logic fifo_empty,        // FIFO boş (YZ hızlandırıcısı için)
    output logic fifo_full          // FIFO dolu (akış kontrolü için)
);

    // =========================================================================
    // Yazmaç tanımları
    // =========================================================================
    logic [31:0]          reg_cpb_r;
    logic [31:0]          reg_stp_r;
    logic [7:0]           reg_tdr_r;
    logic [2:0]           reg_cfg_r;
    logic [31:0]          reg_irq_en_r;   // Kesme etkinleştirme maskesi

    localparam logic [31:0] DEF_CPB = SYS_CLK_HZ / DEFAULT_BAUD;

    // =========================================================================
    // IRQ_EN bit alanları
    // =========================================================================
    localparam int IRQ_RX_DONE    = 0; // Her alım kesmesi
    localparam int IRQ_FIFO_HALF  = 1; // FIFO yarı doluyken kesme
    localparam int IRQ_FIFO_FULL  = 2; // FIFO doluyken kesme
    localparam int IRQ_TX_DONE    = 3; // TX tamamlandı kesmesi
    localparam int IRQ_FRAME_ERR  = 4; // Çerçeve hatası kesmesi

    // =========================================================================
    // TX alt modülü
    // =========================================================================
    logic tx_start_r;
    logic tx_done_w;
    logic tx_busy_w;

    uart_tx u_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_cpb      (reg_cpb_r),
        .i_stp      (reg_stp_r[1:0]),
        .i_data     (reg_tdr_r),
        .i_tx_start (tx_start_r),
        .o_tx       (uart_txd),
        .o_tx_busy  (tx_busy_w),
        .o_tx_done  (tx_done_w)
    );

    // =========================================================================
    // RX alt modülü
    // =========================================================================
    logic       rx_done_w;
    logic [7:0] rx_data_w;
    logic       rx_frame_err_w;

    uart_rx u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_cpb      (reg_cpb_r),
        .i_rx       (uart_rxd),
        .o_data     (rx_data_w),
        .o_rx_done  (rx_done_w),
        .o_rx_busy  (/* bağlantısız */),
        .o_frame_err(rx_frame_err_w)
    );

    // =========================================================================
    // RX FIFO - Alınan veriler burada birikir
    // =========================================================================
    logic              fifo_wr_en;
    logic              fifo_rd_en;
    logic [7:0]        fifo_rd_data;
    logic [FIFO_PTR_W:0] fifo_level;
    logic              fifo_empty_w;
    logic              fifo_full_w;
    logic              fifo_clr_r;

    // FIFO'ya yazma: her başarılı RX alımında
    assign fifo_wr_en = rx_done_w && !fifo_full_w;

    sync_fifo #(
        .DATA_W (8),
        .DEPTH  (FIFO_DEPTH)
    ) u_rx_fifo (
        .clk      (clk),
        .rst_n    (rst_n & ~fifo_clr_r), // Yazılımdan temizleme desteği
        .i_wr_en  (fifo_wr_en),
        .i_wr_data(rx_data_w),
        .i_rd_en  (fifo_rd_en),
        .o_rd_data(fifo_rd_data),
        .o_full   (fifo_full_w),
        .o_empty  (fifo_empty_w),
        .o_level  (fifo_level)
    );

    assign fifo_empty = fifo_empty_w;
    assign fifo_full  = fifo_full_w;


    // =========================================================================
    // Kesme üretimi
    // =========================================================================
    logic irq_rx_done_s;
    logic irq_fifo_half_s;
    logic irq_fifo_full_s;
    logic irq_tx_done_s;
    logic irq_frame_err_s;

    assign irq_rx_done_s   = reg_irq_en_r[IRQ_RX_DONE]   & rx_done_w;
    assign irq_fifo_half_s = reg_irq_en_r[IRQ_FIFO_HALF]  &
                             (fifo_level >= (FIFO_DEPTH / 2));
    assign irq_fifo_full_s = reg_irq_en_r[IRQ_FIFO_FULL]  & fifo_full_w;
    assign irq_tx_done_s   = reg_irq_en_r[IRQ_TX_DONE]    & tx_done_w;
    assign irq_frame_err_s = reg_irq_en_r[IRQ_FRAME_ERR]  & rx_frame_err_w;

    assign uart_stream_irq = irq_rx_done_s  | irq_fifo_half_s |
                             irq_fifo_full_s| irq_tx_done_s   |
                             irq_frame_err_s;

    // =========================================================================
    // TX tetikleme
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_start_r <= 1'b0;
        else begin
            tx_start_r <= 1'b0;
            if (reg_cfg_r[CFG_TX_EN] && !tx_busy_w)
                tx_start_r <= 1'b1;
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - Yazma Kanalı
    // =========================================================================
    logic aw_active_r;
    logic w_active_r;
    logic [AXI_ADDR_W-1:0] aw_addr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_active_r    <= 1'b0;
            w_active_r     <= 1'b0;
            aw_addr_r      <= '0;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= AXI_RESP_OKAY;
            reg_cpb_r      <= DEF_CPB;
            reg_stp_r      <= '0;
            reg_tdr_r      <= '0;
            reg_cfg_r      <= '0;
            reg_irq_en_r   <= '0;
            fifo_clr_r     <= 1'b0;
        end else begin
            fifo_clr_r <= 1'b0; // FIFO temizleme tek saat darbesi

            // Donanım geri bildirimleri ile CFG yazmacının güncellenmesi
            if (rx_done_w)
                reg_cfg_r[CFG_RX_DONE] <= 1'b1;
            if (tx_done_w) begin
                reg_cfg_r[CFG_TX_DONE] <= 1'b1;
                reg_cfg_r[CFG_TX_EN]   <= 1'b0;
            end

            // Yazma adresi handshake (el sıkışması)
            if (s_axil_awvalid && s_axil_awready) begin
                aw_active_r    <= 1'b1;
                aw_addr_r      <= s_axil_awaddr;
                s_axil_awready <= 1'b0;
            end else if (!aw_active_r)
                s_axil_awready <= s_axil_awvalid;

            // Yazma verisi handshake (el sıkışması)
            if (s_axil_wvalid && s_axil_wready) begin
                w_active_r    <= 1'b1;
                s_axil_wready <= 1'b0;
            end else if (!w_active_r)
                s_axil_wready <= s_axil_wvalid;

            // Yazmaçlara yazma
            if (aw_active_r && w_active_r && !s_axil_bvalid) begin
                aw_active_r   <= 1'b0;
                w_active_r    <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= AXI_RESP_OKAY;

                unique case (aw_addr_r[7:0])
                    UART_CPB_OFFSET: reg_cpb_r <= s_axil_wdata;

                    UART_STP_OFFSET: reg_stp_r <= s_axil_wdata;

                    UART_TDR_OFFSET: reg_tdr_r <= s_axil_wdata[7:0];

                    UART_CFG_OFFSET: begin
                        if (s_axil_wdata[CFG_TX_EN])
                            reg_cfg_r[CFG_TX_EN]  <= 1'b1;
                        // Donanım o an set etmiyorsa yazılımın (0 yazarak) temizlemesine izin ver
                        if (!s_axil_wdata[CFG_RX_DONE] && !rx_done_w)
                            reg_cfg_r[CFG_RX_DONE] <= 1'b0;
                        if (!s_axil_wdata[CFG_TX_DONE] && !tx_done_w)
                            reg_cfg_r[CFG_TX_DONE] <= 1'b0;
                    end

                    UARTS_FIFO_CLR_OFFSET: begin
                        // Bit 0 yazılınca FIFO sıfırla
                        if (s_axil_wdata[0]) fifo_clr_r <= 1'b1;
                    end

                    UARTS_IRQ_EN_OFFSET: reg_irq_en_r <= s_axil_wdata;

                    default: s_axil_bresp <= AXI_RESP_SLVERR;
                endcase
            end

            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - Okuma Kanalı
    // =========================================================================
    // UART_RDR okunduğunda FIFO'dan bir bayt al
    assign fifo_rd_en = s_axil_arvalid && !s_axil_rvalid &&
                        (s_axil_araddr[7:0] == UART_RDR_OFFSET) &&
                        !fifo_empty_w;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= AXI_RESP_OKAY;
        end else begin
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= AXI_RESP_OKAY;

                unique case (s_axil_araddr[7:0])
                    UART_CPB_OFFSET:         s_axil_rdata <= reg_cpb_r;
                    UART_STP_OFFSET:         s_axil_rdata <= reg_stp_r;
                    UART_RDR_OFFSET:         s_axil_rdata <= {24'b0, fifo_rd_data};
                    UART_TDR_OFFSET:         s_axil_rdata <= {24'b0, reg_tdr_r};
                    UART_CFG_OFFSET:         s_axil_rdata <= {29'b0, reg_cfg_r};
                    UARTS_FIFO_LEVEL_OFFSET: s_axil_rdata <= {{(32-FIFO_PTR_W-1){1'b0}},
                                                               fifo_level};
                    UARTS_IRQ_EN_OFFSET:     s_axil_rdata <= reg_irq_en_r;
                    default: begin
                        s_axil_rdata <= '0;
                        s_axil_rresp <= AXI_RESP_SLVERR;
                    end
                endcase
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;
        end
    end

endmodule
