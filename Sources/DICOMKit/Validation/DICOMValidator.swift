// NEMA-verified: 2026a, checked 2026-10-01 — PS3.10 2026a Table 7.1-1 Type 1 File Meta elements; PS3.5 Table 6.2-1 maximum lengths and character repertoires of the 16 character-string VRs (AE AS CS DA DS DT IS LO LT PN SH ST TM UC UI UT) and the DA, TM, UI, AS, DS, IS forms, PS3.5 6.2.1 PN component groups, PS3.6 Table 6-1 VM column (level 2, errors); ISO_IR 192; per-IOD Type 1/2 tables from PS3.3 Tables A.2-1, A.3-1, A.4-1, A.6-1, A.8-1, A.33.1-1, A.33.3-1, A.35.1-1..A.35.4-1 and the module tables C.7-1, C.7-3, C.7-5a, C.7-6, C.7-8, C.7-9, C.7-10, C.7-11b/c, C.8-1, C.8-3, C.8-4, C.8-18, C.8-24, C.10-4, C.11.9-1 (PR), C.11.10-1, 10-12 (Content Creator's Name Type 3 via Table 10.9.3-1), C.11.11-1b, C.11.6-1, C.11.15-1, C.12-1, C.17-1 (SR), C.17-2, C.17-5 (root Concept Name Code Sequence 1C), C.18.8-1, C.17.6-1 (KO), C.17.6-2; IOD message prefixes are PS3.6 Table A-1 SOP Class names; Type semantics PS3.5 7.4.1-7.4.4
// NEMA-verified: 2026a, checked 2026-10-06 — iodNameBySOPClassUID (lifted from dicom-validate IODOption, D248): the 7 UIDs and their comments are PS3.6 2026a Table A-1 rows (dumped by script), the IODs they name are the PS3.3 2026a A.2, A.3, A.4, A.6, A.8, A.33.1, A.33.3 titles that PS3.4 2026a Table B.5-1 assigns to them; iodName(forIODOption:) accepts Table A-1 keywords and UIDs
import Foundation
import DICOMCore
import DICOMDictionary
import J2KCore

/// Main validator class that orchestrates DICOM file validation
public struct DICOMValidator {
    let level: Int
    let iod: String?
    let force: Bool
    
    public init(level: Int, iod: String?, force: Bool) {
        self.level = level
        self.iod = iod
        self.force = force
    }
    
    public func validate(data: Data, filePath: String) throws -> ValidationResult {
        var errors: [ValidationIssue] = []
        var warnings: [ValidationIssue] = []
        
        // Level 1: File format validation
        let dicomFile: DICOMFile
        do {
            dicomFile = try DICOMFile.read(from: data, force: force)
        } catch {
            errors.append(ValidationIssue(
                level: .error,
                message: "Failed to parse DICOM file: \(error.localizedDescription)",
                tag: nil
            ))
            return ValidationResult(filePath: filePath, isValid: false, errors: errors, warnings: warnings)
        }
        
        // Check preamble if not forced
        if !force && data.count >= 132 {
            let preambleEnd = data.startIndex.advanced(by: 128)
            let dicmPrefix = data[preambleEnd..<preambleEnd.advanced(by: 4)]
            if String(data: dicmPrefix, encoding: .ascii) != "DICM" {
                warnings.append(ValidationIssue(
                    level: .warning,
                    message: "Missing DICM prefix at byte 128",
                    tag: nil
                ))
            }
        }
        
        // Validate file meta information
        validateFileMetaInformation(dicomFile: dicomFile, errors: &errors, warnings: &warnings)
        
        if level >= 2 {
            // Level 2: Tag presence and VR/VM validation
            validateTagsAndVR(dataSet: dicomFile.dataSet, errors: &errors, warnings: &warnings)
        }
        
        if level >= 3 {
            // Level 3: IOD-specific validation
            if let iodName = iod ?? detectIOD(from: dicomFile.dataSet) {
                validateIOD(dataSet: dicomFile.dataSet, iodName: iodName, errors: &errors, warnings: &warnings)
            } else {
                warnings.append(ValidationIssue(
                    level: .warning,
                    message: "Cannot determine IOD type for validation",
                    tag: .sopClassUID
                ))
            }
        }
        
        if level >= 4 {
            // Level 4: Best practices validation
            validateBestPractices(dataSet: dicomFile.dataSet, errors: &errors, warnings: &warnings)
        }
        
        if level >= 5 {
            // Level 5: JPEG 2000 codestream conformance validation
            let tsUID = dicomFile.fileMetaInformation.string(for: .transferSyntaxUID) ?? ""
            if isJ2KTransferSyntax(tsUID) {
                validateJ2KCodestream(dataSet: dicomFile.dataSet, tsUID: tsUID, errors: &errors, warnings: &warnings)
            }
        }
        
        let isValid = errors.isEmpty
        return ValidationResult(filePath: filePath, isValid: isValid, errors: errors, warnings: warnings)
    }
    
