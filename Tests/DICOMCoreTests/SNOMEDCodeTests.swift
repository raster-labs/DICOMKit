import Testing
@testable import DICOMCore

// MARK: - SNOMEDCode Tests

@Suite("SNOMEDCode Tests")
struct SNOMEDCodeTests {
    
    @Test("Basic creation")
    func testBasicCreation() {
        let code = SNOMEDCode(conceptId: "10200004", displayName: "Liver")
        
        #expect(code.conceptId == "10200004")
        #expect(code.displayName == "Liver")
        #expect(code.concept.codingSchemeDesignator == "SCT")
    }
    
    @Test("Creation from CodedConcept - valid SNOMED")
    func testCreationFromCodedConcept() {
        let concept = CodedConcept(codeValue: "12345", scheme: .SCT, codeMeaning: "Test")
        let code = SNOMEDCode(concept: concept)
        
        #expect(code != nil)
        #expect(code?.conceptId == "12345")
    }
    
    @Test("Creation from CodedConcept - legacy SRT")
    func testCreationFromLegacySRT() {
        let concept = CodedConcept(codeValue: "12345", scheme: .SRT, codeMeaning: "Test")
        let code = SNOMEDCode(concept: concept)
        
        #expect(code != nil) // SRT is also SNOMED
    }
    
    @Test("Creation from CodedConcept - non-SNOMED returns nil")
    func testCreationFromNonSNOMED() {
        let concept = CodedConcept(codeValue: "12345", scheme: .DCM, codeMeaning: "Test")
        let code = SNOMEDCode(concept: concept)
        
        #expect(code == nil)
    }
    
    @Test("Description format")
    func testDescription() {
        let code = SNOMEDCode.liver
        #expect(code.description.contains("10200004"))
        #expect(code.description.contains("SCT"))
    }
    
    // MARK: - Anatomical Locations
    
    @Test("Anatomical location codes - organs")
    func testAnatomicalOrgans() {
        #expect(SNOMEDCode.brain.conceptId == "12738006")
        #expect(SNOMEDCode.heart.conceptId == "80891009")
        #expect(SNOMEDCode.liver.conceptId == "10200004")
        #expect(SNOMEDCode.kidney.conceptId == "64033007")
        #expect(SNOMEDCode.lung.conceptId == "39607008")
        #expect(SNOMEDCode.spleen.conceptId == "78961009")
        #expect(SNOMEDCode.pancreas.conceptId == "15776009")
    }
    
    @Test("Anatomical location codes - body regions")
    func testAnatomicalRegions() {
        #expect(SNOMEDCode.head.conceptId == "69536005")
        #expect(SNOMEDCode.neck.conceptId == "45048000")
        #expect(SNOMEDCode.chest.conceptId == "51185008")
        #expect(SNOMEDCode.abdomen.conceptId == "818983003")
        #expect(SNOMEDCode.pelvis.conceptId == "816092008")
        #expect(SNOMEDCode.spine.conceptId == "421060004")
    }
    
    @Test("Anatomical location codes - lateralized organs")
    func testLateralizedOrgans() {
        #expect(SNOMEDCode.rightLung.conceptId == "3341006")
        #expect(SNOMEDCode.leftLung.conceptId == "44029006")
        #expect(SNOMEDCode.rightKidney.conceptId == "9846003")
        #expect(SNOMEDCode.leftKidney.conceptId == "18639004")
        #expect(SNOMEDCode.rightBreast.conceptId == "73056007")
        #expect(SNOMEDCode.leftBreast.conceptId == "80248007")
    }
    
    // MARK: - Laterality
    
    @Test("Laterality codes")
    func testLaterality() {
        #expect(SNOMEDCode.right.conceptId == "24028007")
        #expect(SNOMEDCode.left.conceptId == "7771000")
        #expect(SNOMEDCode.bilateral.conceptId == "51440002")
        #expect(SNOMEDCode.unilateral.conceptId == "66459002")
        #expect(SNOMEDCode.midline.conceptId == "260528009")
    }
    
    // MARK: - Common Findings
    
    @Test("Finding codes - general")
    func testFindingCodes() {
        #expect(SNOMEDCode.mass.conceptId == "4147007")
        #expect(SNOMEDCode.lesion.conceptId == "52988006")
        #expect(SNOMEDCode.nodule.conceptId == "27925004")
        #expect(SNOMEDCode.cyst.conceptId == "441457006")
        #expect(SNOMEDCode.calcification.conceptId == "36222007")
        #expect(SNOMEDCode.hemorrhage.conceptId == "50960005")
        #expect(SNOMEDCode.edema.conceptId == "267038008")
        #expect(SNOMEDCode.fracture.conceptId == "125605004")
    }
    
