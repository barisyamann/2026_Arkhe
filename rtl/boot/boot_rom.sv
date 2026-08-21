// =============================================================================
// Proje: Arkhe SoC - Donanımsal Boot ROM (1 kB)
// Tasarımcı: Barış Yaman (Kaptan - Arkhe RTL Ekibi)
// Referans: ÖTR Bölüm 3.5 - İki Aşamalı Boot Mimarisi
// Açıklama: İşlemci ilk komutlarını bu ROM içerisindeki bootloader üzerinden çeker.
// =============================================================================

module boot_rom import boot_rom_pkg::*; (
    input  logic        clk_i,
    input  logic        rst_ni,

    // İşlemci OBI/AXI Arayüzünden Gelen İstekler
    input  logic [31:0] rom_addr_i,
    input  logic        rom_req_i,
    output logic [31:0] rom_rdata_o,
    output logic        rom_rvalid_o
);

    // 1 kB ROM Alanı: 256 satır x 32-bit (4 Byte) = 1024 Byte
    //
    // İÇERİK RTL'E GÖMÜLÜDÜR - dosyadan okunmaz.
    //
    // Önceden `$readmemh("boot.hex", rom_mem)` kullanılıyordu. Dosya adı
    // çıplaktı ve $readmemh dosyayı ÇALIŞMA DİZİNİNE göre arar. Vivado
    // projeye eklenmiş dosyayı çözebiliyordu; LibreLane ise her adımı kendi
    // dizininde koşturur (asic/run/arkhe/06-yosys-synthesis/) ve oradan
    // boot.hex görünmüyordu. ROM tanımsız (X) kalıyor, Yosys de siliyordu:
    //
    //     soc_top.u_boot_rom.rom_mem: removing const-x lane 0..31
    //
    // Hata verilmiyordu - sessizdi. Üretilecek çip açılmazdı.
    //
    // Paket `scripts/gen_rom_paketleri.py` ile üretilir; aynı betik ürettiği
    // değerleri kaynak dosyayla tek tek karşılaştırarak doğrular.
    //
    // Erişim `boot_rom_icerik(indeks)` fonksiyonuyla yapılır. İçerik tek bir
    // packed vektörde durur; UNPACKED dizi denendi ve Vivado xelab tek modülde
    // 82 dakikada bitiremedi (packed biçim aynı işi 2,5 saniyede yapıyor).

    // Okuma Mantığı (Açılışta kararlılık için Yazmaç Destekli)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rom_rdata_o  <= 32'h0000_0000; // Reset anında temizle
            rom_rvalid_o <= 1'b0;
        end else begin
            rom_rvalid_o <= rom_req_i; // İstek geldiği çevrimin (cycle) sonunda veri geçerlidir
            if (rom_req_i) begin
                // Adres byte addressable olduğu için [9:2] bitlerini seçiyoruz (Word alignment)
                rom_rdata_o <= boot_rom_icerik(rom_addr_i[9:2]);
            end
        end
    end

endmodule