// NEMA-verified: 2026a, checked 2026-10-06 — the convenience renderers renderFrame(_:window:), tryRenderFrame(_:window:), renderFrameWithStoredWindow and tryRenderFrameWithStoredWindow apply the window through GrayscaleDisplayPipeline, i.e. after the Modality LUT Sequence or Rescale Slope/Intercept ("after any Modality LUT or Rescale Slope and Intercept specified in the IOD have been applied", PS3.3 2026a C.11.2.1.2.1; chain order PS3.4 2026a N.2), then INVERSE for MONOCHROME1 (C.7.6.3.1.2); the first of several Window Center values is the default presentation (C.11.2.1.2) (D243)
// NEMA-verified: 2026a, checked 2026-09-29 — the non-image SOP Class list diffed by Scripts/diff_kit.py against PS3.6 2026a Table A-1 (two UIDs and two names corrected); JPEG YBR relabel per PS3.5 Table 8.2.1-1
import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// DICOMFile extensions for pixel data access
///
/// Provides convenient methods to access pixel data and render images
/// from a DICOM file.
/// Reference: DICOM PS3.3 C.7.6.3 - Image Pixel Module
extension DICOMFile {
    // MARK: - Pixel Data Access
    
    /// Extracts pixel data from the DICOM file
    ///
    /// Returns the uncompressed pixel data along with its descriptor.
    /// For compressed transfer syntaxes (JPEG, JPEG 2000, RLE), the pixel data
    /// is automatically decompressed using the appropriate codec.
    /// Returns nil if pixel data is not present or cannot be extracted.
    ///
    /// - Returns: PixelData if extraction succeeds
    public func pixelData() -> PixelData? {
        // First try to get uncompressed pixel data directly
        if let uncompressedData = dataSet.pixelData() {
            return uncompressedData
        }
        
        // Check if we have encapsulated (compressed) pixel data
        guard let encapsulated = dataSet.encapsulatedPixelData(),
              let tsUID = transferSyntaxUID else {
            return nil
        }
        
        // Get the codec for this transfer syntax
        guard let codec = CodecRegistry.shared.codec(for: tsUID) else {
            // No codec available for this transfer syntax
            return nil
        }
        
        // Decompress all frames
        let descriptor = encapsulated.descriptor
        var decompressedData = Data()
        
        for frameIndex in 0..<descriptor.numberOfFrames {
            guard let frameData = encapsulated.frameData(at: frameIndex) else {
                // Could not retrieve frame data from encapsulated pixel data
                return nil
            }
            
            do {
                let decompressedFrame = try codec.decodeFrame(
                    frameData,
                    descriptor: descriptor,
                    frameIndex: frameIndex
                )
                decompressedData.append(decompressedFrame)
            } catch {
                // Decompression failed - codec could not decode the compressed frame data
                // This can happen if the compressed data is corrupted or uses an unsupported
                // variant of the compression format
                return nil
            }
        }
        
        // Most registry codecs (J2KSwiftCodec for JPEG 2000 / HTJ2K, plus JPEG-LS /
        // RLE, and SOF3 lossless JPEG) decode to the *source* photometric
        // interpretation, so their bytes still match the data set's Photometric
        // Interpretation and the renderer performs any YBR→RGB conversion itself.
        // JPEG Baseline/Extended (SOF0/SOF1) are the exception — JLIDecoder converts
        // YCbCr→RGB internally — so the tag is corrected to RGB below to avoid a
        // double conversion. Reference: DICOM PS3.3 C.7.6.3.1.2
        return PixelData(
            data: decompressedData,
            descriptor: Self.correctedDescriptorForDecodedBytes(descriptor, transferSyntaxUID: tsUID)
        )
    }

