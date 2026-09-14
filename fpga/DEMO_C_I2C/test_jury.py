from pathlib import Path
import sys,json
root=Path(__file__).resolve().parents[1];d=root/'jury_demo'
sys.path.insert(0,str(root/'scripts'))
import run_regression as reg
head=(root/'tb/tb_soc_top.sv').read_text().split('    // --- SystemVerilog Functional Coverage')[0].replace('module tb_soc_top;','module tb_jury;')
(d/'tb_jury.sv').write_text(head+(d/'tb_tail.sv').read_text())
for i,name in enumerate(['deterministik_golden','rastgele_sinif0_silence']):
    (d/f'input{i}.hex').write_text('\n'.join(f'{b:02x}' for b in (d/(name+'.bin')).read_bytes()))
reg.WORK=d/'sim';reg.MEM_KAYNAKLARI.insert(0,d)
sources=[d/'boot_rom_pkg.sv' if f.name=='boot_rom_pkg.sv' else f for f in reg.filelist_rtl()]
t={'ad':'jury','top':'tb_jury','kaynak':sources+[root/'tb/spi_flash_model.sv',d/'tb_jury.sv'],'tanim':['REAL_BOOT'],'mem':['flash_sim.hex','input0.hex','input1.hex']}
r=reg.test_kos(t,reg.VARSAYILAN_VIVADO)
(d/'simulation_result.json').write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2))
raise SystemExit(0 if r['durum']=='GECTI' else 1)
