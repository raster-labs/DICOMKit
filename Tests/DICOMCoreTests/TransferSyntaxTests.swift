import Testing
@testable import DICOMCore

@Suite("TransferSyntax Tests")
struct TransferSyntaxTests {
    
    @Test("Implicit VR Little Endian transfer syntax properties")
    func testImplicitVRLittleEndian() {
        let ts = TransferSyntax.implicitVRLittleEndian
        
        #expect(ts.uid == "1.2.840.10008.1.2")
        #expect(ts.isExplicitVR == false)
        #expect(ts.byteOrder == .littleEndian)
        #expect(ts.isEncapsulated == false)
        #expect(ts.isDeflated == false)
    }
    
    @Test("Explicit VR Little Endian transfer syntax properties")
    func testExplicitVRLittleEndian() {
        let ts = TransferSyntax.explicitVRLittleEndian
        
        #expect(ts.uid == "1.2.840.10008.1.2.1")
        #expect(ts.isExplicitVR == true)
        #expect(ts.byteOrder == .littleEndian)
        #expect(ts.isEncapsulated == false)
        #expect(ts.isDeflated == false)
    }
    
    @Test("Deflated Explicit VR Little Endian transfer syntax properties")
    func testDeflatedExplicitVRLittleEndian() {
        let ts = TransferSyntax.deflatedExplicitVRLittleEndian
        
        #expect(ts.uid == "1.2.840.10008.1.2.1.99")
        #expect(ts.isExplicitVR == true)
        #expect(ts.byteOrder == .littleEndian)
        #expect(ts.isEncapsulated == false)
        #expect(ts.isDeflated == true)
    }
    
    @Test("Explicit VR Big Endian transfer syntax properties")
    func testExplicitVRBigEndian() {
        let ts = TransferSyntax.explicitVRBigEndian
        
        #expect(ts.uid == "1.2.840.10008.1.2.2")
        #expect(ts.isExplicitVR == true)
        #expect(ts.byteOrder == .bigEndian)
        #expect(ts.isEncapsulated == false)
        #expect(ts.isDeflated == false)
    }
    
    @Test("TransferSyntax from UID - Implicit VR Little Endian")
    func testFromUIDImplicitVR() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2")
        
