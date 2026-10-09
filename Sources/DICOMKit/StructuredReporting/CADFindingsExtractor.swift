// NEMA-verified: 2026a, checked 2026-09-29 — reads the TID 4000/4100 trees the builders write (TID 1204, 4020, 4001/4101, 4003, 4006/4104, 4019, 4021/4107, 4015-4018 concepts of PS3.16 2026a) with children nested in the Content Sequence of CODE/IMAGE/SCOORD items per PS3.3 Table C.17-6 (D31), the same tree flattened into following siblings (written before D31), and the layouts written before the check
/// CAD Findings Extraction API
///
/// Provides high-level extraction of Computer-Aided Detection (CAD) findings from
/// Mammography CAD SR and Chest CAD SR documents.
///
/// Reference: PS3.3 Section A.35.5 - Mammography CAD SR IOD
/// Reference: PS3.3 Section A.35.6 - Chest CAD SR IOD
/// Reference: PS3.16 TID 4000 - Mammography CAD Document Root
/// Reference: PS3.16 TID 4100 - Chest CAD Document Root
/// Reference: PS3.16 TID 4006 / TID 4104 - Single Image Finding
/// Reference: PS3.16 TID 4019 - Algorithm Identification

import Foundation
import DICOMCore

/// Represents extracted CAD findings from a CAD SR document
///
/// Provides structured access to CAD processing information and detected findings
/// with confidence scores, locations, and characteristics.
///
/// Example:
/// ```swift
/// let parser = SRDocumentParser()
/// let document = try parser.parse(dataSet: dataSet)
/// let findings = try CADFindings.extract(from: document)
///
/// print("Algorithm: \(findings.processingInfo.algorithmName ?? "Unknown")")
/// for finding in findings.findings {
///     print("Finding: \(finding.findingType?.codeMeaning ?? "Unknown")")
///     print("  Confidence: \(finding.probability ?? 0)")
/// }
/// ```
///
/// ## Layouts read
/// - The template tree with the children of CODE/IMAGE/SCOORD items nested in their Content
///   Sequence (PS3.3 Table C.17-6), as the builders write it since 2026-09-29 (D31): a
///   finding is a CODE (111059, DCM, "Single Image Finding") and its descendants (TID 4006 /
///   TID 4104 rows 2-18), found wherever it hangs, e.g. INFERRED FROM the TID 4001/4101
///   (111017, DCM) CODE.
/// - The same tree written by earlier versions with those children flattened into the
///   siblings that follow their parent: a finding starts at a 111059 CODE without children
///   and takes every following sibling that is not a CONTAINS-related item (the next 111059
///   CODE starts the next finding).
/// - Documents written before the 2026a check, where each finding was a CONTAINER of
///   CONTAINS items.
public struct CADFindings: Sendable, Equatable {

    // MARK: - Document Information

    /// The original SR document
    public let document: SRDocument

    /// CAD document type
    public var cadType: CADType {
        if let docType = document.documentType {
            switch docType.sopClassUID {
            case SRDocumentType.mammographyCADSR.sopClassUID:
                return .mammography
            case SRDocumentType.chestCADSR.sopClassUID:
                return .chest
            default:
                return .unknown
            }
        }
        return .unknown
    }

    // MARK: - CAD Processing Information

    /// CAD processing summary information (TID 4019, first occurrence)
    public let processingInfo: CADProcessingInfo

    /// Detected findings (TID 4006 / TID 4104)
    public let findings: [ExtractedCADFinding]

    /// (121049, DCM, "Language of Content Item and Descendants") of the root (TID 1204)
    public let language: CodedConcept?

    /// The images of the (111028, DCM, "Image Library") (TID 4020 row 1)
    public let imageLibrary: [ImageReference]

    /// Value of (111017, DCM, "CAD Processing and Findings Summary") (CID 6047)
    public let processingAndFindingsSummary: CodedConcept?

    /// Value of (111064, DCM, "Summary of Detections") (CID 6042)
    public let summaryOfDetections: CodedConcept?

    /// Value of (111065, DCM, "Summary of Analyses") (CID 6042)
    public let summaryOfAnalyses: CodedConcept?

    /// Values of (111022, DCM, "Detection Performed") (TID 4017 row 1)
    public let detectionsPerformed: [CodedConcept]

