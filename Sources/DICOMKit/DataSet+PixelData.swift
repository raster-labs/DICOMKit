// NEMA-verified: 2026a, checked 2026-10-01 — Image Pixel (C.7.6.3), Modality LUT (C.11.1), VOI (C.11.2), Palette (C.7.9) and functional-group (C.7.6.16) reads checked against PS3.3 2026a; rescale(_:frameIndex:) reads the per-frame Pixel Value Transformation Sequence (C.7.6.16.2.9, D197); defaults for absent Type 1 attributes are recorded as robustness choices
import Foundation
import DICOMCore

/// DataSet extensions for pixel data access
///
/// Provides convenient methods to extract pixel data and related attributes
/// from a DICOM data set.
/// Reference: DICOM PS3.3 C.7.6.3 - Image Pixel Module
extension DataSet {
    // MARK: - Pixel Data Descriptor
    
    /// Creates a PixelDataDescriptor from the data set's image pixel attributes
    ///
    /// Extracts all necessary attributes to describe the pixel data format.
    /// Returns nil if required attributes are missing.
    ///
    /// - Returns: PixelDataDescriptor if all required attributes are present
    public func pixelDataDescriptor() -> PixelDataDescriptor? {
        // Required attributes
        guard let rows = uint16(for: .rows),
              let columns = uint16(for: .columns),
              let bitsAllocated = uint16(for: .bitsAllocated),
              let bitsStored = uint16(for: .bitsStored),
              let highBit = uint16(for: .highBit),
              let pixelRepresentation = uint16(for: .pixelRepresentation) else {
            return nil
        }
        
        // Photometric Interpretation (required for image data)
        let photometricString = string(for: .photometricInterpretation) ?? "MONOCHROME2"
        guard let photometricInterpretation = PhotometricInterpretation.parse(photometricString) else {
            return nil
        }
        
        // Optional attributes with defaults
        let samplesPerPixel = uint16(for: .samplesPerPixel) ?? 1
        let planarConfiguration = uint16(for: .planarConfiguration) ?? 0
        
        // Number of frames (default 1 for single-frame images)
        let numberOfFrames: Int
        if let frameString = string(for: .numberOfFrames),
           let frames = Int(frameString.trimmingCharacters(in: .whitespaces)) {
            numberOfFrames = frames
        } else {
            numberOfFrames = 1
        }
        
        return PixelDataDescriptor(
            rows: Int(rows),
            columns: Int(columns),
            numberOfFrames: numberOfFrames,
            bitsAllocated: Int(bitsAllocated),
            bitsStored: Int(bitsStored),
            highBit: Int(highBit),
            isSigned: pixelRepresentation != 0,
            samplesPerPixel: Int(samplesPerPixel),
            photometricInterpretation: photometricInterpretation,
            planarConfiguration: Int(planarConfiguration)
        )
    }
    
