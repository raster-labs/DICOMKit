import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — character set names checked against PS3.18 2026a Table D-1; states against PS3.3 C.30.1; the default DICOM version is the package target edition (was 2024c)
/// DICOM Conformance Statement for DICOMweb services
///
/// Represents a conformance statement document that describes the capabilities
/// and implementation details of a DICOMweb server or client, per DICOM PS3.2
/// (Conformance) and PS3.18 (Web Services).
///
/// A conformance statement provides the following information:
/// - Implementation description and version
/// - Supported services (WADO-RS, QIDO-RS, STOW-RS, UPS-RS)
/// - Supported media types and transfer syntaxes
/// - Security features and authentication methods
/// - Service-specific capabilities and limitations
///
/// Reference: PS3.2 - Conformance
/// Reference: PS3.18 - Web Services
///
/// ## Example Usage
///
/// ```swift
/// // Generate from server configuration
/// let statement = ConformanceStatementGenerator.generate(
///     from: serverConfiguration,
///     capabilities: serverCapabilities
/// )
///
/// // Export as JSON
/// let jsonData = try statement.toJSON()
///
/// // Export as human-readable text
/// let textDocument = statement.toText()
/// ```
public struct ConformanceStatement: Sendable, Codable, Equatable {
    
    // MARK: - Document Information
    
    /// Document version (conformance statement format version)
    public let documentVersion: String
    
    /// Date the conformance statement was generated
    public let generatedDate: Date
    
    /// Implementation information
    public let implementation: Implementation
    
    /// Network services supported
    public let networkServices: NetworkServices
    
    /// Security information
    public let security: SecurityInformation
    
    /// Character set support
    public let characterSets: CharacterSetSupport
    
    /// Extensions and custom features
    public let extensions: [String: String]?
    
    // MARK: - Initialization
    
    /// Creates a conformance statement
    /// - Parameters:
    ///   - documentVersion: Version of this conformance statement format
    ///   - generatedDate: When this statement was generated
    ///   - implementation: Implementation details
    ///   - networkServices: Supported network services
    ///   - security: Security features
    ///   - characterSets: Character encoding support
    ///   - extensions: Optional custom extensions
    public init(
        documentVersion: String = "1.0",
        generatedDate: Date = Date(),
        implementation: Implementation,
        networkServices: NetworkServices,
        security: SecurityInformation = SecurityInformation(),
        characterSets: CharacterSetSupport = CharacterSetSupport(),
        extensions: [String: String]? = nil
    ) {
        self.documentVersion = documentVersion
        self.generatedDate = generatedDate
        self.implementation = implementation
        self.networkServices = networkServices
        self.security = security
        self.characterSets = characterSets
        self.extensions = extensions
    }
}

// MARK: - Implementation Information

extension ConformanceStatement {
    /// Information about the implementation
    public struct Implementation: Sendable, Codable, Equatable {
        /// Name of the implementation
        public let name: String
        
        /// Version of the implementation
        public let version: String
        
        /// Vendor or developer name
        public let vendor: String
        
        /// Description of the implementation
        public let description: String?
        
        /// URL for more information
        public let informationURL: URL?
        
        /// Supported DICOM standard version
        public let dicomVersion: String
        
        /// Implementation class UID (if applicable)
        public let implementationClassUID: String?
        
        /// Implementation version name (if applicable)
        public let implementationVersionName: String?
        
        public init(
            name: String,
            version: String,
            vendor: String,
            description: String? = nil,
            informationURL: URL? = nil,
            dicomVersion: String = "2026a",
            implementationClassUID: String? = nil,
            implementationVersionName: String? = nil
        ) {
            self.name = name
            self.version = version
            self.vendor = vendor
            self.description = description
            self.informationURL = informationURL
            self.dicomVersion = dicomVersion
            self.implementationClassUID = implementationClassUID
            self.implementationVersionName = implementationVersionName
        }
        
