#!/usr/bin/env python3
"""Independent codec qualification on synthetic samples, never clinical files.

Tests real dicom-convert processes against DCMTK, OpenJPEG, OpenJPH and libjxl.
Every case records commands, output, binary/fixture identities, and pixel error.
Passing these samples is not a claim about all bit depths or all platforms.
Use Scripts/m7-peer-requirements.txt for the pinned Python dependencies.
DCMTK, OpenJPEG, OpenJPH and libjxl executables must be on PATH.
Exit 0 means no unexpected failure; supported refusals and verified strict-policy
interoperability limits are reported separately and never count as codec passes.
"""
import argparse, hashlib, json, platform, shutil, struct, subprocess, sys, time, traceback
from collections import Counter
from pathlib import Path
import pydicom
import pynetdicom  # registers newer standard transfer syntax UIDs with pydicom
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.encaps import encapsulate, generate_pixel_data_frame
from PIL import Image, __version__ as pillow_version

BASE='1.2.840.10008.1.2'
TARGETS=[
 ('ExplicitVRLittleEndian',BASE+'.1','native',True),
 ('ImplicitVRLittleEndian',BASE,'native',True),
 ('ExplicitVRBigEndian',BASE+'.2','native',True),
 ('DEFLATE',BASE+'.1.99','native',True),
 ('JPEGBaseline',BASE+'.4.50','jpeg',False),
 ('JPEGExtended',BASE+'.4.51','jpeg',False),
 ('JPEGLossless',BASE+'.4.57','jpeg',True),
 ('JPEGLosslessSV1',BASE+'.4.70','jpeg',True),
 ('JPEG2000Lossy',BASE+'.4.91','j2k',False),
 ('JPEG2000Reversible',BASE+'.4.91','j2k',True),
 ('JPEG2000LosslessOnly',BASE+'.4.90','j2k',True),
 ('JPEG2000Part2Lossy',BASE+'.4.93','j2k',False),
 ('JPEG2000Part2Lossless',BASE+'.4.93','j2k',True),
 ('JPEG2000Part2LosslessOnly',BASE+'.4.92','j2k',True),
 ('HTJ2KLossy',BASE+'.4.203','htj',False),
 ('HTJ2KReversible',BASE+'.4.203','htj',True),
 ('HTJ2KLosslessOnly',BASE+'.4.201','htj',True),
 ('HTJ2KRPCLLosslessOnly',BASE+'.4.202','htj',True),
 ('JPEGLSLossless',BASE+'.4.80','jls',True),
 ('JPEGLSNearLossless',BASE+'.4.81','jls',False),
 ('JPEGXLLossy',BASE+'.4.112','jxl',False),
 ('JPEGXLReversible',BASE+'.4.112','jxl',True),
 ('JPEGXLLosslessOnly',BASE+'.4.110','jxl',True),
 ('RLELossless',BASE+'.5','rle',True)]

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,x): Path(p).write_text(json.dumps(x,indent=2,default=str)+'\n')
def require(b,m):
 if not b: raise AssertionError(m)

class CommandFailure(RuntimeError):
 def __init__(self, command, diagnostic):
  self.command=command;self.diagnostic=diagnostic
  super().__init__('Process failed: '+str(command['argv'])+'; '+diagnostic[-1500:])

def tool_provenance():
 probes={name:['--version'] for name in ['dcmcjpeg','dcmdjpeg','dcmcjpls','dcmdjpls','dcmcrle','dcmdrle','cjxl','djxl']}
 probes.update({name:['-h'] for name in ['opj_compress','opj_decompress','ojph_compress','ojph_expand']})
 probes['jxlinfo']=['--help']
 result={}
 for name,flags in probes.items():
  found=shutil.which(name)
  if found is None:result[name]={'available':False};continue
  resolved=Path(found).resolve();row={'available':True,'path':found,'resolvedPath':str(resolved),'sha256':sha(resolved),'versionProbe':[found,*flags]}
  try:
   process=subprocess.run([found,*flags],capture_output=True,text=True,timeout=10)
   row.update({'versionProbeExit':process.returncode,'versionOrHelp':process.stdout+process.stderr})
  except subprocess.TimeoutExpired:row['versionProbeError']='timed out after 10 seconds'
  result[name]=row
 return result

