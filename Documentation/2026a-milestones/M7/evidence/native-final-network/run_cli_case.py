#!/usr/bin/env python3
"""Capture one reviewed, bounded argv execution and associated peer state delta."""
import datetime,hashlib,json,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parent

def main(spec):
    out=ROOT/'cli'/spec['case'];out.mkdir(parents=True,exist_ok=False)
    def state():
        p=ROOT/spec['peer']/'state.json'
        if p.exists():return json.loads(p.read_text())
        return None
    before=state();start=datetime.datetime.now(datetime.timezone.utc).isoformat()
    result=subprocess.run(spec['argv'],capture_output=True,timeout=spec.get('timeout',45))
    (out/'stdout.txt').write_bytes(result.stdout);(out/'stderr.txt').write_bytes(result.stderr)
    after=state();report={**spec,'started_utc':start,'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'binary_sha256':hashlib.sha256(pathlib.Path(spec['argv'][0]).read_bytes()).hexdigest(),'exit':result.returncode,'state_before':before,'state_after':after,'expected_exit_passed':result.returncode==spec['expected_exit']}
    (out/'execution.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'case':spec['case'],'exit':result.returncode,'expected_exit_passed':report['expected_exit_passed']}))
    return 0 if report['expected_exit_passed'] else 1
if __name__=='__main__':sys.exit(main(json.loads(pathlib.Path(sys.argv[1]).read_text())))
