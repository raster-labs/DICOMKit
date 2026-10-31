# M0 reproduction and qualification preparation

## Audit repair verification

Use Python 3.9 or newer and the frozen official DICOM 2026a DocBook sources.
The scripts use the standard library; this milestone does not require a Swift
build. The committed baseline lists every standard URL and SHA-256.

```sh
python3 -m unittest discover -s Scripts -p 'test_*_audit_m0.py' -v
python3 Scripts/diff_cli.py --nema /absolute/path/to/2026a
python3 Scripts/diff_kit.py --nema /absolute/path/to/2026a
python3 Scripts/diff_studio.py --nema /absolute/path/to/2026a
```

Use a temporary output location to capture another baseline:

```sh
python3 Scripts/capture_milestone_baseline.py \
  --nema /absolute/path/to/2026a --out /tmp/dicomkit-m0-baseline.json
```

The optional `--cached-help /path/to/original/help-logs` imports existing
`help-results.json`, `recursive-help-results.json` and help-log hashes. It does
not execute binaries or claim they correspond to the source. The original
review recorded 41 root help invocations and 147 recursive paths with exit 0;
these are retained as historical cached-binary evidence. The 504 earlier
passing tests likewise do not replace fresh-source or packaged-app checks.

An audit can finish normally while reporting product failures. Preserve its
nonzero result and finding detail. An exception is an audit error, not a
successful exclusion. `items.json` retains the 38 known bug-fix actions even
when a narrower literal or contract audit reports zero failures.

## Synthetic fixture preparation

`Scripts/audit_fixtures/m0/fixtures.json` contains 14 small, synthetic Part 10
inputs as hexadecimal bytes with SHA-256 and purpose. These isolate encoding,
metadata or validation behavior; they are not complete clinical IOD datasets.
They can be materialized without running a DICOM operation:

```python
import hashlib, json
from pathlib import Path
manifest = json.loads(Path('Scripts/audit_fixtures/m0/fixtures.json').read_text())
out = Path('/tmp/dicomkit-m0-fixtures')
out.mkdir(exist_ok=True)
for fixture in manifest['fixtures']:
    data = bytes.fromhex(fixture['bytes_hex'])
    assert hashlib.sha256(data).hexdigest() == fixture['sha256']
    (out / fixture['name']).write_bytes(data)
```

## Build and packaged app identity for later milestones

Record the final source commit, dependency lockfiles, actual Xcode/Swift
versions and selected SDK, build command/settings, executable hashes and app
bundle identity. The baseline records **declared** Package/Xcode settings and
their file hashes; these are not resolved build results.

The app target and shared Xcode scheme are `DICOMStudio` in
`DICOMStudio.xcodeproj`; its application entry point is in
`Sources/DICOMStudioApp`. Build that scheme from the accepted source, retain
the build result and app hash, then launch the resulting `DICOMStudio.app`
in an available desktop session. In CLI Workshop, exercise the exact affected
tool, subcommand, visible settings, preview, execution, errors, output and
cancellation against the same synthetic fixtures used by CLI. Record the
actual app actions and outcomes. A view-model test or source scan does not
substitute for this packaged-app gate.

Use the repository's current test/build procedures and match `--skip-build`
only to artifacts built from the same source and settings. Inspect test
discovery; a zero-test XCTest bundle does not establish Swift Testing coverage.
M0 does not launch the app or run the broad Swift/product suite.

## Independent peers and environment gates for M7

| Area | Resource to prepare | Evidence required later |
|---|---|---|
| Query and retrieve | Independent DIMSE SCP/SCU and DICOMweb endpoint with documented capabilities | Expected matching sets, captured keys/status, cancellation and restart results |
| UPS and MPPS | Peer supporting the claimed service roles | Independently decoded timestamps and per-instance SOP references |
| Print SCU and SCP | Independent Print Management peer for each claimed direction | Negotiation, relevant DIMSE operations, output/status and cleanup |
| Physical print | Target film printer or OS paper queue plus actual output device | Device completion and measured/observed output; simulator output is separate |
| Codecs and TLS | Independent decoders/encoders, retained TLS profiles and supported platforms | Decoded expected values and actual runtime negotiation |
| Packaged Studio | Built app, unlocked desktop, permissions and writable temporary output | Real CLI Workshop actions, not just tests or source inspection |

Record peer/version/conformance statements and platform availability before
the later qualification campaign. None of these external or physical gates
has been executed in M0. An unavailable resource remains Blocked/Not run;
successful local self-pair tests cannot waive independent interoperability.
