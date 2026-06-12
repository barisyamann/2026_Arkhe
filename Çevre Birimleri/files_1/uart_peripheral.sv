// =============================================================================
// uart_peripheral.sv
// TEKNOFEST 2026 Çip Tasarım Yarışması - Temel UART Çevre Birimi
//
// Şartname EK-2'de tanımlanan UART yazmaç haritasını uygular.
// Arayüz: AXI4-Lite Slave (konfigürasyon)
//
// Yazmaç Haritası:
//   0x00  UART_CPB  Clock per bit (RW)
//   0x04  UART_STP  Stop bit konfigürasyonu (RW)
//   0x08  UART_RDR  Alım veri yazmacı (RO)
//   0x0C  UART_TDR  Gönderim veri yazmacı (RW)
//   0x10  UART_CFG  Konfigürasyon yazmacı (RW)
// =============================================================================

module uart_peripheral
    import uart_pkg::*;
#(
    // Sistem saat frekansı (varsayılan 50 MHz)
    parameter int SYS_CLK_HZ = 50_000_000,
    // Varsayılan baud hızı
    parameter int DEFAULT_BAUD = 115_200
)(
    input  logic        clk,
    input  logic        rst_n,

    // -------------------------------------------------------------------
    // AXI4-Lite Slave Arayüzü
    // -------------------------------------------------------------------
    // Yazma adresi kanalı
    input  logic [AXI_ADDR_W-1:0] s_axil_awaddr,
    input  logic                  s_axil_awvalid,
    output logic                  s_axil_awready,

    // Yazma verisi kanalı
    input  logic [AXI_DATA_W-1:0] s_axil_wdata,
    input  logic [3:0]            s_axil_wstrb,
    input  logic                  s_axil_wvalid,
    output logic                  s_axil_wready,

    // Yazma yanıt kanalı
    output logic [1:0]            s_axil_bresp,
    output logic                  s_axil_bvalid,
    input  logic                  s_axil_bready,

    // Okuma adresi kanalı
    input  logic [AXI_ADDR_W-1:0] s_axil_araddr,
    input  logic                  s_axil_arvalid,
    output logic                  s_axil_arready,

    // Okuma verisi kanalı
    output logic [AXI_DATA_W-1:0] s_axil_rdata,
    output logic [1:0]            s_axil_rresp,
    output logic                  s_axil_rvalid,
    input  logic                  s_axil_rready,

    // -------------------------------------------------------------------
    // Fiziksel UART hatları
    // -------------------------------------------------------------------
    input  logic uart_rxd,  // Seri giriş
    output logic uart_txd,  // Seri çıkış

    // -------------------------------------------------------------------
    // Kesme çıkışı
    // -------------------------------------------------------------------
    output logic uart_irq   // RX alındı veya TX tamamlandı kesmesi
);

    // =========================================================================
    // Yazmaç tanımları
    // =========================================================================
    logic [31:0] reg_cpb_r;   // UART_CPB
    logic [31:0] reg_stp_r;   // UART_STP  (yalnızca [1:0] geçerli)
    logic [7:0]  reg_rdr_r;   // UART_RDR  (RO, HW tarafından yazılır)
    logic [7:0]  reg_tdr_r;   // UART_TDR
    logic [2:0]  reg_cfg_r;   // UART_CFG  [TX_EN, RX_DONE, TX_DONE]

    // =========================================================================
    // Varsayılan CPB değeri
    // =========================================================================
    localparam logic [31:0] DEF_CPB = SYS_CLK_HZ / DEFAULT_BAUD;

    // =========================================================================
    // TX ve RX alt modülleri
    // =========================================================================
    logic tx_start_r;
    logic tx_done_w;
    logic tx_busy_w;

    uart_tx u_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_cpb      (reg_cpb_r),
        .i_stp      (reg_stp_r[1:0]),
        .i_data     (reg_tdr_r),
        .i_tx_start (tx_start_r),
        .o_tx       (uart_txd),
        .o_tx_busy  (tx_busy_w),
        .o_tx_done  (tx_done_w)
    );

    logic       rx_done_w;
    logic [7:0] rx_data_w;
    logic       rx_frame_err_w;

    uart_rx u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_cpb      (reg_cpb_r),
        .i_rx       (uart_rxd),
        .o_data     (rx_data_w),
        .o_rx_done  (rx_done_w),
        .o_rx_busy  (/* bağlantısız */),
        .o_frame_err(rx_frame_err_w)
    );



    // Kesme: RX alındı VEYA TX tamamlandı
    assign uart_irq = reg_cfg_r[CFG_RX_DONE] | reg_cfg_r[CFG_TX_DONE];

    // =========================================================================
    // TX tetikleme lojiği
    // =========================================================================
    // TX_EN biti 1 yazıldığında ve TX meşgul değilken gönderimi başlat
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start_r <= 1'b0;
        end else begin
            tx_start_r <= 1'b0; // Varsayılan: 0 (tek saat darbesi)
            if (reg_cfg_r[CFG_TX_EN] && !tx_busy_w) begin
                tx_start_r <= 1'b1;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - Yazma Kanalı
    // =========================================================================
    // İki aşamalı READY lojiği: adres ve veri eş zamanlı kabul edilir

    logic aw_active_r; // Yazma adresi bekliyor
    logic w_active_r;  // Yazma verisi bekliyor
    logic [AXI_ADDR_W-1:0] aw_addr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_active_r    <= 1'b0;
            w_active_r     <= 1'b0;
            aw_addr_r      <= '0;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= AXI_RESP_OKAY;
            // Yazmaç sıfırlama
            reg_cpb_r      <= DEF_CPB;
            reg_stp_r      <= '0;
            reg_tdr_r      <= '0;
            reg_rdr_r      <= '0;
            reg_cfg_r      <= '0;
        end else begin
            // -----------------------------------------------------------------
            // Donanım geri bildirimleri ile CFG/RDR yazmacının güncellenmesi
            // -----------------------------------------------------------------
            if (rx_done_w) begin
                reg_rdr_r              <= rx_data_w;
                reg_cfg_r[CFG_RX_DONE] <= 1'b1;
            end
            if (tx_done_w) begin
                reg_cfg_r[CFG_TX_DONE] <= 1'b1;
                reg_cfg_r[CFG_TX_EN]   <= 1'b0;
            end

            // -----------------------------------------------------------------
            // Yazma adresi handshake (el sıkışması)
            // -----------------------------------------------------------------
            if (s_axil_awvalid && s_axil_awready) begin
                aw_active_r    <= 1'b1;
                aw_addr_r      <= s_axil_awaddr;
                s_axil_awready <= 1'b0;
            end else if (!aw_active_r) begin
                s_axil_awready <= s_axil_awvalid;
            end

            // -----------------------------------------------------------------
            // Yazma verisi handshake (el sıkışması)
            // -----------------------------------------------------------------
            if (s_axil_wvalid && s_axil_wready) begin
                w_active_r    <= 1'b1;
                s_axil_wready <= 1'b0;
            end else if (!w_active_r) begin
                s_axil_wready <= s_axil_wvalid;
            end

            // -----------------------------------------------------------------
            // Yazma işlemi: adres ve veri hazır olduğunda
            // -----------------------------------------------------------------
            if (aw_active_r && w_active_r && !s_axil_bvalid) begin
                aw_active_r <= 1'b0;
                w_active_r  <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= AXI_RESP_OKAY;

                // Yazmaç seçimi
                unique case (aw_addr_r[7:0])
                    UART_CPB_OFFSET: reg_cpb_r <= s_axil_wdata;
                    UART_STP_OFFSET: reg_stp_r <= s_axil_wdata;
                    UART_TDR_OFFSET: reg_tdr_r <= s_axil_wdata[7:0];
                    UART_CFG_OFFSET: begin
                        // TX_EN: yazılan değeri al
                        if (s_axil_wdata[CFG_TX_EN])
                            reg_cfg_r[CFG_TX_EN] <= 1'b1;
                        // RX_DONE: donanım o an set etmiyorsa yazılımın temizlemesine izin ver
                        if (!s_axil_wdata[CFG_RX_DONE] && !rx_done_w)
                            reg_cfg_r[CFG_RX_DONE] <= 1'b0;
                        // TX_DONE: donanım o an set etmiyorsa yazılımın temizlemesine izin ver
                        if (!s_axil_wdata[CFG_TX_DONE] && !tx_done_w)
                            reg_cfg_r[CFG_TX_DONE] <= 1'b0;
                    end
                    default: s_axil_bresp <= AXI_RESP_SLVERR;
                endcase
            end

            // Yanıt handshake: master kabul ettiğinde temizle
            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - Okuma Kanalı
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= AXI_RESP_OKAY;
        end else begin
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= AXI_RESP_OKAY;

                // Yazmaç okuma seçimi
                unique case (s_axil_araddr[7:0])
                    UART_CPB_OFFSET: s_axil_rdata <= reg_cpb_r;
                    UART_STP_OFFSET: s_axil_rdata <= reg_stp_r;
                    UART_RDR_OFFSET: s_axil_rdata <= {24'b0, reg_rdr_r};
                    UART_TDR_OFFSET: s_axil_rdata <= {24'b0, reg_tdr_r};
                    UART_CFG_OFFSET: s_axil_rdata <= {29'b0, reg_cfg_r};
                    default: begin
                        s_axil_rdata <= '0;
                        s_axil_rresp <= AXI_RESP_SLVERR;
                    end
                endcase
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;
        end
    end

endmodule
