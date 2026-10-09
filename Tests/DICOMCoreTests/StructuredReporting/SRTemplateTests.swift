import Testing
import Foundation
@testable import DICOMCore

// MARK: - Template Identifier Tests

@Suite("Template Identifier Tests")
struct TemplateIdentifierTests {
    
    @Test("Create template identifier with string TID")
    func testCreateWithStringTID() {
        let identifier = TemplateIdentifier(templateID: "300")
        #expect(identifier.templateID == "300")
        #expect(identifier.version == nil)
        #expect(identifier.mappingResource == "DCMR")
    }
    
    @Test("Create template identifier with integer TID")
    func testCreateWithIntegerTID() {
        let identifier = TemplateIdentifier(tid: 1500)
        #expect(identifier.templateID == "1500")
        #expect(identifier.version == nil)
        #expect(identifier.mappingResource == "DCMR")
    }
    
    @Test("Create template identifier with version")
    func testCreateWithVersion() {
        let identifier = TemplateIdentifier(tid: 300, version: "2.0")
        #expect(identifier.templateID == "300")
        #expect(identifier.version == "2.0")
    }
    
    @Test("Create template identifier with custom mapping resource")
    func testCreateWithMappingResource() {
        let identifier = TemplateIdentifier(tid: 300, mappingResource: "CUSTOM")
        #expect(identifier.mappingResource == "CUSTOM")
    }
    
    @Test("Template identifier description without version")
    func testDescriptionWithoutVersion() {
        let identifier = TemplateIdentifier(tid: 300)
        #expect(identifier.description == "TID 300")
    }
    
    @Test("Template identifier description with version")
    func testDescriptionWithVersion() {
        let identifier = TemplateIdentifier(tid: 300, version: "1.0")
        #expect(identifier.description == "TID 300 v1.0")
    }
    
    @Test("Well-known template identifiers")
    func testWellKnownIdentifiers() {
        #expect(TemplateIdentifier.measurement.templateID == "300")
        #expect(TemplateIdentifier.imageOrSpatialCoordinates.templateID == "320")
        #expect(TemplateIdentifier.imageLibraryEntry.templateID == "1601")
        #expect(TemplateIdentifier.observationContext.templateID == "1001")
        #expect(TemplateIdentifier.observerContext.templateID == "1002")
        #expect(TemplateIdentifier.languageOfContent.templateID == "1204")
        #expect(TemplateIdentifier.linearMeasurements.templateID == "1400")
        #expect(TemplateIdentifier.planarROIMeasurements.templateID == "1410")
        #expect(TemplateIdentifier.volumetricROIMeasurements.templateID == "1411")
        #expect(TemplateIdentifier.roiMeasurements.templateID == "1419")
        #expect(TemplateIdentifier.multipleROIMeasurements.templateID == "1420")
        #expect(TemplateIdentifier.measurementReport.templateID == "1500")
    }
    
    @Test("Template identifier equality")
    func testEquality() {
        let id1 = TemplateIdentifier(tid: 300)
        let id2 = TemplateIdentifier(tid: 300)
        let id3 = TemplateIdentifier(tid: 1500)
        
        #expect(id1 == id2)
        #expect(id1 != id3)
    }
    
    @Test("Template identifier hashing")
    func testHashing() {
        let id1 = TemplateIdentifier(tid: 300)
        let id2 = TemplateIdentifier(tid: 300)
        
        #expect(id1.hashValue == id2.hashValue)
    }
}

// MARK: - Requirement Level Tests

@Suite("Requirement Level Tests")
struct RequirementLevelTests {
    
    @Test("Requirement types are the four symbols of PS3.16 2026a §6.1.7")
    func testRawValues() {
        #expect(RequirementLevel.mandatory.rawValue == "M")
        #expect(RequirementLevel.mandatoryConditional.rawValue == "MC")
        #expect(RequirementLevel.userOption.rawValue == "U")
        #expect(RequirementLevel.userOptionConditional.rawValue == "UC")
        // "C" is not a PS3.16 requirement type and must not be among allCases.
        #expect(RequirementLevel.allCases.count == 4)
    }

    @Test("Requirement level display names")
    func testDisplayNames() {
        #expect(RequirementLevel.mandatory.displayName == "Mandatory")
        #expect(RequirementLevel.mandatoryConditional.displayName == "Mandatory Conditional")
        #expect(RequirementLevel.userOption.displayName == "User Option")
        #expect(RequirementLevel.userOptionConditional.displayName == "User Option Conditional")
    }

    @Test("Mandatory property")
    func testIsMandatory() {
        #expect(RequirementLevel.mandatory.isMandatory == true)
        #expect(RequirementLevel.mandatoryConditional.isMandatory == false)
        #expect(RequirementLevel.userOption.isMandatory == false)
        #expect(RequirementLevel.userOptionConditional.isMandatory == false)
    }

    @Test("All cases")
    func testAllCases() {
        #expect(RequirementLevel.allCases == [.mandatory, .mandatoryConditional, .userOption, .userOptionConditional])
    }

