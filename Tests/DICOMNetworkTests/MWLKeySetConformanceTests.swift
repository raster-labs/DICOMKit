import XCTest
import DICOMCore
@testable import DICOMNetwork

/// MWL request key set and response decoding against PS3.4 Table K.6-1
/// (DICOM_TAG_AUDIT_PHASE2_FINDINGS.md §1).
final class MWLKeySetConformanceTests: XCTestCase {

    // MARK: - Helpers (implicit VR little endian)

    private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    private func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
    private func elem(_ g: UInt16, _ e: UInt16, _ value: Data) -> Data {
        var v = value
        if v.count % 2 != 0 { v.append(0x20) }
        var d = Data()
        d.append(le16(g)); d.append(le16(e)); d.append(le32(UInt32(v.count))); d.append(v)
        return d
    }
    private func elem(_ g: UInt16, _ e: UInt16, _ value: String) -> Data {
        elem(g, e, value.data(using: .isoLatin1)!)
    }
    private func sequence(_ g: UInt16, _ e: UInt16, items: [Data]) -> Data {
        var d = Data()
        d.append(le16(g)); d.append(le16(e)); d.append(le32(0xFFFFFFFF))
        for item in items {
            d.append(Data([0xFE, 0xFF, 0x00, 0xE0])); d.append(le32(0xFFFFFFFF))
            d.append(item)
            d.append(Data([0xFE, 0xFF, 0x0D, 0xE0])); d.append(le32(0))
        }
        d.append(Data([0xFE, 0xFF, 0xDD, 0xE0])); d.append(le32(0))
        return d
    }
    private func code(_ value: String, _ scheme: String, _ meaning: String) -> Data {
        var d = Data()
        d.append(elem(0x0008, 0x0100, value)); d.append(elem(0x0008, 0x0102, scheme)); d.append(elem(0x0008, 0x0104, meaning))
        return d
    }

    private func parse(_ data: Data) -> WorklistItem {
        var offset = 0
        var parsed = DICOMModalityWorklistService.MWLParsedDataSet()
        DICOMModalityWorklistService.parseMWLDataSet(
            data: data, offset: &offset, end: data.count, isExplicitVR: false, into: &parsed)
        return WorklistItem(attributes: parsed.attributes, sequences: parsed.sequences)
    }

    // MARK: - 1b. Return keys

