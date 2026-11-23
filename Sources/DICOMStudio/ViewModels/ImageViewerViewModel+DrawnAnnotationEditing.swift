// ImageViewerViewModel+DrawnAnnotationEditing.swift
// DICOMStudio
//
// Editing the drawn annotations of the image on screen — the viewer-side twin
// of `PrintViewModel+Annotations`.
//
// The store is the same one the print screen edits (`printSelection`, keyed by
// image identity), so an arrow drawn here is on the film the moment the image
// is marked, and an arrow drawn on a film cell is on this screen the moment
// the image is shown. What differs is only the address: the print screen edits
// through a mark ID, the viewer through ``currentAnnotationKey`` — the image
// itself, marked or not.

import Foundation
import DICOMCore
import DICOMKit
import DICOMPrintKit

extension ImageViewerViewModel {

    /// Puts an empty text annotation on the image on screen and selects it, so
    /// the overlay opens it for typing. `nil` when no image is loaded.
    @discardableResult
    public func addDrawnTextAnnotation(at point: PrintOverlayPoint) -> UUID? {
        guard let key = currentAnnotationKey else { return nil }
        let id = printSelection.addTextAnnotation(forKey: key, at: point)
        drawnAnnotationsFollowTools()
        return id
    }

    /// Puts a combined annotation on the image on screen and selects it, so
    /// the overlay opens it for typing. `anchor` is the point its arrow names;
    /// `nil` (or the label point itself) starts it as plain words.
    @discardableResult
    public func addDrawnAnnotation(
        at start: PrintOverlayPoint, anchor: PrintOverlayPoint? = nil
    ) -> UUID? {
        guard let key = currentAnnotationKey else { return nil }
        let id = printSelection.addAnnotation(forKey: key, at: start, anchor: anchor)
        drawnAnnotationsFollowTools()
        return id
    }

    /// Puts an arrow on the image on screen, tail to head, and selects it.
    @discardableResult
    public func addDrawnArrowAnnotation(
        from start: PrintOverlayPoint, to end: PrintOverlayPoint
    ) -> UUID? {
        guard let key = currentAnnotationKey else { return nil }
        let id = printSelection.addArrowAnnotation(forKey: key, from: start, to: end)
        drawnAnnotationsFollowTools()
        return id
    }

    /// Resolves the physical pixel spacing calibration for the currently loaded
    /// DICOM file, checking Pixel Spacing (0028,0030), Imager Pixel Spacing
    /// (0018,1164), and Nominal Scanned Pixel Spacing (0018,2010), with
    /// Estimated Radiographic Magnification Factor (0018,1114) correction.
    public var currentImageCalibration: CalibrationModel {
        guard let ds = dicomFile?.dataSet else { return .uncalibrated }
        let base = CalibrationHelpers.resolveCalibration(
            pixelSpacing: ds.string(for: .pixelSpacing),
            imagerPixelSpacing: ds.string(for: .imagerPixelSpacing),
            nominalScannedPixelSpacing: ds.string(for: .nominalScannedPixelSpacing))
        if let magRaw = ds.string(for: Tag(group: 0x0018, element: 0x1114))?
            .trimmingCharacters(in: .whitespaces),
           let mag = Double(magRaw), mag > 0 {
            return CalibrationHelpers.applyMagnificationCorrection(
                calibration: base, magnificationFactor: mag)
        }
        return base
    }

    /// Computes the linear distance measurement between two normalized points
    /// on the current image.
    public func measureDrawnLength(
        from start: PrintOverlayPoint, to end: PrintOverlayPoint
    ) -> LinearMeasurementResult {
        let width = Double(max(0, imageColumns))
        let height = Double(max(0, imageRows))
        let startPx = AnnotationPoint(x: start.x * width, y: start.y * height)
        let endPx = AnnotationPoint(x: end.x * width, y: end.y * height)
        return MeasurementHelpers.measureLength(
            from: startPx, to: endPx, calibration: currentImageCalibration)
    }

    /// Formats the linear distance between two normalized points on the current
    /// image (e.g. "24.5 mm" when calibrated, or "120.0 px" when uncalibrated).
    public func formattedDrawnLengthText(
        from start: PrintOverlayPoint, to end: PrintOverlayPoint
    ) -> String {
        let result = measureDrawnLength(from: start, to: end)
        return MeasurementHelpers.formatLength(
            pixels: result.lengthPixels, mm: result.lengthMM, unit: .millimeters)
    }

