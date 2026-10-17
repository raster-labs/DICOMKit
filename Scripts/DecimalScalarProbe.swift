// Test-only C entry point. Link against the actual optimized DICOMCore objects.
import DICOMCore

@_cdecl("dicom_decimal_scalar_probe")
public func decimalScalarProbe(_ input: UnsafeRawPointer?, _ count: Int,
                               _ bits: UnsafeMutablePointer<UInt64>) -> UInt8 {
    let result = DICOMDecimalString.parseScalar(.init(start: input, count: count))
    bits.pointee = result.value.bitPattern
    return result.status.rawValue
}