    @Test("Finding codes - severity")
    func testSeverityCodes() {
        #expect(SNOMEDCode.mild.conceptId == "255604002")
        #expect(SNOMEDCode.moderate.conceptId == "6736007")
        #expect(SNOMEDCode.severe.conceptId == "24484000")
    }
    
    @Test("Finding codes - qualifiers")
    func testQualifierCodes() {
        #expect(SNOMEDCode.present.conceptId == "52101004")
        #expect(SNOMEDCode.absent.conceptId == "2667000")
        #expect(SNOMEDCode.unknown.conceptId == "261665006")
        #expect(SNOMEDCode.increased.conceptId == "35105006")
        #expect(SNOMEDCode.decreased.conceptId == "1250004")
        #expect(SNOMEDCode.unchanged.conceptId == "260388006")
    }
    
    // MARK: - Procedures
    
    @Test("Procedure codes")
    func testProcedureCodes() {
        #expect(SNOMEDCode.computedTomography.conceptId == "77477000")
        #expect(SNOMEDCode.magneticResonanceImaging.conceptId == "113091000")
        #expect(SNOMEDCode.radiography.conceptId == "363680008")
        #expect(SNOMEDCode.ultrasonography.conceptId == "16310003")
        #expect(SNOMEDCode.positronEmissionTomography.conceptId == "82918005")
        #expect(SNOMEDCode.mammography.conceptId == "71651007")
    }
    
    // MARK: - CodedConcept Convenience
    
    @Test("CodedConcept to SNOMED conversion")
    func testCodedConceptToSNOMED() {
        let concept = CodedConcept(snomed: SNOMEDCode.liver)
        
        #expect(concept.codeValue == "10200004")
        #expect(concept.codingSchemeDesignator == "SCT")
        #expect(concept.isSNOMED)
    }
    
    @Test("CodedConcept asSNOMED property")
    func testCodedConceptAsSNOMED() {
        let sctConcept = CodedConcept(codeValue: "10200004", scheme: .SCT, codeMeaning: "Liver")
        let dcmConcept = CodedConcept(codeValue: "121071", scheme: .DCM, codeMeaning: "Finding")
        
        #expect(sctConcept.asSNOMED != nil)
        #expect(dcmConcept.asSNOMED == nil)
    }
    
    // MARK: - Equatable / Hashable
    
    @Test("Equatable conformance")
    func testEquatable() {
        let code1 = SNOMEDCode(conceptId: "10200004", displayName: "Liver")
        let code2 = SNOMEDCode.liver
        let code3 = SNOMEDCode.brain
        
        #expect(code1 == code2)
        #expect(code1 != code3)
    }
    
    @Test("Hashable conformance")
    func testHashable() {
        let code1 = SNOMEDCode.liver
        let code2 = SNOMEDCode(conceptId: "10200004", displayName: "Liver")
        
        var set = Set<SNOMEDCode>()
        set.insert(code1)
        set.insert(code2)
        
        #expect(set.count == 1)
    }
}

// MARK: - Measurement concepts (P9, PS3.16 2026a)

@Suite("SNOMEDCode measurement concepts vs PS3.16 2026a")
struct SNOMEDMeasurementConceptTests {
    @Test("Concept IDs and names match the PS3.16 2026a context groups", arguments: [
        (SNOMEDCode.diameter, "81827009", "Diameter"),
        (SNOMEDCode.longAxis, "103339001", "Long Axis"),
        (SNOMEDCode.shortAxis, "103340004", "Short Axis"),
        (SNOMEDCode.perpendicularAxis, "131189007", "Perpendicular Axis"),
        (SNOMEDCode.length, "410668003", "Length"),
        (SNOMEDCode.width, "103355008", "Width"),
        (SNOMEDCode.area, "42798000", "Area"),
        (SNOMEDCode.volume, "118565006", "Volume"),
        (SNOMEDCode.circumference, "74551000", "Circumference"),
        (SNOMEDCode.perimeter, "131191004", "Perimeter"),
        (SNOMEDCode.mode, "373100007", "Mode"),
        (SNOMEDCode.unchanged, "260388006", "Unchanged"),
    ])
    func testConcept(entry: (SNOMEDCode, String, String)) {
        let (code, id, name) = entry
        #expect(code.conceptId == id)
        #expect(code.displayName == name)
        #expect(code.concept.codingSchemeDesignator == "SCT")
    }
}
