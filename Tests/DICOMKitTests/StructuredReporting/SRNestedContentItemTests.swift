import Testing
import Foundation
@testable import DICOMKit
@testable import DICOMCore

/// D31: PS3.3 2026a Table C.17-6 (Document Relationship Macro) gives every content item a
/// Content Sequence (0040,A730), not only CONTAINER. Template rows nested (">") under a CODE,
/// NUM, IMAGE or SCOORD row are children of that item: e.g. PS3.16 2026a TID 1204 row 2,
/// TID 1501 rows 7 and 10d, TID 300 row 1b → TID 301 row 13 → TID 320 rows 3-4 (INFERRED FROM
/// under a NUM), TID 4006 rows 2-8, TID 4104 rows 2-18, TID 4021/4107 row 2.
@Suite("SR content items with children (D31, PS3.3 Table C.17-6)")
struct SRNestedContentItemTests {

    private func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    private let image = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.6.7.8.9")

    private let longAxis = CodedConcept(codeValue: "103339001", codingSchemeDesignator: "SCT", codeMeaning: "Long Axis")
    private let millimeter = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")

    /// TID 1501 row 10 → TID 300 row 1 NUM with TID 300 row 1b → TID 301 row 13 → TID 320
    /// row 3 ">" INFERRED FROM SCOORD and TID 320 row 4 ">>" SELECTED FROM IMAGE
    private func measurementGroupDocument() -> SRDocument {
        let sourceImage = AnyContentItem(ImageContentItem(imageReference: image, relationshipType: .selectedFrom))
        let region = AnyContentItem(SpatialCoordinatesContentItem(
            graphicType: .polyline,
            graphicData: [0, 0, 10, 0, 10, 10, 0, 0],
            relationshipType: .inferredFrom,
            contentItems: [sourceImage]
        ))
        let numeric = AnyContentItem(NumericContentItem(
            conceptName: longAxis, value: 12.5, units: millimeter, relationshipType: .contains,
            contentItems: [region]
        ))
        let group = AnyContentItem(ContainerContentItem(
            conceptName: dcm("125007", "Measurement Group"),
            continuityOfContent: .separate,
            contentItems: [
                AnyContentItem(TextContentItem(conceptName: dcm("112039", "Tracking Identifier"), textValue: "Lesion 1",
                                               relationshipType: .hasObsContext)),
                numeric,
            ],
            relationshipType: .contains
        ))
        let root = ContainerContentItem(
            conceptName: dcm("126000", "Imaging Measurement Report"),
            continuityOfContent: .separate,
            contentItems: [AnyContentItem(ContainerContentItem(
                conceptName: dcm("126010", "Imaging Measurements"),
                continuityOfContent: .separate,
                contentItems: [group],
                relationshipType: .contains
            ))]
        )
        return SRDocument(sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID, sopInstanceUID: "1.2.3.9",
                          documentTitle: root.conceptName, rootContent: root)
    }

    // MARK: - Serializer and parser

    @Test("TID 1501/300/320: a NUM with an INFERRED FROM SCOORD child round-trips nested")
    func numWithInferredFromChildRoundTrips() throws {
        let original = measurementGroupDocument()
        let dataSet = try SRDocumentSerializer().serialize(document: original)

        // Root → Imaging Measurements → Measurement Group → [TEXT, NUM]; the SCOORD is not a
        // sibling of the NUM but in the NUM item's own Content Sequence (0040,A730)
        let measurements = try #require(dataSet[.contentSequence]?.sequenceItems?.first)
        let group = try #require(measurements[.contentSequence]?.sequenceItems?.first)
        let groupItems = try #require(group[.contentSequence]?.sequenceItems)
        #expect(groupItems.map { $0.string(for: .valueType) } == ["TEXT", "NUM"])
        let numItem = groupItems[1]
        let numChildren = try #require(numItem[.contentSequence]?.sequenceItems)
        #expect(numChildren.count == 1)
        #expect(numChildren[0].string(for: .relationshipType) == "INFERRED FROM")
        #expect(numChildren[0].string(for: .valueType) == "SCOORD")
        let scoordChildren = try #require(numChildren[0][.contentSequence]?.sequenceItems)
        #expect(scoordChildren.count == 1)
        #expect(scoordChildren[0].string(for: .relationshipType) == "SELECTED FROM")
        #expect(scoordChildren[0].string(for: .valueType) == "IMAGE")
        // Type 1C: no Content Sequence on an item without children
        #expect(scoordChildren[0][.contentSequence] == nil)
        #expect(groupItems[0][.contentSequence] == nil)

        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        #expect(parsed.rootContent == original.rootContent)
        let numeric = try #require(parsed.findNumericItems().first)
        #expect(numeric.contentItems.count == 1)
        #expect(numeric.contentItems.first?.relationshipType == .inferredFrom)
        #expect(numeric.contentItems.first?.contentItems.first?.asImage?.imageReference == image)
    }

