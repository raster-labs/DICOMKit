// GeneralSettingsView.swift
// DICOMStudio
//
// DICOM Studio — General settings tab

#if canImport(SwiftUI)
import SwiftUI

/// General settings including appearance and default window presets.
@available(macOS 14.0, iOS 17.0, *)
struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $viewModel.appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .accessibilityLabel("Application theme")

                Toggle("Show Welcome on Launch", isOn: $viewModel.showWelcomeOnLaunch)
                    .accessibilityLabel("Show welcome screen when application launches")
            }

            Section("Default Window Presets") {
                // Grouped forms print a TextField's title as the row label,
                // so the field itself carries the name — no separate Text,
                // which had the row reading "Window Center  Center".
                TextField("Window Center", value: $viewModel.defaultWindowCenter, format: .number)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Default window center value")
                TextField("Window Width", value: $viewModel.defaultWindowWidth, format: .number)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Default window width value")
            }

            Section("Recent Files") {
                Stepper("Maximum Recent Files: \(viewModel.recentFilesLimit)",
                        value: $viewModel.recentFilesLimit, in: 5...50)
                    .accessibilityLabel("Maximum number of recent files: \(viewModel.recentFilesLimit)")
            }

            Section {
                Button("Reset to Defaults") {
                    viewModel.resetAllToDefaults()
                }
                .accessibilityLabel("Reset all settings to default values")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
#endif
