// JPIPTests.swift
// Tests for Phase 6: JPIP Streaming support in DICOMKit

import Testing
import Foundation
@testable import DICOMKit
@testable import DICOMCore
import SwiftJ2KJPIP

// MARK: - TransferSyntax JPIP Tests

@Suite("JPIP Transfer Syntax Tests")
struct JPIPTransferSyntaxTests {

    @Test("jpipReferenced isJPIP returns true")
    func isJPIP_jpipReferenced_returnsTrue() {
        #expect(TransferSyntax.jpipReferenced.isJPIP == true)
    }

    @Test("jpipReferencedDeflate isJPIP returns true")
    func isJPIP_jpipReferencedDeflate_returnsTrue() {
        #expect(TransferSyntax.jpipReferencedDeflate.isJPIP == true)
    }

    @Test("explicitVRLittleEndian isJPIP returns false")
    func isJPIP_explicitVRLittleEndian_returnsFalse() {
        #expect(TransferSyntax.explicitVRLittleEndian.isJPIP == false)
    }

    @Test("implicitVRLittleEndian isJPIP returns false")
    func isJPIP_implicitVRLittleEndian_returnsFalse() {
        #expect(TransferSyntax.implicitVRLittleEndian.isJPIP == false)
    }

    @Test("jpeg2000 isJPIP returns false")
    func isJPIP_jpeg2000_returnsFalse() {
        #expect(TransferSyntax.jpeg2000.isJPIP == false)
    }

    @Test("jpipReferenced has correct UID 1.2.840.10008.1.2.4.94")
    func jpipReferenced_hasCorrectUID() {
        #expect(TransferSyntax.jpipReferenced.uid == "1.2.840.10008.1.2.4.94")
    }

    @Test("jpipReferencedDeflate has correct UID 1.2.840.10008.1.2.4.95")
    func jpipReferencedDeflate_hasCorrectUID() {
        #expect(TransferSyntax.jpipReferencedDeflate.uid == "1.2.840.10008.1.2.4.95")
    }

    @Test("from(uid:) JPIP Referenced UID round-trips")
    func fromUID_jpipReferenced_returnsCorrectSyntax() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.94")
        #expect(ts != nil)
        #expect(ts?.isJPIP == true)
    }

    @Test("from(uid:) JPIP Referenced Deflate UID round-trips")
    func fromUID_jpipReferencedDeflate_returnsCorrectSyntax() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.95")
        #expect(ts != nil)
        #expect(ts?.isJPIP == true)
    }

    @Test("from(uid:) unknown UID returns nil")
    func fromUID_unknownUID_returnsNil() {
        let ts = TransferSyntax.from(uid: "9.9.9.9.9.9.9")
        #expect(ts == nil)
    }

    @Test("from(uid:) resolves JPIP Referenced by UID")
    func fromName_jpip_returnsJPIPSyntax() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.94")
        #expect(ts != nil)
        #expect(ts?.isJPIP == true)
    }

    @Test("from(uid:) resolves JPIP Referenced Deflate by UID")
    func fromName_jpipDeflate_returnsJPIPDeflateSyntax() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.95")
        #expect(ts != nil)
        #expect(ts?.isJPIP == true)
    }

    @Test("jpipReferenced is explicit VR (PS3.5 §A.8)")
    func jpipReferenced_isExplicitVR() {
        #expect(TransferSyntax.jpipReferenced.isExplicitVR == true)
    }

    @Test("jpipReferencedDeflate is deflated")
    func jpipReferencedDeflate_isDeflated() {
        #expect(TransferSyntax.jpipReferencedDeflate.isDeflated == true)
    }
}

// MARK: - DICOMJPIPError Tests

@Suite("DICOMJPIPError Tests")
struct DICOMJPIPErrorTests {

    @Test("invalidJPIPURI description contains the bad URI")
    func invalidJPIPURI_descriptionContainsURI() {
        let err = DICOMJPIPError.invalidJPIPURI("not-a-uri")
        #expect(err.description.contains("not-a-uri"))
    }

    @Test("notAJPIPTransferSyntax description contains the UID")
    func notAJPIPTransferSyntax_descriptionContainsUID() {
        let uid = "1.2.840.10008.1.2.1"
        let err = DICOMJPIPError.notAJPIPTransferSyntax(uid)
        #expect(err.description.contains(uid))
    }

