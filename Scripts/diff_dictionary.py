#!/usr/bin/env python3
"""
Re-verify DICOMDictionary against the NEMA DocBook text, row by row.

Usage:
    python3 Scripts/diff_dictionary.py part06_2026a.xml part07_2026a.xml part04_2026a.xml

Compares, and exits 1 on any difference:
  - Resources/DataElementDictionary.txt vs PS3.6 Tables 6-1, 7-1, 8-1, 9-1 and PS3.7 Tables
    E.1-1, E.2-1 (tag, name, keyword, VR, VM, retired), applying the generator's rules
    (50xx/60xx at base group; delimiters and other mask families not emitted).
  - UIDDictionaryEntries.swift vs PS3.6 Table A-1 (uid, name, keyword, type, retired).
  - StorageSOPClasses.swift vs PS3.4 Tables B.5-1 and B.6-1 (membership and names).

This is the "diff row by row" step of the verification method in
DICOMCORE_STANDARD_IMPLEMENTATION.md; run it whenever the target edition moves.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nema_docbook import Part  # noqa: E402
from generate_uid_dictionary import TYPES  # noqa: E402

TAG_RE = re.compile(r"^\(([0-9A-Fa-fxX]{4}),([0-9A-Fa-fxX]{4})\)$")
problems = []


def bad(msg):
    problems.append(msg)


def elements(p6, p7):
    nema = {}
    for label in ("6-1", "7-1", "8-1", "9-1"):
        for r in p6.rows(p6.table(label)):
            if len(r) < 5:
                continue
            g, e = TAG_RE.match(r[0]).groups()
            g, e = g.upper(), e.upper()
            if "X" in g or "X" in e:
                if g[:2] in ("50", "60") and "X" not in e:
                    g = g[:2] + "00"
                else:
                    continue
            if r[3].startswith("See Note"):
                continue
            nema[g + e] = (r[1], r[2], r[3].replace(" or ", "/"), r[4], len(r) > 5 and r[5].startswith("RET"))
    for label, ret in (("E.1-1", False), ("E.2-1", True)):
        for r in p7.rows(p7.table(label)):
            if len(r) < 5:
                continue
            g, e = TAG_RE.match(r[0]).groups()
            nema[g.upper() + e.upper()] = (r[1], r[2], r[3].replace(" or ", "/"), r[4], ret)
    ours = {}
    for line in open("Sources/DICOMDictionary/Resources/DataElementDictionary.txt", encoding="utf-8"):
        if line.startswith("#"):
            continue
        f = line.rstrip("\n").split("|", 6)
        if len(f) < 7:
            bad(f"resource row has {len(f)} fields: {line.strip()}")
            continue
        ours[f[0] + f[1]] = (f[2], f[3], f[4], f[5], f[6] == "R")
    for k in sorted(set(nema) - set(ours)):
        bad(f"element {k} missing from resource: {nema[k]}")
    for k in sorted(set(ours) - set(nema)):
        bad(f"element {k} in resource but not in the standard: {ours[k]}")
    for k in sorted(set(nema) & set(ours)):
        if nema[k] != ours[k]:
            bad(f"element {k}: standard {nema[k]} != resource {ours[k]}")
    print(f"elements: standard {len(nema)}, resource {len(ours)}")


def uids(p6):
    a1 = {}
    for r in p6.rows(p6.table("A-1")):
        if len(r) < 4:
            continue
        a1[r[0].strip()] = (r[1].strip(), r[2].strip(), TYPES.get(r[3].strip(), "?" + r[3]), r[1].strip().endswith("(Retired)"))
    src = open("Sources/DICOMDictionary/UIDDictionaryEntries.swift", encoding="utf-8").read()
    ours = {}
    for m in re.finditer(r'UIDEntry\(uid: "([^"]+)", name: "((?:[^"\\]|\\.)*)", keyword: "([^"]*)", type: \.(\w+)(, retired: true)?\)', src):
        ours[m.group(1)] = (m.group(2).replace('\\"', '"'), m.group(3), m.group(4), bool(m.group(5)))
    for k in sorted(set(a1) - set(ours)):
        bad(f"UID {k} missing from UIDDictionaryEntries: {a1[k]}")
    for k in sorted(set(ours) - set(a1)):
        bad(f"UID {k} in UIDDictionaryEntries but not in A-1: {ours[k]}")
    for k in sorted(set(a1) & set(ours)):
        if a1[k] != ours[k]:
            bad(f"UID {k}: standard {a1[k]} != ours {ours[k]}")
    print(f"UIDs: standard {len(a1)}, ours {len(ours)}")
    return {u: v[0] for u, v in a1.items()}


def storage(p4, names):
    b5 = [r[1].strip() for r in p4.rows(p4.table("B.5-1")) if len(r) > 1]
    b6 = [r[1].strip() for r in p4.rows(p4.table("B.6-1")) if len(r) > 1]
    src = open("Sources/DICOMDictionary/StorageSOPClasses.swift", encoding="utf-8").read()
    def block(name):
        m = re.search(name + r": \[String\] = \[(.*?)\n    \]", src, re.S)
        return re.findall(r'"([0-9.]+)", // (.*)', m.group(1))
    cur, ret = block("allUIDs"), block("retiredUIDs")
    for label, std, ours in (("B.5-1", b5, cur), ("B.6-1", b6, ret)):
        ou = {u for u, _ in ours}
        for u in std:
            if u not in ou:
                bad(f"storage {label}: {u} {names.get(u)} missing")
        for u, n in ours:
            if u not in std:
                bad(f"storage {label}: {u} not in table")
            elif names.get(u) != n:
                bad(f"storage {u}: comment {n!r} != A-1 name {names.get(u)!r}")
        print(f"storage {label}: standard {len(std)}, ours {len(ours)}")


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    p6, p7, p4 = Part(sys.argv[1]), Part(sys.argv[2]), Part(sys.argv[3])
    print(p6.subtitle, "|", p7.subtitle, "|", p4.subtitle)
    elements(p6, p7)
    names = uids(p6)
    storage(p4, names)
    for p in problems:
        print("DIFF:", p)
    print(f"{len(problems)} differences")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
