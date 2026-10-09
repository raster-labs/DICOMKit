import Testing
@testable import DICOMCore

// MARK: - ContextGroup Tests

@Suite("ContextGroup Tests")
struct ContextGroupTests {

    @Test("Basic creation")
    func testBasicCreation() {
        let members = [
            CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right"),
            CodedConcept(codeValue: "7771000", scheme: .SCT, codeMeaning: "Left")
        ]
        let group = ContextGroup(cid: 244, name: "Laterality", isExtensible: false, version: "2024", members: members)
        #expect(group.cid == 244)
        #expect(group.name == "Laterality")
        #expect(group.isExtensible == false)
        #expect(group.version == "2024")
        #expect(group.members.count == 2)
    }

    @Test("Default extensibility is true")
    func testDefaultExtensibility() {
        let group = ContextGroup(cid: 999, name: "Test", members: [])
        #expect(group.isExtensible == true)
    }

    @Test("Description format")
    func testDescription() {
        let group = ContextGroup.laterality
        #expect(group.description.contains("CID 244"))
        #expect(group.description.contains("Laterality"))
        #expect(group.description.contains("non-extensible"))
    }

    @Test("Contains member concept")
    func testContainsMember() {
        let right = CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right")
        let unknown = CodedConcept(codeValue: "000000", scheme: .SCT, codeMeaning: "Unknown")
        #expect(ContextGroup.laterality.contains(right))
        #expect(!ContextGroup.laterality.contains(unknown))
    }

    // MARK: - Validation

    @Test("Validation - valid member")
    func testValidationValidMember() {
        let right = CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right")
        let result = ContextGroup.laterality.validate(right)
        #expect(result == .valid)
        #expect(result.isAcceptable)
    }

    @Test("Validation - extension code in extensible group")
    func testValidationExtensionCodeExtensible() {
        let customCode = CodedConcept(codeValue: "99999", scheme: .SCT, codeMeaning: "Custom")
        let result = ContextGroup.commonAnatomicRegion.validate(customCode) // extensible
        #expect(result == .extensionCode)
        #expect(result.isAcceptable)
    }

    @Test("Validation - invalid code in non-extensible group")
    func testValidationInvalidCodeNonExtensible() {
        let customCode = CodedConcept(codeValue: "99999", scheme: .SCT, codeMeaning: "Custom")
        let result = ContextGroup.laterality.validate(customCode) // non-extensible
        if case .invalid(let reason) = result {
            #expect(reason.contains("CID 244"))
            #expect(!result.isAcceptable)
        } else {
            #expect(Bool(false), "Expected invalid result")
        }
    }

    // MARK: - Well-known groups vs PS3.16 2026a

