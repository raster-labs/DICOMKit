# M4 service reliability completion

**24 October 2026 — all five M4 items completed locally.** Fourteen acceptance
criteria passed; the conditional future bulk-data implementation criterion is
not applicable because bulk retrieval remains unavailable. Its future gate is
retained. Work continues on `codex/dicom-2026a-milestones`, from M3 commit
`b85c281e938ac6a0505bbfae1afc1f6619e59080`. Stop before M5. Main remains unmerged.

## Completed repairs

| Item | Result | Evidence |
|---|---|---|
| NET-05-A | C-CANCEL-FIND is processed while matches are pending; FE00 ends the operation, wrong message/context cancellation is ignored, and legal association reuse remains possible. | Twelve cancellation tests include before-first-result, mid-stream, in-flight boundaries, wrong IDs/contexts, reuse and disconnect cases. |
| NET-05-B | MOVE stops initiating stores after cancellation, settles the initiated store, and returns exact remaining/completed/failed/warning counts and failed UIDs. GET uses the same receive pump and bounded cleanup. | Delayed/mixed-result Storage SCP tests, raw command captures, actual CLI and Workshop outcomes. |
| NET-09-A | Service-base OPTIONS returns negotiated WADL XML or Annex G JSON. Missing/unacceptable Accept returns 406; query/payload and unsupported-method errors are visible. CORS preflight is distinct. | Seven capability tests, 30 HTTP/CLI cases, offline WADL schema validation. |
| NET-09-B | Private and standard capability descriptions reflect implemented routes. Bulk data, rendered images, frames and thumbnails remain false/unadvertised and return 501. | All six advertised retrieval forms exercised; three real WADO CLI requests return byte-identical instances. |
| NET-10-A | Stored Part 10 files rebuild a complete index before the listener opens. Conflicts, duplicate UIDs, corrupt/unreadable files and unsafe paths fail visibly. | Seventeen durability tests and 20 real-process cases, including graceful and forced process restart, FIND/GET/MOVE and content hashes. |

[acceptance.json](acceptance.json) maps every original criterion to test methods,
case names and evidence. [verification.json](verification.json) records counts,
artifact hashes and qualification limits. The evidence folder preserves test
logs, synthetic datasets, wire captures and packaged-app observations.

## CLI and DICOMStudio behavior

A cancelled query now raises `QueryCancelledError`, retaining its partial
results. The CLI prints those results in the selected format and exits 1.
Workshop presents the same partial results, marks the execution ERROR, and
does not leave it Running. Clients release the association normally after FE00.
Code that previously treated a cancelled `QueryService` call as successful must
now handle this error and its `partialResults`.

Retrieve output includes the final remaining count. GET cancellation no longer
retries another storage-context batch, loses the remaining count, or reports a
successful retrieval/presentation-context explanation. Both single and bulk
Workshop GET paths share the corrected final-status handling.

One receive pump dispatches cancellation and storage responses while the request
worker runs. Cancellation applies to the matching active message and presentation
context. Already transmitted/in-flight pending responses are permitted before
the final response; the tests do not demand instantaneous zero additional bytes.
An initiated store is settled before a cancelled retrieve finishes. A cancelled
store has a bounded 30-second settlement deadline. If a GET store message was
only partly transmitted at the deadline, the transport closes: appending a final
response would corrupt DIMSE framing. A fully transmitted store with a silent
receiver is counted failed before FE00. Shutdown drains workers before releasing
the storage lock, and stale listener callbacks cannot join a subsequent run.

The freshly linked **DICOMStudioApp** passed **seven actual GUI cases**: empty and
partial FIND cancellation, MOVE cancellation, GET cancellation, WADO retrieval,
and FIND/GET after server restart. **Seven equivalent CLI replays** matched the
captured query identifiers or independently checked output bytes. Visible status,
partial data and cancellation counts were checked in the app. Accessibility can
truncate console text, so full GUI console byte equality is not claimed. Four
ViewModel cancellation cases separately passed exact combined-output comparisons.

There is no Workshop server-capabilities editor or cancellation button in this
scope. Standard OPTIONS is a backend-only gate. Controlled FE00 peers qualify
client outcomes; actual C-CANCEL behavior is proven separately by server wire
tests. Existing WADO, query and retrieve controls were exercised without adding
new Workshop tools.

## Durability contract and migration

