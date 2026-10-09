#!/usr/bin/env python3
"""DICOMStudio group G5 (SR, terminology, measurements, SEG / RT / parametric map / WSI / waveform helpers, hanging
protocols, AI analysis, specialized modality, security UI) row-by-row checks against the frozen DICOM 2026a DocBook.

Loaded by diff_studio.py (``diff_studio_g5*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
Each check extracts the values the Swift source carries by regex and compares them with the standard's text:

  * coded concept literals (CodedConcept(...) and TerminologyHelpers entry(...))   vs PS3.16 Table D-1 and every CID table
  * coding scheme designators and their display names                             vs PS3.16 Table 8-1 (and the "99" rule)
  * SR value / relationship types, continuity, SCOORD / SCOORD3D / TCOORD types   vs PS3.3 Tables C.17.3-7, C.17.3-8,
                                                                                    C.18.8-1, C.18.6.1.2, C.18.9.1.2, C.18.7.1.1
  * SR, Secondary Capture and Waveform SOP Class UIDs and names                   vs PS3.6 Table A-1
  * RT ROI Interpreted Type, Dose Units, Radiation Type, Segment Algorithm Type   vs PS3.3 Tables C.8-44, C.8-39, C.8-50, C.8.20-4
  * Hanging Protocol Sorting Direction; built-in protocol modalities              vs PS3.3 Table C.23.3-1; C.7.3.1.1.1
  * Encapsulated Document MIME types                                               vs PS3.3 A.45.1 / A.45.2 / A.85.1-A.85.3 Enumerated Values
  * calibration attribute names                                                    vs PS3.6 Table 6-1
  * UCUM codes used for lengths / areas / angles                                   vs PS3.16 CID 7460 / 7461 / 7183
  * security UI: anonymization preview list vs the DICOMKit engine, TLS versions  vs PS3.15 B.12 / B.13 (B.1-B.11 retired)
  * section / table / TID / CID citations in the G5 files exist in 2026a           (diff_kit.check_citations)
"""
import os
import re

# Values known to differ from the standard whose fix changes public API (enum cases, raw values) and waits for the
# owner's approval; a wrong/missing item containing the key is reported as PEND, not FAIL. Empty since 2026-10-06:
# P-STUDIO-SR-TABLE (7c860399), -SCOORD-POLYGON (36fdb6d6), -RT-ROI-TYPES (0c97d71e), -RT-DOSE-UNITS (a6f2c0dd),
# -HP-SORTING-DIRECTION (e9bada7f) and -MEASURE-UM (824bcfab) are implemented, so the same term checks now fail
# (not PEND) on any regression.
PENDING_API_APPROVAL = {
}
DEFERRED = {}
EXEMPT = {}

HERE = os.path.dirname(os.path.abspath(__file__))
D = '{http://docbook.org/ns/docbook}'


def src(files, suffix):
    for name, s in files.items():
        if name.endswith(suffix):
            return s
    raise KeyError(suffix)


def line_of(s, pos):
    return s.count('\n', 0, pos) + 1


def split_pending(items):
    wrong, pending = [], []
    for item in items:
        tag = next((p for k, p in PENDING_API_APPROVAL.items() if k in item), None)
        (pending if tag else wrong).append(item + (f' [{tag}]' if tag else ''))
    return wrong, pending


def block(s, start_pat, what):
    m = re.search(start_pat, s)
    if not m:
        raise SystemExit(f'could not find {what} (/{start_pat}/); update the extractor')
    depth, i = 0, m.end() - 1
    while i < len(s):
        if s[i] in '[{(':
            depth += 1
        elif s[i] in ']})':
            depth -= 1
            if depth == 0:
                return s[m.end():i]
        i += 1
    raise SystemExit(f'unbalanced {what}')


def block_or_empty(s, start_pat, what):
    """block(), or '' when the construct is absent — for checks that must report a missing symbol as a finding."""
    try:
        return block(s, start_pat, what)
    except SystemExit:
        return ''


def section_by_label(part, label):
    for e in part.root.iter():
        if e.get('label') == label and e.tag in (D + 'section', D + 'chapter', D + 'appendix'):
            return e
    return None


def section_text(part, label):
    """Normalised text of a section including its tables (MIME values sit in IOD table cells)."""
    sec = section_by_label(part, label)
    if sec is None:
        return ''
    return ' '.join(part.text(e) for e in sec.iter() if e.tag in (D + 'para', D + 'td'))


# --- PS3.16 Table D-1 / CID tables: coded concepts -----------------------------------------------------------

