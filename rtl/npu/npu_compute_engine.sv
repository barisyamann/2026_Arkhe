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
        DONE            = 4'd13,
        FC_REQUANT      = 4'd14
    } state_t;

    state_t state;

    // Koordinat ve Döngü Sayaçları
    logic [4:0] t_out;   // 0 .. 24 (Zaman çıkışı)
    logic [4:0] f_out;   // 0 .. 19 (Frekans çıkışı)
    logic [3:0] d_out;   // 0 .. 7  (Filtre/Kanal çıkışı)
    logic [3:0] kh;      // 0 .. 9  (Kernel Yükseklik)
    logic [3:0] kw;      // 0 .. 7  (Kernel Genişlik)

logic signed [31:0] conv_acc;
logic signed [31:0] fc_acc [0:3];

// TFLite FC katmanının quantized INT8 çıkışları
logic signed [7:0] fc_logits [0:3];

// Hangi sınıfın requantization işleminin yapıldığını tutar
logic [1:0] fc_q_idx;

logic [12:0] probs [0:3];
    
    // --- Ağırlık ve Sapma (Weight & Bias) ROM Dizi Tanımlamaları ---
    logic signed [7:0]  dw_weights [0:639];
    logic signed [31:0] dw_bias    [0:7];
    logic signed [7:0]  fc_weights [0:15999];
    logic signed [31:0] fc_bias    [0:3];
    logic [12:0] softmax_exp_lut [0:255];

    // ROM Belleklerin Dosyadan Okunarak İlklendirilmesi
    initial begin
        $readmemh("dw_weights.mem", dw_weights);
        $readmemh("dw_bias.mem", dw_bias);
        $readmemh("fc_weights.mem", fc_weights);
        $readmemh("fc_bias.mem", fc_bias);
        $readmemh("softmax_exp_lut.mem", softmax_exp_lut);
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
// ============================================================
// TFLite INT8 Depthwise requantization yardımcı fonksiyonları
// ============================================================

