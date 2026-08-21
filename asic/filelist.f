# =============================================================================
# asic/filelist.f - ASIC sentezinde kullanilacak RTL kaynaklari
# TEKNOFEST 2026 - Takim Arkhe
#
# Yollar GORELIDIR; akis asic/ dizininden baslatildiginda cozumlenir.
# Siralama HDL derleme bagimliliklarina gore: paketler once, ust modul sonda.
#
# ASIC'e GIRMEYENLER ve nedenleri:
#   nexys_top.sv             FPGA'e ozgu ust sarmalayici. Ucdurumlu surucu
#                            halkasi ve kart pinleri icerir; ASIC'te bu
#                            katmanin yerini pad halkasi alir.
#   tb_*.sv / *_tb.sv        Testbench'ler - sentezde kullanilmaz.
#   spi_flash_model.sv       Yalnizca simulasyon modeli.
#   axil_protocol_checker.sv Yalnizca SVA denetleyicisi, sentezlenmez.
# =============================================================================


# --- Paketler (once derlenmeli) ---
../rtl/Cevre_Birimleri/files_1/uart_pkg.sv
# ROM icerik paketleri - URETILMISTIR (scripts/gen_rom_paketleri.py).
# Bunlar boot_rom.sv ve npu_compute_engine.sv'den ONCE gelmelidir.
../rtl/boot/boot_rom_pkg.sv
../rtl/npu/npu_weights_pkg.sv
../rtl/Memory/memory_map_pck.sv
../rtl/cv32e40p-master/rtl/include/cv32e40p_apu_core_pkg.sv
../rtl/cv32e40p-master/rtl/include/cv32e40p_fpu_pkg.sv
../rtl/cv32e40p-master/rtl/include/cv32e40p_pkg.sv

# --- RTL kaynaklari ---
../rtl/Cevre_Birimleri/dma_controller.sv
../rtl/Cevre_Birimleri/files_1/sync_fifo.sv
../rtl/Cevre_Birimleri/files_1/uart_peripheral.sv
../rtl/Cevre_Birimleri/files_1/uart_rx.sv
../rtl/Cevre_Birimleri/files_1/uart_stream_peripheral.sv
../rtl/Cevre_Birimleri/files_1/uart_tx.sv
../rtl/Cevre_Birimleri/gpio_peripheral.sv
../rtl/Cevre_Birimleri/i2c_peripheral.sv
../rtl/Cevre_Birimleri/jtag_debug.sv
../rtl/Cevre_Birimleri/qspi_master.sv
../rtl/Cevre_Birimleri/timer_peripheral.sv
../rtl/Memory/axi_lite_interconnect.sv
../rtl/Memory/axil_arbiter_2to1.sv
../rtl/Memory/axil_arbiter_3to1.sv
../rtl/Memory/obi_to_axi_simple.sv
../rtl/Memory/sram_module.sv
../rtl/boot/boot_rom.sv
../rtl/cv32e40p-master/bhv/cv32e40p_sim_clock_gate.sv
../rtl/cv32e40p-master/rtl/cv32e40p_aligner.sv
../rtl/cv32e40p-master/rtl/cv32e40p_alu.sv
../rtl/cv32e40p-master/rtl/cv32e40p_alu_div.sv
../rtl/cv32e40p-master/rtl/cv32e40p_apu_disp.sv
../rtl/cv32e40p-master/rtl/cv32e40p_compressed_decoder.sv
../rtl/cv32e40p-master/rtl/cv32e40p_controller.sv
../rtl/cv32e40p-master/rtl/cv32e40p_core.sv
../rtl/cv32e40p-master/rtl/cv32e40p_cs_registers.sv
../rtl/cv32e40p-master/rtl/cv32e40p_decoder.sv
../rtl/cv32e40p-master/rtl/cv32e40p_ex_stage.sv
../rtl/cv32e40p-master/rtl/cv32e40p_ff_one.sv
../rtl/cv32e40p-master/rtl/cv32e40p_fifo.sv
../rtl/cv32e40p-master/rtl/cv32e40p_hwloop_regs.sv
../rtl/cv32e40p-master/rtl/cv32e40p_id_stage.sv
../rtl/cv32e40p-master/rtl/cv32e40p_if_stage.sv
../rtl/cv32e40p-master/rtl/cv32e40p_int_controller.sv
../rtl/cv32e40p-master/rtl/cv32e40p_load_store_unit.sv
../rtl/cv32e40p-master/rtl/cv32e40p_mult.sv
../rtl/cv32e40p-master/rtl/cv32e40p_obi_interface.sv
../rtl/cv32e40p-master/rtl/cv32e40p_popcnt.sv
../rtl/cv32e40p-master/rtl/cv32e40p_prefetch_buffer.sv
../rtl/cv32e40p-master/rtl/cv32e40p_prefetch_controller.sv
../rtl/cv32e40p-master/rtl/cv32e40p_register_file_ff.sv
../rtl/cv32e40p-master/rtl/cv32e40p_sleep_unit.sv
../rtl/npu/npu_accelerator.sv
../rtl/npu/npu_axi_controller.sv
../rtl/npu/npu_compute_engine.sv
../rtl/npu/npu_csr.sv
../rtl/npu/npu_tcm_sram.sv

# --- Ust modul ---
../rtl/Memory/soc_top.sv
