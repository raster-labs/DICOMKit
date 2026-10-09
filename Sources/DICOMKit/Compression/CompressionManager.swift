// NEMA-verified: 2026a, checked 2026-10-01 — XYB relabelled RGB after JPEG XL decode per PS3.3 2026a C.7.6.3.1.2 (D12); encapsulation per PS3.5 A.4; lossy output per PS3.3 2026a C.7.6.1.1.5 (0028,2110/2112/2114, DERIVED, new SOP Instance UID, Derivation Description; D184); J2K/HTJ2K PI from SGcod MCT (YBR_RCT/YBR_ICT, RGB after decode) per PS3.5 2026a 8.2.4 / 8.2.14 (D185, D186); JPEG colour YBR_FULL_422 per Table 8.2.1-1 (D190); File Meta UI padded per PS3.5 6.2 (D188)
import Foundation
import DICOMCore

// Shared compression workflow engine for the `dicom-compress` CLI and
// DICOMStudio. Builds on the already-shared CodecRegistry / CompressionQuality /
// TransferSyntax (DICOMCore). Adapters call the public entry points (info /
// compress / decompress, file- and in-memory variants) and format the result;
// the codec dispatch + Part-10 serialization helpers stay internal.

// MARK: - Compression Info

@available(macOS 10.15, *)
public struct CompressionInfo {
    public let transferSyntaxUID: String
    public let transferSyntaxName: String
    public let isCompressed: Bool
    /// Whether the pixels are *effectively* lossless. For single-capability UIDs this is
    /// the UID-level flag; for the `both`-capable general UIDs (.91/.93/.203/.112) it is
    /// derived from Lossy Image Compression (0028,2110) — so an image reversibly encoded
    /// into a general UID reports `true`. Reference: PS3.3 C.7.6.1.1.5.
    public let isLossless: Bool
    public let isJPEG: Bool
    public let isJPEG2000: Bool
    public let isJPEGLS: Bool
    public let isJPEGXL: Bool
    public let isRLE: Bool
    public let isDeflated: Bool
    public let pixelDataSize: Int?
    public let rows: UInt16?
    public let columns: UInt16?
    public let bitsAllocated: UInt16?
    public let bitsStored: UInt16?
    public let samplesPerPixel: UInt16?
    public let photometricInterpretation: String?
    public let numberOfFrames: String?
    /// Lossy Image Compression (0028,2110) as stored ("00" / "01"), `nil` when absent.
    /// PS3.3 C.7.6.1.1.5.
    public var lossyImageCompression: String? = nil
}

// MARK: - Compression Manager

@available(macOS 10.15, *)
public struct CompressionManager {

    public init() {}

    // MARK: - Codec Name Mapping

    /// Codec name → `SelectableEncoding` (UID + encode intent).
    ///
    /// Per the DICOM standard the general JPEG 2000 / HTJ2K / JPEG XL UIDs (.91/.93/.203/.112)
    /// may carry either a reversible or an irreversible codestream, so each general family has
    /// a symmetric `…-lossy` / `…-lossless` pair on the general UID plus a `…-lossless-only`
    /// entry on the reversible-only UID (PS3.5 §A.4.4, §A.4.12). The intent is what lets a
    /// bare `htj2k-lossless` encode reversibly *into* `.203` rather than into `.201`.
    static let codecMap: [(names: [String], encoding: SelectableEncoding)] = [
        (["jpeg", "jpeg-baseline"], SelectableEncoding(transferSyntax: .jpegBaseline, intent: .notApplicable)),
        (["jpeg-extended"], SelectableEncoding(transferSyntax: .jpegExtended, intent: .notApplicable)),
        (["jpeg-lossless"], SelectableEncoding(transferSyntax: .jpegLossless, intent: .notApplicable)),
        (["jpeg-lossless-sv1"], SelectableEncoding(transferSyntax: .jpegLosslessSV1, intent: .notApplicable)),
        // JPEG 2000 — general .91 (lossy/lossless) + lossless-only .90.
        (["jpeg2000", "j2k", "jpeg2000-lossy", "j2k-lossy"], SelectableEncoding(transferSyntax: .jpeg2000, intent: .lossy)),
        (["jpeg2000-lossless", "j2k-lossless"], SelectableEncoding(transferSyntax: .jpeg2000, intent: .lossless)),
        (["jpeg2000-lossless-only", "j2k-lossless-only"], SelectableEncoding(transferSyntax: .jpeg2000Lossless, intent: .notApplicable)),
        // JPEG 2000 Part 2 — general .93 (lossy/lossless) + lossless-only .92.
        (["j2k-part2", "jpeg2000-part2", "j2k-part2-lossy", "jpeg2000-part2-lossy"], SelectableEncoding(transferSyntax: .jpeg2000Part2, intent: .lossy)),
        (["j2k-part2-lossless", "jpeg2000-part2-lossless"], SelectableEncoding(transferSyntax: .jpeg2000Part2, intent: .lossless)),
        (["j2k-part2-lossless-only", "jpeg2000-part2-lossless-only"], SelectableEncoding(transferSyntax: .jpeg2000Part2Lossless, intent: .notApplicable)),
        // HTJ2K — general .203 (lossy/lossless) + lossless-only .201 + RPCL lossless-only .202.
        (["htj2k", "htj2k-lossy"], SelectableEncoding(transferSyntax: .htj2kLossy, intent: .lossy)),
        (["htj2k-lossless"], SelectableEncoding(transferSyntax: .htj2kLossy, intent: .lossless)),
        (["htj2k-lossless-only"], SelectableEncoding(transferSyntax: .htj2kLossless, intent: .notApplicable)),
        (["htj2k-rpcl-lossless-only", "htj2k-rpcl", "htj2k-lossless-rpcl"], SelectableEncoding(transferSyntax: .htj2kRPCLLossless, intent: .notApplicable)),
        (["jpeg-ls-lossless", "jpegls-lossless", "jls-lossless"], SelectableEncoding(transferSyntax: .jpegLSLossless, intent: .notApplicable)),
        (["jpeg-ls", "jpegls", "jls"], SelectableEncoding(transferSyntax: .jpegLSNearLossless, intent: .notApplicable)),
        // JPEG XL — general .112 (lossy VarDCT / lossless Modular) + lossless-only .110.
        // (JPEG Recompression …4.111 is produced only by dicom-convert, never by a --codec name.)
        (["jpeg-xl-lossless", "jxl-lossless"], SelectableEncoding(transferSyntax: .jpegXL, intent: .lossless)),
        (["jpeg-xl", "jxl", "jpeg-xl-lossy", "jxl-lossy"], SelectableEncoding(transferSyntax: .jpegXL, intent: .lossy)),
        (["jpeg-xl-lossless-only", "jxl-lossless-only"], SelectableEncoding(transferSyntax: .jpegXLLossless, intent: .notApplicable)),
        (["rle"], SelectableEncoding(transferSyntax: .rleLossless, intent: .notApplicable)),
        (["explicit-le"], SelectableEncoding(transferSyntax: .explicitVRLittleEndian, intent: .notApplicable)),
        (["implicit-le"], SelectableEncoding(transferSyntax: .implicitVRLittleEndian, intent: .notApplicable)),
        (["deflate"], SelectableEncoding(transferSyntax: .deflatedExplicitVRLittleEndian, intent: .notApplicable)),
    ]

    /// Resolves a codec name to its full `SelectableEncoding` (UID + intent). Use this on
    /// the compress path so the lossy/lossless intent for the general UIDs is preserved.
    public static func resolveEncoding(for codecName: String) -> SelectableEncoding? {
        let lower = codecName.lowercased()
        for entry in codecMap where entry.names.contains(lower) {
            return entry.encoding
        }
        return nil
    }