    @Test("Tree walks descend into the children of non-CONTAINER items")
    func treeWalksDescendIntoNestedChildren() throws {
        let document = measurementGroupDocument()
        // Root children: Imaging Measurements, Measurement Group, TEXT, NUM, SCOORD, IMAGE
        #expect(document.contentItemCount == 6)
        #expect(document.findSpatialCoordinateItems().count == 1)
        #expect(document.findImageItems().count == 1)

        let visited = Array(document.rootContent.contentTreeSequence()).map(\.valueType)
        #expect(visited.contains(.scoord) && visited.contains(.image))

        let numeric = try #require(document.allContentItems.first { $0.valueType == .num })
        #expect(numeric.children?.count == 1)
        #expect(numeric[0]?.valueType == .scoord)
        #expect(numeric[0]?[0]?.valueType == .image)

        let path = try SRPath(pathString: "/Imaging Measurements/Measurement Group/Long Axis/[0]/[0]")
        #expect(document.rootContent.item(at: path)?.asImage?.imageReference == image)
    }

    @Test("MeasurementExtractor: ROI from a NUM's nested INFERRED FROM SCOORD, image from its SELECTED FROM child")
    func measurementExtractorReadsNestedROI() throws {
        let parsed = try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: measurementGroupDocument()))
        let rois = MeasurementExtractor().extractROIs(from: parsed)
        let roi = try #require(rois.first { $0.spatialCoordinates != nil })
        #expect(roi.measurements.map(\.value) == [12.5])
        #expect(roi.imageReference == image)
        #expect(roi.spatialCoordinates?.imageReference == image)
        #expect(rois.filter { $0.spatialCoordinates != nil }.count == 1)
    }

    // MARK: - CAD extraction: nested and legacy sibling layouts

    /// The layout DICOMKit wrote before D31: every non-CONTAINER item's children written as
    /// the siblings that follow it (pre-order), CONTAINER contents kept
    private func siblingLayout(_ items: [AnyContentItem]) -> [AnyContentItem] {
        items.flatMap { item -> [AnyContentItem] in
            if item.isContainer {
                return [item.withContentItems(siblingLayout(item.contentItems))]
            }
            return [item.withContentItems([])] + siblingLayout(item.contentItems)
        }
    }

    private func siblingDocument(_ document: SRDocument) -> SRDocument {
        let root = document.rootContent
        let flatRoot = ContainerContentItem(
            conceptName: root.conceptName,
            continuityOfContent: root.continuityOfContent,
            contentItems: siblingLayout(root.contentItems),
            templateIdentifier: root.templateIdentifier,
            mappingResource: root.mappingResource
        )
        return SRDocument(sopClassUID: document.sopClassUID, sopInstanceUID: document.sopInstanceUID,
                          documentTitle: document.documentTitle, rootContent: flatRoot)
    }

    private func roundTrip(_ document: SRDocument) throws -> SRDocument {
        try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: document))
    }

    private func mammographyCAD() throws -> SRDocument {
        let shape = CADDescriptor(
            conceptName: CodedConcept(codeValue: "107644003", codingSchemeDesignator: "SCT", codeMeaning: "Shape"),
            value: CodedConcept(codeValue: "129734002", codingSchemeDesignator: "SCT", codeMeaning: "Irregular")
        )
        return try MammographyCADSRBuilder()
            .withPatientID("P1")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.1.0", manufacturer: "Example")
            .addFinding(CADFinding(type: .mass, probability: 0.85, location: .circle2D(centerX: 20, centerY: 30, radius: 5, imageReference: image),
                                   descriptors: [shape]))
            .addFinding(type: .calcification, probability: 0.4, location: .point2D(x: 1, y: 2, imageReference: image))
            .build()
    }

    private func chestCAD() throws -> SRDocument {
        try ChestCADSRBuilder()
            .withPatientID("P1")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(algorithmName: "ChestCAD", algorithmVersion: "3.0.0", manufacturer: "Example")
            .addFinding(type: .nodule, probability: 0.75, location: .roi2D(points: [0, 0, 10, 0, 10, 10, 0, 10], imageReference: image))
            .addFinding(type: .mass, probability: 0.6, location: .point2D(x: 5, y: 6, imageReference: image))
            .build()
    }

    @Test("Mammography CAD: TID 4006 rows 2-8 are nested in the Single Image Finding CODE after a round trip")
    func mammographyFindingChildrenNested() throws {
        let parsed = try roundTrip(try mammographyCAD())
        let summary = try #require(parsed.rootContent.contentItems.first { $0.conceptName?.codeValue == "111017" })
        let impression = try #require(summary.contentItems.first?.asContainer)
        let finding = try #require(impression.contentItems.first { $0.conceptName?.codeValue == "111059" })
        #expect(finding.relationshipType == .contains)
        #expect(finding.contentItems.contains { $0.conceptName?.codeValue == "111047" && $0.relationshipType == .hasProperties })
        let center = try #require(finding.contentItems.first { $0.conceptName?.codeValue == "111010" })
        #expect(center.contentItems.map(\.relationshipType) == [.selectedFrom])
        // Nothing after the finding CODE in the impression container: its rows are its children
        #expect(impression.contentItems.last?.conceptName?.codeValue == "111059")
    }

    @Test("Mammography CAD: the pre-D31 sibling layout extracts the same findings as the nested one")
    func mammographyLegacySiblingLayoutExtracts() throws {
        let nested = try roundTrip(try mammographyCAD())
        let legacy = try roundTrip(siblingDocument(try mammographyCAD()))
        // The legacy document really is flat: the finding CODE carries no children
        #expect(legacy.allContentItems.filter { !$0.isContainer }.allSatisfy { $0.contentItems.isEmpty })

        let fromNested = try CADFindings.extract(from: nested)
        let fromLegacy = try CADFindings.extract(from: legacy)
        #expect(fromNested.findings.count == 2)
        #expect(fromLegacy.findings == fromNested.findings)
        #expect(fromLegacy.language == fromNested.language)
        #expect(fromLegacy.imageLibrary == fromNested.imageLibrary)
        #expect(fromLegacy.processingAndFindingsSummary == fromNested.processingAndFindingsSummary)
        #expect(fromLegacy.summaryOfDetections == fromNested.summaryOfDetections)
        #expect(fromLegacy.detectionsPerformed == fromNested.detectionsPerformed)
        #expect(fromLegacy.processingInfo == fromNested.processingInfo)

        let mass = try #require(fromNested.findings.first)
        #expect(mass.findingType == FindingType.mass.concept)
        #expect(abs((mass.probability ?? 0) - 0.85) < 0.001)
        #expect(mass.imageReference == image)
        #expect(mass.characteristics.map(\.codeValue) == ["129734002"])
    }

    @Test("Chest CAD: TID 4104 findings nested INFERRED FROM the TID 4101 CODE; the sibling layout still extracts")
    func chestNestedAndLegacySiblingLayouts() throws {
        let nested = try roundTrip(try chestCAD())
        let summary = try #require(nested.rootContent.contentItems.first { $0.conceptName?.codeValue == "111017" })
        #expect(summary.contentItems.map { $0.conceptName?.codeValue } == ["111059", "111059"])
        #expect(summary.contentItems.allSatisfy { $0.relationshipType == .inferredFrom && !$0.contentItems.isEmpty })

        let legacy = try roundTrip(siblingDocument(try chestCAD()))
        #expect(legacy.rootContent.contentItems.filter { $0.conceptName?.codeValue == "111059" }.count == 2)

        let fromNested = try CADFindings.extract(from: nested)
        let fromLegacy = try CADFindings.extract(from: legacy)
        #expect(fromNested.findings.count == 2)
        #expect(fromLegacy.findings == fromNested.findings)
        #expect(fromLegacy.detectionsPerformed == fromNested.detectionsPerformed)
    }

    // MARK: - Measurement report

    @Test("TID 1204 row 2 and TID 1501 row 7 round-trip nested and extract")
    func measurementReportNestedRowsRoundTrip() throws {
        let document = try MeasurementReportBuilder()
            .withLanguage(CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English"),
                          country: CodedConcept(codeValue: "US", codingSchemeDesignator: "ISO3166_1", codeMeaning: "United States"))
            .addMeasurementGroup(MeasurementGroupData(
                trackingIdentifier: "L1",
                trackingUID: "1.2.3.4",
                findingSite: CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver"),
                laterality: CodedConcept(codeValue: "7771000", codingSchemeDesignator: "SCT", codeMeaning: "Left"),
                contents: [MeasurementGroupContentHelper.lengthMM(value: 3)]
            ))
            .build()
        let dataSet = try SRDocumentSerializer().serialize(document: document)
        let rootItems = try #require(dataSet[.contentSequence]?.sequenceItems)
        // TID 1204 row 2 is inside the row 1 item, not a root-level item
        let language = try #require(rootItems.first)
        #expect(!rootItems.contains { $0[.conceptNameCodeSequence]?.sequenceItems?.first?.string(for: .codeValue) == "121046" })
        let country = try #require(language[.contentSequence]?.sequenceItems?.first)
        #expect(country[.conceptNameCodeSequence]?.sequenceItems?.first?.string(for: .codeValue) == "121046")
        #expect(country.string(for: .relationshipType) == "HAS CONCEPT MOD")

        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        #expect(parsed.rootContent == document.rootContent)
        let report = try MeasurementReport.extract(from: parsed)
        #expect(report.countryOfLanguage?.codeValue == "US")
        let group = try #require(report.measurementGroups.first)
        #expect(group.findingSite?.codeValue == "10200004")
        #expect(group.qualitativeEvaluations.isEmpty)
    }

    // MARK: - Template validation of the builders' output

    @Test("MeasurementReportBuilder output with TID 1204 row 2 and TID 1501 row 7 nested validates against TID 1500")
    func builderOutputValidatesAgainstTemplates() throws {
        let report = try MeasurementReportBuilder()
            .withLanguage(CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English"),
                          country: CodedConcept(codeValue: "US", codingSchemeDesignator: "ISO3166_1", codeMeaning: "United States"))
            .addMeasurementGroup(MeasurementGroupData(
                trackingIdentifier: "L1",
                trackingUID: "1.2.3.4",
                findingSite: CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver"),
                laterality: CodedConcept(codeValue: "7771000", codingSchemeDesignator: "SCT", codeMeaning: "Left"),
                contents: [MeasurementGroupContentHelper.lengthMM(value: 3)]
            ))
            .build()
        let tid1500 = TemplateValidator(mode: .strict).validate(AnyContentItem(report.rootContent), against: .measurementReport)
        #expect(tid1500.isFullyCompliant, Comment(rawValue: tid1500.violations.map(\.description).joined(separator: "\n")))

    }
}
