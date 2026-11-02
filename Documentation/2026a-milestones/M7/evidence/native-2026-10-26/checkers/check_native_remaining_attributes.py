"""Read-only native FINAL14/16/18 evidence reconciliation. No UI or product run."""
import hashlib,importlib.util,json,re,shlex,struct
from pathlib import Path
from datetime import datetime,timezone
import pydicom
from pydicom.encaps import generate_frames
BASE=Path(__file__).resolve().parents[2];N=BASE/'work/m7/native-2026-10-26';UI=N/'ui-attributes';REPO=BASE/'work/DICOMKit-milestones'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
card=json.loads((N/'attribute-viewer-run-card.json').read_text());cases={r['id']:r for r in card['cases']};cli={r['id']:r for r in json.loads((N/'attribute-cli-oracles/execution.json').read_text())['records']}
spec=importlib.util.spec_from_file_location('codec',REPO/'Scripts/verify_m7_codecs.py');codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(codec)
checks={14:[],16:[],18:[]};observed={14:[],16:[],18:[]};reused=[]
def check(group,case,name,ok,detail=None):checks[group].append({'case':case,'assertion':name,'passed':bool(ok),**({'details':detail} if detail is not None else {})})
def semantic(argv):
 out={'tool':Path(argv[0]).name,'positional':[],'options':{}};i=1
 flags={'--dry-run','--strict','--no-clean-pixel-data','--allow-burned-in-phi'}
 while i<len(argv):
  if not argv[i].startswith('--'):out['positional'].append(argv[i]);i+=1;continue
  key=argv[i]
  if key in flags:value=True;i+=1
  else:value=argv[i+1];i+=2
  out['options'].setdefault(key,[]).append(value)
 if out['tool']=='dicom-anon':
  # These are actual documented CLI defaults, not dropped unknown arguments.
  out['options'].setdefault('--redact-style',['blank']);out['options'].setdefault('--redact-fill',['black'])
 return out
def console(text,c):
 lines=text.splitlines();found=[]
 for start,line in enumerate(lines):
  if not re.match(r'\s*\d+ text \$ ',line):continue
  try:matches=semantic(shlex.split(line.split(' text $ ',1)[1]))==semantic(c['CLI_argv'])
  except ValueError:matches=False
  if not matches:continue
  payload=[line.split(' text ',1)[1]]
  for line in lines[start+1:]:
   if re.match(r'^\t+\d+ ',line):break
   payload.append(line)
  found.append('\n'.join(payload).rstrip('\n'))
 return max(found,key=len)
def copied(path):return path.read_text().split('The focused UI element is ',1)[1].split('Value: ',1)[1].strip('\n')
def frame(ds):return next(generate_frames(ds.PixelData,number_of_frames=int(ds.get('NumberOfFrames',1))))
def compare_run(group,ident):
 c=cases[ident];r=cli[ident];before=UI/(ident+'-before.txt');after=UI/(ident+'-after.txt');b=before.read_text();a=after.read_text();cmd,outcome=console(a,c).split('\n',1);outcome=outcome.strip('\n')
 check(group,ident,'native status matches expected outcome','text Console '+c['expected'] in a)
 check(group,ident,'native actual argv equivalent to CLI including documented defaults',semantic(shlex.split(cmd[2:]))==semantic(c['CLI_argv']))
 expected=(Path(r['stdout']).read_text()+Path(r['stderr']).read_text()).replace(str(N/'attribute-cli-oracles/outputs'),str(N/'attributes-viewer-output')).strip('\n')
 check(group,ident,'complete current native console equals paired CLI payload',outcome==expected)
 # Script has a subcommand before the filename; template has no file operand.
 for arg in c['CLI_argv'][1:]:
  if arg in card['source_files']:check(group,ident,'source fixture unchanged',sha(arg)==card['source_files'][arg],arg)
 row={'id':ident,'type':'execution','status':c['expected'],'captured_argv':shlex.split(cmd[2:]),'evidence':{str(p):sha(p) for p in [before,after]},'full_console_compared':True}
 observed[group].append(row);return c,r,row,outcome
