import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMNetwork
// NEMA-verified: 2026a, checked 2026-10-06 — a non-success C-MOVE / C-GET final response is reported by DICOMNetwork NetworkConsole.retrieveFinalResponse in dicom-retrieve wording (D262; PS3.4 Tables C.4-2 / C.4-3, PS3.7 Table 9.3-10, PS3.6 (0008,0058) re-read); the 7 match keys compared with PS3.4 2026a Table C.6-5 (Study Root, Study level: 4 R keys, 1 U key, 2 O keys — Modalities in Study (0008,0061) carries --modality), wildcard / range matching with C.2.2.2.4 / C.2.2.2.5, Query/Retrieve Level STUDY with Table C.6.1-1, methods with Table C.6.2.3-1 (Study Root MOVE/GET), Move Destination (0000,0600) with PS3.7 Table 9.3-9, final-status handling with Tables C.4-2 / C.4-3 via DICOMNetwork.DIMSEServiceStatusText, --priority with PS3.7 Tables 9.3-9 / 9.3-6 (LOW 0002H / MEDIUM 0000H / HIGH 0001H, 3 of 3), state key ModalitiesInStudy with PS3.6 Table 6-1 (0008,0061), ports 104 / 11112 with PS3.8 9.1.2; the Part 10 wrapper writes the 6 Type 1 rows of PS3.10 2026a Table 7.1-1; modes, state file, --output, --timeout, --parallel (concurrent batches, one association per study), --validate, --verbose are plumbing

@main
struct DICOMQR: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-qr",
        abstract: "Integrated DICOM query-retrieve tool",
        discussion: """
            Performs integrated C-FIND query and C-MOVE/C-GET retrieval operations.
            Provides both interactive and automatic modes for seamless workflow.
            
            Interactive Mode:
              Query PACS, display results, and interactively select studies to retrieve.
            
            Automatic Mode:
              Query PACS and automatically retrieve all matching studies.
            
            Resume Mode:
              Resume interrupted retrievals from saved state.
            
            Examples:
              # Interactive query and retrieve
              dicom-qr \\
                server --port 11112 \\
                --aet MY_AET --called-aet PACS_SCP \\
                --move-dest MY_SCP \\
                --patient-name "DOE*" \\
                --interactive
              
              # Automatic query and retrieve
              dicom-qr \\
                server:11112 \\
                --aet MY_AET \\
                --move-dest MY_SCP \\
                --study-date "20240101-20240131" \\
                --modality CT \\
                --output studies/ \\
                --auto
              
              # Query, review, then retrieve
              dicom-qr \\
                server --port 11112 \\
                --aet MY_AET \\
                --patient-id "12345" \\
                --review \\
                --save-state query.state
              
              # Resume interrupted retrieval
              dicom-qr resume --state retrieval.state
            """,
        version: "1.2.3",
        subcommands: [
            Query.self,
            Resume.self
        ],
        defaultSubcommand: Query.self
    )
}

// MARK: - Query Subcommand

