# M7 — local final acceptance

**All 46 active items and all 28 native groups meet their local acceptance criteria; 22 items remain deferred.** At document creation, exact next pushed-head remote CI was pending. Overall publication/goal closure stays provisional until the eight required workflows, jobs and recorded steps succeed. The user retains main merge authority.

The branch is `codex/dicom-2026a-milestones`. The committed source checkpoint `c9001dd12027b2152dabd4a5a2ba490bbf43c21b` has eight successful remote workflows. Later UPS identity and JSON charset repairs are an explicitly hashed source overlay, not binaries from that old commit. [Current source](source-hashes.json), [artifact](artifact-hashes.json), [verification](verification.json) and [checkpoint input](evidence/checkpoint-update-input.json) identify the exact qualification inputs. Remote CI for the next pushed revision was pending at document creation.

## Repairs found during qualification

The original UPS create-json requests removed supplied `00080018` and supplied no query UID. The successful permissive-peer exchange established parity and compact DT preservation, not standard-compliant Create identity. [DICOM PS3.18 2026a §11.4.1.1](https://dicom.nema.org/medical/dicom/2026a/output/html/part18.html#sect_11.4.1.1) requires identity in the collection-target payload or the alternative query target. Both public clients now preserve valid collection-body identity, validate explicit query identity and remove only a matching body UID, reject invalid/conflicting identities before dispatch, and generate a valid client UID when neither identity is supplied. The strict peer verified five CLI actions with 38 assertions on the intermediate UPS-repair executable; five focused test declarations cover nine parameterized invocations. Later JSON changes relinked binaries. This CLI evidence retains its original executable hash and uses the reviewed unchanged UPS-method boundary; it is not a claimed rerun on the final linked binary. The exact rebuilt app was quit, confirmed absent, relaunched by its signed path and verified against all 14 frozen app files. Create/Get succeeded and malformed UID refused locally without a third HTTP request. Independent review accepts three native actions and five CLI actions with 54 assertions; this 54 includes the earlier 38 CLI assertions. The server's permissive UID-less fallback is unchanged and unqualified.

The first complete DICOMWeb run failed with 12 issues in five tests: two issues were a real M2 integration regression because JSON-created UTF-8 values lacked the charset context required by the strict binary accessor ([DICOM PS3.18 2026a F.2.2, Note 3](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part18/sect_F.2.2.html) specifies UTF-8 for the JSON representation); two arose from an invalid undeclared-UTF-8 encoder fixture; eight were stale expectations for intentionally removed M4 capabilities. Those failures were not baseline-tested or all unrelated. The first repaired run retained one issue. Both failed logs and the independent classification are retained. The final full-product run passes: 649 framework-reported Swift Testing tests in 63 suites, and 504 XCTest cases reported, including 2 skips and 502 executed passes, zero failures. Skips are not executed passes. The local and remote M7 gates now select the complete DICOMWeb product. The affected Studio workflow run passes 60 unique tests in three suites; a no-build confirmation is the same 60 tests, not 120. All products and the signed app build pass. The first build-runner wrapper returned 1 because it grepped the wrong framework summary; its log and successful confirmation remain visible.

Earlier qualification also repaired generic Workshop file grants/output identity, single-image folder-target normalization, print option/menu presentation, JPEG Extended process identification, native Pixel Data VR/byte-order/padding and server TLS refusal. The exact prior source, failures and verification remain in the [c900 checkpoint history](evidence/historical-checkpoint-c9001dd/Documentation/2026a-milestones/M7/REPORT.md).

## Native and independent evidence

| Layer | Bounded result |
|---|---|
| Native attributes, script, anonymization and codecs | 71 executions and one disabled preflight, with original app epochs retained |
| Native print | Ten command groups complete; the overlapping CLI/VM and independent-peer counts are not new native totals |
| Initial native network | 43 native executions and 43 CLI counterparts; six accepted receipt layers contain 457 assertions |
| Initial UPS pair | Two native/two CLI actions and 24 parity assertions remain historical and do not qualify request identity |
| Repaired UPS | Three native actions / five CLI actions; two native and four CLI HTTP requests; 54 assertions including the previous CLI 38 |
| Catalog / viewer | 35 selections, 32 unique enabled tools, 41 CLI inventory; selection is not execution. Sixteen SR rows and exact copy retained |

The [native ledger](evidence/native-2026-10-26/native-results.json) closes FINAL-05–12 and FINAL-15 using exact raw wire/output and native capture receipts, and closes FINAL-13 with the separately attributed repaired native UPS proof. The three supplemental copied-command/multiline previews are zero additional executions. The actual three-line QIDO command preview preserves literal Unicode/newline/semicolon/dollar content. Earlier username-only copy is not substituted for it.

## Source and scope boundaries

The new manifest contains 2062 source/build inputs. Fresh artifacts and affected regressions are recorded separately; previous native actions are reused only under the reviewed source-equivalence boundary, never reported as rerun. The historical full Studio run reported 5,391 Swift Testing tests including one optional SampleStudies skip and 92 XCTest cases including four skips, zero failures. The later print-layout gate passed five tests. None of these older runs substitutes for the new complete DICOMWeb run.

- Controlled peer-origin FE00 checks client reporting; no native Cancel-button origin, server C-CANCEL or C-STORE claim.
- The restarted process exits -15 after SIGTERM; the earlier exit-zero oracle was wrong. No graceful-shutdown or power-loss guarantee.
- Persisted Interactive native import has no supported route and remains unexecuted; existing model refusal evidence is separate.
- MPPS terminal N-SET captures are not persisted IN PROGRESS-to-terminal lifecycle qualification; only generated PPS End Date/Time were normalized.
- UPS compact DICOM DT uses existing create-json; Scheduled Start expects ISO8601. Generic UPS attribute update remains backend-only.
- Native Basic headers were captured by a non-enforcing synthetic peer. CLI counterparts omit Basic because there is no CLI Basic flag. Preview-only Bearer/none/multiline observations are not executions.
- Generic 240px forms retain clipping. Operative controls/effective values were observed; a general layout enhancement is outside the original scope.
- SR values/copy retain full precision; the 185px ordinary-image sidebar visibly ellipsizes while AX retains all six fractional digits.
- Other runtimes, clinical/physical devices, real CUPS, calibration, diagnostic fidelity, full IOD/standard and full TLS/mTLS/revocation/cipher qualification remain unexecuted.
- Existing UPS server UID-less fallback remains permissive and unqualified; the repair qualifies client request identity only.

All six original M7 item assertions now pass locally; the register contains 46 completed and 22 deferred items. None of those assertions is an unexecuted CI check. The separate remote_CI field records Pending exact next pushed head as an immutable creation-time snapshot. QUAL-02 retains only its bounded external claims. No deferred enhancement, merge, release or deployment is authorized by this checkpoint.

## Final native closure and remote sequencing

[Independent repaired-native review](evidence/ups-identity-repair/independent-final-native-acceptance.json) and [local final acceptance](evidence/local-final-acceptance.json) preserve the failed UID-less original epoch, the intermediate CLI executable and the fresh final native app separately. Six non-UPS receipt layers provide 457 accepted assertions; repaired UPS provides 54, for 511 accepted network assertions. The original 24 UPS parity assertions are excluded; the earlier 38 CLI assertions are already included in 54. Native/counterpart action counts are recorded by phase rather than summed into a coverage total. Both owned strict peers are stopped and their isolated ports closed.

The actual QUAL-01/02 assertions concern executed tests, source/binary identities, meaningful routes and bounded independent claims. Local acceptance can be recorded before the next push without inventing a CI pass. After the code/document commit is pushed, the exact-head remote receipt and final user report are updated outside the repository; this avoids a self-referential documentation/CI commit loop. No main merge is authorized.

Remote state above is the immutable snapshot recorded at 2026-10-26T09:34:23.083422+00:00. Consult [the milestone branch Actions](https://github.com/raster-labs/DICOMKit/actions?query=branch%3Acodex%2Fdicom-2026a-milestones) for current status; the final user report and remote receipt bind the actual pushed revision after verification.
