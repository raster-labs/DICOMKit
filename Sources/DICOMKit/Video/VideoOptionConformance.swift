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
    public static func violations(
        type: VideoConsole.TypeArgument,
        metadata: VideoWorkflow.Metadata,
        transferSyntax: String?
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
        return lines
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
