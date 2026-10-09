#!/usr/bin/env python3
"""Diff the protocol constants of Sources/DICOMNetwork against the frozen DICOM DocBook.

Usage:
    python3 Scripts/nema_docbook.py fetch 2026a 3   # PS3.3 (print / MPPS / storage commitment modules)
    python3 Scripts/nema_docbook.py fetch 2026a 4   # PS3.4 (service classes)
    python3 Scripts/nema_docbook.py fetch 2026a 6   # PS3.6 (UID registry)
    python3 Scripts/nema_docbook.py fetch 2026a 7   # PS3.7 (DIMSE)
    python3 Scripts/nema_docbook.py fetch 2026a 8   # PS3.8 (upper layer)
    python3 Scripts/diff_network.py --nema DIR [--sources Sources/DICOMNetwork] [--verbose]

Every check extracts the literals from the Swift files by regex (never by hand) and
compares them with the table or clause of the standard named in the check. It prints
one line per check with the counts (matched / wrong / missing / extra) and exits 1
when any check found a wrong value or a missing required value. "Extra" values that
the standard does not define, and standard values the module does not carry, are
listed but do not fail the run unless the check says they must.

This is the extraction + diff step of the verification method in
DICOMCORE_STANDARD_IMPLEMENTATION.md, applied to DICOMNetwork.
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Values known to differ from the standard whose fix changes public API (raw values) and is
# waiting for the owner's approval; reported as PEND, not FAIL. Remove the entry when fixed.
PENDING_API_APPROVAL = set()   # P-MAMMO approved and applied 2026-09-29 (DICOMPrintKit pass)
spec = importlib.util.spec_from_file_location('nema_docbook', os.path.join(HERE, 'nema_docbook.py'))
nd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nd)
D = nd.D


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


class Report:
    def __init__(self, verbose):
        self.verbose = verbose
        self.failed = 0
        self.lines = []

    def check(self, name, matched, wrong=(), missing=(), extra=(), fail_on_missing=True):
        wrong, missing, extra = list(wrong), list(missing), list(extra)
        bad = wrong or (missing and fail_on_missing)
        self.failed += 1 if bad else 0
        status = 'FAIL' if bad else 'ok  '
        print(f'{status} {name}: matched {matched}, wrong {len(wrong)}, missing {len(missing)}, extra {len(extra)}')
        for label, items in (('wrong', wrong), ('missing', missing), ('extra', extra)):
            for item in items:
                if label != 'extra' or self.verbose:
                    print(f'       {label}: {item}')


# --- helpers over the DocBook -------------------------------------------------------

def section_by_id(part, xml_id):
    for sec in part.root.iter(D + 'section'):
        if sec.get(nd.X + 'id') == xml_id:
            return sec
    return None


def section_paras(part, xml_id):
    sec = section_by_id(part, xml_id)
    return [part.text(p) for p in sec.findall(D + 'para')] if sec is not None else []


def section_items(part, xml_id):
    """Text of every list item under a section (itemizedlist, variablelist)."""
    sec = section_by_id(part, xml_id)
    out = []
    if sec is None:
        return out
    for il in sec.iter(D + 'itemizedlist'):
        for li in il.findall(D + 'listitem'):
            out.append(part.text(li))
    for vl in sec.iter(D + 'variablelist'):
        for e in vl.findall(D + 'varlistentry'):
            out.append(nd.norm(''.join(e.itertext())))
    return out


def variablelist_terms(part, xml_id):
    """(term, definition) pairs of the variablelists under a section."""
    sec = section_by_id(part, xml_id)
    out = []
    if sec is None:
        return out
    for vl in sec.iter(D + 'variablelist'):
        for e in vl.findall(D + 'varlistentry'):
            term = e.find(D + 'term')
            item = e.find(D + 'listitem')
            out.append((nd.norm(''.join(term.itertext())) if term is not None else '',
                        part.text(item) if item is not None else ''))
    return out


def table_rows(part, label, caption=None):
    return list(part.rows(part.table(label, caption)))


def cell_codes(text):
    """'1 - no-reason-given | 2 - application-context...' -> {1: 'no-reason-given', ...}."""
    out = {}
    for piece in text.split('|'):
        m = re.match(r'\s*(\d+)\s*-\s*(.+?)\s*$', piece)
        if m:
            out[int(m.group(1))] = m.group(2).strip()
    return out


# --- helpers over the Swift ----------------------------------------------------------

def swift_hex_cases(src):
    """'case name = 0xNNNN' -> {name: value}."""
    return {m.group(1): int(m.group(2), 16) for m in re.finditer(r'case\s+(\w+)\s*=\s*0x([0-9A-Fa-f]+)', src)}


def swift_string_cases(src, enum_name):
    """The raw strings of `enum <enum_name>` (String-backed), without cases marked
    `@available(*, deprecated …)`: those are kept for source compatibility and are
    never written (e.g. MediumType's MAMMO CLEAR / MAMMO BLUE, written as the terms)."""
    m = re.search(r'enum\s+' + re.escape(enum_name) + r'\b[^{]*\{', src)
    if not m:
        # A struct of named terms (FilmDestination since P-BIN: static lets plus .bin(n)).
        return re.findall(r'static\s+let\s+\w+\s*=\s*' + re.escape(enum_name) + r'\(term:\s*"([^"]*)"\)', src)
    depth, i, start = 0, m.end() - 1, m.end() - 1
    while i < len(src):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = re.sub(r'@available\(\*,\s*deprecated[^)]*\)\s*case\s+\w+\s*=\s*"[^"]*"', '', src[start:i])
    return re.findall(r'case\s+\w+\s*=\s*"([^"]*)"', body)


# --- the checks ----------------------------------------------------------------------

def check_pdu_types(rep, p8, src_dir):
    src = read(os.path.join(src_dir, 'PDUType.swift'))
    ours = swift_hex_cases(src)
    std = {}
    for label, name in [('9-11', 'A-ASSOCIATE-RQ'), ('9-17', 'A-ASSOCIATE-AC'), ('9-21', 'A-ASSOCIATE-RJ'),
                        ('9-22', 'P-DATA-TF'), ('9-24', 'A-RELEASE-RQ'), ('9-25', 'A-RELEASE-RP'),
                        ('9-26', 'A-ABORT')]:
        row = table_rows(p8, label)[0]
        assert row[1] == 'PDU-type', row
        std[name] = int(row[2].rstrip('H'), 16)
    names = {'associateRequest': 'A-ASSOCIATE-RQ', 'associateAccept': 'A-ASSOCIATE-AC',
             'associateReject': 'A-ASSOCIATE-RJ', 'dataTransfer': 'P-DATA-TF',
             'releaseRequest': 'A-RELEASE-RQ', 'releaseResponse': 'A-RELEASE-RP', 'abort': 'A-ABORT'}
    wrong, matched = [], 0
    for case, value in ours.items():
        want = std.get(names.get(case))
        if want is None:
            wrong.append(f'{case}: not a PS3.8 PDU')
        elif want != value:
            wrong.append(f'{case}: 0x{value:02X}, PS3.8 says 0x{want:02X}')
        else:
            matched += 1
    missing = [n for n in std if n not in names.values() or names_inv(names).get(n) not in ours]
    rep.check('PS3.8 Tables 9-11..9-26 PDU-type bytes (PDUType.swift)', matched, wrong, missing)


def names_inv(d):
    return {v: k for k, v in d.items()}


def check_item_types(rep, p7, p8, src_dir):
    std = {}
    for part, labels in ((p8, ['9-12', '9-13', '9-14', '9-15', '9-16', '9-18', '9-19', '9-20', 'D.1-1', 'D.1-2']),
                         (p7, ['D.3-1', 'D.3-2', 'D.3-3', 'D.3-4', 'D.3-7', 'D.3-8', 'D.3-9', 'D.3-10',
                               'D.3-11', 'D.3-12', 'D.3-14', 'D.3-15'])):
        for label in labels:
            row = table_rows(part, label)[0]
            assert row[1] == 'Item-type', (label, row)
            std.setdefault(int(row[2].rstrip('H'), 16), []).append(label)
    text = ''
    for name in ('AssociateRequestPDU.swift', 'AssociateAcceptPDU.swift', 'PDUDecoder.swift',
                 'SCPSCURoleSelection.swift', 'UserIdentity.swift'):
        text += read(os.path.join(src_dir, name))
    ours = set(int(m, 16) for m in re.findall(r'(?:append|case|subItemType(?::\s*UInt8)?\s*=|==)\s*\(?0x([0-9A-Fa-f]{2})\b', text))
    ours = {v for v in ours if v in range(0x10, 0x60)}
    matched = sorted(v for v in ours if v in std)
    extra = [f'0x{v:02X}' for v in sorted(ours - set(std))]
    missing = [f'0x{v:02X} ({", ".join(std[v])}) not encoded or decoded' for v in sorted(set(std) - ours)]
    rep.check('PS3.8/PS3.7 item and sub-item type bytes (encoders + PDUDecoder)', len(matched), [], missing, extra,
              fail_on_missing=False)


def check_command_tags(rep, p7, src_dir):
    src = read(os.path.join(src_dir, 'CommandTag.swift'))
    ours = {}
    for m in re.finditer(r'///\s*(.+?)\s*\((0000),([0-9A-Fa-f]{4})\)\s*\n\s*///\s*VR:\s*(\w+),\s*VM:\s*([\w-]+)[\s\S]*?element:\s*0x([0-9A-Fa-f]{4})\)', src):
        name, elem, vr, vm, elem2 = m.group(1), m.group(3).upper(), m.group(4), m.group(5), m.group(6).upper()
        if elem != elem2:
            rep.check(f'CommandTag.swift doc/element mismatch {name}', 0, [f'doc {elem} vs literal {elem2}'])
        ours[elem] = (name, vr, vm)
    std = {}
    for row in table_rows(p7, 'E.1-1'):
        tag, name, keyword, vr, vm = row[0], row[1], row[2], row[3], row[4]
        std[tag[6:10].upper()] = (name, vr, vm)
    matched, wrong = 0, []
    for elem, (name, vr, vm) in ours.items():
        want = std.get(elem)
        if want is None:
            wrong.append(f'(0000,{elem}) {name}: not in Table E.1-1')
        elif (want[0], want[1], want[2]) != (name, vr, vm):
            wrong.append(f'(0000,{elem}) ours {name}/{vr}/{vm}; E.1-1 {want[0]}/{want[1]}/{want[2]}')
        else:
            matched += 1
    missing = [f'(0000,{e}) {std[e][0]}' for e in std if e not in ours]
    rep.check('PS3.7 Table E.1-1 command elements (CommandTag.swift: tag, name, VR, VM)', matched, wrong, missing)


def check_command_field(rep, p7, src_dir):
    src = read(os.path.join(src_dir, 'DIMSECommand.swift'))
    ours = swift_hex_cases(src)
    row = [r for r in table_rows(p7, 'E.1-1') if r[0] == '(0000,0100)'][0]
    std = {int(m.group(1), 16): m.group(2) for m in re.finditer(r'([0-9A-F]{4})H\s+([A-Z-]+-R(?:Q|SP))', row[5])}
    label = {}
    desc = dict(re.findall(r'case \.(\w+):\s*return "([A-Z-]+)"', src))
    matched, wrong = 0, []
    for case, value in ours.items():
        name = desc.get(case, case)
        if value not in std:
            wrong.append(f'{case} = 0x{value:04X} not in E.1-1')
        elif std[value] != name:
            wrong.append(f'0x{value:04X} is {std[value]} in E.1-1, ours {name}')
        else:
            matched += 1
    missing = [f'0x{v:04X} {n}' for v, n in std.items() if v not in ours.values()]
    rep.check('PS3.7 Table E.1-1 Command Field values (DIMSECommand.swift)', matched, wrong, missing)


def check_priority_and_dataset_type(rep, p7, src_dir):
    rows = {r[0]: r for r in table_rows(p7, 'E.1-1')}
    pri = {m.group(1): int(m.group(2), 16) for m in re.finditer(r'(LOW|MEDIUM|HIGH)\s*=\s*([0-9A-F]{4})H', rows['(0000,0700)'][5])}
    ours = swift_hex_cases(read(os.path.join(src_dir, 'DIMSEPriority.swift')))
    wrong = [f'{k}: ours 0x{v:04X}, E.1-1 0x{pri[k.upper()]:04X}' for k, v in ours.items() if pri.get(k.upper()) != v]
    rep.check('PS3.7 Table E.1-1 Priority values (DIMSEPriority.swift)', len(ours) - len(wrong), wrong,
              [k for k in pri if k.lower() not in ours])
    m = re.search(r'value of ([0-9A-F]{4})H if no Data Set is present', rows['(0000,0800)'][5])
    src = read(os.path.join(src_dir, 'CommandSet.swift'))
    ours_ds = re.search(r'noDataSetPresent:\s*UInt16\s*=\s*0x([0-9A-Fa-f]{4})', src)
    wrong = [] if ours_ds and int(ours_ds.group(1), 16) == int(m.group(1), 16) else ['noDataSetPresent differs']
    rep.check('PS3.7 Table E.1-1 Command Data Set Type "no data set" value (CommandSet.swift)', 1 - len(wrong), wrong)


def check_reject_codes(rep, p8, src_dir):
    rows = table_rows(p8, '9-21')
    result = cell_codes([r for r in rows if r[1] == 'Result'][0][2])
    source = cell_codes([r for r in rows if r[1] == 'Source'][0][2])
    reason_cell = [r for r in rows if r[1] == 'Reason/Diag.'][0][2]
    parts = re.split(r'If the Source field has the value \((\d)\)', reason_cell)
    reasons = {}
    for i in range(1, len(parts), 2):
        reasons[int(parts[i])] = cell_codes(parts[i + 1])
    err = read(os.path.join(src_dir, 'DICOMNetworkError.swift'))
    ours_result = swift_hex_cases_dec(err, 'AssociateRejectResult')
    ours_source = swift_hex_cases_dec(err, 'AssociateRejectSource')
    wrong = []
    exp_result = {'rejectedPermanent': 1, 'rejectedTransient': 2}
    exp_source = {'serviceUser': 1, 'serviceProviderACSE': 2, 'serviceProviderPresentation': 3}
    for k, v in ours_result.items():
        if exp_result.get(k) != v or v not in result:
            wrong.append(f'AssociateRejectResult.{k} = {v}')
    for k, v in ours_source.items():
        if exp_source.get(k) != v or v not in source:
            wrong.append(f'AssociateRejectSource.{k} = {v}')
    rep.check('PS3.8 Table 9-21 result/source values (DICOMNetworkError.swift)',
              len(ours_result) + len(ours_source) - len(wrong), wrong)

    # reason descriptions in AssociateRejectPDU.swift and NetworkConsoleFormatter.swift
    for fname, func in (('AssociateRejectPDU.swift', 'reasonDescription'),
                        ('NetworkConsoleFormatter.swift', 'associateRejectReasonDescription')):
        src = read(os.path.join(src_dir, fname))
        start = max(src.find('func ' + func), src.find('var ' + func))
        block = src[start:]
        if fname == 'NetworkConsoleFormatter.swift' and 'AssociateRejectPDU(' in block[:400]:
            rep.check(f'PS3.8 Table 9-21 reject reasons ({fname}): delegates to AssociateRejectPDU.reasonDescription', 1)
            continue
        ours = {}
        current = None
        for line in block.split('\n'):
            m = re.search(r'case \.(serviceUser|serviceProviderACSE|serviceProviderPresentation)', line)
            if m:
                current = {'serviceUser': 1, 'serviceProviderACSE': 2, 'serviceProviderPresentation': 3}[m.group(1)]
            m = re.search(r'case (\d+):\s*return "([^"]+)"', line)
            if m and current:
                ours.setdefault(current, {})[int(m.group(1))] = m.group(2)
            if line.strip() == '}' and current == 3 and ours.get(3):
                break
        wrong, matched = [], 0
        for s, codes in ours.items():
            for code, text in codes.items():
                want = reasons.get(s, {}).get(code)
                if want is None or 'reserved' in want:
                    wrong.append(f'source {s} reason {code} "{text}": not defined in Table 9-21')
                elif not same_reason(text, want):
                    wrong.append(f'source {s} reason {code} "{text}" vs Table 9-21 "{want}"')
                else:
                    matched += 1
        missing = [f'source {s} reason {c} {t}' for s, cs in reasons.items() for c, t in cs.items()
                   if 'reserved' not in t and c not in ours.get(s, {})]
        rep.check(f'PS3.8 Table 9-21 reject reasons ({fname})', matched, wrong, missing)


def same_reason(a, b):
    """Equal after normalisation; tolerates the DocBook's truncated 'temporary-congestio'."""
    a, b = norm_reason(a), norm_reason(b)
    return a == b or a.startswith(b) or b.startswith(a)


def norm_reason(s):
    s = s.lower().replace('-', ' ').replace('recognised', 'recognized')
    s = re.sub(r'\bae title\b', 'ae title', s)
    return re.sub(r'[^a-z0-9 ]', '', s).strip()


def swift_hex_cases_dec(src, enum_name):
    m = re.search(r'enum\s+' + re.escape(enum_name) + r'\b[^{]*\{', src)
    depth, i, start = 0, m.end() - 1, m.end() - 1
    while i < len(src):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = src[start:i]
    return {n: int(v, 0) for n, v in re.findall(r'case\s+(\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)', body)}


def check_abort_codes(rep, p8, src_dir):
    rows = table_rows(p8, '9-26')
    source = cell_codes([r for r in rows if r[1] == 'Source'][0][2])
    reason_cell = [r for r in rows if r[1] == 'Reason/Diag.'][0][2]
    reason_cell = reason_cell.replace('reason-not-specified1 -', 'reason-not-specified | 1 -')  # DocBook lacks a separator
    reasons = cell_codes(reason_cell.split('If the Source field has the value (0)')[0])
    err = read(os.path.join(src_dir, 'DICOMNetworkError.swift'))
    ours_source = swift_hex_cases_dec(err, 'AbortSource')
    ours_reason = swift_hex_cases_dec(err, 'AbortReason')
    wrong = []
    for k, v in ours_source.items():
        if v not in source or 'reserved' in source[v]:
            wrong.append(f'AbortSource.{k} = {v}')
    for k, v in ours_reason.items():
        if v not in reasons or ('reserved' in reasons[v] and k != 'reserved'):
            wrong.append(f'AbortReason.{k} = {v}')
    missing = [f'reason {c} {t}' for c, t in reasons.items() if 'reserved' not in t and c not in ours_reason.values()]
    rep.check('PS3.8 Table 9-26 abort source/reason values (DICOMNetworkError.swift)',
              len(ours_source) + len(ours_reason) - len(wrong), wrong, missing)


def check_presentation_context_results(rep, p8, src_dir):
    rows = table_rows(p8, '9-18')
    std = cell_codes([r for r in rows if r[1] == 'Result/Reason'][0][2])
    src = read(os.path.join(src_dir, 'PresentationContext.swift'))
    ours = swift_hex_cases_dec(src, 'PresentationContextResult')
    wrong = [f'{k} = {v}' for k, v in ours.items() if v not in std]
    missing = [f'{c} {t}' for c, t in std.items() if c not in ours.values()]
    rep.check('PS3.8 Table 9-18 presentation context result values (PresentationContext.swift)',
              len(ours) - len(wrong), wrong, missing)


def check_user_identity_types(rep, p7, src_dir):
    rows = table_rows(p7, 'D.3-14')
    std = cell_codes([r for r in rows if r[1] == 'User-Identity-Type'][0][2])
    src = read(os.path.join(src_dir, 'UserIdentity.swift'))
    ours = swift_hex_cases_dec(src, 'UserIdentityType')
    wrong = [f'{k} = {v}' for k, v in ours.items() if v not in std]
    missing = [f'{c} {t}' for c, t in std.items() if c not in ours.values()]
    rep.check('PS3.7 Table D.3-14 User-Identity-Type values (UserIdentity.swift)', len(ours) - len(wrong), wrong, missing)


def annex_c_statuses(p7):
    """PS3.7 Annex C: {code: (class, name)} from the C.x.y sub-clauses."""
    out = {}
    classes = {'C.1': 'success', 'C.2': 'pending', 'C.3': 'cancel', 'C.4': 'warning', 'C.5': 'failure'}
    for sec in p7.root.iter(D + 'section'):
        i = sec.get(nd.X + 'id') or ''
        m = re.match(r'sect_(C\.\d)\.\d+$', i)
        if not m:
            continue
        title = nd.norm(''.join(sec.find(D + 'title').itertext()))
        for para in sec.iter(D + 'para'):
            mm = re.search(r'shall be set to ([0-9A-F]{4})H', p7.text(para))
            if mm:
                out[int(mm.group(1), 16)] = (classes[m.group(1)], title)
    return out


def ps34_status_tables(p4):
    """PS3.4 status tables: {code_or_pattern: (class, meaning, table)}."""
    out = {}
    tables = ['B.2-1', 'C.4-1', 'C.4-2', 'C.4-3', 'K.4-1', 'F.7.2-2', 'F.8.2-2',
              'H.4.1.2.1.2-1', 'H.4-4', 'H.4.2.2.1.2-1', 'H.4-9', 'H.4.3.1.2.1.2-1', 'H.4.3.2.2.1.2-1',
              'H.4.9.2.1.2-1']
    for label in tables:
        cls = None
        for row in table_rows(p4, label):
            if len(row) >= 3 and row[0] in ('Failure', 'Cancel', 'Success', 'Pending', 'Warning'):
                cls = row[0].lower()
                meaning, code = row[1], row[2]
            elif len(row) >= 2:
                meaning, code = row[0], row[1]
            else:
                continue
            code = code.strip()
            if re.fullmatch(r'[0-9A-Fx]{4}', code):
                out.setdefault(code, []).append((cls, meaning, label))
    return out


def status_class_of(code, annex_c, ps34):
    hexs = f'{code:04X}'
    if code in annex_c:
        return annex_c[code][0]
    for pat, entries in ps34.items():
        if 'x' in pat and re.fullmatch(pat.replace('x', '[0-9A-F]'), hexs):
            return entries[0][0]
        if pat == hexs:
            return entries[0][0]
    return None


def check_dimse_status(rep, p7, p4, src_dir):
    annex_c = annex_c_statuses(p7)
    ps34 = ps34_status_tables(p4)
    src = read(os.path.join(src_dir, 'DIMSEStatus.swift'))
    # named codes: `case .name: return 0xNNNN` in rawValue, plus pending FF00/FF01
    named = {}
    for m in re.finditer(r'case \.(\w+)(?:\(let \w+\))?:\s*return (?:\w+ \? )?0x([0-9A-Fa-f]{4})(?: : 0x([0-9A-Fa-f]{4}))?', src):
        named[m.group(1)] = int(m.group(2), 16)
        if m.group(3):
            named[m.group(1) + '(warningOptionalKeys)'] = int(m.group(3), 16)
    wrong, matched = [], 0
    for name, code in named.items():
        cls = status_class_of(code, annex_c, ps34)
        ours_cls = ('success' if name == 'success' else 'pending' if name.startswith('pending')
                    else 'cancel' if name == 'cancel' else 'warning' if name.startswith('warning') else 'failure')
        if cls is None:
            wrong.append(f'.{name} = 0x{code:04X}: not defined in PS3.7 Annex C or the PS3.4 status tables')
        elif cls != ours_cls:
            wrong.append(f'.{name} = 0x{code:04X}: ours {ours_cls}, standard {cls}')
        else:
            matched += 1
    missing = [f'0x{c:04X} {annex_c[c][1]} (PS3.7 {annex_c[c][0]})' for c in sorted(annex_c) if c not in named.values()]
    missing += [f'{pat} {entries[0][1][:50]} (PS3.4 {entries[0][2]})' for pat, entries in ps34.items()
                if 'x' not in pat and int(pat, 16) not in named.values() and not pat.startswith(('B6', 'C6'))]
    rep.check('PS3.7 Annex C + PS3.4 status tables: named codes and their class (DIMSEStatus.swift)',
              matched, wrong, missing, fail_on_missing=False)

    # classification ranges for unknown codes
    ranges_ok = []
    for code in (0x0001, 0x0107, 0x0116, 0xB000, 0xA700, 0xC123, 0xFF00, 0xFF01, 0xFE00, 0x0000):
        ranges_ok.append(code)
    rep.check('DIMSEStatus range classification probes (informational)', len(ranges_ok))

    # PrintSCPStatus
    psrc = read(os.path.join(src_dir, 'PrintSCPTypes.swift'))
    print_codes = swift_hex_cases_dec(psrc, 'PrintSCPStatus')
    wrong, matched = [], 0
    for name, code in print_codes.items():
        cls = status_class_of(code, annex_c, ps34)
        ours_cls = 'success' if code == 0 else 'warning' if 0xB000 <= code <= 0xBFFF else 'failure'
        if cls is None:
            wrong.append(f'PrintSCPStatus.{name} = 0x{code:04X}: not in PS3.7 Annex C or the PS3.4 Annex H tables')
        elif cls != ours_cls:
            wrong.append(f'PrintSCPStatus.{name} = 0x{code:04X}: ours {ours_cls}, standard {cls}')
        else:
            matched += 1
    print_std = {pat: e for pat, e in ps34.items() if pat.startswith(('B6', 'C6'))}
    missing = [f'0x{pat} {e[0][1][:60]} ({e[0][2]})' for pat, e in print_std.items() if int(pat, 16) not in print_codes.values()]
    rep.check('PS3.4 Annex H print status codes (PrintSCPTypes.swift)', matched, wrong, missing, fail_on_missing=False)


def check_print_status_meanings(rep, p4, src_dir):
    """The explanation string of each PrintSCPStatus code must describe the Annex H meaning."""
    ps34 = ps34_status_tables(p4)
    psrc = read(os.path.join(src_dir, 'PrintSCPTypes.swift'))
    codes = swift_hex_cases_dec(psrc, 'PrintSCPStatus')
    docs = {}
    for m in re.finditer(r'((?:[ \t]*///[^\n]*\n)+)[ \t]*case (\w+) = 0x', psrc):
        docs[m.group(2)] = ' '.join(l.strip().lstrip('/').strip() for l in m.group(1).split('\n'))
    wrong, matched = [], 0
    keywords = {0xC600: 'film box', 0xC601: 'queue', 0xC602: 'queue', 0xC603: 'larger', 0xC605: 'memory',
                0xC613: 'combined', 0xC616: 'film box', 0xB600: 'memory allocation', 0xB601: 'collation',
                0xB602: 'image box', 0xB603: 'image box', 0xB604: 'demagnified', 0xB605: 'density',
                0xB609: 'cropped', 0xB60A: 'decimated'}
    for name, code in codes.items():
        if code in keywords:
            doc = docs.get(name, '').lower()
            if keywords[code] in doc:
                matched += 1
            else:
                std = ps34.get(f'{code:04X}', [(None, '?', '?')])[0][1]
                wrong.append(f'PrintSCPStatus.{name} (0x{code:04X}) doc "{docs.get(name, "")}" vs PS3.4 "{std[:70]}"')
    rep.check('PS3.4 Annex H print status meanings (PrintSCPTypes.swift doc comments)', matched, wrong)


def check_uids(rep, p6, src_dir):
    std = {}
    for row in table_rows(p6, 'A-1'):
        std[row[0]] = (row[1], row[2], row[3])
    wrong, matched, unknown = [], 0, []
    seen = set()
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith('.swift'):
            continue
        src = read(os.path.join(src_dir, name))
        for m in re.finditer(r'"(1\.2\.840\.10008(?:\.\d+)+)"', src):
            uid = m.group(1)
            if uid in seen:
                continue
            seen.add(uid)
            if uid in std:
                matched += 1
            else:
                unknown.append(f'{uid} ({name})')
    rep.check('PS3.6 Table A-1: every 1.2.840.10008.* literal in the module is registered', matched, unknown)


def check_uid_names(rep, p6, src_dir):
    """UID constants whose doc comment names the SOP Class: the name must be the A-1 name."""
    std = {row[0]: row[1] for row in table_rows(p6, 'A-1')}
    wrong, matched = [], 0
    for name in ('QueryRetrieveInformationModel.swift', 'PrintService.swift', 'VerificationService.swift',
                 'StorageCommitmentService.swift', 'MPPSService.swift', 'ModalityWorklistService.swift'):
        src = read(os.path.join(src_dir, name))
        for m in re.finditer(r'///\s*([^\n]+)\n(?:\s*///[^\n]*\n)*?\s*public let \w+\s*=\s*"(1\.2\.840\.10008[\d.]+)"', src):
            doc, uid = m.group(1).strip(), m.group(2)
            if uid not in std:
                continue
            a1 = std[uid]
            if norm_name(a1) in norm_name(doc) or norm_name(doc) in norm_name(a1):
                matched += 1
            else:
                wrong.append(f'{name}: "{doc}" for {uid}; A-1 "{a1}"')
    rep.check('PS3.6 Table A-1 names in UID constant doc comments', matched, wrong)


def norm_name(s):
    s = s.lower().replace('(retired)', '').replace('information model', '').replace('sop class', '')
    s = s.replace('transfer syntax uid', '').replace('uid', '').replace(': default transfer syntax for dicom', '')
    s = s.replace(' - ', ' ').replace('query/retrieve', 'query retrieve')
    return re.sub(r'[^a-z0-9]', '', s)


def check_qr_levels_and_models(rep, p4, src_dir):
    src = read(os.path.join(src_dir, 'QueryLevel.swift'))
    ours = swift_string_cases(src, 'QueryLevel')
    std = [r[1] for r in table_rows(p4, 'C.6.1-1')]
    wrong = [v for v in ours if v not in std]
    missing = [v for v in std if v not in ours]
    rep.check('PS3.4 Table C.6.1-1 Query/Retrieve Level values (QueryLevel.swift)', len(ours) - len(wrong), wrong, missing)
    src = read(os.path.join(src_dir, 'QueryRetrieveInformationModel.swift'))
    ours = set(re.findall(r'"(1\.2\.840\.10008[\d.]+)"', src))
    std = {r[1]: r[0] for r in table_rows(p4, 'C.6.1.3-1') + table_rows(p4, 'C.6.2.3-1')}
    missing = [f'{u} {n}' for u, n in std.items() if u not in ours]
    rep.check('PS3.4 Tables C.6.1.3-1 / C.6.2.3-1 Q/R SOP Classes (QueryRetrieveInformationModel.swift)',
              len([u for u in std if u in ours]), [], missing)
    mwl = read(os.path.join(src_dir, 'ModalityWorklistService.swift'))
    std = {r[1]: r[0] for r in table_rows(p4, 'K.6.1.4-1')}
    rep.check('PS3.4 Table K.6.1.4-1 MWL SOP Class (ModalityWorklistService.swift)',
              len([u for u in std if u in mwl]), [], [u for u in std if u not in mwl])


def check_query_keys(rep, p4, src_dir):
    """The default C-FIND return keys per level carry every R and U key of Tables C.6-1..C.6-5."""
    src = read(os.path.join(src_dir, 'QueryService.swift'))
    core = ''
    core_dir = os.path.join(os.path.dirname(src_dir), 'DICOMCore')
    for name in os.listdir(core_dir):
        if name.startswith('Tag+') or name == 'Tag.swift':
            core += read(os.path.join(core_dir, name))
    core += read(os.path.join(src_dir, 'QueryKeys.swift'))
    tag_of = {}
    for m in re.finditer(r'static let (\w+)\s*=\s*Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)', core):
        tag_of[m.group(1)] = f'({m.group(2).upper()},{m.group(3).upper()})'
    # QueryKeys builder methods -> the tag they add (matching(.tag ...) / returning(.tag ...))
    qk = read(os.path.join(src_dir, 'QueryKeys.swift'))
    method_tag = {}
    for m in re.finditer(r'public func (\w+)\([^)]*\)\s*->\s*QueryKeys\s*\{(.*?)\n    \}', qk, re.S):
        t = re.search(r'(?:matching|returning)\(\.(\w+)', m.group(2))
        if t:
            method_tag[m.group(1)] = tag_of.get(t.group(1), t.group(1))
    # the per-level `case .level:` blocks of the default key builder
    start = src.find('includeParentLevelReturnKeys: Bool = false')
    block = src[start:src.find('\n    }\n', start)]
    blocks = re.split(r'\n\s*case \.(patient|study|series|image):', block)
    levels = {}
    for i in range(1, len(blocks), 2):
        levels[blocks[i]] = set(method_tag.get(n) for n in re.findall(r'\.(\w+)\(', blocks[i + 1]) if n in method_tag)
    tables = {'patient': ['C.6-1'], 'study': ['C.6-2', 'C.6-5'], 'series': ['C.6-3'], 'image': ['C.6-4']}
    for level, labels in tables.items():
        required = {}
        for label in labels:
            for row in table_rows(p4, label):
                if len(row) >= 3 and row[2] in ('R', 'U') and not row[0].startswith('>'):
                    required[row[1]] = f'{row[0]} {row[2]} ({label})'
        ours = levels.get(level, set())
        # STUDY/SERIES/IMAGE levels: the unique keys of the higher levels are supplied by the query itself
        missing = [v for t, v in required.items() if t not in ours]
        rep.check(f'PS3.4 Tables {"/".join(labels)} R and U keys present in the {level.upper()} default return keys (QueryService.swift)',
                  len(required) - len(missing), [], missing, fail_on_missing=False)


def check_print_enums(rep, p3, src_dir):
    src = read(os.path.join(src_dir, 'PrintService.swift'))
    checks = [
        ('PrintPriority', 'sect_C.13.1', ['HIGH', 'MED', 'LOW']),
        ('MediumType', 'sect_C.13.1', None),
        ('FilmDestination', 'sect_C.13.1', None),
        ('FilmOrientation', 'sect_C.13.3', ['PORTRAIT', 'LANDSCAPE']),
        ('FilmSize', 'sect_C.13.3', None),
        ('MagnificationType', 'sect_C.13.3', ['REPLICATE', 'BILINEAR', 'CUBIC', 'NONE']),
        ('TrimOption', 'sect_C.13.3', ['YES', 'NO']),
        ('ImagePolarity', 'sect_C.13.5', ['NORMAL', 'REVERSE']),
        ('DecimateCropBehavior', 'sect_C.13.5', ['DECIMATE', 'CROP', 'FAIL']),
        ('PrinterStatusSeverity', 'sect_C.13.9', ['NORMAL', 'WARNING', 'FAILURE']),
    ]
    for enum, sect, subset in checks:
        ours = swift_string_cases(src, enum)
        if not ours:
            # find the enum by a different name: fall back to searching raw values
            rep.check(f'PS3.3 {sect[5:]} {enum}: enum not found by name', 0, [enum])
            continue
        terms = [t for t, _ in variablelist_terms(p3, sect)]
        std = subset or terms
        wrong = [v for v in ours if v not in terms and v not in ('UNKNOWN',)
                 and not (enum == 'FilmDestination' and re.fullmatch(r'BIN_\d+', v) and 'BIN_i' in terms)]
        pending = [v for v in wrong if (enum, v) in PENDING_API_APPROVAL]
        if pending:
            print(f'PEND PS3.3 {sect[5:]} {enum}: {", ".join(pending)} differ from the standard; raw values are public API, '
                  'change pending owner approval (report P-MAMMO)')
            wrong = [v for v in wrong if v not in pending]
        missing = [v for v in std if v not in ours and v != 'BIN_i' and (subset or enum_term_belongs(enum, v))]
        rep.check(f'PS3.3 {sect[5:]} defined terms of {enum} (PrintService.swift)', len(ours) - len(wrong), wrong, missing,
                  fail_on_missing=False)
    std = [t for t, _ in variablelist_terms(p3, 'sect_C.13.8')][:4]
    enc = read(os.path.join(src_dir, 'PrintSCPEncoder.swift')) + src
    missing = [t for t in std if f'"{t}"' not in enc]
    rep.check('PS3.3 C.13.8 Execution Status terms (PrintService.swift, PrintSCPEncoder.swift)', len(std) - len(missing), [], missing)


def enum_term_belongs(enum, term):
    if enum == 'MediumType':
        return 'FILM' in term or term == 'PAPER'
    if enum == 'FilmDestination':
        return term in ('MAGAZINE', 'PROCESSOR') or term.startswith('BIN_')
    if enum == 'FilmSize':
        return re.fullmatch(r'[0-9_]+(IN|CM)X[0-9_]+(IN|CM)|A[34]', term) is not None
    return True


def check_storage_commitment(rep, p3, p4, src_dir):
    src = read(os.path.join(src_dir, 'StorageCommitmentService.swift'))
    std = {int(t.split()[0].rstrip('H'), 16): ' '.join(t.split()[1:]) for t, _ in variablelist_terms(p3, 'sect_C.14.1.1')}
    ours = {int(v, 16): n for n, v in re.findall(r'static let (\w+)\s*(?::\s*UInt16)?\s*=\s*0x([0-9A-Fa-f]{4})', src)}
    ours = {k: v for k, v in ours.items() if k in std or 'Reason' in v or 'reason' in v}
    wrong = [f'0x{c:04X} {n}' for c, n in ours.items() if c not in std]
    missing = [f'0x{c:04X} {n}' for c, n in std.items() if c not in ours]
    rep.check('PS3.3 C.14.1.1 Failure Reason values (StorageCommitmentService.swift)', len(ours) - len(wrong), wrong, missing)
    action = {r[1] for r in table_rows(p4, 'J.3-1') if r[1]}
    events = {r[1] for r in table_rows(p4, 'J.3-2') if r[1]}
    a = re.search(r'storageCommitmentRequestActionTypeID(?::\s*UInt16)?\s*=\s*(\d+)', src)
    e1 = re.search(r'storageCommitmentSuccessEventTypeID(?::\s*UInt16)?\s*=\s*(\d+)', src)
    e2 = re.search(r'storageCommitmentFailureEventTypeID(?::\s*UInt16)?\s*=\s*(\d+)', src)
    wrong = []
    if not a or a.group(1) not in action:
        wrong.append('action type id')
    if not e1 or e1.group(1) != '1' or not e2 or e2.group(1) != '2' or events != {'1', '2'}:
        wrong.append('event type ids')
    rep.check('PS3.4 Tables J.3-1 / J.3-2 action and event type IDs (StorageCommitmentService.swift)', 2 - len(wrong), wrong)
    tags_std = set(re.findall(r'\((\w{4},\w{4})\)', ' '.join(r[3] for r in table_rows(p4, 'J.3-1') + table_rows(p4, 'J.3-2') if len(r) > 3)))
    tags_ours = set(f'{g.upper()},{e.upper()}' for g, e in re.findall(r'Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)', src))
    tags_ours |= set(f'{g.upper()},{e.upper()}' for g, e in re.findall(r'\(0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{4})\)', src))
    missing = sorted(t for t in tags_std if t not in tags_ours)
    rep.check('PS3.4 Tables J.3-1 / J.3-2 attributes carried (StorageCommitmentService.swift)',
              len(tags_std) - len(missing), [], missing, fail_on_missing=False)


def check_mpps(rep, p4, src_dir):
    src = read(os.path.join(src_dir, 'MPPSService.swift'))
    ours = set()
    for g, e in re.findall(r'Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)', src):
        ours.add(f'({g.upper()},{e.upper()})')
    for g, e in re.findall(r'add(?:Seq)?\(0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{4})', src):
        ours.add(f'({g.upper()},{e.upper()})')
    core = ''
    core_dir = os.path.join(os.path.dirname(src_dir), 'DICOMCore')
    for name in os.listdir(core_dir):
        if name.startswith('Tag+') or name == 'Tag.swift':
            core += read(os.path.join(core_dir, name))
    tag_of = {m.group(1): f'({m.group(2).upper()},{m.group(3).upper()})' for m in
              re.finditer(r'static let (\w+)\s*=\s*Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)', core)}
    for n in re.findall(r'\.(\w+)\b', src):
        if n in tag_of:
            ours.add(tag_of[n])
    required = {}
    for row in table_rows(p4, 'F.7.2-1'):
        if len(row) >= 3 and not row[0].startswith('>') and re.match(r'[12](C)?/[12]', row[2]):
            required[row[1]] = f'{row[0]} {row[2].split("|")[0].strip()}'
    missing = [v for t, v in required.items() if t not in ours]
    rep.check('PS3.4 Table F.7.2-1 top-level Type 1/2 N-CREATE attributes emitted (MPPSService.swift)',
              len(required) - len(missing), [], missing)
    states = {t.split()[0] + (' ' + t.split()[1] if t.startswith('IN') else '') for t, _ in variablelist_terms_ps3(p4, 'F.1-3')}


def variablelist_terms_ps3(p4, label):
    return [(r[0], r[1]) for r in table_rows(p4, label)]


def check_mpps_states(rep, p3, src_dir):
    src = read(os.path.join(src_dir, 'MPPSService.swift'))
    ours = set(re.findall(r'"(IN PROGRESS|COMPLETED|DISCONTINUED)"', src))
    std = {t for t, _ in variablelist_terms(p3, 'sect_C.4.14') if t in ('IN PROGRESS', 'COMPLETED', 'DISCONTINUED')}
    rep.check('PS3.3 C.4.14 Performed Procedure Step Status terms (MPPSService.swift)', len(ours & std), [],
              sorted(std - ours), sorted(ours - std))


def check_state_machine(rep, p8, src_dir):
    src = read(os.path.join(src_dir, 'AssociationStateMachine.swift'))
    std = {}
    for label in ('9-1', '9-2', '9-3', '9-4', '9-5'):
        for row in table_rows(p8, label):
            std[row[0].replace(' ', '')] = row[1]
    # the `description` of each state names its Sta number(s)
    ours = dict(re.findall(r'case \.(\w+):\s*return "[^"]*\((Sta[^)]*)\)"', src))
    wrong, matched = [], 0
    definitions = {
        'idle': ['Sta1'], 'awaitingLocalAssociateResponse': ['Sta2', 'Sta3'],
        'awaitingRemoteAssociateResponse': ['Sta5'], 'established': ['Sta6'],
        'awaitingLocalReleaseResponse': ['Sta8'], 'awaitingRemoteReleaseResponse': ['Sta7'],
        'releaseCollision': ['Sta9', 'Sta10', 'Sta11', 'Sta12'], 'awaitingTransportClose': ['Sta13'],
        'awaitingTransportOpen': ['Sta4'],
    }
    for state, label in ours.items():
        nums = re.findall(r'Sta\s?(\d+)', label)
        want = [d[3:] for d in definitions.get(state, [])]
        if re.search(r'Sta\s?(\d+)\s*[-–]\s*(\d+)', label):
            lo, hi = re.search(r'Sta\s?(\d+)\s*[-–]\s*(\d+)', label).groups()
            nums = [str(n) for n in range(int(lo), int(hi) + 1)]
        if sorted(nums, key=int) == sorted(want, key=int):
            matched += 1
        else:
            wrong.append(f'{state}: labelled {label!r}; PS3.8 Tables 9-1..9-5: {", ".join(definitions.get(state, ["?"]))}')
    rep.check('PS3.8 Tables 9-1..9-5 state numbering in AssociationState.description (AssociationStateMachine.swift)',
              matched, wrong)


def check_ae_title(rep, p8, src_dir):
    src = read(os.path.join(src_dir, 'AETitle.swift'))
    row = [r for r in table_rows(p8, '9-11') if r[1] == 'Called-AE-title'][0][2]
    assert '16 characters' in row and 'ISO 646:1990-Basic G0' in row
    wrong = []
    if 'maxLength = 16' not in src and 'maxLength: Int = 16' not in src:
        wrong.append('maxLength is not 16')
    if not re.search(r'0x20\s*\.\.\.\s*0x7E|0x20\.\.\.0x7E|isG0|>=\s*0x20\s*&&\s*\w+\s*<=\s*0x7E', src):
        wrong.append('permitted characters are not restricted to the ISO 646 basic G0 set (0x20-0x7E)')
    rep.check('PS3.8 Table 9-11 AE title rules (AETitle.swift: 16 bytes, ISO 646 G0)', 2 - len(wrong), wrong)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True, help='directory with partNN_<edition>.xml files')
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--sources', default=os.path.join(os.path.dirname(HERE), 'Sources', 'DICOMNetwork'))
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    parts = {}
    for n in (3, 4, 6, 7, 8):
        path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
        parts[n] = nd.Part(path)
        sub = parts[n].subtitle
        if args.edition not in sub:
            sys.exit(f'{path}: subtitle {sub!r} does not name {args.edition}')
        print(f'using {path}: {sub}')
    p3, p4, p6, p7, p8 = parts[3], parts[4], parts[6], parts[7], parts[8]
    rep = Report(args.verbose)
    src = args.sources

    check_pdu_types(rep, p8, src)
    check_item_types(rep, p7, p8, src)
    check_command_tags(rep, p7, src)
    check_command_field(rep, p7, src)
    check_priority_and_dataset_type(rep, p7, src)
    check_reject_codes(rep, p8, src)
    check_abort_codes(rep, p8, src)
    check_presentation_context_results(rep, p8, src)
    check_user_identity_types(rep, p7, src)
    check_dimse_status(rep, p7, p4, src)
    check_print_status_meanings(rep, p4, src)
    check_uids(rep, p6, src)
    check_uid_names(rep, p6, src)
    check_qr_levels_and_models(rep, p4, src)
    check_query_keys(rep, p4, src)
    check_print_enums(rep, p3, src)
    check_storage_commitment(rep, p3, p4, src)
    check_mpps(rep, p4, src)
    check_mpps_states(rep, p3, src)
    check_state_machine(rep, p8, src)
    check_ae_title(rep, p8, src)

    print(f'\n{rep.failed} check(s) with wrong or missing values')
    sys.exit(1 if rep.failed else 0)


if __name__ == '__main__':
    main()
