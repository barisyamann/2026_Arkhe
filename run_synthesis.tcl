# ==============================================================================
#  run_synthesis.tcl
#  TEKNOFEST 2026 Çip Tasarım Yarışması - Sentez Scripti
# ==============================================================================

# 1. Projeyi yeniden oluştur
source create_project.tcl

# 2. Sentezi başlat (jobs sayısını 4 olarak ayarlayalım)
puts "Sentez baslatiliyor..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Durumu kontrol et
set run_status [get_property STATUS [get_runs synth_1]]
set run_progress [get_property PROGRESS [get_runs synth_1]]
puts "Sentez Durumu: $run_status ($run_progress)"

if {[string first "Complete" $run_status] != -1 || $run_progress == "100%"} {
    puts "Sentez basariyla tamamlandi. Raporlar uretiliyor..."
    open_run synth_1
    report_utilization -file utilization_report.rpt
    report_utilization -hierarchical -file utilization_hierarchical_report.rpt
    puts "Raporlar olusturuldu: utilization_report.rpt ve utilization_hierarchical_report.rpt"
} else {
    puts "HATA: Sentez tamamlanamadi!"
    exit 1
}
