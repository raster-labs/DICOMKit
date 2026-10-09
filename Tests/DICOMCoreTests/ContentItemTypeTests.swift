import Testing
@testable import DICOMCore

// MARK: - ContentItemValueType Tests

@Suite("ContentItemValueType Tests")
struct ContentItemValueTypeTests {
    
    @Test("All 16 value types of PS3.3 2026a Table C.17.3-7 are defined")
    func testAllValueTypesDefined() {
        #expect(ContentItemValueType.allCases.count == 16)
        #expect(ContentItemValueType.allCases.contains(.table))
        #expect(ContentItemValueType.table.rawValue == "TABLE")
    }
    
    @Test("Raw values match DICOM standard")
    func testRawValues() {
        #expect(ContentItemValueType.text.rawValue == "TEXT")
        #expect(ContentItemValueType.code.rawValue == "CODE")
        #expect(ContentItemValueType.num.rawValue == "NUM")
        #expect(ContentItemValueType.date.rawValue == "DATE")
        #expect(ContentItemValueType.time.rawValue == "TIME")
        #expect(ContentItemValueType.datetime.rawValue == "DATETIME")
        #expect(ContentItemValueType.pname.rawValue == "PNAME")
        #expect(ContentItemValueType.uidref.rawValue == "UIDREF")
        #expect(ContentItemValueType.composite.rawValue == "COMPOSITE")
        #expect(ContentItemValueType.image.rawValue == "IMAGE")
        #expect(ContentItemValueType.waveform.rawValue == "WAVEFORM")
        #expect(ContentItemValueType.scoord.rawValue == "SCOORD")
        #expect(ContentItemValueType.scoord3D.rawValue == "SCOORD3D")
        #expect(ContentItemValueType.tcoord.rawValue == "TCOORD")
        #expect(ContentItemValueType.container.rawValue == "CONTAINER")
    }
    
    @Test("Display names are non-empty")
    func testDisplayNames() {
        for valueType in ContentItemValueType.allCases {
            #expect(valueType.displayName.isEmpty == false)
        }
    }
    
    @Test("Type descriptions are non-empty")
    func testTypeDescriptions() {
        for valueType in ContentItemValueType.allCases {
            #expect(valueType.typeDescription.isEmpty == false)
        }
    }
    
    @Test("isReference property")
    func testIsReference() {
        #expect(ContentItemValueType.composite.isReference == true)
        #expect(ContentItemValueType.image.isReference == true)
        #expect(ContentItemValueType.waveform.isReference == true)
        
        #expect(ContentItemValueType.text.isReference == false)
        #expect(ContentItemValueType.code.isReference == false)
        #expect(ContentItemValueType.num.isReference == false)
        #expect(ContentItemValueType.container.isReference == false)
    }
    
    @Test("isCoordinate property")
    func testIsCoordinate() {
        #expect(ContentItemValueType.scoord.isCoordinate == true)
        #expect(ContentItemValueType.scoord3D.isCoordinate == true)
        #expect(ContentItemValueType.tcoord.isCoordinate == true)
        
        #expect(ContentItemValueType.text.isCoordinate == false)
        #expect(ContentItemValueType.image.isCoordinate == false)
    }
    
    @Test("isSimpleValue property")
    func testIsSimpleValue() {
        #expect(ContentItemValueType.text.isSimpleValue == true)
        #expect(ContentItemValueType.code.isSimpleValue == true)
        #expect(ContentItemValueType.num.isSimpleValue == true)
        #expect(ContentItemValueType.date.isSimpleValue == true)
        #expect(ContentItemValueType.time.isSimpleValue == true)
        #expect(ContentItemValueType.datetime.isSimpleValue == true)
        #expect(ContentItemValueType.pname.isSimpleValue == true)
        #expect(ContentItemValueType.uidref.isSimpleValue == true)
        
        #expect(ContentItemValueType.container.isSimpleValue == false)
        #expect(ContentItemValueType.image.isSimpleValue == false)
        #expect(ContentItemValueType.scoord.isSimpleValue == false)
    }
    
    @Test("Description returns raw value")
    func testDescription() {
        #expect(ContentItemValueType.text.description == "TEXT")
        #expect(ContentItemValueType.container.description == "CONTAINER")
    }
}

// MARK: - RelationshipType Tests

