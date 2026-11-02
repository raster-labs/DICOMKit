#!/usr/bin/env python3
"""One actual isolated filesystem server restart for native GET and QR cases."""
import datetime,hashlib,json,pathlib,shutil,signal,socket,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parent
BINARY=pathlib.Path('/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-server')
SOURCE=ROOT.parent/'integrated-final/m5/workshop/synthetic.dcm'
def main():
    evidence=ROOT/'server';evidence.mkdir(exist_ok=False);storage=ROOT/'server-storage';storage.mkdir(exist_ok=False)
    shutil.copyfile(SOURCE,storage/'synthetic.dcm')
    with socket.socket() as probe:probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
    argv=[str(BINARY),'start','--data-dir',str(storage),'--port',str(port),'--aet','M7NATIVE','--database','filesystem']
    receipt={'argv':argv,'binary_sha256':hashlib.sha256(BINARY.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'events':[],'scope':'Actual server uses synthetic isolated storage only. Clients use localhost; listener bind scope follows existing product behavior.'}
    def event(name,**more):
        receipt['events'].append({'name':name,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),**more});(evidence/'lifecycle.json').write_text(json.dumps(receipt,indent=2)+'\n')
    def start(name):
        log=(evidence/(name+'.log')).open('w');proc=subprocess.Popen(argv,stdout=log,stderr=subprocess.STDOUT);event(name+'-started',pid=proc.pid)
        try:
            until=time.monotonic()+20
            while time.monotonic()<until:
                if proc.poll() is not None:raise RuntimeError('Server exited before ready')
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.2):event(name+'-ready',pid=proc.pid);return proc,log
                except OSError:time.sleep(.05)
            raise RuntimeError('Server did not become ready')
        except BaseException:
            if proc.poll() is None:proc.send_signal(signal.SIGTERM);proc.wait(timeout=15)
            log.close();raise
    proc=None;log=None
    try:
        proc,log=start('first');proc.send_signal(signal.SIGTERM);code=proc.wait(timeout=15);log.close();log=None;event('first-stopped',pid=proc.pid,exit=code);assert code==0
        proc,log=start('restarted')
        ready={'host':'127.0.0.1','port':port,'aet':'M7NATIVE','study_uid':'2.25.505','series_uid':'2.25.505.1','instance_uid':'2.25.505.1.1','pid':proc.pid,'storage':str(storage),'stop_file':str(evidence/'stop')}
        (evidence/'ready.json').write_text(json.dumps(ready,indent=2)+'\n');print(json.dumps(ready),flush=True)
        until=time.monotonic()+3600
        while time.monotonic()<until and not(evidence/'stop').exists():
            if proc.poll() is not None:raise RuntimeError('Restarted server exited unexpectedly')
            time.sleep(.2)
    finally:
        if proc is not None and proc.poll() is None:
            proc.send_signal(signal.SIGTERM);code=proc.wait(timeout=15);event('final-stopped',pid=proc.pid,exit=code)
        if log is not None:log.close()
        receipt['source_unchanged']=hashlib.sha256(SOURCE.read_bytes()).hexdigest()==receipt['source_sha256'];receipt['storage_source_unchanged']=(storage/'synthetic.dcm').read_bytes()==SOURCE.read_bytes();receipt['clean_stop']=proc is not None and proc.poll()==0
        (evidence/'lifecycle.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':main()
