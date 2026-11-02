#!/usr/bin/env python3
"""Continue the already completed first SIGTERM stop on the same storage and port.
The first helper incorrectly required exit0; SIGTERM default exit−15 is recorded
explicitly. This verifies process restart, not graceful shutdown callbacks.
"""
import datetime,hashlib,json,pathlib,signal,socket,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parent

def main():
    evidence=ROOT/'server';path=evidence/'lifecycle.json';old=json.loads(path.read_text());assert [e['name'] for e in old['events']]==['first-started','first-ready','first-stopped'];assert old['events'][-1]['exit']==-signal.SIGTERM
    backup=evidence/'initial-helper-zero-exit-assumption-failure.json';backup.write_text(json.dumps(old,indent=2)+'\n')
    argv=old['argv'];binary=pathlib.Path(argv[0]);storage=pathlib.Path(argv[argv.index('--data-dir')+1]);port=int(argv[argv.index('--port')+1]);source=ROOT.parent/'integrated-final/m5/workshop/synthetic.dcm'
    assert hashlib.sha256(binary.read_bytes()).hexdigest()==old['binary_sha256'];assert hashlib.sha256(source.read_bytes()).hexdigest()==old['source_sha256'];assert (storage/'synthetic.dcm').read_bytes()==source.read_bytes()
    report=dict(old);report.pop('clean_stop',None);report['graceful_shutdown_demonstrated']=False;report['oracle_correction']='SIGTERM exit -15 is expected process termination; original exit0 assumption was invalid. No product change.'
    def event(name,**more):
        report['events'].append({'name':name,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),**more});path.write_text(json.dumps(report,indent=2)+'\n')
    log=(evidence/'restarted.log').open('w');proc=subprocess.Popen(argv,stdout=log,stderr=subprocess.STDOUT);event('restarted-started',pid=proc.pid)
    try:
        until=time.monotonic()+20
        while time.monotonic()<until:
            assert proc.poll() is None,'Restarted server exited before ready'
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.2):break
            except OSError:time.sleep(.05)
        else:raise TimeoutError('Restarted listener not ready')
        event('restarted-ready',pid=proc.pid)
        ready={'host':'127.0.0.1','port':port,'aet':'M7NATIVE','study_uid':'2.25.505','series_uid':'2.25.505.1','instance_uid':'2.25.505.1.1','pid':proc.pid,'storage':str(storage),'stop_file':str(evidence/'stop')}
        (evidence/'ready.json').write_text(json.dumps(ready,indent=2)+'\n');print(json.dumps(ready),flush=True)
        until=time.monotonic()+3600
        while time.monotonic()<until and not(evidence/'stop').exists():
            assert proc.poll() is None,'Restarted server exited unexpectedly';time.sleep(.2)
    finally:
        if proc.poll() is None:proc.send_signal(signal.SIGTERM);proc.wait(timeout=15)
        log.close();event('final-stopped',pid=proc.pid,exit=proc.returncode)
        report['stopped_after_SIGTERM']=proc.returncode==-signal.SIGTERM;report['source_unchanged']=hashlib.sha256(source.read_bytes()).hexdigest()==old['source_sha256'];report['storage_source_unchanged']=(storage/'synthetic.dcm').read_bytes()==source.read_bytes();path.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
