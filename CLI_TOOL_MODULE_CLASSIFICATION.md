# CLI Tool Module Classification

## Purpose

This document classifies every currently available CLI executable in the
DICOMKit Swift package by:

- executable product name
- SwiftPM target name and source directory
- package module/library dependencies
- the primary module layer the tool belongs to
- how the same functionality is reached from a third-party application
- how it is reached from the terminal

This document is based on the executable products and executable targets
declared in `Package.swift`.

## Important Distinction

The `dicom-*` tools are **not** library modules. They are **executable products**
and **executable targets** built on top of the DICOMKit package libraries.

That means:

- a terminal reaches them by running the executable product
- a third-party application normally reaches the same functionality by importing
  one or more package libraries such as `DICOMKit`, `DICOMCore`,
  `DICOMDictionary`, `DICOMNetwork`, or `DICOMWeb`
- a third-party application does **not** import `dicom-info`, `dicom-validate`,
  or other executable targets directly

## Package Library Modules

The reusable library/API products currently exposed by the package are:

- `DICOMCore`
- `DICOMDictionary`
- `DICOMKit`
- `DICOMNetwork`
- `DICOMWeb`
- `DICOMToolbox`
- `DICOMStudio`

The end-user CLI tools sit in the executable layer above those libraries.

## Access Rules

### Third-Party Application Access

A third-party Swift application reaches tool functionality in one of two ways:

1. Import the underlying package libraries directly and call their public APIs.
2. Launch the compiled CLI executable as a subprocess if exact CLI behavior is needed.

### Terminal Access

The terminal reaches a tool by running its executable product, for example:

- `dicom-info`
- `dicom-validate`
- `dicom-diff`

From a source checkout this can also mean running the built binary directly,
for example from:

- `.build/debug/<tool>`
- `.build/release/<tool>`

## End-User CLI Tools

