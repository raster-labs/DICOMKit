import Testing
import Foundation
@testable import DICOMWeb

@Suite("QIDOQuery Tests")
struct QIDOQueryTests {
    
    // MARK: - Initialization Tests
    
    @Test("Empty query initialization")
    func testEmptyQueryInit() {
        let query = QIDOQuery()
        
        #expect(query.isEmpty)
        #expect(query.parameterCount == 0)
        #expect(query.toParameters().isEmpty)
    }
    
    @Test("Query initialization with parameters")
    func testQueryInitWithParameters() {
        let params = ["00100020": "12345", "00080020": "20240101"]
        let query = QIDOQuery(parameters: params)
        
        #expect(!query.isEmpty)
        #expect(query.parameterCount == 2)
        
        let result = query.toParameters()
        #expect(result["00100020"] == "12345")
        #expect(result["00080020"] == "20240101")
    }
    
    // MARK: - Patient Level Attribute Tests
    
    @Test("Patient ID query")
    func testPatientIDQuery() {
        let query = QIDOQuery().patientID("12345")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.patientID] == "12345")
    }
    
    @Test("Patient name query")
    func testPatientNameQuery() {
        let query = QIDOQuery().patientName("Smith*")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.patientName] == "Smith*")
    }
    
    @Test("Patient birth date query")
    func testPatientBirthDateQuery() {
        let query = QIDOQuery().patientBirthDate("19800101")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.patientBirthDate] == "19800101")
    }
    
    @Test("Patient sex query")
    func testPatientSexQuery() {
        let query = QIDOQuery().patientSex("M")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.patientSex] == "M")
    }
    
    // MARK: - Study Level Attribute Tests
    
    @Test("Study Instance UID query")
    func testStudyInstanceUIDQuery() {
        let uid = "1.2.840.10008.5.1.4.1.1.2"
        let query = QIDOQuery().studyInstanceUID(uid)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyInstanceUID] == uid)
    }
    
    @Test("Study date query")
    func testStudyDateQuery() {
        let query = QIDOQuery().studyDate("20240101")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyDate] == "20240101")
    }
    
    @Test("Study date range query")
    func testStudyDateRangeQuery() {
        let query = QIDOQuery().studyDate(from: "20240101", to: "20241231")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyDate] == "20240101-20241231")
    }
    
    @Test("Study date range open-ended from query")
    func testStudyDateRangeOpenFrom() {
        let query = QIDOQuery().studyDateRange(from: "20240101")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyDate] == "20240101-")
    }
    
    @Test("Study date range open-ended to query")
    func testStudyDateRangeOpenTo() {
        let query = QIDOQuery().studyDateRange(to: "20241231")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyDate] == "-20241231")
    }
    
    @Test("Study date range empty returns unchanged query")
    func testStudyDateRangeEmpty() {
        let query = QIDOQuery().studyDateRange()
        
        #expect(query.isEmpty)
    }
    
    @Test("Study time query")
    func testStudyTimeQuery() {
        let query = QIDOQuery().studyTime("140000")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyTime] == "140000")
    }
    
    @Test("Study time range query")
    func testStudyTimeRangeQuery() {
        let query = QIDOQuery().studyTime(from: "080000", to: "170000")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyTime] == "080000-170000")
    }
    
    @Test("Study description query")
    func testStudyDescriptionQuery() {
        let query = QIDOQuery().studyDescription("CT*")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyDescription] == "CT*")
    }
    
    @Test("Accession number query")
    func testAccessionNumberQuery() {
        let query = QIDOQuery().accessionNumber("ACC12345")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.accessionNumber] == "ACC12345")
    }
    
    @Test("Referring physician name query")
    func testReferringPhysicianNameQuery() {
        let query = QIDOQuery().referringPhysicianName("Jones*")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.referringPhysicianName] == "Jones*")
    }
    
    @Test("Study ID query")
    func testStudyIDQuery() {
        let query = QIDOQuery().studyID("STUDY001")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyID] == "STUDY001")
    }
    
    // MARK: - Series Level Attribute Tests
    
    @Test("Series Instance UID query")
    func testSeriesInstanceUIDQuery() {
        let uid = "1.2.3.4.5.6"
        let query = QIDOQuery().seriesInstanceUID(uid)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.seriesInstanceUID] == uid)
    }
    
    @Test("Modality query")
    func testModalityQuery() {
        let query = QIDOQuery().modality("CT")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.modality] == "CT")
    }
    
    @Test("Series number query")
    func testSeriesNumberQuery() {
        let query = QIDOQuery().seriesNumber(5)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.seriesNumber] == "5")
    }
    
    @Test("Series description query")
    func testSeriesDescriptionQuery() {
        let query = QIDOQuery().seriesDescription("Axial*")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.seriesDescription] == "Axial*")
    }
    
    @Test("Body part examined query")
    func testBodyPartExaminedQuery() {
        let query = QIDOQuery().bodyPartExamined("CHEST")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.bodyPartExamined] == "CHEST")
    }
    
    // MARK: - Instance Level Attribute Tests
    
    @Test("SOP Instance UID query")
    func testSOPInstanceUIDQuery() {
        let uid = "1.2.3.4.5.6.7"
        let query = QIDOQuery().sopInstanceUID(uid)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.sopInstanceUID] == uid)
    }
    
    @Test("SOP Class UID query")
    func testSOPClassUIDQuery() {
        let uid = "1.2.840.10008.5.1.4.1.1.2"
        let query = QIDOQuery().sopClassUID(uid)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.sopClassUID] == uid)
    }
    
    @Test("Instance number query")
    func testInstanceNumberQuery() {
        let query = QIDOQuery().instanceNumber(10)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.instanceNumber] == "10")
    }
    
    @Test("Number of frames query")
    func testNumberOfFramesQuery() {
        let query = QIDOQuery().numberOfFrames(100)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.numberOfFrames] == "100")
    }
    
    // MARK: - Generic Attribute Tests
    
    @Test("Generic attribute with tag string")
    func testGenericAttributeString() {
        let query = QIDOQuery().attribute("00100010", value: "Test")
        
        let params = query.toParameters()
        #expect(params["00100010"] == "Test")
    }
    
    @Test("Generic attribute with group and element")
    func testGenericAttributeGroupElement() {
        let query = QIDOQuery().attribute(group: 0x0010, element: 0x0020, value: "Patient123")
        
        let params = query.toParameters()
        #expect(params["00100020"] == "Patient123")
    }
    
    // MARK: - Pagination Tests
    
    @Test("Limit query")
    func testLimitQuery() {
        let query = QIDOQuery().limit(10)
        
        let params = query.toParameters()
        #expect(params["limit"] == "10")
    }
    
    @Test("Offset query")
    func testOffsetQuery() {
        let query = QIDOQuery().offset(50)
        
        let params = query.toParameters()
        #expect(params["offset"] == "50")
    }
    
    @Test("Pagination combination")
    func testPaginationCombination() {
        let query = QIDOQuery()
            .limit(25)
            .offset(100)
        
        let params = query.toParameters()
        #expect(params["limit"] == "25")
        #expect(params["offset"] == "100")
    }
    
    // MARK: - Include Fields Tests
    
    @Test("Include single field")
    func testIncludeSingleField() {
        let query = QIDOQuery().includeField("00100010")
        
        let params = query.toParameters()
        #expect(params["includefield"] == "00100010")
    }
    
    @Test("Include multiple fields")
    func testIncludeMultipleFields() {
        let query = QIDOQuery()
            .includeField("00100010")
            .includeField("00100020")
        
        let params = query.toParameters()
        let includefield = params["includefield"] ?? ""
        #expect(includefield.contains("00100010"))
        #expect(includefield.contains("00100020"))
    }
    
    @Test("Include fields array")
    func testIncludeFieldsArray() {
        let query = QIDOQuery().includeFields(["00100010", "00100020", "00080020"])
        
        let params = query.toParameters()
        let includefield = params["includefield"] ?? ""
        #expect(includefield.contains("00100010"))
        #expect(includefield.contains("00100020"))
        #expect(includefield.contains("00080020"))
    }
    
    @Test("Include all fields")
    func testIncludeAllFields() {
        let query = QIDOQuery().includeAllFields()
        
        let params = query.toParameters()
        #expect(params["includefield"] == "all")
    }
    
    @Test("Include all fields takes precedence")
    func testIncludeAllFieldsTakesPrecedence() {
        let query = QIDOQuery()
            .includeField("00100010")
            .includeAllFields()
        
        let params = query.toParameters()
        #expect(params["includefield"] == "all")
    }
    
    // MARK: - Fuzzy Matching Tests
    
    @Test("Fuzzy matching enabled")
    func testFuzzyMatchingEnabled() {
        let query = QIDOQuery().fuzzyMatching(true)
        
        let params = query.toParameters()
        #expect(params["fuzzymatching"] == "true")
    }
    
    @Test("Fuzzy matching disabled")
    func testFuzzyMatchingDisabled() {
        let query = QIDOQuery().fuzzyMatching(false)
        
        let params = query.toParameters()
        #expect(params["fuzzymatching"] == "false")
    }
    
    @Test("Fuzzy matching default is true")
    func testFuzzyMatchingDefault() {
        let query = QIDOQuery().fuzzyMatching()
        
        let params = query.toParameters()
        #expect(params["fuzzymatching"] == "true")
    }
    
    // MARK: - Fluent API Tests
    
    @Test("Fluent API chaining")
    func testFluentAPIChaining() {
        let query = QIDOQuery()
            .patientName("Smith*")
            .modality("CT")
            .studyDate(from: "20240101", to: "20241231")
            .limit(10)
            .offset(0)
        
        let params = query.toParameters()
        
        #expect(params[QIDOQueryAttribute.patientName] == "Smith*")
        #expect(params[QIDOQueryAttribute.modality] == "CT")
        #expect(params[QIDOQueryAttribute.studyDate] == "20240101-20241231")
        #expect(params["limit"] == "10")
        #expect(params["offset"] == "0")
    }
    
    @Test("Query is immutable - returns new instance")
    func testQueryImmutability() {
        let query1 = QIDOQuery()
        let query2 = query1.patientName("Smith")
        
        // Original query should be unchanged
        #expect(query1.isEmpty)
        #expect(!query2.isEmpty)
    }
    
    // MARK: - Convenience Factory Tests
    
    @Test("Studies by patient name factory")
    func testStudiesByPatientNameFactory() {
        let query = QIDOQuery.studiesByPatientName("Smith*", limit: 20)
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.patientName] == "Smith*")
        #expect(params["limit"] == "20")
    }
    
    @Test("Studies by date range factory")
    func testStudiesByDateRangeFactory() {
        let query = QIDOQuery.studiesByDateRange(from: "20240101", to: "20241231")
        
        let params = query.toParameters()
        #expect(params[QIDOQueryAttribute.studyDate] == "20240101-20241231")
    }
    
    @Test("Studies by modality factory")
    func testStudiesByModalityFactory() {
        let query = QIDOQuery.studiesByModality("MR", limit: 50)
        
        let params = query.toParameters()
        // PS3.18 Table 10.6.1-5: the study-level key is Modalities in Study (0008,0061)
        #expect(params[QIDOQueryAttribute.modalitiesInStudy] == "MR")
        #expect(params[QIDOQueryAttribute.modality] == nil)
        #expect(params["limit"] == "50")
    }
    
    @Test("All query factory")
    func testAllQueryFactory() {
        let query = QIDOQuery.all(limit: 100)
        
        let params = query.toParameters()
        #expect(params.count == 1)
        #expect(params["limit"] == "100")
    }
    
    @Test("All query factory without limit")
    func testAllQueryFactoryNoLimit() {
        let query = QIDOQuery.all()
        
        #expect(query.isEmpty)
    }
    
    // MARK: - Equatable Tests
    
    @Test("QIDOQuery equality")
    func testQueryEquality() {
        let query1 = QIDOQuery().patientName("Smith").modality("CT")
        let query2 = QIDOQuery().patientName("Smith").modality("CT")
        
        #expect(query1 == query2)
    }
    
    @Test("QIDOQuery inequality")
    func testQueryInequality() {
        let query1 = QIDOQuery().patientName("Smith")
        let query2 = QIDOQuery().patientName("Jones")
        
        #expect(query1 != query2)
    }
}

