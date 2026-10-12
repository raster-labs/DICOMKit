import Foundation
import DICOMCore

/// Orchestrates the pixel side of `dicom-anon`: detection → planning → (dry-run gate)
/// → redaction, **before** header de-identification.
///
/// This is the one implementation of the option semantics in
/// PIXEL_ANONYMIZATION_PIPELINE.md §2.1, shared by the CLI so the contract is
/// library-testable rather than living in `main.swift`:
///
/// - `--redact-region` **implies** cleaning.
/// - OCR **does not** imply cleaning — it is a region *source*.
/// - Detection feeds the refusal contract: text that was detected but will not be
///   redacted is reported in ``Report/detectedButUnredacted`` and the caller must refuse
///   to write (unless the operator accepts the risk explicitly).
/// - Nothing is written on a dry run; the plan is still built so it can be printed.
public struct PixelCleaningWorkflow: Sendable {

    /// `--recompress <codec|source>` (§5.3).
    public enum Recompress: Sendable, Equatable {
        /// Mirror the input's transfer syntax (encoding parity).
        case source
        /// A named codec from `CompressionManager.codecMap` (`jpeg-ls`, `rle`, …).
        case codec(String)

        public static func parse(_ raw: String) -> Recompress? {
            let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if v.isEmpty { return nil }
            if v == "source" { return .source }
            return CompressionManager.resolveEncoding(for: v) != nil ? .codec(v) : nil
        }
    }

    /// What `--recompress` did.
    public struct Recompression: Sendable, Equatable {
        /// Codec name actually used (`explicit-le` on a fallback).
        public let codec: String
        /// Output transfer syntax UID.
        public let transferSyntaxUID: String
        /// Transfer syntax UID of the input.
        public let sourceTransferSyntaxUID: String
        /// True when the re-encode is irreversible.
        public let lossy: Bool
        /// Honest caveats: lossy regeneration, JXL grayscale, non-encodable fallback.
        public let notes: [String]
    }

    /// OCR mode. The two modes differ on which way they fail, which is the operator's
    /// real choice; `header`'s redaction set is a subset of `classify`'s, so choosing
    /// it can only preserve more, never protect more.
    ///
    /// - `header`: redacts text that matches the study's own header PHI or a PHI-shaped
    ///   pattern (date, time, ID run); keeps everything else. On ultrasound it also
    ///   skips the "blank outside declared regions" strategy, so scales, colour bars
    ///   and legends survive. Fails **open** — burned-in text the header never carried
    ///   is not recognised.
    /// - `classify` (default): `header` plus PHI keywords, keeping only text on the
    ///   clinical allowlist. Fails closed.
    ///
    /// There is deliberately no "blank every detected region" mode: past the closed
    /// allowlist the only text left is provably clinical (laterality, units, technique
    /// factors), so blanking it buys no privacy. To erase an area regardless of what it
    /// reads, name it with `--redact-region`, which is honest about being a location
    /// rather than a PHI judgement.
    public enum TextDetectionMode: String, Sendable, CaseIterable {
        case header
        case classify

        /// Parses `--ocr-mode header|classify`; an empty value is the default.
        public static func parse(_ raw: String?) -> TextDetectionMode? {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty
            else { return .classify }
            return TextDetectionMode(rawValue: raw)
        }

        /// The classifier policy behind the mode.
        var classifierPolicy: PHITextClassifier.Policy {
            switch self {
            case .header: return .header
            case .classify: return .classify
            }
        }

        /// Whether the keep-region inversion (blank everything outside the declared
        /// Ultrasound Regions) contributes to the plan in this mode.
        public var blanksOutsideDeclaredRegions: Bool { self != .header }

        /// True when regions the classifier keeps may still carry PHI the header never
        /// held — the operator chose to accept that.
        public var isFailOpen: Bool { self == .header }

        /// Help-text names, least to most aggressive.
        public static var names: [String] { allCases.map(\.rawValue) }
    }

    /// `--redact-fill black|white|<stored value>`.
    public enum RedactFill: Sendable, Equatable {
        case black
        case white
        case value(Int)

        /// Parses the flag; an empty/nil value means the default (black, 0). `nil`
        /// result = invalid.
        public static func parse(_ raw: String?) -> RedactFill? {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty
            else { return .black }
            switch raw {
            case "black": return .black
            case "white": return .white
            default:
                guard let v = Int(raw), v >= 0 else { return nil }
                return .value(v)
            }
        }

