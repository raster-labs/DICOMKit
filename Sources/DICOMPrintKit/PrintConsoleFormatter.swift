// NEMA-verified: 2026a, checked 2026-10-01 — JSON keyword keys diffed against PS3.6 2026a Table 6-1 (9 keywords: PrinterStatus, PrinterStatusInfo, PrinterName, Manufacturer, ManufacturerModelName, ExecutionStatus, ExecutionStatusInfo, CreationDate DA, CreationTime TM; P-PRINT-JSON); the older tool keys are kept (deprecated); text labels are the PS3.3 Table C.13-8 (4) / C.13-9 (5) attribute names as PS3.6 spells them (D90)
// PrintConsoleFormatter.swift
// DICOMPrintKit
//
// Every line the print surfaces render — printer status, send result, job
// status, film plan — is built here, so the DICOMStudio console and the
// dicom-print terminal output stay identical. Mirrors the role
// NetworkConsoleFormatter plays for query/send/retrieve.
//
// The functions return strings; routing (stdout vs stderr, view vs terminal)
// is the caller's job.

import Foundation
import DICOMNetwork

public enum PrintConsoleFormatter {

    // MARK: - Printer status

    /// Human-readable printer status block. Each label is the attribute name of the
    /// Printer Module (PS3.3 Table C.13-9) as PS3.6 Table 6-1 spells it.
    public static func printerStatusText(_ status: PrinterStatus) -> [String] {
        var lines: [String] = []
        lines.append("Printer Status")
        lines.append("==============")
        lines.append("Printer Name: \(status.printerName ?? "Unknown")")
        lines.append("Printer Status: \(status.status)")
        if let info = status.statusInfo {
            lines.append("Printer Status Info: \(info)")
        }
        if let manufacturer = status.manufacturer {
            lines.append("Manufacturer: \(manufacturer)")
        }
        if let model = status.manufacturerModelName {
            lines.append("Manufacturer's Model Name: \(model)")
        }
        lines.append("Is Normal: \(status.isNormal ? "Yes" : "No")")
        return lines
    }

    /// Machine-readable printer status. Each N-GET attribute is keyed by its PS3.6
    /// Table 6-1 keyword (`PrinterStatus`, `PrinterStatusInfo`, `PrinterName`,
    /// `Manufacturer`, `ManufacturerModelName`). The older tool keys (`status`,
    /// `statusInfo`, `name`, `manufacturer`, `model`) carry the same values and are
    /// deprecated; `isNormal` is derived and has no keyword.
    public static func printerStatusJSON(_ status: PrinterStatus) -> String? {
        var dict: [String: Any] = [
            "status": status.status,
            "PrinterStatus": status.status,
            "isNormal": status.isNormal
        ]
        if let name = status.printerName { dict["name"] = name; dict["PrinterName"] = name }
        if let info = status.statusInfo { dict["statusInfo"] = info; dict["PrinterStatusInfo"] = info }
        if let manufacturer = status.manufacturer {
            dict["manufacturer"] = manufacturer
            dict["Manufacturer"] = manufacturer
        }
        if let model = status.manufacturerModelName { dict["model"] = model; dict["ManufacturerModelName"] = model }
        return json(from: dict)
    }

    // MARK: - Print result

    /// Human-readable outcome of a print job.
    public static func printResultText(_ result: PrintResult) -> [String] {
        var lines: [String] = []
        if result.success {
            lines.append("✓ Print job submitted successfully")
            if let jobUID = result.printJobUID {
                lines.append("  Print Job UID: \(jobUID)")
            }
            if let sessionUID = result.filmSessionUID {
                lines.append("  Film Session UID: \(sessionUID)")
            }
        } else {
            lines.append("✗ Print failed")
            if let error = result.errorMessage {
                lines.append("  Error: \(error)")
            }
        }
        return lines
    }

