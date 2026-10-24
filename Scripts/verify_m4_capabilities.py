#!/usr/bin/env python3
"""M4 capabilities/retrieval gate over a loopback HTTP adapter to the real Swift server.
Uses independently encoded Part 10 data, the built test harness and actual dicom-wado.
No build, dependency download, external PACS access, or production HTTP-server claim.
"""
import argparse
import base64
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import threading
import time
import xml.etree.ElementTree as ET

STUDY, SERIES, INSTANCE = "2.25.401", "2.25.401.1", "2.25.401.1.1"
XML = "application/vnd.sun.wadl+xml"
MULTIPART = 'multipart/related; type="application/dicom"'
NAMESPACE = "http://wadl.dev.java.net/2009/02"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fixture(root):
    def element(tag, vr, value):
        if isinstance(value, str):
            value = value.encode("ascii")
        if len(value) % 2:
            value += b"\0" if vr == "UI" else b" "
        header = struct.pack("<HH", int(tag[:4], 16), int(tag[4:], 16)) + vr.encode()
        return header + (b"\0\0" + struct.pack("<I", len(value)) if vr == "OB" else struct.pack("<H", len(value))) + value
    def dataset(values):
        return b"".join(element(tag, vr, value) for tag, (vr, value) in sorted(values.items()))
    sop = "1.2.840.10008.5.1.4.1.1.7"
    meta = dataset({"00020001": ("OB", b"\0\1"), "00020002": ("UI", sop), "00020003": ("UI", INSTANCE),
                    "00020010": ("UI", "1.2.840.10008.1.2.1"), "00020012": ("UI", "2.25.999401")})
    body = dataset({"00080016": ("UI", sop), "00080018": ("UI", INSTANCE), "00080060": ("CS", "OT"),
                    "00100010": ("PN", "CAPABILITIES^SYNTHETIC"), "00100020": ("LO", "M4-SYNTHETIC"),
                    "0020000D": ("UI", STUDY), "0020000E": ("UI", SERIES), "00200013": ("IS", "1")})
    data = bytes(128) + b"DICM" + element("00020000", "UL", struct.pack("<I", len(meta))) + meta + body
    (root / "synthetic.dcm").write_bytes(data)
    (root / "fixtures.json").write_text(json.dumps([{"file": "synthetic.dcm", "study": STUDY, "series": SERIES, "instance": INSTANCE}], indent=2))
    return data


