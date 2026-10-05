// StructuredReportModelTests.swift
// DICOMStudioTests
//
// Tests for Structured Report models (Milestone 7)

import Testing
@testable import DICOMStudio
import Foundation

// MARK: - SRDocumentType Tests

@Suite("SRDocumentType Tests")
struct SRDocumentTypeTests {
    @Test("All document types have raw values")
    func testRawValues() {
        #expect(SRDocumentType.basicText.rawValue == "BASIC_TEXT")
        #expect(SRDocumentType.enhanced.rawValue == "ENHANCED")
        #expect(SRDocumentType.comprehensive.rawValue == "COMPREHENSIVE")
        #expect(SRDocumentType.comprehensive3D.rawValue == "COMPREHENSIVE_3D")
        #expect(SRDocumentType.measurementReport.rawValue == "MEASUREMENT_REPORT")
        #expect(SRDocumentType.keyObjectSelection.rawValue == "KEY_OBJECT_SELECTION")
        #expect(SRDocumentType.mammographyCAD.rawValue == "MAMMOGRAPHY_CAD")
        #expect(SRDocumentType.chestCAD.rawValue == "CHEST_CAD")
    }

    @Test("Document type count is 8")
    func testAllCasesCount() {
        #expect(SRDocumentType.allCases.count == 8)
    }

    @Test("Display names are non-empty")
    func testDisplayNames() {
        for docType in SRDocumentType.allCases {
            #expect(!docType.displayName.isEmpty)
        }
    }

    @Test("SOP Class UIDs are non-empty")
    func testSOPClassUIDs() {
        for docType in SRDocumentType.allCases {
            #expect(!docType.sopClassUID.isEmpty)
            #expect(docType.sopClassUID.hasPrefix("1.2.840.10008"))
        }
    }

    @Test("Equatable conformance")
    func testEquatable() {
        #expect(SRDocumentType.basicText == SRDocumentType.basicText)
        #expect(SRDocumentType.basicText != SRDocumentType.enhanced)
    }

    @Test("Hashable conformance")
    func testHashable() {
        let set: Set<SRDocumentType> = [.basicText, .enhanced, .basicText]
        #expect(set.count == 2)
    }
}

// MARK: - ContentItemValueType Tests

@Suite("ContentItemValueType Tests")
struct ContentItemValueTypeTests {
    @Test("All 15 value types have raw values")
    func testAllValueTypes() {
        #expect(ContentItemValueType.allCases.count == 15)
        #expect(ContentItemValueType.container.rawValue == "CONTAINER")
        #expect(ContentItemValueType.text.rawValue == "TEXT")
        #expect(ContentItemValueType.code.rawValue == "CODE")
        #expect(ContentItemValueType.numeric.rawValue == "NUM")
        #expect(ContentItemValueType.date.rawValue == "DATE")
        #expect(ContentItemValueType.time.rawValue == "TIME")
        #expect(ContentItemValueType.dateTime.rawValue == "DATETIME")
        #expect(ContentItemValueType.personName.rawValue == "PNAME")
        #expect(ContentItemValueType.uidRef.rawValue == "UIDREF")
        #expect(ContentItemValueType.spatialCoord.rawValue == "SCOORD")
        #expect(ContentItemValueType.spatialCoord3D.rawValue == "SCOORD3D")
        #expect(ContentItemValueType.temporalCoord.rawValue == "TCOORD")
        #expect(ContentItemValueType.composite.rawValue == "COMPOSITE")
        #expect(ContentItemValueType.image.rawValue == "IMAGE")
        #expect(ContentItemValueType.waveform.rawValue == "WAVEFORM")
    }

    @Test("Display names are non-empty")
    func testDisplayNames() {
        for vt in ContentItemValueType.allCases {
            #expect(!vt.displayName.isEmpty)
        }
    }
}

// MARK: - SRRelationshipType Tests

@Suite("SRRelationshipType Tests")
struct SRRelationshipTypeTests {
    @Test("All relationship types have raw values")
    func testRawValues() {
        #expect(SRRelationshipType.allCases.count == 7)
        #expect(SRRelationshipType.contains.rawValue == "CONTAINS")
        #expect(SRRelationshipType.hasObsContext.rawValue == "HAS OBS CONTEXT")
        #expect(SRRelationshipType.hasAcqContext.rawValue == "HAS ACQ CONTEXT")
        #expect(SRRelationshipType.hasConceptMod.rawValue == "HAS CONCEPT MOD")
        #expect(SRRelationshipType.hasProperties.rawValue == "HAS PROPERTIES")
        #expect(SRRelationshipType.inferredFrom.rawValue == "INFERRED FROM")
        #expect(SRRelationshipType.selectedFrom.rawValue == "SELECTED FROM")
    }

