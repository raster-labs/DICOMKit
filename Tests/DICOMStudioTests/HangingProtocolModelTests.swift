// HangingProtocolModelTests.swift
// DICOMStudioTests
//
// Tests for Hanging Protocol models

import Testing
@testable import DICOMStudio
import Foundation

@Suite("LayoutType Tests")
struct LayoutTypeTests {

    @Test("All layout types")
    func testCaseCount() {
        #expect(LayoutType.allCases.count == 7)
    }

    @Test("Single layout dimensions")
    func testSingle() {
        #expect(LayoutType.single.columns == 1)
        #expect(LayoutType.single.rows == 1)
        #expect(LayoutType.single.cellCount == 1)
    }

    @Test("2x1 layout dimensions")
    func testTwoByOne() {
        #expect(LayoutType.twoByOne.columns == 2)
        #expect(LayoutType.twoByOne.rows == 1)
        #expect(LayoutType.twoByOne.cellCount == 2)
    }

    @Test("1x2 layout dimensions")
    func testOneByTwo() {
        #expect(LayoutType.oneByTwo.columns == 1)
        #expect(LayoutType.oneByTwo.rows == 2)
        #expect(LayoutType.oneByTwo.cellCount == 2)
    }

    @Test("2x2 layout dimensions")
    func testTwoByTwo() {
        #expect(LayoutType.twoByTwo.columns == 2)
        #expect(LayoutType.twoByTwo.rows == 2)
        #expect(LayoutType.twoByTwo.cellCount == 4)
    }

    @Test("3x3 layout dimensions")
    func testThreeByThree() {
        #expect(LayoutType.threeByThree.columns == 3)
        #expect(LayoutType.threeByThree.rows == 3)
        #expect(LayoutType.threeByThree.cellCount == 9)
    }

    @Test("Custom layout defaults")
    func testCustom() {
        #expect(LayoutType.custom.columns == 1)
        #expect(LayoutType.custom.rows == 1)
    }
}

@Suite("ImageSortDirection Tests")
struct ImageSortDirectionTests {

    // PS3.3 2026a Table C.23.3-1 Sorting Direction (0072,0604): INCREASING, DECREASING
    @Test("Raw values are the Sorting Direction Enumerated Values")
    func testRawValues() {
        #expect(ImageSortDirection.ascending.rawValue == "INCREASING")
        #expect(ImageSortDirection.descending.rawValue == "DECREASING")
        #expect(ImageSortDirection.allCases.map(\.rawValue) == ["INCREASING", "DECREASING"])
        #expect(ImageSortDirection(rawValue: "INCREASING") == .ascending)
        #expect(ImageSortDirection(rawValue: "DECREASING") == .descending)
    }

    @Test("Legacy stored values ASCENDING / DESCENDING still decode")
    func testLegacyDecoding() {
        #expect(ImageSortDirection(rawValue: "ASCENDING") == .ascending)
        #expect(ImageSortDirection(rawValue: "DESCENDING") == .descending)
        #expect(ImageSortDirection(rawValue: "UP") == nil)
    }
}

@Suite("ImageSelectionCriteria Tests")
struct ImageSelectionCriteriaTests {

    @Test("Default criteria has no filters")
    func testDefaults() {
        let criteria = ImageSelectionCriteria()
        #expect(!criteria.hasFilters)
        #expect(criteria.sortField == .instanceNumber)
        #expect(criteria.sortDirection == .ascending)
    }

    @Test("Modality filter sets hasFilters")
    func testModalityFilter() {
        let criteria = ImageSelectionCriteria(modality: "CT")
        #expect(criteria.hasFilters)
        #expect(criteria.modality == "CT")
    }

    @Test("Series description filter")
    func testSeriesDescFilter() {
        let criteria = ImageSelectionCriteria(seriesDescription: "T1 SAG")
        #expect(criteria.hasFilters)
    }
}

@Suite("ProtocolMatchingCriteria Tests")
struct ProtocolMatchingCriteriaTests {

    @Test("Default has no criteria")
    func testDefaults() {
        let criteria = ProtocolMatchingCriteria()
        #expect(criteria.modality == nil)
        #expect(criteria.bodyPartExamined == nil)
    }

    @Test("Full criteria")
    func testFull() {
        let criteria = ProtocolMatchingCriteria(
            modality: "CT",
            bodyPartExamined: "CHEST",
            procedureCode: "CT_CHEST",
            studyDescriptionPattern: "CT Chest"
        )
        #expect(criteria.modality == "CT")
        #expect(criteria.bodyPartExamined == "CHEST")
    }
}

@Suite("ViewportDefinition Tests")
struct ViewportDefinitionTests {

    @Test("Basic viewport definition")
    func testBasic() {
        let def = ViewportDefinition(position: 0)
        #expect(def.position == 0)
        #expect(!def.isInitialActive)
    }

    @Test("Active viewport")
    func testActive() {
        let def = ViewportDefinition(position: 0, isInitialActive: true)
        #expect(def.isInitialActive)
    }
}

@Suite("HangingProtocolModel Tests")
struct HangingProtocolModelTests {

    @Test("Default protocol")
    func testDefaults() {
        let proto = HangingProtocolModel(name: "Test")
        #expect(proto.name == "Test")
        #expect(proto.layoutType == .single)
        #expect(proto.priority == 0)
        #expect(!proto.isUserDefined)
    }

    @Test("Protocol effective dimensions")
    func testEffectiveDimensions() {
        let proto = HangingProtocolModel(name: "2x2", layoutType: .twoByTwo)
        #expect(proto.effectiveColumns == 2)
        #expect(proto.effectiveRows == 2)
        #expect(proto.effectiveCellCount == 4)
    }

    @Test("Custom layout effective dimensions")
    func testCustomDimensions() {
        let proto = HangingProtocolModel(
            name: "Custom",
            layoutType: .custom,
            customColumns: 4,
            customRows: 3
        )
        #expect(proto.effectiveColumns == 4)
        #expect(proto.effectiveRows == 3)
        #expect(proto.effectiveCellCount == 12)
    }

    @Test("User-defined protocol")
    func testUserDefined() {
        let proto = HangingProtocolModel(
            name: "My Protocol",
            isUserDefined: true,
            creationDate: Date()
        )
        #expect(proto.isUserDefined)
        #expect(proto.creationDate != nil)
    }
}
