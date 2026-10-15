# Bounded input allocation contract

15 October 2026. Source and validation receipts accompany the released dependency
closure; this document defines the API
contract, not Mayam provider or native presentation acceptance.

## Ownership and limits

`DICOMAllocationBudget` is an explicitly injected, synchronous, thread-safe ledger.
Its default limits are encoded 128 MiB, decoded 384 MiB, staging 64 MiB, resident
384 MiB, preview 32 MiB, aggregate 1 GiB. Metadata is reported separately and shares
the staging limit. Class peaks are independent; `peakTotal` is the simultaneous peak.

The ledger, every shared owner record, and all payload storage occupy real anonymous
mappings. Admission includes page rounding before mapping. The ledger bootstrap
page is itself metadata. Each buffer owns a separate metadata control page and a
page-rounded payload; even an empty buffer retains its mapped capacities. Mapping
failure returns a scalar failure and rolls back admission. These are owned anonymous
pages, not uncharged file mappings or inferred `Data` capacities.

Budget, lease, buffer, verified source, parsed index and deferred views are move-only
values. Explicit `shareOutcome()` creates an owning alias without another backing or charge.
Copies and vector growth admit simultaneous old/new capacities. `sameBacking(as:)`
proves buffer alias identity. `capacity`, `controlByteCount` and `retainedByteCount`
report the actual retained capacities; the shared ledger bootstrap is counted once,
not once per buffer. Destruction unmaps storage before releasing its charge. A failed
unmap conservatively retains the charge rather than reporting memory as freed.

`transferOutcome(to:)` moves the complete payload charge exactly once, atomically across all
aliases, without changing the total. Its control page remains metadata until final
owner destruction. A canceled subscriber or dropped result does not release a
worker's separate retained owner. Finalizers run once before unmapping, outside the
ledger lock, and can destroy nested owners safely.

`installRetirementObserverOutcome(context:callback:)` installs one thin C callback before
the first explicit share. It runs only after the final payload/control unmaps and
ledger debit succeed, outside the ledger lock while the ledger remains pinned.
It does not run on failed unmap. This lets a host release its aggregate retained
lease at actual last-owner retirement. The caller must separately account and
retain its callback context until notification; the callback must not allocate,
block or wait for an actor. Register before constructing externally retained aliases.

## External aggregate admission

`DICOMAllocationBudget.make(limits:externalAdmission:)` accepts a concrete
`DICOMExternalAllocationCallbacks` value containing only a borrowed context pointer
and thin C function pointers. Existing construction without callbacks is unchanged.
The local ledger still enforces all its limits. The host's admission callback must
atomically reserve the complete payload and metadata/control pair in its aggregate
ledger before DICOMKit issues any mapping. All existing mapped storage uses this
path, including source/parser/codec controls, workspace, buffers and external leases.
The ledger's own bootstrap is a separate token with zero payload and one metadata
page. Resource values are stable: encoded 0, decoded 1, staging 2, resident 3,
preview 4 and metadata 5. Metadata still shares the local staging limit.

Status zero means success; other callback results are preserved as
`externalAdmissionRefused(Int32)`. Admission success writes a nonzero unique live
token; failure writes zero and acquires no reservation. Transfer must atomically
reclassify the complete payload while retaining its metadata/control charge, or
refuse without changing the aggregate ledger. No mapping occurs after a refusal.
Local refusal precedes external admission/transfer, and external refusal leaves
local live and peak counters unchanged.

`retainContext` acquires one lifetime before bootstrap admission; on refusal it
acquires none. Each successful allocation's `release` notification occurs once,
after every mapping in that token is successfully unmapped (or complete allocation
rollback). On partial unmap failure, the entire external token remains charged,
even if some components were already unmapped and debited locally. This is a
conservative aggregate quarantine, not permission to release live backing.
External reservations retain their token until the final lease owner releases it;
the caller remains responsible for tying those owners to actual external storage.

