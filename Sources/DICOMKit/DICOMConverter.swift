// NEMA-verified: 2026a, checked 2026-10-01 — transfer syntax capabilities via DICOMCore; UID literals, names and PS3.5 citations diffed by Scripts/diff_kit.py against PS3.6 2026a Table A-1 and the PS3.5 text; --strip-private recurses into Sequence Items (PS3.5 2026a 7.8.1, D191); lossy output gets a new SOP Instance UID (PS3.3 2026a C.7.6.1.1.5, D192)
// NEMA-verified: 2026a, checked 2026-10-06 — additionalTableA1Keywords (folded in from dicom-convert TransferSyntaxKeywords, D268): the 7 keyword → UID rows are the PS3.6 2026a Table A-1 keyword column of 1.2.840.10008.1.2.1.99, .4.50, .4.51, .4.92, .4.93, .4.111, .4.202 (dumped by script), the catalog target UIDs whose keyword no cliToken spells; transferSyntaxOptionHelpWithKeywords is the CLI's composed help, unchanged
import Foundation
import DICOMCore

/// Shared DICOM transfer-syntax conversion API for the `dicom-convert` CLI and
/// DICOMStudio's CLI Workshop.
///
/// This is the single source of truth for:
///   - **the list** of transfer syntaxes `dicom-convert` can target (one ordered
///     catalog feeds the CLI `--help`/error text, the CLI Workshop picker, and the
///     representative parameter catalog — never re-hardcode it),
///   - **input** parsing of a user-supplied transfer-syntax token (UID, the CLI's
///     CamelCase names, the kebab aliases, and the historical short aliases),
///   - **the process + output rendering**: reading the source file, optionally
///     stripping private tags, transcoding the pixel data via the DICOMCore
///     ``DICOMCore/TransferSyntaxConverter``, and serialising a complete Part-10
///     byte stream (preamble + DICM + File Meta Information + transcoded data set).
///
/// Both the CLI and the app call ``convertToDICOM(dicomFile:to:stripPrivate:)`` so
/// their byte output is identical (CLI ↔ app parity); the thin shells own only their
/// environment-specific file access and console formatting.
///
/// The target syntaxes are the DICOMCore ``DICOMCore/TransferSyntax`` constants the
/// transcoder can actually encode to — uncompressed, JPEG, JPEG 2000 (incl. Part 2
/// and HTJ2K), JPEG-LS, lossless JPEG XL, and RLE. Video, JPIP-referenced, and the
/// experimental JP3D syntaxes are intentionally excluded as convert targets.
public enum DICOMConverter {

    // MARK: - Target Catalog

    /// One convert target: a DICOMCore transfer syntax **plus its encode intent** and the
    /// tokens that select it.
    ///
    /// Per the DICOM standard the general JPEG 2000 / HTJ2K / JPEG XL UIDs (.91/.93/.203/.112)
    /// may carry either a reversible or an irreversible codestream (PS3.5 §A.4.4, §A.4.12), so
    /// each general family has a symmetric `…-lossy` / `…-lossless` pair on the general UID plus a
    /// `…-lossless-only` entry on the distinct reversible-only UID. The ``intent`` is what lets
    /// `jpeg2000-lossless` encode reversibly *into* `.91` rather than into `.90` — the same split
    /// `CompressionManager.codecMap` / `dicom-compress` use, so the two tools now agree.
    public struct Target: Sendable {
        /// The DICOMCore transfer syntax this target encodes to.
        public let syntax: TransferSyntax
        /// The encode intent (`.lossless`/`.lossy` for `both`-capable UIDs, `.notApplicable`
        /// for single-capability UIDs). Drives reversible-vs-irreversible encoding and the
        /// Lossy Image Compression provenance attributes.
        public let intent: EncodingIntent
        /// CamelCase token emitted in the CLI `--transfer-syntax` help listing
        /// (e.g. `ExplicitVRLittleEndian`, `JPEG2000Reversible`). Accepted on input.
        public let cliToken: String
        /// kebab-case alias shown in the app pickers (CLI Workshop + representative parameter
        /// catalog) so every transfer-syntax dropdown reads the same short style as
        /// dicom-compress, and accepted on input (e.g. `explicit-vr-le`, `jpeg2000-lossless`).
        public let aliasToken: String
        /// Additional historical aliases accepted on input (already lowercased).
        public let extraAliases: [String]

