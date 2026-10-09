# DICOM 2026a Full Modality Coverage — Implementation Plan

**Status:** ✅ Complete — all five phases implemented and verified
**Scope:** DICOMKit library, all `dicom-*` CLI tools, DICOMStudio app
**Out of scope:** DICOMToolbox (see §3.4)
**Standard reference:** DICOM PS3.3 C.7.3.1.1.1 (Modality, `(0008,0060)` Defined Terms) and PS3.16 CID 29 (Acquisition Modality), 2026a

---

## 1. Problem statement

The repository has **no canonical `Modality` type**. Modality is a bare `String` everywhere in the library targets, and at least five mutually inconsistent hand-maintained lists exist:

| # | Location | Codes | Purpose |
|---|---|---|---|
| 1 | `Sources/DICOMStudio/Components/ModalityIcon.swift:24-50` | 26 | icons + display names (de-facto source of truth) |
| 2 | `Sources/DICOMStudio/Components/WindowLevelPresets.swift:122-157` | 8 + 3 aliases | window/level presets |
| 3 | `Sources/DICOMToolbox/Models/ToolRegistry.swift:582-588` | 5 | `dicom-query --modality` dropdown — *out of scope, see §3.4* |
| 4 | `Sources/DICOMKit/Multiframe/MultiframeSOPClassMap.swift:220-230` | 6 | SOP Class → Modality |
| 5 | `Sources/DICOMKit/Validation/DICOMValidator.swift` (6 sites) | 6 literals | per-IOD validation |

Consequences visible today:

- **The standard's list is 2026a; ours is a 26-code subset.** 79 current + 18 retired codes exist; we recognize 26.
- **Codes the library itself emits are not in the app's list.** `WaveformBuilder` emits `AU`, `EPS`, `RESP`; `EncapsulatedDocumentWorkflow` emits `M3D`; `StudyOrganizer` emits the non-standard `XX`. All fall through to the default icon and an uppercased raw string instead of a name.
- **Ophthalmic tomography is unrepresented.** `OPT`, `OPTENF`, `OPTBSV`, `OCT`, `IVOCT`, `OPM`, `OAM`, `OPV` appear nowhere in the repo — only `OP` exists.
- **Four divergent icon/color maps.** `ModalityIcon` (26 codes), `FileOperationsHelpers.swift:55-68` (9 groups, uses non-DICOM `XR`), `StudioTheme.swift:98-106` (4 groups), `ThumbnailHelpers.swift:49-67` (7 groups).
- **Two divergent alias tables.** `ModalityMapping.normalize` (`MRI`→`MR`, `PET`→`PT`, `RT*`→`RT`, `PDF`→`DOC`) vs. `WindowLevelPresets.presets(for:)` (`MRI`, `RG`, `RF` aliases the first table does not know).
- **`RT` is not a DICOM modality code.** The standard defines `RTIMAGE`, `RTPLAN`, `RTDOSE`, `RTSTRUCT`, `RTRECORD`, `RTINTENT`, `RTRAD`, `RTSEGANN`. Our `RT` is an invention that `normalize` collapses real codes onto, losing information.
- **No CLI tool validates `--modality` at all.** Validation exists only in the app's picker UI.

---

## 2. The authoritative 2026a list

### 2.1 Current (non-retired) — 79 codes

> Count verified programmatically against the fetched PS3.3 list during Phase 1;
> an earlier draft of this plan said 80, which was a hand-tally error.

