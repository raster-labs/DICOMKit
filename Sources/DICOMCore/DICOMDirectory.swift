import Foundation

/// DICOMDIR Media Storage Application Profile
///
/// The identifier of the PS3.11 Application Profile a file-set conforms to, e.g. `STD-GEN-CD`.
/// It is a `struct`, not an `enum`, because the Ultrasound profiles are templates whose last
/// component names the media (`STD-US-ID-SF-xxxx`, PS3.11 Table C.1-1), and because private
/// or future identifiers must round-trip. ``isStandard`` reports whether an identifier is one
/// PS3.11 defines. No DICOMDIR attribute carries the profile; it is conformance metadata.
///
/// NEMA-verified: 2026a, checked 2026-09-25 — text-diffed against PS3.11 2026a Annexes A–N:
/// all 64 profile identifiers are present (58 fixed identifiers as constants, and the 6
/// Ultrasound templates through ``ultrasound(_:frames:media:)``). Annex F (Waveform
/// Diskette) is retired and defines no identifier.
///
/// Reference: DICOM PS3.11 - Media Storage Application Profiles
public struct DICOMDIRProfile: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {

    /// The profile identifier, e.g. `"STD-GEN-CD"`.
    public let rawValue: String

    /// Creates a profile from a PS3.11 identifier, or returns `nil` if PS3.11 does not
    /// define it. Ultrasound identifiers must carry a media suffix from Table C.3-3.
    /// The pre-2026-09-25 identifiers of this type (`STD-GEN-DVD`, `STD-GEN-USB`,
    /// `STD-GEN-SEC`, `STD-CTMR-xxxx`, `STD-US-xxxx`) are accepted and mapped to the profile
    /// they most likely meant, so saved settings and scripts keep working.
    public init?(rawValue: String) {
        let id = rawValue.trimmingCharacters(in: .whitespaces).uppercased()
        if let mapped = Self.legacyAliases[id] {
            self = mapped
        } else if Self.fixedIdentifiers.contains(id) || Self.isUltrasoundIdentifier(id) {
            self.rawValue = id
        } else {
            return nil
        }
    }

