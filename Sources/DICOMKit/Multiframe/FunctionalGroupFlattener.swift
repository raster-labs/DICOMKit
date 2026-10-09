// NEMA-verified: 2026a, checked 2026-09-29 — functional-group flattening per PS3.3 2026a C.7.6.16; the Magnetization Transfer and Partial Fourier literals are recorded
import Foundation
import DICOMCore

/// What to do with private (vendor) functional groups when flattening.
public enum PrivateFunctionalGroupPolicy: String, Sendable, CaseIterable {
    /// Promote the first item's attributes to the top level like public groups.
    case flatten
    /// Copy the private sequence to the top level unchanged.
    case keep
    /// Discard private functional groups.
    case drop
}

/// Demultiplexes the Multi-frame Functional Groups module into a single-frame
/// data set: the Shared item is applied first, then the frame's Per-frame item
/// (per-frame wins), each macro sequence's first item being promoted to the top
/// level. This is the generic rule dcm4che (`MultiframeExtractor`) and fo-dicom
/// (`FunctionalGroupValues`) use; the typed clean-up pass on top (Frame Type →
/// Image Type, Effective Echo Time → Echo Time, MR sequence derivations, …) is
/// what emf2sf's `EnhancedMRImageExtractor` and Weasis's macro whitelist add.
///
/// Shared by `FrameSplitter` and the viewer's per-frame model so display and
/// split agree on every attribute.
public enum FunctionalGroupFlattener {

    // MARK: - Frame bookkeeping

    /// The ordering/identity attributes of one frame, read from its functional groups.
    public struct FrameInfo: Sendable, Equatable {
        public var stackID: String?
        public var inStackPositionNumber: UInt32?
        public var temporalPositionIndex: UInt32?
        public var dimensionIndexValues: [UInt32]?
        public var imagePositionPatient: [Double]?
        public var imageOrientationPatient: [Double]?

        public init() {}

        /// Distance of the frame's position along the slice normal (nil without
        /// both a position and an orientation).
        public var positionAlongNormal: Double? {
            guard let p = imagePositionPatient, p.count == 3,
                  let o = imageOrientationPatient, o.count == 6 else { return nil }
            let n = [o[1] * o[5] - o[2] * o[4],
                     o[2] * o[3] - o[0] * o[5],
                     o[0] * o[4] - o[1] * o[3]]
            return p[0] * n[0] + p[1] * n[1] + p[2] * n[2]
        }
    }

    /// Reads the frame's stack/position bookkeeping (Shared then Per-frame).
    public static func frameInfo(in dataSet: DataSet, frameIndex: Int) -> FrameInfo {
        var info = FrameInfo()
        let items = [sharedItem(of: dataSet), perFrameItem(of: dataSet, frameIndex: frameIndex)].compactMap { $0 }
        for item in items {
            if let fc = item[.frameContentSequence]?.sequenceItems?.first {
                if let s = fc.string(for: .stackID) { info.stackID = s.trimmingCharacters(in: .whitespaces) }
                if let n = fc[.inStackPositionNumber]?.uint32Value { info.inStackPositionNumber = n }
                if let t = fc[.temporalPositionIndex]?.uint32Value { info.temporalPositionIndex = t }
                if let d = fc[.dimensionIndexValues]?.uint32Values, !d.isEmpty { info.dimensionIndexValues = d }
            }
            if let pp = item[.planePositionSequence]?.sequenceItems?.first,
               let p = pp[.imagePositionPatient]?.decimalStringValues?.map({ $0.value }) {
                info.imagePositionPatient = p
            }
            if let po = item[.planeOrientationSequence]?.sequenceItems?.first,
               let o = po[.imageOrientationPatient]?.decimalStringValues?.map({ $0.value }) {
                info.imageOrientationPatient = o
            }
            // Volume-based IODs (Enhanced US Volume, Breast Tomo, X-Ray 3D, OPT): the
            // (Volume) macros position frames in the volume frame of reference.
            if info.imagePositionPatient == nil,
               let pv = item[.planePositionVolumeSequence]?.sequenceItems?.first,
               let p = pv[.imagePositionVolume]?.float64Values, p.count == 3 {
                info.imagePositionPatient = p
            }
            if info.imageOrientationPatient == nil,
               let ov = item[.planeOrientationVolumeSequence]?.sequenceItems?.first,
               let o = ov[.imageOrientationVolume]?.float64Values, o.count == 6 {
                info.imageOrientationPatient = o
            }
        }
        if info.imagePositionPatient == nil,
           let p = dataSet[.imagePositionPatient]?.decimalStringValues?.map({ $0.value }) {
            info.imagePositionPatient = p
        }
        if info.imageOrientationPatient == nil,
           let o = dataSet[.imageOrientationPatient]?.decimalStringValues?.map({ $0.value }) {
            info.imageOrientationPatient = o
        }
        return info
    }

