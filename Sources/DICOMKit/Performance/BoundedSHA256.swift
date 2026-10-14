// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (content identity).
// SHA-256: FIPS PUB 180-4, sections 4.1.2, 4.2.2, 5 and 6.2.

/// Fixed-size SHA-256 identity. Hex formatting is an explicit, unbudgeted adapter
/// for logging/UI; the admitted source/parser/codec path retains this value only.
public struct DICOMContentDigest: Equatable, Sendable {
    private let a: UInt32, b: UInt32, c: UInt32, d: UInt32
    private let e: UInt32, f: UInt32, g: UInt32, h: UInt32
    init(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32,
         _ e: UInt32, _ f: UInt32, _ g: UInt32, _ h: UInt32) {
        self.a = a; self.b = b; self.c = c; self.d = d
        self.e = e; self.f = f; self.g = g; self.h = h
    }
    /// Lowercase hexadecimal representation; call outside the admitted operation.
    public var hexadecimal: String {
        var bytes = [UInt8](repeating: 0, count: 64)
        for position in 0..<32 {
            let value = byte(at: position), high = value >> 4, low = value & 15
            bytes[position * 2] = high < 10 ? 48 + high : 87 + high
            bytes[position * 2 + 1] = low < 10 ? 48 + low : 87 + low
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    func byte(at position: Int) -> UInt8 {
        let word: UInt32
        switch position / 4 {
        case 0: word = a
        case 1: word = b
        case 2: word = c
        case 3: word = d
        case 4: word = e
        case 5: word = f
        case 6: word = g
        default: word = h
        }
        return UInt8(truncatingIfNeeded: word >> ((3 - position % 4) * 8))
    }
    func write(to bytes: UnsafeMutableRawBufferPointer) {
        precondition(bytes.count == 32)
        for position in 0..<32 { bytes[position] = byte(at: position) }
    }
    func matches(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard bytes.count == 32 else { return false }
        var difference: UInt8 = 0
        for position in 0..<32 { difference |= bytes[position] ^ byte(at: position) }
        return difference == 0
    }
}

/// Incremental, fixed-storage hash. No Foundation/CryptoKit/CommonCrypto state,
/// lazy global initialization, variable collection, or allocation occurs here.
struct BoundedSHA256 {
    private var a: UInt32 = 0x6a09e667, b: UInt32 = 0xbb67ae85, c: UInt32 = 0x3c6ef372, d: UInt32 = 0xa54ff53a
    private var e: UInt32 = 0x510e527f, f: UInt32 = 0x9b05688c, g: UInt32 = 0x1f83d9ab, h: UInt32 = 0x5be0cd19
    private var block: Words16 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    private var used = 0
    private var byteCount: UInt64 = 0
    private typealias Words16 = (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
                                UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    mutating func update(_ input: UnsafeRawBufferPointer) {
        byteCount &+= UInt64(input.count)
        var offset = 0
        if used > 0 {
            while offset < input.count && used > 0 { append(input[offset]); offset += 1 }
        }
        while input.count - offset >= 64 {
            withUnsafeMutableBytes(of: &block) { output in
                output.copyMemory(from: UnsafeRawBufferPointer(rebasing: input[offset..<offset + 64]))
            }
            compress()
            offset += 64
        }
        while offset < input.count { append(input[offset]); offset += 1 }
    }
    private mutating func append(_ byte: UInt8) {
        withUnsafeMutableBytes(of: &block) { $0[used] = byte }
        used += 1
        if used == 64 { compress(); used = 0 }
    }
    mutating func finalize() -> DICOMContentDigest {
        let bits = byteCount &* 8
        append(0x80)
        while used != 56 { append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { append(UInt8(truncatingIfNeeded: bits >> shift)) }
        return DICOMContentDigest(a, b, c, d, e, f, g, h)
    }
    private static func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    private mutating func compress() {
        var schedule = block
        var aa = a, bb = b, cc = c, dd = d, ee = e, ff = f, gg = g, hh = h
        withUnsafeMutableBytes(of: &schedule) { raw in
            let w = raw.bindMemory(to: UInt32.self)
            for i in 0..<16 { w[i] = UInt32(bigEndian: w[i]) }
            for i in 0..<64 {
                let j = i & 15
                if i >= 16 {
                    let x = w[(i - 15) & 15], y = w[(i - 2) & 15]
                    let s0 = Self.rotate(x, 7) ^ Self.rotate(x, 18) ^ (x >> 3)
                    let s1 = Self.rotate(y, 17) ^ Self.rotate(y, 19) ^ (y >> 10)
                    w[j] = w[j] &+ s0 &+ w[(i - 7) & 15] &+ s1
                }
                let s1 = Self.rotate(ee, 6) ^ Self.rotate(ee, 11) ^ Self.rotate(ee, 25)
                let choice = (ee & ff) ^ (~ee & gg)
                let t1 = hh &+ s1 &+ choice &+ Self.constant(i) &+ w[j]
                let s0 = Self.rotate(aa, 2) ^ Self.rotate(aa, 13) ^ Self.rotate(aa, 22)
                let majority = (aa & bb) ^ (aa & cc) ^ (bb & cc)
                let t2 = s0 &+ majority
                hh = gg; gg = ff; ff = ee; ee = dd &+ t1
                dd = cc; cc = bb; bb = aa; aa = t1 &+ t2
            }
        }
        a &+= aa; b &+= bb; c &+= cc; d &+= dd
        e &+= ee; f &+= ff; g &+= gg; h &+= hh
    }
    private static func constant(_ i: Int) -> UInt32 {
        switch i {
        case 0: 0x428a2f98
        case 1: 0x71374491
        case 2: 0xb5c0fbcf
        case 3: 0xe9b5dba5
        case 4: 0x3956c25b
        case 5: 0x59f111f1
        case 6: 0x923f82a4
        case 7: 0xab1c5ed5
        case 8: 0xd807aa98
        case 9: 0x12835b01
        case 10: 0x243185be
        case 11: 0x550c7dc3
        case 12: 0x72be5d74
        case 13: 0x80deb1fe
        case 14: 0x9bdc06a7
        case 15: 0xc19bf174
        case 16: 0xe49b69c1
        case 17: 0xefbe4786
        case 18: 0x0fc19dc6
        case 19: 0x240ca1cc
        case 20: 0x2de92c6f
        case 21: 0x4a7484aa
        case 22: 0x5cb0a9dc
        case 23: 0x76f988da
        case 24: 0x983e5152
        case 25: 0xa831c66d
        case 26: 0xb00327c8
        case 27: 0xbf597fc7
        case 28: 0xc6e00bf3
        case 29: 0xd5a79147
        case 30: 0x06ca6351
        case 31: 0x14292967
        case 32: 0x27b70a85
        case 33: 0x2e1b2138
        case 34: 0x4d2c6dfc
        case 35: 0x53380d13
        case 36: 0x650a7354
        case 37: 0x766a0abb
        case 38: 0x81c2c92e
        case 39: 0x92722c85
        case 40: 0xa2bfe8a1
        case 41: 0xa81a664b
        case 42: 0xc24b8b70
        case 43: 0xc76c51a3
        case 44: 0xd192e819
        case 45: 0xd6990624
        case 46: 0xf40e3585
        case 47: 0x106aa070
        case 48: 0x19a4c116
        case 49: 0x1e376c08
        case 50: 0x2748774c
        case 51: 0x34b0bcb5
        case 52: 0x391c0cb3
        case 53: 0x4ed8aa4a
        case 54: 0x5b9cca4f
        case 55: 0x682e6ff3
        case 56: 0x748f82ee
        case 57: 0x78a5636f
        case 58: 0x84c87814
        case 59: 0x8cc70208
        case 60: 0x90befffa
        case 61: 0xa4506ceb
        case 62: 0xbef9a3f7
        default: 0xc67178f2
        }
    }
}