    /// Creates a profile from any identifier, including ones PS3.11 does not define.
    public init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        self.init(unchecked: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Whether PS3.11 2026a defines this identifier.
    public var isStandard: Bool {
        Self.fixedIdentifiers.contains(rawValue) || Self.isUltrasoundIdentifier(rawValue)
    }

    /// Whether this is a secure (encrypted) profile, i.e. its identifier contains `SEC`.
    public var isSecure: Bool { rawValue.split(separator: "-").contains("SEC") }

    /// No profile.
    public static let none = DICOMDIRProfile(unchecked: "")

    /// Every fixed identifier PS3.11 2026a defines, in Annex order (excludes the Ultrasound
    /// templates, which need a media suffix).
    public static let allStandard: [DICOMDIRProfile] = fixedIdentifiers.map(DICOMDIRProfile.init(unchecked:))

    // MARK: Basic Cardiac X-Ray Angiographic (PS3.11 Annex A)

    /// STD-XABC-CD
    public static let standardXABasicCardiacCD = DICOMDIRProfile(unchecked: "STD-XABC-CD")

    // MARK: 1024 X-Ray Angiographic (PS3.11 Annex B)

    /// STD-XA1K-CD
    public static let standardXA1024CD = DICOMDIRProfile(unchecked: "STD-XA1K-CD")
    /// STD-XA1K-DVD
    public static let standardXA1024DVD = DICOMDIRProfile(unchecked: "STD-XA1K-DVD")

    // MARK: General Purpose CD-R, DVD and BD Interchange (PS3.11 Annex D)

    /// STD-GEN-CD
    public static let standardGeneralCD = DICOMDIRProfile(unchecked: "STD-GEN-CD")
    /// STD-GEN-DVD-RAM
    public static let standardGeneralDVDRAM = DICOMDIRProfile(unchecked: "STD-GEN-DVD-RAM")
    /// STD-GEN-SEC-CD
    public static let standardGeneralSecureCD = DICOMDIRProfile(unchecked: "STD-GEN-SEC-CD")
    /// STD-GEN-SEC-DVD-RAM
    public static let standardGeneralSecureDVDRAM = DICOMDIRProfile(unchecked: "STD-GEN-SEC-DVD-RAM")
    /// STD-GEN-BD
    public static let standardGeneralBD = DICOMDIRProfile(unchecked: "STD-GEN-BD")
    /// STD-GEN-SEC-BD
    public static let standardGeneralSecureBD = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD")

    // MARK: CT and MR Image (PS3.11 Annex E)

    /// STD-CTMR-MOD41
    public static let standardCTMRMOD41 = DICOMDIRProfile(unchecked: "STD-CTMR-MOD41")
    /// STD-CTMR-CD
    public static let standardCTMRCD = DICOMDIRProfile(unchecked: "STD-CTMR-CD")
    /// STD-CTMR-DVD-RAM
    public static let standardCTMRDVDRAM = DICOMDIRProfile(unchecked: "STD-CTMR-DVD-RAM")
    /// STD-CTMR-DVD
    public static let standardCTMRDVD = DICOMDIRProfile(unchecked: "STD-CTMR-DVD")

    // MARK: General Purpose MIME Interchange (PS3.11 Annex G)

    /// STD-GEN-MIME
    public static let standardGeneralMIME = DICOMDIRProfile(unchecked: "STD-GEN-MIME")

    // MARK: General Purpose DVD with Compression Interchange (PS3.11 Annex H)

    /// STD-GEN-DVD-JPEG
    public static let standardGeneralDVDJPEG = DICOMDIRProfile(unchecked: "STD-GEN-DVD-JPEG")
    /// STD-GEN-DVD-J2K
    public static let standardGeneralDVDJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-DVD-J2K")
    /// STD-GEN-SEC-DVD-JPEG
    public static let standardGeneralSecureDVDJPEG = DICOMDIRProfile(unchecked: "STD-GEN-SEC-DVD-JPEG")
    /// STD-GEN-SEC-DVD-J2K
    public static let standardGeneralSecureDVDJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-DVD-J2K")

    // MARK: DVD MPEG2 Interchange (PS3.11 Annex I)

    /// STD-DVD-MPEG2-MPML
    public static let standardDVDMPEG2MPML = DICOMDIRProfile(unchecked: "STD-DVD-MPEG2-MPML")
    /// STD-DVD-SEC-MPEG2-MPML
    public static let standardDVDSecureMPEG2MPML = DICOMDIRProfile(unchecked: "STD-DVD-SEC-MPEG2-MPML")

    // MARK: General Purpose USB and Flash Memory with Compression Interchange (PS3.11 Annex J)

    /// STD-GEN-USB-JPEG
    public static let standardGeneralUSBJPEG = DICOMDIRProfile(unchecked: "STD-GEN-USB-JPEG")
    /// STD-GEN-USB-J2K
    public static let standardGeneralUSBJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-USB-J2K")
    /// STD-GEN-SEC-USB-JPEG
    public static let standardGeneralSecureUSBJPEG = DICOMDIRProfile(unchecked: "STD-GEN-SEC-USB-JPEG")
    /// STD-GEN-SEC-USB-J2K
    public static let standardGeneralSecureUSBJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-USB-J2K")
    /// STD-GEN-MMC-JPEG
    public static let standardGeneralMMCJPEG = DICOMDIRProfile(unchecked: "STD-GEN-MMC-JPEG")
    /// STD-GEN-MMC-J2K
    public static let standardGeneralMMCJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-MMC-J2K")
    /// STD-GEN-SEC-MMC-JPEG
    public static let standardGeneralSecureMMCJPEG = DICOMDIRProfile(unchecked: "STD-GEN-SEC-MMC-JPEG")
    /// STD-GEN-SEC-MMC-J2K
    public static let standardGeneralSecureMMCJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-MMC-J2K")
    /// STD-GEN-CF-JPEG
    public static let standardGeneralCFJPEG = DICOMDIRProfile(unchecked: "STD-GEN-CF-JPEG")
    /// STD-GEN-CF-J2K
    public static let standardGeneralCFJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-CF-J2K")
    /// STD-GEN-SEC-CF-JPEG
    public static let standardGeneralSecureCFJPEG = DICOMDIRProfile(unchecked: "STD-GEN-SEC-CF-JPEG")
    /// STD-GEN-SEC-CF-J2K
    public static let standardGeneralSecureCFJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-CF-J2K")
    /// STD-GEN-SD-JPEG
    public static let standardGeneralSDJPEG = DICOMDIRProfile(unchecked: "STD-GEN-SD-JPEG")
    /// STD-GEN-SD-J2K
    public static let standardGeneralSDJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-SD-J2K")
    /// STD-GEN-SEC-SD-JPEG
    public static let standardGeneralSecureSDJPEG = DICOMDIRProfile(unchecked: "STD-GEN-SEC-SD-JPEG")
    /// STD-GEN-SEC-SD-J2K
    public static let standardGeneralSecureSDJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-SD-J2K")

    // MARK: Dental (PS3.11 Annex K)

    /// STD-DEN-CD
    public static let standardDentalCD = DICOMDIRProfile(unchecked: "STD-DEN-CD")

    // MARK: ZIP File over Email Interchange (PS3.11 Annex L)

    /// STD-GEN-ZIP-MAIL
    public static let standardGeneralZIPMail = DICOMDIRProfile(unchecked: "STD-GEN-ZIP-MAIL")
    /// STD-GEN-SEC-ZIP-MAIL
    public static let standardGeneralSecureZIPMail = DICOMDIRProfile(unchecked: "STD-GEN-SEC-ZIP-MAIL")
    /// STD-DTL-SEC-ZIP-MAIL
    public static let standardDentalRadiographSecureZIPMail = DICOMDIRProfile(unchecked: "STD-DTL-SEC-ZIP-MAIL")

    // MARK: General Purpose BD with Compression Interchange (PS3.11 Annex M)

    /// STD-GEN-BD-JPEG
    public static let standardGeneralBDJPEG = DICOMDIRProfile(unchecked: "STD-GEN-BD-JPEG")
    /// STD-GEN-BD-J2K
    public static let standardGeneralBDJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-BD-J2K")
    /// STD-GEN-BD-MPEG2-MPML
    public static let standardGeneralBDMPEG2MPML = DICOMDIRProfile(unchecked: "STD-GEN-BD-MPEG2-MPML")
    /// STD-GEN-BD-MPEG2-MPHL
    public static let standardGeneralBDMPEG2MPHL = DICOMDIRProfile(unchecked: "STD-GEN-BD-MPEG2-MPHL")
    /// STD-GEN-BD-MPEG4-HPLV41
    public static let standardGeneralBDMPEG4HPLV41 = DICOMDIRProfile(unchecked: "STD-GEN-BD-MPEG4-HPLV41")
    /// STD-GEN-BD-MPEG4-HPLV41BD
    public static let standardGeneralBDMPEG4HPLV41BD = DICOMDIRProfile(unchecked: "STD-GEN-BD-MPEG4-HPLV41BD")
    /// STD-GEN-SEC-BD-JPEG
    public static let standardGeneralSecureBDJPEG = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-JPEG")
    /// STD-GEN-SEC-BD-J2K
    public static let standardGeneralSecureBDJPEG2000 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-J2K")
    /// STD-GEN-SEC-BD-MPEG2-MPML
    public static let standardGeneralSecureBDMPEG2MPML = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-MPEG2-MPML")
    /// STD-GEN-SEC-BD-MPEG2-MPHL
    public static let standardGeneralSecureBDMPEG2MPHL = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-MPEG2-MPHL")
    /// STD-GEN-SEC-BD-MPEG4-HPLV41
    public static let standardGeneralSecureBDMPEG4HPLV41 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-MPEG4-HPLV41")
    /// STD-GEN-SEC-BD-MPEG4-HPLV41BD
    public static let standardGeneralSecureBDMPEG4HPLV41BD = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-MPEG4-HPLV41BD")

    // MARK: General Purpose BD with MPEG-4 AVC/H.264 Level 4.2 Compression Interchange (PS3.11 Annex N)

    /// STD-GEN-BD-MPEG4-HPLV42-2D
    public static let standardGeneralBDMPEG4HPLV42TwoD = DICOMDIRProfile(unchecked: "STD-GEN-BD-MPEG4-HPLV42-2D")
    /// STD-GEN-BD-MPEG4-HPLV42-3D
    public static let standardGeneralBDMPEG4HPLV42ThreeD = DICOMDIRProfile(unchecked: "STD-GEN-BD-MPEG4-HPLV42-3D")
    /// STD-GEN-BD-MPEG4-SHPLV42
    public static let standardGeneralBDMPEG4SHPLV42 = DICOMDIRProfile(unchecked: "STD-GEN-BD-MPEG4-SHPLV42")
    /// STD-GEN-SEC-BD-MPEG4-HPLV42-2D
    public static let standardGeneralSecureBDMPEG4HPLV42TwoD = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-MPEG4-HPLV42-2D")
    /// STD-GEN-SEC-BD-MPEG4-HPLV42-3D
    public static let standardGeneralSecureBDMPEG4HPLV42ThreeD = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-MPEG4-HPLV42-3D")
    /// STD-GEN-SEC-BD-MPEG4-SHPLV42
    public static let standardGeneralSecureBDMPEG4SHPLV42 = DICOMDIRProfile(unchecked: "STD-GEN-SEC-BD-MPEG4-SHPLV42")

    // MARK: Ultrasound (PS3.11 Annex C)

    /// The Ultrasound profile classes of PS3.11 Table C.1-1.
    public enum UltrasoundClass: String, Sendable, CaseIterable {
        /// Image Display
        case imageDisplay = "ID"
        /// Spatial Calibration
        case spatialCalibration = "SC"
        /// Combined Calibration
        case combinedCalibration = "CC"
    }

    /// The media classes of PS3.11 Table C.3-3, which form the `xxxx` suffix of an
    /// Ultrasound profile identifier.
    public enum UltrasoundMedia: String, Sendable, CaseIterable {
        /// 2.3 GB 90 mm magneto-optical disk
        case mod2390 = "MOD23-90"
        /// CD-R
        case cdr = "CDR"
        /// DVD-RAM
        case dvdRAM = "DVD-RAM"
        /// 120 mm DVD
        case dvd = "DVD"
    }

    /// An Ultrasound profile identifier `STD-US-<class>-<SF|MF>-<media>` (PS3.11 Table C.1-1).
    /// - Parameters:
    ///   - class: Image Display, Spatial Calibration or Combined Calibration.
    ///   - multiFrame: `true` for the multi-frame (MF) profile, `false` for single-frame (SF).
    ///   - media: The media the conformance claim is made for.
    public static func ultrasound(_ class: UltrasoundClass, frames multiFrame: Bool, media: UltrasoundMedia) -> DICOMDIRProfile {
        DICOMDIRProfile(unchecked: "STD-US-\(`class`.rawValue)-\(multiFrame ? "MF" : "SF")-\(media.rawValue)")
    }

    static func isUltrasoundIdentifier(_ id: String) -> Bool {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5, parts[0] == "STD", parts[1] == "US",
              UltrasoundClass(rawValue: parts[2]) != nil, ["SF", "MF"].contains(parts[3]) else { return false }
        return UltrasoundMedia(rawValue: parts[4...].joined(separator: "-")) != nil
    }

    // MARK: Legacy identifiers

    /// General Purpose DVD with JPEG. The identifier `STD-GEN-DVD` does not exist in PS3.11.
    @available(*, deprecated, renamed: "standardGeneralDVDJPEG", message: "STD-GEN-DVD is not a PS3.11 identifier; the DVD-with-JPEG profile is STD-GEN-DVD-JPEG (Annex H)")
    public static let standardGeneralDVD = standardGeneralDVDJPEG

    /// General Purpose USB with JPEG. The identifier `STD-GEN-USB` does not exist in PS3.11.
    @available(*, deprecated, renamed: "standardGeneralUSBJPEG", message: "STD-GEN-USB is not a PS3.11 identifier; the USB-with-JPEG profile is STD-GEN-USB-JPEG (Annex J)")
    public static let standardGeneralUSB = standardGeneralUSBJPEG

    /// General Purpose Secure CD. The identifier `STD-GEN-SEC` does not exist in PS3.11.
    @available(*, deprecated, renamed: "standardGeneralSecureCD", message: "STD-GEN-SEC is not a PS3.11 identifier; every secure profile names its media, e.g. STD-GEN-SEC-CD (Annex D)")
    public static let standardGeneralSecure = standardGeneralSecureCD

    /// CT/MR on CD-R. `STD-CTMR-xxxx` was a placeholder for the four Annex E identifiers.
    @available(*, deprecated, renamed: "standardCTMRCD", message: "STD-CTMR-xxxx is a placeholder; use one of STD-CTMR-CD, -DVD, -DVD-RAM or -MOD41 (Annex E)")
    public static let standardCTMR = standardCTMRCD

    /// Ultrasound Image Display, single frame, on CD-R. `STD-US-xxxx` was a placeholder.
    @available(*, deprecated, message: "STD-US-xxxx is a placeholder; use ultrasound(_:frames:media:) (Annex C)")
    public static let standardUltrasound = ultrasound(.imageDisplay, frames: false, media: .cdr)

    /// PS3.11 2026a defines no mammography media profile. This identifier is not standard.
    @available(*, deprecated, message: "PS3.11 defines no mammography media profile; isStandard is false for this value")
    public static let standardMammography = DICOMDIRProfile(unchecked: "STD-MAM-xxxx")

    private static let legacyAliases: [String: DICOMDIRProfile] = [
        "STD-GEN-DVD": standardGeneralDVDJPEG,
        "STD-GEN-USB": standardGeneralUSBJPEG,
        "STD-GEN-SEC": standardGeneralSecureCD,
        "STD-CTMR-XXXX": standardCTMRCD,
        "STD-US-XXXX": ultrasound(.imageDisplay, frames: false, media: .cdr),
    ]

    /// The 58 fixed identifiers of PS3.11 2026a Annexes A, B, D, E and G–N.
    static let fixedIdentifiers: [String] = [
        "STD-XABC-CD",
        "STD-XA1K-CD",
        "STD-XA1K-DVD",
        "STD-GEN-CD",
        "STD-GEN-DVD-RAM",
        "STD-GEN-SEC-CD",
        "STD-GEN-SEC-DVD-RAM",
        "STD-GEN-BD",
        "STD-GEN-SEC-BD",
        "STD-CTMR-MOD41",
        "STD-CTMR-CD",
        "STD-CTMR-DVD-RAM",
        "STD-CTMR-DVD",
        "STD-GEN-MIME",
        "STD-GEN-DVD-JPEG",
        "STD-GEN-DVD-J2K",
        "STD-GEN-SEC-DVD-JPEG",
        "STD-GEN-SEC-DVD-J2K",
        "STD-DVD-MPEG2-MPML",
        "STD-DVD-SEC-MPEG2-MPML",
        "STD-GEN-USB-JPEG",
        "STD-GEN-USB-J2K",
        "STD-GEN-SEC-USB-JPEG",
        "STD-GEN-SEC-USB-J2K",
        "STD-GEN-MMC-JPEG",
        "STD-GEN-MMC-J2K",
        "STD-GEN-SEC-MMC-JPEG",
        "STD-GEN-SEC-MMC-J2K",
        "STD-GEN-CF-JPEG",
        "STD-GEN-CF-J2K",
        "STD-GEN-SEC-CF-JPEG",
        "STD-GEN-SEC-CF-J2K",
        "STD-GEN-SD-JPEG",
        "STD-GEN-SD-J2K",
        "STD-GEN-SEC-SD-JPEG",
        "STD-GEN-SEC-SD-J2K",
        "STD-DEN-CD",
        "STD-GEN-ZIP-MAIL",
        "STD-GEN-SEC-ZIP-MAIL",
        "STD-DTL-SEC-ZIP-MAIL",
        "STD-GEN-BD-JPEG",
        "STD-GEN-BD-J2K",
        "STD-GEN-BD-MPEG2-MPML",
        "STD-GEN-BD-MPEG2-MPHL",
        "STD-GEN-BD-MPEG4-HPLV41",
        "STD-GEN-BD-MPEG4-HPLV41BD",
        "STD-GEN-SEC-BD-JPEG",
        "STD-GEN-SEC-BD-J2K",
        "STD-GEN-SEC-BD-MPEG2-MPML",
        "STD-GEN-SEC-BD-MPEG2-MPHL",
        "STD-GEN-SEC-BD-MPEG4-HPLV41",
        "STD-GEN-SEC-BD-MPEG4-HPLV41BD",
        "STD-GEN-BD-MPEG4-HPLV42-2D",
        "STD-GEN-BD-MPEG4-HPLV42-3D",
        "STD-GEN-BD-MPEG4-SHPLV42",
        "STD-GEN-SEC-BD-MPEG4-HPLV42-2D",
        "STD-GEN-SEC-BD-MPEG4-HPLV42-3D",
        "STD-GEN-SEC-BD-MPEG4-SHPLV42",
    ]
}

/// DICOM Directory (DICOMDIR)
///
/// Represents a complete DICOMDIR structure for media storage directory.
/// Reference: DICOM PS3.10 - Media Storage and File Format
/// Reference: DICOM PS3.3 F.5 - Media Storage Directory SOP Class
public struct DICOMDirectory: Sendable {
    /// File-set ID (identifier for this file-set)
    public var fileSetID: String
    
