from pathlib import Path
import sys,json
r=Path(__file__).resolve().parents[1];d=r/'closure_20260905'
sys.path.insert(0,str(r/'scripts'));import run_regression as reg
reg.WORK=d/'sim'
t={'ad':'monitor_test','top':'tb_monitor_test','kaynak':[r/'tb/uvm/axil_if.sv',d/'all_axil_pkg.sv',d/'tb_monitor_test.sv'],'tanim':[],'mem':[],'ek_bayrak':['-L','uvm'],'elab_bayrak':['-L','uvm']}
a=reg.test_kos(t,reg.VARSAYILAN_VIVADO)
(d/'monitor_test_result.json').write_text(json.dumps(a,indent=2));print(a)

raise SystemExit(0 if a["durum"] == "GECTI" else 1)
