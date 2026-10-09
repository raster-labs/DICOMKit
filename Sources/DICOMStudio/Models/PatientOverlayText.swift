// PatientOverlayText.swift
// DICOMStudio
//
// DICOM Studio — the identification text burned over an image.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the 11 tag literals (0010,0010), (0010,0020), (0008,0060), (0008,1030), (0020,000D), (0010,0030), (0008,0050), (0008,0080), (0008,103E), (0008,0020), (0008,0030) are PS3.6 2026a Table 6-1 rows with the names the fields carry (Patient's Name, Patient ID, Modality, Study Description, Study Instance UID, Patient's Birth Date, Accession Number, Institution Name, Series Description, Study Date, Study Time), all 11 match; promoted from CR; checked by Scripts/diff_studio_g2_viewer.py
//
// One definition of what the overlay says, used by the viewer's tiles and by the
// film preview's cells. Two of them would be two answers to "who is this
// patient", and the film would eventually disagree with the screen it was
// composed on.

import Foundation
import DICOMCore
import DICOMKit
import DICOMPrintKit

/// Patient and study identification, as lines of overlay text.
///
/// Held as the pieces rather than as finished lines, because two places set them
/// differently: a viewer pane runs them together into a sentence, and a film cell
/// distributes them around the corners of the picture the way a reading station
/// does. Both come from this one reading of the header.
public struct PatientOverlayText: Sendable, Equatable, Hashable {

    /// "Dr JANE DOE, 711794" — who this is.
    public let patientLine: String

    /// Study Date and Study Time (0008,0020 and 0008,0030), formatted for
    /// reading: "15 Oct 2025 14:32".
    ///
    /// The time as well as the date, because a patient can be scanned twice in a
    /// day — before and after contrast, or before and after an intervention —
    /// and two films that differ only by the hour are two films nobody can put
    /// in order.
    public let studyDate: String

    /// Study Description (0008,1030).
    public let studyDescription: String

    /// "Modality: CT" — what made the picture.
    public let modalityLine: String

    /// "Image: 45" — where the picture sits in the sequence it was acquired in.
    public let positionLine: String

    /// The technique this modality is read by, each value under its own label —
    /// "Slice Thickness: 5.00 mm", "kVp: 120". A number on film with nothing
    /// naming it is a number a reader has to guess at, and the guesses differ by
    /// modality.
    ///
    /// Per *image*, not per study: two cells of the same series differ here,
    /// which is the point — a reader comparing two slices on one sheet is
    /// comparing their technique as much as their anatomy.
    public let techniqueLines: [String]

    /// Study Instance UID (0020,000D), or empty when the file had none.
    ///
    /// Not drawn — it is what tells a film whether its images belong together.
    /// The UID rather than the text: two studies of one patient on the same day
    /// produce identical lines and are still two studies.
    public let studyInstanceUID: String

    /// "DOB: 15 Oct 1962" (0010,0030) — drawn only when asked for (FR-006).
    ///
    /// A birth date burned into pixels survives header de-identification;
    /// that is the point on a clinical film and the hazard on anything shared,
    /// which is why including it is a choice, never a default.
    public let birthDateLine: String

    /// "Acc: A123456" (0008,0050) — drawn only when asked for. Labelled: an
    /// accession number alone reads as any other number.
    public let accessionLine: String

    /// Institution Name (0008,0080), verbatim — drawn only when asked for.
    public let institutionLine: String

    /// Series Description (0008,103E) — drawn only when asked for. Left out
    /// by default deliberately: a film cell is one image and the sheet already
    /// carries the study description (see ``corners``).
    public let seriesDescriptionLine: String

    public init(
        patientLine: String = "",
        studyDate: String = "",
        studyDescription: String = "",
        modalityLine: String = "",
        positionLine: String = "",
        techniqueLines: [String] = [],
        studyInstanceUID: String = "",
        birthDateLine: String = "",
        accessionLine: String = "",
        institutionLine: String = "",
        seriesDescriptionLine: String = ""
    ) {
        self.patientLine = patientLine
        self.studyDate = studyDate
        self.studyDescription = studyDescription
        self.modalityLine = modalityLine
        self.positionLine = positionLine
        self.techniqueLines = techniqueLines.filter { !$0.isEmpty }
        self.studyInstanceUID = studyInstanceUID
        self.birthDateLine = birthDateLine
        self.accessionLine = accessionLine
        self.institutionLine = institutionLine
        self.seriesDescriptionLine = seriesDescriptionLine
    }

