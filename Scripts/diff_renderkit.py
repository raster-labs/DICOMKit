#!/usr/bin/env python3
"""Diff the standard-derived formulas, constants and terms that Sources/DICOMRenderKit renders
with against the frozen DICOM DocBook.

Usage:
    for p in 3 5 6; do python3 Scripts/nema_docbook.py fetch 2026a $p --out DIR; done
    python3 Scripts/diff_renderkit.py --nema DIR [--verbose] [--only NAME]

DICOMRenderKit does no value arithmetic of its own. Both backends index byte tables built in
DICOMCore (`WindowLUT`, `ColorSampleLUT`, `PaletteDisplayLUT`) from DICOMCore's
`WindowSettings` and `PaletteColorLUT`; the CPU backend delegates to DICOMKit's
`PixelDataRenderer`, and the chain it is handed is prepared by DICOMKit's
`DICOMImageExporter.determineDisplayPipeline` (a window alone by
`determineModalityWindow`, in modality units). So each check extracts the formula or constant
the rendered pixel depends on from the Swift (or Metal) source that defines it, by regex, turns
it into a Python function where it is a formula, and evaluates it against the formula extracted
from the DocBook (the pseudo-code of C.11.2.1.2.1 / C.11.2.1.3.2, the MathML of C.11.2.1.3.1,
the equations of C.7.6.3.1.2). Nothing is transcribed by hand.

Statuses: `ok`; `FAIL` (DICOMRenderKit contradicts the text; exit 1); `PEND` (the fix changes
DICOMRenderKit public API and waits for the owner); `DEFR` (the value lives in another module
and is a Deferred finding, D-number given). This is the extraction + diff step of the
verification method in DICOMCORE_STANDARD_IMPLEMENTATION.md, applied to DICOMRenderKit (see
DICOMRENDERKIT_STANDARD_IMPLEMENTATION.md for the results).
"""
import argparse
import importlib.util
import math
import os
import re
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


nd = load('nema_docbook')
dw = load('diff_web')          # read_all, section helpers, func_body
dk = load('diff_kit')          # citations, photometric literals, section_terms
D, X = nd.D, nd.X
M = '{http://www.w3.org/1998/Math/MathML}'

# Findings whose fix changes DICOMRenderKit public API, waiting for the owner (PEND), and
# findings that live in another module (DEFR, with their D-number). Each key is a substring of
# the finding text; see DICOMRENDERKIT_STANDARD_IMPLEMENTATION.md.
PENDING_API_APPROVAL = {
    # P-PIPELINE and P-ICC were approved and implemented on 2026-09-30.
}
DEFERRED = {
    # D63, D64, D66, D67 and D65's DICOMKit half were closed on 2026-09-30; the stored-unit
    # conversion (determineWindowSettings) was deprecated on 2026-10-06 (A6) — nothing in
    # DICOMKit renders with it any more, so no row is deferred.
}


class Report:
    def __init__(self, verbose):
        self.verbose = verbose
        self.counts = {'ok': 0, 'FAIL': 0, 'PEND': 0, 'DEFR': 0}

    def check(self, name, matched, wrong=(), missing=(), extra=()):
        wrong, missing = list(wrong) + list(missing), []
        own, pending, deferred = [], [], []
        for item in wrong:
            p = next((v for k, v in PENDING_API_APPROVAL.items() if k in item), None)
            d = next((v for k, v in DEFERRED.items() if k in item), None)
            (pending if p else deferred if d else own).append((p or d or '', item))
        status = 'FAIL' if own else 'PEND' if pending else 'DEFR' if deferred else 'ok'
        self.counts[status] += 1
        print(f'{status:4} {name}: matched {matched}, wrong {len(wrong)}'
              + (f', pending {len(pending)}' if pending else '')
              + (f', deferred {len(deferred)}' if deferred else ''))
        for label, items in (('wrong', own), ('pending', pending), ('deferred', deferred)):
            for tag, item in items:
                print(f'       {label}{" " + tag if tag else ""}: {item}')
        for item in extra:
            if self.verbose:
                print(f'       note: {item}')


def section(part, xml_id):
    sec = dw.section_by_id(part, xml_id)
    if sec is None:
        sys.exit(f'{xml_id} not found in the DocBook; re-read the clause')
    return sec


def section_text(part, xml_id):
    return nd.norm(' '.join(section(part, xml_id).itertext()))


def line_of(src, pos):
    return src.count('\n', 0, pos) + 1


def need(src, pattern, what):
    m = re.search(pattern, src, re.S)
    if not m:
        sys.exit(f'could not find {what} (/{pattern}/) in the Swift source; update the extractor')
    return m


# --- the standard, as Python functions ---------------------------------------------------

def std_pseudocode(p3, xml_id):
    """The if/else-if/else pseudo-code of C.11.2.1.2.1 or C.11.2.1.3.2 as f(x, c, w) on [0, 1]."""
    t = section_text(p3, xml_id)
    m = re.search(r'if \(x <= (?P<lo>[^)]*(?:\([^)]*\)[^)]*)*)\), then y = y min else if '
                  r'\(x > (?P<hi>[^)]*(?:\([^)]*\)[^)]*)*)\), then y = y max else y = (?P<mid>.+?) '
                  r'\* \(y max - y min \) \+ y min', t)
    if not m:
        sys.exit(f'{xml_id}: pseudo-code not found; re-read the clause')
    lo, hi, mid = (compile(m[k], xml_id, 'eval') for k in ('lo', 'hi', 'mid'))

    def f(x, c, w):
        env = {'x': x, 'c': c, 'w': w}
        if x <= eval(lo, env):
            return 0.0
        if x > eval(hi, env):
            return 1.0
        return eval(mid, env)
    f.text = f'x <= {m["lo"]} → ymin; x > {m["hi"]} → ymax; else {m["mid"]}'
    return f


def mathml(e):
    tag = e.tag.replace(M, '')
    kids = [mathml(c) for c in e]
    if tag == 'mfrac':
        return f'(({kids[0]})/({kids[1]}))'
    if tag == 'msub':
        return kids[0] + kids[1]
    if tag in ('mi', 'mn', 'mo'):
        s = (e.text or '').strip()
        return {'−': '-', '·': '*', '×': '*'}.get(s, s)
    return ' '.join(kids)


def std_sigmoid(p3):
    """Equation C.11-1 (MathML) as f(x, c, w) on [0, 1]."""
    eq = next(section(p3, 'sect_C.11.2.1.3.1').iter(M + 'math'))
    expr = ' '.join(mathml(eq).split())
    expected_shape = r'y = \(\(\( ymax - ymin \)\)/\(1 \+ exp - 4 \(\(x - c\)/\(w\)\)\)\) \+ ymin'
    if not re.fullmatch(expected_shape, expr):
        sys.exit(f'C.11.2.1.3.1: equation is now {expr!r}; re-read the clause')
    py = expr.replace('exp - 4 ((x - c)/(w))', 'math.exp(-4*((x - c)/(w)))').split('=', 1)[1]

    def f(x, c, w):
        return eval(py, {'math': math, 'x': x, 'c': c, 'w': w, 'ymax': 1.0, 'ymin': 0.0})
    f.text = expr
    return f


