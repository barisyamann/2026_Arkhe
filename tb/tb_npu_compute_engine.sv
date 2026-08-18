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

    // =========================================================================
    // Self-checking altyapisi
    //
    // Sartname s.615: testler manuel inceleme gerektirmeden kendi kendini
    // kontrol etmelidir. Bu testbench'in basliginda "Self-Checking" yaziyordu
    // ama yalnizca sonuclari YAZDIRIYORDU; gecti mi kaldi mi soylemiyordu.
    //
    // SABIT BEKLENEN DEGER KULLANILMADI. Bunun yerine, agirliklardan bagimsiz
    // DEGISMEZLER denetleniyor:
    //   - softmax olasiliklari Q0.12'de ~4096'ya toplanmali
    //   - class_o, olasiliklarin argmax'i olmali
    //   - farkli girdiler farkli olasilik vektoru uretmeli
    //
    // Sonuncusu dogrudan B4 bulgusunu koruyor: SILENCE ve NO senaryolari
    // eskiden BIREBIR AYNI vektoru uretiyor, donanim iki sinifi ayirt
    // edemiyordu ve rapor bunu "dogru karar" diye isaretlemisti.
    //
    // Deger-tam dogrulama ayri bir testte yapiliyor: tb/npu_golden
    // (bagimsiz Python modeli, kanal kanal ara sonuclar dahil).
    // =========================================================================
    int error_count = 0;
    int check_count = 0;

    // Senaryo sonuclari - senaryolar arasi karsilastirma icin saklanir
    int  sc_probs [0:2][0:3];
    int  sc_class [0:2];
    int  sc_idx = 0;

    task automatic check(input string ad, input bit kosul, input string detay);
        check_count++;
        if (kosul) begin
            log_print($sformatf("      [OK]   %s", ad));
        end else begin
            error_count++;
            log_print($sformatf("      [HATA] %s - %s", ad, detay));
        end
    endtask

    // Gozcu: test hicbir kosulda asili kalmamali
    initial begin
        #40_000_000;   // 40 ms (uc senaryo x ~1,5 ms + pay)
        log_print("      [HATA] ZAMAN ASIMI - test 40 ms icinde bitmedi");
        $fatal(1, "NPU blok testi zaman asimi");
    end

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
        );
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
        log_file = $fopen("simulation.log", "w");
        if (log_file == 0) begin
            $display("HATA: simulation.log dosyası açılamadı!");
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
                // TFLite girdi zero-point = -128, yani gercek deger 0'a karsilik
        // gelen nicemlenmis bayt 0x80'dir. 0x00 sessizlik degil, buyuk
        // pozitif sinyal demektir.
        run_scenario("SENARYO 3 (SILENCE)", 32'h80808080);


        // =====================================================================
        // Senaryolar birbirinden ayirt edilebiliyor mu? (B4 koruma denetimi)
        //
        // Denetim B4: SILENCE ve NO senaryolari BIREBIR AYNI olasilik
        // vektorunu uretiyordu (412/412/412/2858) - donanim iki sinifi
        // ayirt edemiyordu. Bu denetim o durumun geri gelmesini engeller.
        // =====================================================================
        for (int a = 0; a < 3; a++) begin
            for (int b = a + 1; b < 3; b++) begin
                bit ayni;
                ayni = 1'b1;
                for (int k = 0; k < 4; k++)
                    if (sc_probs[a][k] != sc_probs[b][k]) ayni = 1'b0;

                check($sformatf("Senaryo %0d ve %0d farkli sonuc uretti", a+1, b+1),
                      !ayni,
                      $sformatf("iki senaryo BIREBIR AYNI vektor uretti: %0d/%0d/%0d/%0d",
                                sc_probs[a][0], sc_probs[a][1],
                                sc_probs[a][2], sc_probs[a][3]));
            end
        end

        log_print("================================================================");
        if (error_count != 0) begin
            log_print($sformatf(" NPU BLOK TESTI BASARISIZ - %0d hata / %0d denetim",
                                error_count, check_count));
            log_print("================================================================");
            if (log_file != 0) $fclose(log_file);
            $fatal(1, "NPU blok dogrulamasi basarisiz");
        end else begin
            log_print($sformatf(" NPU BLOK TESTI GECTI - %0d denetim, 0 hata", check_count));
            log_print("================================================================");
        end

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
        
        // Giris spektrogramin TAMAMINI (1960 bayt = 490 kelime) desenle doldur.
        // Onceden yalnizca ilk kelime yaziliyordu; uc senaryo birbirinin
        // %99,8 aynisi oluyordu ve hepsi ayni sinifi veriyordu.
        for (int i = 0; i < 490; i = i + 1) begin
            tcm_mem[i] = input_pattern;
        end


        // NPU'yu tetikle
        @ (posedge clk);
        start_i = 1'b1;
        @ (posedge clk);
        start_i = 1'b0;

        // DONE sinyalini bekle (gozcu asili kalmayi engelliyor)
        wait(done_o == 1'b1);
        @ (posedge clk);

        // Sonuçları TCM Bellekten ve Çıkış portlarından oku
        log_print($sformatf("     [TAMAMLANDI] Secilen Sinif (class_o): %0d", class_o));
        log_print("     Softmax Olasiliklari (TCM 7596-7599):");
        log_print($sformatf("       Class 0 (Silence): %0d", tcm_mem[7596]));
        log_print($sformatf("       Class 1 (Unknown): %0d", tcm_mem[7597]));
        log_print($sformatf("       Class 2 (Yes)    : %0d", tcm_mem[7598]));
        log_print($sformatf("       Class 3 (No)     : %0d", tcm_mem[7599]));

        // =====================================================================
        // DEGISMEZ DENETIMLERI
        // =====================================================================
        begin
            int p0, p1, p2, p3, toplam, enbuyuk, argmax;

            p0 = int'(tcm_mem[7596]);  p1 = int'(tcm_mem[7597]);
            p2 = int'(tcm_mem[7598]);  p3 = int'(tcm_mem[7599]);
            toplam = p0 + p1 + p2 + p3;

            // 1) Softmax Q0.12: olasiliklar 4096'ya toplanmali.
            //    Yuvarlama nedeniyle birkac birim sapma normaldir.
            check($sformatf("%s: softmax toplami ~4096 (gelen %0d)", name, toplam),
                  (toplam >= 4080 && toplam <= 4112),
                  $sformatf("Q0.12 softmax bozuk: %0d+%0d+%0d+%0d=%0d", p0,p1,p2,p3,toplam));

            // 2) class_o gercekten argmax mi?
            enbuyuk = p0; argmax = 0;
            if (p1 > enbuyuk) begin enbuyuk = p1; argmax = 1; end
            if (p2 > enbuyuk) begin enbuyuk = p2; argmax = 2; end
            if (p3 > enbuyuk) begin enbuyuk = p3; argmax = 3; end

            check($sformatf("%s: class_o argmax ile tutarli", name),
                  (int'(class_o) == argmax),
                  $sformatf("class_o=%0d ama argmax=%0d", class_o, argmax));

            // Senaryolar arasi karsilastirma icin sakla
            sc_probs[sc_idx][0] = p0;  sc_probs[sc_idx][1] = p1;
            sc_probs[sc_idx][2] = p2;  sc_probs[sc_idx][3] = p3;
            sc_class[sc_idx]    = int'(class_o);
            sc_idx++;
        end

        // NPU'yu sıfırla
        npu_reset_i = 1'b1;
        @ (posedge clk);
        npu_reset_i = 1'b0;
        #100;
    endtask

endmodule
