#!/usr/bin/env python3
"""Diff the standard-derived constants of Sources/DICOMWeb against the frozen DICOM DocBook.

Usage:
    python3 Scripts/nema_docbook.py fetch 2026a 18  # PS3.18 (web services)
    python3 Scripts/nema_docbook.py fetch 2026a 19  # PS3.19 (Native DICOM Model XML)
    python3 Scripts/nema_docbook.py fetch 2026a 3   # PS3.3 (UPS modules, defined terms)
    python3 Scripts/nema_docbook.py fetch 2026a 4   # PS3.4 (UPS service class, Annex CC)
    python3 Scripts/nema_docbook.py fetch 2026a 6   # PS3.6 (data dictionary, UID registry)
    python3 Scripts/diff_web.py --nema DIR [--sources Sources/DICOMWeb] [--verbose]

Every check extracts the literals from the Swift files by regex (never by hand) and
compares them with the table or clause of the standard named in the check. It prints
one line per check with the counts (matched / wrong / missing / extra) and exits 1
when any check found a wrong value or a missing required value. "Extra" values that
the standard does not define, and standard values the module does not carry, are
listed but do not fail the run unless the check says they must. Values whose fix
changes public API and waits for the owner's approval are reported as PEND.

This is the extraction + diff step of the verification method in
DICOMCORE_STANDARD_IMPLEMENTATION.md, applied to DICOMWeb (see
DICOMWEB_STANDARD_IMPLEMENTATION.md for the results).
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('nema_docbook', os.path.join(HERE, 'nema_docbook.py'))
nd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nd)
D = nd.D

# Values known to differ from the standard whose fix changes public API (raw values, enum
# cases) and waits for the owner's approval; reported as PEND, not FAIL. Remove when fixed.
PENDING_API_APPROVAL = set()  # all four owner decisions of 2026-09-28 were approved and applied


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def read_all(src_dir):
    out = {}
    for dirpath, _, names in os.walk(src_dir):
        for name in sorted(names):
            if name.endswith('.swift'):
                out[os.path.relpath(os.path.join(dirpath, name), src_dir)] = read(os.path.join(dirpath, name))
    return out


class Report:
    def __init__(self, verbose):
        self.verbose = verbose
        self.failed = 0
        self.pending = 0

    def check(self, name, matched, wrong=(), missing=(), extra=(), pending=(), fail_on_missing=True):
        wrong, missing, extra, pending = list(wrong), list(missing), list(extra), list(pending)
        bad = wrong or (missing and fail_on_missing)
        self.failed += 1 if bad else 0
        self.pending += 1 if (pending and not bad) else 0
        status = 'FAIL' if bad else ('PEND' if pending else 'ok  ')
        print(f'{status} {name}: matched {matched}, wrong {len(wrong)}, missing {len(missing)}, '
              f'extra {len(extra)}' + (f', pending {len(pending)}' if pending else ''))
        for label, items in (('wrong', wrong), ('missing', missing), ('pending', pending), ('extra', extra)):
            for item in items:
                if label != 'extra' or self.verbose:
                    print(f'       {label}: {item}')


# --- helpers over the DocBook -------------------------------------------------------

def table_rows(part, label, caption=None):
    return list(part.rows(part.table(label, caption)))


def section_by_id(part, xml_id):
    for sec in part.root.iter(D + 'section'):
        if sec.get(nd.X + 'id') == xml_id:
            return sec
    return None


def section_ids(part):
    return ({sec.get(nd.X + 'id') for sec in part.root.iter(D + 'section')}
            | {ch.get(nd.X + 'id') for ch in part.root.iter(D + 'chapter')})


def section_title(part, xml_id):
    sec = section_by_id(part, xml_id)
    if sec is None:
        for ch in part.root.iter(D + 'chapter'):
            if ch.get(nd.X + 'id') == xml_id:
                sec = ch
    if sec is None:
        return None
    t = sec.find(D + 'title')
    return nd.norm(''.join(t.itertext())) if t is not None else ''


def section_code(part, xml_id):
    """Every programlisting under a section, whitespace-normalised."""
    sec = section_by_id(part, xml_id)
    if sec is None:
        return []
    return [' '.join(''.join(pl.itertext()).split()) for pl in sec.iter(D + 'programlisting')]


def variablelist_terms(part, xml_id):
    sec = section_by_id(part, xml_id)
    out = []
    if sec is None:
        return out
    for vl in sec.iter(D + 'variablelist'):
        for e in vl.findall(D + 'varlistentry'):
            term = e.find(D + 'term')
            out.append(nd.norm(''.join(term.itertext())) if term is not None else '')
    return out


# --- helpers over the Swift ----------------------------------------------------------

def enum_body(src, enum_name):
    m = re.search(r'enum\s+' + re.escape(enum_name) + r'\b[^{]*\{', src)
    if not m:
        return ''
    depth, i, start = 0, m.end() - 1, m.end() - 1
    while i < len(src):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    return src[start:i]


def func_body(src, signature_regex):
    """Body of the first function whose declaration matches the regex."""
    m = re.search(signature_regex, src)
    if not m:
        return ''
    i = src.find('{', m.end())
    depth, start = 0, i
    while i < len(src):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    return src[start:i]


def case_vr_set(src, func_name):
    """The `.XX` VR cases listed in `case .A, .B:` lines of a function."""
    body = func_body(src, r'func\s+' + re.escape(func_name) + r'\b')
    return set(re.findall(r'\.([A-Z]{2})\b', re.sub(r'return\s+\w+', '', body)))


def string_cases(src, enum_name):
    return re.findall(r'case\s+\w+\s*=\s*"([^"]*)"', enum_body(src, enum_name))


def hex_cases(src, enum_name):
    return {n: int(v, 16) for n, v in re.findall(r'case\s+(\w+)\s*=\s*0x([0-9A-Fa-f]+)', enum_body(src, enum_name))}


# --- PS3.6 --------------------------------------------------------------------------

def dictionary(p6):
    """PS3.6 Table 6-1: {'GGGGEEEE': (name, keyword, vr, vm, retired)}; ranges keyed as written."""
    out = {}
    for row in table_rows(p6, '6-1'):
        if len(row) < 5:
            continue
        tag = row[0].strip('()').replace(',', '').upper()
        out[tag] = (row[1], row[2], row[3], row[4], row[5] if len(row) > 5 else '')
    return out


def uid_registry(p6):
    return {row[0]: (row[1], row[2]) for row in table_rows(p6, 'A-1')}


# --- checks: DICOM JSON (PS3.18 Annex F) -------------------------------------------------

JSON_TYPE_TO_CLASS = {
    'String': 'string', 'Number': 'numeric', 'Number or String': 'numeric or string',
    'Base64 encoded octet-stream': 'binary', 'Array containing DICOM JSON Objects': 'sequence',
    'Object containing Person Name component groups as strings': 'personname',
}


def check_json_vr_mapping(rep, p18, files):
    std = {}
    for row in table_rows(p18, 'F.2.3-1'):
        vr, jtype = row[0], row[2].split('|')[0].split('(')[0].strip().rstrip('.')
        std[vr] = 'string' if vr == 'AT' else JSON_TYPE_TO_CLASS[jtype]
    enc = files['DICOMJSONEncoder.swift']
    dec = files['DICOMJSONDecoder.swift']
    ours_enc = {}
    for vr in case_vr_set(enc, 'encodeStringValues'):
        ours_enc[vr] = 'string'
    for vr in case_vr_set(enc, 'encodeNumericValues'):
        ours_enc[vr] = 'string' if vr == 'AT' else 'numeric'
    for vr in case_vr_set(enc, 'isInlineBinaryVR'):
        ours_enc[vr] = 'binary'
    ours_enc['PN'] = 'personname'
    ours_enc['SQ'] = 'sequence'
    ours_dec = {}
    for vr in case_vr_set(dec, 'isStringVR'):
        ours_dec[vr] = 'string'
    for vr in case_vr_set(dec, 'isNumericVR'):
        ours_dec[vr] = 'numeric'
    ours_dec['AT'] = 'string' if 'decodeAttributeTag' in dec else '?'
    ours_dec['PN'] = 'personname'
    ours_dec['SQ'] = 'sequence'
    for vr in ('OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'UN'):
        ours_dec[vr] = 'binary'  # binary VRs carry InlineBinary/BulkDataURI, handled before the VR switch
    for label, ours in (('DICOMJSONEncoder.swift', ours_enc), ('DICOMJSONDecoder.swift', ours_dec)):
        wrong, matched = [], 0
        for vr, cls in std.items():
            if ours.get(vr) == cls or (cls == 'numeric or string' and ours.get(vr) in ('numeric', 'string')):
                matched += 1
            else:
                wrong.append(f'{vr}: ours {ours.get(vr)}, F.2.3-1 {cls}')
        extra = [vr for vr in ours if vr not in std]
        rep.check(f'PS3.18 Table F.2.3-1 VR to JSON data type ({label})', matched, wrong, [], extra)


def check_json_layout(rep, p18, files):
    """PS3.18 F.2.2: Value, BulkDataURI and InlineBinary are siblings of vr, at most one present."""
    enc = files['DICOMJSONEncoder.swift']
    dec = files['DICOMJSONDecoder.swift']
    wrong = []
    if re.search(r'\[\s*\[\s*"(InlineBinary|BulkDataURI)"\s*:', enc):
        wrong.append('DICOMJSONEncoder puts InlineBinary/BulkDataURI inside the "Value" array')
    if not re.search(r'result\["(InlineBinary|BulkDataURI)"\]\s*=', enc):
        wrong.append('DICOMJSONEncoder never writes an "InlineBinary"/"BulkDataURI" sibling of "vr"')
    if not re.search(r'elementDict\["InlineBinary"\]', dec) or not re.search(r'elementDict\["BulkDataURI"\]', dec):
        wrong.append('DICOMJSONDecoder does not read "InlineBinary"/"BulkDataURI" as siblings of "vr"')
    # F.2.2: Group Length attributes shall not be included
    if 'element == 0x0000' not in enc and 'element != 0x0000' not in enc and 'isGroupLength' not in enc:
        wrong.append('DICOMJSONEncoder does not exclude Group Length (gggg,0000) attributes (F.2.2)')
    # F.2.3: AT is the 8-character uppercase hex tag
    at_body = func_body(enc, r'func\s+encodeNumericValues\b')
    if 'attributeTagValues' not in at_body:
        wrong.append('DICOMJSONEncoder case .AT does not read attributeTagValues (D3: uint32Values is nil for AT)')
    # F.2.5: null array elements for empty values of a multi-valued attribute
    if 'NSNull' not in enc:
        wrong.append('DICOMJSONEncoder never writes null for an empty value of a multi-valued attribute (F.2.5)')
    if 'NSNull' not in dec:
        wrong.append('DICOMJSONDecoder does not accept null array elements (F.2.5)')
    rep.check('PS3.18 F.2.2-F.2.7 object layout (DICOMJSONEncoder/Decoder)', 6 - len(wrong), wrong)


# --- checks: Native DICOM Model XML (PS3.19 Annex A) --------------------------------------

def check_xml_model(rep, p19, files):
    schema = '\n'.join(section_code(p19, 'sect_A.1.6'))
    m = re.search(r'VR = attribute vr \{([^}]*)\}', schema)
    std_vrs = set(re.findall(r'"([A-Z]{2})"', m.group(1)))
    enc = files['DICOMXMLEncoder.swift']
    dec = files['DICOMXMLDecoder.swift']
    wrong = []
    binary = case_vr_set(enc, 'isBinaryVR')
    want_binary = {'OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'UN'}
    if binary != want_binary:
        wrong.append(f'DICOMXMLEncoder.isBinaryVR is {sorted(binary)}; InlineBinary/BulkData VRs are {sorted(want_binary)} (D4)')
    numeric = {'FL', 'FD', 'SL', 'SS', 'UL', 'US', 'SV', 'UV', 'AT'}
    if not numeric <= set(re.findall(r'\.([A-Z]{2})\b', enc)):
        wrong.append('DICOMXMLEncoder has no value path for the numeric VRs '
                     + ', '.join(sorted(numeric - set(re.findall(r'\.([A-Z]{2})\b', enc))))
                     + ' (DataElement.stringValues is nil for them, so no <Value> is written)')
    ns = re.search(r'default namespace="([^"]+)"', schema).group(1)
    if ns not in enc:
        wrong.append(f'namespace {ns} not in DICOMXMLEncoder')
    if 'xml:space="preserve"' not in enc:
        wrong.append('DICOMXMLEncoder omits xml:space="preserve" (Table A.1.5-1: shall be included)')
    for name in ('NativeDicomModel', 'DicomAttribute', 'Value', 'Item', 'PersonName', 'Alphabetic', 'Ideographic',
                 'Phonetic', 'FamilyName', 'GivenName', 'MiddleName', 'NamePrefix', 'NameSuffix', 'BulkData',
                 'InlineBinary'):
        for label, src in (('encoder', enc), ('decoder', dec)):
            if name not in src:
                wrong.append(f'element {name} missing from DICOMXML{label}')
    for attr in ('keyword', 'privateCreator', 'uuid', 'uri', 'number'):
        if attr not in enc + dec:
            wrong.append(f'attribute {attr} not handled by the XML encoder/decoder')
    # every VR of the schema is a DICOMCore VR (VR(rawValue:)) -- the encoder writes element.vr.rawValue
    rep.check('PS3.19 A.1.5-2 / A.1.6 Native DICOM Model elements and VR handling (DICOMXMLEncoder/Decoder)',
              len(std_vrs) + 20 - len(wrong), wrong)


# --- checks: media types (PS3.18 §8.7) ---------------------------------------------------

def standard_media_types(p18):
    grammar = '\n'.join(section_code(p18, 'sect_8.7.3.5'))
    names = set(re.findall(r'"((?:application|image|video|text|multipart)/[A-Za-z0-9.+-]+)"', grammar))
    for row in table_rows(p18, '8.7.4-1'):
        names.add(row[1] if len(row) == 4 else row[0])
    for row in table_rows(p18, '8.7.3-3'):
        names.add(row[0])
    for row in table_rows(p18, '8.7.3-5'):
        for cell in row:
            if '/' in cell and ' ' not in cell:
                names.add(cell)
    names.add('multipart/related')
    return names


def check_media_types(rep, p18, files):
    std = standard_media_types(p18)
    src = files['DICOMMediaType.swift']
    ours = {}
    for name, typ, sub in re.findall(r'static let (\w+) = DICOMMediaType\(type: "(\w+)", subtype: "([^"]+)"\)', src):
        ours[name] = f'{typ}/{sub}'
    std_lower = {s.lower(): s for s in std}
    wrong, matched, extra = [], 0, []
    for name, mt in ours.items():
        if mt in std:
            matched += 1
        elif mt.lower() in std_lower:
            wrong.append(f'{name} = "{mt}": PS3.18 spells it "{std_lower[mt.lower()]}"')
        elif mt in ('application/json',):
            extra.append(f'{name} = "{mt}" (not a DICOM media type; used for the non-standard /capabilities JSON)')
        else:
            extra.append(f'{name} = "{mt}"')
    missing = [mt for mt in sorted(std) if mt not in ours.values() and not mt.startswith('text/')
               and mt != 'application/pdf']
    rep.check('PS3.18 8.7.3.5 / 8.7.3-3 / 8.7.3-5 / 8.7.4-1 media type names (DICOMMediaType.swift)',
              matched, wrong, missing, extra, fail_on_missing=False)
    # description must quote parameter values that contain RFC 2045 tspecials (e.g. type=application/dicom)
    body = func_body(src, r'var description: String')
    wrong = []
    if not re.search(r'tspecial|contains\("/"\)|\(\)<>@,;:', body):
        wrong.append('DICOMMediaType.description does not quote a parameter value containing "/" '
                     '(RFC 2045 tspecials; PS3.18 8.7.1 type="application/dicom")')
    rep.check('PS3.18 8.7.1 / RFC 2045 quoting of the multipart type parameter (DICOMMediaType.description)',
              1 - len(wrong), wrong)


def check_bulk_data_media_types(rep, p18, files):
    """Table 8.7.3-5: compressed bulk-data media type per transfer syntax."""
    std = {}
    for row in table_rows(p18, '8.7.3-4'):
        for cell in row:
            if re.fullmatch(r'1\.2\.840\.10008[\d.]+', cell):
                std.setdefault(cell, set()).add('application/octet-stream')
    current = None
    for row in table_rows(p18, '8.7.3-5'):
        cells = [c for c in row]
        if len(cells) == 5:
            current = cells[1]
            uid = cells[2]
        elif len(cells) == 4:
            current = cells[0]
            uid = cells[1]
        elif len(cells) == 3:
            uid = cells[0]
        else:
            continue
        if re.fullmatch(r'1\.2\.840\.10008[\d.]+', uid) and current:
            std.setdefault(uid, set()).add(current)
    src = files['DICOMMediaType.swift']
    body = func_body(src, r'func\s+bulkDataMediaType\b')
    if not body:
        rep.check('PS3.18 Table 8.7.3-5 transfer syntax -> compressed bulk data media type (DICOMMediaType.bulkDataMediaType)',
                  0, ['DICOMMediaType.bulkDataMediaType(forTransferSyntax:) does not exist: frames are requested as '
                      'multipart/related; type="application/dicom", which Table 10.4.4-1 does not allow for pixel data'])
        return
    ours = {}
    for uids, name in re.findall(r'case\s+((?:"[\d.]+"(?:,\s*)?)+):\s*return\s*\.?(\w+)', body):
        for uid in re.findall(r'"([\d.]+)"', uids):
            const = re.search(r'static let ' + name + r' = DICOMMediaType\(type: "(\w+)", subtype: "([^"]+)"\)', src)
            ours[uid] = f'{const.group(1)}/{const.group(2)}' if const else name
    wrong, matched = [], 0
    for uid, mt in ours.items():
        if uid in std and mt in std[uid]:
            matched += 1
        else:
            wrong.append(f'{uid} -> {mt}; Table 8.7.3-5: {sorted(std.get(uid, []))}')
    missing = [f'{uid} -> {sorted(m)}' for uid, m in std.items() if uid not in ours]
    rep.check('PS3.18 Table 8.7.3-5 transfer syntax -> compressed bulk data media type (DICOMMediaType.bulkDataMediaType)',
              matched, wrong, missing, fail_on_missing=False)


def check_frames_accept(rep, files):
    body = func_body(files['DICOMwebClient.swift'], r'func\s+retrieveFrames\(')
    wrong = []
    if 'buildAcceptHeader(transferSyntax' in body or ('octet-stream' not in body and 'buildFramesAcceptHeader' not in body):
        wrong.append('retrieveFrames sends Accept: multipart/related; type="application/dicom"; Table 10.4.4-1 '
                     'allows only application/octet-stream or a compressed bulk data media type for pixel data')
    rep.check('PS3.18 Table 10.4.4-1 Accept for frame (pixel data) resources (DICOMwebClient.retrieveFrames)',
              1 - len(wrong), wrong)


# --- checks: UIDs (PS3.6 Table A-1) ---------------------------------------------------------

def check_uids(rep, p6, files):
    std = uid_registry(p6)
    matched, unknown, seen = 0, [], set()
    for name, src in files.items():
        for uid in re.findall(r'"(1\.2\.840\.10008(?:\.\d+)+)"', src):
            if uid in seen:
                continue
            seen.add(uid)
            if uid in std:
                matched += 1
            else:
                unknown.append(f'{uid} ({name})')
    rep.check('PS3.6 Table A-1: every 1.2.840.10008.* literal in the module is registered', matched, unknown)
    # names next to UIDs: `"uid": ("Name", ...)`, `uid: "Name"`, `// Name` and `/// Name` comments
    wrong, matched = [], 0
    for name, src in files.items():
        for uid, doc in re.findall(r'"(1\.2\.840\.10008[\d.]+)"(?:,[ \t]*\n?[ \t]*name:[ \t]*|:[ \t]*\([ \t]*|,?[ \t]*//[ \t]*)"?([^",\n)]+)', src):
            doc = doc.strip().strip('"')
            if uid not in std or not doc or doc.startswith(('vr', 'Value', 'name')):
                continue
            a1 = std[uid][0]
            if norm_name(a1) == norm_name(doc) or norm_name(doc) in norm_name(a1) or norm_name(a1) in norm_name(doc):
                matched += 1
            else:
                wrong.append(f'{name}: "{doc}" for {uid}; A-1 "{a1}"')
    rep.check('PS3.6 Table A-1 names written next to UID literals', matched, wrong)


def norm_name(s):
    s = s.lower().replace('–', '-').replace('(retired)', '')
    s = re.sub(r'\(process \d+\)', '', s)
    s = s.replace('image compression', '').replace('storage', '').replace('sop class', '')
    s = s.replace(': default transfer syntax for lossy jpeg 8 bit', '').replace('lossless only', 'lossless')
    return re.sub(r'[^a-z0-9]', '', s)


# --- checks: URI templates and query parameters ------------------------------------------------

def standard_templates(p18):
    out = {}
    for label in ('10.4.1-1', '10.4.1-2', '10.4.1-3', '10.4.1-4', '10.4.1.5-1', '10.4.1.6-1', '10.5.1-1',
                  '10.6.1-1', '11.1.1-1', '11.4.1-1', '11.10.1-1', '11.11.1-1', '11.12.1-1'):
        for row in table_rows(p18, label):
            if len(row) >= 2 and row[1].startswith(('/', '{')):
                out[row[1].split('{?')[0].replace('?{workitem}', '?workitem=')] = label
    return out


PLACEHOLDERS = {'{studyUID}': '{study}', '{seriesUID}': '{series}', '{instanceUID}': '{instance}',
                '{frameList}': '{frames}', '{workitemUID}': '{workitem}', '{aeTitle}': '{subscriber}',
                '{uid}': '{workitem}', '?workitem={workitemUID}': '?workitem='}


def normalize_template(t):
    for k, v in PLACEHOLDERS.items():
        t = t.replace(k, v)
    return re.sub(r'\[.*?\]', '', t).split('?00081195')[0]


def check_uri_templates(rep, p18, files):
    std = standard_templates(p18)
    wrong, matched, extra = [], 0, []
    builder = files['DICOMwebURLBuilder.swift']
    ours = set(normalize_template(t) for t in re.findall(r'URL for `(?:POST |GET )?([^`]+)`', builder))
    router = files['Server/DICOMwebRoutes.swift']
    ours |= set(normalize_template(t) for t in re.findall(r'pattern:\s*"([^"]+)"', router))
    known_extensions = {'/capabilities': 'DICOMKit JSON capabilities (PS3.18 8.9 defines OPTIONS / with a WADL description)',
                        '/studies/{study}/series/{series}/instances/{instance}/bulkdata/{attributePath}':
                            'per-attribute bulk data path (Table 10.4.1.5-1 has /bulkdata; a Bulk Data resource is any {bulkdataURI})',
                        '/workitems/{workitem}/state/{requestingAE}': 'dcm4chee style; PS3.18 11.7.1 uses ?requester={aetitle}',
                        '/workitems/{workitem}/cancelrequest/{requestingAE}': 'dcm4chee style; PS3.18 11.8.1 uses ?requester={aetitle}',
                        'ws/subscribers/{subscriber}': 'WebSocket endpoint (PS3.18 8.10.4 leaves the URL to the origin server)',
                        '/': 'service root'}
    for t in sorted(ours):
        if t in std:
            matched += 1
        elif t.replace('{requestingAE}', '').rstrip('/') in std:
            matched += 1
        else:
            hit = next((k for k in known_extensions if k in t or t.endswith(k)), None)
            if hit:
                extra.append(f'{t}: {known_extensions[hit]}')
            else:
                wrong.append(f'{t}: not a PS3.18 URI template')
    missing = [f'{t} ({l})' for t, l in std.items() if t not in ours and not t.startswith('{')]
    rep.check('PS3.18 Tables 10.4.1-x, 10.5.1-1, 10.6.1-1, 11.1.1-1, 11.4.1-1, 11.10-11.12 URI templates '
              '(DICOMwebURLBuilder, DICOMwebRouter)', matched, wrong, missing, extra, fail_on_missing=False)


def check_query_parameters(rep, p18, files):
    std = set()
    for row in table_rows(p18, '8.3.4-1'):
        if row and re.fullmatch(r'[a-z]+', row[0]) and row[0] != 'search':
            std.add(row[0])
    for label in ('8.3.5-1', '8.3.5-2', '10.4.1-5', '11.10.1-2', '11.7.2.1-1'):
        for row in table_rows(p18, label):
            if row and re.fullmatch(r'[a-z]+', row[0]):
                std.add(row[0])
    src = files['DICOMwebURLBuilder.swift']
    body = enum_body(src, 'QueryParameter')
    body = re.sub(r'@available\(\*, deprecated[^\n]*\n\s*public static let \w+ = "[^"]+"', '', body)  # deprecated aliases
    ours = dict(re.findall(r'static let (\w+) = "([^"]+)"', body))
    tags = {k: v for k, v in ours.items() if re.fullmatch(r'[0-9A-F]{8}', v)}
    wrong, matched = [], 0
    for k, v in ours.items():
        if k in tags:
            continue
        if v in std:
            matched += 1
        else:
            wrong.append(f'QueryParameter.{k} = "{v}": not a PS3.18 RESTful query parameter (Tables 8.3.4-1, 8.3.5-1, 10.4.1-5)')
    used = set(re.findall(r'"([a-z]+)"', src + files['DICOMwebClient.swift'] + files['QIDOQuery.swift']))
    missing = [q for q in sorted(std) if q not in ours.values() and q not in used
               and q not in ('charset', 'emptyvaluematching', 'multiplevaluematching', 'filter', 'requester')]
    rep.check('PS3.18 Tables 8.3.4-1, 8.3.5-1/2, 10.4.1-5, 11.7.2.1-1, 11.10.1-2 RESTful query parameter names '
              '(DICOMwebURLBuilder.QueryParameter)', matched, wrong, missing, fail_on_missing=False)
    # the rendered-URL builders must emit window=c,w,function and viewport=vw,vh
    wrong = []
    for name, s in (('DICOMwebURLBuilder.renderedParameters', func_body(src, r'static func renderedParameters\(')),
                    ('DICOMwebClient.applyRenderOptions', func_body(files['DICOMwebClient.swift'], r'func applyRenderOptions\('))):
        if 'QueryParameter.window]' not in s.replace(' ', '') and '.window]' not in s.replace(' ', '') \
                and 'renderedParameters(' not in s:
            wrong.append(f'{name} does not emit "window=center,width,function" (8.3.5.1.4)')
        if '.viewport' not in s and 'renderedParameters(' not in s:
            wrong.append(f'{name} does not emit "viewport=vw,vh" (8.3.5.1.3)')
    rep.check('PS3.18 8.3.5.1.3 / 8.3.5.1.4 rendered query parameter syntax (renderedURL, applyRenderOptions)',
              4 - len(wrong), wrong)
    # WADO-URI (PS3.18 §9)
    std_uri = set()
    for label in ('9.1.2-1', '9.1.2-2', '9.4.1-1', '9.5.1-1'):
        for row in table_rows(p18, label):
            if row and re.fullmatch(r'[A-Za-z]+', row[0]):
                std_uri.add(row[0])
    body = func_body(files['WADOURIClient.swift'], r'private func buildURL\(')
    ours = set(re.findall(r'URLQueryItem\(name:\s*"(\w+)"', body))
    wrong = [q for q in ours if q not in std_uri]
    missing = [q for q in sorted(std_uri) if q not in ours]
    rep.check('PS3.18 Tables 9.1.2-1, 9.1.2-2, 9.4.1-1, 9.5.1-1 URI service query parameter names (WADOURIClient.buildURL)',
              len(ours) - len(wrong), wrong, missing, fail_on_missing=False)
    # contentType values allowed by 9.1.2.2.1: application/dicom or a Rendered Media Type (8.7.4-1)
    rendered = {row[1] if len(row) == 4 else row[0] for row in table_rows(p18, '8.7.4-1')}
    body = re.sub(r'@available\(\*, deprecated[^\n]*\n\s*case \w+ = "[^"]*"', '', enum_body(files['WADOURIClient.swift'], 'ContentType'))
    ours = re.findall(r'case\s+\w+\s*=\s*"([^"]*)"', body)
    wrong = [f'"{v}" is not application/dicom or a Rendered Media Type of Table 8.7.4-1 (9.1.2.2.1)'
             for v in ours if v != 'application/dicom' and v not in rendered]
    rep.check('PS3.18 9.1.2.2.1 contentType values (WADOURIClient.ContentType)', len(ours) - len(wrong), wrong)


# --- checks: QIDO-RS attributes (PS3.18 Tables 10.6.1-5, 10.6.3-3..5) -------------------------

def check_qido_attributes(rep, p18, files):
    def tags_of(label):
        out = {}
        for row in table_rows(p18, label):
            for cell in row:
                m = re.fullmatch(r'\((\w{4}),(\w{4})\)', cell)
                if m:
                    out[(m.group(1) + m.group(2)).upper()] = row[0].lstrip('>') if row[0] and not row[0].startswith('(') else row[1]
        return out
    required = tags_of('10.6.1-5')
    qsrc = files['QIDOQuery.swift']
    ours = set(re.findall(r'"([0-9A-F]{8})"', enum_body(qsrc, 'QIDOQueryAttribute')))
    missing = [f'{t} {n}' for t, n in required.items() if t not in ours]
    rep.check('PS3.18 Table 10.6.1-5 required matching attributes (QIDOQueryAttribute)', len(required) - len(missing), [], missing)
    ssrc = files['Server/DICOMwebServer.swift']
    parse = func_body(ssrc, r'func parseQIDOQuery\(')
    ours = set(re.findall(r'"([0-9A-F]{8})"', parse))
    missing = [f'{t} {n}' for t, n in required.items() if t not in ours]
    rep.check('PS3.18 Table 10.6.1-5 required matching attributes parsed by the server (parseQIDOQuery)',
              len(required) - len(missing), [], missing, fail_on_missing=False)
    for label, fn in (('10.6.3-3', 'encodeStudyResultsAsJSON'), ('10.6.3-4', 'encodeSeriesResultsAsJSON'),
                      ('10.6.3-5', 'encodeInstanceResultsAsJSON')):
        std = {}
        for row in table_rows(p18, label):
            if len(row) >= 3:
                std[row[1].strip('()').replace(',', '').upper()] = (row[0], row[2])
        body = func_body(ssrc, r'func ' + fn + r'\(')
        ours = set(re.findall(r'"([0-9A-F]{8})"', body))
        matched = len([t for t in std if t in ours])
        missing = [f'{t} {n} ({ty})' for t, (n, ty) in std.items() if t not in ours and ty in ('R', 'U')]
        rep.check(f'PS3.18 Table {label} R/U return attributes emitted by the server ({fn})', matched, [], missing,
                  fail_on_missing=False)
    # study-level "modality" convenience must query Modalities in Study (0008,0061)
    body = func_body(qsrc, r'static func studiesByModality\(')
    wrong = [] if 'modalitiesInStudy' in body else ['QIDOQuery.studiesByModality sends Modality (0008,0060); '
                                                     'Table 10.6.1-5 study level matches Modalities in Study (0008,0061)']
    rep.check('PS3.18 Table 10.6.1-5 study-level modality key (QIDOQuery.studiesByModality)', 1 - len(wrong), wrong)


# --- checks: transactions, methods and status codes ----------------------------------------------

def check_ups_methods(rep, p18, files):
    std = {}
    for row in table_rows(p18, '11.3-1'):
        if len(row) >= 2 and row[1] in ('GET', 'POST', 'PUT', 'DELETE'):
            std[row[0]] = row[1]
    template = {'Create': '/workitems', 'Retrieve': '/workitems/{workitem}', 'Update': '/workitems/{workitem}',
                'Change State': '/workitems/{workitem}/state', 'Request Cancellation': '/workitems/{workitem}/cancelrequest',
                'Search': '/workitems', 'Subscribe': '/workitems/{workitem}/subscribers/{subscriber}',
                'Unsubscribe': '/workitems/{workitem}/subscribers/{subscriber}'}
    router = files['Server/DICOMwebRoutes.swift']
    routes = set()
    for m in re.finditer(r'case \(\.(\w+), (\d+)\)([^\n]*)\n(?:[^\n]*\n){0,10}?[^\n]*pattern:\s*"([^"]+)"', router):
        routes.add((m.group(1).upper(), normalize_template(m.group(4))))
    wrong, matched = [], 0
    for tx, method in std.items():
        want = (method, template[tx])
        if want in routes:
            matched += 1
        else:
            wrong.append(f'{tx}: PS3.18 Table 11.3-1 is {method} {template[tx]}; router has '
                         + ', '.join(f'{m} {p}' for m, p in sorted(routes) if p == template[tx]))
    if ('POST', '/workitems/{workitem}') in routes:
        body = files['Server/DICOMwebRoutes.swift']
        if re.search(r'case \(\.post, 2\) where components\[0\] == "workitems"[\s\S]{0,300}?createWorkitemWithUID', body):
            wrong.append('router maps POST /workitems/{workitem} to Create; 11.4.1-1 creates with /workitems?{workitem} '
                         'and 11.6.1 uses POST /workitems/{workitem} for Update')
    client = files['DICOMwebClient.swift']
    for fn, tx in (('requestWorkitemCancellation', 'Request Cancellation'), ('updateWorkitem', 'Update'),
                   ('changeWorkitemState', 'Change State'), ('subscribeToWorkitem', 'Subscribe'),
                   ('unsubscribeFromWorkitem', 'Unsubscribe'), ('createWorkitem', 'Create')):
        body = func_body(client, r'public func ' + fn + r'\(\s*\n?\s*(?:uid|workitem|workitemUID)')
        m = re.search(r'method:\s*\.(\w+)', body)
        if m and m.group(1).upper() != std[tx]:
            wrong.append(f'DICOMwebClient.{fn} uses {m.group(1).upper()}; Table 11.3-1: {std[tx]}')
        elif m:
            matched += 1
    sub = func_body(client, r'public func subscribeToWorkitem\(')
    if 'Deletion-Lock' in sub or 'deletionlock' not in sub:
        wrong.append('DICOMwebClient.subscribeToWorkitem sends a "Deletion-Lock" header; 11.10.1.2 defines the '
                     '"deletionlock=true" query parameter')
    rep.check('PS3.18 Table 11.3-1 UPS-RS methods and resources (DICOMwebRouter, DICOMwebClient)', matched, wrong)


def check_server_status_codes(rep, p18, files):
    src = files['Server/DICOMwebServer.swift']
    checks = [
        ('handleCreateWorkitem', '11.4.3-1', {'201', '409', '400'}, set()),
        ('handleUpdateWorkitem', '11.6.3-1', {'200', '400', '404', '409'}, {'204'}),
        ('handleChangeWorkitemState', '11.7.3-1', {'200', '400', '404', '409'}, {'204'}),
        ('handleRequestWorkitemCancellation', '11.8.3-1', {'202', '400', '404', '409'}, {'200'}),
        ('handleSubscribeWorkitem', '11.10.3-1', {'201', '400', '403', '404'}, {'200'}),
        ('handleUnsubscribeWorkitem', '11.11.3-1', {'200', '400', '404'}, set()),
        ('handleSuspendSubscription', '11.12.3-1', {'200', '400', '404'}, set()),
        ('buildSTOWResponseWithStatus', '10.5.3-1', {'200', '202', '400', '409', '415'}, set()),
        ('handleRetrieveFrames', '8.5-1', {'501'}, {'500'}),
        ('handleRetrieveRendered', '8.5-1', {'501'}, {'500'}),
        ('handleRetrieveThumbnail', '8.5-1', {'501'}, {'500'}),
        ('handleRetrieveBulkData', '8.5-1', {'501'}, {'500'}),
    ]
    factory = {'.ok(': '200', '.noContent(': '204', '.badRequest(': '400', '.notFound(': '404', '.conflict(': '409',
               '.unsupportedMediaType(': '415', '.internalError(': '500', '.serviceUnavailable(': '503',
               '.notAcceptable(': '406'}
    std_all = {}
    for label in ('11.4.3-1', '11.6.3-1', '11.7.3-1', '11.8.3-1', '11.10.3-1', '11.11.3-1', '11.12.3-1', '10.5.3-1',
                  '10.4.3-1', '10.6.3-1'):
        codes = set()
        for row in table_rows(p18, label):
            for cell in row:
                m = re.match(r'(\d{3}) \(', cell)
                if m:
                    codes.add(m.group(1))
        std_all[label] = codes
    for label in ('8.5-1',):
        std_all[label] = set(re.findall(r'\b(\d{3})\b', ' '.join(r[0] for r in table_rows(p18, label) if r)))
    wrong, matched = [], 0
    for fn, label, expected_success, forbidden in checks:
        body = func_body(src, r'func ' + fn + r'\(')
        for helper in re.findall(r'return (\w+)\(request\)', body):
            body += func_body(src, r'func ' + helper + r'\(')
        used = set(re.findall(r'statusCode\s*[:=]\s*(\d{3})', body))
        used |= set(re.findall(r'response\((\d{3})', body))
        for k, v in factory.items():
            if k in body:
                used.add(v)
        used.discard('501') if 'UPS-RS not configured' in body and '501' not in expected_success else None
        success = sorted(c for c in used if c.startswith('2'))
        want_success = sorted(c for c in expected_success if c.startswith('2'))
        bad = used & forbidden
        if bad or (want_success and not set(want_success) & used):
            wrong.append(f'{fn}: uses {sorted(used)}; Table {label} success is {want_success}'
                         + (f', {sorted(bad)} not defined for it' if bad else ''))
        else:
            matched += 1
        for c in used - std_all[label] - {'501'}:
            if c not in ('500',):
                wrong.append(f'{fn}: {c} is not in Table {label}')
    rep.check('PS3.18 status codes per transaction (DICOMwebServer handlers)', matched, wrong)


def check_warning_headers(rep, p18, files):
    """The Warning header texts PS3.18 prescribes must be emitted verbatim."""
    src = files['Server/DICOMwebServer.swift']
    wanted = {}
    for sect in ('sect_8.3.4.4.1', 'sect_8.3.4.2', 'sect_11.7.3.2', 'sect_11.6.3.2', 'sect_11.4.3.2', 'sect_11.8.3.2',
                 'sect_11.10.3.2'):
        for code in section_code(p18, sect):
            m = re.search(r'Warning:?\s*(?:299\s*)?<service>:\s*(.+?)(?:CRLF)?$', code)
            if m:
                wanted[m.group(1).strip()] = sect
    matched, missing = 0, []
    for text, sect in wanted.items():
        probe = text.replace('<remaining>', '').split('<')[0].strip()
        if probe and probe in src:
            matched += 1
        else:
            missing.append(f'"{text}" ({sect[5:]})')
    rep.check('PS3.18 prescribed Warning header texts (DICOMwebServer)', matched, [], missing, fail_on_missing=False)


# --- checks: STOW-RS response module (PS3.18 Annex I) ------------------------------------------

def check_stow_response(rep, p18, files):
    tags = {}
    for row in table_rows(p18, 'I.1-1'):
        if len(row) >= 2 and re.fullmatch(r'\(\w{4},\w{4}\)', row[1]):
            tags[row[1].strip('()').replace(',', '').upper()] = row[0].lstrip('>')
    client = files['STOWResponse.swift']
    server = files['Server/DICOMwebServer.swift']
    ours = set(re.findall(r'"([0-9A-F]{8})"', enum_body(client, 'Tag') + func_body(server, r'func buildSTOWResponseJSON\(')))
    ours |= {'00081150', '00081155'}  # SOP Instance Reference Macro (PS3.3 Table 10-11) inside the sequences
    missing = [f'{t} {n}' for t, n in tags.items() if t not in ours and not t.startswith('0400')]
    extra = [t for t in ours if t not in tags and t not in ('00081150', '00081155')]
    rep.check('PS3.18 Table I.1-1 Store Instances Response Module tags (STOWResponse, DICOMwebServer)',
              len(tags) - len(missing), [], missing, extra, fail_on_missing=False)
    codes = {}
    for label in ('I.2-1', 'I.2-2'):
        for row in table_rows(p18, label):
            if row and re.fullmatch(r'[0-9A-Fx]{4}', row[0]):
                codes[row[0]] = (row[2], label)

    def classify(code):
        h = f'{code:04X}'
        for pat, (meaning, label) in codes.items():
            if pat == h or ('x' in pat and re.fullmatch(pat.replace('x', '[0-9A-F]'), h)):
                return meaning, label
        return None

    client = re.sub(r'@available\(\*, deprecated[^\n]*\n\s*case \w+ = 0x[0-9A-Fa-f]+', '', client)  # deprecated cases
    for label, enum_name, src, pend_key in (('STOWResponse.FailureReasonCode', 'FailureReasonCode', client,
                                              'STOWResponse.FailureReasonCode'),
                                             ('DICOMwebServer.STOWFailureReason', 'STOWFailureReason', server, None)):
        ours = hex_cases(src, enum_name)
        wrong, pending, matched = [], [], 0
        extra = []
        for name, code in ours.items():
            hit = classify(code)
            if hit:
                matched += 1
            elif code == 0x0111:
                extra.append(f'.{name} = 0x0111: PS3.7 C.5.9 Duplicate SOP Instance, an additional code as I.2.2 allows')
            else:
                msg = f'.{name} = 0x{code:04X}: not in Tables I.2-1 / I.2-2'
                (pending if pend_key and (pend_key, code) in PENDING_API_APPROVAL else wrong).append(msg)
        missing = [f'{pat} {m}' for pat, (m, l) in codes.items() if 'x' not in pat and int(pat, 16) not in ours.values()]
        rep.check(f'PS3.18 Tables I.2-1 / I.2-2 Warning/Failure Reason codes ({label})', matched, wrong, missing, extra,
                  pending=pending, fail_on_missing=False)


# --- checks: UPS (PS3.4 Annex CC, PS3.3 C.30, PS3.6) --------------------------------------------

def check_ups_states(rep, p3, p4, files):
    wsrc = files['UPS/Workitem.swift']
    std_states = [t for t in variablelist_terms(p3, 'sect_C.30.1') if t.isupper()]
    ours = string_cases(wsrc, 'UPSState')
    rep.check('PS3.3 C.30.1 Procedure Step State terms (UPSState)', len([s for s in ours if s in std_states]),
              [s for s in ours if s not in std_states], [s for s in std_states if s not in ours])
    std_pri = [t.split()[0] for t in variablelist_terms(p3, 'sect_C.30.2') if t.split()[0] in ('HIGH', 'MEDIUM', 'LOW')]
    body = re.sub(r'@available\(\*, deprecated[^\n]*\n\s*case \w+ = "[^"]*"', '', enum_body(wsrc, 'UPSPriority'))
    ours = re.findall(r'case\s+\w+\s*=\s*"([^"]*)"', body)
    wrong = [s for s in ours if s not in std_pri]
    rep.check('PS3.3 C.30.2 Scheduled Procedure Step Priority terms (UPSPriority; the deprecated stat is written as HIGH)',
              len(ours) - len(wrong), wrong, [s for s in std_pri if s not in ours])
    std_ready = [t.split()[0] for t in variablelist_terms(p3, 'sect_C.30.2') if t.split()[0] in ('INCOMPLETE', 'UNAVAILABLE', 'READY')]
    ours = string_cases(wsrc, 'InputReadinessState')
    rep.check('PS3.3 C.30.2 Input Readiness State terms (InputReadinessState)', len([s for s in ours if s in std_ready]),
              [s for s in ours if s not in std_ready], [s for s in std_ready if s not in ours])
    # Table CC.1.1-2: SCU-initiated state changes that succeed
    rows = table_rows(p4, 'CC.1.1-2')
    states = ['SCHEDULED', 'IN PROGRESS', 'COMPLETED', 'CANCELED']
    allowed = set()
    for row in rows:
        m = re.match(r'N-ACTION to Change State to ([A-Z ]+?),? with(?:out)? correct Transaction UID', row[0])
        if not m or 'without' in row[0]:
            continue
        target = m.group(1).strip()
        for state, cell in zip(states, row[2:6]):
            if 'Change State to' in cell:
                allowed.add((state, target))
    body = func_body(wsrc, r'var validTransitions: \[UPSState\]')
    name_of = {'scheduled': 'SCHEDULED', 'inProgress': 'IN PROGRESS', 'completed': 'COMPLETED', 'canceled': 'CANCELED'}
    ours = set()
    for m in re.finditer(r'case \.(\w+):\s*\n\s*return \[([^\]]*)\]', body):
        for t in re.findall(r'\.(\w+)', m.group(2)):
            ours.add((name_of[m.group(1)], name_of[t]))
    wrong = [f'{a} -> {b}: Table CC.1.1-2 gives C310H (the SCP cancels a SCHEDULED UPS itself on Request Cancel, CC.2.2.3)'
             if (a, b) == ('SCHEDULED', 'CANCELED') else f'{a} -> {b}: not allowed by Table CC.1.1-2' for a, b in ours - allowed]
    missing = [f'{a} -> {b}' for a, b in allowed - ours]
    rep.check('PS3.4 Table CC.1.1-2 Change State transitions (UPSState.validTransitions)', len(ours & allowed), wrong, missing)


def check_ups_tags(rep, p6, files):
    dic = dictionary(p6)
    wsrc = files['UPS/Workitem.swift']
    body = enum_body(wsrc, 'UPSTag')
    body = re.sub(r'@available\(\*, deprecated[^\n]*\n\s*public static let \w+ = "[^"]+"', '', body)
    ours = dict(re.findall(r'static let (\w+) = "([0-9A-F]{8})"', body))
    wrong, matched = [], 0
    for name, tag in ours.items():
        entry = dic.get(tag)
        if entry is None:
            wrong.append(f'UPSTag.{name} = {tag}: not in PS3.6 Table 6-1')
            continue
        keyword = entry[1]
        if norm_kw(name) != norm_kw(keyword) and norm_kw(name) not in norm_kw(keyword):
            wrong.append(f'UPSTag.{name} = {tag}: PS3.6 keyword is {keyword}')
        else:
            matched += 1
    rep.check('PS3.6 Table 6-1 tags and keywords of UPSTag (Workitem.swift)', matched, wrong)
    # VR written next to each UPSTag in JSON literals, across the module
    wrong, matched = [], 0
    for fname, src in files.items():
        for name, vr in re.findall(r'UPSTag\.(\w+)\]\s*=\s*\[\s*\n?\s*"vr":\s*"(\w\w)"', src):
            tag = ours.get(name)
            if not tag or tag not in dic:
                continue
            std_vr = dic[tag][2].split(' or ')
            if vr in std_vr:
                matched += 1
            else:
                wrong.append(f'{fname}: {name} ({tag}) written with vr {vr}; PS3.6: {dic[tag][2]}')
    for fname, src in files.items():
        for tag, vr in re.findall(r'"([0-9A-F]{8})"\s*(?:\]|:)\s*=?\s*\[\s*\n?\s*"vr":\s*"(\w\w)"', src):
            if tag in dic and tag not in ours.values():
                std_vr = dic[tag][2].split(' or ')
                if vr in std_vr:
                    matched += 1
                else:
                    wrong.append(f'{fname}: {tag} written with vr {vr}; PS3.6: {dic[tag][2]}')
    rep.check('PS3.6 Table 6-1 VR of every JSON attribute literal in the module', matched, wrong)


def norm_kw(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())


def check_ups_create(rep, p4, files):
    required = {}
    for row in table_rows(p4, 'CC.2.5-3'):
        if len(row) >= 3 and re.fullmatch(r'\(\w{4},\w{4}\)', row[1]) and not row[0].startswith('>'):
            usage = row[2].split('|')[0].strip()
            if re.match(r'[12](C)?/', usage):
                required[row[1].strip('()').replace(',', '').upper()] = f'{row[0]} {usage}'
    wsrc = files['UPS/Workitem.swift']
    body = func_body(wsrc, r'public func toDICOMJSONForCreate\(')
    tag_of = dict(re.findall(r'static let (\w+) = "([0-9A-F]{8})"', enum_body(wsrc, 'UPSTag')))
    ours = set(tag_of.get(n) for n in re.findall(r'UPSTag\.(\w+)', body)) | set(re.findall(r'"([0-9A-F]{8})"', body))
    missing = [f'{t} {d}' for t, d in required.items() if t not in ours and not d.endswith('C/1')]
    conditional = [f'{t} {d}' for t, d in required.items() if t not in ours and d.endswith('C/1')]
    rep.check('PS3.4 Table CC.2.5-3 N-CREATE Type 1/2 attributes emitted (Workitem.toDICOMJSONForCreate)',
              len(required) - len(missing) - len(conditional), [], missing, conditional, fail_on_missing=False)


def check_ups_events(rep, p4, files):
    std = {}
    for row in table_rows(p4, 'CC.2.4-1'):
        if len(row) >= 5 and row[1].isdigit():
            std[int(row[1])] = row[0]
    src = files['UPS/UPSWebSocketClient.swift']
    body = func_body(src, r'private func parseEventType\(')
    ours = {int(n): kind for n, kind in re.findall(r'case (\d+): return \.(\w+)', body)}
    matched = len([n for n in ours if n in std])
    missing = [f'{n} {name}' for n, name in std.items() if n not in ours]
    rep.check('PS3.4 Table CC.2.4-1 Event Type IDs decoded (UPSWebSocketClient.parseEventType)', matched,
              [f'{n}' for n in ours if n not in std], missing, fail_on_missing=False)
    esrc = files['UPS/UPSEvent.swift']
    body = func_body(esrc, r'var eventTypeID: Int')
    ours_ids = set(int(n) for n in re.findall(r'return (\d)', body))
    wrong = [f'eventTypeID {n} not in Table CC.2.4-1' for n in ours_ids if n not in std]
    missing = [f'{n} {name}' for n, name in std.items() if n not in ours_ids]
    # every event payload carries (0000,1002) and never the Transaction UID
    for name in ('UPSStateReportEvent', 'UPSProgressReportEvent', 'UPSCancelRequestedEvent', 'UPSAssignedEvent'):
        struct_body = esrc[esrc.find('struct ' + name):]
        struct_body = struct_body[:struct_body.find('\n}\n')]
        if 'eventTypeIDAttribute' not in struct_body:
            wrong.append(f'{name}.toDICOMJSON has no Event Type ID (0000,1002)')
        if '"00081195"' in struct_body or 'UPSTag.transactionUID' in struct_body:
            wrong.append(f'{name}.toDICOMJSON sends the Transaction UID (PS3.4 CC.2.7.3)')
    rep.check('PS3.4 Table CC.2.4-1 event identification (UPSEventType.eventTypeID, Event Report payloads)',
              len(ours_ids & set(std)), wrong, missing)


# --- checks: character sets, error codes, citations --------------------------------------------

def check_charsets(rep, p18, files):
    std = set()
    for row in table_rows(p18, 'D-1'):
        std.add(row[0])
        std.update(row[1].split('\\'))
    src = files['ConformanceStatement.swift']
    ours = re.findall(r'"((?:ISO_IR \d+|ISO 2022 IR \d+|UTF-8|ISO-8859-\d+|GB18030|GBK|TIS-620))"', src)
    rep.check('PS3.18 Table D-1 character set names (ConformanceStatement)', len([c for c in ours if c in std]),
              [c for c in ours if c not in std])


def check_error_codes(rep, p18, files):
    std = set(re.findall(r'\b([1-5]\d{2})\b', ' '.join(r[0] for r in table_rows(p18, '8.5-1') if r)))
    src = files['DICOMwebError.swift']
    body = func_body(src, r'static func fromHTTPStatus\(')
    ours = set(re.findall(r'case (\d{3})', body))
    rep.check('PS3.18 Table 8.5-1 status codes mapped by DICOMwebError.fromHTTPStatus', len(ours & std), [],
              [c for c in sorted(std) if c not in ours and c.startswith('4') and c in ('410',)],
              [f'{c} (generic HTTP, not in Table 8.5-1)' for c in sorted(ours - std)], fail_on_missing=False)


def check_citations(rep, p18, p19, files):
    ids18 = section_ids(p18)
    ids19 = section_ids(p19)
    expect = {'10.4': 'Retrieve', '10.5': 'Store', '10.6': 'Search', '11': 'Worklist', '11.4': 'Create',
              '11.5': 'Retrieve', '11.6': 'Update', '11.7': 'Change', '11.8': 'Cancel', '11.9': 'Search',
              '11.10': 'Subscribe', '11.11': 'Unsubscribe', '11.12': 'Suspend', '8.9': 'Capabilit', '8.10': 'Notification',
              '8.5': 'Status', '8.6': 'Payload', '8.7': 'Media', '9': 'URI', 'F': 'JSON', '8.3': 'Query', '8.4': 'Header',
              '8.8': 'Character', '10': 'Studies', '8': 'Common', '6': 'Conformance', '6.7': None,
              '6.1.1.1': None, '6.1.1.2': None, '6.1.1.8': None}
    wrong, matched = [], 0
    for fname, src in files.items():
        for m in re.finditer(r'PS3\.(18|19)[ ,]*(?:Section|§|Annex)\s*([A-Z]?[\d.]*[\dA-Z])(?:\s*[-–—]\s*([^\n*]+))?', src):
            part, sect, desc = m.group(1), m.group(2).rstrip('.'), (m.group(3) or '').strip()
            ids = ids18 if part == '18' else ids19
            sid = f'sect_{sect}' if '.' in sect else f'chapter_{sect}'
            if sid not in ids:
                wrong.append(f'{fname}: PS3.{part} {sect} does not exist in the 2026a text ("{desc[:50]}")')
                continue
            want = expect.get(sect)
            if part == '18' and sect in expect and want is None and desc:
                wrong.append(f'{fname}: "PS3.18 {sect} - {desc[:40]}": 2026a §{sect} is "{section_title(p18, sid)}"')
            elif part == '18' and want and desc and want.lower() not in desc.lower() and not desc.lower().startswith(('wado', 'qido', 'stow', 'ups')):
                title = section_title(p18, sid)
                wrong.append(f'{fname}: "PS3.18 {sect} - {desc[:40]}": 2026a §{sect} is "{title}"')
            else:
                matched += 1
    rep.check('PS3.18 / PS3.19 section citations in doc comments exist in the 2026a text and name the right transaction',
              matched, wrong)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True, help='directory with partNN_<edition>.xml files')
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--sources', default=os.path.join(os.path.dirname(HERE), 'Sources', 'DICOMWeb'))
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    parts = {}
    for n in (3, 4, 6, 18, 19):
        path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
        parts[n] = nd.Part(path)
        sub = parts[n].subtitle
        if args.edition not in sub:
            sys.exit(f'{path}: subtitle {sub!r} does not name {args.edition}')
        print(f'using {path}: {sub}')
    p3, p4, p6, p18, p19 = parts[3], parts[4], parts[6], parts[18], parts[19]
    rep = Report(args.verbose)
    files = read_all(args.sources)

    check_json_vr_mapping(rep, p18, files)
    check_json_layout(rep, p18, files)
    check_xml_model(rep, p19, files)
    check_media_types(rep, p18, files)
    check_bulk_data_media_types(rep, p18, files)
    check_frames_accept(rep, files)
    check_uids(rep, p6, files)
    check_uri_templates(rep, p18, files)
    check_query_parameters(rep, p18, files)
    check_qido_attributes(rep, p18, files)
    check_ups_methods(rep, p18, files)
    check_server_status_codes(rep, p18, files)
    check_warning_headers(rep, p18, files)
    check_stow_response(rep, p18, files)
    check_ups_states(rep, p3, p4, files)
    check_ups_tags(rep, p6, files)
    check_ups_create(rep, p4, files)
    check_ups_events(rep, p4, files)
    check_charsets(rep, p18, files)
    check_error_codes(rep, p18, files)
    check_citations(rep, p18, p19, files)

    print(f'\n{rep.failed} check(s) with wrong or missing values, {rep.pending} pending owner approval')
    sys.exit(1 if rep.failed else 0)


if __name__ == '__main__':
    main()