        /// The full encoding (UID + intent) this target selects.
        public var encoding: SelectableEncoding {
            SelectableEncoding(transferSyntax: syntax, intent: intent)
        }

        /// A short, human-readable, intent-aware name — e.g. "JPEG 2000 Lossy",
        /// "JPEG 2000 Lossless", "JPEG 2000 Lossless Only".
        public var displayName: String { encoding.displayName }

        /// Whether encoding to this target is reversible: `both`-capable UIDs honour the
        /// selected intent; single-capability UIDs are fixed by the UID.
        public var encodesLossless: Bool {
            switch syntax.losslessCapability {
            case .both:          return intent == .lossless
            case .losslessOnly:  return true
            case .lossyOnly:     return false
            }
        }

        init(_ syntax: TransferSyntax, intent: EncodingIntent = .notApplicable,
             cli: String, alias: String, extra: [String] = []) {
            self.syntax = syntax
            self.intent = intent
            self.cliToken = cli
            self.aliasToken = alias
            self.extraAliases = extra
        }
    }

    /// The canonical, UI-ordered list of transfer syntaxes `dicom-convert` can target.
    ///
    /// Ordering mirrors ``DICOMCore/TransferSyntax/allKnown`` (uncompressed, JPEG,
    /// JPEG 2000 / HTJ2K, JPEG-LS, JPEG XL, RLE).
    ///
    /// Each `both`-capable general family (JPEG 2000 .91, Part 2 .93, HTJ2K .203, JPEG XL .112)
    /// exposes three intent-tagged targets — `…-lossy` (irreversible into the general UID),
    /// `…-lossless` (reversible into the *same* general UID), and `…-lossless-only` (the distinct
    /// reversible-only UID .90/.92/.201/.110). This matches `CompressionManager.codecMap` /
    /// `dicom-compress` exactly, so the two tools no longer diverge: `jpeg2000-lossless` emits a
    /// reversible codestream in the general .91 UID in both. The `…-lossy` targets also populate
    /// the DICOM Lossy Image Compression provenance attributes (0028,2110/2112/2114). A bare
    /// family alias (`jpeg2000`, `j2k`, `htj2k`, `jxl`) resolves to the **lossy** target, matching
    /// the "bare = lossy" convention shared with `dicom-compress`.
    ///
    /// `JPEGXLRecompression` (…4.111) is a distinct target that losslessly rewraps an
    /// existing JPEG bitstream rather than encoding pixels; it therefore applies only to
    /// an 8-bit JPEG Baseline (…4.50) or JPEG Extended (…4.51) *source*, including
    /// progressive JPEG found inside those fragments (``DICOMCore/TransferSyntaxConverter``
    /// rejects the transcode with a clear error for any other source, and for 12-bit JPEG).
    public static let targets: [Target] = [
        // Uncompressed
        Target(.explicitVRLittleEndian,          cli: "ExplicitVRLittleEndian",  alias: "explicit-vr-le", extra: ["explicit", "evle"]),
        Target(.implicitVRLittleEndian,          cli: "ImplicitVRLittleEndian",  alias: "implicit-vr-le", extra: ["implicit", "ivle"]),
        Target(.explicitVRBigEndian,             cli: "ExplicitVRBigEndian",     alias: "explicit-vr-be", extra: ["evbe", "big-endian"]),
        Target(.deflatedExplicitVRLittleEndian,  cli: "DEFLATE",                 alias: "deflate",        extra: ["deflated", "deflated-explicit-vr-le"]),
        // JPEG
        Target(.jpegBaseline,                    cli: "JPEGBaseline",            alias: "jpeg-baseline",  extra: ["jpeg"]),
        Target(.jpegExtended,                    cli: "JPEGExtended",            alias: "jpeg-extended"),
        Target(.jpegLossless,                    cli: "JPEGLossless",            alias: "jpeg-lossless"),
        Target(.jpegLosslessSV1,                 cli: "JPEGLosslessSV1",         alias: "jpeg-lossless-sv1"),
        // JPEG 2000 — general .91 (lossy + lossless) + lossless-only .90.
        Target(.jpeg2000, intent: .lossy,        cli: "JPEG2000Lossy",           alias: "jpeg2000-lossy",           extra: ["jpeg2000", "j2k", "j2k-lossy"]),
        // `JPEG2000Lossless` is the PS3.6 2026a Table A-1 keyword of .90, so it is an alias of
        // the .90 target; the reversible encode into .91 is `JPEG2000Reversible`
        // (P-CONVERT-TS-KEYWORDS; the same for HTJ2K .201/.203 and JPEG XL .110/.112 below).
        Target(.jpeg2000, intent: .lossless,     cli: "JPEG2000Reversible",      alias: "jpeg2000-lossless",        extra: ["j2k-lossless"]),
        Target(.jpeg2000Lossless,                cli: "JPEG2000LosslessOnly",    alias: "jpeg2000-lossless-only",   extra: ["j2k-lossless-only", "jpeg2000lossless"]),
        // JPEG 2000 Part 2 — general .93 (lossy + lossless) + lossless-only .92.
        Target(.jpeg2000Part2, intent: .lossy,   cli: "JPEG2000Part2Lossy",      alias: "jpeg2000-part2-lossy",     extra: ["jpeg2000-part2", "j2k-part2", "j2k-part2-lossy"]),
        Target(.jpeg2000Part2, intent: .lossless, cli: "JPEG2000Part2Lossless",  alias: "jpeg2000-part2-lossless",  extra: ["j2k-part2-lossless"]),
        Target(.jpeg2000Part2Lossless,           cli: "JPEG2000Part2LosslessOnly", alias: "jpeg2000-part2-lossless-only", extra: ["j2k-part2-lossless-only"]),
        // HTJ2K — general .203 (lossy + lossless) + lossless-only .201 + RPCL lossless-only .202.
        Target(.htj2kLossy, intent: .lossy,      cli: "HTJ2KLossy",              alias: "htj2k-lossy",              extra: ["htj2k"]),
        Target(.htj2kLossy, intent: .lossless,   cli: "HTJ2KReversible",         alias: "htj2k-lossless"),
        Target(.htj2kLossless,                   cli: "HTJ2KLosslessOnly",       alias: "htj2k-lossless-only",     extra: ["htj2klossless"]),
        Target(.htj2kRPCLLossless,               cli: "HTJ2KRPCLLosslessOnly",   alias: "htj2k-rpcl-lossless-only", extra: ["htj2k-rpcl", "htj2k-lossless-rpcl"]),
        // JPEG-LS
        Target(.jpegLSLossless,                  cli: "JPEGLSLossless",          alias: "jpeg-ls-lossless",        extra: ["jpegls", "jpegls-lossless", "jls-lossless"]),
        Target(.jpegLSNearLossless,              cli: "JPEGLSNearLossless",      alias: "jpeg-ls-near-lossless",   extra: ["jpegls-near"]),
        // JPEG XL — general .112 (lossy VarDCT + lossless Modular) + lossless-only .110 + JPEG recompression .111.
        Target(.jpegXL, intent: .lossy,          cli: "JPEGXLLossy",             alias: "jpeg-xl-lossy",           extra: ["jpeg-xl", "jxl", "jpegxl", "jxl-lossy"]),
        Target(.jpegXL, intent: .lossless,       cli: "JPEGXLReversible",        alias: "jpeg-xl-lossless",        extra: ["jxl-lossless"]),
        Target(.jpegXLLossless,                  cli: "JPEGXLLosslessOnly",      alias: "jpeg-xl-lossless-only",   extra: ["jxl-lossless-only", "jpegxllossless"]),
        Target(.jpegXLRecompression,             cli: "JPEGXLRecompression",     alias: "jpeg-xl-recompression",   extra: ["jxl-recompression", "jpegxl-recompression", "jpeg-xl-jpeg-recompression"]),
        // RLE
        Target(.rleLossless,                     cli: "RLELossless",             alias: "rle-lossless",            extra: ["rle"]),
    ]

