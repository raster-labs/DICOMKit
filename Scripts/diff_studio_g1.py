#!/usr/bin/env python3
"""DICOMStudio group G1 (CLI Workshop) row-by-row checks for the FILE tools of the Workshop:
dicom-info, dump, tags, diff, json, xml, validate, split, merge, dcmdir, archive, study, uid, export.

Loaded by diff_studio.py (``diff_studio_g1*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
The generic ``parity`` check of diff_studio.py already compares flags, defaults and picker values with the
ArgumentParser surface; the checks here pin what that diff cannot see, each against the frozen 2026a DocBook
or against the CLI source the Workshop must stay text-identical with:

  * dcmdir --profile picker          is DICOMCore.DICOMDIRProfile.allStandard, whose identifiers are exactly the
                                     PS3.11 2026a Tables A.1-1 … N.1-1 fixed identifiers; help names no family heading
  * dcmdir File-set rules            WorkshopFileSetRules == Sources/dicom-dcmdir/FileSetRules.swift (constants, texts);
                                     16 / 8 / 8 / A-Z 0-9 _ against PS3.10 2026a 8.1, 8.2, 8.5
  * export frame numbers / rate      --frame-number, --start/--end-frame-number help "numbered from 1" (PS3.3 Table 10-3),
                                     the 0-based options deprecated; --fps has no fixed default and names the three
                                     Cine Module attributes of PS3.3 Table C.7-13 with their PS3.6 Table 6-1 names;
                                     the Workshop's copies of ExportStandard.swift texts are identical
  * json / xml empty attributes      include-empty default on with --no-include-empty (PS3.18 F.2.5 / PS3.19 Table
                                     A.1.5-2); the deprecation notes equal the CLIs'
  * split frame selection            --frames help says 0-based / deprecated, --frame-numbers "numbered from 1"
                                     (PS3.3 2026a C.7.6.16.1.2 "Frames are implicitly numbered starting from 1")
  * archive query                    --strict-modality offered; --modality help is the shared ModalityOptionValidator
                                     text; the --study-date warning equals the CLI's
  * validate --iod                   the Workshop's SOP Class -> engine name map equals dicom-validate's IODOption and
                                     every UID / name is a PS3.6 Table A-1 row
  * uid / dump refusal texts         the Workshop's copies of the CLI-local UIDRootRule and dicom-dump texts
  * ValidationModel (panel)          --iod suggestions are PS3.6 Table A-1 UID Keywords; level texts = dicom-validate --level help
  * pixel / codec tools (anon, image, pdf, pixedit, video, convert, compress): the E.3 Option flags vs PS3.15 Table E.1-1
                                     columns / CID 7050, Conversion Type vs Table C.8-24, CID 3000 keywords, the compress
                                     native --syntax set, the convert token set (DICOMConverter.cliTokens) and the
                                     text-identical mirrors of the CLI-local rule files
"""
import os
import re

# The Workshop's dicom-mwl `create` operation is Studio-only (HL7 ORM^O01 over MLLP or the archive REST API —
# no DIMSE service creates a worklist item); the dicom-mwl CLI registers only `query`. The arm keeps the
# `.subcommand` type so the form switches cleanly, and the preview is rendered commented out. Either adding a
# CLI subcommand or moving the operation out of the Workshop changes a product surface: owner's call.
PENDING_API_APPROVAL = {
    "subcommand picker offers ['create'], dicom-mwl commands are": 'P-STUDIO-MWL-CREATE',
}
# diff_studio.check_workshop_parity keys the CLI options by flag, so a `--format` that several subcommands
# declare is compared with the LAST one (compare --format = text, bulk --format = png). The Workshop rows it
# flags mirror their own subcommand's default (summary --format table, single --format jpeg: see
# `diff_cli.py --list-surface`). Tooling, not a standard finding; the orchestrator owns diff_studio.py.
DEFERRED = {
    "Workshop default 'table', dicom-study default 'text'":
        'diff_studio.py by-flag collapse (summary --format is table on both surfaces; compare --format is text)',
    "Workshop default 'jpeg', dicom-export default 'png'":
        'diff_studio.py by-flag collapse (single --format is jpeg on both surfaces; bulk --format is png)',
    # dicom-wado: `retrieve -f, --format` is the METADATA representation (MetadataFormat json | xml, default json,
    # PS3.18 Table 8.7.3-3) and the Workshop mirrors it; the by-flag collapse compares it with the LAST --format
    # declared (ups: OutputFormat table/json/csv/dicom-json). Not a finding (checked by "net web rules").
    "dicom-wado: --format (CLIWorkshopHelpers.swift": 'diff_studio.py by-flag collapse (retrieve --format is MetadataFormat json | xml on both surfaces; query / ups --format is OutputFormat)',
    # dicom-video: the --type picker is `[""] + VideoConsole.TypeArgument.allCases.map(\.rawValue)` (the shared
    # enum; the empty entry omits --type so the engine announces its endoscopic default, as the CLI does without
    # --type). parse_definition reads that expression as the literal [""], so the generic check reports a picker of
    # [''] lacking the three values. Pinned by CLIWorkshopVideoTests "pickers offer exactly the shared enums' raw
    # values" and by "G1 workshop pixel cid3000 audio source" below.
    "dicom-video: --type (CLIWorkshopHelpers.swift": 'diff_studio.py parse_definition reads `[""] + VideoConsole.TypeArgument.allCases.map(\\.rawValue)` as the literal [""]; the picker offers the shared enum\'s three values after the empty entry that omits --type',
}
# Flags the Workshop emits through an internal picker's cliMapping (not a flag-bearing parameter, so the
# surface parser cannot see them): the operation picker of dicom-ups maps search / create-workitem / subscribe /
# unsubscribe onto the CLI's bare flags, the Protocol picker of dicom-wado maps wado-uri onto --uri. The mapping
# is pinned by "net web rules" (every mapped token is a dicom-wado flag).
EXEMPT = {
    'ups --search': 'emitted by the dicom-ups operation picker cliMapping ("search": "--search")',
    'ups --create-workitem': 'emitted by the dicom-ups operation picker cliMapping ("create-workitem": "--create-workitem")',
    'ups --subscribe': 'emitted by the dicom-ups operation picker cliMapping ("subscribe": "--subscribe")',
    'ups --unsubscribe': 'emitted by the dicom-ups operation picker cliMapping ("unsubscribe": "--unsubscribe")',
    'retrieve --uri': 'emitted by the dicom-wado Protocol picker cliMapping ("wado-uri": "--uri")',
}

HERE = os.path.dirname(os.path.abspath(__file__))
VM = 'DICOMStudio/ViewModels/CLIWorkshopViewModel.swift'
HELPERS = 'DICOMStudio/Components/CLIWorkshopHelpers.swift'


def src(files, suffix):
    for name, s in files.items():
        if name.endswith(suffix):
            return s
    raise KeyError(suffix)


def read(ctx, rel):
    return ctx['dw'].read(os.path.join(ctx['sources'], rel))


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


def param(ws, tool, pid):
    for p in ws.get(tool, []):
        if p.get('id') == pid:
            return p
    return None


def literals(s):
    """Swift string literals (comment lines dropped) with every interpolation replaced by a placeholder."""
    out = set()
    code = '\n'.join(l for l in s.split('\n') if not l.strip().startswith('//'))
    for lit in re.findall(r'"((?:[^"\\\n]|\\.)*)"', code):
        out.add(re.sub(r'\\\((?:[^()]|\([^()]*\))*\)', '<x>', lit))
    return out


def cli_help(ctx, tool, flag):
    files, options, outputs, commands = ctx['dc'].surface(tool)
    return [o.get('help', '') for o in options if flag in o.get('names', [])]


def named_tags_match(dictionary, text):
    """Every 'Name (gggg,eeee)' in text must be a PS3.6 Table 6-1 row with that name."""
    matched, wrong = 0, []
    for name, tag in re.findall(r'([A-Z][A-Za-z\' /-]+?) \((\w{4},\w{4})\)', text):
        row = dictionary.get(tag.replace(',', '').upper())
        if row is None:
            wrong.append(f'({tag}) is not in PS3.6 Table 6-1')
        elif row[0].strip() != name.strip():
            wrong.append(f'({tag}) is "{row[0]}" in PS3.6 Table 6-1, help says "{name}"')
        else:
            matched += 1
    return matched, wrong


def ps311_identifiers(p11):
    std, templates = set(), set()
    for lab, cap, t in p11.tables():
        if re.match(r'^[A-N]\.1-1$', lab):
            for row in p11.rows(t):
                for cell in row:
                    for ident in re.findall(r'STD-[A-Z0-9-]+(?:xxxx)?', cell):
                        (templates if ident.endswith('xxxx') else std).add(ident)
    return std, templates


_PART7 = {}


def part7(ctx):
    """PS3.7 2026a (not among the parts diff_studio.py loads): read from the --nema directory on demand."""
    if 'part' not in _PART7:
        import sys
        nema = None
        for i, a in enumerate(sys.argv):
            if a == '--nema' and i + 1 < len(sys.argv):
                nema = sys.argv[i + 1]
            elif a.startswith('--nema='):
                nema = a.split('=', 1)[1]
        path = os.path.join(nema or '', 'part07_2026a.xml')
        _PART7['part'] = ctx['nd'].Part(path) if nema and os.path.exists(path) else None
    return _PART7['part']


# --- dicom-dcmdir ------------------------------------------------------------------------------------------

def check_dcmdir_profile_picker(rep, parts, files, ctx):
    ws = ctx['workshop_surface']()
    p = param(ws, 'dicom-dcmdir', 'profile')
    std, templates = ps311_identifiers(parts[11])
    wrong, matched = [], 0
    if p is None:
        wrong.append('dicom-dcmdir form has no --profile parameter')
    else:
        av = p.get('allowedValues')
        if isinstance(av, list):
            bad = [v for v in av if v not in std]
            wrong += [f'picker offers "{v}", not a PS3.11 2026a identifier (D29)' for v in bad]
            matched += len(av) - len(bad)
        elif 'DICOMDIRProfile.allStandard' in str(av):
            matched += 1
        else:
            wrong.append(f'picker values are {av!r}, neither a literal list nor DICOMDIRProfile.allStandard')
        if p.get('defaultValue') not in std:
            wrong.append(f'default {p.get("defaultValue")!r} is not a PS3.11 identifier')
        # the help may name the deprecated spellings only as deprecated (the CLI's own list)
        vm = src(files, 'CLIWorkshopViewModel.swift')
        dep = set(re.findall(r'"(STD-[A-Z0-9-]+)":\s*"PS3\.11', block(vm, r'deprecatedProfileTables: \[String: String\] = \[', 'deprecatedProfileTables')))
        help_text = str(p.get('helpText', ''))
        before, _, after = help_text.partition('deprecated:')
        for tok in re.findall(r'STD-[A-Z0-9-]+', before):
            if tok in std:
                matched += 1
            else:
                wrong.append(f'help names "{tok}" as an identifier; PS3.11 2026a has none')
        for tok in re.findall(r'STD-[A-Z0-9-]+', after):
            if tok not in dep and tok not in std and tok + 'xxxx' not in {t.replace('xxxx', 'XXXX') for t in templates} and tok not in {t.upper() for t in templates}:
                wrong.append(f'help lists "{tok}" as deprecated but WorkshopFileSetRules.deprecatedProfileTables does not')
    # the registry the picker reads is exactly PS3.11
    core = read(ctx, 'DICOMCore/DICOMDirectory.swift')
    ids = set(re.findall(r'"(STD-[^"]+)"', block(core, r'static let fixedIdentifiers: \[String\] = \[', 'fixedIdentifiers')))
    core_missing = [f'PS3.11 identifier {i} missing from DICOMCore.DICOMDIRProfile.fixedIdentifiers (DICOMCore)' for i in sorted(std - ids)]
    core_extra = [f'DICOMCore.DICOMDIRProfile.fixedIdentifiers has "{i}", not in PS3.11 2026a Tables A.1-1..N.1-1 (DICOMCore)' for i in sorted(ids - std)]
    rep.check(f'PS3.11 2026a Tables A.1-1..N.1-1 ({len(std)} identifiers): dicom-dcmdir Workshop --profile picker is '
              f'DICOMDIRProfile.allStandard and names only identifiers (D29)', matched + len(ids & std),
              wrong + core_extra, core_missing)


