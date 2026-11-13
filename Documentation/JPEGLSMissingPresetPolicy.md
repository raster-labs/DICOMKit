# JPEG-LS missing preset policy

`JPEGLSCodec` now defaults to `missingPresetPolicy: .requireStandardDefaults` in
both initializers. When an LSE preset-coding-parameters segment is absent, a failed
standard-default decode remains a failure. The codec no longer silently inserts
alternate thresholds and retries an untrusted stream.

The opt-in compatibility profile remains available for independently identified
legacy encoders:

```swift
let codec = JPEGLSCodec(
    decodingSyntax: .lossless,
    missingPresetPolicy: .allowLegacyUnclampedRecovery
)
```

This setting is independent of source/codestream precision recovery. It permits
retrying eligible 13–16-bit streams with the historic unclamped thresholds. It
must not be enabled for strict admission merely because standard decoding failed:
successful retry alone cannot establish the source encoder's intended parameters
or image integrity. Existing explicit LSE parameters always take precedence.
Cancellation, resource limits, frame identity and DICOM padding checks still apply.

Applications using the default codec or registry will now reject nonstandard
missing-LSE legacy streams that v3.1.0 automatically recovered. Callers requiring
that compatibility must opt in deliberately. No dependency version or normal
JPEG-LS encoding behaviour changes.

The regression was isolated to DICOMKit's automatic retry: the unchanged SwiftJLS
qualified decoder rejected the external negative fixture with `invalidEntropy`.
That establishes a strict-admission bypass; it does not prove the fixture's
original encoding intent or a SwiftJLS end-of-stream defect. Private fixture bytes
are not included in the repository.

Six synthetic regression cases cover default rejection, exact opt-in recovery,
normal streams, explicit LSE precedence, truncation, cancellation and allocation
release. Existing precision, padding, budget and malformed-envelope tests remain
applicable. The standard parameter definitions are in
[ITU-T T.87](https://www.itu.int/rec/T-REC-T.87-199806-I/en), Annex C.
