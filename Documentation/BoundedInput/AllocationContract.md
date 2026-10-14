# Bounded input allocation work — local candidate

14 October 2026. In progress; not a release or Mayam qualification receipt.

The candidate starts at DICOMKit 2.3.1 (`cae78a752243bd033d12ee7f5d0dcc9670ecf804`)
and incorporates the retained Mayam strict-parsing and discovery patches into the
maintained parser. No Mayam checkout, cached donor, dependency pin or app artifact
is changed. Existing unbounded APIs remain available for existing callers.

## Implemented storage boundary

`DICOMAllocationBudget` is an explicitly injected, synchronous, thread-safe ledger.
Its default limits are encoded 128 MiB, decoded 384 MiB, staging 64 MiB, resident
384 MiB, preview 32 MiB, aggregate 1 GiB. Metadata is reported separately but shares
the staging limit. Class peaks are not added to infer a simultaneous total peak.

`DICOMByteBuffer` privately owns `AlignedPixelBuffer` storage. Its controlled path
reserves every anonymous mapping page before allocation. This is owned anonymous
memory, not a file mapping. Empty buffers still reserve a page. Copies reserve a
second backing; reference aliases share one owner. A one-time class transfer moves
the charge atomically without reducing the live total. Destruction unmaps storage
before releasing its lease. Cancellation does not itself release any lease.

The existing permissive `AlignedPixelBuffer` API retains its compatibility behavior;
its rounding now checks overflow. Its public pointer/Data bridge is not the bounded
API. Borrowing a bounded buffer requires a synchronous closure and forbids pointer
escape or mutation. Caller allocations inside a closure are the caller's separate
responsibility. Fixed control allowances are explicitly distinguished from measured
or intercepted Swift/Foundation heap allocations; these receipts are not RSS or a
complete process-allocation claim.

On platforms with Darwin and CryptoKit, `VerifiedFileByteSource` owns a regular-file descriptor (or duplicates a caller's
anchored descriptor). It hashes the entire admitted source, up to 256 MiB, using
64 KiB blocks and retains SHA-256 block digests plus the full transcript digest.
Every later read verifies the complete block and copies from those exact immutable
bytes. It handles partial reads, EINTR, EOF, cancellation and range overflow.
Device/inode/mode/size/mtime/ctime and path checks detect ordinary source changes.
A detected source failure permanently invalidates retained views. This preserves
the previous snapshot's ordinary-race contract; it does not promise an atomic
filesystem snapshot against a hostile writer during initial capture. Filesystem
syscalls have no deadline guarantee.

`DICOMFile.readBounded(from:options:)` requires strict full parsing. It uses the
canonical `DICOMParser` with a verified cursor and a storage capture policy; there
is no second DICOM grammar. The result is `BoundedDICOMFile`, not a materialized
`DICOMFile`. Elements, sequence scopes and fragments live in controlled flat
containers. Values and raw SQ spans remain deferred. Logical strict limits still
count the same leaf and nested raw-SQ lengths as before. Duplicate detection has
controlled backing and is discarded when parsing finishes. No partial parse escapes.
Strict parsing defaults to native little-endian transfer syntaxes. Compressed input
requires an explicit `allowedTransferSyntaxUIDs` allowlist and
`strictEncapsulation`; the maintained initial compressed profiles are JPEG
baseline, JPEG lossless SV1 and JPEG-LS lossless.

Implicit VR uses an allocation-free primary-VR projection in the maintained
`DataElementDictionary`, generated from its authoritative resource. The descriptive
dictionary's lazy strings, arrays and hash table are not loaded by this lookup.
`Scripts/generate_primary_vr.py --check` verifies that the projection is current.
The bounded UID token reader preserves UTF-8 validity and legacy Unicode/NUL
padding without materializing an arbitrarily padded UI value.

Deferred value/frame acquisitions throw on source changes, cancellation or failed
admission. `readFrame` uses the same canonical frame walker as
`EncapsulatedPixelData.makeFrameIndex`, validates the complete map, then admits and
fills only the selected frame. It does not infer or add Extended Offset Table
qualification to the initial bounded profile. Native frame-size/descriptor and
compressed precision/profile qualification remain the existing caller's authority.

