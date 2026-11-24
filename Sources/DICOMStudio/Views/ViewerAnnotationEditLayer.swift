// ViewerAnnotationEditLayer.swift
// DICOMStudio
//
// DICOM Studio — drawing and editing text and arrows in the main viewer.
//
// The film print screen's `FilmCellAnnotationLayer`, re-stated for a viewport
// whose picture is a shader transform rather than an axis-aligned rectangle:
// the film cell knows an `imageRect` and positions everything against it, but
// the viewer's picture is zoomed, panned, turned and mirrored by the display
// path, so every position here goes through the same mapping the shader
// applies (`ViewerHoverGeometry`), gesture values included — chrome that
// tracked the committed transform would lag the picture mid-drag.
//
// The annotations themselves are *content*, drawn by the GPU overlay texture
// (`AnnotationTextureBuilder`) in the image's own space so they turn and zoom
// with the anatomy — this layer draws only what editing adds: selection
// chrome, endpoint handles, the inline text editor, and the gestures. On the
// rare non-Metal path there is no overlay texture, so this layer also draws
// the annotations' own shapes, upright — a legible fallback rather than a
// replica of the shader.
//
// Same store, same rules as the film: annotations live in
// `PrintSelectionModel.cellAnnotations` keyed by image identity, so an arrow
// drawn here is already on the film cell showing this image, and vice versa.

