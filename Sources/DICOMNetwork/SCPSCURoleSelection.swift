import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — sub-item layout and role bytes compared with PS3.7 2026a Tables D.3-9 / D.3-10 and the default-role rule of D.3.3.4: match

/// SCP/SCU Role Selection Sub-Item (0x54)
///
/// Carried in the User Information Item of A-ASSOCIATE-RQ and A-ASSOCIATE-AC.
/// The requestor proposes, per Abstract Syntax, whether it wants to act as SCU,
/// SCP, or both; the acceptor replies with the roles it grants, which may only
/// reduce what was proposed. When the acceptor omits the sub-item for a SOP
/// Class, the default roles apply (requestor = SCU, acceptor = SCP).
///
/// Mandatory for C-GET (PS3.4 C.4.3.1.1 / C.5.3: the C-GET SCU must be SCP for
/// every Storage SOP Class it wants to receive) and for same-association
/// Storage Commitment N-EVENT-REPORT (PS3.4 J.3.3).
///
/// Reference: PS3.7 Section D.3.3.4 - SCP/SCU Role Selection Negotiation
public struct SCPSCURoleSelection: Sendable, Hashable {
    /// Sub-item type byte for SCP/SCU Role Selection
    public static let subItemType: UInt8 = 0x54

    /// The SOP Class (Abstract Syntax) UID the roles apply to
    public let sopClassUID: String

    /// Whether the requestor proposes (RQ) / is granted (AC) the SCU role
    public let scuRole: Bool

    /// Whether the requestor proposes (RQ) / is granted (AC) the SCP role
    public let scpRole: Bool

    /// Creates a role selection entry
    ///
    /// - Parameters:
    ///   - sopClassUID: The SOP Class UID
    ///   - scuRole: Requestor acts as SCU for this SOP Class
    ///   - scpRole: Requestor acts as SCP for this SOP Class
    public init(sopClassUID: String, scuRole: Bool, scpRole: Bool) {
        self.sopClassUID = sopClassUID
        self.scuRole = scuRole
        self.scpRole = scpRole
    }

    /// Convenience: requestor wants both roles (typical for C-GET storage contexts)
    public static func both(_ sopClassUID: String) -> SCPSCURoleSelection {
        SCPSCURoleSelection(sopClassUID: sopClassUID, scuRole: true, scpRole: true)
    }

    /// Convenience: requestor wants only the SCP role
    public static func scpOnly(_ sopClassUID: String) -> SCPSCURoleSelection {
        SCPSCURoleSelection(sopClassUID: sopClassUID, scuRole: false, scpRole: true)
    }

    /// Encodes the sub-item (PS3.7 Table D.3-9 / D.3-10)
    ///
    /// Layout: type(1) reserved(1) length(2) uidLength(2) uid(n) scuRole(1) scpRole(1)
    public func encode() -> Data {
        var subItem = Data()
        let uidData = Data(sopClassUID.utf8)

        subItem.append(SCPSCURoleSelection.subItemType)
        subItem.append(0x00)
        let length = UInt16(2 + uidData.count + 2)
        subItem.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })

        let uidLength = UInt16(uidData.count)
        subItem.append(contentsOf: withUnsafeBytes(of: uidLength.bigEndian) { Array($0) })
        subItem.append(uidData)
        subItem.append(scuRole ? 1 : 0)
        subItem.append(scpRole ? 1 : 0)
        return subItem
    }

    /// Decodes the payload of a 0x54 sub-item (bytes after the 4-byte header)
    public static func decode(from data: Data) throws -> SCPSCURoleSelection {
        guard data.count >= 4 else {
            throw DICOMNetworkError.decodingFailed("SCP/SCU Role Selection sub-item too short")
        }
        let start = data.startIndex
        let uidLength = Int(UInt16(data[start]) << 8 | UInt16(data[start + 1]))
        guard data.count >= 2 + uidLength + 2 else {
            throw DICOMNetworkError.decodingFailed("SCP/SCU Role Selection sub-item truncated")
        }
        let uidStart = start + 2
        let uidData = data[uidStart ..< uidStart + uidLength]
        let uid = (String(data: uidData, encoding: .ascii) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        let scu = data[uidStart + uidLength] != 0
        let scp = data[uidStart + uidLength + 1] != 0
        return SCPSCURoleSelection(sopClassUID: uid, scuRole: scu, scpRole: scp)
    }
}

extension SCPSCURoleSelection: CustomStringConvertible {
    public var description: String {
        "RoleSelection(\(sopClassUID) scu=\(scuRole) scp=\(scpRole))"
    }
}

/// The roles in effect for one SOP Class on an established association,
/// from the requestor's point of view (PS3.7 D.3.3.4.2).
public struct NegotiatedRoles: Sendable, Hashable {
    /// Requestor may act as SCU for the SOP Class
    public let requestorIsSCU: Bool
    /// Requestor may act as SCP for the SOP Class
    public let requestorIsSCP: Bool

    public init(requestorIsSCU: Bool, requestorIsSCP: Bool) {
        self.requestorIsSCU = requestorIsSCU
        self.requestorIsSCP = requestorIsSCP
    }

    /// Default roles when no role selection was negotiated
    public static let `default` = NegotiatedRoles(requestorIsSCU: true, requestorIsSCP: false)

    /// Resolves the roles for a SOP Class from what was proposed and what the
    /// acceptor answered. The acceptor may only reduce the proposed roles; an
    /// answer for a class that was not proposed, or no answer at all, yields the
    /// default roles.
    public static func resolve(
        proposed: [SCPSCURoleSelection],
        accepted: [SCPSCURoleSelection],
        sopClassUID: String
    ) -> NegotiatedRoles {
        guard let rq = proposed.first(where: { $0.sopClassUID == sopClassUID }),
              let ac = accepted.first(where: { $0.sopClassUID == sopClassUID }) else {
            return .default
        }
        return NegotiatedRoles(
            requestorIsSCU: rq.scuRole && ac.scuRole,
            requestorIsSCP: rq.scpRole && ac.scpRole
        )
    }
}

extension Array where Element == SCPSCURoleSelection {
    /// Builds the acceptor's answer to proposed role selections (PS3.7 D.3.3.4.2).
    ///
    /// For each proposed SOP Class, the requestor's SCP role is granted only when
    /// the acceptor is willing to act as SCU for that class (`acceptSCPRoleFor`),
    /// and the requestor's SCU role is granted only when the acceptor can act as
    /// SCP for it (`acceptSCURoleFor`). Classes the acceptor does not know are
    /// answered with both roles refused.
    public func acceptorResponse(
        acceptSCURoleFor: (String) -> Bool,
        acceptSCPRoleFor: (String) -> Bool
    ) -> [SCPSCURoleSelection] {
        map { proposed in
            SCPSCURoleSelection(
                sopClassUID: proposed.sopClassUID,
                scuRole: proposed.scuRole && acceptSCURoleFor(proposed.sopClassUID),
                scpRole: proposed.scpRole && acceptSCPRoleFor(proposed.sopClassUID)
            )
        }
    }
}
