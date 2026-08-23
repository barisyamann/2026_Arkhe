# =============================================================================
#  fpga_bitstream_olc.tcl - Vivado sentez -> implementasyon -> bitstream
#                           ve her asamanin SURESINI olcer
#
#  TEKNOFEST 2026 - Takim Arkhe
#
#  NEDEN (23 Agustos 2026)
#
#    Elimizdeki Vivado zamanlama raporu 20 Agustos'a ait ve o tarihten
#    sonra tasarim degisti:
#      - FC agirliklari kombinasyonel ROM'dan TCM/SRAM'e tasindi
#      - npu_csr'a weights_ready korumasi eklendi
#      - QSPI kart ustu flash'a baglandi (F2) + STARTUPE2
#      - Boot ROM imaji yeniden uretildi (agirlik yukleme kodu)
#
#    Yani o rapordaki "WNS +1,886 ns, butun kisitlar karsilaniyor" sonucu
#    ARTIK GECERLI DEGILDIR. Bu betik guncel RTL ile bastan olcer.
#
#    Ayrica ASIC tarafinda NPU TCM SRAM okuma yolu kritik yol cikti
#    (tipik kosede WNS -4,00 ns). FPGA'de ayni yol BRAM'e gidiyor;
#    orada da marj yiyip yemedigini gormek istiyoruz.
#
#  KULLANIM (Vivado TCL Console veya batch)
#
#      vivado -mode batch -source scripts/fpga_bitstream_olc.tcl
#
#  CIKTI
#
#      evidence/fpga/bitstream_olcum.txt
# =============================================================================

set proje  "vivado/vivado_nexys_project/Arkhe_SoC_Nexys.xpr"
set rapor  "evidence/fpga/bitstream_olcum.txt"

# Kac is parcacigi kullanilacak - makineye gore
set is_sayisi 4

# -----------------------------------------------------------------------------
proc sure_yaz {fh etiket saniye} {
    set dk [expr {int($saniye) / 60}]
    set sn [expr {int($saniye) % 60}]
    puts $fh [format "  %-34s %3d dk %02d sn   (%.1f s)" $etiket $dk $sn $saniye]
    puts     [format "  %-34s %3d dk %02d sn" $etiket $dk $sn]
}

# -----------------------------------------------------------------------------
file mkdir [file dirname $rapor]
set fh [open $rapor w]

puts $fh "======================================================================="
puts $fh " FPGA BITSTREAM OLCUMU - Nexys A7-100T (xc7a100tcsg324-1)"
puts $fh " Tarih: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fh "======================================================================="
puts $fh ""

open_project $proje
puts $fh "Proje : $proje"
puts $fh "Ust modul : [get_property top [current_fileset]]"
puts $fh ""

# -----------------------------------------------------------------------------
# EKSIK PAKET DOSYALARINI PROJEYE EKLE
#
# 23 Agustos 2026: sentez "'boot_rom_pkg' is not declared" ile dustu.
# Sebep: rtl/boot/boot_rom_pkg.sv Vivado projesinde HIC KAYITLI DEGILDI.
# Regresyon akisi (run_regression.py) kendi dosya listesini kullandigi
# icin orada sorun cikmiyordu; hata yalnizca Vivado projesinde vardi.
#
# Ayrica paketler, onlari import eden modullerden ONCE derlenmelidir.
# Vivado SystemVerilog'da bunu genelde kendi cozer, ama garanti icin
# dosya tipi ve derleme sirasi acikca ayarlaniyor.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# TEK KAYNAK: asic/filelist.f
#
# Vivado projesinin kaynak listesi ile asic/filelist.f AYRI yerlerde
# tutuluyordu ve surekli birbirinden kopuyordu:
#
#   23 Agu  boot_rom_pkg.sv     projede yoktu  -> sentez dustu
#   23 Agu  npu_engine_axi_master.sv / npu_tcm_axi_slave.sv
#                               projede yoktu  -> sentez dustu
#
# Ikisi de yalnizca Vivado'da gorundu; regresyon kendi listesini
# kullandigi icin sorunu gostermedi.
#
# Artik filelist.f TEK KAYNAK: icindeki her dosya projede yoksa
# otomatik ekleniyor. Yeni bir RTL modulu filelist.f'e girdigi anda
# Vivado da onu gorur.
# -----------------------------------------------------------------------------
set fl [open "asic/filelist.f" r]
set fl_icerik [read $fl]
close $fl

