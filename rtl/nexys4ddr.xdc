# ==============================================================================
#  nexys4ddr.xdc
#  TEKNOFEST 2026 - Nexys 4 DDR (XC7A100T-1CSG324C) Pin and Timing Constraints
# ==============================================================================

# --- Saat ve Reset (Clock & Reset) ---
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -period 10.000 -name CLK100MHZ -waveform {0.000 5.000} [get_ports { CLK100MHZ }];

# CPU Reset Butonu (Aktif Düşük - C12)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { CPU_RESETN }];

# --- USB-UART Köprüsü ---
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { UART_TXD_IN }];
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { UART_RXD_OUT }];

# --- I2C Master (Pmod JA) ---
#
# 22 Agustos 2026'da eklendi. Onceden I2C hatlari karta HIC cikmiyordu;
# sartname 5.2 "kurul tarafindan verilecek test senaryolari" istiyor ve
# bir I2C senaryosu kosulamazdi.
#
# PULLUP TRUE, FPGA'nin dahili zayif yukari cekme direncini (~50 kOhm)
# etkinlestirir. Acik drenaj hattinin bosta '1' okunmasi icin gereklidir.
# Fonksiyonel test icin yeterlidir; 400 kHz Fast Mode'da guvenilir yukselme
# kenari icin HARICI 2,2-4,7 kOhm direnc onerilir.
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports { I2C_SCL }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports { I2C_SDA }];

# --- UART-stream (UART 2) - Pmod JB ---
#
# 8 Eylul 2026'da eklendi. TEKNOFEST demo araci IKI AYRI seri port istiyor:
# cikarim vektoru (1960 bayt) UART-stream'den girer, sonuc core UART'tan
# cikar. Kart uzerinde tek USB-UART koprusu var (UART 1 -> C4/D4), bu yuzden
# UART 2 harici bir 3,3 V UART-TTL modulu ile Pmod JB uzerinden veriliyor.
#
# Kablolama (Pmod JB ust sira):
#   JB1 (D14) <- modulun TX'i   (FPGA girisi)
#   JB2 (F16) -> modulun RX'i   (FPGA cikisi)
#   JB5/JB6   <- GND
# DIKKAT: modul 3,3 V kipinde olmalidir; 5 V seviye FPGA bankasini bozar.
#
# PULLUP, hat bosta iken '1' (UART idle) okunmasi icindir; modul takili
# degilken alici sahte start biti gormez.
set_property -dict { PACKAGE_PIN D14   IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports { JB_UART_RX }];
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 } [get_ports { JB_UART_TX }];

# --- JTAG Hata Ayıklama Arayüzü - Pmod JC ---
#
# 9 Eylül 2026'da eklendi. jtag_debug modülü tasarımda vardı ve
# simülasyonda 27 denetimle doğrulanmıştı, ancak nexys_top.sv içinde
# jtag_tck sabit 1'b0'a bağlıydı; TAP durum makinesi hiç saat almıyordu.
# Demo günü jüri JTAG görmek isterse diye fiziksel pinlere çıkarıldı.
#
# Kablolama (Pmod JC üst sıra):
#   JC1 (K1) <- TCK   (harici JTAG adaptöründen)
#   JC2 (F6) <- TMS
#   JC3 (J2) <- TDI
#   JC4 (G6) -> TDO   (FPGA çıkışı)
#   JC5/JC6  <- GND
#
# PULLUP: adaptör takılı değilken TMS/TDI boşta '1' okunur ve TAP
# rastgele duruma geçmez. TCK'da pull-down tercih edilir; sahte saat
# kenarı üretmemesi için.
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33  PULLDOWN TRUE } [get_ports { JTAG_TCK }];
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33  PULLUP   TRUE } [get_ports { JTAG_TMS }];
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33  PULLUP   TRUE } [get_ports { JTAG_TDI }];
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports { JTAG_TDO }];

# JTAG saati ana saatle ASENKRONDUR. Kısıt verilmezse Vivado bu yolları
# ana saatle ilişkilendirmeye çalışır ve sahte ihlaller üretir.
# soc_top içindeki mantık iki saat alanı arasında senkronizatör kullanır.
create_clock -period 100.000 -name jtag_tck_clk [get_ports JTAG_TCK]

