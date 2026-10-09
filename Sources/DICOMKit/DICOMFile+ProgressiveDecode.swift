// NEMA-verified: 2026a, checked 2026-09-29 — the JPEG 2000 / HTJ2K family is named through DICOMCore TransferSyntax constants verified in the DICOMCore pass; resolution levels are JPEG 2000, not DICOM
import Foundation
import DICOMCore

/// Progressive frame decoding (WP-H, plan M5)
///
/// For JPEG 2000-family transfer syntaxes (including HTJ2K), emits coarse
/// reduced-resolution previews first — via J2KSwift's true partial-resolution
/// decode — then the exact full-fidelity frame. For every other syntax the
/// stream degrades gracefully to a single final update.
///
/// Contract (research-adoption instructions §12):
/// - every non-final update carries explicit refinement state (`isFinal ==
///   false`, its resolution level, and reduced dimensions);
/// - the final update is byte-identical to `pixelData(frame:)` — asserted in
///   `FrameAccessTests`;
/// - measurements, exports and AI inputs must use the final update only.
public struct ProgressiveFrameUpdate: Sendable {
    /// Resolution level of this update (0 = full resolution; each level up
    /// halves both dimensions).
    public let resolutionLevel: Int

    /// Whether this is the exact full-fidelity frame.
    public let isFinal: Bool

    /// The decoded samples. Coarse updates have reduced `descriptor.rows` /
    /// `descriptor.columns`; the final update matches the file's geometry.
    public let pixelData: PixelData
}

extension DICOMFile {

    /// Whether this file's transfer syntax supports coarse-first progressive
    /// decoding (JPEG 2000 family, including HTJ2K).
    public var supportsProgressiveDecode: Bool {
        guard let uid = transferSyntaxUID else { return false }
        return Self.j2kFamilyUIDs.contains(uid)
    }

    private static let j2kFamilyUIDs: Set<String> = [
        TransferSyntax.jpeg2000Lossless.uid,
        TransferSyntax.jpeg2000.uid,
        TransferSyntax.jpeg2000Part2Lossless.uid,
        TransferSyntax.jpeg2000Part2.uid,
        TransferSyntax.htj2kLossless.uid,
        TransferSyntax.htj2kRPCLLossless.uid,
        TransferSyntax.htj2kLossy.uid,
    ]

    /// Decodes one frame progressively: coarse resolution levels first, exact
    /// full-fidelity frame last
    ///
    /// - Parameters:
    ///   - frame: Zero-based frame index.
    ///   - coarseLevels: Reduced-resolution levels to emit before the final
    ///     frame, coarsest first (default `[2, 1]` — quarter then half
    ///     resolution). Levels the codestream cannot serve are skipped
    ///     silently; the final full decode always arrives.
    /// - Returns: A stream of `ProgressiveFrameUpdate`s ending with
    ///   `isFinal == true`, or throwing on unrecoverable failure.
    public func pixelDataProgressive(
        frame: Int,
        coarseLevels: [Int] = [2, 1]
    ) -> AsyncThrowingStream<ProgressiveFrameUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if canImport(J2KCore) && canImport(J2KCodec)
                    if self.supportsProgressiveDecode,
                       let encapsulated = self.dataSet.encapsulatedPixelData(),
                       let index = encapsulated.makeFrameIndex(
                           extendedOffsets: self.extendedOffsetTableValues()),
                       let frameBytes = encapsulated.frameData(at: frame, using: index) {
                        let descriptor = encapsulated.descriptor
                        let codec = J2KSwiftCodec()
                        for level in coarseLevels where level > 0 {
                            try Task.checkCancellation()
                            guard let (data, rows, columns) = try? await codec.decodeFrameAtResolution(
                                frameBytes, descriptor: descriptor, level: level) else {
                                continue // level unavailable — refine with the next
                            }
                            let reduced = PixelDataDescriptor(
                                rows: rows, columns: columns, numberOfFrames: 1,
                                bitsAllocated: descriptor.bitsAllocated,
                                bitsStored: descriptor.bitsStored,
                                highBit: descriptor.highBit,
                                isSigned: descriptor.isSigned,
                                samplesPerPixel: descriptor.samplesPerPixel,
                                photometricInterpretation: descriptor.photometricInterpretation,
                                planarConfiguration: descriptor.planarConfiguration)
                            continuation.yield(ProgressiveFrameUpdate(
                                resolutionLevel: level,
                                isFinal: false,
                                pixelData: PixelData(data: data, descriptor: reduced)))
                        }
                    }
                    #endif

                    // Final, exact frame — identical to pixelData(frame:).
                    try Task.checkCancellation()
                    let final = try self.pixelData(frame: frame)
                    continuation.yield(ProgressiveFrameUpdate(
                        resolutionLevel: 0, isFinal: true, pixelData: final))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
