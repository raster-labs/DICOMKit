// Deferred-row closure pass (2026-10-01), DICOMCore rows D109, D130, D139, D151, D176, D187,
// D190, D193. Each test pins the value of the DICOM 2026a text the row cites.

import Testing
import Foundation
@testable import DICOMCore

@Suite("Deferred rows (DICOMCore, 2026a)")
struct DeferredRowsA2CoreTests {

    // MARK: - D109: PS3.5 2026a A.11 / A.12, PS3.6 Table A-1 (four JPIP rows)

    @Test("D109: all four JPIP Referenced syntaxes are JPIP, nothing else is")
    func jpipCoversHTJ2KPair() {
        let jpip = ["1.2.840.10008.1.2.4.94", "1.2.840.10008.1.2.4.95",
                    "1.2.840.10008.1.2.4.204", "1.2.840.10008.1.2.4.205"]
        for uid in jpip {
            #expect(TransferSyntax.from(uid: uid)?.isJPIP == true, "\(uid)")
        }
        let others = TransferSyntax.allKnown.filter { !jpip.contains($0.uid) }
        #expect(others.allSatisfy { !$0.isJPIP })
    }

    // MARK: - D130: PS3.10 2026a 8.6 (File IDs relative to the File-set root)

    private func directory(fileIDs: [[String]]) -> DICOMDirectory {
        let images = fileIDs.enumerated().map { index, id in
            DirectoryRecord(recordType: .image, referencedFileID: id,
                            referencedSOPInstanceUID: "1.2.3.\(index + 1)")
        }
        let series = DirectoryRecord(recordType: .series, children: images)
        let study = DirectoryRecord(recordType: .study, children: [series])
        let patient = DirectoryRecord(recordType: .patient, children: [study])
        return DICOMDirectory(fileSetID: "TEST", rootRecords: [patient])
    }

