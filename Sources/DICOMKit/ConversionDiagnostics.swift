// NEMA-verified: 2026a, checked 2026-10-01 — the JPEG XL JPEG Recompression source rules match the two
// .111 rows of PS3.5 2026a Table 8.2.15-1 (Photometric Interpretation per Samples per Pixel, Pixel
// Representation 0, Bits Allocated / Stored 8), dumped by script; the 1-based frame-number rule cites PS3.3
// 2026a Table 10-3 (Referenced Frame Number: "The first Frame shall be denoted as Frame number 1"); transfer
// syntax names come from TransferSyntax.displayName (PS3.6 Table A-1).
import Foundation
import DICOMCore

// MARK: - ConversionFailure

/// A readable explanation of why a `dicom-convert` conversion cannot run or failed.
///
/// This is the single error type both the `dicom-convert` CLI and DICOMStudio's
/// Workshop report, so the two surfaces print the same text. It names the source and
/// target transfer syntaxes, the reason in plain words, the source's pixel attributes
/// when they matter, and a suggestion for what to pick instead.
///
/// It is produced two ways:
/// - ``DICOMConverter/checkConversion(dicomFile:to:)`` inspects the source *before*
///   any work and rejects a mismatched source transfer syntax or pixel format.
/// - ``DICOMConverter/convertToDICOM(dicomFile:to:stripPrivate:)-(_,SelectableEncoding,_)``
///   wraps any later codec or parser error with the same context.
///
/// ``ConversionFailure/init(describing:)`` turns *any* error, including read errors
/// raised before a conversion starts, into this shape, so the shared console
/// formatter ``ConvertConsole/failureReport(for:)`` always has something readable.
public struct ConversionFailure: Error, LocalizedError, Sendable, Equatable {

    /// Which stage or rule the failure belongs to.
    public enum Category: String, Sendable, Equatable {
        /// The input could not be parsed as DICOM.
        case unreadableInput
        /// The source transfer syntax UID is unknown, retired or undecodable.
        case unsupportedSource
        /// DICOMKit has no encoder for the target transfer syntax.
        case unsupportedTarget
        /// The pixel attributes are outside what the target codec can encode.
        case pixelFormatNotSupported
        /// JPEG XL JPEG Recompression (…4.111) was asked of an unsuitable source.
        case recompressionSource
        /// The conversion would add loss the configuration does not allow.
        case lossyNotAllowed
        /// Decoding the source pixel data failed.
        case decodeFailed
        /// Encoding the target pixel data failed.
        case encodeFailed
        /// Anything else.
        case other
    }

    public let category: Category
    /// Source transfer syntax label, e.g. "JPEG Lossless (Process 14) [1.2.840.10008.1.2.4.57]".
    public let source: String?
    /// Target transfer syntax label.
    public let target: String?
    /// Why the conversion cannot run, in plain words.
    public let reason: String
    /// The source pixel attributes that matter for this failure, one line.
    public let sourceDetails: String?
    /// What to do instead, when there is a sensible alternative.
    public let suggestion: String?
    /// The underlying technical error text, when it adds information.
    public let technical: String?

    public init(
        category: Category,
        source: String? = nil,
        target: String? = nil,
        reason: String,
        sourceDetails: String? = nil,
        suggestion: String? = nil,
        technical: String? = nil
    ) {
        self.category = category
        self.source = source
        self.target = target
        self.reason = reason
        self.sourceDetails = sourceDetails
        self.suggestion = suggestion
        self.technical = technical
    }

    /// First line: what was attempted, or `nil` when there is nothing more specific
    /// to say than the reason itself (for example a missing command-line option).
    public var headline: String? {
        switch (source, target) {
        case let (s?, t?): return "Cannot convert \(s) to \(t)."
        case let (nil, t?): return "Cannot convert to \(t)."
        case let (s?, nil): return "Cannot convert \(s)."
        default:
            return category == .unreadableInput ? "Cannot read the input as a DICOM file." : nil
        }
    }

    /// The full multi-line message shared by the CLI and the app.
    public var message: String {
        guard let headline else {
            return ([reason] + [suggestion].compactMap { $0 }.map { "Suggestion: \($0)" })
                .joined(separator: "\n")
        }
        var lines = [headline, "Reason: \(reason)"]
        if let sourceDetails { lines.append("Source: \(sourceDetails)") }
        if let suggestion { lines.append("Suggestion: \(suggestion)") }
        if let technical, !technical.isEmpty, technical != reason {
            lines.append("Details: \(technical)")
        }
        return lines.joined(separator: "\n")
    }

