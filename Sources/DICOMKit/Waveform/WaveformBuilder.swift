// NEMA-verified: 2026a, checked 2026-09-29 — writes every Type 1 attribute of PS3.3 2026a Table C.10-8 (Instance Number, Content Date/Time, Acquisition DateTime) and Table C.10-9 (Waveform Originality, Number of Channels/Samples, Sampling Frequency, Channel Definition Sequence with Channel Source Sequence and Waveform Bits Stored, one of Channel Time/Sample Skew, Waveform Bits Allocated, Sample Interpretation, Waveform Data); (0070,0006) as ST and (0040,A132) as UL per PS3.6 Table 6-1; Modality per A.34.x content constraints
//
// WaveformBuilder.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-09.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Builder for creating DICOM Waveform objects
///
/// WaveformBuilder provides a fluent API for constructing Waveform IODs,
/// enabling ECG, hemodynamic, audio, and other physiological signal data
/// to be wrapped as DICOM objects for storage and transmission.
///
/// Example - Creating a simple ECG waveform:
/// ```swift
/// let waveform = try WaveformBuilder(
///     waveformType: .twelveLeadECG,
///     studyInstanceUID: "1.2.3.4.5",
///     seriesInstanceUID: "1.2.3.4.5.6"
/// )
/// .setPatientName("Smith^John")
/// .setPatientID("12345")
/// .addMultiplexGroup(
///     samplingFrequency: 500.0,
///     bitsAllocated: 16,
///     sampleInterpretation: .signed16,
///     channels: [
///         WaveformChannel(channelLabel: "Lead I",
///                        channelSource: WaveformCodedConcept(
///                            codeValue: "5.6.3-9-1",
///                            codingSchemeDesignator: "SCPECG",
///                            codeMeaning: "Lead I"))
///     ],
///     waveformData: ecgData
/// )
/// .build()
/// ```
///
/// Every channel needs a `channelSource`: Channel Source Sequence (003A,0208) is Type 1 in
/// the Channel Definition Sequence (PS3.3 Table C.10-9), and `build()` throws without it.
/// Instance Number, Content Date, Content Time and Acquisition DateTime (Type 1 in the
/// Waveform Identification Module, Table C.10-8) are filled in from the clock when not set.
///
/// Reference: PS3.3 A.34 - Waveform IODs
/// Reference: PS3.3 C.10.8 - Waveform Identification Module
/// Reference: PS3.3 C.10.9 - Waveform Module
public final class WaveformBuilder {

    // MARK: - Required Configuration

    private let waveformType: WaveformType
    private let studyInstanceUID: String
    private let seriesInstanceUID: String

    // MARK: - Optional Metadata

    private var sopInstanceUID: String?
    private var instanceNumber: Int?
    private var patientName: String?
    private var patientID: String?
    private var modality: String?
    private var seriesDescription: String?
    private var seriesNumber: Int?
    private var contentDate: DICOMDate?
    private var contentTime: DICOMTime?
    private var acquisitionDateTime: DICOMDateTime?
    private var multiplexGroups: [WaveformMultiplexGroup] = []
    private var annotations: [WaveformAnnotation] = []

    // MARK: - Initialization

    /// Creates a new WaveformBuilder
    ///
    /// - Parameters:
    ///   - waveformType: The type of waveform to create
    ///   - studyInstanceUID: The Study Instance UID
    ///   - seriesInstanceUID: The Series Instance UID
    public init(
        waveformType: WaveformType,
        studyInstanceUID: String,
        seriesInstanceUID: String
    ) {
        self.waveformType = waveformType
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
    }

    // MARK: - Fluent Setters

    /// Sets the SOP Instance UID (auto-generated if not set)
    @discardableResult
    public func setSOPInstanceUID(_ uid: String) -> Self {
        self.sopInstanceUID = uid
        return self
    }

    /// Sets the Instance Number
    @discardableResult
    public func setInstanceNumber(_ number: Int) -> Self {
        self.instanceNumber = number
        return self
    }

    /// Sets the Patient Name
    @discardableResult
    public func setPatientName(_ name: String) -> Self {
        self.patientName = name
        return self
    }

    /// Sets the Patient ID
    @discardableResult
    public func setPatientID(_ id: String) -> Self {
        self.patientID = id
        return self
    }

