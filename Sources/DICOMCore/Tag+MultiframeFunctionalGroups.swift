import Foundation

/// Multi-frame Functional Group macro tags, Multi-frame Dimension / Concatenation
/// attributes and the legacy multi-frame vector attributes (NM, cine) used by the
/// split/merge engines. Reference: PS3.3 C.7.6.16 / C.7.6.17 / C.8.4.8.
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {

    // MARK: - Frame Content / identity (C.7.6.16.2.2)

    /// Frame Type (0008,9007)
    public static let frameType = Tag(group: 0x0008, element: 0x9007)

    /// Temporal Position Index (0020,9128)
    public static let temporalPositionIndex = Tag(group: 0x0020, element: 0x9128)

    /// Frame Comments (0020,9158)
    public static let frameComments = Tag(group: 0x0020, element: 0x9158)

    /// Frame Acquisition Duration (0018,9220)
    public static let frameAcquisitionDuration = Tag(group: 0x0018, element: 0x9220)

    /// Acquisition Number (0020,0012)
    public static let acquisitionNumber = Tag(group: 0x0020, element: 0x0012)

    /// Temporal Position Identifier (0020,0100)
    public static let temporalPositionIdentifier = Tag(group: 0x0020, element: 0x0100)

    /// Number of Temporal Positions (0020,0105)
    public static let numberOfTemporalPositions = Tag(group: 0x0020, element: 0x0105)

    /// Patient Orientation (0020,0020)
    public static let patientOrientation = Tag(group: 0x0020, element: 0x0020)

    /// Image Laterality (0020,0062)
    public static let imageLaterality = Tag(group: 0x0020, element: 0x0062)

    // MARK: - Functional group macro sequences

    /// Frame VOI LUT Sequence (0028,9132)
    public static let frameVOILUTSequence = Tag(group: 0x0028, element: 0x9132)

    /// Pixel Value Transformation Sequence (0028,9145)
    public static let pixelValueTransformationSequence = Tag(group: 0x0028, element: 0x9145)

    /// Frame Anatomy Sequence (0020,9071)
    public static let frameAnatomySequence = Tag(group: 0x0020, element: 0x9071)

    /// Frame Laterality (0020,9072)
    public static let frameLaterality = Tag(group: 0x0020, element: 0x9072)

    /// CT Image Frame Type Sequence (0018,9329)
    public static let ctImageFrameTypeSequence = Tag(group: 0x0018, element: 0x9329)

    /// MR Image Frame Type Sequence (0018,9226)
    public static let mrImageFrameTypeSequence = Tag(group: 0x0018, element: 0x9226)

    /// PET Frame Type Sequence (0018,9751)
    public static let petFrameTypeSequence = Tag(group: 0x0018, element: 0x9751)

    /// XA/XRF Frame Characteristics Sequence (0018,9412)
    public static let xaXRFFrameCharacteristicsSequence = Tag(group: 0x0018, element: 0x9412)

    /// MR Echo Sequence (0018,9114)
    public static let mrEchoSequence = Tag(group: 0x0018, element: 0x9114)

    /// Effective Echo Time (0018,9082)
    public static let effectiveEchoTime = Tag(group: 0x0018, element: 0x9082)

    /// MR Timing and Related Parameters Sequence (0018,9112)
    public static let mrTimingAndRelatedParametersSequence = Tag(group: 0x0018, element: 0x9112)

    /// Cardiac Synchronization Sequence (0018,9118)
    public static let cardiacSynchronizationSequence = Tag(group: 0x0018, element: 0x9118)

    /// Nominal Cardiac Trigger Delay Time (0020,9153)
    public static let nominalCardiacTriggerDelayTime = Tag(group: 0x0020, element: 0x9153)

    /// Trigger Time (0018,1060)
    public static let triggerTime = Tag(group: 0x0018, element: 0x1060)

    /// Irradiation Event Identification Sequence (0018,9477)
    public static let irradiationEventIdentificationSequence = Tag(group: 0x0018, element: 0x9477)

    /// Irradiation Event UID (0008,3010)
    public static let irradiationEventUID = Tag(group: 0x0008, element: 0x3010)

    /// Plane Position (Volume) Sequence (0020,930E)
    public static let planePositionVolumeSequence = Tag(group: 0x0020, element: 0x930E)

    /// Plane Orientation (Volume) Sequence (0020,930F)
    public static let planeOrientationVolumeSequence = Tag(group: 0x0020, element: 0x930F)

    /// Image Position (Volume) (0020,9301)
    public static let imagePositionVolume = Tag(group: 0x0020, element: 0x9301)

    /// Image Orientation (Volume) (0020,9302)
    public static let imageOrientationVolume = Tag(group: 0x0020, element: 0x9302)

    /// Pixel Presentation (0008,9205)
    public static let pixelPresentation = Tag(group: 0x0008, element: 0x9205)

    /// Volumetric Properties (0008,9206)
    public static let volumetricProperties = Tag(group: 0x0008, element: 0x9206)

    /// Volume Based Calculation Technique (0008,9207)
    public static let volumeBasedCalculationTechnique = Tag(group: 0x0008, element: 0x9207)

    /// Complex Image Component (0008,9208)
    public static let complexImageComponent = Tag(group: 0x0008, element: 0x9208)

    /// Acquisition Contrast (0008,9209)
    public static let acquisitionContrast = Tag(group: 0x0008, element: 0x9209)

    /// Content Qualification (0018,9004)
    public static let contentQualification = Tag(group: 0x0018, element: 0x9004)

    // MARK: - Legacy Converted Enhanced (Sup 157)
    //
    // NEMA-verified: 2026a, checked 2026-09-24 — text-diffed against PS3.6 2026a Table 6-1.
    // Tag, name and keyword match, and none is retired. VR (SQ) and VM (1) are held in
    // DICOMDictionary's DataElementDictionary.txt, and they match too. Provenance: Sup 157.

    /// Unassigned Shared Converted Attributes Sequence (0020,9170)
    public static let unassignedSharedConvertedAttributesSequence = Tag(group: 0x0020, element: 0x9170)

    /// Unassigned Per-Frame Converted Attributes Sequence (0020,9171)
    public static let unassignedPerFrameConvertedAttributesSequence = Tag(group: 0x0020, element: 0x9171)

    /// Conversion Source Attributes Sequence (0020,9172)
    public static let conversionSourceAttributesSequence = Tag(group: 0x0020, element: 0x9172)

    // MARK: - Multi-frame Dimension (C.7.6.17)

    /// Dimension Organization Type (0020,9311)
    public static let dimensionOrganizationType = Tag(group: 0x0020, element: 0x9311)

    /// Dimension Description Label (0020,9421)
    public static let dimensionDescriptionLabel = Tag(group: 0x0020, element: 0x9421)

    /// Referenced Image Evidence Sequence (0008,9092)
    public static let referencedImageEvidenceSequence = Tag(group: 0x0008, element: 0x9092)

    /// Source Image Evidence Sequence (0008,9154)
    public static let sourceImageEvidenceSequence = Tag(group: 0x0008, element: 0x9154)

    // MARK: - Concatenation (C.7.6.16.2.2.4)

    /// Concatenation UID (0020,9161)
    public static let concatenationUID = Tag(group: 0x0020, element: 0x9161)

    /// In-concatenation Number (0020,9162)
    public static let inConcatenationNumber = Tag(group: 0x0020, element: 0x9162)

    /// In-concatenation Total Number (0020,9163)
    public static let inConcatenationTotalNumber = Tag(group: 0x0020, element: 0x9163)

    /// Concatenation Frame Offset Number (0020,9228)
    public static let concatenationFrameOffsetNumber = Tag(group: 0x0020, element: 0x9228)

    /// SOP Instance UID of Concatenation Source (0020,0242)
    public static let sopInstanceUIDOfConcatenationSource = Tag(group: 0x0020, element: 0x0242)

    // MARK: - NM Image Module vectors (C.8.4.8)

    /// Energy Window Vector (0054,0010)
    public static let energyWindowVector = Tag(group: 0x0054, element: 0x0010)
    /// Number of Energy Windows (0054,0011)
    public static let numberOfEnergyWindows = Tag(group: 0x0054, element: 0x0011)
    /// Detector Vector (0054,0020)
    public static let detectorVector = Tag(group: 0x0054, element: 0x0020)
    /// Number of Detectors (0054,0021)
    public static let numberOfDetectors = Tag(group: 0x0054, element: 0x0021)
    /// Detector Information Sequence (0054,0022)
    public static let detectorInformationSequence = Tag(group: 0x0054, element: 0x0022)
    /// Phase Vector (0054,0030)
    public static let phaseVector = Tag(group: 0x0054, element: 0x0030)
    /// Number of Phases (0054,0031)
    public static let numberOfPhases = Tag(group: 0x0054, element: 0x0031)
    /// Rotation Vector (0054,0050)
    public static let rotationVector = Tag(group: 0x0054, element: 0x0050)
    /// Number of Rotations (0054,0051)
    public static let numberOfRotations = Tag(group: 0x0054, element: 0x0051)
    /// R-R Interval Vector (0054,0060)
    public static let rrIntervalVector = Tag(group: 0x0054, element: 0x0060)
    /// Number of R-R Intervals (0054,0061)
    public static let numberOfRRIntervals = Tag(group: 0x0054, element: 0x0061)
    /// Time Slot Vector (0054,0070)
    public static let timeSlotVector = Tag(group: 0x0054, element: 0x0070)
    /// Number of Time Slots (0054,0071)
    public static let numberOfTimeSlots = Tag(group: 0x0054, element: 0x0071)
    /// Slice Vector (0054,0080)
    public static let sliceVector = Tag(group: 0x0054, element: 0x0080)
    /// Number of Slices (0054,0081)
    public static let numberOfSlices = Tag(group: 0x0054, element: 0x0081)
    /// Angular View Vector (0054,0090)
    public static let angularViewVector = Tag(group: 0x0054, element: 0x0090)
    /// Time Slice Vector (0054,0100)
    public static let timeSliceVector = Tag(group: 0x0054, element: 0x0100)
    /// Number of Time Slices (0054,0101)
    public static let numberOfTimeSlices = Tag(group: 0x0054, element: 0x0101)
    /// Image Index (0054,1330)
    public static let imageIndex = Tag(group: 0x0054, element: 0x1330)
    /// Frame Reference Time (0054,1300)
    public static let frameReferenceTime = Tag(group: 0x0054, element: 0x1300)
}