    @Test("D130: Referenced File IDs are checked on disk under the File-set root")
    func validateChecksFilesUnderRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D130-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("DICOM/ST1"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0]).write(to: root.appendingPathComponent("DICOM/ST1/IM1"))

        let present = directory(fileIDs: [["DICOM", "ST1", "IM1"]])
        try present.validate(checkFileExistence: true, fileSetRoot: root)

        let missing = directory(fileIDs: [["DICOM", "ST1", "IM1"], ["DICOM", "ST1", "IM2"]])
        #expect {
            try missing.validate(checkFileExistence: true, fileSetRoot: root)
        } throws: { error in
            guard case DICOMDirectory.ValidationError.missingReferencedFile(let id) = error else { return false }
            return id == "DICOM\\ST1\\IM2"
        }

        // A directory is not a referenced File; ".." would leave the File-set (PS3.10 8.6).
        #expect(throws: DICOMDirectory.ValidationError.self) {
            try directory(fileIDs: [["DICOM", "ST1"]]).validate(checkFileExistence: true, fileSetRoot: root)
        }
        #expect(throws: DICOMDirectory.ValidationError.self) {
            try directory(fileIDs: [["..", "IM1"]]).validate(
                checkFileExistence: true, fileSetRoot: root.appendingPathComponent("DICOM/ST1"))
        }
        // Without a root nothing is resolved on disk (unchanged behaviour).
        try missing.validate(checkFileExistence: true)
        try missing.validate()
    }

    // MARK: - D139: PS3.5 2026a 9.1, B.2

    @Test("D139: a malformed or over-long root yields unique UUID derived UIDs, no crash")
    func uidGeneratorFallsBackToUUIDDerived() {
        for root in ["1.2.abc", "1..2", "01.2", "", String(repeating: "1.", count: 25) + "1"] {
            let generator = UIDGenerator(root: root)
            let a = generator.generate(), b = generator.generate()
            let c = generator.generateSOPInstanceUID()
            for uid in [a, b, c] {
                #expect(uid.value.hasPrefix("2.25."), "\(root) -> \(uid.value)")
                #expect(uid.value.count <= 64)
                #expect(DICOMUniqueIdentifier.parse(uid.value) != nil)
            }
            #expect(a != b)
            #expect(UIDGenerator.isUsableRoot(root) == false)
        }
        // A usable root keeps the {root}.{type}.{timestamp}.{random} form.
        let ok = UIDGenerator(root: "1.2.826.0.1.3680043.10.511.4")
        #expect(UIDGenerator.isUsableRoot(ok.root))
        #expect(ok.generateStudyInstanceUID().value.hasPrefix("1.2.826.0.1.3680043.10.511.4.1."))
    }

    @Test("D139: UUID derived UID is 2.25 + the UUID as a decimal integer (PS3.5 B.2)")
    func uuidDerivedUIDValue() throws {
        let uuid = try #require(UUID(uuidString: "F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6"))
        // The worked example of ITU-T X.667 / RFC 4122 as a 128-bit integer.
        #expect(UIDGenerator.uuidDerivedUID(uuid).value == "2.25.329800735698586629295641978511506172918")
        #expect(UIDGenerator.uuidDerivedUID(UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))).value == "2.25.0")
    }

    // MARK: - D151: PS3.5 2026a 7.1, 7.8.1

    @Test("D151: groups 0001, 0003, 0005, 0007 and FFFF are not Private")
    func unusableOddGroupsAreNotPrivate() {
        for group: UInt16 in [0x0001, 0x0003, 0x0005, 0x0007, 0xFFFF] {
            let tag = DICOMCore.Tag(group: group, element: 0x0010)
            #expect(tag.isPrivate == false, "\(tag)")
            #expect(tag.isOddGroup)
        }
        for group: UInt16 in [0x0009, 0x0011, 0x0029, 0x7FE1, 0xFFFD] {
            #expect(DICOMCore.Tag(group: group, element: 0x1000).isPrivate, "\(group)")
        }
        #expect(DICOMCore.Tag(group: 0x0008, element: 0x0010).isPrivate == false)
        #expect(DICOMCore.Tag(group: 0x0008, element: 0x0010).isOddGroup == false)
    }

    // MARK: - D176: PS3.6 2026a Table A-1 names

    @Test("D176: displayName is the PS3.6 Table A-1 UID Name; shortName keeps the abbreviation")
    func displayNameIsTableA1Name() {
        let expected: [(TransferSyntax, String)] = [
            (.implicitVRLittleEndian, "Implicit VR Little Endian: Default Transfer Syntax for DICOM"),
            (.jpegBaseline, "JPEG Baseline (Process 1): Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression"),
            (.jpeg2000Lossless, "JPEG 2000 Image Compression (Lossless Only)"),
            (.htj2kRPCLLossless, "High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)"),
            (.mpeg2MainProfile, "MPEG2 Main Profile / Main Level"),
            (.mpeg4AVCHP41, "MPEG-4 AVC/H.264 High Profile / Level 4.1"),
            (.mpeg4AVCStereoHP42Fragmentable, "Fragmentable MPEG-4 AVC/H.264 Stereo High Profile / Level 4.2"),
            (.hevcH265Main10Profile, "HEVC/H.265 Main 10 Profile / Level 5.1"),
            (.explicitVRBigEndian, "Explicit VR Big Endian (Retired)"),
            (.jpipHTJ2KReferencedDeflate, "JPIP HTJ2K Referenced Deflate"),
        ]
        for (syntax, name) in expected {
            #expect(syntax.displayName == name)
        }
        #expect(TransferSyntax.mpeg2MainProfile.shortName == "MPEG2 Main Profile @ Main Level")
        #expect(TransferSyntax.jpeg2000Lossless.shortName == "JPEG 2000 Lossless Only")
        #expect(SelectableEncoding(transferSyntax: .jpeg2000, intent: .lossy).displayName
                == "JPEG 2000 Image Compression (lossy)")
        #expect(SelectableEncoding(transferSyntax: .jpeg2000, intent: .lossy).shortName == "JPEG 2000 Lossy")
    }

    // MARK: - D187: PS3.5 2026a 10.18.1

    private func gray8(rows: Int, columns: Int) -> (Data, PixelDataDescriptor) {
        let d = PixelDataDescriptor(rows: rows, columns: columns, bitsAllocated: 8, bitsStored: 8,
                                    highBit: 7, isSigned: false, samplesPerPixel: 1,
                                    photometricInterpretation: .monochrome2)
        return (Data((0..<(rows * columns)).map { UInt8(($0 * 7 + $0 / 13) % 251) }), d)
    }

    private func rgb8(rows: Int, columns: Int) -> (Data, PixelDataDescriptor) {
        let d = PixelDataDescriptor(rows: rows, columns: columns, bitsAllocated: 8, bitsStored: 8,
                                    highBit: 7, isSigned: false, samplesPerPixel: 3,
                                    photometricInterpretation: .rgb, planarConfiguration: 0)
        return (Data((0..<(rows * columns * 3)).map { UInt8(($0 * 5 + $0 / 7) % 256) }), d)
    }

    @Test("D187: .202 output is RPCL, has TLM and enough decompositions, and round-trips")
    func htj2kRPCLConforms() throws {
        for (data, descriptor) in [gray8(rows: 300, columns: 200), rgb8(rows: 64, columns: 48),
                                   gray8(rows: 2500, columns: 3000)] {
            let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kRPCLLossless.uid)
            let encoded = try codec.encodeFrame(data, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
            let style = try #require(J2KCodestreamInspector.codingStyle(in: encoded))
            #expect(style.progressionOrder == 2)   // RPCL, ISO/IEC 15444-1 Table A.16
            #expect(style.hasTLM)
            #expect(J2KCodestreamInspector.htj2kRPCLViolations(
                in: encoded, rows: descriptor.rows, columns: descriptor.columns).isEmpty)
            let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
            #expect(decoded == data)
        }
        #expect(J2KCodestreamInspector.minimumDecompositionLevelsForRPCL(rows: 2500, columns: 3000) == 6)
        #expect(J2KCodestreamInspector.minimumDecompositionLevelsForRPCL(rows: 64, columns: 64) == 0)
    }

    @Test("D187: the other J2K syntaxes are not relabelled, and J2K → .202 takes the encoder")
    func otherSyntaxesUntouched() throws {
        let (data, descriptor) = gray8(rows: 100, columns: 100)
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        let encoded = try codec.encodeFrame(data, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        #expect(J2KCodestreamInspector.codingStyle(in: encoded)?.hasTLM == false)
        #expect(TransferSyntaxConverter.canUseFastPathTranscode(from: .jpeg2000Lossless, to: .htj2kRPCLLossless) == false)
        #expect(TransferSyntaxConverter.canUseFastPathTranscode(from: .jpeg2000Lossless, to: .htj2kLossless))
    }

    @Test("D187: a multi-layer codestream is not relabelled (packet order would differ)")
    func multiLayerNotRelabelled() throws {
        let (data, descriptor) = gray8(rows: 64, columns: 64)
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        var bytes = [UInt8](try codec.encodeFrame(data, descriptor: descriptor, frameIndex: 0, configuration: .lossless))
        // Pretend the COD says 2 layers: SGcod layers follow Scod and the progression byte.
        let cod = try #require((0..<(bytes.count - 1)).first { bytes[$0] == 0xFF && bytes[$0 + 1] == 0x52 })
        bytes[cod + 6] = 0; bytes[cod + 7] = 2
        let out = J2KCodestreamInspector.conformingToHTJ2KRPCL(Data(bytes))
        #expect(J2KCodestreamInspector.codingStyle(in: out)?.progressionOrder == 0)
        #expect(J2KCodestreamInspector.codingStyle(in: out)?.hasTLM == true)
    }

    // MARK: - D190: PS3.5 2026a 8.2.1 (JFIF APP0 recommended absent)

    @Test("D190: JPEG Baseline output carries no JFIF APP0 segment and still decodes")
    func jpegBaselineHasNoJFIF() throws {
        for (data, descriptor) in [gray8(rows: 32, columns: 40), rgb8(rows: 16, columns: 24)] {
            let codec = JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid)
            let encoded = try codec.encodeFrame(data, descriptor: descriptor, frameIndex: 0, configuration: .default)
            #expect(encoded.prefix(2) == Data([0xFF, 0xD8]))
            #expect(!JPEGInterchangeFormat.containsJFIFSegment(encoded))
            #expect(encoded.range(of: Data("JFIF".utf8)) == nil)
            let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
            #expect(decoded.count == data.count)
        }
        let lossless = JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid)
        let (g, gd) = gray8(rows: 16, columns: 16)
        let encoded = try lossless.encodeFrame(g, descriptor: gd, frameIndex: 0, configuration: .lossless)
        #expect(!JPEGInterchangeFormat.containsJFIFSegment(encoded))
        #expect(try lossless.decodeFrame(encoded, descriptor: gd, frameIndex: 0) == g)
    }

    @Test("D190: only JFIF / JFXX APP0 segments are removed")
    func removingJFIFKeepsOtherSegments() {
        let jfif: [UInt8] = [0xFF, 0xE0, 0x00, 0x10] + Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0]
        let app1: [UInt8] = [0xFF, 0xE1, 0x00, 0x06] + Array("Exif".utf8)
        let rest: [UInt8] = [0xFF, 0xDA, 0x00, 0x02, 0x12, 0x34, 0xFF, 0xD9]
        let stream = Data([0xFF, 0xD8] + jfif + app1 + rest)
        #expect(JPEGInterchangeFormat.removingJFIFSegments(stream) == Data([0xFF, 0xD8] + app1 + rest))
        #expect(JPEGInterchangeFormat.removingJFIFSegments(Data([0xFF, 0xD8] + app1 + rest)) == Data([0xFF, 0xD8] + app1 + rest))
    }

    // MARK: - D193: PS3.5 2026a 8.2.4, Table 8.2.4-1 (and 8.2.14 for HTJ2K)

    private func rgbDataSet(rows: Int = 16, columns: Int = 16) -> Data {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        func us(_ tag: DICOMCore.Tag, _ v: UInt16) -> DataElement {
            var x = v.littleEndian
            return DataElement(tag: tag, vr: .US, length: 2, valueData: Data(bytes: &x, count: 2))
        }
        let pixels = rgb8(rows: rows, columns: columns).0
        let elements: [DataElement] = [
            us(.samplesPerPixel, 3),
            DataElement(tag: .photometricInterpretation, vr: .CS, length: 4, valueData: Data("RGB ".utf8)),
            us(.planarConfiguration, 0),
            us(.rows, UInt16(rows)), us(.columns, UInt16(columns)),
            us(.bitsAllocated, 8), us(.bitsStored, 8), us(.highBit, 7), us(.pixelRepresentation, 0),
            DataElement(tag: .pixelData, vr: .OB, length: UInt32(pixels.count), valueData: pixels),
        ]
        return elements.reduce(into: Data()) { $0.append(writer.serializeElement($1)) }
    }

    /// Value of a top-level element of an Explicit VR Little Endian data set without sequences.
    private func value(_ tag: DICOMCore.Tag, in data: Data) -> Data? {
        let b = [UInt8](data)
        var i = 0
        while i + 8 <= b.count {
            let g = UInt16(b[i]) | UInt16(b[i + 1]) << 8, e = UInt16(b[i + 2]) | UInt16(b[i + 3]) << 8
            let vr = String(bytes: b[(i + 4)..<(i + 6)], encoding: .ascii) ?? ""
            var length: Int, header: Int
            if ["OB", "OW", "OF", "SQ", "UT", "UN", "OD", "OL", "OV", "UC", "UR", "SV", "UV"].contains(vr) {
                length = Int(b[i + 8]) | Int(b[i + 9]) << 8 | Int(b[i + 10]) << 16 | Int(b[i + 11]) << 24
                header = 12
            } else {
                length = Int(b[i + 6]) | Int(b[i + 7]) << 8
                header = 8
            }
            if g == tag.group && e == tag.element { return Data(b[(i + header)..<min(b.count, i + header + max(0, length))]) }
            if length == 0xFFFF_FFFF { return nil }
            i += header + length
        }
        return nil
    }

    private func photometric(_ data: Data) -> String? {
        value(.photometricInterpretation, in: data).flatMap { String(data: $0, encoding: .ascii) }?
            .trimmingCharacters(in: .whitespaces)
    }

    @Test("D193: RGB → JPEG 2000 with MCT 1 is labelled YBR_RCT, and back to native it is RGB")
    func j2kPhotometricInterpretationFollowsMCT() throws {
        let source = rgbDataSet()
        for target in [TransferSyntax.jpeg2000Lossless, .htj2kLossless] {
            let converter = TransferSyntaxConverter(
                configuration: TranscodingConfiguration(preferredSyntaxes: [target], allowLossyCompression: false,
                                                        preservePixelDataFidelity: true),
                compressionConfiguration: .lossless)
            let encoded = try converter.transcode(dataSetData: source, from: .explicitVRLittleEndian, to: target)
            #expect(photometric(encoded.data) == "YBR_RCT", "\(target.uid)")
            #expect(value(.planarConfiguration, in: encoded.data) == Data([0, 0]))

            let back = try converter.transcode(dataSetData: encoded.data, from: target, to: .explicitVRLittleEndian)
            #expect(photometric(back.data) == "RGB", "\(target.uid)")
            #expect(value(.pixelData, in: back.data) == value(.pixelData, in: source))
        }
    }

    @Test("D193: an irreversible (9-7) colour encode is labelled YBR_ICT")
    func j2kLossyColourIsICT() throws {
        let converter = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(preferredSyntaxes: [.jpeg2000], allowLossyCompression: true,
                                                    preservePixelDataFidelity: false),
            compressionConfiguration: .default)
        let encoded = try converter.transcode(dataSetData: rgbDataSet(), from: .explicitVRLittleEndian, to: .jpeg2000)
        #expect(photometric(encoded.data) == "YBR_ICT")
        let back = try converter.transcode(dataSetData: encoded.data, from: .jpeg2000, to: .explicitVRLittleEndian)
        #expect(photometric(back.data) == "RGB")
    }

    @Test("D193: replacingPhotometricInterpretation pads to an even length and honours the filter")
    func replacingPhotometric() {
        let pi = DataElement(tag: .photometricInterpretation, vr: .CS, length: 8, valueData: Data("YBR_RCT ".utf8))
        let out = TransferSyntaxConverter.replacingPhotometricInterpretation(in: [pi], when: ["YBR_RCT"], with: "RGB")
        #expect(out[0].valueData == Data("RGB ".utf8))
        let kept = TransferSyntaxConverter.replacingPhotometricInterpretation(in: [pi], when: ["RGB"], with: "YBR_ICT")
        #expect(kept[0].valueData == Data("YBR_RCT ".utf8))
    }
}
