import Foundation

/// RLE Lossless codec (pure Swift implementation)
///
/// Decodes Run-Length Encoded pixel data as specified in DICOM PS3.5 Annex G.
/// Reference: DICOM PS3.5 Annex G - RLE Transfer Syntax
///
/// NEMA-verified: 2026a, checked 2026-09-25 — byte-segment order (most significant byte of
/// the Composite Pixel Code first, G.2), the 64-byte header with up to 15 segment offsets
/// relative to the header (G.5), the decoder loop (G.3.2) and the encoder packet rules
/// (replicate 2–128, literal 1–128, -128 unused, G.3.1) match PS3.5 2026a. The encoder
/// used to let runs cross image rows, which G.3.1 forbids; fixed 2026-09-25.
public struct RLECodec: ImageCodec, ImageEncoder, Sendable {
    /// Supported RLE transfer syntax
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.rleLossless.uid  // 1.2.840.10008.1.2.5
    ]

    /// Supported RLE transfer syntax for encoding (RLE Lossless only)
    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.rleLossless.uid  // 1.2.840.10008.1.2.5
    ]

    public init() {}
    
    /// Decodes an RLE-compressed frame
    /// - Parameters:
    ///   - frameData: RLE compressed data
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Frame index (unused for single frame decode)
    /// - Returns: Uncompressed pixel data
    /// - Throws: DICOMError if decoding fails
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard frameData.count >= 64 else {
            throw DICOMError.parsingFailed("RLE data too short for header")
        }
        
        // Parse RLE header (64 bytes)
        // First 4 bytes: number of segments
        // Next 60 bytes: 15 segment offset values (4 bytes each)
        let numberOfSegments = Int(frameData.readUInt32LE(at: 0) ?? 0)
        
        guard numberOfSegments >= 1 && numberOfSegments <= 15 else {
            throw DICOMError.parsingFailed("Invalid RLE segment count: \(numberOfSegments)")
        }
        
        // Read segment offsets
        var segmentOffsets: [Int] = []
        for i in 0..<numberOfSegments {
            let offset = Int(frameData.readUInt32LE(at: 4 + i * 4) ?? 0)
            segmentOffsets.append(offset)
        }
        
        // Calculate expected output size
        let bytesPerSample = descriptor.bytesPerSample
        let samplesPerPixel = descriptor.samplesPerPixel
        let pixelsPerFrame = descriptor.pixelsPerFrame
        let expectedSegments = bytesPerSample * samplesPerPixel
        
        guard numberOfSegments == expectedSegments else {
            throw DICOMError.parsingFailed("Unexpected number of RLE segments: \(numberOfSegments), expected \(expectedSegments)")
        }
        
        // Decode each segment
        var decodedSegments: [Data] = []
        // Header offsets are frame-relative; `subdata(in:)` indexes absolutely.
        // See `decodeSegments` for the same rebasing and why it matters.
        let base = frameData.startIndex
        for i in 0..<numberOfSegments {
            let segmentStart = segmentOffsets[i]
            let segmentEnd: Int

            if i + 1 < numberOfSegments {
                segmentEnd = segmentOffsets[i + 1]
            } else {
                segmentEnd = frameData.count
            }

            guard segmentStart < segmentEnd && segmentEnd <= frameData.count else {
                throw DICOMError.parsingFailed("Invalid RLE segment boundaries")
            }

            let segmentData = frameData.subdata(in: (base + segmentStart)..<(base + segmentEnd))
            let decoded = try decodeRLESegment(segmentData, expectedLength: pixelsPerFrame)
            decodedSegments.append(decoded)
        }
        
        // Interleave segments to form output
        return interleaveSegments(decodedSegments, descriptor: descriptor)
    }

    /// Caller-owned decode: interleaves the decoded segments directly into
    /// `destination`, skipping the intermediate full-frame output buffer the
    /// `Data`-returning path allocates (WP-F, plan M3).
    public func decodeFrame(
        _ frameData: Data,
        descriptor: PixelDataDescriptor,
        frameIndex: Int,
        into destination: UnsafeMutableRawBufferPointer
    ) throws -> Int {
        let bytesPerFrame = descriptor.bytesPerFrame
        guard destination.count >= bytesPerFrame, let base = destination.baseAddress else {
            throw DICOMError.limitExceeded(
                "Caller-owned destination too small: \(destination.count) bytes for \(bytesPerFrame)-byte frame")
        }
        let segments = try decodeSegments(frameData, descriptor: descriptor)
        interleaveSegments(segments, descriptor: descriptor,
                           into: base.assumingMemoryBound(to: UInt8.self),
                           capacity: destination.count)
        return bytesPerFrame
    }

    /// Parses the RLE header and PackBits-decodes every segment (shared by the
    /// `Data`-returning and caller-owned paths).
    private func decodeSegments(_ frameData: Data, descriptor: PixelDataDescriptor) throws -> [Data] {
        guard frameData.count >= 64 else {
            throw DICOMError.parsingFailed("RLE data too short for header")
        }
        let numberOfSegments = Int(frameData.readUInt32LE(at: 0) ?? 0)
        guard numberOfSegments >= 1 && numberOfSegments <= 15 else {
            throw DICOMError.parsingFailed("Invalid RLE segment count: \(numberOfSegments)")
        }
        var segmentOffsets: [Int] = []
        for i in 0..<numberOfSegments {
            segmentOffsets.append(Int(frameData.readUInt32LE(at: 4 + i * 4) ?? 0))
        }
        let expectedSegments = descriptor.bytesPerSample * descriptor.samplesPerPixel
        guard numberOfSegments == expectedSegments else {
            throw DICOMError.parsingFailed(
                "Unexpected number of RLE segments: \(numberOfSegments), expected \(expectedSegments)")
        }
        var decodedSegments: [Data] = []
        // Segment offsets in the RLE header are relative to the start of the frame,
        // but `subdata(in:)` indexes absolutely. `frameData` may be a slice with a
        // non-zero `startIndex` (any caller that avoids a copy — which is the whole
        // direction of the byte-source work — produces one), so rebase before slicing.
        let base = frameData.startIndex
        for i in 0..<numberOfSegments {
            let segmentStart = segmentOffsets[i]
            let segmentEnd = i + 1 < numberOfSegments ? segmentOffsets[i + 1] : frameData.count
            guard segmentStart < segmentEnd && segmentEnd <= frameData.count else {
                throw DICOMError.parsingFailed("Invalid RLE segment boundaries")
            }
            let segmentData = frameData.subdata(in: (base + segmentStart)..<(base + segmentEnd))
            decodedSegments.append(try decodeRLESegment(segmentData, expectedLength: descriptor.pixelsPerFrame))
        }
        return decodedSegments
    }

    /// Pointer-destination variant of `interleaveSegments` (same traversal).
    private func interleaveSegments(
        _ segments: [Data],
        descriptor: PixelDataDescriptor,
        into output: UnsafeMutablePointer<UInt8>,
        capacity: Int
    ) {
        let bytesPerSample = descriptor.bytesPerSample
        let samplesPerPixel = descriptor.samplesPerPixel
        let pixelsPerFrame = descriptor.pixelsPerFrame

        for pixelIndex in 0..<pixelsPerFrame {
            for sampleIndex in 0..<samplesPerPixel {
                for byteIndex in 0..<bytesPerSample {
                    let segmentIndex = sampleIndex * bytesPerSample + (bytesPerSample - 1 - byteIndex)
                    guard segmentIndex < segments.count else { continue }
                    let segment = segments[segmentIndex]
                    guard pixelIndex < segment.count else { continue }

                    let outputOffset: Int
                    if descriptor.planarConfiguration == 0 || samplesPerPixel == 1 {
                        outputOffset = (pixelIndex * samplesPerPixel + sampleIndex) * bytesPerSample + byteIndex
                    } else {
                        let planeSize = pixelsPerFrame * bytesPerSample
                        outputOffset = sampleIndex * planeSize + pixelIndex * bytesPerSample + byteIndex
                    }
                    if outputOffset < capacity {
                        output[outputOffset] = segment[segment.startIndex + pixelIndex]
                    }
                }
            }
        }
    }

    // MARK: - Encoding

    /// Whether this encoder can produce RLE Lossless for the given pixel layout.
    ///
    /// RLE Lossless allows up to 15 segments (`bytesPerSample * samplesPerPixel`)
    /// and 8- or 16-bit samples. RLE is always lossless, so the quality setting
    /// is irrelevant. Reference: DICOM PS3.5 Annex G.
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else { return false }
        let segments = descriptor.bytesPerSample * descriptor.samplesPerPixel
        return segments >= 1 && segments <= 15
    }

    /// Encodes a single frame to RLE Lossless.
    ///
    /// The frame is split into one byte-plane segment per `(sample, byte)` — the
    /// exact inverse of `interleaveSegments` so encode∘decode is the identity —
    /// each segment is PackBits-encoded and padded to an even length, then a
    /// 64-byte RLE header (segment count + offsets, little-endian) is prepended.
    /// Reference: DICOM PS3.5 Annex G.
    /// - Throws: `DICOMError` if the layout needs more than 15 segments.
    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        let numberOfSegments = descriptor.bytesPerSample * descriptor.samplesPerPixel
        guard numberOfSegments >= 1 && numberOfSegments <= 15 else {
            throw DICOMError.parsingFailed("RLE cannot encode \(numberOfSegments) segments (must be 1...15)")
        }

        // De-interleave into byte planes, PackBits-encode each plane row by row
        // ("Each row of the image shall be encoded separately and not cross a row
        // boundary", PS3.5 G.3.1), and pad each segment to an even length.
        let planes = deinterleaveSegments(frameData, descriptor: descriptor, numberOfSegments: numberOfSegments)
        var encodedSegments: [Data] = []
        encodedSegments.reserveCapacity(numberOfSegments)
        for plane in planes {
            var encoded = encodeRLESegment(plane, rowLength: descriptor.columns)
            if encoded.count % 2 != 0 { encoded.append(0) }
            encodedSegments.append(encoded)
        }

        // 64-byte header: first UInt32 = segment count; next fifteen UInt32 = the
        // byte offset of each segment from the start of the frame (header itself).
        var frame = Data(count: 64)
        Self.writeUInt32LE(UInt32(numberOfSegments), into: &frame, at: 0)
        var offset = 64
        for (i, seg) in encodedSegments.enumerated() {
            Self.writeUInt32LE(UInt32(offset), into: &frame, at: 4 + i * 4)
            offset += seg.count
        }
        for seg in encodedSegments { frame.append(seg) }
        return frame
    }

    /// Splits a frame into one byte-plane per segment — the exact inverse of
    /// `interleaveSegments`. Segment order is most-significant byte first within
    /// each sample, matching the decoder's `segmentIndex` mapping.
    private func deinterleaveSegments(_ frameData: Data, descriptor: PixelDataDescriptor, numberOfSegments: Int) -> [[UInt8]] {
        let src = [UInt8](frameData)
        let bytesPerSample = descriptor.bytesPerSample
        let samplesPerPixel = descriptor.samplesPerPixel
        let pixelsPerFrame = descriptor.pixelsPerFrame
        let byPlane = descriptor.planarConfiguration != 0 && samplesPerPixel > 1
        let planeSize = pixelsPerFrame * bytesPerSample

        var segments = [[UInt8]](repeating: [UInt8](repeating: 0, count: pixelsPerFrame), count: numberOfSegments)

        for pixelIndex in 0..<pixelsPerFrame {
            for sampleIndex in 0..<samplesPerPixel {
                for byteIndex in 0..<bytesPerSample {
                    // High-order bytes occupy the lower segment indices.
                    let segmentIndex = sampleIndex * bytesPerSample + (bytesPerSample - 1 - byteIndex)
                    let inputOffset: Int
                    if byPlane {
                        inputOffset = sampleIndex * planeSize + pixelIndex * bytesPerSample + byteIndex
                    } else {
                        inputOffset = (pixelIndex * samplesPerPixel + sampleIndex) * bytesPerSample + byteIndex
                    }
                    segments[segmentIndex][pixelIndex] = inputOffset < src.count ? src[inputOffset] : 0
                }
            }
        }
        return segments
    }

    /// PackBits-encodes one segment — the inverse of `decodeRLESegment`.
    ///
    /// Emits replicate packets (`control = -(runLength - 1)`, then the byte) for
    /// runs of ≥2 identical bytes and literal packets (`control = length - 1`,
    /// then the bytes) otherwise, each capped at 128 bytes. Every image row is
    /// encoded on its own, so no packet crosses a row boundary (PS3.5 G.3.1).
    /// Reference: PS3.5 G.3.
    private func encodeRLESegment(_ src: [UInt8], rowLength: Int) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(src.count / 2 + 16)
        let rowLength = max(1, rowLength)
        var rowStart = 0
        while rowStart < src.count {
            let rowEnd = min(src.count, rowStart + rowLength)
            encodeRLERun(src, from: rowStart, to: rowEnd, into: &out)
            rowStart = rowEnd
        }
        return Data(out)
    }

    /// PackBits-encodes `src[start..<end]` (one image row) into `out`.
    private func encodeRLERun(_ src: [UInt8], from start: Int, to n: Int, into out: inout [UInt8]) {
        var i = start
        while i < n {
            // Measure a replicate run starting at i (capped at 128).
            var runLength = 1
            while i + runLength < n && src[i + runLength] == src[i] && runLength < 128 {
                runLength += 1
            }
            if runLength >= 2 {
                out.append(UInt8(bitPattern: Int8(-(runLength - 1))))
                out.append(src[i])
                i += runLength
            } else {
                // Literal run: copy until a ≥2 run begins, the end, or 128 bytes.
                let literalStart = i
                var literalLength = 0
                while i < n && literalLength < 128 {
                    if i + 1 < n && src[i] == src[i + 1] { break }
                    i += 1
                    literalLength += 1
                }
                out.append(UInt8(bitPattern: Int8(literalLength - 1)))
                out.append(contentsOf: src[literalStart..<(literalStart + literalLength)])
            }
        }
    }

    /// Writes a little-endian UInt32 into `data` at `offset`.
    private static func writeUInt32LE(_ value: UInt32, into data: inout Data, at offset: Int) {
        let base = data.startIndex + offset
        data[base]     = UInt8(value & 0xFF)
        data[base + 1] = UInt8((value >> 8) & 0xFF)
        data[base + 2] = UInt8((value >> 16) & 0xFF)
        data[base + 3] = UInt8((value >> 24) & 0xFF)
    }

    /// Decodes a single RLE segment
    ///
    /// RLE encoding uses a control byte followed by data:
    /// - If n >= 0 and n <= 127: copy the next n+1 bytes literally
    /// - If n >= -127 and n <= -1: repeat the next byte -n+1 times
    /// - If n == -128: no operation (skip)
    ///
    /// Reference: PS3.5 Annex G.3
    private func decodeRLESegment(_ data: Data, expectedLength: Int) throws -> Data {
        var output = Data()
        output.reserveCapacity(expectedLength)

        var offset = 0

        // Strict PS3.5 Annex G decoding: the segment must produce exactly
        // `expectedLength` bytes. A run that overshoots, a segment that ends early,
        // or more than one trailing byte (the G.3.2 even-length pad) is an error;
        // output is never truncated or zero-filled to hide a malformed segment.
        while output.count < expectedLength {
            guard offset < data.count else {
                throw DICOMError.parsingFailed(
                    "RLE segment ended after \(output.count) of \(expectedLength) bytes")
            }
            let controlByte = Int8(bitPattern: data[offset])
            offset += 1

            if controlByte == -128 {
                // No operation - skip
                continue
            } else if controlByte >= 0 {
                // Literal run: copy next n+1 bytes
                let count = Int(controlByte) + 1
                guard offset + count <= data.count else {
                    throw DICOMError.parsingFailed("RLE literal run exceeds data bounds")
                }
                guard output.count + count <= expectedLength else {
                    throw DICOMError.parsingFailed(
                        "RLE literal run exceeds the declared segment length \(expectedLength)")
                }
                output.append(data[offset..<(offset + count)])
                offset += count
            } else {
                // Repeat run: repeat next byte -n+1 times
                let count = Int(-controlByte) + 1
                guard offset < data.count else {
                    throw DICOMError.parsingFailed("RLE repeat run missing byte value")
                }
                guard output.count + count <= expectedLength else {
                    throw DICOMError.parsingFailed(
                        "RLE repeat run exceeds the declared segment length \(expectedLength)")
                }
                output.append(contentsOf: repeatElement(data[offset], count: count))
                offset += 1
            }
        }

        let trailing = data.count - offset
        guard trailing <= 1 else {
            throw DICOMError.parsingFailed(
                "RLE segment carries \(trailing) bytes beyond the declared length \(expectedLength)")
        }

        return output
    }

    /// Interleaves decoded segments into the final pixel data
    ///
    /// For multi-byte samples, high-order bytes come first in separate segments.
    /// For multi-sample pixels (e.g., RGB), each sample component is in a separate segment.
    ///
    /// Reference: PS3.5 Annex G.2
    private func interleaveSegments(_ segments: [Data], descriptor: PixelDataDescriptor) -> Data {
        let bytesPerSample = descriptor.bytesPerSample
        let samplesPerPixel = descriptor.samplesPerPixel
        let pixelsPerFrame = descriptor.pixelsPerFrame
        let bytesPerFrame = descriptor.bytesPerFrame
        
        var output = Data(count: bytesPerFrame)
        
        for pixelIndex in 0..<pixelsPerFrame {
            for sampleIndex in 0..<samplesPerPixel {
                for byteIndex in 0..<bytesPerSample {
                    // Segment index: high-order bytes first within each sample
                    let segmentIndex = sampleIndex * bytesPerSample + (bytesPerSample - 1 - byteIndex)
                    
                    guard segmentIndex < segments.count else {
                        continue
                    }
                    
                    let segment = segments[segmentIndex]
                    guard pixelIndex < segment.count else {
                        continue
                    }
                    
                    // Output offset
                    let outputOffset: Int
                    if descriptor.planarConfiguration == 0 || samplesPerPixel == 1 {
                        // Color-by-pixel or monochrome
                        outputOffset = (pixelIndex * samplesPerPixel + sampleIndex) * bytesPerSample + byteIndex
                    } else {
                        // Color-by-plane
                        let planeSize = pixelsPerFrame * bytesPerSample
                        outputOffset = sampleIndex * planeSize + pixelIndex * bytesPerSample + byteIndex
                    }
                    
                    if outputOffset < output.count {
                        output[outputOffset] = segment[pixelIndex]
                    }
                }
            }
        }
        
        return output
    }
}
