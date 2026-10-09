// ImageInversion.swift
// DICOMStudio
//
// DICOM Studio — displaying a frame inverted.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (a CoreGraphics difference blend that inverts a rendered frame; the reader's inversion is applied after the Presentation LUT the photometric implies, PS3.3 2026a C.7.6.3.1.2)
//
// The pixel renderer has no invert option and negating the VOI window is not
// equivalent (it clips differently once Rescale Slope/Intercept or a signed
// representation are involved), so inversion is applied to the rendered frame.
// The print path inverts P-values directly instead — same result on film, but
// exact, without a round trip through a display colour space.

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics

enum ImageInversion {

    /// Returns a photometrically inverted copy, or `nil` if it cannot be drawn.
    ///
    /// Uses a difference blend against white, which inverts grayscale and colour
    /// alike without needing to know the source's component layout.
    static func inverted(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        context.setBlendMode(.difference)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        return context.makeImage()
    }
}
#endif
