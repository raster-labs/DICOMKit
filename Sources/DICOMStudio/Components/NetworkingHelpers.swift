// NetworkingHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for DICOM Networking Hub display
// Reference: DICOM PS3.8 (Network Communication)
// NEMA-verified: 2026a, checked 2026-10-05 — AE Title rule compared with PS3.5 2026a Table 6.2-1 (AE: 16 bytes
// maximum, Default Character Repertoire without backslash and control characters, leading/trailing spaces
// non-significant, not solely spaces) and PS3.8 Table 9-11: the former uppercase-letters/digits/space/underscore
// rule rejected valid titles such as ANY-SCP and lowercase names and was replaced by DICOMNetwork's AETitle;
// normalize() no longer upper-cases (the standard does not fold case). Ports compared with PS3.8 2026a 9.1.1
// (104 well-known, 11112 registered) and PS3.15 2026a B.12 ("2762 dicom-tls"); 4242 is Orthanc's, not DICOM's.
// The Film Layout helpers restate FilmLayout (Table C.13-3 STANDARD\C,R) and carry no terms of their own.

import Foundation
import DICOMNetwork

// MARK: - AE Title Helpers

/// Platform-independent helpers for AE title validation and formatting.
///
/// The rule is DICOMNetwork's `AETitle` — the one the association actually
/// carries — so the form cannot accept a title the wire will refuse, or refuse
/// one the wire would take.
public enum AETitleHelpers: Sendable {

    /// The longest an AE Title can be: 16 bytes (PS3.5 Table 6.2-1; PS3.8 Table 9-11).
    public static let maximumLength = AETitle.maxLength

    /// Validates a DICOM AE title.
    ///
    /// Rules (PS3.5 2026a Table 6.2-1, VR AE; PS3.8 Table 9-11):
    /// - at most 16 bytes once leading and trailing spaces are removed
    /// - characters of the Default Character Repertoire (20H–7EH), without the
    ///   backslash (5CH) and without control characters — lowercase letters,
    ///   hyphens and punctuation are all permitted
    /// - must not be empty or consist solely of spaces
    ///
    /// - Returns: `true` if the AE title is valid.
    public static func isValid(_ aeTitle: String) -> Bool {
        (try? AETitle(aeTitle)) != nil
    }

    /// Normalises an AE title: removes the leading and trailing spaces that are
    /// not significant (PS3.8 Table 9-11).
    ///
    /// Case is left alone. An AE Title is a byte string and `orthanc` is a
    /// different title from `ORTHANC`; folding it changed the title sent.
    public static func normalize(_ aeTitle: String) -> String {
        aeTitle.trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    /// Returns a validation error message, or nil if valid.
    public static func validationError(for aeTitle: String) -> String? {
        let trimmed = normalize(aeTitle)
        if aeTitle.isEmpty { return "AE title must not be empty." }
        if trimmed.isEmpty { return "AE title must not be all spaces." }
        if trimmed.utf8.count > maximumLength {
            return "AE title must not exceed \(maximumLength) characters."
        }
        if !isValid(aeTitle) {
            return "AE title may only contain printable ASCII characters (20H–7EH), "
                + "and no backslash."
        }
        return nil
    }
}

// MARK: - Port Helpers

/// Helpers for DICOM port validation and display.
public enum PortHelpers: Sendable {

    /// Default DICOM port: the IANA *registered* port 11112, which PS3.8 9.1.1
    /// recommends when the well-known port 104 is privileged.
    public static let defaultDICOMPort: UInt16 = 11112
    /// The well-known port registered for the DICOM Upper Layer Protocol (PS3.8 9.1.1).
    public static let wellKnownDICOMPort: UInt16 = 104
    /// Default DICOM TLS port: the registered "2762 dicom-tls" (PS3.15 B.12).
    public static let defaultTLSPort: UInt16 = 2762
    /// Ports worth offering: DICOM's registered, TLS and well-known ports, and
    /// Orthanc's default (not a DICOM assignment, but the server most often
    /// found on a developer's machine).
    public static let wellKnownPorts: [UInt16] = [11112, 2762, 104, 4242]

