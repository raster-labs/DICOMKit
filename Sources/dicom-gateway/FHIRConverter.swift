// NEMA-verified: 2026a, checked 2026-10-01 — DICOM side only: PN, DA, TM, Patient's Sex (M/F/O, PS3.3 2026a Table C.7-1) and UID checks via DICOMValueMapping; the ImagingStudy.modality system URI equals the FHIR column for DCM in PS3.16 2026a Table 8-1; Modality values are DICOMCore.Modality (PS3.3 C.7.3.1.1.1); the 3 Tag literals match PS3.6 Table 6-1; FHIR resources themselves are not NEMA (plumbing)
import Foundation
import DICOMKit
import DICOMCore

// MARK: - FHIR Resource Type

enum FHIRResourceType: String, CaseIterable {
    case imagingStudy = "ImagingStudy"
    case patient = "Patient"
    case practitioner = "Practitioner"
    case diagnosticReport = "DiagnosticReport"
}

// MARK: - FHIR JSON Converter

class FHIRConverter {
    private let config: MappingConfiguration
    
    init(config: MappingConfiguration = MappingConfiguration()) {
        self.config = config
    }
    
    // MARK: - DICOM to FHIR
    
    func convertToFHIR(dicomFile: DICOMFile, resourceType: FHIRResourceType) throws -> [String: Any] {
        switch resourceType {
        case .imagingStudy:
            return try convertToImagingStudy(dicomFile: dicomFile)
        case .patient:
            return try convertToPatient(dicomFile: dicomFile)
        case .practitioner:
            return try convertToPractitioner(dicomFile: dicomFile)
        case .diagnosticReport:
            return try convertToDiagnosticReport(dicomFile: dicomFile)
        }
    }
    
    private func convertToImagingStudy(dicomFile: DICOMFile) throws -> [String: Any] {
        var resource: [String: Any] = [
            "resourceType": "ImagingStudy",
            "status": "available"
        ]
        
        // Study Instance UID
        if let studyUID = extractString(from: dicomFile, tag: .studyInstanceUID) {
            resource["identifier"] = [
                [
                    "system": "urn:dicom:uid",
                    "value": "urn:oid:\(studyUID)"
                ]
            ]
        }
        
        // Study Date/Time
        if let studyDate = extractString(from: dicomFile, tag: .studyDate),
           let studyTime = extractString(from: dicomFile, tag: .studyTime) {
            resource["started"] = formatFHIRDateTime(date: studyDate, time: studyTime)
        }
        
        // Modality
        if let modality = extractString(from: dicomFile, tag: .modality) {
            resource["modality"] = [
                [
                    "system": "http://dicom.nema.org/resources/ontology/DCM",
                    "code": modality
                ]
            ]
        }
        
        // Study Description
        if let description = extractString(from: dicomFile, tag: .studyDescription) {
            resource["description"] = description
        }
        
        // Number of Series
        if let numberOfSeries = extractString(from: dicomFile, tag: .numberOfStudyRelatedSeries) {
            resource["numberOfSeries"] = Int(numberOfSeries) ?? 0
        }
        
        // Number of Instances
        if let numberOfInstances = extractString(from: dicomFile, tag: .numberOfStudyRelatedInstances) {
            resource["numberOfInstances"] = Int(numberOfInstances) ?? 0
        }
        
        // Patient reference
        if let patientID = extractString(from: dicomFile, tag: .patientID) {
            resource["subject"] = [
                "reference": "Patient/\(patientID)"
            ]
        }
        
        return resource
    }
    
    private func convertToPatient(dicomFile: DICOMFile) throws -> [String: Any] {
        var resource: [String: Any] = [
            "resourceType": "Patient"
        ]
        
        // Patient ID
        if let patientID = extractString(from: dicomFile, tag: .patientID) {
            resource["id"] = patientID
            resource["identifier"] = [
                [
                    "system": "urn:oid:2.16.840.1.113883.19.5",
                    "value": patientID
                ]
            ]
        }
        
        // Patient Name
        if let patientName = extractString(from: dicomFile, tag: .patientName) {
            resource["name"] = [fhirHumanName(fromDICOM: patientName)]
        }
        
        // Birth Date
        if let birthDate = extractString(from: dicomFile, tag: .patientBirthDate) {
            resource["birthDate"] = formatFHIRDate(birthDate)
        }
        
        // Gender
        if let sex = extractString(from: dicomFile, tag: .patientSex) {
            resource["gender"] = mapDICOMSexToFHIR(sex)
        }
        
        return resource
    }
    
