import Testing
import Foundation
@testable import DICOMCore

@Suite("DICOMUniqueIdentifier Tests")
struct DICOMUniqueIdentifierTests {
    
    // MARK: - Parsing Tests
    
    @Test("Parse standard DICOM Transfer Syntax UID")
    func testParseTransferSyntaxUID() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        #expect(uid != nil)
        #expect(uid?.value == "1.2.840.10008.1.2")
        #expect(uid?.components.count == 6)
        #expect(uid?.components == ["1", "2", "840", "10008", "1", "2"])
    }
    
    @Test("Parse standard DICOM SOP Class UID")
    func testParseSOPClassUID() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.2")
        #expect(uid != nil)
        #expect(uid?.value == "1.2.840.10008.5.1.4.1.1.2")
        #expect(uid?.isStandardDICOM == true)
    }
    
    @Test("Parse instance UID with long numeric components")
    func testParseLongInstanceUID() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.113619.2.5.1762583153.215519.978957063.78")
        #expect(uid != nil)
        #expect(uid?.componentCount == 10)
    }
    
    @Test("Parse UID with single component")
    func testParseSingleComponent() {
        let uid = DICOMUniqueIdentifier.parse("1")
        #expect(uid != nil)
        #expect(uid?.components == ["1"])
        #expect(uid?.componentCount == 1)
    }
    
    @Test("Parse UID with zero component")
    func testParseZeroComponent() {
        let uid = DICOMUniqueIdentifier.parse("1.0.2")
        #expect(uid != nil)
        #expect(uid?.components == ["1", "0", "2"])
    }
    
    @Test("Parse with leading/trailing whitespace")
    func testParseWithWhitespace() {
        let uid = DICOMUniqueIdentifier.parse("  1.2.840.10008.1.2  ")
        #expect(uid != nil)
        #expect(uid?.value == "1.2.840.10008.1.2")
    }
    
    @Test("Parse with null padding (common in DICOM)")
    func testParseWithNullPadding() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2\0")
        #expect(uid != nil)
        #expect(uid?.value == "1.2.840.10008.1.2")
    }
    
    @Test("Parse maximum length UID (64 characters)")
    func testParseMaximumLengthUID() {
        // Create a valid 64-character UID
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.2.1.111111111111111111111111111111111111")
        #expect(uid != nil)
        #expect(uid?.value.count == 64)
    }
    
    // MARK: - Validation Tests
    
    @Test("Reject empty string")
    func testRejectEmptyString() {
        #expect(DICOMUniqueIdentifier.parse("") == nil)
        #expect(DICOMUniqueIdentifier.parse("   ") == nil)
    }
    
    @Test("Reject UID exceeding maximum length")
    func testRejectOverlengthUID() {
        // 65 characters is too long
        let longUID = String(repeating: "1", count: 32) + "." + String(repeating: "2", count: 32)
        #expect(longUID.count == 65)
        #expect(DICOMUniqueIdentifier.parse(longUID) == nil)
    }
    
    @Test("Reject UID with leading period")
    func testRejectLeadingPeriod() {
        #expect(DICOMUniqueIdentifier.parse(".1.2.3") == nil)
    }
    
    @Test("Reject UID with trailing period")
    func testRejectTrailingPeriod() {
        #expect(DICOMUniqueIdentifier.parse("1.2.3.") == nil)
    }
    
    @Test("Reject UID with consecutive periods")
    func testRejectConsecutivePeriods() {
        #expect(DICOMUniqueIdentifier.parse("1..2.3") == nil)
        #expect(DICOMUniqueIdentifier.parse("1.2..3") == nil)
    }
    
    @Test("Reject UID with leading zeros in components")
    func testRejectLeadingZeros() {
        // "00" is invalid (leading zero)
        #expect(DICOMUniqueIdentifier.parse("1.02.3") == nil)
        #expect(DICOMUniqueIdentifier.parse("01.2.3") == nil)
        #expect(DICOMUniqueIdentifier.parse("1.2.03") == nil)
    }
    
    @Test("Accept single zero component")
    func testAcceptSingleZero() {
        // Single "0" is valid
        let uid = DICOMUniqueIdentifier.parse("1.0.2")
        #expect(uid != nil)
        #expect(uid?.components == ["1", "0", "2"])
    }
    
    @Test("Reject UID with invalid characters")
    func testRejectInvalidCharacters() {
        // Letters
        #expect(DICOMUniqueIdentifier.parse("1.2.A.3") == nil)
        
        // Spaces
        #expect(DICOMUniqueIdentifier.parse("1.2 .3") == nil)
        
        // Special characters
        #expect(DICOMUniqueIdentifier.parse("1.2-3.4") == nil)
        #expect(DICOMUniqueIdentifier.parse("1.2_3.4") == nil)
        #expect(DICOMUniqueIdentifier.parse("1.2+3.4") == nil)
    }
    
    // MARK: - Component Access Tests
    
    @Test("Root extraction for standard DICOM UID")
    func testRootExtractionDICOM() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.2")
        #expect(uid?.root == "1.2.840.10008")
    }
    
    @Test("Root extraction for non-DICOM UID")
    func testRootExtractionNonDICOM() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.113619.2.5.1762583153.215519.978957063.78")
        #expect(uid?.root == "1.2.840.113619")
    }
    
    @Test("Suffix extraction for standard DICOM UID")
    func testSuffixExtractionDICOM() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.2")
        #expect(uid?.suffix == "5.1.4.1.1.2")
    }
    
    @Test("Suffix extraction for non-DICOM UID")
    func testSuffixExtractionNonDICOM() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.113619.2.5.1762583153.215519.978957063.78")
        #expect(uid?.suffix == "2.5.1762583153.215519.978957063.78")
    }
    
    @Test("Suffix is nil for short UID")
    func testSuffixNilForShortUID() {
        let uid = DICOMUniqueIdentifier.parse("1.2.3.4")
        #expect(uid?.suffix == nil)
    }
    
    // MARK: - Type Detection Tests
    
    @Test("Detect standard DICOM UID")
    func testIsStandardDICOM() {
        let dicomUID = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        #expect(dicomUID?.isStandardDICOM == true)
        
        let nonDicomUID = DICOMUniqueIdentifier.parse("1.2.840.113619.2.5")
        #expect(nonDicomUID?.isStandardDICOM == false)
    }
    
    @Test("Detect Transfer Syntax UID")
    func testIsTransferSyntax() {
        // Implicit VR Little Endian
        let implicit = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        #expect(implicit?.isTransferSyntax == true)
        
        // Explicit VR Little Endian
        let explicit = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.1")
        #expect(explicit?.isTransferSyntax == true)
        
        // SOP Class (not transfer syntax)
        let sopClass = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.2")
        #expect(sopClass?.isTransferSyntax == false)
        
        // Potential false positive - UID starting with transfer syntax prefix but different meaning
        // 1.2.840.10008.1.20 is Storage Commitment SOP Class, NOT a transfer syntax
        let notTransferSyntax = DICOMUniqueIdentifier.parse("1.2.840.10008.1.20.1")
        #expect(notTransferSyntax?.isTransferSyntax == false)
    }
    
    @Test("Detect SOP Class UID")
    func testIsSOPClass() {
        // CT Image Storage
        let ctImage = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.2")
        #expect(ctImage?.isSOPClass == true)
        
        // Transfer Syntax (not SOP Class)
        let transferSyntax = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        #expect(transferSyntax?.isSOPClass == false)
    }

    @Test("SOP Class and Transfer Syntax sets are the PS3.6 2026a Table A-1 registry")
    func testRegistrySetsMatchTableA1() {
        #expect(DICOMUniqueIdentifier.sopClassUIDs.count == 311)
        #expect(DICOMUniqueIdentifier.transferSyntaxUIDs.count == 63)
        // SOP Classes the old prefix heuristic missed.
        for uid in ["1.2.840.10008.1.1",          // Verification
                    "1.2.840.10008.1.20.1",       // Storage Commitment Push Model
                    "1.2.840.10008.5.1.1.1",      // Basic Film Session
                    "1.2.840.10008.1.42",         // Substance Administration Logging
                    "1.2.840.10008.1.3.10",       // Media Storage Directory Storage
                    "1.2.840.10008.5.1.4.1.1.2"] { // CT Image Storage
            #expect(DICOMUniqueIdentifier.parse(uid)?.isSOPClass == true, Comment(rawValue: uid))
        }
        // UIDs the old heuristic wrongly called SOP Classes.
        for uid in ["1.2.840.10008.1.40.1",              // Procedural Event Logging SOP Instance
                    "1.2.840.10008.5.1.4.34.5",          // UPS Global Subscription SOP Instance
                    "1.2.840.10008.5.1.4.34.6",          // UPS Service Class
                    "1.2.840.10008.3.1.2.1.4",           // Detached Patient Management Meta SOP Class
                    "1.2.840.10008.5.1.4.1.1.201.1.1"] { // Storage Management SOP Instance
            #expect(DICOMUniqueIdentifier.parse(uid)?.isSOPClass == false, Comment(rawValue: uid))
        }
        // Papyrus 3 is a (retired) Transfer Syntax outside the 1.2.840.10008.1.2 prefix.
        #expect(DICOMUniqueIdentifier.parse("1.2.840.10008.1.20")?.isTransferSyntax == true)
        #expect(DICOMUniqueIdentifier.parse("1.2.840.10008.1.20.1")?.isTransferSyntax == false)
        #expect(DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.4.112")?.isTransferSyntax == true) // JPEG XL
        #expect(DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.99")?.isTransferSyntax == false)
        #expect(DICOMUniqueIdentifier.sopClassUIDs.isDisjoint(with: DICOMUniqueIdentifier.transferSyntaxUIDs))
    }
    
    // MARK: - Multiple Values Tests
    
    @Test("Parse multiple UIDs")
    func testParseMultiple() {
        let uids = DICOMUniqueIdentifier.parseMultiple("1.2.840.10008.1.2\\1.2.840.10008.1.2.1")
        #expect(uids != nil)
        #expect(uids?.count == 2)
        #expect(uids?[0].value == "1.2.840.10008.1.2")
        #expect(uids?[1].value == "1.2.840.10008.1.2.1")
    }
    
    @Test("Parse single UID as multiple returns single element")
    func testParseSingleAsMultiple() {
        let uids = DICOMUniqueIdentifier.parseMultiple("1.2.840.10008.1.2")
        #expect(uids != nil)
        #expect(uids?.count == 1)
    }
    
    @Test("Parse multiple with invalid UID returns nil")
    func testParseMultipleWithInvalid() {
        let uids = DICOMUniqueIdentifier.parseMultiple("1.2.840.10008.1.2\\invalid.uid")
        #expect(uids == nil)
    }
    
    // MARK: - String Output Tests
    
    @Test("DICOM string format")
    func testDicomString() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        #expect(uid?.dicomString == "1.2.840.10008.1.2")
    }
    
    @Test("CustomStringConvertible")
    func testDescription() {
        let uid = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        #expect(String(describing: uid!) == "1.2.840.10008.1.2")
    }
    
    // MARK: - ExpressibleByStringLiteral Tests
    
    @Test("Create UID from string literal")
    func testStringLiteral() {
        let uid: DICOMUniqueIdentifier = "1.2.840.10008.1.2"
        #expect(uid.value == "1.2.840.10008.1.2")
    }
    
    // MARK: - Equatable/Hashable Tests
    
    @Test("Equality comparison")
    func testEquality() {
        let uid1 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        let uid2 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        let uid3 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.1")
        
        #expect(uid1 == uid2)
        #expect(uid1 != uid3)
    }
    
    @Test("Hash value consistency")
    func testHashable() {
        let uid1 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")!
        let uid2 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")!
        
        #expect(uid1.hashValue == uid2.hashValue)
        
        // Can be used in sets
        let set: Set<DICOMUniqueIdentifier> = [uid1, uid2]
        #expect(set.count == 1)
    }
    
    // MARK: - Comparable Tests
    
    @Test("Comparable - lexicographic ordering")
    func testComparable() {
        let uid1 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")!
        let uid2 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.1")!
        
        #expect(uid1 < uid2)
        #expect(uid2 > uid1)
    }
    
    @Test("Comparable - equal UIDs")
    func testComparableEqual() {
        let uid1 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")!
        let uid2 = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")!
        
        #expect(!(uid1 < uid2))
        #expect(!(uid2 < uid1))
    }
    
    // MARK: - Codable Tests
    
    @Test("Encode and decode UID")
    func testCodable() throws {
        let original = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")!
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DICOMUniqueIdentifier.self, from: data)
        
        #expect(original == decoded)
    }
    
    @Test("Decode invalid UID throws error")
    func testDecodeInvalid() {
        let json = "\"invalid..uid\""
        let data = json.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DICOMUniqueIdentifier.self, from: data)
        }
    }
    
    // MARK: - Constants Tests
    
    @Test("Maximum length constant")
    func testMaximumLengthConstant() {
        #expect(DICOMUniqueIdentifier.maximumLength == 64)
    }
    
    @Test("DICOM root constant")
    func testDICOMRootConstant() {
        #expect(DICOMUniqueIdentifier.dicomRoot == "1.2.840.10008")
    }
    
    // MARK: - Real-World UID Tests
    
    @Test("Common Transfer Syntax UIDs")
    func testCommonTransferSyntaxUIDs() {
        // Implicit VR Little Endian
        let implicit = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2")
        #expect(implicit?.isTransferSyntax == true)
        
        // Explicit VR Little Endian
        let explicitLE = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.1")
        #expect(explicitLE?.isTransferSyntax == true)
        
        // Explicit VR Big Endian
        let explicitBE = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.2")
        #expect(explicitBE?.isTransferSyntax == true)
        
        // JPEG Baseline
        let jpegBaseline = DICOMUniqueIdentifier.parse("1.2.840.10008.1.2.4.50")
        #expect(jpegBaseline?.isTransferSyntax == true)
    }
    
    @Test("Common SOP Class UIDs")
    func testCommonSOPClassUIDs() {
        // CT Image Storage
        let ct = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.2")
        #expect(ct?.isSOPClass == true)
        
        // MR Image Storage
        let mr = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.4")
        #expect(mr?.isSOPClass == true)
        
        // Secondary Capture Image Storage
        let sc = DICOMUniqueIdentifier.parse("1.2.840.10008.5.1.4.1.1.7")
        #expect(sc?.isSOPClass == true)
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Parse and reformat round-trip")
    func testRoundTrip() {
        let testCases = [
            "1.2.840.10008.1.2",
            "1.2.840.10008.5.1.4.1.1.2",
            "1.2.840.113619.2.5.1762583153.215519.978957063.78",
            "1.0.2.0.3",
            "1"
        ]
        
        for original in testCases {
            let parsed = DICOMUniqueIdentifier.parse(original)
            #expect(parsed != nil)
            #expect(parsed?.value == original)
            #expect(parsed?.dicomString == original)
        }
    }
}