    public static func transferSyntax(for codecName: String) -> TransferSyntax? {
        resolveEncoding(for: codecName)?.transferSyntax
    }

    /// Returns whether compressing a source described by `sourceInfo` to `targetCodec`
    /// will *recompress* — i.e. the source is already compressed AND the engine must
    /// decode it to native pixels and then re-encode. Both the CLI and the Studio
    /// Workshop call this so the recompression detection lives in one place (never
    /// re-derived at the call site). Returns `false` for a nil `sourceInfo`
    /// (unreadable source).
    ///
    /// A DIFFERENT encapsulated target UID is always a recompression. A SAME-UID
    /// target is normally a byte passthrough (no decode/re-encode) — EXCEPT when the
    /// caller supplies an explicit `quality` for a *lossy* target: that is a genuine
    /// re-encode at a new quality (e.g. a JPEG 2000 .91 file re-compressed with
    /// `--quality`), performed as decode-to-native + re-encode, so it counts as a
    /// recompression and gets the two-phase treatment. Pass the same `quality` here
    /// that will be passed to `compressData`/`compressDataWithMetrics` so this stays
    /// in lock-step with the actual code path.
    public static func isRecompression(sourceInfo: CompressionInfo?, targetCodec: String,
                                       quality: CompressionQuality? = nil) -> Bool {
        guard let info = sourceInfo, info.isCompressed else { return false }
        guard let target = transferSyntax(for: targetCodec), target.isEncapsulated else { return false }
        if target.uid != info.transferSyntaxUID { return true }
        // Same UID: a two-phase re-encode only when an explicit quality targets a
        // lossy codestream (mirrors compressData's same-syntax lossy re-encode branch).
        return resolveEncoding(for: targetCodec)?.intent == .lossy && quality != nil
    }

    static func codecName(for syntax: TransferSyntax) -> String {
        for entry in codecMap {
            if entry.encoding.transferSyntax.uid == syntax.uid {
                return entry.names[0]
            }
        }
        return syntax.uid
    }

    /// Human-readable transfer-syntax label, sourced from the single shared catalog
    /// (`TransferSyntax.displayName` / `SelectableEncoding`) so compression output stays
    /// in lock-step with the rest of the library instead of maintaining a parallel map.
    ///
    /// The `both`-capable general UIDs (`.91`/`.93`/`.203`) are surfaced in their **lossy**
    /// form: in the compression domain their reversible counterparts are the distinct
    /// `.90`/`.92`/`.201` UIDs, so a bare `.91`/`.93`/`.203` here is always the irreversible
    /// encoding — spelling that out ("HTJ2K Lossy", "JPEG 2000 Lossy") tells the user
    /// exactly which codestream a file/target carries.
    public static func transferSyntaxDisplayName(_ syntax: TransferSyntax) -> String {
        guard syntax.losslessCapability == .both else { return syntax.displayName }
        return SelectableEncoding(transferSyntax: syntax, intent: .lossy).displayName
    }

    // MARK: - Info

    public func getCompressionInfo(path: String) throws -> CompressionInfo {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try getCompressionInfo(data: data)
    }

    /// In-memory variant — used by DICOMStudio (reads via a security-scoped URL).
    public func getCompressionInfo(data: Data) throws -> CompressionInfo {
        let file = try DICOMFile.read(from: data)

        let tsUID = file.fileMetaInformation.string(for: .transferSyntaxUID)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? "1.2.840.10008.1.2"
        let syntax = TransferSyntax.from(uid: tsUID)

        // Effective lossless state. For the `both`-capable general UIDs
        // (.91 / .93 / .203 / .112) the UID alone can't say whether the codestream
        // is reversible: an image reversibly encoded INTO the general UID is
        // indistinguishable at the UID level from a lossy one. The authoritative
        // per-file signal is Lossy Image Compression (0028,2110) — "01" means the
        // pixels were lossy-compressed at some step, "00"/absent means they were
        // not — so consult it for `both` UIDs. Single-capability syntaxes keep the
        // UID-level flag, where the UID IS authoritative (.90 always lossless, .50
        // always lossy). Reference: PS3.3 C.7.6.1.1.5, PS3.5 A.4.4 / A.4.12.
        let lossyFlag = file.dataSet.string(for: .lossyImageCompression)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        let isLossless: Bool
        switch syntax?.losslessCapability {
        case .some(.both):         isLossless = (lossyFlag != "01")
        case .some(.losslessOnly): isLossless = true
        case .some(.lossyOnly):    isLossless = false
        case .none:                isLossless = true   // unknown UID → prior default
        }

        // Name reflects the ACTUAL encoded intent so it never contradicts the
        // Lossless line: a reversibly encoded .91 reads "JPEG 2000 Lossless", not
        // the UID's default "Lossy". Single-capability UIDs use the shared label.
        let transferSyntaxName: String = {
            guard let s = syntax else { return tsUID }
            guard s.losslessCapability == .both else {
                return CompressionManager.transferSyntaxDisplayName(s)
            }
            return SelectableEncoding(
                transferSyntax: s, intent: isLossless ? .lossless : .lossy).displayName
        }()

        let pixelElement = file.dataSet[.pixelData]

        // Pixel Data size: for native (non-encapsulated) data the element length
        // is the byte count. For encapsulated data the length field is the
        // 0xFFFFFFFF undefined-length sentinel — not a byte count — so report the
        // actual compressed payload, the sum of the encapsulated fragment sizes
        // (the Basic Offset Table is metadata, not pixel bytes). Without this,
        // every compressed file reported the sentinel literally as ≈4.0 GB.
        let pixelDataSize: Int? = pixelElement.map { element in
            if let fragments = element.encapsulatedFragments {
                return fragments.reduce(0) { $0 + $1.count }
            }
            // Defend against a stray undefined-length sentinel with no parsed
            // fragments (malformed input): fall back to the actual value bytes.
            if element.length == 0xFFFFFFFF {
                return element.valueData.count
            }
            return Int(element.length)
        }

        return CompressionInfo(
            transferSyntaxUID: tsUID,
            transferSyntaxName: transferSyntaxName,
            isCompressed: syntax?.isEncapsulated ?? false,
            isLossless: isLossless,
            isJPEG: syntax?.isJPEG ?? false,
            isJPEG2000: syntax?.isJPEG2000 ?? false,
            isJPEGLS: syntax?.isJPEGLS ?? false,
            isJPEGXL: syntax?.isJPEGXL ?? false,
            isRLE: syntax?.isRLE ?? false,
            isDeflated: syntax?.isDeflated ?? false,
            pixelDataSize: pixelDataSize,
            rows: file.dataSet.uint16(for: .rows),
            columns: file.dataSet.uint16(for: .columns),
            bitsAllocated: file.dataSet.uint16(for: .bitsAllocated),
            bitsStored: file.dataSet.uint16(for: .bitsStored),
            samplesPerPixel: file.dataSet.uint16(for: .samplesPerPixel),
            photometricInterpretation: file.dataSet.string(for: .photometricInterpretation)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
            numberOfFrames: file.dataSet.string(for: .numberOfFrames)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
            lossyImageCompression: lossyFlag
        )
    }

    // MARK: - Compress