    /// Returns true if the port is in the valid range (1–65535).
    public static func isValid(_ port: Int) -> Bool {
        port >= 1 && port <= 65535
    }

    /// Returns a description for a known DICOM port, otherwise the port number.
    ///
    /// The two DICOM ports are told apart the way PS3.8 9.1.1 does: 104 is the
    /// "well known port", 11112 the "registered" one.
    public static func displayName(for port: UInt16) -> String {
        switch port {
        case 11112: return "11112 (DICOM, registered)"
        case 2762:  return "2762 (DICOM TLS)"
        case 104:   return "104 (DICOM, well-known)"
        case 4242:  return "4242 (Orthanc)"
        default:    return "\(port)"
        }
    }
}

// MARK: - Transfer Speed Formatting

/// Helpers for formatting network throughput for display.
public enum TransferSpeedHelpers: Sendable {

    /// Formats bytes-per-second as a human-readable string.
    ///
    /// Examples:
    /// - 500 → "500 B/s"
    /// - 1536 → "1.5 KB/s"
    /// - 2097152 → "2.0 MB/s"
    public static func formatted(bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case ..<1024:
            return String(format: "%.0f B/s", bytesPerSecond)
        case ..<(1024 * 1024):
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        case ..<(1024 * 1024 * 1024):
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        default:
            return String(format: "%.2f GB/s", bytesPerSecond / (1024 * 1024 * 1024))
        }
    }

    /// Formats total bytes as a human-readable string.
    public static func formattedBytes(_ bytes: Int64) -> String {
        switch bytes {
        case ..<1024:
            return "\(bytes) B"
        case ..<(1024 * 1024):
            return String(format: "%.1f KB", Double(bytes) / 1024)
        case ..<(1024 * 1024 * 1024):
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        default:
            return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
        }
    }

    /// Formats a latency value in milliseconds.
    public static func formattedLatency(_ ms: Double) -> String {
        if ms < 1000 {
            return String(format: "%.0f ms", ms)
        } else {
            return String(format: "%.2f s", ms / 1000)
        }
    }
}

// MARK: - Query Filter Display

/// Helpers for displaying query filter summaries.
public enum QueryFilterHelpers: Sendable {

    /// Returns a short human-readable summary of an active filter.
    public static func summary(for filter: QueryFilter) -> String {
        var parts: [String] = []
        if !filter.patientName.isEmpty { parts.append("Name: \(filter.patientName)") }
        if !filter.patientID.isEmpty   { parts.append("ID: \(filter.patientID)") }
        if !filter.modality.isEmpty    { parts.append("Mod: \(filter.modality)") }
        if !filter.studyDateStart.isEmpty || !filter.studyDateEnd.isEmpty {
            let start = filter.studyDateStart.isEmpty ? "*" : filter.studyDateStart
            let end   = filter.studyDateEnd.isEmpty   ? "*" : filter.studyDateEnd
            parts.append("Date: \(start)–\(end)")
        }
        if !filter.accessionNumber.isEmpty { parts.append("Acc: \(filter.accessionNumber)") }
        return parts.isEmpty ? "(No filter)" : parts.joined(separator: ", ")
    }

    /// Validates a DICOM date string in YYYYMMDD format.
    /// Returns true if empty (no filter) or a valid 8-digit date string.
    public static func isValidDICOMDate(_ dateString: String) -> Bool {
        guard !dateString.isEmpty else { return true }
        guard dateString.count == 8, dateString.allSatisfy({ $0.isNumber }) else { return false }
        let year  = Int(dateString.prefix(4)) ?? 0
        let month = Int(dateString.dropFirst(4).prefix(2)) ?? 0
        let day   = Int(dateString.suffix(2)) ?? 0
        return year > 0 && month >= 1 && month <= 12 && day >= 1 && day <= 31
    }
}

// MARK: - Transfer Item Display

/// Helpers for displaying transfer queue items.
public enum TransferItemHelpers: Sendable {

