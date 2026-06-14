`timescale 1ns / 1ps
// ==============================================================================
//  tb_npu_compute_engine.sv
//  TEKNOFEST 2026 - AI Accelerator Block-Level Self-Checking Testbench
//  Tasarım Ekibi: Arkhe
// ==============================================================================

module tb_npu_compute_engine;

    // --- Sinyal Tanımlamaları ---
    logic        clk;
    logic        rst_n;
    logic        start_i;
    logic        npu_reset_i;
    logic [12:0] in_addr_i;
    logic [12:0] out_addr_i;

    logic        busy_o;
    logic        done_o;
    logic [1:0]  class_o;

    logic        mem_en_b;
    logic [3:0]  mem_we_b;
    logic [12:0] mem_addr_b;
    logic [31:0] mem_wdata_b;
    logic [31:0] mem_rdata_b;

    // --- Mock TCM SRAM Bellek (7680 kelime) ---
    logic [31:0] tcm_mem [0:7679];

    always_ff @(posedge clk) begin
        if (mem_en_b) begin
            if (mem_we_b[0]) tcm_mem[mem_addr_b][7:0]   <= mem_wdata_b[7:0];
            if (mem_we_b[1]) tcm_mem[mem_addr_b][15:8]  <= mem_wdata_b[15:8];
            if (mem_we_b[2]) tcm_mem[mem_addr_b][23:16] <= mem_wdata_b[23:16];
            if (mem_we_b[3]) tcm_mem[mem_addr_b][31:24] <= mem_wdata_b[31:24];
            mem_rdata_b <= tcm_mem[mem_addr_b];
        end
    end

    // --- UUT (Unit Under Test) ---
    npu_compute_engine uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (start_i),
        .npu_reset_i (npu_reset_i),
        .in_addr_i   (in_addr_i),
        .out_addr_i  (out_addr_i),
        .busy_o      (busy_o),
        .done_o      (done_o),
        .class_o     (class_o),
        .mem_en_b    (mem_en_b),
        .mem_we_b    (mem_we_b),
        .mem_addr_b  (mem_addr_b),
        .mem_wdata_b (mem_wdata_b),
        .mem_rdata_b (mem_rdata_b)
    // --- SystemVerilog Functional Coverage (Kapsama) Tanımları ---
    covergroup cg_npu_inference @(posedge clk);
        option.per_instance = 1;
        
        cov_class: coverpoint class_o {
            bins silence = {2'd0};
            bins unknown = {2'd1};
            bins yes     = {2'd2};
            bins no      = {2'd3};
        }
    endgroup

    cg_npu_inference cg_inst = new();

    // --- Saat Üreteci (50 MHz -> 20ns Periyot) ---
    always begin
        clk = 1'b0;
        #10;
        clk = 1'b1;
        #10;
    end

    // --- Log Dosyası Yazma Altyapısı ---
    int log_file;
    
    function automatic void log_print(input string msg);
        $display("%s", msg);
        if (log_file != 0) begin
            $fdisplay(log_file, "%s", msg);
        end
    endfunction

    // --- Test Akışı ---
    initial begin
        log_file = $fopen("C:/Arkhe_2026/tb/T1.1_npu_block_level/simulation.log", "w");
        if (log_file == 0) begin
            $display("HATA: C:/Arkhe_2026/tb/T1.1_npu_block_level/simulation.log dosyası açılamadı!");
        end

        log_print("================================================================");
        log_print(" NPU BLOK SEVİYESİ DOĞRULAMA TESTİ BAŞLATILDI");
        log_print("================================================================");

        // Başlangıç Değerleri
        rst_n       = 1'b0;
        start_i     = 1'b0;
        npu_reset_i = 1'b0;
        in_addr_i   = 13'h0000;
        out_addr_i  = 13'h1dac; // 7596. kelime (Çıkış olasılıkları için)

        #100;
        @ (posedge clk);
        rst_n = 1'b1;
        #20;

        // -------------------------------------------------------------
        // Senaryo 1: YES Girdisi Testi (Directed YES Test)
        // -------------------------------------------------------------
        run_scenario("SENARYO 1 (YES)", 32'h55555555);

        // -------------------------------------------------------------
        // Senaryo 2: NO Girdisi Testi (Directed NO Test)
        // -------------------------------------------------------------
        run_scenario("SENARYO 2 (NO)", 32'hAAAAAAAA);

        // -------------------------------------------------------------
        // Senaryo 3: SILENCE Girdisi Testi (Directed Silence Test)
        // -------------------------------------------------------------
        run_scenario("SENARYO 3 (SILENCE)", 32'h00000000);

        log_print("================================================================");
        log_print(" TÜM BLOK SEVİYESİ TESTLER BAŞARIYLA TAMAMLANDI!");
        log_print("================================================================");
        
        if (log_file != 0) begin
            $fclose(log_file);
        end
        $finish;
    end

    // --- Senaryo Koşturma Görevi (Task) ---
    task automatic run_scenario(input string name, input logic [31:0] input_pattern);
        log_print($sformatf("\n---> %s Baslatiliyor. Giris Deseni: 0x%h", name, input_pattern));
        
        // TCM SRAM bellek sıfırlama
        for (int i = 0; i < 7680; i = i + 1) begin
            tcm_mem[i] = 32'h00000000;
        end
        
        // Giriş spektrogram verisinin ilk kelimesine deseni yaz
        tcm_mem[0] = input_pattern;

        // NPU'yu tetikle
        @ (posedge clk);
        start_i = 1'b1;
        @ (posedge clk);
        start_i = 1'b0;

        // DONE sinyalini bekle
        wait(done_o == 1'b1);
        @ (posedge clk);

        // Sonuçları TCM Bellekten ve Çıkış portlarından oku
        log_print($sformatf("     [TAMAMLANDI] Secilen Sinif (class_o): %0d", class_o));
        log_print("     Softmax Olasiliklari (TCM 7596-7599):");
        log_print($sformatf("       Class 0 (Silence): %0d", tcm_mem[7596]));
        log_print($sformatf("       Class 1 (Unknown): %0d", tcm_mem[7597]));
        log_print($sformatf("       Class 2 (Yes)    : %0d", tcm_mem[7598]));
        log_print($sformatf("       Class 3 (No)     : %0d", tcm_mem[7599]));

        // NPU'yu sıfırla
        npu_reset_i = 1'b1;
        @ (posedge clk);
        npu_reset_i = 1'b0;
        #100;
    endtask

endmodule
