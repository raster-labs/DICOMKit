// StructuredReportModel.swift
// DICOMStudio
//
// DICOM Studio — Structured Reporting models for Milestone 7
// Reference: DICOM PS3.3 C.17 (SR Document), PS3.16 (Content Mapping Resources)
// Supports 8 SR document types, 15 of the 16 content item value types, coded terminology
// NEMA-verified: 2026a, checked 2026-10-05 — 8 SOP Class UIDs diffed against PS3.6 2026a Table A-1 (8 registered, names match; measurementReport reuses Enhanced SR Storage); ContentItemValueType 15 cases against PS3.3 2026a Table C.17.3-7 (16 rows: 15 match, TABLE missing — P-STUDIO-SR-TABLE); SRRelationshipType 7 cases against Table C.17.3-8 (7/7); ContinuityOfContent against Table C.18.8-1 (2/2); SpatialCoordGraphicType against C.18.6.1.2 (5 match, POLYGON is not a 2D SCOORD Graphic Type — P-STUDIO-SCOORD-POLYGON); SpatialCoord3DGraphicType against C.18.9.1.2 (6/6); TemporalRangeType against C.18.7.1.1 (6/6); CodingSchemeDesignator 5 designators against PS3.16 2026a Table 8-1 (5/5, DCM's name corrected to "DICOM Controlled Terminology"); CAD/BI-RADS/tracking enums are UI state

import Foundation

// MARK: - SR Document Type

/// DICOM Structured Report document types (SOP Classes).
public enum SRDocumentType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Basic Text SR — free-text narrative reports.
    case basicText = "BASIC_TEXT"
    /// Enhanced SR — adds numeric measurements and coded findings.
    case enhanced = "ENHANCED"
    /// Comprehensive SR — adds spatial coordinates and full content items.
    case comprehensive = "COMPREHENSIVE"
    /// Comprehensive 3D SR — volumetric spatial coordinates.
    case comprehensive3D = "COMPREHENSIVE_3D"
    /// Measurement Report (TID 1500) — quantitative imaging biomarkers.
    case measurementReport = "MEASUREMENT_REPORT"
    /// Key Object Selection — flag significant images.
    case keyObjectSelection = "KEY_OBJECT_SELECTION"
    /// Mammography CAD SR — computer-aided detection for mammography.
    case mammographyCAD = "MAMMOGRAPHY_CAD"
    /// Chest CAD SR — computer-aided detection for chest imaging.
    case chestCAD = "CHEST_CAD"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .basicText: return "Basic Text SR"
        case .enhanced: return "Enhanced SR"
        case .comprehensive: return "Comprehensive SR"
        case .comprehensive3D: return "Comprehensive 3D SR"
        case .measurementReport: return "Measurement Report"
        case .keyObjectSelection: return "Key Object Selection"
        case .mammographyCAD: return "Mammography CAD SR"
        case .chestCAD: return "Chest CAD SR"
        }
    }

    /// DICOM SOP Class UID for each SR type.
    public var sopClassUID: String {
        switch self {
        case .basicText: return "1.2.840.10008.5.1.4.1.1.88.11"
        case .enhanced: return "1.2.840.10008.5.1.4.1.1.88.22"
        case .comprehensive: return "1.2.840.10008.5.1.4.1.1.88.33"
        case .comprehensive3D: return "1.2.840.10008.5.1.4.1.1.88.34"
        case .measurementReport: return "1.2.840.10008.5.1.4.1.1.88.22"
        case .keyObjectSelection: return "1.2.840.10008.5.1.4.1.1.88.59"
        case .mammographyCAD: return "1.2.840.10008.5.1.4.1.1.88.50"
        case .chestCAD: return "1.2.840.10008.5.1.4.1.1.88.65"
        }
    }
}

// MARK: - Content Item Value Type

