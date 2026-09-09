# =============================================================================
#  sta_tarama.tcl - d45_anten2 icin bagimsiz imzalama STA
#
#  AMAC
#
#    d45_anten2 20 ns imzalamada uc SS kosesinde setup ihlali veriyor
#    (WNS -1,8149 ns, 115 ihlalli yol). LAYOUT DEGISMEDEN yalnizca
#    imzalama periyodunu buyuterek bu ihlallerin kapandigi periyodu
#    bulmak istiyoruz.
#
#    Hesap: WNS -1,8149 ns oldugu icin +2 ns (22 ns) yeterli GORUNUYOR
#    ama bu yalnizca EN KOTU yolun kaymasidir; ara yollarin da pozitife
#    gectigini olcmeden bilemeyiz. Bu yuzden tarama yapiyoruz.
#
#  GIRDI - hepsi teslim paketinden, hicbiri yeniden uretilmiyor
#    netlist : results/netlist/soc_top_pnr.v
#    SPEF    : results/spef/{min,nom,max}/
#    lib     : results/lib/<kose>/  + sky130 std cell + SRAM makro
#
#  Bu betik LAYOUT'A DOKUNMAZ; yalnizca zamanlama analizi yapar.
# =============================================================================

set PKG   $::env(PKG)
set PERIOD $::env(PERIOD)
set CORNER $::env(CORNER)
set PDK   $::env(PDK)

# --- Kose adi -> sky130 lib eslemesi -------------------------------------
# Kose adlari "min/nom/max" (RC) + "tt/ss/ff" (proses) bicimindedir.
# Standart hucre kutuphanesi yalnizca proses/sicaklik/gerilim ile secilir.
switch -glob $CORNER {
    *_tt_025C_1v80 { set SC "sky130_fd_sc_hd__tt_025C_1v80.lib" }
    *_ss_100C_1v60 { set SC "sky130_fd_sc_hd__ss_100C_1v60.lib" }
    *_ff_n40C_1v95 { set SC "sky130_fd_sc_hd__ff_n40C_1v95.lib" }
    default        { puts "BILINMEYEN KOSE: $CORNER" ; exit 1 }
}

# SPEF hangi RC kosesinden gelecek
if {[string match "min_*" $CORNER]} { set RC min } \
elseif {[string match "max_*" $CORNER]} { set RC max } \
else { set RC nom }

read_liberty $PDK/sky130A/libs.ref/sky130_fd_sc_hd/lib/$SC
read_liberty $PKG/asic/macros/sky130_sram_2kbyte_1rw1r_32x512_8/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib

# --- Teknoloji ve hucre LEF'leri (read_verilog bunlari ister) ---
read_lef $PDK/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
read_lef $PDK/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
read_lef $PDK/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_ef_sc_hd.lef
read_lef $PKG/asic/macros/sky130_sram_2kbyte_1rw1r_32x512_8/lef/sky130_sram_2kbyte_1rw1r_32x512_8.lef

read_verilog $PKG/asic/results/netlist/soc_top_pnr.v
link_design soc_top

read_spef $PKG/asic/results/spef/$RC/soc_top.$RC.spef

# --- Kisitlar: d45_anten2'nin signoff SDC'siyle AYNI, yalnizca periyot degisik
create_clock -name clk_i -period $PERIOD [get_ports clk_i]
set_clock_uncertainty -setup 0.25 [get_clocks clk_i]
set_clock_uncertainty -hold  0.10 [get_clocks clk_i]
set_clock_transition  0.15 [get_clocks clk_i]
create_clock -name jtag_clk -period 100.0 [get_ports jtag_tck]
set_clock_groups -asynchronous -group [get_clocks clk_i] -group [get_clocks jtag_clk]
set_propagated_clock [all_clocks]

# --- Sonuc -----------------------------------------------------------------
set wns [sta::worst_slack -max]
set tns [sta::total_negative_slack -max]
set hwns [sta::worst_slack -min]

# Ihlalli yol sayisi
set vio 0
foreach p [find_timing_paths -path_delay max -slack_max 0 -group_count 100000] {
    incr vio
}
set hvio 0
foreach p [find_timing_paths -path_delay min -slack_max 0 -group_count 100000] {
    incr hvio
}

puts "SONUC|$CORNER|$PERIOD|$wns|$tns|$vio|$hwns|$hvio"
exit 0
