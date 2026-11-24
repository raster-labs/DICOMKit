// StructuredReportViewModel.swift
// DICOMStudio
//
// DICOM Studio — ViewModel for Structured Reporting Studio
// NEMA-verified: 2026a, checked 2026-10-05 — the only standard data was the document title it built: retired (121070, DCM, "Findings") with the document type's display name as meaning; now SRBuilderHelpers.documentTitle(for:template:) (PS3.16 2026a CID 7000 / 7021 / 7010, TID 4000 / 4100 row 1); the rest is view state over StructuredReportService

import Foundation
import Observation
import DICOMCore

/// A single validation check item displayed in the Structured Reports Validation panel.
public struct SRValidationCheckItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let passed: Bool
    public let detail: String

    public init(id: String, title: String, passed: Bool, detail: String) {
        self.id = id
        self.title = title
        self.passed = passed
        self.detail = detail
    }
}

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

    /// Selected clinical template preset (from `DICOMCore.SRClinicalCatalog.clinicalTemplatePresets`).
    public var selectedTemplate: SRTemplate?

    /// Selected registered PS3.16 TID template descriptor (from `DICOMCore.TemplateRegistry.shared.allTemplateDescriptors`).
    public var selectedRegisteredTemplate: DICOMCore.SRRegisteredTemplateDescriptor?

    /// Active template section names for the currently selected clinical preset or registered PS3.16 TID template.
    public var activeTemplateSections: [String] {
        if let reg = selectedRegisteredTemplate {
            return reg.sectionNames
        }
        if let tpl = selectedTemplate {
            return tpl.sections
        }
        return []
    }

    /// Active template display name for UI headers.
    public var activeTemplateDisplayName: String? {
        if let reg = selectedRegisteredTemplate {
            return reg.formattedDisplayName
        }
        return selectedTemplate?.displayName
    }

    /// Whether the builder panel is visible.
    public var isBuilderActive: Bool = false

    /// Whether the report validation panel is visible.
    public var isValidationActive: Bool = false

    /// Builder validation errors.
    public var validationErrors: [String] = []

    /// Non-fatal validation warnings (e.g. optional PS3.16 template rows or best practices).
    public var validationWarnings: [String] = []

    /// Positive confirmation message set when report validation succeeds.
    public var validationSuccessMessage: String?

    /// Structured checklist of validation checks from the most recent validation run.
    public var validationChecks: [SRValidationCheckItem] = []

    /// Optional PS3.16 TID template override for the Report Validation tab.
    public var validationTargetTemplate: DICOMCore.SRRegisteredTemplateDescriptor?

    /// Clinical section text keyed by template section heading (e.g. "Findings", "Impression").
    public var sectionTexts: [String: String] = [:]

    /// Free-form clinical findings / diagnosis narrative when building without a template.
    public var freeFormText: String = ""

    /// Key Object Selection purpose and description for KOS building.
    public var keyObjectPurpose: KeyObjectPurpose = .documentation
    public var keyObjectDescription: String = "Key Object Selection"

    /// Quantitative measurements added in the standalone SR Builder.
    public var builderMeasurements: [TrackedMeasurement] = []

    /// Patient & study metadata for standalone SR authoring.
    public var patientName: String = ""
    public var patientID: String = ""
    public var studyInstanceUID: String = ""
    public var observerName: String = ""
    public var isComplete: Bool = true
    public var isVerified: Bool = false
    public var verifyingObserverName: String = ""
    public var verifyingOrganization: String = "DICOMStudio"

    /// Whether an image/study is currently loaded in the Image Viewer.
    /// Defaults to `true` for standalone unit tests; `MainViewModel` keeps this synchronized
    /// with `imageViewerViewModel.dicomFile != nil` so report creation is restricted when no image is open.
    public var hasActiveViewerImage: Bool = true

    /// Active patient, study, equipment, and image-evidence context synchronized from the Image Viewer.
    public var activeStudyContext: SRStudyContext?

    /// Optional callback invoked when the user publishes an SR document into an imported study.
    public var onPublishToStudy: ((SRDocument) -> String?)?

    /// Optional navigation callbacks to jump to the Image Viewer or Study Library when the viewer is empty.
    public var onNavigateToViewer: (() -> Void)?
    public var onNavigateToLibrary: (() -> Void)?

    /// Informational or error status message shown in the Structured Reports screen.
    public var statusMessage: String?

    /// Synchronizes the SR Builder's patient/study metadata and image-availability state with the Image Viewer.
    public func syncWithViewerStudyContext(_ context: SRStudyContext?) {
        hasActiveViewerImage = (context != nil)
        guard let context else {
            activeStudyContext = nil
            return
        }
        let studyChanged = activeStudyContext?.studyInstanceUID != context.studyInstanceUID
        activeStudyContext = context

        if let pName = context.patientName, !pName.isEmpty,
           patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || studyChanged {
            patientName = pName
        }
        if let pID = context.patientID, !pID.isEmpty,
           patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || studyChanged {
            patientID = pID
        }
        if let sUID = context.studyInstanceUID, !sUID.isEmpty,
           studyInstanceUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || studyChanged {
            studyInstanceUID = sUID
        }
    }

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
        guard hasActiveViewerImage else {
            let msg = "Open an image in the Viewer to create a Structured Report."
            validationErrors = [msg]
            validationSuccessMessage = nil
            statusMessage = msg
            return nil
        }

        // Backfill any blank Patient Name, Patient ID, or Study Instance UID from the active study context
        if patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let ctxName = activeStudyContext?.patientName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ctxName.isEmpty {
            patientName = ctxName
        }
        if patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let ctxID = activeStudyContext?.patientID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ctxID.isEmpty {
            patientID = ctxID
        }
        if studyInstanceUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let ctxStudy = activeStudyContext?.studyInstanceUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ctxStudy.isEmpty {
            studyInstanceUID = ctxStudy
        }

        let usesClinicalPreset = selectedTemplate != nil
            && selectedRegisteredTemplate == nil
            && builderDocumentType != .keyObjectSelection
            && builderDocumentType != .measurementReport

        let usesRegisteredTID = selectedRegisteredTemplate != nil
            && builderDocumentType != .keyObjectSelection
            && builderDocumentType != .measurementReport

        let title = SRBuilderHelpers.documentTitle(
            for: builderDocumentType,
            template: usesClinicalPreset ? selectedTemplate : nil,
            registeredTemplate: usesRegisteredTID ? selectedRegisteredTemplate : nil
        )

        var rootItem: SRContentItem
        var resolvedTemplateID: String?

        if let registered = selectedRegisteredTemplate, usesRegisteredTID {
            rootItem = SRBuilderHelpers.buildRegisteredTemplateSR(
                template: registered,
                sectionTexts: sectionTexts
            )
            resolvedTemplateID = registered.identifier.templateID
        } else if let template = selectedTemplate, usesClinicalPreset {
            rootItem = SRBuilderHelpers.buildBasicTextSR(
                template: template,
                sectionTexts: sectionTexts
            )
            resolvedTemplateID = template.corePreset.templateIdentifier?.templateID
        } else if builderDocumentType == .keyObjectSelection {
            rootItem = SRBuilderHelpers.buildKeyObjectSelection(
                purpose: keyObjectPurpose,
                description: keyObjectDescription
            )
            resolvedTemplateID = builderDocumentType.coreDocumentType.defaultRootTemplateIdentifier?.templateID
        } else if builderDocumentType == .measurementReport {
            rootItem = SRBuilderHelpers.buildMeasurementReport(
                measurements: builderMeasurements
            )
            resolvedTemplateID = DICOMCore.TemplateIdentifier.measurementReport.templateID
        } else {
            var children: [SRContentItem] = []
            let trimmedFreeForm = freeFormText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedFreeForm.isEmpty {
                let findingsConcept = SRBuilderHelpers.sectionHeading(for: "Findings")
                let textChild = SRBuilderHelpers.textItem(conceptName: findingsConcept, text: trimmedFreeForm)
                children.append(SRBuilderHelpers.containerItem(
                    conceptName: findingsConcept,
                    continuity: .separate,
                    children: [textChild]
                ))
            }
            rootItem = SRContentItem(
                valueType: .container,
                conceptName: title,
                continuityOfContent: .separate,
                children: children
            )
            resolvedTemplateID = builderDocumentType.coreDocumentType.defaultRootTemplateIdentifier?.templateID
        }

        let trimmedObserver = observerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedObserver.isEmpty && builderDocumentType != .keyObjectSelection {
            let obsItem = SRBuilderHelpers.personNameItem(
                conceptName: CodedConcept(coreConcept: DICOMCore.SRClinicalCatalog.personObserverNameConcept),
                name: trimmedObserver
            )
            rootItem = rootItem.withChildren([obsItem] + rootItem.children)
        }

        let stamp = SRSerializationBridge.currentDICOMTimestamp()
        let document = SRDocument(
            documentType: builderDocumentType,
            title: title,
            patientName: patientName,
            patientID: patientID,
            studyInstanceUID: studyInstanceUID,
            contentDate: stamp.date,
            contentTime: stamp.time,
            rootContentItem: rootItem,
            isComplete: isComplete,
            isVerified: isVerified,
            templateIdentifier: resolvedTemplateID
        )

        var errors = SRBuilderHelpers.validateDocument(document)
        if (usesClinicalPreset || usesRegisteredTID) && !activeTemplateSections.isEmpty {
            let hasAnySectionText = activeTemplateSections.contains { sec in
                !(sectionTexts[sec]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            if !hasAnySectionText && trimmedObserver.isEmpty {
                errors.append(
                    "Enter content in at least one report section (\(activeTemplateSections.joined(separator: ", ")))"
                )
            }
        }
        if isVerified && builderDocumentType != .keyObjectSelection {
            if verifyingObserverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Verifying Observer Name is required when Verified is enabled")
            }
            if verifyingOrganization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Verifying Organization is required when Verified is enabled")
            }
        }
        validationErrors = errors
        if !errors.isEmpty {
            validationSuccessMessage = nil
        }
        return document
    }

    /// Creates a document from the builder settings and loads it into the viewer when valid.
    @discardableResult
    public func createAndLoadDocument() -> SRDocument? {
        guard let doc = createDocument() else { return nil }
        guard validationErrors.isEmpty else {
            statusMessage = "Validation failed: \(validationErrors.first ?? "Check report fields")"
            return nil
        }
        isBuilderActive = false
        isValidationActive = false
        loadDocument(doc)
        statusMessage = "Created \(doc.title.codeMeaning)"
        return doc
    }

    /// Imports a DICOM Part 10 SR `.dcm` file from disk and loads it into the viewer.
    @discardableResult
    public func importDICOMFile(from url: URL) throws -> SRDocument {
        let doc = try SRSerializationBridge.readDocument(from: url)
        isBuilderActive = false
        isValidationActive = false
        loadDocument(doc)
        statusMessage = "Imported \(doc.title.codeMeaning)"
        return doc
    }

    /// Imports DICOM Part 10 SR `Data` and loads it into the viewer.
    @discardableResult
    public func importDICOMData(_ data: Data) throws -> SRDocument {
        let doc = try SRSerializationBridge.readDocument(from: data)
        isBuilderActive = false
        isValidationActive = false
        loadDocument(doc)
        statusMessage = "Imported \(doc.title.codeMeaning)"
        return doc
    }

    /// Serializes the currently selected SR document to DICOM Part 10 `.dcm` `Data`.
    public func exportSelectedDocumentData() throws -> Data {
        guard let index = selectedDocumentIndex, index >= 0, index < documents.count else {
            throw NSError(
                domain: "DICOMStudio.SR",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Select a Structured Report document to export."]
            )
        }
        return try SRSerializationBridge.serialize(
            documents[index],
            verifyingObserverName: verifyingObserverName,
            verifyingOrganization: verifyingOrganization,
            studyContext: activeStudyContext
        )
    }

    /// Publishes the selected document into the currently active study (when available).
    public func publishSelectedDocumentToStudy() {
        guard let index = selectedDocumentIndex, index >= 0, index < documents.count else {
            statusMessage = "Select a Structured Report document first."
            return
        }
        if let callback = onPublishToStudy {
            statusMessage = callback(documents[index]) ?? "Saved Structured Report to study (Series 9002 — SR)."
        } else {
            statusMessage = "Open an imported study in the Viewer to publish directly into Series 9002 (SR), or use Export .dcm."
        }
    }

    /// Validates the current builder settings and updates the UI validation banner and checklist.
    @discardableResult
    public func validateBuilder() -> [String] {
        if selectedTemplate == nil
            && selectedRegisteredTemplate == nil
            && builderMode == .template
            && builderDocumentType != .keyObjectSelection
            && builderDocumentType != .measurementReport {
            let hasAnyText = !sectionTexts.values.allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasAnyText {
                selectedTemplate = .radiologyReport
            }
        }
        guard let doc = createDocument() else {
            let err = validationErrors.isEmpty ? ["Failed to create document"] : validationErrors
            validationErrors = err
            validationSuccessMessage = nil
            return err
        }
        return evaluateDocumentValidation(doc, initialErrors: validationErrors)
    }

    /// Validates either the currently selected loaded SR document (when available) or the current Builder draft.
    @discardableResult
    public func validateCurrentReport() -> [String] {
        if let idx = selectedDocumentIndex, idx >= 0, idx < documents.count, !isBuilderActive {
            let doc = documents[idx]
            let treeErrors = SRBuilderHelpers.validateDocument(doc)
            return evaluateDocumentValidation(doc, initialErrors: treeErrors)
        }
        return validateBuilder()
    }

    /// Runs full SR tree, PS3.3 Annex A.35 IOD Value-Type, PS3.3 Level 3 Part 10, and PS3.16 TID template validation.
    @discardableResult
    public func evaluateDocumentValidation(
        _ doc: SRDocument,
        initialErrors: [String] = []
    ) -> [String] {
        var errors = initialErrors
        let conformance = SRSerializationBridge.validateConformance(
            of: doc,
            verifyingObserverName: verifyingObserverName,
            verifyingOrganization: verifyingOrganization,
            targetTemplate: validationTargetTemplate?.identifier
                ?? selectedRegisteredTemplate?.identifier,
            studyContext: activeStudyContext
        )

        for iodErr in conformance.iodValueTypeErrors where !errors.contains(iodErr) {
            errors.append(iodErr)
        }
        if errors.isEmpty {
            for p10Err in conformance.part10Errors where !errors.contains(p10Err) {
                errors.append(p10Err)
            }
        }

        var warnings = conformance.part10Warnings
        if let tplResult = conformance.templateResult {
            for violation in tplResult.violations {
                let desc = "[\(tplResult.templateIdentifier)] \(violation.message)"
                if !warnings.contains(desc) {
                    warnings.append(desc)
                }
            }
        }

        let itemCount = SRTreeHelpers.totalItemCount(doc.rootContentItem)
        let allowedVTs = doc.documentType.coreDocumentType.allowedValueTypes
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")

        var checks: [SRValidationCheckItem] = [
            SRValidationCheckItem(
                id: "tree",
                title: "SR Content Tree & Root CONTAINER",
                passed: initialErrors.isEmpty,
                detail: initialErrors.isEmpty
                    ? "Root CONTAINER '\(doc.title.codeMeaning)' (\(doc.title.codingSchemeDesignator):\(doc.title.codeValue)) with \(itemCount) item(s)."
                    : initialErrors.joined(separator: " • ")
            ),
            SRValidationCheckItem(
                id: "iod_vt",
                title: "PS3.3 Annex A.35 IOD Allowed Value Types (\(doc.documentType.displayName))",
                passed: conformance.iodValueTypeErrors.isEmpty,
                detail: conformance.iodValueTypeErrors.isEmpty
                    ? "All content item value types permitted by \(doc.documentType.sopClassUID) (Allowed: \(allowedVTs))."
                    : conformance.iodValueTypeErrors.joined(separator: " • ")
            ),
            SRValidationCheckItem(
                id: "part10",
                title: "DICOM Part 10 & PS3.3 Level 3 IOD Conformance",
                passed: conformance.part10Errors.isEmpty,
                detail: conformance.part10Errors.isEmpty
                    ? "SOP Class \(doc.documentType.sopClassUID) (Modality \(doc.documentType.coreDocumentType.modality)) passed Level 3 Type 1/1C/2/2C validation."
                    : conformance.part10Errors.joined(separator: " • ")
            )
        ]

        if let tplResult = conformance.templateResult {
            let tidName = DICOMCore.TemplateRegistry.shared
                .descriptor(for: tplResult.templateIdentifier)?
                .formattedDisplayName ?? "\(tplResult.templateIdentifier)"
            checks.append(
                SRValidationCheckItem(
                    id: "ps316_tid",
                    title: "PS3.16 Template Conformance (\(tidName))",
                    passed: tplResult.errors.isEmpty,
                    detail: tplResult.violations.isEmpty
                        ? "Compliant with \(tidName)."
                        : "\(tplResult.errors.count) mandatory row notice(s), \(tplResult.warnings.count) warning(s)."
                )
            )
        }

        validationChecks = checks
        validationWarnings = warnings
        validationErrors = errors

        if errors.isEmpty {
            let tidBadge = doc.templateIdentifier.map { " • TID \($0)" } ?? ""
            let msg = "Document is valid — \(doc.documentType.displayName) (\(doc.title.codeMeaning)\(tidBadge), \(itemCount) item(s)) conforms to DICOM PS3.3 / PS3.16."
            validationSuccessMessage = msg
            statusMessage = msg
        } else {
            validationSuccessMessage = nil
            statusMessage = "Validation found \(errors.count) issue(s)."
        }
        return errors
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
