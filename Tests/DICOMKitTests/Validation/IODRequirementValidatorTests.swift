import XCTest
import Foundation
import DICOMCore
@testable import DICOMKit

/// P-VALID: the per-IOD Type 1 / Type 2 tables of `DICOMValidator` against PS3.3
/// 2026a (Tables A.x-1 and the module tables they reference) and PS3.5 7.4.1 / 7.4.3.
final class IODRequirementValidatorTests: XCTestCase {

    // MARK: - Fixtures

    private func validate(_ ds: DataSet, sopClassUID: String, iod: String? = nil) throws -> ValidationResult {
        let file = DICOMFile.create(
            dataSet: ds,
            sopClassUID: sopClassUID,
            sopInstanceUID: ds.string(for: .sopInstanceUID) ?? "1.2.3.4.5.6",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid)
        let data = try file.write()
        return try DICOMValidator(level: 3, iod: iod, force: false)
            .validate(data: data, filePath: "test.dcm")
    }

    /// IOD-level errors only (the level-2 format checks are not under test here).
    private func iodErrors(_ result: ValidationResult) -> [String] {
        result.errors.map(\.message).filter { $0.contains("Type") || $0.contains("Enumerated") || $0.contains("must be") }
    }

    /// Patient (Table C.7-1), General Study (Table C.7-3), SOP Common (Table C.12-1).
    private func commonModules(_ ds: inout DataSet, sopClassUID: String) {
        ds.setString("Doe^Jane", for: .patientName, vr: .PN)
        ds.setString("MRN-1", for: .patientID, vr: .LO)
        ds.setString("", for: .patientBirthDate, vr: .DA)
        ds.setString("", for: .patientSex, vr: .CS)
        ds.setString("1.2.3.4.100", for: .studyInstanceUID, vr: .UI)
        ds.setString("", for: .studyDate, vr: .DA)
        ds.setString("", for: .studyTime, vr: .TM)
        ds.setString("", for: .referringPhysicianName, vr: .PN)
        ds.setString("", for: .studyID, vr: .SH)
        ds.setString("", for: .accessionNumber, vr: .SH)
        ds.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6", for: .sopInstanceUID, vr: .UI)
        ds.setString("", for: .manufacturer, vr: .LO)
    }

    /// Image Pixel (Table C.7-11b/c) for a 2x2 MONOCHROME2 16-bit image.
    private func imagePixel(_ ds: inout DataSet) {
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(2, for: .rows)
        ds.setUInt16(2, for: .columns)
        ds.setUInt16(16, for: .bitsAllocated)
        ds.setUInt16(12, for: .bitsStored)
        ds.setUInt16(11, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: Data(repeating: 0, count: 8))
    }

