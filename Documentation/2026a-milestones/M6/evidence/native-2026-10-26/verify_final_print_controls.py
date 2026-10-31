#!/usr/bin/env python3
"""Saved-evidence verifier. Products were run only by the separately authorized replay."""
from pathlib import Path
import json,datetime,re,shlex
from verify_print_native_outputs import copied_console,digest,json_values,options
from verify_print_cli_replays import console_body
from verify_print_native_images import raster
R=Path(__file__).resolve().parent;D=R/'cli-final-controls';U=R/'ui-repaired';checks=[]
def check(name,ok,detail):checks.append({'check':name,'status':'Passed' if ok else 'Failed','detail':detail})
records={};native={}
for name in ['final-status-text-console','final-job-text-console','final-row-order-console']:
 c=copied_console(U/(name+'.txt'));result=json.loads((D/(name+'-cli.json')).read_text());native[name]=c;records[name]=result
 check(name+' exact command/exit',result['argv'][1:]==c['argv'][1:] and result['returncode']==0 and not result['timedOut'] and result['nativeSHA256']==c['sha256'],{'native':c['argv'],'CLI':result['argv'],'exit':result['returncode'],'binarySHA256':result['binarySHA256']})
 if name!='final-row-order-console':check(name+' exact text',result['stdout']=='' and result['stderr'].removesuffix('\n')==console_body(U/(name+'.txt')),{'native':console_body(U/(name+'.txt')),'CLIstdout':result['stdout'],'CLIstderr':result['stderr'],'normalization':'Only one terminal LF; status/job text is diagnostic stderr in shared CLI, merged native console in Workshop'})
submission=native['final-row-order-console']['values'][0];cli_submission=json.loads(records['final-row-order-console']['stdout']);keys={'filmBoxUID','filmSessionUID','printJobUID','success'}
check('row send complete result schema',set(submission)==set(cli_submission)==keys and submission['success'] is cli_submission['success'] is True,{'native':submission,'CLI':cli_submission})
check('job uses actual native announced UID',options(native['final-job-text-console']['argv']).get('--job-id')==[submission['printJobUID']] and submission['printJobUID'] in records['final-job-text-console']['stderr'],'Same actual native job queried, no timestamp/date or UID normalization')
before=(U/'final-row-order-before.txt').read_text();after=(U/'final-row-order-after.txt').read_text()
check('initial visible file and annotation order',re.search(r'Description: DICOM Files or Directories entry 1[^\n]*Value: [^\n]*frame1.dcm',before) is not None and re.search(r'Description: DICOM Files or Directories entry 2[^\n]*Value: [^\n]*frame2.dcm',before) is not None and 'Description: Annotations entry 1, Value: first' in before and 'Description: Annotations entry 2, Value: second' in before,'Initial native AX shows frame1/frame2 and first/second')
check('reversed visible annotation rows','Description: Annotations entry 1, Value: second' in after and 'Description: Annotations entry 2, Value: first' in after,'Actual after-edit AX captures second/first. File rows were above current scroll viewport; their final order is verified through copied command and actual execution.')
command_raw=(U/'final-row-order-command.txt').read_text();command=command_raw.split('Description: Print command to import, Value: ',1)[1].split('\n',1)[0];argv=shlex.split(command);parsed=options(argv)
check('copied reversed rows equal actual invocation',argv==native['final-row-order-console']['argv'] and parsed['positionals'][1:]==[str(R/'print-fixtures/frame2.dcm'),str(R/'print-fixtures/frame1.dcm')] and parsed['--annotate']==['second','first'],'Literal argv confirms both final file and annotation order; no shell evaluation')
events=json_values((D/'receiver.log').read_text());films=[x for x in events if isinstance(x,dict) and 'filledImageBoxCount'in x];nf=next(x for x in films if x['printJobUID']==submission['printJobUID']);cf=next(x for x in films if x['printJobUID']==cli_submission['printJobUID']);ignored={'filmBoxUID','filmSessionUID','printJobUID','receivedAt'}
check('native/CLI complete receiver film parity',{k:v for k,v in nf.items() if k not in ignored}=={k:v for k,v in cf.items() if k not in ignored},{'native':nf,'CLI':cf,'excluded':sorted(ignored)})
check('reversed receiver annotations and counts',nf['annotations']==['1: second','2: first'] and nf['filledImageBoxCount']==2 and nf['imageBoxCount']==2,{'annotations':nf['annotations'],'filled':nf['filledImageBoxCount'],'boxes':nf['imageBoxCount']})
for f,n in [(nf,1),(cf,2)]:
 writes=[]
 for e in events[events.index(f)+1:]:
  if isinstance(e,dict) and 'filledImageBoxCount'in e:break
  m=e.get('message','') if isinstance(e,dict) else ''
  if m.startswith('Wrote '):writes.append(m[6:])
 check('actual job links final-%03d.png'%n,str(D/('final-%03d.png'%n)) in writes,{'UID':f['printJobUID'],'writes':writes})
