// IntegrationTestingTests.swift
// DICOMStudioTests
//
// DICOM Studio — Tests for Integration Testing, Accessibility & Polish (Milestone 23)

import Testing
@testable import DICOMStudio
import Foundation

// MARK: - Model Tests

@Suite("Integration Testing Model Tests")
struct IntegrationTestingModelTests {

    // MARK: - IntegrationTestingTab

    @Test("IntegrationTestingTab has six cases")
    func test_integrationTestingTab_allCases_count() {
        #expect(IntegrationTestingTab.allCases.count == 6)
    }

    @Test("IntegrationTestingTab.e2eTesting displayName is 'E2E Testing'")
    func test_integrationTestingTab_e2eTesting_displayName() {
        #expect(IntegrationTestingTab.e2eTesting.displayName == "E2E Testing")
    }

    @Test("IntegrationTestingTab.unitTests displayName is 'Unit Tests'")
    func test_integrationTestingTab_unitTests_displayName() {
        #expect(IntegrationTestingTab.unitTests.displayName == "Unit Tests")
    }

    @Test("IntegrationTestingTab.accessibility displayName is 'Accessibility'")
    func test_integrationTestingTab_accessibility_displayName() {
        #expect(IntegrationTestingTab.accessibility.displayName == "Accessibility")
    }

    @Test("IntegrationTestingTab.performance displayName is 'Performance'")
    func test_integrationTestingTab_performance_displayName() {
        #expect(IntegrationTestingTab.performance.displayName == "Performance")
    }

    @Test("IntegrationTestingTab.uiPolish displayName is 'UI Polish'")
    func test_integrationTestingTab_uiPolish_displayName() {
        #expect(IntegrationTestingTab.uiPolish.displayName == "UI Polish")
    }

    @Test("IntegrationTestingTab.documentation displayName is 'Documentation'")
    func test_integrationTestingTab_documentation_displayName() {
        #expect(IntegrationTestingTab.documentation.displayName == "Documentation")
    }

    @Test("IntegrationTestingTab id equals rawValue")
    func test_integrationTestingTab_id_equalsRawValue() {
        for tab in IntegrationTestingTab.allCases {
            #expect(tab.id == tab.rawValue)
        }
    }

    @Test("IntegrationTestingTab symbolName is non-empty")
    func test_integrationTestingTab_symbolName_nonEmpty() {
        for tab in IntegrationTestingTab.allCases {
            #expect(!tab.symbolName.isEmpty)
        }
    }

    // MARK: - IntegrationTestToolCategory

    @Test("IntegrationTestToolCategory has nine cases")
    func test_toolCategory_allCases_count() {
        #expect(IntegrationTestToolCategory.allCases.count == 9)
    }

    @Test("IntegrationTestToolCategory total tool count is 42 (every Sources/dicom-* target)")
    func test_toolCategory_totalToolCount() {
        let total = IntegrationTestToolCategory.allCases.reduce(0) { $0 + $1.toolCount }
        #expect(total == 42)
    }

    @Test("IntegrationTestToolCategory.fileInspection has 4 tools")
    func test_toolCategory_fileInspection_toolCount() {
        #expect(IntegrationTestToolCategory.fileInspection.toolCount == 4)
    }

    @Test("IntegrationTestToolCategory.networking has 13 tools")
    func test_toolCategory_networking_toolCount() {
        #expect(IntegrationTestToolCategory.networking.toolCount == 13)
    }

    @Test("IntegrationTestToolCategory toolNames count matches toolCount")
    func test_toolCategory_toolNames_matchCount() {
        for cat in IntegrationTestToolCategory.allCases {
            #expect(cat.toolNames.count == cat.toolCount)
        }
    }

    @Test("IntegrationTestToolCategory displayName is non-empty")
    func test_toolCategory_displayName_nonEmpty() {
        for cat in IntegrationTestToolCategory.allCases {
            #expect(!cat.displayName.isEmpty)
        }
    }

    @Test("IntegrationTestToolCategory id equals rawValue")
    func test_toolCategory_id_equalsRawValue() {
        for cat in IntegrationTestToolCategory.allCases {
            #expect(cat.id == cat.rawValue)
        }
    }

    // MARK: - IntegrationTestStatus

    @Test("IntegrationTestStatus has five cases")
    func test_testStatus_allCases_count() {
        #expect(IntegrationTestStatus.allCases.count == 5)
    }

    @Test("IntegrationTestStatus symbolName is non-empty")
    func test_testStatus_symbolName_nonEmpty() {
        for status in IntegrationTestStatus.allCases {
            #expect(!status.symbolName.isEmpty)
        }
    }

    @Test("IntegrationTestStatus displayName is non-empty")
    func test_testStatus_displayName_nonEmpty() {
        for status in IntegrationTestStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }

    // MARK: - IntegrationTestCase