The final ledger token is released only after the ledger's own successful unmap.
Then `releaseContext` releases the acquired context lifetime, with no subsequent
context access. Complete bootstrap rollback follows the same order; bootstrap
admission refusal has no token to release. Failed rollback/unmap/mutex retirement
retains token and context ownership indefinitely. The caller must admit and retain
context storage accordingly. No retry or asynchronous cleanup is implied.

All callbacks must be thread-safe, nonallocating and nonblocking. Admission and
transfer execute under the local ledger mutex; they must not reenter that ledger.
A host must not hold an aggregate lock while invoking DICOMKit code that may
acquire it. Token release, context callbacks and existing retirement observers
execute outside that mutex. An owner's ledger reference remains alive throughout
its release and observer callbacks; the observer still precedes final ledger
retirement and therefore cannot substitute for `releaseContext`.

Read-only `DICOMByteBuffer.externalAllocationToken` and `externalAdmissionContext`
identify the exact admitted owner for host handoff without a second reservation.
`DICOMAllocationBudget.externalAdmissionContext` identifies its aggregate context.
These properties neither transfer release authority nor prolong context lifetime;
the original callback remains the only release notification, including after a
host handoff. Aliases and transfers preserve the token; a copy gets a distinct one.
A context pointer may be nil even when callbacks are enabled; token presence
distinguishes external admission. No token can be supplied or changed by a caller.

This API does not establish recoverable pthread/Swift bootstrap, host callback
allocation bounds, or complete provider/runtime acceptance. Those remain the
application's independent obligations.

`withBorrowedBytes` is a synchronous borrow. Do not let its pointer escape, mutate it,
or create an uncharged `Array`/`Data` copy and call that managed. An external GPU or
image owner must retain an explicit buffer handle through actual resource destruction;
its own wrapper/deallocator/context allocations require separate host admission.
Legacy `AlignedPixelBuffer` and Foundation bridges remain compatibility APIs.

## Worker and runtime boundary

On Darwin, `DICOMExecutionReservation` admits the current worker's entire reported
usable pthread stack and its real lease control page as metadata. Qualified source,
parser and codec overloads require it and validate the original ledger and thread.
Retain the reservation across the whole synchronous capture/parse/acquire/decode
operation, including cancellation/failure, until the worker actually returns. Never
suspend asynchronously inside this scope. A reservation for another thread or ledger
is rejected. Low-level portable APIs account their backing only; they do not silently
reserve a stack. The execution qualification is not available on Linux.

Create caller-owned worker/TLS/runtime setup, immutable options and borrowed path/
cancellation contexts before the qualified operation. Cancellation uses a thin C
function and a context borrowed only for that synchronous call. The callback must
not allocate or block. No retained source/index/frame stores the cancellation token.
Do not use `pthread_cancel` or force a worker to exit: cancellation must return
through the scalar outcome and ordinary Swift ownership cleanup.
Failures are fixed scalar values returned in explicit outcomes. Qualified calls use
`DICOMAllocationBudget.make`, buffer `allocate`, execution `reserve`, source `capture`,
`readBoundedOutcome`, deferred `*Outcome` methods and `decodeManagedPixelFrameOutcome`.
Switch over success/failure inside admitted work. Do not call `.get()` or throwing
compatibility adapters there: Swift's cold Error witness initialization allocates.
Formatting and legacy error translation belong outside the admitted core.

Qualification is for the exact supported Release compiler/OS/runtime recorded in
its receipt and normal execution without externally installed debugger/profiler/error
hooks. Read-only runtime inspection and compiled selected-branch review establish
that boundary; they do not make mutable runtime hooks immutable. Arbitrary caller
callbacks, instrumentation, kernel storage, preexisting thread setup and inaccessible
guard VM are outside operation-owned backing. This is not a process-wide OOM-survival
or universal OS/toolchain claim. RSS sampling alone does not establish this contract.

## Verified source and canonical parser

