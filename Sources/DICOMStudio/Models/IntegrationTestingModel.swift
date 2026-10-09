// IntegrationTestingModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Integration Testing, Accessibility & Polish (Milestone 23)
// NEMA-verified: 2026a, checked 2026-10-05 — the standard-derived content is the 42 IntegrationTestToolCategory.toolNames (E2E scenarios), diffed against the Sources/dicom-* targets by Scripts/diff_studio_g1_shell.py: dicom-qido, dicom-stow, dicom-ups do not exist (they are dicom-wado subcommands) and dicom-j2k, dicom-jpip, dicom-printscp, dicom-video were missing; toolCount now matches; no CLI option, tag, UID or PS3 clause is carried (test, accessibility, performance and documentation bookkeeping otherwise)

import Foundation

// MARK: - 23.1 End-to-End Integration Testing

/// Top-level tabs for the Integration Testing feature panel.
public enum IntegrationTestingTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    case e2eTesting
    case unitTests
    case accessibility
    case performance
    case uiPolish
    case documentation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .e2eTesting:     return "E2E Testing"
        case .unitTests:      return "Unit Tests"
        case .accessibility:  return "Accessibility"
        case .performance:    return "Performance"
        case .uiPolish:       return "UI Polish"
        case .documentation:  return "Documentation"
        }
    }

    public var symbolName: String {
        switch self {
        case .e2eTesting:     return "testtube.2"
        case .unitTests:      return "checkmark.circle"
        case .accessibility:  return "accessibility"
        case .performance:    return "gauge.with.dots.needle.67percent"
        case .uiPolish:       return "paintbrush"
        case .documentation:  return "book"
        }
    }
}

/// Category of CLI tools for E2E integration testing.
public enum IntegrationTestToolCategory: String, Sendable, CaseIterable, Identifiable, Hashable {
    case fileInspection
    case fileProcessing
    case fileOrganization
    case dataExchange
    case networking
    case viewer
    case clinical
    case utilities
    case cloudAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fileInspection:   return "File Inspection"
        case .fileProcessing:   return "File Processing"
        case .fileOrganization: return "File Organization"
        case .dataExchange:     return "Data Exchange"
        case .networking:       return "Networking"
        case .viewer:           return "Viewer"
        case .clinical:         return "Clinical"
        case .utilities:        return "Utilities"
        case .cloudAI:          return "Cloud & AI"
        }
    }

    /// Number of tools in this category.
    public var toolCount: Int {
        switch self {
        case .fileInspection:   return 4
        case .fileProcessing:   return 5
        case .fileOrganization: return 4
        case .dataExchange:     return 6
        case .networking:       return 13
        case .viewer:           return 3
        case .clinical:         return 3
        case .utilities:        return 2
        case .cloudAI:          return 2
        }
    }

    /// The tool names belonging to this category: every `Sources/dicom-*` target, once (QIDO-RS, STOW-RS and
    /// UPS-RS are `dicom-wado` subcommands, not tools).
    public var toolNames: [String] {
        switch self {
        case .fileInspection:   return ["dicom-info", "dicom-dump", "dicom-tags", "dicom-diff"]
        case .fileProcessing:   return ["dicom-convert", "dicom-validate", "dicom-anon", "dicom-compress", "dicom-j2k"]
        case .fileOrganization: return ["dicom-split", "dicom-merge", "dicom-dcmdir", "dicom-archive"]
        case .dataExchange:     return ["dicom-json", "dicom-xml", "dicom-pdf", "dicom-export", "dicom-pixedit", "dicom-video"]
        case .networking:       return ["dicom-echo", "dicom-query", "dicom-send", "dicom-retrieve", "dicom-qr", "dicom-wado", "dicom-mwl", "dicom-mpps", "dicom-print", "dicom-printscp", "dicom-jpip", "dicom-gateway", "dicom-server"]
        case .viewer:           return ["dicom-viewer", "dicom-image", "dicom-3d"]
        case .clinical:         return ["dicom-report", "dicom-measure", "dicom-study"]
        case .utilities:        return ["dicom-uid", "dicom-script"]
        case .cloudAI:          return ["dicom-cloud", "dicom-ai"]
        }
    }
}

