# DICOM Video Conversion Plan (H.264 / HEVC / MPEG-2)

**Status:** Phases 1-11 delivered. Phase 12 (transcoding) remains out of scope.
**Created:** 2026-09-09
**Last updated:** 2026-10-01
**Target CLI:** `dicom-video`
**Owner:** TBD

> **Delivery note (2026-09-10).** Everything scoped as v1 — Phases 1 through 10 —
> is built, tested and integrated. The `dicom-video` CLI ships `convert`, `probe`,
> `extract` and `batch`; the same engine drives DICOMStudio's CLI Workshop, and the
> Studio viewer now plays clips. Two items grew past the plan as written: the
> shared engine was factored into `VideoWorkflow` + `VideoConsole` (Phase 9 called
> for integration, not for lifting the whole CLI body into DICOMKit), and Phase 11
> was started early — `TransportStreamScanner` reads geometry out of an MPEG-TS so
> `--trust-input` cannot emit Rows/Columns of zero, though full TS demuxing is still
> deferred. See the per-phase status table below and the CHANGELOG entry dated
> 2026-09-10.

> **DICOM 2026d conformance update (2026-10-01).** Audited against PS3.5 8.2.5 -
> 8.2.12 and PS3.6 Table A-1 (2026d) and fixed:
> - **Level limits are enforced on the picture, not just `level_idc`** (H.264
>   Table A-1, H.265 Table A.8): a 4K stream signalled as Level 4.1 is rejected.
> - **HEVC High tier** is rejected (8.2.10 / 8.2.11 name Main tier).
> - **MPEG-2**: the level comparison was inverted (a High Level stream passed the
>   Main Level ceiling); Table 8-1 sizes and rates, and 8.2.6's 1280x720 /
>   1920x1080, 16:9 and frame-rate rules, are now checked.
> - **Audio is carried, not discarded**: the payload was always encapsulated
>   unchanged, so the old "discarding" warning was false. Audio is now validated
>   against 8.2.12 (AVC/HEVC: LPCM, AC-3, AAC, MP3, MP2 with their rate, channel
>   and container limits) and 8.2.5 (MPEG-2: CBR MP3 only).
> - **3D / stereo**: a frame packing SEI selects `.105`, an MVC subset SPS selects
>   `.106`, and Stereo Pairs Present (0022,0028) = YES is written for both.
> - **Basic Offset Table** is written empty (8.2.5 / 8.2.6 require it for MPEG-2;
>   A.4 allows a non-empty one only with an offset per frame).
> - **HEVC `.107` / `.108` are fragmentable in their own right**; the invented
>   `.107.1` / `.108.1` UIDs were removed. Payloads over 4 GiB are split, using
>   the `….1` twin for MPEG-2 / H.264.
> - **MPEG-TS is demultiplexed and validated** (Phase 11): PAT/PMT, full video
>   PES reassembly, frame count, PTS-derived frame rate, audio PIDs.
> - Container display rotation is reported, since DICOM cannot record it.

---

## Phase Status

| Phase | Scope | Status | Where it lives |
|---|---|---|---|
| 1 | Encapsulation fix (BLOCKING) | ✅ Done | `Video.swift`, `VideoParser.swift`; commit `20bbb4c` |
| 2 | IOD attribute corrections + 20 transfer syntaxes | ✅ Done | `TransferSyntax.swift`, `VideoBuilder.swift`; commit `20bbb4c` |
| 3 | Bitstream probing (H.264 / HEVC / MPEG-2) | ✅ Done | `BitstreamReader`, `H264Parser`, `HEVCParser`, `MPEG2Parser` |
| 4 | Container handling (MP4/MOV, raw ES, TS pass-through) | ✅ Done | `MP4ContainerParser`, `VideoProbe`, `TransportStreamScanner` |
| 5 | Conformance validation, reject-and-report | ✅ Done | `VideoConformanceValidator` |
| 6 | DICOM → video extraction | ✅ Done | `VideoExtractor` |
| 7 | CLI target `dicom-video` | ✅ Done | `Sources/dicom-video/main.swift` (a thin adapter) |
| 8 | Batch mode | ✅ Done | `VideoWorkflow.runBatch` |
| 9 | Integration surface | ✅ Done — **exceeded** | `VideoWorkflow` + `VideoConsole`, CLI Workshop, Studio viewer playback |
| 10 | Test matrix | ✅ Done | Unit, round-trip, parity and end-to-end suites |
| 11 | MPEG-TS demuxing | ✅ Done | `TransportStreamScanner.demux`: PAT/PMT, PES reassembly, PTS timing, audio PIDs |
| 12 | Transcoding | ⛔ Out of scope | Unchanged — reject-and-report stands |

---

## 0. Executive Summary

This plan covers building a tool that converts H.264/AVC, H.265/HEVC, and MPEG-2
video into conformant DICOM Video IODs, and extracts them back out.

**The work is not greenfield.** `Sources/DICOMKit/Video/` already contains ~1,000
lines across `Video.swift`, `VideoBuilder.swift`, and `VideoParser.swift`, and all
six video transfer syntaxes are defined in `Sources/DICOMCore/TransferSyntax.swift`.
The three video SOP classes are already registered in `UIDDictionary.swift` and
`StorageSOPClasses.swift`.

**However, the existing code contains a blocking correctness bug** (see Phase 1).
`Video.toDataSet()` writes the video bitstream as a *native* `OB` element, but every
video transfer syntax is *encapsulated* (PS3.5 A.4). The resulting files are not
readable by any conformant parser. Nothing else in this plan is meaningful until
that is fixed.

### Guiding decision: remux, don't transcode

Phases 1-10 ship a **remux-only** tool: it rewraps an already-conformant elementary
stream without re-encoding. This is lossless, fast, and covers the majority of real
workflows. Non-conformant input is **rejected with a message naming the specific
violated constraint**, never silently "fixed".

Transcoding (VideoToolbox re-encode of e.g. Baseline-profile or 4:4:4 input into a
DICOM-legal profile) roughly doubles the scope and would degrade diagnostic pixel
data on every pass. It is **out of scope**, recorded only for the record in
Phase 12.

### Scope decisions (settled)

These were open questions; they are now decided and drive the phases below.

| # | Decision | Consequence |
|---|---|---|
| Q1 | **`--type` flag, default `endoscopic` (ES)**, user-overridable | Phase 7.3; emit a visible notice when defaulting |
| Q2 | **TS *demuxing* deferred**; TS *pass-through* is legal (revised by F2) | Phase 4.4 → Phase 11; `--trust-input` in v1 |
| Q3 | **Reject-and-report** for non-conformant input; no transcoding | Phase 5.3; Phase 12 out of scope |
| Q4 | **Batch mode included**, `--series-mode` with **single series as default** | Phase 8 (new) |
| Q5 | **Strictly video** — H.264 / HEVC / MPEG-2 only | Non-video input errors, pointing at `dicom-image` |

---

## 0.5 Standards Verification (PS3.5 §8.2, PS3.3, IHE ENDO)

This plan was checked against the published standard text. **Six findings changed the
plan**; they are folded into the phases below and listed here so the corrections are
not lost.

