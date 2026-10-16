/// The result of strict conversion of one borrowed DICOM DS value.
///
/// This scalar contains no retained input, reference storage or error allocation.
public struct DICOMDecimalScalarOutcome: Sendable {
    public enum Status: UInt8, Sendable {
        case success
        case empty
        case tooLong
        case invalidSyntax
        case overflow
    }

    public let status: Status
    /// Valid only when `status == .success`; zero otherwise.
    public let value: Double

    fileprivate init(_ status: Status, bits: UInt64 = 0) {
        self.status = status
        self.value = Double(bitPattern: bits)
    }
}

extension DICOMDecimalString {
    /// Converts one strict DS component without allocating or retaining its bytes.
    ///
    /// The entire buffer, including leading/trailing ASCII spaces, must contain
    /// at most 16 bytes. The grammar is `[+-]?(digits[.]digits?|[.]digits)` with
    /// an optional `[eE][+-]?digits` exponent. Only outer ASCII spaces are allowed;
    /// backslash-separated values, other whitespace and nondecimal syntax fail.
    /// Empty/padding-only input reports `.empty`. Length is checked first.
    ///
    /// Conversion rounds the exact decimal value to binary64, nearest with ties
    /// to even, independently of the floating-point rounding mode. Subnormal
    /// values and underflow to signed zero succeed; infinity reports `.overflow`.
    /// Scratch is fixed inline storage on the caller's stack, which must already
    /// be admitted by the caller's execution/lifetime contract. See
    /// `Documentation/BoundedInput/DecimalScalarQualification.md` for bounds and
    /// the qualified toolchain; this API does not admit a thread or Swift runtime.
    ///
    /// The existing String compatibility parser is intentionally unchanged.
    public static func parseScalar(_ bytes: UnsafeRawBufferPointer) -> DICOMDecimalScalarOutcome {
        guard bytes.count <= 16 else { return .init(.tooLong) }
        var start = 0
        var end = bytes.count
        while start < end && bytes[start] == 0x20 { start += 1 }
        while start < end && bytes[end - 1] == 0x20 { end -= 1 }
        guard start < end else { return .init(.empty) }

        var index = start
        var sign: UInt64 = 0
        if bytes[index] == 0x2D || bytes[index] == 0x2B {
            if bytes[index] == 0x2D { sign = 1 << 63 }
            index += 1
        }
        var coefficient: UInt64 = 0
        var digits = 0
        var fractionDigits = 0
        var hasPoint = false
        while index < end {
            let byte = bytes[index]
            if byte >= 0x30 && byte <= 0x39 {
                coefficient = coefficient * 10 + UInt64(byte - 0x30)
                digits += 1
                if hasPoint { fractionDigits += 1 }
            } else if byte == 0x2E && !hasPoint {
                hasPoint = true
            } else {
                break
            }
            index += 1
        }
        guard digits > 0 else { return .init(.invalidSyntax) }

        var exponent = 0
        if index < end && (bytes[index] == 0x45 || bytes[index] == 0x65) {
            index += 1
            var negativeExponent = false
            if index < end && (bytes[index] == 0x2D || bytes[index] == 0x2B) {
                negativeExponent = bytes[index] == 0x2D
                index += 1
            }
            let exponentStart = index
            while index < end && bytes[index] >= 0x30 && bytes[index] <= 0x39 {
                // Saturation cannot affect a finite nonzero result: even after
                // all 16 possible fractional digits, +/-400 is out of range.
                exponent = min(400, exponent * 10 + Int(bytes[index] - 0x30))
                index += 1
            }
            guard index > exponentStart else { return .init(.invalidSyntax) }
            if negativeExponent { exponent = -exponent }
        }
        guard index == end else { return .init(.invalidSyntax) }
        if coefficient == 0 { return .init(.success, bits: sign) }
        exponent -= fractionDigits
        if exponent > 308 { return .init(.overflow) }
        // coefficient < 10^16, so this is below half the least subnormal.
        if exponent <= -340 { return .init(.success, bits: sign) }

        var numerator = DecimalScalarMagnitude(coefficient)
        var denominator = DecimalScalarMagnitude(1)
        if exponent >= 0 {
            for _ in 0..<exponent { numerator.multiplyByTen() }
        } else {
            for _ in 0..<(-exponent) { denominator.multiplyByTen() }
        }

        var binaryExponent = numerator.bitWidth - denominator.bitWidth
        var trial: DecimalScalarMagnitude
        if binaryExponent >= 0 {
            trial = denominator
            trial.shiftLeft(binaryExponent)
            if numerator.compare(trial) < 0 { binaryExponent -= 1 }
        } else {
            trial = numerator
            trial.shiftLeft(-binaryExponent)
            if trial.compare(denominator) < 0 { binaryExponent -= 1 }
        }
        if binaryExponent > 1023 { return .init(.overflow) }
        if binaryExponent < -1075 { return .init(.success, bits: sign) }

        let unitExponent = max(binaryExponent, -1022) - 52
        if unitExponent >= 0 {
            denominator.shiftLeft(unitExponent)
        } else {
            numerator.shiftLeft(-unitExponent)
        }
        trial = denominator
        trial.shiftLeft(52)
        var significand: UInt64 = 0
        for bit in stride(from: 52, through: 0, by: -1) {
            if numerator.compare(trial) >= 0 {
                numerator.subtract(trial)
                significand |= UInt64(1) << bit
            }
            trial.shiftRightOne()
        }
        // numerator now contains the exact remainder.
        numerator.shiftLeft(1)
        let midpoint = numerator.compare(denominator)
        if midpoint > 0 || (midpoint == 0 && significand & 1 != 0) {
            significand += 1
        }
        if binaryExponent < -1022 {
            // Also covers rounding up to the least normal (bit 52 becomes 1).
            return .init(.success, bits: sign | significand)
        }
        if significand == UInt64(1) << 53 {
            significand >>= 1
            binaryExponent += 1
            if binaryExponent > 1023 { return .init(.overflow) }
        }
        let bits = sign | (UInt64(binaryExponent + 1023) << 52)
            | (significand - (UInt64(1) << 52))
        return .init(.success, bits: bits)
    }
}

