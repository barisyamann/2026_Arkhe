// =============================================================================
// uart_pkg.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - UART Çevre Birimi Paketi
// Ortak parametre ve tip tanımları
// =============================================================================

package uart_pkg;

    // ---------------------------------------------------------------------------
    // AXI4-Lite Parametreleri
    // ---------------------------------------------------------------------------
    localparam int AXI_ADDR_W = 8;   // Adres genişliği (byte)
    localparam int AXI_DATA_W = 32;  // Veri genişliği (bit)

    // ---------------------------------------------------------------------------
    // Temel UART Yazmaç Adresleri (şartname Bölüm EK-2)
    // ---------------------------------------------------------------------------
    localparam logic [7:0] UART_CPB_OFFSET = 8'h00; // Clock per bit
    localparam logic [7:0] UART_STP_OFFSET = 8'h04; // Stop bit
    localparam logic [7:0] UART_RDR_OFFSET = 8'h08; // Read data register (RO)
    localparam logic [7:0] UART_TDR_OFFSET = 8'h0C; // Transmit data register
    localparam logic [7:0] UART_CFG_OFFSET = 8'h10; // Configuration register

    // UART Stream için ek yazmaç adresleri
    localparam logic [7:0] UARTS_FIFO_LEVEL_OFFSET = 8'h14; // RX FIFO doluluk seviyesi (RO)
    localparam logic [7:0] UARTS_FIFO_CLR_OFFSET   = 8'h18; // FIFO temizleme yazmacı
    localparam logic [7:0] UARTS_IRQ_EN_OFFSET      = 8'h1C; // Kesme etkinleştirme

    // ---------------------------------------------------------------------------
    // UART_CFG bit alanları
    // ---------------------------------------------------------------------------
    localparam int CFG_TX_EN    = 0; // Transmit enable
    localparam int CFG_RX_DONE  = 1; // Data received (HW set, SW clear)
    localparam int CFG_TX_DONE  = 2; // Transmit completed (HW set, SW clear)

    // ---------------------------------------------------------------------------
    // Stop bit kodlaması (UART_STP[1:0])
    // ---------------------------------------------------------------------------
    typedef enum logic [1:0] {
        STP_1   = 2'b00, // 1 stop bit
        STP_1_5 = 2'b01, // 1.5 stop bit
        STP_2   = 2'b10  // 2 stop bit (1X)
    } stop_bit_t;

    // ---------------------------------------------------------------------------
    // AXI4-Lite yanıt kodları
    // ---------------------------------------------------------------------------
    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ---------------------------------------------------------------------------
    // FIFO derinliği (UART Stream için)
    // ---------------------------------------------------------------------------
    localparam int STREAM_FIFO_DEPTH = 256; // 256 bayt FIFO

endpackage
