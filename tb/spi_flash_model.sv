`timescale 1ns / 1ps
// =============================================================================
// Davranissal SPI NOR Flash modeli - yalnizca CMD_READ (0x03) destekler.
//
// Sartname s.16: sistem QSPI master arayuzunden non-volatile bir bellekten
// boot olmalidir. Bu model, simulasyonda o flash'in yerini alir.
//
// Protokol: SPI Mode 0 (CPOL=0, CPHA=0), MSB once, tek hat.
//   io0 = MOSI (master -> flash), yukselen kenarda orneklenir
//   io1 = MISO (flash -> master), dusen kenarda surulur
// =============================================================================

module spi_flash_model #(
    parameter string INIT_FILE  = "app.hex",
    parameter int    WORD_COUNT = 2048      // 2048 x 4 = 8 kB
)(
    input  logic sck,
    input  logic cs_n,
    inout  wire  io0,
    inout  wire  io1,
    inout  wire  io2,
    inout  wire  io3
);

    localparam int BYTE_COUNT = WORD_COUNT * 4;

    logic [31:0] mem_w [0:WORD_COUNT-1];
    logic [7:0]  mem_b [0:BYTE_COUNT-1];

    initial begin
        for (int i = 0; i < WORD_COUNT; i++) mem_w[i] = 32'h0;
        $readmemh(INIT_FILE, mem_w);
        // 32-bit little-endian kelimeleri bayt dizisine ac
        for (int i = 0; i < WORD_COUNT; i++) begin
            mem_b[i*4 + 0] = mem_w[i][7:0];
            mem_b[i*4 + 1] = mem_w[i][15:8];
            mem_b[i*4 + 2] = mem_w[i][23:16];
            mem_b[i*4 + 3] = mem_w[i][31:24];
        end
        $display("[SPI_FLASH] %0d bayt yuklendi: %s", BYTE_COUNT, INIT_FILE);
    end

    // Flash yalnizca io1'i surer; digerleri her zaman yuksek empedans
    logic drive_miso = 1'b0;
    logic miso_val   = 1'b0;

    assign io1 = drive_miso ? miso_val : 1'bz;
    assign io0 = 1'bz;
    assign io2 = 1'bz;
    assign io3 = 1'bz;

    localparam int PH_CMD  = 0;
    localparam int PH_ADDR = 1;
    localparam int PH_DATA = 2;

    logic [7:0]  cmd_reg;
    logic [23:0] addr_reg;
    logic [7:0]  out_shift;
    int          bit_cnt;
    int          phase;

    // Yeni islem baslangici
    always @(negedge cs_n) begin
        bit_cnt    = 0;
        phase      = PH_CMD;
        cmd_reg    = 8'h00;
        addr_reg   = 24'h0;
        drive_miso = 1'b0;
    end

    always @(posedge cs_n) begin
        drive_miso = 1'b0;
    end

    // Yukselen kenar: master'in surdugu biti ornekle
    always @(posedge sck) begin
        if (!cs_n) begin
            if (phase == PH_CMD) begin
                cmd_reg = {cmd_reg[6:0], io0};
                bit_cnt = bit_cnt + 1;
                if (bit_cnt == 8) begin
                    bit_cnt = 0;
                    if (cmd_reg == 8'h03) begin
                        phase = PH_ADDR;
                    end else begin
                        $display("[SPI_FLASH] Desteklenmeyen komut: 0x%02h", cmd_reg);
                        phase = PH_DATA;   // sifir dondur
                        out_shift = 8'h00;
                    end
                end
            end
            else if (phase == PH_ADDR) begin
                addr_reg = {addr_reg[22:0], io0};
                bit_cnt  = bit_cnt + 1;
                if (bit_cnt == 24) begin
                    bit_cnt   = 0;
                    phase     = PH_DATA;
                    out_shift = (addr_reg < BYTE_COUNT) ? mem_b[addr_reg] : 8'h00;
                end
            end
        end
    end

    // Dusen kenar: bir sonraki biti MISO'ya sur
    always @(negedge sck) begin
        if (!cs_n && phase == PH_DATA) begin
            drive_miso = 1'b1;
            miso_val   = out_shift[7];
            out_shift  = {out_shift[6:0], 1'b0};
            bit_cnt    = bit_cnt + 1;
            if (bit_cnt == 8) begin
                bit_cnt   = 0;
                addr_reg  = addr_reg + 1;
                out_shift = (addr_reg < BYTE_COUNT) ? mem_b[addr_reg] : 8'h00;
            end
        end
    end

endmodule
