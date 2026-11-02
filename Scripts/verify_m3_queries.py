#!/usr/bin/env python3
"""Independent synthetic Part 10 fixtures, process probes, HTTP bridge and CLI oracles.

No DICOMKit encoder is used to produce the expected hierarchy or matching values.
The bridge delegates each request to the real Swift router/provider through files.
"""
import argparse
import contextlib
import http.server
import json
import os
from pathlib import Path
import struct
import subprocess
import threading
import time
import urllib.parse
import urllib.request

LONG = {"OB", "OW", "SQ", "UN", "UT"}
STUDIES = ["1.2.826.0.1.3680043.10.543.301", "1.2.826.0.1.3680043.10.543.302"]
SERIES = [STUDIES[0] + ".1", STUDIES[0] + ".2", STUDIES[1] + ".1"]
INSTANCES = [SERIES[0] + ".1", SERIES[0] + ".2", SERIES[1] + ".1", SERIES[2] + ".1", SERIES[2] + ".2"]
CT, MR = "1.2.840.10008.5.1.4.1.1.2", "1.2.840.10008.5.1.4.1.1.4"


def element(tag, vr, value):
    if isinstance(value, str):
        value = value.encode("utf-8")
    if len(value) % 2:
        value += b"\0" if vr == "UI" else b" "
    header = struct.pack("<HH", int(tag[:4], 16), int(tag[4:], 16)) + vr.encode()
    return header + (b"\0\0" + struct.pack("<I", len(value)) if vr in LONG else struct.pack("<H", len(value))) + value


def dataset(values):
    return b"".join(element(tag, vr, value) for tag, (vr, value) in sorted(values.items()))


def sequence(items):
    return b"".join(struct.pack("<HHI", 0xfffe, 0xe000, len(item)) + item for item in map(dataset, items))


def make_fixtures(root):
    root.mkdir(parents=True, exist_ok=True)
    manifest = []
    # P1 has CT and MR; P2 has CT. InstanceNumber is 1, 2, missing, 1, 2.
    for index, instance in enumerate(INSTANCES):
        series_index = [0, 0, 1, 2, 2][index]
        patient = 0 if series_index < 2 else 1
        modality, sop = ("MR", MR) if series_index == 1 else ("CT", CT)
        values = {
            "00080005": ("CS", "ISO_IR 192"), "00080016": ("UI", sop), "00080018": ("UI", instance),
            "00080020": ("DA", ["20260115", "20260220"][patient]), "00080030": ("TM", "101500"),
            "00080050": ("SH", ["ACC-A", "ACC-B"][patient]), "00080060": ("CS", modality),
            "00081030": ("LO", ["Chest synthetic", "Head synthetic"][patient]),
            "0008103E": ("LO", ["CT-A", "MR-A", "CT-B"][series_index]),
            "00100010": ("PN", ["Müller^Synthetic", "BETA^Synthetic"][patient]),
            "00100020": ("LO", ["P1", "P2"][patient]), "00100030": ("DA", "19700101"), "00101010": ("AS", "050Y"),
            "0020000D": ("UI", STUDIES[patient]), "0020000E": ("UI", SERIES[series_index]),
            "00200010": ("SH", ["ST-A", "ST-B"][patient]), "00200011": ("IS", str(series_index + 1)),
            "00280010": ("US", struct.pack("<H", 512)),
        }
        if index != 2:
            values["00200013"] = ("IS", "2" if index in (1, 4) else "1")
        if series_index != 2:
            values["00400244"] = ("DA", ["20260115", "20260116"][series_index])
            values["00400245"] = ("TM", ["093000", "113000"][series_index])
            items = [{"00400009": ("SH", "SPS-A"), "00401001": ("SH", "RP-A"), "00321033": ("LO", "SERVICE-A")}]
            if series_index == 0:
                items.append({"00400009": ("SH", "SPS-B"), "00401001": ("SH", "RP-B")})
            else:
                items = [{"00400009": ("SH", "SPS-MR"), "00401001": ("SH", "RP-MR")}]
            values["00400275"] = ("SQ", sequence(items))
        meta = dataset({"00020001": ("OB", b"\0\1"), "00020002": ("UI", sop), "00020003": ("UI", instance),
                        "00020010": ("UI", "1.2.840.10008.1.2.1"), "00020012": ("UI", "1.2.826.0.1.3680043.10.543")})
        content = bytes(128) + b"DICM" + element("00020000", "UL", struct.pack("<I", len(meta))) + meta + dataset(values)
        name = f"synthetic-{index}.dcm"
        (root / name).write_bytes(content)
        manifest.append({"file": name, "study": STUDIES[patient], "series": SERIES[series_index], "instance": instance})
    (root / "fixtures.json").write_text(json.dumps(manifest, indent=2))


