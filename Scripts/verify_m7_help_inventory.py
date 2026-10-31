#!/usr/bin/env python3
"""Execute help and invalid-invocation refusal for every enabled CLI/subcommand."""
import argparse, hashlib, json, re, subprocess
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--bin-dir',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True)
a=p.parse_args();root=a.output_dir.resolve();root.mkdir(parents=True,exist_ok=False)
tools=sorted(x for x in a.bin_dir.glob('dicom-*') if x.is_file() and x.stat().st_mode&0o111)
assert len(tools)==41, 'Reconcile enabled tool inventory before qualification'
records=[]
for binary in tools:
 queue=[[]];seen=set()
 while queue:
  path=queue.pop(0);key=tuple(path)
  if key in seen:continue
  seen.add(key);label='__'.join([binary.name]+path);record={'tool':binary.name,'subcommands':path,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
  for name,args in [('help',['--help']),('invalid-invocation',['--dicomkit-m7-invalid-option'])]:
   argv=[str(binary),*path,*args]
   try:r=subprocess.run(argv,text=True,capture_output=True,timeout=10);out=r.stdout+r.stderr;exit_code=r.returncode
   except subprocess.TimeoutExpired as e:out=str(e);exit_code=None
   (root/(label+'-'+name+'.log')).write_text(out)
   record[name]={'argv':argv,'exit':exit_code,'passed':exit_code==0 and 'USAGE:' in out if name=='help' else exit_code==64}
   if name=='help' and exit_code==0:
    section=re.search(r'^SUBCOMMANDS:\n(.*?)(?=^[A-Z][A-Z /-]+:|\Z)',out,re.M|re.S)
    if section:
     for match in re.finditer(r'^  ([a-zA-Z0-9-]+)(?: \(default\))?\s{2,}\S',section.group(1),re.M):
      child=match.group(1)
      if child!='help':queue.append(path+[child])
  records.append(record)
summary={'tools':len(tools),'routes':len(records),'passed':all(r['help']['passed'] and r['invalid-invocation']['passed'] for r in records),'records':records}
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k!='records'}))
for r in records:
 if not (r['help']['passed'] and r['invalid-invocation']['passed']):print(r['tool'],r['subcommands'],r['help'],r['invalid-invocation'])
raise SystemExit(0 if summary['passed'] else 1)
