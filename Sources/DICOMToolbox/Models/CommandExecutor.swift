import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

// Process/Pipe are available only on platforms that permit subprocesses.
#if os(macOS) || os(Linux)

/// Executes literal argv, drains both output streams, and owns a process until it is reaped.
public actor CommandExecutor {
    public enum ExecutionError: LocalizedError {
        case alreadyRunning
        case invalidArgument
        case executableNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "A command is still running or stopping."
            case .invalidArgument: return "Executable and arguments must not contain a NUL character."
            case .executableNotFound(let name): return "Executable not found: \(name)"
            }
        }
    }

    private var currentRun: ProcessRun?
    public var isRunning: Bool { currentRun != nil }

    public init() {}

    /// Streams stdout/stderr chunks in arrival order. No shell or command-string parser is used.
    @discardableResult
    public func execute(
        invocation: CommandInvocation,
        outputHandler: @Sendable @escaping (String) -> Void
    ) async throws -> Int {
        guard currentRun == nil else { throw ExecutionError.alreadyRunning }
        try Task.checkCancellation()
        guard !invocation.executable.isEmpty,
              !([invocation.executable] + invocation.arguments).contains(where: { $0.contains("\0") }) else {
            throw ExecutionError.invalidArgument
        }
        let url = try Self.executableURL(invocation.executable)
        let run = ProcessRun(executable: url, arguments: invocation.arguments, outputHandler: outputHandler)
        currentRun = run
        defer { currentRun = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.start(continuation)
            }
        } onCancel: {
            run.cancel()
        }
    }

    /// Requests termination; execute remains pending until the process and output readers finish.
    public func cancel() { currentRun?.cancel() }

    private static func executableURL(_ executable: String) throws -> URL {
        let candidates: [URL]
        if executable.contains("/") {
            candidates = [URL(fileURLWithPath: executable)]
        } else {
            let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            candidates = path.split(separator: ":", omittingEmptySubsequences: false).map {
                URL(fileURLWithPath: $0.isEmpty ? FileManager.default.currentDirectoryPath : String($0),
                    isDirectory: true).appendingPathComponent(executable)
            }
        }
        for url in candidates {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
               !directory.boolValue, FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw ExecutionError.executableNotFound(executable)
    }
}

