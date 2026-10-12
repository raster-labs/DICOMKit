// NavigationServiceTests.swift
// DICOMStudioTests
//
// Tests for NavigationService and NavigationDestination

import Testing
@testable import DICOMStudio
import Foundation

@Suite("NavigationService Tests")
struct NavigationServiceTests {

    @Test("All navigation destinations have system images")
    func testAllDestinationsHaveSystemImages() {
        for destination in NavigationDestination.allCases {
            #expect(!destination.systemImage.isEmpty, "Missing system image for \(destination.rawValue)")
        }
    }

    @Test("All navigation destinations have accessibility labels")
    func testAllDestinationsHaveAccessibilityLabels() {
        for destination in NavigationDestination.allCases {
            #expect(!destination.accessibilityLabel.isEmpty, "Missing accessibility label for \(destination.rawValue)")
        }
    }

    @Test("Navigation destinations are identifiable")
    func testDestinationsIdentifiable() {
        for destination in NavigationDestination.allCases {
            #expect(destination.id == destination.rawValue)
        }
    }

    @Test("Default destination is library")
    func testDefaultDestination() {
        #expect(NavigationService.defaultDestination == .library)
    }

    @Test("Primary destinations exclude settings")
    func testPrimaryDestinationsExcludeSettings() {
        let primary = NavigationService.primaryDestinations
        #expect(!primary.contains(.settings))
    }

    @Test("Primary destinations include every grouped sidebar item")
    func testPrimaryDestinationsCount() {
        let expected = NavigationDestination.allCases.filter {
            $0 != .settings && $0 != .networkUtility
                && !NavigationService.hiddenDestinations.contains($0)
        }
        #expect(NavigationService.primaryDestinations == expected)
    }

    @Test("Hidden destinations are kept out of the sidebar")
    func testHiddenDestinationsAreNotPrimary() {
        let primary = Set(NavigationService.primaryDestinations)
        for hidden in NavigationService.hiddenDestinations {
            #expect(!primary.contains(hidden))
        }
    }

    @Test("The complete navigation destination catalog exists")
    func testAllDestinationsExist() {
        #expect(Set(NavigationDestination.allCases) == [
            .library, .viewer, .volumeViewer, .jp3dComparison, .aiAnalysis,
            .networking, .dicomWeb, .cloudIntegration, .gateway, .reporting, .printing,
            .printSCP, .tools, .validation, .archiveManagement, .security, .cliWorkshop,
            .networkUtility, .performanceTools, .macOSEnhancements,
            .polishRelease, .integrationTesting, .j2kTestBench, .settings,
        ])
    }

    @Test("NavigationService can be created")
    func testNavigationServiceInit() {
        let service = NavigationService()
        _ = service
        // Just verifying it can be created without issues
    }

    @Test("System images are valid SF Symbol names")
    func testSystemImagesAreStrings() {
        #expect(NavigationDestination.library.systemImage == "folder")
        #expect(NavigationDestination.viewer.systemImage == "photo")
        #expect(NavigationDestination.networking.systemImage == "network")
        #expect(NavigationDestination.reporting.systemImage == "doc.text")
        #expect(NavigationDestination.tools.systemImage == "wrench.and.screwdriver")
        #expect(NavigationDestination.security.systemImage == "lock.shield")
        #expect(NavigationDestination.cliWorkshop.systemImage == "terminal")
        #expect(NavigationDestination.performanceTools.systemImage == "speedometer")
        #expect(NavigationDestination.macOSEnhancements.systemImage == "macwindow")
        #expect(NavigationDestination.polishRelease.systemImage == "paintbrush.pointed")
        #expect(NavigationDestination.settings.systemImage == "gear")
    }
}