    @Test("missingPixelDataProviderURL description names (0028,7FE0)")
    func missingPixelDataProviderURL_descriptionNamesTag() {
        #expect(DICOMJPIPError.missingPixelDataProviderURL.description.contains("(0028,7FE0)"))
    }

    @Test("jpipModuleUnavailable description is not empty")
    func jpipModuleUnavailable_descriptionIsNotEmpty() {
        #expect(!DICOMJPIPError.jpipModuleUnavailable.description.isEmpty)
    }
}

// MARK: - DICOMJPIPRegion Tests

@Suite("DICOMJPIPRegion Tests")
struct DICOMJPIPRegionTests {

    @Test("init sets x, y, width, height correctly")
    func init_setsAllProperties() {
        let region = DICOMJPIPRegion(x: 10, y: 20, width: 100, height: 200)
        #expect(region.x == 10)
        #expect(region.y == 20)
        #expect(region.width == 100)
        #expect(region.height == 200)
    }
}

// MARK: - DICOMJPIPQuality Tests

@Suite("DICOMJPIPQuality Tests")
struct DICOMJPIPQualityTests {

    @Test("layers(4) stores the layer count")
    func layers_storesCount() {
        let quality = DICOMJPIPQuality.layers(4)
        if case .layers(let n) = quality {
            #expect(n == 4)
        } else {
            Issue.record("Expected .layers(4)")
        }
    }

    @Test("resolutionLevel(2) stores the level")
    func resolutionLevel_storesLevel() {
        let rl = DICOMJPIPQuality.resolutionLevel(2)
        if case .resolutionLevel(let lvl) = rl {
            #expect(lvl == 2)
        } else {
            Issue.record("Expected .resolutionLevel(2)")
        }
    }
}

// MARK: - DICOMJPIPImage Tests

@Suite("DICOMJPIPImage Tests")
struct DICOMJPIPImageTests {

    @Test("init sets all properties correctly")
    func init_setsAllProperties() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let sourceURI = URL(string: "jpip://pacs.example.com:8080/study.dcm")!
        let image = DICOMJPIPImage(
            pixelData: data,
            width: 512,
            height: 512,
            components: 1,
            bitDepth: 12,
            sourceURI: sourceURI,
            qualityLayers: 3
        )
        #expect(image.pixelData == data)
        #expect(image.width == 512)
        #expect(image.height == 512)
        #expect(image.components == 1)
        #expect(image.bitDepth == 12)
        #expect(image.sourceURI == sourceURI)
        #expect(image.qualityLayers == 3)
    }
}

// MARK: - DICOMJPIPClient URI Extraction Tests

@Suite("DICOMJPIPClient URI Extraction Tests")
struct DICOMJPIPClientURIExtractionTests {

    /// PS3.5 A.6: the URI lives in Pixel Data Provider URL (0028,7FE0), VR UR
    /// (PS3.6 Table 6-1); "Pixel Data (7FE0,0010) shall not be present".
    private func makeDataSet(uriString: String) -> DataSet {
        let uriData = Data(uriString.utf8)
        let element = DataElement(tag: .pixelDataProviderURL, vr: .UR, length: UInt32(uriData.count), valueData: uriData)
        var ds = DataSet()
        ds[.pixelDataProviderURL] = element
        return ds
    }

    @Test("valid JPIP dataset extracts correct URL")
    func jpipURI_validDataset_returnsCorrectURL() throws {
        let expected = "jpip://pacs.hospital.org:8080/ct-series/001"
        let ds = makeDataSet(uriString: expected)
        let url = try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.94")
        #expect(url.absoluteString == expected)
    }