/// Fixed 1280-bit scratch, never a heap-backed collection. The largest temporary
/// is (10^339 << 52), requiring 1179 bits; see the qualification document.
private struct DecimalScalarMagnitude {
    private var words = DecimalScalarWords()

    init(_ value: UInt64) { words[0] = value }

    var bitWidth: Int {
        for index in stride(from: 19, through: 0, by: -1) {
            if words[index] != 0 {
                return index * 64 + 64 - words[index].leadingZeroBitCount
            }
        }
        return 0
    }

    mutating func multiplyByTen() {
        var carry: UInt64 = 0
        for index in 0..<20 {
            let product = words[index].multipliedFullWidth(by: 10)
            let (low, overflow) = product.low.addingReportingOverflow(carry)
            words[index] = low
            carry = product.high + (overflow ? 1 : 0)
        }
        assert(carry == 0)
    }

    mutating func shiftLeft(_ amount: Int) {
        assert(amount >= 0 && bitWidth + amount <= 1280)
        let whole = amount / 64
        let part = amount % 64
        for destination in stride(from: 19, through: 0, by: -1) {
            let source = destination - whole
            var word: UInt64 = 0
            if source >= 0 {
                word = words[source] << part
                if part != 0 && source > 0 { word |= words[source - 1] >> (64 - part) }
            }
            words[destination] = word
        }
    }

    mutating func shiftRightOne() {
        for index in 0..<19 {
            words[index] = (words[index] >> 1) | (words[index + 1] << 63)
        }
        words[19] >>= 1
    }

    func compare(_ other: borrowing Self) -> Int {
        for index in stride(from: 19, through: 0, by: -1) {
            if words[index] < other.words[index] { return -1 }
            if words[index] > other.words[index] { return 1 }
        }
        return 0
    }

    mutating func subtract(_ other: borrowing Self) {
        var borrow: UInt64 = 0
        for index in 0..<20 {
            let (difference, firstBorrow) = words[index].subtractingReportingOverflow(other.words[index])
            let (result, secondBorrow) = difference.subtractingReportingOverflow(borrow)
            words[index] = result
            borrow = (firstBorrow || secondBorrow) ? 1 : 0
        }
        assert(borrow == 0)
    }
}

/// A homogeneous tuple keeps inline storage available at the library's existing
/// deployment targets. Swift InlineArray would require newer operating systems.
private struct DecimalScalarWords {
    private var storage: (UInt64, UInt64, UInt64, UInt64, UInt64,
                          UInt64, UInt64, UInt64, UInt64, UInt64,
                          UInt64, UInt64, UInt64, UInt64, UInt64,
                          UInt64, UInt64, UInt64, UInt64, UInt64) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    subscript(index: Int) -> UInt64 {
        get {
            withUnsafeBytes(of: storage) {
                $0.load(fromByteOffset: index * MemoryLayout<UInt64>.stride, as: UInt64.self)
            }
        }
        set {
            withUnsafeMutableBytes(of: &storage) {
                $0.storeBytes(of: newValue, toByteOffset: index * MemoryLayout<UInt64>.stride,
                              as: UInt64.self)
            }
        }
    }
}
