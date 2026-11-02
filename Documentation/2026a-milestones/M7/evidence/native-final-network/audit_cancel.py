#!/usr/bin/env python3
import io,json,pathlib,re,shlex
from pydicom.filereader import read_dataset
ROOT=pathlib.Path(__file__).resolve().parent;UI=ROOT.parent/'native-2026-10-26/ui-network'
def read(p,implicit=True):return read_dataset(io.BytesIO(p.read_bytes()),is_implicit_VR=implicit,is_little_endian=True)
def main():
    checks=[]
    def ck(n,p,d=None):checks.append({'name':n,'passed':bool(p),'detail':d})
    before=json.loads((ROOT/'cancel-native-before-cli.json').read_text());state=json.loads((ROOT/'cancel/state.json').read_text());finish=json.loads((ROOT/'cancel/finished.json').read_text())
    ck('exactly four native requests with normal release',len(before['requests'])==4 and before['released']==4 and before['aborted']==0 and not before['errors'])
    ck('exactly eight total requests without automatic retries',len(state['requests'])==8 and state['released']==8 and state['aborted']==0 and not state['errors'])
    ck('peer clean stop',finish['clean_stop'])
    names=['find-cancel-zero','find-cancel-partial','retrieve-move-cancel','retrieve-get-cancel'];raw={};ops=[0x20,0x20,0x21,0x10]
    for i,rec in enumerate(state['requests'],1):
        k=(i-1)%4;prefix=ROOT/'cancel'/f'request-{i:03}';term=read(prefix.with_suffix('.terminal.bin'));cmd=read(prefix.with_suffix('.command.bin'));raw[i]=prefix.with_suffix('.identifier.bin').read_bytes()
        ck(f'request{i} raw operation and FE00 terminal status',cmd.CommandField==ops[k] and term.CommandField==(ops[k]|0x8000) and term.Status==0xfe00)
        if k<2:
            ck(f'request{i} exact partial count',rec['partial_results']==k)
            if k==1:
                d=read(prefix.with_suffix('.partial.bin'),rec['transfer_syntax']=='1.2.840.10008.1.2');ck(f'request{i} partial synthetic row preserved',str(d.PatientName)=='M4^PARTIAL' and str(d.StudyInstanceUID)=='2.25.301')
        else:
            expected=[2,1,1,1] if k==2 else [2,0,1,0];actual=[int(term[t].value) for t in [0x00001020,0x00001021,0x00001022,0x00001023]];ck(f'request{i} independently decoded exact counters',actual==expected,actual)
            uid=read(prefix.with_suffix('.failed-uids.bin'),rec['transfer_syntax']=='1.2.840.10008.1.2');ck(f'request{i} failed SOP UID list',str(uid[0x00080058].value)=='2.25.404.9')
            ck(f'request{i} MoveDestination only in C-MOVE command',str(cmd[0x00000600].value)=='M4DEST' if k==2 else 0x00000600 not in cmd)
    for i,name in enumerate(names,1):
        e=json.loads((ROOT/'cli'/name/'execution.json').read_text());t=(UI/(name+'.txt')).read_text();native=t.split('Complete console:\n',1)[1].split('\n\n',1)[1].strip();stdout=(ROOT/'cli'/name/'stdout.txt').read_text();stderr=(ROOT/'cli'/name/'stderr.txt').read_text();cli=(stdout+stderr).strip()
        ck(name+' native ERROR and CLI nonzero exit','text Console ERROR' in t and e['exit']==1)
        ck(name+' exact native/CLI request Identifier',raw[i]==raw[i+4])
        if i<=2:ck(name+' full native/CLI partial result and error match',native==cli)
        else:
            marker='Executing C-MOVE...' if i==3 else 'Executing C-GET...';ck(name+' full native/CLI final outcome text matches',native.split(marker,1)[1].strip()==cli.split(marker,1)[1].strip())
            native_command=re.findall(r'^\$ (dicom-retrieve .+)$',t,re.M)[0];na=shlex.split(native_command);paths=[pathlib.Path(na[na.index('--output')+1]),pathlib.Path(e['argv'][e['argv'].index('--output')+1])]
            ck(name+' no stored files on either surface',all(not [x for x in p.rglob('*') if x.is_file()] for p in paths))
    report={'cases':['FINAL-09 cancellation','FINAL-10 cancellation'],'native_actions':4,'CLI_actions':4,'assertions':len(checks),'checks':checks,'passed':all(x['passed'] for x in checks),'limits':['Controlled peer-generated FE00 response tests client reporting, not a native cancellation-button origin or server C-CANCEL handling.','Peer performs no C-STORE; reported counters are controlled synthetic values.','C-GET retained Move Destination in the native preview; both wire commands correctly omit MoveDestination. CLI prints the unused option in its introductory header while Workshop omits it; terminal outcome comparison begins at Executing C-GET.','Prepared run card had reversed GET/MOVE counter expectations; the correction is retained in run-card-correction.json and the oracle uses raw terminal CommandSet bytes.']};(ROOT/'native-cancel-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(report['passed'],len(checks),[x for x in checks if not x['passed']])
if __name__=='__main__':main()
