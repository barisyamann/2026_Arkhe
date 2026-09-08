"""Run the pinned Classic flow without overwriting an existing run."""
import os,pathlib,subprocess,sys,time
A=pathlib.Path(__file__).resolve().parents[1]
if not os.environ.get('PDK_ROOT'): raise SystemExit('Set PDK_ROOT to the directory containing sky130A; see README.md')
run=A/'run';run.mkdir(exist_ok=True)
alias=A/'runs'
if alias.is_symlink():
 if alias.resolve()!=run.resolve():raise SystemExit('runs symlink does not point to run')
elif alias.exists():raise SystemExit('runs already exists; preserve it and choose a fresh checkout')
else:alias.symlink_to('run',target_is_directory=True)
tag='d45_anten2_reproduce_'+time.strftime('%Y%m%d_%H%M%S')
if (run/tag).exists():raise SystemExit('Run already exists')
command=[os.environ.get('LIBRELANE','librelane'),'--manual-pdk','--pdk-root',os.environ['PDK_ROOT'],'--run-tag',tag,'config.yaml']
result=subprocess.run(command,cwd=A)
# Deferred signoff failures still produce inspectable artifacts; preserve nonzero status.
collected=subprocess.run([sys.executable,str(A/'scripts/collect_delivery.py'),str(run/tag)],cwd=A)
gds_code=0
if collected.returncode==0:
 gds_code=subprocess.run([sys.executable,str(A/'scripts/run_gds_lvs.py')],cwd=A).returncode
raise SystemExit(result.returncode or collected.returncode or gds_code)
