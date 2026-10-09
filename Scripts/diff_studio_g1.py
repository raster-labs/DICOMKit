#!/usr/bin/env python3
"""DICOMStudio group G1 (CLI Workshop) row-by-row checks for the FILE tools of the Workshop:
dicom-info, dump, tags, diff, json, xml, validate, split, merge, dcmdir, archive, study, uid, export.

Loaded by diff_studio.py (``diff_studio_g1*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
The generic ``parity`` check of diff_studio.py already compares flags, defaults and picker values with the
ArgumentParser surface; the checks here pin what that diff cannot see, each against the frozen 2026a DocBook
or against the engine symbol the Workshop and the CLI both call (the CLI source where a text is still CLI-local):

  * dcmdir --profile picker          is DICOMCore.DICOMDIRProfile.allStandard, whose identifiers are exactly the
                                     PS3.11 2026a Tables A.1-1 … N.1-1 fixed identifiers; help names no family heading
  * dcmdir File-set rules            the Workshop and dicom-dcmdir call DICOMKit DICOMDIRFileSetRules (D253), no Workshop copy;
                                     its 16 / 8 / 8 / A-Z 0-9 _ against PS3.10 2026a 8.1, 8.2, 8.5
  * export frame numbers / rate      --frame-number, --start/--end-frame-number help "numbered from 1" (PS3.3 Table 10-3),
                                     the 0-based options deprecated; --fps has no fixed default and names the three
                                     Cine Module attributes of PS3.3 Table C.7-13 with their PS3.6 Table 6-1 names;
                                     both surfaces call DICOMImageExporter.CineFrameRate / FrameSelection / BurnedInAnnotation (D252)
  * json / xml empty attributes      include-empty default on with --no-include-empty (PS3.18 F.2.5 / PS3.19 Table
                                     A.1.5-2); the deprecation notes equal the CLIs'
  * split frame selection            --frames help says 0-based / deprecated, --frame-numbers "numbered from 1"
                                     (PS3.3 2026a C.7.6.16.1.2 "Frames are implicitly numbered starting from 1")
  * archive query                    --strict-modality offered; --modality help is the shared ModalityOptionValidator
                                     text; the --study-date warning is ArchiveMatching.studyDateKeyWarning in both (D249)
  * validate --iod                   both surfaces call DICOMValidator.iodName(forIODOption:) (D248); every UID / name of
                                     DICOMValidator.iodNameBySOPClassUID is a PS3.6 Table A-1 row
  * uid / dump refusal texts         both surfaces call UIDManager.RootRule (D250); the dicom-dump texts are mirrored
  * ValidationModel (panel)          --iod suggestions are PS3.6 Table A-1 UID Keywords; level texts = dicom-validate --level help
  * pixel / codec tools (anon, image, pdf, pixedit, video, convert, compress): the E.3 Option flags vs PS3.15 Table E.1-1
                                     columns / CID 7050, Conversion Type vs Table C.8-24, CID 3000 keywords, the compress
                                     native --syntax set, the convert token set (DICOMConverter.cliTokens); since the
                                     Studio pass (2026-10-06) the former CLI-local rule files are DICOMKit / DICOMNetwork /
                                     DICOMWeb symbols that the CLI and the Workshop both call (engine_calls), and no
                                     Workshop copy of their texts remains (no_local_copy)
  * directory run exits              export bulk / image / pdf directory runs exit 1 after the summary in both
                                     surfaces; pdf --extract skips non-documents (D251, D271, D273)
"""
import os
import re

