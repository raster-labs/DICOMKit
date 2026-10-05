#!/usr/bin/env python3
"""DICOMStudio group G1 — the CLI shell foundation (Models/CLIShellFoundationModel, Components/CLIShellFoundationHelpers),
the parameter builder (Models/ParameterBuilderModel, Components/ParameterBuilderHelpers), browser navigation
(Models/BrowserNavigationModel, Components/BrowserNavigationHelpers), Models/IntegrationTestingModel and
Components/IntegratedTerminalHelpers — row-by-row checks.

Loaded by diff_studio.py (``diff_studio_g1*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
Every check extracts the values the Swift source carries by regex and diffs them against the CLI surface or the
frozen 2026a DocBook:

  * tool names (ToolCategory.toolNames, ToolRegistryHelpers.allToolNames / totalToolCount, IntegrationTestToolCategory
    .toolNames / toolCount, ParameterCatalogHelpers.allToolNames, BrowserNavigation dicomStandardReference)
                                                        vs the Sources/dicom-* targets (every target listed once)
  * ToolRegistryHelpers.toolDescription service names    vs PS3.7 2026a 9.1.x DIMSE-C service titles, PS3.18 2026a
                                                           WADO-RS / QIDO-RS / STOW-RS / UPS-RS, PS3.4 Annex K / F.7
  * ParameterCatalogHelpers option and argument names    vs diff_cli.extract_options of the named tool (flat over
                                                           subcommands); picker values vs the option's String enum raw
                                                           values, its `--help` value list or CompressionManager.codecMap;
                                                           defaults vs the tool's defaults
  * validateAETitle 16 / validatePort / default port     vs PS3.5 2026a Table 6.2-1 (AE: 16 bytes maximum) and PS3.8 2026a
                                                           9.1.1 (ports 104 and 11112)
  * BrowserNavigationHelpers "PS3.x §y" citations        vs the 2026a DocBook section ids (PS3.7 and PS3.18 included,
                                                           which dk.check_citations leaves out)
  * CommandHistoryHelpers.redactPHI keywords             vs PS3.6 Table 6-1 (keyword → name) and PS3.15 Table E.1-1 rows
"""
import os
import re

PENDING_API_APPROVAL = {}
DEFERRED = {}
# ParameterCatalog rows deliberately not mirrored 1:1 with the CLI, with the reason (reported as notes).
EXEMPT = {
    '--transfer-syntax': 'values are DICOMConverter.aliasTokens, the shared catalog dicom-convert resolves (not a literal list)',
}

HERE = os.path.dirname(os.path.abspath(__file__))
ZW = '​'


def src(files, suffix):
    for name, s in files.items():
        if name.endswith(suffix):
            return s
    raise KeyError(suffix)


def tool_targets(ctx):
    return sorted(n for n in os.listdir(ctx['sources']) if n.startswith('dicom-') and os.path.isdir(os.path.join(ctx['sources'], n)))


def string_list(expr):
    return re.findall(r'"((?:[^"\\]|\\.)*)"', expr)


def switch_string_lists(body):
    """{case: [strings]} for `case .x: return [ ... ]` (multi-line) in a computed property."""
    out = {}
    for m in re.finditer(r'case\s+\.(\w+):\s*\n?\s*return\s*\[(.*?)\]', body, re.S):
        out[m.group(1)] = string_list(m.group(2))
    return out


def switch_ints(body):
    return {c: int(v) for c, v in re.findall(r'case\s+\.(\w+):\s*return\s+(\d+)', body)}


def switch_returns(body):
    return dict(re.findall(r'case\s+"?\.?([\w-]+)"?:\s*return\s+"((?:[^"\\]|\\.)*)"', body))


def prop_body(s, name):
    m = re.search(r'var ' + re.escape(name) + r'[^\n]*\{(.*?)\n    \}', s, re.S)
    return m.group(1) if m else ''


