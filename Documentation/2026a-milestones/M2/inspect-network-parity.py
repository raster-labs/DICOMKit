#!/usr/bin/env python3
"""Recheck saved M2 captures without loading DICOMKit or contacting a peer.
Run from any directory; optional first argument is the evidence directory.
Only network-parity.json is written. Assertions fail on inconsistent evidence.
"""
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

BASE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent
checked = set()

def read(path):
    path = BASE / path
    checked.add(path)
    return path.read_bytes()

def obj(path):
    return json.loads(read(path))

def text(path):
    return read(path).decode()

def decode_explicit_le(data):
    """Length-based Explicit VR LE decoder, including nested SQ/item delimiters."""
    pos = 0
    def take(size):
        nonlocal pos
        assert pos + size <= len(data), 'truncated value'
        value = data[pos:pos + size]
        pos += size
        return value
    def integer(size):
        return int.from_bytes(take(size), 'little')
    def tag():
        group, element = struct.unpack('<HH', take(4))
        return f'{group:04X}{element:04X}'
    def dataset(end, delimiter=None):
        nonlocal pos
        result = {}
        while pos < end:
            key = tag()
            if key == delimiter:
                assert integer(4) == 0
                return result
            assert not key.startswith('FFFE'), f'unexpected delimiter {key}'
            assert key not in result, f'duplicate tag {key}'
            vr = take(2).decode('ascii')
            if vr in {'OB','OD','OF','OL','OV','OW','SQ','SV','UC','UN','UR','UT','UV'}:
                assert integer(2) == 0
                length = integer(4)
            else:
                length = integer(2)
            if vr == 'SQ':
                sequence_end = end if length == 0xFFFFFFFF else pos + length
                items = []
                while pos < sequence_end:
                    item_tag, item_length = tag(), integer(4)
                    if item_tag == 'FFFEE0DD':
                        assert length == 0xFFFFFFFF and item_length == 0
                        break
                    assert item_tag == 'FFFEE000'
                    item_end = sequence_end if item_length == 0xFFFFFFFF else pos + item_length
                    items.append(dataset(item_end, 'FFFEE00D' if item_length == 0xFFFFFFFF else None))
                result[key] = {'vr': vr, 'items': items}
            else:
                assert length != 0xFFFFFFFF and length % 2 == 0
                result[key] = {'vr': vr, 'value': take(length).decode('ascii').rstrip('\x00 ')}
        assert delimiter is None, f'missing {delimiter}'
        return result
    result = dataset(len(data))
    assert pos == len(data)
    return result

def argument(argv, option):
    return argv[argv.index(option) + 1]

classes = {'CT':'1.2.840.10008.5.1.4.1.1.2', 'MR':'1.2.840.10008.5.1.4.1.1.4', 'SC':'1.2.840.10008.5.1.4.1.1.7'}
cli = obj('mpps-cli.json')
missing = next(x for x in cli if x['label'] == 'missing')
diagnostic = '--image-uid requires --sop-class-uid from the referenced object:'
assert missing['exit'] == 64 and diagnostic in missing['stderr'] and missing['stdout'] == ''
gui_missing = text('ui/mpps-no-class.txt')
assert 'Console ERROR' in gui_missing and diagnostic in gui_missing
assert 'MPPS instance updated' not in gui_missing
ready = obj('mpps-capture/ready.json')
assert ready['transferSyntax'] == '1.2.840.10008.1.2.1'
finished = obj('mpps-capture/finished.json')
assert finished == {'associations': 6, 'capturedDataSets': 6}
assert len(list((BASE / 'mpps-capture').glob('*.dcmdata'))) == 6
mpps = []
normalized = {}
for number, (surface, label) in enumerate([(s,k) for s in ['CLI','GUI'] for k in classes], 1):
    source = f'mpps-capture/request-{number:03}.dcmdata'
    dataset = decode_explicit_le(read(source))
    assert dataset['00400252']['value'] == 'COMPLETED'
    series = dataset['00400340']['items']
    assert len(series) == 1
    image_items = series[0]['00081140']['items']
    pairs = [{'sopClassUID': item['00081150']['value'], 'sopInstanceUID': item['00081155']['value']} for item in image_items]
    command = next(x for x in cli if x['label'] == label)
    assert command['exit'] == 0
    expected = [{'sopClassUID': argument(command['argv'], '--sop-class-uid'),
                 'sopInstanceUID': argument(command['argv'], '--image-uid')}]
    assert expected[0]['sopClassUID'] == classes[label] and pairs == expected
    assert series[0]['0020000E']['value'] == argument(command['argv'], '--series-uid')
    assert pairs == obj(f'mpps-capture/request-{number:03}.json')
    if surface == 'GUI':
        ui = text(f'ui/mpps-{label}.txt')
        assert 'Console SUCCESS' in ui and 'MPPS instance updated' in ui
        assert 'Referenced SOP Class UID, Value: ' + classes[label] + ',' in ui
        assert 'Image SOP Instance UIDs, Value: ' + pairs[0]['sopInstanceUID'] + ',' in ui
    # Each surface records the terminal update at its own time; all other fields must match.
    stable = {key: value for key,value in dataset.items() if key not in {'00400250','00400251'}}
    if surface == 'CLI': normalized[label] = stable
    else: assert stable == normalized[label], f'{label} non-time MPPS dataset differs'
    mpps.append({'request': source, 'surface': surface, 'modality_case': label,
                 'seriesInstanceUID': series[0]['0020000E']['value'], 'references': pairs,
                 'decoded_status': dataset['00400252']['value']})

