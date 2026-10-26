#!/usr/bin/env python3
"""Read saved native evidence only; no product/network/UI/settings access.
Exit 1 means a detected mismatch; exit 0 may still be Partial because native
coverage is deliberately tracked separately from recorded comparisons.
"""
import argparse,datetime,hashlib,json,re,shlex
from pathlib import Path
from PIL import Image

def digest(data):return hashlib.sha256(data).hexdigest()
def load(path):return json.loads(path.read_text())
def json_values(text):
 decoder=json.JSONDecoder();values=[];position=0
 while True:
  match=re.search(r'(?m)^\s*[\[{]',text[position:])
  if match is None:break
  start=position+match.start()
  while text[start].isspace():start+=1
  try:value,end=decoder.raw_decode(text,start)
  except json.JSONDecodeError:
   position=start+1;continue
  values.append(value);position=end
 return values

def copied_console(path):
 raw=path.read_text()
 marker='Description: Print command to import, Value: '
 occurrences=[m.end() for m in re.finditer(re.escape(marker),raw)]
 candidates=[]
 for start in occurrences:
  payload=re.split(r'\n\t+\d+ ',raw[start:],maxsplit=1)[0].strip()
  if not payload.startswith('$ dicom-'):continue
  first,_,body=payload.partition('\n')
  candidates.append({'command':first[2:],'argv':shlex.split(first[2:]),'values':json_values(body)})
 if not candidates:raise ValueError('No complete copied-console envelope')
 if any(c!=candidates[0] for c in candidates):raise ValueError('Repeated AX focused payloads disagree')
 return dict(candidates[0],duplicate_envelopes=len(candidates),source=str(path),sha256=digest(path.read_bytes()))

