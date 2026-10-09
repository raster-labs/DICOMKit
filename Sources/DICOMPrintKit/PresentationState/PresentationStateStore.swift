// NEMA-verified: 2026a, checked 2026-09-29 — D27/D36: Displayed Area (Table C.10-4) from the image size, state Modality LUT per PS3.4 2026a N.2.1.1, Color Softcopy PS for colour images per PS3.3 A.33.1.1 and Table A.33.2-1; shutter pixel positions per Table C.7-17a; SOP Classes 11.1/11.2/11.3 per PS3.6 Table A-1 (Scripts/diff_printkit.py)
// PresentationStateStore.swift
// DICOMPrintKit
//
// Where saved views live, and how a viewer finds the ones belonging to an image.
//
// The arrangement is one shared presentation-state series per study, holding one
// object per image per saved view. A study that has been read three ways at
// three windows carries one extra series and three objects per image:
//
//   Study 1.2.3
//   └── Series (PR)  ← one, for the life of the study
//       ├── GSPS → image 42, "Lung window"
//       ├── GSPS → image 42, "Bone window"
//       └── GSPS → image 45, "Lung window"
//
// What ties several objects into one *saved view* is therefore the label, not
// the series: a save that spans five images writes five objects carrying the
// same label. That is the trade this arrangement makes — the container stays a
// single series, and grouping rests on a string the user typed. `SavedView`
// exists so the rest of the app never has to do that grouping by hand.
//
// Objects are written as conformant GSPS files even though they stay inside the
// app. The cost is the same either way, and it means exporting a study later is
// a matter of copying files rather than converting them.

import Foundation
import DICOMCore
import DICOMKit

/// One saved view: every presentation state written under a single label.
public struct SavedView: Sendable, Equatable, Identifiable {

    /// Stable across launches — the label is what the user named the view, and
    /// what groups its objects.
    public var id: String { label }

    /// What the reader called it. Shown in the picker.
    public let label: String

    /// When the view was saved.
    public let created: Date?

    /// The presentation states making up this view, one per image.
    public let states: [StoredPresentationState]

    public init(label: String, created: Date?, states: [StoredPresentationState]) {
        self.label = label
        self.created = created
        self.states = states
    }

    /// The short identifier a reader can quote to name this view.
    ///
    /// A label is what a view is *called*; the reference ID is what it *is*.
    /// The distinction matters the moment a saved view leaves the app — two
    /// studies can each hold a "Lung window", and a report that says "see the
    /// lung window" names nothing findable. The ID is derived from the Series
    /// Instance UID the view's objects share and the label that groups them, so
    /// it is stable across launches without a counter to keep on disk, and it
    /// changes when the view is re-saved under a different name because that is
    /// then a different view.
    ///
    /// Formatted as `PR-XXXXXXXX`: short enough to read aloud and type into a
    /// report, long enough that two views of one study will not collide.
    public var referenceID: String {
        SavedView.referenceID(
            seriesInstanceUID: states.first?.seriesInstanceUID ?? "",
            label: label)
    }

    /// The ID for a view, from the two things that identify it.
    ///
    /// Exposed so a caller writing a view can state the ID it *will* have
    /// before the objects exist, and get the same answer this does afterwards.
    public static func referenceID(seriesInstanceUID: String, label: String) -> String {
        // FNV-1a over the two identifying strings. A non-cryptographic hash is
        // the right tool: this is a name, not a secret, and the property that
        // matters is that it is the same every time it is computed — which
        // Swift's own `hashValue` explicitly is not, being seeded per process.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array("\(seriesInstanceUID)|\(label)".utf8) {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let digits = String(hash, radix: 36, uppercase: true)
        return "PR-" + String(digits.suffix(8))
    }

    /// Whether this view came out of the study's own files rather than being
    /// saved here — shown as such, so a reader knows whose reading it is.
    public var isImported: Bool { states.contains(where: \.isImported) }

    /// The state covering a given image, if this view has one.
    ///
    /// A view saved over three images has nothing to say about a fourth; the
    /// caller shows the default view for it.
    public func state(forImage sopInstanceUID: String) -> StoredPresentationState? {
        states.first { $0.referencedImageUIDs.contains(sopInstanceUID) }
    }

    /// Whether this view says anything about a given image.
    public func covers(image sopInstanceUID: String) -> Bool {
        state(forImage: sopInstanceUID) != nil
    }

    /// How many distinct images this view says something about.
    ///
    /// One for a view saved on a single image; the series' image count for a
    /// view saved across it. This is how the pickers tell the two apart — the
    /// label alone cannot, since a name says nothing about its reach.
    public var coveredImageCount: Int {
        Set(states.flatMap(\.referencedImageUIDs)).count
    }
}

/// A presentation state as it sits on disk, with the file it came from.
public struct StoredPresentationState: Sendable, Equatable {

    /// The parsed state.
    public let state: GrayscalePresentationState

    /// Where it lives, so it can be deleted or rewritten.
    public let url: URL

    /// The text and arrows the reader drew on this image, keyed by frame.
    ///
    /// Read from the sidecar beside the object rather than from the object
    /// itself — see ``AnnotationSidecar`` for why they are not written as a
    /// Graphic Annotation Sequence. Empty for the ordinary saved view, which
    /// records a window and a zoom and nothing drawn. A single-frame image's
    /// drawings sit under frame 0.
    public let annotationsByFrame: [Int: [PrintOverlayAnnotation]]

    /// The pseudo-colour palette the view was read through, if any.
    ///
    /// From the sidecar too: GSPS has no vocabulary for "coloured", so a view
    /// saved off a pseudo-coloured image would otherwise restore grey.
    public let palette: PseudoColorPalette?

    /// Drawings filed by image, for an object that describes several.
    ///
    /// Empty for the app's own objects, which describe one image each and keep
    /// their drawings in ``annotationsByFrame``. An object adopted from the
    /// study may describe a series, and each image's rulers are under its
    /// SOP Instance UID here. Read through ``annotationsByFrame(forImage:)``.
    public let annotationsByFrameByImage: [String: [Int: [PrintOverlayAnnotation]]]

    /// Whether this object was adopted from the study's own files rather than
    /// saved by this app — see ``PresentationStateStore/adopt(presentationStateFiles:studyInstanceUID:images:)``.
    public let isImported: Bool

