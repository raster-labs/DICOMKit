# DICOM 2026a verification audit — DICOMKit package

Date 2026-10-06 · branch `feature/dicom-tag-modality-audit` · local commits only, nothing pushed.
Audit at `fca194a3` (DICOMStudio close) → audit document `5ec7381f` → follow-up `7a3aac80` … `2df71725` (the owner's instruction of 2026-10-06: "complete all deferred items which are open as per the recommendation and leave D216, D221 and D256") → P-item pass `824bcfab` … `071ad9c0` (the owner's instruction of 2026-10-06: "complete everything as per the recommendation" other than the deferred rows; MWL create kept in the app only).

Method: [DICOMCORE_STANDARD_IMPLEMENTATION.md](DICOMCORE_STANDARD_IMPLEMENTATION.md) "Verification method" and "Definition of done for a module". Evidence is script output against the frozen 2026a DocBook (`Scripts/nema_docbook.py fetch 2026a <part>`, parts 3, 4, 5, 6, 7, 8, 10, 11, 14, 15, 16, 18, 19, in a scratch directory deleted afterwards) and the report tables. Doc comments, READMEs and memory are not evidence. Scope: DICOMCore, DICOMDictionary, DICOMKit, DICOMNetwork, DICOMWeb, DICOMPrintKit, DICOMRenderKit, the 42 `dicom-*` tools, DICOMStudio + DICOMStudioApp. DICOMToolbox is out of scope.

**Current result:** all 9 modules meet the definition of done. Every diff script ends with 0 wrong / 0 FAIL, every marker check exits 0, and the full `swift test` exits 0. Of the 276 deferred rows, 271 are closed, 3 are open by the owner's decision (D216, D221, D256) and 2 are void numbers. The 14 P-STUDIO-* items were approved by the owner on 2026-10-06 and implemented (§5.1; Studio open P-items: 0), and the Studio parity changes and the follow-up's behaviour changes are confirmed (§5.2, §5.3). Still waiting on the owner only for D216 / D221 / D256 (§5.4) and the findings of the P-item pass (§5.5).

This document is in two parts. **Part 1** (§1–§5) is the current state. **Part 2** (§H1–§H3) is the history: the audit as found at `fca194a3` with the bookkeeping it fixed, the follow-up log with every commit, and the P-item pass log.

# Part 1 — Current state

## 1. Per-module status

| Module | Swift files | Marked | `check_nema_markers.py` | Diff script (last line) | Open D-rows | Open P-items | Definition of done |
|---|---|---|---|---|---|---|---|
| DICOMCore | 108 | 108 | exit 0 | `diff_sr_templates.py`: 73 templates, 646 rows, 0 differences | 0 | 0 | ✅ met |
| DICOMDictionary | 5 | 5 | exit 0 | `diff_dictionary.py`: 0 differences (elements 5,326; UIDs 465; B.5-1 170; B.6-1 4) | 0 | 0 | ✅ met |
| DICOMKit | 185 | 185 | exit 0 | `diff_kit.py`: 0 wrong, 0 pending; the DICOMDIR and confidentiality generators' `--check` modes match | 0 | 0 | ✅ met |
| DICOMNetwork | 66 | 66 | exit 0 | `diff_network.py`: 0 wrong | 0 | 0 | ✅ met |
| DICOMWeb | 57 | 57 | exit 0 | `diff_web.py`: 0 wrong, 0 pending | 0 | 0 | ✅ met |
| DICOMPrintKit | 31 | 31 | exit 0 | `diff_printkit.py`: 0 wrong, 0 pending | 0 | 0 | ✅ met |
| DICOMRenderKit | 10 | 10 | exit 0 | `diff_renderkit.py`: 17 ok, 0 failing, 0 pending, 0 deferred | 0 | 0 | ✅ met |
| `dicom-*` CLI (42 tools) | 100 | 100 | exit 0 for all 42 directories | `diff_cli.py`: 0 FAIL; `diff_cli_web.py`: 0 FAIL; `cli_contracts.py --check` exit 0 | D216, D221 (owner decision) | 0 | ✅ met |
| DICOMStudio + DICOMStudioApp | 338 | 173 (+165 inventoried as not standard-touching) | exit 0 (`--inventory`) | `diff_studio.py`: 0 FAIL, 0 PEND (222 checks ok) | D256 (owner decision) | 0 | ✅ met (all P-items approved and implemented 2026-10-06) |

## 2. Script evidence

| Script | Last line |
|---|---|
| `diff_dictionary.py part06 part07 part04` | `0 differences` |
| `diff_sr_templates.py part16` | `73 templates, 646 rows compared, 0 differences` |
| `diff_kit.py --nema` | `0 check(s) with wrong or missing values, 0 pending owner approval` |
| `diff_network.py --nema` | `0 check(s) with wrong or missing values` |
| `diff_web.py --nema` | `0 check(s) with wrong or missing values, 0 pending owner approval` |
| `diff_printkit.py --nema` | `0 check(s) with wrong or missing values, 0 pending owner approval` |
| `diff_renderkit.py --nema` | `17 ok, 0 failing, 0 pending owner approval, 0 deferred to another module` |
| `diff_cli.py --nema` (42 tools) | `0 check(s) with wrong or missing values, 0 pending owner approval` |
| `diff_cli_web.py --nema` | `0 check(s) with wrong or missing values, 0 pending owner approval` |
| `diff_studio.py --nema` (G1–G6) | `0 check(s) with wrong or missing values, 0 pending owner approval` (222 ok) |
| `generate_dicomdir_profile_rules.py --check` | `Sources/DICOMKit/DICOMDIRProfileTables.swift: matches` |
| `generate_dicomdir_record_keys.py --check` | `Sources/DICOMKit/DICOMDIRRecordKeyTables.swift: matches` |
| `generate_confidentiality_profile.py --check` | `ok: 211 rows of Table E.3.4-1 (244 keys) match …ConfidentialityProfileStructuredContent.swift` |
| `cli_contracts.py --check` | no output, exit 0 |

Every diff script exits 0. The 13 `diff_studio.py` PEND rows that stood for the P-STUDIO items are now real checks of the standard-conformant state; each was shown to FAIL on the code before its fix (`3d5f502a`, `c618e743`).

## 3. Build and tests

Run at `dd36ae8b`, the last code commit; only scripts and documentation changed after it.

| Step | Result |
|---|---|
| `swift build -c release --product dicom-split --product dicom-merge` | exit 0 |
| `swift test` (full) | exit 0 |
| XCTest | 5,934 run, 5,890 passed, 44 skipped, 0 failed |
| Swift Testing | 49 runs, 9,295 tests, 0 failed |
| After the deferred follow-up (`3060ee3e`), for comparison | XCTest 5,929 run / 44 skipped; Swift Testing 9,261 |
| At the audit (`fca194a3`), for comparison | XCTest 5,835 run / 44 skipped; Swift Testing 9,252 |

## 4. Deferred rows D1–D276

| Status | Rows |
|---|---|
| ✅ closed | 271 |
| ⏳ open by the owner's decision | 3: D216 (J2KSwift upstream), D221 (DICOMToolbox, out of scope), D256 (`dicom-cloud` product commented out in `Package.swift`) |
| void numbers (placeholder rows, no finding) | 2: D244, D246 |

D276 is new: the follow-up found that D1 was only partly fixed, because `PrintService.swift` read OV, SV and UV with a 2-byte length. Every row appears with the same status in every report it is in. The full table is in Appendix A.

## 5. Owner decisions

§5.1–§5.3 are decided (approved or confirmed by the owner on 2026-10-06). §5.4 and §5.5 are open; nothing in them has been implemented.

### 5.1 P-items (14) — approved 2026-10-06 and implemented

P-VIDEO-CONTAINER was approved with D237 and is done (`7a3aac80`). The deferred-rows instruction of 2026-10-06 did not cover these 14 items; the owner's second instruction the same day ("complete everything as per the recommendation") approved them, with one decision on MWL-CREATE: keep worklist-item creation only in the app, not in the CLI. Each was implemented as recommended (DICOMSTUDIO_STANDARD_IMPLEMENTATION.md "Priority action list"; log in §H3).

| Item | What | Standard | Recommendation (from the report) | Status / commit |
|---|---|---|---|---|
| P-STUDIO-ANON-PS315 | `AnonymizationProfile` has no PS3.15 Basic Profile case; the Workshop refuses `ps315` / `basic` (the CLI default) | PS3.15 2026a Annex E | Add `.ps315` (display "PS3.15 Basic Application Level Confidentiality Profile"), make it the default, route it to `Anonymizer.deidentify`; keep the legacy cases labelled as not PS3.15 | ✅ `45457ff9` |
| P-STUDIO-MWL-CREATE | Workshop `dicom-mwl create` (HL7 ORM over MLLP / REST) has no CLI counterpart | — | Either add `dicom-mwl create` to the CLI or move the flow to the Networking panel; unchanged until decided | ✅ `dbcca0fa` — moved to the Networking panel (owner: app only, not the CLI) |
| P-STUDIO-TLS-PROFILES | `TLSMode` / `DICOMwebTLSMode` select TLS versions, not PS3.15 Annex B profiles (B.12 / B.13 live) | PS3.15 2026a Annex B | Re-label as a transport setting (text only), or add `bcp195` / `modifiedBcp195` cases configuring DICOMNetwork per B.12 / B.13 and deprecate `tls12` / `tls13` | ✅ `586c8f31` — profile cases; limits in §5.5 |
| P-STUDIO-UPS-STATE-RAW | Studio `UPSState` raw values `IN_PROGRESS` / `CANCELLED` vs (0074,1000) terms `IN PROGRESS` / `CANCELED` | PS3.3 C.30.1 | Typealias to `DICOMWeb.UPSState` (`.cancelled` → `.canceled` with a deprecated alias) or change the raw values | ✅ `574f5eb0` |
| P-STUDIO-EXPORT-SINGLE-OUTPUT | Workshop requires `--output` where the CLI defaults to the working directory | — | Keep it required in-app (documented non-mirroring); no API change | ✅ `071ad9c0` |
| P-STUDIO-ANON-TAGLIST-NAME | `AnonymizationHelpers.hipaaDirectIdentifierTags` now holds the engine's 14-attribute basic list | — | Rename to `basicProfileTags` with `@available(*, deprecated, renamed:)` | ✅ `f5aceea1` |
| P-STUDIO-MEASURE-UM | `MeasurementUnit` lacks micrometre; dicom-measure offers `--unit um` | PS3.16 CID 7460 / 7461 | Add `case micrometers = "um"`; `ROIHelpers.ucumAreaCode` returns "um2" | ✅ `824bcfab` |
| P-STUDIO-HP-SORTING-DIRECTION | `ImageSortDirection` ASCENDING / DESCENDING vs Sorting Direction INCREASING / DECREASING | PS3.3 Table C.23.3-1 | Change the raw values with a decoding shim for stored state | ✅ `e9bada7f` |
| P-STUDIO-RT-DOSE-UNITS | `RTDoseUnits.cgy = "CGY"` is not a term; RELATIVE, CODED absent | PS3.3 Table C.8-39 | Add `.relative`, `.coded`; keep cGy as a display scale | ✅ `a6f2c0dd` |
| P-STUDIO-RT-ROI-TYPES | `RTROIType` has 6 of 25 terms plus a non-term `OTHER` | PS3.3 Table C.8-44 | Add the 19 missing cases, map unknown to nil, deprecate `.other` | ✅ `0c97d71e` |
| P-STUDIO-SCOORD-POLYGON | `SpatialCoordGraphicType.polygon` is not a 2D SCOORD type | PS3.3 C.18.6.1.2 | Deprecate `.polygon` (renamed `polyline`); writers emit POLYLINE | ✅ `36fdb6d6` |
| P-STUDIO-SR-TABLE | `ContentItemValueType` lacks TABLE | PS3.3 Table C.17.3-7 | Add `case table = "TABLE"`; `SRTreeHelpers` mapping follows | ✅ `7c860399` |
| P-STUDIO-ANNOTATION-UNITS | `TextAnchorType.imageRelative` raw value "IMAGE"; units are PIXEL / DISPLAY / MATRIX | PS3.3 C.10.5 | Raw value → "PIXEL" (deprecated spelling if persisted; grep says it is not), add `matrixRelative = "MATRIX"` | ✅ `cb143f1b` |
| P-STUDIO-PRINT-ENUMS | Studio `PrintPriority` / `PrintMediumType` / `PrintFilmSize` / `PrintJobStatus` duplicate the DICOMNetwork types (D22) | PS3.3 C.13.1 | Deprecate the Studio enums with typealiases onto `DICOMNetwork.PrintPriority` / `MediumType` / `FilmSize`; Medium Type gains the two MAMMO terms | ✅ `298ef7a7` |

### 5.2 Studio parity changes of 2026-10-05 — confirmed by the owner 2026-10-06

Each removed app-only behaviour where the Workshop differed from the CLI tool it mirrors. The owner confirmed them on 2026-10-06 (they are the recommendations); the dicom-image / dicom-pdf row stays superseded.

