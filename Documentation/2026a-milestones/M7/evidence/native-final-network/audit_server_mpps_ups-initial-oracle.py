#!/usr/bin/env python3
import datetime,hashlib,io,json,pathlib,re,sys
sys.dont_write_bytecode=True
ROOT=pathlib.Path(__file__).resolve().parent;UI=ROOT.parent/'native-2026-10-26/ui-network'
sys.path.insert(0,str(ROOT.parent.parent/'DICOMKit-milestones/Scripts'))
from verify_m4_durability import dataset_bytes
from pydicom.filereader import read_dataset
import pydicom

def console(name):
    t=(UI/(name+'.txt')).read_text();return t,t.split('Complete console:\n',1)[1].split('\n\n',1)[1].strip()
def audit_server():
    checks=[];files={}
    def ck(n,p,d=None):checks.append({'name':n,'passed':bool(p),'detail':d})
    life=json.loads((ROOT/'server/lifecycle.json').read_text());events=life['events'];names=[e['name'] for e in events]
    ck('actual start stop restart ready final stop ordering',names==['first-started','first-ready','first-stopped','restarted-started','restarted-ready','final-stopped'])
    ck('first process terminated before a different process restarted',events[2]['exit']==-15 and events[0]['pid']!=events[3]['pid'] and events[2]['utc']<events[3]['utc'])
    ck('final owned process stopped after SIGTERM',life['stopped_after_SIGTERM'] and events[-1]['exit']==-15)
    ck('source and stored fixture unchanged',life['source_unchanged'] and life['storage_source_unchanged'])
    source=ROOT.parent/'integrated-final/m5/workshop/synthetic.dcm';gold=dataset_bytes(source)
    for name in ['retrieve-restarted-get','qr-review','qr-auto']:
        e=json.loads((ROOT/'cli'/name/'execution.json').read_text());t,native=console(name);cli=(ROOT/'cli'/name/'stdout.txt').read_text().strip()
        ck(name+' native SUCCESS and CLI exit0','text Console SUCCESS' in t and e['exit']==0)
        ck(name+' complete console parity after output-directory substitution',native.replace(e['native_output'],'<OUTPUT>')==cli.replace(e['cli_output'],'<OUTPUT>'))
        for surface in ['native','cli']:
            path=pathlib.Path(e[surface+'_output']);actual=[x for x in path.rglob('*') if x.is_file()];files[name+'-'+surface]=[{'path':str(x),'sha256':hashlib.sha256(x.read_bytes()).hexdigest(),'dataset_sha256':hashlib.sha256(dataset_bytes(x)).hexdigest()} for x in actual]
            ck(name+' '+surface+' exact file count',len(actual)==(0 if name=='qr-review' else 1))
            if actual:
                d=pydicom.dcmread(actual[0]);ck(name+' '+surface+' exact source dataset bytes',dataset_bytes(actual[0])==gold)
                ck(name+' '+surface+' exact independent identifiers',str(d.StudyInstanceUID)=='2.25.505' and str(d.SeriesInstanceUID)=='2.25.505.1' and str(d.SOPInstanceUID)=='2.25.505.1.1')
        if name.startswith('qr-'):
            ck(name+' native offers Review and Auto only', 'radio button Description: auto,' in t and 'radio button Description: review,' in t and 'Description: interactive,' not in t)
            ck(name+' exactly one matching study','Found 1 study(ies):' in native)
    return {'cases':['FINAL-10 successful restarted GET','FINAL-15 Review and Auto'],'native_actions':3,'CLI_actions':3,'assertions':len(checks),'checks':checks,'files':files,'passed':all(x['passed'] for x in checks),'limits':['This is one actual native workflow across a process restart; broader durability proofs remain separate.','SIGTERM uses default process termination exit -15. Initial helper incorrectly required exit0; that failure is retained. No graceful shutdown callback or power-loss guarantee is claimed.','Stale Interactive persisted-state injection has no supported native import route and was not executed; existing model refusal test remains separately attributed.','Only output directory paths were normalized for console comparison; all other console text is identical.']}
