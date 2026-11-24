// SRBuilderHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent SR document builder helpers
// Reference: DICOM PS3.16 (Content Mapping Resources), TID 1500, TID 1501, TID 2000, TID 2010
// NEMA-verified: 2026a, checked 2026-10-06 — the 13 coded concepts diffed by script against PS3.16 2026a Table D-1 and the CID tables (7003, 7010, 7021, 7181, 7461, 7470, 9000): 7 matched, 6 corrected ((G-C0E3, SRT) -> (363698007, SCT, "Finding Site") per Table O-1 / TID 1501 row 6; 121200 is "Illustration of ROI"; 113000 is "Of Interest"; mm2 "square millimeter" (CID 7461); [hnsf'U] "Hounsfield unit" (CID 83); 1 "no units" (CID 7181)); (ml, UCUM) is in no CID table, its meaning is UCUM's print name (not verifiable from NEMA text); retired (121070, DCM, "Findings") no longer used as a title/heading with an arbitrary meaning — titles come from CID 7000 / 7021 / 7010 / TID 4000 / TID 4100, section headings from CID 7001, with a 99DCMSTUDIO private code (PS3.16 Section 8) for headings the standard has no code for; TID 1500 rows 1, 6 and TID 1501 rows 2, 3, 6 and TID 2010 rows 1, 7, 8 (IMAGE without a concept name) followed; spatialCoordItem writes the deprecated POLYGON as a closed POLYLINE (first point = last point), the 2D Graphic Types being POINT, MULTIPOINT, POLYLINE, CIRCLE, ELLIPSE (PS3.3 2026a C.18.6.1.2, P-STUDIO-SCOORD-POLYGON)

import Foundation
import DICOMCore

/// Platform-independent helpers for building DICOM SR documents.
///
/// Delegates all coded concepts, UCUM measurement units, document titles, section headings,
/// Key Object Selection purposes, document type lists, and PS3.16 template lists to `DICOMCore`.
public enum SRBuilderHelpers: Sendable {

    // MARK: - Common Coded Concepts (Delegated to DICOMCore.SRClinicalCatalog)