    public func compressFile(
        inputPath: String,
        outputPath: String,
        codec: String,
        quality: CompressionQuality?
    ) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let outputData = try compressData(data, codec: codec, quality: quality)
        try outputData.write(to: URL(fileURLWithPath: outputPath))
    }

    /// In-memory compress (no file I/O) — used by DICOMStudio, which writes the
    /// result through its sandbox-aware OutputAccess path.
    /// `backend` forces a codec execution path where one exists (J2K/HTJ2K
    /// Metal GPU encode); codecs without a matching path run their default.
    /// `jpegEngine` picks the JPEG **Baseline** encoder (JLICodec or Apple
    /// ImageIO); every other codec ignores it. It exists for DICOMStudio's
    /// encoder benchmarking — the `dicom-compress` CLI leaves it at `.jli`.
    public func compressData(_ inputData: Data, codec: String, quality: CompressionQuality?,
                             backend: CodecBackendPreference = .auto,
                             jpegEngine: JPEGCodecEngine = .jli) throws -> Data {
        guard let targetEncoding = CompressionManager.resolveEncoding(for: codec) else {
            throw CompressionError.unknownCodec(codec)
        }
        let targetSyntax = targetEncoding.transferSyntax
        let intent = targetEncoding.intent

        let file = try DICOMFile.read(from: inputData)

        // Resolve the source transfer syntax so we can decide whether this
        // call is an actual compression, a recompression (transcode), a
        // decompression, or just a UID rewrite for two uncompressed forms.
        let sourceSyntax = CompressionManager.resolveSourceTransferSyntax(file: file)

        var workingDataSet = file.dataSet

        // Actually invoke the codec when the target requires encapsulated
        // (compressed) pixel data. The prior implementation only ever
        // rewrote the Transfer Syntax UID, leaving uncompressed bytes in
        // place — every `--codec` flag was silently a no-op for 13/13
        // codecs (output size ≈ input size). See dicom-compress bug
        // report (2026-05-11).
        if targetSyntax.isEncapsulated && !sourceSyntax.isEncapsulated {
            try CompressionManager.encodePixelDataInPlace(
                dataSet: &workingDataSet,
                targetSyntax: targetSyntax,
                quality: quality,
                intent: intent,
                backend: backend,
                jpegEngine: jpegEngine
            )
        } else if targetSyntax.isEncapsulated && sourceSyntax.isEncapsulated
                  && (targetSyntax.uid != sourceSyntax.uid
                      || (intent == .lossy && quality != nil)) {
            // Recompression: decompress source then encode to target. This also
            // covers a SAME-syntax lossy re-encode: a source already in the
            // target's UID (e.g. a JPEG 2000 .91 file re-compressed with
            // `--codec jpeg2000 --quality …`) used to fall through to the
            // passthrough below, which copied the existing codestream verbatim
            // and silently discarded `--quality` — input size == output size,
            // ~0 ms, no actual encode. When an explicit quality is supplied for
            // a lossy target we honor it: decode the source to native pixels and
            // re-encode at the requested quality. Lossless / no-quality
            // same-syntax targets keep the passthrough — re-encoding a
            // reversible codestream into itself is wasted work.
            try CompressionManager.transcodeEncapsulatedInPlace(
                dataSet: &workingDataSet,
                sourceSyntax: sourceSyntax,
                targetSyntax: targetSyntax,
                quality: quality,
                intent: intent,
                backend: backend,
                jpegEngine: jpegEngine
            )
        } else if !targetSyntax.isEncapsulated && sourceSyntax.isEncapsulated {
            // Decompress: decode pixel data into uncompressed bytes.
            // Callers wanting decompression should generally use the
            // `decompress` subcommand, but `compress --codec explicit-le`
            // (and similar) reach here and must do the right thing.
            try CompressionManager.decodePixelDataInPlace(
                dataSet: &workingDataSet,
                sourceSyntax: sourceSyntax,
                targetSyntax: targetSyntax
            )
        }
        // else: both source and target are uncompressed (or syntaxes are
        // identical) — UID rewrite via TransferSyntaxHelper is correct.

        let converter = TransferSyntaxHelper()
        return try converter.convert(
            dataSet: workingDataSet,
            to: targetSyntax,
            preservePixelData: true
        )
    }

    /// Per-phase metrics for a compress run, so the console can report the sizes and
    /// timings of each phase. A plain compress (uncompressed source) has a single
    /// compression phase (`intermediateSize`/`decompressElapsed` are nil). A
    /// recompression (already-compressed source → a different codec) has TWO phases —
    /// first the source is decompressed to native pixels, then those are re-encoded to
    /// the target — so it also carries the intermediate (decompressed) size and the
    /// decompression time.
    public struct CompressMetrics: Sendable {
        public let inputSize: Int                    // source file bytes
        public let outputSize: Int                   // final output file bytes
        public let isRecompression: Bool
        public let sourceTransferSyntaxName: String? // set only for a recompression
        public let intermediateSize: Int?            // decompressed (native) file bytes; nil for plain compress
        public let decompressElapsed: TimeInterval?  // decompression phase; nil for plain compress
        public let compressElapsed: TimeInterval     // compression phase (full run for a plain compress)

        public init(inputSize: Int, outputSize: Int, isRecompression: Bool,
                    sourceTransferSyntaxName: String?, intermediateSize: Int?,
                    decompressElapsed: TimeInterval?, compressElapsed: TimeInterval) {
            self.inputSize = inputSize
            self.outputSize = outputSize
            self.isRecompression = isRecompression
            self.sourceTransferSyntaxName = sourceTransferSyntaxName
            self.intermediateSize = intermediateSize
            self.decompressElapsed = decompressElapsed
            self.compressElapsed = compressElapsed
        }
    }

    /// Compress `inputData` to `codec`, returning the output bytes AND per-phase
    /// `CompressMetrics` (sizes + timings) for the console. This is the entry point the
    /// `dicom-compress` CLI and the Studio Workshop use so the timing/size split is
    /// produced once, in core, rather than re-derived per surface.
    ///
    /// For a recompression it performs the two phases EXPLICITLY — decompress the
    /// source to native pixels (Explicit VR LE), then compress those to the target —
    /// which is exactly the behaviour the console's "decompressing to native pixels
    /// first, then re-encoding" note describes, and lets each phase be timed and its
    /// intermediate size measured. The produced pixels are identical to a direct
    /// `compressData` transcode (both decode the same source and feed the same native
    /// pixels to the same encoder). Pass `sourceInfo` if already computed to avoid a
    /// redundant parse.
    public func compressDataWithMetrics(
        _ inputData: Data,
        codec: String,
        quality: CompressionQuality?,
        sourceInfo: CompressionInfo? = nil,
        backend: CodecBackendPreference = .auto,
        jpegEngine: JPEGCodecEngine = .jli
    ) throws -> (data: Data, metrics: CompressMetrics) {
        guard CompressionManager.transferSyntax(for: codec) != nil else {
            throw CompressionError.unknownCodec(codec)
        }
        let info = sourceInfo ?? (try? getCompressionInfo(data: inputData))

        if CompressionManager.isRecompression(sourceInfo: info, targetCodec: codec, quality: quality) {
            // Phase 1 — decompress the source to native pixels (Explicit VR LE).
            let d0 = Date()
            let intermediate = try decompressData(inputData, syntax: .explicitVRLittleEndian)
            let decompressElapsed = Date().timeIntervalSince(d0)
            // Phase 2 — compress the native pixels to the target codec.
            let c0 = Date()
            let output = try compressData(intermediate, codec: codec, quality: quality,
                                          backend: backend, jpegEngine: jpegEngine)
            let compressElapsed = Date().timeIntervalSince(c0)
            return (output, CompressMetrics(
                inputSize: inputData.count, outputSize: output.count, isRecompression: true,
                sourceTransferSyntaxName: info?.transferSyntaxName, intermediateSize: intermediate.count,
                decompressElapsed: decompressElapsed, compressElapsed: compressElapsed))
        }

        // Plain compress (uncompressed source, or a same-syntax passthrough).
        let c0 = Date()
        let output = try compressData(inputData, codec: codec, quality: quality,
                                      backend: backend, jpegEngine: jpegEngine)
        let compressElapsed = Date().timeIntervalSince(c0)
        return (output, CompressMetrics(
            inputSize: inputData.count, outputSize: output.count, isRecompression: false,
            sourceTransferSyntaxName: nil, intermediateSize: nil,
            decompressElapsed: nil, compressElapsed: compressElapsed))
    }

    // MARK: - Codec dispatch helpers (v9.1 fix)

    /// Resolves the source transfer syntax from a parsed DICOM file's
    /// File Meta Information. Falls back to Explicit VR Little Endian
    /// when the UID is missing (matches DICOMFile.read's default).
    static func resolveSourceTransferSyntax(file: DICOMFile) -> TransferSyntax {
        let sourceUID = file.fileMetaInformation.string(for: .transferSyntaxUID)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            ?? TransferSyntax.explicitVRLittleEndian.uid

        // Try to find the canonical TransferSyntax by UID. If the UID
        // isn't one of the known constants, build a synthetic one with
        // sensible defaults — encapsulated flag is critical for branching
        // so we infer it from the standard UID prefix conventions.
        if let known = TransferSyntax.fromKnownUID(sourceUID) {
            return known
        }
        let isEncap = !TransferSyntax.uncompressedUIDs.contains(sourceUID)
        return TransferSyntax(
            uid: sourceUID,
            isExplicitVR: true,
            byteOrder: .littleEndian,
            isEncapsulated: isEncap
        )
    }

    /// Compresses uncompressed pixel data using the encoder registered
    /// for the target transfer syntax UID, then replaces the data set's
    /// PixelData element with an encapsulated pixel data element holding
    /// the compressed fragments.
    ///
    /// Bug-fix for the previous behaviour where compressFile only
    /// rewrote the Transfer Syntax UID without invoking any encoder.
    static func encodePixelDataInPlace(
        dataSet: inout DataSet,
        targetSyntax: TransferSyntax,
        quality: CompressionQuality?,
        intent: EncodingIntent = .notApplicable,
        backend: CodecBackendPreference = .auto,
        jpegEngine: JPEGCodecEngine = .jli
    ) throws {
        // `jpegEngine` only diverts JPEG Baseline to the native (ImageIO) encoder;
        // for every other transfer syntax this resolves to the registered encoder.
        guard let encoder = CodecRegistry.shared.encoder(for: targetSyntax.uid, engine: jpegEngine) else {
            throw CompressionError.encoderNotAvailable(targetSyntax.uid)
        }
        guard let pixelDataElement = dataSet[.pixelData] else {
            throw CompressionError.noPixelData
        }
        // Source pixel data must be uncompressed bytes here (caller
        // guarantees source !isEncapsulated). The encoder takes the
        // contiguous byte buffer for all frames concatenated, little-endian:
        // OW Pixel Data read from an Explicit VR Big Endian file is swapped first.
        var uncompressedBytes = DICOMWriter.value(
            pixelDataElement.valueData, vr: pixelDataElement.vr,
            from: pixelDataElement.byteOrder, to: .littleEndian)

        var descriptor = try buildPixelDataDescriptor(from: dataSet)

        // Reversible vs irreversible for THIS encode. The general (`.both`-capable) UIDs
        // honour the caller's intent (`.lossless`/`.lossy`); single-capability UIDs are
        // fixed by the UID. A `both` UID with no explicit intent defaults to lossy, matching
        // the historical bare-alias behaviour.
        let encodeLossless: Bool
        switch targetSyntax.losslessCapability {
        case .both:          encodeLossless = (intent == .lossless)
        case .losslessOnly:  encodeLossless = true
        case .lossyOnly:     encodeLossless = false
        }

        let configuration: CompressionConfiguration = {
            // --backend rides along in the config (nil = auto); only codecs
            // with an alternate execution path (J2K/HTJ2K Metal) act on it.
            let forced = backend.forced
            if encodeLossless {
                return CompressionConfiguration(
                    quality: .maximum, speed: .balanced,
                    preferLossless: true, forcedBackend: forced)
            }
            // For lossy paths honour the user's --quality if supplied.
            if let q = quality {
                return CompressionConfiguration(quality: q, speed: .balanced, forcedBackend: forced)
            }
            return CompressionConfiguration(forcedBackend: forced)
        }()

        // Reject unsupported target syntaxes (currently JPEG 2000 Part-2) with a clear,
        // specific reason before the generic layout check below.
        if let reason = J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: targetSyntax.uid) {
            throw CompressionError.unsupportedPixelDataConfiguration(reason)
        }

        // J2KSwift applies the Part 1 colour transform (SGcod MCT = 1) to every 3-component
        // image, which PS3.5 2026a 8.2.4 / 8.2.14 permit only under YBR_RCT / YBR_ICT: YBR_FULL
        // samples are converted to RGB first (lossy targets only — the conversion rounds) and
        // labelled from the codestream below (D-CORE-3, shared with TransferSyntaxConverter).
        if targetSyntax.isJPEG2000, descriptor.photometricInterpretation == .ybrFull {
            do {
                (uncompressedBytes, descriptor) = try TransferSyntaxConverter.rgbForJPEG2000Encode(
                    uncompressedBytes, descriptor: descriptor, lossless: encodeLossless)
            } catch TranscodingError.encodingFailed(let reason) {
                throw CompressionError.unsupportedPixelDataConfiguration(reason)
            }
        }

        guard encoder.canEncode(with: configuration, descriptor: descriptor) else {
            throw CompressionError.unsupportedPixelDataConfiguration(
                "Encoder for \(targetSyntax.uid) cannot handle "
                + "bitsAllocated=\(descriptor.bitsAllocated), "
                + "samplesPerPixel=\(descriptor.samplesPerPixel), "
                + "photometricInterpretation=\(descriptor.photometricInterpretation.rawValue)"
            )
        }

        let compressedFrames = try encoder.encode(
            uncompressedBytes,
            descriptor: descriptor,
            configuration: configuration
        )

        let offsetTable = buildBasicOffsetTable(for: compressedFrames)
        dataSet[.pixelData] = DataElement(
            tag: .pixelData,
            vr: .OB,                         // Encapsulated pixel data is always OB
            length: 0xFFFFFFFF,              // Undefined length sentinel
            valueData: Data(),
            encapsulatedFragments: compressedFrames,
            encapsulatedOffsetTable: offsetTable
        )

        // Photometric Interpretation / Planar Configuration follow what was encoded.
        labelEncodedColour(in: &dataSet, targetSyntax: targetSyntax, firstCodestream: compressedFrames.first)

        // Record DICOM lossy-compression provenance when this encode was irreversible.
        if !encodeLossless {
            let compressedByteCount = compressedFrames.reduce(0) { $0 + $1.count }
            applyLossyImageCompressionAttributes(
                to: &dataSet,
                targetSyntax: targetSyntax,
                uncompressedByteCount: uncompressedBytes.count,
                compressedByteCount: compressedByteCount
            )
        }
    }

    /// Sets Photometric Interpretation and Planar Configuration from the codestream an encoder
    /// wrote (D185 / D-KIT-1, D190 / D-CORE-2):
    /// - JPEG 2000 / HTJ2K: SGcod MCT = 1 → YBR_RCT (5-3 reversible) or YBR_ICT (9-7
    ///   irreversible); Planar Configuration "shall be set to 0" (PS3.5 2026a 8.2.4, Table
    ///   8.2.4-1; 8.2.14, Table 8.2.14-1).
    /// - JPEG Baseline / Extended: 3 components sampled H 2,1,1 / V 1,1,1 → YBR_FULL_422 with
    ///   Planar Configuration 0 (Table 8.2.1-1 allows only YBR_FULL_422 or RGB).
    static func labelEncodedColour(in dataSet: inout DataSet, targetSyntax: TransferSyntax,
                                   firstCodestream: Data?) {
        guard let codestream = firstCodestream else { return }
        var newPI: String?
        if targetSyntax.isJPEG2000 {
            guard let style = J2KCodestreamInspector.codingStyle(in: codestream),
                  style.componentCount == 3 else { return }
            if style.multipleComponentTransform == 1 {
                newPI = style.reversibleWavelet ? "YBR_RCT" : "YBR_ICT"
            }
        } else if targetSyntax.uid == TransferSyntax.jpegBaseline.uid
                    || targetSyntax.uid == TransferSyntax.jpegExtended.uid {
            guard JPEGInterchangeFormat.isHorizontally422(codestream) else { return }
            newPI = "YBR_FULL_422"
        } else {
            return
        }
        if let newPI {
            dataSet.setString(newPI, for: .photometricInterpretation, vr: .CS)
        }
        if dataSet[.planarConfiguration] != nil {
            dataSet.setUInt16(0, for: .planarConfiguration)
        }
    }

    /// Records the DICOM Lossy Image Compression provenance attributes after an irreversible
    /// encode. Per PS3.3 C.7.6.1.1.5 these accumulate ("once lossy, always lossy"): the flag
    /// (0028,2110) is set to `"01"` and stays set, and the ratio (0028,2112) / method
    /// (0028,2114) are **appended** as parallel VM 1-n values — one per lossy step — so a
    /// recompression preserves the earlier history.
    ///
    /// The ratio is the whole-instance uncompressed-to-compressed byte ratio (all frames).
    /// No-op when the target has no lossy method Defined Term (i.e. it is reversible-only).
    static func applyLossyImageCompressionAttributes(
        to dataSet: inout DataSet,
        targetSyntax: TransferSyntax,
        uncompressedByteCount: Int,
        compressedByteCount: Int
    ) {
        guard let method = targetSyntax.lossyImageCompressionMethod else { return }

        // (0028,2110) Lossy Image Compression = "01" (idempotent; never reset to "00").
        dataSet.setString("01", for: .lossyImageCompression, vr: .CS)

        // (0028,2112) Ratio and (0028,2114) Method are parallel VM 1-n arrays: the Nth ratio
        // corresponds to the Nth method (PS3.3 C.7.6.1.1.5.1). Keep only the paired prefix of
        // any pre-existing history before appending this step's pair, so the arrays stay
        // aligned even when a (malformed) source carried a ratio without a method or vice
        // versa. An orphan tail is uninterpretable (no matching Nth value) and cannot be
        // represented as an empty component through the backslash-delimited reader, so it is
        // dropped rather than left silently misaligned; the lossy flag (0028,2110) still
        // records that the image is irreversibly compressed.
        let ratio = Double(uncompressedByteCount) / Double(max(1, compressedByteCount))
        var ratios = dataSet.strings(for: .lossyImageCompressionRatio) ?? []
        var methods = dataSet.strings(for: .lossyImageCompressionMethod) ?? []
        let paired = min(ratios.count, methods.count)
        ratios = Array(ratios.prefix(paired))
        methods = Array(methods.prefix(paired))
        ratios.append(DICOMDecimalString(value: ratio).dicomString)
        methods.append(method)
        dataSet.setStrings(ratios, for: .lossyImageCompressionRatio, vr: .DS)
        dataSet.setStrings(methods, for: .lossyImageCompressionMethod, vr: .CS)

        // (0008,0008) Image Type Value 1 → DERIVED once lossy compression has been applied
        // (PS3.3 2026a C.7.6.1.1.5: "If an image is a compressed version of another image, …
        // Value 1 of the Attribute Image Type (0008,0008) shall be set to DERIVED"). Only rewrite
        // when Image Type is present and still marked ORIGINAL; leave absent Image Type alone
        // (not all IODs define it) and preserve an already-DERIVED value.
        var imageType = dataSet.strings(for: .imageType) ?? []
        if !imageType.isEmpty, imageType[0].uppercased() == "ORIGINAL" {
            imageType[0] = "DERIVED"
            dataSet.setStrings(imageType, for: .imageType, vr: .CS)
        }

        // "… and if the predecessor was a DICOM image, then the Image shall receive a new SOP
        // Instance UID" (PS3.3 2026a C.7.6.1.1.5; D184, D192). The File Meta Information's Media
        // Storage SOP Instance UID (0002,0003) is written from this value.
        if dataSet[.sopInstanceUID] != nil {
            dataSet.setString(UIDGenerator.generateSOPInstanceUID().value, for: .sopInstanceUID, vr: .UI)
        }

        // "For historical reasons, the lossy compression ratio should also be described in
        // Derivation Description (0008,2111)" (C.7.6.1.1.5.2). Appended, so earlier steps stay.
        let step = "Lossy compression \(method), ratio \(DICOMDecimalString(value: ratio).dicomString):1"
        let previous = dataSet.string(for: .derivationDescription)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
        let description = previous.isEmpty ? step : previous + "; " + step
        if description.utf8.count <= 1024 {   // ST: at most 1024 characters (PS3.5 Table 6.2-1)
            dataSet.setString(description, for: .derivationDescription, vr: .ST)
        }
    }

    /// Decodes encapsulated pixel data back into uncompressed bytes,
    /// then replaces the PixelData element with an un-encapsulated form
    /// suitable for the (uncompressed) target syntax.
    static func decodePixelDataInPlace(
        dataSet: inout DataSet,
        sourceSyntax: TransferSyntax,
        targetSyntax: TransferSyntax,
        backend: CodecBackendPreference = .auto
    ) throws {
        // Phase 4: honour the backend preference on decode for JPEG 2000 / HTJ2K
        // sources by using a decode-backend-aware `J2KSwiftCodec` (which auto-detects
        // Part-1 / Part-2 / HTJ2K). Every other codec resolves from the registry as
        // before (their decode has no GPU path / backend axis).
        let codec: ImageCodec
        if sourceSyntax.isJPEG2000 {
            codec = J2KSwiftCodec(decodeBackend: backend.forced, decodingTransferSyntaxUID: sourceSyntax.uid)
        } else if let registryCodec = CodecRegistry.shared.codec(for: sourceSyntax.uid) {
            codec = registryCodec
        } else {
            throw CompressionError.decoderNotAvailable(sourceSyntax.uid)
        }
        guard let pixelDataElement = dataSet[.pixelData] else {
            throw CompressionError.noPixelData
        }
        guard let fragments = pixelDataElement.encapsulatedFragments else {
            throw CompressionError.conversionFailed(
                "Source declares encapsulated transfer syntax \(sourceSyntax.uid) "
                + "but PixelData element has no encapsulated fragments"
            )
        }

        let descriptor = try buildPixelDataDescriptor(from: dataSet)

        // Decode each frame, concatenate. Most codecs produce one fragment
        // per frame, but the spec permits multi-fragment frames; we
        // delegate that responsibility to the codec via decode(...) which
        // handles both cases.
        var combined = Data()
        combined.reserveCapacity(descriptor.totalBytes)
        if fragments.count == descriptor.numberOfFrames {
            for (frameIndex, frame) in fragments.enumerated() {
                let frameBytes = try codec.decodeFrame(
                    frame,
                    descriptor: descriptor,
                    frameIndex: frameIndex
                )
                combined.append(frameBytes)
            }
        } else {
            // Fall back to the multi-frame decode entry point with the
            // contiguous concatenation of all fragments.
            var concatenated = Data()
            for frame in fragments { concatenated.append(frame) }
            combined = try codec.decode(concatenated, descriptor: descriptor)
        }

        // Even byte length padding per DICOM PS3.5 Section 7.1.
        if combined.count % 2 != 0 {
            combined.append(0x00)
        }

        dataSet[.pixelData] = DataElement(
            tag: .pixelData,
            vr: descriptor.bitsAllocated > 8 ? .OW : .OB,
            length: UInt32(combined.count),
            valueData: combined
        )

        // JPEG 2000 / HTJ2K decoders invert the Part 1 multi-component transformation: "If color
        // components are converted from YBR_ICT or YBR_RCT to RGB during decompression and Native
        // re-encoding, the Photometric Interpretation will be changed to RGB" (PS3.5 2026a 8.2.4;
        // 8.2.14 for HTJ2K); native Pixel Data never carries YBR_RCT / YBR_ICT (D186 / D-KIT-1).
        if sourceSyntax.isJPEG2000,
           descriptor.photometricInterpretation == .ybrRCT || descriptor.photometricInterpretation == .ybrICT {
            dataSet.setString("RGB", for: .photometricInterpretation, vr: .CS)
        }

        // JPEG Baseline/Extended (SOF0/SOF1) decode always yields RGB samples —
        // JLIDecoder converts YCbCr → RGB internally regardless of the source's
        // declared Photometric Interpretation (PS3.5 Table 8.2.1-1 permits either
        // YBR_FULL_422 or RGB going in). Correct the tag so it matches the bytes
        // actually decoded; SOF3 lossless (.57/.70) is untouched here since it
        // never applies a color transform and the original tag already matches.
        if (sourceSyntax.uid == TransferSyntax.jpegBaseline.uid
            || sourceSyntax.uid == TransferSyntax.jpegExtended.uid),
           descriptor.samplesPerPixel == 3,
           descriptor.photometricInterpretation.isYBR {
            dataSet.setString("RGB", for: .photometricInterpretation, vr: .CS)
        }

        // The JPEG XL decoder applies the inverse XYB transform and yields RGB samples;
        // "Images in XYB transcoded to other Transfer Syntaxes will use RGB"
        // (PS3.3 C.7.6.3.1.2), as TransferSyntaxConverter already does.
        if sourceSyntax.isJPEGXL, descriptor.photometricInterpretation == .xyb {
            dataSet.setString("RGB", for: .photometricInterpretation, vr: .CS)
        }
    }

    /// Recompression path — decode then re-encode. Operates only on
    /// the PixelData element in-place.
    static func transcodeEncapsulatedInPlace(
        dataSet: inout DataSet,
        sourceSyntax: TransferSyntax,
        targetSyntax: TransferSyntax,
        quality: CompressionQuality?,
        intent: EncodingIntent = .notApplicable,
        backend: CodecBackendPreference = .auto,
        jpegEngine: JPEGCodecEngine = .jli
    ) throws {
        // Step 1: decode to uncompressed bytes (honouring the decode backend).
        try decodePixelDataInPlace(
            dataSet: &dataSet,
            sourceSyntax: sourceSyntax,
            targetSyntax: TransferSyntax.explicitVRLittleEndian,
            backend: backend
        )
        // Step 2: encode to target. Any existing lossy-compression history on the source
        // survives on `dataSet` and is preserved/appended-to by encodePixelDataInPlace.
        try encodePixelDataInPlace(
            dataSet: &dataSet,
            targetSyntax: targetSyntax,
            quality: quality,
            intent: intent,
            backend: backend,
            jpegEngine: jpegEngine
        )
    }

    /// Builds a PixelDataDescriptor from a parsed DataSet. Mirrors
    /// DICOMCore.TransferSyntaxConverter.extractPixelDataDescriptor
    /// (which is private to that type).
    static func buildPixelDataDescriptor(from dataSet: DataSet) throws -> PixelDataDescriptor {
        guard let rows = dataSet.uint16(for: .rows),
              let columns = dataSet.uint16(for: .columns),
              let bitsAllocated = dataSet.uint16(for: .bitsAllocated),
              let bitsStored = dataSet.uint16(for: .bitsStored),
              let highBit = dataSet.uint16(for: .highBit) else {
            throw CompressionError.conversionFailed(
                "Missing required pixel data attributes "
                + "(rows / columns / bitsAllocated / bitsStored / highBit)"
            )
        }
        let pixelRepresentation = dataSet.uint16(for: .pixelRepresentation) ?? 0
        let samplesPerPixel = dataSet.uint16(for: .samplesPerPixel) ?? 1
        let planarConfiguration = dataSet.uint16(for: .planarConfiguration) ?? 0

        let numberOfFrames: Int
        if let nfStr = dataSet.string(for: .numberOfFrames)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
           let nfVal = Int(nfStr), nfVal > 0 {
            numberOfFrames = nfVal
        } else {
            numberOfFrames = 1
        }

        let piRaw = dataSet.string(for: .photometricInterpretation)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        let photometricInterpretation: PhotometricInterpretation = {
            if let raw = piRaw, let pi = PhotometricInterpretation(rawValue: raw) {
                return pi
            }
            return samplesPerPixel == 1 ? .monochrome2 : .rgb
        }()

        return PixelDataDescriptor(
            rows: Int(rows),
            columns: Int(columns),
            numberOfFrames: numberOfFrames,
            bitsAllocated: Int(bitsAllocated),
            bitsStored: Int(bitsStored),
            highBit: Int(highBit),
            isSigned: pixelRepresentation == 1,
            samplesPerPixel: Int(samplesPerPixel),
            photometricInterpretation: photometricInterpretation,
            planarConfiguration: Int(planarConfiguration)
        )
    }

    /// Builds a Basic Offset Table (BOT) for an encapsulated pixel data
    /// element. Per DICOM PS3.5 A.4, the BOT is an array of UInt32
    /// offsets from the first byte of the first fragment (i.e. just
    /// after the BOT item) to the first byte of each frame's first
    /// fragment. We emit one offset per frame.
    static func buildBasicOffsetTable(for fragments: [Data]) -> [UInt32] {
        var offsets: [UInt32] = []
        offsets.reserveCapacity(fragments.count)
        var current: UInt32 = 0
        for fragment in fragments {
            offsets.append(current)
            // 8 bytes for the Item tag + length, then the fragment bytes —
            // padded to even length, exactly as the writer emits them (PS3.5
            // §7.4/A.4). Using the unpadded length here made every offset after
            // an odd-length fragment point one byte short (found by the M2
            // fail-closed frame index).
            let writtenLength = fragment.count + (fragment.count % 2)
            current = current &+ 8 &+ UInt32(writtenLength)
        }
        return offsets
    }

    // MARK: - Decompress

    public func decompressFile(
        inputPath: String,
        outputPath: String,
        syntax: TransferSyntax
    ) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let outputData = try decompressData(data, syntax: syntax)
        try outputData.write(to: URL(fileURLWithPath: outputPath))
    }

    /// In-memory decompress (no file I/O) — used by DICOMStudio.
    public func decompressData(_ inputData: Data, syntax: TransferSyntax) throws -> Data {
        let file = try DICOMFile.read(from: inputData)

        let sourceSyntax = CompressionManager.resolveSourceTransferSyntax(file: file)
        var workingDataSet = file.dataSet

        if sourceSyntax.isEncapsulated && !syntax.isEncapsulated {
            // Source compressed → target uncompressed: actually decode.
            try CompressionManager.decodePixelDataInPlace(
                dataSet: &workingDataSet,
                sourceSyntax: sourceSyntax,
                targetSyntax: syntax
            )
        }
        // else: source already uncompressed OR target is encapsulated
        // (caller misuse) — UID rewrite via TransferSyntaxHelper.

        let converter = TransferSyntaxHelper()
        return try converter.convert(
            dataSet: workingDataSet,
            to: syntax,
            preservePixelData: true
        )
    }

    // MARK: - Supported Codecs

    public static func supportedCodecs() -> [(name: String, syntax: TransferSyntax, aliases: [String])] {
        return codecMap.map { entry in
            (name: entry.names[0], syntax: entry.encoding.transferSyntax, aliases: Array(entry.names.dropFirst()))
        }
    }

    // MARK: - DICOM File Discovery

    public static func findDICOMFiles(in directory: String, recursive: Bool) throws -> [String] {
        let fm = FileManager.default
        var files: [String] = []

        if recursive {
            guard let enumerator = fm.enumerator(atPath: directory) else {
                throw CompressionError.directoryNotFound(directory)
            }
            while let path = enumerator.nextObject() as? String {
                let fullPath = (directory as NSString).appendingPathComponent(path)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    if isDICOMFile(fullPath) {
                        files.append(fullPath)
                    }
                }
            }
        } else {
            let contents = try fm.contentsOfDirectory(atPath: directory)
            for name in contents {
                let fullPath = (directory as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    if isDICOMFile(fullPath) {
                        files.append(fullPath)
                    }
                }
            }
        }

        return files.sorted()
    }

    private static func isDICOMFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "dcm" || ext == "dicom" || ext == "dic" {
            return true
        }
        // Try to detect DICOM files without extension by checking for DICM magic
        if ext.isEmpty {
            guard let handle = FileHandle(forReadingAtPath: path) else { return false }
            defer { handle.closeFile() }
            let header = handle.readData(ofLength: 132)
            if header.count >= 132 {
                let prefix = header.subdata(in: 128..<132)
                return String(data: prefix, encoding: .ascii) == "DICM"
            }
        }
        return false
    }
}

