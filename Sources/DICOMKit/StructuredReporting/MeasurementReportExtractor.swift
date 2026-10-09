// NEMA-verified: 2026a, checked 2026-09-29 — reads the content tree per PS3.16 2026a Tables TID 1500, TID 1204, TID 1600/1601/1602, TID 1501 (rows 2, 3, 3b, 6, 11) and tolerates the pre-2026-09-29 flat placements (images directly under Image Library, Country of Language beside the language item); reads TID 1204 row 2 nested under row 1 per PS3.3 Table C.17-6 (D31), and TID 1501 row 7 is not taken for an evaluation nested or beside the Finding Site; concept codes per Table D-1
// NEMA-verified: 2026a, checked 2026-09-30 — P-MGC: reads TID 1501 rows 7-8 under the Finding Site, rows 10-12 with their nested rows (10d, 11b) and TID 300 row 1b → TID 301 rows 2-7 and 13 → TID 320 rows 1, 3-4 and 6 under a NUM into `ExtractedMeasurementGroup.contents`; rows, relationships, value types and concept codes compared by script against the PS3.16 2026a DocBook tables TID 1501, 300, 301 and 320
/// Measurement Report Extraction API
///
/// Provides high-level extraction of TID 1500 Measurement Report data from SR documents.
///
/// Reference: PS3.16 TID 1500 - Measurement Report
/// Reference: PS3.16 TID 1501 - Measurement Group

import Foundation
import DICOMCore

/// Represents an extracted TID 1500 Measurement Report
///
/// Provides structured access to measurement groups, image library entries,
/// and qualitative evaluations from a TID 1500 compliant SR document.
///
/// Example:
/// ```swift
/// let parser = SRDocumentParser()
/// let document = try parser.parse(dataSet: dataSet)
/// let report = try MeasurementReport.extract(from: document)
/// 
/// for group in report.measurementGroups {
///     print("Tracking: \(group.trackingIdentifier)")
///     for measurement in group.measurements {
///         print("  \(measurement.conceptName?.codeMeaning ?? "Measurement"): \(measurement.value)")
///     }
/// }
/// ```
public struct MeasurementReport: Sendable, Equatable {
    
    // MARK: - Document Information
    
    /// The original SR document
    public let document: SRDocument
    
    /// Document title (Concept Name of root container)
    public var documentTitle: CodedConcept? {
        document.documentTitle
    }
    
    /// Procedure reported codes
    public let proceduresReported: [CodedConcept]
    
    /// Language of content (TID 1204 row 1)
    public let languageOfContent: CodedConcept?

    /// Country of language (TID 1204 row 2)
    public let countryOfLanguage: CodedConcept?

    // MARK: - Content Structures

    /// Image library entries (TID 1600): the IMAGE items of every Image Library Group
    /// (TID 1600 rows 2 and 4 → TID 1601 row 1), in document order. IMAGE items written
    /// directly under the Image Library container (the pre-2026-09-29 layout) are read too.
    public let imageLibraryEntries: [ImageReference]
    
    /// Measurement groups (TID 1501)
    public let measurementGroups: [ExtractedMeasurementGroup]
    
    /// Qualitative evaluations
    public let qualitativeEvaluations: [CodedConcept]
    
    // MARK: - Extraction API
    
    /// Extracts a measurement report from an SR document
    /// - Parameter document: The SR document to extract from
    /// - Returns: An extracted measurement report
    /// - Throws: `ExtractionError` if the document is not a valid measurement report
    public static func extract(from document: SRDocument) throws -> MeasurementReport {
        // Validate document type
        guard let docType = document.documentType,
              docType.sopClassUID == SRDocumentType.comprehensiveSR.sopClassUID ||
              docType.sopClassUID == SRDocumentType.comprehensive3DSR.sopClassUID else {
            throw ExtractionError.invalidDocumentType(
                "Document must be Comprehensive SR or Comprehensive 3D SR for TID 1500, got: \(document.sopClassUID)"
            )
        }
        
        // Extract procedures reported
        let proceduresReported = extractProceduresReported(from: document.rootContent)
        
        // Extract language of content and its country (TID 1204)
        let (languageOfContent, countryOfLanguage) = extractLanguage(from: document.rootContent)

        // Extract image library (TID 1600)
        let imageLibraryEntries = extractImageLibrary(from: document.rootContent)

        // Extract measurement groups (TID 1501)
        let measurementGroups = try extractMeasurementGroups(from: document.rootContent)

        // Extract qualitative evaluations
        let qualitativeEvaluations = extractQualitativeEvaluations(from: document.rootContent)

        return MeasurementReport(
            document: document,
            proceduresReported: proceduresReported,
            languageOfContent: languageOfContent,
            countryOfLanguage: countryOfLanguage,
            imageLibraryEntries: imageLibraryEntries,
            measurementGroups: measurementGroups,
            qualitativeEvaluations: qualitativeEvaluations
        )
    }

