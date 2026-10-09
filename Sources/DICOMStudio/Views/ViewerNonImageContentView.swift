// ViewerNonImageContentView.swift
// DICOMStudio
//
// DICOM Studio — showing a report, a document, or an object with no pixels.
//
// The centre panel is not only for pictures. A structured report is read as a
// narrative, an encapsulated PDF is read as pages, and anything else at least
// says what it is. Nothing here decodes a file: the content was parsed when the
// instance was loaded, so paging through a series stays as cheap as it is for
// images.
//
// NEMA-verified: 2026a, checked 2026-10-05 — StructuredReportNarrativeView.value(of:) covers the 15 non-CONTAINER Value Types of PS3.3 2026a Table C.17.3-7 (TABLE was missing, D237 sibling); the video container name is DICOMKit's containerDisplayName (no exhaustive switch over VideoContainer here, D237); PS3.5 2026a 8.2.7 cited for the MPEG-4 AVC/H.264 container rule

#if canImport(SwiftUI)
import SwiftUI
import DICOMCore
import DICOMKit
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(AVKit)
import AVKit
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ViewerNonImageContentView: View {
    let content: ViewerNonImageContent
    /// Whether a clip should be running. Bound to the view model's cine state
    /// so the toolbar's play/stop and the player move together. Defaults to a
    /// constant for the content that has nothing to play.
    var isPlaying: Binding<Bool> = .constant(false)

    /// SOP Instance UID of the object on screen, which is what identifies a
    /// clip to the player.
    ///
    /// The payload's byte count used to stand in for this, and two clips of
    /// equal length — the same recording exported twice, a series of fixed
    /// duration — then kept playing the first one silently.
    var instanceUID: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(Color.white.opacity(0.15))

            // Content the viewer cannot show at all says so first, in place of
            // a summary the reader would otherwise scan looking for the image.
            if let reason = content.kind.cannotDisplayReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: 520, alignment: .leading)
                    .accessibilityLabel("Cannot be displayed: \(reason)")
            }

            switch content {
            case .report(let document):
                StructuredReportNarrativeView(document: document)
            case .document(let document):
                encapsulatedDocument(document)
            case .video(let video):
                videoPlayer(video)
            case .summary(_, _, let rows):
                summary(rows)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: content.kind.symbolName)
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(content.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(content.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(10)
    }

    // MARK: - Video

    @ViewBuilder
    private func videoPlayer(_ video: DICOMKit.ExtractedVideo) -> some View {
        #if canImport(AVKit)
        ViewerVideoPlayerView(
            video: video, isPlaying: isPlaying, instanceUID: instanceUID)
        #else
        summary([
            .init(label: "Codec", value: video.codec.displayName),
            .init(label: "Transfer Syntax", value: video.transferSyntax.uid),
            .init(label: "Size", value: "\(video.bitstream.count) bytes"),
            .init(label: "Playback", value: "Not available on this platform")
        ])
        #endif
    }

    // MARK: - Encapsulated document

    @ViewBuilder
    private func encapsulatedDocument(_ document: DICOMKit.EncapsulatedDocument) -> some View {
        #if canImport(PDFKit) && os(macOS)
        if document.isPDF, let pdf = PDFDocument(data: document.documentData) {
            PDFDocumentView(document: pdf)
        } else {
            documentPlaceholder(document)
        }
        #else
        documentPlaceholder(document)
        #endif
    }

    /// A document the app cannot render inline — a CDA, an STL, or a PDF whose
    /// bytes will not open. It is still described rather than refused.
    private func documentPlaceholder(_ document: DICOMKit.EncapsulatedDocument) -> some View {
        summary([
            .init(label: "Type",
                  value: ViewerNonImageContent.name(of: document.documentType)),
            .init(label: "MIME type", value: document.mimeType),
            .init(label: "Size",
                  value: EncapsulatedDocumentFormatting.fileSize(Int64(document.documentSize)))
        ])
    }

    // MARK: - Summary

    private func summary(_ rows: [ViewerNonImageContent.Row]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 120, alignment: .trailing)
                        Text(row.value)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Structured report

/// An SR content tree, read as a report.
///
/// Indented by depth rather than drawn as a disclosure tree: a report is read
/// top to bottom, and collapsing sections hides findings.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct StructuredReportNarrativeView: View {
    let document: DICOMKit.SRDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                metadata

                Divider().overlay(Color.white.opacity(0.15))

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let name = row.name {
                            Text(name)
                                .font(.callout.weight(row.isContainer ? .bold : .semibold))
                                .foregroundStyle(.white.opacity(row.isContainer ? 1 : 0.7))
                        }
                        if let value = row.value {
                            Text(value)
                                .font(.callout)
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(row.depth) * 16)
                    .padding(.top, row.isContainer ? 6 : 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let flag = document.completionFlag {
                label("Completion", flag.rawValue)
            }
            if let flag = document.verificationFlag {
                label("Verification", flag.rawValue)
            }
            if let date = document.contentDate {
                label("Content date", DICOMValueParser.formatDate(date))
            }
            label("Content items", "\(document.contentItemCount)")
        }
    }

    private func label(_ name: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// One line of the report.
    private struct Row {
        let depth: Int
        let name: String?
        let value: String?
        let isContainer: Bool
    }

    private var rows: [Row] {
        var result: [Row] = []
        append(container: document.rootContent, depth: 0, into: &result)
        return result
    }

    private func append(container: ContainerContentItem, depth: Int, into rows: inout [Row]) {
        for item in container.contentItems {
            let name = item.conceptName?.codeMeaning
            if let nested = item.asContainer {
                rows.append(Row(depth: depth, name: name ?? "Section",
                                value: nil, isContainer: true))
                append(container: nested, depth: depth + 1, into: &rows)
            } else {
                rows.append(Row(depth: depth,
                                name: name.map { "\($0):" },
                                value: Self.value(of: item),
                                isContainer: false))
            }
        }
    }

    /// The item's value as a reader would say it aloud.
    ///
    /// One branch per PS3.3 Table C.17.3-7 Value Type other than CONTAINER (which
    /// `append(container:)` walks): TEXT, CODE, NUM, DATE, TIME, DATETIME, PNAME,
    /// IMAGE, WAVEFORM, SCOORD / SCOORD3D / TCOORD, COMPOSITE, UIDREF, TABLE.
    static func value(of item: AnyContentItem) -> String? {
        if let text = item.asText { return text.textValue }
        if let code = item.asCode { return code.conceptCode.codeMeaning }
        if let numeric = item.asNumeric {
            let numbers = numeric.numericValues.map { number -> String in
                number == number.rounded() && abs(number) < 1e15
                    ? String(Int(number)) : String(number)
            }.joined(separator: ", ")
            if let units = numeric.measurementUnits?.codeMeaning, !units.isEmpty {
                return "\(numbers) \(units)"
            }
            return numbers
        }
        if let date = item.asDate { return DICOMValueParser.formatDate(date.dateValue) }
        if let time = item.asTime { return DICOMValueParser.formatTime(time.timeValue) }
        if let dateTime = item.asDateTime {
            return DICOMValueParser.formatDateTime(dateTime.dateTimeValue)
        }
        if let name = item.asPersonName {
            return DICOMValueParser.formatPersonName(name.personName)
        }
        if item.asImage != nil { return "(referenced image)" }
        if item.asWaveform != nil { return "(referenced waveform)" }
        if item.isCoordinate { return "(coordinates)" }
        if item.asComposite != nil { return "(referenced object)" }
        if let uid = item.asUIDRef { return uid.uidValue }
        if let table = item.asTable {
            return "(table, \(table.rows) × \(table.columns))"
        }
        return nil
    }
}