Sources: PS3.5 §8.2.7 (H.264 HP@4.1), §8.2.10 (HEVC Main), §8.2.11 (HEVC Main 10),
§A.4.5-A.4.7; PS3.6 Annex A (UID registry); PS3.3 §A.32.5.3 (Video Endoscopic IOD),
§C.7.6.5 (Cine), §C.7.6.6 (Multi-frame), §C.8.12 (VL Image); IHE Endoscopy Image
Archiving (EIA) Rev. 1.1, 2018-11-28.

### F1 — There are 20 video transfer syntaxes, not 6 (**major**)

The repo defines 6 (`.100`, `.101`, `.102`, `.103`, `.107`, `.108`). The registry has
**20**. Missing:

| UID | Name | Note |
|---|---|---|
| `…4.100.1` | Fragmentable MPEG2 MP@ML | fragmentable variant |
| `…4.101.1` | Fragmentable MPEG2 MP@HL | fragmentable variant |
| `…4.102.1` | Fragmentable H.264 HP@4.1 | fragmentable variant |
| `…4.103.1` | Fragmentable H.264 BD HP@4.1 | fragmentable variant |
| **`…4.104`** | **H.264 HP@4.2 For 2D Video** | **IHE-required for endoscopy** |
| `…4.104.1` | Fragmentable H.264 HP@4.2 2D | |
| **`…4.105`** | **H.264 HP@4.2 For 3D Video** | **IHE-required for endoscopy** |
| `…4.105.1` | Fragmentable H.264 HP@4.2 3D | |
| **`…4.106`** | **H.264 Stereo HP@4.2** | **IHE-required for endoscopy** |
| `…4.106.1` | Fragmentable H.264 Stereo HP@4.2 | |

HEVC has no `….1` twins: `…4.107` and `…4.108` are each a Fragmentable
Encapsulated Transfer Syntax already (PS3.5 8.2.10 / 8.2.11, PS3.6 Table A-1).

IHE ENDO Table 3.10.4.1.3.1-2 lists `.100`-`.106` as the transfer syntaxes an
endoscopy Image Archive must support — so **`.104`/`.105`/`.106` are not exotic**,
they are expected in exactly our primary use case. Level 4.2 also covers 1080p60,
which Level 4.1 cannot.

**Action:** add all 14 missing UIDs to `TransferSyntax.swift` (new Phase 2.6), and
extend `isVideo`/`isH264`/`isH265`/`isMPEG2` plus the `allTransferSyntaxes` list.

### F2 — Container must be MPEG-TS or MP4, **not** raw Annex B (**major**)

PS3.5 §8.2.7 / §8.2.10 / §8.2.11, identical wording in each:

> "The container format for the video bit stream shall be MPEG-2 Transport Stream,
> a.k.a. MPEG-TS … or MPEG-4, a.k.a. MP4 container."

The original Phase 4 planned to **strip** the MP4 container and emit an Annex B
elementary stream. That is **backwards** — the encapsulated payload is meant to
*retain* its MP4 (or MPEG-TS) container.

**Actions:**
- Phase 4 becomes *validate and pass through* the MP4 container, not demux it.
- Bitstream probing (Phase 3) still parses SPS/VPS **for validation**, but reads it
  from the `avcC`/`hvcC` box; Annex B conversion is no longer part of the write path.
- **Q2 is partly reversed:** MPEG-TS is not an exotic future format, it is one of the
  two blessed containers. Accepting `.ts` as *input* stays deferred, but passing a TS
  payload through is explicitly legal. See revised Q2 note below.
- Raw `.264`/`.265`/`.m2v` elementary streams must be **wrapped into MP4** before
  encapsulation, not passed through raw.

### F3 — Rows/Columns need **not** be even (**correction**)

Phase 5.2 asserted "Rows and Columns must be even (4:2:0 requirement)". The standard
does **not** state this. Remove the check; keep only the requirement that Rows and
Columns match the bitstream. What §8.2.7 *does* require and the plan omitted:

> "Pixel Aspect Ratio (0028,0034) shall be absent. This corresponds to a 'Sampling
> Aspect Ratio' (SAR) of 1:1."

Non-square-pixel (anamorphic) video must therefore be **rejected**, since SAR ≠ 1:1
cannot be represented.

### F4 — `FrameIncrementPointer` is Type **1**, not 1C; `CineRate`/`RecommendedDisplayFrameRate` are Type **3**

PS3.3 §C.7.6.6: `NumberOfFrames` (0028,0008) **Type 1** and `FrameIncrementPointer`
(0028,0009) **Type 1** — both unconditionally mandatory. Phase 2.1 called the pointer
"1C"; it is stricter than that.

