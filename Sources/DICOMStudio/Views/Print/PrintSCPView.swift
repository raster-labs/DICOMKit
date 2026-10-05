// PrintSCPView.swift
// DICOMStudio
//
// DICOM Studio — the Print SCP screen: Studio as a DICOM printer.
//
// The Print screen sends film to a printer; this one *is* the printer. Point any
// Print SCU at this AE title and port and the film it composes appears here,
// full size, with every film-box attribute it arrived with — which is the whole
// reason to emulate a printer rather than buy one: a real film processor tells
// an SCU developer nothing about why the sheet came out wrong.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the 13 attribute labels with tags in attributeRows (Film Size ID
// (2010,0050) … Presentation LUT Shape (2050,0020)) text-diffed against PS3.6 2026a Table 6-1: 13 of 13 labels are the
// attribute name of their tag ("Film Size" and "Magnification" were abbreviations and now read Film Size ID /
// Magnification Type; Scripts/diff_studio_g6.py); the Printer Status picker lists DICOMPrintKit's
// EmulatedPrinterStatus (Table C.13-9 NORMAL/WARNING/FAILURE) and the Print Job event help names the C.13-8
// Execution Status progression PENDING → PRINTING → DONE. The attribute values shown are the received ones.

#if canImport(SwiftUI)
import SwiftUI
import DICOMPrintKit

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct PrintSCPView: View {
    @Bindable var viewModel: PrintSCPViewModel

    /// Whether the event log is showing. On by default — the log is where a
    /// rejected association explains itself.
    @State private var showLog = true

    /// Whether the film-box attribute table is showing under the film. Off by
    /// default: the sheet is what is looked at first and the attributes are what
    /// it is checked against afterwards.
    @State private var showAttributes = false

    public init(viewModel: PrintSCPViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            statusBar
            if let error = viewModel.startErrorMessage {
                errorBanner(error)
            }
            Divider()
            VSplitView {
                HSplitView {
                    // The list of what arrived is a sidebar, not a half of the
                    // screen: the film is what the emulator exists to show, so
                    // the list is held near its natural width and everything
                    // else goes to the sheet in the middle.
                    filmsPane
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    previewPane
                        .frame(minWidth: 480)
                        .layoutPriority(1)
                }
                .frame(minHeight: 360)

                if showLog {
                    logPane
                        .frame(minHeight: 120, idealHeight: 170)
                }
            }
        }
        .navigationTitle("Printer Emulator")
        .sheet(isPresented: $viewModel.isConfiguring) {
            PrintSCPSettingsSheet(viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Printer Emulator")
                .font(.title.bold())
            Text("Receives print jobs from any Print SCU. Configure the sending device "
                 + "with this machine's address, the port below, and the called AE title.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isRunning ? "Printer Online" : "Printer Offline")
                    .font(.title3.bold())
                Text(viewModel.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.endpointDescription)
                    .font(.system(size: 14, design: .monospaced))
                Text("AE Title : Port")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 28)

            counters

            Spacer()

            Picker("Status", selection: $viewModel.settings.printerStatus) {
                ForEach(EmulatedPrinterStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .onChange(of: viewModel.settings.printerStatus) { _, _ in
                viewModel.applyPrinterStatus()
            }
            .help("The Printer Status this emulator reports to N-GET — "
                  + "set it to Failure to exercise an SCU's error handling.")
            .accessibilityLabel("Reported printer status")

            Button {
                viewModel.isConfiguring = true
            } label: {
                Label("Configure", systemImage: "gearshape")
            }
            .accessibilityLabel("Configure the printer emulator")

            Button {
                Task { await viewModel.toggle() }
            } label: {
                Label(viewModel.isRunning ? "Stop" : "Start",
                      systemImage: viewModel.isRunning ? "stop.circle" : "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRunning ? .red : .green)
            .disabled(viewModel.isBusy)
            .accessibilityLabel(viewModel.isRunning ? "Stop the printer" : "Start the printer")

            Toggle(isOn: $showLog) {
                Image(systemName: "list.bullet.rectangle")
            }
            .toggleStyle(.button)
            .help("Show the event log")
            .accessibilityLabel("Toggle event log")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var counters: some View {
        HStack(spacing: 14) {
            counter("Associations", viewModel.associationCount, "link")
            counter("Films", viewModel.filmCount, "doc.richtext")
            counter("Errors", viewModel.errorCount, "exclamationmark.triangle")
        }
    }

    private func counter(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                Text("\(value)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(title)")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Received films

    private var filmsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Received Films", systemImage: "tray.full")
                    .font(.headline)
                Spacer()
                if !viewModel.films.isEmpty {
                    Text(viewModel.retainedSizeDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Clear") { viewModel.clearFilms() }
                        .font(.callout)
                        .accessibilityLabel("Clear received films")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if viewModel.films.isEmpty {
                ContentUnavailableView {
                    Label("No Films Yet", systemImage: "printer")
                } description: {
                    Text(viewModel.isRunning
                         ? "Send a print job to \(viewModel.endpointDescription) and the composed film appears here."
                         : "Start the printer, then send a print job from any Print SCU.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.films, selection: $viewModel.selectedFilmID) { record in
                    filmRow(record)
                }
                .listStyle(.inset)
            }

            if viewModel.evictedFilmCount > 0 {
                Divider()
                Text("\(viewModel.evictedFilmCount) older film"
                     + "\(viewModel.evictedFilmCount == 1 ? "" : "s") released to stay inside the retention limits.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
        }
    }

    private func filmRow(_ record: ReceivedFilmRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            filmThumbnail(record)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.film.info.callingAETitle)
                    .font(.callout.bold())
                    .lineLimit(1)
                Text("\(record.film.info.filmSize) · \(record.film.info.rows)×\(record.film.info.columns)"
                     + " · \(record.film.info.filledImageBoxCount)/\(record.film.info.imageBoxCount) images")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(record.receivedAt.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !record.savedFiles.isEmpty {
                    Label("\(record.savedFiles.count) file\(record.savedFiles.count == 1 ? "" : "s") saved",
                          systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Film from \(record.film.info.callingAETitle), \(record.summary)")
    }

    @ViewBuilder
    private func filmThumbnail(_ record: ReceivedFilmRecord) -> some View {
        #if canImport(CoreGraphics)
        if let image = record.thumbnail.makeCGImage() {
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 70)
                .background(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.quaternary))
        } else {
            placeholderThumbnail
        }
        #else
        placeholderThumbnail
        #endif
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 56, height: 70)
            .overlay(Image(systemName: "photo").font(.callout).foregroundStyle(.secondary))
    }

    // MARK: - Preview

    private var previewPane: some View {
        VStack(spacing: 0) {
            if let record = viewModel.selectedFilm {
                previewToolbar(record)
                Divider()
                filmSheet(record)
                    .layoutPriority(1)
                // The attributes are what a film is *checked against*, which is
                // a second look — folded away, the sheet has the whole pane.
                if showAttributes {
                    Divider()
                    attributesInspector(record.film.info)
                        .frame(height: 200)
                }
            } else {
                ContentUnavailableView(
                    "No Film Selected",
                    systemImage: "doc.richtext",
                    description: Text("Received films are composed at "
                                      + "\(Int(viewModel.settings.dpi)) DPI and shown here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func previewToolbar(_ record: ReceivedFilmRecord) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.summary)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(record.film.width)×\(record.film.height) px · "
                     + String(format: "%.0f×%.0f mm · ", record.film.info.sheetWidthMillimeters,
                              record.film.info.sheetHeightMillimeters)
                     + "\(record.film.isColor ? "Color" : "Grayscale") · "
                     + record.film.info.densityMapping.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button("PDF…")  { save(record, extension: "pdf") }
                Button("PNG…")  { save(record, extension: "png") }
                Button("TIFF…") { save(record, extension: "tiff") }
            } label: {
                Label("Save Film", systemImage: "square.and.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
            .accessibilityLabel("Save this film")

            Button {
                copyAttributes()
            } label: {
                Label("Copy Attributes", systemImage: "doc.on.doc")
            }
            .accessibilityLabel("Copy film attributes as JSON")

            Toggle(isOn: $showAttributes) {
                Label("Attributes", systemImage: "tablecells")
            }
            .toggleStyle(.button)
            .help("Show the film-box attributes under the film")
            .accessibilityLabel("Toggle film attributes")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func filmSheet(_ record: ReceivedFilmRecord) -> some View {
        ZStack {
            Color(white: 0.12)
            #if canImport(CoreGraphics)
            if let image = record.film.makeCGImage() {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    // Barely inset: the sheet is what this screen is for, and
                    // every point of padding is a point it cannot be drawn in.
                    .padding(6)
                    .accessibilityLabel("Composed film: \(record.summary)")
            } else {
                Text("This film could not be rendered.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            #else
            Text("Film rendering is unavailable on this platform.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func attributesInspector(_ info: ComposedFilmInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.attributeRows(info), id: \.0) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.0)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(row.1)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 3)
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// The film-box attributes as label/value rows, in the order a reader
    /// checks them: what was asked for, then how it was laid out, then how it
    /// was rendered.
    static func attributeRows(_ info: ComposedFilmInfo) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Calling AE", info.callingAETitle),
            ("Received", info.receivedAt.formatted(date: .abbreviated, time: .standard)),
            ("Print Job UID", info.printJobUID),
            ("Film Session UID", info.filmSessionUID),
            ("Film Box UID", info.filmBoxUID),
            ("Film Size ID (2010,0050)", info.filmSize),
            ("Film Orientation (2010,0040)", info.filmOrientation),
            ("Image Display Format (2010,0010)", info.imageDisplayFormat),
            ("Layout", "\(info.rows) × \(info.columns)"),
            ("Medium Type (2000,0030)", info.mediumType),
            ("Number of Copies (2000,0010)", "\(info.numberOfCopies)"),
            ("Magnification Type (2010,0060)", info.magnificationType),
            ("Border Density (2010,0100)", info.borderDensity),
            ("Empty Image Density (2010,0110)", info.emptyImageDensity),
            ("Trim (2010,0140)", info.trim)
        ]
        if let label = info.filmSessionLabel {
            rows.append(("Film Session Label (2000,0050)", label))
        }
        if let minDensity = info.minDensity {
            rows.append(("Min Density (2010,0120)", "\(minDensity)"))
        }
        if let maxDensity = info.maxDensity {
            rows.append(("Max Density (2010,0130)", "\(maxDensity)"))
        }
        if let shape = info.presentationLUTShape {
            rows.append(("Presentation LUT Shape (2050,0020)", shape))
        }
        for (index, annotation) in info.annotations.enumerated() {
            rows.append(("Annotation \(index + 1)", annotation))
        }
        rows.append(("Images", "\(info.filledImageBoxCount) of \(info.imageBoxCount) boxes filled"))
        rows.append(("Sheet",
                     String(format: "%.1f × %.1f mm at %.0f DPI",
                            info.sheetWidthMillimeters, info.sheetHeightMillimeters, info.dpi)))
        rows.append(("Density Mapping", info.densityMapping.displayName))
        for skipped in info.skippedImageBoxes {
            rows.append(("Skipped Box", skipped))
        }
        return rows
    }

    // MARK: - Event log

    private var logPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Event Log", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                if !viewModel.log.isEmpty {
                    Text("\(viewModel.log.count) event\(viewModel.log.count == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Clear") { viewModel.clearLog() }
                        .font(.callout)
                        .accessibilityLabel("Clear event log")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            if viewModel.log.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No events yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.log) { entry in
                            logRow(entry)
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    private func logRow(_ entry: PrintSCPLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.level.sfSymbol)
                .font(.system(size: 13))
                .foregroundStyle(color(for: entry.level))
                .frame(width: 18)
                .padding(.top, 1)

            Text(entry.message)
                .font(.callout)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            Text(entry.timestamp, style: .time)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue): \(entry.message)")
    }

    private func color(for level: PrintSCPLogLevel) -> Color {
        switch level {
        case .info:         return .secondary
        case .connection:   return .blue
        case .filmReceived: return .green
        case .warning:      return .orange
        case .error:        return .red
        }
    }

    // MARK: - Actions

    private func save(_ record: ReceivedFilmRecord, extension ext: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(record.suggestedFileName).\(ext)"
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.saveSelectedFilm(to: url)
        #endif
    }

    private func copyAttributes() {
        guard let json = viewModel.selectedFilmAttributesJSON() else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        #endif
    }
}

// MARK: - Configuration sheet

/// Everything about the emulated printer that is not worth a place in the
/// status bar: transport, negotiated capability, the identity reported to
/// N-GET, how films are composed, and where copies are written.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct PrintSCPSettingsSheet: View {
    @Bindable var viewModel: PrintSCPViewModel
    @Environment(\.dismiss) private var dismiss

    /// CUPS queues, loaded once when the sheet opens — `lpstat` is a process
    /// launch and has no business running on every redraw.
    @State private var paperQueues: [String] = []

    private var isLocked: Bool { viewModel.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Printer Emulator Settings").font(.headline)
                Spacer()
                Button("Done") {
                    viewModel.saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if isLocked {
                Label("Stop the printer to change the listener settings. "
                      + "Composition, output and identity apply to the next film.",
                      systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }

            Form {
                listenerSection
                capabilitySection
                identitySection
                compositionSection
                outputSection
                retentionSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 640)
        .onAppear { paperQueues = viewModel.availablePaperQueues() }
    }

    // MARK: Sections

    private var listenerSection: some View {
        Section("Listener") {
            TextField("AE Title", text: $viewModel.settings.aeTitle)
                .disabled(isLocked)
                .accessibilityLabel("Called AE title")
            TextField("Port", value: $viewModel.settings.port, format: .number.grouping(.never))
                .disabled(isLocked)
                .accessibilityLabel("Listener port")
            Stepper("Maximum concurrent associations: \(viewModel.settings.maxConcurrentAssociations)",
                    value: $viewModel.settings.maxConcurrentAssociations, in: 1...64)
                .disabled(isLocked)
            HStack {
                Text("Idle timeout")
                Spacer()
                TextField("", value: $viewModel.settings.associationIdleTimeoutSeconds,
                          format: .number.precision(.fractionLength(0)))
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                Text("seconds").foregroundStyle(.secondary)
            }
            .disabled(isLocked)
            .help("A peer that opens an association and dies otherwise holds its slot forever. "
                  + "0 disables the timeout.")
            TextField("Allowed calling AE titles", text: $viewModel.settings.allowedCallingAETitles,
                      prompt: Text("Any (comma-separated to restrict)"))
                .disabled(isLocked)
                .accessibilityLabel("Allowed calling AE titles")
        }
    }

    private var capabilitySection: some View {
        Section("Negotiation") {
            Toggle("Accept color print management", isOn: $viewModel.settings.supportsColor)
                .disabled(isLocked)
            Toggle("Accept Presentation LUT", isOn: $viewModel.settings.acceptPresentationLUT)
                .disabled(isLocked)
            Toggle("Accept Basic Annotation Box", isOn: $viewModel.settings.acceptAnnotationBox)
                .disabled(isLocked)
            Toggle("Push Print Job status events", isOn: $viewModel.settings.pushPrintJobEvents)
                .disabled(isLocked)
                .help("N-EVENT-REPORT PENDING → PRINTING → DONE after N-ACTION. "
                      + "Off by default: many SCUs ignore them and a few mishandle them.")
        }
    }

    private var identitySection: some View {
        Section("Reported Identity") {
            TextField("Printer Name", text: $viewModel.settings.printerName)
            TextField("Manufacturer", text: $viewModel.settings.manufacturer)
            TextField("Model", text: $viewModel.settings.manufacturerModelName)
            TextField("Serial Number", text: $viewModel.settings.deviceSerialNumber)
            TextField("Software Version", text: $viewModel.settings.softwareVersion)
            TextField("Status Info", text: $viewModel.settings.printerStatusInfo,
                      prompt: Text(viewModel.settings.printerStatus.defaultStatusInfo))
                .onSubmit { viewModel.applyPrinterStatus() }
        }
    }

    private var compositionSection: some View {
        Section("Film Composition") {
            HStack {
                Text("Resolution")
                Spacer()
                TextField("", value: $viewModel.settings.dpi,
                          format: .number.precision(.fractionLength(0)))
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    // The composer clamps anyway; clamping here too means the
                    // field never shows a number the film will not be composed
                    // at, which would otherwise read as the setting being ignored.
                    .onSubmit { clampResolution() }
                Text("DPI").foregroundStyle(.secondary)
                Button {
                    viewModel.settings.dpi = PrintSCPSettings.defaultDPI
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.settings.dpi == PrintSCPSettings.defaultDPI)
                .help("Reset to \(Int(PrintSCPSettings.defaultDPI)) DPI")
                .accessibilityLabel("Reset resolution to default")
            }
            .help("Composed pixels per inch of film, "
                  + "\(Int(PrintSCPSettings.dpiRange.lowerBound))–"
                  + "\(Int(PrintSCPSettings.dpiRange.upperBound)). A 14×17 in sheet is "
                  + "\(Int(14 * PrintSCPSettings.defaultDPI))×"
                  + "\(Int(17 * PrintSCPSettings.defaultDPI)) px at "
                  + "\(Int(PrintSCPSettings.defaultDPI)) DPI. Match the printer's "
                  + "native resolution so no resampling happens on the way out; "
                  + "film imagers do not address beyond about 600.")
            Picker("Density mapping", selection: $viewModel.settings.densityMapping) {
                ForEach(DensityMapping.allCases, id: \.self) { mapping in
                    Text(mapping.displayName).tag(mapping)
                }
            }
            .help("Paper renders P-Values straight. Film emulation inverts the sheet, "
                  + "so dense areas read dark as they would on a lightbox.")
            Toggle("Draw annotation box text", isOn: $viewModel.settings.drawAnnotations)
            if viewModel.settings.drawAnnotations {
                Picker("Annotation position", selection: $viewModel.settings.annotationEdge) {
                    ForEach(FilmAnnotationEdge.allCases, id: \.self) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .help("Where the film-wide text band sits: a footer or header strip, "
                      + "a rotated strip up either side, or drawn over the images "
                      + "without reserving space.")
            }
            Toggle("Draw trim marks when Trim is YES", isOn: $viewModel.settings.drawTrimMarks)
        }
    }

    private var outputSection: some View {
        Section("Automatic Output") {
            HStack {
                TextField("Folder", text: $viewModel.settings.outputDirectory,
                          prompt: Text(viewModel.settings.outputDirectoryURL.path))
                    .disabled(isLocked)
                Button("Choose…") { chooseOutputDirectory() }
                    .disabled(isLocked)
            }
            Toggle("Save every film as PDF", isOn: $viewModel.settings.savePDF)
                .disabled(isLocked)
            Toggle("Save every film as an image", isOn: $viewModel.settings.saveImage)
                .disabled(isLocked)
            Picker("Image format", selection: $viewModel.settings.imageFormat) {
                ForEach(FilmImageFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .disabled(isLocked || !viewModel.settings.saveImage)
            TextField("File name pattern", text: $viewModel.settings.fileNamePattern)
                .disabled(isLocked)
                .help("Tokens: {job} {session} {film} {ae} {index} {timestamp}")
            Toggle("Also spool to a paper printer", isOn: $viewModel.settings.sendToPaperQueue)
                .disabled(isLocked)
            Picker("Print queue", selection: $viewModel.settings.paperQueue) {
                Text("System default").tag("")
                ForEach(paperQueues, id: \.self) { queue in
                    Text(queue).tag(queue)
                }
            }
            .disabled(isLocked || !viewModel.settings.sendToPaperQueue)
        }
    }

    private var retentionSection: some View {
        Section("Retention") {
            Stepper("Keep the last \(viewModel.settings.retainedFilmLimit) films",
                    value: $viewModel.settings.retainedFilmLimit, in: 1...200)
            HStack {
                Text("Memory ceiling")
                Spacer()
                TextField("", value: $viewModel.settings.retainedMemoryBudgetMB,
                          format: .number.grouping(.never))
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                Text("MB").foregroundStyle(.secondary)
            }
            .help("A 14×17 in sheet at 300 DPI is about 21 MB. Older films are released "
                  + "once the retained sheets exceed this.")
        }
    }

    /// Brings a typed resolution into the range the composer will honor.
    ///
    /// NaN compares false against everything, so it cannot be clamped and falls
    /// back to the default rather than reaching the composer as a garbage sheet
    /// size.
    private func clampResolution() {
        let dpi = viewModel.settings.dpi
        guard !dpi.isNaN else {
            viewModel.settings.dpi = PrintSCPSettings.defaultDPI
            return
        }
        viewModel.settings.dpi = min(max(dpi, PrintSCPSettings.dpiRange.lowerBound),
                                     PrintSCPSettings.dpiRange.upperBound)
    }

    private func chooseOutputDirectory() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.settings.outputDirectory = url.path
        }
        #endif
    }
}
#endif