    /// Creates a PixelDataDescriptor from the data set's image pixel attributes,
    /// throwing detailed errors if required attributes are missing.
    ///
    /// Extracts all necessary attributes to describe the pixel data format.
    /// If any required attribute is missing, throws a detailed error indicating
    /// which specific attributes are not present.
    ///
    /// - Returns: PixelDataDescriptor if all required attributes are present
    /// - Throws: `PixelDataError.missingAttributes` with the list of missing attribute names
    public func tryPixelDataDescriptor() throws -> PixelDataDescriptor {
        // Track missing or invalid required attributes
        var issues: [String] = []
        
        // Collect all required attributes
        let rows = uint16(for: .rows)
        if rows == nil { issues.append("Rows (0028,0010)") }
        
        let columns = uint16(for: .columns)
        if columns == nil { issues.append("Columns (0028,0011)") }
        
        let bitsAllocated = uint16(for: .bitsAllocated)
        if bitsAllocated == nil { issues.append("Bits Allocated (0028,0100)") }
        
        let bitsStored = uint16(for: .bitsStored)
        if bitsStored == nil { issues.append("Bits Stored (0028,0101)") }
        
        let highBit = uint16(for: .highBit)
        if highBit == nil { issues.append("High Bit (0028,0102)") }
        
        let pixelRepresentation = uint16(for: .pixelRepresentation)
        if pixelRepresentation == nil { issues.append("Pixel Representation (0028,0103)") }
        
        // Photometric Interpretation check - only report if truly missing or invalid
        let photometricString = string(for: .photometricInterpretation)
        let photometricInterpretation: PhotometricInterpretation?
        if let piString = photometricString {
            photometricInterpretation = PhotometricInterpretation.parse(piString)
            if photometricInterpretation == nil {
                issues.append("Photometric Interpretation (0028,0004) - unrecognized value: '\(piString)'")
            }
        } else {
            // Default to MONOCHROME2 if not present
            photometricInterpretation = .monochrome2
        }
        
        // If any required attributes are missing or invalid, throw a detailed error
        if !issues.isEmpty {
            throw PixelDataError.missingAttributes(issues)
        }
        
        // At this point, all required values are guaranteed to be valid
        // Use guard-let to make the non-nil guarantees explicit
        guard let validRows = rows,
              let validColumns = columns,
              let validBitsAllocated = bitsAllocated,
              let validBitsStored = bitsStored,
              let validHighBit = highBit,
              let validPixelRepresentation = pixelRepresentation,
              let validPhotometric = photometricInterpretation else {
            // This should never happen due to earlier checks, but provides safety
            throw PixelDataError.missingDescriptor
        }
        
        // Optional attributes with defaults
        let samplesPerPixel = uint16(for: .samplesPerPixel) ?? 1
        let planarConfiguration = uint16(for: .planarConfiguration) ?? 0
        
        // Number of frames (default 1 for single-frame images)
        let numberOfFrames: Int
        if let frameString = string(for: .numberOfFrames),
           let frames = Int(frameString.trimmingCharacters(in: .whitespaces)) {
            numberOfFrames = frames
        } else {
            numberOfFrames = 1
        }
        
        return PixelDataDescriptor(
            rows: Int(validRows),
            columns: Int(validColumns),
            numberOfFrames: numberOfFrames,
            bitsAllocated: Int(validBitsAllocated),
            bitsStored: Int(validBitsStored),
            highBit: Int(validHighBit),
            isSigned: validPixelRepresentation != 0,
            samplesPerPixel: Int(samplesPerPixel),
            photometricInterpretation: validPhotometric,
            planarConfiguration: Int(planarConfiguration)
        )
    }
    
    // MARK: - Pixel Data Extraction
    
    /// Extracts pixel data from the data set
    ///
    /// Returns the uncompressed pixel data along with its descriptor.
    /// Returns nil if pixel data is not present or cannot be extracted.
    ///
    /// - Returns: PixelData if extraction succeeds
    public func pixelData() -> PixelData? {
        guard let descriptor = pixelDataDescriptor() else {
            return nil
        }
        
        // Get the pixel data element
        guard let element = self[.pixelData],
              !element.valueData.isEmpty else {
            return nil
        }

        let bytes = Self.nativePixelBytesLittleEndian(
            element.valueData, byteOrder: element.byteOrder, bitsAllocated: descriptor.bitsAllocated)
        return PixelData(data: bytes, descriptor: descriptor)
    }
    
    /// Extracts uncompressed pixel data from the data set, throwing detailed errors on failure
    ///
    /// Returns the uncompressed pixel data along with its descriptor.
    /// This method only handles uncompressed pixel data; for compressed data,
    /// use `DICOMFile.tryPixelData()` instead.
    ///
    /// - Returns: PixelData if extraction succeeds
    /// - Throws: `PixelDataError` with detailed information about the failure
    public func tryPixelData() throws -> PixelData {
        // First check if we have a valid descriptor (throws detailed error if missing)
        let descriptor = try tryPixelDataDescriptor()
        
        // Get the pixel data element
        guard let element = self[.pixelData] else {
            throw PixelDataError.missingPixelData
        }
        
        // Check if the pixel data has non-empty value data (uncompressed)
        guard !element.valueData.isEmpty else {
            throw PixelDataError.missingPixelData
        }

        let bytes = Self.nativePixelBytesLittleEndian(
            element.valueData, byteOrder: element.byteOrder, bitsAllocated: descriptor.bitsAllocated)
        return PixelData(data: bytes, descriptor: descriptor)
    }
    