PS3.3 §C.7.6.5 (Cine): `FrameTime` is **1C** ("required if Frame Increment Pointer
points to Frame Time"); `CineRate`, `FrameDelay`, `ActualFrameDuration`, `StartTrim`,
`StopTrim`, `RecommendedDisplayFrameRate` are all **Type 3**. Phase 2.5's claim that
all three rate attributes are "required" was wrong — only `FrameTime` is, and only
because we point at it. Still write `CineRate`/`RecommendedDisplayFrameRate` as
useful Type 3 additions.

### F5 — Mandatory IOD modules are missing from the plan (**major**)

PS3.3 §A.32.5.3, Video Endoscopic Image IOD, modules marked **M**: Patient, General
Study, General Series, **General Equipment**, **General Acquisition**, **General
Image**, Cine, Multi-frame, Image Pixel, **Acquisition Context**, **VL Image**, SOP
Common. (Specimen and Frame Extraction are C; Device, ICC Profile, Clinical Trial\*
are U.)

The current `Video.toDataSet()` emits **none** of General Equipment, General
Acquisition, General Image, Acquisition Context, or VL Image. Notably, PS3.3 §C.8.12
makes **`ImageType` (0008,0008) Type 1** — entirely absent from the plan and the code.

**Action:** new Phase 2.7 to emit the mandatory modules. Minimum viable set:
- General Equipment: `Manufacturer` (2)
- General Acquisition: `AcquisitionDate`/`AcquisitionTime` (3, but expected)
- General Image: `InstanceNumber` (2), `PatientOrientation` (2C)
- VL Image: **`ImageType` (1)** — e.g. `ORIGINAL\PRIMARY`, `LossyImageCompression` (2)
- Acquisition Context: `AcquisitionContextSequence` (2) — may be empty
- SOP Common, Image Pixel, Cine, Multi-frame: already covered

### F6 — `LossyImageCompression` is Type 2, and `YBR_PARTIAL_422` is retired

PS3.3 §C.8.12: `LossyImageCompression` (0028,2110) is **Type 2** — the plan's "always
`01`" is correct in value and now confirmed mandatory-if-known.

PS3.3 §C.7.6.3 confirms `YBR_PARTIAL_420` for MPEG-family and notes **`YBR_PARTIAL_422`
is retired**. The codebase's `YBR_FULL_422` default (D4) is doubly wrong — the fix to
`YBR_PARTIAL_420` is confirmed correct by §8.2.7/8.2.10/8.2.11, which each state
"Photometric Interpretation (0028,0004) shall be YBR_PARTIAL_420".

### Confirmed correct (no change)

- Encapsulation via Item/BOT/delimiter, PS3.5 A.4 — **Phase 1 stands unchanged**
- Non-fragmentable UIDs: "one Fragment shall contain the whole bit stream" — matches
  Phase 1.2's single-fragment rule exactly
- HEVC Main 10 = BitsAllocated **16**, BitsStored 10, HighBit 9 — verified §8.2.11
- 8/8/7 for MPEG-2, H.264, HEVC Main; SamplesPerPixel 3; PlanarConfiguration 0;
  PixelRepresentation 0 — verified
- BD-compatible resolution/frame-rate table — verified, though the exact permitted
  set differs from the plan's guess (see Phase 5.2)

---

## 1. Current-State Audit

### 1.1 What already exists and is correct

| Component | Location | State |
|---|---|---|
| Transfer syntax definitions (all 6) | `Sources/DICOMCore/TransferSyntax.swift:362-433` | Correct |
| `isVideo` / `isMPEG2` / `isH264` / `isH265` | `Sources/DICOMCore/TransferSyntax.swift:713-757` | Correct |
| `Video` IOD model | `Sources/DICOMKit/Video/Video.swift` | Correct as a model |
| `VideoType` (endoscopic/microscopic/photographic) | `Sources/DICOMKit/Video/Video.swift` | Correct |
| `VideoCodec.compressionMethod` strings | `Sources/DICOMKit/Video/Video.swift` | Correct (`ISO_13818_2`, `ISO_14496_10`, `ISO_23008_2`) |
| SOP Class UID registration | `UIDDictionary.swift:213-233`, `StorageSOPClasses.swift:88-92` | Correct |
| `EncapsulatedPixelData` type | `Sources/DICOMCore/EncapsulatedPixelData.swift` | Correct, currently unused by Video |
| Encapsulated writer (Item/BOT/delimiter) | `Sources/DICOMCore/DICOMWriter.swift:342` | Correct, currently not reached by Video |
| `frameIncrementPointer` tag | `Sources/DICOMCore/Tag+ImageInformation.swift:226` | Defined, never set by Video |
| Existing tests | `Tests/DICOMKitTests/Video/VideoTests.swift` (52 tests) | Pass, but see 1.3 |

### 1.2 Defects and gaps

| # | Defect | Location | Severity |
|---|---|---|---|
| D1 | Pixel data written as native `OB`, not encapsulated fragments | `VideoBuilder.swift` `toDataSet()` | **Blocking** |
| D2 | Parser reads `.valueData`, which is empty for correctly-encapsulated files | `VideoParser.swift` | **Blocking** |
| D3 | `FrameIncrementPointer` (0028,0009) never set; type 1C for multi-frame | `VideoBuilder.swift` | High |
| D4 | Default `PhotometricInterpretation` is `YBR_FULL_422`; wrong for 4:2:0 video | `Video.swift`, `VideoBuilder.swift` | High |
| D5 | Bit depth hardcoded 8/8/7; cannot express HEVC Main 10 (10-bit) | `VideoBuilder.swift` | High |
| D6 | No bitstream probing; caller must hand-supply rows/columns/frames/fps | `VideoBuilder.swift` | High |
| D7 | No container demux; `.mp4` payload is not DICOM-legal | absent | High |
| D8 | No conformance validation against transfer-syntax constraints | absent | High |
| D9 | No CLI target | absent | Medium |
| D10 | Only 6 of 20 video transfer syntaxes defined (F1); missing IHE-required `.104`/`.105`/`.106` and all 8 fragmentable `.1` variants | `TransferSyntax.swift` | **High** |
| D11 | Mandatory IOD modules not emitted (F5): General Equipment, General Acquisition, General Image, Acquisition Context, VL Image — incl. **`ImageType` Type 1** | `VideoBuilder.swift` | **High** |
| D12 | `PixelAspectRatio` not forced absent; anamorphic (SAR≠1:1) input not rejected (F3) | `VideoBuilder.swift` | Medium |

### 1.3 Why the bug was not caught

`test_video_toDataSet_roundTrip` (`VideoTests.swift:407`) is **in-memory only** — it
builds a `DataSet` and reads attributes straight back. It never serializes through
`DICOMWriter` nor re-parses through `DICOMParser`, so the native-vs-encapsulated
distinction is invisible to it. The Phase 1 test closes exactly this hole.

---

## Phase 1 — Fix Encapsulation (BLOCKING)

**Goal:** Video pixel data survives a real write → read cycle byte-identically.
**Nothing else in this plan is real until this phase is green.**

### 1.1 Fix `Video.toDataSet()`

Replace the native element construction:

```swift
// WRONG — current code
dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: pixelData)
```

with the encapsulated initializer (confirmed present at `DataElement.swift:103`):

```swift
dataSet[.pixelData] = DataElement(
    tag: .pixelData,
    vr: .OB,
    length: 0xFFFFFFFF,
    valueData: Data(),
    encapsulatedFragments: [bitstream],
    encapsulatedOffsetTable: [0]
)
```

### 1.2 Fragmentation rules (PS3.5 A.4) — get these right

- **One fragment for the entire bitstream.** Do *not* split per frame. MPEG-family
  streams are inter-coded; frame boundaries are not independently decodable, and
  splitting them produces an undecodable object.
- **Basic Offset Table:** a single `0` entry (or empty). Never fabricate per-frame
  offsets that cannot be honoured — a wrong BOT is worse than an absent one.
- **Even-length fragments:** `DICOMWriter.serializeEncapsulatedPixelData` already
  pads odd fragments with a trailing `0x00`. **Do not double-pad** in the builder.

### 1.3 Fix `VideoParser`

Read `encapsulatedFragments` first; fall back to `.valueData` only for legacy or
non-encapsulated files:

```swift
let pixelData: Data?
if let element = dataSet[.pixelData] {
    if element.isEncapsulated {
        pixelData = element.encapsulatedFragments?.reduce(into: Data()) { $0 += $1 }
    } else {
        pixelData = element.valueData   // legacy / non-encapsulated fallback
    }
} else {
    pixelData = nil
}
```

### 1.4 Tests (the important part)

Add to `Tests/DICOMKitTests/Video/VideoTests.swift`:

- `test_video_fileRoundTrip_bitstreamIdentical` — build → `DICOMWriter` → bytes →
  `DICOMParser` → `VideoParser` → assert extracted bitstream **byte-identical** to
  input. This is the test that would have caught D1/D2.
- `test_video_pixelData_isEncapsulated` — assert the written element has
  `isEncapsulated == true` and undefined length `0xFFFFFFFF`.
- `test_video_oddLengthBitstream_paddedOnce` — feed an odd-length payload, assert
  exactly one pad byte and that the parser strips/handles it.
- `test_video_basicOffsetTable_singleEntry` — assert BOT is `[0]` or empty.

**Exit criteria:** all four tests pass; a written file opens in an external tool
(dcmtk `dcmdump` / Horos) showing a proper Item/fragment structure.

---

## Phase 2 — Correct the IOD Attributes

**Goal:** Attributes stop contradicting the bitstream. Depends on Phase 1.

### 2.1 `FrameIncrementPointer` (D3)

**Type 1** — unconditionally mandatory, per PS3.3 §C.7.6.6 (F4); `NumberOfFrames` is
Type 1 there too. Must be VR `AT` pointing at `FrameTime` (0018,1063). Note: `VR.AT`
exists (`VR.swift:44`) but there is **no `attributeTag` convenience helper on
`DataElement`** — add one, or encode the 4 bytes (group LE, element LE) directly.

```swift
// FrameIncrementPointer -> FrameTime (0018,1063)
dataSet[.frameIncrementPointer] = DataElement.attributeTag(
    tag: .frameIncrementPointer, value: .frameTime
)
```

### 2.2 Photometric Interpretation (D4)

Must reflect the codec's **actual** chroma subsampling, not a fixed default:

| Codec / profile | Typical chroma | Photometric Interpretation |
|---|---|---|
| MPEG-2 MP@ML / MP@HL | 4:2:0 | `YBR_PARTIAL_420` |
| H.264 High @ 4.1 | 4:2:0 | `YBR_PARTIAL_420` |
| H.264 BD-compatible | 4:2:0 | `YBR_PARTIAL_420` |
| HEVC Main / Main 10 | 4:2:0 | `YBR_PARTIAL_420` |

Change the default from `YBR_FULL_422` to `YBR_PARTIAL_420`, and **derive it from
the parsed `chroma_format_idc`** rather than assuming. Reject 4:2:2 / 4:4:4 input in
remux mode (Phase 5).

### 2.3 Bit depth (D5)

Drive from the bitstream, not from constants:

| Profile | BitsAllocated | BitsStored | HighBit |
|---|---|---|---|
| MPEG-2, H.264, HEVC Main | 8 | 8 | 7 |
| **HEVC Main 10** | **16** | **10** | **9** |

Note `BitsAllocated` for Main 10 is **16**, not 10 — DICOM allocates on byte
boundaries. Add a `setBitDepthForCodec(_:)` helper so callers cannot get this wrong.

### 2.4 Fixed-value attributes

Verified verbatim against PS3.5 §8.2.7 / §8.2.10 / §8.2.11:

- `SamplesPerPixel` = 3 — "shall be 3"
- `PlanarConfiguration` = 0 — "shall be 0"; currently optional, must be emitted
- `PixelRepresentation` = 0 — "shall be 0"
- **`PixelAspectRatio` (0028,0034) shall be ABSENT** (F3) — "corresponds to a
  'Sampling Aspect Ratio' (SAR) of 1:1". Never emit it; reject anamorphic input.
- `LossyImageCompression` = `"01"` — Type 2 per PS3.3 §C.8.12, always lossy
- `LossyImageCompressionMethod` = from `VideoCodec.compressionMethod` (already correct)

### 2.5 Cine Module

The Cine **module** is M in the Video Endoscopic IOD, but its attribute types are
looser than the plan first assumed (F4, PS3.3 §C.7.6.5):

| Attribute | Type | Action |
|---|---|---|
| `FrameTime` (0018,1063) | **1C** — required because we point `FrameIncrementPointer` at it | **Must emit** |
| `CineRate` (0018,0040) | 3 | Emit (useful) |
| `RecommendedDisplayFrameRate` (0008,2144) | 3 | Emit (useful) |
| `FrameDelay`, `ActualFrameDuration`, `StartTrim`, `StopTrim` | 3 | Optional |

All derived from the bitstream frame rate (Phase 3), never guessed. Retain the
existing `effectiveFrameRate` fallback chain for parsing only, not for writing.

### 2.6 Add the 14 missing transfer syntaxes (D10 / F1)

Extend `Sources/DICOMCore/TransferSyntax.swift` with all UIDs from the F1 table, then
update `isVideo`, `isMPEG2`, `isH264`, `isH265`, the `uid →` switch, the
`allTransferSyntaxes` list, and the display-name switch.

Add a distinguishing property, since it changes the write path:

```swift
/// True for the "…​.1" fragmentable variants, where the bitstream MAY span
/// multiple fragments. Non-fragmentable UIDs require exactly one fragment
/// containing the whole stream (PS3.5 §8.2.7).
public var allowsMultipleFragments: Bool { uid.hasSuffix(".1") }
```

Prefer **non-fragmentable** UIDs when writing (simplest, always legal); accept both
when reading. Level 4.2 (`.104`) is the right default for 1080p60 sources, which
Level 4.1 cannot represent.

### 2.7 Emit the mandatory IOD modules (D11 / F5)

Per PS3.3 §A.32.5.3, these modules are **M** and currently unemitted:

| Module | Minimum attributes |
|---|---|
| **VL Image** | **`ImageType` (0008,0008) — Type 1**, e.g. `ORIGINAL\PRIMARY` |
| General Equipment | `Manufacturer` (0008,0070) — Type 2 |
| General Acquisition | `AcquisitionDate`/`AcquisitionTime` |
| General Image | `InstanceNumber` (Type 2), `PatientOrientation` (Type 2C) |
| Acquisition Context | `AcquisitionContextSequence` (0040,0555) — Type 2, may be empty |

Also emit Type 2 identifiers currently missing but required to be present (possibly
empty): `StudyDate`, `StudyTime`, `ReferringPhysicianName`, `StudyID`,
`AccessionNumber`, `PatientBirthDate`, `PatientSex`. Add CLI flags for the ones a
user would reasonably set, and emit zero-length elements otherwise.

**Exit criteria:** unit tests asserting each attribute per codec/profile combination;
a Main 10 file with correct 16/10/9; a written file passing `dicom-validate` with no
missing-Type-1 or missing-Type-2 errors.

---

## Phase 3 — Bitstream Probing

**Goal:** Derive rows, columns, frame count, frame rate, profile, level, chroma
format, and bit depth from the coded parameter sets. This is the bulk of the new
engineering.

**Scope narrowed by F2.** Parsing is now for **validation only** — the bytes written
are the original container's, never a reconstructed stream. For MP4/MOV input the
parameter sets come from the `avcC`/`hvcC` box (Phase 4.2) rather than from a
byte-stream scan; full Annex B scanning is needed only for raw elementary-stream
input (Phase 4.3).

### 3.1 Shared infrastructure

New file `Sources/DICOMKit/Video/BitstreamReader.swift`:

- Big-endian bit reader over `Data`
- **Exp-Golomb decoding**: `ue(v)` unsigned, `se(v)` signed
- **Emulation Prevention Byte removal**: strip `0x03` from `00 00 03` sequences
  before parsing H.264/HEVC RBSP. *Skipping this silently corrupts parsed values.*
- Annex B start-code scanning (`00 00 01` / `00 00 00 01`) and NAL unit splitting

### 3.2 H.264 / AVC — `H264Parser.swift`

Parse SPS (NAL type 7):
- `profile_idc`, `level_idc`, `constraint_set*_flags`
- `chroma_format_idc` (skip correctly for `profile_idc` in {100,110,122,244,44,83,86,118,128})
- `bit_depth_luma_minus8`, `bit_depth_chroma_minus8`
- `pic_width_in_mbs_minus1` → width = `(v+1) * 16`
- `pic_height_in_map_units_minus1`, `frame_mbs_only_flag`
  → height = `(v+1) * 16 * (2 - frame_mbs_only_flag)`
- **`frame_cropping_flag` + crop offsets** — must subtract. Omitting this yields
  **1088 instead of 1080**, the single most common bug in this area.
- VUI: `timing_info_present_flag` → `num_units_in_tick`, `time_scale`
  → fps = `time_scale / (2 * num_units_in_tick)`

### 3.3 HEVC / H.265 — `HEVCParser.swift`

Parse VPS (32) / SPS (33) / PPS (34):
- `general_profile_idc`, `general_level_idc`, `general_tier_flag`
- `chroma_format_idc`
- `pic_width_in_luma_samples`, `pic_height_in_luma_samples`
- **conformance window** offsets — subtract, same trap as H.264 cropping
- `bit_depth_luma_minus8` → 0 = Main, 2 = **Main 10** (selects the transfer syntax)
- VUI timing for fps

### 3.4 MPEG-2 — `MPEG2Parser.swift`

- Sequence header (`0x000001B3`): 12-bit horizontal + 12-bit vertical size,
  `frame_rate_code` (table lookup → 23.976/24/25/29.97/30/50/59.94/60),
  `aspect_ratio_information`
- Sequence extension (`0x000001B5`): `profile_and_level_indication`,
  size extension bits, `progressive_sequence`, `chroma_format`

### 3.5 Frame counting

`NumberOfFrames` must be accurate — a wrong count makes the object non-conformant.
Order of preference:
1. **The MP4 sample table (Phase 4.2)** — exact, cheap, and the normal path
2. Access-unit counting — **fallback for raw elementary streams only**: H.264 — count VCL NALs (types 1/5)
   with `first_mb_in_slice == 0`; HEVC — VCL NAL types 0-31 with
   `first_slice_segment_in_pic_flag == 1`; MPEG-2 — count picture start codes
   (`0x00000100`)
3. Never derive from duration × fps (rounding drift)

**Exit criteria:** fixture-based tests with known-good streams, including a
**cropped 1920×1080** H.264 SPS and a 10-bit HEVC SPS.

---

## Phase 4 — Container Handling

> **Revised by finding F2.** The original plan had this backwards: it proposed
> *stripping* the MP4 container to produce an Annex B elementary stream. PS3.5
> §8.2.7 / §8.2.10 / §8.2.11 each state the opposite:
>
> > "The container format for the video bit stream shall be MPEG-2 Transport Stream,
> > a.k.a. MPEG-TS … or MPEG-4, a.k.a. MP4 container."
>
> The encapsulated payload **retains** its container. Phase 4 is therefore
> *validate and pass through*, not demux.

**Goal:** Accept input, confirm the payload is in a DICOM-legal container, and hand
the bytes to encapsulation unchanged wherever possible.

### 4.1 MP4 / MOV input (primary path)

- **Pass the MP4 payload through byte-for-byte** into the single fragment. No
  AVCC→Annex B conversion, no re-muxing.
- `.mov` is not MP4. If the track is plain H.264/HEVC, remux the container to MP4
  (`AVAssetExportSession` passthrough, or `AVAssetWriter` with
  `AVFileType.mp4` and compressed sample appends) — stream copy only, never re-encode.
- Reject MP4s carrying multiple video tracks, or a video track plus content we cannot
  represent, rather than silently picking track 0.
- Audio: DICOM video may carry audio. PS3.5 2026a 8.2.5 (MPEG2 MP@ML, applied to
  MP@HL by 8.2.6) restricts "any audio components present within the MPEG bit
  stream" to CBR MP3; 8.2.7–8.2.11 (H.264, HEVC) send "any audio components included
  in the data container" to 8.2.12, whose Table 8.2.12-1 allows AAC, MP3 and MPEG-1
  Audio Layer II in MP4, and those plus LPCM and AC-3 in MPEG-2 TS. DICOMKit keeps the
  audio in the bit stream unchanged and checks each track against those constraints
  (`VideoConformanceValidator.validateAudio`, D46): a violation is a **warning**, never a
  rejection or a re-encode — see the resolved open question below. MP3 frame headers are
  walked for the CBR rule, and LATM/raw MPEG-4 audio in MPEG-TS is identified (D58); bits per
  sample of compressed audio is stated as not in the bit stream, and what remains unknown
  (e.g. MP3 complementary channels) is reported as "not checked".

### 4.2 Parameter-set access for validation

Probing (Phase 3) still needs SPS/VPS to validate profile/level/chroma, but now reads
them from the container's sample description rather than from a converted stream:

- `CMVideoFormatDescriptionGetH264ParameterSetAtIndex` /
  `...GetHEVCParameterSetAtIndex` to recover SPS/PPS/VPS from `avcC`/`hvcC`
- `AVAssetTrack.nominalFrameRate` and `naturalSize` cross-checked against the SPS
- Exact frame count from the sample table (`AVAssetReader` sample enumeration),
  which is cheaper and more reliable than counting access units (Phase 3.5)

Parsing is read-only here — the bytes written are the original container's.

### 4.3 Raw elementary stream input

`.264` / `.h264` / `.265` / `.hevc` / `.m2v` / `.mpv` are **not** legal payloads on
their own (F2). They must be **wrapped into MP4** before encapsulation:

- Detect by start-code sniffing, not extension
- Parse with Phase 3 to recover dimensions/profile/frame rate (no container metadata
  to lean on)
- Wrap via `AVAssetWriter`, stream-copying the access units — no re-encode
- If wrapping is not feasible for a given stream, reject with the ffmpeg remedy

### 4.4 MPEG-2 Transport Stream — Q2 partly reversed

MPEG-TS is **one of the two blessed container formats**, not an exotic one. This
narrows Q2 rather than reversing it:

- **Passing a TS payload through** to encapsulation is explicitly legal and cheap —
  support it where the input is already a conformant TS.
- **Demuxing TS** (PES depacketization, PAT/PMT walking) is only needed to *inspect*
  or *convert* one, and stays deferred to Phase 11.

Practical v1 stance: accept `.ts` input in **pass-through mode with `--trust-input`**,
where the user asserts conformance and we skip deep validation; otherwise reject with:

```
error: MPEG-2 Transport Stream input cannot be validated in this release
       (TS demuxing is Phase 11). Either convert to MP4:
         ffmpeg -i input.ts -c copy output.mp4
       or re-run with --trust-input to encapsulate the TS unvalidated.
```

Keep the `VideoContainerDemuxer` protocol so Phase 11 adds a case rather than
reworking the pipeline.

**Exit criteria:** an MP4 input is encapsulated byte-identically and re-extracts to
the same bytes; a raw `.264` is wrapped to MP4 and validates; `.ts` behaves per 4.4.

---

## Phase 5 — Conformance Validation

**Goal:** Enforce constraints rather than merely recording them. Video DICOM is
unusually strict, and this is where most implementations quietly go wrong.

New file `Sources/DICOMKit/Video/VideoConformanceValidator.swift`.

### 5.1 Transfer-syntax selection matrix

Updated for F1 — each row also has a `.1` fragmentable twin (prefer the
non-fragmentable form when writing):

| Transfer Syntax | UID | Requires |
|---|---|---|
| MPEG2 MP@ML | `…4.100` | MPEG-2, Main Profile, Main Level |
| MPEG2 MP@HL | `…4.101` | MPEG-2, Main Profile, High Level |
| H.264 HP@4.1 | `…4.102` | H.264 High Profile, level ≤ 4.1 |
| H.264 BD HP@4.1 | `…4.103` | H.264 High Profile + Table 8-4 constraints |
| **H.264 HP@4.2 2D** | **`…4.104`** | **H.264 High Profile, level ≤ 4.2 — needed for 1080p60** |
| H.264 HP@4.2 3D | `…4.105` | H.264 High Profile 4.2, 3D video |
| H.264 Stereo HP@4.2 | `…4.106` | H.264 Stereo High Profile 4.2 |
| HEVC Main@5.1 | `…4.107` | HEVC Main, level ≤ 5.1, 8-bit |
| HEVC Main10@5.1 | `…4.108` | HEVC Main 10, level ≤ 5.1, 10-bit |

Auto-select from probed profile/level/bit-depth; allow explicit override but
**validate the override and fail loudly on mismatch.** For H.264, prefer `.102` when
level ≤ 4.1, else `.104` — do not reject 1080p60 outright, it is legal at 4.2.

### 5.2 Hard constraints to enforce

Corrected against PS3.5 §8.2.7 (F3):

- ~~Rows and Columns must be even~~ — **the standard does not require this.** Removed.
- **`PixelAspectRatio` must be absent**, i.e. SAR must be 1:1. **Reject anamorphic
  input** (SAR ≠ 1:1 in the SPS VUI) — it cannot be represented.
- Rows/Columns must **match the bitstream** exactly (after cropping / conformance window)
- Level must not exceed the chosen transfer syntax's ceiling
- Profile must match exactly — Baseline/Main H.264 is **rejected** in remux mode
- `chroma_format_idc` must indicate 4:2:0
- `NumberOfFrames` ≥ 1, matching the container's sample count
- Container must be MP4 or MPEG-TS (F2)

**BD-compatible (`…4.103`) — Table 8-4, verified verbatim.** My earlier list was
wrong: it included 720×576 and 720×480, which are **not** in the table, and omitted
the 23.976/24 fps rows.

| Rows | Columns | Frame rate | Scan |
|---|---|---|---|
| 1080 | 1920 | 25 | Interlaced |
| 1080 | 1920 | 29.97 | Interlaced |
| 1080 | 1920 | 24 | Progressive |
| 1080 | 1920 | 23.976 | Progressive |
| 720 | 1280 | 50 | Progressive |
| 720 | 1280 | 59.94 | Progressive |
| 720 | 1280 | 24 | Progressive |
| 720 | 1280 | 23.976 | Progressive |

Note 1920×1080 is permitted only **interlaced** at 25/29.97 — a detail worth
enforcing, since progressive 1080p25 is *not* BD-compatible and belongs on `.102`
or `.104`.

### 5.3 Error reporting — reject and report (Decision Q3)

Non-conformant input is **never silently re-encoded**. The tool rejects it and tells
the user exactly how to fix it. Rationale: remuxing preserves the camera's pixel data
bit-for-bit, whereas re-encoding loses image quality on every pass — unacceptable to
do implicitly to diagnostic imagery.

Every rejection names the violated constraint, the observed value, the expected
value, and a copy-pasteable remedy:

```
error: H.264 profile_idc 66 (Baseline) is not permitted by transfer syntax
       1.2.840.10008.1.2.4.102, which requires High Profile (100).

       Re-encode first, then retry:
       ffmpeg -i input.mp4 -c:v libx264 -profile:v high -level 4.1 fixed.mp4
```

Exit codes: `0` success, `1` I/O or usage error, `2` conformance rejection — so
scripts can distinguish "broken" from "not DICOM-legal".

### 5.4 Non-video input guard (Decision Q5)

`dicom-video` handles **H.264, HEVC, and MPEG-2 only**. Image sequences, animated
GIFs, and TIFF stacks are multi-frame but not video, and belong to a different DICOM
storage path. Detect and redirect rather than attempting conversion:

```
error: 'frames/' contains a PNG image sequence, not a video bitstream.
       dicom-video handles H.264/HEVC/MPEG-2 only. Use dicom-image instead.
```

**Exit criteria:** a rejection test per constraint in 5.2, each asserting its specific
message and exit code; a non-video input test asserting the `dicom-image` redirect.

---

## Phase 6 — DICOM → Video Extraction

**Goal:** The reverse direction. Nearly free once Phase 1 is done.

- Read encapsulated fragments, concatenate, write the elementary stream
- Optionally remux into MP4 via `AVAssetWriter` for playability
- Derive output container/extension from the transfer syntax
- Validate that the transfer syntax is a video one; otherwise a clear error
  directing the user to `dicom-image`

**Exit criteria:** `convert → extract` produces a byte-identical bitstream.

---

## Phase 7 — CLI Target `dicom-video`

**Goal:** Ship the user-facing tool. Only after Phases 1-6.

Naming: `dicom-image` is the still-image tool, so `dicom-video` is the natural
counterpart.

### 7.1 Files

- `Sources/dicom-video/main.swift` — ArgumentParser, matching the `dicom-pdf` and
  `dicom-image` structure
- `Sources/dicom-video/README.md`

### 7.2 `Package.swift` registration (two places, per existing convention)

Product, near line 98:
```swift
.executable(name: "dicom-video", targets: ["dicom-video"]),
```

Target, near line 668:
```swift
.executableTarget(
    name: "dicom-video",
    dependencies: [
        "DICOMKit",
        "DICOMCore",
        "DICOMDictionary",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
    ],
    path: "Sources/dicom-video",
    exclude: ["README.md"]
),
```

### 7.3 Interface sketch

```
dicom-video convert <input> --output <out.dcm>
    [--type endoscopic|microscopic|photographic]   # default: endoscopic (Q1)
    [--transfer-syntax <uid>]        # auto-detected by default
    [--patient-name] [--patient-id]
    [--study-uid] [--series-uid]
    [--series-description] [--modality]
    [--frame-rate <fps>]             # override probe; validated
    [--dry-run]                      # probe + validate, write nothing

dicom-video batch <input-dir> --output-dir <dir>     # Phase 8
    [--series-mode single|per-file]  # default: single (Q4)
    [--type ...] [--study-uid ...] [--patient-name ...]
    [--continue-on-error]

dicom-video extract <in.dcm> --output <out.264|out.mp4>

dicom-video probe <input>           # report dimensions/profile/level/fps/conformance
```

### 7.4 `--type` default behaviour (Decision Q1)

`--type` defaults to `endoscopic`, which also sets modality `ES`. Because a wrong
guess yields a *valid but mislabelled* object that could be misfiled in a PACS, the
default must be **visible, not silent**:

```
note: Using SOP class Video Endoscopic Image Storage (modality ES).
      Override with --type microscopic|photographic.
```

Print only when defaulting, not when `--type` is given explicitly. An explicit
`--modality` overrides the type's default modality without changing the SOP class.

`probe` and `--dry-run` matter: they let a user learn *why* a file is rejected
without producing an object.

**Exit criteria:** `swift build` clean; `--help` correct; CLI smoke tests; a test
asserting the default-notice appears only when `--type` is omitted.

---

## Phase 8 — Batch Mode

**Goal:** Convert a directory of clips in one command, with user-selectable series
grouping. Decision Q4.

### 8.1 Why grouping is a real choice

DICOM organises data as **Study → Series → Instances**. Twenty clips from one
procedure and twenty unrelated recordings are both legitimate, but they mean
different things clinically and sort differently in a viewer.

| `--series-mode` | Result | Fits |
|---|---|---|
| **`single`** (default) | One Series UID; clips become instances 1..N | Clips from **one procedure step on one device** — IHE's normal case |
| `per-file` | A fresh Series UID per clip | Clips from **different procedure steps or different equipment**, where IHE *requires* separate series |

**IHE ENDO §3.10.4.1.1.1 makes `single` the correct default**, not merely the
convenient one: one procedure step on one piece of equipment must be one series, and
that explicitly holds even when the endoscope is swapped mid-procedure. See
"Series Grouping: What the Standard Says" near the end of this document.

Both modes share **one Study Instance UID** — batch implies one patient visit. To
place clips in an existing study, pass `--study-uid`.

**Do not emit `FrameOfReferenceUID`.** IHE requires a single Frame of Reference per
series, but notes the constraint "is avoided" when the attribute is absent at series
level — and endoscopic video has no meaningful spatial frame of reference.

### 8.2 Semantics

- **Ordering is deterministic**: sort filenames with a natural/numeric-aware
  comparator so `clip2.mp4` precedes `clip10.mp4`. `InstanceNumber` follows that
  order, starting at 1.
- `--series-mode single`: one generated Series UID, `SeriesNumber` = 1,
  `InstanceNumber` = 1..N.
- `--series-mode per-file`: a new Series UID per clip, `SeriesNumber` incrementing,
  `InstanceNumber` = 1 within each.
- Explicit `--series-uid` is only valid with `single` — reject it under `per-file`
  as contradictory rather than silently ignoring it.
- Patient/study metadata flags apply uniformly to every output.
- Output naming: `<input-basename>.dcm` in `--output-dir`; refuse to overwrite
  without `--force`.

### 8.3 Failure policy

Default is **fail-fast**: stop at the first rejection, having written nothing further,
so a half-populated series is never left behind. `--continue-on-error` switches to
best-effort — skip failures, convert the rest, print a summary, exit `2` if any were
skipped:

```
Converted 18 of 20 clips (2 skipped).
  skipped: clip07.mp4 — H.264 Baseline profile not permitted
  skipped: clip19.mp4 — Level 5.0 exceeds transfer syntax maximum 4.1
```

Under `single`, skipped files must not leave gaps in `InstanceNumber` — number the
**successful** conversions consecutively.

### 8.4 Recursion

Non-recursive by default; `--recursive` to descend. Filter to known video extensions
and content-sniff before converting, so stray files in a folder are ignored rather
than erroring.

**Exit criteria:** tests for both series modes asserting UID/numbering structure;
natural-sort ordering test; fail-fast and continue-on-error tests; a test that
`--series-uid` with `per-file` is rejected.

---

## Phase 9 — Integration Surface

Adding a CLI here is **not one file**. Mirroring how `dicom-pdf` is wired:

- `Sources/DICOMStudio/ViewModels/CLIWorkshopViewModel.swift` — per-tool handler
  (note the existing `encapsulateFile` / `encapsulateFromDirectory` helpers around
  lines 2075 and 2205 as the pattern to follow)
- `Sources/DICOMStudio/Components/CLIWorkshopHelpers.swift` — tool metadata
- `INSTALLATION.md`, `DISTRIBUTION.md`
- `Formula/` — Homebrew formula
- `README.md` — tool table
- `CHANGELOG.md`
- CI workflow, if executables are enumerated there

**Exit criteria:** the tool appears in Studio's CLI Workshop and installs via brew.

---

## Phase 10 — Test Matrix

### 10.1 Unit
- Exp-Golomb decode vectors
- Emulation-prevention-byte stripping
- SPS/VPS parsing fixtures per codec, **including cropped 1080p and 10-bit HEVC**
- Attribute correctness per codec/profile (Phase 2 table)

### 10.2 Round-trip (highest value)
- `build → write → read → parse` byte-identical bitstream, per codec
- Odd-length payload padding
- Extraction round-trip (Phase 6)

### 10.3 Conformance / negative
- One rejection test per Phase 5.2 constraint, asserting message and exit code
- Non-video input redirects to `dicom-image` (Q5)
- `.ts` input produces the deferred-container error (Q2)
- Malformed/truncated bitstream → clean error, no crash
- Empty and 1-frame inputs

### 10.4 Batch (Phase 8)
- `single` vs `per-file` UID and numbering structure
- Natural-sort ordering (`clip2` before `clip10`)
- Fail-fast vs `--continue-on-error`, including no `InstanceNumber` gaps
- `--series-uid` with `per-file` rejected

### 10.5 Integration
- CLI smoke tests for `convert` / `batch` / `extract` / `probe`
- `--type` default notice appears only when the flag is omitted (Q1)
- Validate output with `dicom-validate`
- Cross-check with dcmtk `dcmdump` where available

**Test fixtures:** generate small synthetic clips with ffmpeg; commit only tiny
(< 100 KB) streams, or generate at test time to avoid repo bloat.

---

## Phase 11 — Future: MPEG-2 Transport Stream (Decision Q2)

Deferred from Phase 4.4. Note MPEG-TS is a **legal container** per F2 — v1 can
already pass a conformant TS through under `--trust-input`. This phase adds the
*demuxing* needed to validate or convert one.

- MPEG-2 TS demux: 188-byte packets, PID filtering via PAT/PMT, PES depacketization
- Program Stream / VOB (`.vob`) pack-layer parsing
- Reassemble PES payloads into a contiguous elementary stream, then reuse Phase 3
- Slots in as a `VideoContainerDemuxer` conformance (Phase 4.4) — no pipeline rework
- Enables dropping `--trust-input` for TS, validating it like MP4

---

## Phase 12 — Future: Transcoding (Decision Q3 — out of scope)

**Not planned.** Recorded so the decision is not silently revisited.

Reject-and-report (Phase 5.3) is the chosen policy: remuxing preserves diagnostic
pixel data bit-for-bit, while re-encoding degrades it on every pass. Revisit only if
users are demonstrably blocked by non-conformant sources they cannot re-encode
themselves.

If ever built:
- VideoToolbox re-encode to a DICOM-legal profile
- Baseline/Main → High, 4:2:2/4:4:4 → 4:2:0, level reduction
- Must set `LossyImageCompressionRatio` from actual sizes and record generation loss
- Explicit opt-in `--transcode`; **never** implicit fallback from a rejection

---

## Execution Order

| Order | Phase | Blocking? | Rough size |
|---|---|---|---|
| 1 | Phase 1 — Encapsulation fix + round-trip test | **Yes** | Small |
| 2 | Phase 2 — IOD attribute corrections | Yes | Small |
| 3 | Phase 3 — Bitstream probing | Yes | **Large** |
| 4 | Phase 4 — Container demuxing (MP4/MOV/raw) | Yes | Medium |
| 5 | Phase 5 — Conformance validation | Yes | Medium |
| 6 | Phase 6 — Extraction | No | Small |
| 7 | Phase 7 — CLI target | No | Medium |
| 8 | Phase 8 — Batch mode | No | Medium |
| 9 | Phase 9 — Integration surface | No | Small |
| 10 | Phase 10 — Test matrix | Continuous | Medium |
| — | Phase 11 — Transport Stream | Future | Medium |
| — | Phase 12 — Transcoding | Out of scope | Large |

Phases 1-2 are worth doing immediately regardless of whether the CLI ships: they fix
a latent bug that makes the *existing, already-shipped* `VideoBuilder` API produce
invalid files.

**v1 delivery = Phases 1-10.** Phases 11-12 are explicitly not v1.

---

## Resolved Decisions

Recorded so they are not silently revisited. See the Scope Decisions table in §0.

1. **Primary SOP class** — `--type` flag, defaulting to **endoscopic (ES)**,
   user-overridable. The default prints a visible notice, because a wrong guess
   produces a valid but mislabelled object. *(Phase 7.4)*
2. **MPEG-2 Transport Stream** — **partly reversed by F2.** MPEG-TS is one of the two
   container formats the standard blesses, so *pass-through* of a conformant TS is
   legal and supported behind `--trust-input`. Only TS **demuxing** (PES/PAT/PMT)
   stays deferred to Phase 11. *(Phase 4.4)*
3. **Transcoding** — **out of scope**. Reject-and-report, since remuxing preserves
   diagnostic pixel data bit-for-bit and re-encoding degrades it. Rejections name the
   constraint and give a copy-pasteable fix; exit code `2`. *(Phase 5.3, Phase 12)*
4. **Batch mode** — **included**, `--series-mode single|per-file` defaulting to
   `single`. **Confirmed correct by IHE** — see §"Series grouping: what the standard
   says" below. *(Phase 8)*
5. **Scope** — **strictly video**: H.264, HEVC, MPEG-2 only. Image sequences and other
   multi-frame stills are rejected with a pointer to `dicom-image`. *(Phase 5.4)*
   IHE ENDO Table 3.10.4.1.3.1-1 corroborates the Q1 default: **Video Endoscopic
   Image Storage** (`…77.1.1.1`) is the sole video SOP class an endoscopy archive
   must support.

---

## Series Grouping: What the Standard Says (answers Q4)

IHE Endoscopy Image Archiving (EIA) Rev. 1.1 §3.10.4.1.1.1 gives **normative rules**,
which settle this better than a preference. Quoted verbatim:

> "When the endoscope is changed in the midst of a procedure, all images acquired
> during the procedure (before and after the change) should be placed in the same
> series."

> "Multiple performed procedure steps are not permitted to reference the same series.
> So conversely, one series cannot contain the output of different performed
> procedure steps."

> "Adding images after completion of a procedure step shall trigger the creation of a
> new series."

> "One series cannot contain the output of different equipment (in part because a
> series must have a single Frame Of Reference). Creating images on different
> equipment shall trigger the creation of a new series."

