// WorklistCreateViewModel.swift
// DICOMStudio
//
// DICOM Studio — creates a Modality Worklist item from the Networking panel's worklist area:
// an HL7 v2 ORM^O01 order over MLLP, or the archive's REST API (dcm4chee-arc `mwlitems`).
// Moved out of the CLI Workshop's dicom-mwl tool on 2026-10-06 (P-STUDIO-MWL-CREATE). Owner
// decision: the create flow stays in the app only (Networking panel); dicom-mwl has no `create`
// subcommand and none is added to the CLI or to DICOMNetwork, so the Workshop's dicom-mwl tool
// offers only the CLI's own subcommand (query). Behaviour unchanged from the Workshop flow.
// Reference: DICOM PS3.3 2026a Table C.4-10 (Scheduled Procedure Step Module), Table C.4-11
// (Requested Procedure Module), Table C.4-12 (Imaging Service Request Module), Table C.7-1
// (Patient Module); PS3.4 Annex K (the worklist the item is then queried from). HL7 ORM^O01 /
// MLLP and the REST endpoint are not DICOM.
// NEMA-verified: 2026a, checked 2026-10-06 — the 16 attributes the form fills compared by script with PS3.3 2026a: (0040,0001) (0040,0010) (0040,0002) (0040,0003) (0040,0009) (0040,0007) (0040,0006) (0008,0060) in Table C.4-10, (0040,1001) (0032,1060) in Table C.4-11, (0008,0050) (0008,0090) in Table C.4-12, (0010,0010) (0010,0020) (0010,0030) (0010,0040) in Table C.7-1 (16/16 rows found); Patient's Sex picker M / F / O = the Table C.7-1 Enumerated Values; the Scheduled Procedure Step Status of a created item is the server's (Table C.4-10 Defined Terms, not set here); no DIMSE service creates a worklist item (PS3.4 Annex K defines C-FIND only)

import Foundation
import Observation
import DICOMNetwork

/// How the worklist item is created. Neither is a DICOM service: PS3.4 Annex K defines only
/// the C-FIND query of a worklist.
public enum WorklistCreateMethod: String, Sendable, CaseIterable, Identifiable {
    /// HL7 v2 ORM^O01 order message over MLLP; the archive creates patient and item.
    case hl7
    /// DICOM JSON POSTed to the archive's REST API (the patient must exist first).
    case rest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hl7:  return "HL7 ORM^O01 (MLLP)"
        case .rest: return "REST API"
        }
    }
}

