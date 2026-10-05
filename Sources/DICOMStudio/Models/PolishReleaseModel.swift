// PolishReleaseModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Polish, Accessibility & Release (Milestone 15)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (localization, accessibility, testing,
// profiling, documentation and release-checklist records; the word DICOM appears only in display text).

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the Polish, Accessibility & Release feature.
public enum PolishReleaseTab: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case i18n          = "I18N"
    case accessibility = "ACCESSIBILITY"
    case testing       = "TESTING"
    case performance   = "PERFORMANCE"
    case documentation = "DOCUMENTATION"
    case release       = "RELEASE"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .i18n:          return "Internationalization"
        case .accessibility: return "Accessibility"
        case .testing:       return "Testing"
        case .performance:   return "Performance"
        case .documentation: return "Documentation"
        case .release:       return "Release"
        }
    }

    /// SF Symbol name for this tab.
    public var sfSymbol: String {
        switch self {
        case .i18n:          return "globe"
        case .accessibility: return "accessibility"
        case .testing:       return "checkmark.seal"
        case .performance:   return "gauge.with.needle"
        case .documentation: return "doc.text.magnifyingglass"
        case .release:       return "paperplane"
        }
    }
}

// MARK: - 15.1 Internationalization

/// Supported localization languages, ordered by priority.
public enum LocalizationLanguage: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case english           = "en"
    case spanish           = "es"
    case french            = "fr"
    case german            = "de"
    case japanese          = "ja"
    case chineseSimplified = "zh-Hans"
    case korean            = "ko"
    case portugueseBrazil  = "pt-BR"
    case arabic            = "ar"
    case hebrew            = "he"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .english:           return "English (US)"
        case .spanish:           return "Spanish"
        case .french:            return "French"
        case .german:            return "German"
        case .japanese:          return "Japanese"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .korean:            return "Korean"
        case .portugueseBrazil:  return "Portuguese (Brazil)"
        case .arabic:            return "Arabic"
        case .hebrew:            return "Hebrew"
        }
    }

    /// True if this language is written right-to-left.
    public var isRTL: Bool {
        self == .arabic || self == .hebrew
    }

    /// Priority tier for implementation order.
    public var tier: LocalizationTier {
        switch self {
        case .english:                         return .primary
        case .spanish, .french, .german,
             .japanese, .chineseSimplified:    return .highPriority
        case .korean, .portugueseBrazil,
             .arabic, .hebrew:                return .medicalMarkets
        }
    }
}

/// Priority tier for localization implementation.
public enum LocalizationTier: String, Sendable, Equatable, Hashable, CaseIterable {
    case primary       = "PRIMARY"
    case highPriority  = "HIGH_PRIORITY"
    case medicalMarkets = "MEDICAL_MARKETS"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .primary:        return "Primary"
        case .highPriority:   return "High Priority"
        case .medicalMarkets: return "Medical Markets"
        }
    }
}

/// Status of a localization effort.
public enum LocalizationStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case complete   = "COMPLETE"
    case partial    = "PARTIAL"
    case inProgress = "IN_PROGRESS"
    case missing    = "MISSING"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .complete:   return "Complete"
        case .partial:    return "Partial"
        case .inProgress: return "In Progress"
        case .missing:    return "Missing"
        }
    }

    /// SF Symbol for this status.
    public var sfSymbol: String {
        switch self {
        case .complete:   return "checkmark.circle.fill"
        case .partial:    return "circle.lefthalf.filled"
        case .inProgress: return "arrow.clockwise.circle"
        case .missing:    return "xmark.circle"
        }
    }
}

/// A single localization string entry.
public struct LocalizationEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Localization key, e.g. "study.count.format".
    public var key: String
    /// The English base value.
    public var baseValue: String
    /// Translations keyed by `LocalizationLanguage.rawValue`.
    public var translations: [String: String]
    /// Context comment for translators.
    public var context: String
    /// Feature area this string belongs to (e.g. "StudyBrowser").
    public var featureArea: String

    public init(
        id: UUID = UUID(),
        key: String,
        baseValue: String,
        translations: [String: String] = [:],
        context: String = "",
        featureArea: String = ""
    ) {
        self.id = id
        self.key = key
        self.baseValue = baseValue
        self.translations = translations
        self.context = context
        self.featureArea = featureArea
    }
}

