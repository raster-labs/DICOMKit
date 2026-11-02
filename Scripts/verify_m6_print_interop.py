#!/usr/bin/env python3
"""Bounded, synthetic, loopback print qualification with independent peers.

Run with Python 3.9+ and pydicom 2.4 / pynetdicom 2.0 / Pillow installed.
This exercises existing print contracts; it does not qualify physical printing.
Every case retains actual DUL streams, independently decoded DIMSE, argv, logs,
fixture hashes and expected assertions. No DICOMKit encoder is used as oracle.
"""
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
import traceback

import pydicom
from pydicom.dataset import Dataset, FileDataset, FileMetaDataset
from pydicom.filereader import read_dataset
from pydicom.uid import ExplicitVRLittleEndian, ImplicitVRLittleEndian
import pynetdicom
from pynetdicom import AE, evt
from PIL import Image, __version__ as pillow_version

UID = '1.2.840.10008.5.1.1.'
SESSION, BOX, GRAY, COLOR = UID+'1', UID+'2', UID+'4', UID+'4.1'
GRAY_META, COLOR_META = UID+'9', UID+'18'
JOB, ANNOTATION, PRINTER, PRINTER_INSTANCE, LUT = [UID+x for x in ('14','15','16','17','23')]
EXPLICIT, IMPLICIT = str(ExplicitVRLittleEndian), str(ImplicitVRLittleEndian)
BASE = '1.2.826.0.1.3680043.10.543.20261024.6.'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, default=str)+'\n')


class PeerCapabilityUnavailable(Exception):
    """The selected independent peer cannot establish this negative precondition."""


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def wait_for(predicate, timeout=10, message='deadline exceeded'):
    end = time.monotonic()+timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.03)
    raise AssertionError(message)


class Process:
    """File-backed logs; deadline applies before reading output; tracked PID only."""
    def __init__(self, argv, directory, name, env=None):
        self.argv = [str(x) for x in argv]
        self.directory, self.name = Path(directory), name
        self.out_path, self.err_path = self.directory/(name+'.stdout'), self.directory/(name+'.stderr')
        self.out, self.err = self.out_path.open('wb'), self.err_path.open('wb')
        self.start = time.monotonic()
        self.process = subprocess.Popen(self.argv, stdout=self.out, stderr=self.err, env=env)
        self.stopped, self.timed_out = False, False
        save_json(self.directory/(name+'.process.json'), {'argv':self.argv, 'pid':self.process.pid})

    def finish(self, timeout=30):
        try:
            self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.timed_out = True
            self.stop()
            raise AssertionError('%s exceeded %.1fs: %s' % (self.name, timeout, self.argv))
        finally:
            self._record()
        return self.process.returncode

    def _record(self):
        self.out.flush(); self.err.flush()
        save_json(self.directory/(self.name+'.process.json'), {
            'argv':self.argv, 'pid':self.process.pid, 'exit_code':self.process.poll(),
            'elapsed_seconds':time.monotonic()-self.start, 'timed_out':self.timed_out,
            'stopped_by_harness':self.stopped})

    def stop(self):
        if self.process.poll() is None:
            self.stopped = True
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self._record()
        self.out.close(); self.err.close()

    def stdout(self):
        self.out.flush() if not self.out.closed else None
        return self.out_path.read_text(errors='replace')

    def stderr(self):
        self.err.flush() if not self.err.closed else None
        return self.err_path.read_text(errors='replace')


class RecordingProxy:
    """Unmodified TCP forwarding plus independent raw stream recording."""
    def __init__(self, destination, directory):
        self.directory = Path(directory)
        self.directory.mkdir()
        self.destination = destination
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0)); self.listener.listen(8)
        self.listener.settimeout(.2)
        self.port = self.listener.getsockname()[1]
        self.done = threading.Event()
        self.connections, self.workers, self.errors = [], [], []
        self.thread = threading.Thread(target=self._accept, daemon=True)
        self.thread.start()

    def _accept(self):
        while not self.done.is_set():
            try:
                client, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            try:
                server = socket.create_connection(('127.0.0.1', self.destination), timeout=3)
                client.settimeout(.2); server.settimeout(.2)
            except OSError as error:
                self.errors.append(str(error)); client.close(); continue
            index = len(self.connections)
            self.connections.append((client, server))
            for source, target, direction in [(client,server,'c2s'), (server,client,'s2c')]:
                worker = threading.Thread(target=self._copy, args=(source,target,index,direction), daemon=True)
                self.workers.append(worker); worker.start()

    def _copy(self, source, target, index, direction):
        with (self.directory/('%02d-%s.dul' % (index,direction))).open('wb') as stream:
            while not self.done.is_set():
                try:
                    data = source.recv(65536)
                    if not data:
                        break
                    stream.write(data); stream.flush(); target.sendall(data)
                except socket.timeout:
                    continue
                except OSError:
                    break
        try:
            target.shutdown(socket.SHUT_WR)
        except OSError:
            pass

    def close(self):
        # Let the release response and EOF reach the recording workers first.
        for worker in self.workers:
            worker.join(timeout=.5)
        self.done.set(); self.listener.close()
        for pair in self.connections:
            for sock in pair:
                try: sock.shutdown(socket.SHUT_RDWR)
                except OSError: pass
                sock.close()
        self.thread.join(timeout=1)
        for worker in self.workers: worker.join(timeout=1)
        save_json(self.directory/'proxy.json', {'connections':len(self.connections), 'errors':self.errors})


def pdus(raw):
    at = 0
    while at < len(raw):
        require(at+6 <= len(raw), 'truncated PDU header')
        kind, length = raw[at], struct.unpack_from('>I',raw,at+2)[0]
        end = at+6+length
        require(end <= len(raw), 'truncated PDU body')
        yield kind, raw[at+6:end]
        at=end


def items(raw):
    at=0
    while at<len(raw):
        require(at+4<=len(raw), 'truncated association item')
        kind,length=raw[at],struct.unpack_from('>H',raw,at+2)[0]
        require(at+4+length<=len(raw),'truncated association item body')
        yield kind,raw[at+4:at+4+length]
        at+=4+length


