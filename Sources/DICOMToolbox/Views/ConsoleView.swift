#if canImport(SwiftUI) && os(macOS)
import SwiftUI

/// Console window showing command preview and execution output
public struct ConsoleView: View {
    let toolID: String?
    let parameterValues: [String: String]
    let subcommand: String?
    let networkConfig: NetworkConfigModel
    @Binding var output: String
    @Binding var status: ExecutionStatus
    @Binding var historyEntries: [CommandHistoryEntry]
    let consoleFontSize: Double
    let onCommandCompleted: ((Bool, String) -> Void)?

    @State private var executor = CommandExecutor()
    @State private var showHistory = false
    @State private var runningCommand: String?

    public init(
        toolID: String?,
        parameterValues: [String: String],
        subcommand: String?,
        networkConfig: NetworkConfigModel,
        output: Binding<String>,
        status: Binding<ExecutionStatus>,
        historyEntries: Binding<[CommandHistoryEntry]>,
        consoleFontSize: Double = AppSettings.defaultConsoleFontSize,
        onCommandCompleted: ((Bool, String) -> Void)? = nil
    ) {
        self.toolID = toolID
        self.parameterValues = parameterValues
        self.subcommand = subcommand
        self.networkConfig = networkConfig
        self._output = output
        self._status = status
        self._historyEntries = historyEntries
        self.consoleFontSize = consoleFontSize
        self.onCommandCompleted = onCommandCompleted
    }

    private var commandBuilder: CommandBuilder? {
        guard let toolID, let tool = ToolRegistry.tool(withID: toolID) else {
            return nil
        }
        let config = tool.requiresNetwork ? networkConfig.toNetworkConfig() : nil
        return CommandBuilder(tool: tool, networkConfig: config)
    }

    private var commandString: String {
        if isRunning, let runningCommand { return runningCommand }
        return commandBuilder?.buildCommand(values: parameterValues, subcommand: subcommand) ?? "Select a tool to begin"
    }

    private var isCommandValid: Bool {
        commandBuilder?.isValid(values: parameterValues, subcommand: subcommand) ?? false
    }

    private var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Command preview line
                HStack {
                    Text("$")
                        .font(.system(size: consoleFontSize, design: .monospaced))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    Text(commandString)
                        .font(.system(size: consoleFontSize, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .accessibilityLabel("Command: \(commandString)")

                    Spacer()

                    // History button
                    Button(action: { showHistory.toggle() }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help("Command History")
                    .accessibilityLabel("Command History")
                    .popover(isPresented: $showHistory) {
                        historyPopover
                    }

                    // Copy button
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commandString, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy command to clipboard")
                    .accessibilityLabel("Copy command to clipboard")

                    // Cancel button (shown during execution)
                    if isRunning {
                        Button(action: {
                            Task {
                                await executor.cancel()
                            }
                        }) {
                            Label("Cancel", systemImage: "stop.fill")
                                .foregroundStyle(.red)
                        }
                        .help("Cancel running command")
                        .accessibilityLabel("Cancel running command")
                    }

                    // Execute button
                    Button(action: executeCommand) {
                        Label("Run", systemImage: "play.fill")
                    }
                    .disabled(!isCommandValid || isRunning)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Run command")

                    // Re-run button (shown when there's history)
                    if !historyEntries.isEmpty && !isRunning {
                        Button(action: {
                            if let last = historyEntries.first {
                                rerunEntry(last)
                            }
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Re-run last command")
                        .accessibilityLabel("Re-run last command")
                    }

                    // Status indicator
                    statusIndicator
                }

                Divider()

                // Output area
                ScrollView {
                    if output.isEmpty {
                        Text("Command output will appear here after execution")
                            .font(.system(size: consoleFontSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("No command output yet")
                    } else {
                        Text(output)
                            .font(.system(size: consoleFontSize, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityLabel("Command output")
                    }
                }
                .frame(minHeight: 100, maxHeight: 200)

                // Bottom bar
                HStack {
                    if case .completed(let exitCode) = status {
                        Text("Exit code: \(exitCode)")
                            .font(.caption)
                            .foregroundStyle(exitCode == 0 ? .green : .red)
                            .accessibilityLabel("Exit code \(exitCode), \(exitCode == 0 ? "success" : "failure")")
                    }
                    Spacer()
                    Button("Clear") {
                        output = ""
                        status = .idle
                    }
                    .disabled(output.isEmpty || isRunning)
                    .accessibilityLabel("Clear console output")
                }
            }
            .padding(8)
        }
        .onDisappear { Task { await executor.cancel() } }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed(let exitCode):
            if exitCode == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Command Execution

    private func executeCommand() {
        guard !isRunning, isCommandValid, let toolID, let builder = commandBuilder else { return }
        runInvocation(builder.buildInvocation(values: parameterValues, subcommand: subcommand),
                      toolID: toolID, subcommand: subcommand, values: parameterValues)
    }

    private func runInvocation(_ invocation: CommandInvocation, toolID: String,
                               subcommand: String?, values: [String: String]) {
        output = ""
        runningCommand = invocation.commandString
        status = .running
        let entry = CommandHistoryEntry(
            toolID: toolID,
            subcommand: subcommand,
            parameterValues: values,
            commandString: invocation.commandString,
            invocation: invocation
        )

        Task { @MainActor in
            // Drain queued UI output before publishing the final status/history entry.
            let (stream, continuation) = AsyncStream<String>.makeStream()
            let outputTask = Task { @MainActor in
                for await chunk in stream { output += chunk }
            }
            let exitCode: Int
            let message: String
            do {
                exitCode = try await executor.execute(invocation: invocation) { chunk in
                    continuation.yield(chunk)
                }
                message = exitCode == 0 ? "Command completed successfully" : "Command failed (exit code \(exitCode))"
            } catch is CancellationError {
                exitCode = -1
                message = "Command cancelled"
                continuation.yield("\n[Cancelled]")
            } catch {
                exitCode = -1
                message = "Command error: \(error.localizedDescription)"
                continuation.yield("\nError: \(error.localizedDescription)")
            }
            continuation.finish()
            await outputTask.value
            status = .completed(exitCode: exitCode)
            runningCommand = nil
            CommandHistory.addEntry(entry.withExitCode(exitCode), to: &historyEntries)
            CommandHistory.save(historyEntries)
            onCommandCompleted?(exitCode == 0, message)
        }
    }

    private func rerunEntry(_ entry: CommandHistoryEntry) {
        guard !isRunning else { return }
        guard let invocation = entry.replayInvocation else {
            output = "This history entry has no verified argument list. Select the tool and parameters to run it again."
            status = .completed(exitCode: -1)
            return
        }
        runInvocation(invocation, toolID: entry.toolID, subcommand: entry.subcommand,
                      values: entry.parameterValues)
    }

    // MARK: - History Popover

    @ViewBuilder
    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Command History")
                    .font(.headline)
                Spacer()
                Button("Export as Script") {
                    let script = CommandHistory.exportAsShellScript(historyEntries)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(script, forType: .string)
                }
                .disabled(historyEntries.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if historyEntries.isEmpty {
                Text("No commands in history")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(historyEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let exitCode = entry.exitCode {
                                Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(exitCode == 0 ? .green : .red)
                                    .font(.caption)
                            }
                            Text(entry.displayCommand)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text(entry.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if entry.replayInvocation == nil {
                            Text("Display only — rebuild parameters to run again")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.copyableCommand, forType: .string)
                    }
                }
                .frame(width: 450, height: 300)
            }
        }
    }
}
#endif

