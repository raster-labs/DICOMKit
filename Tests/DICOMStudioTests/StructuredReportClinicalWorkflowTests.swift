// StructuredReportClinicalWorkflowTests.swift
// DICOMStudioTests
//
// End-to-end verification of the clinical Structured Report (SR) workflow in DICOMStudio,
// separate PR (Series 9001, Modality = "PR") vs SR (Series 9002, Modality = "SR") series invariant,
// nested SR subtree rendering in ViewerNonImageContentView, and standalone SR Part 10 round-trips.

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import DICOMPrintKit
import Foundation

@MainActor
@Suite("Structured Report Clinical Workflow Tests")
struct StructuredReportClinicalWorkflowTests {

    private static let studyUID = "1.2.840.113619.2.55.3.99100"
    private static let imageSeriesUID = "1.2.840.113619.2.55.3.99100.1"
    private static let imageSOPUID = "1.2.840.113619.2.55.3.99100.1.1"

    private func makeStudy() throws -> (ImageViewerViewModel, LibraryModel, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudioClinicalSRTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let elements: [DataElement] = [
            .string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2"),
            .string(tag: .sopInstanceUID, vr: .UI, value: Self.imageSOPUID),
            .string(tag: .studyInstanceUID, vr: .UI, value: Self.studyUID),
            .string(tag: .seriesInstanceUID, vr: .UI, value: Self.imageSeriesUID),
            .string(tag: .patientID, vr: .LO, value: "PAT-2026"),
            .string(tag: .patientName, vr: .PN, value: "PATEL^ARJUN"),
            .string(tag: .studyDate, vr: .DA, value: "20261119"),
            .string(tag: .studyTime, vr: .TM, value: "093000"),
            .string(tag: .accessionNumber, vr: .SH, value: "ACC99100"),
            .string(tag: .studyDescription, vr: .LO, value: "CT Chest with Contrast"),
            .string(tag: .modality, vr: .CS, value: "CT"),
            .string(tag: .windowCenter, vr: .DS, value: "-600"),
            .string(tag: .windowWidth, vr: .DS, value: "1500")
        ]
        let file = DICOMFile.create(
            dataSet: DataSet(elements: elements),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: Self.imageSOPUID
        )
        let imageURL = folder.appendingPathComponent("ct_slice_01.dcm")
        try file.write().write(to: imageURL)

        var library = LibraryModel()
        library.addStudy(StudyModel(studyInstanceUID: Self.studyUID))
        library.addSeries(SeriesModel(
            seriesInstanceUID: Self.imageSeriesUID,
            studyInstanceUID: Self.studyUID,
            seriesNumber: 1,
            modality: "CT",
            seriesDescription: "Axial Lung"
        ))
        library.addInstance(InstanceModel(
            sopInstanceUID: Self.imageSOPUID,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            seriesInstanceUID: Self.imageSeriesUID,
            instanceNumber: 1,
            filePath: imageURL.path
        ))

        let vm = ImageViewerViewModel()
        vm.dicomFile = file
        vm.filePath = imageURL.path
        vm.sopInstanceUID = Self.imageSOPUID
        vm.studyInstanceUID = Self.studyUID
        vm.currentSeriesUID = Self.imageSeriesUID
        vm.imageColumns = 512
        vm.imageRows = 512
        vm.viewContentWidth = 800
        vm.viewContentHeight = 600
        vm.presentationStateStore = PresentationStateStore(
            root: folder.appendingPathComponent("Store")
        )
        vm.loadStudySeries(
            ViewerSeriesCatalog.entries(forStudy: Self.studyUID, in: library),
            studyUID: Self.studyUID
        )

        return (vm, library, folder)
    }

    // MARK: - 1. Separate PR (Series 9001) vs SR (Series 9002) Clinical Authoring

