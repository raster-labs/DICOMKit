import Foundation
import XCTest
import DICOMCore
import DICOMKit

final class M12CheckedValueLengthTests: XCTestCase {
    private let privateValueTag = Tag(group: 0x0011, element: 0x1001)

    func testNested64KiBShortVRUsesFullUNValueAndPreservesFollowingElement() throws {
        // A US value can exceed the short length field after reading an implicit-VR dataset.
        // Use non-palindromic words to verify the little-endian payload required for UN.
        var input = Data()
        var expected = Data()
        for _ in 0..<32_768 {
            input.append(contentsOf: [0x12, 0x34])
            expected.append(contentsOf: [0x34, 0x12])
        }
        let large = DataElement(tag: privateValueTag, vr: .US, length: 65_536, valueData: input, byteOrder: .bigEndian)
        let sibling = DataElement.string(tag: Tag(group: 0x0011, element: 0x1002), vr: .LO, value: "ok")
        let sequence = DataElement(tag: .referencedSeriesSequence, vr: .SQ, length: UInt32.max, valueData: Data(),
                                   sequenceItems: [SequenceItem(elements: [large, sibling])])
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let wire = try writer.serializeCheckedElement(sequence)
        // 12-byte SQ header + 8-byte Item header, followed by the UN element.
        let header = Data([0x11, 0, 1, 0x10, 0x55, 0x4e, 0, 0, 0, 0, 1, 0])
        XCTAssertEqual(wire.count, 20 + header.count + expected.count + 10)
        guard wire.count == 20 + header.count + expected.count + 10 else { return }
        XCTAssertEqual(wire.subdata(in: 20..<32), header)
        XCTAssertEqual(wire.subdata(in: 32..<(32 + expected.count)), expected)
        XCTAssertEqual(wire.suffix(10), Data([0x11, 0, 2, 0x10, 0x4c, 0x4f, 2, 0, 0x6f, 0x6b]))

        let bigEndianWire = try DICOMWriter(byteOrder: .bigEndian, explicitVR: true).serializeCheckedElement(large)
        XCTAssertEqual(bigEndianWire.prefix(12), Data([0, 0x11, 0x10, 1, 0x55, 0x4e, 0, 0, 0, 1, 0, 0]))
        XCTAssertEqual(bigEndianWire.dropFirst(12), expected)
    }

    func testPaddedSizeControlsShortVRBoundary() throws {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        for count in [65_533, 65_535] {
            // A multi-valued DS with one-digit components and an odd logical byte count.
            var values = Data(repeating: 0x31, count: count)
            for index in stride(from: 1, to: count, by: 2) { values[index] = 0x5c }
            let element = DataElement(tag: privateValueTag, vr: .DS, length: UInt32(count), valueData: values)
            let wire = try writer.serializeCheckedElement(element)
            let header: Data = count == 65_533 ? Data([0x44, 0x53, 0xfe, 0xff])
                                               : Data([0x55, 0x4e, 0, 0, 0, 0, 1, 0])
            XCTAssertEqual(wire.dropFirst(4).prefix(header.count), header)
            XCTAssertEqual(wire.dropFirst(4 + header.count), values + Data([0x20]))
        }
    }

    func testCheckedWriterRejectsUnrepresentableOrMismatchedOrdinaryValues() throws {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        for length in [UInt32.max, UInt32(2)] {
            let invalid = DataElement(tag: privateValueTag, vr: .LO, length: length, valueData: Data())
            XCTAssertThrowsError(try writer.serializeCheckedElement(invalid)) { error in
                guard case .parsingFailed = error as? DICOMError else { return XCTFail(String(describing: error)) }
            }
        }
        let oversizedMeta = DataElement(tag: .transferSyntaxUID, vr: .UI, length: 65_536,
                                       valueData: Data(repeating: 0x30, count: 65_536))
        XCTAssertThrowsError(try writer.serializeCheckedElement(oversizedMeta)) { error in
            guard case .limitExceeded = error as? DICOMError else { return XCTFail(String(describing: error)) }
        }
    }

    func testFileWriteChecksFileMetaBeforeComputingItsGroupLength() throws {
        let valid = DICOMFile.create(dataSet: DataSet())
        let read = try DICOMFile.read(from: valid.write())
        var body = read.fileMetaInformation
        let declared = body.uint32(for: .fileMetaInformationGroupLength)
        body.remove(tag: .fileMetaInformationGroupLength)
        XCTAssertEqual(declared.map(Int.init), try body.writeChecked().count)

        let invalidUID = String(repeating: "1", count: 65_536)
        var meta = valid.fileMetaInformation
        meta.setString(invalidUID, for: .transferSyntaxUID, vr: .UI)
        let edited = DICOMFile(fileMetaInformation: meta, dataSet: valid.dataSet)
        let created = DICOMFile.create(dataSet: DataSet(), transferSyntaxUID: invalidUID)
        for file in [edited, created] {
            XCTAssertThrowsError(try file.write()) { error in
                guard case .limitExceeded = error as? DICOMError else { return XCTFail(String(describing: error)) }
            }
        }
    }
}