| Tool | Product / Target | Source Directory | Package Module Dependencies | External Package Dependencies | Primary Layer Classification | Third-Party Application Access | Terminal Access | Notes |
|---|---|---|---|---|---|---|---|---|
| `dicom-info` | executable product `dicom-info` / target `dicom-info` | `Sources/dicom-info` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `J2KCore`, `J2KCodec`, `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`, `DICOMCore`, `DICOMDictionary`; direct shared presenter exists via `MetadataPresenter` | Run `dicom-info` | Shared end-to-end presenter path exists in `DICOMKit.MetadataPresenter` |
| `dicom-convert` | `dicom-convert` / `dicom-convert` | `Sources/dicom-convert` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`, `DICOMCore`, `DICOMDictionary` | Run `dicom-convert` | Uses shared low-level transcoding APIs, but workflow is still executable-local |
| `dicom-validate` | `dicom-validate` / `dicom-validate` | `Sources/dicom-validate` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `J2KCore`, `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; full validation via shared `DICOMValidator` + `ValidationReport` | Run `dicom-validate` | ✅ Validation engine/report extracted to `DICOMKit` (`Sources/DICOMKit/Validation/`); CLI + DICOMStudio now share them (2026-06-08) |
| `dicom-anon` | `dicom-anon` / `dicom-anon` | `Sources/dicom-anon` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; anonymize via shared `Anonymizer` (+ `AnonymizationProfile`/`Action`/`Result`) | Run `dicom-anon` | ✅ `Anonymizer` engine extracted to `DICOMKit` (`Sources/DICOMKit/Anonymization/`); CLI + DICOMStudio now share it, F19 (`--remove`/`--replace` any tag) reconciled in the engine (2026-06-08) |
| `dicom-dump` | `dicom-dump` / `dicom-dump` | `Sources/dicom-dump` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries; direct shared dumper exists via `HexDumper` | Run `dicom-dump` | Shared end-to-end dumper path exists in `DICOMKit.HexDumper` |
| `dicom-query` | `dicom-query` / `dicom-query` | `Sources/dicom-query` | `DICOMCore`, `DICOMNetwork` | `ArgumentParser` | CLI adapter over network libraries | Import `DICOMCore`, `DICOMNetwork` | Run `dicom-query` | DIMSE query workflow |
| `dicom-send` | `dicom-send` / `dicom-send` | `Sources/dicom-send` | `DICOMCore`, `DICOMNetwork` | `ArgumentParser` | CLI adapter over network libraries | Import `DICOMCore`, `DICOMNetwork` | Run `dicom-send` | DIMSE send/store workflow |
| `dicom-diff` | `dicom-diff` / `dicom-diff` | `Sources/dicom-diff` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; full comparison via shared `DICOMComparer` + `ComparisonReport` | Run `dicom-diff` | ✅ `DICOMComparer` + result types + `ComparisonReport` renderer extracted to `DICOMKit` (`Sources/DICOMKit/Comparison/`); CLI + DICOMStudio now share them (2026-06-08) |
| `dicom-retrieve` | `dicom-retrieve` / `dicom-retrieve` | `Sources/dicom-retrieve` | `DICOMCore`, `DICOMNetwork` | `ArgumentParser` | CLI adapter over network libraries | Import `DICOMCore`, `DICOMNetwork` | Run `dicom-retrieve` | DIMSE retrieve workflow |
| `dicom-split` | `dicom-split` / `dicom-split` | `Sources/dicom-split` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; split via shared `FrameSplitter` | Run `dicom-split` | ✅ `FrameSplitter` engine (frame extract + image export) extracted to `DICOMKit` (`Sources/DICOMKit/Splitting/`); CLI + DICOMStudio share it (2026-06-08) |
| `dicom-merge` | `dicom-merge` / `dicom-merge` | `Sources/dicom-merge` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; merge via shared `FrameMerger` | Run `dicom-merge` | ✅ `FrameMerger` engine extracted to `DICOMKit` (`Sources/DICOMKit/Merging/`); CLI + DICOMStudio share it, deterministic sort, parity MATCHES (2026-06-08) |
| `dicom-json` | `dicom-json` / `dicom-json` | `Sources/dicom-json` | `DICOMKit`, `DICOMCore`, `DICOMWeb` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`, `DICOMCore`, `DICOMWeb`; direct encoders/decoders exist | Run `dicom-json` | Uses `DICOMJSONEncoder` / `DICOMJSONDecoder` |
| `dicom-xml` | `dicom-xml` / `dicom-xml` | `Sources/dicom-xml` | `DICOMKit`, `DICOMCore`, `DICOMWeb`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`, `DICOMCore`, `DICOMWeb`, `DICOMDictionary`; direct encoders/decoders exist | Run `dicom-xml` | Uses `DICOMXMLEncoder` / `DICOMXMLDecoder` |
| `dicom-pdf` | `dicom-pdf` / `dicom-pdf` | `Sources/dicom-pdf` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries | Run `dicom-pdf` | Encapsulation / extraction workflow |
| `dicom-image` | `dicom-image` / `dicom-image` | `Sources/dicom-image` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; convert via shared `ImageConverter` | Run `dicom-image` | ✅ Image→Secondary-Capture core extracted to `DICOMKit` (`Sources/DICOMKit/SecondaryCapture/ImageConverter.swift`); CLI + DICOMStudio share it, UID gen reconciled to `UIDGenerator` (2026-06-08) |
| `dicom-dcmdir` | `dicom-dcmdir` / `dicom-dcmdir` | `Sources/dicom-dcmdir` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries | Run `dicom-dcmdir` | DICOMDIR management |
| `dicom-archive` | `dicom-archive` / `dicom-archive` | `Sources/dicom-archive` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; all operations via shared `ArchiveStore` | Run `dicom-archive` | ✅ Full archive engine (index model + 7 operations) extracted to `DICOMKit` (`Sources/DICOMKit/Archive/`); CLI + DICOMStudio share it, parity MATCHES (2026-06-08) |
| `dicom-export` | `dicom-export` / `dicom-export` | `Sources/dicom-export` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; export helpers via shared `DICOMImageExporter` | Run `dicom-export` | ✅ Deterministic export helpers (EXIF/layout/paths/window/encode) extracted to `DICOMKit` (`Sources/DICOMKit/ImageExport/`); CLI + DICOMStudio share them (2026-06-08) |
| `dicom-qr` | `dicom-qr` / `dicom-qr` | `Sources/dicom-qr` | `DICOMKit`, `DICOMCore`, `DICOMNetwork` | `ArgumentParser` | CLI adapter over network + DICOM libraries | Import `DICOMKit`, `DICOMCore`, `DICOMNetwork` | Run `dicom-qr` | Composite query/retrieve helper |
| `dicom-wado` | `dicom-wado` / `dicom-wado` | `Sources/dicom-wado` | `DICOMCore`, `DICOMWeb` | `ArgumentParser` | CLI adapter over web libraries | Import `DICOMCore`, `DICOMWeb`; direct client exists via `DICOMwebClient` | Run `dicom-wado` | DICOMweb retrieve workflow |
| `dicom-echo` | `dicom-echo` / `dicom-echo` | `Sources/dicom-echo` | `DICOMCore`, `DICOMNetwork` | `ArgumentParser` | CLI adapter over network libraries | Import `DICOMCore`, `DICOMNetwork` | Run `dicom-echo` | DIMSE echo/verification |
| `dicom-mwl` | `dicom-mwl` / `dicom-mwl` | `Sources/dicom-mwl` | `DICOMCore`, `DICOMNetwork` | `ArgumentParser` | CLI adapter over network libraries | Import `DICOMCore`, `DICOMNetwork` | Run `dicom-mwl` | Modality Worklist workflow |
| `dicom-mpps` | `dicom-mpps` / `dicom-mpps` | `Sources/dicom-mpps` | `DICOMCore`, `DICOMNetwork` | `ArgumentParser` | CLI adapter over network libraries | Import `DICOMCore`, `DICOMNetwork` | Run `dicom-mpps` | MPPS workflow |
| `dicom-pixedit` | `dicom-pixedit` / `dicom-pixedit` | `Sources/dicom-pixedit` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; edit pixels via shared `PixelEditor` | Run `dicom-pixedit` | ✅ `PixelEditor` engine extracted to `DICOMKit` (`Sources/DICOMKit/PixelEditing/`); CLI + DICOMStudio share it, parity MATCHES (2026-06-08) |
| `dicom-video` | `dicom-video` / `dicom-video` | `Sources/dicom-video` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; convert/probe/extract/batch via shared `VideoWorkflow` + `VideoConsole` | Run `dicom-video` | ✅ Built shared-first, not extracted: `VideoWorkflow` owns every operation and `VideoConsole` every line of text (`Sources/DICOMKit/Video/`), over `VideoProbe` / `VideoConformanceValidator` / `VideoBuilder` / `VideoExtractor`. CLI + DICOMStudio share both; the Workshop form and the CLI's `--help` read the same `VideoConsole.Help` strings. Pinned by `VideoConsoleParityTests` (57 tests) (2026-10-01) |
| `dicom-tags` | `dicom-tags` / `dicom-tags` | `Sources/dicom-tags` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; edit tags via shared `TagEditor` | Run `dicom-tags` | ✅ `TagEditor` engine extracted to `DICOMKit` (`Sources/DICOMKit/TagEditing/`); CLI + DICOMStudio share it, resolution unified on `DataElementDictionary` + skip-on-unknown (2026-06-08) |
| `dicom-uid` | `dicom-uid` / `dicom-uid` | `Sources/dicom-uid` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; generate/validate/lookup/regenerate via shared `UIDManager` | Run `dicom-uid` | ✅ `UIDManager` workflow engine extracted to `DICOMKit` (`Sources/DICOMKit/UIDManagement/`); CLI + DICOMStudio share it, parity MATCHES (2026-06-08) |
| `dicom-compress` | `dicom-compress` / `dicom-compress` | `Sources/dicom-compress` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; info/compress/decompress via shared `CompressionManager` | Run `dicom-compress` | ✅ `CompressionManager` workflow engine extracted to `DICOMKit` (`Sources/DICOMKit/Compression/`); CLI + DICOMStudio share it (in-memory `compressData`/`decompressData`), parity MATCHES (2026-06-08) |
| `dicom-study` | `dicom-study` / `dicom-study` | `Sources/dicom-study` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; scan/analyze via shared `StudyScanner` + `StudyReport` | Run `dicom-study` | ✅ Study analysis engine (scanner + summary/check/stats/compare renderers + models) extracted to `DICOMKit` (`Sources/DICOMKit/Study/`); CLI + DICOMStudio share it, parity MATCHES. `StudyOrganizer` remains CLI-local (2026-06-08) |
| `dicom-script` | `dicom-script` / `dicom-script` | `Sources/dicom-script` | `DICOMKit` | `ArgumentParser` | CLI adapter over package libraries | Import `DICOMKit`; script engine via shared `ScriptParser`/`ScriptExecutor`/`ScriptValidator`/`TemplateGenerator` | Run `dicom-script` | ✅ Script engine extracted to `DICOMKit` (`Sources/DICOMKit/Scripting/`); `ScriptExecutor` takes an injected `CommandRunner` (no `Process` in the library). CLI + DICOMStudio share it, parity MATCHES (2026-06-08) |
| `dicom-report` | `dicom-report` / `dicom-report` | `Sources/dicom-report` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries | Run `dicom-report` | Structured report/reporting workflow |
| `dicom-measure` | `dicom-measure` / `dicom-measure` | `Sources/dicom-measure` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries | Run `dicom-measure` | Measurement workflow |
| `dicom-viewer` | `dicom-viewer` / `dicom-viewer` | `Sources/dicom-viewer` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries | Run `dicom-viewer` | Terminal viewer workflow |
| `dicom-3d` | `dicom-3d` / `dicom-3d` | `Sources/dicom-3d` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries | Run `dicom-3d` | 3D / MPR / reconstruction workflow |
| `dicom-jpip` | `dicom-jpip` / `dicom-jpip` | `Sources/dicom-jpip` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `JPIP`, `ArgumentParser` | CLI adapter over package libraries + JPIP external stack | Import package libraries; JPIP-facing wrapper exists via `DICOMJPIPClient` | Run `dicom-jpip` | JPIP streaming workflow |
| `dicom-j2k` | `dicom-j2k` / `dicom-j2k` | `Sources/dicom-j2k` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `J2KCore`, `J2KCodec`, `J2KFileFormat`, `ArgumentParser` | CLI adapter over package libraries + J2K external stack | Import package libraries and codec wrappers; many J2K operations remain higher-level executable workflows | Run `dicom-j2k` | JPEG 2000 / HTJ2K codestream operations |
| `dicom-gateway` | `dicom-gateway` / `dicom-gateway` | `Sources/dicom-gateway` | `DICOMKit`, `DICOMCore`, `DICOMDictionary` | `ArgumentParser` | CLI adapter over package libraries | Import package libraries | Run `dicom-gateway` | Gateway / interop workflow |