    // MARK: - Native Pixel Byte Order

    /// Normalizes native (uncompressed) pixel bytes to LITTLE ENDIAN.
    ///
    /// Uncompressed pixel samples are stored in the data set's byte order, so a data set that
    /// uses the retired **Explicit VR Big Endian** transfer syntax (1.2.840.10008.1.2.2) has
    /// big-endian 16-bit samples. Consumers (this library's renderer and downstream callers)
    /// assume little endian, so a big-endian frame would otherwise read byte-swapped (noise).
    /// This swaps each 16-bit sample so callers always see one convention. 8-bit samples are
    /// byte-order independent and 32-bit float pixels (rare) fall through unchanged here — only
    /// the common 16-bit case is normalized. Reference: PS3.5 §7.1.2, PS3.3 C.7.6.3.1.2.
    static func nativePixelBytesLittleEndian(_ data: Data, byteOrder: ByteOrder, bitsAllocated: Int) -> Data {
        guard byteOrder == .bigEndian, bitsAllocated == 16 else { return data }
        var bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count {
            bytes.swapAt(i, i + 1)
            i += 2
        }
        return Data(bytes)
    }

    // MARK: - Encapsulated Pixel Data Extraction

    /// Extracts encapsulated (compressed) pixel data from the data set
    ///
    /// Returns the encapsulated pixel data including offset table and fragments.
    /// Returns nil if encapsulated pixel data is not present.
    ///
    /// - Returns: EncapsulatedPixelData if extraction succeeds
    public func encapsulatedPixelData() -> EncapsulatedPixelData? {
        guard let descriptor = pixelDataDescriptor() else {
            return nil
        }
        
        // Get the pixel data element
        guard let element = self[.pixelData] else {
            return nil
        }
        
        // If the element has encapsulated fragments, use those
        if let fragments = element.encapsulatedFragments, !fragments.isEmpty {
            let offsetTable = element.encapsulatedOffsetTable ?? []
            return EncapsulatedPixelData(
                offsetTable: offsetTable,
                fragments: fragments,
                descriptor: descriptor
            )
        }
        
        return nil
    }
    
    // MARK: - Window Settings
    
    /// Returns the first window settings from the data set
    ///
    /// Extracts Window Center and Window Width values to create WindowSettings.
    /// Returns nil if window values are not present.
    ///
    /// - Parameter frameIndex: For Enhanced multi-frame objects, the frame whose
    ///   Frame VOI LUT functional group is consulted when the top-level window is
    ///   absent; `nil` reads the shared item (else the first frame's).
    /// - Returns: WindowSettings if present
    public func windowSettings(frameIndex: Int? = nil) -> WindowSettings? {
        guard let centerDS = decimalString(for: .windowCenter),
              let widthDS = decimalString(for: .windowWidth) else {
            // Enhanced multi-frame objects carry the VOI in the Frame VOI LUT
            // functional group; fall back to that frame's item, else the shared one.
            if let item = functionalGroupItem(.frameVOILUTSequence, frameIndex: frameIndex),
               let c = item[.windowCenter]?.decimalStringValue?.value,
               let w = item[.windowWidth]?.decimalStringValue?.value {
                return WindowSettings(center: c, width: w,
                                      explanation: item.string(for: .windowCenterWidthExplanation),
                                      function: VOILUTFunction.parse(item.string(for: .voiLUTFunction)))
            }
            return nil
        }

        let explanation = string(for: .windowCenterWidthExplanation)
        let functionString = string(for: .voiLUTFunction)
        let function = VOILUTFunction.parse(functionString)

        return WindowSettings(
            center: centerDS.value,
            width: widthDS.value,
            explanation: explanation,
            function: function
        )
    }

