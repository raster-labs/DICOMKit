import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — the 4 level values text-diffed against PS3.4 2026a Table C.6.1-1 (Scripts/diff_network.py): 4 of 4 match

/// Query Level for C-FIND operations
///
/// Specifies the level of the Query/Retrieve hierarchy at which matching is to be performed.
///
/// Reference: PS3.4 Section C.3 - Query/Retrieve Information Model
public enum QueryLevel: String, Sendable, Hashable, CaseIterable {
    /// Patient level - query for patients
    case patient = "PATIENT"
    
    /// Study level - query for studies
    case study = "STUDY"
    
    /// Series level - query for series
    case series = "SERIES"
    
    /// Image (Instance) level - query for individual images/instances
    case image = "IMAGE"
    
    /// The value to set in the Query/Retrieve Level tag
    public var queryRetrieveLevel: String {
        rawValue
    }
}

// MARK: - CustomStringConvertible

extension QueryLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .patient: return "PATIENT"
        case .study: return "STUDY"
        case .series: return "SERIES"
        case .image: return "IMAGE"
        }
    }
}
