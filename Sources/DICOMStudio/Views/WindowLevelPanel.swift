// WindowLevelPanel.swift
// DICOMStudio
//
// DICOM Studio — Window/level controls panel
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data: the slider ranges (centre −1024…3072, width 1…4096) and ±10/±100 steps are UI conveniences in the viewer's stored-pixel units; the width floor of 1 is the LINEAR minimum (PS3.3 2026a C.11.2.1.2.1); presets and header windows come from WindowLevelPresets and DICOMKit

#if canImport(SwiftUI)
import SwiftUI

/// Panel for adjusting window center/width (window/level) settings.
///
/// Provides numeric inputs, preset buttons, and header-based auto settings.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct WindowLevelPanel: View {
    @Bindable var viewModel: ImageViewerViewModel

    public init(viewModel: ImageViewerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Label("Window / Level", systemImage: "slider.horizontal.3")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            // Numeric inputs + sliders + step buttons
            VStack(alignment: .leading, spacing: 8) {
                // Center
                Text("Center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Center",
                    value: Bindable(viewModel).windowCenter,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Window center value")
                .onSubmit { viewModel.renderCurrentFrame() }

                Slider(value: Bindable(viewModel).windowCenter, in: -1024...3072, step: 1)
                    .onChange(of: viewModel.windowCenter) { _, _ in viewModel.renderCurrentFrame() }
                    .accessibilityLabel("Window center slider")

                HStack(spacing: 4) {
                    ForEach([-100, -10, 10, 100], id: \.self) { step in
                        Button(step > 0 ? "+\(step)" : "\(step)") {
                            viewModel.windowCenter += Double(step)
                            viewModel.renderCurrentFrame()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("\(step > 0 ? "Increase" : "Decrease") center by \(abs(step))")
                    }
                }

                Divider()

                // Width
                Text("Width")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Width",
                    value: Bindable(viewModel).windowWidth,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Window width value")
                .onSubmit { viewModel.renderCurrentFrame() }

                Slider(value: Bindable(viewModel).windowWidth, in: 1...4096, step: 1)
                    .onChange(of: viewModel.windowWidth) { _, _ in viewModel.renderCurrentFrame() }
                    .accessibilityLabel("Window width slider")

                HStack(spacing: 4) {
                    ForEach([-100, -10, 10, 100], id: \.self) { step in
                        Button(step > 0 ? "+\(step)" : "\(step)") {
                            viewModel.windowWidth = max(1, viewModel.windowWidth + Double(step))
                            viewModel.renderCurrentFrame()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("\(step > 0 ? "Increase" : "Decrease") width by \(abs(step))")
                    }
                }
            }

            // Current W/L display
            Text(viewModel.windowLevelText)
                .font(.system(size: StudioTypography.monoSize, design: .monospaced))
                .foregroundStyle(.secondary)

            // Auto button from header
            if !viewModel.headerWindowSettings.isEmpty {
                Button("Auto (from header)") {
                    viewModel.autoWindowLevel()
                }
                .accessibilityLabel("Auto-adjust window/level from DICOM header")
            }

            // Presets
            if !viewModel.availablePresets.isEmpty {
                Divider()
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                FlowLayout(spacing: 6) {
                    ForEach(viewModel.availablePresets) { preset in
                        Button(preset.name) {
                            viewModel.applyPreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("\(preset.name) preset")
                        .accessibilityHint("Sets window center to \(Int(preset.center)) and width to \(Int(preset.width))")
                    }
                }
            }

            // Header window settings
            if viewModel.headerWindowSettings.count > 1 {
                Divider()
                Text("Header Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(viewModel.headerWindowSettings.enumerated()), id: \.offset) { index, settings in
                    Button {
                        viewModel.applyWindowSettings(settings)
                    } label: {
                        HStack {
                            Text(settings.explanation ?? "Window \(index + 1)")
                            Spacer()
                            Text("C:\(Int(settings.center)) W:\(Int(settings.width))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.explanation ?? "Window setting \(index + 1)")
                }
            }

            // Inversion toggle
            if viewModel.isMonochrome {
                Divider()
                Toggle("Invert Grayscale", isOn: Binding(
                    get: { viewModel.isInverted },
                    set: { _ in viewModel.toggleInversion() }
                ))
                .accessibilityLabel("Invert grayscale")
            }
        }
        .padding()
    }
}

/// Simple flow layout for preset buttons.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), offsets)
    }
}
#endif
