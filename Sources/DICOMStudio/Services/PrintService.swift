// PrintService.swift
// DICOMStudio
//
// DICOM Studio — DICOM print execution.
//
// A thin adapter over DICOMPrintKit: it turns the app's marked frames into
// prepared film images and runs the job. No DIMSE logic and no pixel
// preparation live here — both come from the shared print core, so the app and
// the dicom-print CLI put identical bytes on film.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: an adapter over DICOMPrintKit's
// PrintImagePreparer / PrintWorkflow and DICOMNetwork's DICOMVerificationService; the Film Size and
// orientation it pads cells against come from the request's enums, verified in DICOMNetwork.

import Foundation
import DICOMCore
import DICOMKit
import DICOMNetwork
import DICOMPrintKit

/// Executes DICOM print jobs on behalf of the app.
public struct PrintService: Sendable {

    /// Receives console lines as a job runs.
    public typealias DiagnosticHandler = @Sendable (PrintDiagnostic) -> Void

    /// Receives progress updates as a job runs.
    public typealias ProgressHandler = @Sendable (PrintProgress) -> Void

    private let preparer: PrintImagePreparer

    public init(preparer: PrintImagePreparer = PrintImagePreparer()) {
        self.preparer = preparer
    }

    // MARK: - Preparation

    /// Prepares the marked frames for printing, in marked order.
    ///
    /// Each mark carries its own frame index — and, when the viewer supplied
    /// one, its own window/level — so a request-wide frame selection would be
    /// wrong here. Every item is prepared under a request specialized to it.
    ///
    /// - Parameters:
    ///   - items: The marked frames, in film-cell order.
    ///   - request: The job settings the print sheet produced.
    ///   - useViewerWindow: When `true` (the default) a mark's captured window
    ///     overrides the file's own window, so the film matches the screen. The
    ///     request's explicit window still wins over both.
    ///   - applyViewerPresentation: When `true` (the default) the mark's zoom,
    ///     pan, rotation, flip and inversion are baked into the film pixels.
    ///     Cropping and permutation happen on the full-resolution decoded frame,
    ///     so a zoomed print keeps the modality's detail. Ignored for `raw`
    ///     requests, whose whole point is untouched stored pixels.
    ///   - annotations: Identification to burn into each frame's corners, keyed
    ///     by mark ID. Empty leaves the pixels alone. Burning is how film carries
    ///     a patient's name reliably: a DICOM printer draws annotation boxes to
    ///     its own layout, and many ignore them entirely.
    ///
    ///     Per mark rather than per file, because the same file can be marked
    ///     onto two films and each mark is captioned on its own.
    ///   - drawnAnnotations: The text and arrows a reader drew, keyed by mark
    ///     ID — per mark rather than per file, because the same image can be
    ///     marked onto two films. Burned into the pixels here, which is the
    ///     one place they become pixels: on screen they are a separate,
    ///     editable layer (`PrintSelectionModel/cellAnnotations`), but a film
    ///     has nothing to carry a layer in, so what is sent has to hold them.
    ///     Empty leaves the pixels alone — which is what the print sheet
    ///     passes when the reader has turned burning off.
    ///   - onProgress: Optional per-frame diagnostic line.
    public func prepare(
        items: [PrintSelectionItem],
        request: PrintJobRequest,
        useViewerWindow: Bool = true,
        applyViewerPresentation: Bool = true,
        annotations: [String: PrintCornerAnnotation] = [:],
        annotationStyle: PrintAnnotationStyle = .automatic,
        drawnAnnotations: [String: [PrintOverlayAnnotation]] = [:],
        onProgress: PrintImagePreparer.ProgressHandler? = nil
    ) async throws -> [PreparedPrintImage] {
        var prepared: [PreparedPrintImage] = []

        // The corner caption is held to the corners of the film *cell*, as the
        // preview draws it; on the wire the image box is all there is to draw
        // into. A fitted frame is therefore letterboxed to its cell's shape
        // before the caption is burned — the picture lands exactly where the
        // printer's own letterbox would have put it, and the caption falls at
        // the cell's corners rather than floating against the picture's edge.
        // Fit scaling only: fill and stretch cover the cell, so there is no
        // letterbox to cross, and padding a true-size frame would change the
        // physical size the film was asked to hold.
        let cellShapes: [FilmCell]
        if !request.raw, request.scalingMode == .fitToFilm, !annotations.isEmpty {
            let sheet = FilmSheet(filmSize: request.effectiveFilmSize,
                                  orientation: request.effectiveFilmOrientation,
                                  dpi: 25.4)
            cellShapes = request.plan(forImageCount: items.count).cells(
                onSheetOfWidth: sheet.widthMillimeters,
                height: sheet.heightMillimeters)
        } else {
            cellShapes = []
        }

        // Files are re-read per mark rather than cached: marks routinely span
        // whole series, and holding every decoded frame would dwarf the film.
        for (itemIndex, item) in items.enumerated() {
            var itemRequest = request
            itemRequest.frameSelection = .single(item.frameIndex + 1)
            // The cell's own palette, since colour is a per-cell choice like the
            // window: a film can hold a colourised PET beside a grey CT, and
            // each cell is prepared with what it was given. The film-wide
            // default has already been folded into the marks by the sheet, so
            // there is nothing to resolve here.
            //
            // Only when the film is applying viewer presentations at all — with
            // that switch off the arrangement is deliberately dropped, and
            // colouring the cell anyway would apply half of a state the rest of
            // the film is ignoring.
            if applyViewerPresentation, !request.raw {
                itemRequest.palette = item.presentation?.palette
            }
            if request.windowSettings == nil, useViewerWindow, !request.raw,
               let center = item.windowCenter, let width = item.windowWidth, width >= 1 {
                // A mark carries the viewer's window, which is in stored values:
                // the renderer works on stored pixels, so `applyPreset` and
                // `applyDefaultWindow` divide the header's output-unit window
                // through the rescale pair before holding it. The preparer
                // windows *after* rescaling, so it is told which space these
                // numbers are in rather than left to assume the wrong one — on
                // a CT with a −1024 (or −8192) intercept that assumption puts
                // the window clear of every pixel and prints a black cell.
                itemRequest.windowSettings = WindowSettings(center: center, width: width)
                itemRequest.windowSpace = item.windowSpace
            }
            let frames = try await preparer.prepare(
                paths: [item.filePath],
                request: itemRequest,
                onProgress: onProgress
            )
            var arranged: [PreparedPrintImage]
            if applyViewerPresentation, !request.raw,
               let presentation = item.presentation, !presentation.isIdentity {
                // The film reads the crop with the geometry the job scales by,
                // so a filled cell prints the panned crop the preview shows.
                arranged = frames.map {
                    $0.applying(presentation,
                                covers: request.scalingMode == .fillToFilm,
                                onProgress: onProgress)
                }
            } else {
                arranged = frames
            }

            // Burned last, on the pixels as they will be sent: cropping or
            // rotating afterwards would take the caption with it, and a
            // half-rotated patient name is worse than none. The reader's own
            // drawing goes on first and the identification caption over it — the
            // caption is the one thing on the film that must stay legible, and an
            // arrow drawn into a corner would otherwise cover it.
            //
            // Burning is the *output* path only. On screen — the viewer and the
            // film preview — the same annotations are a separate layer over the
            // picture, so they stay editable; see `PrintSelectionModel
            // .cellAnnotations`. Film and file are where they become pixels,
            // because a film has no layer to carry them in.
            #if canImport(CoreGraphics)
            if !request.raw, let overlays = drawnAnnotations[item.id], !overlays.isEmpty {
                // The frames handed to the burner have already been cropped,
                // turned and mirrored, while the annotations are still in the
                // *original* image's fractions — so the arrangement goes with
                // them or the mark is burned wherever that fraction happens to
                // land in the turned buffer. Measured against the frame as it
                // arrived from the preparer, which is the space those fractions
                // are in; `frames` is that, before `applying` above.
                let orientation = frames.first.map {
                    PrintOverlayOrientation(
                        presentation: (applyViewerPresentation && !request.raw
                                       ? item.presentation : nil) ?? ViewerPresentation(),
                        imageWidth: Int($0.descriptor.columns),
                        imageHeight: Int($0.descriptor.rows),
                        covers: request.scalingMode == .fillToFilm)
                }
                arranged = arranged.map {
                    ImageAnnotationBurner.burning(
                        overlays: overlays, into: $0, orientation: orientation)
                }
            }
            if !request.raw, let corners = annotations[item.id], !corners.isEmpty {
                // Cells are consumed in film order, spilling over per film —
                // the same order the SCU fills image boxes in — so a ROW/COL
                // layout pads each frame to its *own* cell's shape.
                if !cellShapes.isEmpty {
                    let cell = cellShapes[itemIndex % cellShapes.count]
                    if !cell.isEmpty {
                        arranged = arranged.map {
                            $0.padded(toCellAspectRatio: cell.width / cell.height)
                        }
                    }
                }
                arranged = arranged.map {
                    ImageAnnotationBurner.burning(corners: corners, into: $0, style: annotationStyle)
                }
            }
            #endif

            prepared.append(contentsOf: arranged)
        }
        return prepared
    }