# No pending rows. P-STUDIO-MWL-CREATE (2026-10-06): worklist-item creation (HL7 ORM^O01 / REST, not a DIMSE
# service) moved to the Networking panel; the Workshop's dicom-mwl offers only the CLI's `query`
# (check_mwl_mpps_terms). P-STUDIO-ANON-PS315: dicom-anon --profile ps315 (check_pixel_anon_options).
PENDING_API_APPROVAL = {
}
# Findings whose cause lives in another module (DEFR). The by-flag collapse (D247, D258 a), the cliMapping flags
# (D258 b) and the `[""] + Expr` pickers (D266) are now handled by diff_studio.check_workshop_parity itself:
# options are keyed by (subcommand, flag), cliMapping tokens count as offered, and non-literal pickers resolve.
DEFERRED = {
}
# Deliberate non-mirroring that the parity diff cannot see (it compares flags, defaults and pickers, not
# required-ness), recorded here as a note rather than a key, because EXEMPT keys are matched by flag across every
# tool: P-STUDIO-EXPORT-SINGLE-OUTPUT (071ad9c0) — the Workshop's dicom-export `single` keeps --output required,
# where the CLI derives a name from the input in the working directory when it is omitted; a sandboxed app has no
# working directory to write to (empty --output: ArgumentParser's missing-option text, exit 64). Documented at the
# parameter in CLIWorkshopHelpers.swift; not a DICOM 2026a matter.
EXEMPT = {
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


def block_or_empty(s, start_pat, what):
    """block(), or '' when the construct is absent — for checks that must report a missing symbol as a finding."""
    try:
        return block(s, start_pat, what)
    except SystemExit:
        return ''


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


def cli_sources(ctx, tool):
    """Every Swift file of a dicom-* tool, concatenated (the CLI side of an engine-call check)."""
    d = os.path.join(ctx['sources'], tool)
    return '\n'.join(ctx['dw'].read(os.path.join(d, f)) for f in sorted(os.listdir(d)) if f.endswith('.swift'))


def engine_calls(ws_text, cli_text, calls, label, matched, wrong, cli_calls=None):
    """Since the Studio pass (2026-10-06) the Workshop and the CLI call one engine symbol instead of carrying
    text-identical copies: every call in `calls` must be in the Workshop source, and every call in `cli_calls`
    (default: `calls`) in the CLI's, so the two surfaces provably run the same rule."""
    for c in calls:
        if c in ws_text:
            matched += 1
        else:
            wrong.append(f'{label}: the Workshop does not call {c}')
    for c in (calls if cli_calls is None else cli_calls):
        if c in cli_text:
            matched += 1
        else:
            wrong.append(f'{label}: the CLI does not call {c}; re-read the CLI')
    return matched


def no_local_copy(ws_text, engine_body, keep, forbidden, label, matched, wrong, minimum=16):
    """No Workshop-local copy of a lifted rule: none of the `forbidden` declarations is back, and no Workshop
    string literal equals an engine text literal that contains one of `keep` (the texts stay in the engine)."""
    for decl in forbidden:
        if decl in ws_text:
            wrong.append(f'{label}: the Workshop-local copy `{decl}` is back; call the engine symbol')
        else:
            matched += 1
    ws_lit = literals(ws_text)
    # sentences only: a bare flag or term ("--audio-channel-source", "ISO_IR 192") is shared vocabulary, not a copy
    texts = sorted(l for l in literals(engine_body) if len(l) >= minimum and ' ' in l.strip() and any(k in l for k in keep))
    dup = [l for l in texts if l in ws_lit]
    wrong += [f'{label}: the Workshop carries its own copy of the engine text "{l[:90]}"' for l in dup]
    if texts and not dup:
        matched += 1
    elif not texts:
        wrong.append(f'{label}: no engine text with {keep} found; update the extractor')
    return matched


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
        rules = read(ctx, 'DICOMKit/DICOMDIRFileSetRules.swift')   # the deprecated spellings, DICOMKit since D253
        dep = set(re.findall(r'"(STD-[A-Z0-9-]+)":\s*"PS3\.11', block(rules, r'deprecatedProfileTables: \[String: String\] = \[', 'deprecatedProfileTables')))
        help_text = str(p.get('helpText', ''))
        before, _, after = help_text.partition('deprecated:')
        for tok in re.findall(r'STD-[A-Z0-9-]+', before):
            if tok in std:
                matched += 1
            else:
                wrong.append(f'help names "{tok}" as an identifier; PS3.11 2026a has none')
        for tok in re.findall(r'STD-[A-Z0-9-]+', after):
            if tok not in dep and tok not in std and tok + 'xxxx' not in {t.replace('xxxx', 'XXXX') for t in templates} and tok not in {t.upper() for t in templates}:
                wrong.append(f'help lists "{tok}" as deprecated but DICOMDIRFileSetRules.deprecatedProfileTables does not')
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
    engine = read(ctx, 'DICOMKit/DICOMDIRFileSetRules.swift')
    eng_body = block(engine, r'enum DICOMDIRFileSetRules \{', 'DICOMDIRFileSetRules')
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    # Workshop and dicom-dcmdir both call DICOMKit DICOMDIRFileSetRules (D253); no Workshop copy remains
    calls = ['DICOMDIRFileSetRules.' + f for f in ('fileSetIDRefusal(', 'defaultFileSetID(', 'profileDeprecationNote(', 'describe(', 'findings(')]
    matched = engine_calls(vm, cli_sources(ctx, 'dicom-dcmdir'), calls, 'dicom-dcmdir File-set rules', matched, wrong)
    matched = no_local_copy(vm, eng_body, ('PS3', 'File', 'STD-'), ('enum WorkshopFileSetRules', 'enum FileSetRules {'),
                            'dicom-dcmdir File-set rules', matched, wrong)
    # PS3.10 2026a clauses behind the engine's constants
    def text(part, sid):
        e = dw.section_by_id(part, sid)
        return nd.norm(' '.join(e.itertext())) if e is not None else ''
    t81, t82, t85 = text(parts[10], 'sect_8.1'), text(parts[10], 'sect_8.2'), text(parts[10], 'sect_8.5')
    if 'zero (0) to sixteen (16) characters' not in t81:
        wrong.append('PS3.10 8.1: "16 characters" for the File-set ID not found; re-read the clause')
    elif 'maxFileSetIDLength = 16' not in eng_body:
        wrong.append('DICOMDIRFileSetRules.maxFileSetIDLength is not 16 (PS3.10 8.1; DICOMKit)')
    else:
        matched += 1
    if 'one to eight components' not in t82 or 'one to eight characters' not in t82:
        wrong.append('PS3.10 8.2: "one to eight components/characters" not found; re-read the clause')
    elif 'maxFileIDComponents = 8' not in eng_body or 'maxComponentLength = 8' not in eng_body:
        wrong.append('DICOMDIRFileSetRules File ID limits are not 8 / 8 (PS3.10 8.2; DICOMKit)')
    else:
        matched += 1
    letters = ''.join(re.findall(r'\b([A-Z])\b', t85.split('(uppercase)')[0].split('subset:')[-1]))
    digits = ''.join(sorted(re.findall(r'\b(\d)\b', t85.split('(uppercase)')[1].split('(underscore)')[0]))) if '(uppercase)' in t85 else ''
    allowed = re.search(r'allowedCharacters = Set\("([^"]+)"\)', eng_body)
    if letters != 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' or digits != '0123456789' or '_ (underscore)' not in t85:
        wrong.append('PS3.10 8.5: could not read the A-Z, 0-9, _ repertoire; re-read the clause')
    elif not allowed or set(allowed.group(1)) != set(letters + digits + '_'):
        wrong.append('DICOMDIRFileSetRules.allowedCharacters is not the PS3.10 8.5 repertoire A-Z, 0-9, _ (DICOMKit)')
    else:
        matched += 1
    rep.check('PS3.10 2026a 8.1, 8.2, 8.5: the dicom-dcmdir Workshop and CLI call DICOMKit DICOMDIRFileSetRules, no Workshop copy (D132, D253)',
              matched, wrong)


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
    c713 = {r[1].strip('()').replace(',', '').upper(): r[0].strip() for r in dw.table_rows(parts[3], 'C.7-13') if len(r) > 1 and re.match(r'\(\w{4},\w{4}\)', r[1].strip())}
    if p is None:
        wrong.append('dicom-export form lacks --fps')
    elif p.get('defaultValue'):
        wrong.append(f'--fps carries default {p.get("defaultValue")!r}; the CLI default is the file rate (PS3.3 Table C.7-13)')
    else:
        matched += 1
        m, w = named_tags_match(dictionary, str(p.get('helpText', '')))
        matched += m
        wrong += [f'--fps help: {x}' for x in w]
        for name, tag in re.findall(r'([A-Z][A-Za-z ]+?) \((\w{4},\w{4})\)', str(p.get('helpText', ''))):
            if tag.replace(',', '').upper() not in c713:
                wrong.append(f'--fps help names ({tag}), not a PS3.3 Table C.7-13 attribute')
    # the one rate resolution (DICOMKit, D252) reads the Cine Module attributes in the documented order and names
    # each source by its PS3.3 Table C.7-13 / PS3.6 Table 6-1 name and tag
    engine = read(ctx, 'DICOMKit/ImageExport/DICOMImageExporter+Standard.swift')
    order = re.findall(r'dataSet\.string\(for: \.(\w+)\)', block(engine, r'static func resolve\(explicit: Double\?, dataSet: DataSet\) -> CineFrameRate \{', 'CineFrameRate.resolve'))
    if order != ['recommendedDisplayFrameRate', 'cineRate', 'frameTime']:
        wrong.append(f'DICOMImageExporter.CineFrameRate.resolve reads {order}; expected Recommended Display Frame Rate, Cine Rate, Frame Time (DICOMKit)')
    else:
        matched += 1
    labels = block(engine, r'public var label: String \{', 'CineFrameRate.Source.label')
    for name, tag in re.findall(r'"([A-Z][A-Za-z ]+?) \((\w{4},\w{4})\)"', labels):
        if tag.replace(',', '').upper() not in c713:
            wrong.append(f'CineFrameRate.Source.label names ({tag}), not a PS3.3 Table C.7-13 attribute (DICOMKit)')
    m, w = named_tags_match(dictionary, labels)
    matched += m
    wrong += [f'CineFrameRate.Source.label: {x} (DICOMKit)' for x in w]
    # Workshop and dicom-export call the same DICOMImageExporter texts (D252); no Workshop copy remains
    vm = src(files, 'CLIWorkshopViewModel.swift')
    calls = ['DICOMImageExporter.CineFrameRate.resolve(', 'DICOMImageExporter.FrameSelection.reference', 'DICOMImageExporter.FrameSelection.deprecationNote(',
             'DICOMImageExporter.FrameSelection.invalidFrameNumberMessage(', 'DICOMImageExporter.FrameSelectionConflict(',
             'DICOMImageExporter.ApplyWindowDeprecation.note(', 'DICOMImageExporter.BurnedInAnnotation.isYes(',
             'DICOMImageExporter.BurnedInAnnotation.warning(for:', 'DICOMImageExporter.BurnedInAnnotation.summaryWarning(count:']
    matched = engine_calls(vm, cli_sources(ctx, 'dicom-export'), calls, 'dicom-export standard texts', matched, wrong)
    matched = no_local_copy(vm, engine, ('warning:', 'Frame number', 'cannot be used together', 'Table 10-3'),
                            ('static func exportCineFrameRate', 'static func exportFrameDeprecationNote', 'static func exportBurnedInWarning',
                             'static let exportFrameNumberReference'), 'dicom-export standard texts', matched, wrong)
    rep.check('PS3.3 2026a Table 10-3 / Table C.7-13: dicom-export Workshop frame numbers, deprecated 0-based options, '
              '--fps default; Workshop and CLI call DICOMImageExporter.CineFrameRate / FrameSelection / BurnedInAnnotation (D127, D252)', matched, wrong)


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
    # the --study-date warning is DICOMKit ArchiveMatching.studyDateKeyWarning in both surfaces (D249)
    engine = read(ctx, 'DICOMKit/Archive/ArchiveStore.swift')
    body = block(engine, r'static func studyDateKeyWarning\(_ value: String\?, option: String = "--study-date"\) -> String\? \{', 'studyDateKeyWarning')
    if 'C.2.2.2.5.1' not in body or 'dateRange(value)' not in body:
        wrong.append('ArchiveMatching.studyDateKeyWarning no longer cites PS3.4 C.2.2.2.5.1 / uses dateRange; re-read (DICOMKit)')
    else:
        matched += 1
    matched = engine_calls(vm, cli_sources(ctx, 'dicom-archive'), ['ArchiveMatching.studyDateKeyWarning('], 'dicom-archive --study-date', matched, wrong)
    matched = no_local_copy(vm, body, ('study-date', 'DA range'), ('func archiveStudyDateWarning',), 'dicom-archive --study-date', matched, wrong)
    rep.check('PS3.3 C.7.3.1.1.1 / PS3.4 C.2.2.2.5.1: dicom-archive Workshop query --strict-modality, modality help and the '
              'ArchiveMatching.studyDateKeyWarning both surfaces call (D249)', matched, wrong)


# --- dicom-validate --------------------------------------------------------------------------------------------

def check_validate_iod_map(rep, parts, files, ctx):
    dw = ctx['dw']
    vm = src(files, 'CLIWorkshopViewModel.swift')
    engine = read(ctx, 'DICOMKit/Validation/DICOMValidator.swift')
    registry = dw.uid_registry(parts[6])
    body = block(engine, r'iodNameBySOPClassUID: \[String: String\] = \[', 'iodNameBySOPClassUID')
    eng_map = {uid: (name, comment.strip()) for uid, name, comment in re.findall(r'"([\d.]+)":\s*"(\w+)",\s*//\s*([^\n]+)', body)}
    wrong, matched = [], 0
    if len(eng_map) != 7:
        wrong.append(f'DICOMValidator.iodNameBySOPClassUID read {len(eng_map)} rows, expected 7; update the extractor')
    for uid, (name, comment) in eng_map.items():
        row = registry.get(uid)
        if row is None:
            wrong.append(f'{uid} is not a PS3.6 Table A-1 UID (DICOMKit)')
        elif row[0].strip() != comment:
            wrong.append(f'{uid}: comment says "{comment}", PS3.6 Table A-1 says "{row[0]}" (DICOMKit)')
        else:
            matched += 1
    # both surfaces resolve --iod through DICOMValidator.iodName(forIODOption:) (D248); no Workshop map remains
    matched = engine_calls(vm, cli_sources(ctx, 'dicom-validate'), ['DICOMValidator.iodName(forIODOption:'], 'dicom-validate --iod', matched, wrong)
    for decl in ('validateEngineNameBySOPClassUID', 'func validateIODEngineName'):
        if decl in vm:
            wrong.append(f'dicom-validate --iod: the Workshop-local copy `{decl}` is back; call DICOMValidator.iodName(forIODOption:)')
        else:
            matched += 1
    rep.check('PS3.6 Table A-1: dicom-validate --iod SOP Class map (DICOMValidator.iodNameBySOPClassUID) is called by the Workshop and the CLI (D248)',
              matched, wrong)


# --- dicom-uid / dicom-dump texts ------------------------------------------------------------------------------

def check_uid_and_dump_texts(rep, parts, files, ctx):
    vm = src(files, 'CLIWorkshopViewModel.swift')
    helpers = src(files, 'CLIWorkshopHelpers.swift')
    ws_lit = literals(vm)
    wrong, matched = [], 0
    # --root: DICOMKit UIDManager.RootRule in both surfaces (D250); its texts cite PS3.5 9.1
    engine = read(ctx, 'DICOMKit/UIDManagement/UIDManager.swift')
    rule = block(engine, r'public enum RootRule \{', 'UIDManager.RootRule')
    texts = [l for l in literals(rule) if 'PS3.5 9.1' in l]
    if len(texts) < 4:
        wrong.append(f'UIDManager.RootRule carries {len(texts)} PS3.5 9.1 texts, expected 4; re-read (DICOMKit)')
    else:
        matched += 1
    matched = engine_calls(vm, cli_sources(ctx, 'dicom-uid'), ['UIDManager.RootRule.problems('], 'dicom-uid --root', matched, wrong)
    matched = no_local_copy(vm, rule, ('PS3.5 9.1',), ('func uidRootProblems',), 'dicom-uid --root', matched, wrong)
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
    rep.check('PS3.5 9.1 / PS3.6 Table A-1: dicom-uid --root through UIDManager.RootRule in both surfaces (D250); dicom-dump texts mirror the CLI',
              matched, wrong)


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
    classes the C-STORE response per PS3.4 2026a Table B.2-1 through NetworkConsole.CStoreOutcome as the CLI does,
    prints the shared sendFileWarningLine / sendSummary(warnings:) and NetworkConsole's failure texts (D261)."""
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
    # the C-STORE outcome classes and the texts are DICOMNetwork NetworkConsole's in both surfaces (D261): the
    # failure line is the Table B.2-1 C-STORE wording (status.description(for: .cStore)); no copy is left in the
    # Workshop, and since 2026-10-06 none in dicom-send either
    engine = read(ctx, 'DICOMNetwork/NetworkConsoleFormatter.swift')
    outcome = block(engine, r'public enum CStoreOutcome: Equatable, Sendable \{', 'NetworkConsole.CStoreOutcome')
    if 'status.isSuccess' in outcome and 'status.isWarning' in outcome and 'self = .failed' in outcome:
        matched += 1
    else:
        wrong.append('NetworkConsole.CStoreOutcome no longer classes Success / Warning / Failure (PS3.4 Table B.2-1); re-read (DICOMNetwork)')
    failed = block(engine, r'public static func sendStoreFailedText\(status: DIMSEStatus\) -> String \{', 'sendStoreFailedText')
    if 'status.description(for: .cStore)' not in failed or 'not stored (PS3.4 Table B.2-1)' not in failed:
        wrong.append('NetworkConsole.sendStoreFailedText must word the status per PS3.4 Table B.2-1 (description(for: .cStore)) (DICOMNetwork)')
    else:
        matched += 1
    result = block(engine, r'public static func sendFileResult\(status: DIMSEStatus, rtt: TimeInterval\) -> String \{', 'sendFileResult')
    if 'sendStoreFailedText(status: status)' not in result:
        wrong.append('NetworkConsole.sendFileResult must print sendStoreFailedText for the Failure class (DICOMNetwork)')
    else:
        matched += 1
    cli_send = cli_sources(ctx, 'dicom-send')
    matched = engine_calls(vm, cli_send, ['NetworkConsole.CStoreOutcome(status:', 'NetworkConsole.sendStoreFailedText(status:', 'NetworkConsole.sendPartialFailureText('],
                           'dicom-send C-STORE outcome', matched, wrong,
                           cli_calls=['NetworkConsole.CStoreOutcome(status:', 'NetworkConsole.sendFileResult(status:', 'NetworkConsole.sendStoreFailedText(status:',
                                      'NetworkConsole.sendPartialFailureText('])
    matched = no_local_copy(vm, failed + block(engine, r'public static func sendPartialFailureText\(succeeded: Int, failed: Int\) -> String \{', 'sendPartialFailureText'),
                            ('Table B.2-1', 'Send completed with'), ('enum WorkshopStoreOutcome', 'func sendStoreFailedText', 'func sendPartialFailureText'),
                            'dicom-send C-STORE outcome', matched, wrong, minimum=12)
    stale = [l for l in literals(cli_send) if 'not stored (PS3.4 Table B.2-1)' in l]
    if stale:
        wrong.append(f'dicom-send keeps a CLI-local failure text "{stale[0][:80]}"; it is NetworkConsole.sendStoreFailedText since D261')
    else:
        matched += 1
    send_body = block(vm, r'private func executeDicomSend\(\) async \{', 'executeDicomSend')
    for needle in ('NetworkConsole.sendFileWarningLine(status:', 'warnings: warningCount)',
                   'preferredTransferSyntaxUID: preferredTransferSyntaxUID,', 'transferSyntax: preferredTransferSyntaxUID'):
        if needle in send_body:
            matched += 1
        else:
            wrong.append(f'executeDicomSend must use `{needle}` (shared NetworkConsole / StorageService, as the CLI)')
    rep.check('PS3.7 2026a Tables 9.3-1 / 9.3-9 / 9.3-6 Priority and PS3.4 Table B.2-1: Workshop priority pickers, '
              'dicom-send outcome classes, warning tally and the NetworkConsole failure texts both surfaces call (D75 / P-SEND-SUMMARY Studio half, D261)', matched, wrong)


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
            'NetworkConsole.retrieveFinalResponse(result, service: .cMove)', 'NetworkConsole.retrieveFinalResponse(result, service: .cGet)',
            'priority: priority == .medium ? nil : priority', 'relationalRetrieval: relationalRetrieve))',
            'RetrieveExtendedNegotiation(relationalRetrieval: true)', 'Self.retrieveUIDRefusal(',
            '"(not sent — relational-retrieve)"')),
        ('executeDicomRetrieveBulk', bulk, (
            'DIMSEServiceStatusText.describe(result.status, service: .cMove)',
            'NetworkConsole.retrieveFinalResponse(result, service: .cGet)', 'RetrieveKeys.forStudy(studyUID)')),
        ('executeDicomQR', qr, ('priority: priority)', 'DICOMQueryService.buildQueryKeys(', 'Self.resolveModalityOption(',
                                '"--parallel must be at least 1"', 'Retrieval incomplete: ')),
        ('qrRetrieveStudy', qr_study, ('NetworkConsole.retrieveFinalResponse(moveResult, service: .cMove)', 'NetworkConsole.retrieveFinalResponse(finalResult, service: .cGet)')),
    ):
        for needle in needles:
            if needle in body:
                matched += 1
            else:
                wrong.append(f'{name} must contain `{needle}`')
    for stale in ('status: "\\(result.status)"', 'Resolving Study UID from server', '"INSTANCE"'):
        if stale in retrieve + bulk + qr:
            wrong.append(f'retrieve / qr executors still carry `{stale}` (raw DIMSEStatus or app-only lookup; the CLI words the status per PS3.4 Tables C.4-2 / C.4-3)')
    # the final-response report is NetworkConsole.retrieveFinalResponse in dicom-retrieve, dicom-qr and the Workshop (D262)
    engine = read(ctx, 'DICOMNetwork/NetworkConsoleFormatter.swift')
    helper_body = block(engine, r'public static func retrieveFinalResponse\([^{]*\{', 'retrieveFinalResponse')
    for needle in ('DIMSEServiceStatusText.describe(result.status, service: service)', 'DIMSEServiceStatusText.subOperationCounts(result.progress)'):
        if needle in helper_body:
            matched += 1
        else:
            wrong.append(f'NetworkConsole.retrieveFinalResponse must use `{needle}` (DICOMNetwork)')
    for tool in ('dicom-retrieve', 'dicom-qr'):
        matched = engine_calls(vm, cli_sources(ctx, tool), ['NetworkConsole.retrieveFinalResponse('], tool + ' final response', matched, wrong)
    matched = no_local_copy(vm, helper_body, ('final response', 'Failed SOP Instance UID List', 'Final '),
                            ('func retrieveCheck(', 'func qrRetrieveCheck('), 'C-MOVE / C-GET final response', matched, wrong, minimum=12)
    # CLI-local texts mirrored verbatim (a trailing newline may sit inside the literal on one side and be
    # appended by print() on the other): dicom-retrieve (RetrieveExecutor, DICOMRetrieve) and dicom-qr (DICOMQR)
    def unnl(l):
        return l[:-2] if l.endswith('\\n') else l
    ws_lit = {unnl(l) for l in literals(vm) | literals(src(files, 'CLIWorkshopHelpers.swift'))}
    for rel, keys in (('dicom-retrieve/RetrieveExecutor.swift', ('final response', 'Failed SOP Instance UID List', 'Bulk retrieval', 'Final ')),
                      ('dicom-retrieve/DICOMRetrieve.swift', ('--relational-retrieve', '--uid-list', '--parallel must', '--move-dest parameter')),
                      ('dicom-qr/DICOMQR.swift', ('Retrieval incomplete', 'Failed SOP Instance UID List', '--parallel must', '--move-dest is required', 'Invalid method'))):
        for lit in literals(read(ctx, rel)):
            if not any(k in lit for k in keys) or lit.startswith('#'):
                continue
            if unnl(lit) in ws_lit:
                matched += 1
            else:
                wrong.append(f'{rel.split("/")[0]} text not mirrored by the Workshop: "{lit[:90]}"')
    rep.check('PS3.4 2026a Tables C.4-2 / C.4-3, PS3.7 Tables 9.3-10 / 9.3-7 / 9.3-9 / 9.3-6, PS3.4 C.5.2.1: dicom-retrieve / dicom-qr '
              'Workshop status wording (NetworkConsole.retrieveFinalResponse, D262), priority, relational-retrieve and CLI texts (D76 Studio half, P-RETRIEVE-PRIORITY / -EXTNEG, P-QR-PARALLEL)',
              matched, wrong)


