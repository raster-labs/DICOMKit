// PolishReleaseHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for Polish, Accessibility & Release (Milestone 15)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (sample localization entries, WCAG
// checklist, coverage and benchmark targets); the VoiceOver label takes the modality string it is given.

import Foundation

// MARK: - 15.1 Internationalization Helpers

/// Helpers for internationalization and localization tasks.
public enum I18nHelpers: Sendable {

    /// Returns the default set of localization coverage summaries.
    public static func defaultCoverageSummaries() -> [LocalizationCoverageSummary] {
        LocalizationLanguage.allCases.map { language in
            let (translated, total, status): (Int, Int, LocalizationStatus)
            switch language {
            case .english:
                (translated, total, status) = (500, 500, .complete)
            case .spanish, .french, .german:
                (translated, total, status) = (480, 500, .partial)
            case .japanese, .chineseSimplified:
                (translated, total, status) = (400, 500, .partial)
            case .korean, .portugueseBrazil:
                (translated, total, status) = (200, 500, .inProgress)
            case .arabic, .hebrew:
                (translated, total, status) = (100, 500, .inProgress)
            }
            return LocalizationCoverageSummary(
                language: language,
                totalStrings: total,
                translatedStrings: translated,
                status: status
            )
        }
    }

    /// Returns the sample localization entries for common strings.
    public static func sampleLocalizationEntries() -> [LocalizationEntry] {
        [
            LocalizationEntry(
                key: "study.count.format",
                baseValue: "%d studies",
                translations: [
                    "es": "%d estudios",
                    "fr": "%d études",
                    "de": "%d Studien"
                ],
                context: "Number of DICOM studies in a list",
                featureArea: "StudyBrowser"
            ),
            LocalizationEntry(
                key: "series.count.format",
                baseValue: "%d series",
                translations: [
                    "es": "%d series",
                    "fr": "%d séries",
                    "de": "%d Serien"
                ],
                context: "Number of DICOM series in a study",
                featureArea: "StudyBrowser"
            ),
            LocalizationEntry(
                key: "import.drop.hint",
                baseValue: "Drop DICOM files here",
                translations: [
                    "es": "Suelta archivos DICOM aquí",
                    "fr": "Déposez les fichiers DICOM ici",
                    "de": "DICOM-Dateien hier ablegen"
                ],
                context: "Hint text for the DICOM import drop zone",
                featureArea: "Import"
            ),
            LocalizationEntry(
                key: "window.level.label",
                baseValue: "Window / Level",
                translations: [
                    "es": "Ventana / Nivel",
                    "fr": "Fenêtre / Niveau",
                    "de": "Fenster / Niveau"
                ],
                context: "Label for the window/level control in the image viewer",
                featureArea: "ImageViewer"
            ),
            LocalizationEntry(
                key: "anonymize.confirm.title",
                baseValue: "Anonymize DICOM File",
                translations: [
                    "es": "Anonimizar archivo DICOM",
                    "fr": "Anonymiser le fichier DICOM",
                    "de": "DICOM-Datei anonymisieren"
                ],
                context: "Title of the anonymization confirmation dialog",
                featureArea: "Security"
            ),
        ]
    }

    /// Returns a description of RTL layout requirements.
    public static func rtlLayoutDescription() -> String {
        "Use semantic layout constraints (.leading/.trailing) and natural text alignment for correct RTL mirroring."
    }

    /// Returns true if `language` requires RTL layout.
    public static func requiresRTL(_ language: LocalizationLanguage) -> Bool {
        language.isRTL
    }

    /// Returns the locale identifier string for a given language.
    public static func localeIdentifier(for language: LocalizationLanguage) -> String {
        language.rawValue
    }

    /// Formats a sample date string for the given language using the system locale.
    public static func sampleDateFormatDescription(for language: LocalizationLanguage) -> String {
        "Use DateFormatter with .dateStyle = .medium and locale set to \(language.rawValue)"
    }

    /// Returns the formatter type descriptions.
    public static func formatterDescriptions() -> [LocaleFormatterType: String] {
        [
            .date:        "Use DateFormatter with appropriate style and Locale",
            .number:      "Use NumberFormatter for integers, decimals, and percentages",
            .measurement: "Use MeasurementFormatter for medical measurements (mm, cm, etc.)",
            .fileSize:    "Use ByteCountFormatter for storage information",
            .plural:      "Use .stringsdict files for correct plural handling per language",
        ]
    }

    /// Returns the languages that require pluralization rules.
    public static func languagesRequiringPluralRules() -> [LocalizationLanguage] {
        // All languages have some pluralization rules; RTL languages often have more forms
        LocalizationLanguage.allCases
    }
}

// MARK: - 15.2 Accessibility Helpers

/// Helpers for accessibility audit and compliance tasks.
public enum A11yHelpers: Sendable {

