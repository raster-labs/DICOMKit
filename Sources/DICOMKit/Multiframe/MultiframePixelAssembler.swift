// NEMA-verified: 2026a, checked 2026-09-29 — frame assembly per PS3.5 2026a 8.1.1
import Foundation
import DICOMCore

/// How split/merge treat the pixel bytes of compressed (encapsulated) sources.
public enum MultiframePixelHandling: String, Sendable, CaseIterable {
    /// Keep the transfer syntax: native frames are sliced, encapsulated frames are
    /// carried over as their own fragments (with a rebuilt Basic Offset Table).
    case preserve
    /// Decode every frame to native samples and write Explicit VR Little Endian.
    case decode
}

/// One frame's pixel bytes together with the transfer syntax they are valid in.
public struct FramePixelPayload: Sendable {
    public enum Storage: Sendable {
        case native(Data)
        /// All fragments that make up the frame's codestream (already reassembled
        /// into one fragment per frame by the assembler).
        case encapsulated(Data)
    }

    public let storage: Storage
    public let transferSyntaxUID: String
    /// Single-frame descriptor matching the bytes (photometric interpretation is
    /// corrected for codecs that change it on decode).
    public let descriptor: PixelDataDescriptor

    public init(storage: Storage, transferSyntaxUID: String, descriptor: PixelDataDescriptor) {
        self.storage = storage
        self.transferSyntaxUID = transferSyntaxUID
        self.descriptor = descriptor
    }

    public var isEncapsulated: Bool {
        if case .encapsulated = storage { return true }
        return false
    }

    public var byteCount: Int {
        switch storage {
        case .native(let d), .encapsulated(let d): return d.count
        }
    }
}

public enum MultiframePixelError: Error, CustomStringConvertible {
    case missingPixelData
    case frameOutOfRange(Int)
    case frameExtractionFailed(Int)
    /// Sub-byte (BitsAllocated < 8) frames whose bit length is not a whole
    /// number of bytes: frames cannot be sliced or concatenated without
    /// bit-shifting, which native Pixel Data cannot represent per frame.
    case unalignedSubBytePixels(bitsPerFrame: Int)
    case decodeFailed(frame: Int, reason: String)
    case mixedTransferSyntaxes(expected: String, found: String)
    case mixedFrameSize(expected: Int, found: Int)
    case missingTransferSyntax

    public var description: String {
        switch self {
        case .missingPixelData: return "Missing pixel data"
        case .frameOutOfRange(let f): return "Frame \(f) is out of range"
        case .frameExtractionFailed(let f): return "Failed to extract frame \(f)"
        case .decodeFailed(let f, let reason): return "Failed to decode frame \(f): \(reason)"
        case .mixedTransferSyntaxes(let e, let f):
            return "Inconsistent Transfer Syntax: expected \(e), found \(f) (use --pixel-handling decode to transcode)"
        case .mixedFrameSize(let e, let f):
            return "Inconsistent pixel data size: expected \(e) bytes, found \(f) bytes"
        case .missingTransferSyntax: return "Missing Transfer Syntax UID"
        case .unalignedSubBytePixels(let bits):
            return "Single-bit frames of \(bits) bits do not end on a byte boundary and cannot be merged"
        }
    }
}

/// Per-frame pixel extraction and multi-frame assembly that is correct for both
/// native and encapsulated transfer syntaxes. Shared by `FrameSplitter`,
/// `FrameMerger` and the concatenation code so no tool concatenates raw
/// fragments or mislabels decoded bytes again.
public enum MultiframePixelAssembler {

    public static let explicitVRLittleEndian = TransferSyntax.explicitVRLittleEndian.uid

    // MARK: - Extraction