ups_cli = obj('ups-cli.json')
assert len(ups_cli) == 2 and all(x['exit'] == 0 for x in ups_cli)
assert obj('ups-capture-final/finished.json') == {'requests': 4}
requests = [obj(f'ups-capture-final/request-{i:03}.json') for i in range(1,5)]
for i, request in enumerate(requests, 1):
    assert read(f'ups-capture-final/request-{i:03}.body').decode() == request['body']
assert [r['method'] for r in requests] == ['POST','GET','POST','GET']
assert requests[0]['path'] == requests[2]['path'] == '/dicom-web/workitems'
assert requests[1]['path'] == '/dicom-web/workitems/2.25.20261024001'
assert requests[3]['path'] == '/dicom-web/workitems/2.25.20261024002'
post_cli, post_gui = json.loads(requests[0]['body']), json.loads(requests[2]['body'])
assert post_cli == post_gui
assert post_cli['00404005'] == {'vr':'DT','Value':['20261024103000.123456+0530']}
value = post_cli['00404005']['Value'][0]
assert re.fullmatch(r'\d{14}\.\d{6}[+-]\d{4}', value)
instant = dt.datetime.strptime(value, '%Y%m%d%H%M%S.%f%z').astimezone(dt.timezone.utc).isoformat()
assert instant == '2026-10-24T05:00:00.123456+00:00'
assert 'Created worklist item:' in text('ui/ups-create-json.txt')
get_ui = text('ui/ups-get.txt')
assert '2.25.20261024002 SCHEDULED' in get_ui and 'M2 synthetic schedule' in get_ui

report = {
 'result':'PASS', 'method':'Offline independent standard-library TLV/JSON inspection; no DICOMKit import or peer traffic',
 'mpps':{'associations':6, 'datasets':6, 'requests':mpps,
  'missing_class':{'CLI_exit':64, 'CLI_diagnostic':True,'GUI_error_and_diagnostic':True,
   'extra_associations':0,'basis':'All 6 associations have 6 expected successful CT/MR/SC datasets; CLI and GUI missing-class runs add none'},
  'CLI_GUI_normalized_datasets_equal':True,'normalization_excludes':['00400250 PPS End Date','00400251 PPS End Time'],
  'mixed_classes':'Existing typed service API covered by final/DICOMNetworkTests.log; no mixed-class CLI/GUI form is claimed'},
 'ups':{'requests':4,'sequence':['CLI POST','CLI GET','GUI POST','GUI GET'],
  'normalized_POST_JSON_equal':True,'scheduled_DT':value,'independently_decoded_UTC_instant':instant,
  'GUI_get':'Table showed UID, state and label; scheduled DT visibility is not claimed',
  'scope':'Client request parity against capture fixture; production server DT response/instant validation is established by final/DICOMWebTests.log',
  'excluded_evidence':'ups-capture (initial probe failed because fixture wrongly required client SOP Instance UID; corrected fixture assigns UID)'},
 'limitations':['Synthetic loopback fixtures; no external PACS interoperability qualification.',
  'Explicit SOP Class/Instance pairs were entered; no new source-file import or automatic class inference.',
  'Intermediate MPPS updates and new UPS GUI update routes remain outside M2 scope.'],
 'evidence_sha256':{str(p.relative_to(BASE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(checked)}
}
(BASE / 'network-parity.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: 6 MPPS datasets/associations, zero extra missing-class associations; 4 UPS requests with equal POST JSON and preserved compact DT.')
