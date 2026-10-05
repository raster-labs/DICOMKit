// ViewerAnnotationText.swift
// DICOMStudio
//
// DICOM Studio — the reading annotations drawn in a viewport's corners.
//
// A reading station labels the picture the way a workstation always has: who the
// patient is and what study this is, top right; how the picture is being shown
// (size, window, zoom) top and bottom left; when it was acquired, bottom right;
// and the patient's left/right/head/feet at the four edges.
//
// The text splits in two on purpose. What this type holds is what the *file*
// says — it can be read once per file and cached, because it cannot change while
// the tile shows that image. What the *viewport* says — view size, window, zoom,
// angle, position in the series — is passed in at draw time, because a drag
// changes it many times a second. Mixing the two would re-read a header on every
// mouse delta.
//
// NEMA-verified: 2026a, checked 2026-10-05 — orientation letters: direction cosines read in the PS3.3 2026a C.7.6.2.1.1 patient coordinate system (+x L, +y P, +z head) and lettered with the Patient Orientation abbreviations of C.7.6.1.1.1 (A/P, L/R, H/F — S/I corrected); compressionLine's 5 "Uncompressed" UIDs are the PS3.6 2026a Table A-1 "… VR … Endian" rows (Encapsulated Uncompressed .1.98 added, PS3.5 A.4.11); the 11 tags read are Table 6-1 rows

import Foundation
import DICOMCore
import DICOMKit

/// Which way the patient faces at each edge of the picture — "R" on the left of
/// an axial slice, "S" at the top of a coronal one.
public struct ViewerOrientationLabels: Sendable, Equatable, Hashable {
    public let left: String
    public let right: String
    public let top: String
    public let bottom: String

    public init(left: String, right: String, top: String, bottom: String) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    /// Whether there is anything to draw.
    public var isEmpty: Bool {
        left.isEmpty && right.isEmpty && top.isEmpty && bottom.isEmpty
    }

    /// The labels as they read after the viewport's rotation and flips.
    ///
    /// The letters describe the patient, not the file: once the user rotates a
    /// tile 90°, what was the top edge is on the left, and a label that stayed
    /// put would be telling the reader the wrong side. Rotation is snapped to the
    /// nearest quarter turn — the letters name an edge, and an edge cannot be at
    /// 37°.
    public func transformed(
        rotationDegrees: Double,
        flipHorizontal: Bool,
        flipVertical: Bool
    ) -> ViewerOrientationLabels {
        var result = self

        if flipHorizontal {
            result = ViewerOrientationLabels(
                left: result.right, right: result.left,
                top: result.top, bottom: result.bottom)
        }
        if flipVertical {
            result = ViewerOrientationLabels(
                left: result.left, right: result.right,
                top: result.bottom, bottom: result.top)
        }

        let quarters = Int((rotationDegrees / 90).rounded()).quarterTurns
        for _ in 0..<quarters {
            // A clockwise quarter turn sends the left edge to the top.
            result = ViewerOrientationLabels(
                left: result.bottom, right: result.top,
                top: result.left, bottom: result.right)
        }
        return result
    }

    /// The labels for a set of direction cosines, or `nil` when the file does not
    /// record its orientation.
    ///
    /// The row cosine points along increasing column index — the right edge — and
    /// the column cosine along increasing row index, the bottom edge. The other
    /// two edges are their opposites.
    public static func make(fromImageOrientationPatient raw: String?) -> ViewerOrientationLabels? {
        guard let raw else { return nil }
        let values = raw.split(separator: "\\").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 6 else { return nil }

        let row = Array(values[0..<3])
        let column = Array(values[3..<6])
        guard let right = letters(for: row), let bottom = letters(for: column) else { return nil }

        return ViewerOrientationLabels(
            left: letters(for: row.map { -$0 }) ?? "",
            right: right,
            top: letters(for: column.map { -$0 }) ?? "",
            bottom: bottom)
    }

    /// The anatomical letters for a direction, strongest axis first.
    ///
    /// An oblique direction gets more than one letter ("AL" for a vector mostly
    /// anterior and somewhat left), which is how a reader can tell an oblique
    /// acquisition from an axis-aligned one at a glance. Components too small to
    /// matter are dropped rather than rounded up to a letter the picture does not
    /// really lean towards.
    static func letters(for direction: [Double]) -> String? {
        guard direction.count == 3 else { return nil }
        // Direction cosines are in the patient-based coordinate system of PS3.3
        // C.7.6.2.1.1: +x towards the patient's left, +y towards posterior, +z towards
        // the head. The letters are the Patient Orientation (0020,0020) abbreviations
        // of PS3.3 C.7.6.1.1.1 — A/P, L/R and H (head) / F (foot), not the S/I a
        // workstation might improvise.
        let axes = [
            (value: direction[0], positive: "L", negative: "R"),
            (value: direction[1], positive: "P", negative: "A"),
            (value: direction[2], positive: "H", negative: "F")
        ]
        let ordered = axes.sorted { abs($0.value) > abs($1.value) }
        let text = ordered
            .filter { abs($0.value) >= significantComponent }
            .map { $0.value > 0 ? $0.positive : $0.negative }
            .joined()
        return text.isEmpty ? nil : text
    }

