// ViewerContentKind.swift
// DICOMStudio
//
// DICOM Studio — what kind of thing an instance is, from the viewer's point of view.
//
// A study is not only pictures. Reports, encapsulated documents, key object
// selections and presentation states all sit in the same study and the same
// series pane, and until the viewer can name them it treats each one as a
// picture it failed to decode — which is how a perfectly valid SR ends up
// reported as an "unsupported transfer syntax".
//
// NEMA-verified: 2026a, checked 2026-10-05 — the 5 `…Prefix` constants are PS3.6 2026a Table A-1 OID arcs under 1.2.840.10008.5.1.4.1.1 (88. SR, 104. Encapsulated, 11. Presentation State, 9.100. Waveform Presentation State, 9. Waveform), each ending in "." and used with hasPrefix — 64 member SOP Classes fit their kind, 0 wrong; the two exact UIDs (.88.59 Key Object Selection Document Storage, .66 Raw Data Storage) match A-1; the open arcs "…1.1.9"/"…1.1.11" also matched Content Assessment Results / Microscopy Bulk Simple Annotations / Standalone Curve / VOI LUT and were closed

import Foundation
import DICOMCore
import DICOMKit

/// The kind of content an instance holds.
public enum ViewerContentKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case image
    case video
    case waveform
    case report
    case keyObjectSelection
    case document
    case presentationState
    case rawData
    case other

    /// Classifies an instance by its SOP Class UID (0008,0016).
    ///
    /// Prefix matching rather than an exhaustive table: the storage classes are
    /// organised by family, and a new member of a family — another SR flavour,
    /// another encapsulated document type — should land in the right branch
    /// without this list having to be revised first.
    /// Classifies an instance by transfer syntax first, then SOP Class.
    ///
    /// A video instance carries an *image* SOP Class — Video Endoscopic Image
    /// Storage and its siblings are image storage classes — so the SOP Class
    /// alone cannot tell a clip from a picture. The transfer syntax is what
    /// says the pixels are an encoded bit stream rather than frames the pixel
    /// path can decode, so it is asked first.
    public static func kind(forSOPClassUID uid: String?,
                            transferSyntaxUID: String?) -> ViewerContentKind {
        if let transferSyntaxUID,
           TransferSyntax.from(uid: transferSyntaxUID)?.isVideo == true {
            return .video
        }
        return kind(forSOPClassUID: uid)
    }

    public static func kind(forSOPClassUID uid: String?) -> ViewerContentKind {
        guard let uid, !uid.isEmpty else { return .image }
        switch uid {
        case Self.keyObjectSelectionUID:
            return .keyObjectSelection
        case Self.rawDataUID:
            return .rawData
        default:
            break
        }
        if uid.hasPrefix(Self.structuredReportPrefix)           { return .report }
        if uid.hasPrefix(Self.encapsulatedPrefix)               { return .document }
        if uid.hasPrefix(Self.presentationStatePrefix)          { return .presentationState }
        if uid.hasPrefix(Self.waveformPresentationStatePrefix)  { return .presentationState }
        if uid.hasPrefix(Self.waveformPrefix)                   { return .waveform }
        return .image
    }

    /// Whether this kind is displayed as pixels.
    public var isImage: Bool { self == .image }

    /// Whether one object of this kind is a *recording* the reader steps
    /// between — pictures and clips, as against a report or a presentation
    /// state, which have no per-object frames to preview.
    ///
    /// Distinct from ``isImage`` because a video is not rendered through the
    /// pixel path yet is still a series of separate acquisitions: an
    /// endoscopy series holding three clips hides two of them behind a single
    /// card unless the pane can preview each object. Anything that answers
    /// yes here must be safe to describe by object and frame count; it need
    /// not be safe to hand to the still-image decoder.
    public var hasPerObjectFrames: Bool { self == .image || self == .video }

    /// Why this content cannot be displayed, when it cannot be.
    ///
    /// Raw Data Storage holds a vendor's own acquisition data — k-space,
    /// projections, calibration — in a private format with no image and no
    /// standard way to render one. Saying so plainly is the only honest thing
    /// the viewer can do with it.
    public var cannotDisplayReason: String? {
        switch self {
        case .rawData:
            return "Raw Data objects hold vendor-private acquisition data, "
                + "not an image, and cannot be displayed in the viewer."
        default:
            return nil
        }
    }

    /// Name for the series pane and the viewer's placeholder.
    public var displayName: String {
        switch self {
        case .image:              return "Images"
        case .video:              return "Video"
        case .waveform:           return "Waveform"
        case .report:             return "Structured Report"
        case .keyObjectSelection: return "Key Object Selection"
        case .document:           return "Document"
        case .presentationState:  return "Presentation State"
        case .rawData:            return "Raw Data"
        case .other:              return "Other"
        }
    }

    /// SF Symbol standing in for the content where no picture can be drawn.
    public var symbolName: String {
        switch self {
        case .image:              return "photo"
        case .video:              return "film"
        case .waveform:           return "waveform.path.ecg"
        case .report:             return "doc.text"
        case .keyObjectSelection: return "star.square"
        case .document:           return "doc.richtext"
        case .presentationState:  return "slider.horizontal.below.rectangle"
        case .rawData:            return "exclamationmark.octagon"
        case .other:              return "doc"
        }
    }

    // Storage class families — OID arcs of PS3.6 2026a Table A-1, not UIDs themselves,
    // so each ends in "." and `hasPrefix` matches OID children only: "…1.1.9" alone
    // would also claim Content Assessment Results Storage (…1.1.90.1) and Microscopy
    // Bulk Simple Annotations Storage (…1.1.91.1). The members are listed in PS3.4
    // Table B.5-1 (Standard SOP Classes).
    /// The SR Storage arc: Basic Text SR (…88.11) … Waveform Annotation SR (…88.77),
    /// including Key Object Selection Document (…88.59), handled first.
    static let structuredReportPrefix = "1.2.840.10008.5.1.4.1.1.88."
    static let keyObjectSelectionUID = "1.2.840.10008.5.1.4.1.1.88.59"
    /// Encapsulated PDF, CDA, STL, OBJ and MTL Storage (…104.1 – …104.5).
    static let encapsulatedPrefix = "1.2.840.10008.5.1.4.1.1.104."
    /// The softcopy and volumetric Presentation State Storage arc (…11.1 – …11.12).
    static let presentationStatePrefix = "1.2.840.10008.5.1.4.1.1.11."
    /// Raw Data Storage — vendor-private acquisition data with no image in it.
    static let rawDataUID = "1.2.840.10008.5.1.4.1.1.66"
    /// Waveform Presentation State and Waveform Acquisition Presentation State
    /// Storage (…9.100.1, …9.100.2) sit under the waveform arc but are presentation
    /// states (PS3.3 A.92), so they are asked about before the waveform arc.
    static let waveformPresentationStatePrefix = "1.2.840.10008.5.1.4.1.1.9.100."
    /// The Waveform Storage arc: 12-lead ECG (…9.1.1) … Body Position (…9.8.1).
    static let waveformPrefix = "1.2.840.10008.5.1.4.1.1.9."
}
