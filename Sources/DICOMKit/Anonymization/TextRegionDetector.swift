import Foundation
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Vision)
import Vision
#endif

/// Finds burned-in text in Pixel Data and returns **pixel-space rectangles** to blank.
///
/// OCR is a *region detector*, not the anonymization decision. It never modifies pixels:
/// its output is unioned into a ``PixelRedactionPlan`` (``PixelRedactionPlan/Basis/textDetection``)
/// and the ordinary redactor does the blanking on the original decoded buffer.
///
/// ## Constrained by construction
///
/// Detection runs on a **1:1, unrotated, uncropped render of the full frame** produced by
/// the shared export render path (`DICOMImageExporter.renderFrameForExport`), which honours
/// the file's VOI window — per-frame on Enhanced multiframe. That constraint reduces the
/// coordinate mapping to *flip-Y + denormalize + dilate*, so there is no rotation, crop or
/// resize arithmetic to get wrong. The worst failure this feature can have is OCR finding a
/// name while a buggy transform blanks the wrong pixels under an earned 113101, so the
/// transform is a pure static function pinned by unit tests independent of Vision.
///
/// ## Platform
///
/// Recognition uses Apple Vision, on device, through the Swift-native
/// `RecognizeTextRequest` (macOS 15 / iOS 18 / tvOS 18 / visionOS 2 — the package's own
/// baselines). Where Vision is unavailable ``detect(in:frameIndices:)`` throws
/// ``TextDetectionError/unavailable`` — never a silent "no text found".
///
/// The API generation is a *code* choice, not a detection one: `RecognizeTextRequest`
/// and the older `VNRecognizeTextRequest` drive the same recognizer (revision 3, the
/// only revision the Swift enum offers) and were measured token-for-token identical on
/// the reference frames — same strings, same boxes, same confidences, one candidate per
/// observation. In particular neither exposes per-character geometry, so a ruler tick
/// fused into a numeral (`10` + tick → `10y`) cannot be undone here; that is the
/// classifier's scale-zone rule, which reasons about declared geometry instead
/// (``PHITextClassifier/scaleZones``).
public struct TextRegionDetector: Sendable {

    /// One recognized text run, mapped to image pixels.
    public struct Detection: Sendable, Equatable {
        /// The recognized string. Keep it out of persistent logs (see `redactedForAudit`).
        public let text: String
        /// Pixel rectangle covering the glyphs, dilated and clamped to the frame.
        public let region: PixelRedactionPlan.Region
        /// Vision's confidence in `text` (0…1). Low confidence never lets text pass.
        public let confidence: Float
        /// Frame the text was recognized on.
        public let frameIndex: Int

        public init(text: String, region: PixelRedactionPlan.Region, confidence: Float, frameIndex: Int) {
            self.text = text
            self.region = region
            self.confidence = confidence
            self.frameIndex = frameIndex
        }

        /// A PHI-safe rendering for audit logs: at most the first two characters plus a
        /// length, so the log never becomes a second PHI store.
        public var redactedForAudit: String {
            let prefix = text.prefix(2)
            return "\(prefix)…(\(text.count) chars)"
        }
    }

    /// A Vision-style normalized bounding box: origin **bottom-left**, values 0…1.
    public struct NormalizedBox: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Pixels added on every side of each detected box. Vision boxes hug the glyphs
    /// and antialiased fringes stay legible, so a margin is a safety requirement.
    public static let defaultDilation = 4

    public var dilation: Int

    public init(dilation: Int = TextRegionDetector.defaultDilation) {
        self.dilation = max(0, dilation)
    }

