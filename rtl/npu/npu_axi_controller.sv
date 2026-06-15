`timescale 1ns / 1ps
// Description: AXI4-Lite Slave controller for the 30 kB TCM memory interface.
//              Translates AXI4-Lite read/write transactions into dual-port RAM Port A signals.

module npu_axi_controller (
    input  logic        clk,
    input  logic        rst_n,

    // --- AXI4-Lite Slave - 30 kB Memory Interface ---
    input  logic [31:0] mem_awaddr,
    input  logic        mem_awvalid,
    output logic        mem_awready,
    input  logic [31:0] mem_wdata,
    input  logic [3:0]  mem_wstrb,
    input  logic        mem_wvalid,
    output logic        mem_wready,
    output logic [1:0]  mem_bresp,
    output logic        mem_bvalid,
    input  logic        mem_bready,
    input  logic [31:0] mem_araddr,
    input  logic        mem_arvalid,
    output logic        mem_arready,
    output logic [31:0] mem_rdata,
    output logic [1:0]  mem_rresp,
    output logic        mem_rvalid,
    input  logic        mem_rready,

    // --- Memory Port A Control Outputs ---
    output logic        ram_en_o,
    output logic [3:0]  ram_we_o,
    output logic [12:0] ram_addr_o,
    output logic [31:0] ram_wdata_o,
    input  logic [31:0] ram_rdata_i
);

    // --- AXI write/read channels internal signals ---
    logic [31:0] mem_aw_addr_lat;
    logic        mem_aw_valid_lat;
    logic [31:0] mem_w_data_lat;
    logic [3:0]  mem_wstrb_lat;
    logic        mem_w_valid_lat;
    logic        mem_do_write;
    logic [31:0] mem_ar_addr_lat;

    assign mem_do_write = mem_aw_valid_lat && mem_w_valid_lat;

    // FSM Read State Definition
    typedef enum logic [1:0] {
        R_IDLE    = 2'd0,
        R_MEM     = 2'd1,
        R_CAPTURE = 2'd2,
        R_RESP    = 2'd3
    } rstate_t;
    rstate_t rstate;

    // RAM Control Sinyalleri
    assign ram_en_o    = mem_do_write || (rstate == R_MEM);
    assign ram_we_o    = mem_do_write ? mem_wstrb_lat : 4'b0000;
    assign ram_wdata_o = mem_w_data_lat;

    // Adres dilimleme ve sınır güvenliği
    logic [12:0] byte_addr_write;
    logic [12:0] byte_addr_read;
    assign byte_addr_write = mem_aw_addr_lat[14:2];
    assign byte_addr_read  = mem_ar_addr_lat[14:2];

    assign ram_addr_o  = mem_do_write ? byte_addr_write : byte_addr_read;

    // AXI Write Kanalları
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_awready      <= 1'b0;
            mem_wready       <= 1'b0;
            mem_bvalid       <= 1'b0;
            mem_bresp        <= 2'b00;
            mem_aw_valid_lat <= 1'b0;
            mem_w_valid_lat  <= 1'b0;
            mem_aw_addr_lat  <= '0;
            mem_w_data_lat   <= '0;
            mem_wstrb_lat    <= '0;
        end else begin
            // AW Handshake
            if (mem_awvalid && !mem_aw_valid_lat) begin
                mem_awready      <= 1'b1;
                mem_aw_addr_lat  <= mem_awaddr;
                mem_aw_valid_lat <= 1'b1;
            end else begin
                mem_awready      <= 1'b0;
            end

            // W Handshake
            if (mem_wvalid && !mem_w_valid_lat) begin
                mem_wready      <= 1'b1;
                mem_w_data_lat  <= mem_wdata;
                mem_wstrb_lat   <= mem_wstrb;
                mem_w_valid_lat <= 1'b1;
            end else begin
                mem_wready      <= 1'b0;
            end

            // B Channel
            if (mem_do_write) begin
                mem_aw_valid_lat <= 1'b0;
                mem_w_valid_lat  <= 1'b0;
                mem_bvalid       <= 1'b1;
                mem_bresp        <= 2'b00;
            end

            if (mem_bvalid && mem_bready) begin
                mem_bvalid <= 1'b0;
            end
        end
    end

    // AXI Read Kanalları (FSM)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate           <= R_IDLE;
            mem_arready      <= 1'b0;
            mem_rvalid       <= 1'b0;
            mem_rresp        <= 2'b00;
            mem_rdata        <= '0;
            mem_ar_addr_lat  <= '0;
        end else begin
            case (rstate)
                R_IDLE: begin
                    mem_arready <= 1'b1;
                    if (mem_arvalid && mem_arready) begin
                        mem_ar_addr_lat <= mem_araddr;
                        mem_arready     <= 1'b0;
                        rstate          <= R_MEM;
                    end
                end
                R_MEM: begin
                    rstate          <= R_CAPTURE;
                end
                R_CAPTURE: begin
                    mem_rdata  <= ram_rdata_i;
                    mem_rvalid <= 1'b1;
                    mem_rresp  <= 2'b00;
                    rstate     <= R_RESP;
                end
                R_RESP: begin
                    if (mem_rready) begin
                        mem_rvalid  <= 1'b0;
                        mem_arready <= 1'b1;
                        rstate      <= R_IDLE;
                    end
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

endmodule
