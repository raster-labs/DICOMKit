import XCTest
import DICOMCore
@testable import DICOMKit

/// End-user harness for the DICOM tag audit.
///
/// Reads the foreign-toolkit (pydicom) fixtures built by
/// `Scripts/audit_fixtures/make_audit_fixtures.py` and checks that every corrected
/// attribute comes back through the public parsers. Skipped unless
/// `AUDIT_FIXTURES` points at the directory holding the fixtures:
///
///     python3 Scripts/audit_fixtures/make_audit_fixtures.py /tmp/audit_fixtures
///     AUDIT_FIXTURES=/tmp/audit_fixtures swift test --filter AuditFixtureHarnessTests
final class AuditFixtureHarnessTests: XCTestCase {

    private func fixture(_ name: String) throws -> DataSet {
        guard let dir = ProcessInfo.processInfo.environment["AUDIT_FIXTURES"] else {
            throw XCTSkip("Set AUDIT_FIXTURES to the directory produced by make_audit_fixtures.py")
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try DICOMFile.read(from: data).dataSet
    }

    // MARK: Hanging Protocol (findings #1–#13, #52)

    func test_hangingProtocol_userGroupPriorsSelectorsAndUSValues() throws {
        let hp = try HangingProtocolParser().parse(from: try fixture("hp.dcm"))
        XCTAssertEqual(hp.name, "Audit CT Chest")
        XCTAssertEqual(hp.userGroups, ["AuditRadiologists"])          // (0072,0010)
        XCTAssertEqual(hp.numberOfPriorsReferenced, 2)                  // (0072,0014)
        XCTAssertEqual(hp.imageSets.count, 1)
        let selectors = hp.imageSets[0].selectors
        XCTAssertEqual(selectors.count, 2)                              // (0072,0022) items
        XCTAssertEqual(selectors.first?.attribute, .modality)           // (0072,0026)
        XCTAssertEqual(selectors.first?.values, ["CT"])                 // (0072,0062)
        XCTAssertEqual(selectors.last?.attribute, .rows)
        XCTAssertEqual(selectors.last?.values, ["512"])                 // (0072,007A) US
        XCTAssertEqual(hp.numberOfScreens, 1)
        XCTAssertEqual(hp.screenDefinitions.first?.horizontalPixels, 1920) // US, was nil (#52)
        XCTAssertEqual(hp.screenDefinitions.first?.verticalPixels, 1080)
    }

    // MARK: RT (findings #17–#19)

    func test_rtPlan_brachyApplicationSetupNumberAndTypeNotSwapped() throws {
        let plan = try RTPlanParser.parse(from: try fixture("rtplan.dcm"))
        let setup = try XCTUnwrap(plan.brachyApplicationSetups.first)
        XCTAssertEqual(setup.number, 7)                                 // (300A,0234)
        XCTAssertEqual(setup.type, "FLETCHER_SUIT")                     // (300A,0232)
    }

    func test_rtStruct_elementalCompositionSequenceTag() throws {
        let ds = try fixture("rtstruct.dcm")
        let obs = try XCTUnwrap(ds[.rtROIObservationsSequence]?.sequenceItems?.first)
        let items = obs[.roiElementalCompositionSequence]?.sequenceItems   // (3006,00B6)
        XCTAssertEqual(items?.count, 2)
    }

    // MARK: Waveform (findings #20–#22)

    func test_waveform_annotationTextFrom0070_0006_andTriggerAndDisplayScale() throws {
        let ds = try fixture("ecg.dcm")
        let wf = try WaveformParser.parse(from: ds)
        XCTAssertEqual(wf.annotations.first?.textValue, "Sinus rhythm, audit annotation")
        let mg = try XCTUnwrap(ds[.waveformSequence]?.sequenceItems?.first)
        XCTAssertEqual(mg[.triggerSamplePosition]?.uint32Value, 25)     // (0018,106E) UL
        XCTAssertEqual(mg[.waveformDataDisplayScale]?.float32Value, 10) // (003A,0230) FL
    }

    // MARK: Real World Value / Parametric Map (findings #14–#16, #61, LUT Explanation)

    func test_enhancedMR_lutFormRWV_readsExplanationFirstLastAndData() throws {
        let luts = RealWorldValueLUTParser.parse(from: try fixture("enhanced_mr.dcm"))
        let lut = try XCTUnwrap(luts.first)
        XCTAssertEqual(lut.label, "ADC Mapping")
        XCTAssertEqual(lut.explanation, "Apparent Diffusion Coefficient")   // (0028,3003)
        guard case .lut(let d, let data) = lut.transformation else { return XCTFail("expected LUT form") }
        XCTAssertEqual(d.firstValueMapped, 0)
        XCTAssertEqual(d.lastValueMapped, 63)
        XCTAssertEqual(data.count, 64)
        XCTAssertEqual(data[10], 0.010, accuracy: 1e-9)
    }

    func test_enhancedPET_doubleFloatFirstLastNotSwapped() throws {
        let luts = RealWorldValueLUTParser.parse(from: try fixture("enhanced_pet_fd.dcm"))
        let lut = try XCTUnwrap(luts.first)
        guard case .lut(let d, _) = lut.transformation else { return XCTFail("expected LUT form") }
        XCTAssertEqual(d.firstValueMapped, 0)                            // (0040,9214)
        XCTAssertEqual(d.lastValueMapped, 63)                            // (0040,9213)
    }

    func test_parametricMap_linearRWVSlopeInterceptReadAsFD() throws {
        let map = try ParametricMapParser.parse(from: try fixture("pmap.dcm"))
        let mapping = try XCTUnwrap(map.realWorldValueMappings.first)
        XCTAssertEqual(mapping.label, "T1")
        XCTAssertEqual(mapping.explanation, "T1 relaxation time")
        guard case .linear(let slope, let intercept) = mapping.mapping else { return XCTFail("expected linear") }
        XCTAssertEqual(slope, 2.5); XCTAssertEqual(intercept, 0)
    }

    // MARK: Multiframe (findings #25, #26)

    func test_enhancedMR_flatten_carriesSegmentedKSpaceTraversal() throws {
        let ds = try fixture("enhanced_mr.dcm")
        let legacy = FunctionalGroupFlattener.flatten(ds, frameIndex: 0, toClassic: true)
        XCTAssertEqual(legacy.string(for: Tag(group: 0x0018, element: 0x9033)), "SINGLE")
    }

    func test_frameDimensionPointer_tag0028_000A() throws {
        let ds = try fixture("frame_dim_pointer.dcm")
        XCTAssertNotNil(ds[.frameDimensionPointer])                      // (0028,000A)
        XCTAssertEqual(Tag.frameDimensionPointer, Tag(group: 0x0028, element: 0x000A))
    }

    // MARK: Structured Reporting (findings #23, #24)

    func test_sr_mappingResourceUIDAndName() throws {
        let ds = try fixture("sr_mapping_resource.dcm")
        let tmpl = try XCTUnwrap(ds[.contentTemplateSequence]?.sequenceItems?.first)
        XCTAssertEqual(tmpl.string(for: .mappingResourceUID), "1.2.840.10008.8.1.1")        // (0008,0118)
        XCTAssertEqual(tmpl.string(for: .mappingResourceName), "DICOM Content Mapping Resource") // (0008,0122)
        XCTAssertNoThrow(try SRDocumentParser().parse(dataSet: ds))
    }
}
