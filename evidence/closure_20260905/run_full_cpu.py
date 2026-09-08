from pathlib import Path
import sys,json
r=Path(__file__).resolve().parents[1];d=r/'closure_20260905'
sys.path.insert(0,str(r/'scripts'));import run_regression as reg
reg.WORK=d/'sim';reg.MEM_KAYNAKLARI.insert(0,d)
t={'ad':'full_cpu','top':'tb_full_bench','kaynak':reg.filelist_rtl()+[d/'tb_full_bench.sv'],'tanim':[],'mem':['bench_full.hex','tcm_image.mem']}
a=reg.test_kos(t,reg.VARSAYILAN_VIVADO,ek_tanim=['USE_SRAM_MACRO'])
(d/'full_cpu_result.json').write_text(json.dumps(a,indent=2));print(a)

raise SystemExit(0 if a["durum"] == "GECTI" else 1)