    @Test("non-JPIP transfer syntax throws notAJPIPTransferSyntax")
    func jpipURI_nonJPIPTransferSyntax_throws() {
        let ds = makeDataSet(uriString: "jpip://example.com/test")
        #expect {
            try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.1")
        } throws: { error in
            guard case DICOMJPIPError.notAJPIPTransferSyntax = error else { return false }
            return true
        }
    }

    @Test("missing Pixel Data Provider URL (0028,7FE0) throws missingPixelDataProviderURL")
    func jpipURI_missingProviderURL_throws() {
        let ds = DataSet()
        #expect {
            try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.94")
        } throws: { error in
            guard case DICOMJPIPError.missingPixelDataProviderURL = error else { return false }
            return true
        }
    }

    @Test("empty Pixel Data Provider URL throws missingPixelDataProviderURL")
    func jpipURI_emptyProviderURL_throws() {
        let element = DataElement(tag: .pixelDataProviderURL, vr: .UR, length: 0, valueData: Data())
        var ds = DataSet()
        ds[.pixelDataProviderURL] = element
        #expect {
            try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.94")
        } throws: { error in
            guard case DICOMJPIPError.missingPixelDataProviderURL = error else { return false }
            return true
        }
    }

    @Test("a Pixel Data element is treated as absent: never read as the URI (PS3.5 A.6)")
    func jpipURI_pixelDataElement_isIgnored() {
        let uriData = Data("jpip://legacy.example.com/should-not-be-read".utf8)
        var ds = DataSet()
        ds[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: UInt32(uriData.count), valueData: uriData)
        #expect {
            try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.94")
        } throws: { error in
            guard case DICOMJPIPError.missingPixelDataProviderURL = error else { return false }
            return true
        }
    }

    @Test("Pixel Data Provider URL wins even when a stray Pixel Data element is present")
    func jpipURI_providerURL_ignoresStrayPixelData() throws {
        let expected = "jpip://pacs.hospital.org:8080/ct-series/007"
        var ds = makeDataSet(uriString: expected)
        let stray = Data("jpip://legacy.example.com/other".utf8)
        ds[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: UInt32(stray.count), valueData: stray)
        let url = try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.94")
        #expect(url.absoluteString == expected)
    }

    @Test("Pixel Data Provider URL is read through the generic string accessor as VR UR")
    func jpipURI_providerURL_setViaSetString() throws {
        let expected = "http://pacs.hospital.org/jpip?target=study/1"
        var ds = DataSet()
        ds.setString(expected, for: .pixelDataProviderURL, vr: .UR)
        let url = try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.95")
        #expect(url.absoluteString == expected)
    }

    @Test("Deflate transfer syntax (UID .95) also extracts URI")
    func jpipURI_deflateTransferSyntax_succeeds() throws {
        let expected = "jpip://pacs.hospital.org:8080/series/002"
        let ds = makeDataSet(uriString: expected)
        let url = try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.95")
        #expect(url.absoluteString == expected)
    }

    @Test("leading and trailing whitespace is stripped from URI")
    func jpipURI_whitespaceInPixelData_isTrimmed() throws {
        let paddedURI = "  jpip://pacs.example.com/study  "
        let expected = "jpip://pacs.example.com/study"
        let ds = makeDataSet(uriString: paddedURI)
        let url = try DICOMJPIPClient.jpipURI(from: ds, transferSyntaxUID: "1.2.840.10008.1.2.4.94")
        #expect(url.absoluteString == expected)
    }
}

// MARK: - DICOMJPIPClient actor init tests

@Suite("DICOMJPIPClient Actor Tests")
struct DICOMJPIPClientActorTests {

    @Test("init stores serverURL correctly")
    func init_setsServerURL() {
        let url = URL(string: "http://pacs.example.com:8080")!
        let client = DICOMJPIPClient(serverURL: url)
        #expect(client.serverURL == url)
    }

    @Test("init with HTTPS scheme preserves scheme")
    func init_withHTTPS_preservesScheme() {
        let url = URL(string: "https://secure.pacs.example.com")!
        let client = DICOMJPIPClient(serverURL: url)
        #expect(client.serverURL.scheme == "https")
    }
}

// MARK: - DICOMVolumeProgressiveUpdate Tests

@Suite("DICOMVolumeProgressiveUpdate Tests")
struct DICOMVolumeProgressiveUpdateTests {

    @Test("init stores all properties correctly")
    func init_storesAllProperties() {
        let data = Data([0xAA, 0xBB, 0xCC])
        let update = DICOMVolumeProgressiveUpdate(
            sliceIndex: 7,
            qualityLayer: 2,
            totalLayers: 4,
            sliceData: data,
            width: 512,
            height: 512,
            isVolumeComplete: false
        )
        #expect(update.sliceIndex == 7)
        #expect(update.qualityLayer == 2)
        #expect(update.totalLayers == 4)
        #expect(update.sliceData == data)
        #expect(update.width == 512)
        #expect(update.height == 512)
        #expect(update.isVolumeComplete == false)
    }

