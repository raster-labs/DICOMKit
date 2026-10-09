#!/usr/bin/env python3
"""DICOMStudio group G3 — DIMSE networking, print enums and developer-tools data (not DICOMweb) — row-by-row checks.

Loaded by diff_studio.py (``diff_studio_g3*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
Every check extracts the values the Swift source carries by regex and diffs them against the frozen 2026a DocBook:

  * NetworkingModel print enums (D22)       vs PS3.3 C.13.1 (Print Priority Enumerated Values, Medium Type Defined
                                               Terms), C.13.3 (Film Size ID; Image Display Format STANDARD\\C,R),
                                               C.13.8 (Execution Status); PrintPriority / PrintMediumType / PrintFilmSize
                                               are deprecated aliases, so the DICOMNetwork enums are read
                                               (P-STUDIO-PRINT-ENUMS); pickers iterate DICOMNetwork *.allCases
  * NetworkingModel.MPPSStatus              vs PS3.3 C.4.14 Performed Procedure Step Status Enumerated Values
  * NetworkingModel.NetworkQueryLevel       vs PS3.4 Table C.6.1-1 Query/Retrieve Level values
  * AE Title rules (NetworkingHelpers, ShellServerConfigHelpers)  vs PS3.5 Table 6.2-1 VR AE (16 bytes, no backslash):
                                               both delegate to DICOMNetwork.AETitle, no uppercase-only rule remains
  * ports 104 / 11112 / 2762                vs PS3.8 9.1.1 and PS3.15 B.12/B.13 text (parts 7/8 are loaded from the
                                               --nema directory when present; they are not in diff_studio's parts)
  * TLSMode                                 PS3.15 2026a B.12 / B.13 (the live TLS profiles; B.9-B.11 retired) through
                                               DICOMNetwork SecureTransportConnectionProfile (P-STUDIO-TLS-PROFILES)
  * PerformanceToolsHelpers                 VR names vs PS3.5 Table 6.2-1; sample tags vs PS3.6 Table 6-1; SOP Class /
                                               UID rows vs PS3.6 Table A-1 (name beside UID, Study Root vs Patient Root)
  * GatewayModel (CR) default target port   vs PS3.8 9.1.1 well-known port
"""
import os
import re
import sys

# No pending rows: P-STUDIO-PRINT-ENUMS (298ef7a7) and P-STUDIO-TLS-PROFILES (586c8f31) are implemented and checked
# as ok rows below. Keys here are substrings of findings, so a P-item name left here would hide a regression as PEND.
PENDING_API_APPROVAL = {
}
DEFERRED = {}
EXEMPT = {}

HERE = os.path.dirname(os.path.abspath(__file__))


def src(files, suffix):
    for name, s in files.items():
        if name.endswith(suffix):
            return s
    raise KeyError(suffix)


def any_src(ctx, files, suffix):
    """A Studio source by suffix, from this group's files or any other group's (ShellServerConfigHelpers is G1)."""
    try:
        return src(files, suffix)
    except KeyError:
        return src(ctx['studio_files'](), suffix)


def raw_cases(dw, s, enum_name):
    """{caseName: rawValue} of `enum X: String` in a Swift source."""
    return dict(re.findall(r'case\s+(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', dw.enum_body(s, enum_name)))


def varlists(nd, dw, part, xml_id):
    """[(title, [terms])] of every variablelist under a section, in document order."""
    D = nd.D
    sec = dw.section_by_id(part, xml_id)
    out = []
    for vl in sec.iter(D + 'variablelist'):
        title = vl.find(D + 'title')
        terms = [nd.norm(''.join(e.find(D + 'term').itertext())).strip() for e in vl.findall(D + 'varlistentry')]
        out.append((nd.norm(''.join(title.itertext())).strip() if title is not None else '', terms))
    return out


def extra_part(ctx, n):
    """nema_docbook.Part for a PS3.n not in diff_studio's parts (7, 8), from the --nema directory; None if absent."""
    if '--nema' in sys.argv:
        d = sys.argv[sys.argv.index('--nema') + 1]
        for ed in ('2026a',):
            p = os.path.join(d, f'part{n:02d}_{ed}.xml')
            if os.path.exists(p):
                return ctx['nd'].Part(p)
    return None


