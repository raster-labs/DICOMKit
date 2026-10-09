import Testing
import Foundation
@testable import DICOMCore

/// D31: the Document Relationship Macro (PS3.3 2026a Table C.17-6) puts Content Sequence
/// (0040,A730) in every content item, so every value type carries child content items.
@Suite("Content items of every value type carry children (D31)")
struct SRContentItemChildrenTests {

    private func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    private var language: CodedConcept { dcm("121049", "Language of Content Item and Descendants") }
    private var country: CodedConcept { dcm("121046", "Country of Language") }
    private var english: CodedConcept { CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English") }
    private var unitedStates: CodedConcept { CodedConcept(codeValue: "US", codingSchemeDesignator: "ISO3166_1", codeMeaning: "United States") }

    @Test("Existing initialisers default to no children")
    func defaultsToNoChildren() {
        let code = AnyContentItem(CodeContentItem(conceptName: language, conceptCode: english))
        #expect(code.contentItems.isEmpty)
        #expect(code.children == nil)
        let container = AnyContentItem(ContainerContentItem())
        #expect(container.children == [])
    }

    @Test("Every value type stores children and withContentItems replaces them")
    func everyValueTypeStoresChildren() {
        let child = AnyContentItem(TextContentItem(textValue: "x", relationshipType: .hasProperties))
        let image = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.2", sopInstanceUID: "1.2.3")
        let items: [AnyContentItem] = [
            AnyContentItem(TextContentItem(textValue: "t")),
            AnyContentItem(CodeContentItem(conceptCode: english)),
            AnyContentItem(NumericContentItem(value: 1)),
            AnyContentItem(DateContentItem(dateValue: "20260101")),
            AnyContentItem(TimeContentItem(timeValue: "120000")),
            AnyContentItem(DateTimeContentItem(dateTimeValue: "20260101120000")),
            AnyContentItem(PersonNameContentItem(personName: "Doe^J")),
            AnyContentItem(UIDRefContentItem(uidValue: "1.2.3")),
            AnyContentItem(CompositeContentItem(sopClassUID: "1.2", sopInstanceUID: "1.2.3")),
            AnyContentItem(ImageContentItem(imageReference: image)),
            AnyContentItem(SpatialCoordinatesContentItem(graphicType: .point, graphicData: [1, 2])),
            AnyContentItem(SpatialCoordinates3DContentItem(graphicType: .point, graphicData: [1, 2, 3])),
            AnyContentItem(TemporalCoordinatesContentItem(temporalRangeType: .point, timeOffsets: [0.5])),
            AnyContentItem(ContainerContentItem()),
        ]
        for item in items {
            let parent = item.withContentItems([child])
            #expect(parent.valueType == item.valueType)
            #expect(parent.contentItems == [child], "\(item.valueType)")
            #expect(parent.children == [child])
            #expect(parent != item)
            #expect(parent.addingContentItems([child]).contentItems == [child, child])
            #expect(parent.withContentItems([]).contentItems.isEmpty)
        }
    }

    @Test("TID 1204 row 2 is matched in the Content Sequence of the row 1 CODE")
    func templateValidatorWalksChildrenOfACode() {
        let nested = AnyContentItem(CodeContentItem(
            conceptName: language, conceptCode: english, relationshipType: .hasConceptMod,
            contentItems: [AnyContentItem(CodeContentItem(conceptName: country, conceptCode: unitedStates, relationshipType: .hasConceptMod))]
        ))
        let result = TemplateValidator(mode: .strict).validate([nested], against: .languageOfContent)
        #expect(result.isFullyCompliant, Comment(rawValue: result.violations.map(\.description).joined(separator: "\n")))

        // Written as a sibling (the pre-D31 DICOMKit layout) it is extra content at the level
        // of row 1 of a non-extensible template
        let siblings = [
            AnyContentItem(CodeContentItem(conceptName: language, conceptCode: english, relationshipType: .hasConceptMod)),
            AnyContentItem(CodeContentItem(conceptName: country, conceptCode: unitedStates, relationshipType: .hasConceptMod)),
        ]
        let flat = TemplateValidator(mode: .strict).validate(siblings, against: .languageOfContent)
        #expect(!flat.isFullyCompliant)
        #expect(flat.errors.isEmpty)
    }

    @Test("A nested child that breaks its row is reported under its parent")
    func templateValidatorChecksNestedChildValues() {
        // TID 1204 row 2 is VM 1: two countries under one language item
        let child = AnyContentItem(CodeContentItem(conceptName: country, conceptCode: unitedStates, relationshipType: .hasConceptMod))
        let nested = AnyContentItem(CodeContentItem(
            conceptName: language, conceptCode: english, relationshipType: .hasConceptMod,
            contentItems: [child, child]
        ))
        let result = TemplateValidator(mode: .strict).validate([nested], against: .languageOfContent)
        #expect(result.violations.contains { $0.templateRowID == "2" })
    }
}
