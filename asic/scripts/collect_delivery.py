"""Explicit source-step mapping; preserves old collected outputs in a dated directory."""
import json,pathlib,shutil,sys,time,hashlib
A=pathlib.Path(__file__).resolve().parents[1];P=A.parent
if len(sys.argv)!=2 or not sys.argv[1]:raise SystemExit('Usage: make collect RUN=run/<tag>')
R=pathlib.Path(sys.argv[1]).resolve()
mapping=json.loads((P/'provenance/output_mapping.json').read_text())
mapping['asic/results/config/resolved.json']='resolved.json'
missing=[v for v in mapping.values() if not (R/v).is_file()]
if missing:raise SystemExit('Incomplete run; no existing outputs changed: '+str(missing))
stage=A/('collection_'+time.strftime('%Y%m%d_%H%M%S'));stage.mkdir()
for dest,src in mapping.items():
 target=stage/pathlib.Path(dest).relative_to('asic');target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/src,target)
for filename,key in [('pnr.sdc','PNR_SDC_FILE'),('signoff.sdc','SIGNOFF_SDC_FILE')]:
 cfg=json.loads((R/'resolved.json').read_text());source=pathlib.Path(cfg[key]);source=source if source.is_absolute() else A/source
 shutil.copy2(source,stage/'results/sdc'/filename)
for name in ['reports','results']:
 old=A/name
 if old.exists():old.rename(stage/('previous_'+name))
 (stage/name).rename(old)
print('Collected original-flow outputs from',R)
print('GDS-derived supplemental LVS must be rerun for a newly generated GDS. Old supplemental results were not carried forward.')
