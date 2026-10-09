import XCTest
import DICOMCore
@testable import DICOMNetwork

/// End-to-end scheduled-workflow conformance: one order followed from the MWL
/// item through MPPS N-CREATE (IN PROGRESS) to the two terminal states,
/// N-SET COMPLETED and N-SET DISCONTINUED.
///
/// The three stages are checked against the standard that governs each one:
///
/// - MWL item      — PS3.3 C.4.10 (Scheduled Procedure Step module),
///                   PS3.4 Table K.6-1, encoded as PS3.18 Annex F DICOM JSON.
/// - N-CREATE      — PS3.4 Table F.7.2-1 (N-CREATE column), F.7.2.1.2.
/// - N-SET         — PS3.4 Table F.7.2-1 (N-SET column), F.7.2.1.3.
///
/// Beyond per-stage conformance the tests assert the *continuity* the workflow
/// depends on: the identifiers the worklist issued (Study Instance UID,
/// Accession Number, Requested Procedure ID, Scheduled Procedure Step ID) must
/// survive into the MPPS Scheduled Step Attributes Sequence (0040,0270) so the
/// PACS can bind the performed step back to the order.
final class MWLToMPPSWorkflowConformanceTests: XCTestCase {

    private let explicitLE = "1.2.840.10008.1.2.1"

    /// The instants the step starts and ends; fixed so the encoded DA/TM
    /// values are deterministic.
    private let stepStart = Date(timeIntervalSince1970: 1_790_000_000)
    private let stepEnd = Date(timeIntervalSince1970: 1_790_000_900)

    // MARK: - The order under test
    //
    // One scheduled CT of the chest. Every stage below is built from these
    // constants, so a mismatch anywhere surfaces as a failed continuity check.

    private enum Order {
        static let patientName = "DOE^JOHN^^^"
        static let patientID = "PID-00421"
        static let patientBirthDate = "19700115"
        static let patientSex = "M"
        static let accessionNumber = "ACC-20260923-01"
        static let referringPhysician = "HOUSE^GREGORY"
        static let studyInstanceUID = "1.2.826.0.1.3680043.9.7100.1.1"
        static let requestedProcedureID = "RP-8891"
        static let requestedProcedureDescription = "CT CHEST WITH CONTRAST"
        static let scheduledStepID = "SPS-8891-1"
        static let scheduledStepDescription = "CT CHEST W CONTRAST"
        static let scheduledStationAET = "CT_SCANNER_1"
        static let scheduledStationName = "CT-ROOM-A"
        static let scheduledStartDate = "20260923"
        static let scheduledStartTime = "141500"
        static let scheduledPerformingPhysician = "CHASE^ROBERT"
        static let modality = "CT"

        // Assigned by the modality when the step actually runs.
        static let mppsSOPInstanceUID = "1.2.826.0.1.3680043.9.7100.2.1"
        static let performedStepID = "PPS-1"
        static let performedStationAET = "CT_SCANNER_1"
        static let performedStationName = "CT-ROOM-A"
        static let performingPhysician = "CAMERON^ALLISON"
        static let operatorsName = "TECH^JANE"
        static let studyID = "ST-8891"
        static let protocolName = "CHEST_HELICAL_5MM"
        static let seriesInstanceUID = "1.2.826.0.1.3680043.9.7100.3.1"
        static let sopInstanceUID = "1.2.826.0.1.3680043.9.7100.4.1"
        static let ctImageStorage = "1.2.840.10008.5.1.4.1.1.2"
    }

    // MARK: - Byte-level helpers
    //
    // The MPPS data sets are inspected as encoded bytes: a tag is "present"
    // when its little-endian (group, element) pair occurs in the stream, and
    // its value is read back from the explicit-VR header that follows.

    private func tagBytes(_ g: UInt16, _ e: UInt16) -> [UInt8] {
        [UInt8(g & 0xFF), UInt8(g >> 8), UInt8(e & 0xFF), UInt8(e >> 8)]
    }

    private func contains(_ data: Data, _ g: UInt16, _ e: UInt16) -> Bool {
        data.range(of: Data(tagBytes(g, e))) != nil
    }

