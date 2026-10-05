/// DICOM Transfer Syntax
///
/// Defines the encoding rules for a DICOM data set, including byte ordering
/// and whether Value Representations (VR) are explicitly or implicitly encoded.
///
/// Reference: DICOM PS3.5 Section 10 - Transfer Syntax Specification
public struct TransferSyntax: Sendable, Hashable {
    /// Transfer Syntax UID
    public let uid: String
    
    /// Whether VR is explicitly encoded in data elements
    ///
    /// - Explicit VR: VR is encoded as 2 ASCII characters following the tag
    /// - Implicit VR: VR must be determined from the Data Element Dictionary
    ///
    /// Reference: PS3.5 Section 7.1
    public let isExplicitVR: Bool
    
    /// Byte ordering for multi-byte values
    ///
    /// Reference: PS3.5 Section 7.3
    public let byteOrder: ByteOrder
    
    /// Whether this transfer syntax uses encapsulated (compressed) pixel data
    ///
    /// Reference: PS3.5 Section A.4
    public let isEncapsulated: Bool
    
    /// Whether the data set is deflate compressed
    ///
    /// Reference: PS3.5 Section A.5
    public let isDeflated: Bool
    
    /// Creates a transfer syntax specification
    /// - Parameters:
    ///   - uid: Transfer Syntax UID
    ///   - isExplicitVR: Whether VR is explicitly encoded
    ///   - byteOrder: Byte ordering for multi-byte values
    ///   - isEncapsulated: Whether pixel data is encapsulated
    ///   - isDeflated: Whether data set uses deflate compression
    public init(uid: String, isExplicitVR: Bool, byteOrder: ByteOrder, isEncapsulated: Bool = false, isDeflated: Bool = false) {
        self.uid = uid
        self.isExplicitVR = isExplicitVR
        self.byteOrder = byteOrder
        self.isEncapsulated = isEncapsulated
        self.isDeflated = isDeflated
    }
}

// MARK: - Standard Transfer Syntaxes
extension TransferSyntax {
    /// Implicit VR Little Endian (1.2.840.10008.1.2)
    ///
    /// Default Transfer Syntax for DICOM.
    /// VR is not explicitly encoded and must be looked up from the Data Element Dictionary.
    ///
    /// Reference: PS3.5 Section A.1
    public static let implicitVRLittleEndian = TransferSyntax(
        uid: "1.2.840.10008.1.2",
        isExplicitVR: false,
        byteOrder: .littleEndian
    )
    
    /// Explicit VR Little Endian (1.2.840.10008.1.2.1)
    ///
    /// Most commonly used transfer syntax in modern DICOM implementations.
    /// VR is explicitly encoded as 2 ASCII characters following the tag.
    ///
    /// Reference: PS3.5 Section A.1
    public static let explicitVRLittleEndian = TransferSyntax(
        uid: "1.2.840.10008.1.2.1",
        isExplicitVR: true,
        byteOrder: .littleEndian
    )
    
    /// Deflated Explicit VR Little Endian (1.2.840.10008.1.2.1.99)
    ///
    /// Same encoding as Explicit VR Little Endian, but the Data Set is compressed
    /// using the Deflate algorithm (RFC 1951). The File Meta Information is not deflated.
    ///
    /// Reference: PS3.5 Section A.5
    public static let deflatedExplicitVRLittleEndian = TransferSyntax(
        uid: "1.2.840.10008.1.2.1.99",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isDeflated: true
    )
    
    /// Explicit VR Big Endian (1.2.840.10008.1.2.2) - Retired
    ///
    /// Retired in DICOM PS3.5 (2011). Included for compatibility with legacy files.
    /// VR is explicitly encoded, multi-byte values use big endian byte order.
    ///
    /// Reference: PS3.5 Section A.1
    public static let explicitVRBigEndian = TransferSyntax(
        uid: "1.2.840.10008.1.2.2",
        isExplicitVR: true,
        byteOrder: .bigEndian
    )
    
    // MARK: - JPEG Transfer Syntaxes
    
    /// JPEG Baseline (Process 1) (1.2.840.10008.1.2.4.50)
    ///
    /// Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression.
    /// Uses lossy compression with 8-bit samples.
    ///
    /// Reference: PS3.5 Section A.4.1
    public static let jpegBaseline = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.50",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// JPEG Extended (Process 2 & 4) (1.2.840.10008.1.2.4.51)
    ///
    /// Default Transfer Syntax for Lossy JPEG 12 Bit Image Compression.
    /// Uses lossy compression with 8 or 12-bit samples.
    ///
    /// Reference: PS3.5 Section A.4.2
    public static let jpegExtended = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.51",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// JPEG Lossless, Non-Hierarchical (Process 14) (1.2.840.10008.1.2.4.57)
    ///
    /// Lossless JPEG compression.
    ///
    /// Reference: PS3.5 Section A.4.3
    public static let jpegLossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.57",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14, Selection Value 1) (1.2.840.10008.1.2.4.70)
    ///
    /// Default Transfer Syntax for Lossless JPEG Image Compression.
    /// Most commonly used lossless JPEG transfer syntax.
    ///
    /// Reference: PS3.5 Section A.4.3
    public static let jpegLosslessSV1 = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.70",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    // MARK: - JPEG 2000 Transfer Syntaxes
    
    /// JPEG 2000 Image Compression (Lossless Only) (1.2.840.10008.1.2.4.90)
    ///
    /// JPEG 2000 lossless image compression.
    ///
    /// Reference: PS3.5 Section A.4.4
    public static let jpeg2000Lossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.90",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// JPEG 2000 Image Compression (1.2.840.10008.1.2.4.91)
    ///
    /// JPEG 2000 lossy image compression.
    ///
    /// Reference: PS3.5 Section A.4.4
    public static let jpeg2000 = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.91",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only) (1.2.840.10008.1.2.4.92)
    public static let jpeg2000Part2Lossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.92",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG 2000 Part 2 Multi-component Image Compression (1.2.840.10008.1.2.4.93)
    public static let jpeg2000Part2 = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.93",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// High-Throughput JPEG 2000 Image Compression (Lossless Only) (1.2.840.10008.1.2.4.201)
    public static let htj2kLossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.201",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// High-Throughput JPEG 2000 with RPCL options (Lossless Only) (1.2.840.10008.1.2.4.202)
    public static let htj2kRPCLLossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.202",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// High-Throughput JPEG 2000 Image Compression (1.2.840.10008.1.2.4.203)
    public static let htj2kLossy = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.203",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    // MARK: - JP3D Experimental Transfer Syntaxes
    