        /// The stored pixel value for this image: `white` is the largest representable
        /// stored value at the image's Bits Stored / Pixel Representation.
        public func resolve(for dataSet: DataSet) -> Int {
            switch self {
            case .black: return 0
            case .white: return PixelRedactor.storedRange(in: dataSet).hi
            case .value(let v): return v
            }
        }

        /// The flag spelling that round-trips through `parse`.
        public var flagValue: String {
            switch self {
            case .black: return "black"
            case .white: return "white"
            case .value(let v): return String(v)
            }
        }
    }

    public struct Options: Sendable, Equatable {
        /// `--clean-pixel-data`
        public var cleanPixelData: Bool
        public var cleanRecognizableVisualFeatures = false
        /// `--redact-region` rectangles (already validated).
        public var explicitRegions: [PixelRedactionPlan.Region]
        /// `--ocr-mode`; `nil` when OCR is off (`--no-clean-pixel-data`, or a file whose
        /// Burned In Annotation = NO was taken on trust).
        public var detectText: TextDetectionMode?
        /// `--ocr-all-frames`
        public var ocrAllFrames: Bool
        /// `--text-only`: blank only the OCR text the classifier flagged (plus any
        /// explicit rectangles) — no automatic banner band from the declared
        /// Ultrasound Regions or a device template. Everything the classifier kept
        /// survives in place. Needs `detectText`; drops the band safety net.
        public var textOnly: Bool
        /// `--redact-fill` as a literal stored value (`nil` = 0). Ignored when
        /// `fillWhite` is set.
        public var fillValue: Int?
        /// `--redact-fill white`: resolved per file to the largest stored value.
        public var fillWhite: Bool
        /// Safety margin around detected text.
        public var dilation: Int
        /// `--redact-style` / `--redact-label`
        public var style: PixelRedactor.Style
        /// Regions found on OTHER parts of the same concatenation (directory mode
        /// pre-pass, ``ConcatenationSweep``). Unioned in as text-detection regions so
        /// text found in part 2 is blanked in part 1 too.
        public var presetDetectedRegions: [PixelRedactionPlan.Region]
        /// True when every part of this file's concatenation was swept, so the
        /// single-part coverage warning is not needed.
        public var concatenationAnalyzedCompletely: Bool
        /// `--recompress`: re-encode the clean pixels AFTER redaction and attestation.
        public var recompress: Recompress?
        /// `replace` style only: the header engine's post-de-identification values,
        /// derived with ``ReplacementMapping/derive(original:deidentified:)``. Never
        /// invented here — the pixels and the header must tell one story.
        public var replacementMapping: ReplacementMapping?

        public init(
            cleanPixelData: Bool = false,
            explicitRegions: [PixelRedactionPlan.Region] = [],
            detectText: TextDetectionMode? = nil,
            ocrAllFrames: Bool = false,
            fillValue: Int? = nil,
            dilation: Int = TextRegionDetector.defaultDilation,
            style: PixelRedactor.Style = .blank,
            presetDetectedRegions: [PixelRedactionPlan.Region] = [],
            concatenationAnalyzedCompletely: Bool = false,
            replacementMapping: ReplacementMapping? = nil,
            recompress: Recompress? = nil,
            fillWhite: Bool = false,
            textOnly: Bool = false
        ) {
            self.cleanPixelData = cleanPixelData
            self.explicitRegions = explicitRegions
            self.detectText = detectText
            self.ocrAllFrames = ocrAllFrames
            self.textOnly = textOnly
            self.fillValue = fillValue
            self.fillWhite = fillWhite
            self.dilation = dilation
            self.style = style
            self.presetDetectedRegions = presetDetectedRegions
            self.concatenationAnalyzedCompletely = concatenationAnalyzedCompletely
            self.replacementMapping = replacementMapping
            self.recompress = recompress
        }

        /// Pixel modification is requested: Clean Pixel Data, or rectangles (which
        /// imply it). Detection alone never modifies pixels.
        public var cleaningRequested: Bool {
            cleanPixelData || !explicitRegions.isEmpty
        }

