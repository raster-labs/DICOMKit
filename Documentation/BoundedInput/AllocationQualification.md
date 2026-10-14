# DICOMKit 2.4.0 allocation qualification

This record covers the strict bounded parser and selected managed JPEG/JPEG-LS
paths. The allocation contract defines the caller obligations and exclusions;
Mayam provider and native-presentation acceptance are separate.

## Compiled ownership boundary

The qualified parser requires immutable strict/full options, a verified byte source,
and nonnil mapped capture storage. It uses the same grammar as legacy parsing.
Concrete internal dataset, element, sequence-item and collection outcomes remove
cold generic result-destroy metadata from the selected path. Owned Array/Set/
Dictionary alternatives remain in the canonical parser but are excluded by capture
or empty-count branches; source-backed input refuses legacy materialization.
Empty compatibility values retain nil or immortal singleton references. Static
concrete copy/destroy witnesses do not request generic metadata.

The Core source closure contains mapped ledger/payload/control owners, explicit
sharing and transfer, execution reservation, scalar failure transport and codec
adapters. Payload/control unmapping and ledger debit precede final retirement
notification. The ledger remains pinned during the callback; no callback-context
access follows notification. Failed unmap retains its charge and emits no retirement.

The compiled-call review follows direct branches and defined function addresses,
including optimized closure thunks. Unfiltered legacy alternatives are retained in
its evidence rather than silently removed. Callback targets are a separately
qualified caller boundary. The complete reported worker stack and control mapping
are admitted, including fixed stack probes; no stack-size estimate substitutes for
that ownership. Cancellation is cooperative; forced pthread exit is excluded.

## Compiler and runtime conditions

The selected codegen profile is optimized Swift 6.4, Swift language mode 6,
arm64-apple-macos15.0, with the recorded macOS 27.0.1 (26A434) runtime. Runtime
inspection resolves Swift ARC, empty singleton, copy/fill, math, once, stack-probe,
POSIX and errno implementations. Qualification requires normal default runtime
behavior without external error/syscall/compatibility instrumentation. Read-only
inspection does not make mutable runtime hooks immutable.

Recorded runtime image UUIDs:

| Image | UUID |
| --- | --- |
| Swift Core | C9B36DA7-BB34-35AF-BC5D-91ECBCAA9ED0 |
| Swift Darwin | B4F37828-524C-32F7-94FD-63CB8177AEEC |
| Darwin Foundation errno overlay | 8C802776-95AE-3ED7-BF1C-D9EB9A7DB358 |
| Kernel wrappers | F63BF418-8F75-34A4-AAF1-8CAF2B9B6A05 |
| pthread and stack probe | 5A1828C3-CBC2-3B85-BD07-C8ED10021A41 |
| Scalar math | A3FB340F-3ED5-30F4-8B64-9D5860F64D35 |
| Memory copy/fill | 080E4444-A0FB-3913-9756-4E470015F32F |
| Dispatch once | 022BF08F-0B3A-3225-9E65-16D1553CE90D |

JLSwift 0.10.1 and JLISwift 0.6.0 have their own source and selected-path receipts.
Their package APIs do not establish a complete application memory bound. Other
codec families retain their existing behavior and are outside this new profile.

## Validation results

The final parser split keeps temporary header, delimiter and raw-value work outside
recursive descent. The strict depth cap remains 32. Four explicit/implicit and
defined/undefined sequence combinations accept depth 32 and reject adversarial
depth 1,000 at the existing cap on the test worker's actual stack. All 873 DICOMKit
Swift Testing tests passed.

Fresh optimized SIL and assembly cover 30 selected roots, 220 reachable symbols
and 138 emitted bodies with no missing roots. Compared with the earlier reviewed
module, 127 bodies remain equivalent after label/helper-alias normalization and
17 referenced constant-pool pairs match. Three changed callers and eight newly
emitted helpers were reviewed for the sequence split. The same 17 allocation or
generic-metadata finding functions remain excluded legacy branches. The only new
runtime callee, `swift_bridgeObjectRelease_n`, operates on the immortal empty
sequence-array singleton under the recorded normal ARC profile. The 118 unchanged
Core source files retain their 33-root, 43-body review.

Local released-pin validation completed:

- 9,373 Swift Testing tests in 935 suites across the full run and an unchanged-source
  repeat of the entire 5,354-test Studio target. The initial Studio ARTIM timeout
  remains recorded; this is not described as a clean single full run.
- 6,048 XCTest entries, with 44 existing skips and no XCTest failures.
- One additional optimized sparse-source test over five sizes around 128/256 MiB;
  the over-limit refusal is covered separately. Total unique Swift Testing tests: 9,374.
- Optimized warnings-as-errors Release, forced-CPU rendering tests, and iOS simulator
  module build passed.
- Renewed linked probe: four exact independent JPEG-LS oracles, baseline RGB
  released-codec parity and independent tolerance, complete arena accounting,
  retained alias ownership and final ledger baseline.
- The maintained 5,326-entry primary-VR projection verifies. The tag audit has zero
  blockers, major findings or warnings. Bounded CLI receipt/refusal smoke checks pass.

Current release support and qualification are limited to iOS 18+ and macOS 15+.
Linux, tvOS and visionOS are outside this release scope.

Linux remains blocked by the existing Apple-only JLISwift Accelerate dependency,
as already documented on main before this release. Hosted Linux CI reproduced
that limitation; it is retained as a failure, not represented as passing.
The committed root lockfile preserves the exact locally qualified transitive pins.

visionOS is not qualified by this release: the existing J2KSwift 11.0.3 dependency
specifies visionOS 1 while using Mutex from visionOS 2. Hosted platform and DocC
jobs may report setup limitations; a green wrapper job is not platform proof.
Final Mayam provider, runtime/callback and native-presentation admission remains
separate. `AllocationSources.json` records source and generated-code hashes;
`LocalSourceClosure.json` records immutable released codec pins.

Hosted OCR environment: macOS 27 failed the same standalone Vision revision-3
requests with default and CPU devices, grayscale and RGB images, and both native
and VN APIs. All sixteen matching device/API/format probes passed on macOS 26.6.2;
eight default-device probes also passed on macOS 15.7.9. Required OCR/full-suite CI
uses stable macOS 26 with the Swift 6.4 release toolchain;
this infrastructure change does not alter the recorded allocation compiler/runtime
profile or the product OCR implementation.
