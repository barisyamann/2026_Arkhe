`timescale 1ns / 1ps
// Description: AXI4-Lite Slave register interface for the NPU.
//              Provides control/status signals and configures memory offsets.
//              Implements sticky DONE and interrupt clearing mechanisms.

module npu_csr (
    input  logic        clk,
    input  logic        rst_n,

    // --- AXI4-Lite Slave Arayüzü ---
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

    // --- Compute Engine Kontrol Sinyalleri ---
    output logic        start_o,
    output logic        npu_reset_o,
    output logic [12:0] in_addr_o,
    output logic [12:0] out_addr_o,

    // --- Compute Engine Durum Sinyalleri ---
    input  logic        busy_i,
    input  logic        done_i,
    input  logic [1:0]  class_in,

    // --- Kesme Çıkışı ---
    output logic        irq_o
);

    // Register Offsets
    localparam logic [4:0] REG_CTRL       = 5'h00; // 0x00
    localparam logic [4:0] REG_STATUS     = 5'h04; // 0x04
    localparam logic [4:0] REG_IN_ADDR    = 5'h08; // 0x08
    localparam logic [4:0] REG_OUT_ADDR   = 5'h0C; // 0x0C
    localparam logic [4:0] REG_CLASS_OUT  = 5'h10; // 0x10

    // Yazmaç Değişkenleri
    logic        reg_start;
    logic        reg_npu_reset;
    logic        reg_irq_enable;
    logic [31:0] reg_in_addr;
    logic [31:0] reg_out_addr;
    
    // Sticky done ve interrupt mantığı
    logic        done_sticky;
    logic        irq_clear_pulse;

    assign start_o      = reg_start;
    assign npu_reset_o  = reg_npu_reset;
    assign in_addr_o    = reg_in_addr[12:0];
    assign out_addr_o   = reg_out_addr[12:0];

    // Status register mapping: Bit 0 = BUSY, Bit 1 = DONE, Bit 2 = IRQ_STATUS
    logic [31:0] reg_status;
    assign reg_status = {29'b0, (done_sticky && reg_irq_enable), done_sticky, busy_i};

    // Kesme Çıkışı
    assign irq_o = done_sticky && reg_irq_enable;

    // Sticky done saklayıcısı kontrolü
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_sticky <= 1'b0;
        end else if (reg_npu_reset || irq_clear_pulse || reg_start) begin
            done_sticky <= 1'b0;
        end else if (done_i) begin
            done_sticky <= 1'b1;
        end
    end

    // --- AXI4-Lite Yazma İşlemleri (Write Channel) ---
    logic [31:0] aw_addr_lat;
    logic        aw_valid_lat;
    logic [31:0] w_data_lat;
    logic        w_valid_lat;
    logic        do_write;

    assign do_write = aw_valid_lat && w_valid_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            aw_valid_lat    <= 1'b0;
            w_valid_lat     <= 1'b0;
            aw_addr_lat     <= '0;
            w_data_lat      <= '0;
            reg_start       <= 1'b0;
            reg_npu_reset   <= 1'b0;
            reg_irq_enable  <= 1'b0;
            irq_clear_pulse <= 1'b0;
            reg_in_addr     <= 32'b0;
            reg_out_addr    <= 32'h0000_1DAC; // Varsayılan 7600 offset (TCM çıkış adresi)
        end else begin
            // Tek döngülük kontrol sinyallerini otomatik temizle
            if (reg_start)       reg_start       <= 1'b0;
            if (reg_npu_reset)   reg_npu_reset   <= 1'b0;
            if (irq_clear_pulse) irq_clear_pulse <= 1'b0;

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

            // B Channel ve Yazmaç Değer Atamaları
            if (do_write) begin
                aw_valid_lat <= 1'b0;
                w_valid_lat  <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;

                $display("[%0t] [NPU_CSR WRITE] addr=0x%h, data=0x%h", $time, aw_addr_lat, w_data_lat);

                case (aw_addr_lat[4:0])
                    REG_CTRL: begin
                        reg_start       <= w_data_lat[0];
                        reg_npu_reset   <= w_data_lat[1];
                        irq_clear_pulse <= w_data_lat[2];
                        reg_irq_enable  <= w_data_lat[3];
                    end
                    REG_IN_ADDR:  reg_in_addr  <= w_data_lat;
                    REG_OUT_ADDR: reg_out_addr <= w_data_lat;
                    default:;
                endcase
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // --- AXI4-Lite Okuma İşlemleri (Read Channel) ---
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

            // R Channel ve Yazmaç Değer Okumaları
            if (ar_valid_lat && !s_axi_rvalid) begin
                ar_valid_lat <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;

                case (ar_addr_lat[4:0])
                    REG_CTRL:      s_axi_rdata <= {28'b0, reg_irq_enable, 1'b0, reg_npu_reset, reg_start};
                    REG_STATUS:    s_axi_rdata <= reg_status;
                    REG_IN_ADDR:   s_axi_rdata <= reg_in_addr;
                    REG_OUT_ADDR:  s_axi_rdata <= reg_out_addr;
                    REG_CLASS_OUT: s_axi_rdata <= {30'b0, class_in};
                    default:       s_axi_rdata <= 32'b0;
                endcase

                $display("[%0t] [NPU_CSR READ] addr=0x%h, status=0x%h", $time, ar_addr_lat, reg_status);
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
