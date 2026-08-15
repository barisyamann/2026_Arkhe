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

    logic mem_en_b;
    logic [3:0] mem_we_b;
    logic [12:0] mem_addr_b;
    logic [31:0] mem_wdata_b;
    logic [31:0] mem_rdata_b;

    logic [31:0] mem [0:8191];

    npu_compute_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .npu_reset_i(npu_reset_i),
        .in_addr_i(in_addr_i),
        .out_addr_i(out_addr_i),
        .busy_o(busy_o),
        .done_o(done_o),
        .class_o(class_o),
        .mem_en_b(mem_en_b),
        .mem_we_b(mem_we_b),
        .mem_addr_b(mem_addr_b),
        .mem_wdata_b(mem_wdata_b),
        .mem_rdata_b(mem_rdata_b)
    );

    // Basit 1-cycle synchronous TCM modeli.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_rdata_b <= '0;
        end
        else if (mem_en_b) begin
            if (mem_we_b != 4'b0000) begin
                if (mem_we_b[0])
                    mem[mem_addr_b][7:0] <= mem_wdata_b[7:0];

                if (mem_we_b[1])
                    mem[mem_addr_b][15:8] <= mem_wdata_b[15:8];

                if (mem_we_b[2])
                    mem[mem_addr_b][23:16] <= mem_wdata_b[23:16];

                if (mem_we_b[3])
                    mem[mem_addr_b][31:24] <= mem_wdata_b[31:24];
            end
            else begin
                mem_rdata_b <= mem[mem_addr_b];
            end
        end
    end

    integer cycles;

    initial begin
        for (int i=0; i<8192; i++) mem[i] = '0;

        // 1960 byte = 490 adet 32-bit word
        $readmemh("test_input_pattern.mem", mem, 0, 489);

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
