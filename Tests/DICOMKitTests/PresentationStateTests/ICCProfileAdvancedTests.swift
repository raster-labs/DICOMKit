//
// ICCProfileAdvancedTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class ICCProfileAdvancedTests: XCTestCase {
    
    // MARK: - Color Space Tests
    
    func test_colorSpace_rec2020() {
        let colorSpace = ColorSpace.rec2020
        XCTAssertEqual(colorSpace.rawValue, "Rec. 2020")
        
        #if canImport(CoreGraphics)
        if #available(iOS 9.3, macOS 10.11.2, *) {
            let cgColorSpace = colorSpace.createCGColorSpace()
            XCTAssertNotNil(cgColorSpace)
        }
        #endif
    }
    
    func test_colorSpace_ybrFull() {
        let colorSpace = ColorSpace.ybrFull
        XCTAssertEqual(colorSpace.rawValue, "YBR_FULL")
        
        #if canImport(CoreGraphics)
        let cgColorSpace = colorSpace.createCGColorSpace()
        XCTAssertNotNil(cgColorSpace) // Should fallback to sRGB
        #endif
    }
    
    func test_colorSpace_ybrFull422() {
        let colorSpace = ColorSpace.ybrFull422
        XCTAssertEqual(colorSpace.rawValue, "YBR_FULL_422")
    }
    
    func test_colorSpace_ybrPartial420() {
        let colorSpace = ColorSpace.ybrPartial420
        XCTAssertEqual(colorSpace.rawValue, "YBR_PARTIAL_420")
    }
    
    func test_colorSpace_allCases() {
        let allCases = ColorSpace.allCases
        XCTAssertTrue(allCases.contains(.sRGB))
        XCTAssertTrue(allCases.contains(.adobeRGB))
        XCTAssertTrue(allCases.contains(.displayP3))
        XCTAssertTrue(allCases.contains(.proPhotoRGB))
        XCTAssertTrue(allCases.contains(.rec2020))
        XCTAssertTrue(allCases.contains(.genericRGB))
        XCTAssertTrue(allCases.contains(.ybrFull))
        XCTAssertTrue(allCases.contains(.ybrFull422))
        XCTAssertTrue(allCases.contains(.ybrPartial420))
        XCTAssertTrue(allCases.contains(.custom))
    }
    
    // MARK: - DICOM Color Space Extraction Tests
    
    func test_extractColorSpace_sRGB() {
        var dataSet: [Tag: DataElement] = [:]
        let tag = Tag(group: 0x0028, element: 0x2002)
        let data = "SRGB".data(using: .utf8)!
        let element = DataElement(tag: tag, vr: .CS, length: UInt32(data.count), valueData: data)
        dataSet[tag] = element
        
        let colorSpace = ICCProfile.extractColorSpace(from: dataSet)
        XCTAssertEqual(colorSpace, .sRGB)
    }
    
    func test_extractColorSpace_adobeRGB() {
        var dataSet: [Tag: DataElement] = [:]
        let tag = Tag(group: 0x0028, element: 0x2002)
        let data = "ADOBERGB".data(using: .utf8)!
        let element = DataElement(tag: tag, vr: .CS, length: UInt32(data.count), valueData: data)
        dataSet[tag] = element
        
        let colorSpace = ICCProfile.extractColorSpace(from: dataSet)
        XCTAssertEqual(colorSpace, .adobeRGB)
    }
    
    func test_extractColorSpace_rec2020() {
        var dataSet: [Tag: DataElement] = [:]
        let tag = Tag(group: 0x0028, element: 0x2002)
        let data = "REC2020".data(using: .utf8)!
        let element = DataElement(tag: tag, vr: .CS, length: UInt32(data.count), valueData: data)
        dataSet[tag] = element
        
        let colorSpace = ICCProfile.extractColorSpace(from: dataSet)
        XCTAssertEqual(colorSpace, .rec2020)
    }
    
    func test_extractColorSpace_ybrFull() {
        var dataSet: [Tag: DataElement] = [:]
        let tag = Tag(group: 0x0028, element: 0x2002)
        let data = "YBR_FULL".data(using: .utf8)!
        let element = DataElement(tag: tag, vr: .CS, length: UInt32(data.count), valueData: data)
        dataSet[tag] = element
        
        let colorSpace = ICCProfile.extractColorSpace(from: dataSet)
        XCTAssertEqual(colorSpace, .ybrFull)
    }
    
    func test_extractColorSpace_missing() {
        let dataSet: [Tag: DataElement] = [:]
        let colorSpace = ICCProfile.extractColorSpace(from: dataSet)
        XCTAssertNil(colorSpace)
    }
    
    func test_extractColorSpace_custom() {
        var dataSet: [Tag: DataElement] = [:]
        let tag = Tag(group: 0x0028, element: 0x2002)
        let data = "CUSTOM".data(using: .utf8)!
        let element = DataElement(tag: tag, vr: .CS, length: UInt32(data.count), valueData: data)
        dataSet[tag] = element
        
        let colorSpace = ICCProfile.extractColorSpace(from: dataSet)
        XCTAssertEqual(colorSpace, .custom)
    }
    
    // MARK: - TRC Curve Extraction Tests
    
    func test_trcCurve_extraction() {
        // A 'curv' tag with four 16-bit entries: 12-byte header + 4 × 2 bytes.
        // (The original Data(count: 16) was too short for the entries written
        // at offsets 16 and 18, which trapped in replaceSubrange.)
        var trcData = Data(count: 20)
        
        // Type signature 'curv' (0x63757276)
        trcData.writeUInt32BE(0x63757276, at: 0)
        
        // Reserved (4 bytes)
        trcData.writeUInt32BE(0, at: 4)
        
        // Count: 4 entries
        trcData.writeUInt32BE(4, at: 8)
        
        // Curve values (16-bit each)
        trcData.writeUInt16BE(0, at: 12)
        trcData.writeUInt16BE(21845, at: 14) // ~1/3 of 65535
        trcData.writeUInt16BE(43690, at: 16) // ~2/3 of 65535
        trcData.writeUInt16BE(65535, at: 18)
        
        let tagData = ICCTagData(
            signature: .redTRC,
            data: trcData,
            offset: 0,
            size: trcData.count
        )
        
        let curve = tagData.extractTRCCurve()
        XCTAssertNotNil(curve)
        XCTAssertEqual(curve?.count, 4)
        XCTAssertEqual(curve?[0], 0)
        XCTAssertEqual(curve?[3], 65535)
    }
    
    func test_trcCurve_invalidData() {
        let trcData = Data([0x00, 0x01, 0x02])
        let tagData = ICCTagData(
            signature: .redTRC,
            data: trcData,
            offset: 0,
            size: trcData.count
        )
        
        let curve = tagData.extractTRCCurve()
        XCTAssertNil(curve)
    }
    
    // MARK: - XYZ Extraction Tests
    
    func test_xyz_extraction() {
        var xyzData = Data(count: 20)
        
        // Type signature 'XYZ ' (0x58595A20)
        xyzData.writeUInt32BE(0x58595A20, at: 0)
        
        // Reserved
        xyzData.writeUInt32BE(0, at: 4)
        
        // X, Y, Z values as s15Fixed16Number
        // For D65 white point: X=0.9505, Y=1.0000, Z=1.0890
        let xFixed = UInt32(bitPattern: Int32(0.9505 * 65536.0))
        let yFixed = UInt32(bitPattern: Int32(1.0000 * 65536.0))
        let zFixed = UInt32(bitPattern: Int32(1.0890 * 65536.0))
        
        xyzData.writeUInt32BE(xFixed, at: 8)
        xyzData.writeUInt32BE(yFixed, at: 12)
        xyzData.writeUInt32BE(zFixed, at: 16)
        
        let tagData = ICCTagData(
            signature: .whitePoint,
            data: xyzData,
            offset: 0,
            size: xyzData.count
        )
        
        let xyz = tagData.extractXYZ()
        XCTAssertNotNil(xyz)
        XCTAssertEqual(xyz!.x, 0.9505, accuracy: 0.01)
        XCTAssertEqual(xyz!.y, 1.0000, accuracy: 0.01)
        XCTAssertEqual(xyz!.z, 1.0890, accuracy: 0.01)
    }
    
    func test_xyz_invalidSignature() {
        var xyzData = Data(count: 20)
        xyzData.writeUInt32BE(0x12345678, at: 0) // Invalid signature
        
        let tagData = ICCTagData(
            signature: .whitePoint,
            data: xyzData,
            offset: 0,
            size: xyzData.count
        )
        
        let xyz = tagData.extractXYZ()
        XCTAssertNil(xyz)
    }
    
    // MARK: - ICC Profile Rec2020 Tests
    
    func test_iccProfile_rec2020_detection() {
        var profileData = createMinimalICCProfileData(profileSize: 200)
        
        // Add description tag with "Rec. 2020"
        profileData.writeUInt32BE(1, at: 128)
        profileData.writeUInt32BE(0x64657363, at: 132)
        profileData.writeUInt32BE(144, at: 136)
        profileData.writeUInt32BE(40, at: 140)
        profileData.writeUInt32BE(0x64657363, at: 144)
        profileData.writeUInt32BE(0, at: 148)
        if let textData = "Rec. 2020".data(using: .utf8) {
            profileData.replaceSubrange(152..<(152 + textData.count), with: textData)
        }
        
        let parsed = try? ICCProfileParser.parse(profileData)
        XCTAssertNotNil(parsed)
        
        let iccProfile = ICCProfile(parsed: parsed!, profileData: profileData)
        XCTAssertEqual(iccProfile.colorSpace, .rec2020)
    }
    
    // MARK: - Helper Methods
    
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
        
        // Profile size
        data.writeUInt32BE(profileSize, at: 0)
        
        // Version
        let versionValue = (UInt32(version.major) << 24) | 
                          (UInt32(version.minor) << 20) | 
                          (UInt32(version.bugfix) << 16)
        data.writeUInt32BE(versionValue, at: 8)
        
        // Device class
        data.writeUInt32BE(deviceClass.rawValue, at: 12)
        
        // Data color space
        data.writeUInt32BE(dataColorSpace.rawValue, at: 16)
        
        // PCS
        data.writeUInt32BE(pcs.rawValue, at: 20)
        
        // Profile signature 'acsp'
        data.writeUInt32BE(0x61637370, at: 36)
        
        // Rendering intent
        data.writeUInt32BE(renderingIntent.rawValue, at: 64)
        
        // Tag count
        data.writeUInt32BE(0, at: 128)
        
        return data
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
    
    fileprivate mutating func writeUInt16BE(_ value: UInt16, at offset: Int) {
        let bytes = value.bigEndian
        Swift.withUnsafeBytes(of: bytes) { ptr in
            self.replaceSubrange(offset..<(offset + 2), with: ptr)
        }
    }
    
    fileprivate func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        let subdata = self[offset..<(offset + 4)]
        return subdata.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
    
    fileprivate func readUInt16BE(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        let subdata = self[offset..<(offset + 2)]
        return subdata.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }
}
