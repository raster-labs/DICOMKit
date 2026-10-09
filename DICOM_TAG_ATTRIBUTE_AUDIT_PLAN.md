# DICOM Attribute ↔ Tag Consistency Audit Plan

## Why

The MWL bug: `requestedProcedureDescription` was wired to **(0032,1070)** (Requested Contrast Agent)
instead of **(0032,1060)** (Requested Procedure Description). The doc comment, the Swift identifier and
the JSON key all agreed with each other — only the hex was wrong — so nothing caught it until a real
SCP returned nothing. The same failure shape (name says X, number says Y) can exist anywhere a tag is
spelled by hand. This plan finds every such spot, checks it, and makes the check permanent.

## Audit surface (measured)

| Form | Count | Where |
|---|---|---|
| `Tag(group: 0x…, element: 0x…)` literals | 1 374 | 60 files; DICOMNetwork alone has 208 |
| Named constants `Tag.xxx` in `Tag+*.swift` | 939 | DICOMCore |
| 8-hex string keys `"00321060"` (DICOM JSON / QIDO) | 363 | DICOMWeb, DICOMNetwork, CLIs, Studio |
| `(gggg,eeee)` in comments/docs | 2 421 | everywhere |

Ground truth already exists in-repo: `Sources/DICOMDictionary/Resources/DataElementDictionary.txt`
(PS3.6 2026a, 5 036 entries: tag | name | keyword | VR | VM). The audit is driven by it, not by
reading the standard by eye.

---

## Phase 0 — Tooling (~½ day, first)

One script, `Scripts/audit-tags.py`, that loads the dictionary and emits
`file:line | expected | actual | severity`:

1. **Literal ↔ comment** — for every `Tag(group:element:)` with a human name on the same/previous
   line (`// Requested Procedure Description`, `/// … (0032,1060)`, or an identifier like
   `requestedProcedureDescription`), resolve name → keyword and compare the tag.
   Mismatch = **BLOCKER**. This is exactly the MWL bug.
2. **Named constant ↔ keyword** — every `public static let <name> = Tag(…)` in `Tag+*.swift`:
   `<name>` must equal the dictionary keyword (small explicit alias list allowed).
3. **String key ↔ comment** — same as (1) for `"GGGGEEEE"` JSON keys and `(GGGG,EEEE)` doc comments.
4. **Unknown tag** — literal not in dictionary and not private/odd-group → WARN.
5. **VR sanity** — where a VR is written explicitly (`["vr": "LO", …]`, `DataElement(tag:vr:)`),
   compare to dictionary VR. Mismatch = MAJOR.

Deliverable: `audit-report.md` grouped by target, BLOCKER → MAJOR → WARN.

## Phase 1 — Mechanical sweep (~1 day)

Run the script; fix every BLOCKER/MAJOR, replacing raw literals with `Tag.xxx` (add missing
constants to the right `Tag+*.swift`). Order by blast radius:

1. **DICOMNetwork** — `ModalityWorklistService`, `MPPSService`, `QueryKeys`, `StorageCommitment*`,
   `PrintService` / `PrintSCPEncoder` / `PrintDatasetReader`, `CommandTag`
2. **DICOMWeb** — `QIDOQuery`, `QIDOResults`, `DICOMwebClient`, `ConformanceStatementGenerator`
3. **CLIs that build/parse datasets** — `dicom-mwl`, `dicom-mpps`, `dicom-qr`, `dicom-query`,
   `dicom-retrieve`, `dicom-server`, `dicom-printscp`, `dicom-ai`, `dicom-wado`
4. **DICOMStudio** — tag view, patient overlay, print, Workshop helpers (the UI shows the *name*,
   so a wrong number is invisible — same trap as MWL)
5. **DICOMKit parsers/serializers** — SR, RT, Seg, ParametricMap, Multiframe, Anonymization profiles
6. **DICOMCore `Tag+*.swift`** — check (2) covers all 939 wholesale

## Phase 2 — Semantic audit per service against PS3.4 / PS3.18 (~2 days)

The script proves *number == name*; it cannot prove *the right set of keys is used*. For each
service, transcribe the standard's table and diff it against the code:

