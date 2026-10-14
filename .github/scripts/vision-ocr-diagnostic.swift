// Standalone hosted-runner diagnostic; synthetic pixels only, no DICOM dependencies.
// Run only if the early serial TextRegionDetectorTests gate fails.
// This deliberately preserves RecognizeTextRequest's default revision/devices and
// the detector's accurate/no-correction/no-language-detection configuration.
import Foundation
import CoreGraphics
import CoreText
import CoreML
import Vision
import Darwin

@available(macOS 15.0, *)
@main
struct VisionOCRDiagnostic {
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

    static func fixture(text: String) throws -> CGImage {
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
        guard let raw = context.data,
              let provider = CGDataProvider(data: Data(bytes: raw, count: width * height) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else {
            throw NSError(domain: "OCRDiagnostic.Fixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create grayscale image"])
        }
        // Same provider-backed grayscale CGImage format as PixelDataRenderer.
        // This isolates Vision from DICOM parsing/windowing; it is not their oracle.
        return image
    }

    static func main() async {
        print("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        print("mode=two sequential requests; default revision and compute selection")
        var failed = false
        for (name, text) in [("blank", ""), ("banner", "SMITH JOHN 12/03/1961")] {
            print("BEGIN \(name)")
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = false
            print("revision=\(request.revision) supportedRevisions=\(RecognizeTextRequest.supportedRevisions)")
            print("descriptor=\(request.descriptor)")
            print("recognitionLanguages=\(request.recognitionLanguages)")
            print("supportedRecognitionLanguages=\(request.supportedRecognitionLanguages)")
            for (stage, devices) in request.supportedComputeStageDevices.sorted(by: {
                String(describing: $0.key) < String(describing: $1.key)
            }) {
                print("computeStage=\(stage) supported=\(devices) configured=\(String(describing: request.computeDevice(for: stage)))")
            }
            do {
                let image = try fixture(text: text)
                print("image=\(image.width)x\(image.height) bpc=\(image.bitsPerComponent) bpp=\(image.bitsPerPixel) row=\(image.bytesPerRow) bitmapInfo=\(image.bitmapInfo.rawValue)")
                let started = Date()
                let observations = try await request.perform(on: image)
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                print("elapsedSeconds=\(Date().timeIntervalSince(started)) observations=\(observations.count)")
                print("syntheticRecognizedText=\(strings)")
                let correct = text.isEmpty ? observations.isEmpty : strings.contains { $0.uppercased().contains("SMITH") }
                print("syntheticOraclePassed=\(correct)")
                if !correct { failed = true }
            } catch {
                failed = true
                print("swiftErrorType=\(String(reflecting: type(of: error)))")
                print("swiftError=\(String(reflecting: error))")
                report(error as NSError)
            }
            print("END \(name)")
        }
        // A diagnostic failure remains a failure; no fallback and no test skip.
        exit(failed ? 1 : 0)
    }
}