    /// Extracts one frame from `file` according to `handling`.
    public static func extractFrame(
        from file: DICOMFile,
        frame: Int,
        handling: MultiframePixelHandling
    ) throws -> FramePixelPayload {
        let descriptor = try file.dataSet.tryPixelDataDescriptor()
        guard frame >= 0, frame < descriptor.numberOfFrames else {
            throw MultiframePixelError.frameOutOfRange(frame)
        }
        guard let element = file.dataSet[.pixelData] else {
            throw MultiframePixelError.missingPixelData
        }
        let tsUID = file.transferSyntaxUID.map(MultiframeSOPClassMap.normalize) ?? explicitVRLittleEndian
        let single = singleFrame(descriptor)

        switch handling {
        case .decode:
            let decoded: PixelData
            do {
                decoded = try file.pixelData(frame: frame)
            } catch {
                throw MultiframePixelError.decodeFailed(frame: frame, reason: "\(error)")
            }
            return FramePixelPayload(storage: .native(decoded.data),
                                     transferSyntaxUID: explicitVRLittleEndian,
                                     descriptor: decoded.descriptor)

        case .preserve:
            if !element.valueData.isEmpty {
                // Native: slice the frame's raw bytes; keep the data set's byte order
                // because the transfer syntax is preserved.
                if descriptor.bitsAllocated < 8 {
                    // Bit-packed (PS3.5 8.1.1): frames are packed contiguously.
                    // Slicing (and later concatenating) per frame is only exact
                    // when each frame ends on a byte boundary.
                    // Continuous packing across samples (the standard only defines
                    // sub-byte pixels for Samples per Pixel 1); the byte-boundary
                    // guard below rejects anything this math can't slice exactly.
                    let bitsPerFrame = descriptor.pixelsPerFrame * descriptor.samplesPerPixel * descriptor.bitsAllocated
                    guard bitsPerFrame % 8 == 0 else {
                        throw MultiframePixelError.unalignedSubBytePixels(bitsPerFrame: bitsPerFrame)
                    }
                    let packedBytesPerFrame = bitsPerFrame / 8
                    let start = element.valueData.startIndex + frame * packedBytesPerFrame
                    let end = start + packedBytesPerFrame
                    guard end <= element.valueData.endIndex else {
                        throw MultiframePixelError.frameExtractionFailed(frame)
                    }
                    return FramePixelPayload(storage: .native(Data(element.valueData[start..<end])),
                                             transferSyntaxUID: tsUID, descriptor: single)
                }
                let bytesPerFrame = descriptor.bytesPerFrame
                let start = element.valueData.startIndex + frame * bytesPerFrame
                let end = start + bytesPerFrame
                guard bytesPerFrame > 0, end <= element.valueData.endIndex else {
                    throw MultiframePixelError.frameExtractionFailed(frame)
                }
                return FramePixelPayload(storage: .native(Data(element.valueData[start..<end])),
                                         transferSyntaxUID: tsUID, descriptor: single)
            }
            guard let encapsulated = file.dataSet.encapsulatedPixelData() else {
                throw MultiframePixelError.missingPixelData
            }
            guard let index = encapsulated.makeFrameIndex(extendedOffsets: file.extendedOffsetTableValues()),
                  let codestream = encapsulated.frameData(at: frame, using: index) else {
                throw MultiframePixelError.frameExtractionFailed(frame)
            }
            return FramePixelPayload(storage: .encapsulated(codestream), transferSyntaxUID: tsUID, descriptor: single)
        }
    }

    /// Loads the (only) frame of a single-frame input, or frame 0 of a multi-frame one.
    public static func loadFrame(
        from file: DICOMFile,
        handling: MultiframePixelHandling
    ) throws -> FramePixelPayload {
        try extractFrame(from: file, frame: 0, handling: handling)
    }

    // MARK: - Element construction

    /// The Pixel Data element for a single payload.
    public static func pixelDataElement(for payload: FramePixelPayload) -> DataElement {
        switch payload.storage {
        case .native(let bytes):
            return nativeElement(bytes, bitsAllocated: payload.descriptor.bitsAllocated)
        case .encapsulated(let codestream):
            return encapsulatedElement(fragments: [codestream])
        }
    }

