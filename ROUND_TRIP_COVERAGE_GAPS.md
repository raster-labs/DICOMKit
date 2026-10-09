# Round-Trip Coverage Gaps — CLI Flag/Subcommand Audit

Cross-reference of every `dicom-*` CLI's **full flag/subcommand surface** against the
round-trip test coverage in `Tests/DICOMRoundTripTest/`. The former
`ROUND_TRIP_TEST_CASES.md` catalogue was **removed 2026‑07‑17** because it embedded
dump excerpts and hashed `PatientID`s from the real Tier‑2 corpus; the test files
themselves are now the catalogue.
Companion to [`ROUND_TRIP_TESTS_PLAN.md`](ROUND_TRIP_TESTS_PLAN.md).

## Method & what "covered" means

The round-trip tests drive the **DICOMKit library API** (`Anonymizer`, `FrameMerger`,
`DICOMConverter`, `CompressionManager`, `J2KEncoder`, …) — they never spawn the CLI
binary. A flag/option/subcommand/enumerated-value is **COVERED** when a test exercises
the library behavior that flag triggers; **MISSING** when no test exercises it.

Some CLI surface has **no library oracle by construction** — argv parsing, file-write
orchestration, `--verbose` stdout, file-existence guards. These are marked ⚪ and are
low priority (the behavior lives only in the CLI adapter, not the shared engine).

Priority legend:
- 🔴 **HIGH** — a distinct behavior with correctness risk: an untested codec / transfer
  syntax / output format / whole subcommand / query filter, or a known bug-fix path with
  no regression test. A silent shared bug here would pass parity **and** round-trip today.
- 🟡 **MED** — an enumerated value, alternate output format, or alternate mode where an
  oracle is straightforward to add.
- ⚪ **LOW** — verbose/logging, CLI-only arg parsing & error guards, or output-file write
  orchestration; no library oracle.

---

## ⚠️ Code issues surfaced by the audit (not just test gaps)

These are not "add a test" items — the audit found flags/commands that are **inert,
dead, unimplemented, or mis-advertised**. Worth fixing (or deleting) regardless of tests:

| Tool | Finding | Status (2026-07-04 remediation batch) |
|---|---|---|
| **dicom-json** | `--format {standard,dicomweb}` is **inert** — `convertDicomToJson`/`convertJsonToDicom` never read `format`; `dicomweb` does nothing. | ✅ **REMOVED** (flag deleted; output is always the DICOMweb PS3.18 JSON model) |
| **dicom-json** | `--stream` is **inert** — declared but never referenced in either conversion path. | ✅ **REMOVED** |
| **dicom-merge** | `--format {enhanced-ct,enhanced-mr,enhanced-xa}` is **inert** — `FrameMerger.createMultiFrameFile` never reads `format`; all four values produce byte-identical *standard* multi-frame output. The Enhanced multi-frame construction (functional groups, per-frame sequences) is **not implemented**. *(Found during this pass; `--level study` IS real and is now tested.)* | ✅ **IMPLEMENTED** 2026-09-01 — full Enhanced/Legacy-Converted construction via the shared `Multiframe/` engine (attribute-equality shared/per-frame factoring, Frame Content stacks, Multi-frame Dimension module, source-SOP-class gate, encapsulated pixel assembly); 18 oracles in `EnhancedMultiframeRoundTripTests` (see `ENHANCED_MULTIFRAME_SPLIT_MERGE_PLAN.md`) |
| **dicom-script** | `run --parallel` is **inert** — `ScriptExecutor.executePipeline`/`execute` run steps sequentially regardless ("parallel flag is accepted but treated the same"). A characterization test locks that `parallel:true` still runs every step. *(Found during this pass.)* | ✅ **IMPLEMENTED** (pipeline commands run concurrently with source-order output replay; 2 oracles added; top-level steps stay sequential by design) |
| **dicom-pdf** | `enum ExportFormat {pdf,xml,stl,obj,mtl,dicom}` is **dead code** — `ExpressibleByArgument` but bound to no `@Option`/`@Argument`. | ⏳ open (cosmetic dead code) |
| **dicom-dcmdir** | `update` subcommand is **unimplemented** — prints "not yet implemented", exits 1. `--add` does nothing. | ✅ **IMPLEMENTED** (`DICOMDIRWorkflow.updateDirectory`, both surfaces; 2 oracles added) |
| **dicom-j2k** | Top-level `discussion`/help advertises `benchmark … --backends all`, but `BenchmarkCommand` has **no `--backends` option**. Help text is wrong. | 🚫 HELD (dicom-j2k held by user triage 2026-07-04) |
| **dicom-dump** | `--offset` had a previously crash-prone slice-rebasing fix (comment: "crashes the 0-based dump loop whenever startOffset > 0") — now covered by a regression test (`testOffsetRebasesAndLabelsFromStartOffset`). | ✅ covered |