    @Test("IntegrationTestCase initialiser sets all fields")
    func test_testCase_init_setsAllFields() {
        let tc = IntegrationTestCase(
            toolName: "dicom-info",
            category: .fileInspection,
            testDescription: "Load and display metadata"
        )
        #expect(tc.toolName == "dicom-info")
        #expect(tc.category == .fileInspection)
        #expect(tc.testDescription == "Load and display metadata")
        #expect(tc.status == .pending)
        #expect(tc.errorMessage == nil)
        #expect(tc.durationSeconds == nil)
    }

    @Test("IntegrationTestCase durationDescription for nil is dash")
    func test_testCase_durationDescription_nil() {
        let tc = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d")
        #expect(tc.durationDescription == "—")
    }

    @Test("IntegrationTestCase durationDescription formats milliseconds")
    func test_testCase_durationDescription_ms() {
        let tc = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", durationSeconds: 0.5)
        #expect(tc.durationDescription == "500 ms")
    }

    @Test("IntegrationTestCase durationDescription formats seconds")
    func test_testCase_durationDescription_seconds() {
        let tc = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", durationSeconds: 2.35)
        #expect(tc.durationDescription == "2.35 s")
    }

    // MARK: - IntegrationTestErrorType

    @Test("IntegrationTestErrorType has five cases")
    func test_errorType_allCases_count() {
        #expect(IntegrationTestErrorType.allCases.count == 5)
    }

    @Test("IntegrationTestErrorType expectedBehaviour is non-empty")
    func test_errorType_expectedBehaviour_nonEmpty() {
        for err in IntegrationTestErrorType.allCases {
            #expect(!err.expectedBehaviour.isEmpty)
        }
    }

    // MARK: - IntegrationTestEdgeCase

    @Test("IntegrationTestEdgeCase has five cases")
    func test_edgeCase_allCases_count() {
        #expect(IntegrationTestEdgeCase.allCases.count == 5)
    }

    @Test("IntegrationTestEdgeCase displayName is non-empty")
    func test_edgeCase_displayName_nonEmpty() {
        for ec in IntegrationTestEdgeCase.allCases {
            #expect(!ec.displayName.isEmpty)
        }
    }

    // MARK: - IntegrationTestSuite

    @Test("IntegrationTestSuite empty suite has zero counts")
    func test_testSuite_empty_zeroCounts() {
        let suite = IntegrationTestSuite(category: .fileInspection)
        #expect(suite.passedCount == 0)
        #expect(suite.failedCount == 0)
        #expect(suite.totalCount == 0)
        #expect(suite.overallStatus == .pending)
    }

    @Test("IntegrationTestSuite summary format")
    func test_testSuite_summary_format() {
        let suite = IntegrationTestSuite(category: .fileInspection)
        #expect(suite.summary == "0/0 passed")
    }

    @Test("IntegrationTestSuite overallStatus passed when all passed")
    func test_testSuite_overallStatus_allPassed() {
        let tc = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", status: .passed)
        let suite = IntegrationTestSuite(category: .utilities, testCases: [tc])
        #expect(suite.overallStatus == .passed)
    }

    @Test("IntegrationTestSuite overallStatus failed when any failed")
    func test_testSuite_overallStatus_anyFailed() {
        let tc1 = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", status: .passed)
        let tc2 = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", status: .failed)
        let suite = IntegrationTestSuite(category: .utilities, testCases: [tc1, tc2])
        #expect(suite.overallStatus == .failed)
    }

    @Test("IntegrationTestSuite overallStatus running when any running")
    func test_testSuite_overallStatus_anyRunning() {
        let tc1 = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", status: .pending)
        let tc2 = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", status: .running)
        let suite = IntegrationTestSuite(category: .utilities, testCases: [tc1, tc2])
        #expect(suite.overallStatus == .running)
    }

    // MARK: - UnitTestTarget

    @Test("UnitTestTarget has ten cases")
    func test_unitTestTarget_allCases_count() {
        #expect(UnitTestTarget.allCases.count == 10)
    }

    @Test("UnitTestTarget minimumTestCount is positive")
    func test_unitTestTarget_minimumTestCount_positive() {
        for target in UnitTestTarget.allCases {
            #expect(target.minimumTestCount > 0)
        }
    }

    @Test("UnitTestTarget total minimum is 350+")
    func test_unitTestTarget_totalMinimum() {
        let total = UnitTestTarget.allCases.reduce(0) { $0 + $1.minimumTestCount }
        #expect(total >= 350)
    }

    // MARK: - UnitTestSuiteEntry

    @Test("UnitTestSuiteEntry default values are zero")
    func test_unitTestSuiteEntry_defaultValues() {
        let entry = UnitTestSuiteEntry(target: .commandBuilder)
        #expect(entry.testCount == 0)
        #expect(entry.passedCount == 0)
        #expect(entry.coveragePercent == 0.0)
    }

