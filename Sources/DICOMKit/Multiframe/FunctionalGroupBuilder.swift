// NEMA-verified: 2026a, checked 2026-09-29 — Frame Acquisition Number written as US per PS3.6 2026a Table 6-1; macro membership per PS3.3 C.7.6.16 recorded; Sup 157 kept as provenance
import Foundation
import DICOMCore

/// Builds the Multi-frame Functional Groups + Multi-frame Dimension modules from
/// a sorted list of single-frame data sets.
///
/// Factoring rule (highdicom `_add_functional_group`): an attribute that is
/// present with the same value in every frame is shared; if *any* attribute of a
/// macro varies, the whole macro goes per-frame. Frame Content is always
/// per-frame. Attributes lifted into a macro are reported in `liftedTags` so the
/// caller removes them from the top level; attributes that vary between frames
/// but belong to no macro go into the Unassigned Per-Frame Converted Attributes
/// Sequence (Legacy Converted targets) or are dropped with a warning.
public enum FunctionalGroupBuilder {

    public struct Options: Sendable {
        public var targetSOPClassUID: String
        public var modality: Modality
        /// Emit Conversion Source Attributes + Unassigned Converted Attributes (Sup 157).
        public var legacyConverted: Bool
        /// Group frames into stacks by Image Orientation (Patient).
        public var makeStacks: Bool
        /// Assign Temporal Position Index from Trigger Time / Acquisition Time /
        /// Temporal Position Identifier.
        public var temporalPositions: Bool

        public init(targetSOPClassUID: String, modality: Modality, legacyConverted: Bool,
                    makeStacks: Bool = false, temporalPositions: Bool = false) {
            self.targetSOPClassUID = targetSOPClassUID
            self.modality = modality
            self.legacyConverted = legacyConverted
            self.makeStacks = makeStacks
            self.temporalPositions = temporalPositions
        }
    }

    public struct Output: Sendable {
        public var shared: SequenceItem
        public var perFrame: [SequenceItem]
        public var dimensionOrganizationUID: String
        public var dimensionIndexItems: [SequenceItem]
        public var dimensionOrganizationType: String?
        /// Top-level tags that were moved into a functional group.
        public var liftedTags: Set<Tag>
        /// Per-frame Unassigned Converted Attributes items (Legacy Converted only).
        public var unassignedPerFrame: [SequenceItem]?
        public var stackCount: Int
        public var temporalPositionCount: Int
        public var sharedMacroCount: Int
        public var perFrameMacroCount: Int
        /// Varying top-level attributes that could not be carried (non-legacy targets).
        public var droppedVaryingTags: [Tag]
    }

    // MARK: - Macro table

    /// One functional group macro: the sequence tag and the top-level attributes
    /// it takes (`source` tag in the classic image → `target` tag in the macro).
    struct Macro {
        let sequenceTag: Tag
        let members: [(source: Tag, target: Tag, vr: VR?)]
        let canBeShared: Bool
        /// Restrict to these modalities (nil = every modality).
        let modalities: Set<String>?
    }

