# R1 — main reconciliation and CI repairs

31 October follow-up: the final comprehensive run failed with five tests;
nine other required workflow results passed across the explicitly recorded
test-input/documentation commits. [R2](../R2/REPORT.md) records the diagnosis,
repairs and new verification. The pending language below is historical.

Authorized 30 October 2026: reconcile the milestone branch with latest main, repair CI, verify, update documents and push `codex/dicom-2026a-milestones`. Main merge remains reserved for the user. This work does not expand the 68-item ledger: 49 items remain completed and 19 deferred.

## Integrated source

The starting milestone commit was `82ed0d07eb22f1f7fb8c713eee6d78f4c8334665`; fetched main was `4950a53f96f23d0f13c6670aa3473dee7608505d` (v2.9.2). Main's seven commits were merged into the milestone branch in `cf538dc6`. The sole textual conflict was a parser comment; both the milestone's implicit native Pixel Data OW handling and main's bounded padding/Modality LUT resolution were retained.

Broader integration tests exposed a real Transfer Syntax UID mismatch: bounded parsing removed Unicode whitespace and BOM bytes that M2's strict materialized reader rejected. Bounded lookup now accepts ASCII UID bytes and trailing NUL accessor padding, rejects leading/embedded padding, non-ASCII bytes and BOMs, and retains cancellation and allocation cleanup. Tests cover both readers and a combined 8/16-bit native OW, signed padding and late Modality LUT context fixture. Repeated trailing NUL acceptance preserves the existing accessor compatibility; it is not a full UI VR validation claim. Standard basis: [PS3.5 2026a Table 6.2-1](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/sect_6.2.html) and [UID encoding, §9.1](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/chapter_9.html).

## CI findings and repairs

The original scheduled run `40300110331` built successfully, but OCR tests failed on its runtime and Workshop tests could not find release CLI binaries. It reran the full suite for report generation. Its first parallel run also had two ARTIM timeouts; these did not recur in the serial run and their cause is unproven. The repaired comprehensive job uses the existing stable macOS/Swift setup, requires an OCR runtime preflight, builds and records real CLI binaries, executes the optimized source-envelope gate separately, and runs the remaining complete Debug suite once with coverage. The report reads those logs, rejects failures or empty results, and retains logs and coverage even after failure. A manual `comprehensive_only` input isolates this repaired job; scheduled runs retain the other jobs.

The original documentation job `121479510237` swallowed five unavailable `generate-documentation` commands, then failed because Pages was not configured. A shared helper now emits real API symbol graphs with the compiler, converts all five public modules with bundled DocC, and requires each module's API data and rendered routes. Build, conversion and missing-output errors fail the job. Documentation, general CI and release documentation steps use the same helper. Branch/PR builds produce review artifacts; deployment is restricted to main. The first hosted R1 build passed all module checks, then upload-artifact rejected valid colon-containing DocC filenames. The site is now packaged verbatim in a tar archive before review upload; all 13,950 colon-named JSON files round-trip unchanged. The original upload failure is retained.

The strict tag audit also incorrectly interpreted the diagnostic CLI token `--modality` as the DICOM keyword Modality. Study QIDO correctly uses Modalities in Study `(0008,0061)`. The audit repair distinguishes CLI option labels from attribute names without exempting the file, tag or other checks.

## Verification status

Local repairs are verified: 33 bounded-input Swift Testing declarations and 24 CLI/diagnostic XCTest cases; 87 core/native-pixel tests; 56 audit regressions; 8 scheduled-report controls; 11 documentation controls; a strict source tag audit with no findings; and five generated DocC archives with 1,937 verified module-index API pages. See [verification.json](verification.json) and the source/evidence manifests. Remote CI is checked after the next push, with its final receipt in task outputs. These counts describe distinct layers and are not a combined coverage total. Failed attempts are retained, including the initial 27 UID expectation failures and a test-fixture type-inference compilation failure.

**User-deferred Pages deployment:** on 30 October 2026 the user explicitly chose to leave deployment pending. Authenticated GitHub evidence reports `has_pages:false` and no admin permission. A repository administrator must enable **Settings → Pages → Source: GitHub Actions**. The main workflow checks this explicitly; a successful branch documentation build does not establish Pages deployment. No Pages settings, release or main merge were performed.

M0–M7 and E1 receipts retain their original source identities. E1 networking and metadata implementation files are unchanged, but earlier app hashes and parser checks are not relabeled as verification of the integrated source. No new native GUI, external hospital-system or physical-device qualification is claimed by CI.

The upload-only follow-up changes no production code, test sources, package inputs or test workflow/scripts. Test CI from `0b5c49204428705da54aa27f724843dd50d80f1d` remains attributable to those identical inputs; documentation upload is verified again on the follow-up commit. The final receipt names each tested commit explicitly.