    /// Returns the default accessibility checklist for DICOM Studio.
    public static func defaultCheckItems() -> [AccessibilityCheckItem] {
        var items: [AccessibilityCheckItem] = []

        // VoiceOver
        items.append(AccessibilityCheckItem(
            category: .voiceOver,
            description: "All buttons have accessibility labels",
            screenName: "Global"
        ))
        items.append(AccessibilityCheckItem(
            category: .voiceOver,
            description: "Complex actions have accessibility hints",
            screenName: "Global"
        ))
        items.append(AccessibilityCheckItem(
            category: .voiceOver,
            description: "Dynamic content exposes accessibility values (window/level, measurements)",
            screenName: "ImageViewer"
        ))
        items.append(AccessibilityCheckItem(
            category: .voiceOver,
            description: "Reading order is logical (top-to-bottom, leading-to-trailing)",
            screenName: "StudyBrowser"
        ))
        items.append(AccessibilityCheckItem(
            category: .voiceOver,
            description: "Custom actions provided for medical imaging controls",
            screenName: "ImageViewer"
        ))

        // Dynamic Type
        items.append(AccessibilityCheckItem(
            category: .dynamicType,
            description: "Text scales correctly at all Dynamic Type sizes",
            screenName: "Global"
        ))
        items.append(AccessibilityCheckItem(
            category: .dynamicType,
            description: "Layouts do not break with largest accessibility text sizes",
            screenName: "Global"
        ))

        // High Contrast
        items.append(AccessibilityCheckItem(
            category: .highContrast,
            description: "Text meets WCAG AA contrast ratio (4.5:1 normal, 3:1 large)",
            screenName: "Global"
        ))
        items.append(AccessibilityCheckItem(
            category: .highContrast,
            description: "UI is functional in Increase Contrast mode",
            screenName: "Global"
        ))

        // Reduce Motion
        items.append(AccessibilityCheckItem(
            category: .reduceMotion,
            description: "Animations are skipped when Reduce Motion is enabled",
            screenName: "Global"
        ))
        items.append(AccessibilityCheckItem(
            category: .reduceMotion,
            description: "Cine playback animation respects reduceMotion preference",
            screenName: "ImageViewer"
        ))

        // Switch Control
        items.append(AccessibilityCheckItem(
            category: .switchControl,
            description: "All actions reachable via keyboard / Switch Control",
            screenName: "Global"
        ))
        items.append(AccessibilityCheckItem(
            category: .switchControl,
            description: "Custom gestures have keyboard alternatives",
            screenName: "ImageViewer"
        ))

        // Color Blindness
        items.append(AccessibilityCheckItem(
            category: .colorBlindness,
            description: "Color is not the only means of conveying information",
            screenName: "Global"
        ))
        items.append(AccessibilityCheckItem(
            category: .colorBlindness,
            description: "Status icons/labels supplement color-coded elements",
            screenName: "Networking"
        ))

        // Focus Indicators
        items.append(AccessibilityCheckItem(
            category: .focusIndicator,
            description: "All focusable elements show visible focus ring",
            screenName: "Global"
        ))

        return items
    }

    /// Builds an audit report from the given check items.
    public static func buildAuditReport(from items: [AccessibilityCheckItem]) -> AccessibilityAuditReport {
        let total  = items.count
        let passed = items.filter { $0.status == .passed }.count
        let failed = items.filter { $0.status == .failed }.count
        let partial = items.filter { $0.status == .partial }.count
        let notTested = items.filter { $0.status == .notTested }.count
        return AccessibilityAuditReport(
            totalChecks: total,
            passedChecks: passed,
            failedChecks: failed,
            partialChecks: partial,
            notTestedChecks: notTested
        )
    }

    /// Returns the WCAG contrast ratio guideline description.
    public static func wcagContrastGuideline() -> String {
        "Minimum 4.5:1 for normal text, 3:1 for large text (18pt+)"
    }

    /// Returns the recommended VoiceOver label format for a DICOM image frame.
    public static func voiceOverLabel(forModality modality: String, frameNumber: Int, totalFrames: Int) -> String {
        "\(modality) scan, frame \(frameNumber) of \(totalFrames)"
    }

    /// Returns the accessibility value string for a window/level control.
    public static func windowLevelAccessibilityValue(windowCenter: Double, windowWidth: Double) -> String {
        "Center \(Int(windowCenter)) HU, Width \(Int(windowWidth)) HU"
    }

    /// Returns the recommended adjustable action description for window/level.
    public static func windowLevelAdjustableActionDescription() -> String {
        "Swipe up or down to adjust window center; use accessibilityAdjustableAction for keyboard control"
    }
}

// MARK: - 15.3 Testing Helpers

