// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data of its own (SwiftUI for the dicom-validate panel: the level picker shows ValidationHelpers.levelDescription, the IOD popover ValidationHelpers.knownIODs, both verified in ValidationModel.swift; the console text is DICOMKit.ValidationReport's)
// ValidationView.swift
// DICOMStudio
//
// Full UI for dicom-validate — mirrors all CLI options.
// Output format matches dicom-validate Report.renderText() / renderJSON() exactly.

import Foundation

#if canImport(SwiftUI)
import SwiftUI

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct ValidationView: View {
    @Bindable var viewModel: ValidationViewModel

    public init(viewModel: ValidationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HSplitView {
            optionsPanel
                .frame(minWidth: 280, maxWidth: 380)
            outputPanel
                .frame(minWidth: 300)
        }
        .navigationTitle("DICOM Validation")
    }

    // MARK: - Options Panel

    private var optionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inputSection
                levelSection
                iodSection
                optionsSection
                outputSection
                runSection
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Input

    private var inputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Input")
                    .font(.subheadline.bold())
                HStack {
                    TextField("DICOM file or directory path", text: $viewModel.inputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Input path for validation")
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK {
                            viewModel.inputPath = panel.url?.path ?? ""
                            viewModel.inputScopedURL = panel.url
                        }
                    }
                }
                if viewModel.inputPath.isEmpty {
                    Text("Equivalent to: dicom-validate <input>")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Validation Level

    private var levelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Validation Level")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("--level \(viewModel.level)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Picker("Level", selection: $viewModel.level) {
                    ForEach(1...5, id: \.self) { lvl in
                        Text("\(lvl)").tag(lvl)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Validation level selector")

                Text(ValidationHelpers.levelDescription(viewModel.level))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - IOD

    private var iodSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("IOD Override (optional)")
                    .font(.subheadline.bold())
                HStack {
                    TextField("e.g. CTImageStorage", text: $viewModel.iod)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("IOD name for validation")
                    Button {
                        viewModel.showIODPicker.toggle()
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                    .accessibilityLabel("Show known IOD list")
                    .popover(isPresented: $viewModel.showIODPicker) {
                        iodPickerPopover
                    }
                }
                if viewModel.iod.isEmpty {
                    Text("IOD auto-detected from SOP Class UID")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--iod \(viewModel.iod)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var iodPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Known IODs")
                .font(.caption.bold())
                .padding(.horizontal)
                .padding(.top, 8)
            Divider()
            List(viewModel.iodSuggestions, id: \.self) { iodName in
                Button(iodName) {
                    viewModel.iod = iodName
                    viewModel.showIODPicker = false
                }
                .buttonStyle(.plain)
                .font(.caption)
                .accessibilityLabel("Select IOD: \(iodName)")
            }
            .frame(width: 300, height: 280)
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Options")
                    .font(.subheadline.bold())
                Toggle("--detailed  Show full per-file results", isOn: $viewModel.detailed)
                    .accessibilityLabel("Show detailed validation report")
                Toggle("--recursive  Process directories recursively", isOn: $viewModel.recursive)
                    .accessibilityLabel("Process directories recursively")
                Toggle("--strict  Treat warnings as errors (exit 2)", isOn: $viewModel.strict)
                    .accessibilityLabel("Strict mode — warnings treated as errors")
                Toggle("--force  Parse files without DICM prefix", isOn: $viewModel.force)
                    .accessibilityLabel("Force parse files without DICM prefix")
            }
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Output")
                    .font(.subheadline.bold())
                Picker("Format", selection: $viewModel.format) {
                    ForEach(ValidateOutputFormat.allCases, id: \.self) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Output format")
                HStack {
                    TextField("Save to file (optional)", text: $viewModel.outputPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Output file path")
                    Button("Browse") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = viewModel.format == .json
                            ? [.json]
                            : [.plainText]
                        if panel.runModal() == .OK {
                            viewModel.outputPath = panel.url?.path ?? ""
                            viewModel.outputScopedURL = panel.url
                        }
                    }
                }
            }
        }
    }

    // MARK: - Run

    private var runSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // CLI command preview
            GroupBox("CLI Command") {
                Text(viewModel.cliCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack {
                Button {
                    viewModel.runValidation()
                } label: {
                    Label(viewModel.isRunning ? "Validating…" : "Run Validation", systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.inputPath.isEmpty || viewModel.isRunning)
                .accessibilityLabel("Run DICOM validation")

                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Clear") {
                    viewModel.clearOutput()
                }
                .accessibilityLabel("Clear validation output")
                .disabled(viewModel.validationOutput.isEmpty)
            }
        }
    }

    // MARK: - Output Panel

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with status summary
            HStack {
                Label("Output", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                if !viewModel.lastResults.isEmpty {
                    statusBadge
                }
                if !viewModel.runHistory.isEmpty {
                    historyMenu
                }
            }
            .padding()
            Divider()

            // Results list (if multiple files)
            if viewModel.lastResults.count > 1 {
                fileResultsList
                Divider()
            }

            // Raw text output
            ScrollView {
                Text(viewModel.validationOutput.isEmpty ? "Run validation to see results here.\n\nOutput will match dicom-validate CLI output exactly." : viewModel.validationOutput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(viewModel.validationOutput.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var statusBadge: some View {
        let hasErrors = viewModel.lastResults.contains { !$0.errors.isEmpty }
        let hasWarnings = viewModel.lastResults.contains { !$0.warnings.isEmpty }
        let color: Color = hasErrors ? .red : hasWarnings ? .orange : .green
        let label = hasErrors ? "INVALID" : hasWarnings ? "WARNINGS" : "VALID"
        return Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("Validation status: \(label)")
    }

    private var historyMenu: some View {
        Menu {
            ForEach(viewModel.runHistory.prefix(10)) { record in
                Button {
                    viewModel.validationOutput = record.output
                } label: {
                    let fmt = DateFormatter()
                    let _ = { fmt.timeStyle = .short; fmt.dateStyle = .short }()
                    Text("\(fmt.string(from: record.ranAt)) — \(URL(fileURLWithPath: record.inputPath).lastPathComponent)")
                }
            }
            Divider()
            Button("Clear History", role: .destructive) {
                viewModel.clearHistory()
            }
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 80)
        .accessibilityLabel("Validation history")
    }

    private var fileResultsList: some View {
        List(viewModel.lastResults) { result in
            HStack(spacing: 8) {
                Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.isValid ? .green : .red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: result.filePath).lastPathComponent)
                        .font(.body)
                    Text(result.filePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !result.errors.isEmpty {
                    Text("\(result.errors.count) err")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if !result.warnings.isEmpty {
                    Text("\(result.warnings.count) warn")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
            .accessibilityLabel("\(URL(fileURLWithPath: result.filePath).lastPathComponent): \(result.isValid ? "valid" : "invalid"), \(result.errors.count) errors, \(result.warnings.count) warnings")
        }
        .frame(maxHeight: 200)
        .listStyle(.plain)
    }
}
#endif
