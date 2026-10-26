// CLIWorkshopView.swift
// DICOMStudio
//
// DICOM Studio — Interactive CLI tools workshop view

#if canImport(SwiftUI)
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// CLI Workshop view providing an interactive GUI for all DICOMKit
/// command-line tools with command builder, console, and educational features.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct CLIWorkshopView: View {
    @Bindable var viewModel: CLIWorkshopViewModel
    @State private var showFileImporter = false
    @State private var fileImporterParamID: String = ""
    @State private var fileImporterIsDirectory = false
    @State private var showPrintImport = false
    @State private var printImportText = ""
    @State private var printImportError: String?


    /// Tracks which copy button most recently fired, so we can show a transient
    /// "Copied!" confirmation in place of its copy icon. The token guards against
    /// an earlier copy's delayed reset clearing a more recent one.
    @State private var copiedTarget: CopyTarget?
    @State private var copyFeedbackToken = 0
    private enum CopyTarget: Equatable { case command, console }

    public init(viewModel: CLIWorkshopViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Category tabs (File Inspection, File Processing, …)
            tabPicker
            Divider()

            if viewModel.activeTab == .listener {
                // Listener tab: full-width panel, no command/console area
                LocalListenerView(viewModel: viewModel)
            } else {
                // Tools shown as a horizontal tab row, like the categories above
                toolTabBar
                Divider()
                // Parameters/filters on the LEFT, command preview + console on the RIGHT.
                // Keep the combined minimum modest so the panel doesn't force itself
                // wider than the window — otherwise the top tab rows overflow and the
                // rightmost tabs get clipped with no way to scroll to them.
                //
                // The split is wrapped in a GeometryReader and pinned to an EXACT
                // height (`geo.size.height`) — NOT `maxHeight: .infinity`. HSplitView
                // is backed by NSSplitView, which sizes to the fitting height of its
                // tallest pane. When the "Compare CLI" result (a tall VStack of
                // ScrollViews) appears in the right pane, NSSplitView re-measures the
                // changed subtree with an UNBOUNDED height proposal — under which
                // `maxHeight: .infinity` resolves to the full content height, not the
                // window height. The split then grows past the window and the left
                // pane's pinned Run button is pushed off-screen until a tab switch
                // forces a full rebuild (hence the recurring "Run disappears after
                // Compare" bug). A definite height proposal removes the ambiguity: the
                // panes are bounded, their inner ScrollViews scroll, and the split can
                // never exceed the window — so Run stays pinned and visible.
                GeometryReader { geo in
                    HSplitView {
                        upperPanel
                            .frame(minWidth: 240, idealWidth: 380, maxWidth: 620, maxHeight: .infinity)
                        lowerPanel
                            .frame(minWidth: 260, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { viewModel.stopPrintCommand() }
        #if canImport(AppKit)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.stopPrintCommand()
        }
        #endif
        .sheet(isPresented: $showPrintImport) { printImportSheet }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var printImportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Print Command").font(.headline)
            Text("Paste a command for the selected print tool. Import updates the form without running it. Use Browse afterwards when file access is needed.")
                .font(.callout)
            TextEditor(text: $printImportText).font(.body.monospaced())
                .frame(minHeight: 120).accessibilityLabel("Print command to import")
            if let error = printImportError { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Cancel") { showPrintImport = false }
                Spacer()
                Button("Import") {
                    do {
                        try viewModel.importPrintCommand(printImportText)
                        showPrintImport = false
                    } catch { printImportError = String(describing: error) }
                }.disabled(printImportText.isEmpty)
            }
        }.padding().frame(width: 600)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        // Wrap categories to multiple lines (same as the tool tabs) so none get
        // hidden regardless of window width.
        FlowLayout(spacing: 6) {
            ForEach(CLIWorkshopTab.allCases) { tab in
                categoryTab(tab)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.gray.opacity(0.06))
    }

    /// A single category tab — accent-tinted card when selected.
    private func categoryTab(_ tab: CLIWorkshopTab) -> some View {
        let selected = viewModel.activeTab == tab
        return Button {
            // Switch category AND refresh the selection to the new category's
            // first tool (clears stale form/preview/console).
            viewModel.selectCategory(tab)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.displayName)
                        .font(.body.weight(selected ? .semibold : .regular))
                    Text(tab.tabDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.displayName)
        .accessibilityHint(tab.tabDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Tool Tab Bar

    /// Tools for the active category, shown as a horizontal tab row (styled like
    /// the category tabs). A tooltip carries each tool's description, and the
    /// experience-mode toggle sits at the trailing edge.
    private var toolTabBar: some View {
        let tools = viewModel.toolsForActiveTab()
        return HStack(alignment: .top, spacing: 8) {
            if tools.isEmpty {
                Text("No tools available for this category")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                Spacer()
            } else {
                // Wrap tools to multiple lines so none ever get hidden, regardless
                // of window width (replaces the horizontal scroll that could clip).
                FlowLayout(spacing: 6) {
                    ForEach(tools, id: \.id) { tool in
                        toolTab(tool)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            experienceToggleButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.gray.opacity(0.04))
    }

    /// A single tool "pill" tab — filled accent when selected.
    private func toolTab(_ tool: CLIToolDefinition) -> some View {
        let selected = viewModel.selectedToolID == tool.id
        return Button {
            viewModel.selectTool(id: tool.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .foregroundStyle(selected ? Color.white : .green)
                Text(tool.name)
                    .font(.callout.monospaced().weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? Color.accentColor : Color.gray.opacity(0.15))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tool.briefDescription)
        .accessibilityLabel(tool.name)
        .accessibilityHint(tool.briefDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Beginner/Advanced toggle, pinned at the trailing edge of the tool tab bar.
    private var experienceToggleButton: some View {
        Button {
            viewModel.toggleExperienceMode()
        } label: {
            Label(
                viewModel.experienceMode == .beginner ? "Beginner" : "Advanced",
                systemImage: viewModel.experienceMode == .beginner ? "graduationcap" : "wrench.and.screwdriver"
            )
            .font(.callout)
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .help("Toggle between Beginner and Advanced parameter sets")
        .accessibilityLabel("Toggle experience mode")
    }

    // MARK: - Left Panel (filters) & Right Panel (output)
    //
    // The left/right split is provided by the `HSplitView` in `body` (its
    // divider is draggable). `upperPanel` is the left-hand parameters/filters
    // panel; `lowerPanel` is the right-hand command-preview + console panel.

    /// Left panel — tool purpose header, server selector, and parameter fields
    /// (scrollable), with the Run / Compare action buttons pinned at the bottom.
    private var upperPanel: some View {
        Group {
            if let tool = viewModel.selectedTool() {
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            toolPurposeHeader(tool: tool)
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                if viewModel.isPrintToolSelected {
                                    Text(viewModel.printSettingsLocation)
                                        .font(.callout).textSelection(.enabled)
                                    Button("Import Command") {
                                        printImportText = ""
                                        printImportError = nil
                                        showPrintImport = true
                                    }.disabled(viewModel.isPrintCommandRunning)
                                }
                                if viewModel.isNetworkToolSelected && !viewModel.isPrintToolSelected {
                                    if viewModel.isDICOMwebToolSelected {
                                        dicomwebServerSelectionSection
                                    } else {
                                        serverSelectionSection
                                    }
                                    Divider()
                                }

                                Text("Parameters")
                                    .font(.title3.bold())

                                parameterGrid.disabled(viewModel.isPrintCommandRunning)
                            }
                            .padding()
                        }
                    }

                    Divider()
                    actionFooter
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Select a tool from the tabs above")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Run button pinned at the bottom of the filters panel (after all filters).
    /// (The TESTING-ONLY "Compare CLI" button lives at the top of the right panel.)
    private var actionFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = viewModel.executionUnavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if viewModel.isCommandValid {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .help("Command is valid")
                }
                Spacer()
                if viewModel.isPrintCommandRunning {
                    if let port = viewModel.printListenerPort {
                        Text("Listening on port \(port)").font(.callout)
                    }
                    Button(viewModel.printCancellationRequested ? "Stopping…" : "Stop") {
                        viewModel.stopPrintCommand()
                    }.disabled(viewModel.printCancellationRequested)
                    .accessibilityLabel("Stop print command")
                }

                Button {
                    Task { await viewModel.executeCommand() }
                } label: {
                    Label(viewModel.runActionTitle, systemImage: "play.fill")
                        .font(.body)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isCommandValid || viewModel.consoleStatus == .running)
                .accessibilityLabel(viewModel.runActionTitle + " command")
                .accessibilityHint(viewModel.executionUnavailableReason ?? "Runs the selected Workshop action")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Right panel — command preview, console output, and history (scrollable console).
    private var lowerPanel: some View {
        VStack(spacing: 0) {
            // Command Preview (pinned at top of lower half)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Command Preview")
                            .font(.headline.bold())
                        if viewModel.isCommandValid {
                            Label("Valid", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                    }

                    HStack {
                        Text("$")
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 0.0))
                        Text(viewModel.commandPreview.isEmpty ? "Select a tool to build a command" : viewModel.commandPreview)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(viewModel.commandPreview.isEmpty ? Color(white: 0.5) : Color(white: 0.9))
                            .textSelection(.enabled)
                        Spacer()
                        if !viewModel.commandPreview.isEmpty {
                            Button {
                                copyCommandToClipboard()
                            } label: {
                                if copiedTarget == .command {
                                    Label("Copied!", systemImage: "checkmark.circle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "doc.on.doc")
                                        .font(.body)
                                        .foregroundStyle(Color(white: 0.6))
                                }
                            }
                            .buttonStyle(.borderless)
                            .help("Copy command to clipboard")
                            .accessibilityLabel(copiedTarget == .command ? "Command copied" : "Copy command")
                            .accessibilityHint("Copies the command to the clipboard")
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Console header
            HStack {
                Label("Console", systemImage: "terminal")
                    .font(.headline.bold())
                Spacer()

                consoleStatusBadge

                if !viewModel.consoleOutput.isEmpty {
                    Button {
                        copyConsoleToClipboard()
                    } label: {
                        if copiedTarget == .console {
                            Label("Copied!", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.body)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Copy console output to clipboard")
                    .accessibilityLabel(copiedTarget == .console ? "Console output copied" : "Copy console output")
                    .accessibilityHint("Copies the console output to the clipboard")
                }

                if !viewModel.lastRetrievedFiles.isEmpty {
                    Button {
                        viewModel.openRetrievedFileInViewer()
                    } label: {
                        Label("Open in Viewer", systemImage: "eye")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Open retrieved file in viewer")
                    .accessibilityHint("Opens the first retrieved DICOM file in the image viewer")
                }

                Button("Clear") {
                    viewModel.clearConsoleOutput()
                }
                .font(.body)
                .disabled(viewModel.consoleOutput.isEmpty)
                .accessibilityLabel("Clear console output")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // Console body (scrollable, fills remaining space)
            if viewModel.consoleOutput.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Console output will appear here")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(viewModel.consoleOutput)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(.black.opacity(0.05))
            }

            // History bar
            if !viewModel.commandHistory.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("History")
                            .font(.body.bold())
                        Spacer()
                        Button("Clear") { viewModel.clearHistory() }
                            .font(.body)
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.commandHistory.suffix(10), id: \.id) { entry in
                                Text(entry.toolName)
                                    .font(.callout.monospaced())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(entry.exitCode == 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    // MARK: - Tool Purpose Header

    /// A card displayed at the top of the command panel explaining what the selected tool does.
    private func toolPurposeHeader(tool: CLIToolDefinition) -> some View {
        let purpose = ToolCatalogHelpers.toolPurposeDescription(for: tool.id)
        let capabilities = ToolCatalogHelpers.toolCapabilities(for: tool.id)

        return VStack(alignment: .leading, spacing: 10) {
            // Tool name row
            HStack(spacing: 10) {
                Image(systemName: tool.sfSymbol)
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 32, height: 32)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tool.name)
                            .font(.title3.monospaced().bold())
                        if !tool.dicomStandardRef.isEmpty {
                            Text(tool.dicomStandardRef)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(tool.briefDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Purpose paragraph (only shown when a rich description is available)
            if !purpose.isEmpty {
                Text(purpose)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Capability pills (only shown when available)
            if !capabilities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(capabilities, id: \.self) { cap in
                            Label(cap, systemImage: "checkmark")
                                .font(.callout)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.displayName). \(purpose)")
    }

    // MARK: - Parameter Input Views

    /// Parameter grid (no scroll — parent handles scrolling).
    private var parameterGrid: some View {
        let params = viewModel.visibleParameters()
        // In Beginner mode, advanced flags are surfaced in a collapsible section
        // (instead of being hidden) so every available flag stays reachable.
        let advanced = viewModel.advancedParameters()
        return Group {
            if params.isEmpty && advanced.isEmpty {
                Text("No configurable parameters")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !params.isEmpty { parameterSections(params) }
                    if !advanced.isEmpty {
                        DisclosureGroup {
                            parameterSections(advanced)
                                .padding(.top, 8)
                        } label: {
                            Label("Advanced options (\(advanced.count))", systemImage: "slider.horizontal.3")
                                .font(.headline)
                        }
                        .accessibilityHint("Shows additional flags for this tool")
                    }
                }
            }
        }
    }

    /// Groups a parameter list into Input / Parameters / Options / Output cards,
    /// each in a titled rounded section (booleans render as checkbox rows).
    @ViewBuilder
    private func parameterSections(_ params: [CLIParameterDefinition]) -> some View {
        let input   = params.filter { $0.parameterType == .filePath }
        let output  = params.filter { $0.parameterType == .outputPath }
        let options = params.filter { $0.parameterType == .booleanToggle }
        let main    = params.filter {
            $0.parameterType != .filePath && $0.parameterType != .outputPath && $0.parameterType != .booleanToggle
        }
        VStack(alignment: .leading, spacing: 14) {
            if !input.isEmpty {
                filterSection("Input") { ForEach(input, id: \.id) { valueParameterRow($0) } }
            }
            if !main.isEmpty {
                filterSection("Parameters") { ForEach(main, id: \.id) { valueParameterRow($0) } }
            }
            if !options.isEmpty {
                filterSection("Options") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(options, id: \.id) { booleanCheckboxRow($0) }
                    }
                }
            }
            if !output.isEmpty {
                filterSection("Output") { ForEach(output, id: \.id) { valueParameterRow($0) } }
            }
        }
    }

    /// A titled, lightly-tinted rounded section card.
    @ViewBuilder
    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    /// A value-bearing parameter: bold label + flag hint, the control, and help text.
    @ViewBuilder
    private func valueParameterRow(_ param: CLIParameterDefinition) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(param.displayName)
                    .font(.body.weight(.semibold))
                Spacer()
                if !param.flag.isEmpty {
                    Text(param.flag)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            controlForParameter(param)
            if !param.helpText.isEmpty {
                Text(param.helpText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The input control for a non-boolean parameter.
    @ViewBuilder
    private func controlForParameter(_ param: CLIParameterDefinition) -> some View {
        if viewModel.isPrintToolSelected && param.isRepeatable {
            CLIWorkshopPrintListField(rawValue: parameterBinding(for: param.id), label: param.displayName,
                isFileList: param.id == "paths" || param.id == "scp.SimulateCommand.paths") { urls in
                    viewModel.setPrintFileURLs(urls, forParameterID: param.id)
                }
        } else if (param.parameterType == .enumPicker || param.parameterType == .flagPicker || (param.parameterType == .subcommand && !param.allowedValues.isEmpty)) && !param.allowedValues.isEmpty {
            enumPickerField(param: param)
        } else if param.parameterType == .filePath || param.parameterType == .outputPath {
            filePathField(param: param)
        } else {
            TextField(param.placeholder, text: parameterBinding(for: param.id))
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .accessibilityLabel(param.displayName)
        }
    }

    /// A boolean flag as a checkbox row: ☑ --flag  description.
    @ViewBuilder
    private func booleanCheckboxRow(_ param: CLIParameterDefinition) -> some View {
        let isOn = Binding<Bool>(
            get: {
                let val = viewModel.parameterValues.first(where: { $0.parameterID == param.id })?.stringValue ?? "false"
                return val == "true"
            },
            set: { newValue in
                viewModel.updateParameterValue(parameterID: param.id, value: newValue ? "true" : "false")
            }
        )
        if viewModel.isPrintToolSelected {
            CLIWorkshopPrintOptionCheckbox(parameter: param, isOn: isOn)
        } else {
            Toggle(isOn: isOn) {
                HStack(spacing: 8) {
                    if !param.flag.isEmpty {
                        Text(param.flag)
                            .font(.body.monospaced().weight(.semibold))
                    }
                    Text(param.helpText.isEmpty ? param.displayName : param.helpText)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            .accessibilityLabel(param.displayName)
        }
    }

    /// A file/directory path field with a Browse button and file importer.
    private func filePathField(param: CLIParameterDefinition) -> some View {
        HStack(spacing: 4) {
            TextField(param.placeholder, text: parameterBinding(for: param.id))
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .accessibilityLabel(param.displayName)
            Button {
                fileImporterParamID = param.id
                fileImporterIsDirectory = (param.parameterType == .outputPath)
                showFileImporter = true
            } label: {
                Label("Browse", systemImage: "folder")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Browse for \(param.displayName)")
            .accessibilityHint("Opens a file picker dialog")
        }
        .fileImporter(
            isPresented: Binding(
                get: { showFileImporter && fileImporterParamID == param.id },
                set: { newValue in
                    if !newValue { showFileImporter = false }
                }
            ),
            allowedContentTypes: param.parameterType == .outputPath ? [.folder] : [.data, .folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Store the security-scoped URL for later file access
                    viewModel.setSecurityScopedURL(url, forParameterID: param.id)
                    // Save State File is a single JSON file, but the Browse dialog for
                    // .outputPath fields can only grant a folder (see fileImporterIsDirectory
                    // below) — without this, the field would display the bare folder path
                    // and --save-state would be handed a directory instead of a file to write.
                    // Append the placeholder filename so the field shows a complete path.
                    if param.id == "save-state" {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                            let filePath = url.appendingPathComponent(param.placeholder).path
                            viewModel.updateParameterValue(parameterID: param.id, value: filePath)
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }

    /// A picker that offers preset values — segmented for small sets, menu otherwise.
    @ViewBuilder
    private func enumPickerField(param: CLIParameterDefinition) -> some View {
        let values = param.allowedValues
        // The six Print client commands have long names (for example,
        // "remove-printer"). NSSegmentedControl keeps their combined intrinsic
        // width even when the split pane is narrow, widening the entire scroll
        // document and clipping unrelated fields and checkboxes. Keep command
        // selection in a native menu; short value choices retain their segments.
        let printCommand = viewModel.isPrintToolSelected && param.parameterType == .subcommand
        let useSegmented = !printCommand && values.count >= 2 && values.count <= 6 && !values.contains("")
        let picker = Picker("", selection: parameterBinding(for: param.id)) {
            ForEach(values, id: \.self) { value in
                Text(value.isEmpty ? "Any" : value).tag(value)
            }
        }
        .labelsHidden()
        .font(.body)
        .accessibilityLabel(param.displayName)

        if useSegmented {
            picker.pickerStyle(.segmented)
        } else {
            picker.pickerStyle(.menu)
        }
    }

    // MARK: - Server Selection

    /// Server selection section with saved servers list, add/save buttons.
    private var serverSelectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Server", systemImage: "server.rack")
                    .font(.headline.bold())
                Spacer()
                Button {
                    // Pre-fill from current parameters
                    let host = viewModel.parameterValues.first(where: { $0.parameterID == "host" })?.stringValue ?? ""
                    let port = viewModel.parameterValues.first(where: { $0.parameterID == "port" })?.stringValue ?? "11112"
                    let calledAET = viewModel.parameterValues.first(where: { $0.parameterID == "called-aet" })?.stringValue ?? ""
                    let callingAET = viewModel.parameterValues.first(where: { $0.parameterID == "aet" })?.stringValue ?? "DICOMSTUDIO"
                    viewModel.newServerHost = host
                    viewModel.newServerPort = port
                    viewModel.newServerCalledAET = calledAET
                    viewModel.newServerCallingAET = callingAET
                    viewModel.newServerName = host.isEmpty ? "" : "\(calledAET)@\(host)"
                    viewModel.showAddServerSheet = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add new server")

                Button {
                    viewModel.saveCurrentServerAsDefault()
                } label: {
                    Label("Save as Default", systemImage: "star")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Save current server as default")
                .accessibilityHint("Persists hostname, port, and AE titles as defaults for all network tools")
            }

            if viewModel.savedServerProfiles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No saved servers. Enter parameters manually or add a server.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                // Wrap the server chips onto multiple rows (FlowLayout) so none get hidden
                // off-screen when several servers are added — replaces a horizontal
                // ScrollView that pushed the extra chips out of view.
                FlowLayout(spacing: 6) {
                        // "Manual" chip to deselect any server
                        Button {
                            viewModel.selectedSavedServerID = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 11))
                                Text("Manual")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.selectedSavedServerID == nil ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(
                                    viewModel.selectedSavedServerID == nil ? Color.accentColor.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use manual server entry")

                        ForEach(viewModel.savedServerProfiles) { server in
                            let isSelected = viewModel.selectedSavedServerID == server.id
                            Button {
                                viewModel.applySavedServer(id: server.id)
                            } label: {
                                HStack(spacing: 4) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(server.name)
                                            .font(.caption.bold())
                                        Text("\(server.host):\(server.port)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).stroke(
                                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    viewModel.beginEditServer(id: server.id)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    viewModel.removeSavedServer(id: server.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .accessibilityLabel("Select server \(server.name)")
                            .accessibilityHint("\(server.host) port \(server.port)")
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $viewModel.showAddServerSheet) {
            serverFormSheet(isEditing: false)
        }
        .sheet(isPresented: $viewModel.showEditServerSheet) {
            serverFormSheet(isEditing: true)
        }
    }

    /// Sheet for adding or editing a PACS server profile.
    private func serverFormSheet(isEditing: Bool) -> some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Server" : "Add Server")
                .font(.headline)

            Form {
                TextField("Server Name", text: $viewModel.newServerName)
                    .accessibilityLabel("Server name")
                TextField("Hostname / IP", text: $viewModel.newServerHost)
                    .accessibilityLabel("Hostname")
                TextField("Port", text: $viewModel.newServerPort)
                    .accessibilityLabel("Port")
                TextField("Called AE Title", text: $viewModel.newServerCalledAET)
                    .accessibilityLabel("Called AE Title")
                TextField("Calling AE Title", text: $viewModel.newServerCallingAET)
                    .accessibilityLabel("Calling AE Title")
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    if isEditing {
                        viewModel.showEditServerSheet = false
                        viewModel.editingServerID = nil
                    } else {
                        viewModel.showAddServerSheet = false
                    }
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    if isEditing {
                        viewModel.saveEditedServer()
                    } else {
                        viewModel.addNewServerFromForm()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.newServerName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    viewModel.newServerHost.trimmingCharacters(in: .whitespaces).isEmpty ||
                    viewModel.newServerCalledAET.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320)
    }

    // MARK: - DICOMweb Server Selection

    /// Server selection header and profile chips for DICOMweb tools.
    private var dicomwebServerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("DICOMweb Server", systemImage: "globe")
                    .font(.headline.bold())
                Spacer()
                Button {
                    let url = viewModel.parameterValues.first(where: { $0.parameterID == "url" })?.stringValue ?? ""
                    viewModel.newDICOMwebServerName = url.isEmpty ? "" : (URL(string: url)?.host ?? url)
                    viewModel.newDICOMwebServerURL = url
                    viewModel.showAddDICOMwebServerSheet = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add new DICOMweb server")

                Button {
                    viewModel.saveDICOMwebServerAsDefault()
                } label: {
                    Label("Save as Default", systemImage: "star")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Save current DICOMweb server as default")
                .accessibilityHint("Persists base URL and authentication as defaults for all DICOMweb tools")
            }

            if viewModel.savedDICOMwebProfiles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No saved DICOMweb servers. Enter the base URL manually or add a server.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                // Wrap the server chips onto multiple rows (FlowLayout) so none get hidden
                // off-screen when several servers are added — replaces a horizontal
                // ScrollView that pushed the extra chips out of view.
                FlowLayout(spacing: 6) {
                        // "Manual" chip to deselect any server
                        Button {
                            viewModel.selectedDICOMwebServerID = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 11))
                                Text("Manual")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.selectedDICOMwebServerID == nil ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(
                                    viewModel.selectedDICOMwebServerID == nil ? Color.accentColor.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use manual DICOMweb server entry")

                        ForEach(viewModel.savedDICOMwebProfiles) { server in
                            let isSelected = viewModel.selectedDICOMwebServerID == server.id
                            Button {
                                viewModel.applySavedDICOMwebServer(id: server.id)
                            } label: {
                                HStack(spacing: 4) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(server.name)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Text(server.baseURL)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .truncationMode(.middle)
                                    }
                                    .frame(maxWidth: 260, alignment: .leading)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).stroke(
                                        isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    viewModel.beginEditDICOMwebServer(id: server.id)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    viewModel.removeSavedDICOMwebServer(id: server.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .accessibilityLabel("Select DICOMweb server \(server.name)")
                            .accessibilityHint(server.baseURL)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $viewModel.showAddDICOMwebServerSheet) {
            dicomwebServerFormSheet(isEditing: false)
        }
        .sheet(isPresented: $viewModel.showEditDICOMwebServerSheet) {
            dicomwebServerFormSheet(isEditing: true)
        }
    }

    /// Sheet for adding or editing a DICOMweb server profile.
    private func dicomwebServerFormSheet(isEditing: Bool) -> some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit DICOMweb Server" : "Add DICOMweb Server")
                .font(.headline)

            Form {
                TextField("Server Name", text: $viewModel.newDICOMwebServerName)
                    .accessibilityLabel("Server name")
                TextField("Base URL", text: $viewModel.newDICOMwebServerURL)
                    .accessibilityLabel("Base URL")
                    .accessibilityHint("Full DICOMweb base URL including protocol, e.g. https://pacs.hospital.com/dicom-web")
                Picker("Authentication", selection: $viewModel.newDICOMwebAuthMethod) {
                    Text("None").tag("none")
                    Text("Basic").tag("basic")
                    Text("Bearer Token").tag("bearer")
                }
                .accessibilityLabel("Authentication method")
                if viewModel.newDICOMwebAuthMethod == "basic" {
                    TextField("Username", text: $viewModel.newDICOMwebUsername)
                        .accessibilityLabel("Username")
                    SecureField("Password", text: $viewModel.newDICOMwebToken)
                        .accessibilityLabel("Password")
                } else if viewModel.newDICOMwebAuthMethod == "bearer" {
                    SecureField("Bearer Token", text: $viewModel.newDICOMwebToken)
                        .accessibilityLabel("Bearer token")
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    if isEditing {
                        viewModel.showEditDICOMwebServerSheet = false
                        viewModel.editingDICOMwebServerID = nil
                    } else {
                        viewModel.showAddDICOMwebServerSheet = false
                    }
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    if isEditing {
                        viewModel.saveEditedDICOMwebServer()
                    } else {
                        viewModel.addNewDICOMwebServerFromForm()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.newDICOMwebServerName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    viewModel.newDICOMwebServerURL.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320)
    }

    /// Picker for choosing from saved Networking server profiles.
    private var savedServerPicker: some View {
        Group {
            if viewModel.savedServerProfiles.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No saved servers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Add servers in the Networking tab first.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.savedServerProfiles) { server in
                            Button {
                                viewModel.applySavedServer(id: server.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.caption.bold())
                                            .foregroundStyle(.primary)
                                        Text("\(server.host):\(server.port)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                        Text("AE: \(server.remoteAETitle)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if viewModel.selectedSavedServerID == server.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(8)
                                .background(
                                    viewModel.selectedSavedServerID == server.id
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            viewModel.selectedSavedServerID == server.id
                                                ? Color.accentColor.opacity(0.4)
                                                : Color.secondary.opacity(0.2),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select server \(server.name)")
                            .accessibilityHint("\(server.host) port \(server.port)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var consoleStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(consoleStatusColor)
                .frame(width: 6, height: 6)
            Text(viewModel.consoleStatus.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var consoleStatusColor: Color {
        switch viewModel.consoleStatus {
        case .idle: return .gray
        case .running: return .green
        case .success: return .blue
        case .error: return .red
        }
    }

    private func parameterBinding(for paramID: String) -> Binding<String> {
        Binding(
            get: {
                viewModel.parameterValues.first(where: { $0.parameterID == paramID })?.stringValue ?? ""
            },
            set: { newValue in
                viewModel.updateParameterValue(parameterID: paramID, value: newValue)
            }
        )
    }

    private func copyCommandToClipboard() {
        copyToClipboard(viewModel.commandPreview)
        showCopiedFeedback(for: .command)
    }

    private func copyConsoleToClipboard() {
        copyToClipboard(viewModel.consoleOutput)
        showCopiedFeedback(for: .console)
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    /// Shows a transient "Copied!" confirmation on the given copy button, then
    /// reverts to the copy icon after a short delay. Token-guarded so a rapid
    /// second copy doesn't get cleared early by the first one's pending reset.
    private func showCopiedFeedback(for target: CopyTarget) {
        copyFeedbackToken += 1
        let token = copyFeedbackToken
        withAnimation(.easeInOut(duration: 0.15)) { copiedTarget = target }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copyFeedbackToken == token {
                withAnimation(.easeInOut(duration: 0.2)) { copiedTarget = nil }
            }
        }
    }

}
#endif
