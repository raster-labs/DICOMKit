// NEMA-verified: 2026a, checked 2026-10-06 — --sps-status Defined Terms and warning are DICOMNetwork WorklistQueryKeys' (D264, PS3.3 Table C.4-10 re-read); the 9 matching keys behind --date/--time/--station/--patient/
// --patient-id/--modality/--sps-status/--accession-number/--performing-physician diffed against PS3.4 2026a
// Table K.6-1 (139 rows; matching-key type and allowed matching per row); Range Matching forms against PS3.4
// C.2.2.2.5.1/.2 and the combined date-time remark under (0040,0003) in Table K.6-1; SPS Status values against
// PS3.3 Table C.4-10 (0040,0020) Defined Terms (5: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED); SOP Class UID
// against PS3.6 Table A-1; DA/TM forms against PS3.5 Table 6.2-1. The 38 JSON keys and the response statuses are
// shared DICOMNetwork code (NetworkConsole.mwlJSON, DIMSEStatus): 28 keys are PS3.6 keywords; the other 10 are
// now also written under their PS3.6 2026a Table 6-1 keywords (P-MWL-JSON-KEYS, 10 of 10 checked), old keys kept.
import Foundation
import ArgumentParser
import DICOMCore
import DICOMNetwork

@main
struct DICOMMWLCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-mwl",
        abstract: "DICOM Modality Worklist Management (MWL C-FIND)",
        discussion: """
            Query and manage DICOM Modality Worklist items. Implements the Modality
            Worklist Information Model (MWL) for querying scheduled procedure steps
            from a worklist SCP server.
            
            URL Format:
              hostname               - PACS server hostname or IP address
              hostname:port          - Hostname with embedded port
              --port port            - Optional explicit port (default: 11112)
            
            Examples:
              # Query worklist for today
              dicom-mwl query server --port 11112 --aet MODALITY --date today

              # Query with filters
              dicom-mwl query server:11112 --aet MODALITY \\
                --date 20240315 --station CT1 --patient "DOE^JOHN"

              # Query a date range (both bounds inclusive)
              dicom-mwl query server --port 11112 --aet MODALITY \\
                --date 20240705-20240707

              # Query an open-ended date range (everything from today onward)
              dicom-mwl query server --port 11112 --aet MODALITY \\
                --date today-

              # Query a combined date+time range as one continuous interval
              # (PS3.4 Table K.6-1, remark under Scheduled Procedure Step Start
              # Time (0040,0003)): July 5 10:00 through July 7 18:00
              dicom-mwl query server --port 11112 --aet MODALITY \\
                --date 20240705-20240707 --time 1000-1800

              # Filter to only SCHEDULED steps (PS3.3 Table C.4-10 Defined Term)
              dicom-mwl query server --port 11112 --aet MODALITY \\
                --sps-status SCHEDULED

              # Filter by modality and date with JSON output
              dicom-mwl query 192.168.1.100 --port 11112 --aet MODALITY \\
                --modality CT --date today --json

              # Verbose output showing all attributes
              dicom-mwl query server --port 11112 --aet MODALITY \\
                --date today --verbose

            Date/Time filter syntax (PS3.4 C.2.2.2.5.1 for DA, C.2.2.2.5.2 for TM):
              --date YYYYMMDD              Single Value Matching
              --date YYYYMMDD-YYYYMMDD     Range Matching (both bounds inclusive)
              --date YYYYMMDD-             Open-ended range (that date onward)
              --date -YYYYMMDD             Open-ended range (up to and including that date)
              --date today | tomorrow      Convenience shorthands, usable as a bound too
              --time HHMMSS[-HHMMSS]       Same Single Value / Range Matching for time;
                                           a TM value may be HH, HHMM or HHMMSS[.FFFFFF]
                                           (PS3.5 Table 6.2-1), never across midnight

            SPS Status (0040,0020) Defined Terms (PS3.3 Table C.4-10):
              SCHEDULED, ARRIVED, READY, STARTED, DEPARTED
            (IN PROGRESS / COMPLETED / DISCONTINUED are Performed Procedure Step
            Status values, PS3.3 Table C.4-14, and never appear in a worklist.)
            
            Note: If the server returns a limited number of results, adjust the
            server-side maximum results configuration (e.g., MaximumResults in
            Orthanc, or max_worklist_results in dcm4chee).
            
            Reference: PS3.4 Annex K - Modality Worklist Information Model
            """,
        version: "1.0.0",
        subcommands: [Query.self]
    )
}

