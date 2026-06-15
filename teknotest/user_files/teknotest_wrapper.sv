module teknotest_wrapper(
    input clk_i, // Clock input
    input resetn_i, // Reset input (active low)
    
    input uart_rx_i, // UART RX Input (tb->dut)
    output uart_tx_o // UART TX Output (dut->tb)
);

    // Dummy wires/logic for unused SoC signals
    logic [15:0] gpio_i = 16'h0000;
    logic [15:0] gpio_o;
    logic [15:0] gpio_tx_en_o;
    
    wire i2c_sda;
    wire i2c_scl;
    
    logic qspi_sck;
    logic qspi_cs_n;
    wire qspi_io0;
    wire qspi_io1;
    wire qspi_io2;
    wire qspi_io3;

    // Instantiate SoC Top Module
    soc_top u_soc_top (
        .clk_i        (clk_i),
        .rst_ni       (resetn_i),
        
        .gpio_i       (gpio_i),
        .gpio_o       (gpio_o),
        .gpio_tx_en_o (gpio_tx_en_o),
        
        .uart1_rxd    (uart_rx_i),
        .uart1_txd    (uart_tx_o),
        
        .uart2_rxd    (1'b1),
        .uart2_txd    (),
        
        .i2c_sda      (i2c_sda),
        .i2c_scl      (i2c_scl),
        
        .qspi_sck     (qspi_sck),
        .qspi_cs_n    (qspi_cs_n),
        .qspi_io0     (qspi_io0),
        .qspi_io1     (qspi_io1),
        .qspi_io2     (qspi_io2),
        .qspi_io3     (qspi_io3),
        
        .jtag_tms     (1'b0),
        .jtag_tck     (1'b0),
        .jtag_tdi     (1'b0),
        .jtag_tdo     (),
        .jtag_trst_n  (1'b0)
    );

endmodule