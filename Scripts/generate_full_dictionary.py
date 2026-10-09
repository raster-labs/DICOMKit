#!/usr/bin/env python3
"""
Generate the DICOM Data Element Dictionary resource from the NEMA DocBook text.

Usage:
    python3 Scripts/generate_full_dictionary.py part06_2026a.xml part07_2026a.xml [--date YYYY-MM-DD]

    (fetch the inputs with `python3 Scripts/nema_docbook.py fetch 2026a 06` and `... 07`)

Writes Sources/DICOMDictionary/Resources/DataElementDictionary.txt, a pipe-delimited
file read at runtime by DataElementDictionary.swift:

    GGGG|EEEE|Name|Keyword|VR[/VR...]|VM|Retired

Sources, all from the same edition (the script refuses two different editions):
  - PS3.6 Table 6-1  Registry of DICOM Data Elements
  - PS3.6 Table 7-1  Registry of DICOM File Meta Elements
  - PS3.6 Table 8-1  Registry of DICOM Directory Structuring Elements
  - PS3.6 Table 9-1  Registry of DICOM Dynamic RTP Payload Elements
  - PS3.7 Table E.1-1 Command Fields, Table E.2-1 Retired Command Fields (group 0000,
    which PS3.6 does not list)

Rules (decided in DICOMDICTIONARY_STANDARD_IMPLEMENTATION.md, P1):
  - Every cell is kept verbatim: names keep "µ", VM keeps "1-n or 1", a blank Name,
    Keyword, VR or VM stays blank (the Swift loader maps a blank VR to UN).
  - Multi-VR attributes ("US or SS") are written "US/SS", primary first.
  - Repeating groups 50xx (Curve) and 60xx (Overlay) are emitted once at their base
    group (5000, 6000); the Swift loader normalises any even group in the range to the
    base before lookup. The other, retired, mask families ((0020,31xx), (0028,04x0)…,
    (1000,xxx0)…, (1010,xxxx), (7Fxx,00x0)) are not emitted; they are listed in the
    header of the output so the omission is visible.
  - The three delimiters (FFFE,E000), (FFFE,E00D), (FFFE,E0DD) have no VR ("See Note")
    and are not emitted; the parser handles them structurally.
  - Retired is "R" when the PS3.6 column starts with "RET" (it carries the year, e.g.
    "RET (2007)"), or for every row of PS3.7 Table E.2-1. Retired elements are emitted
    because they appear in real-world files and must be nameable.
  - Lines starting with "#" are comments; the loader and Scripts/audit_tags.py skip them.

The Swift loader (DataElementDictionary.swift) is hand-maintained and NOT regenerated.
"""
import argparse
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nema_docbook import Part  # noqa: E402

OUT = "Sources/DICOMDictionary/Resources/DataElementDictionary.txt"

# The Swift VR enum (DICOMCore/VR.swift). Anything else is an error, not a silent drop.
SWIFT_VRS = {
    "AE", "AS", "AT", "CS", "DA", "DS", "DT", "FL", "FD", "IS", "LO", "LT",
    "OB", "OD", "OF", "OL", "OV", "OW", "PN", "SH", "SL", "SQ", "SS", "ST",
    "SV", "TM", "UC", "UI", "UL", "UN", "UR", "US", "UT", "UV",
}
REPEATING_BASES = {"50": 0x5000, "60": 0x6000}
TAG_RE = re.compile(r"^\(([0-9A-Fa-fxX]{4}),([0-9A-Fa-fxX]{4})\)$")


def edition_of(part):
    m = re.search(r"\b(\d{4}[a-e])\b", part.subtitle)
    if not m:
        sys.exit(f"cannot find an edition in subtitle {part.subtitle!r}")
    return m.group(1)


def vr_field(vr):
    if not vr:
        return ""
    parts = [p.strip() for p in vr.split(" or ")]
    bad = [p for p in parts if p not in SWIFT_VRS]
    if bad:
        sys.exit(f"VR {bad} is not in the Swift VR enum; add it to DICOMCore first")
    return "/".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("part06")
    ap.add_argument("part07")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    a = ap.parse_args()

    p6, p7 = Part(a.part06), Part(a.part07)
    if "PS3.6" not in p6.subtitle or "PS3.7" not in p7.subtitle:
        sys.exit(f"expected PS3.6 and PS3.7, got {p6.subtitle!r} and {p7.subtitle!r}")
    edition = edition_of(p6)
    if edition_of(p7) != edition:
        sys.exit(f"edition mismatch: {p6.subtitle!r} vs {p7.subtitle!r}")

    rows = {}
    skipped_masks, skipped_delims, counts = [], [], {}

    def add(tag, name, kw, vr, vm, retired, source):
        m = TAG_RE.match(tag)
        if not m:
            sys.exit(f"unexpected tag {tag!r} in {source}")
        g, e = m.group(1).upper(), m.group(2).upper()
        if "X" in g or "X" in e:
            if g[:2] in REPEATING_BASES and "X" not in e:
                g = f"{REPEATING_BASES[g[:2]]:04X}"
            else:
                skipped_masks.append(f"({g},{e})")
                return
        if vr.startswith("See Note"):
            skipped_delims.append(f"({g},{e})")
            return
        key = (int(g, 16), int(e, 16))
        if key in rows:
            sys.exit(f"duplicate tag ({g},{e}) from {source}")
        rows[key] = f"{g}|{e}|{name}|{kw}|{vr_field(vr)}|{vm}|{'R' if retired else ''}"
        counts[source] = counts.get(source, 0) + 1

    for label in ("6-1", "7-1", "8-1", "9-1"):
        for r in p6.rows(p6.table(label)):
            if len(r) < 5:
                continue
            ret = len(r) > 5 and r[5].startswith("RET")
            add(r[0], r[1], r[2], r[3], r[4], ret, f"PS3.6 Table {label}")
    for label, retired in (("E.1-1", False), ("E.2-1", True)):
        for r in p7.rows(p7.table(label)):
            if len(r) < 5:
                continue
            add(r[0], r[1], r[2], r[3], r[4], retired, f"PS3.7 Table {label}")

    header = [
        f"# GENERATED by Scripts/generate_full_dictionary.py from {p6.subtitle} and {p7.subtitle}.",
        "# Do not edit by hand; change the generator and re-run it.",
        "# Columns: GGGG|EEEE|Name|Keyword|VR[/VR...]|VM|Retired(R). Lines starting with # are comments.",
        f"# NEMA-verified: {edition}, checked {a.date} — every row is copied from "
        + ", ".join(f"{s} ({n} rows)" for s, n in counts.items())
        + "; names, keywords, VR, VM and retired flags verbatim; "
        f"50xx/60xx repeating groups stored at their base group.",
        "# Not emitted: the delimiters " + ", ".join(skipped_delims) + " (no VR); "
        "the retired mask families " + ", ".join(sorted(set(skipped_masks))) + ".",
    ]
    lines = header + [rows[k] for k in sorted(rows)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Wrote {OUT}: {len(rows)} entries ({counts}); skipped {len(skipped_delims)} delimiters, "
          f"{len(set(skipped_masks))} mask families")


if __name__ == "__main__":
    main()