    /// The CamelCase tokens, in catalog order — drives the CLI Workshop picker.
    public static var cliTokens: [String] { targets.map(\.cliToken) }

    /// The kebab-case aliases, in catalog order — drives the representative catalog picker.
    public static var aliasTokens: [String] { targets.map(\.aliasToken) }

    /// The target transfer syntaxes, in catalog order.
    public static var targetSyntaxes: [TransferSyntax] { targets.map(\.syntax) }

    // MARK: - Parsing

    /// Resolves a user-supplied transfer-syntax token to a convert ``Target`` (UID **and**
    /// encode intent).
    ///
    /// Accepts the canonical UID, the CLI CamelCase name, the kebab alias, and the
    /// historical short aliases (case-insensitive). Returns `nil` when the token is
    /// unrecognised *or* names a transfer syntax that is not a valid convert target
    /// (e.g. a video or JPIP syntax).
    ///
    /// A bare general-family UID (e.g. `1.2.840.10008.1.2.4.91`) is ambiguous between the
    /// lossy and lossless targets that share it; it resolves to the **lossy** target because
    /// the `…-lossy` entry is listed first, matching the historical bare-alias behaviour.
    public static func resolveTarget(_ nameOrUID: String) -> Target? {
        let trimmed = nameOrUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Exact UID — only if it is one of our targets (first match = lossy for a shared UID).
        if let t = targets.first(where: { $0.syntax.uid == trimmed }) {
            return t
        }

        let lower = trimmed.lowercased()
        for t in targets {
            if lower == t.cliToken.lowercased()
                || lower == t.aliasToken
                || lower == t.syntax.uid
                || t.extraAliases.contains(lower) {
                return t
            }
        }
        // A PS3.6 Table A-1 keyword that is not a catalog token selects its UID (first match =
        // lossy for a shared UID, as for a bare UID).
        if let uid = additionalTableA1Keywords.first(where: { $0.key.lowercased() == lower })?.value {
            return targets.first { $0.syntax.uid == uid }
        }
        return nil
    }