    @Test("UnitTestSuiteEntry meetsMinimumCount is false when zero")
    func test_unitTestSuiteEntry_meetsMinimumCount_false() {
        let entry = UnitTestSuiteEntry(target: .commandBuilder)
        #expect(entry.meetsMinimumCount == false)
    }

    @Test("UnitTestSuiteEntry meetsMinimumCount is true when sufficient")
    func test_unitTestSuiteEntry_meetsMinimumCount_true() {
        let entry = UnitTestSuiteEntry(target: .commandBuilder, testCount: 60)
        #expect(entry.meetsMinimumCount == true)
    }

    @Test("UnitTestSuiteEntry meetsCoverageTarget at 95%")
    func test_unitTestSuiteEntry_meetsCoverageTarget() {
        let entry = UnitTestSuiteEntry(target: .versionService, coveragePercent: 95.0)
        #expect(entry.meetsCoverageTarget == true)
    }

    @Test("UnitTestSuiteEntry summary format")
    func test_unitTestSuiteEntry_summary() {
        let entry = UnitTestSuiteEntry(target: .versionService, testCount: 20, passedCount: 18, coveragePercent: 90.5)
        #expect(entry.summary == "18/20 passed (90.5% coverage)")
    }

    // MARK: - IntegrationAccessibilityCheckCategory

    @Test("IntegrationAccessibilityCheckCategory has five cases")
    func test_a11yCategory_allCases_count() {
        #expect(IntegrationAccessibilityCheckCategory.allCases.count == 5)
    }

    @Test("IntegrationAccessibilityCheckCategory symbolName is non-empty")
    func test_a11yCategory_symbolName_nonEmpty() {
        for cat in IntegrationAccessibilityCheckCategory.allCases {
            #expect(!cat.symbolName.isEmpty)
        }
    }

    // MARK: - IntegrationAccessibilityCheckStatus

    @Test("IntegrationAccessibilityCheckStatus has four cases")
    func test_a11yStatus_allCases_count() {
        #expect(IntegrationAccessibilityCheckStatus.allCases.count == 4)
    }

    @Test("IntegrationAccessibilityCheckStatus symbolName is non-empty")
    func test_a11yStatus_symbolName_nonEmpty() {
        for status in IntegrationAccessibilityCheckStatus.allCases {
            #expect(!status.symbolName.isEmpty)
        }
    }

    // MARK: - IntegrationAccessibilityCheckItem

    @Test("IntegrationAccessibilityCheckItem default status is notChecked")
    func test_a11yCheckItem_defaultStatus() {
        let item = IntegrationAccessibilityCheckItem(category: .voiceOver, checkDescription: "Labels present")
        #expect(item.status == .notChecked)
        #expect(item.notes == nil)
    }

    // MARK: - IntegrationKeyboardShortcutEntry

    @Test("IntegrationKeyboardShortcutEntry default isVerified is false")
    func test_keyboardShortcut_defaultNotVerified() {
        let entry = IntegrationKeyboardShortcutEntry(shortcut: "⌘R", action: "Run tool")
        #expect(entry.isVerified == false)
    }

    // MARK: - AccessibilityAuditResult

    @Test("AccessibilityAuditResult empty audit has zero compliance")
    func test_auditResult_empty_zeroCompliance() {
        let audit = AccessibilityAuditResult(category: .voiceOver)
        #expect(audit.compliantCount == 0)
        #expect(audit.totalCount == 0)
        #expect(audit.compliancePercent == 0.0)
    }

    @Test("AccessibilityAuditResult compliance percentage calculation")
    func test_auditResult_compliancePercent() {
        let items = [
            IntegrationAccessibilityCheckItem(category: .voiceOver, checkDescription: "a", status: .compliant),
            IntegrationAccessibilityCheckItem(category: .voiceOver, checkDescription: "b", status: .nonCompliant),
        ]
        let audit = AccessibilityAuditResult(category: .voiceOver, items: items)
        #expect(audit.compliantCount == 1)
        #expect(audit.totalCount == 2)
        #expect(audit.compliancePercent == 50.0)
    }

    @Test("AccessibilityAuditResult summary format")
    func test_auditResult_summary() {
        let audit = AccessibilityAuditResult(category: .voiceOver)
        #expect(audit.summary == "0/0 compliant (0%)")
    }

    // MARK: - PerformanceMetricType

    @Test("PerformanceMetricType has seven cases")
    func test_perfMetric_allCases_count() {
        #expect(PerformanceMetricType.allCases.count == 7)
    }

    @Test("PerformanceMetricType targetDescription is non-empty")
    func test_perfMetric_targetDescription_nonEmpty() {
        for m in PerformanceMetricType.allCases {
            #expect(!m.targetDescription.isEmpty)
        }
    }

    @Test("PerformanceMetricType unit is non-empty")
    func test_perfMetric_unit_nonEmpty() {
        for m in PerformanceMetricType.allCases {
            #expect(!m.unit.isEmpty)
        }
    }

    // MARK: - PerformanceBenchmarkResult