    /// How much a direction has to lean along an axis before that axis is named.
    /// Below this the letter says more about rounding error than about anatomy.
    private static let significantComponent: Double = 0.25
}

private extension Int {
    /// This many quarter turns, normalised to 0…3.
    var quarterTurns: Int { ((self % 4) + 4) % 4 }
}

/// What a viewport's corner annotations say about the file it is showing.
///
/// Every line is empty rather than absent when the file does not record it: the
/// view drops empty lines, so a de-identified or minimal file simply carries
/// fewer of them instead of showing labelled blanks.
public struct ViewerAnnotationText: Sendable, Equatable, Hashable {

    /// "Antony Jagaraj 638145 (66 y)" — who this is.
    public let patientLine: String

    /// Study Description (0008,1030).
    public let studyLine: String

    /// Series Number (0020,0011), as it is referred to aloud.
    public let seriesNumberLine: String

    /// "Image size: 512 x 512".
    public let imageSizeLine: String

    /// "Uncompressed", or the codec the pixels are stored in.
    public let compressionLine: String

    /// "Thickness: 3.00 mm".
    public let geometryLine: String

    /// When the image was acquired.
    public let dateTimeLine: String

    /// Which way the patient faces at each edge.
    public let orientation: ViewerOrientationLabels?

    /// Where the image sits in the patient, for the cursor's millimetre readout.
    public let plane: ViewerImagePlane?

    /// The window the file itself asks for, for a tile the user has not windowed.
    public let fileWindowCenter: Double?
    public let fileWindowWidth: Double?

    /// The image's SOP Instance UID.
    ///
    /// Not drawn anywhere — it is here because this type is already the result
    /// of the one header read a tile's file gets, and the saved-views badge
    /// needs to ask the store "are there presentation states for *this* image".
    /// Reading the header a second time per tile to recover a UID the first
    /// read had in hand would be a decode per tile per redraw.
    public let sopInstanceUID: String?

    public init(
        patientLine: String = "",
        studyLine: String = "",
        seriesNumberLine: String = "",
        imageSizeLine: String = "",
        compressionLine: String = "",
        geometryLine: String = "",
        dateTimeLine: String = "",
        orientation: ViewerOrientationLabels? = nil,
        plane: ViewerImagePlane? = nil,
        fileWindowCenter: Double? = nil,
        fileWindowWidth: Double? = nil,
        sopInstanceUID: String? = nil
    ) {
        self.patientLine = patientLine
        self.studyLine = studyLine
        self.seriesNumberLine = seriesNumberLine
        self.imageSizeLine = imageSizeLine
        self.compressionLine = compressionLine
        self.geometryLine = geometryLine
        self.dateTimeLine = dateTimeLine
        self.orientation = orientation
        self.plane = plane
        self.fileWindowCenter = fileWindowCenter
        self.fileWindowWidth = fileWindowWidth
        self.sopInstanceUID = sopInstanceUID
    }

    /// Whether there is anything to draw.
    public var isEmpty: Bool {
        patientLine.isEmpty && studyLine.isEmpty
            && imageSizeLine.isEmpty && compressionLine.isEmpty
            && geometryLine.isEmpty && dateTimeLine.isEmpty
    }

    // MARK: - Reading a file

    /// Reads the annotations from an open file.
    public static func make(from file: DICOMFile) -> ViewerAnnotationText {
        make(from: file.dataSet, transferSyntaxUID: file.transferSyntaxUID ?? "")
    }

