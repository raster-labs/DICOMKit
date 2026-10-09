#!/usr/bin/env python3
"""Generate the DICOMCore SR template definitions from the PS3.16 DocBook TID tables.

Usage:
    python3 Scripts/generate_sr_templates.py part16.xml [part03.xml]

part16.xml is the DocBook source of PS3.16 for the target edition, e.g.
https://dicom.nema.org/medical/dicom/2026a/source/docbook/part16/part16.xml
part03.xml (optional) resolves the PS3.3 section titles quoted in "Defaults to"
value-set text.

Writes Sources/DICOMCore/StructuredReporting/SRCoreTemplates.swift,
SRMeasurementTemplates.swift and SRCADTemplates.swift. The template set is ROOTS below plus every template
they INCLUDE, transitively. Every row keeps its Concept Name and Value Set
Constraint text verbatim next to the parsed constraints, so a row can always be
compared with the standard.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

D = '{http://docbook.org/ns/docbook}'
X = '{http://www.w3.org/XML/1998/namespace}'

# The templates DICOMCore models, before INCLUDE expansion.
ROOTS = ['300', '1001', '1002', '1204', '1400', '1410', '1411', '1419', '1420',
         '1500', '1501', '1600', '1601', '4000', '4100']

# Swift names. Types and TemplateIdentifier constants that existed before the
# rebuild keep their names; the rest follow the PS3.16 title.
NAMES = {
    '300': ('TID300Measurement', 'measurement'),
    '301': ('TID301MeasurementContent', 'measurementContent'),
    '310': ('TID310MeasurementProperties', 'measurementProperties'),
    '311': ('TID311MeasurementStatisticalProperties', 'measurementStatisticalProperties'),
    '312': ('TID312NormalRangeProperties', 'normalRangeProperties'),
    '315': ('TID315EquationOrTable', 'equationOrTable'),
    '320': ('TID320ImageOrSpatialCoordinates', 'imageOrSpatialCoordinates'),
    '321': ('TID321WaveformOrTemporalCoordinates', 'waveformOrTemporalCoordinates'),
    '1000': ('TID1000Quotation', 'quotation'),
    '1001': ('TID1001ObservationContext', 'observationContext'),
    '1002': ('TID1002ObserverContext', 'observerContext'),
    '1003': ('TID1003PersonObserverIdentifyingAttributes', 'personObserverIdentifyingAttributes'),
    '1004': ('TID1004DeviceObserverIdentifyingAttributes', 'deviceObserverIdentifyingAttributes'),
    '1005': ('TID1005ProcedureStudyContext', 'procedureStudyContext'),
    '1006': ('TID1006SubjectContext', 'subjectContext'),
    '1007': ('TID1007SubjectContextPatient', 'subjectContextPatient'),
    '1008': ('TID1008SubjectContextFetus', 'subjectContextFetus'),
    '1009': ('TID1009SubjectContextSpecimen', 'subjectContextSpecimen'),
    '1010': ('TID1010SubjectContextDevice', 'subjectContextDevice'),
    '1015': ('TID1015PersonObserverDescription', 'personObserverDescription'),
    '1204': ('TID1204LanguageOfContent', 'languageOfContent'),
    '1400': ('TID1400LinearMeasurements', 'linearMeasurements'),
    '1410': ('TID1410PlanarROIMeasurements', 'planarROIMeasurements'),
    '1411': ('TID1411VolumetricROIMeasurements', 'volumetricROIMeasurements'),
    '1419': ('TID1419ROIMeasurements', 'roiMeasurements'),
    '1420': ('TID1420MultipleROIMeasurements', 'multipleROIMeasurements'),
    '1500': ('TID1500MeasurementReport', 'measurementReport'),
    '1501': ('TID1501MeasurementGroup', 'measurementGroup'),
    '1502': ('TID1502TimePointContext', 'timePointContext'),
    '1600': ('TID1600ImageLibrary', 'imageLibrary'),
    '1601': ('TID1601ImageLibraryEntry', 'imageLibraryEntry'),
    '1602': ('TID1602ImageLibraryEntryDescriptors', 'imageLibraryEntryDescriptors'),
    '1603': ('TID1603ImageLibraryEntryDescriptorsForProjectionRadiography',
             'imageLibraryEntryDescriptorsForProjectionRadiography'),
    '1604': ('TID1604ImageLibraryEntryDescriptorsForCrossSectionalModalities',
             'imageLibraryEntryDescriptorsForCrossSectionalModalities'),
    '1605': ('TID1605ImageLibraryEntryDescriptorsForCT', 'imageLibraryEntryDescriptorsForCT'),
    '1606': ('TID1606ImageLibraryEntryDescriptorsForMR', 'imageLibraryEntryDescriptorsForMR'),
    '1607': ('TID1607ImageLibraryEntryDescriptorsForPET', 'imageLibraryEntryDescriptorsForPET'),
    '1608': ('TID1608ImageLibraryEntryDescriptorsForProstateMultiparametricMR',
             'imageLibraryEntryDescriptorsForProstateMultiparametricMR'),
    '4019': ('TID4019AlgorithmIdentification', 'algorithmIdentification'),
    '4108': ('TID4108TrackingIdentifier', 'trackingIdentifier'),
    # Added with TID 4000 and TID 4100 (D50, 2026-09-30)
    '1401': ('TID1401AreaMeasurement', 'areaMeasurement'),
    '1402': ('TID1402VolumeMeasurement', 'volumeMeasurement'),
    '4000': ('TID4000MammographyCADDocumentRoot', 'mammographyCADDocumentRoot'),
    '4001': ('TID4001MammographyCADOverallImpressionRecommendation',
             'mammographyCADOverallImpressionRecommendation'),
    '4002': ('TID4002MammographyCADImpressionRecommendationBody',
             'mammographyCADImpressionRecommendationBody'),
    '4003': ('TID4003MammographyCADIndividualImpressionRecommendation',
             'mammographyCADIndividualImpressionRecommendation'),
    '4004': ('TID4004MammographyCADCompositeFeature', 'mammographyCADCompositeFeature'),
    '4005': ('TID4005MammographyCADCompositeFeatureBody', 'mammographyCADCompositeFeatureBody'),
    '4006': ('TID4006MammographyCADSingleImageFinding', 'mammographyCADSingleImageFinding'),
    '4007': ('TID4007MammographyCADBreastComposition', 'mammographyCADBreastComposition'),
    '4008': ('TID4008MammographyCADBreastGeometry', 'mammographyCADBreastGeometry'),
    '4009': ('TID4009MammographyCADIndividualCalcification', 'mammographyCADIndividualCalcification'),
    '4010': ('TID4010MammographyCADCalcificationCluster', 'mammographyCADCalcificationCluster'),
    '4011': ('TID4011MammographyCADDensity', 'mammographyCADDensity'),
    '4012': ('TID4012MammographyCADNonLesion', 'mammographyCADNonLesion'),
    '4013': ('TID4013MammographyCADSelectedRegion', 'mammographyCADSelectedRegion'),
    '4014': ('TID4014CADImageQuality', 'cadImageQuality'),
    '4015': ('TID4015CADDetectionsPerformed', 'cadDetectionsPerformed'),
    '4016': ('TID4016CADAnalysesPerformed', 'cadAnalysesPerformed'),
    '4017': ('TID4017CADDetectionPerformed', 'cadDetectionPerformed'),
    '4018': ('TID4018CADAnalysisPerformed', 'cadAnalysisPerformed'),
    '4020': ('TID4020CADImageLibraryEntry', 'cadImageLibraryEntry'),
    '4021': ('TID4021MammographyCADGeometry', 'mammographyCADGeometry'),
    '4022': ('TID4022CADObservationContext', 'cadObservationContext'),
    '4023': ('TID4023CADOperatingPoints', 'cadOperatingPoints'),
    '4100': ('TID4100ChestCADDocumentRoot', 'chestCADDocumentRoot'),
    '4101': ('TID4101ChestCADFindingsSummary', 'chestCADFindingsSummary'),
    '4102': ('TID4102ChestCADCompositeFeature', 'chestCADCompositeFeature'),
    '4103': ('TID4103ChestCADCompositeFeatureBody', 'chestCADCompositeFeatureBody'),
    '4104': ('TID4104ChestCADSingleImageFinding', 'chestCADSingleImageFinding'),
    '4105': ('TID4105ChestCADDescriptors', 'chestCADDescriptors'),
    '4106': ('TID4106ResponseEvaluation', 'responseEvaluation'),
    '4107': ('TID4107ChestCADGeometry', 'chestCADGeometry'),
}

MEASUREMENT_FILE_TIDS = {'1400', '1401', '1402', '1410', '1411', '1419', '1420', '1500', '1501',
                         '1502', '1600', '1601', '1602', '1603', '1604', '1605', '1606', '1607',
                         '1608'}
# TID 4019 and 4108 stay in the core file, where they were before the CAD roots were added.
CAD_FILE_TIDS = {t for t in NAMES if t.startswith(('40', '41')) and t not in ('4019', '4108')}

# The date each file's rows were last generated and compared with PS3.16 2026a.
CHECKED = {'Core': '2026-09-30', 'Measurement': '2026-09-30', 'CAD': '2026-09-30'}

RELATIONSHIPS = {
    'CONTAINS': '.contains', 'HAS PROPERTIES': '.hasProperties',
    'HAS OBS CONTEXT': '.hasObsContext', 'HAS ACQ CONTEXT': '.hasAcqContext',
    'HAS CONCEPT MOD': '.hasConceptMod', 'INFERRED FROM': '.inferredFrom',
    'SELECTED FROM': '.selectedFrom',
}
VALUE_TYPES = {
    'TEXT': '.text', 'CODE': '.code', 'NUM': '.num', 'DATE': '.date', 'TIME': '.time',
    'DATETIME': '.datetime', 'PNAME': '.pname', 'UIDREF': '.uidref',
    'COMPOSITE': '.composite', 'IMAGE': '.image', 'WAVEFORM': '.waveform',
    'SCOORD': '.scoord', 'SCOORD3D': '.scoord3D', 'TCOORD': '.tcoord',
    'CONTAINER': '.container', 'TABLE': '.table',
}
REQUIREMENTS = {'M': '.mandatory', 'MC': '.mandatoryConditional', 'U': '.userOption',
                'UC': '.userOptionConditional'}
VM = {'1': ('1', '1'), '2': ('2', '2'), '1-n': ('1', 'nil'), '2-n': ('2', 'nil')}

CODE = r'\(([^,()]+), ([^,()]+), "(.*?)"\)'


def load(path):
    root = ET.parse(path).getroot()
    labels, titles = {}, {}
    for e in root.iter():
        i = e.get(X + 'id')
        if i and e.get('label'):
            labels[i] = e.get('label')
            t = e.find(D + 'title')
            if t is None:
                t = e.find(D + 'caption')
            if t is not None:
                titles[i] = norm(''.join(t.itertext()))
    sub = root.find('.//' + D + 'subtitle')
    return root, labels, titles, norm(''.join(sub.itertext()))


def norm(s):
    return re.sub(r'\s+', ' ', s.replace('\u200b', '')).strip()


def main():
    p16 = sys.argv[1]
    root, labels, titles, edition = load(p16)
    ext_titles = {}
    if len(sys.argv) > 2:
        _, l3, t3, _ = load(sys.argv[2])
        ext_titles = {k: (l3.get(k), v) for k, v in t3.items()}

    def text(e):
        def walk(n, out, top):
            if n.tag == D + 'xref':
                le = n.get('linkend')
                out.append(labels.get(le, le))
                if 'quotedtitle' in (n.get('xrefstyle') or '') and le in titles:
                    out.append(' "' + titles[le] + '"')
            elif n.tag == D + 'olink':
                ptr = n.get('targetptr')
                label, title = ext_titles.get(ptr, (None, None))
                doc = n.get('targetdoc') or ''
                out.append(f'{title} ({doc} {label})' if title else f'{doc} {ptr}')
            else:
                if n.text:
                    out.append(n.text)
                for c in n:
                    walk(c, out, False)
            if n.tail and not top:
                out.append(n.tail)
        paras = e.findall(D + 'para')
        parts = []
        for p in (paras or [e]):
            out = []
            walk(p, out, True)
            s = norm(''.join(out))
            if s:
                parts.append(s)
        return '\n'.join(parts)

    tids = {}
    for s in root.iter(D + 'section'):
        m = re.fullmatch(r'TID (\w+)', s.get('label') or '')
        if not m:
            continue
        info = {'title': titles.get(s.get(X + 'id'), ''), 'meta': {}, 'params': [], 'rows': None}
        intro = s.find(D + 'para')
        info['intro'] = text(intro) if intro is not None else ''
        for ve in s.iter(D + 'varlistentry'):
            k = text(ve.find(D + 'term')).rstrip(':').lower()
            info['meta'][k] = text(ve.find(D + 'listitem'))
        for t in s.findall(D + 'table'):
            head = [text(th) for th in t.iter(D + 'th')]
            body = [[text(td) for td in tr.findall(D + 'td')]
                    for tb in t.findall(D + 'tbody') for tr in tb.findall(D + 'tr')]
            if head and head[0].startswith('Parameter'):
                info['params'] = body
            elif 'NL' in head and info['rows'] is None:
                # Root templates of some SOP Classes have no relationship column.
                cols = ['NL', 'Rel with Parent', 'VT', 'Concept Name', 'VM', 'Req Type',
                        'Condition', 'Value Set Constraint']
                index = [head.index(c) if c in head else None for c in cols]
                info['rows'] = [[r[0]] + [r[i] if i is not None else '' for i in index]
                                for r in body]
        tids[m.group(1)] = info

    selected, todo = set(), list(ROOTS)
    while todo:
        t = todo.pop()
        if t in selected:
            continue
        selected.add(t)
        for r in tids[t]['rows']:
            if r[3] == 'INCLUDE':
                todo += re.findall(r'TID (\w+)', r[4])
    missing = selected - NAMES.keys()
    assert not missing, f'add Swift names for {sorted(missing)}'

    def root_vt(t):
        r = tids[t]['rows'][0]
        if r[3] == 'INCLUDE':
            return root_vt(re.search(r'TID (\w+)', r[4]).group(1))
        return VALUE_TYPES[r[3]]

    core = [t for t in selected if t not in MEASUREMENT_FILE_TIDS and t not in CAD_FILE_TIDS]
    meas = [t for t in selected if t in MEASUREMENT_FILE_TIDS]
    cad = [t for t in selected if t in CAD_FILE_TIDS]
    key = lambda t: int(t)
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(here, '..', 'Sources', 'DICOMCore', 'StructuredReporting')
    write(os.path.join(out_dir, 'SRCoreTemplates.swift'), 'Core', sorted(core, key=key),
          tids, edition, root_vt)
    write(os.path.join(out_dir, 'SRMeasurementTemplates.swift'), 'Measurement',
          sorted(meas, key=key), tids, edition, root_vt)
    write(os.path.join(out_dir, 'SRCADTemplates.swift'), 'CAD',
          sorted(cad, key=key), tids, edition, root_vt)
    print(f'{edition}: {len(selected)} templates, '
          f'{sum(len(tids[t]["rows"]) for t in selected)} rows', file=sys.stderr)


def swift_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def code_literal(value, scheme, meaning):
    return (f'CodedConcept(codeValue: {swift_str(value)}, codingSchemeDesignator: '
            f'{swift_str(scheme)}, codeMeaning: {swift_str(meaning)})')


def concept_constraint(s):
    if not s:
        return '.any'
    m = re.fullmatch(r'(EV|DT) ' + CODE, s)
    if m:
        case = 'exact' if m.group(1) == 'EV' else 'definedTerm'
        return f'.{case}({code_literal(*m.group(2, 3, 4))})'
    m = re.match(r'([DB])CID (\d+)', s)
    if m:
        case = 'fromContextGroup' if m.group(1) == 'D' else 'fromBaselineContextGroup'
        return f'.{case}(contextGroupID: {m.group(2)})'
    m = re.fullmatch(r'\$(\w+)', s)
    if m:
        return f'.parameter({swift_str(m.group(1))})'
    if re.fullmatch(r'The value of Row \w+', s):
        # TID 4023 rows 8-9: the concept is another item's value; kept verbatim in conceptNameText
        return '.any'
    raise ValueError(f'unparsed concept name: {s!r}')


def value_constraint(s):
    first = s.split('\n')[0] if s else ''
    if not first:
        return '.any'
    # One code per paragraph, e.g. TID 1000 row 1 "EV (121003, …) | EV (121004, …)" or TID 4020
    # rows 11-12 "UNITS = EV (um, …) | UNITS = EV (mm, …)": any of them (D50/D55)
    paras = [p for p in s.split('\n') if p]
    if len(paras) > 1:
        codes = [re.fullmatch(r'(UNITS = )?(?:EV )?' + CODE, p) for p in paras]
        if all(codes) and len({bool(c.group(1)) for c in codes}) == 1:
            inner = '.oneOfCodes([' + ', '.join(code_literal(*c.group(2, 3, 4)) for c in codes) + '])'
            return f'.units({inner})' if codes[0].group(1) else inner
    m = re.fullmatch(r'UNITS = (.+)', first)
    if m:
        inner = value_constraint(m.group(1))
        return f'.units({inner})' if not inner.startswith('.custom') else f'.custom(description: {swift_str(s)})'
    m = re.fullmatch(r'(?:(EV|DT) )?' + CODE, first)
    if m:
        case = 'definedTermCode' if m.group(1) == 'DT' else 'exactCode'
        return f'.{case}({code_literal(*m.group(2, 3, 4))})'
    m = re.fullmatch(r'([DB])CID (\d+) "[^"]*"', first)
    if m:
        case = 'fromContextGroup' if m.group(1) == 'D' else 'fromBaselineContextGroup'
        return f'.{case}(contextGroupID: {m.group(2)})'
    m = re.fullmatch(r'\$(\w+)', first)
    if m:
        return f'.parameter({swift_str(m.group(1))})'
    return f'.custom(description: {swift_str(s)})'


def parameter_value(s):
    m = re.fullmatch(r'\$(\w+)', s)
    if m:
        return f'.parameter({swift_str(m.group(1))})'
    m = re.fullmatch(r'(EV|DT) ' + CODE, s)
    if m:
        case = 'code' if m.group(1) == 'EV' else 'definedTerm'
        return f'.{case}({code_literal(*m.group(2, 3, 4))})'
    m = re.fullmatch(r'([DB])CID (\d+) "[^"]*"', s)
    if m:
        case = 'contextGroup' if m.group(1) == 'D' else 'baselineContextGroup'
        return f'.{case}({m.group(2)})'
    return f'.text({swift_str(s)})'


def row_literal(r, tid):
    row_id, nl, rel, vt, concept, vm, req, cond, vs = r
    level = len(nl)
    by_ref = rel.startswith('R-')
    # TID 1401 and 1402 write "R- INFERRED FROM" with a space after the prefix
    rel = rel[2:].strip() if by_ref else rel
    args = [f'rowID: {swift_str(row_id)}', f'nestingLevel: {level}',
            f'relationshipType: {RELATIONSHIPS[rel] if rel else "nil"}']
    if by_ref:
        args.append('isByReference: true')
    vm_min, vm_max = VM[vm]
    card_min = vm_min if req == 'M' else '0'
    include = []
    if vt == 'INCLUDE':
        m = re.fullmatch(r'([DB])TID (\w+) "[^"]*"', concept)
        assert m, (tid, row_id, concept)
        args.append('valueType: nil')
        include.append(f'includedTemplate: .{NAMES[m.group(2)][1]}')
        bindings = []
        for line in filter(None, vs.split('\n')):
            b = re.fullmatch(r'\$(\w+) = (.+)', line)
            if not b:
                continue  # prose such as "Defaults to ..."; kept in valueSetText
            bindings.append(f'TemplateParameterBinding(name: {swift_str(b.group(1))}, '
                            f'value: {parameter_value(b.group(2))}, text: {swift_str(b.group(2))})')
        if bindings:
            include.append('includeParameters: [\n                ' +
                           ',\n                '.join(bindings) + '\n            ]')
    else:
        args.append(f'valueType: {VALUE_TYPES[vt]}')
        args.append(f'conceptName: {concept_constraint(concept)}')
        args.append(f'valueConstraint: {value_constraint(vs)}')
    args.append(f'requirementLevel: {REQUIREMENTS[req]}')
    args.append(f'valueMultiplicity: Cardinality(minimum: {vm_min}, maximum: {vm_max})')
    args.append(f'cardinality: Cardinality(minimum: {card_min}, maximum: {vm_max})')
    if cond:
        args.append(f'condition: .custom(description: {swift_str(cond)})')
    args += include
    if concept:
        args.append(f'conceptNameText: {swift_str(concept)}')
    if vs:
        args.append(f'valueSetText: {swift_str(vs)}')
    return 'TemplateRow(\n            ' + ',\n            '.join(args) + '\n        )'


def write(path, kind, order, tids, edition, root_vt):
    tid_list = ', '.join(order)
    lines = [
        f'/// DICOM SR {kind} Templates',
        '///',
        f'/// GENERATED by Scripts/generate_sr_templates.py from {edition}.',
        '/// Do not edit by hand; change the generator and re-run it.',
        '///',
        f'/// Templates: TID {tid_list}.',
        '///',
        f'/// NEMA-verified: 2026a, checked {CHECKED[kind]} — every row of every template in this',
        '/// file is generated from its PS3.16 2026a TID table (row ID, nesting level,',
        '/// relationship, value type, concept name, VM, requirement type, condition and',
        '/// value set constraint), with INCLUDE rows and parameter bindings kept. The',
        '/// Concept Name and Value Set Constraint cells are kept verbatim in',
        '/// `conceptNameText` and `valueSetText`.',
        '',
        'import Foundation',
        '',
    ]
    for t in order:
        info = tids[t]
        struct, const = NAMES[t]
        meta = info['meta']
        extensible = meta.get('type', 'Extensible') == 'Extensible'
        order_sig = meta.get('order', 'Significant') == 'Significant'
        is_root = meta.get('root', 'No') == 'Yes'
        lines.append(f'// MARK: - TID {t}: {info["title"]}')
        lines.append('')
        lines.append(f'/// TID {t} — {info["title"]}')
        lines.append('///')
        for para in info['intro'].split('\n'):
            lines.append(f'/// {para}')
        lines.append('///')
        lines.append(f'/// Type: {meta.get("type")}. Order: {meta.get("order")}. Root: {meta.get("root")}.')
        lines.append(f'/// Reference: PS3.16 TID {t}')
        lines.append(f'public struct {struct}: SRTemplate {{')
        lines.append(f'    public static let identifier = TemplateIdentifier.{const}')
        lines.append(f'    public static let displayName = {swift_str(info["title"])}')
        lines.append(f'    public static let templateDescription = {swift_str(info["intro"])}')
        lines.append(f'    public static let rootValueType: ContentItemValueType = {root_vt(t)}')
        lines.append(f'    public static let isExtensible = {str(extensible).lower()}')
        lines.append(f'    public static let isOrderSignificant = {str(order_sig).lower()}')
        lines.append(f'    public static let isRoot = {str(is_root).lower()}')
        if info['params']:
            lines.append('    public static let parameters: [TemplateParameter] = [')
            ps = [f'        TemplateParameter(name: {swift_str(p[0].lstrip("$"))}, usage: {swift_str(p[1])})'
                  for p in info['params']]
            lines.append(',\n'.join(ps))
            lines.append('    ]')
        lines.append('')
        lines.append('    public static let rows: [TemplateRow] = [')
        lines.append(',\n'.join('        ' + row_literal(r, t) for r in info['rows']))
        lines.append('    ]')
        lines.append('}')
        lines.append('')
        if t == '1601':
            lines.append('/// The name this type had while it was mis-numbered as TID 320.')
            lines.append('@available(*, deprecated, renamed: "TID1601ImageLibraryEntry",')
            lines.append('           message: "Image Library Entry is TID 1601 in PS3.16; TID 320 is Image or Spatial Coordinates.")')
            lines.append('public typealias TID320ImageLibraryEntry = TID1601ImageLibraryEntry')
            lines.append('')
    with open(path, 'w') as f:
        f.write('\n'.join(lines))


if __name__ == '__main__':
    main()
