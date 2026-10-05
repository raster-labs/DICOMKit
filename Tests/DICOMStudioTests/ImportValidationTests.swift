// ImportValidationTests.swift
// DICOMStudioTests
//
// Tests for ImportValidation helper

import Testing
@testable import DICOMStudio
import DICOMCore
import Foundation

@Suite("ImportValidation Tests")
struct ImportValidationTests {

    // MARK: - DICM Magic Detection

    @Test("Valid DICOM data has magic bytes")
    func testHasDICMMagicValid() {
        var data = Data(count: 128) // 128-byte preamble
        data.append(contentsOf: [0x44, 0x49, 0x43, 0x4D]) // DICM
        data.append(Data(count: 100)) // extra data
        #expect(ImportValidation.hasDICMMagic(data))
    }

    @Test("Data without DICM magic returns false")
    func testHasDICMMagicInvalid() {
        var data = Data(count: 128)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        #expect(!ImportValidation.hasDICMMagic(data))
    }

    @Test("Too-small data returns false")
    func testHasDICMMagicTooSmall() {
        let data = Data(count: 10)
        #expect(!ImportValidation.hasDICMMagic(data))
    }

    @Test("Empty data returns false")
    func testHasDICMMagicEmpty() {
        #expect(!ImportValidation.hasDICMMagic(Data()))
    }

    // MARK: - Validate Data

    @Test("Validates minimum file size")
    func testValidateSmallFile() {
        let data = Data(count: 50)
        let issues = ImportValidation.validate(data: data)
        #expect(issues.count == 1)
        #expect(issues[0].rule == .fileSize)
        #expect(issues[0].severity == .warning)
    }

    @Test("Validates missing DICM magic")
    func testValidateMissingMagic() {
        let data = Data(count: 200)
        let issues = ImportValidation.validate(data: data)
        #expect(issues.contains { $0.rule == .dicmMagic })
    }