    static func macros(for modality: Modality) -> [Macro] {
        var list: [Macro] = [
            Macro(sequenceTag: .pixelMeasuresSequence, members: [
                (.pixelSpacing, .pixelSpacing, nil), (.sliceThickness, .sliceThickness, nil),
                (.spacingBetweenSlices, .spacingBetweenSlices, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .planePositionSequence, members: [
                (.imagePositionPatient, .imagePositionPatient, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .planeOrientationSequence, members: [
                (.imageOrientationPatient, .imageOrientationPatient, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .frameVOILUTSequence, members: [
                (.windowCenter, .windowCenter, nil), (.windowWidth, .windowWidth, nil),
                (.windowCenterWidthExplanation, .windowCenterWidthExplanation, nil),
                (.voiLUTFunction, .voiLUTFunction, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .pixelValueTransformationSequence, members: [
                (.rescaleIntercept, .rescaleIntercept, nil), (.rescaleSlope, .rescaleSlope, nil),
                (.rescaleType, .rescaleType, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .frameAnatomySequence, members: [
                (.anatomicRegionSequence, .anatomicRegionSequence, nil),
                (.imageLaterality, .frameLaterality, .CS)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .derivationImageSequence, members: [
                (.sourceImageSequence, .sourceImageSequence, nil),
                (.derivationDescription, .derivationDescription, nil),
                (.derivationCodeSequence, .derivationCodeSequence, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .referencedImageSequence, members: [
                (.referencedImageSequence, .referencedImageSequence, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .realWorldValueMappingSequence, members: [
                (.realWorldValueMappingSequence, .realWorldValueMappingSequence, nil)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .cardiacSynchronizationSequence, members: [
                (.triggerTime, .nominalCardiacTriggerDelayTime, .FD)], canBeShared: true, modalities: nil),
            Macro(sequenceTag: .irradiationEventIdentificationSequence, members: [
                (.irradiationEventUID, .irradiationEventUID, nil)], canBeShared: true,
                  modalities: ["CT", "PT", "XA", "RF"]),
            Macro(sequenceTag: .mrEchoSequence, members: [
                (.echoTime, .effectiveEchoTime, .FD)], canBeShared: true, modalities: ["MR"]),
            Macro(sequenceTag: .mrTimingAndRelatedParametersSequence, members: [
                (.repetitionTime, .repetitionTime, nil), (.flipAngle, .flipAngle, nil),
                (.echoTrainLength, .echoTrainLength, nil)], canBeShared: true, modalities: ["MR"]),
        ]
        list = list.filter { $0.modalities == nil || $0.modalities!.contains(modality.rawValue) }
        return list
    }

    /// Top-level tags that must never be lifted or reported as "varying": instance
    /// identity, attributes Frame Content already consumes, and the patient /
    /// study / series identity the template supplies for the whole object
    /// (`--validate` is where a study or series mismatch becomes an error).
    static let identityTags: Set<Tag> = [
        .sopInstanceUID, .sopClassUID, .instanceNumber, .pixelData, .numberOfFrames,
        .specificCharacterSet, .imageType, .acquisitionNumber, .acquisitionDate, .acquisitionTime,
        .acquisitionDateTime, .acquisitionDuration, .imageComments, .contentDate, .contentTime,
        .instanceCreationDate, .laterality, .smallestImagePixelValue, .largestImagePixelValue,
        .lossyImageCompression, .lossyImageCompressionRatio, .lossyImageCompressionMethod,
        .temporalPositionIdentifier, .numberOfTemporalPositions, .sliceLocation,
        .extendedOffsetTable, .extendedOffsetTableLengths,
        .studyInstanceUID, .seriesInstanceUID, .frameOfReferenceUID, .seriesNumber, .studyID,
        .seriesDescription, .instanceCreationTime, .instanceCreatorUID,
        Tag(group: 0x0008, element: 0x0050),   // Accession Number
        Tag(group: 0x0008, element: 0x0020), Tag(group: 0x0008, element: 0x0030),   // Study Date, Study Time
        Tag(group: 0x0008, element: 0x0021), Tag(group: 0x0008, element: 0x0031),   // Series Date, Series Time
        Tag(group: 0x0008, element: 0x0013),   // Instance Creation Time
    ]

    /// Groups that describe the patient, not the frame; never per-frame material.
    static let identityGroups: Set<UInt16> = [0x0002, 0x0010, 0x0012]

    // MARK: - Build

    public static func build(frames: [DataSet], options: Options) -> Output {
        let writer = DICOMWriter()
        let modality = options.modality
        let macros = macros(for: modality)

        var lifted = Set<Tag>()
        var sharedElements: [DataElement] = []
        var perFrameElements = Array(repeating: [DataElement](), count: frames.count)
        var sharedMacros = 0, perFrameMacros = 0

        // Generic macros: shared when byte-identical in every frame, else per-frame.
        for macro in macros {
            var perFrameItems: [[DataElement]] = []
            var anyPresent = false
            for frame in frames {
                var elements: [DataElement] = []
                for member in macro.members {
                    guard let element = frame[member.source] else { continue }
                    elements.append(retag(element, to: member.target, vr: member.vr, writer: writer))
                }
                if !elements.isEmpty { anyPresent = true }
                perFrameItems.append(elements)
            }
            guard anyPresent else { continue }
            for member in macro.members { lifted.insert(member.source) }

            let allEqual = perFrameItems.dropFirst().allSatisfy { sameElements($0, perFrameItems[0]) }
            if macro.canBeShared && allEqual {
                sharedElements.append(sequenceElement(macro.sequenceTag, items: [SequenceItem(elements: perFrameItems[0])], writer: writer))
                sharedMacros += 1
            } else {
                for (i, elements) in perFrameItems.enumerated() where !elements.isEmpty {
                    perFrameElements[i].append(sequenceElement(macro.sequenceTag, items: [SequenceItem(elements: elements)], writer: writer))
                }
                perFrameMacros += 1
            }
        }

        // Frame type macro (CT/MR/PET/XA-XRF): per-frame when Image Type varies.
        if let frameTypeTag = frameTypeSequenceTag(for: options.targetSOPClassUID, modality: modality) {
            let items = frames.map { frameTypeItem(from: $0, modality: modality) }
            let allEqual = items.dropFirst().allSatisfy { sameElements($0, items[0]) }
            if allEqual {
                sharedElements.append(sequenceElement(frameTypeTag, items: [SequenceItem(elements: items[0])], writer: writer))
                sharedMacros += 1
            } else {
                for (i, elements) in items.enumerated() {
                    perFrameElements[i].append(sequenceElement(frameTypeTag, items: [SequenceItem(elements: elements)], writer: writer))
                }
                perFrameMacros += 1
            }
        }

        // Stacks / temporal positions / dimension indices.
        let placement = placeFrames(frames, makeStacks: options.makeStacks, temporal: options.temporalPositions)

        // Frame Content: always per-frame.
        for (i, frame) in frames.enumerated() {
            var fc: [DataElement] = []
            if let n = frame.string(for: .acquisitionNumber).flatMap({ UInt16($0.trimmingCharacters(in: .whitespaces)) }) {
                fc.append(DataElement.uint16(tag: .frameAcquisitionNumber, value: n))
            }
            if let dt = acquisitionDateTime(of: frame) {
                fc.append(DataElement.string(tag: .frameAcquisitionDateTime, vr: .DT, value: dt))
                fc.append(DataElement.string(tag: .frameReferenceDateTime, vr: .DT, value: dt))
            }
            if let dur = frame[.acquisitionDuration]?.float64Value {
                fc.append(DataElement.float64(tag: .frameAcquisitionDuration, value: dur))
            }
            if let c = frame[.imageComments] {
                fc.append(DataElement(tag: .frameComments, vr: .LT, length: c.length, valueData: c.valueData, byteOrder: c.byteOrder))
            }
            fc.append(DataElement.string(tag: .stackID, vr: .SH, value: String(placement.stack[i])))
            fc.append(DataElement.uint32(tag: .inStackPositionNumber, value: UInt32(placement.inStack[i])))
            var indexValues: [UInt32] = [UInt32(placement.stack[i]), UInt32(placement.inStack[i])]
            if options.temporalPositions {
                fc.append(DataElement.uint32(tag: .temporalPositionIndex, value: UInt32(placement.temporal[i])))
                indexValues.append(UInt32(placement.temporal[i]))
            }
            fc.append(DataElement.uint32s(tag: .dimensionIndexValues, values: indexValues))
            perFrameElements[i].append(sequenceElement(.frameContentSequence, items: [SequenceItem(elements: fc)], writer: writer))
        }
        perFrameMacros += 1

        // Legacy Converted: per-frame Conversion Source Attributes.
        if options.legacyConverted {
            for (i, frame) in frames.enumerated() {
                var cs: [DataElement] = []
                if let c = frame.string(for: .sopClassUID) {
                    cs.append(DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: MultiframeSOPClassMap.normalize(c)))
                }
                if let u = frame.string(for: .sopInstanceUID) {
                    cs.append(DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: MultiframeSOPClassMap.normalize(u)))
                }
                perFrameElements[i].append(sequenceElement(.conversionSourceAttributesSequence, items: [SequenceItem(elements: cs)], writer: writer))
            }
        }

        // Varying, un-lifted top-level attributes.
        var varying: [Tag] = []
        var allTags = Set<Tag>()
        for frame in frames { allTags.formUnion(frame.tags) }
        for tag in allTags.sorted()
        where !lifted.contains(tag) && !identityTags.contains(tag) && !identityGroups.contains(tag.group) && !tag.isPrivate {
            let first = frames[0][tag]
            let same = frames.dropFirst().allSatisfy { sameElement($0[tag], first) }
            if !same { varying.append(tag) }
        }

        var unassigned: [SequenceItem]? = nil
        var dropped: [Tag] = []
        if options.legacyConverted {
            unassigned = frames.map { frame in
                SequenceItem(elements: varying.compactMap { frame[$0] })
            }
            lifted.formUnion(varying)
        } else {
            dropped = varying
            lifted.formUnion(varying)
        }

        // Dimension module.
        let organizationUID = UIDGenerator.generateUID().value
        var dimensionItems: [SequenceItem] = []
        func dimension(_ pointer: Tag, label: String) -> SequenceItem {
            SequenceItem(elements: [
                DataElement.string(tag: .dimensionOrganizationUID, vr: .UI, value: organizationUID),
                attributeTagElement(.dimensionIndexPointer, value: pointer, writer: writer),
                attributeTagElement(.functionalGroupPointer, value: .frameContentSequence, writer: writer),
                DataElement.string(tag: .dimensionDescriptionLabel, vr: .LO, value: label),
            ])
        }
        dimensionItems.append(dimension(.stackID, label: "Stack ID"))
        dimensionItems.append(dimension(.inStackPositionNumber, label: "In-Stack Position Number"))
        if options.temporalPositions {
            dimensionItems.append(dimension(.temporalPositionIndex, label: "Temporal Position Index"))
        }
        let organizationType: String?
        if options.temporalPositions {
            organizationType = "3D_TEMPORAL"
        } else if placement.stackCount == 1 && placement.regularlySpaced {
            organizationType = "3D"
        } else {
            organizationType = nil
        }

        return Output(
            shared: SequenceItem(elements: sharedElements),
            perFrame: perFrameElements.map { SequenceItem(elements: $0) },
            dimensionOrganizationUID: organizationUID,
            dimensionIndexItems: dimensionItems,
            dimensionOrganizationType: organizationType,
            liftedTags: lifted,
            unassignedPerFrame: unassigned,
            stackCount: placement.stackCount,
            temporalPositionCount: placement.temporalCount,
            sharedMacroCount: sharedMacros,
            perFrameMacroCount: perFrameMacros,
            droppedVaryingTags: dropped
        )
    }

    // MARK: - Frame placement (stacks, positions, temporal index)

    struct Placement {
        var stack: [Int]
        var inStack: [Int]
        var temporal: [Int]
        var stackCount: Int
        var temporalCount: Int
        var regularlySpaced: Bool
    }

    static func placeFrames(_ frames: [DataSet], makeStacks: Bool, temporal: Bool) -> Placement {
        let n = frames.count
        var stack = Array(repeating: 1, count: n)
        var stackCount = 1
        if makeStacks {
            var ids: [String: Int] = [:]
            for (i, frame) in frames.enumerated() {
                let key = orientationKey(frame)
                if let id = ids[key] {
                    stack[i] = id
                } else {
                    let id = ids.count + 1
                    ids[key] = id
                    stack[i] = id
                }
            }
            stackCount = max(1, ids.count)
        }

        var temporalIndex = Array(repeating: 1, count: n)
        var temporalCount = 1
        if temporal {
            let keys = frames.map(temporalKey)
            let unique = Array(Set(keys.map { $0.sortValue })).sorted()
            let rank = Dictionary(uniqueKeysWithValues: unique.enumerated().map { ($1, $0 + 1) })
            for (i, key) in keys.enumerated() { temporalIndex[i] = rank[key.sortValue] ?? 1 }
            temporalCount = max(1, unique.count)
        }

        // In-stack position: rank by position along the normal within (stack, temporal),
        // falling back to input order.
        var inStack = Array(repeating: 1, count: n)
        var groups: [String: [Int]] = [:]
        for i in 0..<n { groups["\(stack[i])/\(temporalIndex[i])", default: []].append(i) }
        var regular = true
        for (_, indices) in groups {
            let positions = indices.map { FunctionalGroupFlattener.frameInfo(in: frames[$0], frameIndex: 0).positionAlongNormal }
            let ordered: [Int]
            if positions.allSatisfy({ $0 != nil }) && indices.count > 1 {
                let pairs = zip(indices, positions).sorted { (($0.1 ?? 0), $0.0) < (($1.1 ?? 0), $1.0) }
                ordered = pairs.map { $0.0 }
                let sortedPositions = pairs.map { $0.1 ?? 0 }
                let deltas = zip(sortedPositions.dropFirst(), sortedPositions).map { $0 - $1 }
                if let first = deltas.first {
                    regular = regular && deltas.allSatisfy { abs($0 - first) <= max(abs(first) * 0.01, 0.001) }
                }
            } else {
                ordered = indices
                if indices.count > 1 && !positions.allSatisfy({ $0 != nil }) { regular = false }
            }
            for (rank, i) in ordered.enumerated() { inStack[i] = rank + 1 }
        }

        return Placement(stack: stack, inStack: inStack, temporal: temporalIndex,
                         stackCount: stackCount, temporalCount: temporalCount, regularlySpaced: regular)
    }

    static func orientationKey(_ frame: DataSet) -> String {
        guard let o = frame[.imageOrientationPatient]?.decimalStringValues?.map({ $0.value }), o.count == 6 else {
            return "none"
        }
        return o.map { String(format: "%.4f", $0) }.joined(separator: "\\")
    }

    struct TemporalKey { let sortValue: Double }

    static func temporalKey(_ frame: DataSet) -> TemporalKey {
        if let t = frame[.triggerTime]?.decimalStringValue?.value { return TemporalKey(sortValue: t) }
        if let id = frame.string(for: .temporalPositionIdentifier).flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            return TemporalKey(sortValue: id)
        }
        if let t = frame.string(for: .acquisitionTime)?.trimmingCharacters(in: .whitespaces),
           let seconds = timeSeconds(t) {
            return TemporalKey(sortValue: seconds)
        }
        return TemporalKey(sortValue: 0)
    }

    static func timeSeconds(_ tm: String) -> Double? {
        let digits = tm.replacingOccurrences(of: ":", with: "")
        guard digits.count >= 2 else { return nil }
        let hh = Double(digits.prefix(2)) ?? 0
        let mm = digits.count >= 4 ? (Double(digits.dropFirst(2).prefix(2)) ?? 0) : 0
        let ss = digits.count > 4 ? (Double(digits.dropFirst(4)) ?? 0) : 0
        return hh * 3600 + mm * 60 + ss
    }

    // MARK: - Frame type macro

    static func frameTypeSequenceTag(for targetSOPClassUID: String, modality: Modality) -> Tag? {
        switch MultiframeSOPClassMap.normalize(targetSOPClassUID) {
        case MultiframeSOPClassMap.UID.enhancedCT, MultiframeSOPClassMap.UID.legacyConvertedEnhancedCT:
            return .ctImageFrameTypeSequence
        case MultiframeSOPClassMap.UID.enhancedMR, MultiframeSOPClassMap.UID.legacyConvertedEnhancedMR:
            return .mrImageFrameTypeSequence
        case MultiframeSOPClassMap.UID.enhancedPET, MultiframeSOPClassMap.UID.legacyConvertedEnhancedPET:
            return .petFrameTypeSequence
        case MultiframeSOPClassMap.UID.enhancedXA, MultiframeSOPClassMap.UID.enhancedXRF:
            return .xaXRFFrameCharacteristicsSequence
        default:
            return nil
        }
    }

    /// Frame Type (4 values, padded from Image Type) plus the Common CT/MR/PET
    /// Image Description attributes the frame-type macros require.
    static func frameTypeItem(from frame: DataSet, modality: Modality) -> [DataElement] {
        var values = (frame.strings(for: .imageType) ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        if values.isEmpty { values = ["ORIGINAL", "PRIMARY"] }
        while values.count < 4 { values.append(values.count == 2 ? "VOLUME" : "NONE") }
        var elements: [DataElement] = [
            DataElement.strings(tag: .frameType, vr: .CS, values: Array(values.prefix(4))),
        ]
        if modality.usesEnhancedFrameTypeDescriptors {
            let samples = frame.uint16(for: .samplesPerPixel) ?? 1
            elements.append(DataElement.string(tag: .pixelPresentation, vr: .CS, value: samples > 1 ? "COLOR" : "MONOCHROME"))
            elements.append(DataElement.string(tag: .volumetricProperties, vr: .CS, value: "VOLUME"))
            elements.append(DataElement.string(tag: .volumeBasedCalculationTechnique, vr: .CS, value: "NONE"))
        }
        if modality == .mr {
            elements.append(DataElement.string(tag: .complexImageComponent, vr: .CS, value: "MAGNITUDE"))
            elements.append(DataElement.string(tag: .acquisitionContrast, vr: .CS, value: "UNKNOWN"))
        }
        return elements
    }

    // MARK: - Helpers

    static func acquisitionDateTime(of frame: DataSet) -> String? {
        if let dt = frame.string(for: .acquisitionDateTime)?.trimmingCharacters(in: .whitespaces), !dt.isEmpty {
            return dt
        }
        guard let date = frame.string(for: .acquisitionDate)?.trimmingCharacters(in: .whitespaces), date.count == 8 else {
            return nil
        }
        let time = frame.string(for: .acquisitionTime)?.trimmingCharacters(in: .whitespaces) ?? ""
        return date + time.replacingOccurrences(of: ":", with: "")
    }

    static func retag(_ element: DataElement, to target: Tag, vr: VR?, writer: DICOMWriter) -> DataElement {
        if target == element.tag && vr == nil { return element }
        let outVR = vr ?? element.vr
        if outVR == element.vr {
            if let items = element.sequenceItems {
                return DataElement(tag: target, vr: .SQ, length: element.length, valueData: element.valueData, sequenceItems: items)
            }
            return DataElement(tag: target, vr: outVR, length: element.length, valueData: element.valueData, byteOrder: element.byteOrder)
        }
        // VR conversion: DS/IS text → FD binary is the only case the macro table needs.
        if outVR == .FD, let value = element.decimalStringValue?.value ?? element.stringValue.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            return DataElement.float64(tag: target, value: value)
        }
        if outVR.isBackslashDelimitedText, let s = element.stringValue {
            return DataElement.string(tag: target, vr: outVR, value: s.trimmingCharacters(in: .whitespaces))
        }
        return DataElement(tag: target, vr: outVR, length: element.length, valueData: element.valueData, byteOrder: element.byteOrder)
    }

    static func sequenceElement(_ tag: Tag, items: [SequenceItem], writer: DICOMWriter) -> DataElement {
        var data = Data()
        for item in items { data.append(writer.serializeSequenceItem(item)) }
        return DataElement(tag: tag, vr: .SQ, length: UInt32(data.count), valueData: data, sequenceItems: items)
    }

    static func attributeTagElement(_ tag: Tag, value: Tag, writer: DICOMWriter) -> DataElement {
        let data = writer.serializeTag(value)
        return DataElement(tag: tag, vr: .AT, length: UInt32(data.count), valueData: data)
    }

    static func sameElement(_ a: DataElement?, _ b: DataElement?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?):
            if x.isSequence || y.isSequence {
                return x.isSequence && y.isSequence && sameItems(x.sequenceItems ?? [], y.sequenceItems ?? [])
            }
            return trimmed(x) == trimmed(y)
        default: return false
        }
    }

    static func sameElements(_ a: [DataElement], _ b: [DataElement]) -> Bool {
        guard a.count == b.count else { return false }
        let bByTag = Dictionary(b.map { ($0.tag, $0) }, uniquingKeysWith: { _, last in last })
        return a.allSatisfy { sameElement($0, bByTag[$0.tag]) }
    }

    static func sameItems(_ a: [SequenceItem], _ b: [SequenceItem]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { sameElements($0.allElements, $1.allElements) }
    }

    /// Value bytes without trailing NUL/space padding so "1.5 " and "1.5" compare equal.
    static func trimmed(_ e: DataElement) -> Data {
        var d = e.valueData
        while let last = d.last, last == 0x00 || last == 0x20 { d.removeLast() }
        return d
    }
}
