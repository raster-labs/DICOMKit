// WaveformHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent ECG and hemodynamic waveform display helpers
// Reference: DICOM PS3.3 C.10.9 (Waveform Module), A.34 (Waveform IODs); PS3.6 Table A-1 (Waveform Storage SOP Classes)
// NEMA-verified: 2026a, checked 2026-10-05 — the 16 Waveform Storage SOP Class UID suffixes and display names diffed by script against PS3.6 2026a Table A-1 (names are the A-1 name minus " Waveform Storage": 16/16; 7 were missing and 3 were abbreviated differently: "12-lead ECG", "Cardiac Electrophysiology", "Basic Voice Audio"); lead labels, grid, heart-rate and sample arithmetic carry no DICOM-defined values (25 mm/s and 10 mm/mV are ECG paper conventions)

import Foundation

/// Platform-independent helpers for waveform (ECG, hemodynamic, audio) display.
public enum WaveformHelpers: Sendable {

    // MARK: - Channel Labels

    /// Standard 12-lead ECG channel labels in clinical order.
    public static func standardECGLeadLabels() -> [String] {
        ["I", "II", "III", "aVR", "aVL", "aVF", "V1", "V2", "V3", "V4", "V5", "V6"]
    }

    /// Common hemodynamic monitoring channel labels.
    public static func hemodynamicChannelLabels() -> [String] {
        ["Art BP", "CVP", "PAP", "PCWP", "ECG", "SpO2", "Resp"]
    }

    // MARK: - SOP Class Display

    /// Waveform category of a Storage SOP Class, used for symbols and short descriptions.
    enum WaveformCategory: String {
        case ecg = "ECG", hemodynamic = "Hemodynamic", electrophysiology = "Electrophysiology", audio = "Audio",
             arterialPulse = "Arterial Pulse", respiratory = "Respiratory", neurophysiology = "Neurophysiology",
             bodyPosition = "Body Position"
    }

    /// The Waveform Storage SOP Classes of PS3.6 Table A-1 under 1.2.840.10008.5.1.4.1.1.9:
    /// (UID, display name = the Table A-1 name without " Waveform Storage", category).
    static let waveformSOPClasses: [(uid: String, name: String, category: WaveformCategory)] = [
        ("1.2.840.10008.5.1.4.1.1.9.1.1", "12-lead ECG", .ecg),
        ("1.2.840.10008.5.1.4.1.1.9.1.2", "General ECG", .ecg),
        ("1.2.840.10008.5.1.4.1.1.9.1.3", "Ambulatory ECG", .ecg),
        ("1.2.840.10008.5.1.4.1.1.9.1.4", "General 32-bit ECG", .ecg),
        ("1.2.840.10008.5.1.4.1.1.9.2.1", "Hemodynamic", .hemodynamic),
        ("1.2.840.10008.5.1.4.1.1.9.3.1", "Cardiac Electrophysiology", .electrophysiology),
        ("1.2.840.10008.5.1.4.1.1.9.4.1", "Basic Voice Audio", .audio),
        ("1.2.840.10008.5.1.4.1.1.9.4.2", "General Audio", .audio),
        ("1.2.840.10008.5.1.4.1.1.9.5.1", "Arterial Pulse", .arterialPulse),
        ("1.2.840.10008.5.1.4.1.1.9.6.1", "Respiratory", .respiratory),
        ("1.2.840.10008.5.1.4.1.1.9.6.2", "Multi-channel Respiratory", .respiratory),
        ("1.2.840.10008.5.1.4.1.1.9.7.1", "Routine Scalp Electroencephalogram", .neurophysiology),
        ("1.2.840.10008.5.1.4.1.1.9.7.2", "Electromyogram", .neurophysiology),
        ("1.2.840.10008.5.1.4.1.1.9.7.3", "Electrooculogram", .neurophysiology),
        ("1.2.840.10008.5.1.4.1.1.9.7.4", "Sleep Electroencephalogram", .neurophysiology),
        ("1.2.840.10008.5.1.4.1.1.9.8.1", "Body Position", .bodyPosition),
    ]

    /// The Table A-1 row for a Waveform Storage SOP Class UID (exact match, or a match on the UID
    /// tail after the "1.2.840.10008.5.1.4.1.1." prefix so abbreviated callers keep working).
    static func waveformSOPClass(_ sopClassUID: String) -> (uid: String, name: String, category: WaveformCategory)? {
        let uid = sopClassUID.replacingOccurrences(of: "\u{200B}", with: "").trimmingCharacters(in: .whitespaces)
        if let exact = waveformSOPClasses.first(where: { $0.uid == uid }) { return exact }
        return waveformSOPClasses.first { uid.hasSuffix("." + $0.uid.dropFirst("1.2.840.10008.5.1.4.1.1.".count)) }
    }

    /// Returns an SF Symbol name appropriate for the given Waveform SOP Class UID.
    public static func sfSymbolForSopClass(_ sopClassUID: String) -> String {
        switch waveformSOPClass(sopClassUID)?.category {
        case .ecg, .electrophysiology: return "waveform.ecg"
        case .hemodynamic, .arterialPulse: return "heart"
        case .audio: return "waveform"
        case .respiratory: return "lungs"
        case .neurophysiology: return "brain.head.profile"
        case .bodyPosition: return "figure.stand"
        case nil: return "waveform"
        }
    }

    /// Returns a human-readable display name for a known Waveform SOP Class UID: the PS3.6
    /// Table A-1 name without its " Waveform Storage" suffix (e.g. "12-lead ECG"), or "Waveform".
    public static func displayNameForSopClass(_ sopClassUID: String) -> String {
        waveformSOPClass(sopClassUID)?.name ?? "Waveform"
    }

    // MARK: - Grid

    /// Calculates the number of major grid lines for the given time range and paper speed.
    ///
    /// Standard ECG grid: 25 mm per second at 25 mm/s.
    public static func gridLineCount(timeRangeSeconds: Double, paperSpeed: Double) -> Int {
        Int(timeRangeSeconds * paperSpeed / 25.0) + 1
    }

    // MARK: - Formatting

    /// Formats a duration in milliseconds for display.
    ///
    /// Values below 1000 ms are shown as `"X ms"`; ≥1000 ms as `"X.X s"`.
    public static func formatDuration(_ ms: Double) -> String {
        if ms < 1000.0 {
            return String(format: "%.0f ms", ms)
        }
        return String(format: "%.1f s", ms / 1000.0)
    }

    // MARK: - Heart Rate

    /// Calculates heart rate in beats per minute from an RR interval in milliseconds.
    public static func calculateHeartRate(rrIntervalMs: Double) -> Double {
        guard rrIntervalMs > 0 else { return 0 }
        return 60000.0 / rrIntervalMs
    }

    // MARK: - Sample / Time Conversion

    /// Converts a sample index to a time position in seconds.
    public static func sampleToTime(sampleIndex: Int, samplingFrequency: Double) -> Double {
        guard samplingFrequency > 0 else { return 0 }
        return Double(sampleIndex) / samplingFrequency
    }

    /// Normalizes a waveform sample value to [0, 1], clamping outside the range.
    public static func normalizedSample(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0.0 }
        return Swift.min(Swift.max((value - min) / (max - min), 0.0), 1.0)
    }

    // MARK: - Type Description

    /// Returns a brief waveform category string for the given SOP Class UID.
    public static func waveformTypeDescription(sopClassUID: String) -> String {
        waveformSOPClass(sopClassUID)?.category.rawValue ?? "Waveform"
    }
}