    @Test("Clinical SR composer saves PR in Series 9001 (Modality PR) and clinical SR in separate Series 9002 (Modality SR)")
    func clinicalSRAndLinkedPRPublishIntoSeparateConformantSeries() async throws {
        let (vm, _, folder) = try makeStudy()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Adjust display state and draw an arrow annotation on the CT slice
        vm.zoomLevel = 1.8
        let arrowID = vm.addDrawnArrowAnnotation(
            from: PrintOverlayPoint(x: 0.3, y: 0.4),
            to: PrintOverlayPoint(x: 0.45, y: 0.5)
        )
        if let arrowID {
            vm.setDrawnAnnotationText("RUL spiculated nodule", id: arrowID)
        }

        // Open clinical SR composer and enter full diagnostic report + linked PR request
        vm.openSRComposer()
        #expect(vm.isSRComposerPresented)

        vm.clinicalSRDraft.reportKind = .diagnosticComprehensiveSR
        vm.clinicalSRDraft.titlePreset = .radiologyReport
        vm.clinicalSRDraft.clinicalHistory = "62-year-old with persistent cough."
        vm.clinicalSRDraft.findings = "14.2 mm spiculated pulmonary nodule in the right upper lobe."
        vm.clinicalSRDraft.impression = "Suspicious right upper lobe nodule (Lung-RADS 4B)."
        vm.clinicalSRDraft.recommendations = "PET-CT and tissue sampling recommended."
        vm.clinicalSRDraft.authorName = "SHARMA^PRIYA"
        vm.clinicalSRDraft.preliminaryFlag = .final
        vm.clinicalSRDraft.completionFlag = .complete
        vm.clinicalSRDraft.verificationFlag = .verified
        vm.clinicalSRDraft.verifyingObserverName = "MEHTA^RAJESH"
        vm.clinicalSRDraft.verifyingOrganization = "Thoracic Radiology"
        vm.clinicalSRDraft.measurements = [
            ClinicalSRMeasurementEntry(label: "RUL Nodule Long Axis", value: 14.2, unit: .millimeter)
        ]
        vm.clinicalSRDraft.alsoSaveCurrentDisplayAsPR = true
        vm.clinicalSRDraft.newPRViewLabel = "Lung Nodule View"

        let publishedSR = try #require(await vm.publishClinicalStructuredReport())
        let publishedPR = try #require(vm.publishedPresentationSeries)

        // PR and SR MUST belong to separate Series with distinct SeriesInstanceUIDs and Modalities!
        #expect(publishedPR.seriesNumber == 9001)
        #expect(publishedPR.modality == "PR")
        #expect(publishedSR.seriesNumber == 9002)
        #expect(publishedSR.modality == "SR")
        #expect(publishedPR.seriesInstanceUID != publishedSR.seriesInstanceUID)
        #expect(!vm.isSRComposerPresented)

        // Inspect serialized SR file on disk
        let srURL = try #require(publishedSR.instances.first?.url)
        let srData = try Data(contentsOf: srURL)

        // Validate against DICOMValidator Level 3
        let validation = try DICOMValidator(level: 3, iod: nil, force: false)
            .validate(data: srData, filePath: srURL.path)
        #expect(validation.errors.isEmpty, "Expected 0 DICOM validation errors, got: \(validation.errors)")

        let srFile = try DICOMFile.read(from: srData)
        #expect(srFile.dataSet.string(for: .modality) == "SR")
        #expect(srFile.dataSet.string(for: .seriesDescription) == "Structured Reports")
        #expect(srFile.dataSet.string(for: .studyDescription) == "CT Chest with Contrast")
        #expect(srFile.dataSet.string(for: .preliminaryFlag) == "FINAL")
        #expect(srFile.dataSet.string(for: .completionFlag) == "COMPLETE")
        #expect(srFile.dataSet.string(for: .verificationFlag) == "VERIFIED")
        #expect(srFile.dataSet[.contentLabel] == nil, "PS3.3 C.11.10 ContentLabel must not pollute SR datasets")

        // Parse back via DICOMKit SRDocumentParser and verify clinical sections, measurements, PR link, and evidence
        let parsed = try SRDocumentParser().parse(dataSet: srFile.dataSet)
        #expect(parsed.documentTitle?.codeValue == "11528-7")
        #expect(parsed.verifyingObservers.first?.name == "MEHTA^RAJESH")
        #expect(parsed.verifyingObservers.first?.organization == "Thoracic Radiology")

        // Evidence sequence must list both the CT series and the separate PR series (9001)
        let evidenceSeriesUIDs = Set(parsed.evidenceReferences.map(\.seriesInstanceUID))
        #expect(evidenceSeriesUIDs.contains(Self.imageSeriesUID))
        #expect(evidenceSeriesUIDs.contains(publishedPR.seriesInstanceUID))

        // Nested Softcopy Presentation State reference (0008,1199) on IMAGE item points to the PR SOP Instance
        let extracted = PresentationStateSRBridge.extract(from: parsed)
        let prSOPUID = try #require(publishedPR.instances.first?.sopInstanceUID)
        #expect(extracted.presentationStateReferences.contains { $0.sopInstanceUID == prSOPUID })

        // Verify clinical text sections are preserved
        let allTexts = parsed.rootContent.contentItems.flatMap { item -> [String] in
            if let c = item.asContainer {
                return c.contentItems.compactMap { $0.asText?.textValue }
            }
            return []
        }
        #expect(allTexts.contains("14.2 mm spiculated pulmonary nodule in the right upper lobe."))
        #expect(allTexts.contains("Suspicious right upper lobe nodule (Lung-RADS 4B)."))

        try assertDSR2XMLPassesIfInstalled(data: srData)
    }

