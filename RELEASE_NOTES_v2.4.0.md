# DICOMKit 2.4.0

DICOMKit adds explicit allocation ownership for verified source windows, strict
full parsing, deferred values/frames, and selected JPEG/JPEG-LS decoding. The
existing parser and numerical kernels remain canonical.

- `VerifiedFileByteSource` preserves the 256 MiB source envelope with incremental
  SHA-256 and verified 64 KiB windows; later acquisition verifies and copies the
  same bytes. Mutation, replacement, truncation, EOF and cancellation remain checked.
- `DICOMAllocationBudget`, move-only owners and explicit sharing account for actual
  mapped payload/control capacities, simultaneous vector growth, copies and final
  destruction. Default class/total limits remain unchanged.
- Nonthrowing outcome APIs avoid cold Swift Error witness initialization inside
  qualified work. `DICOMExecutionReservation` admits a Darwin worker's full stack;
  caller setup, callbacks and exact compiler/runtime conditions remain explicit.
- Final-retirement observers run once after successful final payload/control unmap
  and ledger debit, outside the lock with the ledger pinned. Failed unmap retains
  charge and suppresses notification. Callback context must not be accessed after
  its final notification store.
- Caller-owned codec storage supports JPEG Baseline RGB, JPEG Lossless SV1 monochrome
  and JPEG-LS monochrome profiles. Legacy throwing/Foundation APIs remain available.
- `dicom-info --bounded-summary` exposes strict verified source/index inspection and
  its backing receipt in text or JSON. It excludes CLI formatting, runtime and stack.
- CLI validation test subprocess handling no longer deadlocks on a full stderr pipe.

The complete allocation contract is qualified only for the recorded Release source,
compiler and normal runtime profile. It is not a total-process RSS guarantee,
arbitrary-instrumentation claim, process-wide OOM recovery guarantee, Mayam provider
acceptance or clinical validation. The source reader is not an atomic snapshot
against a hostile writer. See `Documentation/BoundedInput/AllocationContract.md`.

Final qualification receipts and immutable codec commit pins are pending.
