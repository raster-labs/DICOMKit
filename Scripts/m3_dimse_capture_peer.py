#!/usr/bin/env python3
"""Independent, synthetic loopback C-FIND peer for M3 CLI/Workshop qualification.
Python stdlib only; no production DICOMKit imports. Never binds non-loopback.
Usage: python3 m3_dimse_capture_peer.py CAPTURE_DIR [--seconds 600]
Wait for ready.json. Stop via CAPTURE_DIR/stop. Raw Identifier/Command bytes and
JSON interpretations are retained. Fixtures: CT study 2.25.301, series 2.25.301.1;
MR study 2.25.302, series 2.25.302.1. These are fabricated test identifiers.
This is a bounded test peer, not a general DICOM SCP or conformance oracle.
"""
import argparse, fnmatch, json, pathlib, socket, struct, time

IMPLICIT = '1.2.840.10008.1.2'
EXPLICIT = '1.2.840.10008.1.2.1'
FIND_CLASSES = {'1.2.840.10008.5.1.4.1.2.1.1', '1.2.840.10008.5.1.4.1.2.2.1'}
LONG_VRS = {'OB','OD','OF','OL','OV','OW','SQ','UC','UR','UT','UN','SV','UV'}
VRS = {0x00080020:'DA',0x00080021:'DA',0x00080023:'DA',0x00080030:'TM',
       0x00080050:'SH',0x00080052:'CS',0x00080060:'CS',0x00080061:'CS',
       0x00080090:'PN',0x00081030:'LO',0x0008103E:'LO',0x00080016:'UI',0x00080018:'UI',
       0x00100010:'PN',0x00100020:'LO',0x00100030:'DA',0x00100040:'CS',
       0x0020000D:'UI',0x0020000E:'UI',0x00200010:'SH',0x00200011:'IS',0x00200013:'IS',
       0x00201200:'IS',0x00201202:'IS',0x00201204:'IS',0x00201206:'IS',0x00201208:'IS',0x00201209:'IS',
       0x00280008:'IS',0x00280010:'US',0x00280011:'US'}
FIXTURES = []
for index, modality in enumerate(['CT','MR'], 1):
    study = f'2.25.30{index}'
    FIXTURES.append({0x00100010:f'AUDIT^{modality}',0x00100020:f'M3{modality}',0x00100030:'19800101',
        0x00100040:'O',0x00080020:'20261024',0x00080021:'20261024',0x00080023:'20261024',
        0x00080030:'103000',0x00080060:modality,0x00080061:modality,0x00080050:f'M3{index}',
        0x00080090:'TEST^PHYSICIAN',0x00081030:f'M3 {modality} STUDY',0x0008103E:f'M3 {modality} SERIES',
        0x0020000D:study,0x0020000E:study+'.1',0x00080018:study+'.1.1',
        0x00080016:'1.2.840.10008.5.1.4.1.1.'+('2' if modality=='CT' else '4'),
        0x00200010:str(index),0x00200011:'1',0x00200013:'1',0x00201200:'1',0x00201202:'1',
        0x00201204:'1',0x00201206:'1',0x00201208:'1',0x00201209:'1',0x00280008:'1',
        0x00280010:2,0x00280011:2})

def item(kind, value): return struct.pack('>BBH',kind,0,len(value))+value

def items(data):
    offset=0
    while offset<len(data):
        if offset+4>len(data): raise ValueError('truncated item header')
        kind, _, size=struct.unpack_from('>BBH',data,offset); offset+=4
        if offset+size>len(data): raise ValueError('truncated item')
        yield kind,data[offset:offset+size]; offset+=size

def element(tag, vr, value, explicit):
    if isinstance(value, int): value=struct.pack('<H' if vr=='US' else '<I', value)
    elif isinstance(value, str): value=value.encode('ascii')
    if len(value)%2: value+=b'\0' if vr=='UI' else b' '
    header=struct.pack('<HH',tag>>16,tag&0xffff)
    if not explicit: header+=struct.pack('<I',len(value))
    elif vr in LONG_VRS: header+=vr.encode()+b'\0\0'+struct.pack('<I',len(value))
    else: header+=vr.encode()+struct.pack('<H',len(value))
    return header+value

