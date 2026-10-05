#!/usr/bin/env python3
"""G2 viewer / display-pipeline checks for diff_studio.py (loaded by glob; exports CHECKS).

Each check extracts values from the DICOMStudio Swift sources by regex and diffs them against the frozen
2026a DocBook. Nothing is transcribed by hand; see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md (G2, viewer).

  * ShutterShape raw values                      vs PS3.3 C.7.6.11 + C.7.6.15 Shutter Shape (0018,1600) values
  * VOI LUT Function strings                      vs PS3.3 C.11.2 (LINEAR, LINEAR_EXACT, SIGMOID)
  * PresentationLUTShape raw values               vs PS3.3 C.11.6 (IDENTITY, INVERSE)
  * GraphicType raw values                        vs PS3.3 C.10.5 Graphic Type (0070,0023)
  * TextAnchorType raw values                     vs PS3.3 C.10.5 annotation units (PIXEL, DISPLAY, MATRIX)
  * DisplayedArea default size mode               vs PS3.3 C.10.4 Presentation Size Mode (0070,0100)
  * ModalityLUTTransform default Rescale Type     vs PS3.3 C.11.1.1.2 Defined Terms
  * rotationAngle values                          vs PS3.3 C.10.6 Image Rotation (0070,0042)
  * applyLinearVOI / applyLinearExactVOI          vs the C.11.2.1.2.1 / C.11.2.1.3.2 pseudo-code, token for token
  * DICOMInspectorView binary VRs                 vs PS3.5 Table 6.2-1 "Other …" VRs + UN
  * tag literals in the overlay files             vs PS3.6 Table 6-1
  * SOP Class UID literals and the waveform arc   vs PS3.6 Table A-1
  * photometric strings, preset modality codes    vs PS3.3 C.7.6.3.1.2, C.7.3.1.1.1
  * PresentationStatePalette raw values           vs PS3.6 Table B.1-1 (three standard names; the rest documented)
  * the N.2 chain reaches FrameRenderRequest (D65/D68) and the saves carry photometric / Rescale Type (D42)

    python3 Scripts/diff_studio.py --nema DIR --group G2 --only viewer
"""
import os
import re

PENDING_API_APPROVAL = {
    'TextAnchorType "IMAGE"': 'P-STUDIO-ANNOTATION-UNITS',   # raw value IMAGE is not a C.10.5 unit (PIXEL)
}
DEFERRED = {
    'renderFrameWithStoredWindow': 'D-new (DICOMKit: header window applied to stored values)',
}
EXEMPT = {}

G2 = 'DICOMStudio/'


# --- helpers -----------------------------------------------------------------------------------------

def read(ctx, relpath):
    return ctx['dw'].read(os.path.join(ctx['sources'], relpath))


def variablelists(nd, dw, part, xml_id):
    """[[term, …], …]: the terms of every variablelist under a section, list by list."""
    D = nd.D
    sec = dw.section_by_id(part, xml_id)
    out = []
    if sec is None:
        return out
    for vl in sec.iter(D + 'variablelist'):
        out.append([nd.norm(''.join(ve.find(D + 'term').itertext())).strip()
                    for ve in vl.findall(D + 'varlistentry')])
    return out


def list_containing(lists, *members):
    for lst in lists:
        if all(m in lst for m in members):
            return set(lst)
    return set()


def enum_raw_values(src, enum_name):
    m = re.search(r'enum\s+' + enum_name + r'\s*:\s*String[^{]*\{(.*?)\n\}', src, re.S)
    return dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', m.group(1))) if m else {}


def section_paras(nd, dw, part, xml_id):
    D = nd.D
    sec = dw.section_by_id(part, xml_id)
    if sec is None:
        return []
    return [' '.join(''.join(p.itertext()).split()) for p in sec.iter(D + 'para')]


def squash(s):
    return re.sub(r'\s+', '', s).replace('2.0', '2').replace('1.0', '1').replace('0.5', '0.5')


# --- PS3.3 C.7.6.11 / C.7.6.15: shutter shapes -----------------------------------------------------

