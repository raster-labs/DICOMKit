//
// ImageSetDefinitionTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class ImageSetDefinitionTests: XCTestCase {
    
    // MARK: - ImageSetDefinition Tests
    
    func test_imageSetDefinition_initialization_withRequiredParameters() {
        let imageSet = ImageSetDefinition(number: 1)
        
        XCTAssertEqual(imageSet.number, 1)
        XCTAssertNil(imageSet.label)
        XCTAssertEqual(imageSet.selectors.count, 0)
        XCTAssertEqual(imageSet.sortOperations.count, 0)
        // Image Set Selector Category (0072,0034) is Type 1 in the Time Based
        // Image Sets Sequence item (PS3.3 Table C.23.1-1): inferred when not given
        XCTAssertEqual(imageSet.category, .relativeTime)
        XCTAssertEqual(imageSet.timeBasedImageSets.count, 1)
        XCTAssertEqual(imageSet.timeBasedImageSets.first?.number, 1)
        XCTAssertNil(imageSet.timeSelection)
    }
    
    func test_imageSetDefinition_initialization_withAllParameters() {
        let selector = ImageSetSelector(attribute: .modality, values: ["CT"])
        let sortOp = SortOperation(attribute: .instanceNumber)
        let timeSelection = TimeBasedSelection(relativeTimeRange: [0, 0], relativeTimeUnits: .days)

        let imageSet = ImageSetDefinition(
            number: 1,
            label: "Current Study",
            selectors: [selector],
            sortOperations: [sortOp],
            category: .relativeTime,
            timeSelection: timeSelection
        )

        XCTAssertEqual(imageSet.number, 1)
        XCTAssertEqual(imageSet.label, "Current Study")
        XCTAssertEqual(imageSet.selectors.count, 1)
        XCTAssertEqual(imageSet.sortOperations.count, 1)
        XCTAssertEqual(imageSet.category, .relativeTime)
        XCTAssertNotNil(imageSet.timeSelection)
    }
    
    func test_imageSetDefinition_multipleSelectors() {
        let selector1 = ImageSetSelector(attribute: .modality, values: ["CT"])
        let selector2 = ImageSetSelector(attribute: .seriesDescription, values: ["CHEST"])
        
        let imageSet = ImageSetDefinition(number: 1, selectors: [selector1, selector2])
        
        XCTAssertEqual(imageSet.selectors.count, 2)
    }
    
    func test_imageSetDefinition_multipleSortOperations() {
        let sort1 = SortOperation(sortByCategory: .byAcquisitionTime)
        let sort2 = SortOperation(attribute: .instanceNumber)
        
        let imageSet = ImageSetDefinition(number: 1, sortOperations: [sort1, sort2])
        
        XCTAssertEqual(imageSet.sortOperations.count, 2)
    }
    
    // MARK: - ImageSetSelector Tests
    
    func test_imageSetSelector_initialization_withMinimalParameters() {
        let selector = ImageSetSelector(attribute: .modality, values: ["CT"])
        
        XCTAssertEqual(selector.attribute, .modality)
        XCTAssertNil(selector.valueNumber)
        XCTAssertNil(selector.operator)
        XCTAssertEqual(selector.values, ["CT"])
        XCTAssertEqual(selector.usageFlag, .match)
    }
    
    func test_imageSetSelector_initialization_withAllParameters() {
        let selector = ImageSetSelector(
            attribute: .seriesDescription,
            valueNumber: 1,
            operator: .memberOf,
            values: ["CHEST", "THORAX"],
            usageFlag: .match
        )

        XCTAssertEqual(selector.attribute, .seriesDescription)
        XCTAssertEqual(selector.valueNumber, 1)
        XCTAssertEqual(selector.operator, .memberOf)
        XCTAssertNil(selector.filterByCategory)
        XCTAssertNil(selector.attributePresence)
        XCTAssertEqual(selector.values.count, 2)
        XCTAssertEqual(selector.usageFlag, .match)
    }
    
    func test_imageSetSelector_noMatchFlag() {
        let selector = ImageSetSelector(
            attribute: .modality,
            values: ["DX"],
            usageFlag: .noMatch
        )
        
        XCTAssertEqual(selector.usageFlag, .noMatch, "Should exclude matching images")
    }
    
    func test_imageSetSelector_multipleValues() {
        let selector = ImageSetSelector(
            attribute: .modality,
            values: ["CT", "MR", "CR"]
        )
        
        XCTAssertEqual(selector.values.count, 3, "Should support multiple values")
        XCTAssertTrue(selector.values.contains("CT"))
        XCTAssertTrue(selector.values.contains("MR"))
        XCTAssertTrue(selector.values.contains("CR"))
    }
    
    // MARK: - SelectorUsageFlag Tests
    
    func test_selectorUsageFlag_rawValues() {
        XCTAssertEqual(SelectorUsageFlag.match.rawValue, "MATCH")
        XCTAssertEqual(SelectorUsageFlag.noMatch.rawValue, "NO_MATCH")
    }
    
    func test_selectorUsageFlag_fromString() {
        XCTAssertEqual(SelectorUsageFlag(rawValue: "MATCH"), .match)
        XCTAssertEqual(SelectorUsageFlag(rawValue: "NO_MATCH"), .noMatch)
        XCTAssertNil(SelectorUsageFlag(rawValue: "INVALID"))
    }
    
    // MARK: - FilterOperator Tests

    /// PS3.3 2026a Table C.23.3-1, Filter-by Operator (0072,0406) Enumerated Values
    func test_filterOperator_standardTerms() {
        XCTAssertEqual(FilterOperator.rangeInclusive.rawValue, "RANGE_INCL")
        XCTAssertEqual(FilterOperator.rangeExclusive.rawValue, "RANGE_EXCL")
        XCTAssertEqual(FilterOperator.greaterThanOrEqual.rawValue, "GREATER_OR_EQUAL")
        XCTAssertEqual(FilterOperator.lessThanOrEqual.rawValue, "LESS_OR_EQUAL")
        XCTAssertEqual(FilterOperator.greaterThan.rawValue, "GREATER_THAN")
        XCTAssertEqual(FilterOperator.lessThan.rawValue, "LESS_THAN")
        XCTAssertEqual(FilterOperator.memberOf.rawValue, "MEMBER_OF")
        XCTAssertEqual(FilterOperator.notMemberOf.rawValue, "NOT_MEMBER_OF")
    }

    func test_filterOperator_numericOperators() {
        // "applies only to numeric Selector Attribute (0072,0026) Values"
        let numeric: [FilterOperator] = [
            .rangeInclusive, .rangeExclusive, .greaterThanOrEqual, .lessThanOrEqual,
            .greaterThan, .lessThan
        ]
        XCTAssertTrue(numeric.allSatisfy(\.isNumeric))
        XCTAssertFalse(FilterOperator.memberOf.isNumeric)
        XCTAssertFalse(FilterOperator.notMemberOf.isNumeric)
    }

    func test_filterOperator_readsStandardTermsAndOldSpellings() {
        for op: FilterOperator in [.rangeInclusive, .rangeExclusive, .greaterThanOrEqual, .lessThanOrEqual,
                                   .greaterThan, .lessThan, .memberOf, .notMemberOf] {
            XCTAssertEqual(FilterOperator.reading(op.rawValue), op)
        }
        // Old DICOMKit spellings: "MEMBER_OF ... if one value is present in each, this is an 'equal to' operator"
        XCTAssertEqual(FilterOperator.reading("EQUAL"), .memberOf)
        XCTAssertEqual(FilterOperator.reading("NOT_EQUAL"), .notMemberOf)
        XCTAssertEqual(FilterOperator.reading("CONTAINS"), .memberOf)
        // Presence terms belong to Filter-by Attribute Presence (0072,0404)
        XCTAssertNil(FilterOperator.reading("PRESENT"))
        XCTAssertNil(FilterOperator.reading("NOT_PRESENT"))
        XCTAssertNil(FilterOperator.reading("INVALID"))
    }

    /// The deprecated cases serialise to a Table C.23.3-1 term or to (0072,0404)
    @available(*, deprecated)
    func test_filterOperator_deprecatedCasesMap() {
        XCTAssertEqual(FilterOperator.equal.standardTerm, .memberOf)
        XCTAssertEqual(FilterOperator.notEqual.standardTerm, .notMemberOf)
        XCTAssertEqual(FilterOperator.contains.standardTerm, .memberOf)
        XCTAssertNil(FilterOperator.present.standardTerm)
        XCTAssertNil(FilterOperator.notPresent.standardTerm)
        XCTAssertEqual(FilterOperator.present.presenceTerm, .present)
        XCTAssertEqual(FilterOperator.notPresent.presenceTerm, .notPresent)
        XCTAssertNil(FilterOperator.memberOf.presenceTerm)
    }

    // MARK: - Filter-by Category / Attribute Presence / Image Plane

    /// PS3.3 2026a Table C.23.3-1: Filter-by Category (0072,0402) Defined Terms
    func test_filterByCategory_rawValues() {
        XCTAssertEqual(FilterByCategory.imagePlane.rawValue, "IMAGE_PLANE")
        XCTAssertEqual(FilterByCategory(rawValue: "IMAGE_PLANE"), .imagePlane)
    }

    /// PS3.3 2026a Table C.23.3-1: Filter-by Attribute Presence (0072,0404) Enumerated Values
    func test_filterByAttributePresence_rawValues() {
        XCTAssertEqual(FilterByAttributePresence.present.rawValue, "PRESENT")
        XCTAssertEqual(FilterByAttributePresence.notPresent.rawValue, "NOT_PRESENT")
        XCTAssertNil(FilterByAttributePresence(rawValue: "INVALID"))
    }

    /// PS3.3 2026a C.23.3.1.1: Selector CS Value Enumerated Values for IMAGE_PLANE
    func test_imagePlane_rawValues() {
        XCTAssertEqual(ImagePlane.transverse.rawValue, "TRANSVERSE")
        XCTAssertEqual(ImagePlane.coronal.rawValue, "CORONAL")
        XCTAssertEqual(ImagePlane.sagittal.rawValue, "SAGITTAL")
        XCTAssertEqual(ImagePlane.oblique.rawValue, "OBLIQUE")
        XCTAssertEqual(ImagePlane.allCases.count, 4)
        XCTAssertEqual(ImagePlane.reading("AXIAL"), .transverse, "old DICOMKit spelling")
        XCTAssertNil(ImagePlane.reading("INVALID"))
    }

    /// PS3.3 2026a C.23.3.1.1: normal of the orientation; x -> SAGITTAL, y -> CORONAL,
    /// z -> TRANSVERSE, all below threshold -> OBLIQUE
    func test_imagePlane_fromImageOrientationPatient() {
        XCTAssertEqual(ImagePlane(imageOrientationPatient: [1, 0, 0, 0, 1, 0]), .transverse)
        XCTAssertEqual(ImagePlane(imageOrientationPatient: [1, 0, 0, 0, 0, -1]), .coronal)
        XCTAssertEqual(ImagePlane(imageOrientationPatient: [0, 1, 0, 0, 0, -1]), .sagittal)
        let c = 1.0 / 3.0.squareRoot()
        XCTAssertEqual(ImagePlane(imageOrientationPatient: [c, -c, 0, c, c, -c]), .oblique)
        XCTAssertNil(ImagePlane(imageOrientationPatient: [1, 0, 0]))
    }

    // MARK: - ImageSetSelectorCategory Tests

    /// PS3.3 2026a Table C.23.1-1: Image Set Selector Category (0072,0034) Enumerated Values
    func test_imageSetSelectorCategory_rawValues() {
        XCTAssertEqual(ImageSetSelectorCategory.relativeTime.rawValue, "RELATIVE_TIME")
        XCTAssertEqual(ImageSetSelectorCategory.abstractPrior.rawValue, "ABSTRACT_PRIOR")
    }

    func test_imageSetSelectorCategory_fromString() {
        XCTAssertEqual(ImageSetSelectorCategory.reading("RELATIVE_TIME"), .relativeTime)
        XCTAssertEqual(ImageSetSelectorCategory.reading("ABSTRACT_PRIOR"), .abstractPrior)
        // Old DICOMKit spellings map: CURRENT is Relative Time 0\0, the others are abstract priors
        XCTAssertEqual(ImageSetSelectorCategory.reading("CURRENT"), .relativeTime)
        XCTAssertEqual(ImageSetSelectorCategory.reading("PRIOR"), .abstractPrior)
        XCTAssertEqual(ImageSetSelectorCategory.reading("COMPARISON"), .abstractPrior)
        XCTAssertNil(ImageSetSelectorCategory.reading("INVALID"))
    }

    @available(*, deprecated)
    func test_imageSetSelectorCategory_deprecatedCasesMap() {
        XCTAssertEqual(ImageSetSelectorCategory.current.standardTerm, .relativeTime)
        XCTAssertEqual(ImageSetSelectorCategory.prior.standardTerm, .abstractPrior)
        XCTAssertEqual(ImageSetSelectorCategory.comparison.standardTerm, .abstractPrior)
    }

    // MARK: - TimeBasedSelection Tests

    func test_timeBasedSelection_initialization_empty() {
        let selection = TimeBasedSelection()

        XCTAssertTrue(selection.relativeTimeRange.isEmpty)
        XCTAssertNil(selection.relativeTimeUnits)
        XCTAssertTrue(selection.abstractPriorRange.isEmpty)
    }

    /// PS3.3 2026a Table C.23.1-1 Relative Time (0072,0038): "Exactly two numeric values,
    /// indicating the start and end values of a prior range"
    func test_timeBasedSelection_relativeTimeRange_days() {
        let selection = TimeBasedSelection(relativeTimeRange: [7, 30], relativeTimeUnits: .days)

        XCTAssertEqual(selection.relativeTimeRange, [7, 30])
        XCTAssertEqual(selection.relativeTimeUnits, .days)
        XCTAssertTrue(selection.abstractPriorRange.isEmpty)
    }

    /// PS3.3 2026a Table C.23.1-1 Abstract Prior Value (0072,003C): "1 indicates the most
    /// recent prior ... The special value -1 shall indicate the oldest prior"
    func test_timeBasedSelection_abstractPriorRange() {
        let selection = TimeBasedSelection(abstractPriorRange: [1, 3])

        XCTAssertTrue(selection.relativeTimeRange.isEmpty)
        XCTAssertEqual(selection.abstractPriorRange, [1, 3])
        XCTAssertEqual(TimeBasedSelection.mostRecentPrior, 1)
        XCTAssertEqual(TimeBasedSelection.oldestPrior, -1)
    }

    /// The old String member maps onto the SS pair
    @available(*, deprecated)
    func test_timeBasedSelection_deprecatedMembersMap() {
        let single = TimeBasedSelection(relativeTime: 30, relativeTimeUnits: .days)
        XCTAssertEqual(single.relativeTimeRange, [30, 30], "n\\n is prior by n units")
        XCTAssertEqual(single.relativeTime, 30)

        let mostRecent = TimeBasedSelection(abstractPriorValue: "MOST_RECENT")
        XCTAssertEqual(mostRecent.abstractPriorRange, [1, 1])
        XCTAssertEqual(mostRecent.abstractPriorValue, "MOST_RECENT")

        let oldest = TimeBasedSelection(abstractPriorValue: "OLDEST")
        XCTAssertEqual(oldest.abstractPriorRange, [-1, -1])
        XCTAssertEqual(oldest.abstractPriorValue, "OLDEST")

        XCTAssertEqual(TimeBasedSelection(abstractPriorValue: "2").abstractPriorRange, [2, 2])
        XCTAssertEqual(TimeBasedSelection(abstractPriorValue: "1\\3").abstractPriorRange, [1, 3])
        XCTAssertTrue(TimeBasedSelection(abstractPriorValue: "SOMETHING").abstractPriorRange.isEmpty,
                      "text with no SS encoding is dropped")
    }
    
    // MARK: - RelativeTimeUnits Tests

    /// PS3.3 2026a Table C.23.1-1: Relative Time Units (0072,003A) Enumerated Values
    func test_relativeTimeUnits_allValues() {
        XCTAssertEqual(RelativeTimeUnits.seconds.rawValue, "SECONDS")
        XCTAssertEqual(RelativeTimeUnits.minutes.rawValue, "MINUTES")
        XCTAssertEqual(RelativeTimeUnits.hours.rawValue, "HOURS")
        XCTAssertEqual(RelativeTimeUnits.days.rawValue, "DAYS")
        XCTAssertEqual(RelativeTimeUnits.weeks.rawValue, "WEEKS")
        XCTAssertEqual(RelativeTimeUnits.months.rawValue, "MONTHS")
        XCTAssertEqual(RelativeTimeUnits.years.rawValue, "YEARS")
    }
    
    func test_relativeTimeUnits_fromString() {
        XCTAssertEqual(RelativeTimeUnits(rawValue: "DAYS"), .days)
        XCTAssertEqual(RelativeTimeUnits(rawValue: "MONTHS"), .months)
        XCTAssertEqual(RelativeTimeUnits(rawValue: "YEARS"), .years)
        XCTAssertNil(RelativeTimeUnits(rawValue: "INVALID"))
    }
    
    // MARK: - SortOperation Tests
    
    func test_sortOperation_initialization_withCategory() {
        let sort = SortOperation(sortByCategory: .alongAxis)

        XCTAssertEqual(sort.sortByCategory, .alongAxis)
        XCTAssertEqual(sort.direction, .ascending)
        XCTAssertNil(sort.attribute)
        XCTAssertNil(sort.valueNumber)
    }

    func test_sortOperation_initialization_withDirection() {
        let sort = SortOperation(sortByCategory: .byAcquisitionTime, direction: .descending)

        XCTAssertEqual(sort.sortByCategory, .byAcquisitionTime)
        XCTAssertEqual(sort.direction, .descending)
    }

    /// PS3.3 2026a Table C.23.3-1: Selector Attribute (0072,0026) "Required if Sort-by
    /// Category (0072,0602) is not present", with Selector Value Number (0072,0028)
    func test_sortOperation_initialization_withAttribute() {
        let sort = SortOperation(attribute: .sliceLocation, direction: .ascending)

        XCTAssertNil(sort.sortByCategory)
        XCTAssertEqual(sort.direction, .ascending)
        XCTAssertEqual(sort.attribute, .sliceLocation)
        XCTAssertEqual(sort.valueNumber, 1)
    }

    // MARK: - SortByCategory Tests

    /// PS3.3 2026a Table C.23.3-1: Sort-by Category (0072,0602) Defined Terms
    func test_sortByCategory_standardTerms() {
        XCTAssertEqual(SortByCategory.alongAxis.rawValue, "ALONG_AXIS")
        XCTAssertEqual(SortByCategory.byAcquisitionTime.rawValue, "BY_ACQ_TIME")
    }

    func test_sortByCategory_fromString() {
        XCTAssertEqual(SortByCategory(rawValue: "ALONG_AXIS"), .alongAxis)
        XCTAssertEqual(SortByCategory(rawValue: "BY_ACQ_TIME"), .byAcquisitionTime)
        XCTAssertNil(SortByCategory(rawValue: "INVALID"))
    }

    /// The deprecated categories become a Defined Term or a Selector Attribute sort
    @available(*, deprecated)
    func test_sortByCategory_deprecatedCasesMap() {
        let acq = SortOperation(sortByCategory: .acquisitionTime).standardized
        XCTAssertEqual(acq.category, .byAcquisitionTime)
        XCTAssertNil(acq.attribute)

        let pos = SortOperation(sortByCategory: .imagePosition).standardized
        XCTAssertEqual(pos.category, .alongAxis)

        let inst = SortOperation(sortByCategory: .instanceNumber).standardized
        XCTAssertNil(inst.category)
        XCTAssertEqual(inst.attribute, .instanceNumber)
        XCTAssertEqual(inst.valueNumber, 1)

        let slice = SortOperation(sortByCategory: .sliceLocation).standardized
        XCTAssertNil(slice.category)
        XCTAssertEqual(slice.attribute, .sliceLocation)

        let attr = SortOperation(sortByCategory: .attribute, attribute: .acquisitionTime).standardized
        XCTAssertNil(attr.category)
        XCTAssertEqual(attr.attribute, .acquisitionTime)
        XCTAssertEqual(attr.valueNumber, 1)
    }
    
    // MARK: - SortDirection Tests
    
    func test_sortDirection_rawValues() {
        // PS3.3 Table C.23.3-1 Sorting Direction: INCREASING, DECREASING
        XCTAssertEqual(SortDirection.ascending.rawValue, "INCREASING")
        XCTAssertEqual(SortDirection.descending.rawValue, "DECREASING")
    }

    func test_sortDirection_fromString() {
        XCTAssertEqual(SortDirection(rawValue: "INCREASING"), .ascending)
        XCTAssertEqual(SortDirection(rawValue: "DECREASING"), .descending)
        XCTAssertNil(SortDirection(rawValue: "INVALID"))
    }
}
