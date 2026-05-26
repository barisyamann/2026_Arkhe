`timescale 1ns / 1ps

module tb_qspi_mock;
  logic clk = 0;
  logic aresetn = 0;

  // AXI4-Lite Sinyalleri
  logic [31:0] awaddr, wdata, araddr, rdata;
  logic awvalid, wvalid, bready, arvalid, rready;
  logic awready, wready, bvalid, arready, rvalid;
  logic [1:0]  bresp, rresp;

  // QSPI Fiziksel Sinyalleri
  wire spi_sck, spi_cs_n;
  wire spi_io0, spi_io1, spi_io2, spi_io3;
  logic irq;

  // Saat Üretimi
  always #10 clk = ~clk;

  // AXI4-Lite Kurşun Geçirmez Yazma Görevi
  task axi_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      awaddr <= addr; awvalid <= 1;
      while (!awready) @(posedge clk); 
      awvalid <= 0;

      @(posedge clk);
      wdata <= data; wvalid <= 1;
      while (!wready) @(posedge clk);
      wvalid <= 0;

      @(posedge clk);
      bready <= 1;
      while (!bvalid) @(posedge clk);
      bready <= 0;
    end
  endtask

  // Test Senaryosu
  initial begin
    aresetn = 0;
    awvalid = 0; wvalid = 0; bready = 0;
    arvalid = 0; rready = 0;

    #100 aresetn = 1;
    #100;

    $display("--- QSPI Master Yeni Mimari Testi Baslar ---");

    // 1. Aşama: Adres Yazmacına (ADR) hedef adresi yaz
    axi_write(32'h0000_0004, 32'h0012_3400); 

    // 2. Aşama: Veri Yazmacına (DR) TX FIFO verisini yaz
    axi_write(32'h0000_0008, 32'h0000_00AA); 

    // 3. Aşama: CCR Yazmacına komutu gönder ve motoru ateşle
    // Page Program (0x02) komutu, x1 mod, Write aktif
    axi_write(32'h0000_0000, 32'h8000_0502); 

    #5000 $finish;
  end

  // Yeni Monolitik QSPI Master Modülü
  qspi_master #(
      .FIFO_DEPTH(64),
      .AXI_AW(32),
      .AXI_DW(32)
  ) UUT (
      .clk           (clk),
      .rst_n         (aresetn),
      .s_axi_awaddr  (awaddr),
      .s_axi_awvalid (awvalid),
      .s_axi_awready (awready),
      .s_axi_wdata   (wdata),
      .s_axi_wstrb   (4'hF),
      .s_axi_wvalid  (wvalid),
      .s_axi_wready  (wready),
      .s_axi_bresp   (bresp),
      .s_axi_bvalid  (bvalid),
      .s_axi_bready  (bready),
      .s_axi_araddr  (32'h0),
      .s_axi_arvalid (1'b0),
      .s_axi_arready (arready),
      .s_axi_rdata   (rdata),
      .s_axi_rresp   (rresp),
      .s_axi_rvalid  (rvalid),
      .s_axi_rready  (1'b1),
      .qspi_sck      (spi_sck),
      .qspi_cs_n     (spi_cs_n),
      .qspi_io0      (spi_io0),
      .qspi_io1      (spi_io1),
      .qspi_io2      (spi_io2),
      .qspi_io3      (spi_io3),
      .irq           (irq)
  );

  // Gerçek Micron Flash Modeli (Doğru portlarla)
  MT25QL256ABA8E12 flash_memory (
      .S   (spi_cs_n),
      .C   (spi_sck),
      .DQ0 (spi_io0),
      .DQ1 (spi_io1),
      .Vcc (1'b1)
  );

endmodule