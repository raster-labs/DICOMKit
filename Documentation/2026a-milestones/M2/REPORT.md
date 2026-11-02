# M2 — Attribute integrity and workflow datasets

Completed locally on 24 October 2026: **A-01–A-09, NET-06-A, NET-06-B and NET-07-A**.
All 12 items meet their recorded applicable acceptance criteria. M3 has not started.
The work continues from M1 commit `3625b3317229584e42b831efd07c45019ff8236f`
on `codex/dicom-2026a-milestones`. Main and the original checkout are unchanged.
Remote qualification belongs to the pushed commit's checks; this report records
the source-qualified local results and does not predict a future CI result.

## Completed repairs

| Item | Result and verification |
|---|---|
| A-01 | Shared stored-value VR grammar, VM, UID/calendar and numeric checks reject all nine recorded malformed edits. Dry-run and write use the same transaction; failed edits preserve originals. Actual CLI and packaged Workshop refusals, valid Rows, range limits, empty Type 2 and partial DT controls passed. |
| A-02 | Tag saves synchronize dataset and File Meta SOP identity; the writer recalculates group length from encoded bytes. Separate class-only and instance-only CLI/app edits and independent byte inspection passed. Changing a class UID does not establish a new IOD. |
| A-03 | Text decoding retains its charset context; writes preserve compatible encodings or transcode consistently with declarations. Latin-1, UTF-8 and Japanese ISO 2022 read/edit/write checks passed, including significant leading whitespace, inherited/overridden item contexts and malformed declaration/byte refusals. |
| A-04 | Level-2 validation visits sequence items recursively and reports item paths plus leaf tags. Multiple/deeper/undefined-length sequence tests pass without imposing root SOP requirements on each item. Actual nested app diagnostics agree with CLI. |
| A-05 | Exact Gregorian and compact DT/TM validation rejects impossible components while preserving legal precision, fractions and UTC offsets. Invalid and valid packaged-app reports match CLI. |
| A-06 | Mandatory File Meta fields are checked for presence, nonempty value, VR/VM, UID, version bits, raw encoded group length and dataset identity. Individual automated controls and actual level-1/2 CLI/app reports passed. |
| A-07 | Registered VR mismatch is a conformance error without strict mode. Parsing retains the original explicit VR; successful parsing is separate from `isValid=false`. JSON/text and strict on/off agree in CLI and app. |
| A-08 | CLI/app share one numeric-aware copy selector parser. Numeric, parenthesized, compact-hex and keyword forms select the intended tag; invalid/absent selectors fail explicitly. Compatible actual-file copies preserve VR/raw bytes; cross-charset copies retain text. |
| A-09 | New or updated US/SS fields resolve from final Pixel Representation, regardless of edit order. Explicit/implicit and item-context tests passed. Actual app/CLI insertion encodes −1 as `SS FF FF`; existing-value update encodes −2 as `SS FE FF` and yields identical files. |
| NET-06-A | UPS server responses emit compact DICOM DT. Independent parsing of actual request-router responses verifies precision, offset and instant. The separate client encoder remains unchanged. |
| NET-06-B | UPS create/update accepts legal compact DT and rejects invalid/separated ISO-only forms atomically. Invalid updates retain the prior schedule. Backend create/update/retrieve/search tests passed. Generic attribute update has no Workshop route: that UI case is explicitly not applicable. |
| NET-07-A | MPPS refuses an image instance without an actual class before networking. CLI/app CT, MR and SC captures contain correct pairs and agree except generated end timestamps. Existing typed API mixed-list and both-transfer-syntax tests passed. |

The per-criterion results and evidence pointers are in [items.json](../items.json).
`DataSet+DictionaryVR.swift` is unchanged; implicit signed-VR handling lives in
a separate bounded resolver.

## Verification

| Gate | Result |
|---|---|
| Focused Core suites | 235 passed: 16 XCTest + 219 Swift Testing |
| Tag CLI tests | 13 passed |
| Validator CLI tests | 21 passed |
| Kit dataset/edit/charset suites | 55 passed: 42 XCTest + 13 Swift Testing |
| UPS/web suites | 74 passed: 46 XCTest + 28 Swift Testing |
| MPPS/network/workflow suites | 77 passed; one opt-in receiver skipped in this normal run |
| Workshop execution/preview regressions | 33 passed |
| Audit infrastructure regressions | 30 passed |
| Repeatable CLI process campaign | 72 invocations passed, with independent byte checks and unchanged-source assertions |
| Packaged Workshop | 71 captured records across 12 groups: 69 primary cases and two supplementary repeats |
| Independent GUI artifacts | 17 checks passed; all 19 saved validation reports match fresh CLI at the same level, excluding path/duration |
| Actual MPPS capture | Opt-in receiver separately passed; six associations/six datasets, CLI and app CT/MR/SC; both missing-class refusals add zero associations |
| Actual UPS client capture | Four requests: CLI POST/GET, then app POST/GET. Normalized POST bodies match, preserving `20261024103000.123456+0530` and UTC `05:00:00.123456` |
| App and five CLI builds | Passed using locked dependencies, Swift 6.4/Xcode 27, native macOS arm64 |

