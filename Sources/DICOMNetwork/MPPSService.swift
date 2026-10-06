import Foundation
import DICOMCore
import DICOMDictionary
// NEMA-verified: 2026a, checked 2026-10-06 — option rules lifted from dicom-mpps (D263): --status words vs PS3.3 2026a Table C.4-14 (0040,0252) Enumerated Values (IN PROGRESS / DISCONTINUED / COMPLETED, 3 of 3), Patient's Sex (0010,0040) vs Table C.2-3 (M / F / O, 3 of 3), birth date vs PS3.5 Table 6.2-1 DA (YYYYMMDD); N-CREATE/N-SET attribute set text-diffed against PS3.4 2026a Table F.7.2-1 (all 23 top-level Type 1/2 attributes emitted; Modality 1/1 required non-empty, D87; (0040,0281) created zero-length at N-CREATE per the F.7.2.1.1 note, D86; Scripts/diff_network.py); PPS status terms per PS3.3 C.4.14; command sets per PS3.7 Tables 10.3-5, 10.3-9; N-CREATE / N-SET failures thrown as mppsOperationFailed worded per Table F.7.2-2 / PS3.7 Annex C (D83); CID 9300 / 9301 / Table D-1 names per PS3.16 2026a (D84)

/// SOP Class UID for Modality Performed Procedure Step
/// Reference: PS3.4 Annex F - Modality Performed Procedure Step SOP Class
public let modalityPerformedProcedureStepSOPClassUID = "1.2.840.10008.3.1.2.3.3"

/// MPPS Status
public enum MPPSStatus: String, Sendable {
    case inProgress = "IN PROGRESS"
    case completed = "COMPLETED"
    case discontinued = "DISCONTINUED"
}

/// Configuration for the MPPS Service
public struct MPPSConfiguration: Sendable, Hashable {
    /// The local Application Entity title (calling AE)
    public let callingAETitle: AETitle
    
    /// The remote Application Entity title (called AE)
    public let calledAETitle: AETitle
    
    /// Connection timeout in seconds
    public let timeout: TimeInterval
    
    /// Maximum PDU size to propose
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID for this DICOM implementation
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// User identity for authentication (optional)
    public let userIdentity: UserIdentity?

    /// Include the Scheduled Step Attributes Sequence (0040,0270) in N-SET.
    ///
    /// PS3.4 Table F.7.2-1 marks that sequence *Not allowed* in N-SET; strict SCPs
    /// (dcm4chee, DCMTK) may answer 0x0107. Earlier DICOMKit builds always sent it
    /// because one Orthanc deployment appeared to require it. Off by default; turn
    /// on only for an SCP that has been shown to need it.
    public let includeScheduledStepAttributesInNSet: Bool

    /// Forces the Specific Character Set (0008,0005) of the N-CREATE / N-SET data set.
    ///
    /// When nil (the default) the narrowest repertoire that represents every text
    /// value is chosen: none for pure ASCII, "ISO_IR 100" for Latin-1, "ISO_IR 192"
    /// otherwise (PS3.5 6.1.2).
    public let specificCharacterSet: String?
    
    /// Default Implementation Class UID for DICOMKit
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID
    
    /// Default Implementation Version Name for DICOMKit
    public static let defaultImplementationVersionName = "DICOMKIT_001"
    
    /// Creates an MPPS configuration
    ///
    /// - Parameters:
    ///   - callingAETitle: The local AE title
    ///   - calledAETitle: The remote AE title
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - userIdentity: User identity for authentication (optional)
    ///   - includeScheduledStepAttributesInNSet: send (0040,0270) in N-SET (non-conformant; off)
    ///   - specificCharacterSet: forced (0008,0005); nil chooses automatically
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        userIdentity: UserIdentity? = nil,
        includeScheduledStepAttributesInNSet: Bool = false,
        specificCharacterSet: String? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.userIdentity = userIdentity
        self.includeScheduledStepAttributesInNSet = includeScheduledStepAttributesInNSet
        self.specificCharacterSet = specificCharacterSet
    }
}

/// The outcome of an MPPS N-CREATE or N-SET.
///
/// A warning status (0x0107 Attribute List Error, 0x0116 Attribute Value Out of
/// Range, 0xB000–0xBFFF) means the SCP performed the operation, possibly after
/// coercing or dropping attributes (PS3.7 10.1.5.1.6 / 10.1.3.1.6, Annex C); it is
/// reported here rather than thrown.
public struct MPPSOperationResult: Sendable, Hashable {
    /// The MPPS SOP Instance UID — for N-CREATE, the one the SCP returned in
    /// Affected SOP Instance UID when it differs from the requested one
    /// (PS3.7 10.1.5.1.4).
    public let sopInstanceUID: String
    /// The DIMSE status of the response (success or warning)
    public let status: DIMSEStatus
    /// The requested MPPS SOP Instance UID (N-CREATE only differs from `sopInstanceUID`
    /// when the SCP assigned its own)
    public let requestedSOPInstanceUID: String

    public init(sopInstanceUID: String, status: DIMSEStatus, requestedSOPInstanceUID: String? = nil) {
        self.sopInstanceUID = sopInstanceUID
        self.status = status
        self.requestedSOPInstanceUID = requestedSOPInstanceUID ?? sopInstanceUID
    }

    /// The warning status when the SCP completed the operation with a warning; nil on plain success.
    public var warning: DIMSEStatus? { status.isWarning ? status : nil }

    /// Whether the SCP assigned a different SOP Instance UID than the one requested.
    public var sopInstanceUIDWasReassigned: Bool { sopInstanceUID != requestedSOPInstanceUID }
}

/// A coded entry (Code Value / Coding Scheme Designator / Code Meaning) for the
/// MPPS code sequences: Procedure Code, Performed Protocol Code, Scheduled Protocol Code.
public struct MPPSCodedEntry: Sendable, Hashable {
    /// Code Value (0008,0100)
    public let codeValue: String
    /// Coding Scheme Designator (0008,0102)
    public let codingSchemeDesignator: String
    /// Code Meaning (0008,0104)
    public let codeMeaning: String

    public init(codeValue: String, codingSchemeDesignator: String, codeMeaning: String) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
    }

    /// Parses the `CODE|SCHEME|MEANING` text form used by the `dicom-mpps` CLI and
    /// the CLI Workshop's matching field, e.g. `110513|DCM|Discontinued for unspecified reason`
    /// (PS3.16 2026a CID 9301 / Table D-1).
    ///
    /// Shared so the two front-ends cannot disagree on what they accept or on the
    /// message they show when they reject it.
    ///
    /// - Parameter raw: The three-part text, `|`-separated. Surrounding whitespace
    ///   around each part is trimmed; the meaning may itself contain `|`.
    /// - Returns: The parsed entry, or nil when `raw` is not in that form.
    public static func parse(_ raw: String) -> MPPSCodedEntry? {
        let parts = raw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return MPPSCodedEntry(codeValue: parts[0],
                              codingSchemeDesignator: parts[1],
                              codeMeaning: parts[2])
    }

    /// The message shown when ``parse(_:)`` rejects a value, naming the option it came from.
    public static func parseErrorMessage(option: String) -> String {
        "\(option) must be CODE|SCHEME|MEANING, e.g. \"110513|DCM|Discontinued for unspecified reason\""
    }
}

/// A SOP Class / SOP Instance pair referenced from an MPPS Performed Series item.
public struct MPPSReferencedInstance: Sendable, Hashable {
    /// Referenced SOP Class UID (0008,1150) — the instance's real SOP Class, e.g.
    /// CT Image Storage; never a placeholder.
    public let sopClassUID: String
    /// Referenced SOP Instance UID (0008,1155)
    public let sopInstanceUID: String

    public init(sopClassUID: String, sopInstanceUID: String) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
    }
}

/// One item of the Performed Series Sequence (0040,0340) — PS3.4 Table F.7.2-1,
/// Image Acquisition Results module.
public struct MPPSPerformedSeries: Sendable, Hashable {
    /// Series Instance UID (0020,000E) — Type 1
    public let seriesInstanceUID: String
    /// Protocol Name (0018,1030) — Type 1. Must be non-empty.
    public let protocolName: String
    /// Series Description (0008,103E) — Type 2
    public let seriesDescription: String?
    /// Performing Physician's Name (0008,1050) — Type 2
    public let performingPhysicianName: String?
    /// Operators' Name (0008,1070) — Type 2
    public let operatorsName: String?
    /// Retrieve AE Title (0008,0054) — Type 2
    public let retrieveAETitle: String?
    /// Referenced Image Sequence (0008,1140) — Type 2
    public let referencedImages: [MPPSReferencedInstance]
    /// Referenced Non-Image Composite SOP Instance Sequence (0040,0220) — Type 2
    public let referencedNonImageInstances: [MPPSReferencedInstance]

    public init(
        seriesInstanceUID: String,
        protocolName: String,
        seriesDescription: String? = nil,
        performingPhysicianName: String? = nil,
        operatorsName: String? = nil,
        retrieveAETitle: String? = nil,
        referencedImages: [MPPSReferencedInstance] = [],
        referencedNonImageInstances: [MPPSReferencedInstance] = []
    ) {
        self.seriesInstanceUID = seriesInstanceUID
        self.protocolName = protocolName
        self.seriesDescription = seriesDescription
        self.performingPhysicianName = performingPhysicianName
        self.operatorsName = operatorsName
        self.retrieveAETitle = retrieveAETitle
        self.referencedImages = referencedImages
        self.referencedNonImageInstances = referencedNonImageInstances
    }
}

