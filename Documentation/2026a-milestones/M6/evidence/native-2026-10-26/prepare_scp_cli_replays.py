#!/usr/bin/env python3
"""Prepare isolated work files and argv plans only; never execute a product."""
import datetime,json,re,shlex
from pathlib import Path
from verify_print_native_outputs import copied_console,digest
R=Path(__file__).resolve().parent
B=Path('/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-printscp')
C=R/'cli-scp-replay-config';C.mkdir(exist_ok=False)
base=(R/'config/baseline-scp.json').read_bytes()
for name in ['baseline-scp.json','saved-scp.json','simulation-save.json']:(C/name).write_bytes(base)
for name in ['cli-simulated-replay','cli-sink-failure-replay']:(R/name).mkdir(exist_ok=False)
(R/'cli-sink-failure-replay/native-001.png').mkdir()
paths={str(R/'config'):str(C),str(R/'gui-simulated'):str(R/'cli-simulated-replay'),str(R/'sink-failure'):str(R/'cli-sink-failure-replay')}
names=['status-inherit','status-enabled','save-config','status-reloaded','queues','save-before-gather','simulate','sink-failure']
cases=[]
for name in names:
 p=R/'ui'/('scp-'+name+'-console.txt');native=copied_console(p);argv=native['argv'][:];argv[0]=str(B);replacements=[]
 for i,token in enumerate(argv):
  for before,after in paths.items():
   if token==before or token.startswith(before+'/'):
    argv[i]=after+token[len(before):];replacements.append({'index':i,'native':token,'cli':argv[i]});break
 cases.append({'name':name,'argv':argv,'nativeCommand':native['command'],'nativeConsole':str(p),'nativeConsoleSHA256':digest(p.read_bytes()),'replacements':replacements,'expectedExitCode':0,'timeoutSeconds':60,'resultFile':str(R/'cli-results/scp-replay-v1'/(name+'.json'))})
p=R/'ui/scp-paper-gate-import.txt';raw=p.read_text();marker='Description: Print command to import, Value: ';command=re.split(r'\n\t+\d+ ',raw.split(marker,1)[1],maxsplit=1)[0];argv=shlex.split(command);argv[0]=str(B);argv[argv.index('--config')+1]=str(C/'baseline-scp.json')
cases.append({'name':'paper-import-refusal','argv':argv,'nativeCommand':command,'nativeConsole':str(p),'nativeConsoleSHA256':digest(p.read_bytes()),'expectedExitCode':64,'timeoutSeconds':30,'resultFile':str(R/'cli-results/scp-replay-v1/paper-import-refusal.json'),'scope':'CLI parser rejection is compared with native Import parser rejection; native Run was not dispatched.'})
plan={'createdUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Prepared only','binary':str(B),'binarySHA256':digest(B.read_bytes()),'environment':{'DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY':str(R/'cli-settings')},'initialConfigs':{str(C/n):digest(base) for n in ['baseline-scp.json','saved-scp.json','simulation-save.json']},'nativeConfigsProtected':{str(p):digest(p.read_bytes()) for p in (R/'config').glob('*.json')},'cases':cases,'scope':['No listener, peer, physical spool or native Open command is included.','Only executable and explicit config/output path options differ; every replacement is recorded.','Save operations begin from byte-identical native baseline copies; they write fresh cli-scp-replay-config only.','Simulation output is fresh; TIFF(last selected image format)+PDF expected, with no PNG.','Sink-failure fresh native-001.png directory intentionally prevents file write; failure must be reported with no Wrote claim.','Native Open already has Preview AX evidence; replay deliberately excludes it to avoid a second UI launch.']}
(R/'scp-cli-replay-plan.json').write_text(json.dumps(plan,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'prepared':len(cases),'plan':str(R/'scp-cli-replay-plan.json')}))