/// All 15 DICOM SR content item value types per PS3.3 Table C.17.3-7.
public enum ContentItemValueType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Container — groups child items.
    case container = "CONTAINER"
    /// Text — free-text string value.
    case text = "TEXT"
    /// Code — coded concept value.
    case code = "CODE"
    /// Numeric — numeric measurement with units.
    case numeric = "NUM"
    /// Date — calendar date.
    case date = "DATE"
    /// Time — time of day.
    case time = "TIME"
    /// DateTime — combined date and time.
    case dateTime = "DATETIME"
    /// Person Name — DICOM PN value.
    case personName = "PNAME"
    /// UID Reference — unique identifier.
    case uidRef = "UIDREF"
    /// Spatial Coordinates — 2D coordinates in an image.
    case spatialCoord = "SCOORD"
    /// Spatial Coordinates 3D — 3D coordinates in a frame of reference.
    case spatialCoord3D = "SCOORD3D"
    /// Temporal Coordinates — time/frame references.
    case temporalCoord = "TCOORD"
    /// Composite — reference to a composite SOP instance.
    case composite = "COMPOSITE"
    /// Image — reference to an image SOP instance.
    case image = "IMAGE"
    /// Waveform — reference to a waveform SOP instance.
    case waveform = "WAVEFORM"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .container: return "Container"
        case .text: return "Text"
        case .code: return "Code"
        case .numeric: return "Numeric"
        case .date: return "Date"
        case .time: return "Time"
        case .dateTime: return "DateTime"
        case .personName: return "Person Name"
        case .uidRef: return "UID Reference"
        case .spatialCoord: return "Spatial Coordinates"
        case .spatialCoord3D: return "Spatial Coordinates 3D"
        case .temporalCoord: return "Temporal Coordinates"
        case .composite: return "Composite"
        case .image: return "Image"
        case .waveform: return "Waveform"
        }
    }
}

// MARK: - Relationship Type

/// DICOM SR relationship types per PS3.3 Table C.17.3-8.
public enum SRRelationshipType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Contains child items.
    case contains = "CONTAINS"
    /// Has observation context.
    case hasObsContext = "HAS OBS CONTEXT"
    /// Has acquisition context.
    case hasAcqContext = "HAS ACQ CONTEXT"
    /// Has concept modifier.
    case hasConceptMod = "HAS CONCEPT MOD"
    /// Has properties.
    case hasProperties = "HAS PROPERTIES"
    /// Inferred from.
    case inferredFrom = "INFERRED FROM"
    /// Selected from.
    case selectedFrom = "SELECTED FROM"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .contains: return "Contains"
        case .hasObsContext: return "Has Observation Context"
        case .hasAcqContext: return "Has Acquisition Context"
        case .hasConceptMod: return "Has Concept Modifier"
        case .hasProperties: return "Has Properties"
        case .inferredFrom: return "Inferred From"
        case .selectedFrom: return "Selected From"
        }
    }
}

// MARK: - Continuity of Content

/// Continuity flag for container items per PS3.3 C.17.3.2.
public enum ContinuityOfContent: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Separate — items are independent.
    case separate = "SEPARATE"
    /// Continuous — items form a continuous narrative.
    case continuous = "CONTINUOUS"
}

// MARK: - Coding Scheme Designator

/// Common coding scheme designators used in DICOM SR.
public enum CodingSchemeDesignator: String, Sendable, Equatable, Hashable, CaseIterable {
    /// SNOMED CT — Systematized Nomenclature of Medicine Clinical Terms.
    case snomedCT = "SCT"
    /// LOINC — Logical Observation Identifiers Names and Codes.
    case loinc = "LN"
    /// RadLex — Radiology Lexicon.
    case radlex = "RADLEX"
    /// UCUM — Unified Code for Units of Measure.
    case ucum = "UCUM"
    /// DICOM Controlled Terminology.
    case dcm = "DCM"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .snomedCT: return "SNOMED CT"
        case .loinc: return "LOINC"
        case .radlex: return "RadLex"
        case .ucum: return "UCUM"
        case .dcm: return "DICOM Controlled Terminology"
        }
    }
}

// MARK: - Coded Concept