    /// A CT Image conformant to Table A.3-1's Mandatory modules.
    private func conformantCT() -> DataSet {
        var ds = DataSet()
        commonModules(&ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setString("1.2.3.4.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("", for: .seriesNumber, vr: .IS)
        ds.setString("HFS", for: .patientPosition, vr: .CS)               // C.7-5a 2C for CT
        ds.setString("1.2.3.4.300", for: .frameOfReferenceUID, vr: .UI)
        ds.setString("", for: .positionReferenceIndicator, vr: .LO)
        ds.setString("", for: .instanceNumber, vr: .IS)
        ds.setStrings(["0.5", "0.5"], for: .pixelSpacing, vr: .DS)
        ds.setStrings(["1", "0", "0", "0", "1", "0"], for: .imageOrientationPatient, vr: .DS)
        ds.setStrings(["0", "0", "0"], for: .imagePositionPatient, vr: .DS)
        ds.setString("", for: .sliceThickness, vr: .DS)
        imagePixel(&ds)
        ds.setStrings(["ORIGINAL", "PRIMARY", "AXIAL"], for: .imageType, vr: .CS)
        ds.setString("-1024", for: .rescaleIntercept, vr: .DS)
        ds.setString("1", for: .rescaleSlope, vr: .DS)
        ds.setString("", for: .kvp, vr: .DS)
        ds.setString("", for: .acquisitionNumber, vr: .IS)
        return ds
    }

    private func conformantGSPS() -> DataSet {
        var ds = DataSet()
        commonModules(&ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.11.1")
        ds.setString("PR", for: .modality, vr: .CS)
        ds.setString("1.2.3.4.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("1", for: .seriesNumber, vr: .IS)
        ds.setString("20260929", for: .presentationCreationDate, vr: .DA)
        ds.setString("120000", for: .presentationCreationTime, vr: .TM)
        ds.setString("1", for: .instanceNumber, vr: .IS)
        ds.setString("DEFAULT", for: .contentLabel, vr: .CS)
        ds.setString("", for: .contentDescription, vr: .LO)
        ds.setString("", for: .contentCreatorName, vr: .PN)
        let image = SequenceItem(elements: [
            DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2"),
            DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: "1.2.3.4.5.7"),
        ])
        var refSeries = DataSet()
        refSeries.setString("1.2.3.4.201", for: .seriesInstanceUID, vr: .UI)
        refSeries.setSequence([image], for: .referencedImageSequence)
        ds.setSequence([SequenceItem(elements: refSeries.tags.compactMap { refSeries[$0] })], for: .referencedSeriesSequence)
        var area = DataSet()
        area.setStrings(["1", "1"], for: .displayedAreaTopLeftHandCorner, vr: .SL)
        area.setStrings(["512", "512"], for: .displayedAreaBottomRightHandCorner, vr: .SL)
        area.setString("SCALE TO FIT", for: .presentationSizeMode, vr: .CS)
        ds.setSequence([SequenceItem(elements: area.tags.compactMap { area[$0] })], for: .displayedAreaSelectionSequence)
        ds.setString("IDENTITY", for: .presentationLUTShape, vr: .CS)
        return ds
    }

    private func conformantSR() -> DataSet {
        var ds = DataSet()
        commonModules(&ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11")
        ds.setString("SR", for: .modality, vr: .CS)
        ds.setString("1.2.3.4.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("1", for: .seriesNumber, vr: .IS)
        ds.setSequence([], for: .referencedPerformedProcedureStepSequence)
        ds.setString("1", for: .instanceNumber, vr: .IS)
        ds.setString("PARTIAL", for: .completionFlag, vr: .CS)
        ds.setString("UNVERIFIED", for: .verificationFlag, vr: .CS)
        ds.setString("20260929", for: .contentDate, vr: .DA)
        ds.setString("120000", for: .contentTime, vr: .TM)
        ds.setSequence([], for: Tag(group: 0x0040, element: 0xA372))
        ds.setString("CONTAINER", for: .valueType, vr: .CS)
        ds.setSequence([SequenceItem(elements: [
            DataElement.string(tag: .codeValue, vr: .SH, value: "18748-4"),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: "LN"),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: "Diagnostic Imaging Report"),
        ])], for: .conceptNameCodeSequence)
        ds.setString("SEPARATE", for: .continuityOfContent, vr: .CS)
        return ds
    }

    // MARK: - Table contents

    func testCTTableCoversTheMandatoryModulesOfTableA3_1() {
        let rows = IODRequirementTables.ctImage
        let tags = Set(rows.map(\.tag))
        // Table C.7-1 Patient, all Type 2
        for tag in [Tag.patientName, .patientID, .patientBirthDate, .patientSex] {
            XCTAssertEqual(rows.first { $0.tag == tag }?.type, .type2, "\(tag) is Type 2 in Table C.7-1")
        }
        // Table C.7-3 General Study
        XCTAssertEqual(rows.first { $0.tag == .studyInstanceUID }?.type, .type1)
        for tag in [Tag.studyDate, .studyTime, .referringPhysicianName, .studyID, .accessionNumber] {
            XCTAssertEqual(rows.first { $0.tag == tag }?.type, .type2, "\(tag) is Type 2 in Table C.7-3")
        }
        // Table C.7-5a General Series, Table C.7-6 Frame of Reference, Table C.7-8
        XCTAssertEqual(rows.first { $0.tag == .modality }?.type, .type1)
        XCTAssertEqual(rows.first { $0.tag == .seriesNumber }?.type, .type2)
        XCTAssertEqual(rows.first { $0.tag == .frameOfReferenceUID }?.type, .type1)
        XCTAssertEqual(rows.first { $0.tag == .positionReferenceIndicator }?.type, .type2)
        XCTAssertEqual(rows.first { $0.tag == .manufacturer }?.type, .type2)
        // Table C.7-10 Image Plane, Table C.7-11b/c Image Pixel, Table C.8-3 CT Image
        for tag in [Tag.pixelSpacing, .imageOrientationPatient, .imagePositionPatient, .rows, .columns,
                    .samplesPerPixel, .photometricInterpretation, .bitsAllocated, .bitsStored, .highBit,
                    .pixelRepresentation, .pixelData, .imageType, .rescaleIntercept, .rescaleSlope,
                    .sopClassUID, .sopInstanceUID] {
            XCTAssertEqual(rows.first { $0.tag == tag }?.type, .type1, "\(tag) is Type 1")
        }
        for tag in [Tag.sliceThickness, .kvp, .acquisitionNumber, .instanceNumber] {
            XCTAssertEqual(rows.first { $0.tag == tag }?.type, .type2, "\(tag) is Type 2")
        }
        // 4 + 6 + 3 + 2 + 1 + 1 + 4 + 9 + 5 + 2 = 37 distinct attributes
        XCTAssertEqual(tags.count, 37, "CT table has \(tags.count) rows")
        XCTAssertTrue(rows.allSatisfy { $0.module.contains("Table") }, "every row cites its PS3.3 table")
    }

    func testTablesAreKeyedBySOPClassUID() {
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.2"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.4"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.1"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.6.1"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.7"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.11.1"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.11.3"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.88.11"])
        XCTAssertNotNil(IODRequirementTables.bySOPClassUID["1.2.840.10008.5.1.4.1.1.88.59"])
    }

    func testMRTableHasTheMRImageTypes() {
        let rows = IODRequirementTables.mrImage
        for tag in [Tag.scanningSequence, .sequenceVariant] {
            XCTAssertEqual(rows.first { $0.tag == tag }?.type, .type1, "Table C.8-4 Type 1")
        }
        for tag in [Tag.scanOptions, .mrAcquisitionType, .echoTime, .echoTrainLength] {
            XCTAssertEqual(rows.first { $0.tag == tag }?.type, .type2, "Table C.8-4 Type 2")
        }
        XCTAssertNil(rows.first { $0.tag == .rescaleIntercept }, "Rescale is a CT Image row, not MR")
    }

    func testSecondaryCaptureDoesNotRequireModality() {
        // Table C.8-24: Modality Type 3 "shall override the definition in the C.7.3.1".
        XCTAssertNil(IODRequirementTables.secondaryCaptureImage.first { $0.tag == .modality })
        XCTAssertEqual(IODRequirementTables.secondaryCaptureImage.first { $0.tag == .conversionType }?.type, .type1)
        XCTAssertNil(IODRequirementTables.secondaryCaptureImage.first { $0.tag == .manufacturer },
                     "General Equipment is U in Table A.8-1")
    }

    // MARK: - CT: conformant, missing Type 1, missing Type 2, empty Type 1

    func testConformantCTHasNoIODErrors() throws {
        let result = try validate(conformantCT(), sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertTrue(result.errors.isEmpty, "unexpected: \(result.errors.map(\.message))")
        XCTAssertTrue(result.isValid)
    }

    func testEveryMissingType1IsAnErrorForCT() throws {
        let base = conformantCT()
        for req in IODRequirementTables.ctImage where req.type == .type1 {
            // SOP Class/Instance UID absence is caught (and the file rejected) at
            // level 1/2 by other checks; the IOD table still lists them.
            if req.tag == .sopClassUID || req.tag == .sopInstanceUID { continue }
            var ds = base
            ds.remove(tag: req.tag)
            let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
            XCTAssertTrue(result.errors.contains {
                $0.tag == req.tag && $0.message.contains("Missing Type 1 attribute \(req.name)")
                    && $0.message.contains("PS3.5 7.4.1")
            }, "missing \(req.name) must be a Type 1 error; got \(result.errors.map(\.message))")
        }
    }

    func testEveryMissingType2IsAnErrorForCT() throws {
        let base = conformantCT()
        for req in IODRequirementTables.ctImage where req.type == .type2 {
            var ds = base
            ds.remove(tag: req.tag)
            let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
            XCTAssertTrue(result.errors.contains {
                $0.tag == req.tag && $0.message.contains("Missing Type 2 attribute \(req.name)")
                    && $0.message.contains("PS3.5 7.4.3")
            }, "missing \(req.name) must be a Type 2 error; got \(result.errors.map(\.message))")
        }
    }

    func testEmptyType1IsAnErrorButEmptyType2IsNot() throws {
        var ds = conformantCT()
        ds.setString("", for: .rescaleSlope, vr: .DS)     // Type 1, Table C.8-3
        ds.setString("", for: .kvp, vr: .DS)              // Type 2, Table C.8-3 (already empty)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertTrue(result.errors.contains {
            $0.tag == .rescaleSlope && $0.message.contains("Type 1 attribute Rescale Slope is empty")
        }, "\(result.errors.map(\.message))")
        XCTAssertFalse(result.errors.contains { $0.tag == .kvp }, "an empty Type 2 is legal (PS3.5 7.4.3)")
    }