| Service | Code | Standard table | Check |
|---|---|---|---|
| MWL C-FIND | `WorklistQueryKeys`, `WorklistItem`, `dicom-mwl`, Studio Workshop | PS3.4 **K.6-1** | every R/O matching key supported; every return key in `default()` *and* readable from `WorklistItem`; SPS keys nested in (0040,0100); PN wildcard / DA-TM range semantics |
| MPPS N-CREATE / N-SET | `MPPSService`, `dicom-mpps` | PS3.4 **F.7.2-1** | Type 1/2 on CREATE; SET touches only allowed attrs; Performed Series Seq contents |
| Q/R C-FIND | `QueryKeys`, `QueryService`, `dicom-query`, `dicom-qr` | PS3.4 **C.6.1-x / C.6.2-x** | U/R/O keys per level; `QueryRetrieveLevel` set; (0020,12xx) counts readable |
| C-MOVE / C-GET | `dicom-retrieve` | PS3.4 C.4.2 / C.4.3 | unique keys per level only |
| Storage Commitment | `StorageCommitmentService/SCP` | PS3.4 **J.3.2** | Referenced/Failed SOP Seq, Failure Reason, Transaction UID |
| Print | `PrintService`, `PrintSCPEncoder`, `dicom-print(scp)` | PS3.4 **H.4.x** | Film Session/Box/Image Box attribute sets |
| QIDO-RS | `QIDOQuery`, `QIDOResults`, `dicom-wado`, `ConformanceStatementGenerator` | PS3.18 **10.6.1-5 / 10.6.3-x** | required return attrs per level; `includefield` keyword ↔ tag |
| UPS (if any) | grep `(0074,` | PS3.4 CC.2.5 | — |

Output per service: `Docs/audit/<service>-keys.md` with ✅ / ❌ / ➖ (deliberately unsupported).
Each ❌ becomes an issue.

## Phase 3 — Structural correctness (~1 day)

What a tag-number check won't catch:

- **Nesting** — keys that belong inside a sequence item (SPS (0040,0100), Referenced Study
  (0008,1110), Scheduled Protocol Code (0040,0008), Requested Procedure Code (0032,1064)) are placed
  there *and* the reader looks in the same place.
- **Return-key completeness** — every attribute an `*Item` struct reads is sent as an empty return
  key in the default query; otherwise the SCP silently omits it → `nil`.
- **Matching-value encoding** — DA/TM/DT range (`-`), PN wildcard (`*`,`?`), UID list (`\`), CS case,
  empty-vs-absent.
- **SCP side** (`dicom-server`, `dicom-printscp`, Workshop MWL/MPPS SCPs) — responses carry all
  requested Type 1/2 attrs; unsupported keys ignored, not rejected.
- **Keyword-based APIs** (`DataElementDictionary.lookup(keyword:)`, QIDO `includefield`, CLI `--tag`)
  — keyword spelling/casing matches PS3.6 exactly.

## Phase 4 — Tests (~1 day, interleaved with fixes)

1. **Dictionary-driven constant test** (DICOMCoreTests) — iterate every `Tag.xxx` and assert
   `DataElementDictionary.lookup(tag:)?.keyword == "<Name>"`. One test, 939 assertions, kills this
   bug class permanently.
2. **Per-service key-table tests** — encode `<Service>QueryKeys.default()` and assert the exact tag
   set (top-level + per-sequence) against the PS3.4 table as fixture data. Extend
   `WorklistQueryKeysTests` (already started) to MPPS, Q/R, Print, QIDO.
3. **Round-trip tests** — build a response dataset from the standard's table → parse with `*Item` →
   every property non-nil. This is what would have caught (0032,1070).
4. **Golden fixtures** — one anonymised real-world MWL/MPPS/Q-R response per service.

## Phase 5 — Guardrails (~½ day)

- Run `Scripts/audit-tags.py` in CI; fail on any BLOCKER.
- Lint: no bare `Tag(group:element:)` outside `DICOMCore/Tag+*.swift` and
  `PrivateTagDictionary.swift` — use `Tag.xxx`. Allow-list existing files, ratchet down.
- Doc-comment convention: `/// Requested Procedure Description (0032,1060) LO 1` so the script
  cross-checks name, tag *and* VR.
- CONTRIBUTING: "Never type a tag number without its dictionary keyword next to it."

## Phase 6 — Tracking

- One GitHub issue per Phase-2 ❌, label `dicom-conformance`.
- `Docs/audit/README.md` records per-service checklists and the PS3.6 edition audited.
- Re-run the script on every dictionary refresh — retired/renamed keywords surface as mismatches.

## Order & effort

| Step | Effort | Unblocks |
|---|---|---|
| Phase 0 script | 0.5 d | everything |
| Phase 1 mechanical fixes | 1 d | Phase 4.1 |
| Phase 2 — MWL + MPPS + Q/R first, then Print, QIDO | 2 d | Phase 4.2–4.3 |
| Phase 3 | 1 d | — |
| Phase 4 | 1 d | Phase 5 |
| Phase 5 + 6 | 0.5 d | — |

≈ 6 working days total. Phases 0–1 alone give most of the value and can ship as a single PR.

## Workflow rule

Each phase: run → list findings → **user verifies** → fix. No fixes land before the finding list is
reviewed.