The default is now `--database filesystem`; `filesystem://` is the configuration
sentinel. This mode indexes stored Part 10 files deterministically at startup.
Existing valid files remain usable after changing an old SQLite configuration to
filesystem mode. SQLite and PostgreSQL modes/URLs are explicitly refused because
those backends are not implemented. `--database none` is explicitly unindexed;
it retains files but does not promise indexed discovery. The old SQL schema and
deployment examples are marked historical/proposed.

Publication is atomic and does not overwrite an existing SOP Instance UID. An
identical dataset/transfer-syntax/SOP identity is an idempotent retransmission;
sender/receiver File Meta differences do not create a conflict. A differing
dataset preserves the original and fails. Exclusive storage ownership and path
checks prevent concurrent reindex/publication and unsafe symbolic-link traversal.
Malformed stored envelopes prevent startup instead of producing a partial index.

Envelope checks cover explicit/implicit and little/big-endian encodings,
defined/undefined sequences, UN implicit-little-endian sequence content, deflate,
and encapsulated item bounds. These checks are not full IOD or image-codec
validation. File synchronization and process-restart tests do not establish
power-loss durability on every filesystem or storage device.

## Verification results

| Gate | Passed |
|---|---:|
| DICOMWeb focused tests (XCTest + Swift Testing) | 111 |
| dicom-server tests | 101 |
| DICOMNetwork focused tests, including CLI standard rerun | 108 |
| dicom-query / dicom-retrieve / dicom-wado tests | 14 / 9 / 27 |
| DICOMStudio focused Swift Testing cases | 142 |
| **Unique focused tests** | **512** |
| Audit regressions | 30 |
| Explicitly activated process-harness test methods | 3 |
| Cancellation client campaign | 4 CLI + 4 Workshop ViewModel cases |
| Restart/durability campaign | 20 process + 3 Workshop ViewModel cases |
| Capabilities campaign | 30 HTTP/CLI cases |
| Packaged app and equivalent CLI | 7 GUI + 7 CLI replays |

These categories overlap in coverage and must not be summed into a single test
total. The normal focused run skipped five tests: three opt-in harness methods
subsequently passed in the process campaigns; two dicom-qr CLI checks passed
after building that product and rerunning the eight-test CLI standard suite.
Repeated tests are counted once. The CI script builds required CLI products
before running tests to avoid those two cold-build skips.

Independent inspection verified 46 captured DIMSE commands, executable hashes
and four restart dataset hashes. Restart GET/MOVE output retains raw dataset
SHA-256 `c5c931cdd6129bcae78830f714fa84f52577682c10156039cd6b67619c7bb963`.
The packaged WADO file is byte-identical to its synthetic fixture. App build
and source hashes are recorded separately from runtime results.

Verification exposed and repaired GET retry after FE00, misleading cancelled GET
summaries, and platform-specific `/var` path canonicalization. The latter now
uses POSIX canonicalization and retains raw-path symbolic-link checks. Capability
tests distinguish UPS creation (201) from updating an existing workitem (200).
Corrected harness-only assumptions are recorded in the relevant campaign data.

## Standard basis and limits

The frozen 2026a source identities remain in M0. Cancellation and retrieve counts
use [PS3.4 C.4](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part04/sect_C.4.html),
including [C-MOVE parameters](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part04/sect_C.4.2.html),
and PS3.7 DIMSE cancellation. Capabilities use
[PS3.18 8.9](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part18/sect_8.9.html),
Annexes G/H, and [Accept requirements](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part18/sect_8.7.7.html).
File Meta uses PS3.10. Filesystem restart persistence is an application contract;
DICOM does not mandate a SQL backend.

All new runtime evidence uses fabricated data on local macOS loopback. The
DICOMweb production component remains an embedding request router; its HTTP
listener here is test infrastructure. External PACS/providers, other operating
systems, physical printing, device power loss and full IOD/codec conformance are
unexecuted. M3's supplemental packaged UID-list/non-ASCII matching-input gate and
external integration limits remain historical open qualification limits. M0-COV-01
anonymization-profile coverage remains visible. No unrelated enhancement was added.

## Completed and pending

M0–M4 complete **35 of 68 actions**. **11 active actions remain pending**:
M5 Studio contracts (7), M6 print/printscp Workshop coverage (2), and M7 final
qualification (2). **22 actions remain deferred.** Six remaining active actions
are bug fixes. Enhancement scope remains limited to dicom-print and dicom-printscp.

The `Service reliability` workflow repeats the automated M4 gates. Remote checks
must be evaluated on the pushed commit; this report records local verification.
The completion deliverable includes the final remote snapshot. Stop before M5;
merging main requires the user's subsequent instruction.
