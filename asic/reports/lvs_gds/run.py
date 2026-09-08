import pathlib,subprocess,os,json,time
O=pathlib.Path(__file__).resolve().parent
S='/nix/store/af8ijg47w5gfv25fb0dyfcw2aca9sqk6-python3.13-librelane-3.0.6/lib/python3.13/site-packages/librelane/scripts'
def save(stage,**kw): (O/'status.json').write_text(json.dumps(dict(stage=stage,time=time.time(),**kw),indent=2))
env={**os.environ,'PDK_ROOT':str(pathlib.Path.home()/'.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71'),'_TCL_ENV_IN':str(O/'env.tcl'),'_MAGIC_SCRIPT':S+'/magic/extract_spice.tcl'}
save('EXTRACTING_GDS',scope='GDS standard cells and top-level interconnect; exact SRAM master abstracted, SRAM internals not verified')
with (O/'extract.log').open('w') as f:
 r=subprocess.run(['/nix/store/i68lxdmnc7422hvlabbmrhss4sqqkjzq-magic-vlsi-8.3.623/bin/magic','-dnull','-noconsole','-rcfile',str(pathlib.Path.home()/'.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.tech/magic/sky130A.magicrc'),S+'/magic/wrapper.tcl'],cwd=O,env=env,stdout=f,stderr=subprocess.STDOUT)
if r.returncode or not (O/'soc_top.spice').exists():
 save('EXTRACTION_FAILED',code=r.returncode);raise SystemExit(1)
save('NETGEN_COMPARISON')
env['_TCL_ENV_IN']=str(O/'netgen_env.tcl')
with (O/'netgen.log').open('w') as f:
 r=subprocess.run(['/nix/store/kw3frc6fbv3zi2m9n0wv93y1nfiyjiy6-netgen-1.5.316/bin/netgen','-batch','source',str(O/'lvs_script.lvs')],cwd=O,env=env,stdout=f,stderr=subprocess.STDOUT)
report=(O/'lvs.netgen.rpt').read_text(errors='replace') if (O/'lvs.netgen.rpt').exists() else ''
save('FINISHED_REVIEW_REQUIRED',code=r.returncode,report_tail=report[-3500:])