def check_shutter_shapes(rep, parts, files, ctx):
    nd, dw = ctx['nd'], ctx['dw']
    std = set()
    for xid in ('sect_C.7.6.11', 'sect_C.7.6.15'):
        for lst in variablelists(nd, dw, parts[3], xid):
            std |= set(lst)
    std = {t for t in std if t.isupper()}
    ours = set(enum_raw_values(read(ctx, G2 + 'Models/ShutterModel.swift'), 'ShutterShape').values())
    rep.check('G2 viewer: ShutterShape raw values == Shutter Shape (0018,1600) values of PS3.3 C.7.6.11 + C.7.6.15',
              len(ours & std), wrong=sorted(ours - std), missing=sorted(std - ours))


# --- PS3.3 C.11.2 / C.11.6 / C.11.1.1.2: LUT vocabulary ------------------------------------------------

def check_lut_terms(rep, parts, files, ctx):
    nd, dw = ctx['nd'], ctx['dw']
    helpers = read(ctx, G2 + 'Components/PresentationStateHelpers.swift')
    model = read(ctx, G2 + 'Models/PresentationStateModel.swift')
    viewer = read(ctx, G2 + 'ViewModels/ImageViewerViewModel.swift')

    functions = list_containing(variablelists(nd, dw, parts[3], 'sect_C.11.2'), 'LINEAR', 'SIGMOID')
    body = re.search(r'func applyVOILUT\(.*?\n    \}', helpers, re.S).group(0)
    ours = set(re.findall(r'case\s+"([A-Z_]+)"', body))
    ours |= set(re.findall(r'function:\s*String\s*=\s*"([A-Z_]+)"', model))
    ours |= set(re.findall(r'voiLUTFunction:\s*String\s*=\s*"([A-Z_]+)"', viewer))
    rep.check('G2 viewer: VOI LUT Function strings (applyVOILUT cases, model and viewer defaults) == PS3.3 C.11.2 terms',
              len(ours & functions), wrong=sorted(ours - functions), missing=sorted(functions - ours))

    shapes = list_containing(variablelists(nd, dw, parts[3], 'sect_C.11.6'), 'IDENTITY', 'INVERSE')
    ours = set(enum_raw_values(model, 'PresentationLUTShape').values())
    rep.check('G2 viewer: PresentationLUTShape raw values == Presentation LUT Shape (2050,0020) values of PS3.3 C.11.6',
              len(ours & shapes), wrong=sorted(ours - shapes), missing=sorted(shapes - ours))

    rescale = list_containing(variablelists(nd, dw, parts[3], 'sect_C.11.1.1.2'), 'HU', 'US')
    m = re.search(r'rescaleType:\s*String\s*=\s*"([A-Z_]+)"', model)
    default = m.group(1) if m else '?'
    rep.check('G2 viewer: ModalityLUTTransform default Rescale Type is a PS3.3 C.11.1.1.2 Defined Term',
              1 if default in rescale else 0, wrong=[] if default in rescale else [f'default "{default}" not in {sorted(rescale)}'])


# --- PS3.3 C.10.4 / C.10.5 / C.10.6: displayed area, annotations, spatial transformation ---------------

