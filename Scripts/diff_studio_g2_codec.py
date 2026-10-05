#!/usr/bin/env python3
"""G2 codec / transfer-syntax / label checks for diff_studio.py (loaded by glob; exports CHECKS).

Each check extracts values from the DICOMStudio Swift sources by regex and diffs them against the frozen
2026a DocBook (PS3.6 Table A-1 and Table 6-1, PS3.3 C.7.6.3.1.2, C.7.3.1.1.1, C.7.6.1.1.1, Table C.17.3-7). Nothing is
transcribed by hand; see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md (G2, codec) for the results.

    python3 Scripts/diff_studio.py --nema DIR --group G2 --only codec
"""
import os
import re

TS_ROOT = '1.2.840.10008.1.2'

# --- helpers ---------------------------------------------------------------------------------------

def line_of(src, pos):
    return src.count('\n', 0, pos) + 1


def transfer_syntaxes(dw, p6):
    """{uid: name} of every PS3.6 Table A-1 row whose UID Type column is "Transfer Syntax", plus a suffix
    index ('.4.90' -> uid). (diff_cli.transfer_syntaxes filters on diff_web.uid_registry's second column,
    which is the keyword, and so returns nothing — read the rows directly.)"""
    ts = {row[0]: row[1] for row in dw.table_rows(p6, 'A-1') if len(row) > 3 and row[3] == 'Transfer Syntax'}
    by_suffix = {}
    for uid in ts:
        parts = uid.split('.')
        for n in (1, 2, 3):
            if len(parts) > n:
                by_suffix.setdefault('.' + '.'.join(parts[-n:]), uid)
    return ts, by_suffix


def names_match(dw, cand, name):
    a, b = dw.norm_name(cand), dw.norm_name(name)
    return bool(a) and (a == b or b.startswith(a) or a.endswith(b) or b.endswith(a))


def variablelist_entries(nd, dw, part, xml_id):
    """[(term, description)] of every varlistentry under a section, list by list."""
    D = nd.D
    sec = dw.section_by_id(part, xml_id)
    lists = []
    for vl in sec.iter(D + 'variablelist'):
        entries = []
        for ve in vl.findall(D + 'varlistentry'):
            term = nd.norm(''.join(ve.find(D + 'term').itertext())).strip()
            item = ' '.join(''.join(ve.find(D + 'listitem').itertext()).split())
            entries.append((term, item))
        lists.append(entries)
    return lists


def core_enum_raw_values(ctx, relpath, enum_name):
    """{caseName: rawValue} of a `enum X: String` in DICOMCore."""
    src = ctx['dw'].read(os.path.join(ctx['sources'], relpath))
    m = re.search(r'enum\s+' + enum_name + r'\s*:\s*String.*?\{(.*)', src, re.S)
    body = m.group(1) if m else src
    return dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', body))


# --- checks ----------------------------------------------------------------------------------------

def check_transfer_syntax_names(rep, parts, files, ctx):
    """Every transfer-syntax name tied to a UID in Studio text — `"uid", // Name`, `case "uid": return "Name"`,
    `"Name (uid)"` / `"Name (.4.90)"`, `// .4.57 Name` beside a catalog token — spells the PS3.6 Table A-1
    name (modulo diff_web.norm_name; an A-1 prefix is accepted). Runs over every ST file of the module,
    not only G2, so ImportValidation (G1) and FileOperationsHelpers (G4) are covered."""
    dw = ctx['dw']
    ts, by_suffix = transfer_syntaxes(dw, parts[6])
    all_files = ctx['studio_files'](tier='ST')
    matched, wrong = 0, []
    pats = [
        # "1.2.840.10008.1.2.4.70",   // Name   (comment may carry a trailing " — note")
        (re.compile(r'"(' + re.escape(TS_ROOT) + r'[\d.]*)"[ \t]*,?[ \t]*//[ \t]*([^\n]+)'), 'comment'),
        # case "1.2.840.10008.1.2.4.70":  return "Name"
        (re.compile(r'case\s+"(' + re.escape(TS_ROOT) + r'[\d.]*)"\s*:\s*return\s+"([^"]+)"'), 'case'),
        # "Name (1.2.840.10008.1.2.4.70)" or "Name (.4.70)"
        (re.compile(r'"([A-Z][A-Za-z0-9 ,/()+-]{2,80}?)\s*\((' + re.escape(TS_ROOT) + r'[\d.]*|\.\d+(?:\.\d+){0,2})\)"'), 'label'),
        # row("token"),  // .4.57 Name
        (re.compile(r'row\("[^"]+"\)\s*,\s*//\s*(\.\d+(?:\.\d+){0,2})\s+([^\n]+)'), 'rowcomment'),
    ]
    for fname, src in all_files.items():
        for pat, kind in pats:
            for m in pat.finditer(src):
                if kind == 'label':
                    cand, key = m.group(1), m.group(2)
                else:
                    key, cand = m.group(1), m.group(2)
                uid = key if key.startswith('1.') else by_suffix.get(key)
                if uid not in ts:
                    continue
                cand = re.split(r'\s+—\s+|\s+-\s+|,\s+(?:reversible|irreversible)', cand.strip())[0].strip()
                if names_match(dw, cand, ts[uid]):
                    matched += 1
                else:
                    wrong.append(f'{fname}:{line_of(src, m.start())}: "{cand}" for {uid}; A-1 "{ts[uid]}"')
    wrong, pending, deferred = ctx['split_pending'](wrong)
    rep.check('G2 codec: transfer-syntax names tied to a UID in Studio text are PS3.6 Table A-1 names',
              matched, wrong, pending=pending, extra=deferred)


