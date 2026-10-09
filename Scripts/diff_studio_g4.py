#!/usr/bin/env python3
"""DICOMStudio group G4 (file format, media, DICOMDIR, import, library and metadata models) row-by-row checks.

Loaded by diff_studio.py (``diff_studio_g4*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
Each check extracts the values the Swift source carries by regex and compares them with the frozen 2026a DocBook:

  * DICOMDIRParser.knownRecordTypes            vs PS3.3 Table F.4-1 (the Directory Record Types; F.3-3 Enumerated Values)
  * VRDescriptions.fullName / category          vs PS3.5 Table 6.2-1 (34 VRs, "VR Name" column verbatim)
  * DICOMValueParser.characterSetDescription    vs PS3.3 Tables C.12-2 … C.12-5 (Specific Character Set Defined Terms)
  * PrivateTagIdentifier reserved odd groups    vs PS3.5 7.8.1 text
  * transfer-syntax names shown by Studio       vs PS3.6 Table A-1 (DataExchangeHelpers, TransferSyntaxDescriptions
                                                 must take them from DICOMCore `TransferSyntax.displayName`)
  * modality defaults ("OT", …)                 vs PS3.3 C.7.3.1.1.1 Defined Terms
  * File Meta tags read by DICOMFileService     vs PS3.10 Table 7.1-1
  * STD-* media profile identifiers (if any)    vs PS3.11 Tables A.1-1 … N.1-1
  * DICOMDIREntry / DirectoryRecord keys        vs PS3.3 Tables F.5-1 … F.5-3 and F.3-3
"""
import os
import re

PENDING_API_APPROVAL = {}
DEFERRED = {}
EXEMPT = {}

HERE = os.path.dirname(os.path.abspath(__file__))


def src(files, suffix):
    for name, s in files.items():
        if name.endswith(suffix):
            return s
    raise KeyError(suffix)


def swift_string_set(body):
    return re.findall(r'"([^"\n]+)"', body)


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


# --- PS3.3 Table F.4-1: DICOMDIR record types ---------------------------------------------------------

def check_dicomdir_record_types(rep, parts, files, ctx):
    dw = ctx['dw']
    std = []
    for row in dw.table_rows(parts[3], 'F.4-1'):
        if row and row[0] and not row[0].startswith('('):
            std.append(row[0].strip())
    body = block(src(files, 'DICOMDIRParser.swift'), r'knownRecordTypes:\s*Set<String>\s*=\s*\[', 'knownRecordTypes')
    ours = set(swift_string_set(body))
    retired = {'HL7 STRUC DOC'}   # PS3.3 F.5.33, retired PS3.3-2018b; kept for legacy file-sets
    missing = [t for t in std if t not in ours]
    extra = [t for t in sorted(ours - set(std)) if t not in retired]
    matched = len([t for t in std if t in ours])
    wrong = [f'DICOMDIRParser.knownRecordTypes carries "{t}", not a Table F.4-1 record type' for t in extra]
    rep.check('PS3.3 Table F.4-1: DICOMDIRParser.knownRecordTypes is the set of Directory Record Types', matched, wrong,
              [f'Table F.4-1 "{t}" missing from knownRecordTypes' for t in missing],
              [f'retired type kept: {t}' for t in sorted(ours & retired)])
    # DICOMCore carries the same current values (cross-check, so a Studio/Core disagreement is visible)
    core = dw.read(os.path.join(ctx['sources'], 'DICOMCore', 'DirectoryRecord.swift'))
    core_values = set(re.findall(r'case\s+`?\w+`?\s*=\s*"([^"]+)"', core))
    core_missing = [t for t in std if t not in core_values]
    rep.check('PS3.3 Table F.4-1: DICOMCore DirectoryRecordType carries every current record type (cross-check)',
              len(std) - len(core_missing), [], [f'DICOMCore lacks {t}' for t in core_missing])


# --- PS3.3 Tables F.5-1..F.5-3 / F.3-3: record keys the Studio structs carry -------------------------------

def check_dicomdir_record_keys(rep, parts, files, ctx):
    dw = ctx['dw']
    keys = {}
    for label in ('F.5-1', 'F.5-2', 'F.5-3', 'F.3-3'):
        for row in dw.table_rows(parts[3], label):
            if len(row) >= 2 and re.match(r'\(\w{4},\w{4}\)', row[1]):
                keys[row[0].lstrip('>').strip()] = (row[1], label)
    carried = {
        'patientName': "Patient's Name", 'patientID': 'Patient ID', 'studyInstanceUID': 'Study Instance UID',
        'studyDate': 'Study Date', 'studyDescription': 'Study Description', 'seriesInstanceUID': 'Series Instance UID',
        'modality': 'Modality', 'sopInstanceUID': 'Referenced SOP Instance UID in File',
    }
    parser = src(files, 'DICOMDIRParser.swift')
    entry = src(files, 'DataExchangeModel.swift')
    matched, wrong = 0, []
    for field, name in carried.items():
        if not re.search(r'public (let|var) ' + field + r'\b', parser + entry):
            wrong.append(f'field {field} not found in DICOMDIRParser.DirectoryRecord / DICOMDIREntry')
        elif name in keys:
            matched += 1
        else:
            wrong.append(f'{field}: "{name}" is not a key of Tables F.5-1/F.5-2/F.5-3 or F.3-3')
    rep.check('PS3.3 Tables F.5-1..F.5-3, F.3-3: DICOMDIR record fields Studio carries are record keys', matched, wrong)


