#!/usr/bin/env python3
"""Read-only audit of retained native SCU DUL captures; does not launch peers/products."""
import datetime, hashlib, importlib.util, json, pathlib, struct
import pydicom
ROOT=pathlib.Path(__file__).resolve().parent
HELPER=ROOT.parents[1]/'DICOMKit-milestones/Scripts/verify_m6_print_interop.py'
spec=importlib.util.spec_from_file_location('qualified_interop',HELPER)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
# Suppress ONLY persistence in the existing qualified decoder. Wire parsing and
# assertions are unchanged. Hash every evidence file before/after as a guard.
class ReadOnlyCapturePath(type(pathlib.Path())):
    def write_bytes(self,data): return len(data)
m.Path=ReadOnlyCapturePath
m.save_json=lambda *args:None
MODES=['normal','warning','failure','set-failure','action-warning','no-lut','event']
files=[HELPER,ROOT/'native_print_peer.py',ROOT/'print-peers-stop.json']
for mode in MODES:
    folder=ROOT/('peer-'+mode)
    files.extend(p for p in folder.rglob('*') if p.is_file())
files.extend(sorted((ROOT/'ui').glob('peer-*-console.txt')))
files.extend(ROOT/'print-fixtures'/('peer-'+n+'.dcm') for n in ['gray8','gray12','rgb8'])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
before={str(p):sha(p) for p in files}
checks=[]; observations={}; captures={}
def check(case,name,condition,detail=None):
    checks.append({'case':case,'assertion':name,'passed':bool(condition),'detail':detail})
def demand(case,name,fn):
    try:fn();check(case,name,True)
    except Exception as e:check(case,name,False,str(e))
def ops(msg,field,sop=None,direction=None):return m.operation(msg,field,sop,direction)
def console(mode,image='gray8'):
    p=ROOT/'ui'/f'peer-{mode}-peer-{image}.dcm-console.txt'
    raw=p.read_text(); token='Description: Print command to import, Value: '
    text=raw.split(token,1)[1].split('\n\t\t\t5 scroll bar',1)[0].rstrip('\n')
    assert text.startswith('$ dicom-print send ')
    repeated=raw.rsplit(token,1)[-1].rstrip('\n')
    check(mode+'-'+image,'complete copied console agrees across duplicate AX representations',text==repeated)
    result=None
    if '\n{' in text:
        result=json.JSONDecoder().raw_decode(text[text.index('\n{')+1:])[0]
    return p,text,result

def response(req,msg):
    found=[x for x in msg if x['association']==req['association'] and x['direction']!=req['direction'] and int(x['command'].CommandField)==(int(req['command'].CommandField)|0x8000) and int(x['command'].get('MessageIDBeingRespondedTo',-1))==int(req['command'].MessageID)]
    assert len(found)==1
    return found[0]

def flat_value(raw,tag):
    at=0
    while at<len(raw):
        g,e=struct.unpack_from('<HH',raw,at);vr=raw[at+4:at+6].decode()
        long=vr in {'OB','OD','OF','OL','OV','OW','SQ','SV','UC','UN','UR','UT','UV'}
        n=struct.unpack_from('<I' if long else '<H',raw,at+(8 if long else 6))[0]
        start=at+(12 if long else 8)
        assert n!=0xffffffff and start+n<=len(raw)
        if (g,e)==tag:return vr,raw[start:start+n]
        at=start+n
    raise AssertionError('tag absent')