def decode_capture(directory):
    """PS3.8 PDU/PDV framing; pydicom decodes command and negotiated dataset VR."""
    directory=Path(directory); messages=[]; associations=[]
    for cpath in sorted(directory.glob('*-c2s.dul')):
        index=cpath.name.split('-')[0]
        paths={'c2s':cpath,'s2c':directory/(index+'-s2c.dul')}
        streams={k:list(pdus(p.read_bytes())) for k,p in paths.items()}
        requested={}; accepted={}; pdu_types={k:[t for t,_ in v] for k,v in streams.items()}
        for kind,body in streams['c2s']:
            if kind==1:
                for itype,payload in items(body[68:]):
                    if itype==0x20:
                        sub=list(items(payload[4:]))
                        requested[payload[0]]={'abstract':next(x.decode() for t,x in sub if t==0x30),
                                              'offered':[x.decode() for t,x in sub if t==0x40]}
        for kind,body in streams['s2c']:
            if kind==2:
                for itype,payload in items(body[68:]):
                    if itype==0x21:
                        transfer=next((x.decode() for t,x in items(payload[4:]) if t==0x40),None)
                        accepted[payload[0]]={**requested.get(payload[0],{}),'result':payload[2],'transfer':transfer}
        association={'index':index,'contexts':accepted,'pdu_types':pdu_types}
        associations.append(association)
        for direction,stream in streams.items():
            pending={}; command_bytes={}; data_bytes={}
            for kind,body in stream:
                if kind!=4: continue
                at=0
                while at<len(body):
                    size=struct.unpack_from('>I',body,at)[0]
                    require(size>=2 and at+4+size<=len(body),'invalid PDV length')
                    context,flags=body[at+4],body[at+5]; chunk=body[at+6:at+4+size]; at+=4+size
                    target=command_bytes if flags&1 else data_bytes
                    target.setdefault(context,bytearray()).extend(chunk)
                    if not flags&2: continue
                    raw=bytes(target.pop(context))
                    if flags&1:
                        require(context not in pending,'overlapping DIMSE dataset')
                        cmd=read_dataset(io.BytesIO(raw),True,True)
                        record={'association':index,'direction':direction,'context':context,
                                'abstract':accepted.get(context,{}).get('abstract'),
                                'transfer':accepted.get(context,{}).get('transfer'),
                                'command':cmd,'data':None,'command_raw':raw,'data_raw':b''}
                        if int(cmd.CommandDataSetType)==0x0101: messages.append(record)
                        else: pending[context]=record
                    else:
                        require(context in pending,'dataset without command')
                        record=pending.pop(context); record['data_raw']=raw
                        record['data']=read_dataset(io.BytesIO(raw),record['transfer']==IMPLICIT,True)
                        messages.append(record)
            require(not pending and not command_bytes and not data_bytes,'incomplete DIMSE message')
    decoded=[]
    for i,record in enumerate(messages):
        prefix=directory/('message-%03d'%i)
        Path(str(prefix)+'.command.bin').write_bytes(record['command_raw'])
        if record['data_raw']: Path(str(prefix)+'.dataset.bin').write_bytes(record['data_raw'])
        decoded.append({k:v for k,v in record.items() if k not in ('command_raw','data_raw','command','data')})
        decoded[-1].update(command=json.loads(record['command'].to_json()),
                          dataset=json.loads(record['data'].to_json()) if record['data'] is not None else None)
    save_json(directory/'decoded.json',{'associations':associations,'messages':decoded})
    return messages,associations


def command_class(record, messages):
    command=record['command']
    value=command.get('RequestedSOPClassUID',command.get('AffectedSOPClassUID'))
    if value is not None:return str(value)
    # PS3.7 response SOP Class UID is optional for these N-services. Infer it
    # only from a uniquely correlated request, never from the meta context UID.
    field=int(command.CommandField)
    if field&0x8000:
        requests=[r for r in messages if r['association']==record['association']
                  and r['direction']!=record['direction'] and int(r['command'].CommandField)==field&0x7FFF
                  and int(r['command'].get('MessageID',-1))==int(command.MessageIDBeingRespondedTo)]
        if len(requests)==1:return command_class(requests[0],messages)
    return None


def operation(messages, field, sop=None, direction=None):
    return [r for r in messages if int(r['command'].CommandField)==field
            and (sop is None or command_class(r,messages)==sop)
            and (direction is None or r['direction']==direction)]


def assert_correlations(messages):
    for response in messages:
        cmd=response['command']; field=int(cmd.CommandField)
        if not field&0x8000: continue
        requests=[r for r in messages if r['association']==response['association']
                  and r['direction']!=response['direction'] and int(r['command'].CommandField)==field&0x7FFF
                  and int(r['command'].get('MessageID',-1))==int(cmd.MessageIDBeingRespondedTo)]
        require(len(requests)==1,'response has no unique matching request')
        request=requests[0]
        require(request['context']==response['context'],'response context differs from request')
        for affected,requested in [('AffectedSOPClassUID','RequestedSOPClassUID'),('AffectedSOPInstanceUID','RequestedSOPInstanceUID')]:
            expected=request['command'].get(requested,request['command'].get(affected))
            actual=cmd.get(affected)
            if expected is not None and actual is not None:
                require(str(actual)==str(expected),'response %s differs from request'%affected)


def assert_release(associations):
    accepted=[a for a in associations if 2 in a['pdu_types']['s2c']]
    require(accepted,'no accepted association captured')
    for a in accepted:
        require(5 in a['pdu_types']['c2s'] and 6 in a['pdu_types']['s2c'],'normal release missing')
        require(7 not in a['pdu_types']['c2s']+a['pdu_types']['s2c'],'unexpected abort')


def assert_closed(associations):
    accepted=[a for a in associations if 2 in a['pdu_types']['s2c']]
    require(accepted,'no accepted association captured')
    for association in accepted:
        types=association['pdu_types']
        require((5 in types['c2s'] and 6 in types['s2c']) or 7 in types['c2s']+types['s2c'],
                'association neither released nor aborted')


def assert_flow(messages, image_class=GRAY):
    for field,sop in [(0x140,SESSION),(0x140,BOX),(0x120,image_class),(0x130,BOX),(0x150,SESSION)]:
        require(operation(messages,field,sop),'missing operation %04X %s'%(field,sop))
    actions=operation(messages,0x130,BOX)
    require(len(actions)==1,'exactly one print action expected (no duplicate printing)')


def assert_pixels(messages, fixture, color=False, exact=True, bits=None):
    requests=operation(messages,0x120,COLOR if color else GRAY)
    require(len(requests)==1,'expected one image-box N-SET')
    data=requests[0]['data']; seq=data.BasicColorImageSequence if color else data.BasicGrayscaleImageSequence
    require(len(seq)==1,'pixel sequence must have one item'); image=seq[0]
    expected=pydicom.dcmread(fixture)
    for key,value in {'Rows':16,'Columns':16,'SamplesPerPixel':3 if color else 1,
                      'BitsStored':bits or int(expected.BitsStored),'PixelRepresentation':0}.items():
        require(int(image.get(key,-1))==value,'unexpected image '+key)
    require(int(image.BitsAllocated)==(16 if int(image.BitsStored)==12 else 8),'wrong BitsAllocated')
    require(int(image.HighBit)==int(image.BitsStored)-1,'wrong HighBit')
    require(image['Rows'].VR=='US' and image['BitsStored'].VR=='US','incorrect numeric pixel VR')
    if color:
        require(str(image.PhotometricInterpretation)=='RGB' and int(image.PlanarConfiguration)==1,'color wire must be planar RGB')
        raw=bytes(image.PixelData); interleaved=bytes(raw[c*256+i] for i in range(256) for c in range(3))
        if exact: require(interleaved==bytes(expected.PixelData),'RGB samples changed')
    elif exact:
        require(bytes(image.PixelData)==bytes(expected.PixelData),'grayscale raw pixels changed')
    return image


