import Foundation
import Testing
@testable import DICOMCore

@Suite("Strict borrowed decimal scalar")
struct DecimalScalarTests {
    private func parse(_ string: String) -> DICOMDecimalScalarOutcome {
        Array(string.utf8).withUnsafeBytes { DICOMDecimalString.parseScalar($0) }
    }

    @Test func decimalGrammar() {
        for text in ["1", "+1", "-1", "1.", ".5", "-.5", "1.e2", "+.5E-2", "  1.25  "] {
            let result = parse(text)
            #expect(result.status == .success, "\(text)")
            #expect(result.value.bitPattern == Double(text.trimmingCharacters(in: .whitespaces))?.bitPattern)
        }
    }

    @Test func strictRejections() {
        for text in ["+", "-", ".", "+.", "1e", "1e+", "1e-", "1e2e3", "e1", "1..2",
                     "1 2", "1 e2", "1e 2", "1\t", "\n1", "1\r", "1\0", "1\\2", "1\\",
                     "0x1", "0x1p2", "NaN", "nan", "Inf", "-inf", "∞", "١", "1\u{a0}",
                     "--1", "++1", "1-", "1,2", "0e999X", "0e-999X"] {
            let result = parse(text)
            #expect(result.status == .invalidSyntax, "\(text.debugDescription)")
            #expect(result.value.bitPattern == 0)
        }
    }

    @Test func onlyASCIISpacePads() {
        for byte in UInt8.min...UInt8.max where byte != 0x20 {
            // Every non-grammar byte must fail at either outer edge.
            if (0x30...0x39).contains(byte) || byte == 0x2B || byte == 0x2D || byte == 0x2E { continue }
            for bytes in [[byte, 0x31], [0x31, byte]] {
                #expect(bytes.withUnsafeBytes { DICOMDecimalString.parseScalar($0).status } == .invalidSyntax)
            }
        }
    }

    @Test func rawLengthIncludesPadding() {
        #expect(parse("").status == .empty)
        #expect(parse("                ").status == .empty)
        #expect(parse("                 ").status == .tooLong)
        #expect(parse("1234567890123456").status == .success)
        #expect(parse("1234567890123456 ").status == .tooLong)
        #expect(parse(" 1234567890123456").status == .tooLong)
        #expect(parse("12345678901234567").status == .tooLong)
        #expect(DICOMDecimalString.parseScalar(.init(start: nil, count: 0)).status == .empty)
    }

    @Test func integerRoundingTies() {
        let cases: [(String, UInt64)] = [
            ("9007199254740991", 0x433fffffffffffff),
            ("9007199254740992", 0x4340000000000000),
            ("9007199254740993", 0x4340000000000000),
            ("9007199254740995", 0x4340000000000002),
            ("9999999999999999", 0x4341c37937e08000)
        ]
        for (text, bits) in cases {
            let result = parse(text)
            #expect(result.status == .success)
            #expect(result.value.bitPattern == bits, "\(text)")
        }
    }

    @Test func exponentBoundaries() {
        let cases: [(String, UInt64)] = [
            ("2.470328229e-324", 0), ("2.470328230e-324", 1),
            ("22250738585e-318", 0x000fffffffffc710),
            ("22250738586e-318", 0x001000000002ddb2),
            ("179769313486e297", 0x7fefffffffffd2ac),
            ("1e-323", 2), ("1e308", 0x7fe1ccf385ebc8a0)
        ]
        for (text, bits) in cases {
            for prefix in ["", "-"] {
                let result = parse(prefix + text)
                if (prefix + text).utf8.count > 16 {
                    #expect(result.status == .tooLong)
                    continue
                }
                #expect(result.status == .success)
                #expect(result.value.bitPattern == bits | (prefix.isEmpty ? 0 : 1 << 63))
            }
        }
        for text in ["179769313487e297", "-17976931349e298", "1e309", "1e9999999999999"] {
            #expect(parse(text).status == .overflow, "\(text)")
        }
    }

    @Test func signedZeroAndExtremeExponents() {
        for text in ["0", "0.0", "0e9999999999999", "0e-999999999999", "1e-999999999999", "1e-340"] {
            #expect(parse(text).status == .success)
            #expect(parse(text).value.bitPattern == 0)
            #expect(parse("-" + text).status == .success)
            #expect(parse("-" + text).value.bitPattern == 1 << 63)
        }
    }

    @Test func decimalCompatibilityAcrossExponents() {
        // The compatibility API is an additional cross-check, not the independent
        // arbitrary-precision oracle used by the qualification script.
        for exponent in -340...309 {
            for coefficient in ["1", "17", "9999999999"] {
                let text = coefficient + "e" + String(exponent)
                let result = parse(text)
                let expected = Double(text)!
                if expected.isFinite {
                    #expect(result.status == .success)
                    #expect(result.value.bitPattern == expected.bitPattern, "\(text)")
                } else {
                    #expect(result.status == .overflow)
                }
            }
        }
    }

    @Test func compatibilityParserStillAllowsItsDocumentedInputs() {
        #expect(DICOMDecimalString.parse("0x1p2")?.value == 4)
        #expect(DICOMDecimalString.parse("\t1\t")?.value == 1)
        #expect(DICOMDecimalString.parse("1234567890123456 ") != nil)
        #expect(DICOMDecimalString.parseMultiple("1\\2")?.map(\.value) == [1, 2])
    }
}
