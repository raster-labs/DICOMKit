// AboutView.swift
// DICOMStudio
//
// DICOM Studio — About screen

#if canImport(SwiftUI)
import SwiftUI

/// About screen showing DICOMKit version, licenses, and acknowledgments.
@available(macOS 14.0, iOS 17.0, *)
struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cross.case")
                .font(.system(size: 64))
                .foregroundStyle(StudioColors.primary)
                .accessibilityHidden(true)

            Text("DICOM Studio")
                .font(.system(size: StudioTypography.displaySize, weight: .bold))

            Text(versionLine)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Version \(versionLine)")

            Text("A comprehensive DICOM medical imaging application")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("DICOMKit")
                        .font(.headline)
                    Text("v\(StudioBuildInfo.dicomKitVersion)")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Platform")
                        .font(.headline)
                    Text(StudioBuildInfo.platform)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Swift")
                        .font(.headline)
                    Text(StudioBuildInfo.swiftVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .frame(width: 200)

            Text("Built with DICOMKit by Raster Lab")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("© 2026 Raster Lab. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// "Version 2.2.12 (1)" — the build number only when the bundle has one.
    private var versionLine: String {
        if let build = StudioBuildInfo.buildNumber {
            return "Version \(StudioBuildInfo.appVersion) (\(build))"
        }
        return "Version \(StudioBuildInfo.appVersion)"
    }
}
#endif
