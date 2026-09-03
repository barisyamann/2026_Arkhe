`timescale 1ns / 1ps
// =============================================================================
//  tb_axil_decoder.sv - AXI-Lite adres kod cozucu ESDEGERLIK denetleyicisi
//
//  axi_lite_interconnect.sv icindeki get_slave_id fonksiyonu 50 MHz
//  calismasinda sirali if-else zincirinden paralel ust-bit esitligine
//  cevrildi. Bu testbench iki surumun BIREBIR ayni sonucu verdigini
//  kanitlar.
//
//  Kapsam:
//    1. Her bolgenin sinirlari: taban-1, taban, taban+1, son-1, son, son+1
//    2. Her bolgenin TAMAMI ve etrafindaki 256 baytlik pay, bayt bayt
//    3. Butun 32-bit uzayda 64 kB adimli kaba tarama
//    4. Sozde-rastgele adresler
//
//  Kosum: bkz. tb/axil_decoder/README.md
//  (Bu blokta arac adiyla baslayan satir birakilmamalidir; Verilator
//   "// <aracadi>" ile baslayan yorumlari pragma sanip hata veriyor.)
// =============================================================================

module tb_axil_decoder;

    // -------------------------------------------------------------------------
    // ESKI SURUM - 13 ardisik 32-bit buyukluk karsilastirmasi
    // -------------------------------------------------------------------------
    function automatic int eski_get_slave_id(input logic [31:0] addr);
        if (addr >= 32'h0000_0000 && addr <= 32'h0000_03FF) return 0;
        if (addr >= 32'h0100_0000 && addr <= 32'h0100_1FFF) return 1;
        if (addr >= 32'h2000_0000 && addr <= 32'h2000_1FFF) return 2;
        if (addr >= 32'h4000_0000 && addr <= 32'h4000_0FFF) return 3;
        if (addr >= 32'h4001_0000 && addr <= 32'h4001_0FFF) return 4;
        if (addr >= 32'h4002_0000 && addr <= 32'h4002_0FFF) return 5;
        if (addr >= 32'h4003_0000 && addr <= 32'h4003_0FFF) return 6;
        if (addr >= 32'h4004_0000 && addr <= 32'h4004_0FFF) return 7;
        if (addr >= 32'h4005_0000 && addr <= 32'h4005_0FFF) return 8;
        if (addr >= 32'h4006_0000 && addr <= 32'h4006_0FFF) return 9;
        if (addr >= 32'h2001_0000 && addr <= 32'h2001_77FF) return 10;
        if (addr >= 32'h4007_0000 && addr <= 32'h4007_0FFF) return 11;
        if (addr >= 32'h4008_0000 && addr <= 32'h4008_0FFF) return 12;
        return 13;
    endfunction

    // -------------------------------------------------------------------------
    // YENI SURUM - paralel ust bit esitligi
    // (axi_lite_interconnect.sv icindekiyle BIREBIR ayni olmalidir)
    // -------------------------------------------------------------------------
    function automatic int yeni_get_slave_id(input logic [31:0] addr);
        logic [12:0] hit;

        hit[0]  = (addr[31:10] == 22'h000000);
        hit[1]  = (addr[31:13] == 19'h00800);
        hit[2]  = (addr[31:13] == 19'h10000);
        hit[3]  = (addr[31:12] == 20'h40000);
        hit[4]  = (addr[31:12] == 20'h40010);
        hit[5]  = (addr[31:12] == 20'h40020);
        hit[6]  = (addr[31:12] == 20'h40030);
        hit[7]  = (addr[31:12] == 20'h40040);
        hit[8]  = (addr[31:12] == 20'h40050);
        hit[9]  = (addr[31:12] == 20'h40060);
        hit[10] = (addr[31:16] == 16'h2001) &&
                  (addr[15:0]  <= 16'h77FF);
        hit[11] = (addr[31:12] == 20'h40070);
        hit[12] = (addr[31:12] == 20'h40080);

        if (hit[0])  return 0;
        if (hit[1])  return 1;
        if (hit[2])  return 2;
        if (hit[3])  return 3;
        if (hit[4])  return 4;
        if (hit[5])  return 5;
        if (hit[6])  return 6;
        if (hit[7])  return 7;
        if (hit[8])  return 8;
        if (hit[9])  return 9;
        if (hit[10]) return 10;
        if (hit[11]) return 11;
        if (hit[12]) return 12;
        return 13;
    endfunction

    // -------------------------------------------------------------------------
    // Bolge tablosu
    // -------------------------------------------------------------------------
    localparam int N_BOLGE = 13;
    logic [31:0] taban [N_BOLGE];
    logic [31:0] son   [N_BOLGE];

    initial begin
        taban[0]  = 32'h0000_0000; son[0]  = 32'h0000_03FF;
        taban[1]  = 32'h0100_0000; son[1]  = 32'h0100_1FFF;
        taban[2]  = 32'h2000_0000; son[2]  = 32'h2000_1FFF;
        taban[3]  = 32'h4000_0000; son[3]  = 32'h4000_0FFF;
        taban[4]  = 32'h4001_0000; son[4]  = 32'h4001_0FFF;
        taban[5]  = 32'h4002_0000; son[5]  = 32'h4002_0FFF;
        taban[6]  = 32'h4003_0000; son[6]  = 32'h4003_0FFF;
        taban[7]  = 32'h4004_0000; son[7]  = 32'h4004_0FFF;
        taban[8]  = 32'h4005_0000; son[8]  = 32'h4005_0FFF;
        taban[9]  = 32'h4006_0000; son[9]  = 32'h4006_0FFF;
        taban[10] = 32'h2001_0000; son[10] = 32'h2001_77FF;
        taban[11] = 32'h4007_0000; son[11] = 32'h4007_0FFF;
        taban[12] = 32'h4008_0000; son[12] = 32'h4008_0FFF;
    end

    int denetim;
    int hata;
    logic [31:0] a;
    int e, y;
    logic [31:0] tohum;

    task automatic karsilastir(input logic [31:0] adres);
        int ee, yy;
        ee = eski_get_slave_id(adres);
        yy = yeni_get_slave_id(adres);
        denetim++;
        if (ee !== yy) begin
            hata++;
            if (hata <= 20)
                $display("      [HATA] adres=0x%08h  eski=%0d  yeni=%0d", adres, ee, yy);
        end
    endtask

    initial begin
        denetim = 0;
        hata    = 0;

        $display("================================================");
        $display(" AXI-Lite adres kod cozucu ESDEGERLIK denetimi");
        $display("================================================");

        // ---- 1. Sinir noktalari -------------------------------------------
        for (int i = 0; i < N_BOLGE; i++) begin
            if (taban[i] != 0) karsilastir(taban[i] - 1);
            karsilastir(taban[i]);
            karsilastir(taban[i] + 1);
            karsilastir(son[i] - 1);
            karsilastir(son[i]);
            karsilastir(son[i] + 1);
        end
        $display(" 1. sinir noktalari        : %0d denetim", denetim);

        // ---- 2. Her bolgenin tamami + 256 baytlik pay ----------------------
        for (int i = 0; i < N_BOLGE; i++) begin
            logic [31:0] bas, bit_;
            bas  = (taban[i] >= 32'h100) ? (taban[i] - 32'h100) : 32'h0;
            bit_ = son[i] + 32'h100;
            for (logic [31:0] x = bas; x <= bit_; x++) begin
                karsilastir(x);
                if (x == 32'hFFFF_FFFF) break;
            end
        end
        $display(" 2. bolge ici tam tarama   : %0d denetim (kumulatif)", denetim);

        // ---- 3. Butun uzayda 64 kB adimli kaba tarama ----------------------
        for (longint unsigned x = 0; x < 64'h1_0000_0000; x += 32'h1_0000) begin
            karsilastir(x[31:0]);
        end
        $display(" 3. kaba tarama (64 kB adim): %0d denetim (kumulatif)", denetim);

        // ---- 4. Sozde-rastgele adresler ------------------------------------
        tohum = 32'hACE1_2345;
        for (int i = 0; i < 200000; i++) begin
            tohum = {tohum[30:0], tohum[31] ^ tohum[21] ^ tohum[1] ^ tohum[0]};
            karsilastir(tohum);
        end
        $display(" 4. rastgele adresler      : %0d denetim (kumulatif)", denetim);

        $display("================================================");
        if (hata == 0)
            $display(" TEST BASARILI - %0d adresin hepsinde iki kod cozucu ayni", denetim);
        else
            $display(" TEST BASARISIZ - %0d / %0d adreste FARK var", hata, denetim);
        $display("================================================");

        if (hata != 0) $fatal(1, "Esdegerlik saglanmadi");
        $finish;
    end

endmodule