# --- PS3.5 Table 6.2-1: VR set and names -------------------------------------------------------------

def table_621(parts, ctx):
    out = {}
    for row in ctx['dw'].table_rows(parts[5], '6.2-1'):
        if row and re.match(r'^[A-Z]{2}\b', row[0]):
            code, name = row[0].split('|', 1) if '|' in row[0] else (row[0][:2], row[0][2:])
            out[code.strip()] = name.strip()
    return out


def check_vr_names(rep, parts, files, ctx):
    std = table_621(parts, ctx)
    s = src(files, 'VRBadge.swift')
    body = block(s, r'func fullName\(for vr: String\) -> String \{', 'fullName')
    ours = dict(re.findall(r'case "([A-Z]{2})": return "([^"]+)"', body))
    wrong = [f'{vr}: "{ours[vr]}" for Table 6.2-1 "{std[vr]}"' for vr in std if vr in ours and ours[vr] != std[vr]]
    missing = [f'{vr} ({std[vr]}) has no fullName' for vr in std if vr not in ours]
    extra = [f'{vr} is not in Table 6.2-1' for vr in ours if vr not in std]
    rep.check('PS3.5 Table 6.2-1: VRDescriptions.fullName — 34 VRs, "VR Name" verbatim',
              len([vr for vr in std if ours.get(vr) == std[vr]]), wrong + extra, missing)
    cat = block(s, r'func category\(for vr: String\) -> String \{', 'category')
    covered = set(re.findall(r'"([A-Z]{2})"', cat))
    rep.check('PS3.5 Table 6.2-1: VRDescriptions.category covers every VR', len([v for v in std if v in covered]),
              [], [f'{vr} falls to the "other" category' for vr in std if vr not in covered])
    # DICOMValueParser dispatches on VR codes that exist
    vp = src(files, 'DICOMValueParser.swift')
    fmt = block(vp, r'switch vr\.uppercased\(\) \{', 'format switch')
    used = set(re.findall(r'case "([A-Z]{2})"', fmt))
    rep.check('PS3.5 Table 6.2-1: DICOMValueParser.format dispatches on real VR codes', len(used & set(std)),
              [f'{vr} is not a VR' for vr in used - set(std)])


# --- PS3.3 Tables C.12-2..C.12-5: Specific Character Set Defined Terms -------------------------------------

def check_character_sets(rep, parts, files, ctx):
    dw = ctx['dw']
    std = set()
    for label in ('C.12-2', 'C.12-3', 'C.12-4', 'C.12-5'):
        for row in dw.table_rows(parts[3], label):
            for cell in row[:2]:
                if re.match(r'^(ISO_IR \d+|ISO 2022 IR \d+|GB18030|GBK)$', cell.strip()):
                    std.add(cell.strip())
    body = block(src(files, 'DICOMValueParser.swift'), r'let mapping: \[String: String\] = \[', 'characterSet mapping')
    ours = set(k for k, _ in re.findall(r'"([^"]*)":\s*"([^"]*)"', body)) - {''}
    wrong = [f'"{t}" is not a Defined Term of Tables C.12-2..C.12-5' for t in sorted(ours - std)]
    missing = [f'Defined Term {t} falls through to the raw value' for t in sorted(std - ours)]
    rep.check('PS3.3 Tables C.12-2..C.12-5: DICOMValueParser.characterSetDescription keys are the Defined Terms',
              len(ours & std), wrong, missing, fail_on_missing=False)


# --- PS3.5 7.8.1: private groups --------------------------------------------------------------------------

