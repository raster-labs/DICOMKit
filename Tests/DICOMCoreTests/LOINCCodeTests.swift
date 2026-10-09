import Testing
@testable import DICOMCore

// MARK: - LOINCCode Tests

@Suite("LOINCCode Tests")
struct LOINCCodeTests {
    
    @Test("Basic creation")
    func testBasicCreation() {
        let code = LOINCCode(loincNum: "29463-7", longCommonName: "Body weight")
        
        #expect(code.loincNum == "29463-7")
        #expect(code.longCommonName == "Body weight")
        #expect(code.concept.codingSchemeDesignator == "LN")
    }
    
    @Test("Creation from CodedConcept - valid LOINC")
    func testCreationFromCodedConcept() {
        let concept = CodedConcept(codeValue: "29463-7", scheme: .LOINC, codeMeaning: "Body weight")
        let code = LOINCCode(concept: concept)
        
        #expect(code != nil)
        #expect(code?.loincNum == "29463-7")
    }
    
    @Test("Creation from CodedConcept - non-LOINC returns nil")
    func testCreationFromNonLOINC() {
        let concept = CodedConcept(codeValue: "12345", scheme: .DCM, codeMeaning: "Test")
        let code = LOINCCode(concept: concept)
        
        #expect(code == nil)
    }
    
    @Test("Description format")
    func testDescription() {
        let code = LOINCCode.bodyWeight
        #expect(code.description.contains("29463-7"))
        #expect(code.description.contains("LN"))
    }
    
    // MARK: - Vital Signs
    
    @Test("Vital sign codes")
    func testVitalSignCodes() {
        #expect(LOINCCode.bodyWeight.loincNum == "29463-7")
        #expect(LOINCCode.bodyHeight.loincNum == "8302-2")
        #expect(LOINCCode.bodyMassIndex.loincNum == "39156-5")
        #expect(LOINCCode.bodyTemperature.loincNum == "8310-5")
        #expect(LOINCCode.heartRate.loincNum == "8867-4")
        #expect(LOINCCode.respiratoryRate.loincNum == "9279-1")
        #expect(LOINCCode.systolicBloodPressure.loincNum == "8480-6")
        #expect(LOINCCode.diastolicBloodPressure.loincNum == "8462-4")
        #expect(LOINCCode.oxygenSaturation.loincNum == "2708-6")
    }
    
    // MARK: - Measurement Type Codes
    
    @Test("Measurement type codes - dimensions")
    func testMeasurementDimensionCodes() {
        #expect(LOINCCode.diameter.loincNum == "33728-7")
        #expect(LOINCCode.width.loincNum == "81190-8")
        #expect(LOINCCode.depth.loincNum == "81191-6")
        #expect(LOINCCode.area.loincNum == "81298-9")
        #expect(LOINCCode.volume.loincNum == "81297-1")
    }
    
    @Test("Measurement type codes - density")
    func testMeasurementDensityCodes() {
        #expect(LOINCCode.meanDensity.loincNum == "89221-2")
        #expect(LOINCCode.maxDensity.loincNum == "89222-0")
        #expect(LOINCCode.minDensity.loincNum == "89223-8")
        #expect(LOINCCode.stdDevDensity.loincNum == "89224-6")
    }
    
    // MARK: - Report Section Codes
    
    @Test("Radiology report section codes")
    func testReportSectionCodes() {
        #expect(LOINCCode.radiologyReport.loincNum == "18748-4")
        #expect(LOINCCode.clinicalInformation.loincNum == "55752-0")
        #expect(LOINCCode.reasonForStudy.loincNum == "18785-6")
        #expect(LOINCCode.findings.loincNum == "59776-5")
        #expect(LOINCCode.impression.loincNum == "19005-8")
        #expect(LOINCCode.recommendation.loincNum == "18783-1")
        #expect(LOINCCode.technique.loincNum == "55111-9")
    }
    
    @Test("Specific report type codes")
    func testSpecificReportCodes() {
        #expect(LOINCCode.ctScanReport.loincNum == "24727-0")
        #expect(LOINCCode.mriReport.loincNum == "24590-2")
        #expect(LOINCCode.mammographyReport.loincNum == "24605-8")
        #expect(LOINCCode.ultrasoundReport.loincNum == "18750-0")
        #expect(LOINCCode.nuclearMedicineReport.loincNum == "18747-6")
        #expect(LOINCCode.petScanReport.loincNum == "44136-0")
        #expect(LOINCCode.chestXRayReport.loincNum == "30746-2")
    }
    