| Tool | What changed | Why | Commit |
|---|---|---|---|
| dicom-retrieve (Workshop) | the app-only Study-UID C-FIND lookup before a series / instance retrieve is gone; `--relational-retrieve` offered instead | the CLI never did the lookup | `f8e70094` |
| dicom-wado retrieve (Workshop) | per-instance previews after a retrieve removed | not CLI output | `d52bbfa9` |
| dicom-wado ups (Workshop) | query dump, curl block, pre-flight check, hints removed | not CLI output | `d52bbfa9` |
| dicom-anon (Workshop) | executor runs dicom-anon's own loop instead of `SecurityViewModel` | parity of output and refusals | `38a2eea0` |
| dicom-convert (Workshop) | app-only header / banner removed | not CLI output | `38a2eea0` |
| dicom-image / dicom-pdf (Workshop) | directory runs exit 0 with failed files, as the CLIs did | parity | `38a2eea0` — **superseded**: both now exit 1 when a file fails (D271, D273; `726957b5`) |
| dicom-pixedit (Workshop) | refuses out-of-range fill values and widths < 1 instead of clamping; output marked Derived | P-PIXEDIT-RANGE; PS3.3 C.7.6.1.1.2 | `38a2eea0` |
| dicom-anon (Workshop and Security panel) | `--profile` values are the CLI's `legacy-*` names; `ps315` / `basic` refused with exit 1 until P-STUDIO-ANON-PS315 | the old `basic` now means the PS3.15 Basic Profile in the CLI | `61670c42`; ps315 / basic accepted, ps315 the default since `45457ff9` |

### 5.3 Behaviour changes made by the follow-up — confirmed by the owner 2026-10-06

These follow from the approved recommendations; each changes something a user sees. Confirmed by the owner on 2026-10-06.

| Change | Before | Now | Commit |
|---|---|---|---|
| dicom-export bulk, dicom-image and dicom-pdf directory runs (CLI and Workshop) | exit 0 even when files failed | exit 1 after the summary when any file failed; files of the wrong kind are skipped, not failed | `fbf25c1f`, `db10d0f3`, `15b06782`, `66bd8c42`, `726957b5` (D251, D271, D273) |
| dicom-pdf `--extract` over a directory | (new rule) | files that are not DICOM or carry no Encapsulated Document (0042,0011) are skipped (`⊘ <file>: not an Encapsulated Document (skipped)` with `--verbose`). This was my choice, made so mixed folders do not fail; the row only asked for exit 1 | `66bd8c42` (D271) |
| dicom-send per-file failure line | `❌ C-STORE response status Refused: Out of resources (0xA700) — not stored (PS3.4 Table B.2-1)` | `❌ C-STORE response status Failure (0xA700): Refused: Out of resources — not stored (PS3.4 Table B.2-1)` | `04aa31ea` (D261) |
| dicom-qr failed retrieve (CLI and Workshop) | `Retrieval failed: C-MOVE final response …`; failed-UID list only on failure | dicom-retrieve's wording without the prefix; the (0008,0058) list printed whenever the server sends one, then `Final C-MOVE response: …` | `d7609891`, `e4a73d9a` (D262) |
| `DICOMFile.renderFrame(_:window:)` and the stored-window variants (public API) | window applied to stored values (wrong for any rescale) | window in modality units, applied after the Modality LUT (PS3.3 C.11.2.1.2.1) | `15e74ebc` (D243) |
| Workshop dicom-anon "Option flags apply only to --profile ps315" refusal | exit 1 | exit 1, as the CLI (corrected 2026-10-06: the CLI exits 1 on its option-validation refusals, 64 only for ArgumentParser errors; the Workshop briefly exited 64 after `2bd8e408` and is back to 1 since `45457ff9`) | `2bd8e408` (D275), `45457ff9` |
| `DICOMConverter` target resolution | 7 Table A-1 keywords accepted by dicom-convert only | accepted by every caller, `FrameMerger` included | `b281e64f` (D268) |

### 5.4 Open deferred rows

| Row | Decision needed |
|---|---|
| D216 | J2KSwift upstream issue: wait for the dependency, or carry it as a known limitation |
| D221 | DICOMToolbox (unmaintained, out of scope): close as won't fix, or remove the module |
| D256 | `dicom-cloud`: ship the product (uncomment it in `Package.swift`), or drop the sources and Studio's listing |

### 5.5 Findings from the P-item pass (not changed)

| Finding | Where | 2026a ref | Why not changed |
|---|---|---|---|
| The Networking panel's C-ECHO never passes TLS settings to `DICOMVerificationService` (pre-existing); the `TLSMode` → `TLSConfiguration` mapping now exists | DICOMStudio NetworkingViewModel / DICOMNetwork `DICOMVerificationService` | PS3.15 Annex B.12, B.13 | wiring it changes the echo operation's signature (API) |
| DICOMweb `DEVELOPMENT` TLS mode maps to no profile, and accepting self-signed certificates is not implemented (pre-existing) | DICOMStudio `DICOMwebTLSMode`, `DICOMwebClientFactory` | PS3.15 Annex B | not part of the recommendation; needs a decision on whether to keep the mode |
| B.13 limits on Apple platforms: Security offers 9 of B.13's cipher suites (no CCM / CCM_8 / Camellia / DHE); key-length and certificate rules are not checked; URLSession (DICOMweb) applies only the TLS 1.2 minimum, not the suite list | DICOMNetwork `TLSConfiguration`, DICOMWeb `HTTPClient.applyTLSProfile` | PS3.15 Annex B.12, B.13 | platform API limits |
| The dicom-anon burned-in-PHI refusal text is still CLI-local; DICOMStudio keeps a test-pinned identical copy | `Sources/dicom-anon`, `Components/AnonPS315Support.swift` | PS3.15 Annex E | follow-up candidate: lift into DICOMKit `AnonCLI` (as D275 did for the other texts) |

# Part 2 — History

## H1. The audit as found at `fca194a3`

The tables below are unchanged from the audit of 2026-10-06. Findings A1–A8 and every open row they name were resolved by the follow-up (§H2).

### H1.1 Per-module status at the audit

| Module | Swift files | Marked | `check_nema_markers.py` | Diff script (last line, exit) | Open D-rows | Open P-items | Definition of done |
|---|---|---|---|---|---|---|---|
| DICOMCore | 108 | 108 (122 × 2026a, 1 × 2026d on `VR.swift`, policy-justified) | exit 0 | `diff_sr_templates.py`: 73 templates, 646 rows, 0 differences (exit 0). Audit re-check after the merge `1416f7e2`: `Tag+Video.swift` 7/7 constants match PS3.6 Table 6-1; `TransferSyntax.swift` 65 UID literals, 63 registered in Table A-1, 2 unregistered by decision P2/D20 | 0 | 0 | ✅ met |
| DICOMDictionary | 5 | 5 | exit 0 | `diff_dictionary.py`: elements 5,326/5,326; UIDs 465/465; B.5-1 170/170; B.6-1 4/4; 0 differences (exit 0) | 0 | 0 | ✅ met |
| DICOMKit | 177 | 175 | **exit 1** — `Video/VideoAudioStreamInfo.swift`, `Video/VideoLevelLimits.swift` unmarked | `diff_kit.py`: 51 ok, **1 FAIL**, 0 PEND (exit 1); `generate_dicomdir_profile_rules.py --check` matches; `generate_dicomdir_record_keys.py --check` matches; `generate_confidentiality_profile.py --check`: 211 rows / 244 keys match | D237 DICOMKit half (P-VIDEO-CONTAINER); D243, D245 opened by Studio | P-VIDEO-CONTAINER | ❌ A1, A2 |
| DICOMNetwork | 66 | 66 | exit 0 | `diff_network.py`: 43 ok, 0 wrong (exit 0) | 0 (audit finding A5 on D1) | 0 | ✅ met, see A5 |
| DICOMWeb | 55 | 55 | exit 0 | `diff_web.py`: 39 ok, 0 wrong, 0 pending (exit 0) | D254, D255 opened by Studio | 0 | ✅ met |
| DICOMPrintKit | 31 | 31 | exit 0 | `diff_printkit.py`: 32 ok, 0 wrong, 0 pending (exit 0) | D242 opened by Studio | 0 | ✅ met |
| DICOMRenderKit | 10 | 10 | exit 0 | `diff_renderkit.py`: 16 ok, 0 failing, 0 pending, 1 deferred (D65 Studio half, exit 0) | 0 (see A6) | 0 | ✅ met, see A6 |
| `dicom-*` CLI (42 tools) | 100 | 100 | exit 0 for all 42 directories | `diff_cli.py`: 42 tools, 503 ok, **1 FAIL** (exit 1); `diff_cli_web.py`: **crashes** (exit 1); `cli_contracts.py --check` exit 0 | D216, D221, D237; D247–D253, D256, D258, D261–D275 opened by Studio | 0 | ❌ A3, A4 |
| DICOMStudio + DICOMStudioApp | 334 | 170 (+164 inventoried as not standard-touching) | exit 0 (`--inventory`) | `diff_studio.py` (all groups): 206 ok, 0 FAIL, 13 PEND, each naming a P-item (exit 0) | D257, D259, D260 (own rows) | 15 (P-STUDIO-* ×14, P-VIDEO-CONTAINER) | ✅ met pending the owner's P-item decisions |

File counts are `find Sources/<Module> -name '*.swift' | wc -l` at `fca194a3`. The "Status by module" table in the DICOMCore report was refreshed to these counts (`8a7e32ef`); it previously said 106 / 162 / 63 / 54 / 102 for DICOMCore / DICOMKit / DICOMNetwork / DICOMWeb / CLI. Every file added after a module closed is marked except the two DICOMKit video files (A1).

### H1.2 Script evidence at the audit

| Script | Last line | Exit |
|---|---|---|
| `check_nema_markers.py` × 7 modules, 42 CLI directories, Studio `--inventory` | see §H1.1 | 0 everywhere except `Sources/DICOMKit` (1) |
| `diff_dictionary.py part06 part07 part04` | `0 differences` | 0 |
| `diff_sr_templates.py part16` | `73 templates, 646 rows compared, 0 differences` | 0 |
| `diff_kit.py --nema` | `1 check(s) with wrong or missing values, 0 pending owner approval` — wrong: `Video/VideoAudioStreamInfo.swift:134` cites "PS3.5 8.2.5 - CBR MPEG-1 Layer III …"; the check wants the 2026a title "MPEG2 Main Profile / Main Level Video Compression" | 1 |
| `diff_network.py --nema` | `0 check(s) with wrong or missing values` | 0 |
| `diff_web.py --nema` | `0 check(s) with wrong or missing values, 0 pending owner approval` | 0 |
| `diff_printkit.py --nema` | `0 check(s) with wrong or missing values, 0 pending owner approval` | 0 |
| `diff_renderkit.py --nema` | `16 ok, 0 failing, 0 pending owner approval, 1 deferred to another module` | 0 |
| `diff_cli.py --nema` (42 tools) | `1 check(s) with wrong or missing values, 0 pending owner approval` — wrong: `dicom-server/ServerProtocol.swift:196,198` comment (0002,0017)/(0002,0018) as "Sending/Receiving AE Title"; PS3.6 names are "Sending/Receiving Application Entity Title" | 1 |
| `diff_cli_web.py --nema` | `AttributeError: 'NoneType' object has no attribute 'group'` at line 88 (`static let uriContentTypes = [...]` no longer exists in `WADOOptionRules.swift` since `f4262b4f`) | 1 |
| `diff_cli_web.py` scratch-patched to read `WADOURIClient.MediaType.allowed` (not committed) | 30 ok, 1 FAIL: `--content-type help lists exactly the accepted values: matched 11, missing 4` — the four are `text/html`, `text/plain`, `text/xml`, `text/rtf`, which the help does list; the script's regex only matches `application|image|video` | 1 (script artefact) |
| `diff_studio.py --nema` (G1–G6) | `0 check(s) with wrong or missing values, 13 pending owner approval` | 0 |
| `generate_dicomdir_profile_rules.py part11 part04 --check` | `Sources/DICOMKit/DICOMDIRProfileTables.swift: matches` | 0 |
| `generate_dicomdir_record_keys.py part03 part04 --check` | `Sources/DICOMKit/DICOMDIRRecordKeyTables.swift: matches` | 0 |
| `generate_confidentiality_profile.py --nema --check` | `ok: 211 rows of Table E.3.4-1 (244 keys) match …ConfidentialityProfileStructuredContent.swift` | 0 |
| `cli_contracts.py --check` | (no output) | 0 |

The 13 `diff_studio.py` PEND rows map to: P-STUDIO-ANON-PS315 (dicom-anon `--profile` default), P-STUDIO-MWL-CREATE (dicom-mwl subcommand picker), P-STUDIO-ANNOTATION-UNITS, P-STUDIO-PRINT-ENUMS (D22), P-STUDIO-TLS-PROFILES (×2, NetworkingModel and DICOMwebModel), P-STUDIO-UPS-STATE-RAW, P-STUDIO-SR-TABLE, P-STUDIO-SCOORD-POLYGON, P-STUDIO-RT-ROI-TYPES, P-STUDIO-RT-DOSE-UNITS, P-STUDIO-HP-SORTING-DIRECTION, P-STUDIO-MEASURE-UM. All 13 are in the Studio report's Priority action list as pending.

### H1.3 Build and tests at the audit

| Step | Result |
|---|---|
| `swift build -c release --product dicom-split --product dicom-merge` | exit 0 |
| `swift test` (full) | exit 0 |
| XCTest | 5,835 started, 5,791 passed, 44 skipped, 0 failed (counted from `Test Case … started/passed/skipped` lines; the per-target `Test Suite 'All tests'` Executed lines sum to 11,670 = 2 × 5,835) |
| Swift Testing | 49 `Test run with N tests` lines, sum 9,252, 0 failed |
| Last recorded (Studio report, at `fca194a3`) | XCTest 5,819 / 44 skipped, Swift Testing 9,252 |

