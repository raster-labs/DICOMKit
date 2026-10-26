# M7 checkpoint reproduction and portability

The 24 October recipes and c900 source checkpoint remain historical under [the archive](evidence/historical-checkpoint-c9001dd/Documentation/2026a-milestones/M7/REPRODUCE.md). Current source/artifact identities and the verified full-product selection and execution results are in [checkpoint input](evidence/checkpoint-update-input.json). All paths in preserved raw logs remain byte-exact; [portable mappings](evidence/checkpoint-portable-index.json) map original workspace locations to repository evidence.

Run the complete DICOMWeb product through the current Scripts/verify_m7.sh gate; a focused UPS-only run does not replace it. Validate the supplied source manifest against actual files, the real CLI/app/test hashes against their recorded build locations, and the signing/entitlement evidence. The source-equivalence receipt limits reuse of earlier native observations. The failed complete runs remain visible.

The strict UPS peer and replay/oracle scripts are in evidence/ups-identity-repair. They use isolated synthetic fixtures and explicit loopback ports; inspect the preserved run card and original workspace mappings before execution. The bundled scripts retain original execution locations and are not falsely claimed drop-in runnable from the export directory.

The new native network receipts are in evidence/native-final-network; sanitized UI observations are in evidence/native-2026-10-26/ui-network. The three supplementary previews are not executed requests. Original UPS parity success is explicitly superseded as a standard-identity claim; only the repaired CLI strict-peer route is currently qualified. Actual repaired native UPS remains pending.

M6 native PDF proof compares full-page raster and embedded film image/companion bytes. The older VM campaign validated PDF container semantics only; those are distinct epochs. Raw external logs and AX captures intentionally retain their whitespace.

Before publication, verify every evidence hash, all 68 item IDs (45 completed/1 in progress/22 deferred), 27 native Passed plus one Partial, and exact pushed-head CI. Preserve exclusions and optional/conditional unexecuted cases. No main merge is authorized.