    // MARK: - Document Types
    
    @Test("Document type codes")
    func testDocumentTypeCodes() {
        #expect(LOINCCode.diagnosticImagingStudy.loincNum == "18726-0")
        #expect(LOINCCode.procedureNote.loincNum == "28570-0")
        #expect(LOINCCode.consultationNote.loincNum == "11488-4")
        #expect(LOINCCode.dischargeSummary.loincNum == "18842-5")
        #expect(LOINCCode.progressNote.loincNum == "11506-3")
    }
    
    // MARK: - Laboratory Panel Codes
    
    @Test("Laboratory panel codes")
    func testLaboratoryPanelCodes() {
        #expect(LOINCCode.completeBloodCount.loincNum == "58410-2")
        #expect(LOINCCode.comprehensiveMetabolicPanel.loincNum == "24323-8")
        #expect(LOINCCode.lipidPanel.loincNum == "57698-3")
        #expect(LOINCCode.liverFunctionTests.loincNum == "24325-3")
        #expect(LOINCCode.thyroidPanel.loincNum == "34430-3")
    }
    
    // MARK: - CodedConcept Convenience
    
    @Test("CodedConcept to LOINC conversion")
    func testCodedConceptToLOINC() {
        let concept = CodedConcept(loinc: LOINCCode.bodyWeight)
        
        #expect(concept.codeValue == "29463-7")
        #expect(concept.codingSchemeDesignator == "LN")
        #expect(concept.isLOINC)
    }
    
    @Test("CodedConcept asLOINC property")
    func testCodedConceptAsLOINC() {
        let loincConcept = CodedConcept(codeValue: "29463-7", scheme: .LOINC, codeMeaning: "Body weight")
        let dcmConcept = CodedConcept(codeValue: "121071", scheme: .DCM, codeMeaning: "Finding")
        
        #expect(loincConcept.asLOINC != nil)
        #expect(dcmConcept.asLOINC == nil)
    }
    
    @Test("CodedConcept isLOINC property")
    func testCodedConceptIsLOINC() {
        let loincConcept = CodedConcept(codeValue: "29463-7", scheme: .LOINC, codeMeaning: "Body weight")
        let sctConcept = CodedConcept(codeValue: "10200004", scheme: .SCT, codeMeaning: "Liver")
        
        #expect(loincConcept.isLOINC == true)
        #expect(sctConcept.isLOINC == false)
    }
    
    // MARK: - Equatable / Hashable
    
    @Test("Equatable conformance")
    func testEquatable() {
        let code1 = LOINCCode(loincNum: "29463-7", longCommonName: "Body weight")
        let code2 = LOINCCode.bodyWeight
        let code3 = LOINCCode.bodyHeight
        
        #expect(code1 == code2)
        #expect(code1 != code3)
    }
    
    @Test("Hashable conformance")
    func testHashable() {
        let code1 = LOINCCode.bodyWeight
        let code2 = LOINCCode(loincNum: "29463-7", longCommonName: "Body weight")
        
        var set = Set<LOINCCode>()
        set.insert(code1)
        set.insert(code2)
        
        #expect(set.count == 1)
    }
}

// MARK: - Meanings cross-checked with PS3.16 2026a

@Suite("LOINCCode meanings vs PS3.16 2026a")
struct LOINCCodePS316Tests {
    @Test("Codes that PS3.16 uses carry the LOINC concept PS3.16 names", arguments: [
        (LOINCCode.radiologyReport, "18748-4", "Diagnostic imaging study"),
        (LOINCCode.technique, "55111-9", "Current imaging procedure descriptions"),
        (LOINCCode.mriReport, "24590-2", "MR Brain"),
        (LOINCCode.ultrasoundReport, "18750-0", "Cardiac electrophysiology study"),
        (LOINCCode.impression, "19005-8", "Impression"),
        (LOINCCode.recommendation, "18783-1", "Recommendation"),
    ])
    func testMeaning(entry: (LOINCCode, String, String)) {
        let (code, number, name) = entry
        #expect(code.loincNum == number)
        #expect(code.longCommonName == name)
    }
}
