# DICOMPrintKit — DICOM Standard Implementation Report

Generated 2026-09-29, last updated 2026-09-29 (approval pass). Covers all 31 Swift files (30 before the approval pass added `GrayscaleStandardDisplayFunction.swift`) in `Sources/DICOMPrintKit/` (about 11,100 lines
before this pass): the print job model and option catalogue shared by `dicom-print` and DICOM
Studio, the pixel preparation for image boxes, the film composer and output sinks of the Print SCP
emulator, the burned-in annotation renderer, and the bridge that saves and restores a viewer's
arrangement as a presentation state.

**Status: complete.** Every file is bucketed and carries a `NEMA-verified` marker
(`Scripts/check_nema_markers.py Sources/DICOMPrintKit` exits 0: 31 of 31). Every table of values
the module uses is diffed by script against the frozen 2026a DocBook
([Scripts/diff_printkit.py](Scripts/diff_printkit.py): 32 checks, 0 failing, 0 pending). The
deferred rows for this module (D23, D27, D36; D30 was already closed) are closed. The three
decisions the first pass left open (P-MAMMO, P-GSDF, P-CROP) were approved by the owner on
2026-09-29 ("complete the module as per your recommendation") and are implemented as
recommended, each against the clause named. Every behaviour fix has a test;
`swift build` and the full `swift test` pass (exit 0; Verification notes). The work is committed on
`feature/dicom-tag-modality-audit`, locally, for review. Five rows were opened for other modules
(D39–D43); D39, D40, D41 and D43 were closed the same day at the owner's request, D42
(DICOMStudio) stays open for that module's pass. The four
`PDFRoundTripTests` cases that failed on the untouched HEAD (D43) were updated to the 2026a values
at the owner's request; the full `swift test` now exits 0.

