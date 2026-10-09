import Foundation
import DICOMCore
import DICOMDictionary
// NEMA-verified: 2026a, checked 2026-09-28 — C-MOVE/C-GET fields per PS3.7 2026a Tables 9.3-6..9.3-11, status per PS3.4 Tables C.4-2/C.4-3; identifier order per PS3.5 §7.1 and charset per PS3.4 C.4.2.1.4.1; storage contexts batched per PS3.8 §9.3.2.2 (D21); UIDs registered in PS3.6 Table A-1; 2026-10-01: Priority (0000,0700) LOW 0002H / MEDIUM 0000H / HIGH 0001H from RetrieveConfiguration per PS3.7 Tables 9.3-9 / 9.3-6 (3 of 3), relational-retrieval proposed per PS3.4 C.5.2.1 / C.5.3.1 Tables C.5-3 / C.5-4 (2 bytes) with the above-level keys relaxed per C.4.2.2.2.1 / C.4.3.2.2.1

// MARK: - Retrieve Tags

extension Tag {
    /// Failed SOP Instance UID List (0008,0058), VR UI, VM 1-n.
    ///
    /// Carried in the Identifier of a final C-MOVE/C-GET response (status
    /// warning or failure) to name the sub-operations that failed.
    ///
    /// Reference: PS3.4 C.4.2.1.4.2, C.4.3.1.4.2, Table C.4-2
    public static let failedSOPInstanceUIDList = Tag(group: 0x0008, element: 0x0058)
}

// MARK: - Retrieve Progress

/// Progress information for a retrieve operation
///
/// Reports the status of sub-operations during C-MOVE or C-GET retrieval.
///
/// Reference: PS3.7 Section 9.1.4 (C-MOVE), Section 9.1.3 (C-GET)
public struct RetrieveProgress: Sendable, Hashable {
    /// Number of sub-operations remaining
    public let remaining: Int
    
    /// Number of sub-operations completed successfully
    public let completed: Int
    
    /// Number of sub-operations that failed
    public let failed: Int
    
    /// Number of sub-operations that completed with warnings
    public let warning: Int
    
    /// The total number of sub-operations (remaining + completed + failed + warning)
    public var total: Int {
        remaining + completed + failed + warning
    }
    
    /// The fraction of operations complete (0.0 to 1.0)
    public var fractionComplete: Double {
        guard total > 0 else { return 0.0 }
        return Double(completed + failed + warning) / Double(total)
    }
    
    /// Whether all sub-operations have completed (regardless of success/failure)
    public var isComplete: Bool {
        remaining == 0
    }
    
    /// Whether any sub-operations failed
    public var hasFailures: Bool {
        failed > 0
    }
    
    /// Creates retrieve progress information
    ///
    /// - Parameters:
    ///   - remaining: Number of remaining sub-operations
    ///   - completed: Number of completed sub-operations
    ///   - failed: Number of failed sub-operations
    ///   - warning: Number of warning sub-operations
    public init(remaining: Int = 0, completed: Int = 0, failed: Int = 0, warning: Int = 0) {
        self.remaining = remaining
        self.completed = completed
        self.failed = failed
        self.warning = warning
    }
    
    /// Creates retrieve progress from a C-MOVE or C-GET response
    init(from response: CMoveResponse) {
        self.remaining = Int(response.numberOfRemainingSuboperations ?? 0)
        self.completed = Int(response.numberOfCompletedSuboperations ?? 0)
        self.failed = Int(response.numberOfFailedSuboperations ?? 0)
        self.warning = Int(response.numberOfWarningSuboperations ?? 0)
    }
    
    /// Creates retrieve progress from a C-GET response
    init(from response: CGetResponse) {
        self.remaining = Int(response.numberOfRemainingSuboperations ?? 0)
        self.completed = Int(response.numberOfCompletedSuboperations ?? 0)
        self.failed = Int(response.numberOfFailedSuboperations ?? 0)
        self.warning = Int(response.numberOfWarningSuboperations ?? 0)
    }
}

// MARK: - CustomStringConvertible

extension RetrieveProgress: CustomStringConvertible {
    public var description: String {
        "Progress: \(completed)/\(total) completed, \(failed) failed, \(warning) warnings, \(remaining) remaining"
    }
}

// MARK: - Retrieve Result

/// Result of a retrieve operation
///
/// Contains information about the completed C-MOVE or C-GET operation. A
/// failure status from the SCP is reported here (see `isSuccess`), not thrown:
/// only protocol/transport errors throw, so the sub-operation counters and the
/// Failed SOP Instance UID List survive for the caller.
///
/// Reference: PS3.4 C.4.2.1.4.2, C.4.3.1.4.2, Table C.4-2
public struct RetrieveResult: Sendable, Hashable {
    /// The final status of the retrieve operation
    public let status: DIMSEStatus
    
    /// The final progress information
    public let progress: RetrieveProgress

    /// Failed SOP Instance UID List (0008,0058) from the final response
    /// Identifier, empty when the SCP sent none.
    public let failedSOPInstanceUIDs: [String]
    
    /// Whether the retrieve was fully successful: final status 0x0000 (Success)
    /// and no failed sub-operations (PS3.4 C.4.2.1.4.2 / C.4.3.1.4.2).
    ///
    /// A warning status (0xB000, "sub-operations complete, one or more failures
    /// or warnings") is NOT success. Some SCPs (e.g. DCM4CHEE) have been seen to
    /// count coerced sub-operations as both completed and failed; conformance
    /// wins here, so such a run reports `isWarning` and the caller decides.
    public var isSuccess: Bool {
        status.isSuccess && progress.failed == 0
    }

    /// Whether the retrieve completed with a warning: status 0xBxxx, or a
    /// non-zero failed or warning sub-operation count.
    public var isWarning: Bool {
        status.isWarning || progress.failed > 0 || progress.warning > 0
    }

    /// Whether any sub-operation failed (counter or Failed SOP Instance UID List).
    public var hasFailures: Bool {
        progress.failed > 0 || !failedSOPInstanceUIDs.isEmpty
    }

    /// Whether the SCP reported a failure status (0xAxxx / 0xCxxx / 0x01xx).
    public var isFailure: Bool {
        status.isFailure
    }
    
    /// Whether the retrieve completed with some failures
    public var hasPartialFailures: Bool {
        status.isSuccess && progress.failed > 0
    }
    
    /// Whether the retrieve completed with a warning status
    public var hasWarning: Bool {
        status.isWarning
    }
    
    /// Creates a retrieve result
    ///
    /// - Parameters:
    ///   - status: The final DIMSE status
    ///   - progress: The final progress information
    ///   - failedSOPInstanceUIDs: Failed SOP Instance UID List (0008,0058)
    public init(status: DIMSEStatus, progress: RetrieveProgress, failedSOPInstanceUIDs: [String] = []) {
        self.status = status
        self.progress = progress
        self.failedSOPInstanceUIDs = failedSOPInstanceUIDs
    }
}

// MARK: - CustomStringConvertible

extension RetrieveResult: CustomStringConvertible {
    public var description: String {
        var text = """
        RetrieveResult:
          Status: \(status)
          \(progress)
        """
        if !failedSOPInstanceUIDs.isEmpty {
            text += "\n  Failed SOP Instances: " + failedSOPInstanceUIDs.joined(separator: ", ")
        }
        return text
    }
}

