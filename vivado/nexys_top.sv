`timescale 1ns / 1ps
// =============================================================================
//  nexys_top.sv - Nexys A7-100T FPGA Top-Level Wrapper (Hardware Ready)
//  TEKNOFEST 2026 - Takım Arkhe
// =============================================================================

module nexys_top (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,

    // USB-UART Köprüsü
    input  wire        UART_TXD_IN,     // PC -> FPGA (Rx)
    output wire        UART_RXD_OUT,    // FPGA -> PC (Tx)

    // I2C Arayüzü (Pmod JA)
    inout  wire        I2C_SDA,
    inout  wire        I2C_SCL,

    // QSPI Flash
    output wire        QSPI_CS_N,
    inout  wire [3:0]  QSPI_DQ,

    // Harici RISC-V JTAG (Pmod JB)
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,
    input  wire        jtag_trst_n,

    // 16 Anahtar ve 16 LED
    input  wire [15:0] SW,
    output wire [15:0] LED
);

    // -------------------------------------------------------------------------
    // 1. 100 MHz -> 50 MHz Saat Üretimi
    // -------------------------------------------------------------------------
    logic clk_50m_reg = 1'b0;
    always_ff @(posedge CLK100MHZ) begin
        clk_50m_reg <= ~clk_50m_reg;
    end

    wire clk_sys;
    BUFG bufg_clk (
        .I (clk_50m_reg),
        .O (clk_sys)
    );

    // -------------------------------------------------------------------------
    // 2. QSPI Saat Sürücüsü (Artix-7 CCLK / STARTUPE2)
    // -------------------------------------------------------------------------
    wire qspi_sck_int;

    STARTUPE2 #(
        .PROG_USR("FALSE"),
        .SIM_CCLK_FREQ(0.0)
    ) u_startup (
        .CFGCLK     (),
        .CFGMCLK    (),
        .EOS        (),
        .PREQ       (),
        .CLK        (1'b0),
        .GSR        (1'b0),
        .GTS        (1'b0),
        .KEYCLEARB  (1'b1),
        .PACK       (1'b0),
        .USRCCLKO   (qspi_sck_int),
        .USRCCLKTS  (1'b0),
        .USRDONEO   (1'b1),
        .USRDONETS  (1'b0)
    );

    // -------------------------------------------------------------------------
    // 3. I2C ve QSPI Ayrık Hat Bağlantıları (IOBUF)
    // -------------------------------------------------------------------------
    wire sda_o, sda_oe, sda_i;
    wire scl_o, scl_oe, scl_i;

    wire [3:0] qspi_io_o;
    wire [3:0] qspi_io_oe;
    wire [3:0] qspi_io_i;

    IOBUF #(
        .DRIVE(12), .IBUF_LOW_PWR("TRUE"), .IOSTANDARD("LVCMOS33"), .SLEW("SLOW")
    ) u_iobuf_i2c_sda (
        .O(sda_i), .IO(I2C_SDA), .I(sda_o), .T(~sda_oe)
    );

    IOBUF #(
        .DRIVE(12), .IBUF_LOW_PWR("TRUE"), .IOSTANDARD("LVCMOS33"), .SLEW("SLOW")
    ) u_iobuf_i2c_scl (
        .O(scl_i), .IO(I2C_SCL), .I(scl_o), .T(~scl_oe)
    );

    genvar idx;
    generate
        for (idx = 0; idx < 4; idx = idx + 1) begin : gen_qspi_iobuf
            IOBUF #(
                .DRIVE(12), .IBUF_LOW_PWR("TRUE"), .IOSTANDARD("LVCMOS33"), .SLEW("FAST")
            ) u_iobuf_qspi_dq (
                .O(qspi_io_i[idx]), .IO(QSPI_DQ[idx]), .I(qspi_io_o[idx]), .T(~qspi_io_oe[idx])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 4. soc_top Örneklemesi
    // -------------------------------------------------------------------------
    soc_top u_soc (
        .clk_i          (clk_sys),
        .rst_ni         (CPU_RESETN),

        // GPIO
        .gpio_i         (SW),
        .gpio_o         (LED),
        .gpio_tx_en_o   (),

        // UART
        .uart1_rxd      (UART_TXD_IN),
        .uart1_txd      (UART_RXD_OUT),
        .uart2_rxd      (1'b1),
        .uart2_txd      (),

        // I2C
        .i2c_sda_i      (sda_i),
        .i2c_sda_o      (sda_o),
        .i2c_sda_oe     (sda_oe),
        .i2c_scl_i      (scl_i),
        .i2c_scl_o      (scl_o),
        .i2c_scl_oe     (scl_oe),

        // QSPI
        .qspi_sck       (qspi_sck_int),
        .qspi_cs_n      (QSPI_CS_N),
        .qspi_io_i      (qspi_io_i),
        .qspi_io_o      (qspi_io_o),
        .qspi_io_oe     (qspi_io_oe),

        // JTAG
        .jtag_tck       (jtag_tck),
        .jtag_tms       (jtag_tms),
        .jtag_tdi       (jtag_tdi),
        .jtag_tdo       (jtag_tdo),
        .jtag_trst_n    (jtag_trst_n)
    );

endmodule
