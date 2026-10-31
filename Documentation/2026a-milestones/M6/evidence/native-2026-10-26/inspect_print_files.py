#!/usr/bin/env python3
"""Read-only raster/container comparison; no DICOMKit, shell, or network call."""
import argparse,hashlib,json
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('paths',nargs='+',type=Path);p.add_argument('--expect-equal',action='store_true');a=p.parse_args();rows=[]
for path in a.paths:
 if path.suffix.lower()=='.pdf':
  raw=path.read_bytes();ok=raw.startswith(b'%PDF-') and b'%%EOF' in raw[-1024:]
  if not ok:raise SystemExit('Incomplete PDF: '+str(path))
  rows.append({'path':str(path),'PDFContainerComplete':True,'rasterVerified':False})
 else:
  with Image.open(path) as image:
   image.load();rgba=image.convert('RGBA');rows.append({'path':str(path),'size':list(rgba.size),'rgbaSHA256':hashlib.sha256(rgba.tobytes()).hexdigest()})
if a.expect_equal:
 rasters=[(r['size'],r['rgbaSHA256']) for r in rows if 'rgbaSHA256'in r]
 if len(rasters)<2 or any(x!=rasters[0] for x in rasters):raise SystemExit('Raster mismatch or fewer than two raster files')
print(json.dumps(rows,indent=2))