CONCEPT = re.compile(r'codeValue:\s*"([^"]+)"\s*,\s*codingSchemeDesignator:\s*"([^"]+)"\s*,\s*codeMeaning:\s*"([^"]*)"', re.S)
ENTRY = re.compile(r'entry\(code:\s*"([^"]+)",\s*scheme:\s*"([^"]+)",\s*meaning:\s*"([^"]*)"')
HEADING = re.compile(r'"[a-z ]+":\s*\("([\d-]+)",\s*"([^"]+)"\)')   # SRBuilderHelpers.sectionHeadingCodes (LN)


def concept_literals(files):
    out = []
    for fname, s in files.items():
        for m in list(CONCEPT.finditer(s)) + list(ENTRY.finditer(s)):
            out.append((fname, line_of(s, m.start()), m.group(1).strip(), m.group(2).strip(), m.group(3).strip()))
        if fname.endswith('SRBuilderHelpers.swift'):
            for m in HEADING.finditer(s):
                out.append((fname, line_of(s, m.start()), m.group(1), 'LN', m.group(2)))
    return out


def check_coded_concepts(rep, parts, files, ctx):
    dk = ctx['dk']
    p16 = parts[16]
    dcm, cids, srt = dk.dcm_codes(p16), dk.cid_index(p16), dk.srt_to_sct(p16)
    matched, wrong, extra, legacy = 0, [], [], []
    seen = set()
    for fname, line, value, scheme, meaning in concept_literals(files):
        key = (fname, value, scheme, meaning)
        if key in seen:
            continue
        seen.add(key)
        where = f'{os.path.basename(fname)}:{line}'
        if scheme == 'DCM':
            if value not in dcm:
                wrong.append(f'{where}: ({value}, DCM, "{meaning}") is not in PS3.16 Table D-1')
            elif meaning.lower() != dcm[value].lower() and meaning.lower() not in dk.cid_meanings(cids, 'DCM', value):
                wrong.append(f'{where}: ({value}, DCM, "{meaning}"): Table D-1 meaning is "{dcm[value]}"')
            else:
                matched += 1
        elif scheme == 'SRT':
            sct = srt.get(value)
            legacy.append(f'{where}: ({value}, SRT, "{meaning}")' + (f' -> (SCT, {sct[0]}, "{sct[1]}") per Table O-1' if sct else ': not in Table O-1'))
        elif scheme.startswith('99'):
            extra.append(f'{where}: ({value}, {scheme}, "{meaning}") private scheme (PS3.16 section 8)')
        else:
            hits = cids.get((scheme, value))
            if not hits:
                extra.append(f'{where}: ({value}, {scheme}, "{meaning}") appears in no CID table'
                             + (' (external terminology; not verifiable from NEMA text)' if scheme in ('SCT', 'RADLEX', 'LN', 'UCUM') else ''))
            elif meaning.lower() not in dk.cid_meanings(cids, scheme, value):
                wrong.append(f'{where}: ({value}, {scheme}, "{meaning}"): {hits[0][1]} meaning is "{hits[0][0]}"')
            else:
                matched += 1
    wrong, pending = split_pending(wrong)
    rep.check('PS3.16 Table D-1 / CID tables: G5 coded concept literals (value, scheme, meaning; UCUM/SCT meanings case-insensitive)',
              matched, wrong, extra=extra, pending=pending)
    rep.check('PS3.16 Table 8-1 / O-1: no SRT-style SNOMED codes left in G5 (2026a uses SCT concept ids)', 0, legacy)


def check_coding_schemes(rep, parts, files, ctx):
    dw = ctx['dw']
    std = {}
    for row in dw.table_rows(parts[16], '8-1'):
        if len(row) >= 3 and row[0]:
            std[row[0].strip()] = row[2].strip()
    used = set(scheme for _, _, _, scheme, _ in concept_literals(files))
    srm = src(files, 'StructuredReportModel.swift')
    used |= set(ctx['dk'].active_string_cases(srm, 'CodingSchemeDesignator'))
    wrong = [f'designator "{d}" is not in PS3.16 Table 8-1 and is not a private "99…" scheme' for d in sorted(used)
             if d not in std and not d.startswith('99')]
    matched = len([d for d in used if d in std])
    # display names: TerminologyHelpers.schemeDisplayName and CodingSchemeDesignator.displayName
    names = {}
    th = src(files, 'TerminologyHelpers.swift')
    for m in re.finditer(r'case\s+"([A-Z0-9]+)":\s*return\s+"([^"]+)"', block(th, r'func schemeDisplayName\([^)]*\)[^{]*\{', 'schemeDisplayName')):
        names[('TerminologyHelpers', m.group(1))] = m.group(2)
    cases = dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', dw.enum_body(srm, 'CodingSchemeDesignator')))
    for m in re.finditer(r'case\s+\.(\w+):\s*return\s+"([^"]+)"', block(srm, r'var displayName: String \{', 'CodingSchemeDesignator.displayName')):
        if m.group(1) in cases:
            names[('CodingSchemeDesignator', cases[m.group(1)])] = m.group(2)
    for (who, d), name in sorted(names.items()):
        if d in std and name != std[d]:
            wrong.append(f'{who}: "{d}" is shown as "{name}", PS3.16 Table 8-1 Coding Scheme Name is "{std[d]}"')
        elif d in std:
            matched += 1
    rep.check(f'PS3.16 Table 8-1: {len(used)} designators used in G5 are registered; {len(names)} display names are the Table 8-1 names',
              matched, wrong)