    func testCTPatientPositionIsRequiredWhenPatientOrientationCodeSequenceAbsent() throws {
        var ds = conformantCT()
        ds.remove(tag: .patientPosition)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertTrue(result.errors.contains { $0.tag == .patientPosition && $0.message.contains("Type 2C") },
                      "\(result.errors.map(\.message))")
    }

    func testPlanarConfigurationRequiredForMultiSamplePixels() throws {
        var ds = conformantCT()
        ds.setUInt16(3, for: .samplesPerPixel)
        ds.setString("RGB", for: .photometricInterpretation, vr: .CS)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
        XCTAssertTrue(result.errors.contains { $0.tag == .planarConfiguration && $0.message.contains("Type 1C") })
    }

    // MARK: - GSPS

    func testConformantGSPSHasNoIODErrors() throws {
        let result = try validate(conformantGSPS(), sopClassUID: "1.2.840.10008.5.1.4.1.1.11.1")
        XCTAssertTrue(result.errors.isEmpty, "unexpected: \(result.errors.map(\.message))")
    }

    func testGSPSModalityOtherThanPRIsAnError() throws {
        var ds = conformantGSPS()
        ds.setString("OT", for: .modality, vr: .CS)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.11.1")
        XCTAssertTrue(result.errors.contains {
            $0.tag == .modality && $0.message.contains("must be PR") && $0.message.contains("C.11.9")
        }, "Table C.11.9-1 Enumerated Value PR; got \(result.errors.map(\.message))")
        XCTAssertFalse(result.warnings.contains { $0.message.contains("Modality should be 'PR'") },
                       "no longer a warning")
    }