    /// Sets the Modality
    @discardableResult
    public func setModality(_ modality: String) -> Self {
        self.modality = modality
        return self
    }

    /// Sets the Series Description
    @discardableResult
    public func setSeriesDescription(_ description: String) -> Self {
        self.seriesDescription = description
        return self
    }

    /// Sets the Series Number
    @discardableResult
    public func setSeriesNumber(_ number: Int) -> Self {
        self.seriesNumber = number
        return self
    }

    /// Sets the Content Date
    @discardableResult
    public func setContentDate(_ date: DICOMDate) -> Self {
        self.contentDate = date
        return self
    }

    /// Sets the Content Time
    @discardableResult
    public func setContentTime(_ time: DICOMTime) -> Self {
        self.contentTime = time
        return self
    }

    /// Sets Acquisition DateTime (0008,002A), the start of the acquisition and the
    /// reference for Multiplex Group Time Offset (PS3.3 Table C.10-8, Type 1)
    @discardableResult
    public func setAcquisitionDateTime(_ dateTime: DICOMDateTime) -> Self {
        self.acquisitionDateTime = dateTime
        return self
    }

    /// Adds a multiplex group with channel data
    ///
    /// - Parameters:
    ///   - samplingFrequency: Sampling frequency in Hz
    ///   - bitsAllocated: Waveform Bits Allocated (5400,1004): 8, 16, 32 or 64, matching
    ///     `sampleInterpretation` per PS3.3 Table C.10-10
    ///   - sampleInterpretation: Waveform Sample Interpretation (5400,1006)
    ///   - bitsStored: Waveform Bits Stored (003A,021A), the significant bits per sample;
    ///     defaults to `bitsAllocated`
    ///   - channels: Channel definitions; each needs a `channelSource` (Type 1)
    ///   - waveformData: Raw interleaved waveform data
    ///   - originality: Waveform Originality (003A,0004); `nil` is written as ORIGINAL
    ///   - label: Label for the multiplex group
    /// - Returns: Self for method chaining
    @discardableResult
    public func addMultiplexGroup(
        samplingFrequency: Double,
        bitsAllocated: UInt16 = 16,
        sampleInterpretation: WaveformSampleInterpretation = .signed16,
        bitsStored: UInt16? = nil,
        channels: [WaveformChannel],
        waveformData: Data,
        originality: WaveformOriginality? = .original,
        label: String? = nil
    ) -> Self {
        let bytesPerSample = Int(bitsAllocated) / 8
        let channelCount = channels.count
        let numberOfSamples: Int
        if channelCount > 0 && bytesPerSample > 0 {
            numberOfSamples = waveformData.count / (channelCount * bytesPerSample)
        } else {
            numberOfSamples = 0
        }

        let group = WaveformMultiplexGroup(
            samplingFrequency: samplingFrequency,
            numberOfSamples: numberOfSamples,
            waveformBitsAllocated: bitsAllocated,
            waveformBitsStored: bitsStored ?? bitsAllocated,
            waveformSampleInterpretation: sampleInterpretation,
            channels: channels,
            waveformData: waveformData,
            originality: originality,
            multiplexGroupLabel: label
        )
        self.multiplexGroups.append(group)
        return self
    }

    /// Adds a pre-configured multiplex group
    @discardableResult
    public func addMultiplexGroup(_ group: WaveformMultiplexGroup) -> Self {
        self.multiplexGroups.append(group)
        return self
    }

    /// Adds a waveform annotation
    @discardableResult
    public func addAnnotation(_ annotation: WaveformAnnotation) -> Self {
        self.annotations.append(annotation)
        return self
    }

    /// Adds a text annotation
    @discardableResult
    public func addTextAnnotation(
        text: String,
        groupNumber: UInt16? = nil,
        temporalRange: TemporalRangeType? = nil,
        samplePositions: [UInt32]? = nil
    ) -> Self {
        let annotation = WaveformAnnotation(
            textValue: text,
            annotationGroupNumber: groupNumber,
            temporalRangeType: temporalRange,
            referencedSamplePositions: samplePositions
        )
        self.annotations.append(annotation)
        return self
    }

