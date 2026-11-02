# Remaining native print checks

Snapshot: 26 October, after granted tri-state captures and post-repair SCP CLI controls. **Do not rerun completed image/peer campaigns.** Root owns all actions below. This card does not mark any group complete.

## Already established — retain, do not repeat

- Ten native sends plus exact CLI controls, all image pairs, actual job JSON, dry-run, independent gray/color/LUT/annotations, warning/failure/B604/event/cleanup: preserved source-equivalent evidence.
- SCP simulation TIFF+PDF, failed individual file sink, native Preview Open, save-before-gather, receiver gray/color, Stop/restart/duration/max-films, collision/incumbent survival, leaving Workshop, app termination/rebind, independent gray/color and event ACK: preserved evidence.
- Nine rebuilt SCP CLI controls: `scp-native-verification-post-repair.json`, 64 checks passed. Custom paper-gate error exits1, with explicit source-backed oracle correction retained.
- Repaired app registry persistence, removal, missing removal, empty JSON and text guidance now have complete copied-console evidence. `repaired-print-controls-review.json` verifies these and the granted tri-state trio:17 checks passed. No need to repeat registry mutations.
- Granted verbose SCP inherit = entire baseline; enabled differs **only** `supportsColor:true`; disabled = entire baseline. Radio selections and copied argv agree. Earlier ungranted status returning DICOMKIT-PRINTER is a default fallback observation, not a passing config read. Keep both captures.

## 1. Final checkbox-layout repair: two bounded routes

After network agent's layout repair is built/signed, record its source/app hashes and launch the exact final bundle. The existing native print protocol/output evidence stays tied to its prior identity plus an explicit unchanged-command/service justification.

**Print → send:** inspect long labels at the current narrow/expanded layouts and Beginner/advanced disclosure. Native AX must name each checkbox. Click one safe flag and use Space to reverse it; Copy command must change only that flag. Execute a no-peer dry-run after final file Browse:

```text
dicom-print send pacs://127.0.0.1:1 /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --aet M7NATIVE --raw --dry-run --verbose --format text
```

Record readable form/AX, actual flag transitions, copied command and dry-run result. No network or new film is required for this control-only repair.

**Print SCP → serve:** one short run is enough to observe final form disabled during execution and re-enabled after Stop. Use outputnone and the prepared absent-config path, so no file or peer rerun is needed:

```text
dicom-printscp serve --port 21114 --ae-title DCMKIT_M6 --output none --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --duration 30 --format json
```

Check named checkbox AX disabled while running, Stop remains available, and controls re-enable after Stop. Capture bound port and cancelled status. Prior lifecycle tests need no repetition. Tri-state is a separate segmented picker and already has full effective-settings proof; only repeat if its implementation changes in the final repair.

## 2. Distinct output-path failure / missing-folder behavior

The existing `sink-failure/native-001.png` directory proves an individual sink-write failure; it does **not** prove inability to access/create the selected output directory. Add one deliberately unwritable synthetic output folder under this task (root can create it with owner read/execute only and restore permission afterward). Do not use protected user folders or physical queues. Import the command below with its path substituted, Browse the input, retain output-folder grant separately, and run. Require an explicit failure and no Wrote/successful-save claim; preserve output folder state and equivalent CLI result. No film-network peer needed.

```text
dicom-printscp simulate /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/print-fixtures/gray8.dcm --config /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/config/absent.json --dpi 36 --max-pixels 1024 --output png --output-dir /Users/raster/Documents/Codex/2026-10-24/we-have-a-project-in-users-3/work/m7/native-2026-10-26/denied-output --name-pattern 'denied-{index}' --format json
```

An existing regular-file-as-directory control is also available at `.../native-2026-10-26/sink-is-file`; it should fail directory preparation. It may replace a redundant missing/invalid-path negative, but does not establish a filesystem permission denial by itself.

A genuinely **missing writable folder** is expected to be created by `PrintSCPService.makeFilmHandler` (`createDirectory(...withIntermediateDirectories:true)`), not rejected merely for absence. If root includes this case, Browse its existing synthetic parent, then use a new child path and verify creation + actual saved image. Use `--name-pattern 'created-{timestamp}-{index}'` to cover timestamp plus index without another simulation. Compare decoded pixels with the matching CLI control; do not compare timestamp-bearing filenames literally.

Import clears grants. After final Import, Browse every required input/config/output again. Granting input alone does not prove access to an unrelated config or output folder.

## 3. Small remaining evidence gaps in explicit checklist language

These are targeted additions, not a full rerun. Skip only if a complete saved capture already exists elsewhere and is linked into the ledger.

| Gap | Minimal distinct action | Evidence/limit |
|---|---|---|
| SCU `status` **text** | Once against an existing bounded controlled peer, change format to text, Run, Copy full console. | `ui/print-status-text.txt` is only a no-change AX response. JSON is already qualified. Compare complete text with the corresponding CLI control. |
| SCU `job` **text** | Query an actual still-retained UID using text and retain full console. | Existing announced and unknown job JSON results remain valid. Do not reuse a UID from a stopped receiver. Can use the same single final send described below. |
| Actual repeatable-row reordering | If no saved row-edit capture exists, manually change two existing path rows and annotation rows into reversed order, Copy then send once to the bounded CLI receiver. | Existing three-files submission proves input ordering but does not itself prove an actual UI reorder/edit operation. No drag control is required: edit existing rows or remove/re-add in the new order. Compare exact argv and resulting film with CLI; this one send supplies the retained job for text above. |
| AE rejection in actual packaged route | In the same final bounded SCP serve run, set `--allow-ae M7ALLOWED`. Root's CLI status with `--aet M7DENIED` must refuse; allowed caller must succeed. | M6.3 explicitly names AE rejection. Reuse automated protocol detail, capture one native listener result/counters; no print action needed. This can combine with repaired controls disabled/Stop above. |

For the optional combined final send/control, all prior image/codec permutations remain covered. Use just two existing synthetic frames, a 2×1 layout, and two literal annotation rows; reverse them through the form, retain the actual final copied argv, and replay only that vector. Do not infer ordering from a screenshot alone.

## Scope and evidence status

Physical printing remains outside qualification; keep that explicit. PDF checks so far prove complete containers, not rendered page equality. Deep option aliases/default combinations and unchanged parser/protocol negatives are already covered by automated/VM/independent evidence and do not require native repetition. Remaining native work is final repaired-control usability/execution, the distinct output-directory access case, and the small explicit evidence gaps above. `native-results.json` is updated only by its assigned owner.