    /// Returns a descriptor whose Photometric Interpretation matches the *decoded*
    /// bytes for JPEG Baseline/Extended sources.
    ///
    /// JLIDecoder converts YCbCr→RGB internally when decoding SOF0/SOF1 lossy JPEG
    /// (PS3.5 Table 8.2.1-1 permits YBR_FULL_422 or RGB going in), so a source tagged
    /// YBR_FULL_422 yields RGB samples. Left uncorrected, `PixelDataRenderer` would
    /// apply a second YBR→RGB conversion — turning black backgrounds green and
    /// foregrounds magenta (the symptom seen on colour US cine loops). This mirrors
    /// the correction in `CompressionManager.decodePixelDataInPlace`. SOF3 lossless
    /// (.57/.70) never applies a colour transform, so its tag already matches and is
    /// left untouched. Reference: DICOM PS3.3 C.7.6.3.1.2
    static func correctedDescriptorForDecodedBytes(
        _ descriptor: PixelDataDescriptor,
        transferSyntaxUID: String
    ) -> PixelDataDescriptor {
        guard (transferSyntaxUID == TransferSyntax.jpegBaseline.uid
                || transferSyntaxUID == TransferSyntax.jpegExtended.uid),
              descriptor.samplesPerPixel == 3,
              descriptor.photometricInterpretation.isYBR else {
            return descriptor
        }
        return PixelDataDescriptor(
            rows: descriptor.rows,
            columns: descriptor.columns,
            numberOfFrames: descriptor.numberOfFrames,
            bitsAllocated: descriptor.bitsAllocated,
            bitsStored: descriptor.bitsStored,
            highBit: descriptor.highBit,
            isSigned: descriptor.isSigned,
            samplesPerPixel: descriptor.samplesPerPixel,
            photometricInterpretation: .rgb,
            planarConfiguration: descriptor.planarConfiguration
        )
    }

    /// Extracts pixel data from the DICOM file, throwing detailed errors on failure
    ///
    /// Returns the uncompressed pixel data along with its descriptor.
    /// For compressed transfer syntaxes (JPEG, JPEG 2000, RLE), the pixel data
    /// is automatically decompressed using the appropriate codec.
    ///
    /// This method provides detailed error information when pixel data extraction fails,
    /// unlike `pixelData()` which simply returns nil.
    ///
    /// - Returns: PixelData if extraction succeeds
    /// - Throws: `PixelDataError` with detailed information about the failure
    ///
    /// Example usage:
    /// ```swift
    /// do {
    ///     let pixelData = try dicomFile.tryPixelData()
    ///     // Use pixel data...
    /// } catch let error as PixelDataError {
    ///     print("Failed to extract pixel data: \(error.description)")
    ///     print("Explanation: \(error.explanation)")
    /// }
    /// ```
    public func tryPixelData() throws -> PixelData {
        // First check if we have a valid descriptor (throws detailed error if missing)
        let descriptor: PixelDataDescriptor
        do {
            descriptor = try dataSet.tryPixelDataDescriptor()
        } catch let error as PixelDataError {
            // If missing attributes and this is a non-image SOP class, provide enhanced error
            if case .missingAttributes(let attributes) = error {
                let sopUID = sopClassUID
                let isNonImage = sopUID.map { Self.isNonImageSOPClass($0) } ?? false
                
                if isNonImage {
                    // This is a known non-image SOP class - provide context
                    let sopName = sopUID.flatMap { UIDDictionary.lookup(uid: $0)?.name }
                    throw PixelDataError.nonImageSOPClass(
                        missingAttributes: attributes,
                        sopClassUID: sopUID,
                        sopClassName: sopName
                    )
                }
            }
            throw error
        }
        
        // Check if pixel data element exists
        guard let pixelDataElement = dataSet[.pixelData] else {
            throw PixelDataError.missingPixelData
        }
        
        // Try to get uncompressed pixel data directly. Native samples are stored in the data
        // set's byte order; normalize 16-bit big-endian samples to little endian so the
        // descriptor and pixels agree (Explicit VR Big Endian, retired — PS3.5 §7.1.2).
        if !pixelDataElement.valueData.isEmpty {
            let bytes = DataSet.nativePixelBytesLittleEndian(
                pixelDataElement.valueData, byteOrder: pixelDataElement.byteOrder,
                bitsAllocated: descriptor.bitsAllocated)
            return PixelData(data: bytes, descriptor: descriptor)
        }
        
        // Check if we have encapsulated (compressed) pixel data
        guard let encapsulated = dataSet.encapsulatedPixelData() else {
            throw PixelDataError.missingPixelData
        }
        
        guard let tsUID = transferSyntaxUID else {
            throw PixelDataError.missingTransferSyntax
        }
        
        // Get the codec for this transfer syntax
        guard let codec = CodecRegistry.shared.codec(for: tsUID) else {
            throw PixelDataError.unsupportedTransferSyntax(tsUID)
        }
        
        // Decompress all frames
        var decompressedData = Data()
        
        for frameIndex in 0..<descriptor.numberOfFrames {
            guard let frameData = encapsulated.frameData(at: frameIndex) else {
                throw PixelDataError.frameExtractionFailed(frameIndex: frameIndex)
            }
            
            do {
                let decompressedFrame = try codec.decodeFrame(
                    frameData,
                    descriptor: descriptor,
                    frameIndex: frameIndex
                )
                decompressedData.append(decompressedFrame)
            } catch {
                throw PixelDataError.decodingFailed(
                    frameIndex: frameIndex,
                    reason: error.localizedDescription
                )
            }
        }
        
        // JPEG Baseline/Extended decode yields RGB even from a YBR-tagged source
        // (JLIDecoder converts internally); correct the descriptor so the renderer
        // does not double-convert. Other codecs decode to the source photometric
        // interpretation and are left unchanged. See the matching note and helper in
        // `pixelData()`. Reference: DICOM PS3.3 C.7.6.3.1.2
        return PixelData(
            data: decompressedData,
            descriptor: Self.correctedDescriptorForDecodedBytes(descriptor, transferSyntaxUID: tsUID)
        )
    }