for mode in MODES:
    folder=ROOT/('peer-'+mode);msg,assoc=m.decode_capture(folder/'wire');captures[mode]=(msg,assoc)
    summary=json.loads((folder/'capture-summary.json').read_text());peer=json.loads((folder/'independent-peer.json').read_text());live=json.loads((folder/'live-records.json').read_text())
    check(mode,'capture count and clean proxy agree',len(msg)==summary['messages'] and len(assoc)==summary['associations'] and summary['proxy_errors']==[])
    demand(mode,'all response IDs/classes/instances and contexts uniquely correlate',lambda:m.assert_correlations(msg))
    requests=[x for x in msg if not int(x['command'].CommandField)&0x8000]
    demand(mode,'every captured request has exactly one response',lambda:[response(x,msg) for x in requests])
    check(mode,'live and final independent peer logs agree',live==peer)
    names={0x110:'N_GET',0x120:'N_SET',0x130:'N_ACTION',0x140:'N_CREATE',0x150:'N_DELETE'}
    incoming=[{'operation':names[int(x['command'].CommandField)],'class':m.command_class(x,msg),'context':x['context'],'dataset':json.loads(x['data'].to_json()) if x['data'] is not None else None} for x in requests if x['direction']=='c2s']
    # pynetdicom exposes absent N-ACTION Action Information as an empty Dataset.
    peer_records=[{**r,'dataset':None} if r['operation']=='N_ACTION' and r['dataset']=={} else r for r in peer['records']]
    check(mode,'raw wire requests match independent peer records (absent Action Information normalized)',incoming==peer_records)
    all_contexts=True;all_titles=True
    for a in assoc:
        bycontext=a['contexts']
        for r in [x for x in msg if x['association']==a['index']]:
            ctx=bycontext[r['context']];cl=m.command_class(r,msg)
            all_contexts &= ctx['result']==0 and r['transfer'] in (m.EXPLICIT,m.IMPLICIT)
            if cl in [m.LUT,m.ANNOTATION,m.JOB]:all_contexts &= r['abstract']==cl
        raw=(folder/'wire'/(a['index']+'-c2s.dul')).read_bytes()
        requests_pdus=[body for typ,body in m.pdus(raw) if typ==1]
        all_titles &= len(requests_pdus)==1 and requests_pdus[0][4:20].decode().strip()=='PYM6' and requests_pdus[0][20:36].decode().strip()=='M7NATIVE'
    check(mode,'operations use accepted contexts; optional SOP classes use own contexts',all_contexts)
    check(mode,'association AE titles match native command M7NATIVE to PYM6',all_titles)
    expected_closed='abort after successful session delete' if mode in ('set-failure','no-lut') else 'normal release'
    demand(mode,'all associations close with '+expected_closed,lambda:m.assert_closed(assoc) if mode in ('set-failure','no-lut') else m.assert_release(assoc))
    sessions=ops(msg,0x140,m.SESSION,'c2s');deletes=ops(msg,0x150,m.SESSION,'c2s')
    pairs=[]
    for c in sessions:
        uid=str(response(c,msg)['command'].AffectedSOPInstanceUID)
        ds=[x for x in deletes if x['association']==c['association'] and str(x['command'].RequestedSOPInstanceUID)==uid]
        pairs.append(len(ds)==1 and int(response(ds[0],msg)['command'].Status)==0)
    check(mode,'each created Film Session has exactly one matching successful cleanup delete',len(deletes)==len(sessions) and all(pairs))
    unexpected=[hex(int(x['command'].Status)) for x in msg if 'Status' in x['command'] and int(x['command'].Status)!=(0x0106 if mode=='set-failure' and int(x['command'].CommandField)==0x8120 else 0xb604 if mode=='action-warning' and int(x['command'].CommandField)==0x8130 else 0)]
    check(mode,'response statuses exactly match injected/success contract',not unexpected,unexpected)
    settings=[]
    for r in sessions:
        d=r['data'];settings.append(str(d.NumberOfCopies)=='1' and str(d.PrintPriority)=='MED' and str(d.MediumType)=='PAPER' and str(d.FilmDestination)=='PROCESSOR' and d['NumberOfCopies'].VR=='IS')
    for r in ops(msg,0x140,m.BOX,'c2s'):
        d=r['data'];settings.append(str(d.ImageDisplayFormat)=='STANDARD\\1,1' and str(d.FilmSizeID)=='8INX10IN' and str(d.FilmOrientation)=='PORTRAIT' and str(d.MagnificationType)=='REPLICATE' and d['ImageDisplayFormat'].VR=='ST')
        parents=[x for x in sessions if x['association']==r['association']]
        settings.append(len(parents)==1 and str(d.ReferencedFilmSessionSequence[0].ReferencedSOPClassUID)==m.SESSION and str(d.ReferencedFilmSessionSequence[0].ReferencedSOPInstanceUID)==str(response(parents[0],msg)['command'].AffectedSOPInstanceUID))
    check(mode,'session/film values, VR and parent references match visible command',all(settings))
    observations[mode]={'messages':len(msg),'associations':len(assoc),'request_operations':[r['operation']+':'+r['class'] for r in peer['records']], 'session_creates':len(sessions),'session_deletes':len(deletes),'print_actions':len(ops(msg,0x130,m.BOX,'c2s')),'closure':expected_closed,'event_acks':peer['event_acks']}