def check_mwl_mpps_terms(rep, parts, files, ctx):
    """dicom-mwl --sps-status offers the Scheduled Procedure Step Status (0040,0020) Defined Terms of PS3.3 2026a
    C.4.10 / Table C.4-10 and both surfaces call WorklistQueryKeys.spsStatusWarning (D264);
    --specific-character-set and --strict-modality are offered and passed through; dicom-mpps create requires
    --modality (PS3.4 Table F.7.2-1 Type 1), every CODE|DCM|MEANING example is a PS3.16 2026a CID 9301 pair
    (D85), the value rules and the SCP warning are DICOMMPPSService's in both surfaces (D263)."""
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
    # the terms and the warning are DICOMNetwork WorklistQueryKeys' in both surfaces (D264)
    engine = read(ctx, 'DICOMNetwork/ModalityWorklistService.swift')
    eng_terms = re.findall(r'"(\w+)"', block(engine, r'scheduledProcedureStepStatusDefinedTerms: \[String\] =\s*', 'engine terms'))
    if eng_terms != terms:
        wrong.append(f'WorklistQueryKeys.scheduledProcedureStepStatusDefinedTerms {eng_terms} != PS3.3 C.4.10 {terms} (DICOMNetwork)')
    else:
        matched += 1
    cli = cli_sources(ctx, 'dicom-mwl')
    matched = engine_calls(vm, cli, ['WorklistQueryKeys.spsStatusWarning('], 'dicom-mwl --sps-status', matched, wrong)
    matched = no_local_copy(vm, block(engine, r'public static func spsStatusWarning\(_ value: String\?\) -> String\? \{', 'spsStatusWarning'),
                            ('--sps-status', 'private term', 'PS3.3 Table C.4-10:'),
                            ('mwlScheduledProcedureStepStatusDefinedTerms', 'func mwlSPSStatusWarning'), 'dicom-mwl --sps-status', matched, wrong, minimum=12)
    helpers = src(files, 'CLIWorkshopHelpers.swift')
    ws_lit = literals(vm) | literals(helpers)
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
    # P-STUDIO-MWL-CREATE: the subcommand picker is exactly the CLI's commands (query: PS3.4 Annex K defines C-FIND
    # only, no DIMSE service creates a worklist item); no internal create-only fields remain in the Workshop form.
    mwl_form = ws.get('dicom-mwl', [])
    op = next((q for q in mwl_form if q.get('parameterType') == 'subcommand'), None)
    mwl_commands = [c for c in ctx['cli_surface']('dicom-mwl')[3] if c != 'dicom-mwl']   # the root command is listed too
    if mwl_commands != ['query']:
        wrong.append(f'dicom-mwl CLI commands read as {mwl_commands}; re-read (expected query only)')
    elif op is None or op.get('allowedValues') != mwl_commands or op.get('defaultValue') != 'query':
        wrong.append(f'dicom-mwl subcommand picker {op and op.get("allowedValues")} must be the CLI\'s {mwl_commands} (create is the Networking panel\'s)')
    else:
        matched += 1
    internal = [q.get('id') for q in mwl_form if q.get('isInternal') == 'true' or any('create' in v for _, v in q.get('visibility', []))]
    if internal:
        wrong.append(f'dicom-mwl Workshop form still carries internal / create-only fields {internal} (P-STUDIO-MWL-CREATE)')
    else:
        matched += 1
    mwl_body = block(vm, r'private func executeDicomMWLQuery\([^{]*\{', 'executeDicomMWLQuery')
    for needle in ('specificCharacterSet: specificCharacterSet.isEmpty ? nil : specificCharacterSet', 'WorklistQueryKeys.spsStatusWarning(spsStatus)', 'Self.resolveModalityOption('):
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
    # the value rules, texts and warning wording are DICOMNetwork DICOMMPPSService's in both surfaces (D263)
    mpps_engine = read(ctx, 'DICOMNetwork/MPPSService.swift')
    rules = mpps_engine[mpps_engine.index('extension DICOMMPPSService {'):]
    if 'DIMSEServiceStatusText.describe(status, service: operation == "N-SET" ? .mppsNSet : .dimseN)' in rules:
        matched += 1
    else:
        wrong.append('DICOMMPPSService.describeStatus must word the SCP warning through DIMSEServiceStatusText (PS3.4 Table F.7.2-2 / PS3.7 Annex C) (DICOMNetwork)')
    if 'patientSexEnumeratedValues: [String] = ["M", "F", "O"]' in rules:
        matched += 1
    else:
        wrong.append('DICOMMPPSService.patientSexEnumeratedValues must be M, F, O (PS3.3 Table C.2-3) (DICOMNetwork)')
    calls = ['DICOMMPPSService.' + c for c in ('parseStatus(', 'invalidStatusMessage', 'canonicalPatientSex(', 'patientSexErrorMessage(',
                                               'isValidBirthDate(', 'birthDateErrorMessage(', 'warningLine(')]
    matched = engine_calls(vm, cli_mpps, calls, 'dicom-mpps value rules', matched, wrong)
    matched = no_local_copy(vm, rules, ('Invalid status', '--patient-sex', '--patient-birth-date', 'attributes may have been coerced'),
                            ('func mppsStatusOption', 'func mppsPatientSex', 'func mppsBirthDate', 'func mppsWarningLine'),
                            'dicom-mpps value rules', matched, wrong, minimum=12)
    rep.check('PS3.3 2026a C.4.10 (0040,0020) Defined Terms, PS3.4 Table F.7.2-1 Type 1, PS3.16 CID 9301: dicom-mwl / dicom-mpps '
              'Workshop pickers, texts and the DICOMNetwork rules both surfaces call (D85, D263, D264)', matched, wrong)