    /// Creates a PixelDataDescriptor from the file's image pixel attributes
    ///
    /// - Returns: PixelDataDescriptor if all required attributes are present
    public func pixelDataDescriptor() -> PixelDataDescriptor? {
        dataSet.pixelDataDescriptor()
    }
    
    /// Creates a PixelDataDescriptor from the file's image pixel attributes,
    /// throwing detailed errors if required attributes are missing.
    ///
    /// - Returns: PixelDataDescriptor if all required attributes are present
    /// - Throws: `PixelDataError.missingAttributes` with the list of missing attribute names
    public func tryPixelDataDescriptor() throws -> PixelDataDescriptor {
        try dataSet.tryPixelDataDescriptor()
    }
    
    // MARK: - Window Settings
    
    /// Returns the first window settings from the file
    ///
    /// - Returns: WindowSettings if present
    public func windowSettings(frameIndex: Int? = nil) -> WindowSettings? {
        dataSet.windowSettings(frameIndex: frameIndex)
    }

    /// Returns all window settings from the file
    ///
    /// - Parameter frameIndex: For Enhanced multi-frame objects, the frame whose
    ///   Frame VOI LUT functional group supplies the window when there is none at
    ///   the top level.
    /// - Returns: Array of WindowSettings
    public func allWindowSettings(frameIndex: Int? = nil) -> [WindowSettings] {
        dataSet.allWindowSettings(frameIndex: frameIndex)
    }
    
#if canImport(CoreGraphics)
    // MARK: - Image Rendering
    
    /// Renders the specified frame to a CGImage
    ///
    /// Uses automatic windowing based on pixel value range for monochrome images.
    /// For palette color images, uses the palette lookup table from the DICOM file.
    /// - Parameter frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage if rendering succeeds
    public func renderFrame(_ frameIndex: Int = 0) -> CGImage? {
        guard let pixelData = pixelData() else {
            return nil
        }
        
        let lut = dataSet.paletteColorLUT()
        let renderer = PixelDataRenderer(pixelData: pixelData, paletteColorLUT: lut)
        return renderer.renderFrame(frameIndex)
    }
    
