`timescale 1ns/1ps
module tb_sram_registered;
  reg clk=0; always #10 clk=~clk;
  reg rst_n=0;
  reg [31:0] awaddr=0,wdata=0,araddr=0;
  reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
  reg [3:0] wstrb=15;
  wire awready,wready,bvalid,arready,rvalid;
  wire [1:0] bresp,rresp;
  wire [31:0] rdata;
  reg [31:0] golden[0:2047];
  integer checks=0,accepted=0,responded=0,outstanding=0;
  sram_module dut(.clk(clk),.rst_n(rst_n),
    .s_axil_awaddr(awaddr),.s_axil_awvalid(awvalid),.s_axil_awready(awready),
    .s_axil_wdata(wdata),.s_axil_wstrb(wstrb),.s_axil_wvalid(wvalid),.s_axil_wready(wready),
    .s_axil_bresp(bresp),.s_axil_bvalid(bvalid),.s_axil_bready(bready),
    .s_axil_araddr(araddr),.s_axil_arvalid(arvalid),.s_axil_arready(arready),
    .s_axil_rdata(rdata),.s_axil_rresp(rresp),.s_axil_rvalid(rvalid),.s_axil_rready(rready));
  always @(posedge clk) begin
    if (!rst_n) outstanding=0;
    else begin
      if (arvalid && arready) begin accepted=accepted+1; outstanding=outstanding+1; end
      if (rvalid && outstanding!=1) $fatal(1,"Response without exactly one accepted request");
      if (rvalid && rready) begin responded=responded+1; outstanding=outstanding-1; end
    end
  end
  task automatic write_word(input integer word_addr,input reg[31:0] value,input reg[3:0] mask);
    integer j;
    begin
      @(negedge clk); awaddr=word_addr*4; wdata=value; wstrb=mask; awvalid=1; wvalid=1; bready=0;
      fork
        begin do @(posedge clk); while(!awready); @(negedge clk); awvalid=0; end
        begin do @(posedge clk); while(!wready); @(negedge clk); wvalid=0; end
      join
      wait(bvalid); if(bresp!==0) $fatal(1,"Write error");
      for(j=0;j<4;j=j+1) if(mask[j]) golden[word_addr][j*8+:8]=value[j*8+:8];
      @(negedge clk); bready=1; @(posedge clk); @(negedge clk); bready=0;
    end
  endtask
  task automatic read_word(input integer word_addr,input integer stalls);
    reg [31:0] expected;
    begin
      expected=golden[word_addr];
      @(negedge clk); araddr=word_addr*4; arvalid=1; rready=0;
      do @(posedge clk); while(!arready);
      @(negedge clk); arvalid=0; araddr=32'h1ffc;
      wait(rvalid); #1;
      if(rdata!==expected || rresp!==0) $fatal(1,"Read %0d expected %h got %h",word_addr,expected,rdata);
      repeat(stalls) begin
        @(negedge clk); araddr=araddr^32'h800;
        @(posedge clk); #1;
        if(!rvalid || rdata!==expected) $fatal(1,"Response changed under backpressure");
      end
      @(negedge clk); rready=1;
      @(posedge clk); @(negedge clk); rready=0; checks=checks+1;
    end
  endtask
  integer i,a;
  initial begin
    for(i=0;i<2048;i=i+1) golden[i]=0;
    repeat(3) @(negedge clk); rst_n=1;
    // All banks, boundary words, byte writes and varying response stalls.
    for(i=0;i<64;i=i+1) begin a=(i*193)%2048; write_word(a,32'hA5000000^(i*32'h10203),15); end
    for(i=0;i<4;i=i+1) begin
      write_word(i*512,32'h12345678+i,15);
      write_word(i*512+511,32'hCAFEBABE^i,15);
      write_word(i*512,32'hAABBCCDD,5);
    end
    for(i=0;i<64;i=i+1) read_word((i*193)%2048,i%7);
    for(i=0;i<4;i=i+1) begin read_word(i*512,3); read_word(i*512+511,2); end
    // Queue a second address while the first response is stalled.
    @(negedge clk); araddr=0; arvalid=1;
    do @(posedge clk); while(!arready);
    @(negedge clk); araddr=2048; // bank 1, held valid until it can be accepted
    wait(rvalid); #1;
    repeat(5) begin @(posedge clk); #1;
      if(arready || rdata!==golden[0]) $fatal(1,"Accepted a second read too early"); end
    @(negedge clk); rready=1; @(posedge clk);
    @(negedge clk); rready=0;
    do @(posedge clk); while(!arready);
    @(negedge clk); arvalid=0; araddr=0;
    wait(rvalid); #1; if(rdata!==golden[512]) $fatal(1,"Queued bank read failed");
    @(negedge clk); rready=1; @(posedge clk); @(negedge clk); rready=0;
    checks=checks+2;
    // Abort an accepted request by reset; no stale response may escape.
    araddr=4096; arvalid=1; do @(posedge clk); while(!arready);
    @(negedge clk); rst_n=0; arvalid=0;
    repeat(2) @(negedge clk); rst_n=1;
    repeat(3) begin @(posedge clk); #1; if(rvalid) $fatal(1,"Stale response after reset"); end
    read_word(1024,1);
    // Reset while a response is held.
    @(negedge clk); araddr=6144; arvalid=1;
    do @(posedge clk); while(!arready);
    @(negedge clk); arvalid=0; wait(rvalid);
    @(negedge clk); rst_n=0;
    repeat(2) @(negedge clk); rst_n=1;
    repeat(3) begin @(posedge clk); #1; if(rvalid) $fatal(1,"Held response survived reset"); end
    read_word(1536,0);
    if(outstanding!=0 || accepted-responded!=2) $fatal(1,"Request accounting mismatch");
    $display("PASS SRAM registered read: %0d checked reads, %0d accepted, %0d responses, 2 reset-aborted",checks,accepted,responded);
    $finish;
  end
  initial begin #1000000; $fatal(1,"Timeout"); end
endmodule