    // MARK: - Execution

    /// Runs the pre-flight checks the request asks for (C-ECHO, printer status).
    public func preflight(
        profile: PrinterProfile,
        request: PrintJobRequest,
        diagnostics: DiagnosticHandler? = nil
    ) async throws {
        try await PrintWorkflow.preflight(
            configuration: profile.printConfiguration(),
            request: request,
            diagnostics: diagnostics
        )
    }

    /// Prints prepared images, honoring the request's retry policy.
    public func print(
        images: [PreparedPrintImage],
        profile: PrinterProfile,
        request: PrintJobRequest,
        diagnostics: DiagnosticHandler? = nil,
        progress: ProgressHandler? = nil
    ) async throws -> PrintResult {
        try await PrintWorkflow.execute(
            configuration: profile.printConfiguration(),
            request: request,
            images: images,
            diagnostics: diagnostics,
            progress: progress
        )
    }

    // MARK: - Printer queries

    /// C-ECHO the printer AE (the "Test Connection" action).
    public func verify(profile: PrinterProfile) async throws -> Bool {
        let config = profile.printConfiguration(probe: true)
        return try await DICOMVerificationService.verify(
            host: config.host,
            port: config.port,
            callingAE: config.callingAETitle,
            calledAE: config.calledAETitle,
            timeout: config.timeout
        )
    }

