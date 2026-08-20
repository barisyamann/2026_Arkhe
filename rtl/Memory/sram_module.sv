`timescale 1ns / 1ps
// Description: Parametric 8 kB SRAM module with a standard AXI4-Lite Slave Interface.
//              Supports 4-bit write strobes (byte write enable) for BRAM inference in Vivado.
//              Refactored to separate RAM array logic from asynchronous resets.

module sram_module #(
    parameter int AXI_ADDR_W = 32,
    parameter int AXI_DATA_W = 32,
    parameter int RAM_DEPTH  = 2048 // 2048 words * 4 bytes = 8 kB
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // --- AXI4-Lite Slave Arayüzü ---
    // Yazma Adresi
    input  logic [AXI_ADDR_W-1:0]   s_axil_awaddr,
    input  logic                    s_axil_awvalid,
    output logic                    s_axil_awready,
    // Yazma Verisi
    input  logic [AXI_DATA_W-1:0]   s_axil_wdata,
    input  logic [3:0]              s_axil_wstrb,
    input  logic                    s_axil_wvalid,
    output logic                    s_axil_wready,
    // Yazma Yanıtı
    output logic [1:0]              s_axil_bresp,
    output logic                    s_axil_bvalid,
    input  logic                    s_axil_bready,
    // Okuma Adresi
    input  logic [AXI_ADDR_W-1:0]   s_axil_araddr,
    input  logic                    s_axil_arvalid,
    output logic                    s_axil_arready,
    // Okuma Verisi
    output logic [AXI_DATA_W-1:0]   s_axil_rdata,
    output logic [1:0]              s_axil_rresp,
    output logic                    s_axil_rvalid,
    input  logic                    s_axil_rready
);


    // AXI El Sıkışma Durum Kontrolleri
    logic aw_active;
    logic w_active;
    logic [AXI_ADDR_W-1:0] aw_addr_reg;

    localparam logic [1:0] RESP_OKAY = 2'b00;

    // --- AXI Yazma Kontrol Yazmaçları (Async reset içerir) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_active      <= 1'b0;
            w_active       <= 1'b0;
            aw_addr_reg    <= '0;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= RESP_OKAY;
        end else begin
            // Adres handshake
            if (s_axil_awvalid && s_axil_awready) begin
                aw_active      <= 1'b1;
                aw_addr_reg    <= s_axil_awaddr;
                s_axil_awready <= 1'b0;
            end else if (!aw_active) begin
                s_axil_awready <= s_axil_awvalid;
            end

            // Veri handshake
            if (s_axil_wvalid && s_axil_wready) begin
                w_active      <= 1'b1;
                s_axil_wready <= 1'b0;
            end else if (!w_active) begin
                s_axil_wready  <= s_axil_wvalid;
            end

            // Yazma işleminin tamamlanması
            if (aw_active && w_active && !s_axil_bvalid) begin
                aw_active     <= 1'b0;
                w_active      <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= RESP_OKAY;
            end

            // Yanıt tamamlama
            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end


    // --- AXI Okuma Kontrol Yazmaçları (Async reset içerir) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rresp   <= RESP_OKAY;
        end else begin
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= RESP_OKAY;
            end else begin
                s_axil_arready <= 1'b0;
            end

            // Okuma kanalı el sıkışması
            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Bellek gerceklemesi - ortak sinyaller
    // =========================================================================
    logic [31:0]                  ram_rdata;
    logic [$clog2(RAM_DEPTH)-1:0] raddr;
    logic [$clog2(RAM_DEPTH)-1:0] waddr;
    logic                         wr_en;
    logic                         rd_en;

    assign raddr = s_axil_araddr[$clog2(RAM_DEPTH)+1 : 2];
    assign waddr = aw_addr_reg  [$clog2(RAM_DEPTH)+1 : 2];
    assign wr_en = aw_active && w_active && !s_axil_bvalid;
    assign rd_en = s_axil_arvalid && !s_axil_rvalid;

    assign s_axil_rdata = ram_rdata;

`ifdef USE_SRAM_MACRO
    // =========================================================================
    // ASIC GERCEKLEMESI - sky130 SRAM makrolari
    //
    // Makro: sky130_sram_2kbyte_1rw1r_32x512_8  (512 kelime x 32 bit)
    //
    // Bu modul yazma ve okumayi AYRI AXI kanallarindan yapiyor; dolayisiyla
    // 1RW+1R makroya dogal olarak oturuyor:
    //     Port 0 (RW) -> yazmalar
    //     Port 1 (R)  -> okumalar
    // Port 0'in dout0 cikisi kullanilmaz.
    //
    // 2048 kelime = 4 makro:
    //     addr[10:9] -> makro secimi
    //     addr[8:0]  -> makro ici adres
    // =========================================================================
    localparam int MACRO_WORDS = 512;
    localparam int MACRO_AW    = 9;
    localparam int MACRO_COUNT = RAM_DEPTH / MACRO_WORDS;
    localparam int SEL_W       = $clog2(MACRO_COUNT);

    initial begin
        if (RAM_DEPTH % MACRO_WORDS != 0) begin
            $error("RAM_DEPTH (%0d) makro kelime sayisinin kati olmali (%0d)",
                   RAM_DEPTH, MACRO_WORDS);
        end
    end

    logic [SEL_W-1:0]    wsel, rsel;
    logic [MACRO_AW-1:0] wmaddr, rmaddr;

    assign wsel   = waddr[$clog2(RAM_DEPTH)-1 : MACRO_AW];
    assign wmaddr = waddr[MACRO_AW-1:0];
    assign rsel   = raddr[$clog2(RAM_DEPTH)-1 : MACRO_AW];
    assign rmaddr = raddr[MACRO_AW-1:0];

    logic [31:0] dout_r [MACRO_COUNT];

    genvar gi;
    generate
        for (gi = 0; gi < MACRO_COUNT; gi = gi + 1) begin : g_sram
            logic sec_w, sec_r;

            assign sec_w = wr_en && (wsel == gi[SEL_W-1:0]);
            assign sec_r = rd_en && (rsel == gi[SEL_W-1:0]);

            // VERBOSE=0: model her okuma/yazmada $display yapiyor.
            // 23 makro ile simulasyon logu kullanilamaz hale gelirdi.
            sky130_sram_2kbyte_1rw1r_32x512_8 #(.VERBOSE(0)) u_macro (
