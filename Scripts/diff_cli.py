#!/usr/bin/env python3
"""Extract the parameter contract of every `dicom-*` CLI tool from its Swift source and diff it
against the frozen DICOM DocBook.

Usage:
    for p in 3 4 5 6 7 10 11 15 16 18 19; do python3 Scripts/nema_docbook.py fetch 2026a $p --out DIR; done
    python3 Scripts/diff_cli.py --nema DIR [--group G1] [--tool dicom-echo] [--verbose] [--only NAME]
    python3 Scripts/diff_cli.py --nema DIR --emit-contract dicom-echo     # markdown tables for the report

Each tool is an adapter over a DICOMKit engine that was verified separately (DICOMKIT_STANDARD_IMPLEMENTATION.md).
What this script checks is the tool's *surface*: every option, flag and argument (the input contract) and
every JSON key, XML element, printed label and exit code (the output contract). The code side is extracted
from the Swift source by regex (never transcribed); the standard side is extracted from the DocBook tables
named in CONTRACT; the two are diffed row by row. The generic DICOMKit checks (UID registry, A-1 names,
coded concepts, citations, CS literals, de-identification, video limits) are re-run over the tool sources
through diff_kit / diff_web, so a literal that is wrong in a tool is caught even when no contract row names it.

Statuses: `ok`; `FAIL` (the tool contradicts the text; exit 1); `PEND` (the fix changes a public option
name/value/JSON key or a shared DICOMKit type and waits for the owner); `DEFR` (the value lives in another
module and is a Deferred finding, D-number given). Results: DICOMCLI_STANDARD_IMPLEMENTATION.md.
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCES = os.path.join(ROOT, 'Sources')


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


nd = load('nema_docbook')
dw = load('diff_web')
dk = load('diff_kit')
D, X = nd.D, nd.X

GROUPS = {
    'G1': ['dicom-echo', 'dicom-send', 'dicom-query', 'dicom-qr', 'dicom-retrieve', 'dicom-mwl', 'dicom-mpps',
           'dicom-server', 'dicom-gateway', 'dicom-print', 'dicom-printscp', 'dicom-wado', 'dicom-jpip', 'dicom-cloud'],
    'G2': ['dicom-dump', 'dicom-info', 'dicom-tags', 'dicom-json', 'dicom-xml', 'dicom-dcmdir', 'dicom-uid',
           'dicom-validate', 'dicom-diff', 'dicom-split', 'dicom-merge', 'dicom-study', 'dicom-archive', 'dicom-export'],
    'G3': ['dicom-compress', 'dicom-convert', 'dicom-j2k', 'dicom-image', 'dicom-pixedit', 'dicom-video',
           'dicom-pdf', 'dicom-anon'],
    'G4': ['dicom-ai', 'dicom-report', 'dicom-measure', 'dicom-3d', 'dicom-viewer', 'dicom-script'],
}
ALL_TOOLS = [t for g in GROUPS.values() for t in g]

# Findings whose fix changes a public option name, an accepted value, a JSON key or a shared DICOMKit
# type, waiting for the owner (PEND). Key: substring of the finding text; value: P-item name.
PENDING_API_APPROVAL = {
    'RetrieveStatusText': 'P-QR-STATUS-TEXT',
    '--parallel': 'P-QR-PARALLEL',
    'QRSessionState': 'P-QR-STATE-MODALITIES',
    'QueryOutputFormat': 'P-QUERY-JSON',       # dicom-query --format dicom-json (PS3.18 F.2) is additive but touches the shared type
    'column label': 'P-QUERY-COLUMNS',         # table/CSV labels to PS3.6 names (shared formatter, Studio parity)
    'sendSummary': 'P-SEND-SUMMARY',           # warning count in NetworkConsole.sendSummary
    'STD-GEN-DVD': 'P-DCMDIR-PROFILE',   # legacy alias spellings accepted by dicom-dcmdir --profile
    'STD-GEN-USB': 'P-DCMDIR-PROFILE',
}
# Findings whose cause lives in another module (DEFR, with their D-number).
DEFERRED = {
    'DIMSEStatus.description': 'D76 (DICOMNetwork: Q/R status wording)',
    'Level: Instance': 'D77 (DICOMNetwork: console labels)',
    'StoreResult.success': 'D72 (DICOMNetwork: Warning class not success, Failure returned not thrown)',
    'DIMSEStatus.from': 'D73 (DICOMNetwork: 0210/0211/0212/0117 names missing)',
    'levelName': 'D74 (DICOMNetwork: levelName(.image) prints "instance")',
    'NetworkConsoleFormatter': 'D75 (DICOMNetwork: no Warning rendering for C-STORE)',
    'DICOMDIRWriter': 'D70 (DICOMKit: profile not enforced on transfer syntax / SOP Class)',
}


# --- code side: ArgumentParser surface ---------------------------------------------------------

ATTR = re.compile(r'@(Argument|Option|Flag|OptionGroup)\s*(\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?\s*'
                  r'(?:\n\s*)?var\s+`?(\w+)`?\s*(?::\s*([^=\n{]+?))?\s*(?:=\s*([^\n]+?))?\s*(?://[^\n]*)?\n', re.S)
HELP = re.compile(r'help:\s*(?:"""(.*?)"""|"((?:[^"\\]|\\.)*)")', re.S)
CUSTOM = re.compile(r'\.custom(Long|Short)\("([^"]+)"\)')
INLINE_DEFAULT = re.compile(r'\(default:\s*([^)]*)\)')


def kebab(name):
    return re.sub(r'([a-z0-9])([A-Z])', r'\1-\2', name).lower()


def swift_help(text):
    text = re.sub(r'\\\s*\n\s*', '', text)                  # line continuation inside """
    text = text.replace('\\"', '"').replace('\\n', ' ')
    return nd.norm(text)