def check_annotation_terms(rep, parts, files, ctx):
    nd, dw = ctx['nd'], ctx['dw']
    lists = variablelists(nd, dw, parts[3], 'sect_C.10.5')
    annot = read(ctx, G2 + 'Models/AnnotationModel.swift')
    model = read(ctx, G2 + 'Models/PresentationStateModel.swift')
    helpers = read(ctx, G2 + 'Components/PresentationStateHelpers.swift')

    graphic = list_containing(lists, 'POINT', 'POLYLINE', 'ELLIPSE')
    ours = set(enum_raw_values(annot, 'GraphicType').values())
    rep.check('G2 viewer: GraphicType raw values == Graphic Type (0070,0023) values of PS3.3 C.10.5',
              len(ours & graphic), wrong=sorted(ours - graphic), missing=sorted(graphic - ours))

    units = list_containing(lists, 'PIXEL', 'DISPLAY', 'MATRIX')
    ours = set(enum_raw_values(annot, 'TextAnchorType').values())
    p_item = PENDING_API_APPROVAL['TextAnchorType "IMAGE"']
    pending = [f'TextAnchorType "{v}" is not an Anchor Point Annotation Units value {sorted(units)} ({p_item})'
               for v in sorted(ours - units)]
    rep.check('G2 viewer: TextAnchorType raw values ⊆ Bounding Box / Anchor Point Annotation Units of PS3.3 C.10.5',
              len(ours & units), pending=pending, extra=[f'not offered: {t}' for t in sorted(units - ours)])

    modes = list_containing(variablelists(nd, dw, parts[3], 'sect_C.10.4'), 'SCALE TO FIT', 'MAGNIFY')
    m = re.search(r'presentationSizeMode:\s*String\s*=\s*"([A-Z ]+)"', model)
    default = m.group(1) if m else '?'
    rep.check('G2 viewer: DisplayedArea default Presentation Size Mode is a PS3.3 C.10.4 value',
              1 if default in modes else 0, wrong=[] if default in modes else [f'"{default}" not in {sorted(modes)}'])

    rotations = list_containing(variablelists(nd, dw, parts[3], 'sect_C.10.6'), '0', '90', '270')
    body = re.search(r'func rotationAngle\(.*?\n    \}', helpers, re.S).group(0)
    ours = {str(int(float(v))) for v in re.findall(r'return\s+([0-9.]+)', body)}
    rep.check('G2 viewer: rotationAngle values == Image Rotation (0070,0042) values of PS3.3 C.10.6',
              len(ours & rotations), wrong=sorted(ours - rotations), missing=sorted(rotations - ours))
    # Table C.10-6 order: rotation "before any Image Horizontal Flip"; the code must rotate first.
    tp = re.search(r'func transformPoint\(.*?\n    \}', helpers, re.S).group(0)
    rot_at = tp.find('rotationAngle(for:')
    flip_at = tp.find('isFlippedHorizontally(transformation)')
    rows = {r[0]: r[3] for r in dw.table_rows(parts[3], 'C.10-6') if len(r) > 3}
    says_before = 'before any Image Horizontal Flip' in rows.get('Image Rotation', '')
    ok = says_before and 0 <= rot_at < flip_at
    rep.check('G2 viewer: transformPoint rotates before it flips (PS3.3 Table C.10-6 Image Rotation description)',
              1 if ok else 0, wrong=[] if ok else ['transformPoint applies the horizontal flip before the rotation'])


# --- PS3.3 C.11.2.1.2.1 / C.11.2.1.3.2: the window pseudo-code, token for token --------------------------

def _std_pseudocode(nd, dw, part, xml_id):
    paras = section_paras(nd, dw, part, xml_id)
    cond1 = cond2 = ramp = None
    for p in paras:
        q = squash(p)
        if q.startswith('if(x<=') and ',theny=ymin' in q and cond1 is None:
            cond1 = q[len('if('):q.index('),theny=ymin')]
        elif q.startswith('elseif(x>') and ',theny=ymax' in q and cond2 is None:
            cond2 = q[len('elseif('):q.index('),theny=ymax')]
        elif q.startswith('elsey=(') and ')*(ymax-ymin)+ymin' in q and ramp is None:
            ramp = q[len('elsey=('):q.index(')*(ymax-ymin)+ymin')]
    return cond1, cond2, ramp


def _swift_branches(src, func_name):
    body = re.search(r'func ' + func_name + r'\(.*?\n    \}', src, re.S).group(0)
    body = body.replace('pixelValue', 'x').replace('center', 'c').replace('width', 'w')
    c1 = re.search(r'if\s+(x\s*<=.*?)\s*\{', body)
    c2 = re.search(r'else if\s+(x\s*>.*?)\s*\{', body)
    r = re.findall(r'return\s+(\(x.*)', body)
    return (squash(c1.group(1)) if c1 else None, squash(c2.group(1)) if c2 else None,
            squash(r[-1]) if r else None)