    /// (group, CID, name, extensible, version, member count, spot members) extracted from the
    /// PS3.16 2026a CID tables, with "Include CID" rows expanded.
    private static let standard: [(ContextGroup, Int, String, Bool, String, Int, [CodedConcept])] = [
        (ContextGroup.laterality, 244, "Laterality", false, "20030108", 4, [CodedConcept(codeValue: "51440002", scheme: .SCT, codeMeaning: "Bilateral"), CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right"), CodedConcept(codeValue: "7771000", scheme: .SCT, codeMeaning: "Left")]),
        (ContextGroup.measurementReportDocumentTitles, 7021, "Measurement Report Document Title", true, "20141110", 4, [CodedConcept(codeValue: "126000", scheme: .DCM, codeMeaning: "Imaging Measurement Report"), CodedConcept(codeValue: "126002", scheme: .DCM, codeMeaning: "Dynamic Contrast MR Measurement Report"), CodedConcept(codeValue: "126003", scheme: .DCM, codeMeaning: "PET Measurement Report")]),
        (ContextGroup.relativeTime, 3600, "Relative Time", true, "20030327", 3, [CodedConcept(codeValue: "272113006", scheme: .SCT, codeMeaning: "Before"), CodedConcept(codeValue: "272114000", scheme: .SCT, codeMeaning: "During"), CodedConcept(codeValue: "288563008", scheme: .SCT, codeMeaning: "After")]),
        (ContextGroup.commonAnatomicRegion, 4031, "Common Anatomic Region", true, "20250709", 119, [CodedConcept(codeValue: "818981001", scheme: .SCT, codeMeaning: "Abdomen"), CodedConcept(codeValue: "1217253001", scheme: .SCT, codeMeaning: "Lumbo-sacral spine"), CodedConcept(codeValue: "13881006", scheme: .SCT, codeMeaning: "Zygoma")]),
        (ContextGroup.recistDefinedLesionResponse, 6144, "RECIST Defined Lesion Response", true, "20030108", 7, [CodedConcept(codeValue: "112041", scheme: .DCM, codeMeaning: "Target Lesion Complete Response"), CodedConcept(codeValue: "112044", scheme: .DCM, codeMeaning: "Target Lesion Stable Disease"), CodedConcept(codeValue: "112047", scheme: .DCM, codeMeaning: "Non-Target Lesion Progressive Disease")]),
        (ContextGroup.linearMeasurementUnit, 7460, "Linear Measurement Unit", true, "20020904", 3, [CodedConcept(codeValue: "cm", scheme: .UCUM, codeMeaning: "centimeter"), CodedConcept(codeValue: "mm", scheme: .UCUM, codeMeaning: "millimeter"), CodedConcept(codeValue: "um", scheme: .UCUM, codeMeaning: "micrometer")]),
        (ContextGroup.areaMeasurementUnit, 7461, "Area Measurement Unit", true, "20020904", 3, [CodedConcept(codeValue: "cm2", scheme: .UCUM, codeMeaning: "square centimeter"), CodedConcept(codeValue: "mm2", scheme: .UCUM, codeMeaning: "square millimeter"), CodedConcept(codeValue: "um2", scheme: .UCUM, codeMeaning: "square micrometer")]),
        (ContextGroup.volumeMeasurementUnit, 7462, "Volume Measurement Unit", true, "20020904", 4, [CodedConcept(codeValue: "dm3", scheme: .UCUM, codeMeaning: "cubic decimeter"), CodedConcept(codeValue: "mm3", scheme: .UCUM, codeMeaning: "cubic millimeter"), CodedConcept(codeValue: "um3", scheme: .UCUM, codeMeaning: "cubic micrometer")]),
        (ContextGroup.breastImagingFinding, 6054, "Breast Imaging Finding", true, "20050110", 47, [CodedConcept(codeValue: "290084006", scheme: .SCT, codeMeaning: "Breast normal"), CodedConcept(codeValue: "111112", scheme: .DCM, codeMeaning: "Mass in the skin"), CodedConcept(codeValue: "19227008", scheme: .SCT, codeMeaning: "Foreign body")]),
        (ContextGroup.measurementType, 3627, "Measurement Type", true, "20060613", 10, [CodedConcept(codeValue: "371912002", scheme: .SCT, codeMeaning: "Best value"), CodedConcept(codeValue: "371914001", scheme: .SCT, codeMeaning: "Peak to peak"), CodedConcept(codeValue: "258104002", scheme: .SCT, codeMeaning: "Measured")]),
    ]

    @Test("Each built-in group matches its PS3.16 2026a table", arguments: standard)
    func testGroupMatchesStandard(entry: (ContextGroup, Int, String, Bool, String, Int, [CodedConcept])) {
        let (group, cid, name, extensible, version, count, spots) = entry
        #expect(group.cid == cid)
        #expect(group.name == name)
        #expect(group.isExtensible == extensible)
        #expect(group.version == version)
        #expect(group.members.count == count)
        for spot in spots { #expect(group.contains(spot), "\(spot.codeValue) in CID \(cid)") }
        let keys = group.members.map { "\(spot(scheme: $0))|\($0.codeValue)" }
        #expect(Set(keys).count == keys.count, "no duplicate (scheme, code) in CID \(cid)")
    }

    private func spot(scheme concept: CodedConcept) -> String { concept.codingSchemeDesignator }

    @Test("Laterality expands Include CID 247 to Right and Left")
    func testLateralityIncludesCID247() {
        #expect(ContextGroup.laterality.contains(CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right")))
        #expect(ContextGroup.laterality.contains(CodedConcept(codeValue: "7771000", scheme: .SCT, codeMeaning: "Left")))
    }

    @Test("Measurement Type distinguishes Measured, Estimated and Calculated by the standard's codes")
    func testMeasurementTypeCodes() {
        let group = ContextGroup.measurementType
        #expect(group.contains(CodedConcept(codeValue: "258104002", scheme: .SCT, codeMeaning: "Measured")))
        #expect(group.contains(CodedConcept(codeValue: "414135002", scheme: .SCT, codeMeaning: "Estimated")))
        #expect(group.contains(CodedConcept(codeValue: "258090004", scheme: .SCT, codeMeaning: "Calculated")))
    }
}

// MARK: - ContextGroupRegistry Tests

@Suite("ContextGroupRegistry Tests")
struct ContextGroupRegistryTests {

    @Test("Shared instance has the well-known groups, and not the superseded CID numbers")
    func testSharedHasWellKnownGroups() {
        let registry = ContextGroupRegistry.shared
        for cid in [244, 7021, 3600, 4031, 6144, 7460, 7461, 7462, 6054, 3627] {
            #expect(registry.group(forCID: cid) != nil, "CID \(cid)")
        }
        for cid in [218, 4021, 6147, 7464, 12301, 6024, 6051] {
            #expect(registry.group(forCID: cid) == nil, "CID \(cid) is not one of the built-in groups")
        }
    }

    @Test("Lookup by CID")
    func testLookupByCID() {
        let registry = ContextGroupRegistry.shared
        #expect(registry.group(forCID: 244)?.name == "Laterality")
        #expect(registry.group(forCID: 99999) == nil)
    }

    @Test("Register custom group")
    func testRegisterCustomGroup() {
        let registry = ContextGroupRegistry()
        let custom = ContextGroup(cid: 99999, name: "Custom Group",
                                  members: [CodedConcept(codeValue: "TEST", scheme: .DCM, codeMeaning: "Test")])
        registry.register(custom)
        #expect(registry.group(forCID: 99999)?.name == "Custom Group")
    }

    @Test("All groups list")
    func testAllGroups() {
        let all = ContextGroupRegistry.shared.allGroups
        #expect(all.count == 10)
        #expect(all.contains(where: { $0.cid == 244 }))
    }

    @Test("Validate against CID")
    func testValidateAgainstCID() {
        let registry = ContextGroupRegistry.shared
        let right = CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right")
        #expect(registry.validate(right, againstCID: 244) == .valid)
        #expect(registry.validate(right, againstCID: 99999) == nil)
    }
}
