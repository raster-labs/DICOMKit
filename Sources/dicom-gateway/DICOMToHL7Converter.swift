// NEMA-verified: 2026a, checked 2026-10-01 — DICOM side only: Patient's Name is read per PS3.5 2026a 6.2.1 (first component group, prefix/suffix order) via DICOMValueMapping; the HL7 v2 segments, fields and trigger events are not NEMA (plumbing; ADT^AA01 double prefix fixed)
import Foundation
import DICOMKit
import DICOMCore

// MARK: - DICOM to HL7 Converter

class DICOMToHL7Converter {
    private let config: MappingConfiguration
    
    init(config: MappingConfiguration = MappingConfiguration()) {
        self.config = config
    }
    
    // MARK: - Convert to ADT (Admission/Discharge/Transfer)
    
    func convertToADT(dicomFile: DICOMFile, eventType: String = "A01") throws -> HL7Message {
        let builder = HL7MessageBuilder()
        // `--event-type` takes the trigger event as documented ("A01"); a bare "01" is also
        // accepted. The former code prefixed another "A" and sent "ADT^AA01".
        let event = Self.adtTriggerEvent(eventType)
        
        // MSH - Message Header
        _  = builder.addMSH(
            sendingApplication: "DICOMKit",
            sendingFacility: "IMAGING",
            receivingApplication: "HIS",
            receivingFacility: "HOSPITAL",
            messageType: "ADT^\(event)",
            messageControlId: UUID().uuidString.prefix(20).uppercased()
        )
        
        // EVN - Event Type
        let eventTimestamp = formatHL7Timestamp(Date())
        _  = builder.addSegment(id: "EVN", fields: [
            event,
            eventTimestamp
        ])
        
        // PID - Patient Identification
        let patientID = extractString(from: dicomFile, tag: .patientID) ?? "UNKNOWN"
        let patientName = extractString(from: dicomFile, tag: .patientName) ?? "UNKNOWN^UNKNOWN"
        let dateOfBirth = extractDate(from: dicomFile, tag: .patientBirthDate)
        let sex = extractString(from: dicomFile, tag: .patientSex) ?? "U"
        
        _  = builder.addSegment(id: "PID", fields: [
            "",  // Set ID
            patientID,  // Patient ID (External)
            patientID,  // Patient ID (Internal)
            "",  // Alternate Patient ID
            formatHL7Name(patientName),  // Patient Name
            "",  // Mother's Maiden Name
            dateOfBirth ?? "",  // Date of Birth
            sex,  // Sex
            "",  // Patient Alias
            "",  // Race
            "",  // Patient Address
            ""   // County Code
        ])
        
        // PV1 - Patient Visit
        let accessionNumber = extractString(from: dicomFile, tag: .accessionNumber) ?? ""
        
        _  = builder.addSegment(id: "PV1", fields: [
            "",  // Set ID
            "O",  // Patient Class (Outpatient)
            "",  // Assigned Patient Location
            "",  // Admission Type
            "",  // Preadmit Number
            "",  // Prior Patient Location
            "",  // Attending Doctor
            "",  // Referring Doctor
            "",  // Consulting Doctor
            "",  // Hospital Service
            "",  // Temporary Location
            "",  // Preadmit Test Indicator
            "",  // Re-admission Indicator
            "",  // Admit Source
            "",  // Ambulatory Status
            "",  // VIP Indicator
            "",  // Admitting Doctor
            "",  // Patient Type
            accessionNumber,  // Visit Number
            ""   // Financial Class
        ])
        
        return try builder.build(messageType: .ADT)
    }
    
    // MARK: - Convert to ORM (Order Message)
    
    func convertToORM(dicomFile: DICOMFile) throws -> HL7Message {
        let builder = HL7MessageBuilder()
        
        // MSH - Message Header
        _  = builder.addMSH(
            sendingApplication: "DICOMKit",
            sendingFacility: "IMAGING",
            receivingApplication: "RIS",
            receivingFacility: "HOSPITAL",
            messageType: "ORM^O01",
            messageControlId: UUID().uuidString.prefix(20).uppercased()
        )
        
        // PID - Patient Identification (reuse from ADT)
        let patientID = extractString(from: dicomFile, tag: .patientID) ?? "UNKNOWN"
        let patientName = extractString(from: dicomFile, tag: .patientName) ?? "UNKNOWN^UNKNOWN"
        let dateOfBirth = extractDate(from: dicomFile, tag: .patientBirthDate)
        let sex = extractString(from: dicomFile, tag: .patientSex) ?? "U"
        
        _  = builder.addSegment(id: "PID", fields: [
            "",
            patientID,
            patientID,
            "",
            formatHL7Name(patientName),
            "",
            dateOfBirth ?? "",
            sex
        ])
        
        // ORC - Common Order
        let accessionNumber = extractString(from: dicomFile, tag: .accessionNumber) ?? ""
        let studyInstanceUID = extractString(from: dicomFile, tag: .studyInstanceUID) ?? ""
        
        _  = builder.addSegment(id: "ORC", fields: [
            "NW",  // Order Control (New)
            accessionNumber,  // Placer Order Number
            studyInstanceUID,  // Filler Order Number
            "",  // Placer Group Number
            "",  // Order Status
            "",  // Response Flag
            "",  // Quantity/Timing
            "",  // Parent
            formatHL7Timestamp(Date()),  // Date/Time of Transaction
            "",  // Entered By
            ""   // Verified By
        ])
        
        // OBR - Observation Request
        let studyDescription = extractString(from: dicomFile, tag: .studyDescription) ?? "Imaging Study"
        let modality = extractString(from: dicomFile, tag: .modality) ?? "OT"
        let studyDate = extractDate(from: dicomFile, tag: .studyDate)
        let studyTime = extractTime(from: dicomFile, tag: .studyTime)
        let studyDateTime = combineDateTime(date: studyDate, time: studyTime)
        
        _  = builder.addSegment(id: "OBR", fields: [
            "",  // Set ID
            accessionNumber,  // Placer Order Number
            studyInstanceUID,  // Filler Order Number
            "\(modality)^" + studyDescription,  // Universal Service ID
            "",  // Priority
            studyDateTime ?? "",  // Requested Date/Time
            studyDateTime ?? "",  // Observation Date/Time
            "",  // Observation End Date/Time
            "",  // Collection Volume
            "",  // Collector Identifier
            "",  // Specimen Action Code
            "",  // Danger Code
            "",  // Relevant Clinical Info
            studyDateTime ?? "",  // Specimen Received Date/Time
            "",  // Specimen Source
            ""   // Ordering Provider
        ])
        
        return try builder.build(messageType: .ORM)
    }
    
