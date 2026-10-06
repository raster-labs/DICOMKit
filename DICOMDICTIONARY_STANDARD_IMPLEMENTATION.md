# DICOMDictionary — DICOM Standard Implementation Report

Generated 2026-09-28, last updated 2026-09-28. Covers all 5 Swift files in `Sources/DICOMDictionary/`
(4 hand-written, 1 generated), the bundled resource `Resources/DataElementDictionary.txt`, its
generators in `Scripts/`, and the DocC catalogue `DICOMDictionary.docc`.

**Status: complete.** All buckets and all priority items (P1–P6) are done and verified against the
frozen PS3.4, PS3.6 and PS3.7 2026a text. All 5 Swift files carry a well-formed `NEMA-verified`
marker (`Scripts/check_nema_markers.py Sources/DICOMDictionary` exits 0), and
`Scripts/diff_dictionary.py` reports 0 differences between the module's three tables and the
standard. The three DICOMCore rows for this module (D6, D7, D20) are closed; one new finding for
DICOMNetwork (D21) is recorded below. The work is committed on `feature/dicom-tag-modality-audit`,
locally, for review.

Method: [DICOMCORE_STANDARD_IMPLEMENTATION.md → Verification method](DICOMCORE_STANDARD_IMPLEMENTATION.md#verification-method-reuse-for-every-module),
used unchanged. Package target: **DICOM 2026a** (`dicomStandardEdition = "2026a"`,
[DICOMKit.swift](Sources/DICOMKit/DICOMKit.swift)).

**Scope note.** DICOMDictionary is pure standard data: the Data Element registry (PS3.6 Tables 6-1,
7-1, 8-1, 9-1 and PS3.7 Tables E.1-1, E.2-1), the UID registry (PS3.6 Table A-1) and the Storage SOP
Class list (PS3.4 Tables B.5-1, B.6-1). Its Swift files carry no DICOM behaviour beyond loading and
looking up these tables, so the audit was a row-by-row text diff, and the fix was to generate every
table from the DocBook instead of maintaining it by hand or from a third-party library. Every other
library module, the DICOMStudio app and 30 CLI tools import it, and DICOMKit derives element VRs
from it at write time (`DataSet+DictionaryVR.swift`).

---

## Summary

| Bucket | Files | Meaning | Status |
|---|---|---|---|
| A — cites 2026a | 2 (`DataElementDictionary.swift` + resource; `UIDDictionary.swift`) | Doc comment named PS3.6 2026a | ✅ Data did **not** match; both tables now generated from the 2026a DocBook (P1, P2) |
| B2 — no edition, data doesn't match | 1 (`StorageSOPClasses.swift`) | Cited PS3.4 Annex B without an edition | ✅ Now generated from PS3.4 2026a Table B.5-1 / B.6-1 (P3) |
| C1 — plumbing | 1 (`DictionaryEntry.swift`) | Value types and the `UIDType` enum | ✅ `UIDType` now has a case for each A-1 "UID Type" value |
| Generated | 1 (`UIDDictionaryEntries.swift`) | PS3.6 Table A-1 | ✅ Marker written by the generator |
| Non-Swift | resource, 4 scripts, DocC | Data, generators, docs | ✅ (P1, P4) |

### Tables, after the work (2026-09-28)

| Table in the code | Standard table (2026a) | Rows: standard / ours | Differences (`Scripts/diff_dictionary.py`) |
|---|---|---|---|
| `Resources/DataElementDictionary.txt` | PS3.6 6-1 (5,238 incl. 66 repeating rows at their base group, excl. 3 delimiters) + 7-1 (22) + 8-1 (19) + 9-1 (1) + PS3.7 E.1-1 (24) + E.2-1 (22) | 5,326 / 5,326 | 0 |
| `UIDDictionaryEntries.swift` | PS3.6 A-1 | 465 / 465 (+ 2 `unregisteredEntries`) | 0 |
| `StorageSOPClasses.swift` `allUIDs` | PS3.4 B.5-1 | 170 / 170 | 0 |
| `StorageSOPClasses.swift` `retiredUIDs` | PS3.4 B.6-1 | 4 / 4 | 0 |

### Baseline, before the work (2026-09-28, for the record)

| Table | Rows: standard / ours | Missing | Extra | Column mismatches |
|---|---|---|---|---|
| Element dictionary (from pydicom 2.4.4) | 5,263 / 5,102 | **227** | 0 | retired 5, keyword 8, name 7, VM 5, VR 3 (the last three all from the 3 blank rows) |
| Group 0000 command elements | 46 / 46 | 0 | 0 | 0 |
| `UIDDictionary` (hand-written) | 465 / 47 | 418 (31 Transfer Syntaxes) | 2 unregistered | name 5, keyword 2 |
| `StorageSOPClasses` (hand-written) | 170 / 78 | **92** | 0 | 9 abbreviated comments |

Tests: `swift test --filter DICOMDictionaryTests` — 30 tests in 4 suites pass (19 before the work).
Full `swift test` (2026-09-28): every test run passes, exit 0.

---

## Progress log

| Date | Item | What was compared | What changed | Tests |
|---|---|---|---|---|
| 2026-09-28 | Baseline | All 4 Swift files read in full. Resource diffed against PS3.6 2026a Tables 6-1/7-1/8-1/9-1 and PS3.7 2026a Tables E.1-1/E.2-1. `UIDDictionary` and `StorageSOPClasses` diffed against PS3.6 Table A-1, then `StorageSOPClasses` against PS3.4 Tables B.5-1/B.6-1. DICOMCore's verified `TransferSyntax.allKnown` cross-checked: it holds all 63 registered syntaxes, the 2 unregistered HEVC ones, and 2 private JP3D UIDs under a vendor root. | Nothing; report written with the counts above. | 19 pass. |
| 2026-09-28 | P1 | `Scripts/generate_full_dictionary.py` rewritten to read the DocBook through `Scripts/nema_docbook.py`; resource regenerated. Every column of every row verbatim. | 5,102 → 5,326 rows; 227 added, 5 retired flags, 2 keywords, 4 names, 2 VMs corrected; 6 blank-keyword rows no longer carry invented `Unknown` / `Retired-blank`. Loader: skips `#` lines, `allEntries` added, `lookup(keyword: "")` → nil. Resource header carries the provenance marker. | 30 pass. |
| 2026-09-28 | P2 | `Scripts/generate_uid_dictionary.py` → `UIDDictionaryEntries.swift`, all 465 rows of Table A-1. `UIDDictionary.swift` keeps the API and the 2 unregistered HEVC UIDs (`registered: false`). `UIDType` +4 cases, `UIDEntry` +`retired`, +`registered`. `UIDManager.uidTypeDescription` (DICOMKit) updated for the exhaustive switch. | 47 → 465 (+2) rows. D20 closed. | 30 pass. |
| 2026-09-28 | P3 | `Scripts/generate_storage_sop_classes.py` → `StorageSOPClasses.swift` from PS3.4 B.5-1 and B.6-1, names from A-1. Existing 78 keep their order first (negotiation priority), the other 92 follow in table order; `retiredUIDs` new. | 78 → 170 current + 4 retired. D21 recorded for DICOMNetwork. | 30 pass. |
| 2026-09-28 | P4, P5 | DocC page rewritten against the real API; D7 test label fixed. | Docs and one test name. | 30 pass. |
| 2026-09-28 | Close | `Scripts/diff_dictionary.py` (3 parts, 0 differences); `check_nema_markers.py`: 5 of 5. CHANGELOG `[Unreleased]` entry. DICOMCore report: status row, D6/D7/D20 closed. | — | Full `swift test`: all 9 test runs pass (5,165 + 1,504 + 674 + 197 + 84 + 30 + 20 tests), exit 0, no pre-existing failures. |

---

## Priority action list

| # | What | Impact | Status |
|---|---|---|---|
| P1 | Regenerate `DataElementDictionary.txt` from the 2026a DocBook, not from pydicom | **High:** 227 current elements were absent, so DICOMKit wrote them as `UN` and no tool could name them | ✅ Done 2026-09-28 |
| P2 | `UIDDictionary`: full Table A-1; 2 keywords; D20 | Medium: 31 Transfer Syntaxes DICOMCore decodes were "unknown" to `dicom-uid` and the app | ✅ Done 2026-09-28 |
| P3 | `StorageSOPClasses`: full PS3.4 Table B.5-1 | **High for retrieval:** 92 current Storage SOP Classes were absent, so a C-GET/C-MOVE of such a study transferred zero instances | ✅ Done 2026-09-28 (SCU-side cap → D21) |
| P4 | DocC catalogue documented an API that does not exist | Low | ✅ Done 2026-09-28 |
| P5 | D7: test label said CP 1818 for CP 1819 rows | Low | ✅ Done 2026-09-28 |
| P6 | Names / VM cells that differed from PS3.6 (µ, "Per-Frame", "1-n or 1") | Low | ✅ Folded into P1 |

### P1 — `DataElementDictionary.txt` was generated from pydicom 2.4.4, not from PS3.6 2026a — **DONE**

The loader's doc comment and the generator's docstring said "PS3.6 2026a", but
`Scripts/generate_full_dictionary.py` read `pydicom.datadict.DicomDictionary` from whatever pydicom
was installed (2.4.4, 5,127 rows) and dropped rows whose VR is not in the Swift `VR` enum.

**What was wrong** (against the frozen 2026a text): 227 rows missing (226 current, 1 retired), by
group: 0014 ×104 (thermography and NDE source/heating settings (0014,6001)–(0014,6060), wave
dimensions (0014,4101)–(0014,410C)), 0018 ×23 (photoacoustic (0018,9821)–(0018,9829), Date of
Manufacture / Installation), 0040 ×21, 0010 ×15 (Person Names to Use, Pronouns, Gender Identity, Sex
Parameters for Clinical Use (0010,0011)–(0010,0047), Ethnic Group Code Sequence / Ethnic Groups),
3004 ×11, 0008 ×10 (Synthetic Data, Sensitive Content Code Sequence, diagnosis code sequences),
300A ×9, 3006/0022/0012 ×7 each, 0048 ×5, FFFE ×3 (delimiters, see below), and (0006,0001), the only
row of Table 9-1. Retired flag wrong in 5 rows: (0010,2160), (0038,0004), (0070,1807), (0070,1808)
are retired; (3004,0012) is not. Keyword wrong in 2 rows: (003A,0320)
`SummarizedFilterLookupTableSequence`, (003A,0325) `AnalogFilterTypeCodeSequence`. Six rows whose
2026a Keyword cell is blank carried an invented `Unknown` or `Retired-blank`; three of them
((0008,0202), (0018,9445), (0028,0020)) are blank in every column but carried VR `OB`, VM `1`. Names:
`u` for `µ` in (0018,1153), (0018,8150), (0018,8151); "Per-frame" for "Per-Frame" in (5200,9230).
VM: `1-n` for `1-n or 1` in (0028,1200), (0028,3006). Everything else matched: all VRs in the 5,056
shared rows (including OV/SV/UV and the multi-VR rows), all 66 repeating-group rows, and the 46
group 0000 command elements (which PS3.6 does not list; they were checked against PS3.7 Tables
E.1-1 and E.2-1 and match in every column).

**Fix.** The generator now reads `part06.xml` (Tables 6-1, 7-1, 8-1, 9-1) and `part07.xml` (Tables
E.1-1, E.2-1) through `Scripts/nema_docbook.py`, refuses two different editions, refuses a VR the
Swift enum lacks, and writes every cell verbatim. The output format is unchanged, plus `#` comment
lines at the top with the provenance marker (the loader and `Scripts/audit_tags.py` skip them).
The loader gained `allEntries` and rejects an empty keyword in `lookup(keyword:)`.
`Standard2026aTests` pins the row count (5,326), eight of the added rows, every corrected row, the
command elements and the delimiters' absence. `EmptyNameEntryRegressionTests` now asserts the blank
rows load with empty name and keyword (VR `UN`, VM `""` for the fully blank ones).

**Decisions taken** (the recommendations in the draft, approved 2026-09-28):

1. **Delimiters** (FFFE,E000/E00D/E0DD): not emitted. Their VR cell is "See Note"; the parser handles
   them structurally and never looks them up. The resource header lists them.
2. **Blank rows**: stored blank. `lookup(keyword:)` cannot match them.
3. **Other repeating masks** ((0020,31xx), (0028,04x0)…(0028,08x8), (1000,xxx0)…(1000,xxx5),
   (1010,xxxx), (7Fxx,0010)…(7Fxx,0040)): 22 retired families, not emitted; the resource header lists
   them. Revisit if a real file needs them.
4. **µ** kept in names; the `TagConstantAuditTests` alias table maps identifiers to keywords, not
   names, so it is unaffected.

**Dating note.** The 227 rows were not dated one by one to a Supplement or CP. The newest of them
(patient pronouns and gender identity, photoacoustic, thermography) are all absent from pydicom
2.4.4 and present in 2026a; that is the only provenance recorded, and it is enough for the marker,
which names the 2026a tables the rows are copied from.

### P2 — `UIDDictionary.swift`: 47 hand-written rows against a 465-row registry — **DONE**

**What was wrong:** 31 of 63 registered Transfer Syntaxes missing (retired JPEG processes .4.52–.4.66,
JPEG-LS .4.80/.4.81, JPIP .4.94/.4.95/.4.204/.4.205, JPEG XL .4.110–.4.112, RFC 2557 / XML .6.1/.6.2,
SMPTE ST 2110 .7.1–.7.3, Deflated Image Frame Compression .8.1, Encapsulated Uncompressed .1.98,
Papyrus 3 1.2.840.10008.1.20) while DICOMCore's `TransferSyntax.allKnown` already carried all 63;
2 keywords wrong (.4.92 `JPEG2000MCLossless`, .4.93 `JPEG2000MC`); 5 names abbreviated (the Big
Endian row did not say "(Retired)"); ~250 SOP Classes and every Meta SOP Class, Well-known SOP
Instance, Coding Scheme, Service Class and LDAP OID absent although `UIDType` had cases for most.
The 2 Fragmentable HEVC rows (D20) are in no PS3.6 edition.

**Fix.** `Scripts/generate_uid_dictionary.py` writes `UIDDictionaryEntries.swift` with all 465 rows
of Table A-1, name and keyword verbatim, `retired` from the "(Retired)" suffix (75 rows), and the
"UID Type" column mapped as: Transfer Syntax → `.transferSyntax` (63), SOP Class → `.sopClass`
(311), Meta SOP Class → `.metaSOPClass` (9), Well-known SOP Instance → `.wellKnown` (19), LDAP OID →
`.ldap` (39), Coding Scheme and "DICOM UIDs as a Coding Scheme" → `.codingScheme` (16), Application
Context Name → `.applicationContext` (1), and four new cases: Service Class → `.serviceClass` (3),
Application Hosting Model → `.applicationHostingModel` (2), Mapping Resource → `.mappingResource`
(1), Synchronization Frame of Reference → `.synchronizationFrameOfReference` (1). `UIDEntry` gained
`retired` and `registered`. `UIDDictionary.swift` keeps the lookup API and holds the two HEVC UIDs
as `unregisteredEntries` (`registered: false`, name suffixed "(not registered in PS3.6)"), so a file
written with them can still be named. Out-of-module edit required by the new enum cases:
`UIDManager.uidTypeDescription` in DICOMKit (exhaustive switch). No code in `Sources/` looked up
the two changed keywords.

### P3 — `StorageSOPClasses.swift`: 78 of 170 Storage SOP Classes — **DONE**

**What was wrong:** the file called itself the single source of truth for storage negotiation and
explained that an absent class makes C-GET/C-MOVE transfer zero instances, yet 92 of the 170 classes
of PS3.4 2026a Table B.5-1 were absent: 18 of 23 storage SRs (Mammography/Chest/Colon CAD SR, X-Ray
Radiation Dose SR, Radiopharmaceutical and Patient Radiation Dose SR, Procedure Log, Extensible SR,
Acquisition Context SR, Simplified Adult Echo SR, Waveform Annotation SR, …), 20 RT classes (RT Ion
Plan, RT Ion Beams / Brachy / Summary Treatment Records, Enhanced RT Image, RT Physician Intent and
the 2nd-generation RT objects .481.10–.481.25, the Delivery Instructions), 9 presentation states
(Blending, XA/XRF, Advanced Blending, Variable Modality LUT, 5 Volumetric), 15 ophthalmic objects,
8 waveform classes (32-bit ECG, EEG/EMG/EOG, Body Position, 2 Waveform Presentation States),
Parametric Map, Real World Value Mapping, Tractography, Label Map and Height Map Segmentation,
Encapsulated STL/OBJ/MTL, Surface Scan Mesh / Point Cloud, Dermoscopic and Confocal Photography,
Photoacoustic, Intravascular OCT, Eddy Current, Thermography, Ultrasound Waveform, Basic Structured
Display, Hanging Protocol, Color Palette, Implant Templates, Content Assessment Results, Inventory,
Procedure Protocols, DICOS. All 78 present were correct; 9 comments abbreviated the A-1 name.

**Fix.** `Scripts/generate_storage_sop_classes.py` writes the file from PS3.4 Table B.5-1 (`allUIDs`,
170) and B.6-1 (`retiredUIDs`, 4: NM Image, US Image, US Multi-frame, XA Bi-plane), with A-1 names
in the comments. The existing 78 keep their grouped order at the front (the C-GET SCU assigns
presentation-context IDs in list order, so common imaging keeps the low IDs); the other 92 follow in
table order. `isStorage(_:)` recognises current and retired classes; `allUIDs` (what the SCU
proposes and the SCP accepts) holds only current ones.

**Decisions taken:** (a) full B.5-1, approved; (b) retired classes recognised but not proposed,
approved. The SCU-side limit is real: `DICOMRetrieveService` already stops at presentation-context
ID 255 (127 storage contexts) rather than overflowing, so with 170 classes the last 43 in list order
are never proposed. That is D21, for the DICOMNetwork audit.

### P4 — DocC catalogue — **DONE**

`DICOMDictionary.md` showed `DataElementDictionary.shared.lookup(group:element:)`,
`UIDDictionary.shared.name(for:)` and a `DictionaryEntry` symbol, none of which exist. Rewritten
against the real static API; `DataElementEntry`, `UIDEntry`, `UIDType` and `StorageSOPClass` added
to Topics.

### P5 — D7: test label — **DONE**

The 64-bit VR test in `DictionaryTests.swift` now names CP 1818 for the Extended Offset Table rows
and CP 1819 for the (0072,008x) and (0008,04xx) rows.

### Explicitly out of scope — do not chase

- Private vendor dictionaries: none in this module (`PrivateTagDictionary` is in DICOMCore, done).
- The parse/encode behaviour that *uses* the dictionary (VR inference in DICOMKit, Explicit VR
  length rules in DICOMNetwork) belongs to those modules' audits.
- The 2 private JP3D transfer-syntax UIDs in DICOMCore (`1.2.826.0.1.3680043.10.511.1/.2`) are
  under a vendor root by design and cannot be in a PS3.6 registry; the registry test skips
  non-DICOM roots.
- The colour palettes of PS3.6 Annex B and Well-known Frames of Reference (Table A-2): the module
  does not carry them, and nothing asks for them.

---

## Deferred findings

**Carried in from the DICOMCore report:**

| ID | Location | Problem | Standard (2026a) | Status |
|---|---|---|---|---|
| D6 | `Resources/DataElementDictionary.txt` | VR and VM columns never text-diffed | PS3.6 Table 6-1 | ✅ Done 2026-09-28 (P1): every column diffed; 227 missing rows found and the resource regenerated from the DocBook; commit `4f29b7b2` (sha added 2026-10-06, audit A8) |
| D7 | `Tests/DICOMDictionaryTests/DictionaryTests.swift:59` | Test labelled CP 1818 covers CP 1819 rows | Release notes 2019a | ✅ Done 2026-09-28 (P5); commit `4f29b7b2` (sha added 2026-10-06, audit A8) |
| D20 | `UIDDictionary.swift` | Two "Fragmentable HEVC" UIDs not registered in any PS3.6 edition | PS3.6 Table A-1 | ✅ Done 2026-09-28 (P2): kept as `unregisteredEntries` with `registered == false`; commit `f5aa6d0a` (sha added 2026-10-06, audit A8) |

**New findings for other modules** (recorded, not fixed here):

| ID | Module | Location | Problem | Standard (2026a) | Severity | Status |
|---|---|---|---|---|---|---|
| D21 | DICOMNetwork | [RetrieveService.swift:1031-1049](Sources/DICOMNetwork/RetrieveService.swift#L1031) C-GET SCU presentation-context proposal | Proposes one storage context per `StorageSOPClass.allUIDs` entry and stops at ID 255 (127 contexts). With 170 classes the last 43 in list order (2nd-generation RT, DICOS, procedure protocols, …) are never proposed, so a C-GET of such a study still transfers zero instances. Needs a selection strategy: propose the SOP Classes returned by the preceding C-FIND (SOP Class UID in the identifier), or negotiate in batches. | PS3.8 §9.3.2.2 (odd IDs 1–255); PS3.4 C.4.3 | Medium | ✅ Done 2026-09-28, commit be777c1: C-GET proposes the storage classes in batches of 127, second pass only on failures (network report P3) |

---

## Bucket A — Cites 2026a (2 files)

| File | Before | After |
|---|---|---|
| [DataElementDictionary.swift](Sources/DICOMDictionary/DataElementDictionary.swift) + [Resources/DataElementDictionary.txt](Sources/DICOMDictionary/Resources/DataElementDictionary.txt) | ❌ Data from pydicom 2.4.4; 227 of 5,326 rows missing, 5 retired flags and 2 keywords wrong | ✅ Resource generated from PS3.6/PS3.7 2026a; 0 differences. Loader logic (7-column split keeping empty fields, `/` multi-VR, `R` flag, 50xx/60xx canonicalisation per PS3.5 §7.6) confirmed and marked. |
| [UIDDictionary.swift](Sources/DICOMDictionary/UIDDictionary.swift) | ❌ 47 of 465 rows; 31 Transfer Syntaxes missing; 2 unregistered; 2 keywords, 5 names differ | ✅ API over the generated table; 2 unregistered rows labelled. Marked. |

## Bucket B2 — No edition cited, data doesn't match (1 file)

| File | Before | After |
|---|---|---|
| [StorageSOPClasses.swift](Sources/DICOMDictionary/StorageSOPClasses.swift) | ❌ 78 of 170 current classes; 9 comment names abbreviated | ✅ Generated from PS3.4 2026a B.5-1 / B.6-1; 0 differences. Marked by the generator. |

## Bucket C1 — Plumbing (1 file)

| File | Standard data | Result |
|---|---|---|
| [DictionaryEntry.swift](Sources/DICOMDictionary/DictionaryEntry.swift) | `DataElementEntry`, `UIDEntry` value types; `UIDType` | ✅ Types carry no data. `UIDType` compared with the 12 distinct "UID Type" values of A-1; 4 cases added so every value has a home. Marked. |

## Generated (1 file)

| File | Source | Result |
|---|---|---|
| [UIDDictionaryEntries.swift](Sources/DICOMDictionary/UIDDictionaryEntries.swift) | PS3.6 2026a Table A-1 via `Scripts/generate_uid_dictionary.py` | ✅ 465 rows; marker written by the generator. |

## Non-Swift files

| File | Result |
|---|---|
| [Scripts/generate_full_dictionary.py](Scripts/generate_full_dictionary.py) | Rewritten: DocBook in, same format out, provenance header. |
| [Scripts/generate_uid_dictionary.py](Scripts/generate_uid_dictionary.py), [Scripts/generate_storage_sop_classes.py](Scripts/generate_storage_sop_classes.py) | New generators. |
| [Scripts/diff_dictionary.py](Scripts/diff_dictionary.py) | New: re-verifies all three tables against PS3.4/PS3.6/PS3.7; exits 1 on any difference. Run it when the target edition moves. |
| [DICOMDictionary.docc/DICOMDictionary.md](Sources/DICOMDictionary/DICOMDictionary.docc/DICOMDictionary.md) | Rewritten against the real API. |
| [Tests/DICOMDictionaryTests](Tests/DICOMDictionaryTests) | 4 suites, 30 tests: lookups, blank-row regression, `TagConstantAuditTests`, new `Standard2026aTests`. |

---

## Verification notes

- Reproduce the verification: `python3 Scripts/nema_docbook.py fetch 2026a 04`, `… 06`, `… 07`
  (subtitles must read "DICOM PS3.4 2026a - Service Class Specifications", "DICOM PS3.6 2026a - Data
  Dictionary", "DICOM PS3.7 2026a - Message Exchange"), then
  `python3 Scripts/diff_dictionary.py part06_2026a.xml part07_2026a.xml part04_2026a.xml`.
- Regenerate: `generate_full_dictionary.py part06.xml part07.xml`, `generate_uid_dictionary.py part06.xml`,
  `generate_storage_sop_classes.py part04.xml part06.xml`; each takes `--date` for the marker.
- Not checked, by decision: the 22 retired repeating-mask families (not emitted), the 3 delimiters
  (not emitted), and the Supplement/CP dating of the 227 added rows.
- `DICONDE` (303 rows) and `DICOS` (88 rows) elements of Table 6-1 are included and compared like
  every other row; the diff script treats the "DICONDE"/"DICOS" cell as not retired, which is what
  the table means.
