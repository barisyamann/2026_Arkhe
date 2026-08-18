`timescale 1ns / 1ps
// Description: Synthesizable hardware engine for NPU Compute Engine.
//              Implements the full TinyConv / TFLite Micro Speech pipeline:
//              1) Reshape input 1960 INT8 array into 49x40x1 3D tensor via address mapping.
//              2) 10x8 DepthwiseConv2D layer with stride 2x2, 8 channels (SAME padding).
//              3) ReLU activation: max(0, acc).
//              4) Streaming Flatten & FullyConnected matrix multiply-accumulate to 4 output classes.
//              5) Stable Softmax probability scaling (Q0.12 format) using iterative divider.
//              6) Argmax class selection.
//
//              NOT: Hem depthwise requantization + FC MAC yolu (CONV_ReLU_FC ...
//              FC_MAC3) hem de FC requantization yolu (FC_REQUANT ... FC_RQ_SAT)
//              zamanlama kapatmak icin boru hattina ayrilmistir.
//              Aritmetik degistirilmemistir; sadece cevrimlere yayilmistir.

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
    typedef enum logic [4:0] {
        IDLE            = 5'd0,
        INIT            = 5'd1,
        CONV_READ_REQ   = 5'd2,
        CONV_READ_WAIT  = 5'd3,
        CONV_MAC        = 5'd4,
        CONV_ReLU_FC    = 5'd5,
        SOFTMAX_INIT    = 5'd6,
        SOFTMAX_DIV_REQ = 5'd7,
        SOFTMAX_DIV_WAIT= 5'd8,
        WRITE_OUT_0     = 5'd9,
        WRITE_OUT_1     = 5'd10,
        WRITE_OUT_2     = 5'd11,
        WRITE_OUT_3     = 5'd12,
        DONE            = 5'd13,
        FC_REQUANT      = 5'd14,
        // --- Depthwise requantization + FC MAC boru hatti ---
        CONV_RQ_NUDGE   = 5'd15,
        CONV_RQ_SHIFT   = 5'd16,
        CONV_RELU       = 5'd17,
        FC_MAC0         = 5'd18,
        FC_MAC1         = 5'd19,
        FC_MAC2         = 5'd20,
        FC_MAC3         = 5'd21,
        // --- FC requantization boru hatti ---
        FC_RQ_NUDGE     = 5'd22,
        FC_RQ_SHIFT     = 5'd23,
        FC_RQ_SAT       = 5'd24
    } state_t;

    state_t state;

    // Koordinat ve Döngü Sayaçları
    logic [4:0] t_out;   // 0 .. 24 (Zaman çıkışı)
    logic [4:0] f_out;   // 0 .. 19 (Frekans çıkışı)
    logic [3:0] d_out;   // 0 .. 7  (Filtre/Kanal çıkışı)
    logic [3:0] kh;      // 0 .. 9  (Kernel Yükseklik)
    logic [3:0] kw;      // 0 .. 7  (Kernel Genişlik)

    // -------------------------------------------------------------------------
    // R4 - Kanal paylasimi
    //
    // Girdi adresi yalnizca (t_out, f_out, kh, kw)'ya baglidir; d_out ADRESE
    // GIRMEZ. Yani sekiz kanalin hepsi tam olarak ayni girdi piksellerini
    // okuyordu ve ayni 10x8 pencere sekiz kez taraniyordu.
    //
    // Artik pencere BIR KEZ okunuyor, okunan deger sekiz kanala paralel
    // dagitiliyor. Her kanalin kendi biriktiricisi var.
    //
    // Toplama sirasi kanal ICINDE degismedi (kh, kw duzeni ayni) ve kanallar
    // birbirinden bagimsiz; bu yuzden sonuclar bit-birebir ayni kalmali.
    // -------------------------------------------------------------------------
    logic signed [31:0] conv_acc [0:7];
    logic signed [31:0] fc_acc [0:3];

    // TFLite FC katmanının quantized INT8 çıkışları
    logic signed [7:0] fc_logits [0:3];

    // Hangi sınıfın requantization işleminin yapıldığını tutar
    logic [1:0] fc_q_idx;

    logic [12:0] probs [0:3];

    // --- Requantization boru hatti ara yazmaclari ---
    // Hem depthwise (CONV_*) hem FC (FC_RQ_*) yolunda kullanilir;
    // ikisi hicbir zaman ayni anda aktif olmaz.
    logic signed [63:0] rq_ab;      // 32x32 carpim sonucu
    logic               rq_ovf;     // 0x80000000 * 0x80000000 ozel durumu
    logic [31:0]        rq_shift;   // sag kaydirma miktari
    logic signed [31:0] rq_srhm;    // sat_round_high_mul sonucu
    logic signed [31:0] rq_scaled;  // multiply_quantized sonucu
    logic signed [8:0]  fc_y;       // ReLU + doygunluk sonrasi aktivasyon
    logic [13:0]        fc_idx;     // FC agirlik indeksi (0..3999)

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
    // diff = max_logit - current_logit
    // LUT: exp(-diff * FC_OUTPUT_SCALE)
    // FC_OUTPUT_SCALE = 0.09173192083835602
    // Çıkış formatı: Q0.12  (4096 = 1.0)
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
        end else if (npu_reset_i) begin
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
            for (int i = 0; i < 8; i++) conv_acc[i] <= '0;
            div_start   <= 1'b0;
            div_num     <= '0;
            div_den     <= '0;
            c_div       <= '0;
            sum_exp     <= '0;

            // Requantization boru hatti yazmaclari
            rq_ab       <= '0;
            rq_ovf      <= 1'b0;
            rq_shift    <= '0;
            rq_srhm     <= '0;
            rq_scaled   <= '0;
            fc_y        <= '0;
            fc_idx      <= '0;

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

            for (int i = 0; i < 8; i++) conv_acc[i] <= '0;

            div_start   <= 1'b0;
            div_num     <= '0;
            div_den     <= '0;
            c_div       <= '0;
            sum_exp     <= '0;

            fc_q_idx    <= '0;

            // Requantization boru hatti yazmaclari
            rq_ab       <= '0;
            rq_ovf      <= 1'b0;
            rq_shift    <= '0;
            rq_srhm     <= '0;
            rq_scaled   <= '0;
            fc_y        <= '0;
            fc_idx      <= '0;

            for (int i = 0; i < 4; i++) begin
                fc_acc[i]    <= '0;
                fc_logits[i] <= '0;
                probs[i]     <= '0;
                exp_val[i]   <= '0;
            end

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

                    // Sekiz kanalin biriktiricisi ayni anda baslatilir
                    for (int i = 0; i < 8; i++) conv_acc[i] <= dw_bias[i];
                    state <= CONV_READ_REQ;
                end

                CONV_READ_REQ: begin
                    state <= CONV_READ_WAIT;
                end

                CONV_READ_WAIT: begin
                    state <= CONV_MAC;
                end

                CONV_MAC: begin
                    logic signed [8:0] x_centered;

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

                    // Okunan tek piksel sekiz kanala paralel dagitilir.
                    // dw_weights indisleri d icin ARDISIKTIR (kh*64+kw*8+d),
                    // yani sekiz agirlik bitisik bir blokta duruyor.
                    for (int d = 0; d < 8; d++) begin
                        conv_acc[d] <= conv_acc[d] +
                            x_centered * $signed(dw_weights[int'(kh) * 64 + int'(kw) * 8 + d]);
                    end

                    if (kw == 7) begin
                        kw <= '0;
                        if (kh == 9) begin
                            kh    <= '0;
                            d_out <= '0;          // requant/FC turu kanal 0'dan baslar
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

                // ============================================================
                // Depthwise requantization - Asama 1: 32x32 carpma (DSP)
                // ============================================================
                CONV_ReLU_FC: begin
                    logic signed [31:0] m;

                    m        = get_dw_multiplier(d_out[2:0]);
                    rq_ab    <= $signed(conv_acc[d_out[2:0]]) * $signed(m);
                    rq_ovf   <= (conv_acc[d_out[2:0]] == 32'sh80000000) && (m == 32'sh80000000);
                    rq_shift <= get_dw_rshift(d_out[2:0]);
                    state    <= CONV_RQ_NUDGE;
                end

                // Asama 2: nudge ekleme + 2^31'e bolme
                CONV_RQ_NUDGE: begin
                    logic signed [63:0] nudge;
                    logic signed [63:0] r64;

                    if (rq_ovf) begin
                        rq_srhm <= 32'sh7fffffff;
                    end else begin
                        nudge   = (rq_ab >= 0) ?  64'sd1073741824    // 2^30
                                               : -64'sd1073741823;   // 1 - 2^30
                        r64     = (rq_ab + nudge) / 64'sd2147483648; // 2^31
                        rq_srhm <= r64[31:0];
                    end
                    state <= CONV_RQ_SHIFT;
                end

                // Asama 3: rounding_divide_by_pot (degisken kaydirma)
                CONV_RQ_SHIFT: begin
                    rq_scaled <= rounding_divide_by_pot(rq_srhm, rq_shift);
                    state     <= CONV_RELU;
                end

                // Asama 4: ReLU + INT8 doygunluk + FC indeks hesabi
                // Depthwise cikis zero-point = -128, centered deger 0..255.
                CONV_RELU: begin
                    if (rq_scaled < 32'sd0)
                        fc_y <= 9'sd0;
                    else if (rq_scaled > 32'sd255)
                        fc_y <= 9'sd255;
                    else
                        fc_y <= rq_scaled[8:0];

                    fc_idx <= (int'(t_out) * 20 + int'(f_out)) * 8 + int'(d_out);
                    state  <= FC_MAC0;
                end

                // ============================================================
                // Asama 5-8: dort FC MAC, her cevrimde TEK ROM okumasi
                // (D9 bulgusu burada kapaniyor)
                // ============================================================
                FC_MAC0: begin
                    fc_acc[0] <= fc_acc[0]
                        + $signed(fc_y) * $signed(fc_weights[fc_idx]);
                    state <= FC_MAC1;
                end

                FC_MAC1: begin
                    fc_acc[1] <= fc_acc[1]
                        + $signed(fc_y) * $signed(fc_weights[fc_idx + 14'd4000]);
                    state <= FC_MAC2;
                end

                FC_MAC2: begin
                    fc_acc[2] <= fc_acc[2]
                        + $signed(fc_y) * $signed(fc_weights[fc_idx + 14'd8000]);
                    state <= FC_MAC3;
                end

                // Son asama: sayac guncellemeleri burada yapilir.
                // t_out / f_out / d_out boru hatti boyunca sabit kalmali,
                // cunku fc_idx ve dw_multiplier onlara bagli.
                FC_MAC3: begin
                    fc_acc[3] <= fc_acc[3]
                        + $signed(fc_y) * $signed(fc_weights[fc_idx + 14'd12000]);

                    // R4 sonrasi dongu duzeni:
                    //   konvolusyon (kh,kw) SEKIZ KANAL ICIN BIR KEZ kosar,
                    //   ardindan burada kanal kanal requant + FC yapilir.
                    //
                    // Bu yuzden d_out < 7 iken CONV_READ_REQ'e DEGIL,
                    // CONV_ReLU_FC'ye donuyoruz - girdi zaten okundu.
                    if (d_out == 7) begin
                        d_out <= '0;

                        // Sonraki piksel icin sekiz biriktirici birden yenilenir
                        for (int i = 0; i < 8; i++) conv_acc[i] <= dw_bias[i];

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
                        state <= CONV_ReLU_FC;   // ayni pikselin sonraki kanali
                    end
                end

                // ============================================================
                // FC requantization - Asama 1: 32x32 carpma
                //
                // real multiplier    ~ 0.000439331661
                // integer multiplier = 1932201080
                // right shift        = 11
                // output zero-point  = 14
                // ============================================================
                FC_REQUANT: begin
                    rq_ab <= $signed(fc_acc[fc_q_idx]) * 32'sd1932201080;
                    state <= FC_RQ_NUDGE;
                end

                // Asama 2: nudge ekleme + 2^31'e bolme
                FC_RQ_NUDGE: begin
                    logic signed [63:0] nudge;
                    logic signed [63:0] r64;

                    nudge   = (rq_ab >= 0) ?  64'sd1073741824
                                           : -64'sd1073741823;
                    r64     = (rq_ab + nudge) / 64'sd2147483648;
                    rq_srhm <= r64[31:0];
                    state   <= FC_RQ_SHIFT;
                end

                // Asama 3: sabit 11 bit saga kaydirma + yuvarlama
                FC_RQ_SHIFT: begin
                    rq_scaled <= rounding_divide_by_pot(rq_srhm, 11);
                    state     <= FC_RQ_SAT;
                end

                // Asama 4: zero-point ekleme + INT8 doygunluk + sonraki sinif
                FC_RQ_SAT: begin
                    logic signed [31:0] quant_fc;

                    quant_fc = rq_scaled + 32'sd14;

                    if (quant_fc > 32'sd127)
                        fc_logits[fc_q_idx] <= 8'sd127;

                    else if (quant_fc < -32'sd128)
                        fc_logits[fc_q_idx] <= -8'sd128;

                    else
                        fc_logits[fc_q_idx] <= quant_fc[7:0];

                    // Dort sinifi sirayla isle
                    if (fc_q_idx == 2'd3) begin
                        fc_q_idx <= 2'd0;
                        state    <= SOFTMAX_INIT;
                    end else begin
                        fc_q_idx <= fc_q_idx + 2'd1;
                        state    <= FC_REQUANT;
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
