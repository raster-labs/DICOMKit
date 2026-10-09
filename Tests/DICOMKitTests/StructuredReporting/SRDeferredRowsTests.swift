import XCTest
import DICOMCore
@testable import DICOMKit

/// Deferred rows closed on 2026-10-01 in the SR engine, each pinned to the DICOM 2026a text:
/// - D194: NUM with an empty Measured Value Sequence (0040,A300) stays without a value
///   (PS3.3 Table C.18.1-1, Type 2 "Zero or one Item"; C.18.1);
/// - D195: Numeric Value Qualifier Code Sequence (0040,A301), Type 1C, read and written
///   (Table C.18.1-1; PS3.16 CID 42 = CID 43 + CID 44);
/// - D196: Referenced Waveform Channels (0040,A0B0) written as (M,C) pairs (Table C.18.5-1,
///   C.18.5.1.1);
/// - D198: the Type 2 Patient (Table C.7-1), General Study (Table C.7-3) and General
///   Equipment (Table C.7-8) attributes of the SR IODs (Table A.35.3-1);
/// - D199: MeasurementReportBuilder TID 4019 / TID 1001 API and the root Content Template
///   Sequence (PS3.16 TID 1500, 1501, 4019, 1002-1004; PS3.3 Table C.18.8-1).
final class SRDeferredRowsTests: XCTestCase {

    private let length = CodedConcept(codeValue: "410668003", codingSchemeDesignator: "SCT", codeMeaning: "Length")
    private let mm = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")