# FINAL14: five executions plus one preflight, never six executions.
for ident in json.loads((UI/'FINAL-14-native-actions.json').read_text())['executed']:
 c,r,row,outcome=compare_run(14,ident)
 if ident=='script-template':
  expected=Path(cli['script-template']['stdout']).read_text();check(14,ident,'generated native workflow template equals independently generated CLI text',outcome==expected.strip('\n'))
  check(14,ident,'template source subsequently validated is the same template',Path(cases['template-validate']['CLI_argv'][2]).read_text()==expected)
 elif ident=='template-dry-run':check(14,ident,'explicit no-execution outcome and no placeholder output','no commands were actually executed' in outcome and not Path('/path/to/output').exists())
 elif ident in ['unknown-conditional','conditional-pipeline']:check(14,ident,'nested syntax refusal before any log directory creation',not (N/'attributes-viewer-output/must-not-start').exists())
ident='script-live-disabled';p=UI/(ident+'-before.txt');s=p.read_text();cp=UI/(ident+'-copied-command.txt');cmd=copied(cp);argv=shlex.split(cmd);se=semantic(argv)
check(14,ident,'Run visibly disabled with explicit CLI-only guidance','button (disabled) Description: Run command, Help: Live script execution is unavailable in Workshop.' in s)
check(14,ident,'Dry Run off in live preflight','Description: Dry Run (required in Workshop), Value: 0' in s)
check(14,ident,'copied live command identifies exact read-only script without dry-run',se['positional']==cases[ident]['CLI_argv'][1:] and '--dry-run' not in se['options'])
check(14,ident,'configured live log absent before any execution',se['options'].get('--log')==[str(N/'attributes-viewer-output/must-not-start/live.log')] and not Path(se['options']['--log'][0]).exists())
check(14,ident,'existing console success is previous dry-run, not a new execution','no commands were actually executed' in s)
check(14,ident,'live script source remains unchanged',sha(cases[ident]['CLI_argv'][2])==card['source_files'][cases[ident]['CLI_argv'][2]])
observed[14].append({'id':ident,'type':'preflight_only','status':'Run disabled; no execution','evidence':{str(x):sha(x) for x in [p,cp]},'copied_argv':argv,'limit':'Old SUCCESS belongs to previous dry-run; not counted as live result. CLI counterpart intentionally supports live execution.'})
# FINAL16: two executions plus independent visible single-control retention observations.
for action in json.loads((UI/'FINAL-16-native-actions.json').read_text()):
 ident=action['id'];c,r,row,outcome=compare_run(16,ident);target=Path(c['ui_fields']['output']);b=(UI/(ident+'-before.txt')).read_text()
 controls=[x for x in b.splitlines() if re.match(r'\s*\d+ checkbox Description: Allow Burned-in PHI,',x)]
 check(16,ident,'exactly one visible PHI override control with intended state',len(controls)==1 and 'Value: '+('1' if ident=='phi-true' else '0') in controls[0])
 check(16,ident,'pixel cleaning explicitly disabled','checkbox Description: Clean Pixel Data, Value: 0' in b)
 if ident=='phi-false':check(16,ident,'refused metadata-only PHI request creates no output',not target.exists())
 else:
  ds=pydicom.dcmread(target);other=pydicom.dcmread(r['output']);src=pydicom.dcmread(c['CLI_argv'][1])
  check(16,ident,'PatientIdentityRemoved CS stays NO',ds['PatientIdentityRemoved'].VR=='CS' and str(ds.PatientIdentityRemoved)=='NO')
  check(16,ident,'uncleaned pixels remain identical to original and CLI',ds.PixelData==src.PixelData==other.PixelData)
  check(16,ident,'native file-meta and root identity synchronized',ds.SOPInstanceUID==ds.file_meta.MediaStorageSOPInstanceUID and ds.SOPClassUID==ds.file_meta.MediaStorageSOPClassUID)
  excluded={0x00080018,0x0020000D,0x0020000E};left={int(e.tag):(e.VR,str(e.value) if e.VR=='PN' else e.value) for e in ds if int(e.tag) not in excluded};right={int(e.tag):(e.VR,str(e.value) if e.VR=='PN' else e.value) for e in other if int(e.tag) not in excluded}
  check(16,ident,'entire dataset semantics equal CLI except exactly three generated identity UIDs',left==right)
  check(16,ident,'three anonymized identity UIDs are regenerated and syntactically valid',all(getattr(ds,n)!=getattr(src,n) and bool(re.fullmatch(r'[0-9]+(?:\.[0-9]+)*',str(getattr(ds,n)))) for n in ['SOPInstanceUID','StudyInstanceUID','SeriesInstanceUID']))
  row['output_sha256']=sha(target);row['semantic_comparison_exclusions']=['SOPInstanceUID','StudyInstanceUID','SeriesInstanceUID'];row['not_compared_as_bytes']='Generated UIDs intentionally differ between independent anonymization runs.'
