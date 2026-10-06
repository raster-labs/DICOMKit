import Foundation
import DICOMCore
import DICOMNetwork
// NEMA-verified: 2026a, checked 2026-10-06 — final-response lines and error text are NetworkConsole.retrieveFinalResponse (D262; Tables C.4-2 / C.4-3, PS3.7 Table 9.3-10, PS3.6 (0008,0058) re-read); final-status handling checked against PS3.4 2026a Tables C.4-2 / C.4-3 (status wording via DICOMNetwork.DIMSEServiceStatusText, 17 rows, success = 0000 with no failed sub-operations per C.4.2.2.1 / C.4.3.2.1), the four counters against PS3.7 2026a Tables 9.3-7 / 9.3-10, Failed SOP Instance UID List (0008,0058) against C.4.2.1.4.2; the Part 10 wrapper writes the 6 Type 1 rows of PS3.10 2026a Table 7.1-1 (group length, (0002,0001), (0002,0002), (0002,0003), (0002,0010), (0002,0012)) and no Type 3 row; requests built as RetrieveKeys at the level of the most specific UID with the requested Priority (PS3.7 Tables 9.3-9 / 9.3-6) and optional relational-retrieval (PS3.4 Table C.5-3)

#if canImport(Network)

/// Executes C-MOVE and C-GET operations to retrieve DICOM files from a PACS server
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
    let preferredTransferSyntaxUID: String?
    /// Priority (0000,0700) of every C-MOVE-RQ / C-GET-RQ (PS3.7 Tables 9.3-9 / 9.3-6)
    var priority: DIMSEPriority = .medium
    /// Propose relational-retrieval (PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3 byte 1)
    var relationalRetrieval: Bool = false
    
    /// Retrieves a study from PACS
    func retrieveStudy(studyUID: String, method: RetrievalMethod) async throws {
        try await retrieve(studyUID: studyUID, seriesUID: nil, sopUID: nil, method: method)
    }
    
    /// Retrieves a series from PACS (`studyUID` may be nil only with relational-retrieval)
    func retrieveSeries(studyUID: String?, seriesUID: String, method: RetrievalMethod) async throws {
        try await retrieve(studyUID: studyUID, seriesUID: seriesUID, sopUID: nil, method: method)
    }
    
    /// Retrieves an instance from PACS (`studyUID` / `seriesUID` may be nil only with relational-retrieval)
    func retrieveInstance(studyUID: String?, seriesUID: String?, sopUID: String, method: RetrievalMethod) async throws {
        try await retrieve(studyUID: studyUID, seriesUID: seriesUID, sopUID: sopUID, method: method)
    }

    private func retrieve(studyUID: String?, seriesUID: String?, sopUID: String?, method: RetrievalMethod) async throws {
        let keys = Self.retrieveKeys(studyUID: studyUID, seriesUID: seriesUID, sopUID: sopUID)
        switch method {
        case .cMove:
            guard let dest = moveDestination else {
                throw RetrieveError.missingMoveDestination
            }
            try await performCMove(keys: keys, destination: dest)
        case .cGet:
            try await performCGet(keys: keys, studyUID: studyUID, seriesUID: seriesUID)
        }
    }

    /// The Identifier: Query/Retrieve Level from the most specific UID given, and
    /// every UID given (PS3.4 C.4.2.2.1; relational-retrieve allows the
    /// above-level ones to be absent, C.4.2.2.2.1).
    static func retrieveKeys(studyUID: String?, seriesUID: String?, sopUID: String?) -> RetrieveKeys {
        let level: QueryLevel = sopUID != nil ? .image : (seriesUID != nil ? .series : .study)
        var keys = RetrieveKeys(level: level)
        if let studyUID { keys = keys.studyInstanceUID(studyUID) }
        if let seriesUID { keys = keys.seriesInstanceUID(seriesUID) }
        if let sopUID { keys = keys.sopInstanceUID(sopUID) }
        return keys
    }

    /// The engine configuration: Study Root, the requested Priority and, when
    /// asked, the relational-retrieval SOP Class Extended Negotiation.
    func retrieveConfiguration() throws -> RetrieveConfiguration {
        RetrieveConfiguration(
            callingAETitle: try AETitle(callingAE),
            calledAETitle: try AETitle(calledAE),
            timeout: timeout,
            informationModel: .studyRoot,
            priority: priority,
            extendedNegotiation: relationalRetrieval ? RetrieveExtendedNegotiation(relationalRetrieval: true) : nil
        )
    }
    
    /// Retrieves multiple studies in bulk
    func retrieveBulk(studyUIDs: [String], method: RetrievalMethod, parallelism: Int) async throws {
        if verbose {
            fprintln("Bulk retrieving \(studyUIDs.count) studies with parallelism: \(parallelism)")
        }
        
        var successCount = 0
        var failureCount = 0
        
        // Process in batches based on parallelism
        for batch in studyUIDs.chunked(into: parallelism) {
            await withTaskGroup(of: Result<Void, Error>.self) { group in
                for studyUID in batch {
                    group.addTask {
                        do {
                            try await self.retrieveStudy(studyUID: studyUID, method: method)
                            return .success(())
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                
                for await result in group {
                    switch result {
                    case .success:
                        successCount += 1
                    case .failure(let error):
                        failureCount += 1
                        if verbose {
                            fprintln("Failed to retrieve study: \(error)")
                        }
                    }
                }
            }
        }
        
        fprintln("\nBulk retrieval complete:")
        fprintln("  Success: \(successCount)")
        fprintln("  Failed: \(failureCount)")
        
        if failureCount > 0 {
            throw RetrieveError.partialFailure(succeeded: successCount, failed: failureCount)
        }
    }
    
    // MARK: - C-MOVE Implementation
    
    private func performCMove(keys: RetrieveKeys, destination: String) async throws {
        // Intermediate progress is suppressed: the count/cadence of C-MOVE progress
        // messages depends on SCP pacing and differs between two associations, so it
        // can't be compared. Only the deterministic final result is rendered.
        let onProgress: @Sendable (RetrieveProgress) -> Void = { _ in }

        let result = try await DICOMRetrieveService.move(
            host: host,
            port: port,
            configuration: try retrieveConfiguration(),
            keys: keys,
            moveDestination: destination,
            onProgress: onProgress
        )
        
        // C-MOVE result via the SHARED formatter, printed to STDOUT (always).
        print(NetworkConsole.cMoveResult(
            status: DIMSEServiceStatusText.describe(result.status, service: .cMove),
            completed: result.progress.completed,
            failed: result.progress.failed,
            warning: result.progress.warning,
            isSuccess: result.isSuccess), terminator: "")

        // PS3.4 C.4.2.2.1: success means status 0x0000 and no failed
        // sub-operations. Anything else exits non-zero, with the Failed SOP
        // Instance UID List (0008,0058) when the SCP supplied one.
        try Self.checkResult(result, service: .cMove)
    }

    /// Prints failed/warning details to stderr and throws unless `result.isSuccess`.
    /// The status is worded per PS3.4 2026a Table C.4-2 (C-MOVE) or C.4-3 (C-GET)
    /// and the counters per PS3.7 Tables 9.3-10 / 9.3-7.
    /// The lines and the error text are DICOMNetwork's shared
    /// `NetworkConsole.retrieveFinalResponse(_:service:)`, also used by dicom-qr (D262).
    static func checkResult(_ result: RetrieveResult, service: DIMSEStatusService) throws {
        let report = NetworkConsole.retrieveFinalResponse(result, service: service)
        for line in report.lines { fprintln(line) }
        if report.failure == nil { return }
        throw RetrieveError.retrievalFailed(service: service,
                                            status: result.status,
                                            progress: result.progress,
                                            failedSOPInstanceUIDs: result.failedSOPInstanceUIDs)
    }
    
    // MARK: - C-GET Implementation
    
    private func performCGet(keys: RetrieveKeys, studyUID: String?, seriesUID: String?) async throws {
        let stream = DICOMRetrieveService.get(
            host: host,
            port: port,
            configuration: try retrieveConfiguration(),
            keys: keys,
            preferredTransferSyntaxUID: preferredTransferSyntaxUID
        )
        
        var filesReceived = 0
        var finalResult: RetrieveResult?

        for await event in stream {
            switch event {
            case .progress:
                // Suppressed: progress cadence is SCP-dependent and differs run-to-run.
                break

            case .instance(let sopInstanceUID, let sopClassUID, let transferSyntaxUID, let data):
                // Save received instance to disk as a proper Part 10 file. Per-instance
                // lines are NOT printed: the SCP's send order is not guaranteed stable
                // across associations, so they would diff positionally. Only the
                // deterministic received count is reported in the summary.
                try saveInstance(
                    sopInstanceUID: sopInstanceUID,
                    sopClassUID: sopClassUID,
                    transferSyntaxUID: transferSyntaxUID,
                    data: data,
                    studyUID: studyUID,
                    seriesUID: seriesUID
                )
                filesReceived += 1

            case .completed(let result):
                finalResult = result

            case .error(let error):
                throw error
            }
        }

        // C-GET summary via the SHARED formatter (handles the 0-instances warning).
        print(NetworkConsole.cGetSummary(received: filesReceived), terminator: "")

        // PS3.4 C.4.3.2.1: same success rule as C-MOVE.
        if let result = finalResult {
            try Self.checkResult(result, service: .cGet)
        }
    }

    // MARK: - File Management
    
    private func saveInstance(
        sopInstanceUID: String,
        sopClassUID: String,
        transferSyntaxUID: String,
        data: Data,
        studyUID: String?,
        seriesUID: String?
    ) throws {
        let filename = "\(sopInstanceUID).dcm"
        let filepath: String
        // A relational-retrieve by Series/SOP Instance UID alone has no study UID
        // to file under, so recover it from the received data set as for series.
        let effectiveStudyUID = studyUID
            ?? Self.extractUID(element: 0x000D, fromDataSet: data, transferSyntaxUID: transferSyntaxUID)

        // For a study-level C-GET the caller has no series UID, so recover it from the
        // received dataset itself; otherwise --hierarchical would collapse to a flat dump.
        // If it can't be recovered we fall back to flat layout (the prior behavior).
        let effectiveSeriesUID = seriesUID
            ?? Self.extractSeriesUID(fromDataSet: data, transferSyntaxUID: transferSyntaxUID)

        if hierarchical, let series = effectiveSeriesUID, let studyUID = effectiveStudyUID {
            // Organize as study/series/instance
            let studyDir = (outputPath as NSString).appendingPathComponent(studyUID)
            let seriesDir = (studyDir as NSString).appendingPathComponent(series)
            
            // Create directories if needed
            try FileManager.default.createDirectory(
                atPath: seriesDir,
                withIntermediateDirectories: true
            )
            
            filepath = (seriesDir as NSString).appendingPathComponent(filename)
        } else {
            // Flat organization
            filepath = (outputPath as NSString).appendingPathComponent(filename)
        }
        
        // Wrap raw dataset in Part 10 container (preamble + DICM magic + File Meta)
        let part10 = buildPart10(dataset: data, sopClassUID: sopClassUID,
                                  sopInstanceUID: sopInstanceUID,
                                  transferSyntaxUID: transferSyntaxUID)
        try part10.write(to: URL(fileURLWithPath: filepath))
    }
    
    // MARK: - Series UID recovery

    /// Best-effort scan of a raw C-GET dataset for SeriesInstanceUID (0020,000E).
    ///
    /// Handles Explicit and Implicit VR Little Endian (which covers every transfer
    /// syntax a C-GET yields — encapsulated pixel data still uses Explicit VR LE for
    /// the surrounding data set). Returns `nil` on anything it can't confidently parse
    /// (undefined-length sequences, big endian, truncation) so callers fall back to a
    /// flat layout rather than misfiling. Never traps: every read is bounds-checked.
    static func extractSeriesUID(fromDataSet data: Data, transferSyntaxUID: String) -> String? {
        extractUID(element: 0x000E, fromDataSet: data, transferSyntaxUID: transferSyntaxUID)
    }

    /// Best-effort scan for a UID in group 0020 — Study Instance UID (0020,000D)
    /// or Series Instance UID (0020,000E); same rules as ``extractSeriesUID``.
    static func extractUID(element target: UInt16, fromDataSet data: Data, transferSyntaxUID: String) -> String? {
        // Re-base to guarantee 0-based indexing (the dataset may arrive as a slice).
        let bytes = Data(data)
        let implicitVR = (transferSyntaxUID == "1.2.840.10008.1.2")
        // VRs that carry a 2-byte reserved field + 4-byte length in Explicit VR.
        let longFormVRs: Set<String> = ["OB", "OW", "OF", "OD", "OL", "SQ", "UT", "UN", "UC", "UR"]

        var offset = 0
        while offset + 8 <= bytes.count {
            guard let group = bytes.readUInt16LE(at: offset),
                  let element = bytes.readUInt16LE(at: offset + 2) else { return nil }

            // Elements are ordered by (group, element); once we pass the target it's absent.
            if group > 0x0020 || (group == 0x0020 && element > target) { return nil }

            let valueLength: Int
            let valueOffset: Int
            if implicitVR {
                guard let len = bytes.readUInt32LE(at: offset + 4) else { return nil }
                valueLength = Int(len)
                valueOffset = offset + 8
            } else {
                let vr = String(decoding: bytes[offset + 4 ..< offset + 6], as: UTF8.self)
                if longFormVRs.contains(vr) {
                    guard offset + 12 <= bytes.count,
                          let len = bytes.readUInt32LE(at: offset + 8) else { return nil }
                    valueLength = Int(len)
                    valueOffset = offset + 12
                } else {
                    guard let len = bytes.readUInt16LE(at: offset + 6) else { return nil }
                    valueLength = Int(len)
                    valueOffset = offset + 8
                }
            }

            // Undefined length (sequences/encapsulated) — can't skip reliably here.
            if valueLength == 0xFFFF_FFFF { return nil }
            guard valueOffset + valueLength <= bytes.count else { return nil }

            if group == 0x0020 && element == target {
                let raw = bytes[valueOffset ..< valueOffset + valueLength]
                let uid = String(decoding: raw, as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                return uid.isEmpty ? nil : uid
            }

            offset = valueOffset + valueLength
        }
        return nil
    }

    // MARK: - Part 10 file wrapper

    /// Wraps raw C-GET/C-STORE dataset bytes in a DICOM Part 10 container.
    private func buildPart10(dataset: Data,
                              sopClassUID: String,
                              sopInstanceUID: String,
                              transferSyntaxUID: String) -> Data {
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
        meta += obElem(0x0002, 0x0001, Data([0x00, 0x01]))
        meta += uiElem(0x0002, 0x0002, sopClassUID)
        meta += uiElem(0x0002, 0x0003, sopInstanceUID)
        meta += uiElem(0x0002, 0x0010, transferSyntaxUID)
        meta += uiElem(0x0002, 0x0012, DICOMNetworkImplementation.classUID)  // DICOMKit root (D155)

        var file = Data(repeating: 0, count: 128)            // preamble
        file += Data([0x44, 0x49, 0x43, 0x4D])               // DICM
        file += ulElem(0x0002, 0x0000, UInt32(meta.count))   // group length
        file += meta
        file += dataset
        return file
    }
}

// MARK: - Errors

enum RetrieveError: Error, CustomStringConvertible, LocalizedError {
    case missingMoveDestination
    case retrievalFailed(service: DIMSEStatusService, status: DIMSEStatus,
                         progress: RetrieveProgress, failedSOPInstanceUIDs: [String])
    case partialFailure(succeeded: Int, failed: Int)
    
    var description: String {
        switch self {
        case .missingMoveDestination:
            return "C-MOVE requires a move destination AE title"
        case .retrievalFailed(let service, let status, let progress, let uids):
            return NetworkConsole.retrieveFinalResponse(
                RetrieveResult(status: status, progress: progress, failedSOPInstanceUIDs: uids),
                service: service).failure ?? ""
        case .partialFailure(let succeeded, let failed):
            return "Bulk retrieval partially failed: \(succeeded) succeeded, \(failed) failed"
        }
    }

    var errorDescription: String? { description }
}

// MARK: - Utilities

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// Prints to stderr
private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}

#endif
