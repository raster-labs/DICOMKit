import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — the 20 SOP Class UIDs and names diffed against PS3.6 2026a Table A-1 (all registered; the en dash in the DX name corrected); QIDO attribute tags against PS3.18 Table 10.6.1-5
/// Generator for DICOM Conformance Statements
///
/// Creates conformance statements from DICOMweb server configuration and capabilities.
/// The generated statement documents the server's conformance claims per PS3.2.
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
/// // Generate with custom implementation info
/// let customStatement = ConformanceStatementGenerator.generate(
///     from: configuration,
///     capabilities: capabilities,
///     implementation: ConformanceStatement.Implementation(
///         name: "MyPACS",
///         version: "2.0",
///         vendor: "My Company"
///     )
/// )
/// ```
public enum ConformanceStatementGenerator {
    
    /// Generates a conformance statement from server configuration and capabilities
    /// - Parameters:
    ///   - configuration: The server configuration
    ///   - capabilities: The server capabilities
    ///   - implementation: Optional custom implementation info (defaults to DICOMKit)
    /// - Returns: A complete conformance statement
    public static func generate(
        from configuration: DICOMwebServerConfiguration,
        capabilities: DICOMwebCapabilities,
        implementation: ConformanceStatement.Implementation = .dicomKit
    ) -> ConformanceStatement {
        
        let networkServices = buildNetworkServices(
            from: capabilities,
            configuration: configuration
        )
        
        let security = buildSecurityInformation(
            from: configuration,
            capabilities: capabilities
        )
        
        return ConformanceStatement(
            documentVersion: "1.0",
            generatedDate: Date(),
            implementation: implementation,
            networkServices: networkServices,
            security: security,
            characterSets: ConformanceStatement.CharacterSetSupport(),
            extensions: buildExtensions(from: capabilities)
        )
    }
    
    /// Generates a conformance statement from capabilities only (client-side)
    /// - Parameters:
    ///   - capabilities: The capabilities to document
    ///   - implementation: Optional custom implementation info
    /// - Returns: A conformance statement
    public static func generate(
        from capabilities: DICOMwebCapabilities,
        implementation: ConformanceStatement.Implementation = .dicomKit
    ) -> ConformanceStatement {
        let networkServices = buildNetworkServices(from: capabilities, configuration: nil)
        
        let accessControl = ConformanceStatement.AccessControlInfo(
            enabled: capabilities.authenticationMethods.contains { $0 != .none },
            model: capabilities.authenticationMethods.contains(.oauth2) ? "OAuth2/RBAC" : nil,
            roles: capabilities.authenticationMethods.contains(.oauth2) 
                ? ["reader", "writer", "deleter", "worklistManager", "admin"] 
                : nil
        )
        
        let security = ConformanceStatement.SecurityInformation(
            authenticationMethods: capabilities.authenticationMethods.map { $0.rawValue },
            tlsSupport: ConformanceStatement.TLSSupport(),
            auditLogging: false,
            accessControl: accessControl
        )
        
        return ConformanceStatement(
            documentVersion: "1.0",
            generatedDate: Date(),
            implementation: implementation,
            networkServices: networkServices,
            security: security,
            characterSets: ConformanceStatement.CharacterSetSupport(),
            extensions: buildExtensions(from: capabilities)
        )
    }
    
    // MARK: - Private Helpers
    
    private static func buildNetworkServices(
        from capabilities: DICOMwebCapabilities,
        configuration: DICOMwebServerConfiguration?
    ) -> ConformanceStatement.NetworkServices {
        let dicomWeb = buildDICOMwebServices(from: capabilities, configuration: configuration)
        
        return ConformanceStatement.NetworkServices(
            dicomWeb: dicomWeb,
            dimse: nil
        )
    }
    
