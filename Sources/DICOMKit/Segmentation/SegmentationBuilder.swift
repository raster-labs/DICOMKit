// NEMA-verified: 2026a, checked 2026-09-30 — 1-bit frames packed least-significant-bit first per PS3.5 2026a 8.1.1 and D.1; LABELMAP per PS3.3 Table C.8.20-2 (Bits Allocated 8/16, Bits Stored, High Bit, Pixel Representation 0, MONOCHROME2, Segments Overlap NO), C.8.20.2.3.3 (every encoded value described in Segment Sequence), Table A.51-2 (no Segmentation Functional Group for LABELMAP), A.51.4 (Pixel Padding Value), PS3.4 B.5.1.25 (Label Map Segmentation Storage); toDataSet writes the Type 1 attributes of Tables C.8.20-2, C.8.20-4, C.7.6.16-1, C.7.6.17-1; category and type codes per PS3.16 CID 7150/7151; Segmented Property Category/Type Code Sequences (0062,0003)/(0062,000F) Type 1 with one Item per Table C.8.20-4, enforced by buildDataSet (D37d); Tracking ID (0062,0020) UT and Tracking UID (0062,0021) UI, each Type 1C on the other per Table C.8.20-4, enforced by buildDataSet (D45); Patient / General Study Type 2 rows (Tables C.7-1, C.7-3) and Enhanced General Equipment Type 1 rows (Table C.7-8b), both modules M in Table A.51-1, written by buildDataSet (D71, 2026-10-01); PALETTE COLOR LABELMAP (D37b): Photometric Interpretation per Table C.8.20-2 (PALETTE COLOR only for LABELMAP, no Recommended Display CIELab Value), Palette Color Lookup Table and ICC Profile Modules per Table A.51-1 and A.1.3.2, descriptors/data per Table C.7-22a, C.7.6.3.1.5 (8 or 16 bits per entry in the Segmentation IOD, US with Pixel Representation 0, no segmented data) and C.7.6.3.1.6 (8-bit values replicated into 16 bits), ICC Profile header per C.11.15.1.1 and Color Space per C.11.15.1.2, VRs per PS3.6 Table 6-1
//
// SegmentationBuilder.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Builder for creating DICOM Segmentation objects
///
/// SegmentationBuilder provides a fluent API for constructing Segmentation IODs from
/// binary or fractional masks, particularly useful for encoding AI/ML algorithm output.
///
/// Example - Binary Segmentation:
/// ```swift
/// let builder = SegmentationBuilder(
///     rows: 512,
///     columns: 512,
///     segmentationType: .binary,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
///
/// let (segmentation, pixelData) = try builder
///     .setContentLabel("AI Tumor Detection")
///     .setContentDescription("Automated tumor segmentation")
///     .addBinarySegment(
///         number: 1,
///         label: "Tumor",
///         mask: binaryMask,  // [UInt8] with 0 or 1 values
///         category: CodedConcept(codeValue: "49755003", codingSchemeDesignator: "SCT", codeMeaning: "Morphologically Abnormal Structure"),
///         type: CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Tumor"),
///         color: (r: 255, g: 0, b: 0),
///         algorithmType: .automatic,
///         algorithmName: "DeepTumor v1.0"
///     )
///     .build()
/// ```
///
/// Example - Fractional Segmentation:
/// ```swift
/// let builder = SegmentationBuilder(
///     rows: 256,
///     columns: 256,
///     segmentationType: .fractional,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
///
/// let (segmentation, pixelData) = try builder
///     .setContentLabel("Liver Probability Map")
///     .addFractionalSegment(
///         number: 1,
///         label: "Liver",
///         mask: probabilityMask,  // [UInt8] with 0-255 normalized values
///         category: nil,
///         type: CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver"),
///         color: (r: 139, g: 69, b: 19),
///         fractionalType: .probability,
///         maxValue: 255,
///         algorithmType: .automatic,
///         algorithmName: "LiverSegNet v2.0"
///     )
///     .build()
/// ```
///
/// Example - LABELMAP Segmentation (one frame per slice, pixel value = Segment Number):
/// ```swift
/// let builder = SegmentationBuilder(
///     rows: 256,
///     columns: 256,
///     segmentationType: .labelmap,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
///
/// let (segmentation, pixelData) = try builder
///     .addLabelmapSegment(number: 0, label: "Background")
///     .addLabelmapSegment(number: 1, label: "Liver", color: (r: 139, g: 69, b: 19))
///     .addLabelmapSegment(number: 2, label: "Tumor", color: (r: 255, g: 0, b: 0))
///     .setPixelPaddingValue(0)
///     .addLabelmapFrame(sliceLabels, imagePositionPatient: [0, 0, 12.5])
///     .build()
/// ```
/// Every pixel value in a LABELMAP frame must be one of the added Segment Numbers
/// (PS3.3 C.8.20.2.3.3); `build()` throws otherwise. The result is a Label Map
/// Segmentation Storage instance (PS3.4 B.5.1.25). `Segmentation.buildDataSet(pixelData:)`
/// serialises the result.
///
/// Reference: PS3.3 A.51 - Segmentation IOD
/// Reference: PS3.3 C.8.20 - Segmentation Modules
/// Reference: PS3.5 Section 8.1.1 - Pixel Data Encoding of Related Data Elements (bit packing)
public final class SegmentationBuilder {

    // MARK: - Configuration

    private let rows: Int
    private let columns: Int
    private let segmentationType: SegmentationType
    private let studyInstanceUID: String
    private let seriesInstanceUID: String

    // MARK: - Optional Metadata

    private var sopInstanceUID: String?
    private var instanceNumber: Int?
    private var seriesNumber: Int?
    private var contentLabel: String?
    private var contentDescription: String?
    private var contentCreatorName: DICOMPersonName?
    private var contentDate: DICOMDate?
    private var contentTime: DICOMTime?
    private var frameOfReferenceUID: String?
    private var pixelPaddingValue: Int?
    private var labelmapBitsAllocated: Int?
    private var paletteColor: (iccProfile: Data, colorSpace: String?)?
    private var patientAndStudy = SegmentationPatientAndStudy()
    private var equipment = SegmentationEquipment.dicomKit

    // MARK: - Segments and Pixel Data

    private var segments: [SegmentData] = []
    private var sourceImages: [SourceImageReference] = []
    private var labelmapFrames: [LabelmapFrame] = []

    // MARK: - Internal Types

    private struct SegmentData {
        let segment: Segment
        /// Frame pixel data for BINARY/FRACTIONAL; empty for LABELMAP, whose frames are
        /// held in `labelmapFrames`
        let pixelData: Data
        /// The display colour as given, for a PALETTE COLOR LABELMAP's lookup table
        var color: (r: UInt8, g: UInt8, b: UInt8)? = nil
    }

    private struct LabelmapFrame {
        let labels: [UInt16]
        let imagePositionPatient: [Double]?
        let imageOrientationPatient: [Double]?
    }
    
    private struct SourceImageReference {
        let sopClassUID: String
        let sopInstanceUID: String
        let frameNumber: Int?
    }
    
    // MARK: - Initialization
    
    /// Creates a new Segmentation builder
    /// - Parameters:
    ///   - rows: Number of rows in the segmentation
    ///   - columns: Number of columns in the segmentation
    ///   - segmentationType: Type of segmentation (binary, fractional or labelmap)
    ///   - studyInstanceUID: Study Instance UID for the segmentation
    ///   - seriesInstanceUID: Series Instance UID for the segmentation
    public init(
        rows: Int,
        columns: Int,
        segmentationType: SegmentationType,
        studyInstanceUID: String,
        seriesInstanceUID: String
    ) {
        self.rows = rows
        self.columns = columns
        self.segmentationType = segmentationType
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
    }
    
    // MARK: - Configuration Methods
    
    /// Sets the Type 2 Patient (PS3.3 2026a Table C.7-1) and General Study (Table C.7-3)
    /// attributes, e.g. `SegmentationPatientAndStudy(copyingFrom: sourceImage)`
    @discardableResult
    public func setPatientAndStudy(_ attributes: SegmentationPatientAndStudy) -> Self {
        patientAndStudy = attributes
        return self
    }

