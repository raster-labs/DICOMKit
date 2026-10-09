import Foundation
// NEMA-verified: 2026a, checked 2026-10-01 — sub-item layout compared with PS3.7 2026a Table D.3-11 (item type 56H, reserved, item length, SOP-class-uid-length, SOP-class-uid, Service-class-application-information); the Query/Retrieve retrieval bytes with PS3.4 2026a Tables C.5-3 (RQ) / C.5-4 (AC) (byte 1 Relational-retrieval, byte 2 Enhanced Multi-Frame Image Conversion) and the single-byte / default rules of C.5.2.1 / C.5.3.1

/// SOP Class Extended Negotiation Sub-Item (0x56)
///
/// Carried in the User Information Item of A-ASSOCIATE-RQ and A-ASSOCIATE-AC.
/// The requestor offers, per SOP Class, a Service-class-application-information
/// field whose meaning is defined by the Service Class (for Query/Retrieve see
/// ``RetrieveExtendedNegotiation``); the acceptor answers with the subset it
/// supports. Absent an answer, the default (baseline) behaviour applies.
///
/// Reference: PS3.7 Section D.3.3.5, Table D.3-11
public struct SOPClassExtendedNegotiation: Sendable, Hashable {
    /// Sub-item type byte for SOP Class Extended Negotiation (PS3.7 Table D.3-11: 56H)
    public static let subItemType: UInt8 = 0x56

    /// The SOP Class (Abstract Syntax) UID the information applies to
    public let sopClassUID: String

    /// The Service-class-application-information field, as defined by the Service Class
    public let serviceClassApplicationInformation: Data

    public init(sopClassUID: String, serviceClassApplicationInformation: Data) {
        self.sopClassUID = sopClassUID
        self.serviceClassApplicationInformation = serviceClassApplicationInformation
    }

    /// Encodes the sub-item (PS3.7 Table D.3-11)
    ///
    /// Layout: type(1) reserved(1) length(2) uidLength(2) uid(n) info(m)
    public func encode() -> Data {
        var subItem = Data()
        let uidData = Data(sopClassUID.utf8)
        subItem.append(SOPClassExtendedNegotiation.subItemType)
        subItem.append(0x00)
        let length = UInt16(2 + uidData.count + serviceClassApplicationInformation.count)
        subItem.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
        let uidLength = UInt16(uidData.count)
        subItem.append(contentsOf: withUnsafeBytes(of: uidLength.bigEndian) { Array($0) })
        subItem.append(uidData)
        subItem.append(serviceClassApplicationInformation)
        return subItem
    }

    /// Decodes the payload of a 0x56 sub-item (bytes after the 4-byte header)
    public static func decode(from data: Data) throws -> SOPClassExtendedNegotiation {
        guard data.count >= 2 else {
            throw DICOMNetworkError.decodingFailed("SOP Class Extended Negotiation sub-item too short")
        }
        let start = data.startIndex
        let uidLength = Int(UInt16(data[start]) << 8 | UInt16(data[start + 1]))
        guard data.count >= 2 + uidLength else {
            throw DICOMNetworkError.decodingFailed("SOP Class Extended Negotiation sub-item truncated")
        }
        let uidStart = start + 2
        let uid = (String(data: data[uidStart ..< uidStart + uidLength], encoding: .ascii) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        let info = Data(data[(uidStart + uidLength)...])
        return SOPClassExtendedNegotiation(sopClassUID: uid, serviceClassApplicationInformation: info)
    }
}

/// The Service-class-application-information of the Query/Retrieve retrieval
/// SOP Classes (C-MOVE and C-GET).
///
/// Reference: PS3.4 Sections C.5.2.1 / C.5.3.1, Tables C.5-3 (A-ASSOCIATE-RQ)
/// and C.5-4 (A-ASSOCIATE-AC):
///  - byte 1, Relational-retrieval: 0 not supported, 1 supported
///  - byte 2, Enhanced Multi-Frame Image Conversion: 0 Query/Retrieve View not
///    supported, 1 supported
///
/// If the acceptor returns no sub-item both are unsupported (the default); a
/// one-byte answer to a two-byte offer means byte 2 is 0.
public struct RetrieveExtendedNegotiation: Sendable, Hashable {
    /// Byte 1: relational-retrieval (PS3.4 C.4.2.2.2.1 / C.4.3.2.2.1)
    public let relationalRetrieval: Bool
    /// Byte 2: Enhanced Multi-Frame Image Conversion (Query/Retrieve View (0008,0053))
    public let enhancedMultiFrameImageConversion: Bool

    public init(relationalRetrieval: Bool, enhancedMultiFrameImageConversion: Bool = false) {
        self.relationalRetrieval = relationalRetrieval
        self.enhancedMultiFrameImageConversion = enhancedMultiFrameImageConversion
    }

    /// The default condition when no sub-item is negotiated (PS3.4 C.5.2.1).
    public static let baseline = RetrieveExtendedNegotiation(relationalRetrieval: false)

    /// The Service-class-application-information bytes. Only byte 1 is sent
    /// unless byte 2 is requested, so an acceptor that knows only the original
    /// single byte still answers with one byte (PS3.4 C.5.2.1).
    public var serviceClassApplicationInformation: Data {
        enhancedMultiFrameImageConversion
            ? Data([relationalRetrieval ? 1 : 0, 1])
            : Data([relationalRetrieval ? 1 : 0])
    }

    /// The sub-item proposing this information for a retrieval SOP Class.
    public func subItem(for sopClassUID: String) -> SOPClassExtendedNegotiation {
        SOPClassExtendedNegotiation(sopClassUID: sopClassUID,
                                    serviceClassApplicationInformation: serviceClassApplicationInformation)
    }

    /// Reads the acceptor's answer (PS3.4 Table C.5-4); missing bytes are 0.
    public init(serviceClassApplicationInformation info: Data) {
        let bytes = Array(info)
        self.relationalRetrieval = bytes.count > 0 && bytes[0] == 1
        self.enhancedMultiFrameImageConversion = bytes.count > 1 && bytes[1] == 1
    }

    /// What is in effect for a SOP Class: the acceptor may only turn down what
    /// was offered; no answer yields ``baseline`` (PS3.4 C.5.2.1).
    public static func negotiated(
        proposed: RetrieveExtendedNegotiation?,
        accepted: [SOPClassExtendedNegotiation],
        sopClassUID: String
    ) -> RetrieveExtendedNegotiation {
        guard let proposed,
              let answer = accepted.first(where: { $0.sopClassUID == sopClassUID }) else {
            return .baseline
        }
        let ac = RetrieveExtendedNegotiation(serviceClassApplicationInformation: answer.serviceClassApplicationInformation)
        return RetrieveExtendedNegotiation(
            relationalRetrieval: proposed.relationalRetrieval && ac.relationalRetrieval,
            enhancedMultiFrameImageConversion: proposed.enhancedMultiFrameImageConversion && ac.enhancedMultiFrameImageConversion
        )
    }
}
