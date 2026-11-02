# R4 — PR #233 final CI review and print failure reporting

Authorized 2 November 2026: inspect PR #233 and comprehensive CI, repair
remaining failures, verify, update documents and push the same milestone
branch. Starting head: `88edcc7b788a99b23e5847156bbc61707bd70ba4`.
Main merge remains reserved for the user; Pages remains deferred. The original
item ledger stays at 49 completed / 19 deferred.

## CI findings

The [comprehensive run 41191992135](https://github.com/raster-labs/DICOMKit/actions/runs/41191992135)
**passed** on `31d7609b`: 15,825 reported Debug tests, zero failed summaries,
57 XCTest skips, all five optimized source-envelope cases and valid coverage
export. The merged profile and JSON export hashes match the retained artifact;
the archive digest and ZIP CRC also verify. Its report records 7,761 executed
functions in 291 production source files. See the [test report](evidence/comprehensive-test-report.json)
and [artifact verification](evidence/comprehensive-artifact-verification.json).
The selected run intentionally skipped memory, performance, matrix and
dependency-update jobs. Coverage presence is verified; complete export for
every package target is not claimed.

Ten of eleven PR workflows passed on `88edcc7b`; the Print Workshop job failed
in `PrintEmulatorEndToEndTests.testColorJobProducesAColorFilm` after 32.140
seconds with an ARTIM response timeout. The original log does not identify
whether negotiation or release was waiting. Its XCTest result was 379
reported / three skipped / one failed; a later Swift Testing product passed
84 tests. The job correctly exited 1, but its last-100-lines diagnostic omitted
the actual earlier XCTest error. See [initial CI snapshot](evidence/remote-initial.json)
and [original failure](evidence/original-print-failure.json).

## Repair and investigation

`Scripts/verify_m6.sh` now prints earlier error/failure lines before the final
log tail. It still fails on the original command exit and still requires the
expected suite markers. Two controls verify that an early XCTest failure
remains visible despite 150 later successful lines, and that a green summary
without the required suite cannot pass. The first control fails with the old
script; both pass after the repair. All 58 audit controls pass.

The transport timeout did not recur in 20 complete local repetitions of all
seven emulator end-to-end tests: **140 executions, zero failures or skips**.
The subsequent full Print Workshop check also passed. These results do not
establish the timeout's root cause. No product behavior, timeouts, test
assertions or retry policy is changed. The one manual GitHub retry also failed,
in `PrintConformanceLoopbackTests.testColorImageRoundTripsThroughThePlanarWireLayout`
after 32.583 seconds. See [retry failure](evidence/print-retry-failure.json).
The timeout therefore remains unresolved. Both colour-print tests now print
workflow phases, retained by the repaired failure reporter, to distinguish
negotiation from release on the next GitHub execution. Three network and seven
emulator tests also pass under a constrained cooperative task pool locally.

## Verification

| Local check | Result |
| --- | --- |
| dicom-print CLI tests | 20 passed |
| dicom-printscp CLI tests | 20 passed |
| Network print/DIMSE tests | 410 passed |
| Print library | 463 reported, zero failures/skips |
| DICOMStudio M6 | 24 reported, zero failures, one opt-in campaign skip |
| Complete Print Workshop selection | **937 reported, zero failures, one skip** |
| Audit controls | 58 passed, including the two reporting controls |
| Repeated emulator group | 20 runs × seven tests; 140 executions passed |

The repetition, focused selection and comprehensive suite overlap and are not
added into a unique-test total. See [local report](evidence/local-print-report.json),
[repetition hashes](evidence/print-repeat-verification.json) and
[reporting regression](evidence/reporting-control-verification.json).

All production sources, package files, scheduled workflow, toolchain
setup and coverage-reporting controls are unchanged from the successful
comprehensive run. Of the 2,066 recorded R3 inputs, 2,063 are unchanged; the
M6 reporting script and two test files change, and one Python control file is added.
The two Swift test changes add phase diagnostics without changing assertions. The
[input comparison](evidence/input-comparison.json) binds that reuse. The
complete comprehensive suite is not needlessly rerun for this reporting-only
repair; the affected runner and its controls receive fresh verification.

Remote retry and publication results are recorded in the verification receipt.
At report preparation, both the original Print Workshop attempt and its one
retry have failed. The instrumented GitHub run is the next diagnostic gate;
post-push checks must be associated with the actual published revision.

The [final tracked-tree scan](evidence/no-dicom-final.json) covers this repair
and its documents. A [fresh remote scan](evidence/remote-dicom-verification.json)
found zero DICOM payloads in the milestone branch's 7,539 committed entries.
Remote main still contains `Tests/DICOMStudioTests/Fixtures/syn-ct.dcm`, and the
reachable pre-cleanup ancestor still contains the 2,043 removed payloads.
Other remote branches and other repositories were not content-scanned. No
payload content or patient attributes are copied into this evidence.
Older Git objects, main and historical Actions artifacts remain outside the
prior cleanup scope. No new native GUI, physical
printer, hospital-system or all-platform qualification is claimed. No main
merge, auto-merge or Pages deployment is performed.