---

## Implementation status (coverage pass)

Round-trip suite after this pass: **`swift test --filter DICOMRoundTripTests` → 387 passed, 0 failed.**
**40 new oracle-based test cases** were added (excluding `dicom-convert` / `dicom-compress`,
which are under active development and were deliberately left for later).

Legend: ✅ covered this pass · ⚙️ inert flag / code issue (no behavioral oracle possible) ·
🚫 CLI-only (no shared-library entry point) · ⏳ deferred (lower value / ambiguous).

| Tool | Status of the flagged gaps |
|---|---|
| dicom-dump | ✅ `--offset` re-base regression; ✅ whole-file `--length` cap + footer |
| dicom-anon | ✅ `--profile clinical-trial` (now `legacy-clinical-trial`, deprecated; remove + shift variants); 🚫 `--recursive` (`anonymizeDirectory` is CLI-only); ⏳ `--dry-run`/`--backup`/`--output` (write-orchestration, no library oracle) |
| dicom-merge | ✅ `--level study`; ✅ `--sort-by ImagePositionPatient` (along the slice normal); ✅ `--sort-by AcquisitionTime`; ✅ `--format enhanced-*` / `legacy-converted-*` / `auto` / `sc-multiframe` / `us-multiframe`; ✅ `--make-stacks`; ✅ `--pixel-handling` |
| dicom-validate | ✅ level 1, ✅ level 4, ✅ level 5; 🚫 `--recursive` (`validateDirectory` CLI-only); ⏳ `--iod`/`--output`/`--force` |
| dicom-archive | ✅ query `--patient-id`/`--study-uid`/`--study-date`; ✅ export `--series-uid`/`--patient-id`; ✅ export `--flatten=false`; ⏳ default `table`/`tree`/`text` renderers, `import --recursive`, orphan detection |
| dicom-diff | ✅ `--format text` (default renderer); ✅ `--show-identical`; ⚙️ `--quick` (gating bypassed in helpers) |
| dicom-j2k | ✅ lossy transcode `--target j2k`; ✅ lossy `--target htj2k`; ✅ `reduce --layers`; ⏳ `validate --strict`, all `--json`, non-zero `--frame`, `completions` |
| dicom-measure | ✅ `roi --circle`; ✅ `--unit inches`; ⏳ `roi --polygon` (covered indirectly by shoelace + circle), `roi --histogram`, `hu --rect`, `--format json/csv` (formatters in the executable target, unimportable) |
| dicom-script | ⚙️ `--parallel` (inert — characterization test added); ✅ `--log` |
| dicom-pixedit | ✅ non-zero `--fill-value` |
| dicom-split | ✅ `--format jpeg`/`tiff`; ✅ `--apply-window`; 🚫 `--recursive` (true-path directory descent), ⏳ `parseFrameRange` string |
| dicom-uid | ✅ generate `--type sop`; ✅ regenerate `--root`; ⏳ `--json` output (CLI serialization), `--export-map` file write |
| dicom-pdf | ✅ explicit `--modality`; ✅ supplied `--study-uid`/`--series-uid`; 🚫 `--recursive` batch; ⏳ `--show-metadata`; ⚙️ `ExportFormat` dead enum |
| dicom-study | ✅ check `--expected-instances`; ✅ compare `--format json`; ⏳ `check --report`, `--verbose` branches |
| dicom-dcmdir | ✅ profiles STD-GEN-DVD/USB; ✅ `--no-recursive`; ⏳ `--strict`, validate `--check-files`/`--detailed`; ⚙️ `update` subcommand unimplemented |
| dicom-image | ✅ `--modality` (+ default OT); ✅ `--study-description`/`--series-description`/`--series-number`; 🚫 `--recursive` (`convertDirectory` CLI-only) |
| dicom-export | ✅ bulk `--organize-by study`; ✅ contact-sheet `--labels`; ⏳ `--format tiff`, contact-sheet `--format jpeg`/`--apply-window`, animate `--scale`/`--loop-count`, bulk `--recursive` (CoreGraphics-integration paths) |
| dicom-json / dicom-xml | ⚙️ `--format`/`--stream` inert (json); ⏳ `--inline-threshold 0` boundary (CLI maps `0→nil`; library takes an Int — ambiguous, left as a note); ⏳ `--verbose` |
| dicom-info / dicom-tags | ⏳ `--force` (incidental), `--verbose` (no oracle) — both low value |
| dicom-compress / dicom-convert | ⏸️ **deferred by request** (under active codec/TS development) — codec-family and transfer-syntax breadth remain the largest open gaps |