# --- PS3.3 SR enums ---------------------------------------------------------------------------------------

def enum_vs_terms(rep, dk, label, enum, fname, code, terms, kind='Enumerated Values', missing_fail=True):
    std = set(terms)
    wrong = [f'{enum}: "{v}" is not a term of {label}' for v in code if v not in std]
    missing = [f'{enum}: "{t}" ({kind} of {label}) not carried' for t in terms if t not in set(code)]
    wrong, pending = split_pending(wrong)
    missing, pending2 = split_pending(missing)
    rep.check(f'PS3.3 {label} {kind}: {enum} ({fname})', len(set(code) & std), wrong, missing=missing, pending=pending + pending2,
              fail_on_missing=missing_fail)


def check_sr_enums(rep, parts, files, ctx):
    dk, dw = ctx['dk'], ctx['dw']
    p3 = parts[3]
    s = src(files, 'StructuredReportModel.swift')
    vt = [r[0].strip() for r in dw.table_rows(p3, 'C.17.3-7') if r and r[0].strip().isupper()]
    enum_vs_terms(rep, dk, 'Table C.17.3-7', 'ContentItemValueType', 'StructuredReportModel.swift', dk.active_string_cases(s, 'ContentItemValueType'), vt, 'Value Types')
    rt = [r[0].strip() for r in dw.table_rows(p3, 'C.17.3-8') if r and r[0].strip().isupper()]
    enum_vs_terms(rep, dk, 'Table C.17.3-8', 'SRRelationshipType', 'StructuredReportModel.swift', dk.active_string_cases(s, 'SRRelationshipType'), rt, 'Relationship Types')
    lab, kind, terms = dk.attribute_terms(p3, 'Continuity of Content', None)
    enum_vs_terms(rep, dk, f'{lab or "C.18.8-1"} Continuity of Content', 'ContinuityOfContent', 'StructuredReportModel.swift', dk.active_string_cases(s, 'ContinuityOfContent'), terms)
    for enum, sect in (('SpatialCoordGraphicType', 'sect_C.18.6.1.2'), ('SpatialCoord3DGraphicType', 'sect_C.18.9.1.2'), ('TemporalRangeType', 'sect_C.18.7.1.1')):
        terms = dk.section_terms(p3, sect)
        if not terms:
            rep.check(f'{enum}: {sect} has no term list in the 2026a text', 0, [f'{sect} not found'])
            continue
        enum_vs_terms(rep, dk, sect[5:], enum, 'StructuredReportModel.swift', dk.active_string_cases(s, enum), terms)
    # SRTreeHelpers switches must cover the model enums (compile-time exhaustive); report the value-type set it names
    tree = src(files, 'SRTreeHelpers.swift')
    named = set(re.findall(r'case\s+\.(\w+)', tree))
    model = set(re.findall(r'case\s+(\w+)\s*=\s*"', dw.enum_body(s, 'ContentItemValueType')))
    rep.check('SRTreeHelpers names every ContentItemValueType case of the model (display mapping is exhaustive)',
              len(model & named), [f'SRTreeHelpers has no case for .{c}' for c in sorted(model - named)])


# --- PS3.6 Table A-1: SOP Classes -------------------------------------------------------------------------

def a1(parts, ctx):
    return {r[0].strip(): r[1].strip() for r in ctx['dw'].table_rows(parts[6], 'A-1') if len(r) >= 2}