    private func document(_ items: [AnyContentItem], patientName: String? = nil) -> SRDocument {
        let root = ContainerContentItem(
            conceptName: CodedConcept(codeValue: "126000", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurement Report"),
            continuityOfContent: .separate,
            contentItems: items)
        return SRDocument(
            sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID, sopInstanceUID: "1.2.3.4.5.6.7.8.9",
            patientName: patientName, studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4",
            documentTitle: root.conceptName, rootContent: root)
    }

    private func firstContentItem(_ dataSet: DataSet) throws -> SequenceItem {
        try XCTUnwrap(dataSet[.contentSequence]?.sequenceItems?.first)
    }

    // MARK: - D194 / D195: NUM without a value, Numeric Value Qualifier

    func testEmptyMeasuredValueSequenceIsNotReadAsZero() throws {
        // A NUM item as another system writes it: Measured Value Sequence present, zero Items
        // (Type 2), with the qualifier that Table C.18.1-1 requires then
        let qualifier = SequenceItem(elements: [
            DataElement.string(tag: .codeValue, vr: .SH, value: "114006"),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: "DCM"),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: "Measurement failure"),
        ])
        let num = NumericContentItem(conceptName: length, values: [], units: mm,
                                     qualifier: .measurementFailure, relationshipType: .contains)
        var dataSet = try SRDocumentSerializer().serialize(document: document([AnyContentItem(num)]))
        let item = try firstContentItem(dataSet)
        // Written: empty Measured Value Sequence and one qualifier Item
        XCTAssertEqual(item[.measuredValueSequence]?.sequenceItems?.count, 0)
        let written = try XCTUnwrap(item[.numericValueQualifierCodeSequence]?.sequenceItems)
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.string(for: .codeValue), qualifier.string(for: .codeValue))
        XCTAssertEqual(written.first?.string(for: .codingSchemeDesignator), "DCM")
        XCTAssertEqual(written.first?.string(for: .codeMeaning), "Measurement failure")

        // Read back in the default (lenient) mode: no fabricated 0, qualifier kept
        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        let read = try XCTUnwrap(parsed.findNumericItems().first)
        XCTAssertTrue(read.numericValues.isEmpty)
        XCTAssertNil(read.value)
        XCTAssertEqual(read.numericValueQualifier, .measurementFailure)

        // A qualifier code outside CID 42 is not mapped
        dataSet = try SRDocumentSerializer().serialize(document: document([AnyContentItem(
            NumericContentItem(conceptName: length, values: [], units: mm, relationshipType: .contains))]))
        let unqualified = try XCTUnwrap(SRDocumentParser().parse(dataSet: dataSet).findNumericItems().first)
        XCTAssertNil(unqualified.numericValueQualifier)
        XCTAssertTrue(unqualified.numericValues.isEmpty)
    }

    func testQualifierWithAValueRoundTrips() throws {
        // "Qualification of Numeric Value (0040,A30A) in Measured Value Sequence" — a value
        // and a qualifier together (CID 43 Positive Infinity)
        let num = NumericContentItem(conceptName: length, values: [12.5], units: mm,
                                     qualifier: .positiveInfinity, relationshipType: .contains)
        let dataSet = try SRDocumentSerializer().serialize(document: document([AnyContentItem(num)]))
        let read = try XCTUnwrap(SRDocumentParser().parse(dataSet: dataSet).findNumericItems().first)
        XCTAssertEqual(read.value, 12.5)
        XCTAssertEqual(read.numericValueQualifier, .positiveInfinity)
        XCTAssertEqual(NumericValueQualifier.positiveInfinity.code.codeValue, "114002")
    }

    // MARK: - D196: Referenced Waveform Channels

    func testReferencedWaveformChannelsAreWrittenAsMultiplexGroupChannelPairs() throws {
        // C.18.5.1.1 example: "the entire first multiplex group and channels 2 and 3 of the
        // third multiplex group" = 0001 0000 0003 0002 0003 0003
        let channels = [
            WaveformChannelReference(multiplexGroup: 1, channel: 0),
            WaveformChannelReference(multiplexGroup: 3, channel: 2),
            WaveformChannelReference(multiplexGroup: 3, channel: 3),
        ]
        let waveform = WaveformContentItem(
            waveformReference: WaveformReference(
                sopReference: ReferencedSOP(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1", sopInstanceUID: "1.2.3.7"),
                referencedChannels: channels),
            relationshipType: .contains)
        let dataSet = try SRDocumentSerializer().serialize(document: document([AnyContentItem(waveform)]))
        let refSOP = try XCTUnwrap(firstContentItem(dataSet)[.referencedSOPSequence]?.sequenceItems?.first)
        let element = try XCTUnwrap(refSOP[Tag(group: 0x0040, element: 0xA0B0)])
        XCTAssertEqual(element.vr, .US)
        XCTAssertEqual(element.uint16Values, [1, 0, 3, 2, 3, 3])

        let read = try XCTUnwrap(SRDocumentParser().parse(dataSet: dataSet).allContentItems.first?.asWaveform)
        XCTAssertEqual(read.waveformReference.referencedChannels, channels)
        XCTAssertEqual(read.waveformReference.channelNumbers, [0, 2, 3])
    }

    func testWaveformWithoutChannelsWritesNoReferencedWaveformChannels() throws {
        // Type 1C: absent when the reference applies to all channels
        let waveform = WaveformContentItem(
            waveformReference: WaveformReference(
                sopReference: ReferencedSOP(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1", sopInstanceUID: "1.2.3.7")),
            relationshipType: .contains)
        let dataSet = try SRDocumentSerializer().serialize(document: document([AnyContentItem(waveform)]))
        let refSOP = try XCTUnwrap(firstContentItem(dataSet)[.referencedSOPSequence]?.sequenceItems?.first)
        XCTAssertNil(refSOP[Tag(group: 0x0040, element: 0xA0B0)])
    }

    // MARK: - D198: Type 2 Patient / General Study / General Equipment attributes

    func testType2PatientStudyAndEquipmentAttributesAreWritten() throws {
        // Absent values: present with zero length (Type 2)
        let empty = try SRDocumentSerializer().serialize(document: document([]))
        for tag: Tag in [.patientName, .patientID, .patientBirthDate, .patientSex,
                         .studyDate, .studyTime, .referringPhysicianName, .studyID, .accessionNumber,
                         .manufacturer] {
            let element = try XCTUnwrap(empty[tag], "Type 2 \(tag) missing")
            XCTAssertEqual(element.valueData.count, 0, "\(tag)")
        }
        let parsedEmpty = try SRDocumentParser().parse(dataSet: empty)
        XCTAssertNil(parsedEmpty.patientName)
        XCTAssertNil(parsedEmpty.patientBirthDate)

        // Builder values reach the data set and read back
        let built = try MeasurementReportBuilder()
            .withPatientName("Doe^Jane").withPatientID("P7")
            .withPatientBirthDate("19700101").withPatientSex("F")
            .withReferringPhysicianName("Ref^Doc")
            .build()
            .withPatientStudyAndEquipment(studyID: "S1", manufacturer: "ACME")
        let dataSet = try SRDocumentSerializer().serialize(document: built)
        XCTAssertEqual(dataSet.string(for: .patientBirthDate), "19700101")
        XCTAssertEqual(dataSet[.patientBirthDate]?.vr, .DA)
        XCTAssertEqual(dataSet.string(for: .patientSex), "F")
        XCTAssertEqual(dataSet[.patientSex]?.vr, .CS)
        XCTAssertEqual(dataSet.string(for: .referringPhysicianName), "Ref^Doc")
        XCTAssertEqual(dataSet[.referringPhysicianName]?.vr, .PN)
        XCTAssertEqual(dataSet.string(for: .studyID), "S1")
        XCTAssertEqual(dataSet[.studyID]?.vr, .SH)
        XCTAssertEqual(dataSet.string(for: .manufacturer), "ACME")
        XCTAssertEqual(dataSet[.manufacturer]?.vr, .LO)
        let parsed = try SRDocumentParser().parse(dataSet: dataSet)
        XCTAssertEqual(parsed.patientBirthDate, "19700101")
        XCTAssertEqual(parsed.patientSex, "F")
        XCTAssertEqual(parsed.referringPhysicianName, "Ref^Doc")
        XCTAssertEqual(parsed.studyID, "S1")
        XCTAssertEqual(parsed.manufacturer, "ACME")
    }

    // MARK: - D199: TID 1500 root template, TID 4019, TID 1001

    func testRootCarriesContentTemplateSequenceDCMR1500() throws {
        let report = try MeasurementReportBuilder().build()
        XCTAssertEqual(report.rootContent.templateIdentifier, "1500")
        XCTAssertEqual(report.rootContent.mappingResource, "DCMR")
        let dataSet = try SRDocumentSerializer().serialize(document: report)
        let template = try XCTUnwrap(dataSet[.contentTemplateSequence]?.sequenceItems)
        XCTAssertEqual(template.count, 1) // "Only a single Item"
        XCTAssertEqual(template.first?.string(for: .mappingResource), "DCMR")
        XCTAssertEqual(template.first?.string(for: Tag(group: 0x0040, element: 0xDB00)), "1500")
    }

    func testAlgorithmIdentificationRows6b12bAnd9b() throws {
        let algorithm = CADAlgorithmIdentification(name: "Net", version: "2.1", manufacturer: "ACME", parameters: ["t=0.5"])
        var group = MeasurementGroupData(trackingIdentifier: "L1", trackingUID: "1.2.3.99")
        group.algorithmIdentification = CADAlgorithmIdentification(name: "Seg", version: "1")
        let report = try MeasurementReportBuilder()
            .withAlgorithmIdentification(algorithm)
            .addMeasurementGroup(group)
            .build()
        let imagingMeasurements = try XCTUnwrap(report.rootContent.contentItems
            .first { $0.conceptName?.codeValue == "126010" }?.asContainer)
        // Row 6b first, HAS CONCEPT MOD, TID 4019 rows 1, 2, 2b, 3 in template order
        let rows = imagingMeasurements.contentItems.prefix(4)
        XCTAssertEqual(rows.map { $0.conceptName?.codeValue }, ["111001", "111003", "122405", "111002"])
        XCTAssertEqual(rows.map { $0.conceptName?.codeMeaning },
                       ["Algorithm Name", "Algorithm Version", "Algorithm Manufacturer", "Algorithm Parameters"])
        XCTAssertTrue(rows.allSatisfy { $0.relationshipType == .hasConceptMod })
        XCTAssertEqual(rows.first?.asText?.textValue, "Net")
        // Row 9b inside the Measurement Group
        let measurementGroup = try XCTUnwrap(imagingMeasurements.contentItems.last?.asContainer)
        XCTAssertEqual(measurementGroup.conceptName?.codeValue, "125007")
        XCTAssertTrue(measurementGroup.contentItems.contains { $0.conceptName?.codeValue == "111001" && $0.asText?.textValue == "Seg" })

        // Row 6 is MC "IF Row 10 and Row 12 are absent": written with only the algorithm
        let alone = try MeasurementReportBuilder().withAlgorithmIdentification(algorithm).build()
        XCTAssertNotNil(alone.rootContent.contentItems.first { $0.conceptName?.codeValue == "126010" })

        // Row 12b under Qualitative Evaluations
        let qualitative = try MeasurementReportBuilder()
            .addQualitativeEvaluation(
                conceptName: CodedConcept(codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding"),
                value: CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Tumor"))
            .withQualitativeEvaluationsAlgorithmIdentification(algorithm)
            .build()
        let evaluations = try XCTUnwrap(qualitative.rootContent.contentItems
            .first { $0.conceptName?.codeValue == "C0034375" }?.asContainer)
        XCTAssertEqual(evaluations.contentItems.first?.conceptName?.codeValue, "111001")
        XCTAssertNil(qualitative.rootContent.contentItems.first { $0.conceptName?.codeValue == "126010" })
    }

    func testObserverContextTID1002() throws {
        let report = try MeasurementReportBuilder()
            .withLanguage(CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English"))
            .addObserver(.device(uid: "1.2.3.55", name: "AI", manufacturer: "ACME"))
            .addObserver(.person(name: "Doe^Jane", organizationName: "Clinic"))
            .addProcedureReported(CodedConcept(codeValue: "77477000", codingSchemeDesignator: "SCT", codeMeaning: "CT"))
            .build()
        let items = report.rootContent.contentItems
        // Row 2 (TID 1204) first, then row 3 (TID 1001), then row 4 (Procedure reported)
        XCTAssertEqual(items.map { $0.conceptName?.codeValue },
                       ["121049", "121005", "121012", "121013", "121014", "121008", "121009", "121058"])
        XCTAssertTrue(items[1...6].allSatisfy { $0.relationshipType == .hasObsContext })
        // TID 1002 row 1 Observer Type = (121007, DCM, "Device"); TID 1004 row 1 UIDREF
        XCTAssertEqual(items[1].asCode?.conceptCode.codeValue, "121007")
        XCTAssertEqual(items[2].valueType, .uidref)
        // TID 1003 row 1 PNAME
        XCTAssertEqual(items[5].valueType, .pname)

        // Round trip through the serializer keeps the order
        let parsed = try SRDocumentParser().parse(dataSet: SRDocumentSerializer().serialize(document: report))
        XCTAssertEqual(parsed.rootContent.contentItems.map { $0.conceptName?.codeValue },
                       items.map { $0.conceptName?.codeValue })
    }
}