a=raster(D/'final-001.png');b=raster(D/'final-002.png');check('native/CLI film decoded pixels',a['size']==b['size']==[504,612] and a['rgbaSHA256']==b['rgbaSHA256'],{'native':a,'CLI':b});check('native/CLI film exact file bytes',a['fileSHA256']==b['fileSHA256'],'PNG files are also byte-identical, beyond required decoded pixel equality')
check('receiver stopped drained counters',any(isinstance(x,dict) and x.get('message')=='Stopped — 6 associations, 2 films, 0 errors (interrupted)' for x in events),'Parent-owned graceful stop completed after authorized three CLI operations')
# Distinct inaccessible directory outcome: exact simulate replay with same 0500 target.
cn=copied_console(U/'denied-output-console.txt');cr=json.loads((D/'denied-output-cli.json').read_text());nv=next(x for x in cn['values'] if isinstance(x,dict) and 'filledImageBoxCount'in x);cv=json.loads(cr['stdout']);nb=console_body(U/'denied-output-console.txt')
check('denied output exact argv/exit',cr['argv'][1:]==cn['argv'][1:] and cr['returncode']==0 and not cr['timedOut'],{'argv':cr['argv'],'exit':cr['returncode'],'contract':'Nonessential sink failure is reported; film composition survives with exit0'})
check('denied output complete film parity',{k:v for k,v in nv.items() if k not in ignored}=={k:v for k,v in cv.items() if k not in ignored},{'native':nv,'CLI':cv,'excluded':sorted(ignored)})
check('denied output warning parity and no saved claim',cr['stderr'].removesuffix('\n')==nb.split('\n',1)[0] and 'Output failed (png):' in cr['stderr'] and 'Wrote ' not in cr['stdout']+cr['stderr']+nb,{'nativeWarning':nb.split('\n',1)[0],'CLIstderr':cr['stderr']})
check('denied output remained0500 and empty during replay',cr['modeBefore']==cr['modeAfter']=='0o500' and cr['filesBefore']==cr['filesAfter']==[],{'beforeMode':cr['modeBefore'],'afterMode':cr['modeAfter'],'before':cr['filesBefore'],'after':cr['filesAfter'],'note':'Parent may subsequently restore0700; recorded before/after evidence is authoritative for this operation'})
# Two further authorized output-directory controls.
invalid_native=copied_console(U/'output-is-file-console.txt');invalid_cli=json.loads((D/'output-is-file-console-cli.json').read_text());invalid_body=console_body(U/'output-is-file-console.txt')
check('file-as-directory exact argv and refusal',invalid_cli['argv'][1:]==invalid_native['argv'][1:] and invalid_cli['returncode']==1 and not invalid_cli['timedOut'] and invalid_cli['stdout']=='',{'argv':invalid_cli['argv'],'exit':invalid_cli['returncode']})
reason=invalid_cli['stderr'].removeprefix('Error: ').removesuffix('\n')
check('file-as-directory equivalent cause',reason in invalid_body and 'NSCocoaErrorDomain Code=516' in invalid_body and 'NSPOSIXErrorDomain Code=17' in invalid_body and 'Wrote ' not in invalid_body+invalid_cli['stdout']+invalid_cli['stderr'],{'native':invalid_body,'CLI':invalid_cli['stderr'],'scope':'Native prints NSError description including code/path; CLI prints localized reason. Equivalent file-exists cause, not byte-identical wrappers.'})
check('file-as-directory original remains a file',(R/'sink-is-file').is_file(),'No replacement of original synthetic file with a folder')
child_native=copied_console(U/'new-output-child-console.txt');child_cli=json.loads((D/'new-output-child-console-cli.json').read_text());expected_argv=child_native['argv'][:];expected_argv[0]=child_cli['argv'][0];expected_argv[expected_argv.index('--output-dir')+1]=str(R/'cli-new-output-child')
check('new child exact argv apart from isolated output',child_cli['argv']==expected_argv and child_cli['returncode']==0 and not child_cli['timedOut'],{'mapping':child_cli['explicitOutputPathMapping'],'argv':child_cli['argv']})
nfilm=child_native['values'][0];cfilm=json.loads(child_cli['stdout']);check('new child complete film fields',{k:v for k,v in nfilm.items() if k not in ignored}=={k:v for k,v in cfilm.items() if k not in ignored},{'native':nfilm,'CLI':cfilm,'excluded':sorted(ignored)})
nfiles=list((R/'new-output-child').glob('*.png'));cfiles=list((R/'cli-new-output-child').glob('*.png'));check('new child produces onePNG per isolated folder',len(nfiles)==len(cfiles)==1,{'native':[str(p) for p in nfiles],'CLI':[str(p) for p in cfiles]})
np=raster(nfiles[0]);cp=raster(cfiles[0]);check('new child native/CLI decoded pixel parity',np['size']==cp['size']==[504,612] and np['rgbaSHA256']==cp['rgbaSHA256'],{'native':np,'CLI':cp})
from zoneinfo import ZoneInfo
for label,file,film in [('native',nfiles[0],nfilm),('CLI',cfiles[0],cfilm)]:
 stamp=datetime.datetime.fromisoformat(film['receivedAt'].replace('Z','+00:00')).astimezone(ZoneInfo('Asia/Kolkata')).strftime('%Y%m%d-%H%M%S')
 check(label+' filename timestamp/index substitution',file.name=='created-'+stamp+'-001.png',{'file':file.name,'receivedAt':film['receivedAt'],'hostTimeZone':'Asia/Kolkata','pattern':'created-{timestamp}-{index}'})