// MARK: - QIDOQueryAttribute Tests

@Suite("QIDOQueryAttribute Tests")
struct QIDOQueryAttributeTests {
    
    @Test("Patient level attributes format")
    func testPatientLevelAttributes() {
        #expect(QIDOQueryAttribute.patientName == "00100010")
        #expect(QIDOQueryAttribute.patientID == "00100020")
        #expect(QIDOQueryAttribute.patientBirthDate == "00100030")
        #expect(QIDOQueryAttribute.patientSex == "00100040")
    }
    
    @Test("Study level attributes format")
    func testStudyLevelAttributes() {
        #expect(QIDOQueryAttribute.studyDate == "00080020")
        #expect(QIDOQueryAttribute.studyTime == "00080030")
        #expect(QIDOQueryAttribute.accessionNumber == "00080050")
        #expect(QIDOQueryAttribute.modality == "00080060")
        #expect(QIDOQueryAttribute.studyDescription == "00081030")
        #expect(QIDOQueryAttribute.studyInstanceUID == "0020000D")
        #expect(QIDOQueryAttribute.studyID == "00200010")
    }
    
    @Test("Series level attributes format")
    func testSeriesLevelAttributes() {
        #expect(QIDOQueryAttribute.seriesInstanceUID == "0020000E")
        #expect(QIDOQueryAttribute.seriesNumber == "00200011")
        #expect(QIDOQueryAttribute.seriesDescription == "0008103E")
        #expect(QIDOQueryAttribute.bodyPartExamined == "00180015")
    }
    
    @Test("Instance level attributes format")
    func testInstanceLevelAttributes() {
        #expect(QIDOQueryAttribute.sopClassUID == "00080016")
        #expect(QIDOQueryAttribute.sopInstanceUID == "00080018")
        #expect(QIDOQueryAttribute.instanceNumber == "00200013")
        #expect(QIDOQueryAttribute.numberOfFrames == "00280008")
        #expect(QIDOQueryAttribute.rows == "00280010")
        #expect(QIDOQueryAttribute.columns == "00280011")
    }
}
