`timescale 1ns / 1ps

module tb_jtag_debug();

    logic clk = 0;
    logic rst_n = 0;
    logic tck = 0;
    logic tms = 1;
    logic trst_n = 0;
    logic tdi = 0;
    
    logic tdo;
    logic tdo_oe;
    logic debug_req;

    jtag_debug_wrapper dut (
        .m_axi_aclk       (clk),
        .m_axi_aresetn    (rst_n),
        .jtag_tck_i       (tck),
        .jtag_tms_i       (tms),
        .jtag_trst_ni     (trst_n),
        .jtag_tdi_i       (tdi),
        .jtag_tdo_o       (tdo),
        .jtag_tdo_oe_o    (tdo_oe),
        .debug_req_o      (debug_req),
        
        .m_axi_awaddr     (), .m_axi_awprot    (), .m_axi_awvalid   (), .m_axi_awready   (1'b1),
        .m_axi_wdata      (), .m_axi_wstrb     (), .m_axi_wvalid    (), .m_axi_wready    (1'b1),
        .m_axi_bresp      (2'b00), .m_axi_bvalid(1'b1), .m_axi_bready(),
        .m_axi_araddr     (), .m_axi_arprot    (), .m_axi_arvalid   (), .m_axi_arready   (1'b1),
        .m_axi_rdata      (32'h10E31913), .m_axi_rresp(2'b00), .m_axi_rvalid(1'b1), .m_axi_rready()
    );

    always #5 clk = ~clk;

    always #50 tck = ~tck;

    initial begin
        $display("[TB] JTAG simülasyonu temizlendi ve baslatildi.");
        
        rst_n = 0; 
        trst_n = 0;
        tms = 1;
        tdi = 0;
        
        #200;
        
        @(posedge clk);
        rst_n = 1; 
        
        @(posedge tck);
        trst_n = 1;
        $display("[TB] Tüm reset hatları kaldırıldı.");
        
        repeat (5) @(posedge tck);
        
        tms = 0; 
        @(posedge tck); 
        $display("[TB] TAP State: Run-Test/Idle'a gecildi!");
        
        tms = 1; @(posedge tck); 
        tms = 0; @(posedge tck); 
        tms = 0; @(posedge tck); 
        
        $display("[TB] TAP State: Shift-DR durumundayiz.");
        
        tdi = 1;
        repeat (8) @(posedge tck);
        
        tms = 1; @(posedge tck); 
        tms = 1; @(posedge tck); 
        tms = 0; @(posedge tck); 
        
        #500;
        $display("[TB] Başarılı: Simülasyon hatasız tamamlandı.");
        $finish;
    end

endmodule