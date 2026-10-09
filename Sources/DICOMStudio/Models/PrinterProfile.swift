// PrinterProfile.swift
// DICOMStudio
//
// DICOM Studio — a configured DICOM printer (Print SCP).
//
// Deliberately shaped like `PACSServerProfile`: printers are stored, listed,
// tested, and defaulted exactly the way PACS servers are, in the app's own
// storage. The dicom-print CLI keeps its own `~/.config/dicomkit/printers.json`
// registry — a sandboxed app cannot read that path, so the two lists are
// independent by design.
//
// NEMA-verified: 2026a, checked 2026-10-05 — default port 11112 is the PS3.8 2026a 9.1.1 registered DICOM port;
// the default AE title DICOMSTUDIO is a valid PS3.5 Table 6.2-1 AE value (11 of 16 bytes); the colour mode maps
// onto DICOMNetwork's PrintColorMode (Basic Grayscale / Basic Color Print Management, PS3.4 Annex H). No
// other standard data.

import Foundation
import DICOMNetwork

// MARK: - Printer Profile

/// A DICOM printer configuration profile.
/// Reference: DICOM PS3.4 Annex H — Print Management Service Class
public struct PrinterProfile: Sendable, Identifiable, Equatable, Hashable, Codable {
    /// Unique profile identifier.
    public let id: UUID
    /// Human-readable printer name.
    public var name: String
    /// Printer hostname or IP address.
    public var host: String
    /// DICOM port (typically 11112).
    public var port: UInt16
    /// Remote AE title (called AE — the printer).
    public var remoteAETitle: String
    /// Local AE title (calling AE — this workstation).
    public var localAETitle: String
    /// Grayscale or color print management.
    public var colorMode: PrinterColorMode
    /// Connection timeout in seconds.
    public var timeoutSeconds: Double
    /// Current connection status.
    public var status: ServerConnectionStatus
    /// Date/time of the last successful echo or status query.
    public var lastVerifiedDate: Date?
    /// Whether this is the default printer.
    public var isDefault: Bool
    /// Whether the background monitor polls this printer (FR-012).
    ///
    /// Off by default: polling opens a real association on someone's printer, so
    /// it is opted into per device rather than switched on for every profile the
    /// user has ever saved.
    public var isMonitoringEnabled: Bool
    /// Seconds between background status polls, clamped to
    /// ``PrinterProfile/monitoringIntervalRange`` (FR-012: configurable 10–300s).
    public var monitoringIntervalSeconds: Double
    /// Date/time of the last completed status poll, successful or not.
    public var lastStatusCheckDate: Date?
    /// What the printer reported at ``lastStatusCheckDate``.
    public var lastStatusDetail: String?

    /// The interval range FR-012 permits.
    public static let monitoringIntervalRange: ClosedRange<Double> = 10...300

