import Testing
import Foundation
@testable import DICOMCore

// MARK: - CodingScheme Tests

@Suite("CodingScheme Tests")
struct CodingSchemeTests {
    
    @Test("Basic creation")
    func testBasicCreation() {
        let scheme = CodingScheme(
            designator: "TEST",
            name: "Test Coding Scheme"
        )
        
        #expect(scheme.designator == "TEST")
        #expect(scheme.name == "Test Coding Scheme")
        #expect(scheme.uid == nil)
        #expect(scheme.version == nil)
        #expect(scheme.isExternal == false)
        #expect(scheme.resourceURL == nil)
    }
    
    @Test("Creation with all fields")
    func testCreationWithAllFields() {
        let url = URL(string: "https://example.org/scheme")
        let scheme = CodingScheme(
            designator: "TEST",
            name: "Test Coding Scheme",
            uid: "1.2.3.4.5",
            version: "2024.01",
            isExternal: true,
            resourceURL: url
        )
        
        #expect(scheme.uid == "1.2.3.4.5")
        #expect(scheme.version == "2024.01")
        #expect(scheme.isExternal == true)
        #expect(scheme.resourceURL == url)
    }
    
    @Test("Well-known DICOM scheme")
    func testDICOMScheme() {
        let dcm = CodingScheme.dicom
        
        #expect(dcm.designator == "DCM")
        #expect(dcm.name == "DICOM Controlled Terminology")
        #expect(dcm.uid == "1.2.840.10008.2.16.4")
        #expect(dcm.isExternal == false)
    }
    
    @Test("Well-known SNOMED CT scheme")
    func testSNOMEDCTScheme() {
        let sct = CodingScheme.snomedCT
        
        #expect(sct.designator == "SCT")
        #expect(sct.name == "SNOMED Clinical Terms")
        #expect(sct.uid == "2.16.840.1.113883.6.96")
        #expect(sct.isExternal == true)
    }
    
    @Test("Well-known LOINC scheme")
    func testLOINCScheme() {
        let loinc = CodingScheme.loinc
        
        #expect(loinc.designator == "LN")
        #expect(loinc.name == "Logical Observation Identifiers Names and Codes")
        #expect(loinc.uid == "2.16.840.1.113883.6.1")
    }
    
    @Test("Well-known UCUM scheme")
    func testUCUMScheme() {
        let ucum = CodingScheme.ucum
        
        #expect(ucum.designator == "UCUM")
        #expect(ucum.uid == "2.16.840.1.113883.6.8")
    }
    
    @Test("Validation - valid scheme")
    func testValidation() {
        let valid = CodingScheme(designator: "TEST", name: "Test")
        #expect(valid.isValid)
        #expect(valid.validate().isEmpty)
    }
    
    @Test("Validation - empty designator")
    func testValidationEmptyDesignator() {
        let invalid = CodingScheme(designator: "", name: "Test")
        #expect(!invalid.isValid)
        #expect(invalid.validate().contains(.emptyDesignator))
    }
    
    @Test("Validation - designator too long")
    func testValidationDesignatorTooLong() {
        let invalid = CodingScheme(designator: "TOOLONGDESIGNATOR", name: "Test")
        let errors = invalid.validate()
        #expect(errors.contains { 
            if case .designatorTooLong = $0 { return true }
            return false
        })
    }
    
    @Test("Validation - empty name")
    func testValidationEmptyName() {
        let invalid = CodingScheme(designator: "TEST", name: "")
        #expect(!invalid.isValid)
        #expect(invalid.validate().contains(.emptyName))
    }
    
    @Test("Description format")
    func testDescription() {
        let scheme = CodingScheme(designator: "SCT", name: "SNOMED", version: "2024")
        #expect(scheme.description.contains("SCT"))
        #expect(scheme.description.contains("SNOMED"))
        #expect(scheme.description.contains("v2024"))
    }
    
    @Test("Equatable conformance")
    func testEquatable() {
        let scheme1 = CodingScheme(designator: "TEST", name: "Test")
        let scheme2 = CodingScheme(designator: "TEST", name: "Test")
        let scheme3 = CodingScheme(designator: "TEST", name: "Different")
        
        #expect(scheme1 == scheme2)
        #expect(scheme1 != scheme3)
    }
    
    @Test("Hashable conformance")
    func testHashable() {
        let scheme1 = CodingScheme(designator: "TEST", name: "Test")
        let scheme2 = CodingScheme(designator: "TEST", name: "Test")
        
        var set = Set<CodingScheme>()
        set.insert(scheme1)
        set.insert(scheme2)
        
        #expect(set.count == 1)
    }
}

// MARK: - CodingSchemeRegistry Tests

@Suite("CodingSchemeRegistry Tests")
struct CodingSchemeRegistryTests {
    
