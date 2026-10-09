import Testing
import Foundation
@testable import DICOMKit
@testable import DICOMCore

/// P-MGC: `MeasurementGroupContent` cases that carry the rows nested under a Measurement Group
/// item, written in that item's Content Sequence (PS3.3 2026a Table C.17-6):
/// - PS3.16 2026a TID 1501 row 10 → TID 300 row 1 (NUM), row 1b → TID 301 rows 2-7 and 13 →
///   TID 320 rows 1, 3-4 and 6 (`measurementWithContent`);
/// - TID 1501 rows 10c/10d, SCOORD with SELECTED FROM IMAGE (`spatialCoordinatesOnImage`);
/// - TID 1501 rows 11/11b, CODE with HAS CONCEPT MOD CODE (`qualitativeEvaluationWithModifiers`);
/// - TID 1501 row 8, Topographical modifier under the Finding Site (`MeasurementGroupData`).
@Suite("Measurement group children (P-MGC, PS3.16 TID 1501/300/301/320)")
struct MeasurementGroupChildrenTests {

    private func sct(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "SCT", codeMeaning: meaning)
    }

    private let ctImage = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.6.7.8.9")
    private let otherImage = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.4.5.6.7.8.10",
                                            frameNumbers: [2])
    private let millimeter = UCUMUnit.millimeter.concept
    private let longAxis = CodedConcept(codeValue: "103339001", codingSchemeDesignator: "SCT", codeMeaning: "Long Axis")
    private let liver = CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver")
    private let left = CodedConcept(codeValue: "7771000", codingSchemeDesignator: "SCT", codeMeaning: "Left")
    private let upper = CodedConcept(codeValue: "261183002", codingSchemeDesignator: "SCT", codeMeaning: "Upper")
    private let manual = CodedConcept(codeValue: "RID1", codingSchemeDesignator: "99TEST", codeMeaning: "Manual caliper")
    private let maximum = CodedConcept(codeValue: "56851009", codingSchemeDesignator: "SCT", codeMeaning: "Maximum")

    /// TID 300 row 1 NUM with every TID 301 row the builder writes
    private var measurementWithContent: MeasurementGroupContent {
        .measurementWithContent(
            conceptName: longAxis,
            value: 21.5,
            units: millimeter,
            content: MeasurementContent(
                modifiers: [MeasurementConceptModifier(conceptName: sct("246205007", "Quantity"),
                                                       value: sct("258683005", "Weight"))],
                method: manual,
                derivation: maximum,
                findingSites: [MeasurementFindingSite(site: liver, laterality: left, topographicalModifier: upper)],
                sources: [
                    .image(purpose: nil, image: ctImage),
                    .spatialCoordinates(purpose: nil, graphicType: .polyline, graphicData: [1, 1, 20, 20],
                                        sourceImage: ctImage),
                    .spatialCoordinates3D(purpose: nil, graphicType: .point, graphicData: [1, 2, 3],
                                          frameOfReferenceUID: "1.2.3.4.100"),
                ]
            )
        )
    }

    private var roi: MeasurementGroupContent {
        .spatialCoordinatesOnImage(conceptName: nil, graphicType: .circle, graphicData: [10, 10, 15, 10],
                                   sourceImage: otherImage)
    }

    private var evaluation: MeasurementGroupContent {
        .qualitativeEvaluationWithModifiers(
            conceptName: sct("116677004", "Margin"),
            value: sct("129735001", "Spiculated"),
            modifiers: [MeasurementConceptModifier(conceptName: sct("246205007", "Quantity"), value: sct("260411009", "Presence"))]
        )
    }

    private var contents: [MeasurementGroupContent] {
        [measurementWithContent, roi, evaluation, .text(conceptName: sct("371524004", "Clinical report"), value: "stable")]
    }

    private func report() throws -> SRDocument {
        try MeasurementReportBuilder()
            .withPatientID("P1")
            .addImageLibraryEntry(sopClassUID: ctImage.sopReference.sopClassUID,
                                  sopInstanceUID: ctImage.sopReference.sopInstanceUID)
            .addMeasurementGroup(MeasurementGroupData(
                trackingIdentifier: "Lesion 1",
                trackingUID: "1.2.3.4.200",
                findingSite: liver,
                laterality: left,
                topographicalModifier: upper,
                contents: contents
            ))
            .build()
    }

    private func conceptCode(_ item: SequenceItem) -> String? {
        item[.conceptNameCodeSequence]?.sequenceItems?.first?.string(for: .codeValue)
    }

    private func groupItems(_ dataSet: DataSet) throws -> [SequenceItem] {
        let rootItems = try #require(dataSet[.contentSequence]?.sequenceItems)
        let measurements = try #require(rootItems.first { conceptCode($0) == "126010" })
        let group = try #require(measurements[.contentSequence]?.sequenceItems?.first)
        return try #require(group[.contentSequence]?.sequenceItems)
    }

    // MARK: - Serializer and parser

    @Test("TID 300/301/320: the NUM's children are in its Content Sequence, in TID 301 row order, and round-trip")
    func measurementWithContentNestsTID301() throws {
        let document = try report()
        let dataSet = try SRDocumentSerializer().serialize(document: document)
        let items = try groupItems(dataSet)

        let num = try #require(items.first { $0.string(for: .valueType) == "NUM" })
        #expect(num.string(for: .relationshipType) == "CONTAINS")
        #expect(items.filter { $0.string(for: .valueType) == "NUM" }.count == 1)
        let children = try #require(num[.contentSequence]?.sequenceItems)
        // TID 301 rows 2, 3, 4, 5, then row 13 → TID 320 rows 1, 3, 6
        #expect(children.map { $0.string(for: .relationshipType) } == [
            "HAS CONCEPT MOD", "HAS CONCEPT MOD", "HAS CONCEPT MOD", "HAS CONCEPT MOD",
            "INFERRED FROM", "INFERRED FROM", "INFERRED FROM",
        ])
        #expect(children.map { $0.string(for: .valueType) } == ["CODE", "CODE", "CODE", "CODE", "IMAGE", "SCOORD", "SCOORD3D"])
        #expect(children[0...3].map { conceptCode($0) } == ["246205007", "370129005", "121401", "363698007"])

        // TID 301 rows 6-7 under the row 5 Finding Site
        let siteChildren = try #require(children[3][.contentSequence]?.sequenceItems)
        #expect(siteChildren.map { conceptCode($0) } == ["272741003", "106233006"])
        #expect(siteChildren.allSatisfy { $0.string(for: .relationshipType) == "HAS CONCEPT MOD" })

        // TID 320 row 4 under the row 3 SCOORD; rows 1 and 6 have no children
        let scoordChildren = try #require(children[5][.contentSequence]?.sequenceItems)
        #expect(scoordChildren.count == 1)
        #expect(scoordChildren[0].string(for: .relationshipType) == "SELECTED FROM")
        #expect(scoordChildren[0].string(for: .valueType) == "IMAGE")
        #expect(children[4][.contentSequence] == nil)
        #expect(children[6][.contentSequence] == nil)

        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        #expect(parsed.rootContent == document.rootContent)
    }

    @Test("TID 1501 rows 10c/10d: the SCOORD carries its SELECTED FROM IMAGE child and round-trips")
    func spatialCoordinatesOnImageNestsRow10d() throws {
        let document = try report()
        let dataSet = try SRDocumentSerializer().serialize(document: document)
        let items = try groupItems(dataSet)

        let scoords = items.filter { $0.string(for: .valueType) == "SCOORD" }
        #expect(scoords.count == 1)
        let scoord = try #require(scoords.first)
        #expect(scoord.string(for: .relationshipType) == "CONTAINS")
        let children = try #require(scoord[.contentSequence]?.sequenceItems)
        #expect(children.count == 1)
        #expect(children[0].string(for: .relationshipType) == "SELECTED FROM")
        #expect(children[0].string(for: .valueType) == "IMAGE")
        // No group-level IMAGE (row 10b) is written for it
        #expect(!items.contains { $0.string(for: .valueType) == "IMAGE" })

        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        let parsedScoord = try #require(parsed.findSpatialCoordinateItems().first { $0.relationshipType == .contains })
        #expect(parsedScoord.contentItems.first?.asImage?.imageReference == otherImage)
    }

    @Test("TID 1501 rows 11/11b and rows 6-8: modifiers nested under the evaluation CODE and the Finding Site")
    func qualitativeModifiersAndTopographicalModifierNest() throws {
        let dataSet = try SRDocumentSerializer().serialize(document: try report())
        let items = try groupItems(dataSet)

        let evaluation = try #require(items.first { conceptCode($0) == "116677004" })
        #expect(evaluation.string(for: .relationshipType) == "CONTAINS")
        let modifiers = try #require(evaluation[.contentSequence]?.sequenceItems)
        #expect(modifiers.map { conceptCode($0) } == ["246205007"])
        #expect(modifiers[0].string(for: .relationshipType) == "HAS CONCEPT MOD")
        #expect(modifiers[0].string(for: .valueType) == "CODE")

        let site = try #require(items.first { conceptCode($0) == "363698007" })
        let siteChildren = try #require(site[.contentSequence]?.sequenceItems)
        #expect(siteChildren.map { conceptCode($0) } == ["272741003", "106233006"])
        // Neither row 7 nor row 8 is a sibling of the Finding Site
        #expect(!items.contains { ["272741003", "106233006"].contains(conceptCode($0) ?? "") })
    }

    @Test("The topographical modifier is not written without a Finding Site (row 8 has no parent)")
    func topographicalModifierNeedsFindingSite() throws {
        let document = try MeasurementReportBuilder()
            .addMeasurementGroup(MeasurementGroupData(trackingIdentifier: "L", trackingUID: "1.2.3", topographicalModifier: upper))
            .build()
        #expect(!document.allContentItems.contains { $0.conceptName?.codeValue == "106233006" })
    }

    // MARK: - Template validation

    private func measurementGroup(_ document: SRDocument) throws -> AnyContentItem {
        let measurements = try #require(document.rootContent.contentItems.first { $0.conceptName?.codeValue == "126010" })
        return try #require(measurements.contentItems.first)
    }

    @Test("Builder output using every new case validates against TID 1500, and its group against TID 1501, with no violations")
    func newCasesValidateAgainstTID1500() throws {
        let document = try report()
        let result = TemplateValidator(mode: .strict).validate(AnyContentItem(document.rootContent), against: .measurementReport)
        #expect(result.isFullyCompliant, Comment(rawValue: result.violations.map(\.description).joined(separator: "\n")))

        // TID 1500 rows 7-9 include TID 1410, 1411 and 1501, whose row 1 is the same
        // (125007, DCM) CONTAINER; since D52 the validator checks the group against the one whose
        // rows describe it (TID 1501 here). The group is also checked against TID 1501 directly,
        // whose row 10 → TID 300 → TID 301 → TID 320 rows and row 10d/11b are what these cases write.
        let group = TemplateValidator(mode: .strict).validate(try measurementGroup(document), against: .measurementGroup)
        #expect(group.isFullyCompliant, Comment(rawValue: group.violations.map(\.description).joined(separator: "\n")))

        let parsed = try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: document))
        let afterRoundTrip = TemplateValidator(mode: .strict).validate(AnyContentItem(parsed.rootContent), against: .measurementReport)
        #expect(afterRoundTrip.isFullyCompliant,
                Comment(rawValue: afterRoundTrip.violations.map(\.description).joined(separator: "\n")))
    }

    @Test("TID 1501: a SCOORD without its source image (the old case) misses row 10d; the new helper writes it")
    func legacySpatialCoordinatesMissRow10d() throws {
        let document = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "L", trackingUID: "1.2.3") {
                MeasurementGroupContentHelper.coordinates(graphicType: .point, graphicData: [1, 1])
            }
            .build()
        let result = TemplateValidator(mode: .strict).validate(try measurementGroup(document), against: .measurementGroup)
        #expect(result.errors.contains { $0.templateRowID == "10d" },
                Comment(rawValue: result.violations.map(\.description).joined(separator: "\n")))
        // D52: validating the whole report against TID 1500 finds it too (the group is checked
        // against TID 1501 through row 9, not against TID 1410 through row 7)
        let report = TemplateValidator(mode: .strict).validate(AnyContentItem(document.rootContent), against: .measurementReport)
        #expect(report.errors.map(\.templateRowID) == ["10d"],
                Comment(rawValue: report.violations.map(\.description).joined(separator: "\n")))

        let fixed = try MeasurementReportBuilder()
            .addMeasurementGroup(trackingIdentifier: "L", trackingUID: "1.2.3") {
                MeasurementGroupContentHelper.coordinates(graphicType: .point, graphicData: [1, 1], sourceImage: ctImage)
            }
            .build()
        let fixedResult = TemplateValidator(mode: .strict).validate(try measurementGroup(fixed), against: .measurementGroup)
        #expect(fixedResult.isFullyCompliant, Comment(rawValue: fixedResult.violations.map(\.description).joined(separator: "\n")))
        let fixedReport = TemplateValidator(mode: .strict).validate(AnyContentItem(fixed.rootContent), against: .measurementReport)
        #expect(fixedReport.isFullyCompliant, Comment(rawValue: fixedReport.violations.map(\.description).joined(separator: "\n")))
    }

    // MARK: - Extraction

    @Test("MeasurementReport reads the group's contents back as the builder's input after a dataset round trip")
    func extractorReadsNewCasesBack() throws {
        let parsed = try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: try report()))
        let report = try MeasurementReport.extract(from: parsed)
        let group = try #require(report.measurementGroups.first)

        #expect(group.contents == contents)
        #expect(group.findingSite == liver)
        #expect(group.laterality == left)
        #expect(group.topographicalModifier == upper)
        #expect(group.measurements.map(\.value) == [21.5])
        // The TID 1501 row 11 value is still listed; its row 11b modifier is not an evaluation
        #expect(group.qualitativeEvaluations.map(\.codeValue) == ["129735001"])
    }

    @Test("The existing cases still read back unchanged")
    func extractorReadsExistingCases() throws {
        let existing: [MeasurementGroupContent] = [
            MeasurementGroupContentHelper.lengthMM(value: 3),
            .measurements(conceptName: longAxis, values: [1, 2], units: millimeter),
            .qualitativeEvaluation(conceptName: sct("116677004", "Margin"), value: sct("129735001", "Spiculated")),
            MeasurementGroupContentHelper.imageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3.9"),
            MeasurementGroupContentHelper.coordinates(graphicType: .point, graphicData: [1, 1]),
            .spatialCoordinates3D(conceptName: nil, graphicType: .point, graphicData: [1, 2, 3], frameOfReferenceUID: "1.2.3.4"),
            .text(conceptName: sct("371524004", "Clinical report"), value: "x"),
        ]
        let document = try MeasurementReportBuilder()
            .addMeasurementGroup(MeasurementGroupData(trackingIdentifier: "L", trackingUID: "1.2.3", contents: existing))
            .build()
        let parsed = try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: document))
        let group = try #require(try MeasurementReport.extract(from: parsed).measurementGroups.first)
        #expect(group.contents == existing)
    }

    @Test("MeasurementExtractor takes ROIs and images from the NUM's TID 320 SCOORD and the group's row 10c SCOORD")
    func measurementExtractorReadsNestedSource() throws {
        let parsed = try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: try report()))
        let rois = MeasurementExtractor().extractROIs(from: parsed)
        // TID 320 rows 3-4 under the NUM
        let nested = try #require(rois.first { $0.spatialCoordinates?.graphicType == .polyline })
        #expect(nested.measurements.map(\.value) == [21.5])
        #expect(nested.spatialCoordinates?.imageReference == ctImage)
        // TID 1501 rows 10c-10d: the group-level SCOORD's image is its SELECTED FROM child
        let groupLevel = try #require(rois.first { $0.spatialCoordinates?.graphicType == .circle })
        #expect(groupLevel.imageReference == otherImage)
    }
}
