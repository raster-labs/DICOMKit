#!/usr/bin/env python3
"""M2 CLI contract tests with independent Explicit-VR byte inspection; synthetic data only."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

LONG_VRS = {"OB", "OD", "OF", "OL", "OV", "OW", "SQ", "SV", "UC", "UN", "UR", "UT", "UV"}


def elements(data, start=132):
    result = {}
    offset = start
    while offset < len(data):
        group, element = struct.unpack_from("<HH", data, offset)
        vr = data[offset + 4:offset + 6].decode("ascii")
        width = 12 if vr in LONG_VRS else 8
        length = struct.unpack_from("<I" if width == 12 else "<H", data, offset + width - 4 if width == 12 else offset + 6)[0]
        if length == 0xffffffff:
            raise ValueError("This independent flat output inspector requires explicit lengths")
        end = offset + width + length
        assert end <= len(data)
        result[(group, element)] = {"vr": vr, "value": data[offset + width:end], "start": offset, "end": end}
        offset = end
    return result


def scalar(data, tag, encoding="ascii"):
    return elements(data)[tag]["value"].decode(encoding).rstrip("\0 ")


def encode(tag, vr, value):
    value += b"\0" if vr == "UI" and len(value) % 2 else b" " if len(value) % 2 else b""
    header = struct.pack("<HH", *tag) + vr.encode()
    return header + (b"\0\0" + struct.pack("<I", len(value)) if vr in LONG_VRS else struct.pack("<H", len(value))) + value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    fixtures = args.output_dir / "fixtures"
    fixtures.mkdir(exist_ok=True)
    for item in json.loads((root / "Scripts/audit_fixtures/m0/fixtures.json").read_text())["fixtures"]:
        data = bytes.fromhex(item["bytes_hex"])
        assert hashlib.sha256(data).hexdigest() == item["sha256"]
        (fixtures / item["name"]).write_bytes(data)
    results = []

    def run(tool, argv, expected=0):
        p = subprocess.run([str(args.bin_dir / tool), *map(str, argv)], capture_output=True, text=True, timeout=30)
        results.append({"tool": tool, "argv": list(map(str, argv)), "exit": p.returncode,
                        "stdout": p.stdout, "stderr": p.stderr, "expected_exit": expected})
        assert p.returncode == expected, results[-1]
        return p

    def validate(path, valid, level=2, strict=False, fmt="json"):
        argv = [path, "--level", level, "--format", fmt]
        if strict:
            argv.append("--strict")
        p = run("dicom-validate", argv, 0 if valid else 1)
        if fmt == "json":
            assert json.loads(p.stdout)["files"][0]["isValid"] == valid
        else:
            assert ("✓ VALID" if valid else "✗ INVALID") in p.stdout
        return p

    base = fixtures / "base.dcm"
    original = base.read_bytes()
    malformed = ["PatientAge=Y123", "PatientBirthDate=20260231", "PixelSpacing=1..2\\3", "SeriesNumber=++1",
                 "AcquisitionDateTime=20269999112233", "StudyTime=256199", "StudyInstanceUID=1..02", "Rows=1\\2",
                 "RetrieveAETitle=Müller"]
    try:
        for index, value in enumerate(malformed):
            output = args.output_dir / f"rejected-{index}.dcm"
            for tail in [["--dry-run"], ["--output", output], []]:
                p = run("dicom-tags", [base, "--set", value, *tail], 1)
                assert "Error:" in p.stderr + p.stdout
                assert base.read_bytes() == original
                assert not output.exists()
        for name in ["invalid_AS.dcm", "invalid_DT.dcm", "invalid_VM.dcm", "invalid_calendar_date.dcm",
                     "nested-invalid-AS.dcm", "nested-invalid-date.dcm", "odd_numeric_length.dcm", "wrong_VR.dcm"]:
            validate(fixtures / name, False)
        for level in [1, 2]:
            validate(fixtures / "empty-required-meta.dcm", False, level)
            validate(fixtures / "uid-changed.dcm", False, level)
            validate(base, True, level)
        for strict in [False, True]:
            for fmt in ["json", "text"]:
                p = validate(fixtures / "wrong_VR.dcm", False, strict=strict, fmt=fmt)
                assert "VR LO" in p.stdout and "US" in p.stdout
        for value in ["Rows=512", "PatientBirthDate=20240229", "AcquisitionDateTime=2026",
                      "AcquisitionDateTime=20261024103000.123456+0530", "PatientName="]:
            run("dicom-tags", [base, "--set", value, "--dry-run"])
        run("dicom-tags", [base, "--set", "Rows=65536", "--dry-run"], 1)
        for value in ["SOPInstanceUID=2.25.222222222", "SOPClassUID=1.2.840.10008.5.1.4.1.1.2"]:
            output = args.output_dir / ("identity-instance.dcm" if value.startswith("SOPInstance") else "identity-class.dcm")
            run("dicom-tags", [base, "--set", value, "--output", output])
            data = output.read_bytes()
            decoded = elements(data)
            for meta, body in [((2, 2), (8, 0x16)), ((2, 3), (8, 0x18))]:
                assert decoded[meta]["value"] == decoded[body]["value"]
            expected_length = max(item["end"] for tag, item in decoded.items() if tag[0] == 2) - decoded[(2, 0)]["end"]
            assert struct.unpack("<I", decoded[(2, 0)]["value"])[0] == expected_length
            validate(output, True)
        unicode_output = args.output_dir / "unicode.dcm"
        run("dicom-tags", [base, "--set", "PatientName=Müller^患者", "--output", unicode_output])
        assert scalar(unicode_output.read_bytes(), (8, 5)) == "ISO_IR 192"
        assert scalar(unicode_output.read_bytes(), (0x10, 0x10), "utf8") == "Müller^患者"
        latin = fixtures / "latin1-patient.dcm"
        run("dicom-tags", [latin, "--set", "StudyDescription=  Leading text", "--output", args.output_dir / "latin-edited.dcm"])
        edited = (args.output_dir / "latin-edited.dcm").read_bytes()
        edited_encoding = "latin1" if scalar(edited, (8, 5)) == "ISO_IR 100" else "utf8"
        assert scalar(edited, (0x10, 0x10), edited_encoding) == "Müller^Jörg"
        assert scalar(edited, (8, 0x1030), edited_encoding) == "  Leading text"
        for index, selector in enumerate(["0010,0010", "(0010,0010)", "00100010", "PatientName"]):
            output = args.output_dir / f"copy-{index}.dcm"
            run("dicom-tags", [base, "--copy-from", latin, "--tags", selector, "--output", output])
            assert scalar(output.read_bytes(), (0x10, 0x10), "utf8") == "Müller^Jörg"
            validate(output, True)

        # A08: inspect the actual written Value Field when both datasets use Latin-1.
        # Give the destination a different PN so a skipped copy cannot pass this check.
        latin_bytes = latin.read_bytes()
        patient_name = (0x10, 0x10)
        source_name = elements(latin_bytes)[patient_name]
        assert scalar(latin_bytes, (8, 5)) == "ISO_IR 100"
        compatible_input = fixtures / "latin1-copy-destination.dcm"
        compatible_bytes = (latin_bytes[:source_name["start"]]
                            + encode(patient_name, "PN", b"DESTINATION^NAME")
                            + latin_bytes[source_name["end"]:])
        compatible_input.write_bytes(compatible_bytes)
        assert elements(compatible_bytes)[patient_name]["value"] != source_name["value"]
        assert scalar(compatible_bytes, (8, 5)) == "ISO_IR 100"
        compatible_output = args.output_dir / "copy-compatible-latin1.dcm"
        copied = run("dicom-tags", [compatible_input, "--copy-from", latin, "--tags", "0010,0010",
                                   "--verbose", "--output", compatible_output])
        written_bytes = compatible_output.read_bytes()
        written_name = elements(written_bytes)[patient_name]
        assert source_name["vr"] == written_name["vr"] == "PN"
        assert written_name["value"] == source_name["value"]
        assert scalar(written_bytes, (8, 5)) == "ISO_IR 100"
        assert scalar(written_bytes, patient_name, "latin1") == "Müller^Jörg"
        assert copied.stdout.count("COPY (0010,0010)") == 1
        assert "1 change(s) applied." in copied.stdout
        assert latin.read_bytes() == latin_bytes
        assert compatible_input.read_bytes() == compatible_bytes
        validate(compatible_output, True)

        for index, source in enumerate([base, fixtures / "signed.dcm"]):
            output = args.output_dir / f"signed-{index}.dcm"
            run("dicom-tags", [source, "--set", "SmallestImagePixelValue=-1", "--set", "PixelRepresentation=1", "--output", output])
            smallest = elements(output.read_bytes())[(0x28, 0x106)]
            assert smallest["vr"] == "SS" and smallest["value"] == b"\xff\xff"
            validate(output, True)
        run("dicom-tags", [base, "--set", "PixelRepresentation=0", "--set", "SmallestImagePixelValue=-1", "--dry-run"], 1)
    finally:
        (args.output_dir / "cli-verification.json").write_text(json.dumps({"schema_version": 1, "results": results}, indent=2) + "\n")
    print(f"PASS: {len(results)} CLI invocations, independent identity/charset/numeric byte checks; source unchanged")


if __name__ == "__main__":
    main()