## Still required before provider integration

This is not yet the full input-to-retained-image allocation contract. In particular,
legacy codec APIs do not become accounted merely because their input is accounted.
No adapter may silently bridge this result into an uncharged codec/Data/Array path
and call the result bounded.

The local codec branches now provide synchronous caller-storage payload APIs:

* JLSwift borrows encoded spans, stores reachable mapping values and adaptive
  contexts in fixed caller scratch, and runs the canonical monochrome kernel
  directly into UInt16 output. Restart regions are decoded serially without an
  image-sized Int plane or retained array of regions.
* JLISwift lossless uses its existing prediction/Huffman kernel with little-endian
  UInt16 destination storage. Baseline RGB uses MCU-row coefficient strips, shared
  IDCT scratch, backward in-place chroma expansion and tiled color conversion.
  It retains one `12 * pixelCount` arena whose visible RGB prefix is `3 * pixelCount`.
  For widths up to 16,384 and sampling factors 1...4, the reported row workspace is
  at most 10,746,720 bytes. The full arena remains charged when output is retained.
* `decodeManagedPixelFrame` on the existing codec owners reuses descriptor/syntax
  validation and returns `ManagedDecodedPixelFrame`. It supports the current Mayam
  monochrome allocated16 JPEG-LS/lossless and interleaved baseline RGB8 profiles.
  Input storage and decoding must use the same `DICOMAllocationBudget` instance;
  a mismatched budget is rejected before inspection or allocation.
  Broader legacy codec profiles remain available only through their existing APIs;
  managed calls refuse unsupported profiles without an uncharged fallback.
* JPEG-LS inspection reports mapping selection, mapping presence and color
  transformation so precision recovery uses the same narrow policy as the legacy
  descriptor-bearing API. Borrowed parser storage must not imply absent mappings.

**Remaining acceptance blocker:** fixed Swift/CryptoKit/lock/error/control
allowances require independent qualification and a defensible admission/lifetime
mechanism. The backend payload APIs explicitly exclude these allocations. Lazy ICC
profile construction and DCT matrices are shared process-lifetime storage. A finite
observed malloc peak or an arbitrary 64 KiB allowance does not prove a complete
maximum or recoverable allocation failure. These receipts must remain labeled as
controlled payload receipts until this gap is closed.

A standalone optimized allocator probe must trace cold/warm initialization,
concurrency, transient allocations, retained aliases, errors and late cancellation;
its inventory must reconcile against allocator-zone enumeration and an independent
allocation trace. Exact supported runtime/toolchain/allocator versions and the
accounting metric must be recorded. Probe instrumentation cannot itself pre-admit
Swift runtime allocations or turn fatal Swift allocation failure into a thrown error.

Mayam independently owns provider integration and native qualification. The
existing runtime lease must receive the complete retained backing exactly once;
no dependency pin or production path is changed by this candidate.

No cap increase, smaller source envelope, permissive fallback or second input loader
is proposed. Backend branches are local; no publication is authorized for this work.

## Reproducing the local dependency closure

`LocalSourceClosure.json` records the exact local codec revisions and the four
unchanged transitive pins. The DICOMKit manifest still names the published codec
releases; this candidate must be built with explicit SwiftPM edit overrides until
the codec changes receive an authorized upstream publication. For an isolated
scratch directory already resolved from the published baseline:

```sh
swift package --scratch-path /absolute/scratch edit JLSwift --path /absolute/jls-clone
swift package --scratch-path /absolute/scratch edit JLISwift --path /absolute/jli-clone
```

Check both codec HEADs against the manifest first. Preserve the same scratch,
cache/config and module-cache paths for subsequent build/test commands. An edited
workspace-state file is part of the local qualification evidence; released
`Package.resolved` pins alone do not prove the candidate was compiled. There are no
local-path dependencies or unpushed revisions silently substituted into Mayam.
The incorporated strict/discovery patch hashes are recorded to prevent accidental
double application when a future qualified candidate replaces Mayam's donor.