    /// Sets the Enhanced General Equipment Module (Table C.7-8b, all Type 1); the default is
    /// ``SegmentationEquipment/dicomKit``
    @discardableResult
    public func setEquipment(_ equipment: SegmentationEquipment) -> Self {
        self.equipment = equipment
        return self
    }

    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID (will be auto-generated if not set)
    /// - Returns: Updated builder
    @discardableResult
    public func setSOPInstanceUID(_ uid: String) -> Self {
        sopInstanceUID = uid
        return self
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    @discardableResult
    public func setInstanceNumber(_ number: Int) -> Self {
        instanceNumber = number
        return self
    }
    
    /// Sets the Series Number (0020,0011), Type 1 in the Segmentation Series Module
    /// (PS3.3 Table C.8.20-1); `buildDataSet` writes 1 when not set
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    @discardableResult
    public func setSeriesNumber(_ number: Int) -> Self {
        seriesNumber = number
        return self
    }

    /// Sets the Content Label
    /// - Parameter label: A label that identifies the content (max 16 characters)
    /// - Returns: Updated builder
    @discardableResult
    public func setContentLabel(_ label: String) -> Self {
        contentLabel = label
        return self
    }
    
    /// Sets the Content Description
    /// - Parameter description: Human-readable description of the content
    /// - Returns: Updated builder
    @discardableResult
    public func setContentDescription(_ description: String) -> Self {
        contentDescription = description
        return self
    }
    
    /// Sets the Content Creator's Name
    /// - Parameter name: The name of the content creator
    /// - Returns: Updated builder
    @discardableResult
    public func setContentCreator(_ name: DICOMPersonName) -> Self {
        contentCreatorName = name
        return self
    }
    
    /// Sets the Content Date
    /// - Parameter date: The content date
    /// - Returns: Updated builder
    @discardableResult
    public func setContentDate(_ date: DICOMDate) -> Self {
        contentDate = date
        return self
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time
    /// - Returns: Updated builder
    @discardableResult
    public func setContentTime(_ time: DICOMTime) -> Self {
        contentTime = time
        return self
    }
    
    /// Sets the Frame of Reference UID
    /// - Parameter uid: The Frame of Reference UID
    /// - Returns: Updated builder
    @discardableResult
    public func setFrameOfReference(_ uid: String) -> Self {
        frameOfReferenceUID = uid
        return self
    }

    /// Sets Pixel Padding Value (0028,0120): the Segment Number a LABELMAP treats as
    /// background (PS3.3 A.51.4, C.8.20.2.4). It must be one of the added Segment Numbers.
    ///
    /// Only meaningful for LABELMAP; A.51.4 says the attribute "shall not be present if
    /// Segmentation Type (0062,0001) is not LABELMAP", so `build()` ignores it otherwise.
    /// - Parameter value: The background Segment Number
    /// - Returns: Updated builder
    @discardableResult
    public func setPixelPaddingValue(_ value: Int) -> Self {
        pixelPaddingValue = value
        return self
    }

    /// Sets Bits Allocated for a LABELMAP: 8 or 16 (PS3.3 Table C.8.20-2). When not set,
    /// `build()` uses 8 if every Segment Number fits in a byte, 16 otherwise.
    /// - Parameter bits: 8 or 16
    /// - Returns: Updated builder
    @discardableResult
    public func setLabelmapBitsAllocated(_ bits: Int) -> Self {
        labelmapBitsAllocated = bits
        return self
    }
    
    /// Encodes a LABELMAP with Photometric Interpretation PALETTE COLOR instead of
    /// MONOCHROME2 (PS3.3 2026a Table C.8.20-2 allows PALETTE COLOR only for LABELMAP)
    ///
    /// `build()` then fills the Palette Color Lookup Table Module (C.7.9), which Table
    /// A.51-1 requires with PALETTE COLOR, from the segment colours: one 16-bit entry per
    /// value from 0 to the largest Segment Number (C.7.6.3.1.5 allows 8 or 16 bits per
    /// entry in the Segmentation IOD), each 8-bit channel scaled to 16 bits by replicating
    /// it into both bytes (C.7.6.3.1.6). Values no segment describes, and segments added
    /// without a colour, map to black. Recommended Display CIELab Value is not written,
    /// since Table C.8.20-2 says it "shall not be present if Segmentation Type is LABELMAP
    /// and Photometric Interpretation is PALETTE COLOR".
    ///
    /// The ICC Profile Module (C.11.15), also required with PALETTE COLOR (Table A.51-1),
    /// carries `iccProfile`; it must be an Input Device ("scnr") RGB profile with a Lab or
    /// XYZ PCS (C.11.15.1.1). The default is the fixed sRGB profile of
    /// ``SRGBICCProfileWriter`` with Color Space SRGB (C.11.15.1.2).
    ///
    /// `build()` throws ``SegmentationBuilderError/invalidSegmentationType(expected:got:)``
    /// when the builder is not LABELMAP.
    /// - Parameters:
    ///   - iccProfile: ICC Profile (0028,2000) bytes
    ///   - colorSpace: Color Space (0028,2002), Type 3; `nil` omits it
    /// - Returns: Updated builder
    @discardableResult
    public func setPaletteColor(
        iccProfile: Data = SRGBICCProfileWriter.profileData,
        colorSpace: String? = SRGBICCProfileWriter.colorSpace
    ) -> Self {
        paletteColor = (iccProfile, colorSpace)
        return self
    }

    // MARK: - Binary Segment Addition
    
    /// Adds a binary segment to the segmentation
    ///
    /// Binary masks are bit-packed according to PS3.5 Section 8.1.1:
    /// - 8 pixels per byte
    /// - Most significant bit (MSB) first
    /// - Padding bits set to 0 when pixels don't align to byte boundary
    ///
    /// - Parameters:
    ///   - number: Segment number (must be unique, starts from 1)
    ///   - label: Human-readable segment label
    ///   - mask: Binary mask data (0 or 1 values, rows × columns elements)
    ///   - category: Segmented Property Category (CID 7150), e.g. Tissue, Anatomical
    ///     Structure. Type 1 in the Segment Description Macro (PS3.3 Table C.8.20-4):
    ///     `Segmentation.buildDataSet(pixelData:)` throws when it is missing
    ///   - type: Segmented Property Type (CID 7151), e.g. Liver, Tumor. Type 1 likewise
    ///   - color: Optional display color (RGB, each 0-255)
    ///   - algorithmType: Optional algorithm type (automatic, semiautomatic, manual)
    ///   - algorithmName: Optional algorithm name
    /// - Throws: SegmentationBuilderError if validation fails
    /// - Returns: Updated builder
    @discardableResult
    public func addBinarySegment(
        number: Int,
        label: String,
        mask: [UInt8],
        category: CodedConcept? = nil,
        type: CodedConcept? = nil,
        color: (r: UInt8, g: UInt8, b: UInt8)? = nil,
        algorithmType: SegmentAlgorithmType? = nil,
        algorithmName: String? = nil
    ) throws -> Self {
        // Validate segmentation type
        guard segmentationType == .binary else {
            throw SegmentationBuilderError.invalidSegmentationType(expected: .binary, got: segmentationType)
        }
        
        // Validate mask dimensions
        let expectedPixels = rows * columns
        guard mask.count == expectedPixels else {
            throw SegmentationBuilderError.invalidMaskDimensions(expected: expectedPixels, got: mask.count)
        }
        
        // Validate binary values
        for (index, value) in mask.enumerated() {
            guard value == 0 || value == 1 else {
                throw SegmentationBuilderError.invalidBinaryValue(Int(value), index: index)
            }
        }
        
        // Validate segment number
        try validateSegmentNumber(number)
        
        // Convert RGB to CIELab
        let cieLabColor = color.map { rgbToCIELab(r: $0.r, g: $0.g, b: $0.b) }
        
        // Create segment
        let segment = Segment(
            segmentNumber: number,
            segmentLabel: label,
            segmentDescription: nil,
            segmentAlgorithmType: algorithmType,
            segmentAlgorithmName: algorithmName,
            category: category,
            type: type,
            anatomicRegion: nil,
            anatomicRegionModifier: nil,
            recommendedDisplayCIELabValue: cieLabColor,
            trackingID: nil,
            trackingUID: nil
        )
        
        // Pack binary mask
        let packedData = packBinaryMask(mask)
        
        // Store segment data
        segments.append(SegmentData(segment: segment, pixelData: packedData))
        
        return self
    }
    
    // MARK: - Fractional Segment Addition
    
    /// Adds a fractional segment to the segmentation
    ///
    /// Fractional masks represent probability or occupancy values scaled to fit
    /// within the specified max fractional value.
    ///
    /// - Parameters:
    ///   - number: Segment number (must be unique, starts from 1)
    ///   - label: Human-readable segment label
    ///   - mask: Fractional mask data (0-255 normalized values, rows × columns elements)
    ///   - category: Segmented Property Category (CID 7150); Type 1 (Table C.8.20-4),
    ///     `Segmentation.buildDataSet(pixelData:)` throws when it is missing
    ///   - type: Segmented Property Type (CID 7151); Type 1 likewise
    ///   - color: Optional display color (RGB, each 0-255)
    ///   - fractionalType: Type of fractional values (probability or occupancy)
    ///   - maxValue: Maximum fractional value (typically 255 for 8-bit or 65535 for 16-bit)
    ///   - algorithmType: Optional algorithm type
    ///   - algorithmName: Optional algorithm name
    /// - Throws: SegmentationBuilderError if validation fails
    /// - Returns: Updated builder
    @discardableResult
    public func addFractionalSegment(
        number: Int,
        label: String,
        mask: [UInt8],
        category: CodedConcept? = nil,
        type: CodedConcept? = nil,
        color: (r: UInt8, g: UInt8, b: UInt8)? = nil,
        fractionalType: SegmentationFractionalType,
        maxValue: Int,
        algorithmType: SegmentAlgorithmType? = nil,
        algorithmName: String? = nil
    ) throws -> Self {
        // Validate segmentation type
        guard segmentationType == .fractional else {
            throw SegmentationBuilderError.invalidSegmentationType(expected: .fractional, got: segmentationType)
        }
        
        // Validate mask dimensions
        let expectedPixels = rows * columns
        guard mask.count == expectedPixels else {
            throw SegmentationBuilderError.invalidMaskDimensions(expected: expectedPixels, got: mask.count)
        }
        
        // Validate max fractional value
        guard maxValue > 0 && maxValue <= 65535 else {
            throw SegmentationBuilderError.invalidMaxFractionalValue(maxValue)
        }
        
        // Validate segment number
        try validateSegmentNumber(number)
        
        // Convert RGB to CIELab
        let cieLabColor = color.map { rgbToCIELab(r: $0.r, g: $0.g, b: $0.b) }
        
        // Create segment
        let segment = Segment(
            segmentNumber: number,
            segmentLabel: label,
            segmentDescription: nil,
            segmentAlgorithmType: algorithmType,
            segmentAlgorithmName: algorithmName,
            category: category,
            type: type,
            anatomicRegion: nil,
            anatomicRegionModifier: nil,
            recommendedDisplayCIELabValue: cieLabColor,
            trackingID: nil,
            trackingUID: nil
        )
        
        // Determine bits allocated based on max value
        let bitsAllocated = maxValue <= 255 ? 8 : 16
        
        // Scale fractional mask
        let scaledData = scaleFractionalMask(mask, to: bitsAllocated, maxValue: maxValue)
        
        // Store segment data
        segments.append(SegmentData(segment: segment, pixelData: scaledData))
        
        return self
    }
    
    // MARK: - Labelmap Segment and Frame Addition

    /// Describes a segment of a LABELMAP segmentation
    ///
    /// A LABELMAP carries no pixel data per segment: the Segment Number is the pixel value
    /// that encodes the segment in the frames added with ``addLabelmapFrame(_:imagePositionPatient:imageOrientationPatient:)``.
    /// Every pixel value actually encoded must be described by one of these segments
    /// (PS3.3 C.8.20.2.3.3), including 0 when it is used as background.
    ///
    /// - Parameters:
    ///   - number: Segment Number (0062,0004), unique within the instance; 0 is allowed
    ///     (C.8.20.2.4 constrains the numbering to 1, 2, 3… only for BINARY and FRACTIONAL)
    ///   - label: Segment Label (0062,0005)
    ///   - category: Segmented Property Category Code (CID 7150); Type 1 (Table C.8.20-4),
    ///     `Segmentation.buildDataSet(pixelData:)` throws when it is missing
    ///   - type: Segmented Property Type Code (CID 7151); Type 1 likewise
    ///   - color: Optional display color (RGB, each 0-255), written as Recommended Display
    ///     CIELab Value
    ///   - algorithmType: Segment Algorithm Type (0062,0008), MANUAL when nil
    ///   - algorithmName: Segment Algorithm Name (0062,0009), required unless MANUAL
    /// - Throws: SegmentationBuilderError if validation fails
    /// - Returns: Updated builder
    @discardableResult
    public func addLabelmapSegment(
        number: Int,
        label: String,
        category: CodedConcept? = nil,
        type: CodedConcept? = nil,
        color: (r: UInt8, g: UInt8, b: UInt8)? = nil,
        algorithmType: SegmentAlgorithmType? = nil,
        algorithmName: String? = nil
    ) throws -> Self {
        guard segmentationType == .labelmap else {
            throw SegmentationBuilderError.invalidSegmentationType(expected: .labelmap, got: segmentationType)
        }
        guard number >= 0 && number <= 0xFFFF else {
            throw SegmentationBuilderError.invalidSegmentNumber(number)
        }
        if segments.contains(where: { $0.segment.segmentNumber == number }) {
            throw SegmentationBuilderError.duplicateSegmentNumber(number)
        }

        let segment = Segment(
            segmentNumber: number,
            segmentLabel: label,
            segmentDescription: nil,
            segmentAlgorithmType: algorithmType,
            segmentAlgorithmName: algorithmName,
            category: category,
            type: type,
            anatomicRegion: nil,
            anatomicRegionModifier: nil,
            recommendedDisplayCIELabValue: color.map { rgbToCIELab(r: $0.r, g: $0.g, b: $0.b) },
            trackingID: nil,
            trackingUID: nil
        )
        segments.append(SegmentData(segment: segment, pixelData: Data(), color: color))
        return self
    }

    /// Adds one LABELMAP frame (one slice)
    ///
    /// - Parameters:
    ///   - labels: rows × columns pixel values; each is the Segment Number of the segment
    ///     present at that pixel (PS3.3 C.8.20.2.3.3)
    ///   - imagePositionPatient: Optional Image Position (Patient) for the Plane Position
    ///     (Patient) Functional Group
    ///   - imageOrientationPatient: Optional Image Orientation (Patient) for the Plane
    ///     Orientation (Patient) Functional Group
    /// - Throws: SegmentationBuilderError if validation fails
    /// - Returns: Updated builder
    @discardableResult
    public func addLabelmapFrame(
        _ labels: [UInt16],
        imagePositionPatient: [Double]? = nil,
        imageOrientationPatient: [Double]? = nil
    ) throws -> Self {
        guard segmentationType == .labelmap else {
            throw SegmentationBuilderError.invalidSegmentationType(expected: .labelmap, got: segmentationType)
        }
        let expectedPixels = rows * columns
        guard labels.count == expectedPixels else {
            throw SegmentationBuilderError.invalidMaskDimensions(expected: expectedPixels, got: labels.count)
        }
        if let position = imagePositionPatient, position.count != 3 {
            throw SegmentationBuilderError.invalidPlaneGeometry("Image Position (Patient) needs 3 values, got \(position.count)")
        }
        if let orientation = imageOrientationPatient, orientation.count != 6 {
            throw SegmentationBuilderError.invalidPlaneGeometry("Image Orientation (Patient) needs 6 values, got \(orientation.count)")
        }
        labelmapFrames.append(LabelmapFrame(
            labels: labels,
            imagePositionPatient: imagePositionPatient,
            imageOrientationPatient: imageOrientationPatient
        ))
        return self
    }

    // MARK: - Source Image Reference

    /// Adds a source image reference
    ///
    /// Links the segmentation to its source image(s).
    ///
    /// - Parameters:
    ///   - sopClassUID: SOP Class UID of the source image
    ///   - sopInstanceUID: SOP Instance UID of the source image
    ///   - frameNumber: Optional frame number for multi-frame sources
    /// - Returns: Updated builder
    @discardableResult
    public func addSourceImage(
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumber: Int? = nil
    ) -> Self {
        sourceImages.append(SourceImageReference(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumber: frameNumber
        ))
        return self
    }
    
    // MARK: - Build
    
    /// Builds the final Segmentation object and pixel data
    ///
    /// - Throws: SegmentationBuilderError if validation fails
    /// - Returns: A tuple containing the Segmentation object and its pixel data
    public func build() throws -> (segmentation: Segmentation, pixelData: Data) {
        // Validate at least one segment
        guard !segments.isEmpty else {
            throw SegmentationBuilderError.noSegmentsAdded
        }
        // PALETTE COLOR is an Enumerated Value only for LABELMAP (Table C.8.20-2)
        if paletteColor != nil && segmentationType != .labelmap {
            throw SegmentationBuilderError.invalidSegmentationType(expected: .labelmap, got: segmentationType)
        }
        
        // Generate SOP Instance UID if not provided
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateSOPInstanceUID().description
        
        // Get current date/time if not provided
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        
        let finalContentDate = contentDate ?? DICOMDate(
            year: components.year ?? 2024,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
        
        let finalContentTime = contentTime ?? DICOMTime(
            hour: components.hour ?? 0,
            minute: components.minute,
            second: components.second
        )
        
        // Sort segments by number
        let sortedSegments = segments.sorted { $0.segment.segmentNumber < $1.segment.segmentNumber }

        // Build pixel data by concatenating all segment frames (BINARY/FRACTIONAL) or
        // all slices (LABELMAP)
        var combinedPixelData = Data()

        // Determine pixel data properties based on segmentation type
        let (bitsAllocated, bitsStored, highBit): (Int, Int, Int)
        let maxFractionalValue: Int?
        let fractionalType: SegmentationFractionalType?
        let numberOfFrames: Int
        let segmentsOverlap: SegmentsOverlap?
        let finalPixelPaddingValue: Int?
        let perFrameFunctionalGroups: [FunctionalGroup]

        switch segmentationType {
        case .binary:
            bitsAllocated = 1
            bitsStored = 1
            highBit = 0
            maxFractionalValue = nil
            fractionalType = nil
            for segmentData in sortedSegments {
                combinedPixelData.append(segmentData.pixelData)
            }
            numberOfFrames = sortedSegments.count
            segmentsOverlap = nil
            finalPixelPaddingValue = nil
            perFrameFunctionalGroups = sortedSegments.map { segmentData in
                FunctionalGroup(
                    segmentIdentification: SegmentIdentification(
                        referencedSegmentNumber: segmentData.segment.segmentNumber
                    ),
                    derivationImage: nil,
                    frameContent: nil,
                    planePosition: nil,
                    planeOrientation: nil
                )
            }

        case .fractional:
            // Determine from first segment (all should be consistent)
            // For simplicity, we'll use the maxValue from the first fractional segment
            // In a real implementation, this should be stored during addFractionalSegment
            // For now, we'll default to 8-bit
            bitsAllocated = 8
            bitsStored = 8
            highBit = 7
            maxFractionalValue = 255
            fractionalType = .probability
            for segmentData in sortedSegments {
                combinedPixelData.append(segmentData.pixelData)
            }
            numberOfFrames = sortedSegments.count
            segmentsOverlap = nil
            finalPixelPaddingValue = nil
            perFrameFunctionalGroups = sortedSegments.map { segmentData in
                FunctionalGroup(
                    segmentIdentification: SegmentIdentification(
                        referencedSegmentNumber: segmentData.segment.segmentNumber
                    ),
                    derivationImage: nil,
                    frameContent: nil,
                    planePosition: nil,
                    planeOrientation: nil
                )
            }

        case .labelmap:
            // PS3.3 Table C.8.20-2: Bits Allocated 8 or 16; Bits Stored equals Bits
            // Allocated; High Bit 7 or 15; Pixel Representation 0.
            guard !labelmapFrames.isEmpty else {
                throw SegmentationBuilderError.noFramesAdded
            }
            let describedNumbers = Set(sortedSegments.map { $0.segment.segmentNumber })
            let maxSegmentNumber = sortedSegments.map { $0.segment.segmentNumber }.max() ?? 0
            let bits = labelmapBitsAllocated ?? (maxSegmentNumber > 0xFF ? 16 : 8)
            guard bits == 8 || bits == 16 else {
                throw SegmentationBuilderError.invalidBitsAllocated(bits)
            }
            guard maxSegmentNumber <= (bits == 8 ? 0xFF : 0xFFFF) else {
                throw SegmentationBuilderError.segmentNumberExceedsBitsAllocated(maxSegmentNumber, bitsAllocated: bits)
            }
            // A.51.4 / C.8.20.2.4: Pixel Padding Value names the Segment Number treated as
            // background, so it must be one of the described Segment Numbers.
            if let padding = pixelPaddingValue, !describedNumbers.contains(padding) {
                throw SegmentationBuilderError.labelmapValueNotDescribed(padding, frame: nil, index: nil)
            }
            bitsAllocated = bits
            bitsStored = bits
            highBit = bits - 1
            maxFractionalValue = nil
            fractionalType = nil
            segmentsOverlap = .no          // Table C.8.20-2: shall be NO for LABELMAP
            finalPixelPaddingValue = pixelPaddingValue
            numberOfFrames = labelmapFrames.count

            combinedPixelData.reserveCapacity(labelmapFrames.count * rows * columns * (bits / 8))
            for (frameIndex, frame) in labelmapFrames.enumerated() {
                // C.8.20.2.3.3: every pixel value actually encoded is required to be
                // described in an Item of Segment Sequence.
                for (index, value) in frame.labels.enumerated() where !describedNumbers.contains(Int(value)) {
                    throw SegmentationBuilderError.labelmapValueNotDescribed(Int(value), frame: frameIndex, index: index)
                }
                if bits == 8 {
                    combinedPixelData.append(contentsOf: frame.labels.map { UInt8(truncatingIfNeeded: $0) })
                } else {
                    for value in frame.labels {
                        combinedPixelData.append(UInt8(value & 0xFF))
                        combinedPixelData.append(UInt8(value >> 8))
                    }
                }
            }

            // Table A.51-2: the Segmentation Functional Group (Segment Identification
            // Sequence) is not used for LABELMAP. Each frame gets Frame Content with the
            // dimension index (In-Stack Position Number) and, when given, its plane
            // position/orientation.
            perFrameFunctionalGroups = labelmapFrames.enumerated().map { frameIndex, frame in
                FunctionalGroup(
                    segmentIdentification: nil,
                    derivationImage: nil,
                    frameContent: FrameContent(
                        dimensionIndexValues: [frameIndex + 1],
                        stackID: "1",
                        inStackPositionNumber: frameIndex + 1
                    ),
                    planePosition: frame.imagePositionPatient.map { PlanePosition(imagePositionPatient: $0) },
                    planeOrientation: frame.imageOrientationPatient.map { PlaneOrientation(imageOrientationPatient: $0) }
                )
            }
        }
        
        // PALETTE COLOR LABELMAP: the Palette Color Lookup Table indexed by Segment Number
        // (C.7.9, C.7.6.3.1.5) replaces the per-segment CIELab colour, which Table
        // C.8.20-2 forbids with PALETTE COLOR.
        var finalSegments = sortedSegments.map { $0.segment }
        var paletteColorLookupTable: PaletteColorLUT? = nil
        if paletteColor != nil {
            let entryCount = (sortedSegments.map { $0.segment.segmentNumber }.max() ?? 0) + 1
            var red = [UInt16](repeating: 0, count: entryCount)
            var green = red
            var blue = red
            for segmentData in sortedSegments {
                guard let color = segmentData.color else { continue }
                let index = segmentData.segment.segmentNumber
                // C.7.6.3.1.6: 8-bit intensities scaled to 16 bits by replicating the byte
                red[index] = UInt16(color.r) * 0x101
                green[index] = UInt16(color.g) * 0x101
                blue[index] = UInt16(color.b) * 0x101
            }
            let descriptor = PaletteColorLUT.Descriptor(
                numberOfEntries: entryCount, firstMappedValue: 0, bitsPerEntry: 16)
            paletteColorLookupTable = PaletteColorLUT(
                redDescriptor: descriptor, greenDescriptor: descriptor, blueDescriptor: descriptor,
                redLUT: red, greenLUT: green, blueLUT: blue)
            finalSegments = finalSegments.map { segment in
                Segment(
                    segmentNumber: segment.segmentNumber,
                    segmentLabel: segment.segmentLabel,
                    segmentDescription: segment.segmentDescription,
                    segmentAlgorithmType: segment.segmentAlgorithmType,
                    segmentAlgorithmName: segment.segmentAlgorithmName,
                    category: segment.category,
                    type: segment.type,
                    anatomicRegion: segment.anatomicRegion,
                    anatomicRegionModifier: segment.anatomicRegionModifier,
                    recommendedDisplayCIELabValue: nil,
                    trackingID: segment.trackingID,
                    trackingUID: segment.trackingUID
                )
            }
        }

        // Build referenced series
        let referencedSeries: [SegmentationReferencedSeries]
        if !sourceImages.isEmpty {
            // Group by series (for simplicity, assume all from same series)
            let instances = sourceImages.map { ref in
                SegmentationReferencedInstance(
                    sopClassUID: ref.sopClassUID,
                    sopInstanceUID: ref.sopInstanceUID,
                    referencedFrameNumbers: ref.frameNumber.map { [$0] }
                )
            }
            referencedSeries = [SegmentationReferencedSeries(
                seriesInstanceUID: seriesInstanceUID,
                referencedInstances: instances
            )]
        } else {
            referencedSeries = []
        }
        
        // Build the Segmentation object. The SOP Class follows PS3.4 B.5.1.25:
        // Segmentation Storage for BINARY/FRACTIONAL, Label Map Segmentation Storage for
        // LABELMAP.
        var segmentation = Segmentation(
            sopInstanceUID: finalSOPInstanceUID,
            sopClassUID: Segmentation.sopClassUID(for: segmentationType),
            seriesInstanceUID: seriesInstanceUID,
            studyInstanceUID: studyInstanceUID,
            instanceNumber: instanceNumber,
            seriesNumber: seriesNumber,
            contentLabel: contentLabel,
            contentDescription: contentDescription,
            contentCreatorName: contentCreatorName,
            contentDate: finalContentDate,
            contentTime: finalContentTime,
            segmentationType: segmentationType,
            segmentationFractionalType: fractionalType,
            maxFractionalValue: maxFractionalValue,
            segmentsOverlap: segmentsOverlap,
            pixelPaddingValue: finalPixelPaddingValue,
            numberOfSegments: sortedSegments.count,
            segments: finalSegments,
            frameOfReferenceUID: frameOfReferenceUID,
            dimensionOrganizationUID: UIDGenerator.generateUID().value,
            referencedSeries: referencedSeries,
            numberOfFrames: numberOfFrames,
            rows: rows,
            columns: columns,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: highBit,
            samplesPerPixel: 1,
            photometricInterpretation: paletteColor == nil ? "MONOCHROME2" : "PALETTE COLOR",
            pixelRepresentation: 0,
            sharedFunctionalGroups: nil,
            perFrameFunctionalGroups: perFrameFunctionalGroups,
            paletteColorLookupTable: paletteColorLookupTable,
            iccProfile: paletteColor?.iccProfile,
            colorSpace: paletteColor?.colorSpace
        )
        segmentation.patientAndStudy = patientAndStudy
        segmentation.equipment = equipment
        
        return (segmentation: segmentation, pixelData: combinedPixelData)
    }
    
    // MARK: - Private Helper Methods
    
    /// Validates segment number
    private func validateSegmentNumber(_ number: Int) throws {
        guard number >= 1 else {
            throw SegmentationBuilderError.invalidSegmentNumber(number)
        }
        
        // Check for duplicates
        if segments.contains(where: { $0.segment.segmentNumber == number }) {
            throw SegmentationBuilderError.duplicateSegmentNumber(number)
        }
    }
    
    /// Packs binary mask into bit-packed format
    ///
    /// Reference: PS3.5 Section 8.1.1 - Pixel Data Encoding of Related Data Elements (bit packing)
    /// - 8 pixels per byte
    /// - The first pixel in the least significant bit of the first byte, the next pixel
    ///   in the next more significant bit (PS3.5 8.1.1 and D.1: a concatenated stream of
    ///   bits "from the least significant bit of the first Pixel Cell")
    /// - Padding bits set to 0
    ///
    /// - Parameter mask: Binary mask with 0 or 1 values
    /// - Returns: Bit-packed data
    private func packBinaryMask(_ mask: [UInt8]) -> Data {
        let totalPixels = mask.count
        let bytesNeeded = (totalPixels + 7) / 8  // Round up to nearest byte

        var packedData = Data(count: bytesNeeded)

        for pixelIndex in 0..<totalPixels {
            if mask[pixelIndex] == 1 {
                let byteIndex = pixelIndex / 8
                let bitPosition = pixelIndex % 8   // least significant bit first
                packedData[byteIndex] |= (1 << bitPosition)
            }
        }

        return packedData
    }
    
    /// Scales fractional mask to target bit depth
    ///
    /// - Parameters:
    ///   - mask: Normalized mask values (0-255)
    ///   - bitsAllocated: Target bits allocated (8 or 16)
    ///   - maxValue: Maximum fractional value
    /// - Returns: Scaled pixel data
    private func scaleFractionalMask(_ mask: [UInt8], to bitsAllocated: Int, maxValue: Int) -> Data {
        if bitsAllocated == 8 {
            // Direct copy for 8-bit
            return Data(mask)
        } else {
            // Scale to 16-bit
            var data = Data(capacity: mask.count * 2)
            for value in mask {
                let scaled = UInt16((Double(value) / 255.0) * Double(maxValue))
                // Little-endian encoding
                data.append(UInt8(scaled & 0xFF))
                data.append(UInt8((scaled >> 8) & 0xFF))
            }
            return data
        }
    }
    
    /// Converts RGB color to CIELab color space
    ///
    /// This is a simplified conversion. For production use, consider using a
    /// more accurate color space conversion library.
    ///
    /// Reference: PS3.3 C.10.7.1.1 - Recommended Display CIELab Value
    ///
    /// - Parameters:
    ///   - r: Red component (0-255)
    ///   - g: Green component (0-255)
    ///   - b: Blue component (0-255)
    /// - Returns: CIELab color
    private func rgbToCIELab(r: UInt8, g: UInt8, b: UInt8) -> CIELabColor {
        // Simplified RGB to CIELab conversion
        // Normalize RGB to 0-1
        let rNorm = Double(r) / 255.0
        let gNorm = Double(g) / 255.0
        let bNorm = Double(b) / 255.0
        
        // Convert to linear RGB
        func toLinear(_ channel: Double) -> Double {
            if channel <= 0.04045 {
                return channel / 12.92
            } else {
                return pow((channel + 0.055) / 1.055, 2.4)
            }
        }
        
        let rLinear = toLinear(rNorm)
        let gLinear = toLinear(gNorm)
        let bLinear = toLinear(bNorm)
        
        // Convert to XYZ (D65 illuminant)
        let x = rLinear * 0.4124564 + gLinear * 0.3575761 + bLinear * 0.1804375
        let y = rLinear * 0.2126729 + gLinear * 0.7151522 + bLinear * 0.0721750
        let z = rLinear * 0.0193339 + gLinear * 0.1191920 + bLinear * 0.9503041
        
        // Normalize for D65 white point
        let xn = x / 0.95047
        let yn = y / 1.00000
        let zn = z / 1.08883
        
        // Convert to Lab
        func f(_ t: Double) -> Double {
            if t > 0.008856 {
                return pow(t, 1.0/3.0)
            } else {
                return (7.787 * t) + (16.0 / 116.0)
            }
        }
        
        let fx = f(xn)
        let fy = f(yn)
        let fz = f(zn)
        
        let L = (116.0 * fy) - 16.0
        let a = 500.0 * (fx - fy)
        let b_val = 200.0 * (fy - fz)
        
        // Convert to DICOM CIELab range (0-65535)
        // L: 0-100 -> 0-65535
        // a, b: -128 to 127 -> 0-65535
        let lScaled = Int((L / 100.0) * 65535.0)
        let aScaled = Int(((a + 128.0) / 255.0) * 65535.0)
        let bScaled = Int(((b_val + 128.0) / 255.0) * 65535.0)
        
        return CIELabColor(
            l: max(0, min(65535, lScaled)),
            a: max(0, min(65535, aScaled)),
            b: max(0, min(65535, bScaled))
        )
    }
}

// MARK: - DataSet Conversion

extension Segmentation {

    /// Segments Overlap (0062,0013) — no `Tag` constant exists in DICOMCore
    private static let segmentsOverlapTag = Tag(group: 0x0062, element: 0x0013)

    /// Converts the Segmentation and its pixel data to a DICOM DataSet
    ///
    /// Writes the Type 1 attributes of the Segmentation IOD modules the model carries
    /// (PS3.3 Table A.51-1): SOP Common, General Study/Series, Segmentation Series
    /// (Modality SEG, Series Number), Image Pixel, Segmentation Image (Table C.8.20-2 with
    /// the Content Identification Macro of Table 10-12 and the Segment Description Macro
    /// of Table C.8.20-4), Multi-frame Functional Groups (Table C.7.6.16-1) and Multi-frame
    /// Dimension (Table C.7.6.17-1). Values the model does not hold are defaulted where the
    /// standard fixes them (Image Type DERIVED\PRIMARY, Samples per Pixel 1, Lossy Image
    /// Compression 00) and otherwise left to the caller (Patient, Equipment, Frame of
    /// Reference when absent, Common Instance Reference).
    ///
    /// - BINARY/FRACTIONAL: one Dimension Index on Referenced Segment Number (0062,000B)
    ///   in the Segment Identification Sequence (0062,000A); each frame's Segmentation
    ///   Functional Group is written.
    /// - LABELMAP: no Segmentation Functional Group (Table A.51-2); the Dimension Index is
    ///   In-Stack Position Number (0020,9057) in the Frame Content Sequence (0020,9111);
    ///   Segments Overlap NO; Pixel Padding Value when set (A.51.4).
    ///
    /// - PALETTE COLOR (LABELMAP only): the Palette Color Lookup Table Module (C.7.9) and
    ///   ICC Profile Module (C.11.15) the model carries; no Recommended Display CIELab
    ///   Value (Table C.8.20-2). Neither module is written for MONOCHROME2 (A.1.3.2).
    ///
    /// This method does not check the model; a model that breaks a Segmentation IOD rule is
    /// written as it is. ``buildDataSet(pixelData:)`` checks it first and throws.
    ///
    /// - Parameter pixelData: The frame data returned by `SegmentationBuilder.build()`
    /// - Returns: A DataSet ready for `DICOMFile.create`
    @available(*, deprecated, message: "Writes a model that breaks the Segmentation IOD rules without saying so (PS3.3 2026a A.51, C.8.20.2); use buildDataSet(pixelData:), which throws SegmentationDataSetError instead")
    public func toDataSet(pixelData: Data) -> DataSet {
        writeDataSet(pixelData: pixelData)
    }

    /// Converts the Segmentation and its pixel data to a DICOM DataSet, after checking the
    /// Segmentation IOD rules the model can break
    ///
    /// Writes what `toDataSet(pixelData:)` describes. Throws ``SegmentationDataSetError``
    /// when:
    /// - a segment has no Segmented Property Category or Type code: both Code Sequences are
    ///   Type 1 in the Segment Description Macro (PS3.3 2026a Table C.8.20-4);
    /// - a segment has only one of Tracking ID (0062,0020) and Tracking UID (0062,0021):
    ///   each is Type 1C, "Required if" the other "is present" (Table C.8.20-4). A value
    ///   that is empty or all spaces does not count as present;
    /// - Photometric Interpretation (0028,0004) is not an Enumerated Value for the
    ///   Segmentation Type: MONOCHROME2 for BINARY and FRACTIONAL, MONOCHROME2 or PALETTE
    ///   COLOR for LABELMAP (PS3.3 2026a Table C.8.20-2);
    /// - it is PALETTE COLOR and the Palette Color Lookup Table (C.7.9) or ICC Profile
    ///   (C.11.15) the IOD then requires is missing (Table A.51-1), the table breaks
    ///   C.7.6.3.1.5 (identical first and second descriptor values, 8 or 16 bits per entry,
    ///   one datum per entry) or the profile breaks C.11.15.1.1 ("scnr" class, RGB colour
    ///   space, Lab or XYZ PCS), or a segment has a Recommended Display CIELab Value
    ///   (Table C.8.20-2: "shall not be present");
    /// - it is not PALETTE COLOR and the model carries either module, which "shall not be
    ///   present" when the condition of a Conditional Module is not met (A.1.3.2).
    ///
    /// - Parameter pixelData: The frame data returned by `SegmentationBuilder.build()`
    /// - Returns: A DataSet ready for `DICOMFile.create`
    public func buildDataSet(pixelData: Data) throws -> DataSet {
        try validateForDataSet()
        return writeDataSet(pixelData: pixelData)
    }

    /// Whether an optional string carries a value other than spaces (PS3.5 6.2 padding)
    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The Segmentation IOD rules ``buildDataSet(pixelData:)`` enforces
    private func validateForDataSet() throws {
        // Table C.8.20-4 (Segment Description Macro): Segmented Property Category Code
        // Sequence (0062,0003) and Segmented Property Type Code Sequence (0062,000F) are
        // Type 1 with "Only a single Item" (Baseline CID 7150 / CID 7151)
        for segment in segments {
            guard segment.category != nil else {
                throw SegmentationDataSetError.missingSegmentedPropertyCategory(segmentNumber: segment.segmentNumber)
            }
            guard segment.type != nil else {
                throw SegmentationDataSetError.missingSegmentedPropertyType(segmentNumber: segment.segmentNumber)
            }
            // Table C.8.20-4: Tracking ID (0062,0020) 1C "Required if Tracking UID
            // (0062,0021) is present", and Tracking UID 1C "Required if Tracking ID
            // (0062,0020) is present". The writer emits whichever is non-nil, so either
            // both carry a value or neither is set.
            let hasTrackingID = Segmentation.hasValue(segment.trackingID)
            let hasTrackingUID = Segmentation.hasValue(segment.trackingUID)
            if segment.trackingID != nil, !hasTrackingUID {
                throw SegmentationDataSetError.missingTrackingUID(segmentNumber: segment.segmentNumber)
            }
            if segment.trackingUID != nil, !hasTrackingID {
                throw SegmentationDataSetError.missingTrackingID(segmentNumber: segment.segmentNumber)
            }
        }
        // Table C.8.20-2: Photometric Interpretation Enumerated Values by Segmentation Type
        guard segmentationType.allowedPhotometricInterpretations.contains(photometricInterpretation) else {
            throw SegmentationDataSetError.photometricInterpretationNotAllowed(
                photometricInterpretation, segmentationType: segmentationType)
        }
        guard photometricInterpretation == Segmentation.paletteColor else {
            // A.1.3.2: a Conditional Module whose condition is not met shall not be present
            if paletteColorLookupTable != nil {
                throw SegmentationDataSetError.moduleNotAllowed("Palette Color Lookup Table")
            }
            if iccProfile != nil {
                throw SegmentationDataSetError.moduleNotAllowed("ICC Profile")
            }
            return
        }
        // Table A.51-1: both modules are required if Photometric Interpretation is PALETTE COLOR
        guard let lut = paletteColorLookupTable else {
            throw SegmentationDataSetError.missingModule("Palette Color Lookup Table")
        }
        guard let profile = iccProfile else {
            throw SegmentationDataSetError.missingModule("ICC Profile")
        }
        try Segmentation.validatePaletteColorLookupTable(lut)
        try Segmentation.validateICCProfile(profile)
        // Table C.8.20-2: Recommended Display CIELab Value "Shall not be present if
        // Segmentation Type (0062,0001) is LABELMAP and Photometric Interpretation
        // (0028,0004) is PALETTE COLOR"
        if let segment = segments.first(where: { $0.recommendedDisplayCIELabValue != nil }) {
            throw SegmentationDataSetError.recommendedDisplayCIELabValueNotAllowed(segmentNumber: segment.segmentNumber)
        }
    }

    /// PS3.3 2026a C.7.6.3.1.5: the first and second descriptor values are identical for
    /// Red, Green and Blue, as is the third; in the Segmentation IOD the third (bits per
    /// entry) is 8 or 16. Each table holds one datum per entry.
    static func validatePaletteColorLookupTable(_ lut: PaletteColorLUT) throws {
        let descriptors = [lut.redDescriptor, lut.greenDescriptor, lut.blueDescriptor]
        guard Set(descriptors.map(\.numberOfEntries)).count == 1,
              Set(descriptors.map(\.firstMappedValue)).count == 1,
              Set(descriptors.map(\.bitsPerEntry)).count == 1 else {
            throw SegmentationDataSetError.invalidPaletteColorLookupTable(
                "the Red, Green and Blue descriptors differ (C.7.6.3.1.5)")
        }
        let descriptor = lut.redDescriptor
        guard descriptor.bitsPerEntry == 8 || descriptor.bitsPerEntry == 16 else {
            throw SegmentationDataSetError.invalidPaletteColorLookupTable(
                "\(descriptor.bitsPerEntry) bits per entry; the Segmentation IOD allows 8 or 16 (C.7.6.3.1.5)")
        }
        guard (1...65536).contains(descriptor.numberOfEntries),
              (0...0xFFFF).contains(descriptor.firstMappedValue) else {
            throw SegmentationDataSetError.invalidPaletteColorLookupTable(
                "\(descriptor.numberOfEntries) entries from \(descriptor.firstMappedValue); Pixel Representation 0 limits both to 16 bits unsigned (C.7.6.3.1.5)")
        }
        for (name, table) in [("Red", lut.redLUT), ("Green", lut.greenLUT), ("Blue", lut.blueLUT)]
        where table.count != descriptor.numberOfEntries {
            throw SegmentationDataSetError.invalidPaletteColorLookupTable(
                "\(name) table has \(table.count) entries, the descriptor \(descriptor.numberOfEntries)")
        }
    }

    /// PS3.3 2026a C.11.15.1.1: header bytes 12–15 (device class) "scnr", 16–19 (colour
    /// space) "RGB ", 20–23 (PCS) "Lab " or "XYZ "
    static func validateICCProfile(_ profile: Data) throws {
        guard profile.count >= 128 else {
            throw SegmentationDataSetError.invalidICCProfile("\(profile.count) bytes, shorter than the 128-byte ICC header")
        }
        func signature(_ offset: Int) -> String {
            let start = profile.startIndex + offset
            return String(decoding: profile[start..<start + 4], as: UTF8.self)
        }
        guard signature(12) == "scnr" else {
            throw SegmentationDataSetError.invalidICCProfile("device class \"\(signature(12))\", not the Input Device class \"scnr\" (C.11.15.1.1)")
        }
        guard signature(16) == "RGB " else {
            throw SegmentationDataSetError.invalidICCProfile("colour space \"\(signature(16))\", not \"RGB\" (C.11.15.1.1)")
        }
        guard signature(20) == "Lab " || signature(20) == "XYZ " else {
            throw SegmentationDataSetError.invalidICCProfile("PCS \"\(signature(20))\", not \"Lab\" or \"XYZ\" (C.11.15.1.1)")
        }
    }

    /// Photometric Interpretation PALETTE COLOR (Table C.8.20-2)
    static let paletteColor = "PALETTE COLOR"

    private func writeDataSet(pixelData: Data) -> DataSet {
        var dataSet = DataSet()

        // SOP Common Module
        dataSet.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        dataSet.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)

        // Patient Module (Table C.7-1) and General Study Module (Table C.7-3), both M in
        // Table A.51-1: the Type 2 attributes, zero length when unknown (D71, 2026-10-01)
        for (tag, vr, value) in patientAndStudy.elements {
            dataSet.setString(value ?? "", for: tag, vr: vr)
        }

        // General Equipment (Table C.7-8) and Enhanced General Equipment (Table C.7-8b)
        // Modules, both M in Table A.51-1: Manufacturer, Manufacturer's Model Name, Device
        // Serial Number and Software Versions, Type 1 in Table C.7-8b (D71, 2026-10-01)
        dataSet.setString(equipment.manufacturer, for: .manufacturer, vr: .LO)
        dataSet.setString(equipment.manufacturerModelName, for: .manufacturerModelName, vr: .LO)
        dataSet.setString(equipment.deviceSerialNumber, for: .deviceSerialNumber, vr: .LO)
        dataSet.setString(equipment.softwareVersions, for: .softwareVersions, vr: .LO)

        // General Study / General Series / Segmentation Series (Table C.8.20-1)
        dataSet.setString(studyInstanceUID, for: .studyInstanceUID, vr: .UI)
        dataSet.setString(seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)
        dataSet.setString(Modality.seg.rawValue, for: .modality, vr: .CS)
        dataSet.setString(String(seriesNumber ?? 1), for: .seriesNumber, vr: .IS)

        // Frame of Reference
        if let frameOfReferenceUID = frameOfReferenceUID {
            dataSet.setString(frameOfReferenceUID, for: .frameOfReferenceUID, vr: .UI)
        }

        // Segmentation Image Module (Table C.8.20-2)
        dataSet.setStrings(["DERIVED", "PRIMARY"], for: .imageType, vr: .CS)
        // Content Identification Macro (Table 10-12): Instance Number 1, Content Label 1,
        // Content Description 2; Content Creator's Name 3 (Table 10.9.3-1), written zero length when unknown
        dataSet.setString(String(instanceNumber ?? 1), for: .instanceNumber, vr: .IS)
        dataSet.setString(contentLabel ?? "SEGMENTATION", for: .contentLabel, vr: .CS)
        dataSet.setString(contentDescription ?? "", for: .contentDescription, vr: .LO)
        dataSet.setString(contentCreatorName?.dicomString ?? "", for: .contentCreatorName, vr: .PN)
        if let contentDate = contentDate {
            dataSet.setString(contentDate.dicomString, for: .contentDate, vr: .DA)
        }
        if let contentTime = contentTime {
            dataSet.setString(contentTime.dicomString, for: .contentTime, vr: .TM)
        }

        // Image Pixel attributes the module enumerates
        dataSet.setUInt16(UInt16(samplesPerPixel), for: .samplesPerPixel)
        dataSet.setString(photometricInterpretation, for: .photometricInterpretation, vr: .CS)
        dataSet.setUInt16(UInt16(pixelRepresentation), for: .pixelRepresentation)
        dataSet.setUInt16(UInt16(bitsAllocated), for: .bitsAllocated)
        dataSet.setUInt16(UInt16(bitsStored), for: .bitsStored)
        dataSet.setUInt16(UInt16(highBit), for: .highBit)
        dataSet.setUInt16(UInt16(rows), for: .rows)
        dataSet.setUInt16(UInt16(columns), for: .columns)
        dataSet.setString(String(numberOfFrames), for: .numberOfFrames, vr: .IS)
        dataSet.setString("00", for: .lossyImageCompression, vr: .CS)

        dataSet.setString(segmentationType.rawValue, for: .segmentationType, vr: .CS)
        if segmentationType == .fractional {
            // Segmentation Fractional Type and Maximum Fractional Value: 1C, required if FRACTIONAL
            dataSet.setString((segmentationFractionalType ?? .probability).rawValue, for: .segmentationFractionalType, vr: .CS)
            dataSet.setUInt16(UInt16(clamping: maxFractionalValue ?? 255), for: .maximumFractionalValue)
        }
        if let overlap = segmentsOverlap {
            dataSet.setString(overlap.rawValue, for: Segmentation.segmentsOverlapTag, vr: .CS)
        }
        if segmentationType == .labelmap, let padding = pixelPaddingValue {
            // A.51.4: Pixel Padding Value only for LABELMAP; Pixel Representation is 0 so US
            dataSet.setUInt16(UInt16(clamping: padding), for: .pixelPaddingValue)
        }

        // Segment Sequence (Table C.8.20-4 Segment Description Macro). Recommended Display
        // CIELab Value is not written with PALETTE COLOR (Table C.8.20-2).
        let cieLabAllowed = !(segmentationType == .labelmap && photometricInterpretation == Segmentation.paletteColor)
        dataSet.setSequence(segments.map { Segmentation.segmentItem($0, cieLabAllowed: cieLabAllowed) }, for: .segmentSequence)

        // Multi-frame Functional Groups Module (Table C.7.6.16-1)
        let sharedItem = sharedFunctionalGroups.map { Segmentation.functionalGroupItem($0, segmentationType: segmentationType) }
            ?? SequenceItem()
        dataSet.setSequence([sharedItem], for: .sharedFunctionalGroupsSequence)
        if !perFrameFunctionalGroups.isEmpty {
            let items = perFrameFunctionalGroups.enumerated().map { index, group -> SequenceItem in
                var frameGroup = group
                if segmentationType != .labelmap, group.frameContent?.dimensionIndexValues == nil {
                    // Dimension Index Values are 1C, required when a Dimension Index Sequence
                    // exists; for BINARY/FRACTIONAL the single index is the rank of the
                    // referenced segment.
                    let rank = group.segmentIdentification.flatMap { ident in
                        segments.firstIndex { $0.segmentNumber == ident.referencedSegmentNumber }
                    } ?? index
                    frameGroup = FunctionalGroup(
                        segmentIdentification: group.segmentIdentification,
                        derivationImage: group.derivationImage,
                        frameContent: FrameContent(
                            frameAcquisitionNumber: group.frameContent?.frameAcquisitionNumber,
                            frameReferenceDateTime: group.frameContent?.frameReferenceDateTime,
                            frameAcquisitionDateTime: group.frameContent?.frameAcquisitionDateTime,
                            dimensionIndexValues: [rank + 1],
                            stackID: group.frameContent?.stackID,
                            inStackPositionNumber: group.frameContent?.inStackPositionNumber
                        ),
                        planePosition: group.planePosition,
                        planeOrientation: group.planeOrientation
                    )
                }
                return Segmentation.functionalGroupItem(frameGroup, segmentationType: segmentationType)
            }
            dataSet.setSequence(items, for: .perFrameFunctionalGroupsSequence)
        }

        // Multi-frame Dimension Module (Table C.7.6.17-1)
        let organizationUID = dimensionOrganizationUID ?? UIDGenerator.generateUID().value
        dataSet.setSequence([SequenceItem(elements: [
            DataElement.string(tag: .dimensionOrganizationUID, vr: .UI, value: organizationUID),
        ])], for: .dimensionOrganizationSequence)
        let (indexPointer, groupPointer, label): (Tag, Tag, String)
        if segmentationType == .labelmap {
            (indexPointer, groupPointer, label) = (.inStackPositionNumber, .frameContentSequence, "Slice")
        } else {
            (indexPointer, groupPointer, label) = (.referencedSegmentNumber, .segmentIdentificationSequence, "Segment")
        }
        dataSet.setSequence([SequenceItem(elements: [
            DataElement.attributeTag(tag: .dimensionIndexPointer, value: indexPointer),
            DataElement.attributeTag(tag: .functionalGroupPointer, value: groupPointer),
            DataElement.string(tag: .dimensionOrganizationUID, vr: .UI, value: organizationUID),
            DataElement.string(tag: .dimensionDescriptionLabel, vr: .LO, value: label),
        ])], for: .dimensionIndexSequence)

        // Common Instance Reference (Referenced Series Sequence) when the model has one
        if !referencedSeries.isEmpty {
            let seriesItems = referencedSeries.map { series -> SequenceItem in
                let instanceItems = series.referencedInstances.map { instance -> SequenceItem in
                    var elements: [DataElement] = [
                        DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: instance.sopClassUID),
                        DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: instance.sopInstanceUID),
                    ]
                    if let frames = instance.referencedFrameNumbers, !frames.isEmpty {
                        elements.append(DataElement.strings(tag: .referencedFrameNumber, vr: .IS, values: frames.map(String.init)))
                    }
                    return SequenceItem(elements: elements)
                }
                var seriesData = DataSet()
                seriesData.setString(series.seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)
                seriesData.setSequence(instanceItems, for: .referencedInstanceSequence)
                return SequenceItem(elements: seriesData.allElements)
            }
            dataSet.setSequence(seriesItems, for: .referencedSeriesSequence)
        }

        if photometricInterpretation == Segmentation.paletteColor {
            // Palette Color Lookup Table Module (C.7.9, Table C.7-22a), required with
            // PALETTE COLOR (Table A.51-1); segmented tables "shall not be present in a
            // ... Segmentation IOD", so the Red/Green/Blue Data (0028,1201-1203) are written.
            if let lut = paletteColorLookupTable {
                Segmentation.writePaletteColorLookupTable(lut, to: &dataSet)
            }
            // ICC Profile Module (C.11.15, Table C.11.15-1), required with PALETTE COLOR
            if let profile = iccProfile {
                dataSet[.iccProfile] = DataElement(
                    tag: .iccProfile, vr: .OB, length: UInt32(profile.count), valueData: profile)
                if let colorSpace = colorSpace {
                    dataSet.setString(colorSpace, for: .colorSpace, vr: .CS)
                }
            }
        }

        // Pixel Data (7FE0,0010): OB for 1- and 8-bit cells, OW for 16-bit
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: bitsAllocated > 8 ? .OW : .OB, data: pixelData)

