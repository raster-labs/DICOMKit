/// DICOM Tag Extensions - Waveform Information
///
/// Tags specific to DICOM Waveform storage and data
/// Reference: DICOM PS3.6 - Registry of DICOM Data Elements (Waveform group 0x003A)
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - Waveform Identification Module

    /// Instance Number (0020,0013)
    /// Already defined in Tag+ImageInformation.swift

    /// Content Date (0008,0023)
    /// Already defined in Tag+ImageInformation.swift

    /// Content Time (0008,0033)
    /// Already defined in Tag+ImageInformation.swift

    /// Acquisition DateTime (0008,002A)
    /// Already defined in Tag+ImageInformation.swift

    // MARK: - Waveform Module

    /// Waveform Sequence (5400,0100)
    /// VR: SQ, VM: 1
    public static let waveformSequence = Tag(group: 0x5400, element: 0x0100)

    /// Multiplex Group Time Offset (0018,1068)
    /// VR: DS, VM: 1
    public static let multiplexGroupTimeOffset = Tag(group: 0x0018, element: 0x1068)

    /// Trigger Time Offset (0018,1069)
    /// VR: DS, VM: 1
    public static let triggerTimeOffset = Tag(group: 0x0018, element: 0x1069)

    /// Synchronization Trigger (0018,106A)
    /// VR: CS, VM: 1
    public static let synchronizationTrigger = Tag(group: 0x0018, element: 0x106A)

    /// Synchronization Channel (0018,106C)
    /// VR: US, VM: 2
    public static let synchronizationChannel = Tag(group: 0x0018, element: 0x106C)

    /// Trigger Sample Position (0018,106E)
    /// VR: UL, VM: 1
    public static let triggerSamplePosition = Tag(group: 0x0018, element: 0x106E)

    /// Waveform Originality (003A,0004)
    /// VR: CS, VM: 1
    public static let waveformOriginality = Tag(group: 0x003A, element: 0x0004)

    /// Number of Waveform Channels (003A,0005)
    /// VR: US, VM: 1
    public static let numberOfWaveformChannels = Tag(group: 0x003A, element: 0x0005)

    /// Number of Waveform Samples (003A,0010)
    /// VR: UL, VM: 1
    public static let numberOfWaveformSamples = Tag(group: 0x003A, element: 0x0010)

    /// Sampling Frequency (003A,001A)
    /// VR: DS, VM: 1
    public static let samplingFrequency = Tag(group: 0x003A, element: 0x001A)

    /// Multiplex Group Label (003A,0020)
    /// VR: SH, VM: 1
    public static let multiplexGroupLabel = Tag(group: 0x003A, element: 0x0020)

    /// Channel Definition Sequence (003A,0200)
    /// VR: SQ, VM: 1
    public static let channelDefinitionSequence = Tag(group: 0x003A, element: 0x0200)

    /// Waveform Channel Number (003A,0202)
    /// VR: IS, VM: 1
    public static let waveformChannelNumber = Tag(group: 0x003A, element: 0x0202)

    /// Channel Label (003A,0203)
    /// VR: SH, VM: 1
    public static let channelLabel = Tag(group: 0x003A, element: 0x0203)

    /// Channel Status (003A,0205)
    /// VR: CS, VM: 1-n
    public static let channelStatus = Tag(group: 0x003A, element: 0x0205)

    /// Channel Source Sequence (003A,0208)
    /// VR: SQ, VM: 1
    public static let channelSourceSequence = Tag(group: 0x003A, element: 0x0208)

    /// Channel Source Modifiers Sequence (003A,0209)
    /// VR: SQ, VM: 1
    public static let channelSourceModifiersSequence = Tag(group: 0x003A, element: 0x0209)

    /// Source Waveform Sequence (003A,020A)
    /// VR: SQ, VM: 1
    public static let sourceWaveformSequence = Tag(group: 0x003A, element: 0x020A)

    /// Channel Derivation Description (003A,020C)
    /// VR: LO, VM: 1
    public static let channelDerivationDescription = Tag(group: 0x003A, element: 0x020C)

    /// Channel Sensitivity (003A,0210)
    /// VR: DS, VM: 1
    public static let channelSensitivity = Tag(group: 0x003A, element: 0x0210)

    /// Channel Sensitivity Units Sequence (003A,0211)
    /// VR: SQ, VM: 1
    public static let channelSensitivityUnitsSequence = Tag(group: 0x003A, element: 0x0211)

    /// Channel Sensitivity Correction Factor (003A,0212)
    /// VR: DS, VM: 1
    public static let channelSensitivityCorrectionFactor = Tag(group: 0x003A, element: 0x0212)

    /// Channel Baseline (003A,0213)
    /// VR: DS, VM: 1
    public static let channelBaseline = Tag(group: 0x003A, element: 0x0213)

    /// Channel Time Skew (003A,0214)
    /// VR: DS, VM: 1
    public static let channelTimeSkew = Tag(group: 0x003A, element: 0x0214)

    /// Channel Sample Skew (003A,0215)
    /// VR: DS, VM: 1
    public static let channelSampleSkew = Tag(group: 0x003A, element: 0x0215)

    /// Channel Offset (003A,0218)
    /// VR: DS, VM: 1
    public static let channelOffset = Tag(group: 0x003A, element: 0x0218)

    /// Waveform Bits Stored (003A,021A)
    /// VR: US, VM: 1
    public static let waveformBitsStored = Tag(group: 0x003A, element: 0x021A)

    /// Waveform Sample Interpretation (5400,1006)
    /// VR: CS, VM: 1
    /// Values: SB (signed 8-bit), UB (unsigned 8-bit), SS (signed 16-bit),
    ///         US (unsigned 16-bit), MB (8-bit mu-law), AB (8-bit A-law)
    public static let waveformSampleInterpretation = Tag(group: 0x5400, element: 0x1006)

    /// Waveform Bits Allocated (5400,1004)
    /// VR: US, VM: 1
    /// Number of bits allocated for each waveform sample (8, 16, 32, or 64)
    public static let waveformBitsAllocated = Tag(group: 0x5400, element: 0x1004)

    /// Filter Low Frequency (003A,0220)
    /// VR: DS, VM: 1
    public static let filterLowFrequency = Tag(group: 0x003A, element: 0x0220)

    /// Filter High Frequency (003A,0221)
    /// VR: DS, VM: 1
    public static let filterHighFrequency = Tag(group: 0x003A, element: 0x0221)

    /// Notch Filter Frequency (003A,0222)
    /// VR: DS, VM: 1
    public static let notchFilterFrequency = Tag(group: 0x003A, element: 0x0222)

    /// Notch Filter Bandwidth (003A,0223)
    /// VR: DS, VM: 1
    public static let notchFilterBandwidth = Tag(group: 0x003A, element: 0x0223)

    /// Waveform Data Display Scale (003A,0230)
    /// VR: FL, VM: 1
    public static let waveformDataDisplayScale = Tag(group: 0x003A, element: 0x0230)

    // MARK: - Waveform Presentation Module (group 0x003A)

    /// Waveform Display Background CIELab Value (003A,0231)
    /// VR: US, VM: 3
    public static let waveformDisplayBackgroundCIELabValue = Tag(group: 0x003A, element: 0x0231)

    /// Waveform Presentation Group Sequence (003A,0240)
    /// VR: SQ, VM: 1
    public static let waveformPresentationGroupSequence = Tag(group: 0x003A, element: 0x0240)

    /// Presentation Group Number (003A,0241)
    /// VR: US, VM: 1
    public static let presentationGroupNumber = Tag(group: 0x003A, element: 0x0241)

    /// Channel Display Sequence (003A,0242)
    /// VR: SQ, VM: 1
    public static let channelDisplaySequence = Tag(group: 0x003A, element: 0x0242)

    /// Channel Recommended Display CIELab Value (003A,0244)
    /// VR: US, VM: 3
    public static let channelRecommendedDisplayCIELabValue = Tag(group: 0x003A, element: 0x0244)

    /// Channel Position (003A,0245)
    /// VR: FL, VM: 1
    public static let channelPosition = Tag(group: 0x003A, element: 0x0245)

    /// Display Shading Flag (003A,0246)
    /// VR: CS, VM: 1
    public static let displayShadingFlag = Tag(group: 0x003A, element: 0x0246)

    /// Fractional Channel Display Scale (003A,0247)
    /// VR: FL, VM: 1
    public static let fractionalChannelDisplayScale = Tag(group: 0x003A, element: 0x0247)

    /// Absolute Channel Display Scale (003A,0248)
    /// VR: FL, VM: 1
    public static let absoluteChannelDisplayScale = Tag(group: 0x003A, element: 0x0248)

    /// Waveform Data (5400,1010)
    /// VR: OB or OW, VM: 1
    public static let waveformData = Tag(group: 0x5400, element: 0x1010)

    // MARK: - Waveform Annotation Module

    /// Waveform Annotation Sequence (0040,B020)
    /// VR: SQ, VM: 1
    public static let waveformAnnotationSequence = Tag(group: 0x0040, element: 0xB020)

    /// Text Value (0040,A160) — SR content item text. Defined as
    /// `Tag.textValue` in Tag+StructuredReporting.swift.
    ///
    /// The Waveform Annotation Module (PS3.3 C.10.9) carries its text in
    /// Unformatted Text Value (0070,0006) — see `Tag.unformattedTextValue` in
    /// Tag+PresentationState.swift. (0040,A160) is not part of that module.

    /// Annotation Group Number (0040,A180)
    /// VR: US, VM: 1
    public static let annotationGroupNumber = Tag(group: 0x0040, element: 0xA180)

    /// Temporal Range Type (0040,A130)
    /// VR: CS, VM: 1
    public static let temporalRangeType = Tag(group: 0x0040, element: 0xA130)

    /// Referenced Sample Positions (0040,A132)
    /// VR: UL, VM: 1-n
    public static let referencedSamplePositions = Tag(group: 0x0040, element: 0xA132)

    /// Referenced Time Offsets (0040,A138)
    /// VR: DS, VM: 1-n
    public static let referencedTimeOffsets = Tag(group: 0x0040, element: 0xA138)

    /// Referenced DateTime (0040,A13A)
    /// VR: DT, VM: 1-n
    public static let referencedDateTime = Tag(group: 0x0040, element: 0xA13A)

    // MARK: - Synchronization Module

    /// Synchronization Frame of Reference UID (0020,0200)
    /// Already defined in Tag+SeriesInformation.swift

    /// Acquisition Time Synchronized (0018,1800)
    /// VR: CS, VM: 1
    public static let acquisitionTimeSynchronized = Tag(group: 0x0018, element: 0x1800)

    /// Time Source (0018,1801)
    /// VR: SH, VM: 1
    public static let timeSource = Tag(group: 0x0018, element: 0x1801)

    /// Time Distribution Protocol (0018,1802)
    /// VR: CS, VM: 1
    public static let timeDistributionProtocol = Tag(group: 0x0018, element: 0x1802)

    /// NTP Source Address (0018,1803)
    /// VR: LO, VM: 1
    public static let ntpSourceAddress = Tag(group: 0x0018, element: 0x1803)
}
