//
// DisplayFeaturesTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit

@available(iOS 16.0, macOS 13.0, *)
final class DisplayFeaturesTests: XCTestCase {
    
    // MARK: - EDR Display Capabilities Tests
    
    func test_edrCapabilities_initialization() {
        let capabilities = EDRDisplayCapabilities(
            maxEDRHeadroom: 2.0,
            currentEDRHeadroom: 1.5,
            supportsHDR: true
        )
        
        XCTAssertEqual(capabilities.maxEDRHeadroom, 2.0)
        XCTAssertEqual(capabilities.currentEDRHeadroom, 1.5)
        XCTAssertTrue(capabilities.supportsHDR)
    }
    
    func test_edrCapabilities_sdrOnly() {
        let capabilities = EDRDisplayCapabilities(
            maxEDRHeadroom: 1.0,
            currentEDRHeadroom: 1.0,
            supportsHDR: false
        )
        
        XCTAssertEqual(capabilities.maxEDRHeadroom, 1.0)
        XCTAssertFalse(capabilities.supportsHDR)
    }
    
    func test_edrCapabilities_hashable() {
        let cap1 = EDRDisplayCapabilities(maxEDRHeadroom: 2.0, currentEDRHeadroom: 1.5, supportsHDR: true)
        let cap2 = EDRDisplayCapabilities(maxEDRHeadroom: 2.0, currentEDRHeadroom: 1.5, supportsHDR: true)
        let cap3 = EDRDisplayCapabilities(maxEDRHeadroom: 1.0, currentEDRHeadroom: 1.0, supportsHDR: false)
        
        XCTAssertEqual(cap1, cap2)
        XCTAssertNotEqual(cap1, cap3)
    }
    
    // MARK: - HDR Tone Mapping Tests
    
    func test_toneMappingLinear_sdr() {
        let toneMapping = HDRToneMapping(method: .linear)
        
        XCTAssertEqual(toneMapping.apply(to: 0.0), 0.0)
        XCTAssertEqual(toneMapping.apply(to: 0.5), 0.5)
        XCTAssertEqual(toneMapping.apply(to: 1.0), 1.0)
    }
    
    func test_toneMappingLinear_hdr() {
        let toneMapping = HDRToneMapping(method: .linear)
        
        // Linear clips values above 1.0
        XCTAssertEqual(toneMapping.apply(to: 1.5), 1.0)
        XCTAssertEqual(toneMapping.apply(to: 2.0), 1.0)
    }
    
    func test_toneMappingPerceptual_sdr() {
        let toneMapping = HDRToneMapping(method: .perceptual)
        
        // SDR values pass through unchanged
        XCTAssertEqual(toneMapping.apply(to: 0.0), 0.0)
        XCTAssertEqual(toneMapping.apply(to: 0.5), 0.5)
        XCTAssertEqual(toneMapping.apply(to: 1.0), 1.0)
    }
    
    func test_toneMappingPerceptual_hdr() {
        let toneMapping = HDRToneMapping(method: .perceptual)
        
        // HDR values are compressed
        let result1 = toneMapping.apply(to: 1.5)
        let result2 = toneMapping.apply(to: 2.0)
        
        XCTAssertGreaterThan(result1, 0.8)
        XCTAssertLessThan(result1, 1.0)
        XCTAssertGreaterThan(result2, result1)
        XCTAssertLessThan(result2, 1.0)
    }
    
    func test_toneMappingReinhard() {
        let toneMapping = HDRToneMapping(method: .reinhard)
        
        XCTAssertEqual(toneMapping.apply(to: 0.0), 0.0)
        XCTAssertEqual(toneMapping.apply(to: 1.0), 0.5, accuracy: 0.01)
        
        // Reinhard asymptotically approaches 1.0
        let result = toneMapping.apply(to: 10.0)
        XCTAssertGreaterThan(result, 0.9)
        XCTAssertLessThan(result, 1.0)
    }
    
    func test_toneMappingAces() {
        let toneMapping = HDRToneMapping(method: .aces)
        
        let result0 = toneMapping.apply(to: 0.0)
        let result1 = toneMapping.apply(to: 1.0)
        
        XCTAssertGreaterThanOrEqual(result0, 0.0)
        XCTAssertLessThanOrEqual(result0, 1.0)
        XCTAssertGreaterThanOrEqual(result1, 0.0)
        XCTAssertLessThanOrEqual(result1, 1.0)
    }
    
    func test_toneMappingConfiguration() {
        let toneMapping = HDRToneMapping(
            method: .perceptual,
            targetPeakLuminance: 1000.0,
            preserveHighlights: true
        )
        
        XCTAssertEqual(toneMapping.method, .perceptual)
        XCTAssertEqual(toneMapping.targetPeakLuminance, 1000.0)
        XCTAssertTrue(toneMapping.preserveHighlights)
    }
    
    func test_toneMappingMethodCases() {
        let methods = ToneMappingMethod.allCases
        XCTAssertEqual(methods.count, 4)
        XCTAssertTrue(methods.contains(.linear))
        XCTAssertTrue(methods.contains(.perceptual))
        XCTAssertTrue(methods.contains(.reinhard))
        XCTAssertTrue(methods.contains(.aces))
    }
    
    // MARK: - Optical Path Color Tests
    
