// =============================================================================
// QSPI Master Peripheral
// TEKNOFEST 2026 Çip Tasarım Yarışması - Mikrodenetleyici Kategorisi
// Şartname: EK-2 Çevre Birimi Yazmaçları / QSPI Master bölümü
// =============================================================================
// Özellikler:
//   - AXI4-Lite konfigürasyon arayüzü
//   - x1 (SPI), x2 (DSPI), x4 (QSPI) veri genişliği desteği
//   - 256 baytlık sayfa yazma/okuma
//   - 4-bayt adres modu (tüm flash alanı)
//   - SPI Mod 0 (CPOL=0, CPHA=0)
//   - SDR (Single Data Rate) çalışma
//   - 64x32-bit TX ve RX FIFO
//   - Programlanabilir prescaler (QSPI_CCR[30:25])
//   - Desteklenen komutlar: READ, DOR, QOR, PP, QPP, SE, READ_ID, RDID,
//     RES, RDSR1, RDSR2, RDCR, WRR, WRDI, WREN, CLSR, RESET
// =============================================================================

`timescale 1ns/1ps

module qspi_master #(
    parameter FIFO_DEPTH   = 64,   // TX/RX FIFO derinliği (64x32-bit)
    parameter AXI_AW       = 32,   // AXI adres genişliği
    parameter AXI_DW       = 32    // AXI veri genişliği
)(
    // Saat ve Sıfırlama
    input  logic        clk,
    input  logic        rst_n,

    // AXI4-Lite Slave Arayüzü (Konfigürasyon)
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

    // QSPI Fiziksel Pinler
    output logic        qspi_sck,
    output logic        qspi_cs_n,
    inout  logic        qspi_io0,   // MOSI / IO0
    inout  logic        qspi_io1,   // MISO / IO1
    inout  logic        qspi_io2,   // IO2 (QSPI)
    inout  logic        qspi_io3,   // IO3 (QSPI)

    // Kesme çıkışı
    output logic        irq
);

// ---------------------------------------------------------------------------
// Yazmaç Ofset Tanımları (Şartname EK-2)
// ---------------------------------------------------------------------------
localparam ADDR_QSPI_CCR = 5'h00;  // Communication Config Register
localparam ADDR_QSPI_ADR = 5'h04;  // Address Register
localparam ADDR_QSPI_DR  = 5'h08;  // Data Register
localparam ADDR_QSPI_STA = 5'h0C;  // Status Register
localparam ADDR_QSPI_FCR = 5'h10;  // FIFO Control Register

// ---------------------------------------------------------------------------
// Flash Komut Kodları
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// İç Yazmaçlar
// ---------------------------------------------------------------------------
logic [31:0] reg_ccr;   // QSPI_CCR - RW
logic [31:0] reg_adr;   // QSPI_ADR - RW
logic [31:0] reg_sta;   // QSPI_STA - RO

// CCR alanları
logic [7:0]  ccr_instr;         // [7:0]   - Instruction value
logic [1:0]  ccr_data_mode;     // [9:8]   - Data mode (00=no data,01=x1,10=x2,11=x4)
logic        ccr_write_read_n;  // [10]    - 0=read, 1=write
logic [4:0]  ccr_dummy_cycles;  // [15:11] - Dummy cycle count
logic [7:0]  ccr_data_size;     // [23:16] - Data size (N+1 bytes)
// [24] REZERVE
logic [5:0]  ccr_prescaler;     // [30:25] - SCK prescaler
logic        ccr_clr_status;    // [31]    - Clear status

// Status alanları
logic        sta_done;          // [0] - Transaction complete
logic        sta_busy;          // [1] - Busy
logic        sta_rx_full;       // [4] - RX FIFO full
logic        sta_rx_empty;      // [5] - RX FIFO empty
logic        sta_tx_full;       // [6] - TX FIFO full
logic        sta_tx_empty;      // [7] - TX FIFO empty
logic [3:0]  sta_fifo_err;      // [11:8] - FIFO error flags

// ---------------------------------------------------------------------------
// FIFO Yapıları (64 x 32-bit)
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// AXI4-Lite Slave - Yazma Kanalı
// ---------------------------------------------------------------------------
logic [AXI_AW-1:0] aw_addr_lat;
logic               aw_valid_lat;
logic [AXI_DW-1:0] w_data_lat;
logic               w_valid_lat;
logic               do_write;
logic               ccr_written;   // CCR'ye yazma: transaction tetikler

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
        ccr_written   <= 1'b0;
    end else begin
        ccr_written <= 1'b0;
        // AW handshake
        if (s_axi_awvalid && !aw_valid_lat) begin
            s_axi_awready <= 1'b1;
            aw_addr_lat   <= s_axi_awaddr;
            aw_valid_lat  <= 1'b1;
        end else begin
            s_axi_awready <= 1'b0;
        end
        // W handshake
        if (s_axi_wvalid && !w_valid_lat) begin
            s_axi_wready <= 1'b1;
            w_data_lat   <= s_axi_wdata;
            w_valid_lat  <= 1'b1;
        end else begin
            s_axi_wready <= 1'b0;
        end
        // B channel
        if (do_write) begin
            aw_valid_lat <= 1'b0;
            w_valid_lat  <= 1'b0;
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= 2'b00;
            // Yazmaç yazımları
            case (aw_addr_lat[4:0])
                ADDR_QSPI_CCR: begin
                    reg_ccr <= w_data_lat;
                    ccr_written <= 1'b1;
                    // CCR[31]=1 ise durum yazmacını temizle
                    if (w_data_lat[31]) sta_done <= 1'b0;
                end
                ADDR_QSPI_ADR: reg_adr <= w_data_lat;
                ADDR_QSPI_DR: begin
                    // TX FIFO'ya yaz
                    if (!tx_full) begin
                        tx_fifo[tx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= w_data_lat;
                        tx_wr_ptr <= tx_wr_ptr + 1;
                    end else begin
                        sta_fifo_err[1] <= 1'b1; // TX FIFO doluyken yazma hatası
                    end
                end
                ADDR_QSPI_FCR: begin
                    if (w_data_lat[0]) rx_flush <= 1'b1; // RX FIFO flush
                    if (w_data_lat[1]) tx_flush <= 1'b1; // TX FIFO flush
                end
                default:;
            endcase
        end
        if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
    end
end

// ---------------------------------------------------------------------------
// AXI4-Lite Slave - Okuma Kanalı
// ---------------------------------------------------------------------------
logic [AXI_AW-1:0] ar_addr_lat;
logic               ar_valid_lat;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rresp   <= 2'b00;
        s_axi_rdata   <= '0;
        ar_valid_lat  <= 1'b0;
        ar_addr_lat   <= '0;
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
                    // RX FIFO'dan oku
                    if (!rx_empty) begin
                        s_axi_rdata <= rx_fifo[rx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                        rx_rd_ptr   <= rx_rd_ptr + 1;
                    end else begin
                        s_axi_rdata  <= 32'hDEAD_BEEF;
                        sta_fifo_err[0] <= 1'b1; // RX FIFO boşken okuma hatası
                    end
                end
                ADDR_QSPI_STA: s_axi_rdata <= reg_sta;
                ADDR_QSPI_FCR: s_axi_rdata <= 32'h0;
                default:       s_axi_rdata <= 32'h0;
            endcase
        end
        if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
    end
end

// ---------------------------------------------------------------------------
// CCR Alanları Decode
// ---------------------------------------------------------------------------
assign ccr_instr        = reg_ccr[7:0];
assign ccr_data_mode    = reg_ccr[9:8];
assign ccr_write_read_n = reg_ccr[10];
assign ccr_dummy_cycles = reg_ccr[15:11];
assign ccr_data_size    = reg_ccr[23:16];
assign ccr_prescaler    = reg_ccr[30:25];
assign ccr_clr_status   = reg_ccr[31];

// ---------------------------------------------------------------------------
// Durum yazmacı birleştir
// ---------------------------------------------------------------------------
assign reg_sta = {20'h0,
                  sta_fifo_err,      // [11:8]
                  sta_tx_empty,      // [7]
                  sta_tx_full,       // [6]
                  sta_rx_empty,      // [5]
                  sta_rx_full,       // [4]
                  2'b00,             // [3:2] rezerve
                  sta_busy,          // [1]
                  sta_done};         // [0]

assign sta_rx_full  = rx_full;
assign sta_rx_empty = rx_empty;
assign sta_tx_full  = tx_full;
assign sta_tx_empty = tx_empty;

// ---------------------------------------------------------------------------
// FIFO Flush
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_wr_ptr <= '0; tx_rd_ptr <= '0;
        rx_wr_ptr <= '0; rx_rd_ptr <= '0;
        tx_flush  <= 1'b0; rx_flush <= 1'b0;
    end else begin
        if (tx_flush) begin tx_wr_ptr <= '0; tx_rd_ptr <= '0; tx_flush <= 1'b0; end
        if (rx_flush) begin rx_wr_ptr <= '0; rx_rd_ptr <= '0; rx_flush <= 1'b0; end
    end
end

// ---------------------------------------------------------------------------
// SCK Üretimi (Prescaler)
// SCK frekansı = sys_clk / (prescaler + 1)
// CCR[30:25] = 0  → SCLK = sys_clk
// CCR[30:25] = 1  → SCLK = sys_clk / 2
// ---------------------------------------------------------------------------
logic [5:0]  sck_cnt;
logic        sck_en;
logic        sck_int;   // dahili SCK toggling
logic        sck_edge_rise, sck_edge_fall;
logic [5:0]  sck_half_period;

assign sck_half_period = (ccr_prescaler == 6'h0) ? 6'h0 : ccr_prescaler;

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
            // Prescaler 0: Her clk'da toggle (SCLK = sys_clk)
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

// SPI Mod 0: CPOL=0, CPHA=0 — SCK boşta '0'
assign qspi_sck = sck_en ? sck_int : 1'b0;

// ---------------------------------------------------------------------------
// IO Yönlendirme (tristate)
// ---------------------------------------------------------------------------
logic        io_oe;          // çıkış enable
logic [3:0]  io_out;         // çıkış verisi
logic [3:0]  io_in;          // giriş verisi (capture)

assign qspi_io0 = io_oe ? io_out[0] : 1'bz;
assign qspi_io1 = (io_oe && ccr_data_mode[1]) ? io_out[1] : 1'bz;
assign qspi_io2 = (io_oe && ccr_data_mode == 2'b11) ? io_out[2] : 1'bz;
assign qspi_io3 = (io_oe && ccr_data_mode == 2'b11) ? io_out[3] : 1'bz;

assign io_in[0] = qspi_io0;
assign io_in[1] = qspi_io1;
assign io_in[2] = qspi_io2;
assign io_in[3] = qspi_io3;

// ---------------------------------------------------------------------------
// Ana Durum Makinesi
// ---------------------------------------------------------------------------
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

// TX shift register
logic [7:0]  shift_out;
logic [7:0]  shift_in;
logic [2:0]  bit_cnt;        // x1 modda bit sayacı
logic [1:0]  nibble_cnt;     // x2/x4 modda sayaç
logic [7:0]  byte_cnt;       // kaç byte gönderildi/alındı
logic [7:0]  total_bytes;    // toplam gönderilecek/alınacak byte
logic [4:0]  dummy_cnt;      // dummy cycle sayacı
logic [31:0] addr_shift;     // adres shift reg
logic [2:0]  addr_byte_cnt;  // gönderilen adres byte sayısı

// TX FIFO'dan okuma
logic [31:0] tx_word;        // şu an gönderilen 32-bit kelime
logic [1:0]  tx_byte_idx;    // kelime içindeki byte indeksi (0-3)
logic        need_addr;       // bu komut adres gerektiriyor mu

// Adres gerektiren komutlar
function automatic logic cmd_needs_addr(input logic [7:0] cmd);
    case (cmd)
        CMD_READ, CMD_DOR, CMD_QOR, CMD_PP, CMD_QPP, CMD_SE: return 1'b1;
        default: return 1'b0;
    endcase
endfunction

// Veri gerektiren komutlar (data_mode != 00)
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
        sta_fifo_err <= 4'h0;
        bit_cnt      <= 3'h0;
        nibble_cnt   <= 2'h0;
        byte_cnt     <= 8'h0;
        dummy_cnt    <= 5'h0;
        addr_byte_cnt<= 3'h0;
        shift_out    <= 8'h0;
        shift_in     <= 8'h0;
        tx_byte_idx  <= 2'h0;
        tx_word      <= 32'h0;
    end else begin
        // FIFO hata bitleri CCR yazımıyla temizle
        if (ccr_written && reg_ccr[31])
            sta_fifo_err <= 4'h0;

        case (state)
            // ------------------------------------------------------------------
            IDLE: begin
                qspi_cs_n <= 1'b1;
                sck_en    <= 1'b0;
                io_oe     <= 1'b0;
                sta_busy  <= 1'b0;
                if (ccr_written) begin
                    // CCR'ye yazma → transaction başlat
                    sta_done  <= 1'b0;
                    sta_busy  <= 1'b1;
                    state     <= ASSERT_CS;
                    total_bytes <= reg_ccr[23:16] + 1; // N+1 byte
                    byte_cnt    <= 8'h0;
                    addr_byte_cnt <= 3'h0;
                    dummy_cnt   <= 5'h0;
                    // İlk TX kelimesini yükle
                    if (!tx_empty) begin
                        tx_word     <= tx_fifo[tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                        tx_rd_ptr   <= tx_rd_ptr + 1;
                    end
                    tx_byte_idx <= 2'h0;
                end
            end

            // ------------------------------------------------------------------
            ASSERT_CS: begin
                qspi_cs_n <= 1'b0;       // CS aktif
                sck_en    <= 1'b0;
                io_oe     <= 1'b1;
                shift_out <= ccr_instr;   // Komut byte'ını yükle
                bit_cnt   <= 3'd7;
                state     <= SEND_CMD;
            end

            // ------------------------------------------------------------------
            // Komut Gönder (her zaman x1, MSB first)
            SEND_CMD: begin
                sck_en <= 1'b1;
                io_oe  <= 1'b1;
                io_out[0] <= shift_out[7]; // MOSI
                io_out[3:1] <= 3'b111;     // diğerleri high-Z

                if (sck_edge_fall) begin
                    if (bit_cnt == 3'h0) begin
                        // Komut bitti
                        if (cmd_needs_addr(ccr_instr)) begin
                            // 3-byte adres gönder (MSB byte önce)
                            addr_shift    <= reg_adr;
                            addr_byte_cnt <= 3'd0;
                            state         <= SEND_ADDR;
                            shift_out     <= reg_adr[23:16]; // adres[23:16]
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
                                // İlk byte'ı TX kelimesinden al
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

            // ------------------------------------------------------------------
            // Adres Gönder (x1, 3-byte, MSB byte önce)
            SEND_ADDR: begin
                io_oe     <= 1'b1;
                io_out[0] <= shift_out[7];
                io_out[3:1] <= 3'b111;

                if (sck_edge_fall) begin
                    if (bit_cnt == 3'h0) begin
                        addr_byte_cnt <= addr_byte_cnt + 1;
                        if (addr_byte_cnt == 3'd1) begin
                            // İkinci adres byte'ı
                            shift_out <= reg_adr[15:8];
                            bit_cnt   <= 3'd7;
                        end else if (addr_byte_cnt == 3'd2) begin
                            // Üçüncü adres byte'ı (LSB)
                            shift_out <= reg_adr[7:0];
                            bit_cnt   <= 3'd7;
                        end else begin
                            // Adres bitti
                            if (ccr_dummy_cycles > 5'h0) begin
                                dummy_cnt <= ccr_dummy_cycles;
                                state     <= DUMMY;
                            end else if (cmd_needs_data(ccr_data_mode)) begin
                                byte_cnt <= 8'h0;
                                bit_cnt  <= 3'd7;
                                if (ccr_write_read_n) begin
                                    state    <= WRITE_DATA;
                                    // x1 için TX'den ilk byte
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

            // ------------------------------------------------------------------
            // Dummy Cycle'lar
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

            // ------------------------------------------------------------------
            // Veri Yazma
            // x1: bit-serial, x2: 2-bit/cycle, x4: 4-bit/cycle
            WRITE_DATA: begin
                io_oe  <= 1'b1;
                sck_en <= 1'b1;

                if (sck_edge_fall) begin
                    case (ccr_data_mode)
                        2'b01: begin // x1
                            io_out[0] <= shift_out[7];
                            if (bit_cnt == 3'h0) begin
                                byte_cnt <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    state  <= DEASSERT_CS;
                                    sck_en <= 1'b0;
                                end else begin
                                    // Sonraki byte'ı al
                                    if (tx_byte_idx == 2'd3) begin
                                        // Yeni kelime yükle
                                        if (!tx_empty) begin
                                            tx_word     <= tx_fifo[tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                                            tx_rd_ptr   <= tx_rd_ptr + 1;
                                        end
                                        tx_byte_idx <= 2'd0;
                                        shift_out   <= tx_word[7:0]; // güncellenir
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
                        2'b10: begin // x2 - 2-bit/cycle
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
                        2'b11: begin // x4 - 4-bit/cycle
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
                        default:; // 00 = veri yok
                    endcase
                end
            end

            // ------------------------------------------------------------------
            // Veri Okuma
            READ_DATA: begin
                io_oe  <= 1'b0;  // MOSI serbest
                sck_en <= 1'b1;

                if (sck_edge_rise) begin
                    case (ccr_data_mode)
                        2'b01: begin // x1
                            shift_in <= {shift_in[6:0], io_in[1]}; // MISO = IO1
                            if (bit_cnt == 3'h0) begin
                                // Byte tamamlandı, RX FIFO'ya yaz
                                if (!rx_full) begin
                                    // 4 byte dolduğunda FIFO'ya yaz
                                    case (byte_cnt[1:0])
                                        2'd0: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][7:0]   <= {shift_in[6:0], io_in[1]};
                                        2'd1: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][15:8]  <= {shift_in[6:0], io_in[1]};
                                        2'd2: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][23:16] <= {shift_in[6:0], io_in[1]};
                                        2'd3: begin
                                            rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][31:24] <= {shift_in[6:0], io_in[1]};
                                            rx_wr_ptr <= rx_wr_ptr + 1;
                                        end
                                    endcase
                                end else begin
                                    sta_fifo_err[0] <= 1'b1;
                                end
                                byte_cnt <= byte_cnt + 1;
                                if (byte_cnt + 1 >= total_bytes) begin
                                    // Kalan baytları flush et
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
                        2'b10: begin // x2
                            shift_in   <= {shift_in[5:0], io_in[1:0]};
                            if (nibble_cnt == 2'd3) begin
                                nibble_cnt <= 2'd0;
                                if (!rx_full) begin
                                    case (byte_cnt[1:0])
                                        2'd0: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][7:0]   <= {shift_in[5:0], io_in[1:0]};
                                        2'd1: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][15:8]  <= {shift_in[5:0], io_in[1:0]};
                                        2'd2: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][23:16] <= {shift_in[5:0], io_in[1:0]};
                                        2'd3: begin
                                            rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][31:24] <= {shift_in[5:0], io_in[1:0]};
                                            rx_wr_ptr <= rx_wr_ptr + 1;
                                        end
                                    endcase
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
                        2'b11: begin // x4
                            shift_in <= {shift_in[3:0], io_in[3:0]};
                            if (nibble_cnt[0]) begin
                                nibble_cnt <= 2'd0;
                                if (!rx_full) begin
                                    case (byte_cnt[1:0])
                                        2'd0: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][7:0]   <= {shift_in[3:0], io_in[3:0]};
                                        2'd1: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][15:8]  <= {shift_in[3:0], io_in[3:0]};
                                        2'd2: rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][23:16] <= {shift_in[3:0], io_in[3:0]};
                                        2'd3: begin
                                            rx_fifo[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]][31:24] <= {shift_in[3:0], io_in[3:0]};
                                            rx_wr_ptr <= rx_wr_ptr + 1;
                                        end
                                    endcase
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

            // ------------------------------------------------------------------
            DEASSERT_CS: begin
                sck_en    <= 1'b0;
                io_oe     <= 1'b0;
                qspi_cs_n <= 1'b1;
                state     <= DONE_ST;
            end

            // ------------------------------------------------------------------
            DONE_ST: begin
                sta_done <= 1'b1;
                sta_busy <= 1'b0;
                state    <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

// ---------------------------------------------------------------------------
// IRQ - İşlem tamamlanınca
// ---------------------------------------------------------------------------
assign irq = sta_done;

// ---------------------------------------------------------------------------
// Formal / Assertion'lar
// ---------------------------------------------------------------------------
`ifdef FORMAL
    // CS aktifken SCK kullanılıyor olmalı
    assert property (@(posedge clk) disable iff (!rst_n)
        (state == SEND_CMD || state == WRITE_DATA || state == READ_DATA) |-> sck_en);
    // IDLE'da CS pasif
    assert property (@(posedge clk) disable iff (!rst_n)
        (state == IDLE) |-> qspi_cs_n);
    // TX FIFO dolu değilken yazma hatası olmamalı
    assert property (@(posedge clk) disable iff (!rst_n)
        !tx_full |-> !sta_fifo_err[1]);
`endif

endmodule
