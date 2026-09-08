"""Restore verified release files; Python 3.11.8+ (tar data filter required)."""
import argparse,hashlib,io,json,os,pathlib,tarfile,urllib.request
REPO='barisyamann/2026_Arkhe';TAG='d45-anten2-20260908'
ROOT=pathlib.Path(__file__).resolve().parents[1]
def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(4*1024*1024),b''):h.update(b)
 return h.hexdigest()
class Parts(io.RawIOBase):
 def __init__(self,paths):self.paths=iter(paths);self.f=None
 def readable(self):return True
 def read(self,n=-1):
  if n<0:raise ValueError('Bounded streaming reads only')
  data=bytearray()
  while len(data)<n:
   if self.f is None:
    try:self.f=next(self.paths).open('rb')
    except StopIteration:break
   b=self.f.read(n-len(data))
   if b:data.extend(b)
   else:self.f.close();self.f=None
  return bytes(data)
 def close(self):
  if self.f:self.f.close()
  super().close()
def restore(kind,cache=None):
 manifest=json.loads((ROOT/'provenance/release_assets.json').read_text())
 spec=manifest[kind];cache=cache or ROOT/'.delivery_downloads';cache.mkdir(exist_ok=True)
 files=[]
 for part in spec['parts']:
  f=cache/part['name']
  if not f.exists():
   print('Downloading',f.name,flush=True)
   req=urllib.request.Request(f'https://github.com/{REPO}/releases/download/{TAG}/{f.name}')
   with urllib.request.urlopen(req,timeout=120) as response,f.with_suffix(f.suffix+'.tmp').open('wb') as out:
    while b:=response.read(4*1024*1024):out.write(b)
   f.with_suffix(f.suffix+'.tmp').rename(f)
  if f.stat().st_size!=part['bytes'] or digest(f)!=part['sha256']:raise RuntimeError('Asset checksum mismatch: '+f.name)
  files.append(f)
 destination=ROOT if kind=='delivery' else ROOT/'asic/run'
 destination.mkdir(parents=True,exist_ok=True)
 with Parts(files) as stream,tarfile.open(fileobj=stream,mode='r|gz') as archive:
  for member in archive:
   if kind=='delivery':
    if member.name=='package':continue
    if not member.name.startswith('package/'):raise RuntimeError('Unexpected package path')
    member.name=member.name[len('package/'):]
    if member.islnk():
     if not member.linkname.startswith('package/'):raise RuntimeError('Unsafe hardlink')
     member.linkname=member.linkname[len('package/'):]
   path=pathlib.PurePosixPath(member.name)
   if path.is_absolute() or '..' in path.parts:raise RuntimeError('Unsafe path')
   target=destination/member.name
   if target.is_file() and member.isfile():
    h=hashlib.sha256();f=archive.extractfile(member)
    for b in iter(lambda:f.read(4*1024*1024),b''):h.update(b)
    if digest(target)!=h.hexdigest():raise RuntimeError('Existing file differs; use a clean checkout: '+member.name)
    continue
   archive.extract(member,path=destination,filter='data')
 print('Restored',kind,'to',destination)
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--delivery',action='store_true');ap.add_argument('--raw',action='store_true');ns=ap.parse_args()
 if not ns.delivery and not ns.raw:ap.error('choose --delivery and/or --raw')
 if ns.delivery:restore('delivery')
 if ns.raw:restore('raw')