// MARK: - Transfer Syntax Helper (matches dicom-convert Converter pattern)

@available(macOS 10.15, *)
struct TransferSyntaxHelper {
    func convert(
        dataSet: DataSet,
        to targetSyntax: TransferSyntax,
        preservePixelData: Bool = true
    ) throws -> Data {
        var fileMeta = DataSet()

        // File Meta Information Version
        let versionTag = Tag.fileMetaInformationVersion
        fileMeta[versionTag] = DataElement(
            tag: versionTag,
            vr: .OB,
            length: 2,
            valueData: Data([0x00, 0x01])
        )

        // UI values are padded to an even length with a single trailing NULL (PS3.5 2026a 6.2,
        // Table 6.2-1 UI; 7.1: even Value Length; D188).
        func uiElement(_ tag: Tag, _ uid: String) -> DataElement? {
            let trimmed = uid.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII) else { return nil }
            let data = DICOMWriter().padString(trimmed, vr: .UI)
            return DataElement(tag: tag, vr: .UI, length: UInt32(data.count), valueData: data)
        }

        // Media Storage SOP Class UID
        if let sopClassUID = dataSet.string(for: .sopClassUID) {
            fileMeta[.mediaStorageSOPClassUID] = uiElement(.mediaStorageSOPClassUID, sopClassUID)
        }