# --- the code, as Python functions -------------------------------------------------------

def swift_expr(s):
    s = s.replace('pixelValue', 'x').replace('center', 'c').replace('width', 'w')
    return re.sub(r'\bexp\(', 'math.exp(', s)


def code_window_functions(ws_src):
    """WindowSettings.applyLinear / applyLinearExact / applySigmoid as f(x, c, w)."""
    out = {}
    for name in ('applyLinear', 'applyLinearExact'):
        body = swift_expr(dw.func_body(ws_src, r'func\s+' + name + r'\('))
        m = need(body, r'if x <= (.+?) \{\s*return 0\.0\s*\} else if x > (.+?) \{\s*return 1\.0'
                       r'\s*\} else \{\s*return (.+?)\n', f'{name} branches')
        lo, hi, mid = (compile(g, name, 'eval') for g in m.groups())

        def f(x, c, w, lo=lo, hi=hi, mid=mid):
            env = {'x': x, 'c': c, 'w': w}
            return 0.0 if x <= eval(lo, env) else 1.0 if x > eval(hi, env) else eval(mid, env)
        out[name] = f
    body = swift_expr(dw.func_body(ws_src, r'func\s+applySigmoid\('))
    exponent = need(body, r'let exponent = (.+?)\n', 'applySigmoid exponent').group(1)
    ret = need(body, r'return (.+?)\n', 'applySigmoid return').group(1).replace('exponent', f'({exponent})')

    def sig(x, c, w, ret=compile(ret, 'applySigmoid', 'eval')):
        return eval(ret, {'math': math, 'x': x, 'c': c, 'w': w})
    out['applySigmoid'] = sig
    return out


def width_clamp(ws_src, function='linear'):
    """The width WindowSettings.init stores for a requested width w (admissibleWidth)."""
    need(ws_src, r'self\.width = Self\.admissibleWidth\(width, for: function\)', 'WindowSettings.init width')
    body = dw.func_body(ws_src, r'static func admissibleWidth\(')
    lin = need(body, r'case \.linear:\s*return width >= 1\.0 \? width : 1\.0', 'LINEAR width rule')
    other = need(body, r'case \.linearExact, \.sigmoid:\s*return width > 0 && width\.isFinite \? width : 1\.0',
                 'SIGMOID / LINEAR_EXACT width rule')
    if function == 'linear':
        return (lambda w: w if w >= 1.0 else 1.0), lin.group(0)
    return (lambda w: w if (w > 0 and math.isfinite(w)) else 1.0), other.group(0)


def window_lut_quantise(core):
    """WindowLUT.build's final step: normalised y in [0, 1] → display byte."""
    body = core['WindowLUT.swift']
    need(body, r'out\[rawValue\] = WindowLUT\.displayByte\(normalized\)', 'WindowLUT quantisation call')
    tol = float(need(body, r'public static let quantisationTolerance = ([\de.-]+)', 'tolerance').group(1))
    m = need(body, r'UInt8\(max\(0, min\(255, normalized \* 255\.0 \+ quantisationTolerance\)\)\)', 'displayByte')
    return lambda y: int(max(0, min(255, y * 255.0 + tol))), m.group(0)


# --- checks -------------------------------------------------------------------------------

GRID_C = [-1000.5, -50.0, 0.0, 0.5, 40.0, 127.5, 2048.0, 32768.0]
GRID_W = [1.0, 2.0, 3.5, 100.0, 400.0, 4096.0, 65536.0]


def xs_around(c, w):
    pts = {c, c - w / 2, c + w / 2, c - 0.5 - (w - 1) / 2, c - 0.5 + (w - 1) / 2}
    out = set()
    for p in pts:
        for d in (-2, -1, -0.5, 0, 0.5, 1, 2):
            out.add(p + d)
            out.add(math.floor(p) + d)
    return sorted(out)


def check_voi_functions(rep, p3, core):
    """C.11.2.1.2.1 LINEAR, C.11.2.1.3.2 LINEAR_EXACT, C.11.2.1.3.1 SIGMOID vs WindowSettings.apply."""
    std = {'applyLinear': std_pseudocode(p3, 'sect_C.11.2.1.2.1'),
           'applyLinearExact': std_pseudocode(p3, 'sect_C.11.2.1.3.2'),
           'applySigmoid': std_sigmoid(p3)}
    code = code_window_functions(core['WindowSettings.swift'])
    matched, wrong = 0, []
    for name, f in std.items():
        bad = []
        for c in GRID_C:
            for w in GRID_W:
                for x in xs_around(c, w):
                    a, b = f(x, c, w), code[name](x, c, w)
                    if abs(a - b) > 1e-12:
                        bad.append((x, c, w, a, b))
        if bad:
            wrong.append(f'{name}: {len(bad)} points differ, first {bad[0]}')
        else:
            matched += 1
    rep.check('PS3.3 C.11.2.1.2.1 / C.11.2.1.3.1 / C.11.2.1.3.2: LINEAR, SIGMOID, LINEAR_EXACT '
              '(DocBook pseudo-code and Equation C.11-1) vs WindowSettings.apply, evaluated', matched, wrong,
              extra=[f'{k}: {v.text}' for k, v in std.items()])


def check_width_limits(rep, p3, core):
    """LINEAR: w >= 1 (C.11.2.1.2.1); SIGMOID and LINEAR_EXACT: w > 0 (C.11.2.1.3.1/.2)."""
    lin = section_text(p3, 'sect_C.11.2.1.2.1')
    others = [section_text(p3, s) for s in ('sect_C.11.2.1.3.1', 'sect_C.11.2.1.3.2')]
    problems = []
    if 'Window Width (0028,1051) shall always be greater than or equal to 1' not in lin:
        problems.append('C.11.2.1.2.1 no longer says w >= 1; re-read')
    if not all('Window Width (0028,1051) shall always be greater than 0' in t for t in others):
        problems.append('C.11.2.1.3.1/.2 no longer say w > 0; re-read')
    lin, lin_text = width_clamp(core['WindowSettings.swift'], 'linear')
    other, other_text = width_clamp(core['WindowSettings.swift'], 'other')
    matched = 0
    if lin(0.5) == 1.0 and lin(1.0) == 1.0 and lin(3.5) == 3.5:
        matched += 1
    else:
        problems.append(f'LINEAR width rule ({lin_text}) is not w >= 1')
    if all(other(w) == w for w in (0.25, 0.5, 0.999, 2.0)):
        matched += 1
    else:
        problems.append(f'WindowSettings clamps a SIGMOID / LINEAR_EXACT width below 1 ({other_text}); '
                        f'those functions only require w > 0')
    rep.check('PS3.3 C.11.2.1.2.1 / C.11.2.1.3.1 / C.11.2.1.3.2: Window Width limits per function',
              matched, problems)


