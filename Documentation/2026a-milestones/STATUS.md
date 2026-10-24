# DICOM 2026a milestone status

Updated 24 October 2026. **M0, M1 and M2 are complete; M3 has not started.**
All milestone work uses `codex/dicom-2026a-milestones`. The reviewed product
baseline is `4b68d7e22829418c88e48dd53d98b25fee50d90d`; remote main matched that
commit at the start of M0. M0 repaired audit infrastructure; M1 repaired command and execution safety; M2 repairs attribute integrity and workflow datasets.

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
| M3 query safety and filters | 11 | Not started |
| M4 service reliability | 5 | Not started |
| M5 remaining Studio contracts | 7 | Not started |
| M6 print and printscp Workshop coverage | 2 | Not started |
| M7 final qualification | 2 | Not started |
| Other enhancements and dormant components | 22 | Deferred |

Of the 68 original actions, **19 are completed, 27 active items remain pending,
and 22 remain deferred**. 22 product bug-fix actions remain open. The
literal-audit successes do not close runtime, query, encoding or GUI defects.

No fresh Swift build, actual packaged-app check, external interoperability or
physical printing was performed for M0. The earlier 147 help paths and 504
passing cached-binary tests are retained as historical evidence only; their
equivalence to this source was not established. Preparation and gates for the
later verification are in [M0/REPRODUCE.md](M0/REPRODUCE.md).

Stop here before M3. Push M2 on the existing milestone branch. Merging into main,
releasing and beginning M3 require the user’s next instruction.
