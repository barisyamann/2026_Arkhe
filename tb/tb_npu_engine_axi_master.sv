`timescale 1ns / 1ps

module tb_npu_engine_axi_master;

    // ========================================================================
    // Clock / Reset
    // ========================================================================

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    // ========================================================================
    // Compute Engine side
    // ========================================================================

    logic        req_valid_i;
    logic        req_write_i;
    logic [12:0] req_addr_i;
    logic [31:0] req_wdata_i;
    logic [3:0]  req_wstrb_i;

    logic        req_ready_o;

    logic        rsp_valid_o;
    logic [31:0] rsp_rdata_o;
    logic [1:0]  rsp_resp_o;

    // ========================================================================
    // AXI4-Lite side
    // ========================================================================

    logic [31:0] m_axi_awaddr;
    logic        m_axi_awvalid;
    logic        m_axi_awready;

    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wvalid;
    logic        m_axi_wready;

    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;

    logic [31:0] m_axi_araddr;
    logic        m_axi_arvalid;
    logic        m_axi_arready;

    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rvalid;
    logic        m_axi_rready;

    integer error_count;

    // ========================================================================
    // DUT
    // ========================================================================

    npu_engine_axi_master #(
        .TCM_BASE_ADDR(32'h2001_0000)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),

        .req_valid_i    (req_valid_i),
        .req_write_i    (req_write_i),
        .req_addr_i     (req_addr_i),
        .req_wdata_i    (req_wdata_i),
        .req_wstrb_i    (req_wstrb_i),

        .req_ready_o    (req_ready_o),

        .rsp_valid_o    (rsp_valid_o),
        .rsp_rdata_o    (rsp_rdata_o),
        .rsp_resp_o     (rsp_resp_o),

        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),

        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),

        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),

        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),

        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // ========================================================================
    // Yardimci kontrol
    // ========================================================================

    task automatic check(
        input logic condition,
        input string message
    );
        begin
            if (!condition) begin
                $display("FAIL: %s", message);
                error_count = error_count + 1;
            end else begin
                $display("PASS: %s", message);
            end
        end
    endtask

    // ========================================================================
    // READ TEST
    // ========================================================================

    task automatic test_read;
        begin
            $display("");
            $display("========================================");
            $display("TEST 1: AXI READ");
            $display("========================================");

            // Compute Engine read request
            @(negedge clk);

            req_addr_i  = 13'd3584;
            req_write_i = 1'b0;
            req_valid_i = 1'b1;

            // Request kabul edilsin
            @(posedge clk);
            #1;

            check(req_ready_o == 1'b0,
                  "Read request accepted");

            @(negedge clk);
            req_valid_i = 1'b0;

            // Bridge ARVALID uretmeli
            wait(m_axi_arvalid == 1'b1);

            check(m_axi_araddr == 32'h2001_3800,
                  "Read address = 0x20013800");

            // Slave adresi 2 cycle gec kabul etsin
            repeat(2) @(posedge clk);

            @(negedge clk);
            m_axi_arready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            m_axi_arready = 1'b0;

            // Slave veriyi biraz gec dondursun
            repeat(2) @(posedge clk);

            @(negedge clk);

            m_axi_rdata  = 32'hDEAD_BEEF;
            m_axi_rresp  = 2'b00;
            m_axi_rvalid = 1'b1;

            wait(m_axi_rready == 1'b1);

            @(posedge clk);
            #1;

            check(rsp_valid_o == 1'b1,
                  "Read response valid");

            check(rsp_rdata_o == 32'hDEAD_BEEF,
                  "Read data correctly returned");

            check(rsp_resp_o == 2'b00,
                  "Read response OKAY");

            @(negedge clk);
            m_axi_rvalid = 1'b0;

        end
    endtask


    // ========================================================================
    // WRITE TEST 1
    //
    // WREADY erken
    // AWREADY gec
    // ========================================================================

    task automatic test_write_aw_late;
        begin
            $display("");
            $display("========================================");
            $display("TEST 2: WRITE - AWREADY LATE");
            $display("========================================");

            wait(req_ready_o == 1'b1);

            @(negedge clk);

            req_addr_i  = 13'd100;
            req_wdata_i = 32'h1234_5678;
            req_wstrb_i = 4'b1111;
            req_write_i = 1'b1;
            req_valid_i = 1'b1;

            @(posedge clk);

            @(negedge clk);
            req_valid_i = 1'b0;

            wait(m_axi_wvalid == 1'b1);
            wait(m_axi_awvalid == 1'b1);

            check(m_axi_awaddr == 32'h2001_0190,
                  "Write address correct");

            check(m_axi_wdata == 32'h1234_5678,
                  "Write data correct");

            check(m_axi_wstrb == 4'b1111,
                  "Write strobe correct");

            // W channel hemen kabul
            @(negedge clk);
            m_axi_wready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            m_axi_wready = 1'b0;

            // AW 3 cycle gec kabul
            repeat(3) @(posedge clk);

            @(negedge clk);
            m_axi_awready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            m_axi_awready = 1'b0;

            // Write response
            wait(m_axi_bready == 1'b1);

            @(negedge clk);

            m_axi_bresp  = 2'b00;
            m_axi_bvalid = 1'b1;

            @(posedge clk);
            #1;

            check(rsp_valid_o == 1'b1,
                  "Write response valid");

            check(rsp_resp_o == 2'b00,
                  "Write response OKAY");

            @(negedge clk);
            m_axi_bvalid = 1'b0;

        end
    endtask


    // ========================================================================
    // WRITE TEST 2
    //
    // AWREADY erken
    // WREADY gec
    // ========================================================================

    task automatic test_write_w_late;
        begin
            $display("");
            $display("========================================");
            $display("TEST 3: WRITE - WREADY LATE");
            $display("========================================");

            wait(req_ready_o == 1'b1);

            @(negedge clk);

            req_addr_i  = 13'd200;
            req_wdata_i = 32'hCAFE_BABE;
            req_wstrb_i = 4'b1111;
            req_write_i = 1'b1;
            req_valid_i = 1'b1;

            @(posedge clk);

            @(negedge clk);
            req_valid_i = 1'b0;

            wait(m_axi_awvalid == 1'b1);
            wait(m_axi_wvalid == 1'b1);

            check(m_axi_awaddr == 32'h2001_0320,
                  "Second write address correct");

            // AW hemen kabul
            @(negedge clk);
            m_axi_awready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            m_axi_awready = 1'b0;

            // W channel gec kabul
            repeat(3) @(posedge clk);

            @(negedge clk);
            m_axi_wready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            m_axi_wready = 1'b0;

            wait(m_axi_bready == 1'b1);

            @(negedge clk);

            m_axi_bresp  = 2'b00;
            m_axi_bvalid = 1'b1;

            @(posedge clk);
            #1;

            check(rsp_valid_o == 1'b1,
                  "Second write response valid");

            check(rsp_resp_o == 2'b00,
                  "Second write response OKAY");

            @(negedge clk);
            m_axi_bvalid = 1'b0;

        end
    endtask


    // ========================================================================
    // MAIN
    // ========================================================================

    initial begin

        error_count = 0;

        req_valid_i = 0;
        req_write_i = 0;
        req_addr_i  = 0;
        req_wdata_i = 0;
        req_wstrb_i = 0;

        m_axi_awready = 0;
        m_axi_wready  = 0;

        m_axi_bresp   = 0;
        m_axi_bvalid  = 0;

        m_axi_arready = 0;

        m_axi_rdata   = 0;
        m_axi_rresp   = 0;
        m_axi_rvalid  = 0;

        rst_n = 0;

        repeat(5) @(posedge clk);

        @(negedge clk);
        rst_n = 1;

        repeat(2) @(posedge clk);

        test_read();

        repeat(2) @(posedge clk);

        test_write_aw_late();

        repeat(2) @(posedge clk);

        test_write_w_late();

        repeat(3) @(posedge clk);

        $display("");
        $display("========================================");

        if (error_count == 0) begin
            $display("PASS: NPU AXI MASTER TEST BASARILI");
        end else begin
            $display(
                "FAIL: NPU AXI MASTER TEST - %0d hata",
                error_count
            );
        end

        $display("========================================");
        $finish;

    end

endmodule
