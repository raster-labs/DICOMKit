// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (corner caption text model)
// PrintCornerAnnotation.swift
// DICOMPrintKit
//
// What each corner of a printed image says.
//
// Film is annotated the way a reading station is: text in the corners of the
// picture, where a fitted image has background rather than anatomy, and the
// reader's eye — which is in the middle — is never taken off the finding to go
// and read a strip. The arrangement is the workstation's, so a film and the
// screen it was approved on are read the same way:
//
//   top right     who and what — patient and study.
//   bottom left   what made the picture: modality, image number, technique.
//   bottom right  when the study was taken.
//
// Carried as text rather than as Basic Annotation Boxes: a printer lays those
// out to its own configured format, wherever it likes, and many ignore them.

import Foundation

/// Lines of burned-in text, by the corner they belong in.
public struct PrintCornerAnnotation: Sendable, Equatable, Hashable, Codable {

    public var topLeft: [String]
    public var topRight: [String]
    public var bottomLeft: [String]
    public var bottomRight: [String]

    public init(
        topLeft: [String] = [],
        topRight: [String] = [],
        bottomLeft: [String] = [],
        bottomRight: [String] = []
    ) {
        func clean(_ lines: [String]) -> [String] {
            lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        self.topLeft = clean(topLeft)
        self.topRight = clean(topRight)
        self.bottomLeft = clean(bottomLeft)
        self.bottomRight = clean(bottomRight)
    }

    /// Whether there is anything to draw.
    public var isEmpty: Bool {
        topLeft.isEmpty && topRight.isEmpty && bottomLeft.isEmpty && bottomRight.isEmpty
    }

    /// Every line, in reading order — for logs and accessibility, not for layout.
    public var allLines: [String] { topLeft + topRight + bottomLeft + bottomRight }
}