def check_window_pseudocode(rep, parts, files, ctx):
    nd, dw = ctx['nd'], ctx['dw']
    helpers = read(ctx, G2 + 'Components/PresentationStateHelpers.swift')
    for label, xid, func in (('LINEAR', 'sect_C.11.2.1.2.1', 'applyLinearVOI'),
                             ('LINEAR_EXACT', 'sect_C.11.2.1.3.2', 'applyLinearExactVOI')):
        std = _std_pseudocode(nd, dw, parts[3], xid)
        ours = _swift_branches(helpers, func)
        wrong = [f'{func} {what}: Swift "{o}" ≠ standard "{s}"'
                 for what, s, o in zip(('lower threshold', 'upper threshold', 'ramp'), std, ours) if s != o]
        missing = [f'{label}: pseudo-code line not found in {xid}' for s in std if s is None]
        rep.check(f'G2 viewer: {func} is the PS3.3 {xid[5:]} {label} pseudo-code (ymin 0, ymax 1), 3 branches',
                  3 - len(wrong) - len(missing), wrong, missing)
    sig = re.search(r'func applySigmoidVOI\(.*?\n    \}', helpers, re.S).group(0)
    ok = 'exp(' in sig and '-4.0 * (pixelValue - center) / width' in sig
    rep.check('G2 viewer: applySigmoidVOI is 1 / (1 + exp(−4 (x − c) / w)) (PS3.3 C.11.2.1.3.1; the formula is an image in the DocBook, not text-diffed)',
              1 if ok else 0, wrong=[] if ok else ['sigmoid exponent is not −4 (x − c) / w'])


# --- PS3.5 Table 6.2-1: the inspector's binary VRs -----------------------------------------------------

def check_inspector_binary_vrs(rep, parts, files, ctx):
    dw = ctx['dw']
    std = {r[0].split('|')[0].strip() for r in dw.table_rows(parts[5], '6.2-1')
           if r and r[0].split('|')[1].strip().startswith('Other')} | {'UN'}
    src = read(ctx, G2 + 'Views/DICOMInspectorView.swift')
    m = re.search(r'\[VR\.(\w+)((?:,\s*\.\w+)*)\]\.contains\(element\.vr\)', src)
    ours = {m.group(1)} | set(re.findall(r'\.(\w+)', m.group(2))) if m else set()
    rep.check('G2 viewer (D28): DICOMInspectorView binary-VR set == PS3.5 Table 6.2-1 "Other …" VRs + UN',
              len(ours & std), wrong=sorted(ours - std), missing=sorted(std - ours))


# --- PS3.6 Table 6-1: tag literals ---------------------------------------------------------------------

TAG_FILES = (G2 + 'Models/PatientOverlayText.swift', G2 + 'ViewModels/ImageViewerViewModel+PatientOverlay.swift',
             G2 + 'Models/AnnotationModel.swift', G2 + 'Models/ShutterModel.swift',
             G2 + 'Views/DICOMInspectorView.swift', G2 + 'Services/FrameRenderer.swift',
             G2 + 'ViewModels/ImageViewerViewModel.swift')


def check_tag_literals(rep, parts, files, ctx):
    dw = ctx['dw']
    table = {}
    for r in dw.table_rows(parts[6], '6-1'):
        if r and r[0].startswith('('):
            table[r[0].strip('()').upper().replace('X', 'X')] = (r[1], r[-1] if len(r) > 5 else '')
    matched, wrong, missing = 0, [], []
    for rel in TAG_FILES:
        src = read(ctx, rel)
        tags = set(re.findall(r'\((?:0x)?([0-9A-Fa-f]{4}),\s*(?:0x)?([0-9A-Fa-f]{4})\)', src))
        tags |= set(re.findall(r'Tag\(group:\s*0x([0-9A-Fa-f]{4}),\s*element:\s*0x([0-9A-Fa-f]{4})\)', src))
        tags |= set(re.findall(r'string\(dataSet,\s*0x([0-9A-Fa-f]{4}),\s*0x([0-9A-Fa-f]{4})\)', src))
        for g, e in sorted(tags):
            key = f'{g.upper()},{e.upper()}'
            if key.startswith('60') or key.startswith('FFFE'):
                matched += 1          # repeating / item delimiters: PS3.5 7.5 and 7.6, not Table 6-1 rows
                continue
            if key in table:
                matched += 1
            else:
                missing.append(f'{os.path.basename(rel)}: ({key}) is not a PS3.6 Table 6-1 row')
    rep.check('G2 viewer: tag literals in the overlay, annotation, shutter, inspector and renderer files are PS3.6 Table 6-1 rows',
              matched, wrong, missing)


# --- PS3.6 Table A-1: SOP Class UIDs and the waveform arc ---------------------------------------------

