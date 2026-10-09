// PrinterStatusPresentation.swift
// DICOMStudio
//
// DICOM Studio — how a printer's reported state looks on screen.
//
// PS3.3 C.13.9 gives three states and the UI showed two, so a printer low on
// film looked identical to one that had failed. The mapping lives here rather
// than inline in each view, so the settings pane and the printer list cannot
// drift apart on what amber means.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the three Printer Status (2110,0010) values of PS3.3 2026a Table C.13-9
// (NORMAL, WARNING, FAILURE) are DICOMNetwork's PrinterStatusSeverity cases, each given its own colour and glyph
// here plus unknown; Printer Status Info (2110,0020) is shown as the SCP sent it. No literal of its own.

import SwiftUI
import DICOMNetwork

/// Colour, icon and label for a printer's reported status.
public enum PrinterStatusPresentation {

    /// Traffic-light colour: green normal, amber warning, red failure, grey unknown.
    public static func color(for severity: PrinterStatusSeverity) -> Color {
        switch severity {
        case .normal:  return .green
        case .warning: return .orange
        case .failure: return .red
        case .unknown: return .secondary
        }
    }

    /// SF Symbol matching ``color(for:)``.
    ///
    /// Warning and failure take visibly different glyphs, not just different
    /// tints — colour alone is not a safe signal for colour-blind users.
    public static func symbol(for severity: PrinterStatusSeverity) -> String {
        switch severity {
        case .normal:  return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Traffic-light colour for the stored connection status, which is what the
    /// printer list shows between status queries.
    ///
    /// Named apart from ``color(for:)`` deliberately: both enums carry a
    /// `warning` case, so a shared overload makes every `.warning` call site
    /// ambiguous wherever both modules are imported.
    public static func connectionColor(for status: ServerConnectionStatus) -> Color {
        switch status {
        case .online:  return .green
        case .warning: return .orange
        case .error:   return .red
        case .offline: return .secondary
        case .testing: return .secondary
        case .unknown: return .secondary
        }
    }

    /// One-line summary: the state, plus the printer's own detail when it gave one.
    ///
    /// The SCP's Printer Status Info (2110,0020) is the part a technologist can
    /// act on ("SUPPLY LOW"), so it is never dropped when present.
    public static func summary(for status: PrinterStatus) -> String {
        let detail = status.statusInfo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = status.severity.displayName
        guard let detail, !detail.isEmpty else { return base }
        return "\(base) — \(detail)"
    }
}