    /// True when on-device OCR can run in this process.
    public static var isAvailable: Bool {
        #if canImport(Vision) && canImport(CoreGraphics)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Coordinate transform (pure)

    /// Maps a normalized Vision box onto image pixels.
    ///
    /// Vision's origin is bottom-left; DICOM's is top-left, so Y is flipped. Edges are
    /// rounded *outward* (floor on the near edge, ceil on the far edge) so a box never
    /// shrinks below the glyphs, then dilated by `dilation` and clamped to the frame.
    ///
    /// - Returns: `nil` when the box lies entirely outside the frame or is degenerate.
    public static func pixelRegion(
        fromNormalized box: NormalizedBox, columns: Int, rows: Int, dilation: Int
    ) -> PixelRedactionPlan.Region? {
        guard columns > 0, rows > 0, box.width > 0, box.height > 0 else { return nil }
        guard box.x.isFinite, box.y.isFinite, box.width.isFinite, box.height.isFinite else { return nil }

        let left = box.x * Double(columns)
        let right = (box.x + box.width) * Double(columns)
        // Flip: Vision's y is the bottom edge measured from the bottom.
        let top = (1.0 - (box.y + box.height)) * Double(rows)
        let bottom = (1.0 - box.y) * Double(rows)

        let d = max(0, dilation)
        var x0 = Int(left.rounded(.down)) - d
        var y0 = Int(top.rounded(.down)) - d
        var x1 = Int(right.rounded(.up)) + d
        var y1 = Int(bottom.rounded(.up)) + d

        x0 = max(0, min(columns, x0))
        y0 = max(0, min(rows, y0))
        x1 = max(0, min(columns, x1))
        y1 = max(0, min(rows, y1))

        guard x1 > x0, y1 > y0 else { return nil }
        return PixelRedactionPlan.Region(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // MARK: - Frame sampling (pure)

    /// Frames to OCR. Banners are static across a loop, so `{first, middle, last}`
    /// covers the common case; `allFrames` opts into every frame for text that appears
    /// only mid-loop (a stress-echo stage label).
    public static func sampledFrameIndices(frameCount: Int, allFrames: Bool) -> [Int] {
        let count = max(1, frameCount)
        if allFrames { return Array(0..<count) }
        var picks: [Int] = [0]
        let middle = (count - 1) / 2
        if middle != 0 { picks.append(middle) }
        let last = count - 1
        if last != 0 && last != middle { picks.append(last) }
        return picks
    }

    /// Deduplicated regions from detections across all sampled frames (each is applied
    /// to *every* frame by the redactor). Order is stable: first occurrence wins.
    public static func unionedRegions(_ detections: [Detection]) -> [PixelRedactionPlan.Region] {
        var seen = Set<PixelRedactionPlan.Region>()
        var out: [PixelRedactionPlan.Region] = []
        for d in detections where seen.insert(d.region).inserted {
            out.append(d.region)
        }
        return out
    }

    // MARK: - Detection

    /// Runs OCR on the sampled frames of a file.
    ///
    /// - Parameters:
    ///   - file: the source file, **before** header de-identification.
    ///   - frameIndices: frames to scan; `nil` selects ``sampledFrameIndices(frameCount:allFrames:)``
    ///     with `allFrames`.
    ///   - allFrames: scan every frame instead of the sample.
    /// - Throws: ``TextDetectionError/unavailable`` off Apple platforms,
    ///   ``TextDetectionError/renderFailed(frame:)`` when a frame cannot be rendered,
    ///   ``TextDetectionError/recognitionFailed(_:)`` when Vision fails.
    public func detect(
        in file: DICOMFile, frameIndices: [Int]? = nil, allFrames: Bool = false
    ) async throws -> [Detection] {
        #if canImport(Vision) && canImport(CoreGraphics)
        let pixelData = try file.tryPixelData()
        let frameCount = max(1, file.dataSet.numberOfFrames ?? 1)
        let indices = frameIndices ?? Self.sampledFrameIndices(frameCount: frameCount, allFrames: allFrames)
        guard let columns = file.dataSet.uint16(for: .columns).map({ Int($0) }),
              let rows = file.dataSet.uint16(for: .rows).map({ Int($0) }),
              columns > 0, rows > 0
        else { throw TextDetectionError.renderFailed(frame: indices.first ?? 0) }

        var all: [Detection] = []
        for index in indices where index >= 0 && index < frameCount {
            // The one window policy: the file's own VOI (per-frame on Enhanced MF),
            // rescale-adjusted — raw stored values would blow CT to white and hide text.
            let image: CGImage
            do {
                image = try DICOMImageExporter.renderFrameForExport(
                    file: file, pixelData: pixelData, frameIndex: index,
                    applyWindow: false, windowCenter: nil, windowWidth: nil)
            } catch {
                throw TextDetectionError.renderFailed(frame: index)
            }
            guard image.width == columns, image.height == rows else {
                // The transform assumes a 1:1 render; refuse rather than map onto the wrong pixels.
                throw TextDetectionError.renderFailed(frame: index)
            }
            all += try await detect(in: image, frameIndex: index)
        }
        return all
        #else
        throw TextDetectionError.unavailable
        #endif
    }

    #if canImport(Vision) && canImport(CoreGraphics)
    /// Runs OCR on one already-rendered frame. `image` must be the 1:1 frame render.
    ///
    /// `usesLanguageCorrection` stays off and language detection is pinned off: an
    /// autocorrected identifier is a changed identifier, and a "corrected" ID that no
    /// longer matches the header would silently stop being redacted.
    public func detect(in image: CGImage, frameIndex: Int) async throws -> [Detection] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // never "correct" an ID into a word
        request.automaticallyDetectsLanguage = false
        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: image)
        } catch {
            throw TextDetectionError.recognitionFailed(error.localizedDescription)
        }
        var out: [Detection] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            // `boundingBox` is Vision-normalized (lower-left origin), which is exactly
            // what `pixelRegion(fromNormalized:…)` is pinned against — keep the raw
            // normalized values here and let the one tested transform do the mapping.
            let bb = observation.boundingBox
            let box = NormalizedBox(x: bb.origin.x, y: bb.origin.y, width: bb.width, height: bb.height)
            guard let region = Self.pixelRegion(
                fromNormalized: box, columns: image.width, rows: image.height, dilation: dilation)
            else { continue }
            out.append(Detection(
                text: candidate.string, region: region,
                confidence: candidate.confidence, frameIndex: frameIndex))
        }
        return out
    }
    #endif
}

/// Errors from OCR text detection.
public enum TextDetectionError: Error, LocalizedError, Equatable {
    /// On-device OCR (Apple Vision) is not available in this build.
    case unavailable
    /// A frame could not be rendered for OCR.
    case renderFailed(frame: Int)
    /// Vision reported a failure.
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Text detection requires on-device OCR (Apple Vision), which is not available "
                + "on this platform. Use --redact-region for deterministic rectangles instead."
        case .renderFailed(let frame):
            return "Could not render frame \(frame) for text detection."
        case .recognitionFailed(let message):
            return "Text recognition failed: \(message)"
        }
    }
}