        // Media Storage SOP Instance UID
        if let sopInstanceUID = dataSet.string(for: .sopInstanceUID) {
            fileMeta[.mediaStorageSOPInstanceUID] = uiElement(.mediaStorageSOPInstanceUID, sopInstanceUID)
        }

        // Transfer Syntax UID
        fileMeta[.transferSyntaxUID] = uiElement(.transferSyntaxUID, targetSyntax.uid)

        // Implementation Class UID
        fileMeta[.implementationClassUID] = uiElement(.implementationClassUID, "1.2.826.0.1.3680043.10.1")

        // Implementation Version Name
        if let versionData = "DICOMKIT-1.0".data(using: .ascii) {
            fileMeta[.implementationVersionName] = DataElement(
                tag: .implementationVersionName,
                vr: .SH,
                length: UInt32(versionData.count),
                valueData: versionData
            )
        }

        // Build output
        var output = Data()

        // Preamble + DICM prefix
        output.append(Data(repeating: 0, count: 128))
        output.append(contentsOf: "DICM".utf8)

        // Write file meta information (always Explicit VR Little Endian)
        let metaWriter = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let metaData = writeDataSet(fileMeta, writer: metaWriter)

        // File Meta Information Group Length
        let lengthData = metaWriter.serializeUInt32(UInt32(metaData.count))
        let groupLengthElement = DataElement(
            tag: .fileMetaInformationGroupLength,
            vr: .UL,
            length: UInt32(lengthData.count),
            valueData: lengthData
        )
        output.append(metaWriter.serializeElement(groupLengthElement))
        output.append(metaData)