def check_identity_quantisation(rep, p3, core):
    """C.11.2.1.2.1: c = 2^(n-1), w = 2^n is "a mathematical identity"; the byte the table stores
    must be the quantisation (WindowLUT's own floor) of the exact value, not of a rounding error."""
    t = section_text(p3, 'sect_C.11.2.1.2.1')
    if 'A Window Center of 2 n-1 and a Window Width of 2 n selects the range of input values from 0 to 2 n -1. ' \
       'This represents a mathematical identity' not in t:
        sys.exit('C.11.2.1.2.1: identity statement not found; re-read')
    f = std_pseudocode(p3, 'sect_C.11.2.1.2.1')
    quantise, text = window_lut_quantise(core)
    code_linear = code_window_functions(core['WindowSettings.swift'])['applyLinear']
    matched, wrong = 0, []
    for n in (8, 12, 16):
        c, w = Fraction(2 ** (n - 1)), Fraction(2 ** n)
        bad = []
        for x in range(2 ** n):
            exact = ((Fraction(x) - (c - Fraction(1, 2))) / (w - 1) + Fraction(1, 2)) * 255
            exact = min(Fraction(255), max(Fraction(0), exact))
            if quantise(code_linear(float(x), float(c), float(w))) != math.floor(exact):
                bad.append(x)
        if bad:
            wrong.append(f'WindowLUT quantisation ({text}): identity window n={n}: {len(bad)} of {2 ** n} '
                         f'inputs one level below the exact value (e.g. x={bad[:4]})')
        else:
            matched += 1
    rep.check('PS3.3 C.11.2.1.2.1: the identity window (c = 2^(n-1), w = 2^n) renders the exact value',
              matched, wrong)
    assert f  # the pseudo-code was found


def check_modality_before_voi(rep, p3, files, kit):
    """C.11.2.1.2.1: the window applies to stored values "after any Modality LUT or Rescale Slope
    and Intercept ... have been applied". Every DICOMKit render path takes the window in modality
    units and applies it through GrayscaleDisplayPipeline after the Modality LUT: the exporter's
    determineModalityWindow / determineDisplayPipeline, DICOMFile.renderFrame(_:window:) (D243)
    and the request's chain. The deprecated stored-unit determineWindowSettings (the D65 Studio
    half, A6) is evaluated too, so its inexactness stays on record rather than silently kept."""
    t = section_text(p3, 'sect_C.11.2.1.2.1')
    if 'after any Modality LUT or Rescale Slope and Intercept specified in the IOD have been applied' not in t:
        sys.exit('C.11.2.1.2.1: Modality LUT order sentence not found; re-read')
    exporter = kit['ImageExport/DICOMImageExporter.swift']
    f = std_pseudocode(p3, 'sect_C.11.2.1.2.1')
    matched, wrong = 0, []
    # The exact window: determineModalityWindow hands the explicit or header window on unchanged
    # (no slope / intercept arithmetic), so the chain applies it where the sentence says.
    exact = dw.func_body(exporter, r'public static func determineModalityWindow\(')
    if 'return WindowSettings(center: center, width: width)' in exact and 'return window' in exact \
            and 'slope' not in exact and 'intercept' not in exact \
            and 'GrayscaleDisplayPipeline.fullRangeWindow(modalityLUT: modality' in exact:
        matched += 1
    else:
        wrong.append('determineModalityWindow converts the window instead of returning it in modality units')
    pixel = kit['DICOMFile+PixelData.swift']
    convenience = dw.func_body(pixel, r'private func renderFrameWithWindow\(')
    if 'GrayscaleDisplayPipeline.standard(' in convenience and 'modalityLUT: modalityLUT(frameIndex: frameIndex)' in convenience \
            and 'voiLUT: VOILUT(window)' in convenience and 'renderMonochromeFrame(frameIndex, pipeline: pipeline)' in convenience:
        matched += 1
    else:
        wrong.append('DICOMFile.renderFrame(_:window:) does not apply the window through the chain after the Modality LUT (D243)')
    modality_lut = dw.func_body(pixel, r'public func modalityLUT\(')
    if 'dataSet.modalityLUTData()' in modality_lut and '.rescale(slope: slope, intercept: intercept' in modality_lut \
            and modality_lut.find('modalityLUTData()') < modality_lut.find('.rescale('):
        matched += 1
    else:
        wrong.append('DICOMFile.modalityLUT does not prefer the Modality LUT Sequence over the rescale pair (C.11.1.1.2)')
    # The deprecated stored-unit conversion: still present, marked deprecated, and inexact for
    # any slope other than 1 (on record; nothing in DICOMKit renders with it).
    m = need(exporter, r'return WindowSettings\(center: \((center - intercept)\) / slope, width: width / abs\(slope\)\)',
             'toStored conversion')
    deprecated_at = exporter.rfind('@available(*, deprecated', 0, m.start())
    if deprecated_at != -1 and 'public static func determineWindowSettings(' in exporter[deprecated_at:m.start()]:
        matched += 1
    else:
        wrong.append('determineWindowSettings (stored-unit window) is not marked deprecated')
    clamp, _ = width_clamp(dict(dw.read_all(os.path.join(ROOT, 'Sources', 'DICOMCore')))['WindowSettings.swift'], 'linear')
    inexact = 0
    for slope, intercept in ((1.0, -1024.0), (2.0, 0.0), (0.5, 0.0), (-1.0, 100.0)):
        for c, w in ((40.0, 400.0), (0.0, 100.0), (1000.0, 10.0)):
            cs, ws = (c - intercept) / slope, clamp(w / abs(slope))
            bad = [s for s in range(-2000, 2000)
                   if int(255 * f(slope * s + intercept, c, w)) != int(255 * f(float(s), cs, ws))]
            if bad:
                inexact += 1
    if inexact and 'exact only for Rescale Slope 1' in exporter[deprecated_at:m.start()]:
        matched += 1
    else:
        wrong.append(f'the deprecated stored-unit conversion is inexact for {inexact} of 12 (slope, intercept, window) cases '
                     'but its deprecation message does not say so')
    request = files['FrameRenderBackend.swift']
    for field in ('modalityLUT: ModalityLUT?', 'voiLUT: VOILUT?', 'presentationLUT: PresentationLUT?'):
        if f'public let {field}' in request:
            matched += 1
        else:
            wrong.append(f'FrameRenderRequest has no `{field}` (PS3.4 N.2 chain)')
    pipe = kit['GrayscaleDisplayPipeline.swift']
    body = dw.func_body(pipe, r'public func normalizedValue\(')
    order = [body.find('modalityValue(forStoredValue: stored)'), body.find('switch voiLUT'),
             body.find('presentationLUT?.apply(to: voi)')]
    if -1 not in order and order == sorted(order):
        matched += 1
    else:
        wrong.append(f'GrayscaleDisplayPipeline does not apply Modality → VOI → Presentation LUT in order: {order}')
    if '(C.11.2.1.1)' in body and re.search(r'lut\.lookup\(Self\.tableIndex\(modality\)\) / Double\(lut\.maxOutputValue\)', body):
        matched += 1
    else:
        wrong.append('VOI LUT output is not normalised by 2^n − 1 (C.11.2.1.1)')
    export = dw.func_body(exporter, r'public static func renderFrameForExport\(')
    resolve = dw.func_body(exporter, r'public static func determineDisplayPipeline\(')
    if 'determineDisplayPipeline(' in export and 'determineWindowSettings(' not in export and '/ slope' not in resolve \
            and 'file.modalityLUT(frameIndex: frameIndex)' in resolve and 'dataSet.voiLUT()' in resolve:
        matched += 1
    else:
        wrong.append('export does not render monochrome frames through the chain with the window in modality units')
    rep.check('PS3.3 C.11.2.1.2.1: the VOI window applies after the Modality LUT / rescale', matched, wrong,
              extra=[f'deprecated stored-unit conversion: {m.group(0)}'])


