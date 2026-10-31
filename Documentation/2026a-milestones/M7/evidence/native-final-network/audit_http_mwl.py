#!/usr/bin/env python3
"""Read-only verification of completed native/CLI local HTTP and MWL evidence."""
import datetime,hashlib,io,json,pathlib,re,sys,urllib.parse
sys.dont_write_bytecode=True
ROOT=pathlib.Path(__file__).resolve().parent;UI=ROOT.parent/'native-2026-10-26/ui-network'
sys.path.insert(0,str(ROOT));import replay_http_case as h
from pydicom.filereader import read_dataset

def verify_http():
    checks=[]
    def ck(n,p,d=None):checks.append({'name':n,'passed':bool(p),'detail':d})
    specs=json.loads((ROOT/'http-replay-inputs.json').read_text());caps=h.load_captures();receipts=[]
    ck('exact native and CLI HTTP request total',len(caps)==36,len(caps))
    for s in specs:
        r=json.loads((ROOT/'cli'/s['case']/'verification.json').read_text());receipts.append(r)
        ck(s['case']+' replay checks all pass',r['passed'] and all(x['passed'] for x in r['checks']))
        t=pathlib.Path(s['native_ui']).read_text();ck(s['case']+' actual native SUCCESS','text Console SUCCESS' in t)
        if s['kind']=='query':
            pos=t.index('\n\n[')+2;n,_=json.JSONDecoder().raw_decode(t[pos:]);c=json.loads((ROOT/'cli'/s['case']/'stdout.txt').read_text())
            ck(s['case']+' full native summary equals CLI JSON',n==c)
    def q(i):return dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(caps[i-1]['request']['path']).query))
    ck('parent and PPS filters on unscoped series',q(9)=={'00080020':'20260115','00400244':'20260115','limit':'100','offset':'0'})
    ck('scoped series hides parent date and retains PPS',q(10)=={'00400244':'20260115','limit':'100','offset':'0'})
    ck('fully scoped instances hide parent and series filters',q(11)=={'limit':'100','offset':'0'})
    ck('SERIES modality uses 00080060',q(12)=={'00080060':'CT','limit':'100','offset':'0'})
    ck('STUDY modality uses 00080061',q(13)=={'00080061':'CT','limit':'100','offset':'0'})
    listed='1.2.826.0.1.3680043.10.543.301,1.2.826.0.1.3680043.10.543.302'
    ck('UID alternatives remain literal matching query',q(14)=={'0020000D':listed,'limit':'100','offset':'0'} and '/studies?' in caps[13]['request']['path'])
    ck('UTF-8 patient-name intersects UID alternatives',q(15)=={'00100010':'Müller*','0020000D':listed,'limit':'100','offset':'0'})
    ck('changed tool executes fresh query without old filters',q(16)=={'limit':'100','offset':'0'})
    returned=(UI/'qido-filter-returned.txt').read_text();ck('return to series restores preserved hidden UI filters',bool(re.search(r'Description: Study Date, Value: 20260115',returned)) and bool(re.search(r'Description: PPS Start Date,.*Value: 20260115',returned)))
    reset=(UI/'qido-changed-tool-reset.txt').read_text();ck('changed tool clears old UI state','Console IDLE' in reset and 'Description: Base URL, Placeholder:' in reset and 'Description: Study Date, Placeholder:' in reset and 'Müller*' not in reset)
    for name in ['qido-basic-copied-command','wado-basic-copied-command','stow-basic-copied-command','qido-basic-multiline-copied-command']:
        t=(UI/(name+'.txt')).read_text();copy=t.split('Value: # ',1)[1];copy='# '+copy
        ck(name+' all copied lines are comments',all(line.startswith('# ') for line in copy.splitlines() if line.strip()))
        ck(name+' explicitly app-only and omits credentials','basic auth is not CLI-representable' in copy and 'only-test:pass' not in copy and 'm7-native' not in copy)
    ck('STOW native and CLI success summary parity','Total files: 1\n  Successful: 1\n  Failed: 0' in (UI/'stow-basic.txt').read_text() and 'Total files: 1\n  Successful: 1\n  Failed: 0' in (ROOT/'cli/stow-basic/stdout.txt').read_text())
    log=(ROOT/'http/swift-bridge.log').read_text();ck('HTTP peer process harness completed cleanly','Executed 1 test, with 0 failures' in log and "Test Suite 'Selected tests' passed" in log)
    report={'cases':['FINAL-06 QIDO/WADO/STOW portions','FINAL-07','FINAL-08','FINAL-11'],'native_actions':18,'CLI_actions':18,'pairwise_assertions':sum(x['assertions'] for x in receipts),'additional_assertions':len(checks),'checks':checks,'passed':all(c['passed'] for c in checks),'limits':['FINAL06 UPS portion remains separate.','Native Basic header handling is verified; CLI has no Basic authentication flag and equivalent CLI requests omit Basic explicitly.','Synthetic capture server does not enforce credentials.','One native full-instance WADO action covers FINAL11; no additional metadata or bulkdata runtime claim.','Multiline Basic case checks copied preview only; no request was executed.','Filter return capture is a UI observation, not a new request.','Initial CT keyboard-selection attempt left Any; the first three hidden-filter cases therefore prove date/PPS behavior only. Actual later CT requests prove the modality tags.']}
    return report

