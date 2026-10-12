// NavigationService.swift
// DICOMStudio
//
// DICOM Studio — App-wide routing and deep linking

import Foundation

/// Top-level grouping for sidebar navigation destinations.
///
/// DICOM Studio is imaging-first: the `imaging` group stays expanded by
/// default while the others collapse, so the sidebar reads as a viewer with
/// supporting tools rather than a flat list of sixteen equal features.
public enum NavigationCategory: String, CaseIterable, Identifiable, Sendable {
    case imaging   = "Imaging"
    case network   = "DICOM Network"
    case dataTools = "Data & Tools"
    case system    = "System"

    public var id: String { rawValue }

    /// SF Symbol shown on the category's sidebar header row.
    public var systemImage: String {
        switch self {
        case .imaging:   return "photo.on.rectangle.angled"
        case .network:   return "network"
        case .dataTools: return "shippingbox"
        case .system:    return "gearshape.2"
        }
    }
}

/// Sidebar navigation destinations in DICOM Studio.
public enum NavigationDestination: String, CaseIterable, Identifiable, Sendable {
    case library          = "Library"
    case viewer           = "Viewer"
    case volumeViewer     = "3D Viewer"
    case jp3dComparison   = "JP3D Comparison"
    case aiAnalysis       = "AI Analysis"
    case networking       = "Networking"
    case dicomWeb         = "DICOMweb"
    case cloudIntegration = "Cloud"
    case gateway          = "DICOM Gateway"
    case reporting        = "Reporting"
    case printing         = "Print"
    case printSCP         = "Printer Emulator"
    case tools            = "Tools"
    case validation        = "Validation"
    case archiveManagement = "Archive"
    case security         = "Security"
    case cliWorkshop      = "CLI Workshop"
    case networkUtility   = "Network Utility"
    case performanceTools   = "Performance Tools"
    case macOSEnhancements  = "macOS Enhancements"
    case polishRelease      = "Polish & Release"
    case integrationTesting   = "Integration Testing"
    case j2kTestBench         = "J2K Test Bench"
    case settings             = "Settings"

    public var id: String { rawValue }

    /// What the sidebar row reads.
    ///
    /// Separate from `rawValue`, which is the stable identity behind selection,
    /// deep links and the feature search — a row's wording can say more about
    /// what the screen currently holds without that string moving underneath it.
    public var displayName: String { rawValue }

    /// SF Symbol name for this destination.
    public var systemImage: String {
        switch self {
        case .library:            return "folder"
        case .viewer:             return "photo"
        case .volumeViewer:       return "cube.transparent"
        case .jp3dComparison:     return "waveform.path.ecg.rectangle"
        case .aiAnalysis:         return "brain.head.profile"
        case .networking:         return "network"
        case .dicomWeb:           return "globe"
        case .cloudIntegration:   return "icloud"
        case .gateway:            return "arrow.left.arrow.right.circle"
        case .reporting:          return "doc.text"
        case .printing:           return "printer"
        case .printSCP:           return "printer.dotmatrix"
        case .tools:              return "wrench.and.screwdriver"
        case .validation:         return "checkmark.shield"
        case .archiveManagement:  return "archivebox"
        case .security:           return "lock.shield"
        case .cliWorkshop:        return "terminal"
        case .networkUtility:     return "network.badge.shield.half.filled"
        case .performanceTools:   return "speedometer"
        case .macOSEnhancements:  return "macwindow"
        case .polishRelease:      return "paintbrush.pointed"
        case .integrationTesting: return "checklist"
        case .j2kTestBench:       return "testtube.2"
        case .settings:           return "gear"
        }
    }

    /// Short description for accessibility labels.
    public var accessibilityLabel: String {
        switch self {
        case .library:            return "DICOM File Library"
        case .viewer:             return "Image Viewer"
        case .volumeViewer:       return "3D Volume Viewer"
        case .jp3dComparison:     return "JP3D Volumetric Comparison"
        case .aiAnalysis:         return "AI/ML Analysis"
        case .networking:         return "DICOM Networking Hub"
        case .dicomWeb:           return "DICOMweb Integration Hub"
        case .cloudIntegration:   return "Cloud Storage Integration"
        case .gateway:            return "DICOM Gateway – HL7 / FHIR"
        case .reporting:          return "Structured Reporting"
        case .printing:           return "DICOM Print – Printers and Job History"
        case .printSCP:           return "Printer Emulator – Receives Print Jobs from any Print SCU"
        case .tools:              return "Data Exchange and Developer Tools"
        case .validation:         return "DICOM Conformance Validation"
        case .archiveManagement:  return "DICOM Archive Management"
        case .security:           return "Security & Privacy Center"
        case .cliWorkshop:        return "CLI Tools Workshop"
        case .networkUtility:     return "Network Utility – General Network Diagnostics"
        case .performanceTools:   return "Performance & Developer Tools"
        case .macOSEnhancements:  return "macOS-Specific Enhancements"
        case .polishRelease:      return "Polish, Accessibility & Release"
        case .integrationTesting: return "Integration Testing & Polish"
        case .j2kTestBench:       return "J2K Codec Test Bench"
        case .settings:           return "Application Settings"
        }
    }

    /// The sidebar category this destination is grouped under.
    public var category: NavigationCategory {
        switch self {
        case .library, .viewer, .volumeViewer, .jp3dComparison, .aiAnalysis:
            return .imaging
        case .networking, .dicomWeb, .cloudIntegration, .gateway:
            return .network
        case .reporting, .printing, .printSCP, .tools, .validation, .archiveManagement,
             .cliWorkshop, .networkUtility:
            return .dataTools
        case .security, .performanceTools, .macOSEnhancements,
             .polishRelease, .integrationTesting, .j2kTestBench, .settings:
            return .system
        }
    }
}

/// Manages app-wide navigation state and deep linking.
public final class NavigationService: Sendable {
    /// The default destination when the app launches.
    public static let defaultDestination: NavigationDestination = .library

    /// Destinations temporarily hidden from the sidebar UI. The feature code
    /// behind each of these stays intact — this only removes the navigation
    /// entry point, e.g. for a trimmed-down build.
    public static let hiddenDestinations: Set<NavigationDestination> = [
        .volumeViewer, .jp3dComparison, .aiAnalysis,
        .cloudIntegration,
        .reporting, .tools, .validation, .archiveManagement,
    ]

    /// Returns all primary navigation destinations (excluding the standalone
    /// Settings and Network Utility entries, which render outside the category
    /// groups in the sidebar, and any destinations temporarily hidden from
    /// the UI).
    public static var primaryDestinations: [NavigationDestination] {
        NavigationDestination.allCases.filter {
            $0 != .settings && $0 != .networkUtility && !hiddenDestinations.contains($0)
        }
    }

    public init() {}
}