// MARK: - PDF

#if canImport(PDFKit) && os(macOS)
/// PDFKit's own view, which brings scrolling, zooming and text selection with it.
@available(macOS 14.0, *)
struct PDFDocumentView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .black
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
    }
}
#endif
// MARK: - Video

#if canImport(AVKit)
/// The clip, in a player that brings its own transport.
///
/// AVFoundation reads from a URL rather than from data in memory, so the bit
/// stream is spilled to a temporary file first. The payload is a whole
/// container — `dicom-video` refuses a raw elementary stream on the way in
/// (PS3.5 8.2.7) — so what lands on disk is a file a player can open, and the
/// extension follows the container the bytes actually are.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ViewerVideoPlayerView: View {
    let video: DICOMKit.ExtractedVideo
    /// Whether the clip should be running. Owned by the view model so the
    /// toolbar's cine button and the player agree on one answer.
    @Binding var isPlaying: Bool

    /// Identity of the clip on screen — see
    /// ``ViewerNonImageContentView/instanceUID``. Falls back to the payload
    /// size for a standalone file opened outside a series, which carries no
    /// series position to confuse.
    var instanceUID: String?

    @State private var player: AVPlayer?
    @State private var fileURL: URL?
    @State private var failure: String?
    /// Set when playback reaches the end, so the loop restarts from the top
    /// rather than sitting on a last frame that looks like a stall.
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .background(Color.black)
            } else if let failure {
                ContentUnavailableView(
                    "Cannot Play This Clip",
                    systemImage: "film.slash",
                    description: Text(failure))
                .foregroundStyle(.white)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: instanceUID ?? "size:\(video.bitstream.count)") { await prepare() }
        .onDisappear(perform: teardown)
        .onChange(of: isPlaying) { _, wants in
            guard let player else { return }
            // The transport inside `VideoPlayer` moves the same player, so this
            // only pushes the state the view model asked for; it does not fight
            // the reader's own play/pause.
            if wants { player.play() } else { player.pause() }
        }
    }

    /// Writes the payload out and hands it to a player.
    private func prepare() async {
        teardown()
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DICOMStudioVideo", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(
                UUID().uuidString).appendingPathExtension(video.suggestedFileExtension)
            try video.bitstream.write(to: url, options: .atomic)

            let asset = AVURLAsset(url: url)
            // Asking before building the player turns "the window is black" into
            // a sentence naming the codec.
            guard try await asset.load(.isPlayable) else {
                try? FileManager.default.removeItem(at: url)
                // DICOMKit names the container (an MPEG-2 Program Stream / PES by its
                // PS3.5 8.2.5 name), so adding a `VideoContainer` case there needs
                // nothing here.
                failure = "\(video.codec.displayName) in a \(video.containerDisplayName) container "
                    + "is not playable on this system."
                return
            }
            let item = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.actionAtItemEnd = .none
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    newPlayer.seek(to: .zero)
                    if isPlaying { newPlayer.play() }
                }
            fileURL = url
            player = newPlayer
            if isPlaying { newPlayer.play() }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Stops the clip and removes the file it was playing.
    ///
    /// Both halves matter: a player left running keeps decoding a study the
    /// reader has already left, and a file left behind accumulates one copy of
    /// every clip opened this session.
    private func teardown() {
        player?.pause()
        player = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
            self.fileURL = nil
        }
        failure = nil
    }
}
#endif
#endif