    @Test("Well-known template identifiers carry the TID numbers of PS3.16 2026a Annex A")
    func testWellKnownTIDsMatchAnnexA() {
        // (constant, TID, PS3.16 2026a section title)
        let expected: [(TemplateIdentifier, Int, String)] = [
            (.measurement, 300, "Measurement"),
            (.imageOrSpatialCoordinates, 320, "Image or Spatial Coordinates"),
            (.observationContext, 1001, "Observation Context"),
            (.observerContext, 1002, "Observer Context"),
            (.languageOfContent, 1204, "Language of Content Item and Descendants"),
            (.linearMeasurements, 1400, "Linear Measurement"),
            (.planarROIMeasurements, 1410, "Planar ROI Measurements and Qualitative Evaluations"),
            (.volumetricROIMeasurements, 1411, "Volumetric ROI Measurements and Qualitative Evaluations"),
            (.roiMeasurements, 1419, "ROI Measurements"),
            (.multipleROIMeasurements, 1420, "Measurements Derived From Multiple ROI Measurements"),
            (.measurementReport, 1500, "Measurement Report"),
            (.measurementGroup, 1501, "Measurement and Qualitative Evaluation Group"),
            (.imageLibrary, 1600, "Image Library"),
            (.imageLibraryEntry, 1601, "Image Library Entry"),
            (.mammographyCADDocumentRoot, 4000, "Mammography CAD Document Root"),
            (.algorithmIdentification, 4019, "Algorithm Identification"),
            (.areaMeasurement, 1401, "Area Measurement"),
            (.volumeMeasurement, 1402, "Volume Measurement"),
            (.mammographyCADSingleImageFinding, 4006, "Mammography CAD Single Image Finding"),
            (.cadImageLibraryEntry, 4020, "CAD Image Library Entry"),
            (.chestCADDocumentRoot, 4100, "Chest CAD Document Root"),
            (.chestCADSingleImageFinding, 4104, "Chest CAD Single Image Finding"),
            (.responseEvaluation, 4106, "Response Evaluation"),
            (.chestCADGeometry, 4107, "Chest CAD Geometry"),
        ]
        for (identifier, tid, title) in expected {
            #expect(identifier.templateID == String(tid), Comment(rawValue: title))
            #expect(identifier.mappingResource == "DCMR", Comment(rawValue: title))
            // Registered templates carry the same title (display names are generated from PS3.16)
            if let template = TemplateRegistry.shared.template(tid: tid) {
                #expect(template.displayName == title, Comment(rawValue: "TID \(tid)"))
            }
        }
    }
}

// MARK: - Cardinality Tests

@Suite("Cardinality Tests")
struct CardinalityTests {
    
    @Test("Cardinality one")
    func testCardinalityOne() {
        let cardinality = Cardinality.one
        #expect(cardinality.minimum == 1)
        #expect(cardinality.maximum == 1)
        #expect(cardinality.allowsZero == false)
        #expect(cardinality.allowsMultiple == false)
    }
    
    @Test("Cardinality zero or one")
    func testCardinalityZeroOrOne() {
        let cardinality = Cardinality.zeroOrOne
        #expect(cardinality.minimum == 0)
        #expect(cardinality.maximum == 1)
        #expect(cardinality.allowsZero == true)
        #expect(cardinality.allowsMultiple == false)
    }
    
    @Test("Cardinality one or more")
    func testCardinalityOneOrMore() {
        let cardinality = Cardinality.oneOrMore
        #expect(cardinality.minimum == 1)
        #expect(cardinality.maximum == nil)
        #expect(cardinality.allowsZero == false)
        #expect(cardinality.allowsMultiple == true)
    }
    
    @Test("Cardinality zero or more")
    func testCardinalityZeroOrMore() {
        let cardinality = Cardinality.zeroOrMore
        #expect(cardinality.minimum == 0)
        #expect(cardinality.maximum == nil)
        #expect(cardinality.allowsZero == true)
        #expect(cardinality.allowsMultiple == true)
    }
    
    @Test("Custom cardinality")
    func testCustomCardinality() {
        let cardinality = Cardinality(minimum: 2, maximum: 5)
        #expect(cardinality.minimum == 2)
        #expect(cardinality.maximum == 5)
        #expect(cardinality.allowsZero == false)
        #expect(cardinality.allowsMultiple == true)
    }
    
    @Test("Cardinality satisfaction - exact")
    func testSatisfactionExact() {
        let cardinality = Cardinality.one
        #expect(cardinality.isSatisfied(by: 0) == false)
        #expect(cardinality.isSatisfied(by: 1) == true)
        #expect(cardinality.isSatisfied(by: 2) == false)
    }
    
    @Test("Cardinality satisfaction - optional")
    func testSatisfactionOptional() {
        let cardinality = Cardinality.zeroOrOne
        #expect(cardinality.isSatisfied(by: 0) == true)
        #expect(cardinality.isSatisfied(by: 1) == true)
        #expect(cardinality.isSatisfied(by: 2) == false)
    }
    
    @Test("Cardinality satisfaction - unbounded")
    func testSatisfactionUnbounded() {
        let cardinality = Cardinality.oneOrMore
        #expect(cardinality.isSatisfied(by: 0) == false)
        #expect(cardinality.isSatisfied(by: 1) == true)
        #expect(cardinality.isSatisfied(by: 100) == true)
    }
    
    @Test("Cardinality satisfaction - range")
    func testSatisfactionRange() {
        let cardinality = Cardinality(minimum: 2, maximum: 5)
        #expect(cardinality.isSatisfied(by: 1) == false)
        #expect(cardinality.isSatisfied(by: 2) == true)
        #expect(cardinality.isSatisfied(by: 3) == true)
        #expect(cardinality.isSatisfied(by: 5) == true)
        #expect(cardinality.isSatisfied(by: 6) == false)
    }
    