    /// One-line form for batch progress lines: the reason plus the suggestion.
    public var summary: String {
        suggestion.map { "\(reason) \($0)" } ?? reason
    }

    public var errorDescription: String? { message }

    /// Wraps any error into a ``ConversionFailure``. An existing ``ConversionFailure``
    /// is returned unchanged; DICOM read errors, transcoding errors and codec errors
    /// are translated into plain words.
    public init(describing error: Error) {
        if let failure = error as? ConversionFailure {
            self = failure
            return
        }
        self = ConversionFailure.translate(error, source: nil, target: nil)
    }

    /// Translates a raw error into a ``ConversionFailure`` with the given labels.
    static func translate(_ error: Error, source: String?, target: String?) -> ConversionFailure {
        if let failure = error as? ConversionFailure { return failure }
        let technical = String(describing: error)

        if let dicomError = error as? DICOMError {
            switch dicomError {
            case .invalidDICMPrefix, .invalidPreamble:
                return ConversionFailure(
                    category: .unreadableInput, source: source, target: target,
                    reason: "The input is not a DICOM Part 10 file. It has no 128-byte preamble followed by \"DICM\".",
                    suggestion: "If it is a raw DICOM data set without a file header, enable Force (--force).")
            case .unexpectedEndOfData:
                return ConversionFailure(
                    category: .unreadableInput, source: source, target: target,
                    reason: "The input ends before the DICOM data is complete. The file is truncated or damaged.",
                    technical: technical)
            case .unsupportedTransferSyntax(let uid):
                return ConversionFailure(
                    category: .unsupportedSource, source: source ?? label(forUID: uid), target: target,
                    reason: "DICOMKit does not support the source transfer syntax \(uid).",
                    technical: technical)
            default:
                return ConversionFailure(
                    category: source == nil && target == nil ? .unreadableInput : .decodeFailed,
                    source: source, target: target,
                    reason: "The DICOM data could not be parsed.",
                    technical: technical)
            }
        }

        if let transcodingError = error as? TranscodingError {
            switch transcodingError {
            case .unsupportedSourceSyntax:
                return ConversionFailure(
                    category: .unsupportedSource, source: source, target: target,
                    reason: "DICOMKit cannot decode pixel data in the source transfer syntax.",
                    technical: technical)
            case .unsupportedTargetSyntax:
                return ConversionFailure(
                    category: .unsupportedTarget, source: source, target: target,
                    reason: "DICOMKit has no conversion path from the source to the target transfer syntax.",
                    technical: technical)
            case .lossyCompressionNotAllowed:
                return ConversionFailure(
                    category: .lossyNotAllowed, source: source, target: target,
                    reason: "The conversion would lose image detail, and lossy output was not allowed.",
                    suggestion: "Choose a lossless target, or the explicit lossy variant of the target.",
                    technical: technical)
            case .pixelDataExtractionFailed:
                return ConversionFailure(
                    category: .decodeFailed, source: source, target: target,
                    reason: "The source pixel data could not be read. Required image attributes may be missing or inconsistent.",
                    technical: technical)
            case .encodingFailed:
                return ConversionFailure(
                    category: .encodeFailed, source: source, target: target,
                    reason: "The target encoder could not compress the pixel data.",
                    technical: technical)
            case .parsingFailed:
                return ConversionFailure(
                    category: .decodeFailed, source: source, target: target,
                    reason: "The source data set could not be parsed.",
                    technical: technical)
            case .noCompatibleSyntax, .fidelityLost:
                return ConversionFailure(
                    category: .other, source: source, target: target,
                    reason: transcodingError.description,
                    technical: technical)
            }
        }

        let described = readableText(for: error)
        return ConversionFailure(
            category: .other, source: source, target: target,
            reason: described, technical: described == technical ? nil : technical)
    }