    /// Renders the specified frame to a CGImage, throwing detailed errors on failure
    ///
    /// Uses automatic windowing based on pixel value range for monochrome images.
    /// For palette color images, uses the palette lookup table from the DICOM file.
    ///
    /// This method provides detailed error information when pixel data extraction fails,
    /// which is useful for CT and other modality-specific images where understanding
    /// the failure reason is important.
    ///
    /// - Parameter frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage if rendering succeeds
    /// - Throws: `PixelDataError` with detailed information about the failure
    ///
    /// Example usage:
    /// ```swift
    /// do {
    ///     let image = try dicomFile.tryRenderFrame(0)
    ///     // Use rendered image...
    /// } catch let error as PixelDataError {
    ///     print("Failed to render: \(error.description)")
    /// }
    /// ```
    public func tryRenderFrame(_ frameIndex: Int = 0) throws -> CGImage? {
        let pixelData = try tryPixelData()
        
        let lut = dataSet.paletteColorLUT()
        let renderer = PixelDataRenderer(pixelData: pixelData, paletteColorLUT: lut)
        return renderer.renderFrame(frameIndex)
    }
    
    /// Renders the specified frame to a CGImage with custom window settings
    ///
    /// The window is in the units the Modality LUT puts out (Hounsfield units for a
    /// CT, the same units as the file's own Window Center (0028,1050) / Window Width
    /// (0028,1051)): it is applied through ``GrayscaleDisplayPipeline`` after the
    /// Modality LUT Sequence or this frame's Rescale Slope / Intercept, as PS3.3
    /// C.11.2.1.2.1 orders it ("after any Modality LUT or Rescale Slope and Intercept
    /// specified in the IOD have been applied"), then INVERSE for MONOCHROME1
    /// (C.7.6.3.1.2). Before D243 the window was applied to the stored values, so a
    /// CT with Rescale Intercept −1024 rendered misplaced by 1024 (washed out).
    /// Colour and palette frames ignore the window.
    ///
    /// - Parameters:
    ///   - frameIndex: The frame index to render (default 0)
    ///   - window: Window settings in modality (Modality LUT output) units
    /// - Returns: CGImage if rendering succeeds
    public func renderFrame(_ frameIndex: Int = 0, window: WindowSettings) -> CGImage? {
        guard let pixelData = pixelData() else {
            return nil
        }
        
        return renderFrameWithWindow(pixelData: pixelData, frameIndex: frameIndex, window: window)
    }
    
    /// Renders the specified frame to a CGImage with custom window settings,
    /// throwing detailed errors on failure
    ///
    /// The window is in modality (Modality LUT output) units and is applied through
    /// ``GrayscaleDisplayPipeline`` after the Modality LUT, as ``renderFrame(_:window:)``.
    ///
    /// - Parameters:
    ///   - frameIndex: The frame index to render (default 0)
    ///   - window: Window settings in modality (Modality LUT output) units
    /// - Returns: CGImage if rendering succeeds
    /// - Throws: `PixelDataError` with detailed information about the failure
    public func tryRenderFrame(_ frameIndex: Int = 0, window: WindowSettings) throws -> CGImage? {
        let pixelData = try tryPixelData()
        
        return renderFrameWithWindow(pixelData: pixelData, frameIndex: frameIndex, window: window)
    }
    
    /// Renders the specified frame using window settings from the DICOM file
    ///
    /// The file's Window Center (0028,1050) / Window Width (0028,1051) — this frame's
    /// Frame VOI LUT functional group on an Enhanced object, else the shared pair; the
    /// first of several values is the default presentation (PS3.3 C.11.2.1.2) — is
    /// applied after the Modality LUT through ``GrayscaleDisplayPipeline`` (D243).
    /// Falls back to automatic windowing if no window settings are present.
    /// - Parameter frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage if rendering succeeds
    public func renderFrameWithStoredWindow(_ frameIndex: Int = 0) -> CGImage? {
        if let window = headerWindow(frameIndex: frameIndex) {
            return renderFrame(frameIndex, window: window)
        } else {
            return renderFrame(frameIndex)
        }
    }
    
    /// Renders the specified frame using window settings from the DICOM file,
    /// throwing detailed errors on failure
    ///
    /// Falls back to automatic windowing if no window settings are present.
    /// This method provides detailed error information when pixel data extraction fails.
    ///
    /// - Parameter frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage if rendering succeeds
    /// - Throws: `PixelDataError` with detailed information about the failure
    public func tryRenderFrameWithStoredWindow(_ frameIndex: Int = 0) throws -> CGImage? {
        if let window = headerWindow(frameIndex: frameIndex) {
            return try tryRenderFrame(frameIndex, window: window)
        } else {
            return try tryRenderFrame(frameIndex)
        }
    }
    
