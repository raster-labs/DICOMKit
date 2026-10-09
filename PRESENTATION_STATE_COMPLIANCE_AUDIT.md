# Presentation State Compliance Audit — GSPS / CSPS / PCSPS vs DICOM 2026a

**Scope:** DICOMKit Softcopy Presentation State implementation — `Sources/DICOMKit/PresentationState/`, `Sources/DICOMPrintKit/PresentationState/`, and the DICOMStudio viewer paths that consume them.
**Mode:** Read-only audit. No source code was modified.
**Date:** 2026-09-25 · **Branch:** `feature/dicom-tag-modality-audit` @ `278a8b2`

## Method

- **Standard text.** Frozen NEMA DocBook for **2026a**: PS3.3, PS3.4, PS3.5 and PS3.6, fetched from `dicom.nema.org/medical/dicom/2026a/source/docbook/`. Each file's subtitle was confirmed to read "2026a". Every requirement cited below was read from that text, not from memory or from code comments.
- **Executable check.** A throwaway probe package, kept in the session scratchpad and not in the repo, wrote three presentation states through the public API `PresentationStateStore.save(...)`. It used synthetic identifiers only, and wrote:
  - a CT "fit" view as GSPS, with an arrow and a text label;
  - the same CT view as PCSPS, with the Hot Iron palette;
  - an RGB endoscopy image (VL Endoscopic, `…77.1.1`) with a text label.

  Each object was checked with **DCMTK `dcmpschk`** and inspected with `dcmdump`. Findings marked **[probe]** were reproduced in those bytes.
- **Verdicts.**
  - **CONFIRMED** means the code path and the standard text were both read, and for [probe] items the output bytes match.
  - **PLAUSIBLE** means the conclusion follows from the standard's conceptual model, but no single normative sentence states it for this IOD.

### Standard section map (2026a)

| IOD | SOP Class UID | PS3.3 section |
|---|---|---|
| Grayscale Softcopy PS (GSPS) | 1.2.840.10008.5.1.4.1.1.11.1 | A.33.1 |
| Color Softcopy PS (CSPS) | 1.2.840.10008.5.1.4.1.1.11.2 | A.33.2 |
| Pseudo-Color Softcopy PS (PCSPS) | 1.2.840.10008.5.1.4.1.1.11.3 | A.33.3 |
| Pipeline and behaviour | — | PS3.4 Annex N.2 |

The code comments cite the wrong sections: A.33.3/A.33.4 or A.34/A.35/A.36 for CSPS, PCSPS and Blending. See NC-19.

---

## 1. Supported Features

### 1.1 SOP Class support

