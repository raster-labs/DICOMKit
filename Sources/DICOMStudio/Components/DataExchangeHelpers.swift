// DataExchangeHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for Data Exchange & Export display
// Reference: DICOM PS3.10 (Media Storage), PS3.18 Annex F (JSON), PS3.19 Annex A (XML)
//
// NEMA-verified: 2026a, checked 2026-10-05 — `TransferSyntaxHelpers.wellKnownSyntaxes`: the 8 UIDs are PS3.6 2026a
// Table A-1 Transfer Syntax rows and `displayName` is now the A-1 "UID Name" taken from DICOMCore
// `TransferSyntax.displayName` (6 of the 8 literals were abbreviations); `isLossy`/`isCompressed` checked against
// PS3.5 2026a Annex A / 10.1 (Implicit VR LE is the default, Big Endian retired); `encapsulatedSOPClassUID` is
// Encapsulated PDF Storage per PS3.6 Table A-1 / PS3.4 Table B.5-1. The JSON/XML/image/batch helpers carry sizes,
// labels and estimates only.

import Foundation
import DICOMCore

// MARK: - JSON Conversion Helpers

/// Platform-independent helpers for JSON conversion display and validation.
public enum JSONConversionHelpers: Sendable {

    /// Formats a byte count as a human-readable size string.
    public static func formatOutputSize(bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        }
    }

    /// Returns a description of the bulk data threshold setting.
    public static func bulkDataThresholdDescription(bytes: Int) -> String {
        return "Inline data smaller than \(bytes) bytes; larger data uses URI references"
    }

    /// Returns a validation error for the given settings, or nil if valid.
    public static func validationError(for settings: JSONConversionSettings) -> String? {
        if settings.bulkDataThresholdBytes < 0 {
            return "Bulk data threshold must be 0 or greater."
        }
        return nil
    }

    /// Returns the description for the given output format.
    public static func outputFormatDescription(_ format: JSONOutputFormat) -> String {
        return format.description
    }

    /// Estimates the output size in bytes for a JSON conversion.
    public static func estimatedOutputSize(inputSizeBytes: Int, format: JSONOutputFormat) -> Int {
        switch format {
        case .compact:  return inputSizeBytes
        case .pretty:   return Int(Double(inputSizeBytes) * 1.3)
        case .standard: return inputSizeBytes + 512
        }
    }
}

// MARK: - XML Conversion Helpers

/// Platform-independent helpers for XML conversion display and validation.
public enum XMLConversionHelpers: Sendable {

    /// Formats a byte count as a human-readable size string.
    public static func formatOutputSize(bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        }
    }

    /// Returns a validation error for the given settings, or nil if valid.
    public static func validationError(for settings: XMLConversionSettings) -> String? {
        if settings.bulkDataThresholdBytes < 0 {
            return "Bulk data threshold must be 0 or greater."
        }
        return nil
    }

    /// Returns the description for the given output format.
    public static func outputFormatDescription(_ format: XMLOutputFormat) -> String {
        return format.description
    }

    /// Estimates the output size in bytes for an XML conversion.
    public static func estimatedOutputSize(inputSizeBytes: Int, format: XMLOutputFormat) -> Int {
        switch format {
        case .standard:   return Int(Double(inputSizeBytes) * 1.8)
        case .pretty:     return Int(Double(inputSizeBytes) * 2.1)
        case .noKeywords: return Int(Double(inputSizeBytes) * 1.6)
        }
    }
}

// MARK: - Image Export Helpers

/// Platform-independent helpers for image export display and validation.
public enum ImageExportHelpers: Sendable {

    /// Returns a quality label for the given JPEG quality value.
    public static func jpegQualityLabel(for quality: Double) -> String {
        if quality >= 0.9 { return "High" }
        if quality >= 0.7 { return "Medium" }
        return "Low"
    }

    /// Returns the linear scale factor for the given resolution setting.
    public static func scaleFactor(for resolution: ImageExportResolution) -> Double {
        switch resolution {
        case .original: return 1.0
        case .half:     return 0.5
        case .quarter:  return 0.25
        }
    }

    /// Returns the output dimensions after applying the given resolution scale.
    public static func outputDimensions(
        width: Int,
        height: Int,
        resolution: ImageExportResolution
    ) -> (width: Int, height: Int) {
        let factor = scaleFactor(for: resolution)
        return (width: Int(Double(width) * factor), height: Int(Double(height) * factor))
    }

