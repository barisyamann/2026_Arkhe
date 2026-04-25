`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.04.2026 00:36:00
// Design Name: 
// Module Name: axi_lite_interconnect
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


module axi_lite_interconnect (
    // İşlemciden Gelen AXI Hattı (Master)
    input  logic [31:0] m_addr_i,
    input  logic        m_req_i,
    output logic        m_gnt_o,
    
    // ROM Hattı (Slave 0)
    output logic        s0_req_o,
    input  logic        s0_gnt_i,
    
    // RAM Hattı (Slave 1)
    output logic        s1_req_o,
    input  logic        s1_gnt_i,
    
    // GPIO Hattı (Slave 2)
    output logic        s2_req_o,
    input  logic        s2_gnt_i
);

    // ADRES ÇÖZME MANTIĞI (Address Decoding)
    always_comb begin
        // Başlangıçta herkesi sustur
        s0_req_o = 1'b0;
        s1_req_o = 1'b0;
        s2_req_o = 1'b0;
        m_gnt_o  = 1'b0;

        if (m_req_i) begin
            case (m_addr_i[31:28]) // Adresin en solundaki rakama bakıyoruz
                4'h0: begin // 0x0... -> ROM
                    s0_req_o = m_req_i;
                    m_gnt_o  = s0_gnt_i;
                end
                4'h1: begin // 0x1... -> RAM
                    s1_req_o = m_req_i;
                    m_gnt_o  = s1_gnt_i;
                end
                4'h2: begin // 0x2... -> GPIO
                    s2_req_o = m_req_i;
                    m_gnt_o  = s2_gnt_i;
                end
                default: m_gnt_o = 1'b1; // Hatalı adres gelirse işlemciyi kilitleme, onay ver geç.
            endcase
        end
    end

endmodule