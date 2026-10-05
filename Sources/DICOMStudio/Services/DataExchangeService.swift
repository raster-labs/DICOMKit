// DataExchangeService.swift
// DICOMStudio
//
// DICOM Studio — Thread-safe service for Data Exchange & Export display state management
// Reference: DICOM PS3.10 (Media Storage), PS3.18 Annex F (JSON), PS3.19 Annex A (XML)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (locked state store); the default target
// Transfer Syntax 1.2.840.10008.1.2.1 is Explicit VR Little Endian (PS3.6 2026a Table A-1).

import Foundation

public final class DataExchangeService: @unchecked Sendable {
    private let lock = NSLock()

    // 12.1 JSON state
    private var _jsonSettings: JSONConversionSettings = JSONConversionSettings()
    private var _jsonOutput: String = ""
    private var _jsonInputFilePath: String = ""

    // 12.2 XML state
    private var _xmlSettings: XMLConversionSettings = XMLConversionSettings()
    private var _xmlOutput: String = ""
    private var _xmlInputFilePath: String = ""

    // 12.3 Image export state
    private var _imageExportSettings: ImageExportSettings = ImageExportSettings()
    private var _exportedImagePaths: [String] = []

    // 12.4 Transfer syntax state
    private var _conversionJobs: [TransferSyntaxConversionJob] = []
    private var _selectedTargetSyntaxUID: String = "1.2.840.10008.1.2.1"

    // 12.5 DICOMDIR state
    private var _dicomdirEntries: [DICOMDIREntry] = []
    private var _dicomdirOutputPath: String = ""

    // 12.6 PDF encapsulation state
    private var _pdfMode: PDFEncapsulationMode = .encapsulate
    private var _pdfInputPath: String = ""
    private var _pdfOutputPath: String = ""
    private var _pdfPatientName: String = ""
    private var _pdfPatientID: String = ""

    // 12.7 Batch operations state
    private var _batchJobs: [BatchJob] = []
    private var _selectedBatchOperationType: BatchOperationType = .tagModification
    private var _batchTagModifications: [BatchTagModification] = []

    public init() {}

    // MARK: - 12.1 JSON

    public func getJSONSettings() -> JSONConversionSettings { lock.withLock { _jsonSettings } }
    public func setJSONSettings(_ s: JSONConversionSettings) { lock.withLock { _jsonSettings = s } }
    public func getJSONOutput() -> String { lock.withLock { _jsonOutput } }
    public func setJSONOutput(_ s: String) { lock.withLock { _jsonOutput = s } }
    public func getJSONInputFilePath() -> String { lock.withLock { _jsonInputFilePath } }
    public func setJSONInputFilePath(_ s: String) { lock.withLock { _jsonInputFilePath = s } }

    // MARK: - 12.2 XML

    public func getXMLSettings() -> XMLConversionSettings { lock.withLock { _xmlSettings } }
    public func setXMLSettings(_ s: XMLConversionSettings) { lock.withLock { _xmlSettings = s } }
    public func getXMLOutput() -> String { lock.withLock { _xmlOutput } }
    public func setXMLOutput(_ s: String) { lock.withLock { _xmlOutput = s } }
    public func getXMLInputFilePath() -> String { lock.withLock { _xmlInputFilePath } }
    public func setXMLInputFilePath(_ s: String) { lock.withLock { _xmlInputFilePath = s } }

    // MARK: - 12.3 Image Export

    public func getImageExportSettings() -> ImageExportSettings { lock.withLock { _imageExportSettings } }
    public func setImageExportSettings(_ s: ImageExportSettings) { lock.withLock { _imageExportSettings = s } }
    public func getExportedImagePaths() -> [String] { lock.withLock { _exportedImagePaths } }
    public func addExportedImagePath(_ path: String) { lock.withLock { _exportedImagePaths.append(path) } }
    public func clearExportedImagePaths() { lock.withLock { _exportedImagePaths.removeAll() } }

