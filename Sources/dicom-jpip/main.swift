// main.swift — dicom-jpip
// DICOM JPIP streaming client/server utility
// NEMA-verified: 2026a, checked 2026-10-01 — transfer syntax lists diffed against PS3.6 2026a Table A-1 (4 JPIP rows, 4 / 4 match, via JPIPSyntaxes); Pixel Data Provider URL (0028,7FE0) and section citations against PS3.5 2026a 8.4.1, 10.8, A.6, A.7, A.11, A.12; fetch/serve parameters (layers, level, region, port) belong to ISO/IEC 15444-9 JPIP and are out of scope (plumbing)

import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
import DICOMDictionary

@available(macOS 10.15, *)
struct DICOMJpip: ParsableCommand {
    static let deferredMessage =
        "Error: dicom-jpip is deferred in this release pending SwiftJ2K 12.2.0 (SwiftJ2KJPIP module qualification)."

    static let configuration = CommandConfiguration(
        commandName: "dicom-jpip",
        abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] JPIP (JPEG 2000 Interactive Protocol) streaming for DICOM imaging",
        discussion: """
            DEFERRED: `dicom-jpip` is deferred in this release pending `SwiftJ2K` 12.2.0
            (`SwiftJ2KJPIP` module qualification). All operational subcommands currently
            exit with status 1.

            Interact with JPIP servers to progressively stream JPEG 2000 DICOM images.
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

              # Start an embedded JPIP server serving local DICOM files
              dicom-jpip serve --port 8080 --directory /path/to/dicom/files

              # Get JPIP server statistics
              dicom-jpip info http://pacs.example.com:8080
            """,
        version: "1.0.0",
        subcommands: [
            FetchCommand.self,
            URICommand.self,
            ServeCommand.self,
            InfoCommand.self
        ],
        defaultSubcommand: InfoCommand.self
    )
}

@available(macOS 10.15, *)
func failDeferredJPIP(_ subcommand: String) throws -> Never {
    FileHandle.standardError.write(Data(("\(DICOMJpip.deferredMessage) (subcommand: \(subcommand))\n").utf8))
    throw ExitCode.failure
}

// MARK: - fetch

@available(macOS 10.15, *)
extension DICOMJpip {
    struct FetchCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fetch",
            abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] Fetch a DICOM image from a JPIP server",
            discussion: """
                DEFERRED: JPIP retrieval is deferred pending `SwiftJ2K` 12.2.0 (`SwiftJ2KJPIP` qualification).

                Connects to a JPIP server and retrieves a DICOM image progressively.
                Use --layers to limit quality for faster previews, --region for ROI fetching,
                and --level for low-resolution thumbnails.

                Examples:
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --layers 4
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --region 0,0,512,512
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --level 2
                  dicom-jpip fetch http://pacs.example.com:8080 --image CT0001 --output decoded.raw
                """
        )

        @Argument(help: "JPIP server base URL (e.g., http://pacs.example.com:8080)")
        var serverURL: String

        @Option(name: .long, help: "Image ID or JPIP target path on the server")
        var image: String

        @Option(name: .long, help: "Quality layers to fetch (1 = lowest, omit for full quality)")
        var layers: Int?

        @Option(name: .long, help: "Resolution level (0 = full, 1 = half, 2 = quarter...)")
        var level: Int?

        @Option(
            name: .long,
            help: "Region of interest: x,y,width,height (e.g., 0,0,512,512)"
        )
        var region: String?

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
            if let r = region {
                let parts = r.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 4 else {
                    throw ValidationError("--region must be x,y,width,height (four integers)")
                }
                guard parts[2] > 0, parts[3] > 0 else {
                    throw ValidationError("--region width and height must be positive")
                }
            }
        }

        mutating func run() throws {
            try failDeferredJPIP("fetch")
        }
    }
}

// MARK: - uri

@available(macOS 10.15, *)
extension DICOMJpip {
    struct URICommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uri",
            abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] Print the Pixel Data Provider URL (0028,7FE0) of a JPIP-referenced DICOM file",
            discussion: """
                DEFERRED: `dicom-jpip` is deferred pending `SwiftJ2K` 12.2.0 (`SwiftJ2KJPIP` qualification).

                Reads a DICOM file that uses a JPIP Referenced Transfer Syntax and prints its
                Pixel Data Provider URL (0028,7FE0), the JPIP request URL that stands in for the
                absent Pixel Data (PS3.5 8.4.1, A.6).

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
            try failDeferredJPIP("uri")
        }
    }
}

// MARK: - serve

@available(macOS 10.15, *)
extension DICOMJpip {
    struct ServeCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "serve",
            abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] Start an embedded JPIP server for local DICOM files",
            discussion: """
                DEFERRED: JPIP server hosting is deferred pending `SwiftJ2K` 12.2.0 (`SwiftJ2KJPIP` qualification).

                Launches a JPIP server that serves DICOM files from a local directory.
                Clients can then use dicom-jpip fetch or any JPIP-compatible viewer.

                Examples:
                  dicom-jpip serve --directory /path/to/dicoms
                  dicom-jpip serve --port 8081 --directory /path/to/dicoms --max-clients 10
                """
        )

        @Option(name: .shortAndLong, help: "Port to listen on (default: 8080)")
        var port: Int = 8080

        @Option(name: .shortAndLong, help: "Directory of DICOM files to serve")
        var directory: String = "."

        @Option(name: .long, help: "Maximum concurrent clients (default: 16)")
        var maxClients: Int = 16

        @Option(name: .long, help: "Per-client bandwidth limit in bytes/sec (0 = unlimited)")
        var clientBandwidth: Int = 0

        @Flag(name: .shortAndLong, help: "Verbose output")
        var verbose: Bool = false

        mutating func validate() throws {
            guard port > 0, port < 65536 else {
                throw ValidationError("Port must be 1–65535")
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
                throw ValidationError("Directory not found: \(directory)")
            }
        }

        mutating func run() throws {
            try failDeferredJPIP("serve")
        }
    }
}

// MARK: - info

@available(macOS 10.15, *)
extension DICOMJpip {
    struct InfoCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] Display information about a JPIP server or DICOM file",
            discussion: """
                DEFERRED: `dicom-jpip` is deferred pending `SwiftJ2K` 12.2.0 (`SwiftJ2KJPIP` qualification).

                Shows JPIP transfer syntax information for a DICOM file, or queries
                server statistics when given a server URL.

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

        mutating func run() throws {
            try failDeferredJPIP("info")
        }
    }
}

DICOMJpip.main()
