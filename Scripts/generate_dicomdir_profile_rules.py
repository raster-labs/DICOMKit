#!/usr/bin/env python3
"""
Generate DICOMDIRProfileTables.swift from PS3.11 Annex A-N and PS3.4 Table GG.3-1.

Usage:
    python3 Scripts/generate_dicomdir_profile_rules.py part11_2026a.xml part04_2026a.xml [--date YYYY-MM-DD] [--check]

Every "SOP Classes and Transfer Syntaxes" table of PS3.11 (A.3-1, B.3-1, C.3-1, D.3-1,
E.3-1, G.3-1, H.3-1, I.3-1, J.3-1, K.3-1, L.3-1, L.3-2, M.3-1, N.3-1) is copied row for
row, except the Basic Directory row (the DICOMDIR itself): SOP Class UID (nil for
"Composite IODs for which a Media Storage SOP Class is defined in PS3.4"), whether the row
is for Multi-frame Composite IODs only, Transfer Syntax UID (nil for "Defined in
Conformance Statement"), and the FSC / FSR requirement text verbatim. Which profile reads
which table, and how the "-JPEG / -J2K profiles", "Disallowed for CD" and MPEG qualifiers
apply, is code in DICOMDIRProfileRules.swift. `nonPatientStorageUIDs` is PS3.4 Table GG.3-1
(PS3.4 I.4: these are Media Storage SOP Classes too).
The per-profile image attribute tables (A.3-3, B.3-3, B.3-4, E.3-3 to E.3-6, K.3-3, L.4-1: Value
column verbatim; K.3-4, L.4-2: specialized Type) and the Photometric Interpretation / Transfer Syntax
pairs of Table C.3-2 are copied too; DICOMDIRProfileRules parses the Value text and applies each table
to the instances its section names.
The "Additional DICOMDIR Keys" tables (A.3-2, B.3-2, D.3-2, E.3-2, H.3-2, I.3-2: top-level rows; ">" rows
belong to the Sequence key and are copied with it) are copied with their Notes verbatim and each 1C
condition classified (an unknown Notes text stops the script); which Annex applies which table is read
from the xrefs of each X.3.3 section ("H.3-2 specifies the additional associated keys that shall also be
applicable to the profiles defined in this Annex"); the "Icon Images" sections (A.3.3.2, B.3.3.2, E.3.3.3)
give the record types, shall / may, Rows and Columns, Bits Allocated / Stored and Photometric
Interpretation of the icon (PS3.3 F.7 restricted further).
With --check the existing Swift file is compared and the script exits 1 on a difference.
"""
import argparse
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nema_docbook import Part, D, X, norm  # noqa: E402

OUT = "Sources/DICOMKit/DICOMDIRProfileTables.swift"
TABLES = ["A.3-1", "B.3-1", "C.3-1", "D.3-1", "E.3-1", "G.3-1", "H.3-1", "I.3-1",
          "J.3-1", "K.3-1", "L.3-1", "L.3-2", "M.3-1", "N.3-1"]
BASIC_DIRECTORY = "1.2.840.10008.1.3.10"
VALUE_TABLES = ["A.3-3", "B.3-3", "B.3-4", "E.3-3", "E.3-4", "E.3-5", "E.3-6", "K.3-3", "L.4-1"]
TYPE_TABLES = ["K.3-4", "L.4-2"]
KEY_TABLES = ["A.3-2", "B.3-2", "D.3-2", "E.3-2", "H.3-2", "I.3-2"]
# Notes text of a 1C additional key -> condition the builder implements (DICOMDIRProfileKeys.swift)
CONDITIONS = [
    (r"Required if present in image object\.", "present"),
    (r"Required if present in image or spectroscopy object\.", "present"),
    (r"Required if present in image object with a non-zero length value\.", "presentNonZero"),
    (r"Required if present in any objects referenced by subordinate records with a non-zero length value\.",
     "presentInSubordinates"),
    (r"Required if present in image (?:or spectroscopy )?object(?: with one or more items)?, either in the top level "
     r"Data Set or nested within a functional group sequence of the Shared Functional Groups Sequence \(5200,9229\)\.",
     "presentOrSharedFunctionalGroups"),
    (r"Required if the SOP Instance referenced by the Directory Record is an XA Image\.", "xaImage"),
    (r"Required if the SOP Instance referenced by the Directory Record has an Image Type \(0008,0008\) of BIPLANE A "
     r"or BIPLANE B\. May be present otherwise\.", "biplane"),
    (r"Required if the SOP Instance referenced by the Directory Record is an XA Image and has an Image Type "
     r"\(0008,0008\) value 3 of BIPLANE A or BIPLANE B\. May be present otherwise\.", "xaBiplane"),
]
TAG = re.compile(r"^\(([0-9A-Fa-f]{4}),([0-9A-Fa-f]{4})\)$")
UID = re.compile(r"^\d+(\.\d+)+$")


