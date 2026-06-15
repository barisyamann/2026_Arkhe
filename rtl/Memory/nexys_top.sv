`timescale 1ns / 1ps
// ==============================================================================
//  nexys_top.sv
//  Nexys 4 DDR (XC7A100T) Top Level Wrapper for Arkhe RISC-V SoC
// ==============================================================================

module nexys_top (
    input  logic        CLK100MHZ,      // Pin E3 (100 MHz onboard oscillator)
    input  logic        CPU_RESETN,     // Pin C12 (Active-Low CPU Reset Button)

    // GPIO (Switches and LEDs)
    input  logic [15:0] SW,             // 16 slide switches
    output logic [15:0] LED,            // 16 LEDs above the switches

    // UART 1 (USB-UART Bridge)
    input  logic        UART_TXD_IN,    // Pin C4 (RX on FPGA side)
    output logic        UART_RXD_OUT    // Pin D4 (TX on FPGA side)
);

    // 100 MHz -> 50 MHz Saat Bölücü (Clock Divider)
    // Donanım üzerinde kararlı çalışması için saat sinyali BUFG üzerinden geçirilir.
    logic clk_50mhz_reg = 1'b0;
    always_ff @(posedge CLK100MHZ) begin
        clk_50mhz_reg <= ~clk_50mhz_reg;
    end

    logic clk_50mhz;
    BUFG bufg_clk (
        .I(clk_50mhz_reg),
        .O(clk_50mhz)
    );

    // CPU Reset Sinyali için İki Aşamalı Senkronizatör (Reset Synchronizer)
    // Asenkron reset de-assertion kararsızlıklarını (metastability) ve CPU başlangıç kilitlenmelerini önler.
    logic rst_n_sync_reg1 = 1'b0;
    logic rst_n_sync      = 1'b0;
    always_ff @(posedge clk_50mhz or negedge CPU_RESETN) begin
        if (!CPU_RESETN) begin
            rst_n_sync_reg1 <= 1'b0;
            rst_n_sync      <= 1'b0;
        end else begin
            rst_n_sync_reg1 <= 1'b1;
            rst_n_sync      <= rst_n_sync_reg1;
        end
    end

    // Kullanılmayan Tri-state pinler için boş tanımlamalar
    wire i2c_sda_io;
    wire i2c_scl_io;
    wire qspi_io0_io;
    wire qspi_io1_io;
    wire qspi_io2_io;
    wire qspi_io3_io;

    // SoC Ana Modülünün Çağrılması
    soc_top u_soc (
        .clk_i          (clk_50mhz),
        .rst_ni         (rst_n_sync),

        // GPIO
        .gpio_i         (SW),
        .gpio_o         (LED),
        .gpio_tx_en_o   (), // Kullanılmıyor

        // UART 1 (USB-to-UART Bridge)
        .uart1_rxd      (UART_TXD_IN),
        .uart1_txd      (UART_RXD_OUT),

        // UART 2 (Kullanılmıyor, High-Z kalması için 1'e çekildi)
        .uart2_rxd      (1'b1),
        .uart2_txd      (),

        // I2C (Kullanılmıyor)
        .i2c_sda        (i2c_sda_io),
        .i2c_scl        (i2c_scl_io),

        // QSPI NOR Flash (Kullanılmıyor)
        .qspi_sck       (),
        .qspi_cs_n      (),
        .qspi_io0       (qspi_io0_io),
        .qspi_io1       (qspi_io1_io),
        .qspi_io2       (qspi_io2_io),
        .qspi_io3       (qspi_io3_io),

        // JTAG (Kullanılmıyor - Kararsız çalışmayı önlemek için güvenli durumlara çekildi)
        .jtag_tms       (1'b1),
        .jtag_tck       (1'b0),
        .jtag_tdi       (1'b0),
        .jtag_tdo       (),
        .jtag_trst_n    (1'b1)
    );

endmodule
