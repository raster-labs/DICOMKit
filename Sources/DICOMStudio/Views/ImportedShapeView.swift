// ImportedShapeView.swift
// DICOMStudio
//
// DICOM Studio — a shape read out of another viewer's presentation state,
// drawn on screen the way the film will burn it.
//
// Rulers, angles, polygons, circles and ellipses arrive as GSPS graphic
// objects (PS3.3 C.10.5), and a display shutter as the Display Shutter
// module. The geometry — which points mean what for each kind — is
// `ImageAnnotationBurner.shapePath`'s; this view only maps the vertices into
// the caller's coordinate space and strokes the same outline with the same
// halo, so the print preview and the viewer's non-Metal fallback show what
// the burner puts on the film.

#if canImport(SwiftUI)
import SwiftUI
import DICOMPrintKit

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ImportedShapeView: View {
    let annotation: PrintOverlayAnnotation

    /// Where a normalized image point lands in this view's coordinates.
    let point: (PrintOverlayPoint) -> CGPoint

    /// The on-screen height that stands in for the image's, so the stroke
    /// weight scales the way the burner's does.
    let lineScaleHeight: CGFloat

    var body: some View {
        let widths = ImageAnnotationBurner.shapeLineWidths(
            scale: annotation.scale, imageHeight: Double(max(1, lineScaleHeight)))
        let shape = ImportedShape(
            kind: annotation.kind,
            points: annotation.points.map(point),
            filled: annotation.filled,
            armLength: max(3, lineScaleHeight * annotation.scale * 0.5))
        ZStack {
            if annotation.kind == .shutter {
                // Everything outside the open region, in the shutter's own
                // value — even-odd against the whole cell, as on film.
                shape.fill(color(annotation.color), style: FillStyle(eoFill: true))
            } else {
                shape.stroke(halo(annotation.color),
                             style: StrokeStyle(lineWidth: CGFloat(widths.line + widths.halo),
                                                lineCap: .round, lineJoin: .round))
                shape.stroke(color(annotation.color),
                             style: StrokeStyle(lineWidth: CGFloat(widths.line),
                                                lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private func color(_ overlayColor: PrintOverlayColor) -> Color {
        Color(red: overlayColor.red, green: overlayColor.green, blue: overlayColor.blue)
    }

    private func halo(_ overlayColor: PrintOverlayColor) -> Color {
        overlayColor.luminance > 0.45 ? .black.opacity(0.9) : .white.opacity(0.9)
    }
}

/// The shape's path in view coordinates — `ImageAnnotationBurner.shapePath`
/// restated for a top-down coordinate space with an arbitrary mapping.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ImportedShape: Shape {
    let kind: PrintOverlayAnnotation.Kind
    /// The vertices, already in this view's coordinates.
    let points: [CGPoint]
    let filled: Bool
    let armLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch kind {
        case .polyline:
            guard points.count >= 2 else { return path }
            path.move(to: points[0])
            for vertex in points.dropFirst() { path.addLine(to: vertex) }
            if filled { path.closeSubpath() }

        case .circle:
            guard points.count >= 2 else { return path }
            let centre = points[0]
            let radius = hypot(points[1].x - centre.x, points[1].y - centre.y)
            guard radius > 0 else { return path }
            path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: radius * 2, height: radius * 2))

        case .ellipse:
            guard points.count >= 4 else { return path }
            let centre = CGPoint(x: (points[0].x + points[1].x) / 2,
                                 y: (points[0].y + points[1].y) / 2)
            let semiMajor = hypot(points[1].x - points[0].x, points[1].y - points[0].y) / 2
            let semiMinor = hypot(points[3].x - points[2].x, points[3].y - points[2].y) / 2
            guard semiMajor > 0, semiMinor > 0 else { return path }
            let angle = atan2(points[1].y - points[0].y, points[1].x - points[0].x)
            let transform = CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: angle)
            path.addEllipse(in: CGRect(x: -semiMajor, y: -semiMinor,
                                       width: semiMajor * 2, height: semiMinor * 2),
                            transform: transform)

        case .point:
            guard let centre = points.first else { return path }
            path.move(to: CGPoint(x: centre.x - armLength, y: centre.y))
            path.addLine(to: CGPoint(x: centre.x + armLength, y: centre.y))
            path.move(to: CGPoint(x: centre.x, y: centre.y - armLength))
            path.addLine(to: CGPoint(x: centre.x, y: centre.y + armLength))

        case .shutter:
            guard points.count >= 2 else { return path }
            path.addRect(rect)
            if points.count == 2 {
                if filled {
                    let centre = points[0]
                    let radius = hypot(points[1].x - centre.x, points[1].y - centre.y)
                    path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                               width: radius * 2, height: radius * 2))
                } else {
                    path.addRect(CGRect(
                        x: min(points[0].x, points[1].x), y: min(points[0].y, points[1].y),
                        width: abs(points[1].x - points[0].x),
                        height: abs(points[1].y - points[0].y)))
                }
            } else {
                path.move(to: points[0])
                for vertex in points.dropFirst() { path.addLine(to: vertex) }
                path.closeSubpath()
            }

        case .text, .arrow, .annotation, .length:
            break
        }
        return path
    }
}
#endif
