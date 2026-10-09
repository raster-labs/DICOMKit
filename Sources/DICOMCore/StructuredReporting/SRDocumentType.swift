/// DICOM Structured Report Document Types
///
/// Defines the SOP Classes and document types for DICOM Structured Reporting.
///
/// Reference: PS3.4 Annex B - Storage SOP Class Definitions
/// Reference: PS3.3 Section A.35 - Structured Reporting Document IODs
///
/// NEMA-verified: 2026a, checked 2026-09-25 — text-diffed against PS3.6 2026a Table A-1 (the
/// 20 current SR Storage SOP Classes; the 4 retired "Trial" classes .88.1–.88.4 are recognised
/// by `isSRDocument` only) and PS3.3 2026a A.35.1–A.35.23 (each IOD's Value Type constraints,
/// which `allowedValueTypes` reproduces).

/// DICOM Structured Report document types
///
/// Each SR document type has specific constraints on the content and relationships
/// that are allowed within the document.
public enum SRDocumentType: Sendable, Equatable, Hashable {
    /// Basic Text SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.11
    /// Simple text-based reports with limited structure
    case basicTextSR
    
    /// Enhanced SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.22
    /// Adds support for all content item types
    case enhancedSR
    
    /// Comprehensive SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.33
    /// Full SR support including measurements and coordinates
    case comprehensiveSR
    
    /// Comprehensive 3D SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.34
    /// Adds 3D spatial coordinates support
    case comprehensive3DSR
    
    /// Extensible SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.35
    /// Most flexible SR document type
    case extensibleSR
    
    /// Key Object Selection Document
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.59
    /// For marking significant images/findings
    case keyObjectSelectionDocument
    
    /// Mammography CAD SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.50
    /// Computer-aided detection results for mammography
    case mammographyCADSR
    
    /// Chest CAD SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.65
    /// Computer-aided detection results for chest imaging
    case chestCADSR
    
    /// Colon CAD SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.69
    /// Computer-aided detection results for colon imaging
    case colonCADSR
    
    /// X-Ray Radiation Dose SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.67
    /// Radiation dose reporting for X-ray procedures
    case xRayRadiationDoseSR
    
    /// Enhanced X-Ray Radiation Dose SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.76
    /// Enhanced radiation dose reporting
    case enhancedXRayRadiationDoseSR
    
    /// Radiopharmaceutical Radiation Dose SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.68
    /// Radiation dose from radiopharmaceuticals
    case radiopharmaceuticalRadiationDoseSR
    
    /// Patient Radiation Dose SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.73
    /// Cumulative patient radiation dose
    case patientRadiationDoseSR
    
    /// Acquisition Context SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.71
    /// Acquisition context information
    case acquisitionContextSR
    
    /// Simplified Adult Echo SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.72
    /// Echocardiography reports
    case simplifiedAdultEchoSR
    
    /// Implantation Plan SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.70
    /// Implant planning information
    case implantationPlanSR
    
    /// Planned Imaging Agent Administration SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.74
    /// Planned contrast/agent administration
    case plannedImagingAgentAdministrationSR
    
    /// Procedure Log Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.40
    /// Time-stamped log of a procedure (PS3.3 A.35.7)
    case procedureLog

    /// Waveform Annotation SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.77
    /// Annotations of waveform segments by temporal coordinates (PS3.3 A.35.23)
    case waveformAnnotationSR

    /// Performed Imaging Agent Administration SR Storage
    /// SOP Class UID: 1.2.840.10008.5.1.4.1.1.88.75
    /// Performed contrast/agent administration
    case performedImagingAgentAdministrationSR
    
    // MARK: - SOP Class UIDs
    
