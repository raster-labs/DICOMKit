import Foundation
import XCTest
import SwiftJLS
@testable import DICOMCore

final class JPEGLSNegativeRegressionTests: XCTestCase {
    private func synthetic(bits: Int, components: Int = 1) async throws -> (Data, Data, PixelDataDescriptor) {
        let width = 32, height = 32, maxValue = (1 << bits) - 1
        var pixels = Data()
        for y in 0..<height {
            for x in 0..<width {
                for component in 0..<components {
                    let raw = ((x + y) % 5 == 0 ? x * 997 + y * 4099 : x * 73 + y * 211 + (y % 3) * 1800) + component * 2503
                    let word = UInt16(raw & maxValue)
                    pixels.append(UInt8(word & 255)); pixels.append(UInt8(word >> 8))
                }
            }
        }
        let data = try await JPEGLSCodecStrictDecodingTests.makeLegacyUnclampedCodestream(pixels: pixels,
            width: width, height: height, bitsPerSample: bits, samplesPerPixel: components)
        let descriptor = PixelDataDescriptor(rows: height, columns: width, bitsAllocated: 16,
            bitsStored: bits, highBit: bits - 1, isSigned: components == 1 && bits == 16,
            samplesPerPixel: components, photometricInterpretation: components == 1 ? .monochrome2 : .rgb,
            planarConfiguration: 0)
        return (data, pixels, descriptor)
    }

    private func destroy<T: ~Copyable>(_ value: consuming T) {}

    private func assertManagedRejects(_ data: Data, descriptor: PixelDataDescriptor,
                                      codec: JPEGLSCodec) throws {
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        do {
            let input = try DICOMByteBuffer(count: data.count, budget: budget, resource: .encoded)
            data.withUnsafeBytes { input.unsafeMutableBytes.copyMemory(from: $0) }
            do {
                let frame = try codec.decodeManagedPixelFrame(input, descriptor: descriptor, frameIndex: 0, budget: budget)
                XCTFail("Managed decoder accepted \(frame.data.count) bytes")
                destroy(frame)
            } catch {}
            XCTAssertEqual(budget.receipt.current.staging, 0)
            XCTAssertEqual(budget.receipt.current.decoded, 0)
            destroy(input)
        }
        XCTAssertEqual(budget.receipt.currentTotal, baseline)
    }

    func testDefaultRejectsUndeclaredLegacyPresets() async throws {
        for (bits, components) in [(13, 1), (14, 1), (15, 1), (16, 1), (16, 3)] {
            let (data, _, descriptor) = try await synthetic(bits: bits, components: components)
            let codec = JPEGLSCodec(decodingSyntax: .lossless)
            XCTAssertThrowsError(try codec.decodeFrame(data, descriptor: descriptor, frameIndex: 0))
            XCTAssertThrowsError(try codec.decodePixelFrame(data, descriptor: descriptor, frameIndex: 0))
            try assertManagedRejects(data, descriptor: descriptor, codec: codec)
        }
    }

    private func assertManagedMatches(_ data: Data, pixels: Data, descriptor: PixelDataDescriptor,
                                      codec: JPEGLSCodec) throws {
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        let input = try DICOMByteBuffer(count: data.count, budget: budget, resource: .encoded)
        data.withUnsafeBytes { input.unsafeMutableBytes.copyMemory(from: $0) }
        let frame = try codec.decodeManagedPixelFrame(input, descriptor: descriptor, frameIndex: 0, budget: budget)
        XCTAssertEqual(frame.data.withUnsafeBytes { Data($0) }, pixels)
        XCTAssertEqual(budget.receipt.current.staging, 0)
        destroy(frame)
        destroy(input)
        XCTAssertEqual(budget.receipt.currentTotal, baseline)
    }

