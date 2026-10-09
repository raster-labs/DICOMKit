// DICOMFileService.swift
// DICOMStudio
//
// DICOM Studio — File I/O operations via DICOMKit
//
// NEMA-verified: 2026a, checked 2026-10-05 — Transfer Syntax UID read from File Meta Information (0002,0010) with
// Data Set fallback (PS3.10 2026a Table 7.1-1); Media Storage Directory Storage 1.2.840.10008.1.3.10 (PS3.6 2026a
// Table A-1) refused as a non-instance; Tag literals (0008,0061) Modalities in Study, (0008,0021) Series Date,
// (0008,0022) Acquisition Date and the DICOMCore constants used match PS3.6 2026a Table 6-1; Instance Number /
// Series Number read as IS (Table 6-1); DA parsed per PS3.5 Table 6.2-1 YYYYMMDD with tolerance for legacy
// separators; default Modality "OT" is a PS3.3 2026a C.7.3.1.1.1 Defined Term.

import Foundation
import DICOMKit
import DICOMCore
import os.log

/// Logger for DICOM file service diagnostics.
private let logger = Logger(subsystem: "com.dicomstudio", category: "DICOMFileService")

/// Result of a single DICOM parse, containing all three model levels.
///
/// Produced by ``DICOMFileService/parseAllMetadata(data:url:)``
/// so the caller can extract instance, study, and series data from
/// a single ``DICOMFile`` parse.
public struct DICOMParseResult: Sendable {
    public let instance: InstanceModel
    public let study: StudyModel
    public let series: SeriesModel
}

/// Provides DICOM file I/O operations using DICOMKit.
///
/// This service wraps DICOMKit's parsing and file operations, converting
/// raw DICOM data into the application's model types.
public final class DICOMFileService: Sendable {

    public init() {}

    // MARK: - Combined Parse (preferred)

