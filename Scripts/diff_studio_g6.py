#!/usr/bin/env python3
"""DICOMStudio group G6 (Print: PS3.3 C.13, PS3.4 Annex H) row-by-row checks.

Loaded by diff_studio.py (``diff_studio_g6*.py`` glob); exports ``CHECKS = [(name, fn(rep, parts, files, ctx))]``.
DICOMStudio's print screens carry almost no print terms of their own — the pickers enumerate DICOMNetwork's enums
through DICOMPrintKit's PrintOptionCatalog (both verified in their own passes). What Studio does carry is diffed here:

  * PrintSCPView.attributeRows labels "(gggg,eeee)"     vs PS3.6 Table 6-1 attribute names
  * tags read by PrintImageNumberCache / ImageViewerViewModel+Print   vs PS3.6 Table 6-1
  * PrintViewModel density defaults, FilmPreviewView density literals  vs PS3.3 C.13.3 Border / Empty Image Density terms
  * PrintViewModel custom Image Display Format default   vs PS3.3 C.13.3 (STANDARD\\C,R | ROW\\… | COL\\…)
  * PrintSettingsView FilmDestinationPicker              vs PS3.3 C.13.1 Film Destination (MAGAZINE, PROCESSOR, BIN_i,
                                                           no maximum) — the catalogue stops at BIN_2
  * the Execution Status words of the Print SCP help      vs PS3.3 C.13.8 Enumerated Values
  * DICOMPrintKit EmulatedPrinterStatus (shown by the Print SCP pane)   vs PS3.3 C.13.9 Printer Status / Table C.13.9.1-1
  * PrinterStatusPresentation covers DICOMNetwork.PrinterStatusSeverity vs the C.13.9 Enumerated Values
  * the Bits Stored 8/12 help cites Table C.13-5          vs PS3.3 C.13.5 (Bits Stored Enumerated Values 8, 12)
"""
import os
import re

PENDING_API_APPROVAL = {}
DEFERRED = {}
EXEMPT = {}


def src(files, suffix):
    for name, s in files.items():
        if name.endswith(suffix):
            return s
    raise KeyError(suffix)


def varlists(nd, dw, part, xml_id):
    D = nd.D
    sec = dw.section_by_id(part, xml_id)
    out = []
    for vl in sec.iter(D + 'variablelist'):
        title = vl.find(D + 'title')
        terms = [nd.norm(''.join(e.find(D + 'term').itertext())).strip() for e in vl.findall(D + 'varlistentry')]
        out.append((nd.norm(''.join(title.itertext())).strip() if title is not None else '', terms))
    return out


def c13_lists(nd, dw, p3):
    s1 = varlists(nd, dw, p3, 'sect_C.13.1')
    s3 = varlists(nd, dw, p3, 'sect_C.13.3')
    s8 = varlists(nd, dw, p3, 'sect_C.13.8')
    s9 = varlists(nd, dw, p3, 'sect_C.13.9')
    out = {'Film Destination': s1[2][1], 'Image Display Format': s3[0][1], 'Border Density': s3[4][1],
           'Empty Image Density': s3[5][1], 'Trim': s3[6][1], 'Execution Status': s8[0][1], 'Printer Status': s9[0][1]}
    assert 'BIN_i' in out['Film Destination'] and 'BLACK' in out['Border Density'] and 'DONE' in out['Execution Status']
    assert out['Printer Status'] == ['NORMAL', 'WARNING', 'FAILURE']
    return out


# --- PS3.6 Table 6-1: attribute labels and tag reads ------------------------------------------------------

def check_attribute_labels(rep, parts, files, ctx):
    dw = ctx['dw']
    d = dw.dictionary(parts[6])
    s = src(files, 'PrintSCPView.swift')
    body = dw.func_body(s, r'static func attributeRows\(_ info: ComposedFilmInfo\)')
    rows = re.findall(r'\("([^"(]+?)\s*\((\w{4}),(\w{4})\)"', body)
    wrong, matched = [], 0
    for label, g, e in rows:
        std = d.get((g + e).upper())
        if not std:
            wrong.append(f'({g},{e}) is not in Table 6-1')
        elif dw.norm_name(label) == dw.norm_name(std[0]):
            matched += 1
        else:
            wrong.append(f'label "{label}" for ({g},{e}) — Table 6-1 name is "{std[0]}"')
    rep.check(f'PS3.6 Table 6-1: PrintSCPView.attributeRows — {len(rows)} labels with a tag are the attribute name of that tag',
              matched, wrong)


