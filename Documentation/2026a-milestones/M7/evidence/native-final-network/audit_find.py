#!/usr/bin/env python3
import io,json,pathlib,sys
from pydicom.filereader import read_dataset
ROOT=pathlib.Path(__file__).resolve().parent;UI=ROOT.parent/'native-2026-10-26/ui-network'
def main():
    checks=[]
    def ck(n,p,d=None):checks.append({'name':n,'passed':bool(p),'detail':d})
    before=json.loads((ROOT/'find-native-before-cli.json').read_text());end=json.loads((ROOT/'find/state.json').read_text());finish=json.loads((ROOT/'find/finished.json').read_text())
    ck('native positives only create three associations and requests',before=={'associations':3,'errors':[],'requests':3})
    ck('native and CLI positives only create six associations and requests',end=={'associations':6,'errors':[],'requests':6})
    ck('peer finished expected six requests',finish=={'associations':6,'requests':6})
    names=['find-study-ct','find-series-ct','find-image','find-image-modality-refusal','find-patient-date-refusal','find-patient-description-refusal','find-patient-uid-refusal']
    raw={};datasets={}
    for i in range(1,7):
        rec=json.loads((ROOT/'find'/f'request-{i:03}.json').read_text());raw[i]=(ROOT/'find'/f'request-{i:03}.identifier.bin').read_bytes();datasets[i]=read_dataset(io.BytesIO(raw[i]),is_implicit_VR=rec['transferSyntax']=='1.2.840.10008.1.2',is_little_endian=True);k=(i-1)%3
        d=datasets[i];ck(f'request{i} expected query level',str(d.QueryRetrieveLevel)==['STUDY','SERIES','IMAGE'][k]);ck(f'request{i} matches one expected row',rec['resultCount']==1)
        if k==0:
            ck(f'request{i} STUDY exact modality/date/wildcards',str(d.ModalitiesInStudy)=='CT' and 0x00080060 not in d and str(d.StudyDate)=='20260101-20261231' and str(d.PatientName)=='AUDIT*' and str(d.StudyDescription)=='M3*')
        if k==1:ck(f'request{i} SERIES exact modality/scoping',str(d.Modality)=='CT' and 0x00080061 not in d and str(d.StudyInstanceUID)=='2.25.301')
        if k==2:ck(f'request{i} IMAGE exact hierarchy without modality',str(d.StudyInstanceUID)=='2.25.301' and str(d.SeriesInstanceUID)=='2.25.301.1' and 0x00080060 not in d and 0x00080061 not in d)
        resp=read_dataset(io.BytesIO((ROOT/'find'/f'request-{i:03}.response-1.bin').read_bytes()),is_implicit_VR=rec['transferSyntax']=='1.2.840.10008.1.2',is_little_endian=True)
        ck(f'request{i} raw response exact expected UID',str(resp[[0x0020000D,0x0020000E,0x00080018][k]].value)==['2.25.301','2.25.301.1','2.25.301.1.1'][k])
    for i,name in enumerate(names,1):
        e=json.loads((ROOT/'cli'/name/'execution.json').read_text());t=(UI/(name+'.txt')).read_text();native=t.split('Complete console:\n',1)[1].split('\n\n',1)[1].strip();stdout=(ROOT/'cli'/name/'stdout.txt').read_text();stderr=(ROOT/'cli'/name/'stderr.txt').read_text()
        ck(name+' expected CLI exit',e['expected_exit_passed'])
        if i<=3:
            ck(name+' actual native SUCCESS','text Console SUCCESS' in t);ck(name+' byte-exact native/CLI Identifier',raw[i]==raw[i+3]);ck(name+' complete native/CLI JSON results equal',json.loads(native)==json.loads(stdout))
        else:
            ck(name+' actual native ERROR','text Console ERROR' in t);ck(name+' same native/CLI refusal',native==stderr.split('\nUsage:',1)[0].strip());ck(name+' CLI no association or request',e['state_before']==e['state_after'])
    report={'case':'FINAL-09 positive queries and filter refusals','native_actions':7,'CLI_actions':7,'assertions':len(checks),'checks':checks,'passed':all(x['passed'] for x in checks),'limits':['Cancellation results are verified separately. Independent synthetic DIMSE peer; not a general PACS.']};(ROOT/'native-find-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(report['passed'],len(checks),[x for x in checks if not x['passed']])
if __name__=='__main__':main()
