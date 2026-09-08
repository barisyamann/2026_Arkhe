"""Check exact deliverables, source lists and content hashes; report signoff separately."""
import pathlib,json,hashlib,sys
P=pathlib.Path(__file__).resolve().parents[2];A=P/'asic'
required=json.loads((P/'provenance/requirements.json').read_text())
missing=[s for s in required if not (P/s).is_file()]
empty=[s for s in required if (P/s).is_file() and (P/s).stat().st_size==0 and not s.endswith(('.rpt','.drc'))]
cfg=json.loads((A/'config.yaml').read_text())
listed=[s.strip() for s in (A/'filelist.f').read_text().splitlines() if s.strip() and not s.startswith('#')]
actual=[str(pathlib.PurePosixPath(s).relative_to('..')) for s in cfg['VERILOG_FILES']]
source_errors=[]
if listed!=actual:source_errors.append('filelist/config mismatch')
source_errors += [s for s in listed if not (P/s).is_file()]
if (A/'run').exists() and any(f.name!='.gitkeep' for f in (A/'run').iterdir()):source_errors.append('asic/run must be empty except .gitkeep')
bad=[]
manifest=P/'provenance/package_files.json'
if manifest.exists():
 for rel,info in json.loads(manifest.read_text()).items():
  f=P/rel
  if not f.is_file():bad.append(rel+' missing');continue
  if f.stat().st_size!=info['bytes']:bad.append(rel+' size mismatch');continue
  h=hashlib.sha256()
  with f.open('rb') as stream:
   for block in iter(lambda:stream.read(4*1024*1024),b''):h.update(block)
  if h.hexdigest()!=info['sha256']:bad.append(rel+' hash mismatch')
else:bad.append('package_files.json missing')
print(json.dumps({'missing':missing,'empty':empty,'source_errors':source_errors,'hash_errors':bad,'signoff_clean':False,'note':'File completeness is separate from timing/DRC closure; read asic/README.md.'},indent=2))
sys.exit(bool(missing or empty or source_errors or bad))