    /// The first item of a functional-group macro for one frame.
    ///
    /// With a `frameIndex`, that frame's Per-frame item is consulted first (a
    /// macro lives in exactly one of the two sequences, so a per-frame hit is
    /// the frame's own value), then the Shared item. Without one — or when the
    /// index is out of range — the Shared item is read, else the *first*
    /// Per-frame item. Whole-frame access goes through ``flattenedFrame(_:)``.
    func functionalGroupItem(_ macro: Tag, frameIndex: Int? = nil) -> SequenceItem? {
        let perFrame = self[.perFrameFunctionalGroupsSequence]?.sequenceItems
        if let frameIndex, let perFrame, perFrame.indices.contains(frameIndex),
           let item = perFrame[frameIndex][macro]?.sequenceItems?.first {
            return item
        }
        if let shared = self[.sharedFunctionalGroupsSequence]?.sequenceItems?.first,
           let item = shared[macro]?.sequenceItems?.first {
            return item
        }
        if frameIndex == nil, let first = perFrame?.first,
           let item = first[macro]?.sequenceItems?.first {
            return item
        }
        return nil
    }

    /// Whether any frame of an Enhanced multi-frame object carries its own
    /// window or rescale — i.e. whether the Frame VOI LUT or Pixel Value
    /// Transformation macro sits in the Per-frame Functional Groups Sequence.
    /// Viewers use this to decide whether paging frames must re-derive the
    /// default window; cine loops and shared-window volumes answer `false`.
    public var hasPerFrameWindowOrRescale: Bool {
        guard let perFrame = self[.perFrameFunctionalGroupsSequence]?.sequenceItems else { return false }
        return perFrame.contains { item in
            item[.frameVOILUTSequence] != nil || item[.pixelValueTransformationSequence] != nil
        }
    }

    /// The data set of one frame of an Enhanced multi-frame object with its
    /// functional groups promoted to the top level (identity, pixel data and
    /// NumberOfFrames untouched apart from the module removal). Single-frame
    /// objects come back unchanged.
    public func flattenedFrame(_ frameIndex: Int) -> DataSet {
        guard self[.perFrameFunctionalGroupsSequence] != nil || self[.sharedFunctionalGroupsSequence] != nil else {
            return self
        }
        var ds = FunctionalGroupFlattener.flatten(self, frameIndex: frameIndex, toClassic: false)
        if let pixel = self[.pixelData] { ds[.pixelData] = pixel }
        if let frames = self[.numberOfFrames] { ds[.numberOfFrames] = frames }
        return ds
    }
    
    /// Returns all window settings from the data set
    ///
    /// DICOM allows multiple window center/width pairs.
    /// Returns an empty array if no window settings are present.
    ///
    /// - Parameter frameIndex: For Enhanced multi-frame objects, the frame whose
    ///   Frame VOI LUT functional group is consulted when the top-level window is
    ///   absent; `nil` reads the shared item (else the first frame's).
    /// - Returns: Array of WindowSettings
    public func allWindowSettings(frameIndex: Int? = nil) -> [WindowSettings] {
        // Top level first; else the Frame VOI LUT macro, which may carry the
        // same multi-valued pairs as a classic image.
        let element: (Tag) -> DataElement?
        if self[.windowCenter] != nil, self[.windowWidth] != nil {
            element = { self[$0] }
        } else if let item = functionalGroupItem(.frameVOILUTSequence, frameIndex: frameIndex) {
            element = { item[$0] }
        } else {
            return []
        }
        guard let centers = element(.windowCenter)?.decimalStringValues,
              let widths = element(.windowWidth)?.decimalStringValues,
              !centers.isEmpty, !widths.isEmpty else {
            return []
        }

        // Get explanations (may be fewer than windows)
        let explanations = element(.windowCenterWidthExplanation)?.stringValues ?? []
        let functionString = element(.voiLUTFunction)?.stringValue
        let function = VOILUTFunction.parse(functionString)
        
        var settings: [WindowSettings] = []
        let count = Swift.min(centers.count, widths.count)
        
        for i in 0..<count {
            let explanation = i < explanations.count ? explanations[i] : nil
            settings.append(WindowSettings(
                center: centers[i].value,
                width: widths[i].value,
                explanation: explanation,
                function: function
            ))
        }
        
        return settings
    }
    
    // MARK: - Rescale Values
    
