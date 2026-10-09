//
// WaveformParseRegressionTests.swift
// DICOMKit
//
// Regression coverage for the waveform tag-group fix (group 0x5400 → 0x003A).
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// A standards-compliant waveform carries its acquisition + channel-definition
/// attributes in DICOM group 0x003A (PS3.6). These were previously declared in
/// group 0x5400, so `WaveformParser` looked for Sampling Frequency / Number of
/// Waveform Channels / Number of Waveform Samples at the wrong tags and threw
/// "Missing or invalid Sampling Frequency" on every conformant ECG — surfaced to
/// the user as "Could not decode the waveform". This locks in the fix end-to-end.
final class WaveformParseRegressionTests: XCTestCase {

    func test_parser_recoversMultiplexGroupAndChannels_fromGroup003A() throws {
        let leads = ["Lead I", "Lead II", "V1"]
        let samplesPerChannel = 500
        // Channel-interleaved 16-bit samples: samplesPerChannel × channelCount.
        var waveformData = Data()
        for sampleIndex in 0..<samplesPerChannel {
            for channelIndex in 0..<leads.count {
                let phase = Double(channelIndex) * .pi / 6.0
                var v = Int16(sin(Double(sampleIndex) * .pi / 25.0 + phase) * 800.0).littleEndian
                waveformData.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
            }
        }

        let channels = leads.map {
            WaveformChannel(channelLabel: $0,
                            channelSource: WaveformCodedConcept(codeValue: $0, codingSchemeDesignator: "99DICOMKIT", codeMeaning: $0),
                            channelSensitivity: 0.001, channelSensitivityCorrectionFactor: 1.0)
        }

        // buildDataSet() encodes the acquisition + channel-definition attributes with
        // the (corrected) group-0x003A tags — i.e. what any conformant writer produces.
        let dataSet = try WaveformBuilder(
            waveformType: .twelveLeadECG,
            studyInstanceUID: "1.2.840.99999.7",
            seriesInstanceUID: "1.2.840.99999.7.1"
        )
        .setSOPInstanceUID("1.2.840.99999.7.1.1")
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            bitsAllocated: 16,
            sampleInterpretation: .signed16,
            channels: channels,
            waveformData: waveformData,
            originality: .original,
            label: "ECG"
        )
        .buildDataSet()

        // The acquisition attributes must physically live in group 0x003A in the
        // encoded item — asserted against raw tags, independent of the Tag constants.
        let group = try XCTUnwrap(dataSet.sequence(for: .waveformSequence)?.first)
        XCTAssertNotNil(group.elements[DICOMCore.Tag(group: 0x003A, element: 0x0005)],
                        "Number of Waveform Channels must be (003A,0005)")
        XCTAssertNotNil(group.elements[DICOMCore.Tag(group: 0x003A, element: 0x001A)],
                        "Sampling Frequency must be (003A,001A)")
        XCTAssertNil(group.elements[DICOMCore.Tag(group: 0x5400, element: 0x0105)],
                     "Acquisition attributes must not be written to the old (5400,…) group")

        // And the full parse path recovers a populated group with its channels.
        let waveform = try WaveformParser.parse(from: dataSet)
        XCTAssertEqual(waveform.multiplexGroups.count, 1)
        let parsed = try XCTUnwrap(waveform.multiplexGroups.first)
        XCTAssertEqual(parsed.samplingFrequency, 500.0, accuracy: 0.001)
        XCTAssertEqual(parsed.numberOfSamples, samplesPerChannel)
        XCTAssertEqual(parsed.channels.count, leads.count)
        XCTAssertEqual(parsed.channels.map { $0.channelLabel }, leads)
    }
}
