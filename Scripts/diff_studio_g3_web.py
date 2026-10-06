#!/usr/bin/env python3
"""DICOMStudio group G3 — the DICOMweb panel (Models/DICOMwebModel, ViewModels/DICOMwebViewModel, Services/DICOMwebService,
Services/DICOMwebClientFactory, Components/DICOMwebHelpers, Views/DICOMwebView) — row-by-row checks.

Loaded by diff_studio.py (``diff_studio_g3*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
Every check extracts the values the Swift source carries by regex and diffs them against the frozen 2026a DocBook:

  * UPSState terms (dicomTerm, string literals)        vs PS3.3 C.30.1 Procedure Step State (0074,1000) enumerated values
  * UPSState.allowedTransitions                        vs PS3.4 Table CC.1.1-2 (N-ACTION Change State rows, "with correct
                                                          Transaction UID": a cell that is not a Failure/Warning status allows it)
  * SCHEDULED-target refusal text (Helpers, ViewModel)  is DICOMWeb UPSState.changeStateRefusal, as dicom-wado's (D255; PS3.18
                                                          11.7.1.4; PS3.4 Table CC.2.1-2 C303H); the other codes it names vs CC.2.1-2
  * UPSPriority raw values                             vs PS3.3 C.30.2 Scheduled Procedure Step Priority (0074,1200)
  * QIDO: endpointSuffix                               vs PS3.18 Table 10.6.1-1 URI templates
          buildQIDOQuery keys (via DICOMWeb QIDOQuery)  vs PS3.18 Table 10.6.1-5 (study: Modalities in Study; series: Modality)
          fuzzymatching / limit / offset               vs PS3.18 Table 8.3.4-1
  * WADO-URI parameter names (protocolDescription)     vs PS3.18 Table 9.1.2-1 (requestType=WADO, studyUID, seriesUID, objectUID)
  * WADORetrieveMode cases                             vs PS3.18 Table 10.1-1 resource names
  * UPSEventPayloadParser 8-hex tags                   vs PS3.6 Table 6-1 (exist, keyword written beside them) and PS3.4 Table
                                                          CC.2.4-1 (each is an Event Report attribute; bare-name keys reported as extra)
  * HTTP status numbers in the panel                   vs PS3.18 Table 10.5.3-1 (STOW) / Table 8.5-1
  * JPIP text in the View                              vs PS3.6 Table A-1 JPIP rows and Table 6-1 (0028,7FE0) Pixel Data Provider URL
  * DICOMwebTLSMode                                    PS3.15 2026a B.12 / B.13 (live TLS profiles) via DICOMWeb
                                                          DICOMwebConfiguration.TLSProfile (P-STUDIO-TLS-PROFILES)
Since P-STUDIO-UPS-STATE-RAW, Studio's UPSState is a deprecated alias of DICOMWeb's UPSState (WebUPSState), so the
UPS checks read the raw values and validTransitions from Sources/DICOMWeb/UPS/Workitem.swift.
"""
import os
import re

# No pending rows: P-STUDIO-UPS-STATE-RAW (574f5eb0) and P-STUDIO-TLS-PROFILES (586c8f31) are implemented and checked
# as ok rows. Keys here are substrings of findings, so a P-item name left here would hide a regression as PEND.
PENDING_API_APPROVAL = {
}
DEFERRED = {}
EXEMPT = {}

HERE = os.path.dirname(os.path.abspath(__file__))
ZW = '​'


def src(files, suffix):
    for name, s in files.items():
        if name.endswith(suffix):
            return s
    raise KeyError(suffix)


def raw_cases(dw, s, enum_name):
    return dict(re.findall(r'case\s+(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', dw.enum_body(s, enum_name)))


def switch_returns(body):
    """{caseName: "literal"} of `case .x: return "literal"` lines in a computed-property body."""
    return dict(re.findall(r'case\s+\.(\w+):\s*return\s+"((?:[^"\\]|\\.)*)"', body))


def varlists(nd, dw, part, xml_id):
    D = nd.D
    sec = dw.section_by_id(part, xml_id)
    out = []
    for vl in sec.iter(D + 'variablelist'):
        terms = [nd.norm(''.join(e.find(D + 'term').itertext())).strip() for e in vl.findall(D + 'varlistentry')]
        out.append(terms)
    return out