/// Status of a single E2E test case.
public enum IntegrationTestStatus: String, Sendable, CaseIterable, Identifiable, Hashable {
    case pending
    case running
    case passed
    case failed
    case skipped

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pending:  return "Pending"
        case .running:  return "Running"
        case .passed:   return "Passed"
        case .failed:   return "Failed"
        case .skipped:  return "Skipped"
        }
    }

    public var symbolName: String {
        switch self {
        case .pending:  return "clock"
        case .running:  return "arrow.triangle.2.circlepath"
        case .passed:   return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        case .skipped:  return "minus.circle"
        }
    }
}

/// A single E2E integration test case.
public struct IntegrationTestCase: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var toolName: String
    public var category: IntegrationTestToolCategory
    public var testDescription: String
    public var status: IntegrationTestStatus
    public var errorMessage: String?
    public var durationSeconds: Double?

    public init(
        id: UUID = UUID(),
        toolName: String,
        category: IntegrationTestToolCategory,
        testDescription: String,
        status: IntegrationTestStatus = .pending,
        errorMessage: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.category = category
        self.testDescription = testDescription
        self.status = status
        self.errorMessage = errorMessage
        self.durationSeconds = durationSeconds
    }

    /// Human-readable duration string.
    public var durationDescription: String {
        guard let d = durationSeconds else { return "—" }
        if d < 1.0 { return String(format: "%.0f ms", d * 1000) }
        return String(format: "%.2f s", d)
    }
}

/// Type of error handling test.
public enum IntegrationTestErrorType: String, Sendable, CaseIterable, Identifiable, Hashable {
    case invalidInput
    case networkTimeout
    case toolNotInstalled
    case permissionDenied
    case diskFull

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .invalidInput:      return "Invalid File Input"
        case .networkTimeout:    return "Network Timeout"
        case .toolNotInstalled:  return "Tool Not Installed"
        case .permissionDenied:  return "Permission Denied"
        case .diskFull:          return "Disk Full"
        }
    }

    /// The expected user-facing behaviour for this error type.
    public var expectedBehaviour: String {
        switch self {
        case .invalidInput:      return "Error message displayed in terminal"
        case .networkTimeout:    return "Timeout error with retry suggestion"
        case .toolNotInstalled:  return "\"Install Now\" prompt shown"
        case .permissionDenied:  return "Helpful permission error message"
        case .diskFull:          return "Warning before write operations"
        }
    }
}

/// Type of edge case test.
public enum IntegrationTestEdgeCase: String, Sendable, CaseIterable, Identifiable, Hashable {
    case veryLargeFile
    case specialCharacters
    case simultaneousExecution
    case rapidParameterChanges
    case networkLoss

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .veryLargeFile:          return "Very Large Files (>2 GB)"
        case .specialCharacters:      return "Special Characters in Paths"
        case .simultaneousExecution:  return "Simultaneous Tool Execution"
        case .rapidParameterChanges:  return "Rapid Parameter Changes"
        case .networkLoss:            return "Network Connectivity Loss"
        }
    }
}

/// A suite of related E2E tests grouped by category.
public struct IntegrationTestSuite: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var category: IntegrationTestToolCategory
    public var testCases: [IntegrationTestCase]

    public init(
        id: UUID = UUID(),
        category: IntegrationTestToolCategory,
        testCases: [IntegrationTestCase] = []
    ) {
        self.id = id
        self.category = category
        self.testCases = testCases
    }

    /// The number of test cases that have passed.
    public var passedCount: Int { testCases.filter { $0.status == .passed }.count }

    /// The number of test cases that have failed.
    public var failedCount: Int { testCases.filter { $0.status == .failed }.count }

    /// The total number of test cases.
    public var totalCount: Int { testCases.count }

    /// Summary string showing pass/fail/total counts.
    public var summary: String {
        "\(passedCount)/\(totalCount) passed"
    }

    /// Overall status based on individual test results.
    public var overallStatus: IntegrationTestStatus {
        if testCases.isEmpty { return .pending }
        if testCases.allSatisfy({ $0.status == .passed }) { return .passed }
        if testCases.contains(where: { $0.status == .failed }) { return .failed }
        if testCases.contains(where: { $0.status == .running }) { return .running }
        return .pending
    }
}