/// A coded concept from a coding scheme (code value + meaning + scheme).
public struct CodedConcept: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier for this concept.
    public let id: UUID
    /// Code value (e.g., "410668003").
    public let codeValue: String
    /// Coding scheme designator (e.g., "SCT", "LN").
    public let codingSchemeDesignator: String
    /// Human-readable code meaning.
    public let codeMeaning: String
    /// Optional coding scheme version.
    public let codingSchemeVersion: String?

    public init(
        id: UUID = UUID(),
        codeValue: String,
        codingSchemeDesignator: String,
        codeMeaning: String,
        codingSchemeVersion: String? = nil
    ) {
        self.id = id
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
        self.codingSchemeVersion = codingSchemeVersion
    }

    /// Returns a new concept with a different meaning.
    public func withMeaning(_ meaning: String) -> CodedConcept {
        CodedConcept(
            id: id,
            codeValue: codeValue,
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: meaning,
            codingSchemeVersion: codingSchemeVersion
        )
    }
}

// MARK: - Spatial Coordinate Type

/// Graphic type for 2D spatial coordinates per PS3.3 C.18.6.
///
/// PS3.3 2026a C.18.6.1.2 enumerates POINT, MULTIPOINT, POLYLINE, CIRCLE and ELLIPSE; `polygon`
/// is a 3D SCOORD3D term only (C.18.9.1.2) and is kept for source compatibility (P-STUDIO-SCOORD-POLYGON).
public enum SpatialCoordGraphicType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Single point.
    case point = "POINT"
    /// Multiple points forming a polyline.
    case polyline = "POLYLINE"
    /// Circle defined by center and edge point.
    case circle = "CIRCLE"
    /// Ellipse defined by four points.
    case ellipse = "ELLIPSE"
    /// Closed polygon.
    case polygon = "POLYGON"
    /// Multiple individual points.
    case multipoint = "MULTIPOINT"
}

// MARK: - 3D Spatial Coordinate Type

/// Graphic type for 3D spatial coordinates per PS3.3 C.18.9.
public enum SpatialCoord3DGraphicType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Single 3D point.
    case point = "POINT"
    /// 3D polyline.
    case polyline = "POLYLINE"
    /// 3D polygon.
    case polygon = "POLYGON"
    /// 3D ellipse.
    case ellipse = "ELLIPSE"
    /// 3D ellipsoid.
    case ellipsoid = "ELLIPSOID"
    /// Multiple 3D points.
    case multipoint = "MULTIPOINT"
}

// MARK: - Temporal Coordinate Range Type

/// Range type for temporal coordinates per PS3.3 C.18.7.
public enum TemporalRangeType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Single point in time.
    case point = "POINT"
    /// Multiple time points.
    case multipoint = "MULTIPOINT"
    /// Segment of time.
    case segment = "SEGMENT"
    /// Multiple segments.
    case multisegment = "MULTISEGMENT"
    /// Beginning of a range.
    case begin = "BEGIN"
    /// End of a range.
    case end = "END"
}

// MARK: - SR Content Item

