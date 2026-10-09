import Foundation
import ArgumentParser
import DICOMCore
import DICOMNetwork
import DICOMWeb
// NEMA-verified: 2026a, checked 2026-10-01 — --level values diffed against PS3.4 2026a Tables C.6.1-1 / C.6.2-1 (PATIENT, STUDY, SERIES, IMAGE: 4 of 4 sent on the wire via QueryLevel; "instance" kept as a CLI alias of image); the match keys each option maps to checked against Tables C.6-1, C.6-3, C.6-4, C.6-5 (9 options, all listed at their level); wildcard and date-range help against C.2.2.2.4 / C.2.2.2.5; --modality terms via DICOMCore.Modality (C.7.3.1.1.1); --format json/csv keys are the tool's own "(GGGG,EEEE)" tag strings (documented in README); --format dicom-json is the PS3.18 2026a F.2 DICOM JSON Model via DICOMWeb.DICOMJSONEncoder (P-QUERY-JSON); --csv-keywords headers are PS3.6 Table 6-1 keywords and the table labels PS3.6 names (P-QUERY-COLUMNS)

@main
struct DICOMQuery: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-query",
        abstract: "Query DICOM servers using C-FIND and QIDO-RS protocols",
        discussion: """
            Performs DICOM queries against PACS servers using the C-FIND service.
            Supports patient, study, series, and image (instance) level queries
            (Query/Retrieve Level (0008,0052), PS3.4 C.4.1.1.3.1).
            
            The host argument accepts a hostname or IP address, optionally with a
            port suffix (host:port). Use --port to specify the port separately.
            If no port is given, the default is 11112.
            
            Examples:
              dicom-query server --port 11112 --aet MY_SCU --patient-name "SMITH^JOHN"
              dicom-query server:11112 --aet MY_SCU --study-date 20240101-20240131
              dicom-query server:11112 --aet MY_SCU --modality CT --format json
              dicom-query server:11112 --aet MY_SCU --modality CT --format dicom-json
              dicom-query 192.168.1.100:11112 --aet MY_SCU --level series --study-uid 1.2.3
              dicom-query server:11112 --aet MY_SCU --level image --study-uid 1.2.3 --series-uid 1.2.3.4
            """,
        version: "1.0.0"
    )
    
    @Argument(help: "PACS server hostname or IP address, optionally with port (host:port)")
    var host: String
    
    @Option(name: .long, help: "PACS server port (default: 11112, overrides port in host argument)")
    var port: UInt16?
    
    @Option(name: .long, help: "Local Application Entity Title (calling AE)")
    var aet: String
    
    @Option(name: .long, help: "Remote Application Entity Title (default: ANY-SCP)")
    var calledAet: String = "ANY-SCP"
    
    @Option(name: .shortAndLong, help: "Query/Retrieve Level (0008,0052): patient, study, series, image — the values of PS3.4 Tables C.6.1-1 / C.6.2-1; 'instance' is accepted as an alias of image (default: study)")
    var level: QueryLevelOption = .study
    
    @Option(name: .long, help: "Patient's Name (0010,0010); * and ? wild cards per PS3.4 C.2.2.2.4")
    var patientName: String?
    
    @Option(name: .long, help: "Patient ID")
    var patientId: String?
    
    @Option(name: .long, help: "Study Date (0008,0020): YYYYMMDD, or a range YYYYMMDD-YYYYMMDD, -YYYYMMDD (up to and including) or YYYYMMDD- (from, PS3.4 C.2.2.2.5)")
    var studyDate: String?
    
    @Option(name: .long, help: "Study Instance UID")
    var studyUid: String?
    
    @Option(name: .long, help: "Series Instance UID")
    var seriesUid: String?
    
    @Option(name: .long, help: "Accession Number")
    var accessionNumber: String?
    
    @Option(name: .long, help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("filter")))
    var modality: String?

    @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
    var strictModality: Bool = false
    
    @Option(name: .long, help: "Study Description (0008,1030); * and ? wild cards per PS3.4 C.2.2.2.4")
    var studyDescription: String?
    
    @Option(name: .long, help: "Referring physician name")
    var referringPhysician: String?
    
    @Option(name: .shortAndLong, help: "Output format: table, json, csv, compact, dicom-json (default: table). json is the tool's {\"(GGGG,EEEE)\": \"value\"} summary; dicom-json is the PS3.18 F.2 DICOM JSON Model (\"00100010\": {\"vr\": \"PN\", \"Value\": [...]})")
    var format: OutputFormat = .table

    @Flag(name: .long, help: "CSV header row names each column by its PS3.6 keyword (e.g. PatientName) instead of (GGGG,EEEE)")
    var csvKeywords: Bool = false
    
    @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
    var timeout: Int = 60
    
    @Flag(name: .long, help: "Show verbose output including query details")
    var verbose: Bool = false

    @Flag(name: .long, help: "Non-baseline: at SERIES/IMAGE level also request parent-level attributes (Patient Name/ID, Study Date/Description, Accession) as return keys, for lenient SCPs such as dcm4chee (PS3.4 C.4.1.2.1 does not allow them)")
    var includeParentKeys: Bool = false
    
    /// PS3.4 C.4.1.2.1: a SERIES query needs the parent Study UID, an IMAGE
    /// query needs Study and Series UIDs. Checked here so the message names the
    /// flag, before any connection is opened.
    func validate() throws {
        switch level {
        case .series:
            if (studyUid ?? "").isEmpty {
                throw ValidationError("--level series requires --study-uid (PS3.4 C.4.1.2.1: the Study Instance UID of the level above must be given)")
            }
        case .image:
            if (studyUid ?? "").isEmpty || (seriesUid ?? "").isEmpty {
                throw ValidationError("--level image (instance) requires --study-uid and --series-uid (PS3.4 C.4.1.2.1)")
            }
        default:
            break
        }
    }

    mutating func run() async throws {
        // Validate --modality once, up front: an unrecognized code otherwise
        // reaches the PACS as a filter that silently matches nothing.
        modality = try ModalityOptionValidator.resolve(
            modality, strict: strictModality, verbose: verbose)

        #if canImport(Network)
        let serverInfo = resolveHostPort()

        // Verbose header via the SHARED NetworkConsole formatter, printed to STDOUT so
        // its order matches DICOMStudio's in-process console (the parity harness diffs
        // the binary's stdout+stderr against the app). Gated on --verbose so a plain
        // run stays just the results table (clean for piping).
        if verbose {
            let model = level.queryLevel == .patient ? "Patient Root" : "Study Root"
            print(NetworkConsole.queryHeader(
                host: serverInfo.host, port: serverInfo.port,
                callingAE: aet, calledAE: calledAet,
                level: level.queryLevel, informationModel: model,
                timeout: timeout, filters: appliedFilters()), terminator: "")
        }

        // PS3.4 C.4.1.2.1: patient/study filters cannot be matched at SERIES or
        // IMAGE level under the hierarchical model. Say so instead of dropping
        // them silently.
        if let warning = parentLevelFilterWarning() {
            FileHandle.standardError.write((warning + "\n").data(using: .utf8) ?? Data())
        }

        // Build query keys
        let queryKeys = buildQueryKeys()

        // Execute query
        let executor = QueryExecutor(
            host: serverInfo.host,
            port: serverInfo.port,
            callingAE: aet,
            calledAE: calledAet,
            timeout: TimeInterval(timeout)
        )

        let results = try await executor.executeQuery(
            level: level.queryLevel,
            queryKeys: queryKeys
        )

        // Format and output results via the shared formatter (DICOMNetwork).
        let formatter = Self.formatter(format: format, level: level.queryLevel, csvKeywords: csvKeywords)
        let output = formatter.format(results: results)
        print(output, terminator: "")
        #else
        throw ValidationError("Network functionality is not available on this platform")
        #endif
    }

    /// The shared formatter; `dicom-json` is encoded by DICOMWeb's PS3.18 F.2
    /// encoder (pretty-printed, attributes in ascending tag order per F.2.2).
    static func formatter(format: OutputFormat, level: QueryLevel, csvKeywords: Bool) -> DICOMQueryResultFormatter {
        DICOMQueryResultFormatter(
            format: format.asShared, level: level,
            csvHeader: csvKeywords ? .keyword : .tag,
            dicomJSONEncoder: { try DICOMJSONEncoder(configuration: .init(prettyPrinted: true)).encodeMultiple($0) })
    }

    /// Applied, non-empty match filters in the canonical order shared with the app's
    /// header, so the verbose listing is identical on both sides.
    func appliedFilters() -> [(label: String, value: String)] {
        var f: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            if let v = value, !v.isEmpty { f.append((label, v)) }
        }
        add("Patient Name:", patientName)
        add("Patient ID:", patientId)
        add("Study Date:", studyDate)
        add("Modality:", modality)
        add("Study UID:", studyUid)
        add("Series UID:", seriesUid)
        add("Accession:", accessionNumber)
        add("Study Desc:", studyDescription)
        add("Referring Physician:", referringPhysician)
        return f
    }

    func buildQueryKeys() -> QueryKeys {
        // Single shared mapping (DICOMNetwork) used by the CLI, the app, and the
        // CLI-parity reference — so input→C-FIND keys cannot drift. (This is also
        // where the study-level `--modality` → ModalitiesInStudy fix lives.)
        DICOMQueryService.buildQueryKeys(
            level: level.queryLevel,
            patientName: patientName ?? "",
            patientID: patientId ?? "",
            studyDate: studyDate ?? "",
            modality: modality ?? "",
            accession: accessionNumber ?? "",
            studyDescription: studyDescription ?? "",
            referringPhysician: referringPhysician ?? "",
            studyUID: studyUid ?? "",
            seriesUID: seriesUid ?? "",
            includeParentLevelReturnKeys: includeParentKeys
        )
    }

    /// The stderr warning for patient/study filters given at SERIES/IMAGE
    /// level, or nil when nothing is ignored (PS3.4 C.4.1.2.1). Names the level
    /// by its Query/Retrieve Level (0008,0052) value (PS3.4 Table C.6.2-1).
    func parentLevelFilterWarning() -> String? {
        let ignored = DICOMQueryService.ignoredParentLevelFilters(
            level: level.queryLevel,
            patientName: patientName ?? "",
            patientID: patientId ?? "",
            studyDate: studyDate ?? "",
            accession: accessionNumber ?? "",
            studyDescription: studyDescription ?? "",
            referringPhysician: referringPhysician ?? ""
        )
        guard !ignored.isEmpty else { return nil }
        return "Warning: \(ignored.joined(separator: ", ")) cannot be matched at \(level.queryLevel.rawValue) level "
            + "under the hierarchical query model and will be ignored "
            + "(PS3.4 C.4.1.2.1: only the Unique Keys of the levels above may be sent). "
            + "Query at STUDY level first, then narrow with --study-uid."
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
}

