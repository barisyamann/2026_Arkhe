set ::env(STEP_ID) OpenROAD.STAPostPNR
set ::env(TECH_LEF) /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
set ::env(MACRO_LEFS) macros/sky130_sram_2kbyte_1rw1r_32x512_8/lef/sky130_sram_2kbyte_1rw1r_32x512_8.lef
set ::env(STD_CELL_LIBRARY) sky130_fd_sc_hd
set ::env(VDD_PIN) VPWR
set ::env(GND_PIN) VGND
set ::env(TECH_LEFS) "\"nom_*\" /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef \"min_*\" /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__min.tlef \"max_*\" /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__max.tlef"
set ::env(PRIMARY_GDSII_STREAMOUT_TOOL) magic
set ::env(DEFAULT_CORNER) nom_tt_025C_1v80
set ::env(STA_CORNERS) "nom_tt_025C_1v80 nom_ss_100C_1v60 nom_ff_n40C_1v95 min_tt_025C_1v80 min_ss_100C_1v60 min_ff_n40C_1v95 max_tt_025C_1v80 max_ss_100C_1v60 max_ff_n40C_1v95"
set ::env(RT_MIN_LAYER) met1
set ::env(RT_MAX_LAYER) met5
set ::env(SCL_GROUND_PINS) "VGND VNB"
set ::env(SCL_POWER_PINS) "VPWR VPB"
set ::env(TRISTATE_CELLS) "\"sky130_fd_sc_hd__ebuf*\""
set ::env(FILL_CELLS) "sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1"
set ::env(DECAP_CELLS) sky130_fd_sc_hd__decap_3
set ::env(LIB) "\"*_tt_025C_1v80\" /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \"*_ss_100C_1v60\" /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_100C_1v60.lib \"*_ff_n40C_1v95\" /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ff_n40C_1v95.lib"
set ::env(CELL_LEFS) "/home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_ef_sc_hd.lef"
set ::env(CELL_GDS) /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds
set ::env(CELL_VERILOG_MODELS) "/home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v"
set ::env(CELL_BB_VERILOG_MODELS) "/home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd__blackbox.v /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd__blackbox_pp.v"
set ::env(CELL_SPICE_MODELS) "/home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_12.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_20_12.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_40_12.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_60_12.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_80_12.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_12.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_2.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_4.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_8.spice /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice"
set ::env(CELL_CDLS) /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/cdl/sky130_fd_sc_hd.cdl
set ::env(SYNTH_EXCLUDED_CELL_FILE) /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.tech/openlane/sky130_fd_sc_hd/no_synth.cells
set ::env(PNR_EXCLUDED_CELL_FILE) /home/baris/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.tech/openlane/sky130_fd_sc_hd/drc_exclude.cells
set ::env(OUTPUT_CAP_LOAD) 33.442
set ::env(MAX_FANOUT_CONSTRAINT) 10
set ::env(MAX_TRANSITION_CONSTRAINT) 0.75
set ::env(MAX_CAPACITANCE_CONSTRAINT) 0.2
set ::env(CLOCK_UNCERTAINTY_CONSTRAINT) 0.25
set ::env(CLOCK_TRANSITION_CONSTRAINT) 0.1499999999999999944488848768742172978818416595458984375
set ::env(TIME_DERATING_CONSTRAINT) 5
set ::env(IO_DELAY_CONSTRAINT) 20
set ::env(SYNTH_DRIVING_CELL) sky130_fd_sc_hd__inv_2/Y
set ::env(SYNTH_TIEHI_CELL) sky130_fd_sc_hd__conb_1/HI
set ::env(SYNTH_TIELO_CELL) sky130_fd_sc_hd__conb_1/LO
set ::env(SYNTH_BUFFER_CELL) sky130_fd_sc_hd__buf_2/A/X
set ::env(PLACE_SITE) unithd
set ::env(CELL_PAD_EXCLUDE) "\"sky130_fd_sc_hd__tap*\" \"sky130_fd_sc_hd__decap*\" \"sky130_ef_sc_hd__decap*\" \"sky130_fd_sc_hd__fill*\""
set ::env(DIODE_CELL) sky130_fd_sc_hd__diode_2/DIODE
set ::env(WELLTAP_CELL) sky130_fd_sc_hd__tapvpwrvgnd_1
set ::env(ENDCAP_CELL) sky130_fd_sc_hd__decap_3
set ::env(DESIGN_NAME) soc_top
set ::env(CLOCK_PERIOD) 20.0
set ::env(CLOCK_PORT) clk_i
set ::env(CLOCK_NET) clk_i
set ::env(DIE_AREA) "0 0 3832.40 4249.24"
set ::env(MACROS) "sky130_sram_2kbyte_1rw1r_32x512_8 \"gds macros/sky130_sram_2kbyte_1rw1r_32x512_8/gds/sky130_sram_2kbyte_1rw1r_32x512_8.gds lef macros/sky130_sram_2kbyte_1rw1r_32x512_8/lef/sky130_sram_2kbyte_1rw1r_32x512_8.lef instances \\\"\\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[0].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"250.00 250.00\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[1].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"1133.10 250.00\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[2].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2016.20 250.00\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[3].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2899.30 250.00\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[4].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"250.00 866.54\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[5].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"1133.10 866.54\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[6].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2016.20 866.54\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[7].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2899.30 866.54\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[8].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"250.00 1483.08\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[9].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"1133.10 1483.08\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[10].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2016.20 1483.08\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[11].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2899.30 1483.08\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[12].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"250.00 2099.62\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[13].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"1133.10 2099.62\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_npu.u_npu_sram.g_sram\\\\\\\\\\\\\\\[14].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2016.20 2099.62\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_instruction_ram.g_sram\\\\\\\\\\\\\\\[0].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2899.30 2099.62\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_instruction_ram.g_sram\\\\\\\\\\\\\\\[1].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"250.00 2716.16\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_instruction_ram.g_sram\\\\\\\\\\\\\\\[2].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"1133.10 2716.16\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_instruction_ram.g_sram\\\\\\\\\\\\\\\[3].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2016.20 2716.16\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_data_ram.g_sram\\\\\\\\\\\\\\\[0].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2899.30 2716.16\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_data_ram.g_sram\\\\\\\\\\\\\\\[1].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"250.00 3332.70\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_data_ram.g_sram\\\\\\\\\\\\\\\[2].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"1133.10 3332.70\\\\\\\\\\\\\\\" orientation N\\\\\\\" \\\\\\\"u_data_ram.g_sram\\\\\\\\\\\\\\\[3].u_macro\\\\\\\" \\\\\\\"location \\\\\\\\\\\\\\\"2016.20 3332.70\\\\\\\\\\\\\\\" orientation N\\\\\\\"\\\" vh \\\"\\\" nl \\\"\\\" pnl \\\"\\\" spef \\\"\\\" lib \\\"\\\\\\\"*\\\\\\\" macros/sky130_sram_2kbyte_1rw1r_32x512_8/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib\\\" spice macros/sky130_sram_2kbyte_1rw1r_32x512_8/spice/sky130_sram_2kbyte_1rw1r_32x512_8.spice sdf \\\"\\\" json_h None\""
set ::env(EXTRA_VERILOG_MODELS) macros/sky130_sram_2kbyte_1rw1r_32x512_8/verilog/sky130_sram_2kbyte_1rw1r_32x512_8.v
set ::env(FALLBACK_SDC) /nix/store/af8ijg47w5gfv25fb0dyfcw2aca9sqk6-python3.13-librelane-3.0.6/lib/python3.13/site-packages/librelane/scripts/base.sdc
set ::env(PAD_EDGE_SPACING) 0
set ::env(SET_RC_VERBOSE) 0
set ::env(PDN_CONNECT_MACROS_TO_GRID) 1
set ::env(PDN_MACRO_CONNECTIONS) "\".*u_macro VPWR VGND vccd1 vssd1\""
set ::env(PDN_ENABLE_GLOBAL_CONNECTIONS) 1
set ::env(PNR_SDC_FILE) constraints/design.sdc
set ::env(DEDUPLICATE_CORNERS) 0
set ::env(STA_MACRO_PRIORITIZE_NL) 1
set ::env(SIGNOFF_SDC_FILE) constraints/design.sdc
set ::env(CURRENT_NL) /home/baris/arkhe/asic/run/deney_stub/52-openroad-fillinsertion/soc_top.nl.v
set ::env(CURRENT_SPEF) "\"nom_*\" /home/baris/arkhe/asic/run/deney_stub/54-openroad-rcx/nom/soc_top.nom.spef \"min_*\" /home/baris/arkhe/asic/run/deney_stub/54-openroad-rcx/min/soc_top.min.spef \"max_*\" /home/baris/arkhe/asic/run/deney_stub/54-openroad-rcx/max/soc_top.max.spef"
set ::env(CURRENT_ODB) /home/baris/arkhe/asic/run/deney_stub/53-odb-cellfrequencytables/soc_top.odb
set ::env(SAVE_SDC) /home/baris/arkhe/asic/run/deney_stub/55-openroad-stapostpnr/soc_top.sdc
set ::env(OPENLANE_SDC_IDEAL_CLOCKS) 0