    @Test("PerformanceBenchmarkResult formattedValue includes unit")
    func test_benchmarkResult_formattedValue() {
        let r = PerformanceBenchmarkResult(metric: .launchTime, measuredValue: 1.5, targetValue: 2.0, meetsTarget: true)
        #expect(r.formattedValue == "1.5 s")
    }

    @Test("PerformanceBenchmarkResult formattedTarget includes unit")
    func test_benchmarkResult_formattedTarget() {
        let r = PerformanceBenchmarkResult(metric: .memoryUsage, measuredValue: 120.0, targetValue: 150.0, meetsTarget: true)
        #expect(r.formattedTarget == "150.0 MB")
    }

    // MARK: - ProfilingInstrument

    @Test("ProfilingInstrument has four cases")
    func test_profilingInstrument_allCases_count() {
        #expect(ProfilingInstrument.allCases.count == 4)
    }

    @Test("ProfilingInstrument symbolName is non-empty")
    func test_profilingInstrument_symbolName_nonEmpty() {
        for inst in ProfilingInstrument.allCases {
            #expect(!inst.symbolName.isEmpty)
        }
    }

    // MARK: - ProfilingSession

    @Test("ProfilingSession default is not completed")
    func test_profilingSession_default() {
        let session = ProfilingSession(instrument: .leaks)
        #expect(session.isCompleted == false)
        #expect(session.findings == nil)
    }

    // MARK: - UIPolishCategory

    @Test("UIPolishCategory has eleven cases")
    func test_uiPolishCategory_allCases_count() {
        #expect(UIPolishCategory.allCases.count == 11)
    }

    @Test("UIPolishCategory symbolName is non-empty")
    func test_uiPolishCategory_symbolName_nonEmpty() {
        for cat in UIPolishCategory.allCases {
            #expect(!cat.symbolName.isEmpty)
        }
    }

    // MARK: - UIPolishCheckItem

    @Test("UIPolishCheckItem default isVerified is false")
    func test_uiPolishCheckItem_default() {
        let item = UIPolishCheckItem(category: .spacing, checkDescription: "Consistent spacing")
        #expect(item.isVerified == false)
        #expect(item.notes == nil)
    }

    // MARK: - DocumentationSection

    @Test("DocumentationSection has three cases")
    func test_docSection_allCases_count() {
        #expect(DocumentationSection.allCases.count == 3)
    }

    @Test("DocumentationSection symbolName is non-empty")
    func test_docSection_symbolName_nonEmpty() {
        for s in DocumentationSection.allCases {
            #expect(!s.symbolName.isEmpty)
        }
    }

    // MARK: - DocumentationEntryStatus

    @Test("DocumentationEntryStatus has four cases")
    func test_docEntryStatus_allCases_count() {
        #expect(DocumentationEntryStatus.allCases.count == 4)
    }

    // MARK: - IntegrationDocumentationEntry

    @Test("IntegrationDocumentationEntry default status is notStarted")
    func test_docEntry_default() {
        let entry = IntegrationDocumentationEntry(section: .userGuide, title: "Getting Started")
        #expect(entry.status == .notStarted)
        #expect(entry.isComplete == false)
    }

    @Test("IntegrationDocumentationEntry isComplete when published")
    func test_docEntry_isComplete_published() {
        let entry = IntegrationDocumentationEntry(section: .userGuide, title: "Guide", status: .published)
        #expect(entry.isComplete == true)
    }

    // MARK: - IntegrationTestingState

    @Test("IntegrationTestingState default has empty collections")
    func test_state_default_empty() {
        let state = IntegrationTestingState()
        #expect(state.selectedTab == .e2eTesting)
        #expect(state.testSuites.isEmpty)
        #expect(state.unitTestEntries.isEmpty)
        #expect(state.accessibilityAudits.isEmpty)
        #expect(state.keyboardShortcuts.isEmpty)
        #expect(state.benchmarkResults.isEmpty)
        #expect(state.profilingSessions.isEmpty)
        #expect(state.polishChecks.isEmpty)
        #expect(state.documentationEntries.isEmpty)
    }

    @Test("IntegrationTestingState totalE2ETests returns zero when empty")
    func test_state_totalE2ETests_zero() {
        let state = IntegrationTestingState()
        #expect(state.totalE2ETests == 0)
    }

    @Test("IntegrationTestingState passedE2ETests returns zero when empty")
    func test_state_passedE2ETests_zero() {
        let state = IntegrationTestingState()
        #expect(state.passedE2ETests == 0)
    }

    @Test("IntegrationTestingState overallCompliancePercent zero when empty")
    func test_state_overallCompliancePercent_zero() {
        let state = IntegrationTestingState()
        #expect(state.overallCompliancePercent == 0.0)
    }

    @Test("IntegrationTestingState benchmarksMeetingTargets zero when empty")
    func test_state_benchmarksMeetingTargets_zero() {
        let state = IntegrationTestingState()
        #expect(state.benchmarksMeetingTargets == 0)
    }