        /// Default implementation info for DICOMKit
        public static let dicomKit = Implementation(
            name: "DICOMKit",
            version: "0.8.8",
            vendor: "DICOMKit Contributors",
            description: "A pure Swift DICOM toolkit for Apple platforms",
            informationURL: URL(string: "https://github.com/DICOMKit/DICOMKit"),
            dicomVersion: "2026a",
            implementationClassUID: "1.2.826.0.1.3680043.8.1234.1",
            implementationVersionName: "DICOMKIT_0_8_8"
        )
    }
}

// MARK: - Network Services

extension ConformanceStatement {
    /// Network services supported
    public struct NetworkServices: Sendable, Codable, Equatable {
        /// DICOMweb services
        public let dicomWeb: DICOMwebServices
        
        /// Traditional DIMSE services (if supported)
        public let dimse: DIMSEServices?
        
        public init(
            dicomWeb: DICOMwebServices,
            dimse: DIMSEServices? = nil
        ) {
            self.dicomWeb = dicomWeb
            self.dimse = dimse
        }
    }
    
    /// DICOMweb service conformance
    public struct DICOMwebServices: Sendable, Codable, Equatable {
        /// WADO-RS service details
        public let wadoRS: WADORSConformance?
        
        /// QIDO-RS service details
        public let qidoRS: QIDORSConformance?
        
        /// STOW-RS service details
        public let stowRS: STOWRSConformance?
        
        /// UPS-RS service details
        public let upsRS: UPSRSConformance?
        
        /// Delete service support
        public let deleteSupport: DeleteConformance?
        
        public init(
            wadoRS: WADORSConformance? = nil,
            qidoRS: QIDORSConformance? = nil,
            stowRS: STOWRSConformance? = nil,
            upsRS: UPSRSConformance? = nil,
            deleteSupport: DeleteConformance? = nil
        ) {
            self.wadoRS = wadoRS
            self.qidoRS = qidoRS
            self.stowRS = stowRS
            self.upsRS = upsRS
            self.deleteSupport = deleteSupport
        }
    }
    
    /// WADO-RS conformance details
    public struct WADORSConformance: Sendable, Codable, Equatable {
        /// Whether the service is supported
        public let supported: Bool
        
        /// Supported retrieval endpoints
        public let endpoints: WADORSEndpoints
        
        /// Supported media types for retrieval
        public let acceptMediaTypes: [String]
        
        /// Supported transfer syntaxes
        public let transferSyntaxes: [String]
        
        /// Supported instance retrieval options
        public let retrievalOptions: RetrievalOptions
        
        public init(
            supported: Bool = true,
            endpoints: WADORSEndpoints = WADORSEndpoints(),
            acceptMediaTypes: [String] = [],
            transferSyntaxes: [String] = [],
            retrievalOptions: RetrievalOptions = RetrievalOptions()
        ) {
            self.supported = supported
            self.endpoints = endpoints
            self.acceptMediaTypes = acceptMediaTypes
            self.transferSyntaxes = transferSyntaxes
            self.retrievalOptions = retrievalOptions
        }
    }
    
    /// WADO-RS endpoint support
    public struct WADORSEndpoints: Sendable, Codable, Equatable {
        /// Study-level retrieval
        public let study: Bool
        /// Series-level retrieval
        public let series: Bool
        /// Instance-level retrieval
        public let instance: Bool
        /// Frame-level retrieval
        public let frames: Bool
        /// Metadata retrieval
        public let metadata: Bool
        /// Rendered image retrieval
        public let rendered: Bool
        /// Thumbnail retrieval
        public let thumbnail: Bool
        /// Bulk data retrieval
        public let bulkdata: Bool
        