def dictionary(nd, p6):
    """{'(gggg,eeee)': (name, keyword)} of PS3.6 Table 6-1 (tags upper-cased, zero-width spaces stripped)."""
    out = {}
    for row in p6.rows(p6.table('6-1')):
        if len(row) < 3:
            continue
        tag = row[0].replace(ZW, '').upper()
        out[tag] = (row[1].replace(ZW, ''), row[2].replace(ZW, ''))
    return out


def hex8_to_tag(h):
    return f'({h[:4].upper()},{h[4:].upper()})'


# --- PS3.3 C.30.1 / C.30.2 and PS3.4 Table CC.1.1-2: the UPS state machine ---------------------------------

def c30_terms(nd, dw, p3):
    states = [t for t in varlists(nd, dw, p3, 'sect_C.30.1') if 'SCHEDULED' in t][0]
    prios = [t for t in varlists(nd, dw, p3, 'sect_C.30.2') if 'HIGH' in t][0]
    assert states == ['SCHEDULED', 'IN PROGRESS', 'CANCELED', 'COMPLETED'] or set(states) >= {'SCHEDULED', 'CANCELED'}
    return states, prios


def engine_ups(ctx):
    """DICOMWeb's `enum UPSState` source (Sources/DICOMWeb/UPS/Workitem.swift), which Studio's UPSState now aliases."""
    return ctx['dw'].read(os.path.join(ctx['sources'], 'DICOMWeb', 'UPS', 'Workitem.swift'))


def studio_ups_alias(files):
    """P-STUDIO-UPS-STATE-RAW: Studio's UPSState is a deprecated typealias of WebUPSState = DICOMWeb::UPSState with no
    enum of its own; dicomTerm is the raw value, allowedTransitions DICOMWeb's validTransitions. Returns findings."""
    model, alias = src(files, 'DICOMwebModel.swift'), src(files, 'WebUPSState.swift')
    out = []
    if re.search(r'\benum UPSState\b', model) or not re.search(
            r'@available\(\*, deprecated, renamed: "WebUPSState"(?:,\s*message:\s*"[^"]*")?\)\s*public typealias UPSState = WebUPSState\b', model):
        out.append('DICOMwebModel.UPSState must be a deprecated typealias of WebUPSState, not a Studio enum (P-STUDIO-UPS-STATE-RAW)')
    if not re.search(r'public typealias WebUPSState = DICOMWeb::UPSState\b', alias):
        out.append('WebUPSState must name DICOMWeb::UPSState (P-STUDIO-UPS-STATE-RAW)')
    if 'public var dicomTerm: String { rawValue }' not in alias:
        out.append('WebUPSState.dicomTerm must be the raw value (the PS3.3 Table C.30.1-1 term)')
    if 'public var allowedTransitions: [WebUPSState] { validTransitions }' not in alias:
        out.append('WebUPSState.allowedTransitions must be DICOMWeb UPSState.validTransitions (PS3.4 Table CC.1.1-2)')
    return out


def check_ups_states(rep, parts, files, ctx):
    """PS3.3 2026a Table C.30.1-1: Studio's UPSState is DICOMWeb's UPSState (P-STUDIO-UPS-STATE-RAW), whose raw values
    are the four Procedure Step State (0074,1000) Enumerated Values; the retired Studio values still decode."""
    dw, nd = ctx['dw'], ctx['nd']
    states, prios = c30_terms(nd, dw, parts[3])
    model = src(files, 'DICOMwebModel.swift')
    alias = src(files, 'WebUPSState.swift')
    wrong = studio_ups_alias(files)
    raws = raw_cases(dw, engine_ups(ctx), 'UPSState')
    wrong += [f'DICOMWeb UPSState.{c} rawValue "{v}" is not a PS3.3 Table C.30.1-1 term' for c, v in raws.items() if v not in states]
    missing = [f'C.30.1 term "{t}" has no DICOMWeb UPSState case' for t in states if t not in raws.values()]
    legacy = dict(re.findall(r'case "([A-Z_ ]+)":\s*self = \.(\w+)', alias))
    for old, case in (('IN_PROGRESS', 'inProgress'), ('CANCELLED', 'canceled')):
        if legacy.get(old) != case:
            wrong.append(f'WebUPSState(legacyRawValue:) must decode the retired Studio value {old} as .{case}')
    rep.check('PS3.3 2026a Table C.30.1-1: UPSState is DICOMWeb\'s UPSState (deprecated Studio alias); its raw values are the 4 '
              'Procedure Step State terms; IN_PROGRESS / CANCELLED still decode (P-STUDIO-UPS-STATE-RAW)',
              len([v for v in raws.values() if v in states]), wrong, missing)

    # every quoted state literal in the ViewModel / Helpers / View is a C.30.1 term
    lits = set()
    for suffix in ('DICOMwebViewModel.swift', 'DICOMwebHelpers.swift', 'DICOMwebView.swift'):
        s = src(files, suffix)
        lits |= set(re.findall(r'"(SCHEDULED|IN PROGRESS|IN_PROGRESS|COMPLETED|CANCELED|CANCELLED)"', s))
    wrong = [f'state literal "{l}" is not a C.30.1 term' for l in sorted(lits) if l not in states]
    rep.check('PS3.3 C.30.1: UPS state string literals in the DICOMweb ViewModel, Helpers and View are the 4 terms',
              len([l for l in lits if l in states]), wrong, [t for t in states if t not in lits])

    prio = raw_cases(dw, model, 'UPSPriority')
    rep.check('PS3.3 C.30.2: DICOMwebModel.UPSPriority raw values are the Scheduled Procedure Step Priority terms',
              len([v for v in prio.values() if v in prios]),
              [f'UPSPriority.{c} = "{v}" is not a C.30.2 term' for c, v in prio.items() if v not in prios],
              [f'C.30.2 term "{t}" not offered' for t in prios if t not in prio.values()])


