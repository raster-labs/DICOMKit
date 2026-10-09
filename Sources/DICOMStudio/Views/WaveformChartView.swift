// WaveformChartView.swift
// DICOMStudio
//
// DICOM Studio — Waveform (ECG / hemodynamic / EP / audio) tracing display
// Reference: DICOM PS3.3 C.10.9 (Waveform Module), A.34 (Waveform IODs)
// NEMA-verified: 2026a, checked 2026-10-05 — citations checked against PS3.3 2026a section titles; carries no DICOM-standard data (the 1 mm / 5 mm grid, paper and monitor themes, and the Hz / s metadata labels are display conventions; channel data comes from DICOMKit's waveform decoder)

#if canImport(SwiftUI)
import SwiftUI
import DICOMKit

/// Renders a DICOM Waveform IOD (ECG, hemodynamic, EP, respiratory, audio) as a
/// stack of per-channel tracings on a clinical grid.
///
/// Each channel across every multiplex group is drawn in its own lane, calibrated
/// to physical units via ``WaveformMultiplexGroup/channelSamples(at:)``.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct WaveformChartView: View {
    let waveform: Waveform

    @State private var theme: WaveformTheme = .clinicalPaper

    public init(waveform: Waveform) {
        self.waveform = waveform
    }

    /// Visual presentation theme for the tracing display. The DICOM Waveform Module
    /// carries no background/color, so this is purely a viewer choice.
    enum WaveformTheme: String, CaseIterable, Identifiable {
        /// Traditional printed ECG paper: black trace on a red grid over white.
        case clinicalPaper = "Paper"
        /// Bedside patient-monitor look: green trace on a dark background.
        case monitor = "Monitor"

        var id: String { rawValue }

        var pageBackground: Color {
            switch self {
            case .clinicalPaper: return Color(white: 0.98)
            case .monitor: return .black
            }
        }
        var laneBackground: Color {
            switch self {
            case .clinicalPaper: return .white
            case .monitor: return Color(white: 0.06)
            }
        }
        var minorGrid: Color {
            switch self {
            case .clinicalPaper: return Color(red: 0.90, green: 0.45, blue: 0.45).opacity(0.5)
            case .monitor: return .pink.opacity(0.12)
            }
        }
        var majorGrid: Color {
            switch self {
            case .clinicalPaper: return Color(red: 0.85, green: 0.30, blue: 0.30).opacity(0.7)
            case .monitor: return .pink.opacity(0.25)
            }
        }
        var trace: Color {
            switch self {
            case .clinicalPaper: return .black
            case .monitor: return .green
            }
        }
        var primaryText: Color {
            switch self {
            case .clinicalPaper: return .black
            case .monitor: return .white
            }
        }
        var accentText: Color {
            switch self {
            case .clinicalPaper: return Color(red: 0.75, green: 0.15, blue: 0.15)
            case .monitor: return .green
            }
        }
    }

    /// One drawable channel lane with its precomputed calibrated samples.
    private struct Lane: Identifiable {
        let id: Int
        let label: String
        let unit: String?
        let samples: [Double]
        let samplingFrequency: Double
        let minValue: Double
        let maxValue: Double
    }

    /// Flattens every channel of every multiplex group into drawable lanes.
    private var lanes: [Lane] {
        var result: [Lane] = []
        var laneID = 0
        for group in waveform.multiplexGroups {
            for (channelIndex, channel) in group.channels.enumerated() {
                let samples = group.channelSamples(at: channelIndex)
                let minValue = samples.min() ?? 0
                let maxValue = samples.max() ?? 0
                let label = channel.channelLabel?.trimmingCharacters(in: .whitespaces).nonEmpty
                    ?? channel.channelSource?.codeMeaning.nonEmpty
                    ?? "Channel \(laneID + 1)"
                result.append(Lane(
                    id: laneID,
                    label: label,
                    unit: channel.channelSensitivityUnits?.codeMeaning,
                    samples: samples,
                    samplingFrequency: group.samplingFrequency,
                    minValue: minValue,
                    maxValue: maxValue
                ))
                laneID += 1
            }
        }
        return result
    }

    public var body: some View {
        let lanes = self.lanes
        return VStack(spacing: 0) {
            header
            Divider()
            if lanes.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Waveform Channels",
                    systemImage: "waveform.slash",
                    description: Text("This waveform object contains no readable channel data.")
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(lanes) { lane in
                            laneView(lane)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(theme.pageBackground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: WaveformHelpers.sfSymbolForSopClass(waveform.sopClassUID))
                    .foregroundStyle(theme.accentText)
                Text(waveform.waveformType.description)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                if let modality = waveform.modality?.nonEmpty {
                    Text(modality)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Theme", selection: $theme) {
                    ForEach(WaveformTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 16) {
                if let name = waveform.patientName?.nonEmpty {
                    metaLabel("Patient", name)
                }
                if let group = waveform.multiplexGroups.first {
                    metaLabel("Sampling", String(format: "%.0f Hz", group.samplingFrequency))
                    metaLabel("Duration", String(format: "%.1f s", group.duration))
                }
                metaLabel("Channels", "\(waveform.totalChannelCount)")
                if !waveform.annotations.isEmpty {
                    metaLabel("Annotations", "\(waveform.annotations.count)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.pageBackground)
    }

    private func metaLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.primaryText)
        }
    }

    // MARK: - Lane

    private func laneView(_ lane: Lane) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(lane.label)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.accentText)
                if let unit = lane.unit?.nonEmpty {
                    Text(unit)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.3g … %.3g", lane.minValue, lane.maxValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Canvas { context, size in
                drawGrid(context: context, size: size)
                drawTrace(lane: lane, context: context, size: size)
            }
            .frame(height: 90)
            .background(theme.laneBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        // Standard ECG paper: 1mm minor squares with every 5th line (5mm) bolder.
        let minor: CGFloat = 8
        let majorEvery = 5

        var minorPath = Path()
        var majorPath = Path()

        var i = 0
        var x: CGFloat = 0
        while x <= size.width {
            if i % majorEvery == 0 {
                majorPath.move(to: CGPoint(x: x, y: 0))
                majorPath.addLine(to: CGPoint(x: x, y: size.height))
            } else {
                minorPath.move(to: CGPoint(x: x, y: 0))
                minorPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            x += minor
            i += 1
        }

        i = 0
        var y: CGFloat = 0
        while y <= size.height {
            if i % majorEvery == 0 {
                majorPath.move(to: CGPoint(x: 0, y: y))
                majorPath.addLine(to: CGPoint(x: size.width, y: y))
            } else {
                minorPath.move(to: CGPoint(x: 0, y: y))
                minorPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            y += minor
            i += 1
        }

        context.stroke(minorPath, with: .color(theme.minorGrid), lineWidth: 0.5)
        context.stroke(majorPath, with: .color(theme.majorGrid), lineWidth: 0.8)

        // Baseline (mid-line)
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: size.height / 2))
        baseline.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(baseline, with: .color(theme.majorGrid), lineWidth: 0.8)
    }

    private func drawTrace(lane: Lane, context: GraphicsContext, size: CGSize) {
        let samples = lane.samples
        guard samples.count > 1 else { return }

        let range = lane.maxValue - lane.minValue
        let mid = (lane.maxValue + lane.minValue) / 2
        // Leave 10% vertical padding; guard against a flat (zero-range) signal.
        let amplitude = range > 0 ? (Double(size.height) * 0.4) / (range / 2) : 0

        let stepX = size.width / CGFloat(samples.count - 1)
        var path = Path()
        for (index, value) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let y = size.height / 2 - CGFloat((value - mid) * amplitude)
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(theme.trace), lineWidth: 1.0)
    }
}

private extension String {
    /// Returns nil when the string is empty, otherwise itself. Simplifies coalescing.
    var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
