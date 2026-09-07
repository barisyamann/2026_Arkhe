`timescale 1ns / 1ps
// ==============================================================================
//  nexys_top.sv
//  Nexys 4 DDR (XC7A100T) Top Level Wrapper for Arkhe RISC-V SoC
// ==============================================================================

module nexys_top (
    input  logic        CLK100MHZ,      // Pin E3 (100 MHz onboard oscillator)
    input  logic        CPU_RESETN,     // Pin C12 (Active-Low CPU Reset Button)

    // GPIO (Switches and LEDs)
    input  logic [15:0] SW,             // 16 slide switches
    output logic [15:0] LED,            // 16 LEDs above the switches

    // UART 1 (USB-UART Bridge)
    input  logic        UART_TXD_IN,    // Pin C4 (RX on FPGA side)
    output logic        UART_RXD_OUT,   // Pin D4 (TX on FPGA side)

    // -------------------------------------------------------------------------
    // I2C Master - Pmod JA (22 Agustos 2026'da eklendi)
    //
    // ONCEKI DURUM: I2C hatlari yalnizca modul ICINDE kablolanmisti, karta
    // hic cikmiyordu. Yani sartname 5.2'nin istedigi "kurul tarafindan
    // verilecek test senaryolari" arasinda bir I2C senaryosu olsaydi
    // kosulamazdi.
    //
    // ACIK DRENAJ: her iki hat da yalnizca asagi cekilir, asla yukari
    // surulmez. Yukari cekme direnci gerekir - XDC'de PULLUP TRUE ile
    // FPGA'nin dahili zayif direnci (~50 kOhm) etkinlestirildi. Bu
    // fonksiyonel testler icin yeterlidir; 400 kHz'de guvenilir kenar
    // icin HARICI 2,2-4,7 kOhm direnc onerilir.
    // -------------------------------------------------------------------------
    inout  wire         I2C_SCL,        // Pmod JA1 - C17
    inout  wire         I2C_SDA,        // Pmod JA2 - D18

    // -------------------------------------------------------------------
    // QSPI NOR Flash - KART USTU Spansion S25FL128S (16 MB)
    //
    // F2 karari (23 Agustos 2026): harici Pmod modulu alinmadi, kartin
    // kendi flash'i kullaniliyor.
    //
    // DIKKAT: Saat (CCLK) burada YOKTUR. 7-serisinde flash saati ozel bir
    // yapilandirma pinidir; XDC ile atanamaz, STARTUPE2/USRCCLKO
    // uzerinden surulur (asagida).
    // -------------------------------------------------------------------
    output logic        QSPI_CS_N,      // L13
    inout  wire  [3:0]  QSPI_DQ         // K17 K18 L14 M14
);

    // 100 MHz -> 50 MHz Saat Bölücü (Clock Divider)
    // Donanım üzerinde kararlı çalışması için saat sinyali BUFG üzerinden geçirilir.
    logic clk_50mhz_reg = 1'b0;
    always_ff @(posedge CLK100MHZ) begin
        clk_50mhz_reg <= ~clk_50mhz_reg;
    end

    logic clk_50mhz;
    BUFG bufg_clk (
        .I(clk_50mhz_reg),
        .O(clk_50mhz)
    );

    // CPU Reset Sinyali için İki Aşamalı Senkronizatör (Reset Synchronizer)
    // Asenkron reset de-assertion kararsızlıklarını (metastability) ve CPU başlangıç kilitlenmelerini önler.
    logic rst_n_sync_reg1 = 1'b0;
    logic rst_n_sync      = 1'b0;
    always_ff @(posedge clk_50mhz or negedge CPU_RESETN) begin
        if (!CPU_RESETN) begin
            rst_n_sync_reg1 <= 1'b0;
            rst_n_sync      <= 1'b0;
        end else begin
            rst_n_sync_reg1 <= 1'b1;
            rst_n_sync      <= rst_n_sync_reg1;
        end
    end

    // =========================================================================
    // Ucdurumlu (tri-state) surucu halkasi
    //
    // soc_top artik cift yonlu pin ICERMEZ; cikis / cikis-etkin / giris
    // uclusu verir. Gercek 'z surumu burada, en ust seviyede yapiliyor -
    // ASIC akisinda bu katmanin yerini pad halkasi alir.
    //
    // I2C -> Pmod JA. QSPI -> KART USTU Spansion S25FL128S (F2 karari,
    // 23 Agustos 2026). Harici modul alinmadi; kartin kendi flash'i
    // kullaniliyor.
    // =========================================================================
    wire       i2c_sda_o_w, i2c_sda_oe_w;
    wire       i2c_scl_o_w, i2c_scl_oe_w;
    wire [3:0] qspi_io_o_w, qspi_io_oe_w;
    wire       qspi_sck_w, qspi_cs_n_w;

    // I2C acik drenaj: yalnizca asagi cekilir, asla yukari surulmez.
    // oe yuksekken bile '1' surulmez - bu I2C'nin tanimi geregidir.
    assign I2C_SDA = (i2c_sda_oe_w && !i2c_sda_o_w) ? 1'b0 : 1'bz;
    assign I2C_SCL = (i2c_scl_oe_w && !i2c_scl_o_w) ? 1'b0 : 1'bz;

    // -------------------------------------------------------------------------
    // QSPI veri hatlari - kart ustu flash'a cift yonlu baglanti
    // -------------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_qspi_io
            assign QSPI_DQ[gi] = qspi_io_oe_w[gi] ? qspi_io_o_w[gi] : 1'bz;
        end
    endgenerate

    assign QSPI_CS_N = qspi_cs_n_w;

    // -------------------------------------------------------------------------
    // QSPI SAATI - STARTUPE2 UZERINDEN CIKMAK ZORUNDA
    //
    // 7-serisi Artix'te flash saati (CCLK) NORMAL BIR KULLANICI PINI DEGILDIR.
    // Yapilandirma (configuration) devresine ait ozel bir pindir ve XDC ile
    // bir pakete atanamaz. Kullanici mantiginin flash saatini surebilmesinin
    // TEK yolu STARTUPE2 ilkel blogunun USRCCLKO girisidir.
    //
    // Bu detay atlanirsa sentez hata vermez - tasarim kurulur, bitstream
    // uretilir, ama flash'tan HICBIR SEY okunmaz cunku saat pine hic
    // ulasmaz. Sessiz bir basarisizliktir.
    //
    // USRCCLKTS = 0 -> cikis surucusu etkin (ts = tri-state, ters mantik)
    // USRDONEO / USRDONETS -> DONE pinine dokunmuyoruz, varsayilanda birakiliyor
    // -------------------------------------------------------------------------
    STARTUPE2 #(
        .PROG_USR      ("FALSE"),
        .SIM_CCLK_FREQ (0.0)
    ) u_startupe2 (
        .CFGCLK    (),          // kullanilmiyor
        .CFGMCLK   (),          // kullanilmiyor
        .EOS       (),          // kullanilmiyor
        .PREQ      (),          // kullanilmiyor
        .CLK       (1'b0),
        .GSR       (1'b0),
        .GTS       (1'b0),
        .KEYCLEARB (1'b0),
        .PACK      (1'b0),
        .USRCCLKO  (qspi_sck_w),  // <-- flash saati buradan cikar
        .USRCCLKTS (1'b0),        // 0 = surucu etkin
        .USRDONEO  (1'b1),
        .USRDONETS (1'b1)
    );

    // SoC Ana Modülünün Çağrılması
    soc_top u_soc (
        .clk_i          (clk_50mhz),
        .rst_ni         (rst_n_sync),

        // GPIO
        .gpio_i         (SW),
        .gpio_o         (LED),
        .gpio_tx_en_o   (), // Kullanılmıyor

        // UART 1 (USB-to-UART Bridge)
        .uart1_rxd      (UART_TXD_IN),
        .uart1_txd      (UART_RXD_OUT),

        // UART 2 (Kullanılmıyor, High-Z kalması için 1'e çekildi)
        .uart2_rxd      (1'b1),
        .uart2_txd      (),

        // I2C Master -> Pmod JA
        .i2c_sda_o      (i2c_sda_o_w),
        .i2c_sda_oe     (i2c_sda_oe_w),
        .i2c_sda_i      (I2C_SDA),
        .i2c_scl_o      (i2c_scl_o_w),
        .i2c_scl_oe     (i2c_scl_oe_w),
        .i2c_scl_i      (I2C_SCL),

        // QSPI NOR Flash - kart ustu S25FL128S (F2)
        .qspi_sck       (qspi_sck_w),
        .qspi_cs_n      (qspi_cs_n_w),
        .qspi_io_o      (qspi_io_o_w),
        .qspi_io_oe     (qspi_io_oe_w),
        .qspi_io_i      (QSPI_DQ),

        // JTAG (Kullanılmıyor - Kararsız çalışmayı önlemek için güvenli durumlara çekildi)
        .jtag_tms       (1'b1),
        .jtag_tck       (1'b0),
        .jtag_tdi       (1'b0),
        .jtag_tdo       (),
        .jtag_trst_n    (1'b1)
    );

endmodule
