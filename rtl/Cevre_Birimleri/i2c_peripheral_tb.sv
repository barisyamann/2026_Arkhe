// =============================================================================
// TEKNOFEST 2026 - I2C Master Çevre Birimi Testbench (AXI4-Lite)
// Sanal I2C Slave (Sensör/EEPROM) Modeli İçerir
// =============================================================================
`timescale 1ns/1ps

module i2c_peripheral_tb;

    localparam CLK_PERIOD = 20.833; // 48 MHz
    
    logic        clk, rst_n;
    logic [7:0]  s_axil_awaddr;  logic s_axil_awvalid, s_axil_awready;
    logic [31:0] s_axil_wdata;   logic [3:0] s_axil_wstrb;
    logic        s_axil_wvalid,  s_axil_wready;
    logic [1:0]  s_axil_bresp;   logic s_axil_bvalid, s_axil_bready;
    logic [7:0]  s_axil_araddr;  logic s_axil_arvalid, s_axil_arready;
    logic [31:0] s_axil_rdata;   logic [1:0] s_axil_rresp;
    logic        s_axil_rvalid,  s_axil_rready;

    // I2C Fiziksel Pinleri
    wire         scl;
    wire         sda;
    
    // Testbench'in SDA hattını sürebilmesi için (Sanal Slave)
    logic        sda_drv;
    assign sda = sda_drv;
    
    // I2C Open-Drain Pull-up Dirençleri
    pullup(scl);
    pullup(sda);

    // =========================================================================
    // Ucdurumlu surucu halkasi
    //
    // i2c_peripheral artik cift yonlu pin ICERMIYOR: ASIC akisinda tri-state
    // yalnizca pad halkasinda olabildigi icin arayuz cikis/cikis-etkin/giris
    // uclusune ayrildi. Gercek 'z surumu burada, testbench tarafinda.
    //
    // Acik drenaj: *_o daima 0, tum bilgi *_oe'de.
    // =========================================================================
    wire dut_sda_o, dut_sda_oe, dut_scl_o, dut_scl_oe;

    assign sda = dut_sda_oe ? dut_sda_o : 1'bz;
    assign scl = dut_scl_oe ? dut_scl_o : 1'bz;

    int pass_count = 0, fail_count = 0;

    // DUT (Test Edilecek Tasarım)
    // NOT: (.*) kullanilamaz - fiziksel pinler artik ayrik sinyaller.
    i2c_peripheral #(
        .SYS_CLK_FREQ(48_000_000), 
        .I2C_FREQ(400_000)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .sda_o          (dut_sda_o),
        .sda_oe         (dut_sda_oe),
        .sda_i          (sda),
        .scl_o          (dut_scl_o),
        .scl_oe         (dut_scl_oe),
        .scl_i          (scl),
        .i2c_irq        (),

        // NOT: modul portlari s_axi_*, testbench sinyalleri s_axil_*.
        // Eski surumde (.*) kullaniliyordu ve bu adlar ESLESMEDIGI icin
        // AXI portlarinin hicbiri baglanmiyordu - testbench sinyalleri
        // bosluga suruyor, hicbir sey dogrulamiyordu.
        .s_axi_awaddr   (s_axil_awaddr),  .s_axi_awprot  (3'b000),
        .s_axi_awvalid  (s_axil_awvalid), .s_axi_awready (s_axil_awready),
        .s_axi_wdata    (s_axil_wdata),   .s_axi_wstrb   (s_axil_wstrb),
        .s_axi_wvalid   (s_axil_wvalid),  .s_axi_wready  (s_axil_wready),
        .s_axi_bresp    (s_axil_bresp),   .s_axi_bvalid  (s_axil_bvalid),  .s_axi_bready (s_axil_bready),
        .s_axi_araddr   (s_axil_araddr),  .s_axi_arprot  (3'b000),
        .s_axi_arvalid  (s_axil_arvalid), .s_axi_arready (s_axil_arready),
        .s_axi_rdata    (s_axil_rdata),   .s_axi_rresp   (s_axil_rresp),
        .s_axi_rvalid   (s_axil_rvalid),  .s_axi_rready  (s_axil_rready)
    );

    // Saat Sinyali
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // GOZCU (watchdog)
    //
    // Sartname s.615: testler manuel inceleme gerektirmeden kendi kendini
    // kontrol etmelidir. Asili kalan bir test bu sarti saglamaz - birinin
    // gelip fark etmesi gerekir.
    //
    // I2C 400 kHz'de iki islem (2 bayt yazma + 2 bayt okuma) toplam ~200 us
    // surer. 2 ms fazlasiyla yeterli bir ust sinir.
    // =========================================================================
    initial begin
        #2_000_000;   // 2 ms
        $display("================================================================");
        $display(" I2C TESTI ZAMAN ASIMI - 2 ms icinde tamamlanmadi");
        $display(" Son durum: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("================================================================");
        $fatal(1, "I2C testbench zaman asimi");
    end

    // =========================================================================
    // AXI-Lite Görevleri
    // =========================================================================
    task axil_write(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        s_axil_awaddr = addr; s_axil_awvalid = 1'b1;
        s_axil_wdata  = data; s_axil_wstrb   = 4'hF; s_axil_wvalid = 1'b1; s_axil_bready = 1'b1;
        fork
            begin wait(s_axil_awready); @(posedge clk); s_axil_awvalid = 1'b0; end
            begin wait(s_axil_wready);  @(posedge clk); s_axil_wvalid  = 1'b0; end
        join
        wait(s_axil_bvalid); @(posedge clk); s_axil_bready = 1'b0;
    endtask

    task axil_read(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        s_axil_araddr = addr; s_axil_arvalid = 1'b1; s_axil_rready = 1'b1;
        wait(s_axil_arready); @(posedge clk); s_axil_arvalid = 1'b0;
        wait(s_axil_rvalid); data = s_axil_rdata;
        @(posedge clk); s_axil_rready = 1'b0;
    endtask

    // =========================================================================
    // SANAL I2C SLAVE GÖREVLERİ (Master'a Yanıt Verir)
    // =========================================================================
    task wait_start();
        @(negedge sda iff scl === 1'b1);
    endtask

    task wait_stop();
        @(posedge sda iff scl === 1'b1);
    endtask

    task rx_byte_and_ack(output logic [7:0] data);
        for(int i=7; i>=0; i--) begin
            @(posedge scl);
            data[i] = sda;
        end
        @(negedge scl);
        sda_drv = 1'b0; // Slave ACK basıyor
        @(negedge scl);
        sda_drv = 1'bz; // Hattı serbest bırak
    endtask

    // Sanal kole -> master veri gonderimi.
    //
    // IKI DUZELTME:
    //
    // 1) Eski surumde sonda FAZLADAN bir @(negedge scl) vardi. Son bayttan
    //    sonra master NACK verip STOP'a gecer ve SCL bir daha dusmez; bu
    //    yuzden testbench orada sonsuza kadar asili kaliyordu.
    //
    // 2) Sira yanlisti: once kenar bekleniyor, sonra bit suruluyordu.
    //    rx_byte_and_ack ACK'i bitiren dusen kenari zaten tuketiyor,
    //    dolayisiyla ilk veri biti BIR BIT PERIYODU GEC suruluyordu ve
    //    master bostaki '1'i orneklerdi:
    //        gonderilen 0x12 -> okunan 0x89   (bir bit saga kayma)
    //        gonderilen 0x34 -> okunan 0x9A
    //    Dogrusu: once sur, sonra o bitin sonunu bekle.
    //
    // 3) ACK bitinin sonu beklenmiyordu; ikinci bayt ACK periyodu icinde
    //    surulmeye baslayip BIR BIT SOLA kayiyordu (0x34 -> 0x69).
    //    Son bayt haric ACK sonu da beklenmeli.
    task tx_byte(input logic [7:0] data, input bit is_last);
        for(int i=7; i>=0; i--) begin
            sda_drv = data[i];   // once sur
            @(negedge scl);      // sonra bu bitin sonunu bekle
        end
        sda_drv = 1'bz;          // 9. bit: master ACK/NACK basacak

        // ACK bitinin sonunu bekle ki sonraki bayt dogru hizalansin.
        // SON baytta beklenmez: master NACK verip STOP'a gecer ve SCL bir
        // daha dusmez - beklenirse testbench asili kalir.
        if (!is_last) @(negedge scl);
    endtask

    // Bayragin kurulmasini SINIRLI sure bekler.
    //
    // Anlik okuma yarisa aciktir: wait_stop() STOP kenarinda tetiklenir ama
    // TX_DONE/RX_DONE bayragi ST_STOP'un SONUNDA (bit_done) kurulur.
    // Yazilim tarafi zaten dongude yokluyor; testbench de oyle yapmali.
    task wait_flag(input logic [7:0] addr, input int bit_idx, input int max_us);
        logic [31:0] v;
        int          waited;
        begin
            waited = 0;
            forever begin
                axil_read(addr, v);
                if (v[bit_idx]) break;
                if (waited >= max_us) break;
                #1000;                 // 1 us
                waited = waited + 1;
            end
        end
    endtask

    task check(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin $display("[PASS] %s", name); pass_count++; end
        else begin $display("[FAIL] %s: Got %h, Exp %h", name, got, exp); fail_count++; end
    endtask

    // =========================================================================
    // TEST SENARYOSU
    // =========================================================================
    initial begin
        logic [31:0] rdata;
        
        sda_drv = 1'bz;
        rst_n = 1'b0;
        s_axil_awvalid = 0; s_axil_wvalid = 0; s_axil_bready = 0;
        s_axil_arvalid = 0; s_axil_rready = 0;
        
        repeat(10) @(posedge clk); rst_n = 1'b1; repeat(10) @(posedge clk);

        $display("--- I2C TEST BAŞLIYOR ---");

        // ---------------------------------------------------------------------
        // TEST 0: YAZMAC DAVRANISLARI  (22 Agustos 2026'da eklendi)
        //
        // Sartname EK-2 su davranislari acikca tanimliyor ama hicbiri test
        // edilmiyordu; kapsama olcumunde i2c_peripheral %64,2 statement ile
        // dusuk cikti.
        // ---------------------------------------------------------------------

        // --- I2C_NBY kirpma -------------------------------------------------
        // Sartname: "1-4 arasinda bir deger alabilmektedir. 1,2,3,4 degerleri
        // disinda bir deger yazilirsa en yakin sayiya yuvarlanir. Ornegin 0
        // yazilmasi durumunda 1, 25 yazilmasi durumunda 4 degerini alir."
        axil_write(8'h00, 32'd0);
        axil_read(8'h00, rdata);
        check("I2C_NBY: 0 yazildi -> 1", rdata, 32'd1);

        axil_write(8'h00, 32'd25);
        axil_read(8'h00, rdata);
        check("I2C_NBY: 25 yazildi -> 4", rdata, 32'd4);

        axil_write(8'h00, 32'd3);
        axil_read(8'h00, rdata);
        check("I2C_NBY: 3 yazildi -> 3", rdata, 32'd3);

        axil_write(8'h00, 32'd1);
        axil_read(8'h00, rdata);
        check("I2C_NBY: 1 yazildi -> 1", rdata, 32'd1);

        // --- I2C_ADR 7-bit maskeleme ----------------------------------------
        // Sartname: "7-bit mod desteklenmektedir. I2C_ADR[6:0] bitleri slave
        // adresi tanimlar. Diger bitler etkisizdir."
        axil_write(8'h04, 32'hFFFF_FFFF);
        axil_read(8'h04, rdata);
        check("I2C_ADR: yalnizca [6:0] tutuluyor", rdata, 32'h0000_007F);

        // --- I2C_RDR salt-okunur --------------------------------------------
        // Sartname RDR'yi "RO" olarak isaretliyor.
        axil_read(8'h08, rdata);
        begin
            logic [31:0] rdr_onceki;
            rdr_onceki = rdata;
            axil_write(8'h08, 32'hDEAD_BEEF);
            axil_read(8'h08, rdata);
            check("I2C_RDR yazmaya direnir", rdata, rdr_onceki);
        end

        // --- Yazmac geri okuma ----------------------------------------------
        axil_write(8'h0C, 32'h1234_5678);
        axil_read(8'h0C, rdata);
        check("I2C_TDR geri okuma", rdata, 32'h1234_5678);

        // Sonraki testler icin temiz baslangic
        axil_write(8'h10, 32'h00);

        // ---------------------------------------------------------------------
        // TEST 1: I2C MASTER YAZMA (TX) İŞLEMİ
        // ---------------------------------------------------------------------
        axil_write(8'h00, 32'd2);       // I2C_NBY = 2 Bayt
        axil_write(8'h04, 32'h5A);      // I2C_ADR = 0x5A
        axil_write(8'h0C, 32'hBEEF);    // I2C_TDR = 0xBEEF (LSB First: Önce EF, Sonra BE)
        axil_write(8'h10, 32'h01);      // I2C_CFG = 1 (TX_EN)

        // Sanal Slave: Master'ın gönderdiklerini dinliyor ve ACK veriyor
        begin
            logic [7:0] rbyte;
            wait_start();
            rx_byte_and_ack(rbyte); 
            check("TX Slave Addr + W", rbyte, (8'h5A << 1) | 8'h00); // 0xB4 beklenir
            
            rx_byte_and_ack(rbyte); 
            check("TX Byte 0", rbyte, 8'hEF); // LSB önce
            
            rx_byte_and_ack(rbyte); 
            check("TX Byte 1", rbyte, 8'hBE); // MSB sonra
            wait_stop();
        end

        // HW Flag Kontrolü - yoklayarak (yaris onlenir)
        wait_flag(8'h10, 1, 200);
        axil_read(8'h10, rdata);
        check("TX_DONE (CFG[1]) HW Set", rdata[1], 1'b1);
        axil_write(8'h10, 32'h00); // Interrupt temizle

        // ---------------------------------------------------------------------
        // TEST 2: I2C MASTER OKUMA (RX) İŞLEMİ
        // ---------------------------------------------------------------------
        axil_write(8'h00, 32'd2);       // I2C_NBY = 2 Bayt
        axil_write(8'h04, 32'h5A);      // I2C_ADR = 0x5A
        axil_write(8'h10, 32'h04);      // I2C_CFG = 4 (RX_EN - Bit 2)

        // Sanal Slave: Master'a veri gönderiyor
        begin
            logic [7:0] rbyte;
            wait_start();
            rx_byte_and_ack(rbyte);
            check("RX Slave Addr + R", rbyte, (8'h5A << 1) | 8'h01); // 0xB5 beklenir
            
            tx_byte(8'h12, 1'b0); // Master'a 0x12 gonder
            tx_byte(8'h34, 1'b1); // Master'a 0x34 gonder (son bayt)
            wait_stop();
        end

        // HW Flag Kontrolü ve Veri Doğrulama - yoklayarak
        wait_flag(8'h10, 3, 200);
        axil_read(8'h10, rdata);
        check("RX_DONE (CFG[3]) HW Set", rdata[3], 1'b1);
        
        axil_read(8'h08, rdata);
        check("RX Data (RDR) Dogru", rdata[15:0], 16'h3412); // LSB first, 0x12 alt bayta
        
        axil_write(8'h10, 32'h00); // Interrupt temizle

        // =====================================================================
        // Sartname s.615: testler manuel inceleme gerektirmeden kendi kendini
        // kontrol etmelidir. Ozet yazdirmak yetmez - hata varsa kosum
        // BASARISIZ bitmelidir.
        // =====================================================================
        $display("--- OZET: %0d PASS, %0d FAIL ---", pass_count, fail_count);

        if (fail_count != 0) begin
            $display("================================================================");
            $display(" I2C TESTI BASARISIZ - %0d hata", fail_count);
            $display("================================================================");
            $fatal(1, "I2C dogrulamasi basarisiz");
        end else if (pass_count == 0) begin
            $fatal(1, "I2C testi hic denetim calistirmadi - testbench bozuk");
        end else begin
            $display("================================================================");
            $display(" I2C TESTI GECTI - %0d denetim, 0 hata", pass_count);
            $display("================================================================");
        end
        $finish;
    end
endmodule