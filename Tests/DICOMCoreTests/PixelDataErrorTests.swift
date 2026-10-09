import Testing
import Foundation
@testable import DICOMCore

@Suite("PixelDataError Tests")
struct PixelDataErrorTests {
    
    // MARK: - Error Creation Tests
    
    @Test("missingDescriptor error has correct description")
    func testMissingDescriptorDescription() {
        let error = PixelDataError.missingDescriptor
        
        #expect(error.description.contains("Missing required pixel data attributes"))
        #expect(error.explanation.contains("missing required attributes"))
    }
    
    @Test("missingAttributes error lists attribute names")
    func testMissingAttributesDescription() {
        let attributes = ["Rows (0028,0010)", "Columns (0028,0011)", "Bits Allocated (0028,0100)"]
        let error = PixelDataError.missingAttributes(attributes)
        
        #expect(error.description.contains("Rows (0028,0010)"))
        #expect(error.description.contains("Columns (0028,0011)"))
        #expect(error.description.contains("Bits Allocated (0028,0100)"))
        #expect(error.explanation.contains("Rows (0028,0010)"))
        #expect(error.explanation.contains("malformed DICOM file"))
    }
    
    @Test("missingAttributes error with single attribute")
    func testMissingAttributesSingleDescription() {
        let error = PixelDataError.missingAttributes(["Rows (0028,0010)"])
        
        #expect(error.description.contains("Rows (0028,0010)"))
        #expect(error.explanation.contains("missing the following required attributes"))
    }
    
    // MARK: - Non-Image SOP Class Error Tests
    
    @Test("nonImageSOPClass error with SOP class name")
    func testNonImageSOPClassWithName() {
        let attributes = ["Rows (0028,0010)", "Columns (0028,0011)"]
        let error = PixelDataError.nonImageSOPClass(
            missingAttributes: attributes,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11",
            sopClassName: "Basic Text SR Storage"
        )
        
        #expect(error.description.contains("Non-image DICOM object"))
        #expect(error.description.contains("Basic Text SR Storage"))
        #expect(error.description.contains("Rows (0028,0010)"))
        #expect(error.explanation.contains("Basic Text SR Storage"))
        #expect(error.explanation.contains("non-image object"))
        #expect(error.explanation.contains("Structured Reports"))
    }
    
    @Test("nonImageSOPClass error with SOP class UID only")
    func testNonImageSOPClassWithUIDOnly() {
        let attributes = ["Bits Allocated (0028,0100)"]
        let error = PixelDataError.nonImageSOPClass(
            missingAttributes: attributes,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.88.33",
            sopClassName: nil
        )
        
        #expect(error.description.contains("SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.33"))
        #expect(error.description.contains("Bits Allocated (0028,0100)"))
        #expect(error.explanation.contains("SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.33"))
    }
    
    @Test("nonImageSOPClass error without SOP class info")
    func testNonImageSOPClassWithoutInfo() {
        let attributes = ["Rows (0028,0010)", "Columns (0028,0011)", "Bits Allocated (0028,0100)"]
        let error = PixelDataError.nonImageSOPClass(
            missingAttributes: attributes,
            sopClassUID: nil,
            sopClassName: nil
        )
        
        #expect(error.description.contains("Non-image DICOM object"))
        #expect(error.description.contains("Rows (0028,0010)"))
        #expect(error.description.contains("Columns (0028,0011)"))
        #expect(error.description.contains("Bits Allocated (0028,0100)"))
        #expect(error.explanation.contains("non-image object"))
        #expect(error.explanation.contains("Pixel data extraction is not applicable"))
    }
    
    @Test("nonImageSOPClass error explanation mentions common non-image types")
    func testNonImageSOPClassExplanationContent() {
        let error = PixelDataError.nonImageSOPClass(
            missingAttributes: ["Rows (0028,0010)"],
            sopClassUID: nil,
            sopClassName: nil
        )
        
        #expect(error.explanation.contains("Structured Reports"))
        #expect(error.explanation.contains("Key Object Selection"))
        #expect(error.explanation.contains("Presentation States"))
    }
    
    @Test("missingPixelData error has correct description")
    func testMissingPixelDataDescription() {
        let error = PixelDataError.missingPixelData
        
        #expect(error.description.contains("No pixel data element"))
        #expect(error.explanation.contains("does not contain any pixel data"))
    }
    
    @Test("missingTransferSyntax error has correct description")
    func testMissingTransferSyntaxDescription() {
        let error = PixelDataError.missingTransferSyntax
        
        #expect(error.description.contains("Transfer syntax UID is missing"))
        #expect(error.explanation.contains("Transfer Syntax UID is not"))
    }
    
