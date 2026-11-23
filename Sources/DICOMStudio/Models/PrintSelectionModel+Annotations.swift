// PrintSelectionModel+Annotations.swift
// DICOMStudio
//
// DICOM Studio — the text and arrows a reader draws on an image.
//
// An annotation belongs to the image it is drawn on, not to any one film
// mark: the same frame can be marked onto more than one film cell, and the
// main viewer shows an image's annotations whether or not that image is
// marked at all. They are held per image identity, in coordinates normalized
// to the image, and the same values drive the print-tray preview overlay,
// the main viewer's GPU overlay, and (while a print run is composing) the
// burn into film pixels.
//
// Nothing here renders. See ``ImageAnnotationBurner`` for the CPU drawing
// that reaches the printer and ``AnnotationTextureBuilder`` for the GPU
// texture the main viewer composites.

import Foundation
import DICOMPrintKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension PrintSelectionModel {

    // MARK: - Reading

    /// The annotations drawn on one mark's image, in the order they were added.
    public func annotations(forItemID itemID: String) -> [PrintOverlayAnnotation] {
        guard let key = annotationKey(forItemID: itemID) else { return [] }
        return annotations(forKey: key)
    }

    /// The annotations drawn on one image, addressed by image identity.
    ///
    /// The `forKey:` overloads exist for the main viewer, which edits an
    /// image's annotations whether or not that image is marked for print — it
    /// has no mark ID to offer, but always knows the image it is showing.
    public func annotations(forKey key: ImageAnnotationKey) -> [PrintOverlayAnnotation] {
        cellAnnotations[key] ?? []
    }

    /// Every marked image's annotations, keyed by mark ID, blank ones dropped.
    ///
    /// This is what a print run burns: a text box the user opened and never
    /// typed into is not something to draw on film. Two marks that point at
    /// the same image share one annotation set in storage; this join expands
    /// that back out to per-mark keying, because a print job burns per mark
    /// (the same frame marked onto two film cells is burned twice).
    public var annotationsForPrinting: [String: [PrintOverlayAnnotation]] {
        var result: [String: [PrintOverlayAnnotation]] = [:]
        for item in items {
            guard let overlays = cellAnnotations[item.annotationKey] else { continue }
            let drawable = overlays.filter { !$0.isBlank }
            if !drawable.isEmpty { result[item.id] = drawable }
        }
        return result
    }

    /// Whether any image carries a drawn annotation.
    public var hasAnnotations: Bool {
        !annotationsForPrinting.isEmpty
    }

    /// The annotation the inspector is editing, with the mark it belongs to.
    ///
    /// `itemID` is `nil` when the annotation's image is not currently marked
    /// on the tray (e.g. it was drawn from the main viewer only) — callers
    /// that need a mark ID for a `forItemID:` call should treat that as "no
    /// tray cell to point at" rather than fall back to a synthetic ID.
    public var selectedAnnotation: (itemID: String?, annotation: PrintOverlayAnnotation)? {
        guard let selectedAnnotationID else { return nil }
        for (key, overlays) in cellAnnotations {
            if let match = overlays.first(where: { $0.id == selectedAnnotationID }) {
                let itemID = items.first { $0.annotationKey == key }?.id
                return (itemID, match)
            }
        }
        return nil
    }

    /// The selected annotation with the image it lives on — the address the
    /// main viewer edits by, since it may have no mark to name.
    public var selectedAnnotationLocation:
        (key: ImageAnnotationKey, annotation: PrintOverlayAnnotation)? {
        guard let selectedAnnotationID else { return nil }
        for (key, overlays) in cellAnnotations {
            if let match = overlays.first(where: { $0.id == selectedAnnotationID }) {
                return (key, match)
            }
        }
        return nil
    }

    // MARK: - Adding

    /// Puts a line of text on a mark's image at a point, and selects it for
    /// editing.
    ///
    /// Created empty rather than with placeholder words: placeholder text
    /// that nobody clears is how "Text" ends up printed on a film.
    @discardableResult
    public func addTextAnnotation(
        forItemID itemID: String,
        at point: PrintOverlayPoint
    ) -> UUID {
        addTextAnnotation(forKey: annotationKey(forItemID: itemID), at: point)
    }

    /// Puts a line of text on an image at a point, addressed by image identity.
    @discardableResult
    public func addTextAnnotation(
        forKey key: ImageAnnotationKey?,
        at point: PrintOverlayPoint
    ) -> UUID {
        let annotation = PrintOverlayAnnotation(
            kind: .text,
            start: point,
            text: "",
            scale: annotationScale,
            color: annotationColor)
        if let key {
            cellAnnotations[key, default: []].append(annotation)
        }
        selectAnnotation(annotation.id)
        return annotation.id
    }

    /// Puts an arrow on a mark's image, tail to head, and selects it.
    @discardableResult
    public func addArrowAnnotation(
        forItemID itemID: String,
        from start: PrintOverlayPoint,
        to end: PrintOverlayPoint
    ) -> UUID {
        addArrowAnnotation(forKey: annotationKey(forItemID: itemID), from: start, to: end)
    }

    /// Puts an arrow on an image, addressed by image identity.
    @discardableResult
    public func addArrowAnnotation(
        forKey key: ImageAnnotationKey?,
        from start: PrintOverlayPoint,
        to end: PrintOverlayPoint
    ) -> UUID {
        let annotation = PrintOverlayAnnotation(
            kind: .arrow,
            start: start,
            end: end,
            scale: annotationScale,
            color: annotationColor)
        if let key {
            cellAnnotations[key, default: []].append(annotation)
        }
        selectAnnotation(annotation.id)
        return annotation.id
    }

    /// Puts a combined annotation — a label with an arrow from it to an
    /// anchor — on an image, addressed by image identity, and selects it for
    /// typing. With no anchor (or one equal to the label point) it starts as
    /// plain words; the viewer's tool passes the anchor when the reader drags
    /// one out, Weasis-style: press on the thing, drag out the label.
    @discardableResult
    public func addAnnotation(
        forKey key: ImageAnnotationKey?,
        at start: PrintOverlayPoint,
        anchor: PrintOverlayPoint? = nil
    ) -> UUID {
        let annotation = PrintOverlayAnnotation(
            kind: .annotation,
            start: start,
            end: anchor ?? start,
            text: "",
            scale: annotationScale,
            color: annotationColor)
        if let key {
            cellAnnotations[key, default: []].append(annotation)
        }
        selectAnnotation(annotation.id)
        return annotation.id
    }

    /// Puts a linear distance measurement on an image, addressed by image
    /// identity, and selects it.
    @discardableResult
    public func addLengthAnnotation(
        forKey key: ImageAnnotationKey?,
        from start: PrintOverlayPoint,
        to end: PrintOverlayPoint,
        text: String
    ) -> UUID {
        let annotation = PrintOverlayAnnotation(
            kind: .length,
            start: start,
            end: end,
            text: text,
            scale: annotationScale,
            color: annotationColor)
        if let key {
            cellAnnotations[key, default: []].append(annotation)
        }
        selectAnnotation(annotation.id)
        return annotation.id
    }

    // MARK: - Editing

    /// Selects an annotation, or clears the selection with `nil`.
    ///
    /// Selecting something else abandons a text box that was never typed into. A
    /// text annotation is created empty and only exists to be typed into, so one
    /// left behind is a slip, not a decision — and an empty box that lingers on the
    /// preview looks exactly like text that failed to print.
    public func selectAnnotation(_ id: UUID?) {
        discardEmptyText(except: id)
        selectedAnnotationID = id
    }

    /// Removes text annotations that were never typed into, other than one.
    ///
    /// A combined annotation is only "never typed into" when it also has no
    /// arrow: an arrow drawn and left unlabelled is a drawing, not a slip.
    public func discardEmptyText(except keptID: UUID?) {
        for (key, overlays) in cellAnnotations {
            let kept = overlays.filter { overlay in
                guard overlay.id != keptID else { return true }
                switch overlay.kind {
                case .text:       return !overlay.text.isEmpty
                case .arrow:      return true
                case .length:     return !overlay.isBlank
                case .annotation: return !overlay.isBlank
                case .polyline, .circle, .ellipse, .point, .shutter:
                    return true
                }
            }
            guard kept.count != overlays.count else { continue }
            cellAnnotations[key] = kept.isEmpty ? nil : kept
        }
    }

    /// Moves an annotation bodily by a normalized delta — both ends, so an arrow
    /// keeps its length and direction.
    public func moveAnnotation(_ id: UUID, forItemID itemID: String, dx: Double, dy: Double) {
        mutate(id, forItemID: itemID) { $0 = $0.moved(dx: dx, dy: dy) }
    }

    /// Moves an annotation bodily, addressed by image identity.
    public func moveAnnotation(_ id: UUID, forKey key: ImageAnnotationKey, dx: Double, dy: Double) {
        mutate(id, key: key) { $0 = $0.moved(dx: dx, dy: dy) }
    }

    /// Drags one end of an arrow, leaving the other where it is.
    public func moveArrowEnd(
        _ id: UUID,
        forItemID itemID: String,
        isHead: Bool,
        to point: PrintOverlayPoint
    ) {
        guard let key = annotationKey(forItemID: itemID) else { return }
        moveArrowEnd(id, forKey: key, isHead: isHead, to: point)
    }

    /// Drags one end of an arrow, addressed by image identity.
    public func moveArrowEnd(
        _ id: UUID,
        forKey key: ImageAnnotationKey,
        isHead: Bool,
        to point: PrintOverlayPoint
    ) {
        mutate(id, key: key) { annotation in
            // Both ended kinds: an arrow's tail/head, or a combined
            // annotation's label point / anchor. Text has no second end.
            guard annotation.kind != .text else { return }
            if isHead {
                annotation.end = point
            } else {
                annotation.start = point
            }
        }
    }

    /// Swings a combined annotation's label around its anchor, keeping the
    /// distance between them, so the words orbit the point the arrow names.
    ///
    /// The reader aims at a screen direction and this stores the label point
    /// that lands there — the caller has already turned the pointer into an
    /// image-space direction, because the picture may be turned or mirrored
    /// under it and an angle measured on screen is not an angle in the image.
    ///
    /// Radius is taken from where the label is now rather than passed in: an
    /// orbit is a change of *direction* only, and re-deriving it each time is
    /// what keeps a swing from creeping in or out as the pointer moves.
    ///
    /// Normalized coordinates are fractions of two different pixel counts, so
    /// a circle in them is an ellipse on a non-square image. The swing is
    /// therefore computed in pixels — `imageWidth`/`imageHeight` — and put
    /// back afterwards, which is what makes the label hold its distance from
    /// the anchor rather than swelling and shrinking as it goes round.
    public func orbitAnnotationLabel(
        _ id: UUID,
        forKey key: ImageAnnotationKey,
        towards direction: (dx: Double, dy: Double),
        imageWidth: Double,
        imageHeight: Double
    ) {
        guard imageWidth > 0, imageHeight > 0 else { return }
        // A pointer sitting exactly on the anchor names no direction at all;
        // leaving the label where it is beats snapping it somewhere arbitrary.
        let length = (direction.dx * direction.dx
                      + direction.dy * direction.dy).squareRoot()
        guard length > 0, length.isFinite else { return }
        let unitX = direction.dx / length
        let unitY = direction.dy / length

        mutate(id, key: key) { annotation in
            guard annotation.kind != .text else { return }
            let pixelDX = (annotation.start.x - annotation.end.x) * imageWidth
            let pixelDY = (annotation.start.y - annotation.end.y) * imageHeight
            let radius = (pixelDX * pixelDX + pixelDY * pixelDY).squareRoot()
            guard radius > 0 else { return }
            annotation.start = PrintOverlayPoint(
                x: annotation.end.x + unitX * radius / imageWidth,
                y: annotation.end.y + unitY * radius / imageHeight)
        }
    }

    /// Puts an annotation at an absolute point (its top-left, or an arrow's tail
    /// with the head carried along).
    public func placeAnnotation(_ id: UUID, forItemID itemID: String, at point: PrintOverlayPoint) {
        guard let existing = annotations(forItemID: itemID).first(where: { $0.id == id }) else { return }
        moveAnnotation(id, forItemID: itemID,
                       dx: point.x - existing.start.x,
                       dy: point.y - existing.start.y)
    }

    public func setAnnotationText(_ text: String, id: UUID, forItemID itemID: String) {
        mutate(id, forItemID: itemID) { $0.text = text }
    }

    /// Sets an annotation's words, addressed by image identity.
    public func setAnnotationText(_ text: String, id: UUID, forKey key: ImageAnnotationKey) {
        mutate(id, key: key) { $0.text = text }
    }

    /// Sets one annotation's size, and adopts it as the size for the next one —
    /// a reader who has decided how big their annotations should be has decided
    /// it for the whole film, not for one cell.
    public func setAnnotationScale(_ scale: Double, id: UUID, forItemID itemID: String) {
        mutate(id, forItemID: itemID) { $0 = $0.withScale(scale) }
        annotationScale = PrintOverlayAnnotation.clampScale(scale)
    }

    /// Sets an annotation's size, addressed by image identity.
    public func setAnnotationScale(_ scale: Double, id: UUID, forKey key: ImageAnnotationKey) {
        mutate(id, key: key) { $0 = $0.withScale(scale) }
        annotationScale = PrintOverlayAnnotation.clampScale(scale)
    }

    public func setAnnotationColor(_ color: PrintOverlayColor, id: UUID, forItemID itemID: String) {
        mutate(id, forItemID: itemID) { $0.color = color }
        annotationColor = color
    }

    /// Sets an annotation's colour, addressed by image identity.
    public func setAnnotationColor(_ color: PrintOverlayColor, id: UUID, forKey key: ImageAnnotationKey) {
        mutate(id, key: key) { $0.color = color }
        annotationColor = color
    }

    // MARK: - Removing

    /// Deletes one annotation.
    public func removeAnnotation(_ id: UUID, forItemID itemID: String) {
        guard let key = annotationKey(forItemID: itemID) else { return }
        removeAnnotation(id, forKey: key)
    }

    /// Deletes one annotation, addressed by image identity.
    public func removeAnnotation(_ id: UUID, forKey key: ImageAnnotationKey) {
        cellAnnotations[key]?.removeAll { $0.id == id }
        if cellAnnotations[key]?.isEmpty == true { cellAnnotations[key] = nil }
        if selectedAnnotationID == id { selectedAnnotationID = nil }
    }

    /// Deletes whatever is selected, if anything.
    ///
    /// Found by scanning storage rather than through a mark: the selected
    /// annotation may live on an image drawn on from the main viewer that no
    /// mark points at, and it must still be deletable there.
    @discardableResult
    public func removeSelectedAnnotation() -> Bool {
        guard let selectedAnnotationID else { return false }
        for (key, overlays) in cellAnnotations
        where overlays.contains(where: { $0.id == selectedAnnotationID }) {
            removeAnnotation(selectedAnnotationID, forKey: key)
            return true
        }
        return false
    }

    /// Clears one mark's image of annotations.
    public func clearAnnotations(forItemID itemID: String) {
        guard let key = annotationKey(forItemID: itemID) else { return }
        if let ids = cellAnnotations[key]?.map(\.id), ids.contains(where: { $0 == selectedAnnotationID }) {
            selectedAnnotationID = nil
        }
        cellAnnotations[key] = nil
    }

    /// Clears every drawn annotation.
    public func clearAllAnnotations() {
        cellAnnotations = [:]
        selectedAnnotationID = nil
    }

    /// Drops annotations belonging to images that are no longer marked.
    ///
    /// Unmarking an image and marking it again is a routine thing to do while
    /// composing a film; what must not happen is annotations outliving every
    /// mark that pointed at their image and reappearing on some later film.
    /// An image still shown in the main viewer (marked or not) is unaffected
    /// by this — pruning only removes keys with no live mark at all.
    public func pruneAnnotations() {
        let live = Set(items.map(\.annotationKey))
        for key in cellAnnotations.keys where !live.contains(key) {
            cellAnnotations[key] = nil
        }
        if let selectedAnnotationID,
           !cellAnnotations.values.flatMap({ $0 }).contains(where: { $0.id == selectedAnnotationID }) {
            self.selectedAnnotationID = nil
        }
    }

    // MARK: - Plumbing

    /// Resolves a print-tray mark ID to the image identity its annotations
    /// are stored under. `nil` when the mark is no longer selected —
    /// annotation calls against a mark that just left the tray are then
    /// no-ops, same as before this store moved off the mark's own ID.
    private func annotationKey(forItemID itemID: String) -> ImageAnnotationKey? {
        items.first { $0.id == itemID }?.annotationKey
    }

    /// Edits one annotation in place, if it is still there.
    private func mutate(
        _ id: UUID,
        forItemID itemID: String,
        _ transform: (inout PrintOverlayAnnotation) -> Void
    ) {
        guard let key = annotationKey(forItemID: itemID) else { return }
        mutate(id, key: key, transform)
    }

    /// Edits one annotation in place, addressed by image identity.
    private func mutate(
        _ id: UUID,
        key: ImageAnnotationKey,
        _ transform: (inout PrintOverlayAnnotation) -> Void
    ) {
        guard var overlays = cellAnnotations[key],
              let index = overlays.firstIndex(where: { $0.id == id }),
              // Read out of another viewer's state: shown as stated, never
              // moved or reworded here — see ``PrintOverlayAnnotation/isLocked``.
              !overlays[index].isLocked else { return }
        transform(&overlays[index])
        cellAnnotations[key] = overlays
    }
}
