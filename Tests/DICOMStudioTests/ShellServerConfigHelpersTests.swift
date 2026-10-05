// ShellServerConfigHelpersTests.swift
// DICOMStudioTests
//
// Pins the AE Title rule of the shell server configuration against PS3.5 2026a
// Table 6.2-1 (VR AE) and PS3.8 Table 9-11, the rule DICOMNetwork's AETitle
// puts on the wire.

import Testing
@testable import DICOMStudio
import Foundation

@Suite("Shell Server Config Helpers Tests")
struct ShellServerConfigHelpersTests {

    @Test("validateAETitle accepts the default and sample titles, including the hyphenated ANY-SCP")
    func testAcceptsSampleTitles() {
        for title in ["DICOMSTUDIO", "ANY-SCP", "ORTHANC", "PACS_SCP", "orthanc", "pacs.1"] {
            #expect(ServerValidationHelpers.validateAETitle(title) == nil, "\(title)")
        }
        #expect(ServerValidationHelpers.validateProfile(ServerProfileHelpers.defaultProfile()).isEmpty)
        for profile in ServerProfileHelpers.sampleProfiles() {
            #expect(ServerValidationHelpers.validateProfile(profile).isEmpty, Comment(rawValue: profile.name))
        }
    }

    @Test("validateAETitle: 16 bytes maximum after the non-significant spaces are removed")
    func testLength() {
        #expect(ServerValidationHelpers.maxAETitleLength == 16)
        #expect(ServerValidationHelpers.validateAETitle("1234567890123456") == nil)
        #expect(ServerValidationHelpers.validateAETitle(" 1234567890123456 ") == nil)
        #expect(ServerValidationHelpers.validateAETitle("12345678901234567") != nil)
    }

    @Test("validateAETitle rejects empty, solely spaces, backslash, control and non-ASCII characters")
    func testRepertoire() {
        #expect(ServerValidationHelpers.validateAETitle("") != nil)
        #expect(ServerValidationHelpers.validateAETitle("   ") != nil)
        #expect(ServerValidationHelpers.validateAETitle("A\\B") != nil)
        #expect(ServerValidationHelpers.validateAETitle("A\tB") != nil)
        #expect(ServerValidationHelpers.validateAETitle("CAFÉ") != nil)
    }

    @Test("Default DICOM port is the PS3.8 9.1.1 registered port 11112")
    func testDefaultPort() {
        #expect(ShellServerProfile(name: "x", type: .dicom).port == 11112)
        #expect(ServerProfileHelpers.defaultProfile().port == 11112)
    }
}
