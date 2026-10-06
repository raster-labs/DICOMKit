import Foundation
import DICOMCore
import DICOMNetwork
// NEMA-verified: 2026a, checked 2026-10-06 — the three response classes, the per-file ✅ / warning / ❌ lines and the partial-failure text are DICOMNetwork's NetworkConsole.CStoreOutcome / sendFileResult(status:rtt:) / sendStoreFailedText(status:) / sendPartialFailureText (D261; the ❌ line now carries the PS3.4 Table B.2-1 C-STORE wording, e.g. "Failure (0xA700): Refused: Out of resources"); C-STORE response handling diffed against PS3.4 2026a Table B.2-1 (7 rows: Success 0000 stored; Warning B000/B006/B007 stored and reported; Failure A7xx/A9xx/Cxxx not stored, counted as failed) and PS3.7 9.1.1.1.9 (0122 Refused: SOP Class not supported); status text comes from DICOMNetwork.DIMSEStatus; the per-file warning line and the summary Warnings count are rendered by the shared NetworkConsole (Table B.2-1 wording via DIMSEServiceStatusText, P-SEND-SUMMARY)

/// The three PS3.4 Table B.2-1 classes of a C-STORE response are the engine's
/// `NetworkConsole.CStoreOutcome` (D261); this name stays for the DICOMStudio CLI
/// Workshop until it is rewired.
@available(*, deprecated, renamed: "NetworkConsole.CStoreOutcome")
typealias StoreOutcome = NetworkConsole.CStoreOutcome

#if canImport(Network)

/// Executes C-STORE operations to send DICOM files to a PACS server
struct SendExecutor {
    let host: String
    let port: UInt16
    let callingAE: String
    let calledAE: String
    let timeout: TimeInterval
    let priority: DIMSEPriority
    let retryAttempts: Int
    let verbose: Bool
    let preferredTransferSyntaxUID: String?
    
    /// Verifies connection using a real C-ECHO before sending (matches the in-app
    /// dicom-send, which calls the same DICOMVerificationService.echo).
    func verifyConnection() async throws {
        let result = try await DICOMVerificationService.echo(
            host: host, port: port, callingAE: callingAE, calledAE: calledAE, timeout: timeout)
        guard result.success else {
            throw DICOMNetworkError.connectionFailed(
                "C-ECHO verification returned a non-success status: \(result.status)")
        }
    }
    
    /// Sends multiple DICOM files to the PACS server. All progress/summary text is
    /// rendered through the SHARED NetworkConsole formatter (DICOMNetwork) and printed
    /// to STDOUT, so the output is byte-identical to DICOMStudio's in-process send.
    func sendFiles(_ filePaths: [String]) async throws {
        var successCount = 0
        var warningCount = 0
        var failureCount = 0
        var totalBytesTransferred = 0
        let startTime = Date()

        for (index, filePath) in filePaths.enumerated() {
            let fileNumber = index + 1
            let filename = (filePath as NSString).lastPathComponent

            do {
                // Read file data
                let fileURL = URL(fileURLWithPath: filePath)
                let fileData = try Data(contentsOf: fileURL)

                print(NetworkConsole.sendFilePrefix(
                    index: fileNumber, total: filePaths.count,
                    filename: filename, size: fileData.count), terminator: "")
                fflush(stdout)

                // Send with retry logic
                let result = try await sendFileWithRetry(fileData: fileData, filePath: filePath)

                totalBytesTransferred += fileData.count
                successCount += 1

                // The shared formatter renders the Table B.2-1 class of the status
                // (D261): ` ✅ (rtt)`, plus the warning line for the Warning class
                // (stored, but the SCP reports coercion, discarded elements or a
                // SOP Class mismatch).
                print(NetworkConsole.sendFileResult(status: result.status, rtt: result.roundTripTime),
                      terminator: "")
                if NetworkConsole.CStoreOutcome(status: result.status) == .storedWithWarning {
                    warningCount += 1
                }

            } catch {
                failureCount += 1
                print(NetworkConsole.sendFileResultSuffix(
                    success: false, rtt: 0, error: error.localizedDescription), terminator: "")
                // Continue with next file
            }
        }

        // Print final summary
        print(NetworkConsole.sendSummary(
            total: filePaths.count, succeeded: successCount, failed: failureCount,
            bytes: totalBytesTransferred, duration: Date().timeIntervalSince(startTime),
            warnings: warningCount),
            terminator: "")

        if failureCount > 0 {
            throw SendError.partialFailure(succeeded: successCount, failed: failureCount)
        }
    }
    
    /// Sends a single file with retry logic
    private func sendFileWithRetry(fileData: Data, filePath: String) async throws -> StoreResult {
        var lastError: Error?
        
        for attempt in 0...retryAttempts {
            do {
                return try await sendFile(fileData: fileData)
            } catch {
                lastError = error
                
                if attempt < retryAttempts {
                    // No per-attempt chatter: retries are failure-driven and
                    // non-deterministic, so any retry line would diverge between the
                    // CLI and in-app runs. Only the final outcome line is emitted.
                    // Exponential backoff: 1s, 2s, 4s, 8s...
                    let delay = Double(1 << attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? SendError.unknownError
    }
    
    /// Sends a single DICOM file to the PACS server. A response in the Failure
    /// class of PS3.4 Table B.2-1 is thrown as ``SendError/storeFailed(_:)`` so the
    /// retry loop and the per-file tally treat it as a failed transfer (the engine
    /// returns such a response as a `StoreResult` rather than throwing).
    private func sendFile(fileData: Data) async throws -> StoreResult {
        let result = try await storeOnce(fileData: fileData)
        if NetworkConsole.CStoreOutcome(status: result.status) == .failed {
            throw SendError.storeFailed(result.status)
        }
        return result
    }

    private func storeOnce(fileData: Data) async throws -> StoreResult {
        if let preferredTransferSyntaxUID, !preferredTransferSyntaxUID.isEmpty {
            return try await DICOMStorageService.store(
                fileData: fileData,
                preferredTransferSyntaxUID: preferredTransferSyntaxUID,
                to: host,
                port: port,
                callingAE: callingAE,
                calledAE: calledAE,
                priority: priority,
                timeout: timeout
            )
        }

        return try await DICOMStorageService.store(
            fileData: fileData,
            to: host,
            port: port,
            callingAE: callingAE,
            calledAE: calledAE,
            priority: priority,
            timeout: timeout
        )
    }
}

/// Errors that can occur during send operations. The partial-failure text is the
/// shared NetworkConsole one (D261).
enum SendError: LocalizedError {
    case unknownError
    case partialFailure(succeeded: Int, failed: Int)
    /// The SCP answered with a status in the Failure class of PS3.4 Table B.2-1.
    case storeFailed(DIMSEStatus)
    
    var errorDescription: String? {
        switch self {
        case .unknownError:
            return "Unknown error occurred"
        case .partialFailure(let succeeded, let failed):
            return NetworkConsole.sendPartialFailureText(succeeded: succeeded, failed: failed)
        case .storeFailed(let status):
            // The engine's PS3.4 Table B.2-1 wording (D261), the same text
            // NetworkConsole.sendFileResult(status:rtt:) prints after ` ❌ `.
            return NetworkConsole.sendStoreFailedText(status: status)
        }
    }
}

#endif