def cc112_change_state_targets(p4):
    """{from_state: {to_state}} allowed by the 'N-ACTION to Change State to X … with correct Transaction UID' rows."""
    t = p4.table('CC.1.1-2')
    header = [r for r in p4.rows(t, header=True) if 'SCHEDULED' in r][0]
    cols = [c.replace(ZW, '') for c in header]
    first_state = cols.index('SCHEDULED')
    states = cols[first_state:]
    allowed = {s: set() for s in states}
    for row in p4.rows(t):
        ev = row[0].replace(ZW, '')
        m = re.match(r'N-ACTION to Change State to ([A-Z ]+?)(?:,)? with correct Transaction UID', ev)
        if not m:
            continue
        target = m.group(1).strip()
        cells = row[first_state:]
        for state, cell in zip(states, cells):
            if not re.match(r'(Failure|Warning) Status Code', cell.replace(ZW, '').strip()):
                allowed[state].add(target)
    return allowed


def check_ups_transitions(rep, parts, files, ctx):
    dw = ctx['dw']
    allowed = cc112_change_state_targets(parts[4])
    # Studio's allowedTransitions is DICOMWeb's validTransitions (P-STUDIO-UPS-STATE-RAW): read the engine's switch
    body = dw.enum_body(engine_ups(ctx), 'UPSState')
    terms = raw_cases(dw, engine_ups(ctx), 'UPSState')
    tb = re.search(r'var validTransitions: \[UPSState\] \{(.*?)\n    \}', body, re.S).group(1)
    ours = {}
    for cs, lst in re.findall(r'case\s+((?:\.\w+\s*,?\s*)+):\s*return\s+\[([^\]]*)\]', tb):
        for c in re.findall(r'\.(\w+)', cs):
            ours[terms[c]] = {terms[x.strip().lstrip('.')] for x in lst.split(',') if x.strip()}
    matched, wrong, missing = 0, [], []
    alias_findings = [f for f in studio_ups_alias(files) if 'allowedTransitions' in f or 'typealias' in f or 'DICOMWeb::' in f]
    wrong += alias_findings
    matched += 0 if alias_findings else 1
    for state, std in allowed.items():
        got = ours.get(state, set())
        for t in sorted(got - std):
            wrong.append(f'{state} → {t} is offered but Table CC.1.1-2 refuses it')
        for t in sorted(std - got):
            missing.append(f'{state} → {t} is allowed by Table CC.1.1-2 but not offered')
        matched += len(got & std)
    if any('SCHEDULED' in v for v in ours.values()):
        wrong.append('SCHEDULED is offered as a Change State target (Table CC.1.1-2 C303H)')
    rep.check('PS3.4 2026a Table CC.1.1-2: UPSState.allowedTransitions (DICOMWeb UPSState.validTransitions) are the Change State '
              'targets the table allows (P-STUDIO-UPS-STATE-RAW)',
              matched, wrong, missing)


