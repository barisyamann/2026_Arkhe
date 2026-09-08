# Ek GDS kaynakl? LVS

Ayn? d45_anten2 Magic GDS ve powered netlist kar??la?t?r?ld?. Sonu?: Circuits match uniquely.
MAGIC_EXT_USE_GDS=1; yaln?z ^sky130_sram_2kbyte_1rw1r_32x512_8$ SRAM master abstract edildi. SRAM i? transist?r do?rulamas? kapsam d???d?r. PDK transistor/diode modelleri Netgen taraf?ndan primitive blackbox olarak temsil edilir. Standart h?cre ve ?st d?zey ba?lant?lar GDS geometrisinden ??kar?lm??t?r.
?zg?n LEF/DEF LVS raporu ../lvs/ alt?nda korunur. SPICE: ../../results/spice/soc_top_gds.spice.
env.tcl, lvs_script.lvs ve run.py dosyalar? ?zg?n sunucu ?al??ma kayd?d?r; i?lerindeki mutlak yollar tarihsel kay?tt?r. Ta??nabilir yeniden ?al??t?rma: make gds_lvs.