| Capability | GSPS (…11.1) | CSPS (…11.2) | PCSPS (…11.3) |
|---|---|---|---|
| SOP Class registration (UID constants, storage list) | ✅ `PresentationState.swift:447`, `DICOMDictionary/StorageSOPClasses.swift` | ✅ same | ✅ same |
| Read (DICOM file → data set) | ✅ | ✅ | ✅ |
| Parse (data set → model) | ✅ `GrayscalePresentationStateParser` | ⚠️ Partial: geometry and annotations only. ICC is not read, and the result is typed as `GrayscalePresentationState`. | ⚠️ Partial: palette read through `DataSet.paletteColorLUT()` and `PseudoColorPalette.matching`. The `PseudoColorPresentationState` model is never populated. |
| Write (model → data set) | ✅ `GrayscalePresentationStateBuilder` | ❌ No builder | ✅ `PseudoColorPresentationStateBuilder` |
| Save (one PR series per study) | ✅ `PresentationStateStore.save` | ❌ | ✅ chosen when a non-grey palette is set |
| Export (conformant `.dcm` Part 10 file, Explicit VR LE) | ✅ | ❌ | ✅ |
| Import (adopt a study's existing PR objects) | ✅ `StudyPresentationStateAdoption`, `PresentationStateStore` adoption | ⚠️ Accepted, but the ICC profile is dropped | ✅ |
| Viewer application support (DICOMStudio) | ✅ window, zoom/pan, rotate/flip, invert, annotations, shutters (as overlays) | ⚠️ Geometry and annotations only, no colour management | ✅ palette, window, geometry, annotations |
| Headless renderer (`PresentationStateApplicator`) | ⚠️ See NC-9 and NC-10 | ❌ Returns nil for colour images | ❌ No palette stage |

### 1.2 Feature-level detail

| Feature | Status | DICOM reference (2026a) | Implementation location |
|---|---|---|---|
| Presentation Series: Modality = PR | ✅ Correct | PS3.3 C.11.9 | `GrayscalePresentationStateBuilder.swift` (`modality`) |
| Content Label (CS, ≤16 characters, uppercase-folded) | ✅ Correct | PS3.3 Table 10-12 | `GrayscalePresentationStateBuilder.contentLabel(from:)` |
| Content Description, Instance Number, Presentation Creation Date/Time | ✅ Written by the store path | PS3.3 C.11.10, Table 10-12 | `buildDataSet`, `PresentationStateStore.save` |
| Referenced Series Sequence and Referenced Image Sequence (with frame numbers) | ✅ Correct | PS3.3 C.11.11, Table C.11.11-1b | `referencedSeriesElement` |
| Softcopy VOI LUT Sequence: Window Center/Width, Explanation, VOI LUT Function | ✅ Written inside (0028,3110) | PS3.3 C.11.8, C.11.2 | `applyVOILUT` |
| Softcopy Presentation LUT: IDENTITY / INVERSE | ✅ Always present in GSPS | PS3.3 C.11.6; PS3.4 N.2.1.4 | `buildDataSet` |
| Presentation LUT absent in PCSPS | ✅ Removed; inversion is baked into the palette | PS3.3 A.33.3.3 ("shall not be present") | `PseudoColorPresentationStateBuilder.buildDataSet` |
| Spatial Transformation: Image Rotation (US, 0/90/180/270) and Image Horizontal Flip | ✅ Correct VR and values. The viewer applies rotation first, then flip, as C.10.6 requires. A vertical flip is folded into H-flip + 180°. | PS3.3 C.10.6 | `ViewerPresentationStateBridge.spatialTransformation`, `ViewerPresentation.swift:91-95` |
| Displayed Area: TLHC/BRHC 1-based (SL), SCALE TO FIT, Presentation Pixel Aspect Ratio 1\1 | ✅ Correct when present | PS3.3 C.10.4 | `displayedAreaElement`, `ViewerPresentationStateBridge.capture` |
| Zoom / Pan → Displayed Area → Zoom / Pan round trip | ✅ | PS3.3 C.10.4 | `ViewerPresentationStateBridge.capture` / `restore` / `zoomAndPan` |
| Graphic Annotation Sequence: Graphic Layer, Referenced Image Sequence and Frame | ✅ | PS3.3 C.10.5 | `graphicAnnotationElement`, `PrintOverlayAnnotationGSPS.graphicAnnotations` |
| Graphic Types POINT, POLYLINE, INTERPOLATED, CIRCLE, ELLIPSE (read and write) | ✅ The full enumerated set | PS3.3 C.10.5 (Graphic Type enum) | `PresentationGraphicType`, `graphicObjectItem`, `parseGraphicObject` |
| PIXEL coordinates (0.0\0.0 = TLHC of the TLHC pixel) | ✅ Normalised × Columns/Rows | PS3.3 C.10.5 (Bounding Box Annotation Units) | `PrintOverlayAnnotationGSPS.textObject` / `shapeObject` |
| DISPLAY units | ✅ Read | PS3.3 C.10.5 | `AnnotationUnits.display` |
| Text Object: bounding box and justification, Anchor Point with visibility | ✅ | PS3.3 C.10.5 | `textObjectItem`, `parseTextObject` |
| Arrow | ⚠️ Written as two open POLYLINEs (shaft and head). This is conformant as a "simple graphic" rendering, but the Compound ARROW (MF-4) is not written. | PS3.3 C.10.5.1.3 (ARROW) | `PrintOverlayAnnotationGSPS.arrowObjects` |
| Graphic Layer: name, order, description | ✅ | PS3.3 C.10.7 | `graphicLayerElement` |
| Display Shutter: RECTANGULAR / CIRCULAR / POLYGONAL / BITMAP (read) | ⚠️ Read, with defects (NC-6, NC-7) | PS3.3 C.7.6.11, C.11.12 | `parseDisplayShutters` |
| Palette Color LUT module: 8-bit packed OW data, descriptor US/SS, 65536 → 0 | ✅ Encoding correct | PS3.3 C.7.9, C.7.6.3.1.5 | `applyPaletteColorLUT` |
| Palette Color LUT UID, only for the unmodified Annex B table | ✅ Correct use | PS3.3 C.7.9.1; PS3.6 Annex B | `applyPaletteColorLUT` |
| Well-known palettes: Hot Iron, PET, Hot Metal Blue, PET 20 Step, Spring, Summer, Fall, Winter | ✅ All 8 PS3.6 Annex B palettes | PS3.6 Annex B | `DICOMCore/DICOMWellKnownPalettes.swift` |
| Other palettes (Rainbow, Jet, Viridis and similar, 20 total) | ✅ Carried as explicit LUT data with no UID. This is correct because they are not standard palettes. | PS3.3 C.7.9 | `DICOMCore/PseudoColorPalette.swift` |
| ICC Profile module in PCSPS: (0028,2000) and Color Space SRGB | ⚠️ Present, but the profile class is wrong (NC-5) | PS3.3 C.11.15 | `SRGBICCProfileWriter` |
| Immutability: re-save produces a new SOP Instance UID | ✅ | PS3.4 N.2 ("shall never be modified … only a derived SOP Instance") | `PresentationStateStore.save` (delete and re-create) |
| Window presets (soft tissue, lung, bone, user) | ⚠️ App-level only (`DICOMVolumeViewerViewModel`, print cell editing). A PR stores only the resulting window. This is correct because DICOM has no "preset" concept. | PS3.3 C.11.2 (Window Center & Width Explanation) | DICOMStudio |

---

## 2. Missing Features

| ID | Feature | Priority | DICOM reference (2026a) | Required changes |
|---|---|---|---|---|
| MF-1 | **CSPS writer**: build, save and export Color Softcopy PS | **High** | PS3.3 A.33.2 (ICC Profile M; no Modality, VOI or Presentation LUT modules) | New `ColorPresentationStateBuilder` (snippet S-10). `PresentationStateStore.save` must pick the class from Photometric Interpretation (NC-3). |
| MF-2 | **Modality LUT module write** (Rescale Slope, Intercept and Type, or Modality LUT Sequence) | **Critical** | PS3.3 A.33.1.3, A.33.3.3 (C: "Required if a Modality LUT is to be applied"); PS3.4 N.2.1.1 | Snippet S-1 (see NC-1) |
| MF-3 | **Display Shutter write**. Shutters are read-only, so an imported view that is re-saved loses its shutters. | Medium | PS3.3 C.7.6.11, C.11.12 (Shutter Presentation Value 1C; CIELab 1C for non-GSPS) | Snippet S-11 |
| MF-4 | Compound Graphic Sequence (0070,0209): ARROW, RULER, RECTANGLE, ELLIPSE, and others | Medium | PS3.3 C.10.5 (Type 3) and C.10.5.1.3 | Write an ARROW compound item linked by Compound Graphic Instance ID (0070,0226) to the existing polylines. Parse and render on import. |
| MF-5 | Per-object style: Line Style, Text Style and Fill Style sequences (Table C.10-5a/b/c), including per-annotation colour | Medium | PS3.3 C.10.5.1.3.12–14 | The comment in `PrintOverlayAnnotationGSPS.swift:9-11` says DICOM has "no per-annotation colour". That is not correct for 2026a. Per-annotation colour can be written through Line Style and Text Style (CIELab). |
| MF-6 | Graphic Group module (Graphic Group Sequence (0070,0234), Graphic Group ID) | Low | PS3.3 C.10.11 (U) | Optional. Parse it so imported grouped measurements stay together. |
| MF-7 | MATRIX annotation units (tiled / WSI images) | Medium (pathology) | PS3.3 C.10.5 (MATRIX) | Add `case matrix = "MATRIX"` to `AnnotationUnits`. At the moment `AnnotationUnits(rawValue:)` silently turns MATRIX into PIXEL (see NC-13). |
| MF-8 | Bitmap Display Shutter, Overlay Plane and Overlay Activation modules | Low | PS3.3 C.7.6.15, C.9.2, C.11.7 | The parser reads Shutter Overlay Group but the renderer returns `false` (`DisplayShutter.contains`, `.bitmap`). Overlay activation is not modelled. |
| MF-9 | Mask / Presentation State Mask (multi-frame subtraction) | Low | PS3.3 C.7.6.10, C.11.13 | Only needed for XA/XRF subtraction. The PS Mask module is M, but all of its attributes are 1C, so it is conformant when absent. |
| MF-10 | Table-valued VOI LUT and Presentation LUT write | Low | PS3.3 C.11.8, C.11.6 | `applyVOILUT` drops `.lut` and `buildDataSet` downgrades `.lut` to IDENTITY. Encode `(0028,3010)` / `(2050,0010)` instead (see NC-12). |
| MF-11 | TRUE SIZE / MAGNIFY Displayed Area | Low | PS3.3 C.10.4 (Presentation Pixel Spacing 1C, Presentation Pixel Magnification Ratio 1C) | The builder never writes (0070,0101) or (0070,0103), and the parser ignores them. |
| MF-12 | Per-image items in Softcopy VOI LUT Sequence and Displayed Area Selection Sequence (import) | Medium | PS3.3 C.11.8, C.10.4 (item Referenced Image Sequence 1C) | The parser takes `.first` item only (`parseVOILUT`, `parseDisplayedArea`). A third-party PR that covers a series with different windows per image applies image 1's window to all of them. |
| MF-13 | Colour pipeline in the headless renderer: CSPS through ICC to PCS, PCSPS palette stage | Medium | PS3.4 N.2.2.1 | `PresentationStateApplicator.apply` returns nil for non-monochrome images and has no palette stage. |
| MF-14 | Content Creator's Identification Code Sequence, Alternate Content Description, Concept Name Code Sequence | Low | PS3.3 Table 10-12 (Type 3) | Optional. |

---

## 3. Non-Conformance

Severity scale: **Critical** means the displayed image is wrong in a conforming viewer. **High** means a mandatory requirement is violated or the object is rejected by validators. **Medium** means a conditional or semantic violation. **Low** covers documentation or edge cases.

### NC-1: GSPS/PCSPS window written in rescaled units, but no Modality LUT is written — **Critical** · CONFIRMED [probe]

- **Standard requirement.** PS3.4 N.2.1.1: *"If the Modality LUT is not present in the Presentation State it shall be assumed to be an identity transformation. Any Modality LUT or equivalent Attributes in the Image shall not be used."* PS3.4 N.2 repeats: *"…any equivalent transformation, if present, in the Referenced Image SOP Instance shall NOT be used instead."*
- **Current behaviour.**
  - `ImageViewerViewModel+PresentationStates.swift:672-679` converts the window to rescaled units, for example 40/400 HU.
  - `PresentationStateStore.save` builds `GrayscalePresentationState` without `modalityLUT`, and `GrayscalePresentationStateBuilder.buildDataSet` has no Modality LUT output at all.
  - Probe CT PR: `(0028,3110)` WC=40, WW=400, and **no (0028,1052/1053/1054)**.
  - A conforming viewer (DCMTK, dcm4che) therefore applies the 40 HU window to *stored* values, which for intercept −1024 means HU −984. The saved view shows the wrong contrast.
  - DICOMKit only reads its own objects correctly because of the non-conformant fallback in NC-2.
- **Correction needed.** Write Rescale Slope, Intercept and Type from the source image, using snippets S-1a and S-1b. This makes the file self-describing in HU, and the existing HU window becomes correct for every viewer.

### NC-2: Viewer falls back to the image's rescale when the PR has no Modality LUT — **Medium** · CONFIRMED

- **Standard requirement.** PS3.4 N.2.1.1, as quoted in NC-1.
- **Current behaviour.** `ImageViewerViewModel+PresentationStates.swift:1057-1058` does this:

  ```swift
  let slope = restored.rescaleSlope ?? rescaleSlope
  let intercept = restored.rescaleIntercept ?? rescaleIntercept
  ```

  As a result, third-party PR objects that deliberately omit the Modality LUT are displayed with the image's rescale. The standard forbids that.
- **Correction needed.** Apply S-2 *after* S-1 has shipped. PRs that DICOMKit wrote before S-1 carry HU windows with no rescale. They need a migration rule, for example "if Manufacturer is DICOMKit and there is no Modality LUT, assume the image rescale", or they will display incorrectly once S-2 is in.

### NC-3: GSPS written for colour (RGB/YBR/PALETTE) images — **High** · CONFIRMED [probe]

- **Standard requirement.** PS3.3 A.33.1.1: *"This IOD may only be used to reference monochrome images, i.e. images with a Photometric Interpretation (0028,0004) of MONOCHROME1 or MONOCHROME2. See A.33.2 … which allows for referencing color images."*
- **Current behaviour.** `PresentationStateStore.save` picks the SOP class only from `palette`. It does not look at Photometric Interpretation, and `ImageToSave` has no field for it. The probe's VL Endoscopic RGB image produced a **GSPS** with Presentation LUT Shape IDENTITY and no ICC Profile.
- **Correction needed.** Add Photometric Interpretation to `ImageToSave`, and write CSPS (MF-1, S-10) for any image that is not MONOCHROME1 or MONOCHROME2 (S-3).

### NC-4: Displayed Area Selection Sequence omitted for "fit" views — **High** · CONFIRMED [probe, `dcmpschk` FAIL]

- **Standard requirement.** The Displayed Area module is **M** in A.33.1.3, A.33.2.3 and A.33.3.3. The Displayed Area Selection Sequence (0070,005A) is Type 1, and *"Sufficient Items shall be present to describe every image and Frame"* (C.10.4).
- **Current behaviour.** `ViewerPresentationStateBridge.capture` leaves `displayedArea = nil` when the whole image is visible, and `buildDataSet` writes the sequence only `if let area`. The result from `dcmpschk` is `displayedAreaSelectionSQ absent or empty … Test failed`. This affects **every saved view that was not zoomed or panned**: GSPS, PCSPS and the RGB case.
- **Correction needed.** Always write the full-image area (S-4).

### NC-5: ICC profile uses the Display class (`mntr`), but the standard requires an Input profile (`scnr`) — **High** · CONFIRMED [probe]

- **Standard requirement.** PS3.3 C.11.15.1.1: *"The profile shall be of the Input Device class, i.e., header bytes 12 through 15, Profile Device/Class Signature, shall be "scnr"."*
- **Current behaviour.** `SRGBICCProfileWriter.swift:81` writes `appendSignature(&profile, "mntr")`. The probe's PCSPS profile header reads `mntr / RGB  / XYZ `. The colour space (RGB) and PCS (XYZ) are correct.
- **Correction needed.** Apply S-5. Note that this changes the profile bytes, so any test that pins them needs updating.

### NC-6: Display shutter semantics inverted in `PresentationStateApplicator` — **High** · CONFIRMED

- **Standard requirement.** PS3.3 C.7.6.11: the shutter *"neutralize[s] the display of any of the pixels located **outside** of the shutter shape"*. With several shapes, *"the least amount of image remaining shall be visible"*, which is an intersection of the visible regions. The origin is **1,1**.
- **Current behaviour.**
  - `DisplayShutter.contains` returns true *inside* the shape, and `applyShutters` masks those pixels. This blacks out the region of interest and leaves the surround visible.
  - It uses `contains` on *any* shape, which is a union.
  - It uses 0-based `x, y`.
  - It runs *after* rotation while still using pre-rotation coordinates.
  - It clamps the 16-bit Shutter Presentation Value to 255 instead of scaling it.

  The DICOMStudio overlay path (`PresentationStateStore.shutterOverlay`) does paint the outside correctly, so this defect only affects the public DICOMKit renderer.
- **Correction needed.** Apply S-6.

### NC-7: Circular and polygonal shutter coordinates read in the wrong order — **High** · CONFIRMED

- **Standard requirement.** PS3.3 C.7.6.11 defines the two attributes as follows:
  - Center of Circular Shutter (0018,1610): *"…given as **row and column**"*.
  - Vertices of the Polygonal Shutter (0018,1620): *"**row** of the origin vertex\**column** of the origin vertex …"*.
- **Current behaviour.** `GrayscalePresentationStateParser.parseDisplayShutters` reads `centerValues[0]` as the column and `vertexData[i]` as the column. As a result, every imported circular and polygonal shutter is mirrored across the diagonal, both in the DICOMStudio overlay and in the applicator.
- **Correction needed.** Apply S-7.

### NC-8: PCSPS palette has the VOI window baked in *and* also carries it as VOI LUT (double windowing) — **High** · PLAUSIBLE

- **Standard requirement.**
  - The PS3.4 N.2 conceptual pipeline (Figure N.2-1, pseudo-colour path) is: Modality LUT → VOI LUT → **Palette Color LUT** → ICC → PCS.
  - For the same stage in blending, PS3.4 N.2.4.2 states it explicitly: *"The full output range of the preceding VOI LUT transformation is implicitly scaled to the entire input range of the Palette Color LUT."*
  - PS3.3 A.33.3.1 says the palette maps *"the transformed grayscale values"*.
- **Current behaviour.** `applyPaletteColorLUT` sizes the table to the stored-pixel domain (probe: `SS 4096\-2048\8`) and bakes the window into the table, so colour 0 applies below the window and colour 255 above it. It *also* writes the same window in (0028,3110).
  - Its comment says this was done to match Weasis, which indexes the table with raw stored pixels.
  - A pipeline-conformant viewer instead windows first, then spreads the VOI output across the table's whole input range. The palette's ramp ends up squeezed into the slice of entries that corresponds to the window (probe: indices 2912–3312 of 4096). The view renders almost entirely in the first colour, with a narrow band of ramp.
  - Combined with NC-1 (no Modality LUT), the offset is also wrong.
- **Correction needed.** Apply S-8: write the palette as the plain 256-entry Annex B table (`256\0\8`, with its UID) and let VOI do the windowing. Record the Weasis behaviour as a known interoperability issue rather than encoding around it.

### NC-9: Applicator applies flip before rotation — **Medium** · CONFIRMED

- **Standard requirement.** PS3.3 C.10.6: Image Rotation is applied *"before any Image Horizontal Flip"*. PS3.4 N.2.3.3 repeats the order.
- **Current behaviour.** `PresentationStateApplicator.applySpatialTransformation` applies the flip first and the rotation second. For 90° and 270° combined with a flip, the output is the transpose of the correct image. The DICOMStudio viewer is not affected.
- **Correction needed.** Apply S-9.

### NC-10: Applicator does less than its API documentation claims — **Medium** · CONFIRMED

- **Standard requirement.** PS3.4 N.2 defines the complete pipeline. PS3.3 C.11.6.1 says an absent VOI maps *"the full range of the output of the preceding transformation"*.
- **Current behaviour.**
  - The doc comment on `PresentationStateApplicator` (steps 5–7) lists displayed area, shutters and annotations, but displayed area and annotations are not implemented.
  - With no VOI, it divides by a hard-coded `4095`, which assumes 12-bit data.
- **Correction needed.** Either implement those steps or correct the doc comment. The no-VOI case should normalise over the actual output range of the Modality LUT (`BitsStored`, rescale).

### NC-11: Graphic Filled (0070,0024) written on objects that are not closed — **Medium** · CONFIRMED [probe]

- **Standard requirement.**
  - PS3.3 C.10.5 makes Graphic Filled 1C: *"Required if … CIRCLE or ELLIPSE, or … POLYLINE or INTERPOLATED and the first data point is the same as the last."*
  - PS3.5 §7.4.4 says: *"When the specified conditions are not met, Type 1C Data Elements **shall not be included**."*
- **Current behaviour.** `graphicObjectItem` always writes Graphic Filled. The probe arrow's two open POLYLINEs each carry `(0070,0024) CS [N]`.
- **Correction needed.** Apply S-12.

### NC-12: A table-valued Presentation LUT is silently replaced with IDENTITY — **Medium** · CONFIRMED

- **Standard requirement.** PS3.3 C.11.6 defines the Presentation LUT Sequence as the encoding for a non-linear Presentation LUT.
- **Current behaviour.** `buildDataSet` `case .lut:` writes `IDENTITY`. A state parsed from a third-party PR that has a Presentation LUT table, then re-saved, changes appearance without any warning. The same thing happens to `.lut` VOI tables in `applyVOILUT`, which writes nothing.
- **Correction needed.** Encode the table (MF-10), or throw an error rather than writing a different presentation.

### NC-13: Unknown annotation units (MATRIX) are coerced to PIXEL — **Medium** · CONFIRMED

- **Standard requirement.** PS3.3 C.10.5 defines the enumerated values PIXEL, DISPLAY and MATRIX.
- **Current behaviour.** `AnnotationUnits(rawValue:) ?? .pixel` in `parseGraphicObject` and `parseTextObject` places WSI annotations at frame-relative instead of Total-Pixel-Matrix positions.
- **Correction needed.** MF-7. Until MATRIX is supported, skip the object rather than misplacing it.

### NC-14: Retired attribute written for layer colour — **Medium** · CONFIRMED [probe]

- **Standard requirement.** PS3.6 2026a lists (0070,0067) Graphic Layer Recommended Display RGB Value as **RET (2004)**. PS3.3 C.10.7 says it was *"retired and its function replaced by Graphic Layer Recommended Display CIELab Value (0070,0401)"*, encoded per C.10.7.1.1 as L\*·65535/100 and (a\*,b\*)+128 scaled so that 0x8080 = 0.
- **Current behaviour.** `graphicLayerElement` writes (0070,0067) (probe: `US 65535\55705\6554`). It never writes (0070,0401). The parser reads only (0070,0067). DICOMCore has no tag constant for (0070,0401).
- **Correction needed.** Apply S-13. Keep reading (0070,0067) as a fallback for old files.

### NC-15: Content Creator's Name (0070,0084), which is Type 2, is omitted — **Medium** · CONFIRMED [probe]

- **Standard requirement.** PS3.3 Table 10-12 (Content Identification Macro): Content Creator's Name is Type 2.
- **Current behaviour.** `buildDataSet` writes it only when `presentationCreatorsName` is non-nil, and the store passes `creator: nil` by default. The tag is absent from the probe output.
  - The builder API can also omit Type 1 Presentation Creation Date/Time and Instance Number when the caller leaves them nil. The store path always fills them.
- **Correction needed.** Apply S-14.

### NC-16: Shutter Presentation Color CIELab Value is not read — **Low** · CONFIRMED

- **Standard requirement.** PS3.3 C.11.12: (0018,1624) is 1C, required when a shutter is present and the SOP Class is *other than* GSPS.
- **Current behaviour.** Neither the parser nor the model has it. On import it is lost; on export it would be missing (MF-3).
- **Correction needed.** Add it to `DisplayShutter` and to `parseDisplayShutters` and the writer.

### NC-17: Window values also written at the top level of the PR — **Low** · CONFIRMED [probe]

- **Standard requirement.** The window belongs in the Softcopy VOI LUT Sequence (C.11.8). Top-level (0028,1050/1051) is not part of the GSPS or PCSPS IOD. It is allowed only as a Standard Extended SOP Class attribute (PS3.4 B.1.3), and N.2.1.3 says image-level VOI values are not used.
- **Current behaviour.** `applyVOILUT` writes both copies, for backward compatibility with older DICOMKit readers.
- **Correction needed.** Acceptable, but should be documented in the Conformance Statement as a Standard Extended SOP Class. It can be removed once readers older than the Softcopy VOI change are no longer supported.

### NC-18: Displayed Area writer does not enforce the 1C attributes for TRUE SIZE and MAGNIFY — **Low** · CONFIRMED

- **Standard requirement.** PS3.3 C.10.4: TRUE SIZE requires Presentation Pixel Spacing, and MAGNIFY requires Presentation Pixel Magnification Ratio.
- **Current behaviour.** `displayedAreaElement` writes only the aspect ratio, whatever the size mode. The app never produces these modes today, but the public builder accepts them.
- **Correction needed.** MF-11.

### NC-19: Wrong section citations in code comments — **Low** · CONFIRMED

- **Standard requirement.** In 2026a, CSPS is **A.33.2**, PCSPS is **A.33.3** and Blending is **A.33.4**. The Softcopy Presentation LUT module is C.11.6 and the Presentation LUT module is C.11.4.
- **Current behaviour.**
  - `PresentationState.swift` cites A.34, A.35 and A.36.
  - `GrayscalePresentationStateParser.swift:66,71` cites A.33.4 and A.33.3.
  - `PseudoColorPresentationStateBuilder.swift:3` cites A.33.4.
  - `LUTTransformation.swift` labels C.11.6 as the "Presentation LUT Module".
  - `PresentationGraphicType.ellipse` documents "4 corner points of bounding box", but the standard defines them as the **endpoints of the major and minor axes**.
- **Correction needed.** Fix the comments. Add `NEMA-verified: 2026a` markers when the fixes land, following the repo's verification policy.

### Summary of severities

| Severity | IDs |
|---|---|
| Critical | NC-1 |
| High | NC-3, NC-4, NC-5, NC-6, NC-7, NC-8 |
| Medium | NC-2, NC-9, NC-10, NC-11, NC-12, NC-13, NC-14, NC-15 |
| Low | NC-16, NC-17, NC-18, NC-19 |

---

## 4. Required code snippets

These are snippets only, as the audit brief requires. They are not applied.

**S-1a: Modality LUT write.** File `Sources/DICOMKit/PresentationState/GrayscalePresentationStateBuilder.swift`, function `buildDataSet(from:patient:seriesInstanceUID:seriesNumber:)`, placed before `// MARK: Display transformations`. Reference: PS3.3 C.11.1, PS3.4 N.2.1.1.

```swift
// MARK: Modality LUT (C.11.1) — required whenever the window is in rescaled units.
switch state.modalityLUT {
case .rescale(let slope, let intercept, let type)?:
    dataSet.setString(Self.decimalString(intercept), for: .rescaleIntercept, vr: .DS)
    dataSet.setString(Self.decimalString(slope), for: .rescaleSlope, vr: .DS)
    dataSet.setString(type ?? "US", for: .rescaleType, vr: .LO)   // 1C with intercept
case .lut, nil:
    break   // Modality LUT Sequence encoding: see MF-10
}
```

**S-1b: pass the image's rescale into the state.** File `Sources/DICOMPrintKit/PresentationState/PresentationStateStore.swift`, function `save(images:label:patient:creator:created:)`, in the `GrayscalePresentationState(...)` initialiser. Reference: PS3.4 N.2.1.1.

```swift
modalityLUT: .rescale(
    slope: image.rescaleSlope, intercept: image.rescaleIntercept,
    type: image.sopClassUID == "1.2.840.10008.5.1.4.1.1.2" ? "HU" : "US"),
```

**S-2: no image fallback.** File `Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PresentationStates.swift`, the restore path (≈ line 1057). Reference: PS3.4 N.2.1.1. Ship this only after S-1, together with a migration rule for older DICOMKit PRs.

```swift
let slope = restored.rescaleSlope ?? 1        // absent Modality LUT = identity
let intercept = restored.rescaleIntercept ?? 0
```

**S-3: choose the IOD from Photometric Interpretation.** File `PresentationStateStore.swift`. Add `public let photometricInterpretation: String` to `ImageToSave`, then use it in `save`. Reference: PS3.3 A.33.1.1, A.33.2.

```swift
let isMonochrome = image.photometricInterpretation.hasPrefix("MONOCHROME")
let sopClassUID: String = !isMonochrome
    ? ColorPresentationStateBuilder.sopClassUID            // …11.2 (MF-1)
    : (colourPalette == nil ? GrayscalePresentationStateBuilder.sopClassUID
                            : PseudoColorPresentationStateBuilder.sopClassUID)
```

**S-4: always state the displayed area.** File `Sources/DICOMPrintKit/PresentationState/ViewerPresentationStateBridge.swift`, function `capture(...)`, as an `else` branch of `if let region = …`. Reference: PS3.3 C.10.4 (module M, sequence Type 1).

```swift
} else {
    captured.displayedArea = DisplayedArea(
        topLeft: (column: 1, row: 1),
        bottomRight: (column: imageWidth, row: imageHeight),
        sizeMode: .scaleToFit)
}
```

**S-5: ICC Input Device class.** File `Sources/DICOMKit/PresentationState/SRGBICCProfileWriter.swift`, the profile header (line 81). Reference: PS3.3 C.11.15.1.1.

```swift
appendSignature(&profile, "scnr")                  // Input Device class (C.11.15.1.1)
```

**S-6: shutter semantics.** File `Sources/DICOMKit/PresentationState/PresentationStateApplicator.swift`, function `apply(to:frameIndex:)`. Call this *before* `applySpatialTransformation`, and replace the body of `applyShutters`. Reference: PS3.3 C.7.6.11, C.11.12.

```swift
private func applyShutters(to bytes: inout [UInt8], width: Int, height: Int) {
    let shapes = presentationState.shutters.filter {
        if case .bitmap = $0 { return false }; return true
    }
    guard !shapes.isEmpty else { return }
    // P-Value 0…FFFFH scaled to the 8-bit output, not clamped.
    let pValue = presentationState.shutters.first?.presentationValue ?? 0
    let fill = UInt8((pValue * 255 + 32767) / 65535)
    for y in 0..<height {
        for x in 0..<width where !shapes.allSatisfy({ $0.contains(column: x + 1, row: y + 1) }) {
            bytes[y * width + x] = fill     // outside any shape = occluded (1-based origin)
        }
    }
}
```

**S-7: shutter coordinate order.** File `Sources/DICOMKit/PresentationState/GrayscalePresentationStateParser.swift`, function `parseDisplayShutters(from:)`. Reference: PS3.3 C.7.6.11 (0018,1610) and (0018,1620).

```swift
shutters.append(.circular(
    centerColumn: centerValues[1], centerRow: centerValues[0],   // (0018,1610) is row\column
    radius: radius, presentationValue: presentationValue))
// …
vertices.append((column: vertexData[i + 1], row: vertexData[i]))  // (0018,1620) is row\column
```

**S-8: palette without a baked window.** File `Sources/DICOMKit/PresentationState/PseudoColorPresentationStateBuilder.swift`, function `buildDataSet(from:palette:pixelDomain:patient:seriesInstanceUID:seriesNumber:)`. Reference: PS3.4 N.2 (Figure N.2-1) and N.2.4.2.

```swift
// VOI output is implicitly scaled onto the palette's whole input range:
// the table is indexed by the *windowed* value, never by stored pixels.
Self.applyPaletteColorLUT(
    palette, inverted: inverted, domain: nil, window: nil, to: &dataSet)
```

**S-9: rotate, then flip.** File `PresentationStateApplicator.swift`, function `applySpatialTransformation`. Reference: PS3.3 C.10.6.

```swift
var result = bytes
var (w, h) = (width, height)
if transform.isRotated {
    result = applyRotation(to: result, width: w, height: h, degrees: transform.rotation)
    if transform.rotation == 90 || transform.rotation == 270 { swap(&w, &h) }
}
if transform.isFlipped {
    result = applyHorizontalFlip(to: result, width: w, height: h)
}
return result
```

**S-10: CSPS builder, as a new file.** File `Sources/DICOMKit/PresentationState/ColorPresentationStateBuilder.swift`, function `buildDataSet(from:patient:seriesInstanceUID:seriesNumber:)`. Reference: PS3.3 A.33.2.3, C.11.15.

```swift
public struct ColorPresentationStateBuilder: Sendable {
    public static let sopClassUID = "1.2.840.10008.5.1.4.1.1.11.2"
    public init() {}

    public func buildDataSet(
        from state: GrayscalePresentationState,          // geometry + annotations
        patient: PresentationStatePatientContext,
        seriesInstanceUID: String, seriesNumber: Int
    ) -> DataSet {
        var dataSet = GrayscalePresentationStateBuilder().buildDataSet(
            from: state, patient: patient,
            seriesInstanceUID: seriesInstanceUID, seriesNumber: seriesNumber)
        dataSet.setString(Self.sopClassUID, for: .sopClassUID, vr: .UI)
        // A.33.2.3 has no Modality LUT, Softcopy VOI LUT or Softcopy Presentation LUT.
        for tag: Tag in [.softcopyVOILUTSequence, .windowCenter, .windowWidth,
                         .windowCenterWidthExplanation, .voiLUTFunction,
                         .presentationLUTShape, .presentationLUTSequence,
                         .rescaleSlope, .rescaleIntercept, .rescaleType] {
            dataSet[tag] = nil
        }
        // ICC Profile module (C.11.15) — M.
        dataSet[.iccProfile] = DataElement(
            tag: .iccProfile, vr: .OB,
            length: UInt32(SRGBICCProfileWriter.profileData.count),
            valueData: SRGBICCProfileWriter.profileData)
        dataSet.setString(SRGBICCProfileWriter.colorSpace, for: .colorSpace, vr: .CS)
        return dataSet
    }
}
```

When the source image carries its own ICC Profile (0028,2000), prefer copying that profile over the fixed sRGB one. PS3.4 N.2.2.1 says the PR's profile replaces the image's profile.

**S-11: Display Shutter write.** File `GrayscalePresentationStateBuilder.swift`, function `buildDataSet`. Reference: PS3.3 C.7.6.11, C.11.12.

```swift
if !state.shutters.isEmpty {
    var shapes: [String] = []
    for shutter in state.shutters {
        switch shutter {
        case .rectangular(let l, let r, let t, let b, _):
            shapes.append("RECTANGULAR")
            dataSet.setInteger(l, for: .shutterLeftVerticalEdge)
            dataSet.setInteger(r, for: .shutterRightVerticalEdge)
            dataSet.setInteger(t, for: .shutterUpperHorizontalEdge)
            dataSet.setInteger(b, for: .shutterLowerHorizontalEdge)
        case .circular(let c, let r, let radius, _):
            shapes.append("CIRCULAR")
            _ = dataSet.setIntegers([r, c], for: .centerOfCircularShutter)   // row\column
            dataSet.setInteger(radius, for: .radiusOfCircularShutter)
        case .polygonal(let vertices, _):
            shapes.append("POLYGONAL")
            _ = dataSet.setIntegers(vertices.flatMap { [$0.row, $0.column] },
                                    for: .verticesOfPolygonalShutter)
        case .bitmap:
            continue   // needs Bitmap Display Shutter + Overlay Plane (MF-8)
        }
    }
    if !shapes.isEmpty {
        dataSet.setString(shapes.joined(separator: "\\"), for: .shutterShape, vr: .CS)
        dataSet.setInteger(state.shutters.first?.presentationValue ?? 0,
                           for: .shutterPresentationValue)                 // 1C (C.11.12)
        // Non-GSPS classes also need Shutter Presentation Color CIELab Value
        // (0018,1624), 1C — write it in the PCSPS/CSPS builders.
    }
}
```

**S-12: conditional Graphic Filled.** File `GrayscalePresentationStateBuilder.swift`, function `graphicObjectItem(_:)`. Reference: PS3.3 C.10.5 (0070,0024) and PS3.5 §7.4.4.

```swift
var elements: [DataElement] = [ /* units, dimensions, count, data, type — unchanged */ ]
let d = object.data
let closed = object.type == .circle || object.type == .ellipse
    || ((object.type == .polyline || object.type == .interpolated)
        && d.count >= 4 && d[0] == d[d.count - 2] && d[1] == d[d.count - 1])
if closed {
    elements.append(DataElement.string(
        tag: .graphicFilled, vr: .CS, value: object.filled ? "Y" : "N"))
}
return SequenceItem(elements: elements)
```

**S-13: CIELab layer colour.** File `GrayscalePresentationStateBuilder.swift`, function `graphicLayerElement(_:)`, replacing the `recommendedRGBValue` branch. Reference: PS3.3 C.10.7, C.10.7.1.1; PS3.6 (0070,0067) RET.

```swift
if let rgb = layer.recommendedRGBValue {
    let lab = ColorTransform.rgbToLAB((Double(rgb.red) / 65535,
                                       Double(rgb.green) / 65535,
                                       Double(rgb.blue) / 65535))
    let encoded = [Int((lab.l / 100 * 65535).rounded()),
                   Int(((lab.a + 128) * 257).rounded()),
                   Int(((lab.b + 128) * 257).rounded())].map { min(65535, max(0, $0)) }
    elements.append(Self.integers(encoded,
        for: Tag(group: 0x0070, element: 0x0401)))  // Graphic Layer Recommended Display CIELab Value
}
```

Also add `graphicLayerRecommendedDisplayCIELabValue` and `shutterPresentationColorCIELabValue` constants to `DICOMCore/Tag+PresentationState.swift`, and make the parser read (0070,0401) first.

**S-14: Type 2 creator name.** File `GrayscalePresentationStateBuilder.swift`, function `buildDataSet`, under `// MARK: Presentation State Identification`. Reference: PS3.3 Table 10-12.

```swift
dataSet.setString(state.presentationCreatorsName?.dicomString ?? "",
                  for: .contentCreatorName, vr: .PN)   // Type 2: present, may be empty
```

---

## 5. Comparison matrix — validated

"Std" is what 2026a allows. "DICOMKit" is what is implemented, both write and read.

| Function | GSPS Std / DICOMKit | CSPS Std / DICOMKit | PCSPS Std / DICOMKit | Notes on the matrix in the brief |
|---|---|---|---|---|
| Window Level (Softcopy VOI LUT) | Yes / ✅ (NC-1 units) | **No** / n/a | Yes / ⚠️ NC-8 | Correct |
| Modality LUT | Yes / ❌ write, ✅ read | **No** / n/a | Yes / ❌ write, ✅ read | Correct |
| VOI LUT (table) | Yes / read only | No / n/a | Yes / read only | Correct |
| Presentation LUT | Yes (M) / ✅ shape, ❌ table | **No** | **No — "shall not be present"** / ✅ | Correct |
| Palette Color LUT | No / n/a | **No**: A.33.2.3 has no Palette module. The brief's "Possible" is wrong. A PALETTE COLOR *image* keeps its own palette, and CSPS applies ICC after it. | Yes (M) / ✅ | **Brief incorrect for CSPS** |
| Zoom / Pan (Displayed Area, M) | Yes / ⚠️ NC-4 | Yes / read only | Yes / ⚠️ NC-4 | Correct |
| Rotate / Flip | Yes / ✅ | Yes / read only | Yes / ✅ | Correct |
| Shutter | Yes / ⚠️ read only, NC-6/7 | Yes / read only | Yes / read only | Correct. CSPS/PCSPS also need a CIELab shutter colour (NC-16). |
| Text Annotation | Yes / ✅ | Yes / read only | Yes / ✅ | Correct |
| Arrow | Yes (Compound ARROW, Type 3, or polylines) / ⚠️ polylines only | same / read only | same / ⚠️ | Correct |
| Line / Polyline | Yes / ✅ | Yes / read only | Yes / ✅ | Correct |
| Circle / Ellipse | Yes / ✅ round-trip of imported shapes only. There is no drawing tool. | Yes / read only | Yes / ✅ | Correct |
| Measurements | **No measurement semantics in any PS IOD.** Only text and graphics that depict one (C.10.5: *"no semantic notion of an associated observation"*). Structured measurements belong in SR (TID 1500). | same | same | **Brief overstates.** Only "Yes, as annotation". |
| Graphic Layers | Yes / ✅ (NC-14 retired colour) | Yes / read only | Yes / ✅ | Correct |
| ICC Color Management | **No** / ✅ n/a | Yes (M) / ❌ not read, not written | Yes (M) / ⚠️ NC-5 | Correct |
| Grayscale → Color mapping | No | No | Yes / ✅ | Correct |
| *Mask subtraction* (missing from the brief) | Yes (C) / ❌ | **No** | Yes (C) / ❌ | Row added |
| *Overlay activation* (missing from the brief) | Yes (C) / ❌ | Yes (C) / ❌ | Yes (C) / ❌ | Row added |
| *Bitmap shutter* (missing from the brief) | Yes (C) / ⚠️ read only, not rendered | Yes (C) / same | Yes (C) / same | Row added |

---

## 6. Test dataset verification

| Requested dataset | Result |
|---|---|
| GSPS: CT | **Synthetic probe, run.** `dcmpschk` **FAILS** because of NC-4. Byte inspection confirmed NC-1, NC-11, NC-14 and NC-15. |
| GSPS: MR, CR, DX | Not run: no PR-bearing MR/CR/DX test data exists in the repo. MR and DX without rescale are not affected by NC-1. All of them are affected by NC-4, NC-11, NC-14 and NC-15. |
| CSPS: Endoscopy | **Synthetic probe (VL Endoscopic RGB), run.** It produced a **GSPS** (NC-3) and failed `dcmpschk` (NC-4). No CSPS writer exists. |
| CSPS: Pathology, Ophthalmology, Dermatology | Not run. The same outcome as endoscopy follows from code (NC-3). Pathology is additionally affected by NC-13 (MATRIX units). |
| PCSPS: PET, NM, functional maps | **Synthetic probe (CT source, Hot Iron), run.** `dcmpschk` reports "passed", but dcmpschk does not deeply validate PCSPS. By inspection it is affected by NC-4, NC-5, NC-8 and NC-1. |

**Existing unit tests.** Presentation state tests exist in:

- `Tests/DICOMKitTests/`: `GrayscalePresentationStateBuilderTests`, `PseudoColorPresentationStateBuilderTests`
- `Tests/DICOMPrintKitTests/`: `PresentationStateStoreTests`, `PrintOverlayAnnotationGSPSTests`, `ImportedPresentationStateTests`, `PresentationStateFrameReferenceTests`, `WeasisApplyGateTests`
- `Tests/DICOMStudioTests/`: `StudyPresentationStateAdoptionTests`, `SeriesSavedViewTests`, `PresentationSeriesPruneTests`

These tests check round trips through DICOMKit itself. That cannot catch NC-1 or NC-8, where writer and reader share the same wrong assumption. **The tests were not run in this audit.**

**Recommended conformance gate.** Add a CI step that writes one object per IOD and runs `dcmpschk`, plus `dciodvfy` from dicom3tools (not currently installed). Also render one CT PR in DCMTK `dcmp2pgm`, as an independent pipeline, to catch NC-1 and NC-8 regressions.

**Viewer testing.** Rendering in a third-party viewer (OHIF, Horos, dcm4che/Weasis) was not performed.

---

## 7. Final Compliance Summary

Each IOD is scored against a checklist of standard-defined capabilities, covering writing, reading, conformance of what is written, and rendering. Scores are 1 for complete and correct, 0.5 for partial, 0.25 for present but with a correctness defect, and 0 for missing or wrong. Optional (Type 3 / U) features are **not** counted. These percentages are a structured judgement, not a certification.

| Checklist item | GSPS | CSPS | PCSPS |
|---|---|---|---|
| SOP Class registration | 1 | 1 | 1 |
| Parse to model | 0.5 | 0.5 | 0.5 |
| Write / save / export | 1 | 0 | 1 |
| Import (adoption) | 1 | 0.5 | 1 |
| Identification / Relationship / Series modules | 1 | 0 | 1 |
| Modality LUT | 0 | n/a | 0 |
| Softcopy VOI LUT | 0.5 | n/a | 0.5 |
| Softcopy Presentation LUT (GSPS) or its absence (PCSPS) | 0.5 | n/a | 1 |
| Palette Color LUT | n/a | n/a | 0.5 |
| ICC Profile | n/a | 0 | 0.5 |
| Displayed Area (M) | 0.5 | 0.5 | 0.5 |
| Spatial Transformation | 1 | 0.5 | 1 |
| Graphic Annotation | 0.5 | 0.5 | 0.5 |
| Graphic Layer | 0.5 | 0.5 | 0.5 |
| Display Shutter (C) | 0.25 | 0.25 | 0.25 |
| Mask / Overlay / Bitmap shutter (C) | 0 | 0 | 0 |
| IOD applicability (monochrome only / colour) | 0 | 0 | 1 |
| Rendering (viewer and applicator) | 0.5 | 0.25 | 0.5 |
| **Score** | **8.75 / 16** | **4.5 / 14** | **11.25 / 18** |

| IOD | Percentage completed |
|---|---|
| **GSPS** | **≈ 55 %** |
| **CSPS** | **≈ 32 %** (read-side only; no writer) |
| **PCSPS** | **≈ 62 %** |
| **Overall Presentation State compliance** (pooled: 24.5 / 48) | **≈ 51 %** |

### What would move the numbers most

1. **NC-1 + S-1: write the Modality LUT.** A two-file change that fixes CT/PET display in every conformant viewer.
2. **NC-4 + S-4: always write the Displayed Area.** This alone turns every `dcmpschk` failure into a pass.
3. **NC-3 + MF-1 + S-3 + S-10: CSPS writer and IOD selection.** This moves CSPS from about 32 % to 75 % or more.
4. **NC-5, NC-8, NC-6 and NC-7.** Each is a one-function fix.

With items 1–4 applied, the same checklist scores roughly GSPS 75 %, CSPS 75 % and PCSPS 80 %.

### Differences from DICOM 2026a (consolidated)

- **Written objects.** Displayed Area is missing (M). The Modality LUT is missing while the window is in HU. GSPS is used for colour images. The ICC class is `mntr` instead of `scnr`. The retired (0070,0067) is written. Graphic Filled is written when its 1C condition is false. The Type 2 Content Creator's Name is missing. Top-level window attributes are written as extended attributes.
- **Semantics.** The PCSPS palette is indexed by stored values with the window baked in, instead of by VOI output. Shutter geometry (row\column) is swapped on read. Shutter masking is inverted in the public applicator, and the applicator flips before rotating.
- **Reader behaviour.** Image rescale is used when the PR has none. MATRIX units become PIXEL. Only the first per-image VOI and Displayed Area item is used. CSPS ICC profiles are ignored.

*NEMA-verified: 2026a, checked 2026-09-25. Compared PS3.3 A.33.1–A.33.3, C.7.6.11, C.7.9, C.10.4–C.10.7, C.11.1, C.11.6, C.11.8–C.11.15 and Table 10-12; PS3.4 N.2; PS3.5 §7.4.4; PS3.6 entries for (0070,0067) and (0070,0401). Provenance: NEMA DocBook at dicom.nema.org/medical/dicom/2026a/. Source files were not annotated because this audit was read-only.*