def dataset(values, explicit, vrs=None):
    return b''.join(element(tag,(vrs or VRS).get(tag,'LO'),value,explicit) for tag,value in sorted(values.items()))

def decode(data, explicit):
    result={};offset=0
    while offset<len(data):
        if offset+8>len(data): raise ValueError('truncated data element')
        group,elem=struct.unpack_from('<HH',data,offset);tag=group<<16|elem
        if explicit:
            vr=data[offset+4:offset+6].decode('ascii')
            if vr in LONG_VRS:
                if offset+12>len(data): raise ValueError('truncated long VR')
                size=struct.unpack_from('<I',data,offset+8)[0];offset+=12
            else: size=struct.unpack_from('<H',data,offset+6)[0];offset+=8
        else: vr=VRS.get(tag,'UN');size=struct.unpack_from('<I',data,offset+4)[0];offset+=8
        if offset+size>len(data): raise ValueError('truncated value')
        if tag in result: raise ValueError('duplicate tag')
        raw=data[offset:offset+size];offset+=size
        result[tag]={'vr':vr,'raw':raw,'value':raw.decode('ascii',errors='replace').rstrip(' \0')}
    return result

def association_accept(body):
    if len(body)<68: raise ValueError('short association')
    accepted={};response=[]
    for kind,value in items(body[68:]):
        if kind==0x10: response.append(item(0x10,value))
        elif kind==0x20:
            context_id=value[0]; abstract=None;syntaxes=[]
            for subkind,subvalue in items(value[4:]):
                if subkind==0x30: abstract=subvalue.decode('ascii')
                elif subkind==0x40: syntaxes.append(subvalue.decode('ascii'))
            syntax=next((s for s in [EXPLICIT,IMPLICIT] if s in syntaxes),None)
            result=0 if abstract in FIND_CLASSES and syntax else 3
            if result==0: accepted[context_id]={'abstract':abstract,'syntax':syntax}
            response.append(item(0x21,bytes([context_id,0,result,0])+item(0x40,(syntax or IMPLICIT).encode())))
    user=item(0x51,struct.pack('>I',16384))+item(0x52,b'2.25.999301')+item(0x55,b'M3_CAPTURE')
    return body[:68]+b''.join(response)+item(0x50,user),accepted

def command_response(sop, message_id, status, with_data):
    values={0x00000002:('UI',sop),0x00000100:('US',0x8020),0x00000120:('US',message_id),
            0x00000800:('US',0x0001 if with_data else 0x0101),0x00000900:('US',status)}
    body=b''.join(element(tag,vr,value,False) for tag,(vr,value) in sorted(values.items()))
    return element(0,'UL',len(body),False)+body

def match(value, expression, vr):
    if not expression: return True
    text=str(value)
    if vr=='UI': return text in expression.split('\\')
    if vr in {'DA','TM'} and '-' in expression:
        start,end=expression.split('-',1)
        return (not start or text>=start) and (not end or text<=end)
    return fnmatch.fnmatchcase(text,expression)

def matches(keys):
    return [row for row in FIXTURES if all(tag==0x00080052 or not key['value'] or
        match(row.get(tag,''),key['value'],key['vr'] if key['vr']!='UN' else VRS.get(tag,'LO'))
        for tag,key in keys.items())]

def recv_exact(conn,size):
    parts=[]
    while size:
        part=conn.recv(size)
        if not part: raise EOFError()
        parts.append(part);size-=len(part)
    return b''.join(parts)

def send_pdu(conn,kind,body): conn.sendall(struct.pack('>BBI',kind,0,len(body))+body)
def send_pdv(conn,context,command,payload):
    send_pdu(conn,4,struct.pack('>I',len(payload)+2)+bytes([context,3 if command else 2])+payload)

def save_json(path,value): path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def serial_keys(keys): return {f'{tag:08X}':{'vr':key['vr'],'value':key['value']} for tag,key in sorted(keys.items())}

