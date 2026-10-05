// ImportValidation.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent DICOM file validation logic
//
// NEMA-verified: 2026a, checked 2026-10-05 — DICM at offset 128 after the 128-byte preamble and the 132-byte minimum (PS3.10 2026a 7.1); the 16 import-list UIDs are PS3.6 2026a Table A-1 Transfer Syntax rows and their comment names text-diffed against A-1 (16 match after 8 abbreviations were spelled out — D9); a registered but unlisted syntax is now named from DICOMCore rather than called unrecognized; required-tag messages name (0008,0018), (0008,0016), (0020,000D) per Table 6-1

import Foundation
import DICOMCore

/// Platform-independent helper for DICOM file validation.
///
/// Provides validation logic for DICOM file import, checking:
/// - File preamble and DICM magic bytes
/// - File Meta Information presence
/// - Required DICOM tags
/// - Transfer Syntax support
public enum ImportValidation: Sendable {

    /// The DICOM magic bytes "DICM" expected at offset 128.
    public static let dicmMagicBytes: [UInt8] = [0x44, 0x49, 0x43, 0x4D]

    /// Minimum valid DICOM file size (128-byte preamble + 4-byte magic + minimal meta).
    public static let minimumFileSize: Int = 132

    /// Offset where the DICM magic bytes are located.
    public static let dicmMagicOffset: Int = 128

    /// Minimum data for any DICOM content (a single minimal element).
    public static let absoluteMinimumFileSize: Int = 8

    /// Validates raw file data for DICOM compliance.
    ///
    /// The validation is intentionally lenient: missing Part 10
    /// preamble/magic is reported as a **warning**, not an error,
    /// because legacy DICOM files are still parseable via forced
    /// parsing.  Only truly too-small files are rejected outright.
    ///
    /// - Parameter data: The raw file data.
    /// - Returns: Array of validation issues found.
    public static func validate(data: Data) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Reject files that are far too small to contain any DICOM data.
        if data.count < absoluteMinimumFileSize {
            issues.append(ValidationIssue(
                severity: .error,
                message: "File is too small to be a valid DICOM file (\(data.count) bytes)",
                rule: .fileSize
            ))
            return issues
        }

        // Files smaller than 132 bytes cannot be standard Part 10 but
        // may still be legacy DICOM — flag as warning, not error.
        if data.count < minimumFileSize {
            issues.append(ValidationIssue(
                severity: .warning,
                message: "File is smaller than standard Part 10 minimum (\(data.count) bytes, expected ≥\(minimumFileSize))",
                rule: .fileSize
            ))
            return issues
        }

        // Check DICM magic bytes — missing magic is a warning because
        // force-parsing can still succeed for legacy files.
        let magicRange = dicmMagicOffset..<(dicmMagicOffset + 4)
        let magicBytes = Array(data[magicRange])
        if magicBytes != dicmMagicBytes {
            issues.append(ValidationIssue(
                severity: .warning,
                message: "Missing DICM magic bytes at offset 128 (may be a legacy DICOM file)",
                rule: .dicmMagic
            ))
        }

