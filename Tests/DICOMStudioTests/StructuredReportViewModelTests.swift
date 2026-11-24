// StructuredReportViewModelTests.swift
// DICOMStudioTests
//
// Tests for StructuredReportViewModel (Milestone 7)

import Testing
@testable import DICOMStudio
import Foundation

// MARK: - StructuredReportViewModel Tests

@Suite("StructuredReportViewModel Tests")
struct StructuredReportViewModelTests {

    // MARK: - Helpers

    private func makeDocument(type: SRDocumentType = .basicText, title: String = "Test") -> SRDocument {
        let titleConcept = CodedConcept(
            codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: title
        )
        let child = SRContentItem(valueType: .text, textValue: "Sample finding")
        let root = SRContentItem(
            valueType: .container,
            conceptName: titleConcept,
            continuityOfContent: .separate,
            children: [child]
        )
        return SRDocument(
            documentType: type,
            title: titleConcept,
            rootContentItem: root
        )
    }

    // MARK: - Initial State

    @Test("Initial state defaults")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testInitialState() {
        let vm = StructuredReportViewModel()
        #expect(vm.viewerMode == .tree)
        #expect(!vm.isViewerActive)
        #expect(vm.searchQuery.isEmpty)
        #expect(vm.searchResults.isEmpty)
        #expect(vm.documents.isEmpty)
        #expect(vm.selectedDocumentIndex == nil)
        #expect(vm.builderMode == .template)
        #expect(vm.builderDocumentType == .basicText)
        #expect(vm.selectedTemplate == nil)
        #expect(!vm.isBuilderActive)
        #expect(vm.terminologyQuery.isEmpty)
        #expect(vm.terminologyScope == .all)
        #expect(vm.cadFindings.isEmpty)
        #expect(!vm.isCADOverlayActive)
        #expect(vm.cadMinConfidence == 0.0)
        #expect(vm.cadTypeFilter == nil)
    }

    // MARK: - Document Actions

    @Test("loadDocument adds and activates viewer")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLoadDocument() {
        let vm = StructuredReportViewModel()
        let doc = makeDocument()
        vm.loadDocument(doc)
        #expect(vm.documents.count == 1)
        #expect(vm.selectedDocumentIndex == 0)
        #expect(vm.isViewerActive)
        #expect(!vm.flattenedItems.isEmpty)
    }

    @Test("selectDocument changes selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectDocument() {
        let vm = StructuredReportViewModel()
        vm.loadDocument(makeDocument(title: "A"))
        vm.loadDocument(makeDocument(title: "B"))
        vm.selectDocument(at: 0)
        #expect(vm.selectedDocumentIndex == 0)
    }

    @Test("selectDocument out of range does nothing")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectDocumentOutOfRange() {
        let vm = StructuredReportViewModel()
        vm.loadDocument(makeDocument())
        vm.selectDocument(at: 5)
        #expect(vm.selectedDocumentIndex == 0)
    }

    @Test("removeDocument removes and clears")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRemoveDocument() {
        let vm = StructuredReportViewModel()
        vm.loadDocument(makeDocument())
        vm.removeDocument(at: 0)
        #expect(vm.documents.isEmpty)
    }

    // MARK: - Viewer Actions

    @Test("toggleNodeExpansion toggles a node")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testToggleNodeExpansion() {
        let vm = StructuredReportViewModel()
        let doc = makeDocument()
        vm.loadDocument(doc)
        let rootID = vm.documents[0].rootContentItem.id
        let initialCount = vm.flattenedItems.count
        vm.toggleNodeExpansion(rootID)
        // After collapsing root, should show fewer items
        #expect(vm.flattenedItems.count < initialCount)
    }

    @Test("expandAll expands all nodes")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testExpandAll() {
        let vm = StructuredReportViewModel()
        let doc = makeDocument()
        vm.loadDocument(doc)
        vm.collapseAll()
        let collapsedCount = vm.flattenedItems.count
        vm.expandAll()
        #expect(vm.flattenedItems.count >= collapsedCount)
    }