def option_names(kind, attr, var):
    if kind == 'Argument':
        return [f'<{kebab(var)}>']
    names = []
    custom = CUSTOM.findall(attr or '')
    for which, val in custom:
        names.append(('--' if which == 'Long' else '-') + val)
    if not attr or 'name:' not in attr:
        names.append('--' + kebab(var))
    else:
        if '.shortAndLong' in attr:
            names += ['-' + var[0], '--' + kebab(var)]
        elif '.short' in attr and not custom:
            names.append('-' + var[0])
        if '.long' in attr and not custom:
            names.append('--' + kebab(var))
    if 'inversion' in (attr or ''):
        names = [n for n in names] + ['--no-' + kebab(var).replace('enable-', '', 1) if False else '--no-' + kebab(var)]
    return names or ['--' + kebab(var)]


def balanced(src, i):
    """src[i] == '(' -> index just past the matching ')', skipping string literals."""
    depth, j, n = 0, i, len(src)
    while j < n:
        if src.startswith('"""', j):
            k = src.find('"""', j + 3)
            j = (k + 3) if k >= 0 else n
            continue
        c = src[j]
        if c == '"':
            j += 1
            while j < n and src[j] != '"':
                if src[j] == '\\' and j + 1 < n and src[j + 1] == '(':
                    j = balanced(src, j + 1)
                    continue
                j += 2 if src[j] == '\\' else 1
            j += 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return n


DECL = re.compile(r'@(Argument|Option|Flag|OptionGroup)\b')
VAR = re.compile(r'\s*(?:(?:public|private|internal|fileprivate|lazy)\s+)*var\s+`?(\w+)`?\s*(?::\s*([^=\n{]+?))?\s*(?:=\s*([^\n]+?))?\s*(?://[^\n]*)?\n')


def extract_options(src, fname):
    """Every @Argument / @Option / @Flag of a file: kind, names, help, swift type, default, line."""
    out = []
    for m in DECL.finditer(src):
        kind, j = m.group(1), m.end()
        attr = ''
        if j < len(src) and src[j] == '(':
            k = balanced(src, j)
            attr, j = src[j:k], k
        v = VAR.match(src, j)
        if not v or kind == 'OptionGroup':
            continue
        var, typ, default = v.group(1), (v.group(2) or '').strip(), (v.group(3) or '').strip()
        hm = HELP.search(attr)
        help_text = swift_help(hm.group(1) or hm.group(2) or '') if hm else ''
        if not default and kind == 'Flag':
            default = 'false'
        documented = INLINE_DEFAULT.search(help_text)
        out.append({
            'file': fname, 'line': src.count('\n', 0, m.start()) + 1, 'kind': kind, 'var': var,
            'names': option_names(kind, attr, var), 'type': typ, 'default': default,
            'documented_default': documented.group(1).strip() if documented else '', 'help': help_text,
        })
    return out


def struct_name_for_var(src, pos):
    """The ParsableCommand (sub)command that encloses position `pos`."""
    best = None
    for m in re.finditer(r'struct\s+(\w+)\s*:\s*(?:Async)?ParsableCommand', src):
        if m.start() < pos:
            best = m.group(1)
    return best


