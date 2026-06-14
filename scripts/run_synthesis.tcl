# ==============================================================================
#  run_synthesis.tcl
#  TEKNOFEST 2026 Çip Tasarım Yarışması - Sentez Scripti
# ==============================================================================

# 1. Çalışma dizinini projenin kök dizinine yönlendir (Dinamik)
set script_dir [file dirname [file normalize [info script]]]
cd [file join $script_dir ".."]

# Açık proje varsa kapat (çakışmaları önlemek için)
catch {close_project}

# 2. Projeyi yeniden oluştur (XPR dosyası silindiği için sıfırdan kuruyoruz)
source [file join $script_dir "create_project.tcl"]

# 2. Sentezi başlat (tek çekirdek — Windows'ta OOM riskini azaltmak için)
puts "Sentez baslatiliyor..."
set_param general.maxThreads 1
launch_runs synth_1 -jobs 1
wait_on_run synth_1

# Durumu kontrol et
set run_status [get_property STATUS [get_runs synth_1]]
set run_progress [get_property PROGRESS [get_runs synth_1]]
puts "Sentez Durumu: $run_status ($run_progress)"

if {[string first "Complete" $run_status] != -1 || $run_progress == "100%"} {
    puts "Sentez basariyla tamamlandi. Raporlar uretiliyor..."
    open_run synth_1
    report_utilization -file [file join $script_dir "utilization_report.rpt"]
    report_utilization -hierarchical -file [file join $script_dir "utilization_hierarchical_report.rpt"]
    puts "Raporlar olusturuldu: [file join $script_dir "utilization_report.rpt"] ve [file join $script_dir "utilization_hierarchical_report.rpt"]"
} else {
    puts "HATA: Sentez tamamlanamadi!"
}