def make_fixtures(directory):
    directory.mkdir()
    result={}
    for index,(name,bits,samples) in enumerate([('gray8',8,1),('gray12',12,1),('rgb8',8,3)],1):
        meta=FileMetaDataset(); meta.MediaStorageSOPClassUID='1.2.840.10008.5.1.4.1.1.7'
        meta.MediaStorageSOPInstanceUID=BASE+str(index); meta.TransferSyntaxUID=EXPLICIT
        meta.ImplementationClassUID=BASE+'900'
        path=directory/(name+'.dcm'); ds=FileDataset(str(path),{},file_meta=meta,preamble=b'\0'*128)
        ds.is_little_endian=True; ds.is_implicit_VR=False
        ds.SOPClassUID=meta.MediaStorageSOPClassUID; ds.SOPInstanceUID=meta.MediaStorageSOPInstanceUID
        ds.PatientName='SYNTHETIC^PRINT'; ds.PatientID='M6-PRINT'; ds.PatientBirthDate=''; ds.PatientSex=''
        ds.StudyInstanceUID=BASE+'100'; ds.SeriesInstanceUID=BASE+'101'; ds.StudyID='M6'
        ds.StudyDate='20261024'; ds.StudyTime='120000'; ds.SeriesNumber=1; ds.InstanceNumber=index
        ds.AccessionNumber='M6-SYNTHETIC'; ds.ReferringPhysicianName=''; ds.Modality='OT'; ds.ConversionType='WSD'
        ds.Manufacturer='SYNTHETIC'; ds.ImageType=['DERIVED','SECONDARY']; ds.BurnedInAnnotation='NO'
        ds.Rows=16; ds.Columns=16; ds.SamplesPerPixel=samples
        ds.PhotometricInterpretation='RGB' if samples==3 else 'MONOCHROME2'
        ds.BitsAllocated=16 if bits==12 else 8; ds.BitsStored=bits; ds.HighBit=bits-1; ds.PixelRepresentation=0
        if samples==3:
            ds.PlanarConfiguration=0
            pixels=bytes(c for y in range(16) for x in range(16) for c in (x*17,y*17,((x+y)%16)*17))
        elif bits==12: pixels=b''.join(struct.pack('<H',round(i*4095/255)) for i in range(256))
        else: pixels=bytes(range(256))
        ds.PixelData=pixels; ds.save_as(path,write_like_original=False)
        check=pydicom.dcmread(path)
        require(bytes(check.PixelData)==pixels and check.SOPInstanceUID.is_valid,'independent fixture roundtrip failed')
        result[name]=path
    save_json(directory/'manifest.json',{name:{'path':str(path),'sha256':sha(path),'pixel_sha256':hashlib.sha256(pydicom.dcmread(path).PixelData).hexdigest()} for name,path in result.items()})
    return result


def reference(sop, instance):
    ds=Dataset(); ds.ReferencedSOPClassUID=sop; ds.ReferencedSOPInstanceUID=instance; return ds


class IndependentSCP:
    """Small independent normalized DIMSE oracle, not a physical-printer emulator."""
    def __init__(self, directory, color=False, annotation=False, lut=True, job=False,
                 fail_set=False, printer_status='NORMAL', action_warning=False, event=False, both=False):
        self.directory=directory; self.color=color; self.annotation=annotation; self.lut=lut; self.job=job
        self.fail_set=fail_set; self.printer_status=printer_status; self.action_warning=action_warning; self.event=event
        self.records=[]; self.event_acks=[]; self.next_uid=1000; self.images={}
        self.ae=AE(ae_title='PYM6'); self.ae.acse_timeout=5; self.ae.dimse_timeout=8; self.ae.network_timeout=10
        self.ae.add_supported_context(COLOR_META if color else GRAY_META,[EXPLICIT,IMPLICIT])
        if both:self.ae.add_supported_context(GRAY_META if color else COLOR_META,[EXPLICIT,IMPLICIT])
        if annotation:self.ae.add_supported_context(ANNOTATION,[EXPLICIT,IMPLICIT])
        if lut:self.ae.add_supported_context(LUT,[EXPLICIT,IMPLICIT])
        if job:self.ae.add_supported_context(JOB,[IMPLICIT])
        handlers=[(evt.EVT_N_CREATE,self.create),(evt.EVT_N_SET,self.set),
                  (evt.EVT_N_ACTION,self.action),(evt.EVT_N_GET,self.get),
                  (evt.EVT_N_DELETE,self.delete)]
        self.server=self.ae.start_server(('127.0.0.1',0),block=False,evt_handlers=handlers)
        self.port=self.server.server_address[1]

    def uid(self):
        self.next_uid+=1; return BASE+str(self.next_uid)

    def record(self, event, dataset=None):
        req=event.request
        self.records.append({'operation':type(req).__name__,'class':str(getattr(req,'AffectedSOPClassUID',None) or getattr(req,'RequestedSOPClassUID','')),
                             'context':event.context.context_id,'dataset':json.loads(dataset.to_json()) if dataset is not None else None})

    def create(self,event):
        data=event.attribute_list; self.record(event,data); req=event.request
        sop=str(req.AffectedSOPClassUID); uid=str(req.AffectedSOPInstanceUID or self.uid())
        status=Dataset(); status.Status=0; status.AffectedSOPInstanceUID=uid
        response=Dataset()
        if sop==BOX:
            require(str(data.ReferencedFilmSessionSequence[0].ReferencedSOPClassUID)==SESSION,'film session reference class')
            # One image is sufficient for these deliberately single-cell cases.
            image_uid=self.uid(); self.images[image_uid]=None
            response.ReferencedImageBoxSequence=[reference(COLOR if str(event.context.abstract_syntax)==COLOR_META else GRAY,image_uid)]
            if self.annotation and 'AnnotationDisplayFormatID' in data:
                response.ReferencedBasicAnnotationBoxSequence=[reference(ANNOTATION,self.uid()),reference(ANNOTATION,self.uid())]
        elif sop==LUT:
            require(str(data.PresentationLUTShape) in ('IDENTITY','LIN OD'),'illegal Presentation LUT shape')
        elif sop!=SESSION:
            status.Status=0x0122
        return status,response

    def set(self,event):
        data=event.modification_list; self.record(event,data)
        if self.fail_set:
            status=Dataset(); status.Status=0x0106; status.ErrorComment='M6 INJECTED SET FAILURE'; return status,None
        return 0, None

    def action(self,event):
        self.record(event,event.action_information)
        response=Dataset()
        if self.job:
            self.job_uid=BASE+'2000'
            # PS3.4 2026a H.4.1/H.4.2 Action Reply explicitly uses (2100,0500).
            # pydicom's similarly named current keyword instead selects (2120,0070).
            response.add_new(0x21000500,'SQ',[reference(JOB,self.job_uid)])
            if self.event:
                information=Dataset(); information.ExecutionStatusInfo='NORMAL'
                information.PrinterName='M6 SYNTHETIC'; information.FilmSessionLabel='M6'
                status,_=event.assoc.send_n_event_report(information,3,JOB,self.job_uid,msg_id=711)
                self.event_acks.append(int(status.get('Status',-1)))
        return (0xB604 if self.action_warning else 0),response

    def get(self,event):
        self.record(event); sop=str(event.request.RequestedSOPClassUID); data=Dataset()
        if sop==PRINTER:
            data.PrinterStatus=self.printer_status; data.PrinterStatusInfo='NORMAL' if self.printer_status=='NORMAL' else 'SUPPLY LOW'
            data.PrinterName='M6 SYNTHETIC'; data.Manufacturer='INDEPENDENT PYNETDICOM'
        elif sop==JOB:
            data.ExecutionStatus='DONE'; data.ExecutionStatusInfo='NORMAL'; data.PrintPriority='MED'; data.PrinterName='M6 SYNTHETIC'
            data.CreationDate='20261024'; data.CreationTime='120000'; data.Originator='M6DKSCU'
        else: return 0x0122,None
        return 0,data

    def delete(self,event): self.record(event); return 0

    def close(self):
        self.server.shutdown(); self.ae.shutdown()
        save_json(self.directory/'independent-peer.json',{'records':self.records,'event_acks':self.event_acks})