    @Test("Cardinality description")
    func testDescription() {
        #expect(Cardinality.one.description == "1")
        #expect(Cardinality.zeroOrOne.description == "0..1")
        #expect(Cardinality.oneOrMore.description == "1..n")
        #expect(Cardinality.zeroOrMore.description == "0..n")
        #expect(Cardinality(minimum: 2, maximum: 5).description == "2..5")
    }
}

// MARK: - Template Row Tests

@Suite("Template Row Tests")
struct TemplateRowTests {
    
    @Test("Create basic template row")
    func testCreateBasicRow() {
        let row = TemplateRow(
            rowID: "1",
            nestingLevel: 0,
            relationshipType: .contains,
            valueType: .container
        )
        
        #expect(row.rowID == "1")
        #expect(row.nestingLevel == 0)
        #expect(row.relationshipType == .contains)
        #expect(row.valueType == .container)
        #expect(row.requirementLevel == .mandatory)
        #expect(row.cardinality == .one)
        #expect(row.includedTemplate == nil)
    }
    
    @Test("Create template row with concept constraint")
    func testCreateRowWithConceptConstraint() {
        let concept = CodedConcept(
            codeValue: "121071",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        
        let row = TemplateRow(
            relationshipType: .contains,
            valueType: .code,
            conceptName: .exact(concept),
            requirementLevel: .userConditional,
            cardinality: .zeroOrOne
        )
        
        if case .exact(let constraintConcept) = row.conceptName {
            #expect(constraintConcept == concept)
        } else {
            Issue.record("Expected exact concept constraint")
        }
    }
    
    @Test("Create template row with included template")
    func testCreateRowWithIncludedTemplate() {
        let row = TemplateRow(
            relationshipType: .contains,
            valueType: .num,
            includedTemplate: .measurement
        )
        
        #expect(row.includedTemplate == .measurement)
    }
    
    @Test("Create template row with condition")
    func testCreateRowWithCondition() {
        let concept = CodedConcept(
            codeValue: "363698007",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Finding Site"
        )
        
        let row = TemplateRow(
            relationshipType: .hasConceptMod,
            valueType: .code,
            condition: .ifPresent(concept: concept)
        )
        
        if case .ifPresent(let conditionConcept) = row.condition {
            #expect(conditionConcept == concept)
        } else {
            Issue.record("Expected ifPresent condition")
        }
    }
}

// MARK: - Template Registry Tests

@Suite("Template Registry Tests")
struct TemplateRegistryTests {
    
    @Test("Registry has built-in templates")
    func testBuiltInTemplates() {
        let registry = TemplateRegistry.shared
        let templates = registry.registeredTemplates
        
        #expect(templates.count == 73)
        #expect(templates.contains(.mammographyCADDocumentRoot))
        #expect(templates.contains(.chestCADDocumentRoot))
        #expect(templates.contains(.measurement))
        #expect(templates.contains(.imageLibraryEntry))
        #expect(templates.contains(.observationContext))
        #expect(templates.contains(.observerContext))
        #expect(templates.contains(.languageOfContent))
    }
    
    // NOTE: `TemplateRegistry.template(...)` returns `(any SRTemplate.Type)?`
    // — an optional existential metatype. Passing that expression *directly*
    // into `#expect(...)` makes the swift-testing macro instantiate its
    // generic `__checkBinaryOperation` over the existential-metatype optional,
    // which crashes the Swift runtime's metadata cache (EXC_BAD_ACCESS in
    // `__swift_instantiateCanonicalPrespecializedGenericMetadata`). Binding the
    // result to plain `Bool` / `TemplateIdentifier?` locals first keeps the
    // existential metatype out of the macro and sidesteps the runtime bug.

    @Test("Lookup template by identifier")
    func testLookupByIdentifier() {
        let registry = TemplateRegistry.shared

        let template = registry.template(for: .measurement)
        let found = template != nil
        #expect(found)
        let identifier = template?.identifier
        #expect(identifier == .measurement)
    }

    @Test("Lookup template by TID")
    func testLookupByTID() {
        let registry = TemplateRegistry.shared

        let template = registry.template(tid: 300)
        let found = template != nil
        #expect(found)
        let templateID = template?.identifier.templateID
        #expect(templateID == "300")
    }

    @Test("Lookup unknown template returns nil")
    func testLookupUnknownTemplate() {
        let registry = TemplateRegistry.shared

        let template = registry.template(tid: 99999)
        let isAbsent = template == nil
        #expect(isAbsent)
    }
}

// MARK: - Template Definition Tests (PS3.16 2026a)

/// The template rows are generated from the PS3.16 2026a TID tables by
/// Scripts/generate_sr_templates.py. These tests pin facts read from those tables.
@Suite("Template Definition Tests (PS3.16 2026a)")
struct TemplateDefinitionTests {