/// Summary of localization coverage for one language.
public struct LocalizationCoverageSummary: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var language: LocalizationLanguage
    public var totalStrings: Int
    public var translatedStrings: Int
    public var status: LocalizationStatus

    /// Percentage of strings translated (0–100).
    public var coveragePercent: Double {
        guard totalStrings > 0 else { return 0 }
        return Double(translatedStrings) / Double(totalStrings) * 100.0
    }

    public init(
        id: UUID = UUID(),
        language: LocalizationLanguage,
        totalStrings: Int,
        translatedStrings: Int,
        status: LocalizationStatus
    ) {
        self.id = id
        self.language = language
        self.totalStrings = totalStrings
        self.translatedStrings = translatedStrings
        self.status = status
    }
}

/// Type of locale-aware formatter.
public enum LocaleFormatterType: String, Sendable, Equatable, Hashable, CaseIterable {
    case date        = "DATE"
    case number      = "NUMBER"
    case measurement = "MEASUREMENT"
    case fileSize    = "FILE_SIZE"
    case plural      = "PLURAL"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .date:        return "Date & Time"
        case .number:      return "Numbers"
        case .measurement: return "Measurements"
        case .fileSize:    return "File Sizes"
        case .plural:      return "Pluralization"
        }
    }
}

// MARK: - 15.2 Accessibility

/// Categories of accessibility checks.
public enum AccessibilityCheckCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case voiceOver      = "VOICE_OVER"
    case dynamicType    = "DYNAMIC_TYPE"
    case highContrast   = "HIGH_CONTRAST"
    case reduceMotion   = "REDUCE_MOTION"
    case switchControl  = "SWITCH_CONTROL"
    case colorBlindness = "COLOR_BLINDNESS"
    case focusIndicator = "FOCUS_INDICATOR"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .voiceOver:      return "VoiceOver"
        case .dynamicType:    return "Dynamic Type"
        case .highContrast:   return "High Contrast"
        case .reduceMotion:   return "Reduce Motion"
        case .switchControl:  return "Switch Control"
        case .colorBlindness: return "Color Blindness"
        case .focusIndicator: return "Focus Indicators"
        }
    }

    /// SF Symbol for this category.
    public var sfSymbol: String {
        switch self {
        case .voiceOver:      return "speaker.wave.2"
        case .dynamicType:    return "textformat.size"
        case .highContrast:   return "circle.lefthalf.filled"
        case .reduceMotion:   return "figure.walk.motion"
        case .switchControl:  return "gamecontroller"
        case .colorBlindness: return "eye.slash"
        case .focusIndicator: return "target"
        }
    }
}

/// Pass/fail status of an accessibility check.
public enum AccessibilityCheckStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case passed    = "PASSED"
    case failed    = "FAILED"
    case partial   = "PARTIAL"
    case notTested = "NOT_TESTED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .passed:    return "Passed"
        case .failed:    return "Failed"
        case .partial:   return "Partial"
        case .notTested: return "Not Tested"
        }
    }

    /// SF Symbol for this status.
    public var sfSymbol: String {
        switch self {
        case .passed:    return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .partial:   return "exclamationmark.circle.fill"
        case .notTested: return "questionmark.circle"
        }
    }
}

/// A single accessibility check item.
public struct AccessibilityCheckItem: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var category: AccessibilityCheckCategory
    public var description: String
    public var status: AccessibilityCheckStatus
    public var notes: String
    /// Screen or component that this check applies to.
    public var screenName: String

    public init(
        id: UUID = UUID(),
        category: AccessibilityCheckCategory,
        description: String,
        status: AccessibilityCheckStatus = .notTested,
        notes: String = "",
        screenName: String = ""
    ) {
        self.id = id
        self.category = category
        self.description = description
        self.status = status
        self.notes = notes
        self.screenName = screenName
    }
}

/// Summary report from an accessibility audit.
public struct AccessibilityAuditReport: Sendable {
    public var auditDate: Date
    public var totalChecks: Int
    public var passedChecks: Int
    public var failedChecks: Int
    public var partialChecks: Int
    public var notTestedChecks: Int

    /// Overall pass rate (0–100).
    public var passRate: Double {
        guard totalChecks > 0 else { return 0 }
        return Double(passedChecks) / Double(totalChecks) * 100.0
    }

    public init(
        auditDate: Date = Date(),
        totalChecks: Int,
        passedChecks: Int,
        failedChecks: Int,
        partialChecks: Int,
        notTestedChecks: Int
    ) {
        self.auditDate = auditDate
        self.totalChecks = totalChecks
        self.passedChecks = passedChecks
        self.failedChecks = failedChecks
        self.partialChecks = partialChecks
        self.notTestedChecks = notTestedChecks
    }
}