The ⏳/🚫/⚙️ items are intentionally not converted into tests: 🚫 have no shared-library
entry point (they live only in the CLI adapter), ⚙️ are inert/dead and need a code fix rather
than a test, and ⏳ are lower-value, ambiguous, or need the executable-target engine.

---

## Per-tool gaps

### dicom-pixedit
- 🟡 `--fill-value` (non-zero) — mask tests always use `fillValue: 0`, which is also the default; a custom fill value is never distinguished.
- ⚪ `--verbose`; CLI guards ("no operations specified", "--apply-window requires both center+width", file-not-found).

### dicom-anon
- 🔴 `--profile clinical-trial` (now `legacy-clinical-trial`; since 2026-10-01 the default is `ps315`, the PS3.15 Basic Profile, and `basic` is its alias) — the `.clinicalTrial` profile (distinct tag-action set) is **never instantiated**.
- 🔴 `--recursive` — directory batch mode (`anonymizeDirectory`, per-file aggregation, required-flag validation) entirely untested.
- 🟡 `--profile research` (now `legacy-research`) — instantiated (cases 8–9) but assertions target custom `--remove`/`--replace`, not the research profile's own tag removals; its distinctive behavior is unasserted.
- 🟡 `--dry-run` / `--backup` / `--output` — write-orchestration branches (skip-write, `.backup` copy, output write) uncovered.
- ⚪ `--verbose`; CLI tag parser (`parseTag`/`tagFromKeyword` hex+keyword forms for `--remove`/`--replace`/`--keep`); `--force` only exercised as `force:true` on already-prefixed corpus files.

### dicom-tags
- ⚪ `--verbose` (true branch); `--output` default "overwrite input" resolution; CLI guards (`noOperationsSpecified`, file-not-found for input & `--copy-from`, `--tags` comma-split). All mutation flags (`--set`/`--delete`/`--delete-private`/`--copy-from`/`--tags`/`--dry-run`) are covered.

### dicom-info
- ⚪ `--force` — only exercised incidentally via `loadCorpus(force:true)` on prefixed files; the "no DICM prefix" scenario is untested. All three `--format` values, `--tag` (name+hex), `--show-private`, `--statistics` are covered.

### dicom-dump
- 🔴 `--offset` — offset parsing (`0x`-hex + decimal) and the slice-rebasing path (previously crash-prone, see code issues) are **completely untested**; every test passes `startOffset: 0` literally.
- 🟡 whole-file `--length` cap + truncation footer — only the *tag-dump* length path is covered; the whole-file default 64 KiB cap + "…showing first N of M" notice is untested.
- ⚪ `--verbose` covered; `--force` incidental only; CLI parse/error guards.

### dicom-json
- 🔴 `--format dicomweb` — untested **and inert** (see code issues).
- 🟡 `--stream` — untested **and inert** (see code issues).
- 🟡 `--inline-threshold 0` boundary (`0 → nil`, "always URIs") — only positive thresholds tested.
- ⚪ `--verbose`; CLI `parseTagString` (keyword+hex) for `--filter-tag` (tests pass a `Set<Tag>` directly).

### dicom-xml
- 🟡 `--inline-threshold 0` exact boundary — Swift test uses `8`, not the literal `0→nil` branch.
- ⚪ `--verbose`. (Best-covered of the serialization tools; every semantic flag has an oracle, incl. `--filter-tag` via the same `DataElementDictionary.lookup` the CLI uses.)

