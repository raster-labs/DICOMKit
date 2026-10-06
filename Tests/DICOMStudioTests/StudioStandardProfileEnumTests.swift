// StudioStandardProfileEnumTests.swift
// DICOMStudioTests
//
// P-STUDIO-TLS-PROFILES: the Studio TLS modes offer the live PS3.15 2026a Annex B profiles
// (B.12, B.13) and map onto DICOMNetwork / DICOMWeb. Old persisted raw values still decode.

import Testing
@testable import DICOMStudio
import DICOMNetwork
import DICOMWeb
import Foundation

@Suite("P-STUDIO TLS profile and print enum pins (2026a)")
struct StudioStandardProfileEnumTests {

    private struct Box<T: Codable>: Codable { let value: T }

    private func decode<T: Codable>(_ type: T.Type, _ raw: String) throws -> T {
        let json = Data(#"{"value":"\#(raw)"}"#.utf8)
        return try JSONDecoder().decode(Box<T>.self, from: json).value
    }

    // MARK: - TLSMode (DIMSE)

    @Test("TLSMode offers none, B.12, B.13 and mTLS; no pinned TLS version")
    func tlsModeCases() {
        #expect(TLSMode.allCases == [.none, .bcp195, .modifiedBCP195, .mtls])
        #expect(TLSMode.allCases.map(\.rawValue) == ["NONE", "BCP195", "MODIFIED_BCP195", "MTLS"])
        #expect(TLSMode.none.profile == nil)
        #expect(TLSMode.bcp195.profile == .bcp195)
        #expect(TLSMode.mtls.profile == .bcp195)
        #expect(TLSMode.modifiedBCP195.profile == .modifiedBCP195)
    }

    @Test("TLSMode decodes the retired TLS_1_2 / TLS_1_3 to the nearest profile")
    func tlsModeLegacyDecode() throws {
        #expect(try decode(TLSMode.self, "TLS_1_2") == .bcp195)
        #expect(try decode(TLSMode.self, "TLS_1_3") == .modifiedBCP195)
        #expect(TLSMode(rawValue: "TLS_1_2") == .bcp195)
        #expect(TLSMode(rawValue: "TLS_1_3") == .modifiedBCP195)
        for mode in TLSMode.allCases { #expect(try decode(TLSMode.self, mode.rawValue) == mode) }
        let profile = PACSServerProfile(name: "P", host: "h", remoteAETitle: "A", tlsMode: .modifiedBCP195)
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(PACSServerProfile.self, from: data).tlsMode == .modifiedBCP195)
        let legacy = try #require(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "MODIFIED_BCP195", with: "TLS_1_2")
        #expect(try JSONDecoder().decode(PACSServerProfile.self, from: Data(legacy.utf8)).tlsMode == .bcp195)
    }

    @Test("TLSMode builds DICOMNetwork's per-profile TLSConfiguration")
    func tlsModeConfiguration() throws {
        #expect(TLSMode.none.tlsConfiguration() == nil)
        let b12 = try #require(TLSMode.bcp195.tlsConfiguration())
        #expect(b12 == TLSConfiguration.bcp195)
        #expect(b12.minimumVersion == .tlsProtocol12 && b12.maximumVersion == nil)
        let b13 = try #require(TLSMode.modifiedBCP195.tlsConfiguration())
        #expect(b13.cipherSuites == TLSCipherSuite.modifiedBCP195)
        let identity = ClientIdentity(keychainLabel: "studio")
        #expect(TLSMode.mtls.tlsConfiguration(clientIdentity: identity)?.clientIdentity == identity)
        #expect(TLSMode.bcp195.tlsConfiguration(clientIdentity: identity)?.clientIdentity == nil)
    }

    @Test("Deprecated TLSMode.tls12 / .tls13 name the nearest profile")
    @available(*, deprecated)
    func tlsModeDeprecatedAliases() {
        #expect(TLSMode.tls12 == .bcp195)
        #expect(TLSMode.tls13 == .modifiedBCP195)
    }

    // MARK: - DICOMwebTLSMode

    @Test("DICOMwebTLSMode offers none, B.12, B.13 and development; hands the profile to DICOMWeb")
    func webTLSModeCases() throws {
        #expect(DICOMwebTLSMode.allCases == [.none, .bcp195, .modifiedBCP195, .development])
        #expect(DICOMwebTLSMode.bcp195.webTLSProfile == .bcp195)
        #expect(DICOMwebTLSMode.modifiedBCP195.webTLSProfile == .modifiedBCP195)
        #expect(DICOMwebTLSMode.none.webTLSProfile == nil)
        #expect(DICOMwebTLSMode.development.webTLSProfile == nil)
        let profile = DICOMwebServerProfile(name: "W", baseURL: "https://pacs.example/dicom-web",
                                            tlsMode: .modifiedBCP195)
        #expect(try DICOMwebClientFactory.makeConfiguration(from: profile).tlsProfile == .modifiedBCP195)
    }

    @Test("DICOMwebTLSMode decodes the retired COMPATIBLE / STRICT to the nearest profile")
    func webTLSModeLegacyDecode() throws {
        #expect(try decode(DICOMwebTLSMode.self, "COMPATIBLE") == .bcp195)
        #expect(try decode(DICOMwebTLSMode.self, "STRICT") == .modifiedBCP195)
        for mode in DICOMwebTLSMode.allCases { #expect(try decode(DICOMwebTLSMode.self, mode.rawValue) == mode) }
    }

    @Test("Deprecated DICOMwebTLSMode.compatible / .strict name the nearest profile")
    @available(*, deprecated)
    func webTLSModeDeprecatedAliases() {
        #expect(DICOMwebTLSMode.compatible == .bcp195)
        #expect(DICOMwebTLSMode.strict == .modifiedBCP195)
    }
}