    /// Machine-readable outcome. Multi-film jobs also list every film box and
    /// print job UID; the singular keys stay for existing consumers.
    public static func printResultJSON(_ result: PrintResult) -> String? {
        var dict: [String: Any] = [
            "success": result.success
        ]
        if let jobUID = result.printJobUID { dict["printJobUID"] = jobUID }
        if let sessionUID = result.filmSessionUID { dict["filmSessionUID"] = sessionUID }
        if let filmBoxUID = result.filmBoxUID { dict["filmBoxUID"] = filmBoxUID }
        if result.filmBoxUIDs.count > 1 { dict["filmBoxUIDs"] = result.filmBoxUIDs }
        if result.printJobUIDs.count > 1 { dict["printJobUIDs"] = result.printJobUIDs }
        if let error = result.errorMessage { dict["error"] = error }
        return json(from: dict)
    }

    // MARK: - Print job status

    /// Human-readable print job status block. Each label is the attribute name of the
    /// Print Job Module (PS3.3 Table C.13-8) as PS3.6 Table 6-1 spells it.
    public static func jobStatusText(_ status: PrintJobStatus) -> [String] {
        var lines: [String] = []
        lines.append("Print Job Status")
        lines.append("================")
        lines.append("Job UID: \(status.printJobUID)")
        lines.append("Execution Status: \(status.executionStatus)")
        if let info = status.executionStatusInfo {
            lines.append("Execution Status Info: \(info)")
        }
        if let creationDate = status.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            lines.append("Creation Date: \(formatter.string(from: creationDate))")
        }
        if let creationTime = status.creationTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            lines.append("Creation Time: \(formatter.string(from: creationTime))")
        }
        return lines
    }

    /// Machine-readable print job status. Each N-GET attribute is keyed by its PS3.6
    /// Table 6-1 keyword (`ExecutionStatus`, `ExecutionStatusInfo`, `CreationDate` as DA
    /// YYYYMMDD, `CreationTime` as TM HHMMSS). The older tool keys (`status`,
    /// `statusInfo`, `creationDate` as ISO 8601) carry the same values and are
    /// deprecated; `jobUID` (the Print Job SOP Instance UID) stays.
    public static func jobStatusJSON(_ status: PrintJobStatus) -> String? {
        var dict: [String: Any] = [
            "jobUID": status.printJobUID,
            "status": status.executionStatus,
            "ExecutionStatus": status.executionStatus
        ]
        if let info = status.executionStatusInfo { dict["statusInfo"] = info; dict["ExecutionStatusInfo"] = info }
        if let creationDate = status.creationDate {
            dict["creationDate"] = ISO8601DateFormatter().string(from: creationDate)
            dict["CreationDate"] = dicomValue(creationDate, format: "yyyyMMdd")
        }
        if let creationTime = status.creationTime {
            dict["CreationTime"] = dicomValue(creationTime, format: "HHmmss")
        }
        return json(from: dict)
    }

    /// DA / TM text in the time zone DICOMNetwork parsed the value in (the current one).
    private static func dicomValue(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    // MARK: - Film plan

    /// One-line film plan summary: "12 image(s) → 3 film(s) (2×2, 14INX17IN, PORTRAIT)".
    ///
    /// A band layout is named by its format string rather than by a grid —
    /// `ROW\2,1,2` is not 3×2, and reporting it as one would misstate the film.
    public static func planSummary(_ plan: PrintPlan) -> String {
        let grid = plan.displayFormat.isUniformGrid
            ? "\(plan.layout.rows)×\(plan.layout.columns)"
            : plan.displayFormat.raw
        var line = "\(plan.imageCount) image(s) → \(plan.filmCount) film(s) "
            + "(\(grid), \(plan.filmSize.rawValue), \(plan.filmOrientation.rawValue))"
        if plan.copies > 1 {
            line += " × \(plan.copies) copies = \(plan.totalSheets) sheets"
        }
        return line
    }

    /// Per-film breakdown, e.g. "Film 3 of 3: images 9-12 (4 of 4 cells)".
    public static func planDetail(_ plan: PrintPlan) -> [String] {
        (0..<plan.filmCount).map { filmIndex in
            let range = plan.imageIndices(onFilm: filmIndex)
            let used = range.count
            return "Film \(filmIndex + 1) of \(plan.filmCount): "
                + "images \(range.lowerBound + 1)-\(range.upperBound) "
                + "(\(used) of \(plan.cellsPerFilm) cells)"
        }
    }

    // MARK: - Helpers

    private static func json(from dict: Any) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
}
