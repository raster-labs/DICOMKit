# DICOMKit v2.6.0

This release adds strict allocation-bounded conversion of a borrowed DICOM Decimal
String component through `DICOMDecimalString.parseScalar`.

- Return a nonthrowing scalar status and finite `Double` without retaining input.
- Enforce at most 16 raw bytes including ASCII-space padding; reject multiple
  values, embedded whitespace, control bytes, hexadecimal syntax and malformed
  exponents.
- Round the exact decimal value once to nearest-even binary64. Subnormals and
  signed-zero underflow succeed; overflow is reported explicitly.
- Preserve the existing String compatibility APIs, deployment targets and codec
  dependency revisions.
- Build the renderer resource-owning target during CLI staging so all three
  required runtime bundles are present on a clean release runner.

The conversion uses fixed inline stack scratch. The caller must admit the full
stack mapping and keep the borrowed bytes alive during the call. Library and
isolated integration evidence do not establish complete worker/bootstrap or
application acceptance. See the [scalar qualification](Documentation/BoundedInput/DecimalScalarQualification.md).

The standard macOS arm64 CLI archive contains 36 tools and three resource bundles.
Optional DocC generation remains subject to the existing missing-plugin limitation.