    @Test("Shared instance has well-known schemes")
    func testSharedHasWellKnownSchemes() {
        let registry = CodingSchemeRegistry.shared
        
        #expect(registry.scheme(forDesignator: "DCM") != nil)
        #expect(registry.scheme(forDesignator: "SCT") != nil)
        #expect(registry.scheme(forDesignator: "LN") != nil)
        #expect(registry.scheme(forDesignator: "UCUM") != nil)
        #expect(registry.scheme(forDesignator: "RADLEX") != nil)
    }
    
    @Test("Lookup by designator")
    func testLookupByDesignator() {
        let registry = CodingSchemeRegistry.shared
        
        let dcm = registry.scheme(forDesignator: "DCM")
        #expect(dcm?.designator == "DCM")
        
        let unknown = registry.scheme(forDesignator: "UNKNOWN")
        #expect(unknown == nil)
    }
    
    @Test("Register custom scheme")
    func testRegisterCustomScheme() {
        let registry = CodingSchemeRegistry()
        let custom = CodingScheme(designator: "99CUSTOM", name: "Custom Scheme")
        
        registry.register(custom)
        
        #expect(registry.isRegistered("99CUSTOM"))
        #expect(registry.scheme(forDesignator: "99CUSTOM")?.name == "Custom Scheme")
    }
    
    @Test("Unregister scheme")
    func testUnregisterScheme() {
        let registry = CodingSchemeRegistry()
        let custom = CodingScheme(designator: "99TEST", name: "Test")
        registry.register(custom)
        
        let removed = registry.unregister("99TEST")
        
        #expect(removed?.designator == "99TEST")
        #expect(!registry.isRegistered("99TEST"))
    }
    
    @Test("All schemes list")
    func testAllSchemes() {
        let registry = CodingSchemeRegistry.shared
        let all = registry.allSchemes
        
        #expect(all.count >= 10) // Should have at least the well-known schemes
        #expect(all.contains(where: { $0.designator == "DCM" }))
    }
}

// MARK: - CodingSchemeDesignator Extension Tests

@Suite("CodingSchemeDesignator Scheme Extension Tests")
struct CodingSchemeDesignatorSchemeExtensionTests {
    
    @Test("Get full scheme from designator")
    func testGetSchemeFromDesignator() {
        let dcmScheme = CodingSchemeDesignator.DCM.scheme
        #expect(dcmScheme != nil)
        #expect(dcmScheme?.name == "DICOM Controlled Terminology")
        
        let sctScheme = CodingSchemeDesignator.SCT.scheme
        #expect(sctScheme != nil)
        #expect(sctScheme?.name == "SNOMED Clinical Terms")
    }
}

// MARK: - PS3.16 2026a Table 8-1

@Suite("CodingScheme registry vs PS3.16 2026a Table 8-1")
struct CodingSchemeTable81Tests {

    /// (constant, designator, Coding Scheme UID) as PS3.16 2026a Table 8-1 lists them.
    private static let table81: [(CodingScheme, String, String)] = [
        (.dicom, "DCM", "1.2.840.10008.2.16.4"),
        (.snomedCT, "SCT", "2.16.840.1.113883.6.96"),
        (.snomedRT, "SRT", "2.16.840.1.113883.6.96"),
        (.loinc, "LN", "2.16.840.1.113883.6.1"),
        (.radlex, "RADLEX", "2.16.840.1.113883.6.256"),
        (.ucum, "UCUM", "2.16.840.1.113883.6.8"),
        (.fma, "FMA", "2.16.840.1.113883.6.119"),
        (.icd10, "I10", "2.16.840.1.113883.6.3"),
        (.icd10CM, "I10C", "2.16.840.1.113883.6.90"),
        (.icd10PCS, "I10P", "2.16.840.1.113883.6.4"),
        (.nciThesaurus, "NCIt", "2.16.840.1.113883.3.26.1.1"),
        (.umls, "UMLS", "2.16.840.1.113883.6.86"),
        (.acr, "ACR", "2.16.840.1.113883.6.76"),
    ]

    @Test("Designator and UID match Table 8-1", arguments: table81)
    func testDesignatorAndUID(entry: (CodingScheme, String, String)) {
        let (scheme, designator, uid) = entry
        #expect(scheme.designator == designator)
        #expect(scheme.uid == uid)
        #expect(CodingSchemeRegistry.shared.scheme(forDesignator: designator)?.uid == uid)
    }

    @Test("ICD-10 and ICD-10-CM are distinct schemes")
    func testICD10Distinct() {
        #expect(CodingScheme.icd10.designator != CodingScheme.icd10CM.designator)
        #expect(CodingSchemeDesignator.ICD10.rawValue == "I10")
        #expect(CodingSchemeDesignator.ICD10CM.rawValue == "I10C")
    }
}