    /// Values of (111004, DCM, "Analysis Performed") (TID 4018 row 1)
    public let analysesPerformed: [CodedConcept]

    /// Creates the extraction result
    public init(
        document: SRDocument,
        processingInfo: CADProcessingInfo,
        findings: [ExtractedCADFinding],
        language: CodedConcept? = nil,
        imageLibrary: [ImageReference] = [],
        processingAndFindingsSummary: CodedConcept? = nil,
        summaryOfDetections: CodedConcept? = nil,
        summaryOfAnalyses: CodedConcept? = nil,
        detectionsPerformed: [CodedConcept] = [],
        analysesPerformed: [CodedConcept] = []
    ) {
        self.document = document
        self.processingInfo = processingInfo
        self.findings = findings
        self.language = language
        self.imageLibrary = imageLibrary
        self.processingAndFindingsSummary = processingAndFindingsSummary
        self.summaryOfDetections = summaryOfDetections
        self.summaryOfAnalyses = summaryOfAnalyses
        self.detectionsPerformed = detectionsPerformed
        self.analysesPerformed = analysesPerformed
    }

    // MARK: - Extraction API

    /// Extracts CAD findings from a CAD SR document
    /// - Parameter document: The SR document to extract from
    /// - Returns: Extracted CAD findings
    /// - Throws: `ExtractionError` if the document is not a valid CAD SR
    public static func extract(from document: SRDocument) throws -> CADFindings {
        // Validate document type
        guard let docType = document.documentType else {
            throw ExtractionError.invalidDocumentType("Document type could not be determined")
        }

        let isCADDocument = docType.sopClassUID == SRDocumentType.mammographyCADSR.sopClassUID ||
                           docType.sopClassUID == SRDocumentType.chestCADSR.sopClassUID

        guard isCADDocument else {
            throw ExtractionError.invalidDocumentType(
                "Document must be Mammography CAD SR or Chest CAD SR, got: \(document.sopClassUID)"
            )
        }

        let root = document.rootContent
        let rootItems = root.contentItems

        // Extract processing information
        let processingInfo = extractProcessingInfo(from: root)

        // Extract findings
        let findings = extractFindings(from: root)

        // Root-level template rows
        let language = rootItems.lazy.compactMap { $0.asCode }
            .first { $0.conceptName?.codeValue == "121049" }?.conceptCode
        let imageLibrary = rootItems.lazy.compactMap { $0.asContainer }
            .first { $0.conceptName?.codeValue == "111028" }?
            .contentItems.compactMap { $0.asImage?.imageReference } ?? []

        func rootCode(_ code: String) -> CodedConcept? {
            rootItems.lazy.compactMap { $0.asCode }.first { $0.conceptName?.codeValue == code }?.conceptCode
        }

        return CADFindings(
            document: document,
            processingInfo: processingInfo,
            findings: findings,
            language: language,
            imageLibrary: imageLibrary,
            processingAndFindingsSummary: rootCode("111017"),
            summaryOfDetections: rootCode("111064"),
            summaryOfAnalyses: rootCode("111065"),
            detectionsPerformed: collectCodes(named: "111022", in: root),
            analysesPerformed: collectCodes(named: "111004", in: root)
        )
    }

    // MARK: - Private Extraction Helpers

    /// Every CODE item with the given concept name, depth first through the children of every
    /// item (CONTAINER contents and the Content Sequence of other value types)
    private static func collectCodes(named code: String, in container: ContainerContentItem) -> [CodedConcept] {
        collectCodes(named: code, in: container.contentItems)
    }

    private static func collectCodes(named code: String, in items: [AnyContentItem]) -> [CodedConcept] {
        var result: [CodedConcept] = []
        for item in items {
            if let codeItem = item.asCode, codeItem.conceptName?.codeValue == code {
                result.append(codeItem.conceptCode)
            }
            result.append(contentsOf: collectCodes(named: code, in: item.contentItems))
        }
        return result
    }

    /// The first TEXT item with the given concept name, depth first
    private static func firstText(named codes: Set<String>, in container: ContainerContentItem) -> String? {
        firstText(named: codes, in: container.contentItems)
    }

