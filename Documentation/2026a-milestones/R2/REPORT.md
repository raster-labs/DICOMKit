# R2 — PR #233 full-suite repairs and repository DICOM cleanup

Authorized 31 October 2026: repair the five comprehensive-suite failures,
verify the full suite, update documents and push the same milestone branch.
The user also requires no DICOM files in the repository. Main merge remains
reserved for the user; Pages deployment remains deferred. The implementation
ledger stays at 49 completed / 19 deferred.

Starting head: `b5d5f5a6e51881f9b3e8a990b7528b2bbfb03905`.
[PR #233](https://github.com/raster-labs/DICOMKit/pull/233) targets main
`4950a53f96f23d0f13c6670aa3473dee7608505d`.

## Five failures and repairs

The original [comprehensive run 41050923003](https://github.com/raster-labs/DICOMKit/actions/runs/41050923003)
reported five failing test declarations/cases and seven assertion/issue records.
Its Debug report contained 15,824 reported tests and 57 XCTest skips; those
counts never established a passing full suite.

| Failing test | Cause and repair |
| --- | --- |
| `TextEncodingIntegrityTests.failedConversions` | Apple Foundation accepted high-bit bytes through its ASCII decoder. ISO-IR 6 decoding now explicitly rejects bytes >= 0x80 before calling Foundation. Undeclared raw Latin-1 cannot be written as default-repertoire text. |
| `TextEncodingIntegrityTests.emptyOverrideRejectsLatin1Bytes` | The same permissive decoder hid the invalid bytes after the empty Item declaration correctly selected the default repertoire. The existing override logic is retained; the strict decoder now rejects the bytes. |
| `IODRequirementValidatorTests.testConformantGSPSHasNoIODErrors` | The fixture incorrectly encoded SL coordinates with a string factory. It now uses two binary signed longs for each corner. VM validation remains strict. |
| `ParserLimitTests.testMaxElementLengthRejectsOversizedDeclaration` | The explicit-VR header fixture used an illegal SPACE-padded Transfer Syntax UID. It now uses NULL padding so the test reaches the intended element-length check. UID rejection remains strict. |
| `DICOMJSONEncoderTests.testEncodePersonNameIdeographic` | The helper created UTF-8 bytes without character-set context. It now uses the string factory, which records UTF-8 context. Required assertions also fail if the JSON Value array is missing. |

The new Core regression checks all 128 high-bit byte values, plus explicitly
declared Latin-1 and UTF-8 success cases. The two original text-integrity tests
retain their failure expectations. Standard basis:
[PS3.5 2026a §6.1.2.1–2](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/chapter_6.html)
for the default repertoire and its declared replacement, and
[Table 6.2-1](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/sect_6.2.html)
for binary SL values and NULL-padded UI values.

## Repository data cleanup

Removed **2,043 payloads / 3,276,556 bytes**: 573 `.dcm`, two Part 10 backup
files, 95 `.dcmdata` captures, 1,346 binary wire/data captures and 27 DCMTK peer
database indexes. [removed-payloads.json](removed-payloads.json) records paths,
sizes and SHA-256 values, without copying patient attributes or payload bytes.

The earlier [PHI Guard failure](https://github.com/raster-labs/DICOMKit/actions/runs/41175486935)
identified 11 `BurnedInAnnotation=YES` files among the synthetic negative-test
evidence. This tag alone is not proof of real patient identity, nor does its
absence prove anonymization. All DICOM and opaque capture payloads were removed
regardless. No real-patient-free claim is made for historical objects or arbitrary
images. Studio, Print SCP and DCMTK interoperability tests now share a source generator
for an 8×8 synthetic ramp, written only into temporary test directories. No
DICOM fixture is bundled. Explicit external interoperability inputs remain local.

The strengthened PHI Guard checks tracked filenames, Part 10 signatures,
plausible preamble-free explicit/implicit datasets in either byte order, archive
members (ZIP/TAR/GZIP/BZIP2/XZ, including nesting) and milestone wire/database
payloads. Unreadable files, uninspectable archives, tracked symlinks and LFS
pointers fail closed. It never extracts archive paths. Eight regression tests
cover detection, negative controls, nested archives, limits and tracked-file scope.
Ignore rules prevent ordinary accidental additions; the guard also catches
renamed or force-added payloads. Content heuristics are not a universal detector
of deliberately obfuscated or externally stored data.

Historical evidence reports retain their original source identities. Payload
links and original evidence manifests are historical receipts; their files have
been withdrawn from the current tree. Reproduce with the retained generators
and temporary inputs. Do not interpret removed binary artifacts as available
for fresh inspection or their original hashes as hashes of the cleaned tree.

**History boundary:** this normal commit removes files from this branch's latest
tree only. Earlier commits, main and other refs may still expose files. Main
currently includes the former Studio fixture. A purge across shared history and
GitHub caches requires a separately coordinated history rewrite and repository
administrator follow-up; none is performed under this no-main-merge change.

## Verification

All **170 focused tests passed, with no skips**, including the five original
failing cases and the generated Studio print fixture. The strict tag audit has
zero findings; all 56 audit regressions and eight repository guard tests pass.
The initial fixture-helper build failure (missing inner `try` in Testing macros)
was corrected and its log retained. The first complete Debug execution reported 15,825 tests and 55 XCTest skips.
All original five failures passed; one Print SCP test exposed an additional
direct path to the removed fixture. A second DCMTK test had the same path and
could silently skip. Both now use the shared source generator. In the repeat run, the previously
failing Print SCP case passes and the independent-peer XCTest product passes;
the remaining complete suite is still running. The failed full-run log is retained.
The initial
post-removal scan of 7,497 previously tracked, remaining files reported zero
prohibited/uninspected payloads; the final scan must also include new files.
Final counts, source identity, CI runs and remaining skips will be recorded here
after execution. No new native GUI or physical-device qualification is claimed.

Milestone artifact uploads now allow only `.log`, `.json` and `.txt` reports,
so future generated DICOM/wire inputs remain on the runner. Existing historical
GitHub Actions artifacts have not been purged.

The prior PR general-CI macOS job lost runner communication during toolchain setup before tests;
it is distinct from the five comprehensive failures. Other prior PR milestone
and documentation workflows passed. Fresh branch CI will determine the repaired
head's status. Queued comprehensive run `41181621127` was canceled before
execution because the shared-fixture follow-up superseded its source. It is
not recorded as a test pass or a test failure.
