#!/usr/bin/env python3
"""Read-only independent inspection of the bounded M2 GUI artifact snapshot.

Uses Python's struct and standard codecs, not DICOMKit, to inspect flat Explicit
VR Little Endian output. Invokes the built validator read-only for report parity.
The explicit --create-cli-signed-update switch creates one fresh CLI comparison
output and refuses to overwrite an existing file; all GUI files remain read-only.
This is artifact verification, not evidence of the GUI interaction sequence.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LONG_VRS = {"OB", "OD", "OF", "OL", "OV", "OW", "SQ", "SV", "UC", "UN", "UR", "UT", "UV"}
REPORT_NAMES = [
    "report-gui-identity-class.dcm.json", "report-gui-identity-instance.dcm.json",
    "report-gui-signed.dcm.json", "report-gui-unicode.dcm.json",
    "report-invalid_AS.dcm.json", "report-invalid_DT.dcm.json",
    "report-invalid_calendar_date.dcm.json", "report-nested-invalid-AS.dcm.json",
    "report-nested-invalid-date.dcm.json", "report-valid-fraction-DT.dcm.json",
    "report-valid-leap.dcm.json", "report-valid-partial-DT.dcm.json",
    "report-wrong_VR.dcm.json",
]
REPORT_CASES = [(name, 2) for name in REPORT_NAMES] + [
    (f"meta-{level}-{name}.dcm.json", level)
    for level in (1, 2)
    for name in ("empty-required-meta", "uid-changed", "base")
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_elements(path):
    data = path.read_bytes()
    if data[128:132] != b"DICM":
        raise ValueError(f"{path.name}: missing Part 10 marker")
    offset, result = 132, {}
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError(f"{path.name}: truncated header at {offset}")
        tag = struct.unpack_from("<HH", data, offset)
        vr = data[offset + 4:offset + 6].decode("ascii")
        width = 12 if vr in LONG_VRS else 8
        if offset + width > len(data):
            raise ValueError(f"{path.name}: truncated long header at {offset}")
        length = struct.unpack_from("<I" if width == 12 else "<H", data, offset + width - (4 if width == 12 else 2))[0]
        end = offset + width + length
        if length == 0xffffffff or end > len(data) or tag in result:
            raise ValueError(f"{path.name}: unsupported undefined length, overflow or duplicate tag {tag}")
        result[tag] = {"vr": vr, "value": data[offset + width:end], "start": offset, "end": end}
        offset = end
    if text(result, (2, 0x10)) != "1.2.840.10008.1.2.1":
        raise ValueError(f"{path.name}: inspector requires Explicit VR Little Endian")
    return result


def text(elements, tag, encoding="ascii"):
    # Remove only DICOM trailing padding; never leading whitespace.
    return elements[tag]["value"].decode(encoding, errors="strict").rstrip("\0 ")


def describe(element):
    return {"vr": element["vr"], "bytes_hex": element["value"].hex(), "length": len(element["value"])}


def normalized(value):
    # All other keys and array ordering remain part of the comparison.
    ignored = {"filePath", "duration", "durationSeconds", "elapsedTime", "elapsedSeconds", "processingTime"}
    if isinstance(value, dict):
        return {k: normalized(v) for k, v in value.items() if k not in ignored}
    if isinstance(value, list):
        return [normalized(v) for v in value]
    return value


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gui-dir", type=Path, default=Path("/private/tmp/dicomkit-m2-ui"))
    ap.add_argument("--manifest", type=Path, default=ROOT / "work/m2/ui-input-manifest.json")
    ap.add_argument("--original-fixtures", type=Path, default=ROOT / "work/DICOMKit-milestones/Scripts/audit_fixtures/m0/fixtures.json")
    ap.add_argument("--ui-evidence-dir", type=Path, default=ROOT / "work/m2/ui")
    ap.add_argument("--validator", type=Path, default=Path("/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-validate"))
    ap.add_argument("--tag-editor", type=Path, default=Path("/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-tags"))
    ap.add_argument("--cli-signed-update-output", type=Path, default=Path("/private/tmp/dicomkit-m2-ui/cli-signed-update.dcm"))
    ap.add_argument("--create-cli-signed-update", action="store_true")
    ap.add_argument("--output", type=Path, default=ROOT / "work/m2/gui-file-parity.json")
    args = ap.parse_args()
    checks = []

    def check(name, passed, **details):
        checks.append({"check": name, "passed": bool(passed), **details})

    manifest = json.loads(args.manifest.read_text())
    original = json.loads(args.original_fixtures.read_text())["fixtures"]
    originals = {x["name"]: x["sha256"] for x in original}
    hash_checks = []
    for item in manifest:
        path = args.gui_dir / item["name"]
        actual = sha(path) if path.exists() else None
        passed = actual == item["sha256"] and (item["name"] not in originals or actual == originals[item["name"]])
        hash_checks.append({"name": item["name"], "original_m0_fixture": item["name"] in originals,
                            "expected_sha256": item["sha256"], "actual_sha256": actual, "passed": passed})
    check("all_initial_inputs_unchanged", all(x["passed"] for x in hash_checks), count=len(hash_checks))
    original_checks = [x for x in hash_checks if x["original_m0_fixture"]]
    check("all_14_original_fixtures_unchanged", len(original_checks) == 14 and len(originals) == 14 and all(x["passed"] for x in original_checks), count=len(original_checks))
    check("rejected_edit_has_no_output", not (args.gui_dir / "gui-invalid.dcm").exists(), file="gui-invalid.dcm")

    output_names = ["gui-identity-class.dcm", "gui-identity-instance.dcm", "gui-signed.dcm", "gui-signed-update.dcm",
                    "gui-unicode.dcm", "gui-latin-edited.dcm", "gui-japanese.dcm",
                    "gui-copy-numeric.dcm", "gui-copy-parenthesized.dcm", "gui-copy-hex.dcm",
                    "gui-copy-keyword.dcm", "gui-copy-compatible.dcm"]
    parsed = {name: inspect_elements(args.gui_dir / name) for name in output_names}
    output_hashes = {name: sha(args.gui_dir / name) for name in output_names}
    identity = []
    for name in output_names:
        e = parsed[name]
        stored = struct.unpack("<I", e[(2, 0)]["value"])[0]
        actual = max(v["end"] for t, v in e.items() if t[0] == 2) - e[(2, 0)]["end"]
        record = {"file": name, "meta_class": text(e, (2, 2)), "dataset_class": text(e, (8, 0x16)),
                  "meta_instance": text(e, (2, 3)), "dataset_instance": text(e, (8, 0x18)),
                  "stored_group_length": stored, "actual_encoded_group_length": actual}
        record["passed"] = (record["meta_class"] == record["dataset_class"] and record["meta_instance"] == record["dataset_instance"] and stored == actual)
        identity.append(record)
    check("all_inspected_outputs_identity_and_group_length", all(x["passed"] for x in identity), count=len(identity))
    check("changed_sop_class", text(parsed["gui-identity-class.dcm"], (8, 0x16)) == "1.2.840.10008.5.1.4.1.1.2", expected="1.2.840.10008.5.1.4.1.1.2")
    check("changed_sop_instance", text(parsed["gui-identity-instance.dcm"], (8, 0x18)) == "2.25.222222222", expected="2.25.222222222")

    signed = parsed["gui-signed.dcm"]
    raw = signed[(0x28, 0x106)]
    check("signed_minus_one", raw["vr"] == "SS" and raw["value"] == b"\xff\xff" and signed[(0x28, 0x103)]["value"] == b"\x01\x00",
          element=describe(raw), decoded_signed_value=struct.unpack("<h", raw["value"])[0], pixel_representation=describe(signed[(0x28, 0x103)]))
    signed_update = parsed["gui-signed-update.dcm"]
    update_element = signed_update[(0x28, 0x106)]
    check("existing_signed_value_updated_to_minus_two", update_element["vr"] == "SS" and update_element["value"] == b"\xfe\xff" and signed_update[(0x28, 0x103)]["value"] == b"\x01\x00",
          element=describe(update_element), decoded_signed_value=struct.unpack("<h", update_element["value"])[0])
    signed_cli_command = [str(args.tag_editor), str(args.gui_dir / "gui-signed.dcm"), "--set", "SmallestImagePixelValue=-2", "--output", str(args.cli_signed_update_output)]
    signed_cli_execution = {"command": signed_cli_command, "executed_this_run": False}
    if args.create_cli_signed_update:
        if args.cli_signed_update_output.exists():
            raise FileExistsError(f"Refusing to overwrite {args.cli_signed_update_output}; omit --create-cli-signed-update to inspect it or choose a fresh --cli-signed-update-output path")
        proc = subprocess.run(signed_cli_command, capture_output=True, text=True, timeout=30)
        signed_cli_execution.update({"executed_this_run": True, "exit": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr})
        if proc.returncode != 0:
            raise RuntimeError(f"Signed update CLI failed: {proc.stderr}")
    signed_cli_execution.update({"executable_sha256": sha(args.tag_editor), "input_sha256": sha(args.gui_dir / "gui-signed.dcm"),
                                 "output_sha256": sha(args.cli_signed_update_output), "gui_output_sha256": sha(args.gui_dir / "gui-signed-update.dcm")})
    check("existing_signed_update_cli_gui_byte_for_byte_equal", args.cli_signed_update_output.read_bytes() == (args.gui_dir / "gui-signed-update.dcm").read_bytes(), **signed_cli_execution)
    unicode = parsed["gui-unicode.dcm"]
    check("unicode_utf8_declaration_and_bytes", text(unicode, (8, 5)) == "ISO_IR 192" and text(unicode, (0x10, 0x10), "utf-8") == "Müller^患者",
          declaration=text(unicode, (8, 5)), decoded_patient_name=text(unicode, (0x10, 0x10), "utf-8"), element=describe(unicode[(0x10, 0x10)]))
    latin = parsed["gui-latin-edited.dcm"]
    check("latin1_name_and_leading_whitespace", text(latin, (8, 5)) == "ISO_IR 100" and text(latin, (0x10, 0x10), "latin-1") == "Müller^Jörg" and text(latin, (8, 0x1030), "latin-1") == "  Leading text",
          declaration=text(latin, (8, 5)), decoded_patient_name=text(latin, (0x10, 0x10), "latin-1"), decoded_description=text(latin, (8, 0x1030), "latin-1"), description=describe(latin[(8, 0x1030)]))
    japanese = parsed["gui-japanese.dcm"]
    japanese_source = inspect_elements(args.gui_dir / "japanese.dcm")
    jp_text = text(japanese, (0x10, 0x10), "iso2022_jp")
    check("japanese_independent_codec_and_unchanged_bytes", text(japanese, (8, 5)) == "\\ISO 2022 IR 87" and jp_text == "Yamada^Tarou=山田^太郎" and describe(japanese[(0x10, 0x10)]) == describe(japanese_source[(0x10, 0x10)]),
          independent_decoder="Python standard library iso2022_jp (strict)", declaration=text(japanese, (8, 5)), decoded_patient_name=jp_text, element=describe(japanese[(0x10, 0x10)]))

    copied = []
    for kind in ["numeric", "parenthesized", "hex", "keyword"]:
        name = f"gui-copy-{kind}.dcm"
        e = parsed[name]
        copied.append({"file": name, "selector_form": kind, "declaration": text(e, (8, 5)),
                       "decoded_patient_name": text(e, (0x10, 0x10), "utf-8"), "element": describe(e[(0x10, 0x10)])})
    check("four_selectors_equal_name_and_bytes", all(x["declaration"] == "ISO_IR 192" and x["decoded_patient_name"] == "Müller^Jörg" and x["element"] == copied[0]["element"] for x in copied), count=len(copied), outputs=copied)
    compatible = parsed["gui-copy-compatible.dcm"]
    latin_source = inspect_elements(args.gui_dir / "latin1-patient.dcm")
    check("compatible_copy_preserves_vr_raw_bytes", describe(compatible[(0x10, 0x10)]) == describe(latin_source[(0x10, 0x10)]) and text(compatible, (8, 5)) == "ISO_IR 100",
          destination=describe(compatible[(0x10, 0x10)]), source=describe(latin_source[(0x10, 0x10)]), declaration=text(compatible, (8, 5)))

    reports = []
    for name, level in REPORT_CASES:
        path = args.gui_dir / name
        gui = json.loads(path.read_text())
        if len(gui["files"]) != 1:
            raise ValueError(f"{name}: expected single-file report")
        input_path = Path(gui["files"][0]["filePath"])
        if input_path.parent != args.gui_dir:
            raise ValueError(f"{name}: unexpected input path {input_path}")
        command = [str(args.validator), str(input_path), "--level", str(level), "--format", "json"]
        proc = subprocess.run(command, capture_output=True, text=True, timeout=30)
        cli = json.loads(proc.stdout)
        expected_exit = 0 if gui["files"][0]["isValid"] else 1
        same = normalized(gui) == normalized(cli)
        record = {"report": name, "level": level, "gui_report_sha256": sha(path), "input_sha256": sha(input_path),
                  "cli_command": command, "cli_exit": proc.returncode, "expected_exit": expected_exit,
                  "gui_is_valid": gui["files"][0]["isValid"], "cli_is_valid": cli["files"][0]["isValid"],
                  "all_emitted_fields_match_except_path_duration": same,
                  "normalized_gui": normalized(gui), "normalized_cli": normalized(cli),
                  "cli_stderr": proc.stderr, "passed": same and proc.returncode == expected_exit}
        reports.append(record)
    check("all_report_fields_and_statuses_match_cli_at_same_level", all(x["passed"] for x in reports), count=len(reports), levels=[1, 2])
    console_checks = []
    expected_message = "Unexpected VR LO for tag (0028,0010) (expected: US)"
    for strict in (False, True):
        for format_name in ("json", "text"):
            path = args.ui_evidence_dir / f"wrong-vr-console-{str(strict).lower()}-{format_name}.txt"
            capture = path.read_text()
            command = f"$ dicom-validate {args.gui_dir}/wrong_VR.dcm --level 2" + (" --strict" if strict else "") + f" --format {format_name}"
            # Isolate this command's text node, excluding preceding console runs.
            command_start = capture.rfind(command)
            if command_start < 0:
                body = ""
            else:
                body = re.split(r"\n\t+\d+ (?:text|button|scroll area) ", capture[command_start:], maxsplit=1)[0]
            save_lines = [line.strip() for line in capture.splitlines() if "text field (settable) Description: Save Report To," in line]
            save_empty = bool(save_lines) and all("Value:" not in line for line in save_lines)
            strict_matches = f"checkbox Description: Strict Mode, Value: {int(strict)}" in capture
            format_matches = f"radio button Description: {format_name}, Value: 1" in capture
            status_visible = ('"isValid" : false' in body if format_name == "json" else "Status: ✗ INVALID" in body)
            error_severity = ('"errorCount" : 1' in body if format_name == "json" else "Errors (1):" in body)
            record = {"capture": str(path), "sha256": sha(path), "strict": strict, "format": format_name,
                      "command": command, "command_found": command_start >= 0,
                      "settings_match": strict_matches and format_matches,
                      "save_report_field_empty": save_empty, "save_report_field_evidence": save_lines,
                      "expected_vr_error": expected_message, "expected_error_in_this_command_output": expected_message in body,
                      "invalid_status_visible": status_visible, "error_severity_visible": error_severity,
                      "console_error_indicator_visible": "text Console ERROR" in capture,
                      "output_excerpt": body,
                      "passed": command_start >= 0 and strict_matches and format_matches and save_empty and expected_message in body and status_visible and error_severity}
            console_checks.append(record)
    check("wrong_vr_console_error_in_all_four_format_strict_combinations", all(x["passed"] for x in console_checks), count=len(console_checks))
    # Repeat source hashes after all read-only validator invocations.
    check("inputs_still_unchanged_after_inspection", all(sha(args.gui_dir / x["name"]) == x["sha256"] for x in manifest), count=len(manifest))
    result = {
        "schema_version": 1, "inspected_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "scope": "Bounded GUI-created files, 13 level-2 reports, six File Meta level-1/2 reports, and four wrong-VR console captures; artifact checks only.",
        "inspector": str(Path(__file__).resolve()), "inspector_sha256": sha(Path(__file__)),
        "validator": str(args.validator), "validator_sha256": sha(args.validator),
        "gui_dir": str(args.gui_dir), "input_manifest": str(args.manifest), "input_manifest_sha256": sha(args.manifest),
        "original_fixture_manifest": str(args.original_fixtures), "input_hash_checks": hash_checks,
        "gui_output_sha256": output_hashes, "identity_checks": identity, "checks": checks,
        "signed_update_cli_execution": signed_cli_execution,
        "report_comparisons": reports, "report_count": len(reports),
        "wrong_vr_console_checks": console_checks,
        "summary": {"passed": all(x["passed"] for x in checks), "checks_passed": sum(x["passed"] for x in checks), "checks_total": len(checks),
                    "original_fixtures_unchanged": sum(x["passed"] for x in original_checks), "initial_inputs_unchanged": sum(x["passed"] for x in hash_checks),
                    "reports_matched": sum(x["passed"] for x in reports), "valid_reports": sum(x["gui_is_valid"] for x in reports), "invalid_reports": sum(not x["gui_is_valid"] for x in reports),
                    "meta_reports_matched": sum(x["passed"] for x in reports if x["report"].startswith("meta-")),
                    "wrong_vr_console_combinations_passed": sum(x["passed"] for x in console_checks)},
        "limitations": ["Does not independently prove GUI interaction sequence or displayed messages; parent owns UI evidence.",
                        "Synthetic attribute fixtures are not complete clinical IODs; no whole-standard, peer, device or clinical qualification implied.",
                        "The independent byte inspector is intentionally limited to these flat Explicit VR Little Endian output datasets.",
                        "Only the fixed 19 reports named in this script are compared; later report files are outside this snapshot.",
                        "The console AX captures truncate JSON near its final summary fields: their four-way check verifies visible error severity, message, invalid status and settings, not full console JSON serialization. Saved JSON reports receive full-field comparisons."]}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result["summary"], sort_keys=True))
    return 0 if result["summary"]["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
