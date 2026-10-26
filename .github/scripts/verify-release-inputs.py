#!/usr/bin/env python3
"""Bind release validation to an immutable tag without permitting product drift."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", args.tag):
        raise ValueError("Expected a stable version tag")
    if git("status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Validation inputs must be committed")
    source = git("rev-parse", args.tag + "^{commit}")
    validation = git("rev-parse", "HEAD")
    changed = subprocess.check_output(
        ["git", "diff", "--no-renames", "--name-only", "-z", source, validation]
    ).decode().split("\0")
    changed = [path for path in changed if path]
    allowed = lambda path: path.startswith(("Tests/", ".github/")) or path == "CONTRIBUTING.md"
    unexpected = [path for path in changed if not allowed(path)]
    if unexpected:
        raise ValueError("Tagged production inputs differ: " + ", ".join(unexpected))
    receipt = {
        "schemaVersion": 1,
        "tag": args.tag,
        "sourceCommit": source,
        "sourceTree": git("rev-parse", source + "^{tree}"),
        "validationCommit": validation,
        "validationTree": git("rev-parse", validation + "^{tree}"),
        "workflowBlob": git("rev-parse", validation + ":.github/workflows/release.yml"),
        "validationOnlyChanges": changed,
        "productionInputsUnchanged": True,
        "testScope": "focused: 81 core and allocation tests; 9 bounded-input tests; 6 CLI output-rule tests",
        "limits": "Focused regression coverage; full-suite results are separate evidence.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
