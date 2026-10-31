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
This is a workflow preparation defect observed with Swift 6.4, not a
DICOM-standard change.

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

**Local full-suite and coverage verification passed** on repair commit
`31d7609bb2f735b7e85c1acc64c587d203059fe7`, using macOS 27.0.1 arm64,
Xcode 27.0 and Apple Swift 6.4. The publication follow-up changes documentation
and evidence only. All 2,066 source/test/package/script/workflow input hashes
match the tested repair; 2,063 are unchanged from R2 and the three changed
CI inputs are bound by the input comparison.

| Check | Result |
| --- | --- |
| Explicit instrumented build and test discovery | Passed |
| Complete Debug execution | **15,825 reported tests; zero failures; 54 XCTest skips** |
| Optimized source envelope | One declaration, all five boundary cases passed |
| DCMTK print interoperability | Three executed passes, included in Debug total |
| Fresh coverage export and report gate | Passed; nonempty profdata and LLVM JSON |
| Report failure controls | Twelve passed |
| Workflow YAML / diff checks | Passed |

The export records 7,767 executed functions in 292 production source files
across DICOMCore, DICOMDictionary and DICOMKit. This validates exported
coverage presence; it does not establish complete coverage export for every
package target. Both coverage files have recorded hashes and sizes. Raw
profiles remain outside version control. See [verification](verification.json),
[test report](evidence/test-report.json), [commands and exits](evidence/local-execution.json)
and [environment/log hashes](evidence/local-environment.json). The initial
restricted-environment invocation could not access the compiler cache; the
authorized normal-environment run completed successfully. That setup refusal
is distinct from a build or test failure.

[Repaired comprehensive run 41191992135](https://github.com/raster-labs/DICOMKit/actions/runs/41191992135)
is in progress on `31d7609b`; its reporting controls passed. PHI Guard, Audit
tooling and the push documentation workflow passed on that source. Remaining
PR workflows are queued/in progress in the
[publication snapshot](evidence/remote-runs-local-completion.json). Remote
qualification remains **pending**, not passed. The manually dispatched run
selects comprehensive verification only; memory, performance, build-matrix
and dependency jobs are deliberately skipped and are not counted as passes.

The pre-documentation repository scan checked 7,521 tracked files and found
zero prohibited DICOM payloads; the [final staged-tree scan](evidence/no-dicom-final.json)
covers the added R3 documents as well. The R2 history boundary still applies: older
commits, main and historical Actions artifacts were not purged. No new native
GUI, physical-printer, device or optional external-system qualification is
claimed. No merge, auto-merge or Pages deployment is performed.
