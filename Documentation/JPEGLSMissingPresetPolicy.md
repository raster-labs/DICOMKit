# JPEG-LS missing preset policy

`JPEGLSCodec` defaults to `missingPresetPolicy: .requireStandardDefaults` in
both public initializers. When an LSE preset-coding-parameters segment is absent,
a failed standard-default decode remains a failure. Direct low-level callers do
not silently insert alternate thresholds and retry an untrusted stream.

Two explicit compatibility profiles are available for legacy 13–16-bit lossless
(`NEAR = 0`) streams that omitted `min(MAXVAL, 4095)` clamping in ITU-T T.87
Table C.2 without emitting an LSE segment:

```swift
// Post-failure fallback retry (used by CodecRegistry.shared for JPEG-LS Lossless .80):
let fallbackCodec = JPEGLSCodec(
    decodingSyntax: .lossless,
    missingPresetPolicy: .allowLegacyUnclampedRecovery
)

// Deterministic pre-decode selection for streams independently identified as
// originating from a legacy unclamped encoder (e.g., DICOMKIT_0.5.0 or dcm4che-1.4.x / JAI clib_jiio):
let preferredLegacyCodec = JPEGLSCodec(
    decodingSyntax: .lossless,
    missingPresetPolicy: .preferLegacyUnclampedParameters
)
```

`CodecRegistry.shared` registers `TransferSyntax.jpegLSLossless` (`1.2.840.10008.1.2.4.80`)
with `.allowLegacyUnclampedRecovery` while keeping `TransferSyntax.jpegLSNearLossless`
(`1.2.840.10008.1.2.4.81`) on `.requireStandardDefaults`. When `DICOMFile` extracts
pixel data via `CodecRegistry` and File Meta Information `(0002,0013) Implementation Version Name`
matches a known legacy unclamped implementation (`DICOMKIT_0.5.0`, `dcm4che-1.4.*`,
`clib_jiio`, `JAI_IMAGEIO`), it automatically upgrades `.allowLegacyUnclampedRecovery`
to `.preferLegacyUnclampedParameters` so unclamped thresholds are applied before primary
decoding, preventing silent pixel corruption when standard thresholds happen to reach
`EOI` without a bitstream error.

Whenever a frame is decoded using synthesized legacy unclamped preset parameters,
`DecodedPixelFrame.diagnostics` (and `ManagedDecodedPixelFrame.diagnostic` when no
prior precision diagnostic is set) records
`.legacyUnclampedPresetRecovered(encodedPrecision:)`.

This setting is independent of source/codestream precision recovery. It applies only
to eligible 13–16-bit lossless (`NEAR = 0`) streams without mapping tables, point
transforms, or HP color transforms. Existing explicit LSE parameters always take
precedence. Cancellation, resource limits, frame identity and DICOM padding checks
still apply. The standard parameter definitions are in
[ITU-T T.87](https://www.itu.int/rec/T-REC-T.87-199806-I/en), Annex C.
