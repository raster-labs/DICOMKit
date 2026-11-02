# M7 — qualification checkpoint after client repairs

**M7 remains in progress: 45 completed items, one in progress, 22 deferred.** M0–M6 are accepted within their documented software scope. Of the 28 planned native groups, 27 have bounded accepted evidence; FINAL-13 requires the rebuilt UPS native check. The user retains main merge authority.

The branch is `codex/dicom-2026a-milestones`. The committed source checkpoint `c9001dd12027b2152dabd4a5a2ba490bbf43c21b` has eight successful remote workflows. Later UPS identity and JSON charset repairs are an explicitly hashed source overlay, not binaries from that old commit. [Current source](source-hashes.json), [artifact](artifact-hashes.json), [verification](verification.json) and [checkpoint input](evidence/checkpoint-update-input.json) identify the exact qualification inputs. Remote CI for the next pushed revision remains pending.

## Repairs found during qualification

The original UPS create-json requests removed supplied `00080018` and supplied no query UID. The successful permissive-peer exchange established parity and compact DT preservation, not standard-compliant Create identity. [DICOM PS3.18 2026a §11.4.1.1](https://dicom.nema.org/medical/dicom/2026a/output/html/part18.html#sect_11.4.1.1) requires identity in the collection-target payload or the alternative query target. Both public clients now preserve valid collection-body identity, validate explicit query identity and remove only a matching body UID, reject invalid/conflicting identities before dispatch, and generate a valid client UID when neither identity is supplied. The strict peer verified five CLI actions with 38 assertions on the intermediate UPS-repair executable; five focused test declarations cover nine parameterized invocations. Later JSON changes relinked binaries. This CLI evidence retains its original executable hash and uses the reviewed unchanged UPS-method boundary; it is not a claimed rerun on the final linked binary. **No repaired native UPS execution is claimed at this checkpoint.** The server's permissive UID-less fallback is unchanged and unqualified.

The first complete DICOMWeb run failed with 12 issues in five tests: two issues were a real M2 integration regression because JSON-created UTF-8 values lacked the charset context required by the strict binary accessor ([DICOM PS3.18 2026a F.2.2, Note 3](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part18/sect_F.2.2.html) specifies UTF-8 for the JSON representation); two arose from an invalid undeclared-UTF-8 encoder fixture; eight were stale expectations for intentionally removed M4 capabilities. Those failures were not baseline-tested or all unrelated. The first repaired run retained one issue. Both failed logs and the independent classification are retained. The final full-product run passes: 649 framework-reported Swift Testing tests in 63 suites, and 504 XCTest cases reported, including 2 skips and 502 executed passes, zero failures. Skips are not executed passes. The local and remote M7 gates now select the complete DICOMWeb product. The affected Studio workflow run passes 60 unique tests in three suites; a no-build confirmation is the same 60 tests, not 120. All products and the signed app build pass. The first build-runner wrapper returned 1 because it grepped the wrong framework summary; its log and successful confirmation remain visible.

Earlier qualification also repaired generic Workshop file grants/output identity, single-image folder-target normalization, print option/menu presentation, JPEG Extended process identification, native Pixel Data VR/byte-order/padding and server TLS refusal. The exact prior source, failures and verification remain in the [c900 checkpoint history](evidence/historical-checkpoint-c9001dd/Documentation/2026a-milestones/M7/REPORT.md).

## Native and independent evidence

| Layer | Bounded result |
|---|---|
| Native attributes, script, anonymization and codecs | 71 executions and one disabled preflight, with original app epochs retained |
| Native print | Ten command groups complete; the overlapping CLI/VM and independent-peer counts are not new native totals |
| Initial native network | 43 native executions and 43 CLI counterparts; six accepted receipt layers contain 457 assertions |
| Initial UPS pair | Two native/two CLI actions and 24 parity assertions remain historical and do not qualify request identity |
| Repaired UPS CLI | Five actions / 38 assertions; separate from the initial campaign; fresh native counterpart pending |
| Catalog / viewer | 35 selections, 32 unique enabled tools, 41 CLI inventory; selection is not execution. Sixteen SR rows and exact copy retained |

The [native ledger](evidence/native-2026-10-26/native-results.json) closes FINAL-05–12 and FINAL-15 using exact raw wire/output and native capture receipts, while FINAL-13 remains partial. The three supplemental copied-command/multiline previews are zero additional executions. The actual three-line QIDO command preview preserves literal Unicode/newline/semicolon/dollar content. Earlier username-only copy is not substituted for it.

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

M7 and QUAL-01 stay open until actual repaired UPS packaged-app acceptance and required exact pushed-head verification. QUAL-02 retains only its bounded external claims. No deferred enhancement, merge, release or deployment is authorized by this checkpoint.