def check_ups_change_state_refusal(rep, parts, files, ctx):
    """The SCHEDULED refusal is DICOMWeb's UPSState.changeStateRefusal, which Studio's helper returns and dicom-wado
    throws through UPSState.changeStateTarget(optionValue:) (D255) — no Studio copy of the text; every status code it
    and the Studio helper name is in Table CC.2.1-2."""
    dw = ctx['dw']
    helpers = src(files, 'DICOMwebHelpers.swift')
    vm = src(files, 'DICOMwebViewModel.swift')

    workitem = dw.read(os.path.join(ctx['sources'], 'DICOMWeb', 'UPS', 'Workitem.swift'))
    m = re.search(r'public var changeStateRefusal: String\? \{(.*?)\n    \}', workitem, re.S)
    engine_msg = ''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))).replace('\\(rawValue)', 'SCHEDULED') if m else ''
    wrong, missing, matched = [], [], 0
    if not engine_msg:
        missing.append('DICOMWeb UPSState.changeStateRefusal not found; update the extractor')
    elif '11.7.1.4' not in engine_msg or 'C303H' not in engine_msg:
        wrong.append(f'UPSState.changeStateRefusal does not cite PS3.18 11.7.1.4 / C303H: {engine_msg} (DICOMWeb)')
    else:
        matched += 1
    # since P-STUDIO-UPS-STATE-RAW the parameters are the engine's UPSState itself (WebUPSState), so `to.changeStateRefusal`
    hm = re.search(r'static func changeStateRefusal\(from: WebUPSState, to: WebUPSState\) -> String\? \{(.*?)\n    \}', helpers, re.S)
    body = hm.group(1) if hm else ''
    if re.search(r'if let refusal = to\.changeStateRefusal \{\s*return refusal', body):
        matched += 1
    else:
        wrong.append('DICOMwebUPSHelpers.changeStateRefusal(from: WebUPSState, to: WebUPSState) must return DICOMWeb UPSState.changeStateRefusal for SCHEDULED (D255)')
    if 'Change Workitem State target' in body:
        wrong.append('DICOMwebUPSHelpers.changeStateRefusal carries its own copy of the SCHEDULED text; return to.changeStateRefusal')
    else:
        matched += 1
    cli = ''.join(dw.read(os.path.join(ctx['sources'], 'dicom-wado', f)) for f in sorted(os.listdir(os.path.join(ctx['sources'], 'dicom-wado'))) if f.endswith('.swift'))
    if 'changeStateTarget(optionValue:' in cli:
        matched += 1
    else:
        wrong.append('dicom-wado no longer resolves --state through UPSState.changeStateTarget(optionValue:); re-read the CLI')
    if 'changeStateRefusal(from:' not in vm:
        wrong.append('DICOMwebViewModel.transitionUPSState does not use DICOMwebUPSHelpers.changeStateRefusal')
    else:
        matched += 1
    # status codes named by the refusal texts vs Table CC.2.1-2
    std_codes = {row[-1].strip() for row in parts[4].rows(parts[4].table('CC.2.1-2')) if re.match(r'^[0-9A-F]{4}$', row[-1].strip())}
    codes = set(re.findall(r'\b([BC][0-9A-F]{3})H\b', body + ' ' + engine_msg))
    for c in sorted(codes - std_codes):
        wrong.append(f'status code {c}H named by changeStateRefusal is not in Table CC.2.1-2')
    rep.check('PS3.18 11.7.1.4 / PS3.4 Table CC.2.1-2: Studio refuses a SCHEDULED target with DICOMWeb UPSState.changeStateRefusal, '
              'the text dicom-wado throws (D255); codes named exist', matched + len(codes & std_codes), wrong, missing)


# --- PS3.18 Tables 10.6.1-1, 10.6.1-5, 8.3.4-1: QIDO ----------------------------------------------------------