extension DICOMQR {
    struct Query: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "query",
            abstract: "Query and retrieve DICOM studies"
        )
        
        @Argument(help: "PACS server hostname or IP address, optionally with port (host:port)")
        var host: String
        
        @Option(name: .long, help: "PACS server port (default: 11112, the registered DICOM port; 104 is the well-known port — PS3.8 9.1.2)")
        var port: UInt16?
        
        @Option(name: .long, help: "Local Application Entity Title (calling AE)")
        var aet: String
        
        @Option(name: .long, help: "Remote Application Entity Title (default: ANY-SCP)")
        var calledAet: String = "ANY-SCP"
        
        @Option(name: .long, help: "Move Destination (0000,0600): AE Title of the Storage SCP that receives the C-STORE sub-operations (required for C-MOVE)")
        var moveDest: String?
        
        @Option(name: .long, help: "Retrieval method: c-move (Study Root Query/Retrieve Information Model - MOVE) or c-get (Study Root Query/Retrieve Information Model - GET) (default: c-move)")
        var method: String = "c-move"
        
        // Query parameters
        @Option(name: .long, help: "Patient's Name (0010,0010) — wildcards * and ? per PS3.4 C.2.2.2.4 (case handling of PN matching is the SCP's)")
        var patientName: String?
        
        @Option(name: .long, help: "Patient ID (0010,0020)")
        var patientId: String?
        
        @Option(name: .long, help: "Study Date (0008,0020): YYYYMMDD, or a range YYYYMMDD-YYYYMMDD, -YYYYMMDD or YYYYMMDD- (PS3.4 C.2.2.2.5)")
        var studyDate: String?
        
        @Option(name: .long, help: "Study Instance UID (0020,000D)")
        var studyUid: String?
        
        @Option(name: .long, help: "Accession Number (0008,0050)")
        var accessionNumber: String?
        
        @Option(name: .long, help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("filter")))
        var modality: String?

        @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
        var strictModality: Bool = false
        
        @Option(name: .long, help: "Study Description (0008,1030) — wildcards * and ? per PS3.4 C.2.2.2.4")
        var studyDescription: String?
        
        // Output options
        @Option(name: .shortAndLong, help: "Output directory for retrieved files")
        var output: String = "."
        
        @Flag(name: .long, help: "Organize C-GET output hierarchically (<output>/<Study Instance UID>/); C-MOVE output is stored by the move destination")
        var hierarchical: Bool = false
        
        // Mode options
        @Flag(name: .long, help: "Interactive mode - select studies to retrieve")
        var interactive: Bool = false
        
        @Flag(name: .long, help: "Automatic mode - retrieve all matching studies")
        var auto: Bool = false
        
        @Flag(name: .long, help: "Review mode - query only, save state for later")
        var review: Bool = false
        
        @Option(name: .long, help: "Save query/retrieval state to file")
        var saveState: String?
        
        // Additional options
        @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
        var timeout: Int = 60
        
        @Option(name: .long, help: "Maximum concurrent retrievals: up to N studies are retrieved at once, each on its own association; per-study lines are printed in study order (default: 1)")
        var parallel: Int = 1

        @Option(name: .long, help: "Priority (0000,0700) of each C-MOVE-RQ / C-GET-RQ: low (0002H), medium (0000H), high (0001H) — PS3.7 Tables 9.3-9 / 9.3-6 (default: medium)")
        var priority: QRPriorityOption = .medium
        
        @Flag(name: .long, help: "Validate retrieved files")
        var validate: Bool = false

        @Option(name: .long, help: "Requested transfer syntax for retrieved files — negotiated during association setup. Accepts any name/UID the shared parser understands; canonical tokens: \(TransferSyntax.negotiableImageTokens.joined(separator: ", ")).")
        var transferSyntax: String?

        @Flag(name: .long, help: "Show verbose output")
        var verbose: Bool = false

        @Flag(name: .long, help: "Non-baseline: also request parent-level attributes as return keys at SERIES/INSTANCE level (dicom-qr queries at STUDY level, where every requested key is already level-appropriate; accepted for parity with dicom-query)")
        var includeParentKeys: Bool = false
        
        /// Resolves the final host and port.
        func resolveHostPort() -> (host: String, port: UInt16) {
            dicom_qr.resolveHostPort(host: host, port: port)
        }
        
        mutating func run() async throws {
            // Validate --modality up front: an unrecognized code otherwise
            // reaches the PACS as a filter that silently matches nothing.
            modality = try ModalityOptionValidator.resolve(
                modality, strict: strictModality, verbose: verbose)

            #if canImport(Network)
            // Validate mode selection
            let modeCount = [interactive, auto, review].filter { $0 }.count
            if modeCount == 0 {
                throw ValidationError("Must specify one of: --interactive, --auto, or --review")
            }
            if modeCount > 1 {
                throw ValidationError("Cannot specify multiple modes (--interactive, --auto, --review)")
            }
            
            // --parallel sizes the concurrent batches; 0 or less would never retrieve.
            guard parallel >= 1 else {
                throw ValidationError("--parallel must be at least 1")
            }

            // Validate retrieval method
            let retrievalMethod: RetrievalMethod
            switch method.lowercased() {
            case "c-move":
                retrievalMethod = .cMove
                guard moveDest != nil else {
                    throw ValidationError("--move-dest is required for C-MOVE method")
                }
            case "c-get":
                retrievalMethod = .cGet
            default:
                throw ValidationError("Invalid method: \(method). Use c-move or c-get")
            }
            
            // Resolve the requested transfer syntax via the SHARED DICOMCore parser
            // (TransferSyntax.parse) — the identical alias map dicom-retrieve and the
            // in-app executor use; an unrecognized name is an error, never a silent nil.
            let preferredTransferSyntaxUID: String?
            if let transferSyntax, !transferSyntax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let syntax = TransferSyntax.parse(transferSyntax) else {
                    throw ValidationError("Unknown transfer syntax: \(transferSyntax)")
                }
                preferredTransferSyntaxUID = syntax.uid
            } else {
                preferredTransferSyntaxUID = nil
            }

            // Parse server
            let serverInfo = resolveHostPort()

            // Header via the SHARED NetworkConsole formatter (DICOMNetwork), printed to
            // STDOUT so its order/wording matches DICOMStudio's in-process console.
            let modeLabel = interactive ? "Interactive" : (auto ? "Automatic" : "Review")
            print(NetworkConsole.qrHeader(
                host: serverInfo.host, port: serverInfo.port,
                callingAE: aet, calledAE: calledAet,
                mode: modeLabel,
                method: retrievalMethod == .cMove ? "C-MOVE" : "C-GET",
                isReview: review, moveDestination: moveDest,
                output: output, timeout: timeout,
                transferSyntax: transferSyntax,
                filters: appliedFilters()), terminator: "")

            // Build query keys
            let queryKeys = buildQueryKeys()

            let queryExecutor = QueryExecutor(
                host: serverInfo.host,
                port: serverInfo.port,
                callingAE: aet,
                calledAE: calledAet,
                timeout: TimeInterval(timeout)
            )
            
            let results = try await queryExecutor.executeQuery(level: .study, queryKeys: queryKeys)
            
            if results.isEmpty {
                print(NetworkConsole.qrNoStudies(), terminator: "")
                return
            }

            print(NetworkConsole.qrFound(count: results.count), terminator: "")

            // Study list via the SHARED NetworkConsole formatter (DICOMNetwork). Uses
            // toStudyResult() (and ModalitiesInStudy, the key actually requested) so the
            // fields match DICOMStudio's in-process qr exactly.
            for (index, result) in results.enumerated() {
                let s = result.toStudyResult()
                print(NetworkConsole.qrStudyEntry(
                    index: index + 1,
                    patientName: s.patientName, patientID: s.patientID,
                    studyDescription: s.studyDescription, studyDate: s.studyDate,
                    modality: s.modalitiesInStudy, studyUID: s.studyInstanceUID), terminator: "")
            }

            // Handle different modes
            if review {
                print(NetworkConsole.qrReviewComplete(count: results.count), terminator: "")
                if let statePath = saveState {
                    try saveQueryState(results: results, path: statePath)
                    print(NetworkConsole.qrStateSaved(path: statePath), terminator: "")
                }
                return
            }

            // Determine which studies to retrieve
            let studiesToRetrieve: [GenericQueryResult]
            if interactive {
                studiesToRetrieve = try selectStudiesInteractively(results)
            } else {
                studiesToRetrieve = results
            }

            if studiesToRetrieve.isEmpty {
                print(NetworkConsole.qrNoSelection(), terminator: "")
                return
            }

            print(NetworkConsole.qrRetrieving(count: studiesToRetrieve.count), terminator: "")

            // Create retrieve executor
            let retrieveExecutor = RetrieveExecutor(
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
                priority: priority.dimseValue
            )

            // Save state if requested before retrieval
            if let statePath = saveState {
                try saveRetrievalState(
                    studies: studiesToRetrieve,
                    host: serverInfo.host,
                    port: serverInfo.port,
                    callingAE: aet,
                    calledAE: calledAet,
                    moveDestination: moveDest,
                    method: retrievalMethod,
                    outputPath: output,
                    hierarchical: hierarchical,
                    path: statePath
                )
            }
            
            // Execute retrievals. Each retrieval opens its own association
            // (DICOMRetrieveService), so up to --parallel of them run at once; the
            // per-study lines are printed in study order once a batch is done
            // (with --parallel 1 each line is printed before its retrieval starts).
            var successCount = 0
            var failureCount = 0
            let total = studiesToRetrieve.count
            let numbered = Array(studiesToRetrieve.enumerated())

            for batch in stride(from: 0, to: numbered.count, by: parallel).map({ Array(numbered[$0 ..< Swift.min($0 + parallel, numbered.count)]) }) {
                if parallel == 1, let (index, result) = batch.first {
                    let s = result.toStudyResult()
                    if let studyUID = s.studyInstanceUID {
                        print(NetworkConsole.qrRetrieveLine(
                            index: index + 1, total: total,
                            patientName: s.patientName, studyUID: studyUID), terminator: "")
                    }
                    let outcome = await Self.retrieve(result, executor: retrieveExecutor, method: retrievalMethod)
                    Self.printOutcome(outcome, index: index, total: total, result: result, lineAlreadyPrinted: true)
                    if case .success = outcome { successCount += 1 } else { failureCount += 1 }
                    continue
                }
                var outcomes: [Int: StudyRetrieveOutcome] = [:]
                await withTaskGroup(of: (Int, StudyRetrieveOutcome).self) { group in
                    for (index, result) in batch {
                        group.addTask {
                            (index, await Self.retrieve(result, executor: retrieveExecutor, method: retrievalMethod))
                        }
                    }
                    for await (index, outcome) in group { outcomes[index] = outcome }
                }
                for (index, result) in batch {
                    let outcome = outcomes[index] ?? .failed("not run")
                    Self.printOutcome(outcome, index: index, total: total, result: result, lineAlreadyPrinted: false)
                    if case .success = outcome { successCount += 1 } else { failureCount += 1 }
                }
            }

            // Summary via the SHARED formatter.
            print(NetworkConsole.qrSummary(
                total: studiesToRetrieve.count, success: successCount, failed: failureCount), terminator: "")

            if validate && successCount > 0 {
                print(NetworkConsole.qrValidatingHeader(), terminator: "")
                try validateRetrievedFiles(in: output)
            }

            // A study whose final C-MOVE/C-GET response was not Success with no
            // failed sub-operations (PS3.4 C.4.2.2.1 / C.4.3.2.1), or that could
            // not be requested at all, must not leave the exit code at 0.
            if failureCount > 0 {
                throw DICOMQRError.retrievalIncomplete(succeeded: successCount, failed: failureCount)
            }
            #else
            print("Error: Network operations not supported on this platform")
            throw ExitCode(1)
            #endif
        }
        
        // MARK: - Retrieval

        enum StudyRetrieveOutcome: Sendable {
            case missingStudyUID
            case success
            case failed(String)
        }

        /// Retrieves one study; never throws, so a batch always completes.
        static func retrieve(_ result: GenericQueryResult, executor: RetrieveExecutor,
                             method: RetrievalMethod) async -> StudyRetrieveOutcome {
            guard let studyUID = result.toStudyResult().studyInstanceUID else { return .missingStudyUID }
            do {
                try await executor.retrieveStudy(studyUID: studyUID, method: method)
                return .success
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        /// The per-study lines via the shared NetworkConsole formatter.
        static func printOutcome(_ outcome: StudyRetrieveOutcome, index: Int, total: Int,
                                 result: GenericQueryResult, lineAlreadyPrinted: Bool) {
            let s = result.toStudyResult()
            switch outcome {
            case .missingStudyUID:
                print(NetworkConsole.qrMissingStudyUID(index: index + 1, total: total), terminator: "")
            case .success, .failed:
                if !lineAlreadyPrinted, let studyUID = s.studyInstanceUID {
                    print(NetworkConsole.qrRetrieveLine(
                        index: index + 1, total: total,
                        patientName: s.patientName, studyUID: studyUID), terminator: "")
                }
                if case .failed(let message) = outcome {
                    print(NetworkConsole.qrRetrieveOutcome(success: false, error: message), terminator: "")
                } else {
                    print(NetworkConsole.qrRetrieveOutcome(success: true, error: nil), terminator: "")
                }
            }
        }

        // MARK: - Helper Methods
        
        private func buildQueryKeys() -> QueryKeys {
            // dicom-qr always queries at STUDY level, so every filter here is a
            // level-appropriate key (PS3.4 C.4.1.2.1). Keys are built through the
            // SHARED DICOMNetwork mapping (the same one dicom-query and the app
            // use) so the input→C-FIND mapping cannot drift; the patient-name
            // match key is upper-cased as before.
            DICOMQueryService.buildQueryKeys(
                level: .study,
                patientName: patientName?.uppercased() ?? "",
                patientID: patientId ?? "",
                studyDate: studyDate ?? "",
                modality: modality ?? "",
                accession: accessionNumber ?? "",
                studyDescription: studyDescription ?? "",
                studyUID: studyUid ?? "",
                includeParentLevelReturnKeys: includeParentKeys
            )
        }

        /// Applied, non-empty match filters in the canonical order shared with the
        /// app's header, so the header listing is identical on both sides.
        private func appliedFilters() -> [(label: String, value: String)] {
            var f: [(String, String)] = []
            func add(_ label: String, _ value: String?) {
                if let v = value, !v.isEmpty { f.append((label, v)) }
            }
            add("Patient Name:", patientName)
            add("Patient ID:", patientId)
            add("Study Date:", studyDate)
            add("Modality:", modality)
            add("Study UID:", studyUid)
            add("Accession:", accessionNumber)
            add("Study Desc:", studyDescription)
            return f
        }

        private func selectStudiesInteractively(_ results: [GenericQueryResult]) throws -> [GenericQueryResult] {
            print("")
            print("Enter study numbers to retrieve (comma-separated, or 'all'):")
            print("Examples: 1,3,5  or  all  or  1-5")
            print("")
            print("> ", terminator: "")
            
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
                return []
            }
            
            if input.lowercased() == "all" {
                return results
            }
            
            var selectedIndices = Set<Int>()
            let parts = input.components(separatedBy: ",")
            
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                
                // Handle ranges (e.g., "1-5")
                if trimmed.contains("-") {
                    let rangeParts = trimmed.components(separatedBy: "-")
                    if rangeParts.count == 2,
                       let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
                       let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                        // Accept ranges in either order (e.g. "5-1" == "1-5") so a reversed
                        // range never traps `start...end`.
                        for i in Swift.min(start, end)...Swift.max(start, end) {
                            if i >= 1 && i <= results.count {
                                selectedIndices.insert(i - 1)
                            }
                        }
                    }
                } else if let index = Int(trimmed) {
                    if index >= 1 && index <= results.count {
                        selectedIndices.insert(index - 1)
                    }
                }
            }
            
            return selectedIndices.sorted().map { results[$0] }
        }
        
        private func saveQueryState(results: [GenericQueryResult], path: String) throws {
            // Shared state model + canonical encoding (DICOMNetwork.QRSessionState)
            // so the app and CLI write byte-identical, mutually-resumable files.
            let data = try QRSessionState.encode(QRQueryState(results: results))
            try data.write(to: URL(fileURLWithPath: path))
        }
        
        private func saveRetrievalState(
            studies: [GenericQueryResult],
            host: String,
            port: UInt16,
            callingAE: String,
            calledAE: String,
            moveDestination: String?,
            method: RetrievalMethod,
            outputPath: String,
            hierarchical: Bool,
            path: String
        ) throws {
            // Shared state model + canonical encoding (DICOMNetwork.QRSessionState).
            let state = QRRetrievalState(
                studies: studies.map(QRStudyInfo.init(from:)),
                host: host,
                port: port,
                callingAE: callingAE,
                calledAE: calledAE,
                moveDestination: moveDestination,
                method: method,
                outputPath: outputPath,
                hierarchical: hierarchical
            )
            let data = try QRSessionState.encode(state)
            try data.write(to: URL(fileURLWithPath: path))
        }
        
        private func validateRetrievedFiles(in directory: String) throws {
            let fileManager = FileManager.default
            let dirURL = URL(fileURLWithPath: directory)
            
            guard let enumerator = fileManager.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                print(NetworkConsole.qrValidateCannotEnumerate(), terminator: "")
                return
            }
            
            var validCount = 0
            var invalidCount = 0
            
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
                
                // Skip non-DICOM files
                guard fileURL.pathExtension.lowercased() == "dcm" || fileURL.pathExtension.isEmpty else {
                    continue
                }
                
                do {
                    let data = try Data(contentsOf: fileURL)
                    _ = try DICOMFile.read(from: data)
                    validCount += 1
                } catch {
                    invalidCount += 1
                    print(NetworkConsole.qrValidateInvalidFile(name: fileURL.lastPathComponent), terminator: "")
                }
            }

            print(NetworkConsole.qrValidateSummary(valid: validCount, invalid: invalidCount), terminator: "")
        }
    }
}

