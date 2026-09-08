from pathlib import Path
import sys, json, random, zipfile, hashlib, io, wave
import numpy as np
from ai_edge_litert.interpreter import Interpreter

d=Path(__file__).resolve().parent;r=d.parent
sys.path.insert(0,str(r/'tb/npu_audio'))
from micro_frontend import ozellik_cikar
from npu_ref_model import NpuReferansModel
seed=20260905;rng=random.Random(seed);noise=np.random.default_rng(seed)
z=zipfile.ZipFile(d/'mini_speech_commands.zip')
files=sorted(n for n in z.namelist() if n.startswith('mini_speech_commands/') and n.endswith('.wav'))
selection=[]
for label,words in [(2,['yes']),(3,['no']),(1,['down','go','left','right','stop','up'])]:
    pool=[n for n in files if n.split('/')[-2] in words]
    selection += [(n,label) for n in rng.sample(pool,25)]
# Selection is frozen BEFORE consulting either model. Silence is a separate synthetic stratum.
(d/'selection.json').write_text(json.dumps({'seed':seed,'speech':selection,'synthetic_silence':25},indent=2))
it=Interpreter(model_path=str(r/'model/micro_speech_quantized.tflite'));it.allocate_tensors()
inp=it.get_input_details()[0];out=it.get_output_details()[0];ref=NpuReferansModel()
records=[];packed=[];expected=[]
for index in range(101):
    if index<75:
        name,label=selection[index];raw=z.read(name)
        with wave.open(io.BytesIO(raw),'rb') as w:
            assert w.getframerate()==16000 and w.getnchannels()==1 and w.getsampwidth()==2
            samples=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float64)
        samples=np.pad(samples[:16000],(0,max(0,16000-len(samples))))
        q=ozellik_cikar(samples).reshape(-1)
        source_hash=hashlib.sha256(raw).hexdigest()
    elif index<100:
        name=f'synthetic_silence_{index-75}';label=0
        samples=np.zeros(16000) if index==75 else noise.integers(-2,3,16000).astype(np.float64)
        q=ozellik_cikar(samples).reshape(-1);source_hash=hashlib.sha256(samples.astype('<i2').tobytes()).hexdigest()
    else:
        name='benchmark_golden';label=None;source_hash=None
        q=np.array([((i*37+13)%256)-128 for i in range(1960)],dtype=np.int8)
    it.set_tensor(inp['index'],q.reshape(inp['shape']).astype(np.int8));it.invoke()
    official=it.get_tensor(out['index']).reshape(-1).astype(int)
    result=ref.infer(q.astype(int).tolist())
    raw=q.astype(np.int8).tobytes()
    records.append({'index':index,'name':name,'label':label,'source_sha256':source_hash,
        'input_sha256':hashlib.sha256(raw).hexdigest(),'official_class':int(np.argmax(official)),
        'official_output_int8':official.tolist(),'reference':result})
    packed += [f'{int.from_bytes(raw[i:i+4],"little"):08x}' for i in range(0,1960,4)]
    expected += [f'{result["sinif"]:08x}']+[f'{p:08x}' for p in result['probs']]
    print(index,name,'label',label,'official',np.argmax(official),'reference',result['sinif'],flush=True)
metadata={'source':'https://www.tensorflow.org/tutorials/audio/simple_audio',
    'archive_sha256':hashlib.sha256((d/'mini_speech_commands.zip').read_bytes()).hexdigest(),
    'model_sha256':hashlib.sha256((r/'model/micro_speech_quantized.tflite').read_bytes()).hexdigest(),
    'seed':seed,'speech_count':75,'synthetic_silence_count':25,'benchmark_count':1,
    'limitations':['Small stratified evaluation, not entire official test set; training overlap unknown',
        'Floating-point host frontend, not bit-exact official microfrontend; identical tensors used on both classifiers',
        'Synthetic silence evaluated separately; no model-output-based selection'], 'records':records}
(d/'accuracy_inputs.mem').write_text('\n'.join(packed)+'\n')
(d/'accuracy_expected.mem').write_text('\n'.join(expected)+'\n')
(d/'accuracy_dataset.json').write_text(json.dumps(metadata,indent=2))