    @Test("isVolumeComplete true is preserved")
    func init_isVolumeComplete_true() {
        let update = DICOMVolumeProgressiveUpdate(
            sliceIndex: 0, qualityLayer: 4, totalLayers: 4,
            sliceData: Data(), width: 256, height: 256, isVolumeComplete: true
        )
        #expect(update.isVolumeComplete == true)
    }

    @Test("sliceIndex 0 is valid")
    func init_sliceIndexZero_isValid() {
        let update = DICOMVolumeProgressiveUpdate(
            sliceIndex: 0, qualityLayer: 1, totalLayers: 1,
            sliceData: Data([0x01]), width: 4, height: 4, isVolumeComplete: true
        )
        #expect(update.sliceIndex == 0)
    }

    @Test("qualityLayer 1 is minimum valid layer")
    func init_qualityLayer1_isMinimum() {
        let update = DICOMVolumeProgressiveUpdate(
            sliceIndex: 0, qualityLayer: 1, totalLayers: 1,
            sliceData: Data(), width: 64, height: 64, isVolumeComplete: false
        )
        #expect(update.qualityLayer == 1)
    }

    @Test("totalLayers equals qualityLayer at full quality")
    func totalLayers_equalsQualityLayerAtFullQuality() {
        let update = DICOMVolumeProgressiveUpdate(
            sliceIndex: 5, qualityLayer: 4, totalLayers: 4,
            sliceData: Data(), width: 128, height: 128, isVolumeComplete: false
        )
        #expect(update.qualityLayer == update.totalLayers)
    }

    @Test("sliceData is stored exactly")
    func sliceData_storedExactly() {
        let expected = Data(0..<64)
        let update = DICOMVolumeProgressiveUpdate(
            sliceIndex: 1, qualityLayer: 1, totalLayers: 2,
            sliceData: expected, width: 8, height: 8, isVolumeComplete: false
        )
        #expect(update.sliceData == expected)
    }
}

// MARK: - Progressive Volume & Live Loopback JPIP Streaming Tests

@Suite("Progressive Volume & Live Loopback JPIP Streaming Tests")
struct ProgressiveVolumeAPISurfaceTests {

