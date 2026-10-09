// StructuredReportService.swift
// DICOMStudio
//
// DICOM Studio — Service for SR document state management
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (thread-safe document, terminology, CAD and builder state)

import Foundation

/// Thread-safe service managing structured report state including documents,
/// terminology browsing, CAD findings, and builder state.
public final class StructuredReportService: @unchecked Sendable {

    /// Lock for thread-safe access.
    private let lock = NSLock()

    // MARK: - Document State

    /// Currently loaded SR documents.
    private var _documents: [SRDocument] = []

    /// Currently selected document index (nil if none).
    private var _selectedDocumentIndex: Int?

    /// Current search query for SR content.
    private var _searchQuery: String = ""

    /// Current search result IDs.
    private var _searchResults: [UUID] = []

    // MARK: - Terminology State

    /// Recently used terminology entries.
    private var _recentTerms: [TerminologyEntry] = []

    /// Favorite terminology entries.
    private var _favoriteTerms: [TerminologyEntry] = []

    /// Maximum recent terms to keep.
    private let maxRecentTerms = 50

    // MARK: - CAD State

    /// Current CAD findings.
    private var _cadFindings: [CADFinding] = []

    /// Selected CAD finding ID.
    private var _selectedCADFindingID: UUID?

    // MARK: - Builder State

    /// Current builder document type.
    private var _builderDocumentType: SRDocumentType = .basicText

    /// Current builder template.
    private var _builderTemplate: SRTemplate?

    /// Current builder mode.
    private var _builderMode: SRBuilderMode = .template

    // MARK: - Initialization

    /// Creates a new structured report service.
    public init() {}

    // MARK: - Document Management

    /// Returns all loaded documents.
    public var documents: [SRDocument] {
        lock.lock()
        defer { lock.unlock() }
        return _documents
    }

    /// Returns the currently selected document, or nil.
    public var selectedDocument: SRDocument? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = _selectedDocumentIndex,
              index >= 0, index < _documents.count else { return nil }
        return _documents[index]
    }

    /// Returns the selected document index.
    public var selectedDocumentIndex: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _selectedDocumentIndex
    }

    /// Adds a document to the list.
    public func addDocument(_ document: SRDocument) {
        lock.lock()
        defer { lock.unlock() }
        _documents.append(document)
    }

    /// Removes a document at the given index.
    public func removeDocument(at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < _documents.count else { return }
        _documents.remove(at: index)
        if let selected = _selectedDocumentIndex {
            if selected == index {
                _selectedDocumentIndex = nil
            } else if selected > index {
                _selectedDocumentIndex = selected - 1
            }
        }
    }

    /// Selects a document at the given index.
    public func selectDocument(at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        if index >= 0, index < _documents.count {
            _selectedDocumentIndex = index
        }
    }

    /// Clears selection.
    public func clearSelection() {
        lock.lock()
        defer { lock.unlock() }
        _selectedDocumentIndex = nil
    }

    /// Replaces the document at the given index.
    public func replaceDocument(at index: Int, with document: SRDocument) {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < _documents.count else { return }
        _documents[index] = document
    }

    /// Returns the document count.
    public var documentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _documents.count
    }

    // MARK: - Search

    /// Sets the search query and updates results.
    public func setSearchQuery(_ query: String) {
        lock.lock()
        defer { lock.unlock() }
        _searchQuery = query
        if let index = _selectedDocumentIndex, index < _documents.count {
            _searchResults = SRTreeHelpers.searchTree(
                _documents[index].rootContentItem,
                query: query
            )
        } else {
            _searchResults = []
        }
    }

    /// Returns the current search query.
    public var searchQuery: String {
        lock.lock()
        defer { lock.unlock() }
        return _searchQuery
    }

    /// Returns the current search result IDs.
    public var searchResults: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return _searchResults
    }

    // MARK: - Terminology Management

    /// Records a term as recently used.
    public func recordRecentTerm(_ entry: TerminologyEntry) {
        lock.lock()
        defer { lock.unlock() }
        _recentTerms.removeAll { $0.concept == entry.concept }
        _recentTerms.insert(entry, at: 0)
        if _recentTerms.count > maxRecentTerms {
            _recentTerms = Array(_recentTerms.prefix(maxRecentTerms))
        }
    }

    /// Returns recently used terms.
    public var recentTerms: [TerminologyEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _recentTerms
    }

    /// Toggles a term as favorite.
    public func toggleFavorite(_ entry: TerminologyEntry) {
        lock.lock()
        defer { lock.unlock() }
        if let index = _favoriteTerms.firstIndex(where: { $0.concept == entry.concept }) {
            _favoriteTerms.remove(at: index)
        } else {
            _favoriteTerms.append(entry.withFavorite(true))
        }
    }

    /// Returns favorite terms.
    public var favoriteTerms: [TerminologyEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _favoriteTerms
    }

    /// Checks if a concept is a favorite.
    public func isFavorite(_ concept: CodedConcept) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _favoriteTerms.contains { $0.concept == concept }
    }

    // MARK: - CAD Findings Management

    /// Sets the CAD findings.
    public func setCADFindings(_ findings: [CADFinding]) {
        lock.lock()
        defer { lock.unlock() }
        _cadFindings = findings
        _selectedCADFindingID = nil
    }

    /// Returns CAD findings.
    public var cadFindings: [CADFinding] {
        lock.lock()
        defer { lock.unlock() }
        return _cadFindings
    }

    /// Selects a CAD finding.
    public func selectCADFinding(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        _selectedCADFindingID = id
    }

    /// Returns the selected CAD finding ID.
    public var selectedCADFindingID: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return _selectedCADFindingID
    }

    /// Returns the selected CAD finding.
    public var selectedCADFinding: CADFinding? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = _selectedCADFindingID else { return nil }
        return _cadFindings.first { $0.id == id }
    }

    /// Updates the status of a CAD finding.
    public func updateCADFindingStatus(_ id: UUID, status: CADFindingStatus) {
        lock.lock()
        defer { lock.unlock() }
        if let index = _cadFindings.firstIndex(where: { $0.id == id }) {
            _cadFindings[index] = _cadFindings[index].withStatus(status)
        }
    }

    // MARK: - Builder State

    /// Returns the current builder document type.
    public var builderDocumentType: SRDocumentType {
        lock.lock()
        defer { lock.unlock() }
        return _builderDocumentType
    }

    /// Sets the builder document type.
    public func setBuilderDocumentType(_ type: SRDocumentType) {
        lock.lock()
        defer { lock.unlock() }
        _builderDocumentType = type
    }

    /// Returns the current builder template.
    public var builderTemplate: SRTemplate? {
        lock.lock()
        defer { lock.unlock() }
        return _builderTemplate
    }

    /// Sets the builder template.
    public func setBuilderTemplate(_ template: SRTemplate?) {
        lock.lock()
        defer { lock.unlock() }
        _builderTemplate = template
    }

    /// Returns the current builder mode.
    public var builderMode: SRBuilderMode {
        lock.lock()
        defer { lock.unlock() }
        return _builderMode
    }

    /// Sets the builder mode.
    public func setBuilderMode(_ mode: SRBuilderMode) {
        lock.lock()
        defer { lock.unlock() }
        _builderMode = mode
    }
}
