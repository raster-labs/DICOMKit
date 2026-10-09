#!/usr/bin/env python3
"""Generate the Basic Application Level Confidentiality Profile rules of DICOMKit from the
frozen DICOM DocBook: every row of PS3.15 Table E.1-1.

Usage:
    python3 Scripts/nema_docbook.py fetch 2026a 15 --out DIR
    python3 Scripts/nema_docbook.py fetch 2026a 16 --out DIR
    python3 Scripts/generate_confidentiality_profile.py --nema DIR [--check]

Also writes Sources/DICOMKit/Anonymization/ConfidentialityProfileSafePrivate.swift: every row
of PS3.15 Table E.3.10-1 (Safe Private Attributes: Private Creator, group, element within the
block, VR), which the Retain Safe Private Option keeps (E.3.10; D159), and
Sources/DICOMKit/Anonymization/ConfidentialityProfileStructuredContent.swift: every row of
PS3.15 Table E.3.4-1 (Content Item Concept Name Codes: Basic Profile action and option
columns by concept name and Value Type), which the Clean Structured Content Option applies to
Content Items (E.3.4; D159). An SCT row is also written under the SNOMED ID that PS3.16
Table O-1 maps it to, with the designators SRT, SNM3 and 99SDM, because E.3.4 expects the
retired "SNOMED-RT style" codes to be recognised (needs part16_<edition>.xml in --nema).

Writes Sources/DICOMKit/Anonymization/ConfidentialityProfileTableE11.swift: one entry per
row with a single tag — its Basic Profile action and the action of every option column
(Retain UIDs, Device Identity, Institution Identity, Patient Characteristics, Longitudinal
Full / Modified Dates, Clean Descriptors, Clean Structured Content, Clean Graphics) — plus
the four pattern rows (curve data, overlay data and comments, private groups), which the
engine applies by group. With --check it compares the existing file instead and exits 1 on
any difference, so the table can be verified without being rewritten.

This is the "data too large to maintain by hand" step of the verification method in
DICOMCORE_STANDARD_IMPLEMENTATION.md (D69, DICOMKIT_STANDARD_IMPLEMENTATION.md).
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import nema_docbook as nd  # noqa: E402

OUT = os.path.join(ROOT, 'Sources', 'DICOMKit', 'Anonymization', 'ConfidentialityProfileTableE11.swift')
# Table E.1-1 option columns, in table order, and the field each fills.
OPTION_FIELDS = [
    ('Rtn. Safe Priv. Opt.', None),            # only the private pattern row: applied by the engine from Table E.3.10-1
    ('Rtn. UIDs Opt.', 'uids'),
    ('Rtn. Dev. Id. Opt.', 'device'),
    ('Rtn. Inst. Id. Opt.', 'institution'),
    ('Rtn. Pat. Chars. Opt.', 'patient'),
    ('Rtn. Long. Full Dates Opt.', 'fullDates'),
    ('Rtn. Long. Modif. Dates Opt.', 'modifiedDates'),
    ('Clean Desc. Opt.', 'cleanDescriptors'),
    ('Clean Struct. Cont. Opt.', 'cleanStructuredContent'),
    ('Clean Graph. Opt.', 'cleanGraphics'),
]
OUT_SAFE = os.path.join(ROOT, 'Sources', 'DICOMKit', 'Anonymization', 'ConfidentialityProfileSafePrivate.swift')
OUT_SC = os.path.join(ROOT, 'Sources', 'DICOMKit', 'Anonymization', 'ConfidentialityProfileStructuredContent.swift')
# Table E.3.4-1 option columns, in table order (after Basic Prof.), and the field each fills.
SC_FIELDS = [
    ('Rtn. UIDs Opt.', 'uids'),
    ('Rtn. Dev. Id. Opt.', 'device'),
    ('Rtn. Inst. Id. Opt.', 'institution'),
    ('Rtn. Pat. Chars. Opt.', 'patient'),
    ('Rtn. Long. Full Dates Opt.', 'fullDates'),
    ('Rtn. Long. Modif. Dates Opt.', 'modifiedDates'),
    ('Clean Desc. Opt.', 'cleanDescriptors'),
]
# E.3.4: retired "SNOMED-RT style" designators to recognise for an SCT concept.
RETIRED_SNOMED_DESIGNATORS = ['SRT', 'SNM3', '99SDM']
PATTERNS = {'(50xx,xxxx)', '(60xx,4000)', '(60xx,3000)', '(gggg,eeee) where gggg is odd'}


def rows(p15):
    table = p15.table('E.1-1')
    header = list(p15.rows(table, header=True))[0]
    expected = ['Attribute Name', 'Tag', None, None, 'Basic Prof.'] + [c for c, _ in OPTION_FIELDS]
    for i, name in enumerate(expected):
        if name is not None and header[i] != name:
            sys.exit(f'Table E.1-1 column {i} is {header[i]!r}, expected {name!r}; re-read the table')
    out, patterns = [], []
    for row in p15.rows(table):
        if len(row) < 15:
            continue
        tag = row[1].strip()
        if tag in PATTERNS:
            patterns.append((tag, row[0], row[4].replace(' ', '')))
            continue
        m = re.fullmatch(r'\(([0-9A-Fa-f]{4}),([0-9A-Fa-f]{4})\)', tag)
        if not m:
            sys.exit(f'Table E.1-1 row {row[0]!r}: tag {tag!r} is neither a tag nor a known pattern')
        options = {field: row[5 + i].strip() for i, (_, field) in enumerate(OPTION_FIELDS)
                   if field and row[5 + i].strip()}
        out.append(((m.group(1) + m.group(2)).upper(), row[0], row[4].replace(' ', ''), options))
    return out, patterns


def swift(rows_, patterns, subtitle):
    lines = [
        '// ConfidentialityProfileTableE11.swift',
        '// DICOMKit',
        '//',
        f'// GENERATED by Scripts/generate_confidentiality_profile.py from {subtitle},',
        f'// Table E.1-1 ({len(rows_)} single-tag rows; the {len(patterns)} pattern rows are applied by group',
        '// in ConfidentialityEngine). Do not hand-edit: fix the generator and regenerate.',
        '//',
        f'// NEMA-verified: 2026a, checked 2026-09-30 — every single-tag row of PS3.15 2026a Table E.1-1 '
        f'({len(rows_)}), with its Basic Profile action and all option columns, generated from the DocBook '
        '(D69); `generate_confidentiality_profile.py --check` re-verifies it.',
        '',
        'extension ConfidentialityProfile {',
        '    /// One row of PS3.15 Table E.1-1: the Basic Profile action and, per option, the',
        '    /// action the option substitutes ("K" keep, "C" clean), as the table writes them.',
        '    struct E11Row: Sendable, Equatable {',
        '        let basic: String',
        '        var uids: String? = nil',
        '        var device: String? = nil',
        '        var institution: String? = nil',
        '        var patient: String? = nil',
        '        var fullDates: String? = nil',
        '        var modifiedDates: String? = nil',
        '        var cleanDescriptors: String? = nil',
        '        var cleanStructuredContent: String? = nil',
        '        var cleanGraphics: String? = nil',
        '    }',
        '',
        '    /// Table E.1-1, keyed by (group << 16 | element).',
        '    static let tableE11: [UInt32: E11Row] = [',
    ]
    for tag, name, basic, options in sorted(rows_):
        args = [f'basic: "{basic}"'] + [f'{f}: "{v}"' for f in
                                          ('uids', 'device', 'institution', 'patient', 'fullDates', 'modifiedDates',
                                           'cleanDescriptors', 'cleanStructuredContent', 'cleanGraphics')
                                          if (v := options.get(f))]
        lines.append(f'        0x{tag}: E11Row({", ".join(args)}),  // {name}')
    lines += ['    ]', '}', '']
    return '\n'.join(lines)


def safe_private_rows(p15):
    """Table E.3.10-1: (creator, group, element-in-block, VR, meaning)."""
    table = p15.table('E.3.10-1')
    header = list(p15.rows(table, header=True))[0]
    if header[:4] != ['Data Element', 'Private Creator', 'VR', 'VM']:
        sys.exit(f'Table E.3.10-1 header is {header!r}; re-read the table')
    out = []
    for row in p15.rows(table):
        m = re.fullmatch(r'\(([0-9A-Fa-f]{4}),xx([0-9A-Fa-f]{2})\)', row[0].strip())
        if not m:
            sys.exit(f'Table E.3.10-1 row {row!r}: data element is not (gggg,xxee)')
        out.append((row[1].strip(), m.group(1).upper(), m.group(2).upper(), row[2].strip(), row[4].strip()))
    return out


def safe_private_swift(rows_, subtitle):
    lines = [
        '// ConfidentialityProfileSafePrivate.swift',
        '// DICOMKit',
        '//',
        f'// GENERATED by Scripts/generate_confidentiality_profile.py from {subtitle},',
        f'// Table E.3.10-1 ({len(rows_)} rows). Do not hand-edit: fix the generator and regenerate.',
        '//',
        f'// NEMA-verified: 2026a, checked 2026-10-01 — every row of PS3.15 2026a Table E.3.10-1 Safe Private '
        f'Attributes ({len(rows_)}: Private Creator, group, element within the block, VR), generated from the '
        'DocBook (D159); `generate_confidentiality_profile.py --check` re-verifies it.',
        '',
        'extension ConfidentialityProfile {',
        '    /// PS3.15 2026a Table E.3.10-1 Safe Private Attributes, keyed',
        '    /// "<Private Creator>|<group hex>|<element within the block, 2 hex digits>" (upper-case hex),',
        '    /// with the VR the table lists. The Retain Safe Private Option keeps these (E.3.10).',
        '    static let safePrivateAttributes: [String: String] = [',
    ]
    seen = set()
    for creator, group, element, vr, meaning in sorted(rows_):
        key = f'{creator}|{group}|{element}'
        if key in seen:
            continue
        seen.add(key)
        esc = creator.replace('\\', '\\\\').replace('"', '\\"')
        note = meaning.replace('\n', ' ')[:80]
        lines.append(f'        "{esc}|{group}|{element}": "{vr}",  // {note}')
    lines += ['    ]', '}', '']
    return '\n'.join(lines)


def structured_content_rows(p15):
    """Table E.3.4-1: (designator, code value, value type, meaning, basic, {field: code})."""
    table = p15.table('E.3.4-1')
    header = list(p15.rows(table, header=True))[0]
    expected = ['Code Meaning', 'Code Value', 'Coding Scheme Designator', 'Value Type', None, None,
                'Basic Prof.'] + [c for c, _ in SC_FIELDS]
    if len(header) != len(expected) or any(e is not None and header[i] != e for i, e in enumerate(expected)):
        sys.exit(f'Table E.3.4-1 header is {header!r}; re-read the table')
    out = []
    for row in p15.rows(table):
        # "NCDR [2.0b]": Coding Scheme Designator NCDR, Coding Scheme Version 2.0b (PS3.16 Table 8-1).
        designator = re.sub(r'\s*\[.*\]$', '', row[2].strip())
        options = {field: row[7 + i].strip() for i, (_, field) in enumerate(SC_FIELDS) if row[7 + i].strip()}
        out.append((designator, row[1].strip(), row[3].strip(), row[0].strip(), row[6].replace(' ', ''), options))
    return out


def snomed_ids(p16):
    """PS3.16 Table O-1: SNOMED Concept ID (SCT) -> SNOMED ID (SRT)."""
    return {r[0].strip(): r[1].strip() for r in p16.rows(p16.table('O-1')) if len(r) >= 2 and r[1].strip()}


def structured_content_swift(rows_, srt, subtitle, subtitle16):
    entries, aliases = {}, 0
    for designator, value, vt, meaning, basic, options in rows_:
        keys = [(f'{designator}|{value}|{vt}', meaning)]
        if designator == 'SCT':
            if value not in srt:
                sys.exit(f'Table E.3.4-1 SCT {value} ({meaning}) has no SNOMED ID in PS3.16 Table O-1')
            keys += [(f'{d}|{srt[value]}|{vt}', f'{meaning} (retired {d} {srt[value]} = SCT {value})')
                     for d in RETIRED_SNOMED_DESIGNATORS]
        args = [f'basic: "{basic}"'] + [f'{f}: "{v}"' for _, f in SC_FIELDS if (v := options.get(f))]
        for i, (key, note) in enumerate(keys):
            line = f'E341Row(meaning: "{meaning}", {", ".join(args)})'
            if key in entries and entries[key][0] != line:
                sys.exit(f'Table E.3.4-1 lists {key} twice with different actions')
            entries[key] = (line, note)
            aliases += i > 0
    lines = [
        '// ConfidentialityProfileStructuredContent.swift',
        '// DICOMKit',
        '//',
        f'// GENERATED by Scripts/generate_confidentiality_profile.py from {subtitle},',
        f'// Table E.3.4-1 ({len(rows_)} rows), and {subtitle16} Table O-1 (the SNOMED IDs of its SCT',
        f'// rows: {aliases} retired-code keys). Do not hand-edit: fix the generator and regenerate.',
        '//',
        f'// NEMA-verified: 2026a, checked 2026-10-01 — every row of PS3.15 2026a Table E.3.4-1 Clean Structured '
        f'Content Option Content Item Concept Name Codes ({len(rows_)}: concept name, Value Type, Basic Profile '
        'action and the 7 option columns), generated from the DocBook, plus the retired SRT / SNM3 / 99SDM codes '
        'of its SCT rows from PS3.16 2026a Table O-1 (E.3.4) (D159); `generate_confidentiality_profile.py --check` '
        're-verifies it.',
        '',
        'extension ConfidentialityProfile {',
        '    /// One row of PS3.15 Table E.3.4-1: the Basic Profile action for a Content Item with this',
        '    /// Concept Name and Value Type and, per option, the action the option substitutes',
        '    /// ("K" keep, "C" clean), as the table writes them.',
        '    struct E341Row: Sendable, Equatable {',
        '        let meaning: String',
        '        let basic: String',
        '        var uids: String? = nil',
        '        var device: String? = nil',
        '        var institution: String? = nil',
        '        var patient: String? = nil',
        '        var fullDates: String? = nil',
        '        var modifiedDates: String? = nil',
        '        var cleanDescriptors: String? = nil',
        '    }',
        '',
        '    /// Table E.3.4-1, keyed "<Coding Scheme Designator>|<Code Value>|<Value Type>".',
        '    static let structuredContentRows: [String: E341Row] = [',
    ]
    for key in sorted(entries):
        line, note = entries[key]
        lines.append(f'        "{key}": {line},  // {note}')
    lines += ['    ]', '}', '']
    return '\n'.join(lines), len(entries)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True)
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--check', action='store_true', help='compare with the existing file; exit 1 on a difference')
    args = ap.parse_args()
    path = os.path.join(args.nema, f'part15_{args.edition}.xml')
    p15 = nd.Part(path)
    if args.edition not in p15.subtitle:
        sys.exit(f'{path}: subtitle {p15.subtitle!r} does not name {args.edition}')
    rows_, patterns = rows(p15)
    if len(patterns) != len(PATTERNS):
        sys.exit(f'expected the {len(PATTERNS)} pattern rows, found {[p[0] for p in patterns]}')
    text = swift(rows_, patterns, p15.subtitle)
    safe = safe_private_rows(p15)
    safe_text = safe_private_swift(safe, p15.subtitle)
    p16 = nd.Part(os.path.join(args.nema, f'part16_{args.edition}.xml'))
    if args.edition not in p16.subtitle:
        sys.exit(f'part16: subtitle {p16.subtitle!r} does not name {args.edition}')
    sc = structured_content_rows(p15)
    sc_text, sc_keys = structured_content_swift(sc, snomed_ids(p16), p15.subtitle, p16.subtitle)
    if args.check:
        current = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
        if current != text:
            print(f'{OUT} differs from PS3.15 {args.edition} Table E.1-1; regenerate')
            sys.exit(1)
        current = open(OUT_SAFE, encoding='utf-8').read() if os.path.exists(OUT_SAFE) else ''
        if current != safe_text:
            print(f'{OUT_SAFE} differs from PS3.15 {args.edition} Table E.3.10-1; regenerate')
            sys.exit(1)
        current = open(OUT_SC, encoding='utf-8').read() if os.path.exists(OUT_SC) else ''
        if current != sc_text:
            print(f'{OUT_SC} differs from PS3.15 {args.edition} Table E.3.4-1; regenerate')
            sys.exit(1)
        print(f'ok: {len(rows_)} rows and {len(patterns)} patterns of Table E.1-1 match {os.path.relpath(OUT, ROOT)}')
        print(f'ok: {len(safe)} rows of Table E.3.10-1 match {os.path.relpath(OUT_SAFE, ROOT)}')
        print(f'ok: {len(sc)} rows of Table E.3.4-1 ({sc_keys} keys) match {os.path.relpath(OUT_SC, ROOT)}')
        return
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(text)
    with open(OUT_SAFE, 'w', encoding='utf-8') as f:
        f.write(safe_text)
    print(f'wrote {os.path.relpath(OUT, ROOT)}: {len(rows_)} rows; patterns {", ".join(p[0] for p in patterns)}')
    print(f'wrote {os.path.relpath(OUT_SAFE, ROOT)}: {len(safe)} rows of Table E.3.10-1')
    with open(OUT_SC, 'w', encoding='utf-8') as f:
        f.write(sc_text)
    print(f'wrote {os.path.relpath(OUT_SC, ROOT)}: {len(sc)} rows of Table E.3.4-1, {sc_keys} keys')


if __name__ == '__main__':
    main()