    /// The drawings belonging to one image, by frame.
    ///
    /// The per-image filing when the object has it, else the object's own —
    /// which is right for every object that describes a single image.
    public func annotationsByFrame(forImage sopInstanceUID: String) -> [Int: [PrintOverlayAnnotation]] {
        annotationsByFrameByImage[sopInstanceUID] ?? annotationsByFrame
    }

    /// The drawings belonging to one frame of one image.
    public func annotations(forImage sopInstanceUID: String, frame frameIndex: Int) -> [PrintOverlayAnnotation] {
        annotationsByFrame(forImage: sopInstanceUID)[frameIndex] ?? []
    }

    /// Every drawing regardless of frame, in frame order.
    ///
    /// For callers that speak to the image as a whole — a film cell showing one
    /// frame reads ``annotations(forFrame:)`` instead.
    public var annotations: [PrintOverlayAnnotation] {
        annotationsByFrame.sorted { $0.key < $1.key }.flatMap(\.value)
    }

    /// The drawings belonging to one frame of the image.
    public func annotations(forFrame frameIndex: Int) -> [PrintOverlayAnnotation] {
        annotationsByFrame[frameIndex] ?? []
    }

    /// The reader's own wording, kept unfolded.
    ///
    /// Presentation Label is CS-valued and was uppercased on the way out, so the
    /// name shown in the picker comes from Content Description instead.
    private let displayLabel: String?

    /// Series Number (0020,0011) of the presentation-state series this object
    /// lives in.
    ///
    /// Read from the object rather than assumed to be
    /// ``PresentationStateStore/presentationSeriesNumber``: a study can hold
    /// presentation states written elsewhere, and the pane reports what the
    /// file says.
    public let seriesNumber: Int?

    public init(
        state: GrayscalePresentationState,
        url: URL,
        displayLabel: String? = nil,
        annotations: [PrintOverlayAnnotation] = [],
        annotationsByFrame: [Int: [PrintOverlayAnnotation]]? = nil,
        palette: PseudoColorPalette? = nil,
        seriesInstanceUID: String = "",
        seriesNumber: Int? = nil,
        annotationsByFrameByImage: [String: [Int: [PrintOverlayAnnotation]]] = [:],
        isImported: Bool = false
    ) {
        self.state = state
        self.url = url
        self.displayLabel = displayLabel
        // The flat `annotations` parameter is the single-frame spelling every
        // caller used before frames were recorded: it means frame 0.
        self.annotationsByFrame = annotationsByFrame
            ?? (annotations.isEmpty ? [:] : [0: annotations])
        self.palette = palette
        self.seriesInstanceUID = seriesInstanceUID
        self.seriesNumber = seriesNumber
        self.annotationsByFrameByImage = annotationsByFrameByImage
        self.isImported = isImported
    }

    /// Every image this state applies to.
    public var referencedImageUIDs: [String] {
        state.referencedSeries.flatMap { $0.referencedImages.map(\.sopInstanceUID) }
    }

    /// The label the reader gave the view, falling back to the coded one.
    public var label: String {
        displayLabel ?? state.presentationLabel ?? "Saved view"
    }

    /// The presentation-state series this object was written into.
    ///
    /// Read from the file rather than from the parsed state: a
    /// ``GrayscalePresentationState`` describes the *images* it applies to and
    /// carries the series UIDs of those, not the series it itself belongs to.
    public let seriesInstanceUID: String

    /// Compared by identity: a presentation state is a SOP Instance, so two
    /// values are the same state exactly when they carry the same UID and came
    /// from the same file. (`GrayscalePresentationState` is not `Equatable` —
    /// `DisplayedArea` holds tuples, which blocks synthesis.)
    public static func == (
        lhs: StoredPresentationState, rhs: StoredPresentationState
    ) -> Bool {
        lhs.url == rhs.url && lhs.state.sopInstanceUID == rhs.state.sopInstanceUID
    }
}

/// Reads and writes saved views for a study.
///
/// Storage is per study, under the app's own directory: one folder per Study
/// Instance UID, one file per presentation state.
public struct PresentationStateStore: Sendable {

    /// Root directory holding one subdirectory per study.
    public let root: URL

    /// `FileManager.default` is reached through a computed property rather than
    /// stored: it is not `Sendable`, and the store is.
    private var fileManager: FileManager { .default }

    /// - Parameter root: Where to keep saved views. Callers normally pass the
    ///   app-support directory; tests pass a temporary one.
    public init(root: URL) {
        self.root = root
    }