def check_qido(rep, parts, files, ctx):
    dw = ctx['dw']
    p18 = parts[18]
    helpers = src(files, 'DICOMwebHelpers.swift')
    factory = src(files, 'DICOMwebClientFactory.swift')
    # resources
    templates = {row[1].replace(ZW, '').split('{?')[0] for row in p18.rows(p18.table('10.6.1-1'))}
    m = re.search(r'static func endpointSuffix\(for level: QIDOQueryLevel\) -> String \{(.*?)\n    \}', helpers, re.S)
    ours = switch_returns(m.group(1)) if m else {}
    rep.check('PS3.18 Table 10.6.1-1: DICOMwebQIDOHelpers.endpointSuffix values are Search Transaction resource paths',
              len([v for v in ours.values() if v in templates]),
              [f'endpointSuffix .{c} = "{v}" is not a Table 10.6.1-1 resource' for c, v in ours.items() if v not in templates], [])

    # matching keys by level: resolve the QIDOQuery builder method → tag constant in DICOMWeb
    qq = dw.read(os.path.join(ctx['sources'], 'DICOMWeb', 'QIDOQuery.swift'))
    method_attr = dict(re.findall(r'public func (\w+)\([^)]*\) -> QIDOQuery \{\s*\n\s*return with\(parameter: QIDOQueryAttribute\.(\w+)', qq))
    attr_tag = dict(re.findall(r'public static let (\w+) = "([0-9A-Fa-f]{8})"', qq))
    std = {}
    level = None
    for row in p18.rows(p18.table('10.6.1-5')):
        if len(row) == 3:
            level, name, tag = row
        else:
            name, tag = row[-2], row[-1]
        std.setdefault(level.replace(ZW, ''), {})[tag.replace(ZW, '').upper()] = name.replace(ZW, '').lstrip('>')
    body = re.search(r'static func buildQIDOQuery\(from params: QIDOQueryParams\) -> QIDOQuery \{(.*?)\n    \}', factory, re.S).group(1)
    wrong, matched = [], 0
    study_branch = re.search(r'case \.study:\s*query = query\.(\w+)\(', body)
    series_branch = re.search(r'case \.series, \.instance:\s*query = query\.(\w+)\(', body)
    for lvl, br in (('Study', study_branch), ('Series', series_branch)):
        if not br:
            wrong.append(f'buildQIDOQuery has no modality branch for the {lvl} level')
            continue
        tag = hex8_to_tag(attr_tag[method_attr[br.group(1)]])
        if tag in std[lvl] and 'Modalit' in std[lvl][tag]:
            matched += 1
        else:
            wrong.append(f'{lvl}-level modality key {br.group(1)} → {tag} is not the Table 10.6.1-5 modality attribute of that level')
    for meth in ('patientName', 'patientID', 'accessionNumber'):
        tag = hex8_to_tag(attr_tag[method_attr[meth]])
        if tag in std['Study']:
            matched += 1
        else:
            wrong.append(f'buildQIDOQuery.{meth} → {tag} is not a Table 10.6.1-5 study-level key')
    for meth in ('studyDate', 'studyDateRange'):
        if attr_tag[method_attr.get(meth, 'studyDate')] == '00080020':
            matched += 1
    # studyDescription (0008,1030) is not a required matching key: allowed as optional, reported as extra
    extra = ['studyDescription (0008,1030) is not a Table 10.6.1-5 required key (optional matching, allowed)']
    rep.check('PS3.18 Table 10.6.1-5: buildQIDOQuery keys are the required matching attributes of the chosen level (study: Modalities in Study)',
              matched, wrong, [], extra)

    # search parameters
    std_params = {row[0].replace(ZW, '') for row in p18.rows(p18.table('8.3.4-1'))} - {'search', 'match'}
    used = set()
    if re.search(r'params\.fuzzyMatching\b.*?query\.fuzzyMatching\(true\)', body, re.S):
        used.add('fuzzymatching')
    if 'query.limit(' in body:
        used.add('limit')
    if 'query.offset(' in body:
        used.add('offset')
    model = src(files, 'DICOMwebModel.swift')
    missing = []
    if 'var fuzzyMatching: Bool' in model and 'fuzzymatching' not in used:
        missing.append('QIDOQueryParams.fuzzyMatching is never sent as fuzzymatching= (PS3.18 8.3.4.2)')
    rep.check('PS3.18 Table 8.3.4-1: the search parameters the panel offers (fuzzymatching, limit, offset) are sent by buildQIDOQuery',
              len(used & std_params), [p for p in used if p not in std_params], missing,
              [f'Table 8.3.4-1 parameter {p} not offered by the panel' for p in sorted(std_params - used)])


# --- PS3.18 Tables 9.1.2-1, 10.1-1: WADO ---------------------------------------------------------------------

