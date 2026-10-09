import Foundation
import Testing
@testable import DICOMCore

/// Directory Record Type (0004,1430) values and the record hierarchy, checked against
/// PS3.3 2026a Table F.3-3 and Table F.4-1.
@Suite("DirectoryRecordType Tests")
struct DirectoryRecordTypeTests {

    // MARK: - Enumerated Values (Table F.3-3)

    @Test("Every current Enumerated Value parses and is not retired", arguments: [
        "PATIENT", "STUDY", "SERIES", "IMAGE", "RADIOTHERAPY", "RT DOSE", "RT STRUCTURE SET",
        "RT PLAN", "PLAN", "RT TREAT RECORD", "PRESENTATION", "WAVEFORM", "SR DOCUMENT",
        "KEY OBJECT DOC", "SPECTROSCOPY", "RAW DATA", "REGISTRATION", "FIDUCIAL",
        "HANGING PROTOCOL", "ENCAP DOC", "VALUE MAP", "STEREOMETRIC", "PALETTE", "IMPLANT",
        "IMPLANT GROUP", "IMPLANT ASSY", "MEASUREMENT", "SURFACE", "SURFACE SCAN", "TRACT",
        "ASSESSMENT", "ANNOTATION", "INVENTORY", "WF PRESENTATION", "PRIVATE",
    ])
    func testCurrentValues(value: String) throws {
        let type = try #require(DirectoryRecordType(rawValue: value))
        #expect(!type.isRetired)
    }

    @Test("Every retired Enumerated Value parses and is marked retired", arguments: [
        "PRINT QUEUE", "FILM SESSION", "FILM BOX", "IMAGE BOX", "OVERLAY", "MODALITY LUT",
        "VOI LUT", "CURVE", "TOPIC", "VISIT", "RESULTS", "INTERPRETATION", "STUDY COMPONENT",
        "STORED PRINT", "MRDR", "HL7 STRUC DOC",
    ])
    func testRetiredValues(value: String) throws {
        let type = try #require(DirectoryRecordType(rawValue: value))
        #expect(type.isRetired)
    }

    // MARK: - Hierarchy (Table F.4-1)

    private func record(_ type: DirectoryRecordType, _ children: [DirectoryRecord] = []) -> DirectoryRecord {
        DirectoryRecord(recordType: type, children: children)
    }

    private func directory(_ roots: [DirectoryRecord]) -> DICOMDirectory {
        DICOMDirectory(rootRecords: roots)
    }

    @Test("Every SERIES child type in Table F.4-1 validates", arguments: [
        DirectoryRecordType.image, .rtDose, .rtStructureSet, .rtPlan, .rtTreatRecord, .presentation,
        .waveform, .srDocument, .keyObjectDoc, .spectroscopy, .rawData, .registration, .fiducial,
        .encapsulatedDocument, .valueMap, .stereometricRelationship, .plan, .measurement, .surface,
        .tract, .assessment, .radiotherapy, .annotation, .wfPresentation, .private,
    ])
    func testSeriesChildren(child: DirectoryRecordType) throws {
        let tree = record(.patient, [record(.study, [record(.series, [record(child)])])])
        try directory([tree]).validate()
    }

    @Test("Every root-level type in Table F.4-1 validates", arguments: [
        DirectoryRecordType.patient, .hangingProtocol, .palette, .implant, .implantAssy,
        .implantGroup, .inventory, .private,
    ])
    func testRootLevel(type: DirectoryRecordType) throws {
        try directory([record(type)]).validate()
    }

    @Test("PRIVATE is allowed under a leaf, and may contain any record type")
    func testPrivateAnywhere() throws {
        let tree = record(.patient, [record(.study, [record(.series, [
            record(.image, [record(.private, [record(.surfaceScan)])]),
        ])])])
        try directory([tree]).validate()
    }

    @Test("A record in the wrong place is rejected")
    func testWrongPlacementRejected() {
        #expect(throws: DICOMDirectory.ValidationError.self) {
            try directory([record(.patient, [record(.image)])]).validate()
        }
        #expect(throws: DICOMDirectory.ValidationError.self) {
            try directory([record(.study)]).validate()
        }
        #expect(throws: DICOMDirectory.ValidationError.self) {
            try directory([record(.patient, [record(.study, [record(.series, [record(.surfaceScan)])])])]).validate()
        }
    }

    @Test("Retired record types from legacy DICOMDIRs are tolerated")
    func testRetiredTolerated() throws {
        let tree = record(.patient, [record(.study, [
            record(.visit),
            record(.series, [record(.overlay), record(.curve)]),
        ])])
        try directory([tree, record(.printQueue, [record(.filmSession)])]).validate()
    }
}