def check_web_rules(rep, parts, files, ctx):
    """dicom-wado Workshop (qido / wado / stow / ups): the Workshop and the CLI call DICOMWeb's DICOMwebOptionRules and
    UPSState.changeStateTarget(optionValue:) (PS3.18 2026a 9.1.2.2.1, 9.5.1.2.1, 8.3.4.4, 11.7.1.4; D255, D265); the ups --state picker offers exactly
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
    # the option rules are DICOMWeb DICOMwebOptionRules / UPSState in both surfaces (D255, D259, D265); no copy remains
    engine = read(ctx, 'DICOMWeb/DICOMwebOptionRules+Values.swift')
    workitem = read(ctx, 'DICOMWeb/UPS/Workitem.swift')
    states = workitem[workitem.index('// MARK: Change Workitem State targets'):]
    if 'changeStateTargets: [UPSState] = [.inProgress, .completed, .canceled]' not in states:
        wrong.append(f'UPSState.changeStateTargets is not {legal} (PS3.18 11.7.1.4; DICOMWeb)')
    else:
        matched += 1
    cli_wado = cli_sources(ctx, 'dicom-wado')
    ws_calls = ['DICOMwebOptionRules.' + c for c in ('uriContentType(', 'uriFrameNumber(', 'uriRegion(', 'uriAnnotation(', 'uriParameterWarnings(',
                                                 'pagingProblem(', 'changeStateWorkitem(', 'updateDeprecationNote', 'timeouts(')] \
        + ['changeStateTarget(optionValue:', 'catch let e as DICOMwebOptionRefusal']
    cli_calls = ['DICOMwebOptionRules.' + c for c in ('uriContentType(', 'uriFrameNumber(', 'uriRegion(', 'uriAnnotation(', 'uriParameterWarnings(',
                                                  'validatePaging(', 'changeStateWorkitem(', 'updateDeprecationNote', 'timeouts(')] \
        + ['changeStateTarget(optionValue:']
    matched = engine_calls(vm, cli_wado, ws_calls, 'dicom-wado option rules', matched, wrong, cli_calls=cli_calls)
    matched = no_local_copy(vm, engine + states, ('PS3.18', 'Change Workitem State', 'parameter'), ('enum WorkshopWADOOptionRules', 'func upsState('),
                            'dicom-wado option rules', matched, wrong)
    for lit in literals(read(ctx, 'dicom-wado/DICOMWado.swift')):
        if any(k in lit for k in ('is required for', '--transaction-uid is required', '--label is required', '--state is required',
                                   'Invalid patient sex', 'Invalid priority', 'Invalid date format', 'Specify an operation',
                                   'must be at least 1', 'No files specified', 'must be a positive integer', 'frameNumber names a single frame')):
            if lit in literals(vm):
                matched += 1
            else:
                wrong.append(f'dicom-wado text not mirrored by the Workshop: "{lit[:90]}"')
    ups_body = block(vm, r'private func executeDicomUPS\(\) async \{', 'executeDicomUPS')
    for needle in ('WebUPSState.changeStateTarget(optionValue: stateString)', 'DICOMwebOptionRules.changeStateWorkitem(changeState: changeState, update: update)',
                   'DICOMwebOptionRules.updateDeprecationNote', 'UPSResultFormatter().format(', 'UPSConsole.updateResultText('):
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
              '(qido / wado / stow / ups) DICOMwebOptionRules calls, UPS state refusal, pickers and cliMapping flags (P-WADO-UPS-STATE / -UPDATE, P-QUERY-JSON, D255, D265)',
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
    options; the profile, Option and action-report rules are DICOMKit AnonCLI in both surfaces (D275)."""
    dk = ctx['dk']
    ws = ctx['workshop_surface']()
    helpers, vm = src(files, 'CLIWorkshopHelpers.swift'), src(files, 'CLIWorkshopViewModel.swift')
    cli_support = read(ctx, 'DICOMKit/Anonymization/AnonCLISupport.swift')   # DICOMKit AnonCLI since D275
    cli_main = read(ctx, 'dicom-anon/main.swift')
    wrong, matched = [], 0
    # AnonCLI.PS315Flags.setFlags, in order; the Workshop builds the same PS315Flags from its form ids
    set_flags = re.findall(r'\("(--[a-z-]+)",\s*\w+\)', block(cli_support, r'var setFlags: \[String\] \{', 'PS315Flags.setFlags'))
    ws_ids = re.findall(r'on\("([a-z-]+)"\)', block(vm, r'let ps315Flags = AnonCLI\.PS315Flags\(', 'Workshop AnonCLI.PS315Flags'))
    if ['--' + i for i in ws_ids] != set_flags:
        wrong.append(f'the Workshop builds AnonCLI.PS315Flags from {ws_ids}; AnonCLI.PS315Flags.setFlags is {set_flags}')
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
    # the profile / Option / action-report rules are DICOMKit AnonCLI in both surfaces (D275); no Workshop copy
    calls = ['AnonCLI.' + c for c in ('validate(', 'resolveProfile(', 'legacyProfileNotice(', 'attributeActions(', 'actionLines(',
                                      'syncingMediaStorageSOPInstanceUID(', 'PS315Flags(')]
    matched = engine_calls(vm, cli_main, calls, 'dicom-anon AnonCLI', matched, wrong)
    matched = no_local_copy(vm, cli_support, ('PS3', 'Deprecated', 'Note:', 'profile', 'not in PS3.6', 'Private Data Element', 'Attribute actions'),
                            ('enum WorkshopAnonCLI', 'optionFlagIDs', 'func optionsOnlyForPS315'), 'dicom-anon AnonCLI', matched, wrong)
    if 'PS3.15 Annex E Option flags apply only to --profile ps315: ' not in cli_support:
        wrong.append('DICOMKit AnonCLI.validate no longer says "PS3.15 Annex E Option flags apply only to --profile ps315: "; re-read')
    else:
        matched += 1
    # the two texts of the CLI-local AnonymizationError stay mirrored (WorkshopAnonError)
    ws_err = block(vm, r'enum WorkshopAnonError \{', 'WorkshopAnonError')
    for lit in literals(cli_main):
        if lit.startswith('Invalid anonymization profile') or lit == 'File not found':
            if lit in literals(ws_err):
                matched += 1
            else:
                wrong.append(f'dicom-anon AnonymizationError text not mirrored by WorkshopAnonError: "{lit}"')
    # P-STUDIO-ANON-PS315: dicom-anon's validation refusals are its own CLI-local ValidationError, which exits 1
    # (64 is only ArgumentParser's usage exit); the Workshop refuses through AnonCLI.validate with exit 1 too.
    anon_exec = block(vm, r'private func executeDicomAnon\(\) async \{', 'executeDicomAnon')
    if not re.search(r'try AnonCLI\.validate\(profile: profileStr, flags: ps315Flags.*?catch let error as AnonCLI\.ValidationError \{\s*'
                     r'refuse\(error\.message, exitCode: 1\)', anon_exec, re.S):
        wrong.append('the dicom-anon executor must refuse through AnonCLI.validate and report AnonCLI.ValidationError with exit 1, as dicom-anon does')
    else:
        matched += 1
    usage64 = [ln.strip() for ln in anon_exec.split('\n') if 'exitCode: 64' in ln and 'Missing expected argument' not in ln]
    if usage64:
        wrong.append(f'the dicom-anon executor exits 64 on a non-ArgumentParser refusal ({usage64[0][:80]}); dicom-anon\'s own refusals exit 1')
    else:
        matched += 1
    # P-STUDIO-ANON-PS315: --profile default and picker are the CLI's (DICOMKit AnonCLI.defaultProfile / profileAliases):
    # ps315 = the PS3.15 2026a E.1 Basic Application Level Confidentiality Profile (every row of Table E.1-1), basic its
    # alias, the legacy-* lists last (deprecated, not PS3.15); the old clinical-trial / research spellings not offered.
    e1 = ctx['dw'].section_by_id(parts[15], 'sect_E.1')
    e1_text = ctx['nd'].norm(' '.join(e1.itertext())) if e1 is not None else ''
    if 'Basic Application Level Confidentiality Profile' not in e1_text:
        wrong.append('PS3.15 2026a E.1 no longer names the "Basic Application Level Confidentiality Profile"; re-read')
    else:
        matched += 1
    aliases = dict(re.findall(r'"([a-z0-9-]+)":\s*\.(\w+)', block(cli_support, r'public static let profileAliases: \[String: Profile\] = ', 'AnonCLI.profileAliases')))
    default = (re.search(r'public static let defaultProfile = "([^"]+)"', cli_support) or [None, None])[1]
    expected = [default] + [k for k, v in aliases.items() if v == 'ps315' and k != default] + \
               [k for k, v in aliases.items() if v != 'ps315' and k.startswith('legacy-')]
    prof = param(ws, 'dicom-anon', 'profile')
    if default != 'ps315' or aliases.get('basic') != 'ps315':
        wrong.append(f'DICOMKit AnonCLI.defaultProfile is {default!r}, basic -> {aliases.get("basic")!r}; the CLI default must be ps315 with basic its alias')
    elif prof is None or prof.get('defaultValue') != default or prof.get('allowedValues') != expected:
        wrong.append(f'dicom-anon --profile: Workshop default {prof and prof.get("defaultValue")!r} / picker {prof and prof.get("allowedValues")} '
                     f'must be the CLI default {default!r} / {expected} (ps315 first, legacy-* last)')
    else:
        matched += len(expected) + 1
        help_text = str(prof.get('helpText', ''))
        if 'PS3.15 Basic Application Level Confidentiality Profile' not in help_text or 'Table E.1-1' not in help_text \
                or 'not PS3.15' not in help_text:
            wrong.append('dicom-anon --profile help must name the PS3.15 Basic Application Level Confidentiality Profile (Table E.1-1) and label legacy-* not PS3.15')
        else:
            matched += 1
    # ps315 / basic run DICOMKit Anonymizer.deidentify — the CLI's isPS315 branch — through StudioAnonPS315 (no copy)
    ps315_support = read(ctx, 'DICOMStudio/Components/AnonPS315Support.swift')
    deid = block_or_empty(ps315_support, r'static func deidentify\([^{]*\{', 'StudioAnonPS315.deidentify')
    checks = [
        (re.search(r'if isPS315 \{\s*\(anonymizedFile, result\) = try StudioAnonPS315\.deidentify\(', anon_exec),
         'the dicom-anon executor\'s isPS315 branch must call StudioAnonPS315.deidentify'),
        ('let isPS315 = resolvedProfile.isPS315' in anon_exec and 'AnonCLI.resolveProfile(profileStr)' in anon_exec,
         'the dicom-anon executor must resolve --profile through AnonCLI.resolveProfile / Profile.isPS315'),
        ('anonymizer.deidentify(file: dicomFile, options: options)' in deid,
         'StudioAnonPS315.deidentify must call DICOMKit Anonymizer.deidentify(file:options:)'),
        ('anonymizer.deidentify(file: dicomFile, options: ps315Options)' in cli_main,
         'dicom-anon\'s ps315 branch no longer calls Anonymizer.deidentify(file:options:); re-read'),
        ('AnonCLI.applyCustomActions(' in deid and '!allowBurnedInPHI' in deid,
         'StudioAnonPS315.deidentify must refuse burned-in PHI unless allowed and apply --remove / --replace as the CLI does'),
        ('Tag(group:' not in ps315_support and 'Tag.' not in deid,
         'StudioAnonPS315 must not carry a Table E.1-1 copy (the rows are DICOMKit Anonymizer.deidentify\'s)'),
    ]
    for ok_, msg in checks:
        if ok_:
            matched += 1
        else:
            wrong.append(msg)
    rep.check(f'PS3.15 2026a Annex E (E.1 Basic Profile, Table E.1-1 {len(columns)} Option columns, E.3.1-E.3.11), PS3.16 CID 7050: dicom-anon Workshop '
              f'--profile ps315 default and picker, E.3 option flags, pixel-cleaning options, CLI help, refusals exit 1, and the DICOMKit '
              f'AnonCLI / Anonymizer.deidentify calls (P-ANON-RETAIN-DATES, D275, P-STUDIO-ANON-PS315)',
              matched, wrong)