    /// Whether this printer can carry film-level annotation text (the patient
    /// footer). Costs one short association, and is asked before the frames are
    /// prepared because the answer decides whether they are captioned.
    public func supportsAnnotationBoxes(profile: PrinterProfile) async -> Bool {
        await PrintWorkflow.supportsAnnotationBoxes(
            configuration: profile.printConfiguration())
    }

    /// N-GET the printer's status.
    public func printerStatus(profile: PrinterProfile) async throws -> PrinterStatus {
        try await PrintWorkflow.printerStatus(
            configuration: profile.printConfiguration(probe: true))
    }

    /// N-GET the execution status of a submitted print job.
    public func jobStatus(profile: PrinterProfile, printJobUID: String) async throws -> DICOMNetwork.PrintJobStatus {
        try await PrintWorkflow.jobStatus(
            configuration: profile.printConfiguration(),
            printJobUID: printJobUID
        )
    }
}

// MARK: - Job status seam

/// Answers print-job status queries — the seam that lets the history pane's
/// re-query be tested without a printer on the network.
public protocol PrintJobStatusQuerying: Sendable {
    func jobStatus(profile: PrinterProfile, printJobUID: String) async throws -> DICOMNetwork.PrintJobStatus
}

extension PrintService: PrintJobStatusQuerying {}
