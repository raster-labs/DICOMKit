// NEMA-verified: 2026a, checked 2026-10-06 — lifted from dicom-image SCOutput.swift (D274) and re-read against the 2026a DocBook: Conversion Type Defined Terms of PS3.3 Table C.8-24 (via ConversionType.definedTerms); value limits of PS3.5 Table 6.2-1 (LO and PN: no BACKSLASH 5CH, LO 64 chars, PN 64 chars per component group, UI 64 bytes, IS -2^31..2^31-1) and the UID rules of PS3.5 9.1 (via DICOMUniqueIdentifier.parse); Media Storage SOP Instance UID (0002,0003) "Uniquely identifies the SOP Instance associated with the Data Set placed in the file" (PS3.10 Table 7.1-1), via DICOMFile.synchronizingMediaStorageUIDs (D175); Specific Character Set (0008,0005) Type 1C "Required if an expanded or replacement character set is used" (PS3.3 Table C.12-1), "ISO_IR 192" Unicode in UTF-8 (Table C.12-5), via DataSet.setUTF8SpecificCharacterSetIfNeeded (D166); Study Date / Time (0008,0020/0030) Type 2 "Date the Study started" / "Time the Study started" (PS3.3 Table C.7-3), empty when unknown (PS3.5 7.4.3), DA YYYYMMDD "interpreted as a date of the Gregorian calendar system" and TM HHMMSS.FFFFFF (HH 00-23, MM 00-59, SS 00-60) per PS3.5 Table 6.2-1 (P-IMAGE-STUDY-DATETIME, approved 2026-10-06)
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
                                           seriesNumber: Int?, instanceNumber: Int?,
                                           studyDate: String? = nil, studyTime: String? = nil) -> [String] {
            var out: [String] = []
            if let studyDate, self.studyDate(studyDate) == nil {
                out.append("--study-date '\(studyDate)' is not a DA value YYYYMMDD naming a date of the Gregorian "
                           + "calendar (PS3.5 Table 6.2-1)")
            }
            if let studyTime, self.studyTime(studyTime) == nil {
                out.append("--study-time '\(studyTime)' is not a TM value HH[MM[SS[.F{1-6}]]] with HH 00-23, MM 00-59, "
                           + "SS 00-60 (PS3.5 Table 6.2-1)")
            }
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

        // MARK: - --study-date / --study-time (PS3.3 2026a Table C.7-3, PS3.5 Table 6.2-1)

        /// Help text of `--study-date`, shown by the CLI and the Workshop.
        public static let studyDateHelp = "Study Date (0008,0020), DA YYYYMMDD: the date the Study started "
            + "(default: the conversion date for a new study; empty with --study-uid)"
        /// Help text of `--study-time`, shown by the CLI and the Workshop.
        public static let studyTimeHelp = "Study Time (0008,0030), TM HHMMSS[.FFFFFF]: the time the Study started "
            + "(default: the conversion time for a new study; empty with --study-uid)"

        /// A `--study-date` value as a DA value: exactly eight digits YYYYMMDD naming a date of the
        /// Gregorian calendar (PS3.5 2026a Table 6.2-1). Nil otherwise; the ACR-NEMA YYYY.MM.DD form
        /// that ``DICOMDate/parse(_:)`` reads is not accepted here.
        public static func studyDate(_ raw: String) -> DICOMDate? {
            guard raw.count == 8, raw.allSatisfy(isDigit), let date = DICOMDate.parse(raw) else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let components = DateComponents(year: date.year, month: date.month, day: date.day)
            guard components.isValidDate(in: calendar) else { return nil }
            return date
        }

        /// A `--study-time` value as a TM value HH, HHMM, HHMMSS or HHMMSS.F to HHMMSS.FFFFFF with
        /// HH 00-23, MM 00-59 and SS 00-60 (PS3.5 2026a Table 6.2-1). Nil otherwise; the HH:MM:SS
        /// form that ``DICOMTime/parse(_:)`` reads is not accepted here.
        public static func studyTime(_ raw: String) -> DICOMTime? {
            let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let main = parts[0]
            guard [2, 4, 6].contains(main.count), main.allSatisfy(isDigit) else { return nil }
            if parts.count == 2 {
                guard main.count == 6, (1...6).contains(parts[1].count), parts[1].allSatisfy(isDigit) else { return nil }
            }
            return DICOMTime.parse(raw)
        }

        /// Study Date / Time (0008,0020 / 0008,0030) of one run. Both are Type 2, "Date / Time the
        /// Study started" (PS3.3 2026a Table C.7-3), the same in every instance of the Study:
        /// - `--study-date` / `--study-time` given: those values (the one not given is empty);
        /// - neither given and no `--study-uid`: the run starts a new Study, so `runDate`, which the
        ///   caller takes once per run and passes for every instance;
        /// - neither given with `--study-uid`: the Study started before this run at a time the
        ///   converter does not know, so both are empty (PS3.5 7.4.3).
        ///
        /// The values must have passed ``valueViolations(patientName:patientID:studyDescription:seriesDescription:studyUID:seriesUID:seriesNumber:instanceNumber:studyDate:studyTime:)``.
        public static func studyDateTime(studyDate: String?, studyTime: String?, studyUID: String?,
                                         runDate: Date) -> (date: DICOMDate?, time: DICOMTime?) {
            if studyDate != nil || studyTime != nil {
                return (studyDate.flatMap { Self.studyDate($0) }, studyTime.flatMap { Self.studyTime($0) })
            }
            if studyUID != nil { return (nil, nil) }
            return (localDate(runDate), localTime(runDate))
        }

        /// `date` as a DA value in the local time zone on the Gregorian calendar (PS3.5 2026a Table
        /// 6.2-1 DA), whatever calendar the system uses.
        public static func localDate(_ date: Date) -> DICOMDate {
            let c = gregorianLocal.dateComponents([.year, .month, .day], from: date)
            return DICOMDate(year: c.year!, month: c.month!, day: c.day!)
        }

        /// `date` as a TM value HHMMSS in the local time zone (24-hour clock).
        public static func localTime(_ date: Date) -> DICOMTime {
            let c = gregorianLocal.dateComponents([.hour, .minute, .second], from: date)
            return DICOMTime(hour: c.hour!, minute: c.minute!, second: c.second!)
        }

        /// "0"-"9" of the Default Character Repertoire, the only characters of a DA value and,
        /// with ".", of a TM value (PS3.5 2026a Table 6.2-1).
        private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

        private static var gregorianLocal: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            return calendar
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
