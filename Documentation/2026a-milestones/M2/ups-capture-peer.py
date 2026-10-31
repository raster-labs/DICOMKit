#!/usr/bin/env python3
"""Loopback-only UPS request capture fixture; not a DICOM conformance server.

Usage: python3 ups-capture-peer.py DIRECTORY
ready.json supplies the port. Put 'stop' in DIRECTORY to finish (600s maximum).
Stored raw HTTP bodies prove client behavior only; production server acceptance
is covered separately by UPSScheduledDateTimeTests.
"""
import http.server
import json
import pathlib
import sys
import time
import urllib.parse

directory = pathlib.Path(sys.argv[1]).resolve()
directory.mkdir(parents=True, exist_ok=True)
workitems = {}
counter = 0

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, code, payload=None, location=None):
        data = json.dumps(payload).encode() if payload is not None else b""
        self.send_response(code)
        self.send_header("Content-Length", str(len(data)))
        if payload is not None:
            self.send_header("Content-Type", "application/dicom+json")
        if location:
            self.send_header("Location", location)
        self.end_headers()
        self.wfile.write(data)

    def capture(self):
        global counter
        count = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(count)
        counter += 1
        stem = directory / f"request-{counter:03d}"
        stem.with_suffix(".body").write_bytes(body)
        stem.with_suffix(".json").write_text(json.dumps({
            "method": self.command, "path": self.path,
            "headers": dict(self.headers), "body": body.decode(errors="replace")
        }, indent=2))
        return body

    def do_POST(self):
        body = self.capture()
        try:
            value = json.loads(body)
            uid = value.get("00080018", {}).get("Value", [f"2.25.20261024{len(workitems)+1:03d}"])[0]
            value["00080018"] = {"vr": "UI", "Value": [uid]}
        except (ValueError, KeyError, IndexError, TypeError):
            self.send(400, {"error": "Synthetic capture fixture requires valid JSON"})
            return
        workitems[uid] = value
        self.send(201, location=f"http://127.0.0.1:{self.server.server_port}/dicom-web/workitems/{uid}")

    def do_GET(self):
        self.capture()
        path = urllib.parse.urlsplit(self.path).path.rstrip("/")
        if path.endswith("/workitems"):
            self.send(200, list(workitems.values()))
        else:
            uid = path.rsplit("/", 1)[-1]
            self.send(200, workitems[uid]) if uid in workitems else self.send(404)

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
server.timeout = 0.2
(directory / "ready.json").write_text(json.dumps({
    "baseURL": f"http://127.0.0.1:{server.server_port}/dicom-web",
    "purpose": "Capture CLI/packaged Workshop UPS client requests only"
}, indent=2))
deadline = time.monotonic() + 600
while time.monotonic() < deadline and not (directory / "stop").exists():
    server.handle_request()
server.server_close()
(directory / "finished.json").write_text(json.dumps({"requests": counter}))