// MARK: - Retrieve Configuration

/// Configuration for the DICOM Retrieve Service
public struct RetrieveConfiguration: Sendable, Hashable {
    /// The local Application Entity title (calling AE)
    public let callingAETitle: AETitle
    
    /// The remote Application Entity title (called AE)
    public let calledAETitle: AETitle
    
    /// Connection timeout in seconds
    public let timeout: TimeInterval
    
    /// Maximum PDU size to propose
    public let maxPDUSize: UInt32
    
    /// Implementation Class UID for this DICOM implementation
    public let implementationClassUID: String
    
    /// Implementation Version Name (optional)
    public let implementationVersionName: String?
    
    /// The Query/Retrieve Information Model to use
    public let informationModel: QueryRetrieveInformationModel

#if canImport(Network)
    /// Complete TLS transport policy, or `nil` for plain TCP
    public let tlsConfiguration: TLSConfiguration?
#endif
    
    /// User identity for authentication (optional)
    public let userIdentity: UserIdentity?

    /// Priority (0000,0700) of the C-MOVE-RQ / C-GET-RQ: LOW 0002H, MEDIUM 0000H,
    /// HIGH 0001H (PS3.7 2026a Tables 9.3-9 / 9.3-6). Default MEDIUM.
    public let priority: DIMSEPriority

    /// SOP Class Extended Negotiation to propose for the retrieval SOP Class
    /// (PS3.4 C.5.2.1 / C.5.3.1, Table C.5-3), or nil for none (baseline
    /// behaviour). With relational-retrieval requested, an identifier may omit
    /// the Unique Keys of the levels above the retrieve level
    /// (PS3.4 C.4.2.2.2.1 / C.4.3.2.2.1); if the SCP then turns relational-retrieval
    /// down, such a request is not sent and the operation throws.
    public let extendedNegotiation: RetrieveExtendedNegotiation?
    
    /// Default Implementation Class UID for DICOMKit
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID
    
    /// Default Implementation Version Name for DICOMKit
    public static let defaultImplementationVersionName = "DICOMKIT_001"
    
    /// Creates a retrieve configuration
    ///
    /// - Parameters:
    ///   - callingAETitle: The local AE title
    ///   - calledAETitle: The remote AE title
    ///   - timeout: Connection timeout in seconds (default: 60)
    ///   - maxPDUSize: Maximum PDU size (default: 64 KB (`defaultMaxPDUSize`))
    ///   - implementationClassUID: Implementation Class UID
    ///   - implementationVersionName: Implementation Version Name
    ///   - informationModel: The Query/Retrieve Information Model (default: Study Root)
    ///   - userIdentity: User identity for authentication (optional)
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        informationModel: QueryRetrieveInformationModel = .studyRoot,
        userIdentity: UserIdentity? = nil
    ) {
        self.init(callingAETitle: callingAETitle, calledAETitle: calledAETitle, timeout: timeout,
                  maxPDUSize: maxPDUSize, implementationClassUID: implementationClassUID,
                  implementationVersionName: implementationVersionName, informationModel: informationModel,
                  userIdentity: userIdentity, priority: .medium, extendedNegotiation: nil)
    }

    /// Creates a retrieve configuration with an explicit Priority and, optionally,
    /// a SOP Class Extended Negotiation (added 2026-10-01; the initializer above
    /// keeps its signature).
    ///
    /// - Parameters:
    ///   - priority: Priority (0000,0700) of the request (PS3.7 Tables 9.3-9 / 9.3-6)
    ///   - extendedNegotiation: SOP Class Extended Negotiation to propose (default: none, PS3.4 C.5.2.1)
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        informationModel: QueryRetrieveInformationModel = .studyRoot,
        userIdentity: UserIdentity? = nil,
        priority: DIMSEPriority,
        extendedNegotiation: RetrieveExtendedNegotiation? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.informationModel = informationModel
#if canImport(Network)
        self.tlsConfiguration = nil
#endif
        self.userIdentity = userIdentity
        self.priority = priority
        self.extendedNegotiation = extendedNegotiation
    }

#if canImport(Network)
    /// Creates a retrieve configuration with an exact TLS transport policy.
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        informationModel: QueryRetrieveInformationModel = .studyRoot,
        tlsConfiguration: TLSConfiguration?,
        userIdentity: UserIdentity? = nil
    ) {
        self.init(callingAETitle: callingAETitle, calledAETitle: calledAETitle, timeout: timeout,
                  maxPDUSize: maxPDUSize, implementationClassUID: implementationClassUID,
                  implementationVersionName: implementationVersionName, informationModel: informationModel,
                  tlsConfiguration: tlsConfiguration, userIdentity: userIdentity,
                  priority: .medium, extendedNegotiation: nil)
    }

    /// Creates a retrieve configuration with an exact TLS transport policy, an
    /// explicit Priority and, optionally, a SOP Class Extended Negotiation.
    public init(
        callingAETitle: AETitle,
        calledAETitle: AETitle,
        timeout: TimeInterval = 60,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        informationModel: QueryRetrieveInformationModel = .studyRoot,
        tlsConfiguration: TLSConfiguration?,
        userIdentity: UserIdentity? = nil,
        priority: DIMSEPriority,
        extendedNegotiation: RetrieveExtendedNegotiation? = nil
    ) {
        self.callingAETitle = callingAETitle
        self.calledAETitle = calledAETitle
        self.timeout = timeout
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.informationModel = informationModel
        self.tlsConfiguration = tlsConfiguration
        self.userIdentity = userIdentity
        self.priority = priority
        self.extendedNegotiation = extendedNegotiation
    }

    /// Builds the exact association configuration used by retrieve operations.
    func associationConfiguration(host: String, port: UInt16) -> AssociationConfiguration {
        AssociationConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            host: host,
            port: port,
            maxPDUSize: maxPDUSize,
            implementationClassUID: implementationClassUID,
            implementationVersionName: implementationVersionName,
            timeout: timeout,
            tlsConfiguration: tlsConfiguration,
            userIdentity: userIdentity
        )
    }
#endif
}

// MARK: - Retrieve Keys

/// Keys for building retrieve request identifiers
///
/// Similar to QueryKeys but for C-MOVE and C-GET retrieve operations.
public struct RetrieveKeys: Sendable, Hashable {
    /// The query level for the retrieve
    public let level: QueryLevel
    
    /// The key-value pairs for the identifier
    public private(set) var keys: [RetrieveKey]
    
    /// A single retrieve key
    public struct RetrieveKey: Sendable, Hashable {
        public let tag: Tag
        public let vr: VR
        public let value: String
        
        public init(tag: Tag, vr: VR, value: String) {
            self.tag = tag
            self.vr = vr
            self.value = value
        }
    }
    
    /// Creates retrieve keys for a specific level
    ///
    /// - Parameter level: The query level
    public init(level: QueryLevel) {
        self.level = level
        self.keys = []
    }
    
    // MARK: - Fluent API for common keys
    
    /// Sets the Study Instance UID
    ///
    /// Replaces an earlier value: a data element occurs at most once in a
    /// data set (PS3.5 7.1).
    public func studyInstanceUID(_ uid: String) -> RetrieveKeys {
        var copy = self
        copy.keys.removeAll { $0.tag == .studyInstanceUID }
        copy.keys.append(RetrieveKey(tag: .studyInstanceUID, vr: .UI, value: uid))
        return copy
    }
    
