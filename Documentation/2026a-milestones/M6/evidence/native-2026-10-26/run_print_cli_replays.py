#!/usr/bin/env python3
"""Parent-operated exact native argv replays. Creating this file runs nothing."""
import argparse,datetime,hashlib,json,os,subprocess,time
from pathlib import Path

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--plan',type=Path,default=Path(__file__).with_name('print-cli-replay-plan.json'));p.add_argument('--execute',action='store_true');a=p.parse_args();plan=json.loads(a.plan.read_text())
 if not a.execute:p.error('Explicit --execute is required; parent must ensure exclusive use of the existing receiver.')
 binary=Path(plan['binary']);assert sha(binary)==plan['binarySHA256'],'Final binary differs from prepared plan'
 receiver=plan['receiver'];assert len(list(Path(receiver['outputDirectory']).glob('*.png')))==receiver['existingFilmCount'],'Receiver baseline count differs; stop and regenerate plan/output mapping'
 for case in plan['cases']:
  assert sha(Path(case['nativeConsole']))==case['nativeConsoleSHA256'],'Native evidence changed'
  assert not Path(case['resultFile']).exists(),'Refusing to overwrite result '+case['resultFile']
 env=os.environ.copy();env.update(plan['environment'])
 for case in plan['cases']:
  target=Path(case['resultFile']);target.parent.mkdir(parents=True,exist_ok=True);out=target.with_suffix('.stdout.txt');err=target.with_suffix('.stderr.txt');before=len(list(Path(receiver['outputDirectory']).glob('*.png')));started=time.monotonic();timed_out=False
  with out.open('x') as stdout,err.open('x') as stderr:
   try:result=subprocess.run(case['argv'],env=env,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,timeout=case['timeoutSeconds'],shell=False);code=result.returncode
   except subprocess.TimeoutExpired:timed_out=True;code=124
  after=len(list(Path(receiver['outputDirectory']).glob('*.png')))
  record={'name':case['name'],'argv':case['argv'],'environmentOverrides':plan['environment'],'returncode':code,'timedOut':timed_out,'durationSeconds':time.monotonic()-started,'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'stdout':out.read_text(),'stderr':err.read_text(),'filmCountBefore':before,'filmCountAfter':after,'expectedFilmDelta':case['expectedFilmDelta'],'binarySHA256':plan['binarySHA256']}
  target.write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'case':case['name'],'returncode':code,'filmDelta':after-before,'result':str(target)}),flush=True)
  if code!=0 or after-before!=case['expectedFilmDelta']:return 1
 return 0
if __name__=='__main__':raise SystemExit(main())
