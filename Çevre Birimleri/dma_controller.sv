`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 12.06.2026
// Design Name: dma_controller
// Module Name: dma_controller
// Description: Single-Channel DMA Controller with AXI4-Lite interfaces.
//              Provides Memory-to-Memory data transfer capability.
//              Primary use case: UART-Stream → NPU TCM data transfers.
//              CSR Slave port for CPU configuration + Master port for data moves.
//              Ref: ÖTR Bölüm 3.2.8
// 
//////////////////////////////////////////////////////////////////////////////////

module dma_controller (
    input  logic        clk,
    input  logic        rst_n,

    // --- AXI4-Lite Slave - CSR Config (0x4007_0000) ---
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // --- AXI4-Lite Master - Data Transfer Port ---
    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    // --- Kesme Çıkışı (Interrupt) ---
    output logic        irq_o
);

    // =========================================================================
    // CSR Yazmaç Ofsetleri
    // =========================================================================
    localparam logic [4:0] REG_DMA_CTRL     = 5'h00; // [0] Start, [1] Reset
    localparam logic [4:0] REG_DMA_STATUS   = 5'h04; // [0] Busy, [1] Done, [2] Error
    localparam logic [4:0] REG_DMA_SRC_ADDR = 5'h08; // Kaynak adresi
    localparam logic [4:0] REG_DMA_DST_ADDR = 5'h0C; // Hedef adresi
    localparam logic [4:0] REG_DMA_XFER_LEN = 5'h10; // Transfer uzunluğu (kelime)

    // =========================================================================
    // İç Yazmaçlar
    // =========================================================================
    logic [31:0] reg_ctrl;
    logic [31:0] reg_src_addr;
    logic [31:0] reg_dst_addr;
    logic [31:0] reg_xfer_len;

    logic        dma_busy;
    logic        dma_done;
    logic        dma_error;

    // Start pulse
    logic        start_pulse;
    logic        dma_reset;
    assign start_pulse = reg_ctrl[0];
    assign dma_reset   = reg_ctrl[1];

    // Interrupt: transfer tamamlandığında
    assign irq_o = dma_done;

    // =========================================================================
    // DMA Transfer FSM
    // =========================================================================
    typedef enum logic [2:0] {
        DMA_IDLE,
        DMA_READ_REQ,
        DMA_READ_WAIT,
        DMA_WRITE_REQ,
        DMA_WRITE_WAIT,
        DMA_DONE
    } dma_state_t;

    dma_state_t dma_state;

    logic [31:0] src_addr_q;    // Geçerli kaynak adresi
    logic [31:0] dst_addr_q;    // Geçerli hedef adresi
    logic [12:0] xfer_cnt;      // Kalan kelime sayısı
    logic [31:0] read_data_q;   // Okunan veri tampon

    // AXI Master varsayılan değerleri
    always_comb begin
        m_axi_awaddr  = dst_addr_q;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = read_data_q;
        m_axi_wstrb   = 4'hF;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = src_addr_q;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        case (dma_state)
            DMA_READ_REQ: begin
                m_axi_arvalid = 1'b1;
            end
            DMA_READ_WAIT: begin
                m_axi_rready  = 1'b1;
            end
            DMA_WRITE_REQ: begin
                m_axi_awvalid = 1'b1;
                m_axi_wvalid  = 1'b1;
            end
            DMA_WRITE_WAIT: begin
                m_axi_bready  = 1'b1;
            end
            default: ;
        endcase
    end

    // DMA Transfer FSM - Sıralı Mantık
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_state    <= DMA_IDLE;
            dma_busy     <= 1'b0;
            dma_done     <= 1'b0;
            dma_error    <= 1'b0;
            src_addr_q   <= 32'b0;
            dst_addr_q   <= 32'b0;
            xfer_cnt     <= 13'b0;
            read_data_q  <= 32'b0;
        end else if (dma_reset) begin
            dma_state    <= DMA_IDLE;
            dma_busy     <= 1'b0;
            dma_done     <= 1'b0;
            dma_error    <= 1'b0;
            src_addr_q   <= 32'b0;
            dst_addr_q   <= 32'b0;
            xfer_cnt     <= 13'b0;
            read_data_q  <= 32'b0;
        end else begin
            case (dma_state)
                DMA_IDLE: begin
                    dma_busy <= 1'b0;
                    if (start_pulse) begin
                        dma_state   <= DMA_READ_REQ;
                        dma_busy    <= 1'b1;
                        dma_done    <= 1'b0;
                        dma_error   <= 1'b0;
                        src_addr_q  <= reg_src_addr;
                        dst_addr_q  <= reg_dst_addr;
                        xfer_cnt    <= reg_xfer_len[12:0];
                        $display("[%0t] [DMA] Transfer başladı: src=0x%h, dst=0x%h, len=%0d words",
                                 $time, reg_src_addr, reg_dst_addr, reg_xfer_len[12:0]);
                    end
                end

                DMA_READ_REQ: begin
                    // AR kanalından okuma isteği gönder
                    if (m_axi_arready) begin
                        dma_state <= DMA_READ_WAIT;
                    end
                end

                DMA_READ_WAIT: begin
                    // R kanalından veri bekle
                    if (m_axi_rvalid) begin
                        read_data_q <= m_axi_rdata;
                        if (m_axi_rresp != 2'b00) begin
                            dma_error <= 1'b1;
                        end
                        dma_state <= DMA_WRITE_REQ;
                    end
                end

                DMA_WRITE_REQ: begin
                    // AW+W kanallarından yazma isteği gönder
                    if (m_axi_awready && m_axi_wready) begin
                        dma_state <= DMA_WRITE_WAIT;
                    end
                end

                DMA_WRITE_WAIT: begin
                    // B kanalından yazma yanıtı bekle
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) begin
                            dma_error <= 1'b1;
                        end
                        // Adres güncelle ve sonraki kelimeye geç
                        src_addr_q <= src_addr_q + 32'd4;
                        dst_addr_q <= dst_addr_q + 32'd4;
                        if (xfer_cnt <= 13'd1) begin
                            dma_state <= DMA_DONE;
                        end else begin
                            xfer_cnt  <= xfer_cnt - 13'd1;
                            dma_state <= DMA_READ_REQ;
                        end
                    end
                end

                DMA_DONE: begin
                    dma_busy  <= 1'b0;
                    dma_done  <= 1'b1;
                    dma_state <= DMA_IDLE;
                    $display("[%0t] [DMA] Transfer tamamlandı.", $time);
                end

                default: dma_state <= DMA_IDLE;
            endcase
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - CSR Yazma Kanalı
    // =========================================================================
    logic [31:0] aw_addr_lat;
    logic        aw_valid_lat;
    logic [31:0] w_data_lat;
    logic        w_valid_lat;
    logic        do_write;

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
            reg_ctrl      <= 32'b0;
            reg_src_addr  <= 32'b0;
            reg_dst_addr  <= 32'b0;
            reg_xfer_len  <= 32'b0;
        end else begin
            // Start darbesini otomatik sıfırla
            if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0;

            // AW Handshake
            if (s_axi_awvalid && !aw_valid_lat) begin
                s_axi_awready <= 1'b1;
                aw_addr_lat   <= s_axi_awaddr;
                aw_valid_lat  <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
            end

            // W Handshake
            if (s_axi_wvalid && !w_valid_lat) begin
                s_axi_wready <= 1'b1;
                w_data_lat   <= s_axi_wdata;
                w_valid_lat  <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end

            // B Channel ve Yazmaç Atamaları
            if (do_write) begin
                aw_valid_lat <= 1'b0;
                w_valid_lat  <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;

                case (aw_addr_lat[4:0])
                    REG_DMA_CTRL:     reg_ctrl     <= w_data_lat;
                    REG_DMA_SRC_ADDR: reg_src_addr <= w_data_lat;
                    REG_DMA_DST_ADDR: reg_dst_addr <= w_data_lat;
                    REG_DMA_XFER_LEN: reg_xfer_len <= w_data_lat;
                    default: ;
                endcase
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - CSR Okuma Kanalı
    // =========================================================================
    logic [31:0] ar_addr_lat;
    logic        ar_valid_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= '0;
            ar_valid_lat  <= 1'b0;
            ar_addr_lat   <= '0;
        end else begin
            // AR Handshake
            if (s_axi_arvalid && !ar_valid_lat) begin
                s_axi_arready <= 1'b1;
                ar_addr_lat   <= s_axi_araddr;
                ar_valid_lat  <= 1'b1;
            end else begin
                s_axi_arready <= 1'b0;
            end

            // R Channel
            if (ar_valid_lat && !s_axi_rvalid) begin
                ar_valid_lat <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;

                case (ar_addr_lat[4:0])
                    REG_DMA_CTRL:     s_axi_rdata <= reg_ctrl;
                    REG_DMA_STATUS:   s_axi_rdata <= {29'b0, dma_error, dma_done, dma_busy};
                    REG_DMA_SRC_ADDR: s_axi_rdata <= reg_src_addr;
                    REG_DMA_DST_ADDR: s_axi_rdata <= reg_dst_addr;
                    REG_DMA_XFER_LEN: s_axi_rdata <= reg_xfer_len;
                    default:          s_axi_rdata <= 32'b0;
                endcase
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