    /// Returns the rescale intercept value
    ///
    /// Used to convert stored pixel values to output units.
    /// Reference: PS3.3 C.11.1.1.2 - Rescale Intercept
    ///
    /// When a Modality LUT Sequence is present it takes precedence and this
    /// returns 0.0 — see ``rescaleSlope()`` for the rationale.
    ///
    /// - Returns: Rescale intercept (default 0.0 if not present; 0.0 when a
    ///   Modality LUT Sequence is present)
    public func rescaleIntercept(frameIndex: Int? = nil) -> Double {
        guard modalityLUTData() == nil else { return 0.0 }
        if let value = decimalString(for: .rescaleIntercept)?.value { return value }
        return functionalGroupItem(.pixelValueTransformationSequence, frameIndex: frameIndex)?[.rescaleIntercept]?.decimalStringValue?.value ?? 0.0
    }
    
    /// Returns the rescale slope value
    ///
    /// Used to convert stored pixel values to output units.
    /// Reference: PS3.3 C.11.1.1.2 - Rescale Slope
    ///
    /// When a Modality LUT Sequence (0028,3000) is present it takes precedence over
    /// Rescale Slope/Intercept (PS3.3 C.11.1: the two forms are mutually exclusive;
    /// on malformed files carrying both, the sequence wins). In that case this
    /// returns the identity slope so linear composition by callers cannot corrupt
    /// LUT-mapped output; use ``rescale(_:)`` or ``modalityLUTData()`` for the actual
    /// transform.
    ///
    /// - Returns: Rescale slope (default 1.0 if not present; 1.0 when a Modality
    ///   LUT Sequence is present)
    public func rescaleSlope(frameIndex: Int? = nil) -> Double {
        guard modalityLUTData() == nil else { return 1.0 }
        if let value = decimalString(for: .rescaleSlope)?.value { return value }
        return functionalGroupItem(.pixelValueTransformationSequence, frameIndex: frameIndex)?[.rescaleSlope]?.decimalStringValue?.value ?? 1.0
    }

    /// Returns the parsed Modality LUT, when a Modality LUT Sequence (0028,3000)
    /// with a valid first item is present
    ///
    /// Reference: PS3.3 C.11.1 - Modality LUT Module. Descriptor (0028,3002) is
    /// three values [entries (0 ⇒ 65536), first stored value mapped, bits per
    /// entry]; data (0028,3006) is the table. Input values below/above the mapped
    /// range clamp to the first/last entry (C.11.1.1.1).
    ///
    /// - Returns: The LUT, or nil if the sequence is absent or malformed
    public func modalityLUTData() -> LUTData? {
        guard let item = sequence(for: .modalityLUTSequence)?.first else { return nil }

        // Descriptor: US (binary) in conformant files; tolerate IS from
        // JSON/XML-roundtripped or loosely written datasets.
        let descriptor: [Int]
        if let us = item[.lutDescriptor]?.uint16Values, us.count == 3 {
            descriptor = us.map(Int.init)
        } else if let is_ = item[.lutDescriptor]?.integerStringValues, is_.count == 3 {
            descriptor = is_.map { $0.value }
        } else {
            return nil
        }

        // Data: US/OW little-endian 16-bit entries; same IS fallback.
        let data: [Int]
        if let us = item[.lutData]?.uint16Values, !us.isEmpty {
            data = us.map(Int.init)
        } else if let is_ = item[.lutData]?.integerStringValues, !is_.isEmpty {
            data = is_.map { $0.value }
        } else {
            return nil
        }

        return LUTData.parse(descriptor: descriptor, data: data,
                             explanation: item.string(for: .lutExplanation))
    }

    /// Applies the modality transformation to a pixel value
    ///
    /// When a Modality LUT Sequence is present, the value is mapped through the
    /// LUT (with range clamping); otherwise
    /// OutputUnits = Rescale Slope * StoredValue + Rescale Intercept.
    /// Reference: PS3.3 C.11.1
    ///
    /// - Parameter storedValue: The stored pixel value
    /// - Returns: The transformed value in output units (e.g., Hounsfield Units for CT)
    public func rescale(_ storedValue: Double) -> Double {
        rescale(storedValue, frameIndex: nil)
    }

