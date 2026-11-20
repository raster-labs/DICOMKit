// ImageViewerViewModel+StructuredReports.swift
// DICOMStudio
//
// DICOM Studio — Clinical Structured Report authoring and publishing for the Study Viewer.
// NEMA-verified: 2026a, checked 2026-11-19 — PS3.3 2026a A.35.1 (Basic Text SR Storage 1.2.840.10008.5.1.4.1.1.88.11), A.35.3 (Comprehensive SR Storage 1.2.840.10008.5.1.4.1.1.88.33), C.17.1 (SR Document Series Modality = "SR", separate from Softcopy Presentation State C.11.9 Modality = "PR"), C.17.2 (CompletionFlag, VerificationFlag, PreliminaryFlag, Type 1C VerifyingObserverSequence (0040,A073), Type 1C CurrentRequestedProcedureEvidenceSequence (0040,A375)), Table C.18.4-1 (nested Softcopy Presentation State reference (0008,1199) on IMAGE items), and PS3.16 2026a CID 7000 / 7001 / 7021 / 7470 / TID 1500 / TID 1501 / TID 2000

import Foundation
import DICOMCore
import DICOMKit
import DICOMPrintKit

// MARK: - Clinical SR Authoring Types

/// Clinical Structured Report IOD / template family offered in the Study Viewer composer.
public enum ClinicalSRReportKind: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    /// Comprehensive SR (`1.2.840.10008.5.1.4.1.1.88.33`) — full clinical narrative,
    /// quantitative measurements (`NUM`), spatial coordinates (`SCOORD`), and image/PR references.
    case diagnosticComprehensiveSR = "COMPREHENSIVE_SR"
    /// Basic Text SR (`1.2.840.10008.5.1.4.1.1.88.11`) — pure narrative clinical report with image references.
    case basicTextSR = "BASIC_TEXT_SR"
    /// TID 1500 Imaging Measurement Report on Comprehensive SR (`1.2.840.10008.5.1.4.1.1.88.33`).
    case measurementReportTID1500 = "TID_1500_MEASUREMENT_REPORT"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .diagnosticComprehensiveSR: return "Diagnostic Comprehensive SR"
        case .basicTextSR: return "Basic Text SR (Narrative)"
        case .measurementReportTID1500: return "Imaging Measurement Report (TID 1500)"
        }
    }

    public var subtitle: String {
        switch self {
        case .diagnosticComprehensiveSR:
            return "Clinical history, findings, diagnosis/impression, measurements, and optional linked PR state"
        case .basicTextSR:
            return "Structured text sections (History, Findings, Impressions, Recommendations) and image evidence"
        case .measurementReportTID1500:
            return "Quantitative ROI measurements (TID 1500 / TID 1501) with clinical comments and image library"
        }
    }
}

/// Standard PS3.16 CID 7000 / CID 7021 document title presets for clinical Structured Reports.
public enum ClinicalSRTitlePreset: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case diagnosticImagingReport = "18748-4"
    case radiologyReport = "11528-7"
    case imagingMeasurementReport = "126000"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .diagnosticImagingReport: return "Diagnostic Imaging Report (LN 18748-4)"
        case .radiologyReport: return "Radiology Report (LN 11528-7)"
        case .imagingMeasurementReport: return "Imaging Measurement Report (DCM 126000)"
        }
    }

    public var coreConcept: DICOMCore.CodedConcept {
        switch self {
        case .diagnosticImagingReport:
            return DICOMCore.CodedConcept(
                codeValue: "18748-4",
                codingSchemeDesignator: "LN",
                codeMeaning: "Diagnostic Imaging Report"
            )
        case .radiologyReport:
            return DICOMCore.CodedConcept(
                codeValue: "11528-7",
                codingSchemeDesignator: "LN",
                codeMeaning: "Radiology Report"
            )
        case .imagingMeasurementReport:
            return DICOMCore.CodedConcept(
                codeValue: "126000",
                codingSchemeDesignator: "DCM",
                codeMeaning: "Imaging Measurement Report"
            )
        }
    }
}

/// Which study instances the authored Structured Report references as imaging evidence.
public enum ClinicalSRReferenceScope: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case currentImage = "CURRENT_IMAGE"
    case currentSeries = "CURRENT_SERIES"
    case studyOnly = "STUDY_ONLY"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .currentImage: return "Current Image"
        case .currentSeries: return "Current Series"
        case .studyOnly: return "Whole Study (Header Only)"
        }
    }
}

/// Standard UCUM measurement units offered in the clinical SR composer.
public enum ClinicalSRMeasurementUnit: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case millimeter = "mm"
    case centimeter = "cm"
    case squareMillimeter = "mm2"
    case milliliter = "ml"
    case hounsfieldUnit = "[hnsf'U]"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .millimeter: return "mm (Length)"
        case .centimeter: return "cm (Length)"
        case .squareMillimeter: return "mm² (Area)"
        case .milliliter: return "mL (Volume)"
        case .hounsfieldUnit: return "HU (Attenuation)"
        }
    }

    public var ucumConcept: DICOMCore.CodedConcept {
        switch self {
        case .millimeter:
            return DICOMCore.CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm")
        case .centimeter:
            return DICOMCore.CodedConcept(codeValue: "cm", codingSchemeDesignator: "UCUM", codeMeaning: "cm")
        case .squareMillimeter:
            return DICOMCore.CodedConcept(codeValue: "mm2", codingSchemeDesignator: "UCUM", codeMeaning: "square millimeter")
        case .milliliter:
            return DICOMCore.CodedConcept(codeValue: "ml", codingSchemeDesignator: "UCUM", codeMeaning: "milliliter")
        case .hounsfieldUnit:
            return DICOMCore.CodedConcept(codeValue: "[hnsf'U]", codingSchemeDesignator: "UCUM", codeMeaning: "Hounsfield unit")
        }
    }

    public var quantityConcept: DICOMCore.CodedConcept {
        switch self {
        case .millimeter, .centimeter:
            return DICOMCore.CodedConcept(codeValue: "410668003", codingSchemeDesignator: "SCT", codeMeaning: "Length")
        case .squareMillimeter:
            return DICOMCore.CodedConcept(codeValue: "42798000", codingSchemeDesignator: "SCT", codeMeaning: "Area")
        case .milliliter:
            return DICOMCore.CodedConcept(codeValue: "118565006", codingSchemeDesignator: "SCT", codeMeaning: "Volume")
        case .hounsfieldUnit:
            return DICOMCore.CodedConcept(codeValue: "112031", codingSchemeDesignator: "DCM", codeMeaning: "Attenuation Coefficient")
        }
    }
}