def check_full_range_window(rep, p3, kit):
    """C.11.2.1.2.1: x1..x2 in full is c = (x1+x2+1)/2, w = x2-x1+1."""
    t = section_text(p3, 'sect_C.11.2.1.2.1')
    std = need(t, r'a Window Center of \((x1\+x2\+1)\)/2 and a Window Width of \((x2-x1\+1)\) selects the range '
                  r'of input values from x1 to x2', 'full-range sentence')
    f = std_pseudocode(p3, 'sect_C.11.2.1.2.1')
    matched, wrong = 0, []
    good = {'PixelDataRenderer.swift': r'center: Double\(range\.min \+ range\.max \+ 1\) / 2\.0,\s*width: Double\(range\.max - range\.min \+ 1\)',
            'ImageExport/DICOMImageExporter.swift': r'center: Double\(range\.min \+ range\.max \+ 1\) / 2\.0,\s*width: Double\(range\.max - range\.min \+ 1\)',
            'PixelEditing/PixelEditor.swift': r'storedMin \+ descriptor\.storedMax \+ 1\) / 2\.0\s*let storedWidth = Double\(descriptor\.storedMax - descriptor\.storedMin \+ 1\)',
            'ImagePreprocessor.swift': r'WindowSettings\(center: \(minVal \+ maxVal\) / 2\.0, width: maxVal - minVal,\s*function: \.linearExact\)\s*: WindowSettings\(center: minVal \+ 0\.5, width: 1\)',
            'GrayscaleDisplayPipeline.swift': r'\.window\(center: \(low \+ high\) / 2, width: high - low, explanation: nil, function: \.linearExact\)'}
    for fname, pat in good.items():
        if re.search(pat, kit[fname]):
            matched += 1
        else:
            wrong.append(f'{fname}: full-range window is not c = (x1+x2+1)/2, w = x2−x1+1')
    for fname, pat in (('PixelDataRenderer.swift', r'let center = Double\(range\.min \+ range\.max\) / 2\.0\s*'
                                                    r'let width = Double\(range\.max - range\.min\)'),
                       ('ImageExport/DICOMImageExporter.swift', r'let center = Double\(range\.min \+ range\.max\) / 2\.0\s*'
                                                                  r'let width = Double\(range\.max - range\.min\)')):
        src = kit[fname]
        m = re.search(pat, src)
        if not m:
            continue
        x1, x2 = -1000, 3000
        code = [int(255 * f(x, (x1 + x2) / 2, max(1.0, x2 - x1))) for x in range(x1, x2 + 1)]
        want = [int(255 * f(x, (x1 + x2 + 1) / 2, x2 - x1 + 1)) for x in range(x1, x2 + 1)]
        diff = sum(a != b for a, b in zip(code, want))
        wrong.append(f'{fname}:{line_of(src, m.start())}: full-range window is c=(min+max)/2, w=max-min '
                     f'(standard: ({std.group(1)})/2, {std.group(2)}); {diff} of {x2 - x1 + 1} values of a '
                     f'{x1}..{x2} frame differ, x2-1 already saturates')
    rep.check('PS3.3 C.11.2.1.2.1: the auto (full input range) window used when no window is given',
              matched, wrong)


def check_stored_value_chain(rep, p3, p5, core):
    """PS3.5 8.1.1 (mask; sign bit = High Bit; 2's complement), C.7.6.3.1.2 (MONOCHROME1 after the
    VOI). The order of the steps in WindowLUT.build and PaletteDisplayLUT.make."""
    t5 = section_text(p5, 'sect_8.1.1')
    t3 = section_text(p3, 'sect_C.7.6.3.1.2')
    problems, matched = [], 0
    for phrase in ('may not assume anything about the contents of unused bits',
                   'The sign bit shall be the High Bit', "binary 2's complement integer"):
        if phrase not in t5:
            problems.append(f'PS3.5 8.1.1 no longer says "{phrase}"; re-read')
    if 'The minimum sample value is intended to be displayed as white after any VOI gray scale transformations' not in t3:
        problems.append('C.7.6.3.1.2 MONOCHROME1 sentence not found; re-read')
    desc = core['PixelDataDescriptor.swift']
    for pat, what in ((r'var bitShift: Int \{\s*highBit - bitsStored \+ 1', 'bit shift = High Bit − Bits Stored + 1'),
                      (r'var storedBitMask: Int \{\s*\(1 << bitsStored\) - 1', 'mask of Bits Stored bits')):
        if re.search(pat, desc):
            matched += 1
        else:
            problems.append(f'PixelDataDescriptor: {what} not found')
    steps = [r'rawValue >> bitShift', r'& storedBitMask', r'let signBit = 1 << \(bitsStored - 1\)',
             r'maskedValue - \(1 << bitsStored\)', r'window\.apply\(to: Double\(maskedValue\)\)',
             r'if isMonochrome1 \{\s*normalized = 1\.0 - normalized', r'UInt8\(max\(0, min\(255, normalized']
    body = core['WindowLUT.swift']
    pos = [re.search(s, body).start() if re.search(s, body) else -1 for s in steps]
    if -1 in pos or pos != sorted(pos):
        problems.append(f'WindowLUT.build steps missing or out of order: {list(zip(steps, pos))}')
    else:
        matched += 1
    pal = core['ColorSampleLUT.swift']
    psteps = steps[:4] + [r'palette\.lookup\(maskedValue\)']
    ppos = [re.search(s, pal).start() if re.search(s, pal) else -1 for s in psteps]
    if -1 in ppos or ppos != sorted(ppos):
        problems.append(f'PaletteDisplayLUT.make steps missing or out of order: {list(zip(psteps, ppos))}')
    else:
        matched += 1
    rep.check('PS3.5 8.1.1, PS3.3 C.7.6.3.1.2: shift, mask, sign extension, VOI, then MONOCHROME1 inversion',
              matched, problems)