    @Test("Display names are descriptive")
    func testDisplayNames() {
        #expect(SRRelationshipType.contains.displayName == "Contains")
        #expect(SRRelationshipType.hasObsContext.displayName == "Has Observation Context")
    }
}

// MARK: - CodingSchemeDesignator Tests

@Suite("CodingSchemeDesignator Tests")
struct CodingSchemeDesignatorTests {
    @Test("All schemes have display names")
    func testDisplayNames() {
        #expect(CodingSchemeDesignator.snomedCT.displayName == "SNOMED CT")
        #expect(CodingSchemeDesignator.loinc.displayName == "LOINC")
        #expect(CodingSchemeDesignator.radlex.displayName == "RadLex")
        #expect(CodingSchemeDesignator.ucum.displayName == "UCUM")
        #expect(CodingSchemeDesignator.dcm.displayName == "DICOM Controlled Terminology")   // PS3.16 2026a Table 8-1
    }

    @Test("All schemes count is 5")
    func testAllCases() {
        #expect(CodingSchemeDesignator.allCases.count == 5)
    }
}

// MARK: - ContinuityOfContent Tests

@Suite("ContinuityOfContent Tests")
struct ContinuityOfContentTests {
    @Test("Raw values")
    func testRawValues() {
        #expect(ContinuityOfContent.separate.rawValue == "SEPARATE")
        #expect(ContinuityOfContent.continuous.rawValue == "CONTINUOUS")
    }

    @Test("All cases count is 2")
    func testCount() {
        #expect(ContinuityOfContent.allCases.count == 2)
    }
}

// MARK: - CodedConcept Tests

@Suite("CodedConcept Tests")
struct CodedConceptTests {
    @Test("Initialization with all properties")
    func testInit() {
        let concept = CodedConcept(
            codeValue: "410668003",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Length",
            codingSchemeVersion: "2023"
        )
        #expect(concept.codeValue == "410668003")
        #expect(concept.codingSchemeDesignator == "SCT")
        #expect(concept.codeMeaning == "Length")
        #expect(concept.codingSchemeVersion == "2023")
    }

    @Test("Default version is nil")
    func testDefaultVersion() {
        let concept = CodedConcept(
            codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm"
        )
        #expect(concept.codingSchemeVersion == nil)
    }

    @Test("withMeaning creates new concept")
    func testWithMeaning() {
        let original = CodedConcept(
            codeValue: "123", codingSchemeDesignator: "DCM", codeMeaning: "Original"
        )
        let modified = original.withMeaning("Modified")
        #expect(modified.codeMeaning == "Modified")
        #expect(modified.codeValue == "123")
        #expect(modified.id == original.id)
    }

    @Test("Equatable and Hashable")
    func testEquatableHashable() {
        let a = CodedConcept(codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "A")
        let b = CodedConcept(codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "A")
        // Different UUIDs so they should not be equal
        #expect(a != b)

        let c = a.withMeaning("C")
        #expect(a.id == c.id)
    }

    @Test("Identifiable conformance")
    func testIdentifiable() {
        let concept = CodedConcept(
            codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "Test"
        )
        #expect(concept.id != UUID())
    }
}

// MARK: - SpatialCoordGraphicType Tests

@Suite("SpatialCoordGraphicType Tests")
struct SpatialCoordGraphicTypeTests {
    @Test("All 6 graphic types")
    func testAllCases() {
        #expect(SpatialCoordGraphicType.allCases.count == 6)
        #expect(SpatialCoordGraphicType.point.rawValue == "POINT")
        #expect(SpatialCoordGraphicType.polyline.rawValue == "POLYLINE")
        #expect(SpatialCoordGraphicType.circle.rawValue == "CIRCLE")
        #expect(SpatialCoordGraphicType.ellipse.rawValue == "ELLIPSE")
        #expect(SpatialCoordGraphicType.polygon.rawValue == "POLYGON")
        #expect(SpatialCoordGraphicType.multipoint.rawValue == "MULTIPOINT")
    }
}

