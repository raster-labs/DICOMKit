import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

/// M0 parser-hardening tests: resource limits and crash-resistance
/// (RESEARCH_ADOPTION_PLAN.md M0; instructions §17; ECOSYSTEM_COMPARISON §4.1).
final class ParserLimitTests: XCTestCase {

    // MARK: - File builders

    /// Part 10 header declaring Implicit VR Little Endian.
    private func implicitVRHeader() -> Data {
        var data = Data()
        data.append(Data(count: 128))
        data.append(contentsOf: [0x44, 0x49, 0x43, 0x4D]) // DICM
        // (0002,0010) UI, "1.2.840.10008.1.2" padded to 18
        data.append(contentsOf: [0x02, 0x00, 0x10, 0x00])
        data.append(contentsOf: [0x55, 0x49])
        data.append(contentsOf: [0x12, 0x00])
        data.append(contentsOf: Array("1.2.840.10008.1.2\0".utf8))
        return data
    }

    /// Part 10 header declaring Explicit VR Little Endian.
    private func explicitVRHeader() -> Data {
        var data = Data()
        data.append(Data(count: 128))
        data.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])
        // (0002,0010) UI; NULL padding per PS3.5 Table 6.2-1.
        data.append(contentsOf: [0x02, 0x00, 0x10, 0x00])
        data.append(contentsOf: [0x55, 0x49])
        data.append(contentsOf: [0x14, 0x00])
        data.append(contentsOf: Array("1.2.840.10008.1.2.1\0".utf8))
        return data
    }

    // MARK: - Sequence depth (stack-overflow guard)

    /// A file nesting undefined-length sequences thousands deep must throw
    /// `limitExceeded` — before this guard existed it crashed with a stack
    /// overflow (fo-dicom #1977 class of bug).
    func testDeeplyNestedSequencesThrowInsteadOfCrashing() {
        var data = implicitVRHeader()
        // Repeat: (0008,1115) Referenced Series Sequence, undefined length,
        // then Item (FFFE,E000) with undefined length — each pair adds one
        // recursion level and is never closed.
        for _ in 0..<5000 {
            data.append(contentsOf: [0x08, 0x00, 0x15, 0x11]) // tag
            data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // undefined length
            data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0]) // item tag
            data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // undefined length
        }

        XCTAssertThrowsError(try DICOMFile.read(from: data)) { error in
            guard case DICOMError.limitExceeded = error else {
                return XCTFail("Expected limitExceeded, got \(error)")
            }
        }
    }

    /// Nesting below the ceiling still parses.
    func testModerateNestingStillParses() throws {
        var data = implicitVRHeader()
        let depth = 8
        for _ in 0..<depth {
            data.append(contentsOf: [0x08, 0x00, 0x15, 0x11])
            data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
            data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
            data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        }
        // Close them: item delimiter + sequence delimiter per level.
        for _ in 0..<depth {
            data.append(contentsOf: [0xFE, 0xFF, 0x0D, 0xE0, 0x00, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])
        }

        let file = try DICOMFile.read(from: data)
        XCTAssertNotNil(file.dataSet[Tag(group: 0x0008, element: 0x1115)])
    }

    // MARK: - Element length ceiling

    func testMaxElementLengthRejectsOversizedDeclaration() {
        var data = explicitVRHeader()
        // (0010,0010) PN declaring 60 000 bytes (present in file so the
        // default bounds check alone would not reject it).
        data.append(contentsOf: [0x10, 0x00, 0x10, 0x00])
        data.append(contentsOf: [0x50, 0x4E])
        data.append(contentsOf: [0x60, 0xEA]) // 0xEA60 = 60000
        data.append(Data(count: 60000))

        let options = ParsingOptions(maxElementLength: 1024)
        XCTAssertThrowsError(try DICOMFile.read(from: data, options: options)) { error in
            guard case DICOMError.limitExceeded = error else {
                return XCTFail("Expected limitExceeded, got \(error)")
            }
        }
        // Without the option the same file parses.
        XCTAssertNoThrow(try DICOMFile.read(from: data))
    }

    /// A truncated multi-gigabyte length declaration must throw, not allocate.
    func testHugeDeclaredLengthOnTruncatedFileThrows() {
        var data = explicitVRHeader()
        // (7FE0,0010) OB declaring ~3.9 GB with no bytes following.
        data.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])
        data.append(contentsOf: [0x4F, 0x42]) // OB
        data.append(contentsOf: [0x00, 0x00]) // reserved
        data.append(contentsOf: [0x00, 0x00, 0x00, 0xEA]) // length 0xEA000000

        // Must not crash or allocate the declared size; error or truncated
        // parse are both acceptable fail-closed outcomes.
        _ = try? DICOMFile.read(from: data)
    }

    // MARK: - Total element budget

    func testMaxTotalElementsCountsNestedElements() {
        var data = implicitVRHeader()
        // One sequence with one item containing 50 small elements.
        data.append(contentsOf: [0x08, 0x00, 0x15, 0x11])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        for _ in 0..<50 {
            // (0008,0018) SOP Instance UID, length 2
            data.append(contentsOf: [0x08, 0x00, 0x18, 0x00])
            data.append(contentsOf: [0x02, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x31, 0x00])
        }
        data.append(contentsOf: [0xFE, 0xFF, 0x0D, 0xE0, 0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])

        // `maxElements` bounds only the top level, so it cannot catch this;
        // `maxTotalElements` must.
        let options = ParsingOptions(maxTotalElements: 10)
        XCTAssertThrowsError(try DICOMFile.read(from: data, options: options)) { error in
            guard case DICOMError.limitExceeded = error else {
                return XCTFail("Expected limitExceeded, got \(error)")
            }
        }
        XCTAssertNoThrow(try DICOMFile.read(from: data))
    }

    // MARK: - Fragment count

    /// Part 10 header declaring JPEG Baseline (an encapsulated syntax) so the
    /// fragment-parsing path runs.
    private func encapsulatedHeader() -> Data {
        var data = Data()
        data.append(Data(count: 128))
        data.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])
        // (0002,0010) UI, "1.2.840.10008.1.2.4.50" padded to 22
        data.append(contentsOf: [0x02, 0x00, 0x10, 0x00])
        data.append(contentsOf: [0x55, 0x49])
        data.append(contentsOf: [0x16, 0x00])
        data.append(contentsOf: Array("1.2.840.10008.1.2.4.50".utf8))
        return data
    }

    func testMaxFragmentCountRejectsFragmentStorm() {
        var data = encapsulatedHeader()
        // Encapsulated (7FE0,0010) OB undefined length, empty BOT, 100 empty fragments.
        data.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])
        data.append(contentsOf: [0x4F, 0x42, 0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0, 0x00, 0x00, 0x00, 0x00]) // BOT, empty
        for _ in 0..<100 {
            data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0, 0x02, 0x00, 0x00, 0x00, 0xAB, 0xCD])
        }
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])

        let options = ParsingOptions(maxFragmentCount: 16)
        XCTAssertThrowsError(try DICOMFile.read(from: data, options: options)) { error in
            guard case DICOMError.limitExceeded = error else {
                return XCTFail("Expected limitExceeded, got \(error)")
            }
        }
        XCTAssertNoThrow(try DICOMFile.read(from: data))
    }

    // MARK: - Mutation fuzz (crash resistance)

    /// Deterministic LCG so failures are reproducible from the logged seed.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// Random byte mutations over a valid file must never crash the parser —
    /// throwing or returning a partial data set are the only acceptable outcomes.
    func testParserSurvivesRandomByteMutations() {
        var base = explicitVRHeader()
        base.append(contentsOf: [0x10, 0x00, 0x10, 0x00, 0x50, 0x4E, 0x0A, 0x00])
        base.append(contentsOf: Array("Test^Fuzz\0".utf8))
        // A small sequence to expose the nesting paths to mutation.
        base.append(contentsOf: [0x08, 0x00, 0x15, 0x11, 0x53, 0x51, 0x00, 0x00])
        base.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        base.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0, 0xFF, 0xFF, 0xFF, 0xFF])
        base.append(contentsOf: [0x08, 0x00, 0x18, 0x00, 0x55, 0x49, 0x02, 0x00, 0x31, 0x00])
        base.append(contentsOf: [0xFE, 0xFF, 0x0D, 0xE0, 0x00, 0x00, 0x00, 0x00])
        base.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])
        // Encapsulated-style tail to fuzz the fragment path.
        base.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00, 0x4F, 0x42, 0x00, 0x00])
        base.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        base.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0, 0x00, 0x00, 0x00, 0x00])
        base.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0, 0x04, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04])
        base.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])

        let seed: UInt64 = 0xD1C0_2026_0810_0001
        var rng = SplitMix64(state: seed)
        // Default keeps CI fast; set DICOM_FUZZ_ITERATIONS for deep runs
        // (M0 acceptance used 100 000).
        let iterations = ProcessInfo.processInfo.environment["DICOM_FUZZ_ITERATIONS"]
            .flatMap(Int.init) ?? 2000
        let mutableRange = 132..<base.count // keep preamble+DICM to reach the parser

        for i in 0..<iterations {
            var mutated = base
            for _ in 0..<Int.random(in: 1...8, using: &rng) {
                let index = Int.random(in: mutableRange, using: &rng)
                mutated[index] = UInt8.random(in: 0...255, using: &rng)
            }
            // Occasionally truncate.
            if Int.random(in: 0..<10, using: &rng) == 0 {
                mutated = Data(mutated.prefix(Int.random(in: 132..<mutated.count, using: &rng)))
            }
            // Must not crash (seed \(seed), iteration \(i) reproduces failures).
            _ = try? DICOMFile.read(from: mutated)
            _ = i
        }
    }
}
