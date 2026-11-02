import XCTest
import Foundation
import ArgumentParser
@testable import dicom_server

final class M7ServerTLSRefusalTests: XCTestCase {
    private func configuration(directory: URL, tls: Bool = false) -> ServerConfiguration {
        ServerConfiguration(aeTitle: "M7TLS", port: 11112,
            dataDirectory: directory.path, databaseURL: "filesystem://", enableTLS: tls)
    }

    func testDefaultUnsecuredConfigurationRemainsExplicitlyFalse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(try configuration(directory: directory).validated().enableTLS)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testTLSRequestRefusesBeforeAnyStorageOrListenerEffect() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = configuration(directory: directory, tls: true)
        XCTAssertThrowsError(try settings.validated()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("TLS is not implemented"))
            XCTAssertTrue(message.contains("No plaintext fallback"))
        }
        #if canImport(Network)
        XCTAssertThrowsError(try PACSServer(configuration: settings))
        #endif
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDecodedTrueTLSFlagCannotBypassValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encoded = try JSONEncoder().encode(configuration(directory: directory, tls: true))
        let decoded = try JSONDecoder().decode(ServerConfiguration.self, from: encoded)
        XCTAssertThrowsError(try decoded.validated())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testExplicitTLSFlagCannotBeHiddenByUnsecuredConfigurationFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: configFile) }
        try JSONEncoder().encode(configuration(directory: directory, tls: false)).write(to: configFile)
        let command = try StartCommand.parse(["--config", configFile.path, "--tls"])
        XCTAssertThrowsError(try command.resolvedConfiguration()) { error in
            XCTAssertTrue(String(describing: error).contains("No plaintext fallback"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

}
