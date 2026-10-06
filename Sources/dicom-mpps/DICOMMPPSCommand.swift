// NEMA-verified: 2026a, checked 2026-10-06 — --status / --patient-sex / --patient-birth-date rules and the SCP warning line are DICOMNetwork DICOMMPPSService's (D263, re-read against PS3.3 Tables C.4-14 / C.2-3 and PS3.5 Table 6.2-1); the 24 attribute-bearing options of `create`/`update` diffed
// against PS3.4 2026a Table F.7.2-1 (130 rows: N-CREATE / N-SET / Final State usage per tag); --status words
// against PS3.3 Table C.4-14 (0040,0252) Enumerated Values (3) and the N-CREATE/N-SET rules of PS3.4 F.7.2.1.2,
// F.7.2.1.3, F.7.2.2.2; --patient-sex against PS3.3 Table C.2-3 (0010,0040) Enumerated Values (3);
// --patient-birth-date against PS3.5 Table 6.2-1 DA; --discontinuation-reason examples against PS3.16 CID 9300
// (6 DCM rows + CID 9301 17 rows, Table D-1); SOP Class UIDs against PS3.6 Table A-1 (3); response status names
// worded by DICOMNetwork's DIMSEServiceStatusText (PS3.7 Annex C, PS3.4 Table F.7.2-2; the CLI's own
// 22-code table removed, D220). Data-set building, the status
// enum and the console text live in DICOMNetwork (MPPSService, NetworkConsole).
import Foundation
import ArgumentParser
import DICOMCore
import DICOMNetwork