def check_sop_classes(rep, parts, files, ctx):
    names = a1(parts, ctx)
    dw = ctx['dw']
    matched, wrong, extra = 0, [], []
    srm = src(files, 'StructuredReportModel.swift')
    for case, uid in re.findall(r'case\s+\.(\w+):\s*return\s+"(1\.2\.840\.10008[\d.]+)"', block(srm, r'var sopClassUID: String \{', 'SRDocumentType.sopClassUID')):
        if uid not in names:
            wrong.append(f'SRDocumentType.{case}: {uid} is not in PS3.6 Table A-1')
        elif 'SR Storage' not in names[uid] and 'Key Object Selection Document Storage' != names[uid]:
            wrong.append(f'SRDocumentType.{case}: {uid} is "{names[uid]}", not an SR Storage SOP Class')
        else:
            matched += 1
            extra.append(f'SRDocumentType.{case} -> {names[uid]}')
    spm = src(files, 'SpecializedModalityModel.swift')
    for case, uid in re.findall(r'case\s+\.(\w+):\s*return\s+"(1\.2\.840\.10008[\d.]+)"', block(spm, r'public var sopClassUID: String \{', 'SecondaryCaptureDisplayType.sopClassUID')):
        if uid not in names or 'Secondary Capture Image Storage' not in names[uid]:
            wrong.append(f'SecondaryCaptureDisplayType.{case}: {uid} is not a Table A-1 Secondary Capture Image Storage UID')
        else:
            matched += 1
    rep.check('PS3.6 Table A-1: SRDocumentType and SecondaryCaptureDisplayType SOP Class UIDs are registered Storage SOP Classes',
              matched, wrong, extra=extra)
    # Waveform Storage SOP Classes: every current 1.2.840.10008.5.1.4.1.1.9.* "… Waveform Storage" row, names minus the suffix
    wf = src(files, 'WaveformHelpers.swift')
    ours = {m.group(1): m.group(2) for m in re.finditer(r'\("(1\.2\.840\.10008[\d.]+)",\s*"([^"]+)",\s*\.\w+\)', block(wf, r'waveformSOPClasses[^=]*=\s*\[', 'waveformSOPClasses'))}
    std = {u: n for u, n in names.items() if u.startswith('1.2.840.10008.5.1.4.1.1.9.') and n.endswith('Waveform Storage') and 'Retired' not in n}
    wrong = [f'WaveformHelpers: {u} "{n}" is not a Table A-1 Waveform Storage row' for u, n in ours.items() if u not in std]
    wrong += [f'WaveformHelpers: {u} shown as "{n}", Table A-1 name is "{std[u]}"' for u, n in ours.items() if u in std and n + ' Waveform Storage' != std[u]]
    missing = [f'Table A-1 {u} "{n}" not in WaveformHelpers.waveformSOPClasses' for u, n in sorted(std.items()) if u not in ours]
    rep.check(f'PS3.6 Table A-1: the {len(std)} Waveform Storage SOP Classes and their names (minus " Waveform Storage") in WaveformHelpers',
              len([u for u in ours if u in std and ours[u] + ' Waveform Storage' == std[u]]), wrong, missing)


# --- PS3.3 RT / SEG / HP terms ----------------------------------------------------------------------------

def check_rt_seg_terms(rep, parts, files, ctx):
    dk = ctx['dk']
    p3 = parts[3]
    s = src(files, 'SpecializedModalityModel.swift')
    for enum, attr, label in (('RTROIType', 'RT ROI Interpreted Type', None), ('RTDoseUnits', 'Dose Units', 'C.8-39'),
                              ('RTRadiationType', 'Radiation Type', 'C.8-50'), ('SegmentAlgorithmType', 'Segment Algorithm Type', None)):
        lab, kind, terms = dk.attribute_terms(p3, attr, label)
        if not terms:
            rep.check(f'{enum} vs "{attr}": no term list found in the 2026a text', 0, [f'{attr} not found'])
            continue
        enum_vs_terms(rep, dk, f'{lab} "{attr}"', enum, 'SpecializedModalityModel.swift', dk.active_string_cases(s, enum), terms,
                      kind or 'Defined Terms', missing_fail=False)
    # Segmentation Type is not modelled in Studio (SegmentOverlay carries free strings); any literal must be a term
    lab, kind, terms = dk.attribute_terms(p3, 'Segmentation Type', 'C.8.20-2')
    seg = src(files, 'SegmentationHelpers.swift')
    lits = [v for v in set(re.findall(r'"([A-Z_]{4,})"', seg)) if v in ('BINARY', 'FRACTIONAL', 'LABELMAP', 'HEIGHTMAP') or v in terms]
    rep.check(f'PS3.3 {lab} Segmentation Type: literals in SegmentationHelpers ({len(lits)}) are terms', len([v for v in lits if v in terms]),
              [f'SegmentationHelpers: "{v}" is not a Segmentation Type term' for v in lits if v not in terms])


