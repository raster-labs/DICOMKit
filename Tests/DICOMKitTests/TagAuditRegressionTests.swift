//
// TagAuditRegressionTests.swift
// DICOMKitTests
//
// Regression tests for the parsers the 2026-09 tag audit corrected. Each test
// builds its input from the *numeric* PS3.6 tag rather than a `Tag.xxx`
// constant, so a wrong constant cannot make the test pass by round-tripping
// through itself.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class TagAuditRegressionTests: XCTestCase {

    private func tag(_ g: UInt16, _ e: UInt16) -> Tag { Tag(group: g, element: e) }

    private func sequence(_ t: Tag, _ items: [SequenceItem]) -> DataElement {
        DataElement(tag: t, vr: .SQ, length: 0, valueData: Data(), sequenceItems: items)
    }

    /// Measurement Units Code Sequence (0040,08EA) — Type 1 in the RWV mapping item.
    private var unitsSequence: DataElement {
        sequence(tag(0x0040, 0x08EA), [SequenceItem(elements: [
            DataElement.string(tag: .codeValue, vr: .SH, value: "1"),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: "UCUM"),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: "no units"),
        ])])
    }

    /// Enhanced-image layout: Real World Value Mapping Sequence (0040,9096) inside
    /// the Shared Functional Groups Sequence (5200,9229) item.
    private func enhancedDataSet(rwvMapping item: SequenceItem) -> DataSet {
        var dataSet = DataSet()
        let shared = SequenceItem(elements: [sequence(tag(0x0040, 0x9096), [item])])
        dataSet.setSequence([shared], for: tag(0x5200, 0x9229))
        return dataSet
    }

    // MARK: - Real World Value LUT (LUT form) — RealWorldValueLUTParser

    func test_realWorldValueLUT_lutForm_usesFirstLastAndDataTags() throws {
        // PS3.3 C.7.6.16.2.11: LUT form carries
        //   (0040,9216) Real World Value First Value Mapped  US
        //   (0040,9211) Real World Value Last Value Mapped   US
        //   (0040,9212) Real World Value LUT Data            FD 1-n
        let item = SequenceItem(elements: [
            DataElement.uint16(tag: tag(0x0040, 0x9216), value: 0),
            DataElement.uint16(tag: tag(0x0040, 0x9211), value: 3),
            DataElement.float64s(tag: tag(0x0040, 0x9212), values: [10, 20, 30, 40]),
            DataElement.string(tag: tag(0x0040, 0x9210), vr: .SH, value: "LUT"),
            unitsSequence,
        ])
        let dataSet = enhancedDataSet(rwvMapping: item)

        let luts = RealWorldValueLUTParser.parse(from: dataSet)
        XCTAssertEqual(luts.count, 1, "LUT-form mapping must parse")
        guard case .lut(let descriptor, let data)? = luts.first?.transformation else {
            return XCTFail("expected .lut transformation, got \(String(describing: luts.first?.transformation))")
        }
        XCTAssertEqual(descriptor.firstValueMapped, 0)
        XCTAssertEqual(descriptor.lastValueMapped, 3)
        XCTAssertEqual(data, [10, 20, 30, 40])
    }

    func test_realWorldValueLUT_lutForm_doubleFloatRange() throws {
        // FD range: (0040,9214) First, (0040,9213) Last — note the element order.
        let item = SequenceItem(elements: [
            DataElement.float64(tag: tag(0x0040, 0x9214), value: -1.5),
            DataElement.float64(tag: tag(0x0040, 0x9213), value: 1.5),
            DataElement.float64s(tag: tag(0x0040, 0x9212), values: [1, 2]),
            unitsSequence,
        ])
        let dataSet = enhancedDataSet(rwvMapping: item)

        guard case .lut(let descriptor, _)? = RealWorldValueLUTParser.parse(from: dataSet).first?.transformation else {
            return XCTFail("expected .lut transformation")
        }
        XCTAssertEqual(descriptor.firstValueMapped, -1.5)
        XCTAssertEqual(descriptor.lastValueMapped, 1.5)
    }

    // MARK: - Waveform annotation text — (0070,0006), with (0040,A160) fallback

    private func ecgDataSet(annotation: String?) throws -> DataSet {
        var samples = Data()
        var v: Int16 = 100
        samples.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        let lead = WaveformChannel(
            channelLabel: "Lead I",
            channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"),
            channelSensitivity: 0.001)
        var builder = WaveformBuilder(
            waveformType: .twelveLeadECG,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4")
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            bitsAllocated: 16,
            sampleInterpretation: .signedInteger,
            channels: [lead],
            waveformData: samples)
        if let annotation {
            builder = builder.addTextAnnotation(text: annotation)
        }
        return try builder.build().toDataSet()
    }

    func test_waveformAnnotation_isWrittenToUnformattedTextValue() throws {
        let dataSet = try ecgDataSet(annotation: "Sinus rhythm")
        let items = try XCTUnwrap(dataSet.sequence(for: tag(0x0040, 0xB020))) // Waveform Annotation Sequence
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].string(for: tag(0x0070, 0x0006)), "Sinus rhythm",
                       "Waveform Annotation Module text is Unformatted Text Value (0070,0006)")
        XCTAssertNil(items[0][tag(0x0040, 0xA160)], "SR Text Value must not be written")
    }

    func test_waveformAnnotation_readsLegacyTextValueAsFallback() throws {
        var dataSet = try ecgDataSet(annotation: nil)
        // A file written by DICOMKit before the fix carried (0040,A160).
        let legacy = SequenceItem(elements: [
            DataElement.string(tag: tag(0x0040, 0xA160), vr: .UT, value: "Legacy note"),
        ])
        dataSet.setSequence([legacy], for: tag(0x0040, 0xB020))

        let waveform = try WaveformParser.parse(from: dataSet)
        XCTAssertEqual(waveform.annotations.first?.textValue, "Legacy note")
    }

    // MARK: - Hanging Protocol — serializer writes the PS3.6 group 0072 tags

    func test_hangingProtocol_writesStandardTags() throws {
        let hp = HangingProtocol(
            name: "Audit",
            level: .site,
            numberOfPriorsReferenced: 2,
            environments: [HangingProtocolEnvironment(modality: "CT")],
            userGroups: ["Radiology"],
            imageSets: [ImageSetDefinition(
                number: 1,
                selectors: [ImageSetSelector(attribute: .modality, values: ["CT"], usageFlag: .match)])],
            numberOfScreens: 1)
        let ds = try HangingProtocolSerializer().serialize(protocol: hp)

        XCTAssertEqual(ds.uint16(for: tag(0x0072, 0x0014)), 2, "Number of Priors Referenced is (0072,0014)")
        XCTAssertEqual(ds.string(for: tag(0x0072, 0x0010)), "Radiology", "HP User Group Name is (0072,0010)")
        XCTAssertNotNil(ds.sequence(for: tag(0x0072, 0x000C)), "Definition items go in HP Definition Sequence (0072,000C)")
        XCTAssertNil(ds[tag(0x0072, 0x0016)], "(0072,0016) is not a DICOM tag")

        let imageSet = try XCTUnwrap(ds.sequence(for: tag(0x0072, 0x0020))?.first)
        let selectors = try XCTUnwrap(imageSet[tag(0x0072, 0x0022)]?.sequenceItems,
                                      "selectors go in Image Set Selector Sequence (0072,0022)")
        XCTAssertNotNil(selectors.first?[tag(0x0072, 0x0026)], "Selector Attribute is (0072,0026)")
        XCTAssertEqual(selectors.first?.string(for: tag(0x0072, 0x0024)), "MATCH", "Usage Flag is (0072,0024)")
        XCTAssertEqual(selectors.first?.string(for: tag(0x0072, 0x0050)), "CS", "Selector Attribute VR is (0072,0050)")
        XCTAssertEqual(selectors.first?[tag(0x0072, 0x0062)]?.stringValue, "CT", "the value goes in Selector CS Value (0072,0062)")
        XCTAssertNil(selectors.first?[tag(0x0008, 0x0060)], "not under the selected attribute's own tag")
        XCTAssertEqual(selectors.first?[tag(0x0072, 0x0028)]?.uint16Value, 0, "Selector Value Number (0072,0028) is Type 1; 0 = any value")

        // PS3.3 2026a Table C.23.1-1: Image Set Number (0072,0032) and Image Set
        // Selector Category (0072,0034) sit in Time Based Image Sets Sequence
        // (0072,0030) items, not in the Image Sets Sequence item itself.
        XCTAssertNil(imageSet[tag(0x0072, 0x0032)])
        XCTAssertNil(imageSet[tag(0x0072, 0x0034)])
        let timeBased = try XCTUnwrap(imageSet[tag(0x0072, 0x0030)]?.sequenceItems?.first,
                                      "Time Based Image Sets Sequence is (0072,0030)")
        XCTAssertEqual(timeBased[tag(0x0072, 0x0032)]?.uint16Value, 1, "Image Set Number is (0072,0032)")
        XCTAssertEqual(timeBased.string(for: tag(0x0072, 0x0034)), "RELATIVE_TIME", "Image Set Selector Category is (0072,0034)")
        XCTAssertNotNil(ds[tag(0x0072, 0x0102)], "Nominal Screen Definition Sequence (0072,0102) is Type 2")
        XCTAssertNotNil(ds[tag(0x0072, 0x000E)], "HP User Identification Code Sequence (0072,000E) is Type 2")

        // And the parser reads the same numeric layout back.
        let parsed = try HangingProtocolParser().parse(from: ds)
        XCTAssertEqual(parsed.numberOfPriorsReferenced, 2)
        XCTAssertEqual(parsed.userGroups, ["Radiology"])
        XCTAssertEqual(parsed.environments.first?.modality, "CT")
        XCTAssertEqual(parsed.imageSets.first?.selectors.first?.attribute, .modality)
        XCTAssertEqual(parsed.imageSets.first?.selectors.first?.values, ["CT"])
    }

    func test_rtPlan_applicationSetupNumberAndTypeTags() {
        XCTAssertEqual(Tag.applicationSetupNumber, tag(0x300A, 0x0234))
        XCTAssertEqual(Tag.applicationSetupType, tag(0x300A, 0x0232))
    }
}