    /// The PS3.6 2026a Table A-1 keywords of catalog target UIDs whose keyword is not a
    /// ``Target/cliToken`` (nor one of the three reassigned keywords of
    /// ``DICOMCore/TransferSyntax/reassignedTableA1Keywords``), keyword → Transfer Syntax UID.
    /// ``resolveTarget(_:)`` accepts them case-insensitively, so every Table A-1 keyword of a
    /// target UID selects its Table A-1 UID (D268; was `dicom-convert`'s TransferSyntaxKeywords).
    public static let additionalTableA1Keywords: [String: String] = [
        "DeflatedExplicitVRLittleEndian": "1.2.840.10008.1.2.1.99",
        "JPEGBaseline8Bit": "1.2.840.10008.1.2.4.50",
        "JPEGExtended12Bit": "1.2.840.10008.1.2.4.51",
        "JPEG2000MCLossless": "1.2.840.10008.1.2.4.92",
        "JPEG2000MC": "1.2.840.10008.1.2.4.93",
        "JPEGXLJPEGRecompression": "1.2.840.10008.1.2.4.111",
        "HTJ2KLosslessRPCL": "1.2.840.10008.1.2.4.202",
    ]

    /// Resolves a user-supplied token to a ``SelectableEncoding`` (UID + intent). This is the
    /// intent-aware entry point the CLI and app use so a `…-lossless` name encodes reversibly
    /// into the general UID rather than silently emitting lossy pixels.
    public static func resolveTargetEncoding(_ nameOrUID: String) -> SelectableEncoding? {
        resolveTarget(nameOrUID)?.encoding
    }

    /// Resolves a user-supplied token to just its transfer syntax (UID), discarding intent.
    ///
    /// Retained for callers that only need the UID; the encode path should prefer
    /// ``resolveTargetEncoding(_:)`` so the lossy/lossless intent for the general UIDs is
    /// preserved.
    public static func parseTarget(_ nameOrUID: String) -> TransferSyntax? {
        resolveTarget(nameOrUID)?.syntax
    }

    // MARK: - Help / Error Text

    /// One-line `--help` abstract for the `--transfer-syntax` option, listing the
    /// accepted CamelCase target names (kept in sync with ``targets``).
    public static var transferSyntaxOptionHelp: String {
        "Target transfer syntax: " + cliTokens.joined(separator: ", ")
    }

