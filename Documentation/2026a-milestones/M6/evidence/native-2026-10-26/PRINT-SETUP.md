# Native print preparation — 26 October 2026

Preparation only: no UI, peer, DICOMKit command, build or VM campaign was executed.

`print-setup-inventory.json` contains exact imports for all six Print and four Print SCP commands, expected outcomes, CLI controls and root-only peer launches. Thirteen copied synthetic files are hashed in `print-fixture-manifest.json`. Source fixtures are unchanged. Do not rerun the preparation script after collecting native evidence; it initializes the isolated CLI registry and writable config copies.

## Suggested order

1. Check final app/CLI identities and the displayed settings location. The signed app's DEBUG override is in its container cache; it has **not** been redirected to this folder. For registry parity, run CLI list against that exact path, and replay mutations only in the separate `cli-settings` directory. Do not change HOME or the bundle.
2. Add the literal synthetic profile, list JSON/text, verify duplicate rejection, relaunch and list again, then remove and confirm missing-name rejection. This closes four native command routes and persistence without touching Print Center profiles.
3. Start the CLI receiver from the inventory (suggested loopback port 21113; root checks availability). Native Print status/send/job then uses that actual peer. Obtain a current Print Job UID after a real send; never reuse the historical captured UID. Exercise native Browse, Copy/Import, ordered literal rows and the focused send variants. Capture outputs/counters for parity.
4. Native Print SCP status uses `config/baseline-scp.json`: color and annotation switches are false, LUT true, DPI36/max1024. Inspect inherit, enabled and disabled. Save into `saved-scp.json` and reload. Queues enumerates only; paper queue without Allow Paper must refuse.
5. Simulate the exact multi-output command: last image format TIFF plus PDF, no PNG. Compare TIFF pixels with a CLI replay to `cli-simulated`; PDF scope is complete container only. Save-before-gather uses a missing input. `sink-failure/native-001.png` is deliberately a directory to cause an emit failure; `sink-is-file` causes a distinct output-directory/startup error. Open must follow a successful saved file.
6. Native SCP Start on suggested 21114, observe actual port, send CLI gray/color, then Stop and rebind/restart. Cover max-films, duration, collision without harming the incumbent, leaving Workshop, and app termination. Use fresh output folders for independently asserted single-film runs.
7. Independent helpers reuse the frozen oracle: `native_print_peer.py serve` captures native SCU requests and offers normal, status warning/failure, N-SET failure, B604, absent LUT and job-event modes. `send-color` and `send-gray` target the **already running native SCP** and never start it. Root launches every process. The new wrapper is syntax-checked only; its execution is not preclaimed.

## UI and oracle details

Import clears security grants: **Browse after Import** for files/config/output folders. Multi-file Browse replaces the ordered list; edits and Add/Remove preserve literal rows. Advanced fields expose inherit/enabled/disabled with omitted/positive/negative flags. Start disables command controls; Stop remains available and user cancellation records130. The bound-port label is authoritative.

The independent SCP is intentionally one image box per film. Use `peer-*` 16×16 fixtures, `--raw --layout 1x1 --film-size 8x10`, called AE PYM6, and **omit --verify** (no C-ECHO context). Use the full CLI receiver for multicell/frame fixtures. For independent sends into native SCP, called AE is DCMKIT_M6; color mode must enable Push Job Events for the terminal ACK/deletion test. Output folders must initially be empty.

`inspect_print_files.py` reads files only and compares decoded RGBA content/dimensions. Qualified image references are in the inventory; fresh equivalent CLI output is the primary comparison if any dynamic annotation changes. Native/RLE/JPEG must agree, three ordered files must equal all three frames, and selected frame2 must equal its separate fixture while differing from frame1. No PDF raster, physical paper, calibration or clinical claim is implied.