class Case:
    def __init__(self, runner, identifier, title):
        self.runner=runner; self.identifier=identifier; self.title=title
        self.directory=runner.output/identifier; self.directory.mkdir()
        self.observations={}; self.processes=[]

    def run(self, argv, name='client', expect=0, timeout=35):
        process=Process(argv,self.directory,name,self.runner.env); self.processes.append(process)
        code=process.finish(timeout)
        if expect==0: require(code==0,'%s failed (%s): %s'%(name,code,process.stderr()[-4000:]))
        elif expect=='nonzero': require(code!=0,'%s unexpectedly succeeded'%name)
        return process

    def cli(self, port, fixture='gray8', extra=(), expect=0, subcommand='send', name='client'):
        argv=[self.runner.bin/'dicom-print',subcommand,'pacs://127.0.0.1:%s'%port]
        if subcommand=='send': argv += [self.runner.fixtures[fixture], '--layout','1x1','--film-size','8x10','--raw']
        argv+=['--aet','M6DKSCU','--called-aet','DCMTK_M6' if self.identifier.startswith('DC-F') else 'PYM6',
               '--timeout','8','--format','json']+list(extra)
        return self.run(argv,name,expect)

    def capture(self, proxy):
        proxy.close(); messages,associations=decode_capture(proxy.directory)
        require(not proxy.errors,'TCP proxy error: '+repr(proxy.errors))
        assert_correlations(messages)
        self.observations['accepted_contexts']=[a['contexts'] for a in associations]
        self.observations['dimse_messages']=len(messages)
        return messages,associations

    @contextlib.contextmanager
    def independent(self, **kwargs):
        peer=IndependentSCP(self.directory,**kwargs)
        proxy=RecordingProxy(peer.port,self.directory/'wire')
        try: yield peer,proxy
        finally:
            proxy.close(); peer.close()

    @contextlib.contextmanager
    def kit_scp(self, extra=()):
        port=free_port(); config=self.directory/'empty-config.json'; config.write_text('{}\n')
        films=self.directory/'films'; films.mkdir()
        argv=[self.runner.bin/'dicom-printscp','serve','--config',config,'--port',str(port),
              '--ae-title','DCMKIT_M6','--output','png','--output-dir',films,'--dpi','36',
              '--max-pixels','1024','--duration','90','--format','json','--verbose']+list(extra)
        process=Process(argv,self.directory,'receiver',self.runner.env); self.processes.append(process)
        def ready():
            require(process.process.poll() is None,'receiver exited: '+process.stderr()[-3000:])
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.2): return True
            except OSError: return False
        wait_for(ready,message='DICOMKit receiver did not bind')
        proxy=RecordingProxy(port,self.directory/'wire')
        try: yield proxy,films
        finally: proxy.close(); process.stop()

    def films(self, directory, expected=1):
        paths=sorted(directory.glob('*.png'))
        require(len(paths)==expected,'expected %s saved PNG film(s), found %s'%(expected,len(paths)))
        for path in paths:
            with Image.open(path) as image:
                image.load()
                require(image.width>0 and image.height>0,'empty composed film')
                require(image.width<=1024 and image.height<=1024,'film exceeded configured bound')
                extrema=image.getextrema()
                require(any(a!=b for a,b in extrema) if isinstance(extrema[0],tuple) else extrema[0]!=extrema[1],
                        'composed image has no varying pixels')
        self.observations['films']=[{'file':p.name,'sha256':sha(p)} for p in paths]

    def cleanup(self):
        for process in reversed(self.processes):
            if not process.out.closed: process.stop()


def dcmtk_config(case, port, local, implicit=False, lut=True, bits12=True, annotation=False):
    root=case.directory/'dcmtk'
    for name in ('logs','spool','database'): (root/name).mkdir(parents=True)
    text='''[[GENERAL]]
[APPLICATION]
LogDirectory={root}/logs
LogFile=application.log
LogLevel=DEBUG
MessagePort=0
[PRINT]
Spooler={tools}/dcmprscu
Server={tools}/dcmprscp
Directory={root}/spool
DetailedLog=true
BinaryLog=true
DeletePrintJobs=false
MinPrintResolution=16\\16
MaxPrintResolution=512\\512
[DATABASE]
Directory={root}/database
[NETWORK]
Aetitle=M6DCMTK
[[COMMUNICATION]]
[M6]
Type={kind}
Hostname=127.0.0.1
Aetitle={aet}
Port={port}
Protocol=AF_INET
Timeout=8
MaxPDU=32768
ImplicitOnly={implicit}
DisableNewVRs=false
UseTLS=false
DisplayFormat=1,1\\2,1\\1,2\\2,2
FilmSizeID=8INX10IN\\14INX17IN
MediumType=PAPER\\CLEAR FILM\\BLUE FILM
FilmDestination=MAGAZINE\\PROCESSOR\\BIN_1
MagnificationType=REPLICATE\\BILINEAR\\CUBIC\\NONE
SmoothingType=NONE
BorderDensity=BLACK\\WHITE\\150
EmptyImageDensity=BLACK\\WHITE\\20
MaxDensity=320
MinDensity=20
Supports12Bit={bits12}
SupportsPresentationLUT={lut}
PresentationLUTMatchRequired=false
PresentationLUTinFilmSession=false
PresentationLUTPreferSCPRendering=true
SupportsImageSize=true
SupportsDecimateCrop=true
SupportsTrim=true
OmitSOPClassUIDFromCreateResponse=false
'''.format(root=root,tools=case.runner.dcmtk,kind='LOCALPRINTER' if local else 'PRINTER',
           aet='DCMTK_M6' if local else 'DCMKIT_M6',port=port,implicit=str(implicit).lower(),
           bits12=str(bits12).lower(),lut=str(lut).lower())
    if annotation:text+='Annotation=1\\ANNOTATION\n'
    path=case.directory/'dcmtk.cfg'; path.write_text(text); return path