    /// The value that follows a tag's explicit-VR header, as ASCII.
    private func value(_ data: Data, _ g: UInt16, _ e: UInt16) -> String? {
        guard let r = data.range(of: Data(tagBytes(g, e))) else { return nil }
        let vrStart = r.upperBound
        guard vrStart + 4 <= data.count else { return nil }
        let vr = String(bytes: data[vrStart..<vrStart + 2], encoding: .ascii) ?? ""
        let uses4 = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vr)
        let lengthStart = vrStart + (uses4 ? 4 : 2)
        let length: Int
        let valueStart: Int
        if uses4 {
            guard lengthStart + 4 <= data.count else { return nil }
            length = Int(data[lengthStart]) | Int(data[lengthStart + 1]) << 8
                | Int(data[lengthStart + 2]) << 16 | Int(data[lengthStart + 3]) << 24
            valueStart = lengthStart + 4
        } else {
            guard lengthStart + 2 <= data.count else { return nil }
            length = Int(data[lengthStart]) | Int(data[lengthStart + 1]) << 8
            valueStart = lengthStart + 2
        }
        guard valueStart + length <= data.count else { return nil }
        return String(bytes: data[valueStart..<valueStart + length], encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
    }

    /// The VR recorded in the explicit-VR header of a tag.
    private func vr(_ data: Data, _ g: UInt16, _ e: UInt16) -> String? {
        guard let r = data.range(of: Data(tagBytes(g, e))) else { return nil }
        guard r.upperBound + 2 <= data.count else { return nil }
        return String(bytes: data[r.upperBound..<r.upperBound + 2], encoding: .ascii)
    }