def audit_mpps():
    checks=[]
    def ck(n,p,d=None):checks.append({'name':n,'passed':bool(p),'detail':d})
    finish=json.loads((ROOT/'mpps/finished.json').read_text());ck('exact six valid associations and datasets after two refusals',finish=={'associations':6,'capturedDataSets':6})
    completion=json.loads((ROOT/'mpps-peer-completion.json').read_text());ck('capture harness test exits0 and passes',completion['exit_code']==0 and 'Executed 1 test, with 0 failures' in completion['output'])
    normalized={};classes=['1.2.840.10008.5.1.4.1.1.2','1.2.840.10008.5.1.4.1.1.4','1.2.840.10008.5.1.4.1.1.7']
    for i in range(1,7):
        raw=(ROOT/'mpps'/f'request-{i:03}.dcmdata').read_bytes();d=read_dataset(io.BytesIO(raw),is_implicit_VR=False,is_little_endian=True);series=d.PerformedSeriesSequence[0];ref=series.ReferencedImageSequence[0]
        ck(f'raw dataset{i} exact state and performed series',str(d.PerformedProcedureStepStatus)=='COMPLETED' and str(series.SeriesInstanceUID)=='2.25.102')
        ck(f'raw dataset{i} exact supplied class and instance pair',str(ref.ReferencedSOPClassUID)==classes[(i-1)%3] and str(ref.ReferencedSOPInstanceUID)=='2.25.103')
        ck(f'raw dataset{i} exactly one series and reference',len(d.PerformedSeriesSequence)==1 and len(series.ReferencedImageSequence)==1)
        n=d.to_json_dict();n.pop('00400250',None);n.pop('00400251',None);normalized[i]=n
    for i,name in enumerate(['mpps-missing-class','mpps-ct','mpps-mr','mpps-sc']):
        e=json.loads((ROOT/'cli'/name/'execution.json').read_text());t,native=console(name);stdout=(ROOT/'cli'/name/'stdout.txt').read_text();stderr=(ROOT/'cli'/name/'stderr.txt').read_text()
        ck(name+' expected CLI exit',e['expected_exit_passed'])
        ck(name+' native correct outcome',('text Console SUCCESS' if i else 'text Console ERROR') in t)
        if i:
            ck(name+' full native/CLI console equality',native==stdout.strip());ck(name+' full normalized dataset equality',normalized[i]==normalized[i+3])
        else:ck(name+' native and CLI refusal identical',native==stderr.split('\nUsage:',1)[0].strip())
    return {'case':'FINAL-12','native_actions':4,'CLI_actions':4,'successful_pairs':3,'refusal_pairs':1,'assertions':len(checks),'checks':checks,'passed':all(x['passed'] for x in checks),'limits':['Capture SCP accepts terminal N-SET updates; this is not proof of persisted MPPS lifecycle transition from IN PROGRESS.','Only generated PPS End Date00400250 and End Time00400251 were removed before whole-dataset comparison.','Mixed-class typed API and intermediate-update enhancements remain outside the native form scope.']}
