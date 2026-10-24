#!/usr/bin/env python3
"""Independent Explicit VR Little Endian SR fixture for WS-FIX-07.

No DICOMKit serializer or product formatter is used. Invalid temporal controls
are intentional display-retention probes, not claims of IOD conformance.
"""
import argparse
import hashlib
import json
import pathlib
import struct

SAMPLES = [
    ("TIME fraction", "TM", "101530.123456", "10:15:30.123456"),
    ("TIME next fraction", "TM", "101530.123457", "10:15:30.123457"),
    ("TIME trailing zeros", "TM", "101530.120000", "10:15:30.120000"),
    ("TIME hour", "TM", "10", "10"),
    ("TIME minute", "TM", "1015", "10:15"),
    ("DATETIME positive offset", "DT", "20261024101530.123456+0530", "2026-10-24 10:15:30.123456 +0530"),
    ("DATETIME negative offset", "DT", "20261024101530.123456-0330", "2026-10-24 10:15:30.123456 -0330"),
    ("DATETIME year", "DT", "2026", "2026"),
    ("DATETIME month", "DT", "202610", "2026-10"),
    ("DATETIME date", "DT", "20261024", "2026-10-24"),
    ("DATETIME hour", "DT", "2026102410", "2026-10-24 10"),
    ("DATETIME minute", "DT", "202610241015", "2026-10-24 10:15"),
    ("DATETIME zeros UTC", "DT", "20261024101530.120000+0000", "2026-10-24 10:15:30.120000 +0000"),
    ("DATETIME partial offset", "DT", "2026+0530", "2026 +0530"),
    ("Malformed TIME retained", "TM", "101530.1234567", "101530.1234567"),
    ("Malformed DATETIME retained", "DT", "20260230101530+0530", "20260230101530+0530"),
]


def element(tag, vr, value):
    payload = value.encode('ascii') if isinstance(value, str) else value
    if len(payload) % 2:
        payload += b'\0' if vr in ('UI', 'OB') else b' '
    prefix = struct.pack('<HH', *tag) + vr.encode('ascii')
    if vr in ('OB', 'OW', 'SQ', 'UN', 'UT'):
        return prefix + b'\0\0' + struct.pack('<I', len(payload)) + payload
    return prefix + struct.pack('<H', len(payload)) + payload


def dataset(rows):
    return b''.join(element(tag, vr, value) for tag, vr, value in sorted(rows))


def sequence(items):
    return b''.join(struct.pack('<HHI', 0xfffe, 0xe000, len(item)) + item for item in items)


def concept(code, meaning):
    return sequence([dataset([((8, 0x100), 'SH', code), ((8, 0x102), 'SH', '99DICOMKIT'),
                              ((8, 0x104), 'LO', meaning)])])


def make_file():
    sop_class = '1.2.840.10008.5.1.4.1.1.88.11'
    sop_instance = '2.25.550001'
    content = []
    for index, (label, vr, raw, _) in enumerate(SAMPLES):
        content.append(dataset([
            ((0x40, 0xa010), 'CS', 'CONTAINS'),
            ((0x40, 0xa040), 'CS', 'TIME' if vr == 'TM' else 'DATETIME'),
            ((0x40, 0xa043), 'SQ', concept('M5T' + str(index), label)),
            ((0x40, 0xa122 if vr == 'TM' else 0xa120), vr, raw),
        ]))
    body = dataset([
        ((8, 0x16), 'UI', sop_class), ((8, 0x18), 'UI', sop_instance),
        ((8, 0x20), 'DA', '20261024'), ((8, 0x23), 'DA', '20261024'),
        ((8, 0x30), 'TM', '101530'), ((8, 0x33), 'TM', '101530.123456'),
        ((8, 0x60), 'CS', 'SR'), ((8, 0x1030), 'LO', 'M5 Temporal Precision'),
        ((8, 0x103e), 'LO', 'M5 Temporal Precision'),
        ((0x10, 0x10), 'PN', 'M5^Temporal^Synthetic'), ((0x10, 0x20), 'LO', 'M5SR001'),
        ((0x20, 0xd), 'UI', '2.25.550002'), ((0x20, 0xe), 'UI', '2.25.550003'),
        ((0x20, 0x11), 'IS', '1'), ((0x20, 0x13), 'IS', '1'),
        ((0x40, 0xa040), 'CS', 'CONTAINER'),
        ((0x40, 0xa043), 'SQ', concept('M5SR', 'M5 Temporal Precision')),
        ((0x40, 0xa050), 'CS', 'SEPARATE'), ((0x40, 0xa491), 'CS', 'COMPLETE'),
        ((0x40, 0xa493), 'CS', 'UNVERIFIED'), ((0x40, 0xa730), 'SQ', sequence(content)),
    ])
    meta = dataset([
        ((2, 1), 'OB', b'\0\1'), ((2, 2), 'UI', sop_class), ((2, 3), 'UI', sop_instance),
        ((2, 0x10), 'UI', '1.2.840.10008.1.2.1'), ((2, 0x12), 'UI', '2.25.550099'),
        ((2, 0x13), 'SH', 'M5_SYNTHETIC'),
    ])
    return bytes(128) + b'DICM' + element((2, 0), 'UL', struct.pack('<I', len(meta))) + meta + body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=False)
    output = args.output_dir / 'm5-sr-temporal-precision.dcm'
    payload = make_file()
    output.write_bytes(payload)
    manifest = {'file': str(output.resolve()), 'sha256_before_display': hashlib.sha256(payload).hexdigest(),
                'sop_instance_uid': '2.25.550001', 'rows': [dict(label=l, vr=v, raw=r, expected=e) for l,v,r,e in SAMPLES],
                'scope': 'Synthetic read/display/copy fixture; two malformed controls are intentionally retained'}
    (args.output_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(str(output.resolve()))
    print(manifest['sha256_before_display'])


if __name__ == '__main__':
    main()
