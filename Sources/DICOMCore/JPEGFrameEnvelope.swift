import Foundation

/// Marker-only admission for the finite JPEG/JPEG-LS processes supported here.
/// No image-sized buffers are allocated. PS3.5 2026a A.4.1/A.4.3 require an independently
/// encoded frame; A.4 permits padding of its final fragment. Marker grammar: ITU-T T.81 B / T.87 C.
struct JPEGFrameEnvelope {
    let process: UInt8
    let width: Int
    let height: Int
    let precision: Int
    let components: [UInt8]
    let sampling: [UInt8]
    let scanParameters: [(first: Int, last: Int, approximation: Int)]
    let jfif: Bool
    let adobeTransform: UInt8?

    static func parse(_ input: Data, jpegLS: Bool) throws -> Self {
        try input.withUnsafeBytes { try parse($0, jpegLS: jpegLS) }
    }

    static func parse(_ data: UnsafeRawBufferPointer, jpegLS: Bool) throws -> Self {
        func fail(_ reason: String) -> DICOMError { .parsingFailed("JPEG frame envelope: \(reason)") }
        guard data.count >= 4, data[0] == 0xff, data[1] == 0xd8 else { throw fail("missing SOI") }
        func word(_ i: Int) -> Int { Int(data[i]) << 8 | Int(data[i + 1]) }
        var p = 2
        var entropy = false
        var process: UInt8?
        var width = 0, height = 0, precision = 0
        var components: [UInt8] = [], sampling: [UInt8] = []
        var scans: [(first: Int, last: Int, approximation: Int)] = []
        var scanned = Set<UInt8>()
        var jfif = false
        var adobe: UInt8?
        var markers = 0
        while p < data.count {
            try Task.checkCancellation()
            if entropy {
                var cancellationOffset = p
                while p < data.count {
                    if p >= cancellationOffset {
                        try Task.checkCancellation()
                        cancellationOffset = p + min(0x10000, data.count - p)
                    }
                    if data[p] != 0xff { p += 1; continue }
                    guard p + 1 < data.count else { throw fail("truncated entropy marker") }
                    let next = data[p + 1]
                    if jpegLS ? next < 0x80 : next == 0 { p += 2; continue }
                    if (0xd0...0xd7).contains(next) { p += 2; continue }
                    break
                }
                entropy = false
            }
            guard p + 1 < data.count, data[p] == 0xff else { throw fail("missing marker/EOI") }
            var markerCancellationOffset = p
            while p < data.count, data[p] == 0xff {
                if p >= markerCancellationOffset {
                    try Task.checkCancellation()
                    markerCancellationOffset = p + min(0x10000, data.count - p)
                }
                p += 1
            }
            guard p < data.count else { throw fail("truncated marker") }
            let marker = data[p]; p += 1
            markers += 1
            guard markers <= 4096 else { throw DICOMError.limitExceeded("Too many JPEG marker segments") }
            if marker == 0xd9 {
                guard let process, !scans.isEmpty, scanned == Set(components) else {
                    throw fail("incomplete frame/scans")
                }
                guard p == data.count || (p % 2 == 1 && p + 1 == data.count && data[p] == 0) else {
                    throw fail("trailing bytes or concatenated codestream")
                }
                return Self(process: process, width: width, height: height, precision: precision,
                            components: components, sampling: sampling, scanParameters: scans,
                            jfif: jfif, adobeTransform: adobe)
            }
            guard marker != 0xd8, marker != 0, !(0xd0...0xd7).contains(marker), marker != 1,
                  p + 2 <= data.count else { throw fail("unexpected standalone marker") }
            let length = word(p)
            guard length >= 2, length <= data.count - p else { throw fail("truncated segment") }
            let begin = p + 2, end = p + length
            if (0xc0...0xcf).contains(marker) && ![0xc4, 0xc8, 0xcc].contains(marker) || marker == 0xf7 {
                guard process == nil, scans.isEmpty,
                      jpegLS ? marker == 0xf7 : [0xc0, 0xc1, 0xc3].contains(marker),
                      length >= 8 else { throw fail("unsupported or repeated SOF process") }
                precision = Int(data[begin]); height = word(begin + 1); width = word(begin + 3)
                let count = Int(data[begin + 5])
                guard (count == 1 || count == 3), length == 8 + 3 * count else {
                    throw fail("invalid SOF components")
                }
                components = (0..<count).map { data[begin + 6 + 3 * $0] }
                sampling = (0..<count).map { data[begin + 7 + 3 * $0] }
                guard Set(components).count == count else { throw fail("duplicate SOF component") }
                process = marker
            } else if marker == 0xda {
                guard let process, length >= 6 else { throw fail("SOS before SOF") }
                let count = Int(data[begin])
                guard count > 0, count <= components.count, length == 6 + 2 * count else {
                    throw fail("invalid SOS components")
                }
                let ids = (0..<count).map { data[begin + 1 + 2 * $0] }
                guard Set(ids).count == count, ids.allSatisfy({ components.contains($0) && !scanned.contains($0) }) else {
                    throw fail("unknown or repeated scan component")
                }
                // JLISwift's lossless implementation decodes one interleaved scan only.
                guard process != 0xc3 || (scans.isEmpty && count == components.count) else {
                    throw fail("unsupported noninterleaved lossless JPEG scans")
                }
                scanned.formUnion(ids)
                scans.append((Int(data[end - 3]), Int(data[end - 2]), Int(data[end - 1])))
                entropy = true
            } else if marker == 0xe0, end - begin >= 5 {
                jfif = jfif || data[begin..<begin + 5].elementsEqual([0x4a, 0x46, 0x49, 0x46, 0])
            } else if marker == 0xee, end - begin >= 12,
                      data[begin..<begin + 5].elementsEqual([0x41, 0x64, 0x6f, 0x62, 0x65]) {
                adobe = data[begin + 11]
            } else if marker == 0xdc {
                // Neither dependency implements effective DNL dimensions reliably.
                throw fail("DNL dimensions are unsupported")
            }
            p = end
        }
        throw fail("missing EOI")
    }
}