// MARK: - SpatialCoord3DGraphicType Tests

@Suite("SpatialCoord3DGraphicType Tests")
struct SpatialCoord3DGraphicTypeTests {
    @Test("All 6 3D graphic types")
    func testAllCases() {
        #expect(SpatialCoord3DGraphicType.allCases.count == 6)
        #expect(SpatialCoord3DGraphicType.ellipsoid.rawValue == "ELLIPSOID")
    }
}

// MARK: - TemporalRangeType Tests

@Suite("TemporalRangeType Tests")
struct TemporalRangeTypeTests {
    @Test("All 6 temporal range types")
    func testAllCases() {
        #expect(TemporalRangeType.allCases.count == 6)
        #expect(TemporalRangeType.point.rawValue == "POINT")
        #expect(TemporalRangeType.segment.rawValue == "SEGMENT")
    }
}

// MARK: - SRContentItem Tests

@Suite("SRContentItem Tests")
struct SRContentItemTests {
    @Test("Default initialization")
    func testDefaultInit() {
        let item = SRContentItem(valueType: .text, textValue: "Hello")
        #expect(item.valueType == .text)
        #expect(item.textValue == "Hello")
        #expect(item.relationshipType == .contains)
        #expect(item.children.isEmpty)
        #expect(item.isExpanded == true)
    }

    @Test("Container with children")
    func testContainerWithChildren() {
        let child1 = SRContentItem(valueType: .text, textValue: "Child 1")
        let child2 = SRContentItem(valueType: .code, codeValue: CodedConcept(
            codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "Test"
        ))
        let container = SRContentItem(
            valueType: .container,
            continuityOfContent: .separate,
            children: [child1, child2]
        )
        #expect(container.children.count == 2)
        #expect(container.hasChildren)
        #expect(container.totalItemCount == 3)
    }

    @Test("withExpanded creates toggled copy")
    func testWithExpanded() {
        let item = SRContentItem(valueType: .container, isExpanded: true)
        let collapsed = item.withExpanded(false)
        #expect(!collapsed.isExpanded)
        #expect(collapsed.id == item.id)
    }

    @Test("withChildren creates copy with new children")
    func testWithChildren() {
        let item = SRContentItem(valueType: .container, children: [])
        let newChild = SRContentItem(valueType: .text, textValue: "New")
        let updated = item.withChildren([newChild])
        #expect(updated.children.count == 1)
        #expect(updated.id == item.id)
    }

    @Test("totalItemCount counts nested items")
    func testTotalItemCount() {
        let grandchild = SRContentItem(valueType: .text, textValue: "Grandchild")
        let child = SRContentItem(valueType: .container, children: [grandchild])
        let root = SRContentItem(valueType: .container, children: [child])
        #expect(root.totalItemCount == 3)
    }

    @Test("hasChildren is false for leaf nodes")
    func testHasChildrenFalse() {
        let leaf = SRContentItem(valueType: .text, textValue: "Leaf")
        #expect(!leaf.hasChildren)
    }

    @Test("Numeric item with unit")
    func testNumericItem() {
        let unit = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm")
        let item = SRContentItem(valueType: .numeric, numericValue: 42.5, measurementUnit: unit)
        #expect(item.numericValue == 42.5)
        #expect(item.measurementUnit?.codeValue == "mm")
    }

    @Test("Image reference item")
    func testImageItem() {
        let item = SRContentItem(
            valueType: .image,
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "1.2.3.4.5",
            referencedFrameNumbers: [1, 2, 3]
        )
        #expect(item.referencedSOPClassUID == "1.2.840.10008.5.1.4.1.1.2")
        #expect(item.referencedFrameNumbers?.count == 3)
    }

    @Test("Spatial coordinate item")
    func testSpatialCoordItem() {
        let item = SRContentItem(
            valueType: .spatialCoord,
            graphicType: .circle,
            graphicData: [100.0, 100.0, 150.0, 100.0]
        )
        #expect(item.graphicType == .circle)
        #expect(item.graphicData?.count == 4)
    }

    @Test("3D spatial coordinate item")
    func testSpatialCoord3DItem() {
        let item = SRContentItem(
            valueType: .spatialCoord3D,
            graphicType3D: .point,
            graphicData3D: [10.0, 20.0, 30.0]
        )
        #expect(item.graphicType3D == .point)
        #expect(item.graphicData3D?.count == 3)
    }
}

