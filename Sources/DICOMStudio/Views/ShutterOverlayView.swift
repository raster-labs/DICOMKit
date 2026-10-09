// ShutterOverlayView.swift
// DICOMStudio
//
// DICOM Studio — SwiftUI overlay for rendering display shutters
//
// NEMA-verified: 2026a, checked 2026-10-05 — the visible region of a shutter with several shapes is now their intersection, as PS3.3 2026a C.7.6.11 requires ("all of the shapes shall be combined and applied simultaneously, that is, the least amount of image remaining shall be visible"); the cut-out was the union: corrected; circle from centre and radius, rectangle from its four edges, polygon from its vertices (C.7.6.11); the occluded area is filled with the Shutter Presentation Value grey (0018,1622)

import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Renders a DICOM display shutter overlay masking non-visible regions.
///
/// Supports rectangular, circular, and polygonal shutter shapes per DICOM
/// PS3.3 C.7.6.11. Several shapes are "combined and applied simultaneously,
/// that is, the least amount of image remaining shall be visible": the
/// cut-out is their intersection, not their union.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct ShutterOverlayView: View {

    /// The shutter model to render.
    public let shutter: ShutterModel

    /// Image dimensions for coordinate mapping.
    public let imageWidth: Double
    public let imageHeight: Double

    /// Creates a shutter overlay view.
    public init(shutter: ShutterModel, imageWidth: Double, imageHeight: Double) {
        self.shutter = shutter
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / max(1, imageWidth)
            let scaleY = geometry.size.height / max(1, imageHeight)
            let shutterColor = Color(
                white: ShutterHelpers.normalizedShutterGray(shutter.shutterPresentationValue)
            )

            ZStack {
                // Full overlay with shutter color
                shutterColor

                // Cut out the visible region
                ShutterCutoutShape(shutter: shutter, scaleX: scaleX, scaleY: scaleY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}

/// A Shape that defines the visible (cutout) region of a shutter.
///
/// With more than one shape present the visible region is the intersection
/// of all of them (PS3.3 C.7.6.11: "the least amount of image remaining
/// shall be visible"), which is what `ShutterHelpers.isPixelVisible` tests
/// pixel by pixel. A bitmap shutter needs overlay data and is not drawn here.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct ShutterCutoutShape: Shape {
    let shutter: ShutterModel
    let scaleX: Double
    let scaleY: Double

    func path(in rect: CGRect) -> Path {
        var paths: [Path] = []

        // Rectangular cutout
        if shutter.shapes.contains(.rectangular), let rect_shutter = shutter.rectangular {
            let x = Double(rect_shutter.left) * scaleX
            let y = Double(rect_shutter.top) * scaleY
            let w = Double(rect_shutter.width) * scaleX
            let h = Double(rect_shutter.height) * scaleY
            paths.append(Path(CGRect(x: x, y: y, width: w, height: h)))
        }

        // Circular cutout
        if shutter.shapes.contains(.circular), let circ = shutter.circular {
            let cx = Double(circ.centerColumn) * scaleX
            let cy = Double(circ.centerRow) * scaleY
            let rx = Double(circ.radius) * scaleX
            let ry = Double(circ.radius) * scaleY
            paths.append(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)))
        }

        // Polygonal cutout
        if shutter.shapes.contains(.polygonal), let poly = shutter.polygonal, poly.vertices.count >= 3 {
            var polygon = Path()
            polygon.move(to: CGPoint(x: poly.vertices[0].x * scaleX, y: poly.vertices[0].y * scaleY))
            for i in 1..<poly.vertices.count {
                polygon.addLine(to: CGPoint(x: poly.vertices[i].x * scaleX, y: poly.vertices[i].y * scaleY))
            }
            polygon.closeSubpath()
            paths.append(polygon)
        }

        guard var visible = paths.first else { return Path() }
        for other in paths.dropFirst() {
            visible = visible.intersection(other)
        }
        return visible
    }
}
#endif
