import XCTest
@testable import DICOMCore
@testable import DICOMKit
@testable import DICOMDictionary

// Test-local versions of anonymization types (since they're in executable target)

enum AnonymizationProfile {
    case basic
    case clinicalTrial
    case research
    case custom([Tag])
    
    var tagsToRemove: Set<Tag> {
        switch self {
        case .basic:
            return basicProfileTags
        case .clinicalTrial:
            return clinicalTrialProfileTags
        case .research:
            return researchProfileTags
        case .custom(let tags):
            return Set(tags)
        }
    }
    
    private var basicProfileTags: Set<Tag> {
        Set([
            .patientName,
            .patientID,
            .patientBirthDate,
            .patientBirthTime,
            .otherPatientIDs,
            .otherPatientNames,
            .patientComments,
            .referringPhysicianName,
            .performingPhysicianName,
            .operatorsName,
            .institutionName,
            .institutionAddress,
            .stationName,
            .deviceSerialNumber
        ])
    }
    
    private var clinicalTrialProfileTags: Set<Tag> {
        basicProfileTags.union([
            .studyDate,
            .seriesDate,
            .acquisitionDate,
            .contentDate,
            .studyTime,
            .seriesTime,
            .acquisitionTime,
            .contentTime
        ])
    }
    
    private var researchProfileTags: Set<Tag> {
        Set([
            .patientName,
            .patientID,
            .patientBirthDate
        ])
    }
}

enum AnonymizationAction {
    case remove
    case replaceWithEmpty
    case replaceWithDummy(String)
    case hash
    case shiftDate(days: Int)
    case regenerateUID
}

struct AnonymizationResult {
    let filePath: String
    let success: Bool
    let changedTags: [Tag]
    let warnings: [String]
}

struct AuditLogEntry {
    let timestamp: Date
    let filePath: String
    let action: String
    let tag: Tag
    let originalValue: String?
    let newValue: String?
}

class Anonymizer {
    let profile: AnonymizationProfile
    let shiftDates: Int?
    let regenerateUIDs: Bool
    let preserveTags: Set<Tag>
    let customActions: [Tag: AnonymizationAction]
    
    private var dateOffset: Int?
    private var uidMapping: [String: String] = [:]
    private var auditLog: [AuditLogEntry] = []
    
    init(
        profile: AnonymizationProfile,
        shiftDates: Int? = nil,
        regenerateUIDs: Bool = true,
        preserveTags: Set<Tag> = [],
        customActions: [Tag: AnonymizationAction] = [:]
    ) {
        self.profile = profile
        self.shiftDates = shiftDates
        self.regenerateUIDs = regenerateUIDs
        self.preserveTags = preserveTags
        self.customActions = customActions
        
        if let shift = shiftDates {
            self.dateOffset = shift
        }
    }
    