    private func validateFileMetaInformation(dicomFile: DICOMFile, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let dataSet = dicomFile.fileMetaInformation
        
        // The Type 1 File Meta Information elements of PS3.10 Table 7.1-1
        let requiredMetaTags: [(Tag, String)] = [
            (.fileMetaInformationGroupLength, "File Meta Information Group Length"),
            (.fileMetaInformationVersion, "File Meta Information Version"),
            (.mediaStorageSOPClassUID, "Media Storage SOP Class UID"),
            (.mediaStorageSOPInstanceUID, "Media Storage SOP Instance UID"),
            (.transferSyntaxUID, "Transfer Syntax UID"),
            (.implementationClassUID, "Implementation Class UID")
        ]
        
        for (tag, name) in requiredMetaTags {
            if dataSet[tag] == nil {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Missing required File Meta Information element: \(name)",
                    tag: tag
                ))
            }
        }
        
        // Validate Transfer Syntax UID format
        if let tsUID = dataSet.string(for: .transferSyntaxUID) {
            if !isValidUID(tsUID) {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Invalid Transfer Syntax UID format",
                    tag: .transferSyntaxUID
                ))
            }
        }
    }
    
    private func validateTagsAndVR(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        // Validate required Type 1 elements
        let requiredTags: [(Tag, String)] = [
            (.sopClassUID, "SOP Class UID"),
            (.sopInstanceUID, "SOP Instance UID")
        ]
        
        for (tag, name) in requiredTags {
            if let element = dataSet[tag] {
                if element.length == 0 {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "Type 1 element \(name) is empty",
                        tag: tag
                    ))
                }
            } else {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Missing required Type 1 element: \(name)",
                    tag: tag
                ))
            }
        }
        
        // Validate VR for known tags
        for tag in dataSet.tags {
            if let element = dataSet[tag],
               let entry = DataElementDictionary.lookup(tag: tag) {
                
                // Check if VR matches dictionary
                if !entry.vr.contains(element.vr) && element.vr != .UN {
                    warnings.append(ValidationIssue(
                        level: .warning,
                        message: "Unexpected VR \(element.vr) for tag \(tag) (expected: \(entry.vr.map { $0.rawValue }.joined(separator: " or ")))",
                        tag: tag
                    ))
                }
                
                // Validate value format based on VR
                validateValueFormat(element: element, entry: entry, errors: &errors, warnings: &warnings)
            }
        }
        
        // Validate UIDs
        validateUIDs(dataSet: dataSet, errors: &errors, warnings: &warnings)
        
        // Validate dates and times
        validateDatesAndTimes(dataSet: dataSet, errors: &errors, warnings: &warnings)
    }
    
    private func validateValueFormat(element: DataElement, entry: DataElementEntry, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        // A zero-length value is legal for any Type 2 attribute: PS3.5 5 defines
        // it as "present with zero length" when the value is unknown. Only a
        // non-empty value can be malformed, so empty values skip format checks.
        // Every check runs per Value (PS3.5 6.4: backslash-delimited), so a multi-valued
        // DA / TM / UI is judged value by value.
        let name = entry.name
        let values = VRValueRules.values(of: element)

        switch element.vr {
        case .UI:
            for value in values where !value.isEmpty && !isValidUID(value) {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Invalid UID format for \(name)",
                    tag: element.tag
                ))
            }
        case .DA:
            for value in values where !value.isEmpty && !isValidDate(value) {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Invalid date format for \(name) (expected YYYYMMDD)",
                    tag: element.tag
                ))
            }
        case .TM:
            for value in values where !value.isEmpty && !isValidTime(value) {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Invalid time format for \(name) (expected HHMMSS.FFFFFF)",
                    tag: element.tag
                ))
            }
        case .PN:
            // PS3.5 6.2.1: at most three component groups ("=" delimiters), each with at most
            // four component delimiters ("^"); 64 characters per component group (Table 6.2-1).
            for value in values {
                let groups = value.components(separatedBy: "=")
                if groups.count > 3 {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "\(name) (PN) has \(groups.count) component groups; at most 3 are allowed [PS3.5 6.2.1]",
                        tag: element.tag
                    ))
                }
                for group in groups {
                    if group.filter({ $0 == "^" }).count > 4 {
                        errors.append(ValidationIssue(
                            level: .error,
                            message: "\(name) (PN) has a component group with more than 4 component delimiters \"^\" [PS3.5 6.2.1]",
                            tag: element.tag
                        ))
                    }
                    if group.count > 64 {
                        errors.append(ValidationIssue(
                            level: .error,
                            message: "\(name) (PN) has a component group of \(group.count) chars; at most 64 chars per component group [PS3.5 Table 6.2-1]",
                            tag: element.tag
                        ))
                    }
                }
            }
        default:
            break
        }

        // PS3.5 Table 6.2-1 maximum length and character repertoire.
        if let rule = VRValueRules.rule(for: element.vr) {
            for (index, value) in values.enumerated() where !value.isEmpty {
                let length = rule.countsBytes ? value.utf8.count : value.count
                let position = values.count > 1 ? "Value \(index + 1) of " : ""
                if let fixed = rule.fixedLength, length != fixed {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "\(position)\(name) (\(element.vr.rawValue)) is \(length) bytes; \(element.vr.rawValue) is \(fixed) bytes fixed [PS3.5 Table 6.2-1]",
                        tag: element.tag
                    ))
                } else if let max = rule.maxLength, length > max {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "\(position)\(name) (\(element.vr.rawValue)) is \(length) \(rule.countsBytes ? "bytes" : "chars"); \(element.vr.rawValue) allows at most \(max) \(rule.countsBytes ? "bytes" : "chars") [PS3.5 Table 6.2-1]",
                        tag: element.tag
                    ))
                }
                if let bad = value.unicodeScalars.first(where: { !rule.allows($0) }) {
                    let shown = bad.value < 0x20 || bad.value == 0x7F
                        ? String(format: "0x%02X", bad.value) : "'\(Character(bad))'"
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "\(position)\(name) (\(element.vr.rawValue)) contains \(shown), outside the \(element.vr.rawValue) character repertoire (\(rule.repertoire)) [PS3.5 Table 6.2-1]",
                        tag: element.tag
                    ))
                }
            }
        }

        // PS3.5 Table 6.2-1 value forms of AS, DS and IS.
        for (index, value) in values.enumerated() where !value.isEmpty {
            let position = values.count > 1 ? "Value \(index + 1) of " : ""
            switch element.vr {
            case .AS:
                let chars = Array(value)
                if chars.count == 4, !(chars[0...2].allSatisfy { $0.isASCII && $0.isNumber } && "DWMY".contains(chars[3])) {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "\(position)\(name) (AS) '\(value)' is not nnnD, nnnW, nnnM or nnnY [PS3.5 Table 6.2-1]",
                        tag: element.tag))
                }
            case .DS:
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if Double(trimmed) == nil || trimmed.contains(" ") {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "\(position)\(name) (DS) '\(value)' is not a decimal number [PS3.5 Table 6.2-1]",
                        tag: element.tag))
                }
            case .IS:
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if Int32(trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed) == nil {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "\(position)\(name) (IS) '\(value)' is not an integer in -2^31...2^31-1 [PS3.5 Table 6.2-1]",
                        tag: element.tag))
                }
            default:
                break
            }
        }

        // PS3.6 Table 6-1 VM, when the element is encoded with a VR the dictionary gives.
        if entry.vr.contains(element.vr), let vm = VRValueRules.ValueMultiplicity(entry.vm),
           let count = VRValueRules.valueCount(of: element), count > 0, !vm.allows(count) {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(name) has \(count) value\(count == 1 ? "" : "s"); PS3.6 Table 6-1 gives VM \(entry.vm) [PS3.5 6.4]",
                tag: element.tag
            ))
        }
    }

    private func validateUIDs(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let uidTags: [(Tag, String)] = [
            (.sopClassUID, "SOP Class UID"),
            (.sopInstanceUID, "SOP Instance UID"),
            (.studyInstanceUID, "Study Instance UID"),
            (.seriesInstanceUID, "Series Instance UID")
        ]
        
        for (tag, name) in uidTags where dataSet[tag]?.vr != .UI {   // UI values: validateValueFormat
            if let uid = dataSet.string(for: tag) {
                if !isValidUID(uid) {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "Invalid \(name) format",
                        tag: tag
                    ))
                }
            }
        }
    }
    
    private func validateDatesAndTimes(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let dateTags: [(Tag, String)] = [
            (.studyDate, "Study Date"),
            (.seriesDate, "Series Date"),
            (.acquisitionDate, "Acquisition Date")
        ]
        
        for (tag, name) in dateTags where dataSet[tag]?.vr != .DA {   // DA values: validateValueFormat
            if let date = dataSet.string(for: tag), !date.isEmpty {
                if !isValidDate(date) {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "Invalid \(name) format (expected YYYYMMDD)",
                        tag: tag
                    ))
                }
            }
        }
        
        let timeTags: [(Tag, String)] = [
            (.studyTime, "Study Time"),
            (.seriesTime, "Series Time"),
            (.acquisitionTime, "Acquisition Time")
        ]
        
        for (tag, name) in timeTags where dataSet[tag]?.vr != .TM {   // TM values: validateValueFormat
            if let time = dataSet.string(for: tag), !time.isEmpty {
                if !isValidTime(time) {
                    errors.append(ValidationIssue(
                        level: .error,
                        message: "Invalid \(name) format (expected HHMMSS.FFFFFF)",
                        tag: tag
                    ))
                }
            }
        }
    }
    
    private func validateIOD(dataSet: DataSet, iodName: String, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let validator: IODValidator
        
        switch iodName.lowercased() {
        case "ctimagestorage", "ct":
            validator = CTImageStorageValidator()
        case "mrimagestorage", "mr":
            validator = MRImageStorageValidator()
        case "crimagestorage", "cr":
            validator = CRImageStorageValidator()
        case "usimagestorage", "ultrasound":
            validator = USImageStorageValidator()
        case "secondarycaptureimagestorage", "sc":
            validator = SecondaryCaptureImageStorageValidator()
        case "grayscalesoftcopypresentationstate", "gsps":
            validator = GrayscaleSoftcopyPresentationStateValidator()
        case "pseudocolorsoftcopypresentationstate":
            validator = PseudoColorSoftcopyPresentationStateValidator()
        case "basictextsr", "enhancedsr", "comprehensivesr", "structuredreport", "sr", "keyobjectselection", "kos":
            validator = StructuredReportValidator()
        default:
            warnings.append(ValidationIssue(
                level: .warning,
                message: "IOD validation not implemented for: \(iodName)",
                tag: .sopClassUID
            ))
            return
        }
        
        validator.validate(dataSet: dataSet, errors: &errors, warnings: &warnings)
    }
    
    private func validateBestPractices(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        // Recommend Character Set specification
        if dataSet[.specificCharacterSet] == nil {
            warnings.append(ValidationIssue(
                level: .warning,
                message: "Specific Character Set not specified (ISO_IR 100 or ISO_IR 192 recommended)",
                tag: .specificCharacterSet
            ))
        }
        
        // Check for private tags usage
        let privateTags = dataSet.tags.filter { $0.isPrivate }
        if privateTags.count > 10 {
            warnings.append(ValidationIssue(
                level: .warning,
                message: "File contains \(privateTags.count) private tags (may affect interoperability)",
                tag: nil
            ))
        }

        validateModalityDefinedTerm(dataSet: dataSet, warnings: &warnings)
    }

    /// Checks Modality (0008,0060) against the PS3.3 C.7.3.1.1.1 Defined Terms.
    ///
    /// Modality is a Defined Term, not an Enumerated Value, so a code outside the
    /// list is legal and warns rather than errors. Retired codes warn separately:
    /// they are valid in legacy data but should not be written by new equipment.
    private func validateModalityDefinedTerm(dataSet: DataSet, warnings: inout [ValidationIssue]) {
        guard let raw = dataSet.string(for: .modality)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }

        guard let modality = Modality(rawValue: raw) else {
            // An alias is still wrong on the wire, so name the code it should be.
            if let normalized = Modality.normalized(raw) {
                warnings.append(ValidationIssue(
                    level: .warning,
                    message: "Modality '\(raw)' is not a DICOM Defined Term "
                        + "(did you mean '\(normalized.rawValue)' — \(normalized.name)?)",
                    tag: .modality
                ))
            } else {
                warnings.append(ValidationIssue(
                    level: .warning,
                    message: "Modality '\(raw)' is not a DICOM Defined Term "
                        + "(PS3.3 C.7.3.1.1.1); private codes are permitted but reduce interoperability",
                    tag: .modality
                ))
            }
            return
        }

        if modality.isRetired {
            warnings.append(ValidationIssue(
                level: .warning,
                message: "Modality '\(modality.rawValue)' (\(modality.name)) is retired "
                    + "and should not be used in new objects",
                tag: .modality
            ))
        } else if !modality.isStandard {
            warnings.append(ValidationIssue(
                level: .warning,
                message: "Modality '\(modality.rawValue)' is conventional but not a "
                    + "DICOM Defined Term (PS3.3 C.7.3.1.1.1)",
                tag: .modality
            ))
        }
    }
    
    private func detectIOD(from dataSet: DataSet) -> String? {
        guard let sopClassUID = dataSet.string(for: .sopClassUID) else {
            return nil
        }
        
        // One table for the validator, `dicom-validate --iod` and the Workshop (D248).
        return Self.iodName(forSOPClassUID: sopClassUID)
    }
    
    private func isValidUID(_ uid: String) -> Bool {
        // UID format: numeric components separated by dots
        // Each component is 1 or more digits
        // Max length 64 characters
        guard uid.count <= 64 else { return false }
        
        let components = uid.components(separatedBy: ".")
        guard !components.isEmpty else { return false }
        
        for component in components {
            guard !component.isEmpty else { return false }
            guard component.allSatisfy({ $0.isNumber }) else { return false }
            // Leading zeros not allowed except for "0"
            if component.count > 1 && component.first == "0" {
                return false
            }
        }
        
        return true
    }
    
    private func isValidDate(_ date: String) -> Bool {
        // DICOM Date format: YYYYMMDD
        guard date.count == 8 else { return false }
        guard date.allSatisfy({ $0.isNumber }) else { return false }
        
        guard let year = Int(date.prefix(4)),
              let month = Int(date.dropFirst(4).prefix(2)),
              let day = Int(date.suffix(2)) else {
            return false
        }
        
        // PS3.5 Table 6.2-1 DA: YYYYMMDD; the year is not otherwise bounded
        guard year >= 0 && year <= 9999 else { return false }
        guard month >= 1 && month <= 12 else { return false }
        guard day >= 1 && day <= 31 else { return false }
        
        // Ensure the date is a valid Gregorian calendar date
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        
        let calendar = Calendar(identifier: .gregorian)
        guard calendar.date(from: components) != nil else { return false }
        
        return true
    }
    
    private func isValidTime(_ time: String) -> Bool {
        // PS3.5 Table 6.2-1 TM: HHMMSS.FFFFFF, where MM, SS and FFFFFF are each optional
        // after the preceding component; 60 seconds is allowed for a leap second
        let components = time.components(separatedBy: ".")
        guard components.count <= 2 else { return false }

        let hhmmss = components[0]
        guard [2, 4, 6].contains(hhmmss.count) else { return false }
        guard hhmmss.allSatisfy({ $0.isNumber }) else { return false }

        guard let hh = Int(hhmmss.prefix(2)), hh >= 0 && hh <= 23 else { return false }
        if hhmmss.count >= 4 {
            guard let mm = Int(hhmmss.dropFirst(2).prefix(2)), mm >= 0 && mm <= 59 else { return false }
        }
        if hhmmss.count == 6 {
            guard let ss = Int(hhmmss.suffix(2)), ss >= 0 && ss <= 60 else { return false }
        }

        if components.count == 2 {
            guard hhmmss.count == 6 else { return false }
            let fraction = components[1]
            guard (1...6).contains(fraction.count) else { return false }
            guard fraction.allSatisfy({ $0.isNumber }) else { return false }
        }

        return true
    }
    
    // MARK: - JPEG 2000 Codestream Validation (Level 5)
    
    /// JPEG 2000 / HTJ2K membership per the shared `TransferSyntax` source of truth
    /// (covers .90/.91/.92/.93 and HTJ2K .201/.202/.203).
    private func isJ2KTransferSyntax(_ uid: String) -> Bool {
        TransferSyntax.from(uid: uid)?.isJPEG2000 ?? false
    }
    
    private func validateJ2KCodestream(
        dataSet: DataSet,
        tsUID: String,
        errors: inout [ValidationIssue],
        warnings: inout [ValidationIssue]
    ) {
        guard let pixelElement = dataSet[.pixelData] else {
            errors.append(ValidationIssue(
                level: .error,
                message: "J2K transfer syntax declared but Pixel Data (7FE0,0010) is absent",
                tag: .pixelData
            ))
            return
        }
        
        guard let fragments = pixelElement.encapsulatedFragments, !fragments.isEmpty else {
            warnings.append(ValidationIssue(
                level: .warning,
                message: "J2K transfer syntax declared but pixel data is not encapsulated",
                tag: .pixelData
            ))
            return
        }
        
        let validator = J2KHTInteroperabilityValidator()
        let harness = HTJ2KConformanceTestHarness()
        
        for (idx, fragment) in fragments.enumerated() {
            guard !fragment.isEmpty else { continue }
            
            // ISO 15444-4 structure check
            let structureErrors = harness.validateCodestreamStructure(fragment)
            for msg in structureErrors {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Frame \(idx + 1) J2K structure: \(msg)",
                    tag: .pixelData
                ))
            }
            
            // Marker ordering
            let markerResult = validator.validateMarkerOrdering(codestream: fragment)
            for msg in markerResult {
                warnings.append(ValidationIssue(
                    level: .warning,
                    message: "Frame \(idx + 1) J2K marker ordering: \(msg)",
                    tag: .pixelData
                ))
            }
            
            // Segment lengths
            let segResult = validator.validateSegmentLengths(codestream: fragment)
            for msg in segResult {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Frame \(idx + 1) J2K segment length: \(msg)",
                    tag: .pixelData
                ))
            }
            
            // HTJ2K capability signaling
            let capResult = validator.validateCapabilitySignaling(codestream: fragment)
            let expectedHTJ2K = tsUID.hasPrefix("1.2.840.10008.1.2.4.20")
            if expectedHTJ2K && !capResult.isHTJ2K {
                warnings.append(ValidationIssue(
                    level: .warning,
                    message: "Frame \(idx + 1): Transfer syntax declares HTJ2K but CAP marker absent",
                    tag: .pixelData
                ))
            }
            for msg in capResult.errors {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "Frame \(idx + 1) HTJ2K CAP: \(msg)",
                    tag: .pixelData
                ))
            }
            for msg in capResult.warnings {
                warnings.append(ValidationIssue(
                    level: .warning,
                    message: "Frame \(idx + 1) HTJ2K CAP: \(msg)",
                    tag: .pixelData
                ))
            }
            
            // Only validate first frame to keep performance acceptable for large multi-frame files
            if idx == 0 && fragments.count > 1 {
                break
            }
        }
    }
}

