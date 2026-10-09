#!/usr/bin/env python3
"""
Generate DICOMDIRRecordKeyTables.swift from PS3.3 Annex F and PS3.4 Tables B.5-1 / GG.3-1.

Usage:
    python3 Scripts/generate_dicomdir_record_keys.py part03_2026a.xml part04_2026a.xml [--date YYYY-MM-DD] [--check]

Keys: every Directory Record Type of PS3.3 Table F.4-1 with a key table (F.5-1 ... F.5-49) gets its
top-level keys of Type 1, 1C, 2 and 2C (Specific Character Set and the "Any other Attribute" rows
left out; ">" rows belong to a Sequence key and are copied with it). "Include <table>" rows are
expanded with that table's top-level rows, recursively (Table 10-12, 10.9.3-1, C.38.2-1).

Record type per SOP Class: PS3.3 F.5 says, per record type, "This Directory Record shall be used to
reference ..." and names the IE of the IODs whose Keys it carries. A SOP Class of PS3.4 Table B.5-1 or
GG.3-1 references its IOD (column "IOD Specification"); the record type is
  1. the F.5 section whose text links that IOD (or a parent section of it), else
  2. the F.5 section without IOD links whose "Modules related to the <X> IE" names an IE of that IOD's
     module table ("IE" column of the IOD Modules table in PS3.3 Annex A).
SOP Classes that match no record type (the Procedure Protocol and Protocol Approval IODs in 2026a) are
listed separately: no Directory Record Type is defined for them.
With --check the existing Swift file is compared and the script exits 1 on a difference.
"""
import argparse
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nema_docbook import Part, D, X, norm  # noqa: E402

OUT = "Sources/DICOMKit/DICOMDIRRecordKeyTables.swift"
TAG = re.compile(r"^\(([0-9A-Fa-f]{4}),([0-9A-Fa-f]{4})\)$")
SKIP_RECORD_TYPES = {"PATIENT", "STUDY", "SERIES"}


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def sections(p3):
    return {e.get(X + "id"): e for e in p3.root.iter() if (e.get(X + "id") or "").startswith("sect_")}


def f5_sections(p3, secs):
    """record type -> (IE named, IOD section links, F.5 table label)"""
    out = {}
    for sid, e in secs.items():
        m = re.fullmatch(r"sect_F\.5\.(\d+)", sid)
        if not m:
            continue
        paras = e.findall(D + "para")
        if not paras:
            continue
        text = norm(" ".join(paras[0].itertext()))
        rt = re.search(r'Value "([^"]+)"', text)
        if not rt:
            continue
        ie = re.search(r"related to the (.+?) IEs? of", text) or re.search(r"found in the (.+?) IE of", text)
        links = [x.get("linkend") for x in paras[0].iter(D + "xref") if (x.get("linkend") or "").startswith("sect_A")]
        tables = [x.get("linkend") for x in paras[0].iter(D + "xref") if (x.get("linkend") or "").startswith("table_F.5-")]
        out[rt.group(1)] = (ie.group(1) if ie else None, links, tables[0][len("table_"):] if tables else None)
    return out


def iod_ies(p3, secs, sid):
    s = secs.get(sid)
    if s is None:
        return []
    for t in s.iter(D + "table"):
        head = list(p3.rows(t, header=True))[:1]
        if head and head[0] and head[0][0].strip().upper() == "IE":
            return [r[0] for r in p3.rows(t) if len(r) >= 4 and r[0]]
    return []


def record_types(p3, p4):
    secs = sections(p3)
    f5 = f5_sections(p3, secs)
    rows = [(r[0], r[1], r[2].split()[-1]) for label in ("B.5-1", "GG.3-1") for r in p4.rows(p4.table(label))]
    mapping, unmapped = [], []
    for name, uid, sid in rows:
        specific = [rt for rt, (_, links, _) in f5.items()
                    if any(sid == l or sid.startswith(l + ".") for l in links)]
        if specific:
            candidates = specific
        else:
            ies = iod_ies(p3, secs, sid)
            candidates = [rt for rt, (ie, links, _) in f5.items()
                          if ie and not links and ie in ies and rt not in SKIP_RECORD_TYPES]
        if len(candidates) > 1:
            raise SystemExit(f"{uid} {name}: several record types {candidates}")
        if candidates:
            mapping.append((uid, candidates[0], name))
        else:
            unmapped.append((uid, name))
    return f5, mapping, unmapped


