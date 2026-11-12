// NEMA-verified: 2026a, checked 2026-10-06 — lifted from Sources/dicom-video/OptionConformance.swift (D269) so dicom-video and the DICOMStudio CLI Workshop share one copy; re-checked by script against the DocBook: Modality ES / GM / XC are the "The Value of Modality (0008,0060) shall be …" sentences of PS3.3 2026a A.32.5.4.1 (Video Endoscopic), A.32.6.4.1 (Video Microscopic), A.32.7.4.1 (Video Photographic); Patient's Sex Enumerated Values M / F / O are PS3.3 2026a Table C.7-1 (0010,0040); the DA form of Patient's Birth Date is PS3.6 2026a Table 6-1 / PS3.5 Table 6.2-1 (DICOMDate.parse); --transfer-syntax is refused for a UID DICOMCore accepts but PS3.6 2026a Table A-1 does not register (UIDDictionary.registered). Refusal texts unchanged (P-VIDEO-MODALITY-ENUMERATED, P-VIDEO-SEX-ENUMERATED, P-VIDEO-TS-REGISTERED, approved 2026-10-01).
//
// VideoOptionConformance.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore
import DICOMDictionary

/// Refusals for `convert` / `batch` option values that the engine accepts but
/// that yield an object the standard does not allow.
///
/// Shared by `dicom-video` and the DICOMStudio CLI Workshop (D269). Approved
/// 2026-10-01 (P-VIDEO-MODALITY-ENUMERATED, P-VIDEO-SEX-ENUMERATED,
/// P-VIDEO-TS-REGISTERED): any line returned stops the run with exit 1 before
/// anything is written. Until then the same values were written with a warning.
public enum VideoOptionConformance {

    /// The Modality (0008,0060) each IOD fixes, with the PS3.3 2026a section
    /// that says "The Value of Modality (0008,0060) shall be …".
    public static func requiredModality(
        for type: VideoConsole.TypeArgument
    ) -> (value: String, section: String) {
        switch type {
        case .endoscopic: return ("ES", "A.32.5.4.1")
        case .microscopic: return ("GM", "A.32.6.4.1")
        case .photographic: return ("XC", "A.32.7.4.1")
        }
    }

    /// PS3.3 2026a Table C.7-1, Patient's Sex (0010,0040): Enumerated Values.
    public static let patientSexValues = ["M", "F", "O"]

    /// CLI help suffixes stating the refusal (the shared `VideoConsole.Help`
    /// strings are also DICOMStudio's form help).
    public static let modalityHelp = VideoConsole.Help.modality + "; any other value is refused (exit 1)"
    public static let patientSexHelp = VideoConsole.Help.patientSex + "; other values are refused (exit 1, PS3.3 Table C.7-1)"
    public static let patientBirthDateHelp = VideoConsole.Help.patientBirthDate + "; other forms are refused (exit 1, VR DA)"
    public static let transferSyntaxHelp = VideoConsole.Help.transferSyntax + "; a UID not registered there is refused (exit 1)"

    /// Every refusal for one run, in option order.
    ///
    /// - Parameters:
    ///   - type: The `--type` in effect (the default when none was given).
    ///   - metadata: The validated metadata (modality already resolved).
    ///   - transferSyntax: The `--transfer-syntax` value, if given.
    ///   - studyDate: The raw `--study-date` string, if given.
    ///   - studyTime: The raw `--study-time` string, if given.
    public static func violations(
        type: VideoConsole.TypeArgument,
        metadata: VideoWorkflow.Metadata,
        transferSyntax: String?,
        studyDate: String? = nil,
        studyTime: String? = nil
    ) -> [String] {
        var lines: [String] = []
        if let uid = transferSyntax, let line = transferSyntaxViolation(uid) {
            lines.append(line)
        }
        if let modality = metadata.modality {
            let required = requiredModality(for: type)
            if modality != required.value {
                lines.append(VideoConsole.errorLine("""
                    --modality \(modality): PS3.3 \(required.section) requires Modality (0008,0060) \
                    \(required.value) for \(type.sopClassName); refused.
                    """))
            }
        }
        if let sex = metadata.patientSex, !patientSexValues.contains(sex) {
            lines.append(VideoConsole.errorLine("""
                --patient-sex \(sex) is not an Enumerated Value of Patient's Sex (0010,0040) \
                (M, F or O; PS3.3 Table C.7-1); refused.
                """))
        }
        if let date = metadata.patientBirthDate, DICOMDate.parse(date) == nil {
            lines.append(VideoConsole.errorLine("""
                --patient-birth-date \(date) is not a DA value (YYYYMMDD; PS3.5 Table 6.2-1) for \
                Patient's Birth Date (0010,0030); refused.
                """))
        }
        if studyDate != nil || studyTime != nil {
            lines += studyDateTimeViolations(studyDate: studyDate, studyTime: studyTime)
        } else {
            lines += studyDateTimeViolations(metadata: metadata)
        }
        return lines
    }

