// J2KTestBenchView.swift
// DICOMStudio
//
// DICOM Studio — J2K Test Bench: a corpus-driven codec test workflow.
//
// One coherent flow — Corpus → Test Plan → Run → Results. Results lead with a
// Speed Winner scoreboard, then per fixture×syntax cards carrying a decoded-
// image gallery and a speed-ranked table. Tap any image to enlarge it, with an
// amplified difference view for lossy reconstructions.

#if canImport(SwiftUI)
import SwiftUI
import Charts
import CoreGraphics
import UniformTypeIdentifiers
import DICOMCore

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct J2KTestBenchView: View {

    @Bindable var viewModel: J2KTestBenchViewModel
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false
    @State private var lightbox: LightboxItem?
    @State private var lightboxImages: J2KBenchCellImages?
    @State private var lightboxLoading = false
    @State private var lightboxShowsDiff = false
    @State private var performanceChart: PerformanceChart = .decodeSpeed
    @State private var stage: Stage = .setup

    public init(viewModel: J2KTestBenchViewModel) {
        self.viewModel = viewModel
    }

    /// Identifies the image to enlarge; the full-resolution pixels are decoded
    /// on demand when the lightbox opens.
    private struct LightboxItem: Identifiable {
        let id = UUID()
        let title: String
        let fixtureName: String
        let syntaxUID: String
        /// Distinguishes the two rows of a `both`-capable UID (they share `syntaxUID`).
        let syntaxName: String
        /// `nil` shows the original frame; otherwise the codec's decode.
        let codec: J2KBenchCodec?
    }

    /// The available performance-analysis chart views.
    private enum PerformanceChart: String, CaseIterable, Identifiable {
        case decodeSpeed  = "Decode speed"
        case scaling      = "Scaling"
        case relative     = "Relative"
        case compression  = "Compression"
        var id: String { rawValue }
    }

    /// The four stages of the test-bench workflow.
    private enum Stage: String, CaseIterable, Identifiable {
        case setup        = "Setup"
        case results      = "Results"
        case performance  = "Performance"
        case history      = "History"
        var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                header
                Picker("Stage", selection: $stage) {
                    ForEach(Stage.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stageContent
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("J2K Test Bench")
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: [.data, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                viewModel.addFixtures(urls: urls)
            }
        }
        .overlay {
            if let lightbox {
                lightboxView(lightbox)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("J2K Test Bench").font(.title2.bold())
            Text(viewModel.j2kSwiftVersionLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(Color.accentColor)
            Spacer()
            if viewModel.isRunning {
                ProgressView(value: viewModel.progressFraction)
                    .frame(width: 130)
                Button(role: .cancel) { viewModel.cancelRun() } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .controlSize(.small)
            }
        }
    }

    /// The content shown for the selected workflow stage.
    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .setup:
            corpusSection
            planSection
        case .results:
            resultsSection
        case .performance:
            performanceSection
            if !viewModel.hasPerformanceData {
                stageEmptyState(
                    icon: "chart.bar.xaxis",
                    title: "No performance data yet",
                    message: "Run the test matrix from the Setup tab — these charts visualise decode speed, scaling, and compression across the corpus.")
            }
        case .history:
            historySection
        }
    }

    private func stageEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).font(.callout.weight(.medium))
            Text(message)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Corpus

    private var corpusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.corpus.isEmpty {
                    emptyCorpusHint
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.corpus) { fixture in
                            fixtureRow(fixture)
                        }
                    }
                }
                if let addError = viewModel.addError {
                    Label(addError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button { isImporterPresented = true } label: {
                        Label("Add Files or Folder…", systemImage: "plus")
                    }
                    .disabled(viewModel.isRunning)
                    if !viewModel.corpus.isEmpty {
                        Button(role: .destructive) { viewModel.clearCorpus() } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .disabled(viewModel.isRunning)
                    }
                    Spacer()
                    Label("Drag DICOM files or a folder here", systemImage: "arrow.down.doc")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Corpus — \(viewModel.corpus.count) fixture\(viewModel.corpus.count == 1 ? "" : "s")",
                  systemImage: "square.stack.3d.up")
                .font(.headline)
        }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.addFixtures(urls: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: isDropTargeted ? 2 : 0)
        }
    }

    private var emptyCorpusHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.largeTitle).foregroundStyle(.tertiary)
            Text("No fixtures yet").font(.callout.weight(.medium))
            Text("Add DICOM images to test codecs across varied dimensions, bit depths, and modalities — that variety is what makes a corpus meaningful.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func fixtureRow(_ fixture: J2KTestFixture) -> some View {
        HStack(spacing: 8) {
            Text(fixture.modality.isEmpty ? "—" : fixture.modality)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(fixture.name).font(.callout).lineLimit(1)
                Text(fixture.geometrySummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { viewModel.removeFixture(fixture) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRunning)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Test Plan

    private var planSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionCaption("Codec family")
                    Picker("Codec family", selection: $viewModel.plan.format) {
                        ForEach(J2KBenchFormat.allCases) { format in
                            Label(format.rawValue, systemImage: format.systemImage).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(viewModel.isRunning)
                    Text("\(viewModel.plan.format.referenceCodec.displayName) is the reference encoder; same-family codecs decode its output.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    sectionCaption(viewModel.plan.format == .jpeg2000 ? "Transfer syntaxes" : "Modes")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        ForEach(J2KBenchSyntax.all(for: viewModel.plan.format)) { syntax in
                            syntaxChip(syntax)
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    sectionCaption("Codecs")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        ForEach(viewModel.plan.format.codecs) { codec in
                            codecChip(codec)
                        }
                    }
                }
                Divider()
                methodologyControls
                Divider()
                runControls
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Test Plan", systemImage: "slider.horizontal.3").font(.headline)
        }
    }

    private func syntaxChip(_ syntax: J2KBenchSyntax) -> some View {
        let selected = viewModel.plan.selectedSyntaxIDs.contains(syntax.id)
        return Button {
            viewModel.toggleSyntax(syntax.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(syntax.shortName).font(.caption)
                    Text(syntax.isLossless ? "lossless · bit-exact" : "lossy · PSNR")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRunning)
    }

    private func codecChip(_ codec: J2KBenchCodec) -> some View {
        let installed = viewModel.installedCodecs.contains(codec)
        let enabled = isCodecEnabled(codec)
        return Button {
            toggleCodec(codec)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: !installed ? "circle.slash"
                      : (enabled ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(!installed ? .secondary
                                     : (enabled ? Color.accentColor : .secondary))
                Text(codec.displayName).font(.caption)
                if codec.encodes {
                    Text("reference").font(.caption2).foregroundStyle(.tertiary)
                } else if !installed {
                    Text("not installed").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRunning || !installed || codec.encodes)
    }

    private var methodologyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCaption("Methodology")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
                      alignment: .leading, spacing: 8) {
                // Encode/decode API modes (CPU/GPU/HT) are J2KSwift-specific.
                if viewModel.plan.format == .jpeg2000 {
                    labeledControl("Encode API") {
                        Picker("", selection: $viewModel.plan.encodeMode) {
                            ForEach(J2KSwiftEncodeMode.allCases) { mode in
                                Text(plainLabel(mode.label)).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }
                    labeledControl("Decode API") {
                        Picker("", selection: $viewModel.plan.decodeMode) {
                            ForEach(J2KSwiftDecodeMode.allCases) { mode in
                                Text(plainLabel(mode.label)).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }
                }
                Stepper("Warmups: \(viewModel.plan.warmups)",
                        value: $viewModel.plan.warmups, in: 0...5)
                Stepper("Timed runs: \(viewModel.plan.timedRuns)",
                        value: $viewModel.plan.timedRuns, in: 1...15)
                Stepper("Lossy pass: PSNR ≥ \(Int(viewModel.plan.lossyPSNRThresholdDb)) dB",
                        value: $viewModel.plan.lossyPSNRThresholdDb, in: 20...60, step: 1)
            }
        }
        .disabled(viewModel.isRunning)
    }

    private func labeledControl<Content: View>(
        _ label: String, @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
            Spacer(minLength: 0)
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if viewModel.isRunning {
                    Button(role: .cancel) { viewModel.cancelRun() } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        viewModel.runBench()
                        stage = .results
                    } label: {
                        Label("Run Test Matrix", systemImage: "play.fill")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canRun)
                }
                Text(matrixSummary).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if viewModel.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: viewModel.progressFraction)
                    HStack {
                        Text(viewModel.runningLabel ?? "Running…")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("\(viewModel.progressDone)/\(viewModel.progressTotal)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #if DEBUG
            Label("Debug build — SwiftJ2K runs unoptimized; timings are not representative. Build Release for real numbers.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            #endif
        }
    }

    private var matrixSummary: String {
        let fixtures = viewModel.corpus.count
        let syntaxes = viewModel.plan.syntaxes.count
        let codecs = viewModel.activeCodecs.count
        if fixtures == 0 { return "Add fixtures to run." }
        if syntaxes == 0 { return "Select at least one transfer syntax." }
        return "\(fixtures) × \(syntaxes) × \(codecs) = \(fixtures * syntaxes * codecs) cells"
    }

    // MARK: - Results

    private var resultsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                resultsToolbar
                if let status = viewModel.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if viewModel.displayedCells.isEmpty {
                    Text(viewModel.isRunning ? "Running…" : "Run the bench to see results.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    speedScoreboard
                    ForEach(viewModel.resultGroups) { group in
                        groupCard(group)
                    }
                    resultsFootnote
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(resultsLabel, systemImage: "checklist").font(.headline)
        }
    }

    private var resultsToolbar: some View {
        HStack(spacing: 10) {
            if !viewModel.history.runs.isEmpty {
                Menu {
                    ForEach(viewModel.history.runsNewestFirst) { run in
                        Button {
                            viewModel.selectRun(run)
                        } label: {
                            Text("\(runTimestamp(run.timestamp)) — \(run.passCount)/\(run.totalCount)")
                        }
                    }
                } label: {
                    Label(displayedRunMenuLabel, systemImage: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Spacer()
            if viewModel.displayedRun != nil,
               viewModel.baselineRun?.id == viewModel.displayedRun?.id {
                Label("Baseline", systemImage: "star.fill")
                    .font(.caption).foregroundStyle(.yellow)
            } else {
                Button { viewModel.setBaselineToDisplayedRun() } label: {
                    Label("Set as Baseline", systemImage: "star")
                }
                .disabled(viewModel.displayedRun == nil || viewModel.isRunning)
            }
            Button { viewModel.exportCSV() } label: {
                Label("CSV", systemImage: "tablecells")
            }
            .disabled(viewModel.isRunning)
            Button { viewModel.exportMarkdown() } label: {
                Label("Markdown", systemImage: "doc.text")
            }
            .disabled(viewModel.isRunning)
        }
    }

    // MARK: - Speed scoreboard

    private var speedScoreboard: some View {
        let standings = viewModel.speedStandings
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                Text("Speed Winner").font(.subheadline.weight(.bold))
                if let winner = viewModel.overallSpeedWinner {
                    Text("· \(winner.displayName)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.yellow)
                }
                Spacer()
                Text("fastest decode wins each fixture×syntax race")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                standingRow(rank: index, standing: standing)
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.25))
        }
    }

    private func standingRow(rank: Int, standing: J2KTestBenchViewModel.SpeedStanding) -> some View {
        HStack(spacing: 10) {
            Text(medal(rank)).font(.callout).frame(width: 26)
            Text(standing.codec.displayName)
                .font(.callout.weight(rank == 0 ? .semibold : .regular))
                .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                let fraction = standing.races > 0
                    ? Double(standing.wins) / Double(standing.races) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    if fraction > 0 {
                        Capsule()
                            .fill(rank == 0 ? Color.yellow : Color.accentColor.opacity(0.55))
                            .frame(width: max(6, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 10)
            .frame(maxWidth: .infinity)
            Text("won \(standing.wins)/\(standing.races)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 86, alignment: .trailing)
            Text(standing.medianDecodeMs.map { String(format: "%.2f ms", $0) } ?? "—")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
        }
    }

    // MARK: - Group card

    private func groupCard(_ group: J2KTestBenchViewModel.ResultGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(group.fixtureName)  ·  \(group.syntaxName)")
                .font(.callout.weight(.semibold))
            groupSubheader(group)
            galleryRow(group)
            Divider()
            rankedTable(group)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func groupSubheader(_ group: J2KTestBenchViewModel.ResultGroup) -> some View {
        // The reference codec varies by format (J2KSwift, JLISwift, JLSwift, JXLSwift).
        let reference = group.cells.first { $0.codec.encodes } ?? group.cells.first
        HStack(spacing: 12) {
            if let reference {
                if let bytes = reference.encodedBytes {
                    metaChip("doc.zipper", formatBytes(bytes))
                }
                if let ratio = reference.compressionRatio {
                    metaChip("arrow.down.right.and.arrow.up.left", String(format: "%.2f×", ratio))
                }
                if let encode = reference.encodeMs {
                    metaChip("bolt", "encode " + String(format: "%.2f ms", encode))
                }
                if let published = viewModel.publishedBaseline(for: reference) {
                    metaChip("scope", "ref M4 " + String(format: "%.1f ms", published.decodeMsM4))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func metaChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func galleryRow(_ group: J2KTestBenchViewModel.ResultGroup) -> some View {
        let winner = viewModel.groupWinner(group)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail(title: "Original", subtitle: "source frame",
                          image: viewModel.originalImage(for: group.fixtureName),
                          isWinner: false,
                          target: LightboxItem(title: "\(group.fixtureName) · Original",
                                               fixtureName: group.fixtureName,
                                               syntaxUID: group.syntaxUID,
                                               syntaxName: group.syntaxName, codec: nil))
                ForEach(group.cells) { cell in
                    thumbnail(title: cell.codec.displayName,
                              subtitle: decodeSubtitle(cell),
                              image: viewModel.images(for: cell)?.preview,
                              isWinner: cell.codec == winner,
                              target: LightboxItem(
                                title: "\(group.fixtureName) · \(group.syntaxName) · \(cell.codec.displayName)",
                                fixtureName: group.fixtureName,
                                syntaxUID: group.syntaxUID,
                                syntaxName: group.syntaxName, codec: cell.codec))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func thumbnail(title: String, subtitle: String, image: CGImage?,
                           isWinner: Bool, target: LightboxItem) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                if isWinner { Text("🥇").font(.caption2) }
                Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            }
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable().interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.title2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 104, height: 104)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isWinner ? Color.yellow : Color.clear, lineWidth: 1.5)
            }
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 108)
        .contentShape(Rectangle())
        .onTapGesture {
            if image != nil {
                lightboxShowsDiff = false
                lightbox = target
            }
        }
    }

    private func rankedTable(_ group: J2KTestBenchViewModel.ResultGroup) -> some View {
        let winner = viewModel.groupWinner(group)
        return VStack(spacing: 3) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 18, height: 1)
                Text("Codec").frame(width: 92, alignment: .leading)
                Text("Decode").frame(width: 64, alignment: .trailing)
                Text("Speed").frame(maxWidth: .infinity, alignment: .leading)
                Text("PSNR").frame(width: 52, alignment: .trailing)
                Text("Δ base").frame(width: 52, alignment: .trailing)
                Text("Outcome").frame(width: 118, alignment: .leading)
            }
            .font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            ForEach(group.cells) { cell in
                rankRow(cell, in: group, isWinner: cell.codec == winner)
            }
        }
    }

    private func rankRow(_ cell: J2KTestCell, in group: J2KTestBenchViewModel.ResultGroup,
                         isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isWinner ? "🥇" : "").font(.caption2).frame(width: 18)
            HStack(spacing: 4) {
                Image(systemName: cell.codec.systemImage)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(cell.codec.displayName).font(.caption).lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            Text(msText(cell.decodeMs))
                .font(.system(.caption, design: .monospaced).weight(isWinner ? .bold : .regular))
                .frame(width: 64, alignment: .trailing)
            speedBar(fraction: viewModel.speedBarFraction(for: cell, in: group), isWinner: isWinner)
            Text(psnrText(cell))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
            baselineDeltaText(cell)
                .frame(width: 52, alignment: .trailing)
            outcomeBadge(cell.outcome)
                .frame(width: 118, alignment: .leading)
        }
    }

    private func speedBar(fraction: Double, isWinner: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                if fraction > 0 {
                    Capsule()
                        .fill(isWinner ? Color.green : Color.accentColor.opacity(0.7))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func baselineDeltaText(_ cell: J2KTestCell) -> some View {
        if let delta = viewModel.baselineDecodeDelta(for: cell) {
            let regressed = delta > 0.10
            let improved = delta < -0.10
            Text(String(format: "%+.0f%%", delta * 100))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(regressed ? .red : (improved ? .green : .secondary))
        } else {
            Text("—")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func outcomeBadge(_ outcome: J2KTestOutcome) -> some View {
        switch outcome {
        case .pass:
            Label("Pass", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .fail(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(1).help(reason)
        case .error(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(1).help(reason)
        case .skipped(let reason):
            Label(reason, systemImage: "minus.circle")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).help(reason)
        }
    }

    @ViewBuilder
    private var resultsFootnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let baseline = viewModel.baselineRun, baseline.id != viewModel.displayedRun?.id {
                Text("Δ base — decode delta vs the baseline run (\(runTimestamp(baseline.timestamp))).")
            }
            Text("Tap any image to enlarge it; lossy decodes offer an amplified difference view. ref M4 from \(J2KBenchmarkBaseline.sourceDescription).")
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Lightbox

    private func lightboxView(_ item: LightboxItem) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.85)).ignoresSafeArea()
                .onTapGesture { dismissLightbox() }
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text(item.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    if lightboxImages?.difference != nil {
                        Toggle(isOn: $lightboxShowsDiff) {
                            Label("Difference", systemImage: "circle.lefthalf.filled")
                        }
                        .toggleStyle(.button).tint(.white)
                    }
                    Button { dismissLightbox() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                }
                ZStack {
                    if lightboxLoading {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.large).tint(.white)
                            Text("Decoding at full resolution…")
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(width: 520, height: 380)
                    } else if let shown = (lightboxShowsDiff ? lightboxImages?.difference : nil)
                                ?? lightboxImages?.preview {
                        Image(decorative: shown, scale: 1)
                            .resizable().interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 900, maxHeight: 620)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("A full-resolution image is available only for runs from the current session.")
                            .font(.callout).foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .frame(width: 520, height: 380)
                    }
                }
                Text(lightboxShowsDiff
                     ? "Amplified absolute difference vs the original — black means identical."
                     : "Decoded at full resolution. Tap outside to close.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .padding(28)
            .frame(maxWidth: 980)
        }
        .transition(.opacity)
        .task(id: item.id) {
            lightboxShowsDiff = false
            lightboxImages = nil
            lightboxLoading = true
            lightboxImages = await viewModel.detailImages(
                fixtureName: item.fixtureName, syntaxUID: item.syntaxUID,
                syntaxName: item.syntaxName, codec: item.codec)
            lightboxLoading = false
        }
    }

    private func dismissLightbox() {
        lightbox = nil
        lightboxImages = nil
        lightboxLoading = false
        lightboxShowsDiff = false
    }

    // MARK: - Performance Analysis

    @ViewBuilder
    private var performanceSection: some View {
        if viewModel.hasPerformanceData {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Chart", selection: $performanceChart) {
                        ForEach(PerformanceChart.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    performanceChartBody
                        .frame(height: 260)
                    Text(performanceCaption)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Performance Analysis", systemImage: "chart.bar.xaxis").font(.headline)
            }
        }
    }

    @ViewBuilder
    private var performanceChartBody: some View {
        switch performanceChart {
        case .decodeSpeed:  decodeSpeedChart
        case .scaling:      scalingChart
        case .relative:     relativeChart
        case .compression:  compressionChart
        }
    }

    private var decodeSpeedChart: some View {
        Chart(viewModel.speedStandings.filter { $0.medianDecodeMs != nil }) { standing in
            BarMark(
                x: .value("Median decode (ms)", standing.medianDecodeMs ?? 0),
                y: .value("Codec", standing.codec.displayName))
            .foregroundStyle(by: .value("Codec", standing.codec.displayName))
            .annotation(position: .trailing) {
                Text(String(format: "%.2f ms", standing.medianDecodeMs ?? 0))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
    }

    private var scalingChart: some View {
        Chart(viewModel.scalingPoints) { point in
            LineMark(
                x: .value("Megapixels", point.megapixels),
                y: .value("Decode (ms)", point.decodeMs))
            .foregroundStyle(by: .value("Codec", point.codec))
            PointMark(
                x: .value("Megapixels", point.megapixels),
                y: .value("Decode (ms)", point.decodeMs))
            .foregroundStyle(by: .value("Codec", point.codec))
        }
    }

    private var relativeChart: some View {
        Chart(viewModel.relativeDecodeSpeeds) { item in
            BarMark(
                x: .value("× \(viewModel.plan.format.referenceCodec.displayName)", item.ratio),
                y: .value("Codec", item.codec))
            .foregroundStyle(by: .value("Codec", item.codec))
            .annotation(position: .trailing) {
                Text(String(format: "%.2f×", item.ratio))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
    }

    private var compressionChart: some View {
        Chart(viewModel.compressionBySyntax) { stat in
            BarMark(
                x: .value("Ratio", stat.ratio),
                y: .value("Transfer syntax", stat.syntax))
            .foregroundStyle(Color.accentColor)
            .annotation(position: .trailing) {
                Text(String(format: "%.2f×", stat.ratio))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
    }

    private var performanceCaption: String {
        switch performanceChart {
        case .decodeSpeed:
            return "Median decode time per codec across the run — shorter bars are faster."
        case .scaling:
            return "Decode time against image size — shows how each codec scales as frames grow."
        case .relative:
            return "Each codec's median decode time ÷ \(viewModel.plan.format.referenceCodec.displayName)'s. 1.0× is parity; higher is slower."
        case .compression:
            return "Median compression ratio (raw ÷ codestream) per transfer syntax — higher packs smaller."
        }
    }

    // MARK: - History

    private var historySection: some View {
        GroupBox {
            if viewModel.history.runs.isEmpty {
                Text("No runs yet. Completed runs are saved here — set one as the baseline to track regressions.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.history.runsNewestFirst) { run in
                        historyRow(run)
                    }
                }
                .padding(6)
            }
        } label: {
            Label("Run History — \(viewModel.history.runs.count)",
                  systemImage: "clock.arrow.circlepath").font(.headline)
        }
    }

    private func historyRow(_ run: J2KTestRun) -> some View {
        let isShown = run.id == viewModel.displayedRun?.id
        let isBaseline = run.id == viewModel.baselineRun?.id
        return HStack(spacing: 8) {
            Image(systemName: isShown ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isShown ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(runTimestamp(run.timestamp)).font(.callout)
                    if isBaseline {
                        Text("BASELINE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
                Text("\(run.passCount)/\(run.totalCount) passed · \(run.fixtureCount)×\(run.syntaxCount) matrix · \(run.environment)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { viewModel.deleteRun(run) } label: {
                Image(systemName: "trash").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRunning)
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .background(isShown ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectRun(run) }
    }

    // MARK: - Helpers

    private func isCodecEnabled(_ codec: J2KBenchCodec) -> Bool {
        switch codec {
        case .j2kSwift, .jliSwift, .jlSwift, .jxlSwift: return true   // reference codecs
        case .kakadu:   return viewModel.plan.includeKakadu
        case .grok:     return viewModel.plan.includeGrok
        case .djpeg:    return viewModel.plan.includeDjpeg
        case .djxl:     return viewModel.plan.includeDjxl
        case .charls:   return viewModel.plan.includeCharLS
        }
    }

    private func toggleCodec(_ codec: J2KBenchCodec) {
        switch codec {
        case .j2kSwift, .jliSwift, .jlSwift, .jxlSwift: break   // reference codecs are always on
        case .kakadu:   viewModel.plan.includeKakadu.toggle()
        case .grok:     viewModel.plan.includeGrok.toggle()
        case .djpeg:    viewModel.plan.includeDjpeg.toggle()
        case .djxl:     viewModel.plan.includeDjxl.toggle()
        case .charls:   viewModel.plan.includeCharLS.toggle()
        }
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func plainLabel(_ string: String) -> String {
        string.replacingOccurrences(of: "`", with: "")
    }

    private func msText(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "—"
    }

    private func psnrText(_ cell: J2KTestCell) -> String {
        if cell.psnrDb == nil && cell.outcome.isPass { return "∞" }
        return cell.psnrDb.map { String(format: "%.1f", $0) } ?? "—"
    }

    private func decodeSubtitle(_ cell: J2KTestCell) -> String {
        switch cell.outcome {
        case .pass: return cell.decodeMs.map { String(format: "%.2f ms", $0) } ?? "decoded"
        case .fail: return "✗ failed"
        case .error: return "✗ error"
        case .skipped: return "skipped"
        }
    }

    private func medal(_ rank: Int) -> String {
        switch rank {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(rank + 1)"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func runTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter.string(from: date)
    }

    private var displayedRunMenuLabel: String {
        guard let run = viewModel.displayedRun else { return "No runs" }
        return runTimestamp(run.timestamp)
    }

    private var resultsLabel: String {
        guard !viewModel.isRunning, let run = viewModel.displayedRun else { return "Results" }
        return "Results — \(run.passCount)/\(run.totalCount) passed"
    }
}
#endif