    /// Applies the modality transformation of frame `frameIndex` (0-based) to a pixel value.
    ///
    /// As ``rescale(_:)``, with Rescale Slope / Intercept taken from the frame's Pixel Value
    /// Transformation Sequence (0028,9145) when it is in the Per-Frame Functional Groups
    /// Sequence (PS3.3 2026a C.7.6.16.2.9, Table C.7.6.16-10; Table C.8-126 CT Pixel Value
    /// Transformation Macro), so every frame uses its own values (D197). `nil` uses the top-level
    /// or Shared Functional Groups value (the first frame's, when only per-frame values exist).
    public func rescale(_ storedValue: Double, frameIndex: Int?) -> Double {
        if let lut = modalityLUTData() {
            return lut.lookup(Int(storedValue.rounded()))
        }
        return rescaleSlope(frameIndex: frameIndex) * storedValue + rescaleIntercept(frameIndex: frameIndex)
    }
    
    // MARK: - Image Dimensions
    
    /// Returns the number of rows (height) in the image
    public var imageRows: Int? {
        uint16(for: .rows).map { Int($0) }
    }
    
    /// Returns the number of columns (width) in the image
    public var imageColumns: Int? {
        uint16(for: .columns).map { Int($0) }
    }
    
    /// Returns the number of frames in the image
    public var numberOfFrames: Int? {
        if let frameString = string(for: .numberOfFrames),
           let frames = Int(frameString.trimmingCharacters(in: .whitespaces)) {
            return frames
        }
        return nil
    }
    
    // MARK: - Photometric Interpretation
    
    /// Returns the photometric interpretation
    public var photometricInterpretation: PhotometricInterpretation? {
        guard let value = string(for: .photometricInterpretation) else {
            return nil
        }
        return PhotometricInterpretation.parse(value)
    }
    
    // MARK: - Palette Color Lookup Table
    
    /// Returns the Palette Color Lookup Table for PALETTE COLOR images
    ///
    /// Extracts the Red, Green, and Blue palette lookup tables and their
    /// descriptors from the data set. Required for PALETTE COLOR photometric
    /// interpretation images.
    ///
    /// Reference: DICOM PS3.3 C.7.6.3.1.5 - Palette Color Lookup Table Module
    ///
    /// - Returns: PaletteColorLUT if all required components are present
    public func paletteColorLUT() -> PaletteColorLUT? {
        // Get the descriptors
        guard let redDescriptorData = self[.redPaletteColorLookupTableDescriptor]?.valueData,
              let greenDescriptorData = self[.greenPaletteColorLookupTableDescriptor]?.valueData,
              let blueDescriptorData = self[.bluePaletteColorLookupTableDescriptor]?.valueData else {
            return nil
        }
        
        guard let redDescriptor = PaletteColorLUT.Descriptor.parse(from: redDescriptorData),
              let greenDescriptor = PaletteColorLUT.Descriptor.parse(from: greenDescriptorData),
              let blueDescriptor = PaletteColorLUT.Descriptor.parse(from: blueDescriptorData) else {
            return nil
        }
        
        // Get the LUT data
        guard let redLUTData = self[.redPaletteColorLookupTableData]?.valueData,
              let greenLUTData = self[.greenPaletteColorLookupTableData]?.valueData,
              let blueLUTData = self[.bluePaletteColorLookupTableData]?.valueData else {
            return nil
        }
        
        // Parse the LUT data
        guard let redLUT = PaletteColorLUT.parseLUTData(from: redLUTData, descriptor: redDescriptor),
              let greenLUT = PaletteColorLUT.parseLUTData(from: greenLUTData, descriptor: greenDescriptor),
              let blueLUT = PaletteColorLUT.parseLUTData(from: blueLUTData, descriptor: blueDescriptor) else {
            return nil
        }
        
        return PaletteColorLUT(
            redDescriptor: redDescriptor,
            greenDescriptor: greenDescriptor,
            blueDescriptor: blueDescriptor,
            redLUT: redLUT,
            greenLUT: greenLUT,
            blueLUT: blueLUT
        )
    }
}