def check_pixel_conversion_type(rep, parts, files, ctx):
    """PS3.3 2026a Table C.8-24 Conversion Type (0008,0064) Defined Terms: DICOMKit ConversionType.definedTerms, the
    engine list of dicom-pdf and the Workshop (EncapsulatedDocumentBuilder.conversionTypeDefinedTerms, D272) and the
    dicom-image / dicom-pdf Workshop pickers."""
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
    builder = read(ctx, 'DICOMKit/EncapsulatedDocument/EncapsulatedDocumentBuilder.swift')
    pdf_rules = read(ctx, 'DICOMKit/EncapsulatedDocument/EncapsulatedDocumentBuilder+OptionRules.swift')
    terms = re.findall(r'"(\w+)"', re.search(r'static let conversionTypeDefinedTerms = \[([^\]]*)\]', builder).group(1))
    if terms != std:
        wrong.append(f'EncapsulatedDocumentBuilder.conversionTypeDefinedTerms {terms} != Table C.8-24 {std} (DICOMKit)')
    elif 'conversionTypes = EncapsulatedDocumentBuilder.conversionTypeDefinedTerms' not in pdf_rules:
        wrong.append('EncapsulatedDocumentBuilder.OptionRules.conversionTypes must be conversionTypeDefinedTerms (DICOMKit)')
    else:
        matched += 2
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
    pdf_values = re.findall(r'"(\w+)"', re.search(r'static let burnedInAnnotationValues = \[([^\]]*)\]', pdf_rules).group(1))
    if bia is None or bia.get('allowedValues') != [''] + pdf_values:
        wrong.append(f'dicom-pdf --burned-in-annotation picker must be [""] + {pdf_values} (PS3.3 Table C.24-2)')
    else:
        matched += len(pdf_values)
    rep.check('PS3.3 2026a Table C.8-24 (8 Conversion Type Defined Terms) / Table C.24-2: dicom-image and dicom-pdf Workshop '
              '--conversion-type / --burned-in-annotation pickers, DICOMKit ConversionType.definedTerms and EncapsulatedDocumentBuilder.OptionRules (D272)',
              matched, wrong)


