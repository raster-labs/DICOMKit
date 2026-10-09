import Testing
@testable import DICOMCore

// MARK: - DICOMCode Tests

@Suite("DICOMCode Tests")
struct DICOMCodeTests {
    
    @Test("Basic creation")
    func testBasicCreation() {
        let code = DICOMCode(codeValue: "121071", codeMeaning: "Finding")
        
        #expect(code.codeValue == "121071")
        #expect(code.codeMeaning == "Finding")
        #expect(code.concept.codingSchemeDesignator == "DCM")
    }
    
    @Test("Creation from CodedConcept - valid DCM")
    func testCreationFromCodedConcept() {
        let concept = CodedConcept(codeValue: "121071", scheme: .DCM, codeMeaning: "Finding")
        let code = DICOMCode(concept: concept)
        
        #expect(code != nil)
        #expect(code?.codeValue == "121071")
    }
    
    @Test("Creation from CodedConcept - non-DCM returns nil")
    func testCreationFromNonDCM() {
        let concept = CodedConcept(codeValue: "10200004", scheme: .SCT, codeMeaning: "Liver")
        let code = DICOMCode(concept: concept)
        
        #expect(code == nil)
    }
    
    @Test("Description format")
    func testDescription() {
        let code = DICOMCode.finding
        #expect(code.description.contains("121071"))
        #expect(code.description.contains("DCM"))
    }
    
    // MARK: - Constants vs PS3.16 2026a Annex D

    /// Every remaining constant, with its code value and code meaning as PS3.16 2026a
    /// Table D-1 gives them.
    private static let annexD: [(DICOMCode, String, String)] = [
        (DICOMCode.addendum, "121078", "Addendum"),
        (DICOMCode.attenuationCoefficient, "112031", "Attenuation Coefficient"),
        (DICOMCode.chestCADReport, "112000", "Chest CAD Report"),
        (DICOMCode.clinicalHistory, "121060", "History"),
        (DICOMCode.colonCADReport, "112220", "Colon CAD Report"),
        (DICOMCode.conclusion, "121077", "Conclusion"),
        (DICOMCode.countryOfLanguage, "121046", "Country of Language"),
        (DICOMCode.ctDoseLengthProductTotal, "113813", "CT Dose Length Product Total"),
        (DICOMCode.currentProcedureDescriptions, "121064", "Current Procedure Descriptions"),
        (DICOMCode.depth, "111020", "Depth"),
        (DICOMCode.derivation, "121401", "Derivation"),
        (DICOMCode.derivedImagingMeasurements, "126011", "Derived Imaging Measurements"),
        (DICOMCode.device, "121007", "Device"),
        (DICOMCode.deviceObserverManufacturer, "121014", "Device Observer Manufacturer"),
        (DICOMCode.deviceObserverModelName, "121015", "Device Observer Model Name"),
        (DICOMCode.deviceObserverName, "121013", "Device Observer Name"),
        (DICOMCode.deviceObserverSerialNumber, "121016", "Device Observer Serial Number"),
        (DICOMCode.deviceObserverUID, "121012", "Device Observer UID"),
        (DICOMCode.finding, "121071", "Finding"),
        (DICOMCode.height, "121207", "Height"),
        (DICOMCode.imageRegion, "111030", "Image Region"),
        (DICOMCode.imagingMeasurements, "126010", "Imaging Measurements"),
        (DICOMCode.impression, "121073", "Impression"),
        (DICOMCode.languageOfContentItemAndDescendants, "121049", "Language of Content Item and Descendants"),
        (DICOMCode.mammographyCADReport, "111036", "Mammography CAD Report"),
        (DICOMCode.measurementGroup, "125007", "Measurement Group"),
        (DICOMCode.median, "130290", "Median"),
        (DICOMCode.observerType, "121005", "Observer Type"),
        (DICOMCode.person, "121006", "Person"),
        (DICOMCode.personObserverName, "121008", "Person Observer Name"),
        (DICOMCode.probabilityOfCancer, "111047", "Probability of cancer"),
        (DICOMCode.procedureReported, "121058", "Procedure reported"),
        (DICOMCode.recommendation, "121075", "Recommendation"),
        (DICOMCode.request, "121062", "Request"),
        (DICOMCode.series, "113015", "Series"),
        (DICOMCode.sourceImageForSegmentation, "121233", "Source image for segmentation"),
        (DICOMCode.sourceOfMeasurement, "121112", "Source of Measurement"),
        (DICOMCode.sourceSeriesForSegmentation, "121232", "Source series for segmentation"),
        (DICOMCode.standardDeviation, "113061", "Standard Deviation"),
        (DICOMCode.study, "113014", "Study"),
        (DICOMCode.subjectBirthDate, "121031", "Subject Birth Date"),
        (DICOMCode.subjectBreed, "121035", "Subject Breed"),
        (DICOMCode.subjectID, "121030", "Subject ID"),
        (DICOMCode.subjectName, "121029", "Subject Name"),
        (DICOMCode.subjectSex, "121032", "Subject Sex"),
        (DICOMCode.subjectSpecies, "121034", "Subject Species"),
        (DICOMCode.summary, "121111", "Summary"),
        (DICOMCode.trackingIdentifier, "112039", "Tracking Identifier"),
        (DICOMCode.trackingUniqueIdentifier, "112040", "Tracking Unique Identifier"),
        (DICOMCode.xRayRadiationDoseReport, "113701", "X-Ray Radiation Dose Report"),
    ]

