# Add your design files into the Vivado project
# 

# Include directories paths relative to teknotest directory
set include_dirs [list \
    [file normalize "../cv32e40p-master/rtl/include"] \
    [file normalize "../Memory"] \
    [file normalize "../Cevre_Birimleri/files_1"] \
]
set_property include_dirs $include_dirs [list [get_filesets sources_1] [get_filesets sim_1]]

# Package / Configuration files (Must be added first to resolve package dependencies)
add_files -norecurse [list \
    "../Memory/memory_map_pck.sv" \
    "../cv32e40p-master/rtl/include/cv32e40p_apu_core_pkg.sv" \
    "../cv32e40p-master/rtl/include/cv32e40p_fpu_pkg.sv" \
    "../cv32e40p-master/rtl/include/cv32e40p_pkg.sv" \
    "../Cevre_Birimleri/files_1/uart_pkg.sv" \
]
update_compile_order -fileset sources_1

# RISC-V Core files (CV32E40P)
add_files -norecurse [list \
    "../cv32e40p-master/rtl/cv32e40p_aligner.sv" \
    "../cv32e40p-master/rtl/cv32e40p_alu.sv" \
    "../cv32e40p-master/rtl/cv32e40p_alu_div.sv" \
    "../cv32e40p-master/rtl/cv32e40p_apu_disp.sv" \
    "../cv32e40p-master/rtl/cv32e40p_compressed_decoder.sv" \
    "../cv32e40p-master/rtl/cv32e40p_controller.sv" \
    "../cv32e40p-master/rtl/cv32e40p_core.sv" \
    "../cv32e40p-master/rtl/cv32e40p_cs_registers.sv" \
    "../cv32e40p-master/rtl/cv32e40p_decoder.sv" \
    "../cv32e40p-master/rtl/cv32e40p_ex_stage.sv" \
    "../cv32e40p-master/rtl/cv32e40p_ff_one.sv" \
    "../cv32e40p-master/rtl/cv32e40p_fifo.sv" \
    "../cv32e40p-master/rtl/cv32e40p_hwloop_regs.sv" \
    "../cv32e40p-master/rtl/cv32e40p_id_stage.sv" \
    "../cv32e40p-master/rtl/cv32e40p_if_stage.sv" \
    "../cv32e40p-master/rtl/cv32e40p_int_controller.sv" \
    "../cv32e40p-master/rtl/cv32e40p_load_store_unit.sv" \
    "../cv32e40p-master/rtl/cv32e40p_mult.sv" \
    "../cv32e40p-master/rtl/cv32e40p_obi_interface.sv" \
    "../cv32e40p-master/rtl/cv32e40p_popcnt.sv" \
    "../cv32e40p-master/rtl/cv32e40p_prefetch_buffer.sv" \
    "../cv32e40p-master/rtl/cv32e40p_prefetch_controller.sv" \
    "../cv32e40p-master/rtl/cv32e40p_register_file_ff.sv" \
    "../cv32e40p-master/rtl/cv32e40p_sleep_unit.sv" \
    "../cv32e40p-master/bhv/cv32e40p_sim_clock_gate.sv" \
]

# Peripherals, memories and top files
add_files -norecurse [list \
    "../Cevre_Birimleri/gpio_peripheral.sv" \
    "../Cevre_Birimleri/timer_peripheral.sv" \
    "../Cevre_Birimleri/i2c_peripheral.sv" \
    "../Cevre_Birimleri/qspi_master.sv" \
    "../Cevre_Birimleri/files_1/sync_fifo.sv" \
    "../Cevre_Birimleri/files_1/uart_rx.sv" \
    "../Cevre_Birimleri/files_1/uart_tx.sv" \
    "../Cevre_Birimleri/files_1/uart_peripheral.sv" \
    "../Cevre_Birimleri/files_1/uart_stream_peripheral.sv" \
    "../Cevre_Birimleri/npu_accelerator.sv" \
    "../Cevre_Birimleri/npu_compute_engine.sv" \
    "../Cevre_Birimleri/npu_csr.sv" \
    "../Cevre_Birimleri/npu_tcm_sram.sv" \
    "../Cevre_Birimleri/dma_controller.sv" \
    "../Cevre_Birimleri/jtag_debug.sv" \
    "../boot/boot_rom.sv" \
    "../Memory/sram_module.sv" \
    "../Memory/axil_arbiter_2to1.sv" \
    "../Memory/axil_arbiter_3to1.sv" \
    "../Memory/obi_to_axi_simple.sv" \
    "../Memory/axi_lite_interconnect.sv" \
    "../Memory/soc_top.sv" \
    "./user_files/teknotest_wrapper.sv" \
]

set_property top teknotest_tb [get_filesets sim_1]
