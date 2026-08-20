`timescale 1ns / 1ps
// =============================================================================
//  npu_tcm_sram.sv - YZ hizlandirici yerel bellegi (TCM)
//
//  Boyut : 30 kB (7680 kelime x 32 bit)
//  Port A: AXI erisimi        - okuma + yazma
//  Port B: Hesaplama motoru   - SALT OKUMA
//
//  Port B'nin salt-okunur olmasi tesadufi degil: sky130 SRAM makrolari
//  1RW + 1R yapisindadir, yalnizca bir port yazabilir. Motorun sonuc
//  yazimlari npu_accelerator icinde Port A'ya yonlendirilmistir.
//
// -----------------------------------------------------------------------------
//  IKI GERCEKLEME
//
//  `ifdef USE_SRAM_MACRO   -> 15 adet sky130_sram_2kbyte_1rw1r_32x512_8
//                             (ASIC akisi ve makro dogrulama kosumu)
//  varsayilan              -> cikarimsal dizi
//                             (FPGA - Vivado bunu Block RAM'e esler)
//
//  Sartname makronun "islevsel dogrulama testlerinde kullanilmasini" sart
//  kosuyor; bu yuzden regresyon iki kipte de kosulur ve ayni sonuclari
//  uretmesi beklenir.
// =============================================================================

module npu_tcm_sram #(
    // Kelime sayisi. Adres portu 13 bit oldugu icin ust sinir 8192'dir.
    // Makro kipinde bu deger MACRO_COUNT * MACRO_WORDS ile tutarli olmalidir.
    parameter int unsigned TCM_WORDS = 7680
)(
    input  logic        clk,

    // --- Port A (AXI Slave Access) - okuma + yazma ---
    input  logic        en_a,
    input  logic [3:0]  we_a,
    input  logic [12:0] addr_a,
    input  logic [31:0] wdata_a,
    output logic [31:0] rdata_a,

    // --- Port B (Hesaplama motoru) - SALT OKUMA ---
    input  logic        en_b,
    input  logic [12:0] addr_b,
    output logic [31:0] rdata_b
);

