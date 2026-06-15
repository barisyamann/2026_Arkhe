`timescale 1ns/1ps

module axil_protocol_checker (
    input logic clk,
    input logic rst_n,

    // Write Address Channel
    input logic [31:0] awaddr,
    input logic        awvalid,
    input logic        awready,

    // Write Data Channel
    input logic [31:0] wdata,
    input logic [3:0]  wstrb,
    input logic        wvalid,
    input logic        wready,

    // Write Response Channel
    input logic [1:0]  bresp,
    input logic        bvalid,
    input logic        bready,

    // Read Address Channel
    input logic [31:0] araddr,
    input logic        arvalid,
    input logic        arready,

    // Read Data Channel
    input logic [31:0] rdata,
    input logic [1:0]  rresp,
    input logic        rvalid,
    input logic        rready
);

    // =========================================================================
    // SVA (SystemVerilog Assertions) AXI4-Lite Kuralları
    // =========================================================================

    // 1. Reset Durumu: Reset aktifken (rst_n = 0) tüm Valid sinyalleri 0 olmalıdır.
    property p_reset_val;
        @(posedge clk) !rst_n |-> (!awvalid && !wvalid && !bvalid && !arvalid && !rvalid);
    endproperty
    assert_reset_val: assert property (p_reset_val)
        else $error("[AXIL_ERR] Reset durumunda valid sinyalleri pasif değil!");

    // 2. Write Address Stability: awvalid 1 iken awready gelene kadar awaddr değişmemelidir.
    property p_awaddr_stable;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> ($stable(awaddr) && awvalid);
    endproperty
    assert_awaddr_stable: assert property (p_awaddr_stable)
        else $error("[AXIL_ERR] awvalid yuksek ve awready dusukken awaddr degisti!");

    // 3. Write Data Stability: wvalid 1 iken wready gelene kadar wdata ve wstrb değişmemelidir.
    property p_wdata_stable;
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> ($stable(wdata) && $stable(wstrb) && wvalid);
    endproperty
    assert_wdata_stable: assert property (p_wdata_stable)
        else $error("[AXIL_ERR] wvalid yuksek ve wready dusukken wdata veya wstrb degisti!");

    // 4. Read Address Stability: arvalid 1 iken arready gelene kadar araddr değişmemelidir.
    property p_araddr_stable;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> ($stable(araddr) && arvalid);
    endproperty
    assert_araddr_stable: assert property (p_araddr_stable)
        else $error("[AXIL_ERR] arvalid yuksek ve arready dusukken araddr degisti!");

    // 5. Read Data Stability: rvalid 1 iken rready gelene kadar rdata ve rresp değişmemelidir.
    property p_rdata_stable;
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> ($stable(rdata) && $stable(rresp) && rvalid);
    endproperty
    assert_rdata_stable: assert property (p_rdata_stable)
        else $error("[AXIL_ERR] rvalid yuksek ve rready dusukken rdata veya rresp degisti!");

    // 6. Write Response Stability: bvalid 1 iken bready gelene kadar bresp değişmemelidir.
    property p_bresp_stable;
        @(posedge clk) disable iff (!rst_n)
        (bvalid && !bready) |=> ($stable(bresp) && bvalid);
    endproperty
    assert_bresp_stable: assert property (p_bresp_stable)
        else $error("[AXIL_ERR] bvalid yuksek ve bready dusukken bresp degisti!");

endmodule