def check_sample_assembly(rep, p5, files, kit, metal, core):
    """PS3.5 8.1.1 (a Pixel Cell is Bits Allocated wide) and 8.2 (least significant bit first,
    little-endian words): the kernels and the CPU loops assemble one or two bytes, low byte first."""
    t = section_text(p5, 'sect_8.1.1') + ' ' + section_text(p5, 'sect_8.2')
    problems, matched = [], 0
    for phrase in ('The size of the Pixel Cell shall be specified by Bits Allocated',
                   'the least significant bit of each Pixel Cell is encoded in the least significant bit'):
        if phrase not in t:
            problems.append(f'PS3.5 no longer says "{phrase}"; re-read')
    kernel = dw.func_body(metal, r'static inline uint assembleSample\(')
    if re.search(r'return uint\(bytes\[offset\]\) \| \(uint\(bytes\[offset \+ 1\]\) << 8\);', kernel) \
            and 'if (bytesPerSample == 1)' in kernel:
        matched += 1
    else:
        problems.append('assembleSample is not "one byte, or low | high << 8"')
    renderer = files['Metal/MetalFrameRenderer.swift']
    if re.search(r'\(1\.\.\.2\)\.contains\(descriptor\.bytesPerSample\)', renderer):
        matched += 1
    else:
        problems.append('MetalFrameRenderer does not decline Pixel Cells wider than two bytes: a Bits Allocated 32 '
                        'cell would be rendered from its low 16 bits')
    cpu = kit['PixelDataRenderer.swift']
    if re.search(r'table\[low \| \(high << 8\)\]', cpu):
        matched += 1
    wide = len(re.findall(r'descriptor\.cellValue\(in: ', cpu))
    if wide >= 5 and 'WindowLUT.canTabulate(descriptor)' in cpu:
        matched += 1
    else:
        problems.append('PixelDataRenderer assembles every sample from its first two bytes (Bits Allocated 32 cells '
                        'rendered from their low 16 bits)')
    helper = dw.func_body(core['PixelDataDescriptor.swift'], r'public func cellValue\(')
    if re.search(r'for index in 0\.\.<bytesPerSample \{\s*value \|= Int\(bytes\[byteOffset \+ index\]\) << \(8 \* index\)', helper):
        matched += 1
    else:
        problems.append('PixelDataDescriptor.cellValue is not Bits Allocated wide, least significant byte first')
    if 'descriptor.cellValue(in: bytes, at: offset)' in kit['PresentationState/PresentationStateApplicator.swift']:
        matched += 1
    else:
        problems.append('PixelDataRenderer assembles …: the presentation-state applicator reads two bytes per cell')
    rep.check('PS3.5 8.1.1 / 8.2: sample assembly (cell width, little-endian) in the kernels and the CPU loops',
              matched, problems)


def check_planar_configuration(rep, p3, metal, files, kit):
    t = section_text(p3, 'sect_C.7.6.3.1.3')
    problems, matched = [], 0
    if 'R1, G1, B1, R2, G2, B2' not in t or 'R1, R2, R3, …, G1, G2, G3, …, B1, B2, B3' not in t:
        problems.append('C.7.6.3.1.3 enumerated layouts not found; re-read')
    body = dw.func_body(metal, r'kernel void render_color\(')
    for pat, what in ((r'uint base = index \* 3 \* p\.bytesPerSample;', 'config 0: pixel i starts at 3·i samples'),
                      (r'uint gOffset = p\.planeSizeBytes \+ rOffset;', 'config 1: G plane after R'),
                      (r'uint bOffset = 2 \* p\.planeSizeBytes \+ rOffset;', 'config 1: B plane after G')):
        if re.search(pat, body):
            matched += 1
        else:
            problems.append(f'render_color: {what} not found')
    if re.search(r'planeSizeBytes: UInt32\(geometry\.pixelCount \* descriptor\.bytesPerSample\)',
                 files['Metal/MetalFrameRenderer.swift']):
        matched += 1
    else:
        problems.append('MetalFrameRenderer: plane size is not pixels × bytes per sample')
    cpu = kit['PixelDataRenderer.swift']
    if re.search(r'let baseOffset = pixelIndex \* 3 \* bytesPerSample', cpu) and \
            re.search(r'let planeSize = totalPixels \* bytesPerSample', cpu):
        matched += 1
    else:
        problems.append('PixelDataRenderer planar offsets not found')
    rep.check('PS3.3 C.7.6.3.1.3: Planar Configuration 0 / 1 layouts in the kernel and the CPU loop', matched, problems)


def struct_fields(src, name, metal=False):
    m = need(src, r'struct ' + name + r'\s*\{(.*?)\n\s*\}', f'struct {name}')
    if metal:
        return re.findall(r'^\s*(\w+)\s+(\w+);', m.group(1), re.M)
    return [(t, n) for n, t in re.findall(r'var (\w+): ([\w<>]+)', m.group(1))]