    /// Puts a length measurement on the image on screen, calculating its
    /// distance label from the image's pixel spacing, and selects it.
    @discardableResult
    public func addDrawnLengthAnnotation(
        from start: PrintOverlayPoint, to end: PrintOverlayPoint
    ) -> UUID? {
        guard let key = currentAnnotationKey else { return nil }
        let label = formattedDrawnLengthText(from: start, to: end)
        let id = printSelection.addLengthAnnotation(
            forKey: key, from: start, to: end, text: label)
        drawnAnnotationsFollowTools()
        return id
    }

    /// Moves one endpoint of a length measurement and updates its distance label.
    public func moveDrawnLengthEnd(
        _ id: UUID, isEnd: Bool, to point: PrintOverlayPoint
    ) {
        guard let key = currentAnnotationKey else { return }
        printSelection.moveArrowEnd(id, forKey: key, isHead: isEnd, to: point)
        if let updated = printSelection.annotations(forKey: key).first(where: { $0.id == id }) {
            let label = formattedDrawnLengthText(from: updated.start, to: updated.end)
            printSelection.setAnnotationText(label, id: id, forKey: key)
        }
        drawnAnnotationsFollowTools()
    }

    /// Moves an annotation bodily by a normalized delta.
    public func moveDrawnAnnotation(_ id: UUID, dx: Double, dy: Double) {
        guard let key = currentAnnotationKey else { return }
        printSelection.moveAnnotation(id, forKey: key, dx: dx, dy: dy)
        drawnAnnotationsFollowTools()
    }

    /// Drags one end of an arrow, leaving the other where it is.
    public func moveDrawnArrowEnd(_ id: UUID, isHead: Bool, to point: PrintOverlayPoint) {
        guard let key = currentAnnotationKey else { return }
        printSelection.moveArrowEnd(id, forKey: key, isHead: isHead, to: point)
        drawnAnnotationsFollowTools()
    }

    /// Swings a combined annotation's label around the point its arrow names,
    /// keeping their distance — the orbit handle's edit.
    ///
    /// `direction` is in image space, not screen space: the caller maps the
    /// pointer through the same transform the picture is drawn with, so the
    /// label follows the hand on a turned or mirrored image too.
    public func orbitDrawnAnnotationLabel(
        _ id: UUID, towards direction: (dx: Double, dy: Double)
    ) {
        guard let key = currentAnnotationKey else { return }
        printSelection.orbitAnnotationLabel(
            id, forKey: key, towards: direction,
            imageWidth: Double(imageColumns), imageHeight: Double(imageRows))
        drawnAnnotationsFollowTools()
    }

    /// Sets an annotation's words.
    public func setDrawnAnnotationText(_ text: String, id: UUID) {
        guard let key = currentAnnotationKey else { return }
        printSelection.setAnnotationText(text, id: id, forKey: key)
        drawnAnnotationsFollowTools()
    }

    /// Sets an annotation's size, which also becomes the size of the next one.
    public func setDrawnAnnotationScale(_ scale: Double, id: UUID) {
        guard let key = currentAnnotationKey else { return }
        printSelection.setAnnotationScale(scale, id: id, forKey: key)
        drawnAnnotationsFollowTools()
    }

    /// Sets an annotation's colour, which also becomes the next one's.
    public func setDrawnAnnotationColor(_ color: PrintOverlayColor, id: UUID) {
        guard let key = currentAnnotationKey else { return }
        printSelection.setAnnotationColor(color, id: id, forKey: key)
        drawnAnnotationsFollowTools()
    }

    /// Deletes one annotation from the image on screen.
    public func removeDrawnAnnotation(_ id: UUID) {
        guard let key = currentAnnotationKey else { return }
        printSelection.removeAnnotation(id, forKey: key)
        drawnAnnotationsFollowTools()
    }

    /// Deletes whatever is selected, if anything. Wherever it lives — a
    /// selection can outlast a frame step, and the delete key must still work.
    @discardableResult
    public func removeSelectedDrawnAnnotation() -> Bool {
        let removed = printSelection.removeSelectedAnnotation()
        if removed { drawnAnnotationsFollowTools() }
        return removed
    }

    /// Selects an annotation, or clears the selection with `nil`.
    public func selectDrawnAnnotation(_ id: UUID?) {
        printSelection.selectAnnotation(id)
    }

    /// A drawing edit is a tool action: what is on screen afterwards is no
    /// longer the saved view the picker may still be naming.
    private func drawnAnnotationsFollowTools() {
        presentationStateFollowsTools()
    }
}