// MARK: - Resume Subcommand

extension DICOMQR {
    struct Resume: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resume",
            abstract: "Resume interrupted retrieval from saved state"
        )
        
        @Option(name: .shortAndLong, help: "Path to saved state file")
        var state: String
        
        @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
        var timeout: Int = 60

        @Option(name: .long, help: "Priority (0000,0700) of each C-MOVE-RQ / C-GET-RQ: low (0002H), medium (0000H), high (0001H) — PS3.7 Tables 9.3-9 / 9.3-6 (default: medium)")
        var priority: QRPriorityOption = .medium
        
        @Flag(name: .long, help: "Show verbose output")
        var verbose: Bool = false
        
        mutating func run() async throws {
            #if canImport(Network)
            print("Loading retrieval state from: \(state)")
            
            let data = try Data(contentsOf: URL(fileURLWithPath: state))
            let retrievalState = try QRSessionState.decodeRetrievalState(data)
            
            print("Resuming retrieval of \(retrievalState.studies.count) studies")
            print("")
            
            // Create retrieve executor from saved state
            let retrieveExecutor = RetrieveExecutor(
                host: retrievalState.host,
                port: retrievalState.port,
                callingAE: retrievalState.callingAE,
                calledAE: retrievalState.calledAE,
                moveDestination: retrievalState.moveDestination,
                timeout: TimeInterval(timeout),
                outputPath: retrievalState.outputPath,
                hierarchical: retrievalState.hierarchical,
                verbose: verbose,
                preferredTransferSyntaxUID: nil,
                priority: priority.dimseValue
            )
            
            var successCount = 0
            var failureCount = 0
            
            for (index, studyInfo) in retrievalState.studies.enumerated() {
                guard let studyUID = studyInfo.studyInstanceUID else {
                    print("[\(index + 1)/\(retrievalState.studies.count)] ⚠️  Missing Study UID")
                    failureCount += 1
                    continue
                }
                
                print("[\(index + 1)/\(retrievalState.studies.count)] Retrieving: \(studyUID)")
                if let patientName = studyInfo.patientName {
                    print("  Patient: \(patientName)")
                }
                
                do {
                    try await retrieveExecutor.retrieveStudy(studyUID: studyUID, method: retrievalState.method)
                    successCount += 1
                    print("  ✅ Success")
                } catch {
                    failureCount += 1
                    print("  ❌ Failed: \(error.localizedDescription)")
                }
                
                print("")
            }
            
            print("Retrieval Summary:")
            print("  Total: \(retrievalState.studies.count)")
            print("  Success: \(successCount)")
            print("  Failed: \(failureCount)")

            // Same exit-code rule as `query`: any failed study exits non-zero.
            if failureCount > 0 {
                throw DICOMQRError.retrievalIncomplete(succeeded: successCount, failed: failureCount)
            }
            #else
            print("Error: Network operations not supported on this platform")
            throw ExitCode(1)
            #endif
        }
    }
}