@main
struct DICOMMPPSCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-mpps",
        abstract: "DICOM Modality Performed Procedure Step (MPPS) operations",
        discussion: """
            Create and update DICOM Modality Performed Procedure Step (MPPS) instances.
            Implements the MPPS SOP Class for notifying PACS/RIS systems about
            procedure execution status.
            
            URL Format:
              hostname               - PACS server hostname or IP address
              hostname:port          - Hostname with embedded port
              --port port            - Optional explicit port (default: 11112)
            
            Examples:
              # Create MPPS (procedure started)
              dicom-mpps create server --port 11112 \\
                --aet MODALITY --called-aet PACS_SCP \\
                --study-uid 1.2.3.4.5.6.7.8.9 --modality CT \\
                --status "IN PROGRESS"
              
              # Update MPPS (procedure completed). COMPLETED needs at least one
              # Performed Series item (PS3.4 Table F.7.2-1, final state), so name
              # the series and the images it produced with their real SOP Class.
              dicom-mpps update server --port 11112 \\
                --aet MODALITY \\
                --mpps-uid 1.2.840.113619.2.xxx \\
                --status COMPLETED \\
                --study-uid 1.2.3.4.5.6.7.8.9 --series-uid 1.2.3.4.5.6.7.8.9.1 \\
                --sop-class-uid 1.2.840.10008.5.1.4.1.1.2 \\
                --image-uid 1.2.3.4.5.6.7.8.9.1.1

              # Discontinue with a coded reason (PS3.16 CID 9300 "Procedure
              # Discontinuation Reason", scheme DCM)
              dicom-mpps update server --port 11112 \\
                --aet MODALITY \\
                --mpps-uid 1.2.840.113619.2.xxx \\
                --status DISCONTINUED \\
                --discontinuation-reason "110513|DCM|Discontinued for unspecified reason"

            Status words (PS3.3 Table C.4-14 Enumerated Values, PS3.4 F.7.2.1.2 / F.7.2.2.2):
              create  --status "IN PROGRESS"            (the only value N-CREATE may carry)
              update  --status COMPLETED | DISCONTINUED (final; no further N-SET afterwards)

            Reference: PS3.4 Annex F - Modality Performed Procedure Step SOP Class
            """,
        version: "1.0.0",
        subcommands: [Create.self, Update.self]
    )
    
    // MARK: - Shared Helper Functions
    
    /// Resolves the final host and port from ``--host`` and ``--port`` options.
    static func resolveHostPort(host: String, port: UInt16?) -> (host: String, port: UInt16) {
        var resolvedHost = host
        var resolvedPort: UInt16 = port ?? 11112

        if resolvedHost.hasPrefix("pacs://") {
            resolvedHost = String(resolvedHost.dropFirst(7))
        }

        if let lastColon = resolvedHost.lastIndex(of: ":") {
            let portString = String(resolvedHost[resolvedHost.index(after: lastColon)...])
            if let embeddedPort = UInt16(portString) {
                resolvedHost = String(resolvedHost[..<lastColon])
                if port == nil {
                    resolvedPort = embeddedPort
                }
            }
        }

        return (resolvedHost, resolvedPort)
    }
    
    /// The rule and refusal are DICOMNetwork's `DICOMMPPSService.parseStatus` /
    /// `invalidStatusMessage` (PS3.3 Table C.4-14, D263).
    static func parseStatus(_ statusString: String) throws -> MPPSStatus {
        guard let status = DICOMMPPSService.parseStatus(statusString) else {
            throw ValidationError(DICOMMPPSService.invalidStatusMessage)
        }
        return status
    }

    /// Parses a `CODE|SCHEME|MEANING` coded entry (e.g. `110513|DCM|Discontinued for unspecified reason`,
    /// PS3.16 CID 9301 via CID 9300).
    ///
    /// The grammar lives in `MPPSCodedEntry.parse` (DICOMNetwork) so this CLI and the
    /// CLI Workshop's matching field accept exactly the same input and reject it with
    /// the same wording.
    static func parseCodedEntry(_ raw: String, option: String) throws -> MPPSCodedEntry {
        guard let entry = MPPSCodedEntry.parse(raw) else {
            throw ValidationError(MPPSCodedEntry.parseErrorMessage(option: option))
        }
        return entry
    }

    /// Prints an SCP warning status to stderr — the operation was performed, but
    /// the SCP coerced or dropped attributes (PS3.7 Annex C). The line is
    /// DICOMNetwork's `DICOMMPPSService.warningLine` (D263).
    static func reportWarning(_ result: MPPSOperationResult, operation: String) {
        if let warning = result.warning {
            FileHandle.standardError.write(Data(DICOMMPPSService.warningLine(warning, operation: operation).utf8))
        }
    }

    /// The response status worded per PS3.4 Table F.7.2-2 (N-SET) or PS3.7 Annex C —
    /// DICOMNetwork's `DICOMMPPSService.describeStatus` (D263).
    static func describe(_ status: DIMSEStatus, operation: String) -> String {
        DICOMMPPSService.describeStatus(status, operation: operation)
    }

    /// Patient's Sex (0010,0040) Enumerated Values, PS3.3 2026a Table C.2-3: M, F, O.
    @available(*, deprecated, renamed: "DICOMMPPSService.patientSexEnumeratedValues")
    static var patientSexEnumeratedValues: [String] { DICOMMPPSService.patientSexEnumeratedValues }

    /// Returns the canonical value of `--patient-sex`, or throws when it is not an
    /// Enumerated Value (case-insensitive input is accepted and upper-cased) —
    /// DICOMNetwork's `DICOMMPPSService.canonicalPatientSex` (D263).
    static func validatePatientSex(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard let canonical = DICOMMPPSService.canonicalPatientSex(value) else {
            throw ValidationError(DICOMMPPSService.patientSexErrorMessage(value))
        }
        return canonical
    }

    /// Checks `--patient-birth-date` is a DA value YYYYMMDD (PS3.5 Table 6.2-1) —
    /// DICOMNetwork's `DICOMMPPSService.isValidBirthDate` (D263).
    static func validateBirthDate(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard DICOMMPPSService.isValidBirthDate(value) else {
            throw ValidationError(DICOMMPPSService.birthDateErrorMessage(value))
        }
        return value
    }
}

// MARK: - Create Subcommand