/// A single content item in an SR document tree.
public struct SRContentItem: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier.
    public let id: UUID
    /// Value type of this content item.
    public let valueType: ContentItemValueType
    /// Concept name (coded concept describing this item).
    public let conceptName: CodedConcept?
    /// Relationship type to parent item.
    public let relationshipType: SRRelationshipType
    /// Text value (for TEXT items).
    public let textValue: String?
    /// Code value (for CODE items).
    public let codeValue: CodedConcept?
    /// Numeric value (for NUM items).
    public let numericValue: Double?
    /// Measurement unit (for NUM items, UCUM code).
    public let measurementUnit: CodedConcept?
    /// Date value (for DATE items).
    public let dateValue: String?
    /// Time value (for TIME items).
    public let timeValue: String?
    /// DateTime value (for DATETIME items).
    public let dateTimeValue: String?
    /// Person name (for PNAME items).
    public let personName: String?
    /// UID value (for UIDREF items).
    public let uidValue: String?
    /// Graphic type for 2D spatial coordinates.
    public let graphicType: SpatialCoordGraphicType?
    /// 2D coordinate data (pairs of x,y).
    public let graphicData: [Double]?
    /// Graphic type for 3D spatial coordinates.
    public let graphicType3D: SpatialCoord3DGraphicType?
    /// 3D coordinate data (triples of x,y,z).
    public let graphicData3D: [Double]?
    /// Temporal range type.
    public let temporalRangeType: TemporalRangeType?
    /// Referenced SOP Class UID.
    public let referencedSOPClassUID: String?
    /// Referenced SOP Instance UID.
    public let referencedSOPInstanceUID: String?
    /// Referenced frame numbers.
    public let referencedFrameNumbers: [Int]?
    /// Continuity of content (for CONTAINER items).
    public let continuityOfContent: ContinuityOfContent?
    /// Child content items.
    public let children: [SRContentItem]
    /// Whether this node is expanded in the tree view.
    public let isExpanded: Bool

    public init(
        id: UUID = UUID(),
        valueType: ContentItemValueType,
        conceptName: CodedConcept? = nil,
        relationshipType: SRRelationshipType = .contains,
        textValue: String? = nil,
        codeValue: CodedConcept? = nil,
        numericValue: Double? = nil,
        measurementUnit: CodedConcept? = nil,
        dateValue: String? = nil,
        timeValue: String? = nil,
        dateTimeValue: String? = nil,
        personName: String? = nil,
        uidValue: String? = nil,
        graphicType: SpatialCoordGraphicType? = nil,
        graphicData: [Double]? = nil,
        graphicType3D: SpatialCoord3DGraphicType? = nil,
        graphicData3D: [Double]? = nil,
        temporalRangeType: TemporalRangeType? = nil,
        referencedSOPClassUID: String? = nil,
        referencedSOPInstanceUID: String? = nil,
        referencedFrameNumbers: [Int]? = nil,
        continuityOfContent: ContinuityOfContent? = nil,
        children: [SRContentItem] = [],
        isExpanded: Bool = true
    ) {
        self.id = id
        self.valueType = valueType
        self.conceptName = conceptName
        self.relationshipType = relationshipType
        self.textValue = textValue
        self.codeValue = codeValue
        self.numericValue = numericValue
        self.measurementUnit = measurementUnit
        self.dateValue = dateValue
        self.timeValue = timeValue
        self.dateTimeValue = dateTimeValue
        self.personName = personName
        self.uidValue = uidValue
        self.graphicType = graphicType
        self.graphicData = graphicData
        self.graphicType3D = graphicType3D
        self.graphicData3D = graphicData3D
        self.temporalRangeType = temporalRangeType
        self.referencedSOPClassUID = referencedSOPClassUID
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
        self.referencedFrameNumbers = referencedFrameNumbers
        self.continuityOfContent = continuityOfContent
        self.children = children
        self.isExpanded = isExpanded
    }

    /// Returns a copy with toggled expansion state.
    public func withExpanded(_ expanded: Bool) -> SRContentItem {
        SRContentItem(
            id: id, valueType: valueType, conceptName: conceptName,
            relationshipType: relationshipType, textValue: textValue,
            codeValue: codeValue, numericValue: numericValue,
            measurementUnit: measurementUnit, dateValue: dateValue,
            timeValue: timeValue, dateTimeValue: dateTimeValue,
            personName: personName, uidValue: uidValue,
            graphicType: graphicType, graphicData: graphicData,
            graphicType3D: graphicType3D, graphicData3D: graphicData3D,
            temporalRangeType: temporalRangeType,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers,
            continuityOfContent: continuityOfContent,
            children: children, isExpanded: expanded
        )
    }

    /// Returns a copy with new children.
    public func withChildren(_ newChildren: [SRContentItem]) -> SRContentItem {
        SRContentItem(
            id: id, valueType: valueType, conceptName: conceptName,
            relationshipType: relationshipType, textValue: textValue,
            codeValue: codeValue, numericValue: numericValue,
            measurementUnit: measurementUnit, dateValue: dateValue,
            timeValue: timeValue, dateTimeValue: dateTimeValue,
            personName: personName, uidValue: uidValue,
            graphicType: graphicType, graphicData: graphicData,
            graphicType3D: graphicType3D, graphicData3D: graphicData3D,
            temporalRangeType: temporalRangeType,
            referencedSOPClassUID: referencedSOPClassUID,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumbers: referencedFrameNumbers,
            continuityOfContent: continuityOfContent,
            children: newChildren, isExpanded: isExpanded
        )
    }

    /// Total number of items in this subtree (including self).
    public var totalItemCount: Int {
        1 + children.reduce(0) { $0 + $1.totalItemCount }
    }

    /// Whether this item has child items.
    public var hasChildren: Bool {
        !children.isEmpty
    }
}

