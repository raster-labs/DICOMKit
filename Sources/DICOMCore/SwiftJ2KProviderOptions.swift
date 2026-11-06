import Foundation
import Synchronization
import SwiftJ2K

/// Operation kind executed by the 2D `SwiftJ2K` provider.
public enum SwiftJ2KOperationKind: String, Sendable, Equatable, Codable {
    case decode
    case encode
    case transcode
}

/// Captures the exact `SwiftJ2K.OperationReport` emitted for one frame operation.
public struct SwiftJ2KOperationRecord: Sendable, Equatable {
    public let kind: SwiftJ2KOperationKind
    public let transferSyntaxUID: String
    public let targetTransferSyntaxUID: String?
    public let frameIndex: Int
    public let report: OperationReport

    public init(
        kind: SwiftJ2KOperationKind,
        transferSyntaxUID: String,
        targetTransferSyntaxUID: String? = nil,
        frameIndex: Int,
        report: OperationReport
    ) {
        self.kind = kind
        self.transferSyntaxUID = transferSyntaxUID
        self.targetTransferSyntaxUID = targetTransferSyntaxUID
        self.frameIndex = frameIndex
        self.report = report
    }

    /// Maps `SwiftJ2K`'s `Backend` and concrete `AcceleratedEngine` onto `DICOMCore.CodecBackend`
    /// without mislabelling CPU SIMD vs Metal GPU execution.
    public var dicomBackend: CodecBackend? {
        switch report.backend {
        case .scalarCPU:
            return .scalar
        case .accelerated:
            switch report.acceleratedEngine {
            case .cpuSIMD:
                return .accelerate
            case .metalGPU:
                return .metal
            case .none:
                return .scalar
            }
        }
    }
}

/// Thread-safe collector for `SwiftJ2KOperationRecord` telemetry without global mutable state.
public final class SwiftJ2KTelemetryCollector: Sendable {
    private let storage = Mutex<[SwiftJ2KOperationRecord]>([])

    public init() {}

    public func record(_ entry: SwiftJ2KOperationRecord) {
        storage.withLock { $0.append(entry) }
    }

    public var records: [SwiftJ2KOperationRecord] {
        storage.withLock { $0 }
    }

    public func reset() {
        storage.withLock { $0.removeAll() }
    }
}

/// Immutable per-provider options for the 2D `SwiftJ2K` adapter.
public struct SwiftJ2KProviderOptions: Sendable {
    /// Finite `SwiftJ2K` admission and deadline bounds applied to every frame operation.
    public let resourceLimits: ResourceLimits

    /// Per-frame DICOM pre-admission bounds validated before sample decoding or encoding.
    public let decodingLimits: PixelDecodeLimits

    /// Bounded grace window (in seconds) waited for worker unwind after cancellation or deadline expiry.
    public let joinGraceSeconds: Double

    /// Optional provider-level forced backend (`nil` = automatic backend selection) applied when
    /// an individual call leaves its per-operation backend set to `.auto` / `nil`.
    public let defaultBackend: CodecBackend?

    /// Optional per-operation telemetry sink invoked with the exact `SwiftJ2K.OperationReport`.
    public let telemetryHandler: (@Sendable (SwiftJ2KOperationRecord) -> Void)?

    /// Default bounded per-frame options aligned with `PixelDecodeLimits.default` (64 MiB encoded/decoded, 16M pixels, 120s deadline).
    public static let `default`: SwiftJ2KProviderOptions = {
        let limits = (try? ResourceLimits(
            maximumCompressedBytes: 64 << 20,
            maximumDecodedBytes: 64 << 20,
            maximumWorkspaceBytes: 256 << 20,
            maximumPixels: 16 << 20,
            maximumDimension: 65_535,
            maximumFrames: 1,
            maximumMetadataBytes: 4 << 20,
            maximumICCBytes: 4 << 20,
            maximumNestingDepth: 16,
            maximumWorkers: 1,
            deadlineSeconds: 120.0,
            maximumMemoryBytes: 384 << 20
        )) ?? .default
        return SwiftJ2KProviderOptions(
            resourceLimits: limits,
            decodingLimits: PixelDecodeLimits(
                maximumEncodedBytes: limits.maximumCompressedBytes,
                maximumDecodedBytes: limits.maximumDecodedBytes,
                maximumPixels: limits.maximumPixels
            ),
            joinGraceSeconds: 5.0,
            defaultBackend: nil,
            telemetryHandler: nil
        )
    }()