    private static func firstText(named codes: Set<String>, in items: [AnyContentItem]) -> String? {
        for item in items {
            if let textItem = item.asText, codes.contains(textItem.conceptName?.codeValue ?? "") {
                return textItem.textValue
            } else if let found = firstText(named: codes, in: item.contentItems) {
                return found
            }
        }
        return nil
    }

    private static func extractProcessingInfo(from container: ContainerContentItem) -> CADProcessingInfo {
        // TID 4019 rows 1, 2 and 2b: the first Algorithm Identification in the tree. The
        // builders write it under every Single Image Finding and Detection Performed;
        // documents written before the 2026a check put it in a (111017, DCM) or (111001, DCM)
        // CONTAINER at the root, which the depth-first search also finds.
        var manufacturer = firstText(named: manufacturerConceptCodes, in: container)
        if manufacturer == nil {
            // Older files wrote the manufacturer as a CODE item
            manufacturer = firstCode(named: manufacturerConceptCodes, in: container)?.codeMeaning
        }
        return CADProcessingInfo(
            algorithmName: firstText(named: ["111001"], in: container),
            algorithmVersion: firstText(named: ["111003"], in: container),
            manufacturer: manufacturer
        )
    }

    private static func firstCode(named codes: Set<String>, in container: ContainerContentItem) -> CodedConcept? {
        firstCode(named: codes, in: container.contentItems)
    }

    private static func firstCode(named codes: Set<String>, in items: [AnyContentItem]) -> CodedConcept? {
        for item in items {
            if let codeItem = item.asCode, codes.contains(codeItem.conceptName?.codeValue ?? "") {
                return codeItem.conceptCode
            } else if let found = firstCode(named: codes, in: item.contentItems) {
                return found
            }
        }
        return nil
    }

    /// Concept names that carry a finding's probability: (111047, DCM, "Probability of
    /// cancer") (TID 4006 row 7) and (111012, DCM, "Certainty of Finding") (TID 4006 row 6 /
    /// TID 4104 row 12), both 0-100 percent; (111023, DCM) is kept for documents that used it.
    private static let probabilityConceptCodes: Set<String> = ["111047", "111012", "111023"]

    /// (122405, DCM, "Algorithm Manufacturer") (TID 4019 row 2b); (113878, DCM) was written
    /// before the 2026a check.
    private static let manufacturerConceptCodes: Set<String> = ["122405", "113878"]

    /// (111059, DCM, "Single Image Finding") (TID 4006 / TID 4104 row 1); (121071, DCM,
    /// "Finding") was written before the 2026a check.
    private static let findingTypeConceptCodes: Set<String> = ["111059", "121071"]

    /// TID 4019 concept names (rows 1, 1b, 2, 2b, 3, 4), (111056, DCM, "Rendering Intent") and
    /// (112024, DCM, "Single Image Finding Modifier"): property items of a finding that are
    /// not descriptors
    private static let nonDescriptorConceptCodes: Set<String> = ["111001", "111003", "122405", "111002", "111000", "111056", "112024"]

    private static func isProbability(_ item: NumericContentItem) -> Bool {
        item.conceptName.map { probabilityConceptCodes.contains($0.codeValue) } ?? false
    }

    /// The probability as a 0-1 fraction: percent values (UCUM "%") are divided by 100; a
    /// (111047, DCM) value with (1, UCUM, "no units"), as written before the 2026a check, is
    /// already a fraction.
    private static func probabilityValue(_ item: NumericContentItem) -> Double? {
        guard let value = item.numericValues.first else { return nil }
        if item.measurementUnits?.codeValue == "%" { return value / 100 }
        if item.conceptName?.codeValue == "111012" { return value / 100 }
        return value
    }

    /// The descendants of an item in document order (pre-order), i.e. the sequence of items
    /// that earlier versions wrote as the siblings following it
    private static func descendants(of item: AnyContentItem) -> [AnyContentItem] {
        item.contentItems.flatMap { [$0] + descendants(of: $0) }
    }

    private static func extractFindings(from container: ContainerContentItem) -> [ExtractedCADFinding] {
        extractFindings(in: container.contentItems)
    }

