// IntegrationTestingHelpers.swift
// DICOMStudio
//
// DICOM Studio — Helper enums for Integration Testing, Accessibility & Polish (Milestone 23)

import Foundation

// MARK: - E2E Test Helpers

/// Helpers for end-to-end integration test generation and summary reporting.
public enum E2ETestHelpers: Sendable {

    /// Total number of CLI tools across all categories (the sum of `IntegrationTestToolCategory.toolCount`).
    public static var totalToolCount: Int {
        IntegrationTestToolCategory.allCases.reduce(0) { $0 + $1.toolCount }
    }

    /// Generates test cases for every tool in the given category.
    public static func generateTestCases(for category: IntegrationTestToolCategory) -> [IntegrationTestCase] {
        category.toolNames.map { toolName in
            IntegrationTestCase(
                toolName: toolName,
                category: category,
                testDescription: "E2E test for \(toolName)"
            )
        }
    }

    /// Returns a human-readable summary such as "12/15 passed across 3 suites".
    public static func statusSummary(for suites: [IntegrationTestSuite]) -> String {
        let totalPassed = suites.reduce(0) { $0 + $1.passedCount }
        let totalTests = suites.reduce(0) { $0 + $1.totalCount }
        return "\(totalPassed)/\(totalTests) passed across \(suites.count) suites"
    }

    /// Pass rate for a single suite as a percentage (0.0–100.0).
    public static func categoryPassRate(for suite: IntegrationTestSuite) -> Double {
        guard suite.totalCount > 0 else { return 0.0 }
        return Double(suite.passedCount) / Double(suite.totalCount) * 100.0
    }
}

// MARK: - Unit Test Coverage Helpers

/// Helpers for tracking unit test counts and coverage targets.
public enum UnitTestCoverageHelpers: Sendable {

    /// Target overall coverage percentage.
    public static let targetCoveragePercent: Double = 95.0

    /// Target total test count across all suites.
    public static let targetTotalTests: Int = 400

    /// Whether the overall target is met: total tests >= 400 and every suite >= 95% coverage.
    public static func meetsOverallTarget(entries: [UnitTestSuiteEntry]) -> Bool {
        let totalTests = entries.reduce(0) { $0 + $1.testCount }
        guard totalTests >= targetTotalTests else { return false }
        return entries.allSatisfy { $0.coveragePercent >= targetCoveragePercent }
    }

    /// Weighted average coverage across all suites (weighted by test count).
    public static func overallCoveragePercent(entries: [UnitTestSuiteEntry]) -> Double {
        let totalTests = entries.reduce(0) { $0 + $1.testCount }
        guard totalTests > 0 else { return 0.0 }
        let weightedSum = entries.reduce(0.0) { $0 + $1.coveragePercent * Double($1.testCount) }
        return weightedSum / Double(totalTests)
    }

    /// Human-readable summary such as "350 tests, 96.2% avg coverage".
    public static func coverageSummary(entries: [UnitTestSuiteEntry]) -> String {
        let totalTests = entries.reduce(0) { $0 + $1.testCount }
        let avgCoverage = overallCoveragePercent(entries: entries)
        return "\(totalTests) tests, \(String(format: "%.1f", avgCoverage))% avg coverage"
    }
}

// MARK: - Accessibility Audit Helpers

/// Helpers for generating accessibility audit checklists and evaluating compliance.
public enum AccessibilityAuditHelpers: Sendable {

    /// Generates the standard set of VoiceOver check items.
    public static func generateVoiceOverChecks() -> [IntegrationAccessibilityCheckItem] {
        [
            IntegrationAccessibilityCheckItem(
                category: .voiceOver,
                checkDescription: "All interactive controls have accessibility labels"
            ),
            IntegrationAccessibilityCheckItem(
                category: .voiceOver,
                checkDescription: "Navigation order follows logical reading flow"
            ),
            IntegrationAccessibilityCheckItem(
                category: .voiceOver,
                checkDescription: "All functionality reachable without mouse"
            ),
            IntegrationAccessibilityCheckItem(
                category: .voiceOver,
                checkDescription: "Terminal output announced to VoiceOver"
            ),
            IntegrationAccessibilityCheckItem(
                category: .voiceOver,
                checkDescription: "Server connection status announced"
            ),
            IntegrationAccessibilityCheckItem(
                category: .voiceOver,
                checkDescription: "Error states communicated clearly"
            ),
        ]
    }

