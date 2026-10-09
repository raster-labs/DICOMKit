//
// WaveformTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
@testable import DICOMKit
@testable import DICOMCore

final class WaveformTests: XCTestCase {

    // MARK: - WaveformType Tests

    func test_waveformType_twelveLeadECG_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1")
        XCTAssertEqual(type, .twelveLeadECG)
        XCTAssertEqual(type.description, "12-Lead ECG")
    }

    func test_waveformType_generalECG_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.2")
        XCTAssertEqual(type, .generalECG)
        XCTAssertEqual(type.description, "General ECG")
    }

    func test_waveformType_ambulatoryECG_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.3")
        XCTAssertEqual(type, .ambulatoryECG)
    }

    func test_waveformType_hemodynamic_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.2.1")
        XCTAssertEqual(type, .hemodynamic)
    }

    func test_waveformType_cardiacElectrophysiology_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.3.1")
        XCTAssertEqual(type, .cardiacElectrophysiology)
    }

    func test_waveformType_basicVoiceAudio_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.4.1")
        XCTAssertEqual(type, .basicVoiceAudio)
    }

    func test_waveformType_generalAudio_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.4.2")
        XCTAssertEqual(type, .generalAudio)
    }

    func test_waveformType_arterialPulse_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.5.1")
        XCTAssertEqual(type, .arterialPulse)
    }

    func test_waveformType_respiratory_fromSOPClassUID() {
        let type = WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.6.1")
        XCTAssertEqual(type, .respiratoryWaveform)
    }

    /// PS3.6 2026a Table A-1 — the waveform storage SOP Classes added since the first pass
    func test_waveformType_newerStorageClasses_fromSOPClassUID() {
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.1.4"), .general32BitECG)
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.6.2"), .multichannelRespiratory)
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.7.1"), .routineScalpEEG)
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.7.2"), .electromyogram)
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.7.3"), .electrooculogram)
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.7.4"), .sleepEEG)
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.8.1"), .bodyPosition)
        // Waveform Presentation State Storage is not a waveform IOD
        XCTAssertEqual(WaveformType(sopClassUID: "1.2.840.10008.5.1.4.1.1.9.100.1"), .unknown)
    }

    func test_waveformType_unknown_fromInvalidUID() {
        let type = WaveformType(sopClassUID: "1.2.3.4.5")
        XCTAssertEqual(type, .unknown)
        XCTAssertEqual(type.description, "Unknown")
    }

    func test_waveformType_roundTrip_allTypes() {
        for waveformType in WaveformType.allCases where waveformType != .unknown {
            let uid = waveformType.sopClassUID
            let roundTripped = WaveformType(sopClassUID: uid)
            XCTAssertEqual(roundTripped, waveformType, "Round-trip failed for \(waveformType)")
        }
    }

    // MARK: - WaveformSampleInterpretation Tests

    /// PS3.3 2026a Table C.10-10 — Waveform Bits Allocated and Waveform Sample Interpretation.
    /// Every Defined Term with its raw value, bit width and signedness.
    func test_sampleInterpretation_tableC10_10_allTerms() {
        let expected: [(WaveformSampleInterpretation, String, UInt16, Bool)] = [
            (.signed8,    "SB",  8, true),   // signed 8 bit linear
            (.unsigned8,  "UB",  8, false),  // unsigned 8 bit linear
            (.muLaw,      "MB",  8, false),  // 8 bit mu-law (ITU-T G.711)
            (.aLaw,       "AB",  8, false),  // 8 bit A-law (ITU-T G.711)
            (.signed16,   "SS", 16, true),   // signed 16 bit linear
            (.unsigned16, "US", 16, false),  // unsigned 16 bit linear
            (.signed32,   "SL", 32, true),   // signed 32 bit linear
            (.unsigned32, "UL", 32, false),  // unsigned 32 bit linear
            (.signed64,   "SV", 64, true),   // signed 64 bit linear
            (.unsigned64, "UV", 64, false),  // unsigned 64 bit linear
        ]
        XCTAssertEqual(WaveformSampleInterpretation.allCases.count, expected.count,
                       "Table C.10-10 has exactly ten Sample Interpretation terms")
        for (term, raw, bits, signed) in expected {
            XCTAssertEqual(term.rawValue, raw)
            XCTAssertEqual(WaveformSampleInterpretation(dicomValue: raw), term)
            XCTAssertEqual(WaveformSampleInterpretation(dicomValue: " \(raw) "), term, "surrounding spaces are ignored")
            XCTAssertEqual(term.bitsAllocated, bits, "\(raw) pairs with Waveform Bits Allocated \(bits)")
            XCTAssertEqual(term.isSigned, signed, "\(raw) signedness")
        }
        XCTAssertFalse(WaveformSampleInterpretation.muLaw.isLinear)
        XCTAssertFalse(WaveformSampleInterpretation.aLaw.isLinear)
        XCTAssertTrue(WaveformSampleInterpretation.signed16.isLinear)
        XCTAssertNil(WaveformSampleInterpretation(dicomValue: "XX"))
    }

    @available(*, deprecated)
    func test_sampleInterpretation_deprecatedNamesKeepTheirRawValues() {
        // The old names contradicted Table C.10-10; each still maps to the case with the
        // same raw value, so existing callers keep writing the same term.
        XCTAssertEqual(WaveformSampleInterpretation.unsignedInteger, .signed8)        // was "SB"
        XCTAssertEqual(WaveformSampleInterpretation.signedInteger, .signed16)         // was "SS"
        XCTAssertEqual(WaveformSampleInterpretation.unsignedByte, .unsigned8)         // was "UB"
        XCTAssertEqual(WaveformSampleInterpretation.signedShort, .unsigned16)         // was "US"
        XCTAssertTrue(WaveformSampleInterpretation.unsignedInteger.isSigned, "raw value SB is signed 8 bit linear")
        XCTAssertFalse(WaveformSampleInterpretation.signedShort.isSigned, "raw value US is unsigned 16 bit linear")
    }

    func test_multiplexGroup_channelSamples_signed32_and_unsigned32() {
        // SL / UL: 32 bit linear (Table C.10-10, Waveform Bits Allocated 32)
        var data = Data()
        for value in [Int32(-70000), Int32(70000)] {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: 4))
        }
        let signedGroup = WaveformMultiplexGroup(
            samplingFrequency: 1.0, numberOfSamples: 2,
            waveformBitsAllocated: 32, waveformBitsStored: 32,
            waveformSampleInterpretation: .signed32,
            channels: [WaveformChannel()], waveformData: data)
        XCTAssertEqual(signedGroup.channelSamples(at: 0), [-70000.0, 70000.0])

        let unsignedGroup = WaveformMultiplexGroup(
            samplingFrequency: 1.0, numberOfSamples: 2,
            waveformBitsAllocated: 32, waveformBitsStored: 32,
            waveformSampleInterpretation: .unsigned32,
            channels: [WaveformChannel()], waveformData: data)
        XCTAssertEqual(unsignedGroup.channelSamples(at: 0), [Double(UInt32(bitPattern: -70000)), 70000.0])
    }

    func test_multiplexGroup_channelSamples_signed64() {
        // SV: signed 64 bit linear (Table C.10-10, Waveform Bits Allocated 64)
        var data = Data()
        for value in [Int64(-5_000_000_000), Int64(3)] {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: 8))
        }
        let group = WaveformMultiplexGroup(
            samplingFrequency: 1.0, numberOfSamples: 2,
            waveformBitsAllocated: 64, waveformBitsStored: 64,
            waveformSampleInterpretation: .signed64,
            channels: [WaveformChannel()], waveformData: data)
        XCTAssertEqual(group.channelSamples(at: 0), [-5_000_000_000.0, 3.0])
    }

    // MARK: - WaveformOriginality Tests

    func test_waveformOriginality_fromDICOMValue() {
        XCTAssertEqual(WaveformOriginality(dicomValue: "ORIGINAL"), .original)
        XCTAssertEqual(WaveformOriginality(dicomValue: "DERIVED"), .derived)
        XCTAssertNil(WaveformOriginality(dicomValue: "INVALID"))
    }

    // MARK: - WaveformCodedConcept Tests

    func test_codedConcept_equality() {
        let concept1 = WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I")
        let concept2 = WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I")
        let concept3 = WaveformCodedConcept(codeValue: "5.6.3-9-2", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead II")

        XCTAssertEqual(concept1, concept2)
        XCTAssertNotEqual(concept1, concept3)
    }

    // MARK: - WaveformChannel Tests

    func test_channel_applyCalibration_defaultValues() {
        let channel = WaveformChannel()
        let result = channel.applyCalibration(rawValue: 100.0)
        // Default: baseline=0, sensitivity=1, correctionFactor=1, offset=0
        // (100 + 0) * 1 * 1 + 0 = 100
        XCTAssertEqual(result, 100.0, accuracy: 0.001)
    }

    func test_channel_applyCalibration_withSensitivity() {
        let channel = WaveformChannel(channelSensitivity: 0.5)
        let result = channel.applyCalibration(rawValue: 200.0)
        // (200 + 0) * 0.5 * 1 + 0 = 100
        XCTAssertEqual(result, 100.0, accuracy: 0.001)
    }

    func test_channel_applyCalibration_withAllParameters() {
        let channel = WaveformChannel(
            channelSensitivity: 2.0,
            channelSensitivityCorrectionFactor: 0.5,
            channelBaseline: 10.0,
            channelOffset: 5.0
        )
        let result = channel.applyCalibration(rawValue: 100.0)
        // (100 + 10) * 2.0 * 0.5 + 5.0 = 110 * 1.0 + 5.0 = 115.0
        XCTAssertEqual(result, 115.0, accuracy: 0.001)
    }

    // MARK: - WaveformMultiplexGroup Tests

    func test_multiplexGroup_duration() {
        let group = WaveformMultiplexGroup(
            samplingFrequency: 500.0,
            numberOfSamples: 5000,
            waveformBitsAllocated: 16,
            waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [],
            waveformData: Data()
        )
        XCTAssertEqual(group.duration, 10.0, accuracy: 0.001) // 5000/500 = 10 seconds
    }

    func test_multiplexGroup_duration_zeroFrequency() {
        let group = WaveformMultiplexGroup(
            samplingFrequency: 0.0,
            numberOfSamples: 5000,
            waveformBitsAllocated: 16,
            waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [],
            waveformData: Data()
        )
        XCTAssertEqual(group.duration, 0.0)
    }

    func test_multiplexGroup_channelSamples_signedInteger16() {
        // Create a simple 2-channel waveform with 3 samples per channel
        // Channel 0: 100, -200, 300
        // Channel 1: 50, -100, 150
        // Interleaved: [100, 50, -200, -100, 300, 150]
        var data = Data()
        let values: [Int16] = [100, 50, -200, -100, 300, 150]
        for value in values {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        }

        let channel0 = WaveformChannel(channelLabel: "Ch0")
        let channel1 = WaveformChannel(channelLabel: "Ch1")

        let group = WaveformMultiplexGroup(
            samplingFrequency: 500.0,
            numberOfSamples: 3,
            waveformBitsAllocated: 16,
            waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [channel0, channel1],
            waveformData: data
        )

        let samples0 = group.channelSamples(at: 0)
        XCTAssertEqual(samples0.count, 3)
        XCTAssertEqual(samples0[0], 100.0, accuracy: 0.001)
        XCTAssertEqual(samples0[1], -200.0, accuracy: 0.001)
        XCTAssertEqual(samples0[2], 300.0, accuracy: 0.001)

        let samples1 = group.channelSamples(at: 1)
        XCTAssertEqual(samples1.count, 3)
        XCTAssertEqual(samples1[0], 50.0, accuracy: 0.001)
        XCTAssertEqual(samples1[1], -100.0, accuracy: 0.001)
        XCTAssertEqual(samples1[2], 150.0, accuracy: 0.001)
    }

    func test_multiplexGroup_channelSamples_unsignedInteger16() {
        var data = Data()
        let values: [UInt16] = [100, 200, 300, 400]
        for value in values {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: MemoryLayout<UInt16>.size))
        }

        let channel = WaveformChannel(channelLabel: "Ch0")
        let group = WaveformMultiplexGroup(
            samplingFrequency: 250.0,
            numberOfSamples: 4,
            waveformBitsAllocated: 16,
            waveformBitsStored: 16,
            waveformSampleInterpretation: .unsigned16,
            channels: [channel],
            waveformData: data
        )

        let samples = group.channelSamples(at: 0)
        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(samples[0], 100.0, accuracy: 0.001)
        XCTAssertEqual(samples[1], 200.0, accuracy: 0.001)
        XCTAssertEqual(samples[2], 300.0, accuracy: 0.001)
        XCTAssertEqual(samples[3], 400.0, accuracy: 0.001)
    }

    func test_multiplexGroup_channelSamples_signed8bit() {
        let values: [UInt8] = [100, 0x80, 50, 0xFF] // 100, -128, 50, -1
        let data = Data(values)

        let channel = WaveformChannel(channelLabel: "Ch0")
        let group = WaveformMultiplexGroup(
            samplingFrequency: 100.0,
            numberOfSamples: 4,
            waveformBitsAllocated: 8,
            waveformBitsStored: 8,
            waveformSampleInterpretation: .signed8,
            channels: [channel],
            waveformData: data
        )

        let samples = group.channelSamples(at: 0)
        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(samples[0], 100.0, accuracy: 0.001)
        XCTAssertEqual(samples[1], -128.0, accuracy: 0.001)
        XCTAssertEqual(samples[2], 50.0, accuracy: 0.001)
        XCTAssertEqual(samples[3], -1.0, accuracy: 0.001)
    }

    func test_multiplexGroup_channelSamples_unsigned8bit() {
        let values: [UInt8] = [0, 128, 255]
        let data = Data(values)

        let channel = WaveformChannel(channelLabel: "Ch0")
        let group = WaveformMultiplexGroup(
            samplingFrequency: 100.0,
            numberOfSamples: 3,
            waveformBitsAllocated: 8,
            waveformBitsStored: 8,
            waveformSampleInterpretation: .unsigned8,
            channels: [channel],
            waveformData: data
        )

        let samples = group.channelSamples(at: 0)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(samples[1], 128.0, accuracy: 0.001)
        XCTAssertEqual(samples[2], 255.0, accuracy: 0.001)
    }

    func test_multiplexGroup_channelSamples_invalidChannelIndex() {
        let group = WaveformMultiplexGroup(
            samplingFrequency: 500.0,
            numberOfSamples: 10,
            waveformBitsAllocated: 16,
            waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [WaveformChannel(channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"))],
            waveformData: Data(count: 20)
        )

        XCTAssertTrue(group.channelSamples(at: -1).isEmpty)
        XCTAssertTrue(group.channelSamples(at: 1).isEmpty)
    }

    func test_multiplexGroup_channelSamples_withCalibration() {
        // Single channel with sensitivity = 0.001 (millivolts to volts)
        var data = Data()
        let values: [Int16] = [1000, -500]
        for value in values {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        }

        let channel = WaveformChannel(
            channelLabel: "Lead I",
            channelSensitivity: 0.001,
            channelSensitivityCorrectionFactor: 1.0,
            channelBaseline: 0.0,
            channelOffset: 0.0
        )
        let group = WaveformMultiplexGroup(
            samplingFrequency: 500.0,
            numberOfSamples: 2,
            waveformBitsAllocated: 16,
            waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [channel],
            waveformData: data
        )

        let samples = group.channelSamples(at: 0)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0], 1.0, accuracy: 0.001)   // 1000 * 0.001 = 1.0
        XCTAssertEqual(samples[1], -0.5, accuracy: 0.001)  // -500 * 0.001 = -0.5
    }

    // MARK: - Waveform Model Tests

    func test_waveform_totalChannelCount() {
        let group1 = WaveformMultiplexGroup(
            samplingFrequency: 500.0, numberOfSamples: 100,
            waveformBitsAllocated: 16, waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [WaveformChannel(), WaveformChannel(), WaveformChannel()],
            waveformData: Data()
        )
        let group2 = WaveformMultiplexGroup(
            samplingFrequency: 250.0, numberOfSamples: 50,
            waveformBitsAllocated: 16, waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [WaveformChannel(), WaveformChannel()],
            waveformData: Data()
        )

        let waveform = Waveform(
            sopInstanceUID: "1.2.3",
            sopClassUID: Waveform.twelveLeadECGStorageUID,
            studyInstanceUID: "1.2.3.4",
            seriesInstanceUID: "1.2.3.4.5",
            multiplexGroups: [group1, group2]
        )

        XCTAssertEqual(waveform.totalChannelCount, 5)
        XCTAssertEqual(waveform.totalSampleCount, 150)
        XCTAssertEqual(waveform.waveformType, .twelveLeadECG)
    }

    // MARK: - WaveformBuilder Tests

    func test_builder_build_simpleECG() throws {
        // Create a simple sine wave for testing
        var waveformData = Data()
        for i in 0..<100 {
            let value = Int16(sin(Double(i) * .pi / 50.0) * 1000.0)
            var v = value.littleEndian
            waveformData.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        }

        let waveform = try WaveformBuilder(
            waveformType: .generalECG,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .setPatientName("Smith^John")
        .setPatientID("PAT001")
        .setSeriesDescription("ECG Recording")
        .setInstanceNumber(1)
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            bitsAllocated: 16,
            sampleInterpretation: .signed16,
            channels: [
                WaveformChannel(
                    channelLabel: "Lead I",
                    channelSource: WaveformCodedConcept(
                        codeValue: "5.6.3-9-1",
                        codingSchemeDesignator: "SCPECG",
                        codeMeaning: "Lead I"
                    ),
                    channelSensitivity: 0.001
                )
            ],
            waveformData: waveformData
        )
        .build()

        XCTAssertEqual(waveform.sopClassUID, Waveform.generalECGStorageUID)
        XCTAssertEqual(waveform.patientName, "Smith^John")
        XCTAssertEqual(waveform.patientID, "PAT001")
        XCTAssertEqual(waveform.seriesDescription, "ECG Recording")
        XCTAssertEqual(waveform.modality, "ECG")
        XCTAssertEqual(waveform.multiplexGroups.count, 1)
        XCTAssertEqual(waveform.multiplexGroups[0].channels.count, 1)
        XCTAssertEqual(waveform.multiplexGroups[0].samplingFrequency, 500.0)
        XCTAssertEqual(waveform.multiplexGroups[0].numberOfSamples, 100)
        XCTAssertFalse(waveform.sopInstanceUID.isEmpty)
    }

    func test_builder_build_noMultiplexGroups_throws() {
        let builder = WaveformBuilder(
            waveformType: .generalECG,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )

        XCTAssertThrowsError(try builder.build())
    }

    func test_builder_build_withAnnotations() throws {
        var waveformData = Data()
        for _ in 0..<10 {
            var v: Int16 = 100
            waveformData.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        }

        let waveform = try WaveformBuilder(
            waveformType: .generalECG,
            studyInstanceUID: "1.2.3.4.5",
            seriesInstanceUID: "1.2.3.4.5.6"
        )
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            channels: [WaveformChannel(channelLabel: "Lead I", channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"))],
            waveformData: waveformData
        )
        .addTextAnnotation(text: "Normal sinus rhythm", groupNumber: 1)
        .addMeasurementAnnotation(
            conceptCode: WaveformCodedConcept(codeValue: "8867-4", codingSchemeDesignator: "LN", codeMeaning: "Heart rate"),
            value: 72.0,
            units: WaveformCodedConcept(codeValue: "{beats}/min", codingSchemeDesignator: "UCUM", codeMeaning: "beats per minute"),
            groupNumber: 1,
            temporalRange: .point,
            samplePositions: [0]
        )
        .build()

        XCTAssertEqual(waveform.annotations.count, 2)
        XCTAssertEqual(waveform.annotations[0].textValue, "Normal sinus rhythm")
        XCTAssertEqual(waveform.annotations[1].numericValue, 72.0)
        XCTAssertEqual(waveform.annotations[1].conceptNameCode?.codeValue, "8867-4")
    }

    func test_builder_build_customSOPInstanceUID() throws {
        var data = Data()
        var v: Int16 = 0
        data.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))

        let waveform = try WaveformBuilder(
            waveformType: .hemodynamic,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .setSOPInstanceUID("1.2.3.4.5.6.7")
        .addMultiplexGroup(
            samplingFrequency: 100.0,
            channels: [WaveformChannel(channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"))],
            waveformData: data
        )
        .build()

        XCTAssertEqual(waveform.sopInstanceUID, "1.2.3.4.5.6.7")
        XCTAssertEqual(waveform.modality, "HD")
    }

    /// PS3.3 2026a A.34.x.4.1 content constraints: "The Value of Modality (0008,0060) shall be …"
    func test_builder_defaultModality_forDifferentTypes() throws {
        let testCases: [(WaveformType, String)] = [
            (.twelveLeadECG, "ECG"),               // A.34.3
            (.generalECG, "ECG"),                  // A.34.4
            (.ambulatoryECG, "ECG"),               // A.34.5
            (.general32BitECG, "ECG"),             // A.34.18
            (.hemodynamic, "HD"),                  // A.34.6
            (.cardiacElectrophysiology, "EPS"),    // A.34.7
            (.basicVoiceAudio, "AU"),              // A.34.2
            (.generalAudio, "AU"),                 // A.34.10
            (.arterialPulse, "HD"),                // A.34.8
            (.respiratoryWaveform, "RESP"),        // A.34.9
            (.multichannelRespiratory, "RESP"),    // A.34.16
            (.routineScalpEEG, "EEG"),             // A.34.12
            (.electromyogram, "EMG"),              // A.34.13
            (.electrooculogram, "EOG"),            // A.34.14
            (.sleepEEG, "EEG"),                    // A.34.15
            (.bodyPosition, "POS"),                // A.34.17
            (.unknown, "OT"),
        ]
        XCTAssertEqual(testCases.count, WaveformType.allCases.count, "every WaveformType has a pinned Modality")

        for (waveformType, expectedModality) in testCases {
            var data = Data()
            var v: Int16 = 0
            data.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))

            let waveform = try WaveformBuilder(
                waveformType: waveformType,
                studyInstanceUID: "1.2.3",
                seriesInstanceUID: "1.2.3.4"
            )
            .addMultiplexGroup(
                samplingFrequency: 100.0,
                channels: [WaveformChannel(channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"))],
                waveformData: data
            )
            .build()

            XCTAssertEqual(waveform.modality, expectedModality,
                          "Wrong modality for \(waveformType): expected \(expectedModality), got \(waveform.modality ?? "nil")")
        }
    }

    // MARK: - DataSet Conversion (Round-trip) Tests

    func test_waveform_toDataSet_roundTrip() throws {
        // Build a waveform
        var waveformData = Data()
        let sampleValues: [Int16] = [100, 200, -100, -200, 300, 150]
        for value in sampleValues {
            var v = value.littleEndian
            waveformData.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        }

        let leadI = WaveformChannel(
            channelLabel: "Lead I",
            channelSource: WaveformCodedConcept(
                codeValue: "5.6.3-9-1",
                codingSchemeDesignator: "SCPECG",
                codeMeaning: "Lead I"
            ),
            channelSensitivity: 0.001
        )
        let leadII = WaveformChannel(
            channelLabel: "Lead II",
            channelSource: WaveformCodedConcept(
                codeValue: "5.6.3-9-2",
                codingSchemeDesignator: "SCPECG",
                codeMeaning: "Lead II"
            ),
            channelSensitivity: 0.001
        )

        let original = try WaveformBuilder(
            waveformType: .twelveLeadECG,
            studyInstanceUID: "1.2.840.99999.1",
            seriesInstanceUID: "1.2.840.99999.1.1"
        )
        .setSOPInstanceUID("1.2.840.99999.1.1.1")
        .setPatientName("Doe^Jane")
        .setPatientID("PAT002")
        .setModality("ECG")
        .setSeriesDescription("12-Lead ECG")
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            bitsAllocated: 16,
            sampleInterpretation: .signed16,
            channels: [leadI, leadII],
            waveformData: waveformData,
            originality: .original,
            label: "ECG Group"
        )
        .addTextAnnotation(text: "Normal sinus rhythm")
        .build()

        // Convert to DataSet
        let dataSet = original.toDataSet()

        // Verify key attributes
        XCTAssertEqual(dataSet.string(for: .sopClassUID), Waveform.twelveLeadECGStorageUID)
        XCTAssertEqual(dataSet.string(for: .sopInstanceUID), "1.2.840.99999.1.1.1")
        XCTAssertEqual(dataSet.string(for: .studyInstanceUID), "1.2.840.99999.1")
        XCTAssertEqual(dataSet.string(for: .seriesInstanceUID), "1.2.840.99999.1.1")
        XCTAssertEqual(dataSet.string(for: .patientName), "Doe^Jane")
        XCTAssertEqual(dataSet.string(for: .patientID), "PAT002")
        XCTAssertEqual(dataSet.string(for: .modality), "ECG")

        // Verify Waveform Sequence exists
        let waveformSeq = dataSet.sequence(for: .waveformSequence)
        XCTAssertNotNil(waveformSeq)
        XCTAssertEqual(waveformSeq?.count, 1)

        // Verify Annotation Sequence exists
        let annotationSeq = dataSet.sequence(for: .waveformAnnotationSequence)
        XCTAssertNotNil(annotationSeq)
        XCTAssertEqual(annotationSeq?.count, 1)
    }

    func test_waveform_buildDataSet() throws {
        var data = Data()
        var v: Int16 = 100
        data.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))

        let dataSet = try WaveformBuilder(
            waveformType: .generalECG,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            channels: [WaveformChannel(channelLabel: "Lead I", channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"))],
            waveformData: data
        )
        .buildDataSet()

        XCTAssertEqual(dataSet.string(for: .sopClassUID), Waveform.generalECGStorageUID)
        XCTAssertNotNil(dataSet.string(for: .sopInstanceUID))
    }

    // MARK: - WaveformParser Tests

    func test_parser_missingSOPInstanceUID_throws() {
        let dataSet = DataSet()
        XCTAssertThrowsError(try WaveformParser.parse(from: dataSet))
    }

    func test_parser_missingStudyInstanceUID_throws() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3", for: .sopInstanceUID, vr: .UI)
        XCTAssertThrowsError(try WaveformParser.parse(from: dataSet))
    }

    func test_parser_missingSeriesInstanceUID_throws() {
        var dataSet = DataSet()
        dataSet.setString("1.2.3", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        XCTAssertThrowsError(try WaveformParser.parse(from: dataSet))
    }

    func test_parser_minimalValid() throws {
        var dataSet = DataSet()
        dataSet.setString(Waveform.generalECGStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)

        let waveform = try WaveformParser.parse(from: dataSet)
        XCTAssertEqual(waveform.sopInstanceUID, "1.2.3")
        XCTAssertEqual(waveform.sopClassUID, Waveform.generalECGStorageUID)
        XCTAssertEqual(waveform.waveformType, .generalECG)
        XCTAssertTrue(waveform.multiplexGroups.isEmpty)
    }

    func test_parser_withPatientInfo() throws {
        var dataSet = DataSet()
        dataSet.setString(Waveform.generalECGStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)
        dataSet.setString("Smith^John", for: .patientName, vr: .PN)
        dataSet.setString("PAT001", for: .patientID, vr: .LO)
        dataSet.setString("ECG", for: .modality, vr: .CS)
        dataSet.setString("Resting ECG", for: .seriesDescription, vr: .LO)

        let waveform = try WaveformParser.parse(from: dataSet)
        XCTAssertEqual(waveform.patientName, "Smith^John")
        XCTAssertEqual(waveform.patientID, "PAT001")
        XCTAssertEqual(waveform.modality, "ECG")
        XCTAssertEqual(waveform.seriesDescription, "Resting ECG")
    }

    // MARK: - WaveformAnnotation Tests

    func test_annotation_textAnnotation() {
        let annotation = WaveformAnnotation(
            textValue: "Normal sinus rhythm",
            annotationGroupNumber: 1
        )
        XCTAssertEqual(annotation.textValue, "Normal sinus rhythm")
        XCTAssertEqual(annotation.annotationGroupNumber, 1)
        XCTAssertNil(annotation.numericValue)
    }

    func test_annotation_measurementAnnotation() {
        let annotation = WaveformAnnotation(
            conceptNameCode: WaveformCodedConcept(
                codeValue: "8867-4",
                codingSchemeDesignator: "LN",
                codeMeaning: "Heart rate"
            ),
            numericValue: 75.0,
            measurementUnits: WaveformCodedConcept(
                codeValue: "{beats}/min",
                codingSchemeDesignator: "UCUM",
                codeMeaning: "beats per minute"
            ),
            temporalRangeType: .point,
            referencedSamplePositions: [0, 500]
        )

        XCTAssertEqual(annotation.numericValue, 75.0)
        XCTAssertEqual(annotation.conceptNameCode?.codeValue, "8867-4")
        XCTAssertEqual(annotation.measurementUnits?.codeMeaning, "beats per minute")
        XCTAssertEqual(annotation.temporalRangeType, .point)
        XCTAssertEqual(annotation.referencedSamplePositions, [0, 500])
    }

    // MARK: - DICOMFile Integration Tests

    func test_waveform_createDICOMFile() throws {
        var waveformData = Data()
        for i in 0..<100 {
            var value = Int16(sin(Double(i) * .pi / 50.0) * 500.0).littleEndian
            waveformData.append(Data(bytes: &value, count: MemoryLayout<Int16>.size))
        }

        let dataSet = try WaveformBuilder(
            waveformType: .generalECG,
            studyInstanceUID: "1.2.840.99999.1",
            seriesInstanceUID: "1.2.840.99999.1.1"
        )
        .setSOPInstanceUID("1.2.840.99999.1.1.1")
        .setPatientName("Test^Patient")
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            channels: [WaveformChannel(channelLabel: "Lead I", channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"))],
            waveformData: waveformData
        )
        .buildDataSet()

        let dicomFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: Waveform.generalECGStorageUID,
            sopInstanceUID: "1.2.840.99999.1.1.1"
        )

        // Verify DICOM file can be written
        let fileData = try dicomFile.write()
        XCTAssertGreaterThan(fileData.count, 132) // Preamble (128) + DICM (4)
    }

    // MARK: - Multi-channel ECG Tests

    func test_builder_multiChannel_12LeadECG() throws {
        // Create 12-lead ECG data (12 channels, 500 Hz, 10 seconds)
        let numSamples = 5000
        let numChannels = 12
        var waveformData = Data()

        for sampleIndex in 0..<numSamples {
            for channelIndex in 0..<numChannels {
                let phase = Double(channelIndex) * .pi / 6.0
                let value = Int16(sin(Double(sampleIndex) * .pi / 250.0 + phase) * 500.0)
                var v = value.littleEndian
                waveformData.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
            }
        }

        let leadNames = ["Lead I", "Lead II", "Lead III", "aVR", "aVL", "aVF",
                         "V1", "V2", "V3", "V4", "V5", "V6"]

        let channels = leadNames.map { name in
            WaveformChannel(
                channelLabel: name,
                channelSource: WaveformCodedConcept(codeValue: name, codingSchemeDesignator: "99DICOMKIT", codeMeaning: name),
                channelSensitivity: 0.001,
                channelSensitivityCorrectionFactor: 1.0
            )
        }

        let waveform = try WaveformBuilder(
            waveformType: .twelveLeadECG,
            studyInstanceUID: "1.2.3.4",
            seriesInstanceUID: "1.2.3.4.5"
        )
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            bitsAllocated: 16,
            sampleInterpretation: .signed16,
            channels: channels,
            waveformData: waveformData,
            originality: .original
        )
        .build()

        XCTAssertEqual(waveform.multiplexGroups.count, 1)
        XCTAssertEqual(waveform.multiplexGroups[0].channels.count, 12)
        XCTAssertEqual(waveform.multiplexGroups[0].numberOfSamples, numSamples)
        XCTAssertEqual(waveform.multiplexGroups[0].duration, 10.0, accuracy: 0.001)
        XCTAssertEqual(waveform.totalChannelCount, 12)

        // Verify channel samples extraction works
        let leadISamples = waveform.multiplexGroups[0].channelSamples(at: 0)
        XCTAssertEqual(leadISamples.count, numSamples)
    }

    // MARK: - Builder addMultiplexGroup (pre-configured) Test

    func test_builder_addPreConfiguredMultiplexGroup() throws {
        let group = WaveformMultiplexGroup(
            samplingFrequency: 250.0,
            numberOfSamples: 100,
            waveformBitsAllocated: 16,
            waveformBitsStored: 16,
            waveformSampleInterpretation: .signed16,
            channels: [WaveformChannel(channelLabel: "Ch1", channelSource: WaveformCodedConcept(codeValue: "5.6.3-9-1", codingSchemeDesignator: "SCPECG", codeMeaning: "Lead I"))],
            waveformData: Data(count: 200)
        )

        let waveform = try WaveformBuilder(
            waveformType: .hemodynamic,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4"
        )
        .addMultiplexGroup(group)
        .build()

        XCTAssertEqual(waveform.multiplexGroups.count, 1)
        XCTAssertEqual(waveform.multiplexGroups[0].samplingFrequency, 250.0)
    }

    // MARK: - Type 1 attribute coverage (PS3.3 2026a Tables C.10-8 and C.10-9)

    private func ecgChannel(_ label: String, sensitivity: Double? = nil) -> WaveformChannel {
        WaveformChannel(
            channelLabel: label,
            channelSource: WaveformCodedConcept(codeValue: label, codingSchemeDesignator: "99DICOMKIT", codeMeaning: label),
            channelSensitivity: sensitivity)
    }

    func test_builder_writesEveryType1AttributeOfWaveformModule() throws {
        var samples = Data()
        for value in [Int16(1), Int16(-2), Int16(3), Int16(-4)] {
            var v = value.littleEndian
            samples.append(Data(bytes: &v, count: 2))
        }
        let dataSet = try WaveformBuilder(
            waveformType: .generalECG,
            studyInstanceUID: "1.2.3",
            seriesInstanceUID: "1.2.3.4")
        .addMultiplexGroup(
            samplingFrequency: 500.0,
            bitsAllocated: 16,
            sampleInterpretation: .signed16,
            bitsStored: 12,
            channels: [ecgChannel("Lead I", sensitivity: 0.001), ecgChannel("Lead II")],
            waveformData: samples,
            originality: nil)
        .buildDataSet()

        // Table C.10-8 Waveform Identification Module, all Type 1
        XCTAssertEqual(dataSet.string(for: .instanceNumber), "1", "Instance Number (0020,0013) defaults to 1")
        XCTAssertNotNil(dataSet.date(for: .contentDate), "Content Date (0008,0023)")
        XCTAssertNotNil(dataSet.time(for: .contentTime), "Content Time (0008,0033)")
        XCTAssertNotNil(dataSet.dateTime(for: .acquisitionDateTime), "Acquisition DateTime (0008,002A)")
        XCTAssertEqual(dataSet[.acquisitionDateTime]?.vr, .DT)

        // Table C.10-9 Waveform Module, Waveform Sequence Item, Type 1
        let group = try XCTUnwrap(dataSet.sequence(for: .waveformSequence)?.first)
        XCTAssertEqual(group.string(for: .waveformOriginality), "ORIGINAL", "Waveform Originality (003A,0004) is Type 1; nil is written as ORIGINAL")
        XCTAssertEqual(group[.numberOfWaveformChannels]?.uint16Value, 2)
        XCTAssertEqual(group[.numberOfWaveformSamples]?.uint32Value, 2)
        XCTAssertEqual(group.string(for: .samplingFrequency), "500.0")
        XCTAssertEqual(group[.waveformBitsAllocated]?.uint16Value, 16)
        XCTAssertEqual(group.string(for: .waveformSampleInterpretation), "SS")
        XCTAssertEqual(group[.waveformData]?.valueData, samples, "Waveform Data (5400,1010)")
        XCTAssertEqual(group[.waveformData]?.vr, .OW)

        // Channel Definition Sequence Items, Type 1 and 1C
        let channels = try XCTUnwrap(group[.channelDefinitionSequence]?.sequenceItems)
        XCTAssertEqual(channels.count, 2)
        for channel in channels {
            XCTAssertEqual(channel[.waveformBitsStored]?.uint16Value, 12, "Waveform Bits Stored (003A,021A) is Type 1")
            let source = try XCTUnwrap(channel[.channelSourceSequence]?.sequenceItems, "Channel Source Sequence (003A,0208) is Type 1")
            XCTAssertEqual(source.count, 1, "only a single Item shall be included")
            XCTAssertNotNil(source[0].string(for: .codeValue))
            XCTAssertEqual(channel.string(for: .channelSampleSkew), "0",
                           "one of Channel Time Skew / Channel Sample Skew is required (each 1C)")
        }
        // Channel Sensitivity present => Correction Factor and Baseline are required (1C)
        XCTAssertEqual(channels[0].string(for: .channelSensitivity), "0.001")
        XCTAssertEqual(channels[0].string(for: .channelSensitivityCorrectionFactor), "1")
        XCTAssertEqual(channels[0].string(for: .channelBaseline), "0")
        XCTAssertNil(channels[1].string(for: .channelSensitivityCorrectionFactor))

        // And the parser reads Bits Stored from the Channel Definition Item
        let parsed = try WaveformParser.parse(from: dataSet)
        XCTAssertEqual(parsed.multiplexGroups[0].waveformBitsStored, 12)
        XCTAssertEqual(parsed.multiplexGroups[0].originality, .original)
        XCTAssertEqual(parsed.instanceNumber, 1)
        XCTAssertNotNil(parsed.acquisitionDateTime)
    }

    func test_builder_throwsWithoutChannelSource() {
        var samples = Data()
        var v: Int16 = 1
        samples.append(Data(bytes: &v, count: 2))
        let builder = WaveformBuilder(waveformType: .generalECG, studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addMultiplexGroup(samplingFrequency: 500.0, channels: [WaveformChannel(channelLabel: "Lead I")], waveformData: samples)
        XCTAssertThrowsError(try builder.build(), "Channel Source Sequence (003A,0208) is Type 1")
    }

    func test_builder_keepsExplicitIdentificationAttributes() throws {
        var samples = Data()
        var v: Int16 = 1
        samples.append(Data(bytes: &v, count: 2))
        let acquired = DICOMDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 30, second: 5)
        let waveform = try WaveformBuilder(waveformType: .generalECG, studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .setInstanceNumber(7)
            .setContentDate(DICOMDate(year: 2026, month: 9, day: 29))
            .setContentTime(DICOMTime(hour: 8, minute: 30, second: 5))
            .setAcquisitionDateTime(acquired)
            .addMultiplexGroup(samplingFrequency: 500.0, channels: [ecgChannel("Lead I")], waveformData: samples)
            .build()
        XCTAssertEqual(waveform.instanceNumber, 7)
        XCTAssertEqual(waveform.acquisitionDateTime?.dicomString, acquired.dicomString)

        let parsed = try WaveformParser.parse(from: waveform.toDataSet())
        XCTAssertEqual(parsed.instanceNumber, 7)
        XCTAssertEqual(parsed.contentDate?.dicomString, "20260929")
        XCTAssertEqual(parsed.acquisitionDateTime?.dicomString, acquired.dicomString)
    }

    func test_referencedSamplePositions_writtenAndReadAsUL() throws {
        // PS3.6 Table 6-1: (0040,A132) Referenced Sample Positions, VR UL, VM 1-n
        var samples = Data()
        var v: Int16 = 1
        samples.append(Data(bytes: &v, count: 2))
        let positions: [UInt32] = [1, 70000, 4_000_000_000]
        let dataSet = try WaveformBuilder(waveformType: .generalECG, studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addMultiplexGroup(samplingFrequency: 500.0, channels: [ecgChannel("Lead I")], waveformData: samples)
            .addTextAnnotation(text: "QRS", temporalRange: .multipoint, samplePositions: positions)
            .buildDataSet()

        let item = try XCTUnwrap(dataSet.sequence(for: .waveformAnnotationSequence)?.first)
        let element = try XCTUnwrap(item[.referencedSamplePositions])
        XCTAssertEqual(element.vr, .UL)
        XCTAssertEqual(element.valueData.count, positions.count * 4)

        let parsed = try WaveformParser.parse(from: dataSet)
        XCTAssertEqual(parsed.annotations.first?.referencedSamplePositions, positions,
                       "values above 65535 survive only when read as 32-bit UL")
    }

    func test_referencedSamplePositions_legacyUSFallback() throws {
        var dataSet = DataSet()
        dataSet.setString(Waveform.generalECGStorageUID, for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5", for: .seriesInstanceUID, vr: .UI)
        let legacy = SequenceItem(elements: [
            DataElement.string(tag: .unformattedTextValue, vr: .ST, value: "R"),
            DataElement.uint16s(tag: .referencedSamplePositions, values: [3, 9]),
        ])
        dataSet.setSequence([legacy], for: .waveformAnnotationSequence)
        let parsed = try WaveformParser.parse(from: dataSet)
        XCTAssertEqual(parsed.annotations.first?.referencedSamplePositions, [3, 9])
    }
}
