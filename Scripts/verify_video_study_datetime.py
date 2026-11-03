#!/usr/bin/env python3
"""Exercise CLI Study Date/Time with synthetic video and independent DCMTK reads.

Requires ffmpeg and dcmdump on PATH. All media lives in an external temporary
directory and is removed on exit; the optional report contains text only.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    cli = str((args.bin_dir / "dicom-video").resolve())
    for tool in ["ffmpeg", "dcmdump"]:
        if not shutil.which(tool):
            parser.error(f"{tool} is required")
    checks = []
    with tempfile.TemporaryDirectory(prefix="video-study-", dir="/tmp") as folder:
        root = Path(folder)
        inputs = root / "inputs"
        inputs.mkdir()
        clip = inputs / "synthetic.mp4"
        env = dict(os.environ, LLVM_PROFILE_FILE=str(root / "coverage-%p.profraw"))

        def run(argv, expected=0):
            result = subprocess.run(argv, capture_output=True, text=True, env=env)
            if result.returncode != expected:
                raise AssertionError(f"{argv}: exit {result.returncode}, expected {expected}\n{result.stdout}{result.stderr}")
            return result

        run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
             "color=c=blue:s=640x480:r=25", "-t", "0.4", "-an", "-c:v", "libx264",
             "-profile:v", "high", "-level:v", "4.1", "-pix_fmt", "yuv420p", str(clip)])
        shutil.copyfile(clip, inputs / "second.mp4")

        def assert_tags(path, date, time):
            text = run(["dcmdump", "+P", "0008,0020", "+P", "0008,0030", str(path)]).stdout
            fields = {}
            for tag, vr, value in re.findall(r"^\((0008,00[23]0)\) (\w+) (.*?)\s+#", text, re.M):
                value = value.strip()
                if value == "(no value available)":
                    value = ""
                else:
                    assert value.startswith("[") and value.endswith("]"), text
                    value = value[1:-1].rstrip(" ")
                fields[tag] = [vr, value]
            assert fields == {"0008,0020": ["DA", date], "0008,0030": ["TM", time]}, text

        cases = [("20240229", "102030.123456"), ("20240229", "10"),
                 ("20240229", "1020"), ("20240229", None), (None, "102030"), (None, None)]
        for with_uid in [False, True]:
            for index, (date, time) in enumerate(cases):
                output = root / f"convert-{with_uid}-{index}.dcm"
                options = ["--study-uid", "1.2.826.0.1.3680043.10.999.20240229"] if with_uid else []
                if date is not None:
                    options += ["--study-date", date]
                if time is not None:
                    options += ["--study-time", time]
                run([cli, "convert", str(clip), "--output", str(output), "--type", "photographic", *options])
                assert_tags(output, date or "", time or "")
                checks.append(f"convert uid={with_uid} date={date} time={time}")

        for mode in ["single", "per-file"]:
            output = root / mode
            run([cli, "batch", str(inputs), "--output-dir", str(output), "--type", "photographic",
                 "--series-mode", mode, "--study-date", "20240229", "--study-time", "102030.123456"])
            files = sorted(output.glob("*.dcm"))
            assert len(files) == 2, files
            for file in files:
                assert_tags(file, "20240229", "102030.123456")
            checks.append(f"batch {mode}: both instances mapped correctly")

        for operation in ["convert", "batch"]:
            for dry in [False, True]:
                for flag, value in [("--study-date", "20230229"), ("--study-date", "2024.02.29"),
                                    ("--study-time", "240000"), ("--study-time", "10:20:30")]:
                    output = root / "must-not-exist"
                    arguments = [str(clip), "--output"] if operation == "convert" else [str(inputs), "--output-dir"]
                    result = run([cli, operation, *arguments, str(output), flag, value,
                                  *(["--dry-run"] if dry else [])], expected=1)
                    assert flag in result.stderr, result.stderr
                    assert not output.exists(), output
                    checks.append(f"{operation} dry={dry}: rejected {flag} {value} without output")
    report = {"result": "passed", "checks": checks, "check_count": len(checks),
              "reader": "DCMTK dcmdump", "synthetic_media_retained": False}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
