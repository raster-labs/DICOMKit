import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — the 5 User-Identity-Type values and the RQ/AC sub-item layouts compared with PS3.7 2026a Tables D.3-14 / D.3-15 (Scripts/diff_network.py): 5 of 5 match; Supplement 99 kept as provenance for types 1-4

/// User Identity Type for DICOM User Identity Negotiation
///
/// Defines the type of user identity being used for authentication during
/// association establishment.
///
/// Reference: PS3.7 Section D.3.3.7 / Table D.3-14 - User Identity Negotiation
/// Provenance: types 1-4 come from Supplement 99; type 5 (JSON Web Token) was added later
/// (PS3.7 2026a Table D.3-14 lists 1-5; the introducing CP is not named in the 2014a-2026c
/// release notes; CP 2405, 2024e, only clarifies that the DIMSE JWT and the DICOMweb token
/// may be the same).
public enum UserIdentityType: UInt8, Sendable, Hashable {
    /// Username only authentication
    case username = 1
    
    /// Username and passcode (password) authentication
    case usernameAndPasscode = 2
    
    /// Kerberos Service Ticket authentication
    case kerberos = 3
    
    /// SAML Assertion authentication
    case saml = 4
    
    /// JSON Web Token (JWT) authentication
    case jwt = 5
}

/// User Identity for DICOM association authentication
///
/// Represents the user identity information that can be included in an
/// A-ASSOCIATE-RQ PDU for authentication purposes.
///
/// Reference: PS3.7 Section D.3.3.7 / Tables D.3-14, D.3-15 - User Identity Negotiation
/// Provenance: Supplement 99 (types 1-4); JWT (type 5) added later, see `UserIdentityType`.
public struct UserIdentity: Sendable, Hashable {
    /// The type of user identity
    public let identityType: UserIdentityType
    
    /// Whether a positive response is requested from the server
    ///
    /// When true, the SCP should send a User Identity Negotiation response
    /// sub-item in the A-ASSOCIATE-AC PDU to confirm authentication.
    public let positiveResponseRequested: Bool
    
    /// The primary field (username, Kerberos ticket, SAML assertion, or JWT)
    public let primaryField: Data
    
    /// The secondary field (passcode/password for usernameAndPasscode type)
    public let secondaryField: Data?
    
    /// Creates a user identity with username only authentication
    ///
    /// - Parameters:
    ///   - username: The username for authentication
    ///   - positiveResponseRequested: Whether to request server confirmation (default: false)
    /// - Returns: A UserIdentity configured for username-only authentication
    public static func username(
        _ username: String,
        positiveResponseRequested: Bool = false
    ) -> UserIdentity {
        UserIdentity(
            identityType: .username,
            positiveResponseRequested: positiveResponseRequested,
            primaryField: Data(username.utf8),
            secondaryField: nil
        )
    }
    
    /// Creates a user identity with username and passcode authentication
    ///
    /// - Parameters:
    ///   - username: The username for authentication
    ///   - passcode: The passcode (password) for authentication
    ///   - positiveResponseRequested: Whether to request server confirmation (default: false)
    /// - Returns: A UserIdentity configured for username and passcode authentication
    public static func usernameAndPasscode(
        username: String,
        passcode: String,
        positiveResponseRequested: Bool = false
    ) -> UserIdentity {
        UserIdentity(
            identityType: .usernameAndPasscode,
            positiveResponseRequested: positiveResponseRequested,
            primaryField: Data(username.utf8),
            secondaryField: Data(passcode.utf8)
        )
    }
    
    /// Creates a user identity with Kerberos authentication
    ///
    /// - Parameters:
    ///   - serviceTicket: The Kerberos service ticket data
    ///   - positiveResponseRequested: Whether to request server confirmation (default: true)
    /// - Returns: A UserIdentity configured for Kerberos authentication
    public static func kerberos(
        serviceTicket: Data,
        positiveResponseRequested: Bool = true
    ) -> UserIdentity {
        UserIdentity(
            identityType: .kerberos,
            positiveResponseRequested: positiveResponseRequested,
            primaryField: serviceTicket,
            secondaryField: nil
        )
    }
    
    /// Creates a user identity with SAML assertion authentication
    ///
    /// - Parameters:
    ///   - assertion: The SAML assertion data
    ///   - positiveResponseRequested: Whether to request server confirmation (default: true)
    /// - Returns: A UserIdentity configured for SAML authentication
    public static func saml(
        assertion: Data,
        positiveResponseRequested: Bool = true
    ) -> UserIdentity {
        UserIdentity(
            identityType: .saml,
            positiveResponseRequested: positiveResponseRequested,
            primaryField: assertion,
            secondaryField: nil
        )
    }
    
    /// Creates a user identity with JWT authentication
    ///
    /// - Parameters:
    ///   - token: The JWT token string
    ///   - positiveResponseRequested: Whether to request server confirmation (default: true)
    /// - Returns: A UserIdentity configured for JWT authentication
    public static func jwt(
        token: String,
        positiveResponseRequested: Bool = true
    ) -> UserIdentity {
        UserIdentity(
            identityType: .jwt,
            positiveResponseRequested: positiveResponseRequested,
            primaryField: Data(token.utf8),
            secondaryField: nil
        )
    }
    