    /// JP3D Lossless (Experimental) — private vendor extension
    ///
    /// ISO/IEC 15444-10 volumetric JPEG 2000 lossless compression.
    /// DICOM does not define a standard JP3D transfer syntax; this private UID
    /// is used for round-trip testing and internal storage only.
    /// Clearly labelled experimental — not for interoperability.
    public static let jp3dLossless = TransferSyntax(
        uid: "1.2.826.0.1.3680043.10.511.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// JP3D Lossy (Experimental) — private vendor extension
    ///
    /// ISO/IEC 15444-10 volumetric JPEG 2000 lossy compression.
    /// DICOM does not define a standard JP3D transfer syntax; this private UID
    /// is used for round-trip testing and internal storage only.
    /// Clearly labelled experimental — not for interoperability.
    public static let jp3dLossy = TransferSyntax(
        uid: "1.2.826.0.1.3680043.10.511.2",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    // MARK: - JPIP Transfer Syntaxes
    
    /// JPIP Referenced (1.2.840.10008.1.2.4.94)
    ///
    /// JPEG 2000 Interactive Protocol — the pixel data is a URI reference to a
    /// JPIP server endpoint rather than inline pixel data.
    /// Reference: PS3.6 2026a Table A-1, PS3.5 2026a Annex A.6 (was cited as A.8, which is SMPTE ST 2110-20)
    public static let jpipReferenced = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.94",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )
    
    /// JPIP Referenced Deflate (1.2.840.10008.1.2.4.95)
    ///
    /// Like ``jpipReferenced`` but the DICOM dataset is deflate-compressed.
    /// Reference: PS3.6 2026a Table A-1, PS3.5 2026a Annex A.7
    public static let jpipReferencedDeflate = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.95",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false,
        isDeflated: true
    )
    
    // MARK: - JPEG-LS Transfer Syntaxes
    
    /// JPEG-LS Lossless Image Compression (1.2.840.10008.1.2.4.80)
    ///
    /// JPEG-LS lossless image compression using the HP LOCO-I/JPEG-LS algorithm.
    ///
    /// Reference: PS3.5 Section A.4.5, ITU-T T.87 / ISO/IEC 14495-1
    public static let jpegLSLossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.80",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// JPEG-LS Lossy (Near-Lossless) Image Compression (1.2.840.10008.1.2.4.81)
    ///
    /// JPEG-LS near-lossless image compression using the HP LOCO-I/JPEG-LS algorithm
    /// with a configurable maximum error tolerance (NEAR parameter).
    ///
    /// Reference: PS3.5 Section A.4.5, ITU-T T.87 / ISO/IEC 14495-1
    public static let jpegLSNearLossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.81",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    // MARK: - JPEG XL Transfer Syntaxes
    //
    // NEMA-verified: 2026a, checked 2026-09-24 — text-diffed against the frozen 2026a text.
    // NEMA-verified: 2026a, checked 2026-09-25 — the whole registry was diffed against the 63
    // Transfer Syntax rows of PS3.6 2026a Table A-1 and the 22 missing ones added (Q2); the
    // JP3D pair is private and the two HEVC "Fragmentable" UIDs are unregistered but kept by decision.
    // NEMA-verified: 2026a, checked 2026-10-01 — `displayName` returns the PS3.6 2026a Table A-1
    // "UID Name" of all 63 Transfer Syntax rows verbatim (dumped by script; 48 had differed, old
    // abbreviations kept as `shortName`, D176); `isJPIP` covers the 4 JPIP rows .94/.95/.204/.205
    // (PS3.5 2026a A.6, A.7, A.11, A.12; D109).
    // UIDs .4.110/.111/.112 match PS3.6 Table A-1 (name, keyword, type "Transfer Syntax").
    // PS3.5 §10.19 and §A.4.12 are present. Explicit VR, Little Endian and encapsulated
    // agree with PS3.5 §A.4. `.112` may be lossy or lossless (§A.4.12), and (0028,2114)
    // `ISO_18181_1` matches PS3.3 C.7.6.1.1.5. Provenance: Sup 232 (2024d).

    /// JPEG XL Lossless Image Compression (1.2.840.10008.1.2.4.110)
    ///
    /// Mathematically lossless JPEG XL compression that preserves the exact bits
    /// of the original image.
    ///
    /// Reference: PS3.5 Section 10.19 and A.4.12 (Supplement 232, DICOM 2024d),
    /// ISO/IEC 18181 (JPEG XL)
    public static let jpegXLLossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.110",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG XL JPEG Recompression (1.2.840.10008.1.2.4.111)
    ///
    /// Losslessly transcodes existing (possibly lossy) JPEG-encoded data into
    /// JPEG XL, preserving the exact bits of the original JPEG encoding so the
    /// source JPEG can be reconstructed without any additional loss.
    ///
    /// Reference: PS3.5 Section 10.19 and A.4.12 (Supplement 232, DICOM 2024d),
    /// ISO/IEC 18181 (JPEG XL)
    public static let jpegXLRecompression = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.111",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG XL Image Compression (1.2.840.10008.1.2.4.112)
    ///
    /// General JPEG XL compression scheme permitting any JPEG XL mode — lossy,
    /// lossless, or JPEG recompression. Treated as potentially lossy.
    ///
    /// Reference: PS3.5 Section 10.19 and A.4.12 (Supplement 232, DICOM 2024d),
    /// ISO/IEC 18181 (JPEG XL)
    public static let jpegXL = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.112",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    // MARK: - RLE Transfer Syntax
    
    /// RLE Lossless (1.2.840.10008.1.2.5)
    ///
    /// Run-length encoding lossless compression.
    ///
    /// Reference: PS3.5 Section A.4.2 and Annex G
    public static let rleLossless = TransferSyntax(
        uid: "1.2.840.10008.1.2.5",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    // MARK: - Video Transfer Syntaxes
    
    /// MPEG2 Main Profile @ Main Level (1.2.840.10008.1.2.4.100)
    ///
    /// MPEG2 video compression at Main Profile, Main Level.
    /// Supports up to 720x576 at 30fps or 720x480 at 30fps.
    ///
    /// Reference: PS3.5 Section A.4.5
    public static let mpeg2MainProfile = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.100",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// MPEG2 Main Profile @ High Level (1.2.840.10008.1.2.4.101)
    ///
    /// MPEG2 video compression at Main Profile, High Level.
    /// Supports up to 1920x1080 at 30fps (HD video).
    ///
    /// Reference: PS3.5 Section A.4.5
    public static let mpeg2MainProfileHighLevel = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.101",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// MPEG-4 AVC/H.264 High Profile / Level 4.1 (1.2.840.10008.1.2.4.102)
    ///
    /// H.264/AVC video compression at High Profile, Level 4.1.
    /// Supports up to 1920x1080 at 30fps or 1280x720 at 60fps.
    ///
    /// Reference: PS3.5 Section A.4.6
    public static let mpeg4AVCHP41 = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.102",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// MPEG-4 AVC/H.264 BD-compatible High Profile / Level 4.1 (1.2.840.10008.1.2.4.103)
    ///
    /// H.264/AVC video compression compatible with Blu-ray Disc format.
    /// Supports up to 1920x1080 at 30fps.
    ///
    /// Reference: PS3.5 Section A.4.6
    public static let mpeg4AVCHP41BD = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.103",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// HEVC/H.265 Main Profile / Level 5.1 (1.2.840.10008.1.2.4.107)
    ///
    /// H.265/HEVC video compression at Main Profile, Level 5.1, Main tier: 8-bit
    /// 4:2:0 up to 4K at 60 frames per second. A Fragmentable Encapsulated Transfer
    /// Syntax in its own right; there is no ".1" variant.
    ///
    /// Reference: PS3.5 Sections 8.2.10 and A.4.7
    public static let hevcH265MainProfile = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.107",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    
    /// HEVC/H.265 Main 10 Profile / Level 5.1 (1.2.840.10008.1.2.4.108)
    ///
    /// H.265/HEVC video compression at Main 10 Profile, Level 5.1, Main tier:
    /// 10-bit 4:2:0 up to 4K at 60 frames per second. A Fragmentable Encapsulated
    /// Transfer Syntax in its own right; there is no ".1" variant.
    ///
    /// Reference: PS3.5 Sections 8.2.11 and A.4.7
    public static let hevcH265Main10Profile = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.108",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    // MARK: - Video Transfer Syntaxes (H.264 Level 4.2 and Stereo)

    /// MPEG-4 AVC/H.264 High Profile / Level 4.2 For 2D Video (1.2.840.10008.1.2.4.104)
    ///
    /// H.264/AVC video at High Profile, Level 4.2. Level 4.2 covers 1920x1080 at
    /// 60fps, which Level 4.1 cannot represent. Required of endoscopy Image Archives
    /// by IHE Endoscopy Image Archiving (EIA) Table 3.10.4.1.3.1-2.
    ///
    /// Reference: PS3.5 Section A.4.6, Section 8.2.8
    public static let mpeg4AVCHP42For2DVideo = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.104",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// MPEG-4 AVC/H.264 High Profile / Level 4.2 For 3D Video (1.2.840.10008.1.2.4.105)
    ///
    /// H.264/AVC video at High Profile, Level 4.2, carrying 3D video.
    ///
    /// Reference: PS3.5 Section A.4.6, Section 8.2.8
    public static let mpeg4AVCHP42For3DVideo = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.105",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// MPEG-4 AVC/H.264 Stereo High Profile / Level 4.2 (1.2.840.10008.1.2.4.106)
    ///
    /// H.264/AVC video at Stereo High Profile, Level 4.2 (MVC stereo pair).
    ///
    /// Reference: PS3.5 Section A.4.6, Section 8.2.9
    public static let mpeg4AVCStereoHP42 = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.106",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    // MARK: - Video Transfer Syntaxes (Fragmentable Variants)
    //
    // Each non-fragmentable video UID has a "….1" twin in which the bit stream MAY
    // be split across multiple fragments. The non-fragmentable form requires exactly
    // one fragment holding the whole bit stream. See `allowsMultipleFragments`.
    //
    // Reference: PS3.5 Sections A.4.5 - A.4.7

    /// Fragmentable MPEG2 Main Profile @ Main Level (1.2.840.10008.1.2.4.100.1)
    public static let mpeg2MainProfileFragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.100.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// Fragmentable MPEG2 Main Profile @ High Level (1.2.840.10008.1.2.4.101.1)
    public static let mpeg2MainProfileHighLevelFragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.101.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.1 (1.2.840.10008.1.2.4.102.1)
    public static let mpeg4AVCHP41Fragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.102.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// Fragmentable MPEG-4 AVC/H.264 BD-compatible High Profile / Level 4.1 (1.2.840.10008.1.2.4.103.1)
    public static let mpeg4AVCHP41BDFragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.103.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.2 For 2D Video (1.2.840.10008.1.2.4.104.1)
    public static let mpeg4AVCHP42For2DVideoFragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.104.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.2 For 3D Video (1.2.840.10008.1.2.4.105.1)
    public static let mpeg4AVCHP42For3DVideoFragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.105.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// Fragmentable MPEG-4 AVC/H.264 Stereo High Profile / Level 4.2 (1.2.840.10008.1.2.4.106.1)
    public static let mpeg4AVCStereoHP42Fragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.106.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )
    

    /// Fragmentable HEVC/H.265 Main Profile / Level 5.1 (1.2.840.10008.1.2.4.107.1)
    public static let hevcH265MainProfileFragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.107.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// Fragmentable HEVC/H.265 Main 10 Profile / Level 5.1 (1.2.840.10008.1.2.4.108.1)
    public static let hevcH265Main10ProfileFragmentable = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.108.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    // MARK: - Transfer Syntaxes added 2026-09-25 to complete PS3.6 2026a Table A-1 (Q2)

    /// Encapsulated Uncompressed Explicit VR Little Endian (PS3.5 A.4.11): native pixel cells, one Fragment per Frame.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.1.98
    public static let encapsulatedUncompressedExplicitVRLittleEndian = TransferSyntax(
        uid: "1.2.840.10008.1.2.1.98",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPIP HTJ2K Referenced (PS3.5 A.11): Pixel Data (7FE0,0010) is absent and the pixel data is
    /// referenced through Pixel Data Provider URL (0028,7FE0), as with ``jpipReferenced``;
    /// Photometric Interpretation is limited to MONOCHROME1, MONOCHROME2, YBR_ICT and YBR_RCT.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.204
    public static let jpipHTJ2KReferenced = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.204",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )

    /// JPIP HTJ2K Referenced Deflate: like ``jpipHTJ2KReferenced`` with a deflate-compressed data set.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.205
    public static let jpipHTJ2KReferencedDeflate = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.205",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false,
        isDeflated: true
    )

    /// SMPTE ST 2110-20 Uncompressed Progressive Active Video (DICOM Real-Time Video, PS3.22). Not a file-storage syntax.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.7.1
    public static let smpteST2110_20UncompressedProgressiveVideo = TransferSyntax(
        uid: "1.2.840.10008.1.2.7.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )

    /// SMPTE ST 2110-20 Uncompressed Interlaced Active Video (DICOM Real-Time Video, PS3.22). Not a file-storage syntax.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.7.2
    public static let smpteST2110_20UncompressedInterlacedVideo = TransferSyntax(
        uid: "1.2.840.10008.1.2.7.2",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )

    /// SMPTE ST 2110-30 PCM Digital Audio (DICOM Real-Time Video, PS3.22). Not a file-storage syntax.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.7.3
    public static let smpteST2110_30PCMDigitalAudio = TransferSyntax(
        uid: "1.2.840.10008.1.2.7.3",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )

    /// Deflated Image Frame Compression (PS3.5 A.4.13): each Frame deflate-compressed into one Fragment.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.8.1
    public static let deflatedImageFrameCompression = TransferSyntax(
        uid: "1.2.840.10008.1.2.8.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Extended (Process 3 & 5). Retired 2001; kept so legacy files can be identified.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.52 — RET (2001)
    public static let jpegExtendedProcess3And5Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.52",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Spectral Selection, Non-Hierarchical (Process 6 & 8). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.53 — RET (2001)
    public static let jpegSpectralSelectionProcess6And8Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.53",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Spectral Selection, Non-Hierarchical (Process 7 & 9). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.54 — RET (2001)
    public static let jpegSpectralSelectionProcess7And9Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.54",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Full Progression, Non-Hierarchical (Process 10 & 12). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.55 — RET (2001)
    public static let jpegFullProgressionProcess10And12Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.55",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Full Progression, Non-Hierarchical (Process 11 & 13). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.56 — RET (2001)
    public static let jpegFullProgressionProcess11And13Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.56",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Lossless, Non-Hierarchical (Process 15). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.58 — RET (2001)
    public static let jpegLosslessProcess15Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.58",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Extended, Hierarchical (Process 16 & 18). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.59 — RET (2001)
    public static let jpegExtendedHierarchicalProcess16And18Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.59",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Extended, Hierarchical (Process 17 & 19). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.60 — RET (2001)
    public static let jpegExtendedHierarchicalProcess17And19Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.60",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Spectral Selection, Hierarchical (Process 20 & 22). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.61 — RET (2001)
    public static let jpegSpectralSelectionHierarchicalProcess20And22Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.61",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Spectral Selection, Hierarchical (Process 21 & 23). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.62 — RET (2001)
    public static let jpegSpectralSelectionHierarchicalProcess21And23Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.62",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Full Progression, Hierarchical (Process 24 & 26). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.63 — RET (2001)
    public static let jpegFullProgressionHierarchicalProcess24And26Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.63",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Full Progression, Hierarchical (Process 25 & 27). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.64 — RET (2001)
    public static let jpegFullProgressionHierarchicalProcess25And27Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.64",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Lossless, Hierarchical (Process 28). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.65 — RET (2001)
    public static let jpegLosslessHierarchicalProcess28Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.65",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// JPEG Lossless, Hierarchical (Process 29). Retired 2001.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.4.66 — RET (2001)
    public static let jpegLosslessHierarchicalProcess29Retired = TransferSyntax(
        uid: "1.2.840.10008.1.2.4.66",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: true
    )

    /// RFC 2557 MIME encapsulation. Retired 2018b; the data set is not a DICOM binary encoding, so this library only identifies the UID.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.6.1 — RET (2018b)
    public static let rfc2557MIMEEncapsulationRetired = TransferSyntax(
        uid: "1.2.840.10008.1.2.6.1",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )

    /// XML Encoding. Retired 2018b; identified only, not parsed.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.2.6.2 — RET (2018b)
    public static let xmlEncodingRetired = TransferSyntax(
        uid: "1.2.840.10008.1.2.6.2",
        isExplicitVR: true,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )

    /// Papyrus 3 Implicit VR Little Endian. Retired 2015c; reads as Implicit VR Little Endian.
    /// PS3.6 2026a Table A-1: 1.2.840.10008.1.20 — RET (2015c)
    public static let papyrus3ImplicitVRLittleEndianRetired = TransferSyntax(
        uid: "1.2.840.10008.1.20",
        isExplicitVR: false,
        byteOrder: .littleEndian,
        isEncapsulated: false
    )

    /// Creates a TransferSyntax from a UID string
    ///
    /// Returns nil if the UID is not a recognized transfer syntax.
    /// - Parameter uid: Transfer Syntax UID string
    /// - Returns: TransferSyntax if recognized, nil otherwise
    public static func from(uid: String) -> TransferSyntax? {
        switch uid {
        // Uncompressed
        case implicitVRLittleEndian.uid:
            return .implicitVRLittleEndian
        case explicitVRLittleEndian.uid:
            return .explicitVRLittleEndian
        case deflatedExplicitVRLittleEndian.uid:
            return .deflatedExplicitVRLittleEndian
        case explicitVRBigEndian.uid:
            return .explicitVRBigEndian
        // JPEG
        case jpegBaseline.uid:
            return .jpegBaseline
        case jpegExtended.uid:
            return .jpegExtended
        case jpegLossless.uid:
            return .jpegLossless
        case jpegLosslessSV1.uid:
            return .jpegLosslessSV1
        // JPEG 2000
        case jpeg2000Lossless.uid:
            return .jpeg2000Lossless
        case jpeg2000.uid:
            return .jpeg2000
        case jpeg2000Part2Lossless.uid:
            return .jpeg2000Part2Lossless
        case jpeg2000Part2.uid:
            return .jpeg2000Part2
        case htj2kLossless.uid:
            return .htj2kLossless
        case htj2kRPCLLossless.uid:
            return .htj2kRPCLLossless
        case htj2kLossy.uid:
            return .htj2kLossy
        // JP3D (experimental)
        case jp3dLossless.uid:
            return .jp3dLossless
        case jp3dLossy.uid:
            return .jp3dLossy
        // JPIP
        case jpipReferenced.uid:
            return .jpipReferenced
        case jpipReferencedDeflate.uid:
            return .jpipReferencedDeflate
        // JPEG-LS
        case jpegLSLossless.uid:
            return .jpegLSLossless
        case jpegLSNearLossless.uid:
            return .jpegLSNearLossless
        // JPEG XL
        case jpegXLLossless.uid:
            return .jpegXLLossless
        case jpegXLRecompression.uid:
            return .jpegXLRecompression
        case jpegXL.uid:
            return .jpegXL
        // RLE
        case rleLossless.uid:
            return .rleLossless
        // Video
        case mpeg2MainProfile.uid:
            return .mpeg2MainProfile
        case mpeg2MainProfileHighLevel.uid:
            return .mpeg2MainProfileHighLevel
        case mpeg4AVCHP41.uid:
            return .mpeg4AVCHP41
        case mpeg4AVCHP41BD.uid:
            return .mpeg4AVCHP41BD
        case mpeg4AVCHP42For2DVideo.uid:
            return .mpeg4AVCHP42For2DVideo
        case mpeg4AVCHP42For3DVideo.uid:
            return .mpeg4AVCHP42For3DVideo
        case mpeg4AVCStereoHP42.uid:
            return .mpeg4AVCStereoHP42
        case hevcH265MainProfile.uid:
            return .hevcH265MainProfile
        case hevcH265Main10Profile.uid:
            return .hevcH265Main10Profile
        // Video (fragmentable variants)
        case mpeg2MainProfileFragmentable.uid:
            return .mpeg2MainProfileFragmentable
        case mpeg2MainProfileHighLevelFragmentable.uid:
            return .mpeg2MainProfileHighLevelFragmentable
        case mpeg4AVCHP41Fragmentable.uid:
            return .mpeg4AVCHP41Fragmentable
        case mpeg4AVCHP41BDFragmentable.uid:
            return .mpeg4AVCHP41BDFragmentable
        case mpeg4AVCHP42For2DVideoFragmentable.uid:
            return .mpeg4AVCHP42For2DVideoFragmentable
        case mpeg4AVCHP42For3DVideoFragmentable.uid:
            return .mpeg4AVCHP42For3DVideoFragmentable
        case mpeg4AVCStereoHP42Fragmentable.uid:
            return .mpeg4AVCStereoHP42Fragmentable
        case hevcH265MainProfileFragmentable.uid:
            return .hevcH265MainProfileFragmentable
        case hevcH265Main10ProfileFragmentable.uid:
            return .hevcH265Main10ProfileFragmentable
        // Added 2026-09-25 (PS3.6 2026a Table A-1 completion)
        case encapsulatedUncompressedExplicitVRLittleEndian.uid:
            return .encapsulatedUncompressedExplicitVRLittleEndian
        case jpipHTJ2KReferenced.uid:
            return .jpipHTJ2KReferenced
        case jpipHTJ2KReferencedDeflate.uid:
            return .jpipHTJ2KReferencedDeflate
        case smpteST2110_20UncompressedProgressiveVideo.uid:
            return .smpteST2110_20UncompressedProgressiveVideo
        case smpteST2110_20UncompressedInterlacedVideo.uid:
            return .smpteST2110_20UncompressedInterlacedVideo
        case smpteST2110_30PCMDigitalAudio.uid:
            return .smpteST2110_30PCMDigitalAudio
        case deflatedImageFrameCompression.uid:
            return .deflatedImageFrameCompression
        case jpegExtendedProcess3And5Retired.uid:
            return .jpegExtendedProcess3And5Retired
        case jpegSpectralSelectionProcess6And8Retired.uid:
            return .jpegSpectralSelectionProcess6And8Retired
        case jpegSpectralSelectionProcess7And9Retired.uid:
            return .jpegSpectralSelectionProcess7And9Retired
        case jpegFullProgressionProcess10And12Retired.uid:
            return .jpegFullProgressionProcess10And12Retired
        case jpegFullProgressionProcess11And13Retired.uid:
            return .jpegFullProgressionProcess11And13Retired
        case jpegLosslessProcess15Retired.uid:
            return .jpegLosslessProcess15Retired
        case jpegExtendedHierarchicalProcess16And18Retired.uid:
            return .jpegExtendedHierarchicalProcess16And18Retired
        case jpegExtendedHierarchicalProcess17And19Retired.uid:
            return .jpegExtendedHierarchicalProcess17And19Retired
        case jpegSpectralSelectionHierarchicalProcess20And22Retired.uid:
            return .jpegSpectralSelectionHierarchicalProcess20And22Retired
        case jpegSpectralSelectionHierarchicalProcess21And23Retired.uid:
            return .jpegSpectralSelectionHierarchicalProcess21And23Retired
        case jpegFullProgressionHierarchicalProcess24And26Retired.uid:
            return .jpegFullProgressionHierarchicalProcess24And26Retired
        case jpegFullProgressionHierarchicalProcess25And27Retired.uid:
            return .jpegFullProgressionHierarchicalProcess25And27Retired
        case jpegLosslessHierarchicalProcess28Retired.uid:
            return .jpegLosslessHierarchicalProcess28Retired
        case jpegLosslessHierarchicalProcess29Retired.uid:
            return .jpegLosslessHierarchicalProcess29Retired
        case rfc2557MIMEEncapsulationRetired.uid:
            return .rfc2557MIMEEncapsulationRetired
        case xmlEncodingRetired.uid:
            return .xmlEncodingRetired
        case papyrus3ImplicitVRLittleEndianRetired.uid:
            return .papyrus3ImplicitVRLittleEndianRetired
        default:
            return nil
        }
    }

    /// Parses a transfer syntax from a user-facing alias or UID string.
    ///
    /// Accepts standard UIDs plus common CLI names such as
    /// explicit-vr-le, jpeg2000-lossless, htj2k-lossless, htj2k-rpcl, and htj2k.
    ///
    /// - Parameter nameOrUID: The transfer syntax alias or UID.
    /// - Returns: The matching transfer syntax, or nil when unrecognized.
    public static func parse(_ nameOrUID: String) -> TransferSyntax? {
        let trimmed = nameOrUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let syntax = from(uid: trimmed) {
            return syntax
        }

        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalized {
        case "implicitvrlittleendian", "implicit-vr-le", "implicit", "ivle":
            return .implicitVRLittleEndian
        case "explicitvrlittleendian", "explicit-vr-le", "explicit", "evle":
            return .explicitVRLittleEndian
        case "explicitvrbigendian", "explicit-vr-be", "big-endian", "evbe":
            return .explicitVRBigEndian
        case "deflate", "deflated-explicit-vr-le", "deflatedexplicitvrlittleendian":
            return .deflatedExplicitVRLittleEndian
        case "jpeg-baseline", "jpegbaseline", "jpeg", "jpegbaseline8bit":
            return .jpegBaseline
        case "jpeg-extended", "jpegextended", "jpegextended12bit":
            return .jpegExtended
        case "jpeg-lossless", "jpeglossless":
            return .jpegLossless
        case "jpeg-lossless-sv1", "jpeglosslesssv1":
            return .jpegLosslessSV1
        // `parse` returns the UID only and carries NO encode intent, so it is deliberately
        // CONSERVATIVE: the bare `…-lossless` names keep their conventional reversible-only
        // UID (so UID-lookup and association negotiation — dicom-send/retrieve/qr — are
        // unchanged). The lossy/lossless-INTO-the-general-UID split lives entirely in
        // `parseEncoding` (and `CompressionManager.codecMap`), which the encode paths use.
        case "jpeg2000-lossless", "jpeg2000lossless", "j2k-lossless",
             "jpeg2000-lossless-only", "jpeg2000losslessonly", "j2k-lossless-only":
            return .jpeg2000Lossless         // .90 reversible-only
        case "jpeg2000", "jpeg2000-lossy", "j2k", "j2k-lossy":
            return .jpeg2000                 // .91 general
        case "jpeg2000-part2-lossless", "jpeg2000part2lossless", "j2k-part2-lossless",
             "jpeg2000-part2-lossless-only", "j2k-part2-lossless-only", "jpeg2000mclossless":
            return .jpeg2000Part2Lossless    // .92 reversible-only
        case "jpeg2000-part2", "jpeg2000part2", "j2k-part2", "j2k-part2-lossy", "jpeg2000mc":
            return .jpeg2000Part2            // .93 general
        case "htj2k-lossless", "htj2klossless", "htj2k-lossless-only":
            return .htj2kLossless            // .201 reversible-only
        case "htj2k-rpcl-lossless-only", "htj2k-rpcl", "htj2k-lossless-rpcl", "htj2krpcllossless",
             "htj2klosslessrpcl":
            return .htj2kRPCLLossless        // .202 reversible-only (RPCL)
        case "htj2k", "htj2k-lossy", "htj2klossy":
            return .htj2kLossy               // .203 general
        case "jpeg-ls-lossless", "jpegls-lossless", "jls-lossless", "jpeglslossless":
            return .jpegLSLossless
        case "jpeg-ls", "jpegls", "jls", "jpeglsnearlossless":
            return .jpegLSNearLossless
        case "jpeg-xl-lossless", "jpegxl-lossless", "jxl-lossless",
             "jpeg-xl-lossless-only", "jpegxl-lossless-only", "jxl-lossless-only", "jpegxllossless":
            return .jpegXLLossless           // .110 reversible-only
        case "jpeg-xl-recompression", "jpegxl-recompression",
             "jpeg-xl-jpeg-recompression", "jxl-recompression", "jpegxljpegrecompression":
            return .jpegXLRecompression
        case "jpeg-xl", "jpegxl", "jxl", "jpeg-xl-lossy", "jxl-lossy":
            return .jpegXL                   // .112 general
        case "rle", "rle-lossless", "rlelossless":
            return .rleLossless
        case "jp3d-lossless", "jp3dlossless":
            return .jp3dLossless
        case "jp3d", "jp3d-lossy", "jp3dlossy":
            return .jp3dLossy
        case "jpip", "jpip-referenced":
            return .jpipReferenced
        case "jpip-deflate", "jpip-referenced-deflate":
            return .jpipReferencedDeflate
        default:
            return nil
        }
    }
    
    /// Whether this transfer syntax uses JPEG compression
    public var isJPEG: Bool {
        switch uid {
        case TransferSyntax.jpegBaseline.uid,
             TransferSyntax.jpegExtended.uid,
             TransferSyntax.jpegLossless.uid,
             TransferSyntax.jpegLosslessSV1.uid:
            return true
        default:
            return false
        }
    }
    
    /// Whether this transfer syntax uses JPEG 2000 compression
    public var isJPEG2000: Bool {
        switch uid {
        case TransferSyntax.jpeg2000Lossless.uid,
             TransferSyntax.jpeg2000.uid,
             TransferSyntax.jpeg2000Part2Lossless.uid,
             TransferSyntax.jpeg2000Part2.uid,
             TransferSyntax.htj2kLossless.uid,
             TransferSyntax.htj2kRPCLLossless.uid,
             TransferSyntax.htj2kLossy.uid:
            return true
        default:
            return false
        }
    }

    /// Whether this transfer syntax uses JPEG 2000 Part 2 compression.
    public var isJPEG2000Part2: Bool {
        switch uid {
        case TransferSyntax.jpeg2000Part2Lossless.uid,
             TransferSyntax.jpeg2000Part2.uid:
            return true
        default:
            return false
        }
    }

    /// Whether this transfer syntax uses High-Throughput JPEG 2000 compression.
    public var isHTJ2K: Bool {
        switch uid {
        case TransferSyntax.htj2kLossless.uid,
             TransferSyntax.htj2kRPCLLossless.uid,
             TransferSyntax.htj2kLossy.uid:
            return true
        default:
            return false
        }
    }
    
    /// Whether this transfer syntax is a JPIP referenced transfer syntax.
    ///
    /// In a Data Set encoded with one of them "Pixel Data (7FE0,0010) shall not be present, but
    /// rather Pixel Data shall be referenced via Data Element (0028,7FE0) Pixel Data Provider URL";
    /// the URL points to a JPIP server where the JPEG 2000 / HTJ2K image resides. These are the
    /// four "JPIP" rows of PS3.6 2026a Table A-1: JPIP Referenced (.94, PS3.5 A.6), JPIP Referenced
    /// Deflate (.95, A.7), JPIP HTJ2K Referenced (.204, A.11) and JPIP HTJ2K Referenced Deflate
    /// (.205, A.12). Before 2026-10-01 the HTJ2K pair was missing (D109).
    public var isJPIP: Bool {
        switch uid {
        case TransferSyntax.jpipReferenced.uid,
             TransferSyntax.jpipReferencedDeflate.uid,
             TransferSyntax.jpipHTJ2KReferenced.uid,
             TransferSyntax.jpipHTJ2KReferencedDeflate.uid:
            return true
        default:
            return false
        }
    }

    /// Whether this transfer syntax uses JP3D volumetric compression (experimental)
    public var isJP3D: Bool {
        switch uid {
        case TransferSyntax.jp3dLossless.uid,
             TransferSyntax.jp3dLossy.uid:
            return true
        default:
            return false
        }
    }
    
    /// Whether this transfer syntax uses JPEG-LS compression
    public var isJPEGLS: Bool {
        switch uid {
        case TransferSyntax.jpegLSLossless.uid,
             TransferSyntax.jpegLSNearLossless.uid:
            return true
        default:
            return false
        }
    }

    /// Whether this transfer syntax uses JPEG XL compression
    public var isJPEGXL: Bool {
        switch uid {
        case TransferSyntax.jpegXLLossless.uid,
             TransferSyntax.jpegXLRecompression.uid,
             TransferSyntax.jpegXL.uid:
            return true
        default:
            return false
        }
    }

    /// Whether this transfer syntax uses RLE compression
    public var isRLE: Bool {
        uid == TransferSyntax.rleLossless.uid
    }
    
    /// Whether this transfer syntax uses video compression (MPEG2, H.264, or H.265)
    public var isVideo: Bool {
        return isMPEG2 || isH264 || isH265
    }

    /// Whether this video transfer syntax permits the bit stream to span multiple
    /// fragments.
    ///
    /// The MPEG-2 and H.264 "….1" variants are the fragmentable forms of their
    /// non-fragmentable twins, which require that "one Fragment shall contain the
    /// whole bit stream". The two HEVC transfer syntaxes have no twin: PS3.5 defines
    /// each as a Fragmentable Encapsulated Transfer Syntax in its own right ("the
    /// encapsulated Pixel Data Stream may be segmented into multiple Fragments").
    ///
    /// Non-video transfer syntaxes return `false`; fragmentation of, say, a JPEG
    /// codestream is governed by different rules and is not what this property models.
    ///
    /// Reference: PS3.5 Sections 8.2.5 - 8.2.11, A.4.5 - A.4.7
    public var allowsMultipleFragments: Bool {
        return isVideo && (uid.hasSuffix(".1") || isH265)
    }
    
    /// Whether this transfer syntax uses MPEG2 compression
    public var isMPEG2: Bool {
        switch uid {
        case TransferSyntax.mpeg2MainProfile.uid,
             TransferSyntax.mpeg2MainProfileHighLevel.uid,
             TransferSyntax.mpeg2MainProfileFragmentable.uid,
             TransferSyntax.mpeg2MainProfileHighLevelFragmentable.uid:
            return true
        default:
            return false
        }
    }
    
    /// Whether this transfer syntax uses H.264/AVC compression
    public var isH264: Bool {
        switch uid {
        case TransferSyntax.mpeg4AVCHP41.uid,
             TransferSyntax.mpeg4AVCHP41BD.uid,
             TransferSyntax.mpeg4AVCHP42For2DVideo.uid,
             TransferSyntax.mpeg4AVCHP42For3DVideo.uid,
             TransferSyntax.mpeg4AVCStereoHP42.uid,
             TransferSyntax.mpeg4AVCHP41Fragmentable.uid,
             TransferSyntax.mpeg4AVCHP41BDFragmentable.uid,
             TransferSyntax.mpeg4AVCHP42For2DVideoFragmentable.uid,
             TransferSyntax.mpeg4AVCHP42For3DVideoFragmentable.uid,
             TransferSyntax.mpeg4AVCStereoHP42Fragmentable.uid:
            return true
        default:
            return false
        }
    }
    
    /// Whether this transfer syntax uses H.265/HEVC compression
    public var isH265: Bool {
        switch uid {
        case TransferSyntax.hevcH265MainProfile.uid,
             TransferSyntax.hevcH265Main10Profile.uid,
             TransferSyntax.hevcH265MainProfileFragmentable.uid,
             TransferSyntax.hevcH265Main10ProfileFragmentable.uid:
            return true
        default:
            return false
        }
    }
    
    /// Whether PS3.6 2026a Table A-1 marks this transfer syntax as retired.
    ///
    /// Retired syntaxes are kept so files that use them can be identified; nothing
    /// should write them.
    public var isRetired: Bool {
        switch uid {
        case TransferSyntax.explicitVRBigEndian.uid,
             TransferSyntax.jpegExtendedProcess3And5Retired.uid,
             TransferSyntax.jpegSpectralSelectionProcess6And8Retired.uid,
             TransferSyntax.jpegSpectralSelectionProcess7And9Retired.uid,
             TransferSyntax.jpegFullProgressionProcess10And12Retired.uid,
             TransferSyntax.jpegFullProgressionProcess11And13Retired.uid,
             TransferSyntax.jpegLosslessProcess15Retired.uid,
             TransferSyntax.jpegExtendedHierarchicalProcess16And18Retired.uid,
             TransferSyntax.jpegExtendedHierarchicalProcess17And19Retired.uid,
             TransferSyntax.jpegSpectralSelectionHierarchicalProcess20And22Retired.uid,
             TransferSyntax.jpegSpectralSelectionHierarchicalProcess21And23Retired.uid,
             TransferSyntax.jpegFullProgressionHierarchicalProcess24And26Retired.uid,
             TransferSyntax.jpegFullProgressionHierarchicalProcess25And27Retired.uid,
             TransferSyntax.jpegLosslessHierarchicalProcess28Retired.uid,
             TransferSyntax.jpegLosslessHierarchicalProcess29Retired.uid,
             TransferSyntax.rfc2557MIMEEncapsulationRetired.uid,
             TransferSyntax.xmlEncodingRetired.uid,
             TransferSyntax.papyrus3ImplicitVRLittleEndianRetired.uid:
            return true
        default:
            return false
        }
    }

    /// Whether this is a lossless transfer syntax
    public var isLossless: Bool {
        switch uid {
        case TransferSyntax.implicitVRLittleEndian.uid,
             TransferSyntax.explicitVRLittleEndian.uid,
             TransferSyntax.deflatedExplicitVRLittleEndian.uid,
             TransferSyntax.explicitVRBigEndian.uid,
             TransferSyntax.jpegLossless.uid,
             TransferSyntax.jpegLosslessSV1.uid,
             TransferSyntax.jpeg2000Lossless.uid,
             TransferSyntax.jpeg2000Part2Lossless.uid,
             TransferSyntax.htj2kLossless.uid,
             TransferSyntax.htj2kRPCLLossless.uid,
             TransferSyntax.jpegLSLossless.uid,
             TransferSyntax.jpegXLLossless.uid,
             TransferSyntax.jpegXLRecompression.uid,
             TransferSyntax.rleLossless.uid,
             TransferSyntax.jp3dLossless.uid,
             TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.uid,
             TransferSyntax.smpteST2110_20UncompressedProgressiveVideo.uid,
             TransferSyntax.smpteST2110_20UncompressedInterlacedVideo.uid,
             TransferSyntax.smpteST2110_30PCMDigitalAudio.uid,
             TransferSyntax.deflatedImageFrameCompression.uid,
             TransferSyntax.jpegLosslessProcess15Retired.uid,
             TransferSyntax.jpegLosslessHierarchicalProcess28Retired.uid,
             TransferSyntax.jpegLosslessHierarchicalProcess29Retired.uid,
             TransferSyntax.rfc2557MIMEEncapsulationRetired.uid,
             TransferSyntax.xmlEncodingRetired.uid,
             TransferSyntax.papyrus3ImplicitVRLittleEndianRetired.uid:
            return true
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible
extension TransferSyntax: CustomStringConvertible {
    public var description: String {
        let vrType = isExplicitVR ? "Explicit VR" : "Implicit VR"
        let endian = byteOrder == .littleEndian ? "Little Endian" : "Big Endian"
        let deflated = isDeflated ? " Deflated" : ""
        return "\(deflated)\(vrType) \(endian) (\(uid))".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Catalog (display + enumeration)
extension TransferSyntax {
    /// Every transfer syntax DICOMKit defines, in a UI-friendly order (uncompressed,
    /// JPEG, JPEG 2000 / HTJ2K, JPEG-LS, RLE, video, JPIP, JP3D). The single source of
    /// truth for "all available transfer syntaxes" — callers (e.g. pickers) should
    /// enumerate this rather than maintaining their own list. Each entry's `uid`
    /// round-trips through `from(uid:)` / `parse(_:)`.
    public static let allKnown: [TransferSyntax] = [
        // Uncompressed
        .implicitVRLittleEndian, .explicitVRLittleEndian,
        .deflatedExplicitVRLittleEndian, .explicitVRBigEndian,
        // JPEG
        .jpegBaseline, .jpegExtended, .jpegLossless, .jpegLosslessSV1,
        // JPEG 2000 / HTJ2K
        .jpeg2000Lossless, .jpeg2000, .jpeg2000Part2Lossless, .jpeg2000Part2,
        .htj2kLossless, .htj2kRPCLLossless, .htj2kLossy,
        // JPEG-LS
        .jpegLSLossless, .jpegLSNearLossless,
        // JPEG XL
        .jpegXLLossless, .jpegXLRecompression, .jpegXL,
        // RLE
        .rleLossless,
        // Video
        .mpeg2MainProfile, .mpeg2MainProfileHighLevel,
        .mpeg4AVCHP41, .mpeg4AVCHP41BD,
        .mpeg4AVCHP42For2DVideo, .mpeg4AVCHP42For3DVideo, .mpeg4AVCStereoHP42,
        .hevcH265MainProfile, .hevcH265Main10Profile,
        // Video (fragmentable variants)
        .mpeg2MainProfileFragmentable, .mpeg2MainProfileHighLevelFragmentable,
        .mpeg4AVCHP41Fragmentable, .mpeg4AVCHP41BDFragmentable,
        .mpeg4AVCHP42For2DVideoFragmentable, .mpeg4AVCHP42For3DVideoFragmentable,
        .mpeg4AVCStereoHP42Fragmentable,
        .hevcH265MainProfileFragmentable, .hevcH265Main10ProfileFragmentable,
        // JPIP
        .jpipReferenced, .jpipReferencedDeflate,
        // JP3D (experimental / private)
        .jp3dLossless, .jp3dLossy,
        // Added 2026-09-25 to complete PS3.6 2026a Table A-1
        .encapsulatedUncompressedExplicitVRLittleEndian, .deflatedImageFrameCompression,
        .jpipHTJ2KReferenced, .jpipHTJ2KReferencedDeflate,
        .smpteST2110_20UncompressedProgressiveVideo, .smpteST2110_20UncompressedInterlacedVideo,
        .smpteST2110_30PCMDigitalAudio,
        // Retired (identification only)
        .jpegExtendedProcess3And5Retired, .jpegSpectralSelectionProcess6And8Retired,
        .jpegSpectralSelectionProcess7And9Retired, .jpegFullProgressionProcess10And12Retired,
        .jpegFullProgressionProcess11And13Retired, .jpegLosslessProcess15Retired,
        .jpegExtendedHierarchicalProcess16And18Retired, .jpegExtendedHierarchicalProcess17And19Retired,
        .jpegSpectralSelectionHierarchicalProcess20And22Retired, .jpegSpectralSelectionHierarchicalProcess21And23Retired,
        .jpegFullProgressionHierarchicalProcess24And26Retired, .jpegFullProgressionHierarchicalProcess25And27Retired,
        .jpegLosslessHierarchicalProcess28Retired, .jpegLosslessHierarchicalProcess29Retired,
        .rfc2557MIMEEncapsulationRetired, .xmlEncodingRetired, .papyrus3ImplicitVRLittleEndianRetired,
    ]

    /// The name of the Transfer Syntax in PS3.6 2026a Table A-1 ("UID Name" column, verbatim,
    /// including any ": Default Transfer Syntax for …" qualifier and "(Retired)"), so every tool
    /// and message that prints it uses the standard's name. Before 2026-10-01 this returned the
    /// abbreviations that are now ``shortName`` (D176).
    ///
    /// Four UIDs are not in Table A-1 and keep a descriptive name: the two unregistered HEVC
    /// "Fragmentable" UIDs (named after the registered Fragmentable rows) and the private JP3D
    /// pair. An unknown UID falls back to ``description``.
    public var displayName: String {
        switch uid {
        case TransferSyntax.implicitVRLittleEndian.uid: return "Implicit VR Little Endian: Default Transfer Syntax for DICOM"
        case TransferSyntax.explicitVRLittleEndian.uid: return "Explicit VR Little Endian"
        case TransferSyntax.deflatedExplicitVRLittleEndian.uid: return "Deflated Explicit VR Little Endian"
        case TransferSyntax.explicitVRBigEndian.uid: return "Explicit VR Big Endian (Retired)"
        case TransferSyntax.jpegBaseline.uid: return "JPEG Baseline (Process 1): Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression"
        case TransferSyntax.jpegExtended.uid: return "JPEG Extended (Process 2 & 4): Default Transfer Syntax for Lossy JPEG 12 Bit Image Compression (Process 4 only)"
        case TransferSyntax.jpegLossless.uid: return "JPEG Lossless, Non-Hierarchical (Process 14)"
        case TransferSyntax.jpegLosslessSV1.uid: return "JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1]): Default Transfer Syntax for Lossless JPEG Image Compression"
        case TransferSyntax.jpeg2000Lossless.uid: return "JPEG 2000 Image Compression (Lossless Only)"
        case TransferSyntax.jpeg2000.uid: return "JPEG 2000 Image Compression"
        case TransferSyntax.jpeg2000Part2Lossless.uid: return "JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only)"
        case TransferSyntax.jpeg2000Part2.uid: return "JPEG 2000 Part 2 Multi-component Image Compression"
        case TransferSyntax.htj2kLossless.uid: return "High-Throughput JPEG 2000 Image Compression (Lossless Only)"
        case TransferSyntax.htj2kRPCLLossless.uid: return "High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)"
        case TransferSyntax.htj2kLossy.uid: return "High-Throughput JPEG 2000 Image Compression"
        case TransferSyntax.jpegLSLossless.uid: return "JPEG-LS Lossless Image Compression"
        case TransferSyntax.jpegLSNearLossless.uid: return "JPEG-LS Lossy (Near-Lossless) Image Compression"
        case TransferSyntax.jpegXLLossless.uid: return "JPEG XL Lossless"
        case TransferSyntax.jpegXLRecompression.uid: return "JPEG XL JPEG Recompression"
        case TransferSyntax.jpegXL.uid: return "JPEG XL"
        case TransferSyntax.rleLossless.uid: return "RLE Lossless"
        case TransferSyntax.mpeg2MainProfile.uid: return "MPEG2 Main Profile / Main Level"
        case TransferSyntax.mpeg2MainProfileHighLevel.uid: return "MPEG2 Main Profile / High Level"
        case TransferSyntax.mpeg4AVCHP41.uid: return "MPEG-4 AVC/H.264 High Profile / Level 4.1"
        case TransferSyntax.mpeg4AVCHP41BD.uid: return "MPEG-4 AVC/H.264 BD-compatible High Profile / Level 4.1"
        case TransferSyntax.hevcH265MainProfile.uid: return "HEVC/H.265 Main Profile / Level 5.1"
        case TransferSyntax.mpeg4AVCHP42For2DVideo.uid: return "MPEG-4 AVC/H.264 High Profile / Level 4.2 For 2D Video"
        case TransferSyntax.mpeg4AVCHP42For3DVideo.uid: return "MPEG-4 AVC/H.264 High Profile / Level 4.2 For 3D Video"
        case TransferSyntax.mpeg4AVCStereoHP42.uid: return "MPEG-4 AVC/H.264 Stereo High Profile / Level 4.2"
        case TransferSyntax.hevcH265Main10Profile.uid: return "HEVC/H.265 Main 10 Profile / Level 5.1"
        case TransferSyntax.mpeg2MainProfileFragmentable.uid: return "Fragmentable MPEG2 Main Profile / Main Level"
        case TransferSyntax.mpeg2MainProfileHighLevelFragmentable.uid: return "Fragmentable MPEG2 Main Profile / High Level"
        case TransferSyntax.mpeg4AVCHP41Fragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.1"
        case TransferSyntax.mpeg4AVCHP41BDFragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 BD-compatible High Profile / Level 4.1"
        case TransferSyntax.mpeg4AVCHP42For2DVideoFragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.2 For 2D Video"
        case TransferSyntax.mpeg4AVCHP42For3DVideoFragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.2 For 3D Video"
        case TransferSyntax.mpeg4AVCStereoHP42Fragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 Stereo High Profile / Level 4.2"
        case TransferSyntax.hevcH265MainProfileFragmentable.uid: return "Fragmentable HEVC/H.265 Main Profile / Level 5.1"
        case TransferSyntax.hevcH265Main10ProfileFragmentable.uid: return "Fragmentable HEVC/H.265 Main 10 Profile / Level 5.1"
        case TransferSyntax.jpipReferenced.uid: return "JPIP Referenced"
        case TransferSyntax.jpipReferencedDeflate.uid: return "JPIP Referenced Deflate"
        case TransferSyntax.jp3dLossless.uid: return "JP3D Lossless (experimental)"
        case TransferSyntax.jp3dLossy.uid: return "JP3D Lossy (experimental)"
        case TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.uid: return "Encapsulated Uncompressed Explicit VR Little Endian"
        case TransferSyntax.jpipHTJ2KReferenced.uid: return "JPIP HTJ2K Referenced"
        case TransferSyntax.jpipHTJ2KReferencedDeflate.uid: return "JPIP HTJ2K Referenced Deflate"
        case TransferSyntax.smpteST2110_20UncompressedProgressiveVideo.uid: return "SMPTE ST 2110-20 Uncompressed Progressive Active Video"
        case TransferSyntax.smpteST2110_20UncompressedInterlacedVideo.uid: return "SMPTE ST 2110-20 Uncompressed Interlaced Active Video"
        case TransferSyntax.smpteST2110_30PCMDigitalAudio.uid: return "SMPTE ST 2110-30 PCM Digital Audio"
        case TransferSyntax.deflatedImageFrameCompression.uid: return "Deflated Image Frame Compression"
        case TransferSyntax.jpegExtendedProcess3And5Retired.uid: return "JPEG Extended (Process 3 & 5) (Retired)"
        case TransferSyntax.jpegSpectralSelectionProcess6And8Retired.uid: return "JPEG Spectral Selection, Non-Hierarchical (Process 6 & 8) (Retired)"
        case TransferSyntax.jpegSpectralSelectionProcess7And9Retired.uid: return "JPEG Spectral Selection, Non-Hierarchical (Process 7 & 9) (Retired)"
        case TransferSyntax.jpegFullProgressionProcess10And12Retired.uid: return "JPEG Full Progression, Non-Hierarchical (Process 10 & 12) (Retired)"
        case TransferSyntax.jpegFullProgressionProcess11And13Retired.uid: return "JPEG Full Progression, Non-Hierarchical (Process 11 & 13) (Retired)"
        case TransferSyntax.jpegLosslessProcess15Retired.uid: return "JPEG Lossless, Non-Hierarchical (Process 15) (Retired)"
        case TransferSyntax.jpegExtendedHierarchicalProcess16And18Retired.uid: return "JPEG Extended, Hierarchical (Process 16 & 18) (Retired)"
        case TransferSyntax.jpegExtendedHierarchicalProcess17And19Retired.uid: return "JPEG Extended, Hierarchical (Process 17 & 19) (Retired)"
        case TransferSyntax.jpegSpectralSelectionHierarchicalProcess20And22Retired.uid: return "JPEG Spectral Selection, Hierarchical (Process 20 & 22) (Retired)"
        case TransferSyntax.jpegSpectralSelectionHierarchicalProcess21And23Retired.uid: return "JPEG Spectral Selection, Hierarchical (Process 21 & 23) (Retired)"
        case TransferSyntax.jpegFullProgressionHierarchicalProcess24And26Retired.uid: return "JPEG Full Progression, Hierarchical (Process 24 & 26) (Retired)"
        case TransferSyntax.jpegFullProgressionHierarchicalProcess25And27Retired.uid: return "JPEG Full Progression, Hierarchical (Process 25 & 27) (Retired)"
        case TransferSyntax.jpegLosslessHierarchicalProcess28Retired.uid: return "JPEG Lossless, Hierarchical (Process 28) (Retired)"
        case TransferSyntax.jpegLosslessHierarchicalProcess29Retired.uid: return "JPEG Lossless, Hierarchical (Process 29) (Retired)"
        case TransferSyntax.rfc2557MIMEEncapsulationRetired.uid: return "RFC 2557 MIME encapsulation (Retired)"
        case TransferSyntax.xmlEncodingRetired.uid: return "XML Encoding (Retired)"
        case TransferSyntax.papyrus3ImplicitVRLittleEndianRetired.uid: return "Papyrus 3 Implicit VR Little Endian (Retired)"
        default: return description
        }
    }

    /// A short, human-readable name for pickers and compact summaries, e.g. "JPEG Baseline
    /// (Process 1)", "MPEG2 Main Profile @ Main Level", "HTJ2K Lossless Only". It is not the
    /// standard's name; ``displayName`` is.
    public var shortName: String {
        switch uid {
        case TransferSyntax.implicitVRLittleEndian.uid: return "Implicit VR Little Endian"
        case TransferSyntax.explicitVRLittleEndian.uid: return "Explicit VR Little Endian"
        case TransferSyntax.deflatedExplicitVRLittleEndian.uid: return "Deflated Explicit VR Little Endian"
        case TransferSyntax.explicitVRBigEndian.uid: return "Explicit VR Big Endian (retired)"
        case TransferSyntax.jpegBaseline.uid: return "JPEG Baseline (Process 1)"
        case TransferSyntax.jpegExtended.uid: return "JPEG Extended (Process 2 & 4)"
        case TransferSyntax.jpegLossless.uid: return "JPEG Lossless (Process 14)"
        case TransferSyntax.jpegLosslessSV1.uid: return "JPEG Lossless SV1 (Process 14)"
        case TransferSyntax.jpeg2000Lossless.uid: return "JPEG 2000 Lossless Only"
        case TransferSyntax.jpeg2000.uid: return "JPEG 2000"
        case TransferSyntax.jpeg2000Part2Lossless.uid: return "JPEG 2000 Part 2 Multi-component Lossless Only"
        case TransferSyntax.jpeg2000Part2.uid: return "JPEG 2000 Part 2 Multi-component"
        case TransferSyntax.htj2kLossless.uid: return "HTJ2K Lossless Only"
        case TransferSyntax.htj2kRPCLLossless.uid: return "HTJ2K Lossless Only (RPCL)"
        case TransferSyntax.htj2kLossy.uid: return "HTJ2K"
        case TransferSyntax.jpegLSLossless.uid: return "JPEG-LS Lossless"
        case TransferSyntax.jpegLSNearLossless.uid: return "JPEG-LS Near-Lossless"
        case TransferSyntax.jpegXLLossless.uid: return "JPEG XL Lossless"
        case TransferSyntax.jpegXLRecompression.uid: return "JPEG XL JPEG Recompression"
        case TransferSyntax.jpegXL.uid: return "JPEG XL"
        case TransferSyntax.rleLossless.uid: return "RLE Lossless"
        case TransferSyntax.mpeg2MainProfile.uid: return "MPEG2 Main Profile @ Main Level"
        case TransferSyntax.mpeg2MainProfileHighLevel.uid: return "MPEG2 Main Profile @ High Level"
        case TransferSyntax.mpeg4AVCHP41.uid: return "MPEG-4 AVC/H.264 HP @ Level 4.1"
        case TransferSyntax.mpeg4AVCHP41BD.uid: return "MPEG-4 AVC/H.264 BD-compatible HP @ Level 4.1"
        case TransferSyntax.hevcH265MainProfile.uid: return "HEVC/H.265 Main Profile @ Level 5.1"
        case TransferSyntax.mpeg4AVCHP42For2DVideo.uid: return "MPEG-4 AVC/H.264 HP @ Level 4.2 For 2D Video"
        case TransferSyntax.mpeg4AVCHP42For3DVideo.uid: return "MPEG-4 AVC/H.264 HP @ Level 4.2 For 3D Video"
        case TransferSyntax.mpeg4AVCStereoHP42.uid: return "MPEG-4 AVC/H.264 Stereo HP @ Level 4.2"
        case TransferSyntax.hevcH265Main10Profile.uid: return "HEVC/H.265 Main 10 Profile @ Level 5.1"
        case TransferSyntax.mpeg2MainProfileFragmentable.uid: return "Fragmentable MPEG2 Main Profile @ Main Level"
        case TransferSyntax.mpeg2MainProfileHighLevelFragmentable.uid: return "Fragmentable MPEG2 Main Profile @ High Level"
        case TransferSyntax.mpeg4AVCHP41Fragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 HP @ Level 4.1"
        case TransferSyntax.mpeg4AVCHP41BDFragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 BD-compatible HP @ Level 4.1"
        case TransferSyntax.mpeg4AVCHP42For2DVideoFragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 HP @ Level 4.2 For 2D Video"
        case TransferSyntax.mpeg4AVCHP42For3DVideoFragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 HP @ Level 4.2 For 3D Video"
        case TransferSyntax.mpeg4AVCStereoHP42Fragmentable.uid: return "Fragmentable MPEG-4 AVC/H.264 Stereo HP @ Level 4.2"
        case TransferSyntax.hevcH265MainProfileFragmentable.uid: return "Fragmentable HEVC/H.265 Main Profile @ Level 5.1"
        case TransferSyntax.hevcH265Main10ProfileFragmentable.uid: return "Fragmentable HEVC/H.265 Main 10 Profile @ Level 5.1"
        case TransferSyntax.jpipReferenced.uid: return "JPIP Referenced"
        case TransferSyntax.jpipReferencedDeflate.uid: return "JPIP Referenced Deflate"
        case TransferSyntax.jp3dLossless.uid: return "JP3D Lossless (experimental)"
        case TransferSyntax.jp3dLossy.uid: return "JP3D Lossy (experimental)"
        case TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.uid: return "Encapsulated Uncompressed Explicit VR Little Endian"
        case TransferSyntax.jpipHTJ2KReferenced.uid: return "JPIP HTJ2K Referenced"
        case TransferSyntax.jpipHTJ2KReferencedDeflate.uid: return "JPIP HTJ2K Referenced Deflate"
        case TransferSyntax.smpteST2110_20UncompressedProgressiveVideo.uid: return "SMPTE ST 2110-20 Uncompressed Progressive Active Video"
        case TransferSyntax.smpteST2110_20UncompressedInterlacedVideo.uid: return "SMPTE ST 2110-20 Uncompressed Interlaced Active Video"
        case TransferSyntax.smpteST2110_30PCMDigitalAudio.uid: return "SMPTE ST 2110-30 PCM Digital Audio"
        case TransferSyntax.deflatedImageFrameCompression.uid: return "Deflated Image Frame Compression"
        case TransferSyntax.jpegExtendedProcess3And5Retired.uid: return "JPEG Extended (Process 3 & 5) (retired)"
        case TransferSyntax.jpegSpectralSelectionProcess6And8Retired.uid: return "JPEG Spectral Selection, Non-Hierarchical (Process 6 & 8) (retired)"
        case TransferSyntax.jpegSpectralSelectionProcess7And9Retired.uid: return "JPEG Spectral Selection, Non-Hierarchical (Process 7 & 9) (retired)"
        case TransferSyntax.jpegFullProgressionProcess10And12Retired.uid: return "JPEG Full Progression, Non-Hierarchical (Process 10 & 12) (retired)"
        case TransferSyntax.jpegFullProgressionProcess11And13Retired.uid: return "JPEG Full Progression, Non-Hierarchical (Process 11 & 13) (retired)"
        case TransferSyntax.jpegLosslessProcess15Retired.uid: return "JPEG Lossless, Non-Hierarchical (Process 15) (retired)"
        case TransferSyntax.jpegExtendedHierarchicalProcess16And18Retired.uid: return "JPEG Extended, Hierarchical (Process 16 & 18) (retired)"
        case TransferSyntax.jpegExtendedHierarchicalProcess17And19Retired.uid: return "JPEG Extended, Hierarchical (Process 17 & 19) (retired)"
        case TransferSyntax.jpegSpectralSelectionHierarchicalProcess20And22Retired.uid: return "JPEG Spectral Selection, Hierarchical (Process 20 & 22) (retired)"
        case TransferSyntax.jpegSpectralSelectionHierarchicalProcess21And23Retired.uid: return "JPEG Spectral Selection, Hierarchical (Process 21 & 23) (retired)"
        case TransferSyntax.jpegFullProgressionHierarchicalProcess24And26Retired.uid: return "JPEG Full Progression, Hierarchical (Process 24 & 26) (retired)"
        case TransferSyntax.jpegFullProgressionHierarchicalProcess25And27Retired.uid: return "JPEG Full Progression, Hierarchical (Process 25 & 27) (retired)"
        case TransferSyntax.jpegLosslessHierarchicalProcess28Retired.uid: return "JPEG Lossless, Hierarchical (Process 28) (retired)"
        case TransferSyntax.jpegLosslessHierarchicalProcess29Retired.uid: return "JPEG Lossless, Hierarchical (Process 29) (retired)"
        case TransferSyntax.rfc2557MIMEEncapsulationRetired.uid: return "RFC 2557 MIME encapsulation (retired)"
        case TransferSyntax.xmlEncodingRetired.uid: return "XML Encoding (retired)"
        case TransferSyntax.papyrus3ImplicitVRLittleEndianRetired.uid: return "Papyrus 3 Implicit VR Little Endian (retired)"
        default: return description
        }
    }
}

// MARK: - Lossless Capability & Selectable Encodings

/// Whether a transfer syntax UID can carry lossless data, lossy data, or either.
///
/// Some DICOM JPEG 2000 / HTJ2K UIDs are a *single* UID that per PS3.5 may hold
/// **either** a lossy or a lossless codestream (e.g. `.91`, `.93`, `.203`), while
/// others are reversible-only (`.90`, `.92`, `.201`, `.202`).
public enum LosslessCapability: Sendable, Hashable {
    /// The UID may only carry reversible (lossless) data.
    case losslessOnly
    /// The UID may only carry irreversible (lossy) data.
    case lossyOnly
    /// The UID may carry either lossy or lossless data depending on how it was encoded.
    case both
}

/// The intended (or actual) encoding mode selected for a transfer syntax whose UID
/// supports both lossy and lossless. `.notApplicable` is used for single-capability UIDs.
public enum EncodingIntent: Sendable, Hashable {
    case lossless
    case lossy
    case notApplicable
}

extension TransferSyntax {
    /// Whether this UID can carry lossless data, lossy data, or either.
    ///
    /// Single source of truth for the lossy/lossless split. `both`-capable UIDs are
    /// expanded into two rows by ``selectableEncodings``.
    public var losslessCapability: LosslessCapability {
        switch uid {
        // UIDs that per the DICOM standard may carry either a lossy or lossless codestream.
        // PS3.5 A.4.4 (JPEG 2000 .91 / Part 2 .93 / HTJ2K .203) and A.4.12 (JPEG XL .112).
        case TransferSyntax.jpeg2000.uid,          // .91
             TransferSyntax.jpeg2000Part2.uid,     // .93
             TransferSyntax.htj2kLossy.uid,        // .203
             TransferSyntax.jpegXL.uid:            // .112
            return .both
        default:
            // Everything else is single-capability; derive from the reversible flag.
            return isLossless ? .losslessOnly : .lossyOnly
        }
    }

    /// The DICOM **Lossy Image Compression Method** (0028,2114) Defined Term for this
    /// syntax when it carries an *irreversible* (lossy) codestream, or `nil` for
    /// reversible-only syntaxes (which never populate the lossy-compression attributes).
    ///
    /// Single source of truth for (0028,2114). Reference: PS3.5 §A.4.4 (`ISO_15444_1`),
    /// the HTJ2K/Part-15 variant (`ISO_15444_15`), §A.4.12 (`ISO_18181_1`),
    /// §A.4.1 (`ISO_10918_1`), and §A.4.5 (`ISO_14495_1`); PS3.3 C.7.6.1.1.5.
    public var lossyImageCompressionMethod: String? {
        switch uid {
        case TransferSyntax.jpegBaseline.uid,      // .50
             TransferSyntax.jpegExtended.uid,      // .51
             TransferSyntax.jpegExtendedProcess3And5Retired.uid,
             TransferSyntax.jpegSpectralSelectionProcess6And8Retired.uid,
             TransferSyntax.jpegSpectralSelectionProcess7And9Retired.uid,
             TransferSyntax.jpegFullProgressionProcess10And12Retired.uid,
             TransferSyntax.jpegFullProgressionProcess11And13Retired.uid,
             TransferSyntax.jpegExtendedHierarchicalProcess16And18Retired.uid,
             TransferSyntax.jpegExtendedHierarchicalProcess17And19Retired.uid,
             TransferSyntax.jpegSpectralSelectionHierarchicalProcess20And22Retired.uid,
             TransferSyntax.jpegSpectralSelectionHierarchicalProcess21And23Retired.uid,
             TransferSyntax.jpegFullProgressionHierarchicalProcess24And26Retired.uid,
             TransferSyntax.jpegFullProgressionHierarchicalProcess25And27Retired.uid:   // retired lossy JPEG processes
            return "ISO_10918_1"
        case TransferSyntax.jpegLSNearLossless.uid: // .81 (near-lossless is lossy)
            return "ISO_14495_1"
        case TransferSyntax.jpeg2000.uid,          // .91
             TransferSyntax.jpeg2000Part2.uid:     // .93
            return "ISO_15444_1"
        case TransferSyntax.htj2kLossy.uid:        // .203
            return "ISO_15444_15"
        case TransferSyntax.jpegXL.uid:            // .112
            return "ISO_18181_1"
        default:
            return nil
        }
    }
}

/// A user-selectable transfer-syntax encoding: a UID paired with the encoding intent.
///
/// This is what pickers, CLI targets, and validators should enumerate. For a UID whose
/// ``TransferSyntax/losslessCapability`` is `.both`, two `SelectableEncoding` values exist
/// (one `.lossless`, one `.lossy`) that share the same UID; `from(uid:)` remains
/// deterministic because it maps to the single underlying ``TransferSyntax``.
public struct SelectableEncoding: Sendable, Hashable, Identifiable {
    /// The underlying transfer syntax (UID-keyed).
    public let transferSyntax: TransferSyntax
    /// The encoding intent; `.notApplicable` for single-capability UIDs.
    public let intent: EncodingIntent

    public init(transferSyntax: TransferSyntax, intent: EncodingIntent) {
        self.transferSyntax = transferSyntax
        self.intent = intent
    }

    /// The transfer syntax UID (may be shared by a sibling `SelectableEncoding` of the other intent).
    public var uid: String { transferSyntax.uid }

    /// Stable identity combining UID and intent (distinguishes the two rows of a `both` UID).
    public var id: String {
        switch intent {
        case .lossless:       return "\(uid)#lossless"
        case .lossy:          return "\(uid)#lossy"
        case .notApplicable:  return uid
        }
    }

    /// Intent-aware lossless flag. For `both` UIDs this reflects the selected intent
    /// rather than the (UID-level) `TransferSyntax.isLossless`, which always reports lossy.
    public var isLossless: Bool {
        switch intent {
        case .lossless:       return true
        case .lossy:          return false
        case .notApplicable:  return transferSyntax.isLossless
        }
    }

    /// The PS3.6 Table A-1 name of the transfer syntax (``TransferSyntax/displayName``), with the
    /// chosen intent in parentheses for a UID that may carry either (PS3.5 A.4.4: `.91`, `.93`,
    /// `.203`), e.g. "JPEG 2000 Image Compression (lossy)"; single-capability names already say
    /// it ("JPEG 2000 Image Compression (Lossless Only)").
    public var displayName: String {
        switch intent {
        case .lossless:       return "\(transferSyntax.displayName) (lossless)"
        case .lossy:          return "\(transferSyntax.displayName) (lossy)"
        case .notApplicable:  return transferSyntax.displayName
        }
    }

    /// Short picker label, e.g. "JPEG 2000 Lossless", "JPEG 2000 Lossy", "JPEG 2000 Lossless
    /// Only" (``TransferSyntax/shortName`` plus the intent). This was ``displayName`` before
    /// 2026-10-01 (D176).
    public var shortName: String {
        switch intent {
        case .lossless:       return "\(transferSyntax.shortName) Lossless"
        case .lossy:          return "\(transferSyntax.shortName) Lossy"
        case .notApplicable:  return transferSyntax.shortName
        }
    }
}

extension TransferSyntax {
    /// The user-facing catalog of selectable encodings — the shared source of truth for
    /// "which transfer syntaxes can I pick". Built by expanding ``allKnown``: each
    /// `both`-capable UID yields two rows (lossless + lossy); every other UID yields one.
    ///
    /// Callers (CLI targets, app pickers, validators, DICOMweb capabilities, tests) should
    /// enumerate this instead of maintaining their own hardcoded UID lists.
    public static let selectableEncodings: [SelectableEncoding] = allKnown.flatMap { ts -> [SelectableEncoding] in
        switch ts.losslessCapability {
        case .both:
            return [
                SelectableEncoding(transferSyntax: ts, intent: .lossless),
                SelectableEncoding(transferSyntax: ts, intent: .lossy),
            ]
        case .losslessOnly, .lossyOnly:
            return [SelectableEncoding(transferSyntax: ts, intent: .notApplicable)]
        }
    }

    /// The image/storage transfer syntaxes a **UID-only negotiation tool** — `dicom-retrieve`,
    /// `dicom-qr` — can request during C-GET / C-MOVE association setup, each paired with the
    /// canonical short token shown in its transfer-syntax picker and `--transfer-syntax` CLI help.
    ///
    /// This is the **single source of truth** for retrieval transfer-syntax lists, playing the same
    /// role for negotiation tools that ``CompressionManager.supportedCodecs()`` (dicom-compress) and
    /// `DICOMConverter.cliTokens` (dicom-convert) play for the encode tools: the DICOMStudio CLI
    /// Workshop pickers and the `dicom-retrieve` / `dicom-qr` CLIs all derive their list from it, so
    /// a codec added here surfaces on every negotiation surface at once — never hand-maintain those
    /// lists again. Every token round-trips through ``parse(_:)`` (enforced by TransferSyntaxTests).
    ///
    /// Unlike the encode catalogs this is a **UID-level** list (no lossy/lossless intent split): an
    /// association proposes a transfer syntax UID, so the `both`-capable general families contribute
    /// a single entry each (`jpeg2000` → .91, `htj2k` → .203, `jpeg-xl` → .112). Ordering mirrors
    /// ``DICOMConverter``'s UI order (uncompressed, JPEG, JPEG 2000 / HTJ2K, JPEG-LS, JPEG XL, RLE).
    ///
    /// Video (MPEG/HEVC), JPIP, experimental JP3D, and the JPEG XL JPEG-recompression (…4.111)
    /// syntaxes are intentionally omitted: the package cannot decode them, so requesting them for a
    /// file retrieval is not useful.
    public static let negotiableImageSyntaxTokens: [(syntax: TransferSyntax, token: String)] = [
        // Uncompressed
        (.explicitVRLittleEndian,         "explicit-vr-le"),
        (.implicitVRLittleEndian,         "implicit-vr-le"),
        (.explicitVRBigEndian,            "explicit-vr-be"),
        (.deflatedExplicitVRLittleEndian, "deflate"),
        // JPEG
        (.jpegBaseline,                   "jpeg-baseline"),
        (.jpegExtended,                   "jpeg-extended"),
        (.jpegLossless,                   "jpeg-lossless"),
        (.jpegLosslessSV1,                "jpeg-lossless-sv1"),
        // JPEG 2000 / HTJ2K
        (.jpeg2000Lossless,               "jpeg2000-lossless"),
        (.jpeg2000,                       "jpeg2000"),
        (.jpeg2000Part2Lossless,          "jpeg2000-part2-lossless"),
        (.jpeg2000Part2,                  "jpeg2000-part2"),
        (.htj2kLossless,                  "htj2k-lossless"),
        (.htj2kRPCLLossless,              "htj2k-rpcl"),
        (.htj2kLossy,                     "htj2k"),
        // JPEG-LS
        (.jpegLSLossless,                 "jpeg-ls-lossless"),
        (.jpegLSNearLossless,             "jpeg-ls"),
        // JPEG XL
        (.jpegXLLossless,                 "jpeg-xl-lossless"),
        (.jpegXL,                         "jpeg-xl"),
        // RLE
        (.rleLossless,                    "rle-lossless"),
    ]

    /// The canonical negotiation tokens from ``negotiableImageSyntaxTokens``, in catalog order —
    /// drives the `dicom-retrieve` / `dicom-qr` transfer-syntax pickers and CLI help.
    public static var negotiableImageTokens: [String] { negotiableImageSyntaxTokens.map(\.token) }

    /// Parses a user-facing alias/UID into a ``SelectableEncoding``, resolving the lossy vs
    /// lossless intent for `both`-capable UIDs.
    ///
    /// Recognizes everything ``parse(_:)`` does plus the symmetric intent names. Per the
    /// DICOM standard the general UIDs (.91/.93/.203/.112) may carry either a reversible or
    /// an irreversible codestream, so the encode path resolves them with an explicit intent:
    ///
    ///   - `…-lossy`         → general UID, `.lossy`   (e.g. `jpeg2000-lossy` → .91 irreversible)
    ///   - `…-lossless`      → general UID, `.lossless` (e.g. `htj2k-lossless` → .203 reversible)
    ///   - `…-lossless-only` → reversible-only UID      (e.g. `jpeg2000-lossless-only` → .90)
    ///
    /// The legacy `…-91-/-93-/-203-` explicit spellings and the deprecated `htj2k-rpcl`
    /// spelling are accepted as aliases.
    public static func parseEncoding(_ nameOrUID: String) -> SelectableEncoding? {
        let trimmed = nameOrUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        // Symmetric intent names. The bare `…-lossless` spellings encode reversibly *into*
        // the general UID; `…-lossless-only` selects the distinct reversible-only UID.
        switch normalized {
        // JPEG 2000 — general .91 / lossless-only .90
        // `JPEG2000Lossless`, `HTJ2KLossless` and `JPEGXLLossless` are PS3.6 2026a Table A-1
        // keywords of the reversible-only UIDs .90 / .201 / .110, so they fall through to
        // `parse` below (P-CONVERT-TS-KEYWORDS); the reversible encode INTO the general UID
        // is spelled `…Reversible` (or the kebab `…-lossless` aliases).
        case "jpeg2000-lossless", "j2k-lossless", "jpeg2000reversible",
             "jpeg2000-91-lossless", "j2k-91-lossless", "jpeg2000-lossless-91":
            return SelectableEncoding(transferSyntax: .jpeg2000, intent: .lossless)
        case "jpeg2000-lossy", "j2k-lossy", "jpeg2000-91-lossy", "j2k-91-lossy":
            return SelectableEncoding(transferSyntax: .jpeg2000, intent: .lossy)
        case "jpeg2000-lossless-only", "jpeg2000losslessonly", "j2k-lossless-only":
            return SelectableEncoding(transferSyntax: .jpeg2000Lossless, intent: .notApplicable)
        // JPEG 2000 Part 2 — general .93 / lossless-only .92
        case "jpeg2000-part2-lossless", "jpeg2000part2lossless", "j2k-part2-lossless",
             "jpeg2000-part2-93-lossless", "j2k-part2-93-lossless":
            return SelectableEncoding(transferSyntax: .jpeg2000Part2, intent: .lossless)
        case "jpeg2000-part2-lossy", "j2k-part2-lossy",
             "jpeg2000-part2-93-lossy", "j2k-part2-93-lossy":
            return SelectableEncoding(transferSyntax: .jpeg2000Part2, intent: .lossy)
        case "jpeg2000-part2-lossless-only", "j2k-part2-lossless-only":
            return SelectableEncoding(transferSyntax: .jpeg2000Part2Lossless, intent: .notApplicable)
        // HTJ2K — general .203 / lossless-only .201 / RPCL lossless-only .202
        case "htj2k-lossless", "htj2kreversible", "htj2k-203-lossless", "htj2k-lossless-203":
            return SelectableEncoding(transferSyntax: .htj2kLossy, intent: .lossless)
        case "htj2k-lossy", "htj2k-203-lossy":
            return SelectableEncoding(transferSyntax: .htj2kLossy, intent: .lossy)
        case "htj2k-lossless-only":
            return SelectableEncoding(transferSyntax: .htj2kLossless, intent: .notApplicable)
        case "htj2k-rpcl-lossless-only", "htj2k-rpcl", "htj2k-lossless-rpcl", "htj2krpcllossless":
            return SelectableEncoding(transferSyntax: .htj2kRPCLLossless, intent: .notApplicable)
        // JPEG XL — general .112 / lossless-only .110
        case "jpeg-xl-lossless", "jpegxl-lossless", "jxl-lossless", "jpegxlreversible",
             "jpeg-xl-112-lossless", "jxl-112-lossless":
            return SelectableEncoding(transferSyntax: .jpegXL, intent: .lossless)
        case "jpeg-xl-lossy", "jxl-lossy", "jpeg-xl-112-lossy", "jxl-112-lossy":
            return SelectableEncoding(transferSyntax: .jpegXL, intent: .lossy)
        case "jpeg-xl-lossless-only", "jpegxl-lossless-only", "jxl-lossless-only":
            return SelectableEncoding(transferSyntax: .jpegXLLossless, intent: .notApplicable)
        default:
            break
        }

        guard let ts = parse(trimmed) else { return nil }
        switch ts.losslessCapability {
        case .both:
            // Bare `both` alias (e.g. "jpeg2000", "htj2k") historically means the lossy mode.
            return SelectableEncoding(transferSyntax: ts, intent: .lossy)
        case .losslessOnly, .lossyOnly:
            return SelectableEncoding(transferSyntax: ts, intent: .notApplicable)
        }
    }

    /// The three PS3.6 2026a Table A-1 keywords whose meaning changed in
    /// ``parseEncoding(_:)`` (and in `DICOMConverter`'s catalog): keyword → (Table A-1 UID and
    /// name, the new name of the old meaning, the general UID that name encodes into).
    ///
    /// Until 2026-10-01 these keywords selected the reversible encode INTO the general UID
    /// (.91 / .203 / .112); PS3.6 2026a Table A-1 gives them to the reversible-only UIDs
    /// .90 / .201 / .110, which they now select (P-CONVERT-TS-KEYWORDS).
    public static let reassignedTableA1Keywords: [(keyword: String, uid: String, name: String, reversibleName: String, generalUID: String)] = [
        ("JPEG2000Lossless", "1.2.840.10008.1.2.4.90", "JPEG 2000 Image Compression (Lossless Only)",
         "JPEG2000Reversible", "1.2.840.10008.1.2.4.91"),
        ("HTJ2KLossless", "1.2.840.10008.1.2.4.201", "High-Throughput JPEG 2000 Image Compression (Lossless Only)",
         "HTJ2KReversible", "1.2.840.10008.1.2.4.203"),
        ("JPEGXLLossless", "1.2.840.10008.1.2.4.110", "JPEG XL Lossless",
         "JPEGXLReversible", "1.2.840.10008.1.2.4.112"),
    ]

    /// A one-line note for stderr when `token` is one of ``reassignedTableA1Keywords``
    /// (case-insensitive), saying it now selects its Table A-1 UID; `nil` otherwise.
    /// Tools print it for one release after the meaning change.
    public static func reassignedKeywordNote(for token: String) -> String? {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let row = reassignedTableA1Keywords.first(where: { $0.keyword.lowercased() == t }) else {
            return nil
        }
        return "note: \(row.keyword) now selects \(row.uid) (\(row.name)), its PS3.6 Table A-1 UID; "
            + "it used to mean the reversible encode into \(row.generalUID), which is now spelled "
            + "\(row.reversibleName)."
    }
}

/// Byte ordering for DICOM data
///
/// Specifies how multi-byte numeric values are stored in memory.
/// Reference: PS3.5 Section 7.3
public enum ByteOrder: Sendable, Hashable {
    /// Little Endian byte ordering (least significant byte first)
    ///
    /// Default for most DICOM transfer syntaxes.
    case littleEndian
    
    /// Big Endian byte ordering (most significant byte first)
    ///
    /// Used by the retired Explicit VR Big Endian transfer syntax.
    case bigEndian
}