No test or source file changed between `fca194a3` and this run; the XCTest difference of 16 is a counting difference (the earlier figure was not reproduced from the log), not a change in the suite.

### H1.4 Deferred rows D1–D275 at the audit

| Check | Result |
|---|---|
| Distinct IDs | 275 (D1–D275), no gaps, no duplicated numbers |
| IDs appearing in two or more reports | 144 (the originating report and the report that closed it) |
| Status after bookkeeping | 238 ✅ closed · 35 ⏳ open · 2 void (D244, D246: placeholder rows "(none else)" with no finding, now marked void); D65's RenderKit row holds two status fragments, both ✅ |
| IDs with a different status in two reports (before this audit) | 19: D9, D10, D11 (Core ⏳ / Studio ✅), D22 (Network), D28, D29, D44, D56 (Kit), D42 (PrintKit), D165–D174 (CLI per-tool tables ⏳ / CLI master ✅) — all were closed with a commit and are now ✅ everywhere (`2ffaa45f`, `22cad5a9`) |
| Further stale rows found | 48 CLI per-tool rows D157–D205 said ⏳ while the master table was ✅ (`22cad5a9`); CLI master rows D85 (no Status cell at all), D88, D114, D127, D132, D154 said ⏳ after the Studio pass closed them (`1cd0231e`); D65 Studio half and D68 in RenderKit, plus the "open:" notes in the Status-by-module table (`8a7e32ef`, `2ffaa45f`) |
| Closed rows whose status cell names no commit sha | 11: D6, D7, D8, D20, D25, D30, D39, D40, D41, D43, D85 — each has a date and names the P-item, sibling row or test that carries the change (e.g. D6/D7/D20 → dictionary P1/P5/P2, D25 → `DataElementTests.testEmptyValuesPreserved`, D39 → `GraphicAnnotationStyleTests`); recommended: add the sha to each |
| Spot-check by reading the referenced file:line | 26 rows read (D1, D2, D13, D21, D22, D24, D26, D28, D31, D35, D37, D39, D42, D50, D63, D64, D66, D67, D68, D70, D94, D159, D175, D190, D229, D239): 25 confirmed in code with the named commit present and a pinning test; **1 partial — D1**, see A5 |

#### H1.4.1 Rows legitimately open, with recommended owner

| Row | Module (as recorded) | What | Recommended owner / next step |
|---|---|---|---|
| D216 | DICOMCore (J2KSwift dependency) | upstream J2KSwift issue | J2KSwift maintainer; re-check when the dependency is bumped |
| D221 | DICOMToolbox | out of scope (unmaintained) | none; close as "won't fix" when DICOMToolbox is removed |
| D237 (DICOMKit half) | DICOMKit `VideoContainer` | add `.mpegPS` / `.mpegPES` after the Studio switch has a `default` (done `88c271c6`) | DICOMKit, on approval of P-VIDEO-CONTAINER |
| D242 | DICOMPrintKit `PrintOptionCatalog.filmDestinations` | only 4 of the C.13.1 Film Destination terms offered | DICOMPrintKit |
| D243, D245 | DICOMKit (`DICOMFile+PixelData.renderFrame`, `Anonymizer.basicProfileTags`) | engine rows | DICOMKit |
| D254, D255 | DICOMWeb (`UPSEvent.swift` marker text; Change-State target rule lives in dicom-wado) | engine rows | DICOMWeb |
| D247, D258, D266 | `Scripts/diff_studio.py` | parity-check parser limits (by-flag collapse, `[""] + Expr` pickers, EXEMPT rows) | Scripts (orchestrator); tooling only |
| D256 | `Package.swift:189` | `dicom-cloud` product commented out while Studio lists it | owner decision (ship or drop dicom-cloud) |
| D257, D259, D260 | DICOMStudio (`ShellServerConfigHelpers --host`, `UPSState` shadowing, `DICOMwebClientFactory` timeouts) | Studio-internal | DICOMStudio |
| D248–D253, D261–D265, D267–D275 (22 rows) | CLI-local rule files that Studio mirrors text-identically (dicom-validate, archive, uid, export ×2, dcmdir, send, retrieve/qr, mpps, mwl, wado, compress, convert, video, pixedit, pdf ×2, image ×2, anon) | lift each rule set from the tool into DICOMKit / DICOMNetwork / DICOMWeb so Studio and the CLI share one copy; D251, D271, D273 are the "directory run exits 0 with failed files" behaviour (P-CONVERT-EXIT precedent) | CLI maintainer with the engine owner; one tool per commit |

### H1.5 Findings that did not meet the definition of done (not fixed by this audit)