        /// True when *any* pixel work (detection or cleaning) is configured.
        public var isActive: Bool {
            cleaningRequested || detectText != nil
        }
    }

    /// What one run did (or, on a dry run, would do).
    public struct Report: Sendable {
        /// Every OCR detection on the sampled frames (empty when OCR was off).
        public let detections: [TextRegionDetector.Detection]
        /// One verdict per detection (parallel to `detections`). In `all` mode every
        /// verdict is redact.
        public let verdicts: [PHITextClassifier.Verdict]
        /// Header attributes matched per detection (parallel; empty in `all` mode).
        public let matchedTags: [[Tag]]
        /// Frames OCR scanned.
        public let scannedFrames: [Int]
        /// The plan that was (or would be) executed; `nil` when cleaning was not requested.
        public let plan: PixelRedactionPlan?
        /// Set when pixels were actually redacted (never on a dry run).
        public let outcome: PixelRedactor.Outcome?
        /// File bytes to hand to the header pass — redacted when `outcome` is set,
        /// otherwise the input unchanged.
        public let data: Data
        /// Total frames in the object.
        public let frameCount: Int
        /// Non-refusing notes for the summary (e.g. incomplete concatenation coverage).
        public let warnings: [String]
        /// Set when `--recompress` re-encoded the clean pixels.
        public var recompression: Recompression? = nil
        /// The OCR mode that produced `verdicts` (`nil` when OCR was off).
        public var mode: TextDetectionMode? = nil
        /// The stored value actually written into blanked regions (`nil` when nothing
        /// was planned) — `white` resolves per file, so callers read it from here.
        public var resolvedFillValue: Int? = nil
        /// Detected text the run will **not** blank and that was not positively
        /// allowlisted. Non-empty means the caller must refuse to write an output file
        /// unless the operator accepted the risk.
        public var detectedButUnredacted: [TextRegionDetector.Detection] {
            guard !detections.isEmpty else { return [] }
            let wanted = zip(detections, verdicts).filter { $0.1.isRedact }.map(\.0)
            guard let plan, case .redact(let regions, _) = plan.decision else { return wanted }
            return wanted.filter { d in !regions.contains(d.region) }
        }

        /// Keep-verdict detections that actually survive: not covered by any planned
        /// rectangle (a keep verdict never shrinks another source's region, so text
        /// "kept" by the classifier inside a blanked band is gone regardless).
        public var keptAndSurviving: [TextRegionDetector.Detection] {
            let kept = zip(detections, verdicts).filter { !$0.1.isRedact }.map(\.0)
            guard let plan, case .redact(let regions, _) = plan.decision else { return kept }
            return kept.filter { d in !regions.contains { $0.covers(d.region) } }
        }

        /// PHI-safe audit lines: verdict, reason, confidence, rect, frame, truncated text.
        /// Never the full recognized string — the audit log must not become a PHI store.
        public var auditLines: [String] {
            var lines: [String] = []
            if let mode {
                lines.append("OCR mode=\(mode.rawValue)"
                             + (mode.isFailOpen ? " (header-scoped: text absent from the header is kept)" : ""))
            }
            lines += zip(detections, verdicts).map { d, v in
                "OCR frame=\(d.frameIndex) rect=\(d.region.x),\(d.region.y),\(d.region.width),\(d.region.height) "
                + "verdict=\(v.name) reason=\"\(v.reason)\" conf=\(String(format: "%.2f", d.confidence)) "
                + "text=\(d.redactedForAudit)"
            }
            if let r = recompression {
                lines.append("re-encoded to \(r.codec == "explicit-le" && r.sourceTransferSyntaxUID != r.transferSyntaxUID ? "fallback " : "")"
                             + "\(r.transferSyntaxUID) (source \(r.sourceTransferSyntaxUID), \(r.lossy ? "lossy" : "lossless"))")
            }
            return lines
        }
        /// Warnings in the same shape as `ConfidentialityEngine.residualPixelPHIWarnings`.
        public var residualWarnings: [String] {
            let leftover = detectedButUnredacted
            guard !leftover.isEmpty else { return [] }
            let frames = Set(leftover.map(\.frameIndex)).sorted()
            return ["OCR detected \(leftover.count) text region\(leftover.count == 1 ? "" : "s") "
                + "on frame\(frames.count == 1 ? "" : "s") \(frames.map(String.init).joined(separator: ",")) "
                + "that will not be redacted."]
        }
    }