set eklenen 0
foreach satir [split $fl_icerik "
"] {
    set satir [string trim $satir]
    if {$satir eq "" || [string index $satir 0] eq "#"} { continue }

    # filelist.f yollari asic/ dizinine gore bagil: ../rtl/... -> rtl/...
    regsub {^\.\./} $satir "" yol
    if {![file exists $yol]} { continue }

    set ad [file tail $yol]
    if {[llength [get_files -quiet $ad]] == 0} {
        add_files -norecurse -fileset sources_1 [file normalize $yol]
        puts "  projeye eklendi: $yol"
        incr eklenen
    }
    set f [get_files -quiet $ad]
    if {[llength $f] > 0 && [string match "*.sv" $ad]} {
        set_property file_type SystemVerilog $f
    }
}
puts "  filelist.f senkronizasyonu: $eklenen dosya eklendi"

update_compile_order -fileset sources_1

# Kosumlari sifirla - guncel RTL ile bastan olcum yapiliyor
reset_run synth_1
puts $fh "ASAMA SURELERI"
puts $fh ""

# --- SENTEZ ---------------------------------------------------------------
set t0 [clock milliseconds]
launch_runs synth_1 -jobs $is_sayisi
wait_on_run synth_1
set t_synth [expr {([clock milliseconds] - $t0) / 1000.0}]
sure_yaz $fh "Sentez (synth_1)" $t_synth

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts $fh ""
    puts $fh "  HATA: sentez tamamlanmadi."
    close $fh
    error "Sentez basarisiz"
}

# --- IMPLEMENTASYON + BITSTREAM -------------------------------------------
set t0 [clock milliseconds]
launch_runs impl_1 -to_step write_bitstream -jobs $is_sayisi
wait_on_run impl_1
set t_impl [expr {([clock milliseconds] - $t0) / 1000.0}]
sure_yaz $fh "Implementasyon + bitstream" $t_impl
sure_yaz $fh "TOPLAM" [expr {$t_synth + $t_impl}]

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts $fh ""
    puts $fh "  HATA: implementasyon tamamlanmadi."
    close $fh
    error "Implementasyon basarisiz"
}

# --- SONUCLAR --------------------------------------------------------------
open_run impl_1

puts $fh ""
puts $fh "ZAMANLAMA"
puts $fh ""
set wns  [get_property STATS.WNS  [get_runs impl_1]]
set tns  [get_property STATS.TNS  [get_runs impl_1]]
set whs  [get_property STATS.WHS  [get_runs impl_1]]
set ths  [get_property STATS.THS  [get_runs impl_1]]
set wpws [get_property STATS.WPWS [get_runs impl_1]]

puts $fh [format "  %-34s %8s ns" "WNS (setup en kotu)" $wns]
puts $fh [format "  %-34s %8s ns" "TNS (setup toplam)"  $tns]
puts $fh [format "  %-34s %8s ns" "WHS (hold en kotu)"  $whs]
puts $fh [format "  %-34s %8s ns" "THS (hold toplam)"   $ths]
puts $fh [format "  %-34s %8s ns" "WPWS (darbe genisligi)" $wpws]
puts $fh ""

# DIKKAT: get_property STATS.WPWS bazen BOS doner (23 Agustos 2026'da
# oldu). Bos degeri sayisal karsilastirmaya sokmak "ihlal var" gibi
# yaniltici bir sonuc uretiyordu - oysa WNS ve WHS pozitifti ve Vivado
# raporu "All user specified timing constraints are met" diyordu.
# Bu yuzden yalnizca DOLU olan alanlar denetleniyor.
set ihlal 0
foreach {ad deg} [list WNS $wns WHS $whs WPWS $wpws] {
    if {$deg eq "" } { continue }
    if {$deg < 0} { set ihlal 1 }
}
if {$ihlal == 0} {
    puts $fh "  SONUC: butun zamanlama kisitlari KARSILANIYOR."
} else {
    puts $fh "  SONUC: ZAMANLAMA IHLALI VAR."
}

