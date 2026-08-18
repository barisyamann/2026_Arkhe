`timescale 1ns / 1ps
// Description: Testbench to verify Arkhe SoC Top Integration in Vivado.
//              Generates a 50 MHz clock, handles system reset, and mocks
//              external peripheral pins to verify early CPU boot cycles.
//
//              Self-checking: error_count + check() + $fatal
//              PC trace `ifdef TRACE_ON ile acilir (varsayilan: kapali)

module tb_soc_top;

    // --- Sinyal Tanımlamaları ---
    logic        clk;
    logic        rst_n;

    // GPIO
    logic [15:0] gpio_i;
    logic [15:0] gpio_o;
    logic [15:0] gpio_tx_en_o;

    // UART1
    logic        uart1_rxd;
    logic        uart1_txd;

    // UART2
    logic        uart2_rxd;
    logic        uart2_txd;

    // I2C
    wire         i2c_sda;
    wire         i2c_scl;

    // QSPI
    logic        qspi_sck;
    logic        qspi_cs_n;
    wire         qspi_io0;
    wire         qspi_io1;
    wire         qspi_io2;
    wire         qspi_io3;

    // JTAG Debug
    logic        jtag_tms;
    logic        jtag_tck;
    logic        jtag_tdi;
    logic        jtag_tdo;
    logic        jtag_trst_n;

    // --- I2C ve QSPI için Pull-up direnç simülasyonları ---
    assign (weak1, weak0) i2c_sda  = 1'b1;
    assign (weak1, weak0) i2c_scl  = 1'b1;
    assign (weak1, weak0) qspi_io0 = 1'b1;
    assign (weak1, weak0) qspi_io1 = 1'b1;
    assign (weak1, weak0) qspi_io2 = 1'b1;
    assign (weak1, weak0) qspi_io3 = 1'b1;

    // =========================================================================
    // Ucdurumlu surucu halkasi
    //
    // soc_top artik cift yonlu pin icermiyor (ASIC akisinda tri-state yalnizca
    // pad halkasinda olabilir); cikis / cikis-etkin / giris uclusu veriyor.
    // Kart uzerinde bu isi nexys_top yapiyor, burada testbench yapiyor.
    // =========================================================================
    wire       i2c_sda_o_w, i2c_sda_oe_w;
    wire       i2c_scl_o_w, i2c_scl_oe_w;
    wire [3:0] qspi_io_o_w, qspi_io_oe_w;
    wire [3:0] qspi_io_w;

    assign i2c_sda = i2c_sda_oe_w ? i2c_sda_o_w : 1'bz;
    assign i2c_scl = i2c_scl_oe_w ? i2c_scl_o_w : 1'bz;

    assign qspi_io_w = {qspi_io3, qspi_io2, qspi_io1, qspi_io0};

    assign qspi_io0 = qspi_io_oe_w[0] ? qspi_io_o_w[0] : 1'bz;
    assign qspi_io1 = qspi_io_oe_w[1] ? qspi_io_o_w[1] : 1'bz;
    assign qspi_io2 = qspi_io_oe_w[2] ? qspi_io_o_w[2] : 1'bz;
    assign qspi_io3 = qspi_io_oe_w[3] ? qspi_io_o_w[3] : 1'bz;

    // --- UUT (Unit Under Test) ---
    soc_top uut (
        .clk_i        (clk),
        .rst_ni       (rst_n),

        .gpio_i       (gpio_i),
        .gpio_o       (gpio_o),
        .gpio_tx_en_o (gpio_tx_en_o),

        .uart1_rxd    (uart1_rxd),
        .uart1_txd    (uart1_txd),

        .uart2_rxd    (uart2_rxd),
        .uart2_txd    (uart2_txd),

        .i2c_sda_o    (i2c_sda_o_w),
        .i2c_sda_oe   (i2c_sda_oe_w),
        .i2c_sda_i    (i2c_sda),
        .i2c_scl_o    (i2c_scl_o_w),
        .i2c_scl_oe   (i2c_scl_oe_w),
        .i2c_scl_i    (i2c_scl),

        .qspi_sck     (qspi_sck),
        .qspi_cs_n    (qspi_cs_n),
        .qspi_io_o    (qspi_io_o_w),
        .qspi_io_oe   (qspi_io_oe_w),
        .qspi_io_i    (qspi_io_w),

        .jtag_tms     (jtag_tms),
        .jtag_tck     (jtag_tck),
        .jtag_tdi     (jtag_tdi),
        .jtag_tdo     (jtag_tdo),
        .jtag_trst_n  (jtag_trst_n)
        );
    // --- QSPI Flash Modeli ---
    // Sartname s.16: sistem QSPI flash'tan boot olur. Yukleyici (boot.hex)
    // uygulamayi (app.hex) buradan okuyup I-RAM'e yazar.
    spi_flash_model #(
        .INIT_FILE  ("app.hex"),
        .WORD_COUNT (2048)
    ) u_flash (
        .sck   (qspi_sck),
        .cs_n  (qspi_cs_n),
        .io0   (qspi_io0),
        .io1   (qspi_io1),
        .io2   (qspi_io2),
        .io3   (qspi_io3)
    );

    // --- SystemVerilog Functional Coverage (Kapsama) Tanımları ---
    covergroup cg_soc_verification @(posedge clk);
        option.per_instance = 1;

        // GPIO çıkışlarının fonksiyonel kapsaması
        cov_gpio: coverpoint gpio_o {
            bins idle     = {16'h0000};
            bins cls_yes  = {16'h5555};
            bins cls_no   = {16'hAAAA};
            bins cls_sil  = {16'h0F0F};
            bins cls_unk  = {16'hFFFF};
        }


        // JTAG TMS pininin geçişleri
        cov_jtag_tms: coverpoint jtag_tms {
            bins low  = {1'b0};
            bins high = {1'b1};
        }

        // AXI-Lite el sıkışma (handshake) kapsaması
        cov_axi_aw: coverpoint (uut.u_npu.u_npu_axi_ctrl.mem_awvalid && uut.u_npu.u_npu_axi_ctrl.mem_awready) {
            bins hit = {1'b1};
        }
        cov_axi_w: coverpoint (uut.u_npu.u_npu_axi_ctrl.mem_wvalid && uut.u_npu.u_npu_axi_ctrl.mem_wready) {
            bins hit = {1'b1};
        }
        cov_axi_ar: coverpoint (uut.u_npu.u_npu_axi_ctrl.mem_arvalid && uut.u_npu.u_npu_axi_ctrl.mem_arready) {
            bins hit = {1'b1};
        }
        cov_axi_r: coverpoint (uut.u_npu.u_npu_axi_ctrl.mem_rvalid && uut.u_npu.u_npu_axi_ctrl.mem_rready) {
            bins hit = {1'b1};
        }

        // =====================================================================
        // R3 - Islevsel kapsama genisletmesi
        //
        // Denetimdeki oranlar (statement %46,6 / branch %30,1 / toggle %21,5)
        // DMA, UART-stream ve kesmeler hic calismazken olculmustu. Bugun
        // hepsi gercek veriyle uyariliyor; asagidaki noktalar bunu OLCULEBILIR
        // hale getiriyor.
        //
        // Denetimin hakli elestirisi soyleydi: dusuk kapsami "kullanilmayan
        // bloklar" diye savunmak yanlis, cunku o bloklar sartnamenin zorunlu
        // tuttugu cevre birimleri. Dolayisiyla kapsama noktalari zorunlu
        // birimlerin GERCEKTEN calistigini gostermeli.
        // =====================================================================

        // Her kesme kaynagi en az bir kez tetiklendi mi?
        cov_irq_npu:   coverpoint uut.npu_irq        { bins fired = {1'b1}; }
        cov_irq_timer: coverpoint uut.timer_irq      { bins fired = {1'b1}; }
        cov_irq_dma:   coverpoint uut.dma_irq        { bins fired = {1'b1}; }
        cov_irq_fault: coverpoint uut.bus_fault_irq  { bins fired = {1'b1}; }

        // DMA durum makinesinin tum durumlari gezildi mi?
        cov_dma_state: coverpoint uut.u_dma.dma_state {
            bins idle       = {3'd0};
            bins read_req   = {3'd1};
            bins read_wait  = {3'd2};
            bins write_req  = {3'd3};
            bins write_wait = {3'd4};
            bins done       = {3'd5};
        }

        // UART-stream FIFO doluluk bolgeleri - akis kontrolunun
        // gercekten calistigini gosterir
        cov_uart2_fifo: coverpoint uut.u_uart2.fifo_level {
            bins bos     = {0};
            bins az      = {[1:63]};
            bins orta    = {[64:191]};
            bins cok     = {[192:255]};
            bins dolu    = {256};
        }

        // NPU sinif cikisi
        cov_npu_class: coverpoint uut.u_npu.class_sig {
            bins silence = {2'd0};
            bins unknown = {2'd1};
            bins yes     = {2'd2};
            bins no      = {2'd3};
        }

        // Veri yolu hata kaynagi - hangi kopru bildirdi
        cov_fault_src: coverpoint {uut.instr_bus_err, uut.data_bus_err} {
            bins yok        = {2'b00};
            bins veri_kopru = {2'b01};
            bins buyruk_kopru = {2'b10};
        }

        // AXI yanit kodlari - SLVERR bilerek uretiliyor (Boot ROM yazmasi)
        cov_axi_resp: coverpoint uut.u_data_bridge.axil_bresp_i
            iff (uut.u_data_bridge.axil_bvalid_i) {
            bins okay   = {2'b00};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }

        // Kesme x sinif caprazi: dogru sinif dogru kesmeyle mi bildirildi
        cross cov_irq_npu, cov_npu_class;
    endgroup

    cg_soc_verification cg_inst = new();

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

    // =========================================================================
    // Self-checking altyapisi
    // =========================================================================
    int error_count = 0;

    task automatic check(input string        ad,
                         input logic [63:0]  gercek,
                         input logic [63:0]  beklenen);
        if (gercek !== beklenen) begin
            error_count++;
            log_print($sformatf("      [HATA] %s: beklenen=0x%h gercek=0x%h", ad, beklenen, gercek));
        end else begin
            log_print($sformatf("      [OK]   %s = 0x%h", ad, gercek));
        end
    endtask

    // --- Test Akışı ---
    initial begin
        log_file = $fopen("simulation.log", "w");
        if (log_file == 0) begin
            $display("HATA: simulation.log dosyası açılamadı!");
        end

        log_print($sformatf("[%0t] SoC Simülasyonu Başlatıldı.", $time));

        // Başlangıç Değerleri
        rst_n       = 1'b0;
        gpio_i      = 16'h0000;
        uart1_rxd   = 1'b1;
        uart2_rxd   = 1'b1;
        jtag_tms    = 1'b0;
        jtag_tck    = 1'b0;
        jtag_tdi    = 1'b0;
        jtag_trst_n = 1'b0;  // JTAG reset aktif

        // JTAG resetini kaldır
        #50;
        jtag_trst_n = 1'b1;

        // Reset Süreci
        #100;
        @ (posedge clk);
        rst_n = 1'b1;

        #1;
        // NPU Yerel Belleğini (TCM SRAM) sıfırlayarak simülasyon X/U belirsizliğini önleme
        for (int idx = 0; idx < 7680; idx = idx + 1) begin
            uut.u_npu.u_npu_sram.ram[idx] = 32'h0;
        end

        // =====================================================================
        // ACILIS SECIMI
        //
        // Gercek iki asamali boot (Boot ROM -> QSPI flash -> I-RAM) calisir
        // durumda ve ayri olarak dogrulanmaktadir. Ancak QSPI aktarimi
        // simulasyonda cok yavas oldugu icin sistem seviyesi testlerinin bu
        // bedeli her kosumda odemesi gereksizdir.
        //
        // Varsayilan: I-RAM dogrudan doldurulur ve Boot ROM'un ilk iki komutu
        //             I-RAM'e atlayacak sekilde degistirilir.
        // Gercek boot zinciri icin derlemeye  -d REAL_BOOT  ekleyin.
        // =====================================================================
    `ifndef REAL_BOOT
        $readmemh("app.hex", uut.u_instruction_ram.ram);
        uut.u_boot_rom.rom_mem[0] = 32'h010002B7;  // lui t0, 0x01000
        uut.u_boot_rom.rom_mem[1] = 32'h00028067;  // jr  t0
        log_print("[TB] HIZLI ACILIS: I-RAM dogrudan yuklendi, yukleyici atlandi.");
        log_print("[TB] Gercek QSPI boot icin derlemeye -d REAL_BOOT ekleyin.");
    `else
        log_print("[TB] GERCEK BOOT: uygulama QSPI flash'tan yuklenecek.");
    `endif

        log_print($sformatf("[%0t] Reset kaldırıldı. İşlemci çalışıyor...", $time));

        // =====================================================================
        // UART-STREAM VERI YOLU (Sartname EK-1 s.21)
        //
        // CPU, UART2'yi 1 Mbps'e ayarlayip DMA'yi kurduktan sonra UART1'den
        // "Stream ready" yazar. Senkronizasyon gercek arayuz uzerinden
        // kuruluyor - stream FIFO'su 256 bayt oldugu icin erken gonderim
        // tasmaya yol acardi.
        // =====================================================================
        fork : wait_stream_ready
            wait (uart_saw_stream_ready);
            #20_000_000;   // 20 ms zaman asimi
        join_any
        disable wait_stream_ready;

        if (!uart_saw_stream_ready) begin
            error_count++;
            log_print("      [HATA] CPU 'Stream ready' yazmadi - UART-stream/DMA kurulumu basarisiz");
        end else begin
            log_print("      [OK]   CPU UART-stream ve DMA'yi kurdu");
            uart2_send_tensor(8'h55);
        end

        // =====================================================================
        // UART_RDR bayt okuma yolu (EK-2, offset 0x08)
        //
        // DMA yolu UARTS_RDR32'yi kullandigi icin bayt yazmaci sistem
        // testinde hic uyarilmiyordu. CPU, DMA bittikten sonra dort bayt
        // okuyup "RDR: A1B2C3D4" yaziyor. Bu ayni anda iki seyi dogrular:
        //   - FIFO okuma gecikmesi dogru ele aliniyor (eskiden bir onceki
        //     bayt donuyordu)
        //   - UARTS_RDR32 toplayicisi artik bayt calmiyor
        // =====================================================================
        fork : wait_dma_done
            wait (uart_saw_dma_done);
            #2_000_000;
        join_any
        disable wait_dma_done;

        if (uart_saw_dma_done) begin
            log_print("[TB] UART_RDR testi: A1 B2 C3 D4 gonderiliyor");
            uart2_send_byte(8'hA1);
            uart2_send_byte(8'hB2);
            uart2_send_byte(8'hC3);
            uart2_send_byte(8'hD4);
        end

        // NPU donanım motorunun hesaplamayı bitirmesini dinamik olarak bekle
        log_print($sformatf("[%0t] NPU donanım motorunun tamamlanması bekleniyor...", $time));

        // Zaman asimi sart: bu bekleme eskiden cipsizdi ve NPU hic
        // baslamazsa simulasyon sonsuza kadar asili kaliyordu. 18 Agustos'ta
        // tam olarak bu oldu, kosum elle durdurulmak zorunda kalindi.
        // NPU hesaplamasi ~20 ms surer, 60 ms rahat bir ust sinir.
        fork : wait_npu
            wait (uut.u_npu.u_npu_engine.done_o == 1'b1);
            #60_000_000;
        join_any
        disable wait_npu;

        if (uut.u_npu.u_npu_engine.done_o !== 1'b1) begin
            error_count++;
            log_print("      [HATA] NPU zaman asimi - DONE sinyali 60 ms icinde gelmedi");
        end else begin
            log_print($sformatf("[%0t] NPU donanım motoru DONE sinyalini verdi!", $time));
        end

        // =====================================================================
        // KONTROL 1: CPU sinif sonucunu okuyup GPIO'ya yazdi mi?
        //
        // Sinifin 2 mi 3 mu oldugunu burada kontrol etmiyoruz; gercek
        // agirliklarla bu girdinin hangi sinifa dustugu ayrica olculecek.
        // Burada kanitlanan sey: CPU -> NPU -> CPU -> GPIO zinciri calisiyor.
        //
        // CPU once UART'tan "Class: N" yazdirdigi icin (~1.3 ms) zaman asimli
        // bekleme kullaniyoruz.
        // =====================================================================
        fork : wait_gpio
        wait (gpio_o == 16'h5555 || gpio_o == 16'hAAAA || gpio_o == 16'h0F0F);

            #5_000_000;   // 5 ms zaman asimi
        join_any
        disable wait_gpio;

        if (gpio_o == 16'h5555 || gpio_o == 16'hAAAA || gpio_o == 16'h0F0F) begin

            log_print($sformatf("      [OK]   CPU sinif sonucunu GPIO'ya yazdi: 0x%h", gpio_o));
        end else begin
            error_count++;
            log_print($sformatf("      [HATA] GPIO 5 ms icinde beklenen desende yazilmadi: 0x%h", gpio_o));
        end
                // ISR gercekten calisip UART'tan yazdirdi mi?
        // Sartname s.16: "... sonuclari UART arayuzu uzerinden yazdirmalidir."
        // DMA, UART-stream'den TCM'e tasimayi tamamladi mi?
        // Sartname EK-1 s.21: veri UART-stream uzerinden hizlandirici
        // bellegine yazilmali.
        if (uart_saw_dma_done) begin
            log_print("      [OK]   DMA UART-stream verisini TCM'e tasidi");
        end else begin
            error_count++;
            log_print("      [HATA] DMA tamamlanmadi - UART-stream veri yolu calismiyor");
        end

        // Veri yolu hata kesmesi (R8): Boot ROM'a yapilan kasitli yazma
        // SLVERR dondurdu mu, kopru yakaladi mi, ISR dogru adresi gordu mu?
        if (uart_fault_line == "Bus fault @ 0x00000100 ST=0x05") begin
            log_print("      [OK]   Veri yolu hatasi yakalandi, adres ve kaynak dogru");
        end else begin
            error_count++;
            log_print($sformatf("      [HATA] Veri yolu hata kesmesi yanlis - beklenen \"Bus fault @ 0x00000100 ST=0x05\", gelen \"%s\"",
                                uart_fault_line));
        end

        // I2C: kole yokken protokol motoru NACK gorup kendini sonlandirdi mi?
        // Beklenen CFG = 0x02  -> TX_EN dustu (bit0=0), TX_DONE kuruldu (bit1=1)
        if (uart_i2c_line == "I2C CFG=0x02") begin
            log_print("      [OK]   I2C protokol motoru NACK ile dogru sonlandi");
        end else begin
            error_count++;
            log_print($sformatf("      [HATA] I2C yanlis - beklenen \"I2C CFG=0x02\", gelen \"%s\"",
                                uart_i2c_line));
        end

        // UART_RDR bayt yolu: gonderilen dort bayt aynen okundu mu?
        if (uart_rdr_line == "RDR: A1B2C3D4") begin
            log_print("      [OK]   UART_RDR bayt okuma dogru: A1B2C3D4");
        end else begin
            error_count++;
            log_print($sformatf("      [HATA] UART_RDR yanlis - beklenen \"RDR: A1B2C3D4\", gelen \"%s\"",
                                uart_rdr_line));
        end

        if (uart_saw_irq) begin
            log_print("      [OK]   ISR sonucu UART'tan yazdirdi");
        end else begin
            error_count++;
            log_print("      [HATA] ISR'in UART ciktisi gorulmedi");
        end

        // GPIO Pinlerini Değiştirip Test Etme
        @ (posedge clk);
        gpio_i = 16'hA5A5;
        log_print($sformatf("[%0t] GPIO girişleri 0xA5A5 olarak ayarlandı.", $time));

        #5000;
        run_jtag_test();
        log_print($sformatf("[%0t] SoC Simülasyonu Tamamlandı.", $time));

        // =====================================================================
        // Sonuc ozeti - hem ekrana hem log dosyasina yazilir
        // =====================================================================
        log_print("================================================================");
        if (error_count != 0) begin
            log_print($sformatf(" TEST BASARISIZ - %0d hata bulundu", error_count));
        end else begin
            log_print(" TUM TESTLER GECTI - 0 hata");
        end
        log_print("================================================================");

        if (log_file != 0) begin
            $fclose(log_file);
            log_file = 0;
        end

        // Makine-okunabilir sonuc: simulator cikis kodu
        if (error_count != 0) begin
            $fatal(1, "Dogrulama basarisiz");
        end else begin
            $finish;
        end

    end

    // =========================================================================
    // İzleme (Monitoring)
    //
    // Cevrim basina PC trace varsayilan olarak KAPALI. Acmak icin Vivado
    // simulasyon derleme secenegine  -d TRACE_ON  ekleyin.
    // (T2.1 Spike trace karsilastirmasi bu logu kullanir.)
    // =========================================================================
`ifdef TRACE_ON
    logic [31:0] last_pc = 32'h0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (uut.u_core.id_stage_i.pc_id_i !== last_pc) begin
                last_pc <= uut.u_core.id_stage_i.pc_id_i;
                // Polling döngüsünü log kirliliğini önlemek için filtrele
                if (uut.u_core.id_stage_i.pc_id_i != 32'h0100002c &&
                    uut.u_core.id_stage_i.pc_id_i != 32'h01000030 &&
                    uut.u_core.id_stage_i.pc_id_i != 32'h01000034) begin
                    log_print($sformatf("[%0t] PC_ID=0x%h | x10(a0)=0x%h | x12(a2)=0x%h | x13(a3)=0x%h | x14(a4)=0x%h | x15(a5)=0x%h | awaddr=0x%h | awvalid=%b | rx_wr=%0d | rx_rd=%0d | rx_empty=%0b",
                             $time,
                             uut.u_core.id_stage_i.pc_id_i,
                             uut.u_core.id_stage_i.register_file_i.mem[10],
                             uut.u_core.id_stage_i.register_file_i.mem[12],
                             uut.u_core.id_stage_i.register_file_i.mem[13],
                             uut.u_core.id_stage_i.register_file_i.mem[14],
                             uut.u_core.id_stage_i.register_file_i.mem[15],
                             uut.data_axil_awaddr,
                             uut.data_axil_awvalid,
                             uut.u_qspi.rx_wr_ptr,
                             uut.u_qspi.rx_rd_ptr,
                             uut.u_qspi.rx_empty));
                end
            end
        end
    end
`endif

    always @(gpio_o) begin
        log_print($sformatf("[%0t] GPIO Çıkışı Değişti: gpio_o = 16'h%h", $time, gpio_o));
    end
        // =========================================================================
    // UART TX izleyici
    //
    // Islemcinin uart1_txd hattina bastigi bitleri cozup karakterlere
    // cevirir ve satir satir loga yazar. Iki ise yariyor:
    //   1) ISR'in urettigi cikti gorunur olur
    //   2) UART TX yolu ilk kez dogrulanmis olur - bugune kadar hicbir
    //      test bu hatti okumuyordu
    //
    // 115200 baud, 8N1. main.c'de CPB = 434, sistem saati 50 MHz:
    //   bit suresi = 434 x 20 ns = 8680 ns
    // =========================================================================
    localparam int UART_BIT_NS = 8680;

    string uart_line   = "";
    bit    uart_saw_irq = 1'b0;
    bit    uart_saw_stream_ready = 1'b0;
    bit    uart_saw_dma_done     = 1'b0;
    string uart_rdr_line         = "";
    string uart_fault_line       = "";
    string uart_i2c_line         = "";

    task automatic uart_monitor();
        logic [7:0] ch;
        forever begin
            @(negedge uart1_txd);               // start biti
            #(UART_BIT_NS / 2);                 // bit ortasina git
            if (uart1_txd !== 1'b0) continue;   // gecersiz start, yoksay

            for (int i = 0; i < 8; i++) begin   // 8 veri biti, LSB once
                #(UART_BIT_NS);
                ch[i] = uart1_txd;
            end
            #(UART_BIT_NS);                     // stop biti

            if (ch == 8'h0A) begin              // satir sonu
                log_print($sformatf("[UART] %s", uart_line));
                if (uart_line.len() >= 5 && uart_line.substr(0,4) == "[IRQ]")
                    uart_saw_irq = 1'b1;
                if (uart_line == "Stream ready")
                    uart_saw_stream_ready = 1'b1;
                if (uart_line == "DMA done")
                    uart_saw_dma_done = 1'b1;
                if (uart_line.len() >= 5 && uart_line.substr(0,4) == "RDR: ")
                    uart_rdr_line = uart_line;
                if (uart_line.len() >= 14 && uart_line.substr(0,13) == "Bus fault @ 0x")
                    uart_fault_line = uart_line;
                // substr(a,b) SystemVerilog'da HER IKI UCU da kapsar: substr(0,6) yedi
                // karakter dondurur. Onceki surumde substr(0,7) yazilmisti ve
                // sekiz karakterle ("I2C CFG=") karsilastirdigi icin hic eslesmedi.
                if (uart_line.len() >= 7 && uart_line.substr(0,6) == "I2C CFG")
                    uart_i2c_line = uart_line;
                uart_line = "";
            end else if (ch != 8'h0D) begin     // \r yoksay
                uart_line = {uart_line, ch};
            end
        end
    endtask

    initial begin
        wait (rst_n === 1'b1);
        #1000;
        uart_monitor();
    end

    // =========================================================================
    // UART-stream gonderici
    //
    // Sartname EK-1 s.21: "UART-stream cevresel birimi cikarim yapilacak
    // veriyi iletecek ve bu veri istenilen hizlandirici bellek adresine
    // yazilacaktir."
    //
    // 1 Mbps, 8N1. main.c UART2'yi CPB = 50 ile yapilandiriyor
    // (50 MHz / 1 Mbps), yani bit suresi 50 x 20 ns = 1000 ns.
    // Genel UART 115200'de kaldigi icin "en az iki farkli baud hizi"
    // isteri de karsilanmis olur (EK-2 s.22).
    // =========================================================================
    localparam int UART2_BIT_NS = 1000;

    task automatic uart2_send_byte(input logic [7:0] b);
        uart2_rxd = 1'b0;                 // start biti
        #(UART2_BIT_NS);
        for (int i = 0; i < 8; i++) begin
            uart2_rxd = b[i];             // LSB once
            #(UART2_BIT_NS);
        end
        uart2_rxd = 1'b1;                 // stop biti
        #(UART2_BIT_NS);
    endtask

    task automatic uart2_send_tensor(input logic [7:0] pattern);
        log_print($sformatf("[TB] UART-stream'den 1960 bayt gonderiliyor (0x%02h)", pattern));
        for (int i = 0; i < 1960; i++) begin
            uart2_send_byte(pattern);
        end
        log_print("[TB] UART-stream gonderimi tamamlandi");
    endtask

    // Kesme izleyicileri - KENAR tetikli.
    //
    // Seviye tetikli olsalardi kesme hatti yuksek kaldigi her cevrimde
    // satir basarlardi: DMA kesmesi ISR onu temizleyene kadar ~190 cevrim
    // ayakta kaldi ve log okunamaz hale geldi. Yalnizca yukselen kenari
    // bildirmek hem dogru bilgiyi verir hem de kesmenin gercekten
    // temizlendigini gormeyi saglar.
    logic dma_irq_d, i2c_irq_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_irq_d <= 1'b0;
            i2c_irq_d <= 1'b0;
        end else begin
            dma_irq_d <= uut.dma_irq;
            i2c_irq_d <= uut.i2c_irq;

            if (uut.dma_irq && !dma_irq_d)
                log_print($sformatf("[%0t] *** DMA Transfer Tamamlandı - IRQ aktif ***", $time));
            if (!uut.dma_irq && dma_irq_d)
                log_print($sformatf("[%0t] *** DMA kesmesi temizlendi ***", $time));

            if (uut.i2c_irq && !i2c_irq_d)
                log_print($sformatf("[%0t] *** I2C İşlemi Tamamlandı - IRQ aktif ***", $time));
        end
    end

    // --- AXI4-Lite Protokol Denetleyicisi Bağlantısı (SVA) ---
    bind soc_top axil_protocol_checker u_protocol_checker (
        .clk      (clk_i),
        .rst_n    (rst_ni),
        .awaddr   (merged_m_awaddr),
        .awvalid  (merged_m_awvalid),
        .awready  (merged_m_awready),
        .wdata    (merged_m_wdata),
        .wstrb    (merged_m_wstrb),
        .wvalid   (merged_m_wvalid),
        .wready   (merged_m_wready),
        .bresp    (merged_m_bresp),
        .bvalid   (merged_m_bvalid),
        .bready   (merged_m_bready),
        .araddr   (merged_m_araddr),
        .arvalid  (merged_m_arvalid),
        .arready  (merged_m_arready),
        .rdata    (merged_m_rdata),
        .rresp    (merged_m_rresp),
        .rvalid   (merged_m_rvalid),
        .rready   (merged_m_rready)
    );

    // =========================================================================
    // JTAG Sürücü Yardımcı Görevleri (Tasks)
    // =========================================================================

    // TCK darbesi üret
    task automatic jtag_clock();
        jtag_tck = 1'b0;
        #100;
        jtag_tck = 1'b1;
        #100;
        jtag_tck = 1'b0;
    endtask

    // JTAG TAP reset durumuna getir
    task automatic jtag_reset();
        log_print("     [JTAG] TAP Reset yapiliyor...");
        jtag_trst_n = 1'b0;
        #100;
        jtag_trst_n = 1'b1;
        jtag_tms = 1'b1;
        repeat (5) jtag_clock();
        jtag_tms = 1'b0;
        jtag_clock(); // TAP_IDLE durumuna geç
    endtask

    // IR (Instruction Register) Shift et
    task automatic jtag_shift_ir(input logic [3:0] ir_in);
        jtag_tms = 1'b1; jtag_clock(); // -> SELECT_DR_SCAN
        jtag_tms = 1'b1; jtag_clock(); // -> SELECT_IR_SCAN
        jtag_tms = 1'b0; jtag_clock(); // -> CAPTURE_IR
        jtag_tms = 1'b0; jtag_clock(); // -> SHIFT_IR

        for (int i = 0; i < 4; i++) begin
            jtag_tdi = ir_in[i];
            jtag_tms = (i == 3) ? 1'b1 : 1'b0;   // Son bitte EXIT1_IR
            jtag_clock();
        end

        jtag_tms = 1'b1; jtag_clock(); // -> UPDATE_IR
        jtag_tms = 1'b0; jtag_clock(); // -> RUN_TEST_IDLE
    endtask

    // DR (Data Register) Shift et
    task automatic jtag_shift_dr(input  logic [63:0] dr_in,
                                 input  int          len,
                                 output logic [63:0] dr_out);
        jtag_tms = 1'b1; jtag_clock(); // -> SELECT_DR_SCAN
        jtag_tms = 1'b0; jtag_clock(); // -> CAPTURE_DR
        jtag_tms = 1'b0; jtag_clock(); // -> SHIFT_DR

        for (int i = 0; i < len; i++) begin
            jtag_tdi = dr_in[i];
            jtag_tms = (i == len - 1) ? 1'b1 : 1'b0;   // Son bitte EXIT1_DR
            jtag_clock();
            dr_out[i] = jtag_tdo;
        end

        jtag_tms = 1'b1; jtag_clock(); // -> UPDATE_DR
        jtag_tms = 1'b0; jtag_clock(); // -> RUN_TEST_IDLE
    endtask

    // Ana JTAG Test Senaryosu
    task automatic run_jtag_test();
        logic [63:0] jtag_rdata;
        log_print("\n================================================================");
        log_print(" JTAG HATA AYIKLAMA (DEBUG) PORTU DOGRULAMA TESTI BASLATILDI");
        log_print("================================================================");

        jtag_reset();

        // 1. IDCODE OKUMA
        log_print(" ---> JTAG IDCODE okunuyor...");
        jtag_shift_ir(4'h1); // IR_IDCODE
        jtag_shift_dr(64'h0, 32, jtag_rdata);
        check("JTAG IDCODE", jtag_rdata[31:0], 32'h41524B48);

        // 2. CPU HALT (DURDURMA)
        log_print(" ---> CPU'ya HALT istegi gonderiliyor...");
        jtag_shift_ir(4'h4); // IR_DBG_CTRL
        jtag_shift_dr(64'h1, 64, jtag_rdata);
        #100;
        check("CPU halt (debug_req_o)", uut.u_jtag.debug_req_o, 1'b1);

        // 3. JTAG BELLEK YAZMA (TCM SRAM'e yaz)
        log_print(" ---> JTAG uzerinden TCM SRAM adresine veri yaziliyor (0x20011000 = 0xDEADBEEF)...");
        jtag_shift_ir(4'h3); // IR_MEM_WRITE
        jtag_shift_dr({32'hDEADBEEF, 32'h20011000}, 64, jtag_rdata);
        #500;

        // 4. JTAG BELLEK OKUMA (TCM SRAM'den oku)
        log_print(" ---> JTAG uzerinden TCM SRAM adresi okunuyor (0x20011000)...");
        jtag_shift_ir(4'h2); // IR_MEM_READ
        jtag_shift_dr({32'h0, 32'h20011000}, 64, jtag_rdata);
        #500;
        jtag_shift_dr(64'h0, 64, jtag_rdata);   // veri bir sonraki shift'te TDO'dan gelir
        check("JTAG bellek okuma/yazma", jtag_rdata[63:32], 32'hDEADBEEF);

        // 5. CPU RESUME (DEVAM ETTİRME)
        log_print(" ---> CPU Resume ediliyor...");
        jtag_shift_ir(4'h4); // IR_DBG_CTRL
        jtag_shift_dr(64'h0, 64, jtag_rdata);
        #100;
        check("CPU resume (debug_req_o)", uut.u_jtag.debug_req_o, 1'b0);

        log_print("================================================================");
        log_print(" JTAG PORTU DOGRULAMA TESTI TAMAMLANDI");
        log_print("================================================================");
    endtask

endmodule