/// The Networking panel's "New Worklist Item" form and its executor (P-STUDIO-MWL-CREATE).
///
/// The fields and the run are the former CLI Workshop dicom-mwl `create` operation, unchanged:
/// the same defaults (calling AE DICOMSTUDIO, called AE ANY-SCP, port 11112, HL7 port 2575,
/// timeout 60 s, modality CT, MSH-3..6 DICOMSTUDIO / IMAGING / DCM4CHEE / HOSPITAL), the same
/// DICOMNetwork calls (`DICOMModalityWorklistService.createViaHL7` / `.create`), the same console
/// lines (`NetworkConsole.mwlCreateDetailBlock`) and the same exit codes (0 / 1). Owner decision
/// (2026-10-06): this stays in the app; dicom-mwl gets no `create` subcommand.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class WorklistCreateViewModel: Identifiable {

    /// Identity of one sheet presentation.
    public nonisolated let id = UUID()

    // MARK: - Connection

    /// Server host, optionally `host:port`.
    public var host: String = ""
    /// DICOM port (used by the REST method's AE path; default 11112).
    public var port: String = "11112"
    /// Calling AE Title.
    public var callingAET: String = "DICOMSTUDIO"
    /// Called AE Title (the REST path segment `aets/<AET>`).
    public var calledAET: String = "ANY-SCP"
    /// Timeout in seconds.
    public var timeout: String = "60"
    /// Creation method.
    public var method: WorklistCreateMethod = .hl7

    // MARK: - HL7

    public var hl7Port: String = "2575"
    /// MSH-3 Sending Application.
    public var sendingApplication: String = "DICOMSTUDIO"
    /// MSH-4 Sending Facility.
    public var sendingFacility: String = "IMAGING"
    /// MSH-5 Receiving Application.
    public var receivingApplication: String = "DCM4CHEE"
    /// MSH-6 Receiving Facility.
    public var receivingFacility: String = "HOSPITAL"

    // MARK: - REST

    /// REST base URL; empty = `http://<host>:8080/dcm4chee-arc`.
    public var restBaseURL: String = ""

    // MARK: - Patient (PS3.3 Table C.7-1)

    /// Patient's Name (0010,0010) — required.
    public var patientName: String = ""
    /// Patient ID (0010,0020) — required.
    public var patientID: String = ""
    /// Patient's Birth Date (0010,0030), YYYYMMDD.
    public var patientBirthDate: String = ""
    /// Patient's Sex (0010,0040): "", M, F or O.
    public var patientSex: String = ""

    // MARK: - Imaging Service Request / Requested Procedure (PS3.3 Tables C.4-12, C.4-11)

    /// Accession Number (0008,0050).
    public var accessionNumber: String = ""
    /// Referring Physician's Name (0008,0090).
    public var referringPhysician: String = ""
    /// Requested Procedure ID (0040,1001).
    public var procedureID: String = ""
    /// Requested Procedure Description (0032,1060).
    public var procedureDescription: String = ""

    // MARK: - Scheduled Procedure Step (PS3.3 Table C.4-10)

    /// Modality (0008,0060); default CT.
    public var modality: String = "CT"
    /// Scheduled Station AE Title (0040,0001).
    public var scheduledStationAET: String = ""
    /// Scheduled Station Name (0040,0010).
    public var stationName: String = ""
    /// Scheduled Procedure Step Start Date (0040,0002): YYYYMMDD, today or tomorrow; empty = today.
    public var scheduledDate: String = ""
    /// Scheduled Procedure Step Start Time (0040,0003), HHMMSS.
    public var scheduledTime: String = ""
    /// Scheduled Procedure Step ID (0040,0009).
    public var spsID: String = ""
    /// Scheduled Procedure Step Description (0040,0007).
    public var spsDescription: String = ""
    /// Scheduled Performing Physician's Name (0040,0006).
    public var performingPhysician: String = ""

    // MARK: - Run state

    public private(set) var output: String = ""
    public private(set) var isRunning: Bool = false
    /// 0 on success, 1 on any failure (as the former Workshop run recorded it).
    public private(set) var lastExitCode: Int? = nil

    /// Modality picker values (the Workshop's create picker: every known modality code).
    public static let modalityValues: [String] = ModalityMapping.allCodes.sorted()
    /// Patient's Sex picker: empty plus the PS3.3 Table C.7-1 Enumerated Values.
    public static let patientSexValues: [String] = ["", "M", "F", "O"]

    public init() {}

    public func clearOutput() {
        output = ""
        lastExitCode = nil
    }

    private func append(_ text: String) { output += text }

    private func finish(_ code: Int) {
        lastExitCode = code
        isRunning = false
    }

    // MARK: - Run

    /// Creates the worklist item with the current form values.
    public func run() async {
        isRunning = true
        let timeoutValue = TimeInterval(timeout) ?? 60
        guard let server = Self.resolveHostPort(host, explicitPort: port) else {
            append("Error: A valid host is required (e.g. hostname or hostname:11112).\n")
            finish(1)
            return
        }
        let callingAE = callingAET.isEmpty ? "DICOMSTUDIO" : callingAET
        let calledAE = calledAET.isEmpty ? "ANY-SCP" : calledAET
        let modalityValue = modality.isEmpty ? "CT" : modality

        guard !patientName.isEmpty else {
            append("Error: Patient Name is required for worklist creation.\n")
            finish(1)
            return
        }
        guard !patientID.isEmpty else {
            append("Error: Patient ID is required for worklist creation.\n")
            finish(1)
            return
        }

        let resolvedDate: String
        if scheduledDate.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            resolvedDate = formatter.string(from: Date())
        } else {
            resolvedDate = Self.resolvedWorklistDate(scheduledDate)
        }

        switch method {
        case .hl7:
            await runHL7(host: server.host, timeout: timeoutValue, modality: modalityValue, resolvedDate: resolvedDate)
        case .rest:
            await runREST(host: server.host, port: server.port, callingAE: callingAE, calledAE: calledAE,
                          timeout: timeoutValue, modality: modalityValue, resolvedDate: resolvedDate)
        }
    }

    private func detailBlock(modality: String, resolvedDate: String) -> String {
        NetworkConsole.mwlCreateDetailBlock(
            patientName: patientName, patientID: patientID,
            patientDOB: patientBirthDate, patientSex: patientSex,
            accessionNumber: accessionNumber, referringPhysician: referringPhysician,
            modality: modality, scheduledDate: resolvedDate, scheduledTime: scheduledTime,
            stationAET: scheduledStationAET, stationName: stationName,
            spsID: spsID, spsDescription: spsDescription,
            procedureID: procedureID, procedureDescription: procedureDescription,
            performingPhysician: performingPhysician)
    }

    private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    /// HL7 ORM^O01 over MLLP.
    private func runHL7(host: String, timeout: TimeInterval, modality: String, resolvedDate: String) async {
        let hl7PortValue = UInt16(hl7Port) ?? 2575
        let sendingApp = sendingApplication.isEmpty ? "DICOMSTUDIO" : sendingApplication
        let sendingFac = sendingFacility.isEmpty ? "IMAGING" : sendingFacility
        let receivingApp = receivingApplication.isEmpty ? "DCM4CHEE" : receivingApplication
        let receivingFac = receivingFacility.isEmpty ? "HOSPITAL" : receivingFacility

        append("DICOM Modality Worklist (HL7 ORM^O01 via MLLP)\n")
        append("================================================\n")
        append("  HL7 Server:       \(host):\(hl7PortValue)\n")
        append("  Sending App:      \(sendingApp) | \(sendingFac)\n")
        append("  Receiving App:    \(receivingApp) | \(receivingFac)\n")
        append("  Timeout:          \(Int(timeout))s\n")
        append(detailBlock(modality: modality, resolvedDate: resolvedDate))
        append("\nSending HL7 ORM^O01 order message via MLLP...\n\n")

        do {
            let messageControlID = try await DICOMModalityWorklistService.createViaHL7(
                host: host,
                hl7Port: hl7PortValue,
                sendingApplication: sendingApp,
                sendingFacility: sendingFac,
                receivingApplication: receivingApp,
                receivingFacility: receivingFac,
                patientName: patientName,
                patientID: patientID,
                patientBirthDate: Self.nonEmpty(patientBirthDate),
                patientSex: Self.nonEmpty(patientSex),
                accessionNumber: Self.nonEmpty(accessionNumber),
                referringPhysicianName: Self.nonEmpty(referringPhysician),
                requestedProcedureID: Self.nonEmpty(procedureID),
                requestedProcedureDescription: Self.nonEmpty(procedureDescription),
                modality: Self.nonEmpty(modality),
                scheduledStationAETitle: Self.nonEmpty(scheduledStationAET),
                scheduledStationName: Self.nonEmpty(stationName),
                scheduledStartDate: resolvedDate,
                scheduledStartTime: Self.nonEmpty(scheduledTime),
                scheduledProcedureStepID: Self.nonEmpty(spsID),
                scheduledProcedureStepDescription: Self.nonEmpty(spsDescription),
                scheduledPerformingPhysicianName: Self.nonEmpty(performingPhysician),
                timeout: timeout
            )
            append("✅ HL7 ORM^O01 accepted by server (ACK: AA)\n")
            append("  Message Control ID: \(messageControlID)\n")
            append("  Patient and worklist item created automatically.\n")
            finish(0)
        } catch {
            let errorDesc = (error as? DICOMNetworkError)?.description ?? error.localizedDescription
            append("❌ HL7 ORM^O01 failed: \(errorDesc)\n")
            append("  💡 Hints:\n")
            append("     • Ensure the HL7 MLLP listener is running on \(host):\(hl7PortValue)\n")
            append("     • dcm4chee-arc default HL7 port is 2575 (check hl7-connection in UI config)\n")
            append("     • Verify Sending/Receiving Application names match the server config\n")
            finish(1)
        }
    }

    /// DICOM JSON over the archive's REST API.
    private func runREST(host: String, port: UInt16, callingAE: String, calledAE: String,
                         timeout: TimeInterval, modality: String, resolvedDate: String) async {
        let base: String? = restBaseURL.isEmpty ? nil : restBaseURL
        let displayURL = base ?? "http://\(host):8080/dcm4chee-arc"

        append("DICOM Modality Worklist (REST API)\n")
        append("===================================\n")
        append("  REST Endpoint:    \(displayURL)/aets/\(calledAE)/rs/mwlitems\n")
        append("  Timeout:          \(Int(timeout))s\n")
        append(detailBlock(modality: modality, resolvedDate: resolvedDate))
        append("\nCreating Modality Worklist item via REST...\n\n")

        do {
            let sopInstanceUID = try await DICOMModalityWorklistService.create(
                host: host,
                port: port,
                callingAE: callingAE,
                calledAE: calledAE,
                patientName: patientName,
                patientID: patientID,
                patientBirthDate: Self.nonEmpty(patientBirthDate),
                patientSex: Self.nonEmpty(patientSex),
                accessionNumber: Self.nonEmpty(accessionNumber),
                referringPhysicianName: Self.nonEmpty(referringPhysician),
                requestedProcedureID: Self.nonEmpty(procedureID),
                requestedProcedureDescription: Self.nonEmpty(procedureDescription),
                modality: Self.nonEmpty(modality),
                scheduledStationAETitle: Self.nonEmpty(scheduledStationAET),
                scheduledStationName: Self.nonEmpty(stationName),
                scheduledStartDate: resolvedDate,
                scheduledStartTime: Self.nonEmpty(scheduledTime),
                scheduledProcedureStepID: Self.nonEmpty(spsID),
                scheduledProcedureStepDescription: Self.nonEmpty(spsDescription),
                scheduledPerformingPhysicianName: Self.nonEmpty(performingPhysician),
                restBaseURL: base,
                timeout: timeout
            )
            append("✅ Worklist item created successfully\n")
            append("  SOP Instance UID: \(sopInstanceUID)\n")
            finish(0)
        } catch {
            let errorDesc = (error as? DICOMNetworkError)?.description ?? error.localizedDescription
            append("❌ Worklist create failed: \(errorDesc)\n")
            append("  💡 Hint: REST requires the patient to exist first on the server.\n")
            append("     Consider using \"HL7\" create method instead — it auto-creates patient + worklist.\n")
            append("     Default endpoint: http://<host>:8080/dcm4chee-arc/aets/<AET>/rs/mwlitems\n")
            append("     Set \"REST Base URL\" if your server uses a different URL.\n")
            finish(1)
        }
    }

    // MARK: - Helpers (the Workshop's, unchanged)

    /// `host`, `host:port` or `pacs://host[:port]`; an explicit port overrides the embedded one.
    nonisolated static func resolveHostPort(_ hostValue: String, explicitPort: String?) -> (host: String, port: UInt16)? {
        guard !hostValue.isEmpty else { return nil }
        var host = hostValue
        var port: UInt16 = 11112
        if host.hasPrefix("pacs://") {
            host = String(host.dropFirst(7))
        }
        if let lastColon = host.lastIndex(of: ":") {
            let portStr = String(host[host.index(after: lastColon)...])
            if let embeddedPort = UInt16(portStr) {
                host = String(host[..<lastColon])
                port = embeddedPort
            }
        }
        if let ep = explicitPort, let explicitPortNum = UInt16(ep) {
            port = explicitPortNum
        }
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    /// "today", "tomorrow" or a YYYYMMDD value (passed through).
    nonisolated static func resolvedWorklistDate(_ filter: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        switch filter.lowercased() {
        case "today":
            return formatter.string(from: Date())
        case "tomorrow":
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return formatter.string(from: tomorrow)
        default:
            return filter
        }
    }
}
