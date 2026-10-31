#!/usr/bin/env python3
"""Compare saved native and parent-operated CLI replay evidence, read-only."""
import datetime,json,re
from pathlib import Path
from PIL import Image
from verify_print_native_outputs import copied_console,digest,json_values
ROOT=Path(__file__).resolve().parent

def raster(path):
 with Image.open(path) as im:
  im.load();rgba=im.convert('RGBA');return {'size':list(im.size),'rgbaSHA256':digest(rgba.tobytes()),'fileSHA256':digest(path.read_bytes())}

def console_body(path):
 raw=path.read_text();marker='Description: Print command to import, Value: ';start=raw.index(marker)+len(marker)
 return re.split(r'\n\t+\d+ ',raw[start:],maxsplit=1)[0].partition('\n')[2].strip()

def main():
 plan=json.loads((ROOT/'print-cli-replay-plan.json').read_text());events=json_values((ROOT/'cli-receiver.log').read_text());checks=[];pending=[];records=[]
 def check(name,ok,detail):checks.append({'check':name,'status':'Passed' if ok else 'Failed','detail':detail})
 def film_for(uid):
  film=next((x for x in events if isinstance(x,dict) and x.get('printJobUID')==uid and 'filledImageBoxCount' in x),None)
  if film is None:return None,[]
  written=[]
  for event in events[events.index(film)+1:]:
   if isinstance(event,dict) and 'filledImageBoxCount' in event:break
   message=event.get('message','') if isinstance(event,dict) else ''
   if message.startswith('Wrote '):written.append(message[6:])
  return film,written
 for case in plan['cases']:
  target=Path(case['resultFile']);name=case['name']
  if not target.exists():pending.append(name+': CLI replay result missing');continue
  result=json.loads(target.read_text());native=copied_console(Path(case['nativeConsole']))
  check(name+' exact argv',result['argv']==case['argv'] and result['argv'][1:]==native['argv'][1:],'Only executable resolved to frozen final binary; remaining literal tokens identical')
  check(name+' exit and bounded completion',result['returncode']==0 and not result['timedOut'],{'exit':result['returncode'],'timedOut':result['timedOut']})
  check(name+' film counter delta',result['filmCountAfter']-result['filmCountBefore']==case['expectedFilmDelta'],{'before':result['filmCountBefore'],'after':result['filmCountAfter']})
  check(name+' frozen binary',result['binarySHA256']==plan['binarySHA256'],'SHA256 preserved in parent-operated result')
  if name=='dry-run':
   check(name+' complete diagnostic text parity',result['stdout']=='' and result['stderr'].removesuffix('\n')==console_body(Path(case['nativeConsole'])),{'stdout':result['stdout'],'stderr':result['stderr'],'basis':'Shared SCUCommands.execute assigns fprintln=context.diagnostic and sends the entire dryrun text through it. Process context writes diagnostic lines to stderr; Workshop routes both diagnostic and output lines into its one console. Only the final CLI line-terminator LF is removed for copied-console comparison. No text or behavioral field is normalized.','sourceReferences':['Sources/DICOMPrintCommandSupport/SCUCommands.swift:386','Sources/DICOMPrintCommandSupport/SCUCommands.swift:445','Sources/DICOMPrintCommandSupport/SCUCommands.swift:458','Sources/DICOMPrintCommandSupport/SCUCommands.swift:468','Sources/DICOMPrintCommandSupport/PrintCommandContext.swift:47','Sources/DICOMStudio/ViewModels/CLIWorkshopPrintExecution.swift:100']});continue
  try:payload=json.loads(result['stdout'])
  except Exception as exc:check(name+' JSON parse',False,str(exc));continue
  if name=='job':
   expected=next(x for x in native['values'] if isinstance(x,dict) and 'jobUID'in x)
   check(name+' complete schema/value parity',payload==expected,{'native':expected,'cli':payload});continue
  expected=next(x for x in native['values'] if isinstance(x,dict) and 'printJobUID'in x)
  ignored={'filmBoxUID','filmSessionUID','printJobUID'}
  check(name+' result schema and nonvolatile values',set(payload)==set(expected) and {k:v for k,v in payload.items() if k not in ignored}=={k:v for k,v in expected.items() if k not in ignored},{'native':expected,'cli':payload})
  check(name+' generated identifiers differ',all(payload.get(k)!=expected.get(k) for k in ignored),'Independent submissions must generate fresh identifiers')
  native_film,native_paths=film_for(expected['printJobUID']);cli_film,cli_paths=film_for(payload['printJobUID'])
  if native_film is None or cli_film is None:
   pending.append(name+': receiver film JSON still unflushed; repeat read-only verifier after parent-controlled flush/stop')
  else:
   skipped=ignored|{'receivedAt'}
   check(name+' complete receiver film parity',{k:v for k,v in native_film.items() if k not in skipped}=={k:v for k,v in cli_film.items() if k not in skipped},{'native':native_film,'cli':cli_film,'excluded':sorted(skipped)})
   check(name+' actual job-to-file linkage',case['nativePNG'] in native_paths and case['predictedCLIOutputPNG'] in cli_paths,{'native':native_paths,'cli':cli_paths})
  npath=Path(case['nativePNG']);cpath=Path(case['predictedCLIOutputPNG'])
  if not cpath.exists():pending.append(name+': predicted CLI PNG is absent');continue
  nr=raster(npath);cr=raster(cpath)
  check(name+' decoded pixel parity',nr['size']==cr['size'] and nr['rgbaSHA256']==cr['rgbaSHA256'],{'native':dict(nr,path=str(npath)),'cli':dict(cr,path=str(cpath)),'scope':'PNG decode and dimension equality; actualUID/linkage checked separately'})
  records.append({'name':name,'nativeJobUID':expected['printJobUID'],'cliJobUID':payload['printJobUID'],'nativePNG':str(npath),'cliPNG':str(cpath)})
 failures=[x['check'] for x in checks if x['status']=='Failed']
 out={'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Failed' if failures else ('Partial' if pending else 'Passed — exact saved native/CLI comparisons only'),'completedNativeChecklistGroups':0,'checks':checks,'failures':failures,'pending':pending,'records':records,'scope':'Read-only saved comparisons. Broader native print acceptance remains with parent checklist; no product/UI/peer/build launched by verifier.'}
 (ROOT/'print-native-cli-parity.json').write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'status':out['status'],'passed':len(checks)-len(failures),'failures':failures,'pending':pending},indent=2));return bool(failures)
if __name__=='__main__':raise SystemExit(main())
