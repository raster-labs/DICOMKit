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
"""
import os
import re

PENDING_API_APPROVAL = {}
# diff_studio.check_workshop_parity keys the CLI options by flag, so a `--format` that several subcommands
# declare is compared with the LAST one (compare --format = text, bulk --format = png). The Workshop rows it
# flags mirror their own subcommand's default (summary --format table, single --format jpeg: see
# `diff_cli.py --list-surface`). Tooling, not a standard finding; the orchestrator owns diff_studio.py.
DEFERRED = {
    "Workshop default 'table', dicom-study default 'text'":
        'diff_studio.py by-flag collapse (summary --format is table on both surfaces; compare --format is text)',
    "Workshop default 'jpeg', dicom-export default 'png'":
        'diff_studio.py by-flag collapse (single --format is jpeg on both surfaces; bulk --format is png)',
}
EXEMPT = {}

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
]
