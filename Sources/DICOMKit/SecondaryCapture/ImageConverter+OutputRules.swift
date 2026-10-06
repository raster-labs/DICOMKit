// NEMA-verified: 2026a, checked 2026-10-06 — lifted from dicom-image SCOutput.swift (D274) and re-read against the 2026a DocBook: Conversion Type Defined Terms of PS3.3 Table C.8-24 (via ConversionType.definedTerms); value limits of PS3.5 Table 6.2-1 (LO and PN: no BACKSLASH 5CH, LO 64 chars, PN 64 chars per component group, UI 64 bytes, IS -2^31..2^31-1) and the UID rules of PS3.5 9.1 (via DICOMUniqueIdentifier.parse); Media Storage SOP Instance UID (0002,0003) "Uniquely identifies the SOP Instance associated with the Data Set placed in the file" (PS3.10 Table 7.1-1), via DICOMFile.synchronizingMediaStorageUIDs (D175); Specific Character Set (0008,0005) Type 1C "Required if an expanded or replacement character set is used" (PS3.3 Table C.12-1), "ISO_IR 192" Unicode in UTF-8 (Table C.12-5), via DataSet.setUTF8SpecificCharacterSetIfNeeded (D166)
//
// ImageConverter+OutputRules.swift
// DICOMKit
//
// The option checks and output guarantees of an image → Secondary Capture conversion that
// `dicom-image` and DICOMStudio's CLI Workshop share (the Workshop carried a text-identical
// copy, WorkshopSCOutput). Pure: no I/O.
//

import Foundation
import DICOMCore

extension ImageConverter {

    /// Option checks and output post-processing around ``ImageConverter/secondaryCaptureData(imageURL:pageIndex:metadata:useExif:)``.
    public enum OutputRules {

        // MARK: - --conversion-type

        /// Parses a Conversion Type option (case-insensitive) into a PS3.3 2026a Table C.8-24
        /// Defined Term. `nil` input is WSD (Workstation); a `nil` result means "not one of
        /// the eight terms".
        public static func conversionType(_ raw: String?) -> ConversionType? {
            guard let raw else { return .workstation }
            let term = raw.trimmingCharacters(in: .whitespaces).uppercased()
            guard ConversionType.definedTerms.contains(term) else { return nil }
            return ConversionType(rawValue: term)
        }

        // MARK: - Value checks (refusals; PS3.5 2026a Table 6.2-1, Section 9)

        /// Refusals for option values that the written VR cannot hold (P-IMAGE-VR, approved
        /// 2026-10-01). Any line returned stops the run with exit 1 before anything is
        /// written; until then the values were written with a warning.
        public static func valueViolations(patientName: String?, patientID: String?,
                                           studyDescription: String?, seriesDescription: String?,
                                           studyUID: String?, seriesUID: String?,
                                           seriesNumber: Int?, instanceNumber: Int?) -> [String] {
            var out: [String] = []
            for (option, value) in [("--study-uid", studyUID), ("--series-uid", seriesUID)] {
                if let value, DICOMUniqueIdentifier.parse(value) == nil {
                    out.append("\(option) '\(value)' is not a valid UID (PS3.5 9.1: digits and '.', "
                               + "no leading zero in a component, at most 64 bytes; VR UI, Table 6.2-1)")
                }
            }
            for (option, value) in [("--patient-id", patientID), ("--study-description", studyDescription),
                                    ("--series-description", seriesDescription)] {
                guard let value else { continue }
                if value.count > 64 {
                    out.append("\(option) has \(value.count) characters; LO allows at most 64 (PS3.5 Table 6.2-1)")
                }
                if value.contains("\\") {
                    out.append("\(option) contains a backslash, which LO does not allow (PS3.5 Table 6.2-1)")
                }
            }
            if let name = patientName {
                for group in name.split(separator: "=", omittingEmptySubsequences: false) where group.count > 64 {
                    out.append("--patient-name component group has \(group.count) characters; "
                               + "PN allows at most 64 per component group (PS3.5 Table 6.2-1)")
                }
                if name.contains("\\") {
                    out.append("--patient-name contains a backslash, which PN does not allow (PS3.5 Table 6.2-1)")
                }
            }
            let isRange = Int(Int32.min)...Int(Int32.max)
            for (option, value) in [("--series-number", seriesNumber), ("--instance-number", instanceNumber)] {
                if let value, !isRange.contains(value) {
                    out.append("\(option) \(value) is outside the IS range -2^31...2^31-1 (PS3.5 Table 6.2-1)")
                }
            }
            return out
        }

        // MARK: - Output guarantees

        /// Specific Character Set (0008,0005) Defined Term for UTF-8 (PS3.3 2026a Table C.12-5).
        public static let utf8CharacterSet = "ISO_IR 192"

        /// Applies the two output guarantees to a written Part 10 file:
        /// - Media Storage SOP Instance UID (0002,0003) equal to SOP Instance UID (0008,0018)
        ///   (and Media Storage SOP Class UID to SOP Class UID) — PS3.10 Table 7.1-1, through
        ///   ``DICOMFile/synchronizingMediaStorageUIDs()``;
        /// - Specific Character Set (0008,0005) = ISO_IR 192 when a text value (also inside a
        ///   Sequence Item) is not ASCII: Type 1C "Required if an expanded or replacement
        ///   character set is used" (Table C.12-1); DICOMKit writes text as UTF-8.
        ///
        /// ``ImageConverter/secondaryCaptureData(imageURL:pageIndex:metadata:useExif:)`` already
        /// writes both, so on its output this only re-serialises; it is kept for callers that
        /// post-process a file from elsewhere.
        public static func finalize(_ data: Data) throws -> Data {
            let file = try DICOMFile.read(from: data).synchronizingMediaStorageUIDs()
            var dataSet = file.dataSet
            dataSet.setUTF8SpecificCharacterSetIfNeeded()
            return try DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: dataSet).write()
        }

        /// Whether any SH, LO, ST, LT, PN, UC or UT value (also inside a Sequence Item) holds a
        /// byte outside the Default Character Repertoire (PS3.5 6.1.2.3).
        public static func usesNonASCIIText(_ dataSet: DataSet) -> Bool {
            dataSet.containsNonASCIIText()
        }
    }
}
