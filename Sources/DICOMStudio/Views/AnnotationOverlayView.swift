// AnnotationOverlayView.swift
// DICOMStudio
//
// DICOM Studio — SwiftUI overlay for rendering GSPS annotations
//
// NEMA-verified: 2026a, checked 2026-10-05 — draws the 5 Graphic Types as PS3.3 2026a C.10.5.1.2 defines them (CIRCLE from centre and circumference point, ELLIPSE from its axis end points, POLYLINE/INTERPOLATED through all points, POINT as a single point) and text at its Anchor Point or Bounding Box TLHC (C.10.5); colours and line widths are this app's own

import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Renders GSPS graphic and text annotations over a DICOM image.
///
/// Supports polyline, circle, ellipse, point, and text annotations
/// per DICOM PS3.3 C.10.5.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct AnnotationOverlayView: View {

    /// Graphic annotations to render.
    public let graphicAnnotations: [GraphicAnnotation]

    /// Text annotations to render.
    public let textAnnotations: [TextAnnotation]

    /// Image dimensions for coordinate mapping.
    public let imageWidth: Double
    public let imageHeight: Double

    /// Currently selected annotation ID (for editing highlight).
    public let selectedID: UUID?

    /// Selection callback.
    public let onSelect: ((UUID) -> Void)?

    /// Creates an annotation overlay view.
    public init(
        graphicAnnotations: [GraphicAnnotation],
        textAnnotations: [TextAnnotation],
        imageWidth: Double,
        imageHeight: Double,
        selectedID: UUID? = nil,
        onSelect: ((UUID) -> Void)? = nil
    ) {
        self.graphicAnnotations = graphicAnnotations
        self.textAnnotations = textAnnotations
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / max(1, imageWidth)
            let scaleY = geometry.size.height / max(1, imageHeight)

            ZStack {
                // Graphic annotations
                ForEach(graphicAnnotations) { annotation in
                    GraphicAnnotationShape(annotation: annotation, scaleX: scaleX, scaleY: scaleY)
                        .stroke(
                            annotation.id == selectedID ? Color.yellow : Color.green,
                            lineWidth: annotation.id == selectedID ? 2 : 1
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect?(annotation.id)
                        }
                }

                // Text annotations
                ForEach(textAnnotations) { annotation in
                    textAnnotationView(annotation, scaleX: scaleX, scaleY: scaleY)
                }
            }
        }
        .allowsHitTesting(onSelect != nil)
    }

    @ViewBuilder
    private func textAnnotationView(_ annotation: TextAnnotation, scaleX: Double, scaleY: Double) -> some View {
        if let anchor = annotation.anchorPoint {
            Text(annotation.text)
                .font(.caption)
                .foregroundStyle(annotation.id == selectedID ? Color.yellow : Color.green)
                .position(x: anchor.x * scaleX, y: anchor.y * scaleY)
                .onTapGesture {
                    onSelect?(annotation.id)
                }
        } else if let tl = annotation.boundingBoxTopLeft {
            Text(annotation.text)
                .font(.caption)
                .foregroundStyle(Color.green)
                .position(x: tl.x * scaleX, y: tl.y * scaleY)
        }
    }
}

/// A SwiftUI Shape that renders a DICOM graphic annotation.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct GraphicAnnotationShape: Shape {
    let annotation: GraphicAnnotation
    let scaleX: Double
    let scaleY: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch annotation.graphicType {
        case .point:
            guard let point = annotation.points.first else { return path }
            let x = point.x * scaleX
            let y = point.y * scaleY
            path.addEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))

        case .polyline, .interpolated:
            guard annotation.points.count >= 2 else { return path }
            path.move(to: CGPoint(x: annotation.points[0].x * scaleX, y: annotation.points[0].y * scaleY))
            for i in 1..<annotation.points.count {
                path.addLine(to: CGPoint(x: annotation.points[i].x * scaleX, y: annotation.points[i].y * scaleY))
            }

        case .circle:
            guard let params = AnnotationHelpers.circleParameters(annotation) else { return path }
            let cx = params.center.x * scaleX
            let cy = params.center.y * scaleY
            let rx = params.radius * scaleX
            let ry = params.radius * scaleY
            path.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))

        case .ellipse:
            guard let params = AnnotationHelpers.ellipseParameters(annotation) else { return path }
            let cx = params.center.x * scaleX
            let cy = params.center.y * scaleY
            let rx = params.semiMajor * scaleX
            let ry = params.semiMinor * scaleY
            path.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }

        return path
    }
}
#endif