def dc_forward(case, fixture='gray8', implicit=False, shape=None, no_lut=False, status=False):
    port=free_port(); config=dcmtk_config(case,port,True,implicit=implicit,lut=not no_lut)
    server=Process([case.runner.dcmtk/'dcmprscp','--config',config,'--printer','M6','--dump','--log-level','trace'],
                   case.directory,'dcmtk-server',case.runner.env)
    case.processes.append(server)
    def ready():
        require(server.process.poll() is None,'DCMTK SCP startup failed: '+server.stderr()[-2000:])
        try:
            with socket.create_connection(('127.0.0.1',port),timeout=.2):return True
        except OSError:return False
    wait_for(ready,message='DCMTK SCP did not bind')
    proxy=RecordingProxy(port,case.directory/'wire')
    try:
        if no_lut:
            case.cli(proxy.port,subcommand='status',name='capability-probe')
            _,probe_associations=decode_capture(proxy.directory)
            if any(context.get('abstract')==LUT and context.get('result')==0
                   for association in probe_associations for context in association['contexts'].values()):
                case.observations['configured_lut_support']=False
                case.observations['observed_lut_context_accepted']=True
                raise PeerCapabilityUnavailable('DCMTK3.7 accepts LUT despite SupportsPresentationLUT=false; refusal not qualified with this peer. PY-F08 supplies independent rejection coverage.')
        result=case.cli(proxy.port,fixture,extra=['--presentation-lut',shape] if shape else [],
                        expect='nonzero' if no_lut else 0,subcommand='status' if status else 'send')
    finally:
        messages,associations=case.capture(proxy); server.stop()
    if status:
        require(operation(messages,0x110,PRINTER),'Printer N-GET missing')
        require(operation(messages,0x8110,PRINTER)[0]['data'].PrinterStatus=='NORMAL','unexpected Printer status')
        case.observations['cli_json']=json.loads(result.stdout())
    elif no_lut:
        require(not operation(messages,0x130),'unsupported required LUT must not print')
        require('LUT' in result.stderr().upper() or 'LUT' in result.stdout().upper(),'missing LUT refusal diagnostic')
    else:
        assert_flow(messages); assert_pixels(messages,case.runner.fixtures[fixture])
        if shape:
            creates=operation(messages,0x140,LUT)
            require(len(creates)==1 and creates[0]['data'].PresentationLUTShape==('LIN OD' if shape=='lin-od' else 'IDENTITY'),'incorrect LUT shape')
            # H.4.9.2.1.3 and H.5 allow LUT lifetime through association closure.
            case.observations['lut_cleanup']='explicit N-DELETE' if operation(messages,0x150,LUT) else 'association release'
            created_uid=str(operation(messages,0x8140,LUT)[0]['command'].AffectedSOPInstanceUID)
            box=operation(messages,0x140,BOX)[0]['data']
            require(str(box.ReferencedPresentationLUTSequence[0].ReferencedSOPClassUID)==LUT,'film does not reference LUT')
            require(str(box.ReferencedPresentationLUTSequence[0].ReferencedSOPInstanceUID)==created_uid,'film references wrong LUT instance')
        require(json.loads(result.stdout()).get('success') is True,'CLI JSON success contract')
    if implicit:
        require(all(r['transfer']==IMPLICIT for r in messages),'implicit-only negotiation not honored')
    assert_release(associations)
    stored=[]
    for path in (case.directory/'dcmtk'/'database').rglob('*'):
        if not path.is_file():continue
        try:
            ds=pydicom.dcmread(path)
            stored.append({'file':str(path.relative_to(case.directory)),'class':str(ds.SOPClassUID),'sha256':sha(path)})
        except Exception:pass
    if not status and not no_lut: require(stored,'DCMTK produced no independently readable Stored Print/hardcopy object')
    case.observations['dcmtk_stored_objects']=stored


def dc_reverse(case, bits12=True, implicit=False, shape=None, annotation=False):
    flags=['--no-accept-color','--presentation-lut','--annotation-box']
    with case.kit_scp(flags) as (proxy,films):
        config=dcmtk_config(case,proxy.port,False,implicit=implicit,bits12=bits12,annotation=annotation)
        args=[case.runner.dcmtk/'dcmpsprt','--config',config,'--printer','M6','--nospool',
              '--layout','1','1','--filmsize','8INX10IN','--portrait']
        if shape:args+=['--'+shape]
        args+=(['--annotation','M6 SYNTHETIC','--print-no-date','--print-no-name','--print-no-lighting'] if annotation else ['--no-annotation'])
        args+=[case.runner.fixtures['gray8']]
        case.run(args,'render')
        stored=[]
        for path in (case.directory/'dcmtk'/'database').rglob('*'):
            if path.is_file():
                try:
                    if str(pydicom.dcmread(path,stop_before_pixels=True).SOPClassUID)==UID+'27':stored.append(path)
                except Exception:pass
        require(len(stored)==1,'must identify exactly one Stored Print by SOP Class')
        case.run([case.runner.dcmtk/'dcmprscu','--config',config,'--printer','M6','--dump','--log-level','trace',
                  '--copies','1','--medium-type','PAPER','--destination','PROCESSOR',stored[0]],'dcmtk-client')
        wait_for(lambda:len(list(films.glob('*.png')))==1,message='no saved film from independent SCU')
    messages,associations=decode_capture(proxy.directory); assert_correlations(messages); assert_release(associations)
    assert_flow(messages)
    pixel=operation(messages,0x120,GRAY)[0]['data'].BasicGrayscaleImageSequence[0]
    require(int(pixel.BitsStored)==(12 if bits12 else 8),'DCMTK did not send expected depth')
    require(int(pixel.BitsAllocated)==(16 if bits12 else 8) and int(pixel.PixelRepresentation)==0,'illegal grayscale pixel module')
    require(0<int(pixel.Rows)<=512 and 0<int(pixel.Columns)<=512,'unexpected DCMTK render dimensions')
    require(len(set(bytes(pixel.PixelData)))>1,'independent grayscale payload empty/uniform')
    if implicit:require(all(r['transfer']==IMPLICIT for r in messages),'reverse implicit VR was not negotiated')
    if shape:
        lut=operation(messages,0x140,LUT)
        require(lut and lut[0]['data'].PresentationLUTShape==('LIN OD' if shape=='lin-od' else 'IDENTITY'),'reverse LUT not sent')
    if annotation:
        notes=operation(messages,0x120,ANNOTATION)
        require(len(notes)==1 and notes[0]['data'].TextString=='M6 SYNTHETIC','annotation text changed/missing')
        require(int(notes[0]['data'].AnnotationPosition)==1,'annotation position changed')
        require(notes[0]['abstract']==ANNOTATION,'annotation not on separately negotiated context')
    case.films(films)
    case.observations.update(dimse_messages=len(messages),accepted_contexts=[a['contexts'] for a in associations],
                             received_bits=int(pixel.BitsStored),received_size=[int(pixel.Columns),int(pixel.Rows)])


