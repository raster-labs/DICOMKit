/// DICOMNetwork - DICOM Networking Support
///
/// This module provides DICOM networking capabilities for DICOMKit,
/// implementing the DICOM Upper Layer Protocol and DIMSE message exchange.
///
/// Reference: DICOM PS3.7 - Message Exchange
/// Reference: DICOM PS3.8 - Network Communication Support
///
/// ## Overview
///
/// DICOMNetwork provides types and protocols for DICOM network communication,
/// including Protocol Data Units (PDUs) for association management, data transfer,
/// and DIMSE (DICOM Message Service Element) message structures.
///
/// ## Milestone 6.1 - Core Networking Infrastructure
///
/// - PDU type definitions for all DICOM Upper Layer Protocol messages
/// - Association PDUs: A-ASSOCIATE-RQ, A-ASSOCIATE-AC, A-ASSOCIATE-RJ
/// - Release PDUs: A-RELEASE-RQ, A-RELEASE-RP
/// - Data Transfer: P-DATA-TF
/// - Abort: A-ABORT
/// - Presentation Context structures for negotiation
/// - AE Title handling
/// - PDU encoding and decoding
/// - Error types for network operations
///
/// ## Milestone 6.2 - Association Management
///
/// - TCP socket abstraction with `DICOMConnection`
/// - Association state machine for protocol compliance
/// - High-level `Association` class for SCU operations
/// - Async/await network operations
/// - Configuration types for association parameters
///
/// ## Milestone 6.3 - DIMSE Protocol
///
/// - DIMSE Command types (DIMSECommand enum)
/// - DIMSE Status codes (DIMSEStatus type)
/// - DIMSE Priority levels (DIMSEPriority enum)
/// - Command Set encoding/decoding (CommandSet struct)
/// - DIMSE-C message types:
///   - C-ECHO (CEchoRequest, CEchoResponse)
///   - C-STORE (CStoreRequest, CStoreResponse)
///   - C-FIND (CFindRequest, CFindResponse)
///   - C-MOVE (CMoveRequest, CMoveResponse)
///   - C-GET (CGetRequest, CGetResponse)
///   - C-CANCEL (CCancelRequest)
/// - Message assembly (MessageAssembler)
/// - Message fragmentation (MessageFragmenter)
///
/// ## Milestone 6.4 - Verification Service (C-ECHO)
///
/// - C-ECHO SCU implementation via `DICOMVerificationService`
/// - Simple `verify()` method for connectivity testing
/// - Detailed `echo()` method with `VerificationResult`
/// - `VerificationConfiguration` for customization
/// - Verification SOP Class UID constant
/// - Common transfer syntax UID constants
///
/// ## Milestone 6.5 - Query Services (C-FIND)
///
/// - C-FIND SCU implementation via `DICOMQueryService`
/// - Query methods: `findStudies()`, `findSeries()`, `findInstances()`
/// - `QueryKeys` fluent API for building query identifiers
/// - `QueryLevel` for PATIENT, STUDY, SERIES, IMAGE levels
/// - Query result types: `StudyResult`, `SeriesResult`, `InstanceResult`
/// - Wildcard matching support (*, ?)
/// - Date/Time range queries
///
/// ## Milestone 6.6 - Retrieve Services (C-MOVE, C-GET)
///
/// - C-MOVE SCU implementation via `DICOMRetrieveService`
/// - C-GET SCU implementation via `DICOMRetrieveService`
/// - Retrieve methods: `moveStudy()`, `moveSeries()`, `moveInstance()`
/// - Download methods: `getStudy()`, `getSeries()`, `getInstance()`
/// - `RetrieveKeys` fluent API for building retrieve identifiers
/// - `RetrieveProgress` for sub-operation progress tracking
/// - `RetrieveResult` for operation results
/// - Storage SOP Class negotiation for C-GET
/// - Async stream-based C-GET with incoming C-STORE handling
///
/// ## Milestone 6.7 - Advanced Networking Features (Partial)
///
/// - `DICOMClient` unified high-level API
/// - `DICOMClientConfiguration` with server settings and TLS options
/// - `RetryPolicy` configurable retry policies with exponential backoff
/// - Automatic retry logic for transient network failures
/// - `DICOMLogger` centralized logging with configurable handlers
/// - `DICOMLogLevel` (debug, info, warning, error)
/// - `DICOMLogCategory` for filtering by component (connection, association, PDU, etc.)
/// - `OSLogHandler` integration with Apple's Unified Logging System (Apple platforms)
/// - `ConsoleLogHandler` for simple console output
/// - Helper methods for common logging patterns (PDU events, state transitions, operations)
///
/// ## Usage
///
/// ### Creating DIMSE Messages
///
/// ```swift
/// import DICOMNetwork
///
/// // Create a C-ECHO request
/// let echoRequest = CEchoRequest(
///     messageID: 1,
///     presentationContextID: 1
/// )
///
/// // Create a C-STORE request
/// let storeRequest = CStoreRequest(
///     messageID: 2,
///     affectedSOPClassUID: "1.2.840.10008.5.1.4.1.1.7",
///     affectedSOPInstanceUID: "1.2.3.4.5.6.7.8.9",
///     priority: .medium,
///     presentationContextID: 3
/// )
///
/// // Create a C-FIND request
/// let findRequest = CFindRequest(
///     messageID: 3,
///     affectedSOPClassUID: "1.2.840.10008.5.1.4.1.2.2.1",
///     priority: .high,
///     presentationContextID: 5
/// )
/// ```
///
/// ### Assembling Messages from PDVs
///
/// ```swift
/// import DICOMNetwork
///
/// let assembler = MessageAssembler()
///
/// // Add PDVs from received P-DATA-TF PDUs
/// for pdu in receivedPDUs {
///     if let message = try assembler.addPDVs(from: pdu) {
///         // Message is complete
///         if let echoResponse = message.asCEchoResponse() {
///             print("C-ECHO status: \(echoResponse.status)")
///         }
///     }
/// }
/// ```
///
/// ### Fragmenting Messages for Transmission
///
/// ```swift
/// import DICOMNetwork
///
/// let fragmenter = MessageFragmenter(maxPDUSize: 16384)
///
/// let storeRequest = CStoreRequest(
///     messageID: 1,
///     affectedSOPClassUID: sopClassUID,
///     affectedSOPInstanceUID: sopInstanceUID,
///     presentationContextID: 3
/// )
///
/// let pdus = fragmenter.fragmentMessage(
///     commandSet: storeRequest.commandSet,
///     dataSet: dataSetBytes,
///     presentationContextID: 3
/// )
///
/// for pdu in pdus {
///     try await connection.send(pdu: pdu)
/// }
/// ```
///
/// ### Association and Data Transfer
///
/// ```swift
/// import DICOMNetwork
///
/// // Configure association
/// let config = AssociationConfiguration(
///     callingAETitle: try AETitle("MY_SCU"),
///     calledAETitle: try AETitle("PACS"),
///     host: "pacs.hospital.com",
///     port: 11112,
///     implementationClassUID: "1.2.3.4.5.6.7.8.9"
/// )
///
/// // Create association
/// let association = Association(configuration: config)
///
/// // Request presentation contexts
/// let context = try PresentationContext(
///     id: 1,
///     abstractSyntax: "1.2.840.10008.1.1",  // Verification SOP Class
///     transferSyntaxes: ["1.2.840.10008.1.2.1"]
/// )
///
/// // Establish association
/// let negotiated = try await association.request(presentationContexts: [context])
///
/// // Send and receive data
/// let pdv = PresentationDataValue(
///     presentationContextID: 1,
///     isCommand: true,
///     isLastFragment: true,
///     data: commandData
/// )
/// try await association.send(pdv: pdv)
/// let response = try await association.receive()
///
/// // Release association
/// try await association.release()
/// ```
///
/// ### DICOM Verification Service (C-ECHO)
///
/// ```swift
/// import DICOMNetwork
///
/// // Simple connectivity test
/// let success = try await DICOMVerificationService.verify(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS"
/// )
/// print("Connection successful: \(success)")
///
/// // Detailed verification with timing
/// let result = try await DICOMVerificationService.echo(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS",
///     timeout: 10
/// )
/// print("Status: \(result.status)")
/// print("Round-trip time: \(result.roundTripTime)s")
/// ```
///
/// ### DICOM Retrieve Service (C-MOVE)
///
/// ```swift
/// import DICOMNetwork
///
/// // Move a study to a destination AE
/// let result = try await DICOMRetrieveService.moveStudy(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS",
///     studyInstanceUID: "1.2.3.4.5.6.7.8.9",
///     moveDestination: "MY_SCP"
/// ) { progress in
///     print("Progress: \(progress.completed)/\(progress.total)")
/// }
/// print("Completed: \(result.progress.completed)")
/// print("Failed: \(result.progress.failed)")
/// ```
///
/// ### DICOM Download Service (C-GET)
///
/// ```swift
/// import DICOMNetwork
///
/// // Download a study directly
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
///     case .instance(let sopInstanceUID, let sopClassUID, let data):
///         print("Received: \(sopInstanceUID)")
///         // Process the DICOM data
///     case .completed(let result):
///         print("Done: \(result.progress.completed) instances")
///     case .error(let error):
///         print("Error: \(error)")
///     }
/// }
/// ```
///
/// ### Using DICOMClient (High-Level API)
///
/// ```swift
/// import DICOMNetwork
///
/// // Create a client with retry policy
/// let client = try DICOMClient(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MY_SCU",
///     calledAE: "PACS",
///     retryPolicy: .exponentialBackoff(maxRetries: 3)
/// )
///
/// // Test connectivity
/// let connected = try await client.verify()
///
/// // Query for studies
/// let studies = try await client.findStudies(
///     matching: QueryKeys(level: .study)
///         .patientName("DOE^JOHN*")
/// )
///
/// // Download using C-GET
/// for await event in try await client.getStudy(studyInstanceUID: studies[0].studyInstanceUID!) {
///     // Handle events...
/// }
/// ```
///
/// ### Configuring Logging
///
/// ```swift
/// import DICOMNetwork
///
/// // Enable logging with console output (for debugging)
/// await DICOMLogger.shared.addHandler(ConsoleLogHandler())
/// await DICOMLogger.shared.setMinimumLevel(.debug)
///
/// // Or use Apple's Unified Logging (production)
/// #if canImport(os)
/// await DICOMLogger.shared.addHandler(OSLogHandler())
/// #endif
///
/// // Filter to specific categories
/// await DICOMLogger.shared.setEnabledCategories([.connection, .association])
///
/// // Log messages (fire-and-forget style)
/// DICOMLogger.info(.connection, "Connecting to PACS")
/// DICOMLogger.debug(.pdu, "PDU sent", context: ["size": "256"])
/// DICOMLogger.warning(.retrieve, "Retry attempt", context: ["attempt": "2"])
/// DICOMLogger.error(.association, "Association rejected")
/// ```

// MARK: - PDU Types
@_exported import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — carries no DICOM-standard data beyond doc examples whose UIDs (Verification, Secondary Capture, Study Root FIND, Explicit VR LE) are registered in PS3.6 2026a Table A-1

// Re-export all public types
