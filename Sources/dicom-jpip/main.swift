// main.swift — dicom-jpip
// DICOM JPIP streaming client/server utility
// NEMA-verified: 2026a, checked 2026-10-01 — transfer syntax lists diffed against PS3.6 2026a Table A-1 (4 JPIP rows, 4 / 4 match, via JPIPSyntaxes); Pixel Data Provider URL (0028,7FE0) and section citations against PS3.5 2026a 8.4.1, 10.8, A.6, A.7, A.11, A.12; fetch/serve parameters (layers, level, region, port) belong to ISO/IEC 15444-9 JPIP and are out of scope (plumbing)

import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
import DICOMDictionary
import SwiftJ2KJPIP

@available(macOS 10.15, *)
struct DICOMJpip: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-jpip",
        abstract: "JPIP (JPEG 2000 Interactive Protocol) streaming for DICOM imaging",
        discussion: """
            Interact with JPIP servers to progressively stream JPEG 2000 and HTJ2K DICOM
            images using SwiftJ2KJPIP \(DICOMJPIPClient.engineVersion) (ISO/IEC 15444-9).
            JPIP allows retrieving only the image region, resolution level, and quality
            layers needed, minimising bandwidth for large medical imaging datasets.

            Transfer Syntaxes (PS3.6 Table A-1; PS3.5 A.6, A.7, A.11, A.12):
              JPIP Referenced                1.2.840.10008.1.2.4.94
              JPIP Referenced Deflate        1.2.840.10008.1.2.4.95
              JPIP HTJ2K Referenced          1.2.840.10008.1.2.4.204
              JPIP HTJ2K Referenced Deflate  1.2.840.10008.1.2.4.205

            Examples:
              # Fetch full image from JPIP server
              dicom-jpip fetch http://pacs.example.com:8080 --image CT0001

              # Fetch a region at low quality (fast preview)
              dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 \\
                  --region 0,0,512,512 --layers 2

              # Print the Pixel Data Provider URL (0028,7FE0) of a JPIP-referenced file
              dicom-jpip uri study.dcm

              # Start an embedded JPIP server serving local DICOM / JPEG 2000 files
              dicom-jpip serve --port 8080 --directory /path/to/dicom/files

              # Inspect a JPIP-referenced DICOM file or list JPIP transfer syntaxes
              dicom-jpip info study.dcm
              dicom-jpip info --list-syntaxes
            """,
        version: "1.5.0",
        subcommands: [
            FetchCommand.self,
            URICommand.self,
            ServeCommand.self,
            InfoCommand.self
        ],
        defaultSubcommand: InfoCommand.self
    )
}

// MARK: - fetch

