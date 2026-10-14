import Foundation

/// Marker-only admission for the finite JPEG/JPEG-LS processes supported here.
/// Component and scan fields are inline: the admitted grammar permits at most three of each.
/// PS3.5 2026a A.4.1/A.4.3 require an independently
/// encoded frame; A.4 permits padding of its final fragment. Marker grammar: ITU-T T.81 B / T.87 C.
struct JPEGFrameEnvelope {
    let process: UInt8
    let width: Int
    let height: Int
    let precision: Int
    let components: Components
    let scanParameters: Scans
    let jfif: Bool
    let adobeTransform: UInt8?

    struct Component: Equatable {
        var id: UInt8 = 0
        var sampling: UInt8 = 0
    }

    struct Components: Equatable {
        private var first = Component(), second = Component(), third = Component()
        private(set) var count = 0

        subscript(index: Int) -> Component {
            precondition(index >= 0 && index < count)
            switch index { case 0: return first; case 1: return second; default: return third }
        }

        mutating func append(_ component: Component) {
            precondition(count < 3)
            switch count { case 0: first = component; case 1: second = component; default: third = component }
            count += 1
        }

        func index(of id: UInt8) -> Int? {
            for index in 0..<count where self[index].id == id { return index }
            return nil
        }

        var hasUnitSampling: Bool {
            for index in 0..<count where self[index].sampling != 0x11 { return false }
            return true
        }

        var hasRGBIdentifiers: Bool { count == 3 && first.id == 82 && second.id == 71 && third.id == 66 }
    }

    struct Scan: Equatable {
        var first = 0, last = 0, approximation = 0
    }

    struct Scans: Equatable {
        private var first = Scan(), second = Scan(), third = Scan()
        private(set) var count = 0

        subscript(index: Int) -> Scan {
            precondition(index >= 0 && index < count)
            switch index { case 0: return first; case 1: return second; default: return third }
        }

        mutating func append(_ scan: Scan) {
            precondition(count < 3)
            switch count { case 0: first = scan; case 1: second = scan; default: third = scan }
            count += 1
        }

        func allSatisfy(_ predicate: (Scan) -> Bool) -> Bool {
            for index in 0..<count where !predicate(self[index]) { return false }
            return true
        }
    }

    static func parse(_ input: Data, jpegLS: Bool) throws -> Self {
        do {
            return try input.withUnsafeBytes {
                try parse($0, jpegLS: jpegLS, cancellation: DICOMCancellation(check: { _ in Task.isCancelled }))
            }
        } catch let failure as DICOMManagedFailure {
            if failure.code == .cancelled { throw CancellationError() }
            if failure.code == .limitExceeded { throw DICOMError.limitExceeded("Too many JPEG marker segments") }
            let reason: String
            switch failure.operand1 {
            case 0: reason = "missing SOI"
            case 1: reason = "truncated entropy marker"
            case 2: reason = "missing marker/EOI"
            case 3: reason = "truncated marker"
            case 4: reason = "incomplete frame/scans"
            case 5: reason = "trailing bytes or concatenated codestream"
            case 6: reason = "unexpected standalone marker"
            case 7: reason = "truncated segment"
            case 8: reason = "unsupported or repeated SOF process"
            case 9: reason = "invalid SOF components"
            case 10: reason = "duplicate SOF component"
            case 11: reason = "SOS before SOF"
            case 12: reason = "invalid SOS components"
            case 13: reason = "unknown or repeated scan component"
            case 14: reason = "unsupported noninterleaved lossless JPEG scans"
            case 15: reason = "DNL dimensions are unsupported"
            case 16: reason = "missing EOI"
            default: reason = "invalid frame"
            }
            throw DICOMError.parsingFailed("JPEG frame envelope: \(reason)")
        }
    }

    // Throwing compatibility boundary; selected callers use parseOutcome directly.
    static func parse(_ data: UnsafeRawBufferPointer, jpegLS: Bool,
                      cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) -> Self {
        try parseOutcome(data, jpegLS: jpegLS, cancellation: cancellation).get()
    }

