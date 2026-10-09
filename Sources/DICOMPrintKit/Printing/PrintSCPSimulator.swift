// NEMA-verified: 2026a, checked 2026-09-29 — film box built with the job's own Image Display Format (PS3.3 2026a C.13.3, C.13.5.1; was the bounding STANDARD grid); image box SOP class per PS3.6 Table A-1 (1.2.840.10008.5.1.1.4 / .4.1, resolved in DICOMNetwork)
//
// PrintSCPSimulator.swift
// DICOMPrintKit
//
// The composer dev loop: a film, composed exactly as the emulator would compose
// it, without a network in the way.
//
// The images go through the same `PrintImagePreparer` an SCU sends them through
// and the sheet comes out of the same `FilmComposer` the SCP composes with, so
// what this produces is what `dicom-print send` into `dicom-printscp serve`
// produces — minus the DIMSE round trip. That makes it useful for iterating on
// layout and density without standing up two processes, and it is the reason
// `dicom-printscp simulate` and any future in-app "preview a received film"
// share one implementation.
//

import Foundation
import DICOMCore
import DICOMNetwork

/// Composes films locally from DICOM files, bypassing the network.
public struct PrintSCPSimulator: Sendable {

    /// A diagnostic line emitted while preparing images.
    public typealias ProgressHandler = @Sendable (String) -> Void

    public init() {}

    /// Prepares `paths` and composes them into one or more film sheets.
    ///
    /// Films spill exactly as they do on the wire: images fill the layout's
    /// cells, and a new film box starts when the grid is full.
    ///
    /// - Parameters:
    ///   - paths: DICOM files, in the order they should be placed.
    ///   - request: The job whose layout, film size and pixel options apply —
    ///     the SCU-side request type, so a simulated film and a printed film are
    ///     described by the same values.
    ///   - settings: The emulator settings that drive composition.
    ///   - callingAETitle: The AE title recorded on the composed films.
    ///   - onProgress: Optional per-image diagnostic line.
    /// - Throws: `PrintRequestError` for unreadable or undecodable inputs, and
    ///   `FilmCompositionError` when a sheet cannot be rasterized.
    public func composeFilms(
        paths: [String],
        request: PrintJobRequest,
        settings: PrintSCPSettings,
        callingAETitle: String = "SIMULATE",
        onProgress: ProgressHandler? = nil
    ) async throws -> [ComposedFilm] {
        let images = try await PrintImagePreparer().prepare(
            paths: paths, request: request, onProgress: onProgress)
        return try composeFilms(
            images: images,
            request: request,
            settings: settings,
            callingAETitle: callingAETitle)
    }

    /// Composes already-prepared images, for callers that hold pixels rather
    /// than paths (the app's viewer selection).
    public func composeFilms(
        images: [PreparedPrintImage],
        request: PrintJobRequest,
        settings: PrintSCPSettings,
        callingAETitle: String = "SIMULATE"
    ) throws -> [ComposedFilm] {
        guard !images.isEmpty else { return [] }

        let plan = request.plan(forImageCount: images.count)
        // FR-003: the job's scaling mode composes here exactly as it would
        // print — fill and true size through the wire attributes each image
        // box carries, stretch and alignment as the local placement they are.
        let boxOptions = request.imageBoxOptions(for: images)
        let composer = FilmComposer(
            configuration: settings.makeComposerConfiguration().withPlacement(
                alignment: request.cellAlignment,
                stretch: request.scalingMode == .stretch))
        let sessionUID = UIDGenerator.generateSOPInstanceUID().value
        let session = FilmSession(
            sopInstanceUID: sessionUID,
            numberOfCopies: request.copies,
            printPriority: request.priority,
            mediumType: request.mediumType,
            filmDestination: request.filmDestination,
            filmSessionLabel: request.sessionLabel)
        let layout = PrintLayout(rows: plan.layout.rows, columns: plan.layout.columns)
        // Named after the pixels, not the request. A saved film is what the
        // printer would have received, and the SCU moves a job carrying colour
        // frames onto Basic Colour whatever the request said
        // (`PrintWorkflow.reconcilingColorMode`) — a box labelled grayscale
        // while holding three samples per pixel is a state no real printer
        // could be in, and it makes the saved film disagree with the print.
        let hasColorFrames = images.contains { $0.descriptor.samplesPerPixel > 1 }
        let sopClassUID = (request.colorMode == .color || hasColorFrames)
            ? basicColorImageBoxSOPClassUID
            : basicGrayscaleImageBoxSOPClassUID

        var films: [ComposedFilm] = []
        for filmIndex in 0..<plan.filmCount {
            let indices = plan.imageIndices(onFilm: filmIndex)
            let boxes = (0..<plan.cellsPerFilm).map { cell -> ReceivedImageBox in
                let imageIndex = indices.lowerBound + cell
                let box = imageIndex < boxOptions.count
                    ? boxOptions[imageIndex] : PrintImageBoxOptions()
                return ReceivedImageBox(
                    sopInstanceUID: UIDGenerator.generateSOPInstanceUID().value,
                    sopClassUID: sopClassUID,
                    content: ImageBoxContent(
                        imagePosition: UInt16(cell + 1),
                        polarity: request.polarity,
                        requestedImageSize: box.requestedImageSize,
                        requestedDecimateCropBehavior: box.requestedDecimateCropBehavior),
                    image: imageIndex < indices.upperBound ? images[imageIndex].descriptor : nil)
            }

            // The job's own Image Display Format, not the grid that bounds
            // it: a ROW\ or COL\ film has fewer boxes than its bounding grid,
            // and the format defines the boxes (PS3.3 C.13.3) and their
            // numbering (C.13.5.1). Composed from the
            // grid, a `ROW\1,2` film came out as `STANDARD\2,2` — four cells
            // for three images, laid out as the printer would never lay them.
            let filmBox = FilmBox(
                sopInstanceUID: UIDGenerator.generateSOPInstanceUID().value,
                imageDisplayFormat: plan.displayFormat.raw,
                filmOrientation: plan.filmOrientation,
                filmSizeID: plan.filmSize,
                magnificationType: request.magnificationType,
                borderDensity: request.borderDensity,
                emptyImageDensity: request.emptyImageDensity,
                trimOption: request.trimOption,
                configurationInformation: request.configurationInformation,
                imageBoxSOPInstanceUIDs: boxes.map(\.sopInstanceUID))

            let received = ReceivedFilm(
                printJobUID: UIDGenerator.generateSOPInstanceUID().value,
                filmSession: session,
                filmBox: filmBox,
                layout: layout,
                imageBoxes: boxes,
                presentationLUTShape: request.presentationLUTShape,
                annotationDisplayFormatID: request.annotationDisplayFormatID,
                // Per film: a job spilling onto a second sheet can be a second
                // study, and each sheet has to name the patient it carries.
                annotations: request.printOptions.annotations(forFilm: filmIndex),
                callingAETitle: callingAETitle)

            films.append(try composer.compose(received))
        }
        return films
    }
}
