# R3 — PR #233 coverage pipeline repair

Authorized 31 October 2026: inspect current CI, repair remaining failures,
verify, update documents and push `codex/dicom-2026a-milestones`. Main merge
remains reserved for the user. The item ledger stays at 49 completed / 19
deferred; Pages deployment remains user-deferred.

Starting head: `f66264efd8529b5ca6ac05109affaddf80e664f2`.
Product sources and Swift test sources are unchanged from the accepted R2
source `3be6b6ef5de2210016fbb45aef2e96bcabf74ba2`. The
[input comparison](evidence/input-changes.json) identifies only three changed
CI inputs: the scheduled workflow, its report generator and report controls.

## Remaining failure

All 11 PR workflows passed at the starting head. The separate
[comprehensive run 41183009976](https://github.com/raster-labs/DICOMKit/actions/runs/41183009976)
failed after **15,825 reported Debug tests with 57 XCTest skips and no failed
test summaries**, plus one optimized source-envelope declaration covering all
five cases. SwiftPM returned exit 1 because
`.build/out/Products/Debug/codecov` did not exist. Its artifact contained logs
and reports but no exported coverage. The
[original report](evidence/remote-test-report.json) correctly retained the
process failure despite passing assertions. The five R2 failures are fixed;
this run does not establish successful coverage execution.

A fresh isolated package reproduced the same missing-directory failure with
`swift test --enable-code-coverage list` followed by
`swift test --enable-code-coverage --skip-build`. Both of its test assertions
passed, but the process exited 1. Explicitly preparing it with
`swift build --build-tests --enable-code-coverage` made the subsequent test
process exit 0 and produce nonempty profdata and LLVM JSON. See the
[reproduction receipt](evidence/coverage-reproduction.json) and its four logs.
This is an observed Swift 6.4 preparation defect, not a DICOM-standard change.

## Repair

- Explicitly build instrumented tests before discovery; discover and execute
  them with `--skip-build`. Keep the complete Debug execution and separate
  optimized source-envelope execution.
- Derive the coverage directory from SwiftPM's binary path, constrain it to
  this checkout's `.build`, and remove old profiles before execution. A cached
  profile cannot satisfy the new run's evidence requirement.
- Require nonempty `default.profdata`, valid LLVM coverage JSON and executed
  functions under this checkout's production `Sources` directory. Record file
  hashes, sizes and executed source/function counts. Missing, malformed,
  unexecuted or foreign-source coverage fails the report, even with green tests.
- Save a successfully prepared build cache even if later execution/reporting
  fails. Restore still rebuilds current inputs and resets profiles; it does not
  bypass any test or coverage gate.

Twelve reporting controls pass, including the existing checks for earlier
product failures, incomplete/empty selections and unsuccessful process exits.
Workflow YAML parses successfully and `git diff --check` passes.

## Verification and publication

Local full-suite verification with the repaired sequence is in progress.
The new remote run will be recorded after the repair is pushed. These pending
checks are not counted as passed. See the verification receipt for the final
source-bound result when available.

The pre-documentation repository scan checked 7,521 tracked files and found
zero prohibited DICOM payloads. The R2 history boundary still applies: older
commits, main and historical Actions artifacts were not purged. No new native
GUI, physical-printer, device or optional external-system qualification is
claimed. No merge, auto-merge or Pages deployment is performed.
