#!/usr/bin/env python3
"""Synthetic loopback FE00 peer for CLI/Workshop outcome verification.
This peer emits controlled terminal outcomes; actual C-CANCEL handling is tested
separately against ServerSession. It is not a general PACS. No external access.
"""
import argparse, importlib.util, json, pathlib, socket, struct, sys, time
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('wire', pathlib.Path(__file__).with_name('m3_dimse_capture_peer.py'))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
for model in [1,2]:
    w.FIND_CLASSES.update(f'1.2.840.10008.5.1.4.1.2.{model}.{op}' for op in [1,2,3])
w.FIND_CLASSES.add('1.2.840.10008.5.1.4.1.1.2')
w.VRS[0x00080058] = 'UI'


def response(sop, message, command, status, data=False, counts=None):
    values={0x00000002:('UI',sop),0x00000100:('US',command|0x8000),0x00000120:('US',message),
            0x00000800:('US',1 if data else 0x0101),0x00000900:('US',status)}
    if counts is not None:
        values.update({0x00001020+i:('US',v) for i,v in enumerate(counts)})
    body=b''.join(w.element(t,vr,v,False) for t,(vr,v) in sorted(values.items()))
    return w.element(0,'UL',len(body),False)+body


class Peer:
    def __init__(self, root):
        self.root=root; self.records=[]; self.released=0; self.aborted=0; self.errors=[]
    def save(self):
        w.save_json(self.root/'state.json',{'requests':self.records,'released':self.released,'aborted':self.aborted,'errors':self.errors})
    def handle(self, conn):
        contexts={};commands={};buffers={};data={}
        while True:
            kind,_,size=struct.unpack('>BBI',w.recv_exact(conn,6))
            if size>16*1024*1024: raise ValueError('Oversized PDU')
            body=w.recv_exact(conn,size)
            if kind==1:
                reply,contexts=w.association_accept(body)
                roles=[]
                for k,v in w.items(body[68:]):
                    if k==0x50: roles += [w.item(sk,sv) for sk,sv in w.items(v) if sk==0x54]
                rebuilt=reply[:68]
                for k,v in w.items(reply[68:]): rebuilt+=w.item(k,v+b''.join(roles) if k==0x50 else v)
                w.send_pdu(conn,2,rebuilt)
            elif kind==4:
                offset=0
                while offset<len(body):
                    count=struct.unpack_from('>I',body,offset)[0];offset+=4
                    if count<2 or offset+count>len(body): raise ValueError('Bad PDV')
                    context,control=body[offset:offset+2];payload=body[offset+2:offset+count];offset+=count
                    if control&1:
                        buffers[context]=buffers.get(context,b'')+payload
                        if control&2: commands[context]=buffers.pop(context)
                    else:
                        data[context]=data.get(context,b'')+payload
                        if control&2: self.respond(conn,context,contexts[context],commands.pop(context),data.pop(context))
            elif kind==5:
                self.released+=1;self.save();w.send_pdu(conn,6,b'\0'*4);return
            elif kind==7:
                self.aborted+=1;self.save();return
            else: raise ValueError(f'Unexpected PDU {kind}')
    def respond(self,conn,context,negotiated,command,identifier):
        keys=w.decode(command,False);operation=struct.unpack('<H',keys[0x100]['raw'])[0]
        message=struct.unpack('<H',keys[0x110]['raw'])[0];explicit=negotiated['syntax']==w.EXPLICIT
        attrs=w.decode(identifier,explicit);sop=negotiated['abstract'];number=len(self.records)+1
        prefix=self.root/f'request-{number:03}';prefix.with_suffix('.command.bin').write_bytes(command)
        prefix.with_suffix('.identifier.bin').write_bytes(identifier)
        record={'operation':operation,'keys':w.serial_keys(attrs),'terminal_status':'FE00','transfer_syntax':negotiated['syntax']}
        if operation==0x20:
            partial=0 if attrs.get(0x00100020,{}).get('value')=='M4ZERO' else 1
            if partial:
                row=dict(w.FIXTURES[0]);row[0x00100010]='M4^PARTIAL';row[0x00100020]='M4PARTIAL'
                values={tag:('STUDY' if tag==0x00080052 else row.get(tag,'')) for tag in attrs}
                wire=w.dataset(values,explicit,{tag:(v['vr'] if explicit else w.VRS.get(tag,'LO')) for tag,v in attrs.items()})
                w.send_pdv(conn,context,True,response(sop,message,operation,0xff00,True))
                w.send_pdv(conn,context,False,wire);prefix.with_suffix('.partial.bin').write_bytes(wire)
            terminal=response(sop,message,operation,0xfe00);record['partial_results']=partial
            w.send_pdv(conn,context,True,terminal)
        elif operation in [0x10,0x21]:
            # Counters represent a controlled peer report; this peer does not do stores.
            counts=[2,1,1,1] if operation==0x21 else [2,0,1,0]
            failed=w.element(0x00080058,'UI','2.25.404.9',explicit)
            terminal=response(sop,message,operation,0xfe00,True,counts)
            w.send_pdv(conn,context,True,terminal);w.send_pdv(conn,context,False,failed)
            prefix.with_suffix('.failed-uids.bin').write_bytes(failed);record['counts']=counts
        else: raise ValueError(f'Unsupported operation {operation}')
        prefix.with_suffix('.terminal.bin').write_bytes(terminal);self.records.append(record);self.save()


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=pathlib.Path);p.add_argument('--seconds',type=int,default=1800);a=p.parse_args()
    a.directory.mkdir(parents=True,exist_ok=True)
    if (a.directory/'ready.json').exists():p.error('Use a fresh directory')
    peer=Peer(a.directory);peer.save();deadline=time.monotonic()+a.seconds
    with socket.socket() as server:
        server.bind(('127.0.0.1',0));server.listen(4);server.settimeout(.5)
        w.save_json(a.directory/'ready.json',{'host':'127.0.0.1','port':server.getsockname()[1],'synthetic':True,'purpose':'Controlled terminal FE00 outcomes, not a cancellation-SCP oracle'})
        while time.monotonic()<deadline and not (a.directory/'stop').exists():
            try:conn,_=server.accept()
            except socket.timeout:continue
            with conn:
                conn.settimeout(30)
                try:peer.handle(conn)
                except Exception as e:peer.errors.append(repr(e));peer.save()
    w.save_json(a.directory/'finished.json',{'clean_stop':True});peer.save()
if __name__=='__main__':main()