def check_hanging_protocol(rep, parts, files, ctx):
    dk = ctx['dk']
    p3 = parts[3]
    hp = src(files, 'HangingProtocolModel.swift')
    lab, kind, terms = dk.attribute_terms(p3, 'Sorting Direction', None)
    enum_vs_terms(rep, dk, f'{lab} "Sorting Direction"', 'ImageSortDirection', 'HangingProtocolModel.swift', dk.active_string_cases(hp, 'ImageSortDirection'), terms)
    mods = set(dk.section_terms(p3, 'sect_C.7.3.1.1.1'))
    helpers = src(files, 'HangingProtocolHelpers.swift')
    found = re.findall(r'modality:\s*"([A-Z0-9]+)"', helpers)
    wrong = [f'HangingProtocolHelpers: modality "{m}" is not a C.7.3.1.1.1 Defined Term' for m in set(found) if m not in mods]
    rep.check(f'PS3.3 C.7.3.1.1.1: the {len(set(found))} modality values of the built-in hanging protocols are Defined Terms',
              len(set(found)) - len(wrong), wrong)


# --- PS3.3 A.45: Encapsulated Document MIME types ------------------------------------------------------------

def check_mime_types(rep, parts, files, ctx):
    p3 = parts[3]
    # the MIME Type of Encapsulated Document Enumerated Values are variablelist terms under the Encapsulated PDF / CDA
    # IODs (A.45.1, A.45.2) and the Encapsulated STL / OBJ / MTL IODs (A.85.1 - A.85.3 in 2026a)
    std = set()
    for label in ('A.45', 'A.85'):
        sec = section_by_label(p3, label)
        for term in (sec.iter(D + 'term') if sec is not None else ()):
            std |= set(re.findall(r'\b(?:application|text|model)/[A-Za-z0-9.+-]+', ''.join(term.itertext())))
    spm = src(files, 'SpecializedModalityModel.swift')
    ours = re.findall(r'case\s+\.(\w+):\s*return\s+"([a-z]+/[A-Za-z0-9.+-]+)"', block(spm, r'public var mimeType: String \{', 'EncapsulatedDocumentType.mimeType'))
    wrong = [f'EncapsulatedDocumentType.{c}.mimeType "{m}" is not an A.45 / A.85 MIME Type Enumerated Value (case matters: {sorted(std)})' for c, m in ours if m not in std and c != 'unknown']
    helpers = src(files, 'EncapsulatedDocumentHelpers.swift')
    accepted = set(re.findall(r'"((?:application|text|model)/[A-Za-z0-9.+-]+)"', helpers))
    extra = [f'EncapsulatedDocumentHelpers accepts "{m}" on input (not an A.45 / A.85 value)' for m in sorted(accepted) if m not in std] + [f'EncapsulatedDocumentType.unknown -> "{m}" (app fallback)' for c, m in ours if c == 'unknown']
    rep.check(f'PS3.3 A.45.1 / A.45.2 / A.85.1-A.85.3: EncapsulatedDocumentType.mimeType values ({len(ours)}) are MIME Type Enumerated Values ({len(std)} in the text; unknown -> octet-stream is the app fallback)',
              len(ours) - len(wrong), wrong, extra=extra)


# --- PS3.6 Table 6-1: calibration attribute names ------------------------------------------------------------

def check_calibration_tags(rep, parts, files, ctx):
    std = {}
    for r in ctx['dw'].table_rows(parts[6], '6-1'):
        if len(r) >= 2 and r[0].startswith('('):
            std[r[0].strip('()').replace(',', '').upper()] = r[1].strip()
    cal = src(files, 'CalibrationHelpers.swift')
    flat = re.sub(r'\n\s*///\s*', ' ', cal)   # doc comments wrap attribute names across lines
    found = re.findall(r'([A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)*) \(([0-9A-Fa-f]{4}),([0-9A-Fa-f]{4})\)', flat)
    matched, wrong = 0, []
    for name, g, e in set(found):
        tag = (g + e).upper()
        if tag not in std:
            wrong.append(f'CalibrationHelpers: ({g},{e}) is not in PS3.6 Table 6-1')
        elif std[tag] != name:
            wrong.append(f'CalibrationHelpers: ({g},{e}) is named "{name}", Table 6-1 name is "{std[tag]}"')
        else:
            matched += 1
    rep.check(f'PS3.6 Table 6-1: the {len(set(found))} (name, tag) pairs CalibrationHelpers documents', matched, wrong)


# --- PS3.16 CID 7460 / 7461 / 7183: UCUM unit codes for measurements -----------------------------------------