@available(macOS 10.15, *)
extension DICOMJpip {
    struct FetchCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fetch",
            abstract: "Fetch a DICOM image from a JPIP server",
            discussion: """
                Connects to a JPIP server (HTTP, HTTPS, WebSocket, or jpip:// / jpips://)
                and retrieves a JPEG 2000 or HTJ2K image progressively.
                Use --layers to limit quality for faster previews, --region for ROI fetching,
                --level for reduced-resolution thumbnails, and --htj2k to request HTJ2K coding.

                Examples:
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --layers 4
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --region 0,0,512,512
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --level 2
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --htj2k --output decoded.raw
                """
        )

        @Argument(help: "JPIP server base URL (e.g., http://pacs.example.com:8080 or ws://localhost:8080)")
        var serverURL: String

        @Option(name: .long, help: "Image ID or JPIP target path on the server")
        var image: String

        @Option(name: .long, help: "Quality layers to fetch (1 = lowest, omit for full quality)")
        var layers: Int?

        @Option(name: .long, help: "Resolution level discard count (0 = full, 1 = half, 2 = quarter...)")
        var level: Int?

        @Option(
            name: .long,
            help: "Region of interest: x,y,width,height (e.g., 0,0,512,512)"
        )
        var region: String?

        @Flag(name: .long, help: "Prefer HTJ2K block coding (for JPIP HTJ2K Referenced .204/.205 targets)")
        var htj2k: Bool = false

        @Option(name: .shortAndLong, help: "Output file path for raw decoded pixel data")
        var output: String?

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            guard URL(string: serverURL) != nil else {
                throw ValidationError("Invalid server URL: \(serverURL)")
            }
            guard !image.isEmpty else {
                throw ValidationError("--image must not be empty")
            }
            if let l = layers, l < 1 {
                throw ValidationError("--layers must be >= 1")
            }
            if let lv = level, lv < 0 {
                throw ValidationError("--level must be >= 0")
            }
            if let r = region {
                let parts = r.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 4 else {
                    throw ValidationError("--region must be x,y,width,height (four integers)")
                }
                guard parts[0] >= 0, parts[1] >= 0 else {
                    throw ValidationError("--region origin (x,y) must be non-negative")
                }
                guard parts[2] > 0, parts[3] > 0 else {
                    throw ValidationError("--region width and height must be positive")
                }
            }
        }

        mutating func run() throws {
            guard let url = URL(string: serverURL) else {
                throw ExitCode.failure
            }
            let jpipURI = buildJPIPTargetURI(baseURL: url, target: image)
            let capturedVerbose = verbose
            let capturedRegion = region
            let capturedLayers = layers
            let capturedLevel = level
            let capturedHTJ2K = htj2k
            let capturedOutput = output

            let task = Task {
                let codingPref: JPIPCodingPreference = capturedHTJ2K ? .htj2k : .none
                let client = DICOMJPIPClient(serverURL: url, codingPreference: codingPref)
                let fetchedImage: DICOMJPIPImage
                do {
                    if capturedVerbose {
                        print("Server: \(url.absoluteString)")
                        print("Target: \(jpipURI.absoluteString)")
                        if capturedHTJ2K { print("Coding preference: HTJ2K") }
                    }

                    if let regionStr = capturedRegion {
                        let parts = regionStr.split(separator: ",").compactMap { Int($0) }
                        let roi = DICOMJPIPRegion(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
                        let quality: DICOMJPIPQuality
                        if let l = capturedLayers {
                            quality = .layers(l)
                        } else if let lv = capturedLevel {
                            quality = .resolutionLevel(lv)
                        } else {
                            quality = .full
                        }
                        if capturedVerbose { print("Region: x=\(parts[0]) y=\(parts[1]) w=\(parts[2]) h=\(parts[3])") }
                        fetchedImage = try await client.fetchRegion(jpipURI: jpipURI, region: roi, quality: quality)
                    } else if let l = capturedLayers {
                        if capturedVerbose { print("Quality layers: \(l)") }
                        fetchedImage = try await client.fetchProgressiveQuality(jpipURI: jpipURI, layers: l)
                    } else if let lv = capturedLevel {
                        if capturedVerbose { print("Resolution level: \(lv)") }
                        fetchedImage = try await client.fetchResolutionLevel(jpipURI: jpipURI, level: lv)
                    } else {
                        fetchedImage = try await client.fetchImage(jpipURI: jpipURI)
                    }
                } catch {
                    try? await client.close()
                    throw error
                }
                try? await client.close()

                print("Fetched: \(fetchedImage.width)×\(fetchedImage.height), \(fetchedImage.components) component(s), \(fetchedImage.bitDepth)-bit")
                print("Pixel data: \(formatBytes(fetchedImage.pixelData.count))")

                if let outputPath = capturedOutput {
                    let outputURL = URL(fileURLWithPath: outputPath)
                    try fetchedImage.pixelData.write(to: outputURL)
                    print("Written: \(outputPath)")
                }
            }

            _ = try waitForTask(task)
        }
    }
}

// MARK: - uri