## Developer / Support Executables

These are available executable targets in the package, but they are not normal
end-user `dicom-*` tools.

| Executable | Source Directory | Dependencies | Purpose | Third-Party Access | Terminal Access |
|---|---|---|---|---|---|
| `studio-cli-introspect` | `Sources/studio-cli-introspect` | `DICOMStudio` | Dumps the Studio CLI Workshop catalog | Not a public library API; consume `DICOMStudio` directly if needed | Run `studio-cli-introspect` |
| `cli-parity-docs` | `Sources/cli-parity-docs` | `DICOMStudio` | Generates CLI vs DICOMStudio parity docs | Not a public library API | Run `cli-parity-docs` |
| `cli-parity-gen` | `Sources/cli-parity-gen` | `DICOMKit`, `DICOMCore`, `DICOMStudio` | Regenerates CLI parity fixtures/contracts/goldens | Not intended as third-party API | Run `cli-parity-gen` |

## Not Currently Available as Executable Products

These executables are present in the repository but commented out in
`Package.swift`, so they are not currently available executable products.

- `dicom-print`
- `dicom-cloud`
- `dicom-ai`
- `dicom-server`

## Practical Access Summary

### From a Third-Party Application

Use the package libraries directly:

- import `DICOMKit` for file/document/image-level APIs
- import `DICOMCore` for low-level pixel/transcoding/codec APIs
- import `DICOMDictionary` for tag and UID lookup APIs
- import `DICOMNetwork` for DIMSE/network workflows
- import `DICOMWeb` for DICOMweb workflows

