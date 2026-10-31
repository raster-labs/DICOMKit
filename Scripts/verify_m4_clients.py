#!/usr/bin/env python3
"""Verify terminal cancellation outcomes in real CLI and Workshop executors.
Uses a controlled FE00 peer, independently of the actual server C-CANCEL gate.
"""
import argparse,hashlib,json,os,pathlib,subprocess,sys,time
sys.dont_write_bytecode=True

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--bin-dir',type=pathlib.Path,required=True);p.add_argument('--test-bundle',type=pathlib.Path,required=True);p.add_argument('--output-dir',type=pathlib.Path,required=True);a=p.parse_args()
    root=a.output_dir.resolve();root.mkdir(parents=True,exist_ok=True);peer_dir=root/'peer'
    if peer_dir.exists():p.error('Use a fresh output directory')
    peer_dir.mkdir();script=pathlib.Path(__file__).with_name('m4_client_outcome_peer.py');records=[]
    with (root/'peer.log').open('w') as log:
        peer=subprocess.Popen([sys.executable,'-B',str(script),str(peer_dir),'--seconds','300'],stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+10
            while not (peer_dir/'ready.json').exists():
                assert peer.poll() is None and time.monotonic()<deadline,'Peer startup failed'
                time.sleep(.05)
            port=str(json.loads((peer_dir/'ready.json').read_text())['port'])
            for name in ['find-empty','find-partial','move-cancel','get-cancel']:
                query=name.startswith('find');binary=a.bin_dir/('dicom-query' if query else 'dicom-retrieve')
                argv=[str(binary),'127.0.0.1','--port',port,'--aet','M4CLIENT','--called-aet','M4PEER','--timeout','5']
                if query:argv+=['--level','study','--patient-id','M4ZERO' if name=='find-empty' else 'M4PARTIAL','--format','json']
                else:
                    argv+=['--method','c-move' if name=='move-cancel' else 'c-get','--study-uid','2.25.404','--output',str(root/'received')]
                    if name=='move-cancel':argv+=['--move-dest','M4DEST']
                result=subprocess.run(argv,capture_output=True,text=True,timeout=30)
                (root/(name+'.stdout.txt')).write_text(result.stdout);(root/(name+'.stderr.txt')).write_text(result.stderr)
                assert result.returncode==1,(name,result.returncode,result.stdout,result.stderr)
                output=result.stdout+result.stderr;assert 'cancel' in output.lower(),output
                if query:
                    assert 'FE00' in output and ('0 partial result(s)' if name=='find-empty' else '1 partial result(s)') in output
                    if name=='find-partial':assert json.loads(result.stdout)[0]['(0010,0010)']=='M4^PARTIAL'
                else:
                    assert '2.25.404.9' in output
                    assert 'Number of Remaining Sub-operations: 2' in output and 'Number of Failed Sub-operations: 1' in output,output
                    assert ('Number of Completed Sub-operations: 1' if name=='move-cancel' else 'Number of Completed Sub-operations: 0') in output
                    assert ('Number of Warning Sub-operations: 1' if name=='move-cancel' else 'Number of Warning Sub-operations: 0') in output
                    if name=='get-cancel':assert 'likely no storage' not in output
                records.append({'name':name,'exit':result.returncode,'argv':argv,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()})
            env=dict(os.environ,DICOMKIT_M4_CLIENT_PORT=port,DICOMKIT_M4_CLIENT_OUTPUT=str(root))
            result=subprocess.run(['xcrun','xctest','-XCTest','DICOMStudioTests.M4ClientOutcomeHarnessTests/testControlledCancellationOutcomes',str(a.test_bundle)],env=env,capture_output=True,text=True,timeout=120)
            (root/'workshop.log').write_text(result.stdout+result.stderr);assert result.returncode==0,result.stdout+result.stderr
            app=json.loads((root/'workshop.json').read_text());assert len(app)==4
            for row in app:
                cli=(root/(row['name']+'.stdout.txt')).read_text()+(root/(row['name']+'.stderr.txt')).read_text()
                # Workshop prepends its displayed command; all output lines must agree after it.
                console=row['console'].split('\n\n',1)[-1]
                assert console.strip()==cli.strip(),(row['name'],console,cli)
            state=json.loads((peer_dir/'state.json').read_text());assert len(state['requests'])==8 and state['released']==8 and state['aborted']==0 and not state['errors'],state
            (root/'results.json').write_text(json.dumps({'passed':True,'cli_cases':4,'workshop_cases':4,'normal_releases':8,'aborts':0,'records':records,'scope':'Controlled FE00 outcomes; actual server C-CANCEL verified separately'},indent=2)+'\n')
            print('M4 client outcomes:4CLI+4Workshop passed;8normal releases;0aborts')
        finally:
            (peer_dir/'stop').touch()
            try:peer.wait(timeout=5)
            except subprocess.TimeoutExpired:peer.terminate();peer.wait(timeout=5)
if __name__=='__main__':main()
