import XCTest
import DICOMCore
@testable import DICOMNetwork

final class QueryResultsTests: XCTestCase {
    
    // MARK: - Patient Result Tests
    
    func testPatientResultFromAttributes() {
        var attributes: [Tag: Data] = [:]
        attributes[.patientName] = "DOE^JOHN".data(using: .ascii)!
        attributes[.patientID] = "12345678".data(using: .ascii)!
        attributes[.patientBirthDate] = "19800101".data(using: .ascii)!
        attributes[.patientSex] = "M".data(using: .ascii)!
        attributes[.numberOfPatientRelatedStudies] = "5".data(using: .ascii)!
        attributes[.numberOfPatientRelatedSeries] = "15".data(using: .ascii)!
        attributes[.numberOfPatientRelatedInstances] = "500".data(using: .ascii)!
        
        let result = PatientResult(attributes: attributes)
        
        XCTAssertEqual(result.patientName, "DOE^JOHN")
        XCTAssertEqual(result.patientID, "12345678")
        XCTAssertEqual(result.patientBirthDate, "19800101")
        XCTAssertEqual(result.patientSex, "M")
        XCTAssertEqual(result.numberOfPatientRelatedStudies, 5)
        XCTAssertEqual(result.numberOfPatientRelatedSeries, 15)
        XCTAssertEqual(result.numberOfPatientRelatedInstances, 500)
    }
    
    func testPatientResultMissingAttributes() {
        let result = PatientResult(attributes: [:])
        
        XCTAssertNil(result.patientName)
        XCTAssertNil(result.patientID)
        XCTAssertNil(result.patientBirthDate)
        XCTAssertNil(result.patientSex)
        XCTAssertNil(result.numberOfPatientRelatedStudies)
    }
    
    func testPatientResultDescription() {
        var attributes: [Tag: Data] = [:]
        attributes[.patientName] = "DOE^JOHN".data(using: .ascii)!
        attributes[.patientID] = "12345".data(using: .ascii)!
        
        let result = PatientResult(attributes: attributes)
        let description = result.description
        
        XCTAssertTrue(description.contains("DOE^JOHN"))
        XCTAssertTrue(description.contains("12345"))
    }
    
    // MARK: - Study Result Tests
    
