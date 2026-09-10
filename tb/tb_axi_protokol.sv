`timescale 1ns/1ps
// =============================================================================
// AXI4-Lite PROTOKOL UYUM TESTI  (10 Eylul 2026)
//
// NEDEN BU TEST VAR
//   Mevcut 21 testin hicbiri protokolun SERBEST biraktigi durumlari
//   denemiyordu: hep AW ve W birlikte suruluyor, BREADY/RREADY hep
//   yuksek tutuluyordu. Bu bosluk yuzunden uc modulde W kanali veri
//   kaybi hatasi yillarca gorunmedi.
//
//   Bu test, AXI4-Lite'in izin verdigi ama bizim hic denemedigimiz
//   davranislari sinar:
//     1) Kanal bagimsizligi  - AW ve W farkli cevrimlerde
//     2) B kanali geri basinci - BREADY gecikirse BVALID beklemeli
//     3) R kanali geri basinci - RREADY gecikirse RVALID/RDATA sabit
//        kalmali (AXI: VALID kalkinca READY gelene kadar veri degismez)
//
//   Kanal bagimsizligi tb_sram_w_yakalama ve tb_axi_w_yakalama'da
//   ayrica ele alindigi icin burada geri basinca odaklanilir.
// =============================================================================
module tb_axi_protokol;

  reg clk = 0; always #10 clk = ~clk;
  reg rst_n = 0;
  integer hata = 0, denetim = 0;

  reg  [31:0] awaddr = 0, wdata = 0, araddr = 0;
  reg  [3:0]  wstrb = 4'hF;
  reg         awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
  wire        awready, wready, bvalid, arready, rvalid;
  wire [1:0]  bresp, rresp;
  wire [31:0] rdata;

  sram_module #(.RAM_DEPTH(2048)) dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
    .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
    .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
    .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
    .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready));

  task denetle(input [255:0] ad, input kosul);
    begin
      denetim = denetim + 1;
      if (kosul) $display("      [OK]   %0s", ad);
      else begin hata = hata + 1; $display("      [HATA] %0s", ad); end
    end
  endtask

  task yaz(input [31:0] adres, input [31:0] veri);
    integer g;
    begin
      @(negedge clk); awaddr = adres; awvalid = 1; wdata = veri; wstrb = 4'hF; wvalid = 1;
      @(negedge clk); g = 0;
      while (!(awready && wready) && g < 30) begin @(negedge clk); g = g + 1; end
      @(negedge clk); awvalid = 0; wvalid = 0;
    end
  endtask

  integer i, sayac; reg [31:0] ilk; reg sabit;

  initial begin
    $display("================================================================");
    $display(" AXI4-Lite PROTOKOL UYUM TESTI");
    $display("================================================================");
    repeat (4) @(negedge clk); rst_n = 1; repeat (3) @(negedge clk);

    // --- 1) B kanali geri basinci ---
    $display("  -- B kanali: BREADY gecikirse BVALID beklemeli");
    bready = 0;
    yaz(32'h10, 32'hAAAA5555);
    sayac = 0;
    for (i = 0; i < 10; i = i + 1) begin
      @(negedge clk);
      if (bvalid) sayac = sayac + 1;
    end
    denetle("BVALID, BREADY gelene kadar yuksek kaliyor", sayac >= 9);
    @(negedge clk); bready = 1;
    repeat (2) @(negedge clk);
    denetle("BREADY sonrasi BVALID dustu", bvalid === 1'b0);
    denetle("geri basinc altinda veri dogru yazildi", dut.ram[4] === 32'hAAAA5555);

    // --- 2) R kanali geri basinci ---
    $display("  -- R kanali: RREADY gecikirse RVALID/RDATA sabit kalmali");
    yaz(32'h20, 32'h12345678);
    repeat (4) @(negedge clk);
    rready = 0;
    @(negedge clk); araddr = 32'h20; arvalid = 1;
    @(negedge clk); i = 0;
    while (!arready && i < 30) begin @(negedge clk); i = i + 1; end
    @(negedge clk); arvalid = 0;
    i = 0;
    while (!rvalid && i < 30) begin @(negedge clk); i = i + 1; end
    denetle("RVALID geldi", rvalid === 1'b1);
    ilk = rdata; sabit = 1'b1;
    for (i = 0; i < 8; i = i + 1) begin
      @(negedge clk);
      if (!rvalid || rdata !== ilk) sabit = 1'b0;
    end
    denetle("RREADY dusukken RVALID/RDATA degismedi", sabit);
    denetle("okunan veri dogru", ilk === 32'h12345678);
    rready = 1;
    repeat (3) @(negedge clk);

    $display("================================================================");
    if (hata == 0) $display(" AXI PROTOKOL TESTI GECTI - %0d denetim, 0 hata", denetim);
    else           $display(" AXI PROTOKOL TESTI BASARISIZ - %0d hata", hata);
    $display("================================================================");
    $finish;
  end

  initial begin #400000; $display(" [HATA] zaman asimi"); $finish; end

endmodule