    /// Generates predefined keyboard shortcut entries.
    public static func generateKeyboardShortcuts() -> [IntegrationKeyboardShortcutEntry] {
        [
            IntegrationKeyboardShortcutEntry(shortcut: "⌘R", action: "Run command"),
            IntegrationKeyboardShortcutEntry(shortcut: "⌘.", action: "Stop command"),
            IntegrationKeyboardShortcutEntry(shortcut: "⌘K", action: "Clear terminal"),
            IntegrationKeyboardShortcutEntry(shortcut: "⌘O", action: "Open file"),
            IntegrationKeyboardShortcutEntry(shortcut: "⌘1–⌘9", action: "Switch tool category"),
            IntegrationKeyboardShortcutEntry(shortcut: "↑↓", action: "Navigate tool list"),
            IntegrationKeyboardShortcutEntry(shortcut: "Escape", action: "Cancel / dismiss"),
        ]
    }

    /// Overall compliance score as a formatted string such as "87% compliant".
    public static func overallComplianceScore(audits: [AccessibilityAuditResult]) -> String {
        let totalItems = audits.reduce(0) { $0 + $1.totalCount }
        let compliantItems = audits.reduce(0) { $0 + $1.compliantCount }
        guard totalItems > 0 else { return "0% compliant" }
        let percent = Double(compliantItems) / Double(totalItems) * 100.0
        return "\(Int(percent))% compliant"
    }

    /// Simplified WCAG contrast ratio from two relative luminance values (0.0–1.0).
    public static func wcagContrastRatio(foreground: Double, background: Double) -> Double {
        let lighter = max(foreground, background)
        let darker = min(foreground, background)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Whether the contrast ratio meets WCAG AA (4.5:1 normal text, 3:1 large text).
    public static func meetsWCAGAA(ratio: Double, isLargeText: Bool) -> Bool {
        isLargeText ? ratio >= 3.0 : ratio >= 4.5
    }
}

// MARK: - Performance Benchmark Helpers

/// Helpers for creating default performance benchmarks and summarizing results.
public enum PerformanceBenchmarkHelpers: Sendable {

    /// Creates the default benchmark results with predefined target values.
    public static func defaultTargets() -> [PerformanceBenchmarkResult] {
        [
            PerformanceBenchmarkResult(metric: .launchTime, measuredValue: 0.0, targetValue: 2.0, meetsTarget: false),
            PerformanceBenchmarkResult(metric: .sidebarRendering, measuredValue: 0.0, targetValue: 60.0, meetsTarget: false),
            PerformanceBenchmarkResult(metric: .parameterFormRendering, measuredValue: 0.0, targetValue: 50.0, meetsTarget: false),
            PerformanceBenchmarkResult(metric: .terminalOutput, measuredValue: 0.0, targetValue: 10000.0, meetsTarget: false),
            PerformanceBenchmarkResult(metric: .memoryUsage, measuredValue: 0.0, targetValue: 150.0, meetsTarget: false),
            PerformanceBenchmarkResult(metric: .fileDropValidation, measuredValue: 0.0, targetValue: 200.0, meetsTarget: false),
            PerformanceBenchmarkResult(metric: .commandPreviewUpdate, measuredValue: 0.0, targetValue: 100.0, meetsTarget: false),
        ]
    }

    /// Formats a measured value with the appropriate unit for the metric type.
    public static func formattedMetric(value: Double, metric: PerformanceMetricType) -> String {
        switch metric {
        case .launchTime:
            return String(format: "%.2f %@", value, metric.unit)
        case .sidebarRendering:
            return "\(Int(value)) \(metric.unit)"
        case .parameterFormRendering, .fileDropValidation, .commandPreviewUpdate:
            return String(format: "%.0f %@", value, metric.unit)
        case .terminalOutput:
            return "\(Int(value)) \(metric.unit)"
        case .memoryUsage:
            return String(format: "%.1f %@", value, metric.unit)
        }
    }

    /// Whether every benchmark result meets its target.
    public static func meetsAllTargets(results: [PerformanceBenchmarkResult]) -> Bool {
        !results.isEmpty && results.allSatisfy { $0.meetsTarget }
    }