def extra_part(ctx, parts, n):
    """PS3.n loaded from the same --nema directory when diff_studio did not load it (7, 8)."""
    if n in parts:
        return parts[n]
    nema_dir = ctx.get('nema_dir')
    if not nema_dir:
        # recover the directory from a loaded part's file path when available
        for p in parts.values():
            path = getattr(p, 'path', None)
            if path:
                nema_dir = os.path.dirname(path)
                break
    if not nema_dir:
        # diff_studio.py passes no directory in ctx; take it from its own --nema argument
        import sys
        argv = sys.argv
        for i, a in enumerate(argv):
            if a == '--nema' and i + 1 < len(argv):
                nema_dir = argv[i + 1]
            elif a.startswith('--nema='):
                nema_dir = a.split('=', 1)[1]
        if not nema_dir and os.environ.get('NEMA_DIR'):
            nema_dir = os.environ['NEMA_DIR']
    if not nema_dir:
        return None
    path = os.path.join(nema_dir, f'part{n:02d}_2026a.xml')
    if not os.path.exists(path):
        return None
    part = ctx['nd'].Part(path)
    parts[n] = part
    return part


# --- tool names ------------------------------------------------------------------------------------------------

def check_tool_names(rep, parts, files, ctx):
    dw = ctx['dw']
    targets = set(tool_targets(ctx))
    model = src(files, 'CLIShellFoundationModel.swift')
    helpers = src(files, 'CLIShellFoundationHelpers.swift')
    integ = src(files, 'IntegrationTestingModel.swift')
    pbh = src(files, 'ParameterBuilderHelpers.swift')
    bnh = src(files, 'BrowserNavigationHelpers.swift')

    def diff(label, names, counts=None, total=None, subset=False):
        wrong, missing, matched = [], [], 0
        seen = {}
        for n in names:
            seen[n] = seen.get(n, 0) + 1
        for n, k in seen.items():
            if n not in targets:
                wrong.append(f'{label}: "{n}" is not a Sources/dicom-* target')
            elif k > 1:
                wrong.append(f'{label}: "{n}" listed {k} times')
            else:
                matched += 1
        if not subset:
            missing += [f'{label}: shipped tool "{t}" not listed' for t in sorted(targets - set(seen))]
        if total is not None and total != len(targets):
            wrong.append(f'{label}: total {total} but {len(targets)} Sources/dicom-* targets')
        return matched, wrong, missing

    cat = switch_string_lists(prop_body(dw.enum_body(model, 'ToolCategory'), 'toolNames'))
    m1, w1, mi1 = diff('ToolCategory.toolNames', [n for lst in cat.values() for n in lst])
    reg = string_list(re.search(r'allToolNames: \[String\] = \[(.*?)\n  \]', helpers, re.S).group(1))
    total = int(re.search(r'totalToolCount: Int = (\d+)', helpers).group(1))
    m2, w2, mi2 = diff('ToolRegistryHelpers.allToolNames', reg, total=total)
    if set(reg) != {n for lst in cat.values() for n in lst}:
        w2.append('ToolRegistryHelpers.allToolNames and ToolCategory.toolNames differ')
    body = dw.enum_body(integ, 'IntegrationTestToolCategory')
    icat = switch_string_lists(prop_body(body, 'toolNames'))
    icounts = switch_ints(prop_body(body, 'toolCount'))
    m3, w3, mi3 = diff('IntegrationTestToolCategory.toolNames', [n for lst in icat.values() for n in lst])
    for c, lst in icat.items():
        if icounts.get(c) != len(lst):
            w3.append(f'IntegrationTestToolCategory.{c}.toolCount {icounts.get(c)} != {len(lst)} names')
    pb = string_list(re.search(r'allToolNames: \[String\] = \[(.*?)\n    \]', pbh, re.S).group(1))
    m4, w4, _ = diff('ParameterCatalogHelpers.allToolNames', pb, subset=True)
    refs = re.findall(r'case "(dicom-[\w-]+)":\s*return "PS3', bnh)
    m5, w5, _ = diff('BrowserNavigationHelpers.dicomStandardReference', refs, subset=True)
    rep.check(f'Sources/dicom-* targets ({len(targets)}): the shell registry, integration scenarios, parameter catalog and browser references name real tools, each once',
              m1 + m2 + m3 + m4 + m5, w1 + w2 + w3 + w4 + w5, mi1 + mi2 + mi3)


# --- descriptions ------------------------------------------------------------------------------------------------