    func test_default_requestsCodeSequencesAndReferencedStudy() {
        let keys = WorklistQueryKeys.default()
        XCTAssertEqual(keys.allKeys[Tag(group: 0x0032, element: 0x1064)], "", "Requested Procedure Code Sequence (1C)")
        XCTAssertEqual(keys.allKeys[Tag(group: 0x0008, element: 0x1110)], "", "Referenced Study Sequence (2)")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0008)], "", "Scheduled Protocol Code Sequence (1C)")
    }

    func test_default_requestsRemainingType2ReturnKeys() {
        let keys = WorklistQueryKeys.default()
        let root: [(UInt16, UInt16, String)] = [
            (0x0040, 0x1003, "Requested Procedure Priority"), (0x0010, 0x1030, "Patient's Weight"),
            (0x0010, 0x21C0, "Pregnancy Status"), (0x0010, 0x2000, "Medical Alerts"),
            (0x0010, 0x2110, "Allergies"), (0x0038, 0x0050, "Special Needs"), (0x0038, 0x0500, "Patient State"),
            (0x0038, 0x0010, "Admission ID"), (0x0038, 0x0300, "Current Patient Location"),
            (0x0032, 0x1032, "Requesting Physician"), (0x0040, 0x1004, "Patient Transport Arrangements"),
        ]
        for (g, e, name) in root {
            XCTAssertNotNil(keys.allKeys[Tag(group: g, element: e)], "\(name) missing from root return keys")
        }
        let sps: [(UInt16, UInt16, String)] = [
            (0x0040, 0x0011, "SPS Location"), (0x0032, 0x1070, "Requested Contrast Agent"), (0x0040, 0x0012, "Pre-Medication"),
        ]
        for (g, e, name) in sps {
            XCTAssertNotNil(keys.allSPSKeys[Tag(group: g, element: e)], "\(name) missing from SPS return keys")
        }
    }

    // MARK: - 1a. Generic matching keys

    func test_genericMatchingKeys() {
        let keys = WorklistQueryKeys()
            .matching(Tag(group: 0x0040, element: 0x1001), "RP123")
            .spsMatching(Tag(group: 0x0040, element: 0x0010), "CT_ROOM_1")
        XCTAssertEqual(keys.allKeys[Tag(group: 0x0040, element: 0x1001)], "RP123")
        XCTAssertEqual(keys.allSPSKeys[Tag(group: 0x0040, element: 0x0010)], "CT_ROOM_1")
    }

    // MARK: - 1c. Nested sequences

    func test_codeSequencesAreKeptApart() {
        var sps = Data()
        sps.append(elem(0x0008, 0x0060, "CT"))
        sps.append(sequence(0x0040, 0x0008, items: [code("CTCHEST", "99LOCAL", "Chest protocol")]))

        var data = Data()
        data.append(elem(0x0010, 0x0010, "DOE^JOHN"))
        data.append(sequence(0x0032, 0x1064, items: [code("71020", "CPT", "Chest X-ray 2 views")]))
        data.append(sequence(0x0008, 0x1110, items: [{
            var d = Data()
            d.append(elem(0x0008, 0x1150, "1.2.840.10008.3.1.2.3.1"))
            d.append(elem(0x0008, 0x1155, "1.2.3.4.5"))
            return d
        }()]))
        data.append(sequence(0x0040, 0x0100, items: [sps]))

        let item = parse(data)
        XCTAssertEqual(item.patientName, "DOE^JOHN")
        XCTAssertEqual(item.modality, "CT", "SPS attributes still flatten into the root")
        XCTAssertEqual(item.requestedProcedureCode?.codeValue, "71020")
        XCTAssertEqual(item.requestedProcedureCode?.codeMeaning, "Chest X-ray 2 views")
        XCTAssertEqual(item.scheduledProtocolCodes.first?.codeValue, "CTCHEST",
                       "a second Code Value inside the SPS item must not overwrite the first")
        XCTAssertEqual(item.referencedStudies.first?.sopInstanceUID, "1.2.3.4.5")
        XCTAssertNil(item.attributes[Tag(group: 0x0008, element: 0x0100)], "code values are not in the flat map")
    }

    // MARK: - 1c. Character set

    func test_latin1PatientNameDecodesWithSpecificCharacterSet() {
        var data = Data()
        data.append(elem(0x0008, 0x0005, "ISO_IR 100"))
        data.append(elem(0x0010, 0x0010, "MÜLLER^JÖRG"))     // encoded as ISO-8859-1 by the helper
        let item = parse(data)
        XCTAssertEqual(item.patientName, "MÜLLER^JÖRG")
    }

    func test_utf8PatientNameDecodesWithISO_IR_192() {
        var data = Data()
        data.append(elem(0x0008, 0x0005, "ISO_IR 192"))
        data.append(elem(0x0010, 0x0010, "山田^太郎".data(using: .utf8)!))
        let item = parse(data)
        XCTAssertEqual(item.patientName, "山田^太郎")
    }

    func test_missingCharacterSetAssumesLatin1() {
        var data = Data()
        data.append(elem(0x0010, 0x0010, "MÜLLER^JÖRG"))
        XCTAssertEqual(parse(data).patientName, "MÜLLER^JÖRG")
    }

    // MARK: - Identifier character set (PS3.5 6.1.2, PS3.4 C.2.2.2.1, K.6.1.2.2)

    private let implicitLE = "1.2.840.10008.1.2"
    private let charsetTag = Tag(group: 0x0008, element: 0x0005)

    /// Encodes the Identifier (implicit VR LE) and parses it back to raw tag → bytes.
    private func identifier(_ keys: WorklistQueryKeys, override: String? = nil) -> [Tag: Data] {
        let data = DICOMModalityWorklistService.buildQueryIdentifier(
            queryKeys: keys, transferSyntax: implicitLE, specificCharacterSet: override)
        var offset = 0
        var parsed = DICOMModalityWorklistService.MWLParsedDataSet()
        DICOMModalityWorklistService.parseMWLDataSet(
            data: data, offset: &offset, end: data.count, isExplicitVR: false, into: &parsed)
        return parsed.attributes
    }

    func test_identifier_latin1PatientNameDeclaresISO_IR_100AndKeepsEveryByte() {
        let attrs = identifier(WorklistQueryKeys.default().patientName("MÜLLER^JÖRG"))
        XCTAssertEqual(attrs[charsetTag].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 100")
        let expected = "MÜLLER^JÖRG".data(using: .isoLatin1)! + Data([0x20])   // 11 bytes, padded to 12
        XCTAssertEqual(attrs[.patientName], expected,
                       "the key must reach the wire in full — an ASCII failure would send a Universal Match")
    }

    func test_identifier_pureASCIIOmitsSpecificCharacterSet() {
        let attrs = identifier(WorklistQueryKeys.default().patientName("DOE^JOHN"))
        XCTAssertNil(attrs[charsetTag],
                     "PS3.4 C.2.2.2: (0008,0005) shall not have a zero length value; K.4.1.1.3.1: not included unless an expanded/replacement set is used")
        XCTAssertEqual(attrs[.patientName], Data("DOE^JOHN".utf8))
        // Even an explicit empty return key is dropped for ISO 646 keys.
        let withKey = identifier(WorklistQueryKeys.default().patientName("DOE^JOHN").specificCharacterSet(""))
        XCTAssertNil(withKey[charsetTag])
    }

    func test_identifier_spsTextKeyDrivesTheCharacterSet() {
        // Non-ASCII only inside the (0040,0100) item — Scheduled Performing Physician's Name.
        let attrs = identifier(WorklistQueryKeys.default().scheduledPerformingPhysician("MÜLLER*"))
        XCTAssertEqual(attrs[charsetTag].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 100")
        XCTAssertEqual(attrs[Tag(group: 0x0040, element: 0x0006)], "MÜLLER*".data(using: .isoLatin1)! + Data([0x20]))
    }

    func test_identifier_nonLatin1KeyChoosesUTF8() {
        let attrs = identifier(WorklistQueryKeys.default().patientName("山田^太郎"))
        XCTAssertEqual(attrs[charsetTag].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 192")
        // 13 UTF-8 bytes, space-padded to 14 (PS3.5 §6.2)
        XCTAssertEqual(attrs[.patientName], Data("山田^太郎".utf8) + Data([0x20]))
    }

    func test_identifier_overrideWins() {
        let viaKeys = identifier(WorklistQueryKeys.default().patientName("MÜLLER^JÖRG").specificCharacterSet("ISO_IR 192"))
        XCTAssertEqual(viaKeys[charsetTag].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 192")
        XCTAssertEqual(viaKeys[.patientName], Data("MÜLLER^JÖRG".utf8) + Data([0x20]))

        let viaConfig = identifier(WorklistQueryKeys.default().patientName("DOE^JOHN"), override: "ISO_IR 100")
        XCTAssertEqual(viaConfig[charsetTag].flatMap { String(data: $0, encoding: .ascii) }, "ISO_IR 100")
    }

    func test_identifier_nonTextVRStaysASCIIAndNeverGoesEmpty() {
        let attrs = identifier(WorklistQueryKeys.default().modality("CT").accessionNumber("ACC-1"))
        XCTAssertEqual(attrs[Tag(group: 0x0008, element: 0x0060)], Data("CT".utf8))
        XCTAssertEqual(attrs[.accessionNumber], Data("ACC-1 ".utf8))
        XCTAssertNil(attrs[charsetTag], "default repertoire: no (0008,0005) (PS3.4 C.2.2.2, K.4.1.1.3.1)")
    }
}