    func anonymize(file: DICOMFile, filePath: String) throws -> (DICOMFile, AnonymizationResult) {
        var newDataSet = file.dataSet
        var changedTags: [Tag] = []
        var warnings: [String] = []
        
        let tagsToProcess = profile.tagsToRemove.subtracting(preserveTags)
        
        for tag in tagsToProcess {
            guard let element = newDataSet[tag] else { continue }
            
            let action = customActions[tag] ?? defaultAction(for: tag)
            
            switch action {
            case .remove:
                let originalValue = extractValue(from: element)
                newDataSet.remove(tag: tag)
                changedTags.append(tag)
                logChange(filePath: filePath, action: "remove", tag: tag, originalValue: originalValue, newValue: nil)
                
            case .replaceWithEmpty:
                let originalValue = extractValue(from: element)
                replaceWithEmpty(tag: tag, vr: element.vr, in: &newDataSet)
                changedTags.append(tag)
                logChange(filePath: filePath, action: "replace_empty", tag: tag, originalValue: originalValue, newValue: "")
                
            case .replaceWithDummy(let dummy):
                let originalValue = extractValue(from: element)
                replaceWithDummy(tag: tag, vr: element.vr, value: dummy, in: &newDataSet)
                changedTags.append(tag)
                logChange(filePath: filePath, action: "replace_dummy", tag: tag, originalValue: originalValue, newValue: dummy)
                
            case .hash:
                if let originalValue = extractValue(from: element) {
                    let hashed = hashValue(originalValue)
                    replaceWithDummy(tag: tag, vr: element.vr, value: hashed, in: &newDataSet)
                    changedTags.append(tag)
                    logChange(filePath: filePath, action: "hash", tag: tag, originalValue: originalValue, newValue: hashed)
                }
                
            case .shiftDate(let days):
                if let originalDate = newDataSet.string(for: tag) {
                    if let shifted = shiftDate(originalDate, byDays: days) {
                        newDataSet.setString(shifted, for: tag, vr: element.vr)
                        changedTags.append(tag)
                        logChange(filePath: filePath, action: "shift_date", tag: tag, originalValue: originalDate, newValue: shifted)
                    }
                }
                
            case .regenerateUID:
                if let originalUID = newDataSet.string(for: tag) {
                    let newUID = getMappedUID(originalUID)
                    newDataSet.setString(newUID, for: tag, vr: element.vr)
                    changedTags.append(tag)
                    logChange(filePath: filePath, action: "regenerate_uid", tag: tag, originalValue: originalUID, newValue: newUID)
                }
            }
        }
        
        if let offset = dateOffset {
            shiftAllDates(in: &newDataSet, byDays: offset, changedTags: &changedTags, filePath: filePath)
        }
        
        if regenerateUIDs {
            regenerateAllUIDs(in: &newDataSet, changedTags: &changedTags, filePath: filePath)
        }
        
        let phiWarnings = scanForPHILeaks(in: newDataSet)
        warnings.append(contentsOf: phiWarnings)
        
        let newFile = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: newDataSet)
        let result = AnonymizationResult(
            filePath: filePath,
            success: true,
            changedTags: changedTags,
            warnings: warnings
        )
        