def check_tag_reads(rep, parts, files, ctx):
    dw = ctx['dw']
    d = dw.dictionary(parts[6])
    wrong, matched = [], 0
    for suffix in ('PrintImageNumberCache.swift', 'ImageViewerViewModel+Print.swift'):
        s = src(files, suffix) if any(n.endswith(suffix) for n in files) else \
            ctx['studio_files']()[next(n for n in ctx['studio_files']() if n.endswith(suffix))]
        for g, e in re.findall(r'Tag\(group:\s*0x(\w{4}),\s*element:\s*0x(\w{4})\)', s):
            std = d.get((g + e).upper())
            if not std:
                wrong.append(f'{suffix}: ({g},{e}) is not in Table 6-1')
            elif std[0].replace("'", '').lower() not in s.replace("'", '').lower():
                wrong.append(f'{suffix}: ({g},{e}) read without naming it ("{std[0]}")')
            else:
                matched += 1
        for kw in re.findall(r'string\(for:\s*\.(\w+)\)', s):
            hits = [v for v in d.values() if v[1].replace('​', '') == kw[0].upper() + kw[1:]]
            if hits:
                matched += 1
            else:
                wrong.append(f'{suffix}: .{kw} is not a Table 6-1 keyword')
    rep.check('PS3.6 Table 6-1: the tags the print tray reads (Instance Number, Series Description, Modality) exist and are named',
              matched, wrong)


# --- PS3.3 C.13.3: densities and the custom Image Display Format ---------------------------------------------