def swift_str(s):
    return "nil" if s is None else '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def rows_for(p11, label):
    out = []
    for r in p11.rows(p11.table(label)):
        if label == "C.3-1":
            iod, sop, _tsname, ts = r[0], r[1], r[2], r[3]
            fsc = fsr = "Mandatory"   # C.3.1: FSC/FSU may choose any of the listed syntaxes
        else:
            iod, sop, ts_cell = r[0], r[1], r[2]
            fsc, fsr = r[3], r[4]
            ts = ts_cell.split("|")[-1].strip() if "|" in ts_cell else None
            if ts_cell.strip() == "Defined in Conformance Statement":
                ts = None
        if sop == BASIC_DIRECTORY:
            continue
        iod = re.sub(r"(PS3\.\d+) \1", r"\1", iod)   # the xref label is resolved twice
        multi_frame = iod.startswith("Multi-frame Composite IODs")
        generic = iod.startswith("Composite IODs") or multi_frame
        sop_uid = None if generic else sop
        if sop_uid is not None and not UID.match(sop_uid):
            raise SystemExit(f"{label}: unexpected SOP Class cell {sop!r}")
        if ts is not None and not UID.match(ts):
            raise SystemExit(f"{label}: unexpected Transfer Syntax cell {ts!r}")
        out.append((iod, sop_uid, multi_frame, ts, fsc, fsr))
    return out


def additional_keys(p11, label):
    """Top-level rows of an Additional DICOMDIR Keys table: (name, group, element, record types, type,
    condition, notes)."""
    out = []
    for r in p11.rows(p11.table(label)):
        name = r[0].replace(" | ", " ").strip()
        if name.startswith(">"):
            continue
        m = TAG.match(r[1].strip())
        if not m:
            raise SystemExit(f"{label}: unexpected Tag cell {r[1]!r}")
        record_types = [t.strip() for t in r[2].split(" or ")]
        typ, notes = r[3].strip(), (r[4].strip() if len(r) > 4 else "")
        condition = ""
        if typ.endswith("C"):
            first = notes.split(" | ")[0]
            matches = [c for pattern, c in CONDITIONS if re.fullmatch(pattern, first)]
            if len(matches) != 1:
                raise SystemExit(f"{label} {name}: unclassified condition {first!r}")
            condition = matches[0]
        out.append((name, int(m.group(1), 16), int(m.group(2), 16), record_types, typ, condition, notes))
    return out


def annex_key_tables(p11):
    """Annex letter -> Additional DICOMDIR Keys table its X.3.3 section refers to."""
    out = {}
    for sec in p11.root.iter(D + "section"):
        m = re.fullmatch(r"sect_([A-N])\.\d\.3", sec.get(X + "id") or "")
        if not m:
            continue
        refs = {x.get("linkend")[len("table_"):] for x in sec.iter(D + "xref")
                if (x.get("linkend") or "")[len("table_"):] in KEY_TABLES}
        if len(refs) > 1:
            raise SystemExit(f"{m.group(1)}: several Additional Keys tables {refs}")
        if refs:
            prev = out.setdefault(m.group(1), refs.pop())
            if prev not in KEY_TABLES:
                raise SystemExit(f"{m.group(1)}: {prev}")
    return out


def icon_rules(p11):
    """Annex letter -> (section, record types, required, rows, columns, bits, photometric list)."""
    out = {}
    for sec in p11.root.iter(D + "section"):
        sid = sec.get(X + "id") or ""
        m = re.fullmatch(r"sect_([A-N])\.\d\.3\.\d", sid)
        title = sec.find(D + "title")
        if not m or title is None or norm("".join(title.itertext())) != "Icon Images":
            continue
        text = p11.text(sec.find(D + "para"))
        rt = re.search(r"Directory Records of type ([A-Z]+(?: or [A-Z]+)*) (shall|may) include Icon Images", text)
        size = re.search(r"Rows? \(0028,0010\) and Columns? \(0028,0011\) (?:attribute values of|shall be equal to) (\d+)", text)
        bits = re.search(r"Bits Allocated(?: \(0028,0100\))?(?: and Bits Stored \(0028,0101\))? "
                         r"(?:equal to|attribute values of|shall be equal to) (\d+)", text)
        pi = re.search(r"Photometric Interpretation \(0028,0004\) (?:attribute value of|shall be) "
                       r"([A-Z0-9]+(?: or [A-Z0-9 ]+?)?)(?:,| and |\.)", text)
        if not (rt and size and bits):
            raise SystemExit(f"{sid}: icon text not understood: {text!r}")
        out[m.group(1)] = (sid[len("sect_"):], [t.strip() for t in rt.group(1).split(" or ")], rt.group(2) == "shall",
                           int(size.group(1)), int(bits.group(1)),
                           [v.strip() for v in pi.group(1).split(" or ")] if pi else [])
    return out