// MARK: - 23.2 Unit & ViewModel Tests

/// Target for unit test coverage tracking.
public enum UnitTestTarget: String, Sendable, CaseIterable, Identifiable, Hashable {
    case toolRegistryService
    case versionService
    case githubReleaseService
    case serverConfigService
    case commandBuilder
    case commandExecutor
    case parameterFormViewModel
    case fileValidationService
    case commandHistoryService
    case sidebarViewModel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .toolRegistryService:    return "ToolRegistryService"
        case .versionService:         return "VersionService"
        case .githubReleaseService:   return "GitHubReleaseService"
        case .serverConfigService:    return "ServerConfigService"
        case .commandBuilder:         return "CommandBuilder"
        case .commandExecutor:        return "CommandExecutor"
        case .parameterFormViewModel: return "ParameterFormViewModel"
        case .fileValidationService:  return "FileValidationService"
        case .commandHistoryService:  return "CommandHistoryService"
        case .sidebarViewModel:       return "SidebarViewModel"
        }
    }

    /// Minimum required test count for this target.
    public var minimumTestCount: Int {
        switch self {
        case .toolRegistryService:    return 30
        case .versionService:         return 20
        case .githubReleaseService:   return 25
        case .serverConfigService:    return 40
        case .commandBuilder:         return 50
        case .commandExecutor:        return 35
        case .parameterFormViewModel: return 45
        case .fileValidationService:  return 30
        case .commandHistoryService:  return 35
        case .sidebarViewModel:       return 40
        }
    }
}

/// Unit test suite tracking entry.
public struct UnitTestSuiteEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var target: UnitTestTarget
    public var testCount: Int
    public var passedCount: Int
    public var coveragePercent: Double

    public init(
        id: UUID = UUID(),
        target: UnitTestTarget,
        testCount: Int = 0,
        passedCount: Int = 0,
        coveragePercent: Double = 0.0
    ) {
        self.id = id
        self.target = target
        self.testCount = testCount
        self.passedCount = passedCount
        self.coveragePercent = coveragePercent
    }

    /// Whether this suite meets the minimum test count requirement.
    public var meetsMinimumCount: Bool { testCount >= target.minimumTestCount }

    /// Whether coverage meets the 95% target.
    public var meetsCoverageTarget: Bool { coveragePercent >= 95.0 }

    /// Summary string.
    public var summary: String {
        "\(passedCount)/\(testCount) passed (\(String(format: "%.1f", coveragePercent))% coverage)"
    }
}

// MARK: - 23.3 Accessibility Compliance

/// Category of accessibility checks for integration testing.
public enum IntegrationAccessibilityCheckCategory: String, Sendable, CaseIterable, Identifiable, Hashable {
    case voiceOver
    case keyboardNavigation
    case dynamicType
    case highContrast
    case reduceMotion

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .voiceOver:           return "VoiceOver"
        case .keyboardNavigation:  return "Keyboard Navigation"
        case .dynamicType:         return "Dynamic Type"
        case .highContrast:        return "High Contrast"
        case .reduceMotion:        return "Reduce Motion"
        }
    }

    public var symbolName: String {
        switch self {
        case .voiceOver:           return "speaker.wave.3"
        case .keyboardNavigation:  return "keyboard"
        case .dynamicType:         return "textformat.size"
        case .highContrast:        return "circle.lefthalf.filled"
        case .reduceMotion:        return "figure.walk"
        }
    }
}

/// Status of an individual accessibility check for integration testing.
public enum IntegrationAccessibilityCheckStatus: String, Sendable, CaseIterable, Identifiable, Hashable {
    case notChecked
    case compliant
    case nonCompliant
    case partiallyCompliant

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .notChecked:          return "Not Checked"
        case .compliant:           return "Compliant"
        case .nonCompliant:        return "Non-Compliant"
        case .partiallyCompliant:  return "Partially Compliant"
        }
    }

    public var symbolName: String {
        switch self {
        case .notChecked:          return "questionmark.circle"
        case .compliant:           return "checkmark.seal.fill"
        case .nonCompliant:        return "xmark.seal.fill"
        case .partiallyCompliant:  return "exclamationmark.triangle"
        }
    }
}