        public init(
            study: Bool = true,
            series: Bool = true,
            instance: Bool = true,
            frames: Bool = false,
            metadata: Bool = true,
            rendered: Bool = false,
            thumbnail: Bool = false,
            bulkdata: Bool = true
        ) {
            self.study = study
            self.series = series
            self.instance = instance
            self.frames = frames
            self.metadata = metadata
            self.rendered = rendered
            self.thumbnail = thumbnail
            self.bulkdata = bulkdata
        }
    }
    
    /// Retrieval options for WADO-RS
    public struct RetrievalOptions: Sendable, Codable, Equatable {
        /// Whether streaming downloads are supported
        public let streaming: Bool
        /// Whether range requests are supported
        public let rangeRequests: Bool
        /// Maximum concurrent connections
        public let maxConcurrentConnections: Int?
        
        public init(
            streaming: Bool = true,
            rangeRequests: Bool = false,
            maxConcurrentConnections: Int? = nil
        ) {
            self.streaming = streaming
            self.rangeRequests = rangeRequests
            self.maxConcurrentConnections = maxConcurrentConnections
        }
    }
    
    /// QIDO-RS conformance details
    public struct QIDORSConformance: Sendable, Codable, Equatable {
        /// Whether the service is supported
        public let supported: Bool
        
        /// Query levels supported
        public let queryLevels: [String]
        
        /// Supported matching attributes
        public let matchingAttributes: [QueryAttribute]
        
        /// Supported return attributes
        public let returnAttributes: [QueryAttribute]
        
        /// Query options
        public let queryOptions: QueryOptions
        
        public init(
            supported: Bool = true,
            queryLevels: [String] = ["STUDY", "SERIES", "INSTANCE"],
            matchingAttributes: [QueryAttribute] = [],
            returnAttributes: [QueryAttribute] = [],
            queryOptions: QueryOptions = QueryOptions()
        ) {
            self.supported = supported
            self.queryLevels = queryLevels
            self.matchingAttributes = matchingAttributes
            self.returnAttributes = returnAttributes
            self.queryOptions = queryOptions
        }
    }
    
    /// Query attribute definition
    public struct QueryAttribute: Sendable, Codable, Equatable {
        /// DICOM tag as hex string (e.g., "00100010")
        public let tag: String
        /// Human-readable name
        public let name: String
        /// Value Representation
        public let vr: String?
        /// Query levels where this attribute is available
        public let levels: [String]?
        
        public init(
            tag: String,
            name: String,
            vr: String? = nil,
            levels: [String]? = nil
        ) {
            self.tag = tag
            self.name = name
            self.vr = vr
            self.levels = levels
        }
    }
    
    /// Query options for QIDO-RS
    public struct QueryOptions: Sendable, Codable, Equatable {
        /// Whether fuzzy matching is supported
        public let fuzzyMatching: Bool
        /// Whether wildcard matching is supported
        public let wildcardMatching: Bool
        /// Whether date range queries are supported
        public let dateRangeQueries: Bool
        /// Whether time range queries are supported
        public let timeRangeQueries: Bool
        /// Whether combined datetime range queries are supported
        public let dateTimeRangeQueries: Bool
        /// Maximum results per query (nil means unlimited)
        public let maxResults: Int?
        /// Whether includefield=all is supported
        public let includeFieldAll: Bool
        /// Whether pagination is supported
        public let paginationSupported: Bool
        
        public init(
            fuzzyMatching: Bool = false,
            wildcardMatching: Bool = true,
            dateRangeQueries: Bool = true,
            timeRangeQueries: Bool = true,
            dateTimeRangeQueries: Bool = true,
            maxResults: Int? = nil,
            includeFieldAll: Bool = true,
            paginationSupported: Bool = true
        ) {
            self.fuzzyMatching = fuzzyMatching
            self.wildcardMatching = wildcardMatching
            self.dateRangeQueries = dateRangeQueries
            self.timeRangeQueries = timeRangeQueries
            self.dateTimeRangeQueries = dateTimeRangeQueries
            self.maxResults = maxResults
            self.includeFieldAll = includeFieldAll
            self.paginationSupported = paginationSupported
        }
    }
    
