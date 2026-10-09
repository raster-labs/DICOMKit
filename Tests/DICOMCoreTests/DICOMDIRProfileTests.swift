import Foundation
import Testing
@testable import DICOMCore

/// Media Storage Application Profile identifiers, checked against PS3.11 2026a Annexes A–N.
@Suite("DICOMDIRProfile Tests")
struct DICOMDIRProfileTests {

    /// The 58 fixed identifiers of PS3.11 2026a, extracted from the DocBook text by annex.
    private static let standardIdentifiers: [String] = [
        "STD-XABC-CD",                                                          // A
        "STD-XA1K-CD", "STD-XA1K-DVD",                                          // B
        "STD-GEN-CD", "STD-GEN-SEC-CD", "STD-GEN-DVD-RAM", "STD-GEN-SEC-DVD-RAM",
        "STD-GEN-BD", "STD-GEN-SEC-BD",                                         // D
        "STD-CTMR-MOD41", "STD-CTMR-CD", "STD-CTMR-DVD-RAM", "STD-CTMR-DVD",    // E
        "STD-GEN-MIME",                                                         // G
        "STD-GEN-DVD-JPEG", "STD-GEN-DVD-J2K", "STD-GEN-SEC-DVD-JPEG", "STD-GEN-SEC-DVD-J2K", // H
        "STD-DVD-MPEG2-MPML", "STD-DVD-SEC-MPEG2-MPML",                         // I
        "STD-GEN-USB-JPEG", "STD-GEN-USB-J2K", "STD-GEN-SEC-USB-JPEG", "STD-GEN-SEC-USB-J2K",
        "STD-GEN-MMC-JPEG", "STD-GEN-MMC-J2K", "STD-GEN-SEC-MMC-JPEG", "STD-GEN-SEC-MMC-J2K",
        "STD-GEN-CF-JPEG", "STD-GEN-CF-J2K", "STD-GEN-SEC-CF-JPEG", "STD-GEN-SEC-CF-J2K",
        "STD-GEN-SD-JPEG", "STD-GEN-SD-J2K", "STD-GEN-SEC-SD-JPEG", "STD-GEN-SEC-SD-J2K", // J
        "STD-DEN-CD",                                                           // K
        "STD-GEN-ZIP-MAIL", "STD-GEN-SEC-ZIP-MAIL", "STD-DTL-SEC-ZIP-MAIL",     // L
        "STD-GEN-BD-JPEG", "STD-GEN-BD-J2K", "STD-GEN-BD-MPEG2-MPML", "STD-GEN-BD-MPEG2-MPHL",
        "STD-GEN-BD-MPEG4-HPLV41", "STD-GEN-BD-MPEG4-HPLV41BD",
        "STD-GEN-SEC-BD-JPEG", "STD-GEN-SEC-BD-J2K", "STD-GEN-SEC-BD-MPEG2-MPML", "STD-GEN-SEC-BD-MPEG2-MPHL",
        "STD-GEN-SEC-BD-MPEG4-HPLV41", "STD-GEN-SEC-BD-MPEG4-HPLV41BD",         // M
        "STD-GEN-BD-MPEG4-HPLV42-2D", "STD-GEN-BD-MPEG4-HPLV42-3D", "STD-GEN-BD-MPEG4-SHPLV42",
        "STD-GEN-SEC-BD-MPEG4-HPLV42-2D", "STD-GEN-SEC-BD-MPEG4-HPLV42-3D", "STD-GEN-SEC-BD-MPEG4-SHPLV42", // N
    ]

    @Test("The constants are exactly the 58 fixed identifiers of PS3.11 2026a")
    func testAllStandardMatchesPS311() {
        #expect(Set(DICOMDIRProfile.allStandard.map(\.rawValue)) == Set(Self.standardIdentifiers))
        #expect(DICOMDIRProfile.allStandard.count == 58)
    }

    @Test("Every fixed identifier parses and is standard", arguments: standardIdentifiers)
    func testFixedIdentifier(id: String) throws {
        let profile = try #require(DICOMDIRProfile(rawValue: id))
        #expect(profile.rawValue == id)
        #expect(profile.isStandard)
        #expect(profile.isSecure == id.split(separator: "-").contains("SEC"))
    }

