// Standalone hosted-runner diagnostic; synthetic pixels only, no DICOM dependencies.
// Run only if the early serial TextRegionDetectorTests gate fails.
// Matrix: native/VN x default/advertised-CPU x DeviceGray8/opaque sRGB32 x blank/banner.
// Revision and accurate/no-correction/no-language-detection settings never change.
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

    static func runVN(image: CGImage, cpu: Bool, text: String) -> Bool {
        do {
            let request = VNRecognizeTextRequest()
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = false
            // The native default recorded in the hosted baseline is en-US.
            request.recognitionLanguages = ["en-US"]
            print("revision=\(request.revision) supportedRevisions=\(VNRecognizeTextRequest.supportedRevisions)")
            print("recognitionLanguages=\(request.recognitionLanguages)")
            print("supportedRecognitionLanguages=\(try request.supportedRecognitionLanguages())")
            let stages = try request.supportedComputeStageDevices.sorted(by: {
                String(describing: $0.key) < String(describing: $1.key)
            })
            var cpuAvailableForEveryStage = !stages.isEmpty
            if stages.isEmpty { print("computeStageDevices=empty; no advertised CPU selection is possible") }
            for (stage, devices) in stages {
                if cpu {
                    if let advertisedCPU = devices.first(where: {
                        if case .cpu = $0 { return true }
                        return false
                    }) {
                        request.setComputeDevice(advertisedCPU, for: stage)
                        print("cpuSelection[\(stage)]=\(advertisedCPU)")
                    } else {
                        cpuAvailableForEveryStage = false
                        print("cpuSelection[\(stage)]=UNAVAILABLE; stage advertises no CPU")
                    }
                }
                print("computeStage=\(stage) supported=\(devices) configured=\(String(describing: request.computeDevice(for: stage)))")
            }
            if cpu && !cpuAvailableForEveryStage {
                print("status=CPU_MATRIX_CELL_UNAVAILABLE; request not performed")
                return false
            }
            print("image=\(image.width)x\(image.height) bpc=\(image.bitsPerComponent) bpp=\(image.bitsPerPixel) row=\(image.bytesPerRow) alphaInfo=\(image.alphaInfo.rawValue) bitmapInfo=\(image.bitmapInfo.rawValue)")
            print("colorSpace.name=\(String(describing: image.colorSpace?.name)) colorSpace.model=\(String(describing: image.colorSpace?.model))")
            if let data = image.dataProvider?.data { print("providerBytes=\(CFDataGetLength(data))") }
            else { print("providerBytes=unavailable") }
            let started = Date()
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let observations = request.results ?? []
            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
            print("elapsedSeconds=\(Date().timeIntervalSince(started)) observations=\(observations.count)")
            print("syntheticRecognizedText=\(strings)")
            for (index, observation) in observations.enumerated() {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let box = observation.boundingBox
                print("observation[\(index)] text=\(String(reflecting: candidate.string)) confidence=\(candidate.confidence) box=\(box.origin.x),\(box.origin.y),\(box.width),\(box.height)")
            }
            let correct = text.isEmpty ? observations.isEmpty : strings.contains { $0.uppercased().contains("SMITH") }
            print("syntheticOraclePassed=\(correct)")
            return correct
        } catch {
            print("swiftErrorType=\(String(reflecting: type(of: error)))")
            print("swiftError=\(String(reflecting: error))")
            report(error as NSError)
            return false
        }
    }

    static func main() async {
        print("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("processors=\(ProcessInfo.processInfo.activeProcessorCount)")
        print("mode=sequential native/VN x default/advertised-CPU x DeviceGray8/opaque-sRGB32 x blank/banner")
        var failed = false
        for (name, text) in [("blank", ""), ("banner", "SMITH JOHN 12/03/1961")] {
            let gray: Data
            do { gray = try fixturePixels(text: text) }
            catch { report(error as NSError); failed = true; continue }
            for cpu in [false, true] {
                for rgb in [false, true] {
                    for api in ["native", "VN"] {
                        let cell = "\(api)/\(name)/\(cpu ? "advertised-CPU" : "default")/\(rgb ? "opaque-sRGB32" : "DeviceGray8")"
                        print("BEGIN \(cell)")
                        if api == "VN" {
                            do {
                                let passed = runVN(image: try image(gray: gray, rgb: rgb), cpu: cpu, text: text)
                                print("cellPassed=\(passed)")
                                if !passed { failed = true }
                            } catch { failed = true; report(error as NSError); print("cellPassed=false") }
                            print("END \(cell)")
                            continue
                        }
                        var request = RecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.usesLanguageCorrection = false
                        request.automaticallyDetectsLanguage = false
                        print("revision=\(request.revision) supportedRevisions=\(RecognizeTextRequest.supportedRevisions)")
                        print("descriptor=\(request.descriptor)")
                        print("recognitionLanguages=\(request.recognitionLanguages)")
                        print("supportedRecognitionLanguages=\(request.supportedRecognitionLanguages)")
                        let stages = request.supportedComputeStageDevices.sorted(by: {
                            String(describing: $0.key) < String(describing: $1.key)
                        })
                        var cpuAvailableForEveryStage = !stages.isEmpty
                        if stages.isEmpty { print("computeStageDevices=empty; no advertised CPU selection is possible") }
                        for (stage, devices) in stages {
                            if cpu {
                                if let advertisedCPU = devices.first(where: {
                                    if case .cpu = $0 { return true }
                                    return false
                                }) {
                                    request.setComputeDevice(advertisedCPU, for: stage)
                                    print("cpuSelection[\(stage)]=\(advertisedCPU)")
                                } else {
                                    cpuAvailableForEveryStage = false
                                    print("cpuSelection[\(stage)]=UNAVAILABLE; stage advertises no CPU")
                                }
                            }
                            print("computeStage=\(stage) supported=\(devices) configured=\(String(describing: request.computeDevice(for: stage)))")
                        }
                        if cpu && !cpuAvailableForEveryStage {
                            // Never label a partial/default execution as a CPU-only result.
                            failed = true
                            print("status=CPU_MATRIX_CELL_UNAVAILABLE; request not performed")
                            print("END \(cell)")
                            continue
                        }
                        do {
                            let image = try image(gray: gray, rgb: rgb)
                            print("image=\(image.width)x\(image.height) bpc=\(image.bitsPerComponent) bpp=\(image.bitsPerPixel) row=\(image.bytesPerRow) alphaInfo=\(image.alphaInfo.rawValue) bitmapInfo=\(image.bitmapInfo.rawValue)")
                            print("colorSpace.name=\(String(describing: image.colorSpace?.name)) colorSpace.model=\(String(describing: image.colorSpace?.model))")
                            if let data = image.dataProvider?.data {
                                print("providerBytes=\(CFDataGetLength(data))")
                            } else { print("providerBytes=unavailable") }
                            let started = Date()
                            let observations = try await request.perform(on: image)
                            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                            print("elapsedSeconds=\(Date().timeIntervalSince(started)) observations=\(observations.count)")
                            print("syntheticRecognizedText=\(strings)")
                            for (index, observation) in observations.enumerated() {
                                guard let candidate = observation.topCandidates(1).first else { continue }
                                let box = observation.boundingBox
                                print("observation[\(index)] text=\(String(reflecting: candidate.string)) confidence=\(candidate.confidence) box=\(box.origin.x),\(box.origin.y),\(box.width),\(box.height)")
                            }
                            let correct = text.isEmpty ? observations.isEmpty : strings.contains { $0.uppercased().contains("SMITH") }
                            print("syntheticOraclePassed=\(correct)")
                            print("cellPassed=\(correct)")
                            if !correct { failed = true }
                        } catch {
                            failed = true
                            print("swiftErrorType=\(String(reflecting: type(of: error)))")
                            print("swiftError=\(String(reflecting: error))")
                            report(error as NSError)
                            print("cellPassed=false")
                        }
                        print("END \(cell)")
                    }
                }
            }
        }
        // A diagnostic failure remains a failure; no fallback and no test skip.
        exit(failed ? 1 : 0)
    }
}