        #expect(ts != nil)
        #expect(ts?.uid == TransferSyntax.implicitVRLittleEndian.uid)
        #expect(ts?.isExplicitVR == false)
        #expect(ts?.byteOrder == .littleEndian)
        #expect(ts?.isDeflated == false)
    }
    
    @Test("TransferSyntax from UID - Explicit VR Little Endian")
    func testFromUIDExplicitVRLittleEndian() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.1")
        
        #expect(ts != nil)
        #expect(ts?.uid == TransferSyntax.explicitVRLittleEndian.uid)
        #expect(ts?.isExplicitVR == true)
        #expect(ts?.byteOrder == .littleEndian)
        #expect(ts?.isDeflated == false)
    }
    
    @Test("TransferSyntax from UID - Deflated Explicit VR Little Endian")
    func testFromUIDDeflatedExplicitVRLittleEndian() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.1.99")
        
        #expect(ts != nil)
        #expect(ts?.uid == TransferSyntax.deflatedExplicitVRLittleEndian.uid)
        #expect(ts?.isExplicitVR == true)
        #expect(ts?.byteOrder == .littleEndian)
        #expect(ts?.isDeflated == true)
    }
    
    @Test("TransferSyntax from UID - Explicit VR Big Endian")
    func testFromUIDExplicitVRBigEndian() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.2")
        
        #expect(ts != nil)
        #expect(ts?.uid == TransferSyntax.explicitVRBigEndian.uid)
        #expect(ts?.isExplicitVR == true)
        #expect(ts?.byteOrder == .bigEndian)
        #expect(ts?.isDeflated == false)
    }
    
    @Test("TransferSyntax from UID - Unknown UID returns nil")
    func testFromUIDUnknown() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.999")
        
        #expect(ts == nil)
    }
    
    @Test("TransferSyntax from UID - Compressed transfer syntax returns valid syntax")
    func testFromUIDCompressed() {
        // JPEG Baseline (Process 1) - now supported
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.50")
        
        #expect(ts != nil)
        #expect(ts?.isEncapsulated == true)
        #expect(ts?.isExplicitVR == true)
        #expect(ts?.byteOrder == .littleEndian)
    }
    
    @Test("TransferSyntax from UID - Unknown transfer syntax returns nil")
    func testFromUIDUnsupported() {
        let ts = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.999")
        
        #expect(ts == nil)
    }

    @Test("Extended JPEG 2000 families are recognized")
    func testExtendedJPEG2000Families() {
        let part2Lossless = TransferSyntax.jpeg2000Part2Lossless
        #expect(TransferSyntax.from(uid: part2Lossless.uid) == .jpeg2000Part2Lossless)
        #expect(part2Lossless.isJPEG2000)
        #expect(part2Lossless.isJPEG2000Part2)
        #expect(part2Lossless.isLossless)

        let htLossless = TransferSyntax.htj2kLossless
        #expect(TransferSyntax.from(uid: htLossless.uid) == .htj2kLossless)
        #expect(htLossless.isJPEG2000)
        #expect(htLossless.isHTJ2K)
        #expect(htLossless.isLossless)

        let htRPCL = TransferSyntax.htj2kRPCLLossless
        #expect(TransferSyntax.from(uid: htRPCL.uid) == .htj2kRPCLLossless)
        #expect(htRPCL.isHTJ2K)
        #expect(htRPCL.isLossless)

        let htLossy = TransferSyntax.htj2kLossy
        #expect(TransferSyntax.from(uid: htLossy.uid) == .htj2kLossy)
        #expect(htLossy.isHTJ2K)
        #expect(htLossy.isLossless == false)
    }

    @Test("TransferSyntax parse recognizes CLI aliases and UIDs")
    func testParseAliases() {
        #expect(TransferSyntax.parse("explicit-vr-le") == .explicitVRLittleEndian)
        #expect(TransferSyntax.parse("implicit-vr-le") == .implicitVRLittleEndian)
        // `parse` is CONSERVATIVE (UID-only, no intent): bare `…-lossless` keeps the
        // reversible-only UID; `…-lossless-only` is an explicit synonym. The lossless-INTO-
        // general split lives in `parseEncoding` (see testParseEncodingIntentAliases).
        #expect(TransferSyntax.parse("jpeg2000-lossless") == .jpeg2000Lossless)      // .90
        #expect(TransferSyntax.parse("jpeg2000-lossless-only") == .jpeg2000Lossless) // .90
        #expect(TransferSyntax.parse("htj2k-lossless") == .htj2kLossless)           // .201
        #expect(TransferSyntax.parse("htj2k-lossless-only") == .htj2kLossless)      // .201
        #expect(TransferSyntax.parse("htj2k-rpcl-lossless-only") == .htj2kRPCLLossless) // .202
        #expect(TransferSyntax.parse("htj2k-rpcl") == .htj2kRPCLLossless)           // deprecated alias
        #expect(TransferSyntax.parse("htj2k") == .htj2kLossy)                       // .203 general
        #expect(TransferSyntax.parse("1.2.840.10008.1.2.4.201") == .htj2kLossless)
        #expect(TransferSyntax.parse("not-a-syntax") == nil)
    }
    
    @Test("JPEG transfer syntax properties")
    func testJPEGTransferSyntaxes() {
        // JPEG Baseline
        let jpegBaseline = TransferSyntax.jpegBaseline
        #expect(jpegBaseline.uid == "1.2.840.10008.1.2.4.50")
        #expect(jpegBaseline.isEncapsulated == true)
        #expect(jpegBaseline.isJPEG == true)
        #expect(jpegBaseline.isLossless == false)
        
        // JPEG Extended
        let jpegExtended = TransferSyntax.jpegExtended
        #expect(jpegExtended.uid == "1.2.840.10008.1.2.4.51")
        #expect(jpegExtended.isEncapsulated == true)
        #expect(jpegExtended.isJPEG == true)
        
        // JPEG Lossless
        let jpegLossless = TransferSyntax.jpegLossless
        #expect(jpegLossless.uid == "1.2.840.10008.1.2.4.57")
        #expect(jpegLossless.isEncapsulated == true)
        #expect(jpegLossless.isJPEG == true)
        #expect(jpegLossless.isLossless == true)
        
        // JPEG Lossless SV1
        let jpegLosslessSV1 = TransferSyntax.jpegLosslessSV1
        #expect(jpegLosslessSV1.uid == "1.2.840.10008.1.2.4.70")
        #expect(jpegLosslessSV1.isEncapsulated == true)
        #expect(jpegLosslessSV1.isJPEG == true)
        #expect(jpegLosslessSV1.isLossless == true)
    }
    
    @Test("JPEG 2000 transfer syntax properties")
    func testJPEG2000TransferSyntaxes() {
        // JPEG 2000 Lossless
        let j2kLossless = TransferSyntax.jpeg2000Lossless
        #expect(j2kLossless.uid == "1.2.840.10008.1.2.4.90")
        #expect(j2kLossless.isEncapsulated == true)
        #expect(j2kLossless.isJPEG2000 == true)
        #expect(j2kLossless.isLossless == true)
        
        // JPEG 2000 Lossy
        let j2k = TransferSyntax.jpeg2000
        #expect(j2k.uid == "1.2.840.10008.1.2.4.91")
        #expect(j2k.isEncapsulated == true)
        #expect(j2k.isJPEG2000 == true)
        #expect(j2k.isLossless == false)
    }
    
    @Test("RLE transfer syntax properties")
    func testRLETransferSyntax() {
        let rle = TransferSyntax.rleLossless
        #expect(rle.uid == "1.2.840.10008.1.2.5")
        #expect(rle.isEncapsulated == true)
        #expect(rle.isRLE == true)
        #expect(rle.isLossless == true)
    }
    
    @Test("TransferSyntax equality")
    func testEquality() {
        let ts1 = TransferSyntax.explicitVRLittleEndian
        let ts2 = TransferSyntax(
            uid: "1.2.840.10008.1.2.1",
            isExplicitVR: true,
            byteOrder: .littleEndian
        )
        
        #expect(ts1 == ts2)
    }
    
    @Test("TransferSyntax hashable")
    func testHashable() {
        var set: Set<TransferSyntax> = []
        set.insert(.implicitVRLittleEndian)
        set.insert(.explicitVRLittleEndian)
        set.insert(.deflatedExplicitVRLittleEndian)
        set.insert(.explicitVRBigEndian)
        
        #expect(set.count == 4)
        #expect(set.contains(.implicitVRLittleEndian))
        #expect(set.contains(.explicitVRLittleEndian))
        #expect(set.contains(.deflatedExplicitVRLittleEndian))
        #expect(set.contains(.explicitVRBigEndian))
    }
    
    @Test("TransferSyntax description")
    func testDescription() {
        let implicitDesc = TransferSyntax.implicitVRLittleEndian.description
        let explicitLEDesc = TransferSyntax.explicitVRLittleEndian.description
        let deflatedDesc = TransferSyntax.deflatedExplicitVRLittleEndian.description
        let explicitBEDesc = TransferSyntax.explicitVRBigEndian.description
        
        #expect(implicitDesc.contains("Implicit VR"))
        #expect(implicitDesc.contains("Little Endian"))
        #expect(implicitDesc.contains("1.2.840.10008.1.2"))
        
        #expect(explicitLEDesc.contains("Explicit VR"))
        #expect(explicitLEDesc.contains("Little Endian"))
        #expect(explicitLEDesc.contains("1.2.840.10008.1.2.1"))
        
        #expect(deflatedDesc.contains("Explicit VR"))
        #expect(deflatedDesc.contains("Little Endian"))
        #expect(deflatedDesc.contains("Deflated"))
        #expect(deflatedDesc.contains("1.2.840.10008.1.2.1.99"))
        
        #expect(explicitBEDesc.contains("Explicit VR"))
        #expect(explicitBEDesc.contains("Big Endian"))
        #expect(explicitBEDesc.contains("1.2.840.10008.1.2.2"))
    }
    
    @Test("ByteOrder cases")
    func testByteOrderCases() {
        let littleEndian = ByteOrder.littleEndian
        let bigEndian = ByteOrder.bigEndian
        
        #expect(littleEndian != bigEndian)
        #expect(littleEndian == .littleEndian)
        #expect(bigEndian == .bigEndian)
    }
    
    @Test("Custom TransferSyntax creation")
    func testCustomTransferSyntax() {
        // Test creating a custom encapsulated transfer syntax
        let customTS = TransferSyntax(
            uid: "1.2.840.10008.1.2.4.50",
            isExplicitVR: true,
            byteOrder: .littleEndian,
            isEncapsulated: true
        )
        
        #expect(customTS.uid == "1.2.840.10008.1.2.4.50")
        #expect(customTS.isExplicitVR == true)
        #expect(customTS.byteOrder == .littleEndian)
        #expect(customTS.isEncapsulated == true)
        #expect(customTS.isDeflated == false)
    }
    
    @Test("Custom deflated TransferSyntax creation")
    func testCustomDeflatedTransferSyntax() {
        // Test creating a custom deflated transfer syntax
        let customTS = TransferSyntax(
            uid: "1.2.840.10008.1.2.1.99",
            isExplicitVR: true,
            byteOrder: .littleEndian,
            isDeflated: true
        )
        
        #expect(customTS.uid == "1.2.840.10008.1.2.1.99")
        #expect(customTS.isExplicitVR == true)
        #expect(customTS.byteOrder == .littleEndian)
        #expect(customTS.isEncapsulated == false)
        #expect(customTS.isDeflated == true)
    }
}