        // Write main dataset with target transfer syntax. A Deflated Explicit VR
        // Little Endian target (PS3.5 A.5) serializes the Data Set as Explicit VR
        // LE and then DEFLATE-compresses it — the File Meta Information above stays
        // uncompressed. Without this the file was labeled 1.2.840.10008.1.2.1.99
        // but carried raw (un-deflated) bytes, so readers failed with
        // "Failed to decompress deflated data".
        let dataWriter = createWriter(for: targetSyntax)
        var dataSetData = writeDataSet(dataSet, writer: dataWriter)
        if targetSyntax.isDeflated {
            guard let deflated = dataSetData.deflateCompressed() else {
                throw CompressionError.conversionFailed(
                    "Failed to deflate the Data Set for \(targetSyntax.uid). "
                    + "Deflate compression is unavailable on this platform."
                )
            }
            dataSetData = deflated
        }
        output.append(dataSetData)

        return output
    }

    private func createWriter(for transferSyntax: TransferSyntax) -> DICOMWriter {
        let byteOrder: ByteOrder = transferSyntax.byteOrder
        let explicitVR = transferSyntax.isExplicitVR
        return DICOMWriter(byteOrder: byteOrder, explicitVR: explicitVR)
    }

    private func writeDataSet(_ dataSet: DataSet, writer: DICOMWriter) -> Data {
        var output = Data()
        for tag in dataSet.tags.sorted() {
            guard let element = dataSet[tag] else { continue }
            // Encapsulated (compressed) PixelData needs the BOT + Item-tagged
            // fragment + Sequence Delimitation structure, which the shared
            // DICOMWriter does not emit (it skips undefined-length values), so it
            // keeps its dedicated serializer.
            if element.tag == .pixelData
                && element.encapsulatedFragments != nil {
                output.append(serializeEncapsulatedPixelData(element, writer: writer))
                continue
            }
            // Everything else goes through the library's real element serializer.
            // The previous bespoke writer dumped each element's raw `valueData`
            // under the *target* framing — which corrupted sequences carried over
            // from an Implicit VR source (their bytes are implicit-encoded) and
            // truncated the declared length of >64 KB 16-bit-VR elements, both of
            // which desynced the reader so it stopped before PixelData ("No pixel
            // data found in DICOM file"). DICOMWriter re-encodes sequences from
            // their parsed items; the sanitizer keeps oversized short-VR values
            // representable under Explicit VR.
            output.append(writer.serializeElement(
                sanitizedForExplicitVR(element, explicitVR: writer.explicitVR)))
        }
        return output
    }

    /// Promotes an element whose value exceeds the 0xFFFF that a 16-bit Explicit
    /// VR length field can hold — legal under Implicit VR's 32-bit length — to UN,
    /// which carries a 32-bit length. Without this, transcoding Implicit→Explicit
    /// VR either silently truncated the declared length (desyncing every later
    /// element, including PixelData) or trapped on `UInt16(overflow)`.
    private func sanitizedForExplicitVR(_ element: DataElement, explicitVR: Bool) -> DataElement {
        guard explicitVR, element.vr != .SQ, !element.vr.uses32BitLength,
              element.valueData.count > 0xFFFF else { return element }
        return DataElement(tag: element.tag, vr: .UN,
                           length: UInt32(element.valueData.count),
                           valueData: element.valueData)
    }

    /// Serialises an encapsulated PixelData element per DICOM PS3.5 A.4
    /// (Encapsulation of Encoded Pixel Data). Layout:
    ///
    ///   (7FE0,0010) OB  undefined-length
    ///   (FFFE,E000) Item  <BOT length>  <BOT bytes>
    ///   (FFFE,E000) Item  <frag-1 length>  <frag-1 bytes>
    ///   ...
    ///   (FFFE,E000) Item  <frag-N length>  <frag-N bytes>
    ///   (FFFE,E0DD) Sequence Delimitation Item, length 0
    ///
    /// All length fields are 4-byte little-endian unsigned. Encapsulated
    /// pixel data is always written with Explicit VR Little Endian per
    /// PS3.5; the `writer` byte order is honoured for completeness.
    private func serializeEncapsulatedPixelData(
        _ element: DataElement,
        writer: DICOMWriter
    ) -> Data {
        var output = Data()

        // PixelData element header: tag(7FE0,0010) + VR(OB) + 2 reserved
        // + undefined length (0xFFFFFFFF).
        output.append(writer.serializeUInt16(element.tag.group))
        output.append(writer.serializeUInt16(element.tag.element))
        output.append(contentsOf: "OB".utf8)
        output.append(contentsOf: [0x00, 0x00])
        output.append(writer.serializeUInt32(0xFFFFFFFF))

        // Basic Offset Table (BOT) Item: (FFFE,E000) + length + offsets.
        let offsetTable = element.encapsulatedOffsetTable ?? []
        var botBytes = Data()
        for offset in offsetTable {
            botBytes.append(writer.serializeUInt32(offset))
        }
        output.append(writer.serializeUInt16(0xFFFE))
        output.append(writer.serializeUInt16(0xE000))
        output.append(writer.serializeUInt32(UInt32(botBytes.count)))
        output.append(botBytes)

        // Fragment items.
        if let fragments = element.encapsulatedFragments {
            for fragment in fragments {
                output.append(writer.serializeUInt16(0xFFFE))
                output.append(writer.serializeUInt16(0xE000))
                // Fragment bytes must be even-length per PS3.5; pad
                // with a trailing 0x00 if the codec returned odd-sized
                // data (rare but spec-required).
                let padded: Data
                if fragment.count % 2 != 0 {
                    var p = fragment
                    p.append(0x00)
                    padded = p
                } else {
                    padded = fragment
                }
                output.append(writer.serializeUInt32(UInt32(padded.count)))
                output.append(padded)
            }
        }

        // Sequence Delimitation Item (FFFE,E0DD) length 0.
        output.append(writer.serializeUInt16(0xFFFE))
        output.append(writer.serializeUInt16(0xE0DD))
        output.append(writer.serializeUInt32(0))

        return output
    }

    private func writeElement(_ element: DataElement, writer: DICOMWriter) throws -> Data {
        var output = Data()

        // Tag
        output.append(writer.serializeUInt16(element.tag.group))
        output.append(writer.serializeUInt16(element.tag.element))

        let vr = element.vr
        let valueData = element.valueData

        if writer.explicitVR {
            output.append(contentsOf: vr.rawValue.utf8)
            if vr.uses32BitLength {
                output.append(contentsOf: [0x00, 0x00])
                output.append(writer.serializeUInt32(UInt32(valueData.count)))
            } else {
                let length = min(valueData.count, 0xFFFF)
                output.append(writer.serializeUInt16(UInt16(length)))
            }
        } else {
            output.append(writer.serializeUInt32(UInt32(valueData.count)))
        }

        output.append(valueData)
        return output
    }
}