// MARK: - SR Document

/// A complete DICOM SR document.
public struct SRDocument: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier.
    public let id: UUID
    /// Document type.
    public let documentType: SRDocumentType
    /// Document title (coded concept).
    public let title: CodedConcept
    /// Patient name.
    public let patientName: String
    /// Patient ID.
    public let patientID: String
    /// Study instance UID.
    public let studyInstanceUID: String
    /// Series instance UID.
    public let seriesInstanceUID: String
    /// SOP instance UID.
    public let sopInstanceUID: String
    /// Content date.
    public let contentDate: String
    /// Content time.
    public let contentTime: String
    /// Root content item (tree root).
    public let rootContentItem: SRContentItem
    /// Completion flag.
    public let isComplete: Bool
    /// Verification flag.
    public let isVerified: Bool

    public init(
        id: UUID = UUID(),
        documentType: SRDocumentType,
        title: CodedConcept,
        patientName: String = "",
        patientID: String = "",
        studyInstanceUID: String = "",
        seriesInstanceUID: String = "",
        sopInstanceUID: String = "",
        contentDate: String = "",
        contentTime: String = "",
        rootContentItem: SRContentItem = SRContentItem(valueType: .container, continuityOfContent: .separate, children: []),
        isComplete: Bool = false,
        isVerified: Bool = false
    ) {
        self.id = id
        self.documentType = documentType
        self.title = title
        self.patientName = patientName
        self.patientID = patientID
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.sopInstanceUID = sopInstanceUID
        self.contentDate = contentDate
        self.contentTime = contentTime
        self.rootContentItem = rootContentItem
        self.isComplete = isComplete
        self.isVerified = isVerified
    }

    /// Returns a copy with a new root content item.
    public func withRootContentItem(_ item: SRContentItem) -> SRDocument {
        SRDocument(
            id: id, documentType: documentType, title: title,
            patientName: patientName, patientID: patientID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            sopInstanceUID: sopInstanceUID,
            contentDate: contentDate, contentTime: contentTime,
            rootContentItem: item,
            isComplete: isComplete, isVerified: isVerified
        )
    }

    /// Returns a copy marked as complete.
    public func withComplete(_ complete: Bool) -> SRDocument {
        SRDocument(
            id: id, documentType: documentType, title: title,
            patientName: patientName, patientID: patientID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            sopInstanceUID: sopInstanceUID,
            contentDate: contentDate, contentTime: contentTime,
            rootContentItem: rootContentItem,
            isComplete: complete, isVerified: isVerified
        )
    }

    /// Returns a copy marked as verified.
    public func withVerified(_ verified: Bool) -> SRDocument {
        SRDocument(
            id: id, documentType: documentType, title: title,
            patientName: patientName, patientID: patientID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            sopInstanceUID: sopInstanceUID,
            contentDate: contentDate, contentTime: contentTime,
            rootContentItem: rootContentItem,
            isComplete: isComplete, isVerified: verified
        )
    }
}

// MARK: - SR Template

