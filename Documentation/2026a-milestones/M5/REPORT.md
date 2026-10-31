# M5 — Workshop and Toolbox contract corrections

M5 local acceptance is complete within the recorded scope: **22 criteria passed; 2 conditional criteria are not applicable**. The seven scoped items are WS-FIX-04/06/07/08 and TB-FIX-01/02/03. The exact assertions, named tests and case evidence are in [acceptance.json](acceptance.json).

Qualification uses M4 baseline `441ae21ab09bbb18687baa06baa131831a3ac10d` plus the 27-file frozen M5 overlay. The source snapshot, baseline build inputs and recorded binary hashes are retained. Concurrent M6 source, build outputs and mixed-tree audit results are excluded. See [source provenance](evidence/source-provenance.json), [source hashes](source-hashes.json) and [verification](verification.json).

## Behavior established

- Workshop live script execution is unavailable before Run with clear CLI guidance. Template generation, validation and dry-run work. Unknown commands and unsupported conditional pipelines fail deterministically with useful errors. A live dispatcher was not added.
- QR offers explicit Review and Auto behavior. Review retrieves no files; Auto retrieves matching files. Persisted Interactive values refuse before dispatch. Actual interactive selection remains deferred.
- SR TIME/DATETIME display preserves fractions, trailing zeroes, partial precision and signed UTC offsets. Malformed input stays visible without normalization. Six tests, sixteen exact fixture values and native display/copy checks preserve the source file hash.
- Allow Burned-in PHI has one parameter identity and one flag. Beginner advanced disclosure and Advanced mode preserve one binding. With pixel cleaning disabled, refusing the override writes no output; enabling it writes the synthetic object with Patient Identity Removed = NO.
- Toolbox offers only the current `ps315`/`basic` profile tokens, with explicit retention choices. Removed profiles/flags in presets and persisted history receive actionable refusal. Default UID replacement and explicit `--retain-uids` are checked on real synthetic outputs.
- Toolbox template names are required positional arguments. All five generated templates pass the real CLI validator; the retired template `--output` is refused. Console copying/test-side stdout saving is separate from the CLI. M1 structured argv protections remain in place.

These are application contract corrections. DICOM 2026a PS3.5 §6.2 TM/DT lexical meaning and PS3.15 Annex E confidentiality choices inform the temporal and anonymization checks; neither profile names nor these tests certify de-identification or complete DICOM conformance.

## Executed evidence

| Layer | Passed | Evidence |
|---|---:|---|
| Toolbox suite | 499: 11 XCTest + 488 Swift Testing | [log](evidence/DICOMToolboxTests.log) |
| Studio focused suite | 213: 16 XCTest + 197 Swift Testing | [log](evidence/DICOMStudioTests.log) |
| Script round-trip suite | 28 XCTest | [log](evidence/DICOMRoundTripTests.log) |
| Separate opt-in Workshop harness | 1 XCTest / 23 VM actions | [log](evidence/workshop/workshop.log), [actions](evidence/workshop/workshop.json) |
| Frozen-source audit regressions | 30 | [log](evidence/audit-regressions.log) |
| Toolbox actual CLI campaign | 23 cases, including expected refusals | [results](evidence/toolbox-cli/results.json) |
| Workshop paired CLI campaign | 22 CLI cases / 23 VM actions | [results](evidence/workshop/results.json) |
| Native packaged DICOMStudio | 10 cases | [record](evidence/ui/ui-verification.json) |
| Additional native QR CLI replays | 2 | [byte comparisons](evidence/ui/comparisons.json) |

The regular suites total **740 passes: 55 XCTest and 685 Swift Testing**. The ordinary Studio run skipped its one opt-in harness; the separately activated run passed it. No skip is counted as a pass. CLI, GUI and VM action counts are separate behavioral campaigns, not extra test methods. The Toolbox exporter is already included in its 11 XCTest passes.

The app build succeeded and relinked DICOMStudioApp. Native checks covered live-script refusal, Dry Run, Validate, workflow template, conditional-pipeline error, PHI off/on across experience modes, QR Review/Auto, and sixteen SR values with native copy. Only the workflow template was exercised manually; all five were covered by CLI/VM checks. GUI Dry Run is an explicit operator-witnessed observation: the retained AX delta alone does not show the result; [its observation record](evidence/ui/script-dry-run-observation.json) states that limitation. QR retrieved dataset bytes agree across GUI, CLI and fixture; SR source SHA256 remains `699134bd8df05a835a364c74886769581959c602e0bfd5dbf812b0be520f57a6`.

## Repairs and boundaries

Independent review found a real conditional-pipeline validation hole. The frozen implementation refuses unsupported unquoted pipelines in conditionals; the repaired full negative gate passed. Initial stale Toolbox expectations and two CLI oracle mismatches (verbosity and pixel-cleaning policy) were corrected and rerun. [Repair provenance](evidence/repair-provenance.json) links the retained initial records and distinguishes product repair from oracle repair.

WS-FIX-04-AC01 is conditional on adding live Workshop execution, which the plan excludes. WS-FIX-06-AC02 is conditional on adding interactive selection, which remains deferred. Both conditions and future gates remain explicit; neither is counted as passed or waived.

DICOMToolbox is a separate library, not linked into DICOMStudio, and there is no standalone Toolbox app target. Its library form/argv/history checks and real CLI gate passed; a packaged Toolbox UI gate is **not applicable**. No application integration was added to manufacture that gate.

The campaign uses synthetic files and loopback services. It does not qualify physical printing, an external PACS, OCR/pixel-cleaning quality, full IOD conformance, all project tools, or a clinical deployment. M0 audit regressions do not close unrelated coverage gaps. This package records local acceptance; exact-head CI and any publication are separate parent-owned steps. No merge or release is claimed.