    func test_opticalPathColor_brightfield() {
        let opticalPath = OpticalPathColor(
            opticalPathIdentifier: "1",
            illuminationType: .brightfield,
            colorSpace: .sRGB
        )
        
        XCTAssertEqual(opticalPath.opticalPathIdentifier, "1")
        XCTAssertEqual(opticalPath.illuminationType, .brightfield)
        XCTAssertEqual(opticalPath.colorSpace, .sRGB)
        XCTAssertNil(opticalPath.illuminationColor)
        XCTAssertNil(opticalPath.illuminationWavelength)
        XCTAssertNil(opticalPath.iccProfile)
    }
    
    func test_opticalPathColor_fluorescence() {
        let illuminationColor = DICOMKit.RGBColor(red: 0, green: 255, blue: 0)
        
        let opticalPath = OpticalPathColor(
            opticalPathIdentifier: "2",
            illuminationType: .fluorescence,
            illuminationColor: illuminationColor,
            illuminationWavelength: 488,
            colorSpace: .sRGB
        )
        
        XCTAssertEqual(opticalPath.illuminationType, .fluorescence)
        XCTAssertEqual(opticalPath.illuminationColor?.red, 0)
        XCTAssertEqual(opticalPath.illuminationColor?.green, 255)
        XCTAssertEqual(opticalPath.illuminationColor?.blue, 0)
        XCTAssertEqual(opticalPath.illuminationWavelength, 488)
    }
    
    func test_opticalPathColor_withICCProfile() {
        let profileData = Data([0x00, 0x01, 0x02, 0x03])
        
        let opticalPath = OpticalPathColor(
            opticalPathIdentifier: "3",
            illuminationType: .transmittedLight,
            iccProfile: profileData,
            colorSpace: .custom
        )
        
        XCTAssertEqual(opticalPath.iccProfile, profileData)
        XCTAssertEqual(opticalPath.colorSpace, .custom)
    }
    
    func test_illuminationType_allCases() {
        let types = IlluminationType.allCases
        XCTAssertEqual(types.count, 7)
        XCTAssertTrue(types.contains(.brightfield))
        XCTAssertTrue(types.contains(.darkfield))
        XCTAssertTrue(types.contains(.phaseContrast))
        XCTAssertTrue(types.contains(.differentialInterferenceContrast))
        XCTAssertTrue(types.contains(.fluorescence))
        XCTAssertTrue(types.contains(.transmittedLight))
        XCTAssertTrue(types.contains(.reflectedLight))
    }
    
    func test_illuminationType_rawValues() {
        XCTAssertEqual(IlluminationType.brightfield.rawValue, "BRIGHTFIELD")
        XCTAssertEqual(IlluminationType.fluorescence.rawValue, "FLUORESCENCE")
        XCTAssertEqual(IlluminationType.differentialInterferenceContrast.rawValue, "DIC")
    }
    
    // MARK: - RGB Color Tests
    
    func test_rgbColor_initialization() {
        let color = DICOMKit.RGBColor(red: 255, green: 128, blue: 0)
        
        XCTAssertEqual(color.red, 255)
        XCTAssertEqual(color.green, 128)
        XCTAssertEqual(color.blue, 0)
    }
    
    func test_rgbColor_normalizedInit() {
        let color = DICOMKit.RGBColor(normalizedRed: 1.0, normalizedGreen: 0.5, normalizedBlue: 0.0)
        
        XCTAssertEqual(color.red, 255)
        XCTAssertEqual(color.green, 127) // 0.5 * 255 = 127.5 -> 127
        XCTAssertEqual(color.blue, 0)
    }
    
    func test_rgbColor_normalizedInit_clamping() {
        let color = DICOMKit.RGBColor(normalizedRed: 1.5, normalizedGreen: -0.5, normalizedBlue: 0.5)
        
        XCTAssertEqual(color.red, 255) // Clamped from 382.5 to 255
        XCTAssertEqual(color.green, 0) // Clamped from -127.5 to 0
        XCTAssertEqual(color.blue, 127)
    }
    
    func test_rgbColor_normalized() {
        let color = DICOMKit.RGBColor(red: 255, green: 128, blue: 0)
        let normalized = color.normalized
        
        XCTAssertEqual(normalized.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(normalized.green, 0.502, accuracy: 0.01)
        XCTAssertEqual(normalized.blue, 0.0, accuracy: 0.01)
    }
    
    func test_rgbColor_hashable() {
        let color1 = DICOMKit.RGBColor(red: 255, green: 128, blue: 0)
        let color2 = DICOMKit.RGBColor(red: 255, green: 128, blue: 0)
        let color3 = DICOMKit.RGBColor(red: 0, green: 128, blue: 255)
        
        XCTAssertEqual(color1, color2)
        XCTAssertNotEqual(color1, color3)
    }
    
    func test_rgbColor_roundTrip() {
        let original = DICOMKit.RGBColor(red: 200, green: 100, blue: 50)
        let normalized = original.normalized
        let roundTrip = DICOMKit.RGBColor(
            normalizedRed: normalized.red,
            normalizedGreen: normalized.green,
            normalizedBlue: normalized.blue
        )
        
        XCTAssertEqual(roundTrip.red, original.red)
        XCTAssertEqual(roundTrip.green, original.green, accuracy: 1)
        XCTAssertEqual(roundTrip.blue, original.blue, accuracy: 1)
    }
}