def check_private_groups(rep, parts, files, ctx):
    text = ctx['nd'].norm(' '.join(ctx['dw'].section_by_id(parts[5], 'sect_7.8.1').itertext()))
    m = re.search(r'Elements with Tags ((?:\(\w{4},xxxx\)(?:, | and )?)+) shall not be used', text)
    if not m:
        raise SystemExit('PS3.5 7.8.1: "Elements with Tags (0001,xxxx), … shall not be used" not found; re-read the clause')
    std = set(int(g, 16) for g in re.findall(r'\((\w{4}),xxxx\)', m.group(1)))
    s = src(files, 'PrivateTagIdentifier.swift')
    body = block(s, r'reservedOddGroups:\s*Set<UInt16>\s*=\s*\[', 'reservedOddGroups')
    ours = set(int(g, 16) for g in re.findall(r'0x([0-9A-Fa-f]{4})', body))
    wrong = [f'{g:04X} is excluded by Studio but not by 7.8.1' for g in sorted(ours - std)]
    missing = [f'7.8.1 excludes ({g:04X},eeee) but isPrivateGroup accepts it' for g in sorted(std - ours)]
    if 'reservedOddGroups.contains(group)' not in s:
        wrong.append('isPrivateGroup does not consult reservedOddGroups')
    rep.check('PS3.5 7.8.1: PrivateTagIdentifier excludes the reserved odd groups', len(ours & std), wrong, missing)
    creator = re.search(r'element >= 0x(\w{4}) && element <= 0x(\w{4})', s)
    ok = creator and creator.groups() == ('0010', '00FF')
    rep.check('PS3.5 7.8.1: Private Creator Data Elements are (gggg,0010-00FF)', 1 if ok else 0,
              [] if ok else ['isPrivateCreator element range is not 0010-00FF'])


# --- PS3.6 Table A-1: transfer-syntax names shown by Studio ---------------------------------------------------

def check_transfer_syntax_names(rep, parts, files, ctx):
    dw = ctx['dw']
    std = dw.uid_registry(parts[6])
    # Table A-1 columns: UID Value, UID Name, UID Keyword, UID Type, Part
    ts_rows = {row[0] for row in dw.table_rows(parts[6], 'A-1') if len(row) >= 4 and row[3].strip() == 'Transfer Syntax'}
    wrong, matched = [], 0
    # DataExchangeHelpers.wellKnownSyntaxes: displayName must come from DICOMCore (A-1 verbatim), uid must be a TS row
    body = block(src(files, 'DataExchangeHelpers.swift'), r'wellKnownSyntaxes: \[TransferSyntaxEntry\] = \[', 'wellKnownSyntaxes')
    for uid, name in re.findall(r'uid: "([\d.]+)",\s*displayName: ([^,\n]+),', body):
        if uid not in ts_rows:
            wrong.append(f'wellKnownSyntaxes: {uid} is not a Table A-1 Transfer Syntax')
        elif not re.match(r'TransferSyntax\.\w+\.displayName', name.strip()):
            wrong.append(f'wellKnownSyntaxes: {uid} displayName {name.strip()} is a literal, not DICOMCore TransferSyntax.displayName')
        else:
            matched += 1
    # TransferSyntaxDescriptions.describe must delegate to DICOMCore
    mv = src(files, 'MetadataViewModel.swift')
    desc = block(mv, r'enum TransferSyntaxDescriptions: Sendable \{', 'TransferSyntaxDescriptions')
    literal = re.findall(r'"(1\.2\.840\.10008[\d.]+)":\s*"([^"]+)"', desc)
    for uid, name in literal:
        a1 = std.get(uid, ['?'])[0]
        if dw.norm_name(a1) != dw.norm_name(name):
            wrong.append(f'TransferSyntaxDescriptions: "{name}" for {uid}; A-1 "{a1}"')
        else:
            matched += 1
    if 'TransferSyntax.from(uid:' in desc and '.displayName' in desc:
        matched += 1
    else:
        wrong.append('TransferSyntaxDescriptions.describe does not use DICOMCore TransferSyntax.displayName')
    rep.check('PS3.6 Table A-1: transfer-syntax names Studio shows (DataExchangeHelpers, TransferSyntaxDescriptions) '
              'are the A-1 "UID Name" via DICOMCore', matched, wrong)


# --- PS3.3 C.7.3.1.1.1: modality defaults ------------------------------------------------------------------

def check_modality_defaults(rep, parts, files, ctx):
    terms = set(ctx['dk'].section_terms(parts[3], 'sect_C.7.3.1.1.1'))
    if not terms:
        raise SystemExit('C.7.3.1.1.1 Defined Terms not found')
    found = []
    for name, s in files.items():
        for m in re.finditer(r'[mM]odality[A-Za-z]*(?::\s*String)?\s*=\s*"([A-Z0-9]{1,16})"', s):
            found.append((name, m.group(1)))
        for m in re.finditer(r'[mM]odality[A-Za-z]*(?::\s*String)?\s*=\s*Modality\.(\w+)\.rawValue', s):
            found.append((name, m.group(1).upper()))
    wrong = [f'{n}: default modality "{v}" is not a C.7.3.1.1.1 Defined Term' for n, v in found if v not in terms]
    rep.check('PS3.3 C.7.3.1.1.1: modality defaults in G4 (SeriesModel, DICOMFileService, DataExchangeViewModel) are Defined Terms',
              len(found) - len(wrong), wrong, extra=[f'{n}: {v}' for n, v in found])


