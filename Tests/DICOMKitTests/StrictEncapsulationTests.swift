import Foundation
import Testing
import DICOMCore
@testable import DICOMKit

@Suite("Strict encapsulated Pixel Data envelope")
struct StrictEncapsulationTests {
    func fixture() throws -> Data {
        var ds = DataSet()
        ds[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: 0xffffffff, valueData: Data(),
            encapsulatedFragments: [Data([1, 2]), Data([3, 4])], encapsulatedOffsetTable: [0, 10])
        return try DICOMFile.create(dataSet: ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4", transferSyntaxUID: TransferSyntax.jpegBaseline.uid).write()
    }
    @Test func malformedEnvelopesFailClosed() throws {
        let original = try fixture()
        _ = try DICOMFile.read(from: original, options: .init(strictEncapsulation: true))
        #expect(throws: (any Error).self) {
            try DICOMFile.read(from: original, options: .init(strictEncapsulation: true,
                allowedTransferSyntaxUIDs: [TransferSyntax.jpegLSLossless.uid]))
        }
        let tag = Data([0xe0, 0x7f, 0x10, 0]) // Pixel Data
        let start = try #require(original.range(of: tag)).lowerBound
        var cases: [Data] = [Data(original.dropLast(8))]
        for (index, byte) in [(start + 4, UInt8(ascii: "U")), (start + 6, 1),
                              (start + 16, 7), (start + 20, 1), (start + 24, 9),
                              (start + 32, 1), (original.count - 4, 1)] {
            var value = original; value[index] = byte; cases.append(value)
        }
        for bad in cases {
            #expect(throws: (any Error).self) {
                try DICOMFile.read(from: bad, options: .init(strictEncapsulation: true))
            }
        }
        #expect(throws: (any Error).self) {
            try DICOMFile.read(from: original, options: .init(strictEncapsulation: true, maximumEncapsulatedBytes: 11))
        }
    }
}