    @Test("Valid DICOM data produces no errors")
    func testValidateValidData() {
        var data = Data(count: 128)
        data.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])
        data.append(Data(count: 100))
        let issues = ImportValidation.validate(data: data)
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.isEmpty)
    }

    // MARK: - Required Tags Validation

    @Test("All required tags present produces no errors")
    func testRequiredTagsAllPresent() {
        let issues = ImportValidation.validateRequiredTags(
            hasStudyInstanceUID: true,
            hasSOPInstanceUID: true,
            hasSOPClassUID: true
        )
        #expect(issues.isEmpty)
    }

    @Test("Missing SOP Instance UID produces error")
    func testRequiredTagsMissingSOPInstance() {
        let issues = ImportValidation.validateRequiredTags(
            hasStudyInstanceUID: true,
            hasSOPInstanceUID: false,
            hasSOPClassUID: true
        )
        #expect(issues.contains { $0.severity == .error && $0.rule == .requiredTags })
    }

    @Test("Missing SOP Class UID produces warning")
    func testRequiredTagsMissingSOPClass() {
        let issues = ImportValidation.validateRequiredTags(
            hasStudyInstanceUID: true,
            hasSOPInstanceUID: true,
            hasSOPClassUID: false
        )
        #expect(issues.contains { $0.severity == .warning && $0.rule == .sopClassUID })
    }

    @Test("Missing Study Instance UID produces warning")
    func testRequiredTagsMissingStudy() {
        let issues = ImportValidation.validateRequiredTags(
            hasStudyInstanceUID: false,
            hasSOPInstanceUID: true,
            hasSOPClassUID: true
        )
        #expect(issues.contains { $0.severity == .warning && $0.rule == .requiredTags })
    }

    // MARK: - Transfer Syntax Validation

    @Test("Known transfer syntax produces no issues")
    func testTransferSyntaxKnown() {
        let issues = ImportValidation.validateTransferSyntax("1.2.840.10008.1.2")
        #expect(issues.isEmpty)
    }

    @Test("Unknown transfer syntax produces warning")
    func testTransferSyntaxUnknown() {
        let issues = ImportValidation.validateTransferSyntax("1.2.3.4.5.6.7.8.9")
        #expect(issues.count == 1)
        #expect(issues[0].severity == .warning)
        #expect(issues[0].rule == .transferSyntax)
        #expect(issues[0].message.hasPrefix("Unrecognized Transfer Syntax UID"))
    }

    @Test("A registered transfer syntax outside the import list is named, not called unrecognized")
    func testTransferSyntaxRegisteredButUnlisted() {
        // 1.2.840.10008.1.2.4.110 is "JPEG XL Lossless" in PS3.6 2026a Table A-1.
        let issues = ImportValidation.validateTransferSyntax("1.2.840.10008.1.2.4.110")
        #expect(issues.count == 1)
        #expect(issues[0].severity == .warning)
        #expect(issues[0].rule == .transferSyntax)
        #expect(issues[0].message.contains("JPEG XL Lossless (1.2.840.10008.1.2.4.110)"))
        #expect(!issues[0].message.contains("Unrecognized"))
    }

    @Test("The import list is the 16 syntaxes named in the source, all registered in PS3.6")
    func testTransferSyntaxImportList() {
        // The UIDs listed in ImportValidation.validateTransferSyntax, PS3.6 2026a Table A-1.
        let listed = ["1.2.840.10008.1.2", "1.2.840.10008.1.2.1", "1.2.840.10008.1.2.2",
                      "1.2.840.10008.1.2.1.99", "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51",
                      "1.2.840.10008.1.2.4.57", "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.80",
                      "1.2.840.10008.1.2.4.81", "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91",
                      "1.2.840.10008.1.2.4.201", "1.2.840.10008.1.2.4.202", "1.2.840.10008.1.2.4.203",
                      "1.2.840.10008.1.2.5"]
        for uid in listed {
            #expect(ImportValidation.validateTransferSyntax(uid).isEmpty, "\(uid)")
            #expect(TransferSyntax.from(uid: uid) != nil, "\(uid) is registered")
        }
    }

    @Test("Nil transfer syntax produces info")
    func testTransferSyntaxNil() {
        let issues = ImportValidation.validateTransferSyntax(nil)
        #expect(issues.count == 1)
        #expect(issues[0].severity == .info)
    }

    @Test("Empty transfer syntax produces info")
    func testTransferSyntaxEmpty() {
        let issues = ImportValidation.validateTransferSyntax("")
        #expect(issues.count == 1)
        #expect(issues[0].severity == .info)
    }

    @Test("JPEG Baseline transfer syntax is valid")
    func testTransferSyntaxJPEG() {
        let issues = ImportValidation.validateTransferSyntax("1.2.840.10008.1.2.4.50")
        #expect(issues.isEmpty)
    }

    @Test("HTJ2K transfer syntaxes are valid")
    func testTransferSyntaxHTJ2K() {
        #expect(ImportValidation.validateTransferSyntax("1.2.840.10008.1.2.4.201").isEmpty)
        #expect(ImportValidation.validateTransferSyntax("1.2.840.10008.1.2.4.202").isEmpty)
        #expect(ImportValidation.validateTransferSyntax("1.2.840.10008.1.2.4.203").isEmpty)
    }

    // MARK: - Summary and Rejection

    @Test("Summarize counts issues correctly")
    func testSummarize() {
        let issues = [
            ValidationIssue(severity: .error, message: "e1", rule: .fileSize),
            ValidationIssue(severity: .error, message: "e2", rule: .dicmMagic),
            ValidationIssue(severity: .warning, message: "w1", rule: .requiredTags),
            ValidationIssue(severity: .info, message: "i1", rule: .transferSyntax),
        ]
        let (errors, warnings, infos) = ImportValidation.summarize(issues)
        #expect(errors == 2)
        #expect(warnings == 1)
        #expect(infos == 1)
    }

    @Test("Should reject with errors")
    func testShouldRejectWithErrors() {
        let issues = [ValidationIssue(severity: .error, message: "e", rule: .fileSize)]
        #expect(ImportValidation.shouldReject(issues))
    }

    @Test("Should not reject with only warnings")
    func testShouldNotRejectWithWarnings() {
        let issues = [ValidationIssue(severity: .warning, message: "w", rule: .requiredTags)]
        #expect(!ImportValidation.shouldReject(issues))
    }

    @Test("Should not reject empty issues")
    func testShouldNotRejectEmpty() {
        #expect(!ImportValidation.shouldReject([]))
    }

    // MARK: - Constants

    @Test("Minimum file size is 132")
    func testMinimumFileSize() {
        #expect(ImportValidation.minimumFileSize == 132)
    }

    @Test("DICM magic offset is 128")
    func testDICMMagicOffset() {
        #expect(ImportValidation.dicmMagicOffset == 128)
    }

    @Test("DICM magic bytes are correct")
    func testDICMMagicBytes() {
        #expect(ImportValidation.dicmMagicBytes == [0x44, 0x49, 0x43, 0x4D])
    }
}