def check_photometric_sets(rep, parts, files, ctx):
    """ThumbnailHelpers.renderablePhotometricInterpretations (resolved through DICOMCore's enum) and the
    `case "TERM":` labels of ImageMetadataHelpers.photometricLabel are exactly the PS3.3 C.7.6.3.1.2 Defined
    Terms minus those whose text is "Retired. See PS3.3-2001" (HSV, ARGB, CMYK; YBR_PARTIAL_422, retired in
    2017b, is kept for legacy files)."""
    nd, dw = ctx['nd'], ctx['dw']
    entries = [e for lst in variablelist_entries(nd, dw, parts[3], 'sect_C.7.6.3.1.2') for e in lst]
    std = {t for t, d in entries if not d.startswith('Retired. See PS3.3-2001')}
    raw = core_enum_raw_values(ctx, 'DICOMCore/PhotometricInterpretation.swift', 'PhotometricInterpretation')
    th = files.get('DICOMStudio/Components/ThumbnailHelpers.swift', '')
    m = re.search(r'renderablePhotometricInterpretations\s*:\s*\[PhotometricInterpretation\]\s*=\s*\[(.*?)\]', th, re.S)
    cases = re.findall(r'\.(\w+)', m.group(1)) if m else []
    ours = {raw.get(c, f'?{c}') for c in cases}
    rep.check('G2 codec (D10): ThumbnailHelpers photometric set == PS3.3 C.7.6.3.1.2 terms (less the 2001-retired three)',
              len(ours & std), wrong=sorted(ours - std), missing=sorted(std - ours))
    im = files.get('DICOMStudio/Components/ImageMetadataHelpers.swift', '')
    body = re.search(r'func photometricLabel\(.*?\n    \}', im, re.S)
    labels = set(re.findall(r'case\s+"([A-Z_ 0-9]+)"\s*:', body.group(0))) if body else set()
    rep.check('G2 codec (D11): ImageMetadataHelpers.photometricLabel has a label per C.7.6.3.1.2 term (less the 2001-retired three)',
              len(labels & std), wrong=sorted(labels - std), missing=sorted(std - labels))


def check_modality_terms(rep, parts, files, ctx):
    """ModalityIcon / ModalityPicker offer DICOMCore's Modality.allCases and say "all 79 PS3.3 C.7.3.1.1.1
    defined terms": the current entries of DICOMCore's Modality.swift (minus its SC / VL conveniences) must
    be the first variablelist of C.7.3.1.1.1 and its retired entries the second; the "79" in the Studio doc
    comments must be that count."""
    nd, dw = ctx['nd'], ctx['dw']
    lists = variablelist_entries(nd, dw, parts[3], 'sect_C.7.3.1.1.1')
    current = {t for t, _ in lists[0]} if lists else set()
    retired = {t for lst in lists[1:] for t, _ in lst}
    src = dw.read(os.path.join(ctx['sources'], 'DICOMCore/Modality.swift'))
    def entries(name):
        m = re.search(name + r'\s*:\s*\[\(String, String, Category\)\]\s*=\s*\[(.*?)\n    \]', src, re.S)
        return re.findall(r'\(\s*"([A-Z0-9]+)"\s*,\s*"[^"]*"\s*,\s*\.(\w+)\s*\)', m.group(1)) if m else []
    ours_current = {c for c, cat in entries('currentEntries') if cat != 'nonStandard'}
    ours_retired = {c for c, _ in entries('retiredEntries')}
    rep.check('G2 codec: DICOMCore Modality current codes (offered by ModalityPicker) == PS3.3 C.7.3.1.1.1 Defined Terms',
              len(ours_current & current), wrong=sorted(ours_current - current), missing=sorted(current - ours_current))
    rep.check('G2 codec: DICOMCore Modality retired codes == PS3.3 C.7.3.1.1.1 Retired Defined Terms',
              len(ours_retired & retired), wrong=sorted(ours_retired - retired), missing=sorted(retired - ours_retired))
    wrong = []
    for fname in ('DICOMStudio/Components/ModalityIcon.swift', 'DICOMStudio/Components/ModalityPicker.swift'):
        for m in re.finditer(r'(\d+)(?:-item| codes| PS3\.3)', files.get(fname, '')):
            if int(m.group(1)) != len(current):
                wrong.append(f'{fname}:{line_of(files[fname], m.start())}: says {m.group(1)}, C.7.3.1.1.1 lists {len(current)}')
    rep.check('G2 codec: the modality count the Studio doc comments quote equals the C.7.3.1.1.1 count', 2 - len(wrong), wrong)


