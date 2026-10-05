// ModalityIcon.swift
// DICOMStudio
//
// DICOM Studio — Modality-specific SF Symbol icons
//
// NEMA-verified: 2026a, checked 2026-10-05 — the codes offered are DICOMCore Modality.allCases: 79 == the PS3.3 2026a C.7.3.1.1.1 Defined Terms (0 wrong, 0 missing) and 18 retired terms recognised on parse; the "79" quoted here equals that count; icons are presentation

import Foundation
import DICOMCore

/// Platform-independent DICOM modality mapping utilities.
///
/// Provides SF Symbol names and full modality names for DICOM modality codes
/// without requiring SwiftUI. The set of codes comes from ``DICOMCore/Modality``,
/// which carries every PS3.3 C.7.3.1.1.1 Defined Term (2026a) — this type adds
/// only the presentation layer on top of it.
///
/// Icons are assigned per ``DICOMCore/Modality/Category`` with per-code
/// overrides where a modality is visually distinct. Hand-picking a symbol for
/// all 79 codes would be noise, and most families read better as a family.
public enum ModalityMapping: Sendable {

    /// All current modality codes, in the standard's display order.
    ///
    /// Use this as the single source of truth wherever the app offers a fixed
    /// choice of modalities (e.g. CLI Workshop dropdowns). Retired codes and
    /// the conventional non-standard codes (`SC`, `VL`) are deliberately
    /// excluded: they are recognized on parse but never offered.
    public static var allCodes: [String] { Modality.allCases.map(\.rawValue) }

    /// Current modality codes grouped by category, for sectioned pickers.
    ///
    /// A flat 79-item menu is unusable; this keeps the list navigable.
    public static var groupedCodes: [(category: String, codes: [String])] {
        Modality.groupedByCategory.map {
            ($0.category.name, $0.modalities.map(\.rawValue))
        }
    }

    /// Normalizes a raw DICOM modality code — including aliases such as `MRI`,
    /// `PET` and `RT` — to a recognized modality, or `nil` if unrecognized.
    ///
    /// Alias resolution lives in ``DICOMCore/Modality/normalized(_:)`` so the
    /// app and the library agree on what `MRI` means.
    static func normalize(_ modality: String) -> Modality? {
        Modality.normalized(modality)
    }

    /// SF Symbol name for a modality, falling back to its category's symbol.
    private static func systemImage(for modality: Modality) -> String {
        // Per-code overrides: modalities distinct enough to earn their own icon.
        switch modality {
        case .ct: return "cylinder.split.1x2"
        case .mr: return "brain.head.profile"
        case .nm: return "atom"
        case .pt: return "sparkles"
        case .us: return "waveform.path.ecg"
        case .hd: return "waveform"
        case .mg: return "rectangle.compress.vertical"
        case .rf: return "film"
        case .xa: return "heart"
        case .io: return "mouth"
        case .px: return "mouth"
        case .es: return "stethoscope"
        case .gm, .sm, .cfm: return "microbe"
        case .xc: return "camera.fill"
        case .sr: return "doc.text"
        case .pr: return "paintbrush"
        case .ko: return "key"
        case .seg: return "square.on.square.dashed"
        case .reg: return "arrow.triangle.merge"
        case .doc: return "doc.richtext"
        case .m3d: return "cube"
        case .ecg, .eps: return "waveform.path.ecg.rectangle"
        case .au: return "speaker.wave.2"
        case .sc: return "camera"
        case .vl: return "video"
        case .ot: return "questionmark.square"
        // The remaining .other defined terms: each is a real acquisition
        // technique, so each earns an icon rather than the unknown-code grid.
        case .bi: return "bolt.horizontal"          // biomagnetic imaging
        case .dg: return "light.max"                // diaphanography (transillumination)
        case .ls: return "scanner"                  // laser surface scan
        case .oss: return "scanner"                 // optical surface scan
        case .pa: return "waveform.badge.plus"      // photoacoustic
        case .tg: return "thermometer.medium"       // thermography
        default: return systemImage(for: modality.category)
        }
    }

    /// SF Symbol for a whole category — the fallback for codes without an override.
    private static func systemImage(for category: Modality.Category) -> String {
        switch category {
        case .crossSectional: return "cylinder.split.1x2"
        case .radiography: return "xray"
        case .ultrasound: return "waveform.path"
        case .visibleLight: return "camera"
        case .ophthalmic: return "eye"
        case .waveform: return "waveform"
        case .radiotherapy: return "target"
        case .derived: return "square.on.square"
        case .nonStandard: return "photo"
        case .other: return "square.grid.2x2"
        }
    }

    /// Maps DICOM modality codes to appropriate SF Symbol names.
    ///
    /// - Parameter modality: DICOM modality code (e.g. "CT", "MR").
    /// - Returns: SF Symbol name for the modality.
    public static func systemImage(for modality: String) -> String {
        guard let resolved = normalize(modality) else { return "square.grid.2x2" }
        return systemImage(for: resolved)
    }

    /// Returns the full human-readable name for a DICOM modality code.
    ///
    /// Unrecognized codes return themselves uppercased rather than "Unknown":
    /// a private code is more informative displayed than hidden.
    ///
    /// - Parameter modality: DICOM modality code (e.g. "CT", "MR").
    /// - Returns: Human-readable modality name.
    public static func fullName(for modality: String) -> String {
        normalize(modality)?.name ?? modality.uppercased()
    }

    /// The category a modality belongs to, for grouping and color/preset fallback.
    public static func category(for modality: String) -> Modality.Category {
        normalize(modality)?.category ?? .other
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// Displays an SF Symbol icon appropriate for a DICOM modality.
///
/// Usage:
/// ```swift
/// ModalityIcon(modality: "CT")
/// ModalityIcon(modality: "MR", size: 24)
/// ```
@available(macOS 14.0, iOS 17.0, *)
public struct ModalityIcon: View {
    let modality: String
    let size: CGFloat

    public init(modality: String, size: CGFloat = 16) {
        self.modality = modality.uppercased()
        self.size = size
    }

    public var body: some View {
        Image(systemName: ModalityMapping.systemImage(for: modality))
            .font(.system(size: size))
            .foregroundStyle(StudioColors.color(for: modality))
            .accessibilityLabel("\(ModalityMapping.fullName(for: modality)) modality")
    }
}
#endif
