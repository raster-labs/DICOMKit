// NEMA-verified: 2026a, checked 2026-09-29 — backslash multiplicity per PS3.5 2026a 6.4 (the LT, ST, UT, UR exception is recorded)
import Foundation
import DICOMCore

/// Resolves the legacy (pre-functional-group) per-frame vector attributes when a
/// multi-frame object is reduced to one frame:
///
/// - Cine module: `FrameIncrementPointer` (0028,0009) names the vectors that vary
///   per frame — typically `FrameTimeVector` (0018,1065). A classic single-frame
///   target gets a scalar `FrameTime`; a same-class target keeps the pointer with
///   each vector sliced to one value.
/// - NM Image module: the (0054,00x0) index vectors are sliced to the frame's value.
///
/// Neither emf2sf nor gdcmtar does this; Weasis does it for display only.
public enum LegacyVectorResolver {

    public enum Mode: Sendable {
        /// Output is a classic single-frame IOD (US Image, SC Image …).
        case classic
        /// Output keeps the multi-frame SOP Class with NumberOfFrames = 1.
        case sameClass
    }

    /// NM Image module vectors, PS3.3 C.8.4.8.
    public static let nuclearMedicineVectors: [Tag] = [
        .energyWindowVector, .detectorVector, .phaseVector, .rotationVector,
        .rrIntervalVector, .timeSlotVector, .sliceVector, .angularViewVector, .timeSliceVector,
    ]

    /// Rewrites `dataSet` (already reduced to `frameIndex`'s attributes) in place.
    public static func resolve(
        _ dataSet: inout DataSet,
        frameIndex: Int,
        kind: MultiframeSOPClassMap.LegacyVectorKind,
        mode: Mode
    ) {
        resolve(&dataSet, frames: frameIndex..<(frameIndex + 1), kind: kind, mode: mode)
    }

    /// Range form: keeps the vector entries of `frames` (a concatenation part or a
    /// multi-frame chunk). A one-frame range under `.classic` collapses Frame Time
    /// Vector to Frame Time.
    public static func resolve(
        _ dataSet: inout DataSet,
        frames: Range<Int>,
        kind: MultiframeSOPClassMap.LegacyVectorKind,
        mode: Mode
    ) {
        switch kind {
        case .none, .cine:
            resolveFrameIncrementPointer(&dataSet, frames: frames, mode: mode)
        case .nuclearMedicine:
            for tag in nuclearMedicineVectors {
                sliceVector(&dataSet, tag: tag, frames: frames)
            }
            resolveFrameIncrementPointer(&dataSet, frames: frames, mode: mode)
        }
    }

    // MARK: - Frame Increment Pointer

    static func resolveFrameIncrementPointer(_ dataSet: inout DataSet, frames: Range<Int>, mode: Mode) {
        guard let pointerElement = dataSet[.frameIncrementPointer] else {
            // No pointer: a bare Frame Time Vector is still worth collapsing.
            if dataSet[.frameTimeVector] != nil {
                collapseFrameTimeVector(&dataSet, frames: frames, mode: mode)
            }
            return
        }

        for tag in attributeTags(of: pointerElement) {
            if tag == .frameTimeVector {
                collapseFrameTimeVector(&dataSet, frames: frames, mode: mode)
            } else if tag == .frameTime {
                continue
            } else if dataSet[tag] != nil {
                sliceVector(&dataSet, tag: tag, frames: frames)
            }
        }

        if mode == .classic {
            dataSet[.frameIncrementPointer] = nil
        }
    }

    /// Frame Time Vector → Frame Time (classic, one frame) or the range's vector.
    static func collapseFrameTimeVector(_ dataSet: inout DataSet, frames: Range<Int>, mode: Mode) {
        guard let vector = dataSet.strings(for: .frameTimeVector), !vector.isEmpty else { return }
        // A vector shorter than the frame range means the source is malformed;
        // drop the attribute rather than stamp another frame's value.
        guard frames.lowerBound < vector.count else {
            dataSet[.frameTimeVector] = nil
            return
        }
        let upper = min(frames.upperBound, vector.count)
        let values = Array(vector[frames.lowerBound..<upper]).map { $0.trimmingCharacters(in: .whitespaces) }
        switch mode {
        case .classic where values.count == 1:
            dataSet.setString(values[0], for: .frameTime, vr: .DS)
            dataSet[.frameTimeVector] = nil
        default:
            dataSet.setStrings(values, for: .frameTimeVector, vr: .DS)
        }
    }

    // MARK: - Vector slicing

    /// Replaces a multi-valued element with the values of `frames`.
    /// String VRs are split on backslash; binary VRs are sliced by element size.
    static func sliceVector(_ dataSet: inout DataSet, tag: Tag, frames: Range<Int>) {
        guard let element = dataSet[tag] else { return }
        let vr = element.vr

        if vr.isBackslashDelimitedText {
            guard let values = element.stringValues, values.count > 1 else { return }
            guard frames.lowerBound < values.count else {
                dataSet[tag] = nil
                return
            }
            let upper = min(frames.upperBound, values.count)
            let kept = Array(values[frames.lowerBound..<upper]).map { $0.trimmingCharacters(in: .whitespaces) }
            dataSet.setStrings(kept, for: tag, vr: vr)
            return
        }

        let width: Int
        switch vr {
        case .US, .SS: width = 2
        case .UL, .SL, .FL, .AT: width = 4
        case .FD: width = 8
        default: return
        }
        let count = element.valueData.count / width
        guard count > 1 else { return }
        guard frames.lowerBound < count else {
            dataSet[tag] = nil
            return
        }
        let lower = frames.lowerBound
        let upper = min(frames.upperBound, count)
        let start = element.valueData.startIndex + lower * width
        let end = element.valueData.startIndex + upper * width
        let slice = Data(element.valueData[start..<end])
        dataSet[tag] = DataElement(tag: tag, vr: vr, length: UInt32(slice.count),
                                   valueData: slice, byteOrder: element.byteOrder)
    }

    /// Decodes the (group, element) pairs of an AT element, honouring its byte order.
    static func attributeTags(of element: DataElement) -> [Tag] {
        let data = element.valueData
        var tags: [Tag] = []
        var i = data.startIndex
        while i + 4 <= data.endIndex {
            let g0 = UInt16(data[i]), g1 = UInt16(data[i + 1])
            let e0 = UInt16(data[i + 2]), e1 = UInt16(data[i + 3])
            let group: UInt16, elem: UInt16
            if element.byteOrder == .bigEndian {
                group = (g0 << 8) | g1
                elem = (e0 << 8) | e1
            } else {
                group = (g1 << 8) | g0
                elem = (e1 << 8) | e0
            }
            tags.append(Tag(group: group, element: elem))
            i += 4
        }
        return tags
    }
}

extension VR {
    /// Whether values of this VR are text separated by backslashes.
    var isBackslashDelimitedText: Bool {
        switch self {
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT:
            return true
        default:
            return false
        }
    }
}
