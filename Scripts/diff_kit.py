#!/usr/bin/env python3
"""Diff the standard-derived constants of Sources/DICOMKit against the frozen DICOM DocBook.

Usage:
    for p in 3 4 5 6 10 15 16; do python3 Scripts/nema_docbook.py fetch 2026a $p --out DIR; done
    python3 Scripts/diff_kit.py --nema DIR [--sources Sources/DICOMKit] [--verbose] [--only NAME]

Every check extracts the literals from the Swift files by regex (never by hand) and compares
them with the table or clause of the standard named in the check. It prints one line per
check with the counts (matched / wrong / missing / extra) and exits 1 when any check found a
wrong value or a missing required value. "Extra" values that the standard does not define,
and standard values the module does not carry, are listed but do not fail the run unless the
check says they must. Values whose fix changes public API and waits for the owner's approval
are reported as PEND.

This is the extraction + diff step of the verification method in
DICOMCORE_STANDARD_IMPLEMENTATION.md, applied to DICOMKit (see
DICOMKIT_STANDARD_IMPLEMENTATION.md for the results).
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


nd = load('nema_docbook')
dw = load('diff_web')          # Report, read_all, dictionary, uid_registry, section helpers, enum helpers
D, X = nd.D, nd.X

# Values known to differ from the standard whose fix changes public API and waits for the
# owner's approval; reported as PEND, not FAIL. Remove when fixed. Each entry is a substring
# of the finding text it silences (see DICOMKIT_STANDARD_IMPLEMENTATION.md, P-CONST, P-HP,
# P-RT, P-SEG, P-SC, P-AI, P-TITLE).
PENDING_API_APPROVAL = {
    # Every DICOMKit P-item was approved and implemented on 2026-09-29; the DICOMCore row
    # D26 (SRDocumentType.colonCADSR) was closed on 2026-09-29. Nothing is pending.
}

# Private coding schemes (PS3.16 2026a section 8: designators beginning with "99") are
# by definition absent from the NEMA text; their concepts are reported as informational.
PRIVATE_SCHEME_PREFIX = '99'


# --- DocBook helpers ---------------------------------------------------------------------

def table_by_label(part, label):
    for lab, cap, t in part.tables():
        if lab == label:
            return t
    return None


def table_labels(part):
    return {lab for lab, _, _ in part.tables()}


def cell_terms(part, td):
    """The variablelist terms of a table cell (Enumerated Values / Defined Terms lists).

    Some cells list the terms inline ("Enumerated Values: RECTANGULAR CIRCULAR POLYGONAL This
    multi-valued ..."); those are read from the text up to the next sentence."""
    kind = ''
    inline = []
    for p in td.iter(D + 'para'):
        txt = nd.norm(''.join(p.itertext()))
        m = re.match(r'(Enumerated Values|Defined Terms)(?: for [^:]+)?:\s*(.*)', txt)
        if m:
            kind = kind or m.group(1)
            rest = m.group(2)
            if rest and not p.findall(D + 'variablelist'):
                inline = [w for w in re.split(r'\s+', rest) if re.fullmatch(r'[A-Z][A-Z0-9_]*', w)]
    terms = []
    for vl in td.iter(D + 'variablelist'):
        for e in vl.findall(D + 'varlistentry'):
            term = e.find(D + 'term')
            if term is not None:
                terms.append(nd.norm(''.join(term.itertext())))
    return kind, terms or inline


def attribute_terms(part, attr_name, table_label=None):
    """Terms listed for an attribute row of a module table: (table labels, kind, terms).

    Without a table label the terms are the union over every module table that lists the
    attribute, including the terms of a section a row refers to ("See C.7.6.3.1.2"), since
    the same attribute is restricted differently by different IODs."""
    want = attr_name.lower()
    labels, kinds, terms = [], set(), []
    for lab, cap, t in part.tables():
        if table_label and lab != table_label:
            continue
        for body in t.iter(D + 'tbody'):
            for tr in body.findall(D + 'tr'):
                tds = [c for c in tr if c.tag in (D + 'td', D + 'th')]
                if len(tds) < 4:
                    continue
                name = nd.norm(''.join(tds[0].itertext())).lstrip('>').strip().lower()
                if name != want:
                    continue
                kind, cell = cell_terms(part, tds[-1])
                if not cell:
                    # "See C.x.y" carries the terms only when the cell itself lists none;
                    # otherwise the xref is an explanation (and may list another attribute).
                    for xref in tds[-1].iter(D + 'xref'):
                        cell += dw.variablelist_terms(part, xref.get('linkend'))
                if cell:
                    labels.append(lab)
                    kinds.add(kind)
                    terms += [c for c in cell if c not in terms]
                    if table_label:
                        return lab, kind, terms
    kind = 'Enumerated Values' if kinds == {'Enumerated Values'} else ('Defined Terms' if 'Defined Terms' in kinds else '')
    return ', '.join(labels[:4]) + (' …' if len(labels) > 4 else ''), kind, terms


DEPRECATED_CASE = re.compile(r'^[ \t]*@available\(\*,\s*deprecated[^\n]*\n[ \t]*(?:public\s+)?case\s+\w+\s*=\s*"[^"]*"', re.M)


def active_string_cases(src, enum_name):
    """Raw values of the enum's cases that are not marked deprecated (deprecated cases are
    kept for source compatibility and are never written by the serializers)."""
    body = DEPRECATED_CASE.sub('', dw.enum_body(src, enum_name))
    return re.findall(r'case\s+\w+\s*=\s*"([^"]*)"', body)


def section_terms(part, xml_id):
    return dw.variablelist_terms(part, xml_id)


def dcm_codes(p16):
    """PS3.16 Table D-1: {code value: code meaning}."""
    return {row[0]: row[1] for row in dw.table_rows(p16, 'D-1') if len(row) >= 2}


def cid_index(p16):
    """Every (scheme, code) of every CID table: {(scheme, value): [(meaning, CID), ...]}.

    A code can carry different meanings in different context groups (e.g. (50960005, SCT) is
    "Bleeding" in CID 3754 and "Hemorrhage" in CID 6338); any of them is acceptable."""
    out = {}
    for lab, cap, t in p16.tables():
        if not lab.startswith('CID '):
            continue
        for row in p16.rows(t):
            if len(row) >= 3 and row[0] and row[1] and not row[0].startswith('Include'):
                out.setdefault((row[0], row[1]), []).append((row[2], lab))
    return out


def cid_meanings(cids, scheme, value):
    return [m.lower() for m, _ in cids.get((scheme, value), [])]


def cid_rows(p16, label, seen=None):
    """The (scheme, value, meaning) rows of a CID, with `Include CID n` rows expanded."""
    seen = seen if seen is not None else set()
    if label in seen:
        return []
    seen.add(label)
    out = []
    for row in dw.table_rows(p16, label):
        if row and row[0].startswith('Include CID'):
            out += cid_rows(p16, row[0].replace('Include ', '').strip(), seen)
        elif len(row) >= 3:
            out.append((row[0], row[1], row[2]))
    return out


def srt_to_sct(p16):
    """PS3.16 Table O-1: {SNOMED-RT id: (SCT concept id, fully specified name)}."""
    return {row[1]: (row[0], row[2]) for row in dw.table_rows(p16, 'O-1') if len(row) >= 3}


# --- Swift helpers ------------------------------------------------------------------------

TAG_CONST = re.compile(r'static\s+let\s+(\w+)\s*=\s*Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)')
TAG_LITERAL = re.compile(r'Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)')


def tag_constants(core_dir, files):
    """keyword -> GGGGEEEE from DICOMCore's Tag+*.swift and any DICOMKit-local constants."""
    out = {}
    for name in sorted(os.listdir(core_dir)):
        if name.startswith('Tag') and name.endswith('.swift'):
            for kw, g, e in TAG_CONST.findall(dw.read(os.path.join(core_dir, name))):
                out.setdefault(kw, (g + e).upper())
    local = {}
    for fname, src in files.items():
        for kw, g, e in TAG_CONST.findall(src):
            local[kw] = ((g + e).upper(), fname)
            out.setdefault(kw, (g + e).upper())
    return out, local


def line_of(src, pos):
    return src.count('\n', 0, pos) + 1


def vr_options(vr_text):
    """'US or SS' -> {'US','SS'}; 'OB or OW' -> {'OB','OW'}; 'See Note' -> set()."""
    return set(re.findall(r'\b([A-Z]{2})\b', vr_text))


# --- checks --------------------------------------------------------------------------------

def check_coded_concepts(rep, p16, files):
    dcm = dcm_codes(p16)
    cids = cid_index(p16)
    srt = srt_to_sct(p16)
    pat = re.compile(r'codeValue:\s*"([^"]+)"\s*,\s*codingSchemeDesignator:\s*"([^"]+)"\s*,\s*codeMeaning:\s*"([^"]*)"', re.S)
    matched, wrong, extra, legacy, private = 0, [], [], [], []
    seen = set()
    for fname, src in files.items():
        for m in pat.finditer(src):
            value, scheme, meaning = m.group(1).strip(), m.group(2), m.group(3).strip()
            key = (fname, value, scheme, meaning)
            if key in seen:
                continue
            seen.add(key)
            where = f'{fname}:{line_of(src, m.start())}'
            if scheme == 'DCM':
                if value not in dcm:
                    wrong.append(f'{where}: ({value}, DCM, "{meaning}") is not in PS3.16 Table D-1')
                elif meaning.lower() != dcm[value].lower() and meaning.lower() not in cid_meanings(cids, 'DCM', value):
                    wrong.append(f'{where}: ({value}, DCM, "{meaning}"): Table D-1 meaning is "{dcm[value]}"')
                else:
                    matched += 1
            elif scheme == 'SRT':
                sct = srt.get(value)
                if sct is None:
                    legacy.append(f'{where}: ({value}, SRT, "{meaning}"): SRT id not in PS3.16 Table O-1; 2026a uses SCT concept ids')
                else:
                    hits = cids.get(('SCT', sct[0]), [])
                    std = hits[0][0] if hits else sct[1]
                    legacy.append(f'{where}: ({value}, SRT, "{meaning}") -> (SCT, {sct[0]}, "{std}") per Table O-1' + ('' if hits else ' (FSN; not in a CID)'))
            elif scheme.startswith(PRIVATE_SCHEME_PREFIX):
                private.append(f'{where}: ({value}, {scheme}, "{meaning}") private scheme (PS3.16 section 8)')
            else:
                hits = cids.get((scheme, value))
                if not hits:
                    extra.append(f'{where}: ({value}, {scheme}, "{meaning}") appears in no CID table'
                                 + (' (external terminology; not verifiable from NEMA text)' if scheme == 'SCT' else ''))
                elif meaning.lower() not in cid_meanings(cids, scheme, value):
                    wrong.append(f'{where}: ({value}, {scheme}, "{meaning}"): {hits[0][1]} meaning is "{hits[0][0]}"')
                else:
                    matched += 1
    wrong, pending = split_pending(wrong)
    rep.check('PS3.16 Table D-1 / CID tables: coded concept literals (value, scheme, meaning)', matched, wrong, extra=extra + private, pending=pending)
    legacy, pending = split_pending(legacy)
    rep.check('PS3.16 Table 8-1 / O-1: SRT-style SNOMED codes (2026a templates use SCT concept ids)', 0, legacy, pending=pending)


def split_pending(items):
    """Items whose fix waits for the owner's approval are reported as PEND, not FAIL."""
    wrong, pending = [], []
    for item in items:
        (pending if any(p in item for p in PENDING_API_APPROVAL) else wrong).append(item)
    return wrong, pending


def check_vr_literals(rep, p6, files, tags):
    dic = dw.dictionary(p6)
    matched, wrong, unknown = 0, [], []
    pat = re.compile(r'(?:tag|for):\s*\.(\w+)\s*,\s*vr:\s*\.([A-Z]{2})\b')
    for fname, src in files.items():
        for m in pat.finditer(src):
            kw, vr = m.group(1), m.group(2)
            tag = tags.get(kw)
            if tag is None:
                unknown.append(f'{fname}:{line_of(src, m.start())}: .{kw} (no Tag constant found)')
                continue
            entry = dic.get(tag)
            if entry is None:
                unknown.append(f'{fname}:{line_of(src, m.start())}: .{kw} ({tag}) not in PS3.6 Table 6-1')
                continue
            allowed = vr_options(entry[2])
            if not allowed or vr in allowed or (vr == 'OW' and 'OB' in allowed) or (vr == 'OB' and 'OW' in allowed):
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: .{kw} ({tag[:4]},{tag[4:]}) written as {vr}; PS3.6 VR is {entry[2]}')
        for m in TAG_LITERAL.finditer(src):
            tail = src[m.end():m.end() + 80]
            v = re.search(r'vr:\s*\.([A-Z]{2})\b', tail)
            if not v:
                continue
            tag = (m.group(1) + m.group(2)).upper()
            entry = dic.get(tag)
            if entry is None:
                continue
            allowed = vr_options(entry[2])
            vr = v.group(1)
            if not allowed or vr in allowed or (vr == 'OW' and 'OB' in allowed) or (vr == 'OB' and 'OW' in allowed):
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: ({tag[:4]},{tag[4:]}) {entry[1]} written as {vr}; PS3.6 VR is {entry[2]}')
    wrong, pending = split_pending(wrong)
    rep.check('PS3.6 Table 6-1: VR of every element written with an explicit vr:', matched, wrong, extra=unknown, pending=pending)


def check_typed_reads(rep, p6, files, tags):
    dic = dw.dictionary(p6)
    expect = {'uint16': {'US', 'SS', 'OW'}, 'uint32': {'UL', 'SL', 'OL'}, 'int16': {'SS', 'US'}, 'int32': {'SL', 'UL'},
              'decimalString': {'DS'}, 'integerString': {'IS'}, 'float': {'FL'}, 'double': {'FD'}}
    matched, wrong = 0, []
    pat = re.compile(r'\.(uint16|uint32|int16|int32|decimalString|integerString|float|double)\((?:for|tag):\s*\.(\w+)')
    for fname, src in files.items():
        for m in pat.finditer(src):
            fn, kw = m.group(1), m.group(2)
            tag = tags.get(kw)
            entry = dic.get(tag) if tag else None
            if entry is None:
                continue
            allowed = vr_options(entry[2])
            if not allowed or allowed & expect[fn]:
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: .{fn}(.{kw}) but ({tag[:4]},{tag[4:]}) {entry[1]} is {entry[2]}')
    rep.check('PS3.6 Table 6-1: typed reads (uint16/uint32/decimalString/...) match the element VR', matched, wrong)


def check_tag_names(rep, p6, files, local_tags, p7=None):
    # PS3.6 Table 6-1 (data elements) plus Table 7-1 (File Meta), Table 8-1 (Directory Structuring)
    # and, when part 7 is available, PS3.7 Table E.1-1 (command elements, group 0000).
    dic = dw.dictionary(p6)
    extra = [(p6, '7-1'), (p6, '8-1')] + ([(p7, 'E.1-1')] if p7 is not None else [])
    for part, label in extra:
        for row in dw.table_rows(part, label):
            if len(row) >= 4 and re.fullmatch(r'\([0-9A-Fa-fx]{4},[0-9A-Fa-fx]{4}\)', row[0].strip()):
                dic.setdefault(row[0].strip('()').replace(',', '').upper(), (row[1], row[2], row[3], row[4] if len(row) > 4 else '', ''))
    matched, wrong = 0, []

    def norm(s):
        return re.sub(r'[^a-z0-9]', '', s.lower().replace("'s", 's'))

    for fname, src in files.items():
        for m in TAG_LITERAL.finditer(src):
            tag = (m.group(1) + m.group(2)).upper()
            entry = dic.get(tag)
            if entry is None:
                if m.group(1).upper()[-1] in '13579BDF':      # private group
                    continue
                if re.match(r'(?i)^(0002|FFFE|60[0-9A-F]{2}|50[0-9A-F]{2})', tag) is None:
                    wrong.append(f'{fname}:{line_of(src, m.start())}: ({tag[:4]},{tag[4:]}) is not in PS3.6 Tables 6-1 / 7-1 / 8-1 or PS3.7 Table E.1-1')
                continue
            line_end = src.find('\n', m.end())
            rest = src[m.end():line_end if line_end > 0 else m.end() + 120]
            c = re.search(r'//\s*(?:\(\w+,\w+\)\s*)?([A-Za-z][A-Za-z0-9\' ()/,-]+)', rest)
            if not c:
                continue
            doc = c.group(1).strip()
            names = [norm(d) for d in re.split(r',|/', doc)] + [norm(doc)]
            if any(n == norm(entry[0]) or n == norm(entry[1]) or (n and n in norm(entry[0])) or norm(entry[0]) in n for n in names):
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: ({tag[:4]},{tag[4:]}) commented "{doc}"; PS3.6 name is "{entry[0]}"')
    for kw, (tag, fname) in local_tags.items():
        entry = dic.get(tag)
        if entry is None:
            continue
        std_kw = entry[1][0].lower() + entry[1][1:] if entry[1] else ''
        if norm(kw) == norm(std_kw) or norm(kw) in norm(entry[0]) or norm(entry[0]).startswith(norm(kw)[:8]):
            matched += 1
        else:
            wrong.append(f'{fname}: static let {kw} = ({tag[:4]},{tag[4:]}); PS3.6 keyword is {entry[1]}')
    rep.check('PS3.6 Table 6-1: names and keywords written next to Tag(group:element:) literals', matched, wrong)


def check_citations(rep, parts, files):
    ids = {n: dw.section_ids(p) for n, p in parts.items()}
    labels = {n: table_labels(p) for n, p in parts.items()}
    matched, wrong = 0, []
    sect_pat = re.compile(r'PS3\.(\d+)[ ,]*(?:Section|§|Annex|Sect\.)?\s*([A-Z]?\d[\dA-Za-z.]*?)(?=[\s,;:)\]\-–—]|$)(?:\s*[-–—:]\s*([A-Z][^\n*"`]{3,60}))?')
    tab_pat = re.compile(r'PS3\.(\d+)[ ,]*Table\s+([A-Z]?[\d.]+-\d+[a-z]?)')
    tid_pat = re.compile(r'\b(TID|CID)\s+(\d{2,5})\b')
    stop = {'module', 'the', 'and', 'of', 'a', 'macro', 'sequence', 'attribute', 'attributes', 'image', 'sop', 'class',
            'storage', 'iod', 'information', 'object', 'definition', 'definitions', 'for', 'in', 'section', 'general'}
    for fname, src in files.items():
        for m in sect_pat.finditer(src):
            part, sect, desc = int(m.group(1)), m.group(2).rstrip('.'), (m.group(3) or '').strip()
            if part not in parts or re.fullmatch(r'20\d\d[a-e]', sect):     # "PS3.5 2026a" is an edition
                continue
            sid = f'sect_{sect}' if '.' in sect else f'chapter_{sect}'
            if sid not in ids[part] and f'chapter_{sect}' not in ids[part]:
                wrong.append(f'{fname}:{line_of(src, m.start())}: "PS3.{part} {sect}" does not exist in the 2026a text')
                continue
            title = dw.section_title(parts[part], sid) or dw.section_title(parts[part], f'chapter_{sect}') or ''
            if desc:
                dw_words = {w for w in re.findall(r'[a-z0-9]+', desc.lower()) if w not in stop}
                tw = {w for w in re.findall(r'[a-z0-9]+', title.lower()) if w not in stop}
                if dw_words and tw and not (dw_words & tw):
                    wrong.append(f'{fname}:{line_of(src, m.start())}: "PS3.{part} {sect} - {desc[:40]}": 2026a §{sect} is "{title}"')
                    continue
            matched += 1
        for m in tab_pat.finditer(src):
            part, lab = int(m.group(1)), m.group(2)
            if part not in parts:
                continue
            if lab in labels[part]:
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: "PS3.{part} Table {lab}" does not exist in the 2026a text')
        for m in tid_pat.finditer(src):
            lab = f'{m.group(1)} {m.group(2)}'
            if lab in labels[16] or f'sect_{m.group(1)}_{m.group(2)}' in ids[16]:
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: "{lab}" does not exist in PS3.16 2026a')
    rep.check('Section, table, TID and CID citations in doc comments exist in the 2026a text and name the right clause', matched, wrong)


SR_TABLE_FOR_CASE = re.compile(r'case\s+\.(\w+):\s*\n\s*//\s*PS3\.3\s+(A\.35\.\d+)[^\n]*\n\s*return\s+(\[[^\]]*\]|Set\([^)]*\))')
VT = {'text': 'TEXT', 'code': 'CODE', 'num': 'NUM', 'datetime': 'DATETIME', 'date': 'DATE', 'time': 'TIME', 'uidref': 'UIDREF',
      'pname': 'PNAME', 'composite': 'COMPOSITE', 'image': 'IMAGE', 'waveform': 'WAVEFORM', 'scoord': 'SCOORD',
      'scoord3D': 'SCOORD3D', 'tcoord': 'TCOORD', 'container': 'CONTAINER', 'table': 'TABLE'}


def check_sr_value_types(rep, p3, core_dir):
    src = dw.read(os.path.join(core_dir, 'StructuredReporting', 'SRDocumentType.swift'))
    matched, wrong = 0, []
    for case, sect, body in SR_TABLE_FOR_CASE.findall(src):
        if body.startswith('Set('):
            matched += 1
            continue
        code = {VT[v] for v in re.findall(r'\.(\w+)', body)}
        label = sect + '-2'
        rows = dw.table_rows(p3, label)
        std = {'CONTAINER'}
        for row in rows:
            if len(row) >= 3:
                std |= {re.sub(r'\s*\(.*?\)', '', t).strip() for t in row[2].split(',')}
        std.discard('')
        if code == std:
            matched += 1
        else:
            wrong.append(f'SRDocumentType.{case}: code {sorted(code - std)} not in Table {label}; table has {sorted(std - code)} the code lacks')
    wrong, pending = split_pending(wrong)
    rep.check('PS3.3 Tables A.35.x-2: SR IOD value-type sets (DICOMCore, relied on by the DICOMKit builders)', matched, wrong, pending=pending)


def check_enums(rep, parts, files):
    """Each string enum of the module against the terms the standard lists for its attribute."""
    p3, p5 = parts[3], parts[5]
    specs = [
        # (file, enum, part, attribute row name or section id, table label or None)
        ('SecondaryCapture/SecondaryCaptureImage.swift', 'ConversionType', p3, 'Conversion Type', 'C.8-24'),
        ('PresentationState/DisplayShutter.swift', 'ShutterShape', p3, 'Shutter Shape', 'C.7-17'),
        ('PresentationState/GraphicAnnotation.swift', 'PresentationGraphicType', p3, 'Graphic Type', 'C.10-5'),
        ('PresentationState/GraphicAnnotation.swift', 'AnnotationUnits', p3, 'Graphic Annotation Units', 'C.10-5'),
        ('PresentationState/SpatialTransformation.swift', 'PresentationSizeMode', p3, 'Presentation Size Mode', 'C.10-4'),
        # D39 (2026-09-29): Compound Graphic Sequence and the style macros.
        ('PresentationState/GraphicStyle.swift', 'CompoundGraphicType', p3, 'Compound Graphic Type', 'C.10-5'),
        ('PresentationState/GraphicStyle.swift', 'CompoundGraphicUnits', p3, 'Compound Graphic Units', 'C.10-5'),
        ('PresentationState/GraphicStyle.swift', 'TickAlignment', p3, 'Tick Alignment', 'C.10-5'),
        ('PresentationState/GraphicStyle.swift', 'TickLabelAlignment', p3, 'Tick Label Alignment', 'C.10-5'),
        ('PresentationState/GraphicStyle.swift', 'TextHorizontalAlignment', p3, 'Horizontal Alignment', 'C.10-5a'),
        ('PresentationState/GraphicStyle.swift', 'TextVerticalAlignment', p3, 'Vertical Alignment', 'C.10-5a'),
        ('PresentationState/GraphicStyle.swift', 'GraphicShadowStyle', p3, 'Shadow Style', 'C.10-5a'),
        ('PresentationState/GraphicStyle.swift', 'LineDashingStyle', p3, 'Line Dashing Style', 'C.10-5b'),
        ('PresentationState/GraphicStyle.swift', 'GraphicFillMode', p3, 'Fill Mode', 'C.10-5c'),
        ('PresentationState/ColorManagement.swift', 'func:extractColorSpace', p3, 'sect_C.11.15.1.2', None),
        ('Segmentation/Segmentation.swift', 'SegmentationType', p3, 'Segmentation Type', 'C.8.20-2'),   # C.8.20-5 HEIGHTMAP is the Height Map Segmentation IOD (A.91), not modelled
        ('Segmentation/Segmentation.swift', 'SegmentationFractionalType', p3, 'sect_C.8.20.2.3', None),
        ('Segmentation/Segmentation.swift', 'SegmentAlgorithmType', p3, 'Segment Algorithm Type', None),
        ('RadiationTherapy/RTStructureSet.swift', 'ContourGeometricType', p3, 'Contour Geometric Type', None),
        ('RadiationTherapy/RTStructureSet.swift', 'RTROIInterpretedType', p3, 'RT ROI Interpreted Type', None),
        ('Waveform/Waveform.swift', 'WaveformOriginality', p3, 'Waveform Originality', 'C.10-9'),
        ('HangingProtocol/DisplaySet.swift', 'ImageBoxLayoutType', p3, 'Image Box Layout Type', 'C.23.3-1'),   # C.11.17-1 is Structured Display, not modelled
        ('HangingProtocol/DisplaySet.swift', 'ScrollDirection', p3, 'Image Box Scroll Direction', None),
        ('HangingProtocol/DisplaySet.swift', 'ReformattingType', p3, 'Reformatting Operation Type', None),
        ('HangingProtocol/DisplaySet.swift', 'ThreeDRenderingType', p3, '3D Rendering Type', None),
        ('HangingProtocol/ImageSetDefinition.swift', 'SortByCategory', p3, 'Sort-by Category', None),
        ('HangingProtocol/ImageSetDefinition.swift', 'SortDirection', p3, 'Sorting Direction', None),
        ('HangingProtocol/ImageSetDefinition.swift', 'FilterOperator', p3, 'Filter-by Operator', None),
        ('HangingProtocol/ImageSetDefinition.swift', 'ImageSetSelectorCategory', p3, 'Image Set Selector Category', None),
        ('HangingProtocol/ImageSetDefinition.swift', 'RelativeTimeUnits', p3, 'Relative Time Units', None),
        ('HangingProtocol/HangingProtocol.swift', 'HangingProtocolLevel', p3, 'Hanging Protocol Level', None),
        ('StructuredReporting/SRDocument.swift', 'CompletionFlag', p3, 'Completion Flag', 'C.17-2'),
        ('StructuredReporting/SRDocument.swift', 'VerificationFlag', p3, 'Verification Flag', 'C.17-2'),
        ('StructuredReporting/SRDocument.swift', 'PreliminaryFlag', p3, 'Preliminary Flag', 'C.17-2'),
        ('StructuredReporting/MeasurementExtractor.swift', 'MeasurementQualifier', parts[16], 'CID 42', None),
        ('StructuredReporting/KeyObjectSelectionBuilder.swift', 'func:concept', parts[16], 'CID 7010', None),
    ]
    for fname, enum, part, where, label in specs:
        src = files.get(fname)
        if src is None:
            continue
        if enum.startswith('func:'):
            body = dw.func_body(src, r'(?:func|var)\s+' + enum[5:] + r'\b')
            if where.startswith('CID '):
                code = re.findall(r'codeValue:\s*"([^"]+)"', body)
            else:
                code = re.findall(r'"([^"]*)"', ' '.join(re.findall(r'case\s+((?:"[^"]*"\s*,?\s*)+):', body)))
        else:
            code = active_string_cases(src, enum)
        if not code:
            rep.check(f'{enum} ({fname}): enum not found', 0, [f'no `enum {enum}` with string raw values'])
            continue
        if where.startswith('sect_'):
            terms, kind, lab = section_terms(part, where), '', where
        elif where.startswith('CID '):
            rows = cid_rows(part, where)
            # a function returning CodedConcepts is compared by code value (meanings are
            # checked by check_coded_concepts); an enum of strings by meaning, case-insensitively
            terms = [row[1] for row in rows] if enum.startswith('func:') else [row[2].upper() for row in rows]
            code = code if enum.startswith('func:') else [c.upper() for c in code]
            kind, lab = 'CID', where
        else:
            lab, kind, terms = attribute_terms(part, where, label)
        if not terms:
            rep.check(f'{enum} vs "{where}": no term list found in the 2026a text (check by hand)', 0, [], extra=[f'code: {code}'])
            continue
        std = set(terms)
        wrong = [f'{enum}: "{v}" is not a term of {where} ({lab})' for v in code if v not in std]
        extra = []
        if enum.startswith('func:') and not where.startswith('CID '):
            extra, wrong = [w + ' (accepted on input only)' for w in wrong], []   # lenient aliases on read
        missing = [] if kind == 'CID' else [f'{enum}: "{t}" ({kind or "term"} of {where}, {lab}) not carried' for t in terms if t not in set(code)]
        wrong, pending = split_pending(wrong)
        missing, pending2 = split_pending(missing)
        rep.check(f'PS3.3 {lab} "{where}" {kind}: {enum} ({fname})', len(set(code) & std), wrong,
                  missing=missing, extra=extra, pending=pending + pending2, fail_on_missing=False)


def check_cs_literals(rep, p3, p6, files, tags):
    """Every CS literal written to an attribute whose PS3.3 module table lists Enumerated Values
    or Defined Terms must be one of them (Image Type, Pixel Presentation, Modality, ...)."""
    dic = dw.dictionary(p6)
    term_cache = {}
    matched, wrong, unlisted = 0, [], set()
    pats = [re.compile(r'tag:\s*\.(\w+)\s*,\s*vr:\s*\.CS\s*,\s*value:\s*([^)\n]+)'),
            re.compile(r'setString\(([^,\n]+),\s*for:\s*\.(\w+)\s*,\s*vr:\s*\.CS\)')]
    for fname, src in files.items():
        for i, pat in enumerate(pats):
            for m in pat.finditer(src):
                kw, expr = (m.group(1), m.group(2)) if i == 0 else (m.group(2), m.group(1))
                literals = re.findall(r'"([A-Z][A-Z0-9_ \\]*)"', expr)
                if not literals:
                    continue
                tag = tags.get(kw)
                entry = dic.get(tag) if tag else None
                if entry is None:
                    continue
                name = entry[0]
                if name not in term_cache:
                    term_cache[name] = attribute_terms(p3, name)
                lab, kind, terms = term_cache[name]
                if not terms:
                    unlisted.add(name)
                    continue
                for lit in literals:
                    for value in lit.split('\\\\'):
                        if value in terms:
                            matched += 1
                        elif kind == 'Enumerated Values' or value not in ('', ' '):
                            wrong.append(f'{fname}:{line_of(src, m.start())}: "{value}" is not a {kind or "term"} of {name} ({lab})')
    wrong, pending = split_pending(wrong)
    rep.check('PS3.3 module tables: CS literals written to attributes with listed terms', matched, wrong,
              extra=[f'no term list found for {n}' for n in sorted(unlisted)], pending=pending)


def check_deidentification(rep, p15, files, tags):
    """PS3.15 Table E.1-1: every single-tag row, with its Basic Profile action and every option
    column, is in the generated ConfidentialityProfileTableE11.swift (D69), and the four pattern
    rows are applied by group in ConfidentialityEngine."""
    gen = load('generate_confidentiality_profile')
    std_rows, patterns = gen.rows(p15)
    src = files.get('Anonymization/ConfidentialityProfileTableE11.swift', '')
    code = {}
    for m in re.finditer(r'0x([0-9A-F]{8}): E11Row\((.*?)\),', src):
        code[m.group(1)] = dict(re.findall(r'(\w+): "([^"]*)"', m.group(2)))
    matched, wrong, missing = 0, [], []
    for tag, name, basic, options in std_rows:
        want = {'basic': basic, **options}
        if tag not in code:
            missing.append(f'{name} ({tag[:4]},{tag[4:]}) {basic}')
        elif code[tag] != want:
            wrong.append(f'{name} ({tag[:4]},{tag[4:]}): code {code[tag]}; Table E.1-1 {want}')
        else:
            matched += 1
    extra = [f'({t[:4]},{t[4:]}) is not a row of Table E.1-1' for t in sorted(set(code) - {r[0] for r in std_rows})]
    engine = files.get('Anonymization/ConfidentialityEngine.swift', '')
    for pattern, rule in (('(50xx,xxxx)', r'tag\.group & 0xFF00 == 0x5000'),
                          ('(60xx,3000)', r'tag\.element == 0x3000'), ('(60xx,4000)', r'tag\.element == 0x4000'),
                          ('(gggg,eeee) where gggg is odd', r'if isPrivate \{ return \.remove \}')):
        if any(p[0] == pattern and p[2] == 'X' for p in patterns) and re.search(rule, engine):
            matched += 1
        else:
            wrong.append(f'pattern row {pattern} (X) is not applied by the engine')
    rep.check('PS3.15 Table E.1-1: every row (Basic Profile action and option columns) and the pattern rows',
              matched, wrong + extra, missing)


def check_video_constraints(rep, p6, files):
    """PS3.6 Table A-1 names the profile and level of each video transfer syntax; the
    VideoConformanceValidator constraints must say the same."""
    src = files.get('Video/VideoConformanceValidator.swift', '')
    body = dw.func_body(src, r'static\s+func\s+constraints\b')
    std = dw.uid_registry(p6)
    matched, wrong = 0, []
    for m in re.finditer(r'case\s+((?:"1\.2\.840\.10008\.1\.2\.4\.\d+"(?:,\s*)?)+):\s*return\s+Constraints\((.*?)\)\s*\n', body, re.S):
        uids = re.findall(r'"([\d.]+)"', m.group(1))
        args = m.group(2)
        profile = re.search(r'requiredProfileName:\s*"([^"]+)"', args)
        level = re.search(r'maximumLevelTimesTen:\s*(\d+)', args)
        bd = 'requiresBluRayCompatibility: true' in args
        for uid in uids:
            name = std.get(uid, ('', ''))[0]
            if not name:
                wrong.append(f'{uid} not in Table A-1')
                continue
            std_profile = re.search(r'(BD-compatible )?((?:Main 10|Stereo High|High|Main)) Profile', name)
            std_level = re.search(r'Level (\d)\.(\d)', name)
            problems = []
            if profile and std_profile and profile.group(1) != std_profile.group(2):
                problems.append(f'profile "{profile.group(1)}" vs "{std_profile.group(2)}"')
            if level and std_level and int(level.group(1)) != int(std_level.group(1) + std_level.group(2)):
                problems.append(f'level {level.group(1)} vs {std_level.group(1)}.{std_level.group(2)}')
            if bool(std_profile and std_profile.group(1)) != bd:
                problems.append('BD-compatible flag')
            if problems:
                wrong.append(f'{uid} "{name}": ' + ', '.join(problems))
            else:
                matched += 1
    rep.check('PS3.6 Table A-1: video transfer syntax profile, level and BD flag in VideoConformanceValidator', matched, wrong)


def check_mpeg2_frame_rates(rep, p5, files):
    """PS3.5 Table 8-1 (MP@ML frame rate / maximum Rows, Columns), Table 8-2 (MP@HL frame
    rates) and Table 8-3 (MP@HL 1080-row frame rates) against the VideoConformanceValidator
    literals mpeg2MainLevelFormats, mpeg2HighLevelFrameRates, mpeg2HighLevel1080FrameRates (D238)."""
    src = files.get('Video/VideoConformanceValidator.swift', '')
    matched, wrong, missing = 0, [], []
    # Table 8-1: Video Type | Spatial resolution | Frame Rate | Frame Time | Maximum Rows | Maximum Columns
    code = {(m.group(1), float(m.group(2)), int(m.group(3)), int(m.group(4))) for m in re.finditer(
        r'MPEG2MainLevelFormat\(videoType:\s*"([^"]+)",\s*frameRate:\s*([\d.]+),\s*maximumRows:\s*(\d+),'
        r'\s*maximumColumns:\s*(\d+)\)', src)}
    std = {(r[0], float(r[2]), int(r[4]), int(r[5])) for r in dw.table_rows(p5, '8-1')}
    matched += len(code & std)
    missing += [f'Table 8-1 {r}' for r in sorted(std - code)]
    wrong += [f'not in Table 8-1: {r}' for r in sorted(code - std)]
    # Table 8-2: Video Type | Spatial resolution layer | Frame Rate | Frame Time
    body = src[src.find('mpeg2HighLevelFrameRates:'):]
    body = body[:body.find(']\n')]
    code = {(m.group(1), float(m.group(2))) for m in re.finditer(
        r'videoType:\s*"([^"]+)",\s*frameRate:\s*([\d.]+)', body)}
    std = {(r[0], float(r[2])) for r in dw.table_rows(p5, '8-2')}
    matched += len(code & std)
    missing += [f'Table 8-2 {r}' for r in sorted(std - code)]
    wrong += [f'not in Table 8-2: {r}' for r in sorted(code - std)]
    # Table 8-3 (rows directly under <table>): Rows | Columns | Frame rate | Video Type | P / I
    table = p5.table('8-3')
    rates = set()
    for tr in table.iter(dw.D + 'tr'):
        cells = [p5.text(c) for c in tr if c.tag == dw.D + 'td']
        if len(cells) >= 3 and cells[0] == '1080':
            # "29.97, 30" is the 30 Hz nominal rate and its 1/1.001 variant
            rates |= {float(v) for v in re.findall(r'[\d.]+', cells[2]) if float(v) == int(float(v))}
    m = re.search(r'mpeg2HighLevel1080FrameRates:\s*\[Double\]\s*=\s*\[([^\]]*)\]', src)
    code = {float(v) for v in re.findall(r'[\d.]+', m.group(1))} if m else set()
    matched += len(code & rates)
    missing += [f'Table 8-3 1080-row rate {r}' for r in sorted(rates - code)]
    wrong += [f'not a Table 8-3 1080-row rate: {r}' for r in sorted(code - rates)]
    rep.check('PS3.5 Tables 8-1, 8-2, 8-3: MPEG2 frame rates and Main Level maximum Rows / Columns in '
              'VideoConformanceValidator', matched, wrong, missing)


def check_video_audio_rules(rep, p5, files):
    """PS3.5 8.2.12 (per-format audio limits for AVC/HEVC, Table 8.2.12-1 container column) and
    the MPEG-1 Layer III paragraph of 8.2.5 (MPEG2 MP@ML audio) against the literals of
    VideoAudioRules in VideoAudioStreamInfo.swift (A1, A2)."""
    src = files.get('Video/VideoAudioStreamInfo.swift', '')
    matched, wrong, missing = 0, [], []

    def paras(xml_id):
        sec = dw.section_by_id(p5, xml_id)
        return [p5.text(p) for p in sec.iter(dw.D + 'para')] if sec is not None else []

    def khz(text):
        # "48, 96 kHz" and "32 kHz, 44.1 kHz or 48 kHz" both list kilohertz values
        return {int(round(float(v) * 1000)) for v in re.findall(r'\d+(?:\.\d+)?', text)} if 'kHz' in text else set()

    # 8.2.12: "<Format>" heading paragraph, then "Maximum bit rate: …", "Sampling frequency: …",
    # "Number of channels: …", and "If <Format> is used …, the container format shall be MPEG-2 TS."
    heads = {'LPCM': 'lpcm', 'AC-3': 'ac3', 'AAC': 'aac', 'CBR MPEG-1 LAYER III (MP3) Audio Standard': 'mp3',
             'MPEG-1 LAYER II (MP2)': 'mp2'}
    std = {}
    current = None
    for text in paras('sect_8.2.12'):
        if text in heads:
            current = heads[text]
            std[current] = {'ts_only': False}
            continue
        if current is None:
            continue
        m = re.match(r'Maximum bit rate:\s*([\d.]+)\s*(M|k)bps', text)
        if m:
            std[current]['max_bps'] = int(round(float(m.group(1)) * (1_000_000 if m.group(2) == 'M' else 1000)))
        m = re.match(r'Sampling frequency:\s*(.*)', text)
        if m:
            std[current]['rates'] = khz(m.group(1))
        m = re.match(r'Number of channels:\s*(.*)', text)
        if m:
            std[current]['channels'] = m.group(1)
        if re.match(r'If .* is used for Audio components, the container format shall be MPEG-2 TS', text):
            std[current]['ts_only'] = True
    # Table 8.2.12-1: the MP4 column says "-" for the TS-only formats
    for row in dw.table_rows(p5, '8.2.12-1'):
        if len(row) == 3 and row[0] in ('LPCM', 'AC3'):
            if (row[2] == '-') != std.get({'AC3': 'ac3'}.get(row[0], 'lpcm'), {}).get('ts_only'):
                wrong.append(f'Table 8.2.12-1 {row[0]} MP4 column disagrees with the 8.2.12 "shall be MPEG-2 TS" sentence')
            else:
                matched += 1
    if len(std) != 5:
        missing.append(f'8.2.12 names {len(std)} formats, expected LPCM, AC-3, AAC, MP3, MP2')

    body = dw.func_body(src, r'static\s+func\s+avcHEVCProblems\b')
    for fmt, rule in std.items():
        block = re.search(r'case \.' + fmt + r':(.*?)(?=\n\s+case |\Z)', body, re.S)
        if not block:
            missing.append(f'avcHEVCProblems has no case .{fmt}')
            continue
        code = block.group(1)
        m = re.search(r'bitRateProblems\([^)]*maximum:\s*([\d_]+)', code)
        if not m or int(m.group(1).replace('_', '')) != rule.get('max_bps'):
            wrong.append(f'.{fmt} maximum bit rate: code {m and m.group(1)} vs 8.2.12 {rule.get("max_bps")}')
        else:
            matched += 1
        m = re.search(r'sampleRateProblems\([^)]*permitted:\s*\[([^\]]*)\]', code)
        rates = {int(v.replace('_', '')) for v in re.findall(r'[\d_]+', m.group(1))} if m else set()
        if rates != rule.get('rates'):
            wrong.append(f'.{fmt} sampling frequencies: code {sorted(rates)} vs 8.2.12 {sorted(rule.get("rates", []))}')
        else:
            matched += 1
        ts_only = 'container != .mpegTS' in code
        if ts_only != rule['ts_only']:
            wrong.append(f'.{fmt} container: code {"TS only" if ts_only else "TS or MP4"} vs 8.2.12 / Table 8.2.12-1')
        else:
            matched += 1
        chan = rule.get('channels', '')
        m = re.search(r'channelProblems\([^)]*permitted:\s*\[([^\]]*)\]', code)
        if m:
            code_ch = {int(v) for v in re.findall(r'\d+', m.group(1))}
            std_ch = {6 if v == '5.1' else int(v) for v in re.findall(r'\d(?:\.\d)?', chan)}
            if code_ch != std_ch:
                wrong.append(f'.{fmt} channels: code {sorted(code_ch)} vs 8.2.12 "{chan}"')
            else:
                matched += 1
        elif 'channels > 2' in code and chan.startswith('one main mono or stereo channel'):
            matched += 1
        elif fmt != 'lpcm' or ('channels != 2' in code and chan.startswith('2 channels')):
            matched += 1 if fmt == 'lpcm' else 0
            if fmt != 'lpcm':
                wrong.append(f'.{fmt} channels not checked by code; 8.2.12 says "{chan}"')
        else:
            wrong.append(f'.lpcm channels: 8.2.12 says "{chan}"')
        if 'isConstantBitRate == false' in code:
            if fmt == 'mp3':
                matched += 1
            else:
                wrong.append(f'.{fmt} checks CBR but 8.2.12 names CBR only for MP3')
        elif fmt == 'mp3':
            wrong.append('.mp3: 8.2.12 requires CBR MPEG-1 Layer III, code does not check it')

    # 8.2.5 audio paragraphs (MPEG2 MP@ML): CBR MP3, 32/44.1/48 kHz, one main mono or stereo channel
    sect5 = paras('sect_8.2.5')
    start = next((i for i, t in enumerate(sect5) if t.startswith('Any audio components')), None)
    audio5 = sect5[start:start + 8] if start is not None else []
    body5 = dw.func_body(src, r'static\s+func\s+mpeg2Problems\b')
    if not any(t.startswith('CBR MPEG-1 LAYER III (MP3)') for t in audio5):
        missing.append('8.2.5 audio paragraph "CBR MPEG-1 LAYER III (MP3)" not found')
    elif 'audio.format == .mp3' in body5 and 'isConstantBitRate == false' in body5:
        matched += 1
    else:
        wrong.append('mpeg2Problems does not require CBR MP3 (8.2.5)')
    rates5 = set()
    for t in audio5:
        if 'kHz' in t:
            rates5 = khz(t.split(' for the main channel')[0])
    m = re.search(r'sampleRateProblems\([^)]*permitted:\s*\[([^\]]*)\]', body5)
    code5 = {int(v.replace('_', '')) for v in re.findall(r'[\d_]+', m.group(1))} if m else set()
    if rates5 and code5 == rates5:
        matched += 1
    else:
        wrong.append(f'mpeg2Problems sampling frequencies: code {sorted(code5)} vs 8.2.5 {sorted(rates5)}')
    if any(t.startswith('one main mono or stereo channel') for t in audio5) and 'channels > 2' in body5:
        matched += 1
    else:
        wrong.append('mpeg2Problems channel rule vs 8.2.5 "one main mono or stereo channel"')
    rep.check('PS3.5 8.2.12 (and Table 8.2.12-1) / 8.2.5 audio: VideoAudioRules per-format bit rate, sampling '
              'frequency, channels, container and CBR limits', matched, wrong, missing)


def check_waveform_sample_interpretation(rep, p3, files):
    """PS3.3 Table C.10-10: the Sample Interpretation terms and which of them are signed."""
    src = files.get('Waveform/Waveform.swift', '')
    rows = dw.table_rows(p3, 'C.10-10')
    std = {}
    for row in rows:
        cells = [c for c in row if c]
        if len(cells) >= 2 and re.fullmatch(r'[A-Z]{2}', cells[-2]):
            std[cells[-2]] = cells[-1].startswith('signed')
    code = active_string_cases(src, 'WaveformSampleInterpretation')
    body = dw.func_body(src, r'var\s+isSigned\b')
    signed_cases = set(re.findall(r'\.(\w+)', re.search(r'case ([^:]+): return true', body).group(1))) if 'return true' in body else set()
    raw_of = dict(re.findall(r'case\s+(\w+)\s*=\s*"([A-Z]{2})"', dw.enum_body(src, 'WaveformSampleInterpretation')))
    matched, wrong, missing = 0, [], []
    for name, raw in raw_of.items():
        if raw not in std:
            wrong.append(f'"{raw}" is not a Table C.10-10 term')
        elif (name in signed_cases) != std[raw]:
            wrong.append(f'{raw} is {"signed" if std[raw] else "unsigned"} in Table C.10-10 but isSigned says otherwise')
        else:
            matched += 1
    missing = [f'"{t}" not carried' for t in std if t not in code]
    wrong, pending = split_pending(wrong)
    rep.check('PS3.3 Table C.10-10: WaveformSampleInterpretation terms and signedness', matched, wrong,
              missing=missing, pending=pending, fail_on_missing=False)


def check_photometric_terms(rep, p3, files):
    """String literals compared with Photometric Interpretation must be C.7.6.3.1.2 terms. In the DICOMDIR
    sources "PALETTE" is a Directory Record Type (PS3.3 Table F.3-3 Defined Terms), not a photometric term."""
    terms = set(section_terms(p3, 'sect_C.7.6.3.1.2'))
    record_types = set(attribute_terms(p3, 'Directory Record Type')[2] or [])
    matched, wrong = 0, []
    for fname, src in files.items():
        for m in re.finditer(r'"((?:MONOCHROME|PALETTE|RGB|HSV|ARGB|CMYK|YBR|XYB)[A-Z0-9_ ]*)"', src):
            if 'DICOMDIR' in fname and m.group(1) in record_types:
                matched += 1
                continue
            if m.group(1) in terms or m.group(1) in ('RGB ', 'MONOCHROME') or 'hasPrefix' in src[max(0, m.start() - 30):m.start()]:
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: "{m.group(1)}"')
    rep.check('PS3.3 C.7.6.3.1.2: Photometric Interpretation string literals are defined terms', matched, wrong)


# --- non-image SOP classes (PS3.4 Tables B.5-1 and GG.3-1, PS3.3 IOD module tables) ---

PIXEL_MODULES = {'C.7.6.3': 'Image Pixel Module', 'C.7.6.24': 'Floating Point Image Pixel Module',
                 'C.7.6.25': 'Double Floating Point Image Pixel Module'}


def storage_sop_classes(p4):
    """{uid: (name, IOD section id)} for every SOP Class PS3.4 links to a PS3.3 IOD: Table
    B.5-1 (Storage) and Table GG.3-1 (Non-Patient Object Storage)."""
    out = {}
    for label in ('B.5-1', 'GG.3-1'):
        for row in dw.table_rows(p4, label):
            uids = [c for c in row if re.fullmatch(r'1\.2\.840\.10008\.[\d.]+', c)]
            iods = [c for c in row if c.startswith('PS3.3 sect_A')]
            if uids and iods:
                out.setdefault(uids[0], (row[0], iods[0].replace('PS3.3 ', '').strip()))
    return out


def non_image_sop_classes(p3, p4):
    """{uid: name} of the SOP Classes whose IOD module tables name none of the modules that
    carry pixel data (PS3.3 C.7.6.3, C.7.6.24, C.7.6.25)."""
    for ref, title in PIXEL_MODULES.items():
        if dw.section_title(p3, f'sect_{ref}') != title:
            sys.exit(f'PS3.3 {ref} is no longer the {title}; re-read')
    sections = {sec.get(X + 'id'): sec for sec in p3.root.iter(D + 'section')}
    out = {}
    for uid, (name, sid) in storage_sop_classes(p4).items():
        sec = sections.get(sid)
        if sec is None:
            sys.exit(f'{name}: IOD {sid} not found in PS3.3')
        refs = set()
        for t in sec.iter(D + 'table'):
            rows = list(p3.rows(t, header=True))
            if rows and any('Module' in c for c in rows[0]):
                for r in rows[1:]:
                    for c in r:
                        refs.update(re.findall(r'\b(C\.\d+(?:\.\d+)*)\b', c))
        if not refs:
            sys.exit(f'{name}: no module table found under {sid}')
        if not refs & set(PIXEL_MODULES):
            out[uid] = name
    return out


def check_non_image_sop_classes(rep, p3, p4, files):
    """DICOMFile.nonImageSOPClasses must be exactly the SOP Classes without a pixel module."""
    src = files.get('DICOMFile+PixelData.swift', '')
    m = re.search(r'nonImageSOPClasses: Set<String> = \[(.*?)\n    \]', src, re.S)
    code = set(re.findall(r'"(1\.2\.840\.10008[\d.]+)"', m.group(1))) if m else set()
    std = non_image_sop_classes(p3, p4)
    storage = storage_sop_classes(p4)
    wrong = [f'{u} ({storage[u][0] if u in storage else "not a PS3.4 B.5-1 / GG.3-1 SOP Class"}) '
             f'is not a non-image SOP Class' for u in sorted(code - set(std))]
    missing = [f'{u} {std[u]}' for u in sorted(set(std) - code)]
    rep.check(f'PS3.4 Tables B.5-1 / GG.3-1 + PS3.3 IOD modules: nonImageSOPClasses is every SOP Class '
              f'without a pixel module ({len(std)} of {len(storage)})', len(code & set(std)), wrong, missing)


def emit_non_image_swift(p3, p4):
    """The Swift literal for DICOMFile.nonImageSOPClasses, generated from the text."""
    for uid, name in sorted(non_image_sop_classes(p3, p4).items(),
                            key=lambda kv: [int(x) for x in kv[0].split('.')]):
        print(f'        "{uid}",' + ' ' * max(1, 36 - len(uid)) + f'// {name}')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True, help='directory with partNN_<edition>.xml files')
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--sources', default=os.path.join(os.path.dirname(HERE), 'Sources', 'DICOMKit'))
    ap.add_argument('--core', default=os.path.join(os.path.dirname(HERE), 'Sources', 'DICOMCore'))
    ap.add_argument('--verbose', action='store_true')
    ap.add_argument('--only', help='run only checks whose function name contains this text')
    ap.add_argument('--emit-non-image-swift', action='store_true',
                    help='print the generated DICOMFile.nonImageSOPClasses literal and exit')
    args = ap.parse_args()

    parts = {}
    for n in (3, 4, 5, 6, 7, 10, 15, 16):
        path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
        if n == 7 and not os.path.exists(path):
            continue                                   # optional: command elements for tag names
        parts[n] = nd.Part(path)
        sub = parts[n].subtitle
        if args.edition not in sub:
            sys.exit(f'{path}: subtitle {sub!r} does not name {args.edition}')
        print(f'using {path}: {sub}')
    if args.emit_non_image_swift:
        emit_non_image_swift(parts[3], parts[4])
        return
    rep = dw.Report(args.verbose)
    files = dw.read_all(args.sources)
    tags, local_tags = tag_constants(args.core, files)

    # a UID literal used only as a prefix (`hasPrefix("1.2.840.10008.1.2.4.20")`) is not a UID
    uid_files = {n: re.sub(r'hasPrefix\("1\.2\.840\.10008[\d.]*"\)', 'hasPrefix("")', s) for n, s in files.items()}
    checks = [
        ('uids', lambda: dw.check_uids(rep, parts[6], uid_files)),
        ('coded_concepts', lambda: check_coded_concepts(rep, parts[16], files)),
        ('vr_literals', lambda: check_vr_literals(rep, parts[6], files, tags)),
        ('typed_reads', lambda: check_typed_reads(rep, parts[6], files, tags)),
        ('tag_names', lambda: check_tag_names(rep, parts[6], files, local_tags, parts.get(7))),
        ('citations', lambda: check_citations(rep, parts, files)),
        ('sr_value_types', lambda: check_sr_value_types(rep, parts[3], args.core)),
        ('enums', lambda: check_enums(rep, parts, files)),
        ('cs_literals', lambda: check_cs_literals(rep, parts[3], parts[6], files, tags)),
        ('deidentification', lambda: check_deidentification(rep, parts[15], files, tags)),
        ('video', lambda: check_video_constraints(rep, parts[6], files)),
        ('mpeg2-frame-rates', lambda: check_mpeg2_frame_rates(rep, parts[5], files)),
        ('video-audio', lambda: check_video_audio_rules(rep, parts[5], files)),
        ('waveform', lambda: check_waveform_sample_interpretation(rep, parts[3], files)),
        ('photometric', lambda: check_photometric_terms(rep, parts[3], files)),
        ('non_image_sop_classes', lambda: check_non_image_sop_classes(rep, parts[3], parts[4], files)),
    ]
    for name, fn in checks:
        if args.only and args.only not in name:
            continue
        fn()

    print(f'\n{rep.failed} check(s) with wrong or missing values, {rep.pending} pending owner approval')
    sys.exit(1 if rep.failed else 0)


if __name__ == '__main__':
    main()