    // MARK: - Private Rendering Helpers
    
    /// The file's default window for a frame: the first of several Window Center /
    /// Window Width values (the default presentation, PS3.3 C.11.2.1.2), read from this
    /// frame's functional group on an Enhanced object, else the shared pair.
    private func headerWindow(frameIndex: Int) -> WindowSettings? {
        allWindowSettings(frameIndex: frameIndex).first ?? windowSettings(frameIndex: frameIndex)
    }

    /// Internal helper to render a frame with window settings using provided pixel data.
    ///
    /// A monochrome frame goes through the PS3.4 N.2 chain — this frame's Modality LUT,
    /// then the window in modality units, then INVERSE for MONOCHROME1 — so the window
    /// is placed where PS3.3 C.11.2.1.2.1 places it (D243).
    private func renderFrameWithWindow(pixelData: PixelData, frameIndex: Int, window: WindowSettings) -> CGImage? {
        let lut = dataSet.paletteColorLUT()
        let renderer = PixelDataRenderer(pixelData: pixelData, paletteColorLUT: lut)
        
        if pixelData.descriptor.photometricInterpretation.isMonochrome {
            let pipeline = GrayscaleDisplayPipeline.standard(
                for: pixelData.descriptor.photometricInterpretation,
                modalityLUT: modalityLUT(frameIndex: frameIndex), voiLUT: VOILUT(window))
            return renderer.renderMonochromeFrame(frameIndex, pipeline: pipeline)
        } else if pixelData.descriptor.photometricInterpretation.isPaletteColor {
            return renderer.renderPaletteColorFrame(frameIndex)
        } else {
            return renderer.renderColorFrame(frameIndex)
        }
    }
#endif
    
    // MARK: - Image Dimensions
    
    /// Returns the number of rows (height) in the image
    public var imageRows: Int? {
        dataSet.imageRows
    }
    
    /// Returns the number of columns (width) in the image
    public var imageColumns: Int? {
        dataSet.imageColumns
    }
    
    /// Returns the number of frames in the image
    public var numberOfFrames: Int? {
        dataSet.numberOfFrames
    }
    
    /// Whether this file contains multi-frame image data
    public var isMultiFrame: Bool {
        (numberOfFrames ?? 1) > 1
    }
    
    // MARK: - Photometric Interpretation
    
    /// Returns the photometric interpretation
    public var photometricInterpretation: PhotometricInterpretation? {
        dataSet.photometricInterpretation
    }
    
    /// Whether the image data is monochrome
    public var isMonochrome: Bool {
        photometricInterpretation?.isMonochrome ?? false
    }
    
    /// Whether the image data is color
    public var isColor: Bool {
        photometricInterpretation?.isColor ?? false
    }
    
    /// Whether the image data uses palette color lookup tables
    public var isPaletteColor: Bool {
        photometricInterpretation?.isPaletteColor ?? false
    }
    
    // MARK: - Palette Color Lookup Table
    
    /// Returns the palette color lookup table for PALETTE COLOR images
    ///
    /// - Returns: PaletteColorLUT if present and valid
    public func paletteColorLUT() -> PaletteColorLUT? {
        dataSet.paletteColorLUT()
    }
    
    // MARK: - Pixel Value Range
    
    /// Calculates the actual pixel value range in the specified frame
    ///
    /// - Parameter frameIndex: The frame index (default 0)
    /// - Returns: Tuple of (min, max) values if available
    public func pixelRange(forFrame frameIndex: Int = 0) -> (min: Int, max: Int)? {
        pixelData()?.pixelRange(forFrame: frameIndex)
    }
    
    // MARK: - Rescale Values
    