> "All images in a series must share the same Frame Of Reference."

### Verdict: `single` is the correct default — and it is stronger than a preference

One procedure step on one piece of equipment ⇒ **one series**, explicitly including
the case where the scope was swapped mid-procedure. Clips from a single endoscopy run
therefore belong in **one series**, which is what `--series-mode single` does.

`per-file` remains valid but should be documented for what it actually models:
clips from **different procedure steps or different equipment**, where IHE *requires*
separate series.

### Consequences for Phase 8

- Keep `single` as the default. Document it as IHE-aligned, not merely convenient.
- Re-word `per-file` help text: not "unrelated recordings" but "different procedure
  steps or equipment (IHE ENDO §3.10.4.1.1.1)".
- **Do not emit `FrameOfReferenceUID`** unless the caller supplies one. IHE notes the
  same-Frame-of-Reference constraint "is avoided" when the attribute is absent at
  series level — and video endoscopy has no meaningful spatial frame of reference.
- Consider `--series-mode` accepting an explicit grouping later (e.g. by subdirectory
  = one procedure step), which maps onto IHE's model better than either flag.

## Remaining Open Questions

- **Frame counting on long clips** — largely resolved by F2: reading the exact sample
  count from the MP4 sample table (Phase 4.2) is O(1)-ish and avoids walking the
  bitstream. Access-unit counting is now only the fallback for raw elementary streams.
  Still worth confirming typical clip length.