    /// STOW-RS conformance details
    public struct STOWRSConformance: Sendable, Codable, Equatable {
        /// Whether the service is supported
        public let supported: Bool
        
        /// Supported SOP Classes (empty means all)
        public let supportedSOPClasses: [SOPClassInfo]
        
        /// Accepted media types for storage
        public let acceptMediaTypes: [String]
        
        /// Store options
        public let storeOptions: StoreOptions
        
        public init(
            supported: Bool = true,
            supportedSOPClasses: [SOPClassInfo] = [],
            acceptMediaTypes: [String] = [],
            storeOptions: StoreOptions = StoreOptions()
        ) {
            self.supported = supported
            self.supportedSOPClasses = supportedSOPClasses
            self.acceptMediaTypes = acceptMediaTypes
            self.storeOptions = storeOptions
        }
    }
    
    /// SOP Class information
    public struct SOPClassInfo: Sendable, Codable, Equatable {
        /// SOP Class UID
        public let uid: String
        /// Human-readable name
        public let name: String
        /// Category (e.g., "Image", "Structured Report", "Presentation State")
        public let category: String?
        
        public init(uid: String, name: String, category: String? = nil) {
            self.uid = uid
            self.name = name
            self.category = category
        }
    }
    
    /// Store options for STOW-RS
    public struct StoreOptions: Sendable, Codable, Equatable {
        /// Maximum request body size in bytes
        public let maxRequestSize: Int?
        /// Maximum instances per request
        public let maxInstancesPerRequest: Int?
        /// Whether partial success (202) is supported
        public let partialSuccessSupported: Bool
        /// Duplicate handling policy
        public let duplicatePolicy: String
        /// Whether validation is performed
        public let validationEnabled: Bool
        /// Required attributes for storage
        public let requiredAttributes: [String]?
        
        public init(
            maxRequestSize: Int? = nil,
            maxInstancesPerRequest: Int? = nil,
            partialSuccessSupported: Bool = true,
            duplicatePolicy: String = "replace",
            validationEnabled: Bool = true,
            requiredAttributes: [String]? = nil
        ) {
            self.maxRequestSize = maxRequestSize
            self.maxInstancesPerRequest = maxInstancesPerRequest
            self.partialSuccessSupported = partialSuccessSupported
            self.duplicatePolicy = duplicatePolicy
            self.validationEnabled = validationEnabled
            self.requiredAttributes = requiredAttributes
        }
    }
    
    /// UPS-RS conformance details
    public struct UPSRSConformance: Sendable, Codable, Equatable {
        /// Whether the service is supported
        public let supported: Bool
        
        /// Supported operations
        public let operations: UPSOperations
        
        /// State machine support
        public let stateManagement: StateManagement
        
        /// Event subscription support
        public let eventSubscription: EventSubscription
        
        public init(
            supported: Bool = true,
            operations: UPSOperations = UPSOperations(),
            stateManagement: StateManagement = StateManagement(),
            eventSubscription: EventSubscription = EventSubscription()
        ) {
            self.supported = supported
            self.operations = operations
            self.stateManagement = stateManagement
            self.eventSubscription = eventSubscription
        }
    }
    
    /// UPS-RS supported operations
    public struct UPSOperations: Sendable, Codable, Equatable {
        public let search: Bool
        public let retrieve: Bool
        public let create: Bool
        public let update: Bool
        public let changeState: Bool
        public let requestCancellation: Bool
        public let subscribe: Bool
        public let unsubscribe: Bool
        public let suspendSubscription: Bool
        