# JTAG_TCK, Pmod JC1 (K1) uzerindedir ve bu pin CLOCK-CAPABLE (CCIO)
# DEGILDIR. jtag_debug.sv icinde jtag_tck kenar tetiklemeli kullanildigi
# icin Vivado ona global saat tamponu (BUFG) atamaya calisir ve
# yerlestirme "Poor placement for routing between an IO pin and BUFG"
# hatasiyla duser (9 Eylul 2026'da tam olarak bu yasandi).
#
# CLOCK_DEDICATED_ROUTE FALSE bu denetimi uyariya cevirir. Burada
# guvenlidir cunku:
#   - JTAG saati 100 ns periyotludur (10 MHz alti), hata ayiklama icindir
#   - ana saat (clk_50mhz) ayri bir yoldan gelir ve etkilenmez
#   - iki saat alani arasinda jtag_debug.sv senkronizator kullanir
#   - saat gruplari asenkron tanimlanmistir (asagida)
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets JTAG_TCK_IBUF]
# Saat gruplama kisiti asagida, clk_50mhz tanimindan SONRA verilir.
# XDC sirali islenir; burada verilseydi clk_50mhz henuz tanimli olmazdi.

# --- GPIO Yön Kontrolü (Pad tx_en) - Pmod JD ---
#
# 9 Eylül 2026'da eklendi. gpio_tx_en_o önceden boşta bırakılmıştı.
# GPIO'nun dört pin modu (00 giriş, 01 çıkış, 10 açık drenaj-0,
# 11 açık drenaj-1) blok testinde %95,6 kapsamayla doğrulandı ama
# FPGA'da dışarıdan gözlenemiyordu. Alt 8 bit Pmod JD'ye verildi;
# osiloskop veya LED ile pin yönü doğrudan görülebilir.
set_property -dict { PACKAGE_PIN H4  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[0] }];
set_property -dict { PACKAGE_PIN H1  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[1] }];
set_property -dict { PACKAGE_PIN G1  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[2] }];
set_property -dict { PACKAGE_PIN G3  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[3] }];
set_property -dict { PACKAGE_PIN H2  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[4] }];
set_property -dict { PACKAGE_PIN G4  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[5] }];
set_property -dict { PACKAGE_PIN G2  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[6] }];
set_property -dict { PACKAGE_PIN F3  IOSTANDARD LVCMOS33 } [get_ports { GPIO_TXEN[7] }];

# --- 16 Anahtar (Switches - Girişler) ---
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { SW[0] }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { SW[1] }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { SW[2] }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { SW[3] }];
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { SW[4] }];
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { SW[5] }];
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { SW[6] }];
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { SW[7] }];
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS33 } [get_ports { SW[8] }];
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS33 } [get_ports { SW[9] }];
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { SW[10] }];
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { SW[11] }];
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { SW[12] }];
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { SW[13] }];
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { SW[14] }];
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { SW[15] }];

# --- 16 LED (Çıkışlar) ---
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { LED[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { LED[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { LED[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { LED[4] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { LED[5] }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { LED[6] }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { LED[7] }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { LED[8] }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { LED[9] }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { LED[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { LED[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { LED[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { LED[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { LED[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { LED[15] }];

# --- Zamanlama Bölücü Kısıt Tanımı ---
# 50 MHz iç saati elde etmek için üretilen saati Vivado zamanlama motoruna bildiriyoruz
create_generated_clock -name clk_50mhz -source [get_ports CLK100MHZ] -divide_by 2 [get_pins bufg_clk/O]

# JTAG saati ana saatle ASENKRONDUR (9 Eylul 2026'da eklendi).
# Kisit verilmezse Vivado iki alan arasindaki yollari zamanlamaya calisir
# ve sahte ihlaller uretir. soc_top icindeki jtag_debug modulu iki saat
# alani arasinda senkronizator kullanir; bu kisit o gerceegi bildirir.
# Ayni kisit ASIC tarafinda da vardir (constraints/design.sdc).
set_clock_groups -asynchronous -group [get_clocks clk_50mhz] -group [get_clocks jtag_tck_clk]

# =============================================================================
#  QSPI NOR Flash - KART USTU Spansion S25FL128S (16 MB)
#  F2 karari, 23 Agustos 2026
#
#  SAAT PINI YOKTUR: 7-serisi Artix'te flash saati (CCLK) yapilandirma
#  devresine aittir ve pakete atanamaz. Kullanici mantigi onu ancak
#  STARTUPE2 ilkel blogunun USRCCLKO girisinden surebilir; bkz.
#  rtl/Memory/nexys_top.sv icindeki u_startupe2.
#
#  Bu pinler yapilandirma sonrasi kullanici mantigina birakilir. CS ve DQ
#  hatlari yapilandirma sirasinda da kullanildigi icin Vivado uyari
#  uretebilir; asagidaki iki ayar bunu bilinen/kabul edilmis hale getirir.
# =============================================================================
set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports { QSPI_CS_N }]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { QSPI_DQ[0] }]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { QSPI_DQ[1] }]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports { QSPI_DQ[2] }]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { QSPI_DQ[3] }]

# Yapilandirma arayuzunu kullanici mantigina birak
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
