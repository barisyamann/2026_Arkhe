`timescale 1ns/1ps
// =============================================================================
// SRAM W KANALI VERI YAKALAMA TESTI  (10 Eylul 2026)
//
// NEDEN BU TEST VAR
//   sram_module, W el sikismasinda yalnizca `w_active` bayragini kuruyor,
//   WDATA/WSTRB'yi kaydetmiyordu. Fiziksel yazma ise
//       wr_en = aw_active && w_active && !bvalid
//   kosuluyla CANLI sinyalleri ornekliyordu.
//
//   AXI4-Lite'ta AW ve W BAGIMSIZ kanallardir. W once gelirse el sikismasi
//   biter, WREADY duser ve master o andan itibaren WDATA'yi degistirmekte
//   SERBESTTIR. AW bir cevrim sonra gelince YANLIS veri yazilirdi.
//
//   Mevcut 21/21 regresyon ve %100 islevsel kapsama bu sinir durumunu
//   KAPSAMIYORDU: testler hep AW ve W'yi birlikte suruyordu.
//
// EL SIKISMASI ZAMANLAMASI
//   RTL, READY'yi bir cevrim gecikmeli yukseltir ve el sikismasinin
//   gerceklestigi posedge'de tekrar dusurur. VALID, READY'nin yuksek
//   goruldugu negedge'i TAKIP EDEN negedge'e kadar yuksek kalmalidir.
//   Bu yapi olculerek dogrulandi.
// =============================================================================
module tb_sram_w_yakalama;

  reg clk = 0; always #10 clk = ~clk;
  reg rst_n = 0;

  reg  [31:0] awaddr = 0, wdata = 0, araddr = 0;
  reg  [3:0]  wstrb = 4'hF;
  reg         awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
  wire        awready, wready, bvalid, arready, rvalid;
  wire [1:0]  bresp, rresp;
  wire [31:0] rdata;

  integer hata = 0, denetim = 0;

  sram_module #(.RAM_DEPTH(2048)) dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
    .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
    .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
    .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
    .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready));

  task denetle(input [255:0] ad, input kosul, input [31:0] beklenen, input [31:0] gelen);
    begin
      denetim = denetim + 1;
      if (kosul) $display("      [OK]   %0s = 0x%08h", ad, gelen);
      else begin
        hata = hata + 1;
        $display("      [HATA] %0s - beklenen 0x%08h, gelen 0x%08h", ad, beklenen, gelen);
      end
    end
  endtask

  // VALID'i READY gorulene kadar yuksek tutar, sonra bir negedge daha bekler.
  task w_gonder(input [31:0] veri, input [3:0] maske);
    begin
      @(negedge clk); wdata = veri; wstrb = maske; wvalid = 1;
      @(negedge clk);
      while (!wready) @(negedge clk);
      @(negedge clk);
      wvalid = 0;
    end
  endtask

  task aw_gonder(input [31:0] adres);
    begin
      @(negedge clk); awaddr = adres; awvalid = 1;
      @(negedge clk);
      while (!awready) @(negedge clk);
      @(negedge clk);
      awvalid = 0;
    end
  endtask

  task yazma_bitir();
    integer g;
    begin
      g = 0;
      while (!bvalid && g < 40) begin @(negedge clk); g = g + 1; end
      @(negedge clk);
    end
  endtask

  task oku(input [31:0] adres, output [31:0] sonuc);
    integer g;
    begin
      @(negedge clk); araddr = adres; arvalid = 1;
      @(negedge clk);
      g = 0;
      while (!arready && g < 40) begin @(negedge clk); g = g + 1; end
      @(negedge clk);
      arvalid = 0;
      g = 0;
      while (!rvalid && g < 40) begin @(negedge clk); g = g + 1; end
      sonuc = rdata;
      @(negedge clk);
    end
  endtask

  reg [31:0] okunan;

  initial begin
    $display("================================================================");
    $display(" SRAM W KANALI VERI YAKALAMA TESTI");
    $display("================================================================");
    repeat (5) @(negedge clk);
    rst_n = 1;
    repeat (3) @(negedge clk);

    // --- 1) W ONCE, WDATA BOZULUR, sonra AW  (asil hata senaryosu) ---
    $display("  -- W once, ardindan WDATA bozulur, sonra AW gelir");
    w_gonder(32'h12345678, 4'hF);
    @(negedge clk); wdata = 32'hDEADC0DE; wstrb = 4'h0;   // AXI'ye gore SERBEST
    aw_gonder(32'h00000010);
    yazma_bitir();
    oku(32'h00000010, okunan);
    denetle("W-once: el sikismasindaki veri yazildi", okunan === 32'h12345678,
            32'h12345678, okunan);

    // --- 2) AW ONCE, sonra W ---
    $display("  -- AW once, sonra W");
    fork
      aw_gonder(32'h00000020);
      begin repeat (3) @(negedge clk); w_gonder(32'hA5A5A5A5, 4'hF); end
    join
    yazma_bitir();
    oku(32'h00000020, okunan);
    denetle("AW-once: dogru veri yazildi", okunan === 32'hA5A5A5A5,
            32'hA5A5A5A5, okunan);

    // --- 3) AYNI ANDA ---
    $display("  -- AW ve W ayni anda");
    fork aw_gonder(32'h00000030); w_gonder(32'hCAFEBABE, 4'hF); join
    yazma_bitir();
    oku(32'h00000030, okunan);
    denetle("es zamanli: dogru veri yazildi", okunan === 32'hCAFEBABE,
            32'hCAFEBABE, okunan);

    // --- 4) BYTE STROBE ---
    $display("  -- kismi yazma (byte strobe)");
    fork aw_gonder(32'h00000040); w_gonder(32'hFFFFFFFF, 4'hF); join
    yazma_bitir();
    fork aw_gonder(32'h00000040); w_gonder(32'h000000AA, 4'h1); join
    yazma_bitir();
    oku(32'h00000040, okunan);
    denetle("byte strobe: yalniz bayt0 degisti", okunan === 32'hFFFFFFAA,
            32'hFFFFFFAA, okunan);

    $display("================================================================");
    if (hata == 0) $display(" SRAM W YAKALAMA TESTI GECTI - %0d denetim, 0 hata", denetim);
    else           $display(" SRAM W YAKALAMA TESTI BASARISIZ - %0d hata", hata);
    $display("================================================================");
    $finish;
  end

  initial begin
    #500000;
    $display(" [HATA] zaman asimi");
    $finish;
  end

endmodule