    /// Adds a measurement annotation
    @discardableResult
    public func addMeasurementAnnotation(
        conceptCode: WaveformCodedConcept,
        value: Double,
        units: WaveformCodedConcept,
        groupNumber: UInt16? = nil,
        temporalRange: TemporalRangeType? = nil,
        samplePositions: [UInt32]? = nil
    ) -> Self {
        let annotation = WaveformAnnotation(
            conceptNameCode: conceptCode,
            numericValue: value,
            measurementUnits: units,
            annotationGroupNumber: groupNumber,
            temporalRangeType: temporalRange,
            referencedSamplePositions: samplePositions
        )
        self.annotations.append(annotation)
        return self
    }

    // MARK: - Build

    /// Builds the Waveform
    ///
    /// Type 1 attributes of the Waveform Identification Module (PS3.3 Table C.10-8) that
    /// were not set are defaulted: Instance Number to 1, Content Date/Time to the current
    /// clock, Acquisition DateTime to Content Date + Content Time.
    ///
    /// - Returns: The constructed Waveform
    /// - Throws: DICOMError if no multiplex group was added, a multiplex group has no
    ///   channel (Channel Definition Sequence is Type 1, one or more Items), or a channel
    ///   has no `channelSource` (Channel Source Sequence (003A,0208) is Type 1)
    public func build() throws -> Waveform {
        guard !multiplexGroups.isEmpty else {
            throw DICOMError.parsingFailed("At least one multiplex group is required")
        }

        for (groupIndex, group) in multiplexGroups.enumerated() {
            guard !group.channels.isEmpty else {
                throw DICOMError.parsingFailed(
                    "Multiplex group \(groupIndex + 1) has no channels; Channel Definition Sequence (003A,0200) is Type 1 (PS3.3 Table C.10-9)")
            }
            for (channelIndex, channel) in group.channels.enumerated() where channel.channelSource == nil {
                throw DICOMError.parsingFailed(
                    "Channel \(channelIndex + 1) of multiplex group \(groupIndex + 1) has no channelSource; Channel Source Sequence (003A,0208) is Type 1 (PS3.3 Table C.10-9)")
            }
        }

        let instanceUID = sopInstanceUID ?? UIDGenerator.generateSOPInstanceUID().value

        let now = Date()
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let finalContentDate = contentDate ?? DICOMDate(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
        let finalContentTime = contentTime ?? DICOMTime(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0
        )
        let finalAcquisitionDateTime = acquisitionDateTime ?? DICOMDateTime(
            year: finalContentDate.year,
            month: finalContentDate.month,
            day: finalContentDate.day,
            hour: finalContentTime.hour,
            minute: finalContentTime.minute,
            second: finalContentTime.second
        )

        return Waveform(
            sopInstanceUID: instanceUID,
            sopClassUID: waveformType.sopClassUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber ?? 1,
            patientName: patientName,
            patientID: patientID,
            modality: modality ?? defaultModality(),
            seriesDescription: seriesDescription,
            seriesNumber: seriesNumber,
            contentDate: finalContentDate,
            contentTime: finalContentTime,
            acquisitionDateTime: finalAcquisitionDateTime,
            multiplexGroups: multiplexGroups,
            annotations: annotations
        )
    }

    /// Builds the Waveform and converts it to a DICOM DataSet
    ///
    /// - Returns: A DataSet ready for DICOM file creation
    /// - Throws: DICOMError if building fails
    public func buildDataSet() throws -> DataSet {
        let waveform = try build()
        return waveform.toDataSet()
    }

    /// Returns the Modality the IOD's content constraints require (PS3.3 A.34.x.4.1),
    /// OT for an unknown SOP Class
    private func defaultModality() -> String {
        (waveformType.modality ?? Modality.ot).rawValue
    }
}

// MARK: - DataSet Conversion

extension Waveform {

    /// Converts the Waveform to a DICOM DataSet
    ///
    /// Creates a DataSet with all required and optional attributes for the
    /// Waveform IOD.
    ///
    /// - Returns: A DataSet representation of this waveform
    public func toDataSet() -> DataSet {
        var dataSet = DataSet()

        // SOP Common Module
        dataSet.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        dataSet.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)

        // Patient Module
        if let patientName = patientName {
            dataSet.setString(patientName, for: .patientName, vr: .PN)
        }
        if let patientID = patientID {
            dataSet.setString(patientID, for: .patientID, vr: .LO)
        }