ARC_NAMES = {
    'structuredReportPrefix': (r'SR Storage|Key Object Selection Document Storage|Procedure Log Storage', 'report'),
    'encapsulatedPrefix': (r'^Encapsulated .* Storage$', 'document'),
    'presentationStatePrefix': (r'Presentation State Storage', 'presentationState'),
    'waveformPresentationStatePrefix': (r'Presentation State Storage', 'presentationState'),
    'waveformPrefix': (r'Waveform Storage|Presentation State Storage', 'waveform / presentationState'),
}


def check_sop_class_arcs(rep, parts, files, ctx):
    """ViewerContentKind classifies by OID arc. Each `…Prefix = "1.2.840.10008.5.1.4.1.1.N."` literal must be
    a parent of at least one PS3.6 Table A-1 SOP Class, every member's A-1 name must fit the arc's kind, and
    the two exact UIDs (Key Object Selection Document, Raw Data) must carry their A-1 names."""
    dw = ctx['dw']
    std = dw.uid_registry(parts[6])
    src = files.get('DICOMStudio/Models/ViewerContentKind.swift', '')
    matched, wrong, missing = 0, [], []
    for name, prefix in re.findall(r'static let (\w+Prefix)\s*=\s*"([\d.]+)"', src):
        if not prefix.endswith('.'):
            wrong.append(f'{name} = {prefix}: arcs end in "." so hasPrefix matches OID children only')
            continue
        members = {u: v[0] for u, v in std.items() if u.startswith(prefix)}
        if not members:
            missing.append(f'{name} = {prefix}: no PS3.6 Table A-1 UID under this arc')
            continue
        pat, kind = ARC_NAMES.get(name, (None, None))
        for uid, a1 in sorted(members.items()):
            if pat and not re.search(pat, a1):
                wrong.append(f'{name}: {uid} "{a1}" is under the arc but is not a {kind}')
            else:
                matched += 1
    for const, expect in (('keyObjectSelectionUID', 'Key Object Selection Document Storage'),
                          ('rawDataUID', 'Raw Data Storage')):
        m = re.search(r'static let ' + const + r'\s*=\s*"([\d.]+)"', src)
        if m and std.get(m.group(1), ('',))[0] == expect:
            matched += 1
        else:
            wrong.append(f'{const}: {m.group(1) if m else "?"} is not "{expect}" in Table A-1')
    rep.check('G2 codec: ViewerContentKind SOP Class arcs are PS3.6 Table A-1 OID arcs whose members fit the kind',
              matched, wrong, missing)


def check_uncompressed_syntaxes(rep, parts, files, ctx):
    """ViewerAnnotationText.compressionLine calls five syntaxes "Uncompressed": each must be a Table A-1
    transfer syntax whose name carries no codec (an "… VR … Endian" row), and every such non-retired,
    non-Papyrus A-1 row must be listed."""
    ts, _ = transfer_syntaxes(ctx['dw'], parts[6])
    src = files.get('DICOMStudio/Models/ViewerAnnotationText.swift', '')
    body = re.search(r'func compressionLine\(.*?return "Uncompressed"', src, re.S)
    ours = set(re.findall(r'"(' + re.escape(TS_ROOT) + r'[\d.]*)"', body.group(0))) if body else set()
    std = {u for u, n in ts.items() if re.search(r'(Implicit|Explicit) VR (Little|Big) Endian', n) and 'Papyrus' not in n}
    rep.check('G2 codec: ViewerAnnotationText "Uncompressed" syntaxes == the PS3.6 Table A-1 "… VR … Endian" rows',
              len(ours & std), wrong=sorted(ours - std), missing=sorted(std - ours))


