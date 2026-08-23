`timescale 1ns/1ps

module tb_npu_golden;

    logic clk = 0;
    always #10 clk = ~clk; // 50 MHz

    logic rst_n;
    logic start_i;
    logic npu_reset_i;
    logic [12:0] in_addr_i;
    logic [12:0] out_addr_i;

    logic busy_o;
    logic done_o;
    logic [1:0] class_o;

    // Compute Engine request/response
    logic        req_valid;
    logic        req_write;
    logic [12:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0]  req_wstrb;
    logic        req_ready;
    logic        rsp_valid;
    logic [31:0] rsp_rdata;
    logic [1:0]  rsp_resp;

    // Yerel AXI4-Lite
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

    // TCM fiziksel portlari
    logic        tcm_rd_en;
    logic [12:0] tcm_rd_addr;
    logic [31:0] tcm_rd_data;
    logic        tcm_wr_req;
    logic [12:0] tcm_wr_addr;
    logic [31:0] tcm_wr_data;
    logic [3:0]  tcm_wr_strb;
    logic [31:0] tcm_rdata_a;

    npu_compute_engine dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start_i        (start_i),
        .npu_reset_i    (npu_reset_i),
        .in_addr_i      (in_addr_i),
        .out_addr_i     (out_addr_i),
        .busy_o         (busy_o),
        .done_o         (done_o),
        .class_o        (class_o),
        .mem_req_valid_o(req_valid),
        .mem_req_write_o(req_write),
        .mem_req_addr_o (req_addr),
        .mem_req_wdata_o(req_wdata),
        .mem_req_wstrb_o(req_wstrb),
        .mem_req_ready_i(req_ready),
        .mem_rsp_valid_i(rsp_valid),
        .mem_rsp_rdata_i(rsp_rdata),
        .mem_rsp_resp_i (rsp_resp)
    );

    npu_engine_axi_master #(.TCM_BASE_ADDR(32'h2001_0000)) u_master (
        .clk(clk), .rst_n(rst_n),
        .req_valid_i(req_valid), .req_write_i(req_write),
        .req_addr_i(req_addr), .req_wdata_i(req_wdata), .req_wstrb_i(req_wstrb),
        .req_ready_o(req_ready),
        .rsp_valid_o(rsp_valid), .rsp_rdata_o(rsp_rdata), .rsp_resp_o(rsp_resp),
        .m_axi_awaddr(axi_awaddr), .m_axi_awvalid(axi_awvalid), .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata), .m_axi_wstrb(axi_wstrb), .m_axi_wvalid(axi_wvalid), .m_axi_wready(axi_wready),
        .m_axi_bresp(axi_bresp), .m_axi_bvalid(axi_bvalid), .m_axi_bready(axi_bready),
        .m_axi_araddr(axi_araddr), .m_axi_arvalid(axi_arvalid), .m_axi_arready(axi_arready),
        .m_axi_rdata(axi_rdata), .m_axi_rresp(axi_rresp), .m_axi_rvalid(axi_rvalid), .m_axi_rready(axi_rready)
    );

    npu_engine_axi_tcm_slave #(
        .TCM_BASE_ADDR(32'h2001_0000),
        .TCM_WORDS(7680)
    ) u_slave (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(axi_awaddr), .s_axi_awvalid(axi_awvalid), .s_axi_awready(axi_awready),
        .s_axi_wdata(axi_wdata), .s_axi_wstrb(axi_wstrb), .s_axi_wvalid(axi_wvalid), .s_axi_wready(axi_wready),
        .s_axi_bresp(axi_bresp), .s_axi_bvalid(axi_bvalid), .s_axi_bready(axi_bready),
        .s_axi_araddr(axi_araddr), .s_axi_arvalid(axi_arvalid), .s_axi_arready(axi_arready),
        .s_axi_rdata(axi_rdata), .s_axi_rresp(axi_rresp), .s_axi_rvalid(axi_rvalid), .s_axi_rready(axi_rready),
        .tcm_rd_en_o(tcm_rd_en), .tcm_rd_addr_o(tcm_rd_addr), .tcm_rd_data_i(tcm_rd_data),
        .tcm_wr_req_o(tcm_wr_req), .tcm_wr_addr_o(tcm_wr_addr),
        .tcm_wr_data_o(tcm_wr_data), .tcm_wr_strb_o(tcm_wr_strb),
        .tcm_wr_grant_i(1'b1)
    );

    npu_tcm_sram #(.TCM_WORDS(7680)) u_tcm (
        .clk(clk),
        .en_a(tcm_wr_req), .we_a(tcm_wr_strb), .addr_a(tcm_wr_addr),
        .wdata_a(tcm_wr_data), .rdata_a(tcm_rdata_a),
        .en_b(tcm_rd_en), .addr_b(tcm_rd_addr), .rdata_b(tcm_rd_data)
    );

    integer cycles;

    initial begin
        // npu_tcm_sram'in hizli simulasyon modelindeki gercek RAM dizisini
        // golden test vektorleriyle on-yukle.
        $readmemh("test_input_pattern.mem", u_tcm.ram, 0, 489);
        $readmemh("fc_weights_packed32.mem", u_tcm.ram, 3584, 7583);
        rst_n       = 1'b0;
        start_i     = 1'b0;
        npu_reset_i = 1'b0;
        in_addr_i   = 13'd0;
        out_addr_i  = 13'd1024;

        cycles      = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);
        start_i = 1'b1;
        @(posedge clk);
        start_i = 1'b0;

        while (!done_o && cycles < 1000000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!done_o) begin
            $fatal(1, "TIMEOUT: NPU 1,000,000 cycle icinde tamamlanmadi.");
        end

        $display("NPU cycles  = %0d", cycles);
        $display("fc_acc      = [%0d, %0d, %0d, %0d]",
                 dut.fc_acc[0], dut.fc_acc[1], dut.fc_acc[2], dut.fc_acc[3]);
        $display("fc_logits   = [%0d, %0d, %0d, %0d]",
                 $signed(dut.fc_logits[0]), $signed(dut.fc_logits[1]),
                 $signed(dut.fc_logits[2]), $signed(dut.fc_logits[3]));
        $display("probs Q0.12 = [%0d, %0d, %0d, %0d]",
                 dut.probs[0], dut.probs[1], dut.probs[2], dut.probs[3]);
        $display("class       = %0d", class_o);

        // Golden beklenen değerler
        if (dut.fc_acc[0] !== -32'sd566992 ||
            dut.fc_acc[1] !==  32'sd149030 ||
            dut.fc_acc[2] !==  32'sd156762 ||
            dut.fc_acc[3] !==  32'sd216460) begin
            $fatal(1, "FAIL: FC accumulator golden ile eslesmedi.");
        end

        if ($signed(dut.fc_logits[0]) !== -128 ||
            $signed(dut.fc_logits[1]) !==   79 ||
            $signed(dut.fc_logits[2]) !==   83 ||
            $signed(dut.fc_logits[3]) !==  109) begin
            $fatal(1, "FAIL: FC logits golden ile eslesmedi.");
        end

        if (dut.probs[0] !== 13'd0   ||
            dut.probs[1] !== 13'd225 ||
            dut.probs[2] !== 13'd326 ||
            dut.probs[3] !== 13'd3543) begin
            $fatal(1, "FAIL: Softmax probability golden ile eslesmedi.");
        end

        if (class_o !== 2'd3) begin
            $fatal(1, "FAIL: Beklenen sinif NO (3), gelen=%0d", class_o);
        end

        $display("PASS: RTL deterministic golden test basarili.");
        $finish;
    end

endmodule
