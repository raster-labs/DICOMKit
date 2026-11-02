#!/usr/bin/env python3
"""Preparation wrapper over the already-qualified independent print oracle.
Root launches this explicitly. It never starts DICOMKit or drives UI.
New wrapper has syntax review only until root executes it; no new pass inferred.
"""
import argparse,contextlib,importlib.util,json,os,signal,threading,time
from pathlib import Path
from types import SimpleNamespace
here=Path(__file__).resolve().parent
repo=here.parents[1]/'DICOMKit-milestones'
spec=importlib.util.spec_from_file_location('qualified_print',repo/'Scripts/verify_m6_print_interop.py')
api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)

def main():
 p=argparse.ArgumentParser();p.add_argument('operation',choices=['serve','send-color','send-gray'])
 p.add_argument('--output-dir',type=Path,required=True)
 p.add_argument('--mode',choices=['normal','warning','failure','set-failure','action-warning','no-lut','event'],default='normal')
 p.add_argument('--duration',type=float,default=1800)
 p.add_argument('--port',type=int);p.add_argument('--films',type=Path)
 p.add_argument('--invalid-planar',action='store_true');p.add_argument('--no-push-events',action='store_true')
 p.add_argument('--annotation',action='store_true');p.add_argument('--shape',choices=['identity','lin-od'])
 args=p.parse_args();out=args.output_dir.resolve()
 if out.exists():raise SystemExit('Use a fresh output directory')
 if args.operation=='serve':
  out.mkdir(parents=True)
  opts=dict(color=False,both=True,annotation=True,lut=args.mode!='no-lut',job=True,event=args.mode=='event',
            printer_status={'warning':'WARNING','failure':'FAILURE'}.get(args.mode,'NORMAL'),
            fail_set=args.mode=='set-failure',action_warning=args.mode=='action-warning')
  peer=api.IndependentSCP(out,**opts);proxy=api.RecordingProxy(peer.port,out/'wire');stop=threading.Event()
  for signum in [signal.SIGINT,signal.SIGTERM]:signal.signal(signum,lambda *_:stop.set())
  endpoint={'url':'pacs://127.0.0.1:'+str(proxy.port),'calledAE':'PYM6','mode':args.mode,'scope':'Independent software peer; one image box per film; no verification C-ECHO context','pid':os.getpid()}
  api.save_json(out/'endpoint.json',endpoint);print(json.dumps(endpoint),flush=True)
  deadline=time.monotonic()+args.duration
  try:
   while not stop.wait(.5) and time.monotonic()<deadline:
    api.save_json(out/'live-records.json',{'records':peer.records,'event_acks':peer.event_acks})
  finally:
   proxy.close();peer.close()
   messages,associations=api.decode_capture(proxy.directory);api.assert_correlations(messages)
   api.save_json(out/'capture-summary.json',{'messages':len(messages),'associations':len(associations),'event_acks':peer.event_acks,'proxy_errors':proxy.errors,'status':'Captured; selected native result/counter assertions remain reviewer work'})
 else:
  if args.port is None or args.films is None:p.error('--port and --films are required for send operations')
  films=args.films.resolve()
  if not films.is_dir() or list(films.iterdir()):raise SystemExit('Select an existing empty native output folder first')
  fixtures={n:here/'print-fixtures'/('peer-'+n+'.dcm') for n in ['gray8','gray12','rgb8']}
  runner=SimpleNamespace(output=out.parent,fixtures=fixtures,bin=Path('/Volumes/DICOMKit-M1-build/spm/out/Products/Debug'),dcmtk=Path('/opt/homebrew/bin'),env=dict(os.environ))
  class NativeCase(api.Case):
   @contextlib.contextmanager
   def kit_scp(self,extra=()):
    # The native UI, not this wrapper, sets those exact controls. Required:
    # AE DCMKIT_M6, PNG output, DPI36/max1024; color/events or gray/LUT/annotation.
    proxy=api.RecordingProxy(args.port,self.directory/'wire')
    self.observations['native_configuration_required']=list(extra)
    try:yield proxy,films
    finally:proxy.close()
  case=NativeCase(runner,out.name,'Native packaged Print SCP independent peer')
  try:
   if args.operation=='send-color':api.py_reverse(case,invalid=args.invalid_planar,with_job=True,push_events=not args.no_push_events)
   else:api.dc_reverse(case,bits12=True,shape=args.shape,annotation=args.annotation)
   api.save_json(out/'results.json',{'passed':True,'native_listener_launched_by_wrapper':False,'observations':case.observations})
  except BaseException as error:
   api.save_json(out/'results.json',{'passed':False,'error':repr(error),'observations':case.observations});raise
  finally:case.cleanup()
if __name__=='__main__':main()
