# M7 qualification checkpoint

24 October 2026. **Implementation and automated qualification are verified; final native GUI acceptance is blocked by the locked Mac. M7 is not complete.** Work remains on `codex/dicom-2026a-milestones`; main is not merged. The user retains merge authority.

The register now has **43 completed active items, three in progress and 22 deferred**. M0–M5 remain complete. M6's two print enhancement items still require native Workshop acceptance. M7 QUAL-02 has bounded independent runtime evidence; QUAL-01 remains open for the final packaged app. See [acceptance](acceptance.json), [all 68 items](../items.json) and [verification](verification.json).

## Repairs exposed by final qualification

| Repair | Before | Corrected behavior | Evidence |
|---|---|---|---|
| JPEG Extended 8-bit process | `.4.51` output contained Baseline SOF0 | Monochrome 8-bit encoding emits SOF1; other marker payload bytes remain unchanged. Color remains explicitly unsupported. | Core process tests; independent DCMTK decode and direct SOF1 inspection for 8/12-bit samples |
| Server TLS safety | An advertised TLS request could start plaintext; a configuration file also hid an explicit `--tls` request | Flag alone, JSON true and JSON false plus flag all fail before storage/listener startup. TLS listener support is not invented. | Four focused tests; actual CLI negative cases in the 34-case network campaign |
| Decompressed native Pixel Data | Encapsulated OB was copied to native data even with 16 Bits Allocated | Native >8-bit and implicit-VR data use OW. The writer preserves correct little/big-endian words. | Allocated16/stored8,12,16 controls; independent native pixel metadata and byte comparisons |
| Native Pixel Data padding | An odd-sized decoded value could have odd Value Length | One final NUL pads the complete value; no padding is inserted between frames | Single 3×3 frame and two odd-sized frame controls |
| Implicit-VR eager reader | Dictionary's first OB alternative was applied to native Pixel Data | Implicit native Pixel Data is OW; explicit OB/OW input remains unchanged for validation | Eager/strict/lazy/metadata parsing controls and implicit-to-explicit word comparisons |
| Verification portability | Legacy tests assumed a fixed binary directory, invalid fixture padding/identity, stale quoting and fractional-time expectations, or a developer Desktop sample | Test binary path is configurable; fixtures and assertions follow the implemented contracts; independent print uses a repository synthetic fixture | Full Studio suite; activated DCMTK reverse test; retained initial failure logs |

These are qualification-discovered repairs, not additional non-print enhancements or a change to the 68-item register. [Repair provenance](evidence/native-pixel-repair.json), [applied changes](evidence/applied-repairs.json), [source hashes](source-hashes.json) and the [baseline plus source overlay](evidence/source-provenance.json) identify the exact work.

## Final executed evidence

| Gate | Result |
|---|---|
| Integrated M2–M6 scripts and M7 checks | Exit 0 on the frozen final source; detailed per-suite results in verification.json |
| Enabled CLI inventory | 41 binaries; all 147 command/subcommand help checks and invalid-invocation exit-64 checks pass |
| Full DICOMStudio product | Swift Testing run succeeds with 5,380 framework-reported tests and one optional SampleStudies skip; 83 XCTest cases pass with four opt-in skips activated separately in process campaigns |
| Core codec/native-data regressions | 75 pass across 15 suites |
| Conversion diagnostics | 18 XCTest cases pass |
| Audit tooling | 48 regressions pass; CLI/Kit static audits exit 0; Studio completes 178 callbacks without execution errors and retains three finding checks (exit 1) |
| Independent DIMSE network | 34 pass: storage/identity, matching/return keys, cancellation/status counters, MOVE originator identifiers, MPPS references and TLS refusal |
| Independent TLS | 8 client cases pass: four positive C-ECHO connections and four policy refusals; eight valid endpoint controls support the negative cases |
| Independent print | 24 pass; DC-F07 remains one peer limitation, with actual optional-context refusal established by separate PY-F08 |
| Independent codecs | 78 pass; 10 supported refusals and two verified interoperability limits are separate; zero unexpected failures |
| Print Workshop execution harness | 25 actual ViewModel actions and 25 CLI comparisons across all ten commands pass; includes 14 PNG films, compressed inputs and frame selection |
| Final packaged app | Actual app target builds and its ad-hoc signature verifies with project sandbox entitlements; native actions remain blocked |