@available(macOS 10.15, *)
extension DICOMJpip {
    struct URICommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uri",
            abstract: "Print the Pixel Data Provider URL (0028,7FE0) of a JPIP-referenced DICOM file",
            discussion: """
                Reads a DICOM file that uses a JPIP Referenced Transfer Syntax and prints its
                Pixel Data Provider URL (0028,7FE0), the JPIP request URL that stands in for the
                absent Pixel Data (PS3.5 8.4.1, A.6, A.7, A.11, A.12).

                Examples:
                  dicom-jpip uri study.dcm
                  dicom-jpip uri study.dcm --json
                """
        )

        @Argument(help: "DICOM file path")
        var input: String

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        mutating func validate() throws {
            guard FileManager.default.fileExists(atPath: input) else {
                throw ValidationError("File not found: \(input)")
            }
        }

        mutating func run() throws {
            let fileURL = URL(fileURLWithPath: input)
            let dicomFile = try DICOMFile.read(from: fileURL)
            let tsUID = dicomFile.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid

            guard let syntax = JPIPSyntaxes.syntax(tsUID) else {
                print("Error: Transfer syntax \(tsUID) is not a JPIP Referenced Transfer Syntax")
                print("JPIP transfer syntaxes: " + JPIPSyntaxes.all.map(\.uid).joined(separator: ", "))
                throw ExitCode.failure
            }

            let jpipURL = try DICOMJPIPClient.jpipURI(from: dicomFile.dataSet, transferSyntaxUID: tsUID)

            if json {
                let result: [String: Any] = [
                    "file": input,
                    "transferSyntaxUID": tsUID,
                    "isDeflated": syntax.deflated,
                    "jpipURI": jpipURL.absoluteString
                ]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                print("File:                     \(input)")
                print("Transfer Syntax:          \(tsUID) (\(syntax.name))")
                print("Pixel Data Provider URL:  \(jpipURL.absoluteString)")
            }
        }
    }
}

// MARK: - serve

@available(macOS 10.15, *)
extension DICOMJpip {
    struct ServeCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "serve",
            abstract: "Start an embedded JPIP server for local DICOM and JPEG 2000 files",
            discussion: """
                Launches a SwiftJ2KJPIP JPIP server that serves DICOM (.dcm) and raw
                JPEG 2000 / HTJ2K / JP3D (.j2k, .jp2, .jph, .jp3d) files from a local
                directory over HTTP/1.1 and RFC 6455 WebSocket.
                Clients can then use dicom-jpip fetch, dicom-viewer --jpip, or DICOMStudio.

                Examples:
                  dicom-jpip serve --directory /path/to/dicoms
                  dicom-jpip serve --port 8081 --directory /path/to/dicoms --max-clients 10
                """
        )

        @Option(name: .shortAndLong, help: "Port to listen on (default: 8080)")
        var port: Int = 8080

        @Option(name: .long, help: "Host/interface address to bind (default: 127.0.0.1)")
        var host: String = "127.0.0.1"

        @Option(name: .shortAndLong, help: "Directory of DICOM / JPEG 2000 files to serve")
        var directory: String = "."

        @Option(name: .long, help: "Maximum concurrent clients (default: 16)")
        var maxClients: Int = 16

        @Option(name: .long, help: "Per-client bandwidth limit in bytes/sec (0 = unlimited)")
        var clientBandwidth: Int = 0

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            guard port >= 0, port < 65536 else {
                throw ValidationError("Port must be 0–65535")
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
                throw ValidationError("Directory not found: \(directory)")
            }
        }

        mutating func run() throws {
            let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
            let capturedPort = port
            let capturedHost = host
            let capturedMaxClients = maxClients
            let capturedClientBandwidth = clientBandwidth
            let capturedDirectory = directory
            let capturedVerbose = verbose

            let serverTask = Task {
                let config = JPIPServer.Configuration(
                    maxClients: capturedMaxClients,
                    maxQueueSize: 64,
                    globalBandwidthLimit: nil,
                    perClientBandwidthLimit: capturedClientBandwidth == 0 ? nil : capturedClientBandwidth,
                    sessionTimeout: 300
                )
                let server = JPIPServer(port: capturedPort, host: capturedHost, configuration: config)

                let registered = await registerDirectoryTargets(
                    at: dirURL,
                    into: server,
                    verbose: capturedVerbose
                )

                try await server.start()
                let boundPort = await server.listeningPort

                print("JPIP Server (\(DICOMJPIPClient.engineName) \(DICOMJPIPClient.engineVersion)) listening on http://\(capturedHost):\(boundPort)")
                print("Serving \(registered) target(s) from \(capturedDirectory)")
                print("Press Ctrl+C to stop.")

                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    if capturedVerbose {
                        let stats = await server.getStatistics()
                        print("Requests: \(stats.totalRequests)  Active: \(stats.activeClients)  Sent: \(formatBytes(stats.totalBytesSent))")
                    }
                }

                try await server.stop()
            }

            let sema = DispatchSemaphore(value: 0)
            signal(SIGINT) { _ in
                print("\nShutting down...")
                Darwin.exit(0)
            }
            sema.wait()
            _ = serverTask
        }
    }
}