    public static func sharedItem(of dataSet: DataSet) -> SequenceItem? {
        dataSet[.sharedFunctionalGroupsSequence]?.sequenceItems?.first
    }

    public static func perFrameItem(of dataSet: DataSet, frameIndex: Int) -> SequenceItem? {
        guard let items = dataSet[.perFrameFunctionalGroupsSequence]?.sequenceItems,
              frameIndex >= 0, frameIndex < items.count else { return nil }
        return items[frameIndex]
    }

    // MARK: - Exclusion sets

    /// Multi-frame-only attributes that never belong in a single-frame instance.
    public static let multiframeOnlyTags: Set<Tag> = [
        .sharedFunctionalGroupsSequence, .perFrameFunctionalGroupsSequence,
        .numberOfFrames, .pixelData,
        .dimensionOrganizationSequence, .dimensionIndexSequence, .dimensionOrganizationType,
        .referencedImageEvidenceSequence, .sourceImageEvidenceSequence,
        .concatenationUID, .inConcatenationNumber, .inConcatenationTotalNumber,
        .concatenationFrameOffsetNumber, .sopInstanceUIDOfConcatenationSource,
        .extendedOffsetTable, .extendedOffsetTableLengths,
    ]

    /// Functional groups whose sequence *is* the attribute in the classic IOD and
    /// must therefore be copied as a sequence rather than have its item promoted.
    public static let sequenceValuedGroups: Set<Tag> = [
        .referencedImageSequence, .realWorldValueMappingSequence,
    ]

    /// Attributes that only make sense inside Frame Content / Enhanced frame-type
    /// macros; dropped when converting to a classic IOD.
    static let enhancedOnlyTags: Set<Tag> = [
        .stackID, .inStackPositionNumber, .dimensionIndexValues, .temporalPositionIndex,
        .frameType, .frameLaterality, .frameAcquisitionNumber, .frameAcquisitionDateTime,
        .frameAcquisitionDuration, .frameComments, .frameReferenceDateTime,
        .pixelPresentation, .volumetricProperties, .volumeBasedCalculationTechnique,
        .complexImageComponent, .acquisitionContrast, .nominalCardiacTriggerDelayTime,
        .effectiveEchoTime,
    ]

    // MARK: - Flatten

    /// Produces the data set of frame `frameIndex` with every functional group
    /// promoted to the top level. `NumberOfFrames`, pixel data and identity UIDs
    /// are left to the caller.
    ///
    /// - Parameters:
    ///   - toClassic: `true` when the result becomes a classic single-frame IOD
    ///     (typed clean-up applied and Enhanced-only attributes dropped); `false`
    ///     keeps every promoted attribute (same-class targets).
    public static func flatten(
        _ source: DataSet,
        frameIndex: Int,
        toClassic: Bool,
        privatePolicy: PrivateFunctionalGroupPolicy = .flatten
    ) -> DataSet {
        var result = DataSet()
        for element in source.allElements where !multiframeOnlyTags.contains(element.tag) {
            result[element.tag] = element
        }

        if let shared = sharedItem(of: source) {
            apply(shared, to: &result, privatePolicy: privatePolicy)
        }
        if let perFrame = perFrameItem(of: source, frameIndex: frameIndex) {
            apply(perFrame, to: &result, privatePolicy: privatePolicy)
        }

        typedCleanup(&result, toClassic: toClassic, modality: source.string(for: .modality))
        return result
    }

