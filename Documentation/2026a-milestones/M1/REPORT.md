# M1 command and execution safety — completion report

24 October 2026. **M1 is implemented and locally verified. Stop before M2.**
Branch: `codex/dicom-2026a-milestones`. No merge or release was performed.

## Completed items

| Item | Repair | Verification |
|---|---|---|
| WS-FIX-01 | Quote literal command arguments for sh/zsh, including wildcards, backslashes, quotes, whitespace, substitutions and leading `=`; preserve catalog executable/subcommand boundaries. | Real shell argv capture, injection sentinels, actual packaged tag edit and byte-identical CLI output. |
| WS-FIX-02 | Bind leading-hyphen option values using `--flag=value`; preserve short `-o=value` parsing. | Real `DICOMMWLCommand` parser and shared key builder accept open-ended/bounded/scalar DA/TM values; malformed cases reject. Packaged preview and runtime header retain the range values. |
| WS-FIX-05 | Detect Basic-auth capability by stable tool ID; comment every physical line of an app-only preview. | All four catalog entries, renamed labels, multiline values and no-auth/Bearer transitions tested. All four Basic forms checked in the packaged app. Passwords are not emitted. |
| TB-FIX-04 | Keep executable and literal argv separate from display text; launch directly with `posix_spawn`; safely stream output, cancel process groups and replay history. | Complete Toolbox package suite, including live stdout/stderr, split UTF-8, large output, nonzero/rapid exits, launch failure, overlap, task cancellation and stubborn descendants. |

DICOM 2026a DA/TM range and VM syntax is preserved across the form/command boundary.
The existing shared range validator and attribute dictionary remain unchanged.
This does not close the attribute-validation defects assigned to M2.

## Verification results

- **151 Swift tests in 4 Workshop suites passed**: 8 shell/parser safety tests,
  4 parameterized Basic-auth tests (16 catalog cases), existing helpers and network option parity.
- **488 Swift tests in 82 Toolbox suites passed**, including 20 focused safety tests (14 new and 6 existing execution tests).
- **30 M0 Python audit regressions passed**.
- Fresh macOS `DICOMStudio` scheme Debug build passed. A final incremental build
  required no compilation/relinking, confirming the UI-tested app was current.
- Fresh CLI products built. CLI and Workshop output files are **382 bytes** and
  **byte-identical**, SHA-256
  `7d0d089513b42989d8b4f18508ef2e3b3946289e32f1611628965b59698abfe0`.
- Independent explicit-VR decoding confirmed `(0008,0008)` CS `ORIGINAL\PRIMARY`,
  `(0010,0010)` PN `DOE*`, and `(0008,1030)` LO `M1 $HOME (literal)`.
  The synthetic source file remained unchanged.
- Source review and whitespace checks passed. No runtime shell is used by the
  Toolbox executor; shells in tests are intentional serialization oracles.

[Verification and artifact hashes](verification.json), [packaged UI actions](ui-verification.json),
[fixture comparison](fixture-parity.json), [Workshop log](studio-tests.log),
[Toolbox log](toolbox-tests.log), [audit regression log](audit-regression.log).
The `Command safety` workflow publishes checks and logs for the pushed implementation commit.
Remote status must be read from that commit's Actions results; local tests are not a remote CI claim.

## Compatibility and implementation decisions

`CommandExecutor.execute(command: String, ...)` is replaced by
`execute(invocation: CommandInvocation, ...)`. Callers supply an executable and
literal arguments. This is an intentional source API change; there is no unsafe
string-execution compatibility overload. Cancellation throws `CancellationError`;
ConsoleView displays it distinctly and waits for output drainage before final status.
A second launch is refused while the current invocation is running or stopping.

Process groups are established atomically at launch. Cancellation sends TERM,
then KILL after a one-second grace period. The exited group leader is retained
until cleanup, preventing delayed signals from targeting a reused process-group ID.

New history stores the structured invocation. Legacy history stays readable but
cannot be replayed; copying/exporting it produces comments asking the user to rebuild
that command. This prevents old unquoted strings re-entering the execution path.
Toolbox profiles, parameter definitions and stale flags remain M5 work.

## Packaged-app scope and environment observations

The actual app was launched, the affected controls and previews were inspected,
and the synthetic tag operation was executed. MWL valid ranges reached the runtime
header; the deliberate localhost/no-peer check ended in a connection timeout.
A malformed date range failed shared validation. This is argument-path evidence,
not a successful MWL interoperability exchange. Basic auth was checked separately
for query, retrieve, store and UPS; a synthetic Bearer token was displayed and then
removed by selecting no-auth. No HTTP request or real credentials were used.

The first fixture read from Documents stalled in a Foundation file-open call.
The cause was not conclusively established. The same bytes in `/private/tmp`
executed successfully after restarting the app. No privacy setting was changed;
Documents-path access remains unqualified by this run. Some accessibility text
was stale, so rendered screenshots and execution output were also inspected.

DICOMToolbox is a separate library and is not linked by this DICOMStudio app target.
Its SwiftUI ConsoleView compiled and its actual subprocess executor passed runtime
tests. There is no standalone Toolbox application target here; no separate Toolbox
GUI runtime pass is claimed. Linux runtime, independent peers and physical printing
remain later qualification work. The synthetic file is not a complete clinical IOD.

## Pending items and boundary

M1 has no remaining implementation or item-acceptance failures. Broader platform,
file-access and interoperability qualification is explicitly outside this result.
Of the original 68 items: **7 completed, 39 active pending, 22 deferred**.
M2's 12 items are **not started**. M3–M7 also remain not started. The M0-COV-01
anonymization-profile coverage finding remains visible; no new non-print enhancement
was introduced. Only `dicom-print` and `dicom-printscp` enhancements remain in scope.

Do not start M2 or merge into main without the user's next instruction.
