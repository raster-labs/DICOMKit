// ViewerNonImageContent.swift
// DICOMStudio
//
// DICOM Studio — what the viewer shows when the instance is not a picture.
//
// Parsed once at load, so the view is a rendering of a value rather than a
// place where files are read. Anything that cannot be parsed still produces a
// summary: a report the viewer cannot fully decode is still worth naming, and
// saying so beats an error about pixel data the object never claimed to have.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the 7 (group,element) rows of generalRows carry PS3.6 2026a Table 6-1 names (Modality, Protocol Name, Series Description, Content Date, Study Date, Series Number, Instance Number): 7 match; EncapsulatedDocumentType names and the content switch are plumbing

import Foundation
import DICOMCore
import DICOMKit

/// Non-pixel content the viewer can display.
public enum ViewerNonImageContent: Sendable {

    /// A structured report, parsed into its content tree.
    case report(DICOMKit.SRDocument)

    /// An encapsulated document — a PDF report, a CDA, an STL.
    case document(DICOMKit.EncapsulatedDocument)

    /// A video clip — endoscopy, ultrasound cine, microscopy. The payload is
    /// the encoded bit stream exactly as it was encapsulated, which is a
    /// playable container in its own right; the viewer hands it to a player
    /// rather than decoding frames itself.
    case video(DICOMKit.ExtractedVideo)

    /// Anything else: a presentation state, a key object selection, or content
    /// whose own parser refused it. Carries a summary rather than nothing.
    case summary(kind: ViewerContentKind, title: String, rows: [Row])

    /// One "label: value" line of a summary.
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { label }
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    /// What kind of content this is.
    public var kind: ViewerContentKind {
        switch self {
        case .report:  return .report
        case .document: return .document
        case .video: return .video
        case .summary(let kind, _, _): return kind
        }
    }

    /// Name of an encapsulated document type, for a heading.
    ///
    /// `EncapsulatedDocumentType` is a wire enum with lowercase raw values, and
    /// "pdf" is not a title.
    public static func name(of type: DICOMKit.EncapsulatedDocumentType) -> String {
        switch type {
        case .pdf:     return "PDF Document"
        case .cda:     return "CDA Document"
        case .stl:     return "STL Model"
        case .obj:     return "OBJ Model"
        case .mtl:     return "MTL Material"
        case .unknown: return "Document"
        }
    }

    /// Heading for the viewer.
    public var title: String {
        switch self {
        case .report(let document):
            return document.documentTitle?.codeMeaning
                ?? document.documentType?.displayName
                ?? "Structured Report"
        case .document(let document):
            return document.documentTitle ?? Self.name(of: document.documentType)
        case .video(let video):
            return "\(video.codec.displayName) Video"
        case .summary(_, let title, _):
            return title
        }
    }
}

// MARK: - Reading it from a file

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public enum ViewerNonImageContentReader {

    /// Reads the non-image content of a data set, or `nil` if it holds pixels.
    ///
    /// Classification comes first and parsing second, deliberately: an SR whose
    /// content tree cannot be parsed is still an SR, and must not fall through
    /// to the pixel path where it would be reported as an undecodable image.
    /// - Parameter transferSyntaxUID: The instance's transfer syntax. A video
    ///   instance carries an image SOP Class, so this is the only thing that
    ///   distinguishes a clip from a picture; passing `nil` classifies by SOP
    ///   Class alone and a video would fall through to the pixel path.
    public static func content(
        of dataSet: DataSet,
        sopClassUID: String?,
        transferSyntaxUID: String? = nil
    ) -> ViewerNonImageContent? {
        let kind = ViewerContentKind.kind(forSOPClassUID: sopClassUID,
                                          transferSyntaxUID: transferSyntaxUID)
        switch kind {
        case .image, .waveform:
            return nil

        case .video:
            // The bit stream is lifted out whole — the same passthrough the
            // `dicom-video` extract path uses, so what the player receives is
            // byte for byte what was encapsulated. A clip whose payload cannot
            // be recovered is still a video instance, and says so rather than
            // falling through to a pixel error about a picture it never was.
            guard let transferSyntaxUID,
                  let syntax = TransferSyntax.from(uid: transferSyntaxUID),
                  let video = try? VideoExtractor.extract(from: dataSet,
                                                          transferSyntax: syntax) else {
                return .summary(kind: kind, title: kind.displayName,
                                rows: generalRows(of: dataSet, sopClassUID: sopClassUID))
            }
            return .video(video)

        case .report, .keyObjectSelection:
            if let document = try? SRDocumentParser().parse(dataSet: dataSet) {
                return .report(document)
            }
            return .summary(kind: kind, title: kind.displayName,
                            rows: generalRows(of: dataSet, sopClassUID: sopClassUID))

        case .document:
            if let document = try? EncapsulatedDocumentParser.parse(from: dataSet) {
                return .document(document)
            }
            return .summary(kind: kind, title: kind.displayName,
                            rows: generalRows(of: dataSet, sopClassUID: sopClassUID))

        case .presentationState, .rawData, .other:
            return .summary(kind: kind, title: kind.displayName,
                            rows: generalRows(of: dataSet, sopClassUID: sopClassUID))
        }
    }

    /// The identification any object carries, for content with no reader.
    private static func generalRows(of dataSet: DataSet, sopClassUID: String?) -> [ViewerNonImageContent.Row] {
        var rows: [ViewerNonImageContent.Row] = []
        func add(_ label: String, _ group: UInt16, _ element: UInt16, format: ((String) -> String)? = nil) {
            guard let value = dataSet.string(for: Tag(group: group, element: element))?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            rows.append(.init(label: label, value: format.map { $0(value) } ?? value))
        }
        add("Modality", 0x0008, 0x0060)
        add("Protocol", 0x0018, 0x1030)
        add("Description", 0x0008, 0x103E)
        add("Content Date", 0x0008, 0x0023, format: DICOMValueParser.formatDate)
        add("Study Date", 0x0008, 0x0020, format: DICOMValueParser.formatDate)
        add("Series Number", 0x0020, 0x0011)
        add("Instance Number", 0x0020, 0x0013)
        if let sopClassUID, !sopClassUID.isEmpty {
            rows.append(.init(label: "SOP Class", value: sopClassUID))
        }
        return rows
    }
}