    @Test("IntegrationTestingState verifiedPolishChecks zero when empty")
    func test_state_verifiedPolishChecks_zero() {
        let state = IntegrationTestingState()
        #expect(state.verifiedPolishChecks == 0)
    }

    @Test("IntegrationTestingState publishedDocEntries zero when empty")
    func test_state_publishedDocEntries_zero() {
        let state = IntegrationTestingState()
        #expect(state.publishedDocEntries == 0)
    }
}

// MARK: - Helpers Tests

@Suite("Integration Testing Helpers Tests")
struct IntegrationTestingHelpersTests {

    // MARK: - E2ETestHelpers

    @Test("E2ETestHelpers totalToolCount is 42")
    func test_e2eHelpers_totalToolCount() {
        #expect(E2ETestHelpers.totalToolCount == 42)
    }

    @Test("E2ETestHelpers generateTestCases creates correct count for fileInspection")
    func test_e2eHelpers_generateTestCases_fileInspection() {
        let cases = E2ETestHelpers.generateTestCases(for: .fileInspection)
        #expect(cases.count == 4)
        #expect(cases.allSatisfy { $0.category == .fileInspection })
    }

    @Test("E2ETestHelpers generateTestCases creates correct count for networking")
    func test_e2eHelpers_generateTestCases_networking() {
        let cases = E2ETestHelpers.generateTestCases(for: .networking)
        #expect(cases.count == 13)
    }

    @Test("E2ETestHelpers generateTestCases all have pending status")
    func test_e2eHelpers_generateTestCases_allPending() {
        for cat in IntegrationTestToolCategory.allCases {
            let cases = E2ETestHelpers.generateTestCases(for: cat)
            #expect(cases.allSatisfy { $0.status == .pending })
        }
    }

    @Test("E2ETestHelpers statusSummary for empty is zero")
    func test_e2eHelpers_statusSummary_empty() {
        let summary = E2ETestHelpers.statusSummary(for: [])
        #expect(summary.contains("0"))
    }

    @Test("E2ETestHelpers categoryPassRate for empty suite is zero")
    func test_e2eHelpers_categoryPassRate_empty() {
        let suite = IntegrationTestSuite(category: .utilities)
        #expect(E2ETestHelpers.categoryPassRate(for: suite) == 0.0)
    }

    @Test("E2ETestHelpers categoryPassRate all passed is 100")
    func test_e2eHelpers_categoryPassRate_allPassed() {
        let tc = IntegrationTestCase(toolName: "t", category: .utilities, testDescription: "d", status: .passed)
        let suite = IntegrationTestSuite(category: .utilities, testCases: [tc])
        #expect(E2ETestHelpers.categoryPassRate(for: suite) == 100.0)
    }

    // MARK: - UnitTestCoverageHelpers

    @Test("UnitTestCoverageHelpers targetCoveragePercent is 95.0")
    func test_unitTestHelpers_targetCoverage() {
        #expect(UnitTestCoverageHelpers.targetCoveragePercent == 95.0)
    }

    @Test("UnitTestCoverageHelpers targetTotalTests is 400")
    func test_unitTestHelpers_targetTotal() {
        #expect(UnitTestCoverageHelpers.targetTotalTests == 400)
    }

    @Test("UnitTestCoverageHelpers meetsOverallTarget false when empty")
    func test_unitTestHelpers_meetsTarget_empty() {
        #expect(UnitTestCoverageHelpers.meetsOverallTarget(entries: []) == false)
    }

    @Test("UnitTestCoverageHelpers overallCoveragePercent zero when empty")
    func test_unitTestHelpers_overallCoverage_empty() {
        #expect(UnitTestCoverageHelpers.overallCoveragePercent(entries: []) == 0.0)
    }

    @Test("UnitTestCoverageHelpers coverageSummary for empty")
    func test_unitTestHelpers_coverageSummary_empty() {
        let summary = UnitTestCoverageHelpers.coverageSummary(entries: [])
        #expect(summary.contains("0 tests"))
    }

    // MARK: - AccessibilityAuditHelpers

    @Test("AccessibilityAuditHelpers generateVoiceOverChecks returns items")
    func test_a11yHelpers_generateVoiceOverChecks() {
        let checks = AccessibilityAuditHelpers.generateVoiceOverChecks()
        #expect(!checks.isEmpty)
        #expect(checks.allSatisfy { $0.category == .voiceOver })
    }

    @Test("AccessibilityAuditHelpers generateKeyboardShortcuts returns items")
    func test_a11yHelpers_generateKeyboardShortcuts() {
        let shortcuts = AccessibilityAuditHelpers.generateKeyboardShortcuts()
        #expect(!shortcuts.isEmpty)
    }