    private func makeLosslessCodestream(
        width: Int = 16,
        height: Int = 16,
        transferSyntaxUID: String = TransferSyntax.jpeg2000Lossless.uid
    ) throws -> (codestream: Data, rawPixels: Data) {
        var raw = Data(capacity: width * height)
        for y in 0..<height {
            for x in 0..<width {
                raw.append(UInt8((y * 16 + x) & 0xFF))
            }
        }
        let desc = PixelDataDescriptor(
            rows: height,
            columns: width,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let codestream = try SwiftJ2KDICOMCodec(
            encodingTransferSyntaxUID: transferSyntaxUID
        ).encodeFrame(
            raw,
            descriptor: desc,
            frameIndex: 0,
            configuration: .lossless
        )
        return (codestream, raw)
    }

    @Test("DICOMJPIPClient exposes SwiftJ2KJPIP 12.2.0 engine constants and HTJ2K coding preference")
    func engineVersion_and_htj2kCodingPreference() {
        #expect(DICOMJPIPClient.engineName == "SwiftJ2KJPIP")
        #expect(DICOMJPIPClient.engineVersion == "12.2.0")
        #expect(DICOMJPIPClient.codingPreference(forTransferSyntaxUID: TransferSyntax.jpipHTJ2KReferenced.uid) == .htj2k)
        #expect(DICOMJPIPClient.codingPreference(forTransferSyntaxUID: TransferSyntax.jpipHTJ2KReferencedDeflate.uid) == .htj2k)
        #expect(DICOMJPIPClient.codingPreference(forTransferSyntaxUID: TransferSyntax.jpipReferenced.uid) == .none)
        #expect(DICOMJPIPClient.codingPreference(forTransferSyntaxUID: TransferSyntax.jpipReferencedDeflate.uid) == .none)
    }

    @Test("Live loopback JPIPServer + DICOMJPIPClient streams full image, ROI, progressive layers, and resolution level")
    func liveLoopback_full_roi_progressive_resolution() async throws {
        let (codestream, expectedPixels) = try makeLosslessCodestream(width: 16, height: 16)
        let server = JPIPServer(port: 0, host: "127.0.0.1")
        await server.registerImageData(name: "ct001", data: codestream)
        try await server.start()
        let port = await server.listeningPort
        #expect(port > 0)

        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let targetURI = URL(string: "http://127.0.0.1:\(port)/ct001")!
        let client = DICOMJPIPClient(serverURL: baseURL)

        let full = try await client.fetchImage(jpipURI: targetURI)
        #expect(full.width == 16)
        #expect(full.height == 16)
        #expect(full.components == 1)
        #expect(full.bitDepth == 8)
        #expect(full.pixelData == expectedPixels)

        let roi = try await client.fetchRegion(
            jpipURI: targetURI,
            region: DICOMJPIPRegion(x: 4, y: 2, width: 8, height: 6)
        )
        #expect(roi.width == 8)
        #expect(roi.height == 6)
        #expect(!roi.pixelData.isEmpty)

        let preview = try await client.fetchProgressiveQuality(jpipURI: targetURI, layers: 1)
        #expect(preview.width == 16)
        #expect(preview.height == 16)
        #expect(preview.qualityLayers == 1)

        let half = try await client.fetchResolutionLevel(jpipURI: targetURI, level: 1)
        #expect(half.width > 0 && half.width <= 16)
        #expect(half.height > 0 && half.height <= 16)

        try await client.close()
        try await server.stop()
    }

    @Test("Live loopback JPIPServer + HTJ2K (.204) referenced DICOMFile.openVolume and openVolumeProgressively")
    func liveLoopback_htj2k_and_progressiveVolume() async throws {
        let (htCodestream, expectedPixels) = try makeLosslessCodestream(
            width: 16,
            height: 16,
            transferSyntaxUID: TransferSyntax.htj2kLossless.uid
        )
        let server = JPIPServer(port: 0, host: "127.0.0.1")
        await server.registerImageData(name: "htslice0", data: htCodestream)
        await server.registerImageData(name: "htslice1", data: htCodestream)
        try await server.start()
        let port = await server.listeningPort

        let serverURL = URL(string: "http://127.0.0.1:\(port)")!
        let uri0 = URL(string: "http://127.0.0.1:\(port)/htslice0")!
        let uri1 = URL(string: "http://127.0.0.1:\(port)/htslice1")!

        // Build a JPIP HTJ2K Referenced (.204) DICOM file on disk
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString(UIDGenerator.generateUID().value, for: .sopInstanceUID, vr: .UI)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setUInt16(16, for: .rows)
        ds.setUInt16(16, for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setString(uri0.absoluteString, for: .pixelDataProviderURL, vr: .UR)

        let jpipFile = DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: ds.string(for: .sopInstanceUID)!,
            transferSyntaxUID: TransferSyntax.jpipHTJ2KReferenced.uid
        )
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_jpip_htj2k_\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try jpipFile.write().write(to: tmpURL)

        let volume = try await DICOMFile.openVolume(from: tmpURL, jpipServerURL: serverURL)
        #expect(volume.width == 16)
        #expect(volume.height == 16)
        #expect(volume.depth == 1)
        #expect(volume.pixelData == expectedPixels)

        var updates: [DICOMVolumeProgressiveUpdate] = []
        for await u in DICOMFile.openVolumeProgressively(
            serverURL: serverURL,
            sliceJPIPURIs: [uri0, uri1],
            qualityLayers: 2
        ) {
            updates.append(u)
        }
        #expect(updates.count == 4)
        #expect(updates.last?.isVolumeComplete == true)

        // Empty-URI stream terminates cleanly with zero updates
        var emptyUpdates = 0
        for await _ in DICOMFile.openVolumeProgressively(serverURL: serverURL, sliceJPIPURIs: [], qualityLayers: 2) {
            emptyUpdates += 1
        }
        #expect(emptyUpdates == 0)

        try await server.stop()
    }

    @Test("DICOMVolumeProgressiveUpdate is Sendable")
    func progressiveUpdate_isSendable() {
        let update: any Sendable = DICOMVolumeProgressiveUpdate(
            sliceIndex: 0, qualityLayer: 1, totalLayers: 1,
            sliceData: Data(), width: 1, height: 1, isVolumeComplete: true
        )
        #expect(update is DICOMVolumeProgressiveUpdate)
    }
}