def section_text(nd, dw, part, xml_id):
    sec = dw.section_by_id(part, xml_id)
    return ' '.join(''.join(sec.itertext()).split()) if sec is not None else ''


# --- PS3.3 C.13.1 / C.13.3 / C.13.8: the Studio print enums (D22) ------------------------------------------

def c13_terms(nd, dw, p3):
    """The term lists of C.13.1, C.13.3 and C.13.8 by attribute, in the order the text defines them."""
    s1 = varlists(nd, dw, p3, 'sect_C.13.1')
    s3 = varlists(nd, dw, p3, 'sect_C.13.3')
    s8 = varlists(nd, dw, p3, 'sect_C.13.8')
    out = {
        'Print Priority': s1[0][1], 'Medium Type': s1[1][1], 'Film Destination': s1[2][1],
        'Image Display Format': s3[0][1], 'Film Orientation': s3[1][1], 'Film Size ID': s3[2][1],
        'Magnification Type': s3[3][1], 'Border Density': s3[4][1], 'Empty Image Density': s3[5][1],
        'Trim': s3[6][1], 'Requested Resolution ID': s3[8][1],
        'Execution Status': s8[0][1],
    }
    # sanity: the lists are where this expects them (the text has not been reshuffled)
    assert 'MED' in out['Print Priority'] and 'BLUE FILM' in out['Medium Type'] and 'A4' in out['Film Size ID']
    assert 'PORTRAIT' in out['Film Orientation'] and 'DONE' in out['Execution Status'] and 'BIN_i' in out['Film Destination']
    return out


