import Testing
@testable import DICOMCore

// MARK: - SRDocumentType Tests

@Suite("SRDocumentType Tests")
struct SRDocumentTypeTests {
    
    // MARK: - SOP Class UID Tests
    
    @Test("Basic Text SR SOP Class UID")
    func testBasicTextSRUID() {
        #expect(SRDocumentType.basicTextSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.11")
    }
    
    @Test("Enhanced SR SOP Class UID")
    func testEnhancedSRUID() {
        #expect(SRDocumentType.enhancedSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.22")
    }
    
    @Test("Comprehensive SR SOP Class UID")
    func testComprehensiveSRUID() {
        #expect(SRDocumentType.comprehensiveSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.33")
    }
    
    @Test("Comprehensive 3D SR SOP Class UID")
    func testComprehensive3DSRUID() {
        #expect(SRDocumentType.comprehensive3DSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.34")
    }
    
    @Test("Extensible SR SOP Class UID")
    func testExtensibleSRUID() {
        #expect(SRDocumentType.extensibleSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.35")
    }
    
    @Test("Key Object Selection Document SOP Class UID")
    func testKeyObjectSelectionUID() {
        #expect(SRDocumentType.keyObjectSelectionDocument.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.59")
    }
    
    @Test("All CAD SR SOP Class UIDs")
    func testCADSRUIDs() {
        #expect(SRDocumentType.mammographyCADSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.50")
        #expect(SRDocumentType.chestCADSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.65")
        #expect(SRDocumentType.colonCADSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.69")
    }
    
    @Test("Radiation Dose SR SOP Class UIDs")
    func testRadiationDoseSRUIDs() {
        #expect(SRDocumentType.xRayRadiationDoseSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.67")
        #expect(SRDocumentType.enhancedXRayRadiationDoseSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.76")
        #expect(SRDocumentType.radiopharmaceuticalRadiationDoseSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.68")
        #expect(SRDocumentType.patientRadiationDoseSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.73")
    }
    
    @Test("Other SR SOP Class UIDs")
    func testOtherSRUIDs() {
        #expect(SRDocumentType.acquisitionContextSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.71")
        #expect(SRDocumentType.simplifiedAdultEchoSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.72")
        #expect(SRDocumentType.implantationPlanSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.70")
        #expect(SRDocumentType.plannedImagingAgentAdministrationSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.74")
        #expect(SRDocumentType.performedImagingAgentAdministrationSR.sopClassUID == "1.2.840.10008.5.1.4.1.1.88.75")
    }
    
    // MARK: - Display Name Tests
    
    @Test("Display names are non-empty")
    func testDisplayNamesNonEmpty() {
        let allTypes: [SRDocumentType] = [
            .basicTextSR, .enhancedSR, .comprehensiveSR, .comprehensive3DSR,
            .extensibleSR, .keyObjectSelectionDocument, .mammographyCADSR,
            .chestCADSR, .colonCADSR, .xRayRadiationDoseSR, .enhancedXRayRadiationDoseSR,
            .radiopharmaceuticalRadiationDoseSR, .patientRadiationDoseSR,
            .acquisitionContextSR, .simplifiedAdultEchoSR, .implantationPlanSR,
            .plannedImagingAgentAdministrationSR, .performedImagingAgentAdministrationSR
        ]
        
        for docType in allTypes {
            #expect(docType.displayName.isEmpty == false)
        }
    }
    
    @Test("Display name examples")
    func testDisplayNameExamples() {
        #expect(SRDocumentType.basicTextSR.displayName == "Basic Text SR")
        #expect(SRDocumentType.comprehensiveSR.displayName == "Comprehensive SR")
        #expect(SRDocumentType.keyObjectSelectionDocument.displayName == "Key Object Selection Document")
    }
    
    // MARK: - Content Item Type Constraints Tests
    
    @Test("Basic Text SR allowed value types")
    func testBasicTextSRAllowedTypes() {
        let allowed = SRDocumentType.basicTextSR.allowedValueTypes
        
        #expect(allowed.contains(.text))
        #expect(allowed.contains(.code))
        #expect(allowed.contains(.container))
        #expect(allowed.contains(.image))
        
        // Basic Text SR does NOT support NUM
        #expect(allowed.contains(.num) == false)
        // Basic Text SR does NOT support SCOORD
        #expect(allowed.contains(.scoord) == false)
    }
    
