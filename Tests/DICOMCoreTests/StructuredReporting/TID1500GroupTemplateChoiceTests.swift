import Testing
import Foundation
@testable import DICOMCore

/// D52: PS3.16 2026a TID 1500 rows 7, 8 and 9 INCLUDE TID 1410, 1411 and 1501, whose row 1 is the
/// same (125007, DCM, "Measurement Group") CONTAINER. Each describes a different pattern of target
/// content items of that container (PS3.16 §6.2.2), so a group is checked against the included
/// template whose pattern describes it, not always against the first (TID 1410).
@Suite("TID 1500 checks each Measurement Group against the template it follows (D52)")
struct TID1500GroupTemplateChoiceTests {

    private func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    private func sct(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "SCT", codeMeaning: meaning)
    }

    private let ct = "1.2.840.10008.5.1.4.1.1.2"
    private let rtStructureSet = "1.2.840.10008.5.1.4.1.1.481.3"
    private let segmentation = "1.2.840.10008.5.1.4.1.1.66.4"

    private var trackingIdentifier: AnyContentItem {
        .text(conceptName: dcm("112039", "Tracking Identifier"), value: "Lesion 1", relationshipType: .hasObsContext)
    }

    private var trackingUID: AnyContentItem {
        AnyContentItem(UIDRefContentItem(conceptName: dcm("112040", "Tracking Unique Identifier"),
                                         uidValue: "1.2.3.4.200", relationshipType: .hasObsContext))
    }

    private var longAxis: AnyContentItem {
        .numeric(conceptName: sct("103339001", "Long Axis"), value: 21.5,
                 units: CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm"),
                 relationshipType: .contains)
    }

    private func image(_ concept: CodedConcept?, _ relationship: RelationshipType, uid: String = "1.2.3.9") -> AnyContentItem {
        AnyContentItem(ImageContentItem(conceptName: concept, sopClassUID: ct, sopInstanceUID: uid,
                                        relationshipType: relationship))
    }

    private func scoord(_ concept: CodedConcept?, sourceImage: Bool) -> AnyContentItem {
        AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: concept, graphicType: .polyline, graphicData: [1, 1, 20, 20, 1, 20, 1, 1],
            relationshipType: .contains,
            contentItems: sourceImage ? [image(nil, .selectedFrom)] : []
        ))
    }

    /// TID 1410 row 8b / TID 1411 row 12b, with or without its row 8c / 12c child
    private func regionInSpace(identifier: Bool) -> AnyContentItem {
        AnyContentItem(CompositeContentItem(
            conceptName: dcm("130488", "Region in Space"), sopClassUID: rtStructureSet, sopInstanceUID: "1.2.3.50",
            relationshipType: .contains,
            contentItems: identifier
                ? [.text(conceptName: dcm("130489", "Referenced Region of Interest Identifier"), value: "1",
                         relationshipType: .hasProperties)]
                : []
        ))
    }

    private func group(_ items: [AnyContentItem]) -> AnyContentItem {
        .container(conceptName: dcm("125007", "Measurement Group"), items: items, relationshipType: .contains)
    }

    private func report(_ groups: [AnyContentItem]) -> AnyContentItem {
        .container(
            conceptName: dcm("126000", "Imaging Measurement Report"),
            items: [.container(conceptName: dcm("126010", "Imaging Measurements"), items: groups,
                               relationshipType: .contains)]
        )
    }

    private func validate(_ groups: [AnyContentItem]) -> TemplateValidationResult {
        TemplateValidator(mode: .strict).validate([report(groups)], against: .measurementReport)
    }

    private func describe(_ result: TemplateValidationResult) -> Comment {
        Comment(rawValue: result.violations.map(\.description).joined(separator: "\n"))
    }

    // MARK: - TID 1501

    /// TID 1501 rows 2, 3, 5, 6-7, 10 (→ TID 300), 10c-10d
    private func tid1501Group(sourceImage: Bool) -> AnyContentItem {
        group([
            trackingIdentifier,
            trackingUID,
            .code(conceptName: sct("370129005", "Measurement Method"),
                  value: CodedConcept(codeValue: "RID1", codingSchemeDesignator: "99TEST", codeMeaning: "Manual"),
                  relationshipType: .hasConceptMod),
            AnyContentItem(CodeContentItem(
                conceptName: sct("363698007", "Finding Site"), conceptCode: sct("10200004", "Liver"),
                relationshipType: .hasConceptMod,
                contentItems: [.code(conceptName: sct("272741003", "Laterality"), value: sct("7771000", "Left"),
                                     relationshipType: .hasConceptMod)]
            )),
            longAxis,
            scoord(nil, sourceImage: sourceImage),
        ])
    }

    @Test("The three Measurement Group rows tie on the concept, so the item is checked against each")
    func threeRowsTie() {
        let level = TemplateMatcher.expand(
            TemplateMatcher.tree(TID1500MeasurementReport.rows),
            template: TID1500MeasurementReport.self, parameters: [:], relationship: nil,
            groups: [], repeatable: false, visited: ["1500"]
        )
        let imagingMeasurements = level.slots[0].node.children.first { $0.row.rowID == "6" }!
        let groupLevel = TemplateMatcher.expand(
            imagingMeasurements.children, template: TID1500MeasurementReport.self, parameters: [:],
            relationship: nil, groups: [], repeatable: false, visited: ["1500"]
        )
        let candidates = TemplateMatcher.bestSlots(for: tid1501Group(sourceImage: true), in: groupLevel.slots)
        #expect(candidates.map { groupLevel.slots[$0].template.identifier } ==
                [.planarROIMeasurements, .volumetricROIMeasurements, .measurementGroup])
        #expect(TemplateMatcher.bestSlot(for: tid1501Group(sourceImage: true), in: groupLevel.slots) == candidates.first)
    }

    @Test("A TID 1501 group validates with no violations through TID 1500 row 9")
    func tid1501GroupIsClean() {
        let result = validate([tid1501Group(sourceImage: true)])
        #expect(result.isFullyCompliant, describe(result))
    }

    @Test("A TID 1501 SCOORD without its row 10d source image is reported through TID 1500")
    func tid1501ScoordWithoutSourceIsReported() {
        let result = validate([tid1501Group(sourceImage: false)])
        #expect(result.errors.map(\.templateRowID) == ["10d"], describe(result))
        // The group checked on its own against TID 1501 agrees
        let direct = TemplateValidator(mode: .strict).validate(tid1501Group(sourceImage: false), against: .measurementGroup)
        #expect(direct.errors.map(\.templateRowID) == ["10d"], describe(direct))
    }

    // MARK: - TID 1410 and TID 1411

    @Test("A TID 1410 group is still checked against TID 1410 (row 8c under row 8b)")
    func tid1410GroupUsesTID1410() {
        let valid = group([
            trackingIdentifier, trackingUID,
            image(dcm("121214", "Referenced Segmentation Frame"), .contains, uid: "1.2.3.60"),
            image(dcm("121233", "Source image for segmentation"), .contains),
            longAxis,
        ])
        let clean = validate([valid])
        #expect(clean.isFullyCompliant, describe(clean))

        // Row 7 (121214) is a TID 1410 concept; the Region in Space without its row 8c child is
        // reported as TID 1410 row 8c, not TID 1411 row 12c, and not missed as TID 1501 content
        let broken = group([
            trackingIdentifier,
            image(dcm("121214", "Referenced Segmentation Frame"), .contains, uid: "1.2.3.60"),
            regionInSpace(identifier: false),
        ])
        let result = validate([broken])
        #expect(result.errors.map(\.templateRowID) == ["8c"], describe(result))
    }

    @Test("A TID 1411 group is checked against TID 1411 (row 12c under row 12b)")
    func tid1411GroupUsesTID1411() {
        let segment = AnyContentItem(ImageContentItem(
            conceptName: dcm("121191", "Referenced Segment"), sopClassUID: segmentation, sopInstanceUID: "1.2.3.70",
            relationshipType: .contains))
        let sourceSeries = AnyContentItem(UIDRefContentItem(
            conceptName: dcm("121232", "Source series for segmentation"), uidValue: "1.2.3.80", relationshipType: .contains))

        let clean = validate([group([trackingIdentifier, trackingUID, segment, sourceSeries, longAxis])])
        #expect(clean.isFullyCompliant, describe(clean))

        let result = validate([group([trackingIdentifier, segment, sourceSeries, regionInSpace(identifier: false)])])
        #expect(result.errors.map(\.templateRowID) == ["12c"], describe(result))
    }

    @Test("Groups of different templates in one report are each checked against their own")
    func mixedGroups() {
        let planar = group([trackingIdentifier, scoord(dcm("111030", "Image Region"), sourceImage: false)])
        let result = validate([planar, tid1501Group(sourceImage: false)])
        // TID 1410 row 6 (the SCOORD's SELECTED FROM IMAGE) and TID 1501 row 10d
        #expect(Set(result.errors.compactMap(\.templateRowID)) == ["6", "10d"], describe(result))
        #expect(result.errors.count == 2, describe(result))
    }
}
