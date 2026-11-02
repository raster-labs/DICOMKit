#!/usr/bin/env python3
"""Independent loopback UPS identity oracle for PS3.18 2026a 11.4.1.1.
Strict only for Create identity, state, routing and duplicate handling; not a
complete UPS IOD/server implementation. Stores are isolated by surface prefix.
"""
import copy, datetime, http.server, json, pathlib, re, sys, time, urllib.parse

STORES = ("native", "cli", "cli-generated", "cli-default")
UID_RE = re.compile(r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))*", re.ASCII)

def valid_uid(value):
    return isinstance(value, str) and 1 <= len(value.encode("utf-8")) <= 64 and UID_RE.fullmatch(value) is not None

def resolve_identity(target, payload):
    u = urllib.parse.urlsplit(target)
    parts = u.path.split("/")
    if len(parts) != 4 or parts[1] not in STORES or parts[2:] != ["dicom-web", "workitems"]:
        raise ValueError("Unsupported collection target")
    if not isinstance(payload, dict):
        raise ValueError("Data Set must be an object")
    query = urllib.parse.parse_qs(u.query, keep_blank_values=True)
    if query:
        if set(query) != {"workitem"} or len(query["workitem"]) != 1 or not valid_uid(query["workitem"][0]):
            raise ValueError("Invalid Workitem query identity")
        if "00080018" in payload:
            raise ValueError("Query identity form must not also supply Data Set UID")
        uid, form = query["workitem"][0], "query"
    else:
        element = payload.get("00080018")
        if not isinstance(element, dict) or element.get("vr") != "UI" or "InlineBinary" in element or "BulkDataURI" in element:
            raise ValueError("Collection target requires a UI Workitem UID")
        values = element.get("Value")
        if not isinstance(values, list) or len(values) != 1 or not valid_uid(values[0]):
            raise ValueError("Collection Workitem UID must be one valid string")
        uid, form = values[0], "body"
    if payload.get("00741000") != {"vr": "CS", "Value": ["SCHEDULED"]}:
        raise ValueError("Create state must be SCHEDULED")
    return parts[1], uid, form

def selftest():
    base = {"00741000": {"vr": "CS", "Value": ["SCHEDULED"]}}
    good = dict(base, **{"00080018": {"vr": "UI", "Value": ["2.25.701"]}})
    assert resolve_identity("/native/dicom-web/workitems", good) == ("native", "2.25.701", "body")
    assert resolve_identity("/cli/dicom-web/workitems?workitem=2.25.702", base) == ("cli", "2.25.702", "query")
    bad = [
        ("/native/dicom-web/workitems", base),
        ("/native/dicom-web/workitems", dict(base, **{"00080018": {"vr": "LO", "Value": ["2.25.1"]}})),
        ("/native/dicom-web/workitems", dict(base, **{"00080018": {"vr": "UI", "Value": ["1.02"]}})),
        ("/native/dicom-web/workitems", dict(base, **{"00080018": {"vr": "UI", "Value": ["2.25.1", "2.25.2"]}})),
        ("/native/dicom-web/workitems?workitem=2.25.1", good),
        ("/native/dicom-web/workitems?workitem=1.02", base),
        ("/native/dicom-web/workitems?workitem=2.25.1&workitem=2.25.2", base),
    ]
    for target, payload in bad:
        try: resolve_identity(target, payload)
        except ValueError: pass
        else: raise AssertionError((target, payload))
    return {"passed": True, "checks": 9, "production_client_calls": 0,
            "purpose": "Independent oracle self-check, not product acceptance"}

def main():
    if sys.argv[1] == "--self-test":
        print(json.dumps(selftest(), indent=2)); return
    out = pathlib.Path(sys.argv[1]).resolve()
    out.mkdir(parents=True, exist_ok=False)
    stores = {s: {} for s in STORES}
    records = []
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"
        def log_message(self, *_): pass
        def capture(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            record = {"index": len(records) + 1, "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      "method": self.command, "target": self.path, "headers": dict(self.headers), "body": body.decode("utf-8")}
            records.append(record); self.record = record
            (out / ("request-%03d.body" % record["index"])).write_bytes(body)
            return body
        def send(self, status, payload=None, location=None):
            data = json.dumps(payload, separators=(",", ":")).encode() if payload is not None else b""
            headers = {"Content-Length": str(len(data))}
            if payload is not None: headers["Content-Type"] = "application/dicom+json"
            if location: headers["Location"] = location
            self.send_response(status)
            for k, v in headers.items(): self.send_header(k, v)
            self.end_headers(); self.wfile.write(data)
            self.record["response"] = {"status": status, "headers": headers, "body": data.decode()}
            (out / ("request-%03d.json" % self.record["index"])).write_text(json.dumps(self.record, indent=2) + "\n")
            (out / "state.json").write_text(json.dumps({"requests": len(records), "stores": stores}, indent=2) + "\n")
        def do_POST(self):
            raw = self.capture()
            try:
                if self.headers.get("Content-Type", "").split(";")[0] != "application/dicom+json":
                    raise ValueError("Create requires application/dicom+json")
                payload = json.loads(raw); surface, uid, form = resolve_identity(self.path, payload)
            except (ValueError, TypeError, UnicodeError) as error:
                self.send(400, {"error": str(error)}); return
            self.record.update(surface=surface, uid=uid, identity_form=form)
            if uid in stores[surface]:
                self.send(409, {"error": "Workitem UID already exists"}); return
            stored = copy.deepcopy(payload)
            stored["00080018"] = {"vr": "UI", "Value": [uid]}
            stores[surface][uid] = stored
            self.send(201, location=f"http://127.0.0.1:{self.server.server_port}/{surface}/dicom-web/workitems/{uid}")
        def do_GET(self):
            self.capture()
            parts = urllib.parse.urlsplit(self.path).path.split("/")
            if len(parts) != 5 or parts[1] not in stores or parts[2:4] != ["dicom-web", "workitems"] or not valid_uid(parts[4]):
                self.send(404); return
            surface, uid = parts[1], parts[4]
            self.record.update(surface=surface, uid=uid)
            if uid not in stores[surface]: self.send(404); return
            self.send(200, stores[surface][uid])
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    server.timeout = 0.2
    (out / "ready.json").write_text(json.dumps({
        "baseURLs": {s: f"http://127.0.0.1:{server.server_port}/{s}/dicom-web" for s in STORES},
        "port": server.server_port, "pid": __import__("os").getpid(), "self_test": selftest(),
        "limits": ["Identity/state/routing fixture only; not full UPS IOD conformance.",
                   "Synthetic Basic headers recorded; credentials are not enforced."]
    }, indent=2) + "\n")
    deadline = time.monotonic() + 3600
    while time.monotonic() < deadline and not (out / "stop").exists():
        server.handle_request()
    server.server_close()
    (out / "finished.json").write_text(json.dumps({"requests": len(records), "counts": {
        s: sum(r.get("surface") == s for r in records) for s in STORES}}, indent=2) + "\n")

if __name__ == "__main__": main()
