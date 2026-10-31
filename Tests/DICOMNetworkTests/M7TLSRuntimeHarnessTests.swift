import XCTest
import Foundation
import DICOMCore
@testable import DICOMNetwork

#if canImport(Network) && canImport(Security)
final class M7TLSRuntimeHarnessTests: XCTestCase {
    private struct Case: Decodable {
        let name: String
        let host: String
        let port: UInt16
        let trust: String
        let rootDER: String?
        let minimum: String
        let maximum: String?
        let expectedSuccess: Bool
        let modifiedProfile: Bool?
    }
    private struct Record: Encodable {
        let name: String
        let success: Bool
        let expectedSuccess: Bool
        let status: UInt16?
        let error: String?
    }

    /// An opt-in actual library client gate. The independent Python runner owns
    /// ephemeral TLS peers and verifies their protocol/cipher/association logs.
    func testIndependentTLSPeers() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["DICOMKIT_M7_TLS_CASES"],
              let output = env["DICOMKIT_M7_TLS_RESULTS"] else {
            throw XCTSkip("Set DICOMKIT_M7_TLS_CASES and DICOMKIT_M7_TLS_RESULTS for independent TLS peers")
        }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: input)))
        XCTAssertFalse(cases.isEmpty)
        var records: [Record] = []
        for test in cases {
            let trust: CertificateValidation
            switch test.trust {
            case "custom":
                guard let path = test.rootDER else { throw NSError(domain: "M7TLS", code: 1) }
                trust = .custom([try TLSConfiguration.certificate(fromDER: Data(contentsOf: URL(fileURLWithPath: path)))])
            case "system": trust = .system
            default: throw NSError(domain: "M7TLS unsupported trust mode", code: 2)
            }
            guard let minimum = TLSProtocolVersion(rawValue: test.minimum) else {
                throw NSError(domain: "M7TLS invalid minimum", code: 3)
            }
            let maximum = test.maximum.flatMap(TLSProtocolVersion.init(rawValue:))
            if test.maximum != nil { XCTAssertNotNil(maximum) }
            let tls = TLSConfiguration(minimumVersion: minimum, maximumVersion: maximum,
                certificateValidation: trust,
                cipherSuites: test.modifiedProfile == true ? TLSCipherSuite.modifiedBCP195 : nil)
            let configuration = VerificationConfiguration(callingAETitle: try AETitle("M7TLSCLIENT"),
                calledAETitle: try AETitle("M7TLSPEER"), timeout: 5, tlsConfiguration: tls)
            do {
                let result = try await DICOMVerificationService.echo(host: test.host, port: test.port, configuration: configuration)
                records.append(Record(name: test.name, success: result.success, expectedSuccess: test.expectedSuccess,
                    status: result.status.rawValue, error: nil))
                XCTAssertEqual(result.success, test.expectedSuccess, test.name)
                if result.success { XCTAssertEqual(result.status.rawValue, 0, test.name) }
            } catch {
                records.append(Record(name: test.name, success: false, expectedSuccess: test.expectedSuccess,
                    status: nil, error: String(describing: error)))
                XCTAssertFalse(test.expectedSuccess, "\(test.name): \(error)")
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: URL(fileURLWithPath: output), options: .atomic)
        XCTAssertEqual(records.count, cases.count)
    }
}
#endif