- **Audio tracks** — *resolved*: audio is permitted in DICOM video (PS3.5 2026a
  8.2.5–8.2.12; Table 8.2.12-1 lists the formats allowed in MP4 and MPEG-2 TS), so
  it is kept in the bit stream, not stripped. The earlier premise that DICOM video
  IODs have no audio was wrong, and `convert` never removed it. Since D46 the probe
  reads each track's format, sampling frequency, channels, bits per sample and bit rate
  (MP4 and MPEG-TS) and checks them against 8.2.5/8.2.12; a track known to break them is **rejected** (exit 2; PS3.5
  says audio "shall follow the constraints"), with a remedy that re-encodes only the audio, e.g.
  `error: audio track 1 (AAC, 44.1 kHz, 2 channels, max 192 kbit/s) sampling frequency 44.1 kHz is not permitted for AAC; PS3.5 8.2.12 allows 48 kHz`.
  When no track's format can be identified the earlier `VideoConsole.audioCarriedLine`
  text is used. (003A,0300) gets Items only when the Channel Source (CID 3000) is named
  through the library (`VideoWorkflow.Metadata.audioChannelSource`; no CLI option, D56);
  `VideoParser` reads them back, together with the Cine attributes `VideoBuilder` writes
  (Frame Time Vector, Preferred Playback Sequencing, Image Trigger Delay, Effective Duration; D60).