    /// Human-readable summary such as "5/7 targets met".
    public static func performanceSummary(results: [PerformanceBenchmarkResult]) -> String {
        let met = results.filter { $0.meetsTarget }.count
        return "\(met)/\(results.count) targets met"
    }
}

// MARK: - UI Polish Check Helpers

/// Helpers for generating and evaluating the UI polish checklist.
public enum UIPolishCheckHelpers: Sendable {

    /// Generates the standard UI polish checklist items.
    public static func generatePolishChecklist() -> [UIPolishCheckItem] {
        [
            UIPolishCheckItem(category: .spacing, checkDescription: "Consistent spacing between all UI elements"),
            UIPolishCheckItem(category: .animations, checkDescription: "Smooth animations for sidebar and panel transitions"),
            UIPolishCheckItem(category: .loadingStates, checkDescription: "Loading indicators for all async operations"),
            UIPolishCheckItem(category: .errorStates, checkDescription: "Error states with actionable recovery messages"),
            UIPolishCheckItem(category: .emptyStates, checkDescription: "Empty state placeholders for lists and collections"),
            UIPolishCheckItem(category: .windowTitle, checkDescription: "Window title updates to reflect selected tool"),
            UIPolishCheckItem(category: .touchBar, checkDescription: "Touch Bar shows Run and Stop controls"),
            UIPolishCheckItem(category: .menuBar, checkDescription: "Menu bar items update for current context"),
            UIPolishCheckItem(category: .darkMode, checkDescription: "All colors correct in Dark Mode"),
            UIPolishCheckItem(category: .lightMode, checkDescription: "Sufficient contrast in Light Mode"),
            UIPolishCheckItem(category: .toolbar, checkDescription: "Toolbar supports user customisation"),
        ]
    }

    /// Percentage of checklist items that have been verified (0.0–100.0).
    public static func completionPercent(checks: [UIPolishCheckItem]) -> Double {
        guard !checks.isEmpty else { return 0.0 }
        let verified = checks.filter { $0.isVerified }.count
        return Double(verified) / Double(checks.count) * 100.0
    }

    /// Human-readable summary such as "8/11 verified".
    public static func polishSummary(checks: [UIPolishCheckItem]) -> String {
        let verified = checks.filter { $0.isVerified }.count
        return "\(verified)/\(checks.count) verified"
    }
}

// MARK: - Documentation Progress Helpers

/// Helpers for tracking in-app help, user guide, and release notes documentation.
public enum DocumentationProgressHelpers: Sendable {

    /// Generates in-app help documentation entries.
    public static func generateInAppHelpEntries() -> [IntegrationDocumentationEntry] {
        [
            IntegrationDocumentationEntry(section: .inAppHelp, title: "Tool help buttons"),
            IntegrationDocumentationEntry(section: .inAppHelp, title: "Parameter tooltips"),
            IntegrationDocumentationEntry(section: .inAppHelp, title: "What's New sheet"),
        ]
    }

    /// Generates user guide documentation entries.
    public static func generateUserGuideEntries() -> [IntegrationDocumentationEntry] {
        [
            IntegrationDocumentationEntry(section: .userGuide, title: "Getting started"),
            IntegrationDocumentationEntry(section: .userGuide, title: "Server configuration walkthrough"),
            IntegrationDocumentationEntry(section: .userGuide, title: "Tool reference"),
            IntegrationDocumentationEntry(section: .userGuide, title: "Keyboard shortcuts"),
            IntegrationDocumentationEntry(section: .userGuide, title: "Troubleshooting"),
        ]
    }

    /// Generates release notes documentation entries.
    public static func generateReleaseNotesEntries() -> [IntegrationDocumentationEntry] {
        [
            IntegrationDocumentationEntry(section: .releaseNotes, title: "Changelog"),
            IntegrationDocumentationEntry(section: .releaseNotes, title: "Migration notes"),
        ]
    }

    /// Human-readable summary such as "6/10 published".
    public static func overallProgress(entries: [IntegrationDocumentationEntry]) -> String {
        let published = entries.filter { $0.isComplete }.count
        return "\(published)/\(entries.count) published"
    }

    /// Percentage of entries that are published (0.0–100.0).
    public static func completionPercent(entries: [IntegrationDocumentationEntry]) -> Double {
        guard !entries.isEmpty else { return 0.0 }
        let published = entries.filter { $0.isComplete }.count
        return Double(published) / Double(entries.count) * 100.0
    }
}