// MARK: - Query Subcommand

extension DICOMMWLCommand {
    struct Query: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "query",
            abstract: "Query Modality Worklist (C-FIND)"
        )
        
        @Argument(help: "PACS server hostname or IP address, optionally with port (host:port)")
        var host: String
        
        @Option(name: .long, help: "PACS server port (default: 11112)")
        var port: UInt16?
        
        @Option(name: .long, help: "Local Application Entity Title (calling AE)")
        var aet: String
        
        @Option(name: .long, help: "Remote Application Entity Title (default: ANY-SCP)")
        var calledAet: String = "ANY-SCP"
        
        @Option(name: .long, help: "Scheduled date filter: YYYYMMDD, 'today', 'tomorrow', or a DICOM date range (YYYYMMDD-YYYYMMDD, YYYYMMDD-, -YYYYMMDD). A leading-hyphen range needs the equals form: --date=-YYYYMMDD")
        var date: String?

        @Option(name: .long, help: "Scheduled time filter: HHMMSS (or HH / HHMM / HHMMSS.FFFFFF, PS3.5 Table 6.2-1 TM), or a DICOM time range (HHMMSS-HHMMSS, HHMMSS-, -HHMMSS; PS3.4 C.2.2.2.5.2). Combined with --date as one continuous interval when both are ranges (PS3.4 Table K.6-1, remark under (0040,0003)). A leading-hyphen range needs the equals form: --time=-HHMMSS")
        var time: String?

        @Option(name: .long, help: "Scheduled Station AE Title filter")
        var station: String?
        
        @Option(name: .long, help: "Patient name filter (supports wildcards: *)")
        var patient: String?
        
        @Option(name: .long, help: "Patient ID filter")
        var patientId: String?
        
        @Option(name: .long, help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("filter")))
        var modality: String?

        @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
        var strictModality: Bool = false
        
        @Option(name: .long, help: "Scheduled Procedure Step Status (0040,0020) filter. Defined Terms per PS3.3 Table C.4-10: SCHEDULED, ARRIVED, READY, STARTED, DEPARTED (another value is sent as given, with a warning)")
        var spsStatus: String?
        
        @Option(name: .long, help: "Accession number filter")
        var accessionNumber: String?
        
        @Option(name: .long, help: "Scheduled Performing Physician's Name filter (supports wildcards: *)")
        var performingPhysician: String?

        @Option(name: .long, help: "Force the Specific Character Set (0008,0005) of the query, e.g. ISO_IR 100 or ISO_IR 192. By default the narrowest set that represents every text key is chosen (none for pure ASCII)")
        var specificCharacterSet: String?
        
        @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
        var timeout: Int = 60
        
        @Flag(name: .shortAndLong, help: "Show verbose output")
        var verbose: Bool = false
        
        @Flag(name: .long, help: "Output as JSON. Keys are PS3.6 keywords (e.g. ScheduledProcedureStepStartDate, ReferencedStudySequence); the abbreviated keys SPSStartDate, SPSStartTime, SPSStatus, SPSID, SPSDescription, SPSLocation, ScheduledPerformingPhysician, RequestedProcedureCode, ScheduledProtocolCodes, ReferencedStudySOPInstanceUID are still written but deprecated")
        var json: Bool = false
        
        /// Scheduled Procedure Step Status (0040,0020) Defined Terms, PS3.3 2026a Table C.4-10 —
        /// DICOMNetwork's `WorklistQueryKeys.scheduledProcedureStepStatusDefinedTerms` (D264).
        @available(*, deprecated, renamed: "WorklistQueryKeys.scheduledProcedureStepStatusDefinedTerms")
        static var scheduledProcedureStepStatusDefinedTerms: [String] {
            WorklistQueryKeys.scheduledProcedureStepStatusDefinedTerms
        }

        /// The warning printed to stderr for a `--sps-status` value outside Table C.4-10,
        /// or nil when the value is a Defined Term (or absent) — DICOMNetwork's
        /// `WorklistQueryKeys.spsStatusWarning` (D264).
        static func spsStatusWarning(_ value: String?) -> String? {
            WorklistQueryKeys.spsStatusWarning(value)
        }

        mutating func run() async throws {
            // Validate --modality up front: an unrecognized code otherwise
            // reaches the PACS as a filter that silently matches nothing.
            modality = try ModalityOptionValidator.resolve(
                modality, strict: strictModality, verbose: verbose)

            if let warning = Query.spsStatusWarning(spsStatus) {
                FileHandle.standardError.write(Data(warning.utf8))
            }

            #if canImport(Network)
            // Resolve host and port
            let serverInfo = resolveHostPort()
            
            // Verbose header via the SHARED NetworkConsole formatter (DICOMNetwork),
            // printed to STDOUT so its order matches the Studio MWL panel (the parity
            // harness diffs the binary's stdout+stderr against the app). Gated on
            // --verbose (and suppressed in --json mode so the JSON array stays clean).
            if verbose && !json {
                print(NetworkConsole.mwlQueryHeader(
                    host: serverInfo.host, port: serverInfo.port,
                    callingAE: aet, calledAE: calledAet,
                    timeout: timeout, filters: appliedFilters()), terminator: "")
            }

            try await performQuery(serverInfo: serverInfo)
            
            #else
            throw ValidationError("Network functionality is not available on this platform")
            #endif
        }
        
        #if canImport(Network)
        func performQuery(serverInfo: (host: String, port: UInt16)) async throws {
            // Build query keys via the SHARED package builder (DICOMNetwork) — the same
            // mapping DICOMStudio's in-app query and the CLI-parity reference use, so the
            // input→C-FIND mapping cannot drift between the CLI and the app.
            let queryKeys: WorklistQueryKeys
            do {
                queryKeys = try WorklistQueryKeys.forQuery(
                    date: date ?? "",
                    time: time ?? "",
                    station: station ?? "",
                    patientName: patient ?? "",
                    patientID: patientId ?? "",
                    modality: modality ?? "",
                    spsStatus: spsStatus ?? "",
                    accession: accessionNumber ?? "",
                    performingPhysician: performingPhysician ?? ""
                )
            } catch {
                throw ValidationError((error as? WorklistDateFilterError)?.description ?? "\(error)")
            }

            // Perform query
            let items = try await DICOMModalityWorklistService.find(
                host: serverInfo.host,
                port: serverInfo.port,
                callingAE: aet,
                calledAE: calledAet,
                matching: queryKeys,
                timeout: TimeInterval(timeout),
                specificCharacterSet: specificCharacterSet
            )

            // Render via the SHARED NetworkConsole formatter (DICOMNetwork) to STDOUT —
            // the IDENTICAL functions the Studio MWL panel uses, so the formatted list,
            // the JSON array, and the result-limit caution cannot drift between sides.
            if json {
                print(NetworkConsole.mwlJSON(items: items), terminator: "")
            } else if items.isEmpty {
                print(NetworkConsole.mwlNoResults(), terminator: "")
            } else {
                print(NetworkConsole.mwlFound(count: items.count), terminator: "")
                for (index, item) in items.enumerated() {
                    print(NetworkConsole.mwlItem(index: index + 1, item: item, verbose: verbose), terminator: "")
                }
                print(NetworkConsole.mwlCompleted(count: items.count), terminator: "")
            }
            // Warn about a likely server-side result limit (heuristic lives in the
            // shared formatter). Suppressed in --json mode to keep the array clean.
            if !json {
                let warning = NetworkConsole.mwlLimitWarning(count: items.count)
                if !warning.isEmpty { print(warning, terminator: "") }
            }
        }
        #endif

        /// Applied, non-empty worklist filters in the canonical order/labels shared
        /// with the Studio MWL header, so the verbose listing is identical on both sides.
        func appliedFilters() -> [(label: String, value: String)] {
            var f: [(String, String)] = []
            func add(_ label: String, _ value: String?) {
                if let v = value, !v.isEmpty { f.append((label, v)) }
            }
            add("Date:", date)
            add("Time:", time)
            add("Station AET:", station)
            add("Patient Name:", patient)
            add("Patient ID:", patientId)
            add("Modality:", modality)
            add("SPS Status:", spsStatus)
            add("Accession:", accessionNumber)
            add("Performing Physician:", performingPhysician)
            return f
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
}
