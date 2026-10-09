import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// NEMA-verified: 2026a, checked 2026-09-28 — the path segments studies, series, instances, frames, metadata, rendered, bulkdata, workitems, state, cancelrequest and subscribers read against PS3.18 2026a Tables 10.1-1 and 11.1.1-1 (thumbnail and pixeldata added); roles, scopes and JWT handling are not DICOM-defined
// MARK: - JWT Claims

/// Standard JWT claims parsed from a token
///
/// Contains claims from JWT tokens used for authentication,
/// including standard registered claims and custom DICOM-specific claims.
///
/// Reference: RFC 7519 - JSON Web Token (JWT)
public struct JWTClaims: Sendable {
    /// The issuer of the token (iss)
    public let issuer: String?
    
    /// The subject (user identifier) (sub)
    public let subject: String?
    
    /// The audience (client identifiers) (aud)
    public let audience: [String]
    
    /// The expiration time (exp)
    public let expirationTime: Date?
    
    /// The not before time (nbf)
    public let notBefore: Date?
    
    /// The issued at time (iat)
    public let issuedAt: Date?
    
    /// The JWT ID (jti)
    public let jwtID: String?
    
    /// OAuth2 scopes granted to this token
    public let scopes: [String]
    
    /// Roles assigned to this user
    public let roles: [String]
    
    /// The client ID that requested the token
    public let clientID: String?
    
    /// The patient ID this token is scoped to (for patient-level access)
    public let patientID: String?
    
    /// Additional custom claims (keys only - for claim presence checking)
    public let customClaimKeys: Set<String>
    
    /// Creates JWT claims
    public init(
        issuer: String? = nil,
        subject: String? = nil,
        audience: [String] = [],
        expirationTime: Date? = nil,
        notBefore: Date? = nil,
        issuedAt: Date? = nil,
        jwtID: String? = nil,
        scopes: [String] = [],
        roles: [String] = [],
        clientID: String? = nil,
        patientID: String? = nil,
        customClaimKeys: Set<String> = []
    ) {
        self.issuer = issuer
        self.subject = subject
        self.audience = audience
        self.expirationTime = expirationTime
        self.notBefore = notBefore
        self.issuedAt = issuedAt
        self.jwtID = jwtID
        self.scopes = scopes
        self.roles = roles
        self.clientID = clientID
        self.patientID = patientID
        self.customClaimKeys = customClaimKeys
    }
    
    /// Whether the token is expired
    public var isExpired: Bool {
        guard let exp = expirationTime else { return false }
        return Date() >= exp
    }
    
    /// Whether the token is valid for use (not expired and not before is past)
    public var isValidForUse: Bool {
        if isExpired { return false }
        if let nbf = notBefore, Date() < nbf { return false }
        return true
    }
    
    /// Checks if the token has a specific scope
    /// - Parameter scope: The scope to check
    /// - Returns: True if the scope is present
    public func hasScope(_ scope: String) -> Bool {
        scopes.contains(scope)
    }
    
    /// Checks if the token has any of the specified scopes
    /// - Parameter scopes: The scopes to check
    /// - Returns: True if any scope is present
    public func hasAnyScope(_ scopes: [String]) -> Bool {
        !Set(self.scopes).isDisjoint(with: scopes)
    }
    
    /// Checks if the token has a specific role
    /// - Parameter role: The role to check
    /// - Returns: True if the role is present
    public func hasRole(_ role: String) -> Bool {
        roles.contains(role)
    }
    
    /// Checks if the audience includes the expected value
    /// - Parameter expected: The expected audience
    /// - Returns: True if the audience matches
    public func hasAudience(_ expected: String) -> Bool {
        audience.contains(expected)
    }
}

// MARK: - JWT Verification

/// Error types for JWT verification
public enum JWTVerificationError: Error, Sendable, Equatable {
    /// The token format is invalid (not three base64url parts)
    case invalidFormat
    
    /// The token header is malformed
    case malformedHeader
    
    /// The token payload is malformed
    case malformedPayload
    
    /// The token signature verification failed
    case invalidSignature
    
    /// The token has expired
    case expired
    
    /// The token is not yet valid (before nbf claim)
    case notYetValid
    
    /// The token issuer doesn't match expected value
    case invalidIssuer(expected: String, actual: String?)
    
    /// The token audience doesn't include expected value
    case invalidAudience(expected: String)
    