    // MARK: - 12.4 Transfer Syntax

    public func getConversionJobs() -> [TransferSyntaxConversionJob] { lock.withLock { _conversionJobs } }
    public func addConversionJob(_ job: TransferSyntaxConversionJob) { lock.withLock { _conversionJobs.append(job) } }
    public func updateConversionJob(_ job: TransferSyntaxConversionJob) {
        lock.withLock {
            guard let idx = _conversionJobs.firstIndex(where: { $0.id == job.id }) else { return }
            _conversionJobs[idx] = job
        }
    }
    public func removeConversionJob(id: UUID) { lock.withLock { _conversionJobs.removeAll { $0.id == id } } }
    public func getSelectedTargetSyntaxUID() -> String { lock.withLock { _selectedTargetSyntaxUID } }
    public func setSelectedTargetSyntaxUID(_ uid: String) { lock.withLock { _selectedTargetSyntaxUID = uid } }

    // MARK: - 12.5 DICOMDIR

    public func getDICOMDIREntries() -> [DICOMDIREntry] { lock.withLock { _dicomdirEntries } }
    public func addDICOMDIREntry(_ entry: DICOMDIREntry) { lock.withLock { _dicomdirEntries.append(entry) } }
    public func removeDICOMDIREntry(id: UUID) { lock.withLock { _dicomdirEntries.removeAll { $0.id == id } } }
    public func getDICOMDIROutputPath() -> String { lock.withLock { _dicomdirOutputPath } }
    public func setDICOMDIROutputPath(_ s: String) { lock.withLock { _dicomdirOutputPath = s } }

    // MARK: - 12.6 PDF

    public func getPDFMode() -> PDFEncapsulationMode { lock.withLock { _pdfMode } }
    public func setPDFMode(_ m: PDFEncapsulationMode) { lock.withLock { _pdfMode = m } }
    public func getPDFInputPath() -> String { lock.withLock { _pdfInputPath } }
    public func setPDFInputPath(_ s: String) { lock.withLock { _pdfInputPath = s } }
    public func getPDFOutputPath() -> String { lock.withLock { _pdfOutputPath } }
    public func setPDFOutputPath(_ s: String) { lock.withLock { _pdfOutputPath = s } }
    public func getPDFPatientName() -> String { lock.withLock { _pdfPatientName } }
    public func setPDFPatientName(_ s: String) { lock.withLock { _pdfPatientName = s } }
    public func getPDFPatientID() -> String { lock.withLock { _pdfPatientID } }
    public func setPDFPatientID(_ s: String) { lock.withLock { _pdfPatientID = s } }

    // MARK: - 12.7 Batch

    public func getBatchJobs() -> [BatchJob] { lock.withLock { _batchJobs } }
    public func addBatchJob(_ job: BatchJob) { lock.withLock { _batchJobs.append(job) } }
    public func updateBatchJob(_ job: BatchJob) {
        lock.withLock {
            guard let idx = _batchJobs.firstIndex(where: { $0.id == job.id }) else { return }
            _batchJobs[idx] = job
        }
    }
    public func removeBatchJob(id: UUID) { lock.withLock { _batchJobs.removeAll { $0.id == id } } }
    public func getSelectedBatchOperationType() -> BatchOperationType { lock.withLock { _selectedBatchOperationType } }
    public func setSelectedBatchOperationType(_ t: BatchOperationType) { lock.withLock { _selectedBatchOperationType = t } }
    public func getBatchTagModifications() -> [BatchTagModification] { lock.withLock { _batchTagModifications } }
    public func addBatchTagModification(_ mod: BatchTagModification) { lock.withLock { _batchTagModifications.append(mod) } }
    public func removeBatchTagModification(id: UUID) { lock.withLock { _batchTagModifications.removeAll { $0.id == id } } }
    public func clearBatchTagModifications() { lock.withLock { _batchTagModifications.removeAll() } }
}
