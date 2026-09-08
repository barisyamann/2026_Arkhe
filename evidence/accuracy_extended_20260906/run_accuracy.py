from pathlib import Path
import sys,json
r=Path(__file__).resolve().parents[1];d=r/'accuracy_extended_20260906'
sys.path.insert(0,str(r/'scripts'));import run_regression as reg
reg.WORK=d/'sim';reg.MEM_KAYNAKLARI.insert(0,d)
t={'ad':'accuracy','top':'tb_accuracy','kaynak':reg.filelist_rtl()+[d/'tb_accuracy.sv'],'tanim':[],'mem':['accuracy_inputs.mem','accuracy_expected.mem','fc_weights_packed32.mem']}
a=reg.test_kos(t,reg.VARSAYILAN_VIVADO);(d/'accuracy_result.json').write_text(json.dumps(a,indent=2));print(a)

raise SystemExit(0 if a["durum"] == "GECTI" else 1)