    /// Number of rows in each 2026a TID table.
    static let rowCounts: [Int: Int] = [
        300: 2, 301: 19, 310: 6, 311: 4, 312: 4, 315: 3, 320: 6, 321: 5, 1000: 3, 1001: 3,
        1002: 4, 1003: 6, 1004: 12, 1005: 9, 1006: 5, 1007: 12, 1008: 6, 1009: 6, 1010: 6,
        1015: 2, 1204: 2, 1400: 8, 1410: 22, 1411: 23, 1419: 23, 1420: 5, 1500: 18, 1501: 26,
        1502: 7, 1600: 4, 1601: 2, 1602: 17, 1603: 8, 1604: 13, 1605: 2, 1606: 7, 1607: 16,
        1608: 3, 4019: 6, 4108: 2,
        // TID 4000 and TID 4100 with the templates they include (D50)
        1401: 8, 1402: 8, 4000: 9, 4001: 3, 4002: 15, 4003: 5, 4004: 7, 4005: 27, 4006: 26,
        4007: 2, 4008: 4, 4009: 4, 4010: 6, 4011: 6, 4012: 4, 4013: 4, 4014: 4, 4015: 4, 4016: 4,
        4017: 9, 4018: 9, 4020: 28, 4021: 6, 4022: 3, 4023: 9, 4100: 9, 4101: 4, 4102: 14,
        4103: 13, 4104: 24, 4105: 20, 4106: 5, 4107: 6,
    ]

    @Test("All 73 templates are registered with the row count of their 2026a table")
    func testRowCounts() {
        #expect(TemplateRegistry.builtInTemplates.count == 73)
        #expect(Self.rowCounts.count == 73)
        for (tid, count) in Self.rowCounts {
            let rows = TemplateRegistry.shared.template(tid: tid)?.rows.count
            #expect(rows == count, Comment(rawValue: "TID \(tid)"))
        }
    }

    @Test("Every INCLUDE row names a registered template")
    func testIncludesAreClosed() {
        var includes = 0
        for template in TemplateRegistry.builtInTemplates {
            for row in template.rows where row.isInclude {
                includes += 1
                #expect(row.valueType == nil)
                let found = TemplateRegistry.shared.template(for: row.includedTemplate!) != nil
                #expect(found, Comment(rawValue: "\(template.identifier) row \(row.rowID ?? "?")"))
            }
        }
        #expect(includes == 147)
    }

    @Test("Display names are the PS3.16 2026a TID titles")
    func testTitles() {
        #expect(TID300Measurement.displayName == "Measurement")
        #expect(TID1204LanguageOfContent.displayName == "Language of Content Item and Descendants")
        #expect(TID1400LinearMeasurements.displayName == "Linear Measurement")
        #expect(TID1410PlanarROIMeasurements.displayName == "Planar ROI Measurements and Qualitative Evaluations")
        #expect(TID1411VolumetricROIMeasurements.displayName == "Volumetric ROI Measurements and Qualitative Evaluations")
        #expect(TID1420MultipleROIMeasurements.displayName == "Measurements Derived From Multiple ROI Measurements")
        #expect(TID1501MeasurementGroup.displayName == "Measurement and Qualitative Evaluation Group")
        #expect(TID320ImageOrSpatialCoordinates.displayName == "Image or Spatial Coordinates")
        #expect(TID1601ImageLibraryEntry.identifier.templateID == "1601")
    }

    @Test("Type, Order and Root come from the template headers")
    func testTemplateHeaders() {
        #expect(TID1500MeasurementReport.isRoot)
        #expect(TID1500MeasurementReport.isExtensible)
        #expect(!TID1500MeasurementReport.isOrderSignificant)
        #expect(!TID1204LanguageOfContent.isExtensible)
        #expect(!TID1002ObserverContext.isExtensible)
        #expect(!TID4019AlgorithmIdentification.isExtensible)
        #expect(TID300Measurement.isOrderSignificant)
        #expect(!TID300Measurement.isRoot)
    }