    // MARK: - Private Extraction Helpers

    private static func extractProceduresReported(from container: ContainerContentItem) -> [CodedConcept] {
        var procedures: [CodedConcept] = []

        for item in container.contentItems {
            if let codeItem = item.asCode,
               codeItem.conceptName?.codeValue == "121058" { // TID 1500 row 4: Procedure reported
                procedures.append(codeItem.conceptCode)
            }
        }

        return procedures
    }

    /// TID 1500 row 2 → TID 1204: row 1 (121049, DCM) HAS CONCEPT MOD CODE at the root; row 2
    /// (121046, DCM) is its child, in the language item's Content Sequence (PS3.3 Table
    /// C.17-6). A root-level sibling, as `MeasurementReportBuilder` wrote it before
    /// 2026-09-29 (D31), is accepted as well.
    private static func extractLanguage(from container: ContainerContentItem) -> (CodedConcept?, CodedConcept?) {
        var language: CodedConcept?
        var country: CodedConcept?
        for item in container.contentItems {
            guard let codeItem = item.asCode, let concept = codeItem.conceptName else { continue }
            if concept.codeValue == "121049", language == nil {
                language = codeItem.conceptCode
                if country == nil {
                    country = codeItem.contentItems.lazy.compactMap { $0.asCode }
                        .first { $0.conceptName?.codeValue == "121046" }?.conceptCode
                }
            } else if concept.codeValue == "121046", country == nil {
                country = codeItem.conceptCode
            }
        }
        return (language, country)
    }

    /// TID 1600: row 1 CONTAINER (111028, DCM, "Image Library"); row 2 CONTAINS CONTAINER
    /// (126200, DCM, "Image Library Group"); row 4 CONTAINS TID 1601 row 1 IMAGE. IMAGE items
    /// found directly under the Image Library container are read as well.
    private static func extractImageLibrary(from container: ContainerContentItem) -> [ImageReference] {
        var entries: [ImageReference] = []

        for item in container.contentItems {
            guard let imageLibContainer = item.asContainer,
                  imageLibContainer.conceptName?.codeValue == "111028" else { continue }

            for libraryItem in imageLibContainer.contentItems {
                if let group = libraryItem.asContainer,
                   group.conceptName?.codeValue == "126200" {
                    entries += group.contentItems.compactMap { $0.asImage?.imageReference }
                } else if let image = libraryItem.asImage {
                    entries.append(image.imageReference)
                }
            }
        }

        return entries
    }
    
    private static func extractMeasurementGroups(from container: ContainerContentItem) throws -> [ExtractedMeasurementGroup] {
        var groups: [ExtractedMeasurementGroup] = []
        
        // Find Imaging Measurements container
        for item in container.contentItems {
            if let measurementsContainer = item.asContainer,
               measurementsContainer.conceptName?.codeValue == "126010" { // Imaging Measurements
                
                // Each child container is a Measurement Group (TID 1501)
                for groupItem in measurementsContainer.contentItems {
                    if let groupContainer = groupItem.asContainer,
                       groupContainer.conceptName?.codeValue == "125007" { // Measurement Group
                        
                        let group = try extractSingleMeasurementGroup(from: groupContainer)
                        groups.append(group)
                    }
                }
            }
        }
        
        return groups
    }
    
