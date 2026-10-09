#!/usr/bin/env python3
"""Diff the DICOMweb / JPIP command-line tools (dicom-wado, dicom-jpip) against the frozen DICOM DocBook.

Usage:
    python3 Scripts/diff_cli_web.py --nema DIR [--verbose]

Part of the DICOMCLI verification (DICOMCLI_STANDARD_IMPLEMENTATION.md, G1). It
1. reruns the Scripts/diff_web.py checks over Sources/DICOMWeb, the engine every
   dicom-wado subcommand calls (query parameters, QIDO attributes, media types, URI
   templates, UPS methods, JSON VR mapping), and
2. compares what the tools expose with the 2026a text: WADO-URI parameters (PS3.18
   Tables 9.1.2-1, 9.1.2-2, 9.4.1-1, 9.5.1-1), contentType values (9.1.2.2.1, Table
   8.7.4-1), QIDO query parameters (Table 8.3.4-1), levels and matching keys (Table
   10.6.1-5), UPS transactions (Table 11.3-1), Change State targets (11.7.1.4), UPS and
   patient enumerated values (PS3.3 Tables C.30.1-1, C.30.2-1, C.7-1), the query JSON
   keys (PS3.6 Table 6-1 keywords) and the JPIP transfer syntaxes (PS3.6 Table A-1).

The option -> parameter maps below are the only hand-written part; each mapped option
is checked to exist in the tool's ArgumentParser surface (Scripts/diff_cli.py).
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
dw = load('diff_web')
dc = load('diff_cli')

# WADO-URI parameter -> dicom-wado retrieve option ('implicit' = always sent by WADOURIClient)
URI_PARAMS = {
    'requestType': 'implicit', 'studyUID': '--study', 'seriesUID': '--series', 'objectUID': '--instance',
    'contentType': '--content-type', 'frameNumber': '--frames', 'transferSyntax': '--transfer-syntax',
    'anonymize': '--anonymize', 'rows': '--rows', 'columns': '--columns',
}
# QIDO-RS query parameter (Table 8.3.4-1) -> dicom-wado query option
QIDO_PARAMS = {'match': '(matching-key options)', 'fuzzymatching': '--fuzzy-matching',
               'limit': '--limit', 'offset': '--offset'}
# matching key tag (Table 10.6.1-5) -> dicom-wado query option
QIDO_KEYS = {
    '00080020': '--study-date', '00080050': '--accession-number', '00080061': '--modality',
    '00100010': '--patient-name', '00100020': '--patient-id', '0020000D': '--study',
    '00080060': '--modality', '0020000E': '--series', '00400244': '--pps-start-date',
    '00400245': '--pps-start-time', '00400009': '--sps-id', '00401001': '--requested-procedure-id',
}
# UPS-RS transaction (Table 11.3-1) -> dicom-wado ups option
UPS_TX = {'Create': '--create', 'Retrieve': '--get', 'Change State': '--update', 'Search': '--search',
          'Subscribe': '--subscribe', 'Unsubscribe': '--unsubscribe'}


def tool_src(tool):
    return {os.path.basename(k): v for k, v in dc.tool_files(tool).items()}


def option_names(tool):
    return {n for o in dc.surface(tool)[1] for n in o['names'] if n.startswith('--')}


def check_wado(rep, p3, p6, p18):
    src = tool_src('dicom-wado')
    opts = option_names('dicom-wado')
    # WADO-URI parameters
    std = []
    for label in ('9.1.2-1', '9.1.2-2', '9.4.1-1', '9.5.1-1'):
        for row in dw.table_rows(p18, label):
            if row and re.fullmatch(r'[A-Za-z]+', row[0]) and row[0] not in std:
                std.append(row[0])
    wrong = [f'{p} -> {o}: no such option' for p, o in URI_PARAMS.items() if o != 'implicit' and o not in opts]
    wrong += [f'{p}: not a PS3.18 Section 9 parameter' for p in URI_PARAMS if p not in std]
    missing = [p for p in std if p not in URI_PARAMS]
    rep.check(f'PS3.18 Tables 9.1.2-1/9.1.2-2/9.4.1-1/9.5.1-1 WADO-URI parameters reachable from dicom-wado retrieve '
              f'({len(std)} in 2026a)', len(URI_PARAMS) - len(wrong), wrong, missing, fail_on_missing=False)
    # contentType values
    rendered = {row[1] if len(row) == 4 else row[0] for row in dw.table_rows(p18, '8.7.4-1')}
    # dicom-wado's --content-type list is the engine's WADOURIClient.MediaType.allowed (application/dicom +
    # renderedMediaTypes), consumed through DICOMwebOptionRules.uriContentTypes (D265): read it from the engine.
    client = dw.read(os.path.join(ROOT, 'Sources', 'DICOMWeb', 'WADOURIClient.swift'))
    consts = dict(re.findall(r'static let (\w+) = MediaType\(rawValue: "([^"]+)"\)', client))
    rmt = re.search(r'static let renderedMediaTypes: \[MediaType\] = \[([^\]]*)\]', client)
    allowed = re.search(r'static let allowed: \[MediaType\] = \[([^\]]*)\] \+ renderedMediaTypes', client)
    names = (re.findall(r'\.(\w+)', allowed.group(1)) if allowed else []) + (re.findall(r'\.(\w+)', rmt.group(1)) if rmt else [])
    ours = [consts[n] for n in names if n in consts]
    wrong = [v for v in ours if v != 'application/dicom' and v not in rendered]
    wrong += [f'.{n}: no MediaType constant' for n in names if n not in consts]
    missing = sorted(rendered - set(ours))
    if not ours:
        missing.append('WADOURIClient.MediaType.allowed / renderedMediaTypes not found')
    rep.check('PS3.18 9.1.2.2.1 / Table 8.7.4-1 --content-type values (WADOURIClient.MediaType.allowed)',
              len(ours) - len(wrong), wrong, missing, fail_on_missing=False)
    help_m = re.search(r'help: "Content type for WADO-URI:([^"]*)"', src['DICOMWado.swift'])
    listed = re.findall(r'(?:application|image|video|text)/[\w.+-]+', help_m.group(1)) if help_m else []
    rep.check('--content-type help lists exactly the accepted values', len(set(listed) & set(ours)),
              [f'help lists {v}, not accepted' for v in set(listed) - set(ours)],
              [f'{v} accepted, not in help' for v in set(ours) - set(listed)])
    # QIDO query parameters
    std = [row[0] for row in dw.table_rows(p18, '8.3.4-1') if row and re.fullmatch(r'[a-z]+', row[0]) and row[0] != 'search']
    wrong = [f'{p} -> {o}: no such option' for p, o in QIDO_PARAMS.items() if o.startswith('--') and o not in opts]
    missing = [p for p in std if p not in QIDO_PARAMS]
    rep.check(f'PS3.18 Table 8.3.4-1 QIDO-RS query parameters exposed by dicom-wado query ({len(std)} in 2026a)',
              len(QIDO_PARAMS) - len(wrong), wrong, missing, fail_on_missing=False)
    # levels and matching keys
    keys, levels, level = {}, [], None
    for row in dw.table_rows(p18, '10.6.1-5'):
        if len(row) == 3:
            level = row[0]; levels.append(level); name, tag = row[1], row[2]
        else:
            name, tag = row[0], row[1]
        mt = re.fullmatch(r'\((\w{4}),(\w{4})\)', tag)
        if mt:
            keys[(mt.group(1) + mt.group(2)).upper()] = (level, name.lstrip('>'))
    cases = re.findall(r'case (\w+)', dw.enum_body(src['DICOMWado.swift'], 'QueryLevel'))
    rep.check('PS3.18 Table 10.6.1-5 levels = dicom-wado query --level values', len(set(cases) & {l.lower() for l in levels}),
              [c for c in cases if c not in {l.lower() for l in levels}], [l for l in levels if l.lower() not in cases])
    wrong = [f'{t} -> {o}: no such option' for t, o in QIDO_KEYS.items() if o not in opts]
    wrong += [f'{t}: not a Table 10.6.1-5 key' for t in QIDO_KEYS if t not in keys]
    missing = [f'{t} {n} ({lv})' for t, (lv, n) in keys.items() if t not in QIDO_KEYS and t != '00400275']
    rep.check(f'PS3.18 Table 10.6.1-5 matching keys settable by dicom-wado query ({len(keys)} rows incl. the sequence)',
              len(QIDO_KEYS) - len(wrong), wrong, missing, fail_on_missing=False)
    # UPS transactions
    std = [row[0] for row in dw.table_rows(p18, '11.3-1') if len(row) >= 2 and row[1] in ('GET', 'POST', 'PUT', 'DELETE')]
    wrong = [f'{t} -> {o}: no such option' for t, o in UPS_TX.items() if o not in opts]
    missing = [t for t in std if t not in UPS_TX]
    rep.check(f'PS3.18 Table 11.3-1 UPS-RS transactions reachable from dicom-wado ups ({len(std)} in 2026a)',
              len(UPS_TX) - len(wrong), wrong, missing, fail_on_missing=False)
    # Change State targets (11.7.1.4)
    sec = dw.section_by_id(p18, 'sect_11.7.1.4')
    text = nd.norm(''.join(sec.itertext()))
    m = re.search(r'They are: (.*?)\.', text)
    std = re.findall(r'"([A-Z ]+)"', m.group(1))
    # the rule lives on DICOMWeb's UPSState (D255); dicom-wado calls UPSState.changeStateTarget(optionValue:)
    workitem = dw.read(os.path.join(ROOT, 'Sources', 'DICOMWeb', 'UPS', 'Workitem.swift'))
    m = re.search(r'static let changeStateTargets: \[UPSState\] = \[([^\]]*)\]', workitem)
    ours_src = m.group(1) if m else ''
    raw = {'inProgress': 'IN PROGRESS', 'completed': 'COMPLETED', 'canceled': 'CANCELED', 'scheduled': 'SCHEDULED'}
    ours = [raw[c] for c in re.findall(r'\.(\w+)', ours_src)]
    rep.check('PS3.18 11.7.1.4 Change State targets (DICOMWeb UPSState.changeStateTargets)', len(set(ours) & set(std)),
              [v for v in ours if v not in std], [v for v in std if v not in ours])
    # Enumerated values the ups options name in help
    def enum_values(label, tag):
        t = p3.table(label)
        for body in t.iter(nd.D + 'tbody'):
            for tr in body.findall(nd.D + 'tr'):
                txt = nd.norm(' '.join(''.join(c.itertext()) for c in tr))
                if tag in txt:
                    return txt
        return ''
    state_txt = enum_values('C.30.1-1', '(0074,1000)')
    std_states = re.findall(r'\b(SCHEDULED|IN PROGRESS|CANCELED|COMPLETED)\b', state_txt.split('Enumerated Values:')[1])
    help_fs = re.search(r'help: "Filter by Procedure Step State \(0074,1000\): ([^(]*)\(', src['DICOMWado.swift']).group(1)
    listed = [v.strip() for v in help_fs.split(',')]
    rep.check('PS3.3 Table C.30.1-1 Procedure Step State values named by --filter-state help', len(set(listed) & set(std_states)),
              [v for v in listed if v not in std_states], [v for v in std_states if v not in listed])
    prio_txt = enum_values('C.30.2-1', '(0074,1200)')
    std_prio = re.findall(r'\b(HIGH|MEDIUM|LOW)\b used to', prio_txt)
    help_p = re.search(r'Priority \(0074,1200\): ([A-Z, ]+) \(', src['DICOMWado.swift']).group(1)
    listed = [v.strip() for v in help_p.split(',')]
    rep.check('PS3.3 Table C.30.2-1 Scheduled Procedure Step Priority values named by --priority help',
              len(set(listed) & set(std_prio)), [v for v in listed if v not in std_prio], [v for v in std_prio if v not in listed])
    lab, kind, sexes = dc.enumerated_terms(p3, "Patient's Sex")
    body = re.search(r'guard \[([^\]]*)\]\.contains\(normalized\)', src['DICOMWado.swift']).group(1)
    ours = re.findall(r'"(\w+)"', body)
    rep.check(f'PS3.3 Table {lab} Patient\'s Sex values accepted by --patient-sex', len(set(ours) & set(sexes)),
              [v for v in ours if v not in sexes], [v for v in sexes if v not in ours])
    # query --format json keys (shared QIDOResultFormatter) are PS3.6 keywords
    keywords = {row[2] for row in dw.table_rows(p6, '6-1') if len(row) >= 3}
    fmt = dw.read(os.path.join(ROOT, 'Sources', 'DICOMWeb', 'QIDOResultFormatter.swift'))
    keys_used = sorted(set(re.findall(r'dict\["(\w+)"\]', fmt)))
    rep.check('PS3.6 Table 6-1 keywords used as dicom-wado query --format json keys (QIDOResultFormatter; '
              'a summary, not the PS3.18 F model: P-QUERY-JSON)', len([k for k in keys_used if k in keywords]),
              [k for k in keys_used if k not in keywords])
    fmt = dw.read(os.path.join(ROOT, 'Sources', 'DICOMWeb', 'UPSResultFormatter.swift'))
    keys_used = sorted(set(re.findall(r'dict\["(\w+)"\]', fmt)))
    rep.check('PS3.6 Table 6-1 keywords used as dicom-wado ups --format json keys (UPSResultFormatter; '
              'camelCase summary keys, P-QUERY-JSON)', len([k for k in keys_used if k in keywords]), [],
              [], [k for k in keys_used if k not in keywords])


def check_jpip(rep, p6):
    src = tool_src('dicom-jpip')['main.swift']
    a1 = {row[0]: row[1] for row in dw.table_rows(p6, 'A-1') if len(row) >= 2}
    std = {u: n for u, n in a1.items() if n.startswith('JPIP ')}
    body = src[src.index('static var listedSyntaxes'):]
    ours = dict(re.findall(r'"uid": "([0-9.]+)", "name": "([^"]+)"', body))
    wrong = [f'{u}: "{n}", A-1 "{std.get(u, a1.get(u))}"' for u, n in ours.items() if std.get(u) != n]
    missing = [f'{u} {n}' for u, n in std.items() if u not in ours]
    rep.check(f'PS3.6 Table A-1 JPIP transfer syntaxes listed by dicom-jpip info ({len(std)} in 2026a)',
              len(ours) - len(wrong), wrong, missing)
    m = re.search(r'Transfer Syntaxes[^\n]*:\n((?:\s+JPIP[^\n]*\n)+)', src)
    listed = dict((u, n.strip()) for n, u in re.findall(r'(JPIP[A-Za-z0-9 ]+?)\s+(1\.2\.840\.10008\.[0-9.]+)', m.group(1))) if m else {}
    wrong = [f'{u}: "{n}"' for u, n in listed.items() if std.get(u) != n]
    missing = [f'{u} {n}' for u, n in std.items() if u not in listed]
    rep.check('PS3.6 Table A-1 JPIP transfer syntaxes in dicom-jpip --help', len(listed) - len(wrong), wrong, missing)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True)
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()
    parts = {}
    for n in (3, 6, 18, 19):
        path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
        parts[n] = nd.Part(path)
        if args.edition not in parts[n].subtitle:
            sys.exit(f'{path}: subtitle does not name {args.edition}')
        print(f'using {path}: {parts[n].subtitle}')
    p3, p6, p18 = parts[3], parts[6], parts[18]
    rep = dw.Report(args.verbose)
    print('\n== engine called by dicom-wado (Sources/DICOMWeb, Scripts/diff_web.py checks)')
    files = dw.read_all(os.path.join(ROOT, 'Sources', 'DICOMWeb'))
    for fn in (dw.check_json_vr_mapping, dw.check_media_types, dw.check_uri_templates, dw.check_query_parameters,
               dw.check_qido_attributes, dw.check_ups_methods):
        fn(rep, p18, files)
    print('\n== dicom-wado')
    check_wado(rep, p3, p6, p18)
    print('\n== dicom-jpip')
    check_jpip(rep, p6)
    print(f'\n{rep.failed} check(s) with wrong or missing values, {rep.pending} pending owner approval')
    sys.exit(1 if rep.failed else 0)


if __name__ == '__main__':
    main()