    /// The Modality LUT of a frame (PS3.3 2026a C.11.1): the Modality LUT Sequence
    /// (0028,3000) when the file has one, else this frame's Rescale Slope (0028,1053) /
    /// Rescale Intercept (0028,1052) (the Pixel Value Transformation functional group
    /// on an Enhanced object, else the shared pair); `nil` when that is the identity
    /// (slope 1, intercept 0). The sequence and the rescale pair are mutually
    /// exclusive (C.11.1.1.2), so the sequence wins when both are present.
    public func modalityLUT(frameIndex: Int? = nil) -> ModalityLUT? {
        if let table = dataSet.modalityLUTData() {
            return .lut(table)
        }
        let slope = rescaleSlope(frameIndex: frameIndex)
        let intercept = rescaleIntercept(frameIndex: frameIndex)
        return (slope == 1 && intercept == 0)
            ? nil : .rescale(slope: slope, intercept: intercept, type: nil)
    }

    /// Returns the rescale intercept value
    public func rescaleIntercept(frameIndex: Int? = nil) -> Double {
        dataSet.rescaleIntercept(frameIndex: frameIndex)
    }

    /// Returns the rescale slope value
    public func rescaleSlope(frameIndex: Int? = nil) -> Double {
        dataSet.rescaleSlope(frameIndex: frameIndex)
    }
    
    /// Applies the rescale transformation to a pixel value
    ///
    /// OutputUnits = Rescale Slope * StoredValue + Rescale Intercept
    ///
    /// - Parameter storedValue: The stored pixel value
    /// - Returns: The rescaled value in output units
    public func rescale(_ storedValue: Double) -> Double {
        dataSet.rescale(storedValue)
    }

    /// Applies the modality transformation of frame `frameIndex` (0-based), using that frame's
    /// Pixel Value Transformation functional group (PS3.3 2026a C.7.6.16.2.9; D197).
    public func rescale(_ storedValue: Double, frameIndex: Int?) -> Double {
        dataSet.rescale(storedValue, frameIndex: frameIndex)
    }
    
    // MARK: - SOP Class Helpers
    
