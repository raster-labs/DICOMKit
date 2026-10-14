#if canImport(CryptoKit)
import CryptoKit
import Foundation
import Testing
@testable import DICOMKit

@Suite("Fixed-storage source identity")
struct BoundedSHA256Tests {
    @Test("FIPS SHA-256 vectors")
    func knownVectors() {
        for (input, expected) in [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
             "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        ] {
            var hash = BoundedSHA256()
            Array(input.utf8).withUnsafeBytes { hash.update($0) }
            #expect(hash.finalize().hexadecimal == expected)
        }
    }

    @Test("Padding boundaries and incremental splits match independent CryptoKit", arguments:
        [0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 65535, 65536, 65537, 1_000_000])
    func differential(count: Int) {
        var state: UInt64 = 0x7c4a10d2ee193685
        let bytes = (0..<count).map { _ -> UInt8 in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: state >> 32)
        }
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        for stride in [1, 3, 64, 65, 65536] {
            var hash = BoundedSHA256()
            bytes.withUnsafeBytes { raw in
                var offset = 0
                while offset < count {
                    let end = min(count, offset + stride)
                    hash.update(UnsafeRawBufferPointer(rebasing: raw[offset..<end]))
                    offset = end
                }
            }
            let digest = hash.finalize()
            #expect(digest.hexadecimal == expected)
            var output = [UInt8](repeating: 0, count: 32)
            output.withUnsafeMutableBytes { digest.write(to: $0) }
            #expect(output.withUnsafeBytes { digest.matches($0) })
            output[0] ^= 1
            #expect(!output.withUnsafeBytes { digest.matches($0) })
        }
    }
}
#endif