| Code | Meaning | | Code | Meaning |
|---|---|---|---|---|
| `ANN` | Annotation | | `OPTENF` | Ophthalmic Tomography En Face |
| `AR` | Autorefraction | | `OPV` | Ophthalmic Visual Field |
| `ASMT` | Content Assessment Results | | `OSS` | Optical Surface Scan |
| `AU` | Audio | | `OT` | Other |
| `BDUS` | Bone Densitometry (ultrasound) | | `PA` | Photoacoustic |
| `BI` | Biomagnetic Imaging | | `PLAN` | Plan |
| `BMD` | Bone Densitometry (X-Ray) | | `POS` | Position Sensor |
| `CFM` | Confocal Microscopy | | `PR` | Presentation State |
| `CR` | Computed Radiography | | `PT` | Positron Emission Tomography |
| `CT` | Computed Tomography | | `PX` | Panoramic X-Ray |
| `CTPROTOCOL` | CT Protocol (Performed) | | `REG` | Registration |
| `DG` | Diaphanography | | `RESP` | Respiratory Waveform |
| `DMS` | Dermoscopy | | `RF` | Radiofluoroscopy |
| `DOC` | Document | | `RG` | Radiographic Imaging |
| `DX` | Digital Radiography | | `RTDOSE` | Radiotherapy Dose |
| `ECG` | Electrocardiography | | `RTIMAGE` | Radiotherapy Image |
| `EEG` | Electroencephalography | | `RTINTENT` | Radiotherapy Intent |
| `EMG` | Electromyography | | `RTPLAN` | Radiotherapy Plan |
| `EOG` | Electrooculography | | `RTRAD` | RT Radiation |
| `EPS` | Cardiac Electrophysiology | | `RTRECORD` | RT Treatment Record |
| `ES` | Endoscopy | | `RTSEGANN` | Radiotherapy Segment Annotation |
| `FID` | Fiducials | | `RTSTRUCT` | Radiotherapy Structure Set |
| `GM` | General Microscopy | | `RWV` | Real World Value Map |
| `HC` | Hard Copy | | `SEG` | Segmentation |
| `HD` | Hemodynamic Waveform | | `SM` | Slide Microscopy |
| `IO` | Intra-Oral Radiography | | `SMR` | Stereometric Relationship |
| `IOL` | Intraocular Lens Data | | `SR` | SR Document |
| `IVOCT` | Intravascular OCT | | `SRF` | Subjective Refraction |
| `IVUS` | Intravascular Ultrasound | | `STAIN` | Automated Slide Stainer |
| `KER` | Keratometry | | `TEXTUREMAP` | Texture Map |
| `KO` | Key Object Selection | | `TG` | Thermography |
| `LEN` | Lensometry | | `US` | Ultrasound |
| `LS` | Laser Surface Scan | | `VA` | Visual Acuity |
| `M3D` | Model for 3D Manufacturing | | `XA` | X-Ray Angiography |
| `MG` | Mammography | | `XAPROTOCOL` | XA Protocol (Performed) |
| `MR` | Magnetic Resonance | | `XC` | External-Camera Photography |
| `NM` | Nuclear Medicine | | | |
| `OAM` | Ophthalmic Axial Measurements | | | |
| `OCT` | Optical Coherence Tomography (non-Ophthalmic) | | | |
| `OP` | Ophthalmic Photography | | | |
| `OPM` | Ophthalmic Mapping | | | |
| `OPT` | Ophthalmic Tomography | | | |
| `OPTBSV` | Ophthalmic Tomography B-scan Volume Analysis | | | |

### 2.2 Retired — 18 codes

`AS` Angioscopy · `CD` Color Flow Doppler · `CF` Cinefluorography · `CP` Culposcopy · `CS` Cystoscopy · `DD` Duplex Doppler · `DF` Digital Fluoroscopy · `DM` Digital Microscopy · `DS` Digital Subtraction Angiography · `EC` Echocardiography · `FA` Fluorescein Angiography · `FS` Fundoscopy · `LP` Laparoscopy · `MA` MR Angiography · `MS` MR Spectroscopy · `OPR` Ophthalmic Refraction · `ST` SPECT · `VF` Videofluorography

Retired codes are **recognized but not offered**: parsed and displayed for legacy data, flagged by validation, and excluded from pickers and `--modality` completion.

### 2.3 Non-standard codes currently in the repo