    private static func buildDICOMwebServices(
        from capabilities: DICOMwebCapabilities,
        configuration: DICOMwebServerConfiguration?
    ) -> ConformanceStatement.DICOMwebServices {
        
        // WADO-RS
        let wadoRS: ConformanceStatement.WADORSConformance?
        if capabilities.services.wadoRS {
            wadoRS = ConformanceStatement.WADORSConformance(
                supported: true,
                endpoints: ConformanceStatement.WADORSEndpoints(
                    study: true,
                    series: true,
                    instance: true,
                    frames: false,  // Per MILESTONES.md - requires pixel processing
                    metadata: true,
                    rendered: capabilities.services.rendered,
                    thumbnail: capabilities.services.thumbnails,
                    bulkdata: capabilities.services.bulkdata
                ),
                acceptMediaTypes: capabilities.mediaTypes.retrieve,
                transferSyntaxes: capabilities.transferSyntaxes,
                retrievalOptions: ConformanceStatement.RetrievalOptions(
                    streaming: true,
                    rangeRequests: false,  // Per MILESTONES.md - deferred
                    maxConcurrentConnections: configuration?.maxConcurrentRequests
                )
            )
        } else {
            wadoRS = nil
        }
        
        // QIDO-RS
        let qidoRS: ConformanceStatement.QIDORSConformance?
        if capabilities.services.qidoRS {
            qidoRS = ConformanceStatement.QIDORSConformance(
                supported: true,
                queryLevels: capabilities.queryCapabilities.queryLevels.map { $0.rawValue },
                matchingAttributes: buildMatchingAttributes(),
                returnAttributes: buildReturnAttributes(),
                queryOptions: ConformanceStatement.QueryOptions(
                    fuzzyMatching: capabilities.queryCapabilities.fuzzyMatching,
                    wildcardMatching: capabilities.queryCapabilities.wildcardMatching,
                    dateRangeQueries: capabilities.queryCapabilities.dateRangeQueries,
                    timeRangeQueries: true,
                    dateTimeRangeQueries: true,
                    maxResults: capabilities.queryCapabilities.maxResults,
                    includeFieldAll: capabilities.queryCapabilities.includeFieldAll,
                    paginationSupported: true
                )
            )
        } else {
            qidoRS = nil
        }
        
        // STOW-RS
        let stowRS: ConformanceStatement.STOWRSConformance?
        if capabilities.services.stowRS {
            let duplicatePolicy: String
            if let config = configuration {
                switch config.stowConfiguration.duplicatePolicy {
                case .reject:
                    duplicatePolicy = "reject"
                case .replace:
                    duplicatePolicy = "replace"
                case .accept:
                    duplicatePolicy = "accept"
                }
            } else {
                duplicatePolicy = "replace"
            }
            
            stowRS = ConformanceStatement.STOWRSConformance(
                supported: true,
                supportedSOPClasses: buildSupportedSOPClasses(from: configuration),
                acceptMediaTypes: capabilities.mediaTypes.store,
                storeOptions: ConformanceStatement.StoreOptions(
                    maxRequestSize: capabilities.storeCapabilities.maxRequestSize,
                    maxInstancesPerRequest: capabilities.storeCapabilities.maxInstancesPerRequest,
                    partialSuccessSupported: capabilities.storeCapabilities.partialSuccess,
                    duplicatePolicy: duplicatePolicy,
                    validationEnabled: configuration?.stowConfiguration.validateRequiredAttributes ?? true,
                    requiredAttributes: nil
                )
            )
        } else {
            stowRS = nil
        }
        
        // UPS-RS
        let upsRS: ConformanceStatement.UPSRSConformance?
        if capabilities.services.upsRS {
            upsRS = ConformanceStatement.UPSRSConformance(
                supported: true,
                operations: ConformanceStatement.UPSOperations(
                    search: true,
                    retrieve: true,
                    create: true,
                    update: true,
                    changeState: true,
                    requestCancellation: true,
                    subscribe: true,
                    unsubscribe: true,
                    suspendSubscription: true
                ),
                stateManagement: ConformanceStatement.StateManagement(
                    supportedStates: ["SCHEDULED", "IN PROGRESS", "COMPLETED", "CANCELED"],
                    validTransitions: [
                        ["SCHEDULED", "IN PROGRESS"],
                        ["IN PROGRESS", "COMPLETED"],
                        ["IN PROGRESS", "CANCELED"],
                        ["SCHEDULED", "CANCELED"]
                    ],
                    transactionUIDTracking: true
                ),
                eventSubscription: ConformanceStatement.EventSubscription(
                    supported: false,  // Per MILESTONES.md - deferred to future version
                    deliveryMethods: [],
                    globalSubscription: false
                )
            )
        } else {
            upsRS = nil
        }
        
        // Delete support
        let deleteSupport: ConformanceStatement.DeleteConformance?
        if capabilities.services.delete {
            deleteSupport = ConformanceStatement.DeleteConformance(
                supported: true,
                levels: ["STUDY", "SERIES", "INSTANCE"],
                softDeleteSupported: false  // Per MILESTONES.md - soft delete not implemented
            )
        } else {
            deleteSupport = nil
        }
        
        return ConformanceStatement.DICOMwebServices(
            wadoRS: wadoRS,
            qidoRS: qidoRS,
            stowRS: stowRS,
            upsRS: upsRS,
            deleteSupport: deleteSupport
        )
    }
    
