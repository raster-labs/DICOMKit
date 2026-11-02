#!/usr/bin/env python3
"""Independent loopback DIMSE gate for actual CLI/server binaries.
No external endpoints, real studies, printer jobs, or shared trust changes.
Uses pynetdicom3.0.4/pydicom3.0.1; each failed assertion remains a failed gate.
"""
import argparse, copy, hashlib, json, os, pathlib, socket, subprocess, sys, threading, time
import pydicom,pynetdicom
from pydicom.dataset import Dataset, FileDataset, FileMetaDataset
from pydicom.uid import CTImageStorage, MRImageStorage, SecondaryCaptureImageStorage, ExplicitVRLittleEndian, ImplicitVRLittleEndian, ExplicitVRBigEndian
from pynetdicom import AE, evt, build_role
from pynetdicom.sop_class import Verification, StudyRootQueryRetrieveInformationModelFind as FIND, StudyRootQueryRetrieveInformationModelGet as GET, StudyRootQueryRetrieveInformationModelMove as MOVE, PatientRootQueryRetrieveInformationModelFind as PFIND
MPPS='1.2.840.10008.3.1.2.3.3'
STUDY='2.25.700'; CLASSES=[str(CTImageStorage),str(MRImageStorage),str(SecondaryCaptureImageStorage)]
SYNTAXES=[str(ImplicitVRLittleEndian),str(ExplicitVRLittleEndian),str(ExplicitVRBigEndian)]
def save(p,v):p.write_text(json.dumps(v,indent=2,default=str)+'\n')
def free_port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def fixture(path,index,cls,syntax):
 meta=FileMetaDataset();meta.MediaStorageSOPClassUID=cls;meta.MediaStorageSOPInstanceUID='2.25.7000.'+str(index);meta.TransferSyntaxUID=syntax;meta.ImplementationClassUID='2.25.700999'
 ds=FileDataset(str(path),{},file_meta=meta,preamble=b'\0'*128)
 ds.is_little_endian=syntax!=str(ExplicitVRBigEndian);ds.is_implicit_VR=syntax==str(ImplicitVRLittleEndian)
 ds.SOPClassUID=cls;ds.SOPInstanceUID=meta.MediaStorageSOPInstanceUID;ds.StudyInstanceUID=STUDY
 ci=CLASSES.index(cls);ds.SeriesInstanceUID=STUDY+'.'+str(ci+1);ds.Modality=['CT','MR','OT'][ci]
 ds.PatientID='NETM7';ds.PatientName='M7^Synthetic';ds.StudyDate='20261024';ds.StudyTime='101530';ds.StudyDescription='M7 synthetic';ds.SeriesNumber=ci+1;ds.InstanceNumber=index
 ds.Rows=2;ds.Columns=2;ds.SamplesPerPixel=1;ds.PhotometricInterpretation='MONOCHROME2';ds.BitsAllocated=8;ds.BitsStored=8;ds.HighBit=7;ds.PixelRepresentation=0;ds.PixelData=bytes([index,2,3,4])
 pydicom.dcmwrite(path,ds,enforce_file_format=True,little_endian=ds.is_little_endian,implicit_vr=ds.is_implicit_VR);return ds

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--bin-dir',type=pathlib.Path,required=True);p.add_argument('--output-dir',type=pathlib.Path,required=True);a=p.parse_args()
 root=a.output_dir.resolve();root.mkdir(parents=True,exist_ok=True)
 if list(root.iterdir()):p.error('Use an empty output directory')
 assert pynetdicom.__version__=='3.0.4' and pydicom.__version__=='3.0.1','Use pinned peers'
 records=[];wire=[];associations=[];peers=[];processes=[];lock=threading.Lock();state={'find':'success','store':0}
 versions={'python':sys.version,'pynetdicom':pynetdicom.__version__,'pydicom':pydicom.__version__}
 save(root/'versions.json',versions)
 fixtures=[]
 for i in range(6):fixtures.append(fixture(root/f'fixture-{i+1}.dcm',i+1,CLASSES[i//2],SYNTAXES[i%3]))
 def run(name,tool,args,exit=0,contains=None):
  argv=[str(a.bin_dir/tool),*map(str,args)];result=subprocess.run(argv,capture_output=True,text=True,timeout=40)
  (root/(name+'.stdout.txt')).write_text(result.stdout);(root/(name+'.stderr.txt')).write_text(result.stderr)
  assert result.returncode==exit,(name,result.returncode,result.stdout,result.stderr)
  if contains:assert contains.lower() in (result.stdout+result.stderr).lower(),(name,contains,result.stdout,result.stderr)
  records.append({'id':name,'result':'Passed','argv':argv,'exit':result.returncode});return result
 def record(kind,event,ds=None):
  row={'kind':kind,'class':str(event.context.abstract_syntax),'syntax':str(event.context.transfer_syntax),'message_id':event.request.MessageID}
  if ds is not None:row['dataset']=ds.to_json_dict()
  with lock:wire.append(row)
  return row
 def accepted(event):
  with lock:associations.append({'calling_aet':event.assoc.requestor.ae_title,'called_aet':event.assoc.acceptor.ae_title})
 def echo(event):record('C-ECHO',event);return 0
 def store(event):
  ds=event.dataset;row=record('C-STORE',event,ds);row.update(affected_class=str(event.request.AffectedSOPClassUID),affected_instance=str(event.request.AffectedSOPInstanceUID),raw_sha256=hashlib.sha256(event.request.DataSet.getvalue()).hexdigest(),status=state['store'],move_originator_aet=str(getattr(event.request,'MoveOriginatorApplicationEntityTitle','')),move_originator_message_id=getattr(event.request,'MoveOriginatorMessageID',None))
  assert str(ds.SOPClassUID)==row['affected_class'] and str(ds.SOPInstanceUID)==row['affected_instance']
  expected=next(x for x in fixtures if x.SOPInstanceUID==ds.SOPInstanceUID)
  assert ds.PixelData==expected.PixelData and ds.PatientID==expected.PatientID
  if state.get('move_cancel'):
   active=state['move_cancel'];active['received'].append(str(ds.SOPInstanceUID));n=len(active['received'])
   if n==4:active['entered'].set();assert active['settle'].wait(5),'Cancel coordination did not release active MOVE storage'
   row['status']={2:0xB000,3:0xC000}.get(n,0)
  return row['status']
 def find(event):
  query=event.identifier;record('C-FIND',event,query)
  ds=Dataset();ds.QueryRetrieveLevel=query.QueryRetrieveLevel;ds.StudyInstanceUID=STUDY;ds.PatientID='NETM7';ds.PatientName='MÜLLER^SYNTHETIC';ds.SpecificCharacterSet='ISO_IR 192'
  if ds.QueryRetrieveLevel in ['SERIES','IMAGE']:ds.SeriesInstanceUID=STUDY+'.1'
  if ds.QueryRetrieveLevel=='IMAGE':ds.SOPInstanceUID=fixtures[0].SOPInstanceUID
  yield 0xFF00,ds
  yield (0xFE00 if state['find']=='cancel' else 0),None
 def get(event):
  record('C-GET',event,event.identifier);yield len(fixtures)
  for ds in fixtures:yield 0xFF00,ds
 def nset(event):
  ds=event.modification_list;record('N-SET',event,ds);return 0,None
 ae=AE(ae_title='M7PEER');ae.acse_timeout=5;ae.dimse_timeout=5;ae.network_timeout=5
 for c in [Verification,FIND,PFIND,GET,MPPS]:ae.add_supported_context(c,SYNTAXES)
 for c in CLASSES:ae.add_supported_context(c,SYNTAXES,scu_role=True,scp_role=True)
 peer=ae.start_server(('127.0.0.1',0),block=False,evt_handlers=[(evt.EVT_ACCEPTED,accepted),(evt.EVT_C_ECHO,echo),(evt.EVT_C_STORE,store),(evt.EVT_C_FIND,find),(evt.EVT_C_GET,get),(evt.EVT_N_SET,nset)])
 peers.append(peer);port=peer.server_address[1]
 def endpoint(port,called='M7PEER'):return ['127.0.0.1','--port',port,'--aet','M7CLIENT','--called-aet',called,'--timeout','5']
 def check_received(directory):
  actual={}
  for path in directory.rglob('*'):
   if path.is_file():
    try:ds=pydicom.dcmread(path)
    except Exception:continue
    actual[str(ds.SOPInstanceUID)]=ds
  assert set(actual)=={str(x.SOPInstanceUID) for x in fixtures},list(actual)
  for ds in fixtures:
   other=actual[str(ds.SOPInstanceUID)];assert str(other.SOPClassUID)==str(ds.SOPClassUID) and other.PixelData==ds.PixelData
  return {uid:hashlib.sha256(ds.PixelData).hexdigest() for uid,ds in actual.items()}
 try:
  run('client-echo','dicom-echo',endpoint(port))
  for i,ds in enumerate(fixtures):run('client-store-'+str(i+1),'dicom-send',endpoint(port)+[root/f'fixture-{i+1}.dcm','--transfer-syntax',ds.file_meta.TransferSyntaxUID])
  state['store']=0xB000;run('client-store-warning','dicom-send',endpoint(port)+[root/'fixture-1.dcm'],contains='warning')
  state['store']=0xC000;run('client-store-failure','dicom-send',endpoint(port)+[root/'fixture-1.dcm'],exit=1);state['store']=0
  for level,args in [('study',['--modality','CT','--patient-name','M7*','--study-date','20261001-20261031']),('series',['--study-uid',STUDY,'--modality','CT']),('image',['--study-uid',STUDY,'--series-uid',STUDY+'.1'])]:
   run('client-find-'+level,'dicom-query',endpoint(port)+['--level',level,'--format','dicom-json',*args],contains='MÜLLER')
   q=wire[-1]['dataset'];assert q['00080052']['Value']==[level.upper()]
   if level=='study':assert q['00080061']['Value']==['CT'] and q['00080020']['Value']==['20261001-20261031'] and q['00100010']['Value'][0]['Alphabetic']=='M7*'
   if level=='series':assert q['00080060']['Value']==['CT']
   if level=='image':assert '00080060' not in q and '00080061' not in q
  for name,args in [('image-modality',['--level','image','--study-uid',STUDY,'--series-uid',STUDY+'.1','--modality','CT']),('patient-date',['--level','patient','--study-date','20261024']),('patient-description',['--level','patient','--study-description','x']),('patient-studyuid',['--level','patient','--study-uid',STUDY])]:
   count=len(associations);run('refuse-'+name,'dicom-query',endpoint(port)+args,exit=64);assert len(associations)==count
  state['find']='cancel';run('client-find-FE00','dicom-query',endpoint(port)+['--level','study','--format','json'],exit=1,contains='FE00');state['find']='success'
  target=root/'client-get';run('client-get','dicom-retrieve',endpoint(port)+['--method','c-get','--study-uid',STUDY,'--output',target]);save(root/'client-get-pixels.json',check_received(target))
  for ci,cls in enumerate(CLASSES):
   args=['update',*endpoint(port),'--mpps-uid','2.25.700900','--status','COMPLETED','--study-uid',STUDY,'--series-uid',STUDY+'.'+str(ci+1),'--image-uid',fixtures[ci*2].SOPInstanceUID,'--protocol-name','M7SYNTHETIC']
   if ci==0:
    count=len(associations);run('mpps-refuse-missing-class','dicom-mpps',args,exit=64);assert len(associations)==count
   run('mpps-reference-'+str(ci),'dicom-mpps',args+['--sop-class-uid',cls]);ds=Dataset.from_json(wire[-1]['dataset']);reference=ds.PerformedSeriesSequence[0].ReferencedImageSequence[0]
   assert reference.ReferencedSOPClassUID==cls and reference.ReferencedSOPInstanceUID==fixtures[ci*2].SOPInstanceUID
  # Actual server: each request/response below is emitted/decoded by the independent library.
  server_port=free_port();log=(root/'server.log').open('w');argv=[str(a.bin_dir/'dicom-server'),'start','--data-dir',str(root/'server-storage'),'--aet','M7SERVER','--port',str(server_port),'--move-destination',f'M7DEST=127.0.0.1:{port}']
  server=subprocess.Popen(argv,stdout=log,stderr=subprocess.STDOUT);processes.append((server,log))
  client=AE(ae_title='M7ORACLE');client.acse_timeout=5;client.dimse_timeout=8;client.network_timeout=8
  for c in [Verification,FIND,GET,MOVE]:client.add_requested_context(c,SYNTAXES)
  for cls in CLASSES:
   for ts in SYNTAXES:client.add_requested_context(cls,[ts])
  def associate(**kw):
   assoc=client.associate('127.0.0.1',server_port,ae_title='M7SERVER',**kw);assert assoc.is_established,'Independent association failed';return assoc
  deadline=time.monotonic()+10
  while True:
   try:
    with socket.create_connection(('127.0.0.1',server_port),timeout=.2):break
   except OSError:
    assert server.poll() is None and time.monotonic()<deadline,'Actual server did not bind';time.sleep(.05)
  assoc=associate();assert assoc.send_c_echo().Status==0
  for ds in fixtures:assert assoc.send_c_store(ds).Status==0
  assoc.release();records.append({'id':'server-echo-store-native6','result':'Passed','argv':argv,'instances':6})
  def query(level,**values):
   ds=Dataset();ds.QueryRetrieveLevel=level
   for key,value in values.items():setattr(ds,key,value)
   return ds
  for name,ds,count in [('study-wildcard-range',query('STUDY',PatientID='NETM7',PatientName='M7*',StudyDate='20261001-20261031',StudyInstanceUID='',ModalitiesInStudy=''),1),('study-date-miss',query('STUDY',StudyDate='20250101-20251231',StudyInstanceUID=''),0),('series-modality',query('SERIES',StudyInstanceUID=STUDY,Modality='CT',SeriesInstanceUID=''),1),('image-return-keys',query('IMAGE',StudyInstanceUID=STUDY,SeriesInstanceUID=STUDY+'.1',SOPInstanceUID='',InstanceNumber=''),2)]:
   assoc=associate();responses=list(assoc.send_c_find(ds,FIND));assoc.release();assert responses[-1][0].Status==0
   matches=[d for status,d in responses if status.Status in [0xFF00,0xFF01]];assert len(matches)==count,(name,responses)
   save(root/(name+'.json'),[{'status':int(st.Status),'identifier':d.to_json_dict() if d else None} for st,d in responses])
   if name=='image-return-keys':assert all(d.SOPInstanceUID and d.InstanceNumber for d in matches)
   if name=='study-wildcard-range':assert set(matches[0].ModalitiesInStudy)=={'CT','MR','OT'}
   records.append({'id':'server-find-'+name,'result':'Passed','matches':count})
  # C-GET role negotiation and mixed terminal counters, synchronized by an independent storage handler.
  received=[];entered=threading.Event();settle=threading.Event();capture=[]
  def store_get(event):
   ds=event.dataset;received.append(str(ds.SOPInstanceUID));n=len(received)
   if n==4:entered.set();assert settle.wait(5),'Cancel coordination did not release active storage'
   return {2:0xB000,3:0xC000}.get(n,0)
  assoc=associate(ext_neg=[build_role(c,scu_role=False,scp_role=True) for c in CLASSES],evt_handlers=[(evt.EVT_C_STORE,store_get)])
  def get_worker():
   for st,ds in assoc.send_c_get(query('STUDY',StudyInstanceUID=STUDY),GET,msg_id=47):capture.append((st,ds))
  worker=threading.Thread(target=get_worker,daemon=True);worker.start();assert entered.wait(8),'Fourth storage suboperation not reached'
  assoc.send_c_cancel(47,query_model=GET);time.sleep(.05);settle.set();worker.join(10);assert not worker.is_alive(),'Cancelled C-GET did not settle'
  status,failed=capture[-1];assert status.Status==0xFE00,(status,failed)
  assert [status.NumberOfCompletedSuboperations,status.NumberOfWarningSuboperations,status.NumberOfFailedSuboperations,status.NumberOfRemainingSuboperations]==[2,1,1,2],status
  failed_uids=str(failed.FailedSOPInstanceUIDList).split('\\');assert failed_uids==[received[2]],failed
  assert assoc.send_c_echo().Status==0;assoc.release()
  save(root/'server-get-cancel.json',{'statuses':[st.to_json_dict() for st,ds in capture],'received':received,'failed_uids':failed_uids,'association_reused_for_echo':True})
  records.append({'id':'server-get-cancel-mixed-counters','result':'Passed'})
  assoc=associate();responses=list(assoc.send_c_move(query('STUDY',StudyInstanceUID=STUDY),'UNKNOWN',MOVE));assoc.release();assert responses[-1][0].Status==0xA801
  records.append({'id':'server-move-unknown-destination','result':'Passed'})
  # C-MOVE uses a separate independently implemented destination association.
  before=len(wire);assoc=associate();responses=list(assoc.send_c_move(query('STUDY',StudyInstanceUID=STUDY),'M7DEST',MOVE,msg_id=48));assoc.release()
  assert responses[-1][0].Status==0 and responses[-1][0].NumberOfCompletedSuboperations==6,responses
  stores=[row for row in wire[before:] if row['kind']=='C-STORE'];assert len(stores)==6 and {row['affected_instance'] for row in stores}=={str(x.SOPInstanceUID) for x in fixtures}
  assert all(row['move_originator_aet']=='M7ORACLE' and row['move_originator_message_id']==48 for row in stores),stores
  save(root/'server-move-success.json',{'statuses':[st.to_json_dict() for st,ds in responses],'received_stores':stores})
  records.append({'id':'server-move-success-identity-originator','result':'Passed'})
  active={'received':[],'entered':threading.Event(),'settle':threading.Event()};state['move_cancel']=active;capture=[];assoc=associate()
  def move_worker():
   for st,ds in assoc.send_c_move(query('STUDY',StudyInstanceUID=STUDY),'M7DEST',MOVE,msg_id=49):capture.append((st,ds))
  worker=threading.Thread(target=move_worker,daemon=True);worker.start();assert active['entered'].wait(8),'Fourth MOVE suboperation not reached'
  assoc.send_c_cancel(49,query_model=MOVE);time.sleep(.05);active['settle'].set();worker.join(10);assert not worker.is_alive(),'Cancelled C-MOVE did not settle'
  status,failed=capture[-1];assert status.Status==0xFE00,(status,failed)
  assert [status.NumberOfCompletedSuboperations,status.NumberOfWarningSuboperations,status.NumberOfFailedSuboperations,status.NumberOfRemainingSuboperations]==[2,1,1,2],status
  failed_uids=str(failed.FailedSOPInstanceUIDList).split('\\');assert failed_uids==[active['received'][2]],failed
  assert assoc.send_c_echo().Status==0;assoc.release();state.pop('move_cancel')
  save(root/'server-move-cancel.json',{'statuses':[st.to_json_dict() for st,ds in capture],'received':active['received'],'failed_uids':failed_uids,'association_reused_for_echo':True})
  records.append({'id':'server-move-cancel-mixed-counters','result':'Passed'})
  # TLS refusal: no storage effect or listening fallback, including JSON configuration.
  for name,args in [('flag',['--tls']),('config',[]),('config-false-plus-flag',['--tls'])]:
   directory=root/('tls-'+name);target_port=free_port();server_args=['start','--data-dir',directory,'--port',target_port,'--aet','M7TLS']
   if name.startswith('config'):
    config={'aeTitle':'M7TLS','port':target_port,'dataDirectory':str(directory),'databaseURL':'filesystem://','maxConcurrentConnections':10,'maxPDUSize':16384,'enableTLS':name=='config','verbose':False,'knownDestinations':{}}
    save(root/('tls-refusal-'+name+'.json'),config);server_args=['start','--config',root/('tls-refusal-'+name+'.json')]
   run('server-TLS-refusal-'+name,'dicom-server',server_args+args,exit=1,contains='No plaintext fallback')
   assert not directory.exists(),'Refusal must precede storage initialization'
   with socket.socket() as sock:assert sock.connect_ex(('127.0.0.1',target_port))!=0,'TLS request opened a plaintext listener'
  save(root/'wire.json',wire);save(root/'associations.json',associations)
  save(root/'results.json',{'result':'Passed','cases':len(records),'records':records,'versions':versions,'binary_sha256':{t:hashlib.sha256((a.bin_dir/t).read_bytes()).hexdigest() for t in ['dicom-echo','dicom-send','dicom-query','dicom-retrieve','dicom-mpps','dicom-server']},'limits':['Synthetic CT/MR/SC opaque transport and identity, not complete IOD validation.','Native transfer syntaxes only; codec qualification separate.','Deterministic server C-FIND midstream cancellation is not established by this script; M4 tests and independent complementary gate remain required.','TLS protocol/identity tests are a separate library-only runner.','No external PACS or clinical data.']})
  print('M7 independent network cases passed:',len(records));return 0
 except Exception as error:
  save(root/'wire.json',wire);save(root/'associations.json',associations);save(root/'results.json',{'result':'Failed','error':str(error),'completed_records':records,'versions':versions});raise
 finally:
  for process,log in processes:
   process.terminate()
   try:process.wait(timeout=8)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
   log.close()
  for server in peers:server.shutdown();server.server_close()
if __name__=='__main__':sys.exit(main())