def check_backend_parity(rep, metal, files, kit, core):
    """Every value the GPU writes comes from the same DICOMCore table the CPU uses; the compute
    kernels do no floating point; the parameter blocks agree field for field."""
    problems, matched = [], 0
    for k in ('render_monochrome', 'render_color', 'render_palette'):
        body = dw.func_body(metal, r'kernel void ' + k + r'\(')
        if re.search(r'\b(float\d?|half\d?|double)\b', body):
            problems.append(f'{k} uses floating point')
        else:
            matched += 1
    swift = files['Metal/MetalFrameRenderer.swift']
    types = {'UInt32': 'uint'}
    for name in ('MonochromeParams', 'ColorParams', 'PaletteParams'):
        a = [(types.get(t, t), n) for t, n in struct_fields(swift, name)]
        b = struct_fields(metal, name, metal=True)
        if a == b:
            matched += 1
        else:
            problems.append(f'{name}: Swift {a} vs Metal {b}')
    disp_swift = [n for _, n in struct_fields(files['Metal/DisplayFrameTexture.swift'], 'DisplayShaderParams')]
    disp_metal = [n for _, n in struct_fields(metal, 'DisplayParams', metal=True)]
    if disp_swift == disp_metal:
        matched += 1
    else:
        problems.append(f'DisplayParams order: Swift {disp_swift} vs Metal {disp_metal}')
    cpu = kit['PixelDataRenderer.swift']
    req = files['FrameRenderBackend.swift']
    pairs = [
        ('grey table (stored-unit window)', r'return WindowLUT\.grayscale\(descriptor: descriptor, window: window\)', req,
         r'WindowLUT\.grayscale\(descriptor: descriptor, window: window\)', cpu),
        ('grey table (N.2 chain)', r'displayPipeline\(scanningFrame: false\)\?\.table\(for: descriptor\)', req,
         r'if let table = pipeline\.table\(for: descriptor\)', cpu),
        ('the GPU indexes the request\'s grey table', r'guard let lut = request\.greyTable else \{ return nil \}', swift,
         r'renderMonochromeFrame\(\s*request\.frameIndex, pipeline: pipeline', files['CPUFrameRenderer.swift']),
        ('pseudo-colour table', r'PaletteDisplayLUT\.make\(window: lut, entries: palette\.entries\(\)\)', swift,
         r'PaletteDisplayLUT\.make\(\s*window: WindowLUT\.grayscale\(\s*descriptor: request\.pixelData\.descriptor, '
         r'window: window\),\s*entries: palette\.entries\(\)\)', files['CPUFrameRenderer.swift']),
        ('pseudo-colour table (N.2 chain)', r'PaletteDisplayLUT\.make\(window: lut, entries: palette\.entries\(\)\)', swift,
         r'PaletteDisplayLUT\.make\(window: table, entries: colours\)', cpu),
        ('RGB normalisation', r'let masked = \(rawValue >> bitShift\) & storedBitMask', core['ColorSampleLUT.swift'],
         r'r = \(r >> bitShift\) & storedBitMask', cpu),
        ('RGB scale', r'let scale = 255\.0 / Double\(maxValue\)', core['ColorSampleLUT.swift'],
         r'let scale = 255\.0 / Double\(maxValue\)', cpu),
        ('RGB byte', r'UInt8\(max\(0, min\(255, Double\(masked\) \* scale\)\)\)', core['ColorSampleLUT.swift'],
         r'UInt8\(max\(0, min\(255, Double\(r\) \* scale\)\)\)', cpu),
    ]
    for what, pa, sa, pb, sb in pairs:
        if re.search(pa, sa) and re.search(pb, sb):
            matched += 1
        else:
            problems.append(f'{what}: the GPU and CPU tables are not built by the same expression')
    kernel = dw.func_body(metal, r'kernel void render_color\(')
    for strict in (r'base \+ 2 < p\.frameByteCount', r'base \+ 5 < p\.frameByteCount',
                   r'bOffset < p\.frameByteCount', r'bOffset \+ 1 < p\.frameByteCount'):
        cpu_form = strict.replace(r'p\.frameByteCount', r'frameData\.count').replace('base', 'baseOffset')
        if re.search(strict, kernel) and re.search(cpu_form, cpu):
            matched += 1
        else:
            problems.append(f'bounds test {strict} differs between kernel and CPU')
    rep.check('Metal ↔ CPU: no floating point in compute kernels, one table builder, same layouts and bounds',
              matched, problems)


def check_photometric_routing(rep, p3, files):
    t = section_text(p3, 'sect_C.7.6.3.1.2')
    terms = set(dk.section_terms(p3, 'sect_C.7.6.3.1.2'))
    problems, matched = [], 0
    for term in ('MONOCHROME1', 'MONOCHROME2', 'PALETTE COLOR', 'RGB', 'YBR_FULL', 'YBR_FULL_422',
                 'YBR_PARTIAL_420', 'YBR_ICT', 'YBR_RCT', 'XYB'):
        if term in terms:
            matched += 1
        else:
            problems.append(f'{term} is not a C.7.6.3.1.2 term')
    if 'Red, Blue, and Green Palette Color Lookup Tables shall be present' not in t:
        problems.append('C.7.6.3.1.2 PALETTE COLOR sentence not found; re-read')
    req = files['FrameRenderBackend.swift']
    if re.search(r'if photometric\.isMonochrome \{ return \.monochrome \}\s*if photometric\.isPaletteColor '
                 r'\{ return \.palette \}\s*return \.color', req):
        matched += 1
    else:
        problems.append('FrameRenderRequest.family routing changed')
    swift = files['Metal/MetalFrameRenderer.swift']
    for pat, what in ((r'guard let palette = request\.paletteLUT else \{ return nil \}', 'PALETTE COLOR without its tables declined'),
                      (r'guard descriptor\.samplesPerPixel == 3 else \{ return nil \}', 'colour kernel: 3 samples only'),
                      (r'guard !descriptor\.photometricInterpretation\.isYBR else \{ return nil \}', 'YBR stays on the CPU')):
        if re.search(pat, swift):
            matched += 1
        else:
            problems.append(f'MetalFrameRenderer: {what} not found')
    if 'Images in XYB transcoded to other Transfer Syntaxes will use RGB' in t:
        matched += 1
    else:
        problems.append('C.7.6.3.1.2 XYB sentence changed; re-read (XYB frames reach the colour kernel as RGB)')
    rep.check('PS3.3 C.7.6.3.1.2: photometric interpretations routed to the right kernel', matched, problems)


def ybr_rows(text, start):
    i = text.find(start)
    seg = text[i:i + 2000]
    rows = []
    for key in ('Y =', 'CB=', 'CR='):
        m = re.search(re.escape(key) + r'\s*([-+ .\dRGB]+?)\s*(?:\+ 128|\+ 16|CB=|CR=|The above)', seg)
        coef = [float(s.replace(' ', '')) for s in re.findall(r'([-+]\s*\.\d+)[RGB]', m.group(1))]
        rows.append(coef)
    return rows


def invert3(a):
    (a1, a2, a3), (b1, b2, b3), (c1, c2, c3) = a
    det = a1 * (b2 * c3 - b3 * c2) - a2 * (b1 * c3 - b3 * c1) + a3 * (b1 * c2 - b2 * c1)
    return [[(b2 * c3 - b3 * c2) / det, (a3 * c2 - a2 * c3) / det, (a2 * b3 - a3 * b2) / det],
            [(b3 * c1 - b1 * c3) / det, (a1 * c3 - a3 * c1) / det, (a3 * b1 - a1 * b3) / det],
            [(b1 * c2 - b2 * c1) / det, (a2 * c1 - a1 * c2) / det, (a1 * b2 - a2 * b1) / det]]