def check_wado(rep, parts, files, ctx):
    dw = ctx['dw']
    p18 = parts[18]
    model = src(files, 'DICOMwebModel.swift')
    std = {row[0].replace(ZW, ''): row[1].replace(ZW, '').strip('"') for row in p18.rows(p18.table('9.1.2-1'))}
    desc = re.search(r'"([^"]*\?requestType[^"]*)"', dw.enum_body(model, 'WADOProtocol'))
    text = desc.group(1) if desc else ''
    ours = dict(re.findall(r'[?&](\w+)=([^&.]*)', text))
    wrong = [f'WADO-URI parameter "{k}" is not in Table 9.1.2-1' for k in ours if k not in std]
    if ours.get('requestType') != 'WADO':
        wrong.append(f'requestType value is {ours.get("requestType")!r}, Table 9.1.2-1 / 9.1.2.1.1 says "WADO"')
    rep.check('PS3.18 Table 9.1.2-1: WADOProtocol.protocolDescription names the 4 mandatory WADO-URI parameters (requestType=WADO)',
              len([k for k in ours if k in std]), wrong, [f'Table 9.1.2-1 parameter {k} missing' for k in std if k not in ours])

    resources = {row[0].replace(ZW, '') for row in p18.rows(p18.table('10.1-1'))}
    dn = re.search(r'var displayName: String \{(.*?)\n    \}', dw.enum_body(model, 'WADORetrieveMode'), re.S)
    names = switch_returns(dn.group(1)) if dn else {}
    matched = [c for c, v in names.items() if v in resources]
    wrong = [f'WADORetrieveMode.{c} "{v}" is not a Table 10.1-1 resource name' for c, v in names.items()
             if v not in resources and v not in ('Rendered',)]
    extra = [f'WADORetrieveMode.rendered "Rendered" abbreviates Table 10.1-1 "Rendered Study/Series/Instance/Frames"'] if 'rendered' in names else []
    rep.check('PS3.18 Table 10.1-1: WADORetrieveMode display names are Studies Service resource names',
              len(matched), wrong, [], extra)


# --- PS3.6 Table 6-1 and PS3.4 Table CC.2.4-1: the event payload parser ---------------------------------------

def check_event_parser_tags(rep, parts, files, ctx):
    nd = ctx['nd']
    dic = dictionary(nd, parts[6])
    helpers = src(files, 'DICOMwebHelpers.swift')
    body = re.search(r'public enum UPSEventPayloadParser.*?\n\}\n', helpers, re.S).group(0)
    hexes = sorted(set(re.findall(r'"([0-9A-Fa-f]{8})"', body)))
    event_tags = set()
    for row in parts[4].rows(parts[4].table('CC.2.4-1')):
        for cell in row:
            for t in re.findall(r'\(([0-9A-Fa-f]{4}),([0-9A-Fa-f]{4})\)', cell.replace(ZW, '')):
                event_tags.add(f'({t[0].upper()},{t[1].upper()})')
    # code sequence macro (Table 8-3a) items and Actual Human Performers (0040,4035)>(0040,4037) are read as fallbacks
    macro = {'(0008,0100)', '(0008,0102)', '(0008,0104)'}
    matched, wrong, extra = 0, [], []
    for h in hexes:
        tag = hex8_to_tag(h)
        if tag not in dic:
            wrong.append(f'{tag} is not in PS3.6 Table 6-1')
            continue
        name, kw = dic[tag]
        # the comment beside the literal must name the attribute
        line = next((l for l in body.splitlines() if f'"{h}"' in l), '')
        ctx_lines = body[max(0, body.find(f'"{h}"') - 400):body.find(f'"{h}"')]
        if name not in ctx_lines and name not in line and kw not in ctx_lines:
            wrong.append(f'{tag} {name}: name not written near the literal')
            continue
        if tag in event_tags or tag in macro:
            matched += 1
        else:
            extra.append(f'{tag} {name} is read but is not a Table CC.2.4-1 Event Report attribute (fallback)')
    bare = sorted(set(re.findall(r'json\["([A-Za-z]+)"\]', body)))
    extra += [f'bare-name key "{k}" is not a DICOM JSON tag (legacy DICOMKit payloads, fallback only)' for k in bare]
    # the progress attributes must be read inside (0074,1002)
    if not re.search(r'firstSequenceItem\(json\["00741002"\]\)', body):
        wrong.append('Procedure Step Progress (0074,1004) is not read inside Procedure Step Progress Information Sequence (0074,1002)')
    if '"0074100C"' not in body:
        wrong.append('Contact Display Name (0074,100C) is not read')
    rep.check('PS3.6 Table 6-1 / PS3.4 Table CC.2.4-1: UPSEventPayloadParser reads Event Report attributes by tag, progress nested in (0074,1002)',
              matched, wrong, [], extra)