def extract_commands(src):
    """Command names: explicit `commandName:` literals, else the kebab-cased ParsableCommand struct name
    (ArgumentParser's default)."""
    out = []
    for m in re.finditer(r'struct\s+(\w+)\s*:\s*(?:Async)?ParsableCommand\s*\{', src):
        body = src[m.end():m.end() + 2000]
        cm = re.search(r'commandName:\s*"([^"]+)"', body.split('\n    }')[0])
        out.append(cm.group(1) if cm else kebab(m.group(1)))
    return out


def extract_outputs(src, fname):
    """JSON keys, printed labels and exit codes a file emits."""
    out = {'json_keys': set(), 'labels': set(), 'exit_codes': set(), 'enum_values': set()}
    for m in re.finditer(r'"([A-Za-z][A-Za-z0-9_]*)"\s*:\s*(?!\s*\[?\s*"[A-Z]{2}")', src):
        out['json_keys'].add(m.group(1))
    for m in re.finditer(r'print\(\s*"((?:[^"\\]|\\.)*?)"', src):
        label = m.group(1)
        label = re.sub(r'\\\(.*?\)', '…', label)
        if ':' in label:
            out['labels'].add(label.split(':')[0].strip(' -•✓✗⚠️📊📋ℹ'))
    for m in re.finditer(r'ExitCode\((\d+)\)|exit\((\d+)\)|ExitCode\.(\w+)', src):
        out['exit_codes'].add(m.group(1) or m.group(2) or m.group(3))
    for m in re.finditer(r'case\s+\w+\s*=\s*"([^"]+)"', src):
        out['enum_values'].add(m.group(1))
    return out


def tool_files(tool):
    return dw.read_all(os.path.join(SOURCES, tool))


def surface(tool):
    files = tool_files(tool)
    options, outputs, commands = [], {}, []
    for fname, src in files.items():
        options += extract_options(src, fname)
        outputs[fname] = extract_outputs(src, fname)
        commands += extract_commands(src)
    return files, options, outputs, commands


# --- standard side -----------------------------------------------------------------------------

def a1(p6):
    """PS3.6 Table A-1: uid -> (name, type)."""
    return dw.uid_registry(p6)


def transfer_syntaxes(p6):
    return {u: v for u, v in a1(p6).items() if v[1] == 'Transfer Syntax'}


def status_codes(p7):
    """PS3.7 Annex C: status value (hex) -> (class, meaning) from Tables C.4-1 … C.4-N plus 0000 / FF00 / FF01."""
    out = {}
    for lab, cap, t in p7.tables():
        if not lab.startswith('C.4-') and not lab.startswith('C.'):
            continue
        for row in p7.rows(t):
            if len(row) >= 3 and re.fullmatch(r'[0-9A-F]{4}(?:-[0-9A-F]{4})?|[0-9A-F]{2}xx', row[1].strip()):
                out[row[1].strip()] = (row[0].strip(), row[2].strip(), lab)
    return out


def enumerated_terms(p3, attribute_name, table_label=None):
    lab, kind, terms = dk.attribute_terms(p3, attribute_name, table_label)
    return lab, kind, terms


# --- checks -------------------------------------------------------------------------------------

def split_pending(items):
    pending = [i for i in items if any(k in i for k in PENDING_API_APPROVAL)]
    deferred = [i for i in items if any(k in i for k in DEFERRED)]
    wrong = [i for i in items if i not in pending and i not in deferred]
    return wrong, pending, deferred


def check_generic(rep, parts, tool, files, tags, local_tags):
    """Re-run the DICOMKit literal checks over one tool's sources."""
    uid_files = {n: re.sub(r'hasPrefix\("1\.2\.840\.10008[\d.]*"\)', 'hasPrefix("")', s) for n, s in files.items()}
    dw.check_uids(rep, parts[6], uid_files)
    check_uids_in_text(rep, parts[6], tool, files)
    dk.check_coded_concepts(rep, parts[16], files)
    dk.check_tag_names(rep, parts[6], files, local_tags)
    dk.check_citations(rep, {n: p for n, p in parts.items() if n in (3, 4, 5, 6, 10, 15, 16)}, files)
    dk.check_cs_literals(rep, parts[3], parts[6], files, tags)
    dk.check_photometric_terms(rep, parts[3], files)


def help_and_label_strings(src):
    """Only text the user sees: help strings, abstracts/discussions and print literals."""
    out = []
    for m in HELP.finditer(src):
        out.append((m.start(), swift_help(m.group(1) or m.group(2) or '')))
    for m in re.finditer(r'(?:abstract|discussion):\s*(?:"""(.*?)"""|"((?:[^"\\]|\\.)*)")', src, re.S):
        out.append((m.start(), swift_help(m.group(1) or m.group(2) or '')))
    for m in re.finditer(r'print\(\s*"((?:[^"\\]|\\.)*?)"', src):
        out.append((m.start(), m.group(1)))
    return out