/// An individual accessibility check item for integration testing.
public struct IntegrationAccessibilityCheckItem: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var category: IntegrationAccessibilityCheckCategory
    public var checkDescription: String
    public var status: IntegrationAccessibilityCheckStatus
    public var notes: String?

    public init(
        id: UUID = UUID(),
        category: IntegrationAccessibilityCheckCategory,
        checkDescription: String,
        status: IntegrationAccessibilityCheckStatus = .notChecked,
        notes: String? = nil
    ) {
        self.id = id
        self.category = category
        self.checkDescription = checkDescription
        self.status = status
        self.notes = notes
    }
}

/// A predefined keyboard shortcut entry for integration accessibility testing.
public struct IntegrationKeyboardShortcutEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var shortcut: String
    public var action: String
    public var isVerified: Bool

    public init(
        id: UUID = UUID(),
        shortcut: String,
        action: String,
        isVerified: Bool = false
    ) {
        self.id = id
        self.shortcut = shortcut
        self.action = action
        self.isVerified = isVerified
    }
}

/// Overall accessibility audit result for a category.
public struct AccessibilityAuditResult: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var category: IntegrationAccessibilityCheckCategory
    public var items: [IntegrationAccessibilityCheckItem]

    public init(
        id: UUID = UUID(),
        category: IntegrationAccessibilityCheckCategory,
        items: [IntegrationAccessibilityCheckItem] = []
    ) {
        self.id = id
        self.category = category
        self.items = items
    }

    /// Number of compliant checks in this audit.
    public var compliantCount: Int { items.filter { $0.status == .compliant }.count }

    /// Total number of checks.
    public var totalCount: Int { items.count }

    /// Compliance percentage.
    public var compliancePercent: Double {
        guard totalCount > 0 else { return 0.0 }
        return (Double(compliantCount) / Double(totalCount)) * 100.0
    }

    /// Summary string.
    public var summary: String {
        "\(compliantCount)/\(totalCount) compliant (\(String(format: "%.0f", compliancePercent))%)"
    }
}

// MARK: - 23.4 Performance Optimization

/// Type of performance metric being measured.
public enum PerformanceMetricType: String, Sendable, CaseIterable, Identifiable, Hashable {
    case launchTime
    case sidebarRendering
    case parameterFormRendering
    case terminalOutput
    case memoryUsage
    case fileDropValidation
    case commandPreviewUpdate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .launchTime:              return "Launch Time"
        case .sidebarRendering:        return "Sidebar Rendering"
        case .parameterFormRendering:  return "Parameter Form Rendering"
        case .terminalOutput:          return "Terminal Output"
        case .memoryUsage:             return "Memory Usage"
        case .fileDropValidation:      return "File Drop Validation"
        case .commandPreviewUpdate:    return "Command Preview Update"
        }
    }

    /// The target value description for this metric.
    public var targetDescription: String {
        switch self {
        case .launchTime:              return "< 2 seconds"
        case .sidebarRendering:        return "60 fps"
        case .parameterFormRendering:  return "< 50 ms"
        case .terminalOutput:          return "10,000+ lines without drops"
        case .memoryUsage:             return "< 150 MB base, < 300 MB peak"
        case .fileDropValidation:      return "< 200 ms"
        case .commandPreviewUpdate:    return "< 100 ms"
        }
    }

    /// The unit of measurement for this metric.
    public var unit: String {
        switch self {
        case .launchTime:              return "s"
        case .sidebarRendering:        return "fps"
        case .parameterFormRendering:  return "ms"
        case .terminalOutput:          return "lines"
        case .memoryUsage:             return "MB"
        case .fileDropValidation:      return "ms"
        case .commandPreviewUpdate:    return "ms"
        }
    }
}