    /// Application profile type
    public var profile: DICOMDIRProfile
    
    /// Specific character set
    public var specificCharacterSet: String?
    
    /// File-set descriptor file ID (optional)
    public var fileSetDescriptorFileID: [String]?
    
    /// Specific character set of file-set descriptor file
    public var specificCharacterSetOfFileSetDescriptorFile: String?
    
    /// Root directory records (typically PATIENT records)
    public var rootRecords: [DirectoryRecord]
    
    /// File-set consistency flag (true if consistent)
    public var isConsistent: Bool
    
    /// Initialize a new DICOMDIR
    ///
    /// - Parameters:
    ///   - fileSetID: File-set identifier (default: empty string)
    ///   - profile: Application profile (default: .standardGeneralCD)
    ///   - specificCharacterSet: Character set (default: nil)
    ///   - rootRecords: Root directory records (default: empty)
    ///   - isConsistent: Consistency flag (default: true)
    public init(
        fileSetID: String = "",
        profile: DICOMDIRProfile = .standardGeneralCD,
        specificCharacterSet: String? = nil,
        fileSetDescriptorFileID: [String]? = nil,
        specificCharacterSetOfFileSetDescriptorFile: String? = nil,
        rootRecords: [DirectoryRecord] = [],
        isConsistent: Bool = true
    ) {
        self.fileSetID = fileSetID
        self.profile = profile
        self.specificCharacterSet = specificCharacterSet
        self.fileSetDescriptorFileID = fileSetDescriptorFileID
        self.specificCharacterSetOfFileSetDescriptorFile = specificCharacterSetOfFileSetDescriptorFile
        self.rootRecords = rootRecords
        self.isConsistent = isConsistent
    }
    