// MARK: - Helper Types

/// Resolves the final host and port from ``--host`` and ``--port`` options.
private func resolveHostPort(host: String, port: UInt16?) -> (host: String, port: UInt16) {
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

// MARK: - State Types

// The save-state model (QRQueryState / QRRetrievalState / QRStudyInfo), the
// retrieval-method enum, and the GenericQueryResult study accessors were
// hoisted into DICOMNetwork (QRSessionState.swift) so DICOMStudio's Workshop
// reads/writes the SAME format — a state saved on either surface resumes on
// the other. Local names are kept as typealiases.
typealias RetrievalMethod = QRRetrievalMethod

/// The `--priority` values, mapped to the Priority (0000,0700) values of PS3.7
/// Tables 9.3-9 (C-MOVE-RQ) / 9.3-6 (C-GET-RQ): LOW = 0002H, MEDIUM = 0000H,
/// HIGH = 0001H.
enum QRPriorityOption: String, ExpressibleByArgument, CaseIterable {
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

enum DICOMQRError: Error, CustomStringConvertible, LocalizedError {
    case missingMoveDestination
    /// The SCP's final response was not a full success (PS3.4 C.4.2.2.1 / C.4.3.2.1);
    /// `summary` is the shared dicom-retrieve wording (D262).
    case retrievalFailed(summary: String, failedSOPInstanceUIDs: [String])
    /// One or more studies of the run failed; reported after the summary so the
    /// process exits non-zero.
    case retrievalIncomplete(succeeded: Int, failed: Int)
    
    var description: String {
        switch self {
        case .missingMoveDestination:
            return "Move destination AE title is required for C-MOVE retrieval"
        case .retrievalFailed(let summary, _):
            // `summary` is NetworkConsole.retrieveFinalResponse's failure text (D262),
            // which already carries the Failed SOP Instance UID List (0008,0058).
            return summary
        case .retrievalIncomplete(let succeeded, let failed):
            return "Retrieval incomplete: \(succeeded) study(ies) succeeded, \(failed) failed"
        }
    }

    var errorDescription: String? { description }
}

#if canImport(Network)
// Import executor types from dicom-query and dicom-retrieve
// These would normally be in separate files but for CLI tools they're duplicated
struct QueryExecutor {
    let host: String
    let port: UInt16
    let callingAE: String
    let calledAE: String
    let timeout: TimeInterval
    
    func executeQuery(level: QueryLevel, queryKeys: QueryKeys) async throws -> [GenericQueryResult] {
        let configuration = try buildConfiguration(level: level)
        
        return try await DICOMQueryService.find(
            host: host,
            port: port,
            configuration: configuration,
            queryKeys: queryKeys
        )
    }
    
    private func buildConfiguration(level: QueryLevel) throws -> QueryConfiguration {
        let informationModel: QueryRetrieveInformationModel = (level == .patient) ? .patientRoot : .studyRoot
        return QueryConfiguration(
            callingAETitle: try AETitle(callingAE),
            calledAETitle: try AETitle(calledAE),
            timeout: timeout,
            informationModel: informationModel
        )
    }
}

struct RetrieveExecutor {
    let host: String
    let port: UInt16
    let callingAE: String
    let calledAE: String
    let moveDestination: String?
    let timeout: TimeInterval
    let outputPath: String
    let hierarchical: Bool
    let verbose: Bool
    /// Preferred transfer syntax UID for C-GET presentation-context negotiation
    /// (parsed from `--transfer-syntax` via the shared `TransferSyntax.parse`).
    /// C-MOVE is unaffected: the destination SCP negotiates its own contexts.
    let preferredTransferSyntaxUID: String?
    /// Priority (0000,0700) of each C-MOVE-RQ / C-GET-RQ (PS3.7 Tables 9.3-9 / 9.3-6)
    var priority: DIMSEPriority = .medium

    /// Study Root configuration carrying the requested Priority. Relational-retrieval
    /// is not offered: dicom-qr retrieves at STUDY level, where the Identifier
    /// already holds the level's Unique Key (PS3.4 C.4.2.2.1).
    func retrieveConfiguration() throws -> RetrieveConfiguration {
        RetrieveConfiguration(
            callingAETitle: try AETitle(callingAE),
            calledAETitle: try AETitle(calledAE),
            timeout: timeout,
            informationModel: .studyRoot,
            priority: priority
        )
    }

    func retrieveStudy(studyUID: String, method: RetrievalMethod) async throws {
        // Silent per-study retrieval: the calling loop renders the `[i/N] Retrieving…`
        // line and the ✅/❌ outcome via the shared NetworkConsole formatter, so this
        // executor must not print anything of its own (volatile per-instance/progress
        // lines would diverge from the in-app run).
        switch method {
        case .cMove:
            guard let moveDestination = moveDestination else {
                throw DICOMQRError.missingMoveDestination
            }
            let result = try await DICOMRetrieveService.move(
                host: host,
                port: port,
                configuration: try retrieveConfiguration(),
                keys: RetrieveKeys.forStudy(studyUID),
                moveDestination: moveDestination
            )
            // PS3.4 C.4.2.2.1: a failure/warning status or any failed
            // sub-operation is not success; surface counts and the Failed SOP
            // Instance UID List instead of ignoring the result.
            try Self.checkRetrieveResult(result, service: .cMove)
        case .cGet:
            let stream = DICOMRetrieveService.get(
                host: host,
                port: port,
                configuration: try retrieveConfiguration(),
                keys: RetrieveKeys.forStudy(studyUID),
                preferredTransferSyntaxUID: preferredTransferSyntaxUID
            )
            var finalResult: RetrieveResult?
            for await event in stream {
                switch event {
                case .instance(let sopInstanceUID, let sopClassUID, let transferSyntaxUID, let data):
                    try saveInstance(
                        sopInstanceUID: sopInstanceUID,
                        sopClassUID: sopClassUID,
                        transferSyntaxUID: transferSyntaxUID,
                        data: data,
                        studyUID: studyUID
                    )
                case .progress:
                    break
                case .completed(let result):
                    finalResult = result
                case .error(let err):
                    throw err
                }
            }
            // PS3.4 C.4.3.2.1: check the final status and sub-operation counts.
            if let result = finalResult {
                try Self.checkRetrieveResult(result, service: .cGet)
            }
        }
    }

    /// Throws `DICOMQRError.retrievalFailed` unless the result is a full success
    /// (status 0x0000 and no failed sub-operations, PS3.4 C.4.2.2.1 / C.4.3.2.1).
    /// A warning status (0xB000) is therefore a failure for the exit code. The
    /// status is worded per PS3.4 2026a Table C.4-2 (C-MOVE) / C.4-3 (C-GET) and
    /// the counters per PS3.7 Tables 9.3-10 / 9.3-7; the Failed SOP Instance UID
    /// List (0008,0058) and the `Final … response:` line go to stderr first. Lines and
    /// error text are the shared `NetworkConsole.retrieveFinalResponse(_:service:)`,
    /// in dicom-retrieve's wording (D262).
    static func checkRetrieveResult(_ result: RetrieveResult, service: DIMSEStatusService) throws {
        let report = NetworkConsole.retrieveFinalResponse(result, service: service)
        if !report.lines.isEmpty {
            FileHandle.standardError.write(report.lines.map { $0 + "\n" }.joined().data(using: .utf8) ?? Data())
        }
        if let failure = report.failure {
            throw DICOMQRError.retrievalFailed(summary: failure, failedSOPInstanceUIDs: result.failedSOPInstanceUIDs)
        }
    }
    
    // MARK: - File Management
    
    private func saveInstance(
        sopInstanceUID: String,
        sopClassUID: String,
        transferSyntaxUID: String,
        data: Data,
        studyUID: String
    ) throws {
        let fm = FileManager.default
        let filename = "\(sopInstanceUID).dcm"
        let dirPath: String
        
        if hierarchical {
            dirPath = (outputPath as NSString).appendingPathComponent(studyUID)
        } else {
            dirPath = outputPath
        }
        
        try fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        
        let filepath = (dirPath as NSString).appendingPathComponent(filename)
        
        // Wrap the raw dataset in a Part 10 container if it is not already one
        let fileData: Data
        if data.count >= 132,
           data[128] == 0x44, data[129] == 0x49, data[130] == 0x43, data[131] == 0x4D {
            fileData = data
        } else {
            fileData = buildPart10(
                dataset: data,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                transferSyntaxUID: transferSyntaxUID
            )
        }
        try fileData.write(to: URL(fileURLWithPath: filepath), options: .atomic)
    }
    
    // MARK: - Part 10 Wrapper
    
    private func buildPart10(
        dataset: Data,
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String
    ) -> Data {
        func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                                               UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]) }
        func ulElem(_ g: UInt16, _ e: UInt16, _ val: UInt32) -> Data {
            le16(g) + le16(e) + Data([0x55, 0x4C]) + le16(4) + le32(val)
        }
        func obElem(_ g: UInt16, _ e: UInt16, _ val: Data) -> Data {
            le16(g) + le16(e) + Data([0x4F, 0x42, 0x00, 0x00]) + le32(UInt32(val.count)) + val
        }
        func uiElem(_ g: UInt16, _ e: UInt16, _ val: String) -> Data {
            var b = val.data(using: .ascii) ?? Data()
            if b.count % 2 != 0 { b.append(0x00) }
            return le16(g) + le16(e) + Data([0x55, 0x49]) + le16(UInt16(b.count)) + b
        }
        
        var meta = Data()
        meta += obElem(0x0002, 0x0001, Data([0x00, 0x01]))               // File Meta Information Version
        meta += uiElem(0x0002, 0x0002, sopClassUID)                      // Media Storage SOP Class UID
        meta += uiElem(0x0002, 0x0003, sopInstanceUID)                   // Media Storage SOP Instance UID
        meta += uiElem(0x0002, 0x0010, transferSyntaxUID)                // Transfer Syntax UID
        meta += uiElem(0x0002, 0x0012, "1.2.826.0.1.3680043.9.7433.1.1") // Implementation Class UID
        
        var file = Data(repeating: 0, count: 128)                         // 128-byte preamble
        file += Data([0x44, 0x49, 0x43, 0x4D])                            // DICM magic
        file += ulElem(0x0002, 0x0000, UInt32(meta.count))               // File Meta Group Length
        file += meta
        file += dataset
        return file
    }
}
#endif
