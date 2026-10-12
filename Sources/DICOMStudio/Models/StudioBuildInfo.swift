// StudioBuildInfo.swift
// DICOMStudio
//
// DICOM Studio — The library / platform / toolchain facts the app displays

import Foundation

/// The version facts DICOM Studio shows about itself (About screen, the
/// conformance statement header in Performance Tools).
///
/// **Keep these in step with the repository** — they are not derived at
/// build time, so every one of them goes stale silently:
///
/// - `dicomKitVersion` ← the latest `vX.Y.Z` git tag of DICOMKit
///   (`git tag --sort=-v:refname | head -1`).
/// - `platform` ← `platforms:` in `Package.swift` (`.macOS(.vNN)`), which
///   tracks the codec dependencies' deployment targets.
/// - `swiftVersion` ← the `// swift-tools-version:` line at the top of
///   `Package.swift`.
///
/// Whenever any of those three changes, update the matching constant here
/// in the same commit; nothing else in the app should hardcode them.
public enum StudioBuildInfo {
    /// DICOMKit library version, as the release tag without the leading "v".
    public static let dicomKitVersion = "2.2.12"

    /// Minimum macOS the app and library are built for.
    public static let platform = "macOS 15+"

    /// Swift language / tools version the package is built with.
    public static let swiftVersion = "6.2"

    /// The app's own version — `MARKETING_VERSION` in DICOMStudio.xcodeproj,
    /// read from the bundle at runtime so it cannot drift from the Xcode
    /// setting. Falls back to the library version when there is no app
    /// bundle (unit tests, `swift run`).
    public static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? dicomKitVersion
    }

    /// Build number — `CURRENT_PROJECT_VERSION` in DICOMStudio.xcodeproj.
    public static var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}