`ifdef USE_SRAM_MACRO
    // =========================================================================
    // ASIC GERCEKLEMESI - sky130 SRAM makrolari
    //
    // Makro: sky130_sram_2kbyte_1rw1r_32x512_8
    //   512 kelime x 32 bit = 2 kB,  bayt granuler yazma maskesi
    //   Port 0 (RW): clk0 csb0 web0 wmask0 addr0 din0 dout0
    //   Port 1 (R) : clk1 csb1 addr1 dout1
    //   Fiziksel boyut: 683,1 x 416,54 um
    //
    // 7680 kelime = 15 makro. Adres boluntusu:
    //   addr[12:9] -> makro secimi (0..14)
    //   addr[8:0]  -> makro ici adres
    // =========================================================================
    localparam int MACRO_WORDS = 512;
    localparam int MACRO_AW    = 9;
    localparam int MACRO_COUNT = 15;          // 15 * 512 = 7680

    // Sentez zamani tutarlilik denetimi
    initial begin
        if (TCM_WORDS != MACRO_COUNT * MACRO_WORDS) begin
            $error("TCM_WORDS (%0d) makro yapilandirmasiyla uyusmuyor (%0d)",
                   TCM_WORDS, MACRO_COUNT * MACRO_WORDS);
        end
    end

    // --- Adres ayristirma ---
    logic [3:0]           sel_a, sel_b;
    logic [MACRO_AW-1:0]  maddr_a, maddr_b;
    logic                 inr_a, inr_b;      // sinir icinde mi

    assign sel_a   = addr_a[12:MACRO_AW];
    assign maddr_a = addr_a[MACRO_AW-1:0];
    assign inr_a   = (addr_a < TCM_WORDS[12:0]);

    assign sel_b   = addr_b[12:MACRO_AW];
    assign maddr_b = addr_b[MACRO_AW-1:0];
    assign inr_b   = (addr_b < TCM_WORDS[12:0]);

    // --- Makro cikislari ---
    logic [31:0] dout_a [MACRO_COUNT];
    logic [31:0] dout_b [MACRO_COUNT];

    genvar gi;
    generate
        for (gi = 0; gi < MACRO_COUNT; gi = gi + 1) begin : g_sram
            logic sec_a, sec_b;

            // csb / web AKTIF DUSUK - makro sozlesmesi boyle
            assign sec_a = en_a && inr_a && (sel_a == gi[3:0]);
            assign sec_b = en_b && inr_b && (sel_b == gi[3:0]);

            // VERBOSE=0: model her okuma/yazmada $display yapiyor.
            // 23 makro ile simulasyon logu kullanilamaz hale gelirdi.
            sky130_sram_2kbyte_1rw1r_32x512_8 #(.VERBOSE(0)) u_macro (
`ifdef USE_POWER_PINS
                .vccd1  (1'b1),
                .vssd1  (1'b0),
`endif
                // Port 0 - okuma + yazma
                .clk0   (clk),
                .csb0   (~sec_a),
                .web0   (~(sec_a && (we_a != 4'b0))),
                .wmask0 (we_a),
                .addr0  (maddr_a),
                .din0   (wdata_a),
                .dout0  (dout_a[gi]),

                // Port 1 - salt okuma
                .clk1   (clk),
                .csb1   (~sec_b),
                .addr1  (maddr_b),
                .dout1  (dout_b[gi])
            );

            // Simulasyonda X/U onlemek icin makro bellegini sifirla.
            // Referans YEREL ve sabit oldugu icin testbench'ten yapilan
            // degisken indisli erisim sorunu burada yok.
            // synthesis translate_off
            initial begin
                for (int i = 0; i < MACRO_WORDS; i = i + 1)
                    u_macro.mem[i] = 32'h0;
            end
            // synthesis translate_on
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Okuma coklayicisi - BIR CEVRIM GECIKMELI
    //
    // Makro cikisi kayitlidir: dout, adres verildikten sonraki cevrimde gecerli
    // olur. Coklayici anlik sel_a ile surulurse YANLIS makronun cikisi secilir.
    //
    // Ayni tuzaga UART_RDR'de dusulmustu (FIFO cikisi kayitli oldugu icin her
    // okuma bir onceki bayti donduruyordu). Burada bastan gecikmeli kuruldu.
    // -------------------------------------------------------------------------
    logic [3:0] sel_a_q, sel_b_q;
    logic       inr_a_q, inr_b_q;
    logic       en_a_q,  en_b_q;

    always_ff @(posedge clk) begin
        sel_a_q <= sel_a;   inr_a_q <= inr_a;   en_a_q <= en_a;
        sel_b_q <= sel_b;   inr_b_q <= inr_b;   en_b_q <= en_b;
    end

    // -------------------------------------------------------------------------
    // Okuma verisi TUTULMALI - cikarimsal surumde rdata_a/b birer KAYITTI ve
    // bir sonraki okumaya kadar degerini korurdu. Kombinasyonel birakilirsa
    // en_*_q dustugu anda veri kaybolur ve okuyan taraf sifir gorur.
    // -------------------------------------------------------------------------
    logic [31:0] rdata_a_hold, rdata_b_hold;

    always_ff @(posedge clk) begin
        if (en_a_q) rdata_a_hold <= (inr_a_q ? dout_a[sel_a_q] : 32'h0);
        if (en_b_q) rdata_b_hold <= (inr_b_q ? dout_b[sel_b_q] : 32'h0);
    end

    assign rdata_a = en_a_q ? (inr_a_q ? dout_a[sel_a_q] : 32'h0) : rdata_a_hold;
    assign rdata_b = en_b_q ? (inr_b_q ? dout_b[sel_b_q] : 32'h0) : rdata_b_hold;

`else
    // =========================================================================
    // FPGA / HIZLI SIMULASYON GERCEKLEMESI - cikarimsal dizi
    //
    // Vivado bunu Block RAM'e esler. ASIC'te kullanilmaz; orada 391 bin
    // flip-flop uretirdi.
    // =========================================================================
    logic [31:0] ram [0:TCM_WORDS-1];

    // Simulasyonda tanimsiz (X) degerleri onlemek icin sifirlama
    initial begin
        for (int i = 0; i < TCM_WORDS; i = i + 1) begin
            ram[i] = 32'h0;
        end
    end

    // Port A - okuma + yazma, sinir denetimli
    always_ff @(posedge clk) begin
        if (en_a) begin
            if (addr_a < TCM_WORDS) begin
                if (we_a[0]) ram[addr_a][7:0]   <= wdata_a[7:0];
                if (we_a[1]) ram[addr_a][15:8]  <= wdata_a[15:8];
                if (we_a[2]) ram[addr_a][23:16] <= wdata_a[23:16];
                if (we_a[3]) ram[addr_a][31:24] <= wdata_a[31:24];
                rdata_a <= ram[addr_a];
            end else begin
                rdata_a <= 32'h0;
            end
        end
    end

    // Port B - salt okuma (1RW+1R makronun R portu)
    always_ff @(posedge clk) begin
        if (en_b) begin
            if (addr_b < TCM_WORDS) begin
                rdata_b <= ram[addr_b];
            end else begin
                rdata_b <= 32'h0;
            end
        end
    end
`endif

endmodule
