`timescale 1ns/1ps
// =============================================================================
//  tb_npu_audio.sv - NPU cok-vektorlu dogruluk testi (self-checking)
//  TEKNOFEST 2026 - Takim Arkhe
//
//  AMAC (Sartname EK-1):
//    "Yarismacilar, YZ hizlandiricisini kullanarak, yazilim ile gerceklenen
//     modelin dogrulugunu (accuracy) %10'luk bir pencere dahilinde
//     yakalamalidir."
//
//  YONTEM:
//    AYNI 1960 INT8 girdi vektoru hem yazilim referans modeline
//    (tb/npu_audio/npu_ref_model.py) hem de RTL'e verilir. Ayni girdide
//    ayni cikti bekleniyor; yani hedef pencere %10 degil, TAM ESITLIK.
//
//  NEDEN COK VEKTOR:
//    tb_npu_golden tek bir deterministik vektor kosar ve yalnizca NO sinifini
//    uyarir. Karar mekanizmasinin diger uc dali (SILENCE / UNKNOWN / YES) hic
//    calismiyordu. Buradaki vektor kumesi dort sinifi da kapsar.
//
//  Vektorler ve beklenen degerler URETILMISTIR:
//      python tb/npu_audio/gen_vectors.py
// =============================================================================

module tb_npu_audio;

    `include "vectors_expected.svh"

    // Cikis alani girdilerin uzerine binmesin: 5 x 490 = 2450 word kullaniliyor
    // CIKIS BOLGESI - 23 Agustos 2026'da TASINDI
    //
    // Eskiden 4096 idi. FC agirliklari TCM'nin 3584..7583 bolgesine
    // yerlesince cikis yazmalari agirliklarin TAM ORTASINA dusuyordu:
    // 4096..4123 arasi 28 kelime, yani fc_idx 512..539'un agirliklari
    // her vektorden sonra olasilik degerleriyle eziliyordu.
    //
    // Belirti sinsiydi: v0 temiz agirliklarla dogru sonuc veriyor, sonraki
    // vektorler birikimli bozulmus agirlik okuyordu. Sinif kararlari yine
    // dogru cikiyordu (bozulma kucuk), yalnizca logit/olasilik degerleri
    // kayiyordu - bu yuzden ilk bakista "yuvarlama farki" gibi gorundu.
    //
    // Agirliklar 7583'te bitiyor, TCM 7680 kelime -> 7584..7679 arasi
    // 96 kelime bos. 7 vektor x 4 kelime = 28 kelime sigiyor.
    localparam int CIKIS_TABAN = 7584;

    logic clk = 0;
    always #10 clk = ~clk;                     // 50 MHz

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

    logic [31:0] mem [0:8191];

    npu_compute_engine dut (
        .clk(clk), .rst_n(rst_n),
        .start_i(start_i), .npu_reset_i(npu_reset_i),
        .in_addr_i(in_addr_i), .out_addr_i(out_addr_i),
        .busy_o(busy_o), .done_o(done_o), .class_o(class_o),
        .mem_en_b(mem_en_b), .mem_we_b(mem_we_b), .mem_addr_b(mem_addr_b),
        .mem_wdata_b(mem_wdata_b), .mem_rdata_b(mem_rdata_b)
    );

    // Basit 1-cevrim senkron TCM modeli (tb_npu_golden ile ayni)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_rdata_b <= '0;
        end else if (mem_en_b) begin
            if (mem_we_b != 4'b0000) begin
                if (mem_we_b[0]) mem[mem_addr_b][7:0]   <= mem_wdata_b[7:0];
                if (mem_we_b[1]) mem[mem_addr_b][15:8]  <= mem_wdata_b[15:8];
                if (mem_we_b[2]) mem[mem_addr_b][23:16] <= mem_wdata_b[23:16];
                if (mem_we_b[3]) mem[mem_addr_b][31:24] <= mem_wdata_b[31:24];
            end else begin
                mem_rdata_b <= mem[mem_addr_b];
            end
        end
    end

    // =========================================================================
    // Self-checking altyapisi
    // =========================================================================
    int hata_sayisi    = 0;
    int denetim_sayisi = 0;

    task automatic denetle(input string ad, input int gercek, input int beklenen);
        denetim_sayisi++;
        if (gercek === beklenen) begin
            // Regresyon betigi denetimleri [OK] / [HATA] isaretlerinden sayar
            // (scripts/run_regression.py). Isaret basilmazsa test "DENETIM YOK"
            // olarak raporlanir - gecmis olsa bile.
            $display("      [OK]   %-22s = %0d", ad, gercek);
        end else begin
            hata_sayisi++;
            $display("      [HATA] %-22s beklenen=%0d  gercek=%0d",
                     ad, beklenen, gercek);
        end
    endtask

    // Gozcu - test hicbir kosulda asili kalmamali
    initial begin
        #200_000_000;
        $display(" NPU SES TESTI BASARISIZ - zaman asimi");
        $fatal(1, "tb_npu_audio zaman asimi");
    end

    // =========================================================================
    // Test akisi
    // =========================================================================
    int v;
    int cycles;
    int toplam_cycles;
    int dogru_sinif;

    initial begin
        for (int i = 0; i < 8192; i++) mem[i] = '0;

        // Tum vektorler ard arda: vektor v -> word [v*490 .. v*490+489]
        $readmemh("vectors.mem", mem, 0, VEKTOR_SAYISI * VEKTOR_WORD - 1);

        // -------------------------------------------------------------------
        // FC AGIRLIKLARI ARTIK TCM'DEN OKUNUYOR (23 Agustos 2026)
        //
        // GUNCEL TCM YERLESIMI (7680 word):
        //     0    .. 3429   girdi vektorleri (7 x 490)
        //     3430 .. 3583   bos
        //     3584 .. 7583   FC agirliklari (4000 word)
        //     7584 .. 7611   cikis olasiliklari (7 x 4)
        //
        // Iki bolge de agirliklara DEGMEMELIDIR; asagidaki denetimler bunu
        // derleme/kosum aninda zorlar.
        // -------------------------------------------------------------------
        if (VEKTOR_SAYISI * VEKTOR_WORD > 3584)
            $fatal(1, "Girdi bolgesi FC agirliklarina tasiyor (%0d > 3584)",
                   VEKTOR_SAYISI * VEKTOR_WORD);
        if (CIKIS_TABAN < 7584)
            $fatal(1, "Cikis bolgesi FC agirliklarini eziyor (%0d < 7584)",
                   CIKIS_TABAN);
        if (CIKIS_TABAN + VEKTOR_SAYISI * 4 > 7680)
            $fatal(1, "Cikis bolgesi TCM sonunu asiyor");

        $readmemh("fc_weights_packed32.mem", mem, 3584, 7583);

        // -------------------------------------------------------------------
        // FC AGIRLIKLARI ARTIK TCM'DEN OKUNUYOR (23 Agustos 2026)
        //
        // npu_compute_engine, FC agirliklarini buyuk kombinasyonel ROM yerine
        // TCM'nin 3584..7583 bolgesinden okuyor (ASIC fiziksel akisini
        // acmak icin). Testbench bunlari yuklemezse motor SIFIR agirlik
        // okur ve fc_acc yalnizca bias'a esit cikar.
        //
        // YERLESIM DENETIMI: 7 vektor x 490 word = 3430 word (0..3429).
        // Agirliklar 3584'ten basliyor -> cakisma YOK, 154 word pay var.
        // Vektor sayisi 7'yi asarsa bu pay biter; VEKTOR_SAYISI * 490
        // her zaman 3584'un altinda kalmalidir.
        // -------------------------------------------------------------------
        if (VEKTOR_SAYISI * VEKTOR_WORD > 3584)
            $fatal(1, "Vektor bolgesi FC agirlik bolgesine tasiyor (%0d > 3584)",
                   VEKTOR_SAYISI * VEKTOR_WORD);
        $readmemh("fc_weights_packed32.mem", mem, 3584, 7583);

        rst_n         = 1'b0;
        start_i       = 1'b0;
        npu_reset_i   = 1'b0;
        in_addr_i     = 13'd0;
        out_addr_i    = 13'd0;
        toplam_cycles = 0;
        dogru_sinif   = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("================================================================");
        $display(" NPU COK-VEKTORLU DOGRULUK TESTI - %0d vektor", VEKTOR_SAYISI);
        $display(" Referans: yazilim modeli (npu_ref_model.py), ayni girdi");
        $display("================================================================");

        for (v = 0; v < VEKTOR_SAYISI; v++) begin
            // Motoru temiz duruma al
            npu_reset_i = 1'b1;
            @(posedge clk);
            npu_reset_i = 1'b0;
            @(posedge clk);

            in_addr_i  = 13'(v * VEKTOR_WORD);
            out_addr_i = 13'(CIKIS_TABAN + v * 4);
            @(posedge clk);

            start_i = 1'b1;
            @(posedge clk);
            start_i = 1'b0;

            cycles = 0;
            while (!done_o && cycles < 2000000) begin
                @(posedge clk);
                cycles++;
            end
            if (!done_o) $fatal(1, "ZAMAN ASIMI: vektor %0d tamamlanmadi", v);
            toplam_cycles += cycles;

            $display("  [%0d] sinif=%0d logits=[%0d %0d %0d %0d] probs=[%0d %0d %0d %0d] %0d cevrim",
                     v, class_o,
                     $signed(dut.fc_logits[0]), $signed(dut.fc_logits[1]),
                     $signed(dut.fc_logits[2]), $signed(dut.fc_logits[3]),
                     dut.probs[0], dut.probs[1], dut.probs[2], dut.probs[3],
                     cycles);

            denetle($sformatf("v%0d sinif",  v), int'(class_o),             int'(BEKLENEN_SINIF[v]));
            denetle($sformatf("v%0d logit0", v), $signed(dut.fc_logits[0]), BEKLENEN_LOGIT0[v]);
            denetle($sformatf("v%0d logit1", v), $signed(dut.fc_logits[1]), BEKLENEN_LOGIT1[v]);
            denetle($sformatf("v%0d logit2", v), $signed(dut.fc_logits[2]), BEKLENEN_LOGIT2[v]);
            denetle($sformatf("v%0d logit3", v), $signed(dut.fc_logits[3]), BEKLENEN_LOGIT3[v]);
            denetle($sformatf("v%0d prob0",  v), int'(dut.probs[0]),        BEKLENEN_PROB0[v]);
            denetle($sformatf("v%0d prob1",  v), int'(dut.probs[1]),        BEKLENEN_PROB1[v]);
            denetle($sformatf("v%0d prob2",  v), int'(dut.probs[2]),        BEKLENEN_PROB2[v]);
            denetle($sformatf("v%0d prob3",  v), int'(dut.probs[3]),        BEKLENEN_PROB3[v]);

            // TCM'e yazilan sonuc da dogrulanir: CSR ile bellek tutarli olmali
            denetle($sformatf("v%0d TCM p0", v),
                    int'(mem[CIKIS_TABAN + v*4 + 0]), BEKLENEN_PROB0[v]);
            denetle($sformatf("v%0d TCM p3", v),
                    int'(mem[CIKIS_TABAN + v*4 + 3]), BEKLENEN_PROB3[v]);

            if (int'(class_o) == int'(BEKLENEN_SINIF[v])) dogru_sinif++;
        end

        // =====================================================================
        // Dogruluk ozeti - EK-1 %10 penceresi
        // =====================================================================
        $display("================================================================");
        $display(" Siniflandirma uyumu : %0d / %0d", dogru_sinif, VEKTOR_SAYISI);
        $display(" Ortalama cikarim    : %0d cevrim", toplam_cycles / VEKTOR_SAYISI);
        $display(" Denetim             : %0d, hata: %0d", denetim_sayisi, hata_sayisi);
        $display("================================================================");

        if (hata_sayisi != 0) begin
            $display(" NPU SES TESTI BASARISIZ");
            $fatal(1, "RTL yazilim referans modeliyle eslesmedi");
        end
        if (dogru_sinif != VEKTOR_SAYISI) begin
            $display(" NPU SES TESTI BASARISIZ - siniflandirma sapmasi");
            $fatal(1, "Dogruluk penceresi asildi");
        end
        $display(" NPU SES TESTI GECTI - %0d denetim, 0 hata, sapma yok",
                 denetim_sayisi);
        $display("================================================================");
        $finish;
    end

endmodule
