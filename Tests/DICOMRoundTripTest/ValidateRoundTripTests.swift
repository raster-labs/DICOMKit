// ValidateRoundTripTests.swift
// Oracle-based round-trip tests for the `dicom-validate` tool.
//
// These call the DICOMKit library directly (DICOMValidator / ValidationReport),
// never the CLI. Every assertion is a semantic invariant of the validator's
// contract, not a comparison to a re-implementation of the tool.

import XCTest
import Foundation
@testable import DICOMKit
@testable import DICOMCore

final class ValidateRoundTripTests: XCTestCase {

    // MARK: - Private helpers (class-scoped so they never collide with other files)

    // (Validator is constructed inline in `validate(_:level:iod:)`; the CLI default is level 3.)

    /// Return a copy of `file` whose main data set has been mutated by `mutate`.
    /// (`DICOMFile.dataSet` is a `let`, so we rebuild the file to change it.)
    private func mutating(_ file: DICOMFile, _ mutate: (inout DataSet) -> Void) -> DICOMFile {
        var ds = file.dataSet
        mutate(&ds)
        return DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: ds)
    }

    /// Serialize a file and run the validator over its bytes, as the CLI does.
    private func validate(_ file: DICOMFile, level: Int = 3, iod: String? = nil) throws -> ValidationResult {
        let data = try file.write()
        let validator = DICOMValidator(level: level, iod: iod, force: false)
        return try validator.validate(data: data, filePath: "test.dcm")
    }

    /// True if any error message contains the given (case-insensitive) substring.
    private func anyError(_ result: ValidationResult, contains needle: String) -> Bool {
        result.errors.contains { $0.message.range(of: needle, options: .caseInsensitive) != nil }
    }

    // MARK: - Tests

    // Oracle (plan 3.12): a well-formed conformant CT file yields zero validation errors.
    func testValidConformantFileHasNoErrors() throws {
        let file = makeGrayscale8(rows: 8, cols: 8)
        let result = try validate(file)
        XCTAssertTrue(result.errors.isEmpty,
                      "Conformant file must have no errors, got: \(result.errors.map(\.message))")
        XCTAssertTrue(result.isValid, "Conformant file must be reported valid")
    }

    // Oracle (plan 3.12): removing the required Type-1 SOP Class UID produces an error naming it.
    func testMissingSOPClassUIDIsDetected() throws {
        // Remove the Type 1 element from the main dataset (file-meta copy is independent).
        let file = mutating(makeGrayscale8(rows: 8, cols: 8)) { $0[.sopClassUID] = nil }
        // Level 2 is where Type-1 tag presence is validated.
        let result = try validate(file, level: 2)
        XCTAssertFalse(result.isValid, "File missing SOP Class UID must be invalid")
        XCTAssertTrue(anyError(result, contains: "SOP Class UID"),
                      "An error must mention 'SOP Class UID', got: \(result.errors.map(\.message))")
    }

    // Oracle (source-verified): missing Type-1 SOP Instance UID is likewise flagged.
    func testMissingSOPInstanceUIDIsDetected() throws {
        let file = mutating(makeGrayscale8(rows: 8, cols: 8)) { $0[.sopInstanceUID] = nil }
        let result = try validate(file, level: 2)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(anyError(result, contains: "SOP Instance UID"),
                      "An error must mention 'SOP Instance UID', got: \(result.errors.map(\.message))")
    }

    // Oracle (oracleHints): ValidationResult.isValid is true iff errors.isEmpty — for both a good and a broken file.
    func testIsValidEqualsErrorsEmptyInvariant() throws {
        let good = try validate(makeGrayscale8(rows: 4, cols: 4))
        XCTAssertEqual(good.isValid, good.errors.isEmpty)

        let brokenFile = mutating(makeGrayscale8(rows: 4, cols: 4)) { $0[.sopClassUID] = nil }
        let broken = try validate(brokenFile, level: 2)
        XCTAssertEqual(broken.isValid, broken.errors.isEmpty)
    }

    // Oracle (source-verified): an invalid DA date value is reported as an error.
    func testInvalidDateFormatIsDetected() throws {
        // Not YYYYMMDD (month 13) — validator's isValidDate rejects it.
        let file = mutating(makeGrayscale8(rows: 4, cols: 4)) {
            $0.setString("20241301", for: .studyDate, vr: .DA)
        }
        let result = try validate(file, level: 2)
        XCTAssertFalse(result.isValid, "Invalid Study Date must make the file invalid")
        XCTAssertTrue(anyError(result, contains: "date"),
                      "An error must mention the date, got: \(result.errors.map(\.message))")
    }

    // Oracle (source-verified): a non-numeric / malformed UID value is reported as an error.
    func testInvalidUIDFormatIsDetected() throws {
        // Contains a non-numeric component — isValidUID rejects it.
        let file = mutating(makeGrayscale8(rows: 4, cols: 4)) {
            $0.setString("1.2.abc.4", for: .seriesInstanceUID, vr: .UI)
        }
        let result = try validate(file, level: 2)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(anyError(result, contains: "UID"),
                      "An error must mention the UID, got: \(result.errors.map(\.message))")
    }

    // Oracle (oracleHints): exitCode() is 0 for a valid file and 1 when the file has errors.
    func testExitCodeReflectsErrorPresence() throws {
        let validResult = try validate(makeGrayscale8(rows: 4, cols: 4))
        let validReport = ValidationReport(results: [validResult], detailed: false, strict: false)
        XCTAssertEqual(validReport.exitCode(), 0, "Valid file must exit 0")

        let brokenFile = mutating(makeGrayscale8(rows: 4, cols: 4)) { $0[.sopClassUID] = nil }
        let brokenResult = try validate(brokenFile, level: 2)
        let brokenReport = ValidationReport(results: [brokenResult], detailed: false, strict: false)
        XCTAssertEqual(brokenReport.exitCode(), 1, "File with errors must exit 1")
    }

    // Oracle (oracleHints): with --strict and warnings-but-no-errors, exitCode() is 2; without --strict it is 0.
    func testStrictExitCodeForWarningsOnly() throws {
        // Force a warning-only result with no errors: Image Type encoded with VR LO instead
        // of the PS3.6 VR CS triggers an "Unexpected VR" warning; everything else stays
        // conformant. (A lowercase CS value is an error since D142: lowercase letters are
        // outside the CS repertoire of PS3.5 Table 6.2-1.)
        let file = mutating(makeGrayscale8(rows: 4, cols: 4)) {
            $0.setString("AX", for: .imageType, vr: .LO)
        }
        let result = try validate(file, level: 2)

        try XCTSkipIf(!result.errors.isEmpty,
                      "Setup unexpectedly produced errors: \(result.errors.map(\.message))")
        try XCTSkipIf(result.warnings.isEmpty, "Setup did not produce the expected warning")

        let lenient = ValidationReport(results: [result], detailed: false, strict: false)
        XCTAssertEqual(lenient.exitCode(), 0, "Warnings only, non-strict, must exit 0")

        let strict = ValidationReport(results: [result], detailed: false, strict: true)
        XCTAssertEqual(strict.exitCode(), 2, "Warnings only, strict, must exit 2")
    }

    // Oracle (subcommand: reportRendering): the JSON report parses and its counts match the results.
    func testJSONReportCountsMatchResults() throws {
        let brokenFile = mutating(makeGrayscale8(rows: 4, cols: 4)) { $0[.sopClassUID] = nil }
        let result = try validate(brokenFile, level: 2)
        try XCTSkipIf(result.errors.isEmpty, "Expected at least one error to report")

        let report = ValidationReport(results: [result], detailed: true, strict: false)
        let jsonString = try report.render(format: .json)
        let jsonData = Data(jsonString.utf8)
        let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        let root = try XCTUnwrap(obj, "JSON report must parse into an object")

        XCTAssertEqual(root["totalFiles"] as? Int, 1)
        XCTAssertEqual(root["invalidFiles"] as? Int, 1)
        XCTAssertEqual(root["validFiles"] as? Int, 0)
        XCTAssertEqual(root["totalErrors"] as? Int, result.errors.count,
                       "Reported totalErrors must equal the result's error count")
    }

    // Oracle (subcommand: reportRendering): text report reflects validity and error count faithfully.
    func testTextReportReflectsValidity() throws {
        let validResult = try validate(makeGrayscale8(rows: 4, cols: 4))
        let validText = try ValidationReport(results: [validResult], detailed: true, strict: false)
            .render(format: .text)
        XCTAssertTrue(validText.contains("VALID"),
                      "Text report for a valid file must state VALID")

        let brokenFile = mutating(makeGrayscale8(rows: 4, cols: 4)) { $0[.sopClassUID] = nil }
        let brokenResult = try validate(brokenFile, level: 2)
        try XCTSkipIf(brokenResult.errors.isEmpty, "Expected errors for the broken file")
        let brokenText = try ValidationReport(results: [brokenResult], detailed: true, strict: false)
            .render(format: .text)
        XCTAssertTrue(brokenText.contains("INVALID"),
                      "Text report for a broken file must state INVALID")
        XCTAssertTrue(brokenText.contains("\(brokenResult.errors.count)"),
                      "Text report must include the error count")
    }

    // Oracle (level semantics): raising the level never decreases the detected errors on the same file.
    // Level 2 adds tag/VR/VM checks on top of level 1; a Type-1 omission caught at 2 must also be caught at 3.
    func testHigherLevelIsAtLeastAsStrict() throws {
        let brokenFile = mutating(makeGrayscale8(rows: 4, cols: 4)) { $0[.sopClassUID] = nil }
        let atLevel2 = try validate(brokenFile, level: 2)
        let atLevel3 = try validate(brokenFile, level: 3)
        XCTAssertGreaterThanOrEqual(atLevel3.errors.count, atLevel2.errors.count,
                                    "Level 3 must report at least as many errors as level 2")
        XCTAssertTrue(anyError(atLevel2, contains: "SOP Class UID"))
        XCTAssertTrue(anyError(atLevel3, contains: "SOP Class UID"))
    }

    // Oracle (realism, corpus-backed): a real anonymized CT file parses and validates without errors.
    func testCorpusCTValidatesWithoutErrors() throws {
        let f = try loadCorpus(.ct)
        try XCTSkipIf(f == nil, "corpus absent")
        let file = try XCTUnwrap(f)
        let result = try validate(file, level: 3)
        XCTAssertTrue(result.errors.isEmpty,
                      "Real conformant CT must have no errors, got: \(result.errors.map(\.message))")
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Oracle: level 4 (best practices) adds warnings level 3 does not

    // Oracle: level 4 runs validateBestPractices — a file with no SpecificCharacterSet
    // (0008,0005) draws a best-practice warning at level ≥ 4 but not at level 3. Best
    // practices are warnings, not errors, so the file stays valid.
    func testLevel4AddsBestPracticeCharsetWarning() throws {
        let file = makeGrayscale8(rows: 8, cols: 8)   // fixture sets no SpecificCharacterSet
        let needle = "Specific Character Set"

        let l3 = try validate(file, level: 3)
        XCTAssertFalse(l3.warnings.contains { $0.message.contains(needle) },
                       "level 3 must not emit the best-practice charset warning")

        let l4 = try validate(file, level: 4)
        XCTAssertTrue(l4.warnings.contains { $0.message.contains(needle) },
                      "level 4 must emit the best-practice charset warning")
        XCTAssertTrue(l4.isValid, "best practices are warnings only — file stays valid")
    }

    // MARK: - Oracle: level 5 (J2K codestream) runs only for J2K transfer syntaxes

    // Oracle: level 5 validates the JPEG 2000 codestream. A conformant Part-1 J2K
    // corpus file produces no codestream errors; removing its Pixel Data makes level 5
    // flag "Pixel Data absent", while level 4 (which never reaches the J2K check) stays
    // silent — proving the level-5 gate wires the codestream validation.
    func testLevel5ValidatesJ2KCodestream() throws {
        let f = try loadCorpus(.j2kLossless)
        try XCTSkipIf(f == nil, "corpus absent")
        let file = try XCTUnwrap(f)
        XCTAssertEqual(file.fileMetaInformation.string(for: .transferSyntaxUID),
                       "1.2.840.10008.1.2.4.90", "precondition: corpus declares J2K Lossless")

        // The J2K codestream check runs only at level 5: level 4 emits no J2K-specific
        // messages, and level 5 is at least as strict (it adds the codestream pass).
        let l4 = try validate(file, level: 4)
        let l5 = try validate(file, level: 5)
        XCTAssertFalse(l4.errors.contains { $0.message.contains("J2K") },
                       "level 4 must not run the J2K codestream check")
        XCTAssertGreaterThanOrEqual(l5.errors.count + l5.warnings.count,
                                    l4.errors.count + l4.warnings.count,
                                    "level 5 must be at least as strict as level 4")

        // Differential: a J2K-declared file with no Pixel Data is flagged only at level 5.
        let noPixels = mutating(file) { $0[.pixelData] = nil }
        let needle = "Pixel Data"
        let l4np = try validate(noPixels, level: 4)
        XCTAssertFalse(l4np.errors.contains { $0.message.contains("J2K") && $0.message.contains(needle) },
                       "level 4 must not run the J2K pixel-data-presence check")
        let l5np = try validate(noPixels, level: 5)
        XCTAssertTrue(l5np.errors.contains { $0.message.contains("J2K") && $0.message.contains(needle) },
                      "level 5 must flag a J2K-declared file with no Pixel Data")
    }

    // MARK: - Oracle: level 1 (format only) omits the level-2 tag-presence checks

    // Oracle: level 1 validates only file-meta/format, not dataset Type-1 tag presence.
    // A missing dataset SOP Class UID (0008,0016) is caught at level 2 but NOT at level 1
    // (the file-meta MediaStorageSOPClassUID is untouched), and level 1 ≤ level 2 errors.
    func testLevel1FormatOnlyOmitsTagPresenceChecks() throws {
        let broken = mutating(makeGrayscale8(rows: 4, cols: 4)) { $0[.sopClassUID] = nil }
        let l1 = try validate(broken, level: 1)
        let l2 = try validate(broken, level: 2)
        XCTAssertFalse(anyError(l1, contains: "SOP Class UID"),
                       "level 1 (format only) must not run Type-1 tag-presence checks")
        XCTAssertTrue(anyError(l2, contains: "SOP Class UID"),
                      "level 2 must flag the missing Type-1 SOP Class UID")
        XCTAssertLessThanOrEqual(l1.errors.count, l2.errors.count,
                                 "level 1 never reports more errors than level 2")
    }
}
