`timescale 1ns/1ps

module qspi_master #(
    parameter FIFO_DEPTH   = 64,
    parameter AXI_AW       = 32,
    parameter AXI_DW       = 32
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [AXI_AW-1:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [AXI_DW-1:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [AXI_AW-1:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [AXI_DW-1:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    output logic        qspi_sck,
    output logic        qspi_cs_n,

    // -------------------------------------------------------------------------
    // QSPI veri hatlari - AYRIK yon sinyalleri (tri-state modul icinde DEGIL)
    //
    // ASIC akisinda tri-state yalnizca pad halkasinda bulunabilir; sentez
    // araclari modul icindeki 'z surumunu esleyemez. Bu yuzden arayuz
    // cikis / cikis-etkin / giris uclusune ayrildi. Gercek ucdurumlu surucu
    // FPGA'de nexys_top'ta, simulasyonda testbench'te kuruluyor.
    //
    // qspi_io_oe hat basinadir: tek hatli modda yalnizca io0 surulur, ikili
    // modda io0-io1, dortlu modda dordu birden.
    // -------------------------------------------------------------------------
    output logic [3:0]  qspi_io_o,
    output logic [3:0]  qspi_io_oe,
    input  logic [3:0]  qspi_io_i,

    output logic        irq
);

localparam ADDR_QSPI_CCR = 5'h00;
localparam ADDR_QSPI_ADR = 5'h04;
localparam ADDR_QSPI_DR  = 5'h08;
localparam ADDR_QSPI_STA = 5'h0C;
localparam ADDR_QSPI_FCR = 5'h10;

localparam CMD_READ      = 8'h03;
localparam CMD_DOR       = 8'h3B;
localparam CMD_QOR       = 8'h6B;
localparam CMD_PP        = 8'h02;
localparam CMD_QPP       = 8'h32;
localparam CMD_SE        = 8'hD8;
localparam CMD_READ_ID   = 8'hAB;
localparam CMD_RDID      = 8'h9F;
localparam CMD_RES       = 8'hAB;
localparam CMD_RDSR1     = 8'h05;
localparam CMD_RDSR2     = 8'h07;
localparam CMD_RDCR      = 8'h35;
localparam CMD_WRR       = 8'h01;
localparam CMD_WRDI      = 8'h04;
localparam CMD_WREN      = 8'h06;
localparam CMD_CLSR      = 8'h30;
localparam CMD_RESET     = 8'hF0;

logic [31:0] reg_ccr;
logic [31:0] reg_adr;
logic [31:0] reg_sta;

logic [7:0]  ccr_instr;
logic [1:0]  ccr_data_mode;
logic        ccr_write_read_n;
logic [4:0]  ccr_dummy_cycles;
logic [7:0]  ccr_data_size;
logic [5:0]  ccr_prescaler;
logic        ccr_clr_status;

logic        sta_done;
logic        sta_busy;
logic        sta_rx_full;
logic        sta_rx_empty;
logic        sta_tx_full;
logic        sta_tx_empty;
logic [3:0]  sta_fifo_err;
logic        err_rx_empty;
logic        err_rx_full;
logic        err_tx_full;

logic [31:0] tx_fifo [0:FIFO_DEPTH-1];
logic [31:0] rx_fifo [0:FIFO_DEPTH-1];
logic [$clog2(FIFO_DEPTH):0] tx_wr_ptr, tx_rd_ptr;
logic [$clog2(FIFO_DEPTH):0] rx_wr_ptr, rx_rd_ptr;
logic tx_full, tx_empty, rx_full, rx_empty;
logic tx_flush, rx_flush;

assign tx_full  = (tx_wr_ptr[$clog2(FIFO_DEPTH)] != tx_rd_ptr[$clog2(FIFO_DEPTH)]) &&
                  (tx_wr_ptr[$clog2(FIFO_DEPTH)-1:0] == tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]);
assign tx_empty = (tx_wr_ptr == tx_rd_ptr);
assign rx_full  = (rx_wr_ptr[$clog2(FIFO_DEPTH)] != rx_rd_ptr[$clog2(FIFO_DEPTH)]) &&
                  (rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0] == rx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]);
assign rx_empty = (rx_wr_ptr == rx_rd_ptr);

logic [AXI_AW-1:0] aw_addr_lat;
logic              aw_valid_lat;
logic [AXI_DW-1:0] w_data_lat;

    // -------------------------------------------------------------------------
    // AXI4-Lite WSTRB destegi
    //
    // Yazma verisiyle birlikte bayt strobe'u da mandallanir; yazmac atamasi
    // sirasinda etkin olmayan baytlar korunur.
    //
    // Eskiden wstrb tamamen goz ardi ediliyordu: sb/sh ile bir yazmaca bayt
    // yazmak TUM kelimeyi eziyordu. Yazilim hep kelime erisimi yaptigi icin
    // patlamiyordu ama AXI4-Lite ihlaliydi.
    // -------------------------------------------------------------------------
    logic [31:0] w_mask_lat;

logic              w_valid_lat;
logic              do_write;
logic              ccr_written;

assign do_write = aw_valid_lat && w_valid_lat;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        s_axi_bresp   <= 2'b00;
        aw_valid_lat  <= 1'b0;
        w_valid_lat   <= 1'b0;
        aw_addr_lat   <= '0;
        w_data_lat    <= '0;
        w_mask_lat    <= '0;
        ccr_written   <= 1'b0;
        reg_ccr       <= 32'h0;
        reg_adr       <= 32'h0;
        tx_flush      <= 1'b0;
        rx_flush      <= 1'b0;
        tx_wr_ptr     <= '0;
        err_tx_full   <= 1'b0;
    end else begin
        ccr_written <= 1'b0;
        tx_flush    <= 1'b0;
        rx_flush    <= 1'b0;
        if (s_axi_awvalid && !aw_valid_lat) begin
            s_axi_awready <= 1'b1;
            aw_addr_lat   <= s_axi_awaddr;
            aw_valid_lat  <= 1'b1;
        end else begin
            s_axi_awready <= 1'b0;
        end
        if (s_axi_wvalid && !w_valid_lat) begin
            s_axi_wready <= 1'b1;
            w_data_lat   <= s_axi_wdata;
            w_mask_lat   <= {{8{s_axi_wstrb[3]}}, {8{s_axi_wstrb[2]}},
                             {8{s_axi_wstrb[1]}}, {8{s_axi_wstrb[0]}}};
            w_valid_lat  <= 1'b1;
        end else begin
            s_axi_wready <= 1'b0;
        end
        if (do_write) begin
            aw_valid_lat <= 1'b0;
            w_valid_lat  <= 1'b0;
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= 2'b00;
            case (aw_addr_lat[4:0])
                ADDR_QSPI_CCR: begin
                    reg_ccr <= (reg_ccr & ~w_mask_lat) | (w_data_lat & w_mask_lat);
                    ccr_written <= 1'b1;
                end
                ADDR_QSPI_ADR: reg_adr <= (reg_adr & ~w_mask_lat) | (w_data_lat & w_mask_lat);
                ADDR_QSPI_DR: begin
                end
                ADDR_QSPI_FCR: begin
                    if (w_mask_lat[0] && w_data_lat[0]) rx_flush <= 1'b1;
                    if (w_mask_lat[1] && w_data_lat[1]) tx_flush <= 1'b1;
                end
                default:;
            endcase
        end
        if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;

        if (tx_flush) begin
            tx_wr_ptr <= '0;
        end else if (ccr_written && reg_ccr[31]) begin
            err_tx_full <= 1'b0;
        end else if (do_write && aw_addr_lat[4:0] == ADDR_QSPI_DR) begin
            if (!tx_full) begin
                tx_wr_ptr <= tx_wr_ptr + 1;
            end else begin
                err_tx_full <= 1'b1;
            end
        end
    end
end

always_ff @(posedge clk) begin
    if (do_write && aw_addr_lat[4:0] == ADDR_QSPI_DR && !tx_full) begin
        tx_fifo[tx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= w_data_lat;
    end
end

logic [AXI_AW-1:0] ar_addr_lat;
logic              ar_valid_lat;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rresp   <= 2'b00;
        s_axi_rdata   <= '0;
        ar_valid_lat  <= 1'b0;
        ar_addr_lat   <= '0;
        rx_rd_ptr     <= '0;
        err_rx_empty  <= 1'b0;
    end else begin
        if (s_axi_arvalid && !ar_valid_lat) begin
            s_axi_arready <= 1'b1;
            ar_addr_lat   <= s_axi_araddr;
            ar_valid_lat  <= 1'b1;
        end else begin
            s_axi_arready <= 1'b0;
        end
        if (ar_valid_lat && !s_axi_rvalid) begin
            ar_valid_lat <= 1'b0;
            s_axi_rvalid <= 1'b1;
            s_axi_rresp  <= 2'b00;
            case (ar_addr_lat[4:0])
                ADDR_QSPI_CCR: s_axi_rdata <= reg_ccr;
                ADDR_QSPI_ADR: s_axi_rdata <= reg_adr;
                ADDR_QSPI_DR: begin
                    if (!rx_empty) begin
                        s_axi_rdata <= rx_fifo[rx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                        rx_rd_ptr   <= rx_rd_ptr + 1;
                    end else begin
                        s_axi_rdata  <= 32'hDEAD_BEEF;
                        err_rx_empty <= 1'b1;
                    end
                end
                ADDR_QSPI_STA: s_axi_rdata <= reg_sta;
                ADDR_QSPI_FCR: s_axi_rdata <= 32'h0;
                default:       s_axi_rdata <= 32'h0;
            endcase
        end
        if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

        if (rx_flush) begin
            rx_rd_ptr <= '0;
        end
        if (ccr_written && reg_ccr[31]) begin
            err_rx_empty <= 1'b0;
        end
    end
end

assign ccr_instr        = reg_ccr[7:0];
assign ccr_data_mode    = reg_ccr[9:8];
assign ccr_write_read_n = reg_ccr[10];
assign ccr_dummy_cycles = reg_ccr[15:11];
assign ccr_data_size    = reg_ccr[23:16];
assign ccr_prescaler    = reg_ccr[30:25];
assign ccr_clr_status   = reg_ccr[31];

assign sta_fifo_err = {2'b00, err_tx_full, err_rx_empty | err_rx_full};
assign reg_sta = {20'h0,
                  sta_fifo_err,
                  sta_tx_empty,
                  sta_tx_full,
                  sta_rx_empty,
                  sta_rx_full,
                  2'b00,
                  sta_busy,
                  sta_done};

assign sta_rx_full  = rx_full;
assign sta_rx_empty = rx_empty;
assign sta_tx_full  = tx_full;
assign sta_tx_empty = tx_empty;

logic [5:0]  sck_cnt;
logic        sck_en;
logic        sck_int;
logic        sck_edge_rise, sck_edge_fall;
logic [5:0]  sck_half_period;

// =============================================================================
// SCK yarim periyodu - EN AZ 1 (yani 2 cevrim)
//
// KOK NEDEN (16 Agustos'ta prescaler 4 ile gecici olarak ortulen hata):
//
// io_out kayitlidir ve shift_out'u BIR CEVRIM gecikmeyle takip eder:
//     io_out[0] <= shift_out[7];
// shift_out ise sck_edge_fall'da guncellenir. Yani yeni bit, dusen kenardan
// bir cevrim SONRA pine cikar.
//
// Prescaler 0 iken yarim periyot da tam bir cevrimdi. Bu durumda dusen
// kenardan sonraki YUKSELEN kenar, io_out henuz guncellenmeden geliyordu ve
// kole ayni biti IKI KEZ orneklerdi. Belirti: gonderilen 0x03 komutu
// 0x01 olarak okunuyordu.
//
//     0x03 = 0,0,0,0,0,0,1,1  (b7..b0)
//     b7 tekrarlaninca -> 0,0,0,0,0,0,0,1 = 0x01   (birebir eslesti)
//
// Yarim periyot >= 2 cevrim oldugunda kayitlı ciktinin bir cevrimlik
// gecikmesi soguruluyor ve veri, orneklendigi yukselen kenarda kararli
// oluyor. Bu yuzden prescaler 4 sorunu "cozmus" gibi gorunuyordu - asil
// duzeltme, sifir yarim periyoda hic izin vermemek.
//
// Ust sinir: 50 MHz / (2 x 2) = 12,5 MHz SCK. Boot icin fazlasiyla yeterli.
// =============================================================================
assign sck_half_period = (ccr_prescaler == 6'h0) ? 6'h1 : ccr_prescaler;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sck_cnt       <= '0;
        sck_int       <= 1'b0;
        sck_edge_rise <= 1'b0;
        sck_edge_fall <= 1'b0;
    end else if (sck_en) begin
        sck_edge_rise <= 1'b0;
        sck_edge_fall <= 1'b0;
        if (sck_half_period == 6'h0) begin
            sck_int       <= ~sck_int;
            sck_edge_rise <= ~sck_int;
            sck_edge_fall <=  sck_int;
        end else begin
            if (sck_cnt >= sck_half_period) begin
                sck_cnt       <= '0;
                sck_int       <= ~sck_int;
                sck_edge_rise <= ~sck_int;
                sck_edge_fall <=  sck_int;
            end else begin
                sck_cnt <= sck_cnt + 1;
            end
        end
    end else begin
        sck_int       <= 1'b0;
        sck_cnt       <= '0;
        sck_edge_rise <= 1'b0;
        sck_edge_fall <= 1'b0;
    end
end

assign qspi_sck = sck_en ? sck_int : 1'b0;

logic        io_oe;
logic [3:0]  io_out;
logic [3:0]  io_in;

assign qspi_io_o = io_out;

assign qspi_io_oe[0] = io_oe;
assign qspi_io_oe[1] = io_oe && ccr_data_mode[1];
assign qspi_io_oe[2] = io_oe && (ccr_data_mode == 2'b11);
assign qspi_io_oe[3] = io_oe && (ccr_data_mode == 2'b11);

assign io_in = qspi_io_i;

typedef enum logic [3:0] {
    IDLE        = 4'd0,
    ASSERT_CS   = 4'd1,
    SEND_CMD    = 4'd2,
    SEND_ADDR   = 4'd3,
    DUMMY       = 4'd4,
    WRITE_DATA  = 4'd5,
    READ_DATA   = 4'd6,
    DEASSERT_CS = 4'd7,
    DONE_ST     = 4'd8
} state_t;

state_t state;

logic [7:0]  shift_out;
logic [7:0]  shift_in;
logic [2:0]  bit_cnt;
logic [1:0]  nibble_cnt;
logic [8:0]  byte_cnt;
logic [8:0]  total_bytes;
logic [4:0]  dummy_cnt;
logic [31:0] addr_shift;
logic [2:0]  addr_byte_cnt;

logic [31:0] tx_word;
logic [1:0]  tx_byte_idx;
logic        need_addr;

function automatic logic cmd_needs_addr(input logic [7:0] cmd);
    case (cmd)
        CMD_READ, CMD_DOR, CMD_QOR, CMD_PP, CMD_QPP, CMD_SE: return 1'b1;
        default: return 1'b0;
    endcase
endfunction

function automatic logic cmd_needs_data(input logic [1:0] dm);
    return (dm != 2'b00);
endfunction

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= IDLE;
        qspi_cs_n    <= 1'b1;
        sck_en       <= 1'b0;
        io_oe        <= 1'b0;
        io_out       <= 4'h0;
        sta_busy     <= 1'b0;
        sta_done     <= 1'b0;
        err_rx_full  <= 1'b0;
        bit_cnt      <= 3'h0;
        nibble_cnt   <= 2'h0;
        byte_cnt     <= 8'h0;
        total_bytes  <= 8'h0;
        dummy_cnt    <= 5'h0;
        addr_byte_cnt<= 3'h0;
        shift_out    <= 8'h0;
        shift_in     <= 8'h0;
        tx_byte_idx  <= 2'h0;
        tx_word      <= 32'h0;
        tx_rd_ptr    <= '0;
        rx_wr_ptr    <= '0;
    end else begin
        if (ccr_written && reg_ccr[31]) begin
            err_rx_full <= 1'b0;
            sta_done    <= 1'b0;
        end else if (state == IDLE && ccr_written) begin
            sta_done    <= 1'b0;
        end else if (state == DONE_ST) begin
            sta_done    <= 1'b1;
        end

        case (state)
            IDLE: begin
                qspi_cs_n <= 1'b1;
                sck_en    <= 1'b0;
                io_oe     <= 1'b0;
                sta_busy  <= 1'b0;
                if (ccr_written) begin
                    sta_busy  <= 1'b1;
                    state     <= ASSERT_CS;
                    total_bytes <= reg_ccr[23:16] + 1;
                    byte_cnt    <= 8'h0;
                    addr_byte_cnt <= 3'h0;
                    dummy_cnt   <= 5'h0;
                    if (!tx_empty) begin
                        tx_word     <= tx_fifo[tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                        tx_rd_ptr   <= tx_rd_ptr + 1;
                    end
                    tx_byte_idx <= 2'h0;
                end
            end

            ASSERT_CS: begin
                qspi_cs_n <= 1'b0;
                sck_en    <= 1'b0;
                io_oe     <= 1'b1;
                shift_out <= ccr_instr;
                bit_cnt   <= 3'd7;
                state     <= SEND_CMD;
            end

            SEND_CMD: begin
                sck_en <= 1'b1;
                io_oe  <= 1'b1;
                io_out[0] <= shift_out[7];
                io_out[3:1] <= 3'b111;

                if (sck_edge_fall) begin
                    if (bit_cnt == 3'h0) begin
                        if (cmd_needs_addr(ccr_instr)) begin
                            addr_shift    <= reg_adr;
                            addr_byte_cnt <= 3'd0;
                            state         <= SEND_ADDR;
                            shift_out     <= reg_adr[23:16];
                            bit_cnt       <= 3'd7;
                        end else if (ccr_dummy_cycles > 5'h0) begin
                            dummy_cnt <= ccr_dummy_cycles;
                            state     <= DUMMY;
                            sck_en    <= 1'b1;
                        end else if (cmd_needs_data(ccr_data_mode)) begin
                            byte_cnt <= 8'h0;
                            state    <= ccr_write_read_n ? WRITE_DATA : READ_DATA;
                            if (!ccr_write_read_n) io_oe <= 1'b0;
                            bit_cnt  <= 3'd7;
                            if (ccr_write_read_n) begin
                                shift_out   <= tx_word[7:0];
                                tx_byte_idx <= 2'd1;
                            end
                        end else begin
                            state  <= DEASSERT_CS;
                            sck_en <= 1'b0;
                        end
                    end else begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        bit_cnt   <= bit_cnt - 1;
                    end
                end
            end

            SEND_ADDR: begin
                io_oe     <= 1'b1;
                io_out[0] <= shift_out[7];
                io_out[3:1] <= 3'b111;

                if (sck_edge_fall) begin
                    if (bit_cnt == 3'h0) begin
                        addr_byte_cnt <= addr_byte_cnt + 1;
                        // KARSILASTIRMA BIR KAYMISTI (18 Agustos 2026 bulgusu)
                        //
                        // addr_byte_cnt bloklamayan atamayla artar; ilk adres
                        // baytinin SONUNDA hala 0 okunur. Eski kod 1 ve 2 ile
                        // karsilastirdigi icin hicbir dala uymuyor, dogrudan
                        // else'e dusup veri fazina geciyordu:
                        // master 3 adres bayti yerine YALNIZCA 1 tane
                        // gonderiyordu.
                        //
                        // Flash 24 bit adres bekledigi icin iki bayt boyunca
                        // hala adres aliyor, master ise bu sirada bos hatti
                        // (0xFF) okuyordu. Sistem testi bunu goremezdi cunku
                        // varsayilan akis hizli acilis kullaniyor ve QSPI
                        // yolunu hic calistirmiyor.
                        if (addr_byte_cnt == 3'd0) begin
                            shift_out <= reg_adr[15:8];
                            bit_cnt   <= 3'd7;
                        end else if (addr_byte_cnt == 3'd1) begin
                            shift_out <= reg_adr[7:0];
                            bit_cnt   <= 3'd7;
                        end else begin
                            if (ccr_dummy_cycles > 5'h0) begin
                                dummy_cnt <= ccr_dummy_cycles;
                                state     <= DUMMY;
                            end else if (cmd_needs_data(ccr_data_mode)) begin
                                byte_cnt <= 8'h0;
                                bit_cnt  <= 3'd7;
                                if (ccr_write_read_n) begin
                                    state    <= WRITE_DATA;
                                    shift_out   <= tx_word[7:0];
                                    tx_byte_idx <= 2'd1;
                                end else begin
                                    state <= READ_DATA;
                                    io_oe <= 1'b0;
                                end
                            end else begin
                                state  <= DEASSERT_CS;
                                sck_en <= 1'b0;
                            end
                        end
                    end else begin
                        shift_out <= {shift_out[6:0], 1'b0};
                        bit_cnt   <= bit_cnt - 1;
                    end
                end
            end

            DUMMY: begin
                io_oe <= 1'b0;
                if (sck_edge_rise) begin
                    if (dummy_cnt == 5'h1) begin
                        dummy_cnt <= 5'h0;
                        if (cmd_needs_data(ccr_data_mode)) begin
                            byte_cnt <= 8'h0;
                            bit_cnt  <= 3'd7;
                            if (ccr_write_read_n) begin
                                state       <= WRITE_DATA;
                                io_oe       <= 1'b1;
                                shift_out   <= tx_word[7:0];
                                tx_byte_idx <= 2'd1;
                            end else begin
                                state <= READ_DATA;
                            end
                        end else begin
                            state  <= DEASSERT_CS;
                            sck_en <= 1'b0;
                        end
                    end else begin
                        dummy_cnt <= dummy_cnt - 1;
                    end
                end
            end

            WRITE_DATA: begin
                io_oe  <= 1'b1;
                sck_en <= 1'b1;

                if (sck_edge_fall) begin
                    case (ccr_data_mode)
                        2'b01: begin
                            io_out[0] <= shift_out[7];
                            if (bit_cnt == 3'h0) begin
                                byte_cnt <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    state  <= DEASSERT_CS;
                                    sck_en <= 1'b0;
                                end else begin
                                    if (tx_byte_idx == 2'd3) begin
                                        if (!tx_empty) begin
                                            tx_word     <= tx_fifo[tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                                            tx_rd_ptr   <= tx_rd_ptr + 1;
                                        end
                                        tx_byte_idx <= 2'd0;
                                        shift_out   <= tx_word[7:0];
                                    end else begin
                                        case (tx_byte_idx)
                                            2'd0: shift_out <= tx_word[7:0];
                                            2'd1: shift_out <= tx_word[15:8];
                                            2'd2: shift_out <= tx_word[23:16];
                                            2'd3: shift_out <= tx_word[31:24];
                                        endcase
                                        tx_byte_idx <= tx_byte_idx + 1;
                                    end
                                    bit_cnt <= 3'd7;
                                end
                            end else begin
                                shift_out <= {shift_out[6:0], 1'b0};
                                bit_cnt   <= bit_cnt - 1;
                            end
                        end
                        2'b10: begin
                            io_out[1:0] <= shift_out[7:6];
                            if (nibble_cnt == 2'd3) begin
                                nibble_cnt <= 2'd0;
                                byte_cnt   <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    state  <= DEASSERT_CS;
                                    sck_en <= 1'b0;
                                end else begin
                                    shift_out   <= tx_word[7:0];
                                    tx_byte_idx <= tx_byte_idx + 1;
                                end
                            end else begin
                                shift_out  <= {shift_out[5:0], 2'b00};
                                nibble_cnt <= nibble_cnt + 1;
                            end
                        end
                        2'b11: begin
                            io_out[3:0] <= shift_out[7:4];
                            if (nibble_cnt[0] == 1'b1) begin
                                nibble_cnt <= 2'd0;
                                byte_cnt   <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    state  <= DEASSERT_CS;
                                    sck_en <= 1'b0;
                                end else begin
                                    shift_out   <= tx_word[7:0];
                                    tx_byte_idx <= tx_byte_idx + 1;
                                end
                            end else begin
                                shift_out  <= {shift_out[3:0], 4'h0};
                                nibble_cnt <= nibble_cnt + 1;
                            end
                        end
                        default:;
                    endcase
                end
            end

            READ_DATA: begin
                io_oe  <= 1'b0;
                sck_en <= 1'b1;

                if (sck_edge_rise) begin
                    case (ccr_data_mode)
                        2'b01: begin
                            shift_in <= {shift_in[6:0], io_in[1]};
                            if (bit_cnt == 3'h0) begin
                                if (!rx_full) begin
                                    if (byte_cnt[1:0] == 2'd3) begin
                                        rx_wr_ptr <= rx_wr_ptr + 1;
                                    end
                                end else begin
                                    err_rx_full <= 1'b1;
                                end
                                byte_cnt <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    if (byte_cnt[1:0] != 2'd3 && !rx_full)
                                        rx_wr_ptr <= rx_wr_ptr + 1;
                                    state  <= DEASSERT_CS;
                                    sck_en <= 1'b0;
                                end else begin
                                    bit_cnt <= 3'd7;
                                end
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                        2'b10: begin
                            shift_in   <= {shift_in[5:0], io_in[1:0]};
                            if (nibble_cnt == 2'd3) begin
                                nibble_cnt <= 2'd0;
                                if (!rx_full) begin
                                    if (byte_cnt[1:0] == 2'd3) begin
                                        rx_wr_ptr <= rx_wr_ptr + 1;
                                    end
                                end else begin
                                    err_rx_full <= 1'b1;
                                end
                                byte_cnt <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    state  <= DEASSERT_CS;
                                    sck_en <= 1'b0;
                                end
                            end else begin
                                nibble_cnt <= nibble_cnt + 1;
                            end
                        end
                        2'b11: begin
                            shift_in <= {shift_in[3:0], io_in[3:0]};
                            if (nibble_cnt[0]) begin
                                nibble_cnt <= 2'd0;
                                if (!rx_full) begin
                                    if (byte_cnt[1:0] == 2'd3) begin
                                        rx_wr_ptr <= rx_wr_ptr + 1;
                                    end
                                end else begin
                                    err_rx_full <= 1'b1;
                                end
                                byte_cnt <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    state  <= DEASSERT_CS;
                                    sck_en <= 1'b0;
                                end
                            end else begin
                                nibble_cnt <= nibble_cnt + 1;
                            end
                        end
                        default:;
                    endcase
                end
            end

            DEASSERT_CS: begin
                sck_en    <= 1'b0;
                io_oe     <= 1'b0;
                qspi_cs_n <= 1'b1;
                state     <= DONE_ST;
            end

            DONE_ST: begin
                sta_busy <= 1'b0;
                state    <= IDLE;
            end

            default: state <= IDLE;
        endcase

        if (tx_flush) begin
            tx_rd_ptr <= '0;
        end
        if (rx_flush) begin
            rx_wr_ptr <= '0;
        end
    end
end

always_ff @(posedge clk) begin
    if (state == READ_DATA && sck_edge_rise && !rx_full) begin
        case (ccr_data_mode)
            2'b01: begin
                if (bit_cnt == 3'h0) begin
                    case (byte_cnt[1:0])
                        2'd0: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][7:0]   <= {shift_in[6:0], io_in[1]};
                        2'd1: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][15:8]  <= {shift_in[6:0], io_in[1]};
                        2'd2: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][23:16] <= {shift_in[6:0], io_in[1]};
                        2'd3: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][31:24] <= {shift_in[6:0], io_in[1]};
                    endcase
                end
            end
            2'b10: begin
                if (nibble_cnt == 2'd3) begin
                    case (byte_cnt[1:0])
                        2'd0: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][7:0]   <= {shift_in[5:0], io_in[1:0]};
                        2'd1: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][15:8]  <= {shift_in[5:0], io_in[1:0]};
                        2'd2: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][23:16] <= {shift_in[5:0], io_in[1:0]};
                        2'd3: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][31:24] <= {shift_in[5:0], io_in[1:0]};
                    endcase
                end
            end
            2'b11: begin
                if (nibble_cnt[0]) begin
                    case (byte_cnt[1:0])
                        2'd0: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][7:0]   <= {shift_in[3:0], io_in[3:0]};
                        2'd1: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][15:8]  <= {shift_in[3:0], io_in[3:0]};
                        2'd2: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][23:16] <= {shift_in[3:0], io_in[3:0]};
                        2'd3: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][31:24] <= {shift_in[3:0], io_in[3:0]};
                    endcase
                end
            end
            default:;
        endcase
    end
end

assign irq = sta_done;

`ifdef FORMAL
    assert property (@(posedge clk) disable iff (!rst_n)
        (state == SEND_CMD || state == WRITE_DATA || state == READ_DATA) |-> sck_en);
    assert property (@(posedge clk) disable iff (!rst_n)
        (state == IDLE) |-> qspi_cs_n);
    assert property (@(posedge clk) disable iff (!rst_n)
        !tx_full |-> !sta_fifo_err[1]);
`endif

endmodule