// MARK: - 15.3 Comprehensive Testing

/// Types of UI test workflows.
public enum UITestFlowType: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case importBrowseView    = "IMPORT_BROWSE_VIEW"
    case queryRetrieveDisplay = "QUERY_RETRIEVE_DISPLAY"
    case measureSaveSR       = "MEASURE_SAVE_SR"
    case anonymizeExport     = "ANONYMIZE_EXPORT"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .importBrowseView:     return "Import → Browse → View"
        case .queryRetrieveDisplay: return "Query → Retrieve → Display"
        case .measureSaveSR:        return "Measure → Save SR → Reload"
        case .anonymizeExport:      return "Anonymize → Export"
        }
    }

    /// Short description of this workflow.
    public var description: String {
        switch self {
        case .importBrowseView:
            return "Open a DICOM file, browse the study list, and view images"
        case .queryRetrieveDisplay:
            return "Query a PACS, retrieve a series, and display frames"
        case .measureSaveSR:
            return "Draw a measurement, save as Structured Report, and reload it"
        case .anonymizeExport:
            return "Anonymize patient data and export the result"
        }
    }
}

/// Status of a UI test flow execution.
public enum UITestFlowStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case pending = "PENDING"
    case passing = "PASSING"
    case failing = "FAILING"
    case skipped = "SKIPPED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .passing: return "Passing"
        case .failing: return "Failing"
        case .skipped: return "Skipped"
        }
    }

    /// SF Symbol for this status.
    public var sfSymbol: String {
        switch self {
        case .pending: return "clock"
        case .passing: return "checkmark.circle.fill"
        case .failing: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }
}

/// A single UI test flow entry with execution status.
public struct UITestFlowEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var flowType: UITestFlowType
    public var status: UITestFlowStatus
    public var lastRunDate: Date?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        flowType: UITestFlowType,
        status: UITestFlowStatus = .pending,
        lastRunDate: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.flowType = flowType
        self.status = status
        self.lastRunDate = lastRunDate
        self.errorMessage = errorMessage
    }
}

/// Coverage report for a single ViewModel or module.
public struct TestCoverageTarget: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var moduleName: String
    public var coveragePercent: Double
    public var testCount: Int
    public var meetsTarget: Bool

    public init(
        id: UUID = UUID(),
        moduleName: String,
        coveragePercent: Double,
        testCount: Int,
        targetPercent: Double = 95.0
    ) {
        self.id = id
        self.moduleName = moduleName
        self.coveragePercent = coveragePercent
        self.testCount = testCount
        self.meetsTarget = coveragePercent >= targetPercent
    }
}

// MARK: - 15.4 Performance Profiling

/// Types of profiling sessions.
public enum ProfilerSessionType: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case memory  = "MEMORY"
    case cpu     = "CPU"
    case gpu     = "GPU"
    case network = "NETWORK"
    case battery = "BATTERY"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .memory:  return "Memory (Instruments)"
        case .cpu:     return "CPU (Time Profiler)"
        case .gpu:     return "GPU (Metal System Trace)"
        case .network: return "Network (DICOM/DICOMweb)"
        case .battery: return "Battery Impact"
        }
    }

    /// SF Symbol for this session type.
    public var sfSymbol: String {
        switch self {
        case .memory:  return "memorychip"
        case .cpu:     return "cpu"
        case .gpu:     return "gpu"
        case .network: return "network"
        case .battery: return "battery.100"
        }
    }
}

/// Status of a profiling session.
public enum ProfilingSessionStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case notStarted = "NOT_STARTED"
    case running    = "RUNNING"
    case completed  = "COMPLETED"
    case failed     = "FAILED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .running:    return "Running"
        case .completed:  return "Completed"
        case .failed:     return "Failed"
        }
    }
}

/// A single profiling session entry.
public struct ProfilingSessionEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var sessionType: ProfilerSessionType
    public var status: ProfilingSessionStatus
    public var startDate: Date?
    public var durationSeconds: Double
    /// Key findings from the profiling session.
    public var findings: [String]

    public init(
        id: UUID = UUID(),
        sessionType: ProfilerSessionType,
        status: ProfilingSessionStatus = .notStarted,
        startDate: Date? = nil,
        durationSeconds: Double = 0,
        findings: [String] = []
    ) {
        self.id = id
        self.sessionType = sessionType
        self.status = status
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.findings = findings
    }
}