    /// Sets the Series Instance UID
    ///
    /// Replaces an earlier value: a data element occurs at most once in a
    /// data set (PS3.5 7.1).
    public func seriesInstanceUID(_ uid: String) -> RetrieveKeys {
        var copy = self
        copy.keys.removeAll { $0.tag == .seriesInstanceUID }
        copy.keys.append(RetrieveKey(tag: .seriesInstanceUID, vr: .UI, value: uid))
        return copy
    }
    
    /// Sets the SOP Instance UID
    ///
    /// Replaces an earlier value: a data element occurs at most once in a
    /// data set (PS3.5 7.1).
    public func sopInstanceUID(_ uid: String) -> RetrieveKeys {
        var copy = self
        copy.keys.removeAll { $0.tag == .sopInstanceUID }
        copy.keys.append(RetrieveKey(tag: .sopInstanceUID, vr: .UI, value: uid))
        return copy
    }
    
    /// Sets the Patient ID
    ///
    /// The Unique Key of the PATIENT level. Required at every level under the
    /// Patient Root model (PS3.4 Tables C.6-2/C.6-3, C.4.2.1.4.1).
    public func patientID(_ id: String) -> RetrieveKeys {
        var copy = self
        copy.keys.removeAll { $0.tag == .patientID }
        copy.keys.append(RetrieveKey(tag: .patientID, vr: .LO, value: id))
        return copy
    }

    /// The single value of a key, or nil when absent/empty
    func value(for tag: Tag) -> String? {
        let value = keys.first { $0.tag == tag }?.value.trimmingCharacters(in: .whitespaces)
        return (value?.isEmpty ?? true) ? nil : value
    }
    
    // MARK: - Default Keys

    /// Creates retrieve keys for a patient-level retrieval (Patient Root only)
    ///
    /// Patient ID is the only key at PATIENT level (PS3.4 Table C.6-2).
    ///
    /// - Parameter patientID: The Patient ID to retrieve
    /// - Returns: Configured retrieve keys
    public static func forPatient(patientID: String) -> RetrieveKeys {
        RetrieveKeys(level: .patient)
            .patientID(patientID)
    }
    
    /// Creates retrieve keys for a study-level retrieval
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID to retrieve
    ///   - patientID: The Patient ID (required under the Patient Root model)
    /// - Returns: Configured retrieve keys
    public static func forStudy(_ studyUID: String, patientID: String? = nil) -> RetrieveKeys {
        var keys = RetrieveKeys(level: .study)
            .studyInstanceUID(studyUID)
        if let patientID, !patientID.isEmpty { keys = keys.patientID(patientID) }
        return keys
    }
    
    /// Creates retrieve keys for a series-level retrieval
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID to retrieve
    ///   - patientID: The Patient ID (required under the Patient Root model)
    /// - Returns: Configured retrieve keys
    public static func forSeries(studyUID: String, seriesUID: String, patientID: String? = nil) -> RetrieveKeys {
        var keys = RetrieveKeys(level: .series)
            .studyInstanceUID(studyUID)
            .seriesInstanceUID(seriesUID)
        if let patientID, !patientID.isEmpty { keys = keys.patientID(patientID) }
        return keys
    }
    
    /// Creates retrieve keys for an instance-level retrieval
    ///
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID to retrieve
    ///   - patientID: The Patient ID (required under the Patient Root model)
    /// - Returns: Configured retrieve keys
    public static func forInstance(studyUID: String, seriesUID: String, instanceUID: String,
                                   patientID: String? = nil) -> RetrieveKeys {
        var keys = RetrieveKeys(level: .image)
            .studyInstanceUID(studyUID)
            .seriesInstanceUID(seriesUID)
            .sopInstanceUID(instanceUID)
        if let patientID, !patientID.isEmpty { keys = keys.patientID(patientID) }
        return keys
    }
}

#if canImport(Network)

// MARK: - DICOM Retrieve Service

/// DICOM Retrieve Service (C-MOVE and C-GET SCU)
///
/// Implements the DICOM Query/Retrieve Service Class for retrieving studies, series,
/// and instances from a remote DICOM SCP (Service Class Provider).
///
/// ## C-MOVE vs C-GET
///
/// - **C-MOVE**: Requests the SCP to send images to a specified destination AE.
///   Requires a separate Storage SCP to receive the images.
/// - **C-GET**: Requests images to be sent back on the same association.
///   Simpler to use but requires the SCU to be able to receive C-STORE sub-operations.
///
/// Reference: PS3.4 Section C - Query/Retrieve Service Class
/// Reference: PS3.7 Section 9.1.3 - C-GET Service
/// Reference: PS3.7 Section 9.1.4 - C-MOVE Service
///
/// ## Usage - C-MOVE
///
/// ```swift
/// // Retrieve a study to a destination AE
/// let result = try await DICOMRetrieveService.moveStudy(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS",
///     studyInstanceUID: "1.2.3.4.5.6.7.8.9",
///     moveDestination: "MY_SCP"
/// )
/// print("Completed: \(result.progress.completed)")
/// print("Failed: \(result.progress.failed)")
/// ```
///
/// ## Usage - C-GET
///
/// ```swift
/// // Download a study directly (C-GET)
/// let stream = try await DICOMRetrieveService.getStudy(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS",
///     studyInstanceUID: "1.2.3.4.5.6.7.8.9"
/// )
///
/// for await event in stream {
///     switch event {
///     case .progress(let progress):
///         print("Progress: \(progress.completed)/\(progress.total)")
///     case .instance(let sopInstanceUID, let sopClassUID, let transferSyntaxUID, let data):
///         print("Received instance: \(sopInstanceUID) (TS: \(transferSyntaxUID))")
///         // Process the DICOM data — `data` is a raw dataset; wrap in Part 10 before saving
///     case .completed(let result):
///         print("Completed: \(result)")
///     }
/// }
/// ```
public enum DICOMRetrieveService {
    
    // MARK: - C-MOVE Operations
    