# Eight native send outcomes, with the normal endpoint used for two separate images.
for mode,image,association,color in [('normal','gray12','01',False),('normal','rgb8','02',True),('warning','gray8','01',False),('action-warning','gray8','00',False),('event','gray8','00',False)]:
    whole,_=captures[mode];msg=[r for r in whole if r['association']==association];case=mode+'-'+image
    demand(case,'one create/set/print/delete workflow with no duplicate print action',lambda:m.assert_flow(msg,m.COLOR if color else m.GRAY))
    demand(case,'full pixel bytes and image numeric metadata match independent input',lambda:m.assert_pixels(msg,ROOT/'print-fixtures'/('peer-'+image+'.dcm'),color=color))
    pix=ops(msg,0x120,m.COLOR if color else m.GRAY)[0]['data'];item=(pix.BasicColorImageSequence if color else pix.BasicGrayscaleImageSequence)[0]
    check(case,'wire Pixel Data VR OW and metadata VR US retained',item['PixelData'].VR=='OW' and all(item[k].VR=='US' for k in ['Rows','Columns','SamplesPerPixel','BitsAllocated','BitsStored','HighBit','PixelRepresentation']))
    _,text,result=console(mode,image)
    action=ops(msg,0x130,m.BOX)[0];action_rsp=response(action,msg)
    check(case,'console successful job identity equals exact response/reference UIDs',result is not None and result['success'] is True and result['filmBoxUID']==str(action['command'].RequestedSOPInstanceUID) and result['filmSessionUID']==str(response(ops(msg,0x140,m.SESSION)[0],msg)['command'].AffectedSOPInstanceUID) and result['printJobUID']==str(action_rsp['data'][0x21000500].value[0].ReferencedSOPInstanceUID))
    check(case,'Action ID is Print (1) and Print Job reply uses 21000500 SQ/UI',int(action['command'].ActionTypeID)==1 and action_rsp['data'][0x21000500].VR=='SQ' and str(action_rsp['data'][0x21000500].value[0].ReferencedSOPClassUID)==m.JOB)
    observations[mode].setdefault('pixel_cases',[]).append({'image':image,'wire_bits_allocated':int(item.BitsAllocated),'wire_bits_stored':int(item.BitsStored),'rows':int(item.Rows),'columns':int(item.Columns),'samples':int(item.SamplesPerPixel),'planar_configuration':int(item.PlanarConfiguration) if color else None,'wire_pixel_sha256':hashlib.sha256(bytes(item.PixelData)).hexdigest(),'source':str(ROOT/'print-fixtures'/('peer-'+image+'.dcm'))})
    if mode=='warning':check(case,'native console preserves Printer WARNING and continuation','Printer reports WARNING (SUPPLY LOW)' in text and 'continuing' in text)
    if mode=='action-warning':
        warning=result.get('warnings',[])
        check(case,'B604 accepted warning remains successful and visible with Film Box UID',int(action_rsp['command'].Status)==0xb604 and len(warning)==1 and warning[0]['status']=='0xB604' and warning[0]['filmBoxUID']==result['filmBoxUID'] and 'demagnified' in warning[0]['message'])

normal=captures['normal'][0]
luts=ops(normal,0x140,m.LUT);boxes=[x for x in ops(normal,0x140,m.BOX) if x['association']=='01'];notes=ops(normal,0x120,m.ANNOTATION)
check('normal-gray12','one IDENTITY LUT is referenced by Film Box with exact returned UID',len(luts)==1 and str(luts[0]['data'].PresentationLUTShape)=='IDENTITY' and luts[0]['data']['PresentationLUTShape'].VR=='CS' and len(boxes)==1 and str(boxes[0]['data'].ReferencedPresentationLUTSequence[0].ReferencedSOPClassUID)==m.LUT and str(boxes[0]['data'].ReferencedPresentationLUTSequence[0].ReferencedSOPInstanceUID)==str(response(luts[0],normal)['command'].AffectedSOPInstanceUID))
check('normal-gray12','two annotation positions and exact lexical bytes including spaces/semicolon are ordered',len(notes)==2 and [int(n['data'].AnnotationPosition) for n in notes]==[1,2] and [flat_value(n['data_raw'],(0x2030,0x0020)) for n in notes]==[('LO',b' first; literal note  '),('LO',b'second note ')] and all(n['data']['AnnotationPosition'].VR=='US' for n in notes))
for mode,status in [('normal','NORMAL'),('warning','WARNING'),('failure','FAILURE')]:
    msg,_=captures[mode];get=ops(msg,0x110,m.PRINTER,'c2s')
    check(mode,'preflight N-GET returns actual '+status+' Printer Status',len(get)==1 and str(response(get[0],msg)['data'].PrinterStatus)==status)

for mode in ['failure','set-failure','no-lut']:
    msg,assoc=captures[mode];_,text,result=console(mode)
    check(mode,'refusal sends no N-ACTION and console reports failure',not ops(msg,0x130) and result is None and 'Error:' in text)
    if mode=='failure':check(mode,'failed Printer preflight creates no session/box/image','Printer reports FAILURE (SUPPLY LOW)' in text and not ops(msg,0x140) and not ops(msg,0x120))
    elif mode=='set-failure':
        sets=ops(msg,0x120,m.GRAY)
        check(mode,'injected N-SET 0106 diagnostic reaches native console',len(sets)==1 and int(response(sets[0],msg)['command'].Status)==0x0106 and str(response(sets[0],msg)['command'].ErrorComment)=='M6 INJECTED SET FAILURE' and '0x0106' in text and 'M6 INJECTED SET FAILURE' in text)
        demand(mode,'rejected N-SET still contains exact independent gray8 pixels',lambda:m.assert_pixels(msg,ROOT/'print-fixtures/peer-gray8.dcm'))
    else:
        check(mode,'LUT proposal is actually rejected; no substitute LUT/box/image command',any(c['abstract']==m.LUT and c['result']!=0 for a in assoc for c in a['contexts'].values()) and not ops(msg,0x140,m.LUT) and not ops(msg,0x140,m.BOX) and not ops(msg,0x120) and m.LUT in text)

