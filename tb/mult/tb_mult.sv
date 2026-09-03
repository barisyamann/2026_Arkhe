`timescale 1ns / 1ps
//
// cv32e40p_mult MULH hedefli oz-denetimli test
//
// core_test.hex icinde MULH sinifi buyruk YOK (yalniz MUL, DIV, REM), bu
// yuzden cekirdek testi bir MULH degisikligini yakalayamaz. Bu testbench
// carpani dogrudan surer ve referans modelle karsilastirir.
//
// EX asamasi MULH sirasinda onceki cevrimin result_o'sunu op_c_i olarak geri
// besler; burada ayni sey kayitli bir sekilde taklit edilir. TEMEL RTL bu
// testi GECMEK ZORUNDA - gecmezse taklit yanlistir.
//
module tb_mult;
    import cv32e40p_pkg::*;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    logic         enable;
    mul_opcode_e  operator;
    logic         short_subword;
    logic [1:0]   short_signed;
    logic [31:0]  op_a, op_b, op_c;
    logic [4:0]   imm;
    logic [31:0]  result;
    logic         multicycle, mulh_active, ready;
    logic         ex_ready;

    int errors = 0, checks = 0;

    cv32e40p_mult dut (
        .clk(clk), .rst_n(rst_n),
        .enable_i(enable), .operator_i(operator),
        .short_subword_i(short_subword), .short_signed_i(short_signed),
        .op_a_i(op_a), .op_b_i(op_b), .op_c_i(op_c), .imm_i(imm),
        .dot_signed_i(2'b00), .dot_op_a_i(32'h0), .dot_op_b_i(32'h0),
        .dot_op_c_i(32'h0), .is_clpx_i(1'b0), .clpx_shift_i(2'b00),
        .clpx_img_i(1'b0),
        .result_o(result), .multicycle_o(multicycle),
        .mulh_active_o(mulh_active), .ready_o(ready), .ex_ready_i(ex_ready)
    );

    // EX asamasi taklidi: multicycle boyunca result_o -> op_c_i
    // (gercekte ID/EX boru kaydi uzerinden geri besleniyor)
    //
    // op_c_temizle: her yeni operasyonun BASINDA akumulator sifirlanmali.
    // Gercek tasarimda ID asamasi operand C'yi saglar; testte bunu elle
    // yapmazsak onceki testin sonucu STEP0'a sizar.
    logic op_c_temizle;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)            op_c <= 32'h0;
        else if (op_c_temizle) op_c <= 32'h0;
        else if (multicycle)   op_c <= result;
    end

    // signed_mode: 2'b11 = MULH (isaretli x isaretli)
    //              2'b01 = MULHSU (isaretli x isaretsiz)
    //              2'b00 = MULHU  (isaretsiz x isaretsiz)
    task automatic mulh_yap(input [31:0] a, input [31:0] b,
                            input [1:0] sm, output logic [31:0] r);
        int g;
        begin
            @(negedge clk);
            op_c_temizle = 1'b1;
            @(negedge clk);
            op_c_temizle = 1'b0;
            op_a = a; op_b = b; short_signed = sm;
            operator = MUL_H; enable = 1'b1; ex_ready = 1'b0;
            short_subword = 1'b0; imm = 5'd0;
            g = 0;
            // ready_o dusene kadar (islem basladi), sonra tekrar yukselene kadar
            while (ready && g < 50) begin @(negedge clk); g++; end
            g = 0;
            while (!ready && g < 200) begin @(negedge clk); g++; end
            if (g >= 200) begin
                errors++; $display("      [HATA] MULH zaman asimi a=%08h b=%08h", a, b);
                r = 32'hDEAD_DEAD;
            end else
                r = result;
            @(negedge clk);
            ex_ready = 1'b1; enable = 1'b0;
            @(negedge clk);
            ex_ready = 1'b0;
            @(negedge clk);
        end
    endtask

    function automatic logic [31:0] ref_mulh(input [31:0] a, input [31:0] b,
                                             input [1:0] sm);
        logic signed [63:0] ss;
        logic [63:0]        uu;
        logic signed [63:0] su;
        begin
            case (sm)
                2'b11: begin ss = $signed(a) * $signed(b);            return ss[63:32]; end
                2'b01: begin su = $signed(a) * $signed({1'b0, b});    return su[63:32]; end
                default: begin uu = {32'h0,a} * {32'h0,b};            return uu[63:32]; end
            endcase
        end
    endfunction

    task automatic dene(input [31:0] a, input [31:0] b, input [1:0] sm,
                        input string ad);
        logic [31:0] got, exp;
        begin
            mulh_yap(a, b, sm, got);
            exp = ref_mulh(a, b, sm);
            checks++;
            if (got !== exp) begin
                errors++;
                $display("      [HATA] %s a=%08h b=%08h sm=%b: beklenen %08h, gelen %08h",
                         ad, a, b, sm, exp, got);
            end
        end
    endtask

    logic [31:0] a, b;

    initial begin
        enable = 0; operator = MUL_I; short_subword = 0; short_signed = 2'b00;
        op_a = 0; op_b = 0; imm = 0; ex_ready = 0; op_c_temizle = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("================================================");
        $display(" cv32e40p_mult MULH testi");
        $display("================================================");

        // --- yonlu vakalar ---
        dene(32'h0000_0000, 32'h0000_0000, 2'b11, "0 x 0");
        dene(32'h0000_0001, 32'h0000_0001, 2'b11, "1 x 1");
        dene(32'hFFFF_FFFF, 32'hFFFF_FFFF, 2'b11, "-1 x -1");
        dene(32'hFFFF_FFFF, 32'h0000_0001, 2'b11, "-1 x 1");
        dene(32'h8000_0000, 32'h8000_0000, 2'b11, "min x min");
        dene(32'h8000_0000, 32'hFFFF_FFFF, 2'b11, "min x -1");
        dene(32'h7FFF_FFFF, 32'h7FFF_FFFF, 2'b11, "max x max");
        dene(32'h0001_0000, 32'h0001_0000, 2'b11, "65536 x 65536");
        dene(32'hDEAD_BEEF, 32'hCAFE_BABE, 2'b11, "DEADBEEF x CAFEBABE");

        // --- isaretsiz ---
        dene(32'hFFFF_FFFF, 32'hFFFF_FFFF, 2'b00, "MULHU -1 x -1");
        dene(32'h8000_0000, 32'h0000_0002, 2'b00, "MULHU");
        dene(32'hDEAD_BEEF, 32'hCAFE_BABE, 2'b00, "MULHU DEAD x CAFE");

        // --- isaretli x isaretsiz ---
        dene(32'hFFFF_FFFF, 32'h0000_0002, 2'b01, "MULHSU -1 x 2");
        dene(32'h8000_0000, 32'hFFFF_FFFF, 2'b01, "MULHSU min x max_u");

        // --- rastgele ---
        for (int i = 0; i < 60; i++) begin
            a = $urandom(); b = $urandom();
            dene(a, b, 2'b11, $sformatf("rastgele-s %0d", i));
        end
        for (int i = 0; i < 30; i++) begin
            a = $urandom(); b = $urandom();
            dene(a, b, 2'b00, $sformatf("rastgele-u %0d", i));
        end
        for (int i = 0; i < 20; i++) begin
            a = $urandom(); b = $urandom();
            dene(a, b, 2'b01, $sformatf("rastgele-su %0d", i));
        end

        $display("================================================");
        if (errors == 0) $display(" TEST BASARILI - %0d denetimin hepsi gecti", checks);
        else             $display(" TEST BASARISIZ - %0d denetim, %0d hata", checks, errors);
        $display("================================================");
        $finish;
    end

    initial begin
        #4000000;
        $display(" TEST BASARISIZ - genel zaman asimi");
        $finish;
    end
endmodule