# --- Kritik yol - ASIC'te NPU SRAM cikmisti, FPGA'de ne cikiyor? -----------
puts $fh ""
puts $fh "EN KOTU SETUP YOLU (ASIC'te NPU TCM SRAM cikmisti)"
puts $fh ""
set yol [get_timing_paths -max_paths 1 -nworst 1 -setup]
if {[llength $yol] > 0} {
    puts $fh [format "  %-16s %s" "baslangic" [get_property STARTPOINT_PIN $yol]]
    puts $fh [format "  %-16s %s" "bitis"      [get_property ENDPOINT_PIN  $yol]]
    puts $fh [format "  %-16s %s ns" "slack"   [get_property SLACK         $yol]]
    puts $fh [format "  %-16s %s"    "grup"    [get_property GROUP         $yol]]
}

# --- Kaynak kullanimi ------------------------------------------------------
puts $fh ""
puts $fh "KAYNAK KULLANIMI"
puts $fh ""
# Kaynak sayilarini report_utilization ciktisindan almak, get_cells
# filtrelerinden daha guvenilir. Ilk yazimda PRIMITIVE_GROUP degerleri
# yanlisti (REGISTER / BLOCKRAM / DSP diye bir grup yok) ve FF, BRAM,
# DSP hep 0 gorunuyordu.
report_utilization -file evidence/fpga/utilization_bitstream.rpt

set uf [open evidence/fpga/utilization_bitstream.rpt r]
set metin [read $uf]
close $uf
foreach {etiket desen} {
    "Slice LUTs"        {\| Slice LUTs\s+\|\s+(\d+)\s+\|[^|]*\|[^|]*\|\s+(\d+)\s+\|\s+([0-9.]+)}
    "Slice Registers"   {\| Slice Registers\s+\|\s+(\d+)\s+\|[^|]*\|[^|]*\|\s+(\d+)\s+\|\s+([0-9.]+)}
    "Block RAM Tile"    {\| Block RAM Tile\s+\|\s+(\d+)\s+\|[^|]*\|[^|]*\|\s+(\d+)\s+\|\s+([0-9.]+)}
    "DSPs"              {\| DSPs\s+\|\s+(\d+)\s+\|[^|]*\|[^|]*\|\s+(\d+)\s+\|\s+([0-9.]+)}
    "Bonded IOB"        {\| Bonded IOB\s+\|\s+(\d+)\s+\|[^|]*\|[^|]*\|\s+(\d+)\s+\|\s+([0-9.]+)}
} {
    if {[regexp $desen $metin -> kullanilan toplam yuzde]} {
        puts $fh [format "  %-20s %8s / %-8s  %%%s" $etiket $kullanilan $toplam $yuzde]
    }
}

report_timing_summary -file evidence/fpga/timing_bitstream.rpt

# --- Bitstream -------------------------------------------------------------
puts $fh ""
puts $fh "BITSTREAM"
puts $fh ""
set bit [glob -nocomplain vivado/vivado_nexys_project/Arkhe_SoC_Nexys.runs/impl_1/*.bit]
if {[llength $bit] > 0} {
    set b [lindex $bit 0]
    puts $fh [format "  %-34s %s" "dosya" [file tail $b]]
    puts $fh [format "  %-34s %.2f MB" "boyut" [expr {[file size $b] / 1048576.0}]]
    puts $fh "  DURUM: URETILDI"
} else {
    puts $fh "  DURUM: BITSTREAM URETILMEDI"
}

puts $fh ""
puts $fh "Ek raporlar:"
puts $fh "  evidence/fpga/utilization_bitstream.rpt"
puts $fh "  evidence/fpga/timing_bitstream.rpt"

close $fh
puts ""
puts "Rapor yazildi: $rapor"