    private static func extractFindings(in contentItems: [AnyContentItem]) -> [ExtractedCADFinding] {
        var findings: [ExtractedCADFinding] = []
        var current: [AnyContentItem]? = nil

        func flush() {
            if let items = current, let finding = extractSingleFinding(from: items, container: nil) {
                findings.append(finding)
            }
            current = nil
        }

        for item in contentItems {
            if let codeItem = item.asCode, findingTypeConceptCodes.contains(codeItem.conceptName?.codeValue ?? ""),
               current == nil || codeItem.conceptName?.codeValue == "111059" {
                // A (111059, DCM) CODE starts a finding; a (121071, DCM) CODE only when none is open
                // (older files used it for the type and for each characteristic).
                flush()
                if item.contentItems.isEmpty {
                    // Written before D31: the finding's rows are the siblings that follow
                    current = [item]
                } else if let finding = extractSingleFinding(from: [item] + descendants(of: item), container: nil) {
                    // TID 4006 / TID 4104 rows 2-18 nested in the CODE's Content Sequence
                    findings.append(finding)
                }
            } else if let child = item.asContainer {
                flush()
                if child.contentItems.contains(where: { $0.asNumeric.map(isProbability) ?? false }),
                   !child.contentItems.contains(where: { $0.asCode?.conceptName?.codeValue == "111059" }) {
                    // Layout written before the 2026a check: one CONTAINER per finding, no 111059
                    if let finding = extractSingleFinding(from: child.contentItems, container: child) {
                        findings.append(finding)
                    }
                } else {
                    findings.append(contentsOf: extractFindings(from: child))
                }
            } else if current != nil, belongsToOpenFinding(item) {
                current?.append(contentsOf: [item] + descendants(of: item))
            } else {
                flush()
                // Findings nested under a non-CONTAINER item, e.g. INFERRED FROM the TID 4101
                // (111017, DCM) CODE (row 3), or in the TID 4003 containers INFERRED FROM the
                // TID 4001 CODE (row 3)
                if !item.contentItems.isEmpty {
                    findings.append(contentsOf: extractFindings(in: item.contentItems))
                }
            }
        }
        flush()
        return findings
    }

    /// Whether a sibling after a Single Image Finding CODE without children is one of the
    /// children earlier versions flattened after it:
    /// anything not CONTAINS-related (HAS CONCEPT MOD, HAS PROPERTIES, HAS OBS CONTEXT,
    /// SELECTED FROM, INFERRED FROM) or, in the layout written before the 2026a check, a
    /// CONTAINS-related probability NUM, SCOORD, IMAGE or (121071, DCM) CODE.
    private static func belongsToOpenFinding(_ item: AnyContentItem) -> Bool {
        if item.relationshipType != .contains { return true }
        if let numItem = item.asNumeric { return isProbability(numItem) }
        if item.asSpatialCoordinates != nil || item.asImage != nil { return true }
        if let codeItem = item.asCode { return codeItem.conceptName?.codeValue == "121071" }
        return false
    }

