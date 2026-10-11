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

DICOMKit 2.3.0 uses exact maintained stable codec releases:

- [JLISwift 0.5.1](https://github.com/raster-labs/JLISwift/releases/tag/v0.5.1)
- [JLSwift 0.9.3](https://github.com/raster-labs/JLSwift/releases/tag/v0.9.3)

Both are maintenance releases from their respective stable lines. They exclude the unrelated shared-storage release-candidate APIs. No local decoder implementation is copied into DICOMKit and no editable dependency override is required. Application qualification must use these published pins.

The DICOMKit release is based on maintained main, which also contains the changes accumulated since 2.2.16; it is a new minor release rather than a codec-only backport onto the old application pin.

## Qualification

`StrictCompressedFrameTests` exercises header/UID/predictor mismatches, exact sample widths, overflow/budgets, LSE dimensions, missing EOI, concatenation, offset boundaries and nonsequential frame access. `StrictEncapsulationTests` covers malformed Item envelopes and cumulative budgets.

`IndependentCompressedFrameTests` contains ten synthetic fixtures: Pillow/libjpeg RGB/YBR JPEG; analytically constructed 8/12/16-bit SOF3 streams independently decoded by libjpeg; and CharLS 8/12/16-bit monochrome plus interleaved/noninterleaved color JPEG-LS. Lossless output is byte-exact; baseline color allows a maximum three-code-value difference from libjpeg. Each color case also checks planar output. Fixtures contain no patient data.

Regenerate using Python 3.12 and `oracle-requirements.txt`, then run `Scripts/generate_strict_codec_fixtures.py` from the repository root. The external libraries are qualification dependencies only; no DCMTK is executed.

## Deliberate limits

JPEG progressive/arithmetic processes, DNL dimensions, lossless JPEG with noninterleaved scans or nonzero point transform, and ambiguous frame delimiters are rejected by this finite path. JPEG2000, HTJ2K, RLE, video and all other families retain their own qualification status. Application integration, representative vendor coverage, native image acceptance and live PACS retrieval remain separate gates.

References: [DICOM PS3.5 2026a A.4](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/sect_A.4.html), [8.2.1](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/sect_8.2.html), ITU-T T.81 Annex B and T.87 Annex C.