// MARK: - Lossless Capability & Selectable Encodings

@Suite("TransferSyntax: J2K/HTJ2K lossless capability & selectable encodings")
struct TransferSyntaxCapabilityTests {

    @Test("Lossless-only J2K/HTJ2K UIDs report .losslessOnly")
    func testLosslessOnlyCapability() {
        #expect(TransferSyntax.jpeg2000Lossless.losslessCapability == .losslessOnly)        // .90
        #expect(TransferSyntax.jpeg2000Part2Lossless.losslessCapability == .losslessOnly)   // .92
        #expect(TransferSyntax.htj2kLossless.losslessCapability == .losslessOnly)            // .201
        #expect(TransferSyntax.htj2kRPCLLossless.losslessCapability == .losslessOnly)        // .202
    }

    @Test("General J2K/HTJ2K UIDs report .both (lossless or lossy)")
    func testBothCapability() {
        #expect(TransferSyntax.jpeg2000.losslessCapability == .both)       // .91
        #expect(TransferSyntax.jpeg2000Part2.losslessCapability == .both)  // .93
        #expect(TransferSyntax.htj2kLossy.losslessCapability == .both)     // .203
    }

    @Test("A purely-lossy JPEG UID reports .lossyOnly")
    func testLossyOnlyCapability() {
        #expect(TransferSyntax.jpegBaseline.losslessCapability == .lossyOnly)
    }