def check_measurement_units(rep, parts, files, ctx):
    dk = ctx['dk']
    p16 = parts[16]
    codes = {cid: {r[1] for r in dk.cid_rows(p16, f'CID {cid}')} for cid in (7460, 7461, 7183)}
    matched, wrong, extra = 0, [], []
    roi = src(files, 'ROIHelpers.swift')
    for unit, code in re.findall(r'case\s+\.(\w+):\s*return\s+"(\w+)"', block(roi, r'func ucumAreaCode\([^)]*\)[^{]*\{', 'ucumAreaCode')):
        if code in codes[7461]:
            matched += 1
        else:
            wrong.append(f'ROIHelpers.ucumAreaCode(.{unit}) = "{code}" is not a CID 7461 code')
    mp = src(files, 'MeasurementPersistenceHelpers.swift')
    for const, code, cid in (('ucumMM', None, 7460), ('ucumMM2', None, 7461), ('ucumDegrees', None, 7183)):
        m = re.search(r'static let ' + const + r'\s*=\s*"([^"]+)"', mp)
        if not m or m.group(1) not in codes[cid]:
            wrong.append(f'MeasurementPersistenceHelpers.{const} = "{m.group(1) if m else "?"}" is not a CID {cid} code')
        else:
            matched += 1
    mm = ctx['studio_files']().get('DICOMStudio/Models/MeasurementModel.swift', '')
    for v in dk.active_string_cases(mm, 'MeasurementUnit'):
        if v in codes[7460]:
            matched += 1
        else:
            extra.append(f'MeasurementUnit: "{v}" is not a CID 7460 code (printed as a symbol only)')
    # P-STUDIO-MEASURE-UM: micrometers = "um" (CID 7460 "micrometer"), area "um2" (CID 7461 "square micrometer")
    meanings = {cid: {r[1]: r[2] for r in dk.cid_rows(p16, f'CID {cid}')} for cid in (7460, 7461)}
    if 'um' not in dk.active_string_cases(mm, 'MeasurementUnit') or meanings[7460].get('um', '').lower() != 'micrometer':
        wrong.append(f'MeasurementUnit must carry "um", the PS3.16 2026a CID 7460 micrometer code (P-STUDIO-MEASURE-UM; '
                     f'CID 7460 um = {meanings[7460].get("um")!r})')
    else:
        matched += 1
    if not re.search(r'case \.micrometers: return "um2"', roi) or meanings[7461].get('um2', '').lower() != 'square micrometer':
        wrong.append(f'ROIHelpers.ucumAreaCode(.micrometers) must be "um2", the CID 7461 square micrometer code (P-STUDIO-MEASURE-UM; '
                     f'CID 7461 um2 = {meanings[7461].get("um2")!r})')
    else:
        matched += 1
    rep.check('PS3.16 2026a CID 7460 / 7461 / 7183: UCUM codes used by ROIHelpers, MeasurementPersistenceHelpers and MeasurementUnit, '
              'micrometer um / um2 included (P-STUDIO-MEASURE-UM)', matched, wrong, extra=extra)


# --- security UI vs the DICOMKit engine and PS3.15 ---------------------------------------------------------