    private static func buildMatchingAttributes() -> [ConformanceStatement.QueryAttribute] {
        // Common QIDO-RS matching attributes
        return [
            ConformanceStatement.QueryAttribute(tag: "00100010", name: "PatientName", vr: "PN", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00100020", name: "PatientID", vr: "LO", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00080020", name: "StudyDate", vr: "DA", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00080030", name: "StudyTime", vr: "TM", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00080050", name: "AccessionNumber", vr: "SH", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00080061", name: "ModalitiesInStudy", vr: "CS", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "0020000D", name: "StudyInstanceUID", vr: "UI", levels: ["STUDY", "SERIES", "INSTANCE"]),
            ConformanceStatement.QueryAttribute(tag: "00200010", name: "StudyID", vr: "SH", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00080090", name: "ReferringPhysicianName", vr: "PN", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00080060", name: "Modality", vr: "CS", levels: ["SERIES"]),
            ConformanceStatement.QueryAttribute(tag: "0020000E", name: "SeriesInstanceUID", vr: "UI", levels: ["SERIES", "INSTANCE"]),
            ConformanceStatement.QueryAttribute(tag: "00200011", name: "SeriesNumber", vr: "IS", levels: ["SERIES"]),
            ConformanceStatement.QueryAttribute(tag: "00080018", name: "SOPInstanceUID", vr: "UI", levels: ["INSTANCE"]),
            ConformanceStatement.QueryAttribute(tag: "00200013", name: "InstanceNumber", vr: "IS", levels: ["INSTANCE"]),
            ConformanceStatement.QueryAttribute(tag: "00080016", name: "SOPClassUID", vr: "UI", levels: ["INSTANCE"])
        ]
    }
    
    private static func buildReturnAttributes() -> [ConformanceStatement.QueryAttribute] {
        // Common QIDO-RS return attributes (in addition to matching attributes)
        return [
            ConformanceStatement.QueryAttribute(tag: "00100030", name: "PatientBirthDate", vr: "DA", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00100040", name: "PatientSex", vr: "CS", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00081030", name: "StudyDescription", vr: "LO", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00201206", name: "NumberOfStudyRelatedSeries", vr: "IS", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "00201208", name: "NumberOfStudyRelatedInstances", vr: "IS", levels: ["STUDY"]),
            ConformanceStatement.QueryAttribute(tag: "0008103E", name: "SeriesDescription", vr: "LO", levels: ["SERIES"]),
            ConformanceStatement.QueryAttribute(tag: "00201209", name: "NumberOfSeriesRelatedInstances", vr: "IS", levels: ["SERIES"]),
            ConformanceStatement.QueryAttribute(tag: "00080008", name: "ImageType", vr: "CS", levels: ["INSTANCE"]),
            ConformanceStatement.QueryAttribute(tag: "00280010", name: "Rows", vr: "US", levels: ["INSTANCE"]),
            ConformanceStatement.QueryAttribute(tag: "00280011", name: "Columns", vr: "US", levels: ["INSTANCE"]),
            ConformanceStatement.QueryAttribute(tag: "00280100", name: "BitsAllocated", vr: "US", levels: ["INSTANCE"])
        ]
    }
    
    private static func buildSupportedSOPClasses(
        from configuration: DICOMwebServerConfiguration?
    ) -> [ConformanceStatement.SOPClassInfo] {
        // If no specific SOP classes configured, return common ones
        guard let config = configuration,
              !config.stowConfiguration.allowedSOPClasses.isEmpty else {
            return commonSOPClasses()
        }
        
        return config.stowConfiguration.allowedSOPClasses.compactMap { uid in
            sopClassInfo(for: uid)
        }
    }
    
    private static func commonSOPClasses() -> [ConformanceStatement.SOPClassInfo] {
        return [
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.2",
                name: "CT Image Storage",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.4",
                name: "MR Image Storage",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.1",
                name: "Computed Radiography Image Storage",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.1.1",
                name: "Digital X-Ray Image Storage - For Presentation",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.7",
                name: "Secondary Capture Image Storage",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.12.1",
                name: "X-Ray Angiographic Image Storage",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.6.1",
                name: "Ultrasound Image Storage",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.77.1.4",
                name: "VL Photographic Image Storage",
                category: "Image"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.88.11",
                name: "Basic Text SR Storage",
                category: "Structured Report"
            ),
            ConformanceStatement.SOPClassInfo(
                uid: "1.2.840.10008.5.1.4.1.1.88.22",
                name: "Enhanced SR Storage",
                category: "Structured Report"
            )
        ]
    }
    
    private static func sopClassInfo(for uid: String) -> ConformanceStatement.SOPClassInfo? {
        // Common SOP Class UID to name mapping
        let sopClasses: [String: (name: String, category: String)] = [
            "1.2.840.10008.5.1.4.1.1.2": ("CT Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.4": ("MR Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.1": ("Computed Radiography Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.1.1": ("Digital X-Ray Image Storage - For Presentation", "Image"),
            "1.2.840.10008.5.1.4.1.1.7": ("Secondary Capture Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.12.1": ("X-Ray Angiographic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.6.1": ("Ultrasound Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.77.1.1": ("VL Endoscopic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.77.1.2": ("VL Microscopic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.77.1.3": ("VL Slide-Coordinates Microscopic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.77.1.4": ("VL Photographic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.77.1.1.1": ("Video Endoscopic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.77.1.2.1": ("Video Microscopic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.77.1.4.1": ("Video Photographic Image Storage", "Image"),
            "1.2.840.10008.5.1.4.1.1.88.11": ("Basic Text SR Storage", "Structured Report"),
            "1.2.840.10008.5.1.4.1.1.88.22": ("Enhanced SR Storage", "Structured Report"),
            "1.2.840.10008.5.1.4.1.1.88.33": ("Comprehensive SR Storage", "Structured Report"),
            "1.2.840.10008.5.1.4.1.1.66.4": ("Segmentation Storage", "Annotation"),
            "1.2.840.10008.5.1.4.1.1.11.1": ("Grayscale Softcopy Presentation State Storage", "Presentation State"),
            "1.2.840.10008.5.1.4.1.1.11.3": ("Pseudo-Color Softcopy Presentation State Storage", "Presentation State")
        ]
        
        if let info = sopClasses[uid] {
            return ConformanceStatement.SOPClassInfo(uid: uid, name: info.name, category: info.category)
        }
        
        // Unknown SOP Class - return with UID as name
        return ConformanceStatement.SOPClassInfo(uid: uid, name: uid, category: nil)
    }
    
    private static func buildSecurityInformation(
        from configuration: DICOMwebServerConfiguration,
        capabilities: DICOMwebCapabilities
    ) -> ConformanceStatement.SecurityInformation {
        
        let tlsSupport: ConformanceStatement.TLSSupport
        if let tlsConfig = configuration.tlsConfiguration {
            tlsSupport = ConformanceStatement.TLSSupport(
                supported: true,
                required: true,
                minimumVersion: tlsConfig.minimumTLSVersion.rawValue,
                maximumVersion: tlsConfig.maximumTLSVersion?.rawValue,
                clientCertificatesSupported: tlsConfig.requireClientCertificate || tlsConfig.clientCACertificatePath != nil,
                clientCertificatesRequired: tlsConfig.requireClientCertificate
            )
        } else {
            tlsSupport = ConformanceStatement.TLSSupport(
                supported: false,
                required: false,
                minimumVersion: nil,
                maximumVersion: nil,
                clientCertificatesSupported: false,
                clientCertificatesRequired: false
            )
        }
        
        let accessControl = ConformanceStatement.AccessControlInfo(
            enabled: capabilities.authenticationMethods.contains { $0 != .none },
            model: capabilities.authenticationMethods.contains(.oauth2) ? "OAuth2/RBAC" : nil,
            roles: capabilities.authenticationMethods.contains(.oauth2) 
                ? ["reader", "writer", "deleter", "worklistManager", "admin"] 
                : nil
        )
        
        return ConformanceStatement.SecurityInformation(
            authenticationMethods: capabilities.authenticationMethods.map { $0.rawValue },
            tlsSupport: tlsSupport,
            auditLogging: false,  // Per MILESTONES.md - basic audit logging available via metrics
            accessControl: accessControl
        )
    }
    
    private static func buildExtensions(
        from capabilities: DICOMwebCapabilities
    ) -> [String: String]? {
        return capabilities.extensions
    }
}

// MARK: - Server Integration

extension ConformanceStatementGenerator {
    /// Generates a conformance statement from a DICOMweb server
    /// - Parameter server: The DICOMweb server (provides access to configuration)
    /// - Returns: A conformance statement
    public static func generate(for server: DICOMwebServer) async -> ConformanceStatement {
        let configuration = server.configuration
        let capabilities = DICOMwebCapabilities.dicomKitServer
        
        return generate(
            from: configuration,
            capabilities: capabilities
        )
    }
}