def py_forward(case, mode):
    options={}; extra=[]; fixture='gray8'; expect=0
    if mode=='color': options['color']=True; extra=['--color','color']; fixture='rgb8'
    if mode=='annotation':options['annotation']=True; extra=['--annotation-format','M6','--annotate','M6 FIRST','--annotate','M6 SECOND']
    if mode=='set-failure':options['fail_set']=True; expect='nonzero'
    if mode=='no-lut':options['lut']=False; extra=['--presentation-lut','identity']; expect='nonzero'
    if mode in ('printer-failure','printer-warning'):
        options['printer_status']='FAILURE' if mode=='printer-failure' else 'WARNING'; extra=['--check-status']
        if mode=='printer-failure':expect='nonzero'
    if mode=='action-warning':options['action_warning']=True
    if mode=='job-event':options.update(job=True,event=True)
    with case.independent(**options) as (peer,proxy):
        result=case.cli(proxy.port,fixture,extra=extra,expect=expect)
        if mode=='job-event':
            require(peer.event_acks==[0],'Done event did not receive successful ACK while action pending')
            job_uid=json.loads(result.stdout()).get('printJobUID')
            require(job_uid==BASE+'2000','wrong Print Job UID')
            case.cli(proxy.port,extra=['--job-id',job_uid],subcommand='job',name='job-client')
    messages,associations=decode_capture(proxy.directory); assert_correlations(messages)
    if expect=='nonzero':
        assert_closed(associations)
        require(not operation(messages,0x130),'failed preflight/N-SET unexpectedly performed print action')
        if mode=='set-failure':
            require(operation(messages,0x150,SESSION),'failure cleanup did not delete session')
            require('M6 INJECTED SET FAILURE' in result.stderr(),'N-SET diagnostic not surfaced')
        if mode=='no-lut':
            require(not operation(messages,0x140,LUT),'unaccepted optional LUT must not be used via meta context')
            require(any(c.get('abstract')==LUT and c.get('result')!=0 for a in associations for c in a['contexts'].values()),'LUT refusal precondition was not established')
            require('LUT' in (result.stderr()+result.stdout()).upper() or LUT in result.stderr(),
                    'required LUT refusal must identify Presentation LUT by name or exact SOP Class UID')
    else:
        assert_release(associations)
        assert_flow(messages,COLOR if mode=='color' else GRAY)
        assert_pixels(messages,case.runner.fixtures[fixture],color=mode=='color')
        require(json.loads(result.stdout()).get('success') is True,'successful/warning job not reported successful')
    if mode=='annotation':
        annotations=operation(messages,0x120,ANNOTATION)
        require([(int(r['data'].AnnotationPosition),str(r['data'].TextString)) for r in annotations]==[(1,'M6 FIRST'),(2,'M6 SECOND')],'annotation order/text changed')
        require(all(r['abstract']==ANNOTATION for r in annotations),'annotation context not independent')
    if mode in ('action-warning','printer-warning'):
        require('warn' in (result.stdout()+result.stderr()).lower(),'warning not surfaced')
    if mode=='job-event':
        events=operation(messages,0x100,JOB,'s2c'); acks=operation(messages,0x8100,JOB,'c2s')
        require(len(events)==len(acks)==1,'event/ACK missing')
        require(events[0]['abstract']==JOB and events[0]['transfer']==IMPLICIT,'event context/VR mismatch')
        require(int(events[0]['command'].EventTypeID)==3,'Done event type must be 3')
        require(int(acks[0]['command'].Status)==0,'event ACK failure')
        require(len(operation(messages,0x110,JOB))==1,'second-association Job N-GET missing')
    case.observations.update(dimse_messages=len(messages),accepted_contexts=[a['contexts'] for a in associations])


def connect_independent(port, events, with_job=True):
    ae=AE(ae_title='PYM6SCU'); ae.acse_timeout=5; ae.dimse_timeout=8; ae.network_timeout=10
    ae.add_requested_context(COLOR_META,[EXPLICIT])
    if with_job:ae.add_requested_context(JOB,[IMPLICIT])
    def on_event(event):
        info=event.event_information
        events.append({'class':str(event.request.AffectedSOPClassUID),'instance':str(event.request.AffectedSOPInstanceUID),
                       'event_type':int(event.request.EventTypeID),'context':event.context.context_id,
                       'transfer':str(event.context.transfer_syntax),'dataset':json.loads(info.to_json())})
        return 0,None
    association=ae.associate('127.0.0.1',port,ae_title='DCMKIT_M6',evt_handlers=[(evt.EVT_N_EVENT_REPORT,on_event)])
    require(association.is_established,'independent SCU association rejected')
    return ae,association


