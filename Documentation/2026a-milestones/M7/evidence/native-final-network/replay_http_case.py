#!/usr/bin/env python3
"""Bounded same-peer CLI parity for an already captured native HTTP case.
Input is a reviewed case JSON, argv array is executed without a shell.
"""
import base64,datetime,email,gzip,hashlib,json,pathlib,subprocess,sys,urllib.parse,zlib
ROOT=pathlib.Path(__file__).resolve().parent

def load_captures():
    p=ROOT/'http/captures.json'
    return json.loads(p.read_text()) if p.exists() else []
def body(cap):
    data=base64.b64decode(cap['response']['bodyBase64'])
    encoding={k.lower():v for k,v in cap['response']['headers'].items()}.get('content-encoding')
    if encoding=='gzip': return gzip.decompress(data)
    if encoding=='deflate': return zlib.decompress(data)
    if encoding not in (None,'identity'): raise ValueError('Unsupported response content encoding: '+encoding)
    return data
def headers(req):return {k.lower():v for k,v in req['headers'].items()}
def location(req):
    u=urllib.parse.urlsplit(req['path']); return (req['method'],u.path,sorted(urllib.parse.parse_qsl(u.query,keep_blank_values=True)))
def parts(data,content_type):
    m=email.message_from_bytes(b'Content-Type: '+content_type.encode()+b'\r\nMIME-Version: 1.0\r\n\r\n'+data)
    return [x.get_payload(decode=True) for x in m.walk() if not x.is_multipart()]
def run(spec):
    name=spec['case'];out=ROOT/'cli'/name
    out.mkdir(parents=True,exist_ok=False)
    report={'case':name,'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'native_capture':spec['native_capture'],'argv':spec['argv'],'checks':[],'limitations':spec.get('limitations',[])}
    def check(name,passed,detail=None):report['checks'].append({'name':name,'passed':bool(passed),'detail':detail})
    captures=load_captures();native=captures[spec['native_capture']-1];before=len(captures)
    check('native response HTTP status',native['response']['status']==spec.get('expected_status',200))
    check('native authorization',headers(native['request']).get('authorization')==spec.get('native_authorization'))
    p=subprocess.run(spec['argv'],capture_output=True,timeout=60)
    (out/'stdout.txt').write_bytes(p.stdout);(out/'stderr.txt').write_bytes(p.stderr)
    report['exit']=p.returncode;report['binary_sha256']=hashlib.sha256(pathlib.Path(spec['argv'][0]).read_bytes()).hexdigest()
    check('CLI exit',p.returncode==spec.get('expected_exit',0),p.returncode)
    captures=load_captures();new=captures[before:];report['cli_capture_indices']=list(range(before+1,len(captures)+1))
    check('exactly one CLI request',len(new)==1,len(new))
    if len(new)==1:
        cli=new[0]
        check('same method, resource and decoded query',location(native['request'])==location(cli['request']),{'native':location(native['request']),'cli':location(cli['request'])})
        check('CLI response HTTP status',cli['response']['status']==spec.get('expected_status',200))
        check('CLI authorization',headers(cli['request']).get('authorization')==spec.get('cli_authorization'))
        if spec['kind']=='query':
            n=json.loads(body(native));c=json.loads(body(cli));tag={'study':'0020000D','series':'0020000E','instance':'00080018'}[spec['level']]
            nu=sorted(x[tag]['Value'][0] for x in n);cu=sorted(x[tag]['Value'][0] for x in c)
            report['native_UIDs']=nu;report['cli_UIDs']=cu
            check('native exact expected UID set',nu==sorted(spec['expected_uids']),nu)
            check('CLI exact expected UID set',cu==sorted(spec['expected_uids']),cu)
            check('native and CLI complete DICOM JSON response equality',n==c)
        elif spec['kind']=='retrieve':
            nr={k.lower():v for k,v in native['response']['headers'].items()};cr={k.lower():v for k,v in cli['response']['headers'].items()}
            nb=parts(body(native),nr['content-type']);cb=parts(body(cli),cr['content-type']);gold=pathlib.Path(spec['fixture']).read_bytes()
            check('native response exact Part10 fixture',nb==[gold]);check('CLI response exact Part10 fixture',cb==[gold])
            for surface in ['native','cli']:
                files=[x for x in pathlib.Path(spec[surface+'_output']).rglob('*') if x.is_file()]
                hashes={str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in files};report[surface+'_files']=hashes
                check(surface+' exactly one output equal fixture',len(files)==1 and files[0].read_bytes()==gold,hashes)
        elif spec['kind']=='store':
            gold=pathlib.Path(spec['fixture']).read_bytes()
            for surface,cap in [('native',native),('cli',cli)]:
                req=cap['request'];b=base64.b64decode(req['bodyBase64']);mp=parts(b,headers(req)['content-type'])
                check(surface+' request exact Part10 fixture',mp==[gold]);response=json.loads(body(cap));report[surface+'_response']=response
            check('same STOW result JSON',json.loads(body(native))==json.loads(body(cli)))
    report['passed']=all(x['passed'] for x in report['checks']);report['assertions']=len(report['checks'])
    (out/'verification.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'case':name,'passed':report['passed'],'assertions':report['assertions'],'cli_capture_indices':report['cli_capture_indices'],'failures':[x for x in report['checks'] if not x['passed']]}))
    return 0 if report['passed'] else 1
if __name__=='__main__':sys.exit(run(json.loads(pathlib.Path(sys.argv[1]).read_text())))