    /// The `dicom-convert --transfer-syntax` help: ``transferSyntaxOptionHelp`` plus what else
    /// is accepted — a Transfer Syntax UID and the PS3.6 Table A-1 keywords
    /// (``additionalTableA1Keywords`` and the reassigned ones), with the 2026-10-01 meaning
    /// change of `JPEG2000Lossless` / `HTJ2KLossless` / `JPEGXLLossless` (P-CONVERT-TS-KEYWORDS).
    /// The CLI and the Workshop print this text (D268).
    public static var transferSyntaxOptionHelpWithKeywords: String {
        transferSyntaxOptionHelp
            + ". Also a Transfer Syntax UID or a PS3.6 Table A-1 keyword ("
            + (additionalTableA1Keywords.keys + TransferSyntax.reassignedTableA1Keywords.map(\.keyword)).sorted()
                .joined(separator: ", ")
            + "); every Table A-1 keyword selects its Table A-1 UID. Changed: JPEG2000Lossless, "
            + "HTJ2KLossless and JPEGXLLossless now select .90 / .201 / .110; the reversible encode "
            + "into .91 / .203 / .112 is JPEG2000Reversible, HTJ2KReversible, JPEGXLReversible."
    }

    /// A multi-line, grouped listing of the supported convert targets for error output.
    public static var targetListHelp: String {
        func names(_ predicate: (TransferSyntax) -> Bool) -> String {
            targets.filter { predicate($0.syntax) }.map(\.cliToken).joined(separator: ", ")
        }
        let uncompressed = targets.filter {
            !$0.syntax.isEncapsulated && !$0.syntax.isDeflated
        }.map(\.cliToken) + ["DEFLATE"]
        return """
            Available transfer syntaxes:
              Uncompressed: \(uncompressed.joined(separator: ", "))
              JPEG:         \(names { $0.isJPEG })
              JPEG 2000:    \(names { $0.isJPEG2000 })
              JPEG-LS:      \(names { $0.isJPEGLS })
              JPEG XL:      \(names { $0.isJPEGXL })
              RLE:          \(names { $0.isRLE })
            """
    }

    /// The full error message shown when an unrecognised transfer syntax is requested.
    public static func unknownTargetMessage(_ name: String) -> String {
        "Unknown transfer syntax: \(name).\n" + targetListHelp
    }

    // MARK: - Conversion (input → process → output)

    /// The outcome of a transfer-syntax conversion: the serialised Part-10 bytes plus
    /// metadata for the caller's console/log output.
    public struct Outcome: Sendable {
        /// The complete output DICOM file (preamble + DICM + FMI + transcoded data set).
        public let data: Data
        /// The transfer syntax the source file was encoded in.
        public let sourceSyntax: TransferSyntax
        /// The transfer syntax the output was encoded to.
        public let targetSyntax: TransferSyntax
        /// Whether the pixel data was actually re-encoded (false for a same-syntax no-op).
        public let wasTranscoded: Bool
        /// Whether the conversion was lossless end to end.
        public let isLossless: Bool
        /// The number of private tags removed (0 when `stripPrivate` was false).
        public let strippedPrivateTagCount: Int
    }

    /// Optionally strips private tags from an already-parsed DICOM file, transcodes it
    /// to `target`, and renders a complete Part-10 byte stream.
    ///
    /// UID-only overload — the encode intent is derived from the target's capability
    /// (a `both`-capable general UID passed directly defaults to **lossy**, matching the
    /// historical bare-alias behaviour). Prefer ``convertToDICOM(dicomFile:to:stripPrivate:)-…``
    /// taking a ``SelectableEncoding`` when the caller knows the lossy/lossless intent (the CLI
    /// and app resolve it via ``resolveTargetEncoding(_:)``).
    ///
    /// - Parameters:
    ///   - dicomFile: The already-parsed source DICOM file.
    ///   - target: The transfer syntax to encode to (typically from ``parseTarget(_:)``).
    ///   - stripPrivate: Remove all private (odd-group) tags before transcoding.
    public static func convertToDICOM(
        dicomFile: DICOMFile,
        to target: TransferSyntax,
        stripPrivate: Bool
    ) throws -> Outcome {
        let intent: EncodingIntent = target.losslessCapability == .both ? .lossy : .notApplicable
        return try convertToDICOM(
            dicomFile: dicomFile,
            to: SelectableEncoding(transferSyntax: target, intent: intent),
            stripPrivate: stripPrivate
        )
    }