    @Test("AccessibilityAuditHelpers overallComplianceScore for empty")
    func test_a11yHelpers_overallComplianceScore_empty() {
        let score = AccessibilityAuditHelpers.overallComplianceScore(audits: [])
        #expect(score.contains("0"))
    }

    @Test("AccessibilityAuditHelpers meetsWCAGAA normal text 4.5:1")
    func test_a11yHelpers_meetsWCAGAA_normalText() {
        #expect(AccessibilityAuditHelpers.meetsWCAGAA(ratio: 4.5, isLargeText: false) == true)
        #expect(AccessibilityAuditHelpers.meetsWCAGAA(ratio: 4.4, isLargeText: false) == false)
    }

    @Test("AccessibilityAuditHelpers meetsWCAGAA large text 3:1")
    func test_a11yHelpers_meetsWCAGAA_largeText() {
        #expect(AccessibilityAuditHelpers.meetsWCAGAA(ratio: 3.0, isLargeText: true) == true)
        #expect(AccessibilityAuditHelpers.meetsWCAGAA(ratio: 2.9, isLargeText: true) == false)
    }

    // MARK: - PerformanceBenchmarkHelpers

    @Test("PerformanceBenchmarkHelpers defaultTargets returns seven benchmarks")
    func test_perfHelpers_defaultTargets_count() {
        let targets = PerformanceBenchmarkHelpers.defaultTargets()
        #expect(targets.count == 7)
    }

    @Test("PerformanceBenchmarkHelpers formattedMetric includes unit")
    func test_perfHelpers_formattedMetric() {
        let formatted = PerformanceBenchmarkHelpers.formattedMetric(value: 1.5, metric: .launchTime)
        #expect(formatted.contains("s"))
    }

    @Test("PerformanceBenchmarkHelpers meetsAllTargets false when empty")
    func test_perfHelpers_meetsAllTargets_empty() {
        #expect(PerformanceBenchmarkHelpers.meetsAllTargets(results: []) == false)
    }

    @Test("PerformanceBenchmarkHelpers performanceSummary for empty")
    func test_perfHelpers_performanceSummary_empty() {
        let summary = PerformanceBenchmarkHelpers.performanceSummary(results: [])
        #expect(summary.contains("0"))
    }

    // MARK: - UIPolishCheckHelpers

    @Test("UIPolishCheckHelpers generatePolishChecklist returns items")
    func test_polishHelpers_generateChecklist() {
        let checks = UIPolishCheckHelpers.generatePolishChecklist()
        #expect(!checks.isEmpty)
    }

    @Test("UIPolishCheckHelpers completionPercent zero when empty")
    func test_polishHelpers_completionPercent_empty() {
        #expect(UIPolishCheckHelpers.completionPercent(checks: []) == 0.0)
    }

    @Test("UIPolishCheckHelpers polishSummary for empty")
    func test_polishHelpers_polishSummary_empty() {
        let summary = UIPolishCheckHelpers.polishSummary(checks: [])
        #expect(summary.contains("0"))
    }

    // MARK: - DocumentationProgressHelpers

    @Test("DocumentationProgressHelpers generateInAppHelpEntries returns items")
    func test_docHelpers_inAppHelp() {
        let entries = DocumentationProgressHelpers.generateInAppHelpEntries()
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.section == .inAppHelp })
    }

    @Test("DocumentationProgressHelpers generateUserGuideEntries returns items")
    func test_docHelpers_userGuide() {
        let entries = DocumentationProgressHelpers.generateUserGuideEntries()
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.section == .userGuide })
    }

    @Test("DocumentationProgressHelpers generateReleaseNotesEntries returns items")
    func test_docHelpers_releaseNotes() {
        let entries = DocumentationProgressHelpers.generateReleaseNotesEntries()
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.section == .releaseNotes })
    }

    @Test("DocumentationProgressHelpers overallProgress for empty")
    func test_docHelpers_overallProgress_empty() {
        let progress = DocumentationProgressHelpers.overallProgress(entries: [])
        #expect(progress.contains("0"))
    }

    @Test("DocumentationProgressHelpers completionPercent zero when empty")
    func test_docHelpers_completionPercent_empty() {
        #expect(DocumentationProgressHelpers.completionPercent(entries: []) == 0.0)
    }
}

// MARK: - Service Tests

@Suite("Integration Testing Service Tests")
struct IntegrationTestingServiceTests {

    @Test("Service getState returns default state")
    func test_service_getState_default() {
        let service = IntegrationTestingService()
        let state = service.getState()
        #expect(state.selectedTab == .e2eTesting)
        #expect(state.testSuites.isEmpty)
    }

    @Test("Service selectTab updates selected tab")
    func test_service_selectTab() {
        let service = IntegrationTestingService()
        service.selectTab(.accessibility)
        let state = service.getState()
        #expect(state.selectedTab == .accessibility)
    }

    @Test("Service initializeTestSuites creates 9 suites")
    func test_service_initializeTestSuites() {
        let service = IntegrationTestingService()
        service.initializeTestSuites()
        let suites = service.getTestSuites()
        #expect(suites.count == 9)
    }