def check_pixel_cid3000_audio(rep, parts, files, ctx):
    """PS3.16 2026a CID 3000 Audio Channel Source and PS3.3 A.32.x / Table C.7-1: dicom-video and the Workshop call
    DICOMKit AudioChannelSourceOption and VideoOptionConformance (D269); the CID rows and the refusal rules match."""
    dk = ctx['dk']
    ws = ctx['workshop_surface']()
    helpers, vm = src(files, 'CLIWorkshopHelpers.swift'), src(files, 'CLIWorkshopViewModel.swift')
    audio = read(ctx, 'DICOMKit/Video/AudioChannelSourceOption.swift')
    conf = read(ctx, 'DICOMKit/Video/VideoOptionConformance.swift')
    wrong, matched = [], 0
    pat = r'\("([a-z-]+)",\s*VideoAudioChannel\.Source\(dcmCodeValue:\s*"(\d+)",\s*codeMeaning:\s*"([^"]+)"\)\)'
    rows = re.findall(pat, audio)
    cid = [(v, m) for s_, v, m in dk.cid_rows(parts[16], 'CID 3000') if s_ == 'DCM']
    if [(v, m) for _, v, m in rows] != cid:
        wrong.append(f'AudioChannelSourceOption.keywords CID rows {[(v, m) for _, v, m in rows]} != PS3.16 CID 3000 {cid} (DICOMKit)')
    else:
        matched += len(cid)
    for kw, _, meaning in rows:
        if kw != re.sub(r"[^a-z0-9]+", '-', meaning.lower().replace("'", '')).strip('-'):
            wrong.append(f'keyword {kw} is not the hyphenated Code Meaning "{meaning}" (DICOMKit)')
        else:
            matched += 1
    for mod, sect in (('ES', 'A.32.5.4.1'), ('GM', 'A.32.6.4.1'), ('XC', 'A.32.7.4.1')):
        s = ctx['dw'].section_by_id(parts[3], 'sect_' + sect)
        t = ctx['nd'].norm(' '.join(s.itertext())) if s is not None else ''
        if f'shall be {mod}' not in t:
            wrong.append(f'PS3.3 {sect}: "shall be {mod}" not found; re-read')
        elif f'return ("{mod}", "{sect}")' not in conf:
            wrong.append(f'VideoOptionConformance.requiredModality lacks ("{mod}", "{sect}") (DICOMKit)')
        else:
            matched += 1
    sex = ctx['dw'].section_by_id(parts[3], 'sect_C.7.1.1')
    sex_text = ctx['nd'].norm(' '.join(sex.itertext())) if sex is not None else ''
    sex_values = re.findall(r'\b([MFO]) (?:male|female|other)\b', sex_text.partition("Patient's Sex")[2].partition('See Note')[0])
    if sex_values[:3] != ['M', 'F', 'O'] or 'static let patientSexValues = ["M", "F", "O"]' not in conf:
        wrong.append(f'Patient\'s Sex Enumerated Values (PS3.3 C.7.1.1 / Table C.7-1): standard {sex_values[:3]}, VideoOptionConformance.patientSexValues must be ["M", "F", "O"] (DICOMKit)')
    else:
        matched += 3
    for pid, expr in (('modality', 'VideoOptionConformance.modalityHelp'), ('patientSex', 'VideoOptionConformance.patientSexHelp'),
                      ('patientBirthDate', 'VideoOptionConformance.patientBirthDateHelp'), ('transferSyntax', 'VideoOptionConformance.transferSyntaxHelp')):
        p = param(ws, 'dicom-video', pid)
        if p is None or not str(p.get('helpText', '')).startswith(expr):
            wrong.append(f'dicom-video {pid} help must be the CLI\'s {expr} (states the refusal)')
        else:
            matched += 1
    p = param(ws, 'dicom-video', 'audioChannelSource')
    if p is None or not str(p.get('helpText', '')).startswith('AudioChannelSourceOption.help'):
        wrong.append('dicom-video --audio-channel-source help must be AudioChannelSourceOption.help (DICOMKit, D56)')
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
    if 'metadata.audioChannelSources = sources' in vm:
        matched += 1
    else:
        wrong.append('dicom-video executor does not set metadata.audioChannelSources')
    matched = engine_calls(vm + helpers, cli_sources(ctx, 'dicom-video'),
                           ['VideoOptionConformance.violations(', 'AudioChannelSourceOption.parse', 'AudioChannelSourceOption.help',
                            'VideoOptionConformance.modalityHelp', 'VideoOptionConformance.transferSyntaxHelp'],
                           'dicom-video option conformance', matched, wrong)
    matched = no_local_copy(vm + helpers, audio + conf, ('CID 3000', '--audio-channel-source', 'refused', 'A.32'),
                            ('enum WorkshopVideoOptionConformance', 'enum WorkshopAudioChannelSourceOption'), 'dicom-video option conformance', matched, wrong)
    rep.check(f'PS3.16 2026a CID 3000 ({len(cid)} rows), PS3.3 A.32.5.4.1 / A.32.6.4.1 / A.32.7.4.1, C.7.1.1 Patient\'s Sex: dicom-video Workshop '
              '--audio-channel-source (D56) and the P-VIDEO-* refusals are DICOMKit AudioChannelSourceOption / VideoOptionConformance in both surfaces (D269)',
              matched, wrong)