    /// The signing algorithm is not supported
    case unsupportedAlgorithm(String)
    
    /// No signing key is available
    case noSigningKey
    
    /// Required claim is missing
    case missingClaim(String)
}

extension JWTVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid JWT format: expected three base64url-encoded parts"
        case .malformedHeader:
            return "JWT header is malformed"
        case .malformedPayload:
            return "JWT payload is malformed"
        case .invalidSignature:
            return "JWT signature verification failed"
        case .expired:
            return "JWT has expired"
        case .notYetValid:
            return "JWT is not yet valid"
        case .invalidIssuer(let expected, let actual):
            return "JWT issuer '\(actual ?? "none")' does not match expected '\(expected)'"
        case .invalidAudience(let expected):
            return "JWT audience does not include '\(expected)'"
        case .unsupportedAlgorithm(let alg):
            return "JWT algorithm '\(alg)' is not supported"
        case .noSigningKey:
            return "No signing key available for JWT verification"
        case .missingClaim(let claim):
            return "Required claim '\(claim)' is missing from JWT"
        }
    }
}

// MARK: - JWT Verifier Protocol

/// Protocol for JWT token verification
///
/// Implement this protocol to provide custom JWT verification logic,
/// such as using different key sources or verification libraries.
public protocol JWTVerifier: Sendable {
    /// Verifies a JWT token and returns the claims
    /// - Parameter token: The JWT token string
    /// - Returns: The verified claims
    /// - Throws: JWTVerificationError if verification fails
    func verify(_ token: String) async throws -> JWTClaims
}

// MARK: - JWT Parser

/// Parses JWT tokens without cryptographic verification
///
/// This parser extracts claims from JWT tokens without verifying
/// the signature. Use only for testing or when tokens are already
/// verified by a reverse proxy.
///
/// - Warning: Do not use in production without additional verification.
public struct UnsafeJWTParser: JWTVerifier, Sendable {
    /// Validation options
    public let options: ValidationOptions
    
    /// Creates an unsafe JWT parser
    /// - Parameter options: Validation options for claims
    public init(options: ValidationOptions = .default) {
        self.options = options
    }
    
    public func verify(_ token: String) async throws -> JWTClaims {
        let claims = try parseToken(token)
        try validateClaims(claims)
        return claims
    }
    
    /// Parses a JWT token without verification
    /// - Parameter token: The JWT string
    /// - Returns: The parsed claims
    /// - Throws: JWTVerificationError if parsing fails
    public func parseToken(_ token: String) throws -> JWTClaims {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw JWTVerificationError.invalidFormat
        }
        