    @Test("Service initializeTestSuites populates test cases")
    func test_service_initializeTestSuites_hasTestCases() {
        let service = IntegrationTestingService()
        service.initializeTestSuites()
        let suites = service.getTestSuites()
        let totalTests = suites.reduce(0) { $0 + $1.totalCount }
        #expect(totalTests == 42)
    }

    @Test("Service runAllTests sets all to running")
    func test_service_runAllTests() {
        let service = IntegrationTestingService()
        service.initializeTestSuites()
        service.runAllTests()
        let suites = service.getTestSuites()
        for suite in suites {
            for tc in suite.testCases {
                #expect(tc.status == .running)
            }
        }
    }

    @Test("Service resetAllTests sets all to pending")
    func test_service_resetAllTests() {
        let service = IntegrationTestingService()
        service.initializeTestSuites()
        service.runAllTests()
        service.resetAllTests()
        let suites = service.getTestSuites()
        for suite in suites {
            for tc in suite.testCases {
                #expect(tc.status == .pending)
            }
        }
    }

    @Test("Service updateTestStatus updates specific test")
    func test_service_updateTestStatus() {
        let service = IntegrationTestingService()
        service.initializeTestSuites()
        service.updateTestStatus(suiteIndex: 0, testIndex: 0, status: .passed, errorMessage: nil, duration: 0.5)
        let suites = service.getTestSuites()
        #expect(suites[0].testCases[0].status == .passed)
        #expect(suites[0].testCases[0].durationSeconds == 0.5)
    }

    @Test("Service initializeUnitTestEntries creates 10 entries")
    func test_service_initializeUnitTestEntries() {
        let service = IntegrationTestingService()
        service.initializeUnitTestEntries()
        let entries = service.getUnitTestEntries()
        #expect(entries.count == 10)
    }

    @Test("Service updateUnitTestEntry updates target entry")
    func test_service_updateUnitTestEntry() {
        let service = IntegrationTestingService()
        service.initializeUnitTestEntries()
        service.updateUnitTestEntry(target: .commandBuilder, testCount: 55, passedCount: 50, coverage: 96.0)
        let entries = service.getUnitTestEntries()
        let builder = entries.first { $0.target == .commandBuilder }
        #expect(builder?.testCount == 55)
        #expect(builder?.passedCount == 50)
        #expect(builder?.coveragePercent == 96.0)
    }

    @Test("Service initializeAccessibilityAudits creates audits")
    func test_service_initializeAccessibilityAudits() {
        let service = IntegrationTestingService()
        service.initializeAccessibilityAudits()
        let audits = service.getAccessibilityAudits()
        #expect(!audits.isEmpty)
    }

    @Test("Service initializeBenchmarks creates 7 benchmarks")
    func test_service_initializeBenchmarks() {
        let service = IntegrationTestingService()
        service.initializeBenchmarks()
        let results = service.getBenchmarkResults()
        #expect(results.count == 7)
    }

    @Test("Service initializePolishChecks creates checks")
    func test_service_initializePolishChecks() {
        let service = IntegrationTestingService()
        service.initializePolishChecks()
        let checks = service.getPolishChecks()
        #expect(!checks.isEmpty)
    }

    @Test("Service verifyPolishCheck marks check as verified")
    func test_service_verifyPolishCheck() {
        let service = IntegrationTestingService()
        service.initializePolishChecks()
        service.verifyPolishCheck(at: 0, notes: "Looks good")
        let checks = service.getPolishChecks()
        #expect(checks[0].isVerified == true)
        #expect(checks[0].notes == "Looks good")
    }

    @Test("Service resetPolishCheck marks check as unverified")
    func test_service_resetPolishCheck() {
        let service = IntegrationTestingService()
        service.initializePolishChecks()
        service.verifyPolishCheck(at: 0, notes: "test")
        service.resetPolishCheck(at: 0)
        let checks = service.getPolishChecks()
        #expect(checks[0].isVerified == false)
    }

    @Test("Service initializeDocumentationEntries creates entries")
    func test_service_initializeDocumentationEntries() {
        let service = IntegrationTestingService()
        service.initializeDocumentationEntries()
        let entries = service.getDocumentationEntries()
        #expect(!entries.isEmpty)
    }

    @Test("Service updateDocumentationStatus changes status")
    func test_service_updateDocumentationStatus() {
        let service = IntegrationTestingService()
        service.initializeDocumentationEntries()
        service.updateDocumentationStatus(at: 0, status: .published)
        let entries = service.getDocumentationEntries()
        #expect(entries[0].status == .published)
    }

    @Test("Service initializeProfilingSessions creates 4 sessions")
    func test_service_initializeProfilingSessions() {
        let service = IntegrationTestingService()
        service.initializeProfilingSessions()
        let sessions = service.getState().profilingSessions
        #expect(sessions.count == 4)
    }
}

