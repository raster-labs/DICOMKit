#!/usr/bin/env python3
"""
DICOM attribute <-> tag consistency audit.

Cross-checks every hand-written DICOM tag in Sources/ against the bundled
PS3.6 dictionary (Sources/DICOMDictionary/Resources/DataElementDictionary.txt).

A finding is emitted when a human-readable name — a comment, a doc comment,
a Swift identifier, or a `"GGGGEEEE": "Name"` map entry — resolves to a
dictionary entry whose tag differs from the numeric tag written next to it.
That is the failure shape of the (0032,1070)-for-Requested-Procedure-
Description bug: the name is right, the number is wrong, and nothing else
notices.

Checks
  BLOCKER  name/comment/doc/map-entry resolves to a different tag
  MAJOR    `static let x = Tag(...)` whose identifier is not the PS3.6 keyword
           (see ALLOWED_ALIASES); the same tag defined under two names in one
           extension file; explicit VR that contradicts PS3.6
  WARN     tag literal not in the dictionary (private and repeating groups
           excluded)

Usage
  python3 Scripts/audit_tags.py [repo-root] [--strict]
  --strict: exit 1 on any BLOCKER or MAJOR (for CI)
"""
import os
import re
import sys
from collections import defaultdict

args = [a for a in sys.argv[1:] if not a.startswith("--")]
STRICT = "--strict" in sys.argv
ROOT = args[0] if args else "."
DICT = os.path.join(ROOT, "Sources/DICOMDictionary/Resources/DataElementDictionary.txt")
SRC = os.path.join(ROOT, "Sources")

# Constants whose identifier deliberately differs from the PS3.6 keyword.
# Keep this list short: every entry is a place the audit cannot help.
ALLOWED_ALIASES = {
    "exposureInMicroAs":            "ExposureInuAs",
    "verticesOfPolygonalShutter":   "VerticesOfThePolygonalShutter",
    "brachyApplicationSetupSequence": "ApplicationSetupSequence",
    "maxFractionalValue":           "MaximumFractionalValue",
}

# ------------------------------------------------------------ dictionary
by_tag = {}       # (g,e) -> (name, keyword, [vr], vm, retired)
by_norm = {}      # normalised name/keyword -> (g,e)   (non-retired only)
ambiguous = set()

def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())