def wait_file(path, timeout=30):
    deadline = time.monotonic() + timeout
    while not path.exists():
        if time.monotonic() > deadline:
            raise TimeoutError(str(path))
        time.sleep(.02)
    return path


class Bridge:
    def __init__(self, bundle, root):
        self.root, self.bundle, self.captures = root, bundle, []
        self.lock, self.serial = threading.Lock(), 0

    def start(self):
        make_fixtures(self.root)
        for pattern in ("*.request", "*.response", "*.tmp"):
            for stale in self.root.glob(pattern):
                stale.unlink()
        for name in ("stop", "stop-http", "ready"):
            (self.root / name).unlink(missing_ok=True)
        (self.root / "captures.json").write_text("[]")
        self.log = (self.root / "swift-bridge.log").open("w")
        self.process = subprocess.Popen(harness_command(self.bundle), env={**os.environ, "DICOMKIT_M3_BRIDGE_DIR": str(self.root)}, stdout=self.log, stderr=subprocess.STDOUT)
        wait_file(self.root / "ready")
        bridge = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                try:
                    with bridge.lock:
                        bridge.serial += 1
                        prefix = bridge.root / f"http-{bridge.serial:05d}"
                        request = prefix.with_suffix(".request")
                        temporary = prefix.with_suffix(".tmp")
                        temporary.write_text(self.path)
                        temporary.rename(request)
                        response = json.loads(wait_file(prefix.with_suffix(".response")).read_text())
                        bridge.captures.append({"path": self.path, **response})
                        (bridge.root / "captures.json").write_text(json.dumps(bridge.captures, indent=2, ensure_ascii=False))
                    self.send_response(response["status"])
                    body = response["body"].encode()
                    for key, value in response["headers"].items():
                        if key.lower() not in ("content-length", "connection"):
                            self.send_header(key, value)
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except Exception as error:
                    self.send_error(500, str(error))

            def log_message(self, *args):
                pass

        self.http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.http.server_port}/dicom-web"
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        (self.root / "http-ready.json").write_text(json.dumps({"url": self.url, "pid": self.process.pid}))
        return self

    def close(self):
        self.http.shutdown()
        (self.root / "stop").touch()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=10)
        self.log.close()
        assert self.process.returncode == 0, "Swift request bridge failed"


def harness_command(bundle):
    return ["xcrun", "xctest", "-XCTest", "DICOMWebTests.M3QueryProcessHarnessTests/testQueryProcessHarness", str(bundle)]


def ids(body, level):
    tag = {"study": "0020000D", "series": "0020000E", "instance": "00080018"}[level]
    return [row[tag]["Value"][0] for row in json.loads(body)]