    func testStudyResultFromAttributes() {
        var attributes: [Tag: Data] = [:]
        attributes[.studyInstanceUID] = "1.2.3.4.5".data(using: .ascii)!
        attributes[.studyDate] = "20240115".data(using: .ascii)!
        attributes[.studyTime] = "143000".data(using: .ascii)!
        attributes[.studyDescription] = "CT CHEST".data(using: .ascii)!
        attributes[.accessionNumber] = "ACC123".data(using: .ascii)!
        attributes[.studyID] = "STUDY001".data(using: .ascii)!
        attributes[.patientName] = "DOE^JOHN".data(using: .ascii)!
        attributes[.patientID] = "12345".data(using: .ascii)!
        attributes[.modalitiesInStudy] = "CT\\MR".data(using: .ascii)!
        attributes[.numberOfStudyRelatedSeries] = "3".data(using: .ascii)!
        attributes[.numberOfStudyRelatedInstances] = "150".data(using: .ascii)!
        
        let result = StudyResult(attributes: attributes)
        
        XCTAssertEqual(result.studyInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(result.studyDate, "20240115")
        XCTAssertEqual(result.studyTime, "143000")
        XCTAssertEqual(result.studyDescription, "CT CHEST")
        XCTAssertEqual(result.accessionNumber, "ACC123")
        XCTAssertEqual(result.studyID, "STUDY001")
        XCTAssertEqual(result.patientName, "DOE^JOHN")
        XCTAssertEqual(result.patientID, "12345")
        XCTAssertEqual(result.modalitiesInStudy, "CT\\MR")
        XCTAssertEqual(result.modalities, ["CT", "MR"])
        XCTAssertEqual(result.numberOfStudyRelatedSeries, 3)
        XCTAssertEqual(result.numberOfStudyRelatedInstances, 150)
    }
    
    func testStudyResultModalities() {
        // Single modality
        var attributes1: [Tag: Data] = [:]
        attributes1[.modalitiesInStudy] = "CT".data(using: .ascii)!
        let result1 = StudyResult(attributes: attributes1)
        XCTAssertEqual(result1.modalities, ["CT"])
        
        // Multiple modalities
        var attributes2: [Tag: Data] = [:]
        attributes2[.modalitiesInStudy] = "CT\\MR\\US".data(using: .ascii)!
        let result2 = StudyResult(attributes: attributes2)
        XCTAssertEqual(result2.modalities, ["CT", "MR", "US"])
        
        // No modalities
        let result3 = StudyResult(attributes: [:])
        XCTAssertEqual(result3.modalities, [])
    }
    
    func testStudyResultDescription() {
        var attributes: [Tag: Data] = [:]
        attributes[.studyInstanceUID] = "1.2.3.4.5".data(using: .ascii)!
        attributes[.studyDate] = "20240115".data(using: .ascii)!
        
        let result = StudyResult(attributes: attributes)
        let description = result.description
        
        XCTAssertTrue(description.contains("1.2.3.4.5"))
        XCTAssertTrue(description.contains("20240115"))
    }
    
    // MARK: - Series Result Tests
    
    func testSeriesResultFromAttributes() {
        var attributes: [Tag: Data] = [:]
        attributes[.seriesInstanceUID] = "1.2.3.4.5.6".data(using: .ascii)!
        attributes[.seriesNumber] = "1".data(using: .ascii)!
        attributes[.seriesDescription] = "AXIAL IMAGES".data(using: .ascii)!
        attributes[.modality] = "CT".data(using: .ascii)!
        attributes[.seriesDate] = "20240115".data(using: .ascii)!
        attributes[.seriesTime] = "143500".data(using: .ascii)!
        attributes[.bodyPartExamined] = "CHEST".data(using: .ascii)!
        attributes[.numberOfSeriesRelatedInstances] = "50".data(using: .ascii)!
        attributes[.studyInstanceUID] = "1.2.3.4.5".data(using: .ascii)!
        
        let result = SeriesResult(attributes: attributes)
        
        XCTAssertEqual(result.seriesInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(result.seriesNumber, 1)
        XCTAssertEqual(result.seriesDescription, "AXIAL IMAGES")
        XCTAssertEqual(result.modality, "CT")
        XCTAssertEqual(result.seriesDate, "20240115")
        XCTAssertEqual(result.seriesTime, "143500")
        XCTAssertEqual(result.bodyPartExamined, "CHEST")
        XCTAssertEqual(result.numberOfSeriesRelatedInstances, 50)
        XCTAssertEqual(result.studyInstanceUID, "1.2.3.4.5")
    }
    
    func testSeriesResultDescription() {
        var attributes: [Tag: Data] = [:]
        attributes[.seriesInstanceUID] = "1.2.3.4.5.6".data(using: .ascii)!
        attributes[.modality] = "CT".data(using: .ascii)!
        
        let result = SeriesResult(attributes: attributes)
        let description = result.description
        
        XCTAssertTrue(description.contains("1.2.3.4.5.6"))
        XCTAssertTrue(description.contains("CT"))
    }
    
    // MARK: - Instance Result Tests
    
    func testInstanceResultFromAttributes() {
        var attributes: [Tag: Data] = [:]
        attributes[.sopInstanceUID] = "1.2.3.4.5.6.7".data(using: .ascii)!
        attributes[.sopClassUID] = "1.2.840.10008.5.1.4.1.1.2".data(using: .ascii)!
        attributes[.instanceNumber] = "1".data(using: .ascii)!
        attributes[.contentDate] = "20240115".data(using: .ascii)!
        attributes[.contentTime] = "143505".data(using: .ascii)!
        attributes[.rows] = "512".data(using: .ascii)!
        attributes[.columns] = "512".data(using: .ascii)!
        attributes[.numberOfFrames] = "1".data(using: .ascii)!
        attributes[.seriesInstanceUID] = "1.2.3.4.5.6".data(using: .ascii)!
        attributes[.studyInstanceUID] = "1.2.3.4.5".data(using: .ascii)!
        
        let result = InstanceResult(attributes: attributes)
        
        XCTAssertEqual(result.sopInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(result.sopClassUID, "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertEqual(result.instanceNumber, 1)
        XCTAssertEqual(result.contentDate, "20240115")
        XCTAssertEqual(result.contentTime, "143505")
        XCTAssertEqual(result.rows, 512)
        XCTAssertEqual(result.columns, 512)
        XCTAssertEqual(result.numberOfFrames, 1)
        XCTAssertEqual(result.seriesInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(result.studyInstanceUID, "1.2.3.4.5")
    }
    
    func testInstanceResultDescription() {
        var attributes: [Tag: Data] = [:]
        attributes[.sopInstanceUID] = "1.2.3.4.5.6.7".data(using: .ascii)!
        attributes[.instanceNumber] = "1".data(using: .ascii)!
        attributes[.rows] = "512".data(using: .ascii)!
        attributes[.columns] = "512".data(using: .ascii)!
        
        let result = InstanceResult(attributes: attributes)
        let description = result.description
        
        XCTAssertTrue(description.contains("1.2.3.4.5.6.7"))
        XCTAssertTrue(description.contains("512x512"))
    }
    
    // MARK: - Generic Query Result Tests
    
    func testGenericQueryResult() {
        var attributes: [Tag: Data] = [:]
        attributes[.patientName] = "DOE^JOHN".data(using: .ascii)!
        attributes[.studyInstanceUID] = "1.2.3.4.5".data(using: .ascii)!
        
        let result = GenericQueryResult(attributes: attributes, level: .study)
        
        XCTAssertEqual(result.level, .study)
        XCTAssertEqual(result.string(for: .patientName), "DOE^JOHN")
        XCTAssertEqual(result.uid(for: .studyInstanceUID), "1.2.3.4.5")
    }
    
    func testGenericQueryResultConversion() {
        var attributes: [Tag: Data] = [:]
        attributes[.studyInstanceUID] = "1.2.3.4.5".data(using: .ascii)!
        attributes[.patientName] = "DOE^JOHN".data(using: .ascii)!
        
        let generic = GenericQueryResult(attributes: attributes, level: .study)
        
        // Convert to StudyResult
        let studyResult = generic.toStudyResult()
        XCTAssertEqual(studyResult.studyInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(studyResult.patientName, "DOE^JOHN")
        
        // Convert to PatientResult
        let patientResult = generic.toPatientResult()
        XCTAssertEqual(patientResult.patientName, "DOE^JOHN")
    }
    
    // MARK: - Value Parsing Tests
    
    func testStringWithPadding() {
        var attributes: [Tag: Data] = [:]
        // Value with trailing spaces and null
        attributes[.patientName] = "DOE^JOHN  \0".data(using: .ascii)!
        
        let result = PatientResult(attributes: attributes)
        XCTAssertEqual(result.patientName, "DOE^JOHN")
    }
    
    func testIntegerParsing() {
        var attributes: [Tag: Data] = [:]
        // Integer with leading spaces
        attributes[.numberOfPatientRelatedStudies] = "  42  ".data(using: .ascii)!
        
        let result = PatientResult(attributes: attributes)
        XCTAssertEqual(result.numberOfPatientRelatedStudies, 42)
    }
    
    func testInvalidIntegerParsing() {
        var attributes: [Tag: Data] = [:]
        attributes[.numberOfPatientRelatedStudies] = "not a number".data(using: .ascii)!
        
        let result = PatientResult(attributes: attributes)
        XCTAssertNil(result.numberOfPatientRelatedStudies)
    }
    
    // MARK: - Equality and Hashable Tests
    
    func testPatientResultEquality() {
        var attributes1: [Tag: Data] = [:]
        attributes1[.patientName] = "DOE".data(using: .ascii)!
        
        var attributes2: [Tag: Data] = [:]
        attributes2[.patientName] = "DOE".data(using: .ascii)!
        
        var attributes3: [Tag: Data] = [:]
        attributes3[.patientName] = "SMITH".data(using: .ascii)!
        
        let result1 = PatientResult(attributes: attributes1)
        let result2 = PatientResult(attributes: attributes2)
        let result3 = PatientResult(attributes: attributes3)
        
        XCTAssertEqual(result1, result2)
        XCTAssertNotEqual(result1, result3)
    }
    
    func testStudyResultHashable() {
        var attributes1: [Tag: Data] = [:]
        attributes1[.studyInstanceUID] = "1.2.3".data(using: .ascii)!
        
        var attributes2: [Tag: Data] = [:]
        attributes2[.studyInstanceUID] = "1.2.4".data(using: .ascii)!
        
        var set = Set<StudyResult>()
        set.insert(StudyResult(attributes: attributes1))
        set.insert(StudyResult(attributes: attributes2))
        set.insert(StudyResult(attributes: attributes1)) // Duplicate
        
        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - Response Character Set Decoding (PS3.4 C.4.1.1.3.1, PS3.5 6.1.2)

final class QueryResultCharacterSetTests: XCTestCase {

    func testDeclaredISOIR100DecodesLatin1Bytes() {
        let result = StudyResult(attributes: [
            .specificCharacterSet: "ISO_IR 100".data(using: .ascii)!,
            .patientName: "MÜLLER^HANS ".data(using: .isoLatin1)!
        ])
        XCTAssertEqual(result.specificCharacterSet, "ISO_IR 100")
        XCTAssertEqual(result.patientName, "MÜLLER^HANS")
    }

    func testDeclaredISOIR192DecodesUTF8Bytes() {
        let result = PatientResult(attributes: [
            .specificCharacterSet: "ISO_IR 192".data(using: .ascii)!,
            .patientName: Data("山田^太郎".utf8)
        ])
        XCTAssertEqual(result.patientName, "山田^太郎")
    }

    func testUndeclaredLatin1BytesFallBackToLatin1() {
        // No (0008,0005): declared → UTF-8 → Latin-1. 0xDC alone is invalid UTF-8.
        let result = StudyResult(attributes: [
            .patientName: "MÜLLER^HANS".data(using: .isoLatin1)!
        ])
        XCTAssertNil(result.specificCharacterSet)
        XCTAssertEqual(result.patientName, "MÜLLER^HANS")
    }

    func testUndeclaredUTF8BytesDecodeAsUTF8() {
        let result = StudyResult(attributes: [.patientName: Data("MÜLLER^HANS".utf8)])
        XCTAssertEqual(result.patientName, "MÜLLER^HANS")
    }

    func testFormatterJSONAndCSVUseDeclaredCharacterSet() {
        let result = GenericQueryResult(attributes: [
            .specificCharacterSet: "ISO_IR 100".data(using: .ascii)!,
            .patientName: "MÜLLER^HANS ".data(using: .isoLatin1)!
        ], level: .study)
        let json = DICOMQueryResultFormatter(format: .json, level: .study).format(results: [result])
        XCTAssertTrue(json.contains("MÜLLER^HANS"), json)
        let csv = DICOMQueryResultFormatter(format: .csv, level: .study).format(results: [result])
        XCTAssertTrue(csv.contains("MÜLLER^HANS"), csv)
    }
}