def py_reverse(case, invalid=False, with_job=True, push_events=True):
    events=[]; job_uid=None
    with case.kit_scp(['--accept-color']+(['--push-job-events'] if push_events else [])) as (proxy,films):
        ae,assoc=connect_independent(proxy.port,events,with_job)
        try:
            session=Dataset();session.NumberOfCopies='1';session.PrintPriority='MED';session.MediumType='PAPER';session.FilmDestination='PROCESSOR'
            status,_=assoc.send_n_create(session,SESSION,BASE+'3000',msg_id=1,meta_uid=COLOR_META)
            require(status.Status==0,'session create failed')
            box=Dataset();box.ImageDisplayFormat='STANDARD\\1,1';box.FilmOrientation='PORTRAIT';box.FilmSizeID='8INX10IN';box.MagnificationType='REPLICATE'
            box.ReferencedFilmSessionSequence=[reference(SESSION,BASE+'3000')]
            status,response=assoc.send_n_create(box,BOX,BASE+'3001',msg_id=2,meta_uid=COLOR_META)
            require(status.Status==0,'box create failed')
            image_uid=str(response.ReferencedImageBoxSequence[0].ReferencedSOPInstanceUID)
            image=pydicom.dcmread(case.runner.fixtures['rgb8'])
            pixels=Dataset()
            for key in ['Rows','Columns','SamplesPerPixel','PhotometricInterpretation','BitsAllocated','BitsStored','HighBit','PixelRepresentation']:
                pixels.add(image[key])
            pixels.PlanarConfiguration=2 if invalid else 1
            raw=bytes(image.PixelData); pixels.PixelData=b''.join(raw[c::3] for c in range(3))
            data=Dataset();data.ImageBoxPosition=1;data.BasicColorImageSequence=[pixels]
            status,_=assoc.send_n_set(data,COLOR,image_uid,msg_id=3,meta_uid=COLOR_META)
            if invalid:
                require(int(status.Status)==0x0106,'invalid planar configuration must receive Invalid Attribute Value (0106)')
            else:
                require(status.Status==0,'color N-SET failed')
                status,response=assoc.send_n_action(None,1,BOX,BASE+'3001',msg_id=4,meta_uid=COLOR_META)
                require(status.Status==0,'color print action failed')
                job_uid=str(response[0x21000500].value[0].ReferencedSOPInstanceUID)
                if with_job and push_events:wait_for(lambda:len(events)==1,timeout=5,message='Done event missing')
                else:
                    time.sleep(.1); require(not events,'event sent without optional Print Job context or push enabled')
            require(assoc.send_n_delete(BOX,BASE+'3001',msg_id=5,meta_uid=COLOR_META).Status==0,'box delete failed')
            require(assoc.send_n_delete(SESSION,BASE+'3000',msg_id=6,meta_uid=COLOR_META).Status==0,'session delete failed')
            assoc.release()
            if job_uid and with_job:
                ae2,second=connect_independent(proxy.port,events,True)
                try:
                    status,response=second.send_n_get([0x21000020,0x21000030],JOB,job_uid,msg_id=20)
                    if push_events:
                        # H.4.5.2.1.2: confirmed Done event deletes the Print Job.
                        require(int(status.Status)==0x0112,'terminal-ACKed job should be deleted')
                    else:
                        require(status.Status==0 and response.ExecutionStatus=='DONE','unacknowledged job not retained across associations')
                        require(response.ExecutionStatusInfo=='NORMAL','job status info wrong')
                    second.release()
                finally:
                    if second.is_established:second.abort()
                    ae2.shutdown()
            if not invalid:wait_for(lambda:len(list(films.glob('*.png')))==1,message='color film not saved')
        finally:
            if assoc.is_established:assoc.abort()
            ae.shutdown()
    messages,associations=decode_capture(proxy.directory); assert_correlations(messages); assert_release(associations)
    if invalid:
        require(not operation(messages,0x130),'invalid image must not be printed')
        require(not list(films.glob('*.png')),'invalid image produced film')
    else:
        assert_flow(messages,COLOR); assert_pixels(messages,case.runner.fixtures['rgb8'],color=True)
        case.films(films)
        wire_events=operation(messages,0x100,JOB,'s2c')
        if with_job and push_events:
            require(len(wire_events)==1 and wire_events[0]['abstract']==JOB,'event not on Print Job context')
            require(wire_events[0]['transfer']==IMPLICIT,'event did not honor distinct implicit Job context')
            require(int(wire_events[0]['command'].EventTypeID)==3,'terminal event type must be Done (3)')
            require(wire_events[0]['data']['ExecutionStatusInfo'].VR=='CS','event dataset incorrectly encoded')
            require(len(operation(messages,0x8100,JOB,'c2s'))==1,'independent SCU did not ACK event')
            require(len(operation(messages,0x110,JOB))==1,'independent second-association N-GET missing')
        else:require(not wire_events,'event sent despite absent context or disabled push')
        if with_job:require(len(operation(messages,0x110,JOB))==1,'independent second-association N-GET missing')
    save_json(case.directory/'independent-events.json',events)
    case.observations.update(dimse_messages=len(messages),accepted_contexts=[a['contexts'] for a in associations],job_uid=job_uid)


