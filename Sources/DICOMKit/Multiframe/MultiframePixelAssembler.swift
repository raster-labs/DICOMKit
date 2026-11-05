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
            if !element.isEncapsulated {
                guard !element.valueData.isEmpty else { throw MultiframePixelError.missingPixelData }
                guard TransferSyntax.from(uid: tsUID)?.isEncapsulated != true else {
                    throw MultiframePixelError.frameExtractionFailed(frame)
                }
                let bytes = try storedNativeFrame(frame, in: element.valueData, descriptor: descriptor)
                return FramePixelPayload(storage: .native(bytes), transferSyntaxUID: tsUID, descriptor: single)
            }
            guard TransferSyntax.from(uid: tsUID)?.isEncapsulated != false else {
                throw MultiframePixelError.frameExtractionFailed(frame)
            }
            guard let encapsulated = file.dataSet.encapsulatedPixelData() else {
                throw MultiframePixelError.missingPixelData
            }
            guard let index = encapsulated.makeFrameIndex(
                extendedOffsetTableData: file.dataSet[.extendedOffsetTable]?.valueData,
                extendedOffsetTableLengthsData: file.dataSet[.extendedOffsetTableLengths]?.valueData
            ),
                  let codestream = encapsulated.frameData(at: frame, using: index,
                      maximumBytes: PixelDecodeLimits.default.maximumEncodedBytes) else {
                throw MultiframePixelError.frameExtractionFailed(frame)
            }
            return FramePixelPayload(storage: .encapsulated(codestream), transferSyntaxUID: tsUID, descriptor: single)
        }
    }

    /// Preserves stored byte order. Packed frames can be sliced exactly only when
    /// their bit length ends on a byte boundary.
    private static func storedNativeFrame(_ frame: Int, in data: Data, descriptor: PixelDataDescriptor) throws -> Data {
        guard descriptor.rows > 0, descriptor.columns > 0, descriptor.samplesPerPixel > 0,
              descriptor.bitsAllocated > 0 else { throw MultiframePixelError.frameExtractionFailed(frame) }
        let (pixels, pixelOverflow) = descriptor.rows.multipliedReportingOverflow(by: descriptor.columns)
        let (samples, sampleOverflow) = pixels.multipliedReportingOverflow(by: descriptor.samplesPerPixel)
        guard !pixelOverflow, !sampleOverflow else { throw MultiframePixelError.frameExtractionFailed(frame) }

        let size: Int
        if descriptor.bitsAllocated < 8 {
            let (bits, overflow) = samples.multipliedReportingOverflow(by: descriptor.bitsAllocated)
            guard !overflow else { throw MultiframePixelError.frameExtractionFailed(frame) }
            guard bits.isMultiple(of: 8) else { throw MultiframePixelError.unalignedSubBytePixels(bitsPerFrame: bits) }
            size = bits / 8
        } else {
            let (bytes, overflow) = samples.multipliedReportingOverflow(by: descriptor.bytesPerSample)
            guard !overflow else { throw MultiframePixelError.frameExtractionFailed(frame) }
            size = bytes
        }
        let (offset, overflow) = frame.multipliedReportingOverflow(by: size)
        guard !overflow, size <= data.count, offset <= data.count - size else {
            throw MultiframePixelError.frameExtractionFailed(frame)
        }
        let start = data.startIndex + offset
        return Data(data[start..<(start + size)])
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
            // A single fragment starts at offset zero irrespective of its length.
            return DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
                               encapsulatedFragments: [codestream], encapsulatedOffsetTable: [0])
        }
    }

    /// Concatenates payloads into one multi-frame Pixel Data element. Every payload
    /// must share the transfer syntax and (for native data) the frame byte size.
    public static func assemble(_ payloads: [FramePixelPayload]) throws -> (element: DataElement, transferSyntaxUID: String) {
        try assemble(payloads, maximumBytes: Int(UInt32.max))
    }

    /// Native output uses a defined Value Length; encapsulated output uses the
    /// finite serialized-element bound of the canonical offset builder.
    static func assemble(_ payloads: [FramePixelPayload], maximumBytes: Int) throws
        -> (element: DataElement, transferSyntaxUID: String) {
        guard let first = payloads.first else {
            throw MultiframePixelError.missingPixelData
        }
        for payload in payloads.dropFirst() where payload.transferSyntaxUID != first.transferSyntaxUID {
            throw MultiframePixelError.mixedTransferSyntaxes(expected: first.transferSyntaxUID,
                                                             found: payload.transferSyntaxUID)
        }

        if first.isEncapsulated {
            for payload in payloads {
                guard case .encapsulated(let codestream) = payload.storage else {
                    throw MultiframePixelError.mixedTransferSyntaxes(expected: first.transferSyntaxUID,
                                                                     found: payload.transferSyntaxUID)
                }
                guard codestream.count <= PixelDecodeLimits.default.maximumEncodedBytes else {
                    throw DICOMError.limitExceeded("Compressed frame exceeds the assembly byte limit")
                }
            }
            let checked = try EncapsulatedPixelData.buildCheckedBasicOffsetTable(
                lengths: payloads.lazy.map(\.byteCount), includeSingleFrameOffset: true, maxSerializedBytes: maximumBytes)
            var fragments: [Data] = []
            fragments.reserveCapacity(payloads.count)
            for payload in payloads {
                if case .encapsulated(let codestream) = payload.storage { fragments.append(codestream) }
            }
            let element = DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
                                      encapsulatedFragments: fragments, encapsulatedOffsetTable: checked.offsets)
            return (element, first.transferSyntaxUID)
        }

        let expected = first.byteCount
        for payload in payloads {
            guard case .native(let bytes) = payload.storage else {
                throw MultiframePixelError.mixedTransferSyntaxes(expected: first.transferSyntaxUID,
                                                                 found: payload.transferSyntaxUID)
            }
            guard bytes.count == expected else {
                throw MultiframePixelError.mixedFrameSize(expected: expected, found: bytes.count)
            }
        }
        let (logical, overflow) = expected.multipliedReportingOverflow(by: payloads.count)
        let (padded, padOverflow) = logical.addingReportingOverflow(logical % 2)
        guard !overflow, !padOverflow, logical > 0, padded <= maximumBytes, padded < Int(UInt32.max) else {
            throw DICOMError.limitExceeded("Assembled native Pixel Data exceeds its Value Length or byte limit")
        }
        var combined = Data(capacity: padded)
        for payload in payloads {
            if case .native(let bytes) = payload.storage { combined.append(bytes) }
        }
        if padded != logical { combined.append(0) }
        let element = DataElement(tag: .pixelData, vr: first.descriptor.bitsAllocated > 8 ? .OW : .OB,
                                  length: UInt32(padded), valueData: combined)
        return (element, first.transferSyntaxUID)
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
        // Reassembled codestreams carry a newly built BOT, and native output
        // has no fragment table. Neither representation uses source EOT entries.
        dataSet[.extendedOffsetTable] = nil
        dataSet[.extendedOffsetTableLengths] = nil
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

    static func singleFrame(_ d: PixelDataDescriptor) -> PixelDataDescriptor {
        PixelDataDescriptor(rows: d.rows, columns: d.columns, numberOfFrames: 1,
                            bitsAllocated: d.bitsAllocated, bitsStored: d.bitsStored,
                            highBit: d.highBit, isSigned: d.isSigned,
                            samplesPerPixel: d.samplesPerPixel,
                            photometricInterpretation: d.photometricInterpretation,
                            planarConfiguration: d.planarConfiguration)
    }
}