/// MPPS procedure step data
public struct MPPSProcedureStep: Sendable {
    /// SOP Instance UID for the MPPS instance
    public let sopInstanceUID: String
    
    /// Performed Procedure Step Status
    public let status: MPPSStatus
    
    /// Study Instance UID
    public let studyInstanceUID: String?
    
    /// Performed Procedure Step Start Date/Time
    public let startDateTime: Date?
    
    /// Performed Procedure Step End Date/Time (for completed/discontinued)
    public let endDateTime: Date?
    
    /// Referenced Image SOPs (for completed procedures), grouped into Performed
    /// Series items by `seriesUID`. Every reference is emitted with
    /// `referencedSOPClassUID`; prefer `performedSeries`, which carries the real
    /// SOP Class per instance and the Type 1 Protocol Name.
    public let referencedSOPs: [(studyUID: String, seriesUID: String, sopInstanceUID: String)]

    /// SOP Class UID applied to every `referencedSOPs` entry. When nil the legacy
    /// Secondary Capture placeholder is used — non-conformant for anything that is
    /// not an SC image; pass the real class or use `performedSeries`.
    public let referencedSOPClassUID: String?

    /// Protocol Name (0018,1030) applied to series built from `referencedSOPs`.
    /// Type 1 inside every Performed Series item; "UNSPECIFIED" when nil.
    public let protocolName: String?

    /// Performed Series Sequence (0040,0340) items. Takes precedence over
    /// `referencedSOPs` when non-empty.
    public let performedSeries: [MPPSPerformedSeries]
    
    /// Additional attributes, written verbatim into the N-CREATE / N-SET data set
    /// after the modelled ones (VR from the data dictionary, UN if unknown).
    public let attributes: [Tag: Data]

    // MARK: - N-CREATE specific attributes (PS3.4 Table F.7.2-1)

    /// Patient's Name (0010,0010) — Type 2 (PS3.4 Table F.7.2-1, N-CREATE
    /// column 2/2); sent empty when nil.
    public let patientName: String?

    /// Patient ID (0010,0020) — Type 2 (PS3.4 Table F.7.2-1, N-CREATE column
    /// 2/2); sent empty when nil.
    public let patientID: String?

    /// Modality (0008,0060) — Type 1
    public let modality: String?

    /// Performed Procedure Step ID (0040,0253) — Type 1
    public let procedureStepID: String?

    /// Performed Procedure Step Description (0040,0254) — Type 2
    public let procedureStepDescription: String?

    /// Performed Station AE Title (0040,0241) — Type 1
    public let performedStationAETitle: String?

    /// Performing Physician's Name (0008,1050) — Type 2
    public let performingPhysicianName: String?

    /// Performed Station Name (0040,0242) — Type 2
    public let performedStationName: String?

    /// Accession Number (0008,0050) — Type 2
    public let accessionNumber: String?

    /// Scheduled Procedure Step ID for the Scheduled Step Attributes Sequence (0040,0009)
    public let scheduledProcedureStepID: String?

    // MARK: - Remaining PS3.4 Table F.7.2-1 Type 2 attributes

    /// Patient's Birth Date (0010,0030) — Type 2, YYYYMMDD
    public let patientBirthDate: String?
    /// Patient's Sex (0010,0040) — Type 2
    public let patientSex: String?
    /// Study ID (0020,0010) — Type 2
    public let studyID: String?
    /// Performed Location (0040,0243) — Type 2
    public let performedLocation: String?
    /// Performed Procedure Type Description (0040,0255) — Type 2
    public let performedProcedureTypeDescription: String?
    /// Procedure Code Sequence (0008,1032) — Type 2
    public let procedureCode: MPPSCodedEntry?
    /// Performed Protocol Code Sequence (0040,0260) — Type 2
    public let performedProtocolCodes: [MPPSCodedEntry]
    /// Scheduled Step Attributes › Requested Procedure ID (0040,1001) — Type 2
    public let requestedProcedureID: String?
    /// Scheduled Step Attributes › Requested Procedure Description (0032,1060) — Type 2
    public let requestedProcedureDescription: String?
    /// Scheduled Step Attributes › Scheduled Procedure Step Description (0040,0007) — Type 2
    public let scheduledProcedureStepDescription: String?
    /// Scheduled Step Attributes › Scheduled Protocol Code Sequence (0040,0008) — Type 2
    public let scheduledProtocolCodes: [MPPSCodedEntry]
    /// Scheduled Step Attributes › Referenced Study Sequence (0008,1110) — Type 2.
    /// The SOP Instance UID the worklist item carried; the class is Detached Study
    /// Management (1.2.840.10008.3.1.2.3.1) as MWL SCPs conventionally emit.
    public let referencedStudySOPInstanceUID: String?

    /// Performed Procedure Step Discontinuation Reason Code Sequence (0040,0281) —
    /// Type 3 in N-SET, meaningful only when `status` is `.discontinued`. The
    /// Baseline CID 9300 "Procedure Discontinuation Reason" (PS3.3 Table C.4-14),
    /// which includes CID 9301 "Modality PPS Discontinuation Reason", e.g.
    /// 110513 "Discontinued for unspecified reason", 110500 "Doctor canceled
    /// procedure" (PS3.16 2026a Table D-1, scheme DCM).
    public let discontinuationReason: MPPSCodedEntry?

    /// Forces the Specific Character Set (0008,0005) of the data set; nil (the
    /// default) chooses the narrowest set that represents every text value.
    public let specificCharacterSet: String?
    
    public init(
        sopInstanceUID: String,
        status: MPPSStatus,
        studyInstanceUID: String? = nil,
        startDateTime: Date? = nil,
        endDateTime: Date? = nil,
        referencedSOPs: [(studyUID: String, seriesUID: String, sopInstanceUID: String)] = [],
        referencedSOPClassUID: String? = nil,
        protocolName: String? = nil,
        performedSeries: [MPPSPerformedSeries] = [],
        attributes: [Tag: Data] = [:],
        patientName: String? = nil,
        patientID: String? = nil,
        modality: String? = nil,
        procedureStepID: String? = nil,
        procedureStepDescription: String? = nil,
        performedStationAETitle: String? = nil,
        performingPhysicianName: String? = nil,
        performedStationName: String? = nil,
        accessionNumber: String? = nil,
        scheduledProcedureStepID: String? = nil,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        studyID: String? = nil,
        performedLocation: String? = nil,
        performedProcedureTypeDescription: String? = nil,
        procedureCode: MPPSCodedEntry? = nil,
        performedProtocolCodes: [MPPSCodedEntry] = [],
        requestedProcedureID: String? = nil,
        requestedProcedureDescription: String? = nil,
        scheduledProcedureStepDescription: String? = nil,
        scheduledProtocolCodes: [MPPSCodedEntry] = [],
        referencedStudySOPInstanceUID: String? = nil,
        discontinuationReason: MPPSCodedEntry? = nil,
        specificCharacterSet: String? = nil
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.status = status
        self.studyInstanceUID = studyInstanceUID
        self.startDateTime = startDateTime
        self.endDateTime = endDateTime
        self.referencedSOPs = referencedSOPs
        self.referencedSOPClassUID = referencedSOPClassUID
        self.protocolName = protocolName
        self.performedSeries = performedSeries
        self.attributes = attributes
        self.patientName = patientName
        self.patientID = patientID
        self.modality = modality
        self.procedureStepID = procedureStepID
        self.procedureStepDescription = procedureStepDescription
        self.performedStationAETitle = performedStationAETitle
        self.performingPhysicianName = performingPhysicianName
        self.performedStationName = performedStationName
        self.accessionNumber = accessionNumber
        self.scheduledProcedureStepID = scheduledProcedureStepID
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.studyID = studyID
        self.performedLocation = performedLocation
        self.performedProcedureTypeDescription = performedProcedureTypeDescription
        self.procedureCode = procedureCode
        self.performedProtocolCodes = performedProtocolCodes
        self.requestedProcedureID = requestedProcedureID
        self.requestedProcedureDescription = requestedProcedureDescription
        self.scheduledProcedureStepDescription = scheduledProcedureStepDescription
        self.scheduledProtocolCodes = scheduledProtocolCodes
        self.referencedStudySOPInstanceUID = referencedStudySOPInstanceUID
        self.discontinuationReason = discontinuationReason
        self.specificCharacterSet = specificCharacterSet
    }

    /// Every text-VR (PN, LO, SH, ST, LT, UT, UC) value the data set carries,
    /// including nested sequence items — the input to the character set choice.
    var textValues: [String] {
        var values: [String] = []
        func add(_ v: String?) { if let v, !v.isEmpty { values.append(v) } }
        func add(_ code: MPPSCodedEntry?) {
            guard let code else { return }
            add(code.codeValue); add(code.codingSchemeDesignator); add(code.codeMeaning)
        }
        add(patientName); add(patientID); add(procedureStepID); add(procedureStepDescription)
        add(performedStationName); add(performedLocation); add(performedProcedureTypeDescription)
        add(accessionNumber); add(scheduledProcedureStepID); add(studyID)
        add(requestedProcedureID); add(requestedProcedureDescription); add(scheduledProcedureStepDescription)
        add(protocolName); add(performingPhysicianName)
        add(procedureCode); add(discontinuationReason)
        performedProtocolCodes.forEach { add($0) }
        scheduledProtocolCodes.forEach { add($0) }
        for series in effectivePerformedSeries {
            add(series.protocolName); add(series.seriesDescription)
            add(series.performingPhysicianName); add(series.operatorsName)
        }
        return values
    }