CASES=[
 ('DC-F01','DICOMKit SCU to DCMTK: Printer status',lambda c:dc_forward(c,status=True)),
 ('DC-F02','DICOMKit SCU to DCMTK: exact raw grayscale 8-bit',lambda c:dc_forward(c)),
 ('DC-F03','DICOMKit SCU to DCMTK: exact raw grayscale 12-bit',lambda c:dc_forward(c,fixture='gray12')),
 ('DC-F04','DICOMKit SCU to DCMTK: implicit VR',lambda c:dc_forward(c,implicit=True)),
 ('DC-F05','DICOMKit SCU to DCMTK: IDENTITY Presentation LUT',lambda c:dc_forward(c,shape='identity')),
 ('DC-F06','DICOMKit SCU to DCMTK: LIN OD Presentation LUT',lambda c:dc_forward(c,shape='lin-od')),
 ('DC-F07','DICOMKit SCU to DCMTK: unavailable required LUT refuses before print',lambda c:dc_forward(c,shape='identity',no_lut=True)),
 ('DC-R01','DCMTK SCU to DICOMKit: 8-bit grayscale',lambda c:dc_reverse(c,bits12=False)),
 ('DC-R02','DCMTK SCU to DICOMKit: 12-bit grayscale',lambda c:dc_reverse(c)),
 ('DC-R03','DCMTK SCU to DICOMKit: implicit VR',lambda c:dc_reverse(c,implicit=True)),
 ('DC-R04','DCMTK SCU to DICOMKit: IDENTITY Presentation LUT',lambda c:dc_reverse(c,shape='identity')),
 ('DC-R05','DCMTK SCU to DICOMKit: LIN OD Presentation LUT',lambda c:dc_reverse(c,shape='lin-od')),
 ('DC-R06','DCMTK SCU to DICOMKit: separate annotation context and literal text',lambda c:dc_reverse(c,annotation=True)),
 ('PY-F01','DICOMKit SCU to pynetdicom: exact planar color',lambda c:py_forward(c,'color')),
 ('PY-F02','DICOMKit SCU to pynetdicom: repeated annotations',lambda c:py_forward(c,'annotation')),
 ('PY-F03','DICOMKit SCU to pynetdicom: N-SET failure and cleanup',lambda c:py_forward(c,'set-failure')),
 ('PY-F04','DICOMKit SCU to pynetdicom: Printer FAILURE prevents print',lambda c:py_forward(c,'printer-failure')),
 ('PY-F05','DICOMKit SCU to pynetdicom: Printer WARNING surfaced',lambda c:py_forward(c,'printer-warning')),
 ('PY-F06','DICOMKit SCU to pynetdicom: N-ACTION warning surfaced',lambda c:py_forward(c,'action-warning')),
 ('PY-F07','DICOMKit SCU to pynetdicom: interleaved Done ACK and second-association Job query',lambda c:py_forward(c,'job-event')),
 ('PY-F08','DICOMKit SCU to pynetdicom: rejected required LUT prevents print',lambda c:py_forward(c,'no-lut')),
 ('PY-R01','pynetdicom SCU to DICOMKit: color, mixed-VR Job Done ACK and terminal deletion',lambda c:py_reverse(c)),
 ('PY-R02','pynetdicom SCU to DICOMKit: invalid color planarity refused',lambda c:py_reverse(c,invalid=True)),
 ('PY-R03','pynetdicom SCU to DICOMKit: no Job context means no event',lambda c:py_reverse(c,with_job=False)),
 ('PY-R04','pynetdicom SCU to DICOMKit: no event ACK, Job retained across associations',lambda c:py_reverse(c,push_events=False)),
]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin-dir',type=Path)
    parser.add_argument('--output-dir',type=Path)
    parser.add_argument('--dcmtk-dir',type=Path,default=Path('/opt/homebrew/bin'))
    parser.add_argument('--case',action='append',default=[],help='Run only this case ID (repeatable)')
    parser.add_argument('--list',action='store_true',help='List cases without network or fixture writes')
    parser.add_argument('--peer-only',action='store_true',help='Run a recorded independent peer for externally driven CLI/Workshop checks; no pass claim')
    parser.add_argument('--peer-seconds',type=float,default=900,help='Maximum peer-only lifetime (1–3600 seconds)')
    args=parser.parse_args()
    require(1 <= args.peer_seconds <= 3600,'--peer-seconds must be finite in 1–3600')
    if args.list:
        for identifier,title,_ in CASES:print(identifier+' '+title)
        return 0
    require(args.bin_dir is not None and args.output_dir is not None,'--bin-dir and --output-dir are required')
    require(not args.output_dir.exists(),'output directory must be new; preserve previous evidence')
    unknown=set(args.case)-{i for i,_,_ in CASES}; require(not unknown,'unknown case IDs: '+repr(unknown))
    args.output_dir.mkdir(parents=True)
    runner=argparse.Namespace(bin=args.bin_dir.resolve(),output=args.output_dir.resolve(),dcmtk=args.dcmtk_dir.resolve())
    runner.env=os.environ.copy(); settings=runner.output/'isolated-settings';settings.mkdir()
    runner.env['DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY']=str(settings)
    runner.fixtures=make_fixtures(runner.output/'fixtures')
    binaries=[runner.bin/'dicom-print',runner.bin/'dicom-printscp']+[runner.dcmtk/x for x in ['dcmprscp','dcmprscu','dcmpsprt']]
    for binary in binaries:require(binary.is_file() and os.access(binary,os.X_OK),'missing executable '+str(binary))
    versions={}
    for binary in binaries:
        result=subprocess.run([str(binary),'--version'],capture_output=True,text=True,timeout=10,env=runner.env)
        versions[str(binary)]={'sha256':sha(binary),'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr}
    provenance={'python':sys.version,'python_executable':sys.executable,'pydicom':pydicom.__version__,
                'pynetdicom':pynetdicom.__version__,'Pillow':pillow_version,'script_sha256':sha(__file__),
                'independent_module_hashes':{pydicom.__file__:sha(pydicom.__file__),pynetdicom.__file__:sha(pynetdicom.__file__)},
                'binaries':versions,'scope':'Software loopback qualification only; synthetic data; no paper queue or physical device.',
                'standard_refs':['PS3.4 2026a H.3, H.4.1–H.4.6, H.4.9, H.5','PS3.7 2026a 10.1.1–10.1.6','PS3.3 2026a C.13 and C.11.4','PS3.8 PDU/PDV encoding'],
                'limits':['DCMTK receiver does not support color or Annotation Box; those use independent pynetdicom.',
                          'No physical print, calibration, density measurement, diagnostic image quality or full IOD validation claim.',
                          'Only explicitly selected/executed cases qualify; unselected cases remain not run.',
                          'Pynetdicom oracle is a bounded test peer, not a vendor printer conformance statement.',
                          'Existing DICOMKit SCP tolerates color PlanarConfiguration 0 with a diagnostic; negative gate uses illegal value 2. Tolerance of 0 does not establish strict C.13-5 conformance.']}
    save_json(runner.output/'provenance.json',provenance)
    if args.peer_only:
        peer=IndependentSCP(runner.output,color=True,annotation=True,job=True,event=True,both=True)
        proxy=RecordingProxy(peer.port,runner.output/'wire')
        endpoint={'host':'127.0.0.1','port':proxy.port,'aet':'PYM6','url':'pacs://127.0.0.1:%s'%proxy.port,
                  'job_uid_after_first_send':BASE+'2000','fixtures':{k:str(v) for k,v in runner.fixtures.items()},
                  'expires_after_seconds':args.peer_seconds,'status':'observational_peer_not_an_automated_pass'}
        save_json(runner.output/'endpoint.json',endpoint)
        print(json.dumps(endpoint),flush=True)
        try:
            deadline=time.monotonic()+args.peer_seconds
            while time.monotonic()<deadline:time.sleep(.2)
        except KeyboardInterrupt:pass
        finally:
            proxy.close();peer.close()
            messages,associations=decode_capture(proxy.directory)
            assert_correlations(messages)
            save_json(runner.output/'peer-observations.json',{'message_count':len(messages),'associations':associations,
                       'status':'captured_only_requires_case_specific_assertions','event_acks':peer.event_acks})
        return 0
    results=[]
    for identifier,title,function in CASES:
        if args.case and identifier not in args.case:
            results.append({'id':identifier,'title':title,'status':'not_run'});continue
        case=Case(runner,identifier,title); started=time.monotonic()
        record={'id':identifier,'title':title}
        try:
            function(case);record['status']='passed'
        except PeerCapabilityUnavailable as error:
            record.update(status='unqualified_peer',reason=str(error))
        except Exception as error:
            record.update(status='failed',error=str(error)); (case.directory/'traceback.txt').write_text(traceback.format_exc())
        finally:
            try:case.cleanup()
            except Exception as error:record.update(status='failed',cleanup_error=str(error))
            if (case.directory/'wire').exists() and not (case.directory/'wire/decoded.json').exists():
                try:decode_capture(case.directory/'wire')
                except Exception as error:record['capture_decode_error']=str(error)
        record.update(elapsed_seconds=time.monotonic()-started,observations=case.observations)
        save_json(case.directory/'result.json',record);results.append(record)
        save_json(runner.output/'results.json',{'cases':results,'complete':False})
        print(identifier+': '+record['status']+(' — '+record.get('error','') if record['status']=='failed' else ''),flush=True)
    summary={'cases':results,'complete':True,'passed':sum(r['status']=='passed' for r in results),
             'failed':sum(r['status']=='failed' for r in results),'not_run':sum(r['status']=='not_run' for r in results),
             'unqualified_peer':sum(r['status']=='unqualified_peer' for r in results)}
    save_json(runner.output/'results.json',summary)
    return 1 if summary['failed'] else 0


if __name__=='__main__':
    sys.exit(main())