    /// Get all records flattened in depth-first order
    ///
    /// - Returns: Array of all directory records
    public func allRecords() -> [DirectoryRecord] {
        var records: [DirectoryRecord] = []
        
        func traverse(_ record: DirectoryRecord) {
            records.append(record)
            for child in record.children {
                traverse(child)
            }
        }
        
        for root in rootRecords {
            traverse(root)
        }
        
        return records
    }
    
    /// Get total count of all records (including nested)
    ///
    /// - Returns: Total number of records
    public func totalRecordCount() -> Int {
        return allRecords().count
    }
    
    /// Find all records of a specific type
    ///
    /// - Parameter recordType: Type of records to find
    /// - Returns: Array of matching directory records
    public func records(ofType recordType: DirectoryRecordType) -> [DirectoryRecord] {
        return allRecords().filter { $0.recordType == recordType }
    }
    
    /// Find a record by SOP Instance UID
    ///
    /// - Parameter sopInstanceUID: SOP Instance UID to search for
    /// - Returns: The directory record if found, nil otherwise
    public func record(withSOPInstanceUID sopInstanceUID: String) -> DirectoryRecord? {
        return allRecords().first { $0.referencedSOPInstanceUID == sopInstanceUID }
    }
    
    /// Get all referenced file paths
    ///
    /// - Returns: Array of file paths referenced in the directory
    public func allReferencedFiles() -> [String] {
        return allRecords().compactMap { $0.referencedFilePath() }
    }
    