#if canImport(SwiftUI)
import SwiftUI
import DICOMPrintKit

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ViewerAnnotationEditLayer: View {
    @Bindable var viewModel: ImageViewerViewModel

    /// The armed tool. Drawing tools give this layer the whole viewport;
    /// otherwise only the annotations themselves are touchable.
    let tool: ImageViewerDragTool

    /// The transform on screen right now, in-flight gesture folded in — the
    /// same values `livePresentation` hands the shader.
    let liveZoom: Double
    let livePanX: Double
    let livePanY: Double

    /// The text annotation open for typing, if any. Owned by the parent so the
    /// GPU overlay can leave the words out while the editor shows them —
    /// otherwise the committed text sits under the field being typed into.
    @Binding var editingTextID: UUID?

    /// Whether a drawing/editing drag gesture is currently active, so the viewer's
    /// `ToolCursor` switches to the active tool's dragging pointer icon on action.
    @Binding var isToolDragging: Bool

    /// Anchor for the annotation being dragged, so a drag applies deltas.
    @State private var dragAnchor: CGSize = .zero

    /// The annotation being drawn right now — created on the first drag event,
    /// its label carried by every one after it. While this is set the inline
    /// editor stays shut: the words come after the drag, not during it.
    @State private var draftAnnotationID: UUID?

    /// Keyboard focus for the inline text editor.
    @FocusState private var isTextEditorFocused: Bool

    private static let space = "viewerAnnotationEditing"

    var body: some View {
        GeometryReader { geo in
            let mapping = makeMapping(for: geo.size)
            ZStack(alignment: .topLeading) {
                if tool.isDrawing {
                    drawingSurface(mapping)
                }
                ForEach(annotations) { annotation in
                    if annotation.isLocked {
                        // From another viewer's presentation state: shown,
                        // never grabbed. The GPU overlay draws it; this only
                        // stands in on the non-Metal paths.
                        lockedAnnotation(annotation, mapping: mapping)
                    } else {
                        switch annotation.kind {
                        case .text:  textAnnotation(annotation, mapping: mapping)
                        case .arrow: arrowAnnotation(annotation, mapping: mapping)
                        case .annotation:
                            combinedAnnotation(annotation, mapping: mapping)
                        case .length:
                            lengthAnnotation(annotation, mapping: mapping)
                        case .polyline, .circle, .ellipse, .point, .shutter:
                            lockedAnnotation(annotation, mapping: mapping)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .coordinateSpace(name: Self.space)
        // Nothing here may swallow a click meant for the picture: with no
        // drawing tool armed and nothing drawn, the layer is deaf and the
        // pan/window/zoom/rotate drags below get every event.
        .allowsHitTesting(tool.isDrawing || !annotations.isEmpty)
    }

    // MARK: - What is drawn on this image

    private var annotations: [PrintOverlayAnnotation] {
        viewModel.currentDrawnAnnotations
    }

    private var selectedAnnotationID: UUID? {
        viewModel.printSelection.selectedAnnotationID
    }

    /// Whether the GPU overlay texture is drawing the annotations' content.
    /// Without it (CPU fallback, progressive decode) this layer draws them.
    private var contentIsOnGPU: Bool {
        #if canImport(Metal)
        return viewModel.displayTexture != nil
        #else
        return false
        #endif
    }

    // MARK: - Mapping

    private func makeMapping(for size: CGSize) -> ViewerAnnotationMapping {
        ViewerAnnotationMapping(
            viewSize: size,
            imageWidth: viewModel.imageColumns,
            imageHeight: viewModel.imageRows,
            zoom: liveZoom,
            panX: livePanX,
            panY: livePanY,
            rotationDegrees: viewModel.rotationAngle,
            flipHorizontal: viewModel.isFlippedHorizontal,
            flipVertical: viewModel.isFlippedVertical,
            order: viewModel.displayTransformOrder)
    }

    // MARK: - Placing and drawing

    /// The click-and-drag surface the annotation tool owns — Weasis's grammar
    /// for its Annotation graphic, in the film cell's contract: a click places
    /// words where it lands; a press-and-drag names the thing pressed on (the
    /// anchor) and pulls the label out of it, arrow attached; a click that
    /// lands on neither the picture nor an annotation clears the selection.
    private func drawingSurface(_ mapping: ViewerAnnotationMapping) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { location in
                if tool == .annotation, let point = mapping.pointOnPicture(at: location) {
                    viewModel.addDrawnAnnotation(at: point)
                } else {
                    viewModel.selectDrawnAnnotation(nil)
                }
            }
            .gesture(annotationDrawGesture(mapping))
    }

    private func annotationDrawGesture(_ mapping: ViewerAnnotationMapping) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                isToolDragging = true
                // The press names the anchor, which must be on the picture —
                // an arrow rooted in the letterbox has no pixels to be burned
                // into. The label merely clamps, so the drag can sweep past
                // the edge and stay legal.
                guard let anchor = mapping.pointOnPicture(at: value.startLocation)
                else { return }
                let current = mapping.clampedPoint(at: value.location)
                if tool == .length {
                    if let draftAnnotationID {
                        viewModel.moveDrawnLengthEnd(draftAnnotationID, isEnd: true, to: current)
                    } else {
                        draftAnnotationID = viewModel.addDrawnLengthAnnotation(from: anchor, to: current)
                    }
                } else {
                    if let draftAnnotationID {
                        viewModel.moveDrawnArrowEnd(draftAnnotationID, isHead: false, to: current)
                    } else {
                        draftAnnotationID = viewModel.addDrawnAnnotation(at: current, anchor: anchor)
                    }
                }
            }
            .onEnded { _ in
                isToolDragging = false
                finishDraft()
            }
    }

    /// A drag too short to pull the label clear collapses back to the press
    /// point — the same annotation a plain click would have placed there. For
    /// a length ruler, a drag too short to measure anything is discarded.
    private func finishDraft() {
        defer { draftAnnotationID = nil }
        guard let draftAnnotationID,
              let drawn = annotations.first(where: { $0.id == draftAnnotationID }),
              !drawn.hasArrow else { return }
        if drawn.kind == .length {
            viewModel.removeDrawnAnnotation(draftAnnotationID)
        } else {
            viewModel.moveDrawnArrowEnd(draftAnnotationID, isHead: false, to: drawn.end)
        }
    }

    // MARK: - Text

    @ViewBuilder
    private func textAnnotation(
        _ annotation: PrintOverlayAnnotation, mapping: ViewerAnnotationMapping
    ) -> some View {
        let isSelected = selectedAnnotationID == annotation.id
        let anchor = mapping.viewPoint(annotation.start)
        // The burner's fraction of the image's rows, scaled by how large those
        // rows currently are on screen — so the chrome hugs the words at every
        // zoom, exactly as the GPU-drawn words themselves do.
        let fontSize = max(Self.minimumPreviewFontSize,
                           CGFloat(ImageAnnotationBurner.overlayFontSize(
                            imageHeight: Double(viewModel.imageRows),
                            scale: annotation.scale) * mapping.displayScale))
        let isEditing = isSelected
            && draftAnnotationID != annotation.id
            && (editingTextID == annotation.id || annotation.text.isEmpty)

        if isEditing {
            textEditor(annotation, fontSize: fontSize)
                .offset(x: anchor.x, y: anchor.y)
        } else {
            let quad = AnnotationQuadShape(
                corners: mapping.textQuadCorners(
                    for: annotation, imageRows: viewModel.imageRows,
                    imageColumns: viewModel.imageColumns))

            ZStack(alignment: .topLeading) {
                // On the non-GPU paths the words themselves, at the anchor.
                // Upright, which is no longer a fallback's compromise but the
                // same answer the GPU overlay and the film's burn now give:
                // a reader's note reads level however the picture is turned.
                if !contentIsOnGPU {
                    Text(annotation.text)
                        .font(.custom(ImageAnnotationBurner.overlayFontFamily,
                                      size: fontSize))
                        .foregroundStyle(color(annotation.color))
                        .shadow(color: halo(annotation.color),
                                radius: max(1, fontSize * 0.08))
                        .offset(x: anchor.x, y: anchor.y)
                        .allowsHitTesting(false)
                }
                quad
                    .stroke(isSelected ? Color.accentColor : .clear,
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .contentShape(quad)
                    .gesture(moveGesture(annotation, mapping: mapping))
                    .onTapGesture(count: 2) {
                        viewModel.selectDrawnAnnotation(annotation.id)
                        editingTextID = annotation.id
                    }
                    .onTapGesture { viewModel.selectDrawnAnnotation(annotation.id) }
            }
            .accessibilityLabel("Text annotation: \(annotation.text)")
        }
    }

    /// The box the words are typed into — the film's editor, at the mapped
    /// anchor. Upright whatever the picture's rotation: it is chrome for
    /// typing, not a preview of the burn.
    private func textEditor(
        _ annotation: PrintOverlayAnnotation, fontSize: CGFloat
    ) -> some View {
        let editingFontSize = max(fontSize, Self.minimumEditingFontSize)
        let font = Font.custom(ImageAnnotationBurner.overlayFontFamily,
                               size: editingFontSize)

        return TextField("Type here", text: textBinding(annotation), axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(color(annotation.color))
            .lineLimit(1...4)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: Self.minimumEditorWidth, alignment: .leading)
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
            .onChange(of: isTextEditorFocused) { _, focused in
                if !focused, editingTextID == annotation.id {
                    commitTextEditing(annotation.id)
                }
            }
            .accessibilityLabel("Text annotation editor")
    }

    /// Closes the inline editor. Deselecting discards a box nothing was typed
    /// into — see ``PrintSelectionModel/selectAnnotation(_:)``.
    private func commitTextEditing(_ id: UUID) {
        editingTextID = nil
        isTextEditorFocused = false
        if selectedAnnotationID == id { viewModel.selectDrawnAnnotation(nil) }
    }

    /// Every keystroke lands in the store the burner and the film read from.
    private func textBinding(_ annotation: PrintOverlayAnnotation) -> Binding<String> {
        Binding(
            get: {
                annotations.first(where: { $0.id == annotation.id })?.text ?? ""
            },
            set: { viewModel.setDrawnAnnotationText($0, id: annotation.id) })
    }

    // MARK: - Arrow

    @ViewBuilder
    private func arrowAnnotation(
        _ annotation: PrintOverlayAnnotation, mapping: ViewerAnnotationMapping
    ) -> some View {
        let isSelected = selectedAnnotationID == annotation.id
        let tail = mapping.viewPoint(annotation.start)
        let head = mapping.viewPoint(annotation.end)
        let line = AnnotationLineShape(start: tail, end: head)

        ZStack(alignment: .topLeading) {
            // The arrow's own shape on the non-GPU paths, from the same
            // geometry the film burns — the on-screen image height is what
            // stands in for the cell's.
            if !contentIsOnGPU {
                let metrics = ArrowMetrics(
                    scale: annotation.scale,
                    imageHeight: CGFloat(Double(viewModel.imageRows) * mapping.displayScale),
                    tail: tail, head: head)
                ArrowShape(metrics: metrics)
                    .stroke(halo(annotation.color), lineWidth: metrics.haloWidth)
                    .allowsHitTesting(false)
                ArrowShape(metrics: metrics)
                    .fill(color(annotation.color))
                    .allowsHitTesting(false)
            }

            // The grab area: the line fattened, however thin the drawn arrow.
            line
                .stroke(.clear, lineWidth: 1)
                .contentShape(line.stroke(lineWidth: Self.grabWidth))
                .gesture(moveGesture(annotation, mapping: mapping))
                .onTapGesture { viewModel.selectDrawnAnnotation(annotation.id) }

            if isSelected {
                handle(at: tail, mapping: mapping) { newPoint in
                    viewModel.moveDrawnArrowEnd(annotation.id, isHead: false,
                                                to: newPoint)
                }
                handle(at: head, mapping: mapping) { newPoint in
                    viewModel.moveDrawnArrowEnd(annotation.id, isHead: true,
                                                to: newPoint)
                }
            }
        }
        .accessibilityLabel("Arrow annotation")
    }

    // MARK: - Length

    @ViewBuilder
    private func lengthAnnotation(
        _ annotation: PrintOverlayAnnotation, mapping: ViewerAnnotationMapping
    ) -> some View {
        let isSelected = selectedAnnotationID == annotation.id
        let start = mapping.viewPoint(annotation.start)
        let end = mapping.viewPoint(annotation.end)
        let line = AnnotationLineShape(start: start, end: end)
        let labelOriginNorm = PrintAnnotationLayout.lengthLabelOrigin(
            for: annotation,
            imageWidth: Double(viewModel.imageColumns),
            imageHeight: Double(viewModel.imageRows))
        let labelAnchor = mapping.viewPoint(labelOriginNorm)
        let fontSize = max(Self.minimumPreviewFontSize,
                           CGFloat(ImageAnnotationBurner.overlayFontSize(
                            imageHeight: Double(viewModel.imageRows),
                            scale: annotation.scale) * mapping.displayScale))
        let labelOverlay = PrintOverlayAnnotation(
            id: annotation.id,
            kind: .text,
            start: labelOriginNorm,
            text: annotation.text,
            scale: annotation.scale,
            color: annotation.color)
        let labelQuad = AnnotationQuadShape(
            corners: mapping.textQuadCorners(
                for: labelOverlay, imageRows: viewModel.imageRows,
                imageColumns: viewModel.imageColumns))

        ZStack(alignment: .topLeading) {
            if !contentIsOnGPU {
                let imageHeight = Double(viewModel.imageRows) * mapping.displayScale
                let widths = ImageAnnotationBurner.shapeLineWidths(
                    scale: annotation.scale, imageHeight: max(1, imageHeight))
                let tickHalf = CGFloat(max(widths.line * 2.5, Double(fontSize) * 0.35))
                let rulerShape = LengthRulerShape(start: start, end: end, tickHalfLength: tickHalf)
                rulerShape
                    .stroke(halo(annotation.color),
                            style: StrokeStyle(lineWidth: CGFloat(widths.line + widths.halo),
                                               lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
                rulerShape
                    .stroke(color(annotation.color),
                            style: StrokeStyle(lineWidth: CGFloat(widths.line),
                                               lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)

                if annotation.hasWords {
                    Text(annotation.text)
                        .font(.custom(ImageAnnotationBurner.overlayFontFamily,
                                      size: fontSize))
                        .foregroundStyle(color(annotation.color))
                        .shadow(color: halo(annotation.color),
                                radius: max(1, fontSize * 0.08))
                        .offset(x: labelAnchor.x, y: labelAnchor.y)
                        .allowsHitTesting(false)
                }
            }

            // Grab area along the ruler segment
            line
                .stroke(.clear, lineWidth: 1)
                .contentShape(line.stroke(lineWidth: Self.grabWidth))
                .gesture(moveGesture(annotation, mapping: mapping))
                .onTapGesture { viewModel.selectDrawnAnnotation(annotation.id) }

            // Selection box and grab area around the measurement label
            if annotation.hasWords {
                labelQuad
                    .stroke(isSelected ? Color.accentColor : .clear,
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .contentShape(labelQuad)
                    .gesture(moveGesture(annotation, mapping: mapping))
                    .onTapGesture { viewModel.selectDrawnAnnotation(annotation.id) }
            }

            if isSelected {
                handle(at: start, mapping: mapping) { newPoint in
                    viewModel.moveDrawnLengthEnd(annotation.id, isEnd: false,
                                                 to: newPoint)
                }
                handle(at: end, mapping: mapping) { newPoint in
                    viewModel.moveDrawnLengthEnd(annotation.id, isEnd: true,
                                                 to: newPoint)
                }
            }
        }
        .accessibilityLabel("Length measurement: \(annotation.text)")
    }

    // MARK: - Locked annotations and shapes

    /// An annotation the reader may look at but not touch — everything read
    /// out of an imported presentation state, and every shape kind.
    ///
    /// On the GPU paths the overlay texture already draws it and this view is
    /// empty; without the texture the content is drawn here, upright text and
    /// the shape's own path, with no gesture attached so clicks fall through
    /// to the picture.
    @ViewBuilder
    private func lockedAnnotation(
        _ annotation: PrintOverlayAnnotation, mapping: ViewerAnnotationMapping
    ) -> some View {
        if !contentIsOnGPU {
            ZStack(alignment: .topLeading) {
                if annotation.isShape {
                    ImportedShapeView(
                        annotation: annotation,
                        point: { mapping.viewPoint($0) },
                        lineScaleHeight: CGFloat(Double(viewModel.imageRows) * mapping.displayScale))
                } else {
                    if annotation.hasWords {
                        let anchor = mapping.viewPoint(annotation.start)
                        let fontSize = max(Self.minimumPreviewFontSize,
                                           CGFloat(ImageAnnotationBurner.overlayFontSize(
                                            imageHeight: Double(viewModel.imageRows),
                                            scale: annotation.scale) * mapping.displayScale))
                        Text(annotation.text)
                            .font(.custom(ImageAnnotationBurner.overlayFontFamily, size: fontSize))
                            .foregroundStyle(color(annotation.color))
                            .shadow(color: halo(annotation.color), radius: max(1, fontSize * 0.08))
                            .offset(x: anchor.x, y: anchor.y)
                    }
                    if annotation.kind == .arrow || (annotation.kind == .annotation && annotation.hasArrow) {
                        let tailNorm = annotation.kind == .arrow
                            ? annotation.start
                            : PrintAnnotationLayout.leaderTail(
                                for: annotation,
                                imageWidth: Double(viewModel.imageColumns),
                                imageHeight: Double(viewModel.imageRows))
                        if let tailNorm {
                            let metrics = ArrowMetrics(
                                scale: annotation.scale,
                                imageHeight: CGFloat(Double(viewModel.imageRows) * mapping.displayScale),
                                tail: mapping.viewPoint(tailNorm),
                                head: mapping.viewPoint(annotation.end))
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
    }

    // MARK: - Combined annotation (label + arrow, after Weasis)

    /// A combined annotation: the label rendered and edited exactly as the
    /// plain text kind is, with the arrow drawn from the label's border to the
    /// anchor when the two have been pulled apart.
    ///
    /// Handles, Weasis's two: the anchor's re-aims the arrow, the label's
    /// moves the words alone. Dragging the label body or the shaft moves the
    /// whole thing, arrow direction kept.
    @ViewBuilder
    private func combinedAnnotation(
        _ annotation: PrintOverlayAnnotation, mapping: ViewerAnnotationMapping
    ) -> some View {
        let isSelected = selectedAnnotationID == annotation.id
        let tailNorm = PrintAnnotationLayout.leaderTail(
            for: annotation,
            imageWidth: Double(viewModel.imageColumns),
            imageHeight: Double(viewModel.imageRows))

        ZStack(alignment: .topLeading) {
            if let tailNorm {
                let tail = mapping.viewPoint(tailNorm)
                let head = mapping.viewPoint(annotation.end)
                let line = AnnotationLineShape(start: tail, end: head)

                // The arrow's own shape when the GPU overlay is not drawing
                // it: the non-Metal paths, and while the words are being
                // typed — the whole annotation is withheld from the texture
                // then, and the arrow must not vanish with them.
                if !contentIsOnGPU || editingTextID == annotation.id {
                    let metrics = ArrowMetrics(
                        scale: annotation.scale,
                        imageHeight: CGFloat(Double(viewModel.imageRows) * mapping.displayScale),
                        tail: tail, head: head)
                    ArrowShape(metrics: metrics)
                        .stroke(halo(annotation.color), lineWidth: metrics.haloWidth)
                        .allowsHitTesting(false)
                    ArrowShape(metrics: metrics)
                        .fill(color(annotation.color))
                        .allowsHitTesting(false)
                }

                // The shaft as a grab area, like the plain arrow's.
                line
                    .stroke(.clear, lineWidth: 1)
                    .contentShape(line.stroke(lineWidth: Self.grabWidth))
                    .gesture(moveGesture(annotation, mapping: mapping))
                    .onTapGesture { viewModel.selectDrawnAnnotation(annotation.id) }

                if isSelected {
                    handle(at: head, mapping: mapping) { newPoint in
                        viewModel.moveDrawnArrowEnd(annotation.id, isHead: true,
                                                    to: newPoint)
                    }
                }
            }

            // The label — the same view the plain text kind gets, so typing,
            // selection chrome, moving and double-click editing cannot drift
            // between the two.
            textAnnotation(annotation, mapping: mapping)

            // The label's own handle: the words move, the anchor stays put.
            if isSelected, editingTextID != annotation.id,
               draftAnnotationID != annotation.id, annotation.hasArrow {
                handle(at: mapping.viewPoint(annotation.start), mapping: mapping) { newPoint in
                    viewModel.moveDrawnArrowEnd(annotation.id, isHead: false,
                                                to: newPoint)
                }

                // And the orbit handle, which swings the label around the
                // anchor at the distance it already has. Placed a little
                // beyond the label along the arrow's own line, where it is
                // never under the two handles it sits between.
                orbitHandle(annotation, mapping: mapping)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Annotation: \(annotation.text)")
    }

    /// The handle that swings a label around its anchor.
    ///
    /// While the annotation is first being drawn, the drag itself sets the
    /// label's direction — the arrow follows the pointer out of the anchor —
    /// and letting go ends that. This restores the same move afterwards, which
    /// is what the reader asked for: re-selecting an annotation should offer
    /// the circling they had during the draw, not only the two straight drags.
    ///
    /// A ring rather than a filled dot, and set apart from the label, so the
    /// three handles a selected annotation carries are told apart by shape and
    /// position rather than by trying each one.
    private func orbitHandle(
        _ annotation: PrintOverlayAnnotation, mapping: ViewerAnnotationMapping
    ) -> some View {
        let label = mapping.viewPoint(annotation.start)
        let anchor = mapping.viewPoint(annotation.end)
        // Outward along the arrow's line, past the label — the one direction
        // that is clear of both the anchor handle and the words themselves.
        let dx = label.x - anchor.x
        let dy = label.y - anchor.y
        let length = (dx * dx + dy * dy).squareRoot()
        let position = length > 0.001
            ? CGPoint(x: label.x + dx / length * Self.orbitHandleOffset,
                      y: label.y + dy / length * Self.orbitHandleOffset)
            : CGPoint(x: label.x + Self.orbitHandleOffset, y: label.y)

        return Color.clear
            .frame(width: Self.handleGrabSize, height: Self.handleGrabSize)
            .overlay {
                // The glyph says what the handle does. Sized to the ring the
                // other handles draw, so the row of them reads as one set.
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: Self.orbitGlyphSize, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(2)
                    .background(Circle().fill(.white.opacity(0.95)))
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
            }
            .contentShape(Circle())
            .offset(x: position.x - Self.handleGrabSize / 2,
                    y: position.y - Self.handleGrabSize / 2)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        isToolDragging = true
                        // The direction from the anchor to the pointer, taken
                        // in view space and mapped into the image's — the same
                        // inverse the move gesture uses, so the label follows
                        // the hand however the picture is turned or mirrored.
                        let reach = CGSize(width: value.location.x - anchor.x,
                                           height: value.location.y - anchor.y)
                        let direction = mapping.normalizedDelta(reach)
                        viewModel.orbitDrawnAnnotationLabel(
                            annotation.id, towards: direction)
                    }
                    .onEnded { _ in
                        isToolDragging = false
                    }
            )
            .accessibilityHidden(true)
    }

    /// A draggable end of a selected arrow — the film's ring, at the mapped
    /// point.
    private func handle(
        at position: CGPoint,
        mapping: ViewerAnnotationMapping,
        move: @escaping (PrintOverlayPoint) -> Void
    ) -> some View {
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
                    .onChanged { value in
                        isToolDragging = true
                        move(mapping.clampedPoint(at: value.location))
                    }
                    .onEnded { _ in
                        isToolDragging = false
                    }
            )
            .accessibilityHidden(true)
    }

    // MARK: - Moving

    /// Drag anywhere on an annotation to move the whole thing — deltas mapped
    /// through the inverse transform, so a drag right moves the annotation
    /// right on screen whatever way the picture is turned.
    private func moveGesture(
        _ annotation: PrintOverlayAnnotation, mapping: ViewerAnnotationMapping
    ) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                isToolDragging = true
                if selectedAnnotationID != annotation.id {
                    viewModel.selectDrawnAnnotation(annotation.id)
                }
                let dx = value.translation.width - dragAnchor.width
                let dy = value.translation.height - dragAnchor.height
                dragAnchor = value.translation
                let delta = mapping.normalizedDelta(CGSize(width: dx, height: dy))
                viewModel.moveDrawnAnnotation(annotation.id, dx: delta.dx, dy: delta.dy)
            }
            .onEnded { _ in
                isToolDragging = false
                dragAnchor = .zero
            }
    }

    // MARK: - Colours

    private func color(_ overlayColor: PrintOverlayColor) -> Color {
        Color(red: overlayColor.red, green: overlayColor.green, blue: overlayColor.blue)
    }

    private func halo(_ overlayColor: PrintOverlayColor) -> Color {
        overlayColor.luminance > 0.45 ? .black.opacity(0.9) : .white.opacity(0.9)
    }

    // MARK: - Constants (the film's, so the two screens feel the same)

    private static let minimumPreviewFontSize: CGFloat = 6
    private static let minimumEditingFontSize: CGFloat = 12
    private static let minimumEditorWidth: CGFloat = 140
    private static let handleSize: CGFloat = 6
    private static let handleGrabSize: CGFloat = 16
    /// How far past the label the orbit handle sits, in view points — clear of
    /// the words and of the label handle underneath them.
    private static let orbitHandleOffset: CGFloat = 18
    private static let orbitGlyphSize: CGFloat = 7
    private static let grabWidth: CGFloat = 12
}

// MARK: - Mapping

/// The screen transform, bundled so every gesture and every piece of chrome
/// maps through exactly one set of values — the ones the shader is drawing
/// with this frame.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ViewerAnnotationMapping {
    let viewSize: CGSize
    let imageWidth: Int
    let imageHeight: Int
    let zoom: Double
    let panX: Double
    let panY: Double
    let rotationDegrees: Double
    let flipHorizontal: Bool
    let flipVertical: Bool
    let order: ViewerTransformOrder

    /// Where a stored point lands on screen.
    func viewPoint(_ point: PrintOverlayPoint) -> CGPoint {
        ViewerHoverGeometry.viewPoint(
            forNormalizedX: point.x, y: point.y,
            viewSize: viewSize, imageWidth: imageWidth, imageHeight: imageHeight,
            zoom: zoom, panX: panX, panY: panY,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal, flipVertical: flipVertical,
            order: order)
    }

    /// The stored point under a click, or `nil` when the click missed the
    /// picture — the letterbox must not take an annotation.
    func pointOnPicture(at location: CGPoint) -> PrintOverlayPoint? {
        guard let fraction = normalizedFraction(at: location),
              fraction.x >= 0, fraction.x <= 1,
              fraction.y >= 0, fraction.y <= 1 else { return nil }
        return PrintOverlayPoint(x: fraction.x, y: fraction.y)
    }

    /// The stored point under a drag, clamped onto the picture — for the
    /// gestures that legitimately stray past its edge.
    func clampedPoint(at location: CGPoint) -> PrintOverlayPoint {
        guard let fraction = normalizedFraction(at: location) else {
            return PrintOverlayPoint(x: 0, y: 0)
        }
        // PrintOverlayPoint clamps to 0…1 itself.
        return PrintOverlayPoint(x: fraction.x, y: fraction.y)
    }

    private func normalizedFraction(at location: CGPoint) -> (x: Double, y: Double)? {
        ViewerHoverGeometry.normalizedImagePoint(
            atViewPoint: location,
            viewSize: viewSize, imageWidth: imageWidth, imageHeight: imageHeight,
            zoom: zoom, panX: panX, panY: panY,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal, flipVertical: flipVertical,
            order: order)
    }

    /// A view-space drag as the normalized delta it moves an annotation by.
    func normalizedDelta(_ translation: CGSize) -> (dx: Double, dy: Double) {
        ViewerHoverGeometry.normalizedDelta(
            forViewDelta: translation,
            viewSize: viewSize, imageWidth: imageWidth, imageHeight: imageHeight,
            zoom: zoom, rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal, flipVertical: flipVertical,
            order: order)
    }

    /// View points per image pixel, for sizing chrome.
    var displayScale: Double {
        ViewerHoverGeometry.displayScale(
            viewSize: viewSize, imageWidth: imageWidth, imageHeight: imageHeight,
            zoom: zoom)
    }

    /// The four screen corners of a text annotation's words.
    ///
    /// The *anchor* travels with the picture — the words stay stuck to the
    /// anatomy they were dropped on — but the box around them is upright and
    /// axis-aligned, because the words themselves are: the overlay rasterizer
    /// cancels the arrangement for lettering (see ``PrintOverlayOrientation``),
    /// so type on a turned picture reads level. This used to build a quad
    /// turned with the picture, and once the words stopped turning the dashed
    /// selection box and the click target sat at an angle to the text they
    /// belonged to.
    ///
    /// Still four corners rather than a `CGRect`: the caller strokes and
    /// hit-tests a path, and the anchor may be anywhere on screen.
    func textQuadCorners(
        for annotation: PrintOverlayAnnotation, imageRows: Int, imageColumns: Int
    ) -> [CGPoint] {
        guard imageRows > 0, imageColumns > 0 else { return [] }
        let measured = PrintOverlayAnnotationGSPS.measuredTextSize(
            annotation.text, imageHeight: Double(imageRows), scale: annotation.scale)
        // Never smaller than a line of type, so empty-adjacent text still has
        // something to click.
        let fontSize = ImageAnnotationBurner.overlayFontSize(
            imageHeight: Double(imageRows), scale: annotation.scale)
        // In screen points, since the box is measured on screen now: the type
        // is drawn at the image's own scale times whatever the view is showing
        // it at, which is exactly `displayScale`.
        let width = max(measured.width, fontSize) * displayScale
        let height = max(measured.height, fontSize) * displayScale

        let anchor = viewPoint(annotation.start)
        return [
            anchor,
            CGPoint(x: anchor.x + width, y: anchor.y),
            CGPoint(x: anchor.x + width, y: anchor.y + height),
            CGPoint(x: anchor.x, y: anchor.y + height)
        ]
    }
}

// MARK: - Hit shapes

/// A quadrilateral through four mapped corners — a text annotation's words on
/// a possibly-turned picture.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct AnnotationQuadShape: Shape {
    let corners: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard corners.count == 4 else { return path }
        path.move(to: corners[0])
        for corner in corners.dropFirst() { path.addLine(to: corner) }
        path.closeSubpath()
        return path
    }
}

/// The straight line between an arrow's mapped ends, stroked wide for the
/// pointer.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct AnnotationLineShape: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

/// A linear measurement ruler: the segment between `start` and `end` plus
/// perpendicular tick marks at both ends.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct LengthRulerShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let tickHalfLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return path }

        let nx = -dy / len * tickHalfLength
        let ny = dx / len * tickHalfLength

        path.move(to: start)
        path.addLine(to: end)

        path.move(to: CGPoint(x: start.x - nx, y: start.y - ny))
        path.addLine(to: CGPoint(x: start.x + nx, y: start.y + ny))

        path.move(to: CGPoint(x: end.x - nx, y: end.y - ny))
        path.addLine(to: CGPoint(x: end.x + nx, y: end.y + ny))

        return path
    }
}
#endif