    func testGSPSMissingPresentationLUTIsAnError() throws {
        var ds = conformantGSPS()
        ds.remove(tag: .presentationLUTShape)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.11.1")
        XCTAssertTrue(result.errors.contains { $0.message.contains("Softcopy Presentation LUT") })
    }

    func testGSPSMissingType1RowsAreErrors() throws {
        for req in IODRequirementTables.grayscaleSoftcopyPresentationState where req.type == .type1 {
            if req.tag == .sopClassUID || req.tag == .sopInstanceUID { continue }
            var ds = conformantGSPS()
            ds.remove(tag: req.tag)
            let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.11.1")
            XCTAssertTrue(result.errors.contains { $0.tag == req.tag && $0.message.contains("Missing Type 1") },
                          "\(req.name): \(result.errors.map(\.message))")
        }
    }

    func testGSPSDisplayedAreaItemType1RowsAreErrors() throws {
        var ds = conformantGSPS()
        var area = DataSet()
        area.setStrings(["1", "1"], for: .displayedAreaTopLeftHandCorner, vr: .SL)
        // Bottom Right Hand Corner and Presentation Size Mode missing (Table C.10-4 Type 1)
        ds.setSequence([SequenceItem(elements: area.tags.compactMap { area[$0] })], for: .displayedAreaSelectionSequence)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.11.1")
        XCTAssertTrue(result.errors.contains { $0.tag == .displayedAreaBottomRightHandCorner })
        XCTAssertTrue(result.errors.contains { $0.tag == .presentationSizeMode })
    }