| # | Module | Finding | Evidence | Recommended action |
|---|---|---|---|---|
| A1 | DICOMKit | `Sources/DICOMKit/Video/VideoAudioStreamInfo.swift` and `VideoLevelLimits.swift` carry no `NEMA-verified` marker. They arrived with the merge of origin/main PR #217 ("DICOM 2026d video rules", `8de5173d`, merged `1416f7e2` on 2026-10-05, after DICOMKit closed on 2026-09-29). Neither the DICOMKit nor the DICOMStudio report records the merge. | `check_nema_markers.py Sources/DICOMKit` exits 1 | Classify both (B1: they cite PS3.5 8.2.5 / 8.2.12 and ITU-T H.264 Table A-1 / H.265 Table A.8; the level tables are codec-internal and out of scope, the PS3.5 audio and picture rules are not), diff the PS3.5 8.2.5 / 8.2.12 statements by script, add markers, and add a Progress-log line for the merge to the DICOMKit report. |
| A2 | DICOMKit | `diff_kit.py` FAIL: `VideoAudioStreamInfo.swift:134` cites "PS3.5 8.2.5 - CBR MPEG-1 Layer III only …". The clause is right (the MPEG-1 Layer III audio paragraph is inside 2026a §8.2.5 "MPEG2 Main Profile / Main Level Video Compression"; the AVC/HEVC audio rules are §8.2.12), but the citation check compares against the section title. | `diff_kit.py` exit 1 | Reword the doc comment to name the section ("PS3.5 8.2.5 (MPEG2 MP@ML audio): …") when A1 is done. |
| A3 | CLI (dicom-server) | `diff_cli.py` FAIL: `ServerProtocol.swift:196` and `:198` comment (0002,0017) / (0002,0018) as "Sending AE Title" / "Receiving AE Title"; PS3.6 Table 7-1 names are "Sending Application Entity Title" / "Receiving Application Entity Title". The file was last changed in the CLI pass (`7bad09da`); the report says 0 FAIL at close, so either the check or the comment changed afterwards. | `diff_cli.py` exit 1 | Two-word comment fix in dicom-server; re-run `diff_cli.py --tool dicom-server`. |
| A4 | CLI (dicom-wado, dicom-jpip) | `diff_cli_web.py` crashes at line 88: it extracts `static let uriContentTypes = [...]`, which `f4262b4f` (DICOMWeb D105–D108 fix, after the script's last commit `827f0217`) replaced by `WADOURIClient.MediaType.allowed.map(\.rawValue)`. Every dicom-wado/jpip check after that point has not run since. A scratch-patched copy shows the tool is consistent (30 ok) and the remaining FAIL is the script's help-text regex, which ignores `text/*` media types. | exit 1; patched run 30 ok / 1 script artefact | Update the two regexes in `diff_cli_web.py` (read `renderedMediaTypes` from `Sources/DICOMWeb/WADOURIClient.swift`; add `text` to the help regex); re-run; record the counts in the CLI report. |
| A5 | DICOMNetwork | D1 is closed as "all call sites use DICOMCore's `VR.uses32BitLength`, duplicate deleted, regression test" (`d271fea`). The call sites are converted, but the private duplicate `VR.uses4ByteLength` is still at `QueryService.swift:1107` without OV/SV/UV, and `QueryServiceTests.swift:279–292` still pins it. Separately `PrintService.swift:3823` hard-codes the 10-VR list (`["OB","OD","OF","OL","OW","SQ","UC","UN","UR","UT"]`) in a data-set walker, so an OV/SV/UV element there is read with a 2-byte length. | spot-check; `grep -rn uses4ByteLength Sources Tests` | Delete `uses4ByteLength` and its test, route `PrintService.swift:3823` through `VR(string:)?.uses32BitLength`, add a test with an OV element; record as a new D-row (D276) in the DICOMNetwork report. |
| A6 | DICOMRenderKit / DICOMStudio | `diff_renderkit.py` still reports 9 rows "deferred D65 (DICOMStudio half)": `DICOMImageExporter.determineWindowSettings` keeps the inexact `toStored` conversion "for DICOMStudio". The Studio report closes D65's Studio half (`6372e096`, viewer converts c·m+b itself), yet Studio still calls `determineWindowSettings` at `Services/FrameRenderer.swift:288` (`resolvedWindow`, seeds an edit) and `ViewModels/ImageViewerViewModel.swift:1508` (fallback when the file has no window). | `diff_renderkit.py` output lines 7–16; grep | Owner to confirm: either these two call sites only read the file's own window (then the `toStored` path can go and the script's DEFR rows become ok), or D65's Studio half stays partly open and should be re-opened. |
| A7 | DICOMCore / DICOMDictionary | The same merge `1416f7e2` changed `Sources/DICOMCore/Tag+Video.swift` (+9) and `TransferSyntax.swift` (±55) after DICOMCore closed; their markers predate the change (2026-09-25 / 2026-10-01). This audit re-diffed both (Table 6-1 7/7; Table A-1 63/63 registered). PR #217 removed the unregistered `.4.107.1` / `.4.108.1` UIDs upstream; on this branch they are kept by decision D20/P2 with `registered == false`, so the branch now differs from origin/main on that point. | §H1.1 | Add a Progress-log line to the DICOMCore and DICOMDictionary reports for the merge, refresh the two markers' dates, and decide whether to follow upstream and drop the two UIDs (public API: `TransferSyntax.hevcH265MainProfileFragmentable` etc. → deprecate). |
| A8 | Reports | 11 closed rows carry no commit sha in their status cell (§H1.4). | grep | Add the sha to each when next editing those reports. |

### H1.6 Bookkeeping fixed by the audit (report text only, no code)

| Commit | Change |
|---|---|
| `22cad5a9` | CLI report: 48 per-tool rows D157–D205 → ✅ with the master row's sha; file count "102 after this pass" → 100 (3 files folded into engines the same day) |
| `8a7e32ef` | DICOMCore "Status by module": counts 108 / 177 (175 marked) / 66 / 55 / 100 with the added files and commits named; "open:" notes for D28, D29, D44, D56, D65, D68, D42 updated |
| `2ffaa45f` | D9, D10, D11 (Core), D22 (Network), D28, D29, D44, D56 (Kit), D42 (PrintKit), D65 Studio half, D68 (RenderKit) → ✅ with the closing commit; D244, D246 marked void |
| `1cd0231e` | CLI master table: D85 (had no Status cell), D88, D114, D127, D132, D154 → ✅ (Studio pass) |


## H2. Follow-up log


Owner instruction 2026-10-06: "complete all deferred items which are open as per the recommendation and leave D216,
D221 and D256". P-VIDEO-CONTAINER was approved with it (D237). The 14 P-STUDIO-* items in §5.1 are **not** covered by the
instruction (it named deferred rows only) and stay pending. 35 commits, `b34f6ba8` … `15b06782`
(`git log 5ec7381f..15b06782`); every sha below checked with `git cat-file -e`. §H1 is the audit as written before this follow-up; Part 1 and Appendix A carry the current state.

### H2.1 Rows and audit findings closed

| Row | Commit | Result |
|---|---|---|
| D237 + P-VIDEO-CONTAINER | `7a3aac80` | `VideoContainer.mpegPS` / `.mpegPES` reported for MPEG-2 PS and PES (PS3.5 2026a 8.2.5, 8.2.6) |
| A1, A2 | `4e5e2a69` | `VideoAudioStreamInfo` / `VideoLevelLimits` classified B1 and NEMA-verified; the 8.2.5 audio citation names its section (PS3.5 8.2.5, 8.2.12, 8.2.7–8.2.11) |
| A7 | `b34f6ba8` | `Tag+Video.swift` / `TransferSyntax.swift` markers re-checked after merge `1416f7e2`; the two unregistered Fragmentable HEVC UIDs kept (D20 / P2 stands) (PS3.6 Tables 6-1, A-1) |
| D245 | `005b5ec4` | `AnonymizationProfile.basic` documented: 14 Table E.1-1 rows removed, 641 untouched, not Annex E (PS3.15 Table E.1-1) |
| D1 remainder + D276 (A5) | `5de7575d` | duplicate `VR.uses4ByteLength` deleted; the PrintService data-set walker uses DICOMCore `VR.uses32BitLength` (OV/SV/UV were read with a 2-byte length) (PS3.5 7.1.2, Tables 7.1-1/7.1-2). D276 added to DICOMNETWORK_STANDARD_IMPLEMENTATION.md |
| A3 | `4535d37c` | dicom-server comments name (0002,0017) / (0002,0018) per PS3.6 Table 7-1 |
| D254 | `c9bad73e` | `UPSEvent` marker re-checked; P-EVENT no longer named as pending (PS3.4 Table CC.2.4-1) |
| D255 | `f4b3bddd` | `UPSState` change-state API + `DICOMwebOptionRefusal` in DICOMWeb (PS3.18 11.7.1.4; PS3.4 Table CC.1.1-2) |
| D265 | `87bbcbf8` | `DICOMwebOptionRules` (PS3.18 9.1.2.2.1, 9.4.1.2.2, 9.5.1.2.1, 8.3.4.4, 11.7, Table 8.7.4-1) |
| A4 | `986c517b` | `diff_cli_web.py` reads media types and Change-State targets from DICOMWeb; `text/*` in the help regex; exits 0 |
| D261 | `cf4667c7` | dicom-send success / warning lines through `NetworkConsole.CStoreOutcome` / `sendFileResult` (failure wording completed in the Studio pass) (PS3.4 Table B.2-1) |
| D262 | `d7609891` | `NetworkConsole.retrieveFinalResponse` shared by dicom-retrieve and dicom-qr (PS3.4 Tables C.4-2/C.4-3, PS3.7 Table 9.3-10) |
| D263 | `d2812df4` | `DICOMMPPSService` status / Patient's Sex / birth date / warning line (PS3.3 Tables C.4-14, C.2-3; PS3.5 Table 6.2-1 DA) |
| D264 | `29496ff0` | `WorklistQueryKeys` SPS Status Defined Terms and warning (PS3.3 Table C.4-10) |
| D242 | `f1ba662b` | `FilmDestination(catalogToken:)` accepts any BIN_i; dicom-print parses through it (PS3.3 Table C.13-1) |
| D269 | `cc3c3675` | `VideoOptionConformance`, `AudioChannelSourceOption` in DICOMKit Video (PS3.16 CID 3000; PS3.3 A.32.5–A.32.7, Table C.7-1) |
| D270 | `4a756536` | `PixelEditInputChecks` next to `PixelEditor` (PS3.3 C.7.6.3.1, C.11.2.1.2) |
| D275 | `b711104e` | `AnonCLI` in DICOMKit Anonymization (PS3.15 E.3, Table E.1-1a; PS3.10 Table 7.1-1) |
| D257 | `62b76e1e` | test only: the host is positional since `490e18d3`; generated command checked against 7 DIMSE tool surfaces |
| D260 | `81349178` | `DICOMwebClientFactory.makeConfiguration(from:timeouts:)` |
| D259 | `d49d23ac` | `WebUPSState` (internal alias) names `DICOMWeb.UPSState` inside Studio (PS3.3 Table C.30.1-1) |
| D247, D258, D266 | `4d26acec` | `diff_studio.py` parity keyed by (subcommand, flag), cliMapping tokens counted, `[""] + Expr` pickers parsed; 4 DEFERRED + 5 EXEMPT rows removed |
| D248 | `923c496e` | `DICOMValidator.iodNameBySOPClassUID` etc. (PS3.6 Table A-1, 7/7) |
| D249 | `2182f73d` | `ArchiveMatching.studyDateKeyWarning` (PS3.4 C.2.2.2.5.1) |
| D250 | `aeab8202` | `UIDManager.RootRule` (PS3.5 9.1) |
| D253 | `6adbe40e` | `DICOMDIRFileSetRules` (PS3.10 8.1, 8.2, 8.5, 8.6) |
| D267 | `36022531` | `CompressionConsole.NativeTargetSyntax` (PS3.6 Table A-1; PS3.5 A.1–A.5) |
| D268 | `b281e64f` | `DICOMConverter` accepts the 7 Table A-1 keywords for every caller, `FrameMerger` included (PS3.6 Table A-1) |
| D243 + A6 (D65 engine half) | `15e74ebc` + Studio pass `123b81a5` | `DICOMFile` convenience renderers go through `GrayscaleDisplayPipeline` (window in modality units); `DICOMImageExporter.determineModalityWindow` added, `determineWindowSettings` deprecated; `diff_renderkit.py` 0 deferred (PS3.3 C.11.2.1.2.1; PS3.4 N.2). The two Studio callers (`FrameRenderer.swift:288`, `ImageViewerViewModel.swift:1508`) move in the Studio pass |
| D252 | `be267a71` | `DICOMImageExporter.CineFrameRate` / `BurnedInAnnotation` / `FrameSelection` / `FrameSelectionConflict` / `ApplyWindowDeprecation` (PS3.3 Table C.7-13, C.7-9, Table 10-3) |
| D251 | `fbf25c1f` | dicom-export bulk exits 1 when any file failed (files without pixel data skipped) |
| D274 | `46f4a61a` | `ImageConverter.OutputRules` (finalize also covers non-ASCII text in sequence items) (PS3.10 Table 7.1-1; PS3.3 C.12-1, C.12-5) |
| D273 | `db10d0f3` | dicom-image directory run exits 1 when any image failed (non-images skipped) |
| D272 | `98e59069` | `EncapsulatedDocumentBuilder.OptionRules`; the extract padding cut follows the engine's Table C.24-2 rule (PS3.3 Table C.24-2, C.12-1) |
| D271 | `15b06782` | dicom-pdf directory runs exit 1 when any file failed (the Studio pass makes `--extract` skip non-documents) |
| Studio copies of D248–D275 (and D243 / A6 callers) | `2bd8e408`…`3060ee3e` (9 commits) | DICOMStudio CLI Workshop copies replaced by the engine symbols; D261 failure wording and D271 `--extract` skip completed in CLI and Workshop |

Left open by owner decision: **D216** (J2KSwift upstream), **D221** (DICOMToolbox), **D256** (`dicom-cloud` product).
Still void: D244, D246. Every other row D1–D276 is ✅.

### H2.2 Script and test results

All with `--nema 2026a`: `diff_kit.py` 0 wrong; `diff_network.py` 0; `diff_web.py` 0; `diff_printkit.py` 0;
`diff_renderkit.py` 17 ok, 0 failing, 0 deferred; `diff_cli.py` 0 FAIL (42 tools); `diff_cli_web.py` 0 FAIL;
`check_nema_markers.py` exits 0 on every module (DICOMCore 108/108, DICOMDictionary 5/5, DICOMKit 185/185,
DICOMNetwork 66/66, DICOMWeb 57/57, DICOMPrintKit 31/31, DICOMRenderKit 10/10, `Sources/dicom-*` 100/100).
`diff_studio.py` after the Studio pass (`2bd8e408`…`3060ee3e`, 9 commits): 0 FAIL, 13 PEND. Full `swift test` after the Studio pass (at `3060ee3e`, after `swift build -c release --product dicom-split --product dicom-merge`): exit 0; XCTest 5,929 run, 5,885 passed, 44 skipped, 0 failed; Swift Testing 49 runs, 9,261 tests, 0 failed. Every diff script ends with 0 wrong / 0 FAIL (`diff_studio.py` 13 PEND, each a P-STUDIO-* item; `diff_renderkit.py` 0 deferred); every marker check exits 0 (DICOMKit 185/185, DICOMWeb 57/57, CLI 100/100, Studio 171 + 164 inventoried). Open deferred rows: D216, D221, D256 only (owner decision).

### H2.3 Resolution of A1–A8

| # | Resolution |
|---|---|
| A1, A2 | Done `4e5e2a69` (merge `1416f7e2` now recorded in the DICOMKit report's Progress log) |
| A3 | Done `4535d37c` |
| A4 | Done `986c517b` |
| A5 | Done `5de7575d`; the PrintService half recorded as new row D276 (DICOMNetwork, Medium); D1 amended in the DICOMCore and DICOMNetwork reports |
| A6 | Engine half done `15e74ebc` (`determineModalityWindow`, `determineWindowSettings` deprecated, `diff_renderkit` 0 deferred); Studio callers in the Studio pass `123b81a5` |
| A7 | Done `b34f6ba8`; Progress-log lines added to the DICOMCore and DICOMDictionary reports; the two unregistered HEVC UIDs kept (D20 / P2) |
| A8 | All 11 shas found (`git log --grep` / `git log -S`) and added to every report's Status cell for the row: D6 `4f29b7b2`, D7 `4f29b7b2`, D8 `a08258f9`, D20 `f5aa6d0a`, D25 `511ac8ab`, D30 `535d6093`, D39 `bbe90b0a` + `37e59463`, D40 `8dada6c0`, D41 `8dada6c0`, D43 `d411e1ed`, D85 `d716de90`. None left unchanged |

## H3. P-item pass log

Owner instruction 2026-10-06: "complete everything as per the recommendation" other than the deferred rows; mid-task: keep P-STUDIO-MWL create only in the app, not in the CLI. 14 commits `824bcfab` … `071ad9c0` plus `dd36ae8b` (import spacing); every sha checked with `git cat-file -e`. The §5.3 dicom-anon exit-code row was corrected in this pass (the CLI exits 1; `45457ff9`). Findings left unchanged are in §5.5.

| Item | sha | Result | 2026a ref |
|---|---|---|---|
| P-STUDIO-ANON-TAGLIST-NAME | `f5aceea1` | `hipaaDirectIdentifierTags` → `basicProfileTags` (old name deprecated); 14/14 tags are Table E.1-1 rows | PS3.15 Table E.1-1 |
| P-STUDIO-ANON-PS315 | `45457ff9` | `AnonymizationProfile.ps315` default in the Security panel and Workshop; Workshop dicom-anon accepts ps315 / basic and prints dicom-anon's output (byte-identical to the CLI apart from the `$ command` echo); 10 E.3 Option toggles + `--allow-burned-in-phi` in the Security panel; legacy profiles labelled "(not PS3.15)"; option-validation refusals exit 1 like the CLI (built dicom-anon: 1 on "Option flags apply only to --profile ps315", 64 only for ArgumentParser errors) | PS3.15 Annex E (E.1, Table E.1-1, E.3.3–E.3.11 10/10); PS3.10 Table 7.1-1 |
| P-STUDIO-MWL-CREATE | `dbcca0fa` | owner decision: create stays app-only. Moved from the CLI Workshop to Networking › Modality Worklist › "New Worklist Item" (HL7 ORM^O01 / REST); Workshop dicom-mwl offers only `query`; a saved `create` is refused (exit 64) with a pointer to the panel; no CLI / DICOMNetwork change | PS3.3 Tables C.4-10, C.4-11, C.4-12, C.7-1 (16/16) |
| P-STUDIO-EXPORT-SINGLE-OUTPUT | `071ad9c0` | kept required in-app, documented as a deliberate non-mirroring (sandbox, no working directory); comments only | — |
| P-STUDIO-UPS-STATE-RAW | `574f5eb0` | Studio `UPSState` is a deprecated alias of DICOMWeb's (`WebUPSState`, `DICOMWeb::UPSState`); raw values "IN PROGRESS" / "CANCELED"; `.cancelled` deprecated → `.canceled`; `WebUPSState(legacyRawValue:)` loads IN_PROGRESS / CANCELLED | PS3.3 Table C.30.1-1; PS3.4 Table CC.1.1-2 |
| P-STUDIO-TLS-PROFILES | `586c8f31` | DIMSE `TLSMode` {NONE, BCP195 (B.12), MODIFIED_BCP195 (B.13), MTLS}; `DICOMwebTLSMode` {NONE, BCP195, MODIFIED_BCP195, DEVELOPMENT}; DICOMNetwork `SecureTransportConnectionProfile`, `TLSConfiguration.bcp195` / `.modifiedBCP195` / `profile(...)`, `TLSCipherSuite`; DICOMWeb `DICOMwebConfiguration.TLSProfile` / `tlsProfile`; tls12 / tls13 and COMPATIBLE / STRICT deprecated, old saved values load as the nearest profile. Limits in §5.5. B.9–B.11 are retired (B.10 is the old "Non-Downgrading"); B.13 is "Modified BCP 195 RFC 8996, 9325 TLS" | PS3.15 Annex B.12, B.13 |
| P-STUDIO-PRINT-ENUMS | `298ef7a7` | Studio PrintPriority / PrintMediumType / PrintFilmSize deprecated typealiases onto DICOMNetwork PrintPriority / MediumType / FilmSize; PrintJobStatus → NetworkPrintJobState (deprecated alias); displayName extensions on the DICOMNetwork types; Medium Type pickers gain MAMMO CLEAR FILM / MAMMO BLUE FILM; old case names (.med, .bluFilm, .size8x10 …) deprecated | PS3.3 Table C.13-1, C.13-3, C.13-8 |
| P-STUDIO-MEASURE-UM | `824bcfab` | `MeasurementUnit.micrometers` ("um", shown µm), area um2 / µm² | PS3.16 CID 7460, 7461 |
| P-STUDIO-HP-SORTING-DIRECTION | `e9bada7f` | `ImageSortDirection` INCREASING / DECREASING (ASCENDING / DESCENDING still decode) | PS3.3 Table C.23.3-1 |
| P-STUDIO-RT-ROI-TYPES | `0c97d71e` | `RTROIType` 25 Defined Terms; OTHER / unknown → nil; `.other` deprecated | PS3.3 C.8.8.8.1 / Table C.8-44 |
| P-STUDIO-RT-DOSE-UNITS | `a6f2c0dd` | `RTDoseUnits` GY / RELATIVE / CODED; "CGY" decodes as `.gy`; `.cgy` deprecated alias; `RTDoseDisplayScale`, `RTHelpers.formattedDose(gray:scale:)` | PS3.3 Table C.8-39, C.8.8.3 |
| P-STUDIO-SR-TABLE | `7c860399` | `ContentItemValueType.table`; SRTreeHelpers maps all 16 | PS3.3 Table C.17.3-7 |
| P-STUDIO-SCOORD-POLYGON | `36fdb6d6` | `SpatialCoordGraphicType.polygon` deprecated (renamed polyline); writers emit a closed POLYLINE; "POLYGON" still reads | PS3.3 C.18.6.1.2 |
| P-STUDIO-ANNOTATION-UNITS | `cb143f1b` | `TextAnchorType.imageRelative` = "PIXEL" ("IMAGE" still decodes); new `matrixRelative` = "MATRIX" | PS3.3 C.10.5 Table C.10-5 |

## Appendix A — consolidated deferred-row table (276 rows, current)

Status is taken from the row in each report's deferred-findings table; "Reports" lists every report the ID appears in; "Commit" lists the shas named in its status cells (first six). Regenerated 2026-10-06 after the follow-up: 271 ✅, 3 ⏳, 2 void.

| ID | Module (as recorded) | Reports | Status | Last date | Commit(s) | Problem (truncated) |
|---|---|---|---|---|---|---|
| D1 | DICOMNetwork | CORE / NETWORK | ✅ | 2026-10-06 | `d271fea`, `5de7575d` | A second copy of `VR.uses32BitLength` that omits OV, SV and UV. The Explicit VR encode and |
| D2 | DICOMWeb | CORE / WEB | ✅ | 2026-09-28 | `c78356f` | `InlineBinary` and `BulkDataURI` are placed inside the `Value` array (`"Value": [{"InlineB |
| D3 | DICOMWeb | CORE / WEB | ✅ | 2026-09-28 | `c78356f` | AT is read with `uint32Values`, which returns nil for VR AT, so it falls through to the st |
| D4 | DICOMWeb | CORE / WEB | ✅ | 2026-09-28 | `767356c` | Omits OV. SV and UV numeric handling in the XML encoder has not been checked either. |
| D5 | DICOMStudio, DICOMKit | CORE / KIT | ✅ | 2026-10-06 | `c1795b3`, `6372e096` | The "is binary" checks omit OV, so OV values are shown as text. |
| D6 | DICOMDictionary | CORE / DICTIONARY | ✅ | 2026-10-06 | `4f29b7b2` | The VR and VM columns have not been text-diffed. Only (0020,9170)–(9172) were checked, dur |
| D7 | DICOMDictionary tests | CORE / DICTIONARY | ✅ | 2026-10-06 | `4f29b7b2` | The test is labelled "CP-1818 elements", which fits only the Extended Offset Table rows. T |
| D8 | Repo docs | CORE | ✅ | 2026-10-06 | `a08258f9` | Credits the 64-bit VRs to CP-1818; the correct CP is 1819. That entry is already released, |
| D9 | dicom-compress (+ DICOMStudio) | CLI / CORE / STUDIO | ✅ | 2026-10-06 | `dfc929c`, `1bbc18a8` | .4.110 called "JPEG XL Lossless Only"; PS3.6 name is "JPEG XL Lossless". The 25 codec help |
| D10 | DICOMStudio | CORE / STUDIO | ✅ | 2026-10-06 | `1b0588eb` | Omits XYB, YBR_PARTIAL_420, YBR_ICT and YBR_RCT, so those files get no thumbnail. Consider |
| D11 | DICOMStudio | CORE / STUDIO | ✅ | 2026-10-06 | `1b0588eb` | No label for XYB, so the raw "XYB" is shown. Add something like "XYB (JPEG XL)". |
| D12 | DICOMKit | CORE / KIT | ✅ | 2026-09-29 | `c1795b3` | Relabels JPEG Baseline YBR to RGB after decode, but not JPEG XL XYB. It should match `Tran |
| D13 | DICOMNetwork tests | CORE / NETWORK | ✅ | 2026-09-28 | `ab3e5fc` | 8 XCTest failures that also fail on HEAD without this work, confirmed 2026-09-24 by stashi |
| D14 | DICOMKit | CORE / KIT | ✅ | 2026-09-29 | `32253bf` | Throws "Missing or invalid Directory Record Type" for any (0004,1430) value that `Director |
| D15 | dicom-dcmdir, DICOMStudio, DICOMKit | CORE / KIT | ✅ | 2026-10-06 | `32253bf`, `ca2bd29`, `2f730cac` | The `--profile` help and error text still list `STD-GEN-DVD` and `STD-GEN-USB`, which are  |
| D16 | DICOMKit | CORE / KIT | ✅ | 2026-09-29 | `bd4973a` | A second, conflicting copy of the value-type rules, defined as an extension in DICOMKit ne |
| D17 | DICOMKit | CORE / KIT | ✅ | 2026-09-29 | `bd4973a` | Both emit DATETIME content items. PS3.3 A.35.5 (Mammography CAD SR) and A.35.4 (Key Object |
| D18 | DICOMKit | CORE / KIT | ✅ | 2026-09-29 | `bd4973a` | Emit 2D SCOORD content items with Graphic Type POLYGON, which PS3.3 C.18.6.1.2 does not de |
| D19 | — | CORE / KIT | ✅ | 2026-09-29 | `32253bf` | `DICOMFile+FrameAccess.swift:187` says "the OV VR is not yet in the `VR` enum, so explicit |
| D20 | — | CORE / DICTIONARY | ✅ | 2026-10-06 | `f5aa6d0a` | `UIDDictionary.swift:239-252` registers the two "Fragmentable HEVC" UIDs 1.2.840.10008.1.2 |
| D21 | DICOMNetwork | DICTIONARY / NETWORK | ✅ | 2026-09-28 | `be777c1` | Proposes one storage context per `StorageSOPClass.allUIDs` entry and stops at ID 255 (127  |
| D22 | DICOMStudio | NETWORK / STUDIO | ✅ | 2026-10-06 | `6ab02140` | `BLU-RAY` is not a Medium Type defined term; the app re-declares `PrintPriority`, `PrintMe |
| D23 | DICOMPrintKit | NETWORK / PRINTKIT | ✅ | 2026-09-29 | — | Cites "PS3.3 Table C.13-3" for the Bits Stored 8/12 rule; the image-box pixel enumerations |
| D24 | DICOMKit | KIT / NETWORK | ✅ | 2026-09-29 | `535d609` | Duplicate type |
| D25 | DICOMCore | WEB | ✅ | 2026-10-06 | `511ac8ab` | Splits on backslash with `split(separator:)`, which omits empty subsequences, so `"MPG\\XR |
| D26 | DICOMCore | KIT | ✅ | 2026-09-29 | `833a3fb` | Includes TCOORD, which Table A.35.10-2 lists only as a source, and lacks WAVEFORM, a TCOOR |
| D27 | DICOMPrintKit | KIT / PRINTKIT | ✅ | 2026-09-29 | `dc2c0f0` | Displayed Area Selection Sequence (Type 1) omitted for fit views (NC-4): pass `imageSize:` |
| D28 | DICOMStudio | KIT / STUDIO | ✅ | 2026-10-06 | `6372e096` | Falls back to the image's rescale when the PR has no Modality LUT (NC-2; now that DICOMKit |
| D29 | dicom-dcmdir (+ DICOMStudio) | CLI / KIT / STUDIO | ✅ | 2026-10-06 | `ca2bd29`, `2f730cac` | `--profile` help/error listed STD-GEN-DVD / STD-GEN-USB (Annex H/J family headings, not id |
| D30 | DICOMPrintKit | KIT / PRINTKIT | ✅ | 2026-10-06 | `535d6093` | Map between the two `PrintColorMode` types |
| D31 | DICOMCore (+ DICOMKit SR serializer/pars | KIT | ✅ | 2026-09-30 | `ce48c42`, `585e79f` | Only `ContainerContentItem` carries child content items, but Table C.17-6 applies the Docu |
| D32 | DICOMKit | KIT | ✅ | 2026-09-29 | `2a69944` | Structural placement of the model: Image Set Number/Category/Relative Time/Abstract Prior  |
| D33 | DICOMKit | KIT | ✅ | 2026-09-29 | `9ff9dd1` | `DICOMVolume` has no Photometric Interpretation or High Bit field, so a MONOCHROME1 volume |
| D34 | DICOMKit | KIT | ✅ | 2026-09-30 | `ba0a656` | Still say "DICOM video has no audio"; PS3.5 8.2.5–8.2.12 permit audio under Table 8.2.12-1 |
| D35 | DICOMCore | KIT | ✅ | 2026-09-29 | `157e2b3` | No `Tag` constants for (3004,0054) DVH Volume Units, (300A,00CE) Treatment Delivery Type,  |
| D36 | DICOMStudio, DICOMPrintKit | KIT / PRINTKIT | ✅ | 2026-09-29 | `dc2c0f0` | Do not yet pass `imageSize:`; without it a state with no displayed area is still written w |
| D37 | DICOMKit | KIT | ✅ | 2026-09-30 | `a912417`, `a3c60c1`, `1530c52` | Remaining gaps recorded by the P-item pass: Verifying Observer Sequence (1C when VERIFIED) |
| D38 | DICOMKit tests | KIT | ✅ | 2026-09-30 | `cfc7d05`, `fd15624` | Excluded from the `DICOMKitTests` target and never compiled; port or delete |
| D39 | DICOMKit | PRINTKIT | ✅ | 2026-10-06 | `bbe90b0a`, `37e59463` | No Compound Graphic Sequence (0070,0209) — Compound Graphic Type ARROW, RULER, RECTANGLE … |
| D40 | DICOMNetwork | PRINTKIT | ✅ | 2026-10-06 | `8dada6c0` | Cites "PS3.5 3.6.1" for Enumerated Values; no such section in 2026a (it is PS3.5 6.3) |
| D41 | DICOMNetwork | PRINTKIT | ✅ | 2026-10-06 | `8dada6c0` | Text String (2030,0020) written as LO without the 64-character limit or the backslash rule |
| D42 | DICOMStudio | PRINTKIT / STUDIO | ✅ | 2026-10-06 | `6372e096` | Pass the image's Photometric Interpretation (and Rescale Type) to `ViewerPresentationState |
| D43 | DICOMKit tests | PRINTKIT | ✅ | 2026-10-06 | `d411e1ed` | Pin the behaviour from before P-ENCAP (`01fdeb66`); fail on HEAD `56115eaa` without any DI |
| D44 | dicom-ai | CLI / KIT | ✅ | 2026-10-06 | `3fe88bd` | Worse than reported: the writer discarded the builder's data set and emitted 14 attributes |
| D45 | DICOMKit | KIT | ✅ | 2026-09-30 | `b5587dc` | Tracking ID (0062,0020) and Tracking UID (0062,0021) are 1C on each other; the writer does |
| D46 | DICOMKit | KIT | ✅ | 2026-09-30 | `74e7b16` | Audio kept but not checked against PS3.5 8.2.12 (codec, 48 kHz for AAC/AC-3/LPCM, channels |
| D47 | docs | KIT | ✅ | 2026-09-30 | `afa112e` | Still say DICOM video IODs have no audio |
| D48 | DICOMKit | KIT | ✅ | 2026-09-30 | `f99a0e6` | Inputs in (-1, 0) truncate to index 0 through `Int()` and bypass the clamp, returning a va |
| D49 | DICOMKit | KIT | ✅ | 2026-09-30 | `9183b68` | Display-model values (ALPHA, MIP, …) look like DICOM terms but are never written; Blending |
| D50 | DICOMCore | KIT | ✅ | 2026-09-30 | `6b55602` | TID 4000 and TID 4100 are not registered, so the CAD trees cannot be checked with `Templat |
| D51 | DICOMKit tests | KIT | ✅ | 2026-09-30 | `1e4be3b`, `ac61700`, `3c904a3` | Committed but in neither `sources:` nor `exclude`; never compiled ("unhandled files" warni |
| D52 | DICOMCore | KIT | ✅ | 2026-09-30 | `50fc300` | TID 1500 rows 7, 8 and 9 include TID 1410, 1411 and 1501, whose row 1 is the same CONTAINE |
| D53 | DICOMKit | KIT | ✅ | 2026-09-30 | `c9316f6` | Normalises a VOI LUT Sequence table over its entries' actual span, not over 0…2^n − 1 with |
| D54 | DICOMKit | KIT | ✅ | 2026-09-30 | `b419f01`, `f99a0e6` | Convert a Double to an index with `Int(_:)` before clamping, which traps on NaN or ±infini |
| D55 | DICOMCore | KIT | ✅ | 2026-09-30 | `6b55602` | A Value Set Constraint of one code per paragraph was read from its first paragraph only: T |
| D56 | dicom-video (+ DICOMStudio) | CLI / KIT / STUDIO | ✅ | 2026-10-06 | `8eebfab`, `38a2eea0` | No option named the audio Channel Source. Correction to the earlier row: (003A,0300) is Mu |
| D57 | DICOMKit | KIT | ✅ | 2026-09-30 | `8cde34b`, `eabfa8c` | A closed enum of the six CID 3000 codes, while CID 3000 is Extensible and included as a De |
| D58 | DICOMKit | KIT | ✅ | 2026-09-30 | — | Constraints still reported "not checked": CBR of MP3 (needs every frame header read), bits |
| D59 | DICOMKit | KIT | ✅ | 2026-09-30 | `ce7461a` | E-AC-3 is reported as a format 8.2.12 does not permit. Table 8.2.12-1 lists "AC3", but 8.2 |
| D60 | DICOMKit | KIT | ✅ | 2026-09-30 | `4963a51` | Does not read the Cine attributes `VideoBuilder` writes: Frame Time Vector (0018,1065), Pr |
| D61 | DICOMKit | KIT | ✅ | 2026-09-30 | `09df614` | An MP3 frame in dual channel mode (two independent mono programmes, ISO/IEC 11172-3) is ac |
| D62 | DICOMKit | KIT | ✅ | 2026-09-30 | `09df614` | AAC in MPEG-TS (ADTS 0x0F, LATM 0x11) has no stated bit rate, so the 640 kbps maximum of T |
| D63 | DICOMCore (and DICOMKit `SIMDImageProces | RENDERKIT | ✅ | 2026-09-30 | `f82a607` | Truncating a floating-point result makes the standard's identity window lossy: with c = 12 |
| D64 | DICOMCore | RENDERKIT | ✅ | 2026-09-30 | `e1a31fe` | Every width is clamped to ≥ 1; SIGMOID and LINEAR_EXACT only require w > 0, so a width of  |
| D65 | DICOMKit, DICOMStudio | RENDERKIT | ✅ | — | — | The window is converted to stored units as `(c − b)/m`, `w/ |
| D66 | DICOMKit | RENDERKIT | ✅ | 2026-09-30 | `acc6301`, `56207e0` | The pixel-range auto window is c = (min+max)/2, w = max − min; the standard's full-range w |
| D67 | DICOMKit, DICOMCore | RENDERKIT | ✅ | 2026-09-30 | `85c5a80`, `5b3807a`, `bfc25d4`, `56207e0` | A Bits Allocated 32 cell is assembled from its first two bytes, so 65,541 renders as 5 (e. |
| D68 | DICOMStudio | RENDERKIT / STUDIO | ✅ | 2026-10-06 | `6372e096` | Pass the image's Modality LUT (rescale or sequence), VOI (window in modality units or VOI  |
| D69 | DICOMKit | KIT | ✅ | 2026-09-30 | `f8e7d8e` | Found 2026-09-30 when closing the E.1-1 coverage gap by script: the engine applied 79 hand |
| D70 | DICOMKit | CLI | ✅ | 2026-10-01 | `c0943cfc` | The chosen Application Profile is stored but never enforced: PS3.11 Table D.3-1 allows onl |
| D71 | DICOMKit | CLI | ✅ | 2026-10-01 | `96012f70` | `buildDataSet` writes neither the Enhanced General Equipment Module (Table A.51-1 M; Manuf |
| D72 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8` | `StoreResult.success` is false for the Warning class (B000, B006, B007 are successes per P |
| D73 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | No names for 0117 (Invalid object instance), 0210 (Duplicate invocation), 0211 (Unrecogniz |
| D74 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8` | Prints "instance"; the Query/Retrieve Level value is IMAGE |
| D75 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8`, `3b0033f8`, `cc5f315a` | C-STORE Warning statuses are rendered neither as success nor failure |
| D76 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `3b0033f8` | Service-agnostic wording for A701/A702/A801/A900/B000/Cxxx differs from the Q/R names in P |
| D77 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8` | "Level: Instance"; "Completed:/Failed:/Warnings:" instead of the PS3.7 sub-operation names |
| D78 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `3b0033f8` | state JSON stores (0008,0060) under `modality` for a study-level (0008,0061) value |
| D79 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | C-FIND failure names differ from the 2026a tables: 0xA900 printed "Error: Identifier/Data  |
| D80 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `3b0033f8` | 10 of 38 JSON keys are not PS3.6 keywords (see P-MWL-JSON-KEYS); shared with DICOMStudio's |
| D81 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8` | `validateScheduledStationAETitle` tolerates `*`/`?` although Table K.6-1 row 3 allows Sing |
| D82 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | `DIMSEStatus.from` maps no DIMSE-N code except 0110/0111/0112/0118/0122/0213; 0105, 0106,  |
| D83 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | MPPS N-CREATE / N-SET failures are thrown as `DICOMNetworkError.storeFailed` → "Store fail |
| D84 | DICOMNetwork | CLI | ✅ | — | `e3caf409` | Sources/DICOMNetwork/MPPSService.swift:143, :162, :326 |
| D85 | DICOMStudio | CLI / STUDIO | ✅ | 2026-10-06 | `d716de90` | same wrong placeholder "110513\/DCM\/Doctor cancelled procedure"; and :1217-1221 offers `- |
| D86 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | the N-CREATE data set never creates (0040,0281) zero-length, yet the N-SET sends it for DI |
| D87 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | `add(0x0008,0x0060,.CS, procedureStep.modality)` writes an empty value when `modality` is  |
| D88 | Tests/DICOMStudioTests | CLI / STUDIO | ✅ | 2026-10-06 | `32929df7` | parse fixtures use the wrong code/meaning pairs ("110513 Doctor cancelled procedure", "110 |
| D89 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `214bab33` | `FilmDestination` has only BIN_1 and BIN_2; Table C.13-1 defines BIN_i "with no maximum",  |
| D90 | DICOMPrintKit | CLI | ✅ | 2026-10-01 | `350bc2de` | Printer/job status labels "Name", "Status", "Status Info", "Model", "Created" instead of t |
| D91 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | Print Management statuses carry no Annex H name: C6xx prints as "Failed: unable to process |
| D92 | DICOMPrintKit | CLI | ✅ | 2026-10-01 | `350bc2de` | Trim = YES is drawn as four crop marks at the sheet corners; Table C.13-3 says "a trim box |
| D93 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `e3caf409` | 6 of 9 Annex H codes paraphrased. B604 should read "Image size is larger than image box si |
| D94 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | --aet / --allowed-ae / --blocked-ae not validated as VR AE (16 chars); Implementation Clas |
| D95 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | Outgoing P-DATA fragmented to the server's own --max-pdu-size instead of the peer's Maximu |
| D96 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | Unknown Move Destination is sent to localhost:104 instead of status A801 "Refused: Move De |
| D97 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | C-GET sub-operations counted Completed without awaiting C-STORE-RSP; no SCP/SCU Role Selec |
| D98 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | Wildcard applied to UI keys (C.2.2.2.4 lists AE, CS, LO, LT, PN, SH, ST, UC, UR, UT only), |
| D99 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | Target excluded and ~35 compile errors against the current DICOMNetwork/DICOMKit API; DICO |
| D100 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | Required keys not matched/returned: Study Time, Accession Number, Study ID (C.6-2), Patien |
| D101 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | Missing Query/Retrieve Level (0008,0052) defaults to STUDY; the request Identifier "shall  |
| D102 | dicom-server | CLI | ✅ | 2026-10-01 | `7bad09d` | Stored files lack preamble/DICM/File Meta (PS3.10 7.1) and the data set is parsed without  |
| D103 | dicom-gateway | CLI | ✅ | 2026-10-01 | `92421a38` | `forward --listen-port` accepts TCP but implements no PS3.8 Upper Layer / C-STORE SCP; `li |
| D104 | dicom-gateway | CLI | ✅ | 2026-10-01 | `6db2d67f` | Without --template the output claims Secondary Capture Image Storage but has no Image Pixe |
| D105 | DICOMWeb | CLI | ✅ | 2026-10-01 | `f4262b4f` | study column "Modality" holds Modalities In Study (0008,0061); "# Images" is Number of Ser |
| D106 | DICOMWeb | CLI | ✅ | 2026-10-01 | `f4262b4f` | prints "Code <decimal>" without the PS3.18 Table I.2-2 meaning/hex; Warning Reason (Table  |
| D107 | DICOMWeb | CLI | ✅ | 2026-10-01 | `f4262b4f` | rejects the standard term "IN PROGRESS" (accepts only IN_PROGRESS/INPROGRESS); PS3.3 Table |
| D108 | DICOMWeb | CLI | ✅ | 2026-10-01 | `f4262b4f` | 9 optional WADO-URI parameters (charset, annotation, imageAnnotation, imageQuality, region |
| D109 | DICOMCore | CLI | ✅ | 2026-10-01 | `0d8aa69d` | Pixel Data absent, (0028,7FE0)) |
| D110 | DICOMWeb | CLI | ✅ | 2026-10-01 | `d6baa4f7` | The BulkDataURI is `<base>/<GGGGEEEE>` regardless of nesting, so the same tag in two seque |
| D111 | DICOMWeb | CLI | ✅ | 2026-10-01 | `d6baa4f7` | `metadataOnly` removes only (7FE0,0010) at the top level. Float Pixel Data (7FE0,0008), Do |
| D112 | DICOMWeb | CLI | ✅ | 2026-10-01 | `55b5e6b9` | `DICOMFile.create` is called without `sopClassUID:` / `sopInstanceUID:`, so a reverse-conv |
| D113 | DICOMWeb | CLI | ✅ | 2026-10-01 | `d6baa4f7` | The decoder runs with `fetchBulkData: false`, so an attribute that carries a BulkDataURI ( |
| D114 | DICOMStudio | CLI / STUDIO | ✅ | 2026-10-06 | `2f730cac` | Workshop `CLIWorkshopViewModel.swift:1258` builds `includeEmpty` from `paramValue("include |
| D115 | DICOMWeb | CLI | ✅ | 2026-10-01 | `d6baa4f7` | An empty value of a multi-valued PN is skipped, so the numbers come out as 1, 3. `DICOMXML |
| D116 | DICOMKit | CLI | ✅ | 2026-10-01 | `0a7f5b57` | Labels are not PS3.6 names: "Study UID", "Patient Name", "Description" (study and series), |
| D117 | DICOMKit | CLI | ✅ | 2026-10-01 | `0a7f5b57` | `--pattern descriptive` series folder `<Series Number>_<Modality>_<Series Description>` is |
| D118 | DICOMKit | CLI | ✅ | 2026-10-01 | `0a7f5b57` | Files without Series Instance UID / SOP Instance UID (Type 1) are merged under "UNKNOWN"/" |
| D119 | DICOMKit | CLI | ✅ | 2026-10-01 | `0a7f5b57` | Markers say "carries no DICOM-standard data", but the files read 13 attributes, group by t |
| D120 | DICOMKit | CLI | ✅ | 2026-10-01 | `2f70f6eb` | `wildcardMatch` upper-cases pattern and value for every key; Patient ID (LO) wild cards mu |
| D121 | DICOMKit | CLI | ✅ | 2026-10-01 | `2f70f6eb`, `d46affe` | No List of UID Matching or DA Range Matching for Study Instance UID / Study Date (the CLI  |
| D122 | DICOMKit | CLI | ✅ | 2026-10-01 | `2f70f6eb` | The study record's `modality` is the first imported instance's Modality and is shown as th |
| D123 | DICOMKit | CLI | ✅ | 2026-10-01 | `2f70f6eb` | Labels "Patient Name", "Description", "Series", "Images", "Studies" are not PS3.6 names (P |
| D124 | DICOMKit | CLI | ✅ | 2026-10-01 | `2f70f6eb` | Patients keyed on Patient ID alone: Issuer of Patient ID (0010,0021) ignored, and every fi |
| D125 | DICOMKit | CLI | ✅ | 2026-10-01 | `2f70f6eb` | Marker says "carries no DICOM-standard data (SQLite-backed index)": the index is JSON, and |
| D126 | DICOMKit | CLI | ✅ | 2026-10-01 | `46e453ee` | `--exif-fields PatientID` is read (getDICOMFieldValue) but has no EXIF mapping and is drop |
| D127 | DICOMStudio | CLI / STUDIO | ✅ | 2026-10-06 | `2f730cac` | The CLI Workshop still copies the contact-sheet and animate render paths that dicom-export |
| D128 | DICOMKit | CLI | ✅ | 2026-10-01 | `c0943cfc` | `--verbose` record attributes printed as bare tags, no PS3.6 attribute names; "Consistent" |
| D129 | DICOMKit | CLI | ✅ | 2026-10-01 | `c0943cfc` | `DirectoryRecord` is a struct: when the series (or study) already exists, the copy that re |
| D130 | DICOMCore | CLI | ✅ | 2026-10-01 | `b8425965` | `validate(checkFileExistence:)` is a placeholder (only rejects an empty path) — CLI now ch |
| D131 | DICOMKit | CLI | ✅ | 2026-10-01 | `c0943cfc`, `a45fd45` | FSC writes the raw relative path as File ID (lower case, `.dcm`, >8 chars); an FSC should  |
| D132 | DICOMStudio | CLI / STUDIO | ✅ | 2026-10-06 | `2f730cac` | lacks the CLI's new validate rules and File-set ID default (parity) |
| D133 | DICOMKit | CLI | ✅ | 2026-10-01 | `5c921abf` | "Must have at least 2 components" is not a PS3.5 9.1 rule; messages don't cite 9.1; `valid |
| D134 | DICOMKit | CLI | ✅ | 2026-10-01 | — | "Well-Known UID" / "Application Context" / folded "DICOM UIDs as a Coding Scheme" differ f |
| D135 | DICOMKit | CLI | ✅ | 2026-10-01 | `5c921abf` | walks `dataSet.allElements` (top level only): Referenced SOP Instance UID (0008,1155) in R |
| D136 | DICOMKit | CLI | ✅ | 2026-10-01 | `5c921abf` | not-found text says "Transfer Syntax or SOP Class"; filter list has 2 values (CLI no longe |
| D137 | DICOMKit | CLI | ✅ | 2026-10-01 | `55b5e6b9` | `DICOMFile.create(dataSet:sopClassUID:)` without `sopInstanceUID:` writes a fresh Media St |
| D138 | DICOMKit | CLI | ✅ | 2026-10-01 | `5c921abf` | criterion "value not in Table A-1" also replaces UIDs that are not instance identifiers: C |
| D139 | DICOMCore | CLI | ✅ | 2026-10-01 | `b8425965` | force-unwrap crash on a malformed root; truncation to 64 cuts the unique suffix (identical |
| D140 | DICOMKit | CLI | ✅ | 2026-10-01 | `eddc0b49` | GSPS/PCPS: Content Creator's Name (0070,0084) required as Type 2 "[C.11.10 … (Table 10-12) |
| D141 | DICOMKit | CLI | ✅ | 2026-10-01 | `eddc0b49` | message prefixes "CR Image Storage", "US Image Storage", "GSPS", "Pseudo-Color PS", "Key O |
| D142 | DICOMKit | CLI | ✅ | 2026-10-01 | `eddc0b49` | level 2 checks no VR maximum length / repertoire except DA, TM, UI and CS lowercase (warni |
| D143 | DICOMKit | CLI | ✅ | 2026-10-01 | `eddc0b49` | KOS/SR root Concept Name Code Sequence printed as "Type 1 … (Table C.17-5, Root Content It |
| D144 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918` | `buildTagPositionMap` always skips 132 bytes when the data is longer than 132, without che |
| D145 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918` | (FFFE,xxxx) is stepped over with no position entry, so Item / Item Delimitation Item / Seq |
| D146 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918`, `d032c4d7` | Private Creator Data Elements (gggg,0010-00FF) print "Unknown" / no name |
| D147 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918` | `--statistics` prints the Transfer Syntax UID and SOP Class UID without their Table A-1 na |
| D148 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918` | the tag filter matches the PS3.6 name or tag text but never the keyword (DICOMStudio's Wor |
| D149 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918` | JSON `value` is omitted for binary VRs (US, UL, FL, FD, AT, …) though text/CSV render them |
| D150 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918`, `b091aa5` | `applyChanges` writes `setString` under the existing-or-first dictionary VR for any VR (bi |
| D151 | DICOMCore | CLI | ✅ | 2026-10-01 | `b8425965` | `isPrivate` = any odd group; PS3.5 7.1 excludes 0001, 0003, 0005, 0007, FFFF from Private  |
| D152 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918` | `ignorePrivate` applies only to top-level elements; private elements inside sequence items |
| D153 | DICOMKit | CLI | ✅ | 2026-10-01 | `d812b918` | Pixel Data compared byte by byte: `--tolerance`, max/mean and "Different pixels" are per b |
| D154 | DICOMStudio | CLI / STUDIO | ✅ | 2026-10-06 | `2f730cac` | Workshop help for dicom-split `--frames` ("Frame selection (ranges/list)") does not say th |
| D155 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8` | Default SCP/SCU Implementation Class UIDs are not under DICOMKit's UID root |
| D156 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8` | No way to set Move Originator AE Title / Message ID (0000,1030/1031) on the C-STORE-RQ, so |
| D157 | DICOMKit | CLI | ✅ | 2026-10-01 | `31536bad` | Modified Dates Option shifts only DA; DT (60 rows), TM (52) and 3 other C cells are zeroed |
| D158 | DICOMKit | CLI | ✅ | 2026-10-01 | `31536bad` | Clean Descriptors Option keeps every C attribute verbatim (140 rows on the fixture, e.g. S |
| D159 | DICOMKit | CLI | ✅ | 2026-10-01 | `5aeca208`, `dfe30cc9` | `Options` has no Retain Safe Private, Clean Structured Content, Clean Graphics, Clean Reco |
| D160 | DICOMKit | CLI | ✅ | 2026-10-01 | `31536bad` | After pixel cleaning (113101 recorded by PixelRedactor), (0012,0063) omits "Clean Pixel Da |
| D161 | DICOMKit | CLI | ✅ | 2026-10-01 | `31536bad` | `recordMethod` never writes Longitudinal Temporal Information Modified (0028,0303): REMOVE |
| D162 | DICOMKit | CLI | ✅ | 2026-10-01 | `55b5e6b9` | `deidentify` (and `anonymize`, :222) keep the source File Meta: Media Storage SOP Instance |
| D163 | DICOMKit | CLI | ✅ | 2026-10-01 | `31536bad` | `parseFlexibleTag` knows 11 hard-coded keywords and its lowercased lookup can never match  |
| D164 | DICOMKit | CLI | ✅ | 2026-10-01 | `31536bad` | Legacy `shiftAllDates`/`regenerateAllUIDs` (:321) ignore `preserveTags`: `--keep StudyDate |
| D165 | DICOMKit | CLI | ✅ | 2026-10-01 | `55b5e6b9` | `DICOMFile.create(dataSet:transferSyntaxUID:)` is called without `sopInstanceUID`, so (000 |
| D166 | DICOMKit | CLI | ✅ | 2026-10-01 | `3ca15a08` | text written as UTF-8 without Specific Character Set (0008,0005) "ISO_IR 192" when a value |
| D167 | DICOMKit | CLI | ✅ | 2026-10-01 | `3ca15a08` | converter identity (DICOMKit / "dicom-image CLI" / "1.1.6") written to General Equipment,  |
| D168 | DICOMKit | CLI | ✅ | 2026-10-01 | `3ca15a08` | EXIF UserComment/ImageDescription written to Study Description (LO) without the 64-charact |
| D169 | DICOMKit | CLI | ✅ | 2026-10-01 | `ed4470db` | `processData` returns the edit with the source SOP Instance UID, Image Type, Implementatio |
| D170 | DICOMKit | CLI | ✅ | 2026-10-01 | `ed4470db` | `applyWindowLevel` applies center/width to stored values; Window Center/Width are Modality |
| D171 | DICOMKit | CLI | ✅ | 2026-10-01 | `ed4470db` | `applyCrop` leaves Image Position (Patient) (top level and Plane Position Sequence in func |
| D172 | DICOMKit | CLI | ✅ | 2026-10-01 | `ed4470db` | `setPixelValue` clamps to the Bits Allocated range, not Bits Stored / Pixel Representation |
| D173 | DICOMKit | CLI | ✅ | 2026-10-01 | `ed4470db` | decoding a lossy-compressed input writes native pixels without setting Lossy Image Compres |
| D174 | DICOMKit | CLI | ✅ | 2026-10-01 | `ed4470db` | window/invert transform PALETTE COLOR indices and leave Pixel Padding Value (0028,0120) un |
| D175 | DICOMKit | CLI | ✅ | 2026-10-01 | `55b5e6b9` | Root cause of D112, D137, D162, D165 (and the CLI workarounds in dicom-anon, dicom-image,  |
| D176 | DICOMCore | CLI | ✅ | 2026-10-01 | `0d8aa69d` | The 16 video transfer syntax names are abbreviations, not the PS3.6 names ("MPEG2 Main Pro |
| D177 | DICOMKit | CLI | ✅ | 2026-10-01 | `99c47e2e` | MPEG2 MP@ML/MP@HL streams are rejected unless in MP4 or MPEG-TS, citing 8.2.7; 8.2.5 and 8 |
| D178 | DICOMKit | CLI | ✅ | 2026-10-01 | `99c47e2e` | MPEG2 level printed as "0.8" (level_indication 8); PS3.5 names the levels "Main Level" / " |
| D179 | DICOMKit | CLI | ✅ | 2026-10-01 | `99c47e2e` | A raw MPEG-2 elementary stream (.m2v, sequence header 00 00 01 B3) is tried as H.264 first |
| D180 | DICOMKit | CLI | ✅ | 2026-10-01 | `99c47e2e` | A non-ASCII --patient-name (or other text) is written as UTF-8 without Specific Character  |
| D181 | DICOMKit | CLI | ✅ | 2026-10-01 | `51ef296a` | `documentData` is the padded value; (0042,0015) is ignored, so an odd-length document gain |
| D182 | DICOMKit | CLI | ✅ | 2026-10-01 | `51ef296a` | Builder writes neither Encapsulated Document Length (0042,0015) nor Specific Character Set |
| D183 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | "Compression ratio: 12.0%" is output/input size in percent, not the N:1 ratio PS3.3 define |
| D184 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | Lossy compress records (0028,2110/2112/2114) and DERIVED but keeps the SOP Instance UID an |
| D185 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | After a JPEG 2000 / HTJ2K encode of a 3-sample image the codestream has COD MCT = 1 (RCT w |
| D186 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | Decompressing a YBR_RCT / YBR_ICT JPEG 2000 file writes native RGB samples labelled YBR_RC |
| D187 | DICOMCore (J2KSwift dependency) | CLI | ✅ | 2026-10-01 | `4ed69751` | 1.2.840.10008.1.2.4.202 output has COD progression LRCP (the encoder always writes 0 whate |
| D188 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | File Meta UI values (0002,0002), (0002,0003), (0002,0010) are written with odd length and  |
| D189 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | Comment cites "PS3.3 C.7.6.1.1.5.1: shall be set to DERIVED"; that sentence is in C.7.6.1. |
| D190 | DICOMCore | CLI | ✅ | 2026-10-01 | `4ed69751`, `d2e9e3f8`, `d37433f0` | .4.50 colour output carries a JFIF APP0 segment and YCbCr 4:4:4 components while Photometr |
| D191 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | `stripPrivate` filters the top-level Data Set only; a Private Creator and Private Data Ele |
| D192 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | A lossy convert records (0028,2110/2112/2114) and DERIVED but keeps the SOP Instance UID ( |
| D193 | DICOMCore | CLI | ✅ | 2026-10-01 | `4ed69751` | J2K → native keeps PI YBR_RCT / YBR_ICT over RGB samples (only XYB and JPEG YBR are relabe |
| D194 | DICOMKit | CLI | ✅ | 2026-10-01 | `488a9c07` | NUM with an empty Measured Value Sequence (Type 2, zero items allowed) is parsed as value  |
| D195 | DICOMKit | CLI | ✅ | 2026-10-01 | `488a9c07` | Numeric Value Qualifier Code Sequence (0040,A301) is never read (`qualifier: nil`), althou |
| D196 | DICOMKit | CLI | ✅ | 2026-10-01 | `488a9c07` | Referenced Waveform Channels (0040,A0B0), Type 1C, is not written for WAVEFORM items ("can |
| D197 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | `rescale(_:)` takes no frame index and calls `rescaleSlope()`/`rescaleIntercept()` without |
| D198 | DICOMKit | CLI | ✅ | 2026-10-01 | `488a9c07` | `SRDocumentSerializer` writes only Patient's Name / Patient ID and Study Instance UID / St |
| D199 | DICOMKit | CLI | ✅ | 2026-10-01 | `488a9c07` | `MeasurementReportBuilder` has no API for TID 4019 Algorithm Identification (TID 1500 rows |
| D200 | DICOMKit | CLI | ✅ | 2026-10-01 | `092cf368` | the `query` template passes `--study-date-from 20240101 --study-date-to 20241231`, options |
| D201 | DICOMKit | CLI | ✅ | 2026-10-01 | `092cf368` | `pipeline` / `query` templates pass `--host ${PACS_HOST}`; dicom-query and dicom-retrieve  |
| D202 | DICOMKit | CLI | ✅ | 2026-10-01 | `e2c5ea18` | `pipeline` / `anonymize` templates use `dicom-anon --profile basic` (the legacy profile di |
| D203 | DICOMKit | CLI | ✅ | 2026-10-01 | `092cf368` | `dicom-archive create … --input` — dicom-archive has no `create` subcommand (`init`, `impo |
| D204 | DICOMKit | CLI | ✅ | 2026-10-01 | `100a5455` | decode-volume slices: Image Position (Patient) z = origin.z + i·spacing (ignores Image Ori |
| D205 | DICOMKit | CLI | ✅ | 2026-10-01 | `100a5455` | sidecar origin taken from the unsorted series[0] and slice spacing from the z coordinate o |
| D206 | DICOMKit | CLI | ✅ | 2026-10-01 | `d2e9e3f8`, `d37433f0`, `59936daf` | For an Explicit VR Big Endian target the helper writes big-endian headers but copies each  |
| D207 | dicom-3d | CLI | ✅ | 2026-10-01 | `6347a617` | `interpolatedVoxelAt(.nearest)` accepts x in [n-1, n) and uses `round`, so x ≥ n-0.5 round |
| D208 | dicom-convert | CLI | ✅ | 2026-10-01 | `990636cc` | Help attributes "the first Frame is Frame number 1" to PS3.3 C.7.6.6. In the 2026a DocBook |
| D209 | DICOMKit | CLI | ✅ | 2026-10-01 | `2f70f6eb` | The query table and text output still print the study-level `modality` (first instance imp |
| D210 | DICOMNetwork | CLI | ✅ | 2026-10-01 | `22e39bd8` | `GenericQueryResult` keeps only `[Tag: Data]` (no VR, no transfer syntax), so `dicomJSONEl |
| D211 | dicom-anon (docs) | CLI | ✅ | 2026-10-01 | `c1dcbbb5` | repo docs still show `dicom-anon --profile clinical-trial` / `basic` as the old lists. `ba |
| D212 | dicom-anon (tests) | CLI | ✅ | 2026-10-01 | `c1dcbbb5` | uncompiled test scripts still use `dicom-anon --profile basic` / `--profile strict` (no su |
| D213 | DICOMWeb | CLI | ✅ | 2026-10-01 | `f4262b4f` | The parsed workitem drops the server's DICOM JSON, so `UPSResultFormatter` cannot render ` |
| D214 | dicom-gateway | CLI | ✅ | 2026-10-01 | `8e018761` | The listener's (not implemented, D103) forward path still builds the template-less Seconda |
| D215 | DICOMWeb | CLI | ✅ | 2026-10-01 | `d6baa4f7` | (unverified, for the DICOMWeb agent) `decode` builds the main data set from every decoded  |
| D216 | DICOMCore (J2KSwift dependency) | CLI | ⏳ | 2026-10-06 | — | J2KSwift ignores `J2KEncodingConfiguration.progressionOrder` (packets always LRCP, COD 0), |
| D217 | DICOMCore (JLISwift dependency) | CLI | ✅ | 2026-10-01 | `d2e9e3f8`, `d37433f0` | .4.50/.4.51 colour output is YCbCr (4:4:4 JLI; ImageIO subsampling unchecked) while Photom |
| D218 | DICOMCore (J2KSwift dependency) | CLI | ✅ | 2026-10-01 | `d2e9e3f8`, `d37433f0` | J2KSwift applies the multi-component transformation to every 3-component image, so native  |
| D219 | DICOMKit | CLI | ✅ | 2026-10-01 | `d37433f0` | The D193 defect in the DICOMKit compression path (dicom-compress, DICOMStudio): RGB → J2K/ |
| D220 | dicom-mpps | CLI | ✅ | 2026-10-01 | `4739989f`, `e3caf409` | `dimseNStatusNames` duplicates DICOMNetwork's generated Annex C table and `rethrowNamed`'s |
| D221 | DICOMToolbox | CLI | ⏳ | 2026-10-06 | — | dicom-anon `--profile` picker offers basic / clinical-trial / research (default basic): cl |
| D222 | DICOMKit | CLI | ✅ | 2026-10-01 | `60937f6b` | Content Creator's Name (0070,0084) is Type 3 in 2026a (Table 10.9.3-1 via Table 10-12, als |
| D223 | DICOMKit | CLI | ✅ | 2026-10-01 | `1a4e5455` | the workflow / pipeline / anonymize templates and README pass `*.dcm` globs and `> file` r |
| D224 | DICOMKit | CLI | ✅ | 2026-10-01 | `c4808d1c` | slice Image Position (Patient) is `originX\originY\originZ + i·spacingZ` from a `J2KVolume |
| D225 | dicom-report | CLI | ✅ | 2026-10-01 | `4739989f` | WAVEFORM items print `channelNumbers` only; the Multiplex Group of each (M,C) pair (now in |
| D226 | DICOMKit | CLI | ✅ | 2026-10-01 | `ada8def3` | MPEG2 MP@HL (1.2.840.10008.1.2.4.101) constraints of 8.2.6 not checked: "Rows (0028,0010)  |
| D227 | DICOMKit | CLI | ✅ | 2026-10-01 | `ada8def3` | MPEG-2 Program Stream (pack header 00 00 01 BA) and PES input are not recognised (`.unknow |
| D228 | DICOMWeb | CLI | ✅ | 2026-10-01 | `f4262b4f` | `retrieveWorkitemResult(uid:)` failed ("Failed to parse workitem JSON") on a conforming Re |
| D229 | DICOMKit | CLI | ✅ | 2026-10-01 | `23e8227d` | STUDY records never carry Study ID (0020,0010) (Type 1) or Accession Number (0008,0050) (T |
| D230 | DICOMKit | CLI | ✅ | 2026-10-01 | `23e8227d` | Every instance gets an IMAGE record whatever its SOP Class. SR, KOS, presentation states,  |
| D231 | DICOMKit | CLI | ✅ | 2026-10-01 | `23e8227d` | Writes File-set Consistency Flag FFFFH when `isConsistent == false`; 2026a defines only 00 |
| D232 | DICOMKit | CLI | ✅ | 2026-10-01 | `23e8227d` | Only IMAGE/PRESENTATION/SR DOCUMENT/WAVEFORM/RT DOSE/RT STRUCTURE SET/RT PLAN records are  |
| D233 | DICOMKit | CLI | ✅ | 2026-10-01 | `23e8227d` | Profile enforcement covers SOP Class + Transfer Syntax only. The per-profile image attribu |
| D234 | DICOMCore | CLI | ✅ | 2026-10-01 | `3b7d09de` | `--codec jpeg2000` / `htj2k` (lossy intent on .91 / .203) with `--quality maximum` plans a |
| D235 | DICOMCore | CLI | ✅ | 2026-10-01 | `59936daf` | A defined-length SQ was returned with raw bytes and no Items; DICOMWriter re-encodes SQ fr |
| D236 | DICOMKit | CLI | ✅ | 2026-10-01 | `bb4f551a` | Without the Clean Structured Content Option, Content Sequence (0040,A730) Basic Profile "D |
| D237 | DICOMKit | CLI / STUDIO | ✅ | 2026-10-06 | `7a3aac80`, `88c271c6` | MPEG-PS / MPEG-PES are reported as `.elementaryStream` (named by `MPEG2SystemsLayer` / `co |
| D238 | DICOMKit | CLI | ✅ | 2026-10-01 | — | MPEG2 MP@HL frame rates of the 8.2.6 table (25, 30, 50, 60 Hz; 1080-line progressive only  |
| D239 | DICOMKit | CLI | ✅ | 2026-10-01 | `cd1cc509` | The per-profile "Additional DICOMDIR Keys" tables are not applied (only the STD-GEN Image  |
| D240 | DICOMKit | CLI | ✅ | 2026-10-01 | `59d43e1c` | The record tree is rebuilt from the order of the Directory Record Sequence, not from Offse |
| D241 | DICOMKit | CLI | ✅ | 2026-10-01 | `b0d55a65` | README examples still call `echo`, `exit 1` and `rm -rf`, which are not dicom-* tools (the |
| D242 | DICOMPrintKit | STUDIO | ✅ | 2026-10-06 | `f1ba662b`, `a169450e` | `filmDestinations` offers only MAGAZINE, PROCESSOR, BIN_1, BIN_2; the dicom-print CLI ther |
| D243 | DICOMKit | STUDIO | ✅ | 2026-10-06 | `15e74ebc`, `123b81a5` | The convenience renderers hand the header's Window Center/Width (modality units) to `Pixel |
| D244 | (none else) | STUDIO | — void | 2026-10-06 | — |  |
| D245 | DICOMKit | STUDIO | ✅ | 2026-10-06 | `005b5ec4` | The `.basic` legacy profile (dicom-anon `legacy-basic`, Studio "Basic" / "HIPAA Safe Harbo |
| D246 | (none in DICOMKit/DICOMCore from this pa | STUDIO | — void | 2026-10-06 | — |  |
| D247 | Scripts (orchestrator) | STUDIO | ✅ | 2026-10-06 | `4d26acec` | `by_name` keys CLI options by flag, so an option several subcommands declare (study --form |
| D248 | dicom-validate | STUDIO | ✅ | 2026-10-06 | `923c496e`, `2bd8e408` | CLI-local SOP Class → engine IOD name map copied by the Workshop (validateEngineNameBySOPC |
| D249 | dicom-archive | STUDIO | ✅ | 2026-10-06 | `2182f73d`, `2bd8e408` | CLI-local --study-date warning copied by the Workshop (checked); lift next to ArchiveMatch |
| D250 | dicom-uid | STUDIO | ✅ | 2026-10-06 | `aeab8202`, `2bd8e408` | CLI-local UIDRootRule texts copied by the Workshop (uidRootProblems; checked by diff_studi |
| D251 | dicom-export | STUDIO | ✅ | 2026-10-06 | `fbf25c1f`, `726957b5` | `bulk` exits 0 when files failed (only the summary line carries the count), unlike dicom-c |
| D252 | dicom-export | STUDIO | ✅ | 2026-10-06 | `be267a71`, `2bd8e408` | CLI-local CineFrameRate / ExportFrameSelection / BurnedInAnnotation / ExportApplyWindowDep |
| D253 | dicom-dcmdir | STUDIO | ✅ | 2026-10-06 | `6adbe40e`, `2bd8e408` | CLI-local; DICOMStudio carries a text-identical copy (WorkshopFileSetRules, equality check |
| D254 | DICOMWeb | STUDIO | ✅ | 2026-10-06 | `c9bad73e` | Marker still says the event-type strings / bare-name keys are "pending owner approval (P-E |
| D255 | dicom-wado / DICOMWeb | STUDIO | ✅ | 2026-10-06 | `f4b3bddd`, `64a2a74e` | The Change-State target rule and its refusal text are CLI-local; Studio now carries a seco |
| D256 | Package.swift | STUDIO | ⏳ | 2026-10-06 | — | `dicom-cloud` product is commented out ("Phase 1 scope") while Sources/dicom-cloud exists  |
| D257 | DICOMStudio (G1, ShellServerConfigHelper | STUDIO | ✅ | 2026-10-06 | `62b76e1e`, `490e18d3` | `dicomParameters(from:)` injects the server host as `--host`, but every DIMSE tool (dicom- |
| D258 | Scripts (orchestrator) | STUDIO | ✅ | 2026-10-06 | `4d26acec` | (a) by-flag collapse: `retrieve --format` (MetadataFormat json \/ xml) is compared with `u |
| D259 | DICOMStudio (naming) | STUDIO | ✅ | 2026-10-06 | `d49d23ac`, `64a2a74e` | DICOMWeb.UPSState cannot be named inside DICOMStudio (shadowed), so the UPS rules carry th |
| D260 | DICOMStudio (Services) | STUDIO | ✅ | 2026-10-06 | — | makeConfiguration has no timeouts parameter, so the Workshop rebuilds the DICOMwebConfigur |
| D261 | dicom-send | STUDIO | ✅ | 2026-10-06 | `cf4667c7`, `04aa31ea`, `e4a73d9a` | CLI-local outcome classes and texts copied by the Workshop (checked); `NetworkConsole.send |
| D262 | dicom-retrieve / dicom-qr | STUDIO | ✅ | 2026-10-06 | `d7609891`, `e4a73d9a` | The two CLIs word the same non-success final response differently ("C-MOVE final response  |
| D263 | dicom-mpps | STUDIO | ✅ | 2026-10-06 | `d2812df4`, `e4a73d9a` | CLI-local value rules and warning wording copied by the Workshop (checked); lift into DICO |
| D264 | dicom-mwl | STUDIO | ✅ | 2026-10-06 | `29496ff0`, `e4a73d9a` | CLI-local scheduledProcedureStepStatusDefinedTerms / spsStatusWarning copied by the Worksh |
| D265 | dicom-wado | STUDIO | ✅ | 2026-10-06 | `87bbcbf8`, `64a2a74e` | CLI-local rules (contentType, frameNumber, parameter warnings, paging, UPS Change State re |
| D266 | Scripts (orchestrator) | STUDIO | ✅ | 2026-10-06 | `4d26acec` | a picker written `[""] + Expr` is read as the literal `[""]`, so dicom-video --type (an en |
| D267 | dicom-compress | STUDIO | ✅ | 2026-10-06 | `2bd8e408` | CLI-local native-target set and refusal texts mirrored by WorkshopNativeTargetSyntax; lift |
| D268 | dicom-convert | STUDIO | ✅ | 2026-10-06 | `b281e64f`, `2bd8e408` | CLI-local 7 Table A-1 keywords and the composed --transfer-syntax help mirrored by Worksho |
| D269 | dicom-video | STUDIO | ✅ | 2026-10-06 | `cc3c3675`, `2bd8e408` | CLI-local refusals and CID 3000 option grammar mirrored by WorkshopVideoOptionConformance  |
| D270 | dicom-pixedit | STUDIO | ✅ | 2026-10-06 | `4a756536`, `2bd8e408` | CLI-local P-PIXEDIT-RANGE refusals mirrored by WorkshopDerivedImage; lift next to PixelEdi |
| D271 | dicom-pdf | STUDIO | ✅ | 2026-10-06 | `15b06782`, `66bd8c42`, `726957b5` | a directory run exits 0 whatever the per-file outcomes; the Workshop mirrors it |
| D272 | dicom-pdf | STUDIO | ✅ | 2026-10-06 | `98e59069`, `2bd8e408` | CLI-local PDFEncapsulation ((0042,0015), ISO_IR 192, padding cut, option vocabularies); mi |
| D273 | dicom-image | STUDIO | ✅ | 2026-10-06 | `db10d0f3`, `726957b5` | a directory run exits 0 when files failed (only the summary carries the count), unlike dic |
| D274 | dicom-image | STUDIO | ✅ | 2026-10-06 | `46f4a61a`, `2bd8e408` | CLI-local P-IMAGE-VR refusals and finalize() ((0002,0003) = (0008,0018), ISO_IR 192); mirr |
| D275 | dicom-anon | STUDIO | ✅ | 2026-10-06 | `b711104e`, `2bd8e408` | CLI-local AnonCLI (profile aliases, notices, E.1-1a action report, (0002,0003) sync, valid |
| D276 | DICOMNetwork | NETWORK | ✅ | 2026-10-06 | `5de7575d` | The walker hard-coded the 10 VRs that take a 4-byte length (`["OB","OD","OF","OL","OW","SQ |