/// Each launch has its own process group, including nested CLI children that inherit its pipes.
/// State shared by pipe readers, waitpid and cancellation is protected by lock.
private final class ProcessRun: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let lock = NSLock()
    private let outputQueue = DispatchQueue(label: "DICOMToolbox.command-output")
    private let outputHandler: @Sendable (String) -> Void
    private var pid: pid_t?
    private var processDone = false
    private var readersRemaining = 2
    private var cancelled = false
    private var shutdownScheduled = false
    private var shutdownComplete = true
    private var finished = false
    private var exitCode = -1
    private var failure: (any Error)?
    private var continuation: CheckedContinuation<Int, any Error>?

    init(executable: URL, arguments: [String], outputHandler: @Sendable @escaping (String) -> Void) {
        self.executable = executable
        self.arguments = arguments
        self.outputHandler = outputHandler
    }

    func start(_ continuation: CheckedContinuation<Int, any Error>) {
        lock.lock()
        self.continuation = continuation
        do {
            if cancelled { throw CancellationError() }
            pid = try spawn()
        } catch {
            failure = error
            processDone = true
        }
        let launchedPID = pid
        lock.unlock()
        // Close parent write ends even on failed launch, so readers can always reach EOF.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        read(stdout.fileHandleForReading)
        read(stderr.fileHandleForReading)
        if let launchedPID {
            DispatchQueue.global().async { [self] in
                var info = siginfo_t()
                var result: Int32
                // Keep the exited leader unreaped until group shutdown/output draining finishes.
                // Its PID cannot then be reused by an unrelated group before escalation.
                repeat { result = waitid(P_PID, id_t(launchedPID), &info, WEXITED | WNOWAIT) }
                while result < 0 && errno == EINTR
                lock.lock()
                if result < 0 {
                    failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECHILD)
                }
                processDone = true
                lock.unlock()
                completeIfReady()
            }
        }
        completeIfReady()
    }

    private func spawn() throws -> pid_t {
        #if os(macOS)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        #endif
        func check(_ code: Int32) throws {
            if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EINVAL) }
        }
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO))
        for handle in [stdout.fileHandleForReading, stderr.fileHandleForReading,
                       stdout.fileHandleForWriting, stderr.fileHandleForWriting] {
            if handle.fileDescriptor > STDERR_FILENO {
                try check(posix_spawn_file_actions_addclose(&actions, handle.fileDescriptor))
            }
        }
        // Establish the group atomically at spawn; parent-side setpgid after exec would race.
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var mask = sigset_t()
        sigemptyset(&mask)
        try check(posix_spawnattr_setsigmask(&attributes, &mask))
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGTERM, SIGINT, SIGQUIT, SIGHUP, SIGPIPE] { sigaddset(&defaults, signal) }
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        var flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
        #if os(macOS)
        flags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
        #endif
        try check(posix_spawnattr_setflags(&attributes, flags))
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let env = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            env.forEach { free($0) }
        }
        var child: pid_t = 0
        let result = argv.withUnsafeBufferPointer { args in
            env.withUnsafeBufferPointer { environment in
                posix_spawn(&child, executable.path, &actions, &attributes,
                            UnsafeMutablePointer(mutating: args.baseAddress!),
                            UnsafeMutablePointer(mutating: environment.baseAddress!))
            }
        }
        try check(result)
        return child
    }

    func cancel() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        cancelled = true
        if let pid, !shutdownScheduled {
            shutdownScheduled = true
            shutdownComplete = false
            _ = kill(-pid, SIGTERM)
            // Retain ownership until the grace period ends, even if the group leader exits first.
            // A nested process may ignore SIGTERM and keep stdout/stderr open.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
                lock.lock()
                _ = kill(-pid, SIGKILL)
                shutdownComplete = true
                lock.unlock()
                completeIfReady()
            }
        }
        lock.unlock()
        completeIfReady()
    }

    private func completeIfReady() {
        lock.lock()
        guard processDone, readersRemaining == 0, shutdownComplete, !finished,
              let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        if let pid {
            var status: Int32 = 0
            var result: pid_t
            repeat { result = waitpid(pid, &status, 0) } while result < 0 && errno == EINTR
            if result < 0 {
                if failure == nil { failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECHILD) }
            } else {
                // POSIX wait status: normal exit in high byte, terminating signal in low 7 bits.
                exitCode = status & 0x7f == 0 ? Int((status >> 8) & 0xff) : Int(status & 0x7f)
            }
        }
        let result: Result<Int, any Error> = failure.map { .failure($0) }
            ?? (cancelled ? .failure(CancellationError()) : .success(exitCode))
        lock.unlock()
        continuation.resume(with: result)
    }

    private func read(_ handle: FileHandle) {
        DispatchQueue.global().async { [self] in
            defer {
                try? handle.close()
                lock.lock()
                readersRemaining -= 1
                lock.unlock()
                completeIfReady()
            }
            var decoder = OutputDecoder()
            do {
                var buffer = [UInt8](repeating: 0, count: 16_384)
                while true {
                    // One POSIX read returns currently available bytes. Foundation's sized read
                    // can wait to fill its entire buffer, delaying prompts until process exit.
                    #if os(macOS)
                    let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
                    #else
                    let count = Glibc.read(handle.fileDescriptor, &buffer, buffer.count)
                    #endif
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    if count == 0 { break }
                    emit(decoder.append(Data(buffer.prefix(count))))
                }
                emit(decoder.finish())
            } catch {
                lock.lock()
                if failure == nil { failure = error }
                lock.unlock()
                cancel()
            }
        }
    }

    private func emit(_ text: String) {
        guard !text.isEmpty else { return }
        outputQueue.sync { outputHandler(text) }
    }
}

/// Keep an incomplete trailing UTF-8 character until the next read; malformed bytes use replacement.
private struct OutputDecoder {
    private var pending = Data()

    mutating func append(_ bytes: Data) -> String {
        pending.append(bytes)
        let all = Array(pending)
        var start = all.count - 1
        while start > 0 && all[start] & 0xC0 == 0x80 { start -= 1 }
        let lead = all[start]
        let length = lead >= 0xC2 && lead <= 0xDF ? 2 :
            (lead >= 0xE0 && lead <= 0xEF ? 3 : (lead >= 0xF0 && lead <= 0xF4 ? 4 : 1))
        let end = length > all.count - start ? start : all.count
        let text = String(decoding: all[..<end], as: UTF8.self)
        pending = Data(all[end...])
        return text
    }

    mutating func finish() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}
#endif