    /// Concatenates payloads into one multi-frame Pixel Data element. Every payload
    /// must share the transfer syntax and (for native data) the frame byte size.
    public static func assemble(_ payloads: [FramePixelPayload]) throws -> (element: DataElement, transferSyntaxUID: String) {
        guard let first = payloads.first else {
            throw MultiframePixelError.missingPixelData
        }
        for payload in payloads.dropFirst() where payload.transferSyntaxUID != first.transferSyntaxUID {
            throw MultiframePixelError.mixedTransferSyntaxes(expected: first.transferSyntaxUID,
                                                             found: payload.transferSyntaxUID)
        }

        if first.isEncapsulated {
            var fragments: [Data] = []
            fragments.reserveCapacity(payloads.count)
            for payload in payloads {
                guard case .encapsulated(let codestream) = payload.storage else {
                    throw MultiframePixelError.mixedTransferSyntaxes(expected: first.transferSyntaxUID,
                                                                     found: payload.transferSyntaxUID)
                }
                fragments.append(codestream)
            }
            return (encapsulatedElement(fragments: fragments), first.transferSyntaxUID)
        }

        var combined = Data()
        combined.reserveCapacity(payloads.reduce(0) { $0 + $1.byteCount })
        let expected = first.byteCount
        for payload in payloads {
            guard case .native(let bytes) = payload.storage else {
                throw MultiframePixelError.mixedTransferSyntaxes(expected: first.transferSyntaxUID,
                                                                 found: payload.transferSyntaxUID)
            }
            guard bytes.count == expected else {
                throw MultiframePixelError.mixedFrameSize(expected: expected, found: bytes.count)
            }
            combined.append(bytes)
        }
        return (nativeElement(combined, bitsAllocated: first.descriptor.bitsAllocated), first.transferSyntaxUID)
    }

    /// Writes the Image Pixel attributes that may change when frames are decoded
    /// (photometric interpretation, planar configuration) and the transfer syntax
    /// into the data set / file meta.
    public static func applyPixelDescription(
        _ payload: FramePixelPayload,
        to dataSet: inout DataSet,
        fileMeta: inout DataSet
    ) {
        dataSet.setString(payload.descriptor.photometricInterpretation.rawValue,
                          for: .photometricInterpretation, vr: .CS)
        if payload.descriptor.samplesPerPixel > 1 {
            dataSet.setUInt16(UInt16(payload.descriptor.planarConfiguration), for: .planarConfiguration)
        }
        fileMeta.setString(payload.transferSyntaxUID, for: .transferSyntaxUID, vr: .UI)
        if !payload.isEncapsulated {
            dataSet[.extendedOffsetTable] = nil
            dataSet[.extendedOffsetTableLengths] = nil
        }
    }

    // MARK: - Helpers

    static func nativeElement(_ bytes: Data, bitsAllocated: Int) -> DataElement {
        var padded = bytes
        if padded.count % 2 != 0 { padded.append(0x00) }
        return DataElement(tag: .pixelData,
                           vr: bitsAllocated > 8 ? .OW : .OB,
                           length: UInt32(padded.count),
                           valueData: padded)
    }

    /// Encapsulated element with one fragment per frame and a Basic Offset Table
    /// pointing at each fragment's Item header (PS3.5 A.4).
    static func encapsulatedElement(fragments: [Data]) -> DataElement {
        var offsets: [UInt32] = []
        offsets.reserveCapacity(fragments.count)
        var running: UInt32 = 0
        for fragment in fragments {
            offsets.append(running)
            let padded = fragment.count % 2 == 0 ? fragment.count : fragment.count + 1
            running += 8 + UInt32(padded)
        }
        return DataElement(tag: .pixelData,
                           vr: .OB,
                           length: 0xFFFFFFFF,
                           valueData: Data(),
                           encapsulatedFragments: fragments,
                           encapsulatedOffsetTable: offsets)
    }

    static func singleFrame(_ d: PixelDataDescriptor) -> PixelDataDescriptor {
        PixelDataDescriptor(rows: d.rows, columns: d.columns, numberOfFrames: 1,
                            bitsAllocated: d.bitsAllocated, bitsStored: d.bitsStored,
                            highBit: d.highBit, isSigned: d.isSigned,
                            samplesPerPixel: d.samplesPerPixel,
                            photometricInterpretation: d.photometricInterpretation,
                            planarConfiguration: d.planarConfiguration)
    }
}