    /// Readable text for an arbitrary error. Swift errors that are not `LocalizedError`
    /// (for example ArgumentParser's `ValidationError`) otherwise surface as Foundation's
    /// "The operation couldn't be completed. (… error 1.)" fallback.
    static func readableText(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription { return localized }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain || ns.domain == NSURLErrorDomain {
            return ns.localizedDescription
        }
        return String(describing: error)
    }

    /// "Display Name [UID]" for a known UID, or the bare UID.
    static func label(forUID uid: String) -> String {
        guard let syntax = TransferSyntax.from(uid: uid) else { return uid }
        return label(for: syntax)
    }

    static func label(for syntax: TransferSyntax) -> String {
        "\(syntax.displayName) [\(syntax.uid)]"
    }
}

// MARK: - Pre-conversion checks

extension DICOMConverter {

    /// Shared text when DICOM output is requested without a target transfer syntax.
    public static let missingTargetMessage =
        "A target transfer syntax is required for DICOM output. Choose one with --transfer-syntax (Transfer Syntax in the app)."

    /// Shared text when an image export asks for a frame the file does not have.
    public static func invalidFrameMessage(requested: Int, total: Int) -> String {
        "Frame \(requested) does not exist. The file has \(total) frame\(total == 1 ? "" : "s"), numbered 0 to \(max(total - 1, 0))."
    }

    /// Shared text when an image export asks for a Frame number (1-based, PS3.3 Table 10-3:
    /// "The first Frame shall be denoted as Frame number 1") the file does not have.
    public static func invalidFrameNumberMessage(requested: Int, total: Int) -> String {
        "Frame number \(requested) does not exist. The file has \(total) frame\(total == 1 ? "" : "s"), numbered 1 to \(max(total, 1))."
    }

    /// Checks that `dicomFile` can be converted to `encoding` and throws a
    /// ``ConversionFailure`` naming the exact mismatch when it cannot.
    ///
    /// The pixel-format verdict comes from the target encoder's own `canEncode`
    /// (including the automatic 16 → 8-bit reduction the transcoder applies for
    /// 8-bit-only targets), so this never rejects a conversion that would succeed.
    /// The per-target rule table only supplies the wording.
    ///
    /// Called by ``convertToDICOM(dicomFile:to:stripPrivate:)-(_,SelectableEncoding,_)``,
    /// and public so a UI can validate a choice before running.
    public static func checkConversion(dicomFile: DICOMFile, to encoding: SelectableEncoding) throws {
        let target = encoding.transferSyntax
        let targetLabel = ConversionFailure.label(for: target)
        let dataSet = dicomFile.dataSet

        // 1. The source transfer syntax must be one DICOMKit knows. An unknown UID
        //    would otherwise be read as uncompressed and produce garbage.
        let sourceUID = dicomFile.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid
        guard let source = TransferSyntax.from(uid: sourceUID) else {
            throw ConversionFailure(
                category: .unsupportedSource, source: sourceUID, target: targetLabel,
                reason: "The source transfer syntax \(sourceUID) is not one DICOMKit recognises. "
                    + "It may be retired, private, or misspelled in the file meta information.",
                suggestion: "Check the Transfer Syntax UID (0002,0010) of the input file.")
        }
        let sourceLabel = ConversionFailure.label(for: source)
        if source.uid == target.uid { return }  // plain copy, nothing to check

        let descriptor = try? CompressionManager.buildPixelDataDescriptor(from: dataSet)
        let details = descriptor.map(describe)

        // 2. JPEG XL JPEG Recompression, forward and reverse.
        if target.uid == TransferSyntax.jpegXLRecompression.uid {
            try checkRecompressionSource(
                source: source, dataSet: dataSet, descriptor: descriptor,
                sourceLabel: sourceLabel, targetLabel: targetLabel, details: details)
            return
        }
        if source.uid == TransferSyntax.jpegXLRecompression.uid,
           TransferSyntaxConverter.jxlRecompressibleJPEGSyntaxUIDs.contains(target.uid) {
            return  // byte-exact JPEG reconstruction; the frame type is checked per fragment
        }

        // 3. An encapsulated source must be decodable, unless the target keeps the
        //    codestream (J2K ↔ HTJ2K fast path is handled by the transcoder itself).
        if source.isEncapsulated, !source.isDeflated,
           !CodecRegistry.shared.hasCodec(for: source.uid) {
            throw ConversionFailure(
                category: .unsupportedSource, source: sourceLabel, target: targetLabel,
                reason: "DICOMKit has no decoder for \(source.displayName), so its pixel data cannot be read.",
                sourceDetails: details)
        }

        // 4. Uncompressed and deflated targets accept any pixel format.
        guard target.isEncapsulated, !target.isDeflated else { return }

        // 5. The target needs an encoder.
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: target.uid) {
            throw ConversionFailure(
                category: .unsupportedTarget, source: sourceLabel, target: targetLabel,
                reason: reason,
                suggestion: suggestion(forTarget: target, descriptor: descriptor))
        }
        guard let encoder = CodecRegistry.shared.encoder(for: target.uid) else {
            throw ConversionFailure(
                category: .unsupportedTarget, source: sourceLabel, target: targetLabel,
                reason: "DICOMKit can read \(target.displayName) but cannot write it.",
                suggestion: suggestion(forTarget: target, descriptor: descriptor))
        }