    // MARK: - 2. Basic Text SR & TID 1500 Export + Validation

    @Test("Basic Text SR and TID 1500 Measurement Report modes validate and export clean Part 10 .dcm")
    func basicTextAndTID1500ClinicalExportsValidate() throws {
        let (vm, _, folder) = try makeStudy()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Basic Text SR mode
        vm.clinicalSRDraft = ClinicalSRDraft()
        vm.clinicalSRDraft.reportKind = .basicTextSR
        vm.clinicalSRDraft.findings = "Lungs are clear without focal consolidation or pleural effusion."
        vm.clinicalSRDraft.impression = "Normal chest CT."
        let basicData = try vm.exportClinicalStructuredReportData()
        let basicValidation = try DICOMValidator(level: 3, iod: nil, force: false)
            .validate(data: basicData, filePath: "basic_clinical.dcm")
        #expect(basicValidation.errors.isEmpty)
        try assertDSR2XMLPassesIfInstalled(data: basicData)

        // TID 1500 Measurement Report mode
        vm.clinicalSRDraft = ClinicalSRDraft()
        vm.clinicalSRDraft.reportKind = .measurementReportTID1500
        vm.clinicalSRDraft.titlePreset = .imagingMeasurementReport
        vm.clinicalSRDraft.impression = "Stable 8.5 mm hepatic cyst."
        vm.clinicalSRDraft.measurements = [
            ClinicalSRMeasurementEntry(label: "Hepatic Cyst", value: 8.5, unit: .millimeter)
        ]
        let tid1500Data = try vm.exportClinicalStructuredReportData()
        let tid1500Validation = try DICOMValidator(level: 3, iod: nil, force: false)
            .validate(data: tid1500Data, filePath: "tid1500_clinical.dcm")
        #expect(tid1500Validation.errors.isEmpty)
        try assertDSR2XMLPassesIfInstalled(data: tid1500Data)
    }

    // MARK: - 3. ViewerNonImageContentView Nested Non-Container Subtree Rendering

