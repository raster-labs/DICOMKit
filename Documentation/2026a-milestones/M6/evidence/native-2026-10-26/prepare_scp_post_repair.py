#!/usr/bin/env python3
"""Read source/binary evidence and create a new isolated replay plan. No product invocation."""
from pathlib import Path
import json,subprocess,datetime,hashlib
r=Path(__file__).resolve().parent;repo=r.parents[1]/'DICOMKit-milestones';old=r/'scp-cli-replay-plan.json';p=json.loads(old.read_text());sha=lambda b:hashlib.sha256(b).hexdigest();git=lambda *args:subprocess.check_output(['git','-C',str(repo),*args])
head=git('rev-parse','HEAD').decode().strip();changes=git('diff','--name-only','--','Sources').decode().splitlines();unchanged=['Sources/DICOMPrintCommandSupport/PrintCommandContext.swift','Sources/dicom-printscp','Sources/DICOMPrintKit','Sources/DICOMNetwork']
source_files=list((repo/'Sources/DICOMPrintCommandSupport').glob('SCP*.swift'))+[repo/'Sources/DICOMPrintCommandSupport/PrintCommandContext.swift']+list((repo/'Sources/dicom-printscp').glob('*.swift'))
assert git('diff','--',*unchanged)==b'', 'Unexpected SCP/core product delta'
sourceproof=[]
for f in source_files:
 relative=str(f.relative_to(repo));current=f.read_bytes();before=git('show',head+':'+relative);assert current==before;sourceproof.append({'path':relative,'sha256':sha(current),'identicalToNativeEvidenceHEAD':True})
proof={'createdUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'nativeEvidenceHEAD':head,'originalPlan':str(old),'originalPlanSHA256':sha(old.read_bytes()),'originalBinarySHA256':p['binarySHA256'],'postRepairBinarySHA256':sha(Path(p['binary']).read_bytes()),'productionChangesSinceHEAD':changes,'sharedCommandDiff':git('diff','--','Sources/DICOMPrintCommandSupport/SCUCommands.swift').decode(),'unchangedSCPSourceFiles':sourceproof,'unchangedScope':['Sources/DICOMPrintCommandSupport/SCP*.swift']+unchanged,'qualificationDecision':'Only shared command behavior change is SCU list empty-result JSON formatting. SCP executable/support/core source and callbacks are unchanged. Rebuilt binary has a new hash because its shared module includes the changed SCU source. These new isolated CLI controls may compare existing native SCP results, with both identities retained. They do not replace final rebuilt-app native UI acceptance.','buildEvidence':[{'path':str(r/'print-repair-verification'/n),'sha256':sha((r/'print-repair-verification'/n).read_bytes())} for n in ['build-dicom-printscp.log','dicom-printscpTests.log','dicom-printTests.log']],'limits':['Detached-AppKit AX-role test failure under investigation by owning agent; not a CLI/SCP behavior failure.','No product, build, UI or peer invoked by this preparation.']}
proof_path=r/'scp-post-repair-source-justification.json';proof_path.write_text(json.dumps(proof,indent=2,ensure_ascii=False)+'\n')
config=r/'cli-scp-replay-post-repair-config';config.mkdir(exist_ok=False);base=(r/'config/baseline-scp.json').read_bytes()
for n in ['baseline-scp.json','saved-scp.json','simulation-save.json']:(config/n).write_bytes(base)
sim=r/'cli-simulated-post-repair';sink=r/'cli-sink-failure-post-repair';sim.mkdir();sink.mkdir();(sink/'native-001.png').mkdir()
replacements={str(r/'cli-scp-replay-config'):str(config),str(r/'cli-simulated-replay'):str(sim),str(r/'cli-sink-failure-replay'):str(sink),str(r/'cli-results/scp-replay-v1'):str(r/'cli-results/scp-replay-post-repair-v1')}
def replace(s):
 for a,b in replacements.items():
  if s==a or s.startswith(a+'/'):return b+s[len(a):]
 return s
p.update(originalPlan=str(old),originalPlanSHA256=sha(old.read_bytes()),sourceJustification=str(proof_path),sourceJustificationSHA256=sha(proof_path.read_bytes()),previousBinarySHA256=p['binarySHA256'],binarySHA256=proof['postRepairBinarySHA256'],createdUTC=proof['createdUTC'],status='Prepared post-repair controls only; not executed',configDirectory=str(config),simulationOutputDirectory=str(sim),sinkOutputDirectory=str(sink),initialConfigs={str(config/n):sha(base) for n in ['baseline-scp.json','saved-scp.json','simulation-save.json']})
for c in p['cases']:
 c['argv']=[replace(a) for a in c['argv']];c['resultFile']=replace(c['resultFile'])
 for q in c.get('replacements',[]):q['cli']=replace(q['cli'])
new=r/'scp-cli-replay-plan-post-repair.json';new.write_text(json.dumps(p,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'plan':str(new),'proof':str(proof_path),'originalBinarySHA256':proof['originalBinarySHA256'],'newBinarySHA256':p['binarySHA256'],'unchangedSCPFiles':len(sourceproof)},indent=2))
