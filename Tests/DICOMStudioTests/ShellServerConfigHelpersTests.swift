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

    // MARK: - Injected parameters name real CLI options (checked against the tools' ArgumentParser surface)

    @Test("DIMSE injection uses the positional <host>, never --host, and no TLS flag the tools lack")
    func testDICOMInjectionNamesRealOptions() {
        var server = ServerProfileHelpers.defaultProfile()
        server.host = "pacs.example.com"; server.aeTitle = "STUDIO"; server.calledAET = "PACS"; server.tlsEnabled = true
        let flags = NetworkInjectorHelpers.dicomParameters(from: server).map(\.flagName)
        #expect(flags == ["<host>", "--port", "--aet", "--called-aet", "--timeout"])
        #expect(!flags.contains("--host") && !flags.contains("--tls"))
    }

    @Test("DICOMweb injection uses the positional <base-url> and --token (dicom-wado has no --url / --auth)")
    func testDICOMwebInjectionNamesRealOptions() {
        var server = ServerProfileHelpers.defaultProfile()
        server.type = .dicomweb; server.baseURL = "https://pacs.example.com/dicom-web"; server.authMethod = .bearer
        let flags = NetworkInjectorHelpers.dicomwebParameters(from: server).map(\.flagName)
        #expect(flags == ["<base-url>", "--token"])
    }

    // MARK: - D257: the generated DIMSE command parses against each tool's ArgumentParser surface

    /// This checkout's Sources directory, found from this file as CLIToolBuilderRepoRootTests does.
    private static var sourcesDirectory: URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir.appendingPathComponent("Sources")
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// ArgumentParser's default long name for a property: its kebab-cased name (`calledAet` → `called-aet`).
    private static func kebab(_ name: String) -> String {
        name.reduce(into: "") { out, c in
            if c.isUppercase { out += "-" + c.lowercased() } else { out.append(c) }
        }
    }

    /// The long option names (`--x`) and the positional (`@Argument`) property names a dicom-* tool declares,
    /// read from every `@Option` / `@Flag` / `@Argument` in its sources (all subcommands included).
    private static func surface(of tool: String) throws -> (options: Set<String>, positionals: [String]) {
        let dir = try #require(Self.sourcesDirectory).appendingPathComponent(tool)
        var options = Set<String>(), positionals: [String] = []
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }.sorted()
        for file in files {
            let src = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            for match in src.matches(of: /@(Option|Flag|Argument)(?:\((?:[^()]|\([^()]*\))*\))?\s*(?:public\s+)?var\s+(\w+)/) {
                let kind = String(match.output.1), name = String(match.output.2), attribute = String(match.output.0)
                if kind == "Argument" {
                    positionals.append(name)
                    continue
                }
                if let custom = attribute.firstMatch(of: /customLong\("([^"]+)"\)/) {
                    options.insert("--" + custom.output.1)
                } else {
                    options.insert("--" + Self.kebab(name))
                }
            }
        }
        return (options, positionals)
    }

    /// The command-line tokens the injected parameters stand for: a `<positional>` entry is its bare value,
    /// an option entry is `--flag value`.
    private static func commandTokens(_ params: [InjectedParameter]) -> [String] {
        params.flatMap { $0.flagName.hasPrefix("<") ? [$0.value] : [$0.flagName, $0.value] }
    }

    @Test("D257: the injected DIMSE command parses against dicom-echo/query/send/retrieve/qr/mwl/mpps — host is the first positional, never --host; every --flag is an option of the tool",
          arguments: [NetworkToolType.dicomEcho, .dicomQuery, .dicomSend, .dicomRetrieve, .dicomQR, .dicomMWL, .dicomMPPS])
    func injectedCommandParsesAgainstTheToolSurface(toolType: NetworkToolType) throws {
        var server = ServerProfileHelpers.defaultProfile()
        server.host = "pacs.example.com"; server.port = 104; server.aeTitle = "STUDIO"; server.calledAET = "PACS"
        server.timeout = 45; server.tlsEnabled = true
        let params = NetworkInjectorHelpers.injectParameters(from: server, for: toolType)
        let tokens = Self.commandTokens(params)
        let (options, positionals) = try Self.surface(of: toolType.toolName)

        #expect(tokens.first == "pacs.example.com", "\(toolType.toolName): host must be the first positional token")
        #expect(!tokens.contains("--host"), "\(toolType.toolName) has no --host option")
        #expect(positionals.contains("host"), "\(toolType.toolName) declares @Argument var host")
        for param in params where param.flagName.hasPrefix("-") {
            #expect(options.contains(param.flagName), "\(toolType.toolName) has no \(param.flagName) option")
        }
        #expect(tokens == ["pacs.example.com", "--port", "104", "--aet", "STUDIO", "--called-aet", "PACS", "--timeout", "45"])
    }
}