/// One quantitative clinical measurement entered in the Structured Report composer.
public struct ClinicalSRMeasurementEntry: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var label: String
    public var value: Double
    public var unit: ClinicalSRMeasurementUnit

    public init(
        id: UUID = UUID(),
        label: String = "Lesion 1",
        value: Double = 10.0,
        unit: ClinicalSRMeasurementUnit = .millimeter
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
    }
}

/// Draft clinical Structured Report authored in the Study Viewer.
public struct ClinicalSRDraft: Sendable, Equatable {
    public var reportKind: ClinicalSRReportKind = .diagnosticComprehensiveSR
    public var titlePreset: ClinicalSRTitlePreset = .diagnosticImagingReport

    /// Clinical history / indication (`(11329-0, LN, "History")` per CID 7001).
    public var clinicalHistory: String = ""
    /// Radiological observations / analysis (`(59776-5, LN, "Findings")` per CID 7001).
    public var findings: String = ""
    /// Diagnosis / clinical impression (`(19005-8, LN, "Impressions")` per CID 7001).
    public var impression: String = ""
    /// Follow-up recommendations (`(18783-1, LN, "Recommendations")` per CID 7001).
    public var recommendations: String = ""

    /// Author / observer name (`(121008, DCM, "Person Observer Name")`).
    public var authorName: String = ""
    /// Document completion status (`(0040,A491)`).
    public var completionFlag: CompletionFlag = .complete
    /// Preliminary vs. final status (`(0040,A496)`).
    public var preliminaryFlag: PreliminaryFlag? = .final
    /// Verification status (`(0040,A493)`).
    public var verificationFlag: VerificationFlag = .unverified
    /// Verifying observer name (Type 1C in `(0040,A073)` when `verificationFlag == .verified`).
    public var verifyingObserverName: String = ""
    /// Verifying organization (Type 1 in `(0040,A073)` items when `verificationFlag == .verified`).
    public var verifyingOrganization: String = "DICOMStudio"

    /// Which images of the study are referenced as evidence.
    public var referenceScope: ClinicalSRReferenceScope = .currentImage
    /// Whether arrows/labels drawn on the image/series are encoded as SR content (`SCOORD` + `TEXT`).
    public var includeDrawnAnnotations: Bool = true
    /// Optional label of an existing separate `PR` saved view (`Series 9001`) to link via `(0008,1199)`.
    public var linkedSavedViewLabel: String?
    /// Whether to also save the current display state as a new separate `PR` view (`Series 9001`) first.
    public var alsoSaveCurrentDisplayAsPR: Bool = false
    /// Label for the new `PR` view when `alsoSaveCurrentDisplayAsPR == true`.
    public var newPRViewLabel: String = ""

    /// Quantitative measurements entered for this report.
    public var measurements: [ClinicalSRMeasurementEntry] = []

    public init() {}
}

