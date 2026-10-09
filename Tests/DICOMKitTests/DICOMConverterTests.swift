import Testing
import Foundation
@testable import DICOMKit
import DICOMCore

/// Contract tests for the shared ``DICOMConverter`` API — the single source of truth
/// the `dicom-convert` CLI and the DICOMStudio CLI Workshop both use for the convert
/// target list, transfer-syntax parsing, and the conversion pipeline.
@Suite("DICOMConverter Shared API")
struct DICOMConverterTests {

    @Test("every catalog token (cliToken / aliasToken / UID) round-trips through parseTarget")
    func tokensRoundTrip() {
        for t in DICOMConverter.targets {
            #expect(DICOMConverter.parseTarget(t.cliToken)?.uid == t.syntax.uid, "cliToken \(t.cliToken)")
            #expect(DICOMConverter.parseTarget(t.aliasToken)?.uid == t.syntax.uid, "aliasToken \(t.aliasToken)")
            #expect(DICOMConverter.parseTarget(t.syntax.uid)?.uid == t.syntax.uid, "uid \(t.syntax.uid)")
            for alias in t.extraAliases {
                #expect(DICOMConverter.parseTarget(alias)?.uid == t.syntax.uid, "extra alias \(alias)")
            }
        }
    }

    @Test("the picker token lists are the catalog and can never offer a value parseTarget rejects")
    func pickerTokensAlwaysParse() {
        #expect(DICOMConverter.cliTokens.count == DICOMConverter.targets.count)
        #expect(DICOMConverter.aliasTokens.count == DICOMConverter.targets.count)
        for token in DICOMConverter.cliTokens + DICOMConverter.aliasTokens {
            #expect(DICOMConverter.parseTarget(token) != nil, "picker token \(token) must parse")
        }
    }