/// Result of a single performance benchmark.
public struct PerformanceBenchmarkResult: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var metric: PerformanceMetricType
    public var measuredValue: Double
    public var targetValue: Double
    public var meetsTarget: Bool

    public init(
        id: UUID = UUID(),
        metric: PerformanceMetricType,
        measuredValue: Double,
        targetValue: Double,
        meetsTarget: Bool
    ) {
        self.id = id
        self.metric = metric
        self.measuredValue = measuredValue
        self.targetValue = targetValue
        self.meetsTarget = meetsTarget
    }

    /// Formatted measured value with unit.
    public var formattedValue: String {
        "\(String(format: "%.1f", measuredValue)) \(metric.unit)"
    }

    /// Formatted target value with unit.
    public var formattedTarget: String {
        "\(String(format: "%.1f", targetValue)) \(metric.unit)"
    }
}

/// Status of profiling for a specific instrument.
public enum ProfilingInstrument: String, Sendable, CaseIterable, Identifiable, Hashable {
    case timeProfiler
    case allocations
    case leaks
    case coreAnimation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .timeProfiler:   return "Time Profiler"
        case .allocations:    return "Allocations"
        case .leaks:          return "Leaks"
        case .coreAnimation:  return "Core Animation"
        }
    }

    public var symbolName: String {
        switch self {
        case .timeProfiler:   return "clock.arrow.circlepath"
        case .allocations:    return "memorychip"
        case .leaks:          return "drop.triangle"
        case .coreAnimation:  return "film"
        }
    }
}

/// A profiling session entry.
public struct ProfilingSession: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var instrument: ProfilingInstrument
    public var isCompleted: Bool
    public var findings: String?

    public init(
        id: UUID = UUID(),
        instrument: ProfilingInstrument,
        isCompleted: Bool = false,
        findings: String? = nil
    ) {
        self.id = id
        self.instrument = instrument
        self.isCompleted = isCompleted
        self.findings = findings
    }
}

// MARK: - 23.5 UI Polish & Refinement

/// Category of UI polish checks.
public enum UIPolishCategory: String, Sendable, CaseIterable, Identifiable, Hashable {
    case spacing
    case animations
    case loadingStates
    case errorStates
    case emptyStates
    case windowTitle
    case touchBar
    case menuBar
    case darkMode
    case lightMode
    case toolbar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spacing:       return "Spacing & Alignment"
        case .animations:    return "Animations"
        case .loadingStates: return "Loading States"
        case .errorStates:   return "Error States"
        case .emptyStates:   return "Empty States"
        case .windowTitle:   return "Window Title"
        case .touchBar:      return "Touch Bar"
        case .menuBar:       return "Menu Bar"
        case .darkMode:      return "Dark Mode"
        case .lightMode:     return "Light Mode"
        case .toolbar:       return "Toolbar"
        }
    }

    public var symbolName: String {
        switch self {
        case .spacing:       return "ruler"
        case .animations:    return "wand.and.stars"
        case .loadingStates: return "progress.indicator"
        case .errorStates:   return "exclamationmark.bubble"
        case .emptyStates:   return "tray"
        case .windowTitle:   return "macwindow"
        case .touchBar:      return "rectangle.3.group"
        case .menuBar:       return "menubar.rectangle"
        case .darkMode:      return "moon.fill"
        case .lightMode:     return "sun.max.fill"
        case .toolbar:       return "hammer"
        }
    }
}

/// A single UI polish check item.
public struct UIPolishCheckItem: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var category: UIPolishCategory
    public var checkDescription: String
    public var isVerified: Bool
    public var notes: String?

    public init(
        id: UUID = UUID(),
        category: UIPolishCategory,
        checkDescription: String,
        isVerified: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.category = category
        self.checkDescription = checkDescription
        self.isVerified = isVerified
        self.notes = notes
    }
}

// MARK: - 23.6 Documentation & Help

/// Section of in-app or release documentation.
public enum DocumentationSection: String, Sendable, CaseIterable, Identifiable, Hashable {
    case inAppHelp
    case userGuide
    case releaseNotes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inAppHelp:    return "In-App Help"
        case .userGuide:    return "User Guide"
        case .releaseNotes: return "Release Notes"
        }
    }

    public var symbolName: String {
        switch self {
        case .inAppHelp:    return "questionmark.circle"
        case .userGuide:    return "book.pages"
        case .releaseNotes: return "doc.text.magnifyingglass"
        }
    }
}

