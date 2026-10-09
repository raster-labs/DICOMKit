//
// ICCProfileParserTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class ICCProfileParserTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    /// Create a minimal valid ICC profile header
    private func createMinimalICCProfileData(
        // 128-byte header + 4-byte tag count (ICC.1 7.3.1). The original
        // default of 128 left no room for the tag count written at 128.
        profileSize: UInt32 = 132,
        version: (major: UInt8, minor: UInt8, bugfix: UInt8) = (2, 1, 0),
        deviceClass: ICCDeviceClass = .displayDevice,
        dataColorSpace: ICCColorSpace = .rgb,
        pcs: ICCColorSpace = .xyz,
        renderingIntent: ICCRenderingIntent = .perceptual
    ) -> Data {
        var data = Data(count: Int(profileSize))
        
        // Profile size (0-3)
        data.writeUInt32BE(profileSize, at: 0)
        
        // Version (8-11)
        let versionValue = (UInt32(version.major) << 24) | 
                          (UInt32(version.minor) << 20) | 
                          (UInt32(version.bugfix) << 16)
        data.writeUInt32BE(versionValue, at: 8)
        
        // Device class (12-15)
        data.writeUInt32BE(deviceClass.rawValue, at: 12)
        
        // Data color space (16-19)
        data.writeUInt32BE(dataColorSpace.rawValue, at: 16)
        
        // PCS (20-23)
        data.writeUInt32BE(pcs.rawValue, at: 20)
        
        // Profile signature 'acsp' (36-39)
        data.writeUInt32BE(0x61637370, at: 36)
        
        // Rendering intent (64-67)
        data.writeUInt32BE(renderingIntent.rawValue, at: 64)
        
        // Tag count (128-131) - 0 tags for minimal profile
        data.writeUInt32BE(0, at: 128)
        
        return data
    }
    
    // MARK: - Header Parsing Tests
    
    func test_parseHeader_validMinimalProfile() throws {
        let profileData = createMinimalICCProfileData()
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.header.profileSize, 132)
        XCTAssertEqual(parsed.header.version.0, 2)
        XCTAssertEqual(parsed.header.version.1, 1)
        XCTAssertEqual(parsed.header.version.2, 0)
        XCTAssertEqual(parsed.header.deviceClass, .displayDevice)
        XCTAssertEqual(parsed.header.dataColorSpace, .rgb)
        XCTAssertEqual(parsed.header.pcs, .xyz)
        XCTAssertEqual(parsed.header.renderingIntent, .perceptual)
    }
    
    func test_parseHeader_version4Profile() throws {
        let profileData = createMinimalICCProfileData(version: (4, 3, 0))
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.version.0, 4)
        XCTAssertEqual(parsed.version.1, 3)
        XCTAssertEqual(parsed.version.2, 0)
    }
    
    func test_parseHeader_inputDeviceClass() throws {
        let profileData = createMinimalICCProfileData(deviceClass: .inputDevice)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.profileClass, .inputDevice)
        XCTAssertTrue(parsed.isValid(for: .inputDevice))
        XCTAssertFalse(parsed.isValid(for: .displayDevice))
    }
    
    func test_parseHeader_outputDeviceClass() throws {
        let profileData = createMinimalICCProfileData(deviceClass: .outputDevice)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.profileClass, .outputDevice)
        XCTAssertTrue(parsed.isValid(for: .outputDevice))
    }
    
    func test_parseHeader_colorSpaceConversionClass() throws {
        let profileData = createMinimalICCProfileData(deviceClass: .colorSpaceConversion)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.profileClass, .colorSpaceConversion)
        XCTAssertTrue(parsed.isValid(for: .colorSpace))
    }
    
    func test_parseHeader_deviceLinkClass() throws {
        let profileData = createMinimalICCProfileData(deviceClass: .deviceLink)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.profileClass, .deviceLink)
        XCTAssertTrue(parsed.isValid(for: .deviceLink))
    }
    
    func test_parseHeader_grayColorSpace() throws {
        let profileData = createMinimalICCProfileData(dataColorSpace: .gray)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.header.dataColorSpace, .gray)
    }
    
    func test_parseHeader_cmykColorSpace() throws {
        let profileData = createMinimalICCProfileData(dataColorSpace: .cmyk)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.header.dataColorSpace, .cmyk)
    }
    
    func test_parseHeader_labPCS() throws {
        let profileData = createMinimalICCProfileData(pcs: .lab)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.header.pcs, .lab)
    }
    
    func test_parseHeader_relativeColorimetricIntent() throws {
        let profileData = createMinimalICCProfileData(renderingIntent: .relativeColorimetric)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.header.renderingIntent, .relativeColorimetric)
    }
    
    func test_parseHeader_saturationIntent() throws {
        let profileData = createMinimalICCProfileData(renderingIntent: .saturation)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.header.renderingIntent, .saturation)
    }
    
    func test_parseHeader_absoluteColorimetricIntent() throws {
        let profileData = createMinimalICCProfileData(renderingIntent: .absoluteColorimetric)
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.header.renderingIntent, .absoluteColorimetric)
    }
    
    // MARK: - Error Cases
    
    func test_parseError_insufficientData() {
        let tooSmallData = Data([0x00, 0x01, 0x02])
        
        XCTAssertThrowsError(try ICCProfileParser.parse(tooSmallData)) { error in
            guard case ICCProfileParser.ParseError.insufficientData = error else {
                XCTFail("Expected insufficientData error")
                return
            }
        }
    }
    
    func test_parseError_invalidSignature() {
        var profileData = createMinimalICCProfileData()
        // Overwrite signature with invalid value
        profileData.writeUInt32BE(0x12345678, at: 36)
        
        XCTAssertThrowsError(try ICCProfileParser.parse(profileData)) { error in
            guard case ICCProfileParser.ParseError.invalidSignature = error else {
                XCTFail("Expected invalidSignature error")
                return
            }
        }
    }
    
    func test_parseError_description() {
        let error1 = ICCProfileParser.ParseError.insufficientData
        XCTAssertEqual(error1.description, "ICC profile data is too small")
        
        let error2 = ICCProfileParser.ParseError.invalidSignature
        XCTAssertEqual(error2.description, "ICC profile signature mismatch (expected 'acsp')")
        
        let error3 = ICCProfileParser.ParseError.invalidTag("desc")
        XCTAssertEqual(error3.description, "ICC profile tag 'desc' is invalid")
    }
    
    // MARK: - Tag Parsing Tests
    
    func test_parseTagTable_noTags() throws {
        let profileData = createMinimalICCProfileData()
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.tags.count, 0)
        XCTAssertEqual(parsed.description, "Unknown")
    }
    
    func test_parseTagTable_withDescriptionTag() throws {
        var profileData = createMinimalICCProfileData(profileSize: 200)
        
        // Add 1 tag (description)
        profileData.writeUInt32BE(1, at: 128)
        
        // Tag entry at 132:
        // Signature: 'desc' (0x64657363)
        profileData.writeUInt32BE(0x64657363, at: 132)
        // Offset: 144
        profileData.writeUInt32BE(144, at: 136)
        // Size: 40
        profileData.writeUInt32BE(40, at: 140)
        
        // Tag data at 144:
        // Type signature: 'desc' (4 bytes)
        profileData.writeUInt32BE(0x64657363, at: 144)
        // Reserved (4 bytes)
        profileData.writeUInt32BE(0, at: 148)
        // Description text: "Test Profile"
        let text = "Test Profile"
        if let textData = text.data(using: .utf8) {
            profileData.replaceSubrange(152..<(152 + textData.count), with: textData)
        }
        
        let parsed = try ICCProfileParser.parse(profileData)
        
        XCTAssertEqual(parsed.tags.count, 1)
        XCTAssertNotNil(parsed.tags[.profileDescription])
        XCTAssertTrue(parsed.description.contains("Test"))
    }
    
    // MARK: - ParsedICCProfile Tests
    
    func test_parsedProfile_isValid() throws {
        let inputProfile = createMinimalICCProfileData(deviceClass: .inputDevice)
        let parsed1 = try ICCProfileParser.parse(inputProfile)
        XCTAssertTrue(parsed1.isValid(for: .inputDevice))
        XCTAssertFalse(parsed1.isValid(for: .displayDevice))
        
        let displayProfile = createMinimalICCProfileData(deviceClass: .displayDevice)
        let parsed2 = try ICCProfileParser.parse(displayProfile)
        XCTAssertTrue(parsed2.isValid(for: .displayDevice))
        XCTAssertFalse(parsed2.isValid(for: .inputDevice))
    }
    
    func test_parsedProfile_hashable() throws {
        let data1 = createMinimalICCProfileData()
        let data2 = createMinimalICCProfileData()
        let data3 = createMinimalICCProfileData(deviceClass: .inputDevice)
        
        let parsed1 = try ICCProfileParser.parse(data1)
        let parsed2 = try ICCProfileParser.parse(data2)
        let parsed3 = try ICCProfileParser.parse(data3)
        
        XCTAssertEqual(parsed1, parsed2)
        XCTAssertNotEqual(parsed1, parsed3)
    }
    
    // MARK: - ICCProfile Integration Tests
    
    func test_iccProfile_parse() throws {
        let profileData = createMinimalICCProfileData()
        let iccProfile = ICCProfile(profileData: profileData, colorSpace: .sRGB)
        
        let parsed = try iccProfile.parse()
        XCTAssertEqual(parsed.header.deviceClass, .displayDevice)
    }
    
    func test_iccProfile_initFromParsed_sRGB() throws {
        var profileData = createMinimalICCProfileData(profileSize: 200)
        
        // Add description tag with "sRGB"
        profileData.writeUInt32BE(1, at: 128)
        profileData.writeUInt32BE(0x64657363, at: 132)
        profileData.writeUInt32BE(144, at: 136)
        profileData.writeUInt32BE(40, at: 140)
        profileData.writeUInt32BE(0x64657363, at: 144)
        profileData.writeUInt32BE(0, at: 148)
        if let textData = "sRGB".data(using: .utf8) {
            profileData.replaceSubrange(152..<(152 + textData.count), with: textData)
        }
        
        let parsed = try ICCProfileParser.parse(profileData)
        let iccProfile = ICCProfile(parsed: parsed, profileData: profileData)
        
        XCTAssertEqual(iccProfile.colorSpace, .sRGB)
        XCTAssertTrue(iccProfile.description?.contains("sRGB") ?? false)
    }
    
    func test_iccProfile_initFromParsed_adobeRGB() throws {
        var profileData = createMinimalICCProfileData(profileSize: 200)
        
        // Add description tag with "Adobe RGB"
        profileData.writeUInt32BE(1, at: 128)
        profileData.writeUInt32BE(0x64657363, at: 132)
        profileData.writeUInt32BE(144, at: 136)
        profileData.writeUInt32BE(40, at: 140)
        profileData.writeUInt32BE(0x64657363, at: 144)
        profileData.writeUInt32BE(0, at: 148)
        if let textData = "Adobe RGB".data(using: .utf8) {
            profileData.replaceSubrange(152..<(152 + textData.count), with: textData)
        }
        
        let parsed = try ICCProfileParser.parse(profileData)
        let iccProfile = ICCProfile(parsed: parsed, profileData: profileData)
        
        XCTAssertEqual(iccProfile.colorSpace, .adobeRGB)
    }
    
    func test_iccProfile_initFromParsed_displayP3() throws {
        var profileData = createMinimalICCProfileData(profileSize: 200)
        
        // Add description tag with "Display P3"
        profileData.writeUInt32BE(1, at: 128)
        profileData.writeUInt32BE(0x64657363, at: 132)
        profileData.writeUInt32BE(144, at: 136)
        profileData.writeUInt32BE(40, at: 140)
        profileData.writeUInt32BE(0x64657363, at: 144)
        profileData.writeUInt32BE(0, at: 148)
        if let textData = "Display P3".data(using: .utf8) {
            profileData.replaceSubrange(152..<(152 + textData.count), with: textData)
        }
        
        let parsed = try ICCProfileParser.parse(profileData)
        let iccProfile = ICCProfile(parsed: parsed, profileData: profileData)
        
        XCTAssertEqual(iccProfile.colorSpace, .displayP3)
    }
    
    func test_iccProfile_initFromParsed_custom() throws {
        var profileData = createMinimalICCProfileData(profileSize: 200)
        
        // Add description tag with unknown profile name
        profileData.writeUInt32BE(1, at: 128)
        profileData.writeUInt32BE(0x64657363, at: 132)
        profileData.writeUInt32BE(144, at: 136)
        profileData.writeUInt32BE(40, at: 140)
        profileData.writeUInt32BE(0x64657363, at: 144)
        profileData.writeUInt32BE(0, at: 148)
        if let textData = "Custom Profile".data(using: .utf8) {
            profileData.replaceSubrange(152..<(152 + textData.count), with: textData)
        }
        
        let parsed = try ICCProfileParser.parse(profileData)
        let iccProfile = ICCProfile(parsed: parsed, profileData: profileData)
        
        XCTAssertEqual(iccProfile.colorSpace, .custom)
    }
}

// MARK: - Data Extension Helper

extension Data {
    fileprivate mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        let bytes = value.bigEndian
        Swift.withUnsafeBytes(of: bytes) { ptr in
            self.replaceSubrange(offset..<(offset + 4), with: ptr)
        }
    }
}