| Code | Where | Disposition |
|---|---|---|
| `SC` | `ModalityIcon`, `DataExchangeViewModel:73` | **Keep as an alias → `OT`.** Not a Defined Term, but universally used for Secondary Capture. Recognized, flagged by validation, not offered in pickers. |
| `VL` | `ModalityIcon` | **Keep as an alias → `OT`.** Same reasoning; "Visible Light" is a SOP class family, not a modality code. |
| `RT` | `ModalityIcon`, `normalize` | **Demote.** Replaced by the eight real `RT*` codes. `RT` becomes a recognized legacy alias mapping to `RTIMAGE`. |
| `XX` | `StudyOrganizer.swift:115` | **Replace with `OT`** — it is a directory-name placeholder with no standard basis. |
| `XR`, `DR` | `FileOperationsHelpers:55-68`, `PatientOverlayText:254-281` | **Alias → `DX`.** Non-standard vendor spellings. |
| `MRI`, `PET`, `PDF` | `normalize` | **Keep as aliases** → `MR`, `PT`, `DOC`. |

---

## 3. Design

### 3.1 New canonical type — `Sources/DICOMCore/Modality.swift`

`DICOMCore` is the right home: every other library target, every CLI tool and the app already depend on it, directly or transitively. (`DICOMToolbox` does not, but it is out of scope — see §3.4.)

```swift
public struct Modality: RawRepresentable, Hashable, Sendable, Codable,
                        CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String          // the CS value, uppercased & trimmed
    public init?(rawValue: String)       // nil for values that are not a known code
    public init(unchecked rawValue: String)   // preserves unknown private codes

    public var name: String              // "Computed Tomography"
    public var isRetired: Bool
    public var isStandard: Bool          // false for SC, VL, and unknown codes
    public var category: Category        // .crossSectional, .radiography, .ophthalmic, …

    public static let allCases: [Modality]      // 79 current, standard order
    public static let allIncludingRetired: [Modality]
    public static func normalized(_ raw: String) -> Modality?   // applies the alias table
}
```

Design decisions, and why:

- **A `struct` with a `RawRepresentable` failable init, not an `enum`.** DICOM `(0008,0060)` is a *Defined Term*, not an Enumerated Value — private and future codes are legal on the wire. An `enum` would force every parse site to either drop or crash on an unrecognized code; `init(unchecked:)` round-trips it losslessly while `isStandard` reports the truth. This is the single most important constraint on the design, and it is why the existing `StandardModality` enum cannot simply be extended in place.
- **Static constants, not enum cases:** `Modality.ct`, `.mr`, `.opt`, … so call sites read the same as they would with an enum.
- **One alias table**, replacing the two that exist today.
- **`Category`** is what lets the UI group 79 codes sensibly and lets presets/icons have a fallback per family instead of per code.

### 3.2 Replacing `ModalityMapping`

`ModalityIcon.swift` keeps the SwiftUI `ModalityIcon` view and the SF Symbol map, but `StandardModality` is deleted and the icon/name functions delegate to `DICOMCore.Modality`. Icons are assigned **per `Category`**, with per-code overrides only where one is genuinely distinct — 79 hand-picked SF Symbols would be noise.

`ModalityMapping.allCodes`, `systemImage(for:)`, `fullName(for:)` and `normalize(_:)` keep their signatures so the ~10 call sites don't churn; `allCodes` grows from 26 to 79.

### 3.3 Window/level presets

Presets stay a curated set — inventing a window for `TEXTUREMAP` would be a fabricated clinical number, which is worse than none. The changes are:

- Key `presets(for:)` on `Modality` and resolve aliases through the one table (this is what fixes the `MRI`/`RG`/`RF` divergence).
- Add presets for genuinely windowed modalities we now recognize: `RG`, `PX`, `IO`, `BMD`, `IVUS`, `IVOCT`, `OPT`.
- Leave display-ready modalities (`US`, `ES`, `GM`, `XC`, `SM`, `DMS`, …) without presets, as `US` is today, and document why.