    /// Secondary Capture Image Storage — the placeholder used for `referencedSOPs`
    /// entries when `referencedSOPClassUID` is nil.
    public static let legacyReferencedSOPClassUID = "1.2.840.10008.5.1.4.1.1.7"

    /// Detached Study Management SOP Class — the class MWL SCPs put in Referenced
    /// Study Sequence items. Retired in PS3.6 Table A-1; still carried here
    /// because the worklist supplies it (see `buildScheduledStepAttributesSequence`).
    public static let detachedStudyManagementSOPClassUID = "1.2.840.10008.3.1.2.3.1"

    /// The Performed Series items to emit: `performedSeries` when given, otherwise
    /// `referencedSOPs` grouped by series with the shared class / protocol name.
    var effectivePerformedSeries: [MPPSPerformedSeries] {
        if !performedSeries.isEmpty { return performedSeries }
        var order: [String] = []
        var grouped: [String: [MPPSReferencedInstance]] = [:]
        let classUID = referencedSOPClassUID ?? Self.legacyReferencedSOPClassUID
        for ref in referencedSOPs {
            if grouped[ref.seriesUID] == nil { order.append(ref.seriesUID) }
            grouped[ref.seriesUID, default: []].append(
                MPPSReferencedInstance(sopClassUID: classUID, sopInstanceUID: ref.sopInstanceUID))
        }
        return order.map { uid in
            MPPSPerformedSeries(
                seriesInstanceUID: uid,
                protocolName: protocolName ?? "UNSPECIFIED",
                performingPhysicianName: performingPhysicianName,
                referencedImages: grouped[uid] ?? [])
        }
    }
}

#if canImport(Network)

// MARK: - DICOM MPPS Service

/// DICOM Modality Performed Procedure Step Service
///
/// Implements the DICOM MPPS Service for creating and updating performed procedure steps.
///
/// Reference: PS3.4 Annex F - Modality Performed Procedure Step SOP Class
///
/// ## Usage
///
/// ```swift
/// // Create MPPS (procedure started)
/// let mppsUID = try await DICOMMPPSService.create(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MODALITY",
///     calledAE: "PACS",
///     studyInstanceUID: "1.2.3.4.5",
///     status: .inProgress
/// )
///
/// // Update MPPS (procedure completed)
/// try await DICOMMPPSService.update(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MODALITY",
///     calledAE: "PACS",
///     mppsInstanceUID: mppsUID,
///     status: .completed,
///     referencedSOPs: [(studyUID, seriesUID, sopInstanceUID)]
/// )
/// ```
public enum DICOMMPPSService {
    
    /// Creates a new MPPS instance (N-CREATE)
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - studyInstanceUID: The Study Instance UID for the procedure
    ///   - status: The initial status (typically .inProgress)
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - patientName: Patient's Name (0010,0010)
    ///   - patientID: Patient ID (0010,0020)
    ///   - modality: Modality (0008,0060)
    ///   - procedureStepID: Performed Procedure Step ID (0040,0253)
    ///   - procedureStepDescription: Performed Procedure Step Description (0040,0254)
    ///   - performingPhysicianName: Performing Physician's Name (0008,1050)
    ///   - performedStationName: Performed Station Name (0040,0242)
    ///   - accessionNumber: Accession Number (0008,0050)
    ///   - scheduledProcedureStepID: Scheduled Procedure Step ID (0040,0009) for the Scheduled Step Attributes Sequence
    ///   - patientBirthDate / patientSex / studyID / performedLocation /
    ///     performedProcedureTypeDescription / procedureCode / performedProtocolCodes:
    ///     the remaining Type 2 attributes of PS3.4 Table F.7.2-1 (sent empty when nil)
    ///   - requestedProcedureID / requestedProcedureDescription /
    ///     scheduledProcedureStepDescription / scheduledProtocolCodes /
    ///     referencedStudySOPInstanceUID: Scheduled Step Attributes Sequence items,
    ///     normally copied from the worklist item
    ///   - attributes: extra elements written verbatim after the modelled ones
    ///   - specificCharacterSet: forces (0008,0005); nil chooses the narrowest set
    ///     that represents every text value
    /// - Returns: The created MPPS SOP Instance UID (the SCP's, if it assigned one)
    /// - Throws: `DICOMNetworkError.invalidState` when `status` is not IN PROGRESS
    ///   (PS3.4 F.7.2.1.2), `DICOMNetworkError` for connection or protocol errors.
    ///   Use ``createDetailed(host:port:callingAE:calledAE:studyInstanceUID:status:timeout:patientName:patientID:modality:procedureStepID:procedureStepDescription:performingPhysicianName:performedStationName:accessionNumber:scheduledProcedureStepID:patientBirthDate:patientSex:studyID:performedLocation:performedProcedureTypeDescription:procedureCode:performedProtocolCodes:requestedProcedureID:requestedProcedureDescription:scheduledProcedureStepDescription:scheduledProtocolCodes:referencedStudySOPInstanceUID:attributes:specificCharacterSet:)``
    ///   to also see a warning status.
    public static func create(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        status: MPPSStatus = .inProgress,
        timeout: TimeInterval = 60,
        patientName: String? = nil,
        patientID: String? = nil,
        modality: String? = nil,
        procedureStepID: String? = nil,
        procedureStepDescription: String? = nil,
        performingPhysicianName: String? = nil,
        performedStationName: String? = nil,
        accessionNumber: String? = nil,
        scheduledProcedureStepID: String? = nil,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        studyID: String? = nil,
        performedLocation: String? = nil,
        performedProcedureTypeDescription: String? = nil,
        procedureCode: MPPSCodedEntry? = nil,
        performedProtocolCodes: [MPPSCodedEntry] = [],
        requestedProcedureID: String? = nil,
        requestedProcedureDescription: String? = nil,
        scheduledProcedureStepDescription: String? = nil,
        scheduledProtocolCodes: [MPPSCodedEntry] = [],
        referencedStudySOPInstanceUID: String? = nil,
        attributes: [Tag: Data] = [:],
        specificCharacterSet: String? = nil
    ) async throws -> String {
        try await createDetailed(
            host: host, port: port, callingAE: callingAE, calledAE: calledAE,
            studyInstanceUID: studyInstanceUID, status: status, timeout: timeout,
            patientName: patientName, patientID: patientID, modality: modality,
            procedureStepID: procedureStepID, procedureStepDescription: procedureStepDescription,
            performingPhysicianName: performingPhysicianName, performedStationName: performedStationName,
            accessionNumber: accessionNumber, scheduledProcedureStepID: scheduledProcedureStepID,
            patientBirthDate: patientBirthDate, patientSex: patientSex, studyID: studyID,
            performedLocation: performedLocation,
            performedProcedureTypeDescription: performedProcedureTypeDescription,
            procedureCode: procedureCode, performedProtocolCodes: performedProtocolCodes,
            requestedProcedureID: requestedProcedureID,
            requestedProcedureDescription: requestedProcedureDescription,
            scheduledProcedureStepDescription: scheduledProcedureStepDescription,
            scheduledProtocolCodes: scheduledProtocolCodes,
            referencedStudySOPInstanceUID: referencedStudySOPInstanceUID,
            attributes: attributes, specificCharacterSet: specificCharacterSet
        ).sopInstanceUID
    }

