// PrivateTagIdentifierTests.swift
// DICOMStudioTests
//
// Tests for PrivateTagIdentifier

import Testing
@testable import DICOMStudio
import Foundation

@Suite("PrivateTagIdentifier Tests")
struct PrivateTagIdentifierTests {

    // MARK: - Vendor Identification

    @Test("Identifies Siemens from creator string")
    func testIdentifySiemens() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "SIEMENS MR HEADER") == "Siemens")
    }

    @Test("Identifies Siemens CSA header")
    func testIdentifySiemensCSA() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "SIEMENS CSA HEADER") == "Siemens")
    }

    @Test("Identifies GE from creator string")
    func testIdentifyGE() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "GEMS_ACQU_01") == "GE Healthcare")
    }

    @Test("Identifies Philips from creator string")
    func testIdentifyPhilips() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "Philips MR Imaging DD 001") == "Philips")
    }

    @Test("Identifies Toshiba from creator string")
    func testIdentifyToshiba() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "TOSHIBA_MEC_MR3") == "Toshiba/Canon")
    }

    @Test("Identifies vendor by prefix")
    func testIdentifyByPrefix() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "SIEMENS CUSTOM THING") == "Siemens")
        #expect(PrivateTagIdentifier.identifyVendor(creator: "GE CUSTOM") == "GE Healthcare")
        #expect(PrivateTagIdentifier.identifyVendor(creator: "PHILIPS CUSTOM") == "Philips")
    }

    @Test("Case-insensitive vendor lookup")
    func testCaseInsensitive() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "siemens mr header") == "Siemens")
    }

    @Test("Unknown vendor returns nil")
    func testUnknownVendor() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "UNKNOWN VENDOR") == nil)
    }

    @Test("Empty creator returns nil")
    func testEmptyCreator() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "") == nil)
    }

    @Test("Identifies Hologic")
    func testIdentifyHologic() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "HOLOGIC, Inc.") == "Hologic")
    }

    @Test("Identifies Fujifilm")
    func testIdentifyFujifilm() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "FUJI PHOTO FILM Co., Ltd.") == "Fujifilm")
    }

    @Test("Identifies AGFA")
    func testIdentifyAGFA() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "AGFA") == "AGFA")
    }

    @Test("Identifies Varian")
    func testIdentifyVarian() {
        #expect(PrivateTagIdentifier.identifyVendor(creator: "VARIAN Medical Systems VISION 8.0") == "Varian")
    }

    // MARK: - Private Group Detection

    @Test("Odd groups are private")
    func testOddGroupIsPrivate() {
        #expect(PrivateTagIdentifier.isPrivateGroup(0x0009))
        #expect(PrivateTagIdentifier.isPrivateGroup(0x0011))
        #expect(PrivateTagIdentifier.isPrivateGroup(0x7FE1))
    }

    @Test("Even groups are not private")
    func testEvenGroupNotPrivate() {
        #expect(!PrivateTagIdentifier.isPrivateGroup(0x0008))
        #expect(!PrivateTagIdentifier.isPrivateGroup(0x0010))
        #expect(!PrivateTagIdentifier.isPrivateGroup(0x7FE0))
    }

    @Test("The five odd groups PS3.5 2026a 7.8.1 excludes are not private")
    func testReservedOddGroupsNotPrivate() {
        for group: UInt16 in [0x0001, 0x0003, 0x0005, 0x0007, 0xFFFF] {
            #expect(!PrivateTagIdentifier.isPrivateGroup(group), "\(String(format: "%04X", group))")
            #expect(!PrivateTagIdentifier.isPrivateCreator(group: group, element: 0x0010))
        }
        #expect(PrivateTagIdentifier.isPrivateGroup(0x0009))
        #expect(PrivateTagIdentifier.isPrivateGroup(0xFFFD))
    }

    @Test("Group 0 is not private")
    func testGroupZeroNotPrivate() {
        #expect(!PrivateTagIdentifier.isPrivateGroup(0x0000))
    }

    // MARK: - Private Creator Detection

    @Test("Private creator elements in valid range")
    func testPrivateCreatorValid() {
        #expect(PrivateTagIdentifier.isPrivateCreator(group: 0x0009, element: 0x0010))
        #expect(PrivateTagIdentifier.isPrivateCreator(group: 0x0009, element: 0x00FF))
    }

    @Test("Non-private creator elements")
    func testPrivateCreatorInvalid() {
        #expect(!PrivateTagIdentifier.isPrivateCreator(group: 0x0009, element: 0x0000))
        #expect(!PrivateTagIdentifier.isPrivateCreator(group: 0x0009, element: 0x0100))
        #expect(!PrivateTagIdentifier.isPrivateCreator(group: 0x0008, element: 0x0010))
    }

    // MARK: - Display String

    @Test("Display string with known vendor")
    func testDisplayStringKnownVendor() {
        let result = PrivateTagIdentifier.displayString(
            group: 0x0009, element: 0x1010, creator: "SIEMENS MR HEADER"
        )
        #expect(result.contains("Siemens"))
        #expect(result.contains("(0009,1010)"))
    }

    @Test("Display string with unknown creator")
    func testDisplayStringUnknownCreator() {
        let result = PrivateTagIdentifier.displayString(
            group: 0x0009, element: 0x1010, creator: "CUSTOM"
        )
        #expect(result.contains("CUSTOM"))
        #expect(result.contains("(0009,1010)"))
    }

    @Test("Display string without creator")
    func testDisplayStringNoCreator() {
        let result = PrivateTagIdentifier.displayString(
            group: 0x0009, element: 0x1010, creator: nil
        )
        #expect(result.contains("Private"))
        #expect(result.contains("(0009,1010)"))
    }
}