    private static func extractSingleFinding(from items: [AnyContentItem], container: ContainerContentItem?) -> ExtractedCADFinding? {
        var findingType: CodedConcept? = container?.conceptName
        var modifier: CodedConcept?
        var renderingIntent: CodedConcept?
        var probability: Double?
        var certainty: Double?
        var location: CADFindingLocation?
        var outline: CADFindingLocation?
        var characteristics: [CodedConcept] = []
        var descriptors: [CADDescriptor] = []
        var imageReference: ImageReference?
        var hasExplicitType = false
        var pendingSCOORD: SpatialCoordinatesContentItem?

        func resolveLocation(_ scoord: SpatialCoordinatesContentItem, image: ImageReference?) {
            guard let resolved = extractLocation(from: scoord, imageReference: image) else { return }
            // TID 4021 / TID 4107: (111010, DCM, "Center") is the location, (111041, DCM,
            // "Outline") the outline; an (111030, DCM, "Image Region") written before the
            // 2026a check is the location.
            if scoord.conceptName?.codeValue == "111041" {
                outline = resolved
            } else if location == nil || scoord.conceptName?.codeValue == "111030" {
                location = resolved
            }
        }

        for item in items {
            if let numItem = item.asNumeric, isProbability(numItem) {
                // TID 4006 row 7 / TID 4104 row 12; Certainty (111012) is kept separately when
                // Probability of cancer (111047) is also present
                if numItem.conceptName?.codeValue == "111012" {
                    certainty = probabilityValue(numItem)
                    if probability == nil { probability = certainty }
                } else {
                    probability = probabilityValue(numItem)
                }
            } else if let codeItem = item.asCode,
                      findingTypeConceptCodes.contains(codeItem.conceptName?.codeValue ?? ""),
                      !hasExplicitType {
                findingType = codeItem.conceptCode
                hasExplicitType = true
            } else if let scoordItem = item.asSpatialCoordinates {
                // The SELECTED FROM IMAGE follows its SCOORD; resolve when it arrives
                if let pending = pendingSCOORD { resolveLocation(pending, image: imageReference) }
                pendingSCOORD = scoordItem
            } else if let imageItem = item.asImage {
                imageReference = imageItem.imageReference
                if let pending = pendingSCOORD {
                    resolveLocation(pending, image: imageItem.imageReference)
                    pendingSCOORD = nil
                }
            } else if let codeItem = item.asCode {
                switch codeItem.conceptName?.codeValue {
                case "111056":
                    renderingIntent = codeItem.conceptCode
                case "112024":
                    modifier = codeItem.conceptCode
                case "121071":
                    characteristics.append(codeItem.conceptCode)
                case let code? where nonDescriptorConceptCodes.contains(code):
                    break
                default:
                    if let name = codeItem.conceptName {
                        descriptors.append(CADDescriptor(conceptName: name, value: codeItem.conceptCode))
                        characteristics.append(codeItem.conceptCode)
                    } else {
                        characteristics.append(codeItem.conceptCode)
                    }
                }
            }
        }
        if let pending = pendingSCOORD { resolveLocation(pending, image: imageReference) }

        // Require at least a finding type or probability
        guard findingType != nil || probability != nil else {
            return nil
        }

        return ExtractedCADFinding(
            findingType: findingType,
            probability: probability,
            location: location,
            characteristics: characteristics,
            imageReference: imageReference,
            modifier: modifier,
            renderingIntent: renderingIntent,
            certainty: certainty,
            outline: outline,
            descriptors: descriptors
        )
    }

    private static func extractLocation(
        from scoordItem: SpatialCoordinatesContentItem,
        imageReference imageRef: ImageReference?
    ) -> CADFindingLocation? {
        switch scoordItem.graphicType {
        case .point:
            if scoordItem.graphicData.count >= 2 {
                return .point2D(
                    x: scoordItem.graphicData[0],
                    y: scoordItem.graphicData[1],
                    imageReference: imageRef
                )
            }

        case .polyline:
            let points = stride(from: 0, to: scoordItem.graphicData.count - 1, by: 2).map { i in
                (scoordItem.graphicData[i], scoordItem.graphicData[i + 1])
            }
            return .polyline(
                points: points,
                imageReference: imageRef
            )

        case .circle:
            if scoordItem.graphicData.count >= 4 {
                // PS3.3 C.18.6.1.2: the second point lies on the
                // circumference, so the radius is its distance from the centre.
                let centerX = scoordItem.graphicData[0]
                let centerY = scoordItem.graphicData[1]
                let radius = hypot(scoordItem.graphicData[2] - centerX, scoordItem.graphicData[3] - centerY)
                return .circle(
                    centerX: centerX,
                    centerY: centerY,
                    radiusX: radius,
                    radiusY: radius,
                    imageReference: imageRef
                )
            }

        case .ellipse:
            if scoordItem.graphicData.count >= 8 {
                let maxIndex = min(8, scoordItem.graphicData.count) - 1
                let points = stride(from: 0, to: maxIndex, by: 2).map { i in
                    (scoordItem.graphicData[i], scoordItem.graphicData[i + 1])
                }
                return .ellipse(
                    points: points,
                    imageReference: imageRef
                )
            }

        default:
            break
        }

        return nil
    }
}

// MARK: - Supporting Types

/// Type of CAD document
public enum CADType: Sendable, Equatable, Hashable {
    /// Mammography CAD
    case mammography

    /// Chest CAD
    case chest

    /// Unknown CAD type
    case unknown
}

/// CAD processing summary information
public struct CADProcessingInfo: Sendable, Equatable {
    /// Name of the CAD algorithm
    public let algorithmName: String?