def check_security(rep, parts, files, ctx):
    dk, dw = ctx['dk'], ctx['dw']
    p15 = parts[15]
    # (a) the anonymization preview list is exactly what the engine's basic profile removes
    core_tags, _ = dk.tag_constants(os.path.join(ctx['sources'], 'DICOMCore'), {})
    engine = dw.read(os.path.join(ctx['sources'], 'DICOMKit', 'Anonymization', 'Anonymizer.swift'))
    basic_kw = re.findall(r'\.(\w+)', block(engine, r'var basicProfileTags: Set<Tag> \{\s*Set\(\[', 'basicProfileTags'))
    trial_kw = re.findall(r'\.(\w+)', block(engine, r'var clinicalTrialProfileTags: Set<Tag> \{\s*basicProfileTags\.union\(\[', 'clinicalTrialProfileTags'))
    basic = {core_tags[k] for k in basic_kw if k in core_tags}
    trial = basic | {core_tags[k] for k in trial_kw if k in core_tags}
    unresolved = [k for k in basic_kw + trial_kw if k not in core_tags]
    helpers = src(files, 'SecurityHelpers.swift')
    ui_basic = {g + e for g, e in re.findall(r'\("([0-9A-F]{4}),([0-9A-F]{4})",\s*"[^"]+"\)', block(helpers, r'basicProfileTags: \[\(tag: String, name: String\)\] = \[', 'basicProfileTags'))}
    ui_dates = {g + e for g, e in re.findall(r'\("([0-9A-F]{4}),([0-9A-F]{4})",\s*"[^"]+"\)', block(helpers, r'clinicalTrialDateTags: \[\(tag: String, name: String\)\] = \[', 'clinicalTrialDateTags'))}
    wrong = [f'SecurityHelpers.basicProfileTags lists ({t[:4]},{t[4:]}) which DICOMKit Anonymizer .basic does not remove' for t in sorted(ui_basic - basic)]
    missing = [f'DICOMKit Anonymizer .basic removes ({t[:4]},{t[4:]}), absent from SecurityHelpers.basicProfileTags' for t in sorted(basic - ui_basic)]
    wrong += [f'SecurityHelpers clinical-trial list ({t[:4]},{t[4:]}) not removed by Anonymizer .clinicalTrial' for t in sorted((ui_basic | ui_dates) - trial)]
    missing += [f'Anonymizer .clinicalTrial removes ({t[:4]},{t[4:]}), absent from the SecurityHelpers lists' for t in sorted(trial - (ui_basic | ui_dates))]
    wrong += [f'engine keyword .{k} has no DICOMCore Tag constant' for k in unresolved]
    rep.check(f'SecurityHelpers anonymization preview lists ({len(ui_basic)} basic + {len(ui_dates)} dates) equal the DICOMKit Anonymizer '
              f'basic ({len(basic)}) / clinicalTrial ({len(trial)}) tag sets', len(ui_basic & basic) + len(ui_dates & (trial - basic)), wrong, missing)
    # tag names in the lists are Table 6-1 names
    std = {}
    for r in dw.table_rows(parts[6], '6-1'):
        if len(r) >= 2 and r[0].startswith('('):
            std[r[0].strip('()').replace(',', '').upper()] = r[1].strip()
    pairs = re.findall(r'\("([0-9A-F]{4}),([0-9A-F]{4})",\s*"([^"]+)"\)', helpers)
    wrong = [f'SecurityHelpers: ({g},{e}) is named "{n}", PS3.6 Table 6-1 name is "{std.get(g + e)}"' for g, e, n in pairs if std.get(g + e) != n]
    rep.check(f'PS3.6 Table 6-1: the {len(pairs)} (tag, name) pairs of the SecurityHelpers lists carry the Table 6-1 names', len(pairs) - len(wrong), wrong)
    # (b) TLS: PS3.15 2026a B.12 (BCP 195, RFC 8996) — TLS 1.0 / 1.1 are prohibited, 1.2 shall be supported
    model = src(files, 'SecurityModel.swift')
    b12 = section_text(p15, 'B.12')
    allowed = set(re.findall(r'TLS 1\.[23]', b12))
    versions = re.findall(r'"(TLS 1\.\d)"', block(model, r'var minimumTLSVersion: String \{', 'minimumTLSVersion'))
    wrong = [f'SecurityTLSMode.minimumTLSVersion "{v}": PS3.15 2026a B.12 (RFC 8996) allows only {sorted(allowed)}' for v in versions if v not in allowed]
    rep.check(f'PS3.15 B.12: SecurityTLSMode minimum TLS versions ({len(versions)}) are TLS 1.2 / 1.3', len(versions) - len(wrong), wrong)
    # cipher suites shown are B.13 suites
    b13 = set(re.findall(r'TLS_[A-Z0-9_]+', section_text(p15, 'B.13')))
    suites = re.findall(r'"(TLS_[A-Z0-9_]+)"', helpers)
    wrong = [f'SecurityTLSHelpers.strongCipherSuites "{s}" is not a PS3.15 B.13 cipher suite' for s in suites if s not in b13]
    rep.check(f'PS3.15 B.13: the {len(suites)} cipher suites SecurityTLSHelpers shows are B.13 suites ({len(b13)} listed)', len(suites) - len(wrong), wrong)
    # (c) no G5 file cites a PS3.15 Annex B profile that 2026a marks "Retired"
    wrong, matched = [], 0
    for fname, s in files.items():
        for m in re.finditer(r'PS3\.15[^\n]{0,30}?\b(B\.\d+)\b', s):
            txt = section_text(p15, m.group(1))
            if txt.startswith('Retired'):
                wrong.append(f'{os.path.basename(fname)}:{line_of(s, m.start())}: PS3.15 {m.group(1)} is "{txt[:30]}" in 2026a')
            else:
                matched += 1
    rep.check('PS3.15 Annex B: G5 files cite no TLS profile that 2026a retires (B.1, B.2, B.3, B.9, B.10, B.11)', matched, wrong)


