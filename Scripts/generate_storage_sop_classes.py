#!/usr/bin/env python3
"""
Generate StorageSOPClasses.swift from PS3.4 Annex B and PS3.6 Table A-1.

Usage:
    python3 Scripts/generate_storage_sop_classes.py part04_2026a.xml part06_2026a.xml [--date YYYY-MM-DD]

`allUIDs` is every row of PS3.4 Table B.5-1 (Standard SOP Classes of the Storage Service
Class). The order is the negotiation priority: the C-GET SCU proposes one presentation
context per UID and an association allows 127 storage contexts after the C-GET context
(PS3.8 9.3.2.2), so the classes listed in PRIORITY (common imaging first) come before the
rest of B.5-1 in table order. `retiredUIDs` is PS3.4 Table B.6-1. Names in the comments
are the PS3.6 Table A-1 UID Names.
"""
import argparse
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nema_docbook import Part  # noqa: E402

OUT = "Sources/DICOMDictionary/StorageSOPClasses.swift"

# Negotiation priority: proposed first, in this order (common modalities get the low
# presentation-context IDs). Everything else in B.5-1 follows in table order.
PRIORITY = [
    ("Projection X-Ray", ["1.2.840.10008.5.1.4.1.1.1", "1.2.840.10008.5.1.4.1.1.1.1", "1.2.840.10008.5.1.4.1.1.1.1.1",
                          "1.2.840.10008.5.1.4.1.1.1.2", "1.2.840.10008.5.1.4.1.1.1.2.1", "1.2.840.10008.5.1.4.1.1.1.3",
                          "1.2.840.10008.5.1.4.1.1.1.3.1"]),
    ("X-Ray Angiography & Radiofluoroscopy", ["1.2.840.10008.5.1.4.1.1.12.1", "1.2.840.10008.5.1.4.1.1.12.1.1",
                                              "1.2.840.10008.5.1.4.1.1.12.2", "1.2.840.10008.5.1.4.1.1.12.2.1",
                                              "1.2.840.10008.5.1.4.1.1.13.1.1", "1.2.840.10008.5.1.4.1.1.13.1.2",
                                              "1.2.840.10008.5.1.4.1.1.13.1.3", "1.2.840.10008.5.1.4.1.1.13.1.4",
                                              "1.2.840.10008.5.1.4.1.1.13.1.5"]),
    ("CT", ["1.2.840.10008.5.1.4.1.1.2", "1.2.840.10008.5.1.4.1.1.2.1", "1.2.840.10008.5.1.4.1.1.2.2"]),
    ("MR", ["1.2.840.10008.5.1.4.1.1.4", "1.2.840.10008.5.1.4.1.1.4.1", "1.2.840.10008.5.1.4.1.1.4.2",
            "1.2.840.10008.5.1.4.1.1.4.3", "1.2.840.10008.5.1.4.1.1.4.4"]),
    ("Ultrasound", ["1.2.840.10008.5.1.4.1.1.6.1", "1.2.840.10008.5.1.4.1.1.6.2", "1.2.840.10008.5.1.4.1.1.3.1"]),
    ("Nuclear Medicine / PET", ["1.2.840.10008.5.1.4.1.1.20", "1.2.840.10008.5.1.4.1.1.128",
                                "1.2.840.10008.5.1.4.1.1.128.1", "1.2.840.10008.5.1.4.1.1.130"]),
    ("Secondary Capture", ["1.2.840.10008.5.1.4.1.1.7", "1.2.840.10008.5.1.4.1.1.7.1", "1.2.840.10008.5.1.4.1.1.7.2",
                           "1.2.840.10008.5.1.4.1.1.7.3", "1.2.840.10008.5.1.4.1.1.7.4"]),
    ("Visible Light / Microscopy / Ophthalmic", ["1.2.840.10008.5.1.4.1.1.77.1.1", "1.2.840.10008.5.1.4.1.1.77.1.1.1",
                                                  "1.2.840.10008.5.1.4.1.1.77.1.2", "1.2.840.10008.5.1.4.1.1.77.1.2.1",
                                                  "1.2.840.10008.5.1.4.1.1.77.1.3", "1.2.840.10008.5.1.4.1.1.77.1.4",
                                                  "1.2.840.10008.5.1.4.1.1.77.1.4.1", "1.2.840.10008.5.1.4.1.1.77.1.5.1",
                                                  "1.2.840.10008.5.1.4.1.1.77.1.5.2", "1.2.840.10008.5.1.4.1.1.77.1.5.4",
                                                  "1.2.840.10008.5.1.4.1.1.77.1.6"]),
    ("Radiotherapy", ["1.2.840.10008.5.1.4.1.1.481.1", "1.2.840.10008.5.1.4.1.1.481.2", "1.2.840.10008.5.1.4.1.1.481.3",
                      "1.2.840.10008.5.1.4.1.1.481.4", "1.2.840.10008.5.1.4.1.1.481.5"]),
    ("Presentation States", ["1.2.840.10008.5.1.4.1.1.11.1", "1.2.840.10008.5.1.4.1.1.11.2", "1.2.840.10008.5.1.4.1.1.11.3"]),
    ("Structured Reporting & Documents", ["1.2.840.10008.5.1.4.1.1.88.11", "1.2.840.10008.5.1.4.1.1.88.22",
                                          "1.2.840.10008.5.1.4.1.1.88.33", "1.2.840.10008.5.1.4.1.1.88.34",
                                          "1.2.840.10008.5.1.4.1.1.88.59", "1.2.840.10008.5.1.4.1.1.104.1",
                                          "1.2.840.10008.5.1.4.1.1.104.2"]),
    ("Raw / Spatial / Segmentation", ["1.2.840.10008.5.1.4.1.1.66", "1.2.840.10008.5.1.4.1.1.66.1",
                                      "1.2.840.10008.5.1.4.1.1.66.2", "1.2.840.10008.5.1.4.1.1.66.3",
                                      "1.2.840.10008.5.1.4.1.1.66.4", "1.2.840.10008.5.1.4.1.1.66.5"]),
    ("Waveform", ["1.2.840.10008.5.1.4.1.1.9.1.1", "1.2.840.10008.5.1.4.1.1.9.1.2", "1.2.840.10008.5.1.4.1.1.9.1.3",
                  "1.2.840.10008.5.1.4.1.1.9.2.1", "1.2.840.10008.5.1.4.1.1.9.3.1", "1.2.840.10008.5.1.4.1.1.9.4.1",
                  "1.2.840.10008.5.1.4.1.1.9.4.2", "1.2.840.10008.5.1.4.1.1.9.5.1", "1.2.840.10008.5.1.4.1.1.9.6.1",
                  "1.2.840.10008.5.1.4.1.1.9.6.2"]),
]