        return dataSet
    }

    /// Segment Description Macro Item (Table C.8.20-4) plus the Segmentation Image Module
    /// additions (Segment Algorithm Name, Recommended Display CIELab Value, Tracking ID/UID)
    private static func segmentItem(_ segment: Segment, cieLabAllowed: Bool) -> SequenceItem {
        var elements: [DataElement] = [
            DataElement.uint16(tag: .segmentNumber, value: UInt16(clamping: segment.segmentNumber)),
            DataElement.string(tag: .segmentLabel, vr: .LO, value: segment.segmentLabel),
            // Segment Algorithm Type is Type 1 with Enumerated Values AUTOMATIC,
            // SEMIAUTOMATIC, MANUAL; a segment built without one is written as MANUAL
            // (user-entered), the only term that does not require an algorithm name.
            DataElement.string(tag: .segmentAlgorithmType, vr: .CS, value: (segment.segmentAlgorithmType ?? .manual).rawValue),
        ]
        if let description = segment.segmentDescription {
            elements.append(DataElement.string(tag: .segmentDescription, vr: .ST, value: description))
        }
        if let name = segment.segmentAlgorithmName {
            elements.append(DataElement.string(tag: .segmentAlgorithmName, vr: .LO, value: name))
        }
        if let category = segment.category {
            elements.append(codeSequence(tag: .segmentedPropertyCategoryCodeSequence, category))
        }
        if let type = segment.type {
            elements.append(codeSequence(tag: .segmentedPropertyTypeCodeSequence, type))
        }
        if let region = segment.anatomicRegion {
            elements.append(codeSequence(tag: .anatomicRegionSequence, region))
        }
        if let modifier = segment.anatomicRegionModifier {
            elements.append(codeSequence(tag: .anatomicRegionModifierSequence, modifier))
        }
        if cieLabAllowed, let color = segment.recommendedDisplayCIELabValue {
            elements.append(DataElement.uint16s(
                tag: .recommendedDisplayCIELabValue,
                values: [UInt16(clamping: color.l), UInt16(clamping: color.a), UInt16(clamping: color.b)]
            ))
        }
        if let trackingID = segment.trackingID {
            elements.append(DataElement.string(tag: .trackingID, vr: .UT, value: trackingID))
        }
        if let trackingUID = segment.trackingUID {
            elements.append(DataElement.string(tag: .trackingUID, vr: .UI, value: trackingUID))
        }
        return SequenceItem(elements: elements)
    }

    /// Red, Green and Blue Palette Color Lookup Table Descriptor (0028,1101-1103) and Data
    /// (0028,1201-1203), PS3.3 2026a Table C.7-22a and C.7.6.3.1.5/C.7.6.3.1.6
    ///
    /// The descriptor is US: its VR follows Pixel Representation, which is 0 in the
    /// Segmentation IOD (Table C.8.20-2); 2^16 entries are written as 0. 16-bit entries are
    /// one little-endian word each; 8-bit entries one byte each ("equivalent to 8 bits
    /// allocated"), padded to even length. VRs per PS3.6 2026a Table 6-1 (US or SS, OW).
    private static func writePaletteColorLookupTable(_ lut: PaletteColorLUT, to dataSet: inout DataSet) {
        let channels: [(Tag, Tag, PaletteColorLUT.Descriptor, [UInt16])] = [
            (.redPaletteColorLookupTableDescriptor, .redPaletteColorLookupTableData, lut.redDescriptor, lut.redLUT),
            (.greenPaletteColorLookupTableDescriptor, .greenPaletteColorLookupTableData, lut.greenDescriptor, lut.greenLUT),
            (.bluePaletteColorLookupTableDescriptor, .bluePaletteColorLookupTableData, lut.blueDescriptor, lut.blueLUT),
        ]
        for (descriptorTag, dataTag, descriptor, table) in channels {
            dataSet[descriptorTag] = DataElement.uint16s(tag: descriptorTag, values: [
                UInt16(truncatingIfNeeded: descriptor.numberOfEntries),   // 65536 -> 0
                UInt16(truncatingIfNeeded: descriptor.firstMappedValue),
                UInt16(truncatingIfNeeded: descriptor.bitsPerEntry),
            ])
            var bytes = Data(capacity: table.count * 2)
            if descriptor.bitsPerEntry == 8 {
                // PaletteColorLUT holds 8-bit entries in the high byte
                bytes.append(contentsOf: table.map { UInt8($0 >> 8) })
                if bytes.count % 2 == 1 { bytes.append(0) }
            } else {
                for value in table {
                    bytes.append(UInt8(value & 0xFF))
                    bytes.append(UInt8(value >> 8))
                }
            }
            dataSet[dataTag] = DataElement(tag: dataTag, vr: .OW, length: UInt32(bytes.count), valueData: bytes)
        }
    }

    /// Code Sequence Macro Item (Table 8.8-1) wrapped in a single-Item sequence element
    private static func codeSequence(tag: Tag, _ concept: CodedConcept) -> DataElement {
        var elements: [DataElement] = [
            DataElement.string(tag: .codeValue, vr: .SH, value: concept.codeValue),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: concept.codingSchemeDesignator),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: concept.codeMeaning),
        ]
        if let version = concept.codingSchemeVersion {
            elements.append(DataElement.string(tag: .codingSchemeVersion, vr: .SH, value: version))
        }
        return sequenceElement(tag: tag, items: [SequenceItem(elements: elements)])
    }

    private static func sequenceElement(tag: Tag, items: [SequenceItem]) -> DataElement {
        let writer = DICOMWriter()
        var data = Data()
        for item in items {
            data.append(writer.serializeSequenceItem(item))
        }
        return DataElement(tag: tag, vr: .SQ, length: UInt32(data.count), valueData: data, sequenceItems: items)
    }

    /// One Item of the Shared or Per-Frame Functional Groups Sequence
    private static func functionalGroupItem(_ group: FunctionalGroup, segmentationType: SegmentationType) -> SequenceItem {
        var elements: [DataElement] = []

        // Segmentation Macro (Table C.8.20-3) — not for LABELMAP (Table A.51-2)
        if segmentationType != .labelmap, let ident = group.segmentIdentification {
            elements.append(sequenceElement(tag: .segmentIdentificationSequence, items: [SequenceItem(elements: [
                DataElement.uint16(tag: .referencedSegmentNumber, value: UInt16(clamping: ident.referencedSegmentNumber)),
            ])]))
        }

        // Frame Content Macro (Table C.7.6.16-3)
        if let content = group.frameContent {
            var contentElements: [DataElement] = []
            if let number = content.frameAcquisitionNumber {
                contentElements.append(DataElement.uint16(tag: .frameAcquisitionNumber, value: UInt16(clamping: number)))
            }
            if let dateTime = content.frameReferenceDateTime {
                contentElements.append(DataElement.string(tag: .frameReferenceDateTime, vr: .DT, value: dateTime))
            }
            if let dateTime = content.frameAcquisitionDateTime {
                contentElements.append(DataElement.string(tag: .frameAcquisitionDateTime, vr: .DT, value: dateTime))
            }
            if let values = content.dimensionIndexValues {
                contentElements.append(DataElement.uint32s(tag: .dimensionIndexValues, values: values.map { UInt32(clamping: $0) }))
            }
            if let stackID = content.stackID {
                contentElements.append(DataElement.string(tag: .stackID, vr: .SH, value: stackID))
                // In-Stack Position Number is 1C, required if Stack ID is present
                contentElements.append(DataElement.uint32(tag: .inStackPositionNumber, value: UInt32(clamping: content.inStackPositionNumber ?? 1)))
            } else if let position = content.inStackPositionNumber {
                contentElements.append(DataElement.uint32(tag: .inStackPositionNumber, value: UInt32(clamping: position)))
            }
            elements.append(sequenceElement(tag: .frameContentSequence, items: [SequenceItem(elements: contentElements)]))
        }

        // Plane Position (Patient) / Plane Orientation (Patient) Macros
        if let position = group.planePosition {
            elements.append(sequenceElement(tag: .planePositionSequence, items: [SequenceItem(elements: [
                DataElement.strings(tag: .imagePositionPatient, vr: .DS, values: position.imagePositionPatient.map { String($0) }),
            ])]))
        }
        if let orientation = group.planeOrientation {
            elements.append(sequenceElement(tag: .planeOrientationSequence, items: [SequenceItem(elements: [
                DataElement.strings(tag: .imageOrientationPatient, vr: .DS, values: orientation.imageOrientationPatient.map { String($0) }),
            ])]))
        }

        // Derivation Image Macro
        if let derivation = group.derivationImage {
            var derivationElements: [DataElement] = []
            if let description = derivation.derivationDescription {
                derivationElements.append(DataElement.string(tag: .derivationDescription, vr: .ST, value: description))
            }
            if let code = derivation.derivationCode {
                derivationElements.append(codeSequence(tag: .derivationCodeSequence, code))
            }
            let sourceItems = derivation.sourceImages.map { source -> SequenceItem in
                var sourceElements: [DataElement] = [
                    DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: source.sopClassUID),
                    DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: source.sopInstanceUID),
                ]
                if let frame = source.referencedFrameNumber {
                    sourceElements.append(DataElement.string(tag: .referencedFrameNumber, vr: .IS, value: String(frame)))
                }
                if let purpose = source.purposeOfReference {
                    sourceElements.append(codeSequence(tag: .purposeOfReferenceCodeSequence, purpose))
                }
                return SequenceItem(elements: sourceElements)
            }
            derivationElements.append(sequenceElement(tag: .sourceImageSequence, items: sourceItems))
            elements.append(sequenceElement(tag: .derivationImageSequence, items: [SequenceItem(elements: derivationElements)]))
        }

        return SequenceItem(elements: elements)
    }
}