with open(DICT, encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("|")
        if len(parts) < 6:
            continue
        g, e, name, kw, vr, vm = parts[:6]
        retired = len(parts) > 6 and parts[6] == "R"
        try:
            tag = (int(g, 16), int(e, 16))
        except ValueError:
            continue
        by_tag[tag] = (name, kw, vr.split("/"), vm, retired)
        if retired:
            continue  # retired names ("Reference", "Contrast") only cause noise
        for k in {norm(name), norm(kw)}:
            if not k:
                continue
            if k in by_norm and by_norm[k] != tag:
                ambiguous.add(k)
            by_norm.setdefault(k, tag)
for k in ambiguous:
    by_norm.pop(k, None)

def canonical(tag):
    g, e = tag
    if g % 2 == 0 and 0x5000 <= g <= 0x50FF:
        return (0x5000, e)
    if g % 2 == 0 and 0x6000 <= g <= 0x60FF:
        return (0x6000, e)
    return tag

def entry(tag):
    return by_tag.get(canonical(tag))

def fmt(tag):
    return "(%04X,%04X)" % tag

def is_private_or_special(tag):
    g = tag[0]
    return g % 2 == 1 or g == 0xFFFE or (0x7F00 <= g <= 0x7FFF and g != 0x7FE0)

# ------------------------------------------------------------ patterns
RE_LIT = re.compile(r"group:\s*0x([0-9A-Fa-f]{4})\s*,\s*element:\s*0x([0-9A-Fa-f]{4})")
RE_STR = re.compile(r'"([0-9A-Fa-f]{8})"')
RE_MAP = re.compile(r'"([0-9A-Fa-f]{8})"\s*:\s*"([^"]+)"')
RE_PAREN = re.compile(r"\(([0-9A-Fa-f]{4}),\s*([0-9A-Fa-f]{4})\)")
RE_IDENT = re.compile(r"\b(?:static\s+let|let|var|case|func)\s+([a-zA-Z_][a-zA-Z0-9_]*)")
RE_CONST = re.compile(r"static\s+let\s+([a-zA-Z0-9_]+)\s*=\s*Tag\(")
RE_VR_JSON = re.compile(r'"([0-9A-Fa-f]{8})"\s*\]?\s*=\s*\[\s*"vr"\s*:\s*"([A-Z]{2})"')
RE_VR_ENUM = re.compile(r"vr:\s*\.([A-Z]{2})\b")
RE_VR_DOC = re.compile(r"VR:\s*([A-Z]{2})\b")
RE_COMMENT = re.compile(r"//+\s*(.*)$")

STOP_WORDS = ("todo", "fixme", "mark:", "e.g.", "see ", "http", "note:")

def comment_names(text):
    t = RE_PAREN.sub("", text)
    t = RE_VR_DOC.sub("", t)
    t = re.sub(r"\bVM:\s*[\d\-n]+", "", t)
    t = re.sub(r"\b(Type\s*[123][C]?|Required|Optional|Unique|Conditional|Return key|Matching key|inside .*|— .*|- .*|:.*)$", "", t)
    t = t.strip(" .,;:-—")
    if not t or any(w in t.lower() for w in STOP_WORDS):
        return []
    cands = [t]
    for part in re.split(r",", t):
        p = part.strip(" .")
        if p and p != t:
            cands.append(p)
    return cands

def resolve(name):
    return by_norm.get(norm(name))

# ------------------------------------------------------------ scan
findings = defaultdict(list)
stats = defaultdict(int)

def add(sev, path, lineno, msg):
    findings[sev].append((path, lineno, msg))

for dirpath, _, files in os.walk(SRC):
    for fn in files:
        if not fn.endswith(".swift"):
            continue
        path = os.path.join(dirpath, fn)
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().split("\n")
        is_tag_ext = "/DICOMCore/" in path and fn.startswith("Tag")
        defined_here = {}   # tag -> identifier, for duplicate detection
        for i, line in enumerate(lines):
            ln = i + 1
            tags = [(int(a, 16), int(b, 16)) for a, b in RE_LIT.findall(line)]
            strs = [(int(s[:4], 16), int(s[4:], 16)) for s in RE_STR.findall(line)]
            strs = [t for t in strs if entry(t)]
            code_tags = tags + strs
            if not code_tags:
                continue
            stats["lines_with_tags"] += 1

            # A constant marked unavailable/deprecated is documentation of a past
            # mistake, not a definition to audit.
            attr_block = " ".join(l.strip() for l in lines[max(0, i - 3):i])
            if re.search(r"@available\([^)]*\b(unavailable|deprecated)\b", attr_block):
                continue

            for t in code_tags:
                if not entry(t) and not is_private_or_special(t):
                    add("WARN", rel, ln, "tag %s not in PS3.6 dictionary" % fmt(t))

            # --- "GGGGEEEE": "Name" map entries
            for s, name in RE_MAP.findall(line):
                t = (int(s[:4], 16), int(s[4:], 16))
                r = resolve(name)
                if r and canonical(r) != canonical(t):
                    cur = entry(t)
                    add("BLOCKER", rel, ln, "map entry '%s' resolves to %s but key is %s (%s)" % (
                        name, fmt(r), fmt(t), cur[0] if cur else "<unknown>"))

            names = []
            m = RE_COMMENT.search(line)
            code_part = line[:m.start()] if m else line
            if m:
                names += [(c, "comment") for c in comment_names(m.group(1))]
            for ident in RE_IDENT.findall(code_part):
                names.append((ident, "identifier"))
            j = i - 1
            doc_tags = []
            doc_block = []
            while j >= 0 and i - j <= 6 and lines[j].strip().startswith("///"):
                doc_block.insert(0, lines[j].strip()[3:].strip())
                j -= 1
            if doc_block:
                title = doc_block[0]
                for a, b in RE_PAREN.findall(title):
                    doc_tags.append((int(a, 16), int(b, 16)))
                names += [(c, "doc") for c in comment_names(title)]
            if m:
                for a, b in RE_PAREN.findall(m.group(1)):
                    doc_tags.append((int(a, 16), int(b, 16)))

            for dt in doc_tags:
                if dt not in code_tags and entry(dt) and len(code_tags) == 1:
                    e0 = entry(code_tags[0])
                    add("BLOCKER", rel, ln, "doc comment says %s (%s) but code uses %s (%s)" % (
                        fmt(dt), entry(dt)[1], fmt(code_tags[0]), e0[1] if e0 else "?"))

            seen = set()
            for name, kind in names:
                t = resolve(name)
                if not t or t in seen:
                    continue
                seen.add(t)
                stats["names_resolved"] += 1
                if canonical(t) not in [canonical(c) for c in code_tags]:
                    if len(code_tags) > 1 and any(ct[0] == t[0] for ct in code_tags):
                        continue
                    if kind == "identifier":
                        words = [w.lower() for w in re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", name)]
                        kws = [norm(entry(c)[1]) for c in code_tags if entry(c)]
                        if words and any(all(w in kw for w in words) for kw in kws):
                            continue
                    cur = code_tags[0]
                    e0 = entry(cur)
                    add("BLOCKER", rel, ln, "%s '%s' resolves to %s but code uses %s (%s)" % (
                        kind, name, fmt(t), fmt(cur), e0[0] if e0 else "<unknown>"))

            # --- named constants in DICOMCore Tag*.swift
            if is_tag_ext:
                mm = RE_CONST.search(line)
                if mm and len(code_tags) == 1:
                    ident = mm.group(1)
                    t = code_tags[0]
                    e0 = entry(t)
                    if t in defined_here:
                        add("MAJOR", rel, ln, "tag %s already defined as '%s' in this file; second name '%s'" % (
                            fmt(t), defined_here[t], ident))
                    defined_here[t] = ident
                    if e0:
                        ok = norm(ident) in (norm(e0[1]), norm(e0[0])) or ALLOWED_ALIASES.get(ident) == e0[1]
                        if not ok:
                            add("MAJOR", rel, ln, "constant '%s' is %s but PS3.6 keyword is '%s'" % (
                                ident, fmt(t), e0[1]))
                    elif not is_private_or_special(t):
                        add("WARN", rel, ln, "constant '%s' tag %s not in dictionary" % (ident, fmt(t)))

            # --- VR checks
            for s, vr in RE_VR_JSON.findall(line):
                t = (int(s[:4], 16), int(s[4:], 16))
                e0 = entry(t)
                if e0 and vr not in e0[2] and "UN" not in e0[2]:
                    add("MAJOR", rel, ln, "JSON vr '%s' for %s but PS3.6 VR is '%s' (%s)" % (
                        vr, fmt(t), "/".join(e0[2]), e0[1]))
            if len(code_tags) == 1:
                e0 = entry(code_tags[0])
                if e0 and "UN" not in e0[2]:
                    for vr in RE_VR_ENUM.findall(code_part):
                        if vr not in e0[2]:
                            add("MAJOR", rel, ln, "vr .%s for %s but PS3.6 VR is '%s' (%s)" % (
                                vr, fmt(code_tags[0]), "/".join(e0[2]), e0[1]))
                    for vr in RE_VR_DOC.findall(" ".join(doc_block)):
                        if vr != "VR" and vr not in e0[2]:
                            add("MAJOR", rel, ln, "doc says VR: %s for %s but PS3.6 VR is '%s' (%s)" % (
                                vr, fmt(code_tags[0]), "/".join(e0[2]), e0[1]))

# ------------------------------------------------------------ report
order = ["BLOCKER", "MAJOR", "WARN"]
print("# Tag audit report\n")
print("Lines with tags scanned: %d; names resolved: %d\n" % (stats["lines_with_tags"], stats["names_resolved"]))
for sev in order:
    items = findings.get(sev, [])
    print("## %s (%d)\n" % (sev, len(items)))
    bytarget = defaultdict(list)
    for path, ln, msg in items:
        bytarget[path.split("/")[1] if path.startswith("Sources/") else path].append((path, ln, msg))
    for tgt in sorted(bytarget):
        print("### %s\n" % tgt)
        for path, ln, msg in sorted(bytarget[tgt]):
            print("- `%s:%d` — %s" % (path, ln, msg))
        print()

if STRICT and (findings.get("BLOCKER") or findings.get("MAJOR")):
    sys.exit(1)