    /// Default poll interval — 30 seconds, the figure named in the SRS.
    public static let defaultMonitoringInterval: Double = 30

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 11112,
        remoteAETitle: String,
        localAETitle: String = "DICOMSTUDIO",
        colorMode: PrinterColorMode = .grayscale,
        timeoutSeconds: Double = 60.0,
        status: ServerConnectionStatus = .unknown,
        lastVerifiedDate: Date? = nil,
        isDefault: Bool = false,
        isMonitoringEnabled: Bool = false,
        monitoringIntervalSeconds: Double = PrinterProfile.defaultMonitoringInterval,
        lastStatusCheckDate: Date? = nil,
        lastStatusDetail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.remoteAETitle = remoteAETitle
        self.localAETitle = localAETitle
        self.colorMode = colorMode
        self.timeoutSeconds = timeoutSeconds
        self.status = status
        self.lastVerifiedDate = lastVerifiedDate
        self.isDefault = isDefault
        self.isMonitoringEnabled = isMonitoringEnabled
        self.monitoringIntervalSeconds = Self.clampInterval(monitoringIntervalSeconds)
        self.lastStatusCheckDate = lastStatusCheckDate
        self.lastStatusDetail = lastStatusDetail
    }

    /// Brings any interval into the permitted range.
    ///
    /// A stored profile can carry anything — an older build, a hand-edited JSON —
    /// and an out-of-range value here would become a hot loop against a hospital
    /// printer, so it is clamped rather than trusted.
    public static func clampInterval(_ seconds: Double) -> Double {
        // NaN compares false against everything, so it cannot be clamped and
        // falls back to the default. Infinities clamp normally.
        guard !seconds.isNaN else { return defaultMonitoringInterval }
        return min(max(seconds, monitoringIntervalRange.lowerBound),
                   monitoringIntervalRange.upperBound)
    }

    /// Display string for lists: "RAD-PRINTER — 10.0.0.5:11112 (PRINT_SCP)".
    public var summary: String {
        "\(name) — \(host):\(port) (\(remoteAETitle))"
    }

    /// The ceiling for interactive probes — Test Connection and Query Status.
    ///
    /// `timeoutSeconds` is sized for a print job, where a busy printer taking a
    /// minute to answer is normal. A probe the user is watching is not: an
    /// unreachable printer would leave the menu action spinning for the full
    /// print timeout with no feedback, which reads as a hang.
    public static let probeTimeoutCeiling: Double = 10.0

    /// The Print SCU configuration this profile produces.
    ///
    /// - Parameter probe: `true` for interactive status/echo probes, which clamp
    ///   the timeout to ``probeTimeoutCeiling``. Print jobs pass `false`.
    public func printConfiguration(probe: Bool = false) -> PrintConfiguration {
        PrintConfiguration(
            host: host,
            port: port,
            callingAETitle: localAETitle,
            calledAETitle: remoteAETitle,
            // min, not a flat replacement: a profile deliberately set below the
            // ceiling keeps its shorter timeout.
            timeout: probe ? min(timeoutSeconds, Self.probeTimeoutCeiling) : timeoutSeconds,
            colorMode: colorMode.printColorMode
        )
    }

    // MARK: Codable

    /// Decodes tolerantly, so a `printer-profiles.json` written before the
    /// monitoring fields existed still loads instead of dropping every printer
    /// the user configured.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(UInt16.self, forKey: .port)
        remoteAETitle = try container.decode(String.self, forKey: .remoteAETitle)
        localAETitle = try container.decode(String.self, forKey: .localAETitle)
        colorMode = try container.decode(PrinterColorMode.self, forKey: .colorMode)
        timeoutSeconds = try container.decode(Double.self, forKey: .timeoutSeconds)
        status = try container.decode(ServerConnectionStatus.self, forKey: .status)
        lastVerifiedDate = try container.decodeIfPresent(Date.self, forKey: .lastVerifiedDate)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)

        isMonitoringEnabled = (try? container.decodeIfPresent(
            Bool.self, forKey: .isMonitoringEnabled)).flatMap { $0 } ?? false
        let storedInterval = (try? container.decodeIfPresent(
            Double.self, forKey: .monitoringIntervalSeconds)).flatMap { $0 }
        monitoringIntervalSeconds = Self.clampInterval(
            storedInterval ?? Self.defaultMonitoringInterval)
        lastStatusCheckDate = (try? container.decodeIfPresent(
            Date.self, forKey: .lastStatusCheckDate)).flatMap { $0 }
        lastStatusDetail = (try? container.decodeIfPresent(
            String.self, forKey: .lastStatusDetail)).flatMap { $0 }
    }
}

// MARK: - Color Mode

/// Whether a printer is driven with Basic Grayscale or Basic Color Print Management.
public enum PrinterColorMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case grayscale
    case color

    public var id: String { rawValue }

    /// Display label.
    public var displayName: String {
        switch self {
        case .grayscale: return "Grayscale"
        case .color:     return "Color"
        }
    }

    /// The DICOMNetwork color mode this maps to.
    public var printColorMode: DICOMNetwork.PrintColorMode {
        switch self {
        case .grayscale: return .grayscale
        case .color:     return .color
        }
    }
}