    // MARK: - Convert to ORU (Observation Result)
    
    func convertToORU(dicomFile: DICOMFile) throws -> HL7Message {
        let builder = HL7MessageBuilder()
        
        // MSH - Message Header
        _  = builder.addMSH(
            sendingApplication: "DICOMKit",
            sendingFacility: "IMAGING",
            receivingApplication: "LIS",
            receivingFacility: "HOSPITAL",
            messageType: "ORU^R01",
            messageControlId: UUID().uuidString.prefix(20).uppercased()
        )
        
        // PID - Patient Identification
        let patientID = extractString(from: dicomFile, tag: .patientID) ?? "UNKNOWN"
        let patientName = extractString(from: dicomFile, tag: .patientName) ?? "UNKNOWN^UNKNOWN"
        let dateOfBirth = extractDate(from: dicomFile, tag: .patientBirthDate)
        let sex = extractString(from: dicomFile, tag: .patientSex) ?? "U"
        
        _  = builder.addSegment(id: "PID", fields: [
            "",
            patientID,
            patientID,
            "",
            formatHL7Name(patientName),
            "",
            dateOfBirth ?? "",
            sex
        ])
        
        // OBR - Observation Request
        let accessionNumber = extractString(from: dicomFile, tag: .accessionNumber) ?? ""
        let studyInstanceUID = extractString(from: dicomFile, tag: .studyInstanceUID) ?? ""
        let studyDescription = extractString(from: dicomFile, tag: .studyDescription) ?? "Imaging Study"
        let modality = extractString(from: dicomFile, tag: .modality) ?? "OT"
        let studyDate = extractDate(from: dicomFile, tag: .studyDate)
        let studyTime = extractTime(from: dicomFile, tag: .studyTime)
        let studyDateTime = combineDateTime(date: studyDate, time: studyTime)
        
        _  = builder.addSegment(id: "OBR", fields: [
            "",
            accessionNumber,
            studyInstanceUID,
            "\(modality)^" + studyDescription,
            "",
            studyDateTime ?? "",
            studyDateTime ?? "",
            "",
            "",
            "",
            "",
            "",
            "",
            studyDateTime ?? "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "F"  // Result Status (Final)
        ])
        
        // OBX - Observation Result (Image Count)
        let numberOfImages = extractString(from: dicomFile, tag: .numberOfSeriesRelatedInstances) ?? "0"
        
        _ = _  = builder.addSegment(id: "OBX", fields: [
            "1",  // Set ID
            "NM",  // Value Type (Numeric)
            "IMG_COUNT",  // Observation Identifier
            "",  // Observation Sub-ID
            numberOfImages,  // Observation Value
            "images",  // Units
            "",  // References Range
            "",  // Abnormal Flags
            "",  // Probability
            "",  // Nature of Abnormal Test
            "F",  // Observation Result Status (Final)
            ""   // Date Last Obs Normal Value
        ])
        
        return try builder.build(messageType: .ORU)
    }
    
    // MARK: - Helper Methods
    
    private func extractString(from file: DICOMFile, tag: Tag) -> String? {
        return file.dataSet.string(for: tag)
    }
    
    private func extractDate(from file: DICOMFile, tag: Tag) -> String? {
        guard let dateStr = extractString(from: file, tag: tag) else { return nil }
        // Convert DICOM date (YYYYMMDD) to HL7 date (YYYYMMDD)
        return dateStr
    }
    
    private func extractTime(from file: DICOMFile, tag: Tag) -> String? {
        guard let timeStr = extractString(from: file, tag: tag) else { return nil }
        // Convert DICOM time (HHMMSS.FFFFFF) to HL7 time (HHMMSS)
        let components = timeStr.split(separator: ".")
        return String(components.first ?? "")
    }
    
    private func combineDateTime(date: String?, time: String?) -> String? {
        guard let date = date else { return nil }
        if let time = time {
            return date + time
        }
        return date
    }
    
    /// DICOM PN to HL7 XPN: first component group only, prefix and suffix swapped
    /// (PS3.5 6.2.1 orders prefix before suffix; XPN has suffix at 4, prefix at 5).
    private func formatHL7Name(_ dicomName: String) -> String {
        DICOMValueMapping.hl7XPN(fromDICOM: dicomName)
    }
    
    /// ADT trigger event code: "A01" stays "A01"; "01" becomes "A01".
    static func adtTriggerEvent(_ eventType: String) -> String {
        let e = eventType.trimmingCharacters(in: .whitespaces).uppercased()
        return e.hasPrefix("A") ? e : "A" + e
    }
    
    private func formatHL7Timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }
}

