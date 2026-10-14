// Fail early if the hosted Vision runtime cannot perform actual OCR.
// Synthetic fixtures only; the full DICOM OCR/workflow tests remain required.
import Foundation
import CoreGraphics
import CoreText
import Vision
import Darwin

@available(macOS 15.0, *)
@main
struct HostedOCRCheck {
    static func report(_ error: NSError, prefix: String = "error", depth: Int = 0) {
        print("\(prefix).domain=\(error.domain)")
        print("\(prefix).code=\(error.code)")
        print("\(prefix).description=\(error.localizedDescription)")
        for key in error.userInfo.keys.sorted() {
            guard let value = error.userInfo[key] else { continue }
            print("\(prefix).userInfo[\(key)]=\(String(reflecting: value))")
            guard depth < 4 else { continue }
            if let nested = value as? NSError {
                report(nested, prefix: "\(prefix).\(key)", depth: depth + 1)
            } else if let nested = value as? [NSError] {
                for (index, item) in nested.enumerated() {
                    report(item, prefix: "\(prefix).\(key)[\(index)]", depth: depth + 1)
                }
            }
        }
    }

    static func fixturePixels(text: String) throws -> Data {
        // TextRegionDetectorTests.fixture: 512x256, DeviceGray/8-bit, Helvetica-Bold
        // 28 pt, top-left origin (24,20), 20% background and white synthetic text.
        let width = 512, height = 256
        let space = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw NSError(domain: "OCRDiagnostic.Fixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot allocate grayscale context"])
        }
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: 24, y: CGFloat(height) - 20 - bounds.maxY)
        CTLineDraw(line, context)
        guard let raw = context.data else {
            throw NSError(domain: "OCRDiagnostic.Fixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No grayscale context bytes"])
        }
        return Data(bytes: raw, count: width * height)
    }

    static func image(gray: Data, rgb: Bool) throws -> CGImage {
        let width = 512, height = 256
        var bytes = gray
        let space: CGColorSpace
        let bitmapInfo: CGBitmapInfo
        if rgb {
            guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
                throw NSError(domain: "OCRDiagnostic.Fixture", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot create sRGB color space"])
            }
            space = sRGB
            bytes = Data(capacity: gray.count * 4)
            // Explicit RGBA byte order, no color conversion, alpha always opaque.
            // RGB comes from the exact same grayscale samples used by the other cell.
            for value in gray { bytes.append(contentsOf: [value, value, value, 255]) }
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big)
        } else {
            space = CGColorSpaceCreateDeviceGray()
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        }
        guard let provider = CGDataProvider(data: bytes as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: rgb ? 32 : 8,
                bytesPerRow: width * (rgb ? 4 : 1), space: space, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else {
            throw NSError(domain: "OCRDiagnostic.Fixture", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create provider-backed image"])
        }
        // Same provider-backed grayscale CGImage format as PixelDataRenderer.
        // This isolates Vision from DICOM parsing/windowing; it is not their oracle.
        return image
    }

    static func main() async {
        print("Hosted OCR runtime: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        var failed = false
        for text in ["", "SMITH JOHN 12/03/1961"] {
            do {
                let gray = try fixturePixels(text: text)
                for rgb in [false, true] {
                    var request = RecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    request.automaticallyDetectsLanguage = false
                    let observations = try await request.perform(on: image(gray: gray, rgb: rgb))
                    let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                    let passed = text.isEmpty ? observations.isEmpty : strings == [text]
                    print("fixture=\(text.isEmpty ? "blank" : "banner") format=\(rgb ? "RGBA32" : "Gray8") passed=\(passed)")
                    if !passed { failed = true }
                }
            } catch {
                failed = true
                print("Vision error: \(String(reflecting: error))")
                report(error as NSError)
            }
        }
        exit(failed ? 1 : 0)
    }
}
