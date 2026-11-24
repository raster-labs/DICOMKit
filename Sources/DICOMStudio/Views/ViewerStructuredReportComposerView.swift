// ViewerStructuredReportComposerView.swift
// DICOMStudio
//
// DICOM Studio — Clinical Structured Report authoring sheet for the Study Viewer.
// NEMA-verified: 2026a, checked 2026-11-19 — carries UI layout and bindings over ClinicalSRDraft (verified in ImageViewerViewModel+StructuredReports.swift); saves SR documents into dedicated Series 9002 (Modality = "SR", PS3.3 C.17.1) separate from Softcopy Presentation States in Series 9001 (Modality = "PR", PS3.3 C.11.9)

#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import DICOMCore
import DICOMKit
import DICOMPrintKit

/// FileDocument wrapper for exporting serialized DICOM Part 10 SR `.dcm` files via SwiftUI's `fileExporter`.
struct DICOMBinaryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Modal composer in the Study Viewer for authoring clinical DICOM Structured Reports (`SR`)
/// with History, Findings, Diagnosis/Impression, Recommendations, Measurements, Verification,
/// and optional cross-series linking to a separate Presentation State (`PR`) view.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct ViewerStructuredReportComposerView: View {
    @Bindable var viewModel: ImageViewerViewModel

    @State private var isExportingDCM = false
    @State private var exportedDocument: DICOMBinaryDocument?
    @State private var exportFilename = "StructuredReport.dcm"
    @State private var isPublishing = false

    public init(viewModel: ImageViewerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            Form {
                if let err = viewModel.structuredReportComposerError, !err.isEmpty {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                reportTypeSection
                clinicalNarrativeSection

                if viewModel.clinicalSRDraft.reportKind != .basicTextSR {
                    measurementsSection
                }

                evidenceAndPRLinkSection
                observerAndVerificationSection
            }
            .formStyle(.grouped)

            Divider()
            footerBar
        }
        .frame(minWidth: 660, idealWidth: 720, minHeight: 620, idealHeight: 720)
        .fileExporter(
            isPresented: $isExportingDCM,
            document: exportedDocument,
            contentType: .data,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                viewModel.structuredReportComposerError =
                    "Could not export DICOM SR file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("Write Structured Report (DICOM SR)")
                    .font(.headline)
                Text(patientContextSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Saved as dedicated Series 9002 (Modality = SR). Any linked Presentation State remains in separate Series 9001 (Modality = PR).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var patientContextSummary: String {
        let ds = viewModel.dicomFile?.dataSet
        let name = ds?.string(for: .patientName).map(DICOMValueParser.formatPersonName) ?? "Unnamed Patient"
        let pid = ds?.string(for: .patientID) ?? "No ID"
        let mod = ds?.string(for: .modality) ?? "Study"
        let desc = ds?.string(for: .studyDescription)
        if let desc, !desc.isEmpty {
            return "\(name) (\(pid)) • \(mod) — \(desc)"
        }
        return "\(name) (\(pid)) • \(mod)"
    }

    // MARK: - Sections

    private var reportTypeSection: some View {
        Section("Report Type, Template & Title (DICOMCore Registry)") {
            Picker("SR SOP Class", selection: $viewModel.clinicalSRDraft.reportKind) {
                Section("Clinical Imaging Report IODs (Prioritized)") {
                    ForEach(ClinicalSRReportKind.clinicalReportKinds) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Section("All Other PS3.6 SR Storage SOP Classes") {
                    ForEach(ClinicalSRReportKind.specializedReportKinds) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }
            .onChange(of: viewModel.clinicalSRDraft.reportKind) { _, newKind in
                let validPresets = ClinicalSRTitlePreset.presets(for: newKind)
                if !validPresets.contains(viewModel.clinicalSRDraft.titlePreset),
                   let first = validPresets.first {
                    viewModel.clinicalSRDraft.titlePreset = first
                }
                if newKind == .measurementReportTID1500 {
                    viewModel.clinicalSRDraft.selectedTemplateDescriptor =
                        DICOMCore.TemplateRegistry.shared.descriptor(for: .measurementReport)
                } else if let defaultTID = newKind.coreDocumentType.defaultRootTemplateIdentifier {
                    viewModel.clinicalSRDraft.selectedTemplateDescriptor =
                        DICOMCore.TemplateRegistry.shared.descriptor(for: defaultTID)
                }
            }

            LabeledContent("SOP Class UID") {
                Text(viewModel.clinicalSRDraft.reportKind.sopClassUID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.clinicalSRDraft.reportKind.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            let allRegisteredTIDs = DICOMCore.TemplateRegistry.shared.allTemplateDescriptors
            let rootTIDs = allRegisteredTIDs.filter(\.isRoot)
            let subTIDs = allRegisteredTIDs.filter { !$0.isRoot }

            Picker("PS3.16 Registered Template (All \(allRegisteredTIDs.count) TIDs)", selection: $viewModel.clinicalSRDraft.selectedTemplateDescriptor) {
                Text("Default for Selected SOP Class").tag(Optional<DICOMCore.SRRegisteredTemplateDescriptor>.none)
                Section("Root Document Templates (PS3.16)") {
                    ForEach(rootTIDs) { descriptor in
                        Text(descriptor.formattedDisplayName).tag(Optional(descriptor))
                    }
                }
                Section("All Registered Sub-Templates (PS3.16)") {
                    ForEach(subTIDs) { descriptor in
                        Text(descriptor.formattedDisplayName).tag(Optional(descriptor))
                    }
                }
            }

            let availableTitles = ClinicalSRTitlePreset.presets(for: viewModel.clinicalSRDraft.reportKind)
            Picker("Document Title (CID 7000 / CID 7021)", selection: $viewModel.clinicalSRDraft.titlePreset) {
                ForEach(availableTitles) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
        }
    }

    private var clinicalNarrativeSection: some View {
        let historyConcept = DICOMCore.SRClinicalCatalog.sectionHeadingConcept(for: "History")
        let findingsConcept = DICOMCore.SRClinicalCatalog.sectionHeadingConcept(for: "Findings")
        let impressionsConcept = DICOMCore.SRClinicalCatalog.sectionHeadingConcept(for: "Impressions")
        let recsConcept = DICOMCore.SRClinicalCatalog.sectionHeadingConcept(for: "Recommendations")

        return Section("Clinical Analysis & Diagnosis (\(DICOMCore.ContextGroup.diagnosticImagingReportHeadings.name) — CID \(DICOMCore.ContextGroup.diagnosticImagingReportHeadings.cid))") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(historyConcept.codeMeaning) (\(historyConcept.codingSchemeDesignator) \(historyConcept.codeValue))")
                    .font(.caption.weight(.medium))
                TextField(
                    "Reason for exam, symptoms, or clinical background…",
                    text: $viewModel.clinicalSRDraft.clinicalHistory,
                    axis: .vertical
                )
                .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(findingsConcept.codeMeaning) (\(findingsConcept.codingSchemeDesignator) \(findingsConcept.codeValue))")
                    .font(.caption.weight(.medium))
                TextField(
                    "Describe anatomical observations, lesion characteristics, and imaging analysis…",
                    text: $viewModel.clinicalSRDraft.findings,
                    axis: .vertical
                )
                .lineLimit(3...7)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(impressionsConcept.codeMeaning) (\(impressionsConcept.codingSchemeDesignator) \(impressionsConcept.codeValue))")
                    .font(.caption.weight(.medium))
                TextField(
                    "Primary diagnostic conclusion / impression…",
                    text: $viewModel.clinicalSRDraft.impression,
                    axis: .vertical
                )
                .lineLimit(2...5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(recsConcept.codeMeaning) (\(recsConcept.codingSchemeDesignator) \(recsConcept.codeValue))")
                    .font(.caption.weight(.medium))
                TextField(
                    "Optional follow-up imaging or clinical recommendations…",
                    text: $viewModel.clinicalSRDraft.recommendations,
                    axis: .vertical
                )
                .lineLimit(1...3)
            }
        }
    }

    private var measurementsSection: some View {
        Section("Quantitative Measurements & Drawn ROIs") {
            Toggle(
                "Include arrows and text annotations drawn on the image",
                isOn: $viewModel.clinicalSRDraft.includeDrawnAnnotations
            )

            ForEach($viewModel.clinicalSRDraft.measurements) { $entry in
                HStack(spacing: 8) {
                    TextField("Label (e.g. RUL Nodule)", text: $entry.label)
                        .frame(minWidth: 140)
                    TextField("Value", value: $entry.value, format: .number)
                        .frame(width: 90)
                    Picker("Unit", selection: $entry.unit) {
                        ForEach(ClinicalSRMeasurementUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Button(role: .destructive) {
                        viewModel.clinicalSRDraft.measurements.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove measurement")
                }
            }

            Button {
                let nextIndex = viewModel.clinicalSRDraft.measurements.count + 1
                viewModel.clinicalSRDraft.measurements.append(
                    ClinicalSRMeasurementEntry(label: "Measurement \(nextIndex)", value: 10.0, unit: .millimeter)
                )
            } label: {
                Label("Add Quantitative Measurement", systemImage: "plus.circle")
            }
        }
    }

    private var evidenceAndPRLinkSection: some View {
        Section("Evidence Scope & Separate Presentation State (PR) Link") {
            Picker("Referenced Evidence", selection: $viewModel.clinicalSRDraft.referenceScope) {
                ForEach(ClinicalSRReferenceScope.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }

            let availableViews = viewModel.savedViewsForCurrentImage
            if !availableViews.isEmpty {
                Picker(
                    "Link Existing PR View (Series 9001)",
                    selection: Binding(
                        get: { viewModel.clinicalSRDraft.linkedSavedViewLabel ?? "" },
                        set: { viewModel.clinicalSRDraft.linkedSavedViewLabel = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    Text("None (Image reference only)").tag("")
                    ForEach(availableViews) { saved in
                        Text("\(saved.label) (PR)").tag(saved.label)
                    }
                }
            }

            if viewModel.canSaveCurrentView {
                Toggle(
                    "Also save current window/zoom as a separate PR view (Series 9001)",
                    isOn: $viewModel.clinicalSRDraft.alsoSaveCurrentDisplayAsPR
                )
                if viewModel.clinicalSRDraft.alsoSaveCurrentDisplayAsPR {
                    TextField(
                        "PR View Name (e.g. Lung Window)",
                        text: $viewModel.clinicalSRDraft.newPRViewLabel
                    )
                }
            }
        }
    }

    private var observerAndVerificationSection: some View {
        Section("Author, Status & Verification (PS3.3 C.17.2)") {
            TextField(
                "Author / Reporting Physician (e.g. DOE^JANE)",
                text: $viewModel.clinicalSRDraft.authorName
            )

            Picker("Report Status", selection: $viewModel.clinicalSRDraft.preliminaryFlag) {
                Text("Final").tag(Optional(PreliminaryFlag.final))
                Text("Preliminary").tag(Optional(PreliminaryFlag.preliminary))
                Text("Unspecified").tag(Optional<PreliminaryFlag>.none)
            }

            Picker("Completion Flag", selection: $viewModel.clinicalSRDraft.completionFlag) {
                Text("Complete").tag(CompletionFlag.complete)
                Text("Partial").tag(CompletionFlag.partial)
            }

            Picker("Verification Flag", selection: $viewModel.clinicalSRDraft.verificationFlag) {
                Text("Unverified").tag(VerificationFlag.unverified)
                Text("Verified").tag(VerificationFlag.verified)
            }

            if viewModel.clinicalSRDraft.verificationFlag == .verified {
                TextField(
                    "Verifying Observer Name (Required, e.g. SMITH^JOHN)",
                    text: $viewModel.clinicalSRDraft.verifyingObserverName
                )
                TextField(
                    "Verifying Organization (Required, e.g. Radiology Dept)",
                    text: $viewModel.clinicalSRDraft.verifyingOrganization
                )
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel) {
                viewModel.isSRComposerPresented = false
            }

            Spacer()

            Button {
                do {
                    let data = try viewModel.exportClinicalStructuredReportData()
                    exportedDocument = DICOMBinaryDocument(data: data)
                    let pid = viewModel.dicomFile?.dataSet.string(for: .patientID) ?? "Study"
                    exportFilename = "SR_\(pid).dcm"
                    isExportingDCM = true
                } catch {
                    // Error is already populated on `viewModel.structuredReportComposerError`
                }
            } label: {
                Label("Export .dcm…", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export Structured Report as DICOM file")

            if viewModel.canPublishStructuredReportToStudy {
                Button {
                    isPublishing = true
                    Task {
                        _ = await viewModel.publishClinicalStructuredReport()
                        isPublishing = false
                    }
                } label: {
                    if isPublishing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Save to Study (Series 9002 — SR)", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPublishing)
                .accessibilityLabel("Save Structured Report to Study Series 9002")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
#endif
