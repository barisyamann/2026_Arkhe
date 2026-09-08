from pathlib import Path
import sys,json
r=Path(__file__).resolve().parents[1];d=r/'closure_20260905'
sys.path.insert(0,str(r/'scripts'));import run_regression as reg
reg.WORK=d/'sim';reg.MEM_KAYNAKLARI.insert(0,d)
t={'ad':'all_axi','top':'tb_all_axi','kaynak':reg.filelist_rtl()+[r/'rtl/Memory/axil_protocol_checker.sv',r/'tb/uvm/axil_if.sv',d/'all_axil_pkg.sv',r/'tb/spi_flash_model.sv',d/'tb_all_axi.sv'],'tanim':['REAL_BOOT'],'mem':['flash_sim.hex','flash.hex','boot.hex','app.hex','app_sim.hex','qspi_test_pattern.hex'],'ek_bayrak':['-L','uvm'],'elab_bayrak':['-L','uvm']}
a=reg.test_kos(t,reg.VARSAYILAN_VIVADO,ek_tanim=['USE_SRAM_MACRO']);(d/'all_axi_result.json').write_text(json.dumps(a,indent=2));print(a)


raise SystemExit(0 if a["durum"] == "GECTI" else 1)