    @Test("selectableEncodings expands .91/.93/.203 into two rows each")
    func testDualEntriesForBothCapableUIDs() {
        let j2kEncodings = TransferSyntax.selectableEncodings.filter { $0.transferSyntax.isJPEG2000 }

        // .90/.92/.201/.202 → exactly one row each; .91/.93/.203 → two rows each.
        func rows(for uid: String) -> [SelectableEncoding] { j2kEncodings.filter { $0.uid == uid } }
        #expect(rows(for: "1.2.840.10008.1.2.4.90").count == 1)
        #expect(rows(for: "1.2.840.10008.1.2.4.91").count == 2)
        #expect(rows(for: "1.2.840.10008.1.2.4.92").count == 1)
        #expect(rows(for: "1.2.840.10008.1.2.4.93").count == 2)
        #expect(rows(for: "1.2.840.10008.1.2.4.201").count == 1)
        #expect(rows(for: "1.2.840.10008.1.2.4.202").count == 1)
        #expect(rows(for: "1.2.840.10008.1.2.4.203").count == 2)

        // The full J2K/HTJ2K list is 4 single + 3 doubled = 10 rows.
        #expect(j2kEncodings.count == 10)
    }

    @Test("Every negotiableImageSyntaxTokens token parses back to its paired syntax")
    func testNegotiableImageTokensRoundTrip() {
        // This is the source-of-truth contract the dicom-retrieve / dicom-qr pickers and CLI
        // help depend on: each canonical token must resolve, via the SAME parser the CLIs use,
        // to exactly the transfer syntax it is paired with. If this fails, a negotiation surface
        // is offering a token the CLI would reject with "Unknown transfer syntax".
        for entry in TransferSyntax.negotiableImageSyntaxTokens {
            #expect(TransferSyntax.parse(entry.token) == entry.syntax,
                    "token '\(entry.token)' must parse to \(entry.syntax.displayName)")
        }
        // Derived list stays in lockstep with the pairs.
        #expect(TransferSyntax.negotiableImageTokens == TransferSyntax.negotiableImageSyntaxTokens.map(\.token))
    }

    @Test("negotiableImageSyntaxTokens has no duplicate tokens or UIDs")
    func testNegotiableImageTokensAreUnique() {
        let tokens = TransferSyntax.negotiableImageTokens
        #expect(Set(tokens).count == tokens.count)
        let uids = TransferSyntax.negotiableImageSyntaxTokens.map { $0.syntax.uid }
        #expect(Set(uids).count == uids.count)
    }

    @Test("negotiableImageSyntaxTokens covers current codecs and omits non-retrievable ones")
    func testNegotiableImageTokensCoverage() {
        let tokens = Set(TransferSyntax.negotiableImageTokens)
        // The codecs added in the JPEG 2000 Part 2 / JPEG-LS / JPEG XL work must all appear —
        // this is the regression guard against the old hand-maintained list that stopped at RLE.
        for token in ["jpeg-ls-lossless", "jpeg-ls", "jpeg-xl-lossless", "jpeg-xl",
                      "jpeg2000-part2-lossless", "jpeg2000-part2", "jpeg-extended",
                      "explicit-vr-be", "deflate"] {
            #expect(tokens.contains(token), "negotiation list should offer '\(token)'")
        }
        // Non-decodable / non-retrievable syntaxes are intentionally excluded.
        let uids = Set(TransferSyntax.negotiableImageSyntaxTokens.map { $0.syntax.uid })
        for excluded in [TransferSyntax.mpeg2MainProfile, .hevcH265MainProfile,
                         .jpipReferenced, .jp3dLossless, .jpegXLRecompression] {
            #expect(!uids.contains(excluded.uid), "\(excluded.displayName) should not be negotiable")
        }
    }

    @Test("The two .91 rows carry distinct intent, id, and displayName")
    func testNinetyOneLosslessAndLossyRows() {
        let rows = TransferSyntax.selectableEncodings.filter { $0.uid == "1.2.840.10008.1.2.4.91" }
        let lossless = rows.first { $0.intent == .lossless }
        let lossy = rows.first { $0.intent == .lossy }

        #expect(lossless != nil)
        #expect(lossy != nil)
        #expect(lossless?.isLossless == true)
        #expect(lossy?.isLossless == false)
        #expect(lossless?.displayName == "JPEG 2000 Image Compression (lossless)")
        #expect(lossy?.displayName == "JPEG 2000 Image Compression (lossy)")
        #expect(lossless?.shortName == "JPEG 2000 Lossless")
        #expect(lossy?.shortName == "JPEG 2000 Lossy")
        // Distinct identity so pickers/result maps can key on them independently.
        #expect(lossless?.id != lossy?.id)
        #expect(lossless?.id == "1.2.840.10008.1.2.4.91#lossless")
    }

    @Test("Lossless-only rows use .notApplicable intent and their canonical name")
    func testLosslessOnlyRow() {
        let row = TransferSyntax.selectableEncodings.first { $0.uid == "1.2.840.10008.1.2.4.90" }
        #expect(row?.intent == .notApplicable)
        #expect(row?.isLossless == true)
        #expect(row?.displayName == "JPEG 2000 Image Compression (Lossless Only)")
    }

    @Test("Canonical HTJ2K display names")
    func testHTJ2KDisplayNames() {
        // PS3.6 2026a Table A-1 names (D176); the old labels are `shortName`.
        #expect(TransferSyntax.htj2kLossless.displayName == "High-Throughput JPEG 2000 Image Compression (Lossless Only)")
        #expect(TransferSyntax.htj2kRPCLLossless.displayName == "High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)")
        #expect(TransferSyntax.htj2kLossy.displayName == "High-Throughput JPEG 2000 Image Compression")
        #expect(TransferSyntax.htj2kLossless.shortName == "HTJ2K Lossless Only")
        #expect(TransferSyntax.htj2kRPCLLossless.shortName == "HTJ2K Lossless Only (RPCL)")
        #expect(TransferSyntax.htj2kLossy.shortName == "HTJ2K")
    }

    @Test("from(uid:) stays deterministic despite two rows sharing a UID")
    func testFromUIDDeterministic() {
        // Both .91 rows share the same underlying TransferSyntax; from(uid:) is single-valued.
        #expect(TransferSyntax.from(uid: "1.2.840.10008.1.2.4.91") == .jpeg2000)
        for enc in TransferSyntax.selectableEncodings {
            #expect(TransferSyntax.from(uid: enc.uid) == enc.transferSyntax)
        }
    }

    @Test("parseEncoding resolves intent aliases for the general UIDs")
    func testParseEncodingIntentAliases() {
        #expect(TransferSyntax.parseEncoding("j2k-91-lossless")?.uid == "1.2.840.10008.1.2.4.91")
        #expect(TransferSyntax.parseEncoding("j2k-91-lossless")?.isLossless == true)
        #expect(TransferSyntax.parseEncoding("j2k-91-lossy")?.isLossless == false)
        #expect(TransferSyntax.parseEncoding("htj2k-203-lossless")?.uid == "1.2.840.10008.1.2.4.203")
        #expect(TransferSyntax.parseEncoding("htj2k-203-lossless")?.isLossless == true)

        // Symmetric naming: bare `…-lossless` encodes reversibly INTO the general UID;
        // `…-lossless-only` selects the distinct reversible-only UID.
        #expect(TransferSyntax.parseEncoding("j2k-lossless")?.uid == "1.2.840.10008.1.2.4.91")
        #expect(TransferSyntax.parseEncoding("j2k-lossless")?.isLossless == true)
        #expect(TransferSyntax.parseEncoding("j2k-lossless-only")?.uid == "1.2.840.10008.1.2.4.90")
        #expect(TransferSyntax.parseEncoding("j2k-lossless-only")?.isLossless == true)
        // JPEG XL general .112 is now both-capable: -lossless/-lossy resolve into it.
        #expect(TransferSyntax.parseEncoding("jpeg-xl-lossless")?.uid == "1.2.840.10008.1.2.4.112")
        #expect(TransferSyntax.parseEncoding("jpeg-xl-lossless")?.isLossless == true)
        #expect(TransferSyntax.parseEncoding("jpeg-xl-lossless-only")?.uid == "1.2.840.10008.1.2.4.110")
        // A bare general alias defaults to the lossy mode.
        #expect(TransferSyntax.parseEncoding("j2k")?.intent == .lossy)
        #expect(TransferSyntax.parseEncoding("htj2k")?.intent == .lossy)
    }

    @Test("CLI HTJ2K target aliases map to the canonical UIDs (parse is conservative)")
    func testHTJ2KTargetAliases() {
        // `parse` (UID-only) keeps `htj2k-lossless` on the reversible-only .201; the
        // encode-intent split (`htj2k-lossless` → .203 reversible) is in `parseEncoding`.
        #expect(TransferSyntax.parse("htj2k-lossless") == .htj2kLossless)           // .201
        #expect(TransferSyntax.parse("htj2k-lossless-only") == .htj2kLossless)      // .201
        #expect(TransferSyntax.parse("htj2k-rpcl-lossless-only") == .htj2kRPCLLossless) // .202
        #expect(TransferSyntax.parse("htj2k-rpcl") == .htj2kRPCLLossless)           // deprecated alias
        #expect(TransferSyntax.parse("htj2k") == .htj2kLossy)                       // .203
        // parseEncoding carries the intent split:
        #expect(TransferSyntax.parseEncoding("htj2k-lossless")?.uid == "1.2.840.10008.1.2.4.203")
        #expect(TransferSyntax.parseEncoding("htj2k-lossless")?.isLossless == true)
    }
}