    /// Creates a new MPPS instance (N-CREATE) and returns the full outcome —
    /// the SOP Instance UID actually created and the response status, so a
    /// warning (attributes coerced or dropped by the SCP) is visible to the caller.
    ///
    /// Same parameters as ``create(host:port:callingAE:calledAE:studyInstanceUID:status:timeout:patientName:patientID:modality:procedureStepID:procedureStepDescription:performingPhysicianName:performedStationName:accessionNumber:scheduledProcedureStepID:patientBirthDate:patientSex:studyID:performedLocation:performedProcedureTypeDescription:procedureCode:performedProtocolCodes:requestedProcedureID:requestedProcedureDescription:scheduledProcedureStepDescription:scheduledProtocolCodes:referencedStudySOPInstanceUID:attributes:specificCharacterSet:)``.
    public static func createDetailed(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        status: MPPSStatus = .inProgress,
        timeout: TimeInterval = 60,
        patientName: String? = nil,
        patientID: String? = nil,
        modality: String? = nil,
        procedureStepID: String? = nil,
        procedureStepDescription: String? = nil,
        performingPhysicianName: String? = nil,
        performedStationName: String? = nil,
        accessionNumber: String? = nil,
        scheduledProcedureStepID: String? = nil,
        patientBirthDate: String? = nil,
        patientSex: String? = nil,
        studyID: String? = nil,
        performedLocation: String? = nil,
        performedProcedureTypeDescription: String? = nil,
        procedureCode: MPPSCodedEntry? = nil,
        performedProtocolCodes: [MPPSCodedEntry] = [],
        requestedProcedureID: String? = nil,
        requestedProcedureDescription: String? = nil,
        scheduledProcedureStepDescription: String? = nil,
        scheduledProtocolCodes: [MPPSCodedEntry] = [],
        referencedStudySOPInstanceUID: String? = nil,
        attributes: [Tag: Data] = [:],
        specificCharacterSet: String? = nil
    ) async throws -> MPPSOperationResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = MPPSConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            specificCharacterSet: specificCharacterSet
        )
        
        // Generate a new SOP Instance UID for the MPPS
        let mppsInstanceUID = UIDGenerator.generateUID().value
        
        let procedureStep = MPPSProcedureStep(
            sopInstanceUID: mppsInstanceUID,
            status: status,
            studyInstanceUID: studyInstanceUID,
            startDateTime: Date(),
            attributes: attributes,
            patientName: patientName,
            patientID: patientID,
            modality: modality,
            procedureStepID: procedureStepID,
            procedureStepDescription: procedureStepDescription,
            performedStationAETitle: callingAE,
            performingPhysicianName: performingPhysicianName,
            performedStationName: performedStationName,
            accessionNumber: accessionNumber,
            scheduledProcedureStepID: scheduledProcedureStepID,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            studyID: studyID,
            performedLocation: performedLocation,
            performedProcedureTypeDescription: performedProcedureTypeDescription,
            procedureCode: procedureCode,
            performedProtocolCodes: performedProtocolCodes,
            requestedProcedureID: requestedProcedureID,
            requestedProcedureDescription: requestedProcedureDescription,
            scheduledProcedureStepDescription: scheduledProcedureStepDescription,
            scheduledProtocolCodes: scheduledProtocolCodes,
            referencedStudySOPInstanceUID: referencedStudySOPInstanceUID
        )
        
        return try await performNCreate(
            host: host,
            port: port,
            configuration: config,
            procedureStep: procedureStep
        )
    }
    
    /// Updates an existing MPPS instance (N-SET)
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - mppsInstanceUID: The MPPS SOP Instance UID to update
    ///   - status: The new status (.completed or .discontinued)
    ///   - referencedSOPs: Referenced image SOPs (for completed procedures)
    ///   - studyInstanceUID: Study Instance UID for the Scheduled Step Attributes Sequence
    ///   - accessionNumber: Accession Number for the Scheduled Step Attributes Sequence
    ///   - scheduledProcedureStepID: Scheduled Procedure Step ID (0040,0009)
    ///   - procedureStepID: Performed Procedure Step ID; also used as Requested
    ///     Procedure ID (0040,1001) when `requestedProcedureID` is nil (legacy)
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - referencedSOPClassUID: Referenced SOP Class UID (0008,1150) for every
    ///     `referencedSOPs` entry — the images' real class. Nil falls back to the
    ///     Secondary Capture placeholder, which is wrong for anything else.
    ///   - protocolName: Protocol Name (0018,1030), Type 1 in every Performed Series item
    ///   - performedSeries: fully described Performed Series items (preferred over `referencedSOPs`)
    ///   - seriesDescription / operatorsName / performingPhysicianName: Type 2 series attributes
    ///   - legacyNSetScheduledStepAttributes: also send Scheduled Step Attributes
    ///     Sequence (0040,0270) in the N-SET, which PS3.4 forbids; only for an SCP
    ///     known to require it (default false)
    ///   - discontinuationReason: Performed Procedure Step Discontinuation Reason
    ///     Code Sequence (0040,0281) item, sent when `status` is `.discontinued`
    ///     (CID 9300, scheme DCM)
    ///   - specificCharacterSet: forces (0008,0005); nil chooses automatically
    /// - Returns: the response status (success or warning) — a warning means the
    ///   SCP applied the N-SET but coerced or dropped attributes
    /// - Throws: `DICOMNetworkError.invalidState` when `status` is IN PROGRESS
    ///   (PS3.4 F.7.2.1.3) or COMPLETED without any Performed Series item
    ///   (Table F.7.2-1); `DICOMNetworkError` for connection or protocol errors
    @discardableResult
    public static func update(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        mppsInstanceUID: String,
        status: MPPSStatus,
        referencedSOPs: [(studyUID: String, seriesUID: String, sopInstanceUID: String)] = [],
        studyInstanceUID: String? = nil,
        accessionNumber: String? = nil,
        scheduledProcedureStepID: String? = nil,
        procedureStepID: String? = nil,
        timeout: TimeInterval = 60,
        referencedSOPClassUID: String? = nil,
        protocolName: String? = nil,
        performedSeries: [MPPSPerformedSeries] = [],
        seriesDescription: String? = nil,
        operatorsName: String? = nil,
        performingPhysicianName: String? = nil,
        requestedProcedureID: String? = nil,
        performedProtocolCodes: [MPPSCodedEntry] = [],
        attributes: [Tag: Data] = [:],
        legacyNSetScheduledStepAttributes: Bool = false,
        discontinuationReason: MPPSCodedEntry? = nil,
        specificCharacterSet: String? = nil
    ) async throws -> MPPSOperationResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = MPPSConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout,
            includeScheduledStepAttributesInNSet: legacyNSetScheduledStepAttributes,
            specificCharacterSet: specificCharacterSet
        )

        // Series-level Type 2 attributes shared by every series built from
        // `referencedSOPs`; `performedSeries` items carry their own.
        var series = performedSeries
        if series.isEmpty, !referencedSOPs.isEmpty,
           seriesDescription != nil || operatorsName != nil {
            let classUID = referencedSOPClassUID ?? MPPSProcedureStep.legacyReferencedSOPClassUID
            var order: [String] = []
            var grouped: [String: [MPPSReferencedInstance]] = [:]
            for ref in referencedSOPs {
                if grouped[ref.seriesUID] == nil { order.append(ref.seriesUID) }
                grouped[ref.seriesUID, default: []].append(
                    MPPSReferencedInstance(sopClassUID: classUID, sopInstanceUID: ref.sopInstanceUID))
            }
            series = order.map {
                MPPSPerformedSeries(seriesInstanceUID: $0,
                                    protocolName: protocolName ?? "UNSPECIFIED",
                                    seriesDescription: seriesDescription,
                                    performingPhysicianName: performingPhysicianName,
                                    operatorsName: operatorsName,
                                    referencedImages: grouped[$0] ?? [])
            }
        }
        
        let procedureStep = MPPSProcedureStep(
            sopInstanceUID: mppsInstanceUID,
            status: status,
            studyInstanceUID: studyInstanceUID,
            endDateTime: Date(),
            referencedSOPs: referencedSOPs,
            referencedSOPClassUID: referencedSOPClassUID,
            protocolName: protocolName,
            performedSeries: series,
            attributes: attributes,
            procedureStepID: procedureStepID,
            performingPhysicianName: performingPhysicianName,
            accessionNumber: accessionNumber,
            scheduledProcedureStepID: scheduledProcedureStepID,
            performedProtocolCodes: performedProtocolCodes,
            requestedProcedureID: requestedProcedureID ?? procedureStepID,
            discontinuationReason: discontinuationReason
        )
        
        return try await performNSet(
            host: host,
            port: port,
            configuration: config,
            procedureStep: procedureStep
        )
    }

    // MARK: - State validation (PS3.4 F.7.2.1.2 / F.7.2.1.3)

    /// The DIMSE-N operation a procedure step is validated for.
    public enum Operation: Sendable {
        case nCreate
        case nSet
    }

    /// Validates a procedure step against the MPPS state rules before it is sent.
    ///
    /// - N-CREATE (PS3.4 F.7.2.1.2): the status must be IN PROGRESS, and no
    ///   End Date/Time may be carried — a step is created running, never finished.
    /// - N-SET (PS3.4 F.7.2.1.3): the status may only become COMPLETED or
    ///   DISCONTINUED, and End Date/Time (0040,0250/0251) are then Type 1.
    /// - COMPLETED requires at least one Performed Series Sequence (0040,0340)
    ///   item (Table F.7.2-1, Type 1 in the final state); DISCONTINUED may have none.
    /// - N-CREATE requires a non-empty Modality (0008,0060), Type 1 (1/1) in
    ///   Table F.7.2-1 (since 2026-10-01, D87).
    ///
    /// - Throws: `DICOMNetworkError.invalidState` naming the clause that is violated
    public static func validate(_ step: MPPSProcedureStep, for operation: Operation) throws {
        switch operation {
        case .nCreate:
            guard step.status == .inProgress else {
                throw DICOMNetworkError.invalidState(
                    "MPPS N-CREATE must have Performed Procedure Step Status IN PROGRESS, " +
                    "got \(step.status.rawValue) (PS3.4 F.7.2.1.2); use N-SET to reach COMPLETED or DISCONTINUED")
            }
            guard step.endDateTime == nil else {
                throw DICOMNetworkError.invalidState(
                    "MPPS N-CREATE must not carry Performed Procedure Step End Date/Time while IN PROGRESS " +
                    "(PS3.4 F.7.2.1.2, Table F.7.2-1)")
            }
            // Modality (0008,0060) is 1/1 at N-CREATE (Table F.7.2-1, Image
            // Acquisition Results): never sent empty (D87).
            guard let modality = step.modality?.trimmingCharacters(in: .whitespaces), !modality.isEmpty else {
                throw DICOMNetworkError.invalidState(
                    "MPPS N-CREATE requires Modality (0008,0060), Type 1 in PS3.4 Table F.7.2-1")
            }
        case .nSet:
            guard step.status != .inProgress else {
                throw DICOMNetworkError.invalidState(
                    "MPPS N-SET may only set Performed Procedure Step Status to COMPLETED or DISCONTINUED, " +
                    "not IN PROGRESS (PS3.4 F.7.2.1.3)")
            }
            guard step.endDateTime != nil else {
                throw DICOMNetworkError.invalidState(
                    "MPPS N-SET to \(step.status.rawValue) requires Performed Procedure Step End Date/Time " +
                    "(0040,0250)/(0040,0251) (PS3.4 F.7.2.1.3, Table F.7.2-1 Type 1 in the final state)")
            }
            if step.status == .completed, step.effectivePerformedSeries.isEmpty {
                throw DICOMNetworkError.invalidState(
                    "MPPS N-SET to COMPLETED requires at least one Performed Series Sequence (0040,0340) item " +
                    "(PS3.4 Table F.7.2-1, Type 1 in the final state); use DISCONTINUED when nothing was acquired")
            }
        }
    }
    
    // MARK: - Private Implementation
    
    /// Performs the N-CREATE operation
    private static func performNCreate(
        host: String,
        port: UInt16,
        configuration: MPPSConfiguration,
        procedureStep: MPPSProcedureStep
    ) async throws -> MPPSOperationResult {
        // Reject a step that cannot legally be created before opening a connection.
        try validate(procedureStep, for: .nCreate)

        // Create association configuration
        let associationConfig = AssociationConfiguration(
            callingAETitle: configuration.callingAETitle,
            calledAETitle: configuration.calledAETitle,
            host: host,
            port: port,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            timeout: configuration.timeout,
            userIdentity: configuration.userIdentity
        )
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        // Create presentation context for MPPS
        let presentationContext = try PresentationContext(
            id: 1,
            abstractSyntax: modalityPerformedProcedureStepSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: [presentationContext])
            
            // Verify that the SOP Class was accepted
            guard negotiated.isContextAccepted(1) else {
                try await association.abort()
                throw DICOMNetworkError.sopClassNotSupported(modalityPerformedProcedureStepSOPClassUID)
            }
            
            // Get the accepted transfer syntax
            let acceptedTransferSyntax = negotiated.acceptedTransferSyntax(forContextID: 1) 
                ?? implicitVRLittleEndianTransferSyntaxUID
            
            // Perform the N-CREATE operation
            let result = try await sendNCreate(
                association: association,
                presentationContextID: 1,
                maxPDUSize: negotiated.maxPDUSize,
                procedureStep: procedureStep,
                transferSyntax: acceptedTransferSyntax,
                specificCharacterSet: configuration.specificCharacterSet
            )
            
            // Release association gracefully
            try await association.release()
            return result
            
        } catch {
            // Attempt to abort the association on error
            try? await association.abort()
            throw error
        }
    }
    
    /// Performs the N-SET operation
    private static func performNSet(
        host: String,
        port: UInt16,
        configuration: MPPSConfiguration,
        procedureStep: MPPSProcedureStep
    ) async throws -> MPPSOperationResult {
        // Reject an illegal transition before opening a connection.
        try validate(procedureStep, for: .nSet)

        // Create association configuration
        let associationConfig = AssociationConfiguration(
            callingAETitle: configuration.callingAETitle,
            calledAETitle: configuration.calledAETitle,
            host: host,
            port: port,
            maxPDUSize: configuration.maxPDUSize,
            implementationClassUID: configuration.implementationClassUID,
            implementationVersionName: configuration.implementationVersionName,
            timeout: configuration.timeout,
            userIdentity: configuration.userIdentity
        )
        
        // Create association
        let association = Association(configuration: associationConfig)
        
        // Create presentation context for MPPS
        let presentationContext = try PresentationContext(
            id: 1,
            abstractSyntax: modalityPerformedProcedureStepSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        do {
            // Establish association
            let negotiated = try await association.request(presentationContexts: [presentationContext])
            
            // Verify that the SOP Class was accepted
            guard negotiated.isContextAccepted(1) else {
                try await association.abort()
                throw DICOMNetworkError.sopClassNotSupported(modalityPerformedProcedureStepSOPClassUID)
            }
            
            // Get the accepted transfer syntax
            let acceptedTransferSyntax = negotiated.acceptedTransferSyntax(forContextID: 1) 
                ?? implicitVRLittleEndianTransferSyntaxUID
            
            // Perform the N-SET operation
            let result = try await sendNSet(
                association: association,
                presentationContextID: 1,
                maxPDUSize: negotiated.maxPDUSize,
                procedureStep: procedureStep,
                includeScheduledStepAttributes: configuration.includeScheduledStepAttributesInNSet,
                transferSyntax: acceptedTransferSyntax,
                specificCharacterSet: configuration.specificCharacterSet
            )
            
            // Release association gracefully
            try await association.release()
            return result
            
        } catch {
            // Attempt to abort the association on error
            try? await association.abort()
            throw error
        }
    }
    
    /// Sends the N-CREATE request and reads the complete N-CREATE-RSP.
    private static func sendNCreate(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        procedureStep: MPPSProcedureStep,
        transferSyntax: String,
        specificCharacterSet: String? = nil
    ) async throws -> MPPSOperationResult {
        // Build the attribute list
        let attributeData = buildMPPSAttributes(
            procedureStep: procedureStep, transferSyntax: transferSyntax, specificCharacterSet: specificCharacterSet)
        
        // Create N-CREATE request command set
        let commandSet = nCreateCommandSet(
            sopInstanceUID: procedureStep.sopInstanceUID, presentationContextID: presentationContextID)

        // Fragment and send the command and data set
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: commandSet,
            dataSet: attributeData,
            presentationContextID: presentationContextID
        )
        
        // Send all PDUs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive the complete response: an N-CREATE-RSP may carry an Attribute
        // List data set in a following P-DATA-TF (PS3.7 10.1.5.1), so keep
        // receiving until the assembler yields a whole message.
        let assembler = MessageAssembler()
        while true {
            let responsePDU = try await association.receive()
            guard let message = try assembler.addPDVs(from: responsePDU) else { continue }

            guard message.command == .nCreateResponse else {
                throw DICOMNetworkError.decodingFailed(
                    "Expected N-CREATE-RSP, got \(message.command?.description ?? "unknown")")
            }
            let response = NCreateResponse(commandSet: message.commandSet, presentationContextID: presentationContextID)
            let status = response.status
            guard status.isSuccessOrWarning else {
                // PS3.4 F.7.2.1.4: no MPPS-specific codes; PS3.7 Annex C names (D83)
                throw DICOMNetworkError.mppsOperationFailed(
                    operation: "N-CREATE", status: status,
                    errorComment: message.commandSet.errorComment, errorID: message.commandSet.errorID)
            }
            // PS3.7 10.1.5.1.4: the SCP may assign the SOP Instance UID; if it
            // returns one, that is the instance to use for every later N-SET.
            let returnedUID = response.affectedSOPInstanceUID
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            let effectiveUID = returnedUID.isEmpty ? procedureStep.sopInstanceUID : returnedUID
            return MPPSOperationResult(
                sopInstanceUID: effectiveUID,
                status: status,
                requestedSOPInstanceUID: procedureStep.sopInstanceUID)
        }
    }
    
    /// Sends the N-SET request and reads the complete N-SET-RSP.
    private static func sendNSet(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        procedureStep: MPPSProcedureStep,
        includeScheduledStepAttributes: Bool,
        transferSyntax: String,
        specificCharacterSet: String? = nil
    ) async throws -> MPPSOperationResult {
        // Build the N-SET modification list (only update-allowed attributes)
        let modificationData = buildNSetAttributes(
            procedureStep: procedureStep,
            includeScheduledStepAttributes: includeScheduledStepAttributes,
            transferSyntax: transferSyntax,
            specificCharacterSet: specificCharacterSet)
        
        // Create N-SET request command set
        let commandSet = nSetCommandSet(
            sopInstanceUID: procedureStep.sopInstanceUID, presentationContextID: presentationContextID)

        // Fragment and send the command and data set
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: commandSet,
            dataSet: modificationData,
            presentationContextID: presentationContextID
        )
        
        // Send all PDUs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive the complete response: an N-SET-RSP may carry an Attribute List
        // data set in a following P-DATA-TF (PS3.7 10.1.3.1), so keep receiving
        // until the assembler yields a whole message.
        let assembler = MessageAssembler()
        while true {
            let responsePDU = try await association.receive()
            guard let message = try assembler.addPDVs(from: responsePDU) else { continue }

            guard message.command == .nSetResponse else {
                throw DICOMNetworkError.decodingFailed(
                    "Expected N-SET-RSP, got \(message.command?.description ?? "unknown")")
            }
            let response = NSetResponse(commandSet: message.commandSet, presentationContextID: presentationContextID)
            let status = response.status
            guard status.isSuccessOrWarning else {
                // PS3.4 Table F.7.2-2 (0110 + Error ID A710) / PS3.7 Annex C (D83)
                throw DICOMNetworkError.mppsOperationFailed(
                    operation: "N-SET", status: status,
                    errorComment: message.commandSet.errorComment, errorID: message.commandSet.errorID)
            }
            return MPPSOperationResult(sopInstanceUID: procedureStep.sopInstanceUID, status: status)
        }
    }
    
    /// Builds the N-CREATE data set per PS3.4 Annex F, Table F.7.2-1.
    ///
    /// Every Type 1 and Type 2 attribute of the Performed Procedure Step
    /// Relationship, Performed Procedure Step Information and Image Acquisition
    /// Results modules is emitted (Type 2 as zero-length when unknown), plus a
    /// zero-length Performed Procedure Step Discontinuation Reason Code Sequence
    /// (0040,0281) so the N-SET may fill it (F.7.2.1.1 note), followed by the
    /// caller's `attributes`. Elements are sorted by tag before encoding
    /// (PS3.5 7.1).
    ///
    /// The Specific Character Set (0008,0005) — Type 1C — is chosen with
    /// `DIMSECharacterSet.choose(for:override:)` over every text value, nested
    /// items included, and written only when an extended repertoire is needed
    /// (PS3.5 6.1.2); text VRs are encoded in that set.
    internal static func buildMPPSAttributes(
        procedureStep: MPPSProcedureStep,
        transferSyntax: String,
        specificCharacterSet: String? = nil
    ) -> Data {
        let explicit = transferSyntax == explicitVRLittleEndianTransferSyntaxUID
        let charset = chooseCharacterSet(for: procedureStep, override: specificCharacterSet)
        var elements: [(Tag, Data)] = []
        func add(_ g: UInt16, _ e: UInt16, _ vr: VR, _ value: String?) {
            let tag = Tag(group: g, element: e)
            elements.append((tag, encodeElement(tag: tag, vr: vr, value: value ?? "", explicit: explicit, charset: charset)))
        }
        func addSeq(_ g: UInt16, _ e: UInt16, _ data: Data) {
            elements.append((Tag(group: g, element: e), data))
        }

        // ---- Performed Procedure Step Relationship module ----
        if let declared = charset.specificCharacterSet {
            add(0x0008, 0x0005, .CS, declared)                                    // Specific Character Set 1C
        }
        addSeq(0x0008, 0x1120, encodeEmptySequence(tag: Tag(group: 0x0008, element: 0x1120), explicit: explicit)) // Referenced Patient Sequence 2
        add(0x0010, 0x0010, .PN, procedureStep.patientName)                       // Patient's Name 2
        add(0x0010, 0x0020, .LO, procedureStep.patientID)                         // Patient ID 2
        add(0x0010, 0x0030, .DA, procedureStep.patientBirthDate)                  // Patient's Birth Date 2
        add(0x0010, 0x0040, .CS, procedureStep.patientSex)                        // Patient's Sex 2
        addSeq(0x0040, 0x0270, buildScheduledStepAttributesSequence(procedureStep: procedureStep, explicit: explicit, charset: charset)) // 1

        // ---- Performed Procedure Step Information module ----
        add(0x0040, 0x0241, .AE, procedureStep.performedStationAETitle)           // Performed Station AE Title 1
        add(0x0040, 0x0242, .SH, procedureStep.performedStationName)              // Performed Station Name 2
        add(0x0040, 0x0243, .SH, procedureStep.performedLocation)                 // Performed Location 2
        let (startDate, startTime) = dateTimeStrings(procedureStep.startDateTime)
        add(0x0040, 0x0244, .DA, startDate)                                       // PPS Start Date 1
        add(0x0040, 0x0245, .TM, startTime)                                       // PPS Start Time 1
        add(0x0040, 0x0252, .CS, procedureStep.status.rawValue)                   // PPS Status 1
        add(0x0040, 0x0253, .SH, procedureStep.procedureStepID ?? "1")            // PPS ID 1
        add(0x0040, 0x0254, .LO, procedureStep.procedureStepDescription)          // PPS Description 2
        add(0x0040, 0x0255, .LO, procedureStep.performedProcedureTypeDescription) // Performed Procedure Type Description 2
        addSeq(0x0008, 0x1032, encodeCodeSequence(                                 // Procedure Code Sequence 2
            tag: Tag(group: 0x0008, element: 0x1032),
            codes: procedureStep.procedureCode.map { [$0] } ?? [], explicit: explicit, charset: charset))
        let (endDate, endTime) = dateTimeStrings(procedureStep.endDateTime)
        add(0x0040, 0x0250, .DA, endDate)                                         // PPS End Date 2
        add(0x0040, 0x0251, .TM, endTime)                                         // PPS End Time 2
        // PPS Discontinuation Reason Code Sequence 3/3, created zero-length so a later
        // N-SET to DISCONTINUED may fill it: "If an SCU wishes to use the PPS
        // Discontinuation Reason Code Sequence (0040,0281), it must create that
        // Attribute (zero-length) during N-CREATE" (PS3.4 F.7.2.1.1 note; F.7.2.1.2
        // "All Attributes shall be created before they can be set") — D86.
        addSeq(0x0040, 0x0281, encodeEmptySequence(tag: Tag(group: 0x0040, element: 0x0281), explicit: explicit))

        // ---- Image Acquisition Results module ----
        add(0x0008, 0x0060, .CS, procedureStep.modality)                          // Modality 1
        add(0x0020, 0x0010, .SH, procedureStep.studyID)                           // Study ID 2
        addSeq(0x0040, 0x0260, encodeCodeSequence(                                 // Performed Protocol Code Sequence 2
            tag: Tag(group: 0x0040, element: 0x0260),
            codes: procedureStep.performedProtocolCodes, explicit: explicit, charset: charset))
        addSeq(0x0040, 0x0340, buildPerformedSeriesSequence(procedureStep: procedureStep, explicit: explicit, charset: charset)) // 2

        // ---- Caller-supplied extras ----
        let modelled = Set(elements.map { $0.0 })
        for (tag, value) in procedureStep.attributes where !modelled.contains(tag) {
            elements.append((tag, encodeRawElement(tag: tag, data: value, explicit: explicit)))
        }

        return elements.sorted { $0.0 < $1.0 }.reduce(into: Data()) { $0.append($1.1) }
    }

    /// Builds the N-SET modification list per PS3.4 Table F.7.2-1 (N-SET column).
    ///
    /// Sends the attributes an N-SET may modify: End Date/Time, Status, Description,
    /// Performed Series Sequence (Type 1 and non-empty in the final state), plus
    /// the caller's `attributes`. The Scheduled Step Attributes Sequence is *Not
    /// allowed* here and is emitted only when `includeScheduledStepAttributes` is set.
    ///
    /// When the status is DISCONTINUED and a `discontinuationReason` is given, the
    /// Performed Procedure Step Discontinuation Reason Code Sequence (0040,0281)
    /// is sent as a one-item code sequence (CID 9300).
    internal static func buildNSetAttributes(
        procedureStep: MPPSProcedureStep,
        includeScheduledStepAttributes: Bool,
        transferSyntax: String,
        specificCharacterSet: String? = nil
    ) -> Data {
        let explicit = transferSyntax == explicitVRLittleEndianTransferSyntaxUID
        let charset = chooseCharacterSet(for: procedureStep, override: specificCharacterSet)
        var elements: [(Tag, Data)] = []
        func add(_ g: UInt16, _ e: UInt16, _ vr: VR, _ value: String?) {
            let tag = Tag(group: g, element: e)
            elements.append((tag, encodeElement(tag: tag, vr: vr, value: value ?? "", explicit: explicit, charset: charset)))
        }

        if let declared = charset.specificCharacterSet {
            add(0x0008, 0x0005, .CS, declared)                                    // Specific Character Set 1C
        }

        // PPS End Date/Time (0040,0250/0251) — Type 1 once COMPLETED/DISCONTINUED
        let (endDate, endTime) = dateTimeStrings(procedureStep.endDateTime ?? Date())
        add(0x0040, 0x0250, .DA, endDate)
        add(0x0040, 0x0251, .TM, endTime)
        add(0x0040, 0x0252, .CS, procedureStep.status.rawValue)                   // PPS Status
        if let desc = procedureStep.procedureStepDescription, !desc.isEmpty {
            add(0x0040, 0x0254, .LO, desc)                                        // PPS Description 3/2
        }
        if let typeDesc = procedureStep.performedProcedureTypeDescription, !typeDesc.isEmpty {
            add(0x0040, 0x0255, .LO, typeDesc)                                    // Performed Procedure Type Description 3/2
        }
        if !procedureStep.performedProtocolCodes.isEmpty {
            elements.append((Tag(group: 0x0040, element: 0x0260), encodeCodeSequence(
                tag: Tag(group: 0x0040, element: 0x0260),
                codes: procedureStep.performedProtocolCodes, explicit: explicit, charset: charset)))
        }
        if includeScheduledStepAttributes {
            elements.append((Tag(group: 0x0040, element: 0x0270),
                             buildScheduledStepAttributesSequence(procedureStep: procedureStep, explicit: explicit, charset: charset)))
        }
        // PPS Discontinuation Reason Code Sequence (0040,0281) — Type 3, only meaningful
        // for DISCONTINUED (PS3.3 C.4.15, CID 9300).
        if procedureStep.status == .discontinued, let reason = procedureStep.discontinuationReason {
            elements.append((Tag(group: 0x0040, element: 0x0281), encodeCodeSequence(
                tag: Tag(group: 0x0040, element: 0x0281),
                codes: [reason], explicit: explicit, charset: charset)))
        }
        elements.append((Tag(group: 0x0040, element: 0x0340),
                         buildPerformedSeriesSequence(procedureStep: procedureStep, explicit: explicit, charset: charset)))

        let modelled = Set(elements.map { $0.0 })
        for (tag, value) in procedureStep.attributes where !modelled.contains(tag) {
            elements.append((tag, encodeRawElement(tag: tag, data: value, explicit: explicit)))
        }

        return elements.sorted { $0.0 < $1.0 }.reduce(into: Data()) { $0.append($1.1) }
    }

    /// DA / TM strings for a date, or empty strings (Type 2) when nil.
    private static func dateTimeStrings(_ date: Date?) -> (String, String) {
        guard let date else { return ("", "") }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmmss"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        return (dateFormatter.string(from: date), timeFormatter.string(from: date))
    }

    /// The Data Elements whose values are encoded with the Specific Character Set
    /// (PS3.5 6.1.2.3): PN, LO, SH, ST, LT, UT and UC. Every other VR is ISO 646.
    internal static let characterSetVRs: Set<VR> = [.PN, .LO, .SH, .ST, .LT, .UT, .UC]

    /// Chooses the character set for a data set: the explicit `override`, then the
    /// step's own `specificCharacterSet`, else the narrowest set that represents
    /// every text value (root and nested).
    internal static func chooseCharacterSet(for step: MPPSProcedureStep, override: String?) -> DIMSECharacterSet {
        DIMSECharacterSet.choose(for: step.textValues, override: override ?? step.specificCharacterSet)
    }

    // MARK: - Sequence builders

    /// Builds the Scheduled Step Attributes Sequence (0040,0270) — Type 1 in
    /// N-CREATE — with every nested Type 1/2 attribute of Table F.7.2-1.
    private static func buildScheduledStepAttributesSequence(
        procedureStep: MPPSProcedureStep,
        explicit: Bool,
        charset: DIMSECharacterSet
    ) -> Data {
        var item: [(Tag, Data)] = []
        func add(_ g: UInt16, _ e: UInt16, _ vr: VR, _ value: String?) {
            let tag = Tag(group: g, element: e)
            item.append((tag, encodeElement(tag: tag, vr: vr, value: value ?? "", explicit: explicit, charset: charset)))
        }
        add(0x0008, 0x0050, .SH, procedureStep.accessionNumber)                   // Accession Number 2
        // Referenced Study Sequence (0008,1110) — Type 2; carries the worklist item's
        // study reference when known, otherwise empty.
        let refStudyTag = Tag(group: 0x0008, element: 0x1110)
        if let studyRef = procedureStep.referencedStudySOPInstanceUID, !studyRef.isEmpty {
            // Detached Study Management SOP Class 1.2.840.10008.3.1.2.3.1 is
            // retired (PS3.6 Table A-1), but it is what the Modality Worklist
            // item's Referenced Study Sequence supplies (PS3.3 C.4-13 keeps the
            // sequence for that purpose), and the MPPS copies the reference
            // through unchanged.
            item.append((refStudyTag, encodeReferencedSOPSequence(
                tag: refStudyTag,
                references: [MPPSReferencedInstance(
                    sopClassUID: MPPSProcedureStep.detachedStudyManagementSOPClassUID,
                    sopInstanceUID: studyRef)],
                explicit: explicit)))
        } else {
            item.append((refStudyTag, encodeEmptySequence(tag: refStudyTag, explicit: explicit)))
        }
        add(0x0020, 0x000D, .UI, procedureStep.studyInstanceUID)                  // Study Instance UID 1
        add(0x0032, 0x1060, .LO, procedureStep.requestedProcedureDescription)     // Requested Procedure Description 2
        add(0x0040, 0x0007, .LO, procedureStep.scheduledProcedureStepDescription) // SPS Description 2
        item.append((Tag(group: 0x0040, element: 0x0008), encodeCodeSequence(      // Scheduled Protocol Code Sequence 2
            tag: Tag(group: 0x0040, element: 0x0008),
            codes: procedureStep.scheduledProtocolCodes, explicit: explicit, charset: charset)))
        // Scheduled Procedure Step ID is Type 2 in this item (PS3.4 Table
        // F.7.2-1, N-CREATE column 2/2): sent empty when the worklist did not
        // supply one, never invented.
        add(0x0040, 0x0009, .SH, procedureStep.scheduledProcedureStepID)         // SPS ID 2
        add(0x0040, 0x1001, .SH, procedureStep.requestedProcedureID)              // Requested Procedure ID 2

        let itemData = item.sorted { $0.0 < $1.0 }.reduce(into: Data()) { $0.append($1.1) }
        return encodeSequenceWithItem(
            tag: Tag(group: 0x0040, element: 0x0270),
            itemData: itemData,
            explicit: explicit
        )
    }

    /// Builds the Performed Series Sequence (0040,0340) — Type 2 at N-CREATE,
    /// Type 1 and non-empty once COMPLETED/DISCONTINUED. Each item carries the
    /// Type 1 Protocol Name and every Type 2 attribute of Table F.7.2-1.
    private static func buildPerformedSeriesSequence(
        procedureStep: MPPSProcedureStep,
        explicit: Bool,
        charset: DIMSECharacterSet
    ) -> Data {
        let seriesTag = Tag(group: 0x0040, element: 0x0340)
        let series = procedureStep.effectivePerformedSeries
        if series.isEmpty {
            return encodeEmptySequence(tag: seriesTag, explicit: explicit)
        }

        var allItemsData = Data()
        for s in series {
            var item: [(Tag, Data)] = []
            func add(_ g: UInt16, _ e: UInt16, _ vr: VR, _ value: String?) {
                let tag = Tag(group: g, element: e)
                item.append((tag, encodeElement(tag: tag, vr: vr, value: value ?? "", explicit: explicit, charset: charset)))
            }
            add(0x0008, 0x0054, .AE, s.retrieveAETitle)                            // Retrieve AE Title 2
            add(0x0008, 0x1050, .PN, s.performingPhysicianName)                    // Performing Physician's Name 2
            add(0x0008, 0x1070, .PN, s.operatorsName)                              // Operators' Name 2
            add(0x0008, 0x103E, .LO, s.seriesDescription)                          // Series Description 2
            item.append((Tag(group: 0x0008, element: 0x1140), encodeReferencedSOPSequence(   // Referenced Image Sequence 2
                tag: Tag(group: 0x0008, element: 0x1140), references: s.referencedImages, explicit: explicit)))
            add(0x0018, 0x1030, .LO, s.protocolName.isEmpty ? "UNSPECIFIED" : s.protocolName) // Protocol Name 1
            add(0x0020, 0x000E, .UI, s.seriesInstanceUID)                          // Series Instance UID 1
            item.append((Tag(group: 0x0040, element: 0x0220), encodeReferencedSOPSequence(   // Referenced Non-Image Composite SOP Instance Sequence 2
                tag: Tag(group: 0x0040, element: 0x0220), references: s.referencedNonImageInstances, explicit: explicit)))

            let itemData = item.sorted { $0.0 < $1.0 }.reduce(into: Data()) { $0.append($1.1) }
            allItemsData.append(encodeSequenceItem(itemData: itemData))
        }

        var data = Data()
        data.append(encodeSequenceTag(tag: seriesTag, explicit: explicit))
        data.append(allItemsData)
        data.append(sequenceDelimiter())
        return data
    }

    /// Encodes a sequence of (Referenced SOP Class UID, Referenced SOP Instance UID)
    /// items; an empty sequence when `references` is empty.
    private static func encodeReferencedSOPSequence(
        tag: Tag, references: [MPPSReferencedInstance], explicit: Bool
    ) -> Data {
        guard !references.isEmpty else { return encodeEmptySequence(tag: tag, explicit: explicit) }
        var data = encodeSequenceTag(tag: tag, explicit: explicit)
        for ref in references {
            var itemData = Data()
            itemData.append(encodeElement(tag: Tag(group: 0x0008, element: 0x1150), vr: .UI, value: ref.sopClassUID, explicit: explicit))
            itemData.append(encodeElement(tag: Tag(group: 0x0008, element: 0x1155), vr: .UI, value: ref.sopInstanceUID, explicit: explicit))
            data.append(encodeSequenceItem(itemData: itemData))
        }
        data.append(sequenceDelimiter())
        return data
    }

    /// Encodes a Code Sequence Macro (PS3.3 8.8) sequence; empty when `codes` is empty.
    private static func encodeCodeSequence(tag: Tag, codes: [MPPSCodedEntry], explicit: Bool,
                                           charset: DIMSECharacterSet = DIMSECharacterSet(specificCharacterSet: nil)) -> Data {
        guard !codes.isEmpty else { return encodeEmptySequence(tag: tag, explicit: explicit) }
        var data = encodeSequenceTag(tag: tag, explicit: explicit)
        for code in codes {
            var itemData = Data()
            itemData.append(encodeElement(tag: Tag(group: 0x0008, element: 0x0100), vr: .SH, value: code.codeValue, explicit: explicit, charset: charset))
            itemData.append(encodeElement(tag: Tag(group: 0x0008, element: 0x0102), vr: .SH, value: code.codingSchemeDesignator, explicit: explicit, charset: charset))
            itemData.append(encodeElement(tag: Tag(group: 0x0008, element: 0x0104), vr: .LO, value: code.codeMeaning, explicit: explicit, charset: charset))
            data.append(encodeSequenceItem(itemData: itemData))
        }
        data.append(sequenceDelimiter())
        return data
    }

    /// Encodes a caller-supplied element verbatim, taking the VR from the data
    /// dictionary (UN when unknown). Odd-length values are padded.
    private static func encodeRawElement(tag: Tag, data value: Data, explicit: Bool) -> Data {
        let vr = DataElementDictionary.lookup(tag: tag)?.vr.first ?? .UN
        var valueData = value
        if valueData.count % 2 != 0 { valueData.append(vr.isStringVR && vr != .UI ? 0x20 : 0x00) }
        var data = Data()
        var group = tag.group.littleEndian
        var element = tag.element.littleEndian
        data.append(Data(bytes: &group, count: 2))
        data.append(Data(bytes: &element, count: 2))
        if explicit {
            data.append(vr.rawValue.data(using: .ascii) ?? Data([0x55, 0x4E]))
            if vr.uses32BitLength {
                data.append(Data([0x00, 0x00]))
                data.append(le32(UInt32(valueData.count)))
            } else {
                var length = UInt16(valueData.count).littleEndian
                data.append(Data(bytes: &length, count: 2))
            }
        } else {
            data.append(le32(UInt32(valueData.count)))
        }
        data.append(valueData)
        return data
    }

    // MARK: - Sequence encoding helpers

    /// Encodes a complete sequence with a single item.
    private static func encodeSequenceWithItem(tag: Tag, itemData: Data, explicit: Bool) -> Data {
        var data = Data()
        data.append(encodeSequenceTag(tag: tag, explicit: explicit))
        data.append(encodeSequenceItem(itemData: itemData))
        data.append(sequenceDelimiter())
        return data
    }

    /// Encodes an empty sequence (no items).
    private static func encodeEmptySequence(tag: Tag, explicit: Bool) -> Data {
        var data = Data()
        data.append(encodeSequenceTag(tag: tag, explicit: explicit))
        data.append(sequenceDelimiter())
        return data
    }

    /// Encodes a sequence tag with undefined length.
    private static func encodeSequenceTag(tag: Tag, explicit: Bool) -> Data {
        var data = Data()
        var group = tag.group.littleEndian
        var element = tag.element.littleEndian
        data.append(Data(bytes: &group, count: 2))
        data.append(Data(bytes: &element, count: 2))
        if explicit {
            data.append(contentsOf: [0x53, 0x51])   // "SQ"
            data.append(contentsOf: [0x00, 0x00])   // reserved
        }
        data.append(le32(0xFFFFFFFF))                // undefined length
        return data
    }

    /// Encodes a sequence item with undefined length.
    private static func encodeSequenceItem(itemData: Data) -> Data {
        var data = Data()
        // Item tag (FFFE,E000)
        data.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        data.append(le32(0xFFFFFFFF))   // undefined length
        data.append(itemData)
        // Item delimiter (FFFE,E00D)
        data.append(contentsOf: [0xFE, 0xFF, 0x0D, 0xE0])
        data.append(le32(0x00000000))
        return data
    }

    /// Encodes a sequence delimiter (FFFE,E0DD).
    private static func sequenceDelimiter() -> Data {
        var data = Data()
        data.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
        data.append(le32(0x00000000))
        return data
    }

    /// Little-endian 32-bit helper.
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
              UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
    
    /// Encodes a simple data element (helper for command set)
    /// The N-CREATE-RQ command set (PS3.7 Table 10.3-1): Affected SOP Class UID
    /// (0000,0002) = MPPS, Affected SOP Instance UID (0000,1000), Message ID 1,
    /// data set present. Built through `CommandSet`, so odd-length UI values
    /// are NULL-padded to even length (PS3.5 Table 6.2-1).
    static func nCreateCommandSet(sopInstanceUID: String, presentationContextID: UInt8) -> CommandSet {
        NCreateRequest(
            messageID: 1,
            affectedSOPClassUID: modalityPerformedProcedureStepSOPClassUID,
            affectedSOPInstanceUID: sopInstanceUID,
            hasDataSet: true,
            presentationContextID: presentationContextID
        ).commandSet
    }

    /// The N-SET-RQ command set (PS3.7 Table 10.3-5): Requested SOP Class UID
    /// (0000,0003) = MPPS, Requested SOP Instance UID (0000,1001), Message ID 1,
    /// data set present. UI values are NULL-padded by `CommandSet`.
    static func nSetCommandSet(sopInstanceUID: String, presentationContextID: UInt8) -> CommandSet {
        NSetRequest(
            messageID: 1,
            requestedSOPClassUID: modalityPerformedProcedureStepSOPClassUID,
            requestedSOPInstanceUID: sopInstanceUID,
            hasDataSet: true,
            presentationContextID: presentationContextID
        ).commandSet
    }
    
    /// Encodes a single data element for the attribute list.
    ///
    /// Text VRs (PN, LO, SH, ST, LT, UT, UC) are encoded with `charset`; every
    /// other VR is ISO 646. A value never silently becomes zero-length: a
    /// non-ASCII character in a non-text VR falls back to its UTF-8 bytes.
    private static func encodeElement(tag: Tag, vr: VR, value: String, explicit: Bool,
                                      charset: DIMSECharacterSet = DIMSECharacterSet(specificCharacterSet: nil)) -> Data {
        var data = Data()
        
        // Tag (4 bytes, little endian)
        var group = tag.group.littleEndian
        var element = tag.element.littleEndian
        data.append(Data(bytes: &group, count: 2))
        data.append(Data(bytes: &element, count: 2))
        
        // Prepare value data with padding
        var valueData: Data
        if characterSetVRs.contains(vr) {
            valueData = charset.encode(value)
        } else {
            valueData = value.data(using: .ascii) ?? Data(value.utf8)
        }
        
        // Pad to even length per DICOM rules (PS3.5 Section 6.2)
        // DICOM requires all Value Fields to have even length
        if valueData.count % 2 != 0 {
            // Use space (0x20) padding for text VRs, null (0x00) for binary VRs
            // This is a DICOM-specific requirement to maintain alignment
            let paddingChar: UInt8 = (vr == .UI) ? 0x00 : (vr.isStringVR ? 0x20 : 0x00)
            valueData.append(paddingChar)
        }
        
        if explicit {
            // Explicit VR encoding
            // VR (2 bytes)
            if let vrBytes = vr.rawValue.data(using: .ascii) {
                data.append(vrBytes)
            } else {
                data.append(Data([0x55, 0x4E])) // "UN" fallback
            }
            
            // Check if VR uses 4-byte length
            if vr.uses32BitLength {
                // Reserved (2 bytes)
                data.append(Data([0x00, 0x00]))
                // Value Length (4 bytes)
                var length = UInt32(valueData.count).littleEndian
                data.append(Data(bytes: &length, count: 4))
            } else {
                // Value Length (2 bytes)
                var length = UInt16(valueData.count).littleEndian
                data.append(Data(bytes: &length, count: 2))
            }
        } else {
            // Implicit VR encoding
            // Value Length (4 bytes)
            var length = UInt32(valueData.count).littleEndian
            data.append(Data(bytes: &length, count: 4))
        }
        
        // Value
        data.append(valueData)
        
        return data
    }
}

