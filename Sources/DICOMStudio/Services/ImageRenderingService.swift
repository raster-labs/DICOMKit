// ImageRenderingService.swift
// DICOMStudio
//
// DICOM Studio — Image rendering service wrapping DICOMKit APIs
//
// NEMA-verified: 2026a, checked 2026-10-05 — frames are now rendered through DICOMKit's `DICOMImageExporter.renderFrameForExport`, i.e. the PS3.4 2026a N.2 chain: the file's Modality LUT, then the window in the units it puts out (PS3.3 C.11.2.1.2.1), then the Presentation LUT the photometric implies; the service used `DICOMFile.renderFrame(_:window:)` / `renderFrameWithStoredWindow`, which apply the header's window to stored values and so misplace it by the rescale (D65): corrected; the window parameters are documented as modality units; descriptor and header-window reads carry no standard data of their own; checked by Scripts/diff_studio_g2_viewer.py

import Foundation
import DICOMKit
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Service for rendering DICOM images from files.
///
/// Wraps DICOMKit rendering APIs providing a clean interface for the ViewModel layer.
/// Handles pixel data extraction, window/level application, and frame rendering.
public final class ImageRenderingService: Sendable {

    public init() {}

    #if canImport(CoreGraphics)

    /// Renders a specific frame from a DICOM file.
    ///
    /// Through the PS3.4 N.2 chain — the file's Modality LUT, then the window
    /// applied to its output (PS3.3 C.11.2.1.2.1), then the Presentation LUT
    /// the photometric implies — by the policy shared with export and the
    /// viewer, ``DICOMImageExporter/renderFrameForExport``.
    ///
    /// - Parameters:
    ///   - filePath: Path to the DICOM file.
    ///   - frameIndex: Frame index (0-based).
    ///   - windowCenter: Optional Window Center, in the units the Modality LUT
    ///     puts out (HU on CT) — the header's units, not stored values.
    ///   - windowWidth: Optional Window Width, in the same units.
    /// - Returns: Rendered CGImage, or nil if rendering fails.
    /// - Throws: Error if the file cannot be read.
    public func renderFrame(
        filePath: String,
        frameIndex: Int = 0,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil
    ) throws -> CGImage? {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        let file = try DICOMFile.read(from: data)
        return renderFrame(from: file, frameIndex: frameIndex,
                           windowCenter: windowCenter, windowWidth: windowWidth)
    }

    /// Renders a frame using a DICOMFile that has already been parsed.
    ///
    /// Same chain as ``renderFrame(filePath:frameIndex:windowCenter:windowWidth:)``.
    /// Without a window the file's own VOI is resolved: its Window Center /
    /// Width, else its VOI LUT Sequence, else the frame's range.
    ///
    /// - Parameters:
    ///   - file: The parsed DICOMFile.
    ///   - frameIndex: Frame index (0-based).
    ///   - windowCenter: Optional Window Center, in modality units.
    ///   - windowWidth: Optional Window Width, in modality units.
    /// - Returns: Rendered CGImage, or nil if rendering fails.
    public func renderFrame(
        from file: DICOMFile,
        frameIndex: Int = 0,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil
    ) -> CGImage? {
        guard let pixelData = file.pixelData() else { return nil }
        let explicit = windowCenter != nil && windowWidth != nil
        return try? DICOMImageExporter.renderFrameForExport(
            file: file, pixelData: pixelData, frameIndex: frameIndex,
            applyWindow: explicit, windowCenter: windowCenter, windowWidth: windowWidth)
    }

    #endif

    /// Extracts pixel data descriptor from a DICOM file.
    ///
    /// - Parameter filePath: Path to the DICOM file.
    /// - Returns: PixelDataDescriptor, or nil if not available.
    /// - Throws: Error if the file cannot be read.
    public func pixelDataDescriptor(filePath: String) throws -> PixelDataDescriptor? {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        let file = try DICOMFile.read(from: data)
        return file.pixelDataDescriptor()
    }

    /// Extracts window settings from a DICOM file.
    ///
    /// - Parameter filePath: Path to the DICOM file.
    /// - Returns: Array of window settings from the file header.
    /// - Throws: Error if the file cannot be read.
    public func windowSettings(filePath: String) throws -> [WindowSettings] {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        let file = try DICOMFile.read(from: data)
        return file.allWindowSettings()
    }
}