// MARK: - PS3.6 2026a Table A-1 registry completeness (Q2, 2026-09-25)

@Suite("TransferSyntax registry vs PS3.6 2026a Table A-1")
struct TransferSyntaxRegistryCompletenessTests {

    @Test("allKnown covers every Transfer Syntax of Table A-1, plus exactly the 4 known non-registry UIDs")
    func testCoversTableA1() {
        let known = Set(TransferSyntax.allKnown.map(\.uid))
        let registry = DICOMUniqueIdentifier.transferSyntaxUIDs
        #expect(registry.subtracting(known).isEmpty, "missing: \(registry.subtracting(known).sorted())")
        let extras = known.subtracting(registry)
        #expect(extras == [TransferSyntax.jp3dLossless.uid, TransferSyntax.jp3dLossy.uid,
                           TransferSyntax.hevcH265MainProfileFragmentable.uid,
                           TransferSyntax.hevcH265Main10ProfileFragmentable.uid])
    }

    @Test("Every allKnown entry round-trips through from(uid:) and has a display name")
    func testRoundTrip() {
        for syntax in TransferSyntax.allKnown {
            #expect(TransferSyntax.from(uid: syntax.uid)?.uid == syntax.uid)
            #expect(syntax.displayName != syntax.description, Comment(rawValue: syntax.uid))
        }
        #expect(Set(TransferSyntax.allKnown.map(\.uid)).count == TransferSyntax.allKnown.count)
    }

    @Test("Retired syntaxes are flagged: Big Endian, 14 JPEG processes, MIME, XML, Papyrus")
    func testRetired() {
        let retired = TransferSyntax.allKnown.filter(\.isRetired)
        #expect(retired.count == 18)
        #expect(TransferSyntax.explicitVRBigEndian.isRetired)
        #expect(TransferSyntax.papyrus3ImplicitVRLittleEndianRetired.isRetired)
        #expect(!TransferSyntax.papyrus3ImplicitVRLittleEndianRetired.isExplicitVR)
        #expect(!TransferSyntax.jpegBaseline.isRetired)
        #expect(!TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.isRetired)
    }

    @Test("New syntaxes carry the right encoding properties")
    func testNewProperties() {
        #expect(TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.isEncapsulated)
        #expect(TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.isLossless)
        #expect(TransferSyntax.deflatedImageFrameCompression.isEncapsulated)
        #expect(TransferSyntax.deflatedImageFrameCompression.isLossless)
        #expect(TransferSyntax.jpipHTJ2KReferencedDeflate.isDeflated)
        #expect(!TransferSyntax.jpipHTJ2KReferenced.isEncapsulated)
        #expect(TransferSyntax.jpegLosslessProcess15Retired.isLossless)
        #expect(TransferSyntax.jpegExtendedProcess3And5Retired.lossyImageCompressionMethod == "ISO_10918_1")
        #expect(TransferSyntax.jpegLosslessProcess15Retired.lossyImageCompressionMethod == nil)
        #expect(TransferSyntax.from(uid: "1.2.840.10008.1.2.7.3")?.displayName == "SMPTE ST 2110-30 PCM Digital Audio")
    }
}