    static func parseOutcome(_ data: UnsafeRawBufferPointer, jpegLS: Bool,
                      cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Self> {
        var p = 2
        if let failure = cancellation.failure { return .failure(failure) }
        guard data.count >= 4, data[0] == 0xff, data[1] == 0xd8 else {
            return .failure(DICOMManagedFailure(.malformed, offset: 0, 0))
        }
        func word(_ i: Int) -> Int { Int(data[i]) << 8 | Int(data[i + 1]) }
        var entropy = false
        var process: UInt8?
        var width = 0, height = 0, precision = 0
        var components = Components()
        var scans = Scans()
        var scanned: UInt8 = 0
        var jfif = false
        var adobe: UInt8?
        var markers = 0
        while p < data.count {
            if let failure = cancellation.failure { return .failure(failure) }
            if entropy {
                var cancellationOffset = p
                while p < data.count {
                    if p >= cancellationOffset {
                        if let failure = cancellation.failure { return .failure(failure) }
                        cancellationOffset = p + min(0x10000, data.count - p)
                    }
                    if data[p] != 0xff { p += 1; continue }
                    guard p + 1 < data.count else { return .failure(DICOMManagedFailure(.malformed, offset: p, 1)) }
                    let next = data[p + 1]
                    if jpegLS ? next < 0x80 : next == 0 { p += 2; continue }
                    if (0xd0...0xd7).contains(next) { p += 2; continue }
                    break
                }
                entropy = false
            }
            guard p + 1 < data.count, data[p] == 0xff else {
                return .failure(DICOMManagedFailure(.malformed, offset: p, 2))
            }
            var markerCancellationOffset = p
            while p < data.count, data[p] == 0xff {
                if p >= markerCancellationOffset {
                    if let failure = cancellation.failure { return .failure(failure) }
                    markerCancellationOffset = p + min(0x10000, data.count - p)
                }
                p += 1
            }
            guard p < data.count else { return .failure(DICOMManagedFailure(.malformed, offset: p, 3)) }
            let marker = data[p]; p += 1
            markers += 1
            guard markers <= 4096 else { return .failure(DICOMManagedFailure(.limitExceeded, offset: p, markers)) }
            if marker == 0xd9 {
                guard let process, scans.count > 0, scanned == (1 << components.count) - 1 else {
                    return .failure(DICOMManagedFailure(.malformed, offset: p, 4))
                }
                guard p == data.count || (p % 2 == 1 && p + 1 == data.count && data[p] == 0) else {
                    return .failure(DICOMManagedFailure(.malformed, offset: p, 5))
                }
                return .success(Self(process: process, width: width, height: height, precision: precision,
                            components: components, scanParameters: scans,
                            jfif: jfif, adobeTransform: adobe))
            }
            guard marker != 0xd8, marker != 0, !(0xd0...0xd7).contains(marker), marker != 1,
                  p + 2 <= data.count else { return .failure(DICOMManagedFailure(.malformed, offset: p, 6)) }
            let length = word(p)
            guard length >= 2, length <= data.count - p else {
                return .failure(DICOMManagedFailure(.malformed, offset: p, 7))
            }
            let begin = p + 2, end = p + length
            if (0xc0...0xcf).contains(marker) && marker != 0xc4 && marker != 0xc8 && marker != 0xcc || marker == 0xf7 {
                guard process == nil, scans.count == 0,
                      jpegLS ? marker == 0xf7 : (marker == 0xc0 || marker == 0xc1 || marker == 0xc3),
                      length >= 8 else { return .failure(DICOMManagedFailure(.malformed, offset: p, 8)) }
                precision = Int(data[begin]); height = word(begin + 1); width = word(begin + 3)
                let count = Int(data[begin + 5])
                guard (count == 1 || count == 3), length == 8 + 3 * count else {
                    return .failure(DICOMManagedFailure(.malformed, offset: p, 9))
                }
                for index in 0..<count {
                    let id = data[begin + 6 + 3 * index]
                    guard components.index(of: id) == nil else {
                        return .failure(DICOMManagedFailure(.malformed, offset: p, 10))
                    }
                    components.append(Component(id: id, sampling: data[begin + 7 + 3 * index]))
                }
                process = marker
            } else if marker == 0xda {
                guard let process, length >= 6 else { return .failure(DICOMManagedFailure(.malformed, offset: p, 11)) }
                let count = Int(data[begin])
                guard count > 0, count <= components.count, length == 6 + 2 * count else {
                    return .failure(DICOMManagedFailure(.malformed, offset: p, 12))
                }
                // Masks use SOF positions, so arbitrary UInt8 identifiers remain valid.
                var scanMask: UInt8 = 0
                for selector in 0..<count {
                    guard let index = components.index(of: data[begin + 1 + 2 * selector]),
                          (scanned | scanMask) & (1 << index) == 0 else {
                        return .failure(DICOMManagedFailure(.malformed, offset: p, 13))
                    }
                    scanMask |= 1 << index
                }
                // JLISwift's lossless implementation decodes one interleaved scan only.
                guard process != 0xc3 || (scans.count == 0 && count == components.count) else {
                    return .failure(DICOMManagedFailure(.malformed, offset: p, 14))
                }
                // Each successful SOS consumes at least one previously uncovered component;
                // the three-component SOF limit therefore also bounds successful scans to three.
                scanned |= scanMask
                scans.append(Scan(first: Int(data[end - 3]), last: Int(data[end - 2]),
                                  approximation: Int(data[end - 1])))
                entropy = true
            } else if marker == 0xe0, end - begin >= 5 {
                jfif = jfif || (data[begin] == 0x4a && data[begin + 1] == 0x46 && data[begin + 2] == 0x49
                    && data[begin + 3] == 0x46 && data[begin + 4] == 0)
            } else if marker == 0xee, end - begin >= 12,
                      data[begin] == 0x41, data[begin + 1] == 0x64, data[begin + 2] == 0x6f,
                      data[begin + 3] == 0x62, data[begin + 4] == 0x65 {
                adobe = data[begin + 11]
            } else if marker == 0xdc {
                // Neither dependency implements effective DNL dimensions reliably.
                return .failure(DICOMManagedFailure(.malformed, offset: p, 15))
            }
            p = end
        }
        return .failure(DICOMManagedFailure(.malformed, offset: p, 16))
    }
}