    /// Reads the annotations from a data set and the transfer syntax it was
    /// stored in.
    public static func make(from dataSet: DataSet, transferSyntaxUID: String) -> ViewerAnnotationText {
        func string(_ tag: Tag) -> String? {
            guard let value = dataSet.string(for: tag)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        func number(_ tag: Tag) -> Double? {
            guard let raw = string(tag) else { return nil }
            // DS is multi-valued (two window centres, for instance); the first
            // value is the one a viewport shows.
            let first = raw.split(separator: "\\").first.map(String.init) ?? raw
            return Double(first.trimmingCharacters(in: .whitespaces))
        }

        return ViewerAnnotationText(
            patientLine: patientLine(from: dataSet),
            studyLine: string(Tag(group: 0x0008, element: 0x1030)) ?? "",
            seriesNumberLine: string(.seriesNumber) ?? "",
            imageSizeLine: imageSizeLine(from: dataSet),
            compressionLine: compressionLine(for: transferSyntaxUID),
            geometryLine: geometryLine(thickness: number(.sliceThickness)),
            dateTimeLine: dateTimeLine(from: dataSet),
            orientation: ViewerOrientationLabels.make(
                fromImageOrientationPatient: string(.imageOrientationPatient)),
            plane: ViewerImagePlane.make(from: dataSet),
            fileWindowCenter: number(.windowCenter),
            fileWindowWidth: number(Tag(group: 0x0028, element: 0x1051)),
            sopInstanceUID: string(.sopInstanceUID))
    }

    // MARK: - Lines

    /// "Antony Jagaraj 638145 (66 y)".
    private static func patientLine(from dataSet: DataSet) -> String {
        func string(_ group: UInt16, _ element: UInt16) -> String? {
            guard let value = dataSet.string(for: Tag(group: group, element: element))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        let name = string(0x0010, 0x0010).map { DICOMValueParser.formatPersonName($0) }
        let patientID = string(0x0010, 0x0020)
        // The age is parenthesised so it reads as a qualifier of the person
        // rather than as a third identifier.
        let age = string(0x0010, 0x1010).map { "(\(shortAge($0)))" }
        return [name, patientID, age].compactMap { $0 }.joined(separator: " ")
    }

    /// "066Y" → "66 y" — the compact form a corner has room for.
    static func shortAge(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let unit = trimmed.last, "DWMYdwmy".contains(unit),
              let number = Int(trimmed.dropLast()) else { return trimmed }
        return "\(number) \(unit.lowercased())"
    }

    private static func imageSizeLine(from dataSet: DataSet) -> String {
        guard let columns = dataSet.uint16(for: .columns),
              let rows = dataSet.uint16(for: .rows),
              columns > 0, rows > 0 else { return "" }
        return "Image size: \(columns) x \(rows)"
    }

    /// How the pixels are stored, in the words a reader checks image quality by.
    ///
    /// "Uncompressed" is the reading-room word for the syntaxes whose pixel data
    /// has been through no codec — the native ones, the deflated one (deflate
    /// wraps the data set, not the samples) and Encapsulated Uncompressed
    /// (PS3.5 A.4.11: "encodes a stream of one or more Frames of uncompressed
    /// Pixel Data as Encapsulated Fragments"); anything else is named by its
    /// codec, because whether a picture has been through a lossy codec is part
    /// of reading it.
    static func compressionLine(for transferSyntaxUID: String) -> String {
        guard !transferSyntaxUID.isEmpty else { return "" }
        switch transferSyntaxUID {
        case "1.2.840.10008.1.2",        // Implicit VR Little Endian
             "1.2.840.10008.1.2.1",      // Explicit VR Little Endian
             "1.2.840.10008.1.2.1.98",   // Encapsulated Uncompressed Explicit VR Little Endian
             "1.2.840.10008.1.2.1.99",   // Deflated Explicit VR Little Endian
             "1.2.840.10008.1.2.2":      // Explicit VR Big Endian (Retired)
            return "Uncompressed"
        default:
            return ImageMetadataHelpers.transferSyntaxLabel(for: transferSyntaxUID)
        }
    }

    private static func geometryLine(thickness: Double?) -> String {
        thickness.map { "Thickness: \(millimetres($0))" } ?? ""
    }

    /// When the picture was taken — the acquisition stamp when the scanner wrote
    /// one, otherwise the content or study stamp, in that order of nearness to
    /// the image itself.
    private static func dateTimeLine(from dataSet: DataSet) -> String {
        func string(_ tag: Tag) -> String? {
            guard let value = dataSet.string(for: tag)?.trimmingCharacters(in: .whitespaces),
                  !value.isEmpty else { return nil }
            return value
        }
        let date = string(Tag(group: 0x0008, element: 0x0022))       // Acquisition Date
            ?? string(Tag(group: 0x0008, element: 0x0023))           // Content Date
            ?? string(Tag(group: 0x0008, element: 0x0020))           // Study Date
        let time = string(.acquisitionTime) ?? string(.contentTime)

        let parts = [
            date.map { DICOMValueParser.formatDate($0) },
            time.map { DICOMValueParser.formatTime($0) }
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }

    // MARK: - Numbers

    /// A millimetre value as film has always shown it: two decimals, with units.
    static func millimetres(_ value: Double) -> String {
        String(format: "%.2f mm", value)
    }

    /// A number without a trailing ".0" it does not need.
    static func trimmed(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9
            ? String(Int(value.rounded()))
            : String(format: "%g", value)
    }
}
