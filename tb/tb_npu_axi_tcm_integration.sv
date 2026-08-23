`timescale 1ns / 1ps

module tb_npu_axi_tcm_integration;

    // ========================================================================
    // CLOCK / RESET
    // ========================================================================

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    integer error_count;

    // ========================================================================
    // COMPUTE REQUEST SIDE
    // ========================================================================

    logic        req_valid;
    logic        req_write;
    logic [12:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0]  req_wstrb;

    logic        req_ready;

    logic        rsp_valid;
    logic [31:0] rsp_rdata;
    logic [1:0]  rsp_resp;

    // ========================================================================
    // AXI WIRES
    // ========================================================================

    logic [31:0] axi_awaddr;
    logic        axi_awvalid;
    logic        axi_awready;

    logic [31:0] axi_wdata;
    logic [3:0]  axi_wstrb;
    logic        axi_wvalid;
    logic        axi_wready;

    logic [1:0]  axi_bresp;
    logic        axi_bvalid;
    logic        axi_bready;

    logic [31:0] axi_araddr;
    logic        axi_arvalid;
    logic        axi_arready;

    logic [31:0] axi_rdata;
    logic [1:0]  axi_rresp;
    logic        axi_rvalid;
    logic        axi_rready;

    // ========================================================================
    // TCM WIRES
    // ========================================================================

    logic        tcm_rd_en;
    logic [12:0] tcm_rd_addr;
    logic [31:0] tcm_rd_data;

    logic        tcm_wr_req;
    logic [12:0] tcm_wr_addr;
    logic [31:0] tcm_wr_data;
    logic [3:0]  tcm_wr_strb;
    logic        tcm_wr_grant;

    logic [31:0] unused_rdata_a;

    // ========================================================================
    // MASTER
    // ========================================================================

    npu_engine_axi_master #(
        .TCM_BASE_ADDR(32'h2001_0000)
    ) u_master (
        .clk            (clk),
        .rst_n          (rst_n),

        .req_valid_i    (req_valid),
        .req_write_i    (req_write),
        .req_addr_i     (req_addr),
        .req_wdata_i    (req_wdata),
        .req_wstrb_i    (req_wstrb),

        .req_ready_o    (req_ready),

        .rsp_valid_o    (rsp_valid),
        .rsp_rdata_o    (rsp_rdata),
        .rsp_resp_o     (rsp_resp),

        .m_axi_awaddr   (axi_awaddr),
        .m_axi_awvalid  (axi_awvalid),
        .m_axi_awready  (axi_awready),

        .m_axi_wdata    (axi_wdata),
        .m_axi_wstrb    (axi_wstrb),
        .m_axi_wvalid   (axi_wvalid),
        .m_axi_wready   (axi_wready),

        .m_axi_bresp    (axi_bresp),
        .m_axi_bvalid   (axi_bvalid),
        .m_axi_bready   (axi_bready),

        .m_axi_araddr   (axi_araddr),
        .m_axi_arvalid  (axi_arvalid),
        .m_axi_arready  (axi_arready),

        .m_axi_rdata    (axi_rdata),
        .m_axi_rresp    (axi_rresp),
        .m_axi_rvalid   (axi_rvalid),
        .m_axi_rready   (axi_rready)
    );

    // ========================================================================
    // AXI -> TCM SLAVE ADAPTER
    // ========================================================================

    npu_engine_axi_tcm_slave #(
        .TCM_BASE_ADDR(32'h2001_0000),
        .TCM_WORDS(7680)
    ) u_slave (
        .clk            (clk),
        .rst_n          (rst_n),

        .s_axi_awaddr   (axi_awaddr),
        .s_axi_awvalid  (axi_awvalid),
        .s_axi_awready  (axi_awready),

        .s_axi_wdata    (axi_wdata),
        .s_axi_wstrb    (axi_wstrb),
        .s_axi_wvalid   (axi_wvalid),
        .s_axi_wready   (axi_wready),

        .s_axi_bresp    (axi_bresp),
        .s_axi_bvalid   (axi_bvalid),
        .s_axi_bready   (axi_bready),

        .s_axi_araddr   (axi_araddr),
        .s_axi_arvalid  (axi_arvalid),
        .s_axi_arready  (axi_arready),

        .s_axi_rdata    (axi_rdata),
        .s_axi_rresp    (axi_rresp),
        .s_axi_rvalid   (axi_rvalid),
        .s_axi_rready   (axi_rready),

        .tcm_rd_en_o    (tcm_rd_en),
        .tcm_rd_addr_o  (tcm_rd_addr),
        .tcm_rd_data_i  (tcm_rd_data),

        .tcm_wr_req_o   (tcm_wr_req),
        .tcm_wr_addr_o  (tcm_wr_addr),
        .tcm_wr_data_o  (tcm_wr_data),
        .tcm_wr_strb_o  (tcm_wr_strb),

        .tcm_wr_grant_i (tcm_wr_grant)
    );

    // Bu izole testte Port A'yi kullanan baska bir blok yok.
    // Bu yuzden write request her zaman grant alabilir.
    assign tcm_wr_grant = 1'b1;

    // ========================================================================
    // GERCEK NPU TCM
    // ========================================================================

    npu_tcm_sram #(
        .TCM_WORDS(7680)
    ) u_tcm (
        .clk        (clk),

        // Port A - AXI write
        .en_a       (tcm_wr_req),
        .we_a       (tcm_wr_strb),
        .addr_a     (tcm_wr_addr),
        .wdata_a    (tcm_wr_data),
        .rdata_a    (unused_rdata_a),

        // Port B - AXI read
        .en_b       (tcm_rd_en),
        .addr_b     (tcm_rd_addr),
        .rdata_b    (tcm_rd_data)
    );

    // ========================================================================
    // CHECK
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
    // COMPUTE-LIKE WRITE
    // ========================================================================

    task automatic do_write(
        input logic [12:0] addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );
        begin

            wait(req_ready == 1'b1);

            @(negedge clk);

            req_addr  = addr;
            req_wdata = data;
            req_wstrb = strb;
            req_write = 1'b1;
            req_valid = 1'b1;

            @(posedge clk);

            @(negedge clk);
            req_valid = 1'b0;

            wait(rsp_valid == 1'b1);

            #1;

            check(
                rsp_resp == 2'b00,
                "AXI write response OKAY"
            );

            @(posedge clk);
        end
    endtask

    // ========================================================================
    // COMPUTE-LIKE READ
    // ========================================================================

    task automatic do_read(
        input logic [12:0] addr,
        input logic [31:0] expected
    );
        begin

            wait(req_ready == 1'b1);

            @(negedge clk);

            req_addr  = addr;
            req_write = 1'b0;
            req_valid = 1'b1;

            @(posedge clk);

            @(negedge clk);
            req_valid = 1'b0;

            wait(rsp_valid == 1'b1);

            #1;

            check(
                rsp_resp == 2'b00,
                "AXI read response OKAY"
            );

            check(
                rsp_rdata == expected,
                "AXI read data matches TCM content"
            );

            @(posedge clk);
        end
    endtask

    // ========================================================================
    // MAIN TEST
    // ========================================================================

    initial begin

        error_count = 0;

        req_valid = 0;
        req_write = 0;
        req_addr  = 0;
        req_wdata = 0;
        req_wstrb = 0;

        rst_n = 0;

        repeat(5) @(posedge clk);

        @(negedge clk);
        rst_n = 1;

        repeat(2) @(posedge clk);

        $display("");
        $display("========================================");
        $display("TEST 1: FULL WORD WRITE -> READ");
        $display("========================================");

        do_write(
            13'd100,
            32'h1234_5678,
            4'b1111
        );

        do_read(
            13'd100,
            32'h1234_5678
        );

        $display("");
        $display("========================================");
        $display("TEST 2: FC WEIGHT REGION");
        $display("========================================");

        do_write(
            13'd3584,
            32'hDEAD_BEEF,
            4'b1111
        );

        do_read(
            13'd3584,
            32'hDEAD_BEEF
        );

        $display("");
        $display("========================================");
        $display("TEST 3: BYTE STROBE");
        $display("========================================");

        do_write(
            13'd200,
            32'h1122_3344,
            4'b1111
        );

        // Sadece byte 0 degisecek.
        do_write(
            13'd200,
            32'h0000_00AA,
            4'b0001
        );

        do_read(
            13'd200,
            32'h1122_33AA
        );

        repeat(3) @(posedge clk);

        $display("");
        $display("========================================");

        if (error_count == 0) begin
            $display(
                "PASS: NPU AXI -> TCM INTEGRATION TEST BASARILI"
            );
        end else begin
            $display(
                "FAIL: NPU AXI -> TCM TEST - %0d hata",
                error_count
            );
        end

        $display("========================================");

        $finish;
    end

endmodule
