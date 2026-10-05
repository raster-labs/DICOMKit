// J2KTestBenchViewModel.swift
// DICOMStudio
//
// DICOM Studio — J2K Test Bench orchestration.
//
// Manages the fixture corpus, runs the (fixture × transfer syntax × codec)
// matrix off the main actor, scores every cell, renders decoded-image
// previews, computes decode-speed standings, persists each run, and exposes
// regression deltas against a baseline and the published numbers.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (bench orchestration, persistence and standings); fixtures record Photometric Interpretation as DICOMCore's rawValue and syntax names as J2KBenchSyntax.shortName (A-1 names)

import Foundation
import Observation
import CoreGraphics
import DICOMKit
import DICOMCore
import J2KCore

#if os(macOS)
import AppKit
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class J2KTestBenchViewModel {

    /// One fixture×syntax group of the results grid — one cell per codec.
    public struct ResultGroup: Identifiable, Sendable {
        public let id: String
        public let fixtureName: String
        public let syntaxName: String
        public let syntaxUID: String
        public let cells: [J2KTestCell]
    }

    /// One codec's standing in the decode-speed competition.
    public struct SpeedStanding: Identifiable, Sendable {
        public let codec: J2KBenchCodec
        /// Fixture×syntax races this codec decoded fastest.
        public let wins: Int
        /// Total races (groups with at least one passing decode).
        public let races: Int
        public let medianDecodeMs: Double?
        public var id: String { codec.rawValue }
    }

    /// One decode-time sample for the speed-vs-image-size chart.
    public struct ScalingPoint: Identifiable, Sendable {
        public let id = UUID()
        public let codec: String
        public let fixtureName: String
        public let megapixels: Double
        public let decodeMs: Double
    }

    /// A codec's median decode time relative to J2KSwift's (1.0 = parity).
    public struct RelativeSpeed: Identifiable, Sendable {
        public let codec: String
        public let ratio: Double
        public var id: String { codec }
    }

    /// Median compression achieved for one transfer syntax.
    public struct CompressionStat: Identifiable, Sendable {
        public let syntax: String
        public let ratio: Double
        public var id: String { syntax }
    }

    /// Compressed codestream + geometry for one fixture×syntax group, kept so
    /// the lightbox can decode a full-resolution image on demand.
    private struct GroupArtifacts: Sendable {
        let codestream: Data
        let descriptor: PixelDataDescriptor
        let fixturePath: String
    }

    // MARK: - Persisted state

    public private(set) var corpus: [J2KTestFixture] = []
    public private(set) var history: J2KRunHistory = J2KRunHistory()

    // MARK: - Run configuration

    public var plan: J2KTestPlan = J2KTestPlan()

    // MARK: - Run state

    public private(set) var isRunning = false
    public private(set) var currentCells: [J2KTestCell] = []
    public private(set) var runningLabel: String?
    public private(set) var progressDone = 0
    public private(set) var progressTotal = 0

    /// Decoded-image previews for the current session's run, keyed by cell id.
    /// Not persisted — historical runs loaded from disk have no images.
    public private(set) var cellImages: [UUID: J2KBenchCellImages] = [:]
    /// Original-frame previews, keyed by fixture name.
    public private(set) var originalImages: [String: CGImage] = [:]

    /// Per fixture×syntax group: the codestream + geometry, kept so the
    /// lightbox can decode a full-resolution image on demand.
    @ObservationIgnored private var groupArtifacts: [String: GroupArtifacts] = [:]

    /// Which run is shown in the results area (`nil` ⇒ newest).
    public var selectedRunID: UUID?

    /// Transient status / error messages for the UI.
    public var statusMessage: String?
    public var addError: String?

    private let store: J2KTestBenchStore
    private let storageService: StorageService
    @ObservationIgnored private var runTask: Task<Void, Never>?

    /// Decode result bundle returned from an off-main worker.
    private struct CellOutcome: @unchecked Sendable {
        let decodeMs: Double?
        let psnrDb: Double?
        let outcome: J2KTestOutcome
        let images: J2KBenchCellImages
    }

    // MARK: - Init

    public init(storageService: StorageService = StorageService()) {
        self.storageService = storageService
        self.store = J2KTestBenchStore(storageService: storageService)
        self.corpus = Self.withUniqueNames(store.loadCorpus())
        self.history = store.loadHistory()
        self.selectedRunID = history.runsNewestFirst.first?.id
    }

    // MARK: - Codecs

    /// Codecs available on this machine. The pure-Swift reference codecs
    /// (J2KSwift, JLISwift, JLSwift, JXLSwift) are always available; the
    /// comparison peers depend on an installed CLI binary.
    public var installedCodecs: [J2KBenchCodec] {
        var codecs: [J2KBenchCodec] = [.j2kSwift]
        #if os(macOS)
        if KakaduCLICodec.binaryPath != nil { codecs.append(.kakadu) }
        if GrokCLICodec.binaryPath != nil { codecs.append(.grok) }
        #endif
        // JPEG / JPEG-LS / JPEG XL reference codecs are pure-Swift, in-process.
        codecs.append(contentsOf: [.jliSwift, .jlSwift, .jxlSwift])
        #if os(macOS)
        if DjpegCLICodec.binaryPath != nil { codecs.append(.djpeg) }
        if DjxlCLICodec.binaryPath != nil { codecs.append(.djxl) }
        if CharLSCLICodec.binaryPath != nil { codecs.append(.charls) }
        #endif
        return codecs
    }

    /// Codecs in the active format that are installed and enabled. Each format's
    /// reference codec is always on; the same-family peers are toggleable.
    public var activeCodecs: [J2KBenchCodec] {
        plan.format.codecs.filter { codec in
            guard installedCodecs.contains(codec) else { return false }
            switch codec {
            case .j2kSwift, .jliSwift, .jlSwift, .jxlSwift: return true   // reference
            case .kakadu:   return plan.includeKakadu
            case .grok:     return plan.includeGrok
            case .djpeg:    return plan.includeDjpeg
            case .djxl:     return plan.includeDjxl
            case .charls:   return plan.includeCharLS
            }
        }
    }

    public var canRun: Bool {
        !isRunning && !corpus.isEmpty && !plan.syntaxes.isEmpty && !activeCodecs.isEmpty
    }

    /// "J2KSwift 10.9.3" — the codec version under test, shown in the header.
    public var j2kSwiftVersionLabel: String {
        "J2KSwift \(J2KCore.getVersion())"
    }

    // MARK: - Displayed run

    /// The run shown in the results area.
    public var displayedRun: J2KTestRun? {
        if let id = selectedRunID, let run = history.runs.first(where: { $0.id == id }) {
            return run
        }
        return history.runsNewestFirst.first
    }

    /// Cells for the results grid — the live run while running, otherwise the
    /// selected (or most recent) persisted run.
    public var displayedCells: [J2KTestCell] {
        if isRunning { return currentCells }
        return displayedRun?.cells ?? currentCells
    }

    /// Displayed cells grouped by fixture then transfer syntax, in run order.
    public var resultGroups: [ResultGroup] {
        var order: [String] = []
        var buckets: [String: [J2KTestCell]] = [:]
        for cell in displayedCells {
            // Include syntaxName so the two rows of a `both`-capable UID
            // (e.g. `.91` Lossless vs Lossy) form separate result groups.
            let key = "\(cell.fixtureName)|\(cell.syntaxUID)|\(cell.syntaxName)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(cell)
        }
        return order.map { key in
            let cells = buckets[key] ?? []
            return ResultGroup(id: key,
                               fixtureName: cells.first?.fixtureName ?? "",
                               syntaxName: cells.first?.syntaxName ?? "",
                               syntaxUID: cells.first?.syntaxUID ?? "",
                               cells: cells)
        }
    }

    public var progressFraction: Double {
        progressTotal > 0 ? Double(progressDone) / Double(progressTotal) : 0
    }

    // MARK: - Speed competition

    /// Decode-speed standings for the displayed run, best first.
    public var speedStandings: [SpeedStanding] {
        var wins: [J2KBenchCodec: Int] = [:]
        var times: [J2KBenchCodec: [Double]] = [:]
        var races = 0
        for group in resultGroups {
            var fastest: (codec: J2KBenchCodec, ms: Double)?
            for cell in group.cells {
                guard cell.outcome.isPass, let ms = cell.decodeMs else { continue }
                times[cell.codec, default: []].append(ms)
                if fastest == nil || ms < fastest!.ms { fastest = (cell.codec, ms) }
            }
            if let fastest {
                races += 1
                wins[fastest.codec, default: 0] += 1
            }
        }
        let present = Set(displayedCells.map(\.codec))
        let standings = J2KBenchCodec.allCases
            .filter { present.contains($0) }
            .map { codec -> SpeedStanding in
                let samples = (times[codec] ?? []).sorted()
                let median = samples.isEmpty ? nil : samples[samples.count / 2]
                return SpeedStanding(codec: codec, wins: wins[codec] ?? 0,
                                     races: races, medianDecodeMs: median)
            }
        return standings.sorted { lhs, rhs in
            if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
            return (lhs.medianDecodeMs ?? .infinity) < (rhs.medianDecodeMs ?? .infinity)
        }
    }

    /// The codec that won the most decode races (`nil` if there were none).
    public var overallSpeedWinner: J2KBenchCodec? {
        guard let top = speedStandings.first, top.wins > 0 else { return nil }
        return top.codec
    }

    /// The fastest passing codec in a single fixture×syntax group.
    public func groupWinner(_ group: ResultGroup) -> J2KBenchCodec? {
        var best: (codec: J2KBenchCodec, ms: Double)?
        for cell in group.cells {
            guard cell.outcome.isPass, let ms = cell.decodeMs else { continue }
            if best == nil || ms < best!.ms { best = (cell.codec, ms) }
        }
        return best?.codec
    }

    /// Relative decode-speed bar fill (0…1) for a cell within its group —
    /// the fastest codec fills the bar, slower ones proportionally less.
    public func speedBarFraction(for cell: J2KTestCell, in group: ResultGroup) -> Double {
        guard cell.outcome.isPass, let ms = cell.decodeMs, ms > 0 else { return 0 }
        let fastest = group.cells
            .compactMap { $0.outcome.isPass ? $0.decodeMs : nil }
            .min() ?? ms
        return min(1, fastest / ms)
    }

    // MARK: - Performance charts

    /// One decode-time sample per passing cell — for the speed-vs-size chart.
    public var scalingPoints: [ScalingPoint] {
        displayedCells
            .compactMap { cell -> ScalingPoint? in
                guard cell.outcome.isPass, let ms = cell.decodeMs,
                      cell.fixturePixelCount > 0 else { return nil }
                return ScalingPoint(
                    codec: cell.codec.rawValue,
                    fixtureName: cell.fixtureName,
                    megapixels: Double(cell.fixturePixelCount) / 1_000_000,
                    decodeMs: ms)
            }
            .sorted { $0.megapixels < $1.megapixels }
    }

    /// Each codec's median decode time relative to J2KSwift's (1.0 = parity).
    public var relativeDecodeSpeeds: [RelativeSpeed] {
        var medians: [J2KBenchCodec: Double] = [:]
        for standing in speedStandings {
            if let median = standing.medianDecodeMs { medians[standing.codec] = median }
        }
        // Anchor to the displayed run's reference codec (J2KSwift for JPEG 2000,
        // JLISwift/JLSwift/JXLSwift for the other formats).
        let referenceCodec = displayedCells.first?.codec.format.referenceCodec ?? .j2kSwift
        guard let reference = medians[referenceCodec], reference > 0 else { return [] }
        return J2KBenchCodec.allCases.compactMap { codec in
            guard let median = medians[codec] else { return nil }
            return RelativeSpeed(codec: codec.rawValue, ratio: median / reference)
        }
    }

    /// Median compression ratio achieved per transfer syntax.
    public var compressionBySyntax: [CompressionStat] {
        var ratios: [String: [Double]] = [:]
        // Compression is a property of the reference codestream each format's
        // encoder produces, so attribute it to the reference codec's cells.
        for cell in displayedCells where cell.codec.encodes {
            if let ratio = cell.compressionRatio {
                ratios[cell.syntaxName, default: []].append(ratio)
            }
        }
        return J2KBenchSyntax.all.compactMap { syntax -> CompressionStat? in
            guard let values = ratios[syntax.shortName]?.sorted(), !values.isEmpty else { return nil }
            return CompressionStat(syntax: syntax.shortName, ratio: values[values.count / 2])
        }
    }

    /// True when the displayed run has at least one timed, passing decode.
    public var hasPerformanceData: Bool {
        displayedCells.contains { $0.outcome.isPass && $0.decodeMs != nil }
    }

    // MARK: - Images

    public func images(for cell: J2KTestCell) -> J2KBenchCellImages? {
        cellImages[cell.id]
    }

    public func originalImage(for fixtureName: String) -> CGImage? {
        originalImages[fixtureName]
    }

    // MARK: - Regression vs baseline

    /// The run marked as the regression baseline.
    public var baselineRun: J2KTestRun? { history.baseline }

    /// Decode-time delta of `cell` against the baseline run, as a signed
    /// fraction (`+0.12` ⇒ 12 % slower). `nil` when there is no baseline match
    /// or the baseline is the run currently shown.
    public func baselineDecodeDelta(for cell: J2KTestCell) -> Double? {
        guard let baseline = baselineRun,
              baseline.id != displayedRun?.id,
              let prior = baseline.cellsByKey[cell.matchKey],
              let priorMs = prior.decodeMs, priorMs > 0,
              let nowMs = cell.decodeMs else { return nil }
        return (nowMs - priorMs) / priorMs
    }

    /// Published in-process reference for a cell's fixture — the nearest
    /// CROSS_HOST row by modality and pixel count.
    public func publishedBaseline(for cell: J2KTestCell) -> J2KPublishedBenchmark? {
        guard cell.fixturePixelCount > 0 else { return nil }
        return J2KBenchmarkBaseline.nearest(modality: cell.fixtureModality,
                                            pixelCount: cell.fixturePixelCount)
    }

    // MARK: - Plan editing

    public func toggleSyntax(_ id: String) {
        if plan.selectedSyntaxIDs.contains(id) {
            plan.selectedSyntaxIDs.remove(id)
        } else {
            plan.selectedSyntaxIDs.insert(id)
        }
    }

    // MARK: - Corpus management

    /// Imports DICOM files (or every DICOM file under a folder) into the
    /// corpus, copying each into app-owned storage so it survives relaunches.
    public func addFixtures(urls: [URL]) {
        guard !urls.isEmpty else { return }
        addError = nil
        let destination = corpusDirectory
        Task {
            var imported: [J2KTestFixture] = []
            var failures: [String] = []
            // De-duplicate by source path — filenames collide across folders
            // (e.g. SampleStudies' instance_000001.dcm recurs in every series).
            var knownSources = Set(corpus.compactMap(\.sourcePath))
            var takenNames = Set(corpus.map(\.name))
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                for fileURL in Self.dicomCandidateURLs(under: url) {
                    if knownSources.contains(fileURL.path) { continue }
                    switch await Self.importFixture(from: fileURL, into: destination) {
                    case .success(var fixture):
                        let parent = fileURL.deletingLastPathComponent().lastPathComponent
                        fixture.name = Self.uniqueName(fixture.name, parent: parent, taken: takenNames)
                        takenNames.insert(fixture.name)
                        knownSources.insert(fileURL.path)
                        imported.append(fixture)
                    case .failure(let message):
                        if !message.message.isEmpty {
                            failures.append("\(fileURL.lastPathComponent): \(message.message)")
                        }
                    }
                }
            }
            if !imported.isEmpty {
                corpus.append(contentsOf: imported)
                store.saveCorpus(corpus)
                statusMessage = "Added \(imported.count) fixture\(imported.count == 1 ? "" : "s")."
            }
            if !failures.isEmpty {
                addError = failures.prefix(8).joined(separator: "\n")
            } else if imported.isEmpty {
                addError = "No new DICOM images found."
            }
        }
    }

    public func removeFixture(_ fixture: J2KTestFixture) {
        guard !isRunning else { return }
        corpus.removeAll { $0.id == fixture.id }
        store.saveCorpus(corpus)
        originalImages[fixture.name] = nil
        try? FileManager.default.removeItem(atPath: fixture.path)
    }

    public func clearCorpus() {
        guard !isRunning else { return }
        for fixture in corpus {
            try? FileManager.default.removeItem(atPath: fixture.path)
        }
        corpus.removeAll()
        originalImages.removeAll()
        store.saveCorpus(corpus)
    }

    // MARK: - Run

    public func runBench() {
        guard canRun else { return }
        let fixtures = corpus
        let runPlan = plan
        let codecs = activeCodecs
        let syntaxes = runPlan.syntaxes
        let environment = environmentString

        isRunning = true
        currentCells = []
        cellImages = [:]
        groupArtifacts = [:]
        statusMessage = nil
        addError = nil
        progressDone = 0
        progressTotal = fixtures.count * syntaxes.count * codecs.count
        runningLabel = "Preparing…"

        runTask = Task { [weak self] in
            guard let self else { return }
            var cells: [J2KTestCell] = []

            for fixture in fixtures {
                if Task.isCancelled { break }
                self.runningLabel = "Loading \(fixture.name)…"
                let loaded = await Self.loadFrame(fixture: fixture)

                if case .success(let frame) = loaded, self.originalImages[fixture.name] == nil {
                    let original = await Task.detached { () -> J2KBenchCellImages in
                        J2KBenchCellImages(
                            preview: J2KBenchImageRenderer.preview(
                                pixels: frame.data, descriptor: frame.descriptor),
                            difference: nil)
                    }.value
                    if let preview = original.preview {
                        self.originalImages[fixture.name] = preview
                    }
                }

                for syntax in syntaxes {
                    if Task.isCancelled { break }

                    switch loaded {
                    case .failure(let message):
                        for codec in codecs {
                            cells.append(Self.errorCell(fixture: fixture, syntax: syntax,
                                                        codec: codec, message: message.message))
                            self.currentCells = cells
                            self.progressDone += 1
                        }

                    case .success(let frame):
                        self.runningLabel = "\(fixture.name) · \(syntax.shortName) · encoding"
                        let encoded = await Task.detached {
                            J2KTestBenchService.encodeReference(
                                frame: frame.data, descriptor: frame.descriptor,
                                syntax: syntax, mode: runPlan.encodeMode,
                                warmups: runPlan.warmups, runs: runPlan.timedRuns)
                        }.value

                        switch encoded {
                        case .failure(let message):
                            for codec in codecs {
                                cells.append(message.isUnsupported
                                    ? Self.skippedCell(fixture: fixture, syntax: syntax,
                                                       codec: codec, reason: message.message)
                                    : Self.errorCell(fixture: fixture, syntax: syntax,
                                                     codec: codec,
                                                     message: "encode failed — \(message.message)"))
                                self.currentCells = cells
                                self.progressDone += 1
                            }

                        case .success(let product):
                            let ratio = product.codestream.isEmpty ? nil
                                : Double(frame.descriptor.bytesPerFrame) / Double(product.codestream.count)
                            self.groupArtifacts["\(fixture.name)|\(syntax.uid)|\(syntax.shortName)"] = GroupArtifacts(
                                codestream: product.codestream,
                                descriptor: frame.descriptor,
                                fixturePath: fixture.path)
                            for codec in codecs {
                                if Task.isCancelled { break }
                                self.runningLabel = "\(fixture.name) · \(syntax.shortName) · \(codec.rawValue)"
                                let outcome = await Task.detached { () -> CellOutcome in
                                    let scored = J2KTestBenchService.decodeAndScore(
                                        codestream: product.codestream,
                                        original: frame.data,
                                        descriptor: frame.descriptor,
                                        syntax: syntax, codec: codec,
                                        decodeMode: runPlan.decodeMode,
                                        warmups: runPlan.warmups, runs: runPlan.timedRuns,
                                        lossyThresholdDb: runPlan.lossyPSNRThresholdDb)
                                    var preview: CGImage?
                                    if let decoded = scored.decoded {
                                        preview = J2KBenchImageRenderer.preview(
                                            pixels: decoded, descriptor: frame.descriptor)
                                    }
                                    return CellOutcome(
                                        decodeMs: scored.decodeMs, psnrDb: scored.psnrDb,
                                        outcome: scored.outcome,
                                        images: J2KBenchCellImages(preview: preview,
                                                                   difference: nil))
                                }.value
                                let cell = J2KTestCell(
                                    fixtureName: fixture.name,
                                    fixtureModality: fixture.modality,
                                    fixturePixelCount: fixture.pixelCount,
                                    syntaxUID: syntax.uid, syntaxName: syntax.shortName,
                                    codec: codec,
                                    encodeMs: codec.encodes ? product.encodeMs : nil,
                                    decodeMs: outcome.decodeMs,
                                    encodedBytes: product.codestream.count,
                                    rawBytes: frame.descriptor.bytesPerFrame,
                                    compressionRatio: ratio,
                                    psnrDb: outcome.psnrDb,
                                    outcome: outcome.outcome)
                                cells.append(cell)
                                self.cellImages[cell.id] = outcome.images
                                self.currentCells = cells
                                self.progressDone += 1
                            }
                        }
                    }
                }
            }

            let cancelled = Task.isCancelled
            if !cells.isEmpty {
                let run = J2KTestRun(environment: environment, cells: cells,
                                     fixtureCount: fixtures.count, syntaxCount: syntaxes.count)
                self.history.runs.append(run)
                self.store.saveHistory(self.history)
                self.selectedRunID = run.id
                self.statusMessage = cancelled
                    ? "Run cancelled — \(run.passCount)/\(run.totalCount) cells completed."
                    : "Run complete — \(run.passCount)/\(run.totalCount) passed."
            }
            self.isRunning = false
            self.runningLabel = nil
            self.runTask = nil
        }
    }

    public func cancelRun() {
        runTask?.cancel()
    }

    // MARK: - History

    public func selectRun(_ run: J2KTestRun) {
        selectedRunID = run.id
    }

    public func setBaselineToDisplayedRun() {
        guard let run = displayedRun else { return }
        history.baselineRunID = run.id
        store.saveHistory(history)
        statusMessage = "Baseline set to the \(shortTimestamp(run.timestamp)) run."
    }

    public func clearBaseline() {
        history.baselineRunID = nil
        store.saveHistory(history)
    }

    public func deleteRun(_ run: J2KTestRun) {
        guard !isRunning else { return }
        history.runs.removeAll { $0.id == run.id }
        if history.baselineRunID == run.id { history.baselineRunID = nil }
        if selectedRunID == run.id { selectedRunID = history.runsNewestFirst.first?.id }
        store.saveHistory(history)
    }

    // MARK: - Export

    public func exportCSV() { export(fileExtension: "csv", render: J2KTestBenchExporter.csv) }
    public func exportMarkdown() { export(fileExtension: "md", render: J2KTestBenchExporter.markdown) }

    private func export(fileExtension: String, render: (J2KTestRun) -> String) {
        guard !isRunning, let run = displayedRun, !run.cells.isEmpty else {
            statusMessage = "Run the bench before exporting."
            return
        }
        let url = storageService.exportDirectory
            .appendingPathComponent("j2k-bench-\(fileStamp(run.timestamp)).\(fileExtension)")
        do {
            try storageService.createDirectories()
            try Data(render(run).utf8).write(to: url, options: .atomic)
            statusMessage = "Exported to \(url.path)"
            #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            #endif
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private var corpusDirectory: URL {
        storageService.baseDirectory.appendingPathComponent("J2KBenchCorpus", isDirectory: true)
    }

    private var environmentString: String {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return "J2KSwift \(J2KCore.getVersion()) · \(architecture)"
    }

    private func shortTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    private func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func errorCell(fixture: J2KTestFixture, syntax: J2KBenchSyntax,
                                  codec: J2KBenchCodec, message: String) -> J2KTestCell {
        J2KTestCell(fixtureName: fixture.name, fixtureModality: fixture.modality,
                    fixturePixelCount: fixture.pixelCount,
                    syntaxUID: syntax.uid, syntaxName: syntax.shortName,
                    codec: codec, outcome: .error(message))
    }

    /// A row the bench declined to run because the target is blocked, not broken.
    private static func skippedCell(fixture: J2KTestFixture, syntax: J2KBenchSyntax,
                                    codec: J2KBenchCodec, reason: String) -> J2KTestCell {
        J2KTestCell(fixtureName: fixture.name, fixtureModality: fixture.modality,
                    fixturePixelCount: fixture.pixelCount,
                    syntaxUID: syntax.uid, syntaxName: syntax.shortName,
                    codec: codec, outcome: .skipped(reason))
    }

    /// A corpus-unique display name. Fixture names key the result groups and
    /// image lookups, so a collision would merge two distinct fixtures.
    private static func uniqueName(_ base: String, parent: String, taken: Set<String>) -> String {
        if !taken.contains(base) { return base }
        if !parent.isEmpty {
            let qualified = "\(parent)/\(base)"
            if !taken.contains(qualified) { return qualified }
        }
        var suffix = 2
        while taken.contains("\(base) (\(suffix))") { suffix += 1 }
        return "\(base) (\(suffix))"
    }

    /// Re-disambiguates a loaded corpus so older saves with colliding
    /// filenames still render and group correctly.
    private static func withUniqueNames(_ fixtures: [J2KTestFixture]) -> [J2KTestFixture] {
        var taken = Set<String>()
        return fixtures.map { fixture in
            var copy = fixture
            let parent = copy.sourcePath
                .map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent } ?? ""
            copy.name = uniqueName(copy.name, parent: parent, taken: taken)
            taken.insert(copy.name)
            return copy
        }
    }

    // MARK: - Off-main workers

    /// Reads a fixture's frame 0 and descriptor. Runs off the main actor.
    private static func loadFrame(
        fixture: J2KTestFixture
    ) async -> Result<(data: Data, descriptor: PixelDataDescriptor), J2KBenchError> {
        await Task.detached {
            let url = URL(fileURLWithPath: fixture.path)
            guard let fileData = try? Data(contentsOf: url) else {
                return .failure(J2KBenchError("cannot read \(fixture.name)"))
            }
            let file: DICOMFile
            if let parsed = try? DICOMFile.read(from: fileData) {
                file = parsed
            } else if let forced = try? DICOMFile.read(from: fileData, force: true) {
                file = forced
            } else {
                return .failure(J2KBenchError("not a readable DICOM file"))
            }
            guard let pixelData = file.pixelData() else {
                return .failure(J2KBenchError("file has no pixel data"))
            }
            guard let frame = pixelData.frameData(at: 0) else {
                return .failure(J2KBenchError("frame 0 is not accessible"))
            }
            return .success((frame, pixelData.descriptor))
        }.value
    }

    /// Decodes a full-resolution lightbox image on demand. `codec == nil`
    /// loads the original frame; otherwise the group's codestream is decoded
    /// with the given codec, plus an amplified difference vs the original.
    public func detailImages(fixtureName: String, syntaxUID: String, syntaxName: String,
                             codec: J2KBenchCodec?) async -> J2KBenchCellImages {
        guard let artifacts = groupArtifacts["\(fixtureName)|\(syntaxUID)|\(syntaxName)"] else {
            return J2KBenchCellImages(preview: nil, difference: nil)
        }
        let decodeMode = plan.decodeMode
        return await Task.detached {
            let originalFrame = Self.loadFrameData(path: artifacts.fixturePath)
            guard let codec else {
                let image = originalFrame.flatMap {
                    J2KBenchImageRenderer.fullImage(pixels: $0, descriptor: artifacts.descriptor)
                }
                return J2KBenchCellImages(preview: image, difference: nil)
            }
            guard let decoded = J2KTestBenchService.decodeFullResolution(
                codestream: artifacts.codestream, descriptor: artifacts.descriptor,
                codec: codec, decodeMode: decodeMode) else {
                return J2KBenchCellImages(preview: nil, difference: nil)
            }
            let preview = J2KBenchImageRenderer.fullImage(
                pixels: decoded, descriptor: artifacts.descriptor)
            let difference = originalFrame.flatMap {
                J2KBenchImageRenderer.fullDifference(
                    decoded: decoded, original: $0, descriptor: artifacts.descriptor)
            }
            return J2KBenchCellImages(preview: preview, difference: difference)
        }.value
    }

    /// Reads frame 0 of a DICOM file. `nonisolated` so it can run inside the
    /// off-main detached task that decodes a lightbox image.
    nonisolated private static func loadFrameData(path: String) -> Data? {
        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let file: DICOMFile
        if let parsed = try? DICOMFile.read(from: fileData) {
            file = parsed
        } else if let forced = try? DICOMFile.read(from: fileData, force: true) {
            file = forced
        } else {
            return nil
        }
        return file.pixelData()?.frameData(at: 0)
    }

    /// Probes a candidate file and, if it is an image-bearing DICOM, copies it
    /// into the corpus directory and builds a fixture. A `.failure("")` (empty
    /// message) means "not a DICOM file" and is skipped silently.
    private static func importFixture(
        from sourceURL: URL, into destination: URL
    ) async -> Result<J2KTestFixture, J2KBenchError> {
        await Task.detached {
            guard let fileData = try? Data(contentsOf: sourceURL), fileData.count > 132 else {
                return .failure(J2KBenchError(""))
            }
            let file: DICOMFile
            if let parsed = try? DICOMFile.read(from: fileData) {
                file = parsed
            } else if let forced = try? DICOMFile.read(from: fileData, force: true) {
                file = forced
            } else {
                return .failure(J2KBenchError(""))
            }
            guard let descriptor = file.pixelDataDescriptor() else {
                return .failure(J2KBenchError("no image pixel data"))
            }
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let storedURL = destination.appendingPathComponent("\(UUID().uuidString).dcm")
            do {
                try fileData.write(to: storedURL, options: .atomic)
            } catch {
                return .failure(J2KBenchError("could not copy into the corpus"))
            }
            let modality = file.dataSet.string(for: .modality) ?? "OT"
            let fixture = J2KTestFixture(
                path: storedURL.path,
                sourcePath: sourceURL.path,
                name: sourceURL.lastPathComponent,
                columns: descriptor.columns,
                rows: descriptor.rows,
                bitsAllocated: descriptor.bitsAllocated,
                samplesPerPixel: descriptor.samplesPerPixel,
                frameCount: descriptor.numberOfFrames,
                photometric: descriptor.photometricInterpretation.rawValue,
                modality: modality)
            return .success(fixture)
        }.value
    }

    /// Every regular file under `url` (or `[url]` itself when it is a file).
    private static func dicomCandidateURLs(under url: URL) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue { return [url] }
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