def check_uids_in_text(rep, p6, tool, files):
    """Every 1.2.840.10008.* UID anywhere in the tool's source (help rows, discussion, README-style strings),
    not only quoted literals, is registered in PS3.6 Table A-1 (or is a known prefix / root)."""
    std = dw.uid_registry(p6)
    matched, unknown, seen = 0, [], set()
    for fname, src in files.items():
        for m in re.finditer(r'(?<![\d.])(1\.2\.840\.10008(?:\.\d+)+)(?![\d])', src):
            uid = m.group(1).rstrip('.')
            if uid in seen:
                continue
            seen.add(uid)
            if uid in std or any(k.startswith(uid + '.') for k in std):
                matched += 1
            else:
                unknown.append(f'{tool}/{fname}:{src.count(chr(10), 0, m.start()) + 1}: {uid} is not in PS3.6 Table A-1')
    wrong, pending, deferred = split_pending(unknown)
    rep.check(f'{tool}: every 1.2.840.10008.* UID in the source (incl. help text) is registered in PS3.6 Table A-1',
              matched, wrong, pending=pending)


def check_transfer_syntax_names(rep, p6, tool, files, options):
    """User-visible text that ties a name to a transfer syntax by its UID suffix — "JPEG XL Lossless (.4.110)",
    "… (1.2.840.10008.1.2.4.90)" — must spell the name as PS3.6 Table A-1 (modulo norm_name). Names next to a
    full UID literal in code are covered by diff_web.check_uids; bare family names are not claims."""
    ts = transfer_syntaxes(p6)
    by_suffix = {}
    for uid, (name, _) in ts.items():
        for n in (2, 3):
            by_suffix['.' + '.'.join(uid.split('.')[-n:])] = (uid, name)
    matched, wrong = 0, []
    pat = re.compile(r'([A-Z][A-Za-z0-9 /()+-]{2,60}?)\s*\((\.\d+\.\d+(?:\.\d+)?|1\.2\.840\.10008\.1\.2(?:\.\d+)*)\)')
    for fname, src in files.items():
        for pos, text in help_and_label_strings(src):
            for m in pat.finditer(text):
                cand, suf = m.group(1).strip(' -–:'), m.group(2)
                hit = ts.get(suf) or by_suffix.get(suf)
                if not hit:
                    continue
                uid, name = (suf, ts[suf][0]) if suf in ts else hit
                a, b = dw.norm_name(cand), dw.norm_name(name)
                if a == b or a.endswith(b) or b.endswith(a):
                    matched += 1
                else:
                    line = src.count('\n', 0, pos) + 1
                    wrong.append(f'{tool}/{fname}:{line}: "{cand}" for {uid}; A-1 "{name}"')
    wrong, pending, deferred = split_pending(wrong)
    rep.check(f'{tool}: transfer-syntax names tied to a UID in help/labels spelled as PS3.6 Table A-1', matched, wrong,
              pending=pending, extra=[f'DEFR {DEFERRED[k]}: {i}' for i in deferred for k in DEFERRED if k in i])


def raw_value(files, case_name):
    for src in files.values():
        m = re.search(r'case\s+' + re.escape(case_name) + r'\s*=\s*"([^"]+)"', src)
        if m:
            return m.group(1)
    return case_name


def check_documented_defaults(rep, tool, files, options):
    """A `(default: X)` in help text must equal the Swift default (enum cases resolved to their raw value)."""
    matched, wrong = 0, []
    for o in options:
        doc, code = o['documented_default'].strip('"'), o['default'].strip('"')
        if not doc or not code:
            continue
        if code.startswith('.'):
            code = raw_value(files, code[1:])
        if o['kind'] == 'Flag' and doc.lower() not in ('true', 'false'):
            continue   # "(default: on)" for an inverted flag is prose, checked per contract row
        try:
            same = float(doc) == float(code)
        except ValueError:
            same = doc.lower() == code.lower()
        if same:
            matched += 1
        else:
            wrong.append(f"{tool}/{o['file']}:{o['line']}: {o['names'][-1]} help says default {doc!r}, code default {code!r}")
    rep.check(f'{tool}: documented defaults equal the code defaults', matched, wrong)


# Per-tool contract rows live in Scripts/cli_contracts.py: option -> (concept, reference, allowed/note, verdict).
CONTRACT = load('cli_contracts').CONTRACT


