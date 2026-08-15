`timescale 1ns / 1ps
// Description: Synthesizable hardware engine for NPU Compute Engine.
//              Implements the full TinyConv / TFLite Micro Speech pipeline:
//              1) Reshape input 1960 INT8 array into 49x40x1 3D tensor via address mapping.
//              2) 10x8 DepthwiseConv2D layer with stride 2x2, 8 channels (SAME padding).
//              3) ReLU activation: max(0, acc).
//              4) Streaming Flatten & FullyConnected matrix multiply-accumulate to 4 output classes.
//              5) Stable Softmax probability scaling (Q0.12 format) using iterative divider.
//              6) Argmax class selection.

module npu_compute_engine (
    input  logic        clk,
    input  logic        rst_n,

    // --- CSR Arayüz Kontrol Sinyalleri ---
    input  logic        start_i,
    input  logic        npu_reset_i,
    input  logic [12:0] in_addr_i,
    input  logic [12:0] out_addr_i,

    // --- CSR Durum Sinyalleri ---
    output logic        busy_o,
    output logic        done_o,
    output logic [1:0]  class_o,

    // --- Port B TCM Bellek Arayüzü ---
    output logic        mem_en_b,
    output logic [3:0]  mem_we_b,
    output logic [12:0] mem_addr_b,
    output logic [31:0] mem_wdata_b,
    input  logic [31:0] mem_rdata_b
);

    // FSM Durum Tanımları
    typedef enum logic [3:0] {
        IDLE            = 4'd0,
        INIT            = 4'd1,
        CONV_READ_REQ   = 4'd2,
        CONV_READ_WAIT  = 4'd3,
        CONV_MAC        = 4'd4,
        CONV_ReLU_FC    = 4'd5,
        SOFTMAX_INIT    = 4'd6,
        SOFTMAX_DIV_REQ = 4'd7,
        SOFTMAX_DIV_WAIT= 4'd8,
        WRITE_OUT_0     = 4'd9,
        WRITE_OUT_1     = 4'd10,
        WRITE_OUT_2     = 4'd11,
        WRITE_OUT_3     = 4'd12,
        DONE            = 4'd13
    } state_t;

    state_t state;

    // Koordinat ve Döngü Sayaçları
    logic [4:0] t_out;   // 0 .. 24 (Zaman çıkışı)
    logic [4:0] f_out;   // 0 .. 19 (Frekans çıkışı)
    logic [3:0] d_out;   // 0 .. 7  (Filtre/Kanal çıkışı)
    logic [3:0] kh;      // 0 .. 9  (Kernel Yükseklik)
    logic [3:0] kw;      // 0 .. 7  (Kernel Genişlik)

    // Akümülatörler
    logic signed [31:0] conv_acc;
    logic signed [31:0] fc_acc [0:3];
    logic [12:0]        probs [0:3];

    // --- Ağırlık ve Sapma (Weight & Bias) ROM Dizi Tanımlamaları ---
    logic signed [7:0]  dw_weights [0:639];
    logic signed [31:0] dw_bias    [0:7];
    logic signed [7:0]  fc_weights [0:15999];
    logic signed [31:0] fc_bias    [0:3];

    // ROM Belleklerin Dosyadan Okunarak İlklendirilmesi
    initial begin
        $readmemh("dw_weights.mem", dw_weights);
        $readmemh("dw_bias.mem", dw_bias);
        $readmemh("fc_weights.mem", fc_weights);
        $readmemh("fc_bias.mem", fc_bias);
    end

    // --- Adres ve Sınır Güvenliği Mantığı (Reshape 49x40x1) ---
    logic signed [31:0] t_in_signed;
    logic signed [31:0] f_in_signed;
    assign t_in_signed = $signed({27'b0, t_out}) * 2 - 4 + $signed({28'b0, kh});
    assign f_in_signed = $signed({27'b0, f_out}) * 2 - 3 + $signed({28'b0, kw});

    logic in_bounds;
    assign in_bounds = (t_in_signed >= 0 && t_in_signed < 49 && f_in_signed >= 0 && f_in_signed < 40);

    logic [12:0] flat_idx_in;
    assign flat_idx_in = in_bounds ? (t_in_signed[5:0] * 40 + f_in_signed[5:0]) : 13'b0;

    logic [12:0] word_offset;
    assign word_offset = flat_idx_in >> 2;

    logic [1:0] byte_offset;
    assign byte_offset = flat_idx_in[1:0];

    // --- Softmax Exponent LUT Arayüzü ---
    // Q0.12 sabit nokta formatında e^(-x) hesaplayan donanım dostu LUT.
    function automatic logic [12:0] get_exp(input int diff);
        int idx;
        idx = diff >> 5; // Ölçekleme faktörü
        if (idx > 63) return 13'd0;
        else begin
            case (idx)
                0:  return 13'd4096; 1:  return 12'd3848; 2:  return 12'd3615; 3:  return 12'd3396;
                4:  return 12'd3191; 5:  return 12'd2997; 6:  return 12'd2816; 7:  return 12'd2645;
                8:  return 12'd2484; 9:  return 12'd2334; 10: return 12'd2192; 11: return 12'd2060;
                12: return 12'd1935; 13: return 12'd1818; 14: return 12'd1708; 15: return 12'd1604;
                16: return 12'd1507; 17: return 12'd1416; 18: return 12'd1330; 19: return 12'd1249;
                20: return 12'd1174; 21: return 12'd1103; 22: return 12'd1036; 23: return 12'd973;
                24: return 12'd914;  25: return 12'd859;  26: return 12'd807;  27: return 12'd758;
                28: return 12'd712;  29: return 12'd669;  30: return 12'd629;  31: return 12'd591;
                32: return 12'd555;  33: return 12'd521;  34: return 12'd490;  35: return 12'd460;
                36: return 12'd432;  37: return 12'd406;  38: return 12'd381;  39: return 12'd358;
                40: return 12'd336;  41: return 12'd316;  42: return 12'd297;  43: return 12'd279;
                44: return 12'd262;  45: return 12'd246;  46: return 12'd231;  47: return 12'd217;
                48: return 12'd204;  49: return 12'd192;  50: return 12'd180;  51: return 12'd169;
                52: return 12'd159;  53: return 12'd149;  54: return 12'd140;  55: return 12'd132;
                56: return 12'd124;  57: return 12'd116;  58: return 12'd109;  59: return 12'd103;
                60: return 12'd96;   61: return 12'd91;   62: return 12'd85;
                default: return 13'd0;
            endcase
        end
    endfunction

    // --- Softmax Bölücü Birimi (Divider) ---
    logic [12:0] div_num;
    logic [15:0] div_den;
    logic        div_start;
    logic        div_done;
    logic [15:0] divisor;
    logic [15:0] dividend_acc;
    logic [12:0] quotient;
    logic [3:0]  bit_index;
    logic        div_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dividend_acc <= '0;
            divisor      <= '0;
            quotient     <= '0;
            bit_index    <= '0;
            div_active   <= 1'b0;
            div_done     <= 1'b0;
        end else if (div_start) begin
            divisor    <= div_den;
            quotient   <= '0;
            bit_index  <= 4'd12;
            div_active <= 1'b1;
            div_done   <= 1'b0;
            if (div_num >= div_den) begin
                quotient[12] <= 1'b1;
                dividend_acc <= '0;
            end else begin
                quotient[12] <= 1'b0;
                dividend_acc <= {3'b0, div_num};
            end
        end else if (div_active) begin
            logic [16:0] sub_val;
            logic [15:0] next_acc;
            next_acc = {dividend_acc[14:0], 1'b0};
            sub_val = {1'b0, next_acc} - {1'b0, divisor};
            
            if (sub_val[16] == 1'b0) begin
                dividend_acc <= sub_val[15:0];
                quotient[bit_index-1] <= 1'b1;
            end else begin
                dividend_acc <= next_acc;
                quotient[bit_index-1] <= 1'b0;
            end

            if (bit_index == 4'd1) begin
                div_active <= 1'b0;
                div_done   <= 1'b1;
            end else begin
                bit_index  <= bit_index - 4'd1;
            end
        end else begin
            div_done <= 1'b0;
        end
    end

    // --- FSM Kontrol Mantığı ---
    logic signed [31:0] max_score;
    logic [12:0]        exp_val [0:3];
    logic [15:0]        sum_exp;
    logic [1:0]         c_div;

    always_comb begin
        max_score = fc_acc[0];
        if (fc_acc[1] > max_score) max_score = fc_acc[1];
        if (fc_acc[2] > max_score) max_score = fc_acc[2];
        if (fc_acc[3] > max_score) max_score = fc_acc[3];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            busy_o      <= 1'b0;
            done_o      <= 1'b0;
            class_o     <= 2'b00;
            t_out       <= '0;
            f_out       <= '0;
            d_out       <= '0;
            kh          <= '0;
            kw          <= '0;
            conv_acc    <= '0;
            div_start   <= 1'b0;
            div_num     <= '0;
            div_den     <= '0;
            c_div       <= '0;
            sum_exp     <= '0;
            
            for (int i = 0; i < 4; i++) begin
                fc_acc[i]  <= '0;
                probs[i]   <= '0;
                exp_val[i] <= '0;
            end
        end else if (npu_reset_i) begin
            state       <= IDLE;
            busy_o      <= 1'b0;
            done_o      <= 1'b0;
            class_o     <= 2'b00;
            t_out       <= '0;
            f_out       <= '0;
            d_out       <= '0;
            kh          <= '0;
            kw          <= '0;
            conv_acc    <= '0;
            div_start   <= 1'b0;
            c_div       <= '0;
        end else begin
            case (state)
                IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        state       <= INIT;
                        busy_o      <= 1'b1;
                        done_o      <= 1'b0;
                        t_out       <= '0;
                        f_out       <= '0;
                        d_out       <= '0;
                        kh          <= '0;
                        kw          <= '0;
                        $display("[%0t] [NPU_ENGINE] Starting upgraded NPU computation: in_addr=0x%h, out_addr=0x%h", $time, in_addr_i, out_addr_i);
                    end
                end

                INIT: begin
                    for (int i = 0; i < 4; i++) begin
                        fc_acc[i] <= fc_bias[i];
                    end
                    conv_acc <= dw_bias[0]; // Akümülatörü kanal 0 bias değeriyle ilkle
                    state    <= CONV_READ_REQ;
                end

                CONV_READ_REQ: begin
                    state <= CONV_READ_WAIT;
                end

                CONV_READ_WAIT: begin
                    state <= CONV_MAC;
                end

               CONV_MAC: begin
    logic signed [8:0] x_centered;
    logic signed [7:0] w_val;

    if (in_bounds) begin
        logic [7:0] raw_byte;

        raw_byte = (byte_offset == 2'd0) ? mem_rdata_b[7:0]   :
                   (byte_offset == 2'd1) ? mem_rdata_b[15:8]  :
                   (byte_offset == 2'd2) ? mem_rdata_b[23:16] :
                                           mem_rdata_b[31:24];

        // TFLite input zero-point = -128
        // x_centered = x_q - (-128) = x_q + 128
        x_centered = $signed({raw_byte[7], raw_byte}) + 9'sd128;

    end else begin
        // SAME padding gerçek değer olarak 0 olmalıdır.
        // Zero-point çıkarıldıktan sonra centered değer doğrudan 0'dır.
        x_centered = 9'sd0;
    end

    // Depthwise weight zero-point = 0
    w_val = dw_weights[int'(kh) * 64 + int'(kw) * 8 + int'(d_out)];

    conv_acc <= conv_acc + x_centered * w_val;

                    if (kw == 7) begin
                        kw <= '0;
                        if (kh == 9) begin
                            kh    <= '0;
                            state <= CONV_ReLU_FC;
                        end else begin
                            kh    <= kh + 1;
                            state <= CONV_READ_REQ;
                        end
                    end else begin
                        kw    <= kw + 1;
                        state <= CONV_READ_REQ;
                    end
                end

                CONV_ReLU_FC: begin
                    logic signed [31:0] Y_conv;
                    int flat_idx;
                    
                    Y_conv   = (conv_acc < 32'sd0) ? 32'sd0 : conv_acc;
                    flat_idx = (int'(t_out) * 20 + int'(f_out)) * 8 + int'(d_out);

                    // ROM tabanlı FC ağırlık erişimi
                    fc_acc[0] <= fc_acc[0] + Y_conv * fc_weights[flat_idx];
                    fc_acc[1] <= fc_acc[1] + Y_conv * fc_weights[4000 + flat_idx];
                    fc_acc[2] <= fc_acc[2] + Y_conv * fc_weights[8000 + flat_idx];
                    fc_acc[3] <= fc_acc[3] + Y_conv * fc_weights[12000 + flat_idx];

                    if (d_out == 7) begin
                        d_out <= '0;
                        conv_acc <= dw_bias[0]; // Sıradaki koordinat için kanal 0 biası yükle
                        if (f_out == 19) begin
                            f_out <= '0;
                            if (t_out == 24) begin
                                t_out <= '0;
                                state <= SOFTMAX_INIT;
                            end else begin
                                t_out <= t_out + 1;
                                state <= CONV_READ_REQ;
                            end
                        end else begin
                            f_out <= f_out + 1;
                            state <= CONV_READ_REQ;
                        end
                    end else begin
                        d_out <= d_out + 1;
                        conv_acc <= dw_bias[d_out + 1]; // Bir sonraki kanal biasını yükle
                        state <= CONV_READ_REQ;
                    end
                end

                SOFTMAX_INIT: begin
                    exp_val[0] <= get_exp(max_score - fc_acc[0]);
                    exp_val[1] <= get_exp(max_score - fc_acc[1]);
                    exp_val[2] <= get_exp(max_score - fc_acc[2]);
                    exp_val[3] <= get_exp(max_score - fc_acc[3]);
                    c_div      <= '0;
                    state      <= SOFTMAX_DIV_REQ;
                end

                SOFTMAX_DIV_REQ: begin
                    // Toplam payda hesabı
                    sum_exp   = exp_val[0] + exp_val[1] + exp_val[2] + exp_val[3];
                    div_num   <= exp_val[c_div];
                    div_den   <= (sum_exp == 16'd0) ? 16'd1 : sum_exp;
                    div_start <= 1'b1;
                    state     <= SOFTMAX_DIV_WAIT;
                end

                SOFTMAX_DIV_WAIT: begin
                    div_start <= 1'b0;
                    if (div_done) begin
                        probs[c_div] <= quotient;
                        if (c_div == 3) begin
                            state <= WRITE_OUT_0;
                        end else begin
                            c_div <= c_div + 1;
                            state <= SOFTMAX_DIV_REQ;
                        end
                    end
                end

                WRITE_OUT_0: begin
                    state <= WRITE_OUT_1;
                end

                WRITE_OUT_1: begin
                    state <= WRITE_OUT_2;
                end

                WRITE_OUT_2: begin
                    state <= WRITE_OUT_3;
                end

                WRITE_OUT_3: begin
                    state <= DONE;
                    // Argmax Karar Mantığı
                    if (probs[2] >= probs[3] && probs[2] >= probs[1] && probs[2] >= probs[0]) begin
                        class_o <= 2'd2; // YES
                    end else if (probs[3] >= probs[2] && probs[3] >= probs[1] && probs[3] >= probs[0]) begin
                        class_o <= 2'd3; // NO
                    end else if (probs[1] >= probs[0] && probs[1] >= probs[2] && probs[1] >= probs[3]) begin
                        class_o <= 2'd1; // UNKNOWN
                    end else begin
                        class_o <= 2'd0; // SILENCE
                    end
                end

                DONE: begin
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                    if (!done_o) begin
                        $display("[%0t] [NPU_ENGINE] Upgraded NPU computation done. Selected Class=%0d", $time, class_o);
                        $display("            fc_acc: [0]=%0d, [1]=%0d, [2]=%0d, [3]=%0d", fc_acc[0], fc_acc[1], fc_acc[2], fc_acc[3]);
                        $display("            probs:  [0]=%0d, [1]=%0d, [2]=%0d, [3]=%0d", probs[0], probs[1], probs[2], probs[3]);
                    end

                    if (start_i || npu_reset_i) begin
                        state  <= IDLE;
                        done_o <= 1'b0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // --- Port B RAM Kontrol Sinyallerinin Kombinasyonel Sürülmesi ---
    always_comb begin
        mem_en_b    = 1'b0;
        mem_we_b    = 4'b0000;
        mem_addr_b  = 13'b0;
        mem_wdata_b = 32'b0;

        case (state)
            CONV_READ_REQ: begin
                if (in_bounds) begin
                    mem_en_b   = 1'b1;
                    mem_addr_b = in_addr_i + word_offset;
                end
            end
            WRITE_OUT_0: begin
                mem_en_b    = 1'b1;
                mem_we_b    = 4'hf;
                mem_addr_b  = out_addr_i;
                mem_wdata_b = 32'(probs[0]);
            end
            WRITE_OUT_1: begin
                mem_en_b    = 1'b1;
                mem_we_b    = 4'hf;
                mem_addr_b  = out_addr_i + 13'd1;
                mem_wdata_b = 32'(probs[1]);
            end
            WRITE_OUT_2: begin
                mem_en_b    = 1'b1;
                mem_we_b    = 4'hf;
                mem_addr_b  = out_addr_i + 13'd2;
                mem_wdata_b = 32'(probs[2]);
            end
            WRITE_OUT_3: begin
                mem_en_b    = 1'b1;
                mem_we_b    = 4'hf;
                mem_addr_b  = out_addr_i + 13'd3;
                mem_wdata_b = 32'(probs[3]);
            end
            default: ;
        endcase
    end

endmodule