    /// Returns a formatted progress string such as "3/10 instances (30%)".
    public static func progressLabel(for item: TransferItem) -> String {
        guard item.instancesTotal > 0 else {
            return String(format: "%.0f%%", item.progress * 100)
        }
        let pct = Int(item.progress * 100)
        return "\(item.instancesCompleted)/\(item.instancesTotal) instances (\(pct)%)"
    }

    /// Returns the estimated time remaining as a string, or nil if unknown.
    public static func estimatedTimeRemaining(for item: TransferItem) -> String? {
        guard item.bytesPerSecond > 0, item.progress > 0, item.progress < 1,
              item.instancesTotal > 0 else { return nil }
        let remaining = item.instancesTotal - item.instancesCompleted
        let avgBytesPerInstance = 512.0 * 1024  // rough estimate: 512 KB per instance
        let bytesRemaining = Double(remaining) * avgBytesPerInstance
        let secondsRemaining = bytesRemaining / item.bytesPerSecond
        if secondsRemaining < 60 { return String(format: "%.0f s remaining", secondsRemaining) }
        return String(format: "%.0f min remaining", secondsRemaining / 60)
    }
}

// MARK: - Send Queue Display

/// Helpers for displaying C-STORE send queue items.
public enum SendQueueHelpers: Sendable {

    /// Returns the retry description string.
    public static func retryLabel(for item: SendItem, config: SendRetryConfig) -> String {
        if item.retryCount == 0 { return "No retries" }
        return "Retry \(item.retryCount) of \(config.maxRetries)"
    }

    /// Computes the next retry delay in seconds using the given configuration.
    public static func nextRetryDelay(attempt: Int, config: SendRetryConfig) -> Double {
        guard attempt >= 0 else { return config.initialDelaySeconds }
        switch config.backoffStrategy {
        case .fixed:
            return config.initialDelaySeconds
        case .exponential:
            let delay = config.initialDelaySeconds * pow(2.0, Double(attempt))
            return min(delay, config.maxDelaySeconds)
        case .exponentialJitter:
            let base = config.initialDelaySeconds * pow(2.0, Double(attempt))
            let capped = min(base, config.maxDelaySeconds)
            return capped * Double.random(in: 0.75...1.25)
        }
    }
}

// MARK: - Audit Log Display

/// Helpers for displaying HIPAA audit log entries.
public enum AuditLogHelpers: Sendable {

    /// Returns a short display string for an audit log entry.
    public static func summary(for entry: AuditLogEntry) -> String {
        "[\(entry.eventType.displayName)] \(entry.remoteEntity): \(entry.outcome.displayName)"
    }

    /// Formats an audit log entry as a CSV row.
    /// Fields: timestamp, eventType, outcome, remoteEntity, localAETitle, detail
    public static func csvRow(for entry: AuditLogEntry, formatter: DateFormatter) -> String {
        let ts = formatter.string(from: entry.timestamp)
        let fields = [ts, entry.eventType.rawValue, entry.outcome.rawValue,
                      entry.remoteEntity, entry.localAETitle, entry.detail]
        return fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                     .joined(separator: ",")
    }

    /// Returns a CSV string for all provided audit entries, including a header row.
    public static func csvExport(entries: [AuditLogEntry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        let header = "\"Timestamp\",\"Event Type\",\"Outcome\",\"Remote Entity\",\"Local AE\",\"Detail\""
        let rows = entries.sorted { $0.timestamp < $1.timestamp }
                          .map { csvRow(for: $0, formatter: formatter) }
        return ([header] + rows).joined(separator: "\n")
    }
}

// MARK: - Server Profile Validation

/// Helpers for validating server profile configurations.
public enum ServerProfileValidation: Sendable {

    /// Returns a list of validation errors for a server profile, or empty if valid.
    public static func validate(_ profile: PACSServerProfile) -> [String] {
        var errors: [String] = []
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Server name must not be empty.")
        }
        if profile.host.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Hostname must not be empty.")
        }
        if !PortHelpers.isValid(Int(profile.port)) {
            errors.append("Port must be between 1 and 65535.")
        }
        if let aeError = AETitleHelpers.validationError(for: profile.remoteAETitle) {
            errors.append("Remote AE title: \(aeError)")
        }
        if let aeError = AETitleHelpers.validationError(for: profile.localAETitle) {
            errors.append("Local AE title: \(aeError)")
        }
        if profile.timeoutSeconds <= 0 {
            errors.append("Timeout must be greater than 0.")
        }
        return errors
    }

    /// Returns true if the profile is valid.
    public static func isValid(_ profile: PACSServerProfile) -> Bool {
        validate(profile).isEmpty
    }
}