def render(p11, p4, date):
    lines = [
        "// DICOMDIRProfileTables.swift",
        "// DICOMKit",
        "//",
        "// GENERATED by Scripts/generate_dicomdir_profile_rules.py from DICOM PS3.11 2026a - Media Storage Application Profiles",
        "// and DICOM PS3.4 2026a - Service Class Specifications. Do not hand-edit: fix the generator and regenerate.",
        "//",
    ]
    counts = {label: len(rows_for(p11, label)) for label in TABLES}
    total = sum(counts.values())
    gg = [r for r in p4.rows(p4.table("GG.3-1"))]
    lines.append(
        f"// NEMA-verified: 2026a, checked {date} — every non-Basic-Directory row of PS3.11 2026a Tables "
        + ", ".join(f"{k} ({v})" for k, v in counts.items())
        + f" ({total} rows) and the {len(gg)} SOP Classes of PS3.4 2026a Table GG.3-1, generated from the DocBook; "
        + "`generate_dicomdir_profile_rules.py --check` re-verifies it.")
    nvalues = sum(len(list(p11.rows(p11.table(t)))) for t in VALUE_TABLES + TYPE_TABLES)
    c32 = list(p11.rows(p11.table("C.3-2")))
    lines.append(
        f"// Image attribute rows of Tables {', '.join(VALUE_TABLES + TYPE_TABLES)} ({nvalues} rows) and the "
        f"{len(c32)} Photometric Interpretation rows of Table C.3-2 copied verbatim.")
    keyrows = {label: additional_keys(p11, label) for label in KEY_TABLES}
    annexes = annex_key_tables(p11)
    icons = icon_rules(p11)
    lines.append(
        "// Additional DICOMDIR Keys: top-level rows of Tables "
        + ", ".join(f"{k} ({len(v)})" for k, v in keyrows.items())
        + f", applied per Annex {', '.join(f'{a}: {t}' for a, t in sorted(annexes.items()))}; "
        + f"Icon Images sections {', '.join(v[0] for _, v in sorted(icons.items()))} (D239).")
    lines += [
        "",
        "import DICOMCore",
        "",
        "extension DICOMDIRProfileRules {",
        "    /// One row of a PS3.11 \"SOP Classes and Transfer Syntaxes\" table (the Basic Directory",
        "    /// row is left out: it describes the DICOMDIR, not the instances it references).",
        "    struct TableRow: Sendable, Equatable {",
        "        /// Information Object Definition column, verbatim.",
        "        let iod: String",
        "        /// SOP Class UID; nil for \"Composite IODs for which a Media Storage SOP Class is defined in PS3.4\".",
        "        let sopClassUID: String?",
        "        /// The row is for \"Multi-frame Composite IODs\" only.",
        "        let multiFrameOnly: Bool",
        "        /// Transfer Syntax UID; nil for \"Defined in Conformance Statement\".",
        "        let transferSyntaxUID: String?",
        "        /// FSC Requirement column, verbatim.",
        "        let fsc: String",
        "        /// FSR Requirement column, verbatim (carries the \"-JPEG / J2K profiles\" qualifiers).",
        "        let fsr: String",
        "    }",
        "",
        "    /// PS3.11 2026a tables, keyed by table label.",
        "    static let tables: [String: [TableRow]] = [",
    ]
    for label in TABLES:
        lines.append(f"        {swift_str(label)}: [")
        for iod, sop, mf, ts, fsc, fsr in rows_for(p11, label):
            lines.append(
                f"            TableRow(iod: {swift_str(iod)}, sopClassUID: {swift_str(sop)}, "
                f"multiFrameOnly: {'true' if mf else 'false'}, transferSyntaxUID: {swift_str(ts)}, "
                f"fsc: {swift_str(fsc)}, fsr: {swift_str(fsr)}),")
        lines.append("        ],")
    lines += [
        "    ]",
        "",
        "    /// PS3.11 2026a \"Required Image Attribute Values\" tables: Attribute, Tag, Value (verbatim).",
        "    static let imageAttributeValueTables: [String: [(name: String, tag: Tag, value: String)]] = [",
    ]
    def tag_of(cell, label):
        m = TAG.match(cell.strip())
        if not m:
            raise SystemExit(f"{label}: unexpected Tag cell {cell!r}")
        return f"Tag(group: 0x{m.group(1).upper()}, element: 0x{m.group(2).upper()})"
    for label in VALUE_TABLES:
        lines.append(f"        {swift_str(label)}: [")
        for r in p11.rows(p11.table(label)):
            lines.append(f"            ({swift_str(r[0])}, {tag_of(r[1], label)}, {swift_str(r[2])}),")
        lines.append("        ],")
    lines += [
        "    ]",
        "",
        "    /// PS3.11 2026a \"Required Image Attribute Types\" tables: Attribute, Tag, Type.",
        "    static let imageAttributeTypeTables: [String: [(name: String, tag: Tag, type: String)]] = [",
    ]
    for label in TYPE_TABLES:
        lines.append(f"        {swift_str(label)}: [")
        for r in p11.rows(p11.table(label)):
            lines.append(f"            ({swift_str(r[0])}, {tag_of(r[1], label)}, {swift_str(r[2])}),")
        lines.append("        ],")
    lines += [
        "    ]",
        "",
        "    /// PS3.11 2026a Table C.3-2: Photometric Interpretation -> Transfer Syntax UIDs.",
        "    static let ultrasoundPhotometricTransferSyntaxes: [String: [String]] = [",
    ]
    for r in c32:
        uids = [u.strip() for u in r[2].split("|")]
        if not all(UID.match(u) for u in uids):
            raise SystemExit(f"C.3-2: unexpected Transfer Syntax UID cell {r[2]!r}")
        lines.append(f"        {swift_str(r[0])}: [{', '.join(swift_str(u) for u in uids)}],")
    lines += [
        "    ]",
        "",
        "    /// PS3.11 2026a \"Additional DICOMDIR Keys\" tables: top-level rows, Notes verbatim, the 1C",
        "    /// condition classified by the generator.",
        "    static let additionalKeyTables: [String: [AdditionalKey]] = [",
    ]
    for label in KEY_TABLES:
        lines.append(f"        {swift_str(label)}: [")
        for name, g, e, rts, typ, cond, notes in keyrows[label]:
            lines.append(
                f"            AdditionalKey(name: {swift_str(name)}, tag: Tag(group: 0x{g:04X}, element: 0x{e:04X}), "
                f"recordTypes: [{', '.join(swift_str(t) for t in rts)}], type: {swift_str(typ)}, "
                f"condition: {swift_str(cond)}, notes: {swift_str(notes)}),")
        lines.append("        ],")
    lines += [
        "    ]",
        "",
        "    /// The Additional DICOMDIR Keys table each PS3.11 2026a Annex applies (its X.3.3 section).",
        "    static let additionalKeyTableByAnnex: [String: String] = [",
    ]
    for annex, label in sorted(annexes.items()):
        lines.append(f"        {swift_str(annex)}: {swift_str(label)},")
    lines += [
        "    ]",
        "",
        "    /// PS3.11 2026a \"Icon Images\" sections per Annex (empty Photometric list: PS3.3 F.7 alone).",
        "    static let iconImageRules: [String: IconImageRule] = [",
    ]
    for annex, (sec, rts, required, size, bits, pis) in sorted(icons.items()):
        lines.append(
            f"        {swift_str(annex)}: IconImageRule(section: {swift_str(sec)}, recordTypes: [{', '.join(swift_str(t) for t in rts)}], "
            f"required: {'true' if required else 'false'}, rows: {size}, columns: {size}, bits: {bits}, "
            f"photometricInterpretations: [{', '.join(swift_str(v) for v in pis)}]),")
    lines += [
        "    ]",
        "",
        "    /// PS3.4 2026a Table GG.3-1 (Non-Patient Object Storage): Media Storage SOP Classes per PS3.4 I.4.",
        "    static let nonPatientStorageUIDs: Set<String> = [",
    ]
    for r in gg:
        lines.append(f"        {swift_str(r[1])},  // {r[0]}")
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("part11")
    ap.add_argument("part04")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    text = render(Part(a.part11), Part(a.part04), a.date)
    if a.check:
        with open(OUT) as f:
            current = f.read()
        strip = lambda s: re.sub(r"checked \d{4}-\d{2}-\d{2}", "checked DATE", s)
        if strip(current) != strip(text):
            print(f"{OUT}: differs from the DocBook tables")
            sys.exit(1)
        print(f"{OUT}: matches")
        return
    with open(OUT, "w") as f:
        f.write(text)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