    /// Returns a validation error for the given settings, or nil if valid.
    public static func validationError(for settings: ImageExportSettings) -> String? {
        if settings.jpegQuality < 0 || settings.jpegQuality > 1 {
            return "JPEG quality must be between 0.0 and 1.0."
        }
        return nil
    }

    /// Estimates the output file size in bytes.
    public static func estimatedFileSize(width: Int, height: Int, settings: ImageExportSettings) -> Int {
        switch settings.format {
        case .png:
            return width * height * 3
        case .jpeg:
            return Int(Double(width * height * 3) * settings.jpegQuality * 0.3)
        case .tiff:
            return width * height * 4
        }
    }
}

// MARK: - Transfer Syntax Helpers

/// Platform-independent helpers for transfer syntax display and validation.
public enum TransferSyntaxHelpers: Sendable {

    /// A curated list of well-known DICOM transfer syntaxes. `displayName` is the PS3.6 Table A-1
    /// "UID Name" (from DICOMCore); `shortName` is the abbreviation used in narrow UI.
    /// Reference: DICOM PS3.5 §10 and Annex A
    public static let wellKnownSyntaxes: [TransferSyntaxEntry] = [
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2",
            displayName: TransferSyntax.implicitVRLittleEndian.displayName,
            shortName: "Implicit LE",
            isCompressed: false,
            isLossy: false,
            description: "Default transfer syntax (PS3.5 §10.1)"
        ),
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.1",
            displayName: TransferSyntax.explicitVRLittleEndian.displayName,
            shortName: "Explicit LE",
            isCompressed: false,
            isLossy: false,
            description: "Standard uncompressed (PS3.5 §10.1)"
        ),
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.2",
            displayName: TransferSyntax.explicitVRBigEndian.displayName,
            shortName: "Explicit BE",
            isCompressed: false,
            isLossy: false,
            description: "Big endian uncompressed (Retired)"
        ),
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.4.50",
            displayName: TransferSyntax.jpegBaseline.displayName,
            shortName: "JPEG Baseline",
            isCompressed: true,
            isLossy: true,
            description: "Lossy JPEG 8-bit (PS3.5 §8.2.1)"
        ),
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.4.70",
            displayName: TransferSyntax.jpegLosslessSV1.displayName,
            shortName: "JPEG Lossless",
            isCompressed: true,
            isLossy: false,
            description: "Lossless JPEG (PS3.5 §8.2.1)"
        ),
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.4.80",
            displayName: TransferSyntax.jpegLSLossless.displayName,
            shortName: "JPEG-LS",
            isCompressed: true,
            isLossy: false,
            description: "JPEG-LS lossless (PS3.5 §8.2.3)"
        ),
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.4.90",
            displayName: TransferSyntax.jpeg2000Lossless.displayName,
            shortName: "J2K Lossless",
            isCompressed: true,
            isLossy: false,
            description: "JPEG 2000 lossless (PS3.5 §8.2.4)"
        ),
        TransferSyntaxEntry(
            uid: "1.2.840.10008.1.2.5",
            displayName: TransferSyntax.rleLossless.displayName,
            shortName: "RLE",
            isCompressed: true,
            isLossy: false,
            description: "Run-Length Encoding (PS3.5 §8.2.2)"
        )
    ]

    /// Returns a compression ratio description string (e.g. "2.4:1").
    public static func compressionRatioDescription(originalBytes: Int, compressedBytes: Int) -> String {
        guard originalBytes > 0 else { return "N/A" }
        let ratio = Double(originalBytes) / Double(compressedBytes)
        return String(format: "%.1f:1", ratio)
    }

    /// Returns a human-readable size difference label (e.g. "-120.0 KB" or "+50.0 KB").
    public static func sizeDifferenceLabel(originalBytes: Int, convertedBytes: Int) -> String {
        guard convertedBytes > 0 else { return "N/A" }
        if originalBytes == convertedBytes { return "unchanged" }
        let diff = convertedBytes - originalBytes
        let absDiff = abs(diff)
        let sign = diff > 0 ? "+" : "-"
        if absDiff < 1024 {
            return "\(sign)\(absDiff) bytes"
        } else if absDiff < 1024 * 1024 {
            let kb = Double(absDiff) / 1024.0
            return String(format: "%@%.1f KB", sign, kb)
        } else {
            let mb = Double(absDiff) / (1024.0 * 1024.0)
            return String(format: "%@%.1f MB", sign, mb)
        }
    }

    /// Returns a validation error for the given conversion job, or nil if valid.
    public static func validationError(for job: TransferSyntaxConversionJob) -> String? {
        if job.sourceFilePath.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Source file path must not be empty."
        }
        return nil
    }
}