/// PS3.5 2026a Table 6.2-1 length and character-repertoire rules of the character-string VRs,
/// and the PS3.6 Table 6-1 VM column, used by level-2 validation.
enum VRValueRules {

    struct Rule {
        /// Maximum length of one Value; `nil` when only bounded by the 32-bit length.
        let maxLength: Int?
        /// Fixed length of one Value (AS: 4, DA: 8).
        let fixedLength: Int?
        /// `true` for "bytes", `false` for "chars" in Table 6.2-1.
        let countsBytes: Bool
        /// The repertoire, as Table 6.2-1 words it, for messages.
        let repertoire: String
        let allows: (Unicode.Scalar) -> Bool
    }

    private static func isControl(_ c: Unicode.Scalar) -> Bool { c.value < 0x20 || c.value == 0x7F }
    private static func digit(_ c: Unicode.Scalar) -> Bool { c.value >= 0x30 && c.value <= 0x39 }

    /// LO, SH, PN, UC: no BACKSLASH (it delimits Values) and no Control Characters except ESC.
    private static func stringRepertoire(_ c: Unicode.Scalar) -> Bool {
        c.value == 0x1B || !isControl(c)
    }
    /// LT, ST, UT: no Control Characters except TAB, LF, FF, CR and ESC.
    private static func textRepertoire(_ c: Unicode.Scalar) -> Bool {
        [0x09, 0x0A, 0x0C, 0x0D, 0x1B].contains(c.value) || !isControl(c)
    }