cp=UI/'FINAL-16-copied-command.txt';argv=shlex.split(copied(cp));check(16,'copied-command','copied true override matches CLI and appears exactly once',semantic(argv)==semantic(cases['phi-true']['CLI_argv']) and argv.count('--allow-burned-in-phi')==1,{'path':str(cp),'sha256':sha(cp)})
for name in ['phi-retention-final-advanced.txt','phi-retention-final-beginner-expanded.txt']:
 p=UI/name;s=p.read_text();controls=[x for x in s.splitlines() if re.match(r'\s*\d+ checkbox Description: Allow Burned-in PHI,',x)]
 check(16,name,'mode change retains exactly one visible enabled binding',len(controls)==1 and 'Value: 1' in controls[0],{'path':str(p),'sha256':sha(p)})
 if 'beginner' in name:check(16,name,'Beginner advanced disclosure explicitly expanded','Description: Advanced options' in s and any('disclosure triangle Description: Advanced options' in x and 'Value: on' in x for x in s.splitlines()))
# FINAL18: six native conversions; expected codec refusals retain their classification.
for action in json.loads((UI/'FINAL-18-native-actions.json').read_text()):
 ident=action['id'];c,r,row,outcome=compare_run(18,ident);target=Path(c['ui_fields']['output'])
 if c['expected']=='ERROR':
  check(18,ident,'refused conversion leaves no output',not target.exists())
  row['codec_classification']='interoperability_limit' if ident=='strict-precision-refusal' else 'supported_refusal';row['counts_as_codec_success']=False
  phrase={'extended-rgb8':'needs 1 samples per pixel, but the source has 3','part2-refusal':'encoding is not supported','strict-precision-refusal':'JPEG header does not match DICOM dimensions, components or precision'}[ident]
  check(18,ident,'specific bounded refusal diagnostic retained',phrase in outcome)
  continue
 ds=pydicom.dcmread(target);other=pydicom.dcmread(r['output']);row['output_sha256']=sha(target)
 check(18,ident,'root/file-meta identities synchronized',ds.SOPInstanceUID==ds.file_meta.MediaStorageSOPInstanceUID and ds.SOPClassUID==ds.file_meta.MediaStorageSOPClassUID)
 if ident=='extended-gray8':
  h=codec.jpeg_header(frame(ds));check(18,ident,'bounded JPEG marker walk proves SOF1 precision8 48x64mono',h=={'marker':193,'precision':8,'rows':48,'columns':64,'components':1},h)
  check(18,ident,'native .51 codestream byte-identical to CLI codestream',str(ds.file_meta.TransferSyntaxUID)=='1.2.840.10008.1.2.4.51' and frame(ds)==frame(other))
  check(18,ident,'lossy new SOP instance UID differs from input and is synchronized',ds.SOPInstanceUID!=pydicom.dcmread(c['CLI_argv'][1]).SOPInstanceUID)
  left={int(e.tag):(e.VR,e.value) for e in ds if int(e.tag)!=0x00080018};right={int(e.tag):(e.VR,e.value) for e in other if int(e.tag)!=0x00080018};check(18,ident,'native dataset equals CLI except intentionally generated lossy instance UID',left==right)
  prior=BASE/'work/m7/codecs-qualified/forward-JPEGExtended-gray8';check(18,ident,'native exact stream equals already independently decoded qualified stream',frame(ds)==frame(pydicom.dcmread(prior/'encoded.dcm')))
  a=codec.samples(pydicom.dcmread(prior/'foreign-decoded.dcm'));b=codec.samples(pydicom.dcmread(prior/'self-decoded.dcm'));check(18,ident,'reused3072 decoder samples have maximum absolute difference1',len(a)==len(b)==3072 and max(abs(x-y) for x,y in zip(a,b))==1)
  reused.append({'native_case':ident,'proof':'Exact native/CLI/qualified encoded stream identity. Prior DCMTK vs own decoder maximum sample difference1; no new decoder campaign and no exact-original lossy claim.','qualified_path':str(prior),'native_frame_sha256':hashlib.sha256(frame(ds)).hexdigest()})
 elif ident=='native16':
  check(18,ident,'complete native16 file matches fresh CLI byte-for-byte',target.read_bytes()==Path(r['output']).read_bytes());codec.pixel_metadata(ds,'gray12',native=True,transfer_syntax='1.2.840.10008.1.2.1')
  check(18,ident,'OW16allocated/12stored exact6144byte3072sample output',ds['PixelData'].VR=='OW' and len(ds.PixelData)==6144 and codec.samples(ds)==codec.samples(pydicom.dcmread(BASE/'work/m7/codecs-qualified/fixtures/gray12.dcm')))
 elif ident=='native-odd':
  check(18,ident,'complete odd native file matches fresh CLI byte-for-byte',target.read_bytes()==Path(r['output']).read_bytes())
  check(18,ident,'OB3x3samples have exactly one final even-padding NUL',ds['PixelData'].VR=='OB' and (ds.Rows,ds.Columns,ds.BitsAllocated)==(3,3,8) and ds.PixelData.hex()=='00040803070b05090d00')
