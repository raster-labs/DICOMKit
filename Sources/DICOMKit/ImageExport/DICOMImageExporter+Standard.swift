// NEMA-verified: 2026a, checked 2026-10-06 — lifted from dicom-export ExportStandard.swift (D252) and re-read against the 2026a DocBook: PS3.3 Table C.7-13 Cine Module (Recommended Display Frame Rate (0008,2144) "Recommended rate at which the Frames of a Multi-frame Image should be displayed in Frames/second", Cine Rate (0018,0040) "Number of Frames per second", Frame Time (0018,1063) "Nominal time (in msec) per individual Frame", C.7.6.5.1.1); PS3.3 Table C.7-9 Burned In Annotation (0028,0301) Enumerated Values YES / NO ("If this Attribute is absent, then the image may or may not contain burned in annotation"); PS3.3 Table 10-3 "The first Frame shall be denoted as Frame number 1"; names and tags match PS3.6 Table 6-1
//
// DICOMImageExporter+Standard.swift
// DICOMKit
//
// The DICOM inputs and texts of an image export that `dicom-export` and DICOMStudio's
// CLI Workshop share: the cine frame rate of an animation, the Burned In Annotation
// warning, Frame-number selection, and the `--apply-window` deprecation note. Pure:
// no I/O (the callers print).
//

import Foundation
import DICOMCore

extension DICOMImageExporter {

    /// The frame rate of an animated export.
    ///
    /// Without an explicit rate the rate comes from the file's Cine Module (PS3.3 Table C.7-13):
    /// Recommended Display Frame Rate (0008,2144) — "Recommended rate at which the Frames
    /// of a Multi-frame Image should be displayed in Frames/second" — first,
    /// then Cine Rate (0018,0040) — "Number of Frames per second" — then Frame Time (0018,1063),
    /// the nominal time in msec between Frames (C.7.6.5.1.1), as 1000 / Frame Time.
    /// A file with none of them is exported at ``fallbackFPS``. Frame Time Vector
    /// (0018,1065) (variable frame timing) is not used.
    public struct CineFrameRate: Equatable, Sendable {
        /// The rate used when neither an explicit rate nor the file gives one.
        public static let fallbackFPS: Double = 10

        /// Where the rate came from.
        public enum Source: Equatable, Sendable {
            case option
            case recommendedDisplayFrameRate
            case cineRate
            case frameTime
            case fallback

            /// The PS3.6 name and tag of the attribute the rate came from.
            public var label: String {
                switch self {
                case .option: return "--fps"
                case .recommendedDisplayFrameRate: return "Recommended Display Frame Rate (0008,2144)"
                case .cineRate: return "Cine Rate (0018,0040)"
                case .frameTime: return "Frame Time (0018,1063)"
                case .fallback: return "default"
                }
            }
        }

        public let fps: Double
        public let source: Source

        public init(fps: Double, source: Source) {
            self.fps = fps
            self.source = source
        }

        /// `explicit` wins; else the Cine Module attributes in the order above; zero,
        /// negative and non-numeric values are skipped (Frame Time may be 0, C.7.6.5.1.1).
        public static func resolve(explicit: Double?, dataSet: DataSet) -> CineFrameRate {
            if let explicit { return CineFrameRate(fps: explicit, source: .option) }
            if let rate = positiveNumber(dataSet.string(for: .recommendedDisplayFrameRate)) {
                return CineFrameRate(fps: rate, source: .recommendedDisplayFrameRate)
            }
            if let rate = positiveNumber(dataSet.string(for: .cineRate)) {
                return CineFrameRate(fps: rate, source: .cineRate)
            }
            if let msec = positiveNumber(dataSet.string(for: .frameTime)) {
                return CineFrameRate(fps: 1000.0 / msec, source: .frameTime)
            }
            return CineFrameRate(fps: fallbackFPS, source: .fallback)
        }

        private static func positiveNumber(_ raw: String?) -> Double? {
            guard let raw, let value = Double(raw.trimmingCharacters(in: .whitespaces)),
                  value.isFinite, value > 0 else { return nil }
            return value
        }
    }

    /// Burned In Annotation (0028,0301), PS3.3 Table C.7-9: "Indicates whether or not image
    /// contains sufficient burned in annotation to identify the patient and date the image
    /// was acquired." Enumerated Values YES, NO; absent means it may or may not.
    /// A rendered PNG/JPEG/TIFF/GIF keeps that text in its pixels, so the export warns.
    public enum BurnedInAnnotation {
        public static func isYes(_ dataSet: DataSet) -> Bool {
            dataSet.string(for: .burnedInAnnotation)?
                .trimmingCharacters(in: .whitespaces).uppercased() == "YES"
        }

        public static func warning(for path: String) -> String {
            "warning: \(path): Burned In Annotation (0028,0301) is YES — the exported image "
                + "contains burned-in text that identifies the patient"
        }

        public static func summaryWarning(count: Int) -> String {
            "warning: \(count) exported image(s) have Burned In Annotation (0028,0301) YES — "
                + "burned-in text that identifies the patient"
        }
    }

    /// Frame selection by Frame number (P-EXPORT-1, approved 2026-10-01). PS3.3 2026a Table 10-3:
    /// "The first Frame shall be denoted as Frame number 1". The 1-based options are
    /// `--frame-number` (single) and `--start-frame-number` / `--end-frame-number` (animate); the
    /// 0-based `--frame`, `--start-frame`, `--end-frame` keep working, are deprecated, and print a
    /// one-line stderr note. Mixing the two kinds is an error (``FrameSelectionConflict``).
    public enum FrameSelection {
        public static let reference = "PS3.3 Table 10-3: the first Frame is Frame number 1"

        public static func deprecationNote(option: String, replacement: String) -> String {
            "warning: \(option) is deprecated (0-based index); use \(replacement) (numbered from 1, \(reference))"
        }

        /// Text for a Frame number the file does not have.
        public static func invalidFrameNumberMessage(requested: Int, total: Int) -> String {
            "Frame number \(requested) does not exist. The file has \(total) frame\(total == 1 ? "" : "s"), numbered 1 to \(max(total, 1))."
        }
    }

    /// A 0-based frame option and a 1-based Frame number option given together.
    public struct FrameSelectionConflict: LocalizedError, CustomStringConvertible, Equatable, Sendable {
        public let zeroBased: String
        public let oneBased: String

        public init(zeroBased: String, oneBased: String) {
            self.zeroBased = zeroBased
            self.oneBased = oneBased
        }

        public var description: String {
            "\(zeroBased) (deprecated, 0-based) and \(oneBased) (numbered from 1) cannot be used together"
        }
        public var errorDescription: String? { description }
    }

    /// `--apply-window` on `contact-sheet` and `bulk` (P-EXPORT-3, approved 2026-10-01): it has
    /// no effect there (the file's VOI is always applied), so it is deprecated.
    public enum ApplyWindowDeprecation {
        public static func note(subcommand: String) -> String {
            "warning: \(subcommand) --apply-window is deprecated and has no effect: the file's VOI (Window Center (0028,1050) / Window Width (0028,1051), else VOI LUT Sequence (0028,3010), else the full pixel range) is always applied"
        }
    }
}
