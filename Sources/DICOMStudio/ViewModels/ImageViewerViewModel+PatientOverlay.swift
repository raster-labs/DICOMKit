// ImageViewerViewModel+PatientOverlay.swift
// DICOMStudio
//
// DICOM Studio — the patient identification overlay burned over the image.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the 8 tag literals (0010,0010) Patient's Name, (0010,0020) Patient ID, (0008,1030) Study Description, (0008,0060) Modality, (0008,0020) Study Date, (0018,1030) Protocol Name, (0040,0254) Performed Procedure Step Description, (0032,1060) Requested Procedure Description are PS3.6 2026a Table 6-1 rows with those names, all 8 match; Protocol Name is Type 3 in the General Series Module (PS3.3 C.7.3.1) as the fallback comment says; checked by Scripts/diff_studio_g2_viewer.py
//
// Reading rooms identify film by the patient, not by the file: name, ID and the
// study it belongs to. These four values are study-level, so every tile of a
// hung study shows the same text — the overlay is read from the file the viewer
// currently has open rather than by opening each tile's file, which would stall
// the grid for values that cannot differ within a study.

import Foundation
import DICOMKit
import DICOMCore

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension ImageViewerViewModel {

    /// Patient Name (0010,0010), formatted for display.
    public var patientNameForOverlay: String? {
        overlayString(Tag(group: 0x0010, element: 0x0010))
            .map { DICOMValueParser.formatPersonName($0) }
    }

    /// Patient ID (0010,0020).
    public var patientIDForOverlay: String? {
        overlayString(Tag(group: 0x0010, element: 0x0020))
    }

    /// Study Description (0008,1030).
    public var studyDescriptionForOverlay: String? {
        overlayString(Tag(group: 0x0008, element: 0x1030))
    }

    /// Study Description with the punctuation a reading room does not want to
    /// read stripped out.
    ///
    /// Descriptions arrive carrying the separators of whatever system wrote
    /// them — carets, pipes, backslashes, underscores, stray brackets — which
    /// carry no meaning once the value is on its own line. Letters, digits,
    /// spaces and the three marks that do read as words (`-`, `.`, `/`) are
    /// kept; everything else becomes a space and runs of spaces collapse.
    public var studyDescriptionSanitizedForOverlay: String? {
        guard let raw = studyDescriptionForOverlay else { return nil }
        let cleaned = String(raw.map { character in
            character.isLetter || character.isNumber || character == " "
                || character == "-" || character == "." || character == "/"
                ? character : " "
        })
        let collapsed = cleaned.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Every modality in the open study, in series order, without repeats.
    ///
    /// A study is routinely more than one modality (PET/CT, a CT with an SR),
    /// and which ones are in it is part of "what am I looking at". Falls back to
    /// the open file's Modality (0008,0060) when the series pane has not been
    /// populated — a single file opened on its own still has one.
    public var modalitiesForOverlay: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for entry in studySeries {
            let modality = entry.modality.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modality.isEmpty, seen.insert(modality).inserted else { continue }
            ordered.append(modality)
        }
        if ordered.isEmpty, let modality = overlayString(Tag(group: 0x0008, element: 0x0060)) {
            ordered.append(modality)
        }
        return ordered
    }

    /// The study's modalities as one label — "CT", or "PT / CT".
    public var modalityLineForOverlay: String? {
        let modalities = modalitiesForOverlay
        return modalities.isEmpty ? nil : modalities.joined(separator: " / ")
    }

    /// "Patient name, ID · CT / PT" — who this is and what made the pictures.
    ///
    /// The modality rides with the identification rather than with the study
    /// description because it is checked in the same glance as the name.
    public var patientIdentityLine: String {
        [patientNameLine.isEmpty ? nil : patientNameLine, modalityLineForOverlay]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Study Date (0008,0020), formatted as a readable date.
    public var studyDateForOverlay: String? {
        overlayString(Tag(group: 0x0008, element: 0x0020))
            .map { DICOMValueParser.formatDate($0) }
    }

    /// The overlay text of the file the viewer has open.
    ///
    /// Built by the shared ``PatientOverlayText`` so a tile showing another
    /// file — read through ``PatientOverlayTextCache`` — says the same kind of
    /// thing in the same order.
    public var patientOverlayText: PatientOverlayText {
        guard let dataSet = dicomFile?.dataSet else {
            return PatientOverlayText(primaryLine: "", secondaryLine: "")
        }
        return PatientOverlayText.make(from: dataSet)
    }

    /// The overlay's first line: patient name, ID and study date, comma separated.
    public var patientOverlayPrimaryLine: String { patientOverlayText.primaryLine }

    /// The overlay's second line: the study description, on its own.
    public var patientOverlaySecondaryLine: String { patientOverlayText.secondaryLine }

    /// Whether there is anything to draw.
    public var hasPatientOverlayText: Bool { !patientOverlayText.isEmpty }

    /// "Patient name, ID" — the identification line, without the date.
    ///
    /// Split out from the bottom band's first line because the pane sets it in
    /// large type and the date belongs with the study, not the person.
    public var patientNameLine: String {
        [patientNameForOverlay, patientIDForOverlay].compactMap { $0 }.joined(separator: ", ")
    }

    /// "Study date · study description" — what exam this is.
    public var studyLine: String {
        [studyDateForOverlay, studyDescriptionForOverlay]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The acquisition protocol the images were made with, which is what a
    /// reader checks a series against.
    ///
    /// Protocol Name (0018,1030) is the value that means this, but it is Type 3
    /// and a great many scanners never fill it. The performed and requested
    /// procedure descriptions carry the same thing when it is missing — they are
    /// the ordered/performed protocol rather than the acquisition one, which is
    /// the distinction a reader can live with; a blank line is not.
    public var protocolNameForOverlay: String? {
        overlayString(Tag(group: 0x0018, element: 0x1030))                  // Protocol Name
            ?? overlayString(Tag(group: 0x0040, element: 0x0254))           // Performed Procedure Step Description
            ?? overlayString(Tag(group: 0x0032, element: 0x1060))           // Requested Procedure Description
    }

    /// The protocol as the pane shows it, labelled.
    ///
    /// Always says something once a file is open: an unlabelled bare string was
    /// unrecognisable as the protocol, and silence when the tag is absent reads
    /// as "the viewer doesn't show this" rather than "the scanner didn't record
    /// it". Nil only when there is no file to speak about.
    public var protocolLineForOverlay: String? {
        guard dicomFile != nil else { return nil }
        return "Protocol: " + (protocolNameForOverlay ?? "not recorded")
    }

    /// A non-empty, trimmed string value of the loaded data set.
    private func overlayString(_ tag: Tag) -> String? {
        guard let value = dicomFile?.dataSet.string(for: tag)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
