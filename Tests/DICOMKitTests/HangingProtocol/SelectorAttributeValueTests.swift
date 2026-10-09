//
//  SelectorAttributeValueTests.swift
//  DICOMKitTests
//
//  Image Set Selector values travel in Selector Attribute VR (0072,0050) plus
//  the matching Selector xx Value element (0072,005E–0083), per PS3.3
//  Table C.23.4-1 — never under the selected attribute's own tag.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class SelectorAttributeValueTests: XCTestCase {
    
    private func tag(_ g: UInt16, _ e: UInt16) -> Tag { Tag(group: g, element: e) }
    
    /// Serialises one selector and returns its item from (0072,0022).
    private func serializedItem(_ selector: ImageSetSelector) throws -> SequenceItem {
        let hp = HangingProtocol(name: "Sel", imageSets: [ImageSetDefinition(number: 1, selectors: [selector])])
        let ds = try HangingProtocolSerializer().serialize(protocol: hp)
        let imageSet = try XCTUnwrap(ds.sequence(for: tag(0x0072, 0x0020))?.first)
        return try XCTUnwrap(imageSet[tag(0x0072, 0x0022)]?.sequenceItems?.first)
    }
    
    private func roundTrip(_ selector: ImageSetSelector) throws -> ImageSetSelector {
        let hp = HangingProtocol(name: "Sel", imageSets: [ImageSetDefinition(number: 1, selectors: [selector])])
        let ds = try HangingProtocolSerializer().serialize(protocol: hp)
        return try XCTUnwrap(HangingProtocolParser().parse(from: ds).imageSets.first?.selectors.first)
    }
    
    /// Builds a selector item the way a third-party SCP would write it.
    private func parseItem(_ elements: [DataElement]) throws -> ImageSetSelector {
        var ds = DataSet()
        ds[.sopClassUID] = DataElement.string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.38.1")
        ds[.sopInstanceUID] = DataElement.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3")
        ds[.hangingProtocolName] = DataElement.string(tag: .hangingProtocolName, vr: .SH, value: "Sel")
        ds[.hangingProtocolLevel] = DataElement.string(tag: .hangingProtocolLevel, vr: .CS, value: "SITE")
        ds[.hangingProtocolCreator] = DataElement.string(tag: .hangingProtocolCreator, vr: .LO, value: "T")
        ds[.hangingProtocolCreationDateTime] = DataElement.string(tag: .hangingProtocolCreationDateTime, vr: .DT, value: "20240101")
        ds[.numberOfPriorsReferenced] = DataElement.uint16(tag: .numberOfPriorsReferenced, value: 0)
        var imageSet = DataSet()
        imageSet[.imageSetNumber] = DataElement.uint16(tag: .imageSetNumber, value: 1)
        imageSet.setSequence([SequenceItem(elements: elements)], for: .imageSetSelectorSequence)
        ds.setSequence([SequenceItem(elements: imageSet.allElements)], for: .imageSetsSequence)
        return try XCTUnwrap(HangingProtocolParser().parse(from: ds).imageSets.first?.selectors.first)
    }
    
    // MARK: - Serialiser
    
    func test_csAttribute_writesVRAndSelectorCSValue_notTheAttributeTag() throws {
        let item = try serializedItem(ImageSetSelector(attribute: .modality, values: ["CT", "MR"]))
        
        XCTAssertEqual(item[tag(0x0072, 0x0026)]?.attributeTagValue, .modality, "Selector Attribute (0072,0026)")
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "CS", "Selector Attribute VR (0072,0050)")
        XCTAssertEqual(item[tag(0x0072, 0x0062)]?.stringValues, ["CT", "MR"], "Selector CS Value (0072,0062)")
        XCTAssertNil(item[.modality], "values must not be written under the attribute's own tag")
        XCTAssertNil(item[tag(0x0072, 0x0066)], "no Selector LO Value for a CS attribute")
    }
    
    func test_usAttribute_writesSelectorUSValueAsBinary() throws {
        let item = try serializedItem(ImageSetSelector(attribute: .rows, values: ["512"]))
        
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "US")
        let value = try XCTUnwrap(item[tag(0x0072, 0x007A)], "Selector US Value (0072,007A)")
        XCTAssertEqual(value.vr, .US)
        XCTAssertEqual(value.uint16Value, 512)
    }
    
    func test_dsAttribute_writesSelectorDSValue() throws {
        let item = try serializedItem(ImageSetSelector(attribute: .sliceThickness, values: ["1.25"]))
        
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "DS")
        XCTAssertEqual(item[tag(0x0072, 0x0072)]?.stringValue, "1.25", "Selector DS Value (0072,0072)")
    }
    
    func test_fdAttribute_writesSelectorFDValue() throws {
        // (0018,9089) Diffusion Gradient Orientation is FD.
        let item = try serializedItem(ImageSetSelector(attribute: tag(0x0018, 0x9089), values: ["0.5", "0.25", "1"]))
        
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "FD")
        XCTAssertEqual(item[tag(0x0072, 0x0074)]?.float64Values, [0.5, 0.25, 1], "Selector FD Value (0072,0074)")
    }
    
    func test_atAttribute_writesSelectorATValue() throws {
        // (0028,0009) Frame Increment Pointer is AT.
        let item = try serializedItem(ImageSetSelector(attribute: .frameIncrementPointer, values: ["(0018,1063)"]))
        
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "AT")
        XCTAssertEqual(item[tag(0x0072, 0x0060)]?.attributeTagValue, tag(0x0018, 0x1063), "Selector AT Value (0072,0060)")
    }
    
    func test_sqAttribute_writesSelectorCodeSequenceValue() throws {
        let code = CodedConcept(codeValue: "T-D3000", codingSchemeDesignator: "SRT", codeMeaning: "Chest")
        let item = try serializedItem(ImageSetSelector(
            attribute: .anatomicRegionSequence, values: ["T-D3000"], codeValues: [code]))
        
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "SQ")
        let codeItem = try XCTUnwrap(item[tag(0x0072, 0x0080)]?.sequenceItems?.first, "Selector Code Sequence Value (0072,0080)")
        XCTAssertEqual(codeItem.string(for: tag(0x0008, 0x0100)), "T-D3000")
        XCTAssertEqual(codeItem.string(for: tag(0x0008, 0x0102)), "SRT")
        XCTAssertEqual(codeItem.string(for: tag(0x0008, 0x0104)), "Chest")
    }
    
    func test_explicitVR_overridesDictionary_forPrivateAttribute() throws {
        let item = try serializedItem(ImageSetSelector(
            attribute: tag(0x0029, 0x1010), attributeVR: .LO, values: ["VENDOR-A"]))
        
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "LO")
        XCTAssertEqual(item[tag(0x0072, 0x0066)]?.stringValue, "VENDOR-A", "Selector LO Value (0072,0066)")
    }
    
    func test_privateAttributeWithValuesAndNoVR_throws() {
        let selector = ImageSetSelector(attribute: tag(0x0029, 0x1010), values: ["X"])
        let hp = HangingProtocol(name: "Sel", imageSets: [ImageSetDefinition(number: 1, selectors: [selector])])
        
        XCTAssertThrowsError(try HangingProtocolSerializer().serialize(protocol: hp)) { error in
            guard case HangingProtocolError.invalidAttributeValue = error else {
                return XCTFail("expected invalidAttributeValue, got \(error)")
            }
        }
    }
    
    func test_nonNumericValueForUSAttribute_throws() {
        let selector = ImageSetSelector(attribute: .rows, values: ["many"])
        let hp = HangingProtocol(name: "Sel", imageSets: [ImageSetDefinition(number: 1, selectors: [selector])])
        
        XCTAssertThrowsError(try HangingProtocolSerializer().serialize(protocol: hp))
    }
    
    func test_presenceFilter_writesNoVRAndNoValueElement() throws {
        // PS3.3 Table C.23.3-1: PRESENT is a Filter-by Attribute Presence
        // (0072,0404) term of a Filter Operations Sequence (0072,0400) item;
        // Selector Attribute VR is Type 1C only with a Filter-by Operator.
        let hp = HangingProtocol(
            name: "Sel",
            imageSets: [ImageSetDefinition(number: 1)],
            displaySets: [DisplaySet(number: 1, imageSetNumber: 1, filterOperations: [
                FilterOperation(attribute: .sliceLocation, attributePresence: .present)])]
        )
        let dataSet = try HangingProtocolSerializer().serialize(protocol: hp)
        let item = try XCTUnwrap(dataSet.sequence(for: .displaySetsSequence)?[0][.filterOperationsSequence]?.sequenceItems?.first)

        XCTAssertEqual(item[tag(0x0072, 0x0026)]?.attributeTagValue, .sliceLocation)
        XCTAssertNil(item[tag(0x0072, 0x0050)])
        XCTAssertNil(item[tag(0x0072, 0x0072)])
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0404)), "PRESENT")
        XCTAssertNil(item[tag(0x0072, 0x0406)])
    }
    
    func test_sequencePointer_writesSelectorSequencePointer() throws {
        let item = try serializedItem(ImageSetSelector(
            attribute: .codeValue, sequencePointer: .anatomicRegionSequence, values: ["T-D3000"]))
        
        XCTAssertEqual(item[tag(0x0072, 0x0052)]?.attributeTagValue, .anatomicRegionSequence, "Selector Sequence Pointer (0072,0052)")
        XCTAssertEqual(item.string(for: tag(0x0072, 0x0050)), "SH")
        XCTAssertEqual(item[tag(0x0072, 0x006C)]?.stringValue, "T-D3000", "Selector SH Value (0072,006C)")
    }
    
    // MARK: - Round trip
    
    func test_roundTrip_everyVRFamily() throws {
        let cases: [ImageSetSelector] = [
            ImageSetSelector(attribute: .modality, values: ["CT", "MR"]),
            ImageSetSelector(attribute: .rows, values: ["512"]),
            ImageSetSelector(attribute: .sliceThickness, values: ["1.25"]),
            ImageSetSelector(attribute: tag(0x0018, 0x9089), values: ["0.5", "0.25", "1.0"]),
            ImageSetSelector(attribute: .frameIncrementPointer, values: ["(0018,1063)"]),
            ImageSetSelector(attribute: .seriesDescription, valueNumber: 1, values: ["CHEST"]),
            ImageSetSelector(attribute: tag(0x0029, 0x1010), attributeVR: .OB, values: ["DEADBEEF"]),
            ImageSetSelector(attribute: tag(0x0029, 0x1011), attributeVR: .SV, values: ["-5", "9000000000"]),
            ImageSetSelector(attribute: tag(0x0029, 0x1012), attributeVR: .UV, values: ["18446744073709551615"]),
            ImageSetSelector(attribute: tag(0x0029, 0x1013), attributeVR: .UT, values: ["a\\b"]),
            ImageSetSelector(attribute: .codeValue, sequencePointer: .anatomicRegionSequence, values: ["T-D3000"], usageFlag: .noMatch),
        ]
        for selector in cases {
            let back = try roundTrip(selector)
            XCTAssertEqual(back.attribute, selector.attribute, "\(selector.attribute)")
            XCTAssertEqual(back.values, selector.values, "\(selector.attribute)")
            XCTAssertEqual(back.sequencePointer, selector.sequencePointer, "\(selector.attribute)")
            // Selector Value Number (0072,0028) is Type 1 here (PS3.3 Table
            // C.23.1-1): nil is written as 0, "any value"
            XCTAssertEqual(back.valueNumber, selector.valueNumber ?? 0, "\(selector.attribute)")
            XCTAssertEqual(back.usageFlag, selector.usageFlag, "\(selector.attribute)")
            XCTAssertNotNil(back.attributeVR, "\(selector.attribute): VR read back from (0072,0050)")
        }
    }
    
    func test_roundTrip_codeSequence() throws {
        let code = CodedConcept(codeValue: "T-D3000", codingSchemeDesignator: "SRT", codeMeaning: "Chest", codingSchemeVersion: "1")
        let back = try roundTrip(ImageSetSelector(attribute: .anatomicRegionSequence, codeValues: [code]))
        
        XCTAssertEqual(back.attributeVR, .SQ)
        XCTAssertEqual(back.codeValues, [code])
        XCTAssertEqual(back.values, ["T-D3000"], "the matcher sees the Code Value")
    }
    
    // MARK: - Parser, foreign layouts
    
    func test_parse_selectorValueWithoutVRElement_usesTheValueTagToInferVR() throws {
        let selector = try parseItem([
            DataElement.attributeTag(tag: .selectorAttribute, value: .rows),
            DataElement.uint16(tag: tag(0x0072, 0x007A), value: 1024),
            DataElement.string(tag: .imageSetSelectorUsageFlag, vr: .CS, value: "MATCH"),
        ])
        
        XCTAssertEqual(selector.attributeVR, .US)
        XCTAssertEqual(selector.values, ["1024"])
    }
    
    func test_parse_legacyDICOMKitLayout_valuesUnderAttributeTag_stillReads() throws {
        let selector = try parseItem([
            DataElement.attributeTag(tag: .selectorAttribute, value: .modality),
            DataElement.string(tag: .modality, vr: .LO, value: "CT\\MR"),
            DataElement.string(tag: .imageSetSelectorUsageFlag, vr: .CS, value: "MATCH"),
        ])
        
        XCTAssertNil(selector.attributeVR, "a legacy item states no VR")
        XCTAssertEqual(selector.values, ["CT", "MR"])
    }
    
    func test_parse_vrElementWinsOverAttributeTag() throws {
        let selector = try parseItem([
            DataElement.attributeTag(tag: .selectorAttribute, value: .modality),
            DataElement.string(tag: .selectorAttributeVR, vr: .CS, value: "CS"),
            DataElement.strings(tag: tag(0x0072, 0x0062), vr: .CS, values: ["PT"]),
            DataElement.string(tag: .modality, vr: .LO, value: "CT"),
            DataElement.string(tag: .imageSetSelectorUsageFlag, vr: .CS, value: "NO_MATCH"),
        ])
        
        XCTAssertEqual(selector.attributeVR, .CS)
        XCTAssertEqual(selector.values, ["PT"])
        XCTAssertEqual(selector.usageFlag, .noMatch)
    }
    
    // MARK: - VR ↔ tag table
    
    func test_valueTagTable_coversEveryVR_andIsInvertible() {
        for vr in VR.allCases {
            let valueTag = SelectorAttributeValueCoding.valueTag(for: vr)
            XCTAssertEqual(valueTag.group, 0x0072, "\(vr)")
            XCTAssertTrue((0x005E...0x0083).contains(valueTag.element), "\(vr): \(valueTag)")
            XCTAssertEqual(SelectorAttributeValueCoding.vr(forValueTag: valueTag), vr)
        }
        XCTAssertEqual(SelectorAttributeValueCoding.valueTag(for: .CS), tag(0x0072, 0x0062))
        XCTAssertEqual(SelectorAttributeValueCoding.valueTag(for: .US), tag(0x0072, 0x007A))
        XCTAssertEqual(SelectorAttributeValueCoding.valueTag(for: .SQ), tag(0x0072, 0x0080))
        XCTAssertEqual(SelectorAttributeValueCoding.valueTag(for: .UV), tag(0x0072, 0x0083))
        XCTAssertNil(SelectorAttributeValueCoding.vr(forValueTag: tag(0x0072, 0x0026)))
    }
}