    /// The Table 6.2-1 rule of `vr`; `nil` for VRs not checked here (binary VRs, UR).
    static func rule(for vr: VR) -> Rule? {
        switch vr {
        case .AE: return Rule(maxLength: 16, fixedLength: nil, countsBytes: true,
                              repertoire: "Default Character Repertoire excluding BACKSLASH and control characters",
                              allows: { $0.value >= 0x20 && $0.value <= 0x7E && $0 != "\\" })
        case .AS: return Rule(maxLength: nil, fixedLength: 4, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"D\", \"W\", \"M\", \"Y\"",
                              allows: { digit($0) || "DWMY".unicodeScalars.contains($0) })
        case .CS: return Rule(maxLength: 16, fixedLength: nil, countsBytes: true,
                              repertoire: "uppercase characters, \"0\"-\"9\", SPACE and \"_\"",
                              allows: { ($0.value >= 0x41 && $0.value <= 0x5A) || digit($0) || $0 == " " || $0 == "_" })
        case .DA: return Rule(maxLength: nil, fixedLength: 8, countsBytes: true,
                              repertoire: "\"0\"-\"9\"", allows: digit)
        case .DS: return Rule(maxLength: 16, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"+\", \"-\", \"E\", \"e\", \".\" and SPACE",
                              allows: { digit($0) || "+-Ee. ".unicodeScalars.contains($0) })
        case .DT: return Rule(maxLength: 26, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"+\", \"-\", \".\" and SPACE",
                              allows: { digit($0) || "+-. ".unicodeScalars.contains($0) })
        case .IS: return Rule(maxLength: 12, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \"+\", \"-\" and SPACE",
                              allows: { digit($0) || "+- ".unicodeScalars.contains($0) })
        case .LO: return Rule(maxLength: 64, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .LT: return Rule(maxLength: 10240, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except TAB, LF, FF, CR, ESC", allows: textRepertoire)
        case .PN: return Rule(maxLength: nil, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .SH: return Rule(maxLength: 16, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .ST: return Rule(maxLength: 1024, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except TAB, LF, FF, CR, ESC", allows: textRepertoire)
        case .TM: return Rule(maxLength: 14, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\", \".\" and SPACE",
                              allows: { digit($0) || $0 == "." || $0 == " " })
        case .UC: return Rule(maxLength: nil, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except ESC", allows: stringRepertoire)
        case .UI: return Rule(maxLength: 64, fixedLength: nil, countsBytes: true,
                              repertoire: "\"0\"-\"9\" and \".\"", allows: { digit($0) || $0 == "." })
        case .UT: return Rule(maxLength: nil, fixedLength: nil, countsBytes: false,
                              repertoire: "no control characters except TAB, LF, FF, CR, ESC", allows: textRepertoire)
        default: return nil
        }
    }

    /// VRs whose Value Field holds one Value even when it contains a BACKSLASH (Table 6.2-1:
    /// "shall not be multi-valued").
    static let singleValued: Set<VR> = [.LT, .ST, .UT, .UR]

    /// The Values of a character-string element: the Value Field without its trailing padding
    /// (SPACE, or NULL for UI; PS3.5 6.2), split at BACKSLASH (PS3.5 6.4). DA / TM / DT / UI
    /// Values lose their trailing SPACE too ("may be padded with trailing spaces").
    static func values(of element: DataElement) -> [String] {
        guard element.vr.characterRepertoire != nil, element.sequenceItems == nil else { return [] }
        let data = element.valueData
        guard !data.isEmpty else { return [] }
        let raw = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        var trimmed = Substring(raw)
        while let last = trimmed.last, last == " " || last == "\0" { trimmed = trimmed.dropLast() }
        guard !trimmed.isEmpty else { return [] }
        let parts = singleValued.contains(element.vr) ? [String(trimmed)]
            : trimmed.components(separatedBy: "\\")
        switch element.vr {
        case .DA, .TM, .DT, .UI, .AE, .CS, .PN, .UC:
            // Trailing (and for AE / CS leading) spaces are not significant.
            return parts.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \0")) }
        default:
            return parts
        }
    }

    /// The number of Values (PS3.5 6.4): backslash-delimited Values of a character string, or
    /// Value Length / element size of a fixed-size binary VR; `nil` for VRs whose VM is 1 by
    /// definition (OB, OW, SQ, …) or when the length is not a whole number of elements.
    static func valueCount(of element: DataElement) -> Int? {
        let size: Int
        switch element.vr {
        case .US, .SS: size = 2
        case .UL, .SL, .FL, .AT: size = 4
        case .FD, .SV, .UV: size = 8
        default:
            if element.vr.characterRepertoire != nil && element.sequenceItems == nil {
                return values(of: element).count
            }
            return nil
        }
        let length = element.valueData.count
        guard length % size == 0 else { return nil }
        return length / size
    }

    /// A PS3.6 Table 6-1 VM: "1", "1-3", "1-n", "2-2n", "3-3n", "1-n or 1".
    struct ValueMultiplicity {
        let minimum: Int
        let maximum: Int?      // nil = n
        let step: Int          // "2-2n": multiples of 2

        init?(_ text: String) {
            let vm = text.components(separatedBy: " or ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !vm.isEmpty else { return nil }
            let parts = vm.split(separator: "-").map(String.init)
            guard let lo = Int(parts[0]) else { return nil }
            if parts.count == 1 {
                minimum = lo; maximum = lo; step = 1
            } else if parts.count == 2 {
                let hi = parts[1]
                if let n = Int(hi) {
                    minimum = lo; maximum = n; step = 1
                } else if hi == "n" {
                    minimum = lo; maximum = nil; step = 1
                } else if hi.hasSuffix("n"), let k = Int(hi.dropLast()) {
                    minimum = lo; maximum = nil; step = k
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }

        func allows(_ count: Int) -> Bool {
            if count < minimum { return false }
            if let maximum, count > maximum { return false }
            return count % step == 0
        }
    }
}

/// Validation issue
public struct ValidationIssue {
    public enum Level: String, Codable {
        case error
        case warning
    }
    
    public let level: Level
    public let message: String
    public let tag: Tag?
    
    public init(level: Level, message: String, tag: Tag?) {
        self.level = level
        self.message = message
        self.tag = tag
    }
    
    var tagString: String? {
        tag?.description
    }
}

/// Validation result for a single file
public struct ValidationResult {
    public let filePath: String
    public let isValid: Bool
    public let errors: [ValidationIssue]
    public let warnings: [ValidationIssue]
    
    public init(filePath: String, isValid: Bool, errors: [ValidationIssue], warnings: [ValidationIssue]) {
        self.filePath = filePath
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

/// IOD-specific validator protocol
protocol IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue])
}

// MARK: - IOD attribute requirement tables (PS3.3 2026a)

/// The attribute Types the validator enforces, per PS3.5 2026a 7.4:
///
/// - 7.4.1 Type 1: "shall be included … The Length of the Value Field shall not be
///   zero. Absence of a valid Value in a Type 1 Data Element is a protocol violation."
/// - 7.4.3 Type 2: "shall be included … it is permissible that if a Value for a
///   Type 2 Data Element is unknown it can be encoded with zero Value Length and no
///   Value … their absence is a protocol violation."
///
/// Both absences are therefore errors; only a Type 1 may additionally be rejected
/// for being empty.
public enum IODAttributeType: String, Sendable {
    case type1 = "1"
    case type2 = "2"
}

/// One row of an IOD's requirement table: an attribute the IOD's Mandatory modules
/// make Type 1 or Type 2, with the PS3.3 table it was read from.
public struct IODAttributeRequirement: Sendable {
    public let tag: Tag
    public let type: IODAttributeType
    public let name: String
    /// PS3.3 module/table label, e.g. "C.7.1.1 Patient (Table C.7-1)".
    public let module: String

    public init(_ tag: Tag, _ type: IODAttributeType, _ name: String, _ module: String) {
        self.tag = tag
        self.type = type
        self.name = name
        self.module = module
    }
}

/// Type 1/2 attributes of the Mandatory modules of every IOD the validator knows,
/// keyed by SOP Class UID, read from the PS3.3 2026a IOD module tables (A.x-1) and
/// the module attribute tables they reference. Conditionally included modules and
/// 1C/2C attributes are handled in the per-IOD validators, where the condition can
/// be evaluated against the data set.
public enum IODRequirementTables {

    // MARK: Shared modules

    /// C.7.1.1 Patient Module, Table C.7-1.
    static let patient: [IODAttributeRequirement] = [
        .init(.patientName,      .type2, "Patient's Name",       "C.7.1.1 Patient (Table C.7-1)"),
        .init(.patientID,        .type2, "Patient ID",           "C.7.1.1 Patient (Table C.7-1)"),
        .init(.patientBirthDate, .type2, "Patient's Birth Date", "C.7.1.1 Patient (Table C.7-1)"),
        .init(.patientSex,       .type2, "Patient's Sex",        "C.7.1.1 Patient (Table C.7-1)"),
    ]

    /// C.7.2.1 General Study Module, Table C.7-3.
    static let generalStudy: [IODAttributeRequirement] = [
        .init(.studyInstanceUID,       .type1, "Study Instance UID",         "C.7.2.1 General Study (Table C.7-3)"),
        .init(.studyDate,              .type2, "Study Date",                 "C.7.2.1 General Study (Table C.7-3)"),
        .init(.studyTime,              .type2, "Study Time",                 "C.7.2.1 General Study (Table C.7-3)"),
        .init(.referringPhysicianName, .type2, "Referring Physician's Name", "C.7.2.1 General Study (Table C.7-3)"),
        .init(.studyID,                .type2, "Study ID",                   "C.7.2.1 General Study (Table C.7-3)"),
        .init(.accessionNumber,        .type2, "Accession Number",           "C.7.2.1 General Study (Table C.7-3)"),
    ]

    /// C.7.3.1 General Series Module, Table C.7-5a (Modality 1, Series Instance UID 1,
    /// Series Number 2). Laterality 2C and Patient Position 2C are conditional.
    static let generalSeries: [IODAttributeRequirement] = [
        .init(.modality,          .type1, "Modality",            "C.7.3.1 General Series (Table C.7-5a)"),
        .init(.seriesInstanceUID, .type1, "Series Instance UID", "C.7.3.1 General Series (Table C.7-5a)"),
        .init(.seriesNumber,      .type2, "Series Number",       "C.7.3.1 General Series (Table C.7-5a)"),
    ]

    /// C.7.3.1 General Series for the Secondary Capture IOD: Table C.8-24 SC Equipment
    /// makes Modality Type 3 ("This type definition shall override the definition in
    /// the C.7.3.1"), so only the UID and number remain required.
    static let generalSeriesSC: [IODAttributeRequirement] = [
        .init(.seriesInstanceUID, .type1, "Series Instance UID", "C.7.3.1 General Series (Table C.7-5a)"),
        .init(.seriesNumber,      .type2, "Series Number",       "C.7.3.1 General Series (Table C.7-5a)"),
    ]

    /// C.7.4.1 Frame of Reference Module, Table C.7-6.
    static let frameOfReference: [IODAttributeRequirement] = [
        .init(.frameOfReferenceUID,       .type1, "Frame of Reference UID",       "C.7.4.1 Frame of Reference (Table C.7-6)"),
        .init(.positionReferenceIndicator, .type2, "Position Reference Indicator", "C.7.4.1 Frame of Reference (Table C.7-6)"),
    ]

    /// C.7.5.1 General Equipment Module, Table C.7-8 (Manufacturer is its only Type 2).
    static let generalEquipment: [IODAttributeRequirement] = [
        .init(.manufacturer, .type2, "Manufacturer", "C.7.5.1 General Equipment (Table C.7-8)"),
    ]

    /// C.7.6.1 General Image Module, Table C.7-9 (Instance Number 2; Patient
    /// Orientation 2C and Content Date/Time 2C are conditional).
    static let generalImage: [IODAttributeRequirement] = [
        .init(.instanceNumber, .type2, "Instance Number", "C.7.6.1 General Image (Table C.7-9)"),
    ]

    /// C.7.6.2 Image Plane Module, Table C.7-10.
    static let imagePlane: [IODAttributeRequirement] = [
        .init(.pixelSpacing,            .type1, "Pixel Spacing",               "C.7.6.2 Image Plane (Table C.7-10)"),
        .init(.imageOrientationPatient, .type1, "Image Orientation (Patient)", "C.7.6.2 Image Plane (Table C.7-10)"),
        .init(.imagePositionPatient,    .type1, "Image Position (Patient)",    "C.7.6.2 Image Plane (Table C.7-10)"),
        .init(.sliceThickness,          .type2, "Slice Thickness",             "C.7.6.2 Image Plane (Table C.7-10)"),
    ]

    /// C.7.6.3 Image Pixel Module: Table C.7-11b (Pixel Data 1) including Table
    /// C.7-11c Image Pixel Description Macro. Planar Configuration 1C and the Palette
    /// Color LUT 1C rows are conditional.
    static let imagePixel: [IODAttributeRequirement] = [
        .init(.samplesPerPixel,           .type1, "Samples per Pixel",          "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.photometricInterpretation, .type1, "Photometric Interpretation", "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.rows,                      .type1, "Rows",                       "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.columns,                   .type1, "Columns",                    "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.bitsAllocated,             .type1, "Bits Allocated",             "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.bitsStored,                .type1, "Bits Stored",                "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.highBit,                   .type1, "High Bit",                   "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.pixelRepresentation,       .type1, "Pixel Representation",       "C.7.6.3 Image Pixel (Table C.7-11c)"),
        .init(.pixelData,                 .type1, "Pixel Data",                 "C.7.6.3 Image Pixel (Table C.7-11b)"),
    ]

    /// C.12.1 SOP Common Module, Table C.12-1.
    static let sopCommon: [IODAttributeRequirement] = [
        .init(.sopClassUID,    .type1, "SOP Class UID",    "C.12.1 SOP Common (Table C.12-1)"),
        .init(.sopInstanceUID, .type1, "SOP Instance UID", "C.12.1 SOP Common (Table C.12-1)"),
    ]

    // MARK: Modality-specific modules

    /// C.8.2.1 CT Image Module, Table C.8-3 (the pixel-description rows repeat the
    /// Image Pixel ones and are listed once there). Rescale Type is 1C.
    static let ctImageModule: [IODAttributeRequirement] = [
        .init(.imageType,         .type1, "Image Type",         "C.8.2.1 CT Image (Table C.8-3)"),
        .init(.rescaleIntercept,  .type1, "Rescale Intercept",  "C.8.2.1 CT Image (Table C.8-3)"),
        .init(.rescaleSlope,      .type1, "Rescale Slope",      "C.8.2.1 CT Image (Table C.8-3)"),
        .init(.kvp,               .type2, "KVP",                "C.8.2.1 CT Image (Table C.8-3)"),
        .init(.acquisitionNumber, .type2, "Acquisition Number", "C.8.2.1 CT Image (Table C.8-3)"),
    ]

    /// C.8.3.1 MR Image Module, Table C.8-4. Repetition Time 2C, Inversion Time 2C
    /// and Trigger Time 2C are conditional.
    static let mrImageModule: [IODAttributeRequirement] = [
        .init(.imageType,         .type1, "Image Type",          "C.8.3.1 MR Image (Table C.8-4)"),
        .init(.scanningSequence,  .type1, "Scanning Sequence",   "C.8.3.1 MR Image (Table C.8-4)"),
        .init(.sequenceVariant,   .type1, "Sequence Variant",    "C.8.3.1 MR Image (Table C.8-4)"),
        .init(.scanOptions,       .type2, "Scan Options",        "C.8.3.1 MR Image (Table C.8-4)"),
        .init(.mrAcquisitionType, .type2, "MR Acquisition Type", "C.8.3.1 MR Image (Table C.8-4)"),
        .init(.echoTime,          .type2, "Echo Time",           "C.8.3.1 MR Image (Table C.8-4)"),
        .init(.echoTrainLength,   .type2, "Echo Train Length",   "C.8.3.1 MR Image (Table C.8-4)"),
    ]

    /// C.8.1.1 CR Series Module, Table C.8-1.
    static let crSeries: [IODAttributeRequirement] = [
        .init(.bodyPartExamined, .type2, "Body Part Examined", "C.8.1.1 CR Series (Table C.8-1)"),
        .init(Tag(group: 0x0018, element: 0x5101), .type2, "View Position", "C.8.1.1 CR Series (Table C.8-1)"),
    ]

    /// C.8.1.2 CR Image Module, Table C.8-2 (Photometric Interpretation 1, listed
    /// with Image Pixel; everything else Type 3).
    static let crImageModule: [IODAttributeRequirement] = []

    /// C.8.5.6 US Image Module, Table C.8-18 (pixel-description rows are listed with
    /// Image Pixel; Image Type is Type 2 here). Frame Increment Pointer 1C is conditional.
    static let usImageModule: [IODAttributeRequirement] = [
        .init(.imageType, .type2, "Image Type", "C.8.5.6 US Image (Table C.8-18)"),
    ]

    /// C.8.6.1 SC Equipment Module, Table C.8-24.
    static let scEquipment: [IODAttributeRequirement] = [
        .init(.conversionType, .type1, "Conversion Type", "C.8.6.1 SC Equipment (Table C.8-24)"),
    ]

    // MARK: Presentation State modules

    /// C.11.9 Presentation Series Module, Table C.11.9-1 (Modality 1, Enumerated Value PR).
    static let presentationSeries: [IODAttributeRequirement] = [
        .init(.modality, .type1, "Modality", "C.11.9 Presentation Series (Table C.11.9-1)"),
    ]

    /// C.11.10 Presentation State Identification Module, Table C.11.10-1, including
    /// the Content Identification Macro, Table 10-12. Content Creator's Name (0070,0084)
    /// is Type 3 (Content Creator Macro, Table 10.9.3-1, included by Table 10-12), so it is
    /// not listed.
    static let presentationStateIdentification: [IODAttributeRequirement] = [
        .init(.presentationCreationDate, .type1, "Presentation Creation Date", "C.11.10 Presentation State Identification (Table C.11.10-1)"),
        .init(.presentationCreationTime, .type1, "Presentation Creation Time", "C.11.10 Presentation State Identification (Table C.11.10-1)"),
        .init(.instanceNumber,           .type1, "Instance Number",            "C.11.10 Presentation State Identification (Table 10-12)"),
        .init(.contentLabel,             .type1, "Content Label",              "C.11.10 Presentation State Identification (Table 10-12)"),
        .init(.contentDescription,       .type2, "Content Description",        "C.11.10 Presentation State Identification (Table 10-12)"),
    ]

    /// C.11.11 Presentation State Relationship Module, Table C.11.11-1 including the
    /// Presentation State Relationship Macro, Table C.11.11-1b.
    static let presentationStateRelationship: [IODAttributeRequirement] = [
        .init(.referencedSeriesSequence, .type1, "Referenced Series Sequence", "C.11.11 Presentation State Relationship (Table C.11.11-1b)"),
    ]

    /// Table C.11.11-1b, per Item of Referenced Series Sequence.
    static let presentationStateRelationshipItem: [IODAttributeRequirement] = [
        .init(.seriesInstanceUID,       .type1, "Series Instance UID",       "C.11.11 Presentation State Relationship (Table C.11.11-1b, Item)"),
        .init(.referencedImageSequence, .type1, "Referenced Image Sequence", "C.11.11 Presentation State Relationship (Table C.11.11-1b, Item)"),
    ]

    /// C.10.4 Displayed Area Module, Table C.10-4.
    static let displayedArea: [IODAttributeRequirement] = [
        .init(.displayedAreaSelectionSequence, .type1, "Displayed Area Selection Sequence", "C.10.4 Displayed Area (Table C.10-4)"),
    ]

    /// Table C.10-4, per Item of Displayed Area Selection Sequence.
    static let displayedAreaItem: [IODAttributeRequirement] = [
        .init(.displayedAreaTopLeftHandCorner,     .type1, "Displayed Area Top Left Hand Corner",     "C.10.4 Displayed Area (Table C.10-4, Item)"),
        .init(.displayedAreaBottomRightHandCorner, .type1, "Displayed Area Bottom Right Hand Corner", "C.10.4 Displayed Area (Table C.10-4, Item)"),
        .init(.presentationSizeMode,               .type1, "Presentation Size Mode",                  "C.10.4 Displayed Area (Table C.10-4, Item)"),
    ]

    /// C.7.9 Palette Color Lookup Table Module (Mandatory in Table A.33.3-1): the
    /// descriptors and data are Type 1 in Table C.7-11c when the module is present.
    static let paletteColorLUT: [IODAttributeRequirement] = [
        .init(.redPaletteColorLookupTableDescriptor,   .type1, "Red Palette Color LUT Descriptor",   "C.7.9 Palette Color Lookup Table"),
        .init(.greenPaletteColorLookupTableDescriptor, .type1, "Green Palette Color LUT Descriptor", "C.7.9 Palette Color Lookup Table"),
        .init(.bluePaletteColorLookupTableDescriptor,  .type1, "Blue Palette Color LUT Descriptor",  "C.7.9 Palette Color Lookup Table"),
        .init(.redPaletteColorLookupTableData,         .type1, "Red Palette Color LUT Data",         "C.7.9 Palette Color Lookup Table"),
        .init(.greenPaletteColorLookupTableData,       .type1, "Green Palette Color LUT Data",       "C.7.9 Palette Color Lookup Table"),
        .init(.bluePaletteColorLookupTableData,        .type1, "Blue Palette Color LUT Data",        "C.7.9 Palette Color Lookup Table"),
    ]

    /// C.11.15 ICC Profile Module, Table C.11.15-1.
    static let iccProfile: [IODAttributeRequirement] = [
        .init(.iccProfile, .type1, "ICC Profile", "C.11.15 ICC Profile (Table C.11.15-1)"),
    ]

    // MARK: Structured Report modules

    /// C.17.1 SR Document Series Module, Table C.17-1 (Modality 1, Enumerated Value SR).
    static let srDocumentSeries: [IODAttributeRequirement] = [
        .init(.modality,          .type1, "Modality",            "C.17.1 SR Document Series (Table C.17-1)"),
        .init(.seriesInstanceUID, .type1, "Series Instance UID", "C.17.1 SR Document Series (Table C.17-1)"),
        .init(.seriesNumber,      .type1, "Series Number",       "C.17.1 SR Document Series (Table C.17-1)"),
        .init(.referencedPerformedProcedureStepSequence, .type2, "Referenced Performed Procedure Step Sequence", "C.17.1 SR Document Series (Table C.17-1)"),
    ]

    /// C.17.2 SR Document General Module, Table C.17-2. Verifying Observer Sequence
    /// 1C is conditional on Verification Flag.
    static let srDocumentGeneral: [IODAttributeRequirement] = [
        .init(.instanceNumber,   .type1, "Instance Number",   "C.17.2 SR Document General (Table C.17-2)"),
        .init(.completionFlag,   .type1, "Completion Flag",   "C.17.2 SR Document General (Table C.17-2)"),
        .init(.verificationFlag, .type1, "Verification Flag", "C.17.2 SR Document General (Table C.17-2)"),
        .init(.contentDate,      .type1, "Content Date",      "C.17.2 SR Document General (Table C.17-2)"),
        .init(.contentTime,      .type1, "Content Time",      "C.17.2 SR Document General (Table C.17-2)"),
        .init(Tag(group: 0x0040, element: 0xA372), .type2, "Performed Procedure Code Sequence", "C.17.2 SR Document General (Table C.17-2)"),
    ]

    /// C.17.3 SR Document Content Module, Table C.17-4: the Document Content Macro
    /// (Table C.17-5) with Value Type CONTAINER and the Container Macro (Table C.18.8-1).
    /// Concept Name Code Sequence is Type 1C in Table C.17-5 ("Required if Value Type
    /// (0040,A040) is CONTAINER and a heading is present, or this is the Root Content
    /// Item"); ``StructuredReportValidator`` checks it with that condition.
    static let srDocumentContent: [IODAttributeRequirement] = [
        .init(.valueType,               .type1, "Value Type",                 "C.17.3 SR Document Content (Table C.17-5)"),
        .init(.continuityOfContent,     .type1, "Continuity of Content",      "C.17.3 SR Document Content (Table C.18.8-1)"),
    ]

    /// C.17.6.1 Key Object Document Series Module, Table C.17.6-1 (Modality 1,
    /// Enumerated Value KO).
    static let keyObjectDocumentSeries: [IODAttributeRequirement] = [
        .init(.modality,          .type1, "Modality",            "C.17.6.1 Key Object Document Series (Table C.17.6-1)"),
        .init(.seriesInstanceUID, .type1, "Series Instance UID", "C.17.6.1 Key Object Document Series (Table C.17.6-1)"),
        .init(.seriesNumber,      .type1, "Series Number",       "C.17.6.1 Key Object Document Series (Table C.17.6-1)"),
        .init(.referencedPerformedProcedureStepSequence, .type2, "Referenced Performed Procedure Step Sequence", "C.17.6.1 Key Object Document Series (Table C.17.6-1)"),
    ]

    /// C.17.6.2 Key Object Document Module, Table C.17.6-2.
    static let keyObjectDocument: [IODAttributeRequirement] = [
        .init(.instanceNumber, .type1, "Instance Number", "C.17.6.2 Key Object Document (Table C.17.6-2)"),
        .init(.contentDate,    .type1, "Content Date",    "C.17.6.2 Key Object Document (Table C.17.6-2)"),
        .init(.contentTime,    .type1, "Content Time",    "C.17.6.2 Key Object Document (Table C.17.6-2)"),
        .init(Tag(group: 0x0040, element: 0xA375), .type1, "Current Requested Procedure Evidence Sequence", "C.17.6.2 Key Object Document (Table C.17.6-2)"),
    ]

    // MARK: Per-IOD composition (the Mandatory rows of Tables A.x-1)

    /// Table A.3-1 CT Image IOD Modules (M rows): Patient, General Study, General
    /// Series, Frame of Reference, General Equipment, General Acquisition (all Type 3),
    /// General Image, Image Plane, Image Pixel, CT Image, SOP Common.
    public static let ctImage: [IODAttributeRequirement] =
        patient + generalStudy + generalSeries + frameOfReference + generalEquipment
        + generalImage + imagePlane + imagePixel + ctImageModule + sopCommon

    /// Table A.4-1 MR Image IOD Modules (M rows): as CT with MR Image (C.8.3.1).
    public static let mrImage: [IODAttributeRequirement] =
        patient + generalStudy + generalSeries + frameOfReference + generalEquipment
        + generalImage + imagePlane + imagePixel + mrImageModule + sopCommon

    /// Table A.2-1 Computed Radiography Image IOD Modules (M rows): Patient, General
    /// Study, General Series, CR Series, General Equipment, General Acquisition,
    /// General Image, Image Pixel, CR Image, SOP Common (no Frame of Reference, no
    /// Image Plane).
    public static let crImage: [IODAttributeRequirement] =
        patient + generalStudy + generalSeries + crSeries + generalEquipment
        + generalImage + imagePixel + crImageModule + sopCommon

    /// Table A.6-1 Ultrasound Image IOD Modules (M rows): Patient, General Study,
    /// General Series, General Equipment, General Acquisition, General Image, Image
    /// Pixel, US Image, SOP Common (Frame of Reference is U).
    public static let usImage: [IODAttributeRequirement] =
        patient + generalStudy + generalSeries + generalEquipment
        + generalImage + imagePixel + usImageModule + sopCommon

    /// Table A.8-1 Secondary Capture Image IOD Modules (M rows): Patient, General
    /// Study, General Series, SC Equipment, General Acquisition, General Image, Image
    /// Pixel, SC Image (all Type 3), SOP Common. General Equipment is U and Frame of
    /// Reference is C (evaluated in the validator).
    public static let secondaryCaptureImage: [IODAttributeRequirement] =
        patient + generalStudy + generalSeriesSC + scEquipment
        + generalImage + imagePixel + sopCommon

    /// Table A.33.1-1 Grayscale Softcopy Presentation State IOD Modules (M rows):
    /// Patient, General Study, General Series, Presentation Series, General Equipment,
    /// Presentation State Identification, Presentation State Relationship,
    /// Presentation State Shutter (1C only), Presentation State Mask (1C only),
    /// Displayed Area, Softcopy Presentation LUT (either-or 1C, evaluated in the
    /// validator), SOP Common.
    public static let grayscaleSoftcopyPresentationState: [IODAttributeRequirement] =
        patient + generalStudy + generalSeries + presentationSeries + generalEquipment
        + presentationStateIdentification + presentationStateRelationship
        + displayedArea + sopCommon

    /// Table A.33.3-1 Pseudo-Color Softcopy Presentation State IOD Modules (M rows):
    /// the grayscale set without Softcopy Presentation LUT, plus Palette Color Lookup
    /// Table and ICC Profile.
    public static let pseudoColorSoftcopyPresentationState: [IODAttributeRequirement] =
        patient + generalStudy + generalSeries + presentationSeries + generalEquipment
        + presentationStateIdentification + presentationStateRelationship
        + displayedArea + paletteColorLUT + iccProfile + sopCommon

    /// Tables A.35.1-1 Basic Text SR, A.35.2-1 Enhanced SR and A.35.3-1
    /// Comprehensive SR IOD Modules (M rows): Patient, General Study, SR Document
    /// Series, General Equipment, SR Document General, SR Document Content, SOP Common.
    public static let structuredReport: [IODAttributeRequirement] =
        patient + generalStudy + srDocumentSeries + generalEquipment
        + srDocumentGeneral + srDocumentContent + sopCommon

    /// Table A.35.4-1 Key Object Selection Document IOD Modules (M rows): Patient,
    /// General Study, Key Object Document Series, General Equipment, Key Object
    /// Document, SR Document Content, SOP Common.
    public static let keyObjectSelectionDocument: [IODAttributeRequirement] =
        patient + generalStudy + keyObjectDocumentSeries + generalEquipment
        + keyObjectDocument + srDocumentContent + sopCommon

    /// SOP Class UID → requirement rows.
    public static let bySOPClassUID: [String: [IODAttributeRequirement]] = {
        var t: [String: [IODAttributeRequirement]] = [
            "1.2.840.10008.5.1.4.1.1.2":      ctImage,                                 // CT Image Storage
            "1.2.840.10008.5.1.4.1.1.4":      mrImage,                                 // MR Image Storage
            "1.2.840.10008.5.1.4.1.1.1":      crImage,                                 // CR Image Storage
            "1.2.840.10008.5.1.4.1.1.6.1":    usImage,                                 // US Image Storage
            "1.2.840.10008.5.1.4.1.1.7":      secondaryCaptureImage,                   // SC Image Storage
            "1.2.840.10008.5.1.4.1.1.11.1":   grayscaleSoftcopyPresentationState,      // GSPS
            "1.2.840.10008.5.1.4.1.1.11.3":   pseudoColorSoftcopyPresentationState,    // Pseudo-Color PS
            "1.2.840.10008.5.1.4.1.1.88.59":  keyObjectSelectionDocument,              // KOS
        ]
        for uid in SRDocumentType.allSOPClassUIDs where t[uid] == nil {
            t[uid] = structuredReport
        }
        return t
    }()
}

// MARK: - Requirement checking

extension IODValidator {

    /// Reports every row of `requirements` that the data set violates: a missing
    /// Type 1 or Type 2 attribute (PS3.5 7.4.1 / 7.4.3: absence is a protocol
    /// violation) and an empty Type 1 attribute (PS3.5 7.4.1: "The Length of the
    /// Value Field shall not be zero").
    func checkRequirements(
        _ requirements: [IODAttributeRequirement],
        in dataSet: DataSet,
        iod: String,
        errors: inout [ValidationIssue]
    ) {
        for req in requirements {
            guard let element = dataSet[req.tag] else {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "\(iod): Missing Type \(req.type.rawValue) attribute \(req.name) "
                        + "[PS3.3 \(req.module); PS3.5 7.4.\(req.type == .type1 ? "1" : "3")]",
                    tag: req.tag
                ))
                continue
            }
            if req.type == .type1 && Self.isEmpty(element) {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "\(iod): Type 1 attribute \(req.name) is empty "
                        + "[PS3.3 \(req.module); PS3.5 7.4.1]",
                    tag: req.tag
                ))
            }
        }
    }

    /// The same check inside every Item of a sequence.
    func checkItemRequirements(
        _ requirements: [IODAttributeRequirement],
        inItemsOf sequenceTag: Tag,
        sequenceName: String,
        dataSet: DataSet,
        iod: String,
        errors: inout [ValidationIssue]
    ) {
        guard let items = dataSet[sequenceTag]?.sequenceItems else { return }
        for (index, item) in items.enumerated() {
            let itemSet = DataSet(elements: item.allElements)
            var itemErrors: [ValidationIssue] = []
            checkRequirements(requirements, in: itemSet,
                              iod: "\(iod): \(sequenceName) Item \(index + 1)", errors: &itemErrors)
            errors.append(contentsOf: itemErrors)
        }
    }

    /// Enforces an Enumerated Value of a Type 1 CS attribute: a value outside the
    /// list is an error, not a warning (PS3.5 6.1 — an Enumerated Value is the only
    /// permitted set of values).
    func checkEnumeratedValue(
        _ tag: Tag,
        name: String,
        allowed: [String],
        module: String,
        dataSet: DataSet,
        iod: String,
        errors: inout [ValidationIssue]
    ) {
        guard let raw = dataSet.string(for: tag)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }   // absence/emptiness is reported by the Type check
        if !allowed.contains(raw) {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): \(name) must be \(allowed.joined(separator: " or ")) "
                    + "(Enumerated Value, PS3.3 \(module)); found '\(raw)'",
                tag: tag
            ))
        }
    }

    static func isEmpty(_ element: DataElement) -> Bool {
        if let items = element.sequenceItems { return items.isEmpty }
        return element.length == 0 || element.valueData.isEmpty
    }
}

// MARK: - Per-IOD validators

/// CT Image Storage validator — Table A.3-1.
struct CTImageStorageValidator: IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let iod = "CT Image Storage"
        checkRequirements(IODRequirementTables.ctImage, in: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkImagePixelConditionals(dataSet: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkPatientPositionCTMR(dataSet: dataSet, iod: iod, errors: &errors)

        if let raw = dataSet.string(for: .modality),
           Modality.normalized(raw) != Modality.ct {
            errors.append(ValidationIssue(
                level: .error,
                message: "CT Image Storage: Modality must be 'CT'",
                tag: .modality
            ))
        }
    }
}

/// MR Image Storage validator — Table A.4-1.
struct MRImageStorageValidator: IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let iod = "MR Image Storage"
        checkRequirements(IODRequirementTables.mrImage, in: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkImagePixelConditionals(dataSet: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkPatientPositionCTMR(dataSet: dataSet, iod: iod, errors: &errors)

        // Table C.8-4: Repetition Time 2C "Required if Sequence Variant (0018,0021) is
        // SK or if Scanning Sequence (0018,0020) is not EP"; Inversion Time 2C
        // "Required if Scanning Sequence (0018,0020) has Values of IR".
        let scanning = (dataSet.strings(for: .scanningSequence) ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        let variant = (dataSet.strings(for: .sequenceVariant) ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        if (variant.contains("SK") || !scanning.contains("EP")) && dataSet[.repetitionTime] == nil {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Type 2C attribute Repetition Time (required when Sequence Variant is SK or Scanning Sequence is not EP) [PS3.3 C.8.3.1 MR Image (Table C.8-4); PS3.5 7.4.4]",
                tag: .repetitionTime
            ))
        }
        if scanning.contains("IR") && dataSet[.inversionTime] == nil {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Type 2C attribute Inversion Time (required when Scanning Sequence includes IR) [PS3.3 C.8.3.1 MR Image (Table C.8-4); PS3.5 7.4.4]",
                tag: .inversionTime
            ))
        }

