// NEMA-verified: 2026a, checked 2026-10-01 — the 10 attributes written (Patient ID, Issuer of Patient ID, Patient's Name, Birth Date, Sex, Study Description, Modality, Study Date/Time, Study Instance UID, Accession Number) use the PS3.6 2026a Table 6-1 VRs; values pass through DICOMValueMapping (PN, DA, TM, M/F/O, UID, SH/LO lengths per PS3.5 Table 6.2-1 and PS3.3 Table C.7-1); generated UIDs and File Meta under DICOMKit's own root (PS3.5 9.1; the former 1.2.826.0.1.3680043.10.<n> literals were other organisations' arcs); 1 UID literal (Secondary Capture Image Storage) matches PS3.6 Table A-1. The output is not a complete SC Image IOD (D-DICOM-GATEWAY-1)
import Foundation
import DICOMKit
import DICOMCore

// MARK: - HL7 to DICOM Converter

class HL7ToDICOMConverter {
    private let config: MappingConfiguration
    
    init(config: MappingConfiguration = MappingConfiguration()) {
        self.config = config
    }
    
    func convert(hl7Message: HL7Message, templateFile: DICOMFile? = nil) throws -> DICOMFile {
        // Start with template or create new file
        var dicomFile: DICOMFile
        if let template = templateFile {
            dicomFile = template
        } else {
            dicomFile = try createBasicDICOMFile()
        }
        
        // Extract patient information from PID segment
        if let pid = hl7Message.segment("PID") {
            try populatePatientInfo(dicomFile: &dicomFile, pid: pid)
        }
        
        // Extract study information from OBR segment if present
        if let obr = hl7Message.segment("OBR") {
            try populateStudyInfo(dicomFile: &dicomFile, obr: obr)
        }
        
        // Extract accession number from ORC segment if present
        if let orc = hl7Message.segment("ORC") {
            try populateOrderInfo(dicomFile: &dicomFile, orc: orc)
        }
        
        return dicomFile
    }
    
    // MARK: - Population Methods
    
    private func populatePatientInfo(dicomFile: inout DICOMFile, pid: HL7Segment) throws {
        // Patient ID (PID-3, CX): the ID component goes to Patient ID (LO), the assigning
        // authority to Issuer of Patient ID (0010,0021) — PS3.3 Table C.7-1.
        if let cx = pid[2] {
            let (patientID, issuer) = DICOMValueMapping.patientID(fromHL7CX: cx)
            warnIfTooLong(patientID, max: DICOMValueMapping.longStringMaxLength, attribute: "Patient ID (0010,0020)", vr: "LO")
            try setElement(&dicomFile, tag: .patientID, value: patientID, vr: .LO)
            if let issuer {
                try setElement(&dicomFile, tag: .issuerOfPatientID, value: issuer, vr: .LO)
            }
        }
        
        // Patient Name (PID-5, XPN) -> PN, PS3.5 6.2.1 component order
        if let hl7Name = pid[4] {
            let dicomName = DICOMValueMapping.personName(fromHL7XPN: hl7Name)
            try setElement(&dicomFile, tag: .patientName, value: dicomName, vr: .PN)
        }
        
        // Date of Birth (PID-7). DA is YYYYMMDD only; a reduced-precision HL7 date gives the
        // empty value (Patient's Birth Date is Type 2).
        if let dob = pid[6] {
            let dicomDate = DICOMValueMapping.date(fromHL7: dob) ?? ""
            try setElement(&dicomFile, tag: .patientBirthDate, value: dicomDate, vr: .DA)
        }
        
        // Sex (PID-8) -> M, F, O or empty (PS3.3 Table C.7-1)
        if let sex = pid[7] {
            let dicomSex = DICOMValueMapping.patientSex(fromHL7: sex)
            try setElement(&dicomFile, tag: .patientSex, value: dicomSex, vr: .CS)
        }
    }
    
    private func populateStudyInfo(dicomFile: inout DICOMFile, obr: HL7Segment) throws {
        // Study Description (OBR-4)
        if let serviceID = obr[3] {
            // Parse "MODALITY^Description"
            let components = serviceID.split(separator: "^")
            if components.count >= 2 {
                try setElement(&dicomFile, tag: .studyDescription, value: String(components[1]), vr: .LO)
                // Normalize the inbound code: an HL7 feed is an external system
                // and commonly sends a spelling ("MRI", "PET") rather than the
                // DICOM defined term. An unrecognized code is kept as sent —
                // private codes are legal — but uppercased and trimmed to CS form.
                let raw = String(components[0])
                let modality = Modality.normalized(raw) ?? Modality(unchecked: raw)
                try setElement(&dicomFile, tag: .modality, value: modality.rawValue, vr: .CS)
            }
        }
        
        // Study Date/Time (OBR-7)
        if let observationDateTime = obr[6] {
            if let date = DICOMValueMapping.date(fromHL7: observationDateTime) {
                try setElement(&dicomFile, tag: .studyDate, value: date, vr: .DA)
            }
            if let time = DICOMValueMapping.time(fromHL7: observationDateTime) {
                try setElement(&dicomFile, tag: .studyTime, value: time, vr: .TM)
            }
        }
        
        // Filler Order Number -> Study Instance UID (OBR-3)
        if let filler = obr[2] {
            // Used only when it is a UID per PS3.5 9.1; otherwise the generated one stays
            let fillerOrderNumber = DICOMValueMapping.entityIdentifier(fromHL7EI: filler)
            if DICOMValueMapping.isValidUID(fillerOrderNumber) {
                try setElement(&dicomFile, tag: .studyInstanceUID, value: fillerOrderNumber, vr: .UI)
            }
        }
    }
    
    private func populateOrderInfo(dicomFile: inout DICOMFile, orc: HL7Segment) throws {
        // Accession Number (ORC-2, EI): the entity identifier; SH allows 16 characters
        if let placer = orc[1] {
            let accessionNumber = DICOMValueMapping.entityIdentifier(fromHL7EI: placer)
            warnIfTooLong(accessionNumber, max: DICOMValueMapping.shortStringMaxLength, attribute: "Accession Number (0008,0050)", vr: "SH")
            try setElement(&dicomFile, tag: .accessionNumber, value: accessionNumber, vr: .SH)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createBasicDICOMFile() throws -> DICOMFile {
        // A minimal Secondary Capture Image Storage data set. UIDs come from DICOMKit's
        // UIDGenerator and the File Meta Information from DICOMFile.create, both under the
        // library's own root (PS3.5 9.1); the former literals sat under other
        // organisations' arcs of 1.2.826.0.1.3680043.10.
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
    
    private func setElement(_ file: inout DICOMFile, tag: Tag, value: String, vr: VR) throws {
        var newDataSet = file.dataSet
        newDataSet.setString(value, for: tag, vr: vr)
        file = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: newDataSet)
    }
    
    private func warnIfTooLong(_ value: String, max: Int, attribute: String, vr: String) {
        guard value.count > max else { return }
        FileHandle.standardError.write(Data("warning: \(attribute) \"\(value)\" is \(value.count) characters; VR \(vr) allows \(max) (PS3.5 Table 6.2-1)\n".utf8))
    }
}
