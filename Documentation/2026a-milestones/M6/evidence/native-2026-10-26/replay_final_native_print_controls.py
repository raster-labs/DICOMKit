#!/usr/bin/env python3
"""Exact three parent-authorized final native CLI controls; no peer/UI creation."""
from pathlib import Path
import json,subprocess,datetime,time
from verify_print_native_outputs import copied_console,digest
R=Path(__file__).resolve().parent;B=Path('/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-print');D=R/'cli-final-controls';names=['final-status-text-console','final-job-text-console','final-row-order-console']
for name in names:assert not (D/(name+'-cli.json')).exists(),'Preserve prior result; do not rerun blindly'
for name in names:
 c=copied_console(R/'ui-repaired'/(name+'.txt'));a=c['argv'][:];a[0]=str(B);out=D/(name+'-cli.stdout.txt');err=D/(name+'-cli.stderr.txt');start=time.monotonic();timed_out=False
 with out.open('x') as so,err.open('x') as se:
  try:p=subprocess.run(a,stdin=subprocess.DEVNULL,stdout=so,stderr=se,shell=False,timeout=45);code=p.returncode
  except subprocess.TimeoutExpired:code=124;timed_out=True
 record={'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'nativeSource':c['source'],'nativeSHA256':c['sha256'],'argv':a,'binarySHA256':digest(B.read_bytes()),'returncode':code,'timedOut':timed_out,'durationSeconds':time.monotonic()-start,'stdout':out.read_text(),'stderr':err.read_text()}
 (D/(name+'-cli.json')).write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'name':name,'exit':code,'stdout':record['stdout'],'stderr':record['stderr']}),flush=True)
 if code:raise SystemExit(code)
