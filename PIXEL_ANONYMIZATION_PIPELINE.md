# Pixel Data Anonymization Pipeline

How `dicom-anon` removes burned-in PHI from the **stored pixels** of a DICOM object —
not just its header — across single-frame, classic multiframe, enhanced multiframe,
concatenations, and native/compressed source encodings.

Three cooperating region sources, all part of the Clean Pixel Data option (on by
default since 2026-09-07; `--no-clean-pixel-data` opts out):

1. deterministic strategies (declared Ultrasound Regions, device templates)
2. explicit operator rectangles (`--redact-region`)
3. OCR text detection (`--ocr-mode header|classify`)

**Status:** `[EXISTS]` = shipped today, `[NEW]` = to be built. **All five phases landed 2026-09-04** (branch `feature/pixel-anonymization-pipeline`, local); one open codec-layer issue is noted under Phase 5.

---

## 1. Principles (non-negotiable)

Every design choice below traces back to one of these invariants.

1. **Pixels are actually altered.** PS3.15 E.3 Clean Pixel Data means the stored
   sample values change. Overlays, shutters, presentation states, or cropping do
   not qualify — the identifying bytes would remain in the file.
2. **Region sources UNION, never override.** Every enabled source may only *add*
   to the redaction mask; none may shrink or cancel another's region. A false
   positive blanks background; a false negative leaks PHI — the costs are
   asymmetric, so the pipeline always errs toward blanking more.
3. **Detection and cleaning are separate concerns.** OCR may detect and report
   without modifying pixels. Irreversible pixel modification requires explicit
   cleaning intent (`--clean-pixel-data` or `--redact-region`).
4. **Refuse rather than guess.** When the object declares burned-in content — or
   OCR *detects* text that will not be redacted — and the operator has not
   accepted the risk, the tool errors out rather than writing a falsely clean
   result. `--allow-burned-in-phi` is the explicit escape hatch.
5. **The attestation is earned.** (0028,0301) → `NO` and DCM 113101 are written
   *only* when pixels were actually blanked — never stamped on a pass-through.
6. **Every frame, always.** A resolved region applies to all frames of the
   object. Blanking frame 0 of a cine loop de-identifies one fortieth of it.
7. **Pixel work runs BEFORE header de-identification.** Region planning and PHI
   classification read Manufacturer / Model / Modality / PatientName — attributes
   the header pass deletes. Ordering is a correctness requirement (CTP and
   Presidio document the same dependency).
8. **On-device only.** OCR uses Apple Vision locally. PHI must never be uploaded
   to a cloud OCR service as part of anonymizing it.
9. **Never claim exhaustiveness.** A successful run means the configured
   detectors found and removed identified regions — not that every possible
   visual identity (faces, tattoos, missed text) is gone. Console and audit
   wording must reflect this.

---

## 2. CLI surface

**2026-10-12 — integration with main.** `dicom-anon` applies the current PS3.15
Annex E Basic Profile. `--profile ps315` and `--profile basic` select that same
profile; legacy CLI profiles are rejected and remain available only through the
library API. `--remove` and `--replace` are retained, including tag/keyword parsing,
and are applied to both replacement previews and final headers. `--keep`,
`--regenerate-uids`, and `--detect-text` are not part of the OCR CLI surface.
Clean Pixel Data is on by default; use explicit retention options when migrating
legacy scripts. Newer main rules for dates, descriptors, safe private attributes,
structured content, and file-meta UID synchronization remain in force.