`ifdef USE_POWER_PINS
                .vccd1  (1'b1),
                .vssd1  (1'b0),
`endif
                // Port 0 - yalnizca yazma icin kullaniliyor
                .clk0   (clk),
                .csb0   (~sec_w),                 // aktif dusuk
                .web0   (~sec_w),                 // aktif dusuk
                .wmask0 (s_axil_wstrb),
                .addr0  (wmaddr),
                .din0   (s_axil_wdata),
                .dout0  (),                       // kullanilmiyor

                // Port 1 - okuma
                .clk1   (clk),
                .csb1   (~sec_r),
                .addr1  (rmaddr),
                .dout1  (dout_r[gi])
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
    // Makro cikisi kayitlidir; anlik rsel ile secim yapilirsa yanlis makronun
    // cikisi alinir. Ayni tuzaga UART_RDR'de dusulmustu.
    // -------------------------------------------------------------------------
    logic [SEL_W-1:0] rsel_q;
    logic             rd_en_q;
    logic             rvalid_addr_q;

    always_ff @(posedge clk) begin
        rsel_q        <= rsel;
        rd_en_q       <= rd_en;
        rvalid_addr_q <= (raddr < RAM_DEPTH[$clog2(RAM_DEPTH)-1:0]) ||
                         (RAM_DEPTH == (1 << $clog2(RAM_DEPTH)));
    end

    // -------------------------------------------------------------------------
    // Okuma verisi TUTULMALI
    //
    // Ozgun cikarimsal surumde ram_rdata bir KAYITTI ve bir sonraki okumaya
    // kadar degerini korurdu. Ilk makro surumunde bunu kombinasyonel yaptim:
    //     rd_en_q ? dout : 0xDEADBEEF
    // AXI'de rready gecikirse rvalid bir cevrimden fazla yuksek kalir; o
    // cevrimde rd_en_q dusmus olur ve master DEADBEEF okur.
    //
    // Sonuc: yukleyici I-RAM'e yazdigi buyruklari geri okuyamadi, CPU hic
    // baslayamadi. Ilk makro kosumu 8 hata verdi.
    // -------------------------------------------------------------------------
    logic [31:0] rdata_hold;

    always_ff @(posedge clk) begin
        if (rd_en_q) rdata_hold <= dout_r[rsel_q];
    end

    assign ram_rdata = rd_en_q ? dout_r[rsel_q] : rdata_hold;

`else
    // =========================================================================
    // FPGA / HIZLI SIMULASYON - cikarimsal dizi (Vivado Block RAM'e esler)
    // =========================================================================
    logic [31:0] ram [0:RAM_DEPTH-1];

    // --- Yazma (RESET ICERMEZ, saf BRAM cikarimi) ---
    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (waddr < RAM_DEPTH) begin
                if (s_axil_wstrb[0]) ram[waddr][7:0]   <= s_axil_wdata[7:0];
                if (s_axil_wstrb[1]) ram[waddr][15:8]  <= s_axil_wdata[15:8];
                if (s_axil_wstrb[2]) ram[waddr][23:16] <= s_axil_wdata[23:16];
                if (s_axil_wstrb[3]) ram[waddr][31:24] <= s_axil_wdata[31:24];
            end
        end
    end

    // --- Okuma (RESET ICERMEZ) ---
    always_ff @(posedge clk) begin
        if (rd_en) begin
            if (raddr < RAM_DEPTH) begin
                ram_rdata <= ram[raddr];
            end else begin
                ram_rdata <= 32'hDEADBEEF;
            end
        end
    end
`endif

endmodule
