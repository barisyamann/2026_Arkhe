// =============================================================================
// uart_tx.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - UART Verici Modülü
//
// Özellikler:
//   - Programlanabilir baud hızı (sistem_saati / CPB)
//   - 8 bit veri, LSB önce
//   - 1 / 1.5 / 2 stop bit desteği (şartname EK-2)
//   - 1 start bit
// =============================================================================

module uart_tx
    import uart_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Baud rate kontrolü
    input  logic [31:0] i_cpb,         // Clocks Per Bit
    input  logic [1:0]  i_stp,         // Stop bit konfigürasyonu

    // Veri arayüzü
    input  logic [7:0]  i_data,        // Gönderilecek veri
    input  logic        i_tx_start,    // Gönderim başlat (1 saat darbesi)

    // TX çıkışları
    output logic        o_tx,          // Seri çıkış
    output logic        o_tx_busy,     // TX meşgul bayrağı
    output logic        o_tx_done      // Gönderim tamamlandı (1 saat darbesi)
);

    // -------------------------------------------------------------------------
    // Durum makinesi tanımları
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE    = 3'd0,
        ST_START   = 3'd1,
        ST_DATA    = 3'd2,
        ST_STOP1   = 3'd3,
        ST_STOP15  = 3'd4, // 1.5 stop bit için yarım bit ek bekleme
        ST_STOP2   = 3'd5
    } tx_fsm_t;

    tx_fsm_t state_r, state_nxt;

    // -------------------------------------------------------------------------
    // İç sinyaller
    // -------------------------------------------------------------------------
    logic [31:0] clk_cnt_r;
    logic [2:0]  bit_cnt_r;
    logic [7:0]  shift_r;
    logic [31:0] half_cpb;

    assign half_cpb = (i_cpb >> 1); // Yarım bit süresi

    // -------------------------------------------------------------------------
    // Durum geçişi ve çıkış lojiği
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r   <= ST_IDLE;
            clk_cnt_r <= '0;
            bit_cnt_r <= '0;
            shift_r   <= '0;
            o_tx      <= 1'b1;   // Hat hareketsiz hali HIGH
            o_tx_busy <= 1'b0;
            o_tx_done <= 1'b0;
        end else begin
            o_tx_done <= 1'b0;   // Varsayılan: 0

            unique case (state_r)
                // -----------------------------------------------------------------
                ST_IDLE: begin
                    o_tx      <= 1'b1;
                    o_tx_busy <= 1'b0;
                    clk_cnt_r <= '0;
                    bit_cnt_r <= '0;

                    if (i_tx_start) begin
                        shift_r   <= i_data;
                        o_tx_busy <= 1'b1;
                        state_r   <= ST_START;
                    end
                end

                // -----------------------------------------------------------------
                ST_START: begin
                    o_tx <= 1'b0; // Başlangıç biti

                    if (clk_cnt_r >= i_cpb - 1) begin
                        clk_cnt_r <= '0;
                        bit_cnt_r <= '0;
                        state_r   <= ST_DATA;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                // -----------------------------------------------------------------
                ST_DATA: begin
                    o_tx <= shift_r[0]; // LSB önce

                    if (clk_cnt_r >= i_cpb - 1) begin
                        clk_cnt_r <= '0;
                        shift_r   <= {1'b0, shift_r[7:1]}; // Sağa kaydır

                        if (bit_cnt_r == 3'd7) begin
                            bit_cnt_r <= '0;
                            state_r   <= ST_STOP1;
                        end else begin
                            bit_cnt_r <= bit_cnt_r + 1;
                        end
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                // -----------------------------------------------------------------
                ST_STOP1: begin
                    o_tx <= 1'b1; // Durdurma biti HIGH

                    if (clk_cnt_r >= i_cpb - 1) begin
                        clk_cnt_r <= '0;
                        unique case (i_stp)
                            STP_1: begin          // 1 stop bit
                                o_tx_done <= 1'b1;
                                state_r   <= ST_IDLE;
                            end
                            STP_1_5: begin        // 1.5 stop bit
                                state_r <= ST_STOP15;
                            end
                            default: begin        // 2 stop bit (2'b10 veya 2'b11)
                                state_r <= ST_STOP2;
                            end
                        endcase
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                // -----------------------------------------------------------------
                ST_STOP15: begin
                    o_tx <= 1'b1; // Yarım bit ek bekleme

                    if (clk_cnt_r >= half_cpb - 1) begin
                        clk_cnt_r <= '0;
                        o_tx_done <= 1'b1;
                        state_r   <= ST_IDLE;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                // -----------------------------------------------------------------
                ST_STOP2: begin
                    o_tx <= 1'b1; // İkinci stop biti

                    if (clk_cnt_r >= i_cpb - 1) begin
                        clk_cnt_r <= '0;
                        o_tx_done <= 1'b1;
                        state_r   <= ST_IDLE;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                // -----------------------------------------------------------------
                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