/// Registers all supported JPEG 2000 / HTJ2K / JP3D and DICOM image files inside `directoryURL` into `server`.
@available(macOS 10.15, *)
func registerDirectoryTargets(at directoryURL: URL, into server: JPIPServer, verbose: Bool) async -> Int {
    let directExtensions: Set<String> = ["j2k", "j2c", "jp2", "jph", "jp3d"]
    let enumerator = FileManager.default.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: nil
    )
    var registered = 0

    while let fileURL = enumerator?.nextObject() as? URL {
        let ext = fileURL.pathExtension.lowercased()
        let name = fileURL.deletingPathExtension().lastPathComponent

        if directExtensions.contains(ext) {
            do {
                try await server.registerImage(name: name, at: fileURL)
                registered += 1
                if verbose { print("Registered: \(name) (\(fileURL.lastPathComponent))") }
            } catch {
                if verbose { print("Warning: could not register \(name): \(error)") }
            }
        } else if ext == "dcm" {
            do {
                let dicomFile = try DICOMFile.read(from: fileURL)
                if let codestream = try extractJPIPServeCodestream(from: dicomFile) {
                    await server.registerImageData(name: name, data: codestream)
                    registered += 1
                    if verbose { print("Registered DICOM target: \(name)") }
                } else if verbose {
                    print("Skipping \(name): no servable pixel/JP3D stream")
                }
            } catch {
                if verbose { print("Warning: could not register DICOM \(name): \(error)") }
            }
        }
    }

    return registered
}

/// Extracts a JPEG 2000, HTJ2K, or JP3D codestream suitable for `JPIPServer.registerImageData`
/// from a `DICOMFile` (either directly from a JP3D document / encapsulated J2K frame, or by
/// lossless J2K encoding of frame 0 for uncompressed / non-J2K DICOM images).
func extractJPIPServeCodestream(from dicomFile: DICOMFile) throws -> Data? {
    if JP3DVolumeDocument.isJP3DVolumeDocument(dicomFile),
       let payload = dicomFile.dataSet[.encapsulatedDocument]?.valueData,
       payload.count >= 8 {
        let jp3dLen = Int(payload.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
        guard 4 + jp3dLen <= payload.count else { return nil }
        return payload.subdata(in: 4..<(4 + jp3dLen))
    }

    let tsUID = dicomFile.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid
    let j2kSyntaxes: Set<String> = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.jpeg2000Part2.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid
    ]

    if j2kSyntaxes.contains(tsUID),
       let pixelElement = dicomFile.dataSet[.pixelData],
       let fragments = pixelElement.encapsulatedFragments,
       !fragments.isEmpty,
       let descriptor = dicomFile.dataSet.pixelDataDescriptor() {
        let encapsulated = EncapsulatedPixelData(
            offsetTable: pixelElement.encapsulatedOffsetTable ?? [],
            fragments: fragments,
            descriptor: descriptor
        )
        if let frame0 = encapsulated.frameData(at: 0) {
            return frame0
        }
    }

    guard let pixelData = dicomFile.pixelData(),
          let frameBytes = pixelData.frameData(at: 0) else {
        return nil
    }
    var singleFrameDesc = pixelData.descriptor
    singleFrameDesc = PixelDataDescriptor(
        rows: singleFrameDesc.rows,
        columns: singleFrameDesc.columns,
        numberOfFrames: 1,
        bitsAllocated: singleFrameDesc.bitsAllocated,
        bitsStored: singleFrameDesc.bitsStored,
        highBit: singleFrameDesc.highBit,
        isSigned: singleFrameDesc.isSigned,
        samplesPerPixel: singleFrameDesc.samplesPerPixel,
        photometricInterpretation: singleFrameDesc.photometricInterpretation,
        planarConfiguration: singleFrameDesc.planarConfiguration
    )
    return try SwiftJ2KDICOMCodec(
        encodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid
    ).encodeFrame(
        frameBytes,
        descriptor: singleFrameDesc,
        frameIndex: 0,
        configuration: .lossless
    )
}