Method: [DICOMCORE_STANDARD_IMPLEMENTATION.md → Verification method](DICOMCORE_STANDARD_IMPLEMENTATION.md#verification-method-reuse-for-every-module),
used unchanged. Package target: **DICOM 2026a** (`dicomStandardEdition = "2026a"`,
[DICOMKit.swift](Sources/DICOMKit/DICOMKit.swift)).

**Scope note.** DICOMPrintKit carries almost no tables of its own. The print enumerations it
offers are DICOMNetwork enums; the SOP Class UIDs it names are DICOMNetwork constants; the
presentation states it writes go through DICOMKit's builders. So the diff script resolves every
value the module *uses* in the source of the module that defines it and diffs that value, and it
checks what this module passes to those builders against the IOD tables. The standard text used:
PS3.3 C.13.1–C.13.9 and Tables C.13-1, C.13-3, C.13-5, C.13-7, C.13-8, C.13-9 (print modules);
C.11.4 and Table C.11-4 (hardcopy Presentation LUT); A.33.1–A.33.3, C.10.4–C.10.7, C.11.1, C.11.2,
C.11.6, C.7.6.11 / Table C.7-17a (presentation states and shutters); C.7.6.3.1.2 (photometric);
PS3.4 H.3.2.2, H.4.3, H.4.5–H.4.6 (Print Management, meta SOP classes, status information), N.2 and
N.2.1.1 (softcopy pipeline); PS3.5 6.3 and Table 6.2-1; PS3.6 Tables 6-1 and A-1; PS3.14 chapters
6–7 (GSDF, hardcopy). The DICOMNetwork protocol machine (DIMSE, the SCP parser, the pixel-depth
clamp) was verified in its own pass and is not re-scored here.

---

## Summary

| Bucket | Files | Meaning | Status |
|---|---|---|---|
| A — cites 2026a | 0 | — | ✅ (none) |
| B1 — cites another edition, a CP or a Supplement | 0 | — | ✅ (none) |
| B2 — no citation, data or behaviour differed from 2026a | 14 (one new file, `GrayscaleStandardDisplayFunction.swift`) | See the bucket table; every finding verified against the frozen text | ✅ Fixed; three decisions pending (P-MAMMO, P-GSDF, P-CROP) |
| C1 — plumbing | 9 | Confirmed to carry no standard data | ✅ |
| C2 — standard-derived, edition-stable | 8 | Diffed all the same; all values match | ✅ |

**31 files total.**

### Baseline diff, before any change (2026-09-29, `Scripts/diff_printkit.py` against the HEAD sources)

32 scripted checks against PS3.3, PS3.4, PS3.5, PS3.6 and PS3.14 2026a; 10 failed, 3 pending:

| Check | Standard | Result before |
|---|---|---|
| Every `1.2.840.10008` literal registered; print SOP classes used (resolved in DICOMNetwork) and their meta SOP class; PS SOP classes adopted | PS3.6 Table A-1; PS3.4 Tables H.3.2.2.1-1, H.3.2.2.2-1 | match (4, 2, 3) |
| Film Size ID, Film Orientation, Print Priority, Film Destination, Magnification Type, Polarity, Trim, Presentation LUT Shape offered by `PrintOptionCatalog` (DICOMNetwork raw values) | PS3.3 Tables C.13-1, C.13-3, C.13-5, C.11-4 | match (31 values) |
| Medium Type offered | PS3.3 Table C.13-1 | **PEND:** MAMMO CLEAR FILM / MAMMO BLUE FILM not offered (P-MAMMO, D23) |
| Border / Empty Image Density names; grayscale Bits Stored 8/12 | Tables C.13-3, C.13-5 | match |
| `--raw` frames checked against the image box pixel enumerations | Table C.13-5 | **FAIL:** not checked — a raw signed CT went out as Pixel Representation 1, a 16-bit-stored image as Bits Stored 16, a YBR or PALETTE COLOR source with that photometric |
| Printer Status and Printer Status Info | Table C.13-9, C.13.9.1 | **FAIL:** the emulator's FAILURE default Printer Status Info `NO SUPPLY` is not one of the 108 Defined Terms (`SUPPLY EMPTY` is) |
| Physical size of every Film Size ID | Table C.13-3 | **FAIL:** 11 / 12; 10INX14IN drawn as 254 × 355.6 mm; the table says it "corresponds with 25.7CMX36.4CM" |
| Attribute names next to `(GGGG,EEEE)` | PS3.6 Table 6-1 | **FAIL:** 42 / 44; "Max Density (2010,1030)" (the tag is 2010,0130), "Presentation Label (0070,0080)" (Content Label) |
| Names beside `Tag(group:element:)`, typed reads, explicit VRs | PS3.6 Table 6-1 | match |
| Section/table citations exist | PS3.3/3.4/3.5/3.6/3.14/3.16 2026a | **FAIL:** "PS3.5 8.7.4" does not exist |
| Citations name the clause of their topic | C.13.3, C.13.5, C.11.4, C.10.4, C.10.6, C.7.6.11 | **FAIL:** 14 / 18; Bits Stored 8/12 cited as Table C.13-3 (it is C.13-5) in three files (D23), rotation/flip cited as C.10.10 (Waveform Annotation Module; it is C.10.6) |
| Section titles given in parentheses | PS3.3 2026a | **FAIL:** "C.13.6 (Film Size ID)" (C.13.6 is the retired Image Box Relationship Module), "C.11.6 (Presentation LUT)" in a print sentence (the hardcopy module is C.11.4) |
| Photometric literals; Presentation Size Mode, Annotation Units, Graphic Type, Image Rotation the bridge writes | C.7.6.3.1.2; Tables C.10-4, C.10-5, C.10-6 | match |
| What the store passes to the builders | Table C.10-4, A.33.1-1, A.33.2-1; PS3.4 N.2.1.1 | **FAIL (D27, D36):** GSPS and Pseudo-Color builders called without `imageSize:` (Type 1 Displayed Area Selection Sequence missing for every fitted view); no Modality LUT in the state |
| Annotation Text String is LO | PS3.5 Table 6.2-1 | **FAIL:** footer lines sent unchecked (LO is 64 characters, no backslash) |
| Shutter pixel positions | Table C.7-17a | **FAIL:** 1-based edges divided by the image size as if 0-based (the first open row and column were shuttered) |
| P-Values rendered through the GSDF | PS3.14 7.2 | **PEND (P-GSDF)** |
| CROP with no Requested Image Size | Table C.13-5 | **PEND (P-CROP)** |

Tests at the start (HEAD `56115eaa`, `swift test --filter DICOMPrintKitTests` in a clean worktree):
323 XCTest cases (1 skipped: `DCMTKInteropTests.testDCMTKPrintSCUCanPrintToOurEmulator`, "No
sample DICOM image available for the DCMTK tools") and 84 swift-testing tests pass, 0 failures.

After the first pass: DICOMPrintKitTests 351 XCTest cases (the same 1 skipped) and 84
swift-testing tests pass, 0 failures; `diff_printkit.py` 29 ok, 0 FAIL, 3 PEND. After the approval
pass: 362 XCTest cases (1 skipped) and 84 swift-testing tests; `diff_printkit.py` 32 ok, 0 FAIL,
0 PEND (the GSDF and CROP checks were strengthened: coefficients and Table D.2-1 by script, the
stated CROP reading).

---

## Progress log

| Date | Item | What was compared | What changed | Tests |
|---|---|---|---|---|
| 2026-09-29 | Baseline | All 30 files read in full and bucketed. PS3.3, 3.4, 3.5, 3.6, 3.14, 3.16 2026a fetched into the session scratchpad (subtitles checked, not committed). `Scripts/diff_printkit.py` written (reuses `diff_web` Report/dictionary/UID registry/section helpers and `diff_kit` tag, citation and typed-read checks): 32 checks, 10 failed, 3 pending (table above). | Script only | DICOMPrintKitTests at HEAD in a clean worktree: 323 XCTest (1 skipped), 84 swift-testing, 0 failures |
| 2026-09-29 | D27, D36 | PS3.3 Table C.10-4 (Displayed Area Selection Sequence Type 1); A.33.1.1 ("may only be used to reference monochrome images"); Table A.33.2-1 (CSPS: no Modality/VOI/Presentation LUT, ICC Profile M); PS3.4 N.2.1.1 ("If the Modality LUT is not present in the Presentation State it shall be assumed to be an identity transformation. Any Modality LUT … in the Image shall not be used"); PS3.4 N.2 (MONOCHROME1/2 of the referenced image "shall be ignored") | `PresentationStateStore.save` passes the image size to every builder (the whole image, SCALE TO FIT, when the view records no area), writes the image's rescale as the state's Modality LUT (`rescaleType`, default `US`), writes a Color Softcopy Presentation State for any non-monochrome image (a colour image's inversion kept in the sidecar), and the state copies keep Shutter Presentation Color; `ViewerPresentationStateBridge.capture/restore` fold MONOCHROME1 into the Presentation LUT; new defaulted inputs `ImageToSave.photometricInterpretation`, `.rescaleType`, `capture/restore(photometricInterpretation:)` | `PresentationStateIODConformanceTests` (13) |
| 2026-09-29 | Shutters | Table C.7-17a: edges, centre and vertices are positions "with respect to pixels in the image", 1-based; `DisplayShutter.contains` keeps the edge pixels open | `shutterOverlay` opens a rectangle from the left/top edge of its first pixel and puts centres and vertices at pixel centres | 3 tests (same suite); one fixture pin corrected (left edge 50 opens at 49/512) |
| 2026-09-29 | GSPS vocabulary claims | Table C.10-5 (Compound Graphic Sequence, Compound Graphic Type ARROW), Tables C.10-5a/5b (Text/Line Style Sequence, CIELab colour), Table C.10-7 (0070,0401) | The comments in `AnnotationSidecar` and `PrintOverlayAnnotationGSPS` that said DICOM has no arrow and no per-object colour are corrected: the standard has both, DICOMKit's model has neither (D39) | — |
| 2026-09-29 | D23, citations | Tables C.13-3 / C.13-5; C.10.6; C.11.4; C.13.3; C.7.6.3.1.2; PS3.5 6.3 | Bits Stored 8/12 cited as Table C.13-5 in the catalog, the request (doc and CLI message) and the preparer (doc and clamp note); rotation/flip as C.10.6; the composer's references as C.13.3/C.13.5/C.11.4; YBR 4:2:2 as C.7.6.3.1.2; FilmGeometry as C.13.3; CROP as Table C.13-5; C.11.2 claims (VOI LUT over window, first pair "the default") rewritten as this toolkit's choices, since C.11.2 sets neither | clamp-note test pin updated |
| 2026-09-29 | Film geometry, densities | Table C.13-3 Film Size ID ("10INX14IN corresponds with 25.7CMX36.4CM, A4 … 210 x 297, A3 … 297 x 420"); C.11.4 LIN OD; PS3.6 (2010,0130) | 10INX14IN sheet 257 × 364 mm; Max Density named (2010,0130) (C.11.4's own text misprints it as 2010,1030); the 0.20/3.00 OD defaults documented as this toolkit's, not C.13.3's | 1 test |
| 2026-09-29 | `--raw` | Table C.13-5 grayscale (MONOCHROME1/2, Bits Allocated 8/16, Bits Stored 8/12, Pixel Representation 0) and colour (RGB, 8/8) enumerations; High Bit one less than Bits Stored; PS3.5 6.3 | A raw frame that the image box cannot carry is refused with the rule instead of being sent non-conformant | 7 tests |
| 2026-09-29 | Printer status | C.13.9.1 Defined Terms | FAILURE default Printer Status Info `SUPPLY EMPTY` (was `NO SUPPLY`) | 1 test; 3 pins updated (1 DICOMPrintKit, 2 DICOMStudio) |
| 2026-09-29 | Text String | PS3.5 Table 6.2-1 LO; Table C.13-7 | Footer lines cut to 64 characters, backslash → slash, control characters dropped (`FilmIdentificationFooter.textString(_:)`, `textStringMaximumLength`) | 2 tests |
| 2026-09-29 | Simulator | C.13.3 (Image Display Format), C.13.5.1 (box numbering) | `PrintSCPSimulator` writes the job's own Image Display Format; a `ROW\1,2` job was composed as `STANDARD\2,2` (four boxes for three images) | 1 test |
| 2026-09-29 | Markers, close | `check_nema_markers.py`: 30 / 30; `diff_printkit.py`: 29 ok, 0 FAIL, 3 PEND | CHANGELOG `[Unreleased]`; DICOMCore status table; D23/D27/D36 status in the DICOMNetwork and DICOMKit reports | Full `swift test` below |
| 2026-09-29 | Owner approval of P-MAMMO, P-GSDF, P-CROP ("complete the module as per your recommendation") | — | — | — |
| 2026-09-29 | P-MAMMO (D23 remainder) | PS3.3 Table C.13-1 (PAPER, CLEAR FILM, BLUE FILM, MAMMO CLEAR FILM, MAMMO BLUE FILM) | DICOMNetwork `MediumType.mammoClearFilm` / `.mammoBlueFilm`; `.mammoFilmClearBase` / `.mammoFilmBlueBase` deprecated (renamed), still parsed and normalized; `wireValue` always writes the term (SCU session N-CREATE, SCP encoder); `allCases` lists the five terms; `PrintOptions.mammography` sends MAMMO BLUE FILM; the catalogue offers both (`mammo-clear-film`, `mammo-blue-film`); `diff_network.py` ignores deprecated cases and its pending set is empty | DICOMNetworkTests pins updated (+1 legacy-spelling test); 2 catalogue tests |
| 2026-09-29 | P-GSDF | PS3.14 7.1 (L(j), j(L) coefficients, scripted), 7.2 (transmissive: L = La + L0·10^−D, j linear in p), 7.3 (reflective), Annex D.2 and Table D.2-1 (256 densities at L0 2000, La 10, Dmin 0.20, Dmax 3.00) | New `GrayscaleStandardDisplayFunction.swift`; `DensityMapping.gsdf` (token `gsdf`): P-Values laid down through the GSDF (PAPER reflective, film transmissive; Min/Max Density from the film box or 0.20/3.00), LIN OD and numeric Border/Empty densities as densities, shown as luminance relative to the sheet's brightest, sRGB-encoded. `paper` stays the default | `PrintGSDFTests` (9): Table B-1 end points, D.2 range, all 256 Table D.2-1 densities within 0.0015 OD |
| 2026-09-29 | P-CROP | PS3.3 Table C.13-5 ("optimal filling" undefined) | Reading kept (CROP with no size fills the box) and stated in `PRINT_CONFORMANCE.md` 3.5, with the DECIMATE/CROP/FAIL and size table; the conformance statement's stale MAMMO, INVERSE-shape, 16-bits-stored and PS3.5 8.7.4 entries corrected and the three density mappings documented (3.6) | script checks the stated reading |
| 2026-09-29 | D43, D39, D40, D41 (owner: "complete DICOMKit and DICOMNetwork modules work") | PS3.3 A.85.1.4.2, A.45.2.4, Tables C.24-1/C.24-2 (D43); Tables C.10-5, C.10-5a/5b/5c, C.10.5.1.3–C.10.5.1.3.14 and PS3.6 Table 6-1 (D39); PS3.5 6.3 and Table 6.2-1 (D40, D41) | See the Deferred findings rows. Arrows from this module now travel as ARROW compound graphics; each drawing's colour and halo as its Line/Text Style | `PDFRoundTripTests` pins; `GraphicAnnotationStyleTests` (DICOMKit, 6), `PrintOverlayCompoundGraphicTests` (4), a DICOMNetwork LO test; full `swift test` exits 0 (DICOMKitTests 1,558, DICOMNetworkTests 1,403, DICOMPrintKitTests 366) |

---

## Priority action list

| # | What | Standard | Impact | Status |
|---|---|---|---|---|
| P1 | D27/D36: presentation states written without the Type 1 Displayed Area Selection Sequence for fitted views, without the state's Modality LUT, and as GSPS for colour images | PS3.3 Table C.10-4, A.33.1.1, Table A.33.2-1; PS3.4 N.2.1.1 | **High:** every fitted saved view was a non-conformant object; a CT window was applied to stored values by any conforming viewer; colour images were referenced by an IOD that may only reference monochrome ones | ✅ |
| P2 | MONOCHROME1 polarity in saved views | PS3.4 N.2 | **High** for MONOCHROME1 (CR/DX/MG): a conforming viewer showed the saved view inverted | ✅ (DICOMKit side of the input; DICOMStudio must pass the photometric: D42) |
| P3 | `--raw` sent pixel modules Table C.13-5 does not allow | Table C.13-5 | Medium: a strict printer rejects the N-SET; ours clamps | ✅ |
| P4 | 10INX14IN sheet size | Table C.13-3 | Medium: every 10×14 film composed ~1 % narrow and ~2 % short | ✅ |
| P5 | Shutter pixel positions off by one | Table C.7-17a | Low: one extra shuttered row and column | ✅ |
| P6 | Printer Status Info, Text String LO, simulator Image Display Format, citations (D23) | C.13.9.1; PS3.5 Table 6.2-1; C.13.3/C.13.5.1; see Progress log | Low–Medium | ✅ |
| P-MAMMO | Medium Type MAMMO CLEAR FILM / MAMMO BLUE FILM not offered (D23 remainder) | PS3.3 Table C.13-1 | Medium | ✅ 2026-09-29, approved and implemented as recommended (Progress log). The recommendation was: add `MediumType.mammoClearFilm = "MAMMO CLEAR FILM"` and `.mammoBlueFilm = "MAMMO BLUE FILM"` in DICOMNetwork, deprecate `.mammoFilmClearBase`/`.mammoFilmBlueBase`, keep parsing both; then this catalogue offers the two new cases (tokens `mammo-clear-film`, `mammo-blue-film`). |
| P-GSDF | The film composer maps P-Values straight to device grey and numeric Border/Empty densities linearly between Min and Max Density | PS3.14 2026a 7.2: `j(p) = j_min + p/(2^N−1)·(j_max − j_min)`, `L = L_a + L_0·10^−D`; PS3.3 C.11.4 LIN OD; Table C.13-3 Illumination (2010,015E), Reflected Ambient Light (2010,0160) | Medium for the emulator's fidelity: the composed sheet is not the density a GSDF-calibrated printer produces; nothing on the wire changes | ✅ 2026-09-29, approved and implemented as recommended; L0/La are 7.2/7.3's typical values (ReceivedFilm does not carry Illumination/Reflected Ambient Light). The recommendation was: add `DensityMapping.gsdf` ("Calibrated (PS3.14)"): map each P-Value through the GSDF between `L(D_max)` and `L(D_min)` with `L_0`/`L_a` from the film box or 2000/10 cd/m² (7.2's typical values), render LIN OD and numeric densities in the same luminance space, encode to sRGB for the screen/PDF; keep `.paperDirect` the default so existing films and golden hashes stay identical. |
| P-CROP | CROP with no Requested Image Size | PS3.3 Table C.13-5: CROP applies "if the image rows or columns is greater than the available printable pixels"; Requested Image Size overrides "the size that corresponds with optimal filling", which is not defined | Low–Medium: the emulator (and the "Fill to Film" mode that sends CROP) reads it as *cover the cell*; a printer may read it as *fit* and print no crop | ✅ 2026-09-29, option (a) as recommended: the reading is kept and stated in `PRINT_CONFORMANCE.md` 3.5 (option (b), the strict fit reading, was not taken). |

### Decisions taken without asking (all within "fix behaviour that contradicts the standard")

- Additive public inputs only, all defaulted so every caller keeps compiling and keeps its old
  behaviour: `PresentationStateStore.ImageToSave(photometricInterpretation:rescaleType:)`,
  `ViewerPresentationStateBridge.capture(…photometricInterpretation:)` and
  `restore(…photometricInterpretation:)`, `FilmIdentificationFooter.textStringMaximumLength` and
  `textString(_:)`. No case, name or type was changed. With no photometric the store and bridge
  behave as before (monochrome, MONOCHROME2 polarity); DICOMStudio passes none yet (D42).
- The Modality LUT is written only when the rescale is not the identity (absence already means
  identity, N.2.1.1) and never for colour images. Rescale Type defaults to `US` (unspecified,
  C.11.1.1.2) when the caller does not know it.
- A colour image's inversion has no module in the Color Softcopy Presentation State, so it is kept
  in the private sidecar (`inverted`) and restored from there, the same way the palette is.
- A palette chosen on a colour image does not make a Pseudo-Color object (that IOD references
  monochrome images); the colour object wins and the palette stays in the sidecar.
- `--raw` frames the image box cannot carry are refused, not corrected: raw means the stored
  values are sent untouched, and every correction changes them. The message names the rule and
  says to print without `--raw`.
- The composer keeps reading YBR colour image boxes from third-party SCUs although Table C.13-5
  enumerates only RGB — refusing a film the emulator can show helps nobody; the leniency is
  documented at the site.
- The preparer's VOI precedence (the file's VOI LUT Sequence before its Window Center/Width) and
  its first-pair default are kept: C.11.2 permits either ("… or the VOI LUT, but not both at the
  same time, may be applied") and names no default; only the comments that attributed the order
  to the standard were corrected.
- Three DICOMStudio test pins (`NO SUPPLY` → `SUPPLY EMPTY`) and one DICOMPrintKit fixture pin
  (the shutter edge) were updated because they encoded the non-conformant values.

### Explicitly out of scope — do not chase

- The DIMSE sequence, the SCP parser, the pixel-depth clamp and the print enums themselves
  (DICOMNetwork, verified 2026-09-28). This pass only checks the values DICOMPrintKit uses.
- CoreGraphics/CoreText rendering, the PDF/PNG/TIFF writers and CUPS spooling (not DICOM).
- Burned-in reader annotations and patient corners: a local rendering choice with no DICOM
  attribute (documented in the files); only their photometric handling (MONOCHROME1) is scored.

---

## Deferred findings

Rows for this module from the earlier reports come first.

| ID | Module | Where | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D23 | DICOMPrintKit | [PrintOptionCatalog.swift](Sources/DICOMPrintKit/PrintOptionCatalog.swift) | Bits Stored 8/12 cited as Table C.13-3; `mediumTypes` omits the two MAMMO terms | PS3.3 Table C.13-5, C.13.1 (Table C.13-1) | Low | ✅ 2026-09-29 citations, `0913064` (also in PrintJobRequest, PrintImagePreparer); the MAMMO terms with P-MAMMO in the approval pass |
| D27 | DICOMPrintKit | `ViewerPresentationStateBridge.capture`, `PresentationStateStore.save` | No Displayed Area for fitted views (NC-4); no Modality LUT in the state (S-1b); GSPS for colour images (NC-3) | PS3.3 C.10.4, A.33.1.1, A.33.2; PS3.4 N.2.1.1 | High | ✅ 2026-09-29, `dc2c0f0`; MONOCHROME1 polarity (PS3.4 N.2) fixed with it |
| D30 | DICOMPrintKit | `PrintJobRequest.preprocessColorMode`, `PrintImagePreparer` | Map between two `PrintColorMode` types | — | Low | ✅ 2026-09-29 (closed in the DICOMKit pass; confirmed: `preprocessColorMode` returns `colorMode`) |
| D36 | DICOMStudio, DICOMPrintKit | callers of the GSPS / PCSPS builders | `imageSize:` not passed | PS3.3 Table C.10-4 | High | ✅ DICOMPrintKit half 2026-09-29, `dc2c0f0`: the store passes the size DICOMStudio already hands it in `ImageToSave`, so DICOMStudio's saves are fixed too. What DICOMStudio still has to pass (photometric, rescale type) is D42 |

New findings for other modules:

| ID | Module | Where | Problem | Standard | Severity | Status |
|---|---|---|---|---|---|---|
| D39 | DICOMKit | [GraphicAnnotation.swift](Sources/DICOMKit/PresentationState/GraphicAnnotation.swift), `GrayscalePresentationStateBuilder`, `GrayscalePresentationStateParser` | No Compound Graphic Sequence (0070,0209) — Compound Graphic Type ARROW, RULER, RECTANGLE … — and no Text Style / Line Style / Fill Style Sequence (per-object CIELab colour, shadow = the "halo"); DICOMPrintKit therefore writes an arrow as two polylines and every object in its layer's colour | PS3.3 Tables C.10-5, C.10-5a, C.10-5b, C.10-5c | Medium | ✅ 2026-09-29 at the owner's request (DICOMKit): `CompoundGraphic` (all ten Compound Graphic Types, units, rotation, gap, visibility, major ticks, tick alignment, fill; the 1C conditions of Table C.10-5 and the point counts of C.10.5.1.3.3–11), `TextStyle`, `LineStyle`, `FillStyle`, `GraphicShadow`; Compound Graphic Instance ID and Graphic Group ID on graphic and text objects; builder, parser (also anchor-only text objects) and `validate` (alternate rendering, unique IDs); the nine enumerations diffed by `diff_kit.py`. DICOMPrintKit writes arrows as ARROW compound graphics with the polylines as alternate rendering and every object's colour and halo in its style; it reads them back the same way |
| D40 | DICOMNetwork | [PrintPixelDepthConformance.swift:18](Sources/DICOMNetwork/PrintPixelDepthConformance.swift) | Cites "PS3.5 3.6.1" for Enumerated Values; no such section in 2026a (it is PS3.5 6.3) | PS3.5 6.3 | Low: text | ✅ 2026-09-29 (DICOMNetwork): cites PS3.5 6.3 |
| D41 | DICOMNetwork | [PrintService.swift](Sources/DICOMNetwork/PrintService.swift) (~L4305, Basic Annotation Box N-SET) | Text String (2030,0020) written as LO without the 64-character limit or the backslash rule; DICOMPrintKit's footer now complies, other `PrintAnnotation` callers do not | PS3.5 Table 6.2-1 | Low | ✅ 2026-09-29 (DICOMNetwork): `PrintAnnotation.textStringValue` (64 characters, no backslash or control characters) is what the SCU writes |
| D43 | DICOMKit tests | [Tests/DICOMRoundTripTest/PDFRoundTripTests.swift](Tests/DICOMRoundTripTest/PDFRoundTripTests.swift) (`testMIMETypeMapping`, `testOmittedOptionalFieldsAbsent`, `testWrapExtractCDABytesIdentical`, `testWrapExtractSTLBytesIdentical`) | Pin the behaviour from before P-ENCAP (`01fdeb66`); fail on HEAD `56115eaa` without any DICOMPrintKit change. Update the pins to the 2026a values the builder now writes (and set the HL7 Instance Identifier in the CDA fixture) | PS3.3 A.85 (STL `model/stl`), Table C.24-2, Tables A.45.x | Low: test only, but `swift test` exits 1 | ✅ 2026-09-29 at the owner's request: pins set to the 2026a values (STL `model/stl` A.85.1.4.2; CDA `text/XML` A.45.2.4 and an HL7 Instance Identifier, Table C.24-2; Series/Instance Number Type 1 = 1 and Document Title Type 2 empty, Tables C.24-1/C.24-2); full `swift test` exits 0 |
| D42 | DICOMStudio | [ImageViewerViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/ImageViewerViewModel+PresentationStates.swift) (~L460, 475, 610, 619, 1040), [PrintViewModel+PresentationStates.swift](Sources/DICOMStudio/ViewModels/PrintViewModel+PresentationStates.swift) (~L365) | Pass the image's Photometric Interpretation (and Rescale Type) to `ViewerPresentationStateBridge.capture/restore` and `ImageToSave`, so MONOCHROME1 images save and restore with the right Presentation LUT and colour images are saved as Color Softcopy Presentation States (D36 remainder) | PS3.4 N.2; PS3.3 A.33.1.1, Table A.33.2-1 | Medium | ✅ 2026-10-05 `6372e096` (audit 2026-10-06, was "⏳ Open"): see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md |

---

## Bucket B2 — No citation, data or behaviour differed from 2026a (14 files)

| File | Before | After |
|---|---|---|
| [PrintOptionCatalog.swift](Sources/DICOMPrintKit/PrintOptionCatalog.swift) | Bits Stored cited as Table C.13-3 (D23); MAMMO terms not offered | ✅ 31 offered values match Tables C.13-1/C.13-3/C.13-5/C.11-4 by script; citation C.13-5; all five Medium Type terms offered since P-MAMMO. Marked. |
| [PrintJobRequest.swift](Sources/DICOMPrintKit/PrintJobRequest.swift) | Bits Stored cited as Table C.13-3 in the doc and in the `--bit-depth` message (D23) | ✅ Table C.13-5. Marked. |
| [PrintImagePreparer.swift](Sources/DICOMPrintKit/PrintImagePreparer.swift) | `--raw` sent any source pixel module; Table C.13-3 cited in the clamp note; C.11.2 said to rank VOI LUT over window and make the first pair the default | ✅ raw frames checked against Table C.13-5 (7 enumerations + High Bit), refused with the rule; C.13-5 cited; C.11.2 choices documented as this toolkit's. Marked. |
| [PresentationState/PresentationStateStore.swift](Sources/DICOMPrintKit/PresentationState/PresentationStateStore.swift) | D27/D36; shutters one pixel in; Content Label called Presentation Label; state copies dropped Shutter Presentation Color | ✅ see Progress log. Marked. |
| [PresentationState/ViewerPresentationStateBridge.swift](Sources/DICOMPrintKit/PresentationState/ViewerPresentationStateBridge.swift) | Rotation/flip cited as C.10.10; MONOCHROME1 polarity ignored | ✅ C.10.6 confirmed (rotate, then flip — the vertical flip as 180° + horizontal is right); MONOCHROME1 folded both ways. Marked. |
| [PresentationState/AnnotationSidecar.swift](Sources/DICOMPrintKit/PresentationState/AnnotationSidecar.swift) | Said DICOM has no arrow primitive and no per-annotation colour | ✅ corrected against Tables C.10-5/5a/5b (D39); `inverted` for colour images. Marked. |
| [PresentationState/PrintOverlayAnnotationGSPS.swift](Sources/DICOMPrintKit/PresentationState/PrintOverlayAnnotationGSPS.swift) | Same claims; layer colour described as RGB | ✅ corrected; arrows written as ARROW compound graphics with their polylines as alternate rendering, per-object colour/halo in Line/Text Style Sequences, both read back (D39); Graphic Type, units, column/row order and frame numbers match Table C.10-5 / C.10.5.1.2; layer colour is (0070,0401). Marked. |
| [Printing/FilmGeometry.swift](Sources/DICOMPrintKit/Printing/FilmGeometry.swift) | 10INX14IN 254 × 355.6 mm; "C.13.6 (Film Size ID)"; CROP attributed to PS3.4 H.4.3 | ✅ 12 / 12 sheet sizes match Table C.13-3 by script; C.13.3; CROP per Table C.13-5, reading stated in PRINT_CONFORMANCE.md 3.5 (P-CROP); COL numbering column-major per C.13.5.1 confirmed. Marked. |
| [Printing/PresentationLUTTransform.swift](Sources/DICOMPrintKit/Printing/PresentationLUTTransform.swift) | Max Density (2010,1030); default densities attributed to C.13.3 | ✅ (2010,0130); defaults documented as the toolkit's; IDENTITY/LIN OD per C.11.4; LIN OD luminance per PS3.14 7.2 (La = 0). Marked. |
| [Printing/FilmComposer.swift](Sources/DICOMPrintKit/Printing/FilmComposer.swift) | C.11.6 cited for print; PS3.5 8.7.4 for YBR 4:2:2 | ✅ C.11.4; C.7.6.3.1.2 (YBR_FULL/PARTIAL_422 layout and inverse equations checked); polarity/MONOCHROME1 inversions per Table C.13-5 and C.7.6.3.1.2; `DensityMapping.gsdf` renders through the PS3.14 GSDF (P-GSDF). Marked. |
| [Printing/GrayscaleStandardDisplayFunction.swift](Sources/DICOMPrintKit/Printing/GrayscaleStandardDisplayFunction.swift) | (new, P-GSDF) | ✅ 19 coefficients of PS3.14 7.1 diffed by script; 7.2/7.3 viewing; Table D.2-1 reproduced within 0.0015 OD. Marked. |
| [Printing/PrintSCPSettings.swift](Sources/DICOMPrintKit/Printing/PrintSCPSettings.swift) | FAILURE default Printer Status Info `NO SUPPLY` | ✅ `SUPPLY EMPTY`; statuses match Table C.13-9. Marked. |
| [Printing/PrintSCPSimulator.swift](Sources/DICOMPrintKit/Printing/PrintSCPSimulator.swift) | Film box written with the bounding grid, not the job's Image Display Format | ✅ the job's format (C.13.3, C.13.5.1). Marked. |
| [Printing/FilmIdentification.swift](Sources/DICOMPrintKit/Printing/FilmIdentification.swift) | Footer Text String sent unchecked | ✅ LO per PS3.5 Table 6.2-1. Marked. |

## Bucket C1 — Plumbing (9 files)

| File | Confirmed | Result |
|---|---|---|
| [PrintConsoleFormatter.swift](Sources/DICOMPrintKit/PrintConsoleFormatter.swift) | carries no DICOM-standard data (text and JSON for values DICOMNetwork parses) | ✅ Marked |
| [PrintPresentationTransform.swift](Sources/DICOMPrintKit/PrintPresentationTransform.swift) | carries no DICOM-standard data (crop, rotate, flip, invert of prepared pixels) | ✅ Marked |
| [Printing/PrintCornerAnnotation.swift](Sources/DICOMPrintKit/Printing/PrintCornerAnnotation.swift) | carries no DICOM-standard data | ✅ Marked |
| [Printing/PrintAnnotationLayout.swift](Sources/DICOMPrintKit/Printing/PrintAnnotationLayout.swift) | carries no DICOM-standard data (plane geometry) | ✅ Marked |
| [Printing/PrintArrowGeometry.swift](Sources/DICOMPrintKit/Printing/PrintArrowGeometry.swift) | carries no DICOM-standard data | ✅ Marked |
| [Printing/PrintSCPService.swift](Sources/DICOMPrintKit/Printing/PrintSCPService.swift) | carries no DICOM-standard data (assembly) | ✅ Marked |
| [Printing/PrintOverlayOrientation.swift](Sources/DICOMPrintKit/Printing/PrintOverlayOrientation.swift) | carries no DICOM-standard data (annotation mapping) | ✅ Marked |
| [Printing/PrintOutputSink.swift](Sources/DICOMPrintKit/Printing/PrintOutputSink.swift) | carries no DICOM-standard data (sinks) | ✅ Marked |
| [Printing/PrintSCPConsole.swift](Sources/DICOMPrintKit/Printing/PrintSCPConsole.swift) | carries no DICOM-standard data (status codes come from DICOMNetwork) | ✅ Marked |

## Bucket C2 — Standard-derived, edition-stable (8 files)

| File | Compared | Result |
|---|---|---|
| [PrintCellPlacement.swift](Sources/DICOMPrintKit/PrintCellPlacement.swift) | (2020,0030), (2020,0040) DECIMATE/CROP per Table C.13-5; (0028,0030), (0018,1164), (0018,2010) per PS3.6 and PS3.3 10.7 | ✅ match; Fill-to-Film note points at P-CROP. Marked. |
| [PrintWorkflow.swift](Sources/DICOMPrintKit/PrintWorkflow.swift) | Printer Status FAILURE/WARNING (Table C.13-9); Samples per Pixel 1 / 3 per image box class (Table C.13-5) | ✅ match. Marked. |
| [ViewerPresentation.swift](Sources/DICOMPrintKit/ViewerPresentation.swift) | its one citation (Basic Color Image Sequence RGB only, Table C.13-5) | ✅ match. Marked. |
| [Printing/FilmComposingPrintHandler.swift](Sources/DICOMPrintKit/Printing/FilmComposingPrintHandler.swift) | default Printer Status NORMAL (Table C.13-9) | ✅ match. Marked. |
| [Printing/PrintCellPadding.swift](Sources/DICOMPrintKit/Printing/PrintCellPadding.swift) | MONOCHROME1 background (C.7.6.3.1.2); 8-bit pixels (Table C.13-5) | ✅ match. Marked. |
| [Printing/PrintOverlayAnnotation.swift](Sources/DICOMPrintKit/Printing/PrintOverlayAnnotation.swift) | point conventions of POINT, POLYLINE, INTERPOLATED, CIRCLE, ELLIPSE (C.10.5.1.2) | ✅ match. Marked. |
| [Printing/ComposedFilm.swift](Sources/DICOMPrintKit/Printing/ComposedFilm.swift) | 13 tag names in `ComposedFilmInfo` (PS3.6 Table 6-1, by script) | ✅ match. Marked. |
| [Printing/ImageAnnotationBurner.swift](Sources/DICOMPrintKit/Printing/ImageAnnotationBurner.swift) | MONOCHROME1 polarity of burned text (C.7.6.3.1.2); 8-bit grayscale/RGB pixels (Table C.13-5) | ✅ match. Marked. |

---

## Verification notes

- **Scripted checks** ([Scripts/diff_printkit.py](Scripts/diff_printkit.py), 32 checks): UID
  literals (PS3.6 Table A-1); the print SOP classes the module names, resolved in DICOMNetwork and
  checked against Table A-1 and the meta SOP class tables (PS3.4 Tables H.3.2.2.1-1, H.3.2.2.2-1);
  the presentation-state SOP classes the store adopts; every value `PrintOptionCatalog` offers,
  resolved to the DICOMNetwork raw value it sends (and to the wire value for Presentation LUT
  Shape) and compared with the term list of its attribute row (Tables C.13-1, C.13-3, C.13-5,
  C.11-4 — these tables have no Type column, so the rows are read by their first cell), both
  directions; density names and grayscale bit depths; the raw-mode Table C.13-5 enumerations; Printer
  Status (Table C.13-9) and the 108 Printer Status Info Defined Terms (C.13.9.1); the physical size
  of every Film Size ID (inch/cm terms computed, the three metric equivalents read from the C.13-3
  cell); names next to every `(GGGG,EEEE)` in comments and messages (comment lines joined, so a
  wrapped name is read whole); `diff_kit`'s tag-literal names, typed reads, explicit VRs, citation
  existence and photometric literals; a topic check (a sentence about Bits Stored, Film Size ID,
  LIN OD, rotation/flip, Displayed Area or shutters must cite the clause that governs it); section
  titles given in parentheses; the Presentation Size Mode, Annotation Units, Graphic Type and
  Image Rotation values the bridge writes (Tables C.10-4, C.10-5, C.10-6); the builder call sites
  (image size, Modality LUT, colour IOD); the LO Text String; the shutter conversion; and two
  pending-decision probes (GSDF, CROP).
- **Read against the text, not scripted:** the composer's YBR conversions (C.7.6.3.1.2), the
  polarity/MONOCHROME1/Presentation LUT inversion order, the Image Display Format layouts and box
  numbering (C.13.3, C.13.5.1), the spatial-transformation fold (C.10.6), Displayed Area corners
  (C.10.4), the Modality LUT rule (PS3.4 N.2.1.1), the MONOCHROME1 rule (N.2), the VOI rules
  (C.11.2), PS3.14 7.2/7.3.
- **A misprint in the standard:** PS3.3 2026a C.11.4 writes "Max Density (2010,1030)" in the LIN
  OD definition; PS3.6 Table 6-1 (and Table C.13-3) have Max Density at (2010,0130). The code
  follows PS3.6.
- **DICOMNetwork data relied on** (verified 2026-09-28): the print enums, SOP Class constants,
  `PrintImageDisplayFormat.parse` (STANDARD\C,R is columns first — confirmed against C.13.3), the
  SCP's colour-by-plane to colour-by-pixel conversion (so the composer's interleaved reading is
  right), the SCU's Planar Configuration 1 on the wire.
- **Compatibility consequences:** saved views written before this pass have no Displayed Area
  for fitted views and no Modality LUT; they are still read (the absence restores as "fit" and
  the window is used as before). A 10×14 film is composed on a slightly larger sheet. Raw jobs of
  signed, 16-bit-stored, YBR or PALETTE COLOR images now fail with a message instead of printing.
- **Tests at the start** (HEAD `56115eaa`, clean worktree, `swift test --filter DICOMPrintKitTests`):
  323 XCTest cases (1 skipped — `DCMTKInteropTests.testDCMTKPrintSCUCanPrintToOurEmulator`, no
  sample image for the DCMTK tools) and 84 swift-testing tests, 0 failures.
- **Tests at the end** (2026-09-29, `swift build` then the full `swift test`, after
  `swift build -c release --product dicom-merge` and `--product dicom-split` for the CLI parity
  suite): DICOMPrintKitTests 351 XCTest cases (the same 1 skipped) and 84 swift-testing tests pass —
  28 new tests (`PresentationStateIODConformanceTests` 16, `PrintManagementConformanceTests` 11,
  `FilmGeometryTests` +1). Every other bundle passes: DICOMCoreTests 85, DICOMKitTests 1,552 (11
  skipped), DICOMNetworkTests 1,401, DICOMRenderKitTests 92 (14 skipped), DICOMStudioTests 40,
  DICOMViewerTests 51, DICOMWebTests 447 XCTest cases, and every swift-testing run (5,165 + 1,506
  + 751 + 630 + 474 + 226 + 84 + 53 + 30 + 20), **except** DICOMRoundTripTests (528 cases, 18
  skipped): 4 cases of `PDFRoundTripTests` fail (9 assertions), so `swift test` exits 1.
- **Tests after the approval pass** (2026-09-29, full `swift test` after rebuilding dicom-merge and
  dicom-split in release): DICOMPrintKitTests 362 XCTest cases (1 skipped; +11: `PrintGSDFTests`
  9, two Medium Type tests) and 84 swift-testing tests; DICOMNetworkTests 1,402 (+1 legacy-spelling
  test; four pins moved to the new cases); every other bundle and swift-testing run as in the first
  pass. After D43 was closed (the four `PDFRoundTripTests` pins moved to the 2026a values),
  DICOMRoundTripTests passes too (528 cases, 18 skipped) and the full `swift test` exits 0.
- **Annex D.2 inconsistency (NEMA text):** D.2 quotes j_max = 848.75 for L_max = 1271.9 cd/m²;
  both 7.1 j(L) and inverting L(j) give 847.2, and 848.75 would put P-Value 255 at 0.196 OD where
  Table D.2-1 prints 0.200. The implementation matches the table (all 256 rows within 0.0015 OD;
  the table is printed to three decimals).
- **Commits** (local, `feature/dicom-tag-modality-audit`): `bb46504` diff script, `dc2c0f0`
  presentation states (D27, D36), `0913064` print management (D23), `54bb02f` markers on the
  C1/C2 files, `013456a` this report, CHANGELOG and status tables; then the approval pass:
  P-MAMMO (DICOMNetwork + catalogue), P-GSDF (composer), P-CROP and the reports.
- **That failure is pre-existing, proved on the untouched HEAD worktree**
  (`swift test --filter PDFRoundTripTests` at `56115eaa`: the same 4 cases, the same 9
  assertions). The test file still pins the encapsulated-document behaviour from before the
  DICOMKit P-ENCAP commit `01fdeb66` (STL MIME `application/sla` where A.85 now writes
  `model/stl`; Series/Instance Number and Document Title expected absent where the builder now
  writes the Type 1/2 attributes; a CDA wrapped without the Type 1C HL7 Instance Identifier of
  Table C.24-2). Nothing in DICOMPrintKit is involved; logged as D43.
