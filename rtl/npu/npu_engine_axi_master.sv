`timescale 1ns / 1ps

// ============================================================================
// NPU Compute Engine -> AXI4-Lite Master Bridge
//
// Amac:
// Compute Engine'in yerel bellek isteklerini AXI4-Lite transaction'larina
// cevirmek.
//
// Daha sonra Compute Engine:
//   mem_en / mem_addr / mem_rdata
// yerine
//   req_valid / req_ready / rsp_valid
// mantigi ile bu modulu kullanacak.
//
// Bu modul NPU matematik islemlerini yapmaz.
// Sadece bellek erisim protokolunu yonetir.
// ============================================================================

module npu_engine_axi_master (
    input  logic        clk,
    input  logic        rst_n,

    // ------------------------------------------------------------------------
    // Compute Engine tarafindaki basit request/response arayuzu
    // ------------------------------------------------------------------------
    input  logic        req_valid_i,
    input  logic        req_write_i,
    input  logic [12:0] req_addr_i,      // TCM word address
    input  logic [31:0] req_wdata_i,
    input  logic [3:0]  req_wstrb_i,

    output logic        req_ready_o,

    output logic        rsp_valid_o,
    output logic [31:0] rsp_rdata_o,
    output logic [1:0]  rsp_resp_o,

    // ------------------------------------------------------------------------
    // AXI4-Lite Master arayuzu
    // ------------------------------------------------------------------------

    // Write Address Channel
    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    // Write Data Channel
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    // Write Response Channel
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    // Read Address Channel
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    // Read Data Channel
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    // FSM bir sonraki asamada eklenecek.

endmodule
