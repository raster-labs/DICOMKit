# E1 — intermediate MPPS and retained metadata integrity

Authorized 26 October 2026: NET-08-A, WS-DORM-01 and WS-DORM-02 only. Work remains on `codex/dicom-2026a-milestones`, following `4e5ca590275a8ff77a29e5bb4e0804c84f692642`. No main merge is authorized. E1 extends the original scope to 49 items; 19 remain deferred. All ten item criteria passed locally. Publication/remote CI is a separate post-push step.

## Changes and standard basis

NET-08-A adds intermediate N-SET through DICOMNetwork, `dicom-mpps update` and DICOMStudio CLI Workshop. Omitted `--status` omits (0040,0252); explicit `IN PROGRESS` sends it. Intermediate updates have no end timestamps, and absent sequences are not overwritten with empty values. The new update `--procedure-step-description` modifies (0040,0254). The CLI can explicitly clear that value with an empty argument; an empty Workshop text field leaves it unchanged. Workshop retains its existing COMPLETED default and labels the omitted-status choice `Unchanged (IN PROGRESS)`.

PS3.4 2026a F.7.2.2.1/.2 requires the original N-CREATE character set, existing attributes and complete sequence replacements. Both terminal states require a nonempty Performed Series Sequence under Table F.7.2-1 Note 2; a series may contain no references if no instances were acquired. The former DISCONTINUED exemption and automatic retry after a terminal send were incorrect and are repaired. Valid existing terminal workflows remain supported; callers must supply the full acquired-series/reference snapshot. `--series-uid` can describe an acquisition with no instances.

Context is scoped to peer, calling/called AEs and SOP Instance UID in the current process. A known terminal send blocks later updates; an ambiguous terminal failure is not retried automatically. Separate CLI processes cannot recover the original character set or lifecycle from this in-memory context: callers must provide the original nondefault `--specific-character-set`, retain lifecycle information, and handle SCP failures. Intermediate raw attribute dictionaries are refused; this is a bounded typed-update interface, not arbitrary MPPS editing. The explicit legacy scheduled-step flag remains a disclosed compatibility extension, not a standards-conformant N-SET mode.

WS-DORM-01/02 retain and repair the public legacy metadata component. Source reachability inspection finds no production constructor for MetadataView/MetadataViewModel; no new app route is added and no active-screen defect is claimed. US/SS/UL/SL/FL/FD/SV/UV and AT now decode with the element byte order and preserve multiplicity. Incomplete numeric values remain visibly undecoded. Display formatting and `copyValue` are separate: decimal spellings and empty components survive row/bulk copy and filtering. Text copying excludes legal Value Field padding. Numeric copying is a documented textual representation, not a binary export; NaN payload bits, Other byte/word streams and sequence containers are outside that promise. PS3.5 §§6.2/6.4 supply encoding and multiplicity rules; clipboard UI design is a product choice.

## Verification and evidence

Results are recorded in [verification.json](verification.json) and [acceptance.json](acceptance.json). Earlier attempts and environmental failures are retained in evidence; skips, failures and unexecuted checks are not counted as passes. The existing M0–M7 receipts remain historical, unchanged-source evidence only, rather than being relabeled as qualification of E1.

- MPPS regression: 92 executed passes, one manual-only skip.
- Studio regression: 131 Swift Testing passes and 11 XCTest passes, no skips.
- Audit tooling: 48 passes.
- Independent CLI: 17 actions, 56 assertions, 14 requests.
- Independent Workshop: 19 actions, 54 assertions, 14 requests including one external CLI seed. Full action transcripts and summary are retained separately.
- Packaged app: six native actions, four N-SETs and two local refusals; 45 independent wire assertions. One rapid automation batch ran the previous omitted-status selection before the new menu choice settled; its actual intermediate sequence update is retained, and the separately observed COMPLETED execution supplies terminal acceptance.

The new typed description input enforces LO length, multiplicity and allowed controls. Failed unconfirmed intermediate charset attempts no longer pin a guessed declaration; corrected retries succeed. Both repairs have focused tests and peer evidence. Earlier compilation, environment, fixture, mock-readiness and evidence-filename issues are listed in verification.json; final accepted runs pass. No evidence from an unsuccessful attempt is promoted to a pass.

The independent peer uses pydicom/pynetdicom with synthetic loopback data. It records exact request bytes, hashes, decoded datasets and server state, and checks standard-derived expectations independently of the Swift encoder. Native acceptance is limited to the packaged MPPS Workshop route; the dormant component has focused model/parser/copy tests and an active dicom-info regression.

No external hospital system, physical device, other platform or complete IOD/conformance qualification is claimed. Post-push remote verification is separate from local item acceptance. The user retains merge authority.