// MARK: - ViewModel Tests

@Suite("Integration Testing ViewModel Tests")
struct IntegrationTestingViewModelTests {

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializes with default state")
    func test_viewModel_init_defaultState() {
        let vm = IntegrationTestingViewModel()
        #expect(vm.selectedTab == .e2eTesting)
        #expect(vm.testSuites.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel selectTab updates tab")
    func test_viewModel_selectTab() {
        let vm = IntegrationTestingViewModel()
        vm.selectTab(.performance)
        #expect(vm.selectedTab == .performance)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializeTestSuites populates suites")
    func test_viewModel_initializeTestSuites() {
        let vm = IntegrationTestingViewModel()
        vm.initializeTestSuites()
        #expect(vm.testSuites.count == 9)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel runAllTests sets running status")
    func test_viewModel_runAllTests() {
        let vm = IntegrationTestingViewModel()
        vm.initializeTestSuites()
        vm.runAllTests()
        for suite in vm.testSuites {
            for tc in suite.testCases {
                #expect(tc.status == .running)
            }
        }
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel resetAllTests sets pending status")
    func test_viewModel_resetAllTests() {
        let vm = IntegrationTestingViewModel()
        vm.initializeTestSuites()
        vm.runAllTests()
        vm.resetAllTests()
        for suite in vm.testSuites {
            for tc in suite.testCases {
                #expect(tc.status == .pending)
            }
        }
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializeUnitTestEntries populates entries")
    func test_viewModel_initializeUnitTestEntries() {
        let vm = IntegrationTestingViewModel()
        vm.initializeUnitTestEntries()
        #expect(vm.unitTestEntries.count == 10)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializeAccessibilityAudits populates audits")
    func test_viewModel_initializeAccessibilityAudits() {
        let vm = IntegrationTestingViewModel()
        vm.initializeAccessibilityAudits()
        #expect(!vm.accessibilityAudits.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializeKeyboardShortcuts populates shortcuts")
    func test_viewModel_initializeKeyboardShortcuts() {
        let vm = IntegrationTestingViewModel()
        vm.initializeKeyboardShortcuts()
        #expect(!vm.keyboardShortcuts.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializeBenchmarks populates results")
    func test_viewModel_initializeBenchmarks() {
        let vm = IntegrationTestingViewModel()
        vm.initializeBenchmarks()
        #expect(vm.benchmarkResults.count == 7)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializePolishChecks populates checks")
    func test_viewModel_initializePolishChecks() {
        let vm = IntegrationTestingViewModel()
        vm.initializePolishChecks()
        #expect(!vm.polishChecks.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel initializeDocumentationEntries populates entries")
    func test_viewModel_initializeDocumentationEntries() {
        let vm = IntegrationTestingViewModel()
        vm.initializeDocumentationEntries()
        #expect(!vm.documentationEntries.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel e2eTestSummary returns string")
    func test_viewModel_e2eTestSummary() {
        let vm = IntegrationTestingViewModel()
        #expect(!vm.e2eTestSummary.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel unitTestCoverageSummary returns string")
    func test_viewModel_unitTestCoverageSummary() {
        let vm = IntegrationTestingViewModel()
        #expect(!vm.unitTestCoverageSummary.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel performanceSummary returns string")
    func test_viewModel_performanceSummary() {
        let vm = IntegrationTestingViewModel()
        #expect(!vm.performanceSummary.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel polishCompletionSummary returns string")
    func test_viewModel_polishCompletionSummary() {
        let vm = IntegrationTestingViewModel()
        #expect(!vm.polishCompletionSummary.isEmpty)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("ViewModel documentationProgressSummary returns string")
    func test_viewModel_documentationProgressSummary() {
        let vm = IntegrationTestingViewModel()
        #expect(!vm.documentationProgressSummary.isEmpty)
    }
}

// MARK: - NavigationService Tests

@Suite("Integration Testing Navigation Tests")
struct IntegrationTestingNavigationTests {

    @Test("NavigationDestination includes integrationTesting")
    func test_navigationDestination_includesIntegrationTesting() {
        let destinations = NavigationDestination.allCases
        #expect(destinations.contains(.integrationTesting))
    }

    @Test("NavigationDestination.integrationTesting has systemImage")
    func test_navigationDestination_integrationTesting_systemImage() {
        #expect(!NavigationDestination.integrationTesting.systemImage.isEmpty)
    }

    @Test("NavigationDestination.integrationTesting has accessibilityLabel")
    func test_navigationDestination_integrationTesting_accessibilityLabel() {
        #expect(!NavigationDestination.integrationTesting.accessibilityLabel.isEmpty)
    }

    @Test("NavigationDestination.integrationTesting rawValue is 'Integration Testing'")
    func test_navigationDestination_integrationTesting_rawValue() {
        #expect(NavigationDestination.integrationTesting.rawValue == "Integration Testing")
    }
}
