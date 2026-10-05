// HangingProtocolPanel.swift
// DICOMStudio
//
// DICOM Studio — SwiftUI panel for hanging protocol selection and editing
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (UI state and layout only)

import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Panel for selecting and editing hanging protocols.
///
/// Displays available protocols, current layout, and provides
/// controls for creating user-defined protocols.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct HangingProtocolPanel: View {

    /// The hanging protocol ViewModel.
    @Bindable public var viewModel: HangingProtocolViewModel

    /// Creates a hanging protocol panel.
    public init(viewModel: HangingProtocolViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Hanging Protocols")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.startNewProtocol() }) {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Create new hanging protocol")
            }

            // Current layout info
            HStack {
                Image(systemName: HangingProtocolHelpers.layoutSystemImage(for: viewModel.currentLayout))
                Text(viewModel.layoutDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Layout presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LayoutType.allCases, id: \.self) { layout in
                        Button(action: { viewModel.setLayout(layout) }) {
                            VStack(spacing: 4) {
                                Image(systemName: HangingProtocolHelpers.layoutSystemImage(for: layout))
                                    .font(.title3)
                                Text(HangingProtocolHelpers.layoutLabel(for: layout))
                                    .font(.caption2)
                            }
                            .padding(6)
                            .background(
                                viewModel.currentLayout == layout ? Color.accentColor.opacity(0.2) : Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(HangingProtocolHelpers.layoutLabel(for: layout)) layout")
                    }
                }
            }

            // Available protocols list
            if !viewModel.allProtocols.isEmpty {
                Divider()
                Text("Available Protocols")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.allProtocols) { proto in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(proto.name)
                                .font(.body)
                            if let desc = proto.protocolDescription {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if proto.isUserDefined {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if viewModel.activeProtocol?.id == proto.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.applyProtocol(proto)
                    }
                    .accessibilityLabel("\(proto.name) hanging protocol")
                    .accessibilityAddTraits(viewModel.activeProtocol?.id == proto.id ? .isSelected : [])
                }
            }
        }
        .padding()
    }
}
#endif