    @Test("Named constants carry the identifiers they are named for")
    func testNamedConstants() {
        #expect(DICOMDIRProfile.standardGeneralCD.rawValue == "STD-GEN-CD")
        #expect(DICOMDIRProfile.standardGeneralDVDJPEG2000.rawValue == "STD-GEN-DVD-J2K")
        #expect(DICOMDIRProfile.standardGeneralMIME.rawValue == "STD-GEN-MIME")
        #expect(DICOMDIRProfile.standardGeneralBDMPEG4HPLV42TwoD.rawValue == "STD-GEN-BD-MPEG4-HPLV42-2D")
        #expect(DICOMDIRProfile.standardDentalRadiographSecureZIPMail.rawValue == "STD-DTL-SEC-ZIP-MAIL")
        #expect(DICOMDIRProfile.standardXA1024DVD.rawValue == "STD-XA1K-DVD")
    }

    // MARK: - Ultrasound templates (Annex C)

    @Test("All 24 Ultrasound identifiers build, parse and are standard")
    func testUltrasoundIdentifiers() {
        var seen = Set<String>()
        for cls in DICOMDIRProfile.UltrasoundClass.allCases {
            for multiFrame in [false, true] {
                for media in DICOMDIRProfile.UltrasoundMedia.allCases {
                    let profile = DICOMDIRProfile.ultrasound(cls, frames: multiFrame, media: media)
                    #expect(profile.isStandard)
                    #expect(DICOMDIRProfile(rawValue: profile.rawValue) == profile)
                    seen.insert(profile.rawValue)
                }
            }
        }
        #expect(seen.count == 24)
        #expect(seen.contains("STD-US-ID-SF-CDR"))
        #expect(seen.contains("STD-US-CC-MF-MOD23-90"))
        #expect(seen.contains("STD-US-SC-MF-DVD-RAM"))
    }

    @Test("An Ultrasound identifier without a known media suffix is rejected")
    func testUltrasoundNeedsMedia() {
        #expect(DICOMDIRProfile(rawValue: "STD-US-ID-SF-xxxx") == nil)
        #expect(DICOMDIRProfile(rawValue: "STD-US-ID-SF") == nil)
        #expect(DICOMDIRProfile(rawValue: "STD-US-ID-SF-USB") == nil)
    }

    // MARK: - Non-standard and legacy identifiers

    @Test("Unknown identifiers are rejected by the failable initializer, kept by init(unchecked:)")
    func testUnknown() {
        #expect(DICOMDIRProfile(rawValue: "STD-MAM-CD") == nil)
        #expect(DICOMDIRProfile(rawValue: "ACME-PRIVATE") == nil)
        let priv = DICOMDIRProfile(unchecked: "ACME-PRIVATE")
        #expect(priv.rawValue == "ACME-PRIVATE")
        #expect(!priv.isStandard)
    }

    @Test("Legacy identifiers still parse and map to a real profile", arguments: [
        ("STD-GEN-DVD", "STD-GEN-DVD-JPEG"),
        ("STD-GEN-USB", "STD-GEN-USB-JPEG"),
        ("STD-GEN-SEC", "STD-GEN-SEC-CD"),
        ("STD-CTMR-xxxx", "STD-CTMR-CD"),
        ("STD-US-xxxx", "STD-US-ID-SF-CDR"),
        (" std-gen-cd ", "STD-GEN-CD"),
    ])
    func testLegacyAliases(input: String, expected: String) {
        #expect(DICOMDIRProfile(rawValue: input)?.rawValue == expected)
    }

    @Test("Codable round-trips the identifier as a plain string")
    func testCodable() throws {
        let profile = DICOMDIRProfile.standardGeneralBDJPEG
        let data = try JSONEncoder().encode(profile)
        #expect(String(decoding: data, as: UTF8.self) == "\"STD-GEN-BD-JPEG\"")
        #expect(try JSONDecoder().decode(DICOMDIRProfile.self, from: data) == profile)
        // Unknown values survive decoding rather than failing.
        let other = try JSONDecoder().decode(DICOMDIRProfile.self, from: Data("\"X-Y\"".utf8))
        #expect(other.rawValue == "X-Y")
    }
}