/// Helpers for test coverage tracking and UI test flow management.
public enum TestingHelpers: Sendable {

    /// Returns the default set of UI test flow entries.
    public static func defaultUITestFlows() -> [UITestFlowEntry] {
        UITestFlowType.allCases.map { flowType in
            UITestFlowEntry(flowType: flowType, status: .pending)
        }
    }

    /// Returns sample coverage targets for DICOMStudio ViewModels.
    public static func sampleCoverageTargets() -> [TestCoverageTarget] {
        [
            TestCoverageTarget(moduleName: "MainViewModel",             coveragePercent: 97.0, testCount: 42),
            TestCoverageTarget(moduleName: "StudyBrowserViewModel",     coveragePercent: 96.5, testCount: 38),
            TestCoverageTarget(moduleName: "ImageViewerViewModel",      coveragePercent: 95.2, testCount: 51),
            TestCoverageTarget(moduleName: "NetworkingViewModel",       coveragePercent: 95.8, testCount: 47),
            TestCoverageTarget(moduleName: "SecurityViewModel",         coveragePercent: 96.1, testCount: 35),
            TestCoverageTarget(moduleName: "DataExchangeViewModel",     coveragePercent: 95.0, testCount: 40),
            TestCoverageTarget(moduleName: "MacOSEnhancementsViewModel",coveragePercent: 96.4, testCount: 30),
            TestCoverageTarget(moduleName: "PerformanceToolsViewModel", coveragePercent: 95.6, testCount: 33),
        ]
    }

    /// Returns the count of coverage targets that meet the 95% threshold.
    public static func passingTargetCount(from targets: [TestCoverageTarget]) -> Int {
        targets.filter { $0.meetsTarget }.count
    }

    /// Returns average coverage percent across all targets.
    public static func averageCoverage(from targets: [TestCoverageTarget]) -> Double {
        guard !targets.isEmpty else { return 0 }
        let total = targets.reduce(0.0) { $0 + $1.coveragePercent }
        return total / Double(targets.count)
    }

    /// Returns default performance benchmarks for DICOM Studio.
    public static func defaultBenchmarks() -> [PerformanceBenchmark] {
        [
            PerformanceBenchmark(name: "Large file loading", targetDescription: "<2s for 100MB file", isPassing: true),
            PerformanceBenchmark(name: "Multi-frame playback", targetDescription: "60fps for 512×512 series", isPassing: true),
            PerformanceBenchmark(name: "Network throughput", targetDescription: ">50MB/s on LAN", isPassing: true),
            PerformanceBenchmark(name: "Memory ceiling (iOS)", targetDescription: "<200MB steady-state", isPassing: true),
            PerformanceBenchmark(name: "UI interaction latency", targetDescription: "<100ms response", isPassing: true),
        ]
    }
}

// MARK: - 15.4 Performance Profiling Helpers

/// Helpers for performance profiling session management.
public enum PerformanceProfilingHelpers: Sendable {

    /// Returns the default set of profiling session entries.
    public static func defaultProfilingSessions() -> [ProfilingSessionEntry] {
        ProfilerSessionType.allCases.map { sessionType in
            ProfilingSessionEntry(sessionType: sessionType, status: .notStarted)
        }
    }

    /// Returns the Instruments tool name for a given session type.
    public static func instrumentsToolName(for sessionType: ProfilerSessionType) -> String {
        switch sessionType {
        case .memory:  return "Leaks + Allocations"
        case .cpu:     return "Time Profiler"
        case .gpu:     return "Metal System Trace"
        case .network: return "Network (custom DICOM trace)"
        case .battery: return "Energy Log"
        }
    }

    /// Returns a brief description of what to look for in each profiling session.
    public static func profilingFocus(for sessionType: ProfilerSessionType) -> String {
        switch sessionType {
        case .memory:
            return "Check for memory leaks in image cache and DICOM parser; monitor peak RSS during large series playback"
        case .cpu:
            return "Profile frame rendering, DICOM tag parsing, and network dispatch queues"
        case .gpu:
            return "Analyse Metal render pass timing, texture memory, and shader occupancy"
        case .network:
            return "Measure C-STORE throughput, C-FIND latency, and TLS handshake overhead"
        case .battery:
            return "Evaluate CPU wake frequency and GPU idle time during background operations"
        }
    }

    /// Returns a summary description for a completed session.
    public static func sessionSummary(for session: ProfilingSessionEntry) -> String {
        let status = session.status.displayName
        let type   = session.sessionType.displayName
        guard session.status == .completed else { return "\(type): \(status)" }
        let findingCount = session.findings.count
        return "\(type): \(findingCount) finding\(findingCount == 1 ? "" : "s") recorded"
    }
}

// MARK: - 15.5 Documentation Helpers

/// Helpers for documentation status tracking.
public enum DocumentationHelpers: Sendable {