def check_sop_class_uids(rep, parts, files, ctx):
    dw = ctx['dw']
    reg = dw.uid_registry(parts[6])
    matched, wrong = 0, []
    ps = read(ctx, G2 + 'ViewModels/ImageViewerViewModel+PresentationStates.swift')
    for uid in set(re.findall(r'"(1\.2\.840\.10008\.5\.1\.4\.1\.1\.7)"', ps)):
        if reg.get(uid, ('',))[0] == 'Secondary Capture Image Storage':
            matched += 1
        else:
            wrong.append(f'{uid} fallback is not Secondary Capture Image Storage in Table A-1')
    model = read(ctx, G2 + 'Models/PresentationStateModel.swift')
    for uid, expect in (('1.2.840.10008.5.1.4.1.1.11.1', 'Grayscale Softcopy Presentation State Storage'),
                        ('1.2.840.10008.5.1.4.1.1.11.2', 'Color Softcopy Presentation State Storage'),
                        ('1.2.840.10008.5.1.4.1.1.11.3', 'Pseudo-Color Softcopy Presentation State Storage')):
        if uid in model:
            if reg.get(uid, ('',))[0] == expect:
                matched += 1
            else:
                wrong.append(f'PresentationStateModel cites {uid} as {expect}; Table A-1 says {reg.get(uid)}')
    viewer = read(ctx, G2 + 'ViewModels/ImageViewerViewModel.swift')
    body = re.search(r'func isWaveformFile\(.*?\n    \}', viewer, re.S).group(0)
    arcs = re.findall(r'hasPrefix\("([\d.]+)"\)', body)
    include = [a for a in arcs if a.endswith('.') and '.9.100.' not in a]
    exclude = [a for a in arcs if '.9.100.' in a]
    for uid, v in sorted(reg.items()):
        if include and uid.startswith(include[0]):
            if any(uid.startswith(x) for x in exclude):
                ok = 'Presentation State' in v[0]
            else:
                ok = 'Waveform Storage' in v[0]
            if ok:
                matched += 1
            else:
                wrong.append(f'isWaveformFile arc: {uid} "{v[0]}" is classified as a waveform file')
    if not include:
        wrong.append('isWaveformFile has no OID-arc prefix ending in "."')
    rep.check('G2 viewer: SOP Class UID literals and the isWaveformFile arc agree with PS3.6 Table A-1 names',
              matched, wrong)


# --- PS3.3 C.7.6.3.1.2 / C.7.3.1.1.1: photometric and modality strings --------------------------------

def check_photometric_and_modality_strings(rep, parts, files, ctx):
    nd, dw = ctx['nd'], ctx['dw']
    photometric = set()
    for lst in variablelists(nd, dw, parts[3], 'sect_C.7.6.3.1.2'):
        photometric |= set(lst)
    ours = set()
    for rel in (G2 + 'ViewModels/ImageViewerViewModel.swift', G2 + 'ViewModels/ImageViewerViewModel+PresentationStates.swift',
                G2 + 'Services/FrameRenderer.swift', G2 + 'Components/EnterpriseRenderHelpers.swift'):
        ours |= set(re.findall(r'"(MONOCHROME[12]|RGB|PALETTE COLOR|YBR_[A-Z_0-9]+)"', read(ctx, rel)))
    rep.check('G2 viewer: photometric string literals in the viewer files are PS3.3 C.7.6.3.1.2 terms',
              len(ours & photometric), wrong=sorted(ours - photometric))

    lists = variablelists(nd, dw, parts[3], 'sect_C.7.3.1.1.1')
    current = set(lists[0]) if lists else set()
    ours = set()
    for rel in (G2 + 'Components/WindowLevelPresets.swift', G2 + 'ViewModels/DICOMVolumeViewerViewModel.swift'):
        src = read(ctx, rel)
        ours |= set(re.findall(r'modality:\s*"([A-Z]+)"', src))
        ours |= set(re.findall(r'\("([A-Z]+)",\s*\w+Presets\)', src))
        ours |= set(re.findall(r'case\s+"([A-Z]+)":', src))
    rep.check('G2 viewer: preset modality codes (WindowLevelPresets, DICOMVolumeViewerViewModel) are PS3.3 C.7.3.1.1.1 Defined Terms',
              len(ours & current), wrong=sorted(ours - current))


# --- PS3.6 Table B.1-1: palette names ------------------------------------------------------------------

