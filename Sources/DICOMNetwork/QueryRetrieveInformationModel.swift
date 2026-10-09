import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — the 9 SOP Class UIDs checked against PS3.6 2026a Table A-1 and PS3.4 2026a Tables C.6.1.3-1 / C.6.2.3-1 (Scripts/diff_network.py): all registered, the 3 Patient/Study Only classes retired

// MARK: - Query/Retrieve SOP Class UIDs - FIND

/// Patient Root Query/Retrieve Information Model - FIND
///
/// Reference: PS3.4 Annex C.6.1
public let patientRootQueryRetrieveFindSOPClassUID = "1.2.840.10008.5.1.4.1.2.1.1"

/// Study Root Query/Retrieve Information Model - FIND
///
/// Reference: PS3.4 Annex C.6.2
public let studyRootQueryRetrieveFindSOPClassUID = "1.2.840.10008.5.1.4.1.2.2.1"

/// Patient/Study Only Query/Retrieve Information Model - FIND (Retired)
///
/// Reference: PS3.4 Annex C.6.3
public let patientStudyOnlyQueryRetrieveFindSOPClassUID = "1.2.840.10008.5.1.4.1.2.3.1"

// MARK: - Query/Retrieve SOP Class UIDs - MOVE

/// Patient Root Query/Retrieve Information Model - MOVE
///
/// Reference: PS3.4 Annex C.6.1
public let patientRootQueryRetrieveMoveSOPClassUID = "1.2.840.10008.5.1.4.1.2.1.2"

/// Study Root Query/Retrieve Information Model - MOVE
///
/// Reference: PS3.4 Annex C.6.2
public let studyRootQueryRetrieveMoveSOPClassUID = "1.2.840.10008.5.1.4.1.2.2.2"

/// Patient/Study Only Query/Retrieve Information Model - MOVE (Retired)
///
/// Reference: PS3.4 Annex C.6.3
public let patientStudyOnlyQueryRetrieveMoveSOPClassUID = "1.2.840.10008.5.1.4.1.2.3.2"

// MARK: - Query/Retrieve SOP Class UIDs - GET

/// Patient Root Query/Retrieve Information Model - GET
///
/// Reference: PS3.4 Annex C.6.1
public let patientRootQueryRetrieveGetSOPClassUID = "1.2.840.10008.5.1.4.1.2.1.3"

/// Study Root Query/Retrieve Information Model - GET
///
/// Reference: PS3.4 Annex C.6.2
public let studyRootQueryRetrieveGetSOPClassUID = "1.2.840.10008.5.1.4.1.2.2.3"

/// Patient/Study Only Query/Retrieve Information Model - GET (Retired)
///
/// Reference: PS3.4 Annex C.6.3
public let patientStudyOnlyQueryRetrieveGetSOPClassUID = "1.2.840.10008.5.1.4.1.2.3.3"

// MARK: - Query/Retrieve Information Model

/// Query/Retrieve Information Model type
///
/// Defines which information model to use for queries.
///
/// Reference: PS3.4 Section C.6 - Query/Retrieve Service Class
public enum QueryRetrieveInformationModel: Sendable, Hashable {
    /// Patient Root Information Model
    ///
    /// The patient is at the top of the hierarchy.
    /// Supports PATIENT, STUDY, SERIES, and IMAGE query levels.
    case patientRoot
    
    /// Study Root Information Model
    ///
    /// The study is at the top of the hierarchy.
    /// Supports STUDY, SERIES, and IMAGE query levels (not PATIENT).
    case studyRoot
    
    /// The SOP Class UID for C-FIND
    public var findSOPClassUID: String {
        switch self {
        case .patientRoot:
            return patientRootQueryRetrieveFindSOPClassUID
        case .studyRoot:
            return studyRootQueryRetrieveFindSOPClassUID
        }
    }
    
    /// The SOP Class UID for C-MOVE
    public var moveSOPClassUID: String {
        switch self {
        case .patientRoot:
            return patientRootQueryRetrieveMoveSOPClassUID
        case .studyRoot:
            return studyRootQueryRetrieveMoveSOPClassUID
        }
    }
    
    /// The SOP Class UID for C-GET
    public var getSOPClassUID: String {
        switch self {
        case .patientRoot:
            return patientRootQueryRetrieveGetSOPClassUID
        case .studyRoot:
            return studyRootQueryRetrieveGetSOPClassUID
        }
    }
    
    /// The supported query levels for this information model
    public var supportedLevels: [QueryLevel] {
        switch self {
        case .patientRoot:
            return [.patient, .study, .series, .image]
        case .studyRoot:
            return [.study, .series, .image]
        }
    }
    
    /// Whether a query level is supported by this information model
    public func supportsLevel(_ level: QueryLevel) -> Bool {
        supportedLevels.contains(level)
    }
}

// MARK: - CustomStringConvertible

extension QueryRetrieveInformationModel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .patientRoot:
            return "Patient Root"
        case .studyRoot:
            return "Study Root"
        }
    }
}