    @Test("Enhanced SR adds NUM support")
    func testEnhancedSRAddsNum() {
        let basicAllowed = SRDocumentType.basicTextSR.allowedValueTypes
        let enhancedAllowed = SRDocumentType.enhancedSR.allowedValueTypes
        
        #expect(basicAllowed.contains(.num) == false)
        #expect(enhancedAllowed.contains(.num) == true)
    }
    
    @Test("Comprehensive SR adds SCOORD and TCOORD")
    func testComprehensiveSRAddsScoord() {
        let allowed = SRDocumentType.comprehensiveSR.allowedValueTypes
        
        #expect(allowed.contains(.scoord))
        #expect(allowed.contains(.tcoord))
        
        // But not SCOORD3D
        #expect(allowed.contains(.scoord3D) == false)
    }
    
    @Test("Comprehensive 3D SR adds SCOORD3D")
    func testComprehensive3DSRAddsScoord3D() {
        let allowed = SRDocumentType.comprehensive3DSR.allowedValueTypes
        
        #expect(allowed.contains(.scoord3D))
        
        // Has all value types
        #expect(allowed == Set(ContentItemValueType.allCases).subtracting([.table]))
    }
    
    @Test("Key Object Selection limited types")
    func testKeyObjectSelectionLimitedTypes() {
        let allowed = SRDocumentType.keyObjectSelectionDocument.allowedValueTypes
        
        #expect(allowed.contains(.text))
        #expect(allowed.contains(.code))
        #expect(allowed.contains(.image))
        #expect(allowed.contains(.composite))
        #expect(allowed.contains(.container))
        
        // Limited set - no NUM or coordinates
        #expect(allowed.contains(.num) == false)
        #expect(allowed.contains(.scoord) == false)
    }
    
    @Test("allows method")
    func testAllowsMethod() {
        #expect(SRDocumentType.basicTextSR.allows(.text) == true)
        #expect(SRDocumentType.basicTextSR.allows(.num) == false)
        #expect(SRDocumentType.enhancedSR.allows(.num) == true)
        #expect(SRDocumentType.comprehensive3DSR.allows(.scoord3D) == true)
    }
    
    // MARK: - Factory Method Tests
    
    @Test("from sopClassUID - valid UIDs")
    func testFromSOPClassUIDValid() {
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11") == .basicTextSR)
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.22") == .enhancedSR)
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.33") == .comprehensiveSR)
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.34") == .comprehensive3DSR)
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.35") == .extensibleSR)
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.59") == .keyObjectSelectionDocument)
    }
    
    @Test("from sopClassUID - invalid UID")
    func testFromSOPClassUIDInvalid() {
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.2") == nil) // CT Storage
        #expect(SRDocumentType.from(sopClassUID: "invalid") == nil)
        #expect(SRDocumentType.from(sopClassUID: "") == nil)
    }
    
    @Test("isSRDocument static method")
    func testIsSRDocument() {
        #expect(SRDocumentType.isSRDocument(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11") == true)
        #expect(SRDocumentType.isSRDocument(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.33") == true)
        #expect(SRDocumentType.isSRDocument(sopClassUID: "1.2.840.10008.5.1.4.1.1.2") == false)
    }
    
    // MARK: - All SOP Class UIDs Tests
    
    @Test("allSOPClassUIDs contains all document types")
    func testAllSOPClassUIDsCount() {
        // 20 document types defined (PS3.6 2026a Table A-1, current SR Storage SOP Classes)
        #expect(SRDocumentType.allSOPClassUIDs.count == 20)
    }
    
    @Test("allSOPClassUIDs contains specific UIDs")
    func testAllSOPClassUIDsContains() {
        let allUIDs = SRDocumentType.allSOPClassUIDs
        
        #expect(allUIDs.contains("1.2.840.10008.5.1.4.1.1.88.11"))
        #expect(allUIDs.contains("1.2.840.10008.5.1.4.1.1.88.33"))
        #expect(allUIDs.contains("1.2.840.10008.5.1.4.1.1.88.59"))
    }
    
    // MARK: - Description Tests
    
    @Test("description returns display name")
    func testDescription() {
        #expect(SRDocumentType.basicTextSR.description == "Basic Text SR")
        #expect(SRDocumentType.comprehensiveSR.description == "Comprehensive SR")
    }
    
    // MARK: - Equatable and Hashable Tests
    
    @Test("Equatable conformance")
    func testEquatable() {
        #expect(SRDocumentType.basicTextSR == SRDocumentType.basicTextSR)
        #expect(SRDocumentType.basicTextSR != SRDocumentType.enhancedSR)
    }
    