#endif

// MARK: - Option value rules (D263)

/// The value rules and texts of the `dicom-mpps` options, shared with the DICOMStudio
/// CLI Workshop so the two front ends accept the same input and word a refusal or an
/// SCP warning identically (formerly CLI-local in `DICOMMPPSCommand`, D263).
extension DICOMMPPSService {

    /// Parses a `--status` word into Performed Procedure Step Status (0040,0252), whose
    /// Enumerated Values are IN PROGRESS, DISCONTINUED and COMPLETED (PS3.3 2026a
    /// Table C.4-14). Case-insensitive; the space of IN PROGRESS may be omitted or
    /// written `_`. Returns nil for any other word (see ``invalidStatusMessage``).
    public static func parseStatus(_ statusString: String) -> MPPSStatus? {
        switch statusString.uppercased().replacingOccurrences(of: " ", with: "") {
        case "INPROGRESS", "IN_PROGRESS":
            return .inProgress
        case "COMPLETED":
            return .completed
        case "DISCONTINUED":
            return .discontinued
        default:
            return nil
        }
    }

    /// The refusal when ``parseStatus(_:)`` returns nil.
    public static let invalidStatusMessage = "Invalid status. Use 'IN PROGRESS', 'COMPLETED', or 'DISCONTINUED'"