    /// The flat form: whole lines, for callers that set the text as a paragraph
    /// rather than around a picture.
    public init(
        primaryLine: String,
        secondaryLine: String,
        technicalLine: String = "",
        studyInstanceUID: String = ""
    ) {
        self.init(patientLine: primaryLine,
                  studyDescription: secondaryLine,
                  modalityLine: technicalLine,
                  studyInstanceUID: studyInstanceUID)
    }

    /// Patient name, ID and study date, comma separated.
    public var primaryLine: String {
        [patientLine, studyDate].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Study description, on its own line.
    public var secondaryLine: String { studyDescription }

    /// Modality, image position and technique, run together on one line.
    public var technicalLine: String {
        ([modalityLine, positionLine] + techniqueLines)
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Whether there is anything to draw.
    public var isEmpty: Bool {
        primaryLine.isEmpty && secondaryLine.isEmpty && technicalLine.isEmpty
    }

    /// The lines to draw, blank ones dropped.
    public var lines: [String] {
        [primaryLine, secondaryLine, technicalLine].filter { !$0.isEmpty }
    }

    /// The same text arranged around the corners of a picture, as a reading
    /// station arranges it: who and what at the top right, what made the picture
    /// at the bottom left, when it was taken at the bottom right.
    ///
    /// The top left is left clear. On a workstation it holds what the *viewport*
    /// is doing — its size, its window — and a printed cell has no viewport; on
    /// film that corner is where the printer's own label lands.
    ///
    /// Who the patient is and what study this is go unlabelled: a name reads as a
    /// name and a date as a date, and "Patient:" in front of one is a word taking
    /// room from the picture. Everything at the bottom left is labelled, because
    /// "5.00 mm" alone could be a thickness, a spacing or a slice interval.
    public var corners: PrintCornerAnnotation {
        corners(including: [])
    }

    /// The corner arrangement with FR-006's optional fields added.
    ///
    /// The optional fields keep to the corners' existing grammar: who the
    /// patient is grows downward from the patient line (birth date), what the
    /// study is grows under its description (series, accession), and where it
    /// was done joins when it was (institution under the date). The default —
    /// no options — is today's film, byte for byte.
    public func corners(including fields: PrintIdentificationFields) -> PrintCornerAnnotation {
        var topRight = [patientLine]
        if fields.contains(.birthDate) { topRight.append(birthDateLine) }
        topRight.append(studyDescription)
        if fields.contains(.seriesDescription) { topRight.append(seriesDescriptionLine) }
        if fields.contains(.accessionNumber) { topRight.append(accessionLine) }

        var bottomRight = [studyDate]
        if fields.contains(.institutionName) { bottomRight.append(institutionLine) }

        return PrintCornerAnnotation(
            topRight: topRight,
            bottomLeft: [modalityLine, positionLine] + techniqueLines,
            bottomRight: bottomRight)
    }

    /// Reads the overlay text from a data set.
    ///
    /// Missing values are dropped rather than shown as blanks, so a
    /// de-identified file does not print a line of stray commas.
    public static func make(from dataSet: DataSet) -> PatientOverlayText {
        let name = Self.string(dataSet, 0x0010, 0x0010).map { DICOMValueParser.formatPersonName($0) }
        let patientID = Self.string(dataSet, 0x0010, 0x0020)
        let modality = Self.string(dataSet, 0x0008, 0x0060)?.uppercased()

        return PatientOverlayText(
            patientLine: [name, patientID].compactMap { $0 }.joined(separator: ", "),
            studyDate: studyDateTime(from: dataSet),
            studyDescription: Self.string(dataSet, 0x0008, 0x1030) ?? "",
            modalityLine: modality.map { "Modality: \($0)" } ?? "",
            positionLine: positionLine(from: dataSet),
            techniqueLines: modalityDetails(from: dataSet, modality: modality),
            studyInstanceUID: Self.string(dataSet, 0x0020, 0x000D) ?? "",
            // FR-006's optional fields, read here and drawn only when asked
            // for. Labelled where a bare value would be ambiguous: a second
            // date on the film needs to say it is a birth date, and an
            // accession number alone reads as any other number.
            birthDateLine: Self.string(dataSet, 0x0010, 0x0030)
                .map { "DOB: \(DICOMValueParser.formatDate($0))" } ?? "",
            accessionLine: Self.string(dataSet, 0x0008, 0x0050)
                .map { "Acc: \($0)" } ?? "",
            institutionLine: Self.string(dataSet, 0x0008, 0x0080) ?? "",
            seriesDescriptionLine: Self.string(dataSet, 0x0008, 0x103E) ?? "")
    }

    // MARK: - When it was taken

    /// "15 Oct 2025 14:32" — Study Date, and Study Time when the study recorded
    /// one. A study with no date at all says nothing rather than showing a bare
    /// time nobody can place.
    static func studyDateTime(from dataSet: DataSet) -> String {
        guard let date = string(dataSet, 0x0008, 0x0020)
            .map({ DICOMValueParser.formatDate($0) }) else { return "" }
        // To the minute. Seconds are recorded by the scanner and read by nobody:
        // what a reader is separating is a morning study from an afternoon one.
        let time = string(dataSet, 0x0008, 0x0030)
            .map { DICOMValueParser.formatTime($0) }
            .map { $0.split(separator: ":").prefix(2).joined(separator: ":") }
        return [date, time].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - What made the picture

    /// "Image: 45" — Instance Number (0020,0013), the sequence the pictures were
    /// acquired in and the number a reader quotes when asking a colleague to
    /// look at the same slice.
    ///
    /// The series number is not printed beside it. A film cell is one image, and
    /// the series is already said by the study description above it — repeating
    /// it under every picture is a line of type spent on something the whole
    /// sheet has in common.
    ///
    /// Whatever the scanner did not record is left out; a film that prints
    /// "kVp:" with no number beside it has said something false about a machine.
    static func positionLine(from dataSet: DataSet) -> String {
        integer(dataSet, .instanceNumber).map { "Image: \($0)" } ?? ""
    }

    /// The technique this modality is actually read by.
    ///
    /// Chosen by modality rather than printed wholesale: a CT reader checks the
    /// slice thickness and a radiographer checks the exposure, and a strip that
    /// carried both for every image would be a strip nobody reads. Anything the
    /// list does not know still gets its slice thickness, which is the one
    /// technical value common to every sectional modality.
    private static func modalityDetails(from dataSet: DataSet, modality: String?) -> [String] {
        // Resolved through the project's one alias table, so a file written with
        // "MRI" or "DR" gets the same technique line as "MR" or "DX" would.
        guard let modality, let resolved = Modality.normalized(modality) else {
            return [thickness(dataSet)].compactMap { $0 }
        }

        switch resolved {
        case .ct:
            return [thickness(dataSet), kilovolts(dataSet), milliampereSeconds(dataSet)]
                .compactMap { $0 }

        case .mr:
            return [thickness(dataSet), echoTiming(dataSet), fieldStrength(dataSet)]
                .compactMap { $0 }

        case .pt, .nm:
            return [thickness(dataSet),
                    string(dataSet, 0x0018, 0x0031).map { "Radiopharmaceutical: \($0)" }]
                .compactMap { $0 }

        default:
            // Every projection X-ray shares one technique line (kVp / mAs / view),
            // which is what the CR/DX/RF/XA/MG/PX/IO list spelled out by hand.
            if resolved.category == .radiography {
                return [kilovolts(dataSet), milliampereSeconds(dataSet), viewPosition(dataSet)]
                    .compactMap { $0 }
            }
            // Display-ready frames carry the scanner's own burned-in scale;
            // nothing here is read off a technique value the way a CT's is.
            if resolved.category == .ultrasound || resolved.category == .visibleLight {
                return []
            }
            return [thickness(dataSet)].compactMap { $0 }
        }
    }

    /// "Slice Thickness: 5.00 mm" (0018,0050).
    private static func thickness(_ dataSet: DataSet) -> String? {
        number(dataSet, .sliceThickness)
            .map { "Slice Thickness: \(ViewerAnnotationText.millimetres($0))" }
    }

    /// "kVp: 120" (0018,0060) — labelled as the attribute is named, which is what
    /// a radiographer checking a technique is looking for.
    private static func kilovolts(_ dataSet: DataSet) -> String? {
        number(dataSet, .kvp).map { "kVp: \(ViewerAnnotationText.trimmed($0))" }
    }

    /// "Exposure: 250 mAs" (0018,1152), or the tube current when the scanner
    /// recorded only that.
    private static func milliampereSeconds(_ dataSet: DataSet) -> String? {
        if let exposure = number(dataSet, .exposure) {
            return "Exposure: \(ViewerAnnotationText.trimmed(exposure)) mAs"
        }
        return number(dataSet, .xRayTubeCurrent)
            .map { "Tube Current: \(ViewerAnnotationText.trimmed($0)) mA" }
    }

    /// "TR: 450 ms / TE: 12 ms" — the pair that says what an MR image is
    /// weighted by, on one line because they are read as a pair.
    private static func echoTiming(_ dataSet: DataSet) -> String? {
        let tr = number(dataSet, .repetitionTime).map { "TR: \(ViewerAnnotationText.trimmed($0)) ms" }
        let te = number(dataSet, .echoTime).map { "TE: \(ViewerAnnotationText.trimmed($0)) ms" }
        let parts = [tr, te].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    /// "Field Strength: 1.5 T" (0018,0087).
    private static func fieldStrength(_ dataSet: DataSet) -> String? {
        guard let value = number(dataSet, .magneticFieldStrength), value > 0 else { return nil }
        return "Field Strength: \(ViewerAnnotationText.trimmed(value)) T"
    }

    /// "View: PA" (0018,5101). On a plain film the view is half of what the
    /// image is.
    private static func viewPosition(_ dataSet: DataSet) -> String? {
        string(dataSet, 0x0018, 0x5101).map { "View: \($0.uppercased())" }
    }

    // MARK: - Reading values

    private static func string(_ dataSet: DataSet, _ group: UInt16, _ element: UInt16) -> String? {
        string(dataSet, Tag(group: group, element: element))
    }

    private static func string(_ dataSet: DataSet, _ tag: Tag) -> String? {
        guard let value = dataSet.string(for: tag)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func number(_ dataSet: DataSet, _ tag: Tag) -> Double? {
        guard let raw = string(dataSet, tag) else { return nil }
        // DS and IS are multi-valued; the first value is the one that describes
        // the frame being drawn.
        let first = raw.split(separator: "\\").first.map(String.init) ?? raw
        return Double(first.trimmingCharacters(in: .whitespaces))
    }

    private static func integer(_ dataSet: DataSet, _ tag: Tag) -> Int? {
        number(dataSet, tag).map { Int($0) }
    }
}

// MARK: - Optional identification fields

/// The FR-006 fields a film's identification can carry beyond the standard
/// set. All off by default — the default film is today's film — and birth
/// date deserves its own thought before switching on: burned into pixels, it
/// survives any later header de-identification.
public struct PrintIdentificationFields: OptionSet, Sendable, Equatable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Patient Birth Date (0010,0030), as "DOB: 15 Oct 1962".
    public static let birthDate = PrintIdentificationFields(rawValue: 1 << 0)
    /// Accession Number (0008,0050), as "Acc: A123456".
    public static let accessionNumber = PrintIdentificationFields(rawValue: 1 << 1)
    /// Institution Name (0008,0080), verbatim.
    public static let institutionName = PrintIdentificationFields(rawValue: 1 << 2)
    /// Series Description (0008,103E), verbatim.
    public static let seriesDescription = PrintIdentificationFields(rawValue: 1 << 3)
}