def check_densities_and_format(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    lists = c13_lists(nd, dw, parts[3])
    vm = src(files, 'PrintViewModel.swift')
    wrong, matched = [], 0
    for prop, key in (('borderDensity', 'Border Density'), ('emptyImageDensity', 'Empty Image Density')):
        for val in re.findall(prop + r'(?::\s*String)?\s*=\s*"([^"]+)"', vm):
            if val in lists[key] or re.fullmatch(r'\d+', val):
                matched += 1
            else:
                wrong.append(f'PrintViewModel.{prop} = "{val}" is not a C.13.3 {key} term (BLACK, WHITE, or i hundredths of OD)')
    preview = src(files, 'FilmPreviewView.swift')
    for val in re.findall(r'case "([A-Z]+)": return \.(?:black|white)', preview):
        if val in lists['Border Density']:
            matched += 1
        else:
            wrong.append(f'FilmPreviewView draws "{val}", not a C.13.3 density term')
    fmt = re.compile(r'^(STANDARD\\\d+,\d+|ROW\\\d+(,\d+)*|COL\\\d+(,\d+)*|SLIDE|SUPERSLIDE|CUSTOM\\\d+)$')
    assert any(t.startswith('ROW\\R1,R2') for t in lists['Image Display Format'])
    for val in re.findall(r'customLayoutText(?::\s*String)?\s*=\s*"((?:[^"\\]|\\.)*)"', vm):
        if fmt.match(val.replace('\\\\', '\\')):
            matched += 1
        else:
            wrong.append(f'PrintViewModel.customLayoutText default "{val}" is not a C.13.3 Image Display Format')
    rep.check('PS3.3 C.13.3: print-sheet density defaults / preview greys are Border Density terms; the custom layout default is an '
              'Image Display Format form', matched, wrong)


# --- PS3.3 C.13.1: the film destination picker ------------------------------------------------------------------

def check_film_destination_picker(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    std = c13_lists(nd, dw, parts[3])['Film Destination']
    s = src(files, 'PrintSettingsView.swift')
    body = dw.enum_body(s, 'FilmDestinationPicker')
    net = dw.read(os.path.join(ctx['sources'], 'DICOMNetwork', 'PrintService.swift'))
    cat = dw.read(os.path.join(ctx['sources'], 'DICOMPrintKit', 'PrintOptionCatalog.swift'))
    wrong, matched, extra = [], 0, []
    if not body:
        wrong.append('PrintSettingsView has no FilmDestinationPicker')
    else:
        if 'PrintOptionCatalog.filmDestinations' in body and 'binNumber == nil' in body:
            matched += 1   # named terms come from the catalogue (MAGAZINE, PROCESSOR)
        else:
            wrong.append('FilmDestinationPicker does not take the named terms from PrintOptionCatalog.filmDestinations')
        if re.search(r'\.bin\(min\(max\(1, number\), FilmDestination\.maximumBinNumber\)\)', body):
            matched += 1   # BIN_i for any i >= 1, within the CS length
        else:
            wrong.append('FilmDestinationPicker.bin does not hold the number to 1...FilmDestination.maximumBinNumber')
    # DICOMNetwork spells the terms as C.13.1 does; the catalogue stops at BIN_2 (so the picker's open bin number is needed)
    m = re.search(r'public struct FilmDestination\b', net)
    fd = net[m.start():m.start() + 4000] if m else ''
    for term in ('MAGAZINE', 'PROCESSOR'):
        if re.search(r'FilmDestination\(term: "' + term + '"\)', fd):
            matched += 1
        else:
            wrong.append(f'DICOMNetwork.FilmDestination lacks "{term}"')
    if 'FilmDestination(term: "BIN_\\(number)")' in fd and 'BIN_i' in std:
        matched += 1
    else:
        wrong.append('DICOMNetwork.FilmDestination.bin does not write BIN_<number>')
    bins = re.findall(r'\.bin\((\d+)\)', dw.func_body(cat, r'static let filmDestinations') or cat)
    extra.append(f'PrintOptionCatalog.filmDestinations offers BIN_{"/".join(bins)} only; Studio\'s picker adds a bin-number field')
    rep.check('PS3.3 C.13.1 Table C.13-1 Film Destination (MAGAZINE, PROCESSOR, BIN_i with no maximum): PrintSettingsView offers any bin',
              matched, wrong, extra=extra)


# --- PS3.3 C.13.8 / C.13.9: status words ------------------------------------------------------------------------

def check_status_terms(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    lists = c13_lists(nd, dw, parts[3])
    info_terms = {row[0].strip() for row in dw.table_rows(parts[3], 'C.13.9.1-1') if row}
    wrong, matched = [], 0
    scp = src(files, 'PrintSCPView.swift')
    for m in re.finditer(r'N-EVENT-REPORT ([A-Z]+(?: → [A-Z]+)+)', scp):
        for word in m.group(1).split(' → '):
            if word in lists['Execution Status']:
                matched += 1
            else:
                wrong.append(f'PrintSCPView help names "{word}", not a C.13.8 Execution Status value')
    # DICOMPrintKit's emulated status, as the pane shows and pushes it
    pk = dw.read(os.path.join(ctx['sources'], 'DICOMPrintKit', 'Printing', 'PrintSCPSettings.swift'))
    ours = dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', dw.enum_body(pk, 'EmulatedPrinterStatus')))
    for c, v in ours.items():
        if v in lists['Printer Status']:
            matched += 1
        else:
            wrong.append(f'EmulatedPrinterStatus.{c} = "{v}" is not a C.13.9 Printer Status value (DICOMPrintKit)')
    missing = [f'Printer Status "{t}" not emulated' for t in lists['Printer Status'] if t not in ours.values()]
    infos = re.findall(r'case \.\w+:\s*return "([^"]+)"', dw.func_body(pk, r'var defaultStatusInfo: String'))
    for v in infos:
        if v in info_terms or v == 'NORMAL':
            matched += 1
        else:
            wrong.append(f'EmulatedPrinterStatus.defaultStatusInfo "{v}" is not a Table C.13.9.1-1 term (DICOMPrintKit)')
    # Studio's severity presentation covers the three values (plus unknown)
    pres = src(files, 'PrinterStatusPresentation.swift')
    sev = dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', dw.enum_body(dw.read(os.path.join(ctx['sources'], 'DICOMNetwork', 'PrintService.swift')), 'PrinterStatusSeverity')))
    for c, v in sev.items():
        if v in lists['Printer Status'] or v == 'UNKNOWN':
            if f'case .{c}:' in pres:
                matched += 1
            else:
                wrong.append(f'PrinterStatusPresentation has no colour/symbol for PrinterStatusSeverity.{c}')
        else:
            wrong.append(f'DICOMNetwork.PrinterStatusSeverity.{c} = "{v}" is not a C.13.9 value')
    rep.check('PS3.3 C.13.8 / C.13.9 / Table C.13.9.1-1: Execution Status words in the Print SCP help, the emulated Printer Status and '
              'Status Info, and the severity presentation', matched, wrong, missing)


# --- PS3.3 C.13.5: the Bits Stored help ----------------------------------------------------------------------------

def check_bits_stored_help(rep, parts, files, ctx):
    dw, nd = ctx['dw'], ctx['nd']
    lists = varlists(nd, dw, parts[3], 'sect_C.13.5')
    bits = next((terms for title, terms in lists if terms == ['8', '12']), None)
    s = src(files, 'PrintSettingsView.swift')
    m = re.search(r'help\("PS3\.3 Table (C\.13-\d) allows Bits Stored of (\d+) or (\d+)', s)
    wrong, matched = [], 0
    if not m:
        wrong.append('PrintSettingsView no longer carries the Bits Stored help; update the extractor')
    else:
        if m.group(1) == 'C.13-5' and bits and [m.group(2), m.group(3)] == bits:
            matched += 1
        else:
            wrong.append(f'Bits Stored help cites Table {m.group(1)} with {m.group(2)}/{m.group(3)}; C.13.5 lists {bits} in Table C.13-5')
    rep.check('PS3.3 C.13.5 Table C.13-5: the Bits Stored 8/12 help cites the Image Box Pixel Presentation Module', matched, wrong)


CHECKS = [
    ('G6 print attribute labels', check_attribute_labels),
    ('G6 print tag reads', check_tag_reads),
    ('G6 print densities and format', check_densities_and_format),
    ('G6 print film destination picker', check_film_destination_picker),
    ('G6 print status terms', check_status_terms),
    ('G6 print bits stored help', check_bits_stored_help),
]