- **`ImageType` value** (F5) — `ORIGINAL\PRIMARY` is the safe default for
  camera-captured video. Confirm whether any workflow needs `DERIVED`.

---

## References

Verified against the published text on 2026-09-09.

**PS3.5 — encoding constraints (the authoritative source for F2/F3/F6)**
- §8.2.5 / §8.2.6 — MPEG2 MP@ML and MP@HL
- **§8.2.7 — MPEG-4 AVC/H.264 HP@4.1**, incl. Table 8-4 (BD-compatible) and the
  container-format and Pixel-Aspect-Ratio rules
- §8.2.8 / §8.2.9 — H.264 HP@4.2 (2D / 3D), Stereo HP@4.2
- **§8.2.10 — HEVC/H.265 Main@5.1**
- **§8.2.11 — HEVC/H.265 Main 10@5.1** (BitsAllocated 16 / Stored 10 / HighBit 9)
- §A.4 — Encapsulation of Encoded Pixel Data (Item / BOT / delimiter)
- §A.4.5-A.4.7 — MPEG2 / MPEG-4 AVC / HEVC transfer syntaxes, fragmentable variants

**PS3.6 — UID registry**
- Annex A — full video transfer syntax list (the 20 UIDs of F1)

**PS3.3 — IODs and modules**
- §A.32.5 / §A.32.5.3 — Video Endoscopic Image IOD + module table (M/C/U)
- §A.32.6 / §A.32.7 — Video Microscopic / Video Photographic Image IODs
- §C.7.6.3 — Image Pixel Module (`YBR_PARTIAL_420`; `YBR_PARTIAL_422` retired)
- §C.7.6.5 — Cine Module (FrameTime 1C; CineRate/RDFR Type 3)
- §C.7.6.6 — Multi-frame Module (NumberOfFrames and FrameIncrementPointer both Type 1)
- §C.8.12 — VL Image Module (**ImageType Type 1**; LossyImageCompression Type 2)

**IHE**
- Endoscopy Image Archiving (EIA) Rev. 1.1, 2018-11-28 — §3.10.4.1.1.1 Study/Series
  UID rules (the Q4 answer); Tables 3.10.4.1.3.1-1/-2 (SOP classes and transfer
  syntaxes an endoscopy archive must support)

**Codec specifications**
- ITU-T H.262 (MPEG-2 Video), H.264 (AVC), H.265 (HEVC)
- ISO/IEC 14496-15 — AVC/HEVC file format (`avcC` / `hvcC` parameter sets)
- ISO/IEC 14496-14 — MP4 container; ISO/IEC 13818-1 — MPEG-2 Transport Stream
