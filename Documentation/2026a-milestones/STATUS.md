# DICOM 2026a milestone status

Updated 31 October 2026. **R2 local full-suite verification passed: 15,825 reported Debug tests
with 54 XCTest skips, plus all five optimized source-envelope cases.** The five
original failures and the fixture-cleanup dependency are repaired; 2,043
DICOM/wire/database payloads are removed. GitHub comprehensive CI is running.
See [R2 report](R2/REPORT.md) for causes, cleanup scope and the Git-history
boundary. PR #233 remains unmerged; Pages deployment remains deferred.
The following R1/E1/M0–M7 sections preserve their creation-time status.

Updated 30 October 2026. **R1 local repairs are verified; CI remains in progress and Pages deployment is explicitly deferred by the user.** Main `4950a53f` is integrated into the milestone branch; the item ledger remains 49 completed and 19 deferred. See [R1 report](R1/REPORT.md). The following E1/M0–M7 statements retain their original source and verification dates.

Updated 26 October 2026. **E1 is locally complete for NET-08-A, WS-DORM-01 and WS-DORM-02: 49 completed, 0 in progress, 19 deferred. Exact pushed-head CI is recorded separately after publication.** M0–M7 completed at the preceding source checkpoint; their 28 native groups are historical qualification, not a blanket E1 claim. See [E1 report](E1/REPORT.md). The user retains merge authority.

All milestone work uses `codex/dicom-2026a-milestones`. The reviewed product
baseline is `4b68d7e22829418c88e48dd53d98b25fee50d90d`; remote main matched that
commit at the start of M0. M0 repaired audit infrastructure; M1 repaired command and execution safety; M2 repaired attribute integrity and workflow datasets; M3 repaired query safety and filters; M4 repaired service reliability.

## E1 completed — 26 October 2026

All ten criteria pass. MPPS regression: 92 executed passes and one manual-only skip. Studio: 131 Swift Testing passes and 11 XCTest passes. Audit tooling: 48 passes. Independent CLI: 17 actions/56 assertions; Workshop: 19 actions/54 assertions, including correction after a failed external-instance charset guess. Six actual native actions produced four N-SETs and two local refusals; 45 independent wire assertions passed. These overlapping evidence layers are not additive. The retained metadata component has no production constructor; endian/numeric/copy tests and unchanged active dicom-info behavior are verified. See [E1 acceptance](E1/acceptance.json) and [verification](E1/verification.json).

The following M0–M7 sections preserve historical implementation and publication snapshots; their old pending language is not the current E1 state.

## Completed M6 print Workshop coverage

WS-COV-07 and WS-COV-08 are complete: **eight criteria passed** for the finite macOS software scope. All six `dicom-print` and four `dicom-printscp` commands use shared parser/services and have actual packaged Workshop evidence. Visible values, literal argv, CLI output and pixel comparisons, inherited/explicit SCP settings, registry persistence, errors, listener lifecycle, independent peers and final readable 240px forms are recorded in [M6 report](M6/REPORT.md), [native closure](M6/native-closure.json) and [acceptance](M6/acceptance.json).

The historical implementation checkpoint passed 932 focused tests and 38 audit regressions with 2 explicit skips; the M7 descendant recheck passed 933 with 1 ordinary opt-in skip. Independent print records 24 passes and 1 DCMTK peer limitation, and 25 CLI/actual-VM comparisons cover all 10 routes. Native layers are separate and overlapping; they are not added to those counts. The final PDF comparison proves exact CLI/native full-page raster and exact embedded film image/companion equality. Physical printer, real paper queue, calibration and diagnostic fidelity remain unqualified.

The final menu-repaired app has strict signature, normal sandbox entitlements and recorded source/binary identity. Its SCU dry-run and SCP status were executed natively; the final SCP status matches all 11 CLI JSON fields. Unchanged shared-service evidence is reused only within the recorded source-equivalence boundary. Earlier lock, layout and oracle failures remain historical. The original M6 commit `3ee9af8a` had seven passing remote checks; this does not establish CI for the later repair overlay.

## M7 local acceptance complete — remote CI pending

All 46 active item criteria and all 28 native groups have bounded accepted evidence. The rebuilt UPS app was relaunched by its exact signed path; all 14 file hashes match. Create/Get succeeds against the strict peer and malformed identity refuses locally, producing only two HTTP requests. The repair phase records three native/five CLI actions and 54 assertions, including the earlier 38 CLI assertions. Combined with 457 accepted non-UPS assertions, the accepted network total is 511; original 24 UPS parity assertions remain excluded.

The complete DICOMWeb product passes 649 Swift Testing tests in 63 suites and 504 reported XCTest cases including two skips: 502 executed passes. Sixty unique affected Studio tests in three suites pass. Failed complete runs, the genuine M2 JSON charset regression, invalid fixture/stale expectations and runner-summary correction remain visible in [M7 report](M7/REPORT.md).