class Bridge:
    def __init__(self, root, bundle):
        self.root, self.bundle = root, bundle
        self.captures, self.serial = [], 0
        self.lock = threading.Lock()
        self.process = None
        bridge = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def dispatch(self):
                try:
                    with bridge.lock:
                        bridge.serial += 1
                        prefix = bridge.root / f"http-{bridge.serial:05d}"
                        count = int(self.headers.get("Content-Length", "0"))
                        body = self.rfile.read(count) if count else None
                        request = {"method": self.command, "path": self.path, "headers": dict(self.headers),
                                   "bodyBase64": base64.b64encode(body).decode() if body else None}
                        temporary = prefix.with_suffix(".tmp")
                        temporary.write_text(json.dumps(request))
                        temporary.replace(prefix.with_suffix(".request"))
                        bridge.wait(prefix.with_suffix(".response"))
                        response = json.loads(prefix.with_suffix(".response").read_text())
                        bridge.captures.append({"request": request, "response": response})
                        (bridge.root / "captures.json").write_text(json.dumps(bridge.captures, indent=2))
                    payload = base64.b64decode(response["bodyBase64"])
                    self.send_response(response["status"])
                    for key, value in response["headers"].items():
                        if key.lower() not in ("content-length", "connection"):
                            self.send_header(key, value)
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    if self.command != "HEAD":
                        self.wfile.write(payload)
                except Exception as error:
                    self.send_error(500, str(error))
            do_GET = do_OPTIONS = do_POST = do_PUT = do_DELETE = do_HEAD = dispatch
            def log_message(self, *args):
                pass

        self.http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.http.server_port}/dicom-web"

    def wait(self, path):
        deadline = time.monotonic() + 30
        while not path.exists():
            if self.process.poll() is not None:
                raise RuntimeError("Swift bridge exited; inspect swift-bridge.log")
            if time.monotonic() >= deadline:
                raise TimeoutError(str(path))
            time.sleep(.02)

    def start(self):
        self.log = (self.root / "swift-bridge.log").open("w")
        self.process = subprocess.Popen(["xcrun", "xctest", "-XCTest",
            "DICOMWebTests.M4CapabilitiesProcessHarnessTests/testCapabilitiesProcessHarness", str(self.bundle)],
            env={**os.environ, "DICOMKIT_M4_CAPABILITIES_BRIDGE": str(self.root), "DICOMKIT_M4_CAPABILITIES_BASE": self.url},
            stdout=self.log, stderr=subprocess.STDOUT)
        try:
            self.wait(self.root / "ready")
        except BaseException:
            self.process.terminate()
            self.process.wait(timeout=10)
            self.log.close()
            self.http.server_close()
            raise
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        (self.root / "http-ready.json").write_text(json.dumps({"url": self.url, "study": STUDY, "series": SERIES, "instance": INSTANCE}))
        return self

    def close(self):
        self.http.shutdown()
        self.http.server_close()
        (self.root / "stop").touch()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=10)
        self.log.close()
        assert self.process.returncode == 0, "Swift request bridge failed"

    def request(self, method, path="", headers=None, body=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.http.server_port, timeout=30)
        try:
            connection.request(method, "/dicom-web" + path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, {k.lower(): v for k, v in response.getheaders()}, response.read()
        finally:
            connection.close()


def walk(resource, prefix=""):
    path = prefix + ("/" + resource["@path"] if resource["@path"] else "")
    result = {(method["@name"], path) for method in resource.get("method", [])}
    for child in resource.get("resource", []):
        result |= walk(child, path)
    return result


def validate_schema(root, report):
    executable = shutil.which("xmllint")
    if executable is None:
        report["schema_validation"] = {"status": "unavailable", "reason": "xmllint is not installed"}
        return
    schemas = Path(__file__).resolve().parent / "Fixtures" / "WADL"
    provenance = json.loads((schemas / "sources.json").read_text())
    for name, metadata in provenance.items():
        assert sha((schemas / name).read_bytes()) == metadata["sha256"], "Vendored official schema changed"
    catalog = ET.Element("catalog", xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog")
    ET.SubElement(catalog, "uri", name="http://www.w3.org/2001/xml.xsd", uri=(schemas / "xml.xsd").as_uri())
    ET.ElementTree(catalog).write(root / "schema-catalog.xml", encoding="utf-8", xml_declaration=True)
    command = [executable, "--nonet", "--noout", "--schema", str(schemas / "wadl.xsd"), str(root / "capabilities.xml")]
    process = subprocess.run(command, capture_output=True, text=True, timeout=15,
                             env={**os.environ, "XML_CATALOG_FILES": str(root / "schema-catalog.xml")})
    (root / "schema-validation.log").write_text(process.stdout + process.stderr)
    report["schema_validation"] = {"status": "passed" if process.returncode == 0 else "failed",
                                    "exit": process.returncode, "schema_provenance": provenance}
    assert process.returncode == 0, process.stderr


def verify(args, bridge, golden, report):
    def check(name, method, path, headers, status, body=None):
        actual, response_headers, data = bridge.request(method, path, headers, body)
        record = {"name": name, "method": method, "path": path, "status": actual, "expected_status": status,
                  "response_headers": response_headers, "body_sha256": sha(data)}
        report["cases"].append(record)
        assert actual == status, record
        record["passed"] = True
        return response_headers, data

    _, json_data = check("capabilities-json", "OPTIONS", "", {"Accept": "application/json"}, 200)
    _, xml_data = check("capabilities-xml", "OPTIONS", "", {"Accept": XML}, 200)
    (args.output_dir / "capabilities.json").write_bytes(json_data)
    (args.output_dir / "capabilities.xml").write_bytes(xml_data)
    application = json.loads(json_data)["application"]
    assert application["@xmlns"] == NAMESPACE
    assert len(application["resources"]) == 1
    resources = application["resources"][0]
    assert resources["@base"] == bridge.url and len(resources["resource"]) == 1
    advertised = walk(resources["resource"][0])
    tree = ET.fromstring(xml_data)
    assert tree.tag == "{" + NAMESPACE + "}application"
    xml_resources = tree.findall("{" + NAMESPACE + "}resources")
    assert len(xml_resources) == 1 and xml_resources[0].get("base") == bridge.url
    assert not any(method.get("name") == "OPTIONS" for method in tree.iter("{" + NAMESPACE + "}method"))
    validate_schema(args.output_dir, report)
    for name, headers, status, expected in [
        ("missing-accept", {}, 406, None), ("unacceptable", {"Accept": "image/png"}, 406, None),
        ("wildcard", {"Accept": "*/*"}, 200, "application/json"),
        ("weighted", {"Accept": f"application/json;q=0.1,{XML};q=0.9"}, 200, XML),
        ("specific-exclusion", {"Accept": "application/json;q=0,*/*"}, 200, XML),
        ("all-excluded", {"Accept": f"application/json;q=0,{XML};q=0,*/*"}, 406, None),
        ("unsupported-charset", {"Accept": "application/json", "Accept-Charset": "iso-8859-1"}, 406, None),
        ("utf8", {"Accept": XML, "Accept-Charset": "utf-8"}, 200, XML),
    ]:
        headers, _ = check(name, "OPTIONS", "", headers, status)
        assert headers.get("content-type") == expected, headers
    check("query-refusal", "OPTIONS", "?offset=1", {"Accept": XML}, 400)
    check("body-refusal", "OPTIONS", "", {"Accept": XML}, 400, b"not permitted")
    headers, _ = check("method-refusal", "PUT", "/studies", {"Accept": "*/*"}, 405)
    assert headers["allow"] == "GET, POST"
    headers, data = check("cors-preflight", "OPTIONS", "", {"Origin": "https://client.invalid", "Access-Control-Request-Method": "GET"}, 204)
    assert headers["access-control-allow-origin"] == "*" and "GET" in headers["access-control-allow-methods"] and data == b""
    check("origin-bearing-capabilities", "OPTIONS", "", {"Origin": "https://client.invalid", "Accept": XML}, 200)
    base = f"/studies/{STUDY}"
    targets = [base, base + "/metadata", base + f"/series/{SERIES}", base + f"/series/{SERIES}/metadata",
               base + f"/series/{SERIES}/instances/{INSTANCE}", base + f"/series/{SERIES}/instances/{INSTANCE}/metadata"]
    for path in targets:
        template = path.replace(INSTANCE, "{instanceUID}").replace(SERIES, "{seriesUID}").replace(STUDY, "{studyUID}")
        assert ("GET", template) in advertised, template
        metadata = path.endswith("/metadata")
        headers, data = check("advertised-retrieve", "GET", path, {"Accept": "application/dicom+json" if metadata else MULTIPART}, 200)
        if metadata:
            values = json.loads(data)
            assert len(values) == 1 and values[0]["00080018"]["Value"] == [INSTANCE]
            assert values[0]["0020000D"]["Value"] == [STUDY] and values[0]["0020000E"]["Value"] == [SERIES]
        else:
            assert headers["content-type"].startswith("multipart/related") and golden in data
    for suffix in ["bulkdata", "rendered", "thumbnail", "frames/1"]:
        assert not any(suffix.split("/")[0] in path for _, path in advertised)
        check("unavailable-" + suffix, "GET", targets[4] + "/" + suffix, {"Accept": "*/*"}, 501)
    for path in ["", "/capabilities"]:
        _, data = check("private-capabilities", "GET", path, {"Accept": "application/json"}, 200)
        private = json.loads(data)
        assert private["services"]["bulkdata"] is False
        assert private["services"]["rendered"] is False and private["mediaTypes"]["rendered"] == []
    binary = args.bin_dir / "dicom-wado"
    for name, scope in [("study", []), ("series", ["--series", SERIES]), ("instance", ["--series", SERIES, "--instance", INSTANCE])]:
        output = args.output_dir / ("cli-" + name)
        argv = [str(binary), "retrieve", bridge.url, "--study", STUDY, *scope, "--output", str(output)]
        before = len(bridge.captures)
        process = subprocess.run(argv, capture_output=True, text=True, timeout=30)
        record = {"name": "cli-retrieve-" + name, "argv": argv, "exit": process.returncode, "stdout": process.stdout, "stderr": process.stderr}
        report["cases"].append(record)
        assert process.returncode == 0 and len(bridge.captures) == before + 1, record
        files = list(output.glob("*.dcm"))
        assert len(files) == 1 and files[0].read_bytes() == golden, record
        record.update({"passed": True, "sha256": sha(files[0].read_bytes()), "capture": bridge.captures[-1]})
    report["passed"] = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, required=True)
    parser.add_argument("--test-bundle", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--serve", action="store_true", help="Keep the synthetic bridge available for packaged-app retrieval checks")
    args = parser.parse_args()
    args.bin_dir, args.test_bundle, args.output_dir = args.bin_dir.resolve(), args.test_bundle.resolve(), args.output_dir.resolve()
    if args.output_dir.exists():
        parser.error("Use a fresh output directory to preserve earlier evidence")
    if not (args.bin_dir / "dicom-wado").is_file() or not args.test_bundle.exists():
        parser.error("Supply the built dicom-wado directory and DICOMWebTests.xctest bundle")
    args.output_dir.mkdir(parents=True)
    golden = fixture(args.output_dir)
    report = {"items": ["NET-09-A", "NET-09-B"], "cases": [], "passed": False,
              "fixture_sha256": sha(golden), "binary_sha256": sha((args.bin_dir / "dicom-wado").read_bytes()),
              "http_adapter_is_test_code": True, "synthetic_loopback_only": True}
    bridge = Bridge(args.output_dir, args.test_bundle).start()
    try:
        if args.serve:
            print(bridge.url, flush=True)
            while not (args.output_dir / "stop-http").exists():
                time.sleep(.2)
        else:
            verify(args, bridge, golden, report)
    finally:
        try:
            bridge.close()
        finally:
            (args.output_dir / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    if not args.serve:
        print(f"M4 capabilities: {len(report['cases'])} HTTP/CLI cases passed; schema {report['schema_validation']['status']}")


if __name__ == "__main__":
    main()