        public init(
            search: Bool = true,
            retrieve: Bool = true,
            create: Bool = true,
            update: Bool = true,
            changeState: Bool = true,
            requestCancellation: Bool = true,
            subscribe: Bool = true,
            unsubscribe: Bool = true,
            suspendSubscription: Bool = true
        ) {
            self.search = search
            self.retrieve = retrieve
            self.create = create
            self.update = update
            self.changeState = changeState
            self.requestCancellation = requestCancellation
            self.subscribe = subscribe
            self.unsubscribe = unsubscribe
            self.suspendSubscription = suspendSubscription
        }
    }
    
    /// UPS state management conformance
    public struct StateManagement: Sendable, Codable, Equatable {
        /// Supported UPS states
        public let supportedStates: [String]
        /// Valid state transitions
        public let validTransitions: [[String]]?
        /// Transaction UID tracking
        public let transactionUIDTracking: Bool
        
        public init(
            supportedStates: [String] = ["SCHEDULED", "IN PROGRESS", "COMPLETED", "CANCELED"],
            validTransitions: [[String]]? = nil,
            transactionUIDTracking: Bool = true
        ) {
            self.supportedStates = supportedStates
            self.validTransitions = validTransitions
            self.transactionUIDTracking = transactionUIDTracking
        }
    }
    
    /// UPS event subscription conformance
    public struct EventSubscription: Sendable, Codable, Equatable {
        /// Whether event subscription is supported
        public let supported: Bool
        /// Supported delivery methods
        public let deliveryMethods: [String]
        /// Whether global subscription is supported
        public let globalSubscription: Bool
        
        public init(
            supported: Bool = false,
            deliveryMethods: [String] = [],
            globalSubscription: Bool = false
        ) {
            self.supported = supported
            self.deliveryMethods = deliveryMethods
            self.globalSubscription = globalSubscription
        }
    }
    
    /// Delete service conformance
    public struct DeleteConformance: Sendable, Codable, Equatable {
        /// Whether delete is supported
        public let supported: Bool
        /// Delete levels supported
        public let levels: [String]
        /// Whether soft delete is supported
        public let softDeleteSupported: Bool
        
        public init(
            supported: Bool = true,
            levels: [String] = ["STUDY", "SERIES", "INSTANCE"],
            softDeleteSupported: Bool = false
        ) {
            self.supported = supported
            self.levels = levels
            self.softDeleteSupported = softDeleteSupported
        }
    }
    
    /// Traditional DIMSE service conformance
    public struct DIMSEServices: Sendable, Codable, Equatable {
        /// Whether DIMSE services are available
        public let available: Bool
        /// Port for DIMSE connections
        public let port: Int?
        /// AE Title
        public let aeTitle: String?
        /// Supported SOP Classes
        public let sopClasses: [String]?
        
        public init(
            available: Bool = false,
            port: Int? = nil,
            aeTitle: String? = nil,
            sopClasses: [String]? = nil
        ) {
            self.available = available
            self.port = port
            self.aeTitle = aeTitle
            self.sopClasses = sopClasses
        }
    }
}

// MARK: - Security Information

extension ConformanceStatement {
    /// Security-related conformance
    public struct SecurityInformation: Sendable, Codable, Equatable {
        /// Supported authentication methods
        public let authenticationMethods: [String]
        
        /// TLS support information
        public let tlsSupport: TLSSupport
        
        /// Whether audit logging is enabled
        public let auditLogging: Bool
        
        /// Whether access control is enforced
        public let accessControl: AccessControlInfo
        
        public init(
            authenticationMethods: [String] = ["none"],
            tlsSupport: TLSSupport = TLSSupport(),
            auditLogging: Bool = false,
            accessControl: AccessControlInfo = AccessControlInfo()
        ) {
            self.authenticationMethods = authenticationMethods
            self.tlsSupport = tlsSupport
            self.auditLogging = auditLogging
            self.accessControl = accessControl
        }
    }
    
