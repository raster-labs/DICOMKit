// LibraryStorageService.swift
// DICOMStudio
//
// DICOM Studio — Library persistence service
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (JSON persistence of the library index).

import Foundation

/// Service for persisting the DICOM library to disk.
///
/// Uses JSON-based storage for portability and simplicity.
/// The library index is stored as a JSON file alongside the DICOM files.
public final class LibraryStorageService: Sendable {

    /// The storage service providing directory paths.
    public let storageService: StorageService

    /// The filename for the library index.
    public static let indexFilename = "library-index.json"

    /// Creates a library storage service.
    ///
    /// - Parameter storageService: The storage service.
    public init(storageService: StorageService = StorageService()) {
        self.storageService = storageService
    }

    /// URL for the library index file.
    public var indexURL: URL {
        storageService.baseDirectory.appendingPathComponent(Self.indexFilename)
    }

    /// Saves the library model to disk.
    ///
    /// - Parameter library: The library to persist.
    /// - Throws: If the file cannot be written.
    public func save(_ library: LibraryModel) throws {
        let snapshot = LibrarySnapshot(library: library)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try storageService.createDirectories()
        try data.write(to: indexURL, options: .atomic)
    }

    /// Loads the library model from disk.
    ///
    /// - Returns: The loaded library, or an empty library if no index exists.
    public func load() -> LibraryModel {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return LibraryModel()
        }

        do {
            let data = try Data(contentsOf: indexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
            return snapshot.toLibrary()
        } catch {
            return LibraryModel()
        }
    }

    /// Whether a saved library index exists.
    public var hasIndex: Bool {
        FileManager.default.fileExists(atPath: indexURL.path)
    }

    /// Deletes the library index from disk.
    ///
    /// - Throws: If the file cannot be deleted.
    public func deleteIndex() throws {
        if FileManager.default.fileExists(atPath: indexURL.path) {
            try FileManager.default.removeItem(at: indexURL)
        }
    }

    /// Returns the size of the library index file in bytes.
    public func indexSize() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: indexURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Exports the library to a specified directory.
    ///
    /// - Parameters:
    ///   - library: The library to export.
    ///   - destinationURL: The directory to export to.
    /// - Throws: If the export fails.
    public func export(_ library: LibraryModel, to destinationURL: URL) throws {
        let snapshot = LibrarySnapshot(library: library)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let exportPath = destinationURL.appendingPathComponent("dicom-library-export.json")
        try data.write(to: exportPath, options: .atomic)
    }
}

// MARK: - Codable Snapshot Types

/// A JSON-serializable snapshot of the library state.
struct LibrarySnapshot: Codable, Sendable {
    let version: Int
    let studies: [StudySnapshot]
    let series: [SeriesSnapshot]
    let instances: [InstanceSnapshot]

    init(library: LibraryModel) {
        self.version = 1
        self.studies = library.studies.values.map { StudySnapshot(model: $0) }
        self.series = library.series.values.map { SeriesSnapshot(model: $0) }
        self.instances = library.instances.values.map { InstanceSnapshot(model: $0) }
    }

    func toLibrary() -> LibraryModel {
        var library = LibraryModel()
        for study in studies {
            library.addStudy(study.toModel())
        }
        for s in series {
            library.addSeries(s.toModel())
        }
        for instance in instances {
            library.addInstance(instance.toModel())
        }
        return library
    }
}

struct StudySnapshot: Codable, Sendable {
    let studyInstanceUID: String
    let studyID: String
    let studyDate: Date?
    let studyTime: Date?
    let studyDescription: String?
    let accessionNumber: String?
    let referringPhysicianName: String?
    let patientName: String?
    let patientID: String?
    let patientBirthDate: Date?
    let patientSex: String?
    let institutionName: String?
    let numberOfSeries: Int
    let numberOfInstances: Int
    let modalitiesInStudy: [String]
    let storagePath: String?

