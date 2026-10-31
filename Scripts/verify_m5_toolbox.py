#!/usr/bin/env python3
"""Execute real Toolbox-generated argv against CLI, using independent synthetic bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
from verify_m2_attributes import encode, elements, scalar


def fixture():
    sop_class = b"1.2.840.10008.5.1.4.1.1.2"
    sop = b"2.25.505.1.1"
    meta = b"".join([
        encode((2, 1), "OB", b"\0\1"), encode((2, 2), "UI", sop_class),
        encode((2, 3), "UI", sop), encode((2, 0x10), "UI", b"1.2.840.10008.1.2.1"),
        encode((2, 0x12), "UI", b"2.25.505.99")])
    body = b"".join(encode(tag, vr, value) for tag, vr, value in [
        ((8, 5), "CS", b"ISO_IR 192"), ((8, 0x16), "UI", sop_class),
        ((8, 0x18), "UI", sop), ((8, 0x20), "DA", b"20260115"),
        ((8, 0x50), "SH", b"TEST-ACCESSION"), ((8, 0x60), "CS", b"CT"),
        ((8, 0x1030), "LO", b"BEFORE"), ((0x10, 0x10), "PN", b"M5^SYNTHETIC"),
        ((0x10, 0x20), "LO", b"M5-001"), ((0x20, 0x0d), "UI", b"2.25.505"),
        ((0x20, 0x0e), "UI", b"2.25.505.1")])
    return bytes(128) + b"DICM" + encode((2, 0), "UL", struct.pack("<I", len(meta))) + meta + body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    manifest = json.loads((root / "toolbox-cli-manifest.json").read_text())
    data = fixture()
    inputs = [root / "input.dcm", root / "input-directory/nested/input.dcm"]
    for path in inputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    records = []
    passed = False

    def run(name, tool, arguments, success=True):
        binary = args.bin_dir / tool
        command = [str(binary), *arguments]
        result = subprocess.run(command, text=True, capture_output=True, timeout=45)
        (root / (name + ".stdout.txt")).write_text(result.stdout)
        (root / (name + ".stderr.txt")).write_text(result.stderr)
        records.append({"name": name, "argv": command, "exit": result.returncode,
                        "expected_success": success, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()})
        assert (result.returncode == 0) == success, (name, result.returncode, result.stdout, result.stderr)
        return result

    try:
        uid_tags = [(8, 0x18), (0x20, 0x0d), (0x20, 0x0e)]
        for case in manifest["cases"]:
            name = case["id"]
            result = run(name, case["tool"], case["arguments"])
            assert all(p.read_bytes() == data for p in inputs), "Input changed"
            if case["tool"] == "dicom-script":
                output = Path(case["stdoutFile"])
                assert result.stdout.strip() and "--output" not in case["arguments"]
                output.write_text(result.stdout)  # Explicit test/app save, not a CLI --output flag.
                run(name + "-validate", "dicom-script", ["validate", str(output)])
                continue
            output = Path(case["values"]["output"])
            if case["dryRun"]:
                assert not output.exists(), "Dry-run wrote a file"
                continue
            files = sorted(output.rglob("*.dcm")) if case["directory"] else [output]
            assert len(files) == 1, (name, files)
            encoded = files[0].read_bytes()
            for tag in uid_tags:
                unchanged = scalar(encoded, tag) == scalar(data, tag)
                assert unchanged == (case["expectedUIDPolicy"] == "retain"), (name, tag)
            assert scalar(encoded, (2, 3)) == scalar(encoded, (8, 0x18))
            assert scalar(encoded, (2, 2)) == scalar(encoded, (8, 0x16))
            assert scalar(encoded, (0x10, 0x10)) != "M5^SYNTHETIC"
            records[-1]["output_sha256"] = hashlib.sha256(encoded).hexdigest()
            if name == "anon-all-current-controls":
                assert (8, 0x50) not in elements(encoded), "Explicit removed tag survived"
                assert scalar(encoded, (8, 0x1030)) == "SYNTHETIC"
                assert scalar(encoded, (8, 0x20)) == "20251216"
                assert Path(str(output) + ".backup").read_bytes() == data
                assert (root / "audit.log").stat().st_size > 0
        negative = [
            ("retired-profile-clinical", "dicom-anon", [str(inputs[0]), "--profile", "clinical-trial"]),
            ("retired-profile-research", "dicom-anon", [str(inputs[0]), "--profile", "research"]),
            ("retired-regenerate", "dicom-anon", [str(inputs[0]), "--regenerate-uids"]),
            ("retired-keep", "dicom-anon", [str(inputs[0]), "--keep", "PatientName"]),
            ("missing-template", "dicom-script", ["template"]),
            ("retired-template-output", "dicom-script", ["template", "workflow", "--output", str(root / "invalid-template.txt")]),
        ]
        for name, tool, arguments in negative:
            result = run(name, tool, arguments, success=False)
            assert "error" in (result.stdout + result.stderr).lower()
        assert not (root / "invalid-template.txt").exists()
        assert all(p.read_bytes() == data for p in inputs)
        passed = True
        print(f"M5 Toolbox: {len(records)} real CLI cases passed; UID, date, file identity and template oracles passed")
    finally:
        (root / "results.json").write_text(json.dumps({"passed": passed, "process_cases": len(records),
            "retained_toolbox_argv_cases": len(manifest["cases"]), "fixture_sha256": hashlib.sha256(data).hexdigest(),
            "records": records, "scope": "Synthetic metadata-only Part 10 data, no pixel/OCR or complete IOD claim; Toolbox library is not linked into DICOMStudio."}, indent=2) + "\n")


if __name__ == "__main__":
    main()