        if let raw = dataSet.string(for: .modality),
           Modality.normalized(raw) != Modality.mr {
            errors.append(ValidationIssue(
                level: .error,
                message: "MR Image Storage: Modality must be 'MR'",
                tag: .modality
            ))
        }
    }
}

/// CR Image Storage validator — Table A.2-1.
struct CRImageStorageValidator: IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let iod = "Computed Radiography Image Storage"   // PS3.6 Table A-1
        checkRequirements(IODRequirementTables.crImage, in: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkImagePixelConditionals(dataSet: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkPatientOrientation(dataSet: dataSet, iod: iod, imagePlaneOptional: false, errors: &errors)

        if let raw = dataSet.string(for: .modality),
           Modality.normalized(raw) != Modality.cr {
            errors.append(ValidationIssue(
                level: .error,
                message: "CR Image Storage: Modality must be 'CR'",
                tag: .modality
            ))
        }
    }
}

/// Ultrasound Image Storage validator — Table A.6-1.
struct USImageStorageValidator: IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let iod = "Ultrasound Image Storage"             // PS3.6 Table A-1
        checkRequirements(IODRequirementTables.usImage, in: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkImagePixelConditionals(dataSet: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkPatientOrientation(dataSet: dataSet, iod: iod, imagePlaneOptional: false, errors: &errors)

        // Table C.8-18: Frame Increment Pointer 1C "Required if Number of Frames is present".
        if dataSet[.numberOfFrames] != nil && dataSet[.frameIncrementPointer] == nil {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Type 1C attribute Frame Increment Pointer (required when Number of Frames is present) [PS3.3 C.8.5.6 US Image (Table C.8-18); PS3.5 7.4.2]",
                tag: .frameIncrementPointer
            ))
        }

        if let raw = dataSet.string(for: .modality),
           Modality.normalized(raw) != Modality.us {
            errors.append(ValidationIssue(
                level: .error,
                message: "US Image Storage: Modality must be 'US'",
                tag: .modality
            ))
        }
    }
}