def audit_ups():
    checks=[]
    def ck(n,p,d=None):checks.append({'name':n,'passed':bool(p),'detail':d})
    records=[json.loads((ROOT/'ups-auth'/f'request-{i:03}.json').read_text()) for i in range(1,5)];finish=json.loads((ROOT/'ups-auth/finished.json').read_text());ck('exactly two native and two CLI UPS requests',finish['requests']==4 and len(list((ROOT/'ups-auth').glob('request-*.json')))==4)
    source=ROOT.parent.parent/'m2/ups-capture-fixtures/cli-workitem.json';fixture=json.loads(source.read_text());ck('original UPS input hash unchanged',hashlib.sha256(source.read_bytes()).hexdigest()=='596f4b4a2dbbd9a12811283dd9441fdc56cdf8e245177c2fe40ddd4de55c59dd')
    auth='Basic bTctbmF0aXZlOm9ubHktdGVzdDpwYXNz';expected='20261024103000.123456+0530'
    for i,r in enumerate(records,1):
        headers={k.lower():v for k,v in r['headers'].items()};ck(f'UPS request{i} exact authentication scope',headers.get('authorization')==(auth if i<=2 else None));ck(f'UPS request{i} expected method',r['method']==('POST' if i in [1,3] else 'GET'))
        if i in [1,3]:
            d=json.loads(r['body']);ck(f'UPS POST{i} exact original input JSON and route',d==fixture and r['path']=='/dicom-web/workitems');ck(f'UPS POST{i} exact DT and SCHEDULED state',d['00404005']=={'vr':'DT','Value':[expected]} and d['00741000']['Value']==['SCHEDULED'])
    ncreate=console('ups-basic-create')[1];ccreate=(ROOT/'cli/ups-basic-create/stdout.txt').read_text();nuid=re.search(r'UID: ([0-9.]+)',ncreate).group(1);cuid=re.search(r'UID: ([0-9.]+)',ccreate).group(1)
    ck('GET uses each surface own returned UID',records[1]['path']=='/dicom-web/workitems/'+nuid and records[3]['path']=='/dicom-web/workitems/'+cuid and nuid!=cuid)
    n=json.loads(console('ups-basic-get')[1]);c=json.loads((ROOT/'cli/ups-basic-get/stdout.txt').read_text());ck('native GET exact timestamp and state',len(n)==1 and n[0]['scheduledStartDateTime']==expected and n[0]['state']=='SCHEDULED');ck('CLI GET exact timestamp and state',len(c)==1 and c[0]['scheduledStartDateTime']==expected and c[0]['state']=='SCHEDULED')
    ck('native and CLI entire GET result equal except peer-assigned UID',{k:v for k,v in n[0].items() if k!='workitemUID'}=={k:v for k,v in c[0].items() if k!='workitemUID'})
    parsed=datetime.datetime.strptime(expected,'%Y%m%d%H%M%S.%f%z').astimezone(datetime.timezone.utc);ck('DT independently resolves correct exact UTC instant',parsed.isoformat()=='2026-10-24T05:00:00.123456+00:00')
    for name in ['ups-basic-create','ups-basic-get']:
        e=json.loads((ROOT/'cli'/name/'execution.json').read_text());t,_=console(name);ck(name+' actual native SUCCESS and CLI exit0','text Console SUCCESS' in t and e['exit']==0)
    copy=(UI/'ups-basic-copied-command.txt').read_text().split('Value: # ',1)[1];copy='# '+copy;ck('UPS copied Basic command entirely app-only comments',all(x.startswith('# ') for x in copy.splitlines() if x.strip()) and 'basic auth is not CLI-representable' in copy and 'only-test:pass' not in copy)
    b=(UI/'ups-bearer-preview.txt').read_text();none=(UI/'ups-none-preview.txt').read_text();ck('UPS Bearer copied preview has only intended token','--token m7-native-token' in b and 'only-test:pass' not in b and '# in-app' not in b);ck('UPS none copied preview has no stale auth','--token' not in none and 'only-test:pass' not in none and '# in-app' not in none)
    return {'cases':['FINAL-06 UPS portion','FINAL-13'],'native_actions':2,'CLI_actions':2,'assertions':len(checks),'checks':checks,'passed':all(x['passed'] for x in checks),'limits':['Synthetic capture peer supports POST/GET only; no PUT state transition or production UPS server acceptance claim.','Native Basic request headers are verified; CLI requests intentionally omit Basic because it has no Basic flag. Server credential enforcement is not tested.','Bearer/none UPS transitions are copied-preview observations only, not additional executed requests.','The existing create-json route preserves compact DICOM DT; native Scheduled Start field expects ISO8601 and was not given compact DT.']}
if __name__=='__main__':
    for name,fn in [('server',audit_server),('mpps',audit_mpps),('ups',audit_ups)]:
        report=fn();report['verified_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();(ROOT/('native-'+name+'-verification.json')).write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(name,report['passed'],len(report['checks']),[x for x in report['checks'] if not x['passed']])
