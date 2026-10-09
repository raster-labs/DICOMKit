#!/usr/bin/env python3
"""Diff the standard-derived constants and behaviour markers of Sources/DICOMPrintKit against the
frozen DICOM DocBook.

Usage:
    for p in 3 4 5 6 14 16; do python3 Scripts/nema_docbook.py fetch 2026a $p --out DIR; done
    python3 Scripts/diff_printkit.py --nema DIR [--sources Sources/DICOMPrintKit] [--verbose] [--only NAME]

Every check extracts the literals from the Swift files by regex (never by hand) and compares
them with the table or clause of the standard named in the check. It prints one line per
check with the counts (matched / wrong / missing / extra) and exits 1 when any check found a
wrong value or a missing required value. Values whose fix changes public API, or a point the
standard leaves ambiguous, wait for the owner's decision and are reported as PEND.

DICOMPrintKit carries little data of its own: the print enumerations it offers are DICOMNetwork
types, and the presentation states it writes go through DICOMKit builders. The checks therefore
resolve every value the module *uses* to the defining module's source and diff that value, and
check the module's own call sites (what it passes to the builders) against the IOD tables.

This is the extraction + diff step of the verification method in
DICOMCORE_STANDARD_IMPLEMENTATION.md, applied to DICOMPrintKit (see
DICOMPRINTKIT_STANDARD_IMPLEMENTATION.md for the results).
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


nd = load('nema_docbook')
dw = load('diff_web')          # Report, read_all, dictionary, uid_registry, section helpers, enum helpers
dk = load('diff_kit')          # tag constants, citations, typed reads, attribute terms
D, X = nd.D, nd.X

# Findings whose fix changes public API, or a point the standard leaves open, waiting for the
# owner's decision; reported as PEND, not FAIL. Each entry is a substring of the finding text
# it silences (see DICOMPRINTKIT_STANDARD_IMPLEMENTATION.md, priority action list).
PENDING_API_APPROVAL = {
    # P-MAMMO, P-GSDF and P-CROP were approved and applied on 2026-09-29.
}


def split_pending(items):
    wrong, pending = [], []
    for item in items:
        (pending if any(p in item for p in PENDING_API_APPROVAL) else wrong).append(item)
    return wrong, pending


def line_of(src, pos):
    return src.count('\n', 0, pos) + 1


def enum_raw_values(src, enum_name):
    """{case name: raw value} of a String-backed enum (or of a struct of named terms:
    FilmDestination since P-BIN, whose BIN_i values are `.bin(n)`)."""
    out = dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]*)"', dw.enum_body(src, enum_name)))
    out.update(re.findall(r'static\s+let\s+(\w+)\s*=\s*' + re.escape(enum_name) + r'\(term:\s*"([^"]*)"\)', src))
    return out


# --- the standard ------------------------------------------------------------------------

def attr_terms(p3, table, attr):
    """The Enumerated Values / Defined Terms of one attribute row of a module table.

    The print module tables (C.13-x) have three columns (no Type), which
    diff_kit.attribute_terms skips, so the row is found here by its first cell."""
    t = dk.table_by_label(p3, table)
    for body in t.iter(D + 'tbody'):
        for tr in body.findall(D + 'tr'):
            tds = [c for c in tr if c.tag in (D + 'td', D + 'th')]
            if len(tds) < 3 or nd.norm(''.join(tds[0].itertext())).lstrip('>').strip().lower() != attr.lower():
                continue
            kind, terms = dk.cell_terms(p3, tds[-1])
            if not terms:
                for xref in tds[-1].iter(D + 'xref'):
                    terms += dw.variablelist_terms(p3, xref.get('linkend'))
            return terms
    return []


def comment_sentences(src):
    """The module's comments only — each run of consecutive `//` lines joined into one block —
    split into sentences. Code between comments never joins two of them."""
    blocks, current = [], []
    for line in src.split('\n'):
        m = re.match(r'\s*///?\s?(.*)$', line)
        if m:
            current.append(m.group(1))
        elif current:
            blocks.append(' '.join(current))
            current = []
    if current:
        blocks.append(' '.join(current))
    # user-visible messages: adjacent string literals joined across `+`
    for m in re.finditer(r'"(?:[^"\\\n]|\\.)*"(?:\s*\+\s*"(?:[^"\\\n]|\\.)*")*', src):
        text = ''.join(re.findall(r'"((?:[^"\\\n]|\\.)*)"', m.group(0)))
        if 'PS3.' in text or 'Table ' in text:
            blocks.append(text)
    out = []
    for block in blocks:
        out += re.split(r'(?<=[.;])\s+(?=[A-Z(])', block)
    return out


def comment_text(src):
    """The source with consecutive comment lines joined, so a phrase wrapped across two
    `//` lines reads as one."""
    return re.sub(r'\n[ \t]*///?[ \t]?', ' ', src)


def table_cell_text(part, label, attr):
    """The description cell of one attribute row, as plain text."""
    t = dk.table_by_label(part, label)
    for body in t.iter(D + 'tbody'):
        for tr in body.findall(D + 'tr'):
            tds = [c for c in tr if c.tag in (D + 'td', D + 'th')]
            if tds and nd.norm(''.join(tds[0].itertext())).lstrip('>').strip().lower() == attr.lower():
                return nd.norm(' '.join(tds[-1].itertext()))
    return ''


# --- checks ------------------------------------------------------------------------------

def check_print_uids(rep, p4, p6, files, net):
    """The print SOP classes the module names resolve (in DICOMNetwork) to the Table A-1 UID
    of that name, and each image box class belongs to the meta SOP class of its colour
    (PS3.4 Tables H.3.2.2.1-1, H.3.2.2.2-1)."""
    a1 = dw.uid_registry(p6)
    consts = dict(re.findall(r'public\s+let\s+(\w+SOPClassUID)\s*=\s*"([\d.]+)"', net))
    used = sorted({m for src in files.values() for m in re.findall(r'\b(\w+SOPClassUID)\b', src)} & set(consts))
    meta = {'basicGrayscaleImageBoxSOPClassUID': dw.table_rows(p4, 'H.3.2.2.1-1'),
            'basicColorImageBoxSOPClassUID': dw.table_rows(p4, 'H.3.2.2.2-1')}
    matched, wrong = 0, []
    for name in used:
        uid = consts[name]
        if uid not in a1:
            wrong.append(f'{name} = {uid}: not in PS3.6 Table A-1')
            continue
        want = re.sub(r'(?<!^)(?=[A-Z])', ' ', name.replace('SOPClassUID', '')).lower()
        if dw.norm_name(want) not in dw.norm_name(a1[uid][0]):
            wrong.append(f'{name} = {uid}: Table A-1 names it "{a1[uid][0]}"')
            continue
        if name in meta and not any(r[0] == a1[uid][0] for r in meta[name]):
            wrong.append(f'{name}: "{a1[uid][0]}" is not in its meta SOP class table')
            continue
        matched += 1
    rep.check('PS3.6 Table A-1 / PS3.4 H.3.2.2: print SOP classes the module uses (resolved in DICOMNetwork)',
              matched, wrong)


def check_ps_sop_classes(rep, p6, files):
    a1 = dw.uid_registry(p6)
    src = files.get('PresentationState/PresentationStateStore.swift', '')
    body = re.search(r'presentationStateSOPClasses[^=]*=\s*\[(.*?)\]', src, re.S)
    uids = re.findall(r'"([\d.]+)"', body.group(1)) if body else []
    want = {'Grayscale Softcopy Presentation State Storage', 'Color Softcopy Presentation State Storage',
            'Pseudo-Color Softcopy Presentation State Storage'}
    got = {a1.get(u, ('?',))[0] for u in uids}
    wrong = [f'{u}: "{a1.get(u, ("not registered",))[0]}"' for u in uids if a1.get(u, ('',))[0] not in want]
    missing = sorted(want - got)
    rep.check('PS3.6 Table A-1: the presentation state SOP classes the store adopts (GSPS, CSPS, PCSPS)',
              len(uids) - len(wrong), wrong, missing)


# (catalog list, DICOMNetwork enum, PS3.3 table, attribute)
CATALOG = [
    ('filmSizes', 'FilmSize', 'C.13-3', 'Film Size ID'),
    ('orientations', 'FilmOrientation', 'C.13-3', 'Film Orientation'),
    ('priorities', 'PrintPriority', 'C.13-1', 'Print Priority'),
    ('mediumTypes', 'MediumType', 'C.13-1', 'Medium Type'),
    ('filmDestinations', 'FilmDestination', 'C.13-1', 'Film Destination'),
    ('magnificationTypes', 'MagnificationType', 'C.13-3', 'Magnification Type'),
    ('polarities', 'ImagePolarity', 'C.13-5', 'Polarity'),
    ('trimOptions', 'TrimOption', 'C.13-3', 'Trim'),
    ('presentationLUTShapes', 'PresentationLUTShape', 'C.11-4', 'Presentation LUT Shape'),
]


def check_catalog_terms(rep, p3, files, net):
    """Every value PrintOptionCatalog offers is a term of its attribute, and every term is
    offered (BIN_i matches BIN_1…; a Presentation LUT option realised in the pixels sends no
    shape and is not a term)."""
    src = files.get('PrintOptionCatalog.swift', '')
    for listname, enum, table, attr in CATALOG:
        terms = attr_terms(p3, table, attr)
        raw = enum_raw_values(net, enum)
        body = re.search(r'static\s+let\s+' + listname + r'\b[^=]*=\s*\[(.*?)\n\s*\]', src, re.S)
        cases = re.findall(r'\(\s*(?:\w+\.)?\.?(\w+)\s*,', body.group(1)) if body else []
        for n in (re.findall(r'\(\s*\.bin\((\d+)\)\s*,', body.group(1)) if body else []):
            raw = {**raw, f'bin({n})': f'BIN_{n}'}
            cases.append(f'bin({n})')
        wire = raw
        if enum == 'PresentationLUTShape':
            off = set(re.findall(r'case\s+\.(\w+)\s*:\s*return\s+nil',
                                 dw.func_body(dw.enum_body(net, 'PresentationLUTShape'), r'var\s+wireValue\b')))
            wire = {c: v for c, v in raw.items() if c not in off}
        matched, wrong, offered = 0, [], set()
        for case in cases:
            if case not in raw:
                wrong.append(f'{listname}: .{case} is not a {enum} case')
                continue
            if case not in wire:
                continue                       # realised in the pixels, never on the wire
            value = wire[case]
            offered.add(value)
            ok = value in terms or any('_i' in t and re.fullmatch(t.replace('_i', r'_\d+'), value) for t in terms)
            if ok:
                matched += 1
            else:
                wrong.append(f'{listname}: .{case} sends "{value}", not a {attr} term ({table}: {terms})')
        missing = [f'{attr} "{t}" not offered by {listname}' for t in terms
                   if t not in offered and not ('_i' in t and any(re.fullmatch(t.replace('_i', r'_\d+'), o) for o in offered))]
        missing, pending = split_pending(missing)
        rep.check(f'PS3.3 Table {table}: {attr} values PrintOptionCatalog.{listname} offers', matched, wrong,
                  missing, pending=pending)


def check_densities_and_depths(rep, p3, files):
    src = files.get('PrintOptionCatalog.swift', '')
    dens = re.findall(r'"([A-Z]+)"', re.search(r'densities[^=]*=\s*\[([^\]]*)\]', src).group(1))
    std = [t for t in attr_terms(p3, 'C.13-3', 'Border Density') if t.isalpha()]
    wrong = [d for d in dens if d not in std]
    rep.check('PS3.3 Table C.13-3: Border / Empty Image Density named values', len(dens) - len(wrong), wrong,
              [t for t in std if t not in dens])
    depths = [int(x) for x in re.findall(r'\d+', re.search(r'bitDepths[^=]*=\s*\[([^\]]*)\]', src).group(1))]
    gray = dk.table_by_label(p3, 'C.13-5')
    stored = []
    for body in gray.iter(D + 'tbody'):
        for tr in body.findall(D + 'tr'):
            tds = [c for c in tr if c.tag in (D + 'td', D + 'th')]
            if tds and nd.norm(''.join(tds[0].itertext())) == '>Bits Stored':
                stored.append([int(t) for t in dk.cell_terms(p3, tds[-1])[1] if t.isdigit()])
    want = stored[0] if stored else []
    rep.check('PS3.3 Table C.13-5: grayscale Bits Stored the catalog offers (Basic Grayscale Image Sequence)',
              len([d for d in depths if d in want]), [d for d in depths if d not in want],
              [d for d in want if d not in depths])


def check_raw_image_box(rep, p3, files):
    """--raw sends the source's stored pixel values; the preparer must refuse a frame whose
    pixel module Table C.13-5 does not allow in an image box (it cannot be corrected without
    changing the values, which is what raw forbids)."""
    src = files.get('PrintImagePreparer.swift', '')
    t = dk.table_by_label(p3, 'C.13-5')
    seq, std = None, {}
    for body in t.iter(D + 'tbody'):
        for tr in body.findall(D + 'tr'):
            tds = [c for c in tr if c.tag in (D + 'td', D + 'th')]
            name = nd.norm(''.join(tds[0].itertext())) if tds else ''
            if name.startswith('Basic Grayscale'):
                seq = 'gray'
            elif name.startswith('Basic Color'):
                seq = 'color'
            elif name.startswith('Original Image'):
                seq = None
            elif seq and name.startswith('>'):
                terms = dk.cell_terms(p3, tds[-1])[1]
                if terms:
                    std[(seq, name[1:])] = [x.rstrip('H').lstrip('0') or '0' for x in terms]
    code = {
        ('gray', 'Photometric Interpretation'): 'rawGrayscalePhotometric',
        ('gray', 'Bits Allocated'): 'rawGrayscaleBitsAllocated',
        ('gray', 'Bits Stored'): 'rawGrayscaleBitsStored',
        ('gray', 'Pixel Representation'): 'rawPixelRepresentation',
        ('color', 'Photometric Interpretation'): 'rawColorPhotometric',
        ('color', 'Bits Allocated'): 'rawColorBitsAllocated',
        ('color', 'Bits Stored'): 'rawColorBitsStored',
    }
    matched, wrong, missing = 0, [], []
    for key, const in code.items():
        m = re.search(r'static\s+let\s+' + const + r'\b[^=]*=\s*\[([^\]]*)\]', src)
        if not m:
            missing.append(f'{const} (the Table C.13-5 {key[0]} {key[1]} enumeration) is not checked for --raw frames')
            continue
        values = [v.strip().strip('"') for v in m.group(1).split(',') if v.strip()]
        want = std.get(key, [])
        if sorted(values) != sorted(want):
            wrong.append(f'{const} = {values}; Table C.13-5 enumerates {want}')
        else:
            matched += 1
    rep.check('PS3.3 Table C.13-5: --raw frames checked against the image box pixel enumerations', matched,
              wrong, missing)


def check_printer_status(rep, p3, files):
    std_status = attr_terms(p3, 'C.13-9', 'Printer Status')
    sec = dw.section_by_id(p3, 'sect_C.13.9.1')
    info_terms = {'NORMAL'} | {r[0] for r in p3.rows(sec.find('.//' + D + 'table'))}
    src = files.get('Printing/PrintSCPSettings.swift', '')
    raw = enum_raw_values(src, 'EmulatedPrinterStatus')
    matched, wrong = 0, []
    for case, value in raw.items():
        (wrong.append(f'EmulatedPrinterStatus.{case} = "{value}" is not a Printer Status term')
         if value not in std_status else None)
        matched += value in std_status
    body = dw.func_body(src, r'var\s+defaultStatusInfo\b')
    for case, value in re.findall(r'case\s+\.(\w+)\s*:\s*return\s+"([^"]*)"', body):
        if value in info_terms:
            matched += 1
        else:
            wrong.append(f'defaultStatusInfo(.{case}) = "{value}" is not a C.13.9.1 Printer Status Info term')
    for fname in ('PrintWorkflow.swift',):
        for m in re.finditer(r'case\s+"([A-Z]+)"', files.get(fname, '')):
            if m.group(1) in std_status:
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(files[fname], m.start())}: "{m.group(1)}" is not a Printer Status term')
    rep.check('PS3.3 Table C.13-9 / C.13.9.1: Printer Status and Printer Status Info values', matched, wrong,
              [t for t in std_status if t not in raw.values()])


def check_film_sizes(rep, p3, files, net):
    """Sheet sizes in FilmGeometry against the Film Size ID terms: NINXMIN in inches, NCMXMCM in
    centimetres, and the three the C.13-3 description states in metric (10INX14IN, A4, A3)."""
    terms = attr_terms(p3, 'C.13-3', 'Film Size ID')
    text = table_cell_text(p3, 'C.13-3', 'Film Size ID')
    stated = {}
    for tid, w, h, unit in re.findall(r'(\w+) corresponds with (\d+(?:\.\d+)?)\s*(?:CM)?\s*[xX]\s*(\d+(?:\.\d+)?)\s*(CM|millimeters)', text):
        k = 10 if unit == 'CM' else 1
        stated[tid] = (float(w) * k, float(h) * k)
    raw = enum_raw_values(net, 'FilmSize')
    src = files.get('Printing/FilmGeometry.swift', '')
    body = dw.func_body(src, r'func\s+portraitSizeMillimeters\b')
    code = {}
    for case, expr in re.findall(r'case\s+\.(\w+)\s*:\s*return\s+([^\n]+)', body):
        nums = [float(x) for x in re.findall(r'\d+(?:\.\d+)?', expr)]
        if len(nums) < 2:
            continue
        code[raw.get(case, case)] = (nums[0] * 25.4, nums[1] * 25.4) if expr.strip().startswith('inches') else (nums[0], nums[1])
    matched, wrong = 0, []
    for tid in terms:
        if tid in stated:
            want = stated[tid]
        elif (m := re.fullmatch(r'(\d+(?:_\d+)?)INX(\d+)IN', tid)):
            want = (float(m.group(1).replace('_', '.')) * 25.4, float(m.group(2)) * 25.4)
        elif (m := re.fullmatch(r'(\d+)CMX(\d+)CM', tid)):
            want = (float(m.group(1)) * 10, float(m.group(2)) * 10)
        else:
            continue
        got = code.get(tid)
        if got is None:
            wrong.append(f'{tid}: no sheet size')
        elif abs(got[0] - want[0]) > 0.5 or abs(got[1] - want[1]) > 0.5:
            wrong.append(f'{tid}: {got[0]:.1f} x {got[1]:.1f} mm; C.13-3 gives {want[0]:.1f} x {want[1]:.1f} mm')
        else:
            matched += 1
    rep.check('PS3.3 Table C.13-3: physical sheet size of every Film Size ID (FilmGeometry)', matched, wrong)


def check_tag_references(rep, p6, files):
    """Every `Name (GGGG,EEEE)` written in the module names the PS3.6 attribute of that tag."""
    dic = dw.dictionary(p6)

    def norm(s):
        return re.sub(r'[^a-z0-9]', '', s.lower())

    matched, wrong = 0, []
    pat = re.compile(r"([A-Z][A-Za-z/'\- ]{2,60}?)\s*\(([0-9A-Fa-f]{4}),([0-9A-Fa-f]{4})\)")
    for fname, raw in files.items():
        src = comment_text(raw)
        for m in pat.finditer(src):
            name, tag = m.group(1).strip(), (m.group(2) + m.group(3)).upper()
            entry = dic.get(tag)
            if entry is None:
                wrong.append(f'{fname}:{line_of(src, m.start())}: ({tag[:4]},{tag[4:]}) "{name}" is not in PS3.6 Table 6-1')
                continue
            words = name.split()
            # the attribute name is the tail of the phrase before the tag
            if any(norm(' '.join(words[i:])) in (norm(entry[0]), norm(entry[1])) for i in range(len(words))):
                matched += 1
            else:
                wrong.append(f'{fname}:{line_of(src, m.start())}: "{name}" ({tag[:4]},{tag[4:]}); PS3.6 name is "{entry[0]}"')
    rep.check('PS3.6 Table 6-1: attribute names written next to (GGGG,EEEE) in comments and messages', matched, wrong)


# Topic → the clause that governs it. A sentence that states the topic and cites clauses of
# the same family must cite at least one of the governing ones. (exclude: text that makes the
# sentence about something else, e.g. the softcopy Presentation LUT.)
TOPICS = [
    (r'Bits Stored|Bits Allocated|Planar Configuration|Basic (?:Colou?r|Grayscale) Image (?:Box|Sequence)',
     {'C.13-5', 'C.13.5', 'C.13.5.1'}, None),
    (r'Film Size ID|Image Display Format|Min Density|Max Density|Border Density|Annotation Display Format ID|film stock',
     {'C.13.3', 'C.13-3'}, None),
    (r'LIN OD|hardcopy Presentation LUT|Presentation LUT \(print\)', {'C.11.4', 'C.11-4'}, r'softcopy|INVERSE belongs'),
    (r'rotation|[Ff]lip', {'C.10.6', 'C.10-6'}, None),
    (r'Displayed Area', {'C.10.4', 'C.10-4'}, None),
    (r'[Ss]hutter', {'C.7.6.11', 'C.7-17a', 'C.11.12', 'C.11.12-1'}, None),
]


def family(c):
    return '.'.join(c.split('-')[0].split('.')[:2])


def check_citation_topics(rep, files):
    cite = re.compile(r'(?:PS3\.3[ ,]*)?(?:Table\s+)?\b(C\.\d+(?:\.\d+)*(?:-\d+[a-z]?)?)(?=[\s),;:.]|$)')
    matched, wrong = 0, []
    for fname, src in files.items():
        for sentence in comment_sentences(src):
            cites = [c.rstrip('.') for c in cite.findall(sentence)]
            if not cites:
                continue
            for topic, allowed, exclude in TOPICS:
                hit = re.search(topic, sentence)
                if not hit or (exclude and re.search(exclude, sentence)):
                    continue
                fams = {family(a) for a in allowed}
                relevant = [c for c in cites if family(c) in fams]
                if not relevant:
                    continue
                if any(c in allowed for c in relevant):
                    matched += 1
                else:
                    wrong.append(f'{fname}: cites {", ".join(relevant)} for "{hit.group(0)}"; the clause is {sorted(allowed)}')
    rep.check('Citations name the clause that governs their topic (C.13.3 / C.13.5 / C.11.4 / C.10.4 / C.10.6 / C.7.6.11)',
              matched, sorted(set(wrong)))


def check_titled_citations(rep, p3, files):
    """`C.x.y (Title)` names the section's 2026a title; in a sentence about print (it cites a
    C.13 clause), the Presentation LUT is the hardcopy module C.11.4, not the softcopy C.11.6."""
    stop = {'module', 'the', 'and', 'of', 'a', 'macro', 'attributes', 'basic', 'sop', 'class', 'id'}
    matched, wrong = 0, []
    for fname, src in files.items():
        for sentence in comment_sentences(src):
            for m in re.finditer(r'\b(C\.\d+(?:\.\d+)+)\s*\(([A-Z][^)]{2,60})\)', sentence):
                sect, desc = m.group(1), m.group(2)
                title = dw.section_title(p3, 'sect_' + sect) or ''
                dwords = {w for w in re.findall(r'[a-z0-9]+', desc.lower()) if w not in stop}
                twords = {w for w in re.findall(r'[a-z0-9]+', title.lower()) if w not in stop}
                if sect.startswith('C.11.6') and re.search(r'\bC\.13\.', sentence):
                    wrong.append(f'{fname}: {sect} ({desc}) in a print sentence; the hardcopy Presentation LUT is C.11.4')
                elif not title:
                    wrong.append(f'{fname}: {sect} ({desc}) does not exist in PS3.3 2026a')
                elif dwords and twords and not (dwords & twords):
                    wrong.append(f'{fname}: {sect} ({desc}); 2026a {sect} is "{title}"')
                else:
                    matched += 1
    rep.check('PS3.3 section titles given in parentheses after a citation', matched, wrong)


def check_ps_terms(rep, p3, files, kit):
    """Values the bridge and the store write through DICOMKit: Presentation Size Mode, Image
    Rotation, Graphic Annotation Units and Graphic Type (the cases DICOMPrintKit names)."""
    matched, wrong = 0, []
    size_mode = enum_raw_values(kit['SpatialTransformation.swift'], 'PresentationSizeMode')
    units = enum_raw_values(kit['GraphicAnnotation.swift'], 'AnnotationUnits')
    gtype = enum_raw_values(kit['GraphicAnnotation.swift'], 'PresentationGraphicType')
    std = {
        'size': attr_terms(p3, 'C.10-4', 'Presentation Size Mode'),
        'units': attr_terms(p3, 'C.10-5', 'Graphic Annotation Units') or attr_terms(p3, 'C.10-5', 'Bounding Box Annotation Units'),
        'gtype': attr_terms(p3, 'C.10-5', 'Graphic Type'),
        'rotation': attr_terms(p3, 'C.10-6', 'Image Rotation'),
    }
    src = ''.join(files.get(f, '') for f in ('PresentationState/ViewerPresentationStateBridge.swift',
                                              'PresentationState/PrintOverlayAnnotationGSPS.swift',
                                              'PresentationState/PresentationStateStore.swift'))
    for case in sorted(set(re.findall(r'sizeMode:\s*\.(\w+)', src))):
        v = size_mode.get(case)
        (matched := matched + 1) if v in std['size'] else wrong.append(f'Presentation Size Mode .{case} = {v}')
    for case in sorted(set(re.findall(r'[Uu]nits:\s*\.(\w+)', src))):
        v = units.get(case)
        (matched := matched + 1) if v in std['units'] else wrong.append(f'Annotation Units .{case} = {v}')
    compound = enum_raw_values(kit['GraphicStyle.swift'], 'CompoundGraphicType')
    compound_terms = attr_terms(p3, 'C.10-5', 'Compound Graphic Type')
    for case in sorted(set(re.findall(r'type\s*=\s*\.(\w+)|type:\s*\.(\w+)', src))):
        case = case[0] or case[1]
        if case in gtype:
            v = gtype[case]
            (matched := matched + 1) if v in std['gtype'] else wrong.append(f'Graphic Type .{case} = {v}')
        elif case in compound:
            v = compound[case]
            (matched := matched + 1) if v in compound_terms else wrong.append(f'Compound Graphic Type .{case} = {v}')
        else:
            wrong.append(f'.{case} is neither a Graphic Type nor a Compound Graphic Type case')
    rot = re.search(r'rotation:\s*quarterTurns\s*\*\s*90', src)
    if rot and sorted(std['rotation'], key=int) == ['0', '90', '180', '270']:
        matched += 1
    else:
        wrong.append(f'Image Rotation not written as quarterTurns * 90 (C.10-6 enumerates {std["rotation"]})')
    rep.check('PS3.3 Tables C.10-4, C.10-5, C.10-6: terms the presentation-state bridge writes (Graphic and Compound Graphic Type included)', matched, wrong)


def check_state_writers(rep, p3, p4, files):
    """D27/D36: every presentation-state builder call passes the image size (Displayed Area
    Selection Sequence is Type 1, Table C.10-4), the state carries the image's Modality LUT
    (PS3.4 N.2.1.1: without one the image's rescale "shall not be used"), and a colour image
    is written as a Color Softcopy Presentation State (Table A.33.2-1: no grey pipeline)."""
    src = files.get('PresentationState/PresentationStateStore.swift', '')
    n211 = ' '.join(dw.section_paras(p4, 'sect_N.2.1.1')) if hasattr(dw, 'section_paras') else ''
    matched, wrong, missing = 0, [], []
    for m in re.finditer(r'(\w+PresentationStateBuilder)\(\)\.buildDataSet\(', src):
        call = src[m.end():src.find('\n            }', m.end()) + 1]
        if 'imageSize:' in src[m.end():m.end() + 1200].split('buildDataSet(')[0]:
            matched += 1
        else:
            wrong.append(f'PresentationStateStore.swift:{line_of(src, m.start())}: {m.group(1)}.buildDataSet without imageSize:')
    if re.search(r'modalityLUT:\s*\w', dw.func_body(src, r'func\s+save\(')):
        matched += 1
    else:
        missing.append('save(): no Modality LUT in the state (PS3.4 N.2.1.1: the image\'s own rescale shall not be used)')
    if 'ColorPresentationStateBuilder' in src:
        matched += 1
    else:
        missing.append('save(): colour images are written as GSPS; Table A.33.2-1 (CSPS) is the IOD for them')
    rep.check('PS3.3 Table C.10-4, A.33.1-1, A.33.2-1; PS3.4 N.2.1.1: what the store passes to the builders (D27, D36)',
              matched, wrong, missing)


def check_text_string_length(rep, p5, files):
    """Text String (2030,0020) is LO: 64 characters maximum, no backslash (PS3.5 Table 6.2-1)."""
    rows = dw.table_rows(p5, '6.2-1')
    lo = next((r for r in rows if r and r[0].startswith('LO')), None)
    limit = int(re.search(r'(\d+) chars', ' '.join(lo)).group(1)) if lo else 64
    src = files.get('Printing/FilmIdentification.swift', '')
    m = re.search(r'static\s+let\s+textStringMaximumLength\s*=\s*(\d+)', src)
    if not m:
        rep.check('PS3.5 Table 6.2-1: annotation Text String (LO) kept within its length', 0, [],
                  [f'FilmIdentificationFooter.annotations(for:) sends caption lines as Text String (LO, {limit} chars max) unchecked'])
        return
    bad = [] if int(m.group(1)) == limit else [f'textStringMaximumLength = {m.group(1)}; LO is {limit}']
    if '"\\\\"' not in dw.func_body(src, r'func\s+textString\('):
        bad.append('annotations(for:) does not remove the backslash LO forbids')
    rep.check('PS3.5 Table 6.2-1: annotation Text String (LO) kept within its length', 1 if not bad else 0, bad)


def check_shutter_coordinates(rep, p3, files):
    """C.7.6.11: shutter edges and centres are pixel positions ("with respect to pixels in the
    image given as column/row"), 1-based; the overlay built from them must start at pixel 1,
    not a pixel in."""
    text = table_cell_text(p3, 'C.7-17a', 'Shutter Left Vertical Edge')
    src = files.get('PresentationState/PresentationStateStore.swift', '')
    body = dw.func_body(src, r'func\s+shutterOverlay\(')
    ok = bool(re.search(r'-\s*1', body)) or '- 0.5' in body
    rep.check('PS3.3 Table C.7-17a: shutter pixel positions (1-based) converted to image fractions',
              1 if ok and 'pixels in the image' in text else 0,
              [] if ok else ['shutterOverlay divides the 1-based column/row by the image size without removing the 1'])


def check_gsdf(rep, p14, files):
    """PS3.14 7.1-7.3 and Annex D.2: the calibrated rendering (DensityMapping.gsdf). The
    coefficients of L(j) and j(L) in the Swift must be the 7.1 values, the mapping must exist,
    and the test fixture PrintGSDFTests.tableD21 must be Table D.2-1 (256 densities)."""
    text = nd.norm(' '.join(dw.section_by_id(p14, 'sect_7.1').itertext()))
    std = {name: float(value.replace(' ', '')) for name, value in
           re.findall(r'\b([a-mA-I]) = (- ?[\d.]+(?:E-?\d+)?|[\d.]+(?:E-?\d+)?)', text)}
    src = files.get('Printing/GrayscaleStandardDisplayFunction.swift', '')
    ours = {name: float(value) for name, value in
            re.findall(r'\b([a-mA-I]) = (-?[\d.]+(?:e-?\d+)?)', src)}
    matched, wrong, missing = 0, [], []
    for name, value in std.items():
        if name not in ours:
            missing.append(f'{name} = {value} (PS3.14 7.1) not in GrayscaleStandardDisplayFunction.swift')
        elif abs(ours[name] - value) > 1e-12 * max(1, abs(value)):
            wrong.append(f'{name} = {ours[name]}; PS3.14 7.1 gives {value}')
        else:
            matched += 1
    if 'case gsdf' not in files.get('Printing/ComposedFilm.swift', ''):
        missing.append('DensityMapping has no calibrated (GSDF) mapping')
    table = [float(v) for row in dw.table_rows(p14, 'D.2-1') for v in [c for c in row if c][1::2]]
    test_path = os.path.join(ROOT, 'Tests', 'DICOMPrintKitTests', 'PrintGSDFTests.swift')
    body = re.search(r'tableD21: \[Double\] = \[(.*?)\]', dw.read(test_path), re.S) if os.path.exists(test_path) else None
    fixture = [float(v) for v in re.findall(r'-?\d+\.\d+', body.group(1))] if body else []
    if fixture == table and len(table) == 256:
        matched += 1
    else:
        wrong.append(f'PrintGSDFTests.tableD21 ({len(fixture)} values) is not PS3.14 Table D.2-1 ({len(table)} values)')
    rep.check('PS3.14 7.1-7.3, Table D.2-1: GSDF coefficients and the calibrated rendering (DensityMapping.gsdf)',
              matched, wrong, missing)


def check_crop(rep, p3, files):
    """PS3.3 Table C.13-5 leaves "optimal filling" undefined; the reading (CROP with no size fills
    the box, P-CROP) must be stated in the conformance statement and at the composer."""
    text = table_cell_text(p3, 'C.13-5', 'Requested Image Size')
    doc = dw.read(os.path.join(ROOT, 'PRINT_CONFORMANCE.md'))
    src = files.get('Printing/FilmGeometry.swift', '')
    problems = []
    if 'optimal filling' not in text:
        problems.append('Table C.13-5 no longer says "optimal filling"; re-read the clause')
    if not re.search(r'3\.5 Image placement.*?optimal filling.*?CROP, no size', doc, re.S):
        problems.append('PRINT_CONFORMANCE.md does not state how CROP without a size is read')
    if 'PRINT_CONFORMANCE.md 3.5' not in src:
        problems.append('FilmImageFitter does not point at the stated reading')
    rep.check('PS3.3 Table C.13-5: CROP without a Requested Image Size read as stated in PRINT_CONFORMANCE.md 3.5',
              0 if problems else 1, problems)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True, help='directory with partNN_<edition>.xml files')
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--sources', default=os.path.join(ROOT, 'Sources', 'DICOMPrintKit'))
    ap.add_argument('--verbose', action='store_true')
    ap.add_argument('--only', help='run only checks whose name contains this text')
    args = ap.parse_args()

    parts = {}
    for n in (3, 4, 5, 6, 14, 16):
        path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
        parts[n] = nd.Part(path)
        if args.edition not in parts[n].subtitle:
            sys.exit(f'{path}: subtitle {parts[n].subtitle!r} does not name {args.edition}')
        print(f'using {path}: {parts[n].subtitle}')
    rep = dw.Report(args.verbose)
    files = dw.read_all(args.sources)
    net = ''.join(dw.read_all(os.path.join(ROOT, 'Sources', 'DICOMNetwork')).values())
    kit = {os.path.basename(k): v for k, v in dw.read_all(os.path.join(ROOT, 'Sources', 'DICOMKit', 'PresentationState')).items()}
    tags, local_tags = dk.tag_constants(os.path.join(ROOT, 'Sources', 'DICOMCore'), files)

    checks = [
        ('uids', lambda: dw.check_uids(rep, parts[6], files)),
        ('print_uids', lambda: check_print_uids(rep, parts[4], parts[6], files, net)),
        ('ps_sop_classes', lambda: check_ps_sop_classes(rep, parts[6], files)),
        ('catalog', lambda: check_catalog_terms(rep, parts[3], files, net)),
        ('densities', lambda: check_densities_and_depths(rep, parts[3], files)),
        ('raw_image_box', lambda: check_raw_image_box(rep, parts[3], files)),
        ('printer_status', lambda: check_printer_status(rep, parts[3], files)),
        ('film_sizes', lambda: check_film_sizes(rep, parts[3], files, net)),
        ('tag_references', lambda: check_tag_references(rep, parts[6], files)),
        ('tag_names', lambda: dk.check_tag_names(rep, parts[6], files, local_tags)),
        ('typed_reads', lambda: dk.check_typed_reads(rep, parts[6], files, tags)),
        ('vr_literals', lambda: dk.check_vr_literals(rep, parts[6], files, tags)),
        ('citations', lambda: dk.check_citations(rep, parts, files)),
        ('citation_topics', lambda: check_citation_topics(rep, files)),
        ('titled_citations', lambda: check_titled_citations(rep, parts[3], files)),
        ('photometric', lambda: dk.check_photometric_terms(rep, parts[3], files)),
        ('ps_terms', lambda: check_ps_terms(rep, parts[3], files, kit)),
        ('state_writers', lambda: check_state_writers(rep, parts[3], parts[4], files)),
        ('text_string', lambda: check_text_string_length(rep, parts[5], files)),
        ('shutters', lambda: check_shutter_coordinates(rep, parts[3], files)),
        ('gsdf', lambda: check_gsdf(rep, parts[14], files)),
        ('crop', lambda: check_crop(rep, parts[3], files)),
    ]
    for name, fn in checks:
        if args.only and args.only not in name:
            continue
        fn()

    print(f'\n{rep.failed} check(s) with wrong or missing values, {rep.pending} pending owner approval')
    sys.exit(1 if rep.failed else 0)


if __name__ == '__main__':
    main()