// MARK: - PS3.6 2026a Table A-1 keywords in parse / parseEncoding (P-CONVERT-TS-KEYWORDS, 2026-10-01)

@Suite("TransferSyntax.parse / parseEncoding: Table A-1 keywords select their Table A-1 UID")
struct TransferSyntaxTableA1KeywordTests {

    /// Every Transfer Syntax row of PS3.6 2026a Table A-1 (keyword → UID, 63 rows), dumped by
    /// Scripts/nema_docbook.py from part06_2026a.xml.
    static let tableA1: [String: String] = [
        "ImplicitVRLittleEndian": "1.2.840.10008.1.2",
        "ExplicitVRLittleEndian": "1.2.840.10008.1.2.1",
        "EncapsulatedUncompressedExplicitVRLittleEndian": "1.2.840.10008.1.2.1.98",
        "DeflatedExplicitVRLittleEndian": "1.2.840.10008.1.2.1.99",
        "ExplicitVRBigEndian": "1.2.840.10008.1.2.2",
        "MPEG2MPML": "1.2.840.10008.1.2.4.100",
        "MPEG2MPMLF": "1.2.840.10008.1.2.4.100.1",
        "MPEG2MPHL": "1.2.840.10008.1.2.4.101",
        "MPEG2MPHLF": "1.2.840.10008.1.2.4.101.1",
        "MPEG4HP41": "1.2.840.10008.1.2.4.102",
        "MPEG4HP41F": "1.2.840.10008.1.2.4.102.1",
        "MPEG4HP41BD": "1.2.840.10008.1.2.4.103",
        "MPEG4HP41BDF": "1.2.840.10008.1.2.4.103.1",
        "MPEG4HP422D": "1.2.840.10008.1.2.4.104",
        "MPEG4HP422DF": "1.2.840.10008.1.2.4.104.1",
        "MPEG4HP423D": "1.2.840.10008.1.2.4.105",
        "MPEG4HP423DF": "1.2.840.10008.1.2.4.105.1",
        "MPEG4HP42STEREO": "1.2.840.10008.1.2.4.106",
        "MPEG4HP42STEREOF": "1.2.840.10008.1.2.4.106.1",
        "HEVCMP51": "1.2.840.10008.1.2.4.107",
        "HEVCM10P51": "1.2.840.10008.1.2.4.108",
        "JPEGXLLossless": "1.2.840.10008.1.2.4.110",
        "JPEGXLJPEGRecompression": "1.2.840.10008.1.2.4.111",
        "JPEGXL": "1.2.840.10008.1.2.4.112",
        "HTJ2KLossless": "1.2.840.10008.1.2.4.201",
        "HTJ2KLosslessRPCL": "1.2.840.10008.1.2.4.202",
        "HTJ2K": "1.2.840.10008.1.2.4.203",
        "JPIPHTJ2KReferenced": "1.2.840.10008.1.2.4.204",
        "JPIPHTJ2KReferencedDeflate": "1.2.840.10008.1.2.4.205",
        "JPEGBaseline8Bit": "1.2.840.10008.1.2.4.50",
        "JPEGExtended12Bit": "1.2.840.10008.1.2.4.51",
        "JPEGExtended35": "1.2.840.10008.1.2.4.52",
        "JPEGSpectralSelectionNonHierarchical68": "1.2.840.10008.1.2.4.53",
        "JPEGSpectralSelectionNonHierarchical79": "1.2.840.10008.1.2.4.54",
        "JPEGFullProgressionNonHierarchical1012": "1.2.840.10008.1.2.4.55",
        "JPEGFullProgressionNonHierarchical1113": "1.2.840.10008.1.2.4.56",
        "JPEGLossless": "1.2.840.10008.1.2.4.57",
        "JPEGLosslessNonHierarchical15": "1.2.840.10008.1.2.4.58",
        "JPEGExtendedHierarchical1618": "1.2.840.10008.1.2.4.59",
        "JPEGExtendedHierarchical1719": "1.2.840.10008.1.2.4.60",
        "JPEGSpectralSelectionHierarchical2022": "1.2.840.10008.1.2.4.61",
        "JPEGSpectralSelectionHierarchical2123": "1.2.840.10008.1.2.4.62",
        "JPEGFullProgressionHierarchical2426": "1.2.840.10008.1.2.4.63",
        "JPEGFullProgressionHierarchical2527": "1.2.840.10008.1.2.4.64",
        "JPEGLosslessHierarchical28": "1.2.840.10008.1.2.4.65",
        "JPEGLosslessHierarchical29": "1.2.840.10008.1.2.4.66",
        "JPEGLosslessSV1": "1.2.840.10008.1.2.4.70",
        "JPEGLSLossless": "1.2.840.10008.1.2.4.80",
        "JPEGLSNearLossless": "1.2.840.10008.1.2.4.81",
        "JPEG2000Lossless": "1.2.840.10008.1.2.4.90",
        "JPEG2000": "1.2.840.10008.1.2.4.91",
        "JPEG2000MCLossless": "1.2.840.10008.1.2.4.92",
        "JPEG2000MC": "1.2.840.10008.1.2.4.93",
        "JPIPReferenced": "1.2.840.10008.1.2.4.94",
        "JPIPReferencedDeflate": "1.2.840.10008.1.2.4.95",
        "RLELossless": "1.2.840.10008.1.2.5",
        "RFC2557MIMEEncapsulation": "1.2.840.10008.1.2.6.1",
        "XMLEncoding": "1.2.840.10008.1.2.6.2",
        "SMPTEST211020UncompressedProgressiveActiveVideo": "1.2.840.10008.1.2.7.1",
        "SMPTEST211020UncompressedInterlacedActiveVideo": "1.2.840.10008.1.2.7.2",
        "SMPTEST211030PCMDigitalAudio": "1.2.840.10008.1.2.7.3",
        "DeflatedImageFrameCompression": "1.2.840.10008.1.2.8.1",
        "Papyrus3ImplicitVRLittleEndian": "1.2.840.10008.1.20",
    ]

