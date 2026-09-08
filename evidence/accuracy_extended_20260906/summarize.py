from pathlib import Path
import json,re,hashlib,datetime
p=Path(__file__).resolve().parent
meta=json.loads((p/'accuracy_dataset.json').read_text())
status=json.loads((p/'accuracy_result.json').read_text())
log=(p/'sim/accuracy/sim.log').read_text(errors='replace')
rows=[list(map(int,x)) for x in re.findall(r'ACCURACY_ROW (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)',log)]
assert status['durum']=='GECTI' and len(rows)==1400
assert [x[0] for x in rows]==list(range(1400))
records=meta['records'];disagreements=[];numeric=[]
for item,row in zip(records,rows):
    if item['official_class']!=row[1]:disagreements.append({'index':item['index'],'name':item['name'],'label':item['label'],'official':item['official_class'],'rtl':row[1],'official_output':item['official_output_int8'],'rtl_probs':row[2:6]})
    if item['reference']['sinif']!=row[1] or item['reference']['probs']!=row[2:6]:numeric.append(item['index'])
assert not numeric
report={'created':datetime.datetime.now().isoformat(),'count':len(rows),'consecutive_inferences_without_reset':True,'subsets':{},'official_class_disagreements':disagreements,'integer_reference_mismatch_indices':numeric,'limitations':meta['limitations']}
for name,ids in [('speech',range(1200)),('synthetic_silence',range(1200,1300)),('labelled_combined',range(1300)),('stress',range(1300,1400))]+[(n,[i for i in range(1300) if records[i]['label']==c]) for c,n in enumerate(['SILENCE','UNKNOWN','YES','NO'])]:
    ids=list(ids);s={'count':len(ids),'class_agreement_count':sum(records[i]['official_class']==rows[i][1] for i in ids)}
    if name!='stress':
        sw=[[0]*4 for _ in range(4)];hw=[[0]*4 for _ in range(4)]
        for i in ids:sw[records[i]['label']][records[i]['official_class']]+=1;hw[records[i]['label']][rows[i][1]]+=1
        a=sum(sw[i][i] for i in range(4));b=sum(hw[i][i] for i in range(4))
        s.update(official_correct=a,rtl_correct=b,official_accuracy=a/len(ids),rtl_accuracy=b/len(ids),difference_percentage_points=100*(b-a)/len(ids),relative_accuracy_loss=max(0,a-b)/a if a else None,official_confusion=sw,rtl_confusion=hw)
    report['subsets'][name]=s
candidate=json.loads((p.parent/'candidate_manifest.json').read_text())
report['rtl_hash_mismatches']=[n for n,h in candidate['source_hashes'].items() if n.startswith('rtl/') and hashlib.sha256((p.parent/n).read_bytes()).hexdigest()!=h]
assert not report['rtl_hash_mismatches']
report['sha256']={str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in list(p.glob('*.py'))+list(p.glob('*.sv'))+list(p.glob('*.mem'))+[p/'accuracy_dataset.json',p/'selection.json',p/'sim/accuracy/sim.log']}
(p/'report.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:v for k,v in report.items() if k not in ['sha256','limitations']},indent=2))