@Suite("RelationshipType Tests")
struct RelationshipTypeTests {
    
    @Test("All relationship types are defined")
    func testAllRelationshipTypesDefined() {
        #expect(RelationshipType.allCases.count == 7)
    }
    
    @Test("Raw values match DICOM standard")
    func testRawValues() {
        #expect(RelationshipType.contains.rawValue == "CONTAINS")
        #expect(RelationshipType.hasProperties.rawValue == "HAS PROPERTIES")
        #expect(RelationshipType.hasObsContext.rawValue == "HAS OBS CONTEXT")
        #expect(RelationshipType.hasAcqContext.rawValue == "HAS ACQ CONTEXT")
        #expect(RelationshipType.hasConceptMod.rawValue == "HAS CONCEPT MOD")
        #expect(RelationshipType.inferredFrom.rawValue == "INFERRED FROM")
        #expect(RelationshipType.selectedFrom.rawValue == "SELECTED FROM")
    }
    
    @Test("Display names are non-empty")
    func testDisplayNames() {
        for relType in RelationshipType.allCases {
            #expect(relType.displayName.isEmpty == false)
        }
    }
    
    @Test("Meanings are non-empty")
    func testMeanings() {
        for relType in RelationshipType.allCases {
            #expect(relType.meaning.isEmpty == false)
        }
    }
    
    @Test("CONTAINS is valid for CONTAINER parent")
    func testContainsValidForContainer() {
        #expect(RelationshipType.contains.isValidForParent(.container) == true)
        #expect(RelationshipType.contains.isValidForParent(.text) == false)
        #expect(RelationshipType.contains.isValidForParent(.code) == false)
    }
    
    @Test("HAS OBS CONTEXT is valid for any parent")
    func testHasObsContextValidForAny() {
        for valueType in ContentItemValueType.allCases {
            #expect(RelationshipType.hasObsContext.isValidForParent(valueType) == true)
        }
    }
    
    @Test("HAS ACQ CONTEXT is valid for any parent")
    func testHasAcqContextValidForAny() {
        for valueType in ContentItemValueType.allCases {
            #expect(RelationshipType.hasAcqContext.isValidForParent(valueType) == true)
        }
    }
    
    @Test("HAS CONCEPT MOD is valid for specific types")
    func testHasConceptModValidation() {
        #expect(RelationshipType.hasConceptMod.isValidForParent(.code) == true)
        #expect(RelationshipType.hasConceptMod.isValidForParent(.num) == true)
        #expect(RelationshipType.hasConceptMod.isValidForParent(.image) == true)
        #expect(RelationshipType.hasConceptMod.isValidForParent(.scoord) == true)
        
        #expect(RelationshipType.hasConceptMod.isValidForParent(.text) == false)
        #expect(RelationshipType.hasConceptMod.isValidForParent(.container) == false)
    }
    
    @Test("INFERRED FROM is valid for CODE and NUM")
    func testInferredFromValidation() {
        #expect(RelationshipType.inferredFrom.isValidForParent(.code) == true)
        #expect(RelationshipType.inferredFrom.isValidForParent(.num) == true)
        
        #expect(RelationshipType.inferredFrom.isValidForParent(.text) == false)
        #expect(RelationshipType.inferredFrom.isValidForParent(.image) == false)
    }
    
    @Test("SELECTED FROM is valid for coordinate types")
    func testSelectedFromValidation() {
        #expect(RelationshipType.selectedFrom.isValidForParent(.scoord) == true)
        #expect(RelationshipType.selectedFrom.isValidForParent(.scoord3D) == true)
        #expect(RelationshipType.selectedFrom.isValidForParent(.tcoord) == true)
        
        #expect(RelationshipType.selectedFrom.isValidForParent(.text) == false)
        #expect(RelationshipType.selectedFrom.isValidForParent(.image) == false)
    }
    
    @Test("Valid child value types for CONTAINS")
    func testContainsChildTypes() {
        let childTypes = RelationshipType.contains.validChildValueTypes
        
        // CONTAINS can have all value types as children
        #expect(childTypes.count == ContentItemValueType.allCases.count)
    }
    
