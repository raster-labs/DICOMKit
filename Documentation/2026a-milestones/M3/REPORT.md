# M3 — Query safety and filters

24 October 2026. M3 implementation and local verification are complete on
`codex/dicom-2026a-milestones`, based on M2 commit
`56b1b7f03fd4dc0915c49a45e8d181a152e24634`. M4 has not started. This report qualifies
the bounded M3 changes; it is not whole-project or external-PACS conformance.

## Completed repairs

| Item | Result | Principal evidence |
|---|---|---|
| NET-01-A | Malformed/negative/overflowing pagination is rejected with 400; zero values are legal; provider slicing cannot overflow; stable ordering and filtered counts/warnings | 33 isolated child-process probes; direct provider boundary tests |
| NET-02-A | Series queries apply permitted patient/study predicates and series predicates together | Independent multi-patient HTTP result-set oracles |
| NET-02-B | Instance queries apply permitted parent predicates and both path UIDs; unrelated patients/series cannot leak into matches | Scoped/unscoped instance HTTP oracles |
| NET-02-C | Instance Number is indexed and matched numerically; missing values do not inherit a sibling's number | Keyword/tag, signed/zero-padded IS and intersecting SOP UID probes |
| NET-02-D | PPS date/time and nested request attributes are matched, including mixed keyword/tag paths and same-item sequence matching | Individual filters, cross-item negative control, missing sequence, permitted instance resources, combined date/time boundary tests |
| NET-02-E | Comma-separated UID alternatives are ORed within a key and ANDed with other keys; encoded commas survive parsing | Study/series/SOP UID-list HTTP cases and outgoing CLI captures |
| NET-02-F | Optional return fields, repeated/comma/nested inclusions and `all` are honored; mandatory defaults remain; `all` mixed with other entries is rejected | Response tag/VR/value oracles; private creator, scope and cache-key regressions |
| NET-03-A | One resource policy selects the six QIDO paths and their allowed filters for CLI and Workshop | Six-form CLI capture matrix and packaged-app request equality |
| NET-03-B | Valid instance PPS filters no longer receive a false ignored warning; preview and execution use the same effective values | Shared transition matrix with WS-FIX-03 |
| NET-04-A | Unsupported high-level DIMSE filter/level combinations fail before association and before the verbose query header; accepted filters remain in the Identifier | Eight CLI peer cases; three packaged successes and four refusals with unchanged association counts |
| WS-FIX-03 | Inapplicable QIDO values are retained but excluded from preview/request, restored when applicable, and cleared on tool change | Packaged level/scope transitions and fresh-versus-transitioned ViewModel parity tests |

The 11 ledger actions contain 35 acceptance criteria. Exact criterion-to-test
links are in [acceptance.json](acceptance.json) and the updated [ledger](../items.json).
NET-03-B and WS-FIX-03 share one implementation and evidence matrix.

## Verification

- **538 focused runtime tests passed:** DICOMWeb 238, DICOMNetwork 100,
  dicom-query 14, dicom-wado 27 and DICOMStudio 159.
- **30 audit regressions passed.** The pre-existing M0-COV-01 Workshop
  anonymization-profile coverage finding remains visible and unchanged.
- The independent QIDO campaign checks isolated pagination, actual HTTP requests
  through the production router/provider, exact result UIDs/attributes and real
  CLI requests. Its final probe count and individual results are recorded in
  [verification.json](verification.json) and [queries/results.json](queries/results.json).
- **Eight DIMSE CLI cases passed** against an independent Python C-FIND peer:
  four accepted requests and four refusals with no association.
- A freshly linked **DICOMStudioApp** passed **17 recorded GUI checks**: nine
  QIDO executions across all six resource forms, one observed tool reset,
  three DIMSE executions and four DIMSE refusals. **16 equivalent CLI replays**
  matched actual requests, expected result UIDs and the visible console text.
  QIDO captures include restored PPS filters, excluded hidden filters and the
  synthetic UTF-8 name `Müller^Synthetic`.

Native accessibility truncates the newest console item. The comparison therefore
uses the visible console prefix/status, complete wire responses and independently
parsed CLI JSON; it does **not** claim byte equality for the entire GUI console.
The reset check observed a cleared form/preview and disabled Run. No post-reset
request was executed. UID-list edge cases are covered by HTTP/CLI and shared
Workshop request-planning tests, rather than a separate packaged GUI UID-list run.
See [ui-verification.json](ui-verification.json).

Five tests were skipped in the normal focused run. The opt-in M3 process harness
was then executed explicitly by the independent campaign; four existing external
DIMSE integration tests remain **unexecuted**. No external PACS, physical printer,
or other operating-system runtime was qualified.

## Issues found and repaired during verification

Review caught sibling metadata inheritance, date/time cross-day and microsecond
boundaries, invalid non-UID comma matching, missing private creator projection,
study SOP-class aggregation and optional timezone/availability projection. These
were repaired before the final runtime run and have regression coverage.

The existing Latin-1 query JSON fixture also exposed lost character-set context
after the M2 transcoding repair. Query JSON formatting now binds transcoded UTF-8
to its dataset, respects nested character-set overrides and inheritance, and
passes the unchanged Latin-1 fixture plus new regressions. This is a query-output
integrity repair, not a new feature.

The final evidence review added independent standalone predicate probes so that
combined filters cannot conceal an ignored predicate. CI now also triggers when
its independent DIMSE peer or toolchain selector changes.

## Standard basis and compatibility

The frozen 2026a sources and hashes remain in the M0 baseline. This repair uses
[PS3.18 10.6](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part18/sect_10.6.html)
for QIDO resource scope, required keys, responses and pagination, PS3.18 8.3.4
for matching/return parameters, and
[PS3.4 C.2.2.2](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part04/sect_C.2.2.2.html)
for matching semantics, including UID lists, sequences and combined date/time
ranges. Dictionary tag/VR values use the frozen PS3.6 data; JSON follows PS3.18 F.2.

The repository's `InMemoryStorageProvider` is the qualified backend. Third-party
providers remain source-compatible through defaulted requirements, but must opt
into the canonical matching contract and supply the required metadata before
filtered requests are accepted. Otherwise the server returns **501 before search**
instead of silently ignoring predicates. Unknown/unsupported matching keys return
400. This safety boundary requires custom-provider adoption; it is not evidence
that external backends already implement the contract.

The production DICOMweb server remains an embedding request router; the HTTP
listener used here is test infrastructure. DIMSE relational negotiation was not
added. High-level query filters now fail explicitly when unsupported; callers
constructing raw Identifier keys retain responsibility for those keys.

## Completed and pending

M0–M3 close **30 of 68 original actions**. **16 active actions remain pending**:
M4 service reliability (5), M5 remaining Studio contracts (7), M6 print/printscp
Workshop coverage (2), and M7 final qualification (2). **22 actions remain deferred.**
Enhancement scope remains limited to dicom-print and dicom-printscp.

Remote CI must be evaluated on the pushed commit; local results are not remote
CI. The final remote verification accompanies the completion deliverable. Main is
unmerged. Stop before M4 until the user's next instruction.