def check_descriptions(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    helpers = src(files, 'CLIShellFoundationHelpers.swift')
    m = re.search(r'static func toolDescription\(for toolName: String\) -> String \{(.*?)\n  \}', helpers, re.S)
    desc = switch_returns(m.group(1))
    matched, wrong, missing = 0, [], []
    p7 = extra_part(ctx, parts, 7)
    if p7 is None:
        missing.append('PS3.7 2026a DocBook not found beside the loaded parts (fetch part 7)')
    else:
        titles = {dw.section_title(p7, i) for i in dw.section_ids(p7) if re.fullmatch(r'sect_9\.1\.\d', i)}
        for tool, text in desc.items():
            for svc in re.findall(r'\bC-(?:ECHO|FIND|STORE|MOVE|GET)\b', text):
                if f'{svc} Service' in titles:
                    matched += 1
                else:
                    wrong.append(f'{tool}: "{svc}" is not a PS3.7 9.1.x service')
    p18 = parts.get(18)
    if p18 is not None:
        text18 = nd.norm(''.join(p18.root.itertext()))
        for tool, text in desc.items():
            for svc in re.findall(r'\b(?:WADO|QIDO|STOW|UPS)-(?:RS|URI)\b', text):
                if svc in text18:
                    matched += 1
                else:
                    wrong.append(f'{tool}: "{svc}" does not occur in PS3.18 2026a')
    p4 = parts.get(4)
    if p4 is not None:
        text4 = nd.norm(''.join(p4.root.itertext()))
        for tool, phrase in (('dicom-mwl', 'Modality Worklist'), ('dicom-mpps', 'Modality Performed Procedure Step')):
            if phrase in desc.get(tool, '') and phrase in text4:
                matched += 1
            elif phrase not in desc.get(tool, ''):
                wrong.append(f'{tool}: description no longer names "{phrase}"')
    # every target has a description row (the default is a placeholder)
    for t in tool_targets(ctx):
        if t not in desc:
            missing.append(f'toolDescription has no row for shipped tool {t}')
    rep.check('ToolRegistryHelpers.toolDescription: DIMSE-C names are PS3.7 2026a 9.1.x services, RESTful names occur in PS3.18 2026a, every shipped tool has a row',
              matched, wrong, missing)


# --- parameter builder vs the CLI surface -------------------------------------------------------------------------

def balanced_call(s, i):
    """s[i] is the '(' of a call -> the text inside the matching ')' (string literals skipped)."""
    depth, j = 0, i
    while j < len(s):
        c = s[j]
        if c == '"':
            j += 1
            while j < len(s) and s[j] != '"':
                j += 2 if s[j] == '\\' else 1
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return s[i + 1:j]
        j += 1
    return s[i + 1:]


def param_rows(chunk):
    """[(name, type_expr, default_expr)] of every `param("name", ..., type: X[, required: ..][, defaultValue: Y])`."""
    out = []
    for m in re.finditer(r'\bparam\(', chunk):
        inner = balanced_call(chunk, m.end() - 1)
        name = re.match(r'\s*"([^"]+)"', inner).group(1)
        tm = re.search(r'type:\s*(.*?)(?:,\s*required:|,\s*defaultValue:|,\s*group:|$)', inner, re.S)
        dm = re.search(r'defaultValue:\s*(\.\w+\((?:[^()]|\([^()]*\))*\))', inner)
        out.append((name, tm.group(1).strip() if tm else '', dm.group(1) if dm else None))
    return out


def catalog_params(pbh):
    """[(tool, subcommand or None, name, type_expr, default_expr)] of the ParameterCatalogHelpers builders."""
    out = []
    shared = re.search(r'private static func networkParameters\(.*?\n    \}', pbh, re.S).group(0)
    shared_rows = param_rows(shared)
    for m in re.finditer(r'private static func (dicom\w+)\(\) -> ToolParameterConfig \{\n\s*ToolParameterConfig\(\n\s*toolName: "([^"]+)",(.*?)\n    \}\n', pbh, re.S):
        tool, body = m.group(2), m.group(3)
        subs = list(re.finditer(r'ToolSubcommand\(\s*name: "([^"]+)"', body))
        if subs:
            for i, sm in enumerate(subs):
                end = subs[i + 1].start() if i + 1 < len(subs) else len(body)
                out += [(tool, sm.group(1)) + row for row in param_rows(body[sm.start():end])]
        else:
            out += [(tool, None) + row for row in param_rows(body)]
        nm = re.search(r'networkParameters\(.*?timeoutDefault:\s*(\d+)', body, re.S)
        if nm:
            out += [(tool, None, name, typ, (default or '').replace('timeoutDefault', nm.group(1)) or None)
                    for name, typ, default in shared_rows]
    return out


def enum_values(files_of_tool, type_name):
    """Raw values (and declared aliases) of a String enum in the tool's sources."""
    for s in files_of_tool.values():
        m = re.search(r'enum\s+' + re.escape(type_name) + r'\s*:\s*String[^{]*\{', s)
        if not m:
            continue
        depth, i = 0, m.end() - 1
        while i < len(s):
            depth += s[i] == '{'
            depth -= s[i] == '}'
            if depth == 0:
                break
            i += 1
        body = s[m.end():i]
        vals = []
        for cm in re.finditer(r'^\s*case\s+(\w+)(?:\s*=\s*"([^"]*)")?', body, re.M):
            vals.append(cm.group(2) if cm.group(2) is not None else cm.group(1))
        vals += re.findall(r'aliases[^\n]*=\s*\[([^\]]*)\]', body) and re.findall(r'"(\w+)":', re.search(r'aliases[^\n]*=\s*\[([^\]]*)\]', body).group(1)) or []
        return vals
    return None


def help_values(help_text):
    """`Output format: text, json, csv.` / `... : auto (default), metal, ...` -> the listed words."""
    m = re.search(r':\s*([a-z0-9-]+(?:\s*\([^)]*\))?(?:,\s*[a-z0-9-]+(?:\s*\([^)]*\))?)+)', help_text)
    if not m:
        return None
    return [re.sub(r'\s*\(.*', '', v).strip() for v in m.group(1).split(',')]


def check_parameter_builder(rep, parts, files, ctx):
    dc, dw = ctx['dc'], ctx['dw']
    pbh = src(files, 'ParameterBuilderHelpers.swift')
    rows = catalog_params(pbh)
    matched, wrong, extra = 0, [], []
    codec_names = None
    cm_path = os.path.join(ctx['sources'], 'DICOMKit', 'Compression', 'CompressionManager.swift')
    if os.path.exists(cm_path):
        cm = dw.read(cm_path)
        body = re.search(r'codecMap[^=]*=\s*\[(.*?)\n    \]', cm, re.S).group(1)
        codec_names = {n for lst in re.findall(r'\(\[([^\]]*)\]', body) for n in string_list(lst)}
    quality_words = None
    cc_path = os.path.join(ctx['sources'], 'DICOMKit', 'Compression', 'CompressionConsole.swift')
    if os.path.exists(cc_path):
        quality_words = set(re.findall(r'case "(\w+)":\s*return \.\w+', dw.read(cc_path)))
    surfaces = {}
    for tool, sub, name, typ, default in rows:
        if tool not in surfaces:
            surfaces[tool] = dc.surface(tool)
        tfiles, options, _, commands = surfaces[tool]
        label = f'{tool}{" " + sub if sub else ""} {name}'
        if sub and sub not in commands:
            wrong.append(f'{label}: subcommand "{sub}" is not a {tool} command ({", ".join(commands)})')
            continue
        opt = next((o for o in options if name in o['names']), None)
        if opt is None:
            if name in EXEMPT:
                extra.append(f'{label}: exempt — {EXEMPT[name]}')
            else:
                wrong.append(f'{label}: not an option or argument of {tool} (surface: {", ".join(sorted({n for o in options for n in o["names"]}))[:160]}…)')
            continue
        matched += 1
        # picker / radio values
        vm = re.match(r'\.(?:picker|radio)\(options: options\((\[.*\]|[\w.]+)\)\)\s*$', typ, re.S)
        if vm:
            if not vm.group(1).startswith('['):
                if name in EXEMPT:
                    extra.append(f'{label}: values computed — {EXEMPT[name]}')
                else:
                    wrong.append(f'{label}: picker values are computed ({vm.group(1)}) and not checked')
            else:
                offered = string_list(vm.group(1))
                accepted = None
                typ_name = re.sub(r'[?\[\]]', '', opt['type']).strip()
                if typ_name not in ('String', 'Int', 'Bool', 'Double', 'UInt16'):
                    accepted = enum_values(tfiles, typ_name.split('.')[-1])
                if accepted is None and name == '--codec' and codec_names:
                    accepted = codec_names
                if accepted is None and name == '--quality' and quality_words:
                    accepted = quality_words
                if accepted is None and name == '--profile':
                    anon = dw.read(os.path.join(ctx['sources'], tool, 'AnonCLISupport.swift'))
                    accepted = re.findall(r'^\s*"([\w-]+)":\s*\.', re.search(r'profileAliases[^\[]*\[(.*?)\n    \]', anon, re.S).group(1), re.M)
                if accepted is None:
                    accepted = help_values(opt['help'])
                if accepted is None:
                    wrong.append(f'{label}: accepted values of {opt["type"]} not found')
                else:
                    for v in offered:
                        if v in accepted:
                            matched += 1
                        else:
                            wrong.append(f'{label}: picker value "{v}" is not accepted ({", ".join(sorted(accepted))})')
        # defaults
        if default:
            dm = re.search(r'\.(?:int|string|directoryPath)\(\s*"?([^")]+)"?\s*\)', default)
            ours = dm.group(1) if dm else default
            if ours in ('defaultDICOMPort', 'defaultCalledAETitle'):
                ours = re.search(r'static let ' + ours + r'\s*=\s*"?([^"\n]+?)"?\n', pbh).group(1)
            cli = opt['default'].strip().strip('"')
            if re.match(r'\.[A-Za-z]', cli):
                cli = cli[1:]                       # `.study` enum case
            doc = opt['documented_default']
            if cli in ('', '—') and doc:
                cli = re.sub(r'[,;].*', '', doc).strip()
            if cli == 'AnonCLI.defaultProfile':
                cli = re.search(r'static let defaultProfile = "([^"]+)"', dw.read(os.path.join(ctx['sources'], tool, 'AnonCLISupport.swift'))).group(1)
            if cli in ('cMove',):
                cli = 'c-move'
            if ours == cli:
                matched += 1
            else:
                wrong.append(f'{label}: default {ours!r} but the CLI default is {cli!r}')
    rep.check(f'ParameterCatalogHelpers: {len(rows)} rows of the 12 tool forms are options/arguments of the named tool; picker values are accepted; defaults agree',
              matched, wrong, [], extra)


def check_parameter_builder_standard(rep, parts, files, ctx):
    nd = ctx['nd']
    pbh = src(files, 'ParameterBuilderHelpers.swift')
    model = src(files, 'ParameterBuilderModel.swift')
    matched, wrong, missing = 0, [], []
    p5 = parts.get(5)
    if p5 is not None:
        ae = next((r for r in p5.rows(p5.table('6.2-1')) if r and r[0].replace(ZW, '').startswith('AE')), None)
        std_len = re.search(r'(\d+) bytes maximum', ae[-1]) if ae else None
        ours = re.search(r'title\.count > (\d+)', pbh)
        if std_len and ours and std_len.group(1) == ours.group(1):
            matched += 1
        else:
            wrong.append(f'validateAETitle limit {ours.group(1) if ours else "?"} vs PS3.5 Table 6.2-1 AE "{std_len.group(0) if std_len else ae}"')
        if 'uppercase' in model.lower() and 'not restricted to upper case' not in model:
            wrong.append('ParameterBuilderModel claims AE Titles are uppercase; PS3.5 Table 6.2-1 does not')
    p8 = extra_part(ctx, parts, 8)
    if p8 is None:
        missing.append('PS3.8 2026a DocBook not found beside the loaded parts (fetch part 8)')
    else:
        text = nd.norm(''.join(p8.root.itertext()))
        port = re.search(r'static let defaultDICOMPort = (\d+)', pbh).group(1)
        if re.search(r'"registered" port number ' + port, text):
            matched += 1
        else:
            wrong.append(f'default port {port} is not the PS3.8 registered DICOM port')
        for cite in set(re.findall(r'PS3\.8(?: 2026a)? (\d[\d.]*)', pbh + model)):
            sid = f'sect_{cite}'
            sec = ctx['dw'].section_by_id(p8, sid)
            if sec is not None and port in nd.norm(''.join(sec.itertext())):
                matched += 1
            else:
                wrong.append(f'"PS3.8 {cite}" does not exist or does not name port {port}')
        if re.search(r'port < 1 \|\| port > 65535', pbh):
            matched += 1
        else:
            wrong.append('validatePort range is not 1-65535')
    rep.check('PS3.5 Table 6.2-1 (AE 16 bytes) and PS3.8 9.1.1 (registered port 11112): parameter builder validation limits and the default port',
              matched, wrong, missing)


# --- browser citations ---------------------------------------------------------------------------------------

def check_browser_citations(rep, parts, files, ctx):
    dw = ctx['dw']
    bnh = src(files, 'BrowserNavigationHelpers.swift')
    model = src(files, 'BrowserNavigationModel.swift')
    cites = re.findall(r'return "PS3\.(\d+)(?: §([A-Z0-9][\w.]*))?"', bnh) + re.findall(r'e\.g\. "PS3\.(\d+) §([A-Z0-9][\w.]*)"', model)
    matched, wrong, missing = 0, [], []
    for part_no, sect in cites:
        n = int(part_no)
        p = parts.get(n) or extra_part(ctx, parts, n)
        if p is None:
            missing.append(f'PS3.{n} 2026a DocBook not available for "PS3.{n} §{sect}"')
            continue
        if not sect:
            matched += 1          # a whole-part reference
            continue
        sid = f'sect_{sect}' if '.' in sect else f'chapter_{sect}'
        title = dw.section_title(p, sid)
        if title:
            matched += 1
        else:
            wrong.append(f'"PS3.{n} §{sect}" does not exist in PS3.{n} 2026a')
    rep.check(f'BrowserNavigation: {len(cites)} "PS3.x §y" references are 2026a sections (PS3.7 and PS3.18 included)', matched, wrong, missing)


# --- redactPHI keywords --------------------------------------------------------------------------------------

def check_phi_keywords(rep, parts, files, ctx):
    ith = src(files, 'IntegratedTerminalHelpers.swift')
    m = re.search(r'let phiAttributes = \[(.*?)\]', ith, re.S)
    keywords = string_list(m.group(1)) if m else []
    p6, p15 = parts.get(6), parts.get(15)
    if p6 is None or p15 is None:
        rep.check('PS3.15 Table E.1-1: redactPHI keywords', 0, [], ['PS3.6 or PS3.15 not loaded'])
        return
    kw_to_name = {}
    for row in p6.rows(p6.table('6-1')):
        if len(row) >= 3:
            kw_to_name[row[2].replace(ZW, '')] = row[1].replace(ZW, '')
    e11 = {row[0].replace(ZW, '').strip() for row in p15.rows(p15.table('E.1-1'))}
    matched, wrong = 0, []
    for k in keywords:
        name = kw_to_name.get(k)
        if name is None:
            wrong.append(f'"{k}" is not a PS3.6 Table 6-1 keyword')
        elif name not in e11:
            wrong.append(f'"{k}" ({name}) is not a row of PS3.15 Table E.1-1')
        else:
            matched += 1
    rep.check(f'PS3.15 Table E.1-1: the {len(keywords)} CommandHistoryHelpers.redactPHI keywords are Table 6-1 keywords of E.1-1 attributes', matched, wrong)


def check_injected_parameters(rep, parts, files, ctx):
    """Every flagName that NetworkInjectorHelpers injects is an option (or the positional) of the DIMSE tools /
    dicom-wado."""
    dc = ctx['dc']
    helpers = src(files, 'ShellServerConfigHelpers.swift')
    def flags(func):
        m = re.search(r'static func ' + func + r'\(.*?\n    \}\n', helpers, re.S)
        return sorted(set(re.findall(r'flagName:\s*"([^"]+)"', m.group(0)))) if m else []
    matched, wrong = 0, []
    for func, tools in (('dicomParameters', ['dicom-echo', 'dicom-send', 'dicom-query', 'dicom-retrieve',
                                             'dicom-qr', 'dicom-mwl', 'dicom-mpps']),
                        ('dicomwebParameters', ['dicom-wado'])):
        names = flags(func)
        for tool in tools:
            _, options, _, _ = dc.surface(tool)
            known = {n for o in options for n in o['names']}
            for f in names:
                if f in known:
                    matched += 1
                else:
                    wrong.append(f'ShellServerConfigHelpers.{func}: {f} is not a {tool} option')
    rep.check('shell: injected server parameters are real options of the DIMSE tools / dicom-wado', matched, wrong)


CHECKS = [
    ('shell: injected server parameters exist in the CLI surface', check_injected_parameters),
    ('shell: tool names are the Sources/dicom-* targets', check_tool_names),
    ('shell: tool descriptions name PS3.7 / PS3.18 / PS3.4 services', check_descriptions),
    ('shell: parameter builder options exist in the CLI surface', check_parameter_builder),
    ('shell: parameter builder AE/port limits vs PS3.5 / PS3.8', check_parameter_builder_standard),
    ('shell: browser navigation PS3 citations', check_browser_citations),
    ('shell: redactPHI keywords vs PS3.15 Table E.1-1', check_phi_keywords),
]