/// Status of a documentation entry.
public enum DocumentationEntryStatus: String, Sendable, CaseIterable, Identifiable, Hashable {
    case notStarted
    case draft
    case review
    case published

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .draft:      return "Draft"
        case .review:     return "In Review"
        case .published:  return "Published"
        }
    }
}

/// A single documentation entry for integration testing.
public struct IntegrationDocumentationEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var section: DocumentationSection
    public var title: String
    public var status: DocumentationEntryStatus
    public var lastUpdated: Date?

    public init(
        id: UUID = UUID(),
        section: DocumentationSection,
        title: String,
        status: DocumentationEntryStatus = .notStarted,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.section = section
        self.title = title
        self.status = status
        self.lastUpdated = lastUpdated
    }

    /// Whether this entry is complete (published).
    public var isComplete: Bool { status == .published }
}

// MARK: - Top-level Integration Testing State

/// Aggregated state for the full Integration Testing feature.
public struct IntegrationTestingState: Sendable, Equatable {
    public var selectedTab: IntegrationTestingTab
    public var testSuites: [IntegrationTestSuite]
    public var unitTestEntries: [UnitTestSuiteEntry]
    public var accessibilityAudits: [AccessibilityAuditResult]
    public var keyboardShortcuts: [IntegrationKeyboardShortcutEntry]
    public var benchmarkResults: [PerformanceBenchmarkResult]
    public var profilingSessions: [ProfilingSession]
    public var polishChecks: [UIPolishCheckItem]
    public var documentationEntries: [IntegrationDocumentationEntry]

    public init(
        selectedTab: IntegrationTestingTab = .e2eTesting,
        testSuites: [IntegrationTestSuite] = [],
        unitTestEntries: [UnitTestSuiteEntry] = [],
        accessibilityAudits: [AccessibilityAuditResult] = [],
        keyboardShortcuts: [IntegrationKeyboardShortcutEntry] = [],
        benchmarkResults: [PerformanceBenchmarkResult] = [],
        profilingSessions: [ProfilingSession] = [],
        polishChecks: [UIPolishCheckItem] = [],
        documentationEntries: [IntegrationDocumentationEntry] = []
    ) {
        self.selectedTab = selectedTab
        self.testSuites = testSuites
        self.unitTestEntries = unitTestEntries
        self.accessibilityAudits = accessibilityAudits
        self.keyboardShortcuts = keyboardShortcuts
        self.benchmarkResults = benchmarkResults
        self.profilingSessions = profilingSessions
        self.polishChecks = polishChecks
        self.documentationEntries = documentationEntries
    }

    /// Total number of E2E tests across all suites.
    public var totalE2ETests: Int { testSuites.reduce(0) { $0 + $1.totalCount } }

    /// Total number of E2E tests that passed.
    public var passedE2ETests: Int { testSuites.reduce(0) { $0 + $1.passedCount } }

    /// Total number of unit tests across all entries.
    public var totalUnitTests: Int { unitTestEntries.reduce(0) { $0 + $1.testCount } }

    /// Overall accessibility compliance percentage.
    public var overallCompliancePercent: Double {
        let totalItems = accessibilityAudits.reduce(0) { $0 + $1.totalCount }
        let compliant = accessibilityAudits.reduce(0) { $0 + $1.compliantCount }
        guard totalItems > 0 else { return 0.0 }
        return (Double(compliant) / Double(totalItems)) * 100.0
    }

    /// Number of performance benchmarks that meet targets.
    public var benchmarksMeetingTargets: Int { benchmarkResults.filter(\.meetsTarget).count }

    /// Number of UI polish checks that are verified.
    public var verifiedPolishChecks: Int { polishChecks.filter(\.isVerified).count }

    /// Number of documentation entries that are published.
    public var publishedDocEntries: Int { documentationEntries.filter(\.isComplete).count }
}