def check_pixel_compress_syntax(rep, parts, files, ctx):
    """PS3.6 2026a Table A-1 / PS3.5 A.1, A.2, A.3, A.5: dicom-compress decompress / batch --syntax picker is DICOMKit
    CompressionConsole.NativeTargetSyntax (explicit-le, implicit-le, deflate, explicit-be), which the CLI and the
    Workshop both resolve through (D267)."""
    dw = ctx['dw']
    ws = ctx['workshop_surface']()
    helpers, vm = src(files, 'CLIWorkshopHelpers.swift'), src(files, 'CLIWorkshopViewModel.swift')
    engine = block(read(ctx, 'DICOMKit/Compression/CompressionConsole.swift'), r'public enum NativeTargetSyntax \{', 'NativeTargetSyntax')
    core = read(ctx, 'DICOMCore/TransferSyntax.swift')
    wrong, matched = [], 0
    accepted = re.findall(r'\("([a-z-]+)",\s*\.(\w+)\)', engine)
    if len(accepted) != 4:
        wrong.append(f'CompressionConsole.NativeTargetSyntax.accepted read {accepted}; update the extractor')
    registry = dw.uid_registry(parts[6])
    for name, const in accepted:
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
        if p is None or p.get('allowedValues') != 'CompressionConsole.NativeTargetSyntax.accepted.map(\\.name)' or p.get('defaultValue') != 'explicit-le':
            wrong.append('dicom-compress --syntax picker must be CompressionConsole.NativeTargetSyntax.accepted.map(\\.name) with default explicit-le')
        else:
            matched += 1
        cli_h = cli_help(ctx, 'dicom-compress', '--syntax')
        if p is not None and cli_h and p.get('helpText') not in cli_h:
            wrong.append(f'dicom-compress --syntax help {p.get("helpText")!r} is neither subcommand\'s CLI help')
        else:
            matched += 1
    if vm.count('CompressionConsole.NativeTargetSyntax.resolve(syntax)') < 2:
        wrong.append('decompress and batch executors must resolve --syntax through CompressionConsole.NativeTargetSyntax.resolve')
    else:
        matched += 2
    matched = engine_calls(vm, cli_sources(ctx, 'dicom-compress'), ['NativeTargetSyntax.resolve('], 'dicom-compress --syntax', matched, wrong)
    matched = no_local_copy(vm + helpers, engine, ('syntax', 'PS3', 'Native targets'), ('enum WorkshopNativeTargetSyntax',),
                            'dicom-compress --syntax', matched, wrong)
    if 'CompressionConsole.infoJSON(info, filePath: displayPath)' not in vm:
        wrong.append('info --json must render through the shared CompressionConsole.infoJSON (P-COMPRESS-JSON)')
    else:
        matched += 1
    rep.check(f'PS3.6 2026a Table A-1 / PS3.5 A.1, A.2, A.3, A.5: dicom-compress Workshop decompress / batch --syntax picker is the '
              f'{len(accepted)} native targets of CompressionConsole.NativeTargetSyntax, which both surfaces resolve through '
              f'(P-COMPRESS-SYNTAX, D267); info --json shared (P-COMPRESS-JSON)', matched, wrong)


def check_pixel_convert_tokens(rep, parts, files, ctx):
    """PS3.6 2026a Table A-1 keywords / PS3.3 Table 10-3: the dicom-convert Workshop --transfer-syntax picker is
    DICOMConverter.cliTokens, the Table A-1 keywords and the composed help are DICOMConverter's in both surfaces
    (additionalTableA1Keywords / resolveTargetEncoding / transferSyntaxOptionHelpWithKeywords, D268) and are Table A-1
    rows, frames are selected by Frame number from 1 with --frame deprecated."""
    dw = ctx['dw']
    ws = ctx['workshop_surface']()
    helpers, vm = src(files, 'CLIWorkshopHelpers.swift'), src(files, 'CLIWorkshopViewModel.swift')
    kit = read(ctx, 'DICOMKit/DICOMConverter.swift')
    wrong, matched = [], 0
    added = re.findall(r'"(\w+)":\s*"([\d.]+)"', block(kit, r'static let additionalTableA1Keywords: \[String: String\] = \[', 'additionalTableA1Keywords'))
    if not added:
        wrong.append('DICOMConverter.additionalTableA1Keywords not found; update the extractor')
    registry = dw.uid_registry(parts[6])
    for keyword, uid in added:
        row = registry.get(uid)
        if row is None or row[1].strip() != keyword:
            wrong.append(f'{keyword} -> {uid}: PS3.6 Table A-1 keyword of that UID is {row and row[1]!r} (DICOMKit)')
        else:
            matched += 1
    p = param(ws, 'dicom-convert', 'transfer-syntax')
    if p is None or 'allowedValues: [""] + DICOMConverter.cliTokens' not in raw_definition(helpers, 'transfer-syntax', '--transfer-syntax') \
            or p.get('helpText') != 'DICOMConverter.transferSyntaxOptionHelpWithKeywords':
        wrong.append('dicom-convert --transfer-syntax picker must be [""] + DICOMConverter.cliTokens with DICOMConverter.transferSyntaxOptionHelpWithKeywords')
    else:
        matched += 1
    help_body = block(kit, r'public static var transferSyntaxOptionHelpWithKeywords: String \{', 'transferSyntaxOptionHelpWithKeywords')
    matched = engine_calls(vm + helpers, cli_sources(ctx, 'dicom-convert'),
                           ['DICOMConverter.resolveTargetEncoding(', 'DICOMConverter.transferSyntaxOptionHelpWithKeywords'],
                           'dicom-convert --transfer-syntax', matched, wrong)
    matched = no_local_copy(vm + helpers, help_body, ('Table A-1', 'Changed', 'Reversible'), ('enum WorkshopTransferSyntaxKeywords',),
                            'dicom-convert --transfer-syntax', matched, wrong)
    # the three reassigned keywords are Table A-1 rows of their UIDs, and the Reversible spellings are catalog tokens
    core = read(ctx, 'DICOMCore/TransferSyntax.swift')
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
    for needle in ('TransferSyntax.reassignedKeywordNote(for: transferSyntax)', 'ConvertError.invalidFrameNumber(number, pixelData.descriptor.numberOfFrames)',
                   'DICOMConverter.invalidFrameNumberMessage(requested: requested, total: total)', 'cannot be used together',
                   'WorkshopConvertPicker.canonicalToken(value)', 'DICOMConverter.resolveTargetEncoding(name)'):
        if needle in vm:
            matched += 1
        else:
            wrong.append(f'dicom-convert executor lacks {needle}')
    rep.check(f'PS3.6 2026a Table A-1 ({len(added)} added keywords + 3 reassigned), PS3.3 Table 10-3: dicom-convert Workshop --transfer-syntax tokens '
              '(DICOMConverter.cliTokens, P-CONVERT-TS-KEYWORDS; keywords and help DICOMConverter\'s in both surfaces, D268), '
              '--frame-number / deprecated --frame (P-CONVERT-FRAME)', matched, wrong)


