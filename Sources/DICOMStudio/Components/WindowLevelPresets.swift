// WindowLevelPresets.swift
// DICOMStudio
//
// DICOM Studio — Window/level preset definitions for common modalities
//
// NEMA-verified: 2026a, checked 2026-10-05 — the preset centres and widths claim nothing standard-defined (clinical conventions in the units the Modality LUT puts out: HU on CT, PS3.3 2026a C.11.1.1.2, UCUM [hnsf'U]; stored values on 12-bit projection detectors); the 15 modality codes the lists are keyed by (CT, MR, CR, DX, RG, PX, IO, BMD, MG, PT, NM, XA, RF, IVUS, OPT and the OCT family) are PS3.3 2026a C.7.3.1.1.1 Defined Terms resolved through DICOMCore Modality; a preset is a LINEAR window (C.11.2.1.2.1) and every width is ≥ 1; checked by Scripts/diff_studio_g2_viewer.py

import Foundation
import DICOMCore

/// A single window/level preset with descriptive metadata.
public struct WindowLevelPreset: Sendable, Equatable, Identifiable, Hashable {
    /// Unique identifier.
    ///
    /// Includes the modality: preset *names* repeat across modalities ("Bone"
    /// is a CT, CR and DX preset), so a name alone is not an identity. A list
    /// spanning modalities — the print screen's preset menu — fed duplicate
    /// IDs to `ForEach`, and SwiftUI wired rows to the wrong actions.
    public var id: String { "\(modality)/\(name)" }

    /// Display name for the preset (e.g., "Bone", "Lung").
    public let name: String

    /// Window center (level) value.
    public let center: Double

    /// Window width value.
    public let width: Double

    /// Modality this preset is intended for (e.g., "CT", "MR").
    public let modality: String

    /// Creates a new preset.
    public init(name: String, center: Double, width: Double, modality: String) {
        self.name = name
        self.center = center
        self.width = width
        self.modality = modality
    }
}

/// Platform-independent window/level preset definitions for common DICOM modalities.
///
/// Provides standard presets for CT, MR, and other modalities per DICOM PS3.3 C.11.2.1.2.
public enum WindowLevelPresets: Sendable {

    // MARK: - CT Presets