def check_dcmdir_fileset_rules(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    cli = read(ctx, 'dicom-dcmdir/FileSetRules.swift')
    vm = src(files, 'CLIWorkshopViewModel.swift')
    cli_body = block(cli, r'enum FileSetRules \{', 'FileSetRules')
    ws_body = block(vm, r'enum WorkshopFileSetRules \{', 'WorkshopFileSetRules')
    wrong, matched = [], 0
    for name, value in re.findall(r'static let (max\w+|allowedCharacters|fileIDRule|fileSetIDRule) = (.+)', cli_body):
        m = re.search(r'static let ' + name + r' = (.+)', ws_body)
        if not m:
            wrong.append(f'WorkshopFileSetRules lacks {name}')
        elif m.group(1).strip() != value.strip():
            wrong.append(f'WorkshopFileSetRules.{name} = {m.group(1).strip()}; dicom-dcmdir has {value.strip()}')
        else:
            matched += 1
    cli_lit, ws_lit = literals(cli_body), literals(ws_body)
    for lit in sorted(cli_lit):
        if 'PS3' not in lit and 'File' not in lit and 'STD-' not in lit:
            continue
        if lit in ws_lit:
            matched += 1
        else:
            wrong.append(f'dicom-dcmdir text not mirrored by WorkshopFileSetRules: "{lit[:90]}"')
    # PS3.10 2026a clauses behind the constants
    def text(part, sid):
        e = dw.section_by_id(part, sid)
        return nd.norm(' '.join(e.itertext())) if e is not None else ''
    t81, t82, t85 = text(parts[10], 'sect_8.1'), text(parts[10], 'sect_8.2'), text(parts[10], 'sect_8.5')
    if 'zero (0) to sixteen (16) characters' not in t81:
        wrong.append('PS3.10 8.1: "16 characters" for the File-set ID not found; re-read the clause')
    elif 'maxFileSetIDLength = 16' not in ws_body:
        wrong.append('maxFileSetIDLength is not 16 (PS3.10 8.1)')
    else:
        matched += 1
    if 'one to eight components' not in t82 or 'one to eight characters' not in t82:
        wrong.append('PS3.10 8.2: "one to eight components/characters" not found; re-read the clause')
    elif 'maxFileIDComponents = 8' not in ws_body or 'maxComponentLength = 8' not in ws_body:
        wrong.append('File ID limits are not 8 / 8 (PS3.10 8.2)')
    else:
        matched += 1
    letters = ''.join(re.findall(r'\b([A-Z])\b', t85.split('(uppercase)')[0].split('subset:')[-1]))
    digits = ''.join(sorted(re.findall(r'\b(\d)\b', t85.split('(uppercase)')[1].split('(underscore)')[0]))) if '(uppercase)' in t85 else ''
    allowed = re.search(r'allowedCharacters = Set\("([^"]+)"\)', ws_body)
    if letters != 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' or digits != '0123456789' or '_ (underscore)' not in t85:
        wrong.append('PS3.10 8.5: could not read the A-Z, 0-9, _ repertoire; re-read the clause')
    elif not allowed or set(allowed.group(1)) != set(letters + digits + '_'):
        wrong.append('allowedCharacters is not the PS3.10 8.5 repertoire A-Z, 0-9, _')
    else:
        matched += 1
    rep.check('PS3.10 2026a 8.1, 8.2, 8.5: WorkshopFileSetRules mirrors dicom-dcmdir FileSetRules (D132)', matched, wrong)


# --- dicom-export ------------------------------------------------------------------------------------------

def check_export_frames_and_rate(rep, parts, files, ctx):
    dw = ctx['dw']
    ws = ctx['workshop_surface']()
    dictionary = dw.dictionary(parts[6])
    wrong, matched = [], 0
    # Frame numbers from 1: PS3.3 Table 10-3
    t103 = ' '.join(' '.join(r) for r in dw.table_rows(parts[3], '10-3'))
    if 'The first Frame shall be denoted as Frame number 1' not in t103:
        wrong.append('PS3.3 Table 10-3: "The first Frame shall be denoted as Frame number 1" not found; re-read')
    else:
        matched += 1
    for pid, phrase in (('frame-number', 'numbered from 1'), ('start-frame-number', 'Frame number from 1'),
                        ('end-frame-number', 'Frame number from 1')):
        p = param(ws, 'dicom-export', pid)
        if p is None:
            wrong.append(f'dicom-export form lacks --{pid}')
        elif phrase not in str(p.get('helpText', '')) or str(p.get('minValue', '')) != '1':
            wrong.append(f'--{pid}: help must say "{phrase}" and minValue 1 (PS3.3 Table 10-3)')
        else:
            matched += 1
    for pid in ('frame', 'start-frame', 'end-frame'):
        p = param(ws, 'dicom-export', pid)
        cli = cli_help(ctx, 'dicom-export', '--' + pid)
        if p is None:
            wrong.append(f'dicom-export form lacks the deprecated --{pid}')
        elif not str(p.get('helpText', '')).startswith('deprecated: 0-based index') or p.get('defaultValue'):
            wrong.append(f'--{pid}: help must start "deprecated: 0-based index" and carry no default (a default would emit the deprecated option)')
        elif cli and cli[-1] != p.get('helpText'):
            wrong.append(f'--{pid}: Workshop help {p.get("helpText")!r} != CLI help {cli[-1]!r}')
        else:
            matched += 1
    # --fps: no fixed default; the Cine Module attributes of PS3.3 Table C.7-13
    p = param(ws, 'dicom-export', 'fps')
    if p is None:
        wrong.append('dicom-export form lacks --fps')
    elif p.get('defaultValue'):
        wrong.append(f'--fps carries default {p.get("defaultValue")!r}; the CLI default is the file rate (PS3.3 Table C.7-13)')
    else:
        matched += 1
        c713 = {r[1].strip('()').replace(',', '').upper(): r[0].strip() for r in dw.table_rows(parts[3], 'C.7-13') if len(r) > 1 and re.match(r'\(\w{4},\w{4}\)', r[1].strip())}
        m, w = named_tags_match(dictionary, str(p.get('helpText', '')))
        matched += m
        wrong += [f'--fps help: {x}' for x in w]
        for name, tag in re.findall(r'([A-Z][A-Za-z ]+?) \((\w{4},\w{4})\)', str(p.get('helpText', ''))):
            if tag.replace(',', '').upper() not in c713:
                wrong.append(f'--fps help names ({tag}), not a PS3.3 Table C.7-13 attribute')
    # the Workshop's rate resolution reads the same attributes in the same order as the CLI
    vm = src(files, 'CLIWorkshopViewModel.swift')
    cli = read(ctx, 'dicom-export/ExportStandard.swift')
    cli_order = re.findall(r'dataSet\.string\(for: \.(\w+)\)', block(cli, r'static func resolve\(explicit: Double\?, dataSet: DataSet\) -> CineFrameRate \{', 'CineFrameRate.resolve'))
    ws_order = re.findall(r'dataSet\.string\(for: \.(\w+)\)', block(vm, r'static func exportCineFrameRate\(explicit: Double\?, dataSet: DataSet\) -> \(fps: Double, source: String\) \{', 'exportCineFrameRate'))
    if cli_order != ws_order:
        wrong.append(f'exportCineFrameRate reads {ws_order}; dicom-export CineFrameRate reads {cli_order}')
    else:
        matched += 1
    # the CLI-local texts (deprecation, conflict, Frame number, Burned In Annotation, apply-window) are identical
    ws_lit = literals(vm[vm.index('// MARK: dicom-export standard texts'):vm.index('// MARK: - dicom-script Execution')])
    for lit in sorted(literals(cli)):
        if not any(k in lit for k in ('warning:', 'Frame number', 'cannot be used together', 'Table 10-3')):
            continue
        if lit in ws_lit:
            matched += 1
        else:
            wrong.append(f'dicom-export text not mirrored by the Workshop: "{lit[:100]}"')
    rep.check('PS3.3 2026a Table 10-3 / Table C.7-13: dicom-export Workshop frame numbers, deprecated 0-based options, '
              '--fps default and ExportStandard texts (D127)', matched, wrong)


# --- dicom-json / dicom-xml ----------------------------------------------------------------------------------

def check_data_exchange_empty_and_deprecations(rep, parts, files, ctx):
    ws = ctx['workshop_surface']()
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    for tool, dep_id in (('dicom-json', 'no-sort-keys'), ('dicom-xml', 'no-keywords')):
        p = param(ws, tool, 'include-empty')
        if p is None or p.get('defaultValue') != 'true' or p.get('negatedFlag') != '--no-include-empty':
            wrong.append(f'{tool} include-empty must default to true with negatedFlag --no-include-empty (PS3.18 F.2.5 / PS3.19 Table A.1.5-2, D114)')
        else:
            matched += 1
        d = param(ws, tool, dep_id)
        if d is None or not str(d.get('helpText', '')).lower().startswith('deprecated'):
            wrong.append(f'{tool} --{dep_id} help must start with "Deprecated"')
        else:
            matched += 1
        cli = read(ctx, f'{tool}/main.swift')
        notes = [l for l in literals(cli) if l.startswith(f'{tool}: warning: --{dep_id} is deprecated')]
        if len(notes) != 1:
            wrong.append(f'{tool}: deprecation note not found in Sources/{tool}/main.swift')
        elif notes[0] not in literals(vm):
            wrong.append(f'{tool}: Workshop deprecation note differs from the CLI: "{notes[0][:90]}"')
        else:
            matched += 1
    if "includeEmpty: paramValue(\"include-empty\") != \"false\"" not in vm:
        wrong.append('executor must keep empty attributes unless the toggle is off (CLI default on)')
    else:
        matched += 1
    rep.check('PS3.18 F.2.5 / PS3.19 Table A.1.5-2: dicom-json / dicom-xml Workshop include-empty default and deprecation notes (D114)',
              matched, wrong)


# --- dicom-split ---------------------------------------------------------------------------------------------

def check_split_frame_numbers(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    ws = ctx['workshop_surface']()
    wrong, matched = [], 0
    sec = dw.section_by_id(parts[3], 'sect_C.7.6.16.1.2')
    text = nd.norm(' '.join(sec.itertext())) if sec is not None else ''
    if 'Frames are implicitly numbered starting from 1' not in text:
        wrong.append('PS3.3 C.7.6.16.1.2: "Frames are implicitly numbered starting from 1" not found; re-read')
    else:
        matched += 1
    p = param(ws, 'dicom-split', 'frames')
    if p is None or '0-based' not in str(p.get('helpText', '')) or 'deprecated' not in str(p.get('helpText', '')).lower():
        wrong.append('dicom-split --frames help must say deprecated and 0-based (D154)')
    else:
        matched += 1
    q = param(ws, 'dicom-split', 'frame-numbers')
    if q is None or 'numbered from 1' not in str(q.get('helpText', '')) or 'C.7.6.16.1.2' not in str(q.get('helpText', '')):
        wrong.append('dicom-split --frame-numbers help must say "numbered from 1 (PS3.3 C.7.6.16.1.2)"')
    else:
        matched += 1
        cli = cli_help(ctx, 'dicom-split', '--frame-numbers')
        if cli and cli[-1] != q.get('helpText'):
            wrong.append(f'--frame-numbers: Workshop help differs from the CLI: {q.get("helpText")!r} vs {cli[-1]!r}')
        else:
            matched += 1
    vm = src(files, 'CLIWorkshopViewModel.swift')
    for needle in ('SplitConsole.parseFrameNumberSelection', 'SplitConsole.framesDeprecatedLine', 'SplitConsole.framesAndFrameNumbersConflictMessage'):
        if needle in vm:
            matched += 1
        else:
            wrong.append(f'executor does not use {needle}')
    rep.check('PS3.3 2026a C.7.6.16.1.2: dicom-split Workshop --frame-numbers (from 1) and deprecated 0-based --frames (D154)',
              matched, wrong)


# --- dicom-archive -------------------------------------------------------------------------------------------

def check_archive_query_keys(rep, parts, files, ctx):
    ws = ctx['workshop_surface']()
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    p = param(ws, 'dicom-archive', 'strict-modality')
    if p is None or p.get('flag') != '--strict-modality':
        wrong.append('dicom-archive form lacks query --strict-modality (PS3.3 C.7.3.1.1.1)')
    else:
        matched += 1
    m = param(ws, 'dicom-archive', 'modality')
    if m is None or 'ModalityOptionValidator.helpText' not in str(m.get('helpText', '')):
        wrong.append('dicom-archive --modality help must be the shared ModalityOptionValidator.helpText')
    else:
        matched += 1
    if 'ModalityOptionValidator.validate(' not in vm or 'Rejected because --strict-modality is set.' not in vm:
        wrong.append('executor must validate --modality with ModalityOptionValidator and reject under --strict-modality as the CLI')
    else:
        matched += 1
    cli = read(ctx, 'dicom-archive/QueryKeys.swift')
    for lit in literals(cli):
        if 'study-date' in lit and lit not in literals(vm):
            wrong.append(f'study-date warning text not mirrored: "{lit[:80]}"')
        elif 'study-date' in lit:
            matched += 1
    rep.check('PS3.3 C.7.3.1.1.1 / PS3.4 C.2.2.2.5.1: dicom-archive Workshop query --strict-modality, modality help and study-date warning',
              matched, wrong)


# --- dicom-validate --------------------------------------------------------------------------------------------

def check_validate_iod_map(rep, parts, files, ctx):
    dw = ctx['dw']
    vm = src(files, 'CLIWorkshopViewModel.swift')
    cli = read(ctx, 'dicom-validate/IODOption.swift')
    registry = dw.uid_registry(parts[6])
    def entries(s, pat):
        body = block(s, pat, 'engine name map')
        return {uid: (name, comment.strip()) for uid, name, comment in re.findall(r'"([\d.]+)":\s*"(\w+)",\s*//\s*([^\n]+)', body)}
    cli_map = entries(cli, r'engineNameBySOPClassUID: \[String: String\] = \[')
    ws_map = entries(vm, r'validateEngineNameBySOPClassUID: \[String: String\] = \[')
    wrong, matched = [], 0
    for uid, (name, comment) in cli_map.items():
        if ws_map.get(uid, (None,))[0] != name:
            wrong.append(f'{uid}: Workshop maps to {ws_map.get(uid)}, dicom-validate to {name}')
            continue
        row = registry.get(uid)
        if row is None:
            wrong.append(f'{uid} is not a PS3.6 Table A-1 UID')
        elif row[0].strip() != comment:
            wrong.append(f'{uid}: comment says "{comment}", PS3.6 Table A-1 says "{row[0]}"')
        else:
            matched += 1
    for uid in ws_map.keys() - cli_map.keys():
        wrong.append(f'Workshop maps {uid}, dicom-validate does not')
    rep.check('PS3.6 Table A-1: dicom-validate Workshop --iod SOP Class map equals dicom-validate IODOption', matched, wrong)


# --- dicom-uid / dicom-dump texts ------------------------------------------------------------------------------

def check_uid_and_dump_texts(rep, parts, files, ctx):
    vm = src(files, 'CLIWorkshopViewModel.swift')
    helpers = src(files, 'CLIWorkshopHelpers.swift')
    ws_lit = literals(vm)
    wrong, matched = [], 0
    for lit in literals(read(ctx, 'dicom-uid/UIDOptions.swift')):
        if 'PS3.5 9.1' not in lit:
            continue
        if lit in ws_lit:
            matched += 1
        else:
            wrong.append(f'dicom-uid --root text not mirrored by uidRootProblems: "{lit[:80]}"')
    for lit in literals(read(ctx, 'dicom-dump/main.swift')):
        if lit.startswith('Invalid tag format'):
            if any(lit in w for w in ws_lit):
                matched += 1
            else:
                wrong.append(f'dicom-dump text not mirrored: "{lit[:80]}"')
    # the surface parser keeps only the literal part of `[""] + <expr>`, so read the definition itself
    lookup = re.search(r'id: "lookup-type".*?allowedValues: ([^\n]+)', helpers, re.S)
    if lookup is None or 'UIDConsole.lookupTypeFilters.map' not in lookup.group(1):
        wrong.append('dicom-uid lookup --type picker must be the shared UIDConsole.lookupTypeFilters (PS3.6 Table A-1 UID Types)')
    else:
        matched += 1
    if 'UIDManager.tableA1UIDType(of:' not in vm:
        wrong.append('dicom-uid lookup must print UIDManager.tableA1UIDType (PS3.6 Table A-1 UID Type)')
    else:
        matched += 1
    rep.check('PS3.5 9.1 / PS3.6 Table A-1: dicom-uid and dicom-dump Workshop texts mirror the CLIs', matched, wrong)


# --- ValidationModel (the dicom-validate panel outside the Workshop) ---------------------------------------------

def check_validation_panel(rep, parts, files, ctx):
    dw = ctx['dw']
    model = src(files, 'ValidationModel.swift')
    keywords = {v[1].strip() for v in dw.uid_registry(parts[6]).values()}
    body = block(model, r'knownIODs: \[String\] = \[', 'knownIODs')
    ours = re.findall(r'"(\w+)"', body)
    wrong = [f'knownIODs "{k}" is not a PS3.6 Table A-1 UID Keyword' for k in ours if k not in keywords]
    matched = len(ours) - len(wrong)
    # the five level descriptions carry the CLI's --level help segments
    cli = read(ctx, 'dicom-validate/DICOMValidate.swift')
    m = re.search(r'help: "Validation level \(1-5\): ([^"]+)"', cli)
    if not m:
        wrong.append('dicom-validate --level help not found; update the extractor')
    else:
        segments = dict(re.findall(r'(\d)=(.+?)(?=, \d=|$)', m.group(1)))
        levels = dict(re.findall(r'case (\d): return "\d — ([^"]+)"', block(model, r'static func levelDescription\(_ level: Int\) -> String \{', 'levelDescription')))
        for n, text in segments.items():
            if levels.get(n) != text:
                wrong.append(f'levelDescription({n}) is {levels.get(n)!r}; dicom-validate --level help says {text!r}')
            else:
                matched += 1
    vm = src(files, 'ValidationViewModel.swift')
    if 'Validation level must be between 1 and 5\\n' not in vm:
        wrong.append('ValidationViewModel level refusal text differs from dicom-validate')
    else:
        matched += 1
    rep.check('PS3.6 Table A-1 keywords / dicom-validate --level help: ValidationModel IOD suggestions and level descriptions',
              matched, wrong)


# --- Network tools (workshop-net) -------------------------------------------------------------------------

def check_query_retrieve_levels(rep, parts, files, ctx):
    """dicom-query --level offers the Query/Retrieve Level (0008,0052) values of PS3.4 2026a Tables
    C.6.1-1 / C.6.2-1 (PATIENT, STUDY, SERIES, IMAGE) in lower case, the executor maps every value (and the
    CLI alias "instance") onto DICOMNetwork.QueryLevel, and the parent-level warning names the level by
    QueryLevel.rawValue — mirroring the CLI fix 695d961 (no "instance" on the wire)."""
    dw = ctx['dw']
    ws = ctx['workshop_surface']()
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    std = []
    for lab in ('C.6.1-1', 'C.6.2-1'):
        for row in dw.table_rows(parts[4], lab):
            if len(row) >= 2 and row[1].strip().isupper() and row[1].strip() not in std:
                std.append(row[1].strip())
    if std != ['PATIENT', 'STUDY', 'SERIES', 'IMAGE']:
        wrong.append(f'PS3.4 Tables C.6.1-1 / C.6.2-1 read as {std}; re-read the tables')
    else:
        matched += 1
    p = param(ws, 'dicom-query', 'level')
    if p is None:
        wrong.append('dicom-query form has no --level parameter')
    else:
        vals = p.get('allowedValues')
        if vals != [v.lower() for v in std]:
            wrong.append(f'dicom-query --level picker offers {vals}; PS3.4 Table C.6.1-1 values are {[v.lower() for v in std]}')
        else:
            matched += len(vals)
        if p.get('defaultValue') != 'study':
            wrong.append(f'dicom-query --level default {p.get("defaultValue")!r}; the CLI default is study')
        else:
            matched += 1
    parent = param(ws, 'dicom-query', 'include-parent-keys')
    vw = (parent or {}).get('visibleWhen', '')
    if parent is None or '"instance"' in str(vw) or '"image"' not in str(vw):
        wrong.append('dicom-query --include-parent-keys must be visible for the series / image levels (not "instance")')
    else:
        matched += 1
    body = block(vm, r'nonisolated static func queryLevelOption\(_ raw: String\) -> QueryLevel\? \{', 'queryLevelOption')
    cases = dict(re.findall(r'case ((?:"[a-z]+"(?:, )?)+): return \.(\w+)', body))
    mapping = {}
    for keys, level in cases.items():
        for k in re.findall(r'"([a-z]+)"', keys):
            mapping[k] = level
    expected = {'patient': 'patient', 'study': 'study', 'series': 'series', 'image': 'image', 'instance': 'image'}
    for k, v in expected.items():
        if mapping.get(k) != v:
            wrong.append(f'queryLevelOption("{k}") maps to {mapping.get(k)}, expected .{v} (PS3.4 Table C.6.1-1; "instance" = CLI alias of IMAGE)')
        else:
            matched += 1
    exec_body = block(vm, r'private func executeDicomQuery\(\) async \{', 'executeDicomQuery')
    if 'cannot be matched at \\(level.rawValue) level' not in exec_body:
        wrong.append('the parent-level filter warning must name the level by QueryLevel.rawValue (IMAGE), as the CLI does')
    else:
        matched += 1
    if '"INSTANCE"' in exec_body:
        wrong.append('executeDicomQuery still spells the IMAGE level as "INSTANCE"')
    for needle in ('csvHeader: csvKeywords ? .keyword : .tag', 'DICOMJSONEncoder(configuration: .init(prettyPrinted: true)).encodeMultiple'):
        if needle in vm:
            matched += 1
        else:
            wrong.append(f'dicom-query executor must build the shared formatter with `{needle}` (P-QUERY-JSON; DICOMCLI part 4 "net")')
    rep.check('PS3.4 2026a Tables C.6.1-1 / C.6.2-1: dicom-query Workshop --level values, IMAGE on the wire, '
              'dicom-json / csv-keywords formatter (D-query level, P-QUERY-JSON)', matched, wrong)


def check_priority_and_store_outcomes(rep, parts, files, ctx):
    """Priority (0000,0700) pickers of dicom-send (and, once offered, dicom-retrieve / dicom-qr) are low / medium /
    high, the words of PS3.7 2026a Table 9.3-1 (C-STORE-RQ) / 9.3-9 (C-MOVE-RQ) / 9.3-6 (C-GET-RQ) whose values
    LOW 0002H, MEDIUM 0000H, HIGH 0001H are DICOMNetwork.DIMSEPriority's raw values; the dicom-send executor
    classes the C-STORE response per PS3.4 2026a Table B.2-1 like the CLI's StoreOutcome, prints the shared
    sendFileWarningLine / sendSummary(warnings:) and the CLI's SendError texts."""
    dw = ctx['dw']
    ws = ctx['workshop_surface']()
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    # PS3.7: the three Priority values, identical in the three request tables
    std = {}
    p7 = part7(ctx)
    if p7 is None:
        rep.check('PS3.7 2026a Tables 9.3-1 / 9.3-9 / 9.3-6 Priority: PS3.7 not fetched into the --nema directory', 0,
                  pending=['fetch part07_2026a.xml (Scripts/nema_docbook.py fetch 2026a 7 --out <nema>)'])
        return
    for lab in ('9.3-1', '9.3-9', '9.3-6'):
        for row in dw.table_rows(p7, lab):
            if row and row[0].strip() == 'Priority':
                std[lab] = dict(re.findall(r'(LOW|MEDIUM|HIGH) = ([0-9A-F]{4})H', ' '.join(row)))
    if any(v != {'LOW': '0002', 'MEDIUM': '0000', 'HIGH': '0001'} for v in std.values()) or len(std) != 3:
        wrong.append(f'PS3.7 Tables 9.3-1 / 9.3-9 / 9.3-6 Priority read as {std}; re-read')
    else:
        matched += 3
    core = read(ctx, 'DICOMNetwork/DIMSEPriority.swift')
    raw = {k.upper(): v.upper().replace('0X', '') for k, v in re.findall(r'case (low|medium|high) = 0x([0-9A-Fa-f]{4})', core)}
    if raw != {'LOW': '0002', 'MEDIUM': '0000', 'HIGH': '0001'}:
        wrong.append(f'DICOMNetwork.DIMSEPriority raw values {raw} differ from PS3.7 Table 9.3-1 (DICOMNetwork)')
    else:
        matched += 3
    for tool in ('dicom-send', 'dicom-retrieve', 'dicom-qr'):
        p = param(ws, tool, 'priority')
        if p is None:
            if tool != 'dicom-send':
                continue            # offered by a later commit; the parity check reports the contract row
            wrong.append(f'{tool} form has no --priority parameter')
            continue
        if p.get('allowedValues') != ['low', 'medium', 'high'] or p.get('defaultValue') != 'medium':
            wrong.append(f'{tool} --priority must offer low / medium / high (PS3.7 Table 9.3-1 words) with default medium')
        else:
            matched += 1
        if '0002H' not in str(p.get('helpText', '')) or '0001H' not in str(p.get('helpText', '')):
            wrong.append(f'{tool} --priority help must name the PS3.7 values (low 0002H, medium 0000H, high 0001H)')
        else:
            matched += 1
    # PS3.4 Table B.2-1 classes: Warning rows B000 / B006 / B007 are stored, Failure rows are not
    b21 = dw.table_rows(parts[4], 'B.2-1')
    codes = [r[-2].strip() for r in b21 if len(r) >= 3]
    if not {'B000', 'B006', 'B007', 'A7xx', 'A9xx', 'Cxxx', '0000'} <= set(codes):
        wrong.append(f'PS3.4 Table B.2-1 codes read as {codes}; re-read')
    else:
        matched += 1
    cli = read(ctx, 'dicom-send/SendExecutor.swift')
    cli_body = block(cli, r'enum StoreOutcome: Equatable \{', 'StoreOutcome')
    ws_body = block(vm, r'enum WorkshopStoreOutcome: Equatable \{', 'WorkshopStoreOutcome')
    norm = lambda b: re.sub(r'\s+', ' ', re.sub(r'//[^\n]*', '', b)).strip()
    if norm(cli_body) != norm(ws_body):
        wrong.append('WorkshopStoreOutcome differs from dicom-send StoreOutcome (PS3.4 Table B.2-1 classes)')
    else:
        matched += 1
    for lit in literals(cli):
        if 'Table B.2-1' in lit or lit.startswith('Send completed with'):
            if lit in literals(vm):
                matched += 1
            else:
                wrong.append(f'dicom-send text not mirrored by the Workshop: "{lit[:80]}"')
    send_body = block(vm, r'private func executeDicomSend\(\) async \{', 'executeDicomSend')
    for needle in ('NetworkConsole.sendFileWarningLine(status:', 'warnings: warningCount)',
                   'preferredTransferSyntaxUID: preferredTransferSyntaxUID,', 'transferSyntax: preferredTransferSyntaxUID'):
        if needle in send_body:
            matched += 1
        else:
            wrong.append(f'executeDicomSend must use `{needle}` (shared NetworkConsole / StorageService, as the CLI)')
    rep.check('PS3.7 2026a Tables 9.3-1 / 9.3-9 / 9.3-6 Priority and PS3.4 Table B.2-1: Workshop priority pickers, '
              'dicom-send outcome classes, warning tally and SendError texts (D75 / P-SEND-SUMMARY Studio half)', matched, wrong)


def check_retrieve_status_text_source(rep, parts, files, ctx):
    """The dicom-retrieve / dicom-qr executors word a final C-MOVE / C-GET response through
    DICOMNetwork.DIMSEServiceStatusText (PS3.4 2026a Tables C.4-2 / C.4-3) and the PS3.7 Tables 9.3-10 / 9.3-7
    counters (subOperationCounts), build the request through RetrieveConfiguration(priority:extendedNegotiation:)
    and RetrieveKeys at the most specific level, print the shared retrieveHeader(priority:relationalRetrieval:),
    and carry the CLI-local RetrieveError / DICOMQRError / validateUIDOptions texts verbatim (Studio half of D76)."""
    dw = ctx['dw']
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    # the PS3.4 status tables behind the wording exist and carry the Success / Warning rows
    for lab, service in (('C.4-2', 'C-MOVE'), ('C.4-3', 'C-GET')):
        rows = dw.table_rows(parts[4], lab)
        text = ' '.join(' '.join(r) for r in rows)
        if 'Sub-operations Complete - No Failures' not in text or 'B000' not in text:
            wrong.append(f'PS3.4 Table {lab} ({service}): Success 0000 / Warning B000 rows not found; re-read')
        else:
            matched += 1
    retrieve = block(vm, r'private func executeDicomRetrieve\(\) async \{', 'executeDicomRetrieve')
    bulk = block(vm, r'private func executeDicomRetrieveBulk\([^{]*\{', 'executeDicomRetrieveBulk')
    qr = block(vm, r'private func executeDicomQR\(\) async \{', 'executeDicomQR')
    qr_study = block(vm, r'private func qrRetrieveStudy\([^{]*\{', 'qrRetrieveStudy')
    for name, body, needles in (
        ('executeDicomRetrieve', retrieve, (
            'DIMSEServiceStatusText.describe(result.status, service: .cMove)',
            'Self.retrieveCheck(result, service: .cMove)', 'Self.retrieveCheck(result, service: .cGet)',
            'priority: priority == .medium ? nil : priority', 'relationalRetrieval: relationalRetrieve))',
            'RetrieveExtendedNegotiation(relationalRetrieval: true)', 'Self.retrieveUIDRefusal(',
            '"(not sent — relational-retrieve)"')),
        ('executeDicomRetrieveBulk', bulk, (
            'DIMSEServiceStatusText.describe(result.status, service: .cMove)', 'Self.retrieveCheck(result, service: .cGet)',
            'RetrieveKeys.forStudy(studyUID)')),
        ('executeDicomQR', qr, ('priority: priority)', 'DICOMQueryService.buildQueryKeys(', 'Self.resolveModalityOption(',
                                '"--parallel must be at least 1"', 'Retrieval incomplete: ')),
        ('qrRetrieveStudy', qr_study, ('Self.qrRetrieveCheck(moveResult, service: .cMove)', 'Self.qrRetrieveCheck(finalResult, service: .cGet)')),
    ):
        for needle in needles:
            if needle in body:
                matched += 1
            else:
                wrong.append(f'{name} must contain `{needle}`')
    for stale in ('status: "\\(result.status)"', 'Resolving Study UID from server', '"INSTANCE"'):
        if stale in retrieve + bulk + qr:
            wrong.append(f'retrieve / qr executors still carry `{stale}` (raw DIMSEStatus or app-only lookup; the CLI words the status per PS3.4 Tables C.4-2 / C.4-3)')
    helper_body = (block(vm, r'nonisolated static func retrieveCheck\([^{]*\{', 'retrieveCheck')
                   + block(vm, r'nonisolated static func qrRetrieveCheck\([^{]*\{', 'qrRetrieveCheck'))
    for needle in ('DIMSEServiceStatusText.describe(result.status, service: service)', 'DIMSEServiceStatusText.subOperationCounts(result.progress)'):
        if helper_body.count(needle) >= 2:
            matched += 1
        else:
            wrong.append(f'retrieveCheck / qrRetrieveCheck must both use `{needle}`')
    # CLI-local texts mirrored verbatim (a trailing newline may sit inside the literal on one side and be
    # appended by print() on the other): dicom-retrieve (RetrieveExecutor, DICOMRetrieve) and dicom-qr (DICOMQR)
    def unnl(l):
        return l[:-2] if l.endswith('\\n') else l
    ws_lit = {unnl(l) for l in literals(vm) | literals(src(files, 'CLIWorkshopHelpers.swift'))}
    for rel, keys in (('dicom-retrieve/RetrieveExecutor.swift', ('final response', 'Failed SOP Instance UID List', 'Bulk retrieval', 'Final ')),
                      ('dicom-retrieve/DICOMRetrieve.swift', ('--relational-retrieve', '--uid-list', '--parallel must', '--move-dest parameter')),
                      ('dicom-qr/DICOMQR.swift', ('Retrieval incomplete', 'Retrieval failed: ', 'Failed SOP Instance UID List', '--parallel must', '--move-dest is required', 'Invalid method'))):
        for lit in literals(read(ctx, rel)):
            if not any(k in lit for k in keys) or lit.startswith('#'):
                continue
            if unnl(lit) in ws_lit:
                matched += 1
            else:
                wrong.append(f'{rel.split("/")[0]} text not mirrored by the Workshop: "{lit[:90]}"')
    rep.check('PS3.4 2026a Tables C.4-2 / C.4-3, PS3.7 Tables 9.3-10 / 9.3-7 / 9.3-9 / 9.3-6, PS3.4 C.5.2.1: dicom-retrieve / dicom-qr '
              'Workshop status wording, priority, relational-retrieve and CLI texts (D76 Studio half, P-RETRIEVE-PRIORITY / -EXTNEG, P-QR-PARALLEL)',
              matched, wrong)


def check_mwl_mpps_terms(rep, parts, files, ctx):
    """dicom-mwl --sps-status offers the Scheduled Procedure Step Status (0040,0020) Defined Terms of PS3.3 2026a
    C.4.10 / Table C.4-10 and the Workshop's copy of the CLI-local spsStatusWarning is text-identical;
    --specific-character-set and --strict-modality are offered and passed through; dicom-mpps create requires
    --modality (PS3.4 Table F.7.2-1 Type 1), every CODE|DCM|MEANING example is a PS3.16 2026a CID 9301 pair
    (D85), the value rules carry the CLI's texts and the SCP warning is worded by DIMSEServiceStatusText."""
    dw, nd = ctx['dw'], ctx['nd']
    ws = ctx['workshop_surface']()
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    # PS3.3 C.4.10: the Defined Terms of (0040,0020)
    sec = dw.section_by_id(parts[3], 'sect_C.4.10')
    text = nd.norm(' '.join(sec.itertext())) if sec is not None else ''
    i = text.find('Scheduled Procedure Step Status (0040,0020)')
    seg = text[i:i + 700].split('Defined Terms:')
    terms = re.findall(r'\b(SCHEDULED|ARRIVED|READY|STARTED|DEPARTED)\b', seg[1][:400]) if len(seg) > 1 else []
    if terms != ['SCHEDULED', 'ARRIVED', 'READY', 'STARTED', 'DEPARTED']:
        wrong.append(f'PS3.3 C.4.10 (0040,0020) Defined Terms read as {terms}; re-read')
    else:
        matched += 1
    p = param(ws, 'dicom-mwl', 'sps-status')
    if p is None or p.get('allowedValues') != [''] + terms:
        wrong.append(f'dicom-mwl --sps-status picker must offer the PS3.3 Table C.4-10 terms {terms} (plus the blank "any")')
    else:
        matched += len(terms)
    cli = read(ctx, 'dicom-mwl/DICOMMWLCommand.swift')
    cli_terms = re.findall(r'"(\w+)"', block(cli, r'scheduledProcedureStepStatusDefinedTerms: \[String\] =\s*', 'CLI terms'))
    ws_terms = re.findall(r'"(\w+)"', block(vm, r'mwlScheduledProcedureStepStatusDefinedTerms: \[String\] =\s*', 'Workshop terms'))
    if cli_terms != terms or ws_terms != terms:
        wrong.append(f'SPS Status term lists differ: CLI {cli_terms}, Workshop {ws_terms}, PS3.3 {terms}')
    else:
        matched += 1
    helpers = src(files, 'CLIWorkshopHelpers.swift')
    ws_lit = {l.replace('mwlScheduledProcedureStepStatusDefinedTerms', 'scheduledProcedureStepStatusDefinedTerms')
              for l in literals(vm) | literals(helpers)}
    for lit in literals(cli):
        if '--sps-status' in lit or 'private term' in lit or 'PS3.3 Table C.4-10:' in lit:
            if lit in ws_lit:
                matched += 1
            else:
                wrong.append(f'dicom-mwl text not mirrored by the Workshop: "{lit[:80]}"')
    for pid, flag in (('specific-character-set', '--specific-character-set'), ('strict-modality', '--strict-modality')):
        q = param(ws, 'dicom-mwl', pid)
        if q is None or q.get('flag') != flag:
            wrong.append(f'dicom-mwl form lacks {flag} (PS3.4 Table K.6-1a / PS3.3 C.7.3.1.1.1)')
        else:
            matched += 1
    mwl_body = block(vm, r'private func executeDicomMWLQuery\([^{]*\{', 'executeDicomMWLQuery')
    for needle in ('specificCharacterSet: specificCharacterSet.isEmpty ? nil : specificCharacterSet', 'Self.mwlSPSStatusWarning(spsStatus)', 'Self.resolveModalityOption('):
        if needle in mwl_body:
            matched += 1
        else:
            wrong.append(f'executeDicomMWLQuery must contain `{needle}`')
    # dicom-mpps: Type 1 Modality, CID 9301 examples, value rules, warning wording
    m = param(ws, 'dicom-mpps', 'modality')
    if m is None or m.get('isRequired') != 'true' or (isinstance(m.get('allowedValues'), list) and '' in m['allowedValues']) \
            or 'optional' in str(m.get('allowedValues', '')):
        wrong.append('dicom-mpps create --modality must be required with no blank value (PS3.4 Table F.7.2-1 row 105, Type 1)')
    else:
        matched += 1
    cid = {}
    for lab, cap, tb in parts[16].tables():
        if lab == 'CID 9301':
            for row in parts[16].rows(tb):
                if len(row) >= 3 and row[0].strip() == 'DCM':
                    cid[row[1].strip()] = row[2].strip()
    if len(cid) < 17:
        wrong.append(f'PS3.16 CID 9301 read {len(cid)} DCM rows; re-read')
    else:
        matched += 1
    r = param(ws, 'dicom-mpps', 'discontinuation-reason')
    examples = re.findall(r'(\d{6})\|DCM\|([^"\\]+)', str(r.get('helpText', '')) + ' ' + str(r.get('placeholder', ''))) if r else []
    if not examples:
        wrong.append('dicom-mpps --discontinuation-reason carries no CODE|DCM|MEANING example')
    for code, meaning in examples:
        if cid.get(code) != meaning.strip():
            wrong.append(f'dicom-mpps example {code}|DCM|{meaning.strip()} is not a PS3.16 2026a CID 9301 pair (D85; {code} = {cid.get(code)!r})')
        else:
            matched += 1
    cli_mpps = read(ctx, 'dicom-mpps/DICOMMPPSCommand.swift')
    for lit in literals(cli_mpps):
        if any(k in lit for k in ('--modality is required', '--patient-sex must', '--patient-birth-date must', 'Create status must', 'Update status must',
                                   'Invalid status.', '--image-uid needs', '--sop-class-uid not given', 'attributes may have been coerced')):
            if lit in ws_lit or lit.rstrip('\\n') in {l.rstrip('\\n') for l in ws_lit}:
                matched += 1
            else:
                wrong.append(f'dicom-mpps text not mirrored by the Workshop: "{lit[:80]}"')
    if 'DIMSEServiceStatusText.describe(warning, service: operation == "N-SET" ? .mppsNSet : .dimseN)' in vm:
        matched += 1
    else:
        wrong.append('mppsWarningLine must word the SCP warning through DIMSEServiceStatusText (PS3.4 Table F.7.2-2 / PS3.7 Annex C), as dicom-mpps does')
    rep.check('PS3.3 2026a C.4.10 (0040,0020) Defined Terms, PS3.4 Table F.7.2-1 Type 1, PS3.16 CID 9301: dicom-mwl / dicom-mpps '
              'Workshop pickers, texts and warning wording (D85)', matched, wrong)


def check_web_rules(rep, parts, files, ctx):
    """dicom-wado Workshop (qido / wado / stow / ups): the Workshop's copy of the CLI-local WADOOptionRules is
    text-identical (PS3.18 2026a 9.1.2.2.1, 9.5.1.2.1, 8.3.4.4, 11.7.1.4); the ups --state picker offers exactly
    the Change State targets of PS3.18 11.7.1.4 and the executor refuses SCHEDULED (PS3.4 Table CC.1.1-2);
    --filter-state and --state spell the Procedure Step State (0074,1000) as PS3.3 2026a C.30.1 does; --priority
    offers the PS3.3 C.30.2 Enumerated Values; the retrieve --format picker is the CLI's MetadataFormat; every
    cliMapping token of the operation / protocol pickers is a dicom-wado flag; --content-type is the shared
    WADOURIClient.MediaType list (Table 8.7.4-1)."""
    dw, nd = ctx['dw'], ctx['nd']
    ws = ctx['workshop_surface']()
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    # PS3.18 11.7.1.4: the legal Change State values
    sec = dw.section_by_id(parts[18], 'sect_11.7.1.4')
    text = nd.norm(' '.join(sec.itertext())) if sec is not None else ''
    legal = re.findall(r'"(IN PROGRESS|COMPLETED|CANCELED)"', text.split('Procedure Step State (0074,1000)')[-1][:300])
    if legal != ['IN PROGRESS', 'COMPLETED', 'CANCELED']:
        wrong.append(f'PS3.18 11.7.1.4 legal values read as {legal}; re-read')
    else:
        matched += 1
    # PS3.3 C.30.1: the four Enumerated Values of (0074,1000); C.30.2: the priority values
    sec = dw.section_by_id(parts[3], 'sect_C.30.1')
    t = nd.norm(' '.join(sec.itertext())) if sec is not None else ''
    i = t.find('Enumerated Values:')
    states = re.findall(r'\b(SCHEDULED|IN PROGRESS|CANCELED|COMPLETED)\b', t[i:i + 80])
    if sorted(states) != ['CANCELED', 'COMPLETED', 'IN PROGRESS', 'SCHEDULED']:
        wrong.append(f'PS3.3 C.30.1 (0074,1000) Enumerated Values read as {states}; re-read')
    else:
        matched += 1
    sec = dw.section_by_id(parts[3], 'sect_C.30.2')
    t = nd.norm(' '.join(sec.itertext())) if sec is not None else ''
    j = t.find('Scheduled Procedure Step Priority (0074,1200)')
    prios = re.findall(r'\b(HIGH|MEDIUM|LOW)\b', t[j:j + 600].split('Enumerated Values:')[-1][:400]) if j >= 0 else []
    if sorted(set(prios)) != ['HIGH', 'LOW', 'MEDIUM']:
        wrong.append(f'PS3.3 C.30.2 (0074,1200) Enumerated Values read as {prios}; re-read')
    else:
        matched += 1
    # the Workshop pickers
    p = param(ws, 'dicom-ups', 'state')
    if p is None or p.get('allowedValues') != legal or p.get('defaultValue') != 'IN PROGRESS':
        wrong.append(f'dicom-ups --state picker must offer exactly {legal} (PS3.18 11.7.1.4) with default IN PROGRESS; SCHEDULED is refused (PS3.4 Table CC.1.1-2)')
    else:
        matched += len(legal)
    f = param(ws, 'dicom-ups', 'filter-state')
    if f is None or f.get('allowedValues') != [''] + ['SCHEDULED', 'IN PROGRESS', 'COMPLETED', 'CANCELED']:
        wrong.append('dicom-ups --filter-state picker must offer the PS3.3 Table C.30.1-1 words SCHEDULED, IN PROGRESS, COMPLETED, CANCELED')
    else:
        matched += 4
    pr = param(ws, 'dicom-ups', 'create-priority')
    if pr is None or pr.get('allowedValues') != ['HIGH', 'MEDIUM', 'LOW'] or pr.get('defaultValue') != 'MEDIUM':
        wrong.append('dicom-ups --priority picker must offer HIGH, MEDIUM, LOW (PS3.3 Table C.30.2-1) with default MEDIUM')
    else:
        matched += 3
    # the Workshop's WADOOptionRules copy is text-identical (literals naming a PS3.18 clause or an option)
    cli = read(ctx, 'dicom-wado/WADOOptionRules.swift')
    rules_body = block(vm, r'enum WorkshopWADOOptionRules \{', 'WorkshopWADOOptionRules')
    ws_lit = literals(rules_body)
    for lit in literals(cli):
        if not ('PS3.18' in lit or lit.startswith('--') or 'Change Workitem State' in lit or 'parameter' in lit):
            continue
        if lit in ws_lit:
            matched += 1
        else:
            wrong.append(f'dicom-wado WADOOptionRules text not mirrored by WorkshopWADOOptionRules: "{lit[:90]}"')
    for lit in literals(read(ctx, 'dicom-wado/DICOMWado.swift')):
        if any(k in lit for k in ('is required for', '--transaction-uid is required', '--label is required', '--state is required',
                                   'Invalid patient sex', 'Invalid priority', 'Invalid date format', 'Specify an operation',
                                   'must be at least 1', 'No files specified', 'must be a positive integer', 'frameNumber names a single frame')):
            if lit in literals(vm):
                matched += 1
            else:
                wrong.append(f'dicom-wado text not mirrored by the Workshop: "{lit[:90]}"')
    ups_body = block(vm, r'private func executeDicomUPS\(\) async \{', 'executeDicomUPS')
    for needle in ('WorkshopWADOOptionRules.changeStateTarget(stateString)', 'WorkshopWADOOptionRules.changeStateWorkitem(changeState: changeState, update: update)',
                   'WorkshopWADOOptionRules.updateDeprecationNote', 'UPSResultFormatter().format(', 'UPSConsole.updateResultText('):
        if needle in ups_body:
            matched += 1
        else:
            wrong.append(f'executeDicomUPS must contain `{needle}`')
    # cliMapping tokens are dicom-wado flags; the retrieve --format is MetadataFormat; content-type is the shared list
    files_w, options, outputs, commands = ctx['dc'].surface('dicom-wado')
    flags = {n for o in options for n in o['names']}
    # (the surface parser keeps neither cliMapping nor a non-literal allowedValues: read the definitions)
    helpers = src(files, 'CLIWorkshopHelpers.swift')

    def definition(pid, tool):
        arm = re.search(r'^[ \t]*case "' + re.escape(tool) + r'":', helpers, re.M)
        start = arm.end() if arm else 0
        nxt = re.search(r'^[ \t]*case "dicom-', helpers[start:], re.M)
        scope = helpers[start:start + nxt.start()] if nxt else helpers[start:]
        m = re.search(r'CLIParameterDefinition\(\s*id: "' + re.escape(pid) + r'",', scope)
        if not m:
            return ''
        open_paren = m.start() + len('CLIParameterDefinition')
        return scope[m.start():ctx['dc'].balanced(scope, open_paren)]
    for tool, pid in (('dicom-ups', 'operation'), ('dicom-wado', 'wado-protocol')):
        q = definition(pid, tool)
        mapping = re.findall(r'"[^"]+":\s*"(--[\w-]+)"', q[q.find('cliMapping'):] if 'cliMapping' in q else '')
        if not mapping:
            wrong.append(f'{tool} {pid} picker has no cliMapping')
        for tok in mapping:
            if tok in flags:
                matched += 1
            else:
                wrong.append(f'{tool} {pid} cliMapping emits {tok}, not a dicom-wado flag')
    fmt = param(ws, 'dicom-wado', 'format')
    meta = None
    for srcw in files_w.values():
        vals = re.findall(r'case (\w+)', dw.enum_body(srcw, 'MetadataFormat') or '')
        if vals:
            meta = vals
    if fmt is None or meta is None or fmt.get('allowedValues') != meta or fmt.get('defaultValue') != 'json':
        wrong.append(f'dicom-wado retrieve --format picker {fmt and fmt.get("allowedValues")} must be the CLI MetadataFormat {meta} (default json)')
    else:
        matched += len(meta)
    ct = param(ws, 'dicom-wado', 'content-type')
    if ct is None or ct.get('flag') != '--content-type' \
            or 'allowedValues: [""] + WADOURIClient.MediaType.allowed.map(\\.rawValue)' not in definition('content-type', 'dicom-wado'):
        wrong.append('dicom-wado --content-type must be a real flag whose picker is WADOURIClient.MediaType.allowed (PS3.18 Table 8.7.4-1)')
    else:
        matched += 1
    rep.check('PS3.18 2026a 11.7.1.4 / 9.1.2.2.1 / 8.3.4.4, PS3.3 C.30.1 / C.30.2, PS3.4 Table CC.1.1-2: dicom-wado Workshop '
              '(qido / wado / stow / ups) rules mirror, UPS state refusal, pickers and cliMapping flags (P-WADO-UPS-STATE / -UPDATE, P-QUERY-JSON)',
              matched, wrong)




# --- pixel / codec tools (dicom-anon, dicom-image, dicom-pdf, dicom-pixedit, dicom-video, dicom-convert, dicom-compress) ----

def raw_definition(helpers, pid, flag):
    """Source text of the CLIParameterDefinition with this id and flag (parse_definition reads a `[""] + Expr`
    picker as the literal [""], so expression pickers are checked on the source text)."""
    out = []
    for m in re.finditer(r'id: "' + re.escape(pid) + r'", flag: "' + re.escape(flag) + r'"', helpers):
        start = helpers.rfind('CLIParameterDefinition(', 0, m.start())
        depth, i = 0, start + len('CLIParameterDefinition')
        while i < len(helpers):
            if helpers[i] == '(':
                depth += 1
            elif helpers[i] == ')':
                depth -= 1
                if depth == 0:
                    out.append(helpers[start:i + 1])
                    break
            i += 1
    return '\n'.join(out)


def mirror_literals(cli_body, ws_body, keep, label, matched, wrong, limit=100):
    """Every CLI literal containing one of `keep` must be in the Workshop mirror, text-identical."""
    cli_lit, ws_lit = literals(cli_body), literals(ws_body)
    for lit in sorted(cli_lit):
        if not any(k in lit for k in keep):
            continue
        if lit in ws_lit:
            matched += 1
        else:
            wrong.append(f'{label} text not mirrored by the Workshop: "{lit[:limit]}"')
    return matched


def check_pixel_anon_options(rep, parts, files, ctx):
    """PS3.15 2026a Annex E / Table E.1-1 Option columns / PS3.16 CID 7050: the dicom-anon Workshop form offers every
    E.3 Option flag the CLI declares (help texts the CLI's, each naming its CID 7050 Option), plus the pixel-cleaning
    options; WorkshopAnonCLI mirrors the CLI-local AnonCLI texts."""
    dk = ctx['dk']
    ws = ctx['workshop_surface']()
    helpers, vm = src(files, 'CLIWorkshopHelpers.swift'), src(files, 'CLIWorkshopViewModel.swift')
    cli_support = read(ctx, 'dicom-anon/AnonCLISupport.swift')
    cli_main = read(ctx, 'dicom-anon/main.swift')
    wrong, matched = [], 0
    # the CLI's PS315Flags.setFlags, in order
    set_flags = re.findall(r'\("(--[a-z-]+)",\s*\w+\)', block(cli_support, r'var setFlags: \[String\] \{', 'PS315Flags.setFlags'))
    ws_ids = re.findall(r'"([a-z-]+)"', block(vm, r'static let optionFlagIDs = \[', 'WorkshopAnonCLI.optionFlagIDs'))
    if ['--' + i for i in ws_ids] != set_flags:
        wrong.append(f'WorkshopAnonCLI.optionFlagIDs {ws_ids} != dicom-anon PS315Flags.setFlags {set_flags}')
    else:
        matched += len(set_flags)
    cid7050 = {m.lower(): v for s_, v, m in dk.cid_rows(parts[16], 'CID 7050') if s_ == 'DCM'}
    e3_titles = {ctx['dw'].section_title(parts[15], f'sect_E.3.{n}') for n in range(1, 12)}
    for flag in set_flags + ['--clean-pixel-data', '--redact-region', '--redact-fill', '--allow-burned-in-phi']:
        p = next((q for q in ws.get('dicom-anon', []) if q.get('flag') == flag), None)
        if p is None:
            wrong.append(f'dicom-anon form lacks {flag} (PS3.15 E.3 / E.1.1)')
            continue
        matched += 1
        cli = cli_help(ctx, 'dicom-anon', flag)
        help_text = str(p.get('helpText', ''))
        if not cli or not help_text.startswith(cli[-1]):
            wrong.append(f'{flag}: Workshop help {help_text[:70]!r} does not carry the CLI help {cli and cli[-1][:70]!r}')
        else:
            matched += 1
        if flag in set_flags and flag != '--retain-dates':
            norm = help_text.replace('With ', '').lower()
            if not any(meaning in norm for meaning in cid7050):
                wrong.append(f'{flag}: help names no PS3.16 CID 7050 De-identification Method Option')
            else:
                matched += 1
    # Table E.1-1 Option columns (10 "Opt." columns) each have a flag
    header = []
    for lab, cap, t in parts[15].tables():
        if lab == 'E.1-1':
            header = [ctx['nd'].norm(' '.join(x.itertext())) for x in t.iter() if x.tag.split('}')[-1] == 'th']
            break
    columns = [h for h in header if h.endswith('Opt.')]
    column_flags = {'Rtn. Safe Priv. Opt.': '--retain-safe-private', 'Rtn. UIDs Opt.': '--retain-uids',
                    'Rtn. Dev. Id. Opt.': '--retain-device', 'Rtn. Inst. Id. Opt.': '--retain-institution',
                    'Rtn. Pat. Chars. Opt.': '--retain-characteristics', 'Rtn. Long. Full Dates Opt.': '--retain-full-dates',
                    'Rtn. Long. Modif. Dates Opt.': '--retain-modified-dates', 'Clean Desc. Opt.': '--clean-descriptors',
                    'Clean Struct. Cont. Opt.': '--clean-structured-content', 'Clean Graph. Opt.': '--clean-graphics'}
    if len(columns) != 10:
        wrong.append(f'PS3.15 Table E.1-1: expected 10 Option columns, read {columns}; re-read the table')
    for col in columns:
        flag = column_flags.get(col)
        if flag is None or flag not in set_flags:
            wrong.append(f'Table E.1-1 column "{col}" has no dicom-anon flag in the Workshop form')
        else:
            matched += 1
    for title in e3_titles - {'Retain Longitudinal Temporal Information Options'}:
        if not any(title.replace(' Option', '').lower() in str(p.get('helpText', '')).lower() for p in ws.get('dicom-anon', [])):
            wrong.append(f'PS3.15 E.3 "{title}" is named by no dicom-anon form help')
        else:
            matched += 1
    # the mirror: every WorkshopAnonCLI text is an AnonCLI text (the mirror carries only what the legacy
    # path needs; the ps315-only rules stay in the CLI until P-STUDIO-ANON-PS315)
    ws_body = block(vm, r'enum WorkshopAnonCLI \{', 'WorkshopAnonCLI')
    cli_lit = literals(cli_support) | literals(cli_main)
    only_text = 'PS3.15 Annex E Option flags apply only to --profile ps315: '
    for lit in sorted(literals(ws_body)):
        if not any(k in lit for k in ('PS3', 'Deprecated', 'Note:', 'profile', 'not in PS3.6', 'Private Data Element', 'Attribute actions')):
            continue
        if lit in cli_lit or lit.startswith(only_text):
            matched += 1
        else:
            wrong.append(f'WorkshopAnonCLI text is not a dicom-anon AnonCLI text: "{lit[:100]}"')
    if only_text not in cli_support:
        wrong.append(f'dicom-anon AnonCLI.validate no longer says "{only_text}"; update the mirror')
    for lit in literals(cli_main):
        if lit.startswith('Invalid anonymization profile') or lit == 'File not found':
            if lit in literals(ws_body):
                matched += 1
            else:
                wrong.append(f'dicom-anon text not mirrored: "{lit}"')
    cli_aliases = re.findall(r'"([a-z0-9-]+)":\s*\.(\w+)', block(cli_support, r'static let profileAliases: \[String: Profile\] = \[', 'profileAliases'))
    ws_aliases = re.findall(r'"([a-z0-9-]+)":\s*\.(\w+)', block(ws_body, r'static let profileAliases: \[String: Profile\] = \[', 'profileAliases'))
    if cli_aliases != ws_aliases:
        wrong.append(f'WorkshopAnonCLI.profileAliases {ws_aliases} != AnonCLI.profileAliases {cli_aliases}')
    else:
        matched += len(cli_aliases)
    if 'WorkshopAnonCLI.optionsOnlyForPS315(setOptionFlags)' not in vm:
        wrong.append('the dicom-anon executor must refuse set E.3 flags with the CLI\'s "apply only to --profile ps315" text')
    else:
        matched += 1
    rep.check(f'PS3.15 2026a Annex E (Table E.1-1 {len(columns)} Option columns, E.3.1-E.3.11), PS3.16 CID 7050: dicom-anon Workshop '
              f'E.3 option flags, pixel-cleaning options, CLI help and the WorkshopAnonCLI mirror (P-ANON-RETAIN-DATES; ps315 PEND)',
              matched, wrong)


def check_pixel_conversion_type(rep, parts, files, ctx):
    """PS3.3 2026a Table C.8-24 Conversion Type (0008,0064) Defined Terms: DICOMKit ConversionType.definedTerms, the
    CLI lists (dicom-pdf PDFEncapsulation.conversionTypes) and the dicom-image / dicom-pdf Workshop pickers."""
    dw, nd = ctx['dw'], ctx['nd']
    ws = ctx['workshop_surface']()
    wrong, matched = [], 0
    sec = dw.section_by_id(parts[3], 'sect_C.8.6.1')
    text = nd.norm(' '.join(sec.itertext())) if sec is not None else ''
    m = re.search(r'Conversion Type \(0008,0064\) 1 Describes the kind of image conversion\. Defined Terms: (.*?) Modality \(0008,0060\)', text)
    std = re.findall(r'\b([A-Z]{2,3})\b(?= [A-Z][a-z])', m.group(1)) if m else []
    if len(std) != 8:
        wrong.append(f'PS3.3 Table C.8-24: could not read the 8 Defined Terms (got {std}); re-read the table')
    kit = read(ctx, 'DICOMKit/SecondaryCapture/SecondaryCaptureImage.swift')
    kit_terms = re.findall(r'"(\w+)"', re.search(r'static let definedTerms: \[String\] = \[([^\]]*)\]', kit).group(1))
    if kit_terms != std:
        wrong.append(f'ConversionType.definedTerms {kit_terms} != PS3.3 Table C.8-24 {std} (DICOMKit)')
    else:
        matched += len(std)
    pdf_cli = read(ctx, 'dicom-pdf/EncapsulationAttributes.swift')
    for label, body in (('dicom-pdf PDFEncapsulation.conversionTypes', pdf_cli),
                        ('WorkshopPDFEncapsulation.conversionTypes', src(files, 'CLIWorkshopViewModel.swift'))):
        terms = re.findall(r'"(\w+)"', re.search(r'static let conversionTypes = \[([^\]]*)\]', body).group(1))
        if terms != std:
            wrong.append(f'{label} {terms} != Table C.8-24 {std}')
        else:
            matched += 1
    helpers = src(files, 'CLIWorkshopHelpers.swift')
    if helpers.count('allowedValues: [""] + ConversionType.definedTerms') != 2:
        wrong.append('the dicom-image and dicom-pdf --conversion-type pickers must both be [""] + ConversionType.definedTerms')
    else:
        matched += 2
    for tool in ('dicom-image', 'dicom-pdf'):
        p = param(ws, tool, 'conversion-type')
        if p is None or 'allowedValues: [""] + ConversionType.definedTerms' not in raw_definition(helpers, 'conversion-type', '--conversion-type') or p.get('defaultValue'):
            wrong.append(f'{tool} --conversion-type picker must be [""] + ConversionType.definedTerms with no default (the CLI writes WSD when absent)')
        else:
            matched += 1
            cli = cli_help(ctx, tool, '--conversion-type')
            if tool == 'dicom-image' and cli and cli[-1] != p.get('helpText'):
                wrong.append(f'{tool} --conversion-type help differs from the CLI: {p.get("helpText")!r}')
            for term in std:
                if term not in str(p.get('helpText', '')):
                    wrong.append(f'{tool} --conversion-type help does not name {term}')
                else:
                    matched += 1
    bia = param(ws, 'dicom-pdf', 'burned-in-annotation')
    pdf_values = re.findall(r'"(\w+)"', re.search(r'static let burnedInAnnotationValues = \[([^\]]*)\]', pdf_cli).group(1))
    if bia is None or bia.get('allowedValues') != [''] + pdf_values:
        wrong.append(f'dicom-pdf --burned-in-annotation picker must be [""] + {pdf_values} (PS3.3 Table C.24-2)')
    else:
        matched += len(pdf_values)
    rep.check('PS3.3 2026a Table C.8-24 (8 Conversion Type Defined Terms) / Table C.24-2: dicom-image and dicom-pdf Workshop '
              '--conversion-type / --burned-in-annotation pickers, DICOMKit ConversionType.definedTerms and the CLI lists',
              matched, wrong)


def check_pixel_cid3000_audio(rep, parts, files, ctx):
    """PS3.16 2026a CID 3000 Audio Channel Source and PS3.3 A.32.x / Table C.7-1: the dicom-video Workshop mirrors of
    AudioChannelSourceOption and VideoOptionConformance are text-identical and the CID rows match."""
    dk = ctx['dk']
    ws = ctx['workshop_surface']()
    helpers = src(files, 'CLIWorkshopHelpers.swift')
    cli_audio = read(ctx, 'dicom-video/AudioChannelSourceOption.swift')
    cli_conf = read(ctx, 'dicom-video/OptionConformance.swift')
    wrong, matched = [], 0
    pat = r'\("([a-z-]+)",\s*VideoAudioChannel\.Source\(dcmCodeValue:\s*"(\d+)",\s*codeMeaning:\s*"([^"]+)"\)\)'
    cli_rows = re.findall(pat, cli_audio)
    ws_rows = re.findall(pat, block(helpers, r'enum WorkshopAudioChannelSourceOption \{', 'WorkshopAudioChannelSourceOption'))
    if cli_rows != ws_rows:
        wrong.append(f'WorkshopAudioChannelSourceOption.keywords differ from the CLI: {ws_rows} vs {cli_rows}')
    cid = [(v, m) for s_, v, m in dk.cid_rows(parts[16], 'CID 3000') if s_ == 'DCM']
    if [(v, m) for _, v, m in ws_rows] != cid:
        wrong.append(f'Workshop CID 3000 rows {[(v, m) for _, v, m in ws_rows]} != PS3.16 CID 3000 {cid}')
    else:
        matched += len(cid)
    for kw, _, meaning in ws_rows:
        if kw != re.sub(r"[^a-z0-9]+", '-', meaning.lower().replace("'", '')).strip('-'):
            wrong.append(f'keyword {kw} is not the hyphenated Code Meaning "{meaning}"')
        else:
            matched += 1
    ws_body = block(helpers, r'enum WorkshopAudioChannelSourceOption \{', 'WorkshopAudioChannelSourceOption')
    matched = mirror_literals(cli_audio, ws_body, ('CID 3000', '--audio-channel-source', 'keywords', 'SCHEME'), 'dicom-video AudioChannelSourceOption', matched, wrong)
    ws_conf = block(helpers, r'enum WorkshopVideoOptionConformance \{', 'WorkshopVideoOptionConformance')
    matched = mirror_literals(cli_conf, ws_conf, ('refused', 'PS3', 'ES', 'GM', 'XC', 'A.32'), 'dicom-video VideoOptionConformance', matched, wrong)
    for mod, sect in (('ES', 'A.32.5.4.1'), ('GM', 'A.32.6.4.1'), ('XC', 'A.32.7.4.1')):
        s = ctx['dw'].section_by_id(parts[3], 'sect_' + sect)
        t = ctx['nd'].norm(' '.join(s.itertext())) if s is not None else ''
        if f'shall be {mod}' not in t:
            wrong.append(f'PS3.3 {sect}: "shall be {mod}" not found; re-read')
        elif f'return ("{mod}", "{sect}")' not in ws_conf:
            wrong.append(f'WorkshopVideoOptionConformance.requiredModality lacks ("{mod}", "{sect}")')
        else:
            matched += 1
    sex = ctx['dw'].section_by_id(parts[3], 'sect_C.7.1.1')
    sex_text = ctx['nd'].norm(' '.join(sex.itertext())) if sex is not None else ''
    sex_values = re.findall(r'\b([MFO]) (?:male|female|other)\b', sex_text.partition("Patient's Sex")[2].partition('See Note')[0])
    if sex_values[:3] != ['M', 'F', 'O'] or 'static let patientSexValues = ["M", "F", "O"]' not in ws_conf:
        wrong.append(f'Patient\'s Sex Enumerated Values (PS3.3 C.7.1.1 / Table C.7-1): standard {sex_values[:3]}, Workshop patientSexValues must be ["M", "F", "O"]')
    else:
        matched += 3
    for pid, expr in (('modality', 'WorkshopVideoOptionConformance.modalityHelp'), ('patientSex', 'WorkshopVideoOptionConformance.patientSexHelp'),
                      ('patientBirthDate', 'WorkshopVideoOptionConformance.patientBirthDateHelp'), ('transferSyntax', 'WorkshopVideoOptionConformance.transferSyntaxHelp')):
        p = param(ws, 'dicom-video', pid)
        if p is None or not str(p.get('helpText', '')).startswith(expr):
            wrong.append(f'dicom-video {pid} help must be the CLI\'s {expr} (states the refusal)')
        else:
            matched += 1
    for pid, flag in (('strictModality', '--strict-modality'), ('audioChannelSource', '--audio-channel-source')):
        p = param(ws, 'dicom-video', pid)
        if p is None or p.get('flag') != flag:
            wrong.append(f'dicom-video form lacks {flag}')
        else:
            matched += 1
    t = param(ws, 'dicom-video', 'type')
    if t is None or 'allowedValues: [""] + VideoConsole.TypeArgument.allCases.map(\\.rawValue)' not in raw_definition(helpers, 'type', '--type'):
        wrong.append('dicom-video --type picker must be [""] + VideoConsole.TypeArgument.allCases (the DEFERRED by-parser row)')
    else:
        matched += 1
    vm = src(files, 'CLIWorkshopViewModel.swift')
    for needle in ('WorkshopVideoOptionConformance.violations(', 'WorkshopAudioChannelSourceOption.parse(', 'metadata.audioChannelSources = sources'):
        if needle in vm:
            matched += 1
        else:
            wrong.append(f'dicom-video executor does not use {needle}')
    rep.check(f'PS3.16 2026a CID 3000 ({len(cid)} rows), PS3.3 A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1, C.7.1.1 Patient\'s Sex: dicom-video Workshop '
              '--audio-channel-source (D56) and the P-VIDEO-* refusals mirror the CLI', matched, wrong)


def check_pixel_compress_syntax(rep, parts, files, ctx):
    """PS3.6 2026a Table A-1 / PS3.5 A.1, A.2, A.3, A.5: dicom-compress decompress / batch --syntax picker is the
    CLI's NativeTargetSyntax (explicit-le, implicit-le, deflate, explicit-be) and the refusal texts are mirrored."""
    dw = ctx['dw']
    ws = ctx['workshop_surface']()
    helpers = src(files, 'CLIWorkshopHelpers.swift')
    cli = read(ctx, 'dicom-compress/main.swift')
    core = read(ctx, 'DICOMCore/TransferSyntax.swift')
    wrong, matched = [], 0
    pat = r'\("([a-z-]+)",\s*\.(\w+)\)'
    cli_acc = re.findall(pat, block(cli, r'enum NativeTargetSyntax \{', 'NativeTargetSyntax'))
    ws_body = block(helpers, r'enum WorkshopNativeTargetSyntax \{', 'WorkshopNativeTargetSyntax')
    ws_acc = re.findall(pat, ws_body)
    if cli_acc != ws_acc or not cli_acc:
        wrong.append(f'WorkshopNativeTargetSyntax.accepted {ws_acc} != dicom-compress NativeTargetSyntax.accepted {cli_acc}')
    registry = dw.uid_registry(parts[6])
    for name, const in cli_acc:
        m = re.search(r'static let ' + const + r' = TransferSyntax\(\s*uid:\s*"([\d.]+)"', core)
        uid = m.group(1) if m else None
        if uid is None or uid not in registry:
            wrong.append(f'{name}: DICOMCore TransferSyntax.{const} UID {uid} is not a PS3.6 Table A-1 row')
        elif not any(registry[uid][0].startswith(n) for n in ('Implicit VR Little Endian', 'Explicit VR Little Endian', 'Deflated Explicit VR Little Endian', 'Explicit VR Big Endian')):
            wrong.append(f'{name}: {uid} is "{registry[uid][0]}", not a native (PS3.5 A.1 / A.2 / A.3 / A.5) Transfer Syntax')
        else:
            matched += 1
    for sub, pid in (('decompress', 'syntax'), ('batch', 'syntax')):
        p = param(ws, 'dicom-compress', pid)
        if p is None or p.get('allowedValues') != 'WorkshopNativeTargetSyntax.accepted.map(\\.name)' or p.get('defaultValue') != 'explicit-le':
            wrong.append(f'dicom-compress --syntax picker must be WorkshopNativeTargetSyntax.accepted.map(\\.name) with default explicit-le')
        else:
            matched += 1
        cli_h = cli_help(ctx, 'dicom-compress', '--syntax')
        if p is not None and cli_h and p.get('helpText') not in cli_h:
            wrong.append(f'dicom-compress --syntax help {p.get("helpText")!r} is neither subcommand\'s CLI help')
        else:
            matched += 1
    matched = mirror_literals(block(cli, r'enum NativeTargetSyntax \{', 'NativeTargetSyntax'), ws_body, ('syntax', 'PS3', 'Native targets'), 'dicom-compress NativeTargetSyntax', matched, wrong)
    vm = src(files, 'CLIWorkshopViewModel.swift')
    if vm.count('WorkshopNativeTargetSyntax.resolve(syntax)') < 2:
        wrong.append('decompress and batch executors must resolve --syntax through WorkshopNativeTargetSyntax.resolve')
    else:
        matched += 2
    if 'CompressionConsole.infoJSON(info, filePath: displayPath)' not in vm:
        wrong.append('info --json must render through the shared CompressionConsole.infoJSON (P-COMPRESS-JSON)')
    else:
        matched += 1
    rep.check(f'PS3.6 2026a Table A-1 / PS3.5 A.1, A.2, A.3, A.5: dicom-compress Workshop decompress / batch --syntax picker is the '
              f'{len(cli_acc)} native targets of NativeTargetSyntax, refusals mirrored (P-COMPRESS-SYNTAX); info --json shared (P-COMPRESS-JSON)',
              matched, wrong)


def check_pixel_convert_tokens(rep, parts, files, ctx):
    """PS3.6 2026a Table A-1 keywords / PS3.3 Table 10-3: the dicom-convert Workshop --transfer-syntax picker is
    DICOMConverter.cliTokens, the CLI-local TransferSyntaxKeywords are mirrored and their keywords are Table A-1 rows,
    frames are selected by Frame number from 1 with --frame deprecated."""
    dw = ctx['dw']
    ws = ctx['workshop_surface']()
    helpers, vm = src(files, 'CLIWorkshopHelpers.swift'), src(files, 'CLIWorkshopViewModel.swift')
    cli = read(ctx, 'dicom-convert/TransferSyntaxKeywords.swift')
    wrong, matched = [], 0
    pat = r'"(\w+)":\s*"([\d.]+)"'
    cli_add = re.findall(pat, block(cli, r'static let additional: \[String: String\] = \[', 'additional'))
    ws_body = block(helpers, r'enum WorkshopTransferSyntaxKeywords \{', 'WorkshopTransferSyntaxKeywords')
    ws_add = re.findall(pat, block(ws_body, r'static let additional: \[String: String\] = \[', 'additional'))
    if cli_add != ws_add or not cli_add:
        wrong.append(f'WorkshopTransferSyntaxKeywords.additional differs from dicom-convert: {ws_add} vs {cli_add}')
    registry = dw.uid_registry(parts[6])
    for keyword, uid in ws_add:
        row = registry.get(uid)
        if row is None or row[1].strip() != keyword:
            wrong.append(f'{keyword} -> {uid}: PS3.6 Table A-1 keyword of that UID is {row and row[1]!r}')
        else:
            matched += 1
    matched = mirror_literals(cli, ws_body, ('Table A-1', 'Changed', 'Reversible'), 'dicom-convert TransferSyntaxKeywords', matched, wrong)
    p = param(ws, 'dicom-convert', 'transfer-syntax')
    if p is None or 'allowedValues: [""] + DICOMConverter.cliTokens' not in raw_definition(helpers, 'transfer-syntax', '--transfer-syntax') or p.get('helpText') != 'WorkshopTransferSyntaxKeywords.optionHelp':
        wrong.append('dicom-convert --transfer-syntax picker must be [""] + DICOMConverter.cliTokens with the CLI\'s TransferSyntaxKeywords.optionHelp')
    else:
        matched += 1
    # the three reassigned keywords are Table A-1 rows of their UIDs, and the Reversible spellings are catalog tokens
    core = read(ctx, 'DICOMCore/TransferSyntax.swift')
    kit = read(ctx, 'DICOMKit/DICOMConverter.swift')
    for keyword, uid, name, reversible, general in re.findall(r'\("(\w+)",\s*"([\d.]+)",\s*"([^"]+)",\s*"(\w+)",\s*"([\d.]+)"\)', block(core, r'static let reassignedTableA1Keywords[^=]*= \[', 'reassignedTableA1Keywords')):
        row = registry.get(uid)
        if row is None or row[1].strip() != keyword:
            wrong.append(f'{keyword}: PS3.6 Table A-1 keyword of {uid} is {row and row[1]!r} (DICOMCore)')
        elif f'cli: "{reversible}"' not in kit:
            wrong.append(f'{reversible} is not a DICOMConverter catalog cliToken (DICOMKit)')
        else:
            matched += 2
    t103 = ' '.join(' '.join(r) for r in dw.table_rows(parts[3], '10-3'))
    if 'The first Frame shall be denoted as Frame number 1' not in t103:
        wrong.append('PS3.3 Table 10-3: "The first Frame shall be denoted as Frame number 1" not found; re-read')
    else:
        matched += 1
    fn = param(ws, 'dicom-convert', 'frame-number')
    cli_fn = cli_help(ctx, 'dicom-convert', '--frame-number')
    if fn is None or str(fn.get('minValue')) != '1' or (cli_fn and fn.get('helpText') != cli_fn[-1]):
        wrong.append('dicom-convert --frame-number must have minValue 1 and the CLI\'s help (PS3.3 Table 10-3)')
    else:
        matched += 1
    fr = param(ws, 'dicom-convert', 'frame')
    cli_fr = cli_help(ctx, 'dicom-convert', '--frame')
    if fr is None or fr.get('defaultValue') or (cli_fr and fr.get('helpText') != cli_fr[-1]) or not str(fr.get('helpText', '')).startswith('deprecated'):
        wrong.append('dicom-convert --frame must be deprecated (the CLI\'s help, no default)')
    else:
        matched += 1
    for needle in ('WorkshopTransferSyntaxKeywords.meaningChangeNote(for: transferSyntax)', 'ConvertError.invalidFrameNumber(number, pixelData.descriptor.numberOfFrames)',
                   'DICOMConverter.invalidFrameNumberMessage(requested: requested, total: total)', 'cannot be used together', 'WorkshopTransferSyntaxKeywords.canonicalToken(value)'):
        if needle in vm:
            matched += 1
        else:
            wrong.append(f'dicom-convert executor lacks {needle}')
    rep.check(f'PS3.6 2026a Table A-1 ({len(ws_add)} added keywords + 3 reassigned), PS3.3 Table 10-3: dicom-convert Workshop --transfer-syntax tokens '
              '(DICOMConverter.cliTokens, P-CONVERT-TS-KEYWORDS), --frame-number / deprecated --frame (P-CONVERT-FRAME)', matched, wrong)


def check_pixel_rules_mirrors(rep, parts, files, ctx):
    """The dicom-image SCOutput, dicom-pdf PDFEncapsulation and dicom-pixedit DerivedImage CLI-local rules are mirrored
    text-identically by the Workshop (PS3.5 Table 6.2-1 / 9.1, PS3.3 Tables C.24-2 / C.12-1 / C.7.6.3.1 / C.11.2.1.2)."""
    vm = src(files, 'CLIWorkshopViewModel.swift')
    ws = ctx['workshop_surface']()
    wrong, matched = [], 0
    for cli_path, cli_pat, ws_pat, keep, label in (
            ('dicom-image/SCOutput.swift', r'enum SCOutput \{', r'enum WorkshopSCOutput \{', ('PS3', 'ISO_IR'), 'dicom-image SCOutput'),
            ('dicom-pdf/EncapsulationAttributes.swift', r'enum PDFEncapsulation \{', r'enum WorkshopPDFEncapsulation \{', ('PS3', 'ISO_IR', 'WSD'), 'dicom-pdf PDFEncapsulation'),
            ('dicom-pixedit/DerivedImage.swift', r'enum DerivedImage \{', r'enum WorkshopDerivedImage \{', ('PS3',), 'dicom-pixedit DerivedImage')):
        cli_body = block(read(ctx, cli_path), cli_pat, label)
        ws_body = block(vm, ws_pat, label + ' mirror')
        matched = mirror_literals(cli_body, ws_body, keep, label, matched, wrong)
        for name, value in re.findall(r'static let (\w+)(?:: [^=]+)? = (.+)', cli_body):
            m = re.search(r'static let ' + name + r'(?:: [^=]+)? = (.+)', ws_body)
            if not m:
                wrong.append(f'{label} mirror lacks {name}')
            elif m.group(1).strip() != value.strip():
                wrong.append(f'{label} mirror {name} = {m.group(1).strip()}; CLI has {value.strip()}')
            else:
                matched += 1
    # PS3.5 2026a Table 6.2-1 limits behind the refusals: LO / PN 64, UI 64; PS3.3 C.11.2.1.2 width >= 1
    rows = {r[0].split('\n')[0].strip(): ' '.join(r) for r in ctx['dw'].table_rows(parts[5], '6.2-1') if r}
    for vr, phrase in (('LO', '64 chars maximum'), ('PN', '64 chars maximum per component group'), ('UI', '64 bytes maximum')):
        key = next((k for k in rows if k.startswith(vr)), None)
        if key is None or phrase not in rows[key]:
            wrong.append(f'PS3.5 Table 6.2-1 {vr}: "{phrase}" not found; re-read the table')
        else:
            matched += 1
    sec = ctx['dw'].section_by_id(parts[3], 'sect_C.11.2.1.2')
    t = ctx['nd'].norm(' '.join(sec.itertext())) if sec is not None else ''
    if 'shall always be greater than or equal to 1' not in t:
        wrong.append('PS3.3 C.11.2.1.2: "shall always be greater than or equal to 1" not found; re-read')
    else:
        matched += 1
    for tool, pid, needle in (('dicom-image', 'strict-modality', '--strict-modality'), ('dicom-pdf', 'strict-modality', '--strict-modality'),
                              ('dicom-pdf', 'hl7-instance-identifier', '--hl7-instance-identifier')):
        p = param(ws, tool, pid)
        if p is None or p.get('flag') != needle:
            wrong.append(f'{tool} form lacks {needle}')
        else:
            matched += 1
    fv = param(ws, 'dicom-pixedit', 'fill-value')
    if fv is None or fv.get('defaultValue'):
        wrong.append('dicom-pixedit --fill-value must carry no default (the CLI\'s is nil; the executor refuses out-of-range values, P-PIXEDIT-RANGE)')
    else:
        matched += 1
    for needle in ('WorkshopSCOutput.valueViolations(', 'WorkshopSCOutput.finalize(data)', 'WorkshopPDFEncapsulation.complete(&dataSet, documentByteCount: documentData.count)',
                   'WorkshopPDFEncapsulation.documentBytes(document.documentData, in: dicomFile.dataSet)', 'WorkshopDerivedImage.fillValueViolation(', 'WorkshopDerivedImage.windowWidthViolation(width)',
                   'PixelEditDerivation(descriptionPrefix: "dicom-pixedit")'):
        if needle in vm:
            matched += 1
        else:
            wrong.append(f'executor lacks {needle}')
    rep.check('PS3.5 2026a Table 6.2-1 / 9.1, PS3.3 Tables C.24-2 / C.12-1 / C.7.6.3.1 / C.11.2.1.2: dicom-image, dicom-pdf and dicom-pixedit '
              'Workshop mirrors of SCOutput / PDFEncapsulation / DerivedImage (P-IMAGE-VR, P-PIXEDIT-RANGE, D182)', matched, wrong)

CHECKS = [
    ('G1 workshop dcmdir profile picker', check_dcmdir_profile_picker),
    ('G1 workshop dcmdir fileset rules', check_dcmdir_fileset_rules),
    ('G1 workshop export frames and rate', check_export_frames_and_rate),
    ('G1 workshop json xml empty', check_data_exchange_empty_and_deprecations),
    ('G1 workshop split frame numbers', check_split_frame_numbers),
    ('G1 workshop archive query keys', check_archive_query_keys),
    ('G1 workshop validate iod map', check_validate_iod_map),
    ('G1 workshop uid dump texts', check_uid_and_dump_texts),
    ('G1 validation panel', check_validation_panel),
    ('G1 workshop net query levels', check_query_retrieve_levels),
    ('G1 workshop net priority send', check_priority_and_store_outcomes),
    ('G1 workshop net retrieve status', check_retrieve_status_text_source),
    ('G1 workshop net mwl mpps terms', check_mwl_mpps_terms),
    ('G1 workshop net web rules', check_web_rules),
    ('G1 workshop pixel anon options', check_pixel_anon_options),
    ('G1 workshop pixel conversion type', check_pixel_conversion_type),
    ('G1 workshop pixel cid3000 audio source', check_pixel_cid3000_audio),
    ('G1 workshop pixel compress syntax', check_pixel_compress_syntax),
    ('G1 workshop pixel convert tokens', check_pixel_convert_tokens),
    ('G1 workshop pixel image pdf pixedit rules', check_pixel_rules_mirrors),
]