        return issues
    }

    /// Checks if data has a valid DICOM preamble and magic bytes.
    ///
    /// - Parameter data: The raw file data.
    /// - Returns: `true` if the file has valid DICM magic bytes.
    public static func hasDICMMagic(_ data: Data) -> Bool {
        guard data.count >= minimumFileSize else { return false }
        let magicRange = dicmMagicOffset..<(dicmMagicOffset + 4)
        return Array(data[magicRange]) == dicmMagicBytes
    }

    /// Validates that required study-level tags are present.
    ///
    /// - Parameters:
    ///   - hasStudyInstanceUID: Whether Study Instance UID is present.
    ///   - hasSOPInstanceUID: Whether SOP Instance UID is present.
    ///   - hasSOPClassUID: Whether SOP Class UID is present.
    /// - Returns: Array of validation issues for missing required tags.
    public static func validateRequiredTags(
        hasStudyInstanceUID: Bool,
        hasSOPInstanceUID: Bool,
        hasSOPClassUID: Bool
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if !hasSOPInstanceUID {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Missing required SOP Instance UID (0008,0018)",
                rule: .requiredTags
            ))
        }

        if !hasSOPClassUID {
            issues.append(ValidationIssue(
                severity: .warning,
                message: "Missing SOP Class UID (0008,0016)",
                rule: .sopClassUID
            ))
        }

        if !hasStudyInstanceUID {
            issues.append(ValidationIssue(
                severity: .warning,
                message: "Missing Study Instance UID (0020,000D)",
                rule: .requiredTags
            ))
        }

        return issues
    }

    /// Validates the Transfer Syntax UID.
    ///
    /// - Parameter transferSyntaxUID: The Transfer Syntax UID string, if present.
    /// - Returns: Array of validation issues related to transfer syntax.
    public static func validateTransferSyntax(_ transferSyntaxUID: String?) -> [ValidationIssue] {
        guard let uid = transferSyntaxUID, !uid.isEmpty else {
            return [ValidationIssue(
                severity: .info,
                message: "No Transfer Syntax UID specified; assuming Implicit VR Little Endian",
                rule: .transferSyntax
            )]
        }

        // The transfer syntaxes the viewer imports without comment, named as PS3.6 2026a Table A-1.
        let knownTransferSyntaxes: Set<String> = [
            "1.2.840.10008.1.2",        // Implicit VR Little Endian: Default Transfer Syntax for DICOM
            "1.2.840.10008.1.2.1",      // Explicit VR Little Endian
            "1.2.840.10008.1.2.2",      // Explicit VR Big Endian (Retired)
            "1.2.840.10008.1.2.1.99",   // Deflated Explicit VR Little Endian
            "1.2.840.10008.1.2.4.50",   // JPEG Baseline (Process 1)
            "1.2.840.10008.1.2.4.51",   // JPEG Extended (Process 2 & 4)
            "1.2.840.10008.1.2.4.57",   // JPEG Lossless, Non-Hierarchical (Process 14)
            "1.2.840.10008.1.2.4.70",   // JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1])
            "1.2.840.10008.1.2.4.80",   // JPEG-LS Lossless Image Compression
            "1.2.840.10008.1.2.4.81",   // JPEG-LS Lossy (Near-Lossless) Image Compression
            "1.2.840.10008.1.2.4.90",   // JPEG 2000 Image Compression (Lossless Only)
            "1.2.840.10008.1.2.4.91",   // JPEG 2000 Image Compression
            "1.2.840.10008.1.2.4.201",  // High-Throughput JPEG 2000 Image Compression (Lossless Only)
            "1.2.840.10008.1.2.4.202",  // High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)
            "1.2.840.10008.1.2.4.203",  // High-Throughput JPEG 2000 Image Compression
            "1.2.840.10008.1.2.5",      // RLE Lossless
        ]

        if !knownTransferSyntaxes.contains(uid) {
            // A UID the registry knows (PS3.6 Table A-1) is not "unrecognized": it is
            // registered but outside the list above, and the warning names it.
            let message: String
            if let registered = TransferSyntax.from(uid: uid) {
                message = "Transfer Syntax \(registered.displayName) (\(uid)) is registered in PS3.6 "
                    + "but is not among the transfer syntaxes DICOM Studio imports without warning"
            } else {
                message = "Unrecognized Transfer Syntax UID: \(uid)"
            }
            return [ValidationIssue(severity: .warning, message: message, rule: .transferSyntax)]
        }

        return []
    }

    /// Returns a summary categorization of validation issues.
    ///
    /// - Parameter issues: The validation issues to summarize.
    /// - Returns: A tuple of (errors, warnings, infos) counts.
    public static func summarize(_ issues: [ValidationIssue]) -> (errors: Int, warnings: Int, infos: Int) {
        var errors = 0, warnings = 0, infos = 0
        for issue in issues {
            switch issue.severity {
            case .error: errors += 1
            case .warning: warnings += 1
            case .info: infos += 1
            }
        }
        return (errors, warnings, infos)
    }

    /// Whether a file with the given issues should be rejected.
    ///
    /// - Parameter issues: The validation issues.
    /// - Returns: `true` if any error-level issues exist.
    public static func shouldReject(_ issues: [ValidationIssue]) -> Bool {
        issues.contains { $0.severity == .error }
    }
}