    @Test("collapseAll collapses all nodes")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCollapseAll() {
        let vm = StructuredReportViewModel()
        vm.loadDocument(makeDocument())
        vm.collapseAll()
        #expect(vm.flattenedItems.count == 1) // Only root
    }

    @Test("performSearch finds results")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testPerformSearch() {
        let vm = StructuredReportViewModel()
        vm.loadDocument(makeDocument())
        vm.searchQuery = "Sample"
        vm.performSearch()
        #expect(!vm.searchResults.isEmpty)
    }

    @Test("performSearch with no match returns empty")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testPerformSearchNoMatch() {
        let vm = StructuredReportViewModel()
        vm.loadDocument(makeDocument())
        vm.searchQuery = "XYZ_NOT_FOUND"
        vm.performSearch()
        #expect(vm.searchResults.isEmpty)
    }

    @Test("clearSearch resets query and results")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClearSearch() {
        let vm = StructuredReportViewModel()
        vm.loadDocument(makeDocument())
        vm.searchQuery = "test"
        vm.performSearch()
        vm.clearSearch()
        #expect(vm.searchQuery.isEmpty)
        #expect(vm.searchResults.isEmpty)
    }

    @Test("performSearch without document returns empty")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testPerformSearchNoDocument() {
        let vm = StructuredReportViewModel()
        vm.searchQuery = "test"
        vm.performSearch()
        #expect(vm.searchResults.isEmpty)
    }

    // MARK: - Builder Actions

    @Test("createDocument creates basicText document")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCreateBasicTextDocument() {
        let vm = StructuredReportViewModel()
        vm.builderDocumentType = .basicText
        vm.selectedTemplate = .radiologyReport
        let doc = vm.createDocument()
        #expect(doc != nil)
        #expect(doc?.documentType == .basicText)
        #expect(doc?.rootContentItem.children.count == 3)
    }

    @Test("createDocument creates KOS document")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCreateKOSDocument() {
        let vm = StructuredReportViewModel()
        vm.builderDocumentType = .keyObjectSelection
        let doc = vm.createDocument()
        #expect(doc != nil)
        #expect(doc?.documentType == .keyObjectSelection)
    }

    @Test("createDocument creates measurement report")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCreateMeasurementReport() {
        let vm = StructuredReportViewModel()
        vm.builderDocumentType = .measurementReport
        let doc = vm.createDocument()
        #expect(doc != nil)
        #expect(doc?.documentType == .measurementReport)
    }

    @Test("createDocument creates generic document for other types")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCreateGenericDocument() {
        let vm = StructuredReportViewModel()
        vm.builderDocumentType = .comprehensive3D
        let doc = vm.createDocument()
        #expect(doc != nil)
        #expect(doc?.documentType == .comprehensive3D)
    }

    @Test("validateBuilder returns errors for empty document")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testValidateBuilder() {
        let vm = StructuredReportViewModel()
        vm.builderDocumentType = .comprehensive
        let errors = vm.validateBuilder()
        #expect(!errors.isEmpty)
        #expect(vm.validationSuccessMessage == nil)
    }

    @Test("validateBuilder and validateCurrentReport populate validationChecks and validationSuccessMessage when valid")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testValidateBuilderAndCurrentReportSuccess() {
        let vm = StructuredReportViewModel()
        vm.builderDocumentType = .basicText
        vm.selectedTemplate = .radiologyReport
        // Empty sections in template mode should flag missing section content
        let emptyErrors = vm.validateBuilder()
        #expect(!emptyErrors.isEmpty)
        #expect(vm.validationSuccessMessage == nil)

        // Populate section text and re-validate
        vm.sectionTexts["Findings"] = "Clear bilateral lung fields."
        let validErrors = vm.validateBuilder()
        #expect(validErrors.isEmpty)
        #expect(vm.validationSuccessMessage?.contains("Document is valid") == true)
        #expect(vm.validationChecks.count >= 3)
        #expect(vm.validationChecks.allSatisfy { $0.passed })
    }

    // MARK: - Terminology Actions

    @Test("searchTerminology finds results")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSearchTerminology() {
        let vm = StructuredReportViewModel()
        vm.terminologyQuery = "Lung"
        vm.searchTerminology()
        #expect(!vm.terminologyResults.isEmpty)
    }

