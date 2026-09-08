"""Create evidence summaries from completed logs, never from PASS text alone."""
from pathlib import Path
import json,re,hashlib,datetime
d=Path(__file__).resolve().parent
def read(name):return json.loads((d/name).read_text())
def require(ok,message):
    if not ok:raise RuntimeError(message)

dataset=read('accuracy_dataset.json')
alog=(d/'sim/accuracy/sim.log').read_text(encoding='utf-8',errors='replace')
rows=[list(map(int,m)) for m in re.findall(r'ACCURACY_ROW (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)',alog)]
require(read('accuracy_result.json')['durum']=='GECTI' and len(rows)==101,'Accuracy run incomplete')
require([x[0] for x in rows]==list(range(101)),'Missing/duplicated accuracy rows')
report={'rtl_simulation_passed':True,'evaluation_count':100,'benchmark_count':1,'subsets':{},
        'limitations':dataset['limitations'],'source':dataset['source']}
for name,ids in [('speech',list(range(75))),('synthetic_silence',list(range(75,100))),('combined',list(range(100)))]:
    sw=[[0]*4 for _ in range(4)];hw=[[0]*4 for _ in range(4)]
    for i in ids:
        item=dataset['records'][i];sw[item['label']][item['official_class']]+=1;hw[item['label']][rows[i][1]]+=1
    a=sum(sw[i][i] for i in range(4))/len(ids);b=sum(hw[i][i] for i in range(4))/len(ids)
    report['subsets'][name]={'count':len(ids),'tflite_accuracy':a,'rtl_accuracy':b,'difference_percentage_points':100*(b-a),
        'relative_accuracy_difference':abs(b-a)/a if a else None,'tflite_confusion':sw,'rtl_confusion':hw}
report['class_disagreements_including_benchmark']=sum(rows[i][1]!=v['official_class'] for i,v in enumerate(dataset['records']))
report['rtl_vs_integer_reference_probability_mismatches']=sum(rows[i][2:6]!=v['reference']['probs'] for i,v in enumerate(dataset['records']))
require(report['rtl_vs_integer_reference_probability_mismatches']==0,'RTL numeric mismatch')
(d/'accuracy_report.json').write_text(json.dumps(report,indent=2))

log=(d/'sim/full_cpu/sim.log').read_text(encoding='utf-8',errors='replace')
require(read('full_cpu_result.json')['durum']=='GECTI','CPU run incomplete')
cpu=int(re.search(r'FULL_CPU_CYCLES (\d+)',log)[1]);npu=rows[100][-1]
require(cpu>0 and npu>0,'Invalid cycle count')
require('FULL_CPU_PROBS 0 225 326 3543' in log and rows[100][2:6]==[0,225,326,3543],'Benchmark outputs differ')
speed={'passed':True,'cpu_cycles':cpu,'npu_cycles':npu,'speedup':cpu/npu,'reference_clock_hz':50000000,
    'cpu_seconds_at_50mhz':cpu/5e7,'npu_seconds_at_50mhz':npu/5e7,'output_q12':rows[100][2:6],
    'input':'benchmark_golden','cpu_scope':'Full 4000 convolution outputs, FC bias/MAC/requantization and softmax; custom C, -Os rv32imc_zicsr; CPU RTL with SRAM models',
    'npu_scope':'Compute engine with synchronous TCM model; no boot/UART/DMA input transfer',
    'limitations':['Single benchmark input','Custom integer C baseline, not official TFLite Micro executable',
        'Comparison clock is not ASIC post-route timing closure']}
(d/'speed_report.json').write_text(json.dumps(speed,indent=2))

axi={'passed':False,'status':'PENDING'}
if (d/'all_axi_result.json').exists():
    status=read('all_axi_result.json');log=(d/'sim/all_axi/sim.log').read_text(encoding='utf-8',errors='replace')
    inventory=read('axi_inventory.json');coverage=[]
    for m in re.finditer(r'^AXI_COVER (\d+) (\w+) (.*)$',log,re.M):
        coverage.append(dict(index=int(m[1]),name=m[2],**{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',m[3])}))
    passed=(status['durum']=='GECTI' and '[PASS] ALL_AXI_INTERFACES' in log and len(coverage)==len(inventory)
            and all(c['ERR']==0 and c['R']>0 and (inventory[c['index']]['read_only'] or c['B']>0) for c in coverage)
            and 'UVM_ERROR' not in log and 'UVM_FATAL' not in log)
    axi={'passed':passed,'status':status,'interfaces':coverage,'inventory_count':len(inventory),
        'scope':'23 unique AXI-Lite links, passive UVM agents, transaction queues and channel stability checks',
        'notes':['Defined SRAM precondition: crt0_deterministic.S zeroes all 8KB data SRAM using CPU stores before C startup; app.ld includes .sbss/.sdata',
                 'The original firmware produced X-containing DRAM reads; baseline_uninitialized_dram.log is preserved, no X checks disabled',
                 'SLVERR/DECERR are legal responses; directed ROM-write fault is expected',
                 'Continuous instruction fetch may have an outstanding transaction at simulation end; 5ms test liveness bound',
                 'Aggregate counts across cascaded links double-count the same logical transaction; use per-interface counts',
                 'Protocol smoke coverage is not exhaustive randomized AXI verification']}
    require([c['name'] for c in coverage]==[v['name'] for v in inventory] or not passed,'Inventory mismatch')
    (d/'axi_report.json').write_text(json.dumps(axi,indent=2))
result={'created':datetime.datetime.now().isoformat(),'accuracy':report,'speed':speed,'axi':axi,
        'monitor_selftest':read('monitor_test_result.json') if (d/'monitor_test_result.json').exists() else None}
paths=list(d.glob('*.py'))+list(d.glob('*.sv'))+list(d.glob('*.c'))+list(d.glob('*.mem'))
paths += [d/'sim/accuracy/sim.log',d/'sim/full_cpu/sim.log',d/'accuracy_dataset.json',d/'selection.json',d/'bench_full.hex']
for path in [d/'sim/all_axi/sim.log',d/'sim/monitor_test/sim.log',d/'baseline_uninitialized_dram.log',
             d/'crt0_deterministic.S',d/'firmware/bench_full/bench_full.elf',d/'firmware/app_defined/app_defined.elf']:
    if path.exists():paths.append(path)
result['sha256']={str(p.relative_to(d)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
candidate=json.loads((d.parent/'candidate_manifest.json').read_text())
result['candidate_rtl_hash_mismatches']=[name for name,h in candidate['source_hashes'].items()
    if name.startswith('rtl/') and (not (d.parent/name).exists() or hashlib.sha256((d.parent/name).read_bytes()).hexdigest()!=h)]
require(not result['candidate_rtl_hash_mismatches'],'Candidate RTL changed')
result['external_input_sha256']={str(p.relative_to(d.parent)):hashlib.sha256(p.read_bytes()).hexdigest()
    for p in [d.parent/'model/micro_speech_quantized.tflite',d.parent/'weights/fc_weights_packed32.mem',
              d.parent/'tb/npu_sw_bench/tcm_image.mem',d.parent/'jury_demo/app.ld',d.parent/'sw_nexys/src/main.c']}
(d/'closure_report.json').write_text(json.dumps(result,indent=2))
print('Accuracy:',report['subsets']['combined'],'Speedup:',speed['speedup'],'AXI passed:',axi['passed'])