# --- PS3.18 Tables 10.5.3-1 / 8.5-1: HTTP status numbers named by the panel ----------------------------------

def check_status_codes(rep, parts, files, ctx):
    p18 = parts[18]
    stow = set()
    for row in p18.rows(p18.table('10.5.3-1')):
        for cell in row:
            m = re.match(r'^(\d{3}) \(', cell.replace(ZW, '').strip())
            if m:
                stow.add(m.group(1))
    general = set()
    for row in p18.rows(p18.table('8.5-1')):
        m = re.match(r'^(\d{3})', row[0].replace(ZW, '').strip())
        if m:
            general.add(m.group(1))
    named = set()
    for suffix in ('DICOMwebHelpers.swift', 'DICOMwebModel.swift', 'DICOMwebView.swift', 'DICOMwebViewModel.swift'):
        s = src(files, suffix)
        named |= set(re.findall(r'(?:return|HTTP)\s+(\d{3})\b', s))
    wrong = [f'HTTP {c} named by the panel is not in Table 8.5-1' for c in sorted(named - general)]
    matched = len(named & general)
    if '409' in named and '409' not in stow:
        wrong.append('409 is described as a STOW duplicate response but Table 10.5.3-1 does not list it')
    rep.check('PS3.18 Tables 10.5.3-1 / 8.5-1: HTTP status numbers the panel names (409 for a STOW conflict) are standard codes',
              matched, wrong, [])


# --- PS3.6 Tables A-1 and 6-1: the JPIP text of the View ------------------------------------------------------

def check_jpip_text(rep, parts, files, ctx):
    nd = ctx['nd']
    p6 = parts[6]
    view = src(files, 'DICOMwebView.swift')
    jpip = {row[0].replace(ZW, ''): row[1].replace(ZW, '') for row in p6.rows(p6.table('A-1')) if 'JPIP' in row[1]}
    m = re.search(r'"Transfer Syntaxes?: ([^"]*)"', view)
    text = m.group(1) if m else ''
    base = re.search(r'(1\.2\.840\.10008\.1\.2\.4)\.(\d+)', text)
    uids = set()
    if base:
        uids = {base.group(0)} | {f'{base.group(1)}.{n}' for n in re.findall(r'/ \.(\d+)', text)}
    wrong = [f'{u} in the JPIP header is not a JPIP transfer syntax of Table A-1' for u in sorted(uids - set(jpip))]
    missing = [f'JPIP transfer syntax {u} ({n}) not listed' for u, n in jpip.items() if u not in uids]
    rep.check('PS3.6 Table A-1: the JPIP panel header lists the JPIP transfer syntaxes', len(uids & set(jpip)), wrong, missing)

    dic = dictionary(nd, p6)
    uri = re.search(r'Text\("Extract the JPIP[^"]*"\)', view)
    txt = uri.group(0) if uri else ''
    tags = re.findall(r'\(([0-9A-F]{4}),([0-9A-F]{4})\)', txt)
    wrong, matched = [], 0
    for g, e in tags:
        tag = f'({g},{e})'
        if tag != '(0028,7FE0)':
            wrong.append(f'uri panel names {tag} {dic.get(tag, ("?",))[0]}; the JPIP URL is Pixel Data Provider URL (0028,7FE0), PS3.5 A.6')
        elif dic[tag][0] in txt:
            matched += 1
        else:
            wrong.append(f'uri panel names (0028,7FE0) without its Table 6-1 name "{dic[tag][0]}"')
    rep.check('PS3.6 Table 6-1 / PS3.5 A.6: the JPIP uri panel names Pixel Data Provider URL (0028,7FE0)',
              matched, wrong, ['uri panel names no tag'] if not tags else [])


# --- PS3.15 Annex B: TLS profiles (P-STUDIO-TLS-PROFILES, the DICOMweb half) -------------------------------------

