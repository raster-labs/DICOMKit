//
// HangingProtocolTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class HangingProtocolTests: XCTestCase {
    
    // MARK: - HangingProtocol Tests
    
    func test_hangingProtocol_initialization_withRequiredParameters() {
        let hangingProtocol = HangingProtocol(name: "Test Protocol")
        
        XCTAssertEqual(hangingProtocol.name, "Test Protocol", "Name should be set correctly")
        XCTAssertNil(hangingProtocol.description, "Description should be nil by default")
        XCTAssertEqual(hangingProtocol.level, .user, "Level should default to USER")
        XCTAssertNil(hangingProtocol.creator, "Creator should be nil by default")
        XCTAssertNil(hangingProtocol.creationDateTime, "Creation date time should be nil by default")
        XCTAssertNil(hangingProtocol.numberOfPriorsReferenced, "Number of priors should be nil by default")
        XCTAssertEqual(hangingProtocol.environments.count, 0, "Environments should be empty by default")
        XCTAssertEqual(hangingProtocol.userGroups.count, 0, "User groups should be empty by default")
        XCTAssertEqual(hangingProtocol.imageSets.count, 0, "Image sets should be empty by default")
        XCTAssertEqual(hangingProtocol.numberOfScreens, 1, "Number of screens should default to 1")
        XCTAssertEqual(hangingProtocol.screenDefinitions.count, 0, "Screen definitions should be empty by default")
        XCTAssertEqual(hangingProtocol.displaySets.count, 0, "Display sets should be empty by default")
    }
    
    func test_hangingProtocol_initialization_withAllParameters() {
        let environment = HangingProtocolEnvironment(modality: "CT", laterality: "L")
        let imageSet = ImageSetDefinition(number: 1, label: "Primary")
        let screen = ScreenDefinition(verticalPixels: 1080, horizontalPixels: 1920)
        let displaySet = DisplaySet(number: 1, label: "Main View")
        let dateTime = DICOMDateTime(year: 2024, month: 1, day: 15)
        
        let hangingProtocol = HangingProtocol(
            name: "Chest CT Protocol",
            description: "Standard chest CT viewing",
            level: .site,
            creator: "Dr. Smith",
            creationDateTime: dateTime,
            numberOfPriorsReferenced: 2,
            environments: [environment],
            userGroups: ["Radiology"],
            imageSets: [imageSet],
            numberOfScreens: 2,
            screenDefinitions: [screen],
            displaySets: [displaySet]
        )
        
        XCTAssertEqual(hangingProtocol.name, "Chest CT Protocol")
        XCTAssertEqual(hangingProtocol.description, "Standard chest CT viewing")
        XCTAssertEqual(hangingProtocol.level, .site)
        XCTAssertEqual(hangingProtocol.creator, "Dr. Smith")
        XCTAssertNotNil(hangingProtocol.creationDateTime)
        XCTAssertEqual(hangingProtocol.numberOfPriorsReferenced, 2)
        XCTAssertEqual(hangingProtocol.environments.count, 1)
        XCTAssertEqual(hangingProtocol.userGroups.count, 1)
        XCTAssertEqual(hangingProtocol.imageSets.count, 1)
        XCTAssertEqual(hangingProtocol.numberOfScreens, 2)
        XCTAssertEqual(hangingProtocol.screenDefinitions.count, 1)
        XCTAssertEqual(hangingProtocol.displaySets.count, 1)
    }
    
    func test_hangingProtocol_multipleEnvironments() {
        let env1 = HangingProtocolEnvironment(modality: "CT", laterality: nil)
        let env2 = HangingProtocolEnvironment(modality: "MR", laterality: "R")
        
        let hangingProtocol = HangingProtocol(
            name: "Multi-Modal",
            environments: [env1, env2]
        )
        
        XCTAssertEqual(hangingProtocol.environments.count, 2, "Should have 2 environments")
        XCTAssertEqual(hangingProtocol.environments[0].modality, "CT")
        XCTAssertEqual(hangingProtocol.environments[1].modality, "MR")
    }
    
    // MARK: - HangingProtocolLevel Tests
    
    /// PS3.3 2026a Table C.23.1-1 Hanging Protocol Level (0072,0006) Enumerated Values:
    /// MANUFACTURER, SITE, USER_GROUP, SINGLE_USER
    func test_hangingProtocolLevel_rawValues() {
        XCTAssertEqual(HangingProtocolLevel.manufacturer.rawValue, "MANUFACTURER")
        XCTAssertEqual(HangingProtocolLevel.site.rawValue, "SITE")
        XCTAssertEqual(HangingProtocolLevel.group.rawValue, "USER_GROUP")
        XCTAssertEqual(HangingProtocolLevel.user.rawValue, "SINGLE_USER")
        XCTAssertEqual(HangingProtocolLevel.allCases.count, 4)
    }

    func test_hangingProtocolLevel_fromString() {
        XCTAssertEqual(HangingProtocolLevel(rawValue: "MANUFACTURER"), .manufacturer)
        XCTAssertEqual(HangingProtocolLevel(rawValue: "SITE"), .site)
        XCTAssertEqual(HangingProtocolLevel(rawValue: "USER_GROUP"), .group)
        XCTAssertEqual(HangingProtocolLevel(rawValue: "SINGLE_USER"), .user)
        XCTAssertNil(HangingProtocolLevel(rawValue: "INVALID"))
    }
    
    // MARK: - HangingProtocolEnvironment Tests
    
    func test_environment_initialization_withModality() {
        let environment = HangingProtocolEnvironment(modality: "CT")
        
        XCTAssertEqual(environment.modality, "CT")
        XCTAssertNil(environment.laterality)
    }
    
    func test_environment_initialization_withLaterality() {
        let environment = HangingProtocolEnvironment(laterality: "L")
        
        XCTAssertNil(environment.modality)
        XCTAssertEqual(environment.laterality, "L")
    }
    
    func test_environment_initialization_withBoth() {
        let environment = HangingProtocolEnvironment(modality: "MR", laterality: "R")
        
        XCTAssertEqual(environment.modality, "MR")
        XCTAssertEqual(environment.laterality, "R")
    }
    
    func test_environment_initialization_withNeither() {
        let environment = HangingProtocolEnvironment()
        
        XCTAssertNil(environment.modality, "Modality should be nil")
        XCTAssertNil(environment.laterality, "Laterality should be nil")
    }
    
    // MARK: - ScreenDefinition Tests
    
    func test_screenDefinition_initialization_withRequiredParameters() {
        let screen = ScreenDefinition(verticalPixels: 1080, horizontalPixels: 1920)
        
        XCTAssertEqual(screen.verticalPixels, 1080)
        XCTAssertEqual(screen.horizontalPixels, 1920)
        XCTAssertNil(screen.spatialPosition)
        XCTAssertNil(screen.minimumGrayscaleBitDepth)
        XCTAssertNil(screen.minimumColorBitDepth)
        XCTAssertNil(screen.maximumRepaintTime)
    }
    
    func test_screenDefinition_initialization_withAllParameters() {
        let screen = ScreenDefinition(
            verticalPixels: 2160,
            horizontalPixels: 3840,
            spatialPosition: [0.0, 0.0, 1.0],
            minimumGrayscaleBitDepth: 8,
            minimumColorBitDepth: 24,
            maximumRepaintTime: 100
        )
        
        XCTAssertEqual(screen.verticalPixels, 2160)
        XCTAssertEqual(screen.horizontalPixels, 3840)
        XCTAssertEqual(screen.spatialPosition, [0.0, 0.0, 1.0])
        XCTAssertEqual(screen.minimumGrayscaleBitDepth, 8)
        XCTAssertEqual(screen.minimumColorBitDepth, 24)
        XCTAssertEqual(screen.maximumRepaintTime, 100)
    }
    
    func test_screenDefinition_4KResolution() {
        let screen = ScreenDefinition(verticalPixels: 2160, horizontalPixels: 3840)
        
        XCTAssertEqual(screen.verticalPixels, 2160, "Should have 4K vertical resolution")
        XCTAssertEqual(screen.horizontalPixels, 3840, "Should have 4K horizontal resolution")
    }
    
    func test_screenDefinition_dualMonitorSetup() {
        let screen1 = ScreenDefinition(
            verticalPixels: 1080,
            horizontalPixels: 1920,
            spatialPosition: [0.0, 0.0, 0.0]
        )
        let screen2 = ScreenDefinition(
            verticalPixels: 1080,
            horizontalPixels: 1920,
            spatialPosition: [1920.0, 0.0, 0.0]
        )
        
        XCTAssertNotNil(screen1.spatialPosition)
        XCTAssertNotNil(screen2.spatialPosition)
        XCTAssertNotEqual(screen1.spatialPosition?[0], screen2.spatialPosition?[0], 
                         "Screens should have different spatial positions")
    }
    
    func test_screenDefinition_medicalGradeDisplay() {
        let screen = ScreenDefinition(
            verticalPixels: 2048,
            horizontalPixels: 2560,
            minimumGrayscaleBitDepth: 10,
            maximumRepaintTime: 50
        )
        
        XCTAssertEqual(screen.minimumGrayscaleBitDepth, 10, "Medical displays often have 10-bit grayscale")
        XCTAssertEqual(screen.maximumRepaintTime, 50, "Fast repaint for diagnostic viewing")
    }
    
    func test_hangingProtocol_multipleUserGroups() {
        let hangingProtocol = HangingProtocol(
            name: "Shared Protocol",
            userGroups: ["Radiology", "Cardiology", "Neurology"]
        )
        
        XCTAssertEqual(hangingProtocol.userGroups.count, 3, "Should support multiple user groups")
        XCTAssertTrue(hangingProtocol.userGroups.contains("Radiology"))
        XCTAssertTrue(hangingProtocol.userGroups.contains("Cardiology"))
        XCTAssertTrue(hangingProtocol.userGroups.contains("Neurology"))
    }
}