// MARK: - SRDocument Tests

@Suite("SRDocument Tests")
struct SRDocumentTests {
    @Test("Default initialization")
    func testDefaultInit() {
        let title = CodedConcept(
            codeValue: "121070", codingSchemeDesignator: "DCM", codeMeaning: "Test Report"
        )
        let doc = SRDocument(documentType: .basicText, title: title)
        #expect(doc.documentType == .basicText)
        #expect(doc.title.codeMeaning == "Test Report")
        #expect(doc.patientName.isEmpty)
        #expect(!doc.isComplete)
        #expect(!doc.isVerified)
    }

    @Test("withRootContentItem replaces root")
    func testWithRootContentItem() {
        let title = CodedConcept(
            codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "Report"
        )
        let doc = SRDocument(documentType: .basicText, title: title)
        let newRoot = SRContentItem(valueType: .container, children: [
            SRContentItem(valueType: .text, textValue: "Finding")
        ])
        let updated = doc.withRootContentItem(newRoot)
        #expect(updated.rootContentItem.children.count == 1)
        #expect(updated.id == doc.id)
    }

    @Test("withComplete marks document complete")
    func testWithComplete() {
        let title = CodedConcept(codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "R")
        let doc = SRDocument(documentType: .basicText, title: title)
        let complete = doc.withComplete(true)
        #expect(complete.isComplete)
        #expect(complete.id == doc.id)
    }

    @Test("withVerified marks document verified")
    func testWithVerified() {
        let title = CodedConcept(codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "R")
        let doc = SRDocument(documentType: .enhanced, title: title)
        let verified = doc.withVerified(true)
        #expect(verified.isVerified)
    }

    @Test("Full initialization with patient data")
    func testFullInit() {
        let title = CodedConcept(
            codeValue: "121070", codingSchemeDesignator: "DCM", codeMeaning: "CT Report"
        )
        let doc = SRDocument(
            documentType: .comprehensive,
            title: title,
            patientName: "DOE^JOHN",
            patientID: "12345",
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4",
            sopInstanceUID: "1.2.3.4.5",
            contentDate: "20240101",
            contentTime: "120000"
        )
        #expect(doc.patientName == "DOE^JOHN")
        #expect(doc.patientID == "12345")
        #expect(doc.contentDate == "20240101")
    }
}

// MARK: - SRTemplate Tests

@Suite("SRTemplate Tests")
struct SRTemplateTests {
    @Test("All template types count is 5")
    func testAllCases() {
        #expect(SRTemplate.allCases.count == 5)
    }

    @Test("Display names are non-empty")
    func testDisplayNames() {
        for template in SRTemplate.allCases {
            #expect(!template.displayName.isEmpty)
        }
    }

    @Test("Radiology report has 3 sections")
    func testRadiologyReportSections() {
        let sections = SRTemplate.radiologyReport.sections
        #expect(sections.count == 3)
        #expect(sections.contains("Findings"))
        #expect(sections.contains("Impression"))
        #expect(sections.contains("Recommendations"))
    }

    @Test("Pathology report has 3 sections")
    func testPathologyReportSections() {
        let sections = SRTemplate.pathologyReport.sections
        #expect(sections.count == 3)
    }

    @Test("Procedure report has 4 sections")
    func testProcedureReportSections() {
        #expect(SRTemplate.procedureReport.sections.count == 4)
    }

    @Test("Clinical findings has 4 sections")
    func testClinicalFindingsSections() {
        #expect(SRTemplate.clinicalFindings.sections.count == 4)
    }

    @Test("Discharge summary has 3 sections")
    func testDischargeSummarySections() {
        #expect(SRTemplate.dischargeSummary.sections.count == 3)
    }
}

// MARK: - KeyObjectPurpose Tests

@Suite("KeyObjectPurpose Tests")
struct KeyObjectPurposeTests {
    @Test("All purposes count is 6")
    func testAllCases() {
        #expect(KeyObjectPurpose.allCases.count == 6)
    }

    @Test("Display names")
    func testDisplayNames() {
        #expect(KeyObjectPurpose.teaching.displayName == "Teaching")
        #expect(KeyObjectPurpose.qualityControl.displayName == "Quality Control")
        #expect(KeyObjectPurpose.referral.displayName == "Referral")
        #expect(KeyObjectPurpose.conference.displayName == "Conference")
    }
}