// TFLite benzeri:
// SaturatingRoundingDoublingHighMul
function automatic logic signed [31:0] sat_round_high_mul(
    input logic signed [31:0] a,
    input logic signed [31:0] b
);
    logic signed [63:0] ab;
    logic signed [63:0] nudge;
    logic signed [63:0] result64;

    begin
        // Özel overflow durumu
        if ((a == 32'sh80000000) &&
            (b == 32'sh80000000)) begin

            sat_round_high_mul = 32'sh7fffffff;

        end else begin

            ab = $signed(a) * $signed(b);

            if (ab >= 0)
                nudge = 64'sd1073741824;   // 2^30
            else
                nudge = -64'sd1073741823;  // 1 - 2^30

            result64 = (ab + nudge) / 64'sd2147483648; // 2^31

            sat_round_high_mul = result64[31:0];
        end
    end
endfunction


// 2^N'e bölme + yuvarlama
function automatic logic signed [31:0] rounding_divide_by_pot(
    input logic signed [31:0] x,
    input integer exponent
);
    logic signed [31:0] mask;
    logic signed [31:0] remainder;
    logic signed [31:0] threshold;

    begin
        mask = (32'sd1 <<< exponent) - 1;

        remainder = x & mask;

        threshold =
            (mask >>> 1) +
            ((x < 0) ? 32'sd1 : 32'sd0);

        rounding_divide_by_pot =
            (x >>> exponent) +
            ((remainder > threshold) ? 32'sd1 : 32'sd0);
    end
endfunction


// TFLite quantized multiplier
function automatic logic signed [31:0] multiply_quantized(
    input logic signed [31:0] x,
    input logic signed [31:0] multiplier,
    input integer right_shift
);
    logic signed [31:0] temp;

    begin
        temp = sat_round_high_mul(x, multiplier);

        multiply_quantized =
            rounding_divide_by_pot(temp, right_shift);
    end
endfunction


// ============================================================
// Gerçek TFLite modelinden çıkarılan
// Depthwise kanal multiplier değerleri
// ============================================================
function automatic logic signed [31:0] get_dw_multiplier(
    input logic [2:0] channel
);
    begin
        case (channel)

            3'd0: get_dw_multiplier = 32'sd1653229999;
            3'd1: get_dw_multiplier = 32'sd1516545207;
            3'd2: get_dw_multiplier = 32'sd2000799311;
            3'd3: get_dw_multiplier = 32'sd1159928266;
            3'd4: get_dw_multiplier = 32'sd1498403863;
            3'd5: get_dw_multiplier = 32'sd1285645282;
            3'd6: get_dw_multiplier = 32'sd2146175029;
            3'd7: get_dw_multiplier = 32'sd1756589032;

            default:
                get_dw_multiplier = 32'sd0;

        endcase
    end
endfunction


// Her kanalın sağa kaydırma miktarı
function automatic integer get_dw_rshift(
    input logic [2:0] channel
);
    begin
        case (channel)

            3'd0: get_dw_rshift = 10;
            3'd1: get_dw_rshift = 12;
            3'd2: get_dw_rshift = 10;
            3'd3: get_dw_rshift = 10;
            3'd4: get_dw_rshift = 10;
            3'd5: get_dw_rshift = 10;
            3'd6: get_dw_rshift = 10;
            3'd7: get_dw_rshift = 10;

            default:
                get_dw_rshift = 10;

        endcase
    end
endfunction
    // --- Softmax Exponent LUT Arayüzü ---
    // Q0.12 sabit nokta formatında e^(-x) hesaplayan donanım dostu LUT.
    // ------------------------------------------------------------
// Softmax exponent LUT
//
// diff = max_logit - current_logit
//
// LUT:
// exp(-diff * FC_OUTPUT_SCALE)
//
// FC_OUTPUT_SCALE = 0.09173192083835602
//
// Çıkış formatı: Q0.12
// 4096 = 1.0
// ------------------------------------------------------------
function automatic logic [12:0] get_exp(
    input integer diff
);
    begin

        if (diff <= 0)
            get_exp = 13'd4096;

        else if (diff >= 256)
            get_exp = 13'd0;

        else
            get_exp = softmax_exp_lut[diff];

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

        max_score = $signed(fc_logits[0]);

        if ($signed(fc_logits[1]) > max_score)
            max_score = $signed(fc_logits[1]);

        if ($signed(fc_logits[2]) > max_score)
            max_score = $signed(fc_logits[2]);

        if ($signed(fc_logits[3]) > max_score)
            max_score = $signed(fc_logits[3]);

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
                fc_acc[i]    <= '0;
                fc_logits[i] <= '0;
                probs[i]     <= '0;
                exp_val[i]   <= '0;
            end

            fc_q_idx <= '0;
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
                        fc_acc[i]    <= fc_bias[i];
                        fc_logits[i] <= '0;
                    end

                    fc_q_idx <= 2'd0;

                    conv_acc <= dw_bias[0];
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

    logic signed [31:0] scaled_conv;
    logic signed [8:0]  Y_conv_centered;

    int flat_idx;

    // --------------------------------------------------------
    // 1. 32-bit convolution sonucunu gerçek TFLite
    //    quantization değerleriyle yeniden ölçekle
    // --------------------------------------------------------
    scaled_conv = multiply_quantized(
        conv_acc,
        get_dw_multiplier(d_out[2:0]),
        get_dw_rshift(d_out[2:0])
    );

    // --------------------------------------------------------
    // 2. ReLU + INT8 saturation
    //
    // Depthwise çıkış zero-point = -128
    //
    // FC hesabında (q - zero_point) gerektiği için:
    //
    //     q - (-128) = q + 128
    //
    // centred değer 0..255 olur.
    // --------------------------------------------------------
    if (scaled_conv < 32'sd0)
        Y_conv_centered = 9'sd0;

    else if (scaled_conv > 32'sd255)
        Y_conv_centered = 9'sd255;

    else
        Y_conv_centered = scaled_conv[8:0];


    flat_idx =
        (int'(t_out) * 20 + int'(f_out)) * 8
        + int'(d_out);


    // --------------------------------------------------------
    // 3. Fully Connected MAC
    // --------------------------------------------------------
    fc_acc[0] <= fc_acc[0]
        + $signed(Y_conv_centered)
        * $signed(fc_weights[flat_idx]);

    fc_acc[1] <= fc_acc[1]
        + $signed(Y_conv_centered)
        * $signed(fc_weights[4000 + flat_idx]);

    fc_acc[2] <= fc_acc[2]
        + $signed(Y_conv_centered)
        * $signed(fc_weights[8000 + flat_idx]);

    fc_acc[3] <= fc_acc[3]
        + $signed(Y_conv_centered)
        * $signed(fc_weights[12000 + flat_idx]);

                    if (d_out == 7) begin
                        d_out <= '0;
                        conv_acc <= dw_bias[0]; // Sıradaki koordinat için kanal 0 biası yükle
                    if (f_out == 19) begin
                        f_out <= '0;

                        if (t_out == 24) begin
                            t_out    <= '0;
                            fc_q_idx <= 2'd0;
                            state    <= FC_REQUANT;
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
                FC_REQUANT: begin

                    logic signed [31:0] scaled_fc;
                    logic signed [31:0] quant_fc;

                    // --------------------------------------------------------
                    // TFLite FC requantization
                    //
                    // real multiplier ≈ 0.000439331661
                    // integer multiplier = 1932201080
                    // right shift = 11
                    // output zero-point = 14
                    // --------------------------------------------------------

                   scaled_fc = multiply_quantized(
                       fc_acc[fc_q_idx],
                       32'sd1932201080,
                       11
                   );

                   // TFLite output zero-point ekle
                   quant_fc = scaled_fc + 32'sd14;

                   // INT8 saturation
                   if (quant_fc > 32'sd127)
                       fc_logits[fc_q_idx] <= 8'sd127;

                   else if (quant_fc < -32'sd128)
                       fc_logits[fc_q_idx] <= -8'sd128;

                   else
                       fc_logits[fc_q_idx] <= quant_fc[7:0];


                   // Dört sınıfı sırayla işle
                   if (fc_q_idx == 2'd3) begin
                       fc_q_idx <= 2'd0;
                       state    <= SOFTMAX_INIT;
                   end
                   else begin
                       fc_q_idx <= fc_q_idx + 2'd1;
                   end
                end
                SOFTMAX_INIT: begin

                    // FC requantization sonrası gerçek INT8 logits kullanılır.
                    exp_val[0] <= get_exp(max_score - $signed(fc_logits[0]));
                    exp_val[1] <= get_exp(max_score - $signed(fc_logits[1]));
                    exp_val[2] <= get_exp(max_score - $signed(fc_logits[2]));
                    exp_val[3] <= get_exp(max_score - $signed(fc_logits[3]));

                    c_div <= '0;
                    state <= SOFTMAX_DIV_REQ;

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
                    // --------------------------------------------------------
                    // Sınıf seçimi doğrudan quantized FC logits üzerinden.
                    // Softmax sıralamayı değiştirmez.
                    // --------------------------------------------------------

                    if (($signed(fc_logits[0]) >= $signed(fc_logits[1])) &&
                        ($signed(fc_logits[0]) >= $signed(fc_logits[2])) &&
                        ($signed(fc_logits[0]) >= $signed(fc_logits[3]))) begin

                        class_o <= 2'd0; // SILENCE

                    end
                    else if (($signed(fc_logits[1]) >= $signed(fc_logits[2])) &&
                    ($signed(fc_logits[1]) >= $signed(fc_logits[3]))) begin

                        class_o <= 2'd1; // UNKNOWN

                    end
                    else if ($signed(fc_logits[2]) >= $signed(fc_logits[3])) begin

                        class_o <= 2'd2; // YES

                    end
                    else begin

                        class_o <= 2'd3; // NO

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