    /// Add a root record
    ///
    /// - Parameter record: Directory record to add at root level
    public mutating func addRootRecord(_ record: DirectoryRecord) {
        rootRecords.append(record)
    }
    
    /// Remove all root records
    public mutating func removeAllRootRecords() {
        rootRecords.removeAll()
    }
}

// MARK: - DICOMDIR Statistics

extension DICOMDirectory {
    /// Statistics about the DICOMDIR content
    public struct Statistics: Sendable {
        /// Number of patient records
        public let patientCount: Int
        
        /// Number of study records
        public let studyCount: Int
        
        /// Number of series records
        public let seriesCount: Int
        
        /// Number of image records
        public let imageCount: Int

        /// Number of records that reference a SOP Instance (IMAGE, SR DOCUMENT, PRESENTATION,
        /// RT DOSE, ENCAP DOC, HANGING PROTOCOL, …; PS3.3 Table F.4-1)
        public var instanceRecordCount: Int = 0
        
        /// Total number of all records
        public let totalRecordCount: Int
        
        /// Number of active records
        public let activeRecordCount: Int
        
        /// Number of inactive records
        public let inactiveRecordCount: Int
    }
    
    /// Calculate statistics for this DICOMDIR
    ///
    /// - Returns: Statistics about the directory content
    public func statistics() -> Statistics {
        let allRecords = self.allRecords()
        
        var stats = Statistics(
            patientCount: records(ofType: .patient).count,
            studyCount: records(ofType: .study).count,
            seriesCount: records(ofType: .series).count,
            imageCount: records(ofType: .image).count,
            totalRecordCount: allRecords.count,
            activeRecordCount: allRecords.filter { $0.isActive }.count,
            inactiveRecordCount: allRecords.filter { !$0.isActive }.count
        )
        stats.instanceRecordCount = allRecords.filter { $0.referencedSOPInstanceUID != nil }.count
        return stats
    }
}

// MARK: - CustomStringConvertible

extension DICOMDirectory: CustomStringConvertible {
    public var description: String {
        let stats = statistics()
        return """
            DICOMDIR(
              fileSetID: \(fileSetID.isEmpty ? "<none>" : fileSetID)
              profile: \(profile.rawValue)
              patients: \(stats.patientCount)
              studies: \(stats.studyCount)
              series: \(stats.seriesCount)
              images: \(stats.imageCount)
              consistent: \(isConsistent)
            )
            """
    }
}

// MARK: - Validation

extension DICOMDirectory {
    /// Validation error types
    public enum ValidationError: Error, CustomStringConvertible {
        /// File-set ID is missing or invalid
        case invalidFileSetID
        
