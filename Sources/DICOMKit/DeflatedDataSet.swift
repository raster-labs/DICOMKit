// NEMA-verified: 2026a, checked 2026-09-29 — PS3.5 2026a A.5: the data set is one raw DEFLATE stream and the File Meta Information is not deflated; strict end-of-stream handling recorded
import Foundation
#if canImport(Compression)
import Compression
#endif

/// Strict RFC 1951 (raw DEFLATE) inflation for the Data Set of a Deflated Explicit
/// VR Little Endian file (PS3.5 A.5; the File Meta Information is never deflated).
///
/// The stream must be complete (end-of-stream reached), must end exactly at the
/// last input byte, and must not inflate beyond `maximumOutputByteCount`. Each of
/// those conditions is reported as its own failure instead of returning a
/// truncated, padded or oversized buffer. A zlib-wrapped stream (RFC 1950) is not a
/// PS3.5 A.5 data set and fails as corrupt.
public enum DeflatedDataSet {
    public enum Failure: Error, Equatable, Sendable {
        /// The platform provides no DEFLATE implementation.
        case unavailable
        /// Input ended before the DEFLATE end-of-stream marker.
        case truncated
        /// The stream is not valid raw DEFLATE.
        case corrupt
        /// Bytes follow the end-of-stream marker.
        case trailingBytes(Int)
        /// Inflating would exceed the caller's limit.
        case outputLimitExceeded(limit: Int)
    }

    /// Inflates a raw DEFLATE stream strictly.
    /// - Parameters:
    ///   - data: The compressed Data Set bytes (everything after the File Meta Information).
    ///   - maximumOutputByteCount: Hard limit on the inflated size; exceeding it throws
    ///     `Failure.outputLimitExceeded` before more output is produced.
    public static func inflate(_ data: Data, maximumOutputByteCount: Int) throws -> Data {
        guard maximumOutputByteCount > 0 else { throw Failure.outputLimitExceeded(limit: maximumOutputByteCount) }
        guard !data.isEmpty else { throw Failure.truncated }
        #if canImport(Compression)
        return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Data in
            guard let base = input.baseAddress?.assumingMemoryBound(to: UInt8.self) else { throw Failure.truncated }
            // Phase 1: chunked inflation. The platform decoder buffers input well past
            // the end-of-stream marker, so this pass can only say which input chunk
            // holds the marker (the last chunk fed when it reports END).
            var output = Data()
            var endChunkStart = 0
            var exactEnd: Int? = nil
            try drive(base: base, count: input.count, chunkSize: inputChunkSize, byteWiseFrom: nil) { produced, chunkStart, fedEnd, residual, ended in
                if produced.count > 0 {
                    guard output.count + produced.count <= maximumOutputByteCount else {
                        throw Failure.outputLimitExceeded(limit: maximumOutputByteCount)
                    }
                    output.append(produced)
                }
                if ended {
                    endChunkStart = chunkStart
                    if residual > 0 { exactEnd = fedEnd - residual }
                }
            }
            if exactEnd == nil {
                // Phase 2: replay the chunks before the marker's chunk in bulk, then feed
                // that chunk one byte at a time; the decoder reports END on the exact byte.
                try drive(base: base, count: input.count, chunkSize: inputChunkSize, byteWiseFrom: endChunkStart) { _, _, fedEnd, residual, ended in
                    if ended { exactEnd = fedEnd - residual }
                }
            }
            guard let end = exactEnd else { throw Failure.corrupt }
            let trailing = input.count - end
            guard trailing == 0 else { throw Failure.trailingBytes(trailing) }
            return output
        }
        #else
        throw Failure.unavailable
        #endif
    }

    #if canImport(Compression)
    private static let inputChunkSize = 4096
    private static let outputChunkSize = 64 * 1024

    /// Feeds `count` input bytes to a fresh decoder in chunks of `chunkSize` (one byte at a
    /// time from `byteWiseFrom` on) and reports each step to `observe` as
    /// (produced bytes, start offset of the chunk being fed, offset after it, residual
    /// unconsumed bytes of that chunk, whether END was reported). Throws `truncated` or
    /// `corrupt` on the decoder's behalf.
    private static func drive(
        base: UnsafePointer<UInt8>, count: Int, chunkSize: Int, byteWiseFrom: Int?,
        observe: (Data, Int, Int, Int, Bool) throws -> Void
    ) throws {
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 1), dst_size: 0,
            src_ptr: base, src_size: 0, state: nil)
        stream.dst_ptr.deallocate()
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.unavailable
        }
        defer { compression_stream_destroy(&stream) }
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: outputChunkSize)
        defer { chunk.deallocate() }

        var fed = 0
        while fed < count {
            let chunkStart = fed
            let length: Int
            if let byteWiseFrom, fed >= byteWiseFrom {
                length = 1
            } else if let byteWiseFrom {
                length = min(chunkSize, byteWiseFrom - fed)
            } else {
                length = min(chunkSize, count - fed)
            }
            stream.src_ptr = base + fed
            stream.src_size = length
            fed += length
            let isLast = fed == count
            while true {
                stream.dst_ptr = chunk
                stream.dst_size = outputChunkSize
                let status = compression_stream_process(&stream, isLast ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                let produced = outputChunkSize - stream.dst_size
                let ended = status == COMPRESSION_STATUS_END
                if produced > 0 || ended {
                    try observe(Data(bytes: chunk, count: produced), chunkStart, fed, stream.src_size, ended)
                }
                if ended { return }
                guard status == COMPRESSION_STATUS_OK else { throw Failure.corrupt }
                // Output chunk full: keep draining before feeding more input.
                if stream.dst_size == 0 { continue }
                // Wants more input with nothing left to give: the stream is truncated.
                if isLast && stream.src_size == 0 { throw Failure.truncated }
                break
            }
        }
        throw Failure.truncated
    }
    #endif
}