### dicom-diff
- 🔴 `--format text` — the CLI's **default output format** has no Swift renderer test; only `.json`/`.summary` are rendered. (Cases whose doc repro shows `--format text` assert on the result object, not the text renderer.)
- 🟡 `--quick` — the `comparePixels && !quick` gating is bypassed; the quick-suppresses-pixels path is never taken.
- 🟡 `--show-identical` — helper hardcodes `showIdentical: false`; the identical-tag display path is untested.
- ⚪ `--verbose`; CLI `parseTag` for `--ignore-tag`; the `throw ExitCode(1)` wrapper.

### dicom-validate
- 🔴 `--level 4` (best practices) and `--level 5` (J2K codestream) — both rule tiers **entirely unexercised**.
- 🔴 `--recursive` — `validateDirectory` (enumeration, per-file capture, "directory requires --recursive" guard) never invoked.
- 🟡 `--level 1` (format) — `testHigherLevelIsAtLeastAsStrict` compares only levels 2 vs 3.
- 🟡 `--iod` — helper always passes `iod: nil`; IOD-specific validation never triggered.
- 🟡 level-range validation (`1…5` else error).
- ⚪ `--output` (file write path); `--force`; `--detailed` is exercised but its oracle is weak (assertions also hold with `detailed:false`).

### dicom-merge
- 🔴 `--format enhanced-ct` / `enhanced-mr` / `enhanced-xa` — the **entire Enhanced multi-frame construction path** (functional groups, per-frame sequences) is untested; every test hard-codes `.standard`. Largest gap for this tool.
- 🔴 `--level study` — `mergeByStudy(...)` has no test (only `.file` and `.series`).
- 🟡 `--sort-by ImagePositionPatient` (spatial ordering); `--sort-by AcquisitionTime` (temporal ordering) — both untested.
- ⚪ `--recursive` (`gatherInputFiles`/`isDICOMFile`); `--verbose`.

### dicom-split
- 🟡 `--format jpeg` / `--format tiff` — only `.png` among image formats is exercised.
- 🟡 `--apply-window` / `--window-center` / `--window-width` — always off/`nil`; the entire windowed image-export render branch is never taken.
- ⚪ `--recursive` (true path — `processDirectory(recursive:true)` subdirectory descent); `--verbose`; CLI `parseFrameRange` (`"1,3,5-10"` expansion + errors — tests pass a `Set<Int>` directly).

### dicom-dcmdir
- 🔴 `update` subcommand — **unimplemented stub** (see code issues); `--add` untested because it does nothing.
- 🟡 create `--profile STD-GEN-DVD` / `STD-GEN-USB` — only `.standardGeneralCD` is ever built.
- 🟡 create `--no-recursive` (recursive=false scan); create `--strict` (valid-DICOM-only filter) — both untested.
- 🟡 validate `--check-files` (referenced-file-existence) — always `checkFileExistence: false`.
- 🟡 validate `--detailed` — `renderValidationReport(...)` never called (tests invoke `directory.validate` directly).
- ⚪ create/`--verbose`; CLI `resolvedDICOMDIRPath` + profile-string parsing.

### dicom-uid
- 🟡 generate `--type sop` — in the allow-list but never generated.
- 🟡 `--json` — output serialization untested across `generate` / `validate` / `lookup` (tests inspect structs directly).
- 🟡 regenerate `--root` — all regenerate tests pass `root: nil`.
- 🟡 regenerate `--export-map` — the mapping-file JSON write is CLI-only; the in-memory dict is asserted but not the file write.
- ⚪ regenerate `--verbose`; generate count-range (1–1000) validation; invalid-`--type`-filter error. (`--check-registry` is effectively covered — `registryName` is always computed.)

### dicom-pdf
- 🟡 `--modality` (explicit override) — only the default DOC/M3D path is tested; the custom-modality branch never exercised.
- 🟡 `--study-uid` / `--series-uid` (explicit override + auto-generate fallback) — neither the supplied value round-tripping nor the `?? generateUID()` branch is asserted.
- 🟡 `--recursive` — `extractFromDirectory`/`encapsulateFromDirectory` (batch, instance-number auto-increment, shared UIDs, counts) entirely CLI-only.
- 🟡 `--show-metadata` — `metadataReport()` rendering never invoked.
- ⚪ `--extract` disk plumbing (auto filename, write to disk); `--output` path resolution; `--verbose`; required-metadata guards. `ExportFormat` enum is dead code.