    private func convertToPractitioner(dicomFile: DICOMFile) throws -> [String: Any] {
        var resource: [String: Any] = [
            "resourceType": "Practitioner"
        ]
        
        // Referring Physician
        if let referringPhysician = extractString(from: dicomFile, tag: .referringPhysicianName) {
            resource["name"] = [fhirHumanName(fromDICOM: referringPhysician)]
        }
        
        return resource
    }
    
    private func convertToDiagnosticReport(dicomFile: DICOMFile) throws -> [String: Any] {
        var resource: [String: Any] = [
            "resourceType": "DiagnosticReport",
            "status": "final"
        ]
        
        // Study Description -> Code
        if let studyDescription = extractString(from: dicomFile, tag: .studyDescription) {
            resource["code"] = [
                "text": studyDescription
            ]
        }
        
        // Effective DateTime
        if let studyDate = extractString(from: dicomFile, tag: .studyDate),
           let studyTime = extractString(from: dicomFile, tag: .studyTime) {
            resource["effectiveDateTime"] = formatFHIRDateTime(date: studyDate, time: studyTime)
        }
        
        // Patient reference
        if let patientID = extractString(from: dicomFile, tag: .patientID) {
            resource["subject"] = [
                "reference": "Patient/\(patientID)"
            ]
        }
        
        return resource
    }
    
    // MARK: - FHIR to DICOM
    
    func convertFromFHIR(fhirResource: [String: Any], templateFile: DICOMFile? = nil) throws -> DICOMFile {
        guard let resourceType = fhirResource["resourceType"] as? String else {
            throw GatewayError.parsingFailed("Missing resourceType in FHIR resource")
        }
        
        var dicomFile: DICOMFile
        if let template = templateFile {
            dicomFile = template
        } else {
            dicomFile = try createBasicDICOMFile()
        }
        
        switch resourceType {
        case "ImagingStudy":
            try populateFromImagingStudy(dicomFile: &dicomFile, fhir: fhirResource)
        case "Patient":
            try populateFromPatient(dicomFile: &dicomFile, fhir: fhirResource)
        default:
            throw GatewayError.notImplemented("FHIR resource type '\(resourceType)' not yet supported")
        }
        
        return dicomFile
    }
    
    private func populateFromImagingStudy(dicomFile: inout DICOMFile, fhir: [String: Any]) throws {
        // Extract Study Instance UID from identifier
        if let identifiers = fhir["identifier"] as? [[String: Any]],
           let firstIdentifier = identifiers.first,
           let value = firstIdentifier["value"] as? String {
            // Remove "urn:oid:" prefix if present; used only when it is a UID (PS3.5 9.1)
            let uid = value.replacingOccurrences(of: "urn:oid:", with: "")
            if DICOMValueMapping.isValidUID(uid) {
                try setElement(&dicomFile, tag: .studyInstanceUID, value: uid, vr: .UI)
            }
        }
        
        // Study Date/Time
        if let started = fhir["started"] as? String {
            if let date = DICOMValueMapping.date(fromFHIR: started) {
                try setElement(&dicomFile, tag: .studyDate, value: date, vr: .DA)
            }
            if let time = DICOMValueMapping.time(fromFHIR: started) {
                try setElement(&dicomFile, tag: .studyTime, value: time, vr: .TM)
            }
        }
        
        // Study Description
        if let description = fhir["description"] as? String {
            try setElement(&dicomFile, tag: .studyDescription, value: description, vr: .LO)
        }
        
        // Modality
        if let modalities = fhir["modality"] as? [[String: Any]],
           let firstModality = modalities.first,
           let code = firstModality["code"] as? String {
            // Same normalization as the HL7 path: FHIR is an external source,
            // so resolve aliases and canonicalize to CS form, keeping an
            // unrecognized code rather than dropping it.
            let modality = Modality.normalized(code) ?? Modality(unchecked: code)
            try setElement(&dicomFile, tag: .modality, value: modality.rawValue, vr: .CS)
        }
    }
    