    /// TLS support details
    public struct TLSSupport: Sendable, Codable, Equatable {
        /// Whether TLS is supported
        public let supported: Bool
        /// Whether TLS is required
        public let required: Bool
        /// Minimum TLS version
        public let minimumVersion: String?
        /// Maximum TLS version
        public let maximumVersion: String?
        /// Whether client certificates are supported (mTLS)
        public let clientCertificatesSupported: Bool
        /// Whether client certificates are required
        public let clientCertificatesRequired: Bool
        
        public init(
            supported: Bool = false,
            required: Bool = false,
            minimumVersion: String? = nil,
            maximumVersion: String? = nil,
            clientCertificatesSupported: Bool = false,
            clientCertificatesRequired: Bool = false
        ) {
            self.supported = supported
            self.required = required
            self.minimumVersion = minimumVersion
            self.maximumVersion = maximumVersion
            self.clientCertificatesSupported = clientCertificatesSupported
            self.clientCertificatesRequired = clientCertificatesRequired
        }
    }
    
    /// Access control information
    public struct AccessControlInfo: Sendable, Codable, Equatable {
        /// Whether access control is enabled
        public let enabled: Bool
        /// Access control model
        public let model: String?
        /// Supported roles
        public let roles: [String]?
        
        public init(
            enabled: Bool = false,
            model: String? = nil,
            roles: [String]? = nil
        ) {
            self.enabled = enabled
            self.model = model
            self.roles = roles
        }
    }
}

// MARK: - Character Set Support

extension ConformanceStatement {
    /// Character encoding support
    public struct CharacterSetSupport: Sendable, Codable, Equatable {
        /// Default character set
        public let defaultCharacterSet: String
        /// Supported character sets
        public let supportedCharacterSets: [String]
        /// Whether accept-charset negotiation is supported
        public let acceptCharsetNegotiation: Bool
        
        public init(
            defaultCharacterSet: String = "UTF-8",
            supportedCharacterSets: [String] = ["UTF-8", "ISO_IR 100"],
            acceptCharsetNegotiation: Bool = false
        ) {
            self.defaultCharacterSet = defaultCharacterSet
            self.supportedCharacterSets = supportedCharacterSets
            self.acceptCharsetNegotiation = acceptCharsetNegotiation
        }
    }
}

// MARK: - Export Methods

extension ConformanceStatement {
    /// Exports the conformance statement as JSON data
    /// - Parameter encoder: JSON encoder to use (default uses pretty printing)
    /// - Returns: JSON data
    /// - Throws: Encoding error if serialization fails
    public func toJSON(encoder: JSONEncoder? = nil) throws -> Data {
        let jsonEncoder = encoder ?? {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            return enc
        }()
        return try jsonEncoder.encode(self)
    }
    