/// A performance benchmark target.
public struct PerformanceBenchmark: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Description of the benchmark, e.g. "Large file loading".
    public var name: String
    /// Target value with unit, e.g. "<2s for 100MB".
    public var targetDescription: String
    /// Whether this benchmark has been verified as passing.
    public var isPassing: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        targetDescription: String,
        isPassing: Bool = false
    ) {
        self.id = id
        self.name = name
        self.targetDescription = targetDescription
        self.isPassing = isPassing
    }
}

// MARK: - 15.5 Documentation

/// Types of documentation pages.
public enum DocPageType: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case userGuide       = "USER_GUIDE"
    case developerDocs   = "DEVELOPER_DOCS"
    case apiExamples     = "API_EXAMPLES"
    case keyboardRef     = "KEYBOARD_REF"
    case troubleshooting = "TROUBLESHOOTING"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .userGuide:       return "User Guide"
        case .developerDocs:   return "Developer Documentation"
        case .apiExamples:     return "API Integration Examples"
        case .keyboardRef:     return "Keyboard Shortcuts Reference"
        case .troubleshooting: return "Troubleshooting Guide"
        }
    }

    /// SF Symbol for this page type.
    public var sfSymbol: String {
        switch self {
        case .userGuide:       return "book"
        case .developerDocs:   return "chevron.left.forwardslash.chevron.right"
        case .apiExamples:     return "curlybraces"
        case .keyboardRef:     return "keyboard"
        case .troubleshooting: return "questionmark.circle"
        }
    }
}

/// Completion status of a documentation page.
public enum DocPageStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case complete   = "COMPLETE"
    case inProgress = "IN_PROGRESS"
    case planned    = "PLANNED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .complete:   return "Complete"
        case .inProgress: return "In Progress"
        case .planned:    return "Planned"
        }
    }
}

/// A documentation entry tracking completion.
public struct DocumentationEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var docType: DocPageType
    public var title: String
    public var status: DocPageStatus
    public var lastUpdatedDate: Date?
    public var wordCount: Int

    public init(
        id: UUID = UUID(),
        docType: DocPageType,
        title: String,
        status: DocPageStatus = .planned,
        lastUpdatedDate: Date? = nil,
        wordCount: Int = 0
    ) {
        self.id = id
        self.docType = docType
        self.title = title
        self.status = status
        self.lastUpdatedDate = lastUpdatedDate
        self.wordCount = wordCount
    }
}

// MARK: - 15.6 Release Preparation

/// Categories in the release checklist.
public enum ReleaseChecklistCategory: String, Sendable, Equatable, Hashable, CaseIterable {
    case appStoreMetadata = "APP_STORE_METADATA"
    case testFlight       = "TEST_FLIGHT"
    case codeSigning      = "CODE_SIGNING"
    case releaseNotes     = "RELEASE_NOTES"
    case homebrew         = "HOMEBREW"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .appStoreMetadata: return "App Store Metadata"
        case .testFlight:       return "TestFlight Beta"
        case .codeSigning:      return "Code Signing"
        case .releaseNotes:     return "Release Notes"
        case .homebrew:         return "Homebrew Cask"
        }
    }

    /// SF Symbol for this category.
    public var sfSymbol: String {
        switch self {
        case .appStoreMetadata: return "appstore"
        case .testFlight:       return "airplane"
        case .codeSigning:      return "signature"
        case .releaseNotes:     return "note.text"
        case .homebrew:         return "shippingbox"
        }
    }
}

/// A single item in the release checklist.
public struct ReleaseChecklistItem: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var category: ReleaseChecklistCategory
    public var description: String
    public var isCompleted: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        category: ReleaseChecklistCategory,
        description: String,
        isCompleted: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.category = category
        self.description = description
        self.isCompleted = isCompleted
        self.notes = notes
    }
}

/// Overall release status.
public enum ReleaseStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case notStarted      = "NOT_STARTED"
    case inProgress      = "IN_PROGRESS"
    case readyForReview  = "READY_FOR_REVIEW"
    case submitted       = "SUBMITTED"
    case approved        = "APPROVED"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .notStarted:     return "Not Started"
        case .inProgress:     return "In Progress"
        case .readyForReview: return "Ready for Review"
        case .submitted:      return "Submitted"
        case .approved:       return "Approved"
        }
    }

    /// SF Symbol for this status.
    public var sfSymbol: String {
        switch self {
        case .notStarted:     return "circle"
        case .inProgress:     return "arrow.clockwise.circle"
        case .readyForReview: return "checkmark.circle"
        case .submitted:      return "paperplane.fill"
        case .approved:       return "checkmark.seal.fill"
        }
    }
}