def check_tls_mode(rep, parts, files, ctx):
    """DICOMwebTLSMode offers NONE, the two live PS3.15 2026a TLS profiles (B.12, B.13; B.9-B.11 retired) and the
    non-profile DEVELOPMENT mode, and hands the profiles to DICOMWeb DICOMwebConfiguration.TLSProfile, whose raw values
    are the B.12 / B.13 titles without "Secure Transport Connection Profile"; COMPATIBLE / STRICT deprecated, still decode."""
    dw, nd = ctx['dw'], ctx['nd']
    model = src(files, 'DICOMwebModel.swift')
    cases = raw_cases(dw, model, 'DICOMwebTLSMode')
    live = {}
    for n in range(1, 20):
        sec = dw.section_by_id(parts[15], f'sect_B.{n}')
        if sec is None:
            continue
        title = dw.section_title(parts[15], f'sect_B.{n}') or ''
        if 'TLS' in title and 'Retired.' not in nd.norm(' '.join(sec.itertext()))[:400]:
            live[f'B.{n}'] = title
    wrong, matched = [], 0
    if sorted(live) != ['B.12', 'B.13']:
        wrong.append(f'PS3.15 2026a live (non-retired) TLS profiles read as {sorted(live)}; expected B.12 and B.13 — re-read')
    conf = dw.read(os.path.join(ctx['sources'], 'DICOMWeb', 'DICOMwebConfiguration.swift'))
    profiles = raw_cases(dw, conf, 'TLSProfile')
    sections = dict(re.findall(r'case \.(\w+):\s*return "(B\.\d+)"', dw.enum_body(conf, 'TLSProfile')))
    for sec_id, title in live.items():
        got = next((v + ' Secure Transport Connection Profile' for c, v in profiles.items() if sections.get(c) == sec_id), None)
        if got != title:
            wrong.append(f'DICOMWeb DICOMwebConfiguration.TLSProfile for {sec_id} is {got!r}; PS3.15 2026a title {title!r}')
        else:
            matched += 1
    want = {'none': 'NONE', 'bcp195': 'BCP195', 'modifiedBCP195': 'MODIFIED_BCP195', 'development': 'DEVELOPMENT'}
    if cases != want:
        wrong.append(f'DICOMwebTLSMode raw values {cases}, expected {want} (P-STUDIO-TLS-PROFILES)')
    else:
        matched += len(want)
    body = dw.enum_body(model, 'DICOMwebTLSMode')
    pm = re.search(r'public var webTLSProfile: DICOMwebConfiguration\.TLSProfile\? \{(.*?)\n    \}', body, re.S)
    mapping = {}
    for cs, target in re.findall(r'case ((?:\.\w+,?\s*)+):\s*return (\.\w+|nil)', pm.group(1) if pm else ''):
        for c in re.findall(r'\.(\w+)', cs):
            mapping[c] = target
    want_map = {'none': 'nil', 'development': 'nil', 'bcp195': '.bcp195', 'modifiedBCP195': '.modifiedBCP195'}
    if mapping != want_map:
        wrong.append(f'DICOMwebTLSMode.webTLSProfile maps {mapping}, expected {want_map}')
    else:
        matched += 1
    for old, new, raw in (('compatible', 'bcp195', 'COMPATIBLE'), ('strict', 'modifiedBCP195', 'STRICT')):
        if not re.search(r'@available\(\*, deprecated, renamed: "' + new + r'"(?:,\s*message:\s*"[^"]*")?\)\s*public static var '
                         + old + r': DICOMwebTLSMode \{ \.' + new + r' \}', body) \
                or not re.search(r'case "[A-Z_0-9]+", "' + raw + r'":\s*self = \.' + new, body):
            wrong.append(f'DICOMwebTLSMode.{old} must be a deprecated alias of .{new} and "{raw}" must still decode to it')
        else:
            matched += 1
    rep.check('PS3.15 2026a Annex B.12 / B.13: DICOMwebModel.DICOMwebTLSMode selects the live TLS profiles through DICOMWeb '
              'DICOMwebConfiguration.TLSProfile; COMPATIBLE / STRICT deprecated (P-STUDIO-TLS-PROFILES)', matched, wrong)


CHECKS = [
    ('G3 web ups states', check_ups_states),
    ('G3 web ups transitions', check_ups_transitions),
    ('G3 web ups change-state refusal', check_ups_change_state_refusal),
    ('G3 web qido', check_qido),
    ('G3 web wado', check_wado),
    ('G3 web event parser tags', check_event_parser_tags),
    ('G3 web status codes', check_status_codes),
    ('G3 web jpip text', check_jpip_text),
    ('G3 web tls mode', check_tls_mode),
]