def check_palette_names(rep, parts, files, ctx):
    dw = ctx['dw']
    std = {r[1] for r in dw.table_rows(parts[6], 'B.1-1') if len(r) > 1}
    ours = set(enum_raw_values(read(ctx, G2 + 'Models/PresentationStateModel.swift'), 'PresentationStatePalette').values())
    rep.check('G2 viewer: PresentationStatePalette names vs PS3.6 Table B.1-1 Well-known Color Palettes (this app documents its own extras)',
              len(ours & std), extra=[f"app's own palette name: {p}" for p in sorted(ours - std)]
              + [f'standard palette not offered: {p}' for p in sorted(std - ours)], fail_on_missing=False)


# --- PS3.4 N.2: the chain reaches the renderer (D65, D68) and the saves carry their inputs (D42) ---------

def check_display_chain(rep, parts, files, ctx):
    matched, wrong = 0, []
    for rel in (G2 + 'Services/FrameRenderer.swift', G2 + 'ViewModels/ImageViewerViewModel.swift'):
        src = read(ctx, rel)
        for m in re.finditer(r'FrameRenderRequest\((.*?)\)\n', src, re.S):
            args = m.group(1)
            line = src.count('\n', 0, m.start()) + 1
            if 'modalityLUT:' in args and 'voiLUT:' in args and 'iccProfile:' in args:
                matched += 1
            else:
                wrong.append(f'{os.path.basename(rel)}:{line}: FrameRenderRequest built without modalityLUT / voiLUT / iccProfile (PS3.4 N.2)')
            if re.search(r'window:\s*WindowSettings\(', args):
                wrong.append(f'{os.path.basename(rel)}:{line}: a stored-unit window is handed to the renderer (D65)')
    deferred = []
    for rel in (G2 + 'Services/ImageRenderingService.swift', G2 + 'Services/ImageDecodingService.swift'):
        src = read(ctx, rel)
        for m in re.finditer(r'^(?!\s*//).*\b(renderFrameWithStoredWindow|renderFrame\(\w*,?\s*window:)', src, re.M):
            line = src.count('\n', 0, m.start()) + 1
            wrong.append(f'{os.path.basename(rel)}:{line}: renders through DICOMKit\'s stored-value window path, not the N.2 chain (D65)')
    rep.check('G2 viewer (D65, D68): every FrameRenderRequest the viewer builds carries the Modality LUT, VOI and ICC Profile (PS3.4 N.2; PS3.3 C.11.2.1.2.1, C.11.15.1.1)',
              matched, wrong, extra=deferred)

    matched, wrong = 0, []
    for rel in (G2 + 'ViewModels/ImageViewerViewModel+PresentationStates.swift', G2 + 'ViewModels/PrintViewModel+PresentationStates.swift'):
        src = read(ctx, rel)
        for name in ('ImageToSave(', '.capture(', '.restore('):
            for m in re.finditer(re.escape(name) + r'(.*?)\n\s*\)?\n', src, re.S):
                args = m.group(1)
                line = src.count('\n', 0, m.start()) + 1
                need = ['photometricInterpretation:'] + (['rescaleType:'] if name == 'ImageToSave(' else [])
                if all(n in args for n in need):
                    matched += 1
                else:
                    wrong.append(f'{os.path.basename(rel)}:{line}: {name}…) without {need} (PS3.4 N.2; PS3.3 A.33.1.1, D42)')
    rep.check('G2 viewer (D42): ImageToSave / bridge capture / restore are given the Photometric Interpretation and Rescale Type',
              matched, wrong)


CHECKS = [
    ('G2 viewer: shutter shapes', check_shutter_shapes),
    ('G2 viewer: LUT terms', check_lut_terms),
    ('G2 viewer: annotation, displayed-area and spatial terms', check_annotation_terms),
    ('G2 viewer: window pseudo-code', check_window_pseudocode),
    ('G2 viewer: inspector binary VRs (D28)', check_inspector_binary_vrs),
    ('G2 viewer: tag literals', check_tag_literals),
    ('G2 viewer: SOP Class UIDs', check_sop_class_uids),
    ('G2 viewer: photometric and modality strings', check_photometric_and_modality_strings),
    ('G2 viewer: palette names', check_palette_names),
    ('G2 viewer: display chain (D42, D65, D68)', check_display_chain),
]
