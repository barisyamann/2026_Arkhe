# ==============================================================================
#  run_synthesis_direct.tcl
#  Sentezi dogrudan ana Vivado sureci icinde calistir (launch_runs atlanir)
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

# Acik proje varsa kapat
catch {close_project}

# Projeyi yeniden olustur
source create_project.tcl

# Thread sinirlamasini ayarla
set_param general.maxThreads 1

puts "========================================"
puts "Dogrudan sentez baslatiliyor (synth_design)..."
puts "========================================"

if {[catch {synth_design -top soc_top -part xc7a35tcsg324-1} result]} {
    puts "========================================"
    puts "SENTEZ BASARISIZ!"
    puts "Sonuc: $result"
    puts "Hata Kodu: $errorCode"
    puts "Hata Bilgisi:\n$errorInfo"
    puts "========================================"
} else {
    puts "========================================"
    puts "SENTEZ BASARIYLA TAMAMLANDI!"
    puts "========================================"
    report_utilization -file [file join $script_dir "utilization_report.rpt"]
    report_utilization -hierarchical -file [file join $script_dir "utilization_hierarchical_report.rpt"]
    write_checkpoint -force [file join $script_dir "soc_top_synth.dcp"]
    puts "Raporlar ve checkpoint olusturuldu."
}
