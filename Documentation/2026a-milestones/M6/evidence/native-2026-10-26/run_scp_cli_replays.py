#!/usr/bin/env python3
"""Root-operated isolated SCP CLI controls; explicit execution opt-in required."""
import argparse,datetime,json,os,subprocess,time
from pathlib import Path
from verify_print_native_outputs import digest
R=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser();p.add_argument('--execute',action='store_true');p.add_argument('--plan',type=Path,default=R/'scp-cli-replay-plan.json');a=p.parse_args()
 if not a.execute:p.error('Root must supply --execute after reviewing scp-cli-replay-plan.json')
 plan=json.loads(a.plan.read_text());assert digest(Path(plan['binary']).read_bytes())==plan['binarySHA256']
 if 'sourceJustification' in plan:assert digest(Path(plan['sourceJustification']).read_bytes())==plan['sourceJustificationSHA256'],'Source justification changed'
 for path,sha in plan['initialConfigs'].items():assert digest(Path(path).read_bytes())==sha,'Initial copied config changed'
 for path,sha in plan['nativeConfigsProtected'].items():assert digest(Path(path).read_bytes())==sha,'Native config changed since plan'
 for c in plan['cases']:
  assert not Path(c['resultFile']).exists(),'Existing result must be preserved'
  assert digest(Path(c['nativeConsole']).read_bytes())==c['nativeConsoleSHA256']
 env=os.environ.copy();env.update(plan['environment'])
 for c in plan['cases']:
  p=Path(c['resultFile']);p.parent.mkdir(parents=True,exist_ok=True);o=p.with_suffix('.stdout.txt');e=p.with_suffix('.stderr.txt');start=time.monotonic();timeout=False
  with o.open('x') as so,e.open('x') as se:
   try:r=subprocess.run(c['argv'],env=env,stdin=subprocess.DEVNULL,stdout=so,stderr=se,shell=False,timeout=c['timeoutSeconds']);code=r.returncode
   except subprocess.TimeoutExpired:timeout=True;code=124
  result={'name':c['name'],'argv':c['argv'],'returncode':code,'timedOut':timeout,'durationSeconds':time.monotonic()-start,'stdout':o.read_text(),'stderr':e.read_text(),'binarySHA256':plan['binarySHA256'],'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()}
  p.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'case':c['name'],'exit':code,'expected':c['expectedExitCode']}),flush=True)
  if code!=c['expectedExitCode']:return 1
 for path,sha in plan['nativeConfigsProtected'].items():assert digest(Path(path).read_bytes())==sha,'Native config was unexpectedly modified'
 return 0
if __name__=='__main__':raise SystemExit(main())
