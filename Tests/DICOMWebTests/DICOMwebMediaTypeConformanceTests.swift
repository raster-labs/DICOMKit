import Testing
import Foundation
@testable import DICOMWeb

/// PS3.18 2026a media type rules: parameter quoting (8.7.1 / RFC 2045), the bulk data media
/// type per transfer syntax (Tables 8.7.3-4, 8.7.3-5) and the media types for pixel data
/// resources (Table 10.4.4-1).
@Suite("DICOMweb media type conformance (PS3.18 §8.7)")
struct DICOMwebMediaTypeConformanceTests {

    @Test("A parameter value containing '/' is quoted: type=\"application/dicom\"")
    func testTypeParameterIsQuoted() {
        let mt = DICOMMediaType.multipartRelated(boundary: "abc", type: .dicom)
        #expect(mt.description == "multipart/related; boundary=abc; type=\"application/dicom\"")
        #expect(DICOMMediaType.parse(mt.description)?.parameters["type"] == "application/dicom")
        // a UID value has no tspecials and stays bare
        #expect(DICOMMediaType.dicom(transferSyntax: "1.2.840.10008.1.2.1").description
                == "application/dicom; transfer-syntax=1.2.840.10008.1.2.1")
    }

    @Test("Table 8.7.3-5: compressed bulk data media type per transfer syntax")
    func testBulkDataMediaTypes() {
        let expected: [(String, DICOMMediaType)] = [
            ("1.2.840.10008.1.2.1", .octetStream), ("1.2.840.10008.1.2.1.98", .octetStream),
            ("1.2.840.10008.1.2.4.50", .jpeg), ("1.2.840.10008.1.2.4.70", .jpeg),
            ("1.2.840.10008.1.2.5", .dicomRLE), ("1.2.840.10008.1.2.8.1", .xDeflate),
            ("1.2.840.10008.1.2.4.80", .jpegLS), ("1.2.840.10008.1.2.4.90", .jp2),
            ("1.2.840.10008.1.2.4.92", .jpx), ("1.2.840.10008.1.2.4.201", .jphc),
            ("1.2.840.10008.1.2.4.110", .jxl), ("1.2.840.10008.1.2.4.100", .mpeg),
            ("1.2.840.10008.1.2.4.102.1", .mp4), ("1.2.840.10008.1.2.4.107", .h265),
        ]
        for (uid, mt) in expected {
            #expect(DICOMMediaType.bulkDataMediaType(forTransferSyntax: uid) == mt, "\(uid)")
        }
        // Implicit VR Little Endian shall not be used with Web Services (8.7.3)
        #expect(DICOMMediaType.bulkDataMediaType(forTransferSyntax: "1.2.840.10008.1.2") == nil)
    }

    @Test("The media type names of 8.7.3.5 and Table 8.7.4-1 are spelled as the standard spells them")
    func testNames() {
        #expect(DICOMMediaType.dicomRLE.description == "image/dicom-rle")
        #expect(DICOMMediaType.jpx.description == "image/jpx")
        #expect(DICOMMediaType.jxl.description == "image/jxl")
        #expect(DICOMMediaType.xDeflate.description == "application/x-deflate")
        // media types are case-insensitive (RFC 2045 §5.1); DICOMMediaType normalises to lowercase
        #expect(DICOMMediaType.h265.description.lowercased() == "video/h265")
    }
}
