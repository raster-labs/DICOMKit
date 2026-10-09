import Foundation
// NEMA-verified: 2026a, checked 2026-10-01 — Implementation Class UID per PS3.7 2026a D.3.3.2 (A-ASSOCIATE-RQ/-AC Implementation Class UID sub-item) and PS3.5 2026a 9.2.2 (a privately defined UID under a root the organisation owns): DICOMKit's root 1.2.826.0.1.3680043.10.511, the value of DICOMFile.implementationClassUID (D155)

/// The implementation identity DICOMNetwork advertises in the A-ASSOCIATE-RQ / -AC
/// (PS3.7 D.3.3.2).
///
/// `DICOMNetwork` cannot import `DICOMKit`, so the value is repeated here; a test
/// keeps it equal to `DICOMFile.implementationClassUID`, which the file writers put
/// in (0002,0012) — one implementation, one Implementation Class UID.
public enum DICOMNetworkImplementation {
    /// Implementation Class UID: arc `.3` of DICOMKit's private root
    /// `1.2.826.0.1.3680043.10.511` followed by the library version (0.5.0).
    ///
    /// Before 2026-10-01 every DICOMNetwork configuration defaulted to a UID under
    /// `1.2.826.0.1.3680043.9.7433` (`.1.1` SCU, `.1.2` / `.1.3` SCPs, `.1.4` the
    /// commitment listener), which is not DICOMKit's root (D155).
    public static let classUID = "1.2.826.0.1.3680043.10.511.3.0.5.0"
}