`VerifiedFileByteSource` anchors a regular-file descriptor (or duplicates a supplied
one), admits at most 256 MiB, and hashes the entire transcript in 64 KiB windows. Its
fixed scalar SHA-256 implementation retains a full digest and an admitted table of
block digests. Every later acquisition verifies each complete block and copies those
same bytes. Source controls, path and digest table are admitted mapped storage.
`identity` is a fixed 32-byte value; `.hexadecimal` is an explicit caller-side String
adapter. The path/descriptor overloads form the qualified capture boundary; URL
conversion is a caller-side Foundation adapter.

Partial reads, EINTR, EOF, cancellation, range overflow, final symlinks, replacement,
truncation, append and ordinary same-size mutation are checked. Device/inode/mode/
size/mtime/ctime and path guards preserve the prior ordinary-race contract. Source
failures invalidate all aliases; cancellation alone does not. Initial capture is not
an atomic filesystem snapshot against a hostile writer, and syscalls have no deadline
guarantee. No verified-then-unverified second read is used.

Convert caller policy to scalar `BoundedParsingOptions` before the operation.
`DICOMFile.readBoundedOutcome` requires strict full parsing and invokes the canonical
`DICOMParser` with verified windows and a mapped capture policy. There is one grammar.
Scopes, elements, duplicate membership and fragment records use admitted flat
containers; duplicate scratch is released at seal. Values/raw sequence spans are
deferred. Original logical limits, strict rejection behavior and nested raw-SQ value
accounting are preserved. A partial parse never escapes.

Implicit VR uses the generated `DataElementDictionary.primaryValueRepresentation`
switch, not its lazy descriptive dictionary. `Scripts/generate_primary_vr.py --check`
verifies the projection. Scalar explicit-VR and transfer-syntax token decoding avoid
String allocations while preserving maintained UTF-8/BOM/Unicode/NUL padding rules.

Native little-endian syntax is the strict default. Explicit allowlisting and strict
encapsulation admit the existing JPEG baseline, JPEG lossless SV1 and JPEG-LS lossless
profiles. `readFrameOutcome` uses the canonical encapsulated frame walker, validates all
frame groups, then admits and fills only the selected frame. It does not add Extended
Offset Table qualification or a permissive fallback. Source/frame/descriptor identity
and native frame-size policy remain the existing caller's responsibility.

## Codec storage and handoff

Managed JLS/JLI entrypoints require the encoded buffer and decoding budget to have
the same ledger. They validate descriptors before allocation and use the maintained
codec's caller-storage core with scalar errors and cancellation. No fallback into
an uncharged legacy codec path occurs. Existing broader legacy profiles remain
available through their compatibility APIs.

* JPEG-LS monochrome allocated16 uses a fixed 144,864-byte caller workspace and UInt16
  output, with the canonical marker grammar and prediction kernel. Mapping and color
  transform evidence preserve the narrow precision-recovery policy.
* JPEG lossless SV1 monochrome allocated16 uses a 6,160-byte caller workspace and
  little-endian UInt16 output with the canonical Huffman/prediction kernel.
* Baseline interleaved RGB8 uses a 16,384-byte inspection workspace, bounded MCU-row
  coefficient/sampling workspace and a `12 * pixelCount` arena whose visible RGB
  prefix is `3 * pixelCount`. The complete arena remains charged after handoff.
  Fixed shared numerical kernels replace opaque Accelerate workspace calls, with
  independent pixel and prior-kernel differential validation.

`ManagedDecodedPixelFrame` returns the actual descriptor, source frame index, one
optional scalar diagnostic and a consuming `DICOMByteBuffer`. Transfer that complete
backing once to resident/preview ownership and retain it through real destruction.
Do not charge only the visible RGB prefix or release controls when a request cancels.

Mayam independently owns adaptation to its existing preparation/resident lease,
strict provider tests and native presentation qualification. This library introduces
no application dependency, second loader, increased cap or smaller source envelope.