/// Secondary Capture Image Storage validator — Table A.8-1.
///
/// Modality is not required: Table C.8-24 SC Equipment makes it Type 3 and states
/// that this overrides the General Series definition.
struct SecondaryCaptureImageStorageValidator: IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let iod = "Secondary Capture Image Storage"
        checkRequirements(IODRequirementTables.secondaryCaptureImage, in: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkImagePixelConditionals(dataSet: dataSet, iod: iod, errors: &errors)
        ImageIODConditionals.checkPatientOrientation(dataSet: dataSet, iod: iod, imagePlaneOptional: true, errors: &errors)

        // Table A.8-1: Frame of Reference "C - Required if Image Position (Patient)
        // (0020,0032) or Image Orientation (Patient) (0020,0037) are present."
        if dataSet[.imagePositionPatient] != nil || dataSet[.imageOrientationPatient] != nil {
            checkRequirements(IODRequirementTables.frameOfReference, in: dataSet, iod: iod, errors: &errors)
        }
    }
}

/// Conditions shared by the image IODs.
enum ImageIODConditionals {

    /// Table C.7-11c: Planar Configuration 1C "Required if Samples per Pixel
    /// (0028,0002) has a Value greater than 1"; the six Palette Color LUT rows are 1C
    /// "Required if Photometric Interpretation (0028,0004) has a Value of PALETTE COLOR".
    static func checkImagePixelConditionals(dataSet: DataSet, iod: String, errors: inout [ValidationIssue]) {
        if let spp = dataSet.uint16(for: .samplesPerPixel), spp > 1, dataSet[.planarConfiguration] == nil {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Type 1C attribute Planar Configuration (required when Samples per Pixel > 1) [PS3.3 C.7.6.3 Image Pixel (Table C.7-11c); PS3.5 7.4.2]",
                tag: .planarConfiguration
            ))
        }
        if dataSet.string(for: .photometricInterpretation)?.trimmingCharacters(in: .whitespaces) == "PALETTE COLOR" {
            for req in IODRequirementTables.paletteColorLUT where dataSet[req.tag] == nil {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "\(iod): Missing Type 1C attribute \(req.name) (required for PALETTE COLOR) [PS3.3 C.7.6.3 Image Pixel (Table C.7-11c); PS3.5 7.4.2]",
                    tag: req.tag
                ))
            }
        }
    }

    /// Table C.7-5a: Patient Position 2C "Required for images where Patient
    /// Orientation Code Sequence (0054,0410) is not present and whose SOP Class UID
    /// (0008,0016) is one of … CT Image Storage, MR Image Storage …".
    static func checkPatientPositionCTMR(dataSet: DataSet, iod: String, errors: inout [ValidationIssue]) {
        let patientOrientationCodeSequence = Tag(group: 0x0054, element: 0x0410)
        if dataSet[patientOrientationCodeSequence] == nil && dataSet[.patientPosition] == nil {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Type 2C attribute Patient Position (required for CT/MR when Patient Orientation Code Sequence is absent) [PS3.3 C.7.3.1 General Series (Table C.7-5a); PS3.5 7.4.4]",
                tag: .patientPosition
            ))
        }
    }

    /// Table C.7-9: Patient Orientation 2C "Required if image does not require Image
    /// Orientation (Patient) (0020,0037) and Image Position (Patient) (0020,0032) …".
    /// IODs without a Mandatory Image Plane module do not require them, so the
    /// attribute is required unless (for an IOD where Image Plane is U) both are
    /// present anyway.
    static func checkPatientOrientation(dataSet: DataSet, iod: String, imagePlaneOptional: Bool, errors: inout [ValidationIssue]) {
        let hasPlane = dataSet[.imageOrientationPatient] != nil && dataSet[.imagePositionPatient] != nil
        if imagePlaneOptional && hasPlane { return }
        if dataSet[.patientOrientation] == nil {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Type 2C attribute Patient Orientation (required when the image does not carry Image Orientation/Position (Patient)) [PS3.3 C.7.6.1 General Image (Table C.7-9); PS3.5 7.4.4]",
                tag: .patientOrientation
            ))
        }
    }
}