The focused product-test total is **508 passed**, plus 30 audit regressions.
The separately enabled receiver is one additional passing test. A skipped opt-in
test is not counted as a pass. GUI records, report comparisons and process probes
overlap scenarios and are not summed into a misleading total.

[verification.json](verification.json) records source/package/artifact hashes,
test counts and log hashes. [ui-verification.json](ui-verification.json),
[gui-file-parity.json](gui-file-parity.json), [network-parity.json](network-parity.json)
and [cli-verification.json](cli-verification.json) retain the detailed results.
[REPRODUCE.md](REPRODUCE.md) identifies the repeatable gates and actual app target.
The new **Attribute and workflow integrity** workflow runs the focused automated
gates; **Command safety** supplies the existing regression gate on the pushed head.

## Qualification corrections and limits

The initial app build selected the package library scheme also named
`DICOMStudio` and left the previous bundle in place. Its initial GUI result is
excluded. A temporary identical scheme with a distinct name then built
`DICOMStudioApp`, relinked the bundle, and the app was quit/relaunched by exact
path before every published GUI capture. The temporary scheme was removed.

Earlier test failures led to a local legacy `timeValue` compatibility repair,
without weakening strict stored-value validation. A test incorrectly treated
Graphic Data as VM 2-2n; the frozen dictionary specifies 2-n. The corrected test
uses Reference Coordinates for 2-2n and explicitly accepts three Graphic Data
values. Final source-current gates passed. The initial UPS capture fixture also
incorrectly required a client-supplied SOP Instance UID; that probe is excluded.
The corrected synthetic peer assigns a UID and is used only for client capture.

These are focused M2 results, not complete project or clinical conformance:

- Scalar stored-value validation does not replace query matching rules; ranges,
  wildcards and query integration remain M3 work.
- US/SS resolution covers newly set dependent values and implicit parse context.
  Changing Pixel Representation alone does not rewrite untouched fields, and
  full contextual multi-VR validation is not claimed.
- The mixed-class MPPS test uses the existing typed service API. The current
  CLI/app form accepts one explicit class for its image list; no import control
  or intermediate MPPS update enhancement was added.
- UPS GUI GET uses its existing table. It does not display DT. Scheduling proof
  comes from captured request bytes and independently inspected server responses;
  a capture peer is not proof of production server conformance.
- Supported charset cases and item contexts were exercised; this is not exhaustive
  repertoire/platform coverage. Strict conversion refuses undecodable input.
- App tests used synthetic temporary files and loopback peers. External vendor
  interoperability, physical printers, complete IODs, other platforms and final
  integrated qualification remain later gates. No clinical library data was used.

Normative sources are the frozen DICOM 2026a originals recorded in the M0 baseline:
[PS3.5](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/PS3.5.html)
Table 6.2-1 and §§6.1–6.4; [PS3.6](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part06/PS3.6.html)
registered VR/VM; [PS3.3](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part03/PS3.3.html)
C.12.1.1.2 charset tables; [PS3.10](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part10/PS3.10.html)
Table 7.1-1; MPPS/UPS requirements in PS3.4, PS3.7 and PS3.18. CLI syntax itself
is a product contract; DICOM requirements apply to the encoded data and protocol.

## Pending and stop boundary

Of 68 original actions, **19 are completed, 27 active actions remain pending,
and 22 remain deferred**. The pending counts are M3: 11, M4: 5, M5: 7, M6: 2,
and M7: 2. Twenty-two product bug-fix actions remain open.

M0-COV-01 remains visible: Workshop lacks the anonymization `--profile` control,
without demonstrated policy divergence. It was not hidden or expanded into an
unauthorized enhancement. Enhancement scope remains only `dicom-print` and
`dicom-printscp` in M6. **Stop before M3. No merge or release is authorized.**