def check_security_ps315(rep, parts, files, ctx):
    """P-STUDIO-ANON-PS315: the Security panel's default profile is the PS3.15 2026a E.1 Basic Application Level
    Confidentiality Profile, run through StudioAnonPS315.deidentify (DICOMKit Anonymizer.deidentify, as dicom-anon
    --profile ps315); the legacy lists are labelled not PS3.15; the 10 E.3 Option toggles carry the 2026a names."""
    dw, nd = ctx['dw'], ctx['nd']
    p15 = parts[15]
    wrong, matched = [], 0
    e1 = nd.norm(' '.join(dw.section_by_id(p15, 'sect_E.1').itertext()))
    model = src(files, 'SecurityModel.swift')
    support = src(files, 'AnonPS315Support.swift')
    vm = ctx['studio_files']().get('DICOMStudio/ViewModels/SecurityViewModel.swift', '')
    body = ctx['dw'].enum_body(model, 'AnonymizationProfile')
    names = dict(re.findall(r'case \.(\w+):\s*return "([^"]*)"', block(body, r'public var displayName: String \{', 'AnonymizationProfile.displayName')))
    ps315_name = names.get('ps315', '')
    if 'case ps315' not in body or not ps315_name.startswith('PS3.15 ') or ps315_name[len('PS3.15 '):] not in e1:
        wrong.append(f'AnonymizationProfile.ps315.displayName {ps315_name!r} must be "PS3.15 " + the E.1 profile name (Basic Application Level Confidentiality Profile)')
    else:
        matched += 1
    for c, n in names.items():
        if c != 'ps315' and 'not PS3.15' not in n:
            wrong.append(f'AnonymizationProfile.{c}.displayName {n!r} must be labelled "not PS3.15"')
        elif c != 'ps315':
            matched += 1
    if not re.search(r'builderProfiles: \[AnonymizationProfile\] = \[\.ps315\b', body):
        wrong.append('AnonymizationProfile.builderProfiles must list .ps315 first (the default)')
    else:
        matched += 1
    for decl in ('public var selectedProfile: AnonymizationProfile = .ps315', 'public var anonProfile: AnonymizationProfile = .ps315'):
        if decl in vm:
            matched += 1
        else:
            wrong.append(f'SecurityViewModel must declare `{decl}` (the panel default is the PS3.15 Basic Profile)')
    if re.search(r'if isPS315 \{\s*\(anonFile, anonResult\) = try StudioAnonPS315\.deidentify\(', vm) \
            and 'anonymizer.deidentify(file: dicomFile, options: options)' in block_or_empty(support, r'static func deidentify\([^{]*\{', 'StudioAnonPS315.deidentify'):
        matched += 1
    else:
        wrong.append('the Security panel must run .ps315 through StudioAnonPS315.deidentify -> DICOMKit Anonymizer.deidentify(file:options:)')
    # the 10 E.3 Option toggles: names are the E.3.3-E.3.5, E.3.7-E.3.11 section titles and the two E.3.6 Option names
    opts = re.findall(r'OptionToggle\(flag: "(--[a-z-]+)", name: "([^"]+)", section: "(E\.3\.\d+)"',
                      block_or_empty(support, r'static let securityPanelOptions: \[OptionToggle\] = \[', 'securityPanelOptions'))
    for flag, name, sec_id in opts:
        title = dw.section_title(p15, f'sect_{sec_id}') or ''
        text = nd.norm(' '.join(dw.section_by_id(p15, f'sect_{sec_id}').itertext())) if title else ''
        if name == title or (sec_id == 'E.3.6' and name in text):
            matched += 1
        else:
            wrong.append(f'securityPanelOptions {flag}: "{name}" is not the PS3.15 2026a {sec_id} Option name ({title!r})')
    if len(opts) != 10:
        wrong.append(f'securityPanelOptions lists {len(opts)} E.3 Options; expected the 10 of E.3.3-E.3.11')
    rep.check('PS3.15 2026a E.1 / E.3: Security panel default is the Basic Application Level Confidentiality Profile via '
              'StudioAnonPS315 -> Anonymizer.deidentify, legacy lists labelled not PS3.15, 10 E.3 Option names (P-STUDIO-ANON-PS315)',
              matched, wrong)


def check_citations(rep, parts, files, ctx):
    ctx['dk'].check_citations(rep, parts, files)


CHECKS = [
    ('G5 coded concepts', check_coded_concepts),
    ('G5 coding schemes', check_coding_schemes),
    ('G5 sr enums', check_sr_enums),
    ('G5 sop classes', check_sop_classes),
    ('G5 rt seg terms', check_rt_seg_terms),
    ('G5 hanging protocol', check_hanging_protocol),
    ('G5 mime types', check_mime_types),
    ('G5 calibration tags', check_calibration_tags),
    ('G5 measurement units', check_measurement_units),
    ('G5 security', check_security),
    ('G5 security ps315', check_security_ps315),
    ('G5 citations', check_citations),
]