# --- PS3.10 Table 7.1-1: File Meta elements read ------------------------------------------------------------

def check_file_meta(rep, parts, files, ctx):
    dw, dk = ctx['dw'], ctx['dk']
    std = {}
    for row in dw.table_rows(parts[10], '7.1-1'):
        if len(row) >= 2 and row[1].startswith('(0002'):
            std[row[1].strip('()').replace(',', '').upper()] = row[0]
    core, _ = dk.tag_constants(os.path.join(ctx['sources'], 'DICOMCore'), {})
    s = src(files, 'DICOMFileService.swift')
    used = set(re.findall(r'fmi\.string\(for: \.(\w+)\)', s))
    wrong, matched = [], 0
    for kw in sorted(used):
        tag = core.get(kw)
        if tag is None:
            wrong.append(f'.{kw}: no DICOMCore Tag constant')
        elif tag not in std:
            wrong.append(f'.{kw} ({tag}) is read from File Meta Information but is not in Table 7.1-1')
        else:
            matched += 1
    rep.check('PS3.10 Table 7.1-1: File Meta elements DICOMFileService reads from the FMI group', matched, wrong,
              extra=[f'.{kw}' for kw in sorted(used)])
    mdir = re.search(r'mediaStorageDirectoryUID = "([\d.]+)"', s)
    reg = dw.uid_registry(parts[6])
    ok = mdir and mdir.group(1) in reg and 'Media Storage Directory Storage' in reg[mdir.group(1)][0]
    rep.check('PS3.6 Table A-1: DICOMFileService.mediaStorageDirectoryUID is Media Storage Directory Storage',
              1 if ok else 0, [] if ok else [f'mediaStorageDirectoryUID {mdir and mdir.group(1)}'])


# --- PS3.11: media application profile identifiers -----------------------------------------------------------

def check_media_profiles(rep, parts, files, ctx):
    dw = ctx['dw']
    std, templates = set(), set()
    for lab, cap, t in parts[11].tables():
        if re.match(r'^[A-N]\.1-1$', lab):
            for row in parts[11].rows(t):
                for cell in row:
                    for ident in re.findall(r'STD-[A-Z0-9-]+(?:xxxx)?', cell):
                        (templates if ident.endswith('xxxx') else std).add(ident)   # Table C.1-1: STD-US-<class>-<SF|MF>-xxxx
    ours = []
    for name, s in files.items():
        for ident in re.findall(r'"(STD-[A-Za-z0-9-]+)"', s):
            ours.append((name, ident))
    wrong = [f'{n}: "{i}" is not a PS3.11 2026a profile identifier' for n, i in ours if i not in std]
    # the Studio UI offers profiles through DICOMCore DICOMDIRProfile; cross-check that registry (deprecated
    # placeholders such as STD-MAM-xxxx are documented there as non-standard and skipped)
    core = dw.read(os.path.join(ctx['sources'], 'DICOMCore', 'DICOMDirectory.swift'))
    core_ids = set()
    for m in re.finditer(r'DICOMDIRProfile\(unchecked: "(STD-[^"]+)"\)', core):
        if 'deprecated' not in core[max(0, m.start() - 250):m.start()]:
            core_ids.add(m.group(1))
    core_wrong = [f'DICOMCore DICOMDIRProfile "{i}" is not in PS3.11 2026a' for i in sorted(core_ids - std)]
    extra = [f'PS3.11 profile not in DICOMCore: {i}' for i in sorted(std - core_ids)]
    if templates and 'func ultrasound(' not in core:
        core_wrong.append('DICOMCore has no builder for the Table C.1-1 ultrasound identifiers')
    extra += [f'Table C.1-1 template {t} built by DICOMCore ultrasound(_:frames:media:)' for t in sorted(templates)]
    rep.check(f'PS3.11 Tables A.1-1..N.1-1 ({len(std)} fixed identifiers + {len(templates)} C.1-1 templates): STD-* literals '
              f'in G4 ({len(ours)}) and DICOMCore DICOMDIRProfile ({len(core_ids)}) are registered profiles',
              len(ours) - len(wrong) + len(core_ids & std), wrong + core_wrong, extra=extra)


CHECKS = [
    ('G4 dicomdir record types', check_dicomdir_record_types),
    ('G4 dicomdir record keys', check_dicomdir_record_keys),
    ('G4 vr names', check_vr_names),
    ('G4 character sets', check_character_sets),
    ('G4 private groups', check_private_groups),
    ('G4 transfer syntax names', check_transfer_syntax_names),
    ('G4 modality defaults', check_modality_defaults),
    ('G4 file meta', check_file_meta),
    ('G4 media profiles', check_media_profiles),
]
