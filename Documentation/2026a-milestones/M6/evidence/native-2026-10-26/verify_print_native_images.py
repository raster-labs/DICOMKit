#!/usr/bin/env python3
"""Read saved native print evidence; never launch products, peers, builds or UI."""
import datetime,json
from pathlib import Path
from PIL import Image
from verify_print_native_outputs import copied_console,digest,json_values,options
ROOT=Path(__file__).resolve().parent
CASES=['literal','raw12','rgb8','gray8','rle','jpeg','all-frames','frame2','frame2-control','three-files']

def raster(path):
 with Image.open(path) as im:
  im.load();rgba=im.convert('RGBA')
  return {'path':str(path),'size':list(im.size),'mode':im.mode,'rgbaSHA256':digest(rgba.tobytes()),'fileSHA256':digest(path.read_bytes())}

def main():
 checks=[];pending=[];cases=[];failure=[]
 def check(name,passed,detail):
  checks.append({'check':name,'status':'Passed' if passed else 'Failed','detail':detail})
  if not passed:failure.append(name)
 log=(ROOT/'cli-receiver.log').read_bytes();events=json_values(log.decode())
 films=[x for x in events if isinstance(x,dict) and 'filledImageBoxCount' in x]
 for n,name in enumerate(CASES,1):
  console=copied_console(ROOT/'ui'/('print-send-'+name+'-console.txt'))
  replies=[x for x in console['values'] if isinstance(x,dict) and 'printJobUID' in x]
  check(name+' successful native JSON',len(replies)==1 and replies[0].get('success') is True,{'source':console['source'],'sha256':console['sha256']})
  reply=replies[0];path=ROOT/'cli-received'/('native-%03d.png'%n);image=raster(path)
  expected=[288,360] if name=='rgb8' else [504,612]
  check(name+' decoded dimensions',image['size']==expected,image)
  film=next((x for x in films if x.get('printJobUID')==reply['printJobUID']),None)
  linked=False
  if film:
   position=events.index(film);writes=[]
   for event in events[position+1:]:
    if isinstance(event,dict) and 'filledImageBoxCount' in event:break
    message=event.get('message','') if isinstance(event,dict) else ''
    if message.startswith('Wrote '):writes.append(message[6:])
   linked=str(path) in writes
   check(name+' receiver job/file linkage',linked and all(film.get(k)==reply[k] for k in ['filmBoxUID','filmSessionUID','printJobUID']),{'written':writes,'jobUID':reply['printJobUID']})
   check(name+' receiver image count',film['filledImageBoxCount']==(3 if name in ['all-frames','three-files'] else 1),film['filledImageBoxCount'])
  else:pending.append(name+': PNG and successful native result exist; receiver has not flushed a complete film JSON for UID linkage')
  cases.append({'name':name,'native':console,'result':reply,'raster':image,'receiverFilm':film,'receiverLinked':linked})
 byname={x['name']:x for x in cases}
 def equal(a,b):return byname[a]['raster']['size']==byname[b]['raster']['size'] and byname[a]['raster']['rgbaSHA256']==byname[b]['raster']['rgbaSHA256']
 for a,b in [('gray8','rle'),('gray8','jpeg'),('all-frames','three-files'),('frame2','frame2-control')]:check(a+' equals '+b,equal(a,b),'Decoded RGBA dimensions and all pixels equal')
 check('frame2 differs from frame1',not equal('frame2','gray8'),'Selected second frame is not silently replaced by the first frame')
 check('raw12 fixture render equals raw8 fixture render',equal('raw12','gray8'),'Fixture-specific same-ramp output comparison, not proof of preserving 12-bit film pixels; PNG is8-bit')
 old=ROOT.parent/'workshop-images-qualified/results.json';history=json.loads(old.read_text());baselines={'gray8':'native','rle':'rle','jpeg':'jpeg','all-frames':'all-frames','three-files':'three-files','frame2':'selected-frame2','frame2-control':'single-frame2'}
 for name,baseline in baselines.items():
  artifact=history['artifacts']['cli'][baseline];actual=raster(Path(artifact['path']));current=byname[name]['raster']
  check(name+' matches final automated CLI baseline',actual['rgbaSHA256']==artifact['sha256']==current['rgbaSHA256'] and actual['size']==current['size'],{'baseline':actual,'record':str(old),'scope':'Reused unchanged-source control; exact fresh native-argv CLI replay remains distinct'})
 dry_path=ROOT/'ui/print-send-dry-run-console.txt';dry=copied_console(dry_path);raw=dry_path.read_text()
 check('native dryrun complete with unreachable endpoint',options(dry['argv']).get('--dry-run')==[True] and 'pacs://127.0.0.1:1' in dry['argv'] and 'Dry run complete. Use without --dry-run to print files.' in raw,'Captured success text; no network route needed')
 existing=sorted(str(x) for x in (ROOT/'cli-received').glob('*.png'))
 check('post-native-dryrun snapshot has exactly10 films',len(existing)==10,{'files':existing,'scope':'Snapshot before replay controls; receiver is active. No per-action event timing claim beyond saved evidence.'})
 manifest=json.loads((ROOT/'print-fixture-manifest.json').read_text())
 check('13 original and native fixture copies unchanged',len(manifest)==13 and all(digest(Path(x['source']).read_bytes())==x['sha256']==digest(Path(x['copy']).read_bytes()) for x in manifest.values()),{'manifest':str(ROOT/'print-fixture-manifest.json'),'count':len(manifest)})
 pending.extend(['Exact fresh CLI replay of the ten native send argv vectors and job query is prepared but unexecuted by this verifier.','No earlier RGB film exists with the same template/options; require the prepared exact CLI replay.','Registry persistence/remove, PrintSCP command actions and other native checklist requirements remain separately pending. No native checklist group is marked complete.'])
 out={'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Failed' if failure else 'Partial — recorded image checks pass; native acceptance remains open','completedChecklistGroups':0,'checks':checks,'failures':failure,'pending':pending,'cases':cases,'dryrun':dry,'receiverSnapshot':{'sha256':digest(log),'bytes':len(log),'completeFilmRecords':len(films)},'scope':'Read-only independent decoded image verification; no product/UI/peer/build execution. Receiver may buffer final JSON until further writes or stop.'}
 (ROOT/'print-native-image-verification.json').write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n')
 print(json.dumps({'passed':sum(x['status']=='Passed' for x in checks),'failed':failure,'pending':pending,'completeReceiverFilms':len(films)},indent=2))
 return bool(failure)
if __name__=='__main__':raise SystemExit(main())