// MARK: - Errors

public enum CompressionError: Error, CustomStringConvertible {
    case unknownCodec(String)
    case fileNotFound(String)
    case directoryNotFound(String)
    case noPixelData
    case conversionFailed(String)
    case encoderNotAvailable(String)
    case decoderNotAvailable(String)
    case unsupportedPixelDataConfiguration(String)
    case invalidQuality(String)

    public var description: String {
        switch self {
        case .unknownCodec(let name):
            return "Unknown codec '\(name)'. Use 'dicom-compress compress --help' for supported codecs."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .noPixelData:
            return "No pixel data found in DICOM file"
        case .conversionFailed(let reason):
            return "Conversion failed: \(reason)"
        case .encoderNotAvailable(let uid):
            return "No encoder registered for transfer syntax \(uid). "
                + "The codec may be decode-only or unsupported on this platform."
        case .decoderNotAvailable(let uid):
            return "No decoder registered for transfer syntax \(uid). "
                + "Cannot decompress source pixel data."
        case .unsupportedPixelDataConfiguration(let detail):
            return "Encoder rejected pixel-data configuration: \(detail)"
        case .invalidQuality(let value):
            return "Invalid --quality value '\(value)'. "
                + "Use maximum / high / medium / low, or a number in 0.0...1.0."
        }
    }
}