Counts from different layers overlap and must not be summed into a single coverage total. The optional Swift Testing SampleStudies fixture test remains unexecuted; it is separate from the four activated XCTest harness skips. The framework-reported 5,380 is retained verbatim as a run count, not reclassified as 5,380 independently counted executed passes. One activated TLS XCTest method performs eight client cases. Two activated print Workshop harness invocations perform 25 actions. Help/invalid-invocation checks do not imply that every operation/flag combination was executed. The catalog contains 35 entries representing 32 unique enabled tools; nine tools remain outside Workshop scope.

The independent codec oracles use DCMTK, OpenJPEG, OpenJPH and libjxl. The synthetic corpus covers unsigned monochrome 8/12-bit and RGB8, forward/reverse paths and JPEG XL recompression. Expected lossless pixels, metadata, native word order and lossy decoder agreement are checked. Ten refusals are nine JPEG 2000 Part 2 cases and one unsupported Extended RGB case. The two strict-policy limits are independently decodable DCMTK JPEG/JPEG-LS objects with codestream precision 16 and dataset Bits Stored 12; DICOMKit refuses them. They are neither decoding successes nor declarations that the peer is universally nonconformant. See [codec review](evidence/codec-final-review.json) and [peer review](evidence/peer-final-review.json).

Initial failures are retained. The first strengthened codec campaign exposed the OB defect and two oracle issues: the updated Extended refusal diagnostic and PNG scaling of 12-bit JPEG XL samples. The final oracle preserves stream depth through PNM and validates refusal diagnostics/output absence. No unexpected failure was relabeled a pass.

The final static Studio audit initially exposed stale checker paths after print-command extraction and strict query preflight. The audit-only repair follows the current shared paths and adds ten positive/negative controls, with CI discovery updated. Three real finding checks remain: two flag the same absent Workshop anonymization-profile control, and one flags the intentional Workshop `--dry-run=true` versus CLI false default. These are visible product-contract differences; the anonymization control finding alone does not establish a PS3.15 violation. See [audit repair and findings](evidence/studio-audit-repair-verification.json). No product or Swift-test input changed after runtime qualification; [post-build reconciliation](evidence/post-build-audit-reconciliation.json) rehashes all 71 artifacts and separates the four audit-only edits.

## Pending acceptance and limits

The Mac remained locked when the final app was selected for verification. **Zero native M6 or final M7 actions are claimed.** The [28-group native checklist](evidence/native-final-checklist.json) covers changed routes, the M3 UID-list/non-ASCII supplement, all ten print commands, visible forms/preview/copy/import, actual file access, output and listener Stop/restart, and persistence after relaunch. Older milestone GUI results and final ViewModel tests do not replace these actions. Toolbox is a separate library without a linked packaged Toolbox UI; its final non-GUI checks pass.

The retained runtime claims are bounded to macOS arm64 software peers and the recorded fixtures. Complete PS3.15 TLS profiles, mutual TLS, revocation and full cipher matrices; other platform runtimes; physical printer/film; real CUPS output; calibration; diagnostic image quality; and universal IOD/standard conformance remain unqualified. DCMTK's disabled-LUT setting did not refuse the context. SCP planar-0 compatibility tolerance remains disclosed. The [conformance statement](../../ConformanceStatement.md) distinguishes implemented, refused, limited and unqualified behavior.

The app, all CLI binaries and test executables retain the verified identities. The runtime freeze contains 2,057 files; the final source manifest contains 2,058 after the additional Python audit test. Both freezes and audit-only reconciliation are retained alongside [artifact hashes](artifact-hashes.json) and [source hashes](source-hashes.json). [Reproduction instructions](REPRODUCE.md) accompany the evidence. Remote CI must be checked on the exact pushed head; local success does not establish it. M6's prior checkpoint passed all seven remote workflows. No merge, release or deployment is authorized by this report.
