# =============================================================================
#  design.sdc - Arkhe SoC ASIC zamanlama kisitlari
#  TEKNOFEST 2026 - Takim Arkhe
#
#  Hedef: SKY130A, LibreLane Classic akisi
#  Ust modul: soc_top
#
#  NOT: FPGA tarafinda 50 MHz'de kapatildi (WNS +1,811 ns, Vivado 2025.2,
#  xc7a100t). ASIC'te ayni periyot hedefleniyor; sky130 standart hucre
#  gecikmeleri farkli oldugu icin ilk kosumdan sonra gozden gecirilecek.
# =============================================================================

# -----------------------------------------------------------------------------
# Ana saat
# -----------------------------------------------------------------------------
set clk_name   clk_i
set clk_port   clk_i
set clk_period 20.0

create_clock -name $clk_name -period $clk_period [get_ports $clk_port]

# Saat belirsizligi ve gecis suresi
# LibreLane bunlari yapilandirmadan da alabilir; burada acikca veriliyor ki
# SDC tek basina okundugunda da tam olsun.
set_clock_uncertainty 0.25 [get_clocks $clk_name]
set_clock_transition  0.15 [get_clocks $clk_name]

# -----------------------------------------------------------------------------
# Giris / cikis gecikmeleri
#
# Cevre birimi pinleri yavas dis dunyaya baglanir (UART, I2C, QSPI, GPIO,
# JTAG). Periyodun %20'si makul bir baslangic degeridir.
# -----------------------------------------------------------------------------
set io_delay [expr $clk_period * 0.20]

set giris_portlari [remove_from_collection [all_inputs] [get_ports $clk_port]]

set_input_delay  $io_delay -clock $clk_name $giris_portlari
set_output_delay $io_delay -clock $clk_name [all_outputs]

# -----------------------------------------------------------------------------
# Asenkron reset
#
# rst_ni disaridan gelir ve saatle iliskisizdir; zamanlama analizinden
# cikariliyor. Tasarim icinde senkronizasyon nexys_top / pad seviyesinde
# yapilir.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports rst_ni]

# -----------------------------------------------------------------------------
# JTAG - ayri saat alani
#
# jtag_tck bagimsiz ve cok daha yavas bir saattir. jtag_debug icindeki
# TCK alani ile sistem saati alani arasindaki gecisler senkronizasyon
# yazmaclari uzerinden yapilir (jtag_cmd_valid_sync1/sync2).
# Iki alan arasinda zamanlama analizi yapilmamalidir.
# -----------------------------------------------------------------------------
create_clock -name jtag_clk -period 100.0 [get_ports jtag_tck]

set_clock_groups -asynchronous \
    -group [get_clocks $clk_name] \
    -group [get_clocks jtag_clk]

set_false_path -from [get_ports jtag_trst_n]

# -----------------------------------------------------------------------------
# Cikis yuku
# -----------------------------------------------------------------------------
set_load 0.02 [all_outputs]
