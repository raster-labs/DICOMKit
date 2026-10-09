// AnonPS315Support.swift
// DICOMStudio
//
// DICOM Studio — the `--profile ps315` branch of dicom-anon's anonymizeFile, shared by the CLI
// Workshop executor and the Security panel's anonymization builder (P-STUDIO-ANON-PS315).
// Reference: DICOM PS3.15 2026a Annex E (E.1 Basic Application Level Confidentiality Profile,
// Table E.1-1; E.3 Options); PS3.16 2026a CID 7050 (method codes, via DICOMKit)
// NEMA-verified: 2026a, checked 2026-10-06 — carries no table of its own: the PS3.15 Basic Profile is DICOMKit Anonymizer.deidentify(file:options:) (every row of PS3.15 2026a Table E.1-1, engine-verified), the E.3 Options are DICOMKit AnonCLI.options(flags:shiftDates:); the 10 Option names of securityPanelOptions compared by script with the 2026a DocBook (10/10: the E.3.3–E.3.5 and E.3.7–E.3.11 section titles, the two E.3.6 Option names in its text), the audit log method names are the PS3.16 CID 7050 meanings DICOMKit records; the burned-in refusal text is dicom-anon's CLI-local ValidationError text, kept identical

import Foundation
import DICOMCore
import DICOMKit

/// The PS3.15 Basic Profile path of dicom-anon (Sources/dicom-anon/main.swift, `anonymizeFile`,
/// `isPS315` branch), called by both Studio surfaces so their output equals the CLI's.
enum StudioAnonPS315 {

    /// De-identifies one read file the way dicom-anon `--profile ps315` does: DICOMKit
    /// `Anonymizer.deidentify(file:options:)` (PS3.15 2026a Table E.1-1 with the E.3 Options),
    /// the refusal of a file whose pixels may still carry PHI unless `allowBurnedInPHI`
    /// (`--allow-burned-in-phi`), then `--remove` / `--replace` through `AnonCLI.applyCustomActions`
    /// (the engine takes no custom actions). Like the CLI, no UID map is carried between files.
    ///
    /// - Throws: `AnonCLI.ValidationError` with ``WorkshopAnonError/burnedInPHIRefusal(fileName:warnings:)``.
    static func deidentify(
        _ dicomFile: DICOMFile,
        anonymizer: Anonymizer,
        options: ConfidentialityProfile.Options,
        customActions: [Tag: AnonymizationAction],
        allowBurnedInPHI: Bool,
        inputURL: URL
    ) throws -> (DICOMFile, AnonymizationResult) {
        let (file, res, _) = anonymizer.deidentify(file: dicomFile, options: options)
        if !res.warnings.isEmpty && !allowBurnedInPHI {
            throw AnonCLI.ValidationError(
                WorkshopAnonError.burnedInPHIRefusal(fileName: inputURL.lastPathComponent, warnings: res.warnings))
        }
        var scrubbed = file.dataSet
        AnonCLI.applyCustomActions(customActions, source: dicomFile.dataSet, to: &scrubbed)
        let anonymizedFile = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: scrubbed)
        let result = AnonymizationResult(
            filePath: inputURL.path, success: res.success,
            changedTags: res.changedTags, warnings: res.warnings)
        return (anonymizedFile, result)
    }

    /// One PS3.15 E.3 Option the Security panel offers for `.ps315`: its dicom-anon flag, its
    /// name as PS3.15 2026a E.3 gives it, the E.3 section, and the `AnonCLI.PS315Flags` field.
    struct OptionToggle: Sendable {
        let flag: String
        let name: String
        let section: String
        let keyPath: WritableKeyPath<AnonCLI.PS315Flags, Bool> & Sendable
    }

    /// The E.3 Options the Security panel offers (names compared by script with PS3.15 2026a
    /// E.3.3–E.3.11; 10 of the 12 Options of Table E.1-1). Not offered there: E.3.1 Clean Pixel
    /// Data and E.3.2 Clean Recognizable Visual Features (they edit pixels and need regions; the
    /// CLI Workshop's dicom-anon form has them) and the deprecated `--retain-dates`.
    static let securityPanelOptions: [OptionToggle] = [
        OptionToggle(flag: "--retain-full-dates", name: "Retain Longitudinal Temporal Information With Full Dates Option", section: "E.3.6", keyPath: \.retainFullDates),
        OptionToggle(flag: "--retain-modified-dates", name: "Retain Longitudinal Temporal Information With Modified Dates Option", section: "E.3.6", keyPath: \.retainModifiedDates),
        OptionToggle(flag: "--retain-characteristics", name: "Retain Patient Characteristics Option", section: "E.3.7", keyPath: \.retainCharacteristics),
        OptionToggle(flag: "--retain-device", name: "Retain Device Identity Option", section: "E.3.8", keyPath: \.retainDevice),
        OptionToggle(flag: "--retain-uids", name: "Retain UIDs Option", section: "E.3.9", keyPath: \.retainUids),
        OptionToggle(flag: "--retain-safe-private", name: "Retain Safe Private Option", section: "E.3.10", keyPath: \.retainSafePrivate),
        OptionToggle(flag: "--retain-institution", name: "Retain Institution Identity Option", section: "E.3.11", keyPath: \.retainInstitution),
        OptionToggle(flag: "--clean-graphics", name: "Clean Graphics Option", section: "E.3.3", keyPath: \.cleanGraphics),
        OptionToggle(flag: "--clean-structured-content", name: "Clean Structured Content Option", section: "E.3.4", keyPath: \.cleanStructuredContent),
        OptionToggle(flag: "--clean-descriptors", name: "Clean Descriptors Option", section: "E.3.5", keyPath: \.cleanDescriptors),
    ]

    /// The `--audit-log` text dicom-anon writes for `--profile ps315` (the PS3.15 engine keeps
    /// no change log of its own): the CID 7050 meanings of the options in force, plus Clean
    /// Recognizable Visual Features when that pass ran, then one line per changed attribute.
    static func auditLogText(
        options: ConfidentialityProfile.Options,
        cleanRecognizableVisualFeatures: Bool,
        reports: [(path: String, actions: [AnonCLI.AttributeAction])],
        generated: Date = Date()
    ) -> String {
        AnonCLI.auditLogText(
            profileDescription: options.methodCodes.map(\.meaning)
                + (cleanRecognizableVisualFeatures
                   ? [ConfidentialityProfile.DeidentificationMethodCode.cleanRecognizableVisualFeaturesOption.meaning]
                   : []),
            files: reports, generated: generated)
    }
}

extension WorkshopAnonError {
    /// dicom-anon's CLI-local refusal of a `--profile ps315` file whose pixels may still carry
    /// PHI (Burned In Annotation = YES or overlay planes) without `--allow-burned-in-phi`
    /// (Sources/dicom-anon/main.swift, anonymizeFile). Text kept identical to the CLI's.
    static func burnedInPHIRefusal(fileName: String, warnings: [String]) -> String {
        """
        Refusing to anonymize \(fileName): the pixel data may \
        still contain PHI.

        \(warnings.map { "  ⚠️  \($0)" }.joined(separator: "\n"))

        Without --clean-pixel-data this tool de-identifies the DATASET ONLY, \
        so burned-in text survives unchanged.

        Pass --clean-pixel-data to blank it (add --redact-region x,y,w,h if \
        the automatic region selection cannot resolve this device), or \
        --allow-burned-in-phi to write the metadata-scrubbed file anyway \
        (it will be marked Patient Identity Removed = NO).
        """
    }
}