class Peer:
    def __init__(self,directory): self.directory=directory;self.associations=0;self.requests=0;self.errors=[]
    def state(self):
        save_json(self.directory/'state.json',{'associations':self.associations,'requests':self.requests,'errors':self.errors})
    def handle(self,conn):
        self.associations+=1;association=self.associations;self.state()
        contexts={};commands={};command_buffers={};data_buffers={}
        while True:
            kind,_,size=struct.unpack('>BBI',recv_exact(conn,6))
            if size>16*1024*1024: raise ValueError('PDU too large')
            body=recv_exact(conn,size)
            if kind==1:
                reply,contexts=association_accept(body)
                save_json(self.directory/f'association-{association:03}.json',{'contexts':contexts,
                    'calledAE':body[4:20].decode().strip(),'callingAE':body[20:36].decode().strip()})
                send_pdu(conn,2,reply)
            elif kind==4:
                offset=0
                while offset<len(body):
                    if offset+6>len(body): raise ValueError('short PDV')
                    count=struct.unpack_from('>I',body,offset)[0];offset+=4
                    if count<2 or offset+count>len(body): raise ValueError('invalid PDV length')
                    context,control=body[offset:offset+2];payload=body[offset+2:offset+count];offset+=count
                    if context not in contexts: raise ValueError('unaccepted context')
                    if control&1:
                        command_buffers[context]=command_buffers.get(context,b'')+payload
                        if control&2:
                            commands[context]=command_buffers.pop(context)
                    else:
                        data_buffers[context]=data_buffers.get(context,b'')+payload
                        if control&2:
                            self.respond(conn,association,context,contexts[context],commands.pop(context),data_buffers.pop(context))
            elif kind==5:
                send_pdu(conn,6,b'\0'*4);return
            elif kind==7: return
            else: raise ValueError(f'unsupported PDU {kind}')
    def respond(self,conn,association,context,negotiated,command,identifier):
        command_keys=decode(command,False)
        if struct.unpack('<H',command_keys[0x00000100]['raw'])[0]!=0x0020: raise ValueError('not C-FIND')
        message=struct.unpack('<H',command_keys[0x00000110]['raw'])[0]
        explicit=negotiated['syntax']==EXPLICIT;keys=decode(identifier,explicit)
        self.requests+=1;prefix=self.directory/f'request-{self.requests:03}'
        prefix.with_suffix('.command.bin').write_bytes(command)
        prefix.with_suffix('.identifier.bin').write_bytes(identifier)
        rows=matches(keys);level=keys[0x00080052]['value']
        record={'association':association,'context':context,'transferSyntax':negotiated['syntax'],
                'queryLevel':level,'keys':serial_keys(keys),'resultCount':len(rows)}
        save_json(prefix.with_suffix('.json'),record);self.state()
        for index,row in enumerate(rows,1):
            values={tag:(level if tag==0x00080052 else row.get(tag,'')) for tag in keys}
            wire=dataset(values,explicit,{tag:(key['vr'] if explicit else VRS.get(tag,'LO')) for tag,key in keys.items()})
            prefix.with_suffix(f'.response-{index}.bin').write_bytes(wire)
            send_pdv(conn,context,True,command_response(negotiated['abstract'],message,0xff00,True))
            send_pdv(conn,context,False,wire)
        send_pdv(conn,context,True,command_response(negotiated['abstract'],message,0,False))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',type=pathlib.Path)
    parser.add_argument('--seconds',type=int,default=600);args=parser.parse_args()
    args.directory.mkdir(parents=True,exist_ok=True)
    if (args.directory/'ready.json').exists(): raise SystemExit('Use a fresh capture directory to preserve earlier evidence')
    peer=Peer(args.directory);deadline=time.monotonic()+args.seconds
    with socket.socket() as server:
        server.bind(('127.0.0.1',0));server.listen(4);server.settimeout(.5)
        save_json(args.directory/'ready.json',{'host':'127.0.0.1','port':server.getsockname()[1],
            'fixtures':[{f'{tag:08X}':value for tag,value in row.items()} for row in FIXTURES],
            'seconds':args.seconds,'synthetic':True,'implementation':'Python standard library; no DICOMKit imports'})
        peer.state()
        while time.monotonic()<deadline and not (args.directory/'stop').exists():
            try: conn,_=server.accept()
            except socket.timeout: continue
            with conn:
                conn.settimeout(min(15,max(1,deadline-time.monotonic())))
                try: peer.handle(conn)
                except EOFError: pass
                except Exception as exc: peer.errors.append(f'{type(exc).__name__}: {exc}');peer.state()
    peer.state();save_json(args.directory/'finished.json',{'associations':peer.associations,'requests':peer.requests})
if __name__=='__main__': main()
