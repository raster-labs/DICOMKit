import Testing
import Foundation
@testable import DICOMStudio
import DICOMKit
import DICOMCore

/// Headless driver for the multi-format codec bench: runs the *real*
/// `J2KTestBenchService` engine (the same code the DICOMStudio J2K Test Bench
/// GUI uses) over real `SampleStudies` frames and prints the per-format
/// comparison table — reference compression + each same-family codec's decode
/// time and bit-exact correctness. This is the headless equivalent of clicking
/// "Run Test Matrix" in the app.
@Suite("Multi-codec comparison table")
struct MultiCodecComparisonTableTests {

    private func loadFrame(_ path: String) -> (frame: Data, desc: PixelDataDescriptor)? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let file: DICOMFile
        if let p = try? DICOMFile.read(from: data) { file = p }
        else if let f = try? DICOMFile.read(from: data, force: true) { file = f }
        else { return nil }
        guard let pd = file.pixelData(), let frame = pd.frameData(at: 0) else { return nil }
        return (frame, pd.descriptor)
    }

    private func col(_ s: String, _ w: Int, right: Bool = false) -> String {
        if s.count >= w { return String(s.prefix(w)) }
        let pad = String(repeating: " ", count: w - s.count)
        return right ? pad + s : s + pad
    }

    @Test(
        "Per-format codec comparison on SampleStudies",
        .enabled(if: LocalCodecFixtureAvailability.hasSampleStudies, "Requires optional SampleStudies codec fixtures")
    )
    func comparisonTable() throws {
        let root = FileManager.default.currentDirectoryPath + "/SampleStudies"
        // Search a handful of modality folders for suitable frames.
        let dirs = ["dx", "cr", "mg", "mr", "px", "ct", "xa"].map { root + "/" + $0 }
        let fm = FileManager.default

        var picked: [(name: String, frame: Data, desc: PixelDataDescriptor)] = []
        outer: for dir in dirs {
            guard let en = fm.enumerator(atPath: dir) else { continue }
            for case let rel as String in en where rel.hasSuffix(".dcm") {
                let path = dir + "/" + rel
                guard let loaded = loadFrame(path) else { continue }
                let d = loaded.desc
                // Require an uncompressed (raw == expected size), unsigned,
                // 8/16-bit, 1- or 3-component frame of a sensible size so all
                // four codec families apply and the run stays quick.
                let pixels = d.rows * d.columns
                guard loaded.frame.count == d.bytesPerFrame,
                      !d.isSigned,
                      d.samplesPerPixel == 1 || d.samplesPerPixel == 3,
                      d.bitsAllocated == 8 || d.bitsAllocated == 16,
                      pixels >= 256 * 256, pixels <= 1_500_000 else { continue }
                let modality = (dir as NSString).lastPathComponent.uppercased()
                picked.append(("\(modality)/\(URL(fileURLWithPath: path).lastPathComponent)",
                               loaded.frame, d))
                if picked.count >= 2 { break outer }
            }
        }

        try #require(!picked.isEmpty,
                     "no suitable uncompressed sample frame found under \(root)")

        let formats: [J2KBenchFormat] = [.jpeg2000, .jpeg, .jpegLS, .jpegXL]
        let warmups = 1, runs = 3

        for img in picked {
            let d = img.desc
            print("""

            ══════════════════════════════════════════════════════════════════════════
             \(img.name)  —  \(d.columns)×\(d.rows), \(d.bitsAllocated)-bit, spp=\(d.samplesPerPixel), \(img.frame.count) raw bytes
            ══════════════════════════════════════════════════════════════════════════
            """)
            print(col("format", 11) + col("codec", 13) + col("enc bytes", 11, right: true)
                  + col("ratio", 9, right: true) + col("enc ms", 10, right: true)
                  + col("dec ms", 10, right: true) + "  result")
            print(String(repeating: "─", count: 76))

            for fmt in formats {
                guard let syntax = J2KBenchSyntax.all(for: fmt).first(where: { $0.isLossless }) else { continue }
                let enc = J2KTestBenchService.encodeReference(
                    frame: img.frame, descriptor: d, syntax: syntax,
                    mode: .cpu, warmups: warmups, runs: runs)

                switch enc {
                case .failure(let e):
                    print(col(fmt.rawValue, 11) + col(syntax.shortName, 13)
                          + "  encode failed — \(e.message)")
                case .success(let product):
                    let ratio = Double(d.bytesPerFrame) / Double(max(1, product.codestream.count))
                    for codec in fmt.codecs {
                        let scored = J2KTestBenchService.decodeAndScore(
                            codestream: product.codestream, original: img.frame,
                            descriptor: d, syntax: syntax, codec: codec,
                            decodeMode: .cpu, warmups: warmups, runs: runs,
                            lossyThresholdDb: 40)
                        let result: String
                        switch scored.outcome {
                        case .pass:    result = scored.psnrDb == nil ? "bit-exact ✓"
                                                : String(format: "PSNR %.1f dB", scored.psnrDb!)
                        case .fail(let m):    result = "FAIL — \(m)"
                        case .error(let m):   result = "error — \(m)"
                        case .skipped(let m): result = "skipped — \(m)"
                        }
                        let encMs = codec.encodes ? String(format: "%.1f", product.encodeMs) : "—"
                        let decMs = scored.decodeMs.map { String(format: "%.1f", $0) } ?? "—"
                        let isRef = codec.encodes ? "▸ " : "  "
                        print(col(fmt.rawValue, 11)
                              + col(isRef + codec.displayName, 13)
                              + col(String(product.codestream.count), 11, right: true)
                              + col(String(format: "%.2f×", ratio), 9, right: true)
                              + col(encMs, 10, right: true)
                              + col(decMs, 10, right: true)
                              + "  " + result)
                    }
                }
            }
        }
        print("\n(▸ = reference encoder for the family; peers decode its codestream. Compression ratio is the family encoder's; decode times are per codec.)\n")
    }
}