    /// Exports the conformance statement as JSON string
    /// - Parameter encoder: JSON encoder to use (default uses pretty printing)
    /// - Returns: JSON string
    /// - Throws: Encoding error if serialization fails
    public func toJSONString(encoder: JSONEncoder? = nil) throws -> String {
        let data = try toJSON(encoder: encoder)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ConformanceStatementError.encodingFailed("Failed to convert JSON data to string")
        }
        return string
    }
    
    /// Exports the conformance statement as human-readable text document
    /// - Returns: Formatted text document
    public func toText() -> String {
        var lines: [String] = []
        let dateFormatter = ISO8601DateFormatter()
        
        // Header
        lines.append("=" .repeating(count: 72))
        lines.append("DICOM CONFORMANCE STATEMENT")
        lines.append("=" .repeating(count: 72))
        lines.append("")
        
        // Document Info
        lines.append("Document Version: \(documentVersion)")
        lines.append("Generated: \(dateFormatter.string(from: generatedDate))")
        lines.append("")
        
        // Implementation
        lines.append("-" .repeating(count: 72))
        lines.append("IMPLEMENTATION")
        lines.append("-" .repeating(count: 72))
        lines.append("Name: \(implementation.name)")
        lines.append("Version: \(implementation.version)")
        lines.append("Vendor: \(implementation.vendor)")
        if let desc = implementation.description {
            lines.append("Description: \(desc)")
        }
        lines.append("DICOM Version: \(implementation.dicomVersion)")
        if let uid = implementation.implementationClassUID {
            lines.append("Implementation Class UID: \(uid)")
        }
        lines.append("")
        
        // DICOMweb Services
        lines.append("-" .repeating(count: 72))
        lines.append("DICOMWEB SERVICES")
        lines.append("-" .repeating(count: 72))
        
        let web = networkServices.dicomWeb
        
        // WADO-RS
        if let wado = web.wadoRS {
            lines.append("")
            lines.append("WADO-RS (Retrieve):")
            lines.append("  Supported: \(wado.supported ? "Yes" : "No")")
            if wado.supported {
                lines.append("  Endpoints:")
                lines.append("    - Study retrieval: \(wado.endpoints.study ? "Yes" : "No")")
                lines.append("    - Series retrieval: \(wado.endpoints.series ? "Yes" : "No")")
                lines.append("    - Instance retrieval: \(wado.endpoints.instance ? "Yes" : "No")")
                lines.append("    - Frame retrieval: \(wado.endpoints.frames ? "Yes" : "No")")
                lines.append("    - Metadata: \(wado.endpoints.metadata ? "Yes" : "No")")
                lines.append("    - Rendered images: \(wado.endpoints.rendered ? "Yes" : "No")")
                lines.append("    - Thumbnails: \(wado.endpoints.thumbnail ? "Yes" : "No")")
                lines.append("    - Bulk data: \(wado.endpoints.bulkdata ? "Yes" : "No")")
                if !wado.acceptMediaTypes.isEmpty {
                    lines.append("  Accept Media Types:")
                    for mt in wado.acceptMediaTypes {
                        lines.append("    - \(mt)")
                    }
                }
                if !wado.transferSyntaxes.isEmpty {
                    lines.append("  Transfer Syntaxes:")
                    for ts in wado.transferSyntaxes {
                        lines.append("    - \(ts)")
                    }
                }
            }
        }
        
        // QIDO-RS
        if let qido = web.qidoRS {
            lines.append("")
            lines.append("QIDO-RS (Query):")
            lines.append("  Supported: \(qido.supported ? "Yes" : "No")")
            if qido.supported {
                lines.append("  Query Levels: \(qido.queryLevels.joined(separator: ", "))")
                lines.append("  Options:")
                lines.append("    - Fuzzy matching: \(qido.queryOptions.fuzzyMatching ? "Yes" : "No")")
                lines.append("    - Wildcard matching: \(qido.queryOptions.wildcardMatching ? "Yes" : "No")")
                lines.append("    - Date range queries: \(qido.queryOptions.dateRangeQueries ? "Yes" : "No")")
                lines.append("    - Pagination: \(qido.queryOptions.paginationSupported ? "Yes" : "No")")
                if let max = qido.queryOptions.maxResults {
                    lines.append("    - Max results: \(max)")
                }
            }
        }
        
        // STOW-RS
        if let stow = web.stowRS {
            lines.append("")
            lines.append("STOW-RS (Store):")
            lines.append("  Supported: \(stow.supported ? "Yes" : "No")")
            if stow.supported {
                lines.append("  Options:")
                lines.append("    - Partial success (202): \(stow.storeOptions.partialSuccessSupported ? "Yes" : "No")")
                lines.append("    - Duplicate policy: \(stow.storeOptions.duplicatePolicy)")
                lines.append("    - Validation: \(stow.storeOptions.validationEnabled ? "Yes" : "No")")
                if let maxSize = stow.storeOptions.maxRequestSize {
                    lines.append("    - Max request size: \(maxSize) bytes")
                }
                if let maxInst = stow.storeOptions.maxInstancesPerRequest {
                    lines.append("    - Max instances per request: \(maxInst)")
                }
            }
        }
        
        // UPS-RS
        if let ups = web.upsRS {
            lines.append("")
            lines.append("UPS-RS (Worklist):")
            lines.append("  Supported: \(ups.supported ? "Yes" : "No")")
            if ups.supported {
                lines.append("  Operations:")
                lines.append("    - Search: \(ups.operations.search ? "Yes" : "No")")
                lines.append("    - Retrieve: \(ups.operations.retrieve ? "Yes" : "No")")
                lines.append("    - Create: \(ups.operations.create ? "Yes" : "No")")
                lines.append("    - Update: \(ups.operations.update ? "Yes" : "No")")
                lines.append("    - Change state: \(ups.operations.changeState ? "Yes" : "No")")
                lines.append("    - Request cancellation: \(ups.operations.requestCancellation ? "Yes" : "No")")
                lines.append("  State Management:")
                lines.append("    - States: \(ups.stateManagement.supportedStates.joined(separator: ", "))")
                lines.append("  Event Subscription:")
                lines.append("    - Supported: \(ups.eventSubscription.supported ? "Yes" : "No")")
            }
        }
        
        // Delete
        if let del = web.deleteSupport {
            lines.append("")
            lines.append("Delete Service:")
            lines.append("  Supported: \(del.supported ? "Yes" : "No")")
            if del.supported {
                lines.append("  Levels: \(del.levels.joined(separator: ", "))")
                lines.append("  Soft delete: \(del.softDeleteSupported ? "Yes" : "No")")
            }
        }
        
        // Security
        lines.append("")
        lines.append("-" .repeating(count: 72))
        lines.append("SECURITY")
        lines.append("-" .repeating(count: 72))
        lines.append("Authentication Methods: \(security.authenticationMethods.joined(separator: ", "))")
        lines.append("TLS:")
        lines.append("  Supported: \(security.tlsSupport.supported ? "Yes" : "No")")
        lines.append("  Required: \(security.tlsSupport.required ? "Yes" : "No")")
        if let minVer = security.tlsSupport.minimumVersion {
            lines.append("  Minimum version: \(minVer)")
        }
        lines.append("  Client certificates (mTLS):")
        lines.append("    Supported: \(security.tlsSupport.clientCertificatesSupported ? "Yes" : "No")")
        lines.append("    Required: \(security.tlsSupport.clientCertificatesRequired ? "Yes" : "No")")
        lines.append("Access Control:")
        lines.append("  Enabled: \(security.accessControl.enabled ? "Yes" : "No")")
        if let model = security.accessControl.model {
            lines.append("  Model: \(model)")
        }
        if let roles = security.accessControl.roles {
            lines.append("  Roles: \(roles.joined(separator: ", "))")
        }
        
        // Character Sets
        lines.append("")
        lines.append("-" .repeating(count: 72))
        lines.append("CHARACTER ENCODING")
        lines.append("-" .repeating(count: 72))
        lines.append("Default: \(characterSets.defaultCharacterSet)")
        lines.append("Supported: \(characterSets.supportedCharacterSets.joined(separator: ", "))")
        
        lines.append("")
        lines.append("=" .repeating(count: 72))
        lines.append("END OF CONFORMANCE STATEMENT")
        lines.append("=" .repeating(count: 72))
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - String Extension for Repeating

private extension String {
    func repeating(count: Int) -> String {
        String(repeating: self, count: count)
    }
}

// MARK: - Errors

/// Errors that can occur during conformance statement operations
public enum ConformanceStatementError: Error, Sendable {
    /// Encoding failed
    case encodingFailed(String)
    /// Decoding failed
    case decodingFailed(String)
    /// Invalid configuration
    case invalidConfiguration(String)
}

extension ConformanceStatementError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .encodingFailed(let message):
            return "Conformance statement encoding failed: \(message)"
        case .decodingFailed(let message):
            return "Conformance statement decoding failed: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid conformance statement configuration: \(message)"
        }
    }
}
