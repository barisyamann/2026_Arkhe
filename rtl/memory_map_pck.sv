`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.04.2026 15:55:48
// Design Name: 
// Module Name: memory_map_pck
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


package memory_map_pck;

    // Sistem genelinde kullanılacak adres genişliği
    localparam int ADDR_WIDTH = 32;

    // ==============================================================
    // ANA BELLEK BİRİMLERİ (Main Memory Blocks)
    // ==============================================================

    // Boot ROM (Boyut: 1 kB | Bitiş: 0x0000_03FF)
    localparam logic [ADDR_WIDTH-1:0] BOOT_ROM_BASE   = 32'h0000_0000;

    // Buyruk Belleği / Text (Boyut: 8 kB | Bitiş: 0x0100_1FFF)
    localparam logic [ADDR_WIDTH-1:0] INSTR_RAM_BASE  = 32'h0100_0000;

    // Veri Belleği / Data (Boyut: 8 kB | Bitiş: 0x2000_1FFF)
    localparam logic [ADDR_WIDTH-1:0] DATA_RAM_BASE   = 32'h2000_0000;

    // YZ Hızlandırıcı Belleği (Boyut: 30 kB | Bitiş: 0x2001_77FF)
    localparam logic [ADDR_WIDTH-1:0] YZ_MEM_BASE     = 32'h2001_0000;


    // ==============================================================
    // ÇEVRE BİRİMLERİ (Peripherals)
    // ==============================================================

    // GPIO (32 pinli giriş/çıkış kontrol yazmaçları)
    localparam logic [ADDR_WIDTH-1:0] GPIO_BASE       = 32'h4000_0000;

    // Timer (Zamanlayıcı yazmaçları)
    localparam logic [ADDR_WIDTH-1:0] TIMER_BASE      = 32'h4001_0000;

    // UART 1 (Genel amaçlı haberleşme ve debug çıktıları)
    localparam logic [ADDR_WIDTH-1:0] UART1_BASE      = 32'h4002_0000;

    // UART 2 (Sadece YZ hızlandırıcıya ses verisi akıtmak için)
    localparam logic [ADDR_WIDTH-1:0] UART2_BASE      = 32'h4003_0000;

    // I2C Master (Haberleşme yazmaçları)
    localparam logic [ADDR_WIDTH-1:0] I2C_BASE        = 32'h4004_0000;

    // QSPI Master (Dışarıdaki Flash bellek ile haberleşme)
    localparam logic [ADDR_WIDTH-1:0] QSPI_BASE       = 32'h4005_0000;

    // YZ Kontrol CSR (YZ hızlandırıcının durum/kontrol yazmaçları)
    localparam logic [ADDR_WIDTH-1:0] YZ_CTRL_BASE    = 32'h4006_0000;

endpackage