    private func populateFromPatient(dicomFile: inout DICOMFile, fhir: [String: Any]) throws {
        // Patient ID
        if let patientID = fhir["id"] as? String {
            try setElement(&dicomFile, tag: .patientID, value: patientID, vr: .LO)
        }
        
        // Patient Name
        if let names = fhir["name"] as? [[String: Any]],
           let firstName = names.first {
            let family = firstName["family"] as? String ?? ""
            let given = firstName["given"] as? [String] ?? []
            let dicomName = DICOMValueMapping.personName(
                fhirFamily: family,
                given: given,
                prefix: firstName["prefix"] as? [String] ?? [],
                suffix: firstName["suffix"] as? [String] ?? []
            )
            try setElement(&dicomFile, tag: .patientName, value: dicomName, vr: .PN)
        }
        
        // Birth Date
        if let birthDate = fhir["birthDate"] as? String {
            // DA is YYYYMMDD only; a partial FHIR date gives the empty (Type 2) value
            let dicomDate = DICOMValueMapping.date(fromFHIR: birthDate) ?? ""
            try setElement(&dicomFile, tag: .patientBirthDate, value: dicomDate, vr: .DA)
        }
        
        // Gender
        if let gender = fhir["gender"] as? String {
            try setElement(&dicomFile, tag: .patientSex, value: DICOMValueMapping.patientSex(fromFHIR: gender), vr: .CS)
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractString(from file: DICOMFile, tag: Tag) -> String? {
        return file.dataSet.string(for: tag)
    }
    
    private func setElement(_ file: inout DICOMFile, tag: Tag, value: String, vr: VR) throws {
        var newDataSet = file.dataSet
        newDataSet.setString(value, for: tag, vr: vr)
        file = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: newDataSet)
    }
    
    private func createBasicDICOMFile() throws -> DICOMFile {
        // A minimal Secondary Capture Image Storage data set; UIDs and File Meta Information
        // under DICOMKit's own root (UIDGenerator, DICOMFile.create — PS3.5 9.1).
        let sopClassUID = "1.2.840.10008.5.1.4.1.1.7" // Secondary Capture Image Storage
        let sopInstanceUID = UIDGenerator.generateSOPInstanceUID().value
        
        var dataset = DataSet()
        dataset.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        dataset.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)
        dataset.setString(UIDGenerator.generateStudyInstanceUID().value, for: .studyInstanceUID, vr: .UI)
        dataset.setString(UIDGenerator.generateSeriesInstanceUID().value, for: .seriesInstanceUID, vr: .UI)
        dataset.setString(Modality.ot.rawValue, for: .modality, vr: .CS)
        
        return DICOMFile.create(dataSet: dataset, sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
    }
    
    /// DICOM PN (first component group) to a FHIR HumanName: given and middle name
    /// components become the `given` list; prefix and suffix are carried.
    private func fhirHumanName(fromDICOM value: String) -> [String: Any] {
        let pn = DICOMValueMapping.personName(fromDICOM: value)
        var name: [String: Any] = [
            "use": "official",
            "family": pn.family,
            "given": [pn.given, pn.middle].filter { !$0.isEmpty }
        ]
        if !pn.prefix.isEmpty { name["prefix"] = [pn.prefix] }
        if !pn.suffix.isEmpty { name["suffix"] = [pn.suffix] }
        return name
    }
    
    private func formatFHIRDateTime(date: String, time: String) -> String {
        // DICOM: YYYYMMDD + HHMMSS
        // FHIR: YYYY-MM-DDTHH:MM:SS
        guard date.count == 8 else { return "" }
        
        let year = date.prefix(4)
        let month = date.dropFirst(4).prefix(2)
        let day = date.dropFirst(6).prefix(2)
        
        var result = "\(year)-\(month)-\(day)"
        
        if time.count >= 6 {
            let hour = time.prefix(2)
            let minute = time.dropFirst(2).prefix(2)
            let second = time.dropFirst(4).prefix(2)
            result += "T\(hour):\(minute):\(second)"
        }
        
        return result
    }
    
    private func formatFHIRDate(_ date: String) -> String {
        // DICOM: YYYYMMDD -> FHIR: YYYY-MM-DD
        guard date.count == 8 else { return date }
        let year = date.prefix(4)
        let month = date.dropFirst(4).prefix(2)
        let day = date.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(day)"
    }
    
    private func mapDICOMSexToFHIR(_ sex: String) -> String {
        switch sex.uppercased() {
        case "M": return "male"
        case "F": return "female"
        case "O": return "other"
        default: return "unknown"
        }
    }
    
}

// MARK: - Additional DICOM Tags (not in standard extensions)

extension Tag {
    static let numberOfStudyRelatedSeries = Tag(group: 0x0020, element: 0x1206)
    static let numberOfStudyRelatedInstances = Tag(group: 0x0020, element: 0x1208)
    static let numberOfSeriesRelatedInstances = Tag(group: 0x0020, element: 0x1209)
}