    /// Version of the CAD algorithm
    public let algorithmVersion: String?

    /// Manufacturer of the CAD system
    public let manufacturer: String?

    /// Creates CAD processing info
    public init(
        algorithmName: String? = nil,
        algorithmVersion: String? = nil,
        manufacturer: String? = nil
    ) {
        self.algorithmName = algorithmName
        self.algorithmVersion = algorithmVersion
        self.manufacturer = manufacturer
    }
}

/// A single extracted CAD finding
public struct ExtractedCADFinding: Sendable, Equatable {
    /// Type of finding detected (the (111059, DCM, "Single Image Finding") value)
    public let findingType: CodedConcept?

    /// Detection probability/confidence (0.0-1.0): Probability of cancer (111047, DCM) when
    /// present, else Certainty of Finding (111012, DCM)
    public let probability: Double?

    /// Spatial location of the finding ((111010, DCM, "Center"))
    public let location: CADFindingLocation?

    /// Additional characteristics of the finding: the values of the TID 4011/4105 descriptors
    /// and, for older files, the (121071, DCM, "Finding") codes
    public let characteristics: [CodedConcept]

    /// Reference to the source image
    public let imageReference: ImageReference?

    /// (112024, DCM, "Single Image Finding Modifier") (TID 4104 row 2)
    public let modifier: CodedConcept?

    /// (111056, DCM, "Rendering Intent") (CID 6034)
    public let renderingIntent: CodedConcept?

    /// (111012, DCM, "Certainty of Finding") as a 0-1 fraction
    public let certainty: Double?

    /// (111041, DCM, "Outline") (TID 4021 row 3 / TID 4107 row 4)
    public let outline: CADFindingLocation?

    /// TID 4011 / TID 4105 descriptors with their concept names
    public let descriptors: [CADDescriptor]

    /// Creates a CAD finding
    public init(
        findingType: CodedConcept? = nil,
        probability: Double? = nil,
        location: CADFindingLocation? = nil,
        characteristics: [CodedConcept] = [],
        imageReference: ImageReference? = nil,
        modifier: CodedConcept? = nil,
        renderingIntent: CodedConcept? = nil,
        certainty: Double? = nil,
        outline: CADFindingLocation? = nil,
        descriptors: [CADDescriptor] = []
    ) {
        self.findingType = findingType
        self.probability = probability
        self.location = location
        self.characteristics = characteristics
        self.imageReference = imageReference
        self.modifier = modifier
        self.renderingIntent = renderingIntent
        self.certainty = certainty
        self.outline = outline
        self.descriptors = descriptors
    }
}

/// Location information for a CAD finding
public enum CADFindingLocation: Sendable {
    /// 2D point location
    case point2D(x: Float, y: Float, imageReference: ImageReference?)

    /// Polyline/polygon region
    case polyline(points: [(Float, Float)], imageReference: ImageReference?)

    /// Circular region
    case circle(centerX: Float, centerY: Float, radiusX: Float, radiusY: Float, imageReference: ImageReference?)

    /// Elliptical region
    case ellipse(points: [(Float, Float)], imageReference: ImageReference?)
}

extension CADFindingLocation: Equatable {
    public static func == (lhs: CADFindingLocation, rhs: CADFindingLocation) -> Bool {
        switch (lhs, rhs) {
        case (.point2D(let lx, let ly, let lref), .point2D(let rx, let ry, let rref)):
            return lx == rx && ly == ry && lref == rref
        case (.polyline(let lpoints, let lref), .polyline(let rpoints, let rref)):
            guard lpoints.count == rpoints.count, lref == rref else { return false }
            return zip(lpoints, rpoints).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.circle(let lcx, let lcy, let lrx, let lry, let lref), .circle(let rcx, let rcy, let rrx, let rry, let rref)):
            return lcx == rcx && lcy == rcy && lrx == rrx && lry == rry && lref == rref
        case (.ellipse(let lpoints, let lref), .ellipse(let rpoints, let rref)):
            guard lpoints.count == rpoints.count, lref == rref else { return false }
            return zip(lpoints, rpoints).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default:
            return false
        }
    }
}

// Note: ImageReference type is defined in DICOMCore.ContentItem and is reused here