    /// Optionally strips private tags from an already-parsed DICOM file, transcodes it to
    /// `encoding` (UID + intent), and renders a complete Part-10 byte stream.
    ///
    /// This is the shared process + output pipeline used by both the CLI and the app so
    /// their output is byte-identical. The caller owns the environment-specific work:
    /// reading the input bytes from disk and parsing them with the shared
    /// ``DICOMKit/DICOMFile/read(from:force:)`` API (the CLI directly, the app via a
    /// security-scoped URL), then writing ``Outcome/data`` back out and formatting
    /// console messages.
    ///
    /// The intent drives reversible-vs-irreversible encoding for the `both`-capable general
    /// UIDs (.91/.93/.203/.112): a `.lossless` intent encodes a reversible codestream *into*
    /// the general UID (identical pixels, general UID emitted), while a `.lossy` intent encodes
    /// an irreversible codestream **and** records the DICOM Lossy Image Compression provenance
    /// attributes (0028,2110/2112/2114) plus Image Type → DERIVED, exactly as `dicom-compress`
    /// does (via the shared ``CompressionManager/applyLossyImageCompressionAttributes(to:targetSyntax:uncompressedByteCount:compressedByteCount:)``).
    ///
    /// - Parameters:
    ///   - dicomFile: The already-parsed source DICOM file.
    ///   - encoding: The target UID + encode intent (typically from ``resolveTargetEncoding(_:)``).
    ///   - stripPrivate: Remove all private (odd-group) tags before transcoding.
    /// - Returns: The serialised output plus conversion metadata.
    /// - Throws: A ``ConversionFailure`` explaining why the conversion cannot run or failed.
    public static func convertToDICOM(
        dicomFile: DICOMFile,
        to encoding: SelectableEncoding,
        stripPrivate: Bool
    ) throws -> Outcome {
        // Reject a mismatched source transfer syntax or pixel format up front with a
        // readable reason, then wrap any later codec/parser error with the same
        // source → target context. Both the CLI and the app print the resulting
        // ``ConversionFailure`` through ``ConvertConsole/failureReport(for:)``.
        try checkConversion(dicomFile: dicomFile, to: encoding)
        do {
            return try performConversion(dicomFile: dicomFile, to: encoding, stripPrivate: stripPrivate)
        } catch {
            let sourceUID = dicomFile.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid
            throw ConversionFailure.translate(
                error,
                source: ConversionFailure.label(forUID: sourceUID),
                target: ConversionFailure.label(for: encoding.transferSyntax))
        }
    }