// MARK: - DICOMDIR Helpers

/// Platform-independent helpers for DICOMDIR creation display and validation.
public enum DICOMDIRHelpers: Sendable {

    /// Returns the total number of SOP instances across all entries.
    public static func totalInstanceCount(entries: [DICOMDIREntry]) -> Int {
        entries.reduce(0) { $0 + $1.instanceCount }
    }

    /// Returns the total number of series across all entries.
    public static func totalSeriesCount(entries: [DICOMDIREntry]) -> Int {
        entries.reduce(0) { $0 + $1.seriesCount }
    }

    /// Returns a sorted array of unique modalities across all entries.
    public static func uniqueModalities(entries: [DICOMDIREntry]) -> [String] {
        let all = entries.flatMap { $0.modalities }
        return Array(Set(all)).sorted()
    }

    /// Returns a human-readable estimated disk usage string for the given instance count.
    public static func estimatedDiskUsage(instanceCount: Int) -> String {
        let bytes = instanceCount * 512_000
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else if bytes < 1024 * 1024 * 1024 {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        } else {
            let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
            return String(format: "%.2f GB", gb)
        }
    }

    /// Returns a validation error for the given DICOMDIR entry, or nil if valid.
    public static func validationError(for entry: DICOMDIREntry) -> String? {
        if entry.studyInstanceUID.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Study Instance UID must not be empty."
        }
        return nil
    }
}

// MARK: - PDF Encapsulation Helpers

/// Platform-independent helpers for PDF encapsulation display and validation.
public enum PDFEncapsulationHelpers: Sendable {

    /// Returns the description for the given PDF encapsulation mode.
    public static func modeDescription(_ mode: PDFEncapsulationMode) -> String {
        return mode.description
    }

    /// Returns the SOP Class UID for Encapsulated PDF storage.
    /// Reference: DICOM PS3.4 §B.5 — Encapsulated PDF Storage SOP Class
    public static func encapsulatedSOPClassUID() -> String {
        return "1.2.840.10008.5.1.4.1.1.104.1"
    }

    /// Returns a validation error for the given paths, or nil if valid.
    public static func validationError(inputPath: String, outputPath: String) -> String? {
        if inputPath.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Input path must not be empty."
        }
        if outputPath.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Output path must not be empty."
        }
        return nil
    }
}

// MARK: - Batch Operation Helpers

/// Platform-independent helpers for batch operation display and validation.
public enum BatchOperationHelpers: Sendable {

    /// Returns the processing progress as a fraction in [0.0, 1.0].
    public static func progressFraction(job: BatchJob) -> Double {
        guard job.totalCount > 0 else { return 0.0 }
        return Double(job.processedCount + job.failedCount) / Double(job.totalCount)
    }

    /// Returns a human-readable status description for the given job.
    public static func statusDescription(job: BatchJob) -> String {
        switch job.status {
        case .pending:
            return "Pending"
        case .inProgress:
            return "\(job.processedCount) / \(job.totalCount) processed (\(job.failedCount) failed)"
        case .completed:
            return "Completed"
        case .completedWithErrors:
            return "Completed with \(job.failedCount) error(s)"
        case .failed:
            return "Failed"
        }
    }

    /// Returns a detailed description for the given batch operation type.
    public static func operationTypeDescription(_ type: BatchOperationType) -> String {
        switch type {
        case .tagModification:
            return "Modify DICOM attribute values across multiple files in a single pass."
        case .transferSyntaxConversion:
            return "Re-encode pixel data from one transfer syntax to another (e.g. compress or decompress)."
        case .anonymization:
            return "Remove or replace patient-identifying attributes to produce de-identified datasets."
        case .imageExport:
            return "Export pixel data from each DICOM instance as a standard image file (PNG, JPEG, or TIFF)."
        }
    }

    /// Returns true if additional input items can still be added to the job.
    public static func canAddMoreItems(job: BatchJob) -> Bool {
        return job.status == .pending
    }
}
