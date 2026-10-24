#!/usr/bin/env python3
"""Existing-binary M6 Workshop frame/codec parity, synthetic local receiver only."""
import argparse, copy, hashlib, importlib.util, json, os, shlex, shutil, subprocess, time, traceback
from pathlib import Path
import pydicom
from PIL import Image
spec=importlib.util.spec_from_file_location('base',Path(__file__).with_name('verify_m6_workshop.py'))
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def main():
 p=argparse.ArgumentParser();p.add_argument('--bin-dir',type=Path,required=True);p.add_argument('--test-bundle',type=Path,required=True);p.add_argument('--codec-campaign',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args()
 root=a.output_dir.resolve();root.mkdir(parents=True,exist_ok=False);fixtures=root/'fixtures';fixtures.mkdir();binary=a.bin_dir.resolve();campaign=a.codec_campaign.resolve()
 def save(path,obj):base.save(path,obj)
 sources={'native':campaign/'fixtures/gray8.dcm','rle':campaign/'reverse-rle-gray8/foreign.dcm','jpeg':campaign/'reverse-jpeg-gray8/foreign.dcm'}
 for name,path in sources.items():shutil.copyfile(path,fixtures/(name+'.dcm'))
 original=pydicom.dcmread(sources['native']);pixels=bytes(original.PixelData);count=int(original.Rows)*int(original.Columns);assert len(pixels)==count
 for name in ['rle','jpeg']:
  decoded=pydicom.dcmread(campaign/('reverse-'+name+'-gray8')/'decoded.dcm');assert decoded.PixelData==pixels,'Existing codec evidence does not match native control'
 frames=[pixels,bytes(255-x for x in pixels),bytes((x+73)%256 for x in pixels)]
 for index,frame in enumerate(frames,1):
  d=copy.deepcopy(original);d.SOPInstanceUID='1.2.826.0.1.3680043.10.543.20261024.6.91.'+str(index);d.file_meta.MediaStorageSOPInstanceUID=d.SOPInstanceUID;d.PixelData=frame;d.save_as(fixtures/('frame'+str(index)+'.dcm'),write_like_original=False)
 d=copy.deepcopy(original);d.SOPClassUID='1.2.840.10008.5.1.4.1.1.7.2';d.SOPInstanceUID='1.2.826.0.1.3680043.10.543.20261024.6.92';d.file_meta.MediaStorageSOPClassUID=d.SOPClassUID;d.file_meta.MediaStorageSOPInstanceUID=d.SOPInstanceUID;d.NumberOfFrames=3;d.FrameTime='40';d.FrameIncrementPointer=[0x00181063];d.PixelData=b''.join(frames);d.save_as(fixtures/'multi.dcm',write_like_original=False)
 expected={'native':1,'rle':1,'jpeg':1,'three-files':3,'all-frames':3,'single-frame2':1,'selected-frame2':1}
 cases=[('native',['native.dcm'],[]),('rle',['rle.dcm'],[]),('jpeg',['jpeg.dcm'],[]),('three-files',['frame1.dcm','frame2.dcm','frame3.dcm'],['--layout','STANDARD\\2,2']),('all-frames',['multi.dcm'],['--all-frames','--layout','STANDARD\\2,2']),('single-frame2',['frame2.dcm'],[]),('selected-frame2',['multi.dcm'],['--frame','2'])]
 fixture_hash={x.name:base.sha(x) for x in fixtures.iterdir()};records=[];processes=[];logs=[];ok=False;failure=None;artifacts={};comparisons=[]
 def env(side):return dict(os.environ,DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY=str(root/(side+'-settings')))
 def sendargs(number,files,extra):return ['dicom-print','send','pacs://127.0.0.1:'+str(number),*[str(fixtures/f) for f in files],'--called-aet','M6PIXELS','--aet','M6WORKSHOP','--raw','--timeout','5','--format','json',*extra]
 def normalize(value):
  if isinstance(value,dict):return {k:normalize(v) for k,v in value.items() if k not in base.VOLATILE_JSON_KEYS}
  if isinstance(value,list):return [normalize(x) for x in value]
  return value
 try:
  ports={}
  for side in ['cli','workshop']:
   (root/(side+'-settings')).mkdir();(root/side).mkdir();number=base.port();ports[side]=number
   argv=[str(binary/'dicom-printscp'),'serve','--port',str(number),'--ae-title','M6PIXELS','--config',str(root/(side+'-absent.json')),'--output','png','--output-dir',str(root/side),'--name-pattern','film-{index}','--dpi','36','--max-pixels','1024','--max-films',str(len(cases)),'--duration','120','--format','json']
   log=(root/(side+'-receiver.log')).open('w');logs.append(log);proc=subprocess.Popen(argv,cwd=root,env=env(side),stdout=log,stderr=subprocess.STDOUT);processes.append(proc);save(root/(side+'-receiver-process.json'),{'argv':argv,'pid':proc.pid});base.wait_ready(proc,number)
  controls={};requests=[]
  for name,files,extra in cases:
   argv=sendargs(ports['cli'],files,extra);actual=[str(binary/argv[0])]+argv[1:];result=subprocess.run(actual,cwd=root,env=env('cli'),text=True,capture_output=True,timeout=30);records.append({'name':name,'argv':actual,'exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr});assert result.returncode==0,records[-1];controls[name]=json.loads(result.stdout)
   assert controls[name]['success'] is True,(name,controls[name])
   requests.append({'name':name,'command':shlex.join(sendargs(ports['workshop'],files,extra)),'expectedExit':0,'timeoutSeconds':30})
  save(root/'requests.json',requests);save(root/'cli-records.json',records)
  harness=['xcrun','xctest','-XCTest','DICOMStudioTests.M6WorkshopExecutionTests/testConfiguredWorkshopActions',str(a.test_bundle.resolve())]
  res=subprocess.run(harness,cwd=root,env=dict(env('workshop'),DICOMKIT_M6_WORKSHOP_REQUESTS=str(root/'requests.json'),DICOMKIT_M6_WORKSHOP_OUTPUT=str(root/'workshop.json')),text=True,capture_output=True,timeout=120);(root/'workshop-process.log').write_text(res.stdout+res.stderr);assert res.returncode==0,res.stdout+res.stderr
  app=json.loads((root/'workshop.json').read_text());assert len(app)==len(cases)
  for item in app:
   assert item['exit']==0 and item['historyCount']==1 and item['runningAfterCompletion'] is False and item['timedOut'] is False,item
   value=base.json_values(item['console'].split('\n\n',1)[-1])[-1];assert normalize(value)==normalize(controls[item['name']]),(item['name'],value,controls[item['name']]);comparisons.append({'name':item['name'],'CLIWorkshopJSONEqual':True,'images':expected[item['name']]})
  for process in processes:process.wait(timeout=15);assert process.returncode==0
  for log in logs:log.flush()
  for side in ['cli','workshop']:
   filmrows=[x for x in base.json_values((root/(side+'-receiver.log')).read_text()) if isinstance(x,dict) and 'filledImageBoxCount' in x]
   assert [x['filledImageBoxCount'] for x in filmrows]==list(expected.values())
   paths=sorted((root/side).glob('*.png'));assert len(paths)==len(cases),(side,paths);artifacts[side]={}
   for (name,_,_),path in zip(cases,paths):
    with Image.open(path) as img:rgba=img.convert('RGBA');artifacts[side][name]={'path':str(path),'size':list(rgba.size),'sha256':hashlib.sha256(rgba.tobytes()).hexdigest()}
   for left,right in [('native','rle'),('native','jpeg'),('three-files','all-frames'),('single-frame2','selected-frame2')]:
    assert artifacts[side][left]['sha256']==artifacts[side][right]['sha256'],(side,left,right)
   assert artifacts[side]['native']['sha256']!=artifacts[side]['single-frame2']['sha256'],'Distinct selected frame control was not distinct'
  for name in expected:assert artifacts['cli'][name]['sha256']==artifacts['workshop'][name]['sha256'],name
  assert {x.name:base.sha(x) for x in fixtures.iterdir()}==fixture_hash
  ok=True;print('M6 image extension: 7 CLI +7 Workshop sends;14 films; native/RLE/JPEG, three-files/all-frames and frame2 pixel controls passed')
 except BaseException:failure=traceback.format_exc();raise
 finally:
  for proc in reversed(processes):base.stop(proc)
  for log in logs:log.close()
  save(root/'results.json',{'passed':ok,'failure':failure,'workshopRequests':len(cases),'cliControls':len(records),'comparisons':comparisons,'artifacts':artifacts,'records':records,'fixtureSHA256':fixture_hash,'binarySHA256':{n:base.sha(binary/n) for n in ['dicom-print','dicom-printscp']},'scope':'Existing-binary CLI and actual Workshop ViewModel send actions to same-library synthetic receiver. PNG decoded pixel equality with independent native controls; no GUI or hardware claim. RLE and JPEG files originated in independent DCMTK M7 campaign.'})
if __name__=='__main__':main()
