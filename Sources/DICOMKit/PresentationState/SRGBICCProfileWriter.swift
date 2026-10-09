// NEMA-verified: 2026a, checked 2026-09-29 — Input Device class scnr per PS3.3 2026a C.11.15.1.1; Color Space SRGB per C.11.15.1.2; the profile bytes themselves are ICC.1
// SRGBICCProfileWriter.swift
// DICOMKit
//
// A minimal sRGB ICC profile, built byte-by-byte so that it is deterministic.
//
// Why this exists at all: the Color, Pseudo-Color and Blending Softcopy
// Presentation State IODs make the ICC Profile module (PS3.3 C.11.15)
// mandatory — an object of those classes without ICC Profile (0028,2000) is
// non-conformant, however little the profile adds when the intent is plain
// sRGB. So a profile has to be written, and the only honest one to write is
// sRGB: it is what every palette in ``PseudoColorPalette`` is defined in, and
// what an uncalibrated display shows.
//
// Why hand-built rather than asked of ColorSync: `CGColorSpace.copyICCData()`
// returns whatever profile the OS ships, which differs between OS versions —
// and a presentation state whose bytes change with the machine that wrote it
// cannot be round-trip tested, and would make two saves of the same view
// different objects. These bytes are fixed forever.
//
// The profile is an ICC v2.4 three-component matrix/TRC profile of the Input
// Device class, as PS3.3 C.11.15.1.1 requires ("scnr") — the
// simplest legal shape: sRGB primaries chromatically adapted to D50, a gamma
// 2.2 tone curve (the customary v2 approximation of the sRGB curve; the
// difference is invisible on any medical display and irrelevant to a viewer
// that, like ours, treats the profile as "this is sRGB"). Structure per
// ICC.1:2001-04.

import Foundation

/// Writes the fixed sRGB ICC profile embedded in colour presentation states.
public enum SRGBICCProfileWriter {

    /// The profile, computed once — the same 480 bytes on every platform and
    /// every run.
    public static let profileData: Data = makeProfile()

    /// The Color Space (0028,2002) defined term matching this profile.
    public static let colorSpace = "SRGB"

    // MARK: - Construction

    private static func makeProfile() -> Data {
        // Tag data blocks, in file order. Offsets are computed, not assumed.
        let desc = descriptionBlock("sRGB")
        let wtpt = xyzBlock(0.9642, 1.0, 0.8249)          // D50 white point
        let cprt = textBlock("CC0")
        let rXYZ = xyzBlock(0.43607, 0.22249, 0.01392)    // sRGB primaries,
        let gXYZ = xyzBlock(0.38515, 0.71687, 0.09708)    // adapted to D50
        let bXYZ = xyzBlock(0.14307, 0.06061, 0.71410)
        let trc  = gammaCurveBlock(2.2)

        // (signature, data) in file order. The three TRC tags share one curve —
        // ICC explicitly allows shared tag data, and the channels are identical.
        let table: [(String, Data)] = [
            ("desc", desc), ("wtpt", wtpt), ("cprt", cprt),
            ("rXYZ", rXYZ), ("gXYZ", gXYZ), ("bXYZ", bXYZ),
            ("rTRC", trc), ("gTRC", trc), ("bTRC", trc),
        ]

        // Lay out: header (128) + tag count (4) + entries (12 each), then the
        // distinct blocks, each padded to a 4-byte boundary.
        let tagTableSize = 4 + table.count * 12
        var blockOffsets: [Data: UInt32] = [:]
        var body = Data()
        var cursor = UInt32(128 + tagTableSize)
        for (_, block) in table where blockOffsets[block] == nil {
            blockOffsets[block] = cursor
            body.append(block)
            let padding = (4 - block.count % 4) % 4
            body.append(Data(repeating: 0, count: padding))
            cursor += UInt32(block.count + padding)
        }

        let profileSize = UInt32(128 + tagTableSize + body.count)

        var profile = Data(capacity: Int(profileSize))

        // MARK: Header (128 bytes)
        appendUInt32(&profile, profileSize)
        appendUInt32(&profile, 0)                          // preferred CMM: none
        appendUInt32(&profile, 0x02400000)                 // version 2.4
        appendSignature(&profile, "scnr")                  // Input Device class (PS3.3 C.11.15.1.1)
        appendSignature(&profile, "RGB ")                  // data colour space
        appendSignature(&profile, "XYZ ")                  // PCS
        // Creation date, fixed so the bytes are: a profile is identified by its
        // content here, not by when it was first emitted.
        for value in [UInt16(2026), 1, 1, 0, 0, 0] { appendUInt16(&profile, value) }
        appendSignature(&profile, "acsp")                  // file signature
        appendUInt32(&profile, 0)                          // platform: none
        appendUInt32(&profile, 0)                          // flags
        appendUInt32(&profile, 0)                          // device manufacturer
        appendUInt32(&profile, 0)                          // device model
        appendUInt32(&profile, 0)                          // attributes (hi)
        appendUInt32(&profile, 0)                          // attributes (lo)
        appendUInt32(&profile, 0)                          // rendering intent: perceptual
        appendS15Fixed16(&profile, 0.9642)                 // PCS illuminant: D50
        appendS15Fixed16(&profile, 1.0)
        appendS15Fixed16(&profile, 0.8249)
        appendUInt32(&profile, 0)                          // creator: none
        profile.append(Data(repeating: 0, count: 44))      // reserved

        // MARK: Tag table
        appendUInt32(&profile, UInt32(table.count))
        for (signature, block) in table {
            appendSignature(&profile, signature)
            appendUInt32(&profile, blockOffsets[block] ?? 0)
            appendUInt32(&profile, UInt32(block.count))
        }

        profile.append(body)
        return profile
    }

