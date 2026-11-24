// FilmCellAnnotationLayer.swift
// DICOMStudio
//
// DICOM Studio — the reader's own text and arrows, drawn over a film cell.
//
// This layer draws what will be burned into the printed pixels, from the same
// numbers: positions are fractions of the image, so what is on screen here is
// what the printer receives — not an approximation of it. The geometry of an
// arrow (line weight, head length, head width) is deliberately the same formula
// ``ImageAnnotationBurner`` uses, because an arrow that looks balanced in the
// preview and heavy on the film is a preview that lied.
//
// Annotations are positioned against the *image rect* rather than the cell: a
// portrait CT in a landscape cell leaves black margins, and an arrow dropped in
// the margin would have no pixels to be burned into.

#if canImport(SwiftUI)
import SwiftUI
import DICOMPrintKit

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct FilmCellAnnotationLayer: View {
    @Bindable var viewModel: PrintViewModel

    /// The mark this cell shows, which is what annotations belong to.
    let itemID: String

    /// Where the image is actually drawn inside the cell, in cell points.
    ///
    /// The *arranged* picture's rectangle — the one the shader draws, sides
    /// already swapped by a quarter turn. Annotations are stored against the
    /// unarranged image, so `orientation` below is what gets them from one to
    /// the other.
    let imageRect: CGRect

    /// How this cell is turned, mirrored and cropped.
    ///
    /// Without it the layer laid an image-space fraction straight onto the
    /// arranged rectangle, so every annotation on a turned or mirrored cell sat
    /// somewhere other than where it was drawn — and somewhere other than where
    /// the film burns it, which is the one thing this preview exists to promise.
    let orientation: PrintOverlayOrientation

    /// Whether this cell accepts clicks. A cell only takes annotation edits while
    /// a drawing tool is active or something on it is already selected — otherwise
    /// windowing a cell would be interrupted by whatever text is sitting on it.
    let isInteractive: Bool

    /// Anchor for the annotation being dragged, so a drag applies deltas.
    @State private var dragAnchor: CGSize = .zero

    /// The text annotation whose words are being typed right now, if any.
    ///
    /// Editing state lives here, not in the view model: whether a box is open
    /// for typing is chrome, like a focus ring — the film neither knows nor
    /// cares. A freshly placed annotation opens for editing on its own (it is
    /// empty, and empty text exists only to be typed into); an existing one
    /// opens on double-click, so that a single click still selects and a drag
    /// still moves it.
    @State private var editingTextID: UUID?

    /// Keyboard focus for the inline text editor.
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(viewModel.annotations(forItemID: itemID)) { annotation in
                if annotation.isLocked || annotation.isShape {
                    // From another viewer's presentation state: drawn as the
                    // film will burn it, never grabbed — a ruler's label is
                    // a measurement, and dragging it would make it a lie.
                    lockedAnnotation(annotation)
                } else {
                    switch annotation.kind {
                    case .text:  textAnnotation(annotation)
                    case .arrow: arrowAnnotation(annotation)
                    case .annotation: combinedAnnotation(annotation)
                    case .length: lengthAnnotation(annotation)
                    case .polyline, .circle, .ellipse, .point, .shutter:
                        lockedAnnotation(annotation)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        // Nothing here should swallow a click meant for the picture underneath.
        .allowsHitTesting(isInteractive)
    }

    private static let space = "filmCellAnnotations"

    // MARK: - Text

    @ViewBuilder
    private func textAnnotation(_ annotation: PrintOverlayAnnotation) -> some View {
        let isSelected = viewModel.selectedAnnotationID == annotation.id
        // The burner's fraction of the picture's height, then this screen's own
        // floor. The fraction is shared so the preview and the film set the
        // words at one size; the floors are not, and legitimately so — the
        // burner's is in the pixels of the frame, this one in points on screen.
        let fontSize = max(Self.minimumPreviewFontSize,
                           CGFloat(ImageAnnotationBurner.overlayFontSize(
                            imageHeight: Double(imageRect.height),
                            scale: annotation.scale)))
        let position = point(annotation.start)
        // A just-placed annotation is empty, and empty text exists only to be
        // typed into — so it opens straight into the editor without a second
        // click. Anything already worded needs the deliberate double-click.
        let isEditing = isSelected && (editingTextID == annotation.id || annotation.text.isEmpty)

        if isEditing {
            textEditor(annotation, fontSize: fontSize)
                .offset(x: position.x, y: position.y)
        } else {
            // The burner's own face, named by it rather than spelled again here
            // — a preview in the system font would set to a different width and
            // break differently from the film.
            Text(annotation.text)
                .font(.custom(ImageAnnotationBurner.overlayFontFamily, size: fontSize))
                .foregroundStyle(color(annotation.color))
                .shadow(color: halo(annotation.color), radius: max(1, fontSize * 0.08))
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(isSelected ? Color.accentColor : .clear,
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                )
                .contentShape(Rectangle())
                // Level, whatever the cell is doing — the same cancellation the
                // burner applies to the film, so the preview reads as the film
                // will. Rotated about the anchor (`.topLeading`), which is where
                // the caret sat and where the burner sets the type from.
                .rotationEffect(.degrees(orientation.textAngleDegrees),
                                anchor: .topLeading)
                .scaleEffect(x: orientation.textIsMirrored ? -1 : 1, y: 1,
                             anchor: .topLeading)
                .offset(x: position.x, y: position.y)
                .gesture(moveGesture(annotation))
                .onTapGesture(count: 2) {
                    viewModel.selectAnnotation(annotation.id)
                    editingTextID = annotation.id
                }
                .onTapGesture { viewModel.selectAnnotation(annotation.id) }
                .accessibilityLabel("Text annotation: \(annotation.text)")
        }
    }

    /// The box the words are typed into, sitting where the text will print.
    ///
    /// Typing happens on the cell itself: the inspector's field lives in a
    /// sidebar that may well be closed, and a click that produces nothing but a
    /// hairline caret reads as a workflow that broke. The field wears the print
    /// face and colour so the words set to the width they will burn at — but it
    /// never renders below a typeable size, and it carries a visible box and a
    /// floor on its width, because a box too small to see or hit is the failure
    /// this editor exists to fix. The box itself is chrome, like the focus
    /// ring: it is not on the film, only the words are.
    private func textEditor(_ annotation: PrintOverlayAnnotation, fontSize: CGFloat) -> some View {
        let editingFontSize = max(fontSize, Self.minimumEditingFontSize)
        let font = Font.custom(ImageAnnotationBurner.overlayFontFamily, size: editingFontSize)

        return TextField("Type here", text: textBinding(annotation), axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(color(annotation.color))
            .lineLimit(1...4)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: min(Self.minimumEditorWidth, max(imageRect.width - 12, 60)),
                   maxWidth: max(imageRect.width * 0.9, 60),
                   alignment: .leading)
            .fixedSize(horizontal: true, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 1))
            )
            .focused($isTextEditorFocused)
            .onAppear {
                editingTextID = annotation.id
                isTextEditorFocused = true
            }
            .onSubmit { commitTextEditing(annotation.id) }
            #if os(macOS)
            .onExitCommand { commitTextEditing(annotation.id) }
            #endif
            // Clicking elsewhere pulls focus; the box must not linger open.
            .onChange(of: isTextEditorFocused) { _, focused in
                if !focused, editingTextID == annotation.id { commitTextEditing(annotation.id) }
            }
            .accessibilityLabel("Text annotation editor")
    }

    /// Closes the inline editor. Deselecting discards a box nothing was typed
    /// into — see ``PrintViewModel/selectAnnotation(_:)``. Only the editor's
    /// own annotation is let go: by the time a lost focus lands here, the click
    /// that took it may already have selected — or placed — the next one.
    private func commitTextEditing(_ id: UUID) {
        editingTextID = nil
        isTextEditorFocused = false
        if viewModel.selectedAnnotationID == id { viewModel.selectAnnotation(nil) }
    }

    /// The words of one annotation, straight into the model — every keystroke
    /// lands in the same place the burner reads from.
    private func textBinding(_ annotation: PrintOverlayAnnotation) -> Binding<String> {
        Binding(
            get: {
                viewModel.annotations(forItemID: itemID)
                    .first(where: { $0.id == annotation.id })?.text ?? ""
            },
            set: { viewModel.setAnnotationText($0, id: annotation.id, forItemID: itemID) })
    }

    // MARK: - Arrow

    @ViewBuilder
    private func arrowAnnotation(_ annotation: PrintOverlayAnnotation) -> some View {
        let isSelected = viewModel.selectedAnnotationID == annotation.id
        let tail = point(annotation.start)
        let head = point(annotation.end)
        let metrics = ArrowMetrics(
            scale: annotation.scale, imageHeight: imageRect.height,
            tail: tail, head: head)

        ZStack(alignment: .topLeading) {
            // Drawn the way it is burned: a halo tracing the outline, then the
            // arrow filled over it. A blurred shadow softened the head into the
            // shaft and made the arrow read as a plain line.
            ArrowShape(metrics: metrics)
                .stroke(halo(annotation.color), lineWidth: metrics.haloWidth)
            ArrowShape(metrics: metrics)
                .fill(color(annotation.color))
                // A thin arrow is hard to hit, so the touchable area is the line
                // fattened, not the drawn width.
                .contentShape(ArrowShape(metrics: metrics).stroke(lineWidth: Self.grabWidth))
                .gesture(moveGesture(annotation))
                .onTapGesture { viewModel.selectAnnotation(annotation.id) }

            if isSelected {
                handle(at: tail) { newPoint in
                    viewModel.moveArrowEnd(annotation.id, forItemID: itemID,
                                           isHead: false, to: newPoint)
                }
                handle(at: head) { newPoint in
                    viewModel.moveArrowEnd(annotation.id, forItemID: itemID,
                                           isHead: true, to: newPoint)
                }
            }
        }
        .accessibilityLabel("Arrow annotation")
    }

    // MARK: - Length

    @ViewBuilder
    private func lengthAnnotation(_ annotation: PrintOverlayAnnotation) -> some View {
        let isSelected = viewModel.selectedAnnotationID == annotation.id
        let start = point(annotation.start)
        let end = point(annotation.end)
        let widths = ImageAnnotationBurner.shapeLineWidths(
            scale: annotation.scale, imageHeight: Double(max(1, imageRect.height)))
        let fontSize = max(Self.minimumPreviewFontSize,
                           CGFloat(ImageAnnotationBurner.overlayFontSize(
                            imageHeight: Double(imageRect.height),
                            scale: annotation.scale)))
        let tickHalf = CGFloat(max(widths.line * 2.5, Double(fontSize) * 0.35))
        let rulerShape = LengthRulerShape(start: start, end: end, tickHalfLength: tickHalf)
        let labelOriginNorm = PrintAnnotationLayout.lengthLabelOrigin(
            for: annotation,
            imageWidth: Double(max(1, imageRect.width)),
            imageHeight: Double(max(1, imageRect.height)))
        let labelPos = point(labelOriginNorm)

        ZStack(alignment: .topLeading) {
            rulerShape
                .stroke(halo(annotation.color),
                        style: StrokeStyle(lineWidth: CGFloat(widths.line + widths.halo),
                                           lineCap: .round, lineJoin: .round))
            rulerShape
                .stroke(color(annotation.color),
                        style: StrokeStyle(lineWidth: CGFloat(widths.line),
                                           lineCap: .round, lineJoin: .round))
                .contentShape(rulerShape.stroke(lineWidth: Self.grabWidth))
                .gesture(moveGesture(annotation))
                .onTapGesture { viewModel.selectAnnotation(annotation.id) }

            if annotation.hasWords {
                Text(annotation.text)
                    .font(.custom(ImageAnnotationBurner.overlayFontFamily, size: fontSize))
                    .foregroundStyle(color(annotation.color))
                    .shadow(color: halo(annotation.color), radius: max(1, fontSize * 0.08))
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(isSelected ? Color.accentColor : .clear,
                                          style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
                    .rotationEffect(.degrees(orientation.textAngleDegrees), anchor: .topLeading)
                    .scaleEffect(x: orientation.textIsMirrored ? -1 : 1, y: 1, anchor: .topLeading)
                    .offset(x: labelPos.x, y: labelPos.y)
                    .gesture(moveGesture(annotation))
                    .onTapGesture { viewModel.selectAnnotation(annotation.id) }
            }
        }
        .accessibilityLabel("Length measurement: \(annotation.text)")
    }

    // MARK: - Locked annotations and shapes

    /// An imported annotation or a shape, drawn through the cell's
    /// arrangement exactly as the burner will place it, with nothing to grab.
    @ViewBuilder
    private func lockedAnnotation(_ annotation: PrintOverlayAnnotation) -> some View {
        ZStack(alignment: .topLeading) {
            if annotation.isShape {
                ImportedShapeView(
                    annotation: annotation,
                    point: { point($0) },
                    lineScaleHeight: imageRect.height)
            } else {
                if annotation.hasWords {
                    let fontSize = max(Self.minimumPreviewFontSize,
                                       CGFloat(ImageAnnotationBurner.overlayFontSize(
                                        imageHeight: Double(imageRect.height),
                                        scale: annotation.scale)))
                    let position = point(annotation.start)
                    Text(annotation.text)
                        .font(.custom(ImageAnnotationBurner.overlayFontFamily, size: fontSize))
                        .foregroundStyle(color(annotation.color))
                        .shadow(color: halo(annotation.color), radius: max(1, fontSize * 0.08))
                        .rotationEffect(.degrees(orientation.textAngleDegrees), anchor: .topLeading)
                        .scaleEffect(x: orientation.textIsMirrored ? -1 : 1, y: 1, anchor: .topLeading)
                        .offset(x: position.x, y: position.y)
                }
                if annotation.kind == .arrow || (annotation.kind == .annotation && annotation.hasArrow) {
                    let tailNorm = annotation.kind == .arrow
                        ? annotation.start
                        : PrintAnnotationLayout.leaderTail(
                            for: annotation,
                            imageWidth: Double(imageRect.width),
                            imageHeight: Double(imageRect.height))
                    if let tailNorm {
                        let metrics = ArrowMetrics(
                            scale: annotation.scale, imageHeight: imageRect.height,
                            tail: point(tailNorm), head: point(annotation.end))
                        ArrowShape(metrics: metrics)
                            .stroke(halo(annotation.color), lineWidth: metrics.haloWidth)
                        ArrowShape(metrics: metrics)
                            .fill(color(annotation.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(annotation.isShape
                            ? "Imported measurement"
                            : "Imported annotation: \(annotation.text)")
    }

    // MARK: - Combined annotation (label + arrow, after Weasis)

    /// The viewer's merged kind on a film cell: the label exactly as the text
    /// kind renders it, and the arrow from the label's border to the anchor —
    /// tail clipped by the same geometry the burner clips with, so the preview
    /// shows what the film gets.
    @ViewBuilder
    private func combinedAnnotation(_ annotation: PrintOverlayAnnotation) -> some View {
        let isSelected = viewModel.selectedAnnotationID == annotation.id
        let tailNorm = PrintAnnotationLayout.leaderTail(
            for: annotation,
            imageWidth: Double(imageRect.width),
            imageHeight: Double(imageRect.height))

        ZStack(alignment: .topLeading) {
            if let tailNorm {
                let tail = point(tailNorm)
                let head = point(annotation.end)
                let metrics = ArrowMetrics(
                    scale: annotation.scale, imageHeight: imageRect.height,
                    tail: tail, head: head)

                ArrowShape(metrics: metrics)
                    .stroke(halo(annotation.color), lineWidth: metrics.haloWidth)
                ArrowShape(metrics: metrics)
                    .fill(color(annotation.color))
                    .contentShape(ArrowShape(metrics: metrics).stroke(lineWidth: Self.grabWidth))
                    .gesture(moveGesture(annotation))
                    .onTapGesture { viewModel.selectAnnotation(annotation.id) }

                if isSelected {
                    handle(at: head) { newPoint in
                        viewModel.moveArrowEnd(annotation.id, forItemID: itemID,
                                               isHead: true, to: newPoint)
                    }
                }
            }

            textAnnotation(annotation)

            // The label's own handle: the words move, the anchor stays put.
            if isSelected, editingTextID != annotation.id, annotation.hasArrow {
                handle(at: point(annotation.start)) { newPoint in
                    viewModel.moveArrowEnd(annotation.id, forItemID: itemID,
                                           isHead: false, to: newPoint)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Annotation: \(annotation.text)")
    }

    /// A draggable end of a selected arrow.
    ///
    /// A ring, not a disc, and small: a handle is chrome for grabbing the arrow
    /// with, and one big enough to sit over the head hides the very thing the
    /// reader is aiming. What it loses in target size it takes back invisibly —
    /// the grab area is well over twice the drawn ring.
    private func handle(at position: CGPoint, move: @escaping (PrintOverlayPoint) -> Void) -> some View {
        Color.clear
            .frame(width: Self.handleGrabSize, height: Self.handleGrabSize)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.95))
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: Self.handleSize, height: Self.handleSize)
            }
            .contentShape(Circle())
            .offset(x: position.x - Self.handleGrabSize / 2,
                    y: position.y - Self.handleGrabSize / 2)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in move(normalized(value.location)) }
            )
            .accessibilityHidden(true)
    }

    // MARK: - Moving

    /// Drag anywhere on an annotation to move the whole thing.
    private func moveGesture(_ annotation: PrintOverlayAnnotation) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if viewModel.selectedAnnotationID != annotation.id {
                    viewModel.selectAnnotation(annotation.id)
                }
                let dx = value.translation.width - dragAnchor.width
                let dy = value.translation.height - dragAnchor.height
                dragAnchor = value.translation
                guard imageRect.width > 0, imageRect.height > 0 else { return }
                // Through the arrangement as a delta: dragging right on a cell
                // turned a quarter must move the annotation the way the hand
                // went, which on the image beneath is a different axis.
                let moved = orientation.imageDelta(
                    dx: Double(dx) / imageRect.width,
                    dy: Double(dy) / imageRect.height)
                viewModel.moveAnnotation(annotation.id, forItemID: itemID,
                                         dx: moved.dx, dy: moved.dy)
            }
            .onEnded { _ in dragAnchor = .zero }
    }

    // MARK: - Coordinates

    /// An image-space annotation point, in cell points — through the cell's
    /// arrangement, so it lands where the film will burn it.
    private func point(_ overlayPoint: PrintOverlayPoint) -> CGPoint {
        let arranged = orientation.point(overlayPoint)
        return CGPoint(x: imageRect.minX + arranged.x * imageRect.width,
                       y: imageRect.minY + arranged.y * imageRect.height)
    }

    /// A point in cell points, back to a fraction of the image — the way a
    /// click on a turned cell becomes an annotation on the anatomy under it.
    private func normalized(_ location: CGPoint) -> PrintOverlayPoint {
        guard imageRect.width > 0, imageRect.height > 0 else {
            return PrintOverlayPoint(x: 0, y: 0)
        }
        return orientation.imagePoint(
            x: Double((location.x - imageRect.minX) / imageRect.width),
            y: Double((location.y - imageRect.minY) / imageRect.height))
    }

    private func color(_ overlayColor: PrintOverlayColor) -> Color {
        Color(red: overlayColor.red, green: overlayColor.green, blue: overlayColor.blue)
    }

    /// The halo behind an annotation, so it reads over lung and over mediastinum.
    private func halo(_ overlayColor: PrintOverlayColor) -> Color {
        overlayColor.luminance > 0.45 ? .black.opacity(0.9) : .white.opacity(0.9)
    }

    /// Below this the preview type is illegible however small the cell is.
    private static let minimumPreviewFontSize: CGFloat = 6

    /// The editor never sets type below this: words being typed must be
    /// readable at the keyboard even when the printed size is smaller. Once
    /// committed, the annotation renders at its true preview size.
    private static let minimumEditingFontSize: CGFloat = 12

    /// The box opens wide enough to type into before a single letter exists —
    /// clamped to the image when the cell itself is narrower.
    private static let minimumEditorWidth: CGFloat = 140

    /// The drawn ring at each end of a selected arrow.
    private static let handleSize: CGFloat = 6

    /// What that ring is worth to the pointer — big enough to grab, without
    /// covering the anatomy the arrow points at.
    private static let handleGrabSize: CGFloat = 16

    /// How wide an arrow is to the pointer, whatever it is to the eye.
    private static let grabWidth: CGFloat = 12
}

// MARK: - Arrow geometry

/// The measurements of one drawn arrow, in cell points.
///
/// Nothing is decided here: the proportions come from ``PrintArrowGeometry``,
/// which is what ``ImageAnnotationBurner`` draws the film from — so preview and
/// film agree on how heavy the arrow looks and how big its head is.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ArrowMetrics: Equatable {
    let tail: CGPoint
    let head: CGPoint
    let geometry: PrintArrowGeometry

    init(scale: Double, imageHeight: CGFloat, tail: CGPoint, head: CGPoint) {
        self.tail = tail
        self.head = head
        let dx = Double(head.x - tail.x)
        let dy = Double(head.y - tail.y)
        self.geometry = PrintArrowGeometry(
            scale: scale,
            imageHeight: Double(imageHeight),
            arrowLength: (dx * dx + dy * dy).squareRoot())
    }

    var lineWidth: CGFloat { CGFloat(geometry.lineWidth) }

    /// How far the halo spreads beyond the arrow, as a stroke width on its
    /// outline — half of it falls outside the shape, as it does on film.
    var haloWidth: CGFloat { CGFloat(geometry.haloWidth) }

    var outline: PrintArrowOutline? {
        geometry.outline(tail: PrintPlanePoint(x: Double(tail.x), y: Double(tail.y)),
                         head: PrintPlanePoint(x: Double(head.x), y: Double(head.y)))
    }
}

/// A line with a filled head, as one fillable shape.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ArrowShape: Shape {
    let metrics: ArrowMetrics

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let outline = metrics.outline else { return path }

        let half = metrics.lineWidth / 2
        // The shaft as a quad rather than a stroked line, so the whole arrow is
        // one filled path and needs no separate stroke pass.
        let nx = CGFloat(-outline.unitY) * half
        let ny = CGFloat(outline.unitX) * half
        let tail = point(outline.tail)
        let end = point(outline.shaftEnd)
        path.move(to: CGPoint(x: tail.x + nx, y: tail.y + ny))
        path.addLine(to: CGPoint(x: end.x + nx, y: end.y + ny))
        path.addLine(to: CGPoint(x: end.x - nx, y: end.y - ny))
        path.addLine(to: CGPoint(x: tail.x - nx, y: tail.y - ny))
        path.closeSubpath()

        path.move(to: point(outline.head))
        path.addLine(to: point(outline.headLeft))
        path.addLine(to: point(outline.headRight))
        path.closeSubpath()

        return path
    }

    private func point(_ planePoint: PrintPlanePoint) -> CGPoint {
        CGPoint(x: planePoint.x, y: planePoint.y)
    }
}
#endif
