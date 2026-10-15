# DICOMKit v2.5.0

This release lets independently configured local allocation budgets participate in
one caller-owned aggregate budget. It adds optional thin C callbacks while
preserving the existing budget factories and codec behavior.

- Build strict parser options from scalar caps and syntax mask bits, and initialize
  JPEG/JPEG-LS decoders from finite syntax values without legacy String/Set setup.
- Include all three runtime resource bundles with the 36 CLI tools, preserve
  executable permissions through CI artifacts, and refuse incomplete release archives.
- Use portable annotation texture storage on Intel and Apple GPUs, with verified
  GPU completion and managed-texture synchronization in offscreen pixel tests.
- Observe accepted Print SCP connection readiness before starting transport.
- Admit the complete payload and control capacities before either mapping.
- Preserve exact aggregate refusal statuses and atomic resource transfers.
- Keep the same allocation token through aliases and transfers; copies receive
  distinct tokens.
- Release an aggregate token only after its backing mappings have retired, then
  release the context after the final ledger mapping is gone.
- Retain the complete aggregate charge and context when cleanup cannot safely
  finish.

The caller must admit callback storage, maintain the documented lock order and
honor token ownership. These hooks do not establish recoverable pthread/Swift
bootstrap, complete application allocation bounds, or provider/runtime acceptance.
See [the allocation contract](Documentation/BoundedInput/AllocationContract.md).

Codec revisions remain JLISwift v0.6.0
(`b6df774a3c3ecdf4b98971f31543fdd18074ace2`) and JLSwift v0.10.1
(`d17545284a23e93f3d884a18f1046c4e305daa35`).