    /// The DA string the encoder produces for a date — formatted in the local
    /// zone, exactly as `dateTimeStrings` does, so the expectation does not
    /// drift with the machine's timezone.
    private func expectedDA(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    // MARK: - JSON helpers (PS3.18 Annex F)

    private func jsonValue(_ json: [String: Any], _ keyword: String) -> String? {
        guard let attr = json[keyword] as? [String: Any],
              let values = attr["Value"] as? [Any], let first = values.first else { return nil }
        if let s = first as? String { return s }
        if let pn = first as? [String: Any] { return pn["Alphabetic"] as? String }
        return nil
    }

    private func jsonVR(_ json: [String: Any], _ keyword: String) -> String? {
        (json[keyword] as? [String: Any])?["vr"] as? String
    }

    /// The single item of the Scheduled Procedure Step Sequence (0040,0100).
    private func spsItem(_ json: [String: Any]) -> [String: Any]? {
        guard let sq = json["00400100"] as? [String: Any],
              let items = sq["Value"] as? [[String: Any]] else { return nil }
        return items.first
    }

    // MARK: - Stage builders

    private func worklistJSON() -> [String: Any] {
        DICOMModalityWorklistService.buildMWLCreateJSON(
            studyInstanceUID: Order.studyInstanceUID,
            patientName: Order.patientName,
            patientID: Order.patientID,
            patientBirthDate: Order.patientBirthDate,
            patientSex: Order.patientSex,
            accessionNumber: Order.accessionNumber,
            referringPhysicianName: Order.referringPhysician,
            requestedProcedureID: Order.requestedProcedureID,
            requestedProcedureDescription: Order.requestedProcedureDescription,
            modality: Order.modality,
            scheduledStationAETitle: Order.scheduledStationAET,
            scheduledStationName: Order.scheduledStationName,
            scheduledStartDate: Order.scheduledStartDate,
            scheduledStartTime: Order.scheduledStartTime,
            scheduledProcedureStepID: Order.scheduledStepID,
            scheduledProcedureStepDescription: Order.scheduledStepDescription,
            scheduledPerformingPhysicianName: Order.scheduledPerformingPhysician)
    }

    /// The step the modality creates when it starts acquiring — every value
    /// either copied from the worklist item or assigned by the modality.
    private func inProgressStep() -> MPPSProcedureStep {
        MPPSProcedureStep(
            sopInstanceUID: Order.mppsSOPInstanceUID,
            status: .inProgress,
            studyInstanceUID: Order.studyInstanceUID,
            startDateTime: stepStart,
            protocolName: Order.protocolName,
            patientName: Order.patientName,
            patientID: Order.patientID,
            modality: Order.modality,
            procedureStepID: Order.performedStepID,
            procedureStepDescription: Order.scheduledStepDescription,
            performedStationAETitle: Order.performedStationAET,
            performingPhysicianName: Order.performingPhysician,
            performedStationName: Order.performedStationName,
            accessionNumber: Order.accessionNumber,
            scheduledProcedureStepID: Order.scheduledStepID,
            patientBirthDate: Order.patientBirthDate,
            patientSex: Order.patientSex,
            studyID: Order.studyID,
            requestedProcedureID: Order.requestedProcedureID,
            requestedProcedureDescription: Order.requestedProcedureDescription,
            scheduledProcedureStepDescription: Order.scheduledStepDescription)
    }

    private func acquiredSeries() -> MPPSPerformedSeries {
        MPPSPerformedSeries(
            seriesInstanceUID: Order.seriesInstanceUID,
            protocolName: Order.protocolName,
            seriesDescription: "CHEST HELICAL",
            performingPhysicianName: Order.performingPhysician,
            operatorsName: Order.operatorsName,
            retrieveAETitle: Order.performedStationAET,
            referencedImages: [MPPSReferencedInstance(
                sopClassUID: Order.ctImageStorage,
                sopInstanceUID: Order.sopInstanceUID)])
    }

    /// The same step advanced to a terminal state. COMPLETED carries the
    /// acquired series; DISCONTINUED carries a reason and, here, nothing
    /// acquired — the abort-before-acquisition case.
    private func terminalStep(
        _ status: MPPSStatus,
        series: [MPPSPerformedSeries],
        reason: MPPSCodedEntry? = nil
    ) -> MPPSProcedureStep {
        MPPSProcedureStep(
            sopInstanceUID: Order.mppsSOPInstanceUID,
            status: status,
            studyInstanceUID: Order.studyInstanceUID,
            startDateTime: stepStart,
            endDateTime: stepEnd,
            protocolName: Order.protocolName,
            performedSeries: series,
            patientName: Order.patientName,
            patientID: Order.patientID,
            modality: Order.modality,
            procedureStepID: Order.performedStepID,
            procedureStepDescription: Order.scheduledStepDescription,
            performedStationAETitle: Order.performedStationAET,
            performingPhysicianName: Order.performingPhysician,
            accessionNumber: Order.accessionNumber,
            scheduledProcedureStepID: Order.scheduledStepID,
            requestedProcedureID: Order.requestedProcedureID,
            discontinuationReason: reason)
    }

    private func nCreateData() -> Data {
        DICOMMPPSService.buildMPPSAttributes(
            procedureStep: inProgressStep(), transferSyntax: explicitLE)
    }

    private func nSetData(_ step: MPPSProcedureStep) -> Data {
        DICOMMPPSService.buildNSetAttributes(
            procedureStep: step,
            includeScheduledStepAttributes: false,
            transferSyntax: explicitLE)
    }

    // MARK: - Stage 1: MWL item creation (PS3.3 C.4.10, PS3.4 Table K.6-1)

    func test_mwlCreate_carriesEveryRootLevelType1And2Attribute() {
        let json = worklistJSON()

        // Type 1 — must be present and non-empty.
        XCTAssertEqual(jsonValue(json, "00100010"), Order.patientName, "Patient's Name (0010,0010) Type 1")
        XCTAssertEqual(jsonValue(json, "00100020"), Order.patientID, "Patient ID (0010,0020) Type 1")
        XCTAssertEqual(jsonValue(json, "0020000D"), Order.studyInstanceUID, "Study Instance UID (0020,000D) Type 1")
        XCTAssertEqual(jsonValue(json, "00401001"), Order.requestedProcedureID, "Requested Procedure ID (0040,1001) Type 1")

        // Type 2 — must be present, may be empty.
        XCTAssertEqual(jsonValue(json, "00080050"), Order.accessionNumber, "Accession Number (0008,0050) Type 2")
        XCTAssertEqual(jsonValue(json, "00100030"), Order.patientBirthDate, "Patient's Birth Date (0010,0030) Type 2")
        XCTAssertEqual(jsonValue(json, "00100040"), Order.patientSex, "Patient's Sex (0010,0040) Type 2")
        XCTAssertEqual(jsonValue(json, "00080090"), Order.referringPhysician, "Referring Physician's Name (0008,0090) Type 2")
        XCTAssertEqual(jsonValue(json, "00321060"), Order.requestedProcedureDescription,
                       "Requested Procedure Description (0032,1060) Type 2")

        // Specific Character Set (0008,0005) — Type 1C, declared for the Latin-1 text.
        XCTAssertNotNil(jsonValue(json, "00080005"), "Specific Character Set (0008,0005)")
    }

    func test_mwlCreate_scheduledProcedureStepSequenceIsPresentWithOneItem() {
        let json = worklistJSON()
        guard let sq = json["00400100"] as? [String: Any] else {
            return XCTFail("Scheduled Procedure Step Sequence (0040,0100) is Type 1 and missing")
        }
        XCTAssertEqual(sq["vr"] as? String, "SQ")
        XCTAssertEqual((sq["Value"] as? [[String: Any]])?.count, 1,
                       "exactly the one scheduled step of this order")
    }

    func test_mwlCreate_scheduledStepItemCarriesEveryType1And2Attribute() {
        guard let sps = spsItem(worklistJSON()) else {
            return XCTFail("Scheduled Procedure Step Sequence (0040,0100) item missing")
        }

        // Type 1 inside the SPS item (PS3.3 C.4.10).
        XCTAssertEqual(jsonValue(sps, "00080060"), Order.modality, "Modality (0008,0060) Type 1")
        XCTAssertEqual(jsonValue(sps, "00400002"), Order.scheduledStartDate, "SPS Start Date (0040,0002) Type 1")
        XCTAssertEqual(jsonValue(sps, "00400009"), Order.scheduledStepID, "SPS ID (0040,0009) Type 1")

        // Type 2 inside the SPS item.
        XCTAssertEqual(jsonValue(sps, "00400001"), Order.scheduledStationAET,
                       "Scheduled Station AE Title (0040,0001) Type 2")
        XCTAssertEqual(jsonValue(sps, "00400003"), Order.scheduledStartTime, "SPS Start Time (0040,0003) Type 2")
        XCTAssertEqual(jsonValue(sps, "00400006"), Order.scheduledPerformingPhysician,
                       "Scheduled Performing Physician's Name (0040,0006) Type 2")
        XCTAssertEqual(jsonValue(sps, "00400007"), Order.scheduledStepDescription, "SPS Description (0040,0007) Type 2")
        XCTAssertEqual(jsonValue(sps, "00400010"), Order.scheduledStationName,
                       "Scheduled Station Name (0040,0010) Type 2")
    }

    func test_mwlCreate_newItemIsScheduled() {
        // A freshly created worklist item has not been started: PS3.3 C.4.10
        // Scheduled Procedure Step Status (0040,0020) is SCHEDULED, never
        // IN PROGRESS — the modality moves it on via MPPS, not via the order.
        XCTAssertEqual(jsonValue(spsItem(worklistJSON()) ?? [:], "00400020"), "SCHEDULED",
                       "Scheduled Procedure Step Status (0040,0020)")
    }

    func test_mwlCreate_declaresCorrectVRsForEveryAttribute() {
        let json = worklistJSON()
        XCTAssertEqual(jsonVR(json, "00100010"), "PN", "Patient's Name")
        XCTAssertEqual(jsonVR(json, "00100020"), "LO", "Patient ID")
        XCTAssertEqual(jsonVR(json, "00100030"), "DA", "Patient's Birth Date")
        XCTAssertEqual(jsonVR(json, "00100040"), "CS", "Patient's Sex")
        XCTAssertEqual(jsonVR(json, "00080050"), "SH", "Accession Number")
        XCTAssertEqual(jsonVR(json, "0020000D"), "UI", "Study Instance UID")
        XCTAssertEqual(jsonVR(json, "00401001"), "SH", "Requested Procedure ID")

        guard let sps = spsItem(json) else { return XCTFail("SPS item missing") }
        XCTAssertEqual(jsonVR(sps, "00080060"), "CS", "Modality")
        XCTAssertEqual(jsonVR(sps, "00400001"), "AE", "Scheduled Station AE Title")
        XCTAssertEqual(jsonVR(sps, "00400002"), "DA", "SPS Start Date")
        XCTAssertEqual(jsonVR(sps, "00400003"), "TM", "SPS Start Time")
        XCTAssertEqual(jsonVR(sps, "00400009"), "SH", "SPS ID")
    }

    // MARK: - Stage 2: MPPS N-CREATE, IN PROGRESS (PS3.4 Table F.7.2-1, F.7.2.1.2)

    func test_nCreate_statusIsInProgressAndNoEndDateTimeIsValued() {
        let data = nCreateData()

        // PS3.4 F.7.2.1.2 — a step is created running.
        XCTAssertEqual(value(data, 0x0040, 0x0252), "IN PROGRESS", "PPS Status (0040,0252) Type 1")

        // End Date/Time (0040,0250)/(0040,0251) are Type 2 here: present in the
        // data set but with a zero-length value until the step terminates.
        XCTAssertTrue(contains(data, 0x0040, 0x0250), "PPS End Date (0040,0250) Type 2 must be present")
        XCTAssertTrue(contains(data, 0x0040, 0x0251), "PPS End Time (0040,0251) Type 2 must be present")
        XCTAssertEqual(value(data, 0x0040, 0x0250), "", "PPS End Date must be zero-length while IN PROGRESS")
        XCTAssertEqual(value(data, 0x0040, 0x0251), "", "PPS End Time must be zero-length while IN PROGRESS")
    }

    func test_nCreate_carriesEveryType1AttributeWithAValue() {
        let data = nCreateData()
        XCTAssertEqual(value(data, 0x0040, 0x0241), Order.performedStationAET,
                       "Performed Station AE Title (0040,0241) Type 1")
        XCTAssertEqual(value(data, 0x0040, 0x0253), Order.performedStepID, "PPS ID (0040,0253) Type 1")
        XCTAssertEqual(value(data, 0x0008, 0x0060), Order.modality, "Modality (0008,0060) Type 1")
        XCTAssertEqual(value(data, 0x0040, 0x0244), expectedDA(stepStart), "PPS Start Date (0040,0244) Type 1")
        XCTAssertNotEqual(value(data, 0x0040, 0x0245) ?? "", "", "PPS Start Time (0040,0245) Type 1")
        XCTAssertTrue(contains(data, 0x0040, 0x0270),
                      "Scheduled Step Attributes Sequence (0040,0270) Type 1")
    }

    func test_nCreate_carriesEveryType2AttributeOfTheRelationshipModule() {
        let data = nCreateData()
        XCTAssertEqual(value(data, 0x0010, 0x0010), Order.patientName, "Patient's Name (0010,0010) Type 2")
        XCTAssertEqual(value(data, 0x0010, 0x0020), Order.patientID, "Patient ID (0010,0020) Type 2")
        XCTAssertEqual(value(data, 0x0010, 0x0030), Order.patientBirthDate,
                       "Patient's Birth Date (0010,0030) Type 2")
        XCTAssertEqual(value(data, 0x0010, 0x0040), Order.patientSex, "Patient's Sex (0010,0040) Type 2")
        XCTAssertTrue(contains(data, 0x0008, 0x1120), "Referenced Patient Sequence (0008,1120) Type 2")
    }

    func test_nCreate_carriesEveryType2AttributeOfTheInformationAndResultsModules() {
        let data = nCreateData()
        XCTAssertEqual(value(data, 0x0040, 0x0242), Order.performedStationName,
                       "Performed Station Name (0040,0242) Type 2")
        XCTAssertTrue(contains(data, 0x0040, 0x0243), "Performed Location (0040,0243) Type 2")
        XCTAssertEqual(value(data, 0x0040, 0x0254), Order.scheduledStepDescription,
                       "PPS Description (0040,0254) Type 2")
        XCTAssertTrue(contains(data, 0x0040, 0x0255),
                      "Performed Procedure Type Description (0040,0255) Type 2")
        XCTAssertTrue(contains(data, 0x0008, 0x1032), "Procedure Code Sequence (0008,1032) Type 2")
        XCTAssertEqual(value(data, 0x0020, 0x0010), Order.studyID, "Study ID (0020,0010) Type 2")
        XCTAssertTrue(contains(data, 0x0040, 0x0260), "Performed Protocol Code Sequence (0040,0260) Type 2")
        XCTAssertTrue(contains(data, 0x0040, 0x0340),
                      "Performed Series Sequence (0040,0340) Type 2, empty at N-CREATE")
    }

    func test_nCreate_doesNotCarryAStatusTheStateMachineForbids() throws {
        // PS3.4 F.7.2.1.2 — N-CREATE may only create an IN PROGRESS step, and
        // must not carry an End Date/Time. Both are rejected before the wire.
        for status in [MPPSStatus.completed, .discontinued] {
            let step = terminalStep(status, series: [acquiredSeries()])
            XCTAssertThrowsError(try DICOMMPPSService.validate(step, for: .nCreate),
                                 "N-CREATE with \(status.rawValue) violates F.7.2.1.2")
        }
        XCTAssertNoThrow(try DICOMMPPSService.validate(inProgressStep(), for: .nCreate))
    }

    // MARK: - Stage 3a: MPPS N-SET, COMPLETED (PS3.4 Table F.7.2-1, F.7.2.1.3)

    func test_nSetCompleted_carriesTerminalStatusAndType1EndDateTime() {
        let data = nSetData(terminalStep(.completed, series: [acquiredSeries()]))

        XCTAssertEqual(value(data, 0x0040, 0x0252), "COMPLETED", "PPS Status (0040,0252)")

        // Type 1 once the step terminates: present *and* non-empty.
        XCTAssertEqual(value(data, 0x0040, 0x0250), expectedDA(stepEnd), "PPS End Date (0040,0250) Type 1")
        XCTAssertNotEqual(value(data, 0x0040, 0x0251) ?? "", "", "PPS End Time (0040,0251) Type 1")
    }

    func test_nSetCompleted_carriesPerformedSeriesWithEveryNestedAttribute() {
        let data = nSetData(terminalStep(.completed, series: [acquiredSeries()]))

        XCTAssertTrue(contains(data, 0x0040, 0x0340),
                      "Performed Series Sequence (0040,0340) Type 1 once COMPLETED")

        // Type 1 inside each Performed Series item.
        XCTAssertEqual(value(data, 0x0020, 0x000E), Order.seriesInstanceUID,
                       "Series Instance UID (0020,000E) Type 1")
        XCTAssertEqual(value(data, 0x0018, 0x1030), Order.protocolName, "Protocol Name (0018,1030) Type 1")

        // Type 2 inside each item.
        XCTAssertEqual(value(data, 0x0008, 0x0054), Order.performedStationAET,
                       "Retrieve AE Title (0008,0054) Type 2")
        XCTAssertEqual(value(data, 0x0008, 0x1050), Order.performingPhysician,
                       "Performing Physician's Name (0008,1050) Type 2")
        XCTAssertEqual(value(data, 0x0008, 0x1070), Order.operatorsName, "Operators' Name (0008,1070) Type 2")
        XCTAssertEqual(value(data, 0x0008, 0x103E), "CHEST HELICAL", "Series Description (0008,103E) Type 2")
        XCTAssertTrue(contains(data, 0x0008, 0x1140), "Referenced Image Sequence (0008,1140) Type 2")
        XCTAssertTrue(contains(data, 0x0040, 0x0220),
                      "Referenced Non-Image Composite SOP Instance Sequence (0040,0220) Type 2")
    }

    func test_nSetCompleted_referencesTheAcquiredInstanceByItsRealSOPClass() {
        let data = nSetData(terminalStep(.completed, series: [acquiredSeries()]))

        // The Referenced Image Sequence item must name the instance's actual
        // SOP Class, not a Secondary Capture placeholder.
        XCTAssertEqual(value(data, 0x0008, 0x1150), Order.ctImageStorage,
                       "Referenced SOP Class UID (0008,1150) — CT Image Storage")
        XCTAssertEqual(value(data, 0x0008, 0x1155), Order.sopInstanceUID,
                       "Referenced SOP Instance UID (0008,1155)")
    }

    func test_nSetCompleted_omitsAttributesTheNSetColumnDoesNotAllow() {
        let data = nSetData(terminalStep(.completed, series: [acquiredSeries()]))

        // PS3.4 Table F.7.2-1 marks these "Not allowed" in N-SET: they were
        // fixed at N-CREATE and an SCP may reject the message over them.
        XCTAssertFalse(contains(data, 0x0040, 0x0270),
                       "Scheduled Step Attributes Sequence (0040,0270) is Not allowed in N-SET")
        XCTAssertFalse(contains(data, 0x0010, 0x0010), "Patient's Name is Not allowed in N-SET")
        XCTAssertFalse(contains(data, 0x0010, 0x0020), "Patient ID is Not allowed in N-SET")
        XCTAssertFalse(contains(data, 0x0008, 0x0060), "Modality is Not allowed in N-SET")
        XCTAssertFalse(contains(data, 0x0040, 0x0244), "PPS Start Date is Not allowed in N-SET")
        XCTAssertFalse(contains(data, 0x0040, 0x0241),
                       "Performed Station AE Title is Not allowed in N-SET")
    }

    func test_nSetCompleted_carriesNoDiscontinuationReason() {
        // (0040,0281) is meaningful only for DISCONTINUED (PS3.3 C.4.15).
        let step = terminalStep(.completed, series: [acquiredSeries()],
                                reason: MPPSCodedEntry(codeValue: "110513",
                                                       codingSchemeDesignator: "DCM",
                                                       codeMeaning: "Doctor cancelled procedure"))
        XCTAssertFalse(contains(nSetData(step), 0x0040, 0x0281),
                       "Discontinuation Reason Code Sequence must not accompany COMPLETED")
    }

    func test_nSetCompleted_withoutAnyAcquiredSeriesIsRejected() {
        // Table F.7.2-1 — Performed Series Sequence is Type 1 in the COMPLETED
        // state, so a step that acquired nothing must be DISCONTINUED instead.
        XCTAssertThrowsError(
            try DICOMMPPSService.validate(terminalStep(.completed, series: []), for: .nSet))
        XCTAssertNoThrow(
            try DICOMMPPSService.validate(terminalStep(.completed, series: [acquiredSeries()]), for: .nSet))
    }

    // MARK: - Stage 3b: MPPS N-SET, DISCONTINUED (PS3.4 Table F.7.2-1, F.7.2.1.3)

    private func discontinuationReason() -> MPPSCodedEntry {
        // CID 9301 Modality PPS Discontinuation Reasons.
        MPPSCodedEntry(codeValue: "110513", codingSchemeDesignator: "DCM",
                       codeMeaning: "Doctor cancelled procedure")
    }

    func test_nSetDiscontinued_carriesTerminalStatusAndType1EndDateTime() {
        let data = nSetData(terminalStep(.discontinued, series: [], reason: discontinuationReason()))

        XCTAssertEqual(value(data, 0x0040, 0x0252), "DISCONTINUED", "PPS Status (0040,0252)")
        XCTAssertEqual(value(data, 0x0040, 0x0250), expectedDA(stepEnd), "PPS End Date (0040,0250) Type 1")
        XCTAssertNotEqual(value(data, 0x0040, 0x0251) ?? "", "", "PPS End Time (0040,0251) Type 1")
    }

    func test_nSetDiscontinued_carriesTheReasonCodeSequenceWithACompleteCodeItem() {
        let data = nSetData(terminalStep(.discontinued, series: [], reason: discontinuationReason()))

        XCTAssertTrue(contains(data, 0x0040, 0x0281),
                      "PPS Discontinuation Reason Code Sequence (0040,0281)")

        // Code Sequence Macro (PS3.3 8.8) — all three are Type 1 in the item.
        XCTAssertEqual(value(data, 0x0008, 0x0100), "110513", "Code Value (0008,0100)")
        XCTAssertEqual(value(data, 0x0008, 0x0102), "DCM", "Coding Scheme Designator (0008,0102)")
        XCTAssertEqual(value(data, 0x0008, 0x0104), "Doctor cancelled procedure", "Code Meaning (0008,0104)")
    }

    func test_nSetDiscontinued_isAllowedWithNothingAcquired() {
        // A step aborted before any image was produced is the reason
        // DISCONTINUED exists: no Performed Series item is required.
        XCTAssertNoThrow(try DICOMMPPSService.validate(
            terminalStep(.discontinued, series: [], reason: discontinuationReason()), for: .nSet))

        // The sequence is still sent, as a zero-item sequence.
        XCTAssertTrue(contains(nSetData(terminalStep(.discontinued, series: [],
                                                     reason: discontinuationReason())), 0x0040, 0x0340),
                      "Performed Series Sequence (0040,0340) present, empty")
    }

    func test_nSetDiscontinued_afterPartialAcquisitionKeepsTheSeriesAlreadyStored() {
        // A step aborted mid-acquisition must still report what reached the
        // archive, so the PACS does not orphan the stored instances.
        let data = nSetData(terminalStep(.discontinued, series: [acquiredSeries()],
                                         reason: discontinuationReason()))
        XCTAssertEqual(value(data, 0x0020, 0x000E), Order.seriesInstanceUID,
                       "Series Instance UID of the partially acquired series")
        XCTAssertEqual(value(data, 0x0008, 0x1155), Order.sopInstanceUID,
                       "the instance that was stored before the abort")
        XCTAssertEqual(value(data, 0x0040, 0x0252), "DISCONTINUED")
    }

    func test_nSetDiscontinued_omitsAttributesTheNSetColumnDoesNotAllow() {
        let data = nSetData(terminalStep(.discontinued, series: [], reason: discontinuationReason()))
        XCTAssertFalse(contains(data, 0x0040, 0x0270),
                       "Scheduled Step Attributes Sequence (0040,0270) is Not allowed in N-SET")
        XCTAssertFalse(contains(data, 0x0008, 0x0060), "Modality is Not allowed in N-SET")
        XCTAssertFalse(contains(data, 0x0040, 0x0244), "PPS Start Date is Not allowed in N-SET")
    }

    // MARK: - State machine across the whole workflow (PS3.4 F.7.2.1.2 / F.7.2.1.3)

    func test_workflow_onlyTheTwoTerminalTransitionsAreAccepted() {
        let completed = terminalStep(.completed, series: [acquiredSeries()])
        let discontinued = terminalStep(.discontinued, series: [], reason: discontinuationReason())

        // IN PROGRESS → COMPLETED and IN PROGRESS → DISCONTINUED are the only
        // transitions; N-SET may never return a step to IN PROGRESS.
        XCTAssertNoThrow(try DICOMMPPSService.validate(completed, for: .nSet))
        XCTAssertNoThrow(try DICOMMPPSService.validate(discontinued, for: .nSet))
        XCTAssertThrowsError(try DICOMMPPSService.validate(inProgressStep(), for: .nSet),
                             "N-SET to IN PROGRESS violates F.7.2.1.3")
    }

    func test_workflow_terminalStateWithoutAnEndDateTimeIsRejected() {
        for status in [MPPSStatus.completed, .discontinued] {
            let step = MPPSProcedureStep(
                sopInstanceUID: Order.mppsSOPInstanceUID,
                status: status,
                studyInstanceUID: Order.studyInstanceUID,
                endDateTime: nil,
                performedSeries: [acquiredSeries()])
            XCTAssertThrowsError(try DICOMMPPSService.validate(step, for: .nSet),
                                 "\(status.rawValue) without End Date/Time violates Table F.7.2-1 Type 1")
        }
    }

    // MARK: - Continuity: the order's identifiers must survive into the MPPS
    //
    // These are what make the workflow a workflow rather than three unrelated
    // messages. The PACS binds the performed step back to the order through
    // the Scheduled Step Attributes Sequence (0040,0270).

    func test_continuity_nCreateScheduledStepAttributesCarryTheWorklistIdentifiers() {
        let json = worklistJSON()
        let sps = spsItem(json) ?? [:]
        let data = nCreateData()

        XCTAssertEqual(value(data, 0x0020, 0x000D), jsonValue(json, "0020000D"),
                       "Study Instance UID (0020,000D) Type 1 — the binding key")
        XCTAssertEqual(value(data, 0x0008, 0x0050), jsonValue(json, "00080050"),
                       "Accession Number (0008,0050) Type 2 carried from the order")
        XCTAssertEqual(value(data, 0x0040, 0x1001), jsonValue(json, "00401001"),
                       "Requested Procedure ID (0040,1001) Type 2 carried from the order")
        XCTAssertEqual(value(data, 0x0040, 0x0009), jsonValue(sps, "00400009"),
                       "SPS ID (0040,0009) Type 2 carried from the scheduled step")
        XCTAssertEqual(value(data, 0x0040, 0x0007), jsonValue(sps, "00400007"),
                       "SPS Description (0040,0007) Type 2 carried from the scheduled step")
        XCTAssertEqual(value(data, 0x0032, 0x1060), jsonValue(json, "00321060"),
                       "Requested Procedure Description (0032,1060) Type 2 carried from the order")
    }

    func test_continuity_performedStepMatchesTheScheduledDemographicsAndModality() {
        let json = worklistJSON()
        let data = nCreateData()

        // The modality must not silently re-type the patient or the procedure.
        XCTAssertEqual(value(data, 0x0010, 0x0010), jsonValue(json, "00100010"), "Patient's Name")
        XCTAssertEqual(value(data, 0x0010, 0x0020), jsonValue(json, "00100020"), "Patient ID")
        XCTAssertEqual(value(data, 0x0010, 0x0030), jsonValue(json, "00100030"), "Patient's Birth Date")
        XCTAssertEqual(value(data, 0x0010, 0x0040), jsonValue(json, "00100040"), "Patient's Sex")
        XCTAssertEqual(value(data, 0x0008, 0x0060), jsonValue(spsItem(json) ?? [:], "00080060"),
                       "Modality performed must equal the modality scheduled")
    }

    func test_continuity_nCreateAndNSetAddressTheSameProcedureStepInstance() {
        // Both messages act on one SOP Instance: the N-CREATE assigns the UID,
        // the N-SET names it in the command set rather than the data set.
        let created = inProgressStep()
        for terminal in [terminalStep(.completed, series: [acquiredSeries()]),
                         terminalStep(.discontinued, series: [], reason: discontinuationReason())] {
            XCTAssertEqual(terminal.sopInstanceUID, created.sopInstanceUID,
                           "the terminal N-SET must target the created MPPS instance")
            XCTAssertEqual(terminal.studyInstanceUID, created.studyInstanceUID,
                           "and stay bound to the same study")
        }
    }

    func test_continuity_theStudyInstanceUIDIsNeverRegeneratedAcrossStages() {
        // One UID from order to archive: a regenerated Study Instance UID
        // splits the study and is the classic cause of an orphaned MPPS.
        let json = worklistJSON()
        XCTAssertEqual(jsonValue(json, "0020000D"), Order.studyInstanceUID)
        XCTAssertEqual(value(nCreateData(), 0x0020, 0x000D), Order.studyInstanceUID)
        XCTAssertEqual(inProgressStep().studyInstanceUID, Order.studyInstanceUID)
        XCTAssertEqual(terminalStep(.completed, series: [acquiredSeries()]).studyInstanceUID,
                       Order.studyInstanceUID)
    }
}