    @Test("Valid child value types for HAS OBS CONTEXT")
    func testHasObsContextChildTypes() {
        let childTypes = RelationshipType.hasObsContext.validChildValueTypes
        
        #expect(childTypes.contains(.text))
        #expect(childTypes.contains(.code))
        #expect(childTypes.contains(.pname))
        #expect(childTypes.contains(.datetime))
    }
    
    @Test("Description returns raw value")
    func testDescription() {
        #expect(RelationshipType.contains.description == "CONTAINS")
        #expect(RelationshipType.hasProperties.description == "HAS PROPERTIES")
    }
}

// MARK: - GraphicType Tests

@Suite("GraphicType Tests")
struct GraphicTypeTests {
    
    @Test("allCases is exactly the five SCOORD Graphic Types of PS3.3 C.18.6.1.2")
    func testAllGraphicTypesDefined() {
        #expect(GraphicType.allCases.map(\.rawValue) == ["POINT", "MULTIPOINT", "POLYLINE", "CIRCLE", "ELLIPSE"])
    }
    
    @Test("Raw values match DICOM standard")
    func testRawValues() {
        #expect(GraphicType.point.rawValue == "POINT")
        #expect(GraphicType.polyline.rawValue == "POLYLINE")
        #expect(GraphicType.ellipse.rawValue == "ELLIPSE")
        #expect(GraphicType.circle.rawValue == "CIRCLE")
        #expect(GraphicType.multipoint.rawValue == "MULTIPOINT")
    }
    
    @Test("Minimum points are correct")
    func testMinimumPoints() {
        #expect(GraphicType.point.minimumPoints == 1)
        #expect(GraphicType.multipoint.minimumPoints == 2)
        #expect(GraphicType.polyline.minimumPoints == 2)
        #expect(GraphicType.circle.minimumPoints == 2)
        #expect(GraphicType.ellipse.minimumPoints == 4)
    }
}

// MARK: - GraphicType3D Tests

@Suite("GraphicType3D Tests")
struct GraphicType3DTests {
    
    @Test("All 3D graphic types are defined")
    func testAll3DGraphicTypesDefined() {
        #expect(GraphicType3D.allCases.count == 6)
    }
    
    @Test("Raw values match DICOM standard")
    func testRawValues() {
        #expect(GraphicType3D.point.rawValue == "POINT")
        #expect(GraphicType3D.polyline.rawValue == "POLYLINE")
        #expect(GraphicType3D.ellipsoid.rawValue == "ELLIPSOID")
    }
    
    @Test("Minimum points are correct for 3D")
    func testMinimumPoints3D() {
        #expect(GraphicType3D.point.minimumPoints == 1)
        #expect(GraphicType3D.ellipsoid.minimumPoints == 6)
    }
}

// MARK: - TemporalRangeType Tests

@Suite("TemporalRangeType Tests")
struct TemporalRangeTypeTests {
    
    @Test("All six Temporal Range Types of PS3.3 C.18.7.1.1 are defined")
    func testAllTemporalRangeTypesDefined() {
        #expect(Set(TemporalRangeType.allCases.map(\.rawValue)) == ["POINT", "MULTIPOINT", "SEGMENT", "MULTISEGMENT", "BEGIN", "END"])
    }
    
    @Test("Raw values match DICOM standard")
    func testRawValues() {
        #expect(TemporalRangeType.point.rawValue == "POINT")
        #expect(TemporalRangeType.multipoint.rawValue == "MULTIPOINT")
        #expect(TemporalRangeType.segment.rawValue == "SEGMENT")
        #expect(TemporalRangeType.multisegment.rawValue == "MULTISEGMENT")
        #expect(TemporalRangeType.beginSegment.rawValue == "BEGIN")
        #expect(TemporalRangeType.endSegment.rawValue == "END")
    }
}

// MARK: - NumericValueQualifier Tests

@Suite("NumericValueQualifier Tests")
struct NumericValueQualifierTests {

    /// PS3.16 2026a CID 43 and CID 44, the members of CID 42 Numeric Value Qualifier.
    private static let cid42: [(NumericValueQualifier, String, String)] = [
        (.notANumber, "114000", "Not a number"),
        (.negativeInfinity, "114001", "Negative Infinity"),
        (.positiveInfinity, "114002", "Positive Infinity"),
        (.divideByZero, "114003", "Divide by zero"),
        (.underflow, "114004", "Underflow"),
        (.overflow, "114005", "Overflow"),
        (.measurementFailure, "114006", "Measurement failure"),
        (.measurementNotAttempted, "114007", "Measurement not attempted"),
        (.calculationFailure, "114008", "Calculation failure"),
        (.valueOutOfRange, "114009", "Value out of range"),
        (.valueUnknown, "114010", "Value unknown"),
        (.valueIndeterminate, "114011", "Value indeterminate"),
    ]