// MARK: - SegmentationDataSetError

/// A Segmentation IOD rule the model breaks, found by ``Segmentation/buildDataSet(pixelData:)``
///
/// Reference: PS3.3 2026a A.51 (Segmentation IOD), C.8.20.2 (Segmentation Image Module)
public enum SegmentationDataSetError: Error, CustomStringConvertible, Equatable {
    /// Photometric Interpretation is not an Enumerated Value for the Segmentation Type
    /// (Table C.8.20-2)
    case photometricInterpretationNotAllowed(String, segmentationType: SegmentationType)
    /// A module the IOD requires with PALETTE COLOR is missing (Table A.51-1)
    case missingModule(String)
    /// A Conditional Module is present although its condition is not met (A.1.3.2)
    case moduleNotAllowed(String)
    /// The Palette Color Lookup Table breaks C.7.6.3.1.5
    case invalidPaletteColorLookupTable(String)
    /// The ICC Profile breaks C.11.15.1.1
    case invalidICCProfile(String)
    /// Recommended Display CIELab Value with a PALETTE COLOR LABELMAP (Table C.8.20-2)
    case recommendedDisplayCIELabValueNotAllowed(segmentNumber: Int)
    /// A segment without Segmented Property Category Code Sequence (0062,0003), Type 1
    /// (Table C.8.20-4)
    case missingSegmentedPropertyCategory(segmentNumber: Int)
    /// A segment without Segmented Property Type Code Sequence (0062,000F), Type 1
    /// (Table C.8.20-4)
    case missingSegmentedPropertyType(segmentNumber: Int)
    /// A segment with Tracking ID (0062,0020) but no Tracking UID (0062,0021); Tracking UID
    /// is Type 1C, "Required if Tracking ID (0062,0020) is present" (Table C.8.20-4)
    case missingTrackingUID(segmentNumber: Int)
    /// A segment with Tracking UID (0062,0021) but no Tracking ID (0062,0020); Tracking ID
    /// is Type 1C, "Required if Tracking UID (0062,0021) is present" (Table C.8.20-4)
    case missingTrackingID(segmentNumber: Int)

