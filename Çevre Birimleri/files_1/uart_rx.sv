// =============================================================================
// uart_rx.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - UART Alıcı Modülü
//
// Özellikler:
//   - Başlangıç biti ortasından örnekleme (gürültü toleransı)
//   - 8 bit veri, LSB önce
//   - Programlanabilir baud hızı
//   - Yanlış başlangıç biti tespiti
// =============================================================================

module uart_rx
    import uart_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Baud rate kontrolü
    input  logic [31:0] i_cpb,         // Clocks Per Bit

    // Fiziksel hat girişi
    input  logic        i_rx,          // Seri giriş (senkronize edilmiş olmalı)

    // Veri arayüzü
    output logic [7:0]  o_data,        // Alınan veri
    output logic        o_rx_done,     // Alım tamamlandı (1 saat darbesi)
    output logic        o_rx_busy,     // Alıcı meşgul
    output logic        o_frame_err    // Çerçeve hatası (stop biti 0 ise)
);

    // -------------------------------------------------------------------------
    // Durum makinesi
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE  = 2'd0,
        ST_START = 2'd1,
        ST_DATA  = 2'd2,
        ST_STOP  = 2'd3
    } rx_fsm_t;

    rx_fsm_t state_r;

    // -------------------------------------------------------------------------
    // İç sinyaller
    // -------------------------------------------------------------------------
    logic [31:0] clk_cnt_r;
    logic [2:0]  bit_cnt_r;
    logic [7:0]  shift_r;
    logic [31:0] half_cpb;
    logic [31:0] sample_point; // DATA durumunda örnekleme noktası

    assign half_cpb     = (i_cpb >> 1);
    assign sample_point = i_cpb - 1; // Tam bit süresi sonunda örnekle

    // -------------------------------------------------------------------------
    // RX hat senkronizasyonu (2 FF metastabilite zinciri)
    // -------------------------------------------------------------------------
    logic rx_sync1_r, rx_sync2_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1_r <= 1'b1;
            rx_sync2_r <= 1'b1;
        end else begin
            rx_sync1_r <= i_rx;
            rx_sync2_r <= rx_sync1_r;
        end
    end

    // Senkronize hat
    wire rx_s = rx_sync2_r;

    // -------------------------------------------------------------------------
    // Alıcı Durum Makinesi
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r    <= ST_IDLE;
            clk_cnt_r  <= '0;
            bit_cnt_r  <= '0;
            shift_r    <= '0;
            o_data     <= '0;
            o_rx_done  <= 1'b0;
            o_rx_busy  <= 1'b0;
            o_frame_err<= 1'b0;
        end else begin
            o_rx_done   <= 1'b0;
            o_frame_err <= 1'b0;

            unique case (state_r)
                // -----------------------------------------------------------------
                ST_IDLE: begin
                    o_rx_busy <= 1'b0;
                    clk_cnt_r <= '0;
                    bit_cnt_r <= '0;

                    // Hat LOW'a düştüğünde başlangıç biti tespiti
                    if (!rx_s) begin
                        o_rx_busy <= 1'b1;
                        state_r   <= ST_START;
                    end
                end

                // -----------------------------------------------------------------
                // Başlangıç bitinin ortasını bekle ve doğrula
                ST_START: begin
                    if (clk_cnt_r >= half_cpb - 1) begin
                        clk_cnt_r <= '0;
                        if (!rx_s) begin
                            // Geçerli başlangıç biti
                            state_r <= ST_DATA;
                        end else begin
                            // Sahte start biti (gürültü), IDLE'a dön
                            state_r   <= ST_IDLE;
                            o_rx_busy <= 1'b0;
                        end
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                // -----------------------------------------------------------------
                // Her bit sonunda örnekle (tam bit süresi bekle)
                ST_DATA: begin
                    if (clk_cnt_r >= sample_point) begin
                        clk_cnt_r <= '0;
                        // LSB önce alım: yeni bit MSB'ye kaydır
                        shift_r   <= {rx_s, shift_r[7:1]};

                        if (bit_cnt_r == 3'd7) begin
                            bit_cnt_r <= '0;
                            state_r   <= ST_STOP;
                        end else begin
                            bit_cnt_r <= bit_cnt_r + 1;
                        end
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                // -----------------------------------------------------------------
                // Stop biti doğrulama
                ST_STOP: begin
                    if (clk_cnt_r >= sample_point) begin
                        clk_cnt_r <= '0;
                        if (rx_s) begin
                            // Geçerli stop biti
                            o_data    <= shift_r;
                            o_rx_done <= 1'b1;
                        end else begin
                            // Çerçeve hatası: stop biti 0
                            o_frame_err <= 1'b1;
                        end
                        state_r <= ST_IDLE;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 1;
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
