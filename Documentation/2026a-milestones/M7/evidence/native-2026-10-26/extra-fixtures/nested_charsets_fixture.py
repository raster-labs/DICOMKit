#!/usr/bin/env python3
"""Synthetic fixture and independent byte/charset oracle; never invokes DICOMKit."""
from __future__ import annotations
import argparse, copy, hashlib, json, pathlib, struct, warnings
import pydicom
from pydicom.dataset import Dataset
from pydicom.sequence import Sequence

HERE = pathlib.Path(__file__).resolve().parent
TASK = HERE.parents[3]
BASE = TASK / 'work/m7/integrated-final/m2/cli/fixtures/latin1-patient.dcm'
FIXTURE = HERE / 'nested-charsets.dcm'
SEQ = '00400275'
TEXT = {
    '00100010': 'Müller^Jörg',
    f'{SEQ}[0]/00321032': 'Müller^Jörg',
    f'{SEQ}[0]/00321060': '  Héritage Café',
    f'{SEQ}[0]/00400008[0]/00080104': '  Café Über',
    f'{SEQ}[1]/00321032': 'Renée^患者',
    f'{SEQ}[1]/00321060': '  雪の検査',
    f'{SEQ}[1]/00400008[0]/00080104': '  雪の診断',
    f'{SEQ}[2]/00321032': 'Yamada^Tarou=山田^太郎',
    f'{SEQ}[2]/00321060': '  日本検査',
    f'{SEQ}[2]/00400008[0]/00080104': '  日本コード',
}
LONG = {'OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'SQ', 'SV', 'UC', 'UN', 'UR', 'UT', 'UV'}

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def read_dataset(data, start, end, stop_at_item=False):
    """Parse Part10 Explicit VR Little Endian independently of pydicom."""
    pos, elements = start, []
    while pos < end:
        assert pos + 8 <= end, f'truncated header at {pos}'
        group, elem = struct.unpack_from('<HH', data, pos)
        if group == 0xfffe:
            length, = struct.unpack_from('<I', data, pos+4)
            if elem == 0xe00d and stop_at_item:
                assert length == 0
                return elements, pos+8
            raise AssertionError(f'unexpected delimiter {group:04X}{elem:04X} at {pos}')
        vr = data[pos+4:pos+6].decode('ascii')
        assert vr.isalpha() and vr.isupper(), f'invalid VR {vr!r}'
        if vr in LONG:
            assert data[pos+6:pos+8] == b'\0\0'
            length, = struct.unpack_from('<I', data, pos+8)
            value_start = pos+12
        else:
            length, = struct.unpack_from('<H', data, pos+6)
            value_start = pos+8
        item = {'tag': f'{group:04X}{elem:04X}', 'vr': vr, 'offset': pos,
                'value_offset': value_start, 'length': length}
        if vr == 'SQ':
            q, seq_end, children = value_start, end if length == 0xffffffff else value_start+length, []
            assert seq_end <= end
            while q < seq_end:
                g, e, n = struct.unpack_from('<HHI', data, q)
                assert g == 0xfffe
                if e == 0xe0dd:
                    assert length == 0xffffffff and n == 0
                    q += 8
                    break
                assert e == 0xe000
                if n == 0xffffffff:
                    child, q = read_dataset(data, q+8, seq_end, stop_at_item=True)
                else:
                    child, child_end = read_dataset(data, q+8, q+8+n)
                    assert child_end == q+8+n
                    q = child_end
                children.append(child)
            if length != 0xffffffff: assert q == seq_end
            item['items'] = children
            pos = q
        else:
            assert length != 0xffffffff and value_start+length <= end
            item['raw_hex'] = data[value_start:value_start+length].hex()
            pos = value_start+length
        elements.append(item)
    assert pos == end
    return elements, pos

def decode(raw, declaration):
    codec = {'ISO_IR 100':'latin-1', 'ISO_IR 192':'utf-8', '\\ISO 2022 IR 87':'iso2022_jp', '':'ascii'}[declaration]
    return raw.decode(codec).rstrip(' ')

def inspect(path):
    data = path.read_bytes()
    assert data[128:132] == b'DICM'
    root, end = read_dataset(data, 132, len(data))
    assert end == len(data)
    by_path, scopes = {}, {}
    def walk(elements, inherited='', prefix=''):
        declaration_element = next((x for x in elements if x['tag'] == '00080005'), None)
        local = bytes.fromhex(declaration_element['raw_hex']).decode('ascii').rstrip(' ') if declaration_element else None
        effective = local if local is not None else inherited
        scopes[prefix or 'ROOT'] = {'local_declaration': local, 'effective_declaration': effective}
        for x in elements:
            p = prefix+x['tag']
            if 'items' in x:
                for i, child in enumerate(x['items']): walk(child, effective, p+f'[{i}]/')
            else:
                record = {**x, 'path':p, 'effective_declaration':effective}
                if x['vr'] in ('PN','LO','SH','ST','LT','UT','UC'):
                    record['decoded'] = decode(bytes.fromhex(x['raw_hex']), effective)
                elif x['vr'] in ('CS','UI','DA','TM','IS','DS'):
                    record['decoded'] = bytes.fromhex(x['raw_hex']).decode('ascii').rstrip(' \0')
                by_path[p] = record
    walk(root)
    return {'file':str(path.resolve()), 'sha256':digest(path), 'size':len(data),
            'parser':'manual Explicit VR Little Endian tag/item walker + Python codecs; no DICOMKit',
            'scopes':scopes, 'values':by_path}

def pydicom_paths(ds, prefix=''):
    result={}
    for e in ds:
        p=prefix+f'{e.tag.group:04X}{e.tag.element:04X}'
        if e.VR == 'SQ':
            for i,item in enumerate(e.value): result.update(pydicom_paths(item,p+f'[{i}]/'))
        else: result[p]=(e.VR,str(e.value))
    return result

def verify(path, edited=False):
    wire=inspect(path)
    independent=pydicom_paths(pydicom.dcmread(path))
    wanted={**TEXT, '00081030': '  Native nested text' if edited else '  Nested charset source'}
    for p, text in wanted.items():
        assert wire['values'][p]['decoded'] == text, (p,wire['values'][p],text)
        assert independent[p][1] == text, (p,independent[p],text)
        assert independent[p][0] == wire['values'][p]['vr']
        assert wire['values'][p]['length'] % 2 == 0
    scopes=wire['scopes']
    assert scopes['ROOT']['local_declaration'] == 'ISO_IR 100'
    assert scopes[f'{SEQ}[0]/']['local_declaration'] is None
    assert scopes[f'{SEQ}[0]/']['effective_declaration'] == 'ISO_IR 100'
    assert scopes[f'{SEQ}[1]/']['local_declaration'] == 'ISO_IR 192'
    assert scopes[f'{SEQ}[2]/']['local_declaration'] == ('ISO_IR 192' if edited else '\\ISO 2022 IR 87')
    for i in range(3):
        child=f'{SEQ}[{i}]/00400008[0]/'
        assert scopes[child]['local_declaration'] is None
        assert scopes[child]['effective_declaration'] == scopes[f'{SEQ}[{i}]/']['effective_declaration']
    if not edited:
        assert 'fc' in wire['values'][f'{SEQ}[0]/00321032']['raw_hex']
        assert '1b2442' in wire['values'][f'{SEQ}[2]/00321032']['raw_hex']
    wire['pydicom_version']=pydicom.__version__
    wire['asserted_text_paths']=wanted
    wire['assertions_passed']=True
    wire['kind']='edited-output independently checked' if edited else 'synthetic-input independently checked'
    return wire

def generate():
    assert not FIXTURE.exists(), 'Refusing to overwrite existing synthetic fixture'
    source_hash=digest(BASE)
    ds=copy.deepcopy(pydicom.dcmread(BASE))
    ds.SOPInstanceUID='1.2.826.0.1.3680043.10.543.20261026.31'
    ds.file_meta.MediaStorageSOPInstanceUID=ds.SOPInstanceUID
    ds.StudyInstanceUID='1.2.826.0.1.3680043.10.543.20261026.30'
    ds.SeriesInstanceUID='1.2.826.0.1.3680043.10.543.20261026.32'
    ds.StudyDescription='  Nested charset source'
    items=[]
    for i in range(3):
        item=Dataset()
        if i == 1: item.SpecificCharacterSet='ISO_IR 192'
        if i == 2: item.SpecificCharacterSet=['','ISO 2022 IR 87']
        item.RequestingPhysician=TEXT[f'{SEQ}[{i}]/00321032']
        item.RequestedProcedureDescription=TEXT[f'{SEQ}[{i}]/00321060']
        child=Dataset()
        child.CodeValue='LOCAL'
        child.CodingSchemeDesignator='99NATIVE'
        child.CodeMeaning=TEXT[f'{SEQ}[{i}]/00400008[0]/00080104']
        item.ScheduledProtocolCodeSequence=Sequence([child])
        items.append(item)
    ds.RequestAttributesSequence=Sequence(items)
    with warnings.catch_warnings():
        warnings.simplefilter('error')
        pydicom.dcmwrite(FIXTURE,ds,enforce_file_format=True)
    wire=verify(FIXTURE)
    assert digest(BASE) == source_hash
    save(HERE/'nested-charsets-wire-oracle.json',wire)
    manifest={'fixture':str(FIXTURE), 'sha256':digest(FIXTURE),'size':FIXTURE.stat().st_size,
              'source':str(BASE),'source_sha256_before_and_after':source_hash,
              'synthetic':True,'status':'fixture prepared and independently checked; native/product execution not performed',
              'scope':'Generic nested charset/data preservation control, not a complete SC IOD conformance fixture',
              'generator':str(pathlib.Path(__file__).resolve()),'pydicom_version':pydicom.__version__,
              'expected_text_paths':wire['asserted_text_paths'],'source_scope_declarations':wire['scopes'],
              'edit':'StudyDescription=  Native nested text',
              'edited_declaration_expectations':{'ROOT':'ISO_IR 100',f'{SEQ}[0]/':None,f'{SEQ}[1]/':'ISO_IR 192',f'{SEQ}[2]/':'ISO_IR 192'},
              'expected_after_edit':'All text preserved exactly; root Latin1 and inherited item stay Latin1. Existing explicit item overrides normalize to UTF8 with truthful declarations. Do not demand unchanged Japanese ISO2022 bytes after an edit.',
              'wire_oracle':str(HERE/'nested-charsets-wire-oracle.json')}
    save(HERE/'nested-charsets-manifest.json',manifest)
    print(json.dumps({'fixture':str(FIXTURE),'sha256':digest(FIXTURE),'size':FIXTURE.stat().st_size,'text_paths_checked':len(wire['asserted_text_paths']),'original_unchanged':True},ensure_ascii=False))

if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--verify',type=pathlib.Path)
    p.add_argument('--edited',action='store_true')
    p.add_argument('--report',type=pathlib.Path)
    a=p.parse_args()
    if a.verify:
        result=verify(a.verify,a.edited)
        if a.report: save(a.report,result)
        print(json.dumps({'file':str(a.verify),'assertions_passed':True,'text_paths_checked':len(result['asserted_text_paths'])}))
    else: generate()
