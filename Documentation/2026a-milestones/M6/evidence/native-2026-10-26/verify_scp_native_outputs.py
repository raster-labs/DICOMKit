#!/usr/bin/env python3
"""Read saved native SCP evidence and optional parent-operated CLI controls."""
import argparse,datetime,json,re
from pathlib import Path
from verify_print_native_outputs import copied_console,digest,json_values,options
from verify_print_cli_replays import console_body
from verify_print_native_images import raster
R=Path(__file__).resolve().parent
VOLATILE={'filmBoxUID','filmSessionUID','printJobUID','receivedAt'}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--plan',type=Path,default=R/'scp-cli-replay-plan.json');parser.add_argument('--output',type=Path);args=parser.parse_args();plan=json.loads(args.plan.read_text())
 cli_config=Path(plan.get('configDirectory',R/'cli-scp-replay-config'));cli_sim=Path(plan.get('simulationOutputDirectory',R/'cli-simulated-replay'));cli_sink=Path(plan.get('sinkOutputDirectory',R/'cli-sink-failure-replay'))
 checks=[];pending=[];evidence={};consoles={}
 def check(name,ok,detail):checks.append({'check':name,'status':'Passed' if ok else 'Failed','detail':detail})
 def get(name):
  if name not in consoles:consoles[name]=copied_console(R/'ui'/('scp-'+name+'-console.txt'))
  return consoles[name]
 def films(c):return [x for x in c['values'] if isinstance(x,dict) and 'filledImageBoxCount'in x]
 def messages(c):return [x['message'] for x in c['values'] if isinstance(x,dict) and 'message'in x]
 def body(name):return console_body(R/'ui'/('scp-'+name+'-console.txt'))
 def pdf(path):
  data=path.read_bytes();return {'path':str(path),'bytes':len(data),'sha256':digest(data),'completeContainer':data.startswith(b'%PDF-') and data.rstrip().endswith(b'%%EOF')}
 baseline=json.loads((R/'config/baseline-scp.json').read_text());saved=json.loads((R/'config/saved-scp.json').read_text());sim_saved=json.loads((R/'config/simulation-save.json').read_text())
 for name in ['status-inherit','status-enabled']:
  c=get(name);x=c['values'][0];check(name+' native status JSON',x.get('PrinterName')=='M7 Native Baseline' and x.get('PrinterStatus')=='NORMAL' and x.get('isNormal') is True,{'payload':x,'argv':c['argv']})
 check('inherit flags omitted',not any(x in get('status-inherit')['argv'] for x in ['--accept-color','--no-accept-color','--annotation-box','--no-annotation-box','--annotations','--no-annotations','--trim-marks','--no-trim-marks']),'Native imported command retains omitted/inherit state')
 check('enabled flags serialized',all(x in get('status-enabled')['argv'] for x in ['--accept-color','--annotation-box','--annotations','--trim-marks']),'Visible flags serialized as positive switches; status JSON does not expose these internal settings')
 expected=dict(baseline,printerName='Saved Native',supportsColor=False,drawAnnotations=False)
 check('saved native configuration exact fields',saved==expected,{'nativeSaved':saved,'expected':expected})
 check('reloaded native configuration exact fields',get('status-reloaded')['values']==[saved],'Verbose reload returns all saved configuration fields exactly')
 check('native save-before-gather',sim_saved==baseline and body('save-before-gather')=='Wrote '+str(R/'config/simulation-save.json') and not (R/'deliberately-missing.dcm').exists(),'Save-config returns successfully before attempting intentionally missing input; no false gathered/printed claim')
 queues=get('queues')['values'];check('native queues schema',len(queues)==1 and isinstance(queues[0].get('queues'),list) and queues[0]['count']==len(queues[0]['queues']),queues)
 imp=(R/'ui/scp-paper-gate-import.txt').read_text();check('native paper-import refusal','--paper-queue needs --allow-paper' in imp and '--allow-paper ' not in imp.split('Value: ',1)[1].split('\n',1)[0],'Actual Import parser refused before Run; no physical printer dispatch')
 sim=get('simulate');sf=films(sim);wanted={'rows':2,'columns':3,'imageBoxCount':4,'filledImageBoxCount':1,'numberOfCopies':2,'imageDisplayFormat':'ROW\\1,3','borderDensity':'150','emptyImageDensity':'WHITE','trim':'YES','presentationLUTShape':'IDENTITY','annotations':['1:  first; literal note ',"2: O'Neil second"]}
 check('native simulation film fields',len(sf)==1 and all(sf[0].get(k)==v for k,v in wanted.items()),{'expected':wanted,'actual':sf})
 sim_files=sorted(p.name for p in (R/'gui-simulated').iterdir());check('native last image output option + PDF',sim_files==['native-001.pdf','native-001.tiff'],{'actual':sim_files,'contract':'Last image-format option TIFF wins; PDF selected independently'})
 sim_raster=raster(R/'gui-simulated/native-001.tiff');check('native TIFF decode',sim_raster['size']==[504,612],sim_raster)
 sim_pdf=pdf(R/'gui-simulated/native-001.pdf');check('native simulation PDF complete container',sim_pdf['completeContainer'],sim_pdf)
 sink=body('sink-failure');check('native failed sink visible without saved-file claim','Output failed (png):' in sink and 'Wrote ' not in sink and (R/'sink-failure/native-001.png').is_dir() and len(films(get('sink-failure')))==1,'Failed file output is explicit; film/protocol data survives; no file-success claim')
 opened=R/'open-output/opened-001.png';open_ax=(R/'ui/scp-open-preview.txt').read_text();check('native Open targets successful file',opened.is_file() and ('URL: file://'+str(opened)) in open_ax and 'App: Preview' in open_ax and ('Wrote '+str(opened)) in body('open-success'),{'path':str(opened),'raster':raster(opened),'capture':str(R/'ui/scp-open-preview.txt')})
 counters={'serve-stopped':'Stopped — 2 associations, 2 films, 0 errors (cancelled)','duration-complete':'Stopped — 0 associations, 0 films, 0 errors (reached --duration 2s)','one-film-complete':'Stopped — 1 association, 1 film, 0 errors (reached --max-films 1)','independent-color-stopped':'Stopped — 2 associations, 1 film, 1 error (cancelled)','independent-gray-stopped':'Stopped — 1 association, 1 film, 0 errors (cancelled)','leave-cancelled':'Stopped — 0 associations, 0 films, 0 errors (cancelled)'}
 for name,expected_stop in counters.items():
  c=get(name);m=messages(c);check(name+' stopped counters',expected_stop in m and any(x=='Listening on port 21114 as DCMKIT_M6' for x in m),{'expectedStop':expected_stop,'messages':m})
 for case,native_name,file in [('gray8','serve-stopped','native-001'),('rgb8','serve-stopped','native-002'),('one-film','one-film-complete','limited-001')]:
  cli=json.loads((R/'cli-results/native-receiver'/(case+'.json')).read_text());payload=json.loads(cli['stdout']);film=next((x for x in films(get(native_name)) if x['printJobUID']==payload['printJobUID']),None)
  path=R/'gui-received'/(file+'.png');check(case+' CLI/native receiver identifiers',cli['returncode']==0 and payload['success'] is True and film is not None and all(payload[k]==film[k] for k in ['filmBoxUID','filmSessionUID','printJobUID']) and ('Wrote '+str(path)) in messages(get(native_name)),{'CLI':payload,'film':film})
  rr=raster(path);check(case+' native received image',rr['size']==[504,612] and rr['mode']==('RGB' if case=='rgb8' else 'L'),rr)
  if case!='rgb8':check(case+' pixels match final raw gray CLI baseline',rr['rgbaSHA256']==raster(R/'cli-received/native-004.png')['rgbaSHA256'],'Dimensions and decoded RGBA pixels equal')
  if case!='one-film':pr=pdf(R/'gui-received'/(file+'.pdf'));check(case+' received PDF complete container',pr['completeContainer'],pr)
 for color in ['gray','color']:
  result=json.loads((R/('independent-'+color+'-send/results.json')).read_text());path=R/('gui-independent-'+color)/'native-001.png';rr=raster(path)
  check('independent '+color+' actual native role evidence',result['passed'] is True and result['native_listener_launched_by_wrapper'] is False and digest(path.read_bytes())==result['observations']['films'][0]['sha256'] and rr['size']==[288,360] and rr['mode']==('RGB' if color=='color' else 'L'),{'result':result,'raster':rr})
  wire=json.loads((R/('independent-'+color+'-send/wire/decoded.json')).read_text());statuses=[m['command']['00000900']['Value'][0] for m in wire['messages'] if '00000900'in m['command']]
  check('independent '+color+' DIMSE statuses',statuses.count(274)==(1 if color=='color' else 0) and all(s in ([0,274] if color=='color' else [0]) for s in statuses),{'statuses':statuses,'scope':'Color deliberately probes deleted PrintJob with N-GET: expected0112 and error counter1; all other responses successful'})
 color_events=json.loads((R/'independent-color-send/independent-events.json').read_text());color_wire=json.loads((R/'independent-color-send/wire/decoded.json').read_text())
 check('native color terminal event and ACK',len(color_events)==1 and color_events[0]['event_type']==3 and color_events[0]['transfer']=='1.2.840.10008.1.2' and any(m['command'].get('00000100',{}).get('Value')==[33024] and m['command'].get('00000900',{}).get('Value')==[0] for m in color_wire['messages']),{'events':color_events,'scope':'Independent peer captured terminal DONE event on negotiated Implicit VR context and successful event response'})
 rebind=json.loads((R/'scp-leave-rebind.json').read_text());check('leave-Workshop port released',rebind=={'port':21114,'bind_after_leaving_workshop':'passed','listener_launched':False},rebind)
 for path,sha in plan['nativeConfigsProtected'].items():check('native config remains unchanged '+Path(path).name,digest(Path(path).read_bytes())==sha,{'path':path,'sha256':sha})
 for case in plan['cases']:
  name=case['name'];p=Path(case['resultFile'])
  if not p.exists():pending.append('CLI control pending: '+name);continue
  result=json.loads(p.read_text());expected_exit=case['expectedExitCode'];oracle=None
  correction_path=R/'scp-cli-replay-oracle-correction.json'
  if name=='paper-import-refusal' and correction_path.exists():
   candidate=json.loads(correction_path.read_text())
   if candidate['planSHA256']==digest(args.plan.read_bytes()):expected_exit=candidate['correctExpectedExitCode'];oracle=str(correction_path)
  check(name+' CLI exact planned argv/result',result['argv']==case['argv'] and result['returncode']==expected_exit and not result['timedOut'] and result['binarySHA256']==plan['binarySHA256'],{'exit':result['returncode'],'expected':expected_exit,'originalPlanExpected':case['expectedExitCode'],'oracleCorrection':oracle,'argv':result['argv']})
  if name in ['status-inherit','status-enabled','status-reloaded','queues']:
   check(name+' CLI/native complete JSON parity',json_values(result['stdout'])==get(name)['values'],{'CLI':json_values(result['stdout']),'native':get(name)['values']})
  elif name in ['save-config','save-before-gather']:
   filename='saved-scp.json' if name=='save-config' else 'simulation-save.json';cli_saved=json.loads((cli_config/filename).read_text());native_saved=json.loads((R/'config'/filename).read_text());check(name+' saved settings complete parity',cli_saved==native_saved,{'CLI':cli_saved,'native':native_saved})
   expected_body=body(name).replace(str(R/'config'),str(cli_config));check(name+' saved-file diagnostic parity',(result['stdout']+result['stderr']).removesuffix('\n')==expected_body,{'stdout':result['stdout'],'stderr':result['stderr'],'explicitPathMapping':case.get('replacements',[])})
  elif name in ['simulate','sink-failure']:
   cv=[x for x in json_values(result['stdout']) if isinstance(x,dict) and 'filledImageBoxCount'in x];nv=films(get(name));check(name+' CLI/native all film fields',len(cv)==len(nv)==1 and {k:v for k,v in cv[0].items() if k not in VOLATILE}=={k:v for k,v in nv[0].items() if k not in VOLATILE},{'CLI':cv,'native':nv,'excluded':sorted(VOLATILE)})
   if name=='simulate':
    target=cli_sim;check('simulate CLI output selection',sorted(p.name for p in target.iterdir())==['native-001.pdf','native-001.tiff'],'TIFF + PDF only');cr=raster(target/'native-001.tiff');check('simulate native/CLI decoded TIFF pixels',cr['size']==sim_raster['size'] and cr['rgbaSHA256']==sim_raster['rgbaSHA256'],{'CLI':cr,'native':sim_raster});pr=pdf(target/'native-001.pdf');check('simulate CLI PDF complete container',pr['completeContainer'],pr)
   else:check('sink CLI explicit failure without saved claim','Output failed (png):' in result['stderr'] and 'Wrote ' not in result['stderr']+result['stdout'] and (cli_sink/'native-001.png').is_dir(),{'stdout':result['stdout'],'stderr':result['stderr']})
  elif name=='paper-import-refusal':check('paper CLI/native same explicit refusal',result['stdout']=='' and '--paper-queue needs --allow-paper' in result['stderr'],{'stderr':result['stderr'],'nativeSource':case['nativeConsole']})
 pending.extend(['Native registry relaunch/remove and final collision/quit/rebuilt-app checks remain separate parent-owned criteria.','Native enabled flag preview is captured; nonverbose status JSON omits effective boolean settings. Shared-parser/VM automated evidence supplies underlying setting resolution; this capture alone is not a boolean-state dump.','PDF checks establish complete containers only; no physical print or rendered-PDF visual qualification claimed.'])
 failed=[x['check'] for x in checks if x['status']=='Failed'];out={'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Failed' if failed else 'Partial — recorded native/control checks pass; final acceptance remains open','completedNativeChecklistGroups':0,'replayPlan':str(args.plan),'binarySHA256':plan['binarySHA256'],'sourceJustification':plan.get('sourceJustification'),'checks':checks,'failures':failed,'pending':pending,'consoles':consoles,'scope':'Read-only saved evidence. No product, listener, peer, UI, build, protected registry or physical printer action.'}
 (args.output or R/('scp-native-verification-post-repair.json' if 'sourceJustification' in plan else 'scp-native-verification.json')).write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'passed':len(checks)-len(failed),'failed':failed,'pending':pending},indent=2));return bool(failed)
if __name__=='__main__':raise SystemExit(main())