def verify_mwl():
    checks=[]
    def ck(n,p,d=None):checks.append({'name':n,'passed':bool(p),'detail':d})
    before=json.loads((ROOT/'mwl-native-before-cli.json').read_text());end=json.loads((ROOT/'mwl/state.json').read_text());finished=json.loads((ROOT/'mwl/finished.json').read_text())
    ck('native three valid requests and no requests for two invalid inputs',before['associations']==3 and len(before['requests'])==3 and not before['errors'])
    ck('final six associations and six requests only',end['associations']==6 and len(end['requests'])==6 and not end['errors'])
    ck('MWL peer clean stop',finished['clean_stop'] and finished['requests']==6)
    dates=['-20261231','20260101-20261231','20261024'];times=['-120000','090000-120000','101530'];names=['mwl-open-range','mwl-bounded-range','mwl-scalar','mwl-invalid-date','mwl-invalid-time']
    decoded={}
    for i,record in enumerate(end['requests'],1):
        raw=(ROOT/'mwl'/f'request-{i:03}.identifier.bin').read_bytes();d=read_dataset(io.BytesIO(raw),is_implicit_VR=record['transfer_syntax']=='1.2.840.10008.1.2',is_little_endian=True);decoded[i]=d.to_json_dict();step=d.ScheduledProcedureStepSequence[0];k=(i-1)%3
        ck(f'raw request{i} equals independently decoded peer JSON',decoded[i]==record['identifier'])
        ck(f'raw request{i} literal DA/TM values and VRs',str(step.ScheduledProcedureStepStartDate)==dates[k] and str(step.ScheduledProcedureStepStartTime)==times[k] and step[0x00400002].VR=='DA' and step[0x00400003].VR=='TM')
        ck(f'request{i} selects one synthetic work item',record['matches']==1 and record['response']['00100020']['Value']==['M7MWL'])
    for i,name in enumerate(names,1):
        execution=json.loads((ROOT/'cli'/name/'execution.json').read_text());t=(UI/(name+'.txt')).read_text();native=t.split('Complete console:\n',1)[1].split('\n\n',1)[1].strip();stdout=(ROOT/'cli'/name/'stdout.txt').read_text();stderr=(ROOT/'cli'/name/'stderr.txt').read_text()
        ck(name+' expected CLI exit',execution['expected_exit_passed'])
        if i<=3:
            ck(name+' native actual SUCCESS','text Console SUCCESS' in t)
            ck(name+' native and CLI decoded Identifier equality',decoded[i]==decoded[i+3])
            ck(name+' native complete result JSON equals CLI',json.loads(native)==json.loads(stdout))
        else:
            ck(name+' native actual ERROR','text Console ERROR' in t)
            ck(name+' native refusal matches CLI error',native==stderr.split('\nUsage:',1)[0].strip())
            ck(name+' CLI causes no new association or request',execution['state_before']==execution['state_after'])
    copy=(UI/'mwl-open-range-copied-command.txt').read_text();ck('actual copied leading-hyphen ranges are bound option values','--date=-20261231' in copy and '--time=-120000' in copy)
    return {'case':'FINAL-05','native_actions':5,'CLI_actions':5,'valid_pairs':3,'refusal_pairs':2,'assertions':len(checks),'checks':checks,'passed':all(c['passed'] for c in checks),'limits':['Independent synthetic pynetdicom peer supports bounded query matching; not a full MWL SCP qualification.']}

if __name__=='__main__':
    for kind,fn in [('http',verify_http),('mwl',verify_mwl)]:
        report=fn();report['verified_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();(ROOT/('native-'+kind+'-verification.json')).write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n');print(kind,report['passed'],len(report['checks']),[c for c in report['checks'] if not c['passed']])