// MARK: - BIRADSCategory Tests

@Suite("BIRADSCategory Tests")
struct BIRADSCategoryTests {
    @Test("All 7 categories")
    func testAllCases() {
        #expect(BIRADSCategory.allCases.count == 7)
    }

    @Test("Raw values are integers 0-6")
    func testRawValues() {
        #expect(BIRADSCategory.category0.rawValue == 0)
        #expect(BIRADSCategory.category6.rawValue == 6)
    }

    @Test("Display names include BI-RADS prefix")
    func testDisplayNames() {
        for category in BIRADSCategory.allCases {
            #expect(category.displayName.hasPrefix("BI-RADS"))
        }
    }
}

// MARK: - CADFindingType Tests

@Suite("CADFindingType Tests")
struct CADFindingTypeTests {
    @Test("All 6 finding types")
    func testAllCases() {
        #expect(CADFindingType.allCases.count == 6)
    }

    @Test("Display names are non-empty")
    func testDisplayNames() {
        for ft in CADFindingType.allCases {
            #expect(!ft.displayName.isEmpty)
        }
    }

    @Test("SF Symbol names are non-empty")
    func testSFSymbols() {
        for ft in CADFindingType.allCases {
            #expect(!ft.sfSymbolName.isEmpty)
        }
    }
}

// MARK: - CADFindingStatus Tests

@Suite("CADFindingStatus Tests")
struct CADFindingStatusTests {
    @Test("All 3 statuses")
    func testAllCases() {
        #expect(CADFindingStatus.allCases.count == 3)
        #expect(CADFindingStatus.pending.rawValue == "PENDING")
        #expect(CADFindingStatus.accepted.rawValue == "ACCEPTED")
        #expect(CADFindingStatus.rejected.rawValue == "REJECTED")
    }
}

// MARK: - CADFinding Tests

@Suite("CADFinding Tests")
struct CADFindingTests {
    @Test("Default initialization")
    func testDefaultInit() {
        let finding = CADFinding(findingType: .mass, confidence: 0.85)
        #expect(finding.findingType == .mass)
        #expect(finding.confidence == 0.85)
        #expect(finding.status == .pending)
        #expect(finding.locationDescription.isEmpty)
    }

    @Test("Confidence clamping above 1.0")
    func testConfidenceClampHigh() {
        let finding = CADFinding(findingType: .nodule, confidence: 1.5)
        #expect(finding.confidence == 1.0)
    }

    @Test("Confidence clamping below 0.0")
    func testConfidenceClampLow() {
        let finding = CADFinding(findingType: .nodule, confidence: -0.5)
        #expect(finding.confidence == 0.0)
    }

    @Test("withStatus creates copy")
    func testWithStatus() {
        let finding = CADFinding(findingType: .mass, confidence: 0.9)
        let accepted = finding.withStatus(.accepted)
        #expect(accepted.status == .accepted)
        #expect(accepted.id == finding.id)
        #expect(accepted.confidence == 0.9)
    }

    @Test("Confidence percentage formatting")
    func testConfidencePercentage() {
        let finding = CADFinding(findingType: .mass, confidence: 0.85)
        #expect(finding.confidencePercentage == "85%")
    }

    @Test("BI-RADS category for mammography findings")
    func testBIRADSCategory() {
        let finding = CADFinding(
            findingType: .mass,
            confidence: 0.7,
            biradsCategory: .category4
        )
        #expect(finding.biradsCategory == .category4)
    }

    @Test("Coordinates storage")
    func testCoordinates() {
        let finding = CADFinding(
            findingType: .calcification,
            confidence: 0.6,
            coordinates: [100.0, 200.0, 150.0, 250.0]
        )
        #expect(finding.coordinates.count == 4)
    }
}

// MARK: - TerminologyEntry Tests

@Suite("TerminologyEntry Tests")
struct TerminologyEntryTests {
    @Test("Default initialization")
    func testDefaultInit() {
        let concept = CodedConcept(
            codeValue: "123", codingSchemeDesignator: "SCT", codeMeaning: "Test"
        )
        let entry = TerminologyEntry(concept: concept)
        #expect(entry.concept.codeValue == "123")
        #expect(!entry.isFavorite)
        #expect(entry.category.isEmpty)
        #expect(entry.lastUsed.isEmpty)
    }