        // Decode payload (second part)
        guard let payloadData = base64URLDecode(String(parts[1])) else {
            throw JWTVerificationError.malformedPayload
        }
        
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw JWTVerificationError.malformedPayload
        }
        
        return extractClaims(from: payload)
    }
    
    /// Validates claims according to options
    private func validateClaims(_ claims: JWTClaims) throws {
        // Check expiration
        if options.validateExpiration && claims.isExpired {
            throw JWTVerificationError.expired
        }
        
        // Check not before
        if options.validateNotBefore,
           let nbf = claims.notBefore,
           Date() < nbf {
            throw JWTVerificationError.notYetValid
        }
        
        // Check issuer
        if let expectedIssuer = options.expectedIssuer {
            guard claims.issuer == expectedIssuer else {
                throw JWTVerificationError.invalidIssuer(
                    expected: expectedIssuer,
                    actual: claims.issuer
                )
            }
        }
        
        // Check audience
        if let expectedAudience = options.expectedAudience {
            guard claims.hasAudience(expectedAudience) else {
                throw JWTVerificationError.invalidAudience(expected: expectedAudience)
            }
        }
        
        // Check required claims
        for claim in options.requiredClaims {
            switch claim {
            case "sub":
                if claims.subject == nil {
                    throw JWTVerificationError.missingClaim("sub")
                }
            case "iss":
                if claims.issuer == nil {
                    throw JWTVerificationError.missingClaim("iss")
                }
            case "aud":
                if claims.audience.isEmpty {
                    throw JWTVerificationError.missingClaim("aud")
                }
            case "exp":
                if claims.expirationTime == nil {
                    throw JWTVerificationError.missingClaim("exp")
                }
            default:
                // Check in custom claim keys
                if !claims.customClaimKeys.contains(claim) {
                    throw JWTVerificationError.missingClaim(claim)
                }
            }
        }
    }
    
    /// Extracts claims from a payload dictionary
    private func extractClaims(from payload: [String: Any]) -> JWTClaims {
        // Standard claims
        let issuer = payload["iss"] as? String
        let subject = payload["sub"] as? String
        
        // Audience can be string or array
        let audience: [String]
        if let aud = payload["aud"] as? String {
            audience = [aud]
        } else if let audArray = payload["aud"] as? [String] {
            audience = audArray
        } else {
            audience = []
        }
        
        // Time claims (Unix timestamps)
        let expirationTime = (payload["exp"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        let notBefore = (payload["nbf"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        let issuedAt = (payload["iat"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        
        let jwtID = payload["jti"] as? String
        
        // Scopes - can be in "scope" or "scp" claim
        var scopes: [String] = []
        if let scopeString = payload["scope"] as? String {
            scopes = scopeString.components(separatedBy: " ").filter { !$0.isEmpty }
        } else if let scopeArray = payload["scp"] as? [String] {
            scopes = scopeArray
        }
        
        // Roles - various claim names used by different providers
        var roles: [String] = []
        if let roleArray = payload["roles"] as? [String] {
            roles = roleArray
        } else if let realmAccess = payload["realm_access"] as? [String: Any],
                  let realmRoles = realmAccess["roles"] as? [String] {
            // Keycloak format
            roles = realmRoles
        } else if let groups = payload["groups"] as? [String] {
            // Azure AD format
            roles = groups
        }
        
        // Client ID - various claim names
        let clientID = payload["client_id"] as? String
            ?? payload["azp"] as? String
            ?? payload["appid"] as? String
        
        // Patient context (SMART on FHIR)
        let patientID = payload["patient"] as? String
        
        // Extract all claim keys for presence checking
        let customClaimKeys = Set(payload.keys)
        
        return JWTClaims(
            issuer: issuer,
            subject: subject,
            audience: audience,
            expirationTime: expirationTime,
            notBefore: notBefore,
            issuedAt: issuedAt,
            jwtID: jwtID,
            scopes: scopes,
            roles: roles,
            clientID: clientID,
            patientID: patientID,
            customClaimKeys: customClaimKeys
        )
    }
    
    /// Base64URL decodes a string
    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return Data(base64Encoded: base64)
    }
    
    /// Options for JWT validation
    public struct ValidationOptions: Sendable {
        /// Whether to validate expiration
        public let validateExpiration: Bool
        
        /// Whether to validate not-before
        public let validateNotBefore: Bool
        
        /// Expected issuer (nil to skip validation)
        public let expectedIssuer: String?
        
        /// Expected audience (nil to skip validation)
        public let expectedAudience: String?
        
        /// Required claims that must be present
        public let requiredClaims: [String]
        
        public init(
            validateExpiration: Bool = true,
            validateNotBefore: Bool = true,
            expectedIssuer: String? = nil,
            expectedAudience: String? = nil,
            requiredClaims: [String] = []
        ) {
            self.validateExpiration = validateExpiration
            self.validateNotBefore = validateNotBefore
            self.expectedIssuer = expectedIssuer
            self.expectedAudience = expectedAudience
            self.requiredClaims = requiredClaims
        }
        
        /// Default options with expiration and nbf validation
        public static let `default` = ValidationOptions()
        
        /// Skip all validation (for testing only)
        public static let none = ValidationOptions(
            validateExpiration: false,
            validateNotBefore: false
        )
    }
}

#if canImport(CryptoKit) && (os(macOS) || os(iOS) || os(visionOS))
/// HMAC-based JWT verifier
///
/// Verifies JWT tokens signed with HMAC algorithms (HS256, HS384, HS512).
/// Suitable for symmetric key scenarios.
///
/// - Note: Available on macOS, iOS, and visionOS only.
public struct HMACJWTVerifier: JWTVerifier, Sendable {
    /// The symmetric key for verification
    private let key: SymmetricKey
    
    /// The algorithm to expect
    private let algorithm: Algorithm
    
    /// Validation options
    private let options: UnsafeJWTParser.ValidationOptions
    
    /// Parser for extracting claims
    private let parser: UnsafeJWTParser
    
    /// Supported algorithms
    public enum Algorithm: String, Sendable {
        case hs256 = "HS256"
        case hs384 = "HS384"
        case hs512 = "HS512"
    }
    
    /// Creates an HMAC JWT verifier
    /// - Parameters:
    ///   - secret: The secret key as string
    ///   - algorithm: The HMAC algorithm to use
    ///   - options: Validation options
    public init(
        secret: String,
        algorithm: Algorithm = .hs256,
        options: UnsafeJWTParser.ValidationOptions = .default
    ) {
        self.key = SymmetricKey(data: Data(secret.utf8))
        self.algorithm = algorithm
        self.options = options
        self.parser = UnsafeJWTParser(options: options)
    }
    
    /// Creates an HMAC JWT verifier with raw key data
    /// - Parameters:
    ///   - keyData: The secret key data
    ///   - algorithm: The HMAC algorithm to use
    ///   - options: Validation options
    public init(
        keyData: Data,
        algorithm: Algorithm = .hs256,
        options: UnsafeJWTParser.ValidationOptions = .default
    ) {
        self.key = SymmetricKey(data: keyData)
        self.algorithm = algorithm
        self.options = options
        self.parser = UnsafeJWTParser(options: options)
    }
    
    public func verify(_ token: String) async throws -> JWTClaims {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw JWTVerificationError.invalidFormat
        }
        
        // Verify header algorithm
        try verifyHeader(String(parts[0]))
        
        // Calculate expected signature
        let signatureInput = "\(parts[0]).\(parts[1])"
        let expectedSignature = try calculateSignature(signatureInput)
        
        // Compare signatures
        guard let providedSignature = base64URLDecode(String(parts[2])) else {
            throw JWTVerificationError.invalidSignature
        }
        
        guard expectedSignature == providedSignature else {
            throw JWTVerificationError.invalidSignature
        }
        
        // Parse and validate claims
        return try await parser.verify(token)
    }
    
    private func verifyHeader(_ headerB64: String) throws {
        guard let headerData = base64URLDecode(headerB64),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let alg = header["alg"] as? String else {
            throw JWTVerificationError.malformedHeader
        }
        
        guard alg == algorithm.rawValue else {
            throw JWTVerificationError.unsupportedAlgorithm(alg)
        }
    }
    
    private func calculateSignature(_ input: String) throws -> Data {
        let inputData = Data(input.utf8)
        
        switch algorithm {
        case .hs256:
            let signature = HMAC<SHA256>.authenticationCode(for: inputData, using: key)
            return Data(signature)
        case .hs384:
            let signature = HMAC<SHA384>.authenticationCode(for: inputData, using: key)
            return Data(signature)
        case .hs512:
            let signature = HMAC<SHA512>.authenticationCode(for: inputData, using: key)
            return Data(signature)
        }
    }
    
    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return Data(base64Encoded: base64)
    }
}
#endif

// MARK: - Authenticated User

/// Represents an authenticated user with their claims and permissions
public struct AuthenticatedUser: Sendable {
    /// The user identifier (from sub claim)
    public let userID: String?
    
    /// The client ID (application identifier)
    public let clientID: String?
    
    /// The JWT claims
    public let claims: JWTClaims
    
    /// The roles assigned to this user
    public var roles: Set<DICOMwebRole> {
        Set(claims.roles.compactMap { DICOMwebRole(rawValue: $0) })
    }
    
    /// The scopes granted to this user
    public let scopes: Set<String>
    
    /// The patient ID this user can access (nil means all patients)
    public let patientContext: String?
    
    /// Creates an authenticated user
    public init(claims: JWTClaims) {
        self.userID = claims.subject
        self.clientID = claims.clientID
        self.claims = claims
        self.scopes = Set(claims.scopes)
        self.patientContext = claims.patientID
    }
    
    /// Checks if the user has a specific role
    public func hasRole(_ role: DICOMwebRole) -> Bool {
        roles.contains(role)
    }
    
    /// Checks if the user has any of the specified roles
    public func hasAnyRole(_ roles: [DICOMwebRole]) -> Bool {
        !self.roles.isDisjoint(with: roles)
    }
    
    /// Checks if the user has a specific scope
    public func hasScope(_ scope: String) -> Bool {
        scopes.contains(scope)
    }
    
    /// Checks if the user has any of the specified scopes
    public func hasAnyScope(_ scopes: [String]) -> Bool {
        !self.scopes.isDisjoint(with: scopes)
    }
}

// MARK: - DICOMweb Roles

/// Standard roles for DICOMweb access control
public enum DICOMwebRole: String, Sendable, CaseIterable {
    /// Can read all DICOM data (QIDO-RS, WADO-RS)
    case reader = "dicom.reader"
    
    /// Can write DICOM data (STOW-RS)
    case writer = "dicom.writer"
    
    /// Can delete DICOM data
    case deleter = "dicom.deleter"
    
    /// Can manage worklists (UPS-RS)
    case worklistManager = "dicom.worklist"
    
    /// Full administrative access
    case admin = "dicom.admin"
    
    /// The scopes associated with this role
    public var scopes: [String] {
        switch self {
        case .reader:
            return ["dicom.read", "system/ImagingStudy.read"]
        case .writer:
            return ["dicom.write", "system/ImagingStudy.write"]
        case .deleter:
            return ["dicom.delete"]
        case .worklistManager:
            return ["dicom.worklist", "dicom.ups"]
        case .admin:
            return ["dicom.admin", "dicom.*"]
        }
    }
    
    /// Whether this role implies another role
    public func implies(_ other: DICOMwebRole) -> Bool {
        switch self {
        case .admin:
            return true // Admin implies all roles
        case .writer:
            return other == .reader // Writer can also read
        default:
            return self == other
        }
    }
}

// MARK: - Access Policy

/// Protocol for defining access control policies
public protocol AccessPolicy: Sendable {
    /// Checks if access is allowed
    /// - Parameters:
    ///   - user: The authenticated user (nil for anonymous)
    ///   - operation: The operation being performed
    ///   - resource: The resource being accessed
    /// - Returns: True if access is allowed
    func isAllowed(
        user: AuthenticatedUser?,
        operation: DICOMwebOperation,
        resource: DICOMwebResource
    ) -> Bool
}

/// Operations that can be performed on DICOMweb resources
public enum DICOMwebOperation: String, Sendable {
    /// Query for studies/series/instances (QIDO-RS)
    case search
    
    /// Retrieve DICOM objects (WADO-RS)
    case retrieve
    
    /// Retrieve metadata only
    case retrieveMetadata
    
    /// Retrieve rendered images
    case retrieveRendered
    
    /// Store DICOM objects (STOW-RS)
    case store
    
    /// Delete DICOM objects
    case delete
    
    /// UPS-RS worklist operations
    case worklistRead
    case worklistWrite
    case worklistStateChange
    
    /// Capabilities query
    case capabilities
}

/// Resources that can be accessed via DICOMweb
public struct DICOMwebResource: Sendable {
    /// The type of resource
    public let type: ResourceType
    
    /// The study instance UID (if applicable)
    public let studyUID: String?
    
    /// The series instance UID (if applicable)
    public let seriesUID: String?
    
    /// The SOP instance UID (if applicable)
    public let instanceUID: String?
    
    /// The workitem UID (for UPS-RS)
    public let workitemUID: String?
    
    /// The patient ID (if known)
    public let patientID: String?
    
    /// Resource types
    public enum ResourceType: String, Sendable {
        case studies
        case series
        case instances
        case frames
        case metadata
        case rendered
        case bulkdata
        case workitems
        case capabilities
    }
    
    public init(
        type: ResourceType,
        studyUID: String? = nil,
        seriesUID: String? = nil,
        instanceUID: String? = nil,
        workitemUID: String? = nil,
        patientID: String? = nil
    ) {
        self.type = type
        self.studyUID = studyUID
        self.seriesUID = seriesUID
        self.instanceUID = instanceUID
        self.workitemUID = workitemUID
        self.patientID = patientID
    }
    
    /// Creates a resource from a request path
    public static func from(path: String) -> DICOMwebResource {
        // Parse path components like /studies/1.2.3/series/4.5.6/instances/7.8.9
        let components = path.split(separator: "/").map(String.init)
        
        var studyUID: String?
        var seriesUID: String?
        var instanceUID: String?
        var workitemUID: String?
        var type: ResourceType = .studies
        
        var i = 0
        while i < components.count {
            let component = components[i]
            
            switch component {
            case "studies":
                type = .studies
                if i + 1 < components.count && !isKeyword(components[i + 1]) {
                    studyUID = components[i + 1]
                    i += 1
                }
            case "series":
                type = .series
                if i + 1 < components.count && !isKeyword(components[i + 1]) {
                    seriesUID = components[i + 1]
                    i += 1
                }
            case "instances":
                type = .instances
                if i + 1 < components.count && !isKeyword(components[i + 1]) {
                    instanceUID = components[i + 1]
                    i += 1
                }
            case "frames":
                type = .frames
            case "metadata":
                type = .metadata
            case "rendered", "thumbnail":
                type = .rendered
            case "bulkdata", "pixeldata":
                type = .bulkdata
            case "workitems":
                type = .workitems
                if i + 1 < components.count && !isKeyword(components[i + 1]) {
                    workitemUID = components[i + 1]
                    i += 1
                }
            case "capabilities":
                type = .capabilities
            default:
                break
            }
            i += 1
        }
        
        return DICOMwebResource(
            type: type,
            studyUID: studyUID,
            seriesUID: seriesUID,
            instanceUID: instanceUID,
            workitemUID: workitemUID
        )
    }
    
    private static func isKeyword(_ component: String) -> Bool {
        // PS3.18 Tables 10.1-1 and 11.1.1-1 resource path segments, plus DICOMKit's capabilities
        ["studies", "series", "instances", "frames", "metadata", "rendered",
         "thumbnail", "pixeldata", "bulkdata", "workitems", "capabilities", "state",
         "cancelrequest", "subscribers", "suspend"].contains(component)
    }
}

// MARK: - Role-Based Access Policy

/// Access policy based on user roles and scopes
public struct RoleBasedAccessPolicy: AccessPolicy, Sendable {
    /// Whether to allow anonymous access for read operations
    public let allowAnonymousRead: Bool
    
    /// Whether to allow anonymous capabilities queries
    public let allowAnonymousCapabilities: Bool
    
    /// Role requirements for operations
    public let operationRoles: [DICOMwebOperation: [DICOMwebRole]]
    
    /// Scope requirements for operations
    public let operationScopes: [DICOMwebOperation: [String]]
    
    /// Creates a role-based access policy
    public init(
        allowAnonymousRead: Bool = false,
        allowAnonymousCapabilities: Bool = true,
        operationRoles: [DICOMwebOperation: [DICOMwebRole]]? = nil,
        operationScopes: [DICOMwebOperation: [String]]? = nil
    ) {
        self.allowAnonymousRead = allowAnonymousRead
        self.allowAnonymousCapabilities = allowAnonymousCapabilities
        self.operationRoles = operationRoles ?? Self.defaultRoles
        self.operationScopes = operationScopes ?? Self.defaultScopes
    }
    
    public func isAllowed(
        user: AuthenticatedUser?,
        operation: DICOMwebOperation,
        resource: DICOMwebResource
    ) -> Bool {
        // Capabilities are usually public
        if operation == .capabilities && allowAnonymousCapabilities {
            return true
        }
        
        // Check anonymous access for read operations
        if user == nil {
            return allowAnonymousRead && isReadOperation(operation)
        }
        
        guard let user = user else { return false }
        
        // Admin role always has access
        if user.hasRole(.admin) {
            return true
        }
        
        // Check role requirements
        if let requiredRoles = operationRoles[operation] {
            // User must have at least one required role (or a role that implies it)
            let hasRole = requiredRoles.contains { required in
                user.roles.contains { userRole in
                    userRole == required || userRole.implies(required)
                }
            }
            if !hasRole { return false }
        }
        
        // Check scope requirements
        if let requiredScopes = operationScopes[operation] {
            if !user.hasAnyScope(requiredScopes) { return false }
        }
        
        // Check patient context (for SMART on FHIR)
        if let patientContext = user.patientContext,
           let resourcePatient = resource.patientID {
            // User is scoped to a specific patient
            if patientContext != resourcePatient { return false }
        }
        
        return true
    }
    
    private func isReadOperation(_ operation: DICOMwebOperation) -> Bool {
        switch operation {
        case .search, .retrieve, .retrieveMetadata, .retrieveRendered, .worklistRead, .capabilities:
            return true
        default:
            return false
        }
    }
    
    /// Default role requirements
    public static let defaultRoles: [DICOMwebOperation: [DICOMwebRole]] = [
        .search: [.reader, .admin],
        .retrieve: [.reader, .admin],
        .retrieveMetadata: [.reader, .admin],
        .retrieveRendered: [.reader, .admin],
        .store: [.writer, .admin],
        .delete: [.deleter, .admin],
        .worklistRead: [.worklistManager, .admin],
        .worklistWrite: [.worklistManager, .admin],
        .worklistStateChange: [.worklistManager, .admin],
        .capabilities: []
    ]
    
    /// Default scope requirements
    public static let defaultScopes: [DICOMwebOperation: [String]] = [
        .search: ["dicom.read", "system/ImagingStudy.read", "dicom.*"],
        .retrieve: ["dicom.read", "system/ImagingStudy.read", "dicom.*"],
        .retrieveMetadata: ["dicom.read", "system/ImagingStudy.read", "dicom.*"],
        .retrieveRendered: ["dicom.read", "system/ImagingStudy.read", "dicom.*"],
        .store: ["dicom.write", "system/ImagingStudy.write", "dicom.*"],
        .delete: ["dicom.delete", "dicom.*"],
        .worklistRead: ["dicom.worklist", "dicom.ups", "dicom.*"],
        .worklistWrite: ["dicom.worklist", "dicom.ups", "dicom.*"],
        .worklistStateChange: ["dicom.worklist", "dicom.ups", "dicom.*"],
        .capabilities: []
    ]
    
    /// Permissive policy that allows all operations (for development)
    public static let permissive = RoleBasedAccessPolicy(
        allowAnonymousRead: true,
        allowAnonymousCapabilities: true
    )
    
    /// Strict policy requiring authentication for all operations
    public static let strict = RoleBasedAccessPolicy(
        allowAnonymousRead: false,
        allowAnonymousCapabilities: false
    )
}

// MARK: - Authentication Middleware

/// Configuration for authentication middleware
///
/// - Note: When no verifier is configured, tokens are parsed but NOT cryptographically verified.
///   This is suitable for development or when a reverse proxy handles token verification.
///   For production use, always provide a verifier such as `HMACJWTVerifier`.
public struct AuthenticationConfiguration: Sendable {
    /// The JWT verifier to use
    ///
    /// - Important: When nil, tokens are parsed without signature verification.
    ///   This should only be used in development or when tokens are verified upstream.
    public let verifier: (any JWTVerifier)?
    
    /// The access policy to enforce
    public let accessPolicy: any AccessPolicy
    
    /// Whether to allow unauthenticated requests
    public let allowUnauthenticated: Bool
    
    /// Header name for the authorization token
    public let authorizationHeader: String
    
    /// Token prefix (e.g., "Bearer ")
    public let tokenPrefix: String
    
    /// Creates an authentication configuration
    ///
    /// - Parameters:
    ///   - verifier: JWT verifier for token validation. If nil, tokens are parsed without signature verification.
    ///   - accessPolicy: Access control policy (default: permissive)
    ///   - allowUnauthenticated: Whether to allow requests without tokens (default: true)
    ///   - authorizationHeader: Header name for token (default: "Authorization")
    ///   - tokenPrefix: Token prefix (default: "Bearer ")
    ///
    /// - Warning: When verifier is nil, tokens are NOT cryptographically verified.
    public init(
        verifier: (any JWTVerifier)? = nil,
        accessPolicy: any AccessPolicy = RoleBasedAccessPolicy.permissive,
        allowUnauthenticated: Bool = true,
        authorizationHeader: String = "Authorization",
        tokenPrefix: String = "Bearer "
    ) {
        self.verifier = verifier
        self.accessPolicy = accessPolicy
        self.allowUnauthenticated = allowUnauthenticated
        self.authorizationHeader = authorizationHeader
        self.tokenPrefix = tokenPrefix
    }
    
    /// Development configuration (no signature verification)
    ///
    /// - Warning: This configuration does NOT verify token signatures.
    ///   Use only for local development with test data.
    public static let development = AuthenticationConfiguration()
    
    /// Production configuration with JWT verification
    /// - Parameter verifier: The JWT verifier to use
    /// - Returns: Production authentication configuration
    public static func production(verifier: any JWTVerifier) -> AuthenticationConfiguration {
        AuthenticationConfiguration(
            verifier: verifier,
            accessPolicy: RoleBasedAccessPolicy.strict,
            allowUnauthenticated: false
        )
    }
}

/// Authentication middleware for DICOMweb server
public struct AuthenticationMiddleware: Sendable {
    /// The configuration
    public let configuration: AuthenticationConfiguration
    
    /// Creates authentication middleware
    public init(configuration: AuthenticationConfiguration = .development) {
        self.configuration = configuration
    }
    
    /// Authenticates a request and returns the authenticated user
    /// - Parameter request: The incoming request
    /// - Returns: The authenticated user, or nil if unauthenticated
    /// - Throws: AuthenticationError if authentication fails
    public func authenticate(_ request: DICOMwebRequest) async throws -> AuthenticatedUser? {
        // Extract token from header
        guard let authHeader = request.header(configuration.authorizationHeader) else {
            if configuration.allowUnauthenticated {
                return nil
            }
            throw AuthenticationError.missingToken
        }
        
        // Check prefix
        guard authHeader.hasPrefix(configuration.tokenPrefix) else {
            throw AuthenticationError.invalidTokenFormat
        }
        
        let token = String(authHeader.dropFirst(configuration.tokenPrefix.count))
        
        // Verify token
        guard let verifier = configuration.verifier else {
            // No verifier configured - use UnsafeJWTParser with no validation
            // This is suitable for development or when tokens are verified by a reverse proxy
            // WARNING: This does NOT verify signatures - use only in trusted environments
            let parser = UnsafeJWTParser(options: .none)
            let claims = try await parser.verify(token)
            return AuthenticatedUser(claims: claims)
        }
        
        let claims = try await verifier.verify(token)
        return AuthenticatedUser(claims: claims)
    }
    
    /// Authorizes an operation for a user
    /// - Parameters:
    ///   - user: The authenticated user (or nil for anonymous)
    ///   - operation: The operation being performed
    ///   - resource: The resource being accessed
    /// - Returns: True if authorized
    public func authorize(
        user: AuthenticatedUser?,
        operation: DICOMwebOperation,
        resource: DICOMwebResource
    ) -> Bool {
        configuration.accessPolicy.isAllowed(user: user, operation: operation, resource: resource)
    }
    
    /// Authenticates and authorizes a request
    /// - Parameters:
    ///   - request: The incoming request
    ///   - operation: The operation being performed
    ///   - resource: The resource being accessed
    /// - Returns: The authenticated user if authorized
    /// - Throws: AuthenticationError or AuthorizationError
    public func authenticateAndAuthorize(
        request: DICOMwebRequest,
        operation: DICOMwebOperation,
        resource: DICOMwebResource
    ) async throws -> AuthenticatedUser? {
        let user = try await authenticate(request)
        
        guard authorize(user: user, operation: operation, resource: resource) else {
            throw AuthorizationError.accessDenied(operation: operation.rawValue)
        }
        
        return user
    }
}

// MARK: - Authentication Errors

/// Errors during authentication
public enum AuthenticationError: Error, Sendable, Equatable {
    /// No authorization token provided
    case missingToken
    
    /// Token format is invalid
    case invalidTokenFormat
    
    /// Token verification failed
    case verificationFailed(String)
}

extension AuthenticationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Authorization token is missing"
        case .invalidTokenFormat:
            return "Authorization token format is invalid"
        case .verificationFailed(let reason):
            return "Token verification failed: \(reason)"
        }
    }
}

