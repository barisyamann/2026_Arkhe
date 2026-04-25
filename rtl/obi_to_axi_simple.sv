`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.04.2026 00:29:47
// Design Name: 
// Module Name: obi_to_axi_simple
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module obi_to_axi_simple (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI Tarafı (İşlemciye bağlanır)
    input  logic        obi_req_i,
    output logic        obi_gnt_o,
    input  logic [31:0] obi_addr_i,
    input  logic        obi_we_i,
    input  logic [3:0]  obi_be_i,
    input  logic [31:0] obi_wdata_i,
    output logic [31:0] obi_rdata_o,
    output logic        obi_rvalid_o,

    // AXI-Lite Tarafı (Hafızaya/Kavşağa bağlanır)
    output logic        axi_req_o,
    input  logic        axi_gnt_i,
    output logic [31:0] axi_addr_o,
    output logic        axi_we_o,
    output logic [3:0]  axi_be_o,
    output logic [31:0] axi_wdata_o,
    input  logic [31:0] axi_rdata_i,
    input  logic        axi_rvalid_i
);
    // Bu basit köprü sinyalleri sadece birbirine aktarır (Direct mapping)
    assign axi_req_o    = obi_req_i;
    assign obi_gnt_o    = axi_gnt_i;
    assign axi_addr_o   = obi_addr_i;
    assign axi_we_o     = obi_we_i;
    assign axi_be_o     = obi_be_i;
    assign axi_wdata_o  = obi_wdata_i;
    assign obi_rdata_o  = axi_rdata_i;
    assign obi_rvalid_o = axi_rvalid_i;

endmodule