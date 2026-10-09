import Foundation
// NEMA-verified: 2026a, checked 2026-10-01 — CLI resume state; the study row's key `ModalitiesInStudy` is the PS3.6 2026a Table 6-1 keyword of (0008,0061), the STUDY-level return key of PS3.4 Table C.6-5 (P-QR-STATE-MODALITIES; the old `modality` key, (0008,0060), is kept)

// Shared save-state model for `dicom-qr` — the JSON written by `--save-state`
// and consumed by `dicom-qr resume`. Lives in DICOMNetwork so the CLI and
// DICOMStudio's Workshop read/write the SAME format (a state saved on either
// surface resumes on the other).

/// One study row captured from a C-FIND result set.
public struct QRStudyInfo: Codable, Sendable {
    public let studyInstanceUID: String?
    public let patientName: String?
    public let patientID: String?
    public let studyDate: String?
    public let studyDescription: String?
    public let accessionNumber: String?
    /// Modality (0008,0060), a Series-level attribute: nil unless the SCP
    /// volunteered it in a STUDY-level response.
    ///
    /// Deprecated as the study's modality: a STUDY-level C-FIND returns
    /// Modalities in Study (0008,0061) (PS3.4 Table C.6-5), stored under the
    /// PS3.6 keyword key `ModalitiesInStudy` (``modalitiesInStudy``). The JSON
    /// key `modality` is still written, with the same value as before, so
    /// older readers keep working.
    public let modality: String?
    /// Modalities in Study (0008,0061) of the STUDY-level C-FIND response
    /// (PS3.4 Table C.6-5), multiple values joined by `\`. JSON key
    /// `ModalitiesInStudy` (PS3.6 keyword); absent in files written before
    /// 2026-10-01, which decode it as nil.
    public let modalitiesInStudy: String?

    enum CodingKeys: String, CodingKey {
        case studyInstanceUID, patientName, patientID, studyDate, studyDescription, accessionNumber, modality
        case modalitiesInStudy = "ModalitiesInStudy"
    }

    public init(from result: GenericQueryResult) {
        self.studyInstanceUID = result.studyInstanceUID
        self.patientName = result.patientName
        self.patientID = result.patientID
        self.studyDate = result.studyDate
        self.studyDescription = result.studyDescription
        self.accessionNumber = result.accessionNumber
        self.modality = result.modality
        self.modalitiesInStudy = result.toStudyResult().modalitiesInStudy
    }
}

/// State saved by `--save-state` in review mode (query results only).
public struct QRQueryState: Codable, Sendable {
    public let studies: [QRStudyInfo]

    public init(results: [GenericQueryResult]) {
        self.studies = results.map(QRStudyInfo.init(from:))
    }
}

/// C-MOVE vs C-GET, as spelled on the CLI.
public enum QRRetrievalMethod: String, Codable, Sendable {
    case cMove = "c-move"
    case cGet = "c-get"
}

/// State saved by `--save-state` before a retrieval — everything `resume`
/// needs to continue.
public struct QRRetrievalState: Codable, Sendable {
    public let studies: [QRStudyInfo]
    public let host: String
    public let port: UInt16
    public let callingAE: String
    public let calledAE: String
    public let moveDestination: String?
    public let method: QRRetrievalMethod
    public let outputPath: String
    public let hierarchical: Bool

    public init(
        studies: [QRStudyInfo], host: String, port: UInt16,
        callingAE: String, calledAE: String, moveDestination: String?,
        method: QRRetrievalMethod, outputPath: String, hierarchical: Bool
    ) {
        self.studies = studies; self.host = host; self.port = port
        self.callingAE = callingAE; self.calledAE = calledAE
        self.moveDestination = moveDestination; self.method = method
        self.outputPath = outputPath; self.hierarchical = hierarchical
    }
}

public enum QRSessionState {
    /// Serializes a state value with the CLI's canonical formatting
    /// (pretty-printed, sorted keys) so both surfaces write identical bytes.
    public static func encode(_ state: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    public static func decodeRetrievalState(_ data: Data) throws -> QRRetrievalState {
        try JSONDecoder().decode(QRRetrievalState.self, from: data)
    }

    public static func decodeQueryState(_ data: Data) throws -> QRQueryState {
        try JSONDecoder().decode(QRQueryState.self, from: data)
    }
}

// Study-level convenience accessors shared by dicom-qr and the app.
public extension GenericQueryResult {
    var studyInstanceUID: String? { uid(for: .studyInstanceUID) }
    var patientName: String? { string(for: .patientName) }
    var patientID: String? { string(for: .patientID) }
    var studyDate: String? { string(for: .studyDate) }
    var studyDescription: String? { string(for: .studyDescription) }
    var accessionNumber: String? { string(for: .accessionNumber) }
    var modality: String? { string(for: .modality) }
}