// MARK: - ImageViewerViewModel Clinical SR Extension

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension ImageViewerViewModel {

    /// Whether a clinical Structured Report can be authored from the current viewer state.
    public var canAuthorStructuredReport: Bool {
        dicomFile != nil
    }

    /// Whether the open file belongs to a study folder on disk where `Series 9002 (SR)` can be saved.
    public var canPublishStructuredReportToStudy: Bool {
        dicomFile != nil && studyInstanceUID != nil && studySeriesDirectory != nil
    }

    /// Opens the clinical Structured Report composer, optionally pre-linking a saved `PR` view.
    public func openSRComposer(linkedViewLabel: String? = nil, scope: ClinicalSRReferenceScope? = nil) {
        structuredReportComposerError = nil
        if let linkedViewLabel, !linkedViewLabel.isEmpty {
            clinicalSRDraft.linkedSavedViewLabel = linkedViewLabel
            clinicalSRDraft.alsoSaveCurrentDisplayAsPR = false
        } else if let activeView = selectedPresentationStateLabel, !activeView.isEmpty {
            clinicalSRDraft.linkedSavedViewLabel = activeView
        }
        if let scope {
            clinicalSRDraft.referenceScope = scope
        } else if isNonImageContent || isWaveform {
            clinicalSRDraft.referenceScope = .studyOnly
        }
        isSRComposerPresented = true
    }

    /// Saves a named `PR` view into `Series 9001 (Modality = "PR")` first, then opens the
    /// clinical Structured Report composer pre-linked to that `PR` view so the clinician can
    /// enter Findings and Diagnosis/Impression before publishing `Series 9002 (Modality = "SR")`.
    public func saveViewAndOpenSRComposer(label: String, scope: SavedViewScope) async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let saved: Bool
        if scope == .currentImage {
            saved = saveCurrentView(label: trimmed, includeStructuredReport: false)
        } else {
            saved = await saveCurrentView(label: trimmed, scope: scope, includeStructuredReport: false)
        }
        guard saved else { return }
        // Clear the PR-only confirmation alert so it does not compete with the SR composer sheet;
        // the Series Pane already updates immediately via `presentationSeriesPublishRequests`.
        dismissPublishedSeriesConfirmation()
        let srScope: ClinicalSRReferenceScope = (scope == .currentSeries) ? .currentSeries : .currentImage
        openSRComposer(linkedViewLabel: trimmed, scope: srScope)
    }

    /// Validates `clinicalSRDraft` and returns human-readable issues (empty when valid).
    public func validateClinicalSRDraft() -> [String] {
        var issues: [String] = []
        guard dicomFile != nil else {
            return ["Load an image or study in the viewer before creating a Structured Report."]
        }

        let hasHistory = !clinicalSRDraft.clinicalHistory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasFindings = !clinicalSRDraft.findings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImpression = !clinicalSRDraft.impression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRecs = !clinicalSRDraft.recommendations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasNarrative = hasHistory || hasFindings || hasImpression || hasRecs
        let hasDrawn = clinicalSRDraft.includeDrawnAnnotations && !collectedDrawnAnnotationsForDraft().isEmpty
        let hasMeasurements = !clinicalSRDraft.measurements.isEmpty || hasDrawn

        switch clinicalSRDraft.reportKind {
        case .diagnosticComprehensiveSR, .basicTextSR:
            if !hasFindings && !hasImpression && !hasHistory && !hasRecs {
                issues.append("Enter Clinical Findings or Diagnosis / Impression so the Structured Report contains clinical content.")
            }
        case .measurementReportTID1500:
            if !hasMeasurements && !hasNarrative {
                issues.append("Add at least one quantitative measurement, drawn annotation, or clinical comment for a TID 1500 report.")
            }
        }

        if clinicalSRDraft.verificationFlag == .verified {
            if clinicalSRDraft.verifyingObserverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Verifying Observer Name is required when Verification Status is VERIFIED (PS3.3 C.17.2).")
            }
            if clinicalSRDraft.verifyingOrganization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Verifying Organization is required when Verification Status is VERIFIED (PS3.3 C.17.2).")
            }
        }

        if clinicalSRDraft.alsoSaveCurrentDisplayAsPR
            && clinicalSRDraft.newPRViewLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Enter a view name for the separate Presentation State (Series 9001 — PR), or turn off 'Also save current display as PR view'.")
        }

        return issues
    }

    /// Builds a DICOM 2026a–conformant `DICOMKit.SRDocument` from `clinicalSRDraft` and the open study/image.
    public func buildClinicalStructuredReport(
        seriesInstanceUID: String? = nil
    ) throws -> DICOMKit.SRDocument {
        guard let file = dicomFile else {
            throw DICOMError.parsingFailed("No DICOM file is open in the viewer.")
        }

        let ds = file.dataSet
        let studyUID = studyInstanceUID
            ?? ds.string(for: .studyInstanceUID)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? UIDGenerator.generateStudyInstanceUID().value
        let srSeriesUID = seriesInstanceUID ?? UIDGenerator.generateSeriesInstanceUID().value
        let stamp = SRSerializationBridge.currentDICOMTimestamp()

        // Resolve referenced images and any linked separate PR instances (Series 9001)
        let targetImages = resolvedEvidenceImages(for: clinicalSRDraft.referenceScope, activeDataSet: ds)
        let prByImage = resolvedLinkedPRMap(
            studyUID: studyUID,
            viewLabel: clinicalSRDraft.linkedSavedViewLabel
        )

        var evidenceRefs: [HierarchicalSOPReference] = []
        var seenEvidence = Set<String>()
        for img in targetImages {
            if seenEvidence.insert(img.sopInstanceUID).inserted {
                evidenceRefs.append(HierarchicalSOPReference(
                    studyInstanceUID: studyUID,
                    seriesInstanceUID: img.seriesInstanceUID.isEmpty ? srSeriesUID : img.seriesInstanceUID,
                    sopClassUID: img.sopClassUID,
                    sopInstanceUID: img.sopInstanceUID
                ))
            }
            if let prInfo = prByImage[img.sopInstanceUID],
               seenEvidence.insert(prInfo.ref.sopInstanceUID).inserted {
                evidenceRefs.append(HierarchicalSOPReference(
                    studyInstanceUID: studyUID,
                    seriesInstanceUID: prInfo.seriesInstanceUID.isEmpty ? srSeriesUID : prInfo.seriesInstanceUID,
                    sopClassUID: prInfo.ref.sopClassUID,
                    sopInstanceUID: prInfo.ref.sopInstanceUID
                ))
            }
        }

        let historyText = clinicalSRDraft.clinicalHistory.trimmingCharacters(in: .whitespacesAndNewlines)
        let findingsText = clinicalSRDraft.findings.trimmingCharacters(in: .whitespacesAndNewlines)
        let impressionText = clinicalSRDraft.impression.trimmingCharacters(in: .whitespacesAndNewlines)
        let recsText = clinicalSRDraft.recommendations.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorText = clinicalSRDraft.authorName.trimmingCharacters(in: .whitespacesAndNewlines)

        let rawDoc: DICOMKit.SRDocument
        switch clinicalSRDraft.reportKind {
        case .basicTextSR:
            rawDoc = try buildBasicTextClinicalSR(
                dataSet: ds,
                studyUID: studyUID,
                srSeriesUID: srSeriesUID,
                stamp: stamp,
                historyText: historyText,
                findingsText: findingsText,
                impressionText: impressionText,
                recsText: recsText,
                authorText: authorText,
                targetImages: targetImages,
                prByImage: prByImage
            )
        case .diagnosticComprehensiveSR:
            rawDoc = try buildComprehensiveClinicalSR(
                dataSet: ds,
                studyUID: studyUID,
                srSeriesUID: srSeriesUID,
                stamp: stamp,
                historyText: historyText,
                findingsText: findingsText,
                impressionText: impressionText,
                recsText: recsText,
                authorText: authorText,
                targetImages: targetImages,
                prByImage: prByImage
            )
        case .measurementReportTID1500:
            rawDoc = try buildTID1500ClinicalSR(
                dataSet: ds,
                studyUID: studyUID,
                srSeriesUID: srSeriesUID,
                stamp: stamp,
                historyText: historyText,
                findingsText: findingsText,
                impressionText: impressionText,
                recsText: recsText,
                authorText: authorText,
                targetImages: targetImages,
                prByImage: prByImage
            )
        }

        var verifyingObservers = rawDoc.verifyingObservers
        if clinicalSRDraft.verificationFlag == .verified && verifyingObservers.isEmpty {
            verifyingObservers.append(
                VerifyingObserver(
                    name: clinicalSRDraft.verifyingObserverName.trimmingCharacters(in: .whitespacesAndNewlines),
                    organization: clinicalSRDraft.verifyingOrganization.trimmingCharacters(in: .whitespacesAndNewlines),
                    verificationDateTime: "\(stamp.date)\(stamp.time)"
                )
            )
        }

        // Preserve PreliminaryFlag, VerifyingObservers, Study/Series descriptions, and Evidence Sequence
        return DICOMKit.SRDocument(
            sopClassUID: rawDoc.sopClassUID,
            sopInstanceUID: rawDoc.sopInstanceUID,
            patientID: ds.string(for: .patientID) ?? rawDoc.patientID,
            patientName: ds.string(for: .patientName) ?? rawDoc.patientName,
            studyInstanceUID: studyUID,
            studyDate: ds.string(for: .studyDate) ?? rawDoc.studyDate,
            studyTime: ds.string(for: .studyTime) ?? rawDoc.studyTime,
            accessionNumber: ds.string(for: .accessionNumber) ?? rawDoc.accessionNumber,
            seriesInstanceUID: srSeriesUID,
            seriesNumber: String(PresentationStateStore.structuredReportSeriesNumber),
            modality: "SR",
            contentDate: stamp.date,
            contentTime: stamp.time,
            instanceNumber: rawDoc.instanceNumber ?? "1",
            completionFlag: clinicalSRDraft.completionFlag,
            verificationFlag: clinicalSRDraft.verificationFlag,
            preliminaryFlag: clinicalSRDraft.preliminaryFlag,
            verifyingObservers: verifyingObservers,
            documentTitle: rawDoc.documentTitle ?? rawDoc.rootContent.conceptName,
            rootContent: rawDoc.rootContent,
            patientBirthDate: ds.string(for: .patientBirthDate),
            patientSex: ds.string(for: .patientSex),
            referringPhysicianName: ds.string(for: .referringPhysicianName),
            studyID: ds.string(for: .studyID),
            manufacturer: ds.string(for: .manufacturer),
            studyDescription: ds.string(for: .studyDescription),
            seriesDescription: PresentationStateStore.structuredReportSeriesDescription,
            evidenceReferences: evidenceRefs
        )
    }

    /// Publishes the authored clinical Structured Report into `Series 9002 (Modality = "SR")` of the open study
    /// (separate from `Series 9001 (Modality = "PR")`).
    @discardableResult
    public func publishClinicalStructuredReport() async -> PresentationStateStore.PublishedSeries? {
        let errors = validateClinicalSRDraft()
        guard errors.isEmpty else {
            structuredReportComposerError = errors.joined(separator: "\n")
            return nil
        }
        guard let destination = studySeriesDirectory else {
            structuredReportComposerError =
                "This file was opened outside an imported study folder; use 'Export .dcm…' to save it to disk."
            return nil
        }

        // If the clinician opted to save the current display state as a separate PR view first,
        // save it into Series 9001 (Modality = "PR") and link it via (0008,1199).
        if clinicalSRDraft.alsoSaveCurrentDisplayAsPR {
            let prLabel = clinicalSRDraft.newPRViewLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let prScope: SavedViewScope = (clinicalSRDraft.referenceScope == .currentSeries && canSaveViewForSeries)
                ? .currentSeries
                : .currentImage
            let savedPR: Bool
            if prScope == .currentImage {
                savedPR = saveCurrentView(label: prLabel, includeStructuredReport: false)
            } else {
                savedPR = await saveCurrentView(label: prLabel, scope: .currentSeries, includeStructuredReport: false)
            }
            guard savedPR else {
                structuredReportComposerError = presentationStateError ?? "Could not save the linked Presentation State view."
                return nil
            }
            clinicalSRDraft.linkedSavedViewLabel = prLabel
            clinicalSRDraft.alsoSaveCurrentDisplayAsPR = false
        }

        do {
            let srDoc = try buildClinicalStructuredReport()
            let reportLabel = clinicalSRDraft.titlePreset.coreConcept.codeMeaning
            let publishedSR = try PresentationStateStore.publishDocument(
                srDoc,
                label: reportLabel,
                into: destination
            )
            lastAuthoredStudioSRDocument = SRSerializationBridge.fromDICOMKitDocument(srDoc)
            publishedStructuredReportSeries = publishedSR
            structuredReportPublishRequests += 1
            structuredReportComposerError = nil
            isSRComposerPresented = false
            return publishedSR
        } catch {
            structuredReportComposerError = "Could not save the Structured Report: \(error.localizedDescription)"
            return nil
        }
    }

    /// Serializes the authored clinical Structured Report to standalone DICOM Part 10 `Data` for `.dcm` export.
    public func exportClinicalStructuredReportData() throws -> Data {
        let errors = validateClinicalSRDraft()
        if !errors.isEmpty {
            let msg = errors.joined(separator: " ")
            structuredReportComposerError = msg
            throw DICOMError.parsingFailed(msg)
        }
        let srDoc = try buildClinicalStructuredReport()
        let dataSet = try SRDocumentSerializer().serialize(document: srDoc)
        let dicomFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: srDoc.sopClassUID,
            sopInstanceUID: srDoc.sopInstanceUID,
            transferSyntaxUID: SRSerializationBridge.explicitVRLittleEndianUID
        )
        let data = try dicomFile.write()
        lastAuthoredStudioSRDocument = SRSerializationBridge.fromDICOMKitDocument(srDoc)
        structuredReportComposerError = nil
        return data
    }

    // MARK: - Private Builders

    private func buildBasicTextClinicalSR(
        dataSet ds: DataSet,
        studyUID: String,
        srSeriesUID: String,
        stamp: (date: String, time: String),
        historyText: String,
        findingsText: String,
        impressionText: String,
        recsText: String,
        authorText: String,
        targetImages: [SeriesImageIdentity],
        prByImage: [String: (ref: ReferencedSOP, seriesInstanceUID: String)]
    ) throws -> DICOMKit.SRDocument {
        let title = clinicalSRDraft.titlePreset == .imagingMeasurementReport
            ? ClinicalSRTitlePreset.diagnosticImagingReport.coreConcept
            : clinicalSRDraft.titlePreset.coreConcept

        let historyHeading = DICOMCore.CodedConcept(codeValue: "11329-0", codingSchemeDesignator: "LN", codeMeaning: "History")
        let findingsHeading = DICOMCore.CodedConcept(codeValue: "59776-5", codingSchemeDesignator: "LN", codeMeaning: "Findings")
        let impressionsHeading = DICOMCore.CodedConcept(codeValue: "19005-8", codingSchemeDesignator: "LN", codeMeaning: "Impressions")
        let recsHeading = DICOMCore.CodedConcept(codeValue: "18783-1", codingSchemeDesignator: "LN", codeMeaning: "Recommendations")
        let observerConcept = DICOMCore.CodedConcept(codeValue: "121008", codingSchemeDesignator: "DCM", codeMeaning: "Person Observer Name")
        let imageConcept = DICOMCore.CodedConcept(codeValue: "121200", codingSchemeDesignator: "DCM", codeMeaning: "Illustration of ROI")

        var builder = BasicTextSRBuilder()
            .withStudyInstanceUID(studyUID)
            .withSeriesInstanceUID(srSeriesUID)
            .withSeriesNumber(String(PresentationStateStore.structuredReportSeriesNumber))
            .withSeriesDescription(PresentationStateStore.structuredReportSeriesDescription)
            .withContentDate(stamp.date)
            .withContentTime(stamp.time)
            .withCompletionFlag(clinicalSRDraft.completionFlag)
            .withVerificationFlag(clinicalSRDraft.verificationFlag)
            .withDocumentTitle(title)

        if let pID = ds.string(for: .patientID) { builder = builder.withPatientID(pID) }
        if let pName = ds.string(for: .patientName) { builder = builder.withPatientName(pName) }
        if !authorText.isEmpty {
            builder = builder.addItem(AnyContentItem(PersonNameContentItem(
                conceptName: observerConcept,
                personName: authorText,
                relationshipType: .hasObsContext
            )))
        }
        if !historyText.isEmpty {
            builder = builder.addSection(historyHeading) {
                AnyContentItem(TextContentItem(conceptName: historyHeading, textValue: historyText, relationshipType: .contains))
            }
        }
        if !findingsText.isEmpty {
            builder = builder.addSection(findingsHeading) {
                AnyContentItem(TextContentItem(conceptName: findingsHeading, textValue: findingsText, relationshipType: .contains))
            }
        }
        if !impressionText.isEmpty {
            builder = builder.addSection(impressionsHeading) {
                AnyContentItem(TextContentItem(conceptName: impressionsHeading, textValue: impressionText, relationshipType: .contains))
            }
        }
        if !recsText.isEmpty {
            builder = builder.addSection(recsHeading) {
                AnyContentItem(TextContentItem(conceptName: recsHeading, textValue: recsText, relationshipType: .contains))
            }
        }
        for img in targetImages {
            let imgRef = ImageReference(
                sopClassUID: img.sopClassUID,
                sopInstanceUID: img.sopInstanceUID,
                presentationStateReference: prByImage[img.sopInstanceUID]?.ref
            )
            builder = builder.addItem(AnyContentItem(ImageContentItem(
                conceptName: imageConcept,
                imageReference: imgRef,
                relationshipType: .contains
            )))
        }
        return try builder.build()
    }

    private func buildComprehensiveClinicalSR(
        dataSet ds: DataSet,
        studyUID: String,
        srSeriesUID: String,
        stamp: (date: String, time: String),
        historyText: String,
        findingsText: String,
        impressionText: String,
        recsText: String,
        authorText: String,
        targetImages: [SeriesImageIdentity],
        prByImage: [String: (ref: ReferencedSOP, seriesInstanceUID: String)]
    ) throws -> DICOMKit.SRDocument {
        let title = clinicalSRDraft.titlePreset.coreConcept
        let historyHeading = DICOMCore.CodedConcept(codeValue: "11329-0", codingSchemeDesignator: "LN", codeMeaning: "History")
        let findingsHeading = DICOMCore.CodedConcept(codeValue: "59776-5", codingSchemeDesignator: "LN", codeMeaning: "Findings")
        let impressionsHeading = DICOMCore.CodedConcept(codeValue: "19005-8", codingSchemeDesignator: "LN", codeMeaning: "Impressions")
        let recsHeading = DICOMCore.CodedConcept(codeValue: "18783-1", codingSchemeDesignator: "LN", codeMeaning: "Recommendations")
        let measurementsHeading = DICOMCore.CodedConcept(codeValue: "126010", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurements")
        let groupConcept = DICOMCore.CodedConcept(codeValue: "125007", codingSchemeDesignator: "DCM", codeMeaning: "Measurement Group")
        let trackingIDConcept = DICOMCore.CodedConcept(codeValue: "112039", codingSchemeDesignator: "DCM", codeMeaning: "Tracking Identifier")
        let trackingUIDConcept = DICOMCore.CodedConcept(codeValue: "112040", codingSchemeDesignator: "DCM", codeMeaning: "Tracking Unique Identifier")
        let observerConcept = DICOMCore.CodedConcept(codeValue: "121008", codingSchemeDesignator: "DCM", codeMeaning: "Person Observer Name")
        let imageConcept = DICOMCore.CodedConcept(codeValue: "121200", codingSchemeDesignator: "DCM", codeMeaning: "Illustration of ROI")
        let regionConcept = DICOMCore.CodedConcept(codeValue: "111030", codingSchemeDesignator: "DCM", codeMeaning: "Image Region")
        let commentConcept = DICOMCore.CodedConcept(codeValue: "121106", codingSchemeDesignator: "DCM", codeMeaning: "Comment")

        var rootItems: [AnyContentItem] = []

        if !authorText.isEmpty {
            rootItems.append(AnyContentItem(PersonNameContentItem(
                conceptName: observerConcept,
                personName: authorText,
                relationshipType: .hasObsContext
            )))
        }

        func appendNarrativeSection(_ heading: DICOMCore.CodedConcept, _ body: String) {
            guard !body.isEmpty else { return }
            let textNode = AnyContentItem(TextContentItem(
                conceptName: heading,
                textValue: body,
                relationshipType: .contains
            ))
            rootItems.append(AnyContentItem(ContainerContentItem(
                conceptName: heading,
                continuityOfContent: .separate,
                contentItems: [textNode],
                relationshipType: .contains
            )))
        }

        appendNarrativeSection(historyHeading, historyText)
        appendNarrativeSection(findingsHeading, findingsText)
        appendNarrativeSection(impressionsHeading, impressionText)
        appendNarrativeSection(recsHeading, recsText)

        // Quantitative clinical measurements + drawn viewer annotations
        var measurementGroups: [AnyContentItem] = []
        let primaryImg = targetImages.first
        let primaryImageRef: ImageReference? = primaryImg.map {
            ImageReference(
                sopClassUID: $0.sopClassUID,
                sopInstanceUID: $0.sopInstanceUID,
                presentationStateReference: prByImage[$0.sopInstanceUID]?.ref
            )
        }

        for entry in clinicalSRDraft.measurements {
            let trimmedLabel = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
            var groupChildren: [AnyContentItem] = [
                AnyContentItem(TextContentItem(
                    conceptName: trackingIDConcept,
                    textValue: trimmedLabel.isEmpty ? "Measurement" : trimmedLabel,
                    relationshipType: .hasObsContext
                )),
                AnyContentItem(UIDRefContentItem(
                    conceptName: trackingUIDConcept,
                    uidValue: UIDGenerator.generateUID().value,
                    relationshipType: .hasObsContext
                ))
            ]
            var numChildren: [AnyContentItem] = []
            if let primaryImageRef {
                numChildren.append(AnyContentItem(ImageContentItem(
                    conceptName: DICOMCore.CodedConcept(codeValue: "121112", codingSchemeDesignator: "DCM", codeMeaning: "Source of Measurement"),
                    imageReference: primaryImageRef,
                    relationshipType: .inferredFrom
                )))
            }
            groupChildren.append(AnyContentItem(NumericContentItem(
                conceptName: entry.unit.quantityConcept,
                value: entry.value,
                units: entry.unit.ucumConcept,
                relationshipType: .contains,
                contentItems: numChildren
            )))
            measurementGroups.append(AnyContentItem(ContainerContentItem(
                conceptName: groupConcept,
                continuityOfContent: .separate,
                contentItems: groupChildren,
                relationshipType: .contains
            )))
        }

        if clinicalSRDraft.includeDrawnAnnotations {
            for (idx, drawn) in collectedDrawnAnnotationsForDraft().enumerated() {
                let imgRef = ImageReference(
                    sopClassUID: drawn.identity.sopClassUID,
                    sopInstanceUID: drawn.identity.sopInstanceUID,
                    frameNumbers: drawn.annotation.referencedFrameNumbers,
                    presentationStateReference: prByImage[drawn.identity.sopInstanceUID]?.ref
                )
                let label = !drawn.annotation.text.isEmpty ? drawn.annotation.text : "ROI-\(idx + 1)"
                var groupChildren: [AnyContentItem] = [
                    AnyContentItem(TextContentItem(
                        conceptName: trackingIDConcept,
                        textValue: label,
                        relationshipType: .hasObsContext
                    )),
                    AnyContentItem(UIDRefContentItem(
                        conceptName: trackingUIDConcept,
                        uidValue: UIDGenerator.generateUID().value,
                        relationshipType: .hasObsContext
                    ))
                ]
                if !drawn.annotation.points.isEmpty {
                    let coords = drawn.annotation.points.flatMap { [Float($0.x), Float($0.y)] }
                    let gType: DICOMCore.GraphicType = drawn.annotation.points.count == 1 ? .point : .polyline
                    let selectedImg = AnyContentItem(ImageContentItem(
                        conceptName: nil,
                        imageReference: imgRef,
                        relationshipType: .selectedFrom
                    ))
                    groupChildren.append(AnyContentItem(SpatialCoordinatesContentItem(
                        conceptName: regionConcept,
                        graphicType: gType,
                        graphicData: coords,
                        relationshipType: .contains,
                        contentItems: [selectedImg]
                    )))
                }
                if !drawn.annotation.text.isEmpty {
                    groupChildren.append(AnyContentItem(TextContentItem(
                        conceptName: commentConcept,
                        textValue: drawn.annotation.text,
                        relationshipType: .contains
                    )))
                }
                measurementGroups.append(AnyContentItem(ContainerContentItem(
                    conceptName: groupConcept,
                    continuityOfContent: .separate,
                    contentItems: groupChildren,
                    relationshipType: .contains
                )))
            }
        }

        if !measurementGroups.isEmpty {
            rootItems.append(AnyContentItem(ContainerContentItem(
                conceptName: measurementsHeading,
                continuityOfContent: .separate,
                contentItems: measurementGroups,
                relationshipType: .contains
            )))
        }

        // Referenced images (each carrying its nested PR reference if linked)
        for img in targetImages {
            let imgRef = ImageReference(
                sopClassUID: img.sopClassUID,
                sopInstanceUID: img.sopInstanceUID,
                presentationStateReference: prByImage[img.sopInstanceUID]?.ref
            )
            rootItems.append(AnyContentItem(ImageContentItem(
                conceptName: imageConcept,
                imageReference: imgRef,
                relationshipType: .contains
            )))
        }

        let rootContainer = ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: rootItems
        )

        var verifying: [VerifyingObserver] = []
        if clinicalSRDraft.verificationFlag == .verified {
            verifying.append(VerifyingObserver(
                name: clinicalSRDraft.verifyingObserverName.trimmingCharacters(in: .whitespacesAndNewlines),
                organization: clinicalSRDraft.verifyingOrganization.trimmingCharacters(in: .whitespacesAndNewlines),
                verificationDateTime: "\(stamp.date)\(stamp.time)"
            ))
        }

        return DICOMKit.SRDocument(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.88.33",
            sopInstanceUID: UIDGenerator.generateUID().value,
            patientID: ds.string(for: .patientID),
            patientName: ds.string(for: .patientName),
            studyInstanceUID: studyUID,
            seriesInstanceUID: srSeriesUID,
            seriesNumber: String(PresentationStateStore.structuredReportSeriesNumber),
            modality: "SR",
            contentDate: stamp.date,
            contentTime: stamp.time,
            instanceNumber: "1",
            completionFlag: clinicalSRDraft.completionFlag,
            verificationFlag: clinicalSRDraft.verificationFlag,
            preliminaryFlag: clinicalSRDraft.preliminaryFlag,
            verifyingObservers: verifying,
            documentTitle: title,
            rootContent: rootContainer
        )
    }

    private func buildTID1500ClinicalSR(
        dataSet ds: DataSet,
        studyUID: String,
        srSeriesUID: String,
        stamp: (date: String, time: String),
        historyText: String,
        findingsText: String,
        impressionText: String,
        recsText: String,
        authorText: String,
        targetImages: [SeriesImageIdentity],
        prByImage: [String: (ref: ReferencedSOP, seriesInstanceUID: String)]
    ) throws -> DICOMKit.SRDocument {
        let procedureConcept = DICOMCore.CodedConcept(
            codeValue: "363679005",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Imaging procedure"
        )
        var builder = MeasurementReportBuilder(validateOnBuild: true)
            .withStudyInstanceUID(studyUID)
            .withSeriesInstanceUID(srSeriesUID)
            .withSeriesNumber(String(PresentationStateStore.structuredReportSeriesNumber))
            .withSeriesDescription(PresentationStateStore.structuredReportSeriesDescription)
            .withContentDate(stamp.date)
            .withContentTime(stamp.time)
            .withCompletionFlag(clinicalSRDraft.completionFlag)
            .withVerificationFlag(clinicalSRDraft.verificationFlag)
            .withImagingMeasurementReportTitle()
            .addProcedureReported(procedureConcept)

        if let pID = ds.string(for: .patientID) { builder = builder.withPatientID(pID) }
        if let pName = ds.string(for: .patientName) { builder = builder.withPatientName(pName) }

        if !authorText.isEmpty {
            builder = builder.addObserver(.person(name: authorText))
        } else {
            builder = builder.addObserver(.device(uid: UIDGenerator.defaultRoot, name: "DICOMStudio"))
        }

        for img in targetImages {
            builder = builder.addImageLibraryEntry(
                sopClassUID: img.sopClassUID,
                sopInstanceUID: img.sopInstanceUID,
                presentationStateReference: prByImage[img.sopInstanceUID]?.ref
            )
        }

        let primaryImg = targetImages.first
        let primaryImageRef: ImageReference? = primaryImg.map {
            ImageReference(
                sopClassUID: $0.sopClassUID,
                sopInstanceUID: $0.sopInstanceUID,
                presentationStateReference: prByImage[$0.sopInstanceUID]?.ref
            )
        }

        for entry in clinicalSRDraft.measurements {
            let sources: [MeasurementSource] = primaryImageRef.map {
                [.image(
                    purpose: DICOMCore.CodedConcept(codeValue: "121112", codingSchemeDesignator: "DCM", codeMeaning: "Source of Measurement"),
                    image: $0
                )]
            } ?? []
            let group = MeasurementGroupData(
                trackingIdentifier: entry.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Measurement" : entry.label,
                trackingUID: UIDGenerator.generateUID().value,
                contents: [
                    .measurementWithContent(
                        conceptName: entry.unit.quantityConcept,
                        value: entry.value,
                        units: entry.unit.ucumConcept,
                        content: MeasurementContent(sources: sources)
                    )
                ]
            )
            builder = builder.addMeasurementGroup(group)
        }

        if clinicalSRDraft.includeDrawnAnnotations {
            for (idx, drawn) in collectedDrawnAnnotationsForDraft().enumerated() {
                let imgRef = ImageReference(
                    sopClassUID: drawn.identity.sopClassUID,
                    sopInstanceUID: drawn.identity.sopInstanceUID,
                    frameNumbers: drawn.annotation.referencedFrameNumbers,
                    presentationStateReference: prByImage[drawn.identity.sopInstanceUID]?.ref
                )
                var contents: [MeasurementGroupContent] = []
                if !drawn.annotation.points.isEmpty {
                    let coords = drawn.annotation.points.flatMap { [Float($0.x), Float($0.y)] }
                    let gType: DICOMCore.GraphicType = drawn.annotation.points.count == 1 ? .point : .polyline
                    contents.append(.spatialCoordinatesOnImage(
                        conceptName: DICOMCore.CodedConcept(codeValue: "111030", codingSchemeDesignator: "DCM", codeMeaning: "Image Region"),
                        graphicType: gType,
                        graphicData: coords,
                        sourceImage: imgRef
                    ))
                }
                if !drawn.annotation.text.isEmpty {
                    contents.append(.text(
                        conceptName: DICOMCore.CodedConcept(codeValue: "121106", codingSchemeDesignator: "DCM", codeMeaning: "Comment"),
                        value: drawn.annotation.text
                    ))
                }
                if !contents.isEmpty {
                    builder = builder.addMeasurementGroup(MeasurementGroupData(
                        trackingIdentifier: !drawn.annotation.text.isEmpty ? drawn.annotation.text : "ROI-\(idx + 1)",
                        trackingUID: UIDGenerator.generateUID().value,
                        contents: contents
                    ))
                }
            }
        }

        let narrativeSummary = [
            historyText.isEmpty ? nil : "History: \(historyText)",
            findingsText.isEmpty ? nil : "Findings: \(findingsText)",
            impressionText.isEmpty ? nil : "Impression: \(impressionText)",
            recsText.isEmpty ? nil : "Recommendations: \(recsText)"
        ].compactMap { $0 }.joined(separator: "\n")

        if !narrativeSummary.isEmpty {
            builder = builder.addMeasurementGroup(MeasurementGroupData(
                trackingIdentifier: "Clinical Summary",
                trackingUID: UIDGenerator.generateUID().value,
                contents: [
                    .text(
                        conceptName: DICOMCore.CodedConcept(codeValue: "121106", codingSchemeDesignator: "DCM", codeMeaning: "Comment"),
                        value: narrativeSummary
                    )
                ]
            ))
        }

        return try builder.build()
    }

    // MARK: - Evidence & PR Resolution Helpers

    private func resolvedEvidenceImages(
        for scope: ClinicalSRReferenceScope,
        activeDataSet ds: DataSet
    ) -> [SeriesImageIdentity] {
        switch scope {
        case .studyOnly:
            return []
        case .currentImage:
            guard let sopUID = sopInstanceUID ?? ds.string(for: .sopInstanceUID),
                  !sopUID.isEmpty else { return [] }
            let sopClass = ds.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.7"
            guard !sopClass.hasPrefix(ViewerContentKind.presentationStatePrefix),
                  !sopClass.hasPrefix(ViewerContentKind.structuredReportPrefix) else { return [] }
            return [SeriesImageIdentity(
                filePath: filePath ?? "",
                sopClassUID: sopClass,
                sopInstanceUID: sopUID,
                seriesInstanceUID: currentSeriesUID ?? ds.string(for: .seriesInstanceUID) ?? "",
                columns: max(1, imageColumns),
                rows: max(1, imageRows),
                bitsStored: bitsStored,
                isSigned: isSigned,
                rescaleSlope: rescaleSlope,
                rescaleIntercept: rescaleIntercept,
                numberOfFrames: max(1, numberOfFrames)
            )]
        case .currentSeries:
            let paths = imageFilePaths(for: .currentSeries)
            let read = Self.readImageIdentities(paths: paths).filter {
                !$0.sopClassUID.hasPrefix(ViewerContentKind.structuredReportPrefix)
            }
            if !read.isEmpty { return read }
            return resolvedEvidenceImages(for: .currentImage, activeDataSet: ds)
        }
    }

    private func resolvedLinkedPRMap(
        studyUID: String,
        viewLabel: String?
    ) -> [String: (ref: ReferencedSOP, seriesInstanceUID: String)] {
        guard let label = viewLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              let store = presentationStateStore,
              let savedView = store.views(forStudy: studyUID).first(where: { $0.label == label })
        else { return [:] }

        var map: [String: (ref: ReferencedSOP, seriesInstanceUID: String)] = [:]
        for stored in savedView.states {
            let prRef = ReferencedSOP(
                sopClassUID: stored.state.sopClassUID,
                sopInstanceUID: stored.state.sopInstanceUID
            )
            for imgUID in stored.referencedImageUIDs {
                map[imgUID] = (prRef, stored.seriesInstanceUID)
            }
        }
        return map
    }

    private func collectedDrawnAnnotationsForDraft() -> [(identity: SeriesImageIdentity, annotation: DICOMAnnotation)] {
        guard let file = dicomFile else { return [] }
        let scopeForDrawings: ClinicalSRReferenceScope = clinicalSRDraft.referenceScope == .studyOnly
            ? .currentImage
            : clinicalSRDraft.referenceScope
        let targetImages = resolvedEvidenceImages(for: scopeForDrawings, activeDataSet: file.dataSet)
        var results: [(SeriesImageIdentity, DICOMAnnotation)] = []

        for identity in targetImages where !identity.filePath.isEmpty {
            let byFrame = drawnAnnotationsByFrame(forFile: identity.filePath)
            guard !byFrame.isEmpty else { continue }
            let width = max(1, identity.columns)
            let height = max(1, identity.rows)
            let refImg = DICOMKit.ReferencedImage(
                sopClassUID: identity.sopClassUID,
                sopInstanceUID: identity.sopInstanceUID
            )
            let gItems = PrintOverlayAnnotationGSPS.graphicAnnotations(
                from: byFrame,
                imageWidth: width,
                imageHeight: height,
                referencedImage: refImg,
                isMultiFrame: identity.numberOfFrames > 1
            )
            let allOverlays = byFrame.sorted { $0.key < $1.key }.flatMap(\.value)
            let layers = PrintOverlayAnnotationGSPS.graphicLayers(for: allOverlays)
            let converted = DICOMAnnotationConverter.annotations(
                from: gItems,
                layers: layers,
                imageWidth: width,
                imageHeight: height,
                targetCoordinateSpace: .pixel
            )
            for ann in converted {
                results.append((identity, ann))
            }
        }
        return results
    }
}
