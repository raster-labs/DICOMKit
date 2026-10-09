import XCTest
@testable import DICOMCore

final class PrivateTagDictionaryTests: XCTestCase {
    // MARK: - Basic Functionality
    
    func test_init_createsEmptyDictionary() {
        let dict = PrivateTagDictionary()
        
        XCTAssertNil(dict.definition(for: Tag(group: 0x0029, element: 0x1010), creatorID: "TEST"))
    }
    
    func test_init_withDefinitions() {
        let tag = Tag(group: 0x0029, element: 0x1010)
        let def = PrivateTagDefinition(tag: tag, name: "Test Tag", vr: .LO)
        let dict = PrivateTagDictionary(definitions: ["TEST": [tag: def]])
        
        XCTAssertNotNil(dict.definition(for: tag, creatorID: "TEST"))
    }
    
    func test_definition_returnsCorrectDefinition() {
        let tag = Tag(group: 0x0029, element: 0x1010)
        let def = PrivateTagDefinition(tag: tag, name: "Test Tag", vr: .LO, description: "Test description")
        let dict = PrivateTagDictionary(definitions: ["TEST": [tag: def]])
        
        let result = dict.definition(for: tag, creatorID: "TEST")
        
        XCTAssertEqual(result?.tag, tag)
        XCTAssertEqual(result?.name, "Test Tag")
        XCTAssertEqual(result?.vr, .LO)
        XCTAssertEqual(result?.description, "Test description")
    }
    
    func test_vr_returnsCorrectVR() {
        let tag = Tag(group: 0x0029, element: 0x1010)
        let def = PrivateTagDefinition(tag: tag, name: "Test", vr: .CS)
        let dict = PrivateTagDictionary(definitions: ["TEST": [tag: def]])
        
        XCTAssertEqual(dict.vr(for: tag, creatorID: "TEST"), .CS)
    }
    
    func test_name_returnsCorrectName() {
        let tag = Tag(group: 0x0029, element: 0x1010)
        let def = PrivateTagDefinition(tag: tag, name: "Test Name", vr: .LO)
        let dict = PrivateTagDictionary(definitions: ["TEST": [tag: def]])
        
        XCTAssertEqual(dict.name(for: tag, creatorID: "TEST"), "Test Name")
    }
    
    // MARK: - Siemens CSA Dictionary
    