    /// The SOP Class UID for this document type
    public var sopClassUID: String {
        switch self {
        case .basicTextSR:
            return "1.2.840.10008.5.1.4.1.1.88.11"
        case .enhancedSR:
            return "1.2.840.10008.5.1.4.1.1.88.22"
        case .comprehensiveSR:
            return "1.2.840.10008.5.1.4.1.1.88.33"
        case .comprehensive3DSR:
            return "1.2.840.10008.5.1.4.1.1.88.34"
        case .extensibleSR:
            return "1.2.840.10008.5.1.4.1.1.88.35"
        case .keyObjectSelectionDocument:
            return "1.2.840.10008.5.1.4.1.1.88.59"
        case .mammographyCADSR:
            return "1.2.840.10008.5.1.4.1.1.88.50"
        case .chestCADSR:
            return "1.2.840.10008.5.1.4.1.1.88.65"
        case .colonCADSR:
            return "1.2.840.10008.5.1.4.1.1.88.69"
        case .xRayRadiationDoseSR:
            return "1.2.840.10008.5.1.4.1.1.88.67"
        case .enhancedXRayRadiationDoseSR:
            return "1.2.840.10008.5.1.4.1.1.88.76"
        case .radiopharmaceuticalRadiationDoseSR:
            return "1.2.840.10008.5.1.4.1.1.88.68"
        case .patientRadiationDoseSR:
            return "1.2.840.10008.5.1.4.1.1.88.73"
        case .acquisitionContextSR:
            return "1.2.840.10008.5.1.4.1.1.88.71"
        case .simplifiedAdultEchoSR:
            return "1.2.840.10008.5.1.4.1.1.88.72"
        case .implantationPlanSR:
            return "1.2.840.10008.5.1.4.1.1.88.70"
        case .plannedImagingAgentAdministrationSR:
            return "1.2.840.10008.5.1.4.1.1.88.74"
        case .performedImagingAgentAdministrationSR:
            return "1.2.840.10008.5.1.4.1.1.88.75"
        case .procedureLog:
            return "1.2.840.10008.5.1.4.1.1.88.40"
        case .waveformAnnotationSR:
            return "1.2.840.10008.5.1.4.1.1.88.77"
        }
    }
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .basicTextSR:
            return "Basic Text SR"
        case .enhancedSR:
            return "Enhanced SR"
        case .comprehensiveSR:
            return "Comprehensive SR"
        case .comprehensive3DSR:
            return "Comprehensive 3D SR"
        case .extensibleSR:
            return "Extensible SR"
        case .keyObjectSelectionDocument:
            return "Key Object Selection Document"
        case .mammographyCADSR:
            return "Mammography CAD SR"
        case .chestCADSR:
            return "Chest CAD SR"
        case .colonCADSR:
            return "Colon CAD SR"
        case .xRayRadiationDoseSR:
            return "X-Ray Radiation Dose SR"
        case .enhancedXRayRadiationDoseSR:
            return "Enhanced X-Ray Radiation Dose SR"
        case .radiopharmaceuticalRadiationDoseSR:
            return "Radiopharmaceutical Radiation Dose SR"
        case .patientRadiationDoseSR:
            return "Patient Radiation Dose SR"
        case .acquisitionContextSR:
            return "Acquisition Context SR"
        case .simplifiedAdultEchoSR:
            return "Simplified Adult Echo SR"
        case .implantationPlanSR:
            return "Implantation Plan SR"
        case .plannedImagingAgentAdministrationSR:
            return "Planned Imaging Agent Administration SR"
        case .performedImagingAgentAdministrationSR:
            return "Performed Imaging Agent Administration SR"
        case .procedureLog:
            return "Procedure Log"
        case .waveformAnnotationSR:
            return "Waveform Annotation SR"
        }
    }
    
    // MARK: - Content Item Type Constraints
    
    /// The Value Types (0040,A040) an IOD permits in its Content Sequence.
    ///
    /// Each set is the Enumerated Values list of that IOD's Content Constraints in PS3.3 2026a
    /// A.35, generated from the DocBook text. Extensible SR permits every Value Type.
    public var allowedValueTypes: Set<ContentItemValueType> {
        switch self {
        case .basicTextSR:
            // PS3.3 A.35.1
            return [.text, .code, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .container]

        case .enhancedSR:
            // PS3.3 A.35.2
            return [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .tcoord, .container]

        case .comprehensiveSR:
            // PS3.3 A.35.3
            return [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .tcoord, .container]

        case .comprehensive3DSR:
            // PS3.3 A.35.13
            return [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .scoord3D, .tcoord, .container]

        case .extensibleSR:
            // PS3.3 A.35.15: any Value Type of Table C.17.3-7, including TABLE.
            return Set(ContentItemValueType.allCases)

        case .keyObjectSelectionDocument:
            // PS3.3 A.35.4
            return [.text, .code, .uidref, .pname, .composite, .image, .waveform, .container]

        case .mammographyCADSR:
            // PS3.3 A.35.5
            return [.text, .code, .num, .date, .time, .uidref, .pname, .composite, .image, .scoord, .container]

        case .chestCADSR:
            // PS3.3 A.35.6
            return [.text, .code, .num, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .tcoord, .container]

        case .colonCADSR:
            // PS3.3 A.35.10, Table A.35.10-2: the targets of the relationship rows. TCOORD is listed
            // only as a source (TCOORD SELECTED FROM) and no row admits it as a target, so it cannot
            // occur; WAVEFORM is one of that row's targets.
            return [.text, .code, .num, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .scoord3D, .container]

        case .xRayRadiationDoseSR:
            // PS3.3 A.35.8
            return [.text, .code, .num, .datetime, .uidref, .pname, .composite, .image, .container]

        case .enhancedXRayRadiationDoseSR:
            // PS3.3 A.35.22
            return [.text, .code, .num, .datetime, .uidref, .pname, .composite, .image, .scoord3D, .container, .table]

        case .radiopharmaceuticalRadiationDoseSR:
            // PS3.3 A.35.14
            return [.text, .code, .num, .datetime, .uidref, .pname, .container]

        case .patientRadiationDoseSR:
            // PS3.3 A.35.18
            return [.text, .code, .num, .datetime, .uidref, .pname, .composite, .image, .container]

        case .acquisitionContextSR:
            // PS3.3 A.35.16
            return [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .scoord3D, .container]

        case .simplifiedAdultEchoSR:
            // PS3.3 A.35.17
            return [.text, .code, .num, .datetime, .uidref, .pname, .image, .waveform, .scoord, .tcoord, .container]

        case .implantationPlanSR:
            // PS3.3 A.35.12
            return [.text, .code, .num, .date, .uidref, .pname, .composite, .image, .container]

        case .plannedImagingAgentAdministrationSR:
            // PS3.3 A.35.19
            return [.text, .code, .num, .datetime, .date, .uidref, .pname, .container]

        case .performedImagingAgentAdministrationSR:
            // PS3.3 A.35.20
            return [.text, .code, .num, .datetime, .date, .uidref, .pname, .composite, .image, .waveform, .container]

        case .procedureLog:
            // PS3.3 A.35.7
            return [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .container]

        case .waveformAnnotationSR:
            // PS3.3 A.35.23
            return [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .waveform, .tcoord, .container]
        }
    }
    
    /// Returns whether a given value type is allowed in this document type
    public func allows(_ valueType: ContentItemValueType) -> Bool {
        allowedValueTypes.contains(valueType)
    }
    
    // MARK: - Factory Method
    
    /// Creates an SRDocumentType from a SOP Class UID
    /// - Parameter sopClassUID: The SOP Class UID
    /// - Returns: The corresponding document type, or nil if not recognized
    public static func from(sopClassUID: String) -> SRDocumentType? {
        switch sopClassUID {
        case "1.2.840.10008.5.1.4.1.1.88.11": return .basicTextSR
        case "1.2.840.10008.5.1.4.1.1.88.22": return .enhancedSR
        case "1.2.840.10008.5.1.4.1.1.88.33": return .comprehensiveSR
        case "1.2.840.10008.5.1.4.1.1.88.34": return .comprehensive3DSR
        case "1.2.840.10008.5.1.4.1.1.88.35": return .extensibleSR
        case "1.2.840.10008.5.1.4.1.1.88.59": return .keyObjectSelectionDocument
        case "1.2.840.10008.5.1.4.1.1.88.50": return .mammographyCADSR
        case "1.2.840.10008.5.1.4.1.1.88.65": return .chestCADSR
        case "1.2.840.10008.5.1.4.1.1.88.69": return .colonCADSR
        case "1.2.840.10008.5.1.4.1.1.88.67": return .xRayRadiationDoseSR
        case "1.2.840.10008.5.1.4.1.1.88.76": return .enhancedXRayRadiationDoseSR
        case "1.2.840.10008.5.1.4.1.1.88.68": return .radiopharmaceuticalRadiationDoseSR
        case "1.2.840.10008.5.1.4.1.1.88.73": return .patientRadiationDoseSR
        case "1.2.840.10008.5.1.4.1.1.88.71": return .acquisitionContextSR
        case "1.2.840.10008.5.1.4.1.1.88.72": return .simplifiedAdultEchoSR
        case "1.2.840.10008.5.1.4.1.1.88.70": return .implantationPlanSR
        case "1.2.840.10008.5.1.4.1.1.88.74": return .plannedImagingAgentAdministrationSR
        case "1.2.840.10008.5.1.4.1.1.88.75": return .performedImagingAgentAdministrationSR
        case "1.2.840.10008.5.1.4.1.1.88.40": return .procedureLog
        case "1.2.840.10008.5.1.4.1.1.88.77": return .waveformAnnotationSR
        default: return nil
        }
    }
    
    /// The retired "Trial" SR Storage SOP Classes of PS3.6 Table A-1 (.88.1–.88.4: Text,
    /// Audio, Detail and Comprehensive SR Storage - Trial). Their IODs are no longer in PS3.3,
    /// so they have no `SRDocumentType`, but a file carrying one is still a Structured Report.
    public static let retiredTrialSOPClassUIDs: Set<String> = [
        "1.2.840.10008.5.1.4.1.1.88.1", "1.2.840.10008.5.1.4.1.1.88.2",
        "1.2.840.10008.5.1.4.1.1.88.3", "1.2.840.10008.5.1.4.1.1.88.4",
    ]

    /// Returns whether the given SOP Class UID is a Structured Report, including the
    /// retired Trial SOP Classes.
    public static func isSRDocument(sopClassUID: String) -> Bool {
        from(sopClassUID: sopClassUID) != nil || retiredTrialSOPClassUIDs.contains(sopClassUID)
    }
}