### 3.4 `DICOMToolbox` — out of scope (DECIDED)

`DICOMToolbox` is **excluded from this work.** Its 5-code list at
`ToolRegistry.swift:582-588` stays as it is.

Rationale, from the evidence:

- It is **effectively unmaintained**. Last targeted commit is old; its most recent
  change (`7bdd92e`, 2026-09-05) was an incidental repo-wide cross-platform build
  sweep. 15 commits in 12 months vs. 70 for Studio's CLI Workshop.
- It has **no `@main` and no consumer**. Nothing in `Sources/` imports it; only
  `Tests/DICOMToolboxTests` does. It is a published product that nothing runs.
- It was **superseded in practice** by Studio's CLI Workshop
  (`CLIWorkshopHelpers.swift` + `CLIWorkshopViewModel.swift`, 15,590 lines, 33 tools
  vs. Toolbox's 8,369 lines and 30 tools). The plan at `DICOM_STUDIO_PLAN.md:1827`
  to reuse Toolbox's `CommandBuilder`/`CommandExecutor` in Studio was never carried out.

Neither adding a `DICOMCore` dependency nor building a generator is worth it for a
module in this state. **Follow-up, tracked separately:** DICOMToolbox and Studio's
CLI Workshop are two implementations of the same GUI, and that duplication is the
root cause of the list divergence this plan is fixing. Consolidating or retiring
Toolbox deserves its own ticket; it is out of scope here.

### 3.5 CLI validation

Add a shared `--modality` validator in `DICOMCore` used by every tool that takes the flag (`dicom-mwl`, `dicom-query`, `dicom-qr`, `dicom-wado`, `dicom-mpps`, `dicom-archive`, `dicom-image`, `dicom-pdf`, `dicom-video`):

- Unknown code → **warning, not an error** (private codes are legal). `--strict-modality` promotes it to an error.
- Retired code → warning naming the current replacement.
- Alias → silently normalized, with a note at `--verbose`.
- Help text changes from `"e.g., CT, MR, US"` to a pointer at `--list-modalities`, a new flag printing all 79 grouped by category.

---

## 4. Work plan

### Phase 1 — Canonical type
1. `Sources/DICOMCore/Modality.swift` — the type, all 79 + 18 codes, names, categories, alias table. **DONE** — 29 tests passing.
2. `Tests/DICOMCoreTests/ModalityTests.swift` — every code round-trips; retired flagged; aliases normalize; unknown codes preserved via `init(unchecked:)`; `allCases.count == 79`. **DONE**

### Phase 2 — Library adoption ✅ DONE
3. `DICOMValidator.swift` (6 sites) — replace `modality != "X"` literals with `Modality` comparisons; add a Defined-Term check for `(0008,0060)`. **DONE** — also fixes a latent bug: those sites previously rejected `MRI`/`PET` as wrong-modality.
4. `MultiframeSOPClassMap.swift:220-230` — return `Modality`.
5. De-duplicate `["CT","MR","PT"]` / `== "MR"` between `FunctionalGroupBuilder.swift:420-427` and `FrameMerger.swift:580-590` into one `Modality.Category` check.
6. `Video.swift:424-430`, `WaveformBuilder.swift:289-306`, `EncapsulatedDocumentWorkflow.swift:52-59`, `SecondaryCaptureImage.swift:299-301` — return `Modality`.
7. `StudyOrganizer.swift:115` — `XX` → `OT`. **DONE** — plus two further `XX` fallbacks found in `FrameSplitter.swift:570,672` that the original inventory missed.
8. `ModalityWorklistService.swift` — normalize inbound HL7 OBR-24 / IPC-5 modality values.

### Phase 3 — App adoption ✅ DONE
9. Delete `StandardModality`; rewire `ModalityIcon.swift` onto `Modality` with category-based icons. **DONE**
10. `WindowLevelPresets.swift` — re-key on `Modality`, add the new presets (§3.3). **DONE** — 25 → 37 presets (added RG, PX, IO, BMD, IVUS, OPT).
11. Unify the divergent maps: `FileOperationsHelpers.swift:55-68`, `StudioTheme.swift:98-106`, `ThumbnailHelpers.swift:49-67` all delegate to `Modality.Category`.
12. `PatientOverlayText.swift:254-281` — re-key on category; `DR`/`PX` handled by the alias table.
13. Replace the free-text modality `TextField`s with pickers where a fixed choice is right. **DONE** — new `ModalityPicker` (sectioned by category, keeps out-of-list bound values selectable) in `NetworkingView`, `DataExchangeView`, `ArchiveManagementView`.

### Phase 4 — CLI + Toolbox ✅ DONE
14. Shared `--modality` validator across the 9 tools in §3.5. **DONE** — `ModalityOptionValidator` in DICOMCore, plus `--strict-modality` on each tool.

    **Deviation from §3.5:** `--list-modalities` could not be a per-tool flag. Every one of the 9 tools has a *required positional argument* (host, URL or input path), so `dicom-query --list-modalities` fails argument parsing before `run()` is reached. The listing instead lives on `dicom-tags --list-modalities`, whose input argument was made optional, and every `--modality` help string points there.
15. `CLIWorkshopHelpers.swift:73` — picker grows to 79. **DONE** — it already read `ModalityMapping.allCodes`, so it grew automatically; `ModalityPicker` provides category grouping for views that can section.

### Phase 5 — Verification ✅ DONE
17. `swift build` + full `swift test`. **DONE** — build clean; zero Swift Testing failures. Six XCTest failures remain in `DICOMNetworkTests` (character-set encoding + an ARTIM timeout); all are in *untracked* test files that do not exist in HEAD and are unrelated to modality.
18. A test asserting every modality the library *emits* is recognized by the app's display path. **DONE** — `testLibraryEmittedCodesAreDisplayable`, checking both name and icon.
19. `CHANGELOG.md`. **DONE**. `Documentation/` needed no change — no doc enumerates the modality list.
20. **Added during Phase 5:** five raw literals still written to `(0008,0060)` (`dicom-ai` SEG/PR, `dicom-gateway` OT ×2, `JP3DVolumeDocument` DOC) now go through `Modality`; inbound HL7 and FHIR modality values are normalized (plan item 8).

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| **Source-breaking**: `ModalityMapping.StandardModality` is `public` | Keep `ModalityMapping`'s function signatures; only the nested enum is removed. If the library is API-stable for external consumers, mark it `@available(*, deprecated)` for one release instead of deleting. **Needs a call — is `DICOMStudio` a published product?** |
| `RT` demotion changes icons for existing RT data | `RT` stays a recognized alias → `RTIMAGE`; real `RT*` codes now render distinctly. Net improvement, but visibly different. |
| 79-item pickers are unusable flat | Grouped by `Category`, searchable. |

---

## 6. Decisions taken

All four open questions are resolved; no blockers remain.

1. **`DICOMToolbox`** — **out of scope.** Its 5-code list is left untouched; the module
   is unmaintained and has no consumer (§3.4). Consolidation tracked separately.
2. **`ModalityMapping.StandardModality` deletion** — **delete outright, no deprecation.**
   `DICOMStudio` is not in `Package.swift`'s `products`, so no external consumer can
   import it; inside the repo the enum is referenced only by its own file
   (`ModalityIcon.swift`). The public function signatures (`allCodes`,
   `systemImage(for:)`, `fullName(for:)`, `normalize(_:)`) are preserved, so call
   sites are unaffected.
   *Caveat:* if a private repo outside this one imports `DICOMStudio` directly, confirm
   before deleting.
3. **Retired codes** — **recognized but never offered.** Parsed and displayed for legacy
   data, flagged by validation, excluded from pickers and `--modality` completion.
4. **`SC` / `VL`** — **kept as recognized non-standard aliases** (→ `OT`). Dropping them
   would regress existing data.
