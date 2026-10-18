# Verified source work metrics

`VerifiedFileByteSource.workMetrics` returns a `VerifiedSourceWorkMetrics`
value. It is `Sendable` and contains no retained source, ledger, pointer or callback.
Every explicit source alias observes the same accumulated counters.

## Measured work

- `readNanoseconds`, `readCalls` and `bytesRead` cover actual `pread` calls.
  Retries, errors and the capture EOF probe each count as a call. Only positive
  read results add bytes, including complete blocks reread for verification.
- `hashNanoseconds`, `hashUpdates` and `hashFinalizations` cover the fixed-storage
  SHA-256 implementation. Capture updates the full transcript and per-block
  digest; later reads hash the verified block. Internal SHA byte movement is
  included in hashing, not counted again as a separate copy.
- `copyNanoseconds`, `copyCalls` and `bytesCopied` cover the explicit admitted path
  copies, stored 32-byte block digests and copies to the requested output range.
  Allocator zeroing, digest comparison, stat/open/close, locking, decoding and
  caller work are outside these durations.

One `CLOCK_MONOTONIC` clock supplies nanoseconds. Clock reads preserve `errno`,
including across interrupted reads. A zero elapsed duration is valid. Arithmetic
saturates at `UInt64.max`; overflow, a failed clock query or a backward sample
permanently sets `isValid` to false. Do not use invalid metrics for timing claims.
This flag does not express source validity or operation success.

Capture accumulates fixed scalar stack state and publishes it in the existing
admitted source header. Later operations merge fixed scalar deltas under the
header's existing mutex, without holding that mutex over I/O or caller callbacks.
The header's actual stride remains part of metadata admission. There is no
separate heap ledger and reading a snapshot does not extend storage lifetime.

Read a snapshot after the synchronous operation returns for its complete totals.
A snapshot during an operation can exclude unfinished local deltas. Completed
work remains counted if the operation fails or is cancelled. Failed capture
returns no source and therefore no observable snapshot. Concurrent durations
are additive and may overlap in wall time; they are not an end-to-end latency.

## Validation boundary

`VerifiedSourceWorkMetricsTests` covers capture/EOF/short reads and retries,
explicit copies, alias accumulation, concurrent readers, failed/cancelled work,
last-alias lifetime, invalid clocks, saturation and metadata admission/refusal.
The existing bounded parser and allocation-failure tests remain applicable.

After building the actual Release package, run
`Scripts/probe_verified_source_metrics.sh <evidence-directory>` to link its
optimized objects into the maintained allocation probe. It checks cold/hot
capture, reads and snapshots with positive allocator controls, exact admitted
payload/control capacities, mapping counts and final retirement. It records
object/source hashes; the invoking build receipt must bind those objects to the
candidate source manifest. The test-only interposer and caller-owned callback
fixture are not production library code.

These checks do not qualify arbitrary caller callbacks, worker/bootstrap stack
admission, whole-program allocation behavior, application integration, native
presentation or timing-performance targets. Existing immutable release evidence
remains valid only for its recorded inputs.
