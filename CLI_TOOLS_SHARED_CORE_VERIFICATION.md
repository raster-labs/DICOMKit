# CLI Tools — Shared-Core Three-Axis Verification

**Date:** 2026-07-04 · **Method:** 7 parallel read-only audit agents, every tool traced flag-by-flag in current working-tree code (not docs) · **Scope: all 40 `dicom-*` executables.**

> **Addendum (2026-09-11):** `dicom-video` did not exist at the time of this audit and was
> added to the tables below as a 41st tool, verified on the same three axes. It is the first
> tool built shared-first rather than remediated: `VideoWorkflow` + `VideoConsole` were written
> as the engine, and both adapters were thinned onto them from the start. Every other number,
> grade and finding on this page is the 2026-07-04 snapshot and has **not** been re-verified.

> **REMEDIATION STATUS (2026-07-04): batch complete for all non-held tools — see
> [Remediation outcomes](#remediation-outcomes-2026-07-04) at the end of this document.**
> User triage: 11 tools HELD (measure, viewer, 3d, ai, report, gateway, cloud, server,
> j2k, jpip, print — no work), network port/hostname workflow untouched as planned.

This audit answers three questions per tool:

| Axis | Question |
|---|---|
| **A1 — Core** | Is every subcommand/flag's logic implemented in a shared library (DICOMKit / DICOMCore / DICOMNetwork / DICOMWeb / DICOMDictionary), or does it live only in the executable target / `main.swift`? |
| **A2 — Surface** | Are all subcommands and flags available in **both** the app (CLI Workshop) and the CLI? |
| **A3 — Shared use** | Do app and CLI call the **same shared API** for all three stages: input resolution → processing → output/console formatting? |

**Relationship to prior work:** the 49-defect command-construction register in
`APP_CLI_PARITY_VERIFICATION.md` is fully remediated (54/54 items, in-tree). Everything below is
**new** — re-verified against the current tree, including the tools that audit never covered
(the 11 CLIs outside the Workshop) and the axis it never asked about (is the logic in the
shared core at all?).

---

## Executive summary

**The parity problem has moved.** Argument construction (the old audit) is fixed; the surviving
divergence risk is concentrated in two structural gaps:

1. **11 tools keep their engines in the executable target** — unreachable by the app, the
   library, or the tests. For four of them the app ships a **stub** that pretends to do the work
   (gateway even displays a command that doesn't exist).
2. **Output/console formatting is the least-shared stage.** Processing is shared almost
   everywhere it can be, but ~15 tools hand-duplicate their console text on both sides, and two
   have **already drifted** (dicom-validate, dicom-tags).

Grade distribution (A=fully shared+full surface · B=shared engine, duplicated edges ·
C=architecture gap / absent from app / stub / disabled):

| Grade | Tools |
|---|---|
| 🟢 **A** (9) | info, diff, split, study, archive, dcmdir, script, echo, send |
| 🟡 **B** (17) | dump, tags, xml, anon, uid, pixedit, merge, validate, image, export, convert, compress, pdf, query, retrieve, qr, mwl, mpps*, wado* |
| 🔴 **C** (12) | json, measure, viewer, 3d, ai, j2k, jpip, report, print†, server†, gateway, cloud† |

\* mwl/mpps/wado are B on shared use, with one real divergence each (see D-register).
† print/server/cloud targets are **commented out of Package.swift** — they don't even build.

---

## Master status table (40 tools + `dicom-video`, added 2026-09-11)

Legend — A1: ✅ shared · ◐ engine shared, edges inline · ❌ executable-local.
A2: ✅ full parity · ◐ partial · ❌ absent from app · 🧩 app stub.
A3 (input/process/output): ✅ same API · ◐ partly · ❌ duplicated/divergent.
RT: round-trip suite exists in `Tests/DICOMRoundTripTest/`.

| Tool | A1 core | A2 surface | A3 in/proc/out | RT | Verdict |
|---|:-:|:-:|:-:|:-:|---|
| dicom-info | ✅ MetadataPresenter | ✅ | ✅/✅/✅ | ✅ | 🟢 cleanest read tool |
| dicom-dump | ◐ HexDumper; offset/length+parseTag inline | ✅ | ◐/✅/◐ | ✅ | 🟡 `--no-color` dead in-app (N6) |
| dicom-tags | ◐ TagEditor+OutputPathResolver; summary inline | ✅ | ✅/✅/❌ | ✅ | 🟡 console text drifted (D2) |
| dicom-diff | ✅ DICOMComparer+ComparisonReport | ✅ (tolerance narrowed to Int) | ✅/✅/✅ | ✅ | 🟢 |
| dicom-json | ❌ only encoder/decoder primitives shared | ✅ | ❌/✅/❌ | ✅ prim. | 🔴 no shared pipeline; behavior diverges (D4); `--format`/`--stream` inert (N5) |
| dicom-xml | ◐ same gap as json (no inert flags) | ✅ | ❌/✅/❌ | ✅ prim. | 🟡 no shared pipeline |
| dicom-anon | ◐ Anonymizer; summary+tag-parse+walk inline ×2 | ✅ | ❌/✅/❌ | ✅ | 🟡 fragile app exit code (D7) |
| dicom-uid | ◐ UIDManager; app re-inlines validateFileUIDs | ◐ regenerate single-file in-app (S2) | ◐/✅/◐ | ✅ | 🟡 shared API exists but unused (D9) |
| dicom-pixedit | ◐ PixelEditor; app re-inlines parseRegion | ✅ | ❌/✅/❌ | ✅ | 🟡 shared parseRegion unused (D9) |
| dicom-merge | ◐ FrameMerger; gatherInputFiles inline ×2 | ✅ | ❌/✅/◐ | ✅ | 🟡 `--format` inert (N2) |
| dicom-split | ✅ FrameSplitter incl. **shared processDirectory** | ✅ | ✅/✅/◐ | ✅ | 🟢 the model for dir-walks |
| dicom-validate | ◐ DICOMValidator; render forked in app | ✅ | ❌/✅/❌ | ✅ | 🟡 **real render drift** (D1) |
| dicom-image | ◐ ImageConverter; dispatch+console inline ×2 | ✅ | ❌/✅/❌ | ✅ | 🟡 `--use-exif` dead under `--split-pages` (N7) |
| dicom-video | ✅ VideoWorkflow + VideoConsole (whole body, incl. batch) | ✅ 4 subcommands, every flag | ✅/✅/✅ | ✅ | 🟢 shared-first; help strings shared too (added 2026-09-11) |
| dicom-export | ◐ DICOMImageExporter; CG/GIF glue inline ×2 | ✅ (+app dir-expansion) | ◐/✅/❌ | ✅ | 🟡 |
| dicom-measure | ❌ MeasurementEngine + formatters exe-local | ❌ not in Workshop | —/—/— | ⚠️ | 🔴 RT tests test a re-implementation, not the engine (E1) |
| dicom-viewer | ❌ TerminalRenderer exe-local | ❌ | —/—/— | ❌ | 🔴 (E2) |
| dicom-3d | ❌ recon exe-local; JP3D subset shared | ❌ | —/—/— | ❌ | 🔴 3 dead surfaces (N8) |
| dicom-ai | ❌ AIEngine/registry/formatters exe-local | 🧩 app stub emits command strings | —/—/— | ❌ | 🔴 3 inert flags (N9) |
| dicom-convert | ◐ DICOMConverter+DICOMImageExporter; console+walk inline ×2 | ✅ | ❌/✅/❌ | ✅ | 🟡 console diverges (D3); JXL alias split (D8) |
| dicom-compress | ◐ engine+most console shared; info/backends inline ×2 | ✅ | ◐/✅/◐ | ✅ | 🟡 app batch skips shared findDICOMFiles (D6); `--backend` inert (N4) |
| dicom-j2k | ❌ all 8 subcommands inline in main.swift | ❌ (J2K Test Bench ≠ parity) | —/—/— | ✅ prim. | 🔴 roi crop math untested hotspot (E9) |
| dicom-jpip | ◐ client/server in JPIP module; console inline | ❌ (viewer reuses client only) | —/✅/❌ | ❌ | 🔴 Workshop-absent |
| dicom-pdf | ◐ Workflow/Builder/Parser; walk+summaries inline ×2 | ✅ | ❌/✅/❌ | ✅ | 🟡 dead ExportFormat enum |
| dicom-report | ❌ ReportGenerator + all options exe-local | ❌ | —/—/— | ❌ | 🔴 `--format pdf` always throws (N10) |
| dicom-study | ✅ StudyOrganizer/Scanner/Report | ✅ | ✅/✅/✅ | ✅ | 🟢 exemplary |
| dicom-dcmdir | ✅ DICOMDIRWorkflow+DumpFormatter | ✅ | ✅/✅/✅ | ✅ | 🟢 `update` stub both sides (N14) |
| dicom-archive | ✅ ArchiveStore returns rendered strings | ✅ | ✅/✅/✅ | ✅ | 🟢 cleanest overall |
| dicom-script | ✅ ScriptExecutor/Validator/TemplateGenerator | ✅ (app runner intentionally throws) | ✅/✅/◐ | ✅ | 🟢 `--parallel` inert (N3) |
| dicom-echo | ✅ VerificationService+NetworkConsole | ✅ | ✅/✅/✅ | n/a | 🟢 |
| dicom-query | ✅ QueryService+ResultFormatter+NetworkConsole | ✅ | ✅/✅/✅ | n/a | 🟢 `--referring-physician` inert both sides (N1); ~230 dead app lines |
| dicom-retrieve | ◐ services shared; Part-10 wrap ×3, bulk re-inlined | ✅ (+app UID auto-resolve) | ✅/✅/◐ | n/a | 🟡 TS inert on C-MOVE (documented) |
| dicom-qr | ◐ services shared; own executors + 3rd key builder | ◐ `resume`/`--save-state` absent (S3) | ✅/✅/◐ | n/a | 🟡 |
| dicom-send | ✅ FileGatherer+StorageService+NetworkConsole | ✅ (TS omitted by policy) | ✅/✅/✅ | n/a | 🟢 the model network tool |
| dicom-mwl | ✅ query fully shared | ✅ (+app-only create) | ✅/✅/✅ | n/a | 🟢 create header bespoke |
| dicom-mpps | ✅ MPPSService+NetworkConsole | ✅ | ✅/✅/✅ | n/a | 🟢 D5 resolved (CLI forwards `studyInstanceUID: studyUid`) |
| dicom-wado | ◐ clients+4 formatters shared; UPS narration inline ×2 | ◐ `ups --create <json>`, qido `--verbose` absent (S4) | ✅/✅/◐ | n/a | 🟡 |
| dicom-print | ❌ **target disabled**; formatters+config inline | ❌ | —/—/— | n/a | 🔴 `--layout` inert (N12) |
| dicom-server | ❌ **target disabled**; PACS engine exe-local | ❌ | —/—/— | n/a | 🔴 `stop` is a no-op stub (N13) |
| dicom-gateway | ❌ converters exe-local | 🧩 stub; shows nonexistent `convert` cmd | —/—/— | n/a | 🔴 (D10) |
| dicom-cloud | ❌ **target disabled** (+aws dep disabled) | 🧩 stub; jobs never execute | —/—/— | n/a | 🔴 (D11) |

---

## New findings register

### D — Real cross-surface divergences (fix these first)

| # | Sev | Tool | Finding | Anchors |
|---|:-:|---|---|---|
| D1 | 🔴 | dicom-validate | App renders via `ValidationHelpers.renderText` — a fork of shared `ValidationReport.renderText` that **appends an `Exit code: N (…)` block the CLI never prints**. Console not byte-identical; RT tests exercise the library type so cannot catch it. Exit code also computed inline in 3 places instead of shared `exitCode()`. | ValidationModel.swift:207,283-292 · ValidationReport.swift:49,34 · ValidationViewModel.swift:110-120 |
| D2 | 🟡 | dicom-tags | Console diverges: CLI non-verbose prints only `Output written to: <path>` and gates the `N change(s) applied.` line on verbose/dry-run; app always prints the count and says `Saved: <path>`. | dicom-tags/main.swift:101-120 · CLIWorkshopViewModel.swift:5771-5794 |
| D3 | 🟡 | dicom-convert | No shared console builder: CLI batch prints `Conversion complete:` vs app `Batch conversion complete:`; single-file output is entirely different text (one `Transcoded from…` line vs Read/Wrote/TS lines). Dir walk also duplicated with different enumeration. | DICOMConvert.swift:137,179 · CLIWorkshopViewModel.swift:5006,4852-4888 |
| D4 | 🟡 | dicom-json | Behavior diverges: CLI **always writes a file** (default `<input>.json`), never prints JSON; app prints to console when `--output` empty and refuses reverse w/o output. CLI verbose has per-stage timings; app has none. | dicom-json/main.swift:71-82 · CLIWorkshopViewModel.swift:1247-1306 |
| D5 | ✅ | dicom-mpps | `update`: CLI now forwards `studyInstanceUID: studyUid` and standalone `--series-uid` `PerformedSeries` items to `DICOMMPPSService.update`, matching `CLIWorkshopViewModel.executeDicomMpps`. | CLIWorkshopViewModel.swift · DICOMMPPSCommand.swift · MPPSService.swift |
| D6 | 🟡 | dicom-compress | `batch`: CLI discovers files via shared `CompressionManager.findDICOMFiles`; app re-implements discovery inline with a **different heuristic** (extension list + 132-byte DICM probe) and uses different per-file methods (`compressData` vs `compressFile`). | main.swift:438 · CompressionManager.swift:645 · CLIWorkshopViewModel.swift:3479-3512 |
| D7 | 🟡 | dicom-anon | App exit code derived from a string heuristic (`output.contains("Failed: 0")` … `contains("error")`); CLI uses the structured `results.success`. A failing run without the word "error" reports success in-app. | CLIWorkshopViewModel.swift:5355 · dicom-anon/main.swift:129 |
| D8 | 🟡 | convert⇄compress | **In-flight (uncommitted):** `jpeg-xl`/`jxl` now maps to **lossy** (.112) in CompressionManager but still **lossless** (.110) in DICOMConverter, whose doc comment stale-claims the maps match. Same token, opposite meaning across tools. | CompressionManager.swift:59-63 · DICOMConverter.swift:89 |
| D9 | 🟢 | uid, pixedit | Shared API exists but the app doesn't call it: `UIDManager.validateFileUIDs` re-inlined (VM:1593); `PixelEditor.parseRegion` re-implemented (VM:2472). Pure waste — one-line fixes. | UIDManager.swift:154 · PixelEditor.swift:65 |
| D10 | 🔴 | dicom-gateway | App "conversion" is fake: `convertHL7()/convertFHIR()` build a display string only, invoke no converter, and the string references a **nonexistent `dicom-gateway convert` subcommand**. | GatewayViewModel.swift:104-121 |
| D11 | 🟡 | dicom-cloud | App transfer actions enqueue an in-memory pending job with **no runner — jobs never execute**. `DICOMCloudTests` tests local stub copies of the types, not the real code. | CloudIntegrationViewModel.swift:96-148 |

### N — Inert flags / dead surfaces (need code fixes or removal, not tests)

| # | Tool | Surface | Why inert | Anchor |
|---|---|---|---|---|
| N1 | dicom-query | `--referring-physician` | Declared on **both** sides, never fed into `buildQueryKeys` or `appliedFilters` | DICOMQuery.swift:67 · CLIWorkshopHelpers.swift:462 |
| N2 | dicom-merge | `--format enhanced-ct/mr/xa` | `FrameMerger.format` stored, never read; help still advertises Enhanced functional groups | FrameMerger.swift:42,63 |
| N3 | dicom-script | `run --parallel` | Stored in `ScriptContext.parallel`; `executePipeline` sequential, never reads it | ScriptEngine.swift:220,286-293 |
| N4 | dicom-compress | `--backend` | Only feeds the verbose preamble label; `compressData` takes no backend param | main.swift:106 · CompressionManager.swift:325 |
| N5 | dicom-json | `--format`, `--stream` | Declared, never read (both sides; app help admits "no effect") | dicom-json/main.swift:40-53 |
| N6 | dicom-dump | `--no-color` (app) | Toggle exposed, executor hardcodes `useColor:false` | CLIWorkshopViewModel.swift:5567-5637 |
| N7 | dicom-image | `--use-exif` under `--split-pages` | Both sides hardcode `useExif:false` on the TIFF-split path | main.swift:307 · VM:4098 |
| N8 | dicom-3d | `volume` subcmd; `mpr --format`; `mpr --planes oblique` | volume = "not yet implemented" throw; format declared, run() hardcodes .png; oblique validated then `default: continue` | main.swift:488,71/170,99/145 |
| N9 | dicom-ai | `--profile`, `--profile-output`, `--batch-size` | First two never read (PerformanceMetrics.swift orphaned); batch-size only in a verbose print | main.swift:70-73,428/451 |
| N10 | dicom-report | `--format pdf` | `generatePDFReport()` unconditionally throws `pdfNotImplemented` | ReportGenerator.swift:1099-1100 |
| N11 | dicom-measure | `--unit` on `hu --rect` | Forced to `.pixels` | main.swift:322 |
| N12 | dicom-print | `--layout` | Echoed verbose-only; never reaches `PrintOptions` (no such init param) | main.swift:302,334-340 · PrintService.swift:495 |
| N13 | dicom-server | `stop` subcommand | Prints "send SIGINT" hint; `--port` unused | DICOMServer.swift:275-285 |
| N14 | dicom-dcmdir | `update` subcommand | Stub + ExitCode(1) on both sides; app still renders its dead fields | main.swift:266-276 · Helpers:2873-2884 |
| N15 | dicom-j2k | help text | Advertises `benchmark --backends all`; no such option exists | main.swift:43,829-839 |
| N16 | dicom-qido (app) | `timeout` field | Internal field never read by `executeDicomQIDO`; CLI query has no `--timeout` | CLIWorkshopHelpers.swift:1308 |

### E — Engines in executable targets (violates the shared-core rule; blocks app reuse AND real round-trip testing)

| # | Tool | What's trapped in the executable | Shared already |
|---|---|---|---|
| E1 | dicom-measure | `MeasurementEngine` + all formatters (`formatResult`/`formatROIResult`/`writeOutput`) | pixel access (DICOMKit) |
| E2 | dicom-viewer | `TerminalRenderer` + display-mode/normalize types | `DICOMJPIPClient` for `--jpip` |
| E3 | dicom-3d | `VolumeLoader`/`VolumeData`/`MPRGenerator`/`ProjectionRenderer`/`SurfaceExtractor`/`VolumeExport` | JP3D encode/decode/inspect (`JP3DVolumeDocument`, `JP3DCodec`, `CodecBackendProbe`) |
| E4 | dicom-ai | `AIEngine`/`AIDICOMOutputGenerator`/`ModelRegistry` + formatters | — |
| E5 | dicom-report | `ReportGenerator`/`ReportOptions`/`ReportLanguage`/`ReportTemplate`/`ReportFormat` | `SRDocumentParser` (DICOMKit) |
| E6 | dicom-gateway | `DICOMToHL7Converter`/`HL7ToDICOMConverter`/`HL7Parser`/`FHIRConverter`/`HL7Listener`/`DICOMForwarder` | — |
| E7 | dicom-cloud | all cloud logic (also unbuildable — aws-sdk dep disabled) | — |
| E8 | dicom-server | `PACSServer`/`ServerSession`/`DatabaseManager`/`StorageManager`/`ServerConfiguration` | echo probe (DICOMNetwork) |
| E9 | dicom-j2k | all 8 subcommands incl. DICOM re-wrap + **roi crop math** (untested hotspot) | J2KSwift primitives |
| E10 | dicom-jpip | console formatting; `formatBytes` dup; hardcoded TS table | `DICOMJPIPClient`/`JPIPServer`/`jpipURI` |
| E11 | dicom-print | all output formatters + `PrinterConfigManager` | `DICOMPrintService` (DICOMNetwork) |

### P — Duplicated pipelines (parity holds today only by hand-sync)

1. **json/xml orchestration** — whole read→filter→encode→write pipeline inline in both CLIs and both app executors; only codec primitives shared.
2. **Directory walks** re-inlined ×2 in anon, merge, validate, convert, image, pdf, export-bulk — while **split** (`FrameSplitter.processDirectory`) and **send** (`DICOMSendFileGatherer`) prove the shared pattern works.
3. **Console/summary strings** hand-duplicated: anon, pixedit, image, export, pdf, convert, compress(info/backends), uid, dcmdir(verbose header), qr(bulk/validate), ups(create/change-state), mwl(app-create header).
4. **Network plumbing**: host:port/`pacs://` parse duplicated in all 7 DIMSE CLIs + app; Part-10 wrapper written 3× (RetrieveExecutor, DICOMQR, app); dicom-qr re-declares its own QueryExecutor/RetrieveExecutor + a third `buildQueryKeys` variant.
5. **Small parsers** duplicated: dump offset/parseTag, split frames-range, diff ignore-tag, tags `--tags` split, json/xml filter-tag.

### S — Surface gaps (CLI capability unreachable from the app)

| # | Gap |
|---|---|
| S1 | 9 tools absent from the Workshop entirely: measure, viewer, 3d, ai, j2k, jpip, report, print, server (+ gateway/cloud present only as non-functional stub features) |
| S2 | `dicom-uid regenerate`: app is single-file; CLI variadic inputs + cross-file `--maintain-relationships` unreachable |
| S3 | `dicom-qr`: `resume` subcommand + `--save-state` absent in app |
| S4 | `dicom-wado`: `ups --create <json-file>` and qido `--verbose` absent in app |
| S5 | `dicom-send --transfer-syntax` absent in app — **intentional** (as-is policy, documented); not a defect |

---

## Recommended fix order

1. **D1/D2/D3 console drift** — hoist validate/tags/convert console rendering into the shared types (ValidationReport already exists; add `TagEditConsole`, `ConvertConsole`) and delete the forks. These are live terminal-compare DIFFERS risks.
2. **D5 + D6 + D7** — one-line/small executor fixes with wire or exit-code impact.
3. **D8 JXL alias** — pick one meaning for `jpeg-xl`/`jxl` across convert⇄compress (in-flight branch work; fix the stale DICOMConverter comment either way).
4. **D9** — call the shared APIs that already exist (uid, pixedit).
5. **N-register** — implement or remove each inert flag; N1 (query filter silently dropped) first since it silently changes result sets.
6. **E-register (strategic)** — extract engines to shared targets in this order of leverage: E1 measure (unblocks real RT tests that currently test a re-implementation), E9 j2k (roi math untested), E5 report, E3 3d recon. Gateway/cloud/server/print only when those features are re-scoped.
7. **P-register** — adopt the split/send pattern: one shared file-gatherer + one shared console builder per tool family.

## Cross-cutting confirmations (things that are RIGHT)

- The 49-defect register from `APP_CLI_PARITY_VERIFICATION.md` stays fixed — no regressions found.
- DIMSE `--port` systemic class: resolved; single `resolveHostPort`, correct port reaches every service.
- Canonical SOP list single-sourced (`StorageSOPClass.allUIDs` → RetrieveService, StorageSCP).
- `dicom-send` as-is invariant holds on both sides (no transcode anywhere).
- `NetworkConsole` (728 lines) is genuinely both-sides for echo/query/retrieve/qr/send/mwl/mpps chrome.
- Processing engines are shared for **all 23 Workshop file tools** — no tool computes different bytes in app vs CLI (the D-register is about console text, discovery, and one N-SET field).

---

## Remediation outcomes (2026-07-04)

**User triage:** hold measure/viewer/3d/ai/report/gateway/cloud/server/j2k/jpip/print (all E-register
extraction work + their D/N/S items) · never touch the network port/hostname workflow (kills the
P4 host:port consolidation) · fix everything else.

### D — divergences

| # | Outcome |
|---|---|
| D1 | **FIXED** — app validate renders via shared `ValidationReport.render` + `exitCode()`; the drifted `ValidationHelpers.renderText/renderJSON` copies (with the app-only `Exit code:` block) deleted |
| D2 | **FIXED** — new shared `TagEditConsole` (TagEditor.swift) owns the changes block + completion line; CLI and app both call it (`Output written to:`, count line gated on verbose/dry-run) |
| D3 | **FIXED** — new shared `ConvertConsole` (DICOMKit/ConvertConsole.swift): CLI text canonical; app dropped its Read/Wrote/Transfer-Syntax/JPEG-quality/validation chrome and the "Batch conversion complete" wording |
| D4 | **FIXED** — new shared `DataExchangeWorkflow` (DICOMWeb) owns the whole json/xml pipeline (default output path, always-write-file, filter/metadata-only, verbose lines); both CLIs and both app executors call it |
| D5 | **FIXED** — app mpps update no longer forwards `studyInstanceUID` (CLI truth: study/series UIDs flow only into Referenced SOP Sequence) |
| D6 | **FIXED** — app compress batch discovers via shared `CompressionManager.findDICOMFiles` |
| D7 | **FIXED** — `SecurityViewModel.anonLastExitCode` (structured, CLI rule: any failed file → 1) replaces the output-string sniff |
| D8 | **PARTIAL (by design)** — the token-meaning decision (lossy vs lossless) stays with the in-flight convert/compress branch; not resolved here. The stale DICOMConverter comment claim remains to be corrected with that work |
| D9 | **FIXED** — app calls shared `UIDManager.validateFileUIDs` and `PixelEditor.parseRegion` |
| D10/D11 | **HELD** (gateway/cloud) |

### N — inert flags

| # | Outcome |
|---|---|
| N1 | **FIXED** — `--referring-physician` now a study-level matching key via shared `buildQueryKeys(referringPhysician:)` (+ new `QueryKeys.referringPhysicianName(_:)`); wired in CLI `appliedFilters` and app filters |
| N2 | **IMPLEMENTED** — `FrameMerger` enhanced-ct/mr/xa now set the Enhanced SOP Class (dataset + FMI) and emit Shared (PixelMeasures) + Per-frame (FrameContent, PlanePosition) functional groups; `MergeFormat.enhancedSOPClassUID` added; RT oracles added |
| N3 | **IMPLEMENTED** — `--parallel` runs a pipeline's commands concurrently (TaskGroup-free `concurrentPerform`, per-command output buffered and replayed in source order → byte-stable); top-level steps stay sequential (setVariable/conditional dependencies); RT oracles added |
| N4 | **IMPLEMENTED** — `CompressionConfiguration.forcedBackend` threads `--backend` through compressData/WithMetrics → `encodePixelDataInPlace` → codec config; `J2KSwiftCodec.encodeFrame` dispatches metal→`encodeGPU`; other codecs ignore it (documented); CLI + app pass their preference |
| N5 | **REMOVED** — dicom-json `--format`/`--stream` deleted from CLI, app fields, ToolRegistry, and Phase8 test (goldens proved byte-identical output; encoder always emits DICOMweb PS3.18 JSON; no streaming path exists) |
| N6 | **FIXED** — app dump honors the No Color toggle (`useColor: !noColor`), field defaults ON in-app so the default preview says `--no-color` (truthful + paste-identical) |
| N7 | **FIXED** — `--use-exif` honored per page under `--split-pages` on both sides (converter already read per-page EXIF at pageIndex) |
| N8–N13, N15 | **HELD** (3d/ai/report/measure/print/server/j2k) |
| N14 | **IMPLEMENTED** — `dcmdir update` real on both surfaces via shared `DICOMDIRWorkflow.updateDirectory` (parse → union with --add → deterministic rebuild, file-set ID/profile preserved, missing files dropped+counted) + `renderUpdateSummary`; RT oracles added. Caveat: `DICOMDIRReader` still parses profile as STD-GEN-CD (pre-existing) |
| N16 | **REMOVED** — the app-only qido timeout field (CLI query has no `--timeout`) |

### S — surface gaps

| # | Outcome |
|---|---|
| S2 | **FIXED** — app uid regenerate accepts multiple inputs (repeatable positional, shared splitMultiValue), mirrors the CLI loop: output-as-directory for multi-file, shared cross-file mapping (forced for multi-input like the CLI), per-file warnings, one exported map |
| S3 | **PARTIAL** — `--save-state` implemented in-app with a NEW shared state model (`DICOMNetwork/QRSessionState.swift`: QRQueryState/QRRetrievalState/QRStudyInfo + canonical encoding) that the CLI now also uses — an app-saved state resumes via terminal `dicom-qr resume`. **In-app `resume` mode deferred**: it would need compound field-visibility conditions across ~20 required qr fields (a Workshop UI-framework change, not parity wiring) |
| S4 | **FIXED** — ups `create-json` operation (app) calls `client.createWorkitem(workitem:)` with the CLI's exact `printCreateResponse` text; qido `--verbose` field added and wired (header + "Found N …" lines) |
| S5 | unchanged (intentional) |

### P — duplication (drift-risk refactors)

P1 **DONE** (DataExchangeWorkflow). P5 **PARTIAL** (json/xml filter-tag via shared
`resolveFilterTags`; pixedit region parse + uid file-UID gather now shared calls). P4 **SKIPPED**
(user hold on port/hostname workflow).

**P2 DONE (2026-07-04 follow-up batch)** — one shared walk per family, both surfaces:
- New `FileGatherer.regularFiles(under:recursive:)` (DICOMKit/FileGathering.swift): sorted,
  hidden-files-skipped, content-agnostic walk adopted by anon, validate, convert, pdf (both
  walks), export bulk/contact-sheet, and image (with the image-file filter kept in the loop so
  verbose `⊘` skip lines still appear). Sorting makes processing order — and therefore console
  output — deterministic on both surfaces (several scenarios were previously excluded from
  goldens as non-deterministic purely from filesystem enumeration order).
- `FrameMerger.gatherInputFiles(from:recursive:)` + `FrameMerger.isDICOMFile(_:)` hoisted from
  the dicom-merge CLI (multi-root, .dcm/.dicom/.dic + DICM-magic filter), now **sorted** — this
  also fixes a real CLI⇄app drift: the CLI merged in filesystem enumeration order while the app
  sorted, so merged instance order could differ between surfaces.

**P3 DONE (2026-07-04 follow-up batch)** — every remaining hand-duplicated console block now has
one shared builder both surfaces call:
- `AnonConsole` (+ `Anonymizer.parseFlexibleTag`) in Anonymizer.swift — summary block, per-file
  ✓/✗ lines, audit line; app-side `AnonHelpers.renderSummary` deleted. Drift fixed: the app's
  per-file verbose text ("Processing:", "✓ N tags modified") replaced by the CLI's directory-mode
  lines; single-file failures now propagate as fatal errors like the CLI; summary's
  "Modified tags" header now appears for verbose runs even with 0 tags (CLI truth).
- `PixelEditConsole` in PixelEditor.swift — header/Written/Done. Drift fixed: app's extra
  "Edited pixel data:" line, double "Image:" line, byte-size suffix on Written, and unconditional
  Done removed; non-verbose runs are silent like the CLI.
- `ImageConsole` (SecondaryCapture/ImageConsole.swift) — batch/single/TIFF headers, per-file and
  per-page lines, summaries.
- `ExportConsole` (ImageExport/DICOMImageExporter.swift) — Exported/contact-sheet/GIF lines,
  bulk skip/✓/✗/summary.
- `UIDConsole` (UIDManagement/UIDManager.swift) — generate list/JSON, validate ✅/❌ blocks +
  JSON, lookup entry/listing/summary + JSON, regenerate Warning/Processing/mapping/Wrote/
  map-exported/dry-run lines. Note: "Dry run complete — no files modified." is CLI **stderr**
  chrome; the parity contract is app console ≡ CLI stdout, so the app deliberately does not
  mirror it (the regenerated goldens pin this — an attempt to add it in-app was immediately
  flagged as 2× DIFFERS and reverted).
- `CompressionConsole.infoText/infoJSON/infoErrorLine/backendsText/backendsJSON` — the info and
  backends subcommand blocks. Drift fixed: info's read-error line now prints the raw error on
  both sides (the app printed localizedDescription).
- `NetworkConsole` qr additions (qrNoStudies/qrFound/qrReviewComplete/qrStateSaved/qrNoSelection/
  qrRetrieving/qrMissingStudyUID/qrValidatingHeader/qrValidate*) — the dicom-qr lines that were
  still inline on both sides.
- `UPSConsole` (DICOMWeb/UPSResultFormatter.swift) — create response block + change-state verbose
  header/result. Drift fixed: the app's create-workitem panel now prints the CLI's
  "Created worklist item:" block (was "✅ Workitem created successfully"), and change-state prints
  the CLI's "Successfully updated worklist item …" result (Transaction-UID caching is now silent
  bookkeeping). App-only interactive guidance (pre-flight state check, HTTP error hints, curl
  echo) is retained — it has no CLI counterpart.
- `NetworkConsole.mwlCreateDetailBlock` — the MWL-create scheduled-item block previously
  duplicated between the app's HL7 and REST branches (no CLI create exists; a future one uses
  the same builder).

Still tracked as follow-up (network plumbing, adjacent to the held port/hostname workflow):
qr's local QueryExecutor/RetrieveExecutor + third `buildQueryKeys` variant, and the Part-10
wrapper written 3× (RetrieveExecutor, DICOMQR, app).

### E — held tools

All E-register items untouched per user hold.