extension DICOMMPPSCommand {
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create MPPS instance (N-CREATE)"
        )
        
        @Argument(help: "PACS server hostname or IP address, optionally with port (host:port)")
        var host: String
        
        @Option(name: .long, help: "PACS server port (default: 11112)")
        var port: UInt16?
        
        @Option(name: .long, help: "Local Application Entity Title (calling AE)")
        var aet: String
        
        @Option(name: .long, help: "Remote Application Entity Title (default: ANY-SCP)")
        var calledAet: String = "ANY-SCP"
        
        @Option(name: .long, help: "Study Instance UID for the procedure")
        var studyUid: String
        
        @Option(name: .long, help: "Patient's Name (0010,0010) in DICOM format e.g. DOE^JOHN")
        var patientName: String?
        
        @Option(name: .long, help: "Patient ID (0010,0020)")
        var patientId: String?
        
        @Option(name: .long, help: "Initial status — must be IN PROGRESS; N-CREATE always starts the step (default: IN PROGRESS)")
        var status: String = "IN PROGRESS"
        
        @Option(name: .long, help: "Scheduled Procedure Step ID from the MWL item — links this MPPS to the worklist entry so the server can transition its status (0040,0009)")
        var spsId: String?
        
        @Option(name: .long, help: "Accession Number linking the procedure to the imaging order (0008,0050)")
        var accessionNumber: String?

        @Option(name: .long, help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("value")))
        var modality: String?

        @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
        var strictModality: Bool = false

        @Option(name: .long, help: "Patient's Birth Date (0010,0030) as YYYYMMDD (VR DA, PS3.5 Table 6.2-1)")
        var patientBirthDate: String?

        @Option(name: .long, help: "Patient's Sex (0010,0040) Enumerated Values M, F or O (PS3.3 Table C.2-3)")
        var patientSex: String?

        @Option(name: .long, help: "Study ID (0020,0010)")
        var studyId: String?

        @Option(name: .long, help: "Performed Station Name (0040,0242)")
        var stationName: String?

        @Option(name: .long, help: "Performed Location (0040,0243)")
        var performedLocation: String?

        @Option(name: .long, help: "Performed Procedure Step ID (0040,0253) (default: 1)")
        var procedureStepId: String?

        @Option(name: .long, help: "Performed Procedure Step Description (0040,0254)")
        var procedureStepDescription: String?

        @Option(name: .long, help: "Performing Physician's Name (0008,1050), DICOM PN format")
        var performingPhysician: String?

        @Option(name: .long, help: "Requested Procedure ID (0040,1001) from the MWL item")
        var requestedProcedureId: String?

        @Option(name: .long, help: "Requested Procedure Description (0032,1060) from the MWL item")
        var requestedProcedureDescription: String?

        @Option(name: .long, help: "Scheduled Procedure Step Description (0040,0007) from the MWL item")
        var spsDescription: String?

        @Option(name: .long, help: "Referenced Study SOP Instance UID (0008,1155) from the MWL item's Referenced Study Sequence")
        var referencedStudyUid: String?

        @Option(name: .long, help: "Force the Specific Character Set (0008,0005), e.g. ISO_IR 100 or ISO_IR 192. By default the narrowest set that represents every text value is chosen")
        var specificCharacterSet: String?
        
        @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
        var timeout: Int = 60
        
        @Flag(name: .shortAndLong, help: "Show verbose output")
        var verbose: Bool = false
        
        mutating func run() async throws {
            // Validate --modality up front: an unrecognized code otherwise
            // reaches the PACS as a filter that silently matches nothing.
            modality = try ModalityOptionValidator.resolve(
                modality, strict: strictModality, verbose: verbose)
            // Modality (0008,0060) is Type 1 in the N-CREATE (PS3.4 Table F.7.2-1,
            // Image Acquisition Results); without it the data set would carry an
            // empty Type 1 attribute.
            guard let modality, !modality.isEmpty else {
                throw ValidationError("--modality is required: Modality (0008,0060) is Type 1 in the MPPS N-CREATE (PS3.4 Table F.7.2-1)")
            }
            patientSex = try DICOMMPPSCommand.validatePatientSex(patientSex)
            patientBirthDate = try DICOMMPPSCommand.validateBirthDate(patientBirthDate)

            #if canImport(Network)
            let serverInfo = DICOMMPPSCommand.resolveHostPort(host: host, port: port)

            // Parse status
            let mppsStatus = try DICOMMPPSCommand.parseStatus(status)

            // N-CREATE always STARTS the performed procedure step IN PROGRESS; the
            // terminal states (COMPLETED / DISCONTINUED) are reached only via `update`
            // (N-SET). Reject anything else so a step can never be minted already in a
            // terminal state — mirroring the Update subcommand's status guard.
            guard mppsStatus == .inProgress else {
                throw ValidationError("Create status must be IN PROGRESS — use 'dicom-mpps update --status COMPLETED|DISCONTINUED' to transition the step")
            }

            // Verbose header via the SHARED NetworkConsole formatter (DICOMNetwork) to
            // STDOUT — the IDENTICAL builder the Studio MPPS panel uses, so the chrome
            // can't drift. The order matches the app (the parity harness diffs the
            // binary's stdout+stderr against the app's in-process console).
            if verbose {
                var fields: [(label: String, value: String)] = [("Study UID:", studyUid)]
                if let patientName { fields.append(("Patient Name:", patientName)) }
                if let patientId { fields.append(("Patient ID:", patientId)) }
                if let spsId { fields.append(("SPS ID:", spsId)) }
                if let accessionNumber { fields.append(("Accession Number:", accessionNumber)) }
                print(NetworkConsole.mppsHeader(
                    isCreate: true,
                    host: serverInfo.host, port: serverInfo.port,
                    callingAE: aet, calledAE: calledAet,
                    status: mppsStatus.rawValue, timeout: timeout,
                    fields: fields), terminator: "")
            }

            print(NetworkConsole.mppsProgress(isCreate: true), terminator: "")

            // Create MPPS
            let result = try await DICOMMPPSService.createDetailed(
                host: serverInfo.host,
                port: serverInfo.port,
                callingAE: aet,
                calledAE: calledAet,
                studyInstanceUID: studyUid,
                status: mppsStatus,
                timeout: TimeInterval(timeout),
                patientName: patientName,
                patientID: patientId,
                modality: modality,
                procedureStepID: procedureStepId,
                procedureStepDescription: procedureStepDescription,
                performingPhysicianName: performingPhysician,
                performedStationName: stationName,
                accessionNumber: accessionNumber,
                scheduledProcedureStepID: spsId,
                patientBirthDate: patientBirthDate,
                patientSex: patientSex,
                studyID: studyId,
                performedLocation: performedLocation,
                requestedProcedureID: requestedProcedureId,
                requestedProcedureDescription: requestedProcedureDescription,
                scheduledProcedureStepDescription: spsDescription,
                referencedStudySOPInstanceUID: referencedStudyUid,
                specificCharacterSet: specificCharacterSet
                )
            let mppsInstanceUID = result.sopInstanceUID
            DICOMMPPSCommand.reportWarning(result, operation: "N-CREATE")
            if result.sopInstanceUIDWasReassigned {
                FileHandle.standardError.write(Data(
                    "note: SCP assigned MPPS SOP Instance UID \(result.sopInstanceUID) (requested \(result.requestedSOPInstanceUID)); use the assigned UID for the N-SET (PS3.7 10.1.5.1.4)\n".utf8))
            }

            // Result via the SHARED formatter — preserves the "MPPS Instance UID:" marker
            // the parity comparator threads into the subsequent N-SET. The CLI-specific
            // next-step hint (the literal update command) stays local: it's legitimately
            // different from the app's UI instruction.
            print(NetworkConsole.mppsCreateResult(uid: mppsInstanceUID), terminator: "")
            print("")
            print("Use this UID to update the MPPS when the procedure completes")
            print("(COMPLETED needs at least one Performed Series item, PS3.4 Table F.7.2-1 final state):")
            print("  dicom-mpps update \(serverInfo.host) --port \(serverInfo.port) \\")
            print("    --aet \(aet) --mpps-uid \(mppsInstanceUID) --status COMPLETED \\")
            print("    --study-uid \(studyUid) --series-uid <SeriesInstanceUID> \\")
            print("    --sop-class-uid <SOPClassUID> --image-uid <SOPInstanceUID>")
            
            #else
            throw ValidationError("Network functionality is not available on this platform")
            #endif
        }
    }
}