    #if canImport(SwiftUI)
    @Test("StructuredReportNarrativeView renders nested NUM -> SCOORD -> IMAGE child subtrees")
    func narrativeViewRendersNestedNonContainerSubtrees() throws {
        let imgItem = AnyContentItem(ImageContentItem(
            conceptName: nil,
            imageReference: ImageReference(
                sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                sopInstanceUID: Self.imageSOPUID
            ),
            relationshipType: .selectedFrom
        ))
        let scoordItem = AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: nil,
            graphicType: .polyline,
            graphicData: [10, 20, 40, 60],
            relationshipType: .inferredFrom,
            contentItems: [imgItem]
        ))
        let numItem = AnyContentItem(NumericContentItem(
            conceptName: DICOMCore.CodedConcept(codeValue: "410668003", codingSchemeDesignator: "SCT", codeMeaning: "Length"),
            value: 24.5,
            units: DICOMCore.CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm"),
            relationshipType: .contains,
            contentItems: [scoordItem]
        ))
        let group = AnyContentItem(ContainerContentItem(
            conceptName: DICOMCore.CodedConcept(codeValue: "125007", codingSchemeDesignator: "DCM", codeMeaning: "Measurement Group"),
            continuityOfContent: .separate,
            contentItems: [numItem],
            relationshipType: .contains
        ))
        let title = DICOMCore.CodedConcept(codeValue: "126000", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurement Report")
        let doc = DICOMKit.SRDocument(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.88.33",
            sopInstanceUID: "1.2.840.113619.2.55.3.99100.9002.1",
            documentTitle: title,
            rootContent: ContainerContentItem(conceptName: title, continuityOfContent: .separate, contentItems: [group])
        )

        let rows = StructuredReportNarrativeView(document: doc).rows
        // Must include: Measurement Group (depth 0), Length: 24.5 mm (depth 1),
        // inferred from: (polyline coordinates, 2 pt) (depth 2), selected from: (referenced image ...) (depth 3)
        #expect(rows.count == 4)
        #expect(rows[1].value == "24.5 mm")
        #expect(rows[2].value?.contains("polyline coordinates") == true)
        #expect(rows[3].value?.contains(Self.imageSOPUID) == true)
    }
    #endif

    // MARK: - 4. Standalone StructuredReportViewModel + SRSerializationBridge Round-Trip

    @Test("Standalone StructuredReportViewModel builds, exports, validates, and re-imports Pathology & Radiology SRs")
    func standaloneBuilderRoundTripsIncludingLongCodeValues() throws {
        let vm = StructuredReportViewModel()
        vm.builderDocumentType = .basicText
        vm.selectedTemplate = .pathologyReport // includes "GROSS_DESCRIPTION" (17 chars -> LongCodeValue)
        vm.patientName = "KUMAR^ANITA"
        vm.patientID = "P-7788"
        vm.observerName = "RAO^VIKRAM"
        vm.isComplete = true
        vm.isVerified = true
        vm.verifyingObserverName = "RAO^VIKRAM"
        vm.verifyingOrganization = "Pathology Lab"
        vm.sectionTexts = [
            "Gross Description": "2.1 cm well-circumscribed tan nodule.",
            "Microscopic Description": "Benign glandular proliferation without atypia.",
            "Diagnosis": "Benign fibroadenoma."
        ]

        let created = try #require(vm.createAndLoadDocument())
        #expect(vm.validationErrors.isEmpty)
        #expect(created.isVerified)

        let exportedData = try vm.exportSelectedDocumentData()
        let validation = try DICOMValidator(level: 3, iod: nil, force: false)
            .validate(data: exportedData, filePath: "pathology_sr.dcm")
        #expect(validation.errors.isEmpty, "Unexpected validation errors: \(validation.errors)")

        let reimported = try vm.importDICOMData(exportedData)
        #expect(reimported.patientName == "KUMAR^ANITA")
        #expect(reimported.isVerified)
        #expect(reimported.rootContentItem.children.contains { $0.conceptName?.codeValue == "GROSS_DESCRIPTION" })
        try assertDSR2XMLPassesIfInstalled(data: exportedData)
    }

    @Test("StructuredReportService matches favorite and recent terms by DICOM code regardless of UUID")
    func terminologyMatchesByCodeAcrossDistinctInstances() {
        let service = StructuredReportService()
        let first = TerminologyEntry(
            concept: DICOMStudio.CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung")
        )
        let second = TerminologyEntry(
            concept: DICOMStudio.CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung")
        )
        #expect(first.concept != second.concept) // Distinct UUIDs preserved for SwiftUI Identifiable
        #expect(first.concept.matchesCode(second.concept))

        service.toggleFavorite(first)
        #expect(service.isFavorite(second.concept))
        service.toggleFavorite(second)
        #expect(!service.isFavorite(first.concept))

        service.recordRecentTerm(first)
        service.recordRecentTerm(second)
        #expect(service.recentTerms.count == 1)
    }

    // MARK: - Helper

    private func assertDSR2XMLPassesIfInstalled(data: Data) throws {
        let dsr2xmlPath = "/opt/homebrew/bin/dsr2xml"
        guard FileManager.default.isExecutableFile(atPath: dsr2xmlPath) else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("studio-sr-\(UUID().uuidString).dcm")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: dsr2xmlPath)
        proc.arguments = [url.path]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(proc.terminationStatus == 0, "dsr2xml failed: \(stderr)")
    }
}
