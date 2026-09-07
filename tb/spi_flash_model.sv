`timescale 1ns / 1ps
// =============================================================================
//  spi_flash_model.sv - Davranissal SPI/QSPI NOR Flash modeli
//
//  Sartname s.16: sistem QSPI master arayuzunden non-volatile bir bellekten
//  boot olmalidir. Bu model, simulasyonda o flash'in yerini alir.
//
//  22 AGUSTOS 2026 - GENISLETILDI
//
//    Onceki surum YALNIZCA READ (0x03) destekliyordu. Bu yuzden
//    qspi_master'in yazma, silme ve durum yollari HIC test edilmiyordu;
//    kapsama olcumunde modul %58,4 statement ile en dusuk bizim
//    modulumuzdu. Sartname s.24 su komutlari zorunlu tutuyor ve hepsi
//    RTL'de gerceklenmis ama dogrulanmamisti.
//
//  DESTEKLENEN KOMUTLAR
//    0x03  READ   tek hatli okuma
//    0x6B  QOR    dortlu hatli okuma (dummy cevrimli)
//    0x06  WREN   yazma etkinlestir  (WEL <- 1)
//    0x04  WRDI   yazma devre disi   (WEL <- 0)
//    0x05  RDSR1  durum yazmaci oku  {6'b0, WEL, WIP}
//    0x9F  RDID   uretici/cihaz kimligi (3 bayt)
//    0x02  PP     sayfa programla (tek hatli)   - WEL gerektirir
//    0xD8  SE     sektor sil (64 kB -> 0xFF)    - WEL gerektirir
//
//  PROTOKOL
//    SPI Mode 0 (CPOL=0, CPHA=0), MSB once.
//    Master cikisini DUSEN kenarda gunceller; model YUKSELEN kenarda
//    ornekler. Model cikisini DUSEN kenarda surer.
//
//    Hat eslemeleri qspi_master.sv ile birebir ayni:
//      x1 okuma : io1
//      x4 okuma : {io3, io2, io1, io0}   (io3 en anlamli)
//      x1 yazma : io0
// =============================================================================

module spi_flash_model #(
    // -----------------------------------------------------------------
    // APP_OFS - imajin flash icindeki MANTIKSAL adresi (23 Agustos 2026)
    //
    // F2'de kart ustu flash kullaniliyor ve basinda FPGA bitstream'i
    // duruyor; uygulama 0x800000'e programlaniyor. Bootloader da oradan
    // okuyor. Simulasyonun bunu birebir modellemesi gerekir, yoksa test
    // gercek donanimdan BASKA bir seyi dogrular.
    //
    // 8 MB'lik bir dizi ayirmamak icin imaj yine dizinin basinda tutulur;
    // yalnizca ADRES ESLEMESI kaydirilir: mantiksal APP_OFS -> indeks 0.
    // -----------------------------------------------------------------
    parameter int unsigned APP_OFS = 0,
    parameter string INIT_FILE  = "app.hex",
    parameter int    WORD_COUNT = 2048,     // 2048 x 4 = 8 kB
    // Adres fazi genisligi: 3 = eski davranis (24 bit), 4 = 4-bayt mod.
    // Gercek NOR flash bunu bir mod bitiyle secer; modelde parametredir.
    parameter int    ADDR_BYTES = 3,
    // RDID yaniti - S25FL ailesi bicimi (uretici, tip, kapasite)
    parameter logic [23:0] JEDEC_ID = 24'h01_02_19,
    // Sektor boyutu (SE komutu bu kadar bayti 0xFF yapar)
    parameter int    SECTOR_BYTES = 4096
)(
    input  logic sck,
    input  logic cs_n,
    inout  wire  io0,
    inout  wire  io1,
    inout  wire  io2,
    inout  wire  io3
);

    localparam int BYTE_COUNT = WORD_COUNT * 4;

    logic [31:0] mem_w [0:WORD_COUNT-1];
    logic [7:0]  mem_b [0:BYTE_COUNT-1];

    initial begin
        for (int i = 0; i < WORD_COUNT; i++) mem_w[i] = 32'h0;
        $readmemh(INIT_FILE, mem_w);
        // 32-bit little-endian kelimeleri bayt dizisine ac
        for (int i = 0; i < WORD_COUNT; i++) begin
            mem_b[i*4 + 0] = mem_w[i][7:0];
            mem_b[i*4 + 1] = mem_w[i][15:8];
            mem_b[i*4 + 2] = mem_w[i][23:16];
            mem_b[i*4 + 3] = mem_w[i][31:24];
        end
        $display("[SPI_FLASH] %0d bayt yuklendi: %s", BYTE_COUNT, INIT_FILE);
    end

    // -------------------------------------------------------------------------
    // Cikis suruculeri
    //
    // Tek hatli okumada yalnizca io1 surulur. Dortlu okumada dordu birden.
    // Yazma komutlarinda model hicbir hatti surmez.
    // -------------------------------------------------------------------------
    logic       drive_x1 = 1'b0;      // io1 surulsun
    logic       drive_x4 = 1'b0;      // io0..io3 surulsun
    logic [3:0] out_nib  = 4'h0;

    assign io0 = drive_x4 ? out_nib[0] : 1'bz;
    assign io1 = drive_x4 ? out_nib[1] : (drive_x1 ? out_nib[1] : 1'bz);
    assign io2 = drive_x4 ? out_nib[2] : 1'bz;
    assign io3 = drive_x4 ? out_nib[3] : 1'bz;

    // -------------------------------------------------------------------------
    // Durum
    // -------------------------------------------------------------------------
    localparam int PH_CMD   = 0;
    localparam int PH_ADDR  = 1;
    localparam int PH_DUMMY = 2;
    localparam int PH_RD1   = 3;   // tek hatli okuma
    localparam int PH_RD4   = 4;   // dortlu okuma
    localparam int PH_WR1   = 5;   // tek hatli yazma (PP)
    localparam int PH_NONE  = 6;   // veri fazi yok

    localparam logic [7:0] CMD_READ  = 8'h03;
    localparam logic [7:0] CMD_QOR   = 8'h6B;
    localparam logic [7:0] CMD_WREN  = 8'h06;
    localparam logic [7:0] CMD_WRDI  = 8'h04;
    localparam logic [7:0] CMD_RDSR1 = 8'h05;
    localparam logic [7:0] CMD_RDID  = 8'h9F;
    localparam logic [7:0] CMD_PP    = 8'h02;
    localparam logic [7:0] CMD_SE    = 8'hD8;

    localparam int QOR_DUMMY = 8;   // QOR icin dummy cevrim (bit) sayisi

    logic [7:0]  cmd_reg;
    logic [31:0] addr_reg;

    // Mantiksal flash adresini dizi indeksine cevirir. APP_OFS altindaki
    // veya imaj sonrasindaki adresler gecersizdir (bos flash = 0xFF degil
    // 0x00 donuyoruz - mevcut davranis korundu).
    function automatic bit gecerli(input logic [31:0] a);
        return (a >= APP_OFS) && ((a - APP_OFS) < BYTE_COUNT);
    endfunction

    function automatic int unsigned indeks(input logic [31:0] a);
        return int'(a - APP_OFS);
    endfunction
    logic [7:0]  out_shift;
    logic [7:0]  in_shift;
    int          bit_cnt;
    int          phase;
    int          id_idx;

    logic        wel = 1'b0;        // write enable latch

    // Istatistik - testbench dogrulamak icin okuyabilir
    int          pp_bayt   = 0;     // programlanan bayt sayisi
    int          se_sayisi = 0;     // silinen sektor sayisi

    // -------------------------------------------------------------------------
    // Yeni islem baslangici
    // -------------------------------------------------------------------------
    always @(negedge cs_n) begin
        bit_cnt  = 0;
        phase    = PH_CMD;
        cmd_reg  = 8'h00;
        addr_reg = 32'h0;
        in_shift = 8'h00;
        id_idx   = 0;
        drive_x1 = 1'b0;
        drive_x4 = 1'b0;
    end

    always @(posedge cs_n) begin
        drive_x1 = 1'b0;
        drive_x4 = 1'b0;
        // Yazma/silme islemi CS yukselince tamamlanir; WEL otomatik duser
        if (cmd_reg == CMD_PP || cmd_reg == CMD_SE)
            wel = 1'b0;
    end

    // -------------------------------------------------------------------------
    // Yukselen kenar: master'in surdugu biti ornekle
    // -------------------------------------------------------------------------
    always @(posedge sck) begin
        if (!cs_n) begin
            case (phase)
                // ---------------------------------------------------------
                PH_CMD: begin
                    cmd_reg = {cmd_reg[6:0], io0};
                    bit_cnt = bit_cnt + 1;
                    if (bit_cnt == 8) begin
                        bit_cnt = 0;
                        case (cmd_reg)
                            CMD_READ, CMD_QOR, CMD_PP, CMD_SE: phase = PH_ADDR;

                            CMD_WREN: begin
                                wel   = 1'b1;
                                phase = PH_NONE;
                            end
                            CMD_WRDI: begin
                                wel   = 1'b0;
                                phase = PH_NONE;
                            end
                            CMD_RDSR1: begin
                                // {6'b0, WEL, WIP} - WIP her zaman 0 (aninda biter)
                                out_shift = {6'b0, wel, 1'b0};
                                phase     = PH_RD1;
                            end
                            CMD_RDID: begin
                                out_shift = JEDEC_ID[23:16];
                                id_idx    = 1;
                                phase     = PH_RD1;
                            end
                            default: begin
                                $display("[SPI_FLASH] Desteklenmeyen komut: 0x%02h", cmd_reg);
                                out_shift = 8'h00;
                                phase     = PH_RD1;
                            end
                        endcase
                    end
                end

                // ---------------------------------------------------------
                PH_ADDR: begin
                    addr_reg = {addr_reg[30:0], io0};
                    bit_cnt  = bit_cnt + 1;
                    if (bit_cnt == ADDR_BYTES * 8) begin
                        bit_cnt = 0;
                        case (cmd_reg)
                            CMD_READ: begin
                                out_shift = gecerli(addr_reg) ? mem_b[indeks(addr_reg)] : 8'h00;
                                phase     = PH_RD1;
                            end
                            CMD_QOR: begin
                                phase = PH_DUMMY;
                            end
                            CMD_PP: begin
                                if (!wel)
                                    $display("[SPI_FLASH] UYARI: WEL yokken PP - yazma yok sayildi");
                                phase = PH_WR1;
                            end
                            CMD_SE: begin
                                if (!wel) begin
                                    $display("[SPI_FLASH] UYARI: WEL yokken SE - silme yok sayildi");
                                end else begin
                                    // Sektor tabanina hizala ve 0xFF yap
                                    int taban;
                                    taban = (indeks(addr_reg) / SECTOR_BYTES) * SECTOR_BYTES;
                                    for (int i = 0; i < SECTOR_BYTES; i++)
                                        if ((taban + i) < BYTE_COUNT) mem_b[taban + i] = 8'hFF;
                                    se_sayisi = se_sayisi + 1;
                                    $display("[SPI_FLASH] SE: 0x%06h..0x%06h silindi",
                                             taban, taban + SECTOR_BYTES - 1);
                                end
                                phase = PH_NONE;
                            end
                            default: phase = PH_NONE;
                        endcase
                    end
                end

                // ---------------------------------------------------------
                PH_DUMMY: begin
                    bit_cnt = bit_cnt + 1;
                    if (bit_cnt == QOR_DUMMY) begin
                        bit_cnt   = 0;
                        out_shift = gecerli(addr_reg) ? mem_b[indeks(addr_reg)] : 8'h00;
                        phase     = PH_RD4;
                    end
                end

                // ---------------------------------------------------------
                // Tek hatli yazma (PP). Master io0'i surer.
                // ---------------------------------------------------------
                PH_WR1: begin
                    in_shift = {in_shift[6:0], io0};
                    bit_cnt  = bit_cnt + 1;
                    if (bit_cnt == 8) begin
                        bit_cnt = 0;
                        if (wel && gecerli(addr_reg)) begin
                            // Gercek NOR flash yalnizca 1 -> 0 yapabilir
                            mem_b[indeks(addr_reg)] = mem_b[indeks(addr_reg)] & in_shift;
                            pp_bayt         = pp_bayt + 1;
                        end
                        addr_reg = addr_reg + 1;
                    end
                end

                default: ; // PH_RD1 / PH_RD4 / PH_NONE - ornekleme yok
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Dusen kenar: bir sonraki biti/nibble'i hatta sur
    // -------------------------------------------------------------------------
    always @(negedge sck) begin
        if (!cs_n && phase == PH_RD1) begin
            drive_x1   = 1'b1;
            drive_x4   = 1'b0;
            out_nib[1] = out_shift[7];
            out_shift  = {out_shift[6:0], 1'b0};
            bit_cnt    = bit_cnt + 1;
            if (bit_cnt == 8) begin
                bit_cnt = 0;
                case (cmd_reg)
                    CMD_RDSR1: out_shift = {6'b0, wel, 1'b0};   // tekrar tekrar
                    CMD_RDID: begin
                        out_shift = (id_idx == 1) ? JEDEC_ID[15:8]
                                  : (id_idx == 2) ? JEDEC_ID[7:0] : 8'h00;
                        id_idx    = id_idx + 1;
                    end
                    default: begin
                        addr_reg  = addr_reg + 1;
                        out_shift = gecerli(addr_reg) ? mem_b[indeks(addr_reg)] : 8'h00;
                    end
                endcase
            end
        end
        else if (!cs_n && phase == PH_RD4) begin
            drive_x4 = 1'b1;
            drive_x1 = 1'b0;
            out_nib  = out_shift[7:4];
            out_shift = {out_shift[3:0], 4'h0};
            bit_cnt  = bit_cnt + 1;
            if (bit_cnt == 2) begin          // iki nibble = bir bayt
                bit_cnt   = 0;
                addr_reg  = addr_reg + 1;
                out_shift = gecerli(addr_reg) ? mem_b[indeks(addr_reg)] : 8'h00;
            end
        end
    end

endmodule