### dicom-archive
- 🔴 query `--patient-id`, `--study-uid`, `--study-date` — three **query filters never exercised** (always `nil`); silent-wrong-result risk. (`export --study-uid` is a separate code path and does not cover query filtering.)
- 🔴 export `--series-uid`, `--patient-id` — series-/patient-level export filters never run.
- 🟡 export `--flatten=false` — the hierarchical (non-flatten) export layout is never actually written (the one `flatten:false` call throws before writing).
- 🟡 import `--recursive` — directory-tree recursive discovery untested.
- 🟡 default renderers with no oracle — query `table`(default)/`text`, list `tree`(default)/`table`, stats `text`(default). Only the `json` variants are asserted.
- 🟡 check orphan-file / size-mismatch detection — only missing + unreadable are covered.
- ⚪ import/export `--verbose`; `list --show-instances=false` default.

### dicom-export
- 🟡 `--format tiff` (single + bulk) — the `tiff` value is never exported; only png/jpeg.
- 🟡 contact-sheet `--format jpeg` — contact sheet only ever written as PNG.
- 🟡 contact-sheet `--labels` — `includeLabels:false` always; the label-height branch + filename drawing untested.
- 🟡 contact-sheet `--apply-window` — the sheet-specific stored-window-vs-plain branch never taken.
- 🟡 animate `--loop-count` — always default `0`; non-infinite loop untested.
- 🟡 animate `--scale` — the 0.1–2.0 clamp + CGContext resample path untested.
- 🟡 bulk `--organize-by study` — only flat/patient/series among the `buildOrganizedPath` cases.
- 🟡 bulk `--recursive` — the recursive directory-walk branch never exercised.
- ⚪ bulk `--verbose`; `--quality` for PNG paths (inert, lossless); single `--frame` out-of-range guard.

### dicom-image
- 🟡 `--modality` — neither the "OT" default nor a custom modality is asserted.
- 🟡 `--study-description` / `--series-description` / `--series-number` — never set by the test's `makeMetadata`; no assertion on their tags.
- 🟡 `--recursive` — `convertDirectory` walk never driven (the "batch" test loops `secondaryCaptureData` directly).
- ⚪ `--verbose`; required-arg guards; `--output` path selection.

### dicom-j2k
- 🔴 transcode `--target j2k` (lossy …4.91), `--target htj2k` (lossy …4.204) — both lossy transcode branches never exercised.
- 🟡 transcode `--target htj2k-rpcl` (…4.203) — not covered distinctly (only `htj2k-lossless` …4.202).
- 🟡 transcode `--quality` — only meaningful for lossy; never exercised since no lossy transcode is tested.
- 🟡 reduce `--layers` (`qualityLayers`) — test sets only `decompositionLevels`.
- 🟡 validate `--strict` — the strict branch (interop warnings → failure) untested; also `validateCapabilitySignaling` never called.
- 🟡 `--json` on `info` / `validate` / `benchmark` / `compare` — all four JSON branches untested.
- 🟡 `--frame` (non-zero) on info/validate/roi/benchmark/compare — all default to frame 0.
- ⚪ `completions` subcommand (bash/zsh/fish); `--verbose`. (Note: CLI DICOM-rewrap details — `roi` crop tag rewrite, `transcode` FMI UID rewrite — are library-untested; only codec-config semantics are covered.)

### dicom-measure
- 🔴 roi `--circle` — circular ROI collection (r² membership) **completely untested**.
- 🟡 roi `--polygon` — the per-pixel polygon ROI path (`isPointInPolygon` ray-casting in `collectROIValues`) is untested (area tests use the shoelace formula only).
- 🟡 roi `--histogram` + `--bins` — `generateHistogram`/bin logic + 2–65536 validation untested.
- 🟡 hu `--rect` (+ `--statistics`) — the HU ROI-averaging branch untested; only point-sample HU covered.
- 🟡 `--unit inches` — the ÷25.4 (distance) and ÷25.4² (area) conversions never exercised.
- 🟡 `--format json` / `--format csv` — no oracle at all (formatters live in the executable target, unimportable); even `--format text` output is not asserted, only the numeric values.
- ⚪ `--force`; `--output` (writeOutput file path); `--verbose`; subcommand `validate()` guards.

