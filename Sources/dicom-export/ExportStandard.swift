// NEMA-verified: 2026a, checked 2026-10-06 — no DICOM rule of its own since D252: the cine rate of PS3.3 2026a Table C.7-13, Burned In Annotation (0028,0301) of Table C.7-9 and the Frame-number texts of Table 10-3 are DICOMKit DICOMImageExporter.CineFrameRate / .BurnedInAnnotation / .FrameSelection / .FrameSelectionConflict / .ApplyWindowDeprecation, which the tool calls; the deprecated typealiases below only forward for the tests and DICOMStudio's copy; the frame render goes through DICOMImageExporter.renderFrameForExport (PS3.4 N.2 chain, verified in DICOMKit)
import Foundation
import DICOMCore
import DICOMKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The pre-D252 name of ``DICOMImageExporter/CineFrameRate`` (PS3.3 Table C.7-13).
@available(*, deprecated, renamed: "DICOMImageExporter.CineFrameRate", message: "lifted into DICOMKit (D252)")
typealias CineFrameRate = DICOMImageExporter.CineFrameRate

/// The pre-D252 name of ``DICOMImageExporter/BurnedInAnnotation`` (PS3.3 Table C.7-9).
@available(*, deprecated, renamed: "DICOMImageExporter.BurnedInAnnotation", message: "lifted into DICOMKit (D252)")
typealias BurnedInAnnotation = DICOMImageExporter.BurnedInAnnotation

/// The pre-D252 name of ``DICOMImageExporter/FrameSelection`` (PS3.3 Table 10-3).
@available(*, deprecated, renamed: "DICOMImageExporter.FrameSelection", message: "lifted into DICOMKit (D252)")
typealias ExportFrameSelection = DICOMImageExporter.FrameSelection

/// The pre-D252 name of ``DICOMImageExporter/FrameSelectionConflict``. Not a
/// `ValidationError`, so the command exits 1 with its message.
@available(*, deprecated, renamed: "DICOMImageExporter.FrameSelectionConflict", message: "lifted into DICOMKit (D252)")
typealias ExportFrameSelectionConflict = DICOMImageExporter.FrameSelectionConflict

/// The pre-D252 name of ``DICOMImageExporter/ApplyWindowDeprecation`` (P-EXPORT-3).
@available(*, deprecated, renamed: "DICOMImageExporter.ApplyWindowDeprecation", message: "lifted into DICOMKit (D252)")
typealias ExportApplyWindowDeprecation = DICOMImageExporter.ApplyWindowDeprecation

// The tool's own I/O: the engine types return texts, the CLI prints them to stderr.
extension DICOMImageExporter.BurnedInAnnotation {
    static func printWarning(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

extension DICOMImageExporter.FrameSelection {
    static func printNote(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

#if canImport(CoreGraphics)
/// The one frame-render decision for every `dicom-export` subcommand: the shared
/// DICOMImageExporter.renderFrameForExport (the PS3.4 N.2 grayscale chain — Modality
/// LUT or rescale, then the VOI in modality units, then INVERSE for MONOCHROME1).
/// `contact-sheet` and `animate` used other DICOMFile render paths before.
enum ExportFrames {
    static func render(
        file: DICOMFile, pixelData: PixelData? = nil, frameIndex: Int,
        applyWindow: Bool, windowCenter: Double?, windowWidth: Double?
    ) throws -> CGImage {
        guard let pixelData = pixelData ?? file.pixelData() else { throw ExportError.noPixelData }
        return try DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pixelData, frameIndex: frameIndex,
            applyWindow: applyWindow, windowCenter: windowCenter, windowWidth: windowWidth)
    }
}
#endif