def options(argv):
 out={};i=2
 while i<len(argv):
  token=argv[i]
  if token=='--':out['positionals']=argv[i+1:];break
  if token.startswith('--'):
   key,sep,value=token.partition('=')
   if not sep:
    if i+1<len(argv) and not argv[i+1].startswith('--'):value=argv[i+1];i+=1
    else:value=True
   out.setdefault(key,[]).append(value)
  i+=1
 return out

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parent)
 parser.add_argument('--output',type=Path);args=parser.parse_args();root=args.root.resolve();ui=root/'ui';results=root/'cli-results'
 failures=[];pending=[];checks=[];evidence={};consoles={}
 def record(name,ok,detail,source=None):
  row={'check':name,'result':'Passed' if ok else 'Failed','detail':detail}
  if source is not None:row['source']=str(source)
  checks.append(row)
  if not ok:failures.append(name)
 for file in sorted(ui.glob('*console.txt')):
  try:consoles[file.stem]=copied_console(file)
  except Exception as exc:failures.append(file.name+': '+str(exc))
 for name,value in consoles.items():evidence[name]=value
 # Screenshots were read by the independent reviewer; never call this OCR or
 # machine extraction. Refuse to reuse the transcription if its image changed.
 transcriptions=load(root/'print-screenshot-transcriptions.json')
 for entry in transcriptions:
  image_path=root/entry['image'];same=digest(image_path.read_bytes())==entry['sha256']
  record(entry['name']+' screenshot identity',same,'Manual visual transcription applies only to the reviewed screenshot.',image_path)
  cli=load(results/entry['cli_control']);payload=json.loads(cli['stdout'])
  record(entry['name']+' schema/value parity',same and cli['returncode']==0 and entry['payload']==payload,
         {'basis':'Manual screenshot transcription vs complete independent-settings/live-peer CLI JSON','native':entry['payload'],'cli':payload},image_path)
  # Prefer later full copied console if root captures it; screenshot-only still
  # remains valid explicitly scoped evidence, not a native JSON text artifact.
  aliases=entry['console_aliases'];native=next((consoles[n] for n in aliases if n in consoles),None)
  if native:
   record(entry['name']+' full copied-console parity',payload in native['values'], 'Exact native JSON schema and values equal CLI.',native['source'])
  else:pending.append(entry['name']+': screenshot parity established; no full copied JSON text retained yet')
 forbidden=load(results/'app-list-after-add.json')
 record('same-registry permission boundary retained',forbidden['returncode']!=0 and 'permission' in forbidden['stderr'].lower(),
        'OS-denied app registry access is not treated as a registry pass; no access bypass. Alternative isolated CLI fixture comparison above.')
 fixture_results=[]
 for name,entry in load(root/'print-fixture-manifest.json').items():
  source=Path(entry['source']);copy=Path(entry['copy']);ok=digest(source.read_bytes())==entry['sha256']==digest(copy.read_bytes())
  fixture_results.append({'name':name,'unchanged':ok,'sha256':entry['sha256']})
 record('all synthetic source and copy fixtures unchanged',all(x['unchanged'] for x in fixture_results),{'files':len(fixture_results)})
 send=consoles.get('print-send-literal-console');job=consoles.get('print-job-console');current_job=None
 if send:
  payload=next((x for x in send['values'] if isinstance(x,dict) and 'printJobUID'in x),None)
  record('native literal send successful JSON',payload is not None and payload.get('success') is True,'Complete copied console, with actual generated UIDs.',send['source'])
  if payload:
   current_job=payload['printJobUID'];argv=options(send['argv'])
   expected={'--layout':['ROW\\1,3'],'--window-center':['-600'],'--window-width':['1200'],'--copies':['2'],
             '--annotate':[' first; literal note ',"O'Neil second"],'--presentation-lut':['IDENTITY']}
   record('native literal argument preservation',all(argv.get(k)==v for k,v in expected.items()) and
          argv.get('positionals',[])[-1:]==[str(root/'print-fixtures'/"literal O'Neil; snow 雪.dcm")],
          {'expected':expected,'parsed':argv})
   log_data=(root/'cli-receiver.log').read_bytes();received=json_values(log_data.decode())
   film=next((x for x in received if isinstance(x,dict) and x.get('printJobUID')==current_job and 'filledImageBoxCount'in x),None)
   expected_film={'filmBoxUID':payload['filmBoxUID'],'filmSessionUID':payload['filmSessionUID'],'filledImageBoxCount':1,'imageBoxCount':4,
    'imageDisplayFormat':'ROW\\1,3','rows':2,'columns':3,'numberOfCopies':2,'mediumType':'CLEAR FILM','filmSize':'14INX17IN','presentationLUTShape':'IDENTITY','callingAETitle':'M7NATIVE'}
   record('receiver matches native send identifiers and film fields',film is not None and all(film.get(k)==v for k,v in expected_film.items()),{'expected':expected_film,'actual':film})
   evidence['receiver_log_snapshot']={'sha256':digest(log_data),'bytes':len(log_data),'note':'Active receiver; complete JSON values parsed, incomplete trailing write ignored. No process interaction.'}
   if film:
    film_index=received.index(film);writes=[]
    for event in received[film_index+1:]:
     if isinstance(event,dict) and 'filledImageBoxCount'in event:break
     message=event.get('message','') if isinstance(event,dict) else ''
     if message.startswith('Wrote '):writes.append(Path(message[6:]))
    raster=[]
    for path in writes:
     if path.suffix.lower()!='.png':continue
     with Image.open(path) as image:
      image.load();rgba=image.convert('RGBA');raster.append({'path':str(path),'size':list(rgba.size),'rgbaSHA256':digest(rgba.tobytes()),'fileSHA256':digest(path.read_bytes())})
    record('native literal send saved PNG',len(raster)==1 and raster[0]['size']==[504,612],raster)
    evidence['native_send_rasters']=raster
    pending.append('Literal send PNG is decoded and linked to the actual native job; pixel equality with an equivalent new CLI send is not yet established unless its separate control/output is added.')
    evidence['annotation_scope']='Copied argv preserves both outer spaces. Receiver presentation strings trim them; this display is not exact wire-byte evidence. Use independent DIMSE capture for a wire-preservation claim.'
   if (results/'send-literal.json').exists():
    ctrl=load(results/'send-literal.json');value=json.loads(ctrl['stdout']);keys={'filmBoxUID','filmSessionUID','printJobUID','success'}
    record('literal send CLI result schema',ctrl['returncode']==0 and set(value)==set(payload)==keys and value['success'] is True,'UID values are intentionally per-request and must not be compared equal.')
 else:pending.append('No full native literal-send console available')
 if job and current_job:
  payload=next((x for x in job['values'] if isinstance(x,dict) and 'jobUID'in x),None)
  record('native job query refers to actual native submission',payload is not None and payload.get('jobUID')==current_job and
         payload.get('ExecutionStatus')=='DONE' and payload.get('ExecutionStatusInfo')=='NORMAL' and
         options(job['argv']).get('--job-id')==[current_job],payload,job['source'])
  controls=[results/'job.json',results/'job-control.json']
  control=next((x for x in controls if x.exists()),None)
  if control:
   cli=load(control);record('job exact CLI schema/value parity',cli['returncode']==0 and json.loads(cli['stdout'])==payload,'Same actual retained job, so all fields must match exactly.',control)
  else:pending.append('Actual job status DONE is captured; no equivalent CLI job JSON file yet')
 no_change=[]
 for path in sorted(ui.glob('*.txt')):
  if path.read_text().startswith('There has been no change in the accessibility tree'):no_change.append(path.name)
 evidence['no_change_AX_files']=no_change
 pending.extend(['Duplicate-add refusal is not established by print-add-duplicate.txt alone (no-change AX); retain screenshot or full console.',
                 'Text-mode list/status outputs are not established by their no-change AX files.',
                 'Registry relaunch persistence/removal and remaining print matrix actions require their own final native evidence.'])
 if current_job:(root/'current-native-print-job.json').write_text(json.dumps({'jobUID':current_job,'source':str(ui/'print-send-literal-console.txt'),'status':'Observed actual native submission'},indent=2)+'\n')
 out={'schema_version':1,'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Failed' if failures else 'Partial — recorded comparisons pass; native matrix remains open','checks':checks,'failures':failures,'pending':pending,'fixture_results':fixture_results,'evidence':evidence,
      'limits':['Read-only saved-evidence verification; no product, peer, UI, build or protected-registry access.','Screenshot comparisons are explicitly manual transcriptions tied to image hashes.','No-change AX snapshots are not outcome evidence; overlapping evidence is not additive.']}
 target=args.output or root/'print-native-output-verification.json';target.write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n')
 print(json.dumps({'status':out['status'],'passed_checks':sum(c['result']=='Passed' for c in checks),'failed':failures,'pending_count':len(pending),'jobUID':current_job},indent=2))
 return 1 if failures else 0
if __name__=='__main__':raise SystemExit(main())