The original item assertions now pass locally. The separate machine-readable remote_CI state_at_document_creation is Pending exact next pushed head. Eight old c9001dd workflows passed, but they do not establish a new-head result. Overall publication/goal closure stays provisional until the next code/document commit passes all eight exact-head workflows/jobs/steps. The post-push receipt and final report are output-only; no main merge or additional enhancement is authorized.

## Completed M5 items

WS-FIX-04/06/07/08 and TB-FIX-01/02/03 are complete: 22 criteria passed and two
conditional alternatives are not applicable. The frozen M5 source passed 740
focused suite tests, one separately activated Workshop harness and 30 audit
regressions. Actual process campaigns passed 23 Toolbox CLI cases and 22 CLI /23
Workshop ViewModel actions. Ten packaged-app cases verified script refusal and
supported actions, explicit Auto/Review modes, the single PHI control, and exact
SR temporal display/copy. The SR source bytes stayed unchanged. Counts describe
different overlapping layers, not one additive test total.

All six CI workflows passed on M5 commit `c91c79d9655929eef97ccffd601a9ef4297241d6`;
see [remote verification](M5/remote-verification.json).

See [M5 report](M5/REPORT.md), [acceptance](M5/acceptance.json),
[verification](M5/verification.json) and [reproduction](M5/REPRODUCE.md).
Toolbox remains a separate library; it is not linked into DICOMStudio and no
packaged Toolbox UI qualification is claimed. M6 print integration is complete; remaining M7 qualification proceeds under the user's authorization, with no merge.

## Completed M4 items

NET-05-A/B, NET-09-A/B and NET-10-A are complete. Fourteen criteria passed;
one future bulk-data criterion is explicitly not applicable and remains a future
gate. **512 unique focused tests**, **30 audit regressions**, three activated
process-harness methods, 20 durability process cases, 30 capabilities HTTP/CLI
cases, four cancellation CLI/four Workshop ViewModel cases, and three restarted
server Workshop ViewModel cases passed. All initial focused-suite skips have
subsequent passing evidence. These counts overlap in coverage and are not additive.

The freshly linked packaged app passed seven GUI cases and seven equivalent CLI
replays. Cancellation status/partial results/counts, WADO byte identity and
restart query/retrieve integrity were checked. No full GUI console byte equality
is claimed. See [M4 report](M4/REPORT.md), [acceptance](M4/acceptance.json),
[verification](M4/verification.json) and [reproduction](M4/REPRODUCE.md).

The server now defaults to filesystem restart reindex; unimplemented SQLite and
PostgreSQL selections are refused with migration guidance. External PACS,
other operating systems, power-loss durability and full IOD/codec qualification
remain unexecuted. These local results do not substitute for exact-commit CI.

## Completed M3 items

NET-01-A, NET-02-A–F, NET-03-A/B, NET-04-A and WS-FIX-03 are implemented;
all 35 item criteria have executed evidence. 538 focused runtime tests,
153 independent QIDO probes, eight DIMSE CLI cases and 30 audit regressions passed.
The qualified packaged app passed 17 GUI checks, with 16 CLI replays matching
captured requests. See [M3 report](M3/REPORT.md), [acceptance](M3/acceptance.json),
[verification](M3/verification.json) and [reproduction](M3/REPRODUCE.md).

Full GUI console byte equality is not claimed because accessibility truncates it.
A supplemental packaged UID-list/non-ASCII matching-input case remains unexecuted;
HTTP/CLI/shared Workshop tests cover those semantics. Four existing external DIMSE
integration tests also remain unexecuted. External providers require explicit
canonical-matching adoption; no external backend is qualified. Remote results
must be checked on the pushed commit; local tests do not stand in for CI.

## Completed M2 items

A-01–A-09, NET-06-A, NET-06-B and NET-07-A are implemented and verified.
508 focused runtime tests passed; one opt-in receiver test was skipped in the
normal run and passed separately during the actual network capture. All 30
audit regressions and 72 repeatable CLI process probes passed. Packaged Workshop
edits, metadata display, validation and applicable UPS/MPPS routes were exercised;
independent file and wire inspections passed. See [M2 report](M2/REPORT.md),
[verification](M2/verification.json) and [reproduction](M2/REPRODUCE.md).
The generic UPS attribute-update route is backend-only and explicitly UI-not-applicable.
Remote CI must be checked on the pushed M2 commit; local evidence is not remote CI.

## Completed M1 items

WS-FIX-01, WS-FIX-02, WS-FIX-05 and TB-FIX-04 are implemented and verified.
151 Workshop tests, 488 Toolbox tests and 30 audit regressions passed. The fresh
packaged app passed the recorded form/preview checks and synthetic tag execution;
CLI/app outputs are byte-identical. See [M1 report](M1/REPORT.md) for exact evidence,
API/history migration behavior, environment observations and qualification limits.