/// Grayscale Softcopy Presentation State validator — Table A.33.1-1.
struct GrayscaleSoftcopyPresentationStateValidator: IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let iod = "Grayscale Softcopy Presentation State Storage"   // PS3.6 Table A-1
        checkRequirements(IODRequirementTables.grayscaleSoftcopyPresentationState, in: dataSet, iod: iod, errors: &errors)
        PresentationStateConditionals.checkCommon(dataSet: dataSet, iod: iod, validator: self, errors: &errors)

        // Table C.11.6-1 Softcopy Presentation LUT (M): Presentation LUT Sequence 1C
        // "Required if Presentation LUT Shape (2050,0020) is absent" and Presentation
        // LUT Shape 1C "Required if Presentation LUT Sequence (2050,0010) is absent".
        if dataSet[.presentationLUTSequence] == nil && dataSet[.presentationLUTShape] == nil {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Softcopy Presentation LUT: either Presentation LUT Sequence or Presentation LUT Shape is required (Type 1C) [PS3.3 C.11.6 Softcopy Presentation LUT (Table C.11.6-1); PS3.5 7.4.2]",
                tag: .presentationLUTShape
            ))
        }
    }
}

/// Pseudo-Color Softcopy Presentation State validator — Table A.33.3-1: the
/// grayscale modules without Softcopy Presentation LUT, plus Palette Color Lookup
/// Table (C.7.9, M) and ICC Profile (C.11.15, M).
struct PseudoColorSoftcopyPresentationStateValidator: IODValidator {
    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let iod = "Pseudo-Color Softcopy Presentation State Storage"   // PS3.6 Table A-1
        checkRequirements(IODRequirementTables.pseudoColorSoftcopyPresentationState, in: dataSet, iod: iod, errors: &errors)
        PresentationStateConditionals.checkCommon(dataSet: dataSet, iod: iod, validator: self, errors: &errors)
    }
}