    /// Returns the default documentation entries.
    public static func defaultDocumentationEntries() -> [DocumentationEntry] {
        [
            DocumentationEntry(
                docType: .userGuide,
                title: "DICOM Studio User Guide",
                status: .inProgress,
                wordCount: 3500
            ),
            DocumentationEntry(
                docType: .developerDocs,
                title: "DICOMKit Integration Guide",
                status: .inProgress,
                wordCount: 2800
            ),
            DocumentationEntry(
                docType: .apiExamples,
                title: "API Usage Examples",
                status: .planned,
                wordCount: 0
            ),
            DocumentationEntry(
                docType: .keyboardRef,
                title: "Keyboard Shortcuts Reference",
                status: .complete,
                wordCount: 800
            ),
            DocumentationEntry(
                docType: .troubleshooting,
                title: "Troubleshooting Guide",
                status: .planned,
                wordCount: 0
            ),
        ]
    }

    /// Returns total word count across all documentation entries.
    public static func totalWordCount(from entries: [DocumentationEntry]) -> Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    /// Returns entries that are complete.
    public static func completedEntries(from entries: [DocumentationEntry]) -> [DocumentationEntry] {
        entries.filter { $0.status == .complete }
    }

    /// Returns completion percentage (0–100) based on completed entries.
    public static func completionPercent(from entries: [DocumentationEntry]) -> Double {
        guard !entries.isEmpty else { return 0 }
        let completed = completedEntries(from: entries).count
        return Double(completed) / Double(entries.count) * 100.0
    }
}

// MARK: - 15.6 Release Helpers

/// Helpers for release preparation and checklist management.
public enum ReleaseHelpers: Sendable {

    /// Returns the default release checklist.
    public static func defaultReleaseChecklist() -> [ReleaseChecklistItem] {
        var items: [ReleaseChecklistItem] = []

        // App Store Metadata
        items.append(ReleaseChecklistItem(category: .appStoreMetadata, description: "Write app description and keywords"))
        items.append(ReleaseChecklistItem(category: .appStoreMetadata, description: "Prepare 10 App Store screenshots (macOS)"))
        items.append(ReleaseChecklistItem(category: .appStoreMetadata, description: "Add privacy policy URL"))
        items.append(ReleaseChecklistItem(category: .appStoreMetadata, description: "Select app category (Medical)"))

        // TestFlight
        items.append(ReleaseChecklistItem(category: .testFlight, description: "Upload build to TestFlight"))
        items.append(ReleaseChecklistItem(category: .testFlight, description: "Invite external beta testers"))
        items.append(ReleaseChecklistItem(category: .testFlight, description: "Collect and address beta feedback"))

        // Code Signing
        items.append(ReleaseChecklistItem(category: .codeSigning, description: "Configure distribution certificate"))
        items.append(ReleaseChecklistItem(category: .codeSigning, description: "Configure App Store provisioning profile"))
        items.append(ReleaseChecklistItem(category: .codeSigning, description: "Enable App Sandbox and required entitlements"))

        // Release Notes
        items.append(ReleaseChecklistItem(category: .releaseNotes, description: "Write release notes for v1.0"))
        items.append(ReleaseChecklistItem(category: .releaseNotes, description: "Update CHANGELOG.md"))
        items.append(ReleaseChecklistItem(category: .releaseNotes, description: "Tag git release (v1.0.0)"))

        // Homebrew
        items.append(ReleaseChecklistItem(category: .homebrew, description: "Create Homebrew cask formula"))
        items.append(ReleaseChecklistItem(category: .homebrew, description: "Submit cask to homebrew-cask repository"))

        return items
    }

    /// Returns the overall release status based on checklist completion.
    public static func releaseStatus(from items: [ReleaseChecklistItem]) -> ReleaseStatus {
        guard !items.isEmpty else { return .notStarted }
        let total     = items.count
        let completed = items.filter { $0.isCompleted }.count
        switch completed {
        case 0:
            return .notStarted
        case total:
            return .readyForReview
        default:
            return .inProgress
        }
    }

    /// Returns the count of completed checklist items per category.
    public static func completedCount(for category: ReleaseChecklistCategory, in items: [ReleaseChecklistItem]) -> Int {
        items.filter { $0.category == category && $0.isCompleted }.count
    }

    /// Returns the total count of items per category.
    public static func totalCount(for category: ReleaseChecklistCategory, in items: [ReleaseChecklistItem]) -> Int {
        items.filter { $0.category == category }.count
    }

    /// Returns a short summary string for the checklist, e.g. "8 / 15 complete".
    public static func checklistSummary(from items: [ReleaseChecklistItem]) -> String {
        let completed = items.filter { $0.isCompleted }.count
        return "\(completed) / \(items.count) complete"
    }
}
