# Strict compressed-frame decoding

This change addresses the DICOMKit compression handoff from Mayam. It is a finite JPEG/JPEG-LS decoding change; registry membership is not a claim that every modality or encoding is qualified.

## Ownership

- `EncapsulatedPixelData.makeFrameIndex` is the single frame-to-fragment mapper, including the older `frameData(at:)` API. Partial/excess tables, invalid boundaries, overlapping Basic/Extended tables, unrepresentable offsets and ambiguous multiframe layouts fail closed.
- `ParsingOptions.strictEncapsulation` validates the complete PS3.5 2026a A.4 envelope during full Pixel Data parsing. Existing tolerant parsing remains the default for compatibility. Use a finite `allowedTransferSyntaxUIDs` set and explicit byte/fragment budgets for admission. Metadata-only reads do not validate pixel payloads.
- `JLICodec` and `JPEGLSCodec` check the effective encoded header against DICOM metadata and resource policy before calling the sample decoder. JPEG registry instances enforce their transfer syntax and SV1 predictor. `JPEGFrameEnvelope` validates a complete selected codestream and permitted padding. No fragment-per-frame guessing remains for ambiguous layouts.
- `ImageCodec.decodePixelFrame` returns bytes, their actual descriptor, and the source frame index. JPEG DCT output reports RGB; SOF3/JPEG-LS preserve component meaning. The existing convenience APIs use the result. The aligned JPEG path validates before allocating destination storage.
- JLISwift owns complete JPEG stream parsing, bounded sample allocation, explicit raw RGB DCT decoding, and rejection of unsupported output-color relabeling. Its XYB path remains intact.
- JLSwift owns complete JPEG-LS stream parsing and bounds on effective LSE-expanded dimensions and all decoded Int sample planes.

## Released dependencies

DICOMKit 2.3.1 uses exact maintained stable codec releases:

- [JLISwift 0.5.2](https://github.com/raster-labs/JLISwift/releases/tag/v0.5.2)
- [JLSwift 0.9.3](https://github.com/raster-labs/JLSwift/releases/tag/v0.9.3)

Both are maintenance releases from their respective stable lines. They exclude the unrelated shared-storage release-candidate APIs. No local decoder implementation is copied into DICOMKit and no editable dependency override is required. Application qualification must use these published pins. JLISwift 0.5.2 corrects full-resolution integer YCbCr chroma sample positioning; the unchanged maximum lossy RGB tolerance is three code values against the independent oracle.

The DICOMKit release is based on maintained main, which also contains the changes accumulated since 2.2.16; it is a new minor release rather than a codec-only backport onto the old application pin.

## Qualification

### Explicit JPEG-LS precision recovery

`JPEGLSCodec.PrecisionPolicy.useCodestreamForUnsignedMonochrome` enables a bounded
receiver recovery through `decodePixelFrame` and header-only `inspectFrame`. An unsigned monochrome NEAR=0
codestream with precision 16 may be decoded in a source 16-bit container whose
Bits Stored is smaller. The returned descriptor reports Bits Stored 16 and High
Bit 15, and `diagnostics` includes `sourcePrecisionMismatch`. The original source
descriptor is unchanged. Every decoded bit is retained, including values above
the range suggested by the source metadata; this is never masking or clamping.

`inspectFrame(_:descriptor:frameIndex:)` returns `JPEGLSCodec.FrameInfo` with the
same actual descriptor, source frame index and diagnostics. It shares the decode
path's envelope, header, policy, syntax and allocation guards, allowing indexing
and loading to agree. Inspection does not decode entropy data or certify sample
validity; a later decode may still reject damaged sample data.

The default policy and Data-only `decodeFrame` API still require matching source
precision. Dimensions, component count, frame identity, complete envelopes and
allocation limits remain enforced. This recovery excludes signed samples,
color, near-lossless data, point transforms, mapping tables and color transforms.
The JPEG-LS allocation budget also bounds its intermediate `Int` sample planes;
applications must explicitly choose adequate finite limits for their admitted
image dimensions, without treating the limit as a process-RSS guarantee.

PS3.5 2026a 8.2.3 requires consistency between attributes and the compressed
stream and imports the receiver-recovery notes of 8.2.1. Those notes support using
encoded characteristics when metadata conflicts; recovery does not certify the
source as conformant. A 16-bit coding range can contain only values below 4096
without becoming a 12-bit codestream (ITU-T T.87 4.3.2 and C.2.4.1.1).
Applications must retain source metadata separately, explicitly handle the
diagnostic and actual descriptor, and qualify their sample/display interpretation.
Native export requires its own consistent attributes and IOD validation.

`JPEGLSPrecisionRecoveryTests` uses independent synthetic CharLS streams with both
12-bit-range values and values through 65535. It verifies exact bytes, unchanged
source metadata, actual descriptor/diagnostics, strict defaults and rejected
unqualified transformations. Regenerate with
`Scripts/generate_precision_recovery_fixtures.py` using the same oracle environment.

`StrictCompressedFrameTests` exercises header/UID/predictor mismatches, exact sample widths, overflow/budgets, LSE dimensions, missing EOI, concatenation, offset boundaries and nonsequential frame access. `StrictEncapsulationTests` covers malformed Item envelopes and cumulative budgets.

`IndependentCompressedFrameTests` contains ten synthetic fixtures: Pillow/libjpeg RGB/YBR JPEG; analytically constructed 8/12/16-bit SOF3 streams independently decoded by libjpeg; and CharLS 8/12/16-bit monochrome plus interleaved/noninterleaved color JPEG-LS. Lossless output is byte-exact; baseline color allows a maximum three-code-value difference from libjpeg. Each color case also checks planar output. Fixtures contain no patient data.

Regenerate using Python 3.12 and `oracle-requirements.txt`, then run `Scripts/generate_strict_codec_fixtures.py` from the repository root. The external libraries are qualification dependencies only; no DCMTK is executed.

## Deliberate limits

JPEG progressive/arithmetic processes, DNL dimensions, lossless JPEG with noninterleaved scans or nonzero point transform, and ambiguous frame delimiters are rejected by this finite path. JPEG2000, HTJ2K, RLE, video and all other families retain their own qualification status. Application integration, representative vendor coverage, native image acceptance and live PACS retrieval remain separate gates.

References: [DICOM PS3.5 2026a A.4](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/sect_A.4.html), [8.2.1](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/sect_8.2.html), ITU-T T.81 Annex B and T.87 Annex C.