    public var description: String {
        switch self {
        case .photometricInterpretationNotAllowed(let value, let type):
            return "Photometric Interpretation \(value) is not allowed for Segmentation Type \(type.rawValue); allowed: \(type.allowedPhotometricInterpretations.joined(separator: ", ")) (PS3.3 Table C.8.20-2)"
        case .missingModule(let module):
            return "The \(module) Module is required when Photometric Interpretation is PALETTE COLOR (PS3.3 Table A.51-1)"
        case .moduleNotAllowed(let module):
            return "The \(module) Module shall not be present unless Photometric Interpretation is PALETTE COLOR (PS3.3 Table A.51-1, A.1.3.2)"
        case .invalidPaletteColorLookupTable(let reason):
            return "Invalid Palette Color Lookup Table: \(reason)"
        case .invalidICCProfile(let reason):
            return "Invalid ICC Profile: \(reason)"
        case .recommendedDisplayCIELabValueNotAllowed(let number):
            return "Segment \(number): Recommended Display CIELab Value shall not be present in a PALETTE COLOR LABELMAP (PS3.3 Table C.8.20-2)"
        case .missingSegmentedPropertyCategory(let number):
            return "Segment \(number): Segmented Property Category Code Sequence (0062,0003) is Type 1 (PS3.3 Table C.8.20-4, CID 7150)"
        case .missingSegmentedPropertyType(let number):
            return "Segment \(number): Segmented Property Type Code Sequence (0062,000F) is Type 1 (PS3.3 Table C.8.20-4, CID 7151)"
        case .missingTrackingUID(let number):
            return "Segment \(number): Tracking UID (0062,0021) is required when Tracking ID (0062,0020) is present (PS3.3 Table C.8.20-4)"
        case .missingTrackingID(let number):
            return "Segment \(number): Tracking ID (0062,0020) is required when Tracking UID (0062,0021) is present (PS3.3 Table C.8.20-4)"
        }
    }
}