    @Test("Hashable conformance")
    func testHashable() {
        var set = Set<SRDocumentType>()
        set.insert(.basicTextSR)
        set.insert(.basicTextSR)
        set.insert(.enhancedSR)
        
        #expect(set.count == 2)
    }

    // MARK: - PS3.3 2026a A.35 Value Type constraints

    private static let standardValueTypes: [(SRDocumentType, Set<ContentItemValueType>)] = [
        (SRDocumentType.basicTextSR, [.text, .code, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .container]),  // A.35.1
        (SRDocumentType.enhancedSR, [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .tcoord, .container]),  // A.35.2
        (SRDocumentType.comprehensiveSR, [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .tcoord, .container]),  // A.35.3
        (SRDocumentType.comprehensive3DSR, [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .scoord3D, .tcoord, .container]),  // A.35.13
        (SRDocumentType.extensibleSR, Set(ContentItemValueType.allCases)),  // A.35.15
        (SRDocumentType.keyObjectSelectionDocument, [.text, .code, .uidref, .pname, .composite, .image, .waveform, .container]),  // A.35.4
        (SRDocumentType.mammographyCADSR, [.text, .code, .num, .date, .time, .uidref, .pname, .composite, .image, .scoord, .container]),  // A.35.5
        (SRDocumentType.chestCADSR, [.text, .code, .num, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .tcoord, .container]),  // A.35.6
        (SRDocumentType.colonCADSR, [.text, .code, .num, .date, .time, .uidref, .pname, .composite, .image, .waveform, .scoord, .scoord3D, .container]),  // A.35.10 (Table A.35.10-2 targets; TCOORD is only a source)
        (SRDocumentType.xRayRadiationDoseSR, [.text, .code, .num, .datetime, .uidref, .pname, .composite, .image, .container]),  // A.35.8
        (SRDocumentType.enhancedXRayRadiationDoseSR, [.text, .code, .num, .datetime, .uidref, .pname, .composite, .image, .scoord3D, .container, .table]),  // A.35.22
        (SRDocumentType.radiopharmaceuticalRadiationDoseSR, [.text, .code, .num, .datetime, .uidref, .pname, .container]),  // A.35.14
        (SRDocumentType.patientRadiationDoseSR, [.text, .code, .num, .datetime, .uidref, .pname, .composite, .image, .container]),  // A.35.18
        (SRDocumentType.acquisitionContextSR, [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .scoord3D, .container]),  // A.35.16
        (SRDocumentType.simplifiedAdultEchoSR, [.text, .code, .num, .datetime, .uidref, .pname, .image, .waveform, .scoord, .tcoord, .container]),  // A.35.17
        (SRDocumentType.implantationPlanSR, [.text, .code, .num, .date, .uidref, .pname, .composite, .image, .container]),  // A.35.12
        (SRDocumentType.plannedImagingAgentAdministrationSR, [.text, .code, .num, .datetime, .date, .uidref, .pname, .container]),  // A.35.19
        (SRDocumentType.performedImagingAgentAdministrationSR, [.text, .code, .num, .datetime, .date, .uidref, .pname, .composite, .image, .waveform, .container]),  // A.35.20
        (SRDocumentType.procedureLog, [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .composite, .image, .waveform, .container]),  // A.35.7
        (SRDocumentType.waveformAnnotationSR, [.text, .code, .num, .datetime, .date, .time, .uidref, .pname, .waveform, .tcoord, .container]),  // A.35.23
    ]

    @Test("allowedValueTypes equals each IOD's Enumerated Values in PS3.3 2026a A.35",
          arguments: standardValueTypes)
    func testAllowedValueTypesMatchStandard(entry: (SRDocumentType, Set<ContentItemValueType>)) {
        #expect(entry.0.allowedValueTypes == entry.1, "\(entry.0)")
    }

    @Test("Procedure Log and Waveform Annotation SR are recognized")
    func testNewSOPClasses() {
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.40") == .procedureLog)
        #expect(SRDocumentType.from(sopClassUID: "1.2.840.10008.5.1.4.1.1.88.77") == .waveformAnnotationSR)
        #expect(SRDocumentType.procedureLog.displayName == "Procedure Log")
    }

    @Test("Retired Trial SR SOP Classes count as SR documents but have no type")
    func testRetiredTrialSOPClasses() {
        for uid in ["1.2.840.10008.5.1.4.1.1.88.1", "1.2.840.10008.5.1.4.1.1.88.4"] {
            #expect(SRDocumentType.isSRDocument(sopClassUID: uid))
            #expect(SRDocumentType.from(sopClassUID: uid) == nil)
        }
    }
}
