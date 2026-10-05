// SRBuilderHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent SR document builder helpers
// Reference: DICOM PS3.16 (Content Mapping Resources), TID 1500, TID 1501, TID 2000, TID 2010
// NEMA-verified: 2026a, checked 2026-10-05 — the 13 coded concepts diffed by script against PS3.16 2026a Table D-1 and the CID tables (7003, 7010, 7021, 7181, 7461, 7470, 9000): 7 matched, 6 corrected ((G-C0E3, SRT) -> (363698007, SCT, "Finding Site") per Table O-1 / TID 1501 row 6; 121200 is "Illustration of ROI"; 113000 is "Of Interest"; mm2 "square millimeter" (CID 7461); [hnsf'U] "Hounsfield unit" (CID 83); 1 "no units" (CID 7181)); (ml, UCUM) is in no CID table, its meaning is UCUM's print name (not verifiable from NEMA text); retired (121070, DCM, "Findings") no longer used as a title/heading with an arbitrary meaning — titles come from CID 7000 / 7021 / 7010 / TID 4000 / TID 4100, section headings from CID 7001, with a 99DCMSTUDIO private code (PS3.16 Section 8) for headings the standard has no code for; TID 1500 rows 1, 6 and TID 1501 rows 2, 3, 6 and TID 2010 rows 1, 7, 8 (IMAGE without a concept name) followed

import Foundation

/// Platform-independent helpers for building DICOM SR documents.
///
/// Provides template generation, content item construction, and validation
/// for all 8 SR document types.
public enum SRBuilderHelpers: Sendable {

    // MARK: - Common Coded Concepts

    /// Coded concept for a measurement group (TID 1500).
    public static let measurementGroupConcept = CodedConcept(
        codeValue: "125007", codingSchemeDesignator: "DCM",
        codeMeaning: "Measurement Group"
    )

    /// Coded concept for tracking identifier.
    public static let trackingIdentifierConcept = CodedConcept(
        codeValue: "112039", codingSchemeDesignator: "DCM",
        codeMeaning: "Tracking Identifier"
    )

    /// Coded concept for tracking unique identifier.
    public static let trackingUIDConcept = CodedConcept(
        codeValue: "112040", codingSchemeDesignator: "DCM",
        codeMeaning: "Tracking Unique Identifier"
    )

    /// Coded concept for finding.
    public static let findingConcept = CodedConcept(
        codeValue: "121071", codingSchemeDesignator: "DCM",
        codeMeaning: "Finding"
    )

    /// Coded concept for finding site (TID 1501 row 6; PS3.16 2026a uses the SCT concept id,
    /// Table O-1 maps the SNOMED-RT id G-C0E3 to it).
    public static let findingSiteConcept = CodedConcept(
        codeValue: "363698007", codingSchemeDesignator: "SCT",
        codeMeaning: "Finding Site"
    )

    /// Purpose of reference for an image illustrating a region of interest
    /// (CID 7003, TID 1501 row 9c). The Table D-1 meaning of 121200 is "Illustration of ROI".
    public static let imageReferenceConcept = CodedConcept(
        codeValue: "121200", codingSchemeDesignator: "DCM",
        codeMeaning: "Illustration of ROI"
    )

    /// Default Key Object Selection document title: (113000, DCM, "Of Interest") from CID 7010
    /// (TID 2010 row 1). `keyObjectTitle(for:)` picks the CID 7010 title that matches a purpose.
    public static let keyObjectSelectionTitle = CodedConcept(
        codeValue: "113000", codingSchemeDesignator: "DCM",
        codeMeaning: "Of Interest"
    )

    // MARK: - UCUM Unit Concepts

    /// UCUM millimeter unit.
    public static let ucumMillimeter = CodedConcept(
        codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm"
    )

    /// UCUM centimeter unit.
    public static let ucumCentimeter = CodedConcept(
        codeValue: "cm", codingSchemeDesignator: "UCUM", codeMeaning: "cm"
    )