    /// Patient's Sex (0010,0040) Enumerated Values, PS3.3 2026a Table C.2-3: M, F, O.
    public static let patientSexEnumeratedValues: [String] = ["M", "F", "O"]

    /// The canonical Patient's Sex (0010,0040) value of `value` (trimmed, upper-cased),
    /// or nil when it is not one of ``patientSexEnumeratedValues`` (PS3.3 Table C.2-3).
    public static func canonicalPatientSex(_ value: String) -> String? {
        let upper = value.trimmingCharacters(in: .whitespaces).uppercased()
        return patientSexEnumeratedValues.contains(upper) ? upper : nil
    }

    /// The refusal of a `--patient-sex` value that is not an Enumerated Value.
    public static func patientSexErrorMessage(_ value: String) -> String {
        "--patient-sex must be one of M, F, O (Patient's Sex (0010,0040) Enumerated Values, PS3.3 Table C.2-3), got '\(value)'"
    }

    /// Whether `value` is a DA value YYYYMMDD: 8 bytes fixed, ASCII digits only
    /// (PS3.5 2026a Table 6.2-1 DA).
    public static func isValidBirthDate(_ value: String) -> Bool {
        value.count == 8 && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The refusal of a `--patient-birth-date` value that is not DA YYYYMMDD.
    public static func birthDateErrorMessage(_ value: String) -> String {
        "--patient-birth-date must be YYYYMMDD (VR DA, PS3.5 Table 6.2-1), got '\(value)'"
    }

    /// The response status worded by DICOMNetwork's generated tables: PS3.4 2026a
    /// Table F.7.2-2 for an N-SET (`operation == "N-SET"`), else PS3.7 Annex C (MPPS
    /// N-CREATE has no specific codes, PS3.4 F.7.2.1.4), e.g.
    /// "Warning (0x0107): Attribute List warning".
    public static func describeStatus(_ status: DIMSEStatus, operation: String) -> String {
        DIMSEServiceStatusText.describe(status, service: operation == "N-SET" ? .mppsNSet : .dimseN)
    }

    /// The stderr line for a Warning-class response — the SCP performed the operation
    /// but coerced or dropped attributes (PS3.7 Annex C) — with its trailing newline.
    public static func warningLine(_ warning: DIMSEStatus, operation: String) -> String {
        "warning: SCP completed the \(operation) with \(describeStatus(warning, operation: operation)) — attributes may have been coerced or dropped\n"
    }
}