def run(args):
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    records = []
    try:
        if not args.skip_isolated:
            fixture = root / "isolated"
            make_fixtures(fixture)
            for endpoint, level, count in [("studies", "study", 2), ("series", "series", 3), ("instances", "instance", 5)]:
                for query, status, size in [("offset=-1", 400, None), ("limit=-1", 400, None), ("offset=abc", 400, None),
                    ("limit=1.5", 400, None), ("offset=" + "9" * 80, 400, None), ("limit=" + "9" * 80, 400, None),
                    ("limit=0", 200, 0), ("offset=0", 200, count), ("offset=0&limit=1", 200, 1),
                    ("offset=9223372036854775807&limit=9223372036854775807", 200, 0), ("limit=9223372036854775807", 200, count)]:
                    response_file = fixture / "probe-response.json"
                    response_file.unlink(missing_ok=True)
                    path = f"/dicom-web/{endpoint}?{query}"
                    process = subprocess.run(harness_command(args.test_bundle), env={**os.environ, "DICOMKIT_M3_BRIDGE_DIR": str(fixture),
                        "DICOMKIT_M3_PROBE_PATH": path}, capture_output=True, text=True, timeout=30)
                    record = {"kind": "isolated", "path": path, "exit": process.returncode, "expected_status": status}
                    records.append(record)
                    assert process.returncode == 0, process.stdout + process.stderr
                    response = json.loads(response_file.read_text())
                    record.update(response)
                    assert response["status"] == status, record
                    if size is not None:
                        assert len(ids(response["body"], level)) == size, record
                    if query == "limit=0":
                        assert any(k.lower() == "warning" and str(count) in v for k, v in response["headers"].items()), record
                    record["passed"] = True
        bridge = Bridge(args.test_bundle, root / "http").start()
        try:
            def check(endpoint, query, expected, level, status=200):
                encoded = urllib.parse.urlencode(query, doseq=True) if not isinstance(query, str) else query
                url = bridge.url + "/" + endpoint + ("?" + encoded if encoded else "")
                try:
                    with urllib.request.urlopen(url, timeout=30) as response:
                        result_status, body = response.status, response.read().decode()
                except urllib.error.HTTPError as error:
                    result_status, body = error.code, error.read().decode()
                record = {"kind": "http", "path": urllib.parse.urlsplit(url).path + "?" + encoded,
                          "status": result_status, "expected_status": status, "expected_ids": expected, "body": body}
                records.append(record)
                assert result_status == status, record
                if status == 200:
                    assert ids(body, level) == expected, record
                record["passed"] = True
                return json.loads(body)

            for endpoint, level, expected in [("studies", "study", STUDIES), ("series", "series", SERIES), ("instances", "instance", INSTANCES)]:
                for _ in range(3):
                    check(endpoint, {}, expected, level)
                check(endpoint, {"offset": 1, "limit": 1}, expected[1:2], level)
            for tag in ("PatientID", "00100020"):
                check("series", {tag: "NO_MATCH"}, [], "series")
                check("series", {tag: "P1"}, SERIES[:2], "series")
                check("instances", {tag: "P2"}, INSTANCES[3:], "instance")
                check(f"studies/{STUDIES[0]}/series", {tag: "P2"}, [], "series")
                check(f"studies/{STUDIES[0]}/series/{SERIES[0]}/instances", {tag: "P2"}, [], "instance")
            # Literal acceptance controls: nonmatching patient at All Instances,
            # restrictive study AND series filters, and leaf filters inside both path UIDs.
            for tag in ("PatientID", "00100020"):
                check("instances", {tag: "NO_MATCH"}, [], "instance")
            check("instances", {"Modality": "CT"}, [*INSTANCES[:2], *INSTANCES[3:]], "instance")
            check("instances", {"StudyInstanceUID": STUDIES[0], "Modality": "CT"}, INSTANCES[:2], "instance")
            check("instances", {"StudyDate": "20260101-20260131", "Modality": "CT"}, INSTANCES[:2], "instance")
            scoped_instances = f"studies/{STUDIES[0]}/series/{SERIES[0]}/instances"
            check(scoped_instances, {"InstanceNumber": "2", "PatientID": "P1"}, INSTANCES[1:2], "instance")
            check(scoped_instances, {"SOPInstanceUID": INSTANCES[4]}, [], "instance")
            check("studies", {"PatientName": "Müll*", "StudyDate": "20260101-20260131"}, STUDIES[:1], "study")
            check("series", {"StudyDate": "20260101-20260131", "AccessionNumber": "ACC-A", "ModalitiesInStudy": "MR", "Modality": "CT"}, SERIES[:1], "series")
            check("instances", {"PatientID": "P1", "Modality": "CT"}, INSTANCES[:2], "instance")
            check(f"studies/{STUDIES[0]}/instances", {"Modality": "MR"}, INSTANCES[2:3], "instance")
            for tag in ("InstanceNumber", "00200013"):
                check("instances", {tag: "2"}, [INSTANCES[1], INSTANCES[4]], "instance")
                check("instances", {tag: "1"}, [INSTANCES[0], INSTANCES[3]], "instance")
                check("instances", {tag: "+2"}, [INSTANCES[1], INSTANCES[4]], "instance")
                check("instances", {tag: "2", "SOPInstanceUID": INSTANCES[1]}, [INSTANCES[1]], "instance")
            for keyword, tag, endpoint, expected, level in [("StudyInstanceUID", "0020000D", "studies", STUDIES, "study"),
                    ("SeriesInstanceUID", "0020000E", "series", [SERIES[0], SERIES[2]], "series"),
                    ("SOPInstanceUID", "00080018", "instances", [INSTANCES[0], INSTANCES[4]], "instance")]:
                for name in (keyword, tag):
                    check(endpoint, {name: ",".join(expected)}, expected, level)
            check("instances", {"StudyInstanceUID": ",".join(STUDIES), "Modality": "MR"}, INSTANCES[2:3], "instance")
            check("instances", {"SOPClassUID": CT + "," + MR}, INSTANCES, "instance")
            check("instances", {"00080016": CT}, [*INSTANCES[:2], *INSTANCES[3:]], "instance")
            for endpoint, level, expected in [("series", "series", SERIES[:1]), ("instances", "instance", INSTANCES[:2]),
                    (f"studies/{STUDIES[0]}/instances", "instance", INSTANCES[:2])]:
                # Each required predicate independently excludes the other series;
                # these controls also exclude the third series with missing PPS/SQ.
                for name, positive in [("PerformedProcedureStepStartDate", "20260115"),
                        ("PerformedProcedureStepStartTime", "090000-100000"),
                        ("RequestAttributesSequence.ScheduledProcedureStepID", "SPS-B"),
                        ("RequestAttributesSequence.RequestedProcedureID", "RP-B")]:
                    check(endpoint, {name: positive}, expected, level)
                    negative = "20260117" if name.endswith("Date") else "150000-160000" if name.endswith("Time") else "NO_MATCH"
                    check(endpoint, {name: negative}, [], level)
                check(endpoint, {"PerformedProcedureStepStartDate": "20260115", "PerformedProcedureStepStartTime": "090000-100000"}, expected, level)
                for prefix, child in [("RequestAttributesSequence", "ScheduledProcedureStepID"), ("00400275", "00400009"), ("00400275", "ScheduledProcedureStepID")]:
                    check(endpoint, {prefix + "." + child: "SPS-B"}, expected, level)
                check(endpoint, {"00400275.00400009": "SPS-A", "00400275.00401001": "RP-B"}, [], level)
            check("series", {"PerformedProcedureStepStartDate": "20260115-20260116"}, SERIES[:2], "series")
            check("series", {"PerformedProcedureStepStartDate": "20260114-20260116", "PerformedProcedureStepStartTime": "100000-120000"}, SERIES[:2], "series")
            for query in ["limit=-2", "PatientID=P1&PatientID=P2", "PatientID=P1&00100020=P1", "includefield=all&includefield=PatientBirthDate",
                          "includefield=all,PatientBirthDate", "PatientID=%ZZ", "UnknownFilter=P1"]:
                check("studies", query, None, "study", 400)
            default = check("studies", {}, STUDIES, "study")
            assert "00101010" not in default[0]
            for query in [{"includefield": "PatientAge"}, {"includefield": "00101010"}, {"includefield": "all"}, {"includefield": "PatientAge,PatientBirthDate"},
                          [("includefield", "PatientAge"), ("includefield", "PatientBirthDate")]]:
                rows = check("studies", query, STUDIES, "study")
                assert rows[0]["00101010"] == {"vr": "AS", "Value": ["050Y"]}, rows
            for name in ("RequestAttributesSequence.RequestingService", "00400275.00321033", "RequestAttributesSequence.00321033"):
                rows = check("series", {"includefield": name}, SERIES, "series")
                assert rows[0]["00400275"]["Value"][0]["00321033"] == {"vr": "LO", "Value": ["SERVICE-A"]}, rows

            # Capture all six targets through the shipped executable, not a mock transport.
            cli_cases = [(["--level", "study", "--modality", "CT"], "/studies", {"00080061": ["CT"]}, STUDIES, "study"),
                (["--level", "series", "--modality", "CT"], "/series", {"00080060": ["CT"]}, [SERIES[0], SERIES[2]], "series"),
                (["--level", "series", "--study", STUDIES[0], "--modality", "CT"], f"/studies/{STUDIES[0]}/series", {"00080060": ["CT"]}, SERIES[:1], "series"),
                (["--level", "instance", "--modality", "CT"], "/instances", {"00080060": ["CT"]}, [*INSTANCES[:2], *INSTANCES[3:]], "instance"),
                (["--level", "instance", "--study", STUDIES[0], "--modality", "CT"], f"/studies/{STUDIES[0]}/instances", {"00080060": ["CT"]}, INSTANCES[:2], "instance"),
                (["--level", "instance", "--study", STUDIES[0], "--series", SERIES[0], "--patient-id", "P1"], f"/studies/{STUDIES[0]}/series/{SERIES[0]}/instances", {"00100020": ["P1"]}, INSTANCES[:2], "instance")]
            pps_args = ["--pps-start-date", "20260115", "--pps-start-time", "090000-100000", "--sps-id", "SPS-A", "--requested-procedure-id", "RP-A"]
            pps_params = {"00400244": ["20260115"], "00400245": ["090000-100000"], "00400275.00400009": ["SPS-A"], "00400275.00401001": ["RP-A"]}
            for scope in ([], ["--study", STUDIES[0]]):
                path = "/instances" if not scope else f"/studies/{STUDIES[0]}/instances"
                cli_cases.append((["--level", "instance", *scope, *pps_args], path, pps_params, INSTANCES[:2], "instance"))
            cli_cases.extend([
                (["--level", "series", "--study", ",".join(STUDIES), "--patient-id", "P1"], "/series", {"0020000D": [",".join(STUDIES)], "00100020": ["P1"]}, SERIES[:2], "series"),
                (["--level", "instance", "--study", STUDIES[0], "--series", ",".join(SERIES[:2])], f"/studies/{STUDIES[0]}/instances", {"0020000E": [",".join(SERIES[:2])]}, INSTANCES[:3], "instance")])
            for argv, path, expected_params, expected, level in cli_cases:
                before = len(bridge.captures)
                process = subprocess.run([str(args.bin_dir / "dicom-wado"), "query", bridge.url, *argv, "--format", "dicom-json"], capture_output=True, text=True, timeout=30)
                record = {"kind": "cli", "argv": argv, "exit": process.returncode, "stdout": process.stdout, "stderr": process.stderr}
                records.append(record)
                assert process.returncode == 0 and len(bridge.captures) == before + 1, record
                assert "ignor" not in process.stderr.lower(), record
                capture = bridge.captures[-1]
                parsed = urllib.parse.urlsplit(capture["path"])
                params = urllib.parse.parse_qs(parsed.query)
                assert parsed.path == "/dicom-web" + path, capture
                assert params == {"limit": ["100"], "offset": ["0"], **expected_params}, capture
                assert ids(process.stdout, level) == expected, record
                record.update({"capture": capture, "passed": True})
            for argv in [["--level", "instance", "--study", STUDIES[0], "--series", SERIES[0], "--modality", "CT"],
                         ["--level", "study", "--pps-start-date", "20260115"],
                         ["--level", "series", "--study", STUDIES[0], "--study-date", "20260115"]]:
                before = len(bridge.captures)
                process = subprocess.run([str(args.bin_dir / "dicom-wado"), "query", bridge.url, *argv], capture_output=True, text=True, timeout=30)
                record = {"kind": "cli-refusal", "argv": argv, "exit": process.returncode, "stderr": process.stderr, "stdout": process.stdout}
                records.append(record)
                assert process.returncode != 0 and len(bridge.captures) == before, record
                record["passed"] = True
        finally:
            bridge.close()
    finally:
        (root / "results.json").write_text(json.dumps(records, indent=2, ensure_ascii=False))
    print(f"M3 independent probes passed: {len(records)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-bundle", type=Path, required=True)
    parser.add_argument("--bin-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--skip-isolated", action="store_true")
    parser.add_argument("--serve", action="store_true", help="Keep the synthetic HTTP bridge running for packaged-app checks")
    args = parser.parse_args()
    if args.serve:
        bridge = Bridge(args.test_bundle.resolve(), args.output_dir.resolve()).start()
        print(bridge.url, flush=True)
        try:
            while not (bridge.root / "stop-http").exists():
                time.sleep(.2)
        finally:
            bridge.close()
    else:
        run(args)