// MARK: - SegmentationBuilderError

/// Errors that can occur during segmentation building
public enum SegmentationBuilderError: Error, CustomStringConvertible {
    /// Invalid mask dimensions
    case invalidMaskDimensions(expected: Int, got: Int)
    
    /// Invalid binary value (must be 0 or 1)
    case invalidBinaryValue(Int, index: Int)
    
    /// Invalid segment number (must be >= 1)
    case invalidSegmentNumber(Int)
    
    /// Duplicate segment number
    case duplicateSegmentNumber(Int)
    
    /// No segments added
    case noSegmentsAdded
    
    /// Invalid max fractional value
    case invalidMaxFractionalValue(Int)
    
    /// Invalid segmentation type for operation
    case invalidSegmentationType(expected: SegmentationType, got: SegmentationType)

    /// A LABELMAP needs at least one frame
    case noFramesAdded

    /// A LABELMAP pixel value (or the Pixel Padding Value, when `frame` is nil) is not
    /// described by any Segment Sequence Item (PS3.3 C.8.20.2.3.3)
    case labelmapValueNotDescribed(Int, frame: Int?, index: Int?)

    /// LABELMAP Bits Allocated must be 8 or 16 (PS3.3 Table C.8.20-2)
    case invalidBitsAllocated(Int)