    public init() {}

    // MARK: - Output encoding parity (`--recompress`, §5.3)

    /// Resolves what to encode with. `source` mirrors the input syntax, honouring the
    /// lossy/lossless intent the source declared in (0028,2110); syntaxes the toolkit
    /// cannot encode fall back to Explicit VR LE with a note — never a silent
    /// substitution, never a refusal to redact.
    static func resolveRecompressCodec(
        _ target: Recompress, sourceTransferSyntaxUID: String, sourceDataSet: DataSet
    ) -> (codec: String, notes: [String]) {
        switch target {
        case .codec(let name):
            return (name, [])
        case .source:
            let uid = sourceTransferSyntaxUID.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            let sourceIsLossy = sourceDataSet.string(for: .lossyImageCompression)?
                .trimmingCharacters(in: .whitespaces) == "01"
            let candidates = CompressionManager.codecMap.filter { $0.encoding.transferSyntax.uid == uid }
            guard !candidates.isEmpty else {
                return ("explicit-le", ["source transfer syntax \(uid) cannot be re-encoded by this toolkit — "
                                        + "output written as Explicit VR Little Endian instead"])
            }
            // Prefer the entry whose intent matches the source's declared lossy state.
            let preferred = candidates.first { entry in
                switch entry.encoding.intent {
                case .lossy: return sourceIsLossy
                case .lossless: return !sourceIsLossy
                case .notApplicable: return true
                }
            } ?? candidates[0]
            return (preferred.names[0], [])
        }
    }

    static func recompress(
        cleanData: Data, target: Recompress, sourceTransferSyntaxUID: String, sourceDataSet: DataSet,
        regions: [PixelRedactionPlan.Region], fillValue: Int
    ) throws -> (Data, Recompression) {
        var (codec, notes) = resolveRecompressCodec(
            target, sourceTransferSyntaxUID: sourceTransferSyntaxUID, sourceDataSet: sourceDataSet)
        guard let encoding = CompressionManager.resolveEncoding(for: codec) else {
            throw CompressionError.unknownCodec(codec)
        }
        // Irreversible when the intent says so, or when the syntax itself is lossy-only
        // (JPEG baseline/extended, JPEG-LS near-lossless) — the same rule the compressor
        // uses to decide whether to record a lossy generation.
        let lossy = encoding.intent == .lossy
            || (encoding.intent == .notApplicable && encoding.transferSyntax.lossyImageCompressionMethod != nil)
        if lossy {
            notes.append("lossy re-encode (\(codec)) re-quantizes the WHOLE image, not just the redacted "
                         + "regions — second-generation loss; Lossy Image Compression Ratio/Method updated")
        }
        if lossy, encoding.transferSyntax.uid == TransferSyntax.jpegXL.uid,
           (sourceDataSet.uint16(for: .samplesPerPixel) ?? 1) == 1 {
            notes.append("JPEG XL lossy (VarDCT) is RGB-only: this grayscale image is encoded lossless "
                         + "Modular under the same transfer syntax UID")
        }

        let encoded: Data
        do {
            encoded = try CompressionManager().compressData(cleanData, codec: codec, quality: nil)
        } catch {
            // Never a refusal to redact: keep the clean uncompressed output and say why.
            notes.append("re-encode with \(codec) failed (\(error.localizedDescription)) — output written as "
                         + "Explicit VR Little Endian instead")
            codec = "explicit-le"
            let fallback = Recompression(
                codec: codec, transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
                sourceTransferSyntaxUID: sourceTransferSyntaxUID, lossy: false, notes: notes)
            return (cleanData, fallback)
        }

        // Blanking oracle after the codec round-trip: the rects must still be flat fill.
        try verifyBlankAfterRecompression(encoded, regions: regions, fillValue: fillValue, lossy: lossy)

        let outUID = try DICOMFile.read(from: encoded).transferSyntaxUID ?? encoding.transferSyntax.uid
        return (encoded, Recompression(
            codec: codec, transferSyntaxUID: outUID, sourceTransferSyntaxUID: sourceTransferSyntaxUID,
            lossy: lossy, notes: notes))
    }