    @Test("unsupportedTransferSyntax error includes UID")
    func testUnsupportedTransferSyntaxDescription() {
        let uid = "1.2.840.10008.1.2.4.80"
        let error = PixelDataError.unsupportedTransferSyntax(uid)
        
        #expect(error.description.contains(uid))
        #expect(error.explanation.contains("not currently supported"))
        #expect(error.transferSyntaxName == "JPEG-LS Lossless Image Compression")
    }

    @Test("unsupportedTransferSyntax explanation names the syntax and lists what this build decodes")
    func testUnsupportedTransferSyntaxExplanationIsRegistryDriven() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.80")
        #expect(error.explanation.contains("(JPEG-LS Lossless Image Compression)"))
        #expect(error.explanation.contains("This build can decode: "))
        // The list is derived from the registry, not typed in: every registered
        // decoder's display name must appear.
        for uid in CodecRegistry.shared.supportedTransferSyntaxes {
            if let name = TransferSyntax.from(uid: uid)?.displayName {
                #expect(error.explanation.contains(name), "missing \(name)")
            }
        }
        // An unknown UID has no name to show after it.
        let unknown = PixelDataError.unsupportedTransferSyntax("1.2.3.4")
        #expect(unknown.explanation.contains("'1.2.3.4' which is not currently supported"))
        #expect(unknown.transferSyntaxName == nil)
    }
    
    @Test("frameExtractionFailed error includes frame index")
    func testFrameExtractionFailedDescription() {
        let error = PixelDataError.frameExtractionFailed(frameIndex: 5)
        
        #expect(error.description.contains("frame 5"))
        #expect(error.explanation.contains("frame 5"))
    }
    
    @Test("decodingFailed error includes frame index and reason")
    func testDecodingFailedDescription() {
        let error = PixelDataError.decodingFailed(frameIndex: 3, reason: "Invalid JPEG header")
        
        #expect(error.description.contains("frame 3"))
        #expect(error.description.contains("Invalid JPEG header"))
        #expect(error.explanation.contains("failed to decompress"))
    }
    
    // MARK: - Transfer Syntax Name Tests
    
    @Test("transferSyntaxName returns correct name for JPEG-LS Lossless")
    func testTransferSyntaxNameJPEGLSLossless() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.80")
        #expect(error.transferSyntaxName == "JPEG-LS Lossless Image Compression")
    }
    
    @Test("transferSyntaxName returns correct name for JPEG-LS Near-Lossless")
    func testTransferSyntaxNameJPEGLSNearLossless() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.81")
        #expect(error.transferSyntaxName == "JPEG-LS Lossy (Near-Lossless) Image Compression")
    }
    
    @Test("transferSyntaxName returns correct name for JPEG 2000 Part 2 Lossless Only")
    func testTransferSyntaxNameJPEG2000Part2Lossless() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.92")
        #expect(error.transferSyntaxName == "JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only)")
    }

    @Test("transferSyntaxName returns correct name for JPEG 2000 Part 2 Lossy")
    func testTransferSyntaxNameJPEG2000Part2Lossy() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.93")
        #expect(error.transferSyntaxName == "JPEG 2000 Part 2 Multi-component Image Compression")
    }

    @Test("transferSyntaxName returns correct name for HTJ2K Lossless Only")
    func testTransferSyntaxNameHTJPEG2000Lossless() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.201")
        #expect(error.transferSyntaxName == "High-Throughput JPEG 2000 Image Compression (Lossless Only)")
    }

    @Test("transferSyntaxName returns correct name for HTJ2K Lossless Only (RPCL)")
    func testTransferSyntaxNameHTJPEG2000RPCL() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.202")
        #expect(error.transferSyntaxName == "High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)")
    }

    @Test("transferSyntaxName returns correct name for HTJ2K Lossy")
    func testTransferSyntaxNameHTJPEG2000Lossy() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.840.10008.1.2.4.203")
        #expect(error.transferSyntaxName == "High-Throughput JPEG 2000 Image Compression")
    }
    
    @Test("transferSyntaxName returns nil for unknown UID")
    func testTransferSyntaxNameUnknown() {
        let error = PixelDataError.unsupportedTransferSyntax("1.2.3.4.5.6.7")
        #expect(error.transferSyntaxName == nil)
    }
    
    @Test("transferSyntaxName returns nil for non-unsupportedTransferSyntax errors")
    func testTransferSyntaxNameNonApplicable() {
        let error = PixelDataError.missingDescriptor
        #expect(error.transferSyntaxName == nil)
    }
    
    // MARK: - Error Conformance Tests
    
    @Test("PixelDataError conforms to Error protocol")
    func testErrorConformance() {
        let error: Error = PixelDataError.missingDescriptor
        #expect(error is PixelDataError)
    }
    
    @Test("PixelDataError conforms to Sendable")
    func testSendableConformance() {
        let error: any Sendable = PixelDataError.missingDescriptor
        #expect(error is PixelDataError)
    }
}
