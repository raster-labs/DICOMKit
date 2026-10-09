// NEMA-verified: 2026a, checked 2026-09-25 — Planar Configuration 0/1 sample order matches PS3.3 2026a C.7.6.3.1.3 (0 = colour-by-pixel, 1 = colour-by-plane); no other standard data. C1 classification confirmed.

import Foundation

// Helpers for bridging DICOM frame buffers to/from the channel-interleaved,
// little-endian pixel layout that the JLISwift / JXLSwift codecs expect.
//
// A DICOM frame for a multi-component image may be stored either
// sample-interleaved (Planar Configuration 0: R,G,B,R,G,B,…) or planar
// (Planar Configuration 1: R…R,G…G,B…B). Both JLISwift's `JLIImage.data` and
// JXLSwift's `ImageFrame.data` are channel-interleaved `[UInt8]`, row-major,
// with 16-bit samples little-endian — which matches DICOM's little-endian
// sample storage, so only the planar↔interleaved reshuffle is ever needed.

/// DICOM frame (per `descriptor`) → channel-interleaved, row-major bytes.
/// A single-component frame, or one already stored interleaved, passes through
/// unchanged.
func interleavedFrameBytes(from frame: Data, descriptor: PixelDataDescriptor) -> [UInt8] {
    let spp = descriptor.samplesPerPixel
    if spp == 1 || descriptor.planarConfiguration == 0 {
        return [UInt8](frame)
    }
    let bps = descriptor.bitsAllocated <= 8 ? 1 : 2
    let pixels = descriptor.rows * descriptor.columns
    let src = [UInt8](frame)
    var out = [UInt8](repeating: 0, count: pixels * spp * bps)
    for p in 0..<pixels {
        for c in 0..<spp {
            let srcByte = (c * pixels + p) * bps
            let dstByte = (p * spp + c) * bps
            for b in 0..<bps where srcByte + b < src.count {
                out[dstByte + b] = src[srcByte + b]
            }
        }
    }
    return out
}

/// Channel-interleaved, row-major bytes → DICOM frame (per `descriptor`).
/// Inverse of `interleavedFrameBytes`; reshuffles to planar when the descriptor
/// declares Planar Configuration 1.
func dicomFrameBytes(fromInterleaved data: [UInt8], descriptor: PixelDataDescriptor) -> Data {
    let spp = descriptor.samplesPerPixel
    if spp == 1 || descriptor.planarConfiguration == 0 {
        return Data(data)
    }
    let bps = descriptor.bitsAllocated <= 8 ? 1 : 2
    let pixels = descriptor.rows * descriptor.columns
    var out = [UInt8](repeating: 0, count: pixels * spp * bps)
    for p in 0..<pixels {
        for c in 0..<spp {
            let srcByte = (p * spp + c) * bps
            let dstByte = (c * pixels + p) * bps
            for b in 0..<bps where srcByte + b < data.count {
                out[dstByte + b] = data[srcByte + b]
            }
        }
    }
    return Data(out)
}