## Completed M0 items

| Item | Result | Verification |
|---|---|---|
| AUD-01 | Current CLI contracts and enabled-tool inventory repaired | 41 tools, 492 static checks, zero failures; 12 focused regression tests |
| AUD-02 | Studio inventory/current workflow discovery/error isolation repaired | All G1–G6 complete; 340 sources classified; zero execution errors; 10 regression tests |
| AUD-03 | Narrow private-tag alias repair preserves mismatch detection | 165 tag-name matches; full Kit literal audit passes; 8 positive/negative regression tests |

The integrated audit regression run passes **30 tests**. Negative controls
verify that wrong tags/keywords, stale flags, wrong defaults, missing inputs
and failing checks remain visible. A lightweight `Audit tooling` workflow runs
these tests on the milestone branch; this document records local evidence,
not a claim about a future remote run. Remote status is available on the
pushed commit's Checks/Actions page.

The [baseline](M0/baseline.json) records source tree identities, dependency and
build-setting hashes, the current command/Workshop inventories, frozen standard
hashes/URLs, 14 synthetic fixtures and historical help evidence. The
[verification record](M0/verification.json) links the complete audit logs.

## Deliberately visible coverage finding

The completed Studio audit exits **1**, with **two failed assertions for one
coverage gap**: Workshop does not expose anonymization `--profile`. The CLI's
`ps315` and `basic` choices and the Workshop both use the same Basic Profile
workflow, so this is not demonstrated policy divergence or a DICOM violation.
No whitelist hides it. It is also distinct from the stale Toolbox profiles and
flags tracked by TB-FIX-01/TB-FIX-02. Retain it as M0-COV-01 without adding an
unauthorized non-print enhancement.

M0 is accepted because the audit now completes and reports that gap accurately.
A zero execution-error count is not the same as a fully passing product audit.

## Current anonymization command compatibility

| Historical spelling/assumption | Current contract |
|---|---|
| `--regenerate-uids` | Removed; replacement is the default. `--retain-uids` explicitly enables retention. |
| `--keep` | Removed; no generic replacement. Named PS3.15 retention options express the supported policies. |
| Legacy `clinical-trial`/`research` CLI profiles | Not accepted; `ps315` is default and `basic` uses the same shared workflow. Library legacy profiles do not imply CLI support. |
| Full/modified dates | `--retain-dates` / `--retain-full-dates` retain full dates; `--shift-dates` supplies modified dates; `--retain-modified-dates` requires a shift. Conflicting full/modified policies are rejected by the current workflow. |
| `--no-raw` inferred from help prose | Not declared. Negative spellings are extracted only from actual inversion metadata. |
| Optional Print SCP flags default to false | Absent optional flags remain `nil`, preserving configuration inheritance. |

These are audit-contract corrections; no product options or defaults changed.

## Pending work and boundaries

| Milestone | Items | Status |
|---|---:|---|
| M0 baseline and audits | 3 | Completed |
| M1 command/execution safety | 4 | Completed |
| M2 attribute integrity and workflow datasets | 12 | Completed |
| M3 query safety and filters | 11 | Completed (35 item criteria) |
| M4 service reliability | 5 | Completed (14 passed, 1 conditional not applicable) |
| M5 remaining Studio contracts | 7 | Completed (22 passed, 2 conditional not applicable) |
| M6 print and printscp Workshop coverage | 2 | Completed (8 passed) |
| M7 final qualification | 2 | Completed local item criteria; CI creation-time snapshot recorded separately |
| E1 intermediate MPPS and retained metadata | 3 | Completed (10 criteria passed) |
| Other enhancements and dormant components | 19 | Deferred |

Of the 68 original actions, **49 are completed and 19 remain deferred**. All planned bug-fix milestones and the two print enhancements are complete; remote publication verification remains. The
literal-audit successes do not close runtime, query, encoding or GUI defects.

No fresh Swift build, actual packaged-app check, external interoperability or
physical printing was performed for M0. The earlier 147 help paths and 504
passing cached-binary tests are retained as historical evidence only; their
equivalence to this source was not established. Preparation and gates for the
later verification are in [M0/REPRODUCE.md](M0/REPRODUCE.md).

The user authorized completion of M5–M7 on 24 October 2026, after M4 was pushed.
Continue sequentially, update documents after each milestone and push the same
branch. Do not merge main; the user will merge. The user additionally authorized NET-08-A, WS-DORM-01 and WS-DORM-02 on 26 October 2026. The other 19 deferred enhancements remain
outside scope. Unavailable qualification evidence must stay explicit.

Remote state above is the immutable snapshot recorded at 2026-10-26T09:34:23.083422+00:00. Consult [the milestone branch Actions](https://github.com/raster-labs/DICOMKit/actions?query=branch%3Acodex%2Fdicom-2026a-milestones) for current status; the final user report and remote receipt bind the actual pushed revision after verification.
