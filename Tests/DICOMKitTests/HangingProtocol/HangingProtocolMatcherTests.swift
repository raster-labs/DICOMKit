//
// HangingProtocolMatcherTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class HangingProtocolMatcherTests: XCTestCase {
    
    // MARK: - HangingProtocolMatcher Tests
    
    func test_matcher_initialization_empty() async {
        let matcher = HangingProtocolMatcher()
        let protocols = await matcher.allProtocols()
        
        XCTAssertEqual(protocols.count, 0, "Should initialize with no protocols")
    }
    
    func test_matcher_initialization_withProtocols() async {
        let hangingProtocol = HangingProtocol(name: "Test")
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        let protocols = await matcher.allProtocols()
        
        XCTAssertEqual(protocols.count, 1, "Should initialize with provided protocols")
    }
    
    func test_matcher_addProtocol() async {
        let matcher = HangingProtocolMatcher()
        let hangingProtocol = HangingProtocol(name: "Test Protocol")
        
        await matcher.add(protocol: hangingProtocol)
        let protocols = await matcher.allProtocols()
        
        XCTAssertEqual(protocols.count, 1, "Should add protocol")
        XCTAssertEqual(protocols[0].name, "Test Protocol")
    }
    
    func test_matcher_removeProtocol() async {
        let hangingProtocol = HangingProtocol(name: "To Remove")
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        await matcher.remove(protocolNamed: "To Remove")
        let protocols = await matcher.allProtocols()
        
        XCTAssertEqual(protocols.count, 0, "Should remove protocol by name")
    }
    
    func test_matcher_removeNonexistentProtocol() async {
        let hangingProtocol = HangingProtocol(name: "Test")
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        await matcher.remove(protocolNamed: "Nonexistent")
        let protocols = await matcher.allProtocols()
        
        XCTAssertEqual(protocols.count, 1, "Should not remove if name doesn't match")
    }
    
    // MARK: - Protocol Matching Tests
    
    func test_matchProtocol_noEnvironments_matchesAll() async {
        let hangingProtocol = HangingProtocol(name: "Generic")
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3", modalities: ["CT"])
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertNotNil(match, "Protocol with no environments should match any study")
        XCTAssertEqual(match?.name, "Generic")
    }
    
    func test_matchProtocol_modalityMatch() async {
        let env = HangingProtocolEnvironment(modality: "CT")
        let hangingProtocol = HangingProtocol(name: "CT Protocol", environments: [env])
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3", modalities: ["CT"])
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertNotNil(match, "Should match when modality matches")
        XCTAssertEqual(match?.name, "CT Protocol")
    }
    
    func test_matchProtocol_modalityMismatch() async {
        let env = HangingProtocolEnvironment(modality: "MR")
        let hangingProtocol = HangingProtocol(name: "MR Protocol", environments: [env])
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3", modalities: ["CT"])
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertNil(match, "Should not match when modality doesn't match")
    }
    
    func test_matchProtocol_lateralityMatch() async {
        let env = HangingProtocolEnvironment(modality: "DX", laterality: "L")
        let hangingProtocol = HangingProtocol(name: "Left DX", environments: [env])
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3", modalities: ["DX"], laterality: "L")
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertNotNil(match, "Should match when both modality and laterality match")
    }
    
    func test_matchProtocol_lateralityMismatch() async {
        let env = HangingProtocolEnvironment(modality: "DX", laterality: "R")
        let hangingProtocol = HangingProtocol(name: "Right DX", environments: [env])
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3", modalities: ["DX"], laterality: "L")
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertNil(match, "Should not match when laterality doesn't match")
    }
    
    func test_matchProtocol_multipleEnvironments() async {
        let env1 = HangingProtocolEnvironment(modality: "CT")
        let env2 = HangingProtocolEnvironment(modality: "MR")
        let hangingProtocol = HangingProtocol(name: "Multi-Modal", environments: [env1, env2])
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3", modalities: ["MR"])
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertNotNil(match, "Should match if any environment matches")
    }
    
    // MARK: - Priority Ordering Tests
    
    func test_matchProtocol_priorityOrdering_userOverGroup() async {
        let userProtocol = HangingProtocol(name: "User", level: .user)
        let groupProtocol = HangingProtocol(name: "Group", level: .group)
        let matcher = HangingProtocolMatcher(protocols: [groupProtocol, userProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3")
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertEqual(match?.name, "User", "User level should have priority over group")
    }
    
    func test_matchProtocol_priorityOrdering_groupOverSite() async {
        let siteProtocol = HangingProtocol(name: "Site", level: .site)
        let groupProtocol = HangingProtocol(name: "Group", level: .group)
        let matcher = HangingProtocolMatcher(protocols: [siteProtocol, groupProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3")
        let match = await matcher.matchProtocol(for: studyInfo)
        
        XCTAssertEqual(match?.name, "Group", "Group level should have priority over site")
    }
    
    func test_matchProtocol_priorityOrdering_userOverSite() async {
        let siteProtocol = HangingProtocol(name: "Site", level: .site)
        let userProtocol = HangingProtocol(name: "User", level: .user)
        let matcher = HangingProtocolMatcher(protocols: [siteProtocol, userProtocol])

        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3")
        let match = await matcher.matchProtocol(for: studyInfo)

        XCTAssertEqual(match?.name, "User", "User level should have priority over site")
    }

    /// PS3.3 2026a Table C.23.1-1 Hanging Protocol Level MANUFACTURER ranks below SITE
    func test_matchProtocol_priorityOrdering_siteOverManufacturer() async {
        let manufacturerProtocol = HangingProtocol(name: "Manufacturer", level: .manufacturer)
        let siteProtocol = HangingProtocol(name: "Site", level: .site)
        let matcher = HangingProtocolMatcher(protocols: [manufacturerProtocol, siteProtocol])

        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3")
        let matches = await matcher.matchingProtocols(for: studyInfo)

        XCTAssertEqual(matches.map(\.name), ["Site", "Manufacturer"])
    }
    
    // MARK: - User Group Matching Tests
    
    func test_matchProtocol_userGroupMatch() async {
        let hangingProtocol = HangingProtocol(name: "Radiology", userGroups: ["Radiology"])
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3")
        let match = await matcher.matchProtocol(for: studyInfo, userGroup: "Radiology")
        
        XCTAssertNotNil(match, "Should match when user group matches")
    }
    
    func test_matchProtocol_userGroupMismatch() async {
        let hangingProtocol = HangingProtocol(name: "Radiology", userGroups: ["Radiology"])
        let matcher = HangingProtocolMatcher(protocols: [hangingProtocol])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3")
        let match = await matcher.matchProtocol(for: studyInfo, userGroup: "Cardiology")
        
        XCTAssertNil(match, "Should not match when user group doesn't match")
    }
    
    func test_matchingProtocols_returnsAllMatches() async {
        let `protocol1` = HangingProtocol(name: "Protocol 1", level: .site)
        let `protocol2` = HangingProtocol(name: "Protocol 2", level: .group)
        let matcher = HangingProtocolMatcher(protocols: [`protocol1`, `protocol2`])
        
        let studyInfo = StudyInfo(studyInstanceUID: "1.2.3")
        let matches = await matcher.matchingProtocols(for: studyInfo)
        
        XCTAssertEqual(matches.count, 2, "Should return all matching protocols")
    }
    
    // MARK: - StudyInfo Tests
    
    func test_studyInfo_initialization() {
        let studyInfo = StudyInfo(
            studyInstanceUID: "1.2.3.4",
            modalities: ["CT", "MR"],
            laterality: "L",
            studyDescription: "Chest CT",
            bodyPartExamined: "CHEST",
            attributes: [.patientName: "Doe^John"]
        )
        
        XCTAssertEqual(studyInfo.studyInstanceUID, "1.2.3.4")
        XCTAssertEqual(studyInfo.modalities.count, 2)
        XCTAssertTrue(studyInfo.modalities.contains("CT"))
        XCTAssertEqual(studyInfo.laterality, "L")
        XCTAssertEqual(studyInfo.studyDescription, "Chest CT")
        XCTAssertEqual(studyInfo.bodyPartExamined, "CHEST")
        XCTAssertEqual(studyInfo.attributes[.patientName], "Doe^John")
    }
    
    func test_studyInfo_fromDataSet() {
        var dataSet = DataSet()
        dataSet[.studyInstanceUID] = DataElement.string(tag: .studyInstanceUID, vr: .UI, value: "1.2.3.4")
        dataSet[.modality] = DataElement.string(tag: .modality, vr: .CS, value: "CT")
        dataSet[.laterality] = DataElement.string(tag: .laterality, vr: .CS, value: "R")
        dataSet[.studyDescription] = DataElement.string(tag: .studyDescription, vr: .LO, value: "Brain MRI")
        
        let studyInfo = StudyInfo(from: dataSet)
        
        XCTAssertNotNil(studyInfo)
        XCTAssertEqual(studyInfo?.studyInstanceUID, "1.2.3.4")
        XCTAssertTrue(studyInfo?.modalities.contains("CT") ?? false)
        XCTAssertEqual(studyInfo?.laterality, "R")
        XCTAssertEqual(studyInfo?.studyDescription, "Brain MRI")
    }
    
    func test_studyInfo_fromDataSet_missingStudyUID() {
        let dataSet = DataSet()
        
        let studyInfo = StudyInfo(from: dataSet)
        
        XCTAssertNil(studyInfo, "Should return nil if Study Instance UID is missing")
    }
    
    // MARK: - ImageSetMatcher Tests
    
    func test_imageSetMatcher_matches_simpleSelector() {
        let selector = ImageSetSelector(attribute: .modality, values: ["CT"])
        let imageSet = ImageSetDefinition(number: 1, selectors: [selector])
        let matcher = ImageSetMatcher(imageSet: imageSet)
        
        let instance = InstanceInfo(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2",
            attributes: [.modality: "CT"]
        )
        
        XCTAssertTrue(matcher.matches(instance: instance), "Should match when attribute matches")
    }
    
    func test_imageSetMatcher_matches_mismatch() {
        let selector = ImageSetSelector(attribute: .modality, values: ["MR"])
        let imageSet = ImageSetDefinition(number: 1, selectors: [selector])
        let matcher = ImageSetMatcher(imageSet: imageSet)
        
        let instance = InstanceInfo(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2",
            attributes: [.modality: "CT"]
        )
        
        XCTAssertFalse(matcher.matches(instance: instance), "Should not match when attribute doesn't match")
    }
    
    /// PS3.3 2026a Table C.23.1-1 Image Set Selector Usage Flag (0072,0024): the flag
    /// decides only when the Attribute is not in the image object. NO_MATCH: "do not
    /// consider the image to be a match"; MATCH: "consider the image to be a match anyway".
    func test_imageSetMatcher_usageFlag_attributeAbsent() {
        let noMatch = ImageSetSelector(attribute: .modality, values: ["DX"], usageFlag: .noMatch)
        let match = ImageSetSelector(attribute: .modality, values: ["DX"], usageFlag: .match)
        let instance = InstanceInfo(sopInstanceUID: "1.2.3", seriesInstanceUID: "1.2", attributes: [:])

        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [noMatch])).matches(instance: instance))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [match])).matches(instance: instance))
    }

    func test_imageSetMatcher_usageFlag_doesNotChangeAValueMismatch() {
        let selector = ImageSetSelector(attribute: .modality, values: ["DX"], usageFlag: .noMatch)
        let imageSet = ImageSetDefinition(number: 1, selectors: [selector])
        let matcher = ImageSetMatcher(imageSet: imageSet)

        let instance = InstanceInfo(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2",
            attributes: [.modality: "CT"]
        )

        XCTAssertFalse(matcher.matches(instance: instance), "the attribute is present and CT is not DX")
    }

    /// PS3.3 2026a Table C.23.3-1 Filter-by Attribute Presence (0072,0404)
    func test_imageSetMatcher_matches_attributePresence() {
        let present = ImageSetSelector(attribute: .sliceLocation, attributePresence: .present)
        let notPresent = ImageSetSelector(attribute: .sliceLocation, attributePresence: .notPresent)

        let withSlice = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.sliceLocation: "100.5"])
        let withoutSlice = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.modality: "CT"])

        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [present])).matches(instance: withSlice))
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [present])).matches(instance: withoutSlice))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notPresent])).matches(instance: withoutSlice))
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notPresent])).matches(instance: withSlice))
    }

    /// The deprecated PRESENT / NOT_PRESENT operators still act as Filter-by Attribute Presence
    @available(*, deprecated)
    func test_imageSetMatcher_matches_deprecatedPresenceOperators() {
        let present = ImageSetSelector(attribute: .sliceLocation, operator: .present, values: [])
        let notPresent = ImageSetSelector(attribute: .sliceLocation, operator: .notPresent, values: [])
        let withSlice = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.sliceLocation: "100.5"])
        let withoutSlice = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.modality: "CT"])

        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [present])).matches(instance: withSlice))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notPresent])).matches(instance: withoutSlice))
    }

    /// PS3.3 2026a Table C.23.3-1 MEMBER_OF: "one of the values in the image is present in
    /// the values of the selector"; NOT_MEMBER_OF: "none of the values in the image is present"
    func test_imageSetMatcher_matches_memberOf() {
        let memberOf = ImageSetSelector(attribute: .imageType, operator: .memberOf, values: ["PRIMARY", "ORIGINAL"])
        let notMemberOf = ImageSetSelector(attribute: .imageType, operator: .notMemberOf, values: ["DERIVED", "SECONDARY"])
        let noOperator = ImageSetSelector(attribute: .modality, values: ["CT", "MR"])

        let ct = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1",
                              attributes: [.imageType: "ORIGINAL\\PRIMARY\\AXIAL", .modality: "CT"])
        let derived = InstanceInfo(sopInstanceUID: "2", seriesInstanceUID: "1",
                                   attributes: [.imageType: "DERIVED\\SECONDARY", .modality: "DX"])

        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [memberOf])).matches(instance: ct))
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [memberOf])).matches(instance: derived))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notMemberOf])).matches(instance: ct))
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notMemberOf])).matches(instance: derived))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [noOperator])).matches(instance: ct), "no operator is MEMBER_OF")
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [noOperator])).matches(instance: derived))
    }

    /// PS3.3 2026a Table C.23.1-1 Selector Value Number (0072,0028): "which Value of a
    /// multi-valued Attribute ... is to be used"; zero identifies any value
    func test_imageSetMatcher_matches_selectorValueNumber() {
        let third = ImageSetSelector(attribute: .imageType, valueNumber: 3, values: ["AXIAL"])
        let any = ImageSetSelector(attribute: .imageType, valueNumber: 0, values: ["AXIAL"])
        let ct = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.imageType: "ORIGINAL\\PRIMARY\\AXIAL"])
        let twoValues = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.imageType: "AXIAL\\PRIMARY"])

        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [third])).matches(instance: ct))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [any])).matches(instance: ct))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [any])).matches(instance: twoValues))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [third])).matches(instance: twoValues),
                      "value 3 is not available, so the MATCH usage flag applies")
    }

    /// PS3.3 2026a Table C.23.3-1 RANGE_INCL: "all values lie within the specified range, or
    /// are equal to the endpoints"; RANGE_EXCL: "all values lie outside the specified range,
    /// and are not equal to the endpoints"; two selector values, the first <= the second
    func test_imageSetMatcher_matches_rangeOperators() {
        let inclusive = ImageSetSelector(attribute: .sliceLocation, operator: .rangeInclusive, values: ["10", "20"])
        let exclusive = ImageSetSelector(attribute: .sliceLocation, operator: .rangeExclusive, values: ["10", "20"])
        let badRange = ImageSetSelector(attribute: .sliceLocation, operator: .rangeInclusive, values: ["20", "10"])
        let oneValue = ImageSetSelector(attribute: .sliceLocation, operator: .rangeInclusive, values: ["10"])

        func instance(_ slice: String) -> InstanceInfo {
            InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.sliceLocation: slice])
        }
        func matches(_ selector: ImageSetSelector, _ slice: String) -> Bool {
            ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [selector])).matches(instance: instance(slice))
        }

        XCTAssertTrue(matches(inclusive, "15.5"))
        XCTAssertTrue(matches(inclusive, "10"), "endpoint is inside for RANGE_INCL")
        XCTAssertTrue(matches(inclusive, "20.0"))
        XCTAssertFalse(matches(inclusive, "25"))

        XCTAssertTrue(matches(exclusive, "25"))
        XCTAssertTrue(matches(exclusive, "-3"))
        XCTAssertFalse(matches(exclusive, "20"), "endpoint is not outside for RANGE_EXCL")
        XCTAssertFalse(matches(exclusive, "15"))

        XCTAssertFalse(matches(badRange, "15"), "first value must be <= second")
        XCTAssertFalse(matches(oneValue, "10"), "two values shall be present")
        XCTAssertFalse(matches(inclusive, "abc"), "applies only to numeric values")
    }

    /// PS3.3 2026a Table C.23.3-1 GREATER_OR_EQUAL / LESS_OR_EQUAL / GREATER_THAN / LESS_THAN:
    /// numeric comparison of all image values with the selector value
    func test_imageSetMatcher_matches_comparisonOperators() {
        func matches(_ op: FilterOperator, _ slice: String) -> Bool {
            let selector = ImageSetSelector(attribute: .sliceLocation, operator: op, values: ["100"])
            let instance = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.sliceLocation: slice])
            return ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [selector])).matches(instance: instance)
        }

        XCTAssertTrue(matches(.greaterThan, "100.5"))
        XCTAssertFalse(matches(.greaterThan, "100"))
        XCTAssertTrue(matches(.greaterThanOrEqual, "100"))
        XCTAssertFalse(matches(.greaterThanOrEqual, "99"))
        XCTAssertTrue(matches(.lessThan, "99"))
        XCTAssertFalse(matches(.lessThan, "100"))
        XCTAssertTrue(matches(.lessThanOrEqual, "100"))
        XCTAssertFalse(matches(.lessThanOrEqual, "1000"), "numeric, not lexical: '1000' > '100'")
    }

    /// PS3.3 2026a C.23.3.1.1: IMAGE_PLANE with Selector CS Value TRANSVERSE / CORONAL /
    /// SAGITTAL / OBLIQUE, computed from Image Orientation (Patient); MEMBER_OF applies
    func test_imageSetMatcher_matches_imagePlaneCategory() {
        let transverse = ImageSetSelector(
            attribute: .imageOrientationPatient,
            attributeVR: .CS,
            operator: .memberOf,
            filterByCategory: .imagePlane,
            values: [ImagePlane.transverse.rawValue]
        )
        let notSagittal = ImageSetSelector(
            attribute: .imageOrientationPatient,
            attributeVR: .CS,
            operator: .notMemberOf,
            filterByCategory: .imagePlane,
            values: [ImagePlane.sagittal.rawValue]
        )
        let axial = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1",
                                 attributes: [.imageOrientationPatient: "1\\0\\0\\0\\1\\0"])
        let sagittal = InstanceInfo(sopInstanceUID: "2", seriesInstanceUID: "1",
                                    attributes: [.imageOrientationPatient: "0\\1\\0\\0\\0\\-1"])
        let noOrientation = InstanceInfo(sopInstanceUID: "3", seriesInstanceUID: "1", attributes: [:])

        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [transverse])).matches(instance: axial))
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [transverse])).matches(instance: sagittal))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notSagittal])).matches(instance: axial))
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notSagittal])).matches(instance: sagittal))
        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [transverse])).matches(instance: noOrientation),
                      "no orientation: the MATCH usage flag applies")
    }

    /// The deprecated CONTAINS operator keeps substring matching on the way out
    @available(*, deprecated)
    func test_imageSetMatcher_matches_containsOperator() {
        let selector = ImageSetSelector(attribute: .seriesDescription, operator: .contains, values: ["CHEST"])
        let imageSet = ImageSetDefinition(number: 1, selectors: [selector])
        let matcher = ImageSetMatcher(imageSet: imageSet)

        let instance = InstanceInfo(
            sopInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2",
            attributes: [.seriesDescription: "CHEST CT ANGIO"]
        )

        XCTAssertTrue(matcher.matches(instance: instance), "Should match when value contains substring")
    }

    @available(*, deprecated)
    func test_imageSetMatcher_matches_deprecatedEqualOperators() {
        let equal = ImageSetSelector(attribute: .modality, operator: .equal, values: ["CT"])
        let notEqual = ImageSetSelector(attribute: .modality, operator: .notEqual, values: ["CT"])
        let ct = InstanceInfo(sopInstanceUID: "1", seriesInstanceUID: "1", attributes: [.modality: "CT"])

        XCTAssertTrue(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [equal])).matches(instance: ct))
        XCTAssertFalse(ImageSetMatcher(imageSet: ImageSetDefinition(number: 1, selectors: [notEqual])).matches(instance: ct))
    }
    
    // MARK: - InstanceInfo Tests
    
    func test_instanceInfo_initialization() {
        let instance = InstanceInfo(
            sopInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4",
            attributes: [.instanceNumber: "1", .sliceLocation: "100.0"]
        )
        
        XCTAssertEqual(instance.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(instance.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(instance.attributes[.instanceNumber], "1")
        XCTAssertEqual(instance.attributes[.sliceLocation], "100.0")
    }
    
    func test_instanceInfo_fromDataSet() {
        var dataSet = DataSet()
        dataSet[.sopInstanceUID] = DataElement.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5")
        dataSet[.seriesInstanceUID] = DataElement.string(tag: .seriesInstanceUID, vr: .UI, value: "1.2.3.4")
        dataSet[.instanceNumber] = DataElement.string(tag: .instanceNumber, vr: .IS, value: "1")
        dataSet[.modality] = DataElement.string(tag: .modality, vr: .CS, value: "CT")
        dataSet[.imageOrientationPatient] = DataElement.strings(
            tag: .imageOrientationPatient, vr: .DS, values: ["1", "0", "0", "0", "1", "0"])

        let instance = InstanceInfo(from: dataSet)

        XCTAssertNotNil(instance)
        XCTAssertEqual(instance?.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(instance?.seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(instance?.attributes[.instanceNumber], "1")
        XCTAssertEqual(instance?.attributes[.modality], "CT")
        XCTAssertEqual(instance?.attributes[.imageOrientationPatient], "1\\0\\0\\0\\1\\0")
    }
    
    func test_instanceInfo_fromDataSet_missingRequiredFields() {
        var dataSet = DataSet()
        dataSet[.sopInstanceUID] = DataElement.string(tag: .sopInstanceUID, vr: .UI, value: "1.2.3.4.5")
        
        let instance = InstanceInfo(from: dataSet)
        
        XCTAssertNil(instance, "Should return nil if required fields are missing")
    }
}