    func testExplicitRecoveryPreservesPixelsAndResources() async throws {
        for (bits, components) in [(13, 1), (14, 1), (15, 1), (16, 1), (16, 3)] {
            let (raw, pixels, descriptor) = try await synthetic(bits: bits, components: components)
            var variants = [raw]
            if raw.count % 2 == 1 { variants.append(raw + Data([0])) }
            for data in variants {
                let codec = JPEGLSCodec(decodingSyntax: .lossless,
                    missingPresetPolicy: .allowLegacyUnclampedRecovery)
                let stringCodec = JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
                    missingPresetPolicy: .allowLegacyUnclampedRecovery)
                XCTAssertEqual(try codec.decodePixelFrame(data, descriptor: descriptor, frameIndex: 0).data, pixels)
                XCTAssertEqual(try stringCodec.decodeFrame(data, descriptor: descriptor, frameIndex: 0), pixels)
                try assertManagedMatches(data, pixels: pixels, descriptor: descriptor, codec: codec)
            }
        }
    }

    func testStandardStreamsRemainExactUnderBothPolicies() async throws {
        for components in [1, 3] {
            let (_, pixels, descriptor) = try await synthetic(bits: 16, components: components)
            let data = try JPEGLSCodec().encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
            for policy in [JPEGLSCodec.MissingPresetPolicy.requireStandardDefaults, .allowLegacyUnclampedRecovery] {
                let codec = JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: policy)
                XCTAssertEqual(try codec.decodeFrame(data, descriptor: descriptor, frameIndex: 0), pixels)
                try assertManagedMatches(data, pixels: pixels, descriptor: descriptor, codec: codec)
            }
        }
    }

    func testExplicitLSEAlwaysControlsParameters() async throws {
        let (raw, pixels, descriptor) = try await synthetic(bits: 16)
        let sos = try XCTUnwrap(raw.range(of: Data([0xff, 0xda])))
        for (thresholds, shouldPass) in [([258, 1027, 4356], true), ([18, 67, 276], false)] {
            var lse = Data([0xff, 0xf8, 0, 13, 1, 0xff, 0xff])
            for value in thresholds + [64] { lse.append(UInt8(value >> 8)); lse.append(UInt8(value & 255)) }
            let data = Data(raw[..<sos.lowerBound]) + lse + Data(raw[sos.lowerBound...])
            for policy in [JPEGLSCodec.MissingPresetPolicy.requireStandardDefaults, .allowLegacyUnclampedRecovery] {
                let codec = JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: policy)
                if shouldPass {
                    XCTAssertEqual(try codec.decodeFrame(data, descriptor: descriptor, frameIndex: 0), pixels)
                    try assertManagedMatches(data, pixels: pixels, descriptor: descriptor, codec: codec)
                } else {
                    XCTAssertThrowsError(try codec.decodeFrame(data, descriptor: descriptor, frameIndex: 0))
                    try assertManagedRejects(data, descriptor: descriptor, codec: codec)
                }
            }
        }
    }

    func testTruncatedEntropyRejectedEvenWithCompatibilityEnabled() async throws {
        let (_, pixels, descriptor) = try await synthetic(bits: 16)
        let valid = try JPEGLSCodec().encodeFrame(pixels, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let truncated = Data(valid.prefix(valid.count / 2)) + Data([0xff, 0xd9])
        for policy in [JPEGLSCodec.MissingPresetPolicy.requireStandardDefaults, .allowLegacyUnclampedRecovery] {
            let codec = JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: policy)
            XCTAssertThrowsError(try codec.decodeFrame(truncated, descriptor: descriptor, frameIndex: 0))
            try assertManagedRejects(truncated, descriptor: descriptor, codec: codec)
        }
    }

    func testCancellationNeverTriggersRecovery() async throws {
        let (data, _, descriptor) = try await synthetic(bits: 16)
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        let input = try DICOMByteBuffer(count: data.count, budget: budget, resource: .encoded)
        data.withUnsafeBytes { input.unsafeMutableBytes.copyMemory(from: $0) }
        let codec = JPEGLSCodec(decodingSyntax: .lossless, missingPresetPolicy: .allowLegacyUnclampedRecovery)
        switch codec.decodeManagedPixelFrameOutcome(input, descriptor: descriptor, frameIndex: 0,
            budget: budget, cancellation: DICOMCancellation(check: { _ in true })) {
        case .success(let frame): XCTFail("Cancelled decode succeeded"); destroy(frame)
        case .failure(let failure): XCTAssertEqual(failure.code, .cancelled)
        }
        destroy(input)
        XCTAssertEqual(budget.receipt.currentTotal, baseline)
    }

}