    /// Builds `SwiftJ2KProviderOptions` aligned with caller-supplied `PixelDecodeLimits`.
    public static func from(
        decodingLimits: PixelDecodeLimits,
        defaultBackend: CodecBackend? = nil
    ) -> SwiftJ2KProviderOptions {
        let maxEncoded = max(1, decodingLimits.maximumEncodedBytes)
        let maxDecoded = max(1, decodingLimits.maximumDecodedBytes)
        let maxPixels = max(1, decodingLimits.maximumPixels)
        let (ws4, wsOv) = maxDecoded.multipliedReportingOverflow(by: 4)
        let maxWorkspace = max(256 << 20, wsOv ? (1 << 30) : ws4)
        let (mem6, memOv) = maxDecoded.multipliedReportingOverflow(by: 6)
        let maxMemory = max(384 << 20, max(maxWorkspace, memOv ? (1 << 30) : mem6))
        let limits = (try? ResourceLimits(
            maximumCompressedBytes: maxEncoded,
            maximumDecodedBytes: maxDecoded,
            maximumWorkspaceBytes: maxWorkspace,
            maximumPixels: maxPixels,
            maximumDimension: 65_535,
            maximumFrames: 1,
            maximumMetadataBytes: 4 << 20,
            maximumICCBytes: 4 << 20,
            maximumNestingDepth: 16,
            maximumWorkers: 1,
            deadlineSeconds: 120.0,
            maximumMemoryBytes: maxMemory
        )) ?? SwiftJ2KProviderOptions.default.resourceLimits
        return SwiftJ2KProviderOptions(
            resourceLimits: limits,
            decodingLimits: decodingLimits,
            joinGraceSeconds: 5.0,
            defaultBackend: defaultBackend,
            telemetryHandler: nil
        )
    }

    public init(
        resourceLimits: ResourceLimits = SwiftJ2KProviderOptions.default.resourceLimits,
        decodingLimits: PixelDecodeLimits? = nil,
        joinGraceSeconds: Double = 5.0,
        defaultBackend: CodecBackend? = nil,
        telemetryHandler: (@Sendable (SwiftJ2KOperationRecord) -> Void)? = nil
    ) {
        self.resourceLimits = resourceLimits
        self.decodingLimits = decodingLimits ?? PixelDecodeLimits(
            maximumEncodedBytes: resourceLimits.maximumCompressedBytes,
            maximumDecodedBytes: resourceLimits.maximumDecodedBytes,
            maximumPixels: resourceLimits.maximumPixels
        )
        let clampedGrace = joinGraceSeconds.isFinite ? max(0.05, min(joinGraceSeconds, 30.0)) : 5.0
        self.joinGraceSeconds = clampedGrace
        self.defaultBackend = defaultBackend
        self.telemetryHandler = telemetryHandler
    }

    /// Convenience initialiser attaching a `SwiftJ2KTelemetryCollector`.
    public init(
        resourceLimits: ResourceLimits = SwiftJ2KProviderOptions.default.resourceLimits,
        decodingLimits: PixelDecodeLimits? = nil,
        joinGraceSeconds: Double = 5.0,
        defaultBackend: CodecBackend? = nil,
        collector: SwiftJ2KTelemetryCollector
    ) {
        self.init(
            resourceLimits: resourceLimits,
            decodingLimits: decodingLimits,
            joinGraceSeconds: joinGraceSeconds,
            defaultBackend: defaultBackend,
            telemetryHandler: { collector.record($0) }
        )
    }
}