def check_ybr(rep, p3, kit, files, metal):
    """C.7.6.3.1.2 YBR_FULL / YBR_PARTIAL_420 forward equations, inverted here, vs the inverse the
    CPU fallback applies (PixelDataRenderer, DICOMKit); and the desaturate weights of the display
    shader vs the YBR_FULL Y row. Tolerance 5e-4: the text prints four decimals."""
    t = section_text(p3, 'sect_C.7.6.3.1.2')
    full = ybr_rows(t, 'the following equations convert between RGB and YCBCR')
    partial = ybr_rows(t, 'convert between RGB and YBR_PARTIAL_420')
    cpu = kit['PixelDataRenderer.swift']
    problems, matched = [], 0
    for name, fwd, scale in (('ybrFullToRGB', full, 1.0), ('ybrPartialToRGB', partial, 1.0)):
        inv = invert3(fwd)
        body = dw.func_body(cpu, r'static func ' + name + r'\(')
        got = {}
        for ch, expr in re.findall(r'let ([rgb]) = (.+)', body):
            ycoef = re.search(r'([\d.]+) \* yc', expr)
            got[ch] = (float(ycoef.group(1)) if ycoef else 1.0,
                       sum(float(v) * (-1 if s == '-' else 1) for s, v in re.findall(r'([-+])\s*([\d.]+) \* cbc', expr)),
                       sum(float(v) * (-1 if s == '-' else 1) for s, v in re.findall(r'([-+])\s*([\d.]+) \* crc', expr)))
        for i, ch in enumerate('rgb'):
            want = tuple(inv[i])
            if ch not in got or any(abs(a - b) > 5e-4 for a, b in zip(got[ch], want)):
                problems.append(f'{name} {ch}: code {got.get(ch)} vs inverse of the C.7.6.3.1.2 matrix '
                                f'{tuple(round(v, 6) for v in want)}')
            else:
                matched += 1
    m = re.search(r'dot\(rgb, float3\(([\d.]+), ([\d.]+), ([\d.]+)\)\)', metal)
    if m and all(abs(float(a) - b) < 1e-9 for a, b in zip(m.groups(), full[0])):
        matched += 1
    else:
        problems.append(f'display_fragment desaturate weights {m.groups() if m else None} are not the '
                        f'YBR_FULL Y row {full[0]}')
    if '0.299/0.587/0.114' in files['Metal/DisplayFrameTexture.swift']:
        matched += 1
    rep.check('PS3.3 C.7.6.3.1.2: YBR_FULL / YBR_PARTIAL_420 inverses (CPU fallback) and the Rec.601 desaturate weights',
              matched, problems, extra=[f'YBR_FULL rows {full}', f'YBR_PARTIAL_420 rows {partial}'])


def check_palette_lookup(rep, p3, core):
    """C.7.6.3.1.5 (clamping, 0 = 2^16 entries) and C.7.6.3.1.6 (full-range entries) vs
    PaletteColorLUT, evaluated."""
    t5 = section_text(p3, 'sect_C.7.6.3.1.5')
    t6 = section_text(p3, 'sect_C.7.6.3.1.6')
    problems, matched = [], 0
    for phrase in ('All input values less than the first value mapped are also mapped to the first entry',
                   'Input values greater than or equal to number of entries + first value mapped are also mapped to the last entry',
                   'When the number of table entries is equal to 2 16 then this Value shall be 0'):
        if phrase not in t5:
            problems.append(f'C.7.6.3.1.5 no longer says "{phrase}"; re-read')
    if 'simply replicate the Value in both the most and least significant bytes' not in t6:
        problems.append('C.7.6.3.1.6 replication sentence not found; re-read')
    src = core['PaletteColorLUT.swift']
    clamp = need(src, r'let index = pixelValue - descriptor\.firstMappedValue\s*return max\(0, min\(descriptor\.numberOfEntries - 1, index\)\)',
                 'clampIndex')
    entries, first = 16, -3
    for v in range(-10, 30):
        want = 0 if v < first else entries - 1 if v >= entries + first else v - first
        if max(0, min(entries - 1, v - first)) != want:
            problems.append(f'clampIndex({v}) differs from C.7.6.3.1.5')
            break
    else:
        matched += 1
    if re.search(r'numberOfEntries\s*[:=]\s*[^\n]*== 0 \? 65536|== 0 \? 65_536|0 \? 65536', src) or \
            re.search(r'65536|65_536', src):
        matched += 1
    else:
        problems.append('PaletteColorLUT: first descriptor Value 0 not read as 65,536 entries')
    if re.search(r'return UInt8\(value >> 8\)', src):
        # 16-bit entry → its high byte; an 8-bit entry replicated (0xABAB) or placed high (0xAB00) → 0xAB
        if all((v << 8 | v) >> 8 == v and (v << 8) >> 8 == v for v in range(256)):
            matched += 1
    else:
        problems.append('PaletteColorLUT.normalize is not the high byte')
    rep.check('PS3.3 C.7.6.3.1.5 / C.7.6.3.1.6: palette index clamping and entry scaling', matched, problems,
              extra=[clamp.group(0)])


def expand_segments(values):
    """PS3.3 C.7.9.2 segmented LUT data (opcode 0 discrete, 1 linear) → entries. Linear
    segments end on their stated value; the standard gives no rounding rule, and half-to-even
    (Python's round) is the rule the DICOMCore tables state."""
    out, i = [], 0
    while i < len(values):
        op, n = values[i], values[i + 1]
        if op == 0:
            out += values[i + 2:i + 2 + n]
            i += 2 + n
        elif op == 1:
            y0, y1 = out[-1], values[i + 2]
            out += [round(y0 + (y1 - y0) * k / n) for k in range(1, n + 1)]
            i += 3
        else:
            sys.exit(f'segment opcode {op} not handled; read C.7.9.2')
    return out


def check_well_known_palettes(rep, p6, core):
    """PS3.6 Annex B: the 8 × 256 RGB entries of the Well-Known Color Palettes (explicit or
    segmented, Tables B.1.N.2-2, descriptor Tables B.1.N.2-1) vs DICOMWellKnownPalettes, which
    both backends fold into the pseudo-colour table."""
    src = core['DICOMWellKnownPalettes.swift']
    names = {'HOT_IRON': 'hotIron', 'PET': 'pet', 'HOT_METAL_BLUE': 'hotMetalBlue', 'PET_20_STEP': 'petTwentyStep',
             'SPRING': 'spring', 'SUMMER': 'summer', 'FALL': 'fall', 'WINTER': 'winter'}
    matched, wrong = 0, []
    for uid, label, _, sect, *rest in dw.table_rows(p6, 'B.1-1'):
        desc = dw.table_rows(p6, f'{sect}.2-1')[0]
        rows = dw.table_rows(p6, f'{sect}.2-2')
        cols = [[int(r[k]) for r in rows if len(r) > k and r[k].strip()] for k in range(3)]
        if [int(v) for v in desc] != [256, 0, 8]:
            wrong.append(f'{label}: descriptor {desc} is not (256, 0, 8)')
            continue
        if any(len(c) != 256 for c in cols):
            cols = [expand_segments(c) for c in cols]
        body = need(src, r'static let ' + names[label] + r'Packed: \[UInt32\] = \[(.*?)\]', f'{label} table')
        ours = [int(v, 16) for v in re.findall(r'0x([0-9A-Fa-f]{6})', body.group(1))]
        std = [(r << 16) | (g << 8) | b for r, g, b in zip(*cols)]
        diff = [i for i, (a, b) in enumerate(zip(ours, std)) if a != b]
        if len(ours) != 256 or len(std) != 256 or diff:
            wrong.append(f'{label}: {len(ours)} entries in DICOMCore, {len(std)} in PS3.6 {sect}; differ at {diff[:6]}')
        else:
            matched += 1
    rep.check('PS3.6 Annex B: the eight Well-Known Color Palettes, 256 RGB entries each (segmented ones expanded '
              'per PS3.3 C.7.9.2)', matched, wrong)