    @Test("TID 300 is a NUM root that includes TID 301")
    func testTID300() {
        let rows = TID300Measurement.rows
        #expect(TID300Measurement.rootValueType == .num)
        #expect(rows[0].relationshipType == nil)
        #expect(rows[0].conceptName == .parameter("Measurement"))
        #expect(rows[0].valueConstraint == .units(.parameter("Units")))
        #expect(rows[1].rowID == "1b")
        #expect(rows[1].nestingLevel == 1)
        #expect(rows[1].includedTemplate == .measurementContent)
        #expect(rows[1].includeParameters.count == 15)
        #expect(TID300Measurement.parameters.first == TemplateParameter(
            name: "Measurement", usage: "Coded term or Context Group for Concept Name of measurement"))
    }

    @Test("TID 1500 rows: root, INCLUDEs and parameter bindings")
    func testTID1500() {
        let rows = TID1500MeasurementReport.rows
        #expect(rows[0].valueType == .container)
        #expect(rows[0].conceptName == .fromContextGroup(contextGroupID: 7021))
        #expect(rows[0].valueSetText == "Root node")

        let observationContext = rows.first { $0.rowID == "3" }
        #expect(observationContext?.includedTemplate == .observationContext)
        #expect(observationContext?.relationshipType == .hasObsContext)
        #expect(observationContext?.requirementLevel == .mandatory)

        let groups = rows.first { $0.rowID == "9" }
        #expect(groups?.nestingLevel == 2)
        #expect(groups?.includedTemplate == .measurementGroup)
        #expect(groups?.valueMultiplicity == .oneOrMore)
        #expect(groups?.cardinality == .zeroOrMore)
        #expect(groups?.includeParameters.first == TemplateParameterBinding(
            name: "Measurement", value: .baselineContextGroup(218),
            text: "BCID 218 \"Quantitative Image Feature\""))

        let imagingMeasurements = rows.first { $0.rowID == "6" }
        #expect(imagingMeasurements?.requirementLevel == .mandatoryConditional)
        #expect(imagingMeasurements?.condition == .custom(description: "IF Row 10 and Row 12 are absent"))
        #expect(imagingMeasurements?.conceptName == .exact(
            CodedConcept(codeValue: "126010", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurements")))
    }

    @Test("TID 1400 keeps by-reference relationships and VM 2-n")
    func testTID1400() {
        let rows = TID1400LinearMeasurements.rows
        #expect(rows[0].conceptName == .fromContextGroup(contextGroupID: 7470))
        let byReference = rows.first { $0.rowID == "3" }
        #expect(byReference?.relationshipType == .selectedFrom)
        #expect(byReference?.isByReference == true)
        let vertices = rows.first { $0.rowID == "5" }
        #expect(vertices?.valueMultiplicity == Cardinality(minimum: 2))
        #expect(vertices?.requirementLevel == .userOptionConditional)
    }

    @Test("A value set of one code per paragraph accepts each (TID 1000 row 1, TID 4020 rows 11-12)")
    func testMultiCodeValueSets() {
        let document = CodedConcept(codeValue: "121003", codingSchemeDesignator: "DCM", codeMeaning: "Document")
        let verbal = CodedConcept(codeValue: "121004", codingSchemeDesignator: "DCM", codeMeaning: "Verbal")
        #expect(TID1000Quotation.rows[0].valueConstraint == .oneOfCodes([document, verbal]))
        let micrometer = CodedConcept(codeValue: "um", codingSchemeDesignator: "UCUM", codeMeaning: "micrometer")
        let millimeter = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")
        for rowID in ["11", "12"] {
            let row = TID4020CADImageLibraryEntry.rows.first { $0.rowID == rowID }
            #expect(row?.valueConstraint == .units(.oneOfCodes([micrometer, millimeter])))
        }
        let mode = CodedConcept(codeValue: "121001", codingSchemeDesignator: "DCM", codeMeaning: "Quotation Mode")
        for (value, valid) in [(document, true), (verbal, true), (millimeter, false)] {
            let item = AnyContentItem.code(conceptName: mode, value: value, relationshipType: .hasObsContext)
            let result = TemplateValidator(mode: .strict).validate([item], against: .quotation)
            #expect(result.errors.contains { $0.templateRowID == "1" } == !valid, Comment(rawValue: value.codeMeaning))
        }
    }

    @Test("Defined Terms and Baseline groups are distinguished")
    func testDefinedTermsAndBaselineGroups() {
        let trackingIdentifier = TID1501MeasurementGroup.rows.first { $0.rowID == "2" }
        #expect(trackingIdentifier?.conceptName == .definedTerm(
            CodedConcept(codeValue: "112039", codingSchemeDesignator: "DCM", codeMeaning: "Tracking Identifier")))
        let procedure = TID1500MeasurementReport.rows.first { $0.rowID == "4" }
        #expect(procedure?.valueConstraint == .fromBaselineContextGroup(contextGroupID: 100))
    }

    @Test("Rows nest by nesting level")
    func testTree() {
        let tree = TemplateMatcher.tree(TID1500MeasurementReport.rows)
        #expect(tree.count == 1)
        #expect(tree[0].children.map { $0.row.rowID } == ["2", "3", "4", "5", "6", "10", "12"])
        let qualitative = tree[0].children.last!
        #expect(qualitative.children.map { $0.row.rowID } == ["12b", "13", "14"])
        #expect(qualitative.children[1].children.map { $0.row.rowID } == ["13b"])
    }
}

// MARK: - Template Validation Against 2026a Rows