cp=UI/'FINAL-18-copied-command.txt';check(18,'copied-command','actual copied precision-refusal argv exactly matches CLI plan',semantic(shlex.split(copied(cp)))==semantic(cases['strict-precision-refusal']['CLI_argv']),{'path':str(cp),'sha256':sha(cp)})
for group in [14,16,18]:
 report={'recorded_utc':datetime.now(timezone.utc).isoformat(),'qualification_epoch':'final-qualified-native app-menu-rerun','identity':str(N/'final-qualified-native-equivalence.json'),'identity_sha256':sha(N/'final-qualified-native-equivalence.json'),'native_executions_observed':sum(x['type']=='execution' for x in observed[group]),'preflight_only_observations':sum(x['type']=='preflight_only' for x in observed[group]),'checks':checks[group],'passed':sum(x['passed'] for x in checks[group]),'failed':sum(not x['passed'] for x in checks[group]),'observed':observed[group],'completion':'All scoped subcases substantiated; parent final acceptance remains separate.','execution_boundary':'Read-only saved artifacts, AX/clipboard captures, source and file hashes. No native UI, product run or build by this checker.'}
 if group==14:report['limits']=['Only workflow template manually exercised; allfive template contracts remain covered by separate automated evidence.','Live refusal is a disabled preflight observation; prior SUCCESS belongs to dry-run. No live native execution asserted.']
 if group==16:report['limits']=['Earlier mode-B capture hid advanced options; it is not evidence of value loss. Final reexpanded Beginner and Advanced captures eachshow exactlyone enabledcontrol.','Generated identity UIDs differ intentionally; defined metadata/pixel semantics compared instead of whole-file bytes.'];report['CLI_default_normalization']={'redact-style':'blank','redact-fill':'black','source':'Sources/dicom-anon/DICOMAnon.swift:107-119 and Sources/DICOMKit/Anonymization/PixelCleaningWorkflow.swift:106-108'}
 if group==18:report['reused_independent_decode_proof']=reused;report['limits']=['Three successful outputs, two supported refusals, one strict-precision interoperability limit. Refusals nevercount ascodecpasses.','Lossy instance UID generated per run; exact codestream and otherdatasetmetadata compared. Independent decoder agreement bounded1, not exactoriginalsamples.']
 (N/f'native-FINAL-{group:02}-verification.json').write_text(json.dumps(report,indent=2,ensure_ascii=False,default=str)+'\n')
 print('FINAL',group,'executions',report['native_executions_observed'],'preflight',report['preflight_only_observations'],'checks',report['passed'],'passed',report['failed'],'failed')
 for x in checks[group]:
  if not x['passed']:print(x)
assert all(c['passed'] for cs in checks.values() for c in cs)