Automatic OCR requires Apple Vision. Linux builds still encounter the existing
JLISwift dependency's Apple Accelerate imports; this integration does not claim
Linux support. See [CLI compatibility and limitations](Sources/dicom-anon/README.md#limitations).

```bash
# Deterministic strategies + OCR (classify), the default
dicom-anon in.dcm -o out.dcm

# Explicit rectangles (repeatable; always applied)
dicom-anon in.dcm -o out.dcm --redact-region 0,0,1024,90 --redact-region 0,700,1024,68

# Aggressive OCR mode: blank every detected glyph
dicom-anon in.dcm -o out.dcm --ocr-mode classify

# Preserving OCR mode: only header-matched / PHI-shaped text; scales survive
dicom-anon in.dcm -o out.dcm --ocr-mode header --text-only --redact-fill white

# Preview what would be blanked, destroy nothing
dicom-anon in.dcm --dry-run

# Header only (refuses files whose pixels may still carry PHI)
dicom-anon in.dcm -o out.dcm --no-clean-pixel-data
```

| Flag | Role | Status |
|---|---|---|
| `--no-clean-pixel-data` | Opt out of Clean Pixel Data (header-only run; refusal contract still applies) | EXISTS (2026-09-07) |
| `--redact-region x,y,w,h` | Operator rectangles; deterministic, reproducible; always applied | EXISTS |
| `--redact-fill black\|white\|N` | Fill for blanked samples | EXISTS |
| `--ocr-mode header\|classify` | OCR failure direction; default `classify` (fails closed) | EXISTS (was `--detect-text-mode`; `all` removed) |
| `--ocr-all-frames` | OCR every frame instead of sampled frames | EXISTS |
| `--text-only` | Blank only the OCR-flagged text (plus `--redact-region`) at its exact position — no banner band | EXISTS |
| `--allow-burned-in-phi` | Write the metadata-scrubbed file anyway; marked Patient Identity Removed = NO | EXISTS |
| `--dry-run` | Print planned regions/verdicts, write nothing | EXISTS |
| `--recompress <codec\|source>` | Re-encode clean pixels post-redaction (§5.3) | EXISTS |
| `--redact-style <blank\|label\|replace>` | What the cleaned region shows (§6.5) | EXISTS |
| `--redact-label <text>` | Custom stamp text for `label` style | EXISTS |

### 2.1 Option semantics

- **Burned In Annotation (0028,0301) policy** (operator decision, 2026-09-07):
  `YES` → clean (refuse if no source locates the text); absent → OCR decides;
  `NO` → trusted, pixels neither inspected nor modified, said so on the verbose
  console and in the audit log. Overlay planes or `--redact-region` override the
  trust. Implemented in `AnonymizationWorkflow.pixelPolicy`.
- `--redact-region` is always applied, even under a trusted `NO`.
- OCR is a region *source* inside Clean Pixel Data; it never runs on its own. With
  cleaning on, every redact verdict is blanked; text the classifier keeps survives
  (and is reported).
- `--ocr-mode header --text-only` = remove exactly the study's own identifiers,
  institution and dates **and nothing else**: no keep-region inversion, no
  device-template strip. Motivating case (2026-09-07): a GE Vivid S70 Doppler frame
  where `classify` blanked the four bands outside the declared regions and `header`
  alone still painted the whole top strip via the generic ultrasound template.
  `--text-only` requires cleaning (validation error with `--no-clean-pixel-data`),
  warns on every run that the band safety net is gone, and refuses with a text-only
  reason when OCR flagged nothing on an image that declares burned-in text.
- `--redact-style replace` needs pixel cleaning (both OCR modes classify).
- **Default is `classify`** (since Phase 3).

### 2.2 OCR modes

Three modes, least → most aggressive, each a subset of the next
(`header ⊆ classify ⊆ all`, pinned by test). Choosing a lower mode can only
preserve more, never protect more.

**`header`** — redact only text that matches the study's own header PHI
(names, IDs, accession, institution/department/station, physicians, operators,
DOB/study dates in any burned rendering, age) or a PHI-shaped pattern (date,
time, ≥5-digit run, mixed alphanumeric ID). Everything else is kept — scales,
legends, units, free annotations. On ultrasound the keep-region inversion (§2.1
strategy b) is **skipped** and any device template strip is **clipped to the
rows above/below the declared Ultrasound Regions bounding box** (never beside
it), because those bands are exactly where GE/Philips draw the velocity scale,
colour bar, its `Soft/.16` label and the time axis the mode exists to preserve. The mode **fails open**: burned-in text the header
never carried (a sticker, a second patient, a RIS-entered name) is not
recognised. Every run says so in the summary; the audit log records
`OCR mode=header`; a header with no harvestable identifiers gets its own
warning. Modality-independent — on CR/DX/CT/MR/XA/SC it changes only the OCR
verdicts (there are no bands there).

**`classify` (default)** — `header` plus PHI-keyword lines (`Pt:`, `DOB`,
`Dr`, `Hospital`…) and **anything not positively allowlisted**; preserves only
confidently allowlisted clinical/technical text (laterality, units, technique
factors, bare scale numerals). Fails closed.

**`all`** — redact every detected text region, no preservation attempted.
Intentionally aggressive: maximum text removal where loss of visible clinical
annotations is acceptable. Not the default, because destroying every annotation
by default costs clinical utility without a safety gain over classify's
uncertain→redact rule.

---

## 3. Pipeline overview

```text
DICOM file bytes
   │
   ▼
[1] Read file ─────────────── DICOMFile.read / force-parse              [EXISTS]
   │
   ▼
[2] Characterize ──────────── frame organization + transfer syntax      [EXISTS]
   │                          single / classic MF / enhanced MF
   │                          native / encapsulated
   ▼
[3] Harvest PHI terms ─────── BEFORE header scrubbing                   [EXISTS]
   │                          PatientName/ID, accession, dates,
   │                          institution, physician/operator names
   ▼
[4] Plan regions (UNION of all enabled sources)
   │    a. explicit --redact-region rectangles                          [EXISTS]
   │    b. US keep-region inversion ((0018,6011) complement)            [EXISTS]
   │    c. device templates (curated modality/vendor/geometry)          [EXISTS]
   │    d. OCR detection + classification                               [EXISTS]
   │
   │    Declared or detected PHI left unredacted → REFUSE (§2.1, §10).
   │    Nothing declared, nothing detected → nothingToDo (pass through).
   ▼
[5] Dry-run gate ───────────── print region table and STOP if requested [EXISTS]
   │
   ▼
[6] Decode Pixel Data ──────── encapsulated → native samples,           [EXISTS]
   │                           every frame (all codecs)
   ▼
[7] Mask regions ───────────── same rects on EVERY frame, fill value,   [EXISTS]
   │                           all samples-per-pixel
   ▼
[8] Re-encode ──────────────── Explicit VR Little Endian; descriptor    [EXISTS]
   │                           updated to the decoded format
   ▼
[9] Strip side channels ────── Icon Image Sequence removed;             [EXISTS]
   │                           overlay planes (60xx) removed
   ▼
[10] Attest ────────────────── (0028,0301)=NO; DCM 113101 in            [EXISTS]
   │                           (0012,0064); basis + provenance note
   ▼
[11] Header de-identification ─ PS3.15 Annex E engine (profile options) [EXISTS]
   │
   ▼
[12] Write anonymized DICOM                                             [EXISTS]
```

Existing implementation anchors:

- Planning: `Sources/DICOMKit/Anonymization/PixelRedactionPlan.swift`
- Execution + attestation: `Sources/DICOMKit/Anonymization/PixelRedactor.swift`
- Masking engine: `Sources/DICOMKit/PixelEditing/PixelEditor.swift`
- Device table: `Sources/DICOMKit/Anonymization/DeviceRedactionTemplates.swift`
- Declared-PHI detection: `ConfidentialityEngine.residualPixelPHIWarnings`
- CLI orchestration: `Sources/dicom-anon/main.swift` (pixel work first, then header) — thin adapter over the shared `PixelCleaningWorkflow` (`Sources/DICOMKit/Anonymization/PixelCleaningWorkflow.swift`), which owns the §2.1 option semantics, the refusal signal (`Report.residualWarnings`) and the dry-run gate, so the contract is tested at the library (`PixelCleaningWorkflowTests`)

New components:

- `Sources/DICOMKit/Anonymization/TextRegionDetector.swift` [EXISTS — Phase 1.1: transform, sampling, Vision detection, unit + Vision tests]
- `Sources/DICOMKit/Anonymization/PHITextClassifier.swift` [EXISTS — Phase 3: header term harvest, fuzzy/pattern/keyword redaction, allowlist keep]

---

## 4. Frame organizations

Rows/Columns are top-level attributes in all three organizations, so one
pixel-space rect set is valid for every frame of an object. What differs is
frame-count discovery, OCR rendering, and functional-group bookkeeping.

### 4.1 Single-frame (CR, DX, SC, single-frame US/CT/MR…)

One frame decoded, masked, re-encoded. OCR operates on frame 0, rendered via
`determineWindowSettings` (the one window policy — never raw stored values,
which blow CT to white and hide the text).

### 4.2 Classic multiframe (US cine, XA runs, NM, legacy MF SC)

- Frame count: (0028,0008) Number of Frames.
- PixelEditor already applies each rect to every frame — invariant #6 by
  construction.
- Default OCR sampling: `{first, middle, last}` — banners are static across a
  loop. Detected rects are unioned, then blanked on **all** frames.
- `--ocr-all-frames` for text that appears only mid-loop (e.g. a stress-echo
  stage label). Slow on long loops; opt-in.

### 4.3 Enhanced multiframe (Enhanced CT/MR/XA/US Volume…)

Uses the shared `Sources/DICOMKit/Multiframe/` layer.

- Geometry: still top-level Rows/Columns — one rect set covers all frames.
- **OCR rendering must honor per-frame VOI.** Resolution order: per-frame
  Frame VOI LUT functional group → shared functional group → top-level fallback.
  Text rendered at the wrong contrast evades detection.
- **Functional groups pass through untouched.** Masking changes only PixelData +
  the descriptor. The invariant `NumberOfFrames == per-frame FG count` must hold
  in the output; the redactor never truncates, pads, or reorders FG content.

### 4.4 Concatenations

A concatenation instance holds only part of the frame set. Text found in part 2
must also be blanked in part 1.

Preferred (directory/batch mode): process all parts in one invocation, detect
across all parts, **union regions across the complete concatenation**, apply the
union to every part.

Minimum (single-file mode): detect the Concatenation UID, warn that the complete
concatenation was not analyzed, never claim exhaustive cleaning.

### 4.5 Frame matrix

| Concern | Single | Classic MF | Enhanced MF |
|---|---|---|---|
| Frame count | 1 | (0028,0008) | (0028,0008) + FG invariant |
| Rect geometry | top-level R/C | top-level R/C | top-level R/C |
| OCR frames scanned | frame 0 | first/mid/last (or all) | first/mid/last (or all) |
| OCR render window | file VOI | file VOI | **per-frame** VOI |
| Mask applied to | the frame | every frame | every frame |
| Side channels | icon, overlays | icon, overlays | icon, overlays |
| Extra bookkeeping | — | sampling | FG counts + concatenation |

---

## 5. Compressed vs uncompressed sources

### 5.1 Uncompressed (native LE/BE)

Samples masked in place in the native buffer; output Explicit VR LE. Bits
Allocated/Stored, High Bit, Pixel Representation, Samples per Pixel, Planar
Configuration and Photometric Interpretation always describe the actual output
buffer.

### 5.2 Encapsulated (JPEG family, JPEG-LS, J2K, HTJ2K, RLE, JPEG XL, deflate)

**Decode → mask → re-emit uncompressed.** Never edit compressed fragments or
coefficients in place:

1. PS3.15 E.3 requires the stored samples to change; coefficient tricks blur
   rather than blank and can leave PHI recoverable.
2. Masking decoded samples while keeping the compressed syntax tag produces a
   file viewers cannot decode (the bug PixelEditor's decode path exists to
   prevent).
3. The output transfer syntax must accurately describe the resulting Pixel Data.

Mechanics (existing, in PixelEditor): `tryPixelData()` decodes **every frame**
through the shared codec layer (BOT/fragment walking included); photometric
follows the decode (YBR JPEG/J2K → RGB, descriptor + (0028,0004) updated with
the buffer — never relabeled independently); output FMI set to Explicit VR LE.

### 5.3 Output encoding and `--recompress` [EXISTS — Phase 5, 2026-09-04]

Default output (no flag) stays **Explicit VR LE**: universally readable (the
Horos compatibility notes are the proof) and never adds generation loss without
the operator asking. The consequence — a long compressed cine grows
substantially when re-emitted uncompressed — is documented in `--help`.

`--recompress` hands the clean pixels to the existing `CompressionManager`
strictly **after** redaction:

```text
decode → mask → attest → re-encode (source syntax or named codec)
```

```bash
--recompress source      # mirror the input's transfer syntax (encoding parity)
--recompress jpeg-ls     # or force any specific codec
```

**`--recompress source` — encoding parity.** The source transfer syntax is
captured at stage [2] and re-targeted at stage [8]. Encoders exist for every
still-image syntax the toolkit decodes (`CompressionManager.codecMap`), so
parity holds across the board:

| Source | Output | Fidelity |
|---|---|---|
| Implicit / Explicit VR LE | same | exact — pixels outside regions byte-identical |
| Deflate | Deflate | exact (inflate → mask → re-deflate) |
| RLE / JPEG-LS / JPEG lossless / J2K .90 / HTJ2K reversible / JXL Modular | same codec, same UID | exact — lossless round-trip |
| JPEG baseline/extended, J2K .91 lossy, HTJ2K lossy, JXL VarDCT | same codec, lossy re-encode | same syntax, **second-generation loss** |

Caveats, stated honestly:

1. **Same syntax ≠ same bytes.** Lossless sources decode to identical pixels
   outside the redacted regions, but the compressed bitstream differs (different
   encoder, different fragmenting). Consumers see identical images; a byte-diff
   does not.
2. **Lossy → lossy re-quantizes the whole image**, not just the banner —
   unavoidable. The tool does it as asked, prints a one-line warning, and
   updates Lossy Image Compression Ratio/Method (0028,2112/2114) for the new
   generation so the header stays honest.
3. **JXLSwift VarDCT is RGB-only**: a grayscale lossy-JXL source falls back to
   lossless Modular on the same general `.112` UID. Syntax matches, the lossy
   character doesn't. Warn.
4. **Non-encodable syntaxes** (MPEG/H.264 video, JPIP-referenced, retired
   Explicit VR BE if BE writing is not offered): fall back to Explicit VR LE
   with a clear console line — never a silent substitution, never a refusal to
   redact.

The blanking oracle gains one step under `--recompress`: reopen the output and
verify the redacted rects are still blank after the codec round-trip (a flat
black rectangle survives lossy compression as a flat black rectangle). The
audit line records the re-encode ("re-encoded to source syntax
1.2.840.10008.1.2.4.70").

### 5.4 Encoding matrix

| Source | Decode | Mask | Output syntax | Photometric |
|---|---|---|---|---|
| Native LE/BE | none | in place | Explicit VR LE | unchanged |
| RLE | full | native buffer | Explicit VR LE | unchanged |
| JPEG family / JPEG-LS | full | native buffer | Explicit VR LE | YBR → RGB with buffer |
| J2K / HTJ2K / JPEG XL | full | native buffer | Explicit VR LE | per decode |
| Deflate | inflate | native buffer | Explicit VR LE | unchanged |

---

## 6. OCR detection and PHI classification [EXISTS]

OCR is a **region detector**, not the final anonymization decision by itself.

```text
sampled frame indices
   ↓
render OCR-friendly image        (1:1, full frame — see §6.2)
   ↓
Vision VNRecognizeTextRequest(.accurate)
   ↓
text + normalized bbox + confidence + frame index
   ↓
coordinate conversion (flip Y, denormalize)
   ↓
safety dilation (default 4 px)
   ↓
PHI classification (classify mode)
   ↓
redaction regions → union into the plan
```

The OCR-friendly rendering is temporary and exists only to improve detection.
**Redaction always runs on the original decoded pixel buffer.**

### 6.1 Rendering for OCR

Raw stored values are unsuitable for OCR (CT range, MR intensity spread —
windowing decides whether burned text is even visible). So: decode the frame,
render an 8-bit representation via the modality-appropriate windowing path
(per-frame VOI for enhanced MF, §4.3), OCR that image, map coordinates back.

### 6.2 Coordinate transform — constrained by construction

The OCR rendering is **always a 1:1, unrotated, uncropped render of the full
frame** — exactly what the existing render path produces. This is a deliberate
constraint: it reduces the transform to flip-Y + denormalize (scale by
Columns/Rows) + dilation, and eliminates rotation/crop/resize mapping code — the
worst failure class this feature has is OCR correctly finding a name while a
buggy transform blanks the wrong pixels under an earned 113101. The transform is
unit-tested independently before integration (§11.4), including non-square
Rows/Columns.

### 6.3 `TextRegionDetector`

- Apple Vision, `.accurate`, on-device.
- Returns recognized text, normalized bbox, confidence, frame index.
- Dilates each rect by a configurable margin (default 4 px) — Vision boxes hug
  the glyphs and antialiased fringes stay legible.
- Unions regions across sampled frames per file.
- Platform: Apple platforms only. Elsewhere, `--detect-text` is a **hard
  error** — never a silent "no text found."

### 6.4 `PHITextClassifier` (classify mode)

**Term harvest** (stage [3], before scrubbing):

- Direct: PatientName (each PN component — "SMITH^JOHN" must match
  "John Smith", "SMITH, JOHN", "J SMITH"), PatientID + other IDs,
  AccessionNumber, InstitutionName, referring/performing/operator names.
- Derived: birth/study/series dates rendered in common burned formats
  (`MM/DD/YYYY`, `DD-MON-YYYY`, `YYYYMMDD`, …), patient age, MRN with and
  without leading zeros.
- Patterns (no header source needed): date-shaped strings, ID-like long digit
  runs, text adjacent to trigger keywords (`Pt:`, `Name:`, `DOB:`, `Acc#`,
  `MRN`).

**Fuzzy matching**, never exact equality: normalize both sides (uppercase,
strip punctuation/whitespace, drop PN separators), then normalized-substring +
bounded edit distance. Accounts for OCR substitutions `O↔0`, `I↔1`, `S↔5`.

**Verdicts** — two, and the failure direction is pinned:

| Verdict | Action | Rule |
|---|---|---|
| Redact | blank | PHI match, pattern match, PHI-keyword proximity, or **anything uncertain** — low OCR confidence never lets text pass |
| Keep | preserve | ONLY text positively matched against the allowlist: laterality (`L`/`R`/`RT`/`LT`), units (`cm`/`mm`), technique factors (`kVp`/`mAs`), bare scale numerals |

**Scale-zone tick rule (2026-09-07).** The recognizer is Apple Vision
(`VNRecognizeTextRequest`, `.accurate`, no language correction); it returns a
single candidate and word-level boxes only, so a ruler tick that touches a
numeral comes back fused into the word — `10` + tick → `10y` at confidence
1.00, `15` + tick → `15}` (verified on a GE Vivid S70 Doppler frame; masking
the stroke that crosses the box edge and re-reading gives `10`, but the same
re-read turns `15}` into `15y`, so a second OCR pass is not a fix). The
classifier therefore takes the file's own Sequence of Ultrasound Regions as
`scaleZones`: a short numeral (≤3 integer digits, optional sign/decimal) with
exactly ONE trailing non-digit glyph whose box intersects a declared region is
kept as a scale numeral. Outside every declared region the same text (`72y` in
a banner) is still redacted, and header matches, PHI patterns, keywords and low
confidence still win inside the zone. Pinned in `PHITextClassifierTests`.

Redact by default; keep only what is provably safe. Classification can only make
redaction *less* aggressive than `all` — text Vision missed never reaches the
classifier — so classify mode is never safer than `all`, only more preserving.

**`header` policy** (`PHITextClassifier.Policy.header`): runs only the first
two steps — harvested-term match and PHI-shaped pattern — and keeps everything
else with reason `header mode: no header match or PHI pattern`. Low OCR
confidence still tries the matches (a fuzzy hit on garbled PHI is the safe
direction) and otherwise keeps, noting the confidence. Matched tags are still
reported, so `replace` style works with it. The console's kept count says how
many kept regions lie inside blanked regions anyway (`N kept (…; M of them
inside blanked regions anyway)`) — "kept" must never be read as "survives".

### 6.5 Redaction styles — what the cleaned region shows [EXISTS]

The primary target workflow is **classify mode + `replace`**: clinical text
stays untouched, and only PHI regions are anonymized in place.

All styles share one safety-critical mechanic — **blank-then-draw**: the entire
detected region is first filled with the fill value (this is what destroys the
original glyphs), and only then is any replacement rendered into the blanked
box. The replacement is cosmetic on top of a completed redaction; the original
text is 100% gone regardless of style. PS3.15 is satisfied by the blanking (the
stored identifying values are removed), so 113101 stays earned in every style.

| Style | Region content after cleaning | Needs classifier | Phase |
|---|---|---|---|
| `blank` (default) | fill value only | no | 1 ✅ |
| `label` | fixed stamp (`REDACTED` / `--redact-label` text) — works for every verdict including uncertain; a reviewer sees "cleaned deliberately", not a suspected rendering bug | no | 1 ✅ (`RedactionLabelRenderer` → `PixelOperation.stamp`; too-small regions fall back to blank and are listed in `Outcome.labelFallbackRegions` + the console) |
| `replace` | semantic replacement: burned name → **anonymized** name, burned date → **shifted** date, burned ID → pseudonym | yes | 4 ✅ (`ReplacementMapping.derive(original:deidentified:)` reads the header engine's own output from an in-memory preview of the configured pass; only classified matches with a mapped value for every matched attribute are drawn; note: PS3.15 Basic **zeroes** PatientName/ID and the integrated main rules clear birth date even with Modified Dates; those regions use the fallback label instead of restoring original values) |

Rendering: CoreGraphics/CoreText glyphs mapped to stored values at the image's
real bit depth (foreground = a bright stored value, background = the fill);
drawn identically on every frame; survives `--recompress` like any other pixels.

**Rules for `replace` (each one is a leak or integrity bug if broken):**

1. **Replacement values come ONLY from the header de-identification engine's own
   mapping** — never invented separately. The pixels and the header must tell
   the same story; header `ANON-0042` with pixels `ANON-0117` is a
   data-integrity bug.
2. **Only classified regions get semantic replacement.** A date gets the shifted
   date only when `--shift-dates` is active; if the header policy *removes*
   dates, the pixels get blank/label too — pixels must never retain information
   the header policy removed.
3. **Uncertain regions never get replacement** — there is nothing truthful to
   substitute. Blank or label only.
4. **The detection oracle still applies**: OCR of the output must find the
   replacement text and none of the original strings.
5. Region too small to render legibly → fall back to blank **with an audit
   note**, never silently.

Honest limits: this is not reversible pseudonymization in the pixels — the
burned-in original is destroyed; reversibility (if a trial needs it) lives in
the header engine's mapping table. Replacement text is rendered to fit the
blanked box, not to imitate the device's font/layout — deliberately, so output
never masquerades as original acquisition rendering.

### 6.6 Plan integration

`PixelRedactionPlan.Basis.textDetection` case. [EXISTS — Phase 1.2]

```text
finalMask = explicit ∪ keepRegionInversion ∪ deviceTemplates ∪ OCR
```

No source may remove another source's region. The `.unresolved` refusal message
gains `--detect-text` as a suggested way out alongside `--redact-region`.

Each region retains provenance: source basis, rect, originating frame(s), and
for OCR: confidence, verdict, reason.

---

## 7. Dry-run and audit trail

`--dry-run` prints the full region table and writes nothing:

```text
Frame 0:
  OCR  rect=12,8,180,32   verdict=redact  reason=matched PatientName   conf=0.98
  OCR  rect=800,20,45,24  verdict=keep    reason=allowlist: laterality conf=0.94
Final:
  1 explicit region + 2 OCR regions = 3 unioned regions
  Frames affected: all (47)
  Pixel modification: YES
```

**PHI-safe logging.** Persistent audit logs never contain full recognized
strings — truncated text or a one-way hash, plus verdict, reason, confidence,
rect, frame index. The audit log must not become a second PHI store.

**Console wording.** Report what was done, never claim proof of cleanliness:

> `OCR: 7 candidate regions; 5 selected for redaction across 3 sampled frames.`

not "image is now completely clean." The provenance note records
"OCR text detection (Vision, N regions)" — 113101 is earned because pixels were
genuinely altered, but the note must not imply exhaustiveness (principle #9).

---

## 8. Side channels and non-text survivors

Pixel masking alone does not remove all image-associated PHI. Handled in stage [9]:

| Survivor | Why it leaks | Action |
|---|---|---|
| Icon Image Sequence (0088,0200) | thumbnail derived *before* cleaning still shows the text | **removed** (regeneration would need a render policy the redactor deliberately does not own) |
| Overlay planes (60xx,3000/…) | renderers burn overlay graphics into the displayed image | plane elements **removed outright**, unconditionally |
| Burned In Annotation (0028,0301) | stale `YES` misleads downstream | set `NO` only when blanking occurred |
| De-identification Method Code Seq (0012,0064) | consumers need provenance | DCM 113101 appended only when earned |

Out of scope: free-text descriptors, private tags, curves (the header engine's
job); and non-text pixel PHI — faces, tattoos, other visual identity — for which
`--redact-region` remains the deterministic operator mechanism.

---

## 9. Failure modes and refusals

| Situation | Behavior |
|---|---|
| Declared burned-in PHI, no region source resolves | **error** — never silent pass-through |
| OCR detects text; cleaning not requested; `-o` given | **error** (detection feeds the refusal, §2.1) unless `--allow-burned-in-phi` |
| OCR detects text; no `-o` | inspection: report and exit |
| Operator accepts dirty pixels | `--allow-burned-in-phi`: file written, Patient Identity Removed = NO |
| Nothing declared, OCR off, no template | `nothingToDo` — pass through (the blind spot OCR closes) |
| `--detect-text` on a platform without Vision | **hard error**, never a no-op |
| Invalid rectangle / rect outside frame bounds | validation error at parse time |
| Enhanced FG count mismatch after rewrite | invariant violation — error, never emit (`PixelRedactionError.functionalGroupMismatch` / `.functionalGroupsAltered`) [EXISTS] |
| Concatenation part processed alone | warn: cross-part OCR coverage incomplete (`Report.warnings`, never a refusal) [EXISTS] |
| Decode failure | error — never write partially cleaned output |
| Re-encode failure | error — never write a falsely attested output |

---

## 10. Test plan

### 10.1 Fixtures (synthetic, committed)

Known burned-in text drawn into Pixel Data: single-frame SC (native + JPEG
baseline + RLE), classic multiframe US cine (native + JPEG baseline), enhanced
CT and enhanced MR (native + J2K/HTJ2K where supported) with per-frame VOI that
differs across frames, a concatenation pair, tilted/small text, multiple text
locations, and clinical non-PHI annotations (laterality, scale, kVp).

### 10.2 Oracles

1. **Blanking**: every pixel inside each planned rect equals the fill value on
   *every* frame; pixels outside the union are unchanged relative to the decoded
   source (apart from required representation/photometric conversion) — masking
   must not disturb anatomy.
2. **Detection round-trip**: OCR the *output*; planted PHI strings are no longer
   detectable; allowlisted text survives in classify mode; `all` mode removes it.
3. **Attestation**: 113101 + (0028,0301)=NO present iff regions were blanked;
   pass-through files never falsely attested; `--allow-burned-in-phi` output
   remains marked not clean.

### 10.3 Coordinate transform (pre-integration)

Flip-Y, denormalization, dilation clamping, non-square Rows/Columns. (Rotation/
crop/resize cases deliberately absent — the 1:1 render constraint in §6.2 makes
that code not exist.)

### 10.4 Enhanced multiframe invariants

`NumberOfFrames == per-frame FG count` in the output; shared and per-frame FGs
byte-stable; no frame dropped or duplicated.

### 10.5 Classifier pins

Fuzz table (`SMITH^JOHN` ↔ "J. Smith"/"John Smith"/"SMITH, JOHN", `O↔0`,
`I↔1`); uncertain → redact; allowlist keeps `R`/`cm`/`kVp` in classify mode;
`all` mode blanks the same text; date/ID patterns fire without header terms.

Redaction styles: `label` stamps every redacted region; `replace` output's
burned name/ID/date equals the header engine's anonymized values for the same
file (pixels and header tell one story); a date region is replaced only under
`--shift-dates`, else blanked; uncertain regions never carry replacement text;
in all styles OCR of the output finds no original string.

### 10.6 Compression matrix

Each source syntax in §5.4: open → decode → detect → mask → write → reopen →
verify photometric/descriptor and that redacted regions carry no PHI. With
`--recompress source`: additionally assert the output transfer syntax UID equals
the source's, the rects are still blank after the codec round-trip, lossless
sources decode byte-identically outside the mask, and lossy sources carry
updated (0028,2112/2114).

### 10.7 Dry-run and platform

Dry-run: table printed, no output file, input untouched, no persistent log
contains full OCR strings. Platform: Vision available → normal; unavailable →
explicit failure; manual-rectangle workflow deterministic regardless of OCR.

Run: `swift test --filter DICOMAnonTests` (+ `AnonRoundTripTests`). Rebuild the
release binary after DICOMKit changes before manual CLI verification.

---

## 11. Build order

**Phase 1 — OCR safety core**
1. ✅ `TextRegionDetector` + coordinate-transform unit tests (transform first). (2026-09-04)
2. ✅ `Basis.textDetection` + plan union. (2026-09-04)
3. ✅ `--detect-text` detection-only behavior + refusal integration (§2.1). (2026-09-04; `--allow-burned-in-phi` output is stamped Patient Identity Removed = NO / Burned In Annotation = YES)
4. ✅ `--dry-run` region table. (2026-09-04)
5. ✅ `--clean-pixel-data --detect-text` end-to-end (interim `all` semantics). (2026-09-04; verified on the release-style banner fixture: OCR of the output finds nothing on any of 5 frames)
6. ✅ `--redact-style blank|label` + `--redact-label` (blank-then-draw mechanic). (2026-09-04; verified on the binary: OCR of a labelled output reads only the stamp)

**Phase 2 — Frame coverage** ✅ (2026-09-04)
6. ✅ Classic MF sampling (first/middle/last) + `--ocr-all-frames`. (shipped in Phase 1 via `TextRegionDetector.sampledFrameIndices`; pinned by a mid-loop-only banner test: sampling misses it, `--ocr-all-frames` finds it, and the region is then blanked on every frame)
7. ✅ Enhanced MF per-frame VOI rendering. (the shared `renderFrameForExport` already resolves Frame VOI LUT → shared → top-level per frame; pinned by a 16-bit Enhanced MR fixture whose frame 1 window blacks the text out — detections land on frames 0/2 only. Post-rewrite invariant `NumberOfFrames == per-frame FG count` + byte-stable shared/per-frame FGs is now enforced by `PixelRedactor.checkFunctionalGroupInvariant` — a violation refuses to emit)

**Phase 3 — Classification** ✅ (2026-09-04)
8. ✅ PHI term harvesting from the original header (`PHITextClassifier.harvestTerms`: PN components + joined/initial forms, IDs with/without leading zeros, accession, institution words, station, 22 burned date renderings, age).
9. ✅ `PHITextClassifier`: OCR-confusion folding + bounded edit distance, date/time/ID/mixed-alphanumeric patterns, PHI keyword proximity, positive allowlist (laterality, units incl. glued `120KVP`, technique/display labels, ≤4-digit numerals); uncertain → redact.
10. ✅ Default `classify`; `=all` stays the explicit aggressive mode (workflow: only redact verdicts contribute regions; keeps never count as unredacted leftovers).
11. ✅ Audit verdict lines (PHI-safe): `Report.auditLines` → `Anonymizer.recordPixelAudit` → `--audit-log` (truncated text + length only; verified no name reaches the log).

**Phase 4 — Complete object coverage + semantic replacement** ✅ (2026-09-04)
12. ✅ Concatenation cross-part union in directory/batch mode + single-file warning. (2026-09-04; `PixelCleaningWorkflow.sweep` + `ConcatenationSweep` pre-pass in `dicom-anon --recursive`, `Options.presetDetectedRegions` unioned into every part, `isComplete` needs every declared part; verified on the binary: a clean-looking part 1 is blanked with part 2's regions)
13. ✅ `--redact-style replace` (§6.5): values from the header engine's mapping,
    date replacement gated on `--shift-dates`, uncertain → blank/label,
    too-small-region fallback with audit note. (2026-09-04; `PHITextClassifier.classifyDetailed` reports matched attributes in text order; `PixelRedactor.Replacement` per region; CLI previews the header pass with a throwaway engine; verified on the binary: header and pixels both read `ANONYMOUS <32-hex pseudonym>`; requires `--detect-text` classify)
14. ✅ Expanded compression/photometric regression tests. (2026-09-04; `PixelRedactionCompressionMatrixTests`: 18 cases — explicit/implicit LE, deflate, RLE (8/16-bit/RGB), JPEG baseline (gray/RGB), JPEG lossless, JPEG-LS, J2K lossless+lossy, HTJ2K, JPEG XL — each: detect → decode → mask every frame → Explicit VR LE with a descriptor matching the buffer, pixels outside the mask equal the decoded source, no detectable text, attestation earned. Two pre-existing bugs found and fixed: (a) the parser's deflate inflate truncated silently at 4× the deflated size — now streamed; (b) PixelEditor re-emitted a deflated source raw under a still-deflated File Meta. Native Implicit VR sources are now re-emitted Explicit VR LE by the redactor as §5.1 specifies.)

**Phase 5 — Output encoding parity** ✅ (2026-09-04)
14. ✅ `--recompress <codec>` + `--recompress source` (§5.3), only after the clean
    uncompressed path is proven: source-syntax capture, lossy regeneration
    warning + (0028,2112/2114) update, JXL grayscale and non-encodable
    fallbacks, post-recompress blanking verification. (`PixelCleaningWorkflow.recompress` runs strictly after redaction + attestation and hands the clean bytes to the shared `CompressionManager`; `source` resolves the codec from the input UID honouring the declared lossy state; encode failure or a non-encodable syntax falls back to Explicit VR LE with a note; `verifyBlankAfterRecompression` reopens, decodes and re-checks every rect on every frame (exact for lossless; inset + tolerance for lossy) and refuses to write otherwise; console/audit record the re-encode. Verified on the binary: RLE source parity (same UID, rects blank, anatomy intact), JPEG baseline lossy with the second-generation warning and updated (0028,2110/2112/2114).)

**Open codec-layer issue (not part of this plan):** the JPEG 2000 *lossy* (.91) path in J2KSwift is unreliable in this build — a metal-backend lossy encode decodes cleanly in pydicom/OpenJPEG but as noise in our decoder, and `--quality maximum` fails its own round-trip validation. The compression matrix records this as a loud known-issue skip (decode-fidelity precheck) rather than a redaction failure; JPEG 2000 lossless is unaffected and required to pass.

---

## 12. Implementation contract (summary)

```text
DETECTION      OCR may detect without modifying.
CLEANING       Pixel modification requires explicit cleaning intent.
REFUSAL        Detected-but-unredacted PHI blocks output (escape: --allow-burned-in-phi).
REGIONS        All region sources are unioned; none shrinks another.
FRAMES         A resolved region is applied to every frame.
OCR            Detect on a 1:1 OCR-friendly rendering; redact the original buffer.
CLASSIFY       PHI and uncertain text are redacted; only allowlisted text survives.
STYLE          Blank first, always; label/replace draw only into an already-blanked region.
REPLACE        Replacement values come from the header engine's mapping alone.
COMPRESSION    Decode → redact → valid output; recompress (incl. source parity) after, never before.
ORDER          Pixel work precedes header de-identification.
ATTESTATION    Never claim clean pixels unless pixels were actually changed.
AUDIT          Record what was done without creating a second PHI store.
HONESTY        Report actions, never exhaustiveness.
```
