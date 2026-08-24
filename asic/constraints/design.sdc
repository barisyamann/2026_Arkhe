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
# Giris / cikis gecikmeleri
#
# Cevre birimi pinleri yavas dis dunyaya baglanir (UART, I2C, QSPI, GPIO,
# JTAG). Periyodun %20'si makul bir baslangic degeridir.
# -----------------------------------------------------------------------------
set io_delay [expr $clk_period * 0.20]

# Saat portlarini giris listesinden cikar.
#
# NOT: remove_from_collection bir Synopsys DC komutudur, OpenSTA'da YOKTUR:
#   "invalid command name remove_from_collection"
# OpenSTA'da all_inputs duz bir Tcl listesi dondurur; Tcl liste
# islemleriyle filtreliyoruz.
set giris_portlari [all_inputs]

foreach saat_portu [list $clk_port jtag_tck] {
    set idx [lsearch $giris_portlari [get_ports $saat_portu]]
    if {$idx >= 0} {
        set giris_portlari [lreplace $giris_portlari $idx $idx]
    }
}

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
# Cikis yuku
# -----------------------------------------------------------------------------
set_load 0.02 [all_outputs]

# =============================================================================
#  TASARIM KURALI KISITLARI  (6. kosum sonrasi eklendi - 24 Agustos 2026)
#
#  NEDEN EKSIKTILER
#
#    LibreLane'in varsayilan SDC sablonu bu uc kisiti config.yaml'daki
#    degerlerden uretir. Biz PNR_SDC_FILE / SIGNOFF_SDC_FILE ile KENDI
#    SDC'mizi verdigimiz icin o sablon devre disi kaldi. Sonuc: kisitlar
#    config'de yaziyordu ama araca HIC ULASMIYORDU.
#
#  BELIRTI
#
#    6. kosumda dokuz kosenin TAMAMINDA max cap ve max slew ihlali:
#        min_ff (en iyi kose)  :  215 cap / 579 slew
#        nom_tt                :  438 cap / 1842 slew
#        max_ss (en kotu)      : 1305 cap / 12364 slew
#
#    Kok neden kanit: reset agaci 49 tampona bolunmus, HER BIRI ~150 YUK
#    suruyor. Buna ragmen STA "max fanout violation count 0" diyordu -
#    cunku ortada kisit yoktu. MAX_FANOUT_CONSTRAINT: 10 config'de duruyor,
#    hicbir etkisi olmamis.
#
#    Ihlallerin dagilimi da bunu dogruluyor:
#        215 RESET_B pini      (yuksek fanout reset agi)
#        279 DIODE pini        (ayni yavas aglara takili anten diyotlari)
#         92 SRAM wmask pini
#
#  DEGERLER config.yaml ILE AYNI TUTULUR
#
#    Env degiskeni varsa ondan okunur, yoksa ayni sabit kullanilir. Boylece
#    config.yaml'daki deger degistiginde burasi da otomatik uyar.
# =============================================================================

proc _kisit_degeri {ad varsayilan} {
    if {[info exists ::env($ad)] && $::env($ad) ne ""} {
        return $::env($ad)
    }
    return $varsayilan
}

set_max_fanout      [_kisit_degeri MAX_FANOUT_CONSTRAINT     10]   [current_design]
set_max_transition  [_kisit_degeri MAX_TRANSITION_CONSTRAINT 0.75] [current_design]
set_max_capacitance [_kisit_degeri MAX_CAPACITANCE_CONSTRAINT 0.2] [current_design]

# -----------------------------------------------------------------------------
#  GIRIS PORTLARI ICIN SURUCU MODELI
#
#  set_driving_cell olmadan giris portlari IDEAL surucu varsayilir: gecis
#  suresi sifir kabul edilir ve ag RC'si uzerinden hesaplanan slew gercekci
#  olmaz. 6. kosumda clk_i giris agi 0,562 pF yuk tasiyordu ve ilk saat
#  tamponunun girisinde 1,61 ns slew olculuyordu - bu deger bir surucu
#  modeliyle hesaplanmis degildi.
#
#  inv_2 orta guclu bir surucu; disaridan gelen tipik bir sinyali temsil
#  eder. Saat portlari da dahil edilir, cunku onlar da disaridan surulur.
# -----------------------------------------------------------------------------
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs]