    /// Creates a custom user identity
    ///
    /// - Parameters:
    ///   - identityType: The type of identity
    ///   - positiveResponseRequested: Whether to request server confirmation
    ///   - primaryField: The primary field data
    ///   - secondaryField: The secondary field data (only for usernameAndPasscode)
    public init(
        identityType: UserIdentityType,
        positiveResponseRequested: Bool,
        primaryField: Data,
        secondaryField: Data?
    ) {
        self.identityType = identityType
        self.positiveResponseRequested = positiveResponseRequested
        self.primaryField = primaryField
        self.secondaryField = secondaryField
    }
    
    /// The username if this is a username or username/passcode identity
    public var username: String? {
        guard identityType == .username || identityType == .usernameAndPasscode else {
            return nil
        }
        return String(data: primaryField, encoding: .utf8)
    }
}

/// User Identity Server Response
///
/// Represents the server's response to a user identity negotiation request.
/// This is included in the A-ASSOCIATE-AC PDU when the SCU requested a
/// positive response.
///
/// Reference: PS3.7 Section D.3.3.7.2 - Server Response
public struct UserIdentityServerResponse: Sendable, Hashable {
    /// The server response data
    ///
    /// For Kerberos authentication, this contains the Server Response
    /// (Kerberos Server ticket).
    /// For SAML authentication, this contains the SAML Response.
    /// For other types, the format is implementation-defined.
    public let serverResponse: Data
    
    /// Creates a server response
    ///
    /// - Parameter serverResponse: The server response data
    public init(serverResponse: Data) {
        self.serverResponse = serverResponse
    }
}

// MARK: - Encoding

extension UserIdentity {
    /// Sub-item type for User Identity Negotiation request (A-ASSOCIATE-RQ)
    ///
    /// Reference: PS3.7 Table D.3-14
    static let subItemType: UInt8 = 0x58
    
    /// Encodes the user identity as a sub-item for the User Information item
    ///
    /// Reference: PS3.7 Section D.3.3.7.1 - Sub-item Structure (A-ASSOCIATE-RQ)
    ///
    /// - Returns: The encoded sub-item data
    func encode() -> Data {
        var data = Data()
        
        // Sub-Item Type (1 byte) - 0x58
        data.append(Self.subItemType)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // Calculate item length
        var contentLength = 1 + 1 + 2 + primaryField.count // type + response flag + primary length + primary
        if let secondary = secondaryField {
            contentLength += 2 + secondary.count // secondary length + secondary
        } else if identityType == .usernameAndPasscode {
            contentLength += 2 // secondary length field (0)
        }
        
        // Item Length (2 bytes, big endian)
        let itemLength = UInt16(contentLength)
        data.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        
        // User-Identity-Type (1 byte)
        data.append(identityType.rawValue)
        
        // Positive-response-requested (1 byte)
        data.append(positiveResponseRequested ? 0x01 : 0x00)
        
        // Primary-field-length (2 bytes, big endian)
        let primaryLength = UInt16(primaryField.count)
        data.append(contentsOf: withUnsafeBytes(of: primaryLength.bigEndian) { Array($0) })
        
        // Primary-field
        data.append(primaryField)
        
        // Secondary-field-length and Secondary-field (only for usernameAndPasscode)
        if identityType == .usernameAndPasscode {
            let secondaryLength = UInt16(secondaryField?.count ?? 0)
            data.append(contentsOf: withUnsafeBytes(of: secondaryLength.bigEndian) { Array($0) })
            if let secondary = secondaryField {
                data.append(secondary)
            }
        }
        
        return data
    }
}

extension UserIdentityServerResponse {
    /// Sub-item type for User Identity Server Response (A-ASSOCIATE-AC)
    ///
    /// Reference: PS3.7 Table D.3-15
    static let subItemType: UInt8 = 0x59
    
    /// Encodes the server response as a sub-item for the User Information item
    ///
    /// Reference: PS3.7 Section D.3.3.7.2 - Sub-item Structure (A-ASSOCIATE-AC)
    ///
    /// - Returns: The encoded sub-item data
    func encode() -> Data {
        var data = Data()
        
        // Sub-Item Type (1 byte) - 0x59
        data.append(Self.subItemType)
        
        // Reserved (1 byte)
        data.append(0x00)
        
        // Item Length (2 bytes, big endian)
        let itemLength = UInt16(2 + serverResponse.count) // length field + response
        data.append(contentsOf: withUnsafeBytes(of: itemLength.bigEndian) { Array($0) })
        
        // Server-response-length (2 bytes, big endian)
        let responseLength = UInt16(serverResponse.count)
        data.append(contentsOf: withUnsafeBytes(of: responseLength.bigEndian) { Array($0) })
        
        // Server-response
        data.append(serverResponse)
        
        return data
    }
}

// MARK: - CustomStringConvertible

extension UserIdentity: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        var desc = "UserIdentity(type: \(identityType)"
        if positiveResponseRequested {
            desc += ", positiveResponseRequested"
        }
        desc += ")"
        return desc
    }

    public var debugDescription: String { description }

    /// A deliberately redacted mirror so `dump` and nested configuration reflection
    /// cannot expose usernames, passcodes, JWTs, assertions, or service tickets.
    public var customMirror: Mirror {
        let children: KeyValuePairs<String, Any> = [
            "identityType": identityType,
            "positiveResponseRequested": positiveResponseRequested,
            "primaryFieldByteCount": primaryField.count,
            "hasSecondaryField": secondaryField != nil,
        ]
        return Mirror(self, children: children, displayStyle: .struct)
    }
}

extension UserIdentityType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .username:
            return "username"
        case .usernameAndPasscode:
            return "usernameAndPasscode"
        case .kerberos:
            return "kerberos"
        case .saml:
            return "saml"
        case .jwt:
            return "jwt"
        }
    }
}