/// Templates for common SR document types.
public enum SRTemplate: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Radiology report (Findings, Impression, Recommendations).
    case radiologyReport = "RADIOLOGY_REPORT"
    /// Pathology report.
    case pathologyReport = "PATHOLOGY_REPORT"
    /// Procedure report.
    case procedureReport = "PROCEDURE_REPORT"
    /// Clinical findings.
    case clinicalFindings = "CLINICAL_FINDINGS"
    /// Discharge summary.
    case dischargeSummary = "DISCHARGE_SUMMARY"

    /// Display name.
    public var displayName: String {
        switch self {
        case .radiologyReport: return "Radiology Report"
        case .pathologyReport: return "Pathology Report"
        case .procedureReport: return "Procedure Report"
        case .clinicalFindings: return "Clinical Findings"
        case .dischargeSummary: return "Discharge Summary"
        }
    }

    /// Default section names for this template.
    public var sections: [String] {
        switch self {
        case .radiologyReport: return ["Findings", "Impression", "Recommendations"]
        case .pathologyReport: return ["Gross Description", "Microscopic Description", "Diagnosis"]
        case .procedureReport: return ["Indication", "Technique", "Findings", "Impression"]
        case .clinicalFindings: return ["History", "Examination", "Assessment", "Plan"]
        case .dischargeSummary: return ["Admission Diagnosis", "Hospital Course", "Discharge Instructions"]
        }
    }
}

// MARK: - Key Object Selection Purpose

/// Purpose of key object selection per PS3.16 CID 7010.
public enum KeyObjectPurpose: String, Sendable, Equatable, Hashable, CaseIterable {
    /// For teaching purposes.
    case teaching = "TEACHING"
    /// For quality control.
    case qualityControl = "QUALITY_CONTROL"
    /// For referral / second opinion.
    case referral = "REFERRAL"
    /// For clinical conference.
    case conference = "CONFERENCE"
    /// For research.
    case research = "RESEARCH"
    /// For report documentation.
    case documentation = "DOCUMENTATION"

    /// Display name.
    public var displayName: String {
        switch self {
        case .teaching: return "Teaching"
        case .qualityControl: return "Quality Control"
        case .referral: return "Referral"
        case .conference: return "Conference"
        case .research: return "Research"
        case .documentation: return "Documentation"
        }
    }
}

// MARK: - BI-RADS Assessment Category

/// BI-RADS assessment categories for mammography per PS3.16.
public enum BIRADSCategory: Int, Sendable, Equatable, Hashable, CaseIterable {
    /// Incomplete — Need additional imaging.
    case category0 = 0
    /// Negative.
    case category1 = 1
    /// Benign.
    case category2 = 2
    /// Probably benign.
    case category3 = 3
    /// Suspicious.
    case category4 = 4
    /// Highly suggestive of malignancy.
    case category5 = 5
    /// Known biopsy-proven malignancy.
    case category6 = 6

    /// Display name.
    public var displayName: String {
        switch self {
        case .category0: return "BI-RADS 0: Incomplete"
        case .category1: return "BI-RADS 1: Negative"
        case .category2: return "BI-RADS 2: Benign"
        case .category3: return "BI-RADS 3: Probably Benign"
        case .category4: return "BI-RADS 4: Suspicious"
        case .category5: return "BI-RADS 5: Highly Suggestive of Malignancy"
        case .category6: return "BI-RADS 6: Known Malignancy"
        }
    }
}

// MARK: - CAD Finding Type

/// Types of CAD (Computer-Aided Detection) findings.
public enum CADFindingType: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Mass detection.
    case mass = "MASS"
    /// Calcification cluster.
    case calcification = "CALCIFICATION"
    /// Architectural distortion.
    case architecturalDistortion = "ARCHITECTURAL_DISTORTION"
    /// Nodule (chest).
    case nodule = "NODULE"
    /// Consolidation (chest).
    case consolidation = "CONSOLIDATION"
    /// Lesion (generic).
    case lesion = "LESION"

    /// Display name.
    public var displayName: String {
        switch self {
        case .mass: return "Mass"
        case .calcification: return "Calcification"
        case .architecturalDistortion: return "Architectural Distortion"
        case .nodule: return "Nodule"
        case .consolidation: return "Consolidation"
        case .lesion: return "Lesion"
        }
    }

    /// SF Symbol name for this finding type.
    public var sfSymbolName: String {
        switch self {
        case .mass: return "circle.fill"
        case .calcification: return "sparkle"
        case .architecturalDistortion: return "waveform"
        case .nodule: return "circle.dashed"
        case .consolidation: return "cloud.fill"
        case .lesion: return "exclamationmark.triangle"
        }
    }
}

// MARK: - CAD Finding Status

/// Review status for a CAD finding.
public enum CADFindingStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Pending review.
    case pending = "PENDING"
    /// Accepted by reviewer.
    case accepted = "ACCEPTED"
    /// Rejected by reviewer.
    case rejected = "REJECTED"

    /// Display name.
    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .rejected: return "Rejected"
        }
    }
}

// MARK: - CAD Finding

/// A single CAD finding with location, confidence, and review status.
public struct CADFinding: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier.
    public let id: UUID
    /// Type of finding.
    public let findingType: CADFindingType
    /// Confidence score (0.0–1.0).
    public let confidence: Double
    /// Location description.
    public let locationDescription: String
    /// 2D coordinates in the image (pairs of x,y).
    public let coordinates: [Double]
    /// Referenced SOP Instance UID of the image.
    public let referencedSOPInstanceUID: String
    /// Referenced frame number (nil for single-frame).
    public let referencedFrameNumber: Int?
    /// BI-RADS assessment (mammography only).
    public let biradsCategory: BIRADSCategory?
    /// Review status.
    public let status: CADFindingStatus
    /// Coded attributes describing the finding.
    public let attributes: [CodedConcept]

    public init(
        id: UUID = UUID(),
        findingType: CADFindingType,
        confidence: Double,
        locationDescription: String = "",
        coordinates: [Double] = [],
        referencedSOPInstanceUID: String = "",
        referencedFrameNumber: Int? = nil,
        biradsCategory: BIRADSCategory? = nil,
        status: CADFindingStatus = .pending,
        attributes: [CodedConcept] = []
    ) {
        self.id = id
        self.findingType = findingType
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.locationDescription = locationDescription
        self.coordinates = coordinates
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
        self.referencedFrameNumber = referencedFrameNumber
        self.biradsCategory = biradsCategory
        self.status = status
        self.attributes = attributes
    }

    /// Returns a copy with a new status.
    public func withStatus(_ newStatus: CADFindingStatus) -> CADFinding {
        CADFinding(
            id: id, findingType: findingType, confidence: confidence,
            locationDescription: locationDescription,
            coordinates: coordinates,
            referencedSOPInstanceUID: referencedSOPInstanceUID,
            referencedFrameNumber: referencedFrameNumber,
            biradsCategory: biradsCategory,
            status: newStatus, attributes: attributes
        )
    }

    /// Confidence as a percentage string.
    public var confidencePercentage: String {
        let pct = Int(confidence * 100)
        return "\(pct)%"
    }
}

// MARK: - Terminology Entry

/// An entry in a coded terminology (SNOMED CT, LOINC, RadLex, UCUM).
public struct TerminologyEntry: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier.
    public let id: UUID
    /// Coded concept.
    public let concept: CodedConcept
    /// Category / parent concept.
    public let category: String
    /// Whether this entry is a favorite.
    public let isFavorite: Bool
    /// Last used timestamp (ISO 8601 string or empty).
    public let lastUsed: String

    public init(
        id: UUID = UUID(),
        concept: CodedConcept,
        category: String = "",
        isFavorite: Bool = false,
        lastUsed: String = ""
    ) {
        self.id = id
        self.concept = concept
        self.category = category
        self.isFavorite = isFavorite
        self.lastUsed = lastUsed
    }

    /// Returns a copy with toggled favorite state.
    public func withFavorite(_ favorite: Bool) -> TerminologyEntry {
        TerminologyEntry(
            id: id, concept: concept, category: category,
            isFavorite: favorite, lastUsed: lastUsed
        )
    }

    /// Returns a copy with updated last used.
    public func withLastUsed(_ timestamp: String) -> TerminologyEntry {
        TerminologyEntry(
            id: id, concept: concept, category: category,
            isFavorite: isFavorite, lastUsed: timestamp
        )
    }
}

