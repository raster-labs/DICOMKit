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

    /// Default bounded per-frame options aligned with `PixelDecodeLimits.default` (64 MiB encoded, 256 MiB decoded, 64M pixels, multi-worker, 120s deadline).
    public static let `default`: SwiftJ2KProviderOptions = {
        let defaultWorkers = min(max(1, ProcessInfo.processInfo.activeProcessorCount), 16)
        let limits = (try? ResourceLimits(
            maximumCompressedBytes: 64 << 20,
            maximumDecodedBytes: 256 << 20,
            maximumWorkspaceBytes: 2 << 30,
            maximumPixels: 64 << 20,
            maximumDimension: 65_535,
            maximumFrames: 1,
            maximumMetadataBytes: 4 << 20,
            maximumICCBytes: 4 << 20,
            maximumNestingDepth: 16,
            maximumWorkers: defaultWorkers,
            deadlineSeconds: 120.0,
            maximumMemoryBytes: 4 << 30
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
        let defaultWorkers = min(max(1, ProcessInfo.processInfo.activeProcessorCount), 16)
        let maxEncoded = max(1, decodingLimits.maximumEncodedBytes)
        let maxDecoded = max(1, decodingLimits.maximumDecodedBytes)
        let maxPixels = max(1, decodingLimits.maximumPixels)
        let (ws8, wsOv) = maxDecoded.multipliedReportingOverflow(by: 8)
        let (px24, pxOv) = maxPixels.multipliedReportingOverflow(by: 24)
        let (pxWorkspace, pxWsOv) = px24.addingReportingOverflow(64 << 20)
        let maxWorkspace = max(
            512 << 20,
            max(wsOv ? (4 << 30) : ws8, (pxOv || pxWsOv) ? (4 << 30) : pxWorkspace)
        )
        let (mem2, memOv) = maxWorkspace.multipliedReportingOverflow(by: 2)
        let maxMemory = max(1024 << 20, max(maxWorkspace, memOv ? (8 << 30) : mem2))
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
            maximumWorkers: defaultWorkers,
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
