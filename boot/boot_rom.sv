// =============================================================================
// Proje: Arkhe SoC - Donanımsal Boot ROM (1 kB)
// Tasarımcı: Barış Yaman (Kaptan - Arkhe RTL Ekibi)
// Referans: ÖTR Bölüm 3.5 - İki Aşamalı Boot Mimarisi
// Açıklama: İşlemci ilk komutlarını bu ROM içerisindeki bootloader üzerinden çeker.
// =============================================================================

module boot_rom (
    input  logic        clk_i,
    input  logic        rst_ni,
    
    // İşlemci OBI/AXI Arayüzünden Gelen İstekler
    input  logic [31:0] rom_addr_i,
    input  logic        rom_req_i,
    output logic [31:0] rom_rdata_o,
    output logic        rom_rvalid_o
);

    // 1 kB ROM Alanı: 256 satır x 32-bit (4 Byte) = 1024 Byte
    logic [31:0] rom_mem [0:255]; 

    // Bellek hücrelerini boot.hex dosyası ile dolduruyoruz
    initial begin
        $readmemh("boot.hex", rom_mem);
    end

    // Okuma Mantığı (Açılışta kararlılık için Yazmaç Destekli)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rom_rdata_o  <= 32'h0000_0000; // Reset anında temizle
            rom_rvalid_o <= 1'b0;
        end else begin
            rom_rvalid_o <= rom_req_i; // İstek geldiği çevrimin (cycle) sonunda veri geçerlidir
            if (rom_req_i) begin
                // Adres byte addressable olduğu için [9:2] bitlerini seçiyoruz (Word alignment)
                rom_rdata_o <= rom_mem[rom_addr_i[9:2]]; 
            end
        end
    end

endmodule