// MARK: - Measurement Tracking

/// Lesion tracking method for Measurement Report (TID 1500).
public enum LesionTrackingMethod: String, Sendable, Equatable, Hashable, CaseIterable {
    /// RECIST 1.1 criteria.
    case recist = "RECIST"
    /// WHO criteria.
    case who = "WHO"
    /// Volume-based tracking.
    case volumetric = "VOLUMETRIC"
    /// Diameter-based tracking.
    case diameter = "DIAMETER"

    /// Display name.
    public var displayName: String {
        switch self {
        case .recist: return "RECIST 1.1"
        case .who: return "WHO"
        case .volumetric: return "Volumetric"
        case .diameter: return "Diameter"
        }
    }
}

// MARK: - Measurement Time Point

/// Time point for lesion tracking comparison.
public enum MeasurementTimePoint: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Baseline measurement.
    case baseline = "BASELINE"
    /// Follow-up measurement.
    case followUp = "FOLLOW_UP"
    /// Final measurement.
    case final_ = "FINAL"

    /// Display name.
    public var displayName: String {
        switch self {
        case .baseline: return "Baseline"
        case .followUp: return "Follow-Up"
        case .final_: return "Final"
        }
    }
}

// MARK: - Tracked Measurement

/// A tracked measurement with identifier and time point.
public struct TrackedMeasurement: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier.
    public let id: UUID
    /// Tracking identifier string.
    public let trackingIdentifier: String
    /// Tracking unique identifier.
    public let trackingUID: String
    /// Measurement value.
    public let value: Double
    /// Measurement unit (UCUM).
    public let unit: CodedConcept
    /// Time point.
    public let timePoint: MeasurementTimePoint
    /// Tracking method.
    public let trackingMethod: LesionTrackingMethod
    /// Finding site (coded).
    public let findingSite: CodedConcept?

    public init(
        id: UUID = UUID(),
        trackingIdentifier: String,
        trackingUID: String = "",
        value: Double,
        unit: CodedConcept,
        timePoint: MeasurementTimePoint = .baseline,
        trackingMethod: LesionTrackingMethod = .recist,
        findingSite: CodedConcept? = nil
    ) {
        self.id = id
        self.trackingIdentifier = trackingIdentifier
        self.trackingUID = trackingUID
        self.value = value
        self.unit = unit
        self.timePoint = timePoint
        self.trackingMethod = trackingMethod
        self.findingSite = findingSite
    }

    /// Returns a copy with updated value.
    public func withValue(_ newValue: Double) -> TrackedMeasurement {
        TrackedMeasurement(
            id: id, trackingIdentifier: trackingIdentifier,
            trackingUID: trackingUID, value: newValue,
            unit: unit, timePoint: timePoint,
            trackingMethod: trackingMethod,
            findingSite: findingSite
        )
    }
}

// MARK: - SR Viewer State

/// State for the SR document viewer.
public enum SRViewerMode: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Tree view of content items.
    case tree = "TREE"
    /// Flat list view.
    case list = "LIST"
    /// Document narrative view.
    case narrative = "NARRATIVE"
}

// MARK: - SR Builder State

/// State for the SR document builder.
public enum SRBuilderMode: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Template-based building.
    case template = "TEMPLATE"
    /// Free-form building.
    case freeForm = "FREE_FORM"
    /// Import from existing SR.
    case importExisting = "IMPORT"
}

// MARK: - Terminology Search Scope

/// Scope for terminology search.
public enum TerminologySearchScope: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Search all terminologies.
    case all = "ALL"
    /// Search only SNOMED CT.
    case snomedCT = "SCT"
    /// Search only LOINC.
    case loinc = "LN"
    /// Search only RadLex.
    case radlex = "RADLEX"
    /// Search only UCUM.
    case ucum = "UCUM"

    /// Display name.
    public var displayName: String {
        switch self {
        case .all: return "All Terminologies"
        case .snomedCT: return "SNOMED CT"
        case .loinc: return "LOINC"
        case .radlex: return "RadLex"
        case .ucum: return "UCUM"
        }
    }
}