def check_pixel_rules_mirrors(rep, parts, files, ctx):
    """The dicom-image, dicom-pdf and dicom-pixedit rules lifted into DICOMKit (ImageConverter.OutputRules, D274;
    EncapsulatedDocumentBuilder.OptionRules, D272; PixelEditInputChecks, D270) are called by the CLI and the Workshop,
    with no Workshop copy left (PS3.5 Table 6.2-1 / 9.1, PS3.3 Tables C.24-2 / C.12-1 / C.7.6.3.1 / C.11.2.1.2)."""
    vm = src(files, 'CLIWorkshopViewModel.swift')
    ws = ctx['workshop_surface']()
    wrong, matched = [], 0
    for tool, engine_path, calls, cli_calls, keep, forbidden, label in (
            ('dicom-image', 'DICOMKit/SecondaryCapture/ImageConverter+OutputRules.swift',
             ['ImageConverter.OutputRules.conversionType(', 'ImageConverter.OutputRules.valueViolations(', 'ImageConverter.OutputRules.finalize(data)'],
             ['ImageConverter.OutputRules.conversionType(', 'ImageConverter.OutputRules.valueViolations(', 'ImageConverter.OutputRules.finalize('],
             ('PS3', 'ISO_IR'), ('enum WorkshopSCOutput',), 'dicom-image ImageConverter.OutputRules (D274)'),
            ('dicom-pdf', 'DICOMKit/EncapsulatedDocument/EncapsulatedDocumentBuilder+OptionRules.swift',
             ['EncapsulatedDocumentBuilder.OptionRules.conversionType(', 'EncapsulatedDocumentBuilder.OptionRules.burnedInAnnotation(',
              'EncapsulatedDocumentBuilder.OptionRules.hl7InstanceIdentifier(', 'EncapsulatedDocumentBuilder.OptionRules.complete(&dataSet, documentByteCount: documentData.count)',
              'EncapsulatedDocumentBuilder.OptionRules.documentBytes(document.documentData, in: dicomFile.dataSet)'],
             ['EncapsulatedDocumentBuilder.OptionRules.conversionType(', 'EncapsulatedDocumentBuilder.OptionRules.burnedInAnnotation(',
              'EncapsulatedDocumentBuilder.OptionRules.hl7InstanceIdentifier(', 'EncapsulatedDocumentBuilder.OptionRules.complete(',
              'EncapsulatedDocumentBuilder.OptionRules.documentBytes('],
             ('PS3', 'ISO_IR', 'WSD'), ('enum WorkshopPDFEncapsulation', 'class WorkshopClinicalDocumentIDFinder'), 'dicom-pdf EncapsulatedDocumentBuilder.OptionRules (D272)'),
            ('dicom-pixedit', 'DICOMKit/PixelEditing/PixelEditInputChecks.swift',
             ['PixelEditInputChecks.fillValueViolation(', 'PixelEditInputChecks.storedRange(of:', 'PixelEditInputChecks.windowWidthViolation(width)'],
             ['PixelEditInputChecks.fillValueViolation(', 'PixelEditInputChecks.storedRange(', 'PixelEditInputChecks.windowWidthViolation('],
             ('PS3',), ('enum WorkshopDerivedImage',), 'dicom-pixedit PixelEditInputChecks (D270)')):
        engine = read(ctx, engine_path)
        matched = engine_calls(vm, cli_sources(ctx, tool), calls, label, matched, wrong, cli_calls=cli_calls)
        matched = no_local_copy(vm, engine, keep, forbidden, label, matched, wrong)
    # the engine texts cite the clauses the refusals rest on
    rules = read(ctx, 'DICOMKit/SecondaryCapture/ImageConverter+OutputRules.swift') + read(ctx, 'DICOMKit/PixelEditing/PixelEditInputChecks.swift')
    for cite in ('PS3.5 Table 6.2-1', 'PS3.5 9.1', 'PS3.3 C.7.6.3.1', 'PS3.3 C.11.2.1.2'):
        if cite in rules:
            matched += 1
        else:
            wrong.append(f'the image / pixedit engine rules no longer cite {cite}; re-read (DICOMKit)')
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
    if 'PixelEditDerivation(descriptionPrefix: "dicom-pixedit")' in vm:
        matched += 1
    else:
        wrong.append('executor lacks PixelEditDerivation(descriptionPrefix: "dicom-pixedit")')
    rep.check('PS3.5 2026a Table 6.2-1 / 9.1, PS3.3 Tables C.24-2 / C.12-1 / C.7.6.3.1 / C.11.2.1.2: dicom-image, dicom-pdf and dicom-pixedit '
              'Workshop and CLI call ImageConverter.OutputRules / EncapsulatedDocumentBuilder.OptionRules / PixelEditInputChecks '
              '(P-IMAGE-VR, P-PIXEDIT-RANGE, D182, D270, D272, D274)', matched, wrong)



def check_directory_run_exits(rep, parts, files, ctx):
    """P-CONVERT-EXIT siblings (2026-10-06): dicom-export bulk (D251), dicom-image's directory run (D273) and both
    dicom-pdf directory runs (D271) exit 1 after the summary when a file failed, and the Workshop returns the same
    status; dicom-pdf --extract skips a file without Encapsulated Document (0042,0011) (PS3.3 2026a C.24.2) in both
    surfaces, with the same verbose line."""
    dw, nd = ctx['dw'], ctx['nd']
    vm = src(files, 'CLIWorkshopViewModel.swift')
    wrong, matched = [], 0
    sec = dw.section_by_id(parts[3], 'sect_C.24.2')
    t = nd.norm(' '.join(sec.itertext())) if sec is not None else ''
    if 'Encapsulated Document (0042,0011)' not in t:
        wrong.append('PS3.3 C.24.2: Encapsulated Document (0042,0011) not found in the module; re-read')
    else:
        matched += 1
    export_cli = read(ctx, 'dicom-export/main.swift')
    image_cli = read(ctx, 'dicom-image/main.swift')
    pdf_cli = read(ctx, 'dicom-pdf/main.swift')
    for label, cli, cli_needles, ws_body, ws_needles in (
            ('dicom-export bulk (D251)', export_cli, ['if errorCount > 0 {\n                throw ExitCode.failure'],
             block(vm, r'private func executeDicomExport\(\) async \{', 'executeDicomExport'), ['return (log, errorCount > 0 ? 1 : 0)']),
            ('dicom-image directory run (D273)', image_cli, ['if failureCount > 0 {\n            throw ExitCode.failure'],
             block(vm, r'private func executeDicomImage\(\) async \{', 'executeDicomImage'), ['return (out, failureCount > 0 ? 1 : 0)']),
            ('dicom-pdf directory runs (D271)', pdf_cli, ['if failureCount > 0 {\n            throw ExitCode.failure'],
             block(vm, r'private func executeDicomPdf\(\) async \{', 'executeDicomPdf'),
             ['let failed = extractMode ? try extractFromDirectory(inputURL) : try encapsulateFromDirectory(inputURL)',
              'return (log, failed > 0 ? 1 : 0)'])):
        for needle in cli_needles:
            n = cli.count(needle)
            want = 2 if label.startswith('dicom-pdf') else 1
            if n < want:
                wrong.append(f'{label}: the CLI no longer exits 1 after the summary ({n} of {want}); re-read the CLI')
            else:
                matched += 1
        for needle in ws_needles:
            if needle in ws_body:
                matched += 1
            else:
                wrong.append(f'{label}: the Workshop does not return the CLI\'s status (`{needle}`)')
    # dicom-pdf --extract over a directory: the skip rule and its verbose line are the CLI's
    extract_ws = block(vm, r'func extractFromDirectory\(_ dir: URL\) throws -> Int \{', 'Workshop extractFromDirectory')
    extract_cli = block(pdf_cli, r'private func extractFromDirectory\(inputPath: String, outputPath: String\?\) throws \{', 'dicom-pdf extractFromDirectory')
    for label, body in (('the CLI', extract_cli), ('the Workshop', extract_ws)):
        if 'dicomFile.dataSet[.encapsulatedDocument] != nil' in body and 'continue' in body:
            matched += 1
        else:
            wrong.append(f'dicom-pdf --extract (D271): {label} must skip a file without Encapsulated Document (0042,0011)')
    cli_line = literals(block(pdf_cli, r'static func skippedLine\(fileName: String\) -> String \{', 'DICOMPdf.skippedLine'))
    ws_line = literals(block(vm, r'nonisolated static func pdfSkippedLine\(fileName: String\) -> String \{', 'pdfSkippedLine'))
    if not cli_line or cli_line != ws_line:
        wrong.append(f'dicom-pdf skip line differs: CLI {sorted(cli_line)}, Workshop {sorted(ws_line)}')
    else:
        matched += 1
    rep.check('P-CONVERT-EXIT siblings, PS3.3 2026a C.24.2: the Workshop\'s dicom-export bulk, dicom-image and dicom-pdf directory runs exit 1 '
              'after the summary as the CLIs do; dicom-pdf --extract skips non-documents in both surfaces (D251, D271, D273)', matched, wrong)


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
    ('G1 workshop directory run exits', check_directory_run_exits),
]