/// Errors during authorization
public enum AuthorizationError: Error, Sendable, Equatable {
    /// Access to the resource is denied
    case accessDenied(operation: String)
    
    /// Insufficient permissions for the operation
    case insufficientPermissions(required: String)
    
    /// Resource not found or not accessible
    case resourceNotAccessible(String)
}

extension AuthorizationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .accessDenied(let operation):
            return "Access denied for operation: \(operation)"
        case .insufficientPermissions(let required):
            return "Insufficient permissions. Required: \(required)"
        case .resourceNotAccessible(let resource):
            return "Resource not accessible: \(resource)"
        }
    }
}

// MARK: - Response Helpers

extension DICOMwebResponse {
    /// Creates a 401 Unauthorized response
    public static func unauthorized(
        message: String = "Authentication required",
        realm: String? = "DICOMweb"
    ) -> DICOMwebResponse {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let realm = realm {
            headers["WWW-Authenticate"] = "Bearer realm=\"\(realm)\""
        }
        
        let body = """
        {"error": "unauthorized", "message": "\(message)"}
        """.data(using: .utf8)
        
        return DICOMwebResponse(statusCode: 401, headers: headers, body: body)
    }
    
    /// Creates a 403 Forbidden response
    public static func forbidden(message: String = "Access denied") -> DICOMwebResponse {
        let body = """
        {"error": "forbidden", "message": "\(message)"}
        """.data(using: .utf8)
        
        return DICOMwebResponse(
            statusCode: 403,
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }
}