    private static func extractSingleMeasurementGroup(from container: ContainerContentItem) throws -> ExtractedMeasurementGroup {
        var trackingIdentifier: String?
        var trackingUID: String?
        var findingType: CodedConcept?
        var findingSite: CodedConcept?
        var laterality: CodedConcept?
        var topographicalModifier: CodedConcept?
        var measurements: [Measurement] = []
        var qualitativeEvaluations: [CodedConcept] = []
        var contents: [MeasurementGroupContent] = []
        
        for item in container.contentItems {
            // TID 1501 row 2: HAS OBS CONTEXT TEXT (112039, DCM, "Tracking Identifier")
            if let textItem = item.asText,
               textItem.conceptName?.codeValue == "112039" {
                trackingIdentifier = textItem.textValue
            }

            // TID 1501 row 3: HAS OBS CONTEXT UIDREF (112040, DCM, "Tracking Unique Identifier")
            else if let uidItem = item.asUIDRef,
                    uidItem.conceptName?.codeValue == "112040" {
                trackingUID = uidItem.uidValue
            }

            // TID 1501 row 3b: CONTAINS CODE (121071, DCM, "Finding")
            else if let codeItem = item.asCode,
                    codeItem.conceptName?.codeValue == "121071" {
                findingType = codeItem.conceptCode
            }

            // TID 1501 row 6: HAS CONCEPT MOD CODE (363698007, SCT, "Finding Site"), with rows 7
            // (Laterality) and 8 (Topographical modifier) in its Content Sequence
            else if let codeItem = item.asCode,
                    codeItem.conceptName?.codeValue == "363698007" {
                findingSite = codeItem.conceptCode
                let site = Self.findingSite(from: codeItem)
                laterality = laterality ?? site.laterality
                topographicalModifier = topographicalModifier ?? site.topographicalModifier
            }

            // TID 1501 row 7 written beside the Finding Site (the layout before 2026-09-29, D31)
            else if let codeItem = item.asCode, codeItem.relationshipType == .hasConceptMod,
                    codeItem.conceptName?.codeValue == "272741003" {
                laterality = laterality ?? codeItem.conceptCode
            }

            // TID 1501 row 10 → TID 300 row 1: NUM measurements
            else if let numItem = item.asNumeric {
                let measurement = Measurement(from: numItem)
                measurements.append(measurement)
            }

            // TID 1501 row 11: CONTAINS CODE ($QualType) qualitative evaluations. Concept
            // modifiers of the group (HAS CONCEPT MOD, e.g. row 7 Laterality written beside
            // the Finding Site) are not evaluations.
            else if let codeItem = item.asCode,
                    codeItem.relationshipType != .hasConceptMod {
                qualitativeEvaluations.append(codeItem.conceptCode)
            }

            // TID 1501 rows 10-12, as the builder's `MeasurementGroupContent`
            if let content = Self.groupContent(from: item) {
                contents.append(content)
            }
        }
        
        guard let trackingID = trackingIdentifier else {
            throw ExtractionError.missingRequiredElement("Tracking Identifier is required for Measurement Group")
        }
        
        return ExtractedMeasurementGroup(
            trackingIdentifier: trackingID,
            trackingUID: trackingUID,
            findingType: findingType,
            findingSite: findingSite,
            laterality: laterality,
            topographicalModifier: topographicalModifier,
            measurements: measurements,
            qualitativeEvaluations: qualitativeEvaluations,
            contents: contents
        )
    }

    // MARK: TID 1501 rows 10-12 and their nested rows (P-MGC)

