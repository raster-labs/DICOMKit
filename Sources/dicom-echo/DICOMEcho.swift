import Foundation
import ArgumentParser
import DICOMCore
import DICOMNetwork
// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data of its own: every option is plumbing (host, port, AE Titles, count, timeout, stats, diagnose, verbose); the C-ECHO statuses it prints (PS3.7 2026a 9.1.5.1.4: 0000 Success, 0122 Refused: SOP Class not supported, 0210 Duplicate invocation, 0211 Unrecognized operation, 0212 Mistyped argument) are rendered by DICOMNetwork.DIMSEStatus; port 11112 is the registered DICOM port of PS3.8 2026a 9.1.1; AE Titles are PS3.5 Table 6.2-1 VR AE (16 bytes), checked by DICOMNetwork.AETitle

@main
struct DICOMEcho: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-echo",
        abstract: "Test DICOM connectivity using C-ECHO (verification service)",
        discussion: """
            Performs DICOM C-ECHO verification to test connectivity with PACS servers.
            This is the simplest DICOM network operation and is useful for testing
            connectivity, network configuration, and PACS server availability.
            
            The host argument accepts a hostname or IP address, optionally with a
            port suffix (host:port). Use --port to specify the port separately.
            If no port is given, the default is 11112.
            
            Examples:
              dicom-echo server:11112 --aet TEST_SCU
              dicom-echo server --port 11112 --aet TEST_SCU
              dicom-echo server:11112 --aet TEST_SCU --called-aet PACS_SCP
              dicom-echo 192.168.1.100:11112 --aet TEST_SCU --count 10 --stats
              dicom-echo server:11112 --aet TEST_SCU --verbose
              dicom-echo server:11112 --aet TEST_SCU --diagnose
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
    
    @Option(name: .shortAndLong, help: "Number of echo requests to send (default: 1)")
    var count: Int = 1
    
    @Option(name: .long, help: "Connection timeout in seconds (default: 30)")
    var timeout: Int = 30
    
    @Flag(name: .long, help: "Show statistics (min/avg/max round-trip time)")
    var stats: Bool = false
    
    @Flag(name: .long, help: "Run network diagnostics")
    var diagnose: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output including connection details")
    var verbose: Bool = false
    
    mutating func run() async throws {
        #if canImport(Network)
        let serverInfo = resolveHostPort()
        
        // Validate count
        guard count > 0 else {
            throw ValidationError("Count must be greater than 0")
        }
        
        // Verbose header via the SHARED NetworkConsole formatter (DICOMNetwork),
        // printed to STDOUT so the parity harness (which diffs the binary's
        // stdout+stderr against the app) sees identical chrome. Gated on --verbose so
        // plain output stays pipe-friendly — the same convention as dicom-query.
        if verbose {
            emit(NetworkConsole.echoHeader(
                host: serverInfo.host, port: serverInfo.port,
                callingAE: aet, calledAE: calledAet,
                timeout: timeout, count: count))
        }
        
        if diagnose {
            try await runDiagnostics(serverInfo: serverInfo)
        } else {
            try await runEcho(serverInfo: serverInfo)
        }
        
        #else
        throw ValidationError("Network functionality is not available on this platform")
        #endif
    }
    
    #if canImport(Network)
    func runEcho(serverInfo: (host: String, port: UInt16)) async throws {
        var results: [VerificationResult] = []
        var successCount = 0
        var failureCount = 0
        
        for i in 1...count {
            if verbose && count > 1 {
                emit(NetworkConsole.echoProgress(index: i, total: count))
            }

            do {
                let result = try await DICOMVerificationService.echo(
                    host: serverInfo.host,
                    port: serverInfo.port,
                    callingAE: aet,
                    calledAE: calledAet,
                    timeout: TimeInterval(timeout)
                )

                results.append(result)

                if result.success {
                    successCount += 1
                    // Per-echo detail only for a single echo or in verbose mode; a silent
                    // multi-echo run shows one dot per success instead.
                    if verbose || count == 1 {
                        emit(NetworkConsole.echoSuccess(
                            remoteAE: result.remoteAETitle, status: result.status, rtt: result.roundTripTime))
                    } else {
                        emit(NetworkConsole.echoProgressDot())
                        fflush(stdout)
                    }
                } else {
                    failureCount += 1
                    emit(NetworkConsole.echoStatusFailure(status: result.status))
                }

            } catch let netErr as DICOMNetworkError {
                failureCount += 1
                emit(NetworkConsole.echoFailureDetail(
                    netErr, host: serverInfo.host, port: serverInfo.port,
                    callingAE: aet, calledAE: calledAet, timeout: timeout))
            } catch {
                failureCount += 1
                emit(NetworkConsole.echoError(error.localizedDescription))
            }

            // Small delay between requests if count > 1
            if i < count && count > 1 {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        if count > 1 && !verbose {
            emit(NetworkConsole.echoDotsTerminator()) // New line after dots
        }

        // Print summary (multi-echo runs or --stats) via the SHARED formatter.
        if count > 1 || stats {
            emit(NetworkConsole.echoSummary(sent: count, succeeded: successCount, failed: failureCount))
            if stats {
                let roundTripTimes = results.filter { $0.success }.map { $0.roundTripTime }
                emit(NetworkConsole.echoStats(roundTripTimes: roundTripTimes))
            }
        }

        // Exit with appropriate code
        if failureCount > 0 {
            throw ExitCode(1)
        }
    }
    
    func runDiagnostics(serverInfo: (host: String, port: UInt16)) async throws {
        // All diagnostics chrome flows through the SHARED NetworkConsole formatter so
        // the CLI and the Studio panel emit byte-identical output.
        emit(NetworkConsole.echoDiagnoseHeader())

        // Test 1: Basic connectivity
        emit(NetworkConsole.echoDiagnoseTest1Header(host: serverInfo.host, port: serverInfo.port))

        do {
            let result = try await DICOMVerificationService.echo(
                host: serverInfo.host,
                port: serverInfo.port,
                callingAE: aet,
                calledAE: calledAet,
                timeout: TimeInterval(timeout)
            )
            emit(NetworkConsole.echoDiagnoseBasicResult(
                success: result.success, status: result.status, rtt: result.roundTripTime))
        } catch {
            emit(NetworkConsole.echoDiagnoseBasicError(error.localizedDescription))
            throw ExitCode(1)
        }

        // Test 2: Multiple requests for stability
        emit(NetworkConsole.echoDiagnoseTest2Header())
        var stableSuccessCount = 0
        var stableRTTs: [TimeInterval] = []

        for i in 1...5 {
            do {
                let result = try await DICOMVerificationService.echo(
                    host: serverInfo.host,
                    port: serverInfo.port,
                    callingAE: aet,
                    calledAE: calledAet,
                    timeout: TimeInterval(timeout)
                )

                if result.success {
                    stableSuccessCount += 1
                    stableRTTs.append(result.roundTripTime)
                    emit(NetworkConsole.echoDiagnoseStabilitySuccess(index: i, total: 5, rtt: result.roundTripTime))
                } else {
                    emit(NetworkConsole.echoDiagnoseStabilityFailure(index: i, total: 5, status: result.status))
                }
            } catch {
                emit(NetworkConsole.echoDiagnoseStabilityError(index: i, total: 5, message: error.localizedDescription))
            }

            if i < 5 {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms between requests
            }
        }

        emit(NetworkConsole.echoDiagnoseStabilitySummary(
            successes: stableSuccessCount, total: 5, roundTripTimes: stableRTTs))

        // Test 3: Association info
        emit(NetworkConsole.echoDiagnoseAssociationParams())

        // Verdict
        emit(NetworkConsole.echoDiagnoseResult(stabilitySuccesses: stableSuccessCount))

        if stableSuccessCount < 5 {
            throw ExitCode(1)
        }
    }
    #endif

    /// Writes shared-formatter output to STDOUT. The NetworkConsole strings already
    /// carry their own newlines, so no terminator is added.
    func emit(_ text: String) {
        print(text, terminator: "")
    }
    
    /// Resolves the final host and port from ``--host`` and ``--port`` options.
    /// If ``--host`` contains a colon-separated port (e.g. "server:4242"),
    /// that embedded port is used unless ``--port`` is explicitly provided.
    /// Default port is 11112.
    func resolveHostPort() -> (host: String, port: UInt16) {
        var resolvedHost = host
        var resolvedPort: UInt16 = port ?? 11112

        // Strip pacs:// prefix if provided for backward compatibility
        if resolvedHost.hasPrefix("pacs://") {
            resolvedHost = String(resolvedHost.dropFirst(7))
        }

        // Check if host contains embedded port (e.g., "server:4242")
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
