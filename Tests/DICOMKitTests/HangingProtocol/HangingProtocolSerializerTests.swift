//
// HangingProtocolSerializerTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class HangingProtocolSerializerTests: XCTestCase {
    
    var serializer: HangingProtocolSerializer!
    
    override func setUp() {
        super.setUp()
        serializer = HangingProtocolSerializer()
    }
    
    // MARK: - Basic Serialization Tests
    
    func test_serialize_minimalProtocol() throws {
        let hangingProtocol = HangingProtocol(name: "Test Protocol")
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertEqual(dataSet.string(for: .hangingProtocolName), "Test Protocol")
        XCTAssertEqual(dataSet.string(for: .hangingProtocolLevel), "SINGLE_USER")   // PS3.3 Table C.23.1-1
        XCTAssertEqual(dataSet.uint16(for: .numberOfScreens), 1)
    }
    
    func test_serialize_completeProtocol() throws {
        let dateTime = DICOMDateTime(year: 2024, month: 1, day: 15)
        
        let hangingProtocol = HangingProtocol(
            name: "Complete Protocol",
            description: "Test description",
            level: .site,
            creator: "Dr. Smith",
            creationDateTime: dateTime,
            numberOfPriorsReferenced: 2,
            numberOfScreens: 2
        )
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertEqual(dataSet.string(for: .hangingProtocolName), "Complete Protocol")
        XCTAssertEqual(dataSet.string(for: .hangingProtocolDescription), "Test description")
        XCTAssertEqual(dataSet.string(for: .hangingProtocolLevel), "SITE")
        XCTAssertEqual(dataSet.string(for: .hangingProtocolCreator), "Dr. Smith")
        XCTAssertNotNil(dataSet.string(for: .hangingProtocolCreationDateTime))
        XCTAssertEqual(dataSet.uint16(for: .numberOfPriorsReferenced), 2)
        XCTAssertEqual(dataSet.uint16(for: .numberOfScreens), 2)
    }
    
    func test_serialize_protocolLevel_site() throws {
        let hangingProtocol = HangingProtocol(name: "Test", level: .site)
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertEqual(dataSet.string(for: .hangingProtocolLevel), "SITE")
    }
    
    func test_serialize_protocolLevel_group() throws {
        let hangingProtocol = HangingProtocol(name: "Test", level: .group)
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertEqual(dataSet.string(for: .hangingProtocolLevel), "USER_GROUP")
    }
    
    func test_serialize_protocolLevel_user() throws {
        let hangingProtocol = HangingProtocol(name: "Test", level: .user)

        let dataSet = try serializer.serialize(protocol: hangingProtocol)

        XCTAssertEqual(dataSet.string(for: .hangingProtocolLevel), "SINGLE_USER")
    }
    
    // MARK: - Environment Serialization Tests
    
    func test_serialize_environments_empty() throws {
        let hangingProtocol = HangingProtocol(name: "Test", environments: [])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertNil(dataSet.sequence(for: .hangingProtocolDefinitionSequence),
                     "Should not include empty environment sequence")
    }
    
    func test_serialize_environments_single() throws {
        let environment = HangingProtocolEnvironment(modality: "CT")
        let hangingProtocol = HangingProtocol(name: "Test", environments: [environment])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let envSequence = dataSet.sequence(for: .hangingProtocolDefinitionSequence)
        XCTAssertNotNil(envSequence)
        XCTAssertEqual(envSequence?.count, 1)
        
        let envItem = envSequence?[0]
        XCTAssertEqual(envItem?.string(for: .modality), "CT")
    }
    
    func test_serialize_environments_multiple() throws {
        let env1 = HangingProtocolEnvironment(modality: "CT", laterality: nil)
        let env2 = HangingProtocolEnvironment(modality: "MR", laterality: "L")
        let hangingProtocol = HangingProtocol(name: "Test", environments: [env1, env2])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let envSequence = dataSet.sequence(for: .hangingProtocolDefinitionSequence)
        XCTAssertEqual(envSequence?.count, 2)
        
        XCTAssertEqual(envSequence?[0].string(for: .modality), "CT")
        XCTAssertEqual(envSequence?[1].string(for: .modality), "MR")
        XCTAssertEqual(envSequence?[1].string(for: .laterality), "L")
    }
    
    // MARK: - User Group Serialization Tests
    
    func test_serialize_userGroups_empty() throws {
        let hangingProtocol = HangingProtocol(name: "Test", userGroups: [])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertNil(dataSet.string(for: .hangingProtocolUserGroupName))
    }
    
    func test_serialize_userGroups_single() throws {
        let hangingProtocol = HangingProtocol(name: "Test", userGroups: ["Radiology"])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertEqual(dataSet.string(for: .hangingProtocolUserGroupName), "Radiology")
    }
    
    // MARK: - Screen Definition Serialization Tests
    
    func test_serialize_screenDefinitions_empty() throws {
        let hangingProtocol = HangingProtocol(name: "Test", screenDefinitions: [])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        // Type 2 (PS3.3 Table C.23.2-1): present with zero items
        XCTAssertNotNil(dataSet[.nominalScreenDefinitionSequence])
        XCTAssertEqual(dataSet.sequence(for: .nominalScreenDefinitionSequence)?.count ?? 0, 0)
    }
    
    func test_serialize_screenDefinitions_single() throws {
        let screen = ScreenDefinition(
            verticalPixels: 1080,
            horizontalPixels: 1920,
            minimumGrayscaleBitDepth: 8
        )
        let hangingProtocol = HangingProtocol(name: "Test", screenDefinitions: [screen])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let screenSequence = dataSet.sequence(for: .nominalScreenDefinitionSequence)
        XCTAssertNotNil(screenSequence)
        XCTAssertEqual(screenSequence?.count, 1)
        
        let screenItem = screenSequence?[0]
        XCTAssertEqual(screenItem?[.numberOfVerticalPixels]?.uint16Value, 1080)
        XCTAssertEqual(screenItem?[.numberOfHorizontalPixels]?.uint16Value, 1920)
    }
    
    // MARK: - Image Set Serialization Tests
    
    func test_serialize_imageSets_empty() throws {
        let hangingProtocol = HangingProtocol(name: "Test", imageSets: [])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertNil(dataSet.sequence(for: .imageSetsSequence))
    }
    
    func test_serialize_imageSets_single() throws {
        let imageSet = ImageSetDefinition(number: 1, label: "Primary")
        let hangingProtocol = HangingProtocol(name: "Test", imageSets: [imageSet])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let imageSetSequence = dataSet.sequence(for: .imageSetsSequence)
        XCTAssertNotNil(imageSetSequence)
        XCTAssertEqual(imageSetSequence?.count, 1)
        
        // PS3.3 Table C.23.1-1: Image Set Number and Label are Time Based
        // Image Sets Sequence (0072,0030) item attributes
        let imageSetItem = imageSetSequence?[0]
        XCTAssertNil(imageSetItem?[.imageSetNumber])
        XCTAssertNil(imageSetItem?[.imageSetLabel])
        let timeItem = imageSetItem?[.timeBasedImageSetsSequence]?.sequenceItems?.first
        XCTAssertEqual(timeItem?[.imageSetNumber]?.uint16Value, 1)
        XCTAssertEqual(timeItem?.string(for: .imageSetLabel), "Primary")
    }
    
    func test_serialize_imageSetSelector() throws {
        let selector = ImageSetSelector(
            attribute: .modality,
            valueNumber: 1,
            values: ["CT"],
            usageFlag: .match
        )
        let imageSet = ImageSetDefinition(number: 1, selectors: [selector])
        let hangingProtocol = HangingProtocol(name: "Test", imageSets: [imageSet])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let imageSetSequence = dataSet.sequence(for: .imageSetsSequence)
        let imageSetItem = imageSetSequence?[0]
        let selectorSequence = imageSetItem?[.imageSetSelectorSequence]?.sequenceItems
        
        XCTAssertNotNil(selectorSequence)
        XCTAssertEqual(selectorSequence?.count, 1)
        
        // PS3.3 Table C.23.4-1: the value travels in Selector Attribute VR
        // (0072,0050) + Selector CS Value (0072,0062), not under (0008,0060).
        let item = selectorSequence?[0]
        XCTAssertEqual(item?[.selectorAttribute]?.attributeTagValue, .modality)
        XCTAssertEqual(item?[.selectorValueNumber]?.uint16Value, 1)
        // Filter-by attributes are not Image Set Selector Sequence attributes
        // (PS3.3 Table C.23.1-1)
        XCTAssertNil(item?[.filterByOperator])
        XCTAssertEqual(item?.string(for: .selectorAttributeVR), "CS")
        XCTAssertEqual(item?[.selectorCSValue]?.stringValue, "CT")
        XCTAssertNil(item?[.modality])
        XCTAssertNil(item?[.filterByCategory])
        XCTAssertNil(item?[.filterByAttributePresence])
        XCTAssertEqual(item?.string(for: .imageSetSelectorUsageFlag), "MATCH")
    }

    // MARK: - Standard Terms (PS3.3 2026a Tables C.23.1-1 / C.23.3-1)

    /// A protocol whose display set 1 shows image set 1 through `filters`.
    private func filterProtocol(_ filters: [FilterOperation], selectors: [ImageSetSelector] = []) -> HangingProtocol {
        HangingProtocol(
            name: "T",
            imageSets: [ImageSetDefinition(number: 1, selectors: selectors)],
            displaySets: [DisplaySet(number: 1, imageSetNumber: 1, filterOperations: filters)]
        )
    }

    /// The Filter Operations Sequence (0072,0400) item of display set 1 and
    /// its parsed value (PS3.3 Table C.23.3-1).
    private func filterItem(_ filter: FilterOperation) throws -> (SequenceItem?, FilterOperation?) {
        let dataSet = try serializer.serialize(protocol: filterProtocol([filter]))
        let item = dataSet.sequence(for: .displaySetsSequence)?[0][.filterOperationsSequence]?.sequenceItems?.first
        let parsed = try HangingProtocolParser().parse(from: dataSet).displaySets.first?.filterOperations.first
        return (item, parsed)
    }

    /// Filter-by Operator (0072,0406): every Enumerated Value round-trips
    func test_roundTrip_filterByOperator_everyTerm() throws {
        let terms: [(FilterOperator, String)] = [
            (.rangeInclusive, "RANGE_INCL"), (.rangeExclusive, "RANGE_EXCL"),
            (.greaterThanOrEqual, "GREATER_OR_EQUAL"), (.lessThanOrEqual, "LESS_OR_EQUAL"),
            (.greaterThan, "GREATER_THAN"), (.lessThan, "LESS_THAN"),
            (.memberOf, "MEMBER_OF"), (.notMemberOf, "NOT_MEMBER_OF"),
        ]
        for (op, term) in terms {
            let (item, parsed) = try filterItem(FilterOperation(attribute: .sliceLocation, operator: op, values: ["10", "20"]))
            XCTAssertEqual(item?.string(for: .filterByOperator), term)
            XCTAssertEqual(item?.string(for: .selectorAttributeVR), "DS")
            XCTAssertEqual(item?[.selectorValueNumber]?.uint16Value, 0, "Type 1C with an operator; 0 = any value")
            XCTAssertEqual(parsed?.operator, op)
        }
    }

    /// Deprecated operators are written as Table C.23.3-1 terms, PRESENT / NOT_PRESENT as
    /// Filter-by Attribute Presence (0072,0404)
    @available(*, deprecated)
    func test_serialize_filterByOperator_deprecatedCasesWriteStandardTerms() throws {
        XCTAssertEqual(try filterItem(FilterOperation(attribute: .modality, operator: .equal, values: ["CT"])).0?
            .string(for: .filterByOperator), "MEMBER_OF")
        XCTAssertEqual(try filterItem(FilterOperation(attribute: .modality, operator: .notEqual, values: ["CT"])).0?
            .string(for: .filterByOperator), "NOT_MEMBER_OF")
        XCTAssertEqual(try filterItem(FilterOperation(attribute: .seriesDescription, operator: .contains, values: ["CHEST"])).0?
            .string(for: .filterByOperator), "MEMBER_OF")

        let present = try filterItem(FilterOperation(attribute: .sliceLocation, operator: .present)).0
        XCTAssertNil(present?[.filterByOperator])
        XCTAssertEqual(present?.string(for: .filterByAttributePresence), "PRESENT")

        let (notPresent, parsed) = try filterItem(FilterOperation(attribute: .sliceLocation, operator: .notPresent))
        XCTAssertNil(notPresent?[.filterByOperator])
        XCTAssertEqual(notPresent?.string(for: .filterByAttributePresence), "NOT_PRESENT")
        XCTAssertNil(parsed?.operator)
        XCTAssertEqual(parsed?.attributePresence, .notPresent)
    }

    /// A filter given on the deprecated ImageSetSelector API is written as a
    /// Filter Operations Sequence item of the display set that shows the
    /// image set, never in the Image Set Selector Sequence item.
    @available(*, deprecated)
    func test_serialize_deprecatedSelectorFilterGoesToDisplaySet() throws {
        let legacy = ImageSetSelector(attribute: .sliceLocation, operator: .greaterThan, values: ["10"])
        let dataSet = try serializer.serialize(protocol: filterProtocol([], selectors: [legacy]))

        let selectorItem = dataSet.sequence(for: .imageSetsSequence)?[0][.imageSetSelectorSequence]?.sequenceItems?.first
        XCTAssertNil(selectorItem?[.filterByOperator])
        XCTAssertNil(selectorItem?[.filterByAttributePresence])
        XCTAssertNil(selectorItem?[.filterByCategory])

        let filter = dataSet.sequence(for: .displaySetsSequence)?[0][.filterOperationsSequence]?.sequenceItems?.first
        XCTAssertEqual(filter?[.selectorAttribute]?.attributeTagValue, .sliceLocation)
        XCTAssertEqual(filter?.string(for: .filterByOperator), "GREATER_THAN")
        XCTAssertEqual(filter?[.selectorDSValue]?.stringValue.map { $0.trimmingCharacters(in: .whitespaces) }, "10")

        let parsed = try HangingProtocolParser().parse(from: dataSet)
        XCTAssertEqual(parsed.displaySets.first?.filterOperations.first?.operator, .greaterThan)
    }

    /// Filter-by Attribute Presence (0072,0404) and Filter-by Category (0072,0402)
    func test_roundTrip_filterByPresenceAndCategory() throws {
        for presence in [FilterByAttributePresence.present, .notPresent] {
            let (item, parsed) = try filterItem(FilterOperation(attribute: .sliceLocation, attributePresence: presence))
            XCTAssertEqual(item?.string(for: .filterByAttributePresence), presence.rawValue)
            XCTAssertNil(item?[.filterByOperator])
            XCTAssertEqual(parsed?.attributePresence, presence)
        }

        // C.23.3.1.1: IMAGE_PLANE with Selector Attribute VR CS and Selector CS
        // Value plane terms; Selector Attribute is absent (Type 1C on the
        // absence of Filter-by Category)
        let plane = FilterOperation(filterByCategory: .imagePlane, operator: .memberOf, values: ["TRANSVERSE", "CORONAL"])
        let (item, parsed) = try filterItem(plane)
        XCTAssertEqual(item?.string(for: .filterByCategory), "IMAGE_PLANE")
        XCTAssertNil(item?[.selectorAttribute])
        XCTAssertEqual(item?.string(for: .filterByOperator), "MEMBER_OF")
        XCTAssertEqual(item?.string(for: .selectorAttributeVR), "CS")
        XCTAssertEqual(item?[.selectorCSValue]?.stringValues, ["TRANSVERSE", "CORONAL"])
        XCTAssertEqual(parsed?.filterByCategory, .imagePlane)
        XCTAssertEqual(parsed?.values, ["TRANSVERSE", "CORONAL"])
    }

    /// Hanging Protocol Level (0072,0006): every Enumerated Value round-trips
    func test_roundTrip_hangingProtocolLevel_everyTerm() throws {
        for level in HangingProtocolLevel.allCases {
            let dataSet = try serializer.serialize(protocol: HangingProtocol(name: "T", level: level))
            XCTAssertEqual(dataSet.string(for: .hangingProtocolLevel), level.rawValue)
            XCTAssertEqual(try HangingProtocolParser().parse(from: dataSet).level, level)
        }
        XCTAssertEqual(try serializer.serialize(protocol: HangingProtocol(name: "T", level: .manufacturer))
            .string(for: .hangingProtocolLevel), "MANUFACTURER")
    }

    /// The first Time Based Image Sets Sequence (0072,0030) item of the
    /// image set (PS3.3 Table C.23.1-1) and its parsed value.
    private func imageSetItem(_ imageSet: ImageSetDefinition) throws -> (SequenceItem?, TimeBasedImageSet?) {
        let dataSet = try serializer.serialize(protocol: HangingProtocol(name: "T", imageSets: [imageSet]))
        let parsed = try HangingProtocolParser().parse(from: dataSet).imageSets.first?.timeBasedImageSets.first
        let imageSetItem = dataSet.sequence(for: .imageSetsSequence)?.first
        XCTAssertNil(imageSetItem?[.imageSetSelectorCategory], "not in the Image Sets Sequence item")
        return (imageSetItem?[.timeBasedImageSetsSequence]?.sequenceItems?.first, parsed)
    }

    /// Image Set Selector Category (0072,0034): RELATIVE_TIME / ABSTRACT_PRIOR
    func test_roundTrip_imageSetSelectorCategory_everyTerm() throws {
        for (category, term) in [(ImageSetSelectorCategory.relativeTime, "RELATIVE_TIME"), (.abstractPrior, "ABSTRACT_PRIOR")] {
            let (item, parsed) = try imageSetItem(ImageSetDefinition(number: 1, category: category))
            XCTAssertEqual(item?.string(for: .imageSetSelectorCategory), term)
            XCTAssertEqual(parsed?.category, category)
        }
    }

    @available(*, deprecated)
    func test_serialize_imageSetSelectorCategory_deprecatedCasesWriteStandardTerms() throws {
        XCTAssertEqual(try imageSetItem(ImageSetDefinition(number: 1, category: .current)).0?
            .string(for: .imageSetSelectorCategory), "RELATIVE_TIME")
        XCTAssertEqual(try imageSetItem(ImageSetDefinition(number: 1, category: .prior)).0?
            .string(for: .imageSetSelectorCategory), "ABSTRACT_PRIOR")
        XCTAssertEqual(try imageSetItem(ImageSetDefinition(number: 1, category: .comparison)).0?
            .string(for: .imageSetSelectorCategory), "ABSTRACT_PRIOR")
    }

    /// Abstract Prior Value (0072,003C) is SS VM 2 (PS3.6 Table 6-1); Relative Time (0072,0038)
    /// is US VM 2; Relative Time Units (0072,003A) every Enumerated Value
    func test_roundTrip_timeBasedSelection_abstractPriorValueIsSS() throws {
        let selection = TimeBasedSelection(relativeTimeRange: [7, 30], relativeTimeUnits: .days, abstractPriorRange: [1, -1])
        let (item, parsed) = try imageSetItem(ImageSetDefinition(number: 1, category: .abstractPrior, timeSelection: selection))

        XCTAssertEqual(item?[.abstractPriorValue]?.vr, .SS)
        XCTAssertEqual(item?[.abstractPriorValue]?.int16Values, [1, -1])
        XCTAssertEqual(item?[.relativeTime]?.vr, .US)
        XCTAssertEqual(item?[.relativeTime]?.uint16Values, [7, 30])
        XCTAssertEqual(item?.string(for: .relativeTimeUnits), "DAYS")

        XCTAssertEqual(parsed?.timeSelection?.abstractPriorRange, [1, -1])
        XCTAssertEqual(parsed?.timeSelection?.relativeTimeRange, [7, 30])
        XCTAssertEqual(parsed?.timeSelection?.relativeTimeUnits, .days)

        for units in [RelativeTimeUnits.seconds, .minutes, .hours, .days, .weeks, .months, .years] {
            let (unitsItem, unitsParsed) = try imageSetItem(ImageSetDefinition(
                number: 1, timeSelection: TimeBasedSelection(relativeTimeRange: [0, 0], relativeTimeUnits: units)))
            XCTAssertEqual(unitsItem?.string(for: .relativeTimeUnits), units.rawValue)
            XCTAssertEqual(unitsParsed?.timeSelection?.relativeTimeUnits, units)
        }
    }

    func test_serialize_timeBasedSelection_singleValueIsWrittenAsPair() throws {
        let (item, _) = try imageSetItem(ImageSetDefinition(
            number: 1, timeSelection: TimeBasedSelection(relativeTimeRange: [30], relativeTimeUnits: .days, abstractPriorRange: [2])))
        XCTAssertEqual(item?[.relativeTime]?.uint16Values, [30, 30], "n\\n is prior by n units")
        XCTAssertEqual(item?[.abstractPriorValue]?.int16Values, [2, 2])
    }

    @available(*, deprecated)
    func test_serialize_timeBasedSelection_deprecatedStringIsWrittenAsSS() throws {
        let (item, parsed) = try imageSetItem(ImageSetDefinition(
            number: 1, timeSelection: TimeBasedSelection(abstractPriorValue: "MOST_RECENT")))
        XCTAssertEqual(item?[.abstractPriorValue]?.vr, .SS)
        XCTAssertEqual(item?[.abstractPriorValue]?.int16Values, [1, 1])
        XCTAssertEqual(parsed?.timeSelection?.abstractPriorValue, "MOST_RECENT")
    }

    /// The Sorting Operations Sequence (0072,0600) item of display set 1
    /// (PS3.3 Table C.23.3-1) and its parsed value.
    private func sortItem(_ operation: SortOperation) throws -> (SequenceItem?, SortOperation?) {
        let dataSet = try serializer.serialize(protocol: HangingProtocol(
            name: "T",
            imageSets: [ImageSetDefinition(number: 1)],
            displaySets: [DisplaySet(number: 1, imageSetNumber: 1, sortingOperations: [operation])]
        ))
        XCTAssertNil(dataSet.sequence(for: .imageSetsSequence)?[0][.sortingOperationsSequence],
                     "not in the Image Sets Sequence item")
        let item = dataSet.sequence(for: .displaySetsSequence)?[0][.sortingOperationsSequence]?.sequenceItems?.first
        let parsed = try HangingProtocolParser().parse(from: dataSet).displaySets.first?.sortingOperations.first
        return (item, parsed)
    }

    /// Sort-by Category (0072,0602) ALONG_AXIS / BY_ACQ_TIME and Sorting Direction (0072,0604)
    func test_roundTrip_sortByCategory_everyTerm() throws {
        for (category, term) in [(SortByCategory.alongAxis, "ALONG_AXIS"), (.byAcquisitionTime, "BY_ACQ_TIME")] {
            for direction in [SortDirection.ascending, .descending] {
                let (item, parsed) = try sortItem(SortOperation(sortByCategory: category, direction: direction))
                XCTAssertEqual(item?.string(for: .sortByCategory), term)
                XCTAssertEqual(item?.string(for: .sortingDirection), direction.rawValue)
                XCTAssertNil(item?[.selectorAttribute])
                XCTAssertEqual(parsed?.sortByCategory, category)
                XCTAssertEqual(parsed?.direction, direction)
            }
        }
    }

    /// Sorting by attribute: Selector Attribute (0072,0026) + Selector Value Number (0072,0028),
    /// no Sort-by Category
    func test_roundTrip_sortByAttribute() throws {
        let (item, parsed) = try sortItem(SortOperation(attribute: .instanceNumber, valueNumber: 1, direction: .descending))
        XCTAssertNil(item?[.sortByCategory])
        XCTAssertEqual(item?[.selectorAttribute]?.attributeTagValue, .instanceNumber)
        XCTAssertEqual(item?[.selectorValueNumber]?.uint16Value, 1)
        XCTAssertEqual(item?.string(for: .sortingDirection), "DECREASING")
        XCTAssertNil(parsed?.sortByCategory)
        XCTAssertEqual(parsed?.attribute, .instanceNumber)
        XCTAssertEqual(parsed?.valueNumber, 1)
        XCTAssertEqual(parsed?.direction, .descending)
    }

    @available(*, deprecated)
    func test_serialize_sortByCategory_deprecatedCasesWriteStandardTerms() throws {
        let inst = try sortItem(SortOperation(sortByCategory: .instanceNumber)).0
        XCTAssertNil(inst?[.sortByCategory])
        XCTAssertEqual(inst?[.selectorAttribute]?.attributeTagValue, .instanceNumber)
        XCTAssertEqual(inst?[.selectorValueNumber]?.uint16Value, 1)

        let slice = try sortItem(SortOperation(sortByCategory: .sliceLocation)).0
        XCTAssertNil(slice?[.sortByCategory])
        XCTAssertEqual(slice?[.selectorAttribute]?.attributeTagValue, .sliceLocation)

        XCTAssertEqual(try sortItem(SortOperation(sortByCategory: .acquisitionTime)).0?.string(for: .sortByCategory), "BY_ACQ_TIME")
        XCTAssertEqual(try sortItem(SortOperation(sortByCategory: .imagePosition)).0?.string(for: .sortByCategory), "ALONG_AXIS")

        let attr = try sortItem(SortOperation(sortByCategory: .attribute, attribute: .acquisitionTime)).0
        XCTAssertNil(attr?[.sortByCategory])
        XCTAssertEqual(attr?[.selectorAttribute]?.attributeTagValue, .acquisitionTime)
    }

    private func imageBoxItem(_ imageBox: ImageBox) throws -> (SequenceItem?, ImageBox?) {
        let displaySet = DisplaySet(number: 1, imageBoxes: [imageBox])
        let dataSet = try serializer.serialize(protocol: HangingProtocol(name: "T", displaySets: [displaySet]))
        let item = dataSet.sequence(for: .displaySetsSequence)?[0][.imageBoxesSequence]?.sequenceItems?.first
        let parsed = try HangingProtocolParser().parse(from: dataSet).displaySets.first?.imageBoxes.first
        return (item, parsed)
    }

    /// Image Box Layout Type (0072,0304): every Defined Term round-trips
    func test_roundTrip_imageBoxLayoutType_everyTerm() throws {
        let terms: [(ImageBoxLayoutType, String)] = [
            (.tiled, "TILED"), (.stack, "STACK"), (.cine, "CINE"), (.processed, "PROCESSED"), (.single, "SINGLE"),
        ]
        for (layout, term) in terms {
            let (item, parsed) = try imageBoxItem(ImageBox(number: 1, layoutType: layout))
            XCTAssertEqual(item?.string(for: .imageBoxLayoutType), term)
            XCTAssertEqual(parsed?.layoutType, layout)
        }
    }

    /// Scroll Direction (0072,0310) and Small / Large Scroll Type (0072,0312 / 0316)
    func test_roundTrip_scrollTerms() throws {
        for direction in [ScrollDirection.vertical, .horizontal] {
            for scroll in [ScrollType.page, .rowColumn, .image] {
                let box = ImageBox(number: 1, layoutType: .tiled, tileHorizontalDimension: 2, tileVerticalDimension: 2,
                                   scrollDirection: direction, smallScrollType: scroll, smallScrollAmount: 1,
                                   largeScrollType: scroll, largeScrollAmount: 4)
                let (item, parsed) = try imageBoxItem(box)
                XCTAssertEqual(item?.string(for: .imageBoxScrollDirection), direction.rawValue)
                XCTAssertEqual(item?.string(for: .imageBoxSmallScrollType), scroll.rawValue)
                XCTAssertEqual(item?.string(for: .imageBoxLargeScrollType), scroll.rawValue)
                XCTAssertEqual(parsed?.scrollDirection, direction)
                XCTAssertEqual(parsed?.smallScrollType, scroll)
                XCTAssertEqual(parsed?.largeScrollType, scroll)
            }
        }
    }

    @available(*, deprecated)
    func test_serialize_deprecatedLayoutAndScrollCasesWriteStandardTerms() throws {
        let (item, parsed) = try imageBoxItem(ImageBox(number: 1, layoutType: .tiledAll, smallScrollType: .fraction, smallScrollAmount: 1))
        XCTAssertEqual(item?.string(for: .imageBoxLayoutType), "TILED")
        XCTAssertEqual(item?.string(for: .imageBoxSmallScrollType), "PAGE")
        XCTAssertEqual(parsed?.layoutType, .tiled)
        XCTAssertEqual(parsed?.smallScrollType, .page)
    }

    /// The Display Sets Sequence item of `displaySet` (reformatting and 3D
    /// Rendering Type are display set attributes, PS3.3 Table C.23.3-1) and
    /// the parsed display set.
    private func displaySetItem(_ displaySet: DisplaySet) throws -> (SequenceItem?, DisplaySet?) {
        let dataSet = try serializer.serialize(protocol: HangingProtocol(name: "T", displaySets: [displaySet]))
        let item = dataSet.sequence(for: .displaySetsSequence)?.first
        let box = item?[.imageBoxesSequence]?.sequenceItems?.first
        for tag in [Tag.reformattingOperationType, .reformattingThickness, .reformattingInterval,
                    .reformattingOperationInitialViewDirection, .threeDRenderingType] {
            XCTAssertNil(box?[tag], "\(tag) is not an Image Boxes Sequence attribute")
        }
        return (item, try HangingProtocolParser().parse(from: dataSet).displaySets.first)
    }

    /// Reformatting Operation Type (0072,0510) MPR / 3D_RENDERING / SLAB, Initial View Direction
    /// (0072,0516) SAGITTAL / TRANSVERSE / CORONAL / OBLIQUE, 3D Rendering Type (0072,0520)
    func test_roundTrip_reformattingTerms() throws {
        let types: [(ReformattingType, String)] = [(.mpr, "MPR"), (.threeDRendering, "3D_RENDERING"), (.slab, "SLAB")]
        for (type, term) in types {
            for plane in ImagePlane.allCases {
                let op = ReformattingOperation(type: type, thickness: 2, interval: 1, initialViewPlane: plane)
                let (item, parsed) = try displaySetItem(DisplaySet(
                    number: 1, imageBoxes: [ImageBox(number: 1)], reformattingOperation: op, threeDRenderingType: .mip))
                XCTAssertEqual(item?.string(for: .reformattingOperationType), term)
                XCTAssertEqual(item?[.reformattingThickness]?.float64Value, 2)
                XCTAssertEqual(item?[.reformattingInterval]?.float64Value, 1)
                XCTAssertEqual(item?.string(for: .reformattingOperationInitialViewDirection), plane.rawValue)
                XCTAssertEqual(parsed?.reformattingOperation?.type, type)
                XCTAssertEqual(parsed?.reformattingOperation?.initialViewPlane, plane)
            }
        }

        for rendering in [ThreeDRenderingType.mip, .surfaceRendering, .volumeRendering] {
            let displaySet = DisplaySet(
                number: 1, imageBoxes: [ImageBox(number: 1)],
                reformattingOperation: ReformattingOperation(type: .threeDRendering, initialViewPlane: .transverse),
                threeDRenderingType: rendering, threeDRenderingSubtypes: ["SHADED"])
            let (item, parsed) = try displaySetItem(displaySet)
            XCTAssertEqual(item?[.threeDRenderingType]?.stringValues, [rendering.rawValue, "SHADED"])
            XCTAssertEqual(parsed?.threeDRenderingType, rendering)
            XCTAssertEqual(parsed?.threeDRenderingSubtypes, ["SHADED"])
        }
    }

    /// CPR -> MPR; MIP / MinIP / AvgIP -> 3D_RENDERING with an implied 3D Rendering Type.
    /// Values given on the deprecated ImageBox API are written at display set level.
    @available(*, deprecated)
    func test_serialize_deprecatedReformattingCasesWriteStandardTerms() throws {
        func boxed(_ box: ImageBox) throws -> SequenceItem? {
            try displaySetItem(DisplaySet(number: 1, imageBoxes: [box])).0
        }
        let cpr = try boxed(ImageBox(number: 1, reformattingOperation: ReformattingOperation(type: .cpr)))
        XCTAssertEqual(cpr?.string(for: .reformattingOperationType), "MPR")
        XCTAssertNil(cpr?[.threeDRenderingType])

        let mip = try boxed(ImageBox(number: 1, reformattingOperation: ReformattingOperation(type: .mip)))
        XCTAssertEqual(mip?.string(for: .reformattingOperationType), "3D_RENDERING")
        XCTAssertEqual(mip?[.threeDRenderingType]?.stringValues, ["MIP"])

        let minIP = try boxed(ImageBox(number: 1, reformattingOperation: ReformattingOperation(type: .minIP)))
        XCTAssertEqual(minIP?.string(for: .reformattingOperationType), "3D_RENDERING")
        XCTAssertEqual(minIP?[.threeDRenderingType]?.stringValues, ["VOLUME", "MINIP"])

        let avgIP = try boxed(ImageBox(number: 1, reformattingOperation: ReformattingOperation(type: .avgIP)))
        XCTAssertEqual(avgIP?[.threeDRenderingType]?.stringValues, ["VOLUME", "AVGIP"])

        // An explicit 3D Rendering Type on the box wins over the implied one
        let explicit = try boxed(ImageBox(number: 1, reformattingOperation: ReformattingOperation(type: .minIP),
                                          threeDRenderingType: .surfaceRendering))
        XCTAssertEqual(explicit?[.threeDRenderingType]?.stringValues, ["SURFACE"])

        let axial = try boxed(ImageBox(number: 1, reformattingOperation: ReformattingOperation(type: .mpr, initialViewDirection: "AXIAL")))
        XCTAssertEqual(axial?.string(for: .reformattingOperationInitialViewDirection), "TRANSVERSE")
    }

    /// Partial Data Display Handling (0072,0208) is Type 2 at the top level: MAINTAIN_LAYOUT /
    /// ADAPT_LAYOUT, zero length when not defined
    func test_roundTrip_partialDataDisplayHandling() throws {
        for handling in [PartialDataDisplayHandling.maintainLayout, .adaptLayout] {
            let dataSet = try serializer.serialize(protocol: HangingProtocol(name: "T", partialDataDisplayHandling: handling))
            XCTAssertEqual(dataSet.string(for: .partialDataDisplayHandling), handling.rawValue)
            XCTAssertEqual(try HangingProtocolParser().parse(from: dataSet).partialDataDisplayHandling, handling)
        }

        let undefined = try serializer.serialize(protocol: HangingProtocol(name: "T", displaySets: [DisplaySet(number: 1)]))
        XCTAssertNotNil(undefined[.partialDataDisplayHandling], "Type 2: present")
        XCTAssertEqual(undefined[.partialDataDisplayHandling]?.length, 0, "zero length when not defined")
        XCTAssertNil(undefined.sequence(for: .displaySetsSequence)?[0][.partialDataDisplayHandling],
                     "not written inside the Display Sets Sequence item")
        XCTAssertNil(try HangingProtocolParser().parse(from: undefined).partialDataDisplayHandling)
    }

    @available(*, deprecated)
    func test_serialize_partialDataHandling_deprecatedDisplaySetValueIsPromoted() throws {
        let displaySet = DisplaySet(number: 1, partialDataHandling: "ADAPT_LAYOUT")
        let dataSet = try serializer.serialize(protocol: HangingProtocol(name: "T", displaySets: [displaySet]))
        XCTAssertEqual(dataSet.string(for: .partialDataDisplayHandling), "ADAPT_LAYOUT")
        XCTAssertNil(dataSet.sequence(for: .displaySetsSequence)?[0][.partialDataDisplayHandling])

        let nonTerm = DisplaySet(number: 1, partialDataHandling: "DISPLAY")
        let dropped = try serializer.serialize(protocol: HangingProtocol(name: "T", displaySets: [nonTerm]))
        XCTAssertEqual(dropped[.partialDataDisplayHandling]?.length, 0, "a non-term is dropped")
    }

    /// Justification (0072,0717 / 0718) and the YES / NO flags
    func test_roundTrip_justificationAndFlags() throws {
        let options = DisplayOptions(voiType: VOIType.lung.rawValue, showGrayscaleInverted: true, showImageTrueSize: false,
                                     showGraphicAnnotations: false, showPatientDemographics: true,
                                     showAcquisitionTechniques: false, horizontalJustification: .right, verticalJustification: .bottom)
        let dataSet = try serializer.serialize(protocol: HangingProtocol(name: "T", displaySets: [DisplaySet(number: 1, displayOptions: options)]))
        let item = dataSet.sequence(for: .displaySetsSequence)?[0]
        XCTAssertEqual(item?.string(for: .voiType), "LUNG")
        XCTAssertEqual(item?.string(for: .displaySetHorizontalJustification), "RIGHT")
        XCTAssertEqual(item?.string(for: .displaySetVerticalJustification), "BOTTOM")
        XCTAssertEqual(item?.string(for: .showGrayscaleInverted), "YES")
        XCTAssertEqual(item?.string(for: .showGraphicAnnotationFlag), "NO")
        XCTAssertEqual(item?.string(for: .showPatientDemographicsFlag), "YES")
        XCTAssertEqual(item?.string(for: .showAcquisitionTechniquesFlag), "NO")

        let parsed = try HangingProtocolParser().parse(from: dataSet).displaySets[0].displayOptions
        XCTAssertEqual(parsed.voiTypeTerm, .lung)
        XCTAssertEqual(parsed.horizontalJustification, .right)
        XCTAssertEqual(parsed.verticalJustification, .bottom)
        XCTAssertTrue(parsed.showGrayscaleInverted)
        XCTAssertFalse(parsed.showGraphicAnnotations)
        XCTAssertTrue(parsed.showPatientDemographics)
        XCTAssertFalse(parsed.showAcquisitionTechniques)
    }
    
    // MARK: - Display Set Serialization Tests
    
    func test_serialize_displaySets_empty() throws {
        let hangingProtocol = HangingProtocol(name: "Test", displaySets: [])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        XCTAssertNil(dataSet.sequence(for: .displaySetsSequence))
    }
    
    func test_serialize_displaySets_single() throws {
        let displaySet = DisplaySet(number: 1, label: "Main View")
        let hangingProtocol = HangingProtocol(name: "Test", displaySets: [displaySet])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let displaySetSequence = dataSet.sequence(for: .displaySetsSequence)
        XCTAssertNotNil(displaySetSequence)
        XCTAssertEqual(displaySetSequence?.count, 1)
        
        let displaySetItem = displaySetSequence?[0]
        XCTAssertEqual(displaySetItem?[.displaySetNumber]?.uint16Value, 1)
        XCTAssertEqual(displaySetItem?.string(for: .displaySetLabel), "Main View")
    }
    
    func test_serialize_imageBox_stack() throws {
        let imageBox = ImageBox(number: 1, layoutType: .stack, imageSetNumbers: [1])
        let displaySet = DisplaySet(number: 1, imageBoxes: [imageBox])
        let hangingProtocol = HangingProtocol(name: "Test", displaySets: [displaySet])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let displaySetSequence = dataSet.sequence(for: .displaySetsSequence)
        let displaySetItem = displaySetSequence?[0]
        let imageBoxSequence = displaySetItem?[.imageBoxesSequence]?.sequenceItems
        
        XCTAssertNotNil(imageBoxSequence)
        XCTAssertEqual(imageBoxSequence?.count, 1)
        
        let imageBoxItem = imageBoxSequence?[0]
        XCTAssertEqual(imageBoxItem?[.imageBoxNumber]?.uint16Value, 1)
        XCTAssertEqual(imageBoxItem?.string(for: .imageBoxLayoutType), "STACK")
    }
    
    func test_serialize_imageBox_tiled() throws {
        let imageBox = ImageBox(
            number: 1,
            layoutType: .tiled,
            imageSetNumbers: [1, 2, 3, 4],
            tileHorizontalDimension: 2,
            tileVerticalDimension: 2
        )
        let displaySet = DisplaySet(number: 1, imageBoxes: [imageBox])
        let hangingProtocol = HangingProtocol(name: "Test", displaySets: [displaySet])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let displaySetSequence = dataSet.sequence(for: .displaySetsSequence)
        let displaySetItem = displaySetSequence?[0]
        let imageBoxSequence = displaySetItem?[.imageBoxesSequence]?.sequenceItems
        let imageBoxItem = imageBoxSequence?[0]
        
        XCTAssertEqual(imageBoxItem?.string(for: .imageBoxLayoutType), "TILED")
        XCTAssertEqual(imageBoxItem?[.imageBoxTileHorizontalDimension]?.uint16Value, 2)
        XCTAssertEqual(imageBoxItem?[.imageBoxTileVerticalDimension]?.uint16Value, 2)
    }
    
    func test_serialize_displayOptions() throws {
        let options = DisplayOptions(
            patientOrientation: "L\\P",
            showGrayscaleInverted: true,
            showImageTrueSize: true,
            showGraphicAnnotations: false
        )
        let displaySet = DisplaySet(number: 1, displayOptions: options)
        let hangingProtocol = HangingProtocol(name: "Test", displaySets: [displaySet])
        
        let dataSet = try serializer.serialize(protocol: hangingProtocol)
        
        let displaySetSequence = dataSet.sequence(for: .displaySetsSequence)
        let displaySetItem = displaySetSequence?[0]
        
        XCTAssertEqual(displaySetItem?.string(for: .displaySetPatientOrientation), "L\\P")
        // PS3.3 Table C.23.3-1: the display flags are enumerated YES / NO
        XCTAssertEqual(displaySetItem?.string(for: .showGrayscaleInverted), "YES")
        XCTAssertEqual(displaySetItem?.string(for: .showImageTrueSizeFlag), "YES")
        XCTAssertEqual(displaySetItem?.string(for: .showGraphicAnnotationFlag), "NO")
    }
    
    // MARK: - Round-Trip Tests
    
    func test_roundTrip_minimalProtocol() throws {
        let originalProtocol = HangingProtocol(name: "Round Trip Test")
        
        let dataSet = try serializer.serialize(protocol: originalProtocol)
        let parser = HangingProtocolParser()
        let parsedProtocol = try parser.parse(from: dataSet)
        
        XCTAssertEqual(parsedProtocol.name, originalProtocol.name)
        XCTAssertEqual(parsedProtocol.level, originalProtocol.level)
        XCTAssertEqual(parsedProtocol.numberOfScreens, originalProtocol.numberOfScreens)
    }
    
    func test_roundTrip_completeProtocol() throws {
        let env = HangingProtocolEnvironment(modality: "CT", laterality: "L")
        let imageSet = ImageSetDefinition(number: 1, label: "Primary")
        let screen = ScreenDefinition(verticalPixels: 1080, horizontalPixels: 1920)
        let displaySet = DisplaySet(number: 1, label: "Main View")
        
        let originalProtocol = HangingProtocol(
            name: "Complete Protocol",
            description: "Full test",
            level: .site,
            creator: "Dr. Smith",
            environments: [env],
            userGroups: ["Radiology"],
            imageSets: [imageSet],
            numberOfScreens: 2,
            screenDefinitions: [screen],
            displaySets: [displaySet]
        )
        
        let dataSet = try serializer.serialize(protocol: originalProtocol)
        let parser = HangingProtocolParser()
        let parsedProtocol = try parser.parse(from: dataSet)
        
        XCTAssertEqual(parsedProtocol.name, originalProtocol.name)
        XCTAssertEqual(parsedProtocol.description, originalProtocol.description)
        XCTAssertEqual(parsedProtocol.level, originalProtocol.level)
        XCTAssertEqual(parsedProtocol.creator, originalProtocol.creator)
        XCTAssertEqual(parsedProtocol.environments.count, originalProtocol.environments.count)
        XCTAssertEqual(parsedProtocol.userGroups.count, originalProtocol.userGroups.count)
        XCTAssertEqual(parsedProtocol.imageSets.count, originalProtocol.imageSets.count)
        XCTAssertEqual(parsedProtocol.numberOfScreens, originalProtocol.numberOfScreens)
        XCTAssertEqual(parsedProtocol.screenDefinitions.count, originalProtocol.screenDefinitions.count)
        XCTAssertEqual(parsedProtocol.displaySets.count, originalProtocol.displaySets.count)
    }
    
    func test_roundTrip_environments() throws {
        let env1 = HangingProtocolEnvironment(modality: "CT")
        let env2 = HangingProtocolEnvironment(modality: "MR", laterality: "L")
        let originalProtocol = HangingProtocol(name: "Test", environments: [env1, env2])
        
        let dataSet = try serializer.serialize(protocol: originalProtocol)
        let parser = HangingProtocolParser()
        let parsedProtocol = try parser.parse(from: dataSet)
        
        XCTAssertEqual(parsedProtocol.environments.count, 2)
        XCTAssertEqual(parsedProtocol.environments[0].modality, "CT")
        XCTAssertEqual(parsedProtocol.environments[1].modality, "MR")
        XCTAssertEqual(parsedProtocol.environments[1].laterality, "L")
    }
    
    func test_roundTrip_displaySet_withImageBox() throws {
        let imageBox = ImageBox(
            number: 1,
            layoutType: .tiled,
            imageSetNumbers: [1, 2],
            tileHorizontalDimension: 2,
            tileVerticalDimension: 1
        )
        let displaySet = DisplaySet(number: 1, imageBoxes: [imageBox])
        let originalProtocol = HangingProtocol(name: "Test", displaySets: [displaySet])
        
        let dataSet = try serializer.serialize(protocol: originalProtocol)
        let parser = HangingProtocolParser()
        let parsedProtocol = try parser.parse(from: dataSet)
        
        XCTAssertEqual(parsedProtocol.displaySets.count, 1)
        XCTAssertEqual(parsedProtocol.displaySets[0].imageBoxes.count, 1)
        
        let parsedBox = parsedProtocol.displaySets[0].imageBoxes[0]
        XCTAssertEqual(parsedBox.number, 1)
        XCTAssertEqual(parsedBox.layoutType, .tiled)
        XCTAssertEqual(parsedBox.tileHorizontalDimension, 2)
        XCTAssertEqual(parsedBox.tileVerticalDimension, 1)
    }
}