    @Test("catalog covers the DICOMCore-encodable convert set incl. Part 2, HTJ2K, JPEG XL (.112)")
    func catalogCoverage() {
        let uids = Set(DICOMConverter.targetSyntaxes.map(\.uid))
        let expected: [TransferSyntax] = [
            .explicitVRLittleEndian, .implicitVRLittleEndian, .explicitVRBigEndian, .deflatedExplicitVRLittleEndian,
            .jpegBaseline, .jpegExtended, .jpegLossless, .jpegLosslessSV1,
            // Both the general (.91/.93/.203/.112) and reversible-only (.90/.92/.201/.202/.110) UIDs.
            .jpeg2000, .jpeg2000Lossless, .jpeg2000Part2, .jpeg2000Part2Lossless,
            .htj2kLossy, .htj2kLossless, .htj2kRPCLLossless,
            .jpegLSLossless, .jpegLSNearLossless, .jpegXL, .jpegXLLossless, .jpegXLRecompression, .rleLossless,
        ]
        for s in expected { #expect(uids.contains(s.uid), "missing target \(s.displayName)") }
        // Non-encodable / out-of-scope syntaxes must NOT be offered as convert targets.
        // (JPEG XL .112 and JPEG XL Recompression …4.111 ARE targets now.)
        for s: TransferSyntax in [.mpeg2MainProfile, .jpipReferenced, .jp3dLossless] {
            #expect(!uids.contains(s.uid), "\(s.displayName) must not be a convert target")
            #expect(DICOMConverter.parseTarget(s.uid) == nil, "\(s.displayName) UID must not parse as a target")
        }
    }

    @Test("bare general-family aliases resolve to the LOSSY general UID with .lossy intent (matches dicom-compress)")
    func bareAliasesAreLossy() {
        // A bare family name selects the lossy general UID (the "bare = lossy" convention).
        for (alias, uid) in [
            ("jpeg2000", TransferSyntax.jpeg2000.uid),      // .91
            ("j2k", TransferSyntax.jpeg2000.uid),           // .91
            ("htj2k", TransferSyntax.htj2kLossy.uid),       // .203
            ("jpeg-xl", TransferSyntax.jpegXL.uid),         // .112
            ("jxl", TransferSyntax.jpegXL.uid),             // .112
            ("jpegxl", TransferSyntax.jpegXL.uid),          // .112
        ] {
            let enc = DICOMConverter.resolveTargetEncoding(alias)
            #expect(enc?.uid == uid, "alias \(alias)")
            #expect(enc?.intent == .lossy, "alias \(alias) must be lossy")
        }
        // Bare "jpegls" still means LOSSLESS (.80) for dicom-convert (a pre-existing convert
        // convention that intentionally differs from dicom-compress's near-lossless default).
        #expect(DICOMConverter.parseTarget("jpegls")?.uid == TransferSyntax.jpegLSLossless.uid)
    }

    @Test("symmetric intent names: -lossy/-lossless share the general UID; -lossless-only is the reversible-only UID")
    func symmetricIntentNames() {
        // JPEG 2000: -lossy and -lossless BOTH map to the general .91 UID (intent differs);
        // -lossless-only maps to the distinct reversible-only .90 UID.
        let lossy = DICOMConverter.resolveTargetEncoding("jpeg2000-lossy")
        #expect(lossy?.uid == TransferSyntax.jpeg2000.uid && lossy?.intent == .lossy)
        let lossless = DICOMConverter.resolveTargetEncoding("jpeg2000-lossless")
        #expect(lossless?.uid == TransferSyntax.jpeg2000.uid && lossless?.intent == .lossless)
        let losslessOnly = DICOMConverter.resolveTargetEncoding("jpeg2000-lossless-only")
        #expect(losslessOnly?.uid == TransferSyntax.jpeg2000Lossless.uid)

        // HTJ2K: general .203 (lossy/lossless), lossless-only .201, RPCL lossless-only .202.
        #expect(DICOMConverter.resolveTargetEncoding("htj2k-lossless")?.uid == TransferSyntax.htj2kLossy.uid)
        #expect(DICOMConverter.resolveTargetEncoding("htj2k-lossless")?.intent == .lossless)
        #expect(DICOMConverter.resolveTargetEncoding("htj2k-lossless-only")?.uid == TransferSyntax.htj2kLossless.uid)
        #expect(DICOMConverter.resolveTargetEncoding("htj2k-rpcl-lossless-only")?.uid == TransferSyntax.htj2kRPCLLossless.uid)

        // JPEG XL: general .112 (lossy/lossless), lossless-only .110.
        #expect(DICOMConverter.resolveTargetEncoding("jpeg-xl-lossless")?.uid == TransferSyntax.jpegXL.uid)
        #expect(DICOMConverter.resolveTargetEncoding("jpeg-xl-lossless")?.intent == .lossless)
        #expect(DICOMConverter.resolveTargetEncoding("jpeg-xl-lossless-only")?.uid == TransferSyntax.jpegXLLossless.uid)
    }

    // PS3.6 2026a Table A-1 (dumped): JPEG2000Lossless .90, HTJ2KLossless .201, JPEGXLLossless .110.
    @Test("Table A-1 keywords JPEG2000Lossless / HTJ2KLossless / JPEGXLLossless select their A-1 UID; …Reversible the general UID (P-CONVERT-TS-KEYWORDS)")
    func reassignedTableA1Keywords() {
        for row in TransferSyntax.reassignedTableA1Keywords {
            #expect(DICOMConverter.resolveTargetEncoding(row.keyword)?.uid == row.uid, "\(row.keyword)")
            let old = DICOMConverter.resolveTargetEncoding(row.reversibleName)
            #expect(old?.uid == row.generalUID && old?.intent == .lossless, "\(row.reversibleName)")
            #expect(DICOMConverter.cliTokens.contains(row.reversibleName))
            #expect(!DICOMConverter.cliTokens.contains(row.keyword))
        }
        #expect(DICOMConverter.resolveTargetEncoding("JPEG2000Lossless")?.uid == "1.2.840.10008.1.2.4.90")
        #expect(DICOMConverter.resolveTargetEncoding("HTJ2KLossless")?.uid == "1.2.840.10008.1.2.4.201")
        #expect(DICOMConverter.resolveTargetEncoding("JPEGXLLossless")?.uid == "1.2.840.10008.1.2.4.110")
    }

    @Test("legacy short aliases preserved (CLI ↔ app parity)")
    func legacyAliases() {
        #expect(DICOMConverter.parseTarget("evle")?.uid == TransferSyntax.explicitVRLittleEndian.uid)
        #expect(DICOMConverter.parseTarget("ivle")?.uid == TransferSyntax.implicitVRLittleEndian.uid)
        #expect(DICOMConverter.parseTarget("evbe")?.uid == TransferSyntax.explicitVRBigEndian.uid)
        #expect(DICOMConverter.parseTarget("j2k")?.uid == TransferSyntax.jpeg2000.uid)
        #expect(DICOMConverter.parseTarget("rle")?.uid == TransferSyntax.rleLossless.uid)
        #expect(DICOMConverter.parseTarget("deflate")?.uid == TransferSyntax.deflatedExplicitVRLittleEndian.uid)
        // Case-insensitive CamelCase from the CLI is accepted too.
        #expect(DICOMConverter.parseTarget("ExplicitVRLittleEndian")?.uid == TransferSyntax.explicitVRLittleEndian.uid)
    }

    @Test("unknown token returns nil and the error message names it and lists targets")
    func unknownToken() {
        #expect(DICOMConverter.parseTarget("Bogus") == nil)
        #expect(DICOMConverter.parseTarget("") == nil)
        #expect(DICOMConverter.parseTarget("   ") == nil)
        let msg = DICOMConverter.unknownTargetMessage("Bogus")
        #expect(msg.contains("Bogus"))
        #expect(msg.contains("HTJ2KLossless"))
        #expect(msg.contains("JPEGXLLossless"))
    }

    @Test("convertToDICOM transcodes explicit → implicit and renders a valid Part-10 file")
    func convertRoundTrip() throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        ds.setString("TEST^PATIENT", for: .patientName, vr: .PN)
        let file = DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )

        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: file, to: .implicitVRLittleEndian, stripPrivate: false
        )
        #expect(outcome.sourceSyntax.uid == TransferSyntax.explicitVRLittleEndian.uid)
        #expect(outcome.targetSyntax.uid == TransferSyntax.implicitVRLittleEndian.uid)
        #expect(outcome.wasTranscoded)
        #expect(outcome.isLossless)
        #expect(outcome.strippedPrivateTagCount == 0)

        // The output is a real DICOM file encoded in the target transfer syntax.
        let reread = try DICOMFile.read(from: outcome.data)
        #expect(reread.transferSyntaxUID == TransferSyntax.implicitVRLittleEndian.uid)
        #expect(reread.dataSet.string(for: .patientName)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) == "TEST^PATIENT")
    }

    /// Builds a minimal Explicit VR LE source file for transcode round-trip tests.
    private func makeSource(patient: String = "TEST^PATIENT") -> DICOMFile {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        ds.setString(patient, for: .patientName, vr: .PN)
        return DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
    }

    @Test("convertToDICOM produces a valid Deflated Explicit VR LE file that round-trips (FMI uncompressed)")
    func convertToDeflateRoundTrips() throws {
        // DEFLATE is a data-set-level deflate the DICOMCore transcoder rejects; convertToDICOM
        // handles it directly (serialize EVLE → deflate; File Meta Information stays uncompressed).
        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: makeSource(), to: .deflatedExplicitVRLittleEndian, stripPrivate: false
        )
        #expect(outcome.targetSyntax.uid == TransferSyntax.deflatedExplicitVRLittleEndian.uid)
        #expect(outcome.wasTranscoded)
        #expect(outcome.isLossless)

        let reread = try DICOMFile.read(from: outcome.data)
        #expect(reread.transferSyntaxUID == TransferSyntax.deflatedExplicitVRLittleEndian.uid)
        #expect(reread.dataSet.string(for: .patientName)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) == "TEST^PATIENT")
    }

    /// Builds a minimal uncompressed 8×8 16-bit MONOCHROME2 source with real pixel data,
    /// suitable for exercising the J2K/HTJ2K/JXL encode paths.
    private func makePixelSource() throws -> DICOMFile {
        var els: [DataElement] = []
        els.append(.uint16(tag: .rows, value: 8))
        els.append(.uint16(tag: .columns, value: 8))
        els.append(.uint16(tag: .bitsAllocated, value: 16))
        els.append(.uint16(tag: .bitsStored, value: 12))
        els.append(.uint16(tag: .highBit, value: 11))
        els.append(.uint16(tag: .pixelRepresentation, value: 0))
        els.append(.uint16(tag: .samplesPerPixel, value: 1))
        els.append(.string(tag: .photometricInterpretation, vr: .CS, value: "MONOCHROME2"))
        els.append(.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.7"))
        els.append(.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5.6.7.8.9"))
        els.append(.string(tag: .imageType, vr: .CS, value: "ORIGINAL\\PRIMARY\\AXIAL"))
        var pixels = Data()
        for i in 0..<64 {
            let v = UInt16((i * 60) % 4096)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8((v >> 8) & 0xFF))
        }
        els.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        let ds = DataSet(elements: els)
        let bytes = try DICOMFile.create(
            dataSet: ds, transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid).write()
        return try DICOMFile.read(from: bytes)
    }

    private func tsUID(_ f: DICOMFile) -> String? {
        f.fileMetaInformation.string(for: .transferSyntaxUID)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    /// The native pixel bytes `makePixelSource()` encodes, for fidelity comparisons.
    private var expectedPixels: Data {
        var pixels = Data()
        for i in 0..<64 {
            let v = UInt16((i * 60) % 4096)
            pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8((v >> 8) & 0xFF))
        }
        return pixels
    }

    /// DEFLATE (PS3.5 A.5) is a data-set-level codec over a *native* Explicit VR LE stream —
    /// it has no encapsulated form. An encapsulated source therefore has to be decoded to
    /// native pixels before the data set is deflated.
    ///
    /// Regression: the deflate branch used to serialize the encapsulated (7FE0,0010) straight
    /// into the deflate stream. The codestream survived, but the file was labelled
    /// 1.2.840.10008.1.2.1.99 while still carrying an undefined-length, Item-tagged element, so
    /// no conformant reader could decode pixels from it — and `dicom-convert` exited 0 saying
    /// "(lossless)". The pre-existing deflate test missed it because its source had no pixel data.
    @Test("encapsulated source → DEFLATE decodes pixels to native (RLE)")
    func rleToDeflateCarriesNativePixels() throws {
        let rleEnc = try #require(DICOMConverter.resolveTargetEncoding("rle-lossless"))
        let rle = try DICOMFile.read(from: DICOMConverter.convertToDICOM(
            dicomFile: try makePixelSource(), to: rleEnc, stripPrivate: false).data)
        #expect(tsUID(rle) == TransferSyntax.rleLossless.uid)
        #expect(rle.dataSet[.pixelData]?.encapsulatedFragments != nil)  // source really is encapsulated

        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: rle, to: .deflatedExplicitVRLittleEndian, stripPrivate: false)
        #expect(outcome.isLossless)

        let out = try DICOMFile.read(from: outcome.data)
        #expect(tsUID(out) == TransferSyntax.deflatedExplicitVRLittleEndian.uid)

        let pixelElement = try #require(out.dataSet[.pixelData])
        // Native, not encapsulated: defined length, no fragments.
        #expect(pixelElement.encapsulatedFragments == nil)
        #expect(pixelElement.length != 0xFFFF_FFFF)
        // RLE is reversible, so the pixels must survive bit-for-bit.
        #expect(pixelElement.valueData == expectedPixels)
    }

    @Test("encapsulated source → DEFLATE decodes pixels to native (JPEG 2000 lossless-only)")
    func j2kLosslessToDeflateCarriesNativePixels() throws {
        let j2kEnc = try #require(DICOMConverter.resolveTargetEncoding("jpeg2000-lossless-only"))
        let j2k = try DICOMFile.read(from: DICOMConverter.convertToDICOM(
            dicomFile: try makePixelSource(), to: j2kEnc, stripPrivate: false).data)
        #expect(j2k.dataSet[.pixelData]?.encapsulatedFragments != nil)

        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: j2k, to: .deflatedExplicitVRLittleEndian, stripPrivate: false)

        let out = try DICOMFile.read(from: outcome.data)
        #expect(tsUID(out) == TransferSyntax.deflatedExplicitVRLittleEndian.uid)
        let pixelElement = try #require(out.dataSet[.pixelData])
        #expect(pixelElement.encapsulatedFragments == nil)
        #expect(pixelElement.valueData == expectedPixels)
    }

    @Test("uncompressed source → DEFLATE still carries its pixels unchanged")
    func nativeToDeflateCarriesNativePixels() throws {
        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: try makePixelSource(), to: .deflatedExplicitVRLittleEndian, stripPrivate: false)

        let out = try DICOMFile.read(from: outcome.data)
        #expect(tsUID(out) == TransferSyntax.deflatedExplicitVRLittleEndian.uid)
        let pixelElement = try #require(out.dataSet[.pixelData])
        #expect(pixelElement.encapsulatedFragments == nil)
        #expect(pixelElement.valueData == expectedPixels)
    }

    @Test("deflated encapsulated output round-trips back to native pixels")
    func deflateRoundTripsBackToNative() throws {
        let rleEnc = try #require(DICOMConverter.resolveTargetEncoding("rle-lossless"))
        let rle = try DICOMFile.read(from: DICOMConverter.convertToDICOM(
            dicomFile: try makePixelSource(), to: rleEnc, stripPrivate: false).data)
        let deflated = try DICOMFile.read(from: DICOMConverter.convertToDICOM(
            dicomFile: rle, to: .deflatedExplicitVRLittleEndian, stripPrivate: false).data)

        let back = try DICOMFile.read(from: DICOMConverter.convertToDICOM(
            dicomFile: deflated, to: .explicitVRLittleEndian, stripPrivate: false).data)
        #expect(tsUID(back) == TransferSyntax.explicitVRLittleEndian.uid)
        #expect(back.dataSet[.pixelData]?.valueData == expectedPixels)
    }

    @Test("jpeg2000-lossy → .91 sets Lossy Image Compression provenance + Image Type DERIVED")
    func lossyJ2KWritesProvenance() throws {
        let src = try makePixelSource()
        let enc = try #require(DICOMConverter.resolveTargetEncoding("jpeg2000-lossy"))
        let outcome = try DICOMConverter.convertToDICOM(dicomFile: src, to: enc, stripPrivate: false)
        #expect(outcome.targetSyntax.uid == TransferSyntax.jpeg2000.uid)   // general .91
        #expect(!outcome.isLossless)

        let f = try DICOMFile.read(from: outcome.data)
        #expect(tsUID(f) == "1.2.840.10008.1.2.4.91")
        #expect(f.dataSet.string(for: .lossyImageCompression) == "01")
        #expect(f.dataSet.strings(for: .lossyImageCompressionMethod) == ["ISO_15444_1"])
        #expect(f.dataSet.strings(for: .lossyImageCompressionRatio)?.isEmpty == false)
        // Image Type Value 1 promoted ORIGINAL → DERIVED (PS3.3 C.7.6.1.1.5.1).
        #expect(f.dataSet.strings(for: .imageType)?.first == "DERIVED")
    }

    @Test("jpeg2000-lossless → .91 encodes reversibly INTO the general UID with NO lossy provenance")
    func losslessIntoGeneralUIDNoProvenance() throws {
        let src = try makePixelSource()
        let enc = try #require(DICOMConverter.resolveTargetEncoding("jpeg2000-lossless"))
        let outcome = try DICOMConverter.convertToDICOM(dicomFile: src, to: enc, stripPrivate: false)
        // Same general .91 UID as the lossy target, but reported lossless and unstamped.
        #expect(outcome.targetSyntax.uid == TransferSyntax.jpeg2000.uid)
        #expect(outcome.isLossless)

        let f = try DICOMFile.read(from: outcome.data)
        #expect(tsUID(f) == "1.2.840.10008.1.2.4.91")
        #expect(f.dataSet.string(for: .lossyImageCompression) == nil)
        #expect(f.dataSet.strings(for: .lossyImageCompressionMethod) == nil)
        #expect(f.dataSet.strings(for: .imageType)?.first == "ORIGINAL")   // not promoted
    }

    @Test("jpeg2000-lossless-only → .90 uses the distinct reversible-only UID, no provenance")
    func losslessOnlyUsesReversibleOnlyUID() throws {
        let src = try makePixelSource()
        let enc = try #require(DICOMConverter.resolveTargetEncoding("jpeg2000-lossless-only"))
        let outcome = try DICOMConverter.convertToDICOM(dicomFile: src, to: enc, stripPrivate: false)
        #expect(outcome.targetSyntax.uid == TransferSyntax.jpeg2000Lossless.uid)   // .90
        #expect(outcome.isLossless)

        let f = try DICOMFile.read(from: outcome.data)
        #expect(tsUID(f) == "1.2.840.10008.1.2.4.90")
        #expect(f.dataSet.string(for: .lossyImageCompression) == nil)
    }

    @Test("convertToDICOM transcodes explicit LE → explicit BE and round-trips losslessly")
    func convertToBigEndianRoundTrips() throws {
        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: makeSource(), to: .explicitVRBigEndian, stripPrivate: false
        )
        #expect(outcome.targetSyntax.uid == TransferSyntax.explicitVRBigEndian.uid)
        #expect(outcome.wasTranscoded)
        #expect(outcome.isLossless)

        let reread = try DICOMFile.read(from: outcome.data)
        #expect(reread.transferSyntaxUID == TransferSyntax.explicitVRBigEndian.uid)
        #expect(reread.dataSet.string(for: .patientName)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) == "TEST^PATIENT")
    }
}
