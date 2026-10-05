// VRBadge.swift
// DICOMStudio
//
// DICOM Studio — Value Representation badge component
//
// NEMA-verified: 2026a, checked 2026-10-05 — `VRDescriptions.fullName` diffed against the 34 VRs of PS3.5 2026a
// Table 6.2-1 ("VR Name" column, verbatim): 25 matched, 2 corrected (UI "Unique Identifier (UID)", SQ "Sequence of
// Items"), 7 added (AS, AT, OL, OV, SV, UV, UR); `category` covers all 34 (the grouping and the badge colours are UI
// choices, not standard data).

import Foundation

/// Platform-independent DICOM Value Representation descriptions.
///
/// Provides human-readable names and category groupings for
/// DICOM VR codes without requiring SwiftUI.
public enum VRDescriptions: Sendable {

    /// Returns the full human-readable name for a DICOM VR code.
    ///
    /// - Parameter vr: Two-letter DICOM VR code (e.g. "PN", "UI").
    /// - Returns: Human-readable VR name.
    public static func fullName(for vr: String) -> String {
        switch vr.uppercased() {
        case "PN": return "Person Name"
        case "LO": return "Long String"
        case "SH": return "Short String"
        case "CS": return "Code String"
        case "UI": return "Unique Identifier (UID)"
        case "UR": return "Universal Resource Identifier or Universal Resource Locator (URI/URL)"
        case "DA": return "Date"
        case "TM": return "Time"
        case "DT": return "Date Time"
        case "IS": return "Integer String"
        case "DS": return "Decimal String"
        case "US": return "Unsigned Short"
        case "SS": return "Signed Short"
        case "UL": return "Unsigned Long"
        case "SL": return "Signed Long"
        case "FL": return "Floating Point Single"
        case "FD": return "Floating Point Double"
        case "OB": return "Other Byte"
        case "OW": return "Other Word"
        case "SQ": return "Sequence of Items"
        case "AS": return "Age String"
        case "AT": return "Attribute Tag"
        case "OL": return "Other Long"
        case "OV": return "Other 64-bit Very Long"
        case "SV": return "Signed 64-bit Very Long"
        case "UV": return "Unsigned 64-bit Very Long"
        case "AE": return "Application Entity"
        case "LT": return "Long Text"
        case "ST": return "Short Text"
        case "UT": return "Unlimited Text"
        case "UC": return "Unlimited Characters"
        case "OF": return "Other Float"
        case "OD": return "Other Double"
        case "UN": return "Unknown"
        default: return vr.uppercased()
        }
    }

    /// Returns the color category for a DICOM VR code.
    ///
    /// Categories are: `"string"`, `"identifier"`, `"datetime"`,
    /// `"numeric"`, `"binary"`, `"sequence"`, or `"other"`.
    ///
    /// - Parameter vr: Two-letter DICOM VR code.
    /// - Returns: Category name for color grouping.
    public static func category(for vr: String) -> String {
        switch vr.uppercased() {
        case "PN", "LO", "SH", "CS", "LT", "ST", "UT", "UC":
            return "string"
        case "UI", "AE", "UR", "AT":
            return "identifier"
        case "DA", "TM", "DT", "AS":
            return "datetime"
        case "IS", "DS", "US", "SS", "UL", "SL", "SV", "UV", "FL", "FD":
            return "numeric"
        case "OB", "OW", "OL", "OV", "OF", "OD", "UN":
            return "binary"
        case "SQ":
            return "sequence"
        default:
            return "other"
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// Displays a DICOM Value Representation as a compact badge.
///
/// Usage:
/// ```swift
/// VRBadge(vr: "PN")
/// VRBadge(vr: "UI")
/// ```
@available(macOS 14.0, iOS 17.0, *)
public struct VRBadge: View {
    let vr: String

    public init(vr: String) {
        self.vr = vr.uppercased()
    }

    public var body: some View {
        Text(vr)
            .font(.system(size: StudioTypography.captionSize, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Value Representation \(VRDescriptions.fullName(for: vr))")
    }

    private var badgeColor: Color {
        switch VRDescriptions.category(for: vr) {
        case "string": return .blue
        case "identifier": return .purple
        case "datetime": return .orange
        case "numeric": return .green
        case "binary": return .red
        case "sequence": return .indigo
        default: return .gray
        }
    }
}
#endif
