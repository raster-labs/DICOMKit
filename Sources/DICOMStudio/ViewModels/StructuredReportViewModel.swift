// StructuredReportViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for Structured Reporting Studio
// NEMA-verified: 2026a, checked 2026-10-05 — the only standard data was the document title it built: retired (121070, DCM, "Findings") with the document type's display name as meaning; now SRBuilderHelpers.documentTitle(for:template:) (PS3.16 2026a CID 7000 / 7021 / 7010, TID 4000 / 4100 row 1); the rest is view state over StructuredReportService

import Foundation
import Observation

/// ViewModel for Structured Reporting Studio, managing SR document viewing,
/// building, terminology browsing, and CAD findings visualization.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class StructuredReportViewModel {

    // MARK: - Viewer State

    /// Current viewer mode.
    public var viewerMode: SRViewerMode = .tree

    /// Whether the viewer is active.
    public var isViewerActive: Bool = false

    /// Search query for SR content.
    public var searchQuery: String = ""

    /// Search result item IDs.
    public var searchResults: [UUID] = []

    /// Currently selected content item ID in the tree.
    public var selectedContentItemID: UUID?

    /// Flattened tree items for display.
    public var flattenedItems: [(item: SRContentItem, depth: Int)] = []

    // MARK: - Builder State

    /// Current builder mode.
    public var builderMode: SRBuilderMode = .template

    /// Selected document type for building.
    public var builderDocumentType: SRDocumentType = .basicText

    /// Selected template.
    public var selectedTemplate: SRTemplate?

    /// Whether the builder panel is visible.
    public var isBuilderActive: Bool = false

    /// Builder validation errors.
    public var validationErrors: [String] = []

    // MARK: - Terminology State

    /// Terminology search query.
    public var terminologyQuery: String = ""

    /// Terminology search scope.
    public var terminologyScope: TerminologySearchScope = .all

    /// Terminology search results.
    public var terminologyResults: [TerminologyEntry] = []

    /// Recently used terms.
    public var recentTerms: [TerminologyEntry] = []

    /// Favorite terms.
    public var favoriteTerms: [TerminologyEntry] = []

    /// Whether terminology browser is visible.
    public var isTerminologyBrowserActive: Bool = false

    // MARK: - CAD State

    /// CAD findings list.
    public var cadFindings: [CADFinding] = []

    /// Selected CAD finding ID.
    public var selectedCADFindingID: UUID?

    /// Whether CAD overlay is visible.
    public var isCADOverlayActive: Bool = false

    /// Minimum confidence filter for CAD display.
    public var cadMinConfidence: Double = 0.0

    /// CAD finding type filter (nil = show all).
    public var cadTypeFilter: CADFindingType?

    // MARK: - Document State

    /// Loaded SR documents.
    public var documents: [SRDocument] = []

    /// Selected document index.
    public var selectedDocumentIndex: Int?

    // MARK: - Service

    /// The underlying structured report service.
    public let reportService: StructuredReportService

    // MARK: - Initialization

    /// Creates a new SR ViewModel.
    ///
    /// - Parameter reportService: The service for SR operations (injectable for testing).
    public init(
        reportService: StructuredReportService = StructuredReportService()
    ) {
        self.reportService = reportService
    }

    // MARK: - Document Actions

    /// Loads a document and activates the viewer.
    public func loadDocument(_ document: SRDocument) {
        reportService.addDocument(document)
        documents = reportService.documents
        let index = documents.count - 1
        reportService.selectDocument(at: index)
        selectedDocumentIndex = index
        isViewerActive = true
        refreshFlattenedTree()
    }

    /// Selects a document by index.
    public func selectDocument(at index: Int) {
        guard index >= 0, index < documents.count else { return }
        reportService.selectDocument(at: index)
        selectedDocumentIndex = index
        refreshFlattenedTree()
    }

    /// Removes a document by index.
    public func removeDocument(at index: Int) {
        reportService.removeDocument(at: index)
        documents = reportService.documents
        selectedDocumentIndex = reportService.selectedDocumentIndex
        refreshFlattenedTree()
    }

    // MARK: - Viewer Actions

    /// Toggles expansion of a tree node.
    public func toggleNodeExpansion(_ itemID: UUID) {
        guard let index = selectedDocumentIndex, index < documents.count else { return }
        let doc = documents[index]
        let newRoot = SRTreeHelpers.toggleExpansion(doc.rootContentItem, itemID: itemID)
        let updatedDoc = doc.withRootContentItem(newRoot)
        reportService.replaceDocument(at: index, with: updatedDoc)
        documents = reportService.documents
        refreshFlattenedTree()
    }

    /// Expands all nodes in the current document.
    public func expandAll() {
        guard let index = selectedDocumentIndex, index < documents.count else { return }
        let doc = documents[index]
        let newRoot = SRTreeHelpers.expandAll(doc.rootContentItem)
        let updatedDoc = doc.withRootContentItem(newRoot)
        reportService.replaceDocument(at: index, with: updatedDoc)
        documents = reportService.documents
        refreshFlattenedTree()
    }

    /// Collapses all nodes in the current document.
    public func collapseAll() {
        guard let index = selectedDocumentIndex, index < documents.count else { return }
        let doc = documents[index]
        let newRoot = SRTreeHelpers.collapseAll(doc.rootContentItem)
        let updatedDoc = doc.withRootContentItem(newRoot)
        reportService.replaceDocument(at: index, with: updatedDoc)
        documents = reportService.documents
        refreshFlattenedTree()
    }

    /// Performs a search in the current document.
    public func performSearch() {
        guard let index = selectedDocumentIndex, index < documents.count else {
            searchResults = []
            return
        }
        reportService.setSearchQuery(searchQuery)
        searchResults = reportService.searchResults
    }

    /// Clears the search.
    public func clearSearch() {
        searchQuery = ""
        searchResults = []
        reportService.setSearchQuery("")
    }

    // MARK: - Builder Actions

    /// Creates a new document from the current builder settings.
    public func createDocument() -> SRDocument? {
        let title = SRBuilderHelpers.documentTitle(
            for: builderDocumentType,
            template: builderDocumentType == .basicText ? selectedTemplate : nil
        )

        var rootItem: SRContentItem

        if let template = selectedTemplate, builderDocumentType == .basicText {
            rootItem = SRBuilderHelpers.buildBasicTextSR(template: template)
        } else if builderDocumentType == .keyObjectSelection {
            rootItem = SRBuilderHelpers.buildKeyObjectSelection(
                purpose: .documentation,
                description: "Key Object Selection"
            )
        } else if builderDocumentType == .measurementReport {
            rootItem = SRBuilderHelpers.buildMeasurementReport()
        } else {
            rootItem = SRContentItem(
                valueType: .container,
                conceptName: title,
                continuityOfContent: .separate,
                children: []
            )
        }

        let document = SRDocument(
            documentType: builderDocumentType,
            title: title,
            rootContentItem: rootItem
        )

        validationErrors = SRBuilderHelpers.validateDocument(document)
        return document
    }

    /// Validates the current builder settings.
    public func validateBuilder() -> [String] {
        if let doc = createDocument() {
            return SRBuilderHelpers.validateDocument(doc)
        }
        return ["Failed to create document"]
    }

    // MARK: - Terminology Actions

    /// Searches terminology with the current query and scope.
    public func searchTerminology() {
        terminologyResults = TerminologyHelpers.search(
            query: terminologyQuery,
            scope: terminologyScope
        )
    }

    /// Records a term as recently used.
    public func recordTermUsage(_ entry: TerminologyEntry) {
        reportService.recordRecentTerm(entry)
        recentTerms = reportService.recentTerms
    }

    /// Toggles a term as favorite.
    public func toggleTermFavorite(_ entry: TerminologyEntry) {
        reportService.toggleFavorite(entry)
        favoriteTerms = reportService.favoriteTerms
    }

    /// Checks if a concept is in favorites.
    public func isTermFavorite(_ concept: CodedConcept) -> Bool {
        reportService.isFavorite(concept)
    }

    // MARK: - CAD Actions

    /// Loads CAD findings.
    public func loadCADFindings(_ findings: [CADFinding]) {
        reportService.setCADFindings(findings)
        cadFindings = findings
        isCADOverlayActive = true
    }

    /// Selects a CAD finding.
    public func selectCADFinding(_ id: UUID) {
        reportService.selectCADFinding(id)
        selectedCADFindingID = id
    }

    /// Updates the status of a CAD finding (accept/reject).
    public func updateCADFindingStatus(_ id: UUID, status: CADFindingStatus) {
        reportService.updateCADFindingStatus(id, status: status)
        cadFindings = reportService.cadFindings
    }

    /// Returns filtered CAD findings based on current filters.
    public var filteredCADFindings: [CADFinding] {
        var filtered = cadFindings

        if let typeFilter = cadTypeFilter {
            filtered = CADVisualizationHelpers.filterByType(filtered, type: typeFilter)
        }

        if cadMinConfidence > 0.0 {
            filtered = CADVisualizationHelpers.filterByMinConfidence(
                filtered, minConfidence: cadMinConfidence
            )
        }

        return CADVisualizationHelpers.sortByConfidence(filtered)
    }

    /// Returns CAD finding statistics.
    public var cadStatistics: [String: Int] {
        CADVisualizationHelpers.findingStatistics(cadFindings)
    }

    // MARK: - Private Helpers

    /// Refreshes the flattened tree from the selected document.
    private func refreshFlattenedTree() {
        guard let index = selectedDocumentIndex, index < documents.count else {
            flattenedItems = []
            return
        }
        flattenedItems = SRTreeHelpers.flattenTree(documents[index].rootContentItem)
    }
}