    /// A Segment Number does not fit in the LABELMAP Bits Allocated
    case segmentNumberExceedsBitsAllocated(Int, bitsAllocated: Int)

    /// Image Position/Orientation (Patient) with the wrong number of values
    case invalidPlaneGeometry(String)

    public var description: String {
        switch self {
        case .noFramesAdded:
            return "No frames added to LABELMAP segmentation"
        case .labelmapValueNotDescribed(let value, let frame, let index):
            if let frame = frame, let index = index {
                return "LABELMAP pixel value \(value) at frame \(frame), index \(index) is not a described Segment Number (PS3.3 C.8.20.2.3.3)"
            }
            return "Pixel Padding Value \(value) is not a described Segment Number (PS3.3 C.8.20.2.4)"
        case .invalidBitsAllocated(let bits):
            return "Invalid LABELMAP Bits Allocated \(bits) (must be 8 or 16)"
        case .segmentNumberExceedsBitsAllocated(let number, let bits):
            return "Segment Number \(number) does not fit in \(bits) bits"
        case .invalidPlaneGeometry(let message):
            return "Invalid plane geometry: \(message)"
        case .invalidMaskDimensions(let expected, let got):
            return "Invalid mask dimensions: expected \(expected) pixels, got \(got)"
        case .invalidBinaryValue(let value, let index):
            return "Invalid binary value \(value) at index \(index) (must be 0 or 1)"
        case .invalidSegmentNumber(let number):
            return "Invalid segment number \(number) (must be >= 1)"
        case .duplicateSegmentNumber(let number):
            return "Duplicate segment number \(number)"
        case .noSegmentsAdded:
            return "No segments added to segmentation"
        case .invalidMaxFractionalValue(let value):
            return "Invalid max fractional value \(value) (must be 1-65535)"
        case .invalidSegmentationType(let expected, let got):
            return "Invalid segmentation type: expected \(expected), got \(got)"
        }
    }
}