def check_general_row_tags(rep, parts, files, ctx):
    """ViewerNonImageContent.generalRows: each `add("Label", 0xGGGG, 0xEEEE)` row's label must be the PS3.6
    Table 6-1 name of that tag or a trailing-word shortening of it ("Protocol" for Protocol Name,
    "Description" for Series Description)."""
    dw = ctx['dw']
    names = {r[0]: r[1] for r in dw.table_rows(parts[6], '6-1') if r and r[0].startswith('(')}
    src = files.get('DICOMStudio/Models/ViewerNonImageContent.swift', '')
    matched, wrong = 0, []
    for label, g, e in re.findall(r'add\("([^"]+)",\s*0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{4})', src):
        tag = f'({g.upper()},{e.upper()})'
        name = names.get(tag)
        if name and (label == name or name.endswith(' ' + label) or name.startswith(label + ' ')):
            matched += 1
        else:
            wrong.append(f'{tag} "{label}": Table 6-1 says "{name}"')
    rep.check('G2 codec: ViewerNonImageContent summary rows carry PS3.6 Table 6-1 names', matched, wrong)


SR_VALUE_ACCESSORS = {
    'TEXT': 'asText', 'NUM': 'asNumeric', 'CODE': 'asCode', 'DATETIME': 'asDateTime', 'DATE': 'asDate',
    'TIME': 'asTime', 'UIDREF': 'asUIDRef', 'PNAME': 'asPersonName', 'COMPOSITE': 'asComposite',
    'IMAGE': 'asImage', 'WAVEFORM': 'asWaveform', 'SCOORD': 'isCoordinate', 'SCOORD3D': 'isCoordinate',
    'TCOORD': 'isCoordinate', 'CONTAINER': 'asContainer', 'TABLE': 'asTable',
}


def check_sr_value_types(rep, parts, files, ctx):
    """StructuredReportNarrativeView renders one branch per PS3.3 Table C.17.3-7 Value Type (the DICOMCore
    AnyContentItem accessor named in SR_VALUE_ACCESSORS must appear in the view)."""
    dw = ctx['dw']
    std = [r[0] for r in dw.table_rows(parts[3], 'C.17.3-7') if r and r[0].isupper()]
    src = files.get('DICOMStudio/Views/ViewerNonImageContentView.swift', '')
    matched, missing, extra = 0, [], []
    for vt in std:
        acc = SR_VALUE_ACCESSORS.get(vt)
        if acc is None:
            extra.append(f'{vt}: no accessor mapped in SR_VALUE_ACCESSORS')
        elif re.search(r'\b' + acc + r'\b', src):
            matched += 1
        else:
            missing.append(f'{vt} (AnyContentItem.{acc})')
    for vt in SR_VALUE_ACCESSORS:
        if vt not in std:
            extra.append(f'{vt} is not a 2026a C.17.3-7 value type')
    rep.check('G2 codec: SR narrative covers every PS3.3 Table C.17.3-7 Value Type', matched, missing=missing, extra=extra)


def check_orientation_letters(rep, parts, files, ctx):
    """ViewerOrientationLabels.letters: the six letters are the Patient Orientation abbreviations of PS3.3
    C.7.6.1.1.1 (A P R L H F), paired by axis as the C.7.6.2.1.1 patient coordinate system defines +x/+y/+z
    (left, posterior, head)."""
    nd, dw = ctx['nd'], ctx['dw']
    sec = dw.section_by_id(parts[3], 'sect_C.7.6.1.1.1')
    text = ' '.join(''.join(sec.itertext()).split())
    std = dict(re.findall(r'\b([APRLHF]) \((anterior|posterior|right|left|head|foot)\)', text))
    src = files.get('DICOMStudio/Models/ViewerAnnotationText.swift', '')
    body = re.search(r'let axes = \[(.*?)\n\s*\]', src, re.S)
    ours = re.findall(r'direction\[(\d)\], positive: "(\w)", negative: "(\w)"', body.group(1)) if body else []
    want = {'0': ('L', 'R'), '1': ('P', 'A'), '2': ('H', 'F')}   # +x left, +y posterior, +z head (C.7.6.2.1.1)
    matched, wrong = 0, []
    for axis, pos, neg in ours:
        if (pos, neg) == want.get(axis) and pos in std and neg in std:
            matched += 1
        else:
            wrong.append(f'axis {axis}: +{pos}/-{neg}; C.7.6.1.1.1 letters {sorted(std)}, expected {want.get(axis)}')
    if len(std) < 6:
        wrong.append(f'could not read all six letters from C.7.6.1.1.1: {std}')
    rep.check('G2 codec: viewer orientation letters are the PS3.3 C.7.6.1.1.1 Patient Orientation abbreviations', matched, wrong)


CHECKS = [
    ('G2 codec: transfer-syntax names', check_transfer_syntax_names),
    ('G2 codec: photometric sets (D10, D11)', check_photometric_sets),
    ('G2 codec: modality terms', check_modality_terms),
    ('G2 codec: SOP Class arcs', check_sop_class_arcs),
    ('G2 codec: uncompressed syntaxes', check_uncompressed_syntaxes),
    ('G2 codec: general row tags', check_general_row_tags),
    ('G2 codec: SR value types', check_sr_value_types),
    ('G2 codec: orientation letters', check_orientation_letters),
]