    /// Reads one item of a Measurement Group as the `MeasurementGroupContent` case that writes
    /// it, or nil for the group's other rows (1b-9d) and for items no case describes.
    /// A NUM without children reads as `.measurement` (or `.measurements` when it has several
    /// values), even if it was built as `.measurementWithContent` with empty content.
    static func groupContent(from item: AnyContentItem) -> MeasurementGroupContent? {
        switch item.valueType {
        case .num:
            // TID 1501 row 10 → TID 300 row 1 (NUM), row 1b → TID 301 in its Content Sequence
            guard item.relationshipType == .contains, let num = item.asNumeric else { return nil }
            if !num.contentItems.isEmpty, num.numericValues.count == 1,
               let conceptName = num.conceptName, let units = num.measurementUnits {
                return .measurementWithContent(conceptName: conceptName, value: num.numericValues[0],
                                               units: units, content: measurementContent(from: num.contentItems))
            }
            if num.numericValues.count == 1 {
                return .measurement(conceptName: num.conceptName, value: num.numericValues[0], units: num.measurementUnits)
            }
            return .measurements(conceptName: num.conceptName, values: num.numericValues, units: num.measurementUnits)

        case .code:
            // TID 1501 row 11 (CODE) with row 11b (HAS CONCEPT MOD CODE) in its Content Sequence.
            // Rows 3a (276214006, SCT) and 3b (121071, DCM) are CONTAINS CODE too but are not
            // evaluations.
            guard item.relationshipType == .contains, let code = item.asCode,
                  !["276214006", "121071"].contains(code.conceptName?.codeValue ?? "") else { return nil }
            let modifiers = code.contentItems.compactMap(conceptModifier(from:))
            if let conceptName = code.conceptName, !modifiers.isEmpty {
                return .qualitativeEvaluationWithModifiers(conceptName: conceptName, value: code.conceptCode,
                                                           modifiers: modifiers)
            }
            return .qualitativeEvaluation(conceptName: code.conceptName, value: code.conceptCode)

        case .image:
            // TID 1501 row 10b (CONTAINS IMAGE). INFERRED FROM is the layout before 2026-09-29.
            // Rows 9c (121200, DCM) and 9d (130401, DCM) are CONTAINS IMAGE with their own concept.
            guard item.relationshipType == .contains || item.relationshipType == .inferredFrom,
                  let image = item.asImage,
                  !["121200", "130401"].contains(image.conceptName?.codeValue ?? "") else { return nil }
            let reference = image.imageReference
            return .imageReference(sopClassUID: reference.sopReference.sopClassUID,
                                   sopInstanceUID: reference.sopReference.sopInstanceUID,
                                   frameNumbers: reference.frameNumbers)

        case .scoord:
            // TID 1501 row 10c (SCOORD) with row 10d (SELECTED FROM IMAGE) in its Content Sequence
            guard item.relationshipType == .contains, let scoord = item.asSpatialCoordinates else { return nil }
            if let source = selectedFromImage(scoord.contentItems) {
                return .spatialCoordinatesOnImage(conceptName: scoord.conceptName, graphicType: scoord.graphicType,
                                                  graphicData: scoord.graphicData, sourceImage: source)
            }
            return .spatialCoordinates(conceptName: scoord.conceptName, graphicType: scoord.graphicType,
                                       graphicData: scoord.graphicData)

        case .scoord3D:
            // TID 1501 row 10e (SCOORD3D)
            guard item.relationshipType == .contains, let scoord = item.asSpatialCoordinates3D else { return nil }
            return .spatialCoordinates3D(conceptName: scoord.conceptName, graphicType: scoord.graphicType,
                                         graphicData: scoord.graphicData,
                                         frameOfReferenceUID: scoord.frameOfReferenceUID ?? "")

        case .text:
            // TID 1501 row 12 (CONTAINS TEXT); rows 1b and 2 are HAS OBS CONTEXT
            guard item.relationshipType == .contains, let text = item.asText else { return nil }
            return .text(conceptName: text.conceptName, value: text.textValue)

        default:
            return nil
        }
    }

    /// TID 301 rows 2-7 and 13 (→ TID 320 rows 1, 3-4, 6) from a NUM's Content Sequence.
    /// Other rows are not read.
    static func measurementContent(from children: [AnyContentItem]) -> MeasurementContent {
        var content = MeasurementContent()
        for child in children {
            if let code = child.asCode, child.relationshipType == .hasConceptMod {
                switch code.conceptName?.codeValue {
                case "370129005" where content.method == nil:                 // row 3
                    content.method = code.conceptCode
                case "121401" where content.derivation == nil:                // row 4
                    content.derivation = code.conceptCode
                case "363698007":                                             // rows 5-7
                    content.findingSites.append(findingSite(from: code))
                case "370129005", "121401":
                    break
                default:                                                      // row 2
                    if let modifier = conceptModifier(from: child) { content.modifiers.append(modifier) }
                }
            } else if child.relationshipType == .inferredFrom {                // row 13 → TID 320
                if let image = child.asImage {                                // row 1
                    content.sources.append(.image(purpose: image.conceptName, image: image.imageReference))
                } else if let scoord = child.asSpatialCoordinates,           // rows 3-4
                          let source = selectedFromImage(scoord.contentItems) {
                    content.sources.append(.spatialCoordinates(purpose: scoord.conceptName, graphicType: scoord.graphicType,
                                                               graphicData: scoord.graphicData, sourceImage: source))
                } else if let scoord = child.asSpatialCoordinates3D {         // row 6
                    content.sources.append(.spatialCoordinates3D(purpose: scoord.conceptName, graphicType: scoord.graphicType,
                                                                 graphicData: scoord.graphicData,
                                                                 frameOfReferenceUID: scoord.frameOfReferenceUID ?? ""))
                }
            }
        }
        return content
    }

    /// A Finding Site CODE with its Laterality (272741003, SCT) and Topographical modifier
    /// (106233006, SCT) children: TID 1501 rows 6-8, TID 301 rows 5-7
    static func findingSite(from code: CodeContentItem) -> MeasurementFindingSite {
        let children = code.contentItems.compactMap { $0.asCode }.filter { $0.relationshipType == .hasConceptMod }
        return MeasurementFindingSite(
            site: code.conceptCode,
            laterality: children.first { $0.conceptName?.codeValue == "272741003" }?.conceptCode,
            topographicalModifier: children.first { $0.conceptName?.codeValue == "106233006" }?.conceptCode
        )
    }