    /// Coded concept for a measurement group (TID 1500 / TID 1501).
    public static let measurementGroupConcept = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.measurementGroupConcept
    )

    /// Coded concept for tracking identifier.
    public static let trackingIdentifierConcept = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.trackingIdentifierConcept
    )

    /// Coded concept for tracking unique identifier.
    public static let trackingUIDConcept = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.trackingUIDConcept
    )

    /// Coded concept for finding.
    public static let findingConcept = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.findingConcept
    )

    /// Coded concept for finding site (TID 1501 row 6).
    public static let findingSiteConcept = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.findingSiteConcept
    )

    /// Purpose of reference for an image illustrating a region of interest (CID 7003, TID 1501 row 9c).
    public static let imageReferenceConcept = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.imageReferenceConcept
    )

    /// Default Key Object Selection document title from CID 7010 (TID 2010 row 1).
    public static let keyObjectSelectionTitle = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.defaultKeyObjectSelectionTitle
    )

    // MARK: - UCUM Unit Concepts (Delegated to DICOMCore.SRClinicalCatalog)

    /// UCUM millimeter unit.
    public static let ucumMillimeter = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.ucumMillimeter
    )

    /// UCUM centimeter unit.
    public static let ucumCentimeter = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.ucumCentimeter
    )

    /// UCUM square millimeter unit (CID 7461).
    public static let ucumSquareMillimeter = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.ucumSquareMillimeter
    )

    /// UCUM milliliter unit.
    public static let ucumMilliliter = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.ucumMilliliter
    )

    /// UCUM Hounsfield unit (CID 83).
    public static let ucumHounsfieldUnit = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.ucumHounsfieldUnit
    )

    /// UCUM no units (dimensionless; CID 7181).
    public static let ucumNoUnits = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.ucumNoUnits
    )

    /// All standard measurement unit descriptors from `DICOMCore.SRClinicalCatalog.measurementUnits`.
    public static var availableMeasurementUnits: [DICOMCore.SRClinicalCatalog.MeasurementUnitDescriptor] {
        DICOMCore.SRClinicalCatalog.measurementUnits
    }

    // MARK: - Document Titles and Section Headings (Delegated to DICOMCore)

    /// Private coding scheme designator from `DICOMCore.SRClinicalCatalog`.
    static var privateCodingScheme: String {
        DICOMCore.SRClinicalCatalog.privateCodingScheme
    }

    /// Document title for a clinical report template preset from `DICOMCore`.
    static func documentTitle(for template: SRTemplate) -> CodedConcept {
        CodedConcept(coreConcept: template.corePreset.titleConcept)
    }

    /// Document title for a registered PS3.16 TID template from `DICOMCore.TemplateRegistry`.
    public static func documentTitle(for registeredTemplate: DICOMCore.SRRegisteredTemplateDescriptor) -> CodedConcept {
        CodedConcept(coreConcept: registeredTemplate.defaultDocumentTitle)
    }

    /// Document title for an SR document type, delegated to `DICOMCore`.
    static func documentTitle(
        for documentType: SRDocumentType,
        template: SRTemplate? = nil,
        registeredTemplate: DICOMCore.SRRegisteredTemplateDescriptor? = nil
    ) -> CodedConcept {
        if let registeredTemplate {
            return documentTitle(for: registeredTemplate)
        }
        if documentType == .measurementReport {
            let coreTitle = DICOMCore.ContextGroup.measurementReportDocumentTitles.members.first
                ?? DICOMCore.DICOMCode.imagingMeasurementReport.concept
            return CodedConcept(coreConcept: coreTitle)
        }
        if let template {
            return documentTitle(for: template)
        }
        return CodedConcept(coreConcept: documentType.coreDocumentType.defaultDocumentTitle)
    }

    /// Section heading concept delegated to `DICOMCore.SRClinicalCatalog.sectionHeadingConcept(for:)`.
    static func sectionHeading(for sectionName: String) -> CodedConcept {
        CodedConcept(coreConcept: DICOMCore.SRClinicalCatalog.sectionHeadingConcept(for: sectionName))
    }

    /// CID 7010 Key Object Selection Document Title for a selection purpose, delegated to `DICOMCore`.
    static func keyObjectTitle(for purpose: KeyObjectPurpose) -> CodedConcept {
        CodedConcept(coreConcept: purpose.coreDescriptor.titleConcept)
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
    ///
    /// The deprecated `SpatialCoordGraphicType.polygon` is written as POLYLINE with the first
    /// point repeated at the end when the data is not already closed: PS3.3 2026a C.18.6.1.2 has
    /// no POLYGON Graphic Type for SCOORD.
    public static func spatialCoordItem(
        conceptName: CodedConcept,
        graphicType: SpatialCoordGraphicType,
        graphicData: [Double],
        relationship: SRRelationshipType = .contains
    ) -> SRContentItem {
        var type = graphicType
        var data = graphicData
        if graphicType.rawValue == "POLYGON" {   // deprecated `.polygon`
            type = .polyline
            data = closedPolyline(graphicData)
        }
        return SRContentItem(
            valueType: .spatialCoord,
            conceptName: conceptName,
            relationshipType: relationship,
            graphicType: type,
            graphicData: data
        )
    }

    /// Returns 2D graphic data (x, y pairs) with the first point appended when the last point
    /// differs from it, so the POLYLINE is closed (PS3.3 2026a C.18.6.1.2).
    static func closedPolyline(_ data: [Double]) -> [Double] {
        guard data.count >= 4, data.count % 2 == 0 else { return data }
        let n = data.count
        if data[0] == data[n - 2] && data[1] == data[n - 1] { return data }
        return data + [data[0], data[1]]
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

    /// Builds an SR document root container from any registered PS3.16 TID template in `DICOMCore.TemplateRegistry`.
    public static func buildRegisteredTemplateSR(
        template: DICOMCore.SRRegisteredTemplateDescriptor,
        sectionTexts: [String: String] = [:]
    ) -> SRContentItem {
        let titleConcept = documentTitle(for: template)
        let sections = template.sectionConcepts.map { coreSection in
            let sectionConcept = CodedConcept(coreConcept: coreSection)
            let text = sectionTexts[coreSection.codeMeaning] ?? ""
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
            coreConcept: DICOMCore.SRClinicalCatalog.keyObjectDescriptionConcept
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

    /// Concept name of the TID 1500 row 6 CONTAINER that holds the measurement groups,
    /// delegated to `DICOMCore.SRClinicalCatalog.imagingMeasurementsConcept`.
    public static let imagingMeasurementsConcept = CodedConcept(
        coreConcept: DICOMCore.SRClinicalCatalog.imagingMeasurementsConcept
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
            coreConcept: DICOMCore.SRClinicalCatalog.quantityConcept(forUCUMCode: measurement.unit.codeValue)
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

    /// Returns the list of supported SR document types for a builder mode, sourced from `DICOMCore.SRDocumentType`
    /// with clinical imaging report IODs prioritized at the top followed by all remaining PS3.6 SR Storage SOP Classes.
    ///
    /// - Parameter mode: The builder mode.
    /// - Returns: Array of supported document types.
    public static func supportedDocumentTypes(for mode: SRBuilderMode) -> [SRDocumentType] {
        SRDocumentType.prioritizedForClinicalAuthoring
    }

    /// Returns all clinical report section templates from `DICOMCore.SRClinicalCatalog.clinicalTemplatePresets`
    /// applicable to a document type.
    ///
    /// - Parameter documentType: The SR document type.
    /// - Returns: Array of available clinical templates.
    public static func availableTemplates(for documentType: SRDocumentType) -> [SRTemplate] {
        switch documentType {
        case .keyObjectSelection:
            return []
        default:
            return SRTemplate.allCases
        }
    }

    /// Returns all registered PS3.16 TID template descriptors from `DICOMCore.TemplateRegistry.shared`
    /// (all 73 registered templates, ordered with root templates first).
    public static var allRegisteredTemplates: [DICOMCore.SRRegisteredTemplateDescriptor] {
        DICOMCore.TemplateRegistry.shared.allTemplateDescriptors
    }

    /// Returns all registered PS3.16 TID template descriptors from `DICOMCore.TemplateRegistry.shared`
    /// for a given document type.
    public static func registeredTemplates(for documentType: SRDocumentType) -> [DICOMCore.SRRegisteredTemplateDescriptor] {
        DICOMCore.TemplateRegistry.shared.allTemplateDescriptors
    }
}