    @Test("searchTerminology with scope filters results")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSearchTerminologyScoped() {
        let vm = StructuredReportViewModel()
        vm.terminologyQuery = "Lung"
        vm.terminologyScope = .snomedCT
        vm.searchTerminology()
        for entry in vm.terminologyResults {
            #expect(entry.concept.codingSchemeDesignator == "SCT")
        }
    }

    @Test("recordTermUsage adds to recent list")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRecordTermUsage() {
        let vm = StructuredReportViewModel()
        let entry = TerminologyEntry(
            concept: CodedConcept(
                codeValue: "1", codingSchemeDesignator: "SCT", codeMeaning: "Test"
            )
        )
        vm.recordTermUsage(entry)
        #expect(vm.recentTerms.count == 1)
    }

    @Test("toggleTermFavorite toggles favorite")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testToggleTermFavorite() {
        let vm = StructuredReportViewModel()
        let concept = CodedConcept(
            codeValue: "1", codingSchemeDesignator: "SCT", codeMeaning: "Test"
        )
        let entry = TerminologyEntry(concept: concept)
        vm.toggleTermFavorite(entry)
        #expect(vm.isTermFavorite(concept))
        #expect(vm.favoriteTerms.count == 1)

        vm.toggleTermFavorite(entry)
        #expect(!vm.isTermFavorite(concept))
    }

    // MARK: - CAD Actions

    @Test("loadCADFindings sets findings and activates overlay")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLoadCADFindings() {
        let vm = StructuredReportViewModel()
        let findings = [
            CADFinding(findingType: .mass, confidence: 0.9),
            CADFinding(findingType: .nodule, confidence: 0.7),
        ]
        vm.loadCADFindings(findings)
        #expect(vm.cadFindings.count == 2)
        #expect(vm.isCADOverlayActive)
    }

    @Test("selectCADFinding sets selection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSelectCADFinding() {
        let vm = StructuredReportViewModel()
        let finding = CADFinding(findingType: .mass, confidence: 0.8)
        vm.loadCADFindings([finding])
        vm.selectCADFinding(finding.id)
        #expect(vm.selectedCADFindingID == finding.id)
    }

    @Test("updateCADFindingStatus changes status")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testUpdateCADFindingStatus() {
        let vm = StructuredReportViewModel()
        let finding = CADFinding(findingType: .mass, confidence: 0.8)
        vm.loadCADFindings([finding])
        vm.updateCADFindingStatus(finding.id, status: .accepted)
        #expect(vm.cadFindings[0].status == .accepted)
    }

    @Test("filteredCADFindings respects type filter")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilteredCADFindingsType() {
        let vm = StructuredReportViewModel()
        vm.loadCADFindings([
            CADFinding(findingType: .mass, confidence: 0.9),
            CADFinding(findingType: .nodule, confidence: 0.7),
            CADFinding(findingType: .mass, confidence: 0.6),
        ])
        vm.cadTypeFilter = .mass
        #expect(vm.filteredCADFindings.count == 2)
    }

    @Test("filteredCADFindings respects confidence filter")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFilteredCADFindingsConfidence() {
        let vm = StructuredReportViewModel()
        vm.loadCADFindings([
            CADFinding(findingType: .mass, confidence: 0.9),
            CADFinding(findingType: .nodule, confidence: 0.3),
        ])
        vm.cadMinConfidence = 0.5
        #expect(vm.filteredCADFindings.count == 1)
    }

    @Test("cadStatistics returns correct stats")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCADStatistics() {
        let vm = StructuredReportViewModel()
        vm.loadCADFindings([
            CADFinding(findingType: .mass, confidence: 0.9),
            CADFinding(findingType: .nodule, confidence: 0.7),
        ])
        let stats = vm.cadStatistics
        #expect(stats["total"] == 2)
    }

    // MARK: - Dependency Injection

    @Test("Custom service injection")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCustomService() {
        let service = StructuredReportService()
        let vm = StructuredReportViewModel(reportService: service)
        #expect(vm.reportService === service)
    }
}