    /// A HAS CONCEPT MOD CODE with a concept name: TID 301 row 2, TID 1501 row 11b
    static func conceptModifier(from item: AnyContentItem) -> MeasurementConceptModifier? {
        guard item.relationshipType == .hasConceptMod, let code = item.asCode,
              let conceptName = code.conceptName else { return nil }
        return MeasurementConceptModifier(conceptName: conceptName, value: code.conceptCode)
    }

    /// The image of a SELECTED FROM IMAGE child: TID 1501 row 10d, TID 320 row 4
    static func selectedFromImage(_ children: [AnyContentItem]) -> ImageReference? {
        children.first { $0.relationshipType == .selectedFrom && $0.valueType == .image }?.asImage?.imageReference
    }
    
    private static func extractQualitativeEvaluations(from container: ContainerContentItem) -> [CodedConcept] {
        var evaluations: [CodedConcept] = []
        
        for item in container.contentItems {
            // TID 1500 row 9: a "Qualitative Evaluations" (C0034375, UMLS)
            // container whose CODE children are the evaluations.
            if let evaluationsContainer = item.asContainer,
               evaluationsContainer.conceptName?.codeValue == "C0034375" {
                evaluations += evaluationsContainer.contentItems.compactMap { $0.asCode?.conceptCode }
            }
            // Evaluations written directly under the root.
            else if let codeItem = item.asCode,
                    let conceptName = codeItem.conceptName,
                    ["121071", "121073", "121074"].contains(conceptName.codeValue) {
                evaluations.append(codeItem.conceptCode)
            }
        }
        
        return evaluations
    }
}

// MARK: - Supporting Types

// Note: ImageReference type is defined in DICOMCore.ContentItem and is reused here

/// Represents a measurement group (TID 1501)
public struct ExtractedMeasurementGroup: Sendable, Equatable {
    /// Tracking identifier for the measurement group
    public let trackingIdentifier: String
    
    /// Tracking unique identifier (UID)
    public let trackingUID: String?
    
    /// Type of finding being measured
    public let findingType: CodedConcept?
    
    /// Anatomical site of the finding
    public let findingSite: CodedConcept?

    /// Laterality of the finding site: TID 1501 row 7
    public let laterality: CodedConcept?

    /// Topographical modifier of the finding site: TID 1501 row 8
    public let topographicalModifier: CodedConcept?
    
    /// Numeric measurements in this group
    public let measurements: [Measurement]
    
    /// Qualitative evaluations (coded concepts)
    public let qualitativeEvaluations: [CodedConcept]

    /// The group's TID 1501 rows 10-12, with the rows nested under them (10d, 11b, and TID 300
    /// row 1b → TID 301 → TID 320 under a NUM), read as the `MeasurementGroupContent` that
    /// `MeasurementReportBuilder` writes them from, in document order
    public let contents: [MeasurementGroupContent]
    
    /// Creates a measurement group
    public init(
        trackingIdentifier: String,
        trackingUID: String? = nil,
        findingType: CodedConcept? = nil,
        findingSite: CodedConcept? = nil,
        laterality: CodedConcept? = nil,
        topographicalModifier: CodedConcept? = nil,
        measurements: [Measurement] = [],
        qualitativeEvaluations: [CodedConcept] = [],
        contents: [MeasurementGroupContent] = []
    ) {
        self.trackingIdentifier = trackingIdentifier
        self.trackingUID = trackingUID
        self.findingType = findingType
        self.findingSite = findingSite
        self.laterality = laterality
        self.topographicalModifier = topographicalModifier
        self.measurements = measurements
        self.qualitativeEvaluations = qualitativeEvaluations
        self.contents = contents
    }
}

// MARK: - Extraction Errors

/// Errors that can occur during extraction
public enum ExtractionError: Error, Sendable, Equatable {
    /// Invalid document type for extraction
    case invalidDocumentType(String)
    
    /// Missing required element
    case missingRequiredElement(String)
    
    /// Invalid structure
    case invalidStructure(String)
}

extension ExtractionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDocumentType(let message):
            return "Invalid document type: \(message)"
        case .missingRequiredElement(let message):
            return "Missing required element: \(message)"
        case .invalidStructure(let message):
            return "Invalid structure: \(message)"
        }
    }
}