        // 6. The pixel format must suit the encoder. Without pixel data there is
        //    nothing to encode, and the transcoder copies the data set as-is.
        guard let descriptor, dataSet[.pixelData] != nil else { return }
        let encodeLossless: Bool
        switch target.losslessCapability {
        case .both:         encodeLossless = (encoding.intent == .lossless)
        case .losslessOnly: encodeLossless = true
        case .lossyOnly:    encodeLossless = false
        }
        let configuration: DICOMCore.CompressionConfiguration = encodeLossless ? .lossless : .default
        if encoder.canEncode(with: configuration, descriptor: descriptor) { return }
        if descriptor.bitsAllocated == 16, descriptor.samplesPerPixel <= 3,
           encoder.canEncode(with: configuration, descriptor: eightBitVariant(of: descriptor)) {
            return  // the transcoder windows 16-bit data down to 8-bit for this target
        }

        let rule = PixelRule.forTarget(target)
        let violations = rule?.violations(of: descriptor, targetName: target.displayName) ?? []
        let reason = violations.isEmpty
            ? "\(target.displayName) cannot encode this pixel format."
                + (rule.map { " It needs \($0.requirement)." } ?? "")
            : violations.joined(separator: " ")
        throw ConversionFailure(
            category: .pixelFormatNotSupported, source: sourceLabel, target: targetLabel,
            reason: reason, sourceDetails: details,
            suggestion: suggestion(forTarget: target, descriptor: descriptor))
    }

    // MARK: Recompression

    private static func checkRecompressionSource(
        source: TransferSyntax, dataSet: DataSet, descriptor: PixelDataDescriptor?,
        sourceLabel: String, targetLabel: String, details: String?
    ) throws {
        let losslessAlternative = "Use JPEG XL Lossless (jxl-lossless-only) for a bit-exact JPEG XL copy instead."
        guard TransferSyntaxConverter.jxlRecompressibleJPEGSyntaxUIDs.contains(source.uid) else {
            let why: String
            switch source.uid {
            case TransferSyntax.jpegLossless.uid, TransferSyntax.jpegLosslessSV1.uid:
                why = "The source is lossless JPEG, which uses predictive coding (SOF3) and has no DCT coefficients to carry over."
            case _ where !source.isEncapsulated || source.isDeflated:
                why = "The source is uncompressed, so there is no JPEG bitstream to wrap."
            default:
                why = "The source is \(source.displayName), not a JPEG bitstream."
            }
            throw ConversionFailure(
                category: .recompressionSource, source: sourceLabel, target: targetLabel,
                reason: "JPEG XL JPEG Recompression only wraps an 8-bit DCT JPEG (JPEG Baseline or JPEG Extended). " + why,
                sourceDetails: details,
                suggestion: losslessAlternative)
        }
        // PS3.5 Table 8.2.15-1: …4.111 is 8-bit unsigned, 1 or 3 samples, and not MONOCHROME1.
        guard let descriptor else { return }  // the transcoder reports missing attributes
        var problems: [String] = []
        if descriptor.bitsAllocated != 8 || descriptor.bitsStored != 8 {
            problems.append("The source is \(descriptor.bitsStored)-bit, but JPEG XL JPEG Recompression carries only 8-bit JPEG. 12-bit JPEG cannot be recompressed.")
        }
        if descriptor.isSigned {
            problems.append("The source pixels are signed, but JPEG XL JPEG Recompression requires unsigned pixels.")
        }
        if descriptor.samplesPerPixel != 1 && descriptor.samplesPerPixel != 3 {
            problems.append("The source has \(descriptor.samplesPerPixel) samples per pixel, but only 1 or 3 are allowed.")
        }
        // Table 8.2.15-1 rows for …4.111: MONOCHROME2 with 1 sample; YBR_FULL_422, XYB or RGB with 3.
        let pi = descriptor.photometricInterpretation
        if pi == .monochrome1 {
            problems.append("MONOCHROME1 is not allowed with JPEG XL JPEG Recompression (DICOM PS3.5 Table 8.2.15-1).")
        } else if descriptor.samplesPerPixel == 1 && pi != .monochrome2 {
            problems.append("With 1 sample per pixel JPEG XL JPEG Recompression allows only MONOCHROME2, not \(pi.rawValue) (DICOM PS3.5 Table 8.2.15-1).")
        } else if descriptor.samplesPerPixel == 3 && ![.ybrFull422, .xyb, .rgb].contains(pi) {
            problems.append("With 3 samples per pixel JPEG XL JPEG Recompression allows only YBR_FULL_422, XYB or RGB, not \(pi.rawValue) (DICOM PS3.5 Table 8.2.15-1).")
        }
        if !problems.isEmpty {
            throw ConversionFailure(
                category: .recompressionSource, source: sourceLabel, target: targetLabel,
                reason: problems.joined(separator: " "),
                sourceDetails: details,
                suggestion: losslessAlternative)
        }
    }

    // MARK: Helpers

    /// "Bits Allocated 16, Bits Stored 12, unsigned, 1 sample, MONOCHROME2, 1 frame".
    static func describe(_ d: PixelDataDescriptor) -> String {
        let samples = d.samplesPerPixel == 1 ? "1 sample" : "\(d.samplesPerPixel) samples"
        let frames = d.numberOfFrames == 1 ? "1 frame" : "\(d.numberOfFrames) frames"
        return "Bits Allocated \(d.bitsAllocated), Bits Stored \(d.bitsStored), "
            + "\(d.isSigned ? "signed" : "unsigned"), \(samples) per pixel, "
            + "\(d.photometricInterpretation.rawValue), \(frames), \(d.columns)×\(d.rows)"
    }

    static func eightBitVariant(of d: PixelDataDescriptor) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: d.rows, columns: d.columns, numberOfFrames: d.numberOfFrames,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            samplesPerPixel: d.samplesPerPixel,
            photometricInterpretation: d.photometricInterpretation,
            planarConfiguration: d.planarConfiguration)
    }

    /// A target the source *can* go to, phrased as advice.
    static func suggestion(forTarget target: TransferSyntax, descriptor: PixelDataDescriptor?) -> String? {
        guard let d = descriptor else { return nil }
        if d.bitsAllocated > 16 || (d.samplesPerPixel != 1 && d.samplesPerPixel != 3) {
            return "Keep it uncompressed (explicit-vr-little-endian) or use Deflated Explicit VR Little Endian."
        }
        if d.isSigned && d.bitsAllocated == 8 {
            return "Use JPEG-LS Lossless, JPEG 2000 Lossless or HTJ2K Lossless, which accept signed 8-bit data."
        }
        if d.samplesPerPixel == 1, d.numberOfFrames < 2, target.isJP3D {
            return "Use JPEG 2000 Lossless or HTJ2K Lossless for a single-frame image."
        }
        if d.bitsStored > 12 {
            return "For more than 12 bits use JPEG Lossless, JPEG-LS, JPEG 2000, HTJ2K or JPEG XL."
        }
        return nil
    }

    // MARK: Rule table (wording only; the encoder's canEncode is the authority)

    struct PixelRule {
        let requirement: String
        let bitsAllocated: Set<Int>
        let bitsStored: ClosedRange<Int>?
        let samples: Set<Int>
        let signed: SignedRule
        let minFrames: Int
        let maxRLESegments: Int?

        enum SignedRule { case any, unsignedOnly, signedNeeds16Bit }

        static func forTarget(_ t: TransferSyntax) -> PixelRule? {
            switch t.uid {
            case TransferSyntax.jpegBaseline.uid:
                return PixelRule(
                    requirement: "8-bit unsigned data with 1 or 3 samples (16-bit data is windowed down to 8-bit)",
                    bitsAllocated: [8, 16], bitsStored: 1...8, samples: [1, 3],
                    signed: .unsignedOnly, minFrames: 1, maxRLESegments: nil)
            case TransferSyntax.jpegExtended.uid:
                return PixelRule(
                    requirement: "unsigned data of up to 12 bits with 1 or 3 samples",
                    bitsAllocated: [8, 16], bitsStored: 1...12, samples: [1, 3],
                    signed: .unsignedOnly, minFrames: 1, maxRLESegments: nil)
            case TransferSyntax.jpegLossless.uid, TransferSyntax.jpegLosslessSV1.uid:
                return PixelRule(
                    requirement: "2- to 16-bit data with 1 or 3 samples",
                    bitsAllocated: [8, 16], bitsStored: 2...16, samples: [1, 3],
                    signed: .any, minFrames: 1, maxRLESegments: nil)
            case TransferSyntax.jpegXLLossless.uid, TransferSyntax.jpegXL.uid:
                return PixelRule(
                    requirement: "8- or 16-bit data with 1 or 3 samples, and signed data only at 16-bit",
                    bitsAllocated: [8, 16], bitsStored: nil, samples: [1, 3],
                    signed: .signedNeeds16Bit, minFrames: 1, maxRLESegments: nil)
            case TransferSyntax.rleLossless.uid:
                return PixelRule(
                    requirement: "8- or 16-bit data with at most 15 byte segments per pixel",
                    bitsAllocated: [8, 16], bitsStored: nil, samples: [],
                    signed: .any, minFrames: 1, maxRLESegments: 15)
            case _ where t.isJP3D:
                return PixelRule(
                    requirement: "8- or 16-bit single-sample volumes with at least 2 frames",
                    bitsAllocated: [8, 16], bitsStored: nil, samples: [1],
                    signed: .any, minFrames: 2, maxRLESegments: nil)
            case _ where t.isJPEG2000 || t.isHTJ2K || t.isJPEGLS:
                return PixelRule(
                    requirement: "8- or 16-bit data with 1 or 3 samples",
                    bitsAllocated: [8, 16], bitsStored: nil, samples: [1, 3],
                    signed: .any, minFrames: 1, maxRLESegments: nil)
            default:
                return nil
            }
        }

        func violations(of d: PixelDataDescriptor, targetName name: String) -> [String] {
            var out: [String] = []
            if !bitsAllocated.contains(d.bitsAllocated) {
                out.append("\(name) needs Bits Allocated 8 or 16, but the source has \(d.bitsAllocated).")
            } else if let range = bitsStored, !range.contains(d.bitsStored) {
                out.append("\(name) supports at most \(range.upperBound)-bit data (Bits Stored \(range.lowerBound) to \(range.upperBound)), but the source stores \(d.bitsStored) bits.")
            }
            if !samples.isEmpty, !samples.contains(d.samplesPerPixel) {
                let allowed = samples.sorted().map(String.init).joined(separator: " or ")
                out.append("\(name) needs \(allowed) samples per pixel, but the source has \(d.samplesPerPixel).")
            }
            if let maxSegments = maxRLESegments, d.bytesPerSample * d.samplesPerPixel > maxSegments {
                out.append("\(name) allows at most \(maxSegments) byte segments, but the source needs \(d.bytesPerSample * d.samplesPerPixel).")
            }
            switch signed {
            case .unsignedOnly where d.isSigned:
                out.append("\(name) cannot encode signed pixel data (Pixel Representation 1).")
            case .signedNeeds16Bit where d.isSigned && d.bitsAllocated != 16:
                out.append("\(name) has no signed 8-bit sample type; signed data must be 16-bit.")
            default:
                break
            }
            if d.numberOfFrames < minFrames {
                out.append("\(name) needs a multi-frame volume of at least \(minFrames) frames, but the source has \(d.numberOfFrames).")
            }
            if d.samplesPerPixel == 3, d.photometricInterpretation.isYBR, d.bitsAllocated > 8,
               bitsStored?.upperBound == 12 {
                out.append("\(name) accepts YBR colour data only at 8-bit.")
            }
            return out
        }
    }
}