restored=json.loads((D/'denied-output-restored.json').read_text());check('denied folder permissions restored by authorization',restored['modeBefore']=='0o500' and restored['modeAfter']=='0o700' and restored['filesBefore']==restored['filesAfter']==[] and (R/'denied-output').stat().st_mode&0o777==0o700,restored)
manifest=json.loads((R/'print-fixture-manifest.json').read_text());check('all13 fixture sources/copies unchanged',len(manifest)==13 and all(digest(Path(x['source']).read_bytes())==x['sha256']==digest(Path(x['copy']).read_bytes()) for x in manifest.values()),{'count':len(manifest)})
initial=U/'final-job-text-invalid-oracle.txt';check('initial incorrect positional job oracle preserved',initial.exists() and '--job-id' not in initial.read_text().split('Value: ',1)[1].split('\n',1)[0],{'path':str(initial),'sha256':digest(initial.read_bytes()),'classification':'Initial Import used incorrect positional job syntax; correct invocation explicitly supplies --job-id. Not a product failure.'})
failed=[x['check'] for x in checks if x['status']=='Failed'];report={'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Passed' if not failed else 'Failed','checks':checks,'failures':failed,'nativeSourceScope':'Captured current ui-repaired actions; artifact identity belongs to parent manifests. No milestone/group completion implied.','authorizedProductInvocations':{'dicom-print':3,'dicom-printscp':3,'newPeers':0,'UI':0,'builds':0,'productEdits':0},'receiverSnapshotSHA256':digest((D/'receiver.log').read_bytes()),'remainingScope':'Final checkbox layout/typed-output repair and other FINAL groups remain separate.'}
(R/'final-print-controls-verification.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'passed':len(checks)-len(failed),'failed':failed},indent=2));raise SystemExit(bool(failed))
