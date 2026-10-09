import Foundation
import DICOMCore
import DICOMKit

// NEMA-verified: 2026a, checked 2026-09-28 — DA/TM range matching read against PS3.4 2026a C.2.2.2.5; wildcard matching against C.2.2.2.4 (case-insensitive, a leniency); tags via DICOMCore.Tag
/// In-memory storage provider for testing and development
///
/// This implementation stores DICOM instances in memory, making it
/// suitable for unit tests and development scenarios. Data is lost
/// when the provider is deallocated.
///
/// Supports both permanent and soft deletion modes:
/// - Permanent deletion: Instances are removed from storage
/// - Soft deletion: Instances are marked as deleted but retained
///
/// - Note: Not suitable for production use with large datasets.
public actor InMemoryStorageProvider: DICOMwebStorageProvider {
    
    /// Internal storage of instances by hierarchy
    private var studies: [String: StudyData] = [:]
    
    /// Soft-deleted instance UIDs (marked for deletion but retained)
    /// Format: "studyUID/seriesUID/instanceUID"
    private var softDeletedInstances: Set<String> = []
    
    /// Creates an empty in-memory storage provider
    public init() {}
    
    /// Creates an in-memory storage provider with initial instances
    /// - Parameter instances: Array of (studyUID, seriesUID, instanceUID, data) tuples
    public init(instances: [(studyUID: String, seriesUID: String, instanceUID: String, data: Data)]) async {
        for instance in instances {
            try? await storeInstance(
                data: instance.data,
                studyUID: instance.studyUID,
                seriesUID: instance.seriesUID,
                instanceUID: instance.instanceUID
            )
        }
    }
    
    /// Helper to generate soft delete key
    private func softDeleteKey(studyUID: String, seriesUID: String, instanceUID: String) -> String {
        return "\(studyUID)/\(seriesUID)/\(instanceUID)"
    }
    
    /// Check if instance is soft-deleted
    private func isSoftDeleted(studyUID: String, seriesUID: String, instanceUID: String) -> Bool {
        return softDeletedInstances.contains(softDeleteKey(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID))
    }
    
    // MARK: - Instance Operations
    
    public func getInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> Data? {
        // Don't return soft-deleted instances
        guard !isSoftDeleted(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID) else {
            return nil
        }
        return studies[studyUID]?.series[seriesUID]?.instances[instanceUID]?.data
    }
    
    public func getSeriesInstances(
        studyUID: String,
        seriesUID: String
    ) async throws -> [InstanceInfo] {
        guard let study = studies[studyUID],
              let series = study.series[seriesUID] else {
            return []
        }
        // Filter out soft-deleted instances
        return series.instances.compactMap { (instanceUID, info) in
            guard !isSoftDeleted(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID) else {
                return nil
            }
            return info
        }
    }
    
    public func getStudyInstances(studyUID: String) async throws -> [InstanceInfo] {
        guard let study = studies[studyUID] else {
            return []
        }
        // Filter out soft-deleted instances
        return study.series.flatMap { (seriesUID, series) in
            series.instances.compactMap { (instanceUID, info) in
                guard !isSoftDeleted(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID) else {
                    return nil
                }
                return info
            }
        }
    }
    
    public func storeInstance(
        data: Data,
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws {
        // Parse metadata from the DICOM data
        let metadata = extractMetadata(from: data)
        
        // Create instance info
        let instanceInfo = InstanceInfo(
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            sopClassUID: metadata.sopClassUID,
            transferSyntaxUID: metadata.transferSyntaxUID,
            size: Int64(data.count),
            data: data
        )
        
        // Store in hierarchy
        if studies[studyUID] == nil {
            studies[studyUID] = StudyData(
                studyInstanceUID: studyUID,
                patientName: metadata.patientName,
                patientID: metadata.patientID,
                studyDate: metadata.studyDate,
                studyTime: metadata.studyTime,
                studyDescription: metadata.studyDescription,
                accessionNumber: metadata.accessionNumber,
                referringPhysicianName: metadata.referringPhysicianName
            )
        }
        
        if studies[studyUID]?.series[seriesUID] == nil {
            studies[studyUID]?.series[seriesUID] = SeriesData(
                seriesInstanceUID: seriesUID,
                modality: metadata.modality,
                seriesNumber: metadata.seriesNumber,
                seriesDescription: metadata.seriesDescription
            )
        }
        
        studies[studyUID]?.series[seriesUID]?.instances[instanceUID] = instanceInfo
        
        // Update modalities in study
        if let modality = metadata.modality,
           !(studies[studyUID]?.modalitiesInStudy.contains(modality) ?? true) {
            studies[studyUID]?.modalitiesInStudy.insert(modality)
        }
        
        // Update SOP classes in study
        if let sopClass = metadata.sopClassUID,
           !(studies[studyUID]?.sopClassesInStudy.contains(sopClass) ?? true) {
            studies[studyUID]?.sopClassesInStudy.insert(sopClass)
        }
    }
    
    public func deleteInstance(
        studyUID: String,
        seriesUID: String,
        instanceUID: String,
        mode: DeletionMode = .permanent
    ) async throws -> Bool {
        guard studies[studyUID]?.series[seriesUID]?.instances[instanceUID] != nil else {
            return false
        }
        
        let key = softDeleteKey(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
        
        switch mode {
        case .soft:
            // Mark as soft-deleted
            softDeletedInstances.insert(key)
            return true
            
        case .permanent:
            // Remove soft-delete mark if it exists
            softDeletedInstances.remove(key)
            
            // Permanently delete the instance
            studies[studyUID]?.series[seriesUID]?.instances.removeValue(forKey: instanceUID)
            
            // Clean up empty series
            if studies[studyUID]?.series[seriesUID]?.instances.isEmpty ?? false {
                studies[studyUID]?.series.removeValue(forKey: seriesUID)
            }
            
            // Clean up empty studies
            if studies[studyUID]?.series.isEmpty ?? false {
                studies.removeValue(forKey: studyUID)
            }
            
            return true
        }
    }
    
    public func deleteSeries(
        studyUID: String,
        seriesUID: String,
        mode: DeletionMode = .permanent
    ) async throws -> Int {
        guard let series = studies[studyUID]?.series[seriesUID] else {
            return 0
        }
        
        let instanceKeys = series.instances.keys
        let count = instanceKeys.count
        
        switch mode {
        case .soft:
            // Mark all instances as soft-deleted
            for instanceUID in instanceKeys {
                let key = softDeleteKey(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                softDeletedInstances.insert(key)
            }
            return count
            
        case .permanent:
            // Remove soft-delete marks
            for instanceUID in instanceKeys {
                let key = softDeleteKey(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                softDeletedInstances.remove(key)
            }
            
            // Permanently delete the series
            studies[studyUID]?.series.removeValue(forKey: seriesUID)
            
            // Clean up empty studies
            if studies[studyUID]?.series.isEmpty ?? false {
                studies.removeValue(forKey: studyUID)
            }
            
            return count
        }
    }
    
    public func deleteStudy(
        studyUID: String,
        mode: DeletionMode = .permanent
    ) async throws -> Int {
        guard let study = studies[studyUID] else {
            return 0
        }
        
        var count = 0
        for series in study.series.values {
            count += series.instances.count
        }
        
        switch mode {
        case .soft:
            // Mark all instances in the study as soft-deleted
            for (seriesUID, series) in study.series {
                for instanceUID in series.instances.keys {
                    let key = softDeleteKey(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                    softDeletedInstances.insert(key)
                }
            }
            return count
            
        case .permanent:
            // Remove all soft-delete marks for this study
            for (seriesUID, series) in study.series {
                for instanceUID in series.instances.keys {
                    let key = softDeleteKey(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
                    softDeletedInstances.remove(key)
                }
            }
            
            // Permanently delete the study
            studies.removeValue(forKey: studyUID)
            return count
        }
    }
    
    // MARK: - Query Operations
    
    public func searchStudies(query: StorageQuery) async throws -> [StudyRecord] {
        var results: [StudyRecord] = []
        
        for (_, study) in studies {
            if matchesStudyQuery(study: study, query: query) {
                let record = StudyRecord(
                    studyInstanceUID: study.studyInstanceUID,
                    patientName: study.patientName,
                    patientID: study.patientID,
                    patientBirthDate: study.patientBirthDate,
                    patientSex: study.patientSex,
                    studyDate: study.studyDate,
                    studyTime: study.studyTime,
                    accessionNumber: study.accessionNumber,
                    referringPhysicianName: study.referringPhysicianName,
                    studyDescription: study.studyDescription,
                    studyID: study.studyID,
                    modalitiesInStudy: Array(study.modalitiesInStudy),
                    numberOfStudyRelatedSeries: study.series.count,
                    numberOfStudyRelatedInstances: study.series.values.reduce(0) { $0 + $1.instances.count },
                    sopClassesInStudy: Array(study.sopClassesInStudy)
                )
                results.append(record)
            }
        }
        
        // Apply pagination
        let start = min(query.offset, results.count)
        let end = min(start + query.limit, results.count)
        return Array(results[start..<end])
    }
    
    public func searchSeries(studyUID: String?, query: StorageQuery) async throws -> [SeriesRecord] {
        var results: [SeriesRecord] = []
        
        let studiesToSearch = studyUID.map { [$0: studies[$0]] as [String: StudyData?] } ?? studies.mapValues { Optional($0) }
        
        for (studyId, optStudy) in studiesToSearch {
            guard let study = optStudy else { continue }
            
            for (_, series) in study.series {
                if matchesSeriesQuery(series: series, query: query) {
                    let record = SeriesRecord(
                        studyInstanceUID: studyId,
                        seriesInstanceUID: series.seriesInstanceUID,
                        modality: series.modality,
                        seriesNumber: series.seriesNumber,
                        seriesDescription: series.seriesDescription,
                        bodyPartExamined: series.bodyPartExamined,
                        seriesDate: series.seriesDate,
                        seriesTime: series.seriesTime,
                        performingPhysicianName: series.performingPhysicianName,
                        numberOfSeriesRelatedInstances: series.instances.count
                    )
                    results.append(record)
                }
            }
        }
        
        // Apply pagination
        let start = min(query.offset, results.count)
        let end = min(start + query.limit, results.count)
        return Array(results[start..<end])
    }
    
    public func searchInstances(
        studyUID: String?,
        seriesUID: String?,
        query: StorageQuery
    ) async throws -> [InstanceRecord] {
        var results: [InstanceRecord] = []
        
        let studiesToSearch = studyUID.map { [$0: studies[$0]] as [String: StudyData?] } ?? studies.mapValues { Optional($0) }
        
        for (studyId, optStudy) in studiesToSearch {
            guard let study = optStudy else { continue }
            
            let seriesToSearch = seriesUID.map { [$0: study.series[$0]] as [String: SeriesData?] } ?? study.series.mapValues { Optional($0) }
            
            for (_, optSeries) in seriesToSearch {
                guard let series = optSeries else { continue }
                
                for (_, instance) in series.instances {
                    if matchesInstanceQuery(instance: instance, query: query) {
                        let record = InstanceRecord(
                            studyInstanceUID: studyId,
                            seriesInstanceUID: instance.seriesUID,
                            sopInstanceUID: instance.instanceUID,
                            sopClassUID: instance.sopClassUID,
                            transferSyntaxUID: instance.transferSyntaxUID
                        )
                        results.append(record)
                    }
                }
            }
        }
        
        // Apply pagination
        let start = min(query.offset, results.count)
        let end = min(start + query.limit, results.count)
        return Array(results[start..<end])
    }
    
    // MARK: - Metadata Operations
    
    public func getInstanceMetadata(
        studyUID: String,
        seriesUID: String,
        instanceUID: String
    ) async throws -> DataSet? {
        guard let data = try await getInstance(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID) else {
            return nil
        }
        
        // Parse and return without pixel data
        guard let dicomFile = try? DICOMFile.read(from: data, force: true) else {
            return nil
        }
        
        var metadata = dicomFile.dataSet
        // Remove pixel data for metadata response by setting to nil
        metadata[Tag.pixelData] = nil
        return metadata
    }
    
    public func getSeriesMetadata(
        studyUID: String,
        seriesUID: String
    ) async throws -> [DataSet] {
        let instances = try await getSeriesInstances(studyUID: studyUID, seriesUID: seriesUID)
        return instances.compactMap { instance -> DataSet? in
            guard let dicomFile = try? DICOMFile.read(from: instance.data, force: true) else {
                return nil
            }
            var dataSet = dicomFile.dataSet
            dataSet[Tag.pixelData] = nil
            return dataSet
        }
    }
    
    public func getStudyMetadata(studyUID: String) async throws -> [DataSet] {
        let instances = try await getStudyInstances(studyUID: studyUID)
        return instances.compactMap { instance -> DataSet? in
            guard let dicomFile = try? DICOMFile.read(from: instance.data, force: true) else {
                return nil
            }
            var dataSet = dicomFile.dataSet
            dataSet[Tag.pixelData] = nil
            return dataSet
        }
    }
    
    // MARK: - Statistics
    
    public func countStudies(query: StorageQuery) async throws -> Int {
        var count = 0
        for (_, study) in studies {
            if matchesStudyQuery(study: study, query: query) {
                count += 1
            }
        }
        return count
    }
    
    public func countSeries(studyUID: String) async throws -> Int {
        return studies[studyUID]?.series.count ?? 0
    }
    
    public func countInstances(studyUID: String, seriesUID: String) async throws -> Int {
        return studies[studyUID]?.series[seriesUID]?.instances.count ?? 0
    }
    
    // MARK: - Private Types
    
    private struct StudyData {
        let studyInstanceUID: String
        var patientName: String?
        var patientID: String?
        var patientBirthDate: String?
        var patientSex: String?
        var studyDate: String?
        var studyTime: String?
        var studyDescription: String?
        var studyID: String?
        var accessionNumber: String?
        var referringPhysicianName: String?
        var modalitiesInStudy: Set<String> = []
        var sopClassesInStudy: Set<String> = []
        var series: [String: SeriesData] = [:]
    }
    
    private struct SeriesData {
        let seriesInstanceUID: String
        var modality: String?
        var seriesNumber: Int?
        var seriesDescription: String?
        var bodyPartExamined: String?
        var seriesDate: String?
        var seriesTime: String?
        var performingPhysicianName: String?
        var instances: [String: InstanceInfo] = [:]
    }
    
    private struct ExtractedMetadata {
        var sopClassUID: String?
        var transferSyntaxUID: String?
        var patientName: String?
        var patientID: String?
        var studyDate: String?
        var studyTime: String?
        var studyDescription: String?
        var accessionNumber: String?
        var referringPhysicianName: String?
        var modality: String?
        var seriesNumber: Int?
        var seriesDescription: String?
    }
    
    // MARK: - Private Methods
    
    private func extractMetadata(from data: Data) -> ExtractedMetadata {
        var metadata = ExtractedMetadata()
        
        // Try to parse the DICOM data
        guard let dicomFile = try? DICOMFile.read(from: data, force: true) else {
            return metadata
        }
        
        let dataSet = dicomFile.dataSet
        let fileMetaInfo = dicomFile.fileMetaInformation
        
        // Extract key fields
        metadata.sopClassUID = dataSet.string(for: Tag.sopClassUID) ?? fileMetaInfo.string(for: Tag.mediaStorageSOPClassUID)
        metadata.transferSyntaxUID = fileMetaInfo.string(for: Tag.transferSyntaxUID)
        metadata.patientName = dataSet.string(for: Tag.patientName)
        metadata.patientID = dataSet.string(for: Tag.patientID)
        metadata.studyDate = dataSet.string(for: Tag.studyDate)
        metadata.studyTime = dataSet.string(for: Tag.studyTime)
        metadata.studyDescription = dataSet.string(for: Tag.studyDescription)
        metadata.accessionNumber = dataSet.string(for: Tag.accessionNumber)
        metadata.referringPhysicianName = dataSet.string(for: Tag.referringPhysicianName)
        metadata.modality = dataSet.string(for: Tag.modality)
        metadata.seriesNumber = dataSet.integerString(for: Tag.seriesNumber)?.value
        metadata.seriesDescription = dataSet.string(for: Tag.seriesDescription)
        
        return metadata
    }
    
    private func matchesStudyQuery(study: StudyData, query: StorageQuery) -> Bool {
        // Study Instance UID exact match
        if let uid = query.studyInstanceUID, study.studyInstanceUID != uid {
            return false
        }
        
        // Patient name wildcard match
        if let pattern = query.patientName {
            guard let name = study.patientName, matchesWildcard(value: name, pattern: pattern, fuzzy: query.fuzzyMatching) else {
                return false
            }
        }
        
        // Patient ID wildcard match
        if let pattern = query.patientID {
            guard let id = study.patientID, matchesWildcard(value: id, pattern: pattern, fuzzy: query.fuzzyMatching) else {
                return false
            }
        }
        
        // Accession number match
        if let acc = query.accessionNumber, study.accessionNumber != acc {
            return false
        }

        // Study ID
        if let id = query.studyID, study.studyID != id {
            return false
        }

        // Study Date / Time — DA/TM single value or range (PS3.4 C.2.2.2.5)
        if let range = query.studyDate, !range.contains(dicomValue: study.studyDate) {
            return false
        }
        if let range = query.studyTime, !range.contains(dicomValue: study.studyTime, format: "HHmmss") {
            return false
        }

        // Study Description / Referring Physician — wildcard
        if let pattern = query.studyDescription {
            guard let desc = study.studyDescription,
                  matchesWildcard(value: desc, pattern: pattern, fuzzy: query.fuzzyMatching) else {
                return false
            }
        }
        if let pattern = query.referringPhysicianName {
            guard let name = study.referringPhysicianName,
                  matchesWildcard(value: name, pattern: pattern, fuzzy: query.fuzzyMatching) else {
                return false
            }
        }
        
        // Modalities in study
        if let modalities = query.modalitiesInStudy {
            let intersection = Set(modalities).intersection(study.modalitiesInStudy)
            if intersection.isEmpty {
                return false
            }
        }
        
        return true
    }
    
    private func matchesSeriesQuery(series: SeriesData, query: StorageQuery) -> Bool {
        // Series Instance UID exact match
        if let uid = query.seriesInstanceUID, series.seriesInstanceUID != uid {
            return false
        }
        
        // Modality match
        if let modality = query.modality, series.modality != modality {
            return false
        }
        
        // Series number match
        if let num = query.seriesNumber, series.seriesNumber != num {
            return false
        }

        if let pattern = query.seriesDescription {
            guard let desc = series.seriesDescription,
                  matchesWildcard(value: desc, pattern: pattern, fuzzy: query.fuzzyMatching) else {
                return false
            }
        }
        if let bodyPart = query.bodyPartExamined, series.bodyPartExamined != bodyPart {
            return false
        }
        
        return true
    }
    
    private func matchesInstanceQuery(instance: InstanceInfo, query: StorageQuery) -> Bool {
        // SOP Instance UID exact match
        if let uid = query.sopInstanceUID, instance.instanceUID != uid {
            return false
        }
        if let classUID = query.sopClassUID, instance.sopClassUID != classUID {
            return false
        }
        // Instance Number is not indexed by the in-memory provider; a filter on it
        // cannot be honoured here and is ignored (persistent providers match it).
        
        return true
    }
    
    private func matchesWildcard(value: String, pattern: String, fuzzy: Bool) -> Bool {
        // If fuzzy matching, use contains
        if fuzzy {
            let searchTerm = pattern.replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "?", with: "")
            return value.localizedCaseInsensitiveContains(searchTerm)
        }
        
        // Simple wildcard matching: * matches any sequence, ? matches single char
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        
        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: .caseInsensitive) else {
            return value == pattern
        }
        
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}

// MARK: - Convenience for Testing

extension InMemoryStorageProvider {
    /// Number of studies stored
    public var studyCount: Int {
        studies.count
    }
    
    /// Number of total instances stored
    public var instanceCount: Int {
        studies.values.reduce(0) { sum, study in
            sum + study.series.values.reduce(0) { $0 + $1.instances.count }
        }
    }
    
    /// All study UIDs
    public var studyUIDs: [String] {
        Array(studies.keys)
    }
}