    /// Reopens the re-encoded output, decodes it, and checks every redacted rect on every
    /// frame is still the fill. Lossless: exact. Lossy: a flat rectangle survives as a
    /// flat rectangle, but codec ringing can bleed a few pixels at the edge, so the check
    /// insets each rect and allows a small tolerance; a rect too small to inset was
    /// already verified before re-encoding.
    static func verifyBlankAfterRecompression(
        _ data: Data, regions: [PixelRedactionPlan.Region], fillValue: Int, lossy: Bool
    ) throws {
        let (decoded, _) = try PixelEditor(verbose: false).processData(data, operations: [])
        let file = try DICOMFile.read(from: decoded)
        let ds = file.dataSet
        guard let px = ds[.pixelData]?.valueData,
              let columns = ds.uint16(for: .columns).map(Int.init),
              let rows = ds.uint16(for: .rows).map(Int.init)
        else { throw PixelRedactionError.recompressVerificationFailed("no decodable pixel data") }
        let spp = Int(ds.uint16(for: .samplesPerPixel) ?? 1)
        let bytes = Int(ds.uint16(for: .bitsAllocated) ?? 8) / 8
        let signed = (ds.uint16(for: .pixelRepresentation) ?? 0) == 1
        let frames = max(1, ds.numberOfFrames ?? 1)
        let frameBytes = rows * columns * spp * bytes
        let inset = lossy ? 8 : 0
        let tolerance = lossy ? 16 : 0
        func sample(_ i: Int) -> Int {
            if bytes == 1 { return signed ? Int(Int8(bitPattern: px[i])) : Int(px[i]) }
            let raw = UInt16(px[i]) | UInt16(px[i + 1]) << 8
            return signed ? Int(Int16(bitPattern: raw)) : Int(raw)
        }
        for r in regions {
            let x0 = r.x + inset, y0 = r.y + inset
            let x1 = min(columns, r.x + r.width) - inset, y1 = min(rows, r.y + r.height) - inset
            guard x1 > x0, y1 > y0 else { continue }
            for f in 0..<frames {
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let base = f * frameBytes + (y * columns + x) * spp * bytes
                        for c in 0..<spp {
                            let i = base + c * bytes
                            guard i + bytes <= px.count else {
                                throw PixelRedactionError.recompressVerificationFailed("pixel data truncated")
                            }
                            if abs(sample(i) - fillValue) > tolerance {
                                throw PixelRedactionError.recompressVerificationFailed(
                                    "frame \(f) pixel (\(x),\(y)) = \(sample(i)) inside redacted rect after re-encode")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Semantic replacement (`replace` style)

    /// The header engine's post-de-identification values for the attributes the
    /// classifier can match, keyed by tag. Built by comparing the ORIGINAL data set with
    /// the engine's output for the same file, so the values are the engine's own —
    /// header `ANONYMOUS`/`ANON-0042` and pixels `ANONYMOUS`/`ANON-0042`, always.
    public struct ReplacementMapping: Sendable, Equatable {
        /// Tag → replacement text to draw. A tag the header policy REMOVED or zeroed is
        /// absent: pixels must never retain information the header dropped.
        public var values: [Tag: String]

        public init(values: [Tag: String] = [:]) { self.values = values }

        /// Attributes eligible for replacement (the classifier's harvest set).
        public static let attributes: [Tag] = [
            .patientName, .otherPatientNames, .referringPhysicianName, .performingPhysicianName,
            Tag(group: 0x0008, element: 0x1070), Tag(group: 0x0008, element: 0x1048),
            Tag(group: 0x0008, element: 0x1060), .requestingPhysician,
            .patientID, .otherPatientIDs, .accessionNumber, .institutionName,
            .institutionalDepartmentName, .stationName, Tag(group: 0x0020, element: 0x0010),
            .patientBirthDate, .studyDate, .seriesDate, .acquisitionDate, .contentDate, .patientAge,
        ]

        public static func derive(original: DataSet, deidentified: DataSet) -> ReplacementMapping {
            var values: [Tag: String] = [:]
            for tag in attributes {
                guard original.string(for: tag)?.trimmingCharacters(in: .whitespaces).isEmpty == false,
                      let after = deidentified.string(for: tag)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !after.isEmpty
                else { continue }
                values[tag] = render(after, vr: deidentified[tag]?.vr)
            }
            return ReplacementMapping(values: values)
        }

        /// Human-legible form for the stamp: PN separators → spaces, DA → ISO date.
        static func render(_ value: String, vr: VR?) -> String {
            switch vr {
            case .PN?:
                let alphabetic = value.split(separator: "=", omittingEmptySubsequences: false).first.map(String.init) ?? value
                return alphabetic.split(separator: "^").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            case .DA?:
                let d = value.filter(\.isNumber)
                guard d.count == 8 else { return value }
                return "\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.suffix(2))"
            default:
                return value
            }
        }
    }

    /// Decides per detected region what the `replace` style may draw. Only a classified
    /// PHI match with a header-mapped value for EVERY matched attribute gets a value;
    /// uncertain/pattern/keyword verdicts, `all` mode, and removed attributes fall back.
    static func replacements(
        detections: [TextRegionDetector.Detection], verdicts: [PHITextClassifier.Verdict],
        matchedTags: [[Tag]], mapping: ReplacementMapping?, style: PixelRedactor.Style
    ) -> [PixelRedactionPlan.Region: PixelRedactor.Replacement] {
        guard case .replace = style else { return [:] }
        var out: [PixelRedactionPlan.Region: PixelRedactor.Replacement] = [:]
        for (i, d) in detections.enumerated() where i < verdicts.count && verdicts[i].isRedact {
            guard out[d.region] == nil else { continue }
            let tags = i < matchedTags.count ? matchedTags[i] : []
            guard !tags.isEmpty else {
                out[d.region] = .unavailable(reason: "uncertain region — nothing truthful to substitute")
                continue
            }
            guard let mapping else {
                out[d.region] = .unavailable(reason: "no header mapping supplied")
                continue
            }
            var parts: [String] = []
            for tag in tags {
                guard let v = mapping.values[tag] else {
                    out[d.region] = .unavailable(reason: "header policy removed \(tag) — blanked, not replaced")
                    break
                }
                if !parts.contains(v) { parts.append(v) }
            }
            if out[d.region] == nil { out[d.region] = .value(parts.joined(separator: " ")) }
        }
        return out
    }

    // MARK: - Concatenations

    /// Concatenation bookkeeping of one instance, when it is a part.
    public struct ConcatenationInfo: Sendable, Equatable {
        public let uid: String
        public let number: Int?
        public let total: Int?
    }

    public static func concatenationInfo(of dataSet: DataSet) -> ConcatenationInfo? {
        guard MultiframeConcatenation.isPart(dataSet),
              let uid = dataSet.string(for: .concatenationUID)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        else { return nil }
        return ConcatenationInfo(
            uid: uid,
            number: dataSet.uint16(for: .inConcatenationNumber).map(Int.init),
            total: dataSet.uint16(for: .inConcatenationTotalNumber).map(Int.init))
    }

    static func concatenationCoverageWarning(_ info: ConcatenationInfo) -> String {
        let which: String
        if let n = info.number, let t = info.total { which = "part \(n) of \(t)" }
        else if let n = info.number { which = "part \(n)" }
        else { which = "a part" }
        return "Concatenation \(info.uid): this file is \(which) and was analyzed alone — "
            + "text that appears only in another part was not detected. Process the whole "
            + "concatenation in one directory run for cross-part coverage."
    }

    /// Detects (and classifies) text in one file without cleaning, for the batch
    /// pre-pass. Returns the redact-verdict regions and the concatenation info.
    public func sweep(fileData: Data, options: Options) async throws -> (info: ConcatenationInfo?, regions: [PixelRedactionPlan.Region]) {
        let file = try DICOMFile.read(from: fileData)
        let info = Self.concatenationInfo(of: file.dataSet)
        var probe = options
        probe.cleanPixelData = false
        probe.explicitRegions = []
        probe.presetDetectedRegions = []
        probe.concatenationAnalyzedCompletely = true
        let report = try await run(fileData: fileData, options: probe, dryRun: true)
        let regions = TextRegionDetector.unionedRegions(
            zip(report.detections, report.verdicts).filter { $0.1.isRedact }.map(\.0))
        return (info, regions)
    }

    /// Directory-mode pre-pass: unions detected regions across every part of each
    /// concatenation so the union can be applied to every part (§4.4).
    public struct ConcatenationSweep: Sendable {
        public private(set) var regions: [String: [PixelRedactionPlan.Region]] = [:]
        public private(set) var partsSeen: [String: Set<Int>] = [:]
        public private(set) var totals: [String: Int] = [:]

        public init() {}

        public mutating func add(_ info: ConcatenationInfo, regions found: [PixelRedactionPlan.Region]) {
            var union = regions[info.uid] ?? []
            for r in found where !union.contains(r) { union.append(r) }
            regions[info.uid] = union
            if let n = info.number { partsSeen[info.uid, default: []].insert(n) }
            if let t = info.total { totals[info.uid] = t }
        }

        public func regions(for uid: String) -> [PixelRedactionPlan.Region] { regions[uid] ?? [] }

        /// True when every declared part of the concatenation was swept.
        public func isComplete(_ uid: String) -> Bool {
            guard let total = totals[uid], let seen = partsSeen[uid] else { return false }
            return seen.count >= total && (1...total).allSatisfy { seen.contains($0) }
        }
    }

    /// Marks an output the operator chose to write **with detected text still in the
    /// pixels** (`--allow-burned-in-phi`). The header pass asserts Patient Identity
    /// Removed = YES for the data set alone; PS3.15 conditions YES on the whole object,
    /// so a file the tool *knows* carries burned-in text must say NO — and Burned In
    /// Annotation = YES, because that is now an observed fact, not a declaration.
    public static func markDetectedTextRetained(in dataSet: inout DataSet) {
        dataSet.setString("NO", for: Tag(group: 0x0012, element: 0x0062), vr: .CS)
        dataSet.setString("YES", for: .burnedInAnnotation, vr: .CS)
    }

    /// Runs detection and (unless `dryRun`) redaction over one file's bytes.
    ///
    /// - Throws: ``TextDetectionError`` when OCR was requested and cannot run;
    ///   ``PixelRedactionError/unresolvedRegion(_:)`` when cleaning was requested but
    ///   no source resolved a region; any read/decode error.
    public func run(fileData: Data, options: Options, dryRun: Bool) async throws -> Report {
        let file = try DICOMFile.read(from: fileData)
        let frameCount = max(1, file.dataSet.numberOfFrames ?? 1)
        var notes: [String] = []

        // §4.4 A concatenation instance holds only part of the frame set. Alone, OCR
        // cannot see text that appears only in another part — say so, never claim
        // exhaustive cleaning.
        if options.detectText != nil, !options.concatenationAnalyzedCompletely,
           let info = Self.concatenationInfo(of: file.dataSet) {
            notes.append(Self.concatenationCoverageWarning(info))
        }

        // [3] Harvest PHI terms from the ORIGINAL header, before any scrubbing.
        // [4d] OCR detection — a region source, never a cleaning decision.
        var detections: [TextRegionDetector.Detection] = []
        var verdicts: [PHITextClassifier.Verdict] = []
        var matchedTags: [[Tag]] = []
        var scanned: [Int] = []
        if let mode = options.detectText {
            guard TextRegionDetector.isAvailable else { throw TextDetectionError.unavailable }
            scanned = TextRegionDetector.sampledFrameIndices(
                frameCount: frameCount, allFrames: options.ocrAllFrames)
            detections = try await TextRegionDetector(dilation: options.dilation)
                .detect(in: file, frameIndices: scanned)
            let terms = PHITextClassifier.harvestTerms(from: file.dataSet)
            let classifier = PHITextClassifier(
                terms: terms, policy: mode.classifierPolicy,
                scaleZones: PixelRedactionPlan.declaredRegions(for: file.dataSet))
            let classified = classifier.classifyDetailed(detections)
            verdicts = classified.map(\.verdict)
            matchedTags = classified.map(\.matchedTags)
            if mode.isFailOpen {
                // The mode's limit, stated on every run: nothing here proves the kept
                // text is clinical — only that the header did not contain it.
                if terms.isEmpty {
                    notes.append("OCR mode header: the header holds NO harvestable identifiers "
                                 + "(already de-identified or empty), so only PHI-shaped patterns "
                                 + "(dates, times, ID runs) can be recognised in the pixels.")
                }
                let kept = verdicts.filter { !$0.isRedact }.count
                if kept > 0 {
                    notes.append("OCR mode header: \(kept) text region\(kept == 1 ? "" : "s") kept because "
                                 + "nothing tied \(kept == 1 ? "it" : "them") to this study's header — text the "
                                 + "header never carried (stickers, annotations, RIS-entered names) is not "
                                 + "recognised by this mode. Verify visually before release.")
                }
            }
        }

        func report(plan: PixelRedactionPlan?, outcome: PixelRedactor.Outcome?, data: Data,
                    fill: Int? = nil) -> Report {
            var r = Report(detections: detections, verdicts: verdicts, matchedTags: matchedTags, scannedFrames: scanned,
                           plan: plan, outcome: outcome, data: data, frameCount: frameCount, warnings: notes)
            r.mode = options.detectText
            r.resolvedFillValue = fill
            return r
        }

        guard options.cleaningRequested else {
            return report(plan: nil, outcome: nil, data: fileData)
        }

        // [4] Plan: union of every enabled source. Only redact verdicts contribute a
        // region; a keep verdict can never shrink another source's region. Regions
        // swept from sibling concatenation parts are unioned in as well.
        var detected = TextRegionDetector.unionedRegions(
            zip(detections, verdicts).filter { $0.1.isRedact }.map(\.0))
        for r in options.presetDetectedRegions where !detected.contains(r) { detected.append(r) }
        var plan = PixelRedactionPlan.plan(
            for: file.dataSet, explicitRegions: options.explicitRegions, detectedRegions: detected,
            blankOutsideDeclaredRegions: options.detectText?.blanksOutsideDeclaredRegions ?? true,
            textOnly: options.textOnly)
        if options.textOnly {
            // The operator gave up the band safety net; say so on every run, and make a
            // refusal name the real cause (no flagged text) rather than the generic one.
            notes.append("Text-only: the automatic banner band (declared-region inversion / device "
                         + "template) is skipped — only the \(detected.count) flagged text region"
                         + "\(detected.count == 1 ? "" : "s")\(options.explicitRegions.isEmpty ? "" : " and the explicit rectangles")"
                         + " are blanked. Text OCR missed, or the classifier kept, stays. Verify visually before release.")
            if case .unresolved(let reason) = plan.decision {
                plan = PixelRedactionPlan(decision: .unresolved(
                    reason: "--text-only: OCR flagged no text to redact and no --redact-region was given, "
                        + "so nothing locates the burned-in content. " + reason))
            }
        }
        // `white` is a per-image value (Bits Stored / Pixel Representation), resolved once
        // here so the redactor, the recompress oracle and the console all see the same number.
        let fill: Int? = options.fillWhite ? RedactFill.white.resolve(for: file.dataSet) : options.fillValue

        // [5] Dry-run gate: plan built, nothing executed. An unresolved plan is still
        // surfaced as the error it would be, so a dry run predicts the real run.
        if dryRun {
            if case .unresolved(let reason) = plan.decision {
                throw PixelRedactionError.unresolvedRegion(reason)
            }
            return report(plan: plan, outcome: nil, data: fileData, fill: fill)
        }

        // [6]–[10] Decode, mask every frame, strip side channels, attest.
        let replacements = Self.replacements(
            detections: detections, verdicts: verdicts, matchedTags: matchedTags,
            mapping: options.replacementMapping, style: options.style)
        if let (redacted, outcome) = try PixelRedactor().redact(
            fileData: fileData, plan: plan, fillValue: fill, style: options.style,
            replacements: replacements) {
            var data = redacted
            if options.cleanRecognizableVisualFeatures {
                data = try PixelRedactor().redactRecognizableVisualFeatures(
                    fileData: data, regions: options.explicitRegions, fillValue: fill).data
            }
            var recompression: Recompression?
            if let target = options.recompress {
                // Strictly AFTER redaction + attestation (§5.3): decode → mask → attest → re-encode.
                let sourceUID = file.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid
                (data, recompression) = try Self.recompress(
                    cleanData: data, target: target, sourceTransferSyntaxUID: sourceUID,
                    sourceDataSet: file.dataSet, regions: outcome.regions, fillValue: fill ?? 0)
            }
            var out = report(plan: plan, outcome: outcome, data: data, fill: fill)
            out.recompression = recompression
            return out
        }
        return report(plan: plan, outcome: nil, data: fileData, fill: fill)
    }
}