    /// Keeps the Multi-frame Functional Groups module but trims the Per-frame
    /// sequence to the one item of `frameIndex` (same-class Enhanced targets).
    public static func reduceToSingleFrame(_ source: DataSet, frameIndex: Int) -> DataSet {
        var result = source
        if let item = perFrameItem(of: source, frameIndex: frameIndex) {
            result.setSequence([item], for: .perFrameFunctionalGroupsSequence)
        }
        for tag in [Tag.concatenationUID, .inConcatenationNumber, .inConcatenationTotalNumber,
                    .concatenationFrameOffsetNumber, .sopInstanceUIDOfConcatenationSource,
                    .extendedOffsetTable, .extendedOffsetTableLengths] {
            result[tag] = nil
        }
        return result
    }

    // MARK: - Generic promotion

    static func apply(_ item: SequenceItem, to result: inout DataSet, privatePolicy: PrivateFunctionalGroupPolicy) {
        for element in item.allElements {
            if element.tag.isPrivate {
                switch privatePolicy {
                case .drop: continue
                case .keep: result[element.tag] = element; continue
                case .flatten: break
                }
            }
            guard element.isSequence else {
                result[element.tag] = element
                continue
            }
            if sequenceValuedGroups.contains(element.tag) {
                result[element.tag] = element
                continue
            }
            guard let first = element.sequenceItems?.first else { continue }
            for inner in first.allElements {
                result[inner.tag] = inner
            }
        }
    }

    // MARK: - Typed clean-up

    static func typedCleanup(_ ds: inout DataSet, toClassic: Bool, modality: String?) {
        // Frame Type → Image Type (emf2sf), keeping the frame type only for same-class targets.
        if let frameType = ds[.frameType] {
            ds[.imageType] = DataElement(tag: .imageType, vr: .CS, length: frameType.length,
                                         valueData: frameType.valueData, byteOrder: frameType.byteOrder)
        }
        guard toClassic else { return }

        if let lat = ds.string(for: .frameLaterality), ds[.imageLaterality] == nil {
            ds.setString(lat.trimmingCharacters(in: .whitespaces), for: .imageLaterality, vr: .CS)
        }
        if let n = ds[.frameAcquisitionNumber]?.uint32Value, ds[.acquisitionNumber] == nil {
            ds.setString(String(n), for: .acquisitionNumber, vr: .IS)
        }
        if let dt = ds.string(for: .frameAcquisitionDateTime)?.trimmingCharacters(in: .whitespaces), !dt.isEmpty {
            if ds[.acquisitionDateTime] == nil { ds.setString(dt, for: .acquisitionDateTime, vr: .DT) }
            if ds[.acquisitionDate] == nil, dt.count >= 8 {
                ds.setString(String(dt.prefix(8)), for: .acquisitionDate, vr: .DA)
            }
            if ds[.acquisitionTime] == nil, dt.count > 8 {
                let time = String(dt.dropFirst(8)).split(whereSeparator: { $0 == "+" || $0 == "-" }).first.map(String.init) ?? ""
                if !time.isEmpty { ds.setString(time, for: .acquisitionTime, vr: .TM) }
            }
        }
        if let dur = ds[.frameAcquisitionDuration]?.float64Value, ds[.acquisitionDuration] == nil {
            ds[.acquisitionDuration] = DataElement.float64(tag: .acquisitionDuration, value: dur)
        }
        if let c = ds[.frameComments], ds[.imageComments] == nil {
            ds[.imageComments] = DataElement(tag: .imageComments, vr: .LT, length: c.length,
                                             valueData: c.valueData, byteOrder: c.byteOrder)
        }
        if let trigger = ds[.nominalCardiacTriggerDelayTime]?.float64Value, ds[.triggerTime] == nil {
            ds.setString(DataSet.defaultDecimalString(trigger), for: .triggerTime, vr: .DS)
        }
        if let t = ds[.temporalPositionIndex]?.uint32Value, ds[.temporalPositionIdentifier] == nil {
            ds.setString(String(t), for: .temporalPositionIdentifier, vr: .IS)
        }

        if modality?.trimmingCharacters(in: .whitespaces) == "MR" {
            mrCleanup(&ds)
        }

        for tag in enhancedOnlyTags {
            ds[tag] = nil
        }
    }

