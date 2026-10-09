/// DICOM Tag Extensions - Secondary Capture Information
///
/// Tags specific to DICOM Secondary Capture Image IODs.
/// Secondary Capture images are created by capturing images from non-DICOM
/// sources such as cameras, scanners, or screen captures.
///
/// Reference: PS3.3 C.8.6.1 - SC Equipment Module
/// Reference: PS3.3 C.8.6.2 - SC Image Module
/// Reference: PS3.3 C.8.6.3 - SC Multi-Frame Image Module
/// Reference: PS3.3 A.8 - Secondary Capture Image IOD
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {

    // MARK: - SC Equipment Module (PS3.3 C.8.6.1)

    /// Conversion Type (0008,0064)
    /// VR: CS, VM: 1
    /// Describes the kind of conversion that was performed on the image.
    /// Defined terms: DV, DI, DF, WSD, SD, SI, SYN
    public static let conversionType = Tag(group: 0x0008, element: 0x0064)

    // MARK: - SC Image Module (PS3.3 C.8.6.2)

    /// Date of Secondary Capture (0018,1012)
    /// VR: DA, VM: 1
    /// The date the Secondary Capture image was created
    public static let dateOfSecondaryCapture = Tag(group: 0x0018, element: 0x1012)

    /// Time of Secondary Capture (0018,1014)
    /// VR: TM, VM: 1
    /// The time the Secondary Capture image was created
    public static let timeOfSecondaryCapture = Tag(group: 0x0018, element: 0x1014)

    // MARK: - SC Multi-Frame Image Module (PS3.3 C.8.6.3)

    // Note: Frame Increment Pointer (0028,0009) is defined in Tag+ImageInformation.swift
    // Note: Frame Label Vector (0018,2002) is defined in Tag+ImageInformation.swift
    // Note: Nominal Scanned Pixel Spacing (0018,2010) is defined in Tag+Video.swift

    /// Page Number Vector (0018,2001)
    /// VR: IS, VM: 1-n
    /// An array of page numbers that identifies the pages of a multi-page document
    public static let pageNumberVector = Tag(group: 0x0018, element: 0x2001)

    /// Frame Primary Angle Vector (0018,2003)
    /// VR: DS, VM: 1-n
    /// An array of primary angle values for each frame
    public static let framePrimaryAngleVector = Tag(group: 0x0018, element: 0x2003)

    /// Frame Secondary Angle Vector (0018,2004)
    /// VR: DS, VM: 1-n
    /// An array of secondary angle values for each frame
    public static let frameSecondaryAngleVector = Tag(group: 0x0018, element: 0x2004)
}