    /// Parses raw DICOM data **once** and returns instance, study, and
    /// series models in a single pass.
    ///
    /// This is the preferred entry point — it avoids re-parsing the same
    /// bytes three times and correctly reads Transfer Syntax UID from
    /// File Meta Information.
    ///
    /// - Parameters:
    ///   - data: Raw file data.
    ///   - url:  Original file URL (used for file size and path).
    /// - Returns: A ``DICOMParseResult`` with all three models.
    /// - Throws: If the data cannot be parsed as DICOM.
    public func parseAllMetadata(data: Data, url: URL) throws -> DICOMParseResult {
        logger.debug("Parsing DICOM data (\(data.count) bytes) from \(url.lastPathComponent)")

        // Try standard Part 10 first, then fall back to force-parsing
        // for legacy DICOM files without the Part 10 preamble.
        let dicomFile: DICOMFile
        var usedForceFallback = false
        do {
            dicomFile = try DICOMFile.read(from: data)
        } catch {
            logger.info("Standard parse failed (\(error.localizedDescription)), retrying with force=true")
            dicomFile = try DICOMFile.read(from: data, force: true)
            usedForceFallback = true
        }
        let ds  = dicomFile.dataSet
        let fmi = dicomFile.fileMetaInformation

        // The legacy/force path uses a lenient "looks like DICOM" heuristic that
        // accepts any data whose first two bytes form an even uint16 < 0x7FFF —
        // which matches a lot of plain ASCII text. Reject force-parsed results
        // that carry none of the identifying UIDs every real instance has.
        if usedForceFallback {
            let hasIdentifyingTag = ds.string(for: .sopInstanceUID) != nil
                || ds.string(for: .sopClassUID) != nil
                || ds.string(for: .studyInstanceUID) != nil
                || ds.string(for: .seriesInstanceUID) != nil
            if !hasIdentifyingTag {
                throw DICOMError.parsingFailed("Force-parsed data lacks any DICOM identifying UID")
            }
        }

        // --- Transfer Syntax UID lives in File Meta Information (0002,0010) ---
        let transferSyntaxUID = fmi.string(for: .transferSyntaxUID)
            ?? ds.string(for: .transferSyntaxUID)

        // A DICOMDIR is an index of a file set, not an instance of anything: it
        // has no image, no series and no study of its own. Importing one used to
        // manufacture a study out of it — the "Unknown Patient, 0 series, 0
        // images" row — so it is refused here, where the SOP Class is known.
        let mediaStorageSOPClass = fmi.string(for: .mediaStorageSOPClassUID)
            ?? ds.string(for: .sopClassUID)
        if mediaStorageSOPClass == Self.mediaStorageDirectoryUID {
            throw DICOMError.parsingFailed(
                "This is a DICOMDIR index, not an image — import the files it refers to")
        }

        // Identity is what makes an instance filable. Without a SOP Instance UID
        // and a Series Instance UID there is nothing to key a series on, and the
        // fabricated UUIDs below would file the object under a study that can
        // never be opened again.
        guard let realSOPInstanceUID = ds.string(for: .sopInstanceUID)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !realSOPInstanceUID.isEmpty,
              let realSeriesInstanceUID = ds.string(for: .seriesInstanceUID)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !realSeriesInstanceUID.isEmpty
        else {
            throw DICOMError.parsingFailed(
                "File carries no SOP Instance UID or Series Instance UID")
        }

        // --- Instance ---
        let sopInstanceUID = realSOPInstanceUID
        let sopClassUID = ds.string(for: .sopClassUID)
            ?? fmi.string(for: .mediaStorageSOPClassUID)
            ?? ""
        let seriesInstanceUID = realSeriesInstanceUID
        // Instance Number is IS — an *integer string* — so it has to be read as
        // text. Read as a binary SL it is always nil, which is how a series ends
        // up in file-system order instead of acquisition order.
        let instanceNumber = Self.integerString(in: ds, tag: .instanceNumber)
        let rows = ds.uint16(for: .rows).map { Int($0) }
        let columns = ds.uint16(for: .columns).map { Int($0) }
        let bitsAllocated = ds.uint16(for: .bitsAllocated).map { Int($0) }
        let photometricInterpretation = ds.string(for: .photometricInterpretation)
        let numberOfFrames = ds.string(for: .numberOfFrames)
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let fileSize = Int64(data.count)

        let instance = InstanceModel(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            seriesInstanceUID: seriesInstanceUID,
            instanceNumber: instanceNumber,
            filePath: url.path,
            fileSize: fileSize,
            transferSyntaxUID: transferSyntaxUID,
            rows: rows,
            columns: columns,
            bitsAllocated: bitsAllocated,
            numberOfFrames: numberOfFrames,
            photometricInterpretation: photometricInterpretation
        )

        // --- Study ---
        // A file with no Study Instance UID still has to be filed somewhere. A
        // fresh UUID per file put every image in a study of its own — a library
        // full of one-image studies — so the series it belongs to is used as the
        // key instead: the objects that belong together stay together, and the
        // study is stable across re-imports of the same file.
        let declaredStudyUID = ds.string(for: .studyInstanceUID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let studyInstanceUID = (declaredStudyUID?.isEmpty == false)
            ? declaredStudyUID! : realSeriesInstanceUID
        let modality = ds.string(for: .modality)
        var modalitiesInStudy: Set<String> = []
        if let mod = modality?.trimmingCharacters(in: .whitespaces), !mod.isEmpty {
            modalitiesInStudy.insert(mod)
        }
        // Modalities in Study (0008,0061) is a multi-valued list naming every
        // modality of the exam. Where it is present it says more than this one
        // file's own Modality, so both are folded in.
        for value in ds.strings(for: Tag(group: 0x0008, element: 0x0061)) ?? [] {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { modalitiesInStudy.insert(trimmed) }
        }

        // Study Date, then the dates a study falls back to when it has none of
        // its own. A study filed under "Unknown Date" sorts to the bottom of the
        // library and reads as a broken import, so a date is worth looking for.
        let studyDate = Self.date(in: ds, tags: [
            .studyDate,
            Tag(group: 0x0008, element: 0x0021),   // Series Date
            Tag(group: 0x0008, element: 0x0022)    // Acquisition Date
        ])

        let study = StudyModel(
            studyInstanceUID: studyInstanceUID,
            studyID: ds.string(for: .studyID) ?? "",
            studyDate: studyDate,
            studyDescription: ds.string(for: .studyDescription),
            accessionNumber: ds.string(for: .accessionNumber),
            referringPhysicianName: ds.string(for: .referringPhysicianName),
            patientName: ds.string(for: .patientName),
            patientID: ds.string(for: .patientID),
            patientSex: ds.string(for: .patientSex),
            institutionName: ds.string(for: .institutionName),
            modalitiesInStudy: modalitiesInStudy
        )

        // --- Series ---
        let series = SeriesModel(
            seriesInstanceUID: seriesInstanceUID,
            studyInstanceUID: studyInstanceUID,
            seriesNumber: Self.integerString(in: ds, tag: .seriesNumber),
            modality: modality ?? "OT",
            seriesDescription: ds.string(for: .seriesDescription),
            bodyPartExamined: ds.string(for: .bodyPartExamined),
            transferSyntaxUID: transferSyntaxUID
        )

        logger.debug("Parsed OK — SOP UID=\(sopInstanceUID), Study UID=\(studyInstanceUID), Series UID=\(seriesInstanceUID)")
        return DICOMParseResult(instance: instance, study: study, series: series)
    }

    // MARK: - Legacy convenience (kept for tests / callers that need a single model)

    /// Parses a DICOM file and returns an InstanceModel with extracted metadata.
    public func parseFile(at url: URL) throws -> InstanceModel {
        let data = try Data(contentsOf: url)
        return try parseAllMetadata(data: data, url: url).instance
    }

    /// Parses already-loaded DICOM data and returns an InstanceModel.
    public func parseFileData(_ data: Data, at url: URL) throws -> InstanceModel {
        try parseAllMetadata(data: data, url: url).instance
    }

    /// Extracts study-level metadata from a DICOM file's data set.
    public func extractStudyMetadata(from url: URL) throws -> StudyModel {
        let data = try Data(contentsOf: url)
        return try parseAllMetadata(data: data, url: url).study
    }

    /// Extracts study-level metadata from already-loaded DICOM data.
    public func extractStudyMetadataFromData(_ data: Data) throws -> StudyModel {
        try parseAllMetadata(data: data, url: URL(fileURLWithPath: "/unknown")).study
    }

    /// Extracts series-level metadata from a DICOM file's data set.
    public func extractSeriesMetadata(from url: URL) throws -> SeriesModel {
        let data = try Data(contentsOf: url)
        return try parseAllMetadata(data: data, url: url).series
    }

    /// Extracts series-level metadata from already-loaded DICOM data.
    public func extractSeriesMetadataFromData(_ data: Data) throws -> SeriesModel {
        try parseAllMetadata(data: data, url: URL(fileURLWithPath: "/unknown")).series
    }

    /// The first parsable date among a list of date tags.
    ///
    /// DA is eight digits, but real files carry `yyyy.MM.dd` (ACR-NEMA era),
    /// `yyyy-MM-dd`, and dates with a time or a range appended. Anything with
    /// eight leading digits is a date, and reading it beats filing the study
    /// under "Unknown Date".
    static func date(in dataSet: DataSet, tags: [Tag]) -> Date? {
        for tag in tags {
            guard let raw = dataSet.string(for: tag)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            if let parsed = parseDICOMDate(raw) { return parsed }
        }
        return nil
    }

    /// Parses one DA value, tolerating the separators found in the wild.
    static func parseDICOMDate(_ raw: String) -> Date? {
        // An empty value is not a date, and `DateFormatter` is happy to read one
        // as the start of its era rather than refusing it.
        guard raw.contains(where: \.isNumber) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for pattern in ["yyyyMMdd", "yyyy.MM.dd", "yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: raw) { return date }
        }
        // Last resort: the leading eight digits, which covers a date with a
        // time, a range, or padding stuck to it.
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: String(digits.prefix(8)))
    }


    /// Media Storage Directory Storage — the SOP Class of a DICOMDIR.
    static let mediaStorageDirectoryUID = "1.2.840.10008.1.3.10"

    /// Reads an IS (Integer String) element, e.g. Series Number, Instance Number.
    ///
    /// IS values are text — `"7"`, `" 7 "`, `"+7"` — and are padded to an even
    /// length. `DataSet.int32(for:)` decodes binary SL only and returns nil for
    /// every one of them, which silently un-numbers every series and instance in
    /// the library.
    static func integerString(in dataSet: DataSet, tag: Tag) -> Int? {
        guard let raw = dataSet.string(for: tag)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            // Some devices really do write it as binary; honour that too.
            return dataSet.int32(for: tag).map(Int.init)
        }
        if let value = Int(raw) { return value }
        // Multi-valued or decorated: take the leading signed integer.
        let firstValue = raw.split(separator: "\\").first.map(String.init) ?? raw
        return Int(firstValue.trimmingCharacters(in: .whitespaces))
    }

}