def check_spatial_order(rep, p3, files):
    """C.10.6: rotation "before any Image Horizontal Flip"; the display transforms rotate, then flip."""
    t = section_text(p3, 'sect_C.10.6')
    problems, matched = [], 0
    if 'before any Image Horizontal Flip (0070,0041) is applied' not in t or 'after any Image Rotation has been applied' not in t:
        problems.append('C.10.6 order sentences not found; re-read')
    src = files['Metal/DisplayFrameTexture.swift']
    for fn in ('func transform(imageWidth', 'func sourceRegionTransform('):
        body = dw.func_body(src, re.escape(fn))
        r, f = body.find('if rotationDegrees != 0'), body.find('if flipHorizontal || flipVertical')
        if 0 <= r < f:
            matched += 1
        else:
            problems.append(f'{fn}: flip is not applied after the rotation')
    rep.check('PS3.3 C.10.6: rotation before horizontal flip in the display transforms', matched, problems)


def check_icc(rep, p3, files, kit):
    """C.11.15.1.1: the ICC Profile maps device-dependent stored values to the PCS. Both backends
    tag their output Device RGB / Device Gray; the request carries no profile."""
    t = section_text(p3, 'sect_C.11.15.1.1')
    problems = []
    if 'encodes an ICC Input Device Profile that encodes the transformation of device-dependent color stored pixel values into PCS-Values' not in t:
        problems.append('C.11.15.1.1 sentence not found; re-read')
    tagged = [n for n, s in list(files.items()) + [('PixelDataRenderer.swift', kit['PixelDataRenderer.swift'])]
              if 'CGColorSpaceCreateDeviceRGB()' in s]
    matched = 0
    if re.search(r'public let iccProfile\s*:', files['FrameRenderBackend.swift']) and \
            'CGColorSpace(iccData: iccProfile as CFData)' in files['FrameRenderBackend.swift']:
        matched += 1
    else:
        problems.append(f'no ICC Profile in FrameRenderRequest: colour output is tagged Device RGB ({", ".join(tagged)})')
    for fname, pat in (('CPUFrameRenderer.swift', r'image\.copy\(colorSpace: space\)'),
                       ('Metal/MetalFrameRenderer.swift', r'colorSpace: isGrayscale \? nil : request\.outputColorSpace'),
                       ('Metal/MetalImageView.swift', r'view\.colorspace = frame\?\.colorSpace')):
        if re.search(pat, files[fname]):
            matched += 1
        else:
            problems.append(f'{fname}: colour output is not tagged with the ICC Profile')
    rep.check('PS3.3 C.11.15.1.1: ICC Profile applied to colour output', matched, problems)


def check_citations(rep, parts, files, metal):
    all_files = dict(files)
    all_files['Metal/FrameRender.metal.txt'] = metal
    dk.check_citations(rep, parts, all_files)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema', required=True, help='directory with partNN_<edition>.xml files')
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--sources', default=os.path.join(ROOT, 'Sources', 'DICOMRenderKit'))
    ap.add_argument('--verbose', action='store_true')
    ap.add_argument('--only', help='run only checks whose name contains this text')
    args = ap.parse_args()

    parts = {}
    for n in (3, 5, 6):
        path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
        parts[n] = nd.Part(path)
        if args.edition not in parts[n].subtitle:
            sys.exit(f'{path}: subtitle {parts[n].subtitle!r} does not name {args.edition}')
        print(f'using {path}: {parts[n].subtitle}')
    parts[16] = parts[6]       # no TID/CID citations in this module; keeps dk.check_citations total
    rep = Report(args.verbose)
    files = dw.read_all(args.sources)
    metal = dw.read(os.path.join(args.sources, 'Metal', 'FrameRender.metal.txt'))
    core = dw.read_all(os.path.join(ROOT, 'Sources', 'DICOMCore'))
    kit = dw.read_all(os.path.join(ROOT, 'Sources', 'DICOMKit'))

    checks = [
        ('voi_functions', lambda: check_voi_functions(rep, parts[3], core)),
        ('width_limits', lambda: check_width_limits(rep, parts[3], core)),
        ('identity', lambda: check_identity_quantisation(rep, parts[3], core)),
        ('modality', lambda: check_modality_before_voi(rep, parts[3], files, kit)),
        ('full_range', lambda: check_full_range_window(rep, parts[3], kit)),
        ('chain', lambda: check_stored_value_chain(rep, parts[3], parts[5], core)),
        ('assembly', lambda: check_sample_assembly(rep, parts[5], files, kit, metal, core)),
        ('planar', lambda: check_planar_configuration(rep, parts[3], metal, files, kit)),
        ('parity', lambda: check_backend_parity(rep, metal, files, kit, core)),
        ('photometric_routing', lambda: check_photometric_routing(rep, parts[3], files)),
        ('photometric_literals', lambda: dk.check_photometric_terms(rep, parts[3], files)),
        ('ybr', lambda: check_ybr(rep, parts[3], kit, files, metal)),
        ('palette', lambda: check_palette_lookup(rep, parts[3], core)),
        ('well_known_palettes', lambda: check_well_known_palettes(rep, parts[6], core)),
        ('spatial', lambda: check_spatial_order(rep, parts[3], files)),
        ('icc', lambda: check_icc(rep, parts[3], files, kit)),
        ('citations', lambda: check_citations(rep, parts, files, metal)),
    ]
    for name, fn in checks:
        if args.only and args.only not in name:
            continue
        fn()

    c = rep.counts
    print(f'\n{c["ok"]} ok, {c["FAIL"]} failing, {c["PEND"]} pending owner approval, '
          f'{c["DEFR"]} deferred to another module')
    sys.exit(1 if c['FAIL'] else 0)


if __name__ == '__main__':
    main()