    // MARK: - SR

    func testConformantBasicTextSRHasNoIODErrors() throws {
        let result = try validate(conformantSR(), sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11")
        XCTAssertTrue(result.errors.isEmpty, "unexpected: \(result.errors.map(\.message))")
    }

    func testSRMissingType1RowsAreErrors() throws {
        for req in IODRequirementTables.structuredReport where req.type == .type1 {
            if req.tag == .sopClassUID || req.tag == .sopInstanceUID { continue }
            var ds = conformantSR()
            ds.remove(tag: req.tag)
            let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11")
            XCTAssertTrue(result.errors.contains { $0.tag == req.tag && $0.message.contains("Missing Type 1") },
                          "\(req.name): \(result.errors.map(\.message))")
        }
    }

    func testSRModalityIsEnumeratedSRAndKOSIsKO() throws {
        var ds = conformantSR()
        ds.setString("OT", for: .modality, vr: .CS)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11")
        XCTAssertTrue(result.errors.contains { $0.tag == .modality && $0.message.contains("must be SR") })

        var kos = conformantSR()
        kos.setString("1.2.840.10008.5.1.4.1.1.88.59", for: .sopClassUID, vr: .UI)
        kos.setString("KO", for: .modality, vr: .CS)
        kos.setSequence([], for: Tag(group: 0x0040, element: 0xA375))
        let kosResult = try validate(kos, sopClassUID: "1.2.840.10008.5.1.4.1.1.88.59")
        XCTAssertFalse(kosResult.errors.contains { $0.tag == .modality },
                       "Table C.17.6-1: KO is the Enumerated Value for Key Object Selection; got \(kosResult.errors.map(\.message))")
        XCTAssertTrue(kosResult.errors.contains { $0.message.contains("Current Requested Procedure Evidence Sequence is empty") },
                      "Table C.17.6-2 Type 1 sequence must not be empty")
    }

    func testVerifiedSRRequiresVerifyingObserverSequence() throws {
        var ds = conformantSR()
        ds.setString("COMPLETE", for: .completionFlag, vr: .CS)
        ds.setString("VERIFIED", for: .verificationFlag, vr: .CS)
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11")
        XCTAssertTrue(result.errors.contains { $0.tag == .verifyingObserverSequence && $0.message.contains("Type 1C") })
    }

    // MARK: - SC auto-detection

    func testSecondaryCaptureIsDetectedAndValidated() throws {
        var ds = DataSet()
        commonModules(&ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7")
        ds.setString("1.2.3.4.200", for: .seriesInstanceUID, vr: .UI)
        ds.setString("", for: .seriesNumber, vr: .IS)
        ds.setString("", for: .instanceNumber, vr: .IS)
        ds.setString("", for: .patientOrientation, vr: .CS)
        imagePixel(&ds)
        // Conversion Type (Table C.8-24, Type 1) deliberately missing; Modality absent is fine.
        let result = try validate(ds, sopClassUID: "1.2.840.10008.5.1.4.1.1.7")
        XCTAssertTrue(result.errors.contains { $0.tag == .conversionType && $0.message.contains("Missing Type 1") },
                      "\(result.errors.map(\.message))")
        XCTAssertFalse(result.errors.contains { $0.tag == .modality })
        XCTAssertFalse(result.warnings.contains { $0.message.contains("IOD validation not implemented") })
    }
}