enum PresentationStateConditionals {
    /// Table C.11.9-1: Modality Enumerated Value PR; Table C.11.11-1b and Table
    /// C.10-4 Item-level Type 1 rows.
    static func checkCommon(dataSet: DataSet, iod: String, validator: some IODValidator, errors: inout [ValidationIssue]) {
        validator.checkEnumeratedValue(
            .modality, name: "Modality", allowed: ["PR"],
            module: "C.11.9 Presentation Series (Table C.11.9-1)",
            dataSet: dataSet, iod: iod, errors: &errors)
        validator.checkItemRequirements(
            IODRequirementTables.presentationStateRelationshipItem,
            inItemsOf: .referencedSeriesSequence, sequenceName: "Referenced Series Sequence",
            dataSet: dataSet, iod: iod, errors: &errors)
        validator.checkItemRequirements(
            IODRequirementTables.displayedAreaItem,
            inItemsOf: .displayedAreaSelectionSequence, sequenceName: "Displayed Area Selection Sequence",
            dataSet: dataSet, iod: iod, errors: &errors)
    }
}

/// Structured Report validator — Tables A.35.1-1 / A.35.2-1 / A.35.3-1 (and the
/// other SR Storage SOP Classes that use the SR Document Series and General
/// modules); Key Object Selection uses Table A.35.4-1.
struct StructuredReportValidator: IODValidator {
    static let keyObjectSelectionDocumentUID = "1.2.840.10008.5.1.4.1.1.88.59"

    func validate(dataSet: DataSet, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]) {
        let sopClassUID = dataSet.string(for: .sopClassUID)?.trimmingCharacters(in: .whitespaces) ?? ""
        let isKOS = sopClassUID == Self.keyObjectSelectionDocumentUID
        // Message prefix: the SOP Class name of PS3.6 2026a Table A-1 ("Key Object Selection
        // Document Storage", "Basic Text SR Storage", ...); PS3.3 A.35's title when the data set
        // carries no SR SOP Class.
        let iod: String
        if isKOS {
            iod = "Key Object Selection Document Storage"
        } else if SRDocumentType.isSRDocument(sopClassUID: sopClassUID),
                  let name = UIDDictionary.lookup(uid: sopClassUID)?.name {
            iod = name
        } else {
            iod = "Structured Report Document"
        }

        if isKOS {
            checkRequirements(IODRequirementTables.keyObjectSelectionDocument, in: dataSet, iod: iod, errors: &errors)
            // Table C.17.6-1: Modality Enumerated Value KO.
            checkEnumeratedValue(.modality, name: "Modality", allowed: ["KO"],
                                 module: "C.17.6.1 Key Object Document Series (Table C.17.6-1)",
                                 dataSet: dataSet, iod: iod, errors: &errors)
        } else {
            checkRequirements(IODRequirementTables.structuredReport, in: dataSet, iod: iod, errors: &errors)
            // Table C.17-1: Modality Enumerated Value SR.
            checkEnumeratedValue(.modality, name: "Modality", allowed: ["SR"],
                                 module: "C.17.1 SR Document Series (Table C.17-1)",
                                 dataSet: dataSet, iod: iod, errors: &errors)
            // Table C.17-2: Verifying Observer Sequence 1C "Required if Verification
            // Flag (0040,A493) is VERIFIED".
            if dataSet.string(for: .verificationFlag)?.trimmingCharacters(in: .whitespaces) == "VERIFIED",
               dataSet[.verifyingObserverSequence] == nil {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "\(iod): Missing Type 1C attribute Verifying Observer Sequence (required when Verification Flag is VERIFIED) [PS3.3 C.17.2 SR Document General (Table C.17-2); PS3.5 7.4.2]",
                    tag: .verifyingObserverSequence
                ))
            }
        }

        // Table C.17-5: Concept Name Code Sequence is Type 1C, required for the Root Content
        // Item, whose attributes are the top level of the data set (C.17.3).
        let rootConceptName = "Concept Name Code Sequence"
        let rootModule = "C.17.3 SR Document Content (Table C.17-5)"
        if let element = dataSet[.conceptNameCodeSequence] {
            if Self.isEmpty(element) {
                errors.append(ValidationIssue(
                    level: .error,
                    message: "\(iod): Type 1C attribute \(rootConceptName) is empty (required for the Root Content Item) [PS3.3 \(rootModule); PS3.5 7.4.2]",
                    tag: .conceptNameCodeSequence))
            }
        } else {
            errors.append(ValidationIssue(
                level: .error,
                message: "\(iod): Missing Type 1C attribute \(rootConceptName) (required for the Root Content Item) [PS3.3 \(rootModule); PS3.5 7.4.2]",
                tag: .conceptNameCodeSequence))
        }

        // C.17.3.1: "The root Content Item is of type CONTAINER".
        checkEnumeratedValue(.valueType, name: "Value Type of the root Content Item", allowed: ["CONTAINER"],
                             module: "C.17.3.1 SR Document Content Tree",
                             dataSet: dataSet, iod: iod, errors: &errors)
    }
}

// MARK: - IOD names by SOP Class (shared by the validator, dicom-validate --iod and the Workshop; D248)

extension DICOMValidator {

    /// The IOD name the validator switches on, per SOP Class UID of PS3.6 2026a Table A-1.
    ///
    /// The IODs are the ones PS3.4 2026a Table B.5-1 assigns to these SOP Classes: PS3.3 2026a
    /// A.2 Computed Radiography Image, A.3 CT Image, A.4 MR Image, A.6 Ultrasound Image,
    /// A.8 Secondary Capture Image, A.33.1 Grayscale Softcopy Presentation State and A.33.3
    /// Pseudo-Color Softcopy Presentation State. The names are the engine's own (`CRImageStorage`,
    /// `USImageStorage`, `GrayscaleSoftcopyPresentationState`, …), not all of them Table A-1
    /// keywords; the SR SOP Classes are not listed here because every one of them (Key Object
    /// Selection included) validates as `StructuredReport` — see ``iodName(forSOPClassUID:)``.
    public static let iodNameBySOPClassUID: [String: String] = [
        "1.2.840.10008.5.1.4.1.1.2": "CTImageStorage",                         // CT Image Storage
        "1.2.840.10008.5.1.4.1.1.4": "MRImageStorage",                         // MR Image Storage
        "1.2.840.10008.5.1.4.1.1.1": "CRImageStorage",                         // Computed Radiography Image Storage
        "1.2.840.10008.5.1.4.1.1.6.1": "USImageStorage",                       // Ultrasound Image Storage
        "1.2.840.10008.5.1.4.1.1.7": "SecondaryCaptureImageStorage",           // Secondary Capture Image Storage
        "1.2.840.10008.5.1.4.1.1.11.1": "GrayscaleSoftcopyPresentationState",  // Grayscale Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.3": "PseudoColorSoftcopyPresentationState", // Pseudo-Color Softcopy Presentation State Storage
    ]

    /// The engine IOD name for a SOP Class UID: ``iodNameBySOPClassUID``, or `StructuredReport`
    /// for every SR SOP Class of ``DICOMCore/SRDocumentType`` (the SR validator branches on the
    /// SOP Class itself); `nil` for an IOD the validator does not implement.
    public static func iodName(forSOPClassUID uid: String) -> String? {
        if let name = iodNameBySOPClassUID[uid] { return name }
        if SRDocumentType.isSRDocument(sopClassUID: uid) { return "StructuredReport" }
        return nil
    }

    /// The SOP Class UID an `--iod` option value names: a UID, or a PS3.6 Table A-1 keyword in
    /// any letter case (`UltrasoundImageStorage`, `ultrasoundimagestorage`); `nil` otherwise.
    public static func sopClassUID(forIODOption value: String) -> String? {
        if let entry = UIDDictionary.lookup(uid: value) { return entry.uid }
        if let entry = UIDDictionary.lookup(keyword: value) { return entry.uid }
        let lower = value.lowercased()
        return UIDDictionary.sopClasses.first { $0.keyword.lowercased() == lower }?.uid
    }

    /// The IOD name to pass as `iod` for an `--iod` option value: a Table A-1 keyword or UID is
    /// mapped through ``iodName(forSOPClassUID:)``; any other value (the engine's short names
    /// `ct`, `mr`, `cr`, `sc`, `gsps`, `sr`, `kos`, or an unsupported IOD, which the engine reports
    /// as "IOD validation not implemented") passes through unchanged. `US` / `us` selects the
    /// Ultrasound Image IOD (the engine's short name for it is `ultrasound`).
    public static func iodName(forIODOption value: String) -> String {
        if value.lowercased() == "us" { return "USImageStorage" }
        guard let uid = sopClassUID(forIODOption: value) else { return value }
        return iodName(forSOPClassUID: uid) ?? value
    }
}
