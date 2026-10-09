import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — the maximum-length semantics of PS3.8 2026a Annex D.1 (0 = no maximum); the default and minimum sizes are implementation choices and say so

/// Protocol for all DICOM Protocol Data Units (PDUs)
///
/// Reference: PS3.8 Section 9 - Protocol Data Units
public protocol PDU: Sendable {
    /// The PDU type code
    var pduType: PDUType { get }
    
    /// Encodes the PDU to binary data for network transmission
    func encode() throws -> Data
}

/// Default Maximum Length (P-DATA-TF size) this implementation proposes (64 KB)
///
/// This is an implementation choice, not a value defined by the standard.
/// PS3.8 Annex D.1 (Table D.1-1) only defines the field: the Maximum Length
/// Received sub-item tells the peer the largest P-DATA-TF PDU it may send,
/// and the value 0 "indicates that no maximum length is specified". A larger
/// size improves throughput for bulk transfers (C-FIND, C-STORE, etc.) and
/// 64 KB is widely supported by contemporary DICOM implementations.
///
/// Reference: PS3.8 Annex D.1 - Maximum Length Negotiation
public let defaultMaxPDUSize: UInt32 = 65536

/// Smallest Maximum Length this implementation considers practical (4 KB)
///
/// An implementation choice; PS3.8 Annex D.1 sets no lower bound.
public let minimumPDUSize: UInt32 = 4096

/// Largest value the 4-byte Maximum Length Received field can carry
///
/// PS3.8 Annex D.1 Table D.1-1: the field is an unsigned 32-bit number.
public let maximumPDUSize: UInt32 = 0xFFFFFFFF

/// Resolves the P-DATA-TF size limit to apply towards a peer.
///
/// PS3.8 Annex D.1: a Maximum Length of 0 means "no maximum length is
/// specified", so a peer value of 0 must not be treated as a limit of zero
/// bytes; this implementation then uses its own configured value.
///
/// - Parameters:
///   - local: This side's configured maximum PDU size (0 = unlimited)
///   - remote: The peer's Maximum Length Received (0 = unlimited)
/// - Returns: The size to fragment P-DATA-TF PDUs to
func negotiatedMaxPDUSize(local: UInt32, remote: UInt32) -> UInt32 {
    if remote == 0 { return local }
    if local == 0 { return remote }
    return min(local, remote)
}

/// Checks an incoming PDU against this side's Maximum Length.
///
/// PS3.8 Annex D.1: the negotiated Maximum Length governs only the
/// P-DATA-TF PDUs the peer sends. An A-ASSOCIATE-RQ/AC with many
/// presentation contexts is bounded only by `PDUDecoder.maximumPDULength`,
/// and a local maximum of 0 means no limit.
///
/// - Throws: `DICOMNetworkError.pduTooLarge` for an over-sized P-DATA-TF
func checkPDULength(type: PDUType, length: UInt32, maxPDUSize: UInt32) throws {
    guard type == .dataTransfer, maxPDUSize != 0, length > maxPDUSize else { return }
    throw DICOMNetworkError.pduTooLarge(received: length, maximum: maxPDUSize)
}

/// Validates the Implementation Class UID / Version Name user-information
/// sub-items before an A-ASSOCIATE-RQ/AC is encoded.
///
/// PS3.7 Table D.3-3/D.3-4: the Implementation Version Name is "a string of
/// 1 to 16 ISO 646:1990 (basic G0 set) characters"; PS3.5 Table 6.2-1: a UI
/// value is at most 64 bytes.
///
/// - Throws: `DICOMNetworkError.encodingFailed` when a limit is exceeded
func validateImplementationSubItems(classUID: String, versionName: String?) throws {
    guard classUID.utf8.count <= 64 else {
        throw DICOMNetworkError.encodingFailed(
            "Implementation Class UID exceeds 64 bytes (\(classUID.utf8.count))")
    }
    if let versionName {
        let length = versionName.utf8.count
        guard (1...16).contains(length) else {
            throw DICOMNetworkError.encodingFailed(
                "Implementation Version Name must be 1-16 characters (got \(length))")
        }
    }
}
