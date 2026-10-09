#!/usr/bin/env python3
"""Diff every generated SR template row in DICOMCore against the PS3.16 DocBook.

Usage:
    python3 Scripts/diff_sr_templates.py part16.xml [TID ...]

Reads the TemplateRow literals of SRCoreTemplates.swift, SRMeasurementTemplates.swift and
SRCADTemplates.swift as Swift source text (not through the generator), extracts each TID
table with Scripts/nema_docbook.py, and compares, row by row: row number, nesting level,
relationship (with the by-reference "R-" flag), value type or INCLUDE and the included TID,
the Concept Name cell and the parsed concept constraint, VM, requirement type, condition and
the Value Set Constraint cell (and, where that cell is only codes, the parsed value
constraint). Exits 1 on any difference. With TIDs given, checks only those.

This is the check for D50 (TID 4000 and TID 4100 added, 2026-09-30); it also covers the 40
templates generated for P10.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from nema_docbook import Part  # noqa: E402

SR = os.path.join(HERE, '..', 'Sources', 'DICOMCore', 'StructuredReporting')
FILES = ['SRCoreTemplates.swift', 'SRMeasurementTemplates.swift', 'SRCADTemplates.swift']

RELATIONSHIPS = {
    '.contains': 'CONTAINS', '.hasProperties': 'HAS PROPERTIES', '.hasObsContext': 'HAS OBS CONTEXT',
    '.hasAcqContext': 'HAS ACQ CONTEXT', '.hasConceptMod': 'HAS CONCEPT MOD',
    '.inferredFrom': 'INFERRED FROM', '.selectedFrom': 'SELECTED FROM', 'nil': '',
}
REQUIREMENTS = {'.mandatory': 'M', '.mandatoryConditional': 'MC', '.userOption': 'U',
                '.userOptionConditional': 'UC'}
SWIFT_STRING = r'"((?:[^"\\]|\\.)*)"'


def unescape(s):
    return re.sub(r'\\(.)', lambda m: '\n' if m.group(1) == 'n' else m.group(1), s)


def field(chunk, name, pattern=SWIFT_STRING):
    m = re.search(r'\n\s*' + name + r': ' + pattern, chunk)
    return m.group(1) if m else None


def text_field(chunk, name):
    v = field(chunk, name)
    return unescape(v) if v is not None else ''


def identifiers():
    """TemplateIdentifier constant name -> TID, from SRTemplate.swift."""
    src = open(os.path.join(SR, 'SRTemplate.swift')).read()
    return dict(re.findall(r'public static let (\w+) = TemplateIdentifier\(tid: (\d+)\)', src))


def swift_templates():
    templates = {}
    for name in FILES:
        path = os.path.join(SR, name)
        if not os.path.exists(path):
            continue
        src = open(path).read()
        for m in re.finditer(r'public struct (\w+): SRTemplate \{(.*?)\n\}\n', src, re.S):
            body = m.group(2)
            ident = re.search(r'identifier = TemplateIdentifier\.(\w+)', body).group(1)
            rows = body.split('TemplateRow(')[1:]
            templates[ident] = (m.group(1), rows)
    return templates


def normalise(s):
    """The generator's cell text: paragraphs joined by newlines, xrefs with quoted titles,
    olinks as "Title (PS3.x label)". nema_docbook joins paragraphs with " | " and prints
    bare labels; bring both to that form."""
    s = s.replace('\n', ' | ')
    s = re.sub(r'((?:[DB]?CID|[DB]?TID|CID|TID) \w+) "[^"]*"', r'\1', s)
    return re.sub(r'\s+', ' ', s).strip()


def same_text(swift, docbook):
    """Equal, except that an olink nema_docbook prints as "PS3.3 sect_C.7.5.1" is written by
    the generator (given part03) as the section title followed by "(PS3.3 C.7.5.1)"."""
    if swift == docbook:
        return True
    if 'sect_' not in docbook:
        return False
    pieces = re.split(r'(PS3\.\d+) sect_([\w.]*\w)', docbook)
    pattern = ''
    for i in range(0, len(pieces), 3):
        pattern += re.escape(pieces[i])
        if i + 2 < len(pieces):
            pattern += r'.*?\(' + re.escape(pieces[i + 1] + ' ' + pieces[i + 2]) + r'\)'
    return re.fullmatch(pattern, swift) is not None


CODE = r'\(([^,()]+), ([^,()]+), "(.*?)"\)'


def expected_concept(cell):
    """The Swift ConceptNameConstraint a Concept Name cell stands for, as a comparable tuple."""
    if not cell:
        return ('any',)
    m = re.fullmatch(r'(EV|DT) ' + CODE, cell)
    if m:
        return ('exact' if m.group(1) == 'EV' else 'definedTerm', m.group(2), m.group(3))
    m = re.match(r'([DB])CID (\d+)', cell)
    if m:
        return ('fromContextGroup' if m.group(1) == 'D' else 'fromBaselineContextGroup', m.group(2))
    m = re.fullmatch(r'\$(\w+)', cell)
    if m:
        return ('parameter', m.group(1))
    return ('any',)


def swift_concept(chunk):
    m = re.search(r'\n\s*conceptName: \.(\w+)(.*)', chunk)
    if not m:
        return None
    case, rest = m.group(1), m.group(2)
    if case in ('exact', 'definedTerm'):
        c = re.search(r'codeValue: ' + SWIFT_STRING + r', codingSchemeDesignator: ' + SWIFT_STRING, rest)
        return (case, unescape(c.group(1)), unescape(c.group(2)))
    if case in ('fromContextGroup', 'fromBaselineContextGroup'):
        return (case, re.search(r'contextGroupID: (\d+)', rest).group(1))
    if case == 'parameter':
        return (case, unescape(re.search(SWIFT_STRING, rest).group(1)))
    return (case,)


def main():
    part = Part(sys.argv[1])
    only = set(sys.argv[2:])
    ids = identifiers()
    templates = swift_templates()
    problems, checked_rows, checked_templates = [], 0, 0
    for ident, (struct, rows) in sorted(templates.items(), key=lambda kv: int(ids[kv[0]])):
        tid = ids[ident]
        if only and tid not in only:
            continue
        # A TID with a Parameters table shares its label; the template table is the last one
        matches = [t for label, _, t in part.tables() if label == f'TID {tid}']
        table = matches[-1]
        doc = [r for r in part.rows(table)]
        checked_templates += 1
        if len(doc) != len(rows):
            problems.append(f'TID {tid}: {len(rows)} rows in Swift, {len(doc)} in PS3.16')
        for chunk, cells in zip(rows, doc):
            cells = cells + [''] * (9 - len(cells))
            if len(cells) == 9:
                row_id, nl, rel, vt, concept, vm, req, cond, vs = cells
            else:
                problems.append(f'TID {tid}: unexpected column count {len(cells)}')
                continue
            checked_rows += 1
            where = f'TID {tid} row {row_id}'

            def check(what, swift, docbook):
                if swift != docbook:
                    problems.append(f'{where} {what}: Swift {swift!r} ≠ PS3.16 {docbook!r}')

            check('row', text_field(chunk, 'rowID'), row_id)
            check('NL', int(field(chunk, 'nestingLevel', r'(\d+)')), len(nl))
            by_ref = field(chunk, 'isByReference', r'(true)') == 'true'
            doc_rel = re.sub(r'^R-\s*', '', rel)
            check('relationship', (RELATIONSHIPS[field(chunk, 'relationshipType', r'([.\w]+)')], by_ref),
                  (doc_rel, rel.startswith('R-')))
            vt_swift = field(chunk, 'valueType', r'([.\w]+)')
            if vt_swift == 'nil':
                check('VT', 'INCLUDE', vt)
                included = field(chunk, 'includedTemplate', r'\.(\w+)')
                m = re.fullmatch(r'[DB]TID (\w+)', concept)
                check('included TID', ids.get(included), m.group(1) if m else concept)
            else:
                check('VT', vt_swift.lstrip('.').upper().replace('SCOORD3D', 'SCOORD3D'), vt)
                check('concept constraint', swift_concept(chunk), expected_concept(concept))
            check('concept text', normalise(text_field(chunk, 'conceptNameText')), normalise(concept))
            vm_min = field(chunk, 'valueMultiplicity', r'Cardinality\(minimum: (\d+)')
            vm_max = re.search(r'valueMultiplicity: Cardinality\(minimum: \d+, maximum: (\w+)\)', chunk).group(1)
            check('VM', vm_min + ('-n' if vm_max == 'nil' else ('' if vm_max == vm_min else '-' + vm_max)), vm)
            check('requirement', REQUIREMENTS[field(chunk, 'requirementLevel', r'([.\w]+)')], req)
            cond_swift = re.search(r'condition: \.custom\(description: ' + SWIFT_STRING + r'\)', chunk)
            cond_text = normalise(unescape(cond_swift.group(1)) if cond_swift else '')
            if not same_text(cond_text, normalise(cond)):
                check('condition', cond_text, normalise(cond))
            # A Value Set cell made only of codes ("EV (…)", "DT (…)", "UNITS = EV (…)", one per
            # paragraph) is parsed into the constraint: the same codes, all of them
            paras = [p for p in vs.split(' | ') if p]
            if paras and vt != 'INCLUDE' and all(re.fullmatch(r'(?:UNITS = )?(?:EV |DT )?' + CODE, p) for p in paras):
                constraint = re.search(r'\n\s*valueConstraint: (.*)', chunk).group(1)
                swift_codes = re.findall(r'codeValue: ' + SWIFT_STRING + r', codingSchemeDesignator: ' + SWIFT_STRING,
                                         constraint)
                doc_codes = [re.search(CODE, p).group(1, 2) for p in paras]
                check('value constraint codes', [tuple(map(unescape, c)) for c in swift_codes], doc_codes)
                check('value constraint units', constraint.startswith('.units('), paras[0].startswith('UNITS = '))
            vs_text = normalise(text_field(chunk, 'valueSetText'))
            if not same_text(vs_text, normalise(vs)):
                check('value set', vs_text, normalise(vs))
    for p in problems:
        print(p)
    print(f'{part.subtitle}: {checked_templates} templates, {checked_rows} rows compared, '
          f'{len(problems)} differences', file=sys.stderr)
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