    /// The conversion itself, without the pre-checks and error wrapping.
    private static func performConversion(
        dicomFile: DICOMFile,
        to encoding: SelectableEncoding,
        stripPrivate: Bool
    ) throws -> Outcome {
        let target = encoding.transferSyntax

        // Whether THIS encode is reversible: the general (`both`-capable) UIDs honour the
        // selected intent; single-capability UIDs are fixed by the UID. Mirrors
        // `CompressionManager.encodePixelDataInPlace` so convert and compress agree.
        let encodeLossless: Bool
        switch target.losslessCapability {
        case .both:          encodeLossless = (encoding.intent == .lossless)
        case .losslessOnly:  encodeLossless = true
        case .lossyOnly:     encodeLossless = false
        }

        var dataSet = dicomFile.dataSet

        // Optionally strip private tags.
        var strippedCount = 0
        if stripPrivate {
            // Every Sequence Item is a Data Set with its own Private Data Elements and Private
            // Creators (PS3.5 2026a 7.8.1), so the strip recurses into nested Items (D191).
            var filtered = DataSet()
            for tag in dataSet.tags {
                guard let element = dataSet[tag] else { continue }
                if tag.isPrivate { strippedCount += 1; continue }
                filtered[tag] = strippingPrivate(element, count: &strippedCount)
            }
            dataSet = filtered
        }

        // The native (uncompressed) pixel byte count for the lossy compression ratio, captured
        // from the SOURCE before transcoding (it is the numerator "uncompressed size" regardless
        // of any downstream bit-depth reduction). Falls back to the raw element length.
        let sourceUncompressedPixelBytes: Int = {
            if let d = try? CompressionManager.buildPixelDataDescriptor(from: dataSet) { return d.totalBytes }
            return dataSet[.pixelData]?.valueData.count ?? 0
        }()

        // Determine the source transfer syntax from the file.
        let sourceSyntaxUID = dicomFile.transferSyntaxUID ?? TransferSyntax.explicitVRLittleEndian.uid
        let sourceSyntax = TransferSyntax.from(uid: sourceSyntaxUID) ?? .explicitVRLittleEndian

        // The in-memory data set is always fully decoded (``DICOMFile/read(from:force:)``
        // inflates a Deflated source), so when the *source* is itself deflated the byte
        // stream the transcoder/deflater consumes is its un-deflated Explicit VR LE form.
        let serializationSyntax: TransferSyntax = sourceSyntax.isDeflated ? .explicitVRLittleEndian : sourceSyntax

        // File Meta Information for the output (shared by both payload paths; never deflated).
        let sopClassUID = dataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.7"
        let sopInstanceUID = dataSet.string(for: .sopInstanceUID) ?? UIDGenerator.generateSOPInstanceUID().value
        let outputFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: target.uid
        )
        let fmiWriter = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)

        // --- Process: build the data-set payload for the target syntax ---
        let dataSetPayload: Data
        let wasTranscoded: Bool
        let isLossless: Bool

        if target.isDeflated {
            // Deflated Explicit VR Little Endian (PS3.5 A.5): serialize the Data Set as
            // Explicit VR LE then DEFLATE-compress the whole stream (the File Meta
            // Information above stays uncompressed). Mirrors ``CompressionManager`` so
            // convert and compress produce equivalent deflate output. Always lossless.
            // The DICOMCore ``TransferSyntaxConverter`` only handles uncompressed and
            // encapsulated/pixel-level codecs — not data-set-level deflate — so this
            // is handled here rather than delegated to ``transcode``.
            //
            // An ENCAPSULATED source must have its pixel data decoded to native first.
            // Deflate is a data-set-level codec over a *native* Explicit VR LE stream;
            // it has no encapsulated form. Serializing the encapsulated element straight
            // into the deflate stream produced a file labelled …1.2.1.99 that still held
            // an undefined-length (7FE0,0010) with Item-tagged fragments — the codestream
            // survived, but no conformant reader (DICOMKit's own included) could decode
            // pixel data from it, and the tool reported success.
            let plain: Data
            if serializationSyntax.isEncapsulated {
                let decoder = TransferSyntaxConverter(
                    configuration: TranscodingConfiguration(
                        preferredSyntaxes: [.explicitVRLittleEndian],
                        allowLossyCompression: false,
                        preservePixelDataFidelity: true
                    ),
                    compressionConfiguration: .lossless
                )
                let sourceWriter = DICOMWriter(
                    byteOrder: serializationSyntax.byteOrder,
                    explicitVR: serializationSyntax.isExplicitVR
                )
                plain = try decoder.transcode(
                    dataSetData: dataSet.write(using: sourceWriter),
                    from: serializationSyntax,
                    to: .explicitVRLittleEndian
                ).data
            } else {
                let evleWriter = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
                plain = dataSet.write(using: evleWriter)
            }
            guard let deflated = plain.deflateCompressed() else {
                throw TranscodingError.encodingFailed(
                    "Failed to deflate the Data Set for \(target.uid). "
                    + "Deflate compression is unavailable on this platform."
                )
            }
            dataSetPayload = deflated
            wasTranscoded = sourceSyntax.uid != target.uid
            isLossless = true
        } else {
            // Transcode pixel data via the DICOMCore converter. `preferLossless` in the
            // compression config drives reversible vs irreversible for the `both`-capable UIDs
            // (the encoder honours it); `.lossless` also carries the strict lossless preset.
            let compressionConfig: DICOMCore.CompressionConfiguration = encodeLossless
                ? .lossless
                : .default
            // A `both`-capable UID reports `isLossless == false` at the UID level, so the
            // transcoder's lossy gate would reject a *reversible* encode INTO it (.91/.93/.203/.112
            // lossless). Permit "lossy" whenever this encode is genuinely lossy OR the target UID
            // is `both`-capable; the actual fidelity is governed by `compressionConfig.preferLossless`.
            let allowLossy = !encodeLossless || target.losslessCapability == .both
            let converter = TransferSyntaxConverter(
                configuration: TranscodingConfiguration(
                    preferredSyntaxes: [target],
                    allowLossyCompression: allowLossy,
                    preservePixelDataFidelity: encodeLossless
                ),
                compressionConfiguration: compressionConfig
            )

            // Serialize the (possibly filtered) data set to bytes in the source syntax.
            let sourceWriter = DICOMWriter(
                byteOrder: serializationSyntax.byteOrder,
                explicitVR: serializationSyntax.isExplicitVR
            )
            let dataSetBytes = dataSet.write(using: sourceWriter)

            let result = try converter.transcode(
                dataSetData: dataSetBytes,
                from: serializationSyntax,
                to: target
            )
            dataSetPayload = result.data
            wasTranscoded = result.wasTranscoded
            // The transcoder reports `isLossless == false` for a reversible encode into a
            // `both`-capable UID (it keys off the UID's lossy-capable flag), so OR in the
            // intent-derived truth; recompression/deflate paths correctly set `result.isLossless`.
            isLossless = encodeLossless || result.isLossless
        }

        // --- Output: render the complete Part-10 file ---
        var outputData = Data()
        outputData.append(Data(repeating: 0, count: 128))  // Preamble
        outputData.append(contentsOf: "DICM".utf8)          // DICM prefix
        outputData.append(outputFile.fileMetaInformation.write(using: fmiWriter))
        outputData.append(dataSetPayload)

        // Record DICOM Lossy Image Compression provenance for an irreversible encapsulated
        // encode (0028,2110/2112/2114 + Image Type → DERIVED), reusing the exact writer
        // `dicom-compress` uses. No-op for reversible-only targets (method Defined Term is nil).
        if !encodeLossless, wasTranscoded, target.isEncapsulated, target.lossyImageCompressionMethod != nil {
            outputData = try applyLossyProvenance(
                to: outputData, target: target, uncompressedPixelByteCount: sourceUncompressedPixelBytes)
        }

        return Outcome(
            data: outputData,
            sourceSyntax: sourceSyntax,
            targetSyntax: target,
            wasTranscoded: wasTranscoded,
            isLossless: isLossless,
            strippedPrivateTagCount: strippedCount
        )
    }

    /// `element` with the Private Data Elements of its Sequence Items removed, at any depth;
    /// `count` is increased by the number removed.
    static func strippingPrivate(_ element: DataElement, count: inout Int) -> DataElement {
        guard let items = element.sequenceItems else { return element }
        let before = count
        let newItems: [SequenceItem] = items.map { item in
            var kept: [Tag: DataElement] = [:]
            for (tag, child) in item.elements {
                if tag.isPrivate { count += 1; continue }
                kept[tag] = strippingPrivate(child, count: &count)
            }
            return SequenceItem(elements: kept)
        }
        guard count != before else { return element }
        // DICOMWriter re-encodes a sequence from its Items and recomputes the length, so the
        // raw `valueData` of the source is not carried.
        return DataElement(tag: element.tag, vr: element.vr, length: 0, valueData: Data(),
                           sequenceItems: newItems, byteOrder: element.byteOrder)
    }

    /// Re-reads a freshly transcoded encapsulated file, stamps the DICOM Lossy Image Compression
    /// provenance attributes (0028,2110/2112/2114 + Image Type → DERIVED) via the shared
    /// ``CompressionManager`` writer, and re-serialises it. The compressed byte count is the sum
    /// of the encapsulated fragment sizes; the uncompressed byte count is the source's native
    /// pixel size. This runs a metadata-only parse + re-write (the compressed fragments are copied
    /// verbatim), so no pixel re-encode occurs.
    private static func applyLossyProvenance(
        to fileData: Data,
        target: TransferSyntax,
        uncompressedPixelByteCount: Int
    ) throws -> Data {
        let file = try DICOMFile.read(from: fileData)
        var dataSet = file.dataSet
        let compressedByteCount = dataSet[.pixelData]?.encapsulatedFragments?
            .reduce(0) { $0 + $1.count } ?? 0
        // Without both byte counts the ratio is meaningless — leave the file as transcoded.
        guard compressedByteCount > 0, uncompressedPixelByteCount > 0 else { return fileData }
        CompressionManager.applyLossyImageCompressionAttributes(
            to: &dataSet,
            targetSyntax: target,
            uncompressedByteCount: uncompressedPixelByteCount,
            compressedByteCount: compressedByteCount
        )
        return try TransferSyntaxHelper().convert(dataSet: dataSet, to: target, preservePixelData: true)
    }
}