def pixel_metadata(ds,inp,native=False,transfer_syntax=None):
 stored=12 if inp=='gray12' else 8;spp=3 if inp=='rgb8' else 1
 require((int(ds.Rows),int(ds.Columns),int(ds.SamplesPerPixel))==(48,64,spp),'Wrong pixel dimensions/components')
 require((int(ds.BitsAllocated),int(ds.BitsStored),int(ds.HighBit),int(ds.PixelRepresentation))==(16 if stored>8 else 8,stored,stored-1,0),'Wrong depth/high-bit/signedness attributes')
 require(int(ds.get('NumberOfFrames',1))==1,'Unexpected frame count')
 require(ds.SOPInstanceUID==ds.file_meta.MediaStorageSOPInstanceUID,'File meta / dataset instance identity mismatch')
 require(ds.SOPClassUID==ds.file_meta.MediaStorageSOPClassUID,'File meta / dataset class identity mismatch')
 if transfer_syntax is not None:require(str(ds.file_meta.TransferSyntaxUID)==transfer_syntax,'Wrong transfer syntax UID')
 if native:
  require(str(ds.PhotometricInterpretation)==('RGB' if spp==3 else 'MONOCHROME2'),'Wrong decoded photometric interpretation')
  if spp==3:require(int(ds.PlanarConfiguration)==0,'Decoded RGB must be interleaved')
  else:require('PlanarConfiguration' not in ds,'Unexpected monochrome PlanarConfiguration')
  require(not ds['PixelData'].is_undefined_length,'Native output still encapsulated')
  allocated=int(ds.BitsAllocated)
  word_required=allocated>8 or str(ds.file_meta.TransferSyntaxUID)==BASE
  require(ds['PixelData'].VR in (['OW'] if word_required else ['OB','OW']),'Wrong native PixelData VR')
  expected_bytes=48*64*spp*(allocated//8)
  require(len(ds.PixelData)==expected_bytes,'Wrong native PixelData length')
 return {'rows':int(ds.Rows),'columns':int(ds.Columns),'samplesPerPixel':int(ds.SamplesPerPixel),
  'bitsAllocated':int(ds.BitsAllocated),'bitsStored':int(ds.BitsStored),'highBit':int(ds.HighBit),
  'pixelRepresentation':int(ds.PixelRepresentation),'photometricInterpretation':str(ds.PhotometricInterpretation),
  'planarConfiguration':int(ds.PlanarConfiguration) if 'PlanarConfiguration' in ds else None,
  'transferSyntax':str(ds.file_meta.TransferSyntaxUID)}

def jpeg_header(frame):
 require(frame[:2]==b'\xff\xd8','Missing JPEG SOI');offset=2
 while offset<len(frame):
  require(frame[offset]==255,'Missing JPEG header marker')
  while offset<len(frame) and frame[offset]==255:offset+=1
  require(offset<len(frame),'Truncated JPEG marker');marker=frame[offset];offset+=1
  require(marker not in [0,0xda,0xd8,0xd9] and offset+2<=len(frame),'No SOF before scan/end')
  length=int.from_bytes(frame[offset:offset+2],'big')
  require(length>=2 and length<=len(frame)-offset,'Invalid JPEG segment length')
  if marker in [0xc0,0xc1,0xc3,0xf7]:
   require(length>=8,'Truncated JPEG SOF');components=frame[offset+7]
   require(length==8+3*components,'Invalid JPEG SOF component length')
   return {'marker':marker,'precision':frame[offset+2],'rows':int.from_bytes(frame[offset+3:offset+5],'big'),
    'columns':int.from_bytes(frame[offset+5:offset+7],'big'),'components':components}
  offset+=length
 raise AssertionError('JPEG SOF missing')

def jpeg_without_single_dicom_pad(frame):
 if frame.endswith(b'\xff\xd9'):return frame
 if len(frame)%2==0 and frame.endswith(b'\xff\xd9\x00'):return frame[:-1]
 raise AssertionError('JPEG must end in EOI with at most one DICOM even-length NUL pad')

def samples(ds):
 data=ds.PixelData; n=int(ds.Rows)*int(ds.Columns)*int(ds.SamplesPerPixel)
 if ds.BitsAllocated==8:
  if str(ds.file_meta.TransferSyntaxUID)==BASE+'.2' and ds['PixelData'].VR=='OW':
   data=b''.join(data[i:i+2][::-1] for i in range(0,len(data),2))
  return list(data[:n])
 return list(struct.unpack(('>' if str(ds.file_meta.TransferSyntaxUID)==BASE+'.2' else '<')+str(n)+'H', data[:n*2]))

def raster(p):
 if Path(p).suffix in ['.pgm','.ppm']:
  data=Path(p).read_bytes(); pos=0
  def token():
   nonlocal pos
   while True:
    while data[pos] in b' \t\r\n':pos+=1
    if data[pos]!=35:break
    pos=data.index(b'\n',pos)+1
   start=pos
   while data[pos] not in b' \t\r\n':pos+=1
   return data[start:pos]
  magic=token();width=int(token());height=int(token());maximum=int(token())
  pos+=2 if data[pos:pos+2]==b'\r\n' else 1
  n=width*height*(3 if magic==b'P6' else 1)
  vals=list(data[pos:pos+n]) if maximum<256 else list(struct.unpack('>'+str(n)+'H',data[pos:pos+2*n]))
  return (width,height),vals
 with Image.open(p) as im:
  vals=list(im.getdata()); return im.size,[v for item in vals for v in (item if isinstance(item,tuple) else (item,))]

def fixture(root,name,index,bits=8,rgb=False):
 ds=FileDataset(str(root/(name+'.dcm')),{},file_meta=FileMetaDataset(),preamble=b'\0'*128)
 ds.file_meta.MediaStorageSOPClassUID='1.2.840.10008.5.1.4.1.1.7'
 ds.file_meta.MediaStorageSOPInstanceUID='1.2.826.0.1.3680043.10.543.20261024.7.'+str(index)
 ds.file_meta.TransferSyntaxUID=BASE+'.1'; ds.file_meta.ImplementationClassUID='1.2.826.0.1.3680043.10.543.7'
 ds.is_little_endian=True; ds.is_implicit_VR=False
 ds.SOPClassUID=ds.file_meta.MediaStorageSOPClassUID;ds.SOPInstanceUID=ds.file_meta.MediaStorageSOPInstanceUID
 ds.StudyInstanceUID='1.2.826.0.1.3680043.10.543.20261024.7.100';ds.SeriesInstanceUID=ds.StudyInstanceUID+'.1'
 ds.PatientName='SYNTHETIC^CODEC';ds.PatientID='M7-CODEC';ds.PatientBirthDate='';ds.PatientSex=''
 ds.StudyDate='20261024';ds.StudyTime='120000';ds.Modality='OT';ds.ConversionType='WSD';ds.ImageType=['ORIGINAL','PRIMARY']
 ds.AccessionNumber='M7-CODEC';ds.StudyID='M7';ds.SeriesNumber='1';ds.InstanceNumber=str(index)
 ds.Rows=48;ds.Columns=64;ds.SamplesPerPixel=3 if rgb else 1;ds.PhotometricInterpretation='RGB' if rgb else 'MONOCHROME2'
 ds.BitsAllocated=16 if bits>8 else 8;ds.BitsStored=bits;ds.HighBit=bits-1;ds.PixelRepresentation=0
 if rgb: ds.PlanarConfiguration=0
 maximum=(1<<bits)-1
 values=[round(maximum*((x*3+y*2+c*17)%193)/192) for y in range(48) for x in range(64) for c in range(ds.SamplesPerPixel)]
 ds.PixelData=bytes(values) if bits==8 else struct.pack('<'+str(len(values))+'H',*values)
 p=root/(name+'.dcm');ds.save_as(p,write_like_original=False)
 image=root/(name+('.ppm' if rgb else '.pgm'))
 payload=bytes(values) if bits==8 else struct.pack('>'+str(len(values))+'H',*values)
 image.write_bytes(('P6' if rgb else 'P5').encode()+b'\n64 48\n'+str(maximum).encode()+b'\n'+payload)
 return p,image,values

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--bin-dir',type=Path,required=True);ap.add_argument('--output-dir',type=Path,required=True);ap.add_argument('--smoke',action='store_true');ap.add_argument('--case',action='append',default=[])
 a=ap.parse_args();binary=(a.bin_dir/'dicom-convert').resolve()
 planned={'forward-'+t[0]+'-'+inp for t in TARGETS for inp in (['gray8'] if a.smoke else ['gray8','gray12','rgb8']) if not(inp=='gray12' and t[0]=='JPEGBaseline')}
 if not a.smoke:planned.update({'reverse-'+family+'-'+inp for family in ['jpeg','jls','rle','j2k','htj','jxl'] for inp in ['gray8','gray12','rgb8']});planned.add('forward-JPEGXLRecompression-gray8')
 if set(a.case)-planned:ap.error('Unknown or unavailable requested cases: '+', '.join(sorted(set(a.case)-planned)))
 selected=set(a.case) if a.case else planned
 require(bool(selected),'No cases selected')
 root=a.output_dir.resolve();root.mkdir(parents=True,exist_ok=False)
 fixtures=root/'fixtures';fixtures.mkdir()
 inputs={n:fixture(fixtures,n,i,b,r) for n,i,b,r in [('gray8',1,8,False),('gray12',2,12,False),('rgb8',3,8,True)]}
 save(root/'provenance.json',{'binary':str(binary),'sha256':sha(binary),'scriptSHA256':sha(__file__),'python':sys.version,'platform':platform.platform(),'machine':platform.machine(),'pydicom':pydicom.__version__,'pynetdicom':pynetdicom.__version__,'Pillow':pillow_version,'fixtures':{n:sha(p) for n,(p,_,_) in inputs.items()},'externalTools':tool_provenance(),'plannedCases':len(planned),'selectedCases':sorted(selected),'platform_scope':'Synthetic unsigned 8/12-bit monochrome and RGB8 on the recorded host; no signed/16-bit-stored/multiframe/other-platform or physical-output qualification'})
 results=[]
 def case(name,body):
  if a.case and name not in a.case:return
  d=root/name;d.mkdir();record={'name':name,'commands':[]};start=time.monotonic()
  def run(argv):
   argv=[str(x) for x in argv];idx=len(record['commands']);out=d/(str(idx)+'.stdout');err=d/(str(idx)+'.stderr')
   with out.open('wb') as o,err.open('wb') as e:
    try: proc=subprocess.run(argv,stdout=o,stderr=e,timeout=60)
    except subprocess.TimeoutExpired: record['commands'].append({'argv':argv,'timeout':60});raise
   command={'argv':argv,'exit':proc.returncode,'stdout':out.name,'stderr':err.name};record['commands'].append(command)
   if proc.returncode!=0:raise CommandFailure(command,err.read_text(errors='replace'))
  try:body(d,run,record);record['status']='passed'
  except Exception as e:
   record['status']='failed';record['error']=str(e);(d/'traceback.txt').write_text(traceback.format_exc())
   if isinstance(e,CommandFailure) and e.command['exit']>0 and e.command['argv'][0]==str(binary):
    diagnostic=e.diagnostic
    part2={'forward-'+token+'-'+inp for token in ['JPEG2000Part2Lossy','JPEG2000Part2Lossless','JPEG2000Part2LosslessOnly'] for inp in ['gray8','gray12','rgb8']}
    unsupported=(name in part2 and 'encoding is not supported: the JPEG 2000 Part-2 multi-component transform cannot be inverted by the current decoder' in diagnostic)
    unsupported=unsupported or (name=='forward-JPEGExtended-rgb8' and all(x in diagnostic for x in ['JPEG Extended (Process 2 & 4)', 'needs 1 samples per pixel, but the source has 3.', '3 samples per pixel, RGB']))
    if unsupported and len(record['commands'])==1 and not (d/'encoded.dcm').exists():
     record['status']='supported_refusal';record['refusalVerified']={'positiveNonzeroExit':e.command['exit'],'outputAbsent':True,'diagnosticMatched':True,'countsAsCodecPass':False}
    precision_reason={'reverse-jpeg-gray12':'JPEG header does not match DICOM dimensions, components or precision',
     'reverse-jls-gray12':'JPEG-LS precision mismatch is outside the selected recovery policy'}
    if name in precision_reason and precision_reason[name] in diagnostic and record.get('independent_foreign_exact') is True and record.get('precision_policy_case_verified') is True and not (d/'decoded.dcm').exists():
     record['status']='interoperability_limit';record['limitVerified']={'positiveNonzeroExit':e.command['exit'],'outputAbsent':True,'independentDecodeExact':True,'countsAsCodecPass':False,
      'scope':'Actual independently encoded and decoded unsigned monochrome16precision/12stored stream; current strict descriptor policy refuses it. No determination that this peer is nonconformant.'}
  record['elapsed_seconds']=time.monotonic()-start;save(d/'result.json',record);results.append(record);print(name,record['status'],record.get('error',''),flush=True);save(root/'summary.json',results)
 def decode_independent(file,family,d,run):
  if family=='native': return samples(pydicom.dcmread(file))
  if family in ['jpeg','jls','rle']:
   target=d/'foreign-decoded.dcm';run([shutil.which({'jpeg':'dcmdjpeg','jls':'dcmdjpls','rle':'dcmdrle'}[family]),file,target]);return samples(pydicom.dcmread(target))
  ds=pydicom.dcmread(file);frame=next(generate_pixel_data_frame(ds.PixelData,1));stream=d/('stream.'+{'j2k':'j2k','htj':'jph','jxl':'jxl'}[family]);stream.write_bytes(frame)
  output=d/('foreign-decoded.ppm' if int(ds.SamplesPerPixel)==3 else 'foreign-decoded.pgm')
  if family=='j2k':run([shutil.which('opj_decompress'),'-i',stream,'-o',output])
  elif family=='htj':run([shutil.which('ojph_expand'),'-i',stream,'-o',output])
  else:
   run([shutil.which('jxlinfo'),stream])
   # PNM represents the codestream's original precision, unlike PNG which
   # rescales 12-bit samples to16 bits. Keep exact integer samples, not a
   # tolerance or a normalization derived from the expected source values.
   run([shutil.which('djxl'),stream,output,'--bits_per_sample=0'])
  size,values=raster(output);require(size==(64,48),'Wrong oracle dimensions');return values
 def forward(d,run,record,target,inp):
  token,uid,family,lossless=target;p,_,expected=inputs[inp];output=d/'encoded.dcm'
  run([binary,p,'--output',output,'--transfer-syntax',token]);ds=pydicom.dcmread(output)
  record['encoded_metadata']=pixel_metadata(ds,inp,native=family=='native',transfer_syntax=uid)
  oracle=decode_independent(output,family,d,run);require(len(oracle)==len(expected),'Wrong sample count')
  errors=[abs(x-y) for x,y in zip(oracle,expected)];record['max_source_error']=max(errors);record['mean_source_error']=sum(errors)/len(errors)
  if lossless: require(max(errors)==0,'Lossless output differs from original samples')
  else:
   require(record['mean_source_error']<((1<<int(ds.BitsStored))-1)*.15,'Unexpectedly severe lossy distortion')
   require(str(ds.LossyImageCompression)=='01','Missing lossy provenance')
  back=d/'self-decoded.dcm';run([binary,output,'--output',back,'--transfer-syntax','ExplicitVRLittleEndian']);decoded=pydicom.dcmread(back);record['decoded_metadata']=pixel_metadata(decoded,inp,native=True,transfer_syntax=BASE+'.1');actual=samples(decoded)
  require(len(actual)==len(oracle),'Self decoder sample count mismatch');delta=max(abs(x-y) for x,y in zip(actual,oracle));record['max_decoder_disagreement']=delta
  require(delta<=(0 if lossless else 2),'Decoder disagrees with independent oracle')
 for t in TARGETS:
  for inp in (['gray8'] if a.smoke else ['gray8','gray12','rgb8']):
   if inp=='gray12' and t[0]=='JPEGBaseline': continue
   case('forward-'+t[0]+'-'+inp,lambda d,run,rec,t=t,inp=inp:forward(d,run,rec,t,inp))
 def reverse(d,run,rec,family,inp):
  p,image,expected=inputs[inp];foreign=d/'foreign.dcm'
  if family in ['jpeg','jls','rle']:
   exe={'jpeg':'dcmcjpeg','jls':'dcmcjpls','rle':'dcmcrle'}[family];run([shutil.which(exe),p,foreign])
  else:
   stream=d/('foreign.'+{'j2k':'j2k','htj':'jph','jxl':'jxl'}[family]);uid={'j2k':BASE+'.4.90','htj':BASE+'.4.201','jxl':BASE+'.4.110'}[family]
   if family=='j2k':run([shutil.which('opj_compress'),'-i',image,'-o',stream,'-n','4'])
   elif family=='htj':run([shutil.which('ojph_compress'),'-i',image,'-o',stream,'-reversible','true','-num_decomps','3'])
   else:run([shutil.which('cjxl'),image,stream,'-d','0','-e','3'])
   ds=pydicom.dcmread(p);ds.file_meta.TransferSyntaxUID=uid;ds.PixelData=encapsulate([stream.read_bytes()]);ds['PixelData'].is_undefined_length=True
   if inp=='rgb8' and family in ['j2k','htj']:ds.PhotometricInterpretation='YBR_RCT'
   ds.save_as(foreign,write_like_original=False)
  independent=decode_independent(foreign,family,d,run)
  require(independent==expected,'Independent encoder/decoder pair did not reproduce exact source samples')
  rec['independent_foreign_exact']=True;rec['independent_sample_count']=len(independent)
  foreign_ds=pydicom.dcmread(foreign);rec['foreign_metadata']=pixel_metadata(foreign_ds,inp)
  if family in ['jpeg','jls']:
   header=jpeg_header(next(generate_pixel_data_frame(foreign_ds.PixelData,1)));rec['foreign_header']=header
   expected_uid=BASE+('.4.70' if family=='jpeg' else '.4.80')
   rec['precision_policy_case_verified']=(inp=='gray12' and str(foreign_ds.file_meta.TransferSyntaxUID)==expected_uid and header=={'marker':0xc3 if family=='jpeg' else 0xf7,'precision':16,'rows':48,'columns':64,'components':1})
  out=d/'decoded.dcm';run([binary,foreign,'--output',out,'--transfer-syntax','ExplicitVRLittleEndian']);decoded=pydicom.dcmread(out)
  rec['decoded_metadata']=pixel_metadata(decoded,inp,native=True,transfer_syntax=BASE+'.1');actual=samples(decoded)
  require(actual==expected,'Independent lossless stream did not decode to exact source samples');rec['sample_count']=len(actual)
 if not a.smoke:
  for family in ['jpeg','jls','rle','j2k','htj','jxl']:
   for inp in ['gray8','gray12','rgb8']:
    case('reverse-'+family+'-'+inp,lambda d,run,rec,f=family,i=inp:reverse(d,run,rec,f,i))
 def recompress(d,run,rec):
  source=inputs['gray8'][0];jpeg=d/'original-jpeg.dcm'
  run([shutil.which('dcmcjpeg'),'+eb',source,jpeg])
  original=next(generate_pixel_data_frame(pydicom.dcmread(jpeg).PixelData,1))
  output=d/'recompressed.dcm';run([binary,jpeg,'--output',output,'--transfer-syntax','JPEGXLRecompression'])
  ds=pydicom.dcmread(output);rec['encoded_metadata']=pixel_metadata(ds,'gray8',transfer_syntax=BASE+'.4.111')
  stream=d/'stream.jxl';stream.write_bytes(next(generate_pixel_data_frame(ds.PixelData,1)))
  restored=d/'restored.jpg';run([shutil.which('djxl'),stream,restored])
  normalized=jpeg_without_single_dicom_pad(original);reconstructed=jpeg_without_single_dicom_pad(restored.read_bytes())
  require(reconstructed==normalized,'JPEG reconstruction differs beyond an allowed single DICOM even-length pad')
  rec['reconstructionComparison']='Exact JPEG bytes with at most one trailing DICOM even-length NUL pad excluded'
  rec['originalFragmentBytes']=len(original);rec['restoredJPEGBytes']=len(restored.read_bytes())
  back=d/'decoded.dcm';run([binary,output,'--output',back,'--transfer-syntax','ExplicitVRLittleEndian'])
  oracle=decode_independent(jpeg,'jpeg',d,run);decoded=pydicom.dcmread(back);rec['decoded_metadata']=pixel_metadata(decoded,'gray8',native=True,transfer_syntax=BASE+'.1');actual=samples(decoded)
  require(len(actual)==len(oracle) and max(abs(x-y) for x,y in zip(actual,oracle))<=2,'Recompression decode disagrees with independent JPEG decoder')
  rec['jpeg_sha256']=hashlib.sha256(normalized).hexdigest()
 if not a.smoke:case('forward-JPEGXLRecompression-gray8',recompress)
 require(bool(results),'No cases executed')
 require({r['name'] for r in results}==selected,'Unknown, missing or unexecuted requested case')
 counts=Counter(x['status'] for x in results)
 totals={'executed':len(results),'selected':len(selected),**{key:counts[key] for key in ['passed','supported_refusal','interoperability_limit','failed']},
  'meaning':'Only passed counts as codec qualification. Supported refusals and independently verified interoperability limits are separate. Exit0 means no unexpected failure, not complete codec support.'}
 require({n:sha(p) for n,(p,_,_) in inputs.items()}==json.loads((root/'provenance.json').read_text())['fixtures'],'Input fixtures changed during campaign')
 save(root/'totals.json',totals);print('Codec summary: '+json.dumps(totals,sort_keys=True),flush=True)
 return 1 if counts['failed'] else 0

if __name__=='__main__':raise SystemExit(main())