    func test_siemensCSA_hasCSAImageHeaderInfo() {
        let dict = PrivateTagDictionary.siemensCSA
        let tag = Tag(group: 0x0029, element: 0x1010)
        
        let def = dict.definition(for: tag, creatorID: "SIEMENS CSA HEADER")
        
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "CSA Image Header Info")
        XCTAssertEqual(def?.vr, .OB)
    }
    
    func test_siemensCSA_hasCSASeriesHeaderInfo() {
        let dict = PrivateTagDictionary.siemensCSA
        let tag = Tag(group: 0x0029, element: 0x1020)
        
        let def = dict.definition(for: tag, creatorID: "SIEMENS CSA HEADER")
        
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "CSA Series Header Info")
    }
    
    // MARK: - Siemens MR Dictionary
    
    func test_siemensMR_hasBValue() {
        let dict = PrivateTagDictionary.siemensMR
        let tag = Tag(group: 0x0019, element: 0x100c)
        
        let def = dict.definition(for: tag, creatorID: "SIEMENS MR HEADER")
        
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "B Value")
        XCTAssertEqual(def?.vr, .IS)
    }
    
    func test_siemensMR_hasDiffusionGradientDirection() {
        let dict = PrivateTagDictionary.siemensMR
        let tag = Tag(group: 0x0019, element: 0x100e)
        
        let def = dict.definition(for: tag, creatorID: "SIEMENS MR HEADER")
        
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "Diffusion Gradient Direction")
        XCTAssertEqual(def?.vr, .FD)
    }

    // MARK: - Cross-check against DCMTK private.dic / GDCM privatedicts.xml (2026-09-25)

    /// (creator, group, element, VR, name) for every built-in definition, as the DCMTK
    /// and GDCM private dictionaries give them.
    private let referenceEntries: [(String, UInt16, UInt16, VR, String)] = [
        ("SIEMENS CSA HEADER", 0x0029, 0x1008, .CS, "CSA Image Header Type"),
        ("SIEMENS CSA HEADER", 0x0029, 0x1009, .LO, "CSA Image Header Version"),
        ("SIEMENS CSA HEADER", 0x0029, 0x1010, .OB, "CSA Image Header Info"),
        ("SIEMENS CSA HEADER", 0x0029, 0x1018, .CS, "CSA Series Header Type"),
        ("SIEMENS CSA HEADER", 0x0029, 0x1019, .LO, "CSA Series Header Version"),
        ("SIEMENS CSA HEADER", 0x0029, 0x1020, .OB, "CSA Series Header Info"),
        ("SIEMENS MR HEADER", 0x0019, 0x100c, .IS, "B Value"),
        ("SIEMENS MR HEADER", 0x0019, 0x100d, .CS, "Diffusion Directionality"),
        ("SIEMENS MR HEADER", 0x0019, 0x100e, .FD, "Diffusion Gradient Direction"),
        ("SIEMENS MR HEADER", 0x0019, 0x100f, .SH, "Gradient Mode"),
        ("GEMS_IDEN_01", 0x0009, 0x1001, .LO, "Full Fidelity"),
        ("GEMS_IDEN_01", 0x0009, 0x1002, .SH, "Suite ID"),
        ("GEMS_IDEN_01", 0x0009, 0x1004, .SH, "Product ID"),
        ("GEMS_ACQU_01", 0x0019, 0x100f, .DS, "Horizontal Frame Of Reference"),
        ("Philips Imaging DD 001", 0x2001, 0x1001, .FL, "Chemical Shift"),
        ("Philips Imaging DD 001", 0x2001, 0x1003, .FL, "Diffusion B-Factor"),
        ("Philips Imaging DD 001", 0x2001, 0x1008, .IS, "Phase Number"),
    ]

    func test_wellKnown_matchesReferenceDictionaries() {
        let dict = PrivateTagDictionary.wellKnown
        for (creator, group, element, vr, name) in referenceEntries {
            let tag = Tag(group: group, element: element)
            let def = dict.definition(for: tag, creatorID: creator)
            XCTAssertNotNil(def, "\(creator) \(tag)")
            XCTAssertEqual(def?.vr, vr, "\(creator) \(tag) VR")
            XCTAssertEqual(def?.name, name, "\(creator) \(tag) name")
        }
    }

    func test_wellKnown_hasNoDefinitionsBeyondTheReferenceList() {
        // Every entry the dictionaries expose must be in the cross-checked list.
        let known = Set(referenceEntries.map { "\($0.0)|\($0.1)|\($0.2)" })
        for dict in [PrivateTagDictionary.siemensCSA, .siemensMR, .geMedical, .geAcquisition, .philipsImaging] {
            for (creator, _, _, _, _) in referenceEntries {
                // Probe the full private block for stray entries.
                for element in UInt16(0x1000)...UInt16(0x10ff) {
                    for group: UInt16 in [0x0009, 0x0019, 0x0029, 0x2001] {
                        if let def = dict.definition(for: Tag(group: group, element: element), creatorID: creator) {
                            XCTAssertTrue(known.contains("\(creator)|\(group)|\(element)"), "unexpected \(creator) \(def.tag) \(def.name)")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - GE Medical Dictionary
    
    func test_geMedical_hasProductID() {
        let dict = PrivateTagDictionary.geMedical
        let tag = Tag(group: 0x0009, element: 0x1004)
        
        let def = dict.definition(for: tag, creatorID: "GEMS_IDEN_01")
        
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "Product ID")
    }
    
    // MARK: - Philips Dictionary
    
    func test_philipsImaging_hasChemicalShift() {
        let dict = PrivateTagDictionary.philipsImaging
        let tag = Tag(group: 0x2001, element: 0x1001)
        
        let def = dict.definition(for: tag, creatorID: "Philips Imaging DD 001")
        
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "Chemical Shift")
        XCTAssertEqual(def?.vr, .FL)
    }
    
    // MARK: - Well-Known Combined Dictionary
    
    func test_wellKnown_includesSiemensTags() {
        let dict = PrivateTagDictionary.wellKnown
        
        XCTAssertNotNil(dict.definition(for: Tag(group: 0x0029, element: 0x1010), creatorID: "SIEMENS CSA HEADER"))
        XCTAssertNotNil(dict.definition(for: Tag(group: 0x0019, element: 0x100c), creatorID: "SIEMENS MR HEADER"))
    }
    
    func test_wellKnown_includesGETags() {
        let dict = PrivateTagDictionary.wellKnown
        
        XCTAssertNotNil(dict.definition(for: Tag(group: 0x0009, element: 0x1004), creatorID: "GEMS_IDEN_01"))
    }
    
    func test_wellKnown_includesPhilipsTags() {
        let dict = PrivateTagDictionary.wellKnown
        
        XCTAssertNotNil(dict.definition(for: Tag(group: 0x2001, element: 0x1003), creatorID: "Philips Imaging DD 001"))
    }
}