def check_print_enums(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    terms = c13_terms(nd, dw, parts[3])
    s = src(files, 'NetworkingModel.swift')
    net = dw.read(os.path.join(ctx['sources'], 'DICOMNetwork', 'PrintService.swift'))

    def diff(name, ours, std, exact=True, deprecated=()):
        wrong = [f'{name}.{c} = "{v}" is not a {std_name} term' for c, v in ours.items() if v not in std]
        missing = [f'{std_name} "{t}" not offered by {name}' for t in std if t not in ours.values()] if exact else []
        extra = [] if exact else [f'{std_name} "{t}" not offered by {name}' for t in std if t not in ours.values()]
        return len([v for v in ours.values() if v in std]), wrong, missing, extra

    # P-STUDIO-PRINT-ENUMS: the Studio print enums are deprecated typealiases of DICOMNetwork's, so the values offered
    # are the engine's (MediumType: its `allCases` list, which leaves out the two deprecated MAMMO spellings).
    def engine_values(name):
        cases = raw_cases(dw, net, name)
        lm = re.search(r'public static let allCases: \[' + name + r'\] = \[([^\]]*)\]', dw.enum_body(net, name))
        return {c: cases[c] for c in re.findall(r'\.(\w+)', lm.group(1))} if lm else cases

    def alias_ok(studio, engine):
        return (not re.search(r'\benum ' + studio + r'\b', s)) and bool(re.search(
            r'@available\(\*, deprecated, renamed: "' + re.escape(engine) + r'"(?:,\s*message:\s*"[^"]*")?\)\s*public typealias ' + studio + r' = '
            + re.escape(engine) + r'\b', s))

    for studio, engine, attr, label in (
            ('PrintPriority', 'PrintPriority', 'Print Priority', 'PS3.3 2026a C.13.1 Table C.13-1 Print Priority (Enumerated Values)'),
            ('PrintMediumType', 'MediumType', 'Medium Type', 'PS3.3 2026a C.13.1 Table C.13-1 Medium Type (Defined Terms)'),
            ('PrintFilmSize', 'FilmSize', 'Film Size ID', 'PS3.3 2026a C.13.3 Table C.13-3 Film Size ID (Defined Terms)')):
        std_name = label
        m, w, mi, ex = diff(f'DICOMNetwork.{engine}', engine_values(engine), terms[attr])
        if not alias_ok(studio, f'DICOMNetwork.{engine}'):
            w.append(f'NetworkingModel.{studio} must be a deprecated typealias of DICOMNetwork.{engine}, not a Studio enum (P-STUDIO-PRINT-ENUMS)')
        rep.check(f'{label}: NetworkingModel.{studio} is DICOMNetwork.{engine} (deprecated alias); its values are exactly the terms '
                  f'(P-STUDIO-PRINT-ENUMS, D22)', m, w, mi, ex)

    std_name = 'PS3.3 2026a C.13.8 Table C.13-8 Execution Status (Enumerated Values)'
    ours = raw_cases(dw, s, 'NetworkPrintJobState')
    m, w, mi, ex = diff('NetworkPrintJobState', ours, terms['Execution Status'])
    if not re.search(r'@available\(\*, deprecated, renamed: "NetworkPrintJobState"\)\s*public typealias PrintJobStatus = NetworkPrintJobState\b', s):
        w.append('PrintJobStatus must be a deprecated typealias of NetworkPrintJobState (P-STUDIO-PRINT-ENUMS)')
    rep.check('PS3.3 2026a C.13.8 Table C.13-8: NetworkingModel.NetworkPrintJobState (formerly PrintJobStatus) raw values are the '
              'Execution Status Enumerated Values (P-STUDIO-PRINT-ENUMS, D22)', m, w, mi, ex)

    # Image Display Format STANDARD\C,R — C columns then R rows, each case's own geometry
    assert terms['Image Display Format'][0].startswith('STANDARD\\C,R')
    body = dw.enum_body(s, 'FilmLayout')
    layouts = raw_cases(dw, s, 'FilmLayout')

    def switch_values(prop):
        m = re.search(r'var ' + prop + r': Int \{\s*switch self \{(.*?)\}\s*\}', body, re.S)
        return dict(re.findall(r'case \.(\w+):\s*return (\d+)', m.group(1))) if m else {}
    cols, rows, cells = switch_values('columns'), switch_values('rows'), switch_values('cellCount')
    wrong = []
    for case, raw in layouts.items():
        want = f'STANDARD\\\\{cols.get(case)},{rows.get(case)}'
        if raw != want:
            wrong.append(f'FilmLayout.{case} = "{raw}", geometry says {want} (C.13.3: STANDARD\\C,R, columns first)')
        if int(cells.get(case, -1)) != int(cols.get(case, 0)) * int(rows.get(case, 0)):
            wrong.append(f'FilmLayout.{case}.cellCount {cells.get(case)} != columns*rows')
    rep.check('PS3.3 C.13.3: NetworkingModel.FilmLayout raw values are STANDARD\\C,R of each case\'s own columns and rows',
              len(layouts) - len(wrong), wrong)

    # the Networking panel hands the layout to DICOMPrintService (it used to drop it)
    vm = src(files, 'NetworkingViewModel.swift')
    ok = bool(re.search(r'PrintLayout\(rows:\s*job\.filmLayout\.rows,\s*columns:\s*job\.filmLayout\.columns\)', vm)) \
        and bool(re.search(r'printImages\([^)]*layout:\s*networkLayout', vm, re.S))
    rep.check('PS3.3 C.13.3: NetworkingViewModel passes the chosen Film Layout to DICOMPrintService.printImages(layout:) as Image Display Format',
              1 if ok else 0, [] if ok else ['NetworkingViewModel.submitPrintJob does not pass layout: to printImages'])

    # D22 / P-STUDIO-PRINT-ENUMS: no Studio copy of the print enums is left — the New Print Job pickers iterate the
    # DICOMNetwork enums (so Medium Type offers all five C.13-1 terms, MAMMO CLEAR FILM / MAMMO BLUE FILM included) and
    # submitPrintJob hands the job's values to PrintOptions unmapped.
    view = src(files, 'NetworkingView.swift')
    matched, wrong = 0, []
    for engine in ('PrintPriority', 'MediumType', 'FilmSize'):
        if re.search(r'ForEach\(DICOMNetwork\.' + engine + r'\.allCases\b', view):
            matched += 1
        else:
            wrong.append(f'the New Print Job picker must iterate DICOMNetwork.{engine}.allCases')
    for name, text in ctx['studio_files']().items():
        for alias in ('PrintPriority', 'PrintMediumType', 'PrintFilmSize'):
            if re.search(r'ForEach\(' + alias + r'\.allCases\b', text):
                wrong.append(f'{name} iterates the deprecated Studio alias {alias}.allCases')
    if re.search(r'PrintOptions\([^)]*priority: job\.priority,\s*filmSize: job\.filmSize,\s*mediumType: job\.mediumType', vm, re.S):
        matched += 1
    else:
        wrong.append('NetworkingViewModel.submitPrintJob must pass job.priority / filmSize / mediumType to PrintOptions unmapped')
    rep.check('PS3.3 2026a Tables C.13-1 / C.13-3 (D22): the print pickers and PrintOptions use DICOMNetwork PrintPriority / MediumType / '
              'FilmSize directly, no Studio copy (P-STUDIO-PRINT-ENUMS)', matched, wrong)


# --- PS3.3 C.4.14: MPPS status --------------------------------------------------------------------------

def check_mpps_status(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    lists = varlists(nd, dw, parts[3], 'sect_C.4.14')
    std = next(terms for title, terms in lists if 'IN PROGRESS' in terms)
    s = src(files, 'NetworkingModel.swift')
    ours = raw_cases(dw, s, 'MPPSStatus')
    net = dw.read(os.path.join(ctx['sources'], 'DICOMNetwork', 'MPPSService.swift')) \
        if os.path.exists(os.path.join(ctx['sources'], 'DICOMNetwork', 'MPPSService.swift')) else ''
    wrong = [f'MPPSStatus.{c} = "{v}" is not a C.4.14 Performed Procedure Step Status value' for c, v in ours.items() if v not in std]
    missing = [f'C.4.14 "{t}" missing from MPPSStatus' for t in std if t not in ours.values()]
    rep.check('PS3.3 C.4.14 Table C.4-14: NetworkingModel.MPPSStatus raw values are the Performed Procedure Step Status Enumerated Values',
              len([v for v in ours.values() if v in std]), wrong, missing)
    # the view shows rawValue; MWL/MPPS wording in PS3.4 F.7.2 uses the same spellings
    if net:
        theirs = set(raw_cases(dw, net, 'MPPSStatus').values())
        rep.check('PS3.3 C.4.14: Studio MPPSStatus spellings agree with DICOMNetwork.MPPSStatus (cross-check)',
                  len(set(ours.values()) & theirs), [f'"{v}" not in DICOMNetwork.MPPSStatus' for v in set(ours.values()) - theirs])


# --- PS3.4 Table C.6.1-1: query levels --------------------------------------------------------------------

def check_query_levels(rep, parts, files, ctx):
    dw = ctx['dw']
    std = [row[1].strip() for row in dw.table_rows(parts[4], 'C.6.1-1') if len(row) >= 2]
    s = src(files, 'NetworkingModel.swift')
    ours = list(raw_cases(dw, s, 'NetworkQueryLevel').values())
    wrong = [f'NetworkQueryLevel "{v}" is not a Table C.6.1-1 level' for v in ours if v not in std]
    missing = [f'Table C.6.1-1 level {t} missing' for t in std if t not in ours]
    rep.check('PS3.4 Table C.6.1-1: NetworkingModel.NetworkQueryLevel raw values are PATIENT / STUDY / SERIES / IMAGE',
              len([v for v in ours if v in std]), wrong, missing)


# --- PS3.5 Table 6.2-1 (VR AE), PS3.8 Table 9-11: AE Title rules --------------------------------------------

def check_ae_title_rules(rep, parts, files, ctx):
    dw = ctx['dw']
    ae_row = next(r for r in dw.table_rows(parts[5], '6.2-1') if r and r[0].startswith('AE'))
    length = re.search(r'(\d+) bytes maximum', ae_row[-1]).group(1)
    wrong, matched = [], 0
    aet = dw.read(os.path.join(ctx['sources'], 'DICOMNetwork', 'AETitle.swift'))
    m = re.search(r'static let maxLength = (\d+)', aet)
    if m and m.group(1) == length:
        matched += 1
    else:
        wrong.append(f'DICOMNetwork.AETitle.maxLength {m and m.group(1)} != Table 6.2-1 {length} bytes')
    if '5C' not in ae_row[-2].upper() and 'BACKSLASH' not in ae_row[-2].upper():
        wrong.append('Table 6.2-1 AE row no longer excludes 5CH; update the rule')
    for suffix, rule in (('NetworkingHelpers.swift', 'AETitleHelpers'), ('ShellServerConfigHelpers.swift', 'ServerValidationHelpers')):
        s = any_src(ctx, files, suffix)
        body = dw.enum_body(s, rule)
        if 'AETitle(' not in body:
            wrong.append(f'{rule} does not validate through DICOMNetwork.AETitle')
        elif re.search(r'uppercaseLetters|\.alphanumerics', body):
            wrong.append(f'{rule} still restricts the repertoire below Table 6.2-1 (uppercase/alphanumerics only)')
        elif re.search(r'\.uppercased\(\)', body):
            wrong.append(f'{rule} folds the case of an AE Title; the standard does not')
        else:
            matched += 1
        if 'AETitle.maxLength' in body or f'= {length}' in body:
            matched += 1
        else:
            wrong.append(f'{rule} does not carry the {length}-byte maximum')
    rep.check(f'PS3.5 Table 6.2-1 VR AE ({length} bytes, Default Character Repertoire without 5CH): Studio AE Title rules delegate to '
              f'DICOMNetwork.AETitle and keep no uppercase-only or case-folding rule', matched, wrong)


# --- PS3.8 9.1.1, PS3.15 B.12: ports --------------------------------------------------------------------------

def check_ports(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    p8 = extra_part(ctx, 8)
    pending, wrong, matched = [], [], 0
    helpers = src(files, 'NetworkingHelpers.swift')
    body = dw.enum_body(helpers, 'PortHelpers')
    ours = dict(re.findall(r'static let (\w+): UInt16 = (\d+)', body))
    if p8 is None:
        pending.append('PS3.8 not in --nema directory; port text not compared (fetch part 8)')
    else:
        text = section_text(nd, dw, p8, 'sect_9.1.1')
        wk = re.search(r'"well known port"[^.]*?port number (\d+)', text)
        reg = re.search(r'"registered" port number (\d+)', text)
        for const, m in (('wellKnownDICOMPort', wk), ('defaultDICOMPort', reg)):
            if m and ours.get(const) == m.group(1):
                matched += 1
            else:
                wrong.append(f'PortHelpers.{const} = {ours.get(const)}; PS3.8 9.1.1 says {m and m.group(1)}')
        # displayName tells them apart the way the clause does
        if re.search(r'case 104:\s*return "104 \(DICOM, well-known\)"', body) and \
                re.search(r'case 11112:\s*return "11112 \(DICOM, registered\)"', body):
            matched += 1
        else:
            wrong.append('PortHelpers.displayName does not label 104 well-known / 11112 registered')
    tls = section_text(nd, dw, parts[15], 'sect_B.12')
    m = re.search(r'registered port number "(\d+) dicom-tls"', tls)
    if m and ours.get('defaultTLSPort') == m.group(1):
        matched += 1
    else:
        wrong.append(f'PortHelpers.defaultTLSPort = {ours.get("defaultTLSPort")}; PS3.15 B.12 says {m and m.group(1)}')
    # every other default port in the group's models is the registered port
    for suffix in ('NetworkingModel.swift', 'ShellServerConfigModel.swift'):
        s = any_src(ctx, files, suffix)
        for d in re.findall(r'port: (?:UInt16|Int) = (\d+)', s):
            if d == ours.get('defaultDICOMPort'):
                matched += 1
            else:
                wrong.append(f'{suffix}: default port {d} is neither the well-known nor the registered DICOM port')
    # CR file: GatewayModel's default target port is the well-known port
    cr = ctx['studio_files'](tier='CR', group='G3')
    gw = next((s for n, s in cr.items() if n.endswith('GatewayModel.swift')), '')
    for d in re.findall(r'targetPort: Int = (\d+)', gw):
        if d in (ours.get('wellKnownDICOMPort'), ours.get('defaultDICOMPort')):
            matched += 1
        else:
            wrong.append(f'GatewayModel default targetPort {d} is not a DICOM port of PS3.8 9.1.1')
    rep.check('PS3.8 9.1.1 (104 well-known, 11112 registered), PS3.15 B.12 ("2762 dicom-tls"): Studio default and listed ports',
              matched, wrong, pending=pending)


# --- PS3.15 Annex B: TLS profiles (P-STUDIO-TLS-PROFILES) --------------------------------------------------------

def check_tls_mode(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    s = src(files, 'NetworkingModel.swift')
    ours = raw_cases(dw, s, 'TLSMode')
    titles = {}
    for sec in parts[15].root.iter(nd.D + 'section'):
        xid = sec.get(nd.X + 'id') or ''
        if re.match(r'sect_B\.\d+$', xid):
            t = sec.find(nd.D + 'title')
            txt = section_text(nd, dw, parts[15], xid)
            titles[xid] = (nd.norm(''.join(t.itertext())), 'Retired.' in txt[:400])
    live = {k[5:]: v[0] for k, v in titles.items() if 'TLS' in v[0] and not v[1]}
    wrong, matched = [], 0
    if sorted(live) != ['B.12', 'B.13']:
        wrong.append(f'PS3.15 2026a live (non-retired) TLS profiles read as {sorted(live)}; expected B.12 and B.13 — re-read')
    # DICOMNetwork SecureTransportConnectionProfile: title = raw value + suffix, section = the Annex B section
    net = dw.read(os.path.join(ctx['sources'], 'DICOMNetwork', 'TLSConfiguration.swift'))
    profiles = raw_cases(dw, net, 'SecureTransportConnectionProfile')
    body = dw.enum_body(net, 'SecureTransportConnectionProfile')
    sections = dict(re.findall(r'case \.(\w+):\s*return "(B\.\d+)"', body))
    if 'public var title: String { rawValue + " Secure Transport Connection Profile" }' not in body:
        wrong.append('DICOMNetwork SecureTransportConnectionProfile.title must be rawValue + " Secure Transport Connection Profile"')
    by_section = {sections.get(c): v + ' Secure Transport Connection Profile' for c, v in profiles.items()}
    for sec_id, title in live.items():
        if by_section.get(sec_id) != title:
            wrong.append(f'DICOMNetwork SecureTransportConnectionProfile for {sec_id} titles {by_section.get(sec_id)!r}; PS3.15 2026a: {title!r}')
        else:
            matched += 1
    for c, sec_id in sections.items():
        if sec_id not in live:
            wrong.append(f'SecureTransportConnectionProfile.{c} names {sec_id}, not a live 2026a TLS profile (B.9-B.11 retired)')
    # Studio TLSMode (P-STUDIO-TLS-PROFILES): NONE, the two profiles and mutual-TLS B.12; no case names a TLS version
    want = {'none': 'NONE', 'bcp195': 'BCP195', 'modifiedBCP195': 'MODIFIED_BCP195', 'mtls': 'MTLS'}
    if ours != want:
        wrong.append(f'TLSMode raw values {ours}, expected {want} (PS3.15 2026a B.12 / B.13 profiles; P-STUDIO-TLS-PROFILES)')
    else:
        matched += len(want)
    mbody = dw.enum_body(s, 'TLSMode')
    pm = re.search(r'public var profile: SecureTransportConnectionProfile\? \{(.*?)\n    \}', mbody, re.S)
    mapping = {}
    for cs, target in re.findall(r'case ((?:\.\w+,?\s*)+):\s*return (\.\w+|nil)', pm.group(1) if pm else ''):
        for c in re.findall(r'\.(\w+)', cs):
            mapping[c] = target
    want_map = {'none': 'nil', 'bcp195': '.bcp195', 'mtls': '.bcp195', 'modifiedBCP195': '.modifiedBCP195'}
    if mapping != want_map:
        wrong.append(f'TLSMode.profile maps {mapping}, expected {want_map} (B.12 for BCP195 / MTLS, B.13 for MODIFIED_BCP195)')
    else:
        matched += 1
    dm = re.search(r'var displayName: String \{(.*?)\n    \}', mbody, re.S)
    names = dict(re.findall(r'case \.(\w+):\s*return "([^"]*)"', dm.group(1) if dm else ''))
    for c, sec_id in (('bcp195', 'B.12'), ('modifiedBCP195', 'B.13'), ('mtls', 'B.12')):
        if sec_id not in names.get(c, ''):
            wrong.append(f'TLSMode.{c}.displayName {names.get(c)!r} does not name PS3.15 {sec_id}')
        else:
            matched += 1
    for old, new, raw in (('tls12', 'bcp195', 'TLS_1_2'), ('tls13', 'modifiedBCP195', 'TLS_1_3')):
        if not re.search(r'@available\(\*, deprecated, renamed: "' + new + r'"(?:,\s*message:\s*"[^"]*")?\)\s*public static var ' + old + r': TLSMode \{ \.' + new + r' \}', mbody) \
                or not re.search(r'case "[A-Z_0-9]+", "' + raw + r'":\s*self = \.' + new, mbody):
            wrong.append(f'TLSMode.{old} must be a deprecated alias of .{new} and "{raw}" must still decode to it')
        else:
            matched += 1
    rep.check('PS3.15 2026a Annex B.12 / B.13: NetworkingModel.TLSMode selects the live TLS Secure Transport Connection Profiles '
              '(B.9-B.11 retired) through DICOMNetwork SecureTransportConnectionProfile; tls12 / tls13 deprecated (P-STUDIO-TLS-PROFILES)',
              matched, wrong)


# --- PerformanceToolsHelpers: PS3.5 Table 6.2-1, PS3.6 Tables 6-1 and A-1 ----------------------------------

def check_vr_full_names(rep, parts, files, ctx):
    dw = ctx['dw']
    std = {}
    for row in dw.table_rows(parts[5], '6.2-1'):
        if row and re.match(r'^[A-Z]{2}\s*\|', row[0]):
            code, name = row[0].split('|', 1)
            std[code.strip()] = name.strip()
    s = src(files, 'PerformanceToolsHelpers.swift')
    body = dw.func_body(s, r'static func vrFullName\(for vrCode: String\) -> String \{') if hasattr(dw, 'func_body') else ''
    if not body:
        m = re.search(r'static func vrFullName\(for vrCode: String\) -> String \{(.*?)\n    \}', s, re.S)
        body = m.group(1)
    ours = dict(re.findall(r'case "([A-Z]{2})": return "([^"]+)"', body))
    wrong, matched = [], 0
    for vr, name in ours.items():
        if vr not in std:
            wrong.append(f'{vr} is not a Table 6.2-1 VR')
        elif name == std[vr]:
            matched += 1
        else:
            wrong.append(f'{vr}: "{name}" for Table 6.2-1 "{std[vr]}"')
    missing = [f'{vr} ({std[vr]}) has no vrFullName' for vr in std if vr not in ours]
    rep.check('PS3.5 Table 6.2-1: TagDictionaryHelpers.vrFullName — 34 VR names verbatim', matched, wrong, missing)


def check_sample_tags(rep, parts, files, ctx):
    dw = ctx['dw']
    d = dw.dictionary(parts[6])
    s = src(files, 'PerformanceToolsHelpers.swift')
    rows = re.findall(r'DICOMTagEntry\(tag: "\((\w{4}),(\w{4})\)", name: "([^"]+)",\s*keyword: "(\w+)",\s*vr: "(\w+)", vm: "([^"]+)"', s)
    wrong, matched = [], 0
    for g, e, name, kw, vr, vm in rows:
        std = d.get((g + e).upper())
        if not std:
            wrong.append(f'({g},{e}) not in Table 6-1')
            continue
        sname, skw, svr, svm, retired = std
        problems = []
        if dw.norm_name(name) != dw.norm_name(sname):
            problems.append(f'name "{name}" != "{sname}"')
        if kw != skw.replace('​', ''):
            problems.append(f'keyword {kw} != {skw}')
        if vr not in svr.replace(' or ', ' ').split():
            problems.append(f'VR {vr} != {svr}')
        if vm != svm:
            problems.append(f'VM {vm} != {svm}')
        if retired.strip().upper().startswith('RET'):
            problems.append('retired')
        if problems:
            wrong.append(f'({g},{e}): ' + ', '.join(problems))
        else:
            matched += 1
    rep.check(f'PS3.6 Table 6-1: TagDictionaryHelpers.sampleTagEntries ({len(rows)} rows: tag, name, keyword, VR, VM, not retired)',
              matched, wrong)


def check_uid_rows(rep, parts, files, ctx):
    dw = ctx['dw']
    reg = dw.uid_registry(parts[6])
    s = src(files, 'PerformanceToolsHelpers.swift')
    wrong, matched, extra = [], 0, []
    for kind, pat in (('UIDEntry', r'UIDEntry\(uid: "([\d.]+)",\s*name: "([^"]+)"'),
                      ('SOPClassEntry', r'SOPClassEntry\(uid: "([\d.]+)",\s*name: "([^"]+)"'),
                      ('TransferSyntaxInfoEntry', r'uid: "([\d.]+)",\s*\n\s*name: "([^"]+)"')):
        for uid, name in re.findall(pat, s):
            std = reg.get(uid)
            if not std:
                wrong.append(f'{kind} {uid} is not registered in Table A-1')
                continue
            sname = std[0].replace('​', '')
            a, b = dw.norm_name(name), dw.norm_name(sname)
            if a == b or b.startswith(a) or b.startswith(a.replace(' sop class', '')):
                matched += 1
            elif 'Root Query' in sname or 'Root Query' in name:
                wrong.append(f'{kind} {uid} "{name}" — Table A-1: "{sname}" (Patient Root .2.1.x vs Study Root .2.2.x)')
            else:
                wrong.append(f'{kind} {uid} "{name}" is not the Table A-1 name "{sname}"')
    # the Workshop queries Study Root (study/series/image level) and Patient Root (patient level): both must be listed
    sop_uids = set(re.findall(r'SOPClassEntry\(uid: "([\d.]+)"', s))
    for uid in ('1.2.840.10008.5.1.4.1.2.2.1', '1.2.840.10008.5.1.4.1.2.2.2', '1.2.840.10008.5.1.4.1.2.2.3',
                '1.2.840.10008.5.1.4.1.2.1.1', '1.2.840.10008.5.1.4.1.2.1.2', '1.2.840.10008.5.1.4.1.2.1.3'):
        if uid not in sop_uids:
            extra.append(f'conformance list lacks {uid} {reg[uid][0]}')
    rep.check('PS3.6 Table A-1: PerformanceToolsHelpers UID rows (sample UIDs, transfer syntaxes, conformance SOP Classes) carry the registered name',
              matched, wrong, extra=extra)


CHECKS = [
    ('G3 dimse print enums (D22)', check_print_enums),
    ('G3 dimse mpps status', check_mpps_status),
    ('G3 dimse query levels', check_query_levels),
    ('G3 dimse ae title rules', check_ae_title_rules),
    ('G3 dimse ports', check_ports),
    ('G3 dimse tls mode', check_tls_mode),
    ('G3 dimse vr full names', check_vr_full_names),
    ('G3 dimse sample tags', check_sample_tags),
    ('G3 dimse uid rows', check_uid_rows),
]
