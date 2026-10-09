import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — LOW/MEDIUM/HIGH text-diffed against PS3.7 2026a Table E.1-1 (0000,0700) (Scripts/diff_network.py): 3 of 3 match; the value is defined in PS3.7 §9.1.x, not PS3.4

/// Priority level for DIMSE operations
///
/// Reference: PS3.7 Section 9.1.1
public enum DIMSEPriority: UInt16, Sendable, Hashable, Codable {
    /// Low priority (0x0002)
    case low = 0x0002
    
    /// Medium priority (0x0000)
    case medium = 0x0000
    
    /// High priority (0x0001)
    case high = 0x0001
}

// MARK: - CustomStringConvertible
extension DIMSEPriority: CustomStringConvertible {
    public var description: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        }
    }
}

// MARK: - Default
extension DIMSEPriority {
    /// Default priority is medium
    public static var `default`: DIMSEPriority { .medium }
}