    /// Moves a study to a destination AE using C-MOVE
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - studyInstanceUID: The Study Instance UID to retrieve
    ///   - moveDestination: The destination AE title to receive the images
    ///   - onProgress: Optional callback for progress updates
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: The result of the C-MOVE operation
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func moveStudy(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)? = nil,
        timeout: TimeInterval = 60
    ) async throws -> RetrieveResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout
        )
        
        let keys = RetrieveKeys.forStudy(studyInstanceUID)
        
        return try await performMove(
            host: host,
            port: port,
            configuration: config,
            keys: keys,
            moveDestination: moveDestination,
            onProgress: onProgress
        )
    }
    
    /// Moves a series to a destination AE using C-MOVE
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID to retrieve
    ///   - moveDestination: The destination AE title to receive the images
    ///   - onProgress: Optional callback for progress updates
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: The result of the C-MOVE operation
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func moveSeries(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)? = nil,
        timeout: TimeInterval = 60
    ) async throws -> RetrieveResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout
        )
        
        let keys = RetrieveKeys.forSeries(studyUID: studyInstanceUID, seriesUID: seriesInstanceUID)
        
        return try await performMove(
            host: host,
            port: port,
            configuration: config,
            keys: keys,
            moveDestination: moveDestination,
            onProgress: onProgress
        )
    }
    
    /// Moves an instance to a destination AE using C-MOVE
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    ///   - sopInstanceUID: The SOP Instance UID to retrieve
    ///   - moveDestination: The destination AE title to receive the image
    ///   - onProgress: Optional callback for progress updates
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: The result of the C-MOVE operation
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func moveInstance(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)? = nil,
        timeout: TimeInterval = 60
    ) async throws -> RetrieveResult {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout
        )
        
        let keys = RetrieveKeys.forInstance(
            studyUID: studyInstanceUID,
            seriesUID: seriesInstanceUID,
            instanceUID: sopInstanceUID
        )
        
        return try await performMove(
            host: host,
            port: port,
            configuration: config,
            keys: keys,
            moveDestination: moveDestination,
            onProgress: onProgress
        )
    }
    
    // MARK: - C-GET Operations
    
    /// Event types emitted during a C-GET retrieve operation
    public enum GetEvent: Sendable {
        /// Progress update with current sub-operation counts
        case progress(RetrieveProgress)
        
        /// A DICOM instance has been received
        case instance(sopInstanceUID: String, sopClassUID: String, transferSyntaxUID: String, data: Data)
        
        /// The operation has completed
        case completed(RetrieveResult)
        
        /// An error occurred
        case error(DICOMNetworkError)
    }
    
    /// Downloads a study using C-GET
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - studyInstanceUID: The Study Instance UID to retrieve
    ///   - storageSopClasses: Storage SOP Classes to accept (default: common SOP classes).
    ///     Presentation context IDs are odd 1...255 (PS3.8 9.3.2.2), so one
    ///     association proposes the C-GET class plus at most 127 storage classes:
    ///     one C-GET per batch of 127 storage classes; a second pass on a new
    ///     association only when the first reported failures (instances of
    ///     classes not yet proposed are refused by the SCP and counted as failed).
    ///     See `storageContextBatches(_:)`.
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: An async stream of get events
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func getStudy(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        storageSopClasses: [String]? = nil,
        preferredTransferSyntaxUID: String? = nil,
        timeout: TimeInterval = 60
    ) async throws -> AsyncStream<GetEvent> {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout
        )
        
        let keys = RetrieveKeys.forStudy(studyInstanceUID)
        
        return performGet(
            host: host,
            port: port,
            configuration: config,
            keys: keys,
            storageSopClasses: storageSopClasses ?? commonStorageSOPClassUIDs,
            preferredTransferSyntaxUID: preferredTransferSyntaxUID
        )
    }
    
    /// Downloads a series using C-GET
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID to retrieve
    ///   - storageSopClasses: Storage SOP Classes to accept (default: common SOP classes).
    ///     Presentation context IDs are odd 1...255 (PS3.8 9.3.2.2), so one
    ///     association proposes the C-GET class plus at most 127 storage classes:
    ///     one C-GET per batch of 127 storage classes; a second pass on a new
    ///     association only when the first reported failures (instances of
    ///     classes not yet proposed are refused by the SCP and counted as failed).
    ///     See `storageContextBatches(_:)`.
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: An async stream of get events
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func getSeries(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        storageSopClasses: [String]? = nil,
        preferredTransferSyntaxUID: String? = nil,
        timeout: TimeInterval = 60
    ) async throws -> AsyncStream<GetEvent> {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout
        )
        
        let keys = RetrieveKeys.forSeries(studyUID: studyInstanceUID, seriesUID: seriesInstanceUID)
        
        return performGet(
            host: host,
            port: port,
            configuration: config,
            keys: keys,
            storageSopClasses: storageSopClasses ?? commonStorageSOPClassUIDs,
            preferredTransferSyntaxUID: preferredTransferSyntaxUID
        )
    }
    
    /// Downloads an instance using C-GET
    ///
    /// - Parameters:
    ///   - host: The remote host address
    ///   - port: The remote port number (default: 104)
    ///   - callingAE: The local AE title
    ///   - calledAE: The remote AE title
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    ///   - sopInstanceUID: The SOP Instance UID to retrieve
    ///   - storageSopClasses: Storage SOP Classes to accept (default: common SOP classes).
    ///     Presentation context IDs are odd 1...255 (PS3.8 9.3.2.2), so one
    ///     association proposes the C-GET class plus at most 127 storage classes:
    ///     one C-GET per batch of 127 storage classes; a second pass on a new
    ///     association only when the first reported failures (instances of
    ///     classes not yet proposed are refused by the SCP and counted as failed).
    ///     See `storageContextBatches(_:)`.
    ///   - timeout: Connection timeout in seconds (default: 60)
    /// - Returns: An async stream of get events
    /// - Throws: `DICOMNetworkError` for connection or protocol errors
    public static func getInstance(
        host: String,
        port: UInt16 = dicomDefaultPort,
        callingAE: String,
        calledAE: String,
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String,
        storageSopClasses: [String]? = nil,
        preferredTransferSyntaxUID: String? = nil,
        timeout: TimeInterval = 60
    ) async throws -> AsyncStream<GetEvent> {
        let callingAETitle = try AETitle(callingAE)
        let calledAETitle = try AETitle(calledAE)
        
        let config = RetrieveConfiguration(
            callingAETitle: callingAETitle,
            calledAETitle: calledAETitle,
            timeout: timeout
        )
        
        let keys = RetrieveKeys.forInstance(
            studyUID: studyInstanceUID,
            seriesUID: seriesInstanceUID,
            instanceUID: sopInstanceUID
        )
        
        return performGet(
            host: host,
            port: port,
            configuration: config,
            keys: keys,
            storageSopClasses: storageSopClasses ?? commonStorageSOPClassUIDs,
            preferredTransferSyntaxUID: preferredTransferSyntaxUID
        )
    }
    
    // MARK: - Full-Configuration Operations

    /// Performs C-MOVE with an explicit retrieve configuration.
    public static func move(
        host: String,
        port: UInt16 = dicomDefaultPort,
        configuration: RetrieveConfiguration,
        keys: RetrieveKeys,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)? = nil
    ) async throws -> RetrieveResult {
        try await performMove(
            host: host,
            port: port,
            configuration: configuration,
            keys: keys,
            moveDestination: moveDestination,
            onProgress: onProgress
        )
    }

    /// Performs C-GET with an explicit retrieve configuration.
    ///
    /// Storage presentation contexts: one C-GET per batch of 127 storage
    /// classes (PS3.8 9.3.2.2 allows 128 odd context IDs, ID 1 is the C-GET
    /// class); a second pass on a new association only when the first reported
    /// failures. Results of the passes are merged (see `mergeGetPassResults`).
    public static func get(
        host: String,
        port: UInt16 = dicomDefaultPort,
        configuration: RetrieveConfiguration,
        keys: RetrieveKeys,
        storageSopClasses: [String]? = nil,
        preferredTransferSyntaxUID: String? = nil
    ) -> AsyncStream<GetEvent> {
        performGet(
            host: host,
            port: port,
            configuration: configuration,
            keys: keys,
            storageSopClasses: storageSopClasses ?? commonStorageSOPClassUIDs,
            preferredTransferSyntaxUID: preferredTransferSyntaxUID
        )
    }

    // MARK: - Private Implementation - C-MOVE
    
    /// Performs the C-MOVE operation
    private static func performMove(
        host: String,
        port: UInt16,
        configuration: RetrieveConfiguration,
        keys: RetrieveKeys,
        moveDestination: String,
        onProgress: (@Sendable (RetrieveProgress) -> Void)?
    ) async throws -> RetrieveResult {
        
        // Validate the identifier against the information model (PS3.4 C.4.2.1.4.1);
        // with relational-retrieval requested the above-level keys may be absent
        // (PS3.4 C.4.2.2.2.1) — checked again once the SCP has answered.
        try validateRetrieveKeys(keys, informationModel: configuration.informationModel,
                                 relationalRetrieval: configuration.extendedNegotiation?.relationalRetrieval == true)
        
        // Create association configuration
        let associationConfig = configuration.associationConfiguration(host: host, port: port)
        
        // Create association
        let association = Association(configuration: associationConfig)
        let moveSOPClassUID = configuration.informationModel.moveSOPClassUID
        
        // Create presentation context for C-MOVE
        let presentationContext = try PresentationContext(
            id: 1,
            abstractSyntax: configuration.informationModel.moveSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        
        do {
            // Establish association (PS3.4 C.5.2: optionally one SOP Class
            // Extended Negotiation Sub-Item for the retrieval SOP Class)
            let negotiated = try await association.request(
                presentationContexts: [presentationContext],
                extendedNegotiations: configuration.extendedNegotiation.map { [$0.subItem(for: moveSOPClassUID)] } ?? []
            )
            
            // Verify that the SOP Class was accepted
            guard negotiated.isContextAccepted(1) else {
                try await association.abort()
                throw DICOMNetworkError.sopClassNotSupported(configuration.informationModel.moveSOPClassUID)
            }

            try await requireRelationalRetrievalIfNeeded(
                keys: keys, configuration: configuration, negotiated: negotiated,
                sopClassUID: moveSOPClassUID, association: association)
            
            // Get the accepted transfer syntax
            let acceptedTransferSyntax = negotiated.acceptedTransferSyntax(forContextID: 1) 
                ?? implicitVRLittleEndianTransferSyntaxUID
            
            // Perform the C-MOVE
            let result = try await performCMove(
                association: association,
                presentationContextID: 1,
                maxPDUSize: negotiated.maxPDUSize,
                keys: keys,
                moveDestination: moveDestination,
                transferSyntax: acceptedTransferSyntax,
                sopClassUID: configuration.informationModel.moveSOPClassUID,
                priority: configuration.priority,
                onProgress: onProgress
            )
            
            // Release association gracefully
            try await association.release()
            
            return result
            
        } catch {
            // Attempt to abort the association on error
            try? await association.abort()
            throw error
        }
    }
    
    /// Performs the C-MOVE request/response exchange
    private static func performCMove(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        keys: RetrieveKeys,
        moveDestination: String,
        transferSyntax: String,
        sopClassUID: String,
        priority: DIMSEPriority = .medium,
        onProgress: (@Sendable (RetrieveProgress) -> Void)?
    ) async throws -> RetrieveResult {
        // Build the retrieve identifier data set
        let identifierData = buildRetrieveIdentifier(keys: keys, transferSyntax: transferSyntax)
        
        // Create C-MOVE request (Priority (0000,0700), PS3.7 Table 9.3-9)
        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: sopClassUID,
            moveDestination: moveDestination,
            priority: priority,
            presentationContextID: presentationContextID
        )
        
        // Fragment and send the command and data set
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: identifierData,
            presentationContextID: presentationContextID
        )
        
        // Send all PDUs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive responses
        let assembler = MessageAssembler()
        
        while true {
            let responsePDU = try await association.receive()
            
            if let message = try assembler.addPDVs(from: responsePDU) {
                guard let moveResponse = message.asCMoveResponse() else {
                    throw DICOMNetworkError.decodingFailed(
                        "Expected C-MOVE-RSP, got \(message.command?.description ?? "unknown")"
                    )
                }
                
                // Update progress
                let progress = RetrieveProgress(from: moveResponse)
                onProgress?(progress)
                
                // Check the status
                let status = moveResponse.status
                
                if status.isPending {
                    // Pending - continue receiving responses
                    continue
                }

                // Final response (success, warning, failure or cancel): the
                // Identifier may carry the Failed SOP Instance UID List
                // (PS3.4 C.4.2.1.4.2, Table C.4-2). A failure status is returned
                // in the result, not thrown, so the counters are not lost.
                let failed = failedSOPInstanceUIDs(from: message.dataSet, transferSyntax: transferSyntax)
                return RetrieveResult(status: status, progress: progress, failedSOPInstanceUIDs: failed)
            }
        }
    }
    
    // MARK: - Private Implementation - C-GET
    
    /// Maximum number of storage presentation contexts proposed on one C-GET
    /// association: PS3.8 9.3.2.2 allows the odd IDs 1...255 (128 contexts) and
    /// ID 1 is always the C-GET SOP Class.
    static let maxStorageContextsPerAssociation = 127

    /// Splits the storage SOP Classes a C-GET SCU is willing to receive into
    /// batches that fit one association (at most
    /// `maxStorageContextsPerAssociation` each). Order is preserved and
    /// duplicate UIDs are proposed once. An empty input yields no batches.
    static func storageContextBatches(_ uids: [String]) -> [[String]] {
        var seen = Set<String>()
        var unique: [String] = []
        for uid in uids where seen.insert(uid).inserted {
            unique.append(uid)
        }
        let size = maxStorageContextsPerAssociation
        return stride(from: 0, to: unique.count, by: size).map { start in
            Array(unique[start..<min(start + size, unique.count)])
        }
    }

    /// Merges the result of a further C-GET pass into the accumulated result.
    ///
    /// Received instances are yielded as they arrive, so only the counters are
    /// merged: completed and warning sub-operations add up; failed
    /// sub-operations and the Failed SOP Instance UID List are those of the
    /// last pass only (earlier failures were instances of classes not yet
    /// proposed, which the next pass re-requested); remaining is 0; the status
    /// is the last pass's.
    static func mergeGetPassResults(previous: RetrieveResult?, next: RetrieveResult) -> RetrieveResult {
        guard let previous else { return next }
        let progress = RetrieveProgress(
            remaining: 0,
            completed: previous.progress.completed + next.progress.completed,
            failed: next.progress.failed,
            warning: previous.progress.warning + next.progress.warning
        )
        return RetrieveResult(
            status: next.status,
            progress: progress,
            failedSOPInstanceUIDs: next.failedSOPInstanceUIDs
        )
    }

    /// Performs the C-GET operation
    ///
    /// One C-GET per batch of `maxStorageContextsPerAssociation` storage
    /// classes (see `storageContextBatches(_:)`); a further pass on a new
    /// association proposing the next batch is made only when the previous
    /// pass reported failed sub-operations or a Failed SOP Instance UID List,
    /// since an SCP refuses (and counts as failed) the instances whose SOP
    /// Class had no presentation context.
    private static func performGet(
        host: String,
        port: UInt16,
        configuration: RetrieveConfiguration,
        keys: RetrieveKeys,
        storageSopClasses: [String],
        preferredTransferSyntaxUID: String? = nil
    ) -> AsyncStream<GetEvent> {
        AsyncStream { continuation in
            let producer = Task {
                do {
                    // Validate the identifier against the information model (PS3.4 C.4.2.1.4.1);
                    // relational-retrieval relaxes the above-level keys (PS3.4 C.4.3.2.2.1)
                    try validateRetrieveKeys(keys, informationModel: configuration.informationModel,
                                             relationalRetrieval: configuration.extendedNegotiation?.relationalRetrieval == true)

                    var batches = storageContextBatches(storageSopClasses)
                    if batches.isEmpty { batches = [[]] }

                    var merged: RetrieveResult? = nil
                    for (index, batch) in batches.enumerated() {
                        if index > 0, let previous = merged, !previous.hasFailures {
                            break
                        }
                        let passResult = try await performGetPass(
                            host: host,
                            port: port,
                            configuration: configuration,
                            keys: keys,
                            storageSopClasses: batch,
                            preferredTransferSyntaxUID: preferredTransferSyntaxUID,
                            continuation: continuation
                        )
                        merged = mergeGetPassResults(previous: merged, next: passResult)
                    }

                    if let merged {
                        continuation.yield(.completed(merged))
                    }
                    continuation.finish()
                } catch let error as DICOMNetworkError {
                    continuation.yield(.error(error))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(DICOMNetworkError.connectionFailed(error.localizedDescription)))
                    continuation.finish()
                }
            }
            // If the consumer stops iterating (its task is cancelled, it breaks out, or the
            // stream is abandoned), cancel the producer so its association and network reads
            // tear down instead of leaking. This is effective now that
            // DICOMConnection.receive(length:) honors cancellation by cancelling the socket.
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    /// One C-GET pass: a new association proposing the C-GET SOP Class plus
    /// `storageSopClasses` (at most `maxStorageContextsPerAssociation`), the
    /// C-GET exchange, and a graceful release. Received instances and progress
    /// are yielded on `continuation`; the final result is returned.
    private static func performGetPass(
        host: String,
        port: UInt16,
        configuration: RetrieveConfiguration,
        keys: RetrieveKeys,
        storageSopClasses: [String],
        preferredTransferSyntaxUID: String?,
        continuation: AsyncStream<GetEvent>.Continuation
    ) async throws -> RetrieveResult {
        // Create association configuration
        let associationConfig = configuration.associationConfiguration(host: host, port: port)

        // Create association
        let association = Association(configuration: associationConfig)

        // Build presentation contexts:
        // 1. C-GET SOP Class
        // 2. Storage SOP Classes for receiving C-STORE sub-operations
        var presentationContexts: [PresentationContext] = []
        var contextID: UInt8 = 1

        // C-GET presentation context
        let getContext = try PresentationContext(
            id: contextID,
            abstractSyntax: configuration.informationModel.getSOPClassUID,
            transferSyntaxes: [
                explicitVRLittleEndianTransferSyntaxUID,
                implicitVRLittleEndianTransferSyntaxUID
            ]
        )
        presentationContexts.append(getContext)
        contextID += 2

        // Storage SOP Class presentation contexts
        // Build the accepted TS list: preferred first (if provided), then
        // uncompressed, then the common compressed syntaxes. Offering the
        // compressed syntaxes lets the SCP send natively-compressed objects
        // (e.g. JPEG-Lossless XA cine) instead of being forced to transcode —
        // which many SCPs refuse to do, silently dropping the sub-operation.
        var storageTransferSyntaxes: [String] = []
        if let preferred = preferredTransferSyntaxUID, !preferred.isEmpty {
            storageTransferSyntaxes.append(preferred)
        }
        for ts in retrieveStorageTransferSyntaxUIDs
            where !storageTransferSyntaxes.contains(ts) {
            storageTransferSyntaxes.append(ts)
        }
        // Presentation context IDs are odd, 1...255 (PS3.8 9.3.2.2), so at
        // most 127 storage contexts fit after the C-GET context (ID 1,
        // always first). The caller batches the classes accordingly; this
        // bound only guards against an oversized batch. Duplicate UIDs are
        // proposed once.
        var proposedStorageUIDs: [String] = []
        var storageContextIDToUID: [UInt8: String] = [:]
        var nextContextID = Int(contextID)
        for sopClassUID in storageSopClasses where !proposedStorageUIDs.contains(sopClassUID) {
            guard nextContextID <= 255 else { break }
            let id = UInt8(nextContextID)
            let storageContext = try PresentationContext(
                id: id,
                abstractSyntax: sopClassUID,
                transferSyntaxes: storageTransferSyntaxes
            )
            presentationContexts.append(storageContext)
            proposedStorageUIDs.append(sopClassUID)
            storageContextIDToUID[id] = sopClassUID
            nextContextID += 2
        }

        // PS3.4 C.4.3.1.1 / C.5.3, PS3.7 D.3.3.4: the C-GET SCU must
        // negotiate the SCP role for every Storage SOP Class it is
        // willing to receive as a C-STORE sub-operation.
        let roleSelections = proposedStorageUIDs.map { SCPSCURoleSelection.both($0) }

        // Establish association (PS3.4 C.5.3: optionally one SOP Class
        // Extended Negotiation Sub-Item for the retrieval SOP Class)
        let getSOPClassUID = configuration.informationModel.getSOPClassUID
        let negotiated = try await association.request(
            presentationContexts: presentationContexts,
            roleSelections: roleSelections,
            extendedNegotiations: configuration.extendedNegotiation.map { [$0.subItem(for: getSOPClassUID)] } ?? []
        )

        // Verify that the C-GET SOP Class was accepted
        guard negotiated.isContextAccepted(1) else {
            try await association.abort()
            throw DICOMNetworkError.sopClassNotSupported(
                configuration.informationModel.getSOPClassUID
            )
        }

        try await requireRelationalRetrievalIfNeeded(
            keys: keys, configuration: configuration, negotiated: negotiated,
            sopClassUID: getSOPClassUID, association: association)

        // Storage contexts usable for C-STORE sub-operations: when the SCP
        // answered the role selection (PS3.7 D.3.3.4.2) only contexts whose
        // SOP Class was granted the SCP role count. An SCP that sent no
        // role selection sub-item at all (older implementations) is taken
        // to apply the default roles for our proposal, so every accepted
        // storage context stays usable, as before.
        let scpAnsweredRoles = !negotiated.acceptPDU.roleSelections.isEmpty
        var usableStorageContextIDs: Set<UInt8>? = nil
        if scpAnsweredRoles {
            usableStorageContextIDs = Set(storageContextIDToUID.compactMap { id, uid in
                negotiated.isContextAccepted(id) && negotiated.isSCPRoleAccepted(for: uid) ? id : nil
            })
        }

        // Get the accepted transfer syntax
        let acceptedTransferSyntax = negotiated.acceptedTransferSyntax(forContextID: 1)
            ?? implicitVRLittleEndianTransferSyntaxUID

        // Perform the C-GET
        let result = try await performCGet(
            association: association,
            presentationContextID: 1,
            maxPDUSize: negotiated.maxPDUSize,
            keys: keys,
            transferSyntax: acceptedTransferSyntax,
            sopClassUID: configuration.informationModel.getSOPClassUID,
            priority: configuration.priority,
            negotiated: negotiated,
            usableStorageContextIDs: usableStorageContextIDs,
            continuation: continuation
        )

        // Release association gracefully
        try await association.release()
        return result
    }

    /// Performs the C-GET request/response exchange
    private static func performCGet(
        association: Association,
        presentationContextID: UInt8,
        maxPDUSize: UInt32,
        keys: RetrieveKeys,
        transferSyntax: String,
        sopClassUID: String,
        priority: DIMSEPriority = .medium,
        negotiated: NegotiatedAssociation,
        usableStorageContextIDs: Set<UInt8>? = nil,
        continuation: AsyncStream<GetEvent>.Continuation
    ) async throws -> RetrieveResult {
        // Build the retrieve identifier data set
        let identifierData = buildRetrieveIdentifier(keys: keys, transferSyntax: transferSyntax)
        
        // Create C-GET request (Priority (0000,0700), PS3.7 Table 9.3-6)
        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: sopClassUID,
            priority: priority,
            presentationContextID: presentationContextID
        )
        
        // Fragment and send the command and data set
        let fragmenter = MessageFragmenter(maxPDUSize: maxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: identifierData,
            presentationContextID: presentationContextID
        )
        
        // Send all PDUs
        for pdu in pdus {
            for pdv in pdu.presentationDataValues {
                try await association.send(pdv: pdv)
            }
        }
        
        // Receive responses and C-STORE sub-operations
        let assembler = MessageAssembler()
        
        while true {
            let responsePDU = try await association.receive()
            
            if let message = try assembler.addPDVs(from: responsePDU) {
                // Check what type of message we received
                switch message.command {
                case .cGetResponse:
                    guard let getResponse = message.asCGetResponse() else {
                        throw DICOMNetworkError.decodingFailed("Failed to parse C-GET-RSP")
                    }
                    
                    // Update progress
                    let progress = RetrieveProgress(from: getResponse)
                    continuation.yield(.progress(progress))
                    
                    // Check the status
                    let status = getResponse.status
                    
                    if status.isPending {
                        // Pending - continue receiving
                        continue
                    } else {
                        // Complete (success, warning, failure, or cancel). The final
                        // Identifier may carry the Failed SOP Instance UID List
                        // (PS3.4 C.4.3.1.4.2, Table C.4-2).
                        let failed = failedSOPInstanceUIDs(from: message.dataSet, transferSyntax: transferSyntax)
                        return RetrieveResult(status: status, progress: progress, failedSOPInstanceUIDs: failed)
                    }
                    
                case .cStoreRequest:
                    // Incoming C-STORE sub-operation
                    guard let storeRequest = message.asCStoreRequest() else {
                        throw DICOMNetworkError.decodingFailed("Failed to parse C-STORE-RQ")
                    }
                    
                    let sopInstanceUID = storeRequest.affectedSOPInstanceUID
                    let sopClassUID = storeRequest.affectedSOPClassUID
                    
                    // Resolve the transfer syntax from the negotiated presentation contexts
                    let instanceTS = negotiated.acceptedTransferSyntax(
                        forContextID: message.presentationContextID
                    ) ?? implicitVRLittleEndianTransferSyntaxUID
                    
                    // A sub-operation on a context for which we were not granted the
                    // SCP role (PS3.7 D.3.3.4) is refused rather than accepted.
                    let roleAccepted = usableStorageContextIDs?.contains(message.presentationContextID) ?? true
                    
                    // Yield the instance data
                    if roleAccepted, let dataSetData = message.dataSet {
                        continuation.yield(.instance(
                            sopInstanceUID: sopInstanceUID,
                            sopClassUID: sopClassUID,
                            transferSyntaxUID: instanceTS,
                            data: dataSetData
                        ))
                    }
                    
                    // Send C-STORE response
                    let storeResponse = CStoreResponse(
                        messageIDBeingRespondedTo: storeRequest.messageID,
                        affectedSOPClassUID: sopClassUID,
                        affectedSOPInstanceUID: sopInstanceUID,
                        status: roleAccepted ? .success : .refusedSOPClassNotSupported,
                        presentationContextID: message.presentationContextID
                    )
                    
                    let responsePDUs = fragmenter.fragmentMessage(
                        commandSet: storeResponse.commandSet,
                        dataSet: nil,
                        presentationContextID: message.presentationContextID
                    )
                    
                    for pdu in responsePDUs {
                        for pdv in pdu.presentationDataValues {
                            try await association.send(pdv: pdv)
                        }
                    }
                    
                default:
                    throw DICOMNetworkError.decodingFailed(
                        "Unexpected command during C-GET: \(message.command?.description ?? "unknown")"
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Methods

    /// Validates a retrieve identifier against the information model.
    ///
    /// - The level must be supported by the model.
    /// - Unique Keys of every level above the retrieve level must be present
    ///   (PS3.4 C.4.2.1.4.1 / C.4.3.1.4.1): Study Instance UID at SERIES,
    ///   Study + Series Instance UID at IMAGE.
    /// - Under the Patient Root model (Tables C.6-2/C.6-3) Patient ID is required
    ///   at every level; at PATIENT level it is the only key.
    ///
    /// - Throws: `DICOMNetworkError.invalidState` naming the missing key.
    static func validateRetrieveKeys(
        _ keys: RetrieveKeys,
        informationModel: QueryRetrieveInformationModel,
        relationalRetrieval: Bool = false
    ) throws {
        guard informationModel.supportsLevel(keys.level) else {
            throw DICOMNetworkError.invalidState(
                "Retrieve level \(keys.level) is not supported by \(informationModel)"
            )
        }
        let level = keys.level.rawValue
        if relationalRetrieval {
            // PS3.4 C.4.2.2.2.1 / C.4.3.2.2.1: relational-retrieve removes the
            // requirement for Unique Keys of the levels above the retrieve level;
            // the retrieve level's own Unique Key is still needed.
            try validateRetrieveLevelUniqueKey(keys, informationModel: informationModel)
            return
        }
        if informationModel == .patientRoot {
            guard keys.value(for: .patientID) != nil else {
                throw DICOMNetworkError.invalidState(
                    "A Patient Root \(level)-level retrieve requires Patient ID (0010,0020) "
                    + "(PS3.4 C.4.2.1.4.1, Tables C.6-2/C.6-3: the PATIENT level Unique Key is required at every level)"
                )
            }
            if keys.level == .patient,
               keys.keys.contains(where: { $0.tag != .patientID && !$0.value.isEmpty }) {
                throw DICOMNetworkError.invalidState(
                    "A Patient Root PATIENT-level retrieve identifier shall contain only Patient ID (0010,0020) "
                    + "(PS3.4 Table C.6-2)"
                )
            }
        }
        if keys.level == .series || keys.level == .image {
            guard keys.value(for: .studyInstanceUID) != nil else {
                throw DICOMNetworkError.invalidState(
                    "A \(level)-level retrieve requires Study Instance UID (0020,000D) (PS3.4 C.4.2.1.4.1)"
                )
            }
        }
        if keys.level == .image {
            guard keys.value(for: .seriesInstanceUID) != nil else {
                throw DICOMNetworkError.invalidState(
                    "An IMAGE-level retrieve requires Series Instance UID (0020,000E) (PS3.4 C.4.2.1.4.1)"
                )
            }
        }
    }

    /// The retrieve level's own Unique Key (PS3.4 C.4.2.2.1: Patient ID at
    /// PATIENT, Study / Series / SOP Instance UID below).
    static func validateRetrieveLevelUniqueKey(
        _ keys: RetrieveKeys,
        informationModel: QueryRetrieveInformationModel
    ) throws {
        let uniqueKey: Tag
        switch keys.level {
        case .patient: uniqueKey = .patientID
        case .study:   uniqueKey = .studyInstanceUID
        case .series:  uniqueKey = .seriesInstanceUID
        case .image:   uniqueKey = .sopInstanceUID
        }
        guard keys.value(for: uniqueKey) != nil else {
            throw DICOMNetworkError.invalidState(
                "A \(keys.level.rawValue)-level retrieve requires the Unique Key of that level \(uniqueKey) (PS3.4 C.4.2.2.1)"
            )
        }
    }

    /// Whether the identifier relies on relational-retrieval, i.e. omits a
    /// Unique Key of a level above the retrieve level (PS3.4 C.4.2.2.2.1).
    static func identifierNeedsRelationalRetrieval(
        _ keys: RetrieveKeys,
        informationModel: QueryRetrieveInformationModel
    ) -> Bool {
        (try? validateRetrieveKeys(keys, informationModel: informationModel)) == nil
    }

    /// After association negotiation: when the identifier omits above-level
    /// Unique Keys and the SCP did not accept relational-retrieval (no
    /// sub-item returned, or byte 1 = 0 — PS3.4 C.5.2.1, Table C.5-4), the
    /// request is not sent; the association is released and the error names
    /// the missing key.
    private static func requireRelationalRetrievalIfNeeded(
        keys: RetrieveKeys,
        configuration: RetrieveConfiguration,
        negotiated: NegotiatedAssociation,
        sopClassUID: String,
        association: Association
    ) async throws {
        guard let proposed = configuration.extendedNegotiation, proposed.relationalRetrieval,
              identifierNeedsRelationalRetrieval(keys, informationModel: configuration.informationModel) else {
            return
        }
        let inEffect = RetrieveExtendedNegotiation.negotiated(
            proposed: proposed,
            accepted: negotiated.acceptPDU.extendedNegotiations,
            sopClassUID: sopClassUID)
        guard inEffect.relationalRetrieval else {
            try? await association.release()
            throw DICOMNetworkError.invalidState(
                "The SCP did not accept relational-retrieval for \(sopClassUID) (PS3.4 C.5.2.1, Table C.5-4), "
                + "so the identifier must carry the Unique Keys of the levels above \(keys.level.rawValue) "
                + "(PS3.4 C.4.2.2.1)"
            )
        }
    }

    /// Extracts the Failed SOP Instance UID List (0008,0058) from a final
    /// C-MOVE/C-GET response Identifier, or an empty list when the response
    /// carried no data set or no such element.
    static func failedSOPInstanceUIDs(from dataSet: Data?, transferSyntax: String) -> [String] {
        guard let dataSet, !dataSet.isEmpty else { return [] }
        let attributes = DICOMQueryService.parseQueryResponse(data: dataSet, transferSyntax: transferSyntax)
        guard let raw = attributes[.failedSOPInstanceUIDList] else { return [] }
        let value = String(data: raw, encoding: .ascii) ?? String(decoding: raw, as: UTF8.self)
        return value.split(separator: "\\")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \0")) }
            .filter { !$0.isEmpty }
    }
    
    /// Builds the retrieve identifier data set
    ///
    /// Every element, including Query/Retrieve Level (0008,0052), is written in
    /// ascending tag order (PS3.5 7.1), so at IMAGE level SOP Instance UID
    /// (0008,0018) precedes (0008,0052).
    ///
    /// The Specific Character Set is chosen exactly as
    /// `DICOMQueryService.buildQueryIdentifier` does: a caller-supplied
    /// (0008,0005) key wins, else the narrowest set representing every text-VR
    /// value (none for ISO 646, "ISO_IR 100" for Latin-1, "ISO_IR 192"
    /// otherwise). When one is needed it is inserted into the Identifier
    /// (PS3.4 C.4.2.1.4.1, C.2.2.2; PS3.5 6.1.2) and text values are encoded in
    /// it, so a non-ASCII key never degrades to a zero-length (universal) key.
    static func buildRetrieveIdentifier(keys: RetrieveKeys, transferSyntax: String) -> Data {
        var data = Data()
        let isExplicitVR = transferSyntax == explicitVRLittleEndianTransferSyntaxUID

        var allKeys = keys.keys
        let callerCharacterSetKey = allKeys.first { $0.tag == .specificCharacterSet }
        let callerValue = callerCharacterSetKey?.value.trimmingCharacters(in: .whitespaces)
        let override = (callerValue?.isEmpty == false) ? callerValue : nil

        let textValues = allKeys.filter { DICOMQueryService.textVRs.contains($0.vr) }.map { $0.value }
        let characterSet = DIMSECharacterSet.choose(for: textValues, override: override)

        allKeys.removeAll { $0.tag == .specificCharacterSet }
        if let chosen = characterSet.specificCharacterSet {
            allKeys.append(RetrieveKeys.RetrieveKey(tag: .specificCharacterSet, vr: .CS, value: chosen))
        }

        // Merge Query/Retrieve Level into the key set and sort everything by
        // ascending tag order (PS3.5 7.1)
        allKeys.append(RetrieveKeys.RetrieveKey(
            tag: .queryRetrieveLevel, vr: .CS, value: keys.level.queryRetrieveLevel))
        for key in allKeys.sorted(by: { $0.tag < $1.tag }) {
            data.append(DICOMQueryService.encodeElement(
                tag: key.tag,
                vr: key.vr,
                value: key.value,
                explicit: isExplicitVR,
                characterSet: characterSet
            ))
        }

        return data
    }
}

#endif

// MARK: - Common Storage SOP Class UIDs

/// Common Storage SOP Class UIDs for C-GET operations.
///
/// A C-GET SCU must propose one storage presentation context per SOP Class it
/// is willing to receive as a C-STORE sub-operation. This is sourced from the
/// package-wide canonical registry (`StorageSOPClass.allUIDs` in
/// `DICOMDictionary`) so the SCU, the `StorageSCP` and the validator stay in
/// lock-step — see ``StorageSOPClass`` for why a shared list matters.
public let commonStorageSOPClassUIDs: [String] = StorageSOPClass.allUIDs

// MARK: - Retrieve Transfer Syntaxes

/// Transfer syntaxes proposed for each storage presentation context during
/// C-GET. Includes the uncompressed baselines plus the common compressed
/// syntaxes so the SCP can return natively-compressed objects without
/// transcoding (e.g. JPEG-Lossless / JPEG 2000 XA cine).
let retrieveStorageTransferSyntaxUIDs: [String] = [
    explicitVRLittleEndianTransferSyntaxUID,    // 1.2.840.10008.1.2.1
    implicitVRLittleEndianTransferSyntaxUID,    // 1.2.840.10008.1.2
    "1.2.840.10008.1.2.4.50",                   // JPEG Baseline (Process 1)
    "1.2.840.10008.1.2.4.51",                   // JPEG Extended (Process 2 & 4)
    "1.2.840.10008.1.2.4.57",                   // JPEG Lossless, Non-Hierarchical (Process 14)
    "1.2.840.10008.1.2.4.70",                   // JPEG Lossless SV1 (Process 14, SV1)
    "1.2.840.10008.1.2.4.90",                   // JPEG 2000 Lossless
    "1.2.840.10008.1.2.4.91",                   // JPEG 2000
    "1.2.840.10008.1.2.5"                        // RLE Lossless
]