    init(model: StudyModel) {
        self.studyInstanceUID = model.studyInstanceUID
        self.studyID = model.studyID
        self.studyDate = model.studyDate
        self.studyTime = model.studyTime
        self.studyDescription = model.studyDescription
        self.accessionNumber = model.accessionNumber
        self.referringPhysicianName = model.referringPhysicianName
        self.patientName = model.patientName
        self.patientID = model.patientID
        self.patientBirthDate = model.patientBirthDate
        self.patientSex = model.patientSex
        self.institutionName = model.institutionName
        self.numberOfSeries = model.numberOfSeries
        self.numberOfInstances = model.numberOfInstances
        self.modalitiesInStudy = Array(model.modalitiesInStudy)
        self.storagePath = model.storagePath
    }

    func toModel() -> StudyModel {
        StudyModel(
            studyInstanceUID: studyInstanceUID,
            studyID: studyID,
            studyDate: studyDate,
            studyTime: studyTime,
            studyDescription: studyDescription,
            accessionNumber: accessionNumber,
            referringPhysicianName: referringPhysicianName,
            patientName: patientName,
            patientID: patientID,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            institutionName: institutionName,
            numberOfSeries: numberOfSeries,
            numberOfInstances: numberOfInstances,
            modalitiesInStudy: Set(modalitiesInStudy),
            storagePath: storagePath
        )
    }
}

struct SeriesSnapshot: Codable, Sendable {
    let seriesInstanceUID: String
    let studyInstanceUID: String
    let seriesNumber: Int?
    let modality: String
    let seriesDescription: String?
    let seriesDate: Date?
    let bodyPartExamined: String?
    let numberOfInstances: Int
    let transferSyntaxUID: String?

    init(model: SeriesModel) {
        self.seriesInstanceUID = model.seriesInstanceUID
        self.studyInstanceUID = model.studyInstanceUID
        self.seriesNumber = model.seriesNumber
        self.modality = model.modality
        self.seriesDescription = model.seriesDescription
        self.seriesDate = model.seriesDate
        self.bodyPartExamined = model.bodyPartExamined
        self.numberOfInstances = model.numberOfInstances
        self.transferSyntaxUID = model.transferSyntaxUID
    }

    func toModel() -> SeriesModel {
        SeriesModel(
            seriesInstanceUID: seriesInstanceUID,
            studyInstanceUID: studyInstanceUID,
            seriesNumber: seriesNumber,
            modality: modality,
            seriesDescription: seriesDescription,
            seriesDate: seriesDate,
            bodyPartExamined: bodyPartExamined,
            numberOfInstances: numberOfInstances,
            transferSyntaxUID: transferSyntaxUID
        )
    }
}

struct InstanceSnapshot: Codable, Sendable {
    let sopInstanceUID: String
    let sopClassUID: String
    let seriesInstanceUID: String
    let instanceNumber: Int?
    let filePath: String
    let fileSize: Int64
    let transferSyntaxUID: String?
    let rows: Int?
    let columns: Int?
    let bitsAllocated: Int?
    let numberOfFrames: Int?
    let photometricInterpretation: String?

    init(model: InstanceModel) {
        self.sopInstanceUID = model.sopInstanceUID
        self.sopClassUID = model.sopClassUID
        self.seriesInstanceUID = model.seriesInstanceUID
        self.instanceNumber = model.instanceNumber
        self.filePath = model.filePath
        self.fileSize = model.fileSize
        self.transferSyntaxUID = model.transferSyntaxUID
        self.rows = model.rows
        self.columns = model.columns
        self.bitsAllocated = model.bitsAllocated
        self.numberOfFrames = model.numberOfFrames
        self.photometricInterpretation = model.photometricInterpretation
    }

    func toModel() -> InstanceModel {
        InstanceModel(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber,
            filePath: filePath,
            fileSize: fileSize,
            transferSyntaxUID: transferSyntaxUID,
            rows: rows,
            columns: columns,
            bitsAllocated: bitsAllocated,
            numberOfFrames: numberOfFrames,
            photometricInterpretation: photometricInterpretation
        )
    }
}