### dicom-script
- 🔴 run `--parallel` — the parallel-execution scheduling path is **completely untested** (every test passes `parallel:false`).
- 🟡 run `--log` — log-file creation/writing never exercised (`logPath:nil` always).
- ⚪ run/validate `--verbose`; CLI `parseVariables` KEY=VALUE parsing + `invalidVariable`; `scriptNotFound` guard.

### dicom-study
- 🟡 check `--expected-instances` — the expected-instances-per-series check untested (`expectedInstances:nil` always).
- 🟡 compare `--format json` — the JSON comparison renderer (advertised in the tool's own discussion) has no oracle; all compare coverage uses `text`.
- ⚪ check `--report` file write; `check`/`compare`/`organize` `--verbose`; adapter `directoryNotFound`/`noFilesFound` guards.

### dicom-compress
- 🔴 **~14 codec families untested** — of 19 `codecMap` entries, only 5 are exercised (`jpeg-baseline`, `jpeg2000`, `jpeg2000-lossless`, `jpeg-ls-lossless`, `rle`). Untested: `jpeg-ls`/near-lossless (…4.81), `jpeg-extended` (…4.51), `jpeg-lossless` (…4.57), `jpeg-lossless-sv1` (…4.70), `j2k-part2` / `j2k-part2-lossless` (…4.201/.202), the entire `htj2k` family, the `jpeg-xl` family (…4.110/.112), and `deflate`/`explicit-le`/`implicit-le` as compress targets. *(See parity-matrix memo: some lossy codecs are intentionally local-only in CI — but the codec's own encode path still deserves a local oracle.)*
- 🔴 recompression path — compressing an already-compressed file to a **different** codec (`isRecompression` decode-then-reencode) is untested; tests only compress uncompressed sources.
- 🟡 `--quality high|medium|low|<numeric>` — only `.maximum` is exercised (the `parseQuality` string path + presets untested).
- 🟡 `--backend metal|accelerate|scalar|auto` — backend selection never constructed.
- 🟡 `backends` subcommand (+`--json`); `info --json` — output branches untested.
- 🟡 batch `--recursive`, `--quality`, `--syntax implicit-le` — batch tests use non-recursive + defaults.
- ⚪ `--verbose`.

### dicom-convert
- 🔴 **~13 transfer-syntax targets untested** — of 20 `DICOMConverter.targets`, only 7 are exercised (`ExplicitVRLittleEndian`, `ImplicitVRLittleEndian`, `DEFLATE`, `RLELossless`, `JPEGBaseline`, `JPEG2000Lossless`, `JPEGXLRecompression`). Untested: `ExplicitVRBigEndian`, `JPEGExtended`, `JPEGLossless`, `JPEGLosslessSV1`, `JPEG2000` (lossy), `JPEG2000Part2Lossless`/`Part2`, `HTJ2KLossless`/`HTJ2KRPCLLossless`/`HTJ2K`, `JPEGLSLossless`, `JPEGLSNearLossless`, `JPEGXLLossless`.
- 🟡 `--format jpeg` (+ `--quality`) and `--format tiff` — only `dicom`+`png` covered; even for PNG the file-encode step (`exportCGImage`) isn't driven (tests inspect the `CGImage` from `renderFrameForExport`).
- 🟡 `--frame` (non-zero) — multi-frame export selection untested (`frameIndex:0` always).
- ⚪ `--recursive` (directory convert); `--validate` (re-read guard branch); `--force`.

---

## Summary — highest-value additions (🔴)

| Tool | 🔴 Gap |
|---|---|
| dicom-compress | ~14 untested codec families + recompression path |
| dicom-convert | ~13 untested transfer-syntax targets |
| dicom-merge | Enhanced-CT/MR/XA construction; `--level study` |
| dicom-validate | levels 4 & 5; `--recursive` |
| dicom-archive | query `--patient-id`/`--study-uid`/`--study-date`; export `--series-uid`/`--patient-id` |
| dicom-diff | `--format text` (default renderer) |
| dicom-j2k | lossy transcode targets (`j2k`, `htj2k`) |
| dicom-measure | roi `--circle` |
| dicom-script | run `--parallel` |
| dicom-dump | `--offset` (known crash-fix path, no regression test) |
| dicom-anon | `--profile legacy-clinical-trial` (was `clinical-trial`); `--recursive` |
| dicom-dcmdir | `update` subcommand (unimplemented) |
