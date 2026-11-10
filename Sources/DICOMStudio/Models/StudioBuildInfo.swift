// StudioBuildInfo.swift
// DICOMStudio
//
// DICOM Studio — The library / platform / toolchain facts the app displays

import Foundation
import DICOMKit

/// The version facts DICOM Studio shows about itself (About screen, the
/// conformance statement header in Performance Tools).
///
/// **Keep these in step with the repository** — `dicomKitVersion` reads
/// `DICOMKit.version` directly, while the platform and toolchain strings track
/// `Package.swift`:
///
/// - `dicomKitVersion` ← `DICOMKit.version` (matches the latest `vX.Y.Z` tag).
/// - `platform` ← `platforms:` in `Package.swift` (`.macOS(.v26)`, `.iOS(.v26)`),
///   which tracks the codec dependencies' deployment targets.
/// - `swiftVersion` ← the `// swift-tools-version:` line at the top of
///   `Package.swift`.
///
/// Whenever `Package.swift` changes those floors, update the matching constant
/// here in the same commit; nothing else in the app should hardcode them.
public enum StudioBuildInfo {
    /// DICOMKit library version, sourced directly from `DICOMKit.version`.
    public static let dicomKitVersion = DICOMKit.version

    /// Minimum Apple OS platforms the app and library target.
    public static let platform = "macOS 26+ / iOS 26+"

    /// Swift language / tools version the package is built with.
    public static let swiftVersion = "6.4"

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