// MARK: - SOP Class UID Constants

extension SRDocumentType {
    /// All SR SOP Class UIDs
    public static var allSOPClassUIDs: [String] {
        [
            SRDocumentType.basicTextSR.sopClassUID,
            SRDocumentType.enhancedSR.sopClassUID,
            SRDocumentType.comprehensiveSR.sopClassUID,
            SRDocumentType.comprehensive3DSR.sopClassUID,
            SRDocumentType.extensibleSR.sopClassUID,
            SRDocumentType.keyObjectSelectionDocument.sopClassUID,
            SRDocumentType.mammographyCADSR.sopClassUID,
            SRDocumentType.chestCADSR.sopClassUID,
            SRDocumentType.colonCADSR.sopClassUID,
            SRDocumentType.xRayRadiationDoseSR.sopClassUID,
            SRDocumentType.enhancedXRayRadiationDoseSR.sopClassUID,
            SRDocumentType.radiopharmaceuticalRadiationDoseSR.sopClassUID,
            SRDocumentType.patientRadiationDoseSR.sopClassUID,
            SRDocumentType.acquisitionContextSR.sopClassUID,
            SRDocumentType.simplifiedAdultEchoSR.sopClassUID,
            SRDocumentType.implantationPlanSR.sopClassUID,
            SRDocumentType.plannedImagingAgentAdministrationSR.sopClassUID,
            SRDocumentType.performedImagingAgentAdministrationSR.sopClassUID,
            SRDocumentType.procedureLog.sopClassUID,
            SRDocumentType.waveformAnnotationSR.sopClassUID
        ]
    }
}

// MARK: - CustomStringConvertible

extension SRDocumentType: CustomStringConvertible {
    public var description: String {
        displayName
    }
}