def check_contract(rep, parts, tool, options):
    """Every contract row names a real option (a row may be qualified by subcommand, combine short and
    long spellings, or be a parenthesised "(not exposed)" row for a standard concept the tool lacks)."""
    rows = CONTRACT.get(tool, {})
    known = {n for o in options for n in o['names']}
    def names_real(key):
        if key.startswith('('):
            return True
        return any(tok in known for tok in re.split(r'[,\s]+', key))
    missing = [f'{tool}: contract row {k} names no option in the source' for k in rows if not names_real(k)]
    rep.check(f'{tool}: contract rows name real options', len(rows) - len(missing), missing)


# --- report emission -----------------------------------------------------------------------------

def emit_contract(parts, tool):
    files, options, outputs, commands = surface(tool)
    rows = CONTRACT.get(tool, {})
    print(f'### {tool}\n')
    print(f'Commands: {", ".join(commands) or "(single)"} · files: {", ".join(files)}\n')
    print('**Input contract**\n')
    print('| Option | DICOM concept | 2026a reference | Allowed per standard | Code accepts | Default (std) | Default (code) | Verdict |')
    print('|---|---|---|---|---|---|---|---|')
    for o in options:
        name = ', '.join(o['names'])
        row = rows.get(o['names'][-1]) or rows.get(o['names'][0])
        concept, ref, allowed, verdict = (row + ('', ''))[:4] if row else ('', '', '', 'plumbing')
        accepts = o['type'].replace('|', '\\|')
        print(f"| `{name}` | {concept} | {ref} | {allowed} | `{accepts}` | | `{o['default'] or '—'}` | {verdict} |")
    print('\n**Output contract**\n')
    print('| Field | DICOM source | Encoding (standard) | Encoding (code) | Verdict |')
    print('|---|---|---|---|---|')
    for fname, o in outputs.items():
        for k in sorted(o['json_keys']):
            print(f'| JSON `{k}` ({fname}) | | | | |')
        for k in sorted(o['labels']):
            print(f'| label `{k}` ({fname}) | | | | |')
        for k in sorted(o['exit_codes']):
            print(f'| exit `{k}` ({fname}) | | | | |')
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True)
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--group', choices=sorted(GROUPS))
    ap.add_argument('--tool', action='append')
    ap.add_argument('--verbose', action='store_true')
    ap.add_argument('--only', help='run only checks whose name contains this text')
    ap.add_argument('--emit-contract', metavar='TOOL', help='print the report tables for one tool and exit')
    ap.add_argument('--list-surface', action='store_true', help='print the extracted options per tool and exit')
    args = ap.parse_args()

    tools = args.tool or (GROUPS[args.group] if args.group else ALL_TOOLS)
    if args.emit_contract:
        emit_contract({}, args.emit_contract)
        return
    parts = {}
    if not args.list_surface:
        for n in (3, 4, 5, 6, 7, 10, 11, 15, 16, 18, 19):
            path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
            if not os.path.exists(path):
                print(f'missing {path} (fetch it); checks needing PS3.{n} are skipped', file=sys.stderr)
                continue
            parts[n] = nd.Part(path)
            if args.edition not in parts[n].subtitle:
                sys.exit(f'{path}: subtitle {parts[n].subtitle!r} does not name {args.edition}')
            print(f'using {path}: {parts[n].subtitle}')
    if args.list_surface:
        for tool in tools:
            files, options, outputs, commands = surface(tool)
            print(f'== {tool}: {len(options)} options, commands {commands}')
            for o in options:
                print(f"   {o['kind']:8} {', '.join(o['names']):36} {o['type']:28} = {o['default'] or '—':14} {o['help'][:70]}")
        return

    rep = dw.Report(args.verbose)
    core_files = dw.read_all(os.path.join(SOURCES, 'DICOMCore'))
    for tool in tools:
        files, options, outputs, commands = surface(tool)
        tags, local_tags = dk.tag_constants(os.path.join(SOURCES, 'DICOMCore'), files)
        print(f'\n== {tool} ({len(files)} files, {len(options)} options)')
        checks = [
            ('generic', lambda: check_generic(rep, parts, tool, files, tags, local_tags)),
            ('transfer_syntax_names', lambda: check_transfer_syntax_names(rep, parts[6], tool, files, options)),
            ('defaults', lambda: check_documented_defaults(rep, tool, files, options)),
            ('contract', lambda: check_contract(rep, parts, tool, options)),
        ]
        for name, fn in checks:
            if args.only and args.only not in name:
                continue
            fn()
    print(f'\n{rep.failed} check(s) with wrong or missing values, {rep.pending} pending owner approval')
    sys.exit(1 if rep.failed else 0)


if __name__ == '__main__':
    main()
