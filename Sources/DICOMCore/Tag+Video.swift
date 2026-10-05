/// DICOM Tag Extensions - Video Information
///
/// Tags specific to DICOM Video storage and multi-frame cine modules.
/// Many video-related tags are already defined in Tag+ImageInformation.swift
/// (numberOfFrames, frameTime, frameDelay, cineRate, etc.).
/// This extension adds video-specific tags not covered elsewhere.
///
/// Reference: DICOM PS3.3 - Video IODs
/// Reference: PS3.3 C.7.6.5 - Cine Module
/// Reference: PS3.3 A.32.5 - Video Endoscopic Image IOD
/// Reference: PS3.3 A.32.6 - Video Microscopic Image IOD
/// Reference: PS3.3 A.32.7 - Video Photographic Image IOD
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {

    // MARK: - Cine Module (PS3.3 C.7.6.5)

    /// Recommended Display Frame Rate (0008,2144)
    /// VR: IS, VM: 1
    /// Recommended rate at which frames should be displayed, in frames/second
    public static let recommendedDisplayFrameRate = Tag(group: 0x0008, element: 0x2144)

    /// Start Trim (0008,2142)
    /// VR: IS, VM: 1
    /// The frame number of the first frame of interest in a multi-frame cine image
    public static let startTrim = Tag(group: 0x0008, element: 0x2142)

    /// Stop Trim (0008,2143)
    /// VR: IS, VM: 1
    /// The frame number of the last frame of interest in a multi-frame cine image
    public static let stopTrim = Tag(group: 0x0008, element: 0x2143)

    // MARK: - Stereoscopic Video (PS3.5 8.2.8 - 8.2.9)

    /// Stereo Pairs Present (0022,0028)
    /// VR: CS, VM: 1
    /// YES when the encapsulated video carries stereoscopic pairs. PS3.5 requires
    /// YES for the H.264 "For 3D Video" and Stereo High transfer syntaxes, and NO
    /// or absent for "For 2D Video" (Table 8-8, Section 8.2.9).
    public static let stereoPairsPresent = Tag(group: 0x0022, element: 0x0028)

    // MARK: - Acquisition Context Module

    /// Acquisition Duration (0018,9073)
    /// VR: FD, VM: 1
    /// Duration of acquisition in seconds
    public static let acquisitionDuration = Tag(group: 0x0018, element: 0x9073)

    // MARK: - SC Multi-frame Image Module

    /// Nominal Scanned Pixel Spacing (0018,2010)
    /// VR: DS, VM: 2
    /// Physical distance between adjacent pixels in mm
    public static let nominalScannedPixelSpacing = Tag(group: 0x0018, element: 0x2010)

    /// Acquisition Context Sequence (0040,0555)
    /// VR: SQ, VM: 1
    /// Type 2 in the Acquisition Context Module; may be present with zero items.
    ///
    /// Reference: PS3.3 C.7.6.14 - Acquisition Context Module
    public static let acquisitionContextSequence = Tag(group: 0x0040, element: 0x0555)
}