    /// The default location: `~/Library/Application Support/DICOMStudio/PresentationStates`.
    public static func applicationSupport() throws -> PresentationStateStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return PresentationStateStore(
            root: base
                .appendingPathComponent("DICOMStudio", isDirectory: true)
                .appendingPathComponent("PresentationStates", isDirectory: true))
    }

    // MARK: - Layout

    /// The directory holding one study's saved views.
    public func directory(forStudy studyInstanceUID: String) -> URL {
        // The UID is used as a path component directly: DICOM UIDs are digits
        // and dots by definition (PS3.5 9.1), so there is nothing to escape.
        root.appendingPathComponent(studyInstanceUID, isDirectory: true)
    }

    // MARK: - Saving

    /// What a save needs to know about one image.
    public struct ImageToSave: Sendable, Equatable {

        /// SOP Class and Instance UID of the image being described.
        public let sopClassUID: String
        public let sopInstanceUID: String

        /// The series that image belongs to.
        public let seriesInstanceUID: String

        /// The view to record for it.
        public let display: ViewerPresentationStateBridge.CapturedDisplay

        /// What the reader drew on it, if anything, keyed by frame.
        ///
        /// Defaulted so every existing caller that saves a window and a zoom
        /// keeps compiling and keeps writing no sidecar.
        public let annotationsByFrame: [Int: [PrintOverlayAnnotation]]

        /// The pseudo-colour palette the image was read through, if any.
        ///
        /// Recorded in the sidecar only — GSPS cannot say "coloured" — so a
        /// view saved off a pseudo-coloured image restores coloured.
        public let palette: PseudoColorPalette?

        /// Every drawing regardless of frame, in frame order — what the
        /// best-effort Graphic Annotation Sequence is written from.
        public var annotations: [PrintOverlayAnnotation] {
            annotationsByFrame.sorted { $0.key < $1.key }.flatMap(\.value)
        }

        /// The image's pixel dimensions, needed to state the drawn annotations
        /// in the GSPS's own units — the overlays are fractions of the image,
        /// and a Graphic Annotation Sequence speaks in pixels. Zero (the
        /// default) writes the sidecar only, as every caller did before the
        /// sequence was written at all.
        public let imageWidth: Int
        public let imageHeight: Int

        /// The image's stored-pixel depth and signedness — what sizes the
        /// Palette Color LUT of a coloured save. The table must hold one entry
        /// per storable pixel value or a conforming viewer indexes past its
        /// end and paints the film one colour. Zero (the default) falls back
        /// to the 8-bit table, which is only right for 8-bit images.
        public let bitsStored: Int
        public let isSigned: Bool

        /// The image's rescale, needed to turn the state's window — carried
        /// in rescaled units — back into the stored-value domain the palette
        /// table is baked over.
        public let rescaleSlope: Double
        public let rescaleIntercept: Double

        /// How many frames the image has.
        ///
        /// What decides whether the written Graphic Annotation Sequence names
        /// frames at all: a drawing on frame 3 of a cine has to say so, or a
        /// conforming viewer shows it on all sixty. One frame — the default —
        /// keeps the un-framed form, which is both correct for a single-frame
        /// image and the exact bytes written before frames were stated.
        public let numberOfFrames: Int

        /// Whether frame numbers belong in this image's annotations.
        var isMultiFrame: Bool { numberOfFrames > 1 }

        /// Photometric Interpretation (0028,0004) of the image, when the caller
        /// knows it.
        ///
        /// Decides the IOD: a Grayscale (or Pseudo-Color) Softcopy Presentation
        /// State "may only be used to reference monochrome images" (PS3.3
        /// A.33.1.1), so any other photometric is saved as a Color Softcopy
        /// Presentation State (A.33.2). `nil` keeps the monochrome reading every
        /// caller had before this was recorded.
        public let photometricInterpretation: String?

        /// Rescale Type (0028,1054) of the image — `HU` for CT — written with
        /// the state's own Modality LUT. `nil` writes `US` (unspecified).
        public let rescaleType: String?

        /// Whether the image is a colour image, so only a Color Softcopy
        /// Presentation State may describe it.
        var isColor: Bool {
            guard let photometric = photometricInterpretation?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")).uppercased(),
                  !photometric.isEmpty else { return false }
            return photometric != "MONOCHROME1" && photometric != "MONOCHROME2"
        }

        /// The Modality LUT the state carries: the image's own rescale.
        ///
        /// PS3.4 N.2.1.1: under a presentation state the image's Modality LUT
        /// "shall not be used", and an absent one is the identity. The window
        /// this app captures is in rescaled units, so a state without the
        /// rescale would window stored values. Left out when the rescale is
        /// the identity (nothing to apply) and for colour images, whose IOD
        /// has no Modality LUT module (Table A.33.2-1).
        var modalityLUT: ModalityLUT? {
            guard !isColor, rescaleSlope != 0,
                  rescaleSlope != 1 || rescaleIntercept != 0 else { return nil }
            return .rescale(slope: rescaleSlope, intercept: rescaleIntercept, type: rescaleType)
        }

        /// The image size the builders write the Type 1 Displayed Area from
        /// when the view records none (PS3.3 Table C.10-4); `nil` when unknown.
        var imageSize: (columns: Int, rows: Int)? {
            imageWidth > 0 && imageHeight > 0 ? (imageWidth, imageHeight) : nil
        }

        public init(
            sopClassUID: String,
            sopInstanceUID: String,
            seriesInstanceUID: String,
            display: ViewerPresentationStateBridge.CapturedDisplay,
            annotations: [PrintOverlayAnnotation] = [],
            annotationsByFrame: [Int: [PrintOverlayAnnotation]]? = nil,
            palette: PseudoColorPalette? = nil,
            imageWidth: Int = 0,
            imageHeight: Int = 0,
            bitsStored: Int = 0,
            isSigned: Bool = false,
            rescaleSlope: Double = 1,
            rescaleIntercept: Double = 0,
            numberOfFrames: Int = 1,
            photometricInterpretation: String? = nil,
            rescaleType: String? = nil
        ) {
            self.sopClassUID = sopClassUID
            self.sopInstanceUID = sopInstanceUID
            self.seriesInstanceUID = seriesInstanceUID
            self.display = display
            // The flat `annotations` parameter is the single-frame spelling —
            // it means frame 0, which is every frame a single-frame image has.
            self.annotationsByFrame = annotationsByFrame
                ?? (annotations.isEmpty ? [:] : [0: annotations])
            self.palette = palette
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
            self.bitsStored = bitsStored
            self.isSigned = isSigned
            self.rescaleSlope = rescaleSlope
            self.rescaleIntercept = rescaleIntercept
            // A file that says nothing about frames has one, and zero or a
            // negative count is not a picture — either way the un-framed form
            // is what gets written.
            self.numberOfFrames = max(1, numberOfFrames)
            self.photometricInterpretation = photometricInterpretation
            self.rescaleType = rescaleType
        }
    }

    /// Writes one saved view: one presentation state per image, all under the
    /// same label and the same study-wide series.
    ///
    /// Saving under a label that already exists replaces it, so a reader who
    /// adjusts a view and saves it again gets one entry in the picker rather
    /// than two.
    ///
    /// - Parameters:
    ///   - images: The images the reader had adjusted. An empty array writes
    ///     nothing.
    ///   - label: What to call the view.
    ///   - patient: Study and patient attributes, read from a source image.
    ///   - creator: Who saved it, if known.
    ///   - created: When — passed in rather than read from the clock so the
    ///     caller stays testable.
    /// - Returns: The saved view, or nil if there was nothing to save.
    @discardableResult
    public func save(
        images: [ImageToSave],
        label: String,
        patient: PresentationStatePatientContext,
        creator: DICOMPersonName? = nil,
        created: Date = Date()
    ) throws -> SavedView? {
        guard !images.isEmpty else { return nil }

        let directory = directory(forStudy: patient.studyInstanceUID)
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true)

        // The series UID has to be read *before* the replace below, or replacing
        // the only saved view of a study would take its series identity with it.
        let seriesInstanceUID = seriesUID(forStudy: patient.studyInstanceUID)

        // Replacing rather than appending: a second save under the same name is
        // the reader correcting the view, not adding another.
        try deleteView(label: label, studyInstanceUID: patient.studyInstanceUID)

        var context = patient
        context.seriesDescription = Self.seriesDescription

        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: created)
        let creationDate = DICOMDate(
            year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
        let creationTime = DICOMTime(
            hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0)

        var stored: [StoredPresentationState] = []

        for (index, image) in images.enumerated() {
            let sopInstanceUID = UIDGenerator.generateSOPInstanceUID().value

            // The drawings, in DICOM's own vocabulary as well as the sidecar's:
            // the sequence is what another viewer can read, the sidecar is what
            // our restore reads (see ``AnnotationSidecar`` for why both exist).
            // Needs the pixel dimensions — callers that pass none keep writing
            // sidecar-only objects.
            //
            // The series reference names the instance and no frame: the
            // window, the zoom and the palette are statements about the whole
            // multi-frame image, and a frame number here would narrow the
            // state to one frame of a cine the reader adjusted entirely.
            // Frames are named where they actually mean something — on the
            // individual drawings below.
            let referencedImage = ReferencedImage(
                sopClassUID: image.sopClassUID,
                sopInstanceUID: image.sopInstanceUID)
            let graphicAnnotations = PrintOverlayAnnotationGSPS.graphicAnnotations(
                from: image.annotationsByFrame,
                imageWidth: image.imageWidth,
                imageHeight: image.imageHeight,
                referencedImage: referencedImage,
                isMultiFrame: image.isMultiFrame)

            // Which presentation state IOD this image needs. A colour image
            // takes the Color Softcopy object (…11.2): GSPS and Pseudo-Color
            // "may only be used to reference monochrome images" (A.33.1.1). A
            // non-grey palette on a monochrome image has to leave in a
            // Pseudo-Color object (…11.3) or it does not leave at all — GSPS
            // has no colour vocabulary, which is why the palette used to
            // survive only in the private sidecar and vanished from every
            // exported study. Grey stays GSPS: same file another viewer
            // already reads, no palette module carrying nothing.
            let colourPalette: PseudoColorPalette? = {
                guard !image.isColor,
                      let palette = image.palette, !palette.isGrayscale else { return nil }
                return palette
            }()
            let sopClassUID = image.isColor
                ? ColorPresentationStateBuilder.sopClassUID
                : colourPalette == nil
                    ? GrayscalePresentationStateBuilder.sopClassUID
                    : PseudoColorPresentationStateBuilder.sopClassUID

            let state = GrayscalePresentationState(
                sopInstanceUID: sopInstanceUID,
                sopClassUID: sopClassUID,
                instanceNumber: index + 1,
                presentationLabel: label,
                presentationCreationDate: creationDate,
                presentationCreationTime: creationTime,
                presentationCreatorsName: creator,
                referencedSeries: [
                    ReferencedSeries(
                        seriesInstanceUID: image.seriesInstanceUID,
                        referencedImages: [referencedImage])
                ],
                modalityLUT: image.modalityLUT,
                voiLUT: image.display.voiLUT,
                presentationLUT: image.display.presentationLUT,
                spatialTransformation: image.display.spatialTransformation,
                displayedArea: image.display.displayedArea,
                graphicLayers: graphicAnnotations.isEmpty
                    ? [] : PrintOverlayAnnotationGSPS.graphicLayers(for: image.annotations),
                graphicAnnotations: graphicAnnotations)

            // The Displayed Area Selection Sequence is Type 1 (Table C.10-4):
            // a view that records no area (the whole image, fitted) is written
            // as the whole image, which the builders do from the image size.
            let dataSet: DataSet
            if image.isColor {
                // Table A.33.2-1 has no Modality, VOI or Presentation LUT
                // module; the builder writes the shared modules and the ICC
                // Profile. An inversion the reader applied is kept in the
                // sidecar, the one place that can say it for a colour image.
                dataSet = ColorPresentationStateBuilder().buildDataSet(
                    from: ColorPresentationState(parsed: state),
                    patient: context,
                    seriesInstanceUID: seriesInstanceUID,
                    seriesNumber: Self.presentationSeriesNumber,
                    imageSize: image.imageSize)
            } else if let colourPalette {
                dataSet = PseudoColorPresentationStateBuilder().buildDataSet(
                    from: state,
                    palette: colourPalette,
                    // The table must cover the image's stored range; with no
                    // depth recorded the 8-bit shape is the only honest guess.
                    pixelDomain: image.bitsStored > 0
                        ? .init(
                            bitsStored: image.bitsStored, isSigned: image.isSigned,
                            rescaleSlope: image.rescaleSlope,
                            rescaleIntercept: image.rescaleIntercept)
                        : nil,
                    patient: context,
                    seriesInstanceUID: seriesInstanceUID,
                    seriesNumber: Self.presentationSeriesNumber,
                    imageSize: image.imageSize)
            } else {
                dataSet = GrayscalePresentationStateBuilder().buildDataSet(
                    from: state,
                    patient: context,
                    seriesInstanceUID: seriesInstanceUID,
                    seriesNumber: Self.presentationSeriesNumber,
                    imageSize: image.imageSize)
            }

            let url = directory.appendingPathComponent("\(sopInstanceUID).dcm")
            let file = DICOMFile.create(
                dataSet: dataSet,
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                transferSyntaxUID: Self.transferSyntaxUID)
            try file.write().write(to: url, options: [.atomic])

            // Written after the object, and non-fatally: a saved view that keeps
            // its window and loses its arrows is a poor outcome, but losing the
            // whole view because a sidecar could not be written is a worse one.
            var drawnByFrame: [Int: [PrintOverlayAnnotation]] = [:]
            for (frame, annotations) in image.annotationsByFrame {
                let drawn = annotations.filter { !$0.isBlank }
                if !drawn.isEmpty { drawnByFrame[frame] = drawn }
            }
            let invertedColour = image.isColor && image.display.presentationLUT == .inverse
            var sidecar = AnnotationSidecar.Contents(
                palette: image.palette, annotationsByFrame: drawnByFrame)
            sidecar.inverted = invertedColour
            try? AnnotationSidecar.write(sidecar, forStateAt: url)

            // The model handed back is what a later read of the file yields:
            // a colour object carries no LUT, and its inversion (if any) comes
            // back from the sidecar.
            let written = image.isColor
                ? Self.replacingPresentationLUT(
                    Self.withoutLUTs(state), with: invertedColour ? .inverse : nil)
                : state
            stored.append(StoredPresentationState(
                state: written, url: url,
                annotationsByFrame: drawnByFrame,
                palette: image.palette,
                seriesInstanceUID: seriesInstanceUID,
                seriesNumber: Self.presentationSeriesNumber))
        }

        return SavedView(label: label, created: created, states: stored)
    }

    // MARK: - Loading

    /// Every saved view for a study, newest first.
    ///
    /// Unreadable files are skipped rather than thrown on: one corrupt object
    /// must not cost the reader the rest of their saved views.
    public func views(forStudy studyInstanceUID: String) -> [SavedView] {
        let directory = directory(forStudy: studyInstanceUID)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }

        let parser = GrayscalePresentationStateParser()
        var stored: [StoredPresentationState] = []

        for url in urls where url.pathExtension.lowercased() == "dcm" {
            guard let file = try? DICOMFile.read(from: url),
                  let state = try? parser.parse(dataSet: file.dataSet) else { continue }
            // Content Label (0070,0080) is CS-valued, so what the reader
            // typed was folded to uppercase when it was written. The unfolded
            // name lives in Content Description (0070,0081) — read it back, or
            // "Lung window" returns as "LUNG WINDOW" and no longer matches the
            // label a delete or a re-save is looking for.
            let displayLabel = file.dataSet.string(for: .contentDescription)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sidecar = AnnotationSidecar.read(forStateAt: url)

            // The palette, from whichever copy survived. The sidecar is
            // authoritative when present — it records the reader's actual
            // choice, grey choices included. When it did not travel (a study
            // exported and re-imported carries only the DICOM), a Pseudo-Color
            // object's own Palette Color LUT names the palette instead: that is
            // the entire point of writing …11.3 rather than a sidecar alone.
            var resolvedState = state
            let palette: PseudoColorPalette?
            if let fromSidecar = sidecar.palette {
                palette = fromSidecar
            } else if let match = Self.paletteMatch(in: file.dataSet) {
                palette = match.palette
                // An inverted view of this IOD has its inversion baked into the
                // table — no Presentation LUT Shape to read — so the state is
                // rebuilt saying INVERSE, or the restore would colour the view
                // and quietly lose the flip.
                if match.inverted, state.presentationLUT == nil {
                    resolvedState = Self.replacingPresentationLUT(state, with: .inverse)
                }
            } else {
                palette = nil
            }
            // A Color Softcopy object has no Presentation LUT; an inversion the
            // reader applied to a colour image travels in the sidecar.
            if sidecar.inverted, resolvedState.presentationLUT == nil {
                resolvedState = Self.replacingPresentationLUT(resolvedState, with: .inverse)
            }

            stored.append(StoredPresentationState(
                state: resolvedState,
                url: url,
                displayLabel: (displayLabel?.isEmpty == false) ? displayLabel : nil,
                annotationsByFrame: sidecar.annotationsByFrame,
                palette: palette,
                seriesInstanceUID: file.dataSet.string(for: .seriesInstanceUID) ?? "",
                seriesNumber: file.dataSet.string(for: .seriesNumber)
                    .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
                annotationsByFrameByImage: sidecar.annotationsByFrameByImage,
                isImported: sidecar.isImported))
        }

        // Grouping by label is what makes several objects one saved view. This
        // is the cost of a single shared series: the label carries the grouping.
        let grouped = Dictionary(grouping: stored) { $0.label }

        return grouped
            .map { label, states in
                SavedView(
                    label: label,
                    created: states.compactMap(Self.creationDate).max(),
                    states: states.sorted {
                        ($0.state.instanceNumber ?? 0) < ($1.state.instanceNumber ?? 0)
                    })
            }
            .sorted { lhs, rhs in
                // Newest first, with ties broken by name so the order is stable.
                switch (lhs.created, rhs.created) {
                case let (left?, right?) where left != right:
                    return left > right
                default:
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
            }
    }

    /// The saved views that say something about one image.
    ///
    /// This is what the viewer's picker lists: a view saved over other images
    /// has nothing to offer this one and is left out.
    public func views(
        forStudy studyInstanceUID: String, image sopInstanceUID: String
    ) -> [SavedView] {
        views(forStudy: studyInstanceUID).filter { $0.covers(image: sopInstanceUID) }
    }

    // MARK: - Deleting

    /// Removes one saved view, by label.
    ///
    /// An imported view leaves a marker behind — see ``declinedMarker(for:)``
    /// — so the study's own copy, still in its folder, is not adopted straight
    /// back on the next open. Deleting it here means "I do not want this
    /// reading offered", and that has to hold across visits.
    public func deleteView(label: String, studyInstanceUID: String) throws {
        for view in views(forStudy: studyInstanceUID) where view.label == label {
            for state in view.states {
                if state.isImported {
                    fileManager.createFile(
                        atPath: Self.declinedMarker(for: state.url).path, contents: nil)
                }
                try? fileManager.removeItem(at: state.url)
                // The sidecar goes with the object. Leaving one behind would
                // outlive its `.dcm` and be picked up by the next save that
                // happened to draw the same SOP Instance UID.
                AnnotationSidecar.delete(forStateAt: state.url)
            }
        }
    }

    /// The file whose presence says an imported object was deleted by hand
    /// and must not be adopted again: `<sopInstanceUID>.declined` beside where
    /// the object was.
    static func declinedMarker(for stateURL: URL) -> URL {
        stateURL.deletingPathExtension().appendingPathExtension("declined")
    }

    /// Removes every saved view for a study.
    public func deleteAll(forStudy studyInstanceUID: String) throws {
        let directory = directory(forStudy: studyInstanceUID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    // MARK: - Adopting the study's own presentation states

    /// The presentation state IODs this store reads: Grayscale (…11.1),
    /// Color (…11.2) and Pseudo-Color (…11.3) Softcopy.
    public static let presentationStateSOPClasses: Set<String> = [
        "1.2.840.10008.5.1.4.1.1.11.1",
        "1.2.840.10008.5.1.4.1.1.11.2",
        "1.2.840.10008.5.1.4.1.1.11.3",
    ]

    /// What the adoption needs to know about an image a state may describe.
    public struct AdoptableImage: Sendable, Equatable {
        public let sopInstanceUID: String
        public let columns: Int
        public let rows: Int
        public let numberOfFrames: Int

        public init(sopInstanceUID: String, columns: Int, rows: Int, numberOfFrames: Int = 1) {
            self.sopInstanceUID = sopInstanceUID
            self.columns = columns
            self.rows = rows
            self.numberOfFrames = max(1, numberOfFrames)
        }
    }

    /// What one adoption pass did.
    public struct AdoptionResult: Sendable, Equatable {
        /// Objects copied into the store this pass.
        public var adopted: [URL] = []
        /// Objects already in the store, left as they were.
        public var alreadyPresent: Int = 0
        /// Files skipped: not a presentation state, unreadable, or describing
        /// no image the study has.
        public var skipped: Int = 0

        public init() {}
    }

    /// Takes the presentation states a study arrived with into the store, so
    /// the viewer offers them the way it offers its own saved views.
    ///
    /// A study from a PACS or another workstation carries its readings as PR
    /// objects in a series of its own — Weasis writes one per series, with
    /// every ruler and label on every image in it. The store only ever listed
    /// what this app had saved, so those readings were classified in the
    /// series pane and shown nowhere. This is the step that was missing.
    ///
    /// Each object is copied under the study, keyed by its SOP Instance UID,
    /// so a second pass over the same study changes nothing — including the
    /// app's own published objects, which are already in the store under the
    /// same UID. Alongside the copy goes a sidecar carrying what the object
    /// says in this app's own vocabulary: the graphic annotations converted
    /// per image and frame, and the display shutters as shutter overlays, so
    /// every downstream reader — viewer, print preview, film — works from the
    /// same channel the app's own drawings use. An object whose sidecar
    /// travelled with it (one this app published) keeps that sidecar instead.
    ///
    /// - Parameters:
    ///   - urls: The candidate files. Anything that is not a presentation
    ///     state is skipped, so a whole study folder may be passed.
    ///   - studyInstanceUID: The study to file them under. An object claiming
    ///     a different study is skipped.
    ///   - images: The study's images by SOP Instance UID, with the pixel
    ///     dimensions the object's pixel-unit coordinates are normalized by.
    ///     An object that describes none of them is skipped.
    @discardableResult
    public func adopt(
        presentationStateFiles urls: [URL],
        studyInstanceUID: String,
        images: [String: AdoptableImage]
    ) -> AdoptionResult {
        var result = AdoptionResult()
        guard !urls.isEmpty, !images.isEmpty else {
            result.skipped = urls.count
            return result
        }
        let parser = GrayscalePresentationStateParser()
        let directory = directory(forStudy: studyInstanceUID)

        for url in urls where url.pathExtension.lowercased() == "dcm" || url.pathExtension.isEmpty {
            guard let file = try? DICOMFile.read(from: url),
                  let sopClass = file.dataSet.string(for: .sopClassUID)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  Self.presentationStateSOPClasses.contains(sopClass),
                  let sopInstanceUID = file.dataSet.string(for: .sopInstanceUID)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !sopInstanceUID.isEmpty,
                  let state = try? parser.parse(dataSet: file.dataSet)
            else { result.skipped += 1; continue }

            // The object's own study, when it states one, must be this one:
            // a PR filed under another study describes nothing here.
            if let claimed = file.dataSet.string(for: .studyInstanceUID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !claimed.isEmpty, claimed != studyInstanceUID {
                result.skipped += 1
                continue
            }

            let referenced = Set(state.referencedSeries.flatMap {
                $0.referencedImages.map(\.sopInstanceUID) })
            let described = referenced.compactMap { images[$0] }
            guard !described.isEmpty else { result.skipped += 1; continue }

            let destination = directory.appendingPathComponent("\(sopInstanceUID).dcm")
            if fileManager.fileExists(atPath: destination.path)
                || fileManager.fileExists(atPath: Self.declinedMarker(for: destination).path) {
                result.alreadyPresent += 1
                continue
            }

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: destination)
            } catch {
                result.skipped += 1
                continue
            }

            // A sidecar that travelled with the object is the app's own record
            // of what was drawn — authoritative, as it is for the store's own
            // copy. Anything else gets one built from what the object says.
            let travelled = AnnotationSidecar.read(forStateAt: url)
            if !travelled.isEmpty {
                var contents = travelled
                contents.isImported = true
                try? AnnotationSidecar.write(contents, forStateAt: destination)
            } else {
                let contents = Self.importedSidecar(for: state, images: described)
                try? AnnotationSidecar.write(contents, forStateAt: destination)
            }
            result.adopted.append(destination)
        }
        return result
    }

    /// What an adopted object says, in the app's own vocabulary.
    static func importedSidecar(
        for state: GrayscalePresentationState,
        images: [AdoptableImage]
    ) -> AnnotationSidecar.Contents {
        var contents = AnnotationSidecar.Contents()
        contents.isImported = true
        for image in images {
            var byFrame = PrintOverlayAnnotationGSPS.overlays(
                from: state,
                forImage: image.sopInstanceUID,
                imageWidth: image.columns,
                imageHeight: image.rows,
                numberOfFrames: image.numberOfFrames)
            // Shutters are a statement about the whole image, every frame.
            let shutters = state.shutters.compactMap {
                Self.shutterOverlay($0, imageWidth: image.columns, imageHeight: image.rows)
            }
            if !shutters.isEmpty {
                for frame in 0..<image.numberOfFrames {
                    byFrame[frame, default: []].insert(
                        contentsOf: shutters.map { var copy = $0; copy.id = UUID(); return copy },
                        at: 0)
                }
            }
            if !byFrame.isEmpty {
                contents.annotationsByFrameByImage[image.sopInstanceUID] = byFrame
            }
        }
        return contents
    }

    /// A display shutter as the overlay that paints its outside.
    ///
    /// The presentation value is a 16-bit P-value (PS3.3 Table C.7-17a); absent,
    /// the shutter is black, which is what every viewer shows for it. Bitmap
    /// shutters need the overlay plane they name, which the sidecar cannot
    /// carry — those are left to the overlay-plane renderer.
    ///
    /// Shutter edges, centres and vertices are *pixel positions* — "with
    /// respect to pixels in the image given as column/row" (Table C.7-17a) —
    /// counted from 1, and the edge pixels are inside the open region (the
    /// same reading ``DisplayShutter/contains(column:row:)`` applies). Pixel
    /// `c` covers `c − 1 ..< c` of the image's width, so a rectangle opens from
    /// the left edge of its first pixel to the right edge of its last, and a
    /// centre or vertex sits at the middle of its pixel.
    static func shutterOverlay(
        _ shutter: DisplayShutter, imageWidth: Int, imageHeight: Int
    ) -> PrintOverlayAnnotation? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let width = Double(imageWidth)
        let height = Double(imageHeight)
        let grey = Double(shutter.presentationValue ?? 0) / 65535
        let color = PrintOverlayColor(red: grey, green: grey, blue: grey)
        func point(x: Double, y: Double) -> PrintOverlayPoint {
            PrintOverlayPoint(x: x / width, y: y / height)
        }
        /// The middle of 1-based pixel (column, row).
        func centre(_ column: Int, _ row: Int) -> PrintOverlayPoint {
            point(x: Double(column) - 0.5, y: Double(row) - 0.5)
        }
        switch shutter {
        case .rectangular(let left, let right, let top, let bottom, _):
            return PrintOverlayAnnotation(
                shape: .shutter,
                points: [point(x: Double(left - 1), y: Double(top - 1)),
                         point(x: Double(right), y: Double(bottom))],
                filled: false, color: color)
        case .circular(let centerColumn, let centerRow, let radius, _):
            // The radius is "a number of pixels along the row direction".
            return PrintOverlayAnnotation(
                shape: .shutter,
                points: [centre(centerColumn, centerRow),
                         centre(centerColumn + radius, centerRow)],
                filled: true, color: color)
        case .polygonal(let vertices, _):
            guard vertices.count >= 3 else { return nil }
            return PrintOverlayAnnotation(
                shape: .shutter, points: vertices.map { centre($0.column, $0.row) },
                filled: false, color: color)
        case .bitmap:
            return nil
        }
    }

    // MARK: - Publishing into the study

    /// One presentation-state object as it now sits in the study.
    public struct PublishedInstance: Sendable, Equatable {

        /// SOP Class and Instance UID of the presentation state itself.
        public let sopClassUID: String
        public let sopInstanceUID: String

        /// Where it was written.
        public let url: URL

        /// Instance Number within the presentation-state series.
        public let instanceNumber: Int

        /// The images it describes, so a caller can say what it applies to.
        public let referencedImageUIDs: [String]

        public init(
            sopClassUID: String,
            sopInstanceUID: String,
            url: URL,
            instanceNumber: Int,
            referencedImageUIDs: [String]
        ) {
            self.sopClassUID = sopClassUID
            self.sopInstanceUID = sopInstanceUID
            self.url = url
            self.instanceNumber = instanceNumber
            self.referencedImageUIDs = referencedImageUIDs
        }
    }

    /// A saved view, published as a series of the study.
    ///
    /// Everything a library needs to file the series without re-reading the
    /// objects: the identity of the series, what to call it, and its instances.
    public struct PublishedSeries: Sendable, Equatable {

        /// The study the series belongs to.
        public let studyInstanceUID: String

        /// Series Instance UID — the same one the store has been using for this
        /// study's presentation states all along, so publishing twice adds
        /// objects to one series rather than making a second.
        public let seriesInstanceUID: String

        /// Series Number and Description, matching what is in the objects.
        public let seriesNumber: Int
        public let seriesDescription: String

        /// "PR", by definition of a presentation state.
        public let modality: String

        /// The reference ID a reader quotes to name this view.
        public let referenceID: String

        /// The view's own name.
        public let label: String

        /// The objects written, one per image the view covers.
        public let instances: [PublishedInstance]

        public init(
            studyInstanceUID: String,
            seriesInstanceUID: String,
            seriesNumber: Int,
            seriesDescription: String,
            modality: String,
            referenceID: String,
            label: String,
            instances: [PublishedInstance]
        ) {
            self.studyInstanceUID = studyInstanceUID
            self.seriesInstanceUID = seriesInstanceUID
            self.seriesNumber = seriesNumber
            self.seriesDescription = seriesDescription
            self.modality = modality
            self.referenceID = referenceID
            self.label = label
            self.instances = instances
        }
    }

    /// Publishes a saved view as a series of the study, at a chosen location.
    ///
    /// The objects the store already holds *are* conformant GSPS files sitting
    /// in a "PR" series — what keeps them out of the study is only where they
    /// live: an app-support directory the library does not index. Publishing is
    /// therefore a copy, not a conversion, and deliberately so. Rebuilding the
    /// objects here would mean two code paths that must agree on what a saved
    /// view is, and the second one would drift.
    ///
    /// The destination is the caller's: a study imported from a folder gets the
    /// series written beside its own files, which is what makes the pane show
    /// it after the next scan. The store's own copy is left alone — publishing
    /// hands the study a copy, it does not move the reader's saved view out of
    /// the app.
    ///
    /// - Parameters:
    ///   - label: The view to publish.
    ///   - studyInstanceUID: The study it belongs to.
    ///   - destination: Directory to write into. Created if it does not exist.
    /// - Returns: The published series, or nil if there is no such view.
    @discardableResult
    public func publish(
        label: String,
        studyInstanceUID: String,
        into destination: URL
    ) throws -> PublishedSeries? {
        guard let view = views(forStudy: studyInstanceUID)
            .first(where: { $0.label == label }) else { return nil }
        guard !view.states.isEmpty else { return nil }

        try fileManager.createDirectory(
            at: destination, withIntermediateDirectories: true)

        // Objects of *this* view already in the study, from an earlier publish.
        //
        // They cannot be found by filename: saving under an existing label
        // replaces the store's copy with freshly minted SOP Instance UIDs, so
        // the new objects land beside the old ones rather than over them. They
        // are found by reading what is there and keeping whatever carries this
        // view's label, which is the same thing that groups a saved view
        // everywhere else.
        let superseded = publishedObjects(ofView: view.label, in: destination)

        var instances: [PublishedInstance] = []

        for state in view.states {
            let sopInstanceUID = state.state.sopInstanceUID
            let url = destination.appendingPathComponent("\(sopInstanceUID).dcm")

            // Overwrite rather than skip: publishing the same view twice is a
            // reader re-publishing after adjusting it, and a stale object left
            // in place would be the one the study kept showing.
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.copyItem(at: state.url, to: url)

            // The sidecar travels with the object, so a published series
            // restores the reader's arrows the same way the store's copy does.
            AnnotationSidecar.copy(forStateAt: state.url, toStateAt: url)

            instances.append(PublishedInstance(
                // The state's own class: a coloured view published a
                // Pseudo-Color object, and calling it GSPS here would misfile
                // it in every index built from this record.
                sopClassUID: state.state.sopClassUID,
                sopInstanceUID: sopInstanceUID,
                url: url,
                instanceNumber: state.state.instanceNumber ?? (instances.count + 1),
                referencedImageUIDs: state.referencedImageUIDs))
        }

        // Whatever the re-publish did not just write is a leftover of the view
        // as it used to be. Removed last, so a failure partway through copying
        // leaves the reader with both copies rather than neither.
        let written = Set(instances.map(\.url.standardizedFileURL))
        for url in superseded where !written.contains(url.standardizedFileURL) {
            try? fileManager.removeItem(at: url)
            AnnotationSidecar.delete(forStateAt: url)
        }

        return PublishedSeries(
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: view.states.first?.seriesInstanceUID
                ?? seriesUID(forStudy: studyInstanceUID),
            seriesNumber: Self.presentationSeriesNumber,
            seriesDescription: Self.seriesDescription,
            modality: GrayscalePresentationStateBuilder.modality,
            referenceID: view.referenceID,
            label: view.label,
            instances: instances)
    }

    /// The presentation states already in a study folder that carry a label.
    ///
    /// Reads the objects rather than trusting filenames: a re-saved view is
    /// written under new SOP Instance UIDs, so the file that has to be replaced
    /// is not the one the new object would be named after.
    ///
    /// Only presentation states are considered — the destination is the study's
    /// own folder, full of images this must never touch.
    private func publishedObjects(ofView label: String, in destination: URL) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: destination, includingPropertiesForKeys: nil) else { return [] }

        return urls.filter { url in
            guard url.pathExtension.lowercased() == "dcm",
                  let file = try? DICOMFile.read(from: url),
                  let sopClass = file.dataSet.string(for: .sopClassUID),
                  Self.presentationStateSOPClasses.contains(sopClass)
            else { return false }
            // Content Description holds the reader's own wording; Presentation
            // Label is the CS-folded one. Matching either is what makes this
            // agree with the grouping `views(forStudy:)` does.
            let described = file.dataSet.string(for: .contentDescription)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return described == label
                || file.dataSet.string(for: .contentLabel)
                    == GrayscalePresentationStateBuilder.contentLabel(from: label)
        }
    }

    // MARK: - Series identity

    /// The Series Instance UID this study's presentation states share.
    ///
    /// Recovered from the objects already on disk, so there is no side file to
    /// keep in step; a study with nothing saved yet gets a fresh one. This is
    /// what makes "one shared series per study" true however many views the
    /// reader accumulates.
    private func seriesUID(forStudy studyInstanceUID: String) -> String {
        let directory = directory(forStudy: studyInstanceUID)
        if let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension.lowercased() == "dcm" {
                if let file = try? DICOMFile.read(from: url),
                   let uid = file.dataSet.string(for: .seriesInstanceUID),
                   !uid.isEmpty {
                    return uid
                }
            }
        }
        return UIDGenerator.generateSeriesInstanceUID().value
    }

    /// Reads the palette out of a Pseudo-Color presentation state's own data.
    ///
    /// UID first: Palette Color Lookup Table UID (0028,1199) names one of the
    /// standard's eight palettes outright. Failing that, the table itself is
    /// compared against the catalogue — which is how our computed palettes
    /// (Viridis and friends, which have no UID to carry) come back by name.
    /// `nil` for a grayscale object (no LUT to read) or a foreign table.
    static func paletteMatch(in dataSet: DataSet) -> PseudoColorPalette.Match? {
        guard dataSet.string(for: .sopClassUID)
                == PseudoColorPresentationStateBuilder.sopClassUID else { return nil }

        if let uid = dataSet.string(for: .paletteColorLookupTableUID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let palette = PseudoColorPalette.allCases.first(
               where: { $0.wellKnownSOPInstanceUID == uid }) {
            // The UID is only ever written uninverted — a reversed table is no
            // longer the table the UID names — so inverted is false by
            // construction here.
            return PseudoColorPalette.Match(palette: palette, inverted: false)
        }

        guard let lut = dataSet.paletteColorLUT() else { return nil }
        return PseudoColorPalette.matching(lut)
    }

    /// The same state with no Modality, VOI or Presentation LUT — what a Color
    /// Softcopy object reads back as (Table A.33.2-1 has none of the modules).
    static func withoutLUTs(_ state: GrayscalePresentationState) -> GrayscalePresentationState {
        GrayscalePresentationState(
            sopInstanceUID: state.sopInstanceUID,
            sopClassUID: state.sopClassUID,
            instanceNumber: state.instanceNumber,
            presentationLabel: state.presentationLabel,
            presentationDescription: state.presentationDescription,
            presentationCreationDate: state.presentationCreationDate,
            presentationCreationTime: state.presentationCreationTime,
            presentationCreatorsName: state.presentationCreatorsName,
            referencedSeries: state.referencedSeries,
            spatialTransformation: state.spatialTransformation,
            displayedArea: state.displayedArea,
            graphicLayers: state.graphicLayers,
            graphicAnnotations: state.graphicAnnotations,
            shutters: state.shutters,
            shutterPresentationColor: state.shutterPresentationColor)
    }

    /// The same state with a different Presentation LUT — needed because the
    /// model is immutable and the Pseudo-Color and Color read paths have to
    /// restore an inversion the object itself cannot state.
    static func replacingPresentationLUT(
        _ state: GrayscalePresentationState,
        with presentationLUT: PresentationLUT?
    ) -> GrayscalePresentationState {
        GrayscalePresentationState(
            sopInstanceUID: state.sopInstanceUID,
            sopClassUID: state.sopClassUID,
            instanceNumber: state.instanceNumber,
            presentationLabel: state.presentationLabel,
            presentationDescription: state.presentationDescription,
            presentationCreationDate: state.presentationCreationDate,
            presentationCreationTime: state.presentationCreationTime,
            presentationCreatorsName: state.presentationCreatorsName,
            referencedSeries: state.referencedSeries,
            modalityLUT: state.modalityLUT,
            voiLUT: state.voiLUT,
            presentationLUT: presentationLUT,
            spatialTransformation: state.spatialTransformation,
            displayedArea: state.displayedArea,
            graphicLayers: state.graphicLayers,
            graphicAnnotations: state.graphicAnnotations,
            shutters: state.shutters,
            shutterPresentationColor: state.shutterPresentationColor)
    }

    private static func creationDate(_ stored: StoredPresentationState) -> Date? {
        guard let date = stored.state.presentationCreationDate else { return nil }
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        if let time = stored.state.presentationCreationTime {
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
        }
        return Calendar(identifier: .gregorian).date(from: components)
    }

    // MARK: - Constants

    /// Series Number of the presentation-state series. High enough not to
    /// collide with a modality's own numbering.
    static let presentationSeriesNumber = 9001

    static let seriesDescription = "Presentation States"

    /// Explicit VR Little Endian — what a GSPS is normally stored as, and what
    /// keeps the files readable by anything else.
    public static let transferSyntaxUID = "1.2.840.10008.1.2.1"
}