    @Test("Every DICOMCode constant carries its Annex D code value and meaning", arguments: annexD)
    func testConstantMatchesAnnexD(entry: (DICOMCode, String, String)) {
        let (code, value, meaning) = entry
        #expect(code.codeValue == value)
        #expect(code.codeMeaning == meaning)
        #expect(code.concept.codingSchemeDesignator == "DCM")
    }

    @Test("No two constants share a code value")
    func testNoDuplicateCodeValues() {
        let values = Self.annexD.map { $0.1 }
        #expect(Set(values).count == values.count)
    }

    @Test("Corrected codes")
    func testCorrectedCodes() {
        #expect(DICOMCode.summary.codeValue == "121111")
        #expect(DICOMCode.impression.codeValue == "121073")
        #expect(DICOMCode.conclusion.codeValue == "121077")
        #expect(DICOMCode.recommendation.codeValue == "121075")
        #expect(DICOMCode.mammographyCADReport.codeValue == "111036")
        #expect(DICOMCode.clinicalHistory.codeMeaning == "History")
        #expect(DICOMCode.imagingMeasurementReport.codeValue == "126000")
    }
    
    // MARK: - CodedConcept Convenience
    
    @Test("CodedConcept to DICOMCode conversion")
    func testCodedConceptToDICOMCode() {
        let concept = CodedConcept(dicomCode: DICOMCode.finding)
        
        #expect(concept.codeValue == "121071")
        #expect(concept.codingSchemeDesignator == "DCM")
        #expect(concept.isDICOMControlled)
    }
    
    @Test("CodedConcept asDICOMCode property")
    func testCodedConceptAsDICOMCode() {
        let dcmConcept = CodedConcept(codeValue: "121071", scheme: .DCM, codeMeaning: "Finding")
        let sctConcept = CodedConcept(codeValue: "10200004", scheme: .SCT, codeMeaning: "Liver")
        
        #expect(dcmConcept.asDICOMCode != nil)
        #expect(sctConcept.asDICOMCode == nil)
    }
    
    // MARK: - Equatable / Hashable
    
    @Test("Equatable conformance")
    func testEquatable() {
        let code1 = DICOMCode(codeValue: "121071", codeMeaning: "Finding")
        let code2 = DICOMCode.finding
        let code3 = DICOMCode.measurementGroup
        
        #expect(code1 == code2)
        #expect(code1 != code3)
    }
    
    @Test("Hashable conformance")
    func testHashable() {
        let code1 = DICOMCode.finding
        let code2 = DICOMCode(codeValue: "121071", codeMeaning: "Finding")
        
        var set = Set<DICOMCode>()
        set.insert(code1)
        set.insert(code2)
        
        #expect(set.count == 1)
    }
}