def table_keys(p3, label, seen=()):
    """Top-level rows of a key table: (keyword name, group, element, type, description)."""
    out = []
    for r in p3.rows(p3.table(label)):
        first = r[0].strip()
        if first.startswith(">"):
            continue
        inc = re.match(r"^Include (?:Table )?([0-9A-Z][0-9A-Za-z.\-]*)", first)
        if inc:
            ref = inc.group(1)
            if ref not in seen:
                out += table_keys(p3, ref, seen + (label,))
            continue
        if len(r) < 3:
            continue
        m = TAG.match(r[1].strip())
        if not m:
            continue
        name, typ = first, r[2].strip()
        if name == "Specific Character Set":
            continue
        out.append((name, int(m.group(1), 16), int(m.group(2), 16), typ, r[3].strip() if len(r) > 3 else ""))
    return out


def render(p3, p4, date):
    f5, mapping, unmapped = record_types(p3, p4)
    keys = {}
    for rt, (_, _, table) in f5.items():
        if table:
            keys[rt] = [k for k in table_keys(p3, table) if k[3] in ("1", "1C", "2", "2C")]
    nkeys = sum(len(v) for v in keys.values())
    lines = [
        "// DICOMDIRRecordKeyTables.swift",
        "// DICOMKit",
        "//",
        "// GENERATED by Scripts/generate_dicomdir_record_keys.py from DICOM PS3.3 2026a Annex F and DICOM PS3.4",
        "// 2026a Tables B.5-1 and GG.3-1. Do not hand-edit: fix the generator and regenerate.",
        "//",
        f"// NEMA-verified: 2026a, checked {date} — {len(keys)} Directory Record Types of PS3.3 2026a Table F.4-1 with their "
        f"Type 1 / 1C / 2 / 2C keys from Tables F.5-1 to F.5-49 ({nkeys} keys, Include rows expanded); the record type of "
        f"{len(mapping)} SOP Classes of PS3.4 2026a Tables B.5-1 and GG.3-1 from the F.5 \"shall be used to reference\" "
        f"sections and the IOD IEs; {len(unmapped)} SOP Classes have none; "
        "`generate_dicomdir_record_keys.py --check` re-verifies it.",
        "",
        "import DICOMCore",
        "",
        "extension DICOMDIRRecordKeys {",
        "    /// Directory Record Type (0004,1430) Value per Media Storage SOP Class UID.",
        "    static let recordTypeBySOPClass: [String: String] = [",
    ]
    for uid, rt, name in mapping:
        lines.append(f"        {swift_str(uid)}: {swift_str(rt)},  // {name}")
    lines += [
        "    ]",
        "",
        "    /// SOP Classes of PS3.4 Tables B.5-1 / GG.3-1 for which PS3.3 2026a defines no Directory Record Type.",
        "    static let sopClassesWithoutRecordType: [String: String] = [",
    ]
    for uid, name in unmapped:
        lines.append(f"        {swift_str(uid)}: {swift_str(name)},")
    lines += [
        "    ]",
        "",
        "    /// Type 1 / 1C / 2 / 2C keys per Directory Record Type, in table order.",
        "    static let keyTable: [String: (table: String, keys: [Key])] = [",
    ]
    for rt, (_, _, table) in sorted(f5.items(), key=lambda kv: int(kv[1][2].split("-")[1]) if kv[1][2] else 0):
        if rt not in keys:
            continue
        lines.append(f"        {swift_str(rt)}: (table: {swift_str(table)}, keys: [")
        for name, g, e, typ, desc in keys[rt]:
            lines.append(f"            Key(tag: Tag(group: 0x{g:04X}, element: 0x{e:04X}), name: {swift_str(name)}, "
                         f"type: {swift_str(typ)}),")
        lines.append("        ]),")
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("part03")
    ap.add_argument("part04")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    text = render(Part(a.part03), Part(a.part04), a.date)
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