        // General Study Module
        dataSet.setString(studyInstanceUID, for: .studyInstanceUID, vr: .UI)

        // General Series Module
        dataSet.setString(seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)

        if let modality = modality {
            dataSet.setString(modality, for: .modality, vr: .CS)
        }
        if let seriesDescription = seriesDescription {
            dataSet.setString(seriesDescription, for: .seriesDescription, vr: .LO)
        }
        if let seriesNumber = seriesNumber {
            dataSet.setString(String(seriesNumber), for: .seriesNumber, vr: .IS)
        }

        // Instance Number
        if let instanceNumber = instanceNumber {
            dataSet.setString(String(instanceNumber), for: .instanceNumber, vr: .IS)
        }

        // Waveform Identification Module (PS3.3 Table C.10-8): Content Date, Content
        // Time and Acquisition DateTime are Type 1; WaveformBuilder.build() fills them.
        if let contentDate = contentDate {
            dataSet.setString(contentDate.dicomString, for: .contentDate, vr: .DA)
        }
        if let contentTime = contentTime {
            dataSet.setString(contentTime.dicomString, for: .contentTime, vr: .TM)
        }
        if let acquisitionDateTime = acquisitionDateTime {
            dataSet.setString(acquisitionDateTime.dicomString, for: .acquisitionDateTime, vr: .DT)
        }

        // Waveform Sequence
        if !multiplexGroups.isEmpty {
            let waveformItems = multiplexGroups.map { group -> SequenceItem in
                serializeMultiplexGroup(group)
            }
            dataSet.setSequence(waveformItems, for: .waveformSequence)
        }

        // Waveform Annotation Sequence
        if !annotations.isEmpty {
            let annotationItems = annotations.map { annotation -> SequenceItem in
                serializeAnnotation(annotation)
            }
            dataSet.setSequence(annotationItems, for: .waveformAnnotationSequence)
        }

        return dataSet
    }

    /// Serializes a multiplex group to a SequenceItem
    private func serializeMultiplexGroup(_ group: WaveformMultiplexGroup) -> SequenceItem {
        var elements: [DataElement] = []

        // Sampling Frequency
        elements.append(DataElement.string(
            tag: .samplingFrequency,
            vr: .DS,
            value: String(group.samplingFrequency)
        ))

        // Number of Waveform Channels
        elements.append(DataElement.uint16(
            tag: .numberOfWaveformChannels,
            value: UInt16(group.channels.count)
        ))

        // Number of Waveform Samples (003A,0010) — VR UL: a 4-byte binary integer,
        // not an ASCII decimal string.
        elements.append(DataElement.uint32(
            tag: .numberOfWaveformSamples,
            value: UInt32(group.numberOfSamples)
        ))

        // Waveform Bits Allocated (5400,1004)
        elements.append(DataElement.uint16(
            tag: .waveformBitsAllocated,
            value: group.waveformBitsAllocated
        ))

        // Waveform Sample Interpretation (5400,1006)
        elements.append(DataElement.string(
            tag: .waveformSampleInterpretation,
            vr: .CS,
            value: group.waveformSampleInterpretation.rawValue
        ))

        // Waveform Originality (003A,0004) — Type 1 (PS3.3 Table C.10-9). A group built
        // without a value is written as ORIGINAL, the term for source sample data
        // (C.10.9.1.3).
        elements.append(DataElement.string(
            tag: .waveformOriginality,
            vr: .CS,
            value: (group.originality ?? .original).rawValue
        ))

        // Multiplex Group Label
        if let label = group.multiplexGroupLabel {
            elements.append(DataElement.string(
                tag: .multiplexGroupLabel,
                vr: .SH,
                value: label
            ))
        }

        // Multiplex Group Time Offset
        if let offset = group.multiplexGroupTimeOffset {
            elements.append(DataElement.string(
                tag: .multiplexGroupTimeOffset,
                vr: .DS,
                value: String(offset)
            ))
        }

        // Trigger Time Offset
        if let offset = group.triggerTimeOffset {
            elements.append(DataElement.string(
                tag: .triggerTimeOffset,
                vr: .DS,
                value: String(offset)
            ))
        }

        // Channel Definition Sequence (003A,0200) — Type 1, one Item per channel
        if !group.channels.isEmpty {
            let channelItems = group.channels.map { channel -> SequenceItem in
                serializeChannel(channel, bitsStored: group.waveformBitsStored)
            }
            // Serialize channel sequence
            let writer = DICOMWriter()
            var channelData = Data()
            for channelItem in channelItems {
                channelData.append(writer.serializeSequenceItem(channelItem))
            }
            elements.append(DataElement(
                tag: .channelDefinitionSequence,
                vr: .SQ,
                length: UInt32(channelData.count),
                valueData: channelData,
                sequenceItems: channelItems
            ))
        }

        // Waveform Data (5400,1010) — Type 1; OB or OW (PS3.6 Table 6-1). OB for 8-bit
        // samples, OW otherwise.
        elements.append(DataElement.data(
            tag: .waveformData,
            vr: group.waveformBitsAllocated == 8 ? .OB : .OW,
            data: group.waveformData
        ))

        return SequenceItem(elements: elements)
    }

