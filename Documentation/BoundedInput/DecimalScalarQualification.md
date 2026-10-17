# Strict borrowed DS conversion

`DICOMDecimalString.parseScalar(_ bytes: UnsafeRawBufferPointer)` converts one
borrowed component synchronously. `DICOMDecimalScalarOutcome` contains only a
`Status` and `Double`; it retains neither input nor scratch. Check `.success`
before using `value`. Failure values are positive zero. Statuses distinguish
empty/padding-only input, excessive length, invalid syntax and overflow.

The raw component may contain at most **16 bytes including padding**. Only outer
ASCII spaces are trimmed. The grammar is
`[+-]?(digits[.]digits?|[.]digits)([eE][+-]?digits)?`. There must be a mantissa
digit and, when present, an exponent digit. Backslashes, multiple values,
embedded whitespace, non-ASCII, NUL/control bytes, hexadecimal forms, NaN and
infinity are rejected. Length takes precedence over all other errors. Empty
components are not numbers. These rules follow the DS row and individual-value
length rule in [DICOM PS3.5 section 6.2](https://dicom.nema.org/medical/dicom/current/output/chtml/part05/sect_6.2.html).

The existing String and multi-value compatibility APIs are unchanged, including
their documented leniency. Callers requiring strict source metadata use this
new entry point and decide the semantic policy separately: for example, parsing
a zero slope successfully does not establish that it is valid rescale metadata.

## Exact numerical contract

Conversion rounds the exact base-10 value to IEEE binary64 using nearest with
ties to even. It does not perform floating-point arithmetic or call a platform
decimal converter. Rounding is therefore independent of the floating-point
rounding mode. Subnormals succeed. Underflow succeeds with correctly signed
zero; negative decimal zero preserves its sign, even with extreme exponents.
A result that rounds to infinity returns `.overflow`.

Up to 16 decimal digits fit in a UInt64 coefficient (`N < 10^16 < 2^54`). The
parser validates the entire component before taking range shortcuts. Exponents
saturate at magnitude 400; subtracting at most 16 fractional digits cannot move
a saturated exponent back into the finite nonzero range. A nonzero coefficient
with exponent greater than 308 overflows. With exponent at most -340, its value
is below half the least subnormal. The remaining exact path has decimal exponent
in [-339, 308].

Numerator and denominator use fixed, homogeneous 20-word UInt64 tuples (1280
bits), preserving the library's existing deployment targets. Multiplication by
10, shifts, comparison and subtraction operate only on that inline storage.
`10^339` requires 1127 bits; the largest divisor trial (`10^339 << 52`) needs
1179. The numerator scaled for subnormal rounding needs at most 1128 bits.
Positive-exponent construction, exponent alignment and doubled remainders also
fit within 1280 bits. No dynamic collection, recursion or lazy table is used.

Integer comparisons determine the binary exponent. A bounded 53-step division
produces the significand and remainder at the normal/subnormal unit. Comparing
twice the remainder with the divisor performs one final rounding, including
significand carry, the subnormal/normal transition and overflow. Debug assertions
check the fixed-capacity arithmetic invariants.

## Reproducible qualification

Run the focused compatibility and strict tests, then build the stable target:

```sh
swift test --test-product DICOMCoreTests --filter 'DecimalScalarTests|DICOMDecimalStringTests'
swift build -c release --target DICOMCore
bash Scripts/probe_decimal_scalar.sh work/strict-borrowed-ds
```

The macOS arm64 probe links the **actual package Release object** for the scalar
entry point, plus a test-only C-callable Swift wrapper. The direct
call audit includes the wrapper and every reachable helper and fails on unknown
or indirect calls. Its only permitted external terminal guard is
`__stack_chk_fail` for stack corruption. Thus no normal path can invoke Swift
allocation, metadata initialization, reference counting or a platform converter.

The numerical oracle uses Python Decimal only to obtain an exact integer ratio,
then independently binary-searches IEEE values and compares integer midpoints.
It covers 16-digit tie directions, underflow neighbors, the normal boundary,
overflow neighbors, a full exponent sweep, deterministic random decimals and
arbitrary bytes. Every corpus case runs under four floating-point rounding modes.

Fresh subprocesses exercise first-call success and rejection paths, followed by
hot calls. An armed interposer counts malloc/calloc/realloc, aligned and zone
allocation entry points, and mmap; positive malloc/mmap controls must fire.
Counters are armed only around the actual Swift-wrapper call, after process
loading and preparation of the borrowed bytes. The static closure audit is
required alongside these measurements, including to exclude Swift allocator
paths that could otherwise reuse existing runtime storage invisibly to malloc.

This evidence qualifies conversion on the recorded toolchain and architecture.
It does **not** admit process loading, Swift runtime initialization, a worker or
the caller's stack mapping. The fixed scratch and compiler frames live on that
already admitted stack and expire before return; no separate token survives.
The caller must preserve the borrowed bytes during the call and account for its
entire stack mapping through its existing final-owner contract. Source-backed
Mayam metadata semantics, integration and worker/bootstrap acceptance remain
separate application-owner gates.

## Qualified snapshot

The local arm64 qualification used Apple Swift 6.4
(`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`) and the macOS 27 SDK:

- 36 focused strict/compatibility tests passed; the optimized DICOMCore target built.
- 13,489 independent oracle cases passed in four verified rounding modes
  (53,956 calls).
- 27 fresh processes each performed 400 cold/hot calls (10,800 calls).
- All measured conversion calls had zero allocation and mapping events; positive
  controls observed both allocation and mmap.
- The optimized wrapper/conversion closure contained seven functions, no unknown
  or indirect control-flow edges, and only terminal stack-corruption guards.
- The parser frame was 1,872 bytes; its largest helper frame was 192 bytes.
  The maximum known call path, including the 32-byte test wrapper, was 2,096 bytes.
  This emitted frame size is evidence for this artifact, not a stable API promise
  or a replacement for admitting the caller's complete stack mapping.

Sanitized source/object/toolchain and receipt hashes are in
`DecimalScalarQualificationReceipt.json`. Detailed local logs and disassembly are
under `work/strict-borrowed-ds/`. The probe script assumes the preceding build is
current; its standalone invocation does not establish object freshness. Rebuild
and requalify after changing source, toolchain, optimization or architecture.