// MARK: - Update Subcommand

extension DICOMMPPSCommand {
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update MPPS instance (N-SET)"
        )
        
        @Argument(help: "PACS server hostname or IP address, optionally with port (host:port)")
        var host: String
        
        @Option(name: .long, help: "PACS server port (default: 11112)")
        var port: UInt16?
        
        @Option(name: .long, help: "Local Application Entity Title (calling AE)")
        var aet: String
        
        @Option(name: .long, help: "Remote Application Entity Title (default: ANY-SCP)")
        var calledAet: String = "ANY-SCP"
        
        @Option(name: .long, help: "MPPS SOP Instance UID to update")
        var mppsUid: String
        
        @Option(name: .long, help: "New Performed Procedure Step Status (0040,0252): COMPLETED or DISCONTINUED (PS3.3 Table C.4-14; PS3.4 F.7.2.2.2 — final, no later N-SET). COMPLETED requires at least one Performed Series item (--series-uid with --image-uid), PS3.4 Table F.7.2-1 final state")
        var status: String
        
        @Option(name: .long, help: "Study Instance UID for referenced images")
        var studyUid: String?
        
        @Option(name: .long, help: "Series Instance UID for referenced images")
        var seriesUid: String?
        
        @Option(name: .long, help: "SOP Instance UID (0008,1155) of a referenced image, repeatable; needs --study-uid and --series-uid to form the Performed Series item")
        var imageUid: [String] = []

        @Option(name: .long, help: "SOP Class UID (0008,1150) of the referenced images, e.g. 1.2.840.10008.5.1.4.1.1.2 for CT. Without it the Secondary Capture class is sent, which is wrong for anything but SC")
        var sopClassUid: String?

        @Option(name: .long, help: "Protocol Name (0018,1030) — Type 1 in every Performed Series item (default: UNSPECIFIED)")
        var protocolName: String?

        @Option(name: .long, help: "Series Description (0008,103E) for the performed series")
        var seriesDescription: String?

        @Option(name: .long, help: "Operators' Name (0008,1070), DICOM PN format")
        var operatorName: String?

        @Option(name: .long, help: "Performing Physician's Name (0008,1050), DICOM PN format")
        var performingPhysician: String?

        @Flag(name: .long, help: "Also send the Scheduled Step Attributes Sequence (0040,0270) in the N-SET. PS3.4 forbids it; use only for an SCP known to require it")
        var legacyNsetScheduledAttributes: Bool = false

        @Option(name: .long, help: "Performed Procedure Step Discontinuation Reason Code Sequence (0040,0281) as CODE|SCHEME|MEANING, only with --status DISCONTINUED. Codes normally come from PS3.16 CID 9300 'Procedure Discontinuation Reason' (which includes CID 9301) with scheme DCM, e.g. \"110513|DCM|Discontinued for unspecified reason\", \"110500|DCM|Doctor canceled procedure\", \"110501|DCM|Equipment failure\", \"110507|DCM|Patient did not arrive\"")
        var discontinuationReason: String?

        @Option(name: .long, help: "Force the Specific Character Set (0008,0005), e.g. ISO_IR 100 or ISO_IR 192. By default the narrowest set that represents every text value is chosen")
        var specificCharacterSet: String?
        
        @Option(name: .long, help: "Connection timeout in seconds (default: 60)")
        var timeout: Int = 60
        
        @Flag(name: .shortAndLong, help: "Show verbose output")
        var verbose: Bool = false
        
        mutating func run() async throws {
            #if canImport(Network)
            let serverInfo = DICOMMPPSCommand.resolveHostPort(host: host, port: port)
            
            // Parse status
            let mppsStatus = try DICOMMPPSCommand.parseStatus(status)
            
            // Validate status
            guard mppsStatus == .completed || mppsStatus == .discontinued else {
                throw ValidationError("Update status must be COMPLETED or DISCONTINUED")
            }

            var reason: MPPSCodedEntry?
            if let discontinuationReason {
                guard mppsStatus == .discontinued else {
                    throw ValidationError("--discontinuation-reason is only valid with --status DISCONTINUED")
                }
                reason = try DICOMMPPSCommand.parseCodedEntry(discontinuationReason, option: "--discontinuation-reason")
            }

            // Image references are only encoded inside a Performed Series item, which
            // needs the Study and Series Instance UIDs; without them the --image-uid
            // values used to be dropped silently.
            if !imageUid.isEmpty, studyUid == nil || seriesUid == nil {
                throw ValidationError("--image-uid needs --study-uid and --series-uid: Referenced Image Sequence (0008,1140) items live in a Performed Series Sequence (0040,0340) item with its Series Instance UID (0020,000E) (PS3.4 Table F.7.2-1)")
            }

            if !imageUid.isEmpty, sopClassUid == nil {
                FileHandle.standardError.write(Data(
                    "warning: --sop-class-uid not given; Referenced SOP Class UID defaults to Secondary Capture (1.2.840.10008.5.1.4.1.1.7), which is non-conformant for CT/MR/… images\n".utf8))
            }
            
            // Verbose header via the SHARED NetworkConsole formatter (DICOMNetwork).
            if verbose {
                var fields: [(label: String, value: String)] = [("MPPS UID:", mppsUid)]
                if studyUid != nil, seriesUid != nil {
                    fields.append(("Referenced Images:", "\(imageUid.count) instance(s)"))
                }
                print(NetworkConsole.mppsHeader(
                    isCreate: false,
                    host: serverInfo.host, port: serverInfo.port,
                    callingAE: aet, calledAE: calledAet,
                    status: mppsStatus.rawValue, timeout: timeout,
                    fields: fields), terminator: "")
            }

            // Build referenced SOPs list
            var referencedSOPs: [(studyUID: String, seriesUID: String, sopInstanceUID: String)] = []
            if let study = studyUid, let series = seriesUid {
                for imageUID in imageUid {
                    referencedSOPs.append((study, series, imageUID))
                }
            }

            print(NetworkConsole.mppsProgress(isCreate: false), terminator: "")

            // Update MPPS
            let result = try await DICOMMPPSService.update(
                host: serverInfo.host,
                port: serverInfo.port,
                callingAE: aet,
                calledAE: calledAet,
                mppsInstanceUID: mppsUid,
                status: mppsStatus,
                referencedSOPs: referencedSOPs,
                timeout: TimeInterval(timeout),
                referencedSOPClassUID: sopClassUid,
                protocolName: protocolName,
                seriesDescription: seriesDescription,
                operatorsName: operatorName,
                performingPhysicianName: performingPhysician,
                legacyNSetScheduledStepAttributes: legacyNsetScheduledAttributes,
                discontinuationReason: reason,
                specificCharacterSet: specificCharacterSet
                )
            DICOMMPPSCommand.reportWarning(result, operation: "N-SET")

            // Result via the SHARED formatter — preserves the "New Status:" /
            // "Referenced Images:" markers the parity comparator parses.
            print(NetworkConsole.mppsUpdateResult(
                uid: mppsUid,
                status: mppsStatus.rawValue,
                referencedImages: referencedSOPs.count), terminator: "")
            
            #else
            throw ValidationError("Network functionality is not available on this platform")
            #endif
        }
    }
}