    /// Strict Gregorian DA and TM validation shared with the image converter.
    /// Unknown values are represented by nil, not by the conversion clock.
    public static func studyDateTimeViolations(
        studyDate: String? = nil,
        studyTime: String? = nil
    ) -> [String] {
        var lines: [String] = []
        if let date = studyDate, ImageConverter.OutputRules.studyDate(date) == nil {
            lines.append("--study-date \(date) is not a valid Gregorian DA value (YYYYMMDD) for Study Date (0008,0020); refused.")
        }
        if let time = studyTime, ImageConverter.OutputRules.studyTime(time) == nil {
            lines.append("--study-time \(time) is not a valid TM value (HH, HHMM or HHMMSS[.FFFFFF]) for Study Time (0008,0030); refused.")
        }
        return lines
    }

    /// Validates `DICOMDate` and `DICOMTime` values on ``VideoWorkflow/Metadata``
    /// against Gregorian calendar rules and TM component ranges.
    public static func studyDateTimeViolations(metadata: VideoWorkflow.Metadata) -> [String] {
        var lines: [String] = []
        if let date = metadata.studyDate, !isValidStudyDate(date) {
            lines.append("--study-date \(date.dicomString) is not a valid Gregorian DA value (YYYYMMDD) for Study Date (0008,0020); refused.")
        }
        if let time = metadata.studyTime, !isValidStudyTime(time) {
            lines.append("--study-time \(time.dicomString) is not a valid TM value (HH, HHMM or HHMMSS[.FFFFFF]) for Study Time (0008,0030); refused.")
        }
        return lines
    }

    private static func isValidStudyDate(_ date: DICOMDate) -> Bool {
        guard (0...9999).contains(date.year), (1...12).contains(date.month), (1...31).contains(date.day) else {
            return false
        }
        return ImageConverter.OutputRules.studyDate(date.dicomString) != nil
    }

    private static func isValidStudyTime(_ time: DICOMTime) -> Bool {
        guard (0...23).contains(time.hour) else { return false }
        if let minute = time.minute {
            guard (0...59).contains(minute) else { return false }
        } else if time.second != nil || time.microsecond != nil {
            return false
        }
        if let second = time.second {
            guard (0...60).contains(second) else { return false }
        } else if time.microsecond != nil {
            return false
        }
        if let microsecond = time.microsecond {
            guard (0...999_999).contains(microsecond) else { return false }
        }
        return ImageConverter.OutputRules.studyTime(time.dicomString) != nil
    }

    /// A refusal when `--transfer-syntax` names a UID that DICOMCore treats as
    /// video but PS3.6 Table A-1 does not register (the two "Fragmentable HEVC"
    /// UIDs, kept in DICOMCore by decision P2).
    public static func transferSyntaxViolation(_ uid: String) -> String? {
        guard let entry = UIDDictionary.lookup(uid: uid), !entry.registered else { return nil }
        return VideoConsole.errorLine("""
            --transfer-syntax \(uid) is not registered in PS3.6 Table A-1; \
            HEVC/H.265 has only the non-fragmentable 1.2.840.10008.1.2.4.107 and .108; refused.
            """)
    }
}