DOC = '''/// Canonical registry of DICOM Storage SOP Class UIDs.
///
/// This is the **single source of truth** for "which SOP Classes are storage
/// objects" across the DICOMKit package. Every component that negotiates
/// storage presentation contexts MUST derive its list from here rather than
/// maintaining its own copy, so the SCU, the SCP and the validator can never
/// drift apart:
///
/// - `DICOMRetrieveService` (C-GET SCU) proposes one storage presentation
///   context per UID so the SCP has somewhere to send each instance.
/// - `StorageSCP` (C-STORE / C-MOVE destination) accepts these abstract
///   syntaxes during association negotiation.
/// - `DICOMValidator` recognises these as known storage objects.
///
/// ## Why this matters
///
/// C-GET and C-MOVE deliver images as C-STORE sub-operations whose abstract
/// syntax must be negotiated up front. If a study's SOP Class is missing from
/// the proposed/accepted set, the peer has no presentation context to send it
/// on and silently transfers **zero** instances (e.g. an X-Ray Angiographic
/// study returning "0 files" while reporting success). Keeping this list
/// complete and shared prevents that class of bug.
///
/// ## Order
///
/// An association allows 127 storage presentation contexts after the C-GET
/// context (odd IDs 1...255, PS3.8 9.3.2.2), fewer than the classes in
/// `allUIDs`, so the C-GET SCU proposes the list in order until it runs out of
/// IDs. Common imaging classes come first; the rest follow in PS3.4 Table
/// B.5-1 order. Membership, not order, is what matters for the SCP and the
/// validator.
///
/// Reference: DICOM PS3.4 Annex B (Storage Service Class), Table B.5-1 and
/// B.6-1; PS3.6 Table A-1 for the names.'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("part04")
    ap.add_argument("part06")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    a = ap.parse_args()
    p4, p6 = Part(a.part04), Part(a.part06)
    if "PS3.4" not in p4.subtitle or "PS3.6" not in p6.subtitle:
        sys.exit(f"expected PS3.4 and PS3.6, got {p4.subtitle!r}, {p6.subtitle!r}")
    edition = re.search(r"\b(\d{4}[a-e])\b", p4.subtitle).group(1)
    if re.search(r"\b(\d{4}[a-e])\b", p6.subtitle).group(1) != edition:
        sys.exit("edition mismatch between PS3.4 and PS3.6")

    names = {r[0].strip(): r[1].strip() for r in p6.rows(p6.table("A-1")) if len(r) > 1}
    current = [r[1].strip() for r in p4.rows(p4.table("B.5-1")) if len(r) > 1]
    retired = [r[1].strip() for r in p4.rows(p4.table("B.6-1")) if len(r) > 1]
    for u in current + retired:
        if u not in names:
            sys.exit(f"{u} is in PS3.4 Annex B but not in PS3.6 Table A-1")
    cur_set = set(current)
    prio = [u for _, us in PRIORITY for u in us]
    for u in prio:
        if u not in cur_set:
            sys.exit(f"PRIORITY UID {u} is not in Table B.5-1")
    if len(set(prio)) != len(prio):
        sys.exit("duplicate UID in PRIORITY")
    rest = [u for u in current if u not in set(prio)]

    def row(u, last=False):
        return f'        "{u}",{"" if not last else ""} // {names[u]}'

    out = [
        "/// DICOM Storage SOP Classes",
        "///",
        f"/// GENERATED by Scripts/generate_storage_sop_classes.py from {p4.subtitle} and {p6.subtitle}.",
        "/// Do not edit by hand; change the generator (its PRIORITY list sets the order) and re-run it.",
        "///",
        f"/// NEMA-verified: {edition}, checked {a.date} — `allUIDs` is exactly the {len(current)} rows of",
        f"/// PS3.4 {edition} Table B.5-1 (Standard SOP Classes of the Storage Service Class) and",
        f"/// `retiredUIDs` the {len(retired)} rows of Table B.6-1; every UID and name checked against",
        f"/// PS3.6 {edition} Table A-1.",
        "",
        "import Foundation",
        "",
        DOC,
        "public enum StorageSOPClass {",
        "    /// All current Storage SOP Class UIDs (PS3.4 Table B.5-1), in negotiation order.",
        "    public static let allUIDs: [String] = [",
    ]
    for title, us in PRIORITY:
        out.append(f"        // MARK: {title}")
        out += [row(u) for u in us]
    out.append("        // MARK: Remaining PS3.4 Table B.5-1 classes, in table order")
    out += [row(u) for u in rest]
    out += [
        "    ]",
        "",
        "    /// Retired Storage SOP Class UIDs (PS3.4 Table B.6-1). Not proposed by the",
        "    /// SCU, but still recognised by `isStorage(_:)` because archives hold them.",
        "    public static let retiredUIDs: [String] = [",
    ]
    out += [row(u) for u in retired]
    out += [
        "    ]",
        "",
        "    /// All current Storage SOP Class UIDs as a set, for fast membership checks.",
        "    public static let allUIDSet: Set<String> = Set(allUIDs)",
        "",
        "    /// Retired Storage SOP Class UIDs as a set.",
        "    public static let retiredUIDSet: Set<String> = Set(retiredUIDs)",
        "",
        "    /// Returns `true` if the given UID is a current or retired Storage SOP Class.",
        "    public static func isStorage(_ uid: String) -> Bool {",
        "        allUIDSet.contains(uid) || retiredUIDSet.contains(uid)",
        "    }",
        "}",
        "",
    ]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"Wrote {OUT}: {len(current)} current ({len(prio)} prioritised), {len(retired)} retired")


if __name__ == "__main__":
    main()
