import Foundation
import DICOMCore
import DICOMNetwork
// NEMA-verified: 2026a, checked 2026-10-01 — Information Model choice checked against PS3.4 2026a C.6.1 / C.6.2: PATIENT level → Patient Root (Table C.6.1-1), STUDY/SERIES/IMAGE → Study Root (Table C.6.2-1); the key tables themselves live in DICOMNetwork.DICOMQueryService.buildQueryKeys

#if canImport(Network)

/// Executes C-FIND queries against a DICOM PACS server
struct QueryExecutor {
    let host: String
    let port: UInt16
    let callingAE: String
    let calledAE: String
    let timeout: TimeInterval
    
    /// Executes a C-FIND query and returns results
    func executeQuery(level: QueryLevel, queryKeys: QueryKeys) async throws -> [GenericQueryResult] {
        let configuration = try buildConfiguration(level: level)
        
        return try await DICOMQueryService.find(
            host: host,
            port: port,
            configuration: configuration,
            queryKeys: queryKeys
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func buildConfiguration(level: QueryLevel) throws -> QueryConfiguration {
        let informationModel: QueryRetrieveInformationModel = (level == .patient) ? .patientRoot : .studyRoot
        return QueryConfiguration(
            callingAETitle: try AETitle(callingAE),
            calledAETitle: try AETitle(calledAE),
            timeout: timeout,
            informationModel: informationModel
        )
    }
}

#endif
