# ==============================================================================
#  create_nexys_project.tcl
#  TEKNOFEST 2026 - Nexys 4 DDR (XC7A100T) Proje Oluşturma Scripti
#  Tasarım Ekibi: Arkhe
# ==============================================================================

# Karakter kodlaması ve boşluk uyumsuzluğunu önlemek için dizini kontrol ediyoruz
if {[file exists "./Cevre_Birimleri"]} {
    set periph_dir "./Cevre_Birimleri"
} elseif {[file exists "./Çevre Birimleri"]} {
    set periph_dir "./Çevre Birimleri"
} else {
    set periph_dir "./Cevre_Birimleri"
}
puts "Bulunan Cevre Birimleri Dizini: $periph_dir"

set project_name "Arkhe_SoC_Nexys"
set project_dir "./vivado_nexys_project"

# 1. Projeyi Oluştur (Nexys 4 DDR FPGA: XC7A100T-1CSG324C)
create_project $project_name $project_dir -part xc7a100tcsg324-1 -force

# Board part property'yi temizle
set_property BOARD_PART "" [current_project]

# Hedef dili Verilog olarak ayarla
set_property target_language Verilog [current_project]

# 2. Include Arama Yolları Tanımlama (Package ve Header dosyaları için)
set include_dirs [list \
    [file normalize "./cv32e40p-master/rtl/include"] \
    [file normalize "./Memory"] \
    [file normalize "$periph_dir/files_1"] \
]
set_property include_dirs $include_dirs [current_fileset]
set_property include_dirs $include_dirs [get_filesets sim_1]

# 3. Paket Dosyalarını Önce Ekle
add_files -norecurse [list \
    "./Memory/memory_map_pck.sv" \
    "./cv32e40p-master/rtl/include/cv32e40p_apu_core_pkg.sv" \
    "./cv32e40p-master/rtl/include/cv32e40p_fpu_pkg.sv" \
    "./cv32e40p-master/rtl/include/cv32e40p_pkg.sv" \
    "$periph_dir/files_1/uart_pkg.sv" \
]
update_compile_order -fileset sources_1

# 4. RISC-V İşlemci Çekirdeği (CV32E40P) Dosyalarını Ekle
add_files -norecurse [list \
    "./cv32e40p-master/rtl/cv32e40p_aligner.sv" \
    "./cv32e40p-master/rtl/cv32e40p_alu.sv" \
    "./cv32e40p-master/rtl/cv32e40p_alu_div.sv" \
    "./cv32e40p-master/rtl/cv32e40p_apu_disp.sv" \
    "./cv32e40p-master/rtl/cv32e40p_compressed_decoder.sv" \
    "./cv32e40p-master/rtl/cv32e40p_controller.sv" \
    "./cv32e40p-master/rtl/cv32e40p_core.sv" \
    "./cv32e40p-master/rtl/cv32e40p_cs_registers.sv" \
    "./cv32e40p-master/rtl/cv32e40p_decoder.sv" \
    "./cv32e40p-master/rtl/cv32e40p_ex_stage.sv" \
    "./cv32e40p-master/rtl/cv32e40p_ff_one.sv" \
    "./cv32e40p-master/rtl/cv32e40p_fifo.sv" \
    "./cv32e40p-master/rtl/cv32e40p_hwloop_regs.sv" \
    "./cv32e40p-master/rtl/cv32e40p_id_stage.sv" \
    "./cv32e40p-master/rtl/cv32e40p_if_stage.sv" \
    "./cv32e40p-master/rtl/cv32e40p_int_controller.sv" \
    "./cv32e40p-master/rtl/cv32e40p_load_store_unit.sv" \
    "./cv32e40p-master/rtl/cv32e40p_mult.sv" \
    "./cv32e40p-master/rtl/cv32e40p_obi_interface.sv" \
    "./cv32e40p-master/rtl/cv32e40p_popcnt.sv" \
    "./cv32e40p-master/rtl/cv32e40p_prefetch_buffer.sv" \
    "./cv32e40p-master/rtl/cv32e40p_prefetch_controller.sv" \
    "./cv32e40p-master/rtl/cv32e40p_register_file_ff.sv" \
    "./cv32e40p-master/rtl/cv32e40p_sleep_unit.sv" \
    "./cv32e40p-master/bhv/cv32e40p_sim_clock_gate.sv" \
]

# 5. Çevre Birimleri (Peripherals) Dosyalarını Ekle
add_files -norecurse [list \
    "$periph_dir/gpio_peripheral.sv" \
    "$periph_dir/timer_peripheral.sv" \
    "$periph_dir/i2c_peripheral.sv" \
    "$periph_dir/qspi_master.sv" \
    "$periph_dir/files_1/sync_fifo.sv" \
    "$periph_dir/files_1/uart_rx.sv" \
    "$periph_dir/files_1/uart_tx.sv" \
    "$periph_dir/files_1/uart_peripheral.sv" \
    "$periph_dir/files_1/uart_stream_peripheral.sv" \
    "$periph_dir/npu_accelerator.sv" \
    "$periph_dir/npu_compute_engine.sv" \
    "$periph_dir/npu_csr.sv" \
    "$periph_dir/npu_tcm_sram.sv" \
    "$periph_dir/dma_controller.sv" \
    "$periph_dir/jtag_debug.sv" \
]

# 6. Bellek ve En Üst Seviye (Top) Dosyalarını Ekle (nexys_top.sv dahil)
add_files -norecurse [list \
    "./boot/boot_rom.sv" \
    "./Memory/sram_module.sv" \
    "./Memory/axil_arbiter_2to1.sv" \
    "./Memory/axil_arbiter_3to1.sv" \
    "./Memory/obi_to_axi_simple.sv" \
    "./Memory/axi_lite_interconnect.sv" \
    "./Memory/soc_top.sv" \
    "./Memory/nexys_top.sv" \
]

# 7. Kısıt Dosyalarını (Constraints) Ekle
add_files -fileset constrs_1 -norecurse [list "./nexys4ddr.xdc"]

# 8. Simülasyon Dosyalarını sim_1 Setine Ekle
add_files -fileset sim_1 -norecurse [list \
    "./Memory/tb_soc_top.sv" \
    "./boot/boot.hex" \
]

# 9. Hiyerarşi Top Modüllerini Belirle (Nexys Top olarak ayarlandı)
set_property top nexys_top [current_fileset]
set_property top tb_soc_top [get_filesets sim_1]

# 10. Derleme sırasını ve hiyerarşiyi güncelle
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "================================================================"
puts " Nexys 4 DDR SoC Vivado Projesi Başarıyla Oluşturuldu!"
puts " Ana Modül (Top): nexys_top.sv"
puts " Zamanlama Kısıtları: nexys4ddr.xdc"
puts "================================================================"
