//
// DCMTKInteropTests.swift
// DICOMPrintKitTests
//
// Interoperability against a *foreign* Print implementation.
//
// Our loopback tests run our SCU against our SCP, so they share every
// assumption in the codebase. DCMTK is an independent implementation of the
// same standard, which is the cheapest evidence available that "any modality"
// and "any printer" are real claims:
//
//   A. dcmprscu (DCMTK Print SCU)  →  DICOMPrintServer (ours)
//   B. DICOMPrintService (ours)    →  dcmprscp (DCMTK Print SCP)
//
// Skipped automatically when DCMTK is not installed, so CI without it stays
// green; `brew install dcmtk` turns the coverage on.
//

import XCTest
import DICOMCore
import DICOMNetwork
@testable import DICOMPrintKit

#if canImport(Network)

final class DCMTKInteropTests: XCTestCase {

    // MARK: Tool discovery

    /// Locates a DCMTK tool on PATH or in the usual Homebrew prefixes.
    private static func tool(_ name: String) -> URL? {
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Use an explicitly supplied synthetic fixture or the repository's
    /// synthetic CT. Never inspect a developer's Desktop or patient files.
    private static func sampleImage() throws -> URL? {
        if let explicit = ProcessInfo.processInfo.environment["DICOMKIT_PRINT_INTEROP_IMAGE"], !explicit.isEmpty {
            guard FileManager.default.fileExists(atPath: explicit) else {
                throw NSError(domain: "DCMTKInteropFixture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "DICOMKIT_PRINT_INTEROP_IMAGE does not name an existing fixture: \(explicit)"])
            }
            return URL(fileURLWithPath: explicit)
        }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("DICOMStudioTests/Fixtures/syn-ct.dcm")
        return FileManager.default.fileExists(atPath: fixture.path) ? fixture : nil
    }

    private struct ProcessResult {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    @discardableResult
    private func run(_ executable: URL, _ arguments: [String],
                     workingDirectory: URL? = nil, timeout: TimeInterval = 60) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        // Read while the process runs so a chatty tool cannot fill the pipe and
        // deadlock against waitUntilExit().
        let handle = pipe.fileHandleForReading
        var data = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            data.append(handle.availableData)
        }
        if process.isRunning {
            process.terminate()
            return ProcessResult(status: -1, output: String(decoding: data, as: UTF8.self)
                + "\n[timed out after \(timeout)s]")
        }
        data.append(handle.readDataToEndOfFile())
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self))
    }

    // MARK: Fixtures

    private var workspace: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcmtk-interop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        try super.tearDownWithError()
    }

    /// A DCMTK configuration naming our emulator as the target printer.
    private func writeSCUConfig(port: UInt16, aeTitle: String) throws -> URL {
        let database = workspace.appendingPathComponent("db")
        let spool = workspace.appendingPathComponent("spool")
        for directory in [database, spool] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // DCMTK nests its sections under double-bracket groups: printer
        // entries live in [[COMMUNICATION]], everything else in [[GENERAL]].
        // Getting this wrong silently yields "unable to select printer".
        let config = """
        [[GENERAL]]
        [DATABASE]
        Directory = \(database.path)
        [NETWORK]
        AETitle = DCMTK_SCU
        Port = 0
        MaxPDU = 16384
        [PRINT]
        Directory = \(spool.path)
        [[COMMUNICATION]]
        [DICOMKIT]
        Aetitle = \(aeTitle)
        Description = DICOMKit print emulator
        Hostname = 127.0.0.1
        Port = \(port)
        Type = PRINTER
        ImplicitOnly = false
        DisableNewVRs = false
        FilmDestination = PROCESSOR
        MagnificationType = BILINEAR
        MediumType = PAPER
        DisplayFormat = 1,1\\2,2
        FilmSizeID = 8INX10IN\\14INX17IN\\A4
        MaxDensity = 300
        MinDensity = 20
        MaxPDU = 16384
        SupportsPresentationLUT = true
        PresentationLUTMatchRequired = false
        PresentationLUTPreferSCPRendering = false
        Supports12Bit = true

        """
        let url = workspace.appendingPathComponent("printers.cfg")
        try config.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: A — DCMTK SCU → our SCP

    /// A third-party Print SCU must be able to drive our emulator end to end.
    func testDCMTKPrintSCUCanPrintToOurEmulator() async throws {
        guard let dcmpsprt = Self.tool("dcmpsprt"), let dcmprscu = Self.tool("dcmprscu") else {
            throw XCTSkip("DCMTK not installed (brew install dcmtk)")
        }
        guard let image = try Self.sampleImage() else {
            throw XCTSkip("No sample DICOM image available for the DCMTK tools")
        }

        let screen = ScreenSink()
        let handler = FilmComposingPrintHandler(
            composer: FilmComposer(configuration: FilmComposerConfiguration(dpi: 100)),
            sink: screen)
        let server = DICOMPrintServer(
            configuration: PrintSCPConfiguration(
                aeTitle: try AETitle("DCMPRINT"), port: 0,
                associationIdleTimeout: 60),
            delegate: handler)
        try await server.start()
        defer { Task { await server.stop() } }

        let port = await server.boundPort
        let config = try writeSCUConfig(port: port, aeTitle: "DCMPRINT")

        // Step 1: dcmpsprt renders the image into a Stored Print + Hardcopy
        // Grayscale images in its database directory.
        let render = try run(dcmpsprt, [
            "--verbose", "--nospool",
            "--config", config.path, "--printer", "DICOMKIT",
            "--layout", "1", "1",
            image.path
        ], workingDirectory: workspace)
        XCTAssertTrue(render.succeeded, "dcmpsprt failed:\n\(render.output)")

        // Step 2: dcmprscu spools that job to us over the wire.
        let database = workspace.appendingPathComponent("db")
        let storedPrints = try storedPrintFiles(in: database)
        XCTAssertFalse(storedPrints.isEmpty,
                       "dcmpsprt produced no Stored Print object:\n\(render.output)")

        let spool = try run(dcmprscu, [
            "--verbose", "--print", "--dump",
            "--config", config.path, "--printer", "DICOMKIT"
        ] + storedPrints.map(\.path), workingDirectory: workspace)
        XCTAssertTrue(spool.succeeded, "dcmprscu failed:\n\(spool.output)")

        // Step 3: the film must have arrived, composed.
        let films = await screen.films
        XCTAssertFalse(films.isEmpty, "No film reached the sink.\n\(spool.output)")
        if let film = films.first {
            XCTAssertEqual(film.info.callingAETitle, "DCMTK_SCU")
            XCTAssertGreaterThan(film.info.filledImageBoxCount, 0)
            XCTAssertGreaterThan(film.width, 0)
        }
    }

    /// Stored Print Storage instances (1.2.840.10008.5.1.1.27) in a directory.
    private func storedPrintFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator {
            guard let data = try? Data(contentsOf: url), data.count > 132 else { continue }
            // Cheap check: the Stored Print SOP Class UID appears in the meta
            // information of the file DCMTK wrote.
            if String(decoding: data.prefix(4096), as: UTF8.self)
                .contains("1.2.840.10008.5.1.1.27") {
                found.append(url)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    // MARK: B — our SCU → DCMTK SCP

    /// Our SCU must be able to print to a third-party printer.
    ///
    /// Driven by DCMTK's own sample IHEFULL profile rather than a hand-written
    /// config: dcmprscp validates image data against the printer's configured
    /// Presentation LUT characteristics, and a minimal config leaves it with an
    /// active LUT that rejects every bit depth. Using the shipped profile is
    /// both realistic and the only way the SCP accepts image boxes at all.
    func testOurPrintSCUCanPrintToTheDCMTKPrintSCP() async throws {
        guard let dcmprscp = Self.tool("dcmprscp") else {
            throw XCTSkip("DCMTK not installed (brew install dcmtk)")
        }
        guard let profile = try sampleIHEFullConfig(port: 11119) else {
            throw XCTSkip("DCMTK sample configuration (dcmpstat.cfg / printers.cfg) not found")
        }

        let process = Process()
        process.executableURL = dcmprscp
        process.arguments = ["--verbose", "--config", profile.path, "--printer", "IHEFULL"]
        process.currentDirectoryURL = workspace
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        // Give the listener time to bind (dcmprscp opens its database first).
        try await Task.sleep(nanoseconds: 2_500_000_000)

        // 12-bit P-Values: the IHE Full profile is a 12-bit printer, and
        // dcmprscp rejects data whose depth does not match its Presentation LUT.
        var pixels = Data()
        for index in 0..<(64 * 64) {
            let value = UInt16(index % 4096)
            pixels.append(UInt8(value & 0xFF))
            pixels.append(UInt8(value >> 8))
        }
        let descriptor = PrintImageData(
            pixelData: pixels, rows: 64, columns: 64,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2")

        let result = try await DICOMPrintService.printImages(
            configuration: PrintConfiguration(
                host: "127.0.0.1", port: 11119,
                callingAETitle: "DICOMKIT_SCU", calledAETitle: "IHEFULL",
                timeout: 20),
            images: [pixels],
            options: PrintOptions(filmSize: .size8InX10In, mediumType: .paper),
            imageDescriptors: [descriptor])

        if process.isRunning { process.terminate() }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        XCTAssertTrue(result.success, "Print to DCMTK failed: \(result.errorMessage ?? "")\n\(output)")
        XCTAssertNotNil(result.filmSessionUID)
        XCTAssertNotNil(result.filmBoxUID)
        // dcmprscp does not implement the Print Job SOP Class — it rejects that
        // presentation context and returns no Print Job UID from N-ACTION. The
        // job must still be reported as printed, which is what
        // `PrintResult.printJobUIDs` being empty is meant to express.
        XCTAssertTrue(result.printJobUIDs.isEmpty || result.printJobUID != nil)
    }

    /// DCMTK's shipped `dcmpstat.cfg`, with the IHEFULL printer moved to `port`.
    ///
    /// The sample file already contains the IHEFULL entry, so it is edited in
    /// place rather than having `printers.cfg` appended — a duplicate section
    /// would win on the original port and the listener would go unused.
    private func sampleIHEFullConfig(port: UInt16) throws -> URL? {
        let prefixes = ["/opt/homebrew/etc/dcmtk-3.7.0", "/usr/local/etc/dcmtk-3.7.0",
                        "/opt/homebrew/etc/dcmtk", "/usr/local/etc/dcmtk"]
        guard let directory = prefixes.first(where: {
            FileManager.default.fileExists(atPath: $0 + "/dcmpstat.cfg")
        }) else { return nil }

        let base = try String(contentsOfFile: directory + "/dcmpstat.cfg", encoding: .utf8)
        guard base.contains("[IHEFULL]") else { return nil }

        // dcmprscp resolves its relative database/spool directories against the
        // working directory, which is this test's workspace.
        for name in ["database", "spool"] {
            try FileManager.default.createDirectory(
                at: workspace.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        var section = ""
        var rewritten: [String] = []
        for line in base.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { section = trimmed }
            if section == "[IHEFULL]", trimmed.lowercased().hasPrefix("port") {
                rewritten.append("Port = \(port)")
            } else {
                rewritten.append(line)
            }
        }

        let url = workspace.appendingPathComponent("ihefull.cfg")
        try rewritten.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// When a real printer rejects a film-session attribute, the SCU must stop
    /// there and report *that* — not sail on and fail later with a misleading
    /// code. This is the end-to-end guard for the 0x0106 classification fix.
    func testAttributeRejectionByTheDCMTKSCPFailsFastWithTheRealStatus() async throws {
        guard let dcmprscp = Self.tool("dcmprscp") else {
            throw XCTSkip("DCMTK not installed (brew install dcmtk)")
        }

        let port: UInt16 = 11118
        let database = workspace.appendingPathComponent("reject-db")
        let spool = workspace.appendingPathComponent("reject-spool")
        for directory in [database, spool] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // The printer supports PAPER only.
        let config = """
        [[GENERAL]]
        [DATABASE]
        Directory = \(database.path)
        [NETWORK]
        AETitle = DCMTK_STRICT
        Port = \(port)
        MaxPDU = 16384
        [PRINT]
        Directory = \(spool.path)
        [[COMMUNICATION]]
        [STRICTPRINTER]
        Aetitle = DCMTK_STRICT
        Description = DCMTK print server, PAPER only
        Hostname = 127.0.0.1
        Port = \(port)
        Type = LOCALPRINTER
        DisplayFormat = 1,1
        FilmSizeID = 8INX10IN
        MediumType = PAPER
        FilmDestination = PROCESSOR
        MagnificationType = BILINEAR

        """
        let configURL = workspace.appendingPathComponent("strict.cfg")
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = dcmprscp
        process.arguments = ["--verbose", "--config", configURL.path, "--printer", "STRICTPRINTER"]
        process.currentDirectoryURL = workspace
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        try await Task.sleep(nanoseconds: 2_500_000_000)

        let pixels = Data(repeating: 128, count: 32 * 32)
        let descriptor = PrintImageData(
            pixelData: pixels, rows: 32, columns: 32,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2")

        do {
            _ = try await DICOMPrintService.printImages(
                configuration: PrintConfiguration(
                    host: "127.0.0.1", port: port,
                    callingAETitle: "DICOMKIT_SCU", calledAETitle: "DCMTK_STRICT",
                    timeout: 20),
                images: [pixels],
                // CLEAR FILM is a valid defined term, but this printer does not
                // stock it — the rejection must surface immediately.
                options: PrintOptions(filmSize: .size8InX10In, mediumType: .clearFilm),
                imageDescriptors: [descriptor])
            XCTFail("Expected the printer's attribute rejection to fail the job")
        } catch DICOMNetworkError.printOperationFailed(let status, _) {
            XCTAssertEqual(status.rawValue, 0x0106,
                           "must report Invalid Attribute Value, not a later downstream code")
        }

        if process.isRunning { process.terminate() }
    }
}

#endif