    /// Serializes a channel definition to a SequenceItem
    ///
    /// Writes the Type 1 attributes of a Channel Definition Sequence Item (PS3.3 Table
    /// C.10-9): Channel Source Sequence (003A,0208) and Waveform Bits Stored (003A,021A),
    /// plus one of Channel Time Skew / Channel Sample Skew (each 1C, required if the other
    /// is absent) — Channel Sample Skew 0 when neither was given.
    private func serializeChannel(_ channel: WaveformChannel, bitsStored: UInt16) -> SequenceItem {
        var elements: [DataElement] = []

        if let label = channel.channelLabel {
            elements.append(DataElement.string(tag: .channelLabel, vr: .SH, value: label))
        }

        if let status = channel.channelStatus {
            elements.append(DataElement.string(tag: .channelStatus, vr: .CS, value: status.joined(separator: "\\")))
        }

        // Waveform Bits Stored (003A,021A) — Type 1, VR US
        elements.append(DataElement.uint16(tag: .waveformBitsStored, value: bitsStored))

        if let source = channel.channelSource {
            let sourceItem = createCodeSequenceItem(source)
            let writer = DICOMWriter()
            let itemData = writer.serializeSequenceItem(sourceItem)
            elements.append(DataElement(
                tag: .channelSourceSequence,
                vr: .SQ,
                length: UInt32(itemData.count),
                valueData: itemData,
                sequenceItems: [sourceItem]
            ))
        }

        if let modifiers = channel.channelSourceModifiers, !modifiers.isEmpty {
            let modifierItems = modifiers.map { createCodeSequenceItem($0) }
            let writer = DICOMWriter()
            var modData = Data()
            for modItem in modifierItems {
                modData.append(writer.serializeSequenceItem(modItem))
            }
            elements.append(DataElement(
                tag: .channelSourceModifiersSequence,
                vr: .SQ,
                length: UInt32(modData.count),
                valueData: modData,
                sequenceItems: modifierItems
            ))
        }

        if let sensitivity = channel.channelSensitivity {
            elements.append(DataElement.string(tag: .channelSensitivity, vr: .DS, value: String(sensitivity)))
        }

        if let units = channel.channelSensitivityUnits {
            let unitsItem = createCodeSequenceItem(units)
            let writer = DICOMWriter()
            let itemData = writer.serializeSequenceItem(unitsItem)
            elements.append(DataElement(
                tag: .channelSensitivityUnitsSequence,
                vr: .SQ,
                length: UInt32(itemData.count),
                valueData: itemData,
                sequenceItems: [unitsItem]
            ))
        }

        // Channel Sensitivity Correction Factor (003A,0212) and Channel Baseline (003A,0213)
        // are 1C, required if Channel Sensitivity is present: identity values (1, 0) are
        // written when the caller gave a sensitivity but not these.
        if let factor = channel.channelSensitivityCorrectionFactor {
            elements.append(DataElement.string(tag: .channelSensitivityCorrectionFactor, vr: .DS, value: String(factor)))
        } else if channel.channelSensitivity != nil {
            elements.append(DataElement.string(tag: .channelSensitivityCorrectionFactor, vr: .DS, value: "1"))
        }

        if let baseline = channel.channelBaseline {
            elements.append(DataElement.string(tag: .channelBaseline, vr: .DS, value: String(baseline)))
        } else if channel.channelSensitivity != nil {
            elements.append(DataElement.string(tag: .channelBaseline, vr: .DS, value: "0"))
        }

        if let skew = channel.channelTimeSkew {
            elements.append(DataElement.string(tag: .channelTimeSkew, vr: .DS, value: String(skew)))
        }

        if let skew = channel.channelSampleSkew {
            elements.append(DataElement.string(tag: .channelSampleSkew, vr: .DS, value: String(skew)))
        } else if channel.channelTimeSkew == nil {
            elements.append(DataElement.string(tag: .channelSampleSkew, vr: .DS, value: "0"))
        }

        if let offset = channel.channelOffset {
            elements.append(DataElement.string(tag: .channelOffset, vr: .DS, value: String(offset)))
        }

        if let freq = channel.filterLowFrequency {
            elements.append(DataElement.string(tag: .filterLowFrequency, vr: .DS, value: String(freq)))
        }

        if let freq = channel.filterHighFrequency {
            elements.append(DataElement.string(tag: .filterHighFrequency, vr: .DS, value: String(freq)))
        }

        if let freq = channel.notchFilterFrequency {
            elements.append(DataElement.string(tag: .notchFilterFrequency, vr: .DS, value: String(freq)))
        }

        if let bandwidth = channel.notchFilterBandwidth {
            elements.append(DataElement.string(tag: .notchFilterBandwidth, vr: .DS, value: String(bandwidth)))
        }

        return SequenceItem(elements: elements)
    }

