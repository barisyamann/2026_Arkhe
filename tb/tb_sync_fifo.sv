`timescale 1ns / 1ps
// =============================================================================
//  tb_sync_fifo.sv - sync_fifo blok testi
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN VAR
//
//    9. ASIC kosumunda ss kosesinin en kotu yolu bu FIFO'nun icindeydi:
//        u_uart2.u_rx_fifo.rd_ptr_r[0] -> u_uart2.u_rx_fifo.mem[25][0]
//        98 hucre, -8,026 ns
//    En kotu SEKIZ bitis noktasinin tamami ayni FIFO'nun mem[...] hucreleriydi.
//
//    Kok neden: o_full kombinasyonel olarak (wr_ptr - rd_ptr) cikarmasindan
//    ve 9 bit karsilastirmadan geliyordu, sonra 256x8 = 2048 flip-flop'un
//    yazma iznini besliyordu.
//
//    Duzeltme iki asamali:
//      1) dolu/bos tespiti cikaricidan ayrildi (sarma biti karsilastirmasi)
//      2) bayraklar yazmaclandi (sonraki cevrim isaretcilerinden)
//
//    Zamanlama duzeltmesi islevi bozarsa kazanim anlamsizdir. Bu test
//    dosyasi tam da o riski kapatir: FIFO'nun DAVRANIS sozlesmesini
//    dogrudan, kendi kendini denetleyerek sinar.
//
//  KAPSAM
//
//    1  reset          : empty=1, full=0, level=0
//    2  tek yaz/oku    : veri ve isaretci guncellemeleri
//    3  fill-to-full   : DEPTH yazma sonunda full, fazlasi bloklanmali
//    4  drain-to-empty : DEPTH okuma sonunda empty, fazlasi bloklanmali
//    5  wraparound     : isaretci sarmasi sonrasi veri sirasi korunmali
//    6  es zamanli R/W : doluluk sabit, sira dogru
//    7  full + read    : dolu iken okuma yapilinca full dusmeli
//    8  empty + write  : bos iken yazma yapilinca empty dusmeli
//
//  Sartname EK-3, cevre birimi blok testleri: "kendi kendini kontrol eden
//  (self-checking) yapida olmali".
// =============================================================================

module tb_sync_fifo;

    localparam int DATA_W = 8;
    localparam int DEPTH  = 256;
    localparam int PTR_W  = $clog2(DEPTH);

    logic              clk = 1'b0;
    logic              rst_n;
    logic              i_wr_en;
    logic [DATA_W-1:0] i_wr_data;
    logic              i_rd_en;
    logic [DATA_W-1:0] o_rd_data;
    logic              o_full;
    logic              o_empty;
    logic [PTR_W:0]    o_level;

    int hata = 0;
    int gecen = 0;

    always #5 clk = ~clk;   // 100 MHz

    sync_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .i_wr_en(i_wr_en), .i_wr_data(i_wr_data),
        .i_rd_en(i_rd_en), .o_rd_data(o_rd_data),
        .o_full(o_full), .o_empty(o_empty), .o_level(o_level)
    );

    // -------------------------------------------------------------------------
    // Denetim yardimcilari
    // -------------------------------------------------------------------------
    task automatic denetle(input string ad, input logic kosul);
        if (kosul) begin
            gecen++;
            $display("  [OK]   %s", ad);
        end else begin
            hata++;
            $display("  [HATA] %s", ad);
        end
    endtask

    task automatic denetle_esit(input string ad, input int gorulen, input int beklenen);
        if (gorulen === beklenen) begin
            gecen++;
            $display("  [OK]   %s (%0d)", ad, gorulen);
        end else begin
            hata++;
            $display("  [HATA] %s: beklenen %0d, gorulen %0d", ad, beklenen, gorulen);
        end
    endtask

    task automatic cevrim(input int n = 1);
        repeat (n) @(posedge clk);
    endtask

    task automatic yaz(input logic [DATA_W-1:0] d);
        i_wr_data <= d;
        i_wr_en   <= 1'b1;
        @(posedge clk);
        i_wr_en   <= 1'b0;
    endtask

    task automatic oku;
        i_rd_en <= 1'b1;
        @(posedge clk);
        i_rd_en <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    initial begin
        $display("");
        $display("==================================================");
        $display(" sync_fifo blok testi  (DATA_W=%0d, DEPTH=%0d)", DATA_W, DEPTH);
        $display("==================================================");

        i_wr_en = 0; i_rd_en = 0; i_wr_data = '0;
        rst_n = 1'b0;
        cevrim(3);
        rst_n = 1'b1;
        cevrim(2);

        // ---------------------------------------------------------------------
        $display("\n-- 1. reset sonrasi durum --");
        denetle("reset sonrasi empty=1", o_empty === 1'b1);
        denetle("reset sonrasi full=0",  o_full  === 1'b0);
        denetle_esit("reset sonrasi level", o_level, 0);

        // ---------------------------------------------------------------------
        $display("\n-- 2. tek yazma / tek okuma --");
        yaz(8'hA5);
        cevrim(1);
        denetle("bir yazmadan sonra empty=0", o_empty === 1'b0);
        denetle_esit("bir yazmadan sonra level", o_level, 1);

        oku();
        cevrim(1);
        denetle_esit("okunan veri", o_rd_data, 8'hA5);
        denetle("bir okumadan sonra empty=1", o_empty === 1'b1);
        denetle_esit("bir okumadan sonra level", o_level, 0);

        // ---------------------------------------------------------------------
        $display("\n-- 3. fill-to-full --");
        for (int i = 0; i < DEPTH; i++) begin
            i_wr_data <= i[DATA_W-1:0];
            i_wr_en   <= 1'b1;
            @(posedge clk);
        end
        i_wr_en <= 1'b0;
        cevrim(1);
        denetle("DEPTH yazmadan sonra full=1", o_full === 1'b1);
        denetle_esit("DEPTH yazmadan sonra level", o_level, DEPTH);

        // Dolu iken fazladan yazma BLOKLANMALI
        yaz(8'hFF);
        cevrim(1);
        denetle("dolu iken fazladan yazma bloklandi", o_level === DEPTH[PTR_W:0]);

        // ---------------------------------------------------------------------
        $display("\n-- 7. dolu iken okuma yapilinca full dusmeli --");
        oku();
        cevrim(1);
        denetle("dolu + okuma sonrasi full=0", o_full === 1'b0);
        denetle_esit("dolu + okuma sonrasi level", o_level, DEPTH-1);
        denetle_esit("ilk okunan veri (FIFO sirasi)", o_rd_data, 0);

        // ---------------------------------------------------------------------
        $display("\n-- 4. drain-to-empty (sira denetimiyle) --");
        begin
            int beklenen = 1;   // 0 zaten yukarida okundu
            int sira_hatasi = 0;
            for (int i = 1; i < DEPTH; i++) begin
                i_rd_en <= 1'b1;
                @(posedge clk);
                i_rd_en <= 1'b0;
                @(posedge clk);
                if (o_rd_data !== beklenen[DATA_W-1:0]) sira_hatasi++;
                beklenen++;
            end
            denetle_esit("bosaltirken sira hatasi", sira_hatasi, 0);
        end
        denetle("DEPTH okumadan sonra empty=1", o_empty === 1'b1);
        denetle_esit("DEPTH okumadan sonra level", o_level, 0);

        // Bos iken fazladan okuma BLOKLANMALI
        oku();
        cevrim(1);
        denetle_esit("bos iken fazladan okuma bloklandi", o_level, 0);

        // ---------------------------------------------------------------------
        $display("\n-- 8. bos iken yazma yapilinca empty dusmeli --");
        yaz(8'h5A);
        cevrim(1);
        denetle("bos + yazma sonrasi empty=0", o_empty === 1'b0);
        oku();
        cevrim(2);

        // ---------------------------------------------------------------------
        $display("\n-- 5. wraparound (isaretci sarmasi) --");
        // Isaretciler DEPTH kadar ilerlemis durumda; bir tur daha doldur/bosalt.
        begin
            int sira_hatasi = 0;
            for (int i = 0; i < DEPTH; i++) begin
                i_wr_data <= (8'h80 + i[DATA_W-1:0]);
                i_wr_en   <= 1'b1;
                @(posedge clk);
            end
            i_wr_en <= 1'b0;
            cevrim(1);
            denetle("sarma sonrasi tekrar full=1", o_full === 1'b1);

            for (int i = 0; i < DEPTH; i++) begin
                i_rd_en <= 1'b1;
                @(posedge clk);
                i_rd_en <= 1'b0;
                @(posedge clk);
                if (o_rd_data !== (8'h80 + i[DATA_W-1:0])) sira_hatasi++;
            end
            denetle_esit("sarma sonrasi sira hatasi", sira_hatasi, 0);
            denetle("sarma sonrasi tekrar empty=1", o_empty === 1'b1);
        end

        // ---------------------------------------------------------------------
        $display("\n-- 6. es zamanli yazma + okuma --");
        // Once biraz doldur
        for (int i = 0; i < 16; i++) begin
            i_wr_data <= (8'h30 + i[DATA_W-1:0]);
            i_wr_en   <= 1'b1;
            @(posedge clk);
        end
        i_wr_en <= 1'b0;
        cevrim(1);
        denetle_esit("es zamanli test oncesi level", o_level, 16);

        begin
            logic [PTR_W:0] onceki = o_level;
            int sira_hatasi = 0;
            // 8 cevrim boyunca ayni anda yaz ve oku - doluluk SABIT kalmali
            for (int i = 0; i < 8; i++) begin
                i_wr_data <= (8'h70 + i[DATA_W-1:0]);
                i_wr_en   <= 1'b1;
                i_rd_en   <= 1'b1;
                @(posedge clk);
            end
            i_wr_en <= 1'b0;
            i_rd_en <= 1'b0;
            cevrim(1);
            denetle_esit("es zamanli R/W sonrasi level degismedi", o_level, onceki);
        end

        // ---------------------------------------------------------------------
        $display("\n==================================================");
        if (hata == 0)
            $display(" TUM TESTLER GECTI - %0d denetim, 0 hata", gecen);
        else
            $display(" BASARISIZ - %0d denetim, %0d hata", gecen, hata);
        $display("==================================================");
        $display("");
        $finish;
    end

    // Guvenlik: test takilirsa sonsuza kadar beklemesin
    initial begin
        #2_000_000;
        $display(" [HATA] zaman asimi - test takildi");
        $finish;
    end

endmodule