        /// Directory record hierarchy is invalid
        case invalidHierarchy(String)
        
        /// Referenced file does not exist
        case missingReferencedFile(String)
        
        /// SOP Instance UID is missing or invalid
        case invalidSOPInstanceUID(String)
        
        /// Duplicate SOP Instance UID found
        case duplicateSOPInstanceUID(String)
        
        /// Record type is invalid for its position in hierarchy
        case invalidRecordTypeInHierarchy(String)
        
        public var description: String {
            switch self {
            case .invalidFileSetID:
                return "File-set ID is missing or invalid"
            case .invalidHierarchy(let msg):
                return "Invalid directory hierarchy: \(msg)"
            case .missingReferencedFile(let path):
                return "Referenced file does not exist: \(path)"
            case .invalidSOPInstanceUID(let uid):
                return "Invalid SOP Instance UID: \(uid)"
            case .duplicateSOPInstanceUID(let uid):
                return "Duplicate SOP Instance UID: \(uid)"
            case .invalidRecordTypeInHierarchy(let msg):
                return "Invalid record type in hierarchy: \(msg)"
            }
        }
    }
    
    /// Validate the directory structure
    ///
    /// Checks for duplicate Referenced SOP Instance UIDs, the record hierarchy of PS3.3 Table
    /// F.4-1 and, with `checkFileExistence`, the Referenced File IDs (0004,1500).
    ///
    /// File IDs are relative to the root of the File-set, the directory node that holds the
    /// DICOMDIR (PS3.10 2026a 8.6: "the File IDs, including the DICOMDIR File IDs, would be
    /// relative to this directory node path name"), and "The DICOMDIR shall not reference Files
    /// outside of the File-set to which it belongs". Pass that directory as `fileSetRoot` (for a
    /// DICOMDIR read from `url`, `url.deletingLastPathComponent()`): every Referenced File ID must
    /// then name an existing regular file inside it, or ``ValidationError/missingReferencedFile(_:)``
    /// is thrown with the File ID. Without a `fileSetRoot` a `DICOMDirectory` does not know where
    /// its File-set is, so only an empty File ID is reported.
    ///
    /// - Parameters:
    ///   - checkFileExistence: Whether to check the Referenced File IDs (default: false)
    ///   - fileSetRoot: The File-set root directory the File IDs are resolved against (default: nil)
    /// - Throws: ValidationError if validation fails
    public func validate(checkFileExistence: Bool = false, fileSetRoot: URL? = nil) throws {
        // Check for duplicate SOP Instance UIDs
        var seenUIDs = Set<String>()
        for record in allRecords() {
            if let uid = record.referencedSOPInstanceUID {
                if seenUIDs.contains(uid) {
                    throw ValidationError.duplicateSOPInstanceUID(uid)
                }
                seenUIDs.insert(uid)
            }
        }
        
        // Validate the hierarchy against PS3.3 Table F.4-1. Retired record types (and
        // PRIVATE, which may contain anything) are not checked below themselves, since the
        // Standard no longer defines what they may contain.
        func validateChildren(of record: DirectoryRecord) throws {
            guard let allowed = record.recordType.allowedChildTypes else { return }
            for child in record.children {
                if !allowed.contains(child.recordType) && !child.recordType.isRetired {
                    throw ValidationError.invalidRecordTypeInHierarchy(
                        "\(child.recordType.rawValue) cannot be child of \(record.recordType.rawValue)"
                    )
                }
                try validateChildren(of: child)
            }
        }

        for root in rootRecords {
            if !DirectoryRecordType.rootLevelTypes.contains(root.recordType) && !root.recordType.isRetired {
                throw ValidationError.invalidRecordTypeInHierarchy(
                    "\(root.recordType.rawValue) cannot be a root-level record"
                )
            }
            try validateChildren(of: root)
        }
        
        // Optionally check the Referenced File IDs against the File-set (PS3.10 8.6)
        if checkFileExistence {
            let root = fileSetRoot?.standardizedFileURL
            for record in allRecords() {
                guard let components = record.referencedFileID, !components.isEmpty else { continue }
                let fileID = components.joined(separator: "\\")
                if components.contains(where: { $0.isEmpty }) {
                    throw ValidationError.missingReferencedFile(fileID)
                }
                guard let root else { continue }
                // A component of "." or ".." (or one carrying a path separator) would leave the
                // File-set; PS3.10 8.5 allows neither "." nor "/" in a File ID component.
                if components.contains(where: { $0 == "." || $0 == ".." || $0.contains("/") }) {
                    throw ValidationError.missingReferencedFile(fileID)
                }
                let url = components.reduce(root) { $0.appendingPathComponent($1) }
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) || isDirectory.boolValue {
                    throw ValidationError.missingReferencedFile(fileID)
                }
            }
        }
    }
}