    /// UCUM square millimeter unit (CID 7461).
    public static let ucumSquareMillimeter = CodedConcept(
        codeValue: "mm2", codingSchemeDesignator: "UCUM", codeMeaning: "square millimeter"
    )

    /// UCUM milliliter unit. PS3.16 lists no `ml` in a volume context group (CID 7462 uses cm3);
    /// the meaning is UCUM's print name.
    public static let ucumMilliliter = CodedConcept(
        codeValue: "ml", codingSchemeDesignator: "UCUM", codeMeaning: "milliliter"
    )

    /// UCUM Hounsfield unit (CID 83).
    public static let ucumHounsfieldUnit = CodedConcept(
        codeValue: "[hnsf'U]", codingSchemeDesignator: "UCUM", codeMeaning: "Hounsfield unit"
    )

    /// UCUM no units (dimensionless; CID 7181). `{ratio}` is a separate UCUM code with the meaning "ratio".
    public static let ucumNoUnits = CodedConcept(
        codeValue: "1", codingSchemeDesignator: "UCUM", codeMeaning: "no units"
    )

    // MARK: - Document Titles and Section Headings (PS3.16 CID 7000 / 7001 / 7010 / 7021)

    /// Private coding scheme designator (PS3.16 Section 8: "99" prefix) for the app's own section
    /// headings that PS3.16 has no code for.
    static let privateCodingScheme = "99DCMSTUDIO"

    /// Document title for a report template: CID 7000 where the standard has a matching title,
    /// otherwise a private code carrying the template name.
    static func documentTitle(for template: SRTemplate) -> CodedConcept {
        switch template {
        case .radiologyReport:
            return CodedConcept(codeValue: "11528-7", codingSchemeDesignator: "LN", codeMeaning: "Radiology Report")
        case .procedureReport, .pathologyReport, .clinicalFindings, .dischargeSummary:
            return CodedConcept(codeValue: template.rawValue, codingSchemeDesignator: privateCodingScheme,
                                codeMeaning: template.displayName)
        }
    }

    /// Document title for an SR document type: the root concept name its template prescribes
    /// (TID 2000 BCID 7000, TID 1500 DCID 7021, TID 2010 DCID 7010, TID 4000 / TID 4100 row 1).
    static func documentTitle(for documentType: SRDocumentType, template: SRTemplate? = nil) -> CodedConcept {
        switch documentType {
        case .basicText, .enhanced, .comprehensive, .comprehensive3D:
            if let template { return documentTitle(for: template) }
            return CodedConcept(codeValue: "18748-4", codingSchemeDesignator: "LN", codeMeaning: "Diagnostic Imaging Report")
        case .measurementReport:
            return CodedConcept(codeValue: "126000", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurement Report")
        case .keyObjectSelection:
            return keyObjectSelectionTitle
        case .mammographyCAD:
            return CodedConcept(codeValue: "111036", codingSchemeDesignator: "DCM", codeMeaning: "Mammography CAD Report")
        case .chestCAD:
            return CodedConcept(codeValue: "112000", codingSchemeDesignator: "DCM", codeMeaning: "Chest CAD Report")
        }
    }

    /// CID 7001 "Diagnostic Imaging Report Heading" codes for the template section names.
    private static let sectionHeadingCodes: [String: (String, String)] = [
        "findings": ("59776-5", "Findings"),
        "impression": ("19005-8", "Impressions"),
        "impressions": ("19005-8", "Impressions"),
        "recommendations": ("18783-1", "Recommendations"),
        "history": ("11329-0", "History"),
        "indication": ("18785-6", "Indications for Procedure"),
        "indications": ("18785-6", "Indications for Procedure"),
        "summary": ("55112-7", "Summary"),
        "conclusions": ("55110-1", "Conclusions"),
        "addendum": ("55107-7", "Addendum"),
        "complications": ("55109-3", "Complications"),
        "key images": ("55113-5", "Key Images"),
        "request": ("55115-0", "Request"),
    ]

    /// Section heading concept: the CID 7001 code when the standard has one for the heading,
    /// otherwise a private code carrying the heading text.
    static func sectionHeading(for sectionName: String) -> CodedConcept {
        if let (code, meaning) = sectionHeadingCodes[sectionName.lowercased()] {
            return CodedConcept(codeValue: code, codingSchemeDesignator: "LN", codeMeaning: meaning)
        }
        let code = sectionName.uppercased().replacingOccurrences(of: " ", with: "_")
        return CodedConcept(codeValue: code, codingSchemeDesignator: privateCodingScheme, codeMeaning: sectionName)
    }

    /// CID 7010 Key Object Selection Document Title for a selection purpose.
    static func keyObjectTitle(for purpose: KeyObjectPurpose) -> CodedConcept {
        switch purpose {
        case .teaching:       return CodedConcept(codeValue: "113004", codingSchemeDesignator: "DCM", codeMeaning: "For Teaching")
        case .qualityControl: return CodedConcept(codeValue: "113010", codingSchemeDesignator: "DCM", codeMeaning: "Quality Issue")
        case .referral:       return CodedConcept(codeValue: "113002", codingSchemeDesignator: "DCM", codeMeaning: "For Referring Provider")
        case .conference:     return CodedConcept(codeValue: "113005", codingSchemeDesignator: "DCM", codeMeaning: "For Conference")
        case .research:       return CodedConcept(codeValue: "113009", codingSchemeDesignator: "DCM", codeMeaning: "For Research")
        case .documentation:  return keyObjectSelectionTitle
        }
    }

    // MARK: - Content Item Builders

    /// Creates a container content item.
    public static func containerItem(
        conceptName: CodedConcept,
        relationship: SRRelationshipType = .contains,
        continuity: ContinuityOfContent = .separate,
        children: [SRContentItem] = []
    ) -> SRContentItem {
        SRContentItem(
            valueType: .container,
            conceptName: conceptName,
            relationshipType: relationship,
            continuityOfContent: continuity,
            children: children
        )
    }

    /// Creates a text content item.
    public static func textItem(
        conceptName: CodedConcept,
        text: String,
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .text,
            conceptName: conceptName,
            relationshipType: relationship,
            textValue: text
        )
    }