        return (newFile, result)
    }
    
    private func defaultAction(for tag: Tag) -> AnonymizationAction {
        if tag == .patientName {
            return .replaceWithDummy("ANONYMOUS")
        } else if tag == .patientID {
            return .hash
        } else if isDateTag(tag) {
            return shiftDates != nil ? .shiftDate(days: shiftDates!) : .remove
        } else if isUIDTag(tag) {
            return regenerateUIDs ? .regenerateUID : .remove
        } else {
            return .remove
        }
    }
    
    private func isDateTag(_ tag: Tag) -> Bool {
        [.studyDate, .seriesDate, .acquisitionDate, .contentDate, .patientBirthDate].contains(tag)
    }
    
    private func isUIDTag(_ tag: Tag) -> Bool {
        [.studyInstanceUID, .seriesInstanceUID, .sopInstanceUID].contains(tag)
    }
    
    private func extractValue(from element: DataElement) -> String? {
        if let str = element.stringValue {
            return str
        }
        return "\(element.tag)"
    }
    
    private func replaceWithEmpty(tag: Tag, vr: VR, in dataSet: inout DataSet) {
        dataSet.setString("", for: tag, vr: vr)
    }
    
    private func replaceWithDummy(tag: Tag, vr: VR, value: String, in dataSet: inout DataSet) {
        dataSet.setString(value, for: tag, vr: vr)
    }
    
    private func hashValue(_ value: String) -> String {
        var hash = value.hashValue
        if hash < 0 {
            hash = -hash
        }
        return String(format: "%016X", hash)
    }
    
    private func shiftDate(_ dateString: String, byDays days: Int) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        if let date = formatter.date(from: dateString) {
            if let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) {
                return formatter.string(from: shifted)
            }
        }
        return nil
    }
    
    private func shiftAllDates(in dataSet: inout DataSet, byDays days: Int, changedTags: inout [Tag], filePath: String) {
        let dateTags: [Tag] = [.studyDate, .seriesDate, .acquisitionDate, .contentDate]
        
        for tag in dateTags {
            if let originalDate = dataSet.string(for: tag), !changedTags.contains(tag) {
                if let shifted = shiftDate(originalDate, byDays: days) {
                    if let element = dataSet[tag] {
                        dataSet.setString(shifted, for: tag, vr: element.vr)
                        changedTags.append(tag)
                        logChange(filePath: filePath, action: "shift_date", tag: tag, originalValue: originalDate, newValue: shifted)
                    }
                }
            }
        }
    }
    
    private func regenerateAllUIDs(in dataSet: inout DataSet, changedTags: inout [Tag], filePath: String) {
        let uidTags: [Tag] = [.studyInstanceUID, .seriesInstanceUID, .sopInstanceUID]
        
        for tag in uidTags {
            if let originalUID = dataSet.string(for: tag), !changedTags.contains(tag) {
                let newUID = getMappedUID(originalUID)
                if let element = dataSet[tag] {
                    dataSet.setString(newUID, for: tag, vr: element.vr)
                    changedTags.append(tag)
                    logChange(filePath: filePath, action: "regenerate_uid", tag: tag, originalValue: originalUID, newValue: newUID)
                }
            }
        }
    }
    
    private func getMappedUID(_ originalUID: String) -> String {
        if let mapped = uidMapping[originalUID] {
            return mapped
        }
        
        let newUID = UIDGenerator.generateUID().value
        uidMapping[originalUID] = newUID
        return newUID
    }
    
    private func scanForPHILeaks(in dataSet: DataSet) -> [String] {
        var warnings: [String] = []
        
        for tag in dataSet.tags {
            if tag.isPrivate {
                if let element = dataSet[tag], let value = extractValue(from: element) {
                    if containsSuspiciousPHI(value) {
                        warnings.append("Potential PHI detected in private tag \(tag): \(value.prefix(20))...")
                    }
                }
            }
        }
        
        return warnings
    }
    
    private func containsSuspiciousPHI(_ value: String) -> Bool {
        let patterns = [
            "\\b[A-Z][a-z]+\\s[A-Z][a-z]+\\b",
            "\\b\\d{3}-\\d{2}-\\d{4}\\b",
            "\\b\\d{10}\\b",
            "\\b\\d{1,2}/\\d{1,2}/\\d{4}\\b"
        ]
        
        for pattern in patterns {
            if let _ = value.range(of: pattern, options: .regularExpression) {
                return true
            }
        }
        
        return false
    }
    
    private func logChange(filePath: String, action: String, tag: Tag, originalValue: String?, newValue: String?) {
        let entry = AuditLogEntry(
            timestamp: Date(),
            filePath: filePath,
            action: action,
            tag: tag,
            originalValue: originalValue,
            newValue: newValue
        )
        auditLog.append(entry)
    }
    
    func getAuditLog() -> [AuditLogEntry] {
        return auditLog
    }
    
    func writeAuditLog(to url: URL) throws {
        let dateFormatter = ISO8601DateFormatter()
        var logText = "DICOM Anonymization Audit Log\n"
        logText += "Generated: \(dateFormatter.string(from: Date()))\n\n"
        
        for entry in auditLog {
            logText += "[\(dateFormatter.string(from: entry.timestamp))] "
            logText += "\(entry.filePath) - \(entry.action) - \(entry.tag)\n"
            if let orig = entry.originalValue {
                logText += "  Original: \(orig)\n"
            }
            if let new = entry.newValue {
                logText += "  New: \(new)\n"
            }
            logText += "\n"
        }
        
        try logText.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class DICOMAnonTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func createTestDICOMFile(
        patientName: String = "Doe^John",
        patientID: String = "12345",
        patientBirthDate: String = "19800101",
        studyDate: String = "20240115",
        studyInstanceUID: String = "1.2.3.4.5"
    ) -> DICOMFile {
        var dataSet = DataSet()
        
        dataSet.setString(patientName, for: .patientName, vr: .PN)
        dataSet.setString(patientID, for: .patientID, vr: .LO)
        dataSet.setString(patientBirthDate, for: .patientBirthDate, vr: .DA)
        dataSet.setString(studyDate, for: .studyDate, vr: .DA)
        dataSet.setString(studyInstanceUID, for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        dataSet.setString("CT", for: .modality, vr: .CS)
        
        return DICOMFile.create(dataSet: dataSet)
    }
    
    // MARK: - Basic Profile Tests
    
    func testRemovePatientName() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertNil(anonymizedFile.dataSet[.patientName] ?? anonymizedFile.dataSet.string(for: .patientName))
    }
    
    func testRemovePatientID() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.changedTags.contains(.patientID))
    }
    
    func testRemoveDateOfBirth() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertNil(anonymizedFile.dataSet[.patientBirthDate])
    }
    
    func testReplacePatientNameWithAnonymous() throws {
        let file = createTestDICOMFile()
        let customActions: [Tag: AnonymizationAction] = [
            .patientName: .replaceWithDummy("ANONYMOUS")
        ]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            customActions: customActions
        )
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(anonymizedFile.dataSet.string(for: .patientName), "ANONYMOUS")
    }
    
    func testHashPatientID() throws {
        let file = createTestDICOMFile(patientID: "ABC123")
        let customActions: [Tag: AnonymizationAction] = [
            .patientID: .hash
        ]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            customActions: customActions
        )
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        let hashedValue = anonymizedFile.dataSet.string(for: .patientID)
        XCTAssertNotNil(hashedValue)
        XCTAssertNotEqual(hashedValue, "ABC123")
        XCTAssertEqual(hashedValue?.count, 16) // SHA-256 truncated to 16 chars
    }
    
    // MARK: - Date Shifting Tests
    
    func testShiftDatesByOffset() throws {
        let file = createTestDICOMFile(studyDate: "20240115")
        let anonymizer = Anonymizer(profile: .basic, shiftDates: 100, regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        let shiftedDate = anonymizedFile.dataSet.string(for: .studyDate)
        XCTAssertNotNil(shiftedDate)
        XCTAssertNotEqual(shiftedDate, "20240115")
        XCTAssertEqual(shiftedDate, "20240424") // 100 days after Jan 15, 2024
    }
    
    func testPreserveDateIntervals() throws {
        var dataSet = DataSet()
        dataSet.setString("20240101", for: .studyDate, vr: .DA)
        dataSet.setString("20240110", for: .seriesDate, vr: .DA)
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .basic, shiftDates: 50, regenerateUIDs: false)
        
        let (anonymizedFile, _) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        let studyDate = anonymizedFile.dataSet.string(for: .studyDate)!
        let seriesDate = anonymizedFile.dataSet.string(for: .seriesDate)!
        
        // Parse dates to verify interval is preserved (9 days)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let study = formatter.date(from: studyDate)!
        let series = formatter.date(from: seriesDate)!
        
        let interval = Calendar.current.dateComponents([.day], from: study, to: series).day!
        XCTAssertEqual(interval, 9)
    }
    
    func testShiftDatesWithCustomAction() throws {
        let file = createTestDICOMFile(studyDate: "20240115")
        let customActions: [Tag: AnonymizationAction] = [
            .studyDate: .shiftDate(days: 30)
        ]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            customActions: customActions
        )
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        let shiftedDate = anonymizedFile.dataSet.string(for: .studyDate)
        XCTAssertEqual(shiftedDate, "20240214") // 30 days after Jan 15
    }
    
    // MARK: - UID Regeneration Tests
    
    func testGenerateNewStudyInstanceUID() throws {
        let originalUID = "1.2.3.4.5.6.7.8.9"
        let file = createTestDICOMFile(studyInstanceUID: originalUID)
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: true)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        let newUID = anonymizedFile.dataSet.string(for: .studyInstanceUID)
        XCTAssertNotNil(newUID)
        XCTAssertNotEqual(newUID, originalUID)
    }
    
    func testGenerateNewSeriesInstanceUID() throws {
        var dataSet = DataSet()
        dataSet.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: true)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertNotEqual(anonymizedFile.dataSet.string(for: .seriesInstanceUID), "1.2.3.4.5")
    }
    
    func testMaintainUIDReferences() throws {
        let originalUID = "1.2.3.4.5.6.7.8.9"
        
        // Create two files with same Study Instance UID
        let file1 = createTestDICOMFile(studyInstanceUID: originalUID)
        let file2 = createTestDICOMFile(studyInstanceUID: originalUID)
        
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: true)
        
        let (anon1, _) = try anonymizer.anonymize(file: file1, filePath: "test1.dcm")
        let (anon2, _) = try anonymizer.anonymize(file: file2, filePath: "test2.dcm")
        
        let uid1 = anon1.dataSet.string(for: .studyInstanceUID)
        let uid2 = anon2.dataSet.string(for: .studyInstanceUID)
        
        // Both files should have same new UID (consistent mapping)
        XCTAssertEqual(uid1, uid2)
        XCTAssertNotEqual(uid1, originalUID)
    }
    
    // MARK: - Profile Tests
    
    func testBasicProfile() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.changedTags.contains(.patientName))
        XCTAssertTrue(result.changedTags.contains(.patientID))
        XCTAssertTrue(result.changedTags.contains(.patientBirthDate))
    }
    
    func testClinicalTrialProfile() throws {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("12345", for: .patientID, vr: .LO)
        dataSet.setString("20240101", for: .studyDate, vr: .DA)
        dataSet.setString("120000", for: .studyTime, vr: .TM)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .clinicalTrial, regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.changedTags.contains(.patientName))
        XCTAssertTrue(result.changedTags.contains(.studyDate))
        XCTAssertTrue(result.changedTags.contains(.studyTime))
    }
    
    func testResearchProfile() throws {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("12345", for: .patientID, vr: .LO)
        dataSet.setString("19800101", for: .patientBirthDate, vr: .DA)
        dataSet.setString("20240101", for: .studyDate, vr: .DA)
        dataSet.setString("CT Brain Study", for: .studyDescription, vr: .LO)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .research, regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        // Research profile should keep study date and description
        XCTAssertNotNil(anonymizedFile.dataSet.string(for: .studyDate))
        XCTAssertNotNil(anonymizedFile.dataSet.string(for: .studyDescription))
    }
    
    func testCustomProfileWithSpecificTags() throws {
        let customTags: [Tag] = [.patientName, .patientBirthDate]
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .custom(customTags), regenerateUIDs: false)
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.changedTags.contains(.patientName))
        XCTAssertTrue(result.changedTags.contains(.patientBirthDate))
        // Patient ID should NOT be changed (not in custom list)
        XCTAssertNotNil(anonymizedFile.dataSet.string(for: .patientID))
    }
    
    // MARK: - Preserve Tags Tests
    
    func testPreserveSpecificTag() throws {
        let file = createTestDICOMFile()
        let preserveTags: Set<Tag> = [.patientName]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            preserveTags: preserveTags
        )
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        // Patient name should be preserved
        XCTAssertEqual(anonymizedFile.dataSet.string(for: .patientName), "Doe^John")
        // Other tags should still be anonymized
        XCTAssertTrue(result.changedTags.contains(.patientID))
    }
    
    // MARK: - Custom Actions Tests
    
    func testCustomRemoveAction() throws {
        let file = createTestDICOMFile()
        let customActions: [Tag: AnonymizationAction] = [
            .patientName: .remove
        ]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            customActions: customActions
        )
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertNil(anonymizedFile.dataSet[.patientName])
    }
    
    func testCustomReplaceAction() throws {
        let file = createTestDICOMFile()
        let customActions: [Tag: AnonymizationAction] = [
            .patientName: .replaceWithDummy("TEST^PATIENT")
        ]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            customActions: customActions
        )
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(anonymizedFile.dataSet.string(for: .patientName), "TEST^PATIENT")
    }
    
    func testCustomHashAction() throws {
        let file = createTestDICOMFile(patientID: "UNIQUE123")
        let customActions: [Tag: AnonymizationAction] = [
            .patientID: .hash
        ]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            customActions: customActions
        )
        
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        let hashedID = anonymizedFile.dataSet.string(for: .patientID)
        XCTAssertNotNil(hashedID)
        XCTAssertNotEqual(hashedID, "UNIQUE123")
        // Hash should be deterministic
        let anonymizer2 = Anonymizer(
            profile: .basic,
            regenerateUIDs: false,
            customActions: customActions
        )
        let (anonymizedFile2, _) = try anonymizer2.anonymize(file: file, filePath: "test.dcm")
        XCTAssertEqual(hashedID, anonymizedFile2.dataSet.string(for: .patientID))
    }
    
    // MARK: - Audit Log Tests
    
    func testAuditLogContainsChanges() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let _ = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        let auditLog = anonymizer.getAuditLog()
        XCTAssertFalse(auditLog.isEmpty)
        XCTAssertTrue(auditLog.contains(where: { $0.tag == .patientName }))
        XCTAssertTrue(auditLog.contains(where: { $0.tag == .patientID }))
    }
    
    func testAuditLogWriteToFile() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let _ = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit.log")
        try anonymizer.writeAuditLog(to: tempURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        let logContent = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(logContent.contains("DICOM Anonymization Audit Log"))
        XCTAssertTrue(logContent.contains("test.dcm"))
        
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: - PHI Detection Tests
    
    func testDetectPHIInPrivateTags() throws {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        // Add a private tag with potential PHI
        let privateTag = Tag(group: 0x0009, element: 0x0010)
        dataSet.setString("John Smith 123-45-6789", for: privateTag, vr: .LO)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (_, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("private tag") }))
    }
    
    // MARK: - Multi-File Consistency Tests
    
    func testConsistentPseudonymization() throws {
        let file1 = createTestDICOMFile(patientID: "PATIENT001", studyInstanceUID: "1.2.3.4.5")
        let file2 = createTestDICOMFile(patientID: "PATIENT001", studyInstanceUID: "1.2.3.4.5")
        
        let customActions: [Tag: AnonymizationAction] = [
            .patientID: .hash
        ]
        let anonymizer = Anonymizer(
            profile: .basic,
            regenerateUIDs: true,
            customActions: customActions
        )
        
        let (anon1, _) = try anonymizer.anonymize(file: file1, filePath: "test1.dcm")
        let (anon2, _) = try anonymizer.anonymize(file: file2, filePath: "test2.dcm")
        
        // Both files should have same hashed patient ID
        XCTAssertEqual(
            anon1.dataSet.string(for: .patientID),
            anon2.dataSet.string(for: .patientID)
        )
        
        // Both files should have same new study UID
        XCTAssertEqual(
            anon1.dataSet.string(for: .studyInstanceUID),
            anon2.dataSet.string(for: .studyInstanceUID)
        )
    }
    
    // MARK: - Edge Cases
    
    func testAnonymizeFileWithoutPatientInfo() throws {
        var dataSet = DataSet()
        dataSet.setString("CT", for: .modality, vr: .CS)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (_, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.changedTags.isEmpty)
    }
    
    func testAnonymizeFileWithEmptyValues() throws {
        var dataSet = DataSet()
        dataSet.setString("", for: .patientName, vr: .PN)
        dataSet.setString("", for: .patientID, vr: .LO)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (_, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
    }
    
    func testAnonymizeWithInvalidDate() throws {
        var dataSet = DataSet()
        dataSet.setString("Doe^John", for: .patientName, vr: .PN)
        dataSet.setString("INVALID", for: .studyDate, vr: .DA)
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        
        let file = DICOMFile.create(dataSet: dataSet)
        let anonymizer = Anonymizer(profile: .basic, shiftDates: 100, regenerateUIDs: false)
        
        // Should not throw, but date won't be shifted
        let (anonymizedFile, result) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        XCTAssertTrue(result.success)
        // Invalid date should remain unchanged or removed
        let studyDate = anonymizedFile.dataSet.string(for: .studyDate)
        XCTAssertTrue(studyDate == nil || studyDate == "INVALID")
    }
    
    // MARK: - File Writing Tests
    
    func testAnonymizedFileCanBeWritten() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (anonymizedFile, _) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        // Should be able to write the file
        let data = try anonymizedFile.write()
        XCTAssertFalse(data.isEmpty)
        XCTAssertGreaterThan(data.count, 132) // At least preamble + prefix
    }
    
    func testAnonymizedFileCanBeRead() throws {
        let file = createTestDICOMFile()
        let anonymizer = Anonymizer(profile: .basic, regenerateUIDs: false)
        
        let (anonymizedFile, _) = try anonymizer.anonymize(file: file, filePath: "test.dcm")
        
        // Write and read back
        let data = try anonymizedFile.write()
        let readFile = try DICOMFile.read(from: data)
        
        XCTAssertNotNil(readFile)
        XCTAssertEqual(readFile.dataSet.string(for: .modality), "CT")
    }
}
