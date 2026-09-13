`timescale 1ns/1ps
// =============================================================================
// AXI W KANALI VERI YAKALAMA - CEVRE BIRIMLERI  (10 Eylul 2026)
//
// NEDEN BU TEST VAR
//   sram_module'de bulunan W kanali veri kaybi hatasi, ayni KALIPLA
//   uart_peripheral ve uart_stream_peripheral'da da vardi (tarama ile
//   bulundu, sonda ile olculdu):
//
//       READY'ler BAGIMSIZ ve gecikmeli yukseliyor
//       + yazma `aw_active_r && w_active_r` olunca yapiliyor
//       + o an CANLI s_axil_wdata ornekleniyor
//       = W once gelirse, AW gelene kadar master veriyi degistirebilir
//
//   Olculen: CPB'ye 0x000000AB yazilmasi gerekirken 0xFFFFFFFF yazildi.
//
//   Bu testler duzeltmenin kalici oldugunu ve ileride geri gelmedigini
//   garanti eder. Duzeltme geri alindiginda BASARISIZ olmalidirlar.
// =============================================================================
module tb_axi_w_yakalama;

  reg clk = 0; always #10 clk = ~clk;
  reg rst_n = 0;
  integer hata = 0, denetim = 0;

  // --- ortak AXI surucu sinyalleri ---
  reg  [31:0] awaddr = 0, wdata = 0;
  reg  [3:0]  wstrb = 4'hF;
  reg         awvalid = 0, wvalid = 0, bready = 1;

  // uart_peripheral
  wire u1_awready, u1_wready, u1_bvalid, u1_arready, u1_rvalid, u1_txd, u1_irq;
  wire [1:0] u1_bresp, u1_rresp; wire [31:0] u1_rdata;
  uart_peripheral u1 (.clk(clk), .rst_n(rst_n),
    .uart_rxd(1'b1), .uart_txd(u1_txd), .uart_irq(u1_irq),
    .s_axil_awaddr(awaddr[7:0]), .s_axil_awvalid(awvalid), .s_axil_awready(u1_awready),
    .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(u1_wready),
    .s_axil_bresp(u1_bresp), .s_axil_bvalid(u1_bvalid), .s_axil_bready(bready),
    .s_axil_araddr(8'h0), .s_axil_arvalid(1'b0), .s_axil_arready(u1_arready),
    .s_axil_rdata(u1_rdata), .s_axil_rresp(u1_rresp), .s_axil_rvalid(u1_rvalid), .s_axil_rready(1'b1));

  // uart_stream_peripheral
  wire u2_awready, u2_wready, u2_bvalid, u2_arready, u2_rvalid, u2_txd, u2_irq;
  wire [1:0] u2_bresp, u2_rresp; wire [31:0] u2_rdata;
  uart_stream_peripheral u2 (.clk(clk), .rst_n(rst_n),
    .uart_rxd(1'b1), .uart_txd(u2_txd), .uart_stream_irq(u2_irq),
    .fifo_empty(), .fifo_full(),
    .s_axil_awaddr(awaddr[7:0]), .s_axil_awvalid(awvalid), .s_axil_awready(u2_awready),
    .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(u2_wready),
    .s_axil_bresp(u2_bresp), .s_axil_bvalid(u2_bvalid), .s_axil_bready(bready),
    .s_axil_araddr(8'h0), .s_axil_arvalid(1'b0), .s_axil_arready(u2_arready),
    .s_axil_rdata(u2_rdata), .s_axil_rresp(u2_rresp), .s_axil_rvalid(u2_rvalid), .s_axil_rready(1'b1));

  task denetle(input [255:0] ad, input [31:0] gelen, input [31:0] beklenen);
    begin
      denetim = denetim + 1;
      if (gelen === beklenen) $display("      [OK]   %0s = 0x%08h", ad, gelen);
      else begin
        hata = hata + 1;
        $display("      [HATA] %0s - beklenen 0x%08h, gelen 0x%08h", ad, beklenen, gelen);
      end
    end
  endtask

  // W once gonderir, veriyi bozar, sonra AW gonderir.
  // Iki cevre birimi ayni sinyalleri paylastigi icin tek gecis her
  // ikisini birden uyarir.
  task w_once_sonra_aw(input [7:0] adres, input [31:0] veri, input [31:0] bozuk);
    integer g;
    begin
      // W kanali
      @(negedge clk); wdata = veri; wstrb = 4'hF; wvalid = 1;
      @(negedge clk);
      g = 0; while (!(u1_wready && u2_wready) && g < 30) begin @(negedge clk); g = g + 1; end
      @(negedge clk); wvalid = 0;
      // AXI'ye gore artik WDATA serbest - BOZ
      @(negedge clk); wdata = bozuk; wstrb = 4'hF;
      // AW kanali
      @(negedge clk); awaddr = {24'h0, adres}; awvalid = 1;
      @(negedge clk);
      g = 0; while (!(u1_awready && u2_awready) && g < 30) begin @(negedge clk); g = g + 1; end
      @(negedge clk); awvalid = 0;
      repeat (4) @(negedge clk);
    end
  endtask

  initial begin
    $display("================================================================");
    $display(" AXI W KANALI VERI YAKALAMA - CEVRE BIRIMLERI");
    $display("================================================================");
    repeat (4) @(negedge clk); rst_n = 1; repeat (3) @(negedge clk);

    $display("  -- CPB yazmacina W-once yazma, ardindan WDATA bozuluyor");
    w_once_sonra_aw(8'h00, 32'h000000AB, 32'hFFFFFFFF);
    denetle("uart_peripheral CPB", u1.reg_cpb_r, 32'h000000AB);
    denetle("uart_stream CPB",     u2.reg_cpb_r, 32'h000000AB);

    $display("  -- STP yazmacina W-once yazma");
    w_once_sonra_aw(8'h04, 32'h00000001, 32'hDEADBEEF);
    denetle("uart_peripheral STP", u1.reg_stp_r, 32'h00000001);
    denetle("uart_stream STP",     u2.reg_stp_r, 32'h00000001);

    $display("================================================================");
    if (hata == 0) $display(" AXI W YAKALAMA TESTI GECTI - %0d denetim, 0 hata", denetim);
    else           $display(" AXI W YAKALAMA TESTI BASARISIZ - %0d hata", hata);
    $display("================================================================");
    $finish;
  end

  initial begin #300000; $display(" [HATA] zaman asimi"); $finish; end

endmodule