    /// Creates a code content item.
    public static func codeItem(
        conceptName: CodedConcept,
        code: CodedConcept,
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .code,
            conceptName: conceptName,
            relationshipType: relationship,
            codeValue: code
        )
    }

    /// Creates a numeric content item with UCUM units.
    public static func numericItem(
        conceptName: CodedConcept,
        value: Double,
        unit: CodedConcept,
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .numeric,
            conceptName: conceptName,
            relationshipType: relationship,
            numericValue: value,
            measurementUnit: unit
        )
    }

    /// Creates a person name content item.
    public static func personNameItem(
        conceptName: CodedConcept,
        name: String,
        relationship: SRRelationshipType = .hasObsContext
    ) -> SRContentItem {
        SRContentItem(
            valueType: .personName,
            conceptName: conceptName,
            relationshipType: relationship,
            personName: name
        )
    }

    /// Creates a date content item.
    public static func dateItem(
        conceptName: CodedConcept,
        date: String,
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .date,
            conceptName: conceptName,
            relationshipType: relationship,
            dateValue: date
        )
    }

    /// Creates a UID reference content item.
    public static func uidRefItem(
        conceptName: CodedConcept,
        uid: String,
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .uidRef,
            conceptName: conceptName,
            relationshipType: relationship,
            uidValue: uid
        )
    }

    /// Creates an image reference content item.
    public static func imageItem(
        conceptName: CodedConcept,
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil,
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .image,
            conceptName: conceptName,
            relationshipType: relationship,
            referencedSOPClassUID: sopClassUID,
            referencedSOPInstanceUID: sopInstanceUID,
            referencedFrameNumbers: frameNumbers
        )
    }

    /// Creates a 2D spatial coordinate content item.
    public static func spatialCoordItem(
        conceptName: CodedConcept,
        graphicType: SpatialCoordGraphicType,
        graphicData: [Double],
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .spatialCoord,
            conceptName: conceptName,
            relationshipType: relationship,
            graphicType: graphicType,
            graphicData: graphicData
        )
    }

    /// Creates a 3D spatial coordinate content item.
    public static func spatialCoord3DItem(
        conceptName: CodedConcept,
        graphicType: SpatialCoord3DGraphicType,
        graphicData: [Double],
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        SRContentItem(
            valueType: .spatialCoord3D,
            conceptName: conceptName,
            relationshipType: relationship,
            graphicType3D: graphicType,
            graphicData3D: graphicData
        )
    }

    // MARK: - Template Builders

    /// Builds a Basic Text SR document from a template (TID 2000 layout: a titled CONTAINER from
    /// CID 7000 holding one CONTAINER per section heading from CID 7001).
    ///
    /// - Parameters:
    ///   - template: The report template.
    ///   - sectionTexts: Text for each section (keyed by section name).
    /// - Returns: Root content item with template sections.
    public static func buildBasicTextSR(
        template: SRTemplate,
        sectionTexts: [String: String] = [:]
    ) -> SRContentItem {
        let titleConcept = documentTitle(for: template)
        let sections = template.sections.map { sectionName in
            let sectionConcept = sectionHeading(for: sectionName)
            let text = sectionTexts[sectionName] ?? ""
            let textChild = textItem(
                conceptName: sectionConcept,
                text: text
            )
            return containerItem(
                conceptName: sectionConcept,
                continuity: .separate,
                children: text.isEmpty ? [] : [textChild]
            )
        }
        return containerItem(
            conceptName: titleConcept,
            continuity: .separate,
            children: sections
        )
    }

    /// Builds a Key Object Selection document (TID 2010: the title is the CID 7010 code for the
    /// purpose, row 7 is the Key Object Description TEXT, rows 8 are IMAGE items without a
    /// concept name).
    ///
    /// - Parameters:
    ///   - purpose: The selection purpose.
    ///   - description: Description text.
    ///   - imageReferences: Array of (sopClassUID, sopInstanceUID) pairs.
    /// - Returns: Root content item for Key Object Selection.
    public static func buildKeyObjectSelection(
        purpose: KeyObjectPurpose,
        description: String,
        imageReferences: [(String, String)] = []
    ) -> SRContentItem {
        var children: [SRContentItem] = []

        let purposeConcept = CodedConcept(
            codeValue: "113012", codingSchemeDesignator: "DCM",
            codeMeaning: "Key Object Description"
        )
        children.append(textItem(conceptName: purposeConcept, text: description))

        for (classUID, instanceUID) in imageReferences {
            children.append(SRContentItem(
                valueType: .image,
                conceptName: nil,
                relationshipType: .contains,
                referencedSOPClassUID: classUID,
                referencedSOPInstanceUID: instanceUID
            ))
        }

        return containerItem(
            conceptName: keyObjectTitle(for: purpose),
            continuity: .separate,
            children: children
        )
    }

    /// Concept name of the TID 1500 row 6 CONTAINER that holds the measurement groups.
    public static let imagingMeasurementsConcept = CodedConcept(
        codeValue: "126010", codingSchemeDesignator: "DCM",
        codeMeaning: "Imaging Measurements"
    )

    /// Builds a Measurement Report root item (TID 1500 skeleton: row 1 title from CID 7021,
    /// row 6 "Imaging Measurements" CONTAINER holding one TID 1501 group per measurement).
    ///
    /// - Parameters:
    ///   - measurements: Tracked measurements to include.
    /// - Returns: Root content item for a measurement report.
    public static func buildMeasurementReport(
        measurements: [TrackedMeasurement] = []
    ) -> SRContentItem {
        let reportTitle = documentTitle(for: .measurementReport)
        var groups: [SRContentItem] = []
        for measurement in measurements {
            let group = buildMeasurementGroup(for: measurement)
            groups.append(group)
        }
        let imagingMeasurements = containerItem(
            conceptName: imagingMeasurementsConcept,
            continuity: .separate,
            children: groups
        )
        return containerItem(
            conceptName: reportTitle,
            continuity: .separate,
            children: groups.isEmpty ? [] : [imagingMeasurements]
        )
    }

    /// Builds a single measurement group for a tracked measurement (TID 1501 rows 1-3, 6 and a
    /// CID 7470 "Length" NUM).
    public static func buildMeasurementGroup(
        for measurement: TrackedMeasurement
    ) -> SRContentItem {
        var children: [SRContentItem] = []

        children.append(textItem(
            conceptName: trackingIdentifierConcept,
            text: measurement.trackingIdentifier,
            relationship: .hasObsContext
        ))

        if !measurement.trackingUID.isEmpty {
            children.append(uidRefItem(
                conceptName: trackingUIDConcept,
                uid: measurement.trackingUID,
                relationship: .hasObsContext
            ))
        }

        let measurementConcept = CodedConcept(
            codeValue: "410668003", codingSchemeDesignator: "SCT",
            codeMeaning: "Length"
        )
        children.append(numericItem(
            conceptName: measurementConcept,
            value: measurement.value,
            unit: measurement.unit
        ))

        if let site = measurement.findingSite {
            children.append(codeItem(
                conceptName: findingSiteConcept,
                code: site,
                relationship: .hasConceptMod
            ))
        }

        return containerItem(
            conceptName: measurementGroupConcept,
            continuity: .separate,
            children: children
        )
    }

    // MARK: - Validation

    /// Validates an SR document for completeness.
    ///
    /// - Parameter document: The SR document.
    /// - Returns: Array of validation error strings (empty if valid).
    public static func validateDocument(_ document: SRDocument) -> [String] {
        var errors: [String] = []

        if document.title.codeMeaning.isEmpty {
            errors.append("Document title is empty")
        }

        if document.rootContentItem.valueType != .container {
            errors.append("Root content item must be a CONTAINER")
        }

        if document.rootContentItem.children.isEmpty {
            errors.append("Document has no content items")
        }

        validateContentItems(document.rootContentItem, errors: &errors, path: "root")

        return errors
    }

    private static func validateContentItems(
        _ item: SRContentItem,
        errors: inout [String],
        path: String
    ) {
        switch item.valueType {
        case .text:
            if item.textValue == nil || item.textValue?.isEmpty == true {
                errors.append("Text item at \(path) has empty value")
            }
        case .code:
            if item.codeValue == nil {
                errors.append("Code item at \(path) has no coded value")
            }
        case .numeric:
            if item.numericValue == nil {
                errors.append("Numeric item at \(path) has no value")
            }
            if item.measurementUnit == nil {
                errors.append("Numeric item at \(path) has no unit")
            }
        case .personName:
            if item.personName == nil || item.personName?.isEmpty == true {
                errors.append("Person name item at \(path) has empty name")
            }
        case .image:
            if item.referencedSOPInstanceUID == nil || item.referencedSOPInstanceUID?.isEmpty == true {
                errors.append("Image item at \(path) has no referenced SOP Instance UID")
            }
        default:
            break
        }

        for (index, child) in item.children.enumerated() {
            validateContentItems(child, errors: &errors, path: "\(path)/\(index)")
        }
    }

    /// Returns the list of supported SR document types for a builder mode.
    ///
    /// - Parameter mode: The builder mode.
    /// - Returns: Array of supported document types.
    public static func supportedDocumentTypes(for mode: SRBuilderMode) -> [SRDocumentType] {
        switch mode {
        case .template:
            return [.basicText, .enhanced, .measurementReport, .keyObjectSelection]
        case .freeForm:
            return SRDocumentType.allCases
        case .importExisting:
            return SRDocumentType.allCases
        }
    }

    /// Returns the available templates for a document type.
    ///
    /// - Parameter documentType: The SR document type.
    /// - Returns: Array of available templates.
    public static func availableTemplates(for documentType: SRDocumentType) -> [SRTemplate] {
        switch documentType {
        case .basicText:
            return SRTemplate.allCases
        case .enhanced, .comprehensive, .comprehensive3D:
            return [.radiologyReport, .procedureReport]
        case .measurementReport:
            return [.radiologyReport]
        case .keyObjectSelection, .mammographyCAD, .chestCAD:
            return []
        }
    }
}
