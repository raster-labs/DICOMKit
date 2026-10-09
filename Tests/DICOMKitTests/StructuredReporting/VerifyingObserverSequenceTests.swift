import XCTest
import DICOMCore
@testable import DICOMKit

/// Verifying Observer Sequence (0040,A073) of the SR Document General Module (PS3.3 2026a
/// Table C.17-2) as written by `SRDocumentSerializer` and read back by `SRDocumentParser`
/// (D37 a). Type 1C: "Required if Verification Flag (0040,A493) is VERIFIED", "One or more
/// Items shall be included"; PS3.5 2026a 7.4.2: a Type 1C element "shall not be included"
/// when its condition is not met.
final class VerifyingObserverSequenceTests: XCTestCase {

    private let observer = VerifyingObserver(
        name: "Smith^Jane",
        identificationCode: CodedConcept(codeValue: "RAD-0042", codingSchemeDesignator: "99LOCAL", codeMeaning: "Jane Smith"),
        organization: "General Hospital Radiology",
        verificationDateTime: "20260929101500")

    private func document(
        completionFlag: CompletionFlag? = .complete,
        verificationFlag: VerificationFlag?,
        observers: [VerifyingObserver] = []
    ) -> SRDocument {
        let root = ContainerContentItem(
            conceptName: CodedConcept(codeValue: "126000", scheme: .DCM, codeMeaning: "Imaging Measurement Report"),
            continuityOfContent: .separate,
            contentItems: [])
        return SRDocument(
            sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID, sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4",
            completionFlag: completionFlag, verificationFlag: verificationFlag,
            verifyingObservers: observers,
            documentTitle: root.conceptName, rootContent: root)
    }

    // MARK: - Tags (PS3.6 2026a Table 6-1)

    func testTagsMatchPS36() {
        XCTAssertEqual(Tag.verifyingObserverSequence, Tag(group: 0x0040, element: 0xA073))
        XCTAssertEqual(Tag.verifyingObserverName, Tag(group: 0x0040, element: 0xA075))
        XCTAssertEqual(Tag.verifyingObserverIdentificationCodeSequence, Tag(group: 0x0040, element: 0xA088))
        XCTAssertEqual(Tag.verifyingOrganization, Tag(group: 0x0040, element: 0xA027))
        XCTAssertEqual(Tag.verificationDateTime, Tag(group: 0x0040, element: 0xA030))
    }

    // MARK: - VERIFIED: one or more Items

    func testVerifiedWritesTheSequenceAndReadsItBack() throws {
        let second = VerifyingObserver(name: "Doe^John", organization: "General Hospital Radiology",
                                       verificationDateTime: "20260929103000")
        let dataSet = try SRDocumentSerializer().serialize(
            document: document(verificationFlag: .verified, observers: [observer, second]))

        let sequence = try XCTUnwrap(dataSet[.verifyingObserverSequence])
        XCTAssertEqual(sequence.vr, .SQ)
        let items = try XCTUnwrap(sequence.sequenceItems)
        XCTAssertEqual(items.count, 2)

        // Verifying Observer Name (0040,A075) Type 1, PN
        XCTAssertEqual(items[0][.verifyingObserverName]?.vr, .PN)
        XCTAssertEqual(items[0].string(for: .verifyingObserverName), "Smith^Jane")
        // Verifying Organization (0040,A027) Type 1, LO
        XCTAssertEqual(items[0][.verifyingOrganization]?.vr, .LO)
        XCTAssertEqual(items[0].string(for: .verifyingOrganization), "General Hospital Radiology")
        // Verification DateTime (0040,A030) Type 1, DT
        XCTAssertEqual(items[0][.verificationDateTime]?.vr, .DT)
        XCTAssertEqual(items[0].string(for: .verificationDateTime), "20260929101500")
        // Verifying Observer Identification Code Sequence (0040,A088) Type 2: one Item here …
        let code = try XCTUnwrap(items[0][.verifyingObserverIdentificationCodeSequence]?.sequenceItems)
        XCTAssertEqual(code.count, 1)
        XCTAssertEqual(code[0].string(for: .codeValue), "RAD-0042")
        XCTAssertEqual(code[0].string(for: .codingSchemeDesignator), "99LOCAL")
        XCTAssertEqual(code[0].string(for: .codeMeaning), "Jane Smith")
        // … and present with zero Items when the observer has no code
        let empty = try XCTUnwrap(items[1][.verifyingObserverIdentificationCodeSequence])
        XCTAssertEqual(empty.vr, .SQ)
        XCTAssertEqual(empty.sequenceItems?.count ?? 0, 0)

        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.verificationFlag, .verified)
        XCTAssertEqual(parsed.verifyingObservers, [observer, second])
    }

    func testVerifiedWithoutObserversThrows() {
        XCTAssertThrowsError(try SRDocumentSerializer().serialize(
            document: document(verificationFlag: .verified))) { error in
            guard case SRDocumentSerializer.SerializationError.missingRequiredAttribute = error else {
                return XCTFail("expected missingRequiredAttribute, got \(error)")
            }
        }
    }

    func testType1ItemAttributesMustHaveValues() {
        for incomplete in [
            VerifyingObserver(name: "", organization: "Org", verificationDateTime: "20260929"),
            VerifyingObserver(name: "A^B", organization: " ", verificationDateTime: "20260929"),
            VerifyingObserver(name: "A^B", organization: "Org", verificationDateTime: ""),
        ] {
            XCTAssertThrowsError(try SRDocumentSerializer().serialize(
                document: document(verificationFlag: .verified, observers: [incomplete]))) { error in
                guard case SRDocumentSerializer.SerializationError.missingRequiredAttribute = error else {
                    return XCTFail("expected missingRequiredAttribute, got \(error)")
                }
            }
        }
    }

    // MARK: - UNVERIFIED: not included (PS3.5 7.4.2)

    func testUnverifiedOmitsTheSequence() throws {
        let dataSet = try SRDocumentSerializer().serialize(document: document(verificationFlag: .unverified))
        XCTAssertNil(dataSet[.verifyingObserverSequence])
        XCTAssertEqual(try SRDocumentParser().parse(dataSet: dataSet).verifyingObservers, [])

        // No flag at all is written as UNVERIFIED, likewise without the sequence
        let defaulted = try SRDocumentSerializer().serialize(document: document(verificationFlag: nil))
        XCTAssertEqual(defaulted.string(for: .verificationFlag), "UNVERIFIED")
        XCTAssertNil(defaulted[.verifyingObserverSequence])
    }

    func testUnverifiedWithObserversThrows() {
        XCTAssertThrowsError(try SRDocumentSerializer().serialize(
            document: document(verificationFlag: .unverified, observers: [observer]))) { error in
            guard case SRDocumentSerializer.SerializationError.inconsistentAttributes = error else {
                return XCTFail("expected inconsistentAttributes, got \(error)")
            }
        }
    }

    // MARK: - Builder output

    func testBuilderDocumentGainsObserversWithCopy() throws {
        let built = try SRDocumentBuilder()
            .withCompletionFlag(.complete)
            .withVerificationFlag(.verified)
            .build()
        XCTAssertThrowsError(try SRDocumentSerializer().serialize(document: built))

        let verified = built.withVerifyingObservers([observer])
        XCTAssertEqual(verified.sopInstanceUID, built.sopInstanceUID)
        XCTAssertEqual(verified.verificationFlag, .verified)
        let dataSet = try SRDocumentSerializer().serialize(document: verified)
        XCTAssertEqual(dataSet[.verifyingObserverSequence]?.sequenceItems?.count, 1)
    }
}