    @Test("withFavorite toggles favorite")
    func testWithFavorite() {
        let concept = CodedConcept(
            codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "T"
        )
        let entry = TerminologyEntry(concept: concept)
        let fav = entry.withFavorite(true)
        #expect(fav.isFavorite)
        #expect(fav.id == entry.id)
    }

    @Test("withLastUsed updates timestamp")
    func testWithLastUsed() {
        let concept = CodedConcept(
            codeValue: "1", codingSchemeDesignator: "DCM", codeMeaning: "T"
        )
        let entry = TerminologyEntry(concept: concept)
        let used = entry.withLastUsed("2024-01-15T10:00:00Z")
        #expect(used.lastUsed == "2024-01-15T10:00:00Z")
    }
}

// MARK: - LesionTrackingMethod Tests

@Suite("LesionTrackingMethod Tests")
struct LesionTrackingMethodTests {
    @Test("All 4 methods")
    func testAllCases() {
        #expect(LesionTrackingMethod.allCases.count == 4)
        #expect(LesionTrackingMethod.recist.displayName == "RECIST 1.1")
        #expect(LesionTrackingMethod.who.displayName == "WHO")
    }
}

// MARK: - MeasurementTimePoint Tests

@Suite("MeasurementTimePoint Tests")
struct MeasurementTimePointTests {
    @Test("All 3 time points")
    func testAllCases() {
        #expect(MeasurementTimePoint.allCases.count == 3)
        #expect(MeasurementTimePoint.baseline.displayName == "Baseline")
        #expect(MeasurementTimePoint.followUp.displayName == "Follow-Up")
    }
}

// MARK: - TrackedMeasurement Tests

@Suite("TrackedMeasurement Tests")
struct TrackedMeasurementTests {
    @Test("Default initialization")
    func testDefaultInit() {
        let unit = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm")
        let m = TrackedMeasurement(
            trackingIdentifier: "Lesion 1",
            value: 15.5,
            unit: unit
        )
        #expect(m.trackingIdentifier == "Lesion 1")
        #expect(m.value == 15.5)
        #expect(m.timePoint == .baseline)
        #expect(m.trackingMethod == .recist)
    }

    @Test("withValue updates measurement value")
    func testWithValue() {
        let unit = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm")
        let m = TrackedMeasurement(trackingIdentifier: "L1", value: 10.0, unit: unit)
        let updated = m.withValue(12.5)
        #expect(updated.value == 12.5)
        #expect(updated.id == m.id)
        #expect(updated.trackingIdentifier == "L1")
    }

    @Test("Finding site optional")
    func testFindingSite() {
        let unit = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "mm")
        let site = CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung")
        let m = TrackedMeasurement(
            trackingIdentifier: "L1",
            value: 20.0,
            unit: unit,
            findingSite: site
        )
        #expect(m.findingSite?.codeMeaning == "Lung")
    }
}

// MARK: - SRViewerMode Tests

@Suite("SRViewerMode Tests")
struct SRViewerModeTests {
    @Test("All 3 modes")
    func testAllCases() {
        #expect(SRViewerMode.allCases.count == 3)
        #expect(SRViewerMode.tree.rawValue == "TREE")
        #expect(SRViewerMode.list.rawValue == "LIST")
        #expect(SRViewerMode.narrative.rawValue == "NARRATIVE")
    }
}

// MARK: - SRBuilderMode Tests

@Suite("SRBuilderMode Tests")
struct SRBuilderModeTests {
    @Test("All 3 modes")
    func testAllCases() {
        #expect(SRBuilderMode.allCases.count == 3)
        #expect(SRBuilderMode.template.rawValue == "TEMPLATE")
        #expect(SRBuilderMode.freeForm.rawValue == "FREE_FORM")
    }
}

// MARK: - TerminologySearchScope Tests

@Suite("TerminologySearchScope Tests")
struct TerminologySearchScopeTests {
    @Test("All 5 scopes")
    func testAllCases() {
        #expect(TerminologySearchScope.allCases.count == 5)
    }

    @Test("Display names")
    func testDisplayNames() {
        #expect(TerminologySearchScope.all.displayName == "All Terminologies")
        #expect(TerminologySearchScope.snomedCT.displayName == "SNOMED CT")
        #expect(TerminologySearchScope.loinc.displayName == "LOINC")
        #expect(TerminologySearchScope.radlex.displayName == "RadLex")
        #expect(TerminologySearchScope.ucum.displayName == "UCUM")
    }
}