    // MARK: - MR derivations (dcm4che EnhancedMRImageExtractor)

    private static let echoPulseSequence = Tag(group: 0x0018, element: 0x9008)
    private static let inversionRecovery = Tag(group: 0x0018, element: 0x9009)
    private static let echoPlanarPulseSequence = Tag(group: 0x0018, element: 0x9018)
    private static let segmentedKSpaceTraversal = Tag(group: 0x0018, element: 0x9033)
    private static let magnetizationTransfer = Tag(group: 0x0018, element: 0x9020)
    private static let steadyStatePulseSequence = Tag(group: 0x0018, element: 0x9017)
    private static let spoiling = Tag(group: 0x0018, element: 0x9016)
    private static let oversamplingPhase = Tag(group: 0x0018, element: 0x9029)
    private static let partialFourier = Tag(group: 0x0018, element: 0x9081)
    private static let flowCompensation = Tag(group: 0x0018, element: 0x9010)

    static func mrCleanup(_ ds: inout DataSet) {
        if let et = ds[.effectiveEchoTime]?.float64Value, ds[.echoTime] == nil, et != 0 {
            ds.setString(DataSet.defaultDecimalString(et), for: .echoTime, vr: .DS)
        }

        func cs(_ tag: Tag) -> String { ds.string(for: tag)?.trimmingCharacters(in: .whitespaces) ?? "" }

        if ds[.scanningSequence] == nil {
            var values: [String] = []
            switch cs(echoPulseSequence) {
            case "SPIN": values.append("SE")
            case "GRADIENT": values.append("GR")
            case "BOTH": values.append(contentsOf: ["SE", "GR"])
            default: break
            }
            if cs(inversionRecovery) == "YES" { values.append("IR") }
            if cs(echoPlanarPulseSequence) == "YES" { values.append("EP") }
            if values.isEmpty { values = ["RM"] }
            ds.setStrings(values, for: .scanningSequence, vr: .CS)
        }
        if ds[.sequenceVariant] == nil {
            var values: [String] = []
            let traversal = cs(segmentedKSpaceTraversal)
            if !traversal.isEmpty && traversal != "SINGLE" { values.append("SK") }
            if cs(magnetizationTransfer) == "ON" { values.append("MTC") }
            let steady = cs(steadyStatePulseSequence)
            if !steady.isEmpty && steady != "NONE" { values.append(steady == "TIME_REVERSED" ? "TRSS" : "SS") }
            let sp = cs(spoiling)
            if !sp.isEmpty && sp != "NONE" { values.append("SP") }
            let osp = cs(oversamplingPhase)
            if !osp.isEmpty && osp != "NONE" { values.append("OSP") }
            if values.isEmpty { values = ["NONE"] }
            ds.setStrings(values, for: .sequenceVariant, vr: .CS)
        }
        if ds[.scanOptions] == nil {
            var values: [String] = []
            let pf = cs(partialFourier)
            if !pf.isEmpty && pf != "NONE" { values.append("PFF") }
            if cs(flowCompensation) != "" && cs(flowCompensation) != "NONE" { values.append("FC") }
            if let imageType = ds.strings(for: .imageType), imageType.count > 2 {
                let flavor = imageType[2].trimmingCharacters(in: .whitespaces)
                if flavor.hasPrefix("CARD") { values.append("CG") }
                if flavor.hasSuffix("RESP_GATED") { values.append("RG") }
                if flavor == "ANGIO", ds[.angioFlag] == nil { ds.setString("Y", for: .angioFlag, vr: .CS) }
            }
            ds.setStrings(values, for: .scanOptions, vr: .CS)
        }
    }
}