/// The `--level` values. These are the Query/Retrieve Level (0008,0052) values of
/// PS3.4 Tables C.6.1-1 (Patient Root) and C.6.2-1 (Study Root) in lower case:
/// PATIENT, STUDY, SERIES, IMAGE. `instance` is kept as an alias of `image` (the
/// spelling earlier releases accepted); the value sent on the wire is always IMAGE.
enum QueryLevelOption: String, ExpressibleByArgument, CaseIterable {
    case patient
    case study
    case series
    case image

    /// Alternative spellings accepted on the command line, mapped to the standard value.
    static let aliases: [String: QueryLevelOption] = ["instance": .image]

    init?(argument: String) {
        let key = argument.lowercased()
        if let level = QueryLevelOption(rawValue: key) {
            self = level
        } else if let level = QueryLevelOption.aliases[key] {
            self = level
        } else {
            return nil
        }
    }

    static var allValueStrings: [String] { allCases.map(\.rawValue) + aliases.keys.sorted() }

    var queryLevel: QueryLevel {
        switch self {
        case .patient: return .patient
        case .study: return .study
        case .series: return .series
        case .image: return .image
        }
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case table
    case json
    case csv
    case compact
    /// PS3.18 F.2 DICOM JSON Model
    case dicomJSON = "dicom-json"

    /// Maps to the shared package formatter's format.
    var asShared: QueryOutputFormat { QueryOutputFormat(rawValue: rawValue) ?? .table }
}
