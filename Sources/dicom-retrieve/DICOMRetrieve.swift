import Foundation
import ArgumentParser
import DICOMCore
import DICOMNetwork
// NEMA-verified: 2026a, checked 2026-10-01 — option surface compared with PS3.4 2026a: the 3 retrieve levels and their unique keys (Table C.6.1-1 STUDY/SERIES/IMAGE; Table C.6-5 Study Instance UID U key; C.4.2.2.1 / C.4.3.2.1 one unique key per level above the retrieve level), the 2 methods and their SOP Classes (Table C.6.2.3-1, Study Root MOVE/GET), Move Destination (0000,0600) per PS3.7 Table 9.3-9, ports 104 / 11112 per PS3.8 9.1.2; host, --called-aet default, --output, --timeout, --parallel, --hierarchical, --verbose are plumbing; --priority low/medium/high diffed against PS3.7 2026a Tables 9.3-9 / 9.3-6 Priority (0000,0700) LOW 0002H / MEDIUM 0000H / HIGH 0001H (3 of 3); --relational-retrieve per PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3 byte 1, relaxing the above-level UIDs per C.4.2.2.2.1 / C.4.3.2.2.1

@main
struct DICOMRetrieve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-retrieve",
        abstract: "Retrieve DICOM files from PACS using C-MOVE or C-GET protocols",
        discussion: """
            Retrieves DICOM studies, series, or instances from PACS servers using the C-MOVE
            or C-GET service. C-MOVE requires a destination AE, while C-GET retrieves directly.
            
            The host argument accepts a hostname or IP address, optionally with a
            port suffix (host:port). Use --port to specify the port separately.
            If no port is given, the default is 11112.
            
            Examples:
              # Retrieve study using C-MOVE
              dicom-retrieve server --port 11112 \\
                --aet MY_SCU --called-aet PACS_SCP \\
                --move-dest MY_SCP \\
                --study-uid 1.2.840.xxx \\
                --output study_dir/
              
              # Retrieve using C-GET (simpler, no move destination)
              dicom-retrieve server --port 11112 \\
                --aet MY_SCU \\
                --study-uid 1.2.840.xxx \\
                --method c-get \\
                --output study_dir/
              
              # Retrieve specific series
              dicom-retrieve server:11112 \\
                --aet MY_SCU \\
                --move-dest MY_SCP \\
                --study-uid 1.2.840.xxx \\
                --series-uid 1.2.840.yyy \\
                --output series_dir/
              
              # Series by its UID alone (relational-retrieve, PS3.4 C.4.2.2.2.1),
              # at HIGH priority (Priority (0000,0700) 0001H, PS3.7 Table 9.3-9)
              dicom-retrieve server:11112 \\
                --aet MY_SCU \\
                --move-dest MY_SCP \\
                --series-uid 1.2.840.yyy \\
                --relational-retrieve --priority high
              
              # Bulk retrieve from UID list
              dicom-retrieve server --port 11112 \\
                --aet MY_SCU \\
                --move-dest MY_SCP \\
                --uid-list study_uids.txt \\
                --output studies/ \\
                --parallel 4
            """,
        version: "1.1.2"
    )
    
    @Argument(help: "PACS server hostname or IP address, optionally with port (host:port)")
    var host: String
    
    @Option(name: .long, help: "PACS server port (default: 11112, the registered DICOM port; 104 is the well-known port — PS3.8 9.1.2)")
    var port: UInt16?
    
    @Option(name: .long, help: "Local Application Entity Title (calling AE)")
    var aet: String
    
    @Option(name: .long, help: "Remote Application Entity Title (default: ANY-SCP)")
    var calledAet: String = "ANY-SCP"
    
    @Option(name: .long, help: "Study Instance UID (0020,000D) to retrieve — Query/Retrieve Level STUDY")
    var studyUid: String?
    
    @Option(name: .long, help: "Series Instance UID (0020,000E) to retrieve — Query/Retrieve Level SERIES (requires --study-uid unless --relational-retrieve)")
    var seriesUid: String?
    
    @Option(name: .long, help: "SOP Instance UID (0008,0018) to retrieve — Query/Retrieve Level IMAGE (requires --study-uid and --series-uid unless --relational-retrieve)")
    var instanceUid: String?
    
    @Option(name: .long, help: "File containing list of Study UIDs to retrieve (one per line)")
    var uidList: String?
    
    @Option(name: .long, help: "Output directory for retrieved files")
    var output: String = "."
    
    @Option(name: .long, help: "Retrieval method: c-move (Study Root Query/Retrieve Information Model - MOVE) or c-get (Study Root Query/Retrieve Information Model - GET) (default: c-move)")
    var method: RetrievalMethod = .cMove
    
    @Option(name: .long, help: "Move Destination (0000,0600): AE Title of the Storage SCP that receives the C-STORE sub-operations (required for C-MOVE)")
    var moveDest: String?
    
    @Flag(name: .long, help: "Organize C-GET output hierarchically (<output>/<Study Instance UID>/<Series Instance UID>/); C-MOVE output is stored by the move destination")
    var hierarchical: Bool = false
    
    @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
    var timeout: Int = 60
    
    @Option(name: .long, help: "Number of parallel retrieval operations (default: 1)")
    var parallel: Int = 1

    @Option(name: .long, help: "Priority (0000,0700) of the C-MOVE-RQ / C-GET-RQ: low (0002H), medium (0000H), high (0001H) — PS3.7 Tables 9.3-9 / 9.3-6 (default: medium)")
    var priority: RetrievePriorityOption = .medium

    @Flag(name: .long, help: "Propose relational-retrieval in a SOP Class Extended Negotiation Sub-Item (PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3 byte 1). With it, --series-uid or --instance-uid may be given without the UIDs of the levels above (PS3.4 C.4.2.2.2.1); if the SCP turns relational-retrieval down, such a request is not sent (exit 1)")
    var relationalRetrieve: Bool = false

    @Option(name: .long, help: "Requested transfer syntax for retrieved files — applies directly to C-GET and is advisory for C-MOVE. Accepts any name/UID the shared parser understands; canonical tokens: \(TransferSyntax.negotiableImageTokens.joined(separator: ", ")).")
    var transferSyntax: String?

    @Flag(name: .shortAndLong, help: "Show verbose output including progress")
    var verbose: Bool = false
    
    mutating func run() async throws {
        #if canImport(Network)
        let serverInfo = resolveHostPort()

        let preferredTransferSyntaxUID: String?
        if let transferSyntax, !transferSyntax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let syntax = TransferSyntax.parse(transferSyntax) else {
                throw ValidationError("Unknown transfer syntax: \(transferSyntax)")
            }
            preferredTransferSyntaxUID = syntax.uid
        } else {
            preferredTransferSyntaxUID = nil
        }
        
        // Validate method and destination
        if method == .cMove && moveDest == nil {
            throw ValidationError("C-MOVE requires --move-dest parameter")
        }

        // --parallel drives `chunked(into:)` / `stride(by:)`, which traps on a
        // non-positive stride. Reject it up front with a clear message.
        guard parallel >= 1 else {
            throw ValidationError("--parallel must be at least 1")
        }
        
        // Validate UID parameters
        try validateUIDOptions()
        
        // Create output directory
        try createOutputDirectory(output)

        // Header via the SHARED NetworkConsole formatter (DICOMNetwork), printed to
        // STDOUT so its order/wording matches DICOMStudio's in-process console. The
        // uid-list bulk path has no single study UID and no in-app equivalent, so it
        // skips the shared header.
        if uidList == nil {
            let levelLabel: String
            if instanceUid != nil { levelLabel = "Instance" }
            else if seriesUid != nil { levelLabel = "Series" }
            else { levelLabel = "Study" }
            print(NetworkConsole.retrieveHeader(
                method: method == .cGet ? "C-GET" : "C-MOVE",
                host: serverInfo.host, port: serverInfo.port,
                callingAE: aet, calledAE: calledAet,
                moveDestination: moveDest,
                level: levelLabel,
                studyUID: studyUid ?? "(not sent — relational-retrieve)", seriesUID: seriesUid, instanceUID: instanceUid,
                output: output, hierarchical: hierarchical, timeout: timeout,
                transferSyntax: transferSyntax,
                priority: priority == .medium ? nil : priority.dimseValue,
                relationalRetrieval: relationalRetrieve), terminator: "")
            print("Executing \(method == .cGet ? "C-GET" : "C-MOVE")...")
        }

        // Create executor
        let executor = RetrieveExecutor(
            host: serverInfo.host,
            port: serverInfo.port,
            callingAE: aet,
            calledAE: calledAet,
            moveDestination: moveDest,
            timeout: TimeInterval(timeout),
            outputPath: output,
            hierarchical: hierarchical,
            verbose: verbose,
            preferredTransferSyntaxUID: preferredTransferSyntaxUID,
            priority: priority.dimseValue,
            relationalRetrieval: relationalRetrieve
        )

        // Execute retrieval
        if let uidListPath = uidList {
            // Bulk retrieval from file
            let uids = try loadUIDList(from: uidListPath)
            if verbose {
                fprintln("Loaded \(uids.count) UIDs from \(uidListPath)")
                fprintln("")
            }
            try await executor.retrieveBulk(studyUIDs: uids, method: method, parallelism: parallel)
        } else if let sopUID = instanceUid {
            // Single instance retrieval (study/series UIDs may be absent only with
            // relational-retrieve, checked by validateUIDOptions)
            try await executor.retrieveInstance(
                studyUID: studyUid,
                seriesUID: seriesUid,
                sopUID: sopUID,
                method: method
            )
        } else if let seriesUID = seriesUid {
            // Series retrieval
            try await executor.retrieveSeries(
                studyUID: studyUid,
                seriesUID: seriesUID,
                method: method
            )
        } else if let studyUID = studyUid {
            // Study retrieval
            try await executor.retrieveStudy(studyUID: studyUID, method: method)
        }
        
        #else
        throw ValidationError("Network functionality is not available on this platform")
        #endif
    }
    
    /// The UID options needed per retrieve level. Baseline (PS3.4 C.4.2.2.1 /
    /// C.4.3.2.1): a Unique Key for each level above the retrieve level, so
    /// --series-uid needs --study-uid and --instance-uid needs both. With
    /// --relational-retrieve (PS3.4 C.4.2.2.2.1 / C.4.3.2.2.1) the retrieve
    /// level's own UID is enough.
    func validateUIDOptions() throws {
        guard studyUid != nil || uidList != nil || (relationalRetrieve && (seriesUid != nil || instanceUid != nil)) else {
            throw ValidationError(relationalRetrieve
                ? "Must specify --study-uid, --series-uid, --instance-uid or --uid-list"
                : "Must specify either --study-uid or --uid-list")
        }
        if relationalRetrieve { return }

        if seriesUid != nil && studyUid == nil {
            throw ValidationError("--series-uid requires --study-uid (PS3.4 C.4.2.2.1), or --relational-retrieve")
        }
        
        if instanceUid != nil && (studyUid == nil || seriesUid == nil) {
            throw ValidationError("--instance-uid requires both --study-uid and --series-uid (PS3.4 C.4.2.2.1), or --relational-retrieve")
        }
    }

    /// Resolves the final host and port from ``--host`` and ``--port`` options.
    func resolveHostPort() -> (host: String, port: UInt16) {
        var resolvedHost = host
        var resolvedPort: UInt16 = port ?? 11112

        if resolvedHost.hasPrefix("pacs://") {
            resolvedHost = String(resolvedHost.dropFirst(7))
        }

        if let lastColon = resolvedHost.lastIndex(of: ":") {
            let portString = String(resolvedHost[resolvedHost.index(after: lastColon)...])
            if let embeddedPort = UInt16(portString) {
                resolvedHost = String(resolvedHost[..<lastColon])
                if port == nil {
                    resolvedPort = embeddedPort
                }
            }
        }

        return (resolvedHost, resolvedPort)
    }
    
    func createOutputDirectory(_ path: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw ValidationError("Output path exists but is not a directory: \(path)")
            }
        } else {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }
    
    func loadUIDList(from path: String) throws -> [String] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") } // Filter empty lines and comments
    }
}

enum RetrievalMethod: String, ExpressibleByArgument {
    case cMove = "c-move"
    case cGet = "c-get"
}

/// The `--priority` values, mapped to the Priority (0000,0700) values of PS3.7
/// Tables 9.3-9 (C-MOVE-RQ) / 9.3-6 (C-GET-RQ): LOW = 0002H, MEDIUM = 0000H,
/// HIGH = 0001H.
enum RetrievePriorityOption: String, ExpressibleByArgument, CaseIterable {
    case low
    case medium
    case high

    var dimseValue: DIMSEPriority {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

/// Prints to stderr
private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}