    /// Standard CT presets for various tissue types.
    /// Reference: Standard clinical window/level settings per radiological practice.
    public static let ctPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Abdomen", center: 40, width: 400, modality: "CT"),
        WindowLevelPreset(name: "Bone", center: 300, width: 1500, modality: "CT"),
        WindowLevelPreset(name: "Brain", center: 40, width: 80, modality: "CT"),
        // Chest soft tissue uses the same W/L as Abdomen per standard clinical convention
        WindowLevelPreset(name: "Chest", center: 40, width: 400, modality: "CT"),
        WindowLevelPreset(name: "Lung", center: -600, width: 1500, modality: "CT"),
        WindowLevelPreset(name: "Liver", center: 60, width: 150, modality: "CT"),
        WindowLevelPreset(name: "Mediastinum", center: 50, width: 350, modality: "CT"),
        WindowLevelPreset(name: "Stroke", center: 40, width: 40, modality: "CT"),
    ]

    // MARK: - MR Presets

    /// Standard MR presets for common sequence types.
    public static let mrPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "T1", center: 500, width: 1000, modality: "MR"),
        WindowLevelPreset(name: "T2", center: 400, width: 800, modality: "MR"),
        WindowLevelPreset(name: "FLAIR", center: 600, width: 1200, modality: "MR"),
    ]

    // MARK: - Projection Radiography Presets

    /// CR/DX presets, in raw stored-value terms of a typical 12-bit detector.
    ///
    /// Projection images vary far more between detectors than CT does between
    /// scanners; these are starting points around the common 12-bit midpoint,
    /// not gospel — the header's own VOI (which the print path already prefers
    /// when it exists) is always the better default.
    public static let crPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Chest", center: 2048, width: 4096, modality: "CR"),
        WindowLevelPreset(name: "Bone", center: 2048, width: 2048, modality: "CR"),
        WindowLevelPreset(name: "Soft Tissue", center: 1650, width: 2800, modality: "CR"),
    ]

    /// DX shares CR's detector conventions.
    public static let dxPresets: [WindowLevelPreset] = crPresets.map {
        WindowLevelPreset(name: $0.name, center: $0.center, width: $0.width, modality: "DX")
    }

    /// Mammography: high-contrast windows on a 12-bit scale.
    public static let mgPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 2048, width: 4096, modality: "MG"),
        WindowLevelPreset(name: "High Contrast", center: 2048, width: 2048, modality: "MG"),
    ]

    /// PET, in SUV-shaped terms: an inverted-gray 0–5 / 0–10 SUV display is
    /// the common reading default.
    public static let ptPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "SUV 0–5", center: 2.5, width: 5, modality: "PT"),
        WindowLevelPreset(name: "SUV 0–10", center: 5, width: 10, modality: "PT"),
    ]

    /// Nuclear medicine planar/SPECT counts.
    public static let nmPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 128, width: 256, modality: "NM"),
        WindowLevelPreset(name: "High Count", center: 50, width: 100, modality: "NM"),
    ]

    /// Angiography (8-bit display-ready frames are the norm).
    public static let xaPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 128, width: 256, modality: "XA"),
        WindowLevelPreset(name: "Subtracted", center: 128, width: 180, modality: "XA"),
    ]

    /// Conventional radiography (film/screen equivalent), same latitude as CR.
    public static let rgPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 2048, width: 4096, modality: "RG"),
        WindowLevelPreset(name: "Bone", center: 2048, width: 2500, modality: "RG"),
        WindowLevelPreset(name: "Soft Tissue", center: 1800, width: 3000, modality: "RG"),
    ]

    /// Panoramic dental X-ray.
    public static let pxPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 2048, width: 4096, modality: "PX"),
        WindowLevelPreset(name: "Bone", center: 2048, width: 2500, modality: "PX"),
    ]

    /// Intra-oral dental radiography.
    public static let ioPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 2048, width: 4096, modality: "IO"),
        WindowLevelPreset(name: "Bone", center: 2048, width: 2500, modality: "IO"),
    ]

    /// Bone densitometry (X-ray).
    public static let bmdPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 2048, width: 4096, modality: "BMD"),
    ]

    /// Intravascular ultrasound — 8-bit, but benefits from a contrast option.
    public static let ivusPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 128, width: 256, modality: "IVUS"),
        WindowLevelPreset(name: "High Contrast", center: 128, width: 160, modality: "IVUS"),
    ]

    /// Optical coherence tomography (ophthalmic and intravascular).
    public static let octPresets: [WindowLevelPreset] = [
        WindowLevelPreset(name: "Standard", center: 128, width: 256, modality: "OPT"),
        WindowLevelPreset(name: "High Contrast", center: 128, width: 160, modality: "OPT"),
    ]

    // MARK: - Lookup

    /// Returns the preset list for the given modality.
    ///
    /// Presets are deliberately curated, not exhaustive. Display-ready
    /// modalities (US, ES, GM, SM, XC, DMS…) have no entry: their frames are
    /// 8-bit and already windowed, so a fixed window would be an invented
    /// number rather than a clinical one. The same reasoning excludes the
    /// non-image codes (SR, PR, KO, SEG, DOC…), which have no pixels to window.
    ///
    /// - Parameter modality: DICOM modality code (e.g., "CT", "MR").
    /// - Returns: Array of presets, empty if no presets are defined for the modality.
    public static func presets(for modality: String) -> [WindowLevelPreset] {
        guard let resolved = Modality.normalized(modality) else { return [] }
        switch resolved {
        case .ct:    return ctPresets
        case .mr:    return mrPresets
        case .cr:    return crPresets
        case .dx:    return dxPresets
        case .rg:    return rgPresets
        case .px:    return pxPresets
        case .io:    return ioPresets
        case .bmd:   return bmdPresets
        case .mg:    return mgPresets
        case .pt:    return ptPresets
        case .nm:    return nmPresets
        case .xa, .rf: return xaPresets
        case .ivus:  return ivusPresets
        case .opt, .oct, .ivoct, .optenf, .optbsv: return octPresets
        default:     return []
        }
    }

    /// Returns all available presets across all modalities.
    public static var allPresets: [WindowLevelPreset] {
        presetsByModality.flatMap { $0.presets }
    }

    /// Every preset list, grouped and labelled by modality — for menus that
    /// span modalities and want a submenu per modality rather than one long
    /// run of prefixed names.
    public static let presetsByModality: [(modality: String, presets: [WindowLevelPreset])] = [
        ("CT", ctPresets), ("MR", mrPresets), ("CR", crPresets), ("DX", dxPresets),
        ("RG", rgPresets), ("PX", pxPresets), ("IO", ioPresets), ("BMD", bmdPresets),
        ("MG", mgPresets), ("PT", ptPresets), ("NM", nmPresets), ("XA", xaPresets),
        ("IVUS", ivusPresets), ("OPT", octPresets),
    ]

    /// Finds a preset by name and modality.
    ///
    /// - Parameters:
    ///   - name: Preset name (case-insensitive).
    ///   - modality: DICOM modality code.
    /// - Returns: The matching preset, or nil.
    public static func preset(named name: String, modality: String) -> WindowLevelPreset? {
        presets(for: modality).first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Returns a default preset for the given modality (the first in the list).
    ///
    /// - Parameter modality: DICOM modality code.
    /// - Returns: The first preset for that modality, or nil.
    public static func defaultPreset(for modality: String) -> WindowLevelPreset? {
        presets(for: modality).first
    }
}