    /// Serializes an annotation to a SequenceItem
    private func serializeAnnotation(_ annotation: WaveformAnnotation) -> SequenceItem {
        var elements: [DataElement] = []

        if let text = annotation.textValue {
            elements.append(DataElement.string(tag: .unformattedTextValue, vr: .ST, value: text))
        }

        if let concept = annotation.conceptNameCode {
            let conceptItem = createCodeSequenceItem(concept)
            let writer = DICOMWriter()
            let itemData = writer.serializeSequenceItem(conceptItem)
            elements.append(DataElement(
                tag: .conceptNameCodeSequence,
                vr: .SQ,
                length: UInt32(itemData.count),
                valueData: itemData,
                sequenceItems: [conceptItem]
            ))
        }

        if let value = annotation.numericValue {
            elements.append(DataElement.string(tag: .numericValue, vr: .DS, value: String(value)))
        }

        if let units = annotation.measurementUnits {
            let unitsItem = createCodeSequenceItem(units)
            let writer = DICOMWriter()
            let itemData = writer.serializeSequenceItem(unitsItem)
            elements.append(DataElement(
                tag: .measurementUnitsCodeSequence,
                vr: .SQ,
                length: UInt32(itemData.count),
                valueData: itemData,
                sequenceItems: [unitsItem]
            ))
        }

        if let groupNumber = annotation.annotationGroupNumber {
            elements.append(DataElement.uint16(tag: .annotationGroupNumber, value: groupNumber))
        }

        if let rangeType = annotation.temporalRangeType {
            elements.append(DataElement.string(tag: .temporalRangeType, vr: .CS, value: rangeType.rawValue))
        }

        if let positions = annotation.referencedSamplePositions, !positions.isEmpty {
            // Serialize as UL (unsigned long) values
            var data = Data()
            for pos in positions {
                var value = pos.littleEndian
                data.append(Data(bytes: &value, count: MemoryLayout<UInt32>.size))
            }
            elements.append(DataElement.data(tag: .referencedSamplePositions, vr: .UL, data: data))
        }

        if let offsets = annotation.referencedTimeOffsets, !offsets.isEmpty {
            let offsetStr = offsets.map { String($0) }.joined(separator: "\\")
            elements.append(DataElement.string(tag: .referencedTimeOffsets, vr: .DS, value: offsetStr))
        }

        return SequenceItem(elements: elements)
    }

    /// Creates a SequenceItem for a coded concept
    private func createCodeSequenceItem(_ code: WaveformCodedConcept) -> SequenceItem {
        var elements: [DataElement] = []
        elements.append(DataElement.string(tag: .codeValue, vr: .SH, value: code.codeValue))
        elements.append(DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: code.codingSchemeDesignator))
        elements.append(DataElement.string(tag: .codeMeaning, vr: .LO, value: code.codeMeaning))
        return SequenceItem(elements: elements)
    }
}