    @Test("All 12 CID 42 qualifiers are defined")
    func testCount() {
        #expect(NumericValueQualifier.allCases.count == 12)
        #expect(Set(Self.cid42.map { $0.0 }) == Set(NumericValueQualifier.allCases))
    }

    @Test("Each qualifier carries its CID 42 code", arguments: cid42)
    func testCode(entry: (NumericValueQualifier, String, String)) {
        let (qualifier, value, meaning) = entry
        #expect(qualifier.code.codeValue == value)
        #expect(qualifier.code.codeMeaning == meaning)
        #expect(NumericValueQualifier(code: qualifier.code.concept) == qualifier)
    }

    @Test("A non-CID-42 code gives no qualifier")
    func testUnknownCode() {
        #expect(NumericValueQualifier(code: CodedConcept(codeValue: "121071", scheme: .DCM, codeMeaning: "Finding")) == nil)
        #expect(NumericValueQualifier(code: CodedConcept(codeValue: "114000", scheme: .SCT, codeMeaning: "x")) == nil)
    }
}

// MARK: - ContinuityOfContent Tests

@Suite("ContinuityOfContent Tests")
struct ContinuityOfContentTests {
    
    @Test("Raw values match DICOM standard")
    func testRawValues() {
        #expect(ContinuityOfContent.separate.rawValue == "SEPARATE")
        #expect(ContinuityOfContent.continuous.rawValue == "CONTINUOUS")
    }
}

// MARK: - ReferencedSOP Tests

@Suite("ReferencedSOP Tests")
struct ReferencedSOPTests {
    
    @Test("Basic creation")
    func testBasicCreation() {
        let ref = ReferencedSOP(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5.6.7.8.9"
        )
        
        #expect(ref.sopClassUID == "1.2.840.10008.5.1.4.1.1.2")
        #expect(ref.sopInstanceUID == "1.2.3.4.5.6.7.8.9")
    }
    
    @Test("Equatable conformance")
    func testEquatable() {
        let ref1 = ReferencedSOP(sopClassUID: "1.2.3", sopInstanceUID: "4.5.6")
        let ref2 = ReferencedSOP(sopClassUID: "1.2.3", sopInstanceUID: "4.5.6")
        let ref3 = ReferencedSOP(sopClassUID: "1.2.3", sopInstanceUID: "7.8.9")
        
        #expect(ref1 == ref2)
        #expect(ref1 != ref3)
    }
}

// MARK: - ImageReference Tests

@Suite("ImageReference Tests")
struct ImageReferenceTests {
    
    @Test("Basic creation")
    func testBasicCreation() {
        let sopRef = ReferencedSOP(sopClassUID: "1.2.3", sopInstanceUID: "4.5.6")
        let ref = ImageReference(sopReference: sopRef)
        
        #expect(ref.sopReference == sopRef)
        #expect(ref.frameNumbers == nil)
        #expect(ref.segmentNumbers == nil)
    }
    
    @Test("Creation with frame numbers")
    func testCreationWithFrameNumbers() {
        let ref = ImageReference(
            sopClassUID: "1.2.3",
            sopInstanceUID: "4.5.6",
            frameNumbers: [1, 2, 3]
        )
        
        #expect(ref.frameNumbers == [1, 2, 3])
    }
    
    @Test("Creation with all fields")
    func testCreationWithAllFields() {
        let purpose = CodedConcept.imageReference
        let ref = ImageReference(
            sopReference: ReferencedSOP(sopClassUID: "1.2.3", sopInstanceUID: "4.5.6"),
            frameNumbers: [1, 5],
            segmentNumbers: [2],
            purposeOfReference: purpose
        )
        
        #expect(ref.frameNumbers == [1, 5])
        #expect(ref.segmentNumbers == [2])
        #expect(ref.purposeOfReference == purpose)
    }
}