/// Without this, `error.localizedDescription` — which DICOMStudio's console prints —
/// falls back to Foundation's opaque bridge string ("The operation couldn't be
/// completed. (DICOMKit.CompressionError error 6.)"), hiding the actual reason the
/// encode failed. The `dicom-compress` CLI never hit this because it interpolates the
/// error directly (`"\(error)"`), reaching `CustomStringConvertible` above. Mirrors
/// `DICOMError`'s conformance so both surfaces report the same sentence.
extension CompressionError: LocalizedError {
    public var errorDescription: String? { description }
}

// MARK: - TransferSyntax convenience for source-UID resolution

extension TransferSyntax {
    /// UIDs of the three uncompressed transfer syntaxes per DICOM PS3.5.
    /// Used to decide whether a parsed file's transfer syntax is
    /// encapsulated when only the UID string is available.
    fileprivate static let uncompressedUIDs: Set<String> = [
        TransferSyntax.implicitVRLittleEndian.uid,
        TransferSyntax.explicitVRLittleEndian.uid,
        TransferSyntax.explicitVRBigEndian.uid,
        TransferSyntax.deflatedExplicitVRLittleEndian.uid,
    ]

    /// Returns the canonical TransferSyntax instance for a given UID
    /// string, if it matches one of the standard transfer syntaxes that
    /// the dicom-compress codec map recognises. Looks up via the
    /// CompressionManager's codecMap entries so this stays in sync with
    /// supported codecs.
    fileprivate static func fromKnownUID(_ uid: String) -> TransferSyntax? {
        for entry in CompressionManager.codecMap where entry.encoding.transferSyntax.uid == uid {
            return entry.encoding.transferSyntax
        }
        return nil
    }
}