// MARK: - MPPS Display

/// Helpers for displaying MPPS procedure step information.
public enum MPPSHelpers: Sendable {

    /// Formats a radiation dose in mGy for display.
    public static func formattedDose(_ dosemGy: Double?) -> String {
        guard let dose = dosemGy else { return "N/A" }
        return String(format: "%.2f mGy", dose)
    }

    /// Formats an exposure in mAs for display.
    public static func formattedExposure(_ exposuremAs: Double?) -> String {
        guard let exp = exposuremAs else { return "N/A" }
        return String(format: "%.1f mAs", exp)
    }

    /// Returns the elapsed time string for an in-progress or completed MPPS item.
    public static func elapsedTime(for item: MPPSItem) -> String {
        let end = item.endDateTime ?? Date()
        let elapsed = end.timeIntervalSince(item.startDateTime)
        if elapsed < 60 { return String(format: "%.0f sec", elapsed) }
        if elapsed < 3600 { return String(format: "%.0f min", elapsed / 60) }
        return String(format: "%.1f hr", elapsed / 3600)
    }
}

// MARK: - Print Helpers

/// Helpers for DICOM print configuration display.
public enum PrintHelpers: Sendable {

    /// Returns the DICOM tag value string for a film layout.
    /// This matches the DICOM (2010,0010) Image Display Format tag value.
    public static func dicomTagValue(for layout: FilmLayout) -> String {
        layout.rawValue
    }

    /// Returns a description of a print job.
    public static func description(for job: PrintJob) -> String {
        """
        \(job.filmLayout.displayName) layout, \
        \(job.numberOfCopies) copy(s), \
        \(job.mediumType.displayName), \
        \(job.imageFilePaths.count) image(s)
        """
    }

    /// Returns all available layouts sorted by cell count.
    public static func allLayouts() -> [FilmLayout] {
        FilmLayout.allCases.sorted { $0.cellCount < $1.cellCount }
    }

    /// Computes how many film sheets are required for a given number of images.
    public static func filmSheetCount(imageCount: Int, layout: FilmLayout) -> Int {
        guard imageCount > 0 else { return 0 }
        return (imageCount + layout.cellCount - 1) / layout.cellCount
    }

    /// Returns the range of image indices for a specific film sheet (0-based).
    public static func imageIndices(forSheet sheet: Int, layout: FilmLayout, totalImages: Int) -> Range<Int> {
        let start = sheet * layout.cellCount
        let end = min(start + layout.cellCount, totalImages)
        return start ..< end
    }

    /// Returns a summary string for the film preview.
    public static func previewSummary(imageCount: Int, layout: FilmLayout) -> String {
        let sheets = filmSheetCount(imageCount: imageCount, layout: layout)
        if sheets <= 1 {
            return "\(imageCount) of \(layout.cellCount) cells filled"
        }
        return "\(imageCount) images across \(sheets) film sheets"
    }
}

// MARK: - Monitoring Display

/// Helpers for displaying network monitoring metrics.
public enum MonitoringHelpers: Sendable {

    /// Returns a success rate as a percentage string.
    public static func successRateLabel(_ stats: NetworkMonitoringStats) -> String {
        String(format: "%.1f%%", stats.successRate * 100)
    }

    /// Returns a short summary of monitoring stats.
    public static func summary(_ stats: NetworkMonitoringStats) -> String {
        let inbound  = TransferSpeedHelpers.formatted(bytesPerSecond: stats.inboundBytesPerSecond)
        let outbound = TransferSpeedHelpers.formatted(bytesPerSecond: stats.outboundBytesPerSecond)
        return "Connections: \(stats.pooledConnectionCount) pooled, \(stats.activeAssociationCount) active | ↓\(inbound) ↑\(outbound)"
    }
}