    @Test("Every Table A-1 keyword parse accepts resolves to its Table A-1 UID")
    func everyAcceptedKeyword() {
        var accepted = 0
        for (keyword, uid) in Self.tableA1 {
            guard let ts = TransferSyntax.parse(keyword) else { continue }
            accepted += 1
            #expect(ts.uid == uid, "\(keyword)")
            #expect(TransferSyntax.parseEncoding(keyword)?.transferSyntax.uid == uid, "\(keyword) (parseEncoding)")
        }
        #expect(accepted >= 21)
    }

    @Test("JPEG2000Lossless / HTJ2KLossless / JPEGXLLossless select .90 / .201 / .110; …Reversible the old meaning")
    func reassigned() throws {
        #expect(TransferSyntax.reassignedTableA1Keywords.count == 3)
        for row in TransferSyntax.reassignedTableA1Keywords {
            #expect(Self.tableA1[row.keyword] == row.uid, "\(row.keyword)")
            let enc = try #require(TransferSyntax.parseEncoding(row.keyword))
            #expect(enc.transferSyntax.uid == row.uid)
            #expect(enc.isLossless)
            let old = try #require(TransferSyntax.parseEncoding(row.reversibleName))
            #expect(old.transferSyntax.uid == row.generalUID)
            #expect(old.intent == .lossless)
            let note = try #require(TransferSyntax.reassignedKeywordNote(for: row.keyword.uppercased()))
            #expect(note.contains(row.uid) && note.contains(row.name) && note.contains(row.reversibleName))
        }
        // The kebab aliases keep their meaning.
        #expect(TransferSyntax.parseEncoding("jpeg2000-lossless")?.uid == "1.2.840.10008.1.2.4.91")
        #expect(TransferSyntax.parseEncoding("htj2k-lossless")?.uid == "1.2.840.10008.1.2.4.203")
        #expect(TransferSyntax.reassignedKeywordNote(for: "jpeg2000-lossless") == nil)
    }
}