// MARK: - info

@available(macOS 10.15, *)
extension DICOMJpip {
    struct InfoCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Display information about a JPIP server or DICOM file",
            discussion: """
                Shows JPIP transfer syntax information for a DICOM file, or displays
                server connection details when given a server URL.

                Examples:
                  dicom-jpip info study.dcm
                  dicom-jpip info http://pacs.example.com:8080
                  dicom-jpip info --list-syntaxes
                """
        )

        @Argument(help: "DICOM file path or JPIP server URL (optional)")
        var target: String?

        @Flag(name: .long, help: "List JPIP transfer syntaxes")
        var listSyntaxes: Bool = false

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        mutating func run() throws {
            if listSyntaxes {
                printJPIPSyntaxes(asJSON: json)
                return
            }

            guard let target = target else {
                print("JPIP (JPEG 2000 Interactive Protocol) — DICOM PS3.5 8.4.1 and Annex A.6, A.7, A.11, A.12")
                print("Engine: \(DICOMJPIPClient.engineName) \(DICOMJPIPClient.engineVersion)")
                print("")
                print("Transfer Syntaxes:")
                printJPIPSyntaxes(asJSON: false)
                print("")
                print("Use 'dicom-jpip --help' for available subcommands.")
                return
            }

            if target.hasPrefix("http://") || target.hasPrefix("https://")
                || target.hasPrefix("ws://") || target.hasPrefix("wss://")
                || target.hasPrefix("jpip://") || target.hasPrefix("jpips://") {
                guard let serverURL = URL(string: target) else {
                    print("Error: Invalid URL: \(target)")
                    throw ExitCode.failure
                }
                try queryServer(serverURL: serverURL, asJSON: json)
            } else {
                try inspectDICOMFile(path: target)
            }
        }

        /// The rows `--list-syntaxes` prints. PS3.6 Table A-1 UIDs and names are kept as
        /// literals so Scripts/diff_cli_web.py can diff them; JPIPSyntaxesTests pins them to
        /// JPIPSyntaxes.all.
        static var listedSyntaxes: [[String: String]] {
            [
                ["uid": "1.2.840.10008.1.2.4.94", "name": "JPIP Referenced",
                 "description": "Pixel Data absent; Pixel Data Provider URL (0028,7FE0) references a JPEG 2000 bit stream on a JPIP server (PS3.5 A.6)"],
                ["uid": "1.2.840.10008.1.2.4.95", "name": "JPIP Referenced Deflate",
                 "description": "As JPIP Referenced, with the Data Set deflate-compressed (PS3.5 A.7)"],
                ["uid": "1.2.840.10008.1.2.4.204", "name": "JPIP HTJ2K Referenced",
                 "description": "Pixel Data absent; Pixel Data Provider URL (0028,7FE0) references an HTJ2K bit stream on a JPIP server (PS3.5 A.11)"],
                ["uid": "1.2.840.10008.1.2.4.205", "name": "JPIP HTJ2K Referenced Deflate",
                 "description": "As JPIP HTJ2K Referenced, with the Data Set deflate-compressed (PS3.5 A.12)"]
            ]
        }

        private func printJPIPSyntaxes(asJSON: Bool) {
            let syntaxes = Self.listedSyntaxes
            if asJSON {
                let data = try? JSONSerialization.data(withJSONObject: syntaxes, options: [.prettyPrinted])
                print(String(data: data ?? Data(), encoding: .utf8) ?? "")
            } else {
                for s in syntaxes {
                    print("  \(s["uid"] ?? "")  \(s["name"] ?? "")")
                    print("    \(s["description"] ?? "")")
                }
            }
        }

        private func inspectDICOMFile(path: String) throws {
            guard FileManager.default.fileExists(atPath: path) else {
                print("Error: File not found: \(path)")
                throw ExitCode.failure
            }
            let fileURL = URL(fileURLWithPath: path)
            let dicomFile = try DICOMFile.read(from: fileURL)
            let tsUID = dicomFile.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid
            let syntax = JPIPSyntaxes.syntax(tsUID)

            if json {
                var result: [String: Any] = [
                    "file": path,
                    "transferSyntaxUID": tsUID,
                    "isJPIP": syntax != nil
                ]
                if syntax != nil {
                    if let jpipURL = try? DICOMJPIPClient.jpipURI(from: dicomFile.dataSet, transferSyntaxUID: tsUID) {
                        result["jpipURI"] = jpipURL.absoluteString
                    }
                }
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                print("File:                     \(path)")
                print("Transfer Syntax:          \(tsUID)\(syntax.map { " (\($0.name))" } ?? "")")
                print("Is JPIP:                  \(syntax != nil ? "Yes" : "No")")
                if syntax != nil {
                    if let jpipURL = try? DICOMJPIPClient.jpipURI(from: dicomFile.dataSet, transferSyntaxUID: tsUID) {
                        print("Pixel Data Provider URL:  \(jpipURL.absoluteString)")
                        print("Server Host:              \(jpipURL.host ?? "unknown")")
                        print("Server Port:              \(jpipURL.port.map(String.init) ?? "default")")
                    }
                }
            }
        }

        private func queryServer(serverURL: URL, asJSON: Bool) throws {
            let base = DICOMJPIPClient.serverBaseURL(from: serverURL)
            if asJSON {
                let info: [String: Any] = [
                    "serverURL": base.absoluteString,
                    "host": base.host ?? "unknown",
                    "port": base.port ?? (base.scheme == "https" || base.scheme == "wss" || base.scheme == "jpips" ? 443 : 80),
                    "scheme": base.scheme ?? "http",
                    "engine": DICOMJPIPClient.engineName,
                    "engineVersion": DICOMJPIPClient.engineVersion
                ]
                let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                print("JPIP Server: \(base.absoluteString)")
                print("Engine:      \(DICOMJPIPClient.engineName) \(DICOMJPIPClient.engineVersion)")
                print("(Use 'dicom-jpip fetch \(base.absoluteString) --image <target>' to stream an image)")
            }
        }
    }
}

// MARK: - Helpers

func buildJPIPTargetURI(baseURL: URL, target: String) -> URL {
    if var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let cleanTarget = target.hasPrefix("/") ? String(target.dropFirst()) : target
        components.path = "\(basePath)/\(cleanTarget)"
        if let built = components.url {
            return built
        }
    }
    return baseURL.appendingPathComponent(target)
}

private func formatBytes(_ bytes: Int) -> String {
    if bytes < 1024 {
        return "\(bytes) B"
    } else if bytes < 1024 * 1024 {
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    } else if bytes < 1024 * 1024 * 1024 {
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    } else {
        return String(format: "%.1f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
    }
}

/// Synchronously waits for an async Task to complete and returns its value.
@available(macOS 10.15, *)
private func waitForTask<T: Sendable>(_ task: Task<T, Error>) throws -> T {
    let sema = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>?
    Task {
        result = await task.result
        sema.signal()
    }
    sema.wait()
    return try result!.get()
}

DICOMJpip.main()