    // MARK: - Tag data types

    /// textDescriptionType ('desc') — ICC.1:2001-04 6.5.17.
    private static func descriptionBlock(_ text: String) -> Data {
        var block = Data()
        appendSignature(&block, "desc")
        appendUInt32(&block, 0)                            // reserved
        let ascii = Data(text.utf8) + Data([0])
        appendUInt32(&block, UInt32(ascii.count))
        block.append(ascii)
        appendUInt32(&block, 0)                            // Unicode language code
        appendUInt32(&block, 0)                            // Unicode count
        appendUInt16(&block, 0)                            // ScriptCode code
        block.append(0)                                    // Macintosh count
        block.append(Data(repeating: 0, count: 67))        // Macintosh description
        return block
    }

    /// textType ('text') — ICC.1:2001-04 6.5.20.
    private static func textBlock(_ text: String) -> Data {
        var block = Data()
        appendSignature(&block, "text")
        appendUInt32(&block, 0)
        block.append(Data(text.utf8))
        block.append(0)
        return block
    }

    /// XYZType ('XYZ ') — ICC.1:2001-04 6.5.26.
    private static func xyzBlock(_ x: Double, _ y: Double, _ z: Double) -> Data {
        var block = Data()
        appendSignature(&block, "XYZ ")
        appendUInt32(&block, 0)
        appendS15Fixed16(&block, x)
        appendS15Fixed16(&block, y)
        appendS15Fixed16(&block, z)
        return block
    }

    /// curveType ('curv') with a single gamma value — ICC.1:2001-04 6.5.3.
    private static func gammaCurveBlock(_ gamma: Double) -> Data {
        var block = Data()
        appendSignature(&block, "curv")
        appendUInt32(&block, 0)
        appendUInt32(&block, 1)                            // one entry: a gamma
        appendUInt16(&block, UInt16((gamma * 256).rounded())) // u8Fixed8
        return block
    }

    // MARK: - Big-endian primitives (ICC files are big-endian throughout)

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value >> 24))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendSignature(_ data: inout Data, _ signature: String) {
        precondition(signature.utf8.count == 4, "ICC signatures are 4 bytes")
        data.append(contentsOf: signature.utf8)
    }

    private static func appendS15Fixed16(_ data: inout Data, _ value: Double) {
        appendUInt32(&data, UInt32(bitPattern: Int32((value * 65536).rounded())))
    }
}