Where a shared package-level helper already exists, prefer it over shelling out.
Examples include:

- `MetadataPresenter`
- `HexDumper`
- `DICOMValidator` / `ValidationReport`
- `DICOMComparer` / `ComparisonReport`
- `Anonymizer`
- `TagEditor`
- `FrameMerger`
- `FrameSplitter`
- `StudyScanner` / `StudyReport` / `StudyOrganizer`
- `ArchiveStore`
- `PixelEditor`
- `ScriptParser` / `ScriptExecutor` / `ScriptValidator` / `TemplateGenerator`
- `ImageConverter`
- `UIDManager`
- `CompressionManager`
- `DICOMImageExporter`
- `DICOMJSONEncoder` / `DICOMJSONDecoder`
- `DICOMXMLEncoder` / `DICOMXMLDecoder`
- `DICOMwebClient`
- `DICOMJPIPClient`
- `TransferSyntaxConverter`

If exact CLI behavior is required for a tool whose workflow is still largely
executable-local, launch the compiled executable as a subprocess.

### From the Terminal

Build or install the package executables, then run the corresponding command
name directly, for example:

- `dicom-info`
- `dicom-validate`
- `dicom-diff`

From a source checkout, the built binaries are usually under:

- `.build/debug/`
- `.build/release/`

## Key Takeaway

The `dicom-*` tools belong to the **executable layer** of the DICOMKit package.
They are built on top of the package's reusable library modules, but they are
not themselves importable package libraries.