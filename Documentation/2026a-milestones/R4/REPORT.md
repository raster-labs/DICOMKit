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
The timeout's root cause remains unresolved. Both colour-print tests now print
workflow phases, retained by the repaired failure reporter, to distinguish
negotiation from release on the next GitHub execution. Three network and seven
emulator tests also pass under a constrained cooperative task pool locally.
Five subsequent repetitions of the complete network/print-library selections
passed 4,365 reported test executions with zero skips. The
[first instrumented GitHub Print Workshop run](https://github.com/raster-labs/DICOMKit/actions/runs/41396662562)
passed at `09db627d`: 937 reported tests, zero failures, four skips and 58 audit
controls. The four skips are three unavailable DCMTK peer tests and the opt-in
Workshop campaign. Its [retained artifact report](evidence/remote-print-success-report.json)
verifies the digest, CRC and every test product's summary. This passing run
does not identify or repair a demonstrated transport root cause.
The separate [PR-triggered Print Workshop run 41396668863](https://github.com/raster-labs/DICOMKit/actions/runs/41396668863)
also passed on the same diagnostic commit.

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
The [broader repetition receipt](evidence/product-repetition-verification.json)
binds all ten later product logs. No failed-run retry policy is introduced.

All production sources, package files, scheduled workflow, toolchain
setup and coverage-reporting controls are unchanged from the successful
comprehensive run. Of the 2,066 recorded R3 inputs, 2,063 are unchanged; the
M6 reporting script and two test files change, and one Python control file is added.
The two Swift test changes add phase diagnostics without changing assertions. The
[input comparison](evidence/input-comparison.json) binds that reuse. The
complete comprehensive suite is not needlessly rerun for this reporting-only
repair; the affected runner and its controls receive fresh verification.
The documentation-only publication follow-up is bound by 2,068 input hashes,
including the unchanged tracked dependency lockfile separately checked against
the comprehensive source. It changes no application, test, script or workflow
input after diagnostic commit `09db627d`.

Remote retry and publication results are recorded in [verification](verification.json).
The original Print Workshop attempt and its one retry failed; both instrumented
Print Workshop runs passed. At this [documentation checkpoint](evidence/remote-diagnostic-results.json),
six PR workflows passed and five remained queued/in progress. Post-push checks must be
associated with the actual published revision; historical failures remain
visible even if a later run passes.

The [final tracked-tree scan](evidence/no-dicom-final.json) covers this repair
and its documents. A [fresh remote scan](evidence/remote-dicom-verification.json)
found zero DICOM payloads in the milestone branch's 7,539 committed entries.
Remote main still contains `Tests/DICOMStudioTests/Fixtures/syn-ct.dcm`, and the
reachable pre-cleanup ancestor still contains the 2,043 removed payloads.
The subsequent [all-branch inventory](evidence/remote-all-branches-dicom-summary.json)
content-scans all **417 remote branch heads** from the recorded GitHub snapshot.
It confirms **403 Part 10 file occurrences across 55 heads**, representing
**25 distinct blobs and 24 repository paths**. The milestone head `09db627d`
has zero findings across 7,554 entries. Main still has the fixture above;
other heads retain older CLIParity fixtures and round-trip corpus files.
The inventory identifies every affected branch, commit and path with hashes,
without copying payload contents or patient attributes. Patient identity or
anonymization is not classified. Tags, Actions artifacts and other repositories
are outside this scan; no account-wide absence claim is made.
Older Git objects, main and historical Actions artifacts remain outside the
prior cleanup scope. No new native GUI, physical
printer, hospital-system or all-platform qualification is claimed. No main
merge, auto-merge or Pages deployment is performed.
