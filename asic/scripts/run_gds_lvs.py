"""Supplemental GDS extraction/LVS, same geometry; SRAM internals abstracted."""
import os,pathlib,subprocess,json,time,sys,shutil
A=pathlib.Path(__file__).resolve().parents[1]
if not os.environ.get('PDK_ROOT'):raise SystemExit('Set PDK_ROOT')
(A/'run').mkdir(exist_ok=True)
alias=A/'runs'
if alias.is_symlink():
 if alias.resolve()!=(A/'run').resolve():raise SystemExit('runs does not point to run')
elif alias.exists():raise SystemExit('Use a clean checkout; runs already exists')
else:alias.symlink_to('run',target_is_directory=True)
tag='d45_gds_lvs_'+time.strftime('%Y%m%d_%H%M%S')
state={'metrics':{},'gds':str(A/'results/gds/soc_top.gds'),'pnl':str(A/'results/netlist/soc_top_powered.v'),'def':str(A/'results/def/soc_top.def'),'nl':str(A/'results/netlist/soc_top_pnr.v')}
for k,v in state.items():
 if k!='metrics' and not pathlib.Path(v).exists():raise SystemExit('Missing '+v)
input_file=A/'run'/(tag+'_input.json');input_file.parent.mkdir(exist_ok=True);input_file.write_text(json.dumps(state))
args=[os.environ.get('LIBRELANE','librelane'),'--manual-pdk','--pdk-root',os.environ['PDK_ROOT'],'--run-tag',tag,'--from','Magic.SpiceExtraction','--to','Netgen.LVS','--with-initial-state',str(input_file),'-c','MAGIC_EXT_USE_GDS=true','-c','MAGIC_EXT_ABSTRACT_CELLS=["^sky130_sram_2kbyte_1rw1r_32x512_8$"]','config.yaml']
r=subprocess.run(args,cwd=A)
run=A/'runs'/tag;out=A/'reports/lvs_gds';out.mkdir(parents=True,exist_ok=True)
for step in run.glob('*'):
 if step.is_dir() and ('spiceextraction' in step.name or 'netgen-lvs' in step.name):
  for f in step.rglob('*'):
   if f.is_file() and f.suffix in ['.rpt','.json','.log']:
    target=out/step.name/f.relative_to(step);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
  spice=step/'soc_top.spice'
  if spice.exists():shutil.copy2(spice,A/'results/spice/soc_top_gds.spice')
print('Supplemental run:',run,'SRAM interior abstracted; review Netgen report, not only exit code.')
sys.exit(r.returncode)