    /// The SOP Classes whose IOD carries no pixel data: every SOP Class PS3.4 2026a
    /// Table B.5-1 (Storage) or Table GG.3-1 (Non-Patient Object Storage) links to an
    /// IOD whose module table names none of the Image Pixel (C.7.6.3), Floating Point
    /// Image Pixel (C.7.6.24) or Double Floating Point Image Pixel (C.7.6.25) Modules.
    ///
    /// NEMA-verified: 2026a, checked 2026-09-30 — generated by `Scripts/diff_kit.py
    /// --emit-non-image-swift` from PS3.4 2026a Tables B.5-1 / GG.3-1 and the PS3.3 2026a
    /// IOD module tables; 113 of 179 SOP Classes (was 82, 31 missing). Do not hand-edit.
    private static let nonImageSOPClasses: Set<String> = [
        "1.2.840.10008.5.1.4.1.1.4.2",         // MR Spectroscopy Storage
        "1.2.840.10008.5.1.4.1.1.9.1.1",       // 12-lead ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.1.2",       // General ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.1.3",       // Ambulatory ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.1.4",       // General 32-bit ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.2.1",       // Hemodynamic Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.3.1",       // Cardiac Electrophysiology Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.4.1",       // Basic Voice Audio Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.4.2",       // General Audio Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.5.1",       // Arterial Pulse Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.6.1",       // Respiratory Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.6.2",       // Multi-channel Respiratory Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.1",       // Routine Scalp Electroencephalogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.2",       // Electromyogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.3",       // Electrooculogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.4",       // Sleep Electroencephalogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.8.1",       // Body Position Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.100.1",     // Waveform Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.9.100.2",     // Waveform Acquisition Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.1",        // Grayscale Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.2",        // Color Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.3",        // Pseudo-Color Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.4",        // Blending Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.5",        // XA/XRF Grayscale Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.6",        // Grayscale Planar MPR Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.7",        // Compositing Planar MPR Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.8",        // Advanced Blending Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.9",        // Volume Rendering Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.10",       // Segmented Volume Rendering Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.11",       // Multiple Volume Rendering Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.12",       // Variable Modality LUT Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.66",          // Raw Data Storage
        "1.2.840.10008.5.1.4.1.1.66.1",        // Spatial Registration Storage
        "1.2.840.10008.5.1.4.1.1.66.2",        // Spatial Fiducials Storage
        "1.2.840.10008.5.1.4.1.1.66.3",        // Deformable Spatial Registration Storage
        "1.2.840.10008.5.1.4.1.1.66.5",        // Surface Segmentation Storage
        "1.2.840.10008.5.1.4.1.1.66.6",        // Tractography Results Storage
        "1.2.840.10008.5.1.4.1.1.67",          // Real World Value Mapping Storage
        "1.2.840.10008.5.1.4.1.1.68.1",        // Surface Scan Mesh Storage
        "1.2.840.10008.5.1.4.1.1.68.2",        // Surface Scan Point Cloud Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.3",    // Stereometric Relationship Storage
        "1.2.840.10008.5.1.4.1.1.78.1",        // Lensometry Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.2",        // Autorefraction Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.3",        // Keratometry Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.4",        // Subjective Refraction Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.5",        // Visual Acuity Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.6",        // Spectacle Prescription Report Storage
        "1.2.840.10008.5.1.4.1.1.78.7",        // Ophthalmic Axial Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.8",        // Intraocular Lens Calculations Storage
        "1.2.840.10008.5.1.4.1.1.79.1",        // Macular Grid Thickness and Volume Report
        "1.2.840.10008.5.1.4.1.1.80.1",        // Ophthalmic Visual Field Static Perimetry Measurements Storage
        "1.2.840.10008.5.1.4.1.1.88.11",       // Basic Text SR Storage
        "1.2.840.10008.5.1.4.1.1.88.22",       // Enhanced SR Storage
        "1.2.840.10008.5.1.4.1.1.88.33",       // Comprehensive SR Storage
        "1.2.840.10008.5.1.4.1.1.88.34",       // Comprehensive 3D SR Storage
        "1.2.840.10008.5.1.4.1.1.88.35",       // Extensible SR Storage
        "1.2.840.10008.5.1.4.1.1.88.40",       // Procedure Log Storage
        "1.2.840.10008.5.1.4.1.1.88.50",       // Mammography CAD SR Storage
        "1.2.840.10008.5.1.4.1.1.88.59",       // Key Object Selection Document Storage
        "1.2.840.10008.5.1.4.1.1.88.65",       // Chest CAD SR Storage
        "1.2.840.10008.5.1.4.1.1.88.67",       // X-Ray Radiation Dose SR Storage
        "1.2.840.10008.5.1.4.1.1.88.68",       // Radiopharmaceutical Radiation Dose SR Storage
        "1.2.840.10008.5.1.4.1.1.88.69",       // Colon CAD SR Storage
        "1.2.840.10008.5.1.4.1.1.88.70",       // Implantation Plan SR Storage
        "1.2.840.10008.5.1.4.1.1.88.71",       // Acquisition Context SR Storage
        "1.2.840.10008.5.1.4.1.1.88.72",       // Simplified Adult Echo SR Storage
        "1.2.840.10008.5.1.4.1.1.88.73",       // Patient Radiation Dose SR Storage
        "1.2.840.10008.5.1.4.1.1.88.74",       // Planned Imaging Agent Administration SR Storage
        "1.2.840.10008.5.1.4.1.1.88.75",       // Performed Imaging Agent Administration SR Storage
        "1.2.840.10008.5.1.4.1.1.88.76",       // Enhanced X-Ray Radiation Dose SR Storage
        "1.2.840.10008.5.1.4.1.1.88.77",       // Waveform Annotation SR Storage
        "1.2.840.10008.5.1.4.1.1.90.1",        // Content Assessment Results Storage
        "1.2.840.10008.5.1.4.1.1.91.1",        // Microscopy Bulk Simple Annotations Storage
        "1.2.840.10008.5.1.4.1.1.104.1",       // Encapsulated PDF Storage
        "1.2.840.10008.5.1.4.1.1.104.2",       // Encapsulated CDA Storage
        "1.2.840.10008.5.1.4.1.1.104.3",       // Encapsulated STL Storage
        "1.2.840.10008.5.1.4.1.1.104.4",       // Encapsulated OBJ Storage
        "1.2.840.10008.5.1.4.1.1.104.5",       // Encapsulated MTL Storage
        "1.2.840.10008.5.1.4.1.1.131",         // Basic Structured Display Storage
        "1.2.840.10008.5.1.4.1.1.200.1",       // CT Defined Procedure Protocol Storage
        "1.2.840.10008.5.1.4.1.1.200.2",       // CT Performed Procedure Protocol Storage
        "1.2.840.10008.5.1.4.1.1.200.3",       // Protocol Approval Storage
        "1.2.840.10008.5.1.4.1.1.200.7",       // XA Defined Procedure Protocol Storage
        "1.2.840.10008.5.1.4.1.1.200.8",       // XA Performed Procedure Protocol Storage
        "1.2.840.10008.5.1.4.1.1.201.1",       // Inventory Storage
        "1.2.840.10008.5.1.4.1.1.481.3",       // RT Structure Set Storage
        "1.2.840.10008.5.1.4.1.1.481.4",       // RT Beams Treatment Record Storage
        "1.2.840.10008.5.1.4.1.1.481.5",       // RT Plan Storage
        "1.2.840.10008.5.1.4.1.1.481.6",       // RT Brachy Treatment Record Storage
        "1.2.840.10008.5.1.4.1.1.481.7",       // RT Treatment Summary Record Storage
        "1.2.840.10008.5.1.4.1.1.481.8",       // RT Ion Plan Storage
        "1.2.840.10008.5.1.4.1.1.481.9",       // RT Ion Beams Treatment Record Storage
        "1.2.840.10008.5.1.4.1.1.481.10",      // RT Physician Intent Storage
        "1.2.840.10008.5.1.4.1.1.481.11",      // RT Segment Annotation Storage
        "1.2.840.10008.5.1.4.1.1.481.12",      // RT Radiation Set Storage
        "1.2.840.10008.5.1.4.1.1.481.13",      // C-Arm Photon-Electron Radiation Storage
        "1.2.840.10008.5.1.4.1.1.481.14",      // Tomotherapeutic Radiation Storage
        "1.2.840.10008.5.1.4.1.1.481.15",      // Robotic-Arm Radiation Storage
        "1.2.840.10008.5.1.4.1.1.481.16",      // RT Radiation Record Set Storage
        "1.2.840.10008.5.1.4.1.1.481.17",      // RT Radiation Salvage Record Storage
        "1.2.840.10008.5.1.4.1.1.481.18",      // Tomotherapeutic Radiation Record Storage
        "1.2.840.10008.5.1.4.1.1.481.19",      // C-Arm Photon-Electron Radiation Record Storage
        "1.2.840.10008.5.1.4.1.1.481.20",      // Robotic Radiation Record Storage
        "1.2.840.10008.5.1.4.1.1.481.21",      // RT Radiation Set Delivery Instruction Storage
        "1.2.840.10008.5.1.4.1.1.481.22",      // RT Treatment Preparation Storage
        "1.2.840.10008.5.1.4.1.1.481.25",      // RT Patient Position Acquisition Instruction Storage
        "1.2.840.10008.5.1.4.34.7",            // RT Beams Delivery Instruction Storage
        "1.2.840.10008.5.1.4.34.10",           // RT Brachy Application Setup Delivery Instruction Storage
        "1.2.840.10008.5.1.4.38.1",            // Hanging Protocol Storage
        "1.2.840.10008.5.1.4.39.1",            // Color Palette Storage
        "1.2.840.10008.5.1.4.43.1",            // Generic Implant Template Storage
        "1.2.840.10008.5.1.4.44.1",            // Implant Assembly Template Storage
        "1.2.840.10008.5.1.4.45.1",            // Implant Template Group Storage
    ]
    
    /// Checks if a SOP Class UID represents a non-image DICOM object
    ///
    /// Non-image SOP classes include Structured Reports, Presentation States,
    /// Waveforms, and other document-based DICOM objects that do not contain pixel data.
    ///
    /// - Parameter sopClassUID: The SOP Class UID to check
    /// - Returns: true if the SOP class is known to be a non-image type
    private static func isNonImageSOPClass(_ sopClassUID: String) -> Bool {
        return nonImageSOPClasses.contains(sopClassUID)
    }
    
}