msg,_=captures['event'];events=ops(msg,0x100,m.JOB,'s2c');acks=ops(msg,0x8100,m.JOB,'c2s')
check('event','one DONE event uses separately accepted implicit Print Job context and successful correlated ACK',len(events)==len(acks)==1 and events[0]['abstract']==m.JOB and events[0]['transfer']==m.IMPLICIT and events[0]['context']==acks[0]['context'] and int(events[0]['command'].EventTypeID)==3 and int(events[0]['command'].MessageID)==711 and int(acks[0]['command'].MessageIDBeingRespondedTo)==711 and int(acks[0]['command'].Status)==0 and int(acks[0]['command'].CommandDataSetType)==0x101)
check('event','event information expected status/info, native job UID and peer ACK agree',str(events[0]['command'].AffectedSOPInstanceUID)==m.BASE+'2000' and str(events[0]['data'].ExecutionStatusInfo)=='NORMAL' and str(events[0]['data'].PrinterName)=='M6 SYNTHETIC' and str(events[0]['data'].FilmSessionLabel)=='M6' and json.loads((ROOT/'peer-event/independent-peer.json').read_text())['event_acks']==[0])
reqs=[x for x in msg if x['direction']=='c2s'];rsps=[x for x in msg if x['direction']=='s2c']
check('event','ACK is sent during outstanding N-ACTION before session cleanup',next(i for i,x in enumerate(reqs) if int(x['command'].CommandField)==0x130)<next(i for i,x in enumerate(reqs) if int(x['command'].CommandField)==0x8100)<next(i for i,x in enumerate(reqs) if int(x['command'].CommandField)==0x150) and next(i for i,x in enumerate(rsps) if int(x['command'].CommandField)==0x100)<next(i for i,x in enumerate(rsps) if int(x['command'].CommandField)==0x8130))
check('provenance','all retained evidence bytes unchanged by independent audit',before=={str(p):sha(p) for p in files})
failed=[x for x in checks if not x['passed']]
report={'reviewed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'verdict':'PASS' if not failed else 'FAIL','scope':'Eight native SCU sends to seven independent stopped software peers; retained raw DUL independently decoded. No product/UI/peer launch or build.', 'native_send_outcomes':8,'peers':7,'associations':sum(len(a) for _,a in captures.values()),'dimse_messages':sum(len(x) for x,_ in captures.values()),'assertions':{'total':len(checks),'passed':len(checks)-len(failed),'failed':len(failed)},'checks':checks,'observations':observations,'evidence_sha256':before,'reader':{'pydicom':pydicom.__version__,'qualified_helper':str(HELPER),'helper_sha256':sha(HELPER),'decoder_persistence':'disabled for original evidence; parsing/assertion implementation unchanged'},'limits':['Independent software peer only; no physical printer/paper or vendor interoperability certification.','Only the eight retained sends are asserted; no native listener/SCP, printer registry, capabilities, Job N-GET, timeout/retry or other unobserved UI action is inferred.','Successful flows release normally. Injected N-SET failure and rejected LUT clean up with successful session deletion then A-ABORT; do not describe these two as normal releases.','Session cleanup wire request/response is proven. The simple peer records operations; durable resource reclamation or actual physical completion is outside its model.','Grayscale12 command includes raw mode and render bit-depth8; raw preserves original 16 allocated/12 stored pixel samples on wire, as independently verified.','Annotation first trailing space is indistinguishable from DICOM trailing padding semantically; exact expected UTF8/ASCII bytes including original space plus one even pad are checked.','Copied console was obtained by the native owner and pasted into a nonexecuted Import sheet for complete AX capture; report uses it as copied output corroborated by wire, not as new command execution.','This audit does not independently repeat source/app identity checks; see native-resume-identity and owner execution record for packaged provenance.'],'standards_basis':[{'local_frozen':'work/standards/part04_2026a.xml','section':'H.4.1.2.3','meaning':'Film Session N-DELETE covers session hierarchy including referenced images/annotations/LUTs; peer reclamation not asserted.'}]}
(ROOT/'native-scu-peer-independent-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'verdict':report['verdict'],'assertions':report['assertions'],'outcomes':8,'associations':report['associations'],'messages':report['dimse_messages'],'failed':failed},ensure_ascii=False))