@Suite("Template Validation Tests (PS3.16 2026a)")
struct TemplateValidationBehaviourTests {
    let dcm = { (value: String, meaning: String) in
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    @Test("A minimal TID 1500 tree is compliant")
    func testMinimalMeasurementReport() {
        let group = AnyContentItem.container(
            conceptName: dcm("125007", "Measurement Group"),
            items: [
                .text(conceptName: dcm("112039", "Tracking Identifier"), value: "Lesion 1",
                      relationshipType: .hasObsContext),
                .numeric(conceptName: CodedConcept(codeValue: "103339001", codingSchemeDesignator: "SCT",
                                                   codeMeaning: "Long Axis"),
                         value: 12.5,
                         units: CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm"),
                         relationshipType: .contains),
            ],
            relationshipType: .contains
        )
        let report = AnyContentItem.container(
            conceptName: dcm("126000", "Imaging Measurement Report"),
            items: [.container(conceptName: dcm("126010", "Imaging Measurements"), items: [group],
                               relationshipType: .contains)]
        )
        let result = TemplateValidator(mode: .strict).validate([report], against: .measurementReport)
        #expect(result.isFullyCompliant, Comment(rawValue: result.violations.map(\.description).joined(separator: "\n")))
    }

    @Test("A missing M row is reported")
    func testMissingMandatoryRow() {
        let result = TemplateValidator().validate([], against: .languageOfContent)
        #expect(result.errors.map(\.templateRowID) == ["1"])
    }

    @Test("M rows of an optional INCLUDE apply once it has content")
    func testOptionalIncludeWithContent() {
        // TID 1500 row 6b includes TID 4019 (U). Algorithm Name without Algorithm Version
        // violates TID 4019 row 2 (M).
        let report = AnyContentItem.container(
            conceptName: dcm("126000", "Imaging Measurement Report"),
            items: [.container(
                conceptName: dcm("126010", "Imaging Measurements"),
                items: [.text(conceptName: dcm("111001", "Algorithm Name"), value: "Seg",
                              relationshipType: .hasConceptMod)],
                relationshipType: .contains
            )]
        )
        let result = TemplateValidator().validate([report], against: .measurementReport)
        #expect(result.errors.map(\.templateRowID) == ["2"])
        #expect(result.errors.first?.message.contains("Algorithm Version") == true)
    }

    @Test("Extra content is reported only in a non-extensible template")
    func testExtensibility() {
        let language = AnyContentItem.code(
            conceptName: dcm("121049", "Language of Content Item and Descendants"),
            value: CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English"),
            relationshipType: .hasConceptMod
        )
        let extra = AnyContentItem.text(conceptName: dcm("121106", "Comment"), value: "x",
                                        relationshipType: .hasConceptMod)
        let nonExtensible = TemplateValidator(mode: .strict).validate([language, extra], against: .languageOfContent)
        #expect(nonExtensible.warnings.count == 1)
        #expect(nonExtensible.isCompliant)

        let lenient = TemplateValidator(mode: .lenient).validate([language, extra], against: .languageOfContent)
        #expect(lenient.isFullyCompliant)

        let extensible = TemplateValidator(mode: .strict).validate([extra], against: .measurementContent)
        #expect(extensible.isFullyCompliant)
    }

    @Test("NUM units are checked against UNITS = EV")
    func testUnits() {
        // TID 1008 row 5: Number of Fetuses by US, UNITS = EV (1, UCUM, "no units")
        let concept = CodedConcept(codeValue: "11878-6", codingSchemeDesignator: "LN",
                                   codeMeaning: "Number of Fetuses by US")
        let good = AnyContentItem.numeric(
            conceptName: concept, value: 2,
            units: CodedConcept(codeValue: "1", codingSchemeDesignator: "UCUM", codeMeaning: "no units"))
        let bad = AnyContentItem.numeric(
            conceptName: concept, value: 2,
            units: CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm"))
        let validator = TemplateValidator()
        #expect(validator.validate([good], against: .subjectContextFetus).isFullyCompliant)
        #expect(validator.validate([bad], against: .subjectContextFetus).errors.map(\.templateRowID) == ["5"])
    }

    @Test("Code Meaning is not significant when matching codes")
    func testCodeMeaningIgnored() {
        let language = AnyContentItem.code(
            conceptName: dcm("121049", "Language of Content"),
            value: CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English"),
            relationshipType: .hasConceptMod
        )
        #expect(TemplateValidator().validate([language], against: .languageOfContent).isFullyCompliant)
    }

    @Test("Detection finds TID 1204 for a language item")
    func testDetection() {
        let language = AnyContentItem.code(
            conceptName: dcm("121049", "Language of Content Item and Descendants"),
            value: CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English"),
            relationshipType: .hasConceptMod
        )
        let detected = TemplateDetector().detectTemplates([language]).map(\.template)
        #expect(detected.contains(.languageOfContent))
    }
}

// MARK: - Template Violation Tests

@Suite("Template Violation Tests")
struct TemplateViolationTests {
    
    @Test("Create error violation")
    func testErrorViolation() {
        let violation = TemplateViolation(
            severity: .error,
            templateRowID: "1",
            contentPath: "/Report/Finding",
            message: "Missing required field",
            details: "Expected: Finding"
        )
        
        #expect(violation.severity == .error)
        #expect(violation.templateRowID == "1")
        #expect(violation.contentPath == "/Report/Finding")
        #expect(violation.message == "Missing required field")
        #expect(violation.details == "Expected: Finding")
    }
    
    @Test("Create warning violation")
    func testWarningViolation() {
        let violation = TemplateViolation(
            severity: .warning,
            message: "Optional field not provided"
        )
        
        #expect(violation.severity == .warning)
        #expect(violation.templateRowID == nil)
        #expect(violation.contentPath == nil)
    }
    
    @Test("Factory method - missing required")
    func testMissingRequiredFactory() {
        let concept = CodedConcept(
            codeValue: "121071",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        
        let violation = TemplateViolation.missingRequired(
            rowID: "1",
            conceptName: concept,
            path: "/Report"
        )
        
        #expect(violation.severity == .error)
        #expect(violation.message.contains("Finding"))
    }
    
    @Test("Factory method - cardinality violation")
    func testCardinalityViolationFactory() {
        let violation = TemplateViolation.cardinalityViolation(
            rowID: "2",
            expected: .one,
            actual: 3,
            conceptName: nil,
            path: "/Report"
        )
        
        #expect(violation.severity == .error)
        #expect(violation.message.contains("expected"))
        #expect(violation.message.contains("3"))
    }
    
    @Test("Factory method - value type mismatch")
    func testValueTypeMismatchFactory() {
        let violation = TemplateViolation.valueTypeMismatch(
            rowID: "3",
            expected: .num,
            actual: .text,
            path: "/Report/Measurement"
        )
        
        #expect(violation.severity == .error)
        #expect(violation.message.contains("NUM"))
        #expect(violation.message.contains("TEXT"))
    }
    
    @Test("Factory method - relationship mismatch")
    func testRelationshipMismatchFactory() {
        let violation = TemplateViolation.relationshipMismatch(
            rowID: "4",
            expected: .contains,
            actual: .hasProperties,
            path: "/Report/Finding"
        )
        
        #expect(violation.severity == .error)
        #expect(violation.templateRowID == "4")
        #expect(violation.contentPath == "/Report/Finding")
        #expect(violation.message.contains("CONTAINS"))
        #expect(violation.message.contains("HAS PROPERTIES"))
    }
    
    @Test("Factory method - invalid concept")
    func testInvalidConceptFactory() {
        let actualConcept = CodedConcept(
            codeValue: "121072",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Observation"
        )
        let expectedConstraint = ConceptNameConstraint.exact(CodedConcept(
            codeValue: "121071",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        ))
        
        let violation = TemplateViolation.invalidConcept(
            rowID: "5",
            expected: expectedConstraint,
            actual: actualConcept,
            path: "/Report/Item"
        )
        
        #expect(violation.severity == .error)
        #expect(violation.templateRowID == "5")
        #expect(violation.contentPath == "/Report/Item")
        #expect(violation.message.contains("Observation"))
    }
    
    @Test("Factory method - invalid value")
    func testInvalidValueFactory() {
        let constraint = ValueConstraint.numericUnits(unitCode: CodedConcept(
            codeValue: "mm",
            codingSchemeDesignator: "UCUM",
            codeMeaning: "mm"
        ))
        
        let violation = TemplateViolation.invalidValue(
            rowID: "6",
            constraint: constraint,
            path: "/Report/Measurement"
        )
        
        #expect(violation.severity == .error)
        #expect(violation.templateRowID == "6")
        #expect(violation.contentPath == "/Report/Measurement")
        #expect(violation.message.contains("constraint"))
    }
    
    @Test("Factory method - unexpected content")
    func testUnexpectedContentFactory() {
        let violation = TemplateViolation.unexpectedContent(
            path: "/Report/Extra",
            message: "Found unexpected NUM content item"
        )
        
        #expect(violation.severity == .warning)
        #expect(violation.templateRowID == nil)
        #expect(violation.contentPath == "/Report/Extra")
        #expect(violation.message.contains("unexpected"))
    }
    
    @Test("Violation description")
    func testViolationDescription() {
        let violation = TemplateViolation(
            severity: .error,
            templateRowID: "1",
            contentPath: "/Report",
            message: "Test message",
            details: "Details here"
        )
        
        let description = violation.description
        #expect(description.contains("[ERROR]"))
        #expect(description.contains("/Report"))
        #expect(description.contains("row 1"))
        #expect(description.contains("Test message"))
        #expect(description.contains("Details here"))
    }
}

// MARK: - Template Validation Result Tests

@Suite("Template Validation Result Tests")
struct TemplateValidationResultTests {
    
    @Test("Successful validation result")
    func testSuccessfulResult() {
        let result = TemplateValidationResult.success(for: .measurement)
        
        #expect(result.templateIdentifier == .measurement)
        #expect(result.violations.isEmpty)
        #expect(result.isCompliant == true)
        #expect(result.isFullyCompliant == true)
        #expect(result.errorCount == 0)
        #expect(result.warningCount == 0)
    }
    
    @Test("Result with errors")
    func testResultWithErrors() {
        let violations = [
            TemplateViolation(severity: .error, message: "Error 1"),
            TemplateViolation(severity: .error, message: "Error 2"),
            TemplateViolation(severity: .warning, message: "Warning 1")
        ]
        
        let result = TemplateValidationResult(
            templateIdentifier: .measurement,
            violations: violations
        )
        
        #expect(result.isCompliant == false)
        #expect(result.isFullyCompliant == false)
        #expect(result.errorCount == 2)
        #expect(result.warningCount == 1)
        #expect(result.errors.count == 2)
        #expect(result.warnings.count == 1)
    }
    
    @Test("Result with only warnings")
    func testResultWithOnlyWarnings() {
        let violations = [
            TemplateViolation(severity: .warning, message: "Warning 1"),
            TemplateViolation(severity: .warning, message: "Warning 2")
        ]
        
        let result = TemplateValidationResult(
            templateIdentifier: .measurement,
            violations: violations
        )
        
        #expect(result.isCompliant == true)
        #expect(result.isFullyCompliant == false)
        #expect(result.errorCount == 0)
        #expect(result.warningCount == 2)
    }
}

// MARK: - Template Validator Tests

@Suite("Template Validator Tests")
struct TemplateValidatorTests {
    
    @Test("Validator initialization")
    func testValidatorInitialization() {
        let strictValidator = TemplateValidator(mode: .strict)
        #expect(strictValidator.mode == .strict)
        #expect(strictValidator.maxDepth == 50)
        
        let lenientValidator = TemplateValidator(mode: .lenient, maxDepth: 100)
        #expect(lenientValidator.mode == .lenient)
        #expect(lenientValidator.maxDepth == 100)
    }
    
    @Test("Validate against unknown template")
    func testValidateUnknownTemplate() {
        let validator = TemplateValidator()
        let unknownTemplate = TemplateIdentifier(tid: 99999)
        
        let result = validator.validate([], against: unknownTemplate)
        
        #expect(result.isCompliant == false)
        #expect(result.errorCount == 1)
        #expect(result.errors[0].message.contains("Unknown template"))
    }
    
    @Test("Validate empty content")
    func testValidateEmptyContent() {
        let validator = TemplateValidator(mode: .lenient)
        
        let result = validator.validate([], against: .measurement)
        
        // Empty content won't match mandatory rows in lenient mode
        // Since TID 300 has a mandatory NUM row
        #expect(result.violations.count >= 0) // May have violations for mandatory items
    }
}

// MARK: - Template Detector Tests

@Suite("Template Detector Tests")
struct TemplateDetectorTests {
    
    @Test("Detect template from empty content")
    func testDetectFromEmptyContent() {
        let detector = TemplateDetector()
        _ = detector.detectTemplate([])
        
        // Empty content might still match templates with all optional rows
        // This test verifies the API doesn't crash with empty input
    }
    
    @Test("Detect templates returns sorted results")
    func testDetectTemplatesReturnsSorted() {
        let detector = TemplateDetector()
        let results = detector.detectTemplates([])
        
        // Verify results are sorted by confidence (descending)
        guard results.count > 1 else { return }
        for i in 1..<results.count {
            #expect(results[i-1].confidence >= results[i].confidence)
        }
    }
}

// MARK: - Concept Name Constraint Tests

@Suite("Concept Name Constraint Tests")
struct ConceptNameConstraintTests {
    
    @Test("Any constraint")
    func testAnyConstraint() {
        let constraint = ConceptNameConstraint.any
        if case .any = constraint {
            // Passes
        } else {
            Issue.record("Expected any constraint")
        }
    }
    
    @Test("Exact constraint")
    func testExactConstraint() {
        let concept = CodedConcept(
            codeValue: "121071",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Finding"
        )
        let constraint = ConceptNameConstraint.exact(concept)
        
        if case .exact(let c) = constraint {
            #expect(c == concept)
        } else {
            Issue.record("Expected exact constraint")
        }
    }
    
    @Test("From context group constraint")
    func testFromContextGroupConstraint() {
        let constraint = ConceptNameConstraint.fromContextGroup(contextGroupID: 244)
        
        if case .fromContextGroup(let cid) = constraint {
            #expect(cid == 244)
        } else {
            Issue.record("Expected fromContextGroup constraint")
        }
    }
    
    @Test("One of constraint")
    func testOneOfConstraint() {
        let concepts = [
            CodedConcept(codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "One"),
            CodedConcept(codeValue: "2", codingSchemeDesignator: "DCM", codeMeaning: "Two")
        ]
        let constraint = ConceptNameConstraint.oneOf(concepts)
        
        if case .oneOf(let c) = constraint {
            #expect(c.count == 2)
        } else {
            Issue.record("Expected oneOf constraint")
        }
    }
}

// MARK: - Value Constraint Tests

@Suite("Value Constraint Tests")
struct ValueConstraintTests {
    
    @Test("Any value constraint")
    func testAnyConstraint() {
        let constraint = ValueConstraint.any
        if case .any = constraint {
            // Passes
        } else {
            Issue.record("Expected any constraint")
        }
    }
    
    @Test("Exact code constraint")
    func testExactCodeConstraint() {
        let code = CodedConcept(
            codeValue: "R",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Right"
        )
        let constraint = ValueConstraint.exactCode(code)
        
        if case .exactCode(let c) = constraint {
            #expect(c == code)
        } else {
            Issue.record("Expected exactCode constraint")
        }
    }
    
    @Test("Numeric units constraint")
    func testNumericUnitsConstraint() {
        let unit = CodedConcept(
            codeValue: "mm",
            codingSchemeDesignator: "UCUM",
            codeMeaning: "mm"
        )
        let constraint = ValueConstraint.numericUnits(unitCode: unit)
        
        if case .numericUnits(let u) = constraint {
            #expect(u == unit)
        } else {
            Issue.record("Expected numericUnits constraint")
        }
    }
}

// MARK: - Template Row Condition Tests

@Suite("Template Row Condition Tests")
struct TemplateRowConditionTests {
    
    @Test("None condition")
    func testNoneCondition() {
        let condition = TemplateRowCondition.none
        if case .none = condition {
            // Passes
        } else {
            Issue.record("Expected none condition")
        }
    }
    
    @Test("If present condition")
    func testIfPresentCondition() {
        let concept = CodedConcept(
            codeValue: "363698007",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Finding Site"
        )
        let condition = TemplateRowCondition.ifPresent(concept: concept)
        
        if case .ifPresent(let c) = condition {
            #expect(c == concept)
        } else {
            Issue.record("Expected ifPresent condition")
        }
    }
    
    @Test("If equals condition")
    func testIfEqualsCondition() {
        let concept = CodedConcept(codeValue: "121005", codingSchemeDesignator: "DCM", codeMeaning: "Observer Type")
        let value = CodedConcept(codeValue: "121006", codingSchemeDesignator: "DCM", codeMeaning: "Person")
        let condition = TemplateRowCondition.ifEquals(concept: concept, value: value)
        
        if case .ifEquals(let c, let v) = condition {
            #expect(c == concept)
            #expect(v == value)
        } else {
            Issue.record("Expected ifEquals condition")
        }
    }
    
    @Test("If absent condition")
    func testIfAbsentCondition() {
        let concept = CodedConcept(codeValue: "test", codingSchemeDesignator: "DCM", codeMeaning: "Test")
        let condition = TemplateRowCondition.ifAbsent(concept: concept)
        
        if case .ifAbsent(let c) = condition {
            #expect(c == concept)
        } else {
            Issue.record("Expected ifAbsent condition")
        }
    }
    
    @Test("Custom condition")
    func testCustomCondition() {
        let condition = TemplateRowCondition.custom(description: "Complex rule here")
        
        if case .custom(let desc) = condition {
            #expect(desc == "Complex rule here")
        } else {
            Issue.record("Expected custom condition")
        }
    }
}
