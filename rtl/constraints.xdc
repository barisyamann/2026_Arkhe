# ==============================================================================
#  constraints.xdc
#  TEKNOFEST 2026 Çip Tasarım Yarışması - Zamanlama Sınırlandırmaları
#  Tasarım Ekibi: Arkhe
# ==============================================================================

# 1. Ana Sistem Saati (Clock) - 50 MHz (Periyot: 20 ns)
# (Eğer tasarımdaki hedefiniz farklıysa period değerini değiştirebilirsiniz)
create_clock -period 20.000 -name clk_i -waveform {0.000 10.000} [get_ports clk_i]

# 2. JTAG TCK Saati - 10 MHz (Periyot: 100 ns)
# JTAG debug arayüzünün saati sistem saatinden bağımsız çalışır
create_clock -period 100.000 -name jtag_tck -waveform {0.000 50.000} [get_ports jtag_tck]

# 3. Asenkron Saat Grupları (Clock Domain Crossing - CDC)
# Sistem saati ile JTAG saati asenkrondur, bu iki alan arasındaki yolları zamanlama analizinden muaf tutuyoruz.
set_clock_groups -asynchronous -group [get_clocks clk_i] -group [get_clocks jtag_tck]
