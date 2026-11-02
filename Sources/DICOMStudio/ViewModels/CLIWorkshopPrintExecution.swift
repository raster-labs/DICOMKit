import Foundation
import DICOMPrintCommandSupport
#if canImport(AppKit)
import AppKit
#endif

private enum WorkshopPrintEvent: Sendable {
    case line(String)
    case listener(UInt16?)
    case finished(Int)
}

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension CLIWorkshopViewModel {
    public var isPrintToolSelected: Bool {
        selectedToolID == "dicom-print" || selectedToolID == "dicom-printscp"
    }

    public var printSettingsLocation: String {
        let directory = PrintCommandContext.defaultSettingsDirectory
        if selectedToolID == "dicom-print" {
            return "Printer list: \(directory.appendingPathComponent("printers.json").path). This Workshop list is separate from Print Center and may differ from the terminal's list when the app is sandboxed."
        }
        let explicit = parameterValues.first { $0.parameterID == "scp.ConfigOptions.config" }?.stringValue ?? ""
        let path = explicit.isEmpty ? directory.appendingPathComponent("printscp.json").path : explicit
        return "Settings: \(path). Explicit options override this file. Use Browse to grant access to files and output folders."
    }

    public var printCommandValidationError: String? {
        guard let toolID = selectedToolID, isPrintToolSelected else { return nil }
        do {
            let argv = try CLIWorkshopPrintCommandCodec.arguments(toolID: toolID,
                parameterValues: parameterValues, parameterDefinitions: parameterDefinitions)
            if toolID == "dicom-print" {
                try CLIWorkshopPrintExecutor.validate(arguments: Array(argv.dropFirst()))
            } else {
                try CLIWorkshopPrintSCPExecutor.validate(arguments: Array(argv.dropFirst()))
            }
            return nil
        } catch { return String(describing: error) }
    }

    /// Parses and validates the entire import before replacing any form values.
    public func importPrintCommand(_ command: String) throws {
        guard let toolID = selectedToolID, isPrintToolSelected, !isPrintCommandRunning else {
            throw NSError(domain: "PrintWorkshop", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Select an idle print tool before importing a command."])
        }
        let imported = try CLIWorkshopPrintCommandCodec.importCommand(command, toolID: toolID,
            parameterDefinitions: parameterDefinitions)
        replaceParameterValues(imported)
        securityScopedURLs.removeAll()
    }

    public func stopPrintCommand() {
        guard isPrintCommandRunning else { return }
        printCancellationRequested = true
        printCommandTask?.cancel()
    }

    /// Retains each native file-picker grant independently; the displayed array
    /// contains literal paths and never grants access by itself.
    public func setPrintFileURLs(_ urls: [URL], forParameterID id: String) {
        for key in securityScopedURLs.keys.filter({ $0.hasPrefix(id + "#") }) {
            securityScopedURLs.removeValue(forKey: key)
        }
        for (index, url) in urls.enumerated() { securityScopedURLs[id + "#\(index)"] = url }
        updateParameterValue(parameterID: id, value: CLIWorkshopPrintCommandCodec.encodedList(urls.map(\.path)))
    }

    func executePrintCommand() async {
        guard !isPrintCommandRunning, let toolID = selectedToolID else { return }
        if let error = printCommandValidationError {
            clearConsoleOutput()
            appendConsoleOutput("Cannot run: \(error)\n")
            updateConsoleStatus(.error)
            return
        }
        let argv: [String]
        do {
            argv = try CLIWorkshopPrintCommandCodec.arguments(toolID: toolID,
                parameterValues: parameterValues, parameterDefinitions: parameterDefinitions)
        } catch {
            appendConsoleOutput("Cannot run: \(error)\n")
            updateConsoleStatus(.error)
            return
        }
        let command = argv.map(CommandBuilderHelpers.shellEscape).joined(separator: " ")
        let grantedURLs = Array(securityScopedURLs.values)
        let accessed = grantedURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }
        isPrintCommandRunning = true
        printCancellationRequested = false
        printListenerPort = nil
        clearConsoleOutput()
        updateConsoleStatus(.running)
        appendConsoleOutput("$ \(command)\n\n")

        let (events, continuation) = AsyncStream<WorkshopPrintEvent>.makeStream()
        let context = PrintCommandContext(
            output: { continuation.yield(.line($0)) },
            diagnostic: { continuation.yield(.line($0)) },
            openFile: { url in
                #if canImport(AppKit)
                Task { @MainActor in NSWorkspace.shared.open(url) }
                #endif
            },
            listenerState: { continuation.yield(.listener($0)) })
        let task = Task.detached {
            do {
                try Task.checkCancellation()
                if toolID == "dicom-print" {
                    try await CLIWorkshopPrintExecutor.execute(arguments: Array(argv.dropFirst()), context: context)
                } else {
                    try await CLIWorkshopPrintSCPExecutor.execute(arguments: Array(argv.dropFirst()), context: context)
                }
                continuation.yield(.finished(Task.isCancelled ? 130 : 0))
            } catch is CancellationError {
                continuation.yield(.finished(130))
            } catch {
                continuation.yield(.line("Error: \(error)"))
                continuation.yield(.finished(PrintCommandContext.exitCode(for: error)))
            }
            continuation.finish()
        }
        printCommandTask = task
        var exitCode = 1
        await withTaskCancellationHandler {
            for await event in events {
                switch event {
                case .line(let line): appendConsoleOutput(line + "\n")
                case .listener(let port): printListenerPort = port
                case .finished(let code): exitCode = code
                }
            }
        } onCancel: { task.cancel() }
        await task.value
        if printCancellationRequested { exitCode = 130 }
        if exitCode == 130 { appendConsoleOutput("Stopped by user; the print operation was cancelled.\n") }
        printListenerPort = nil
        printCommandTask = nil
        isPrintCommandRunning = false
        updateConsoleStatus(exitCode == 0 ? .success : .error)
        addToHistory(toolName: toolID, command: command, exitCode: exitCode, output: consoleOutput)
    }
}
