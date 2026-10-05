// CLIShellFoundationHelpers.swift
// DICOMStudio
//
// DICOM Studio — Helpers for CLI Shell Foundation (Milestone 17)
// NEMA-verified: 2026a, checked 2026-10-05 — the 42 allToolNames and toolDescription rows diffed against the Sources/dicom-* targets and their ArgumentParser abstracts (4 tools added, dicom-tags / dicom-image / dicom-wado descriptions corrected to what the tools do); the DIMSE names in the descriptions (C-ECHO, C-FIND, C-STORE, C-MOVE, C-GET) are PS3.7 2026a 9.1.1-9.1.5 services, WADO-RS / QIDO-RS / STOW-RS / UPS-RS are PS3.18 2026a service names, Modality Worklist / Modality Performed Procedure Step are PS3.4 2026a Annex K / F.7 SOP Classes; no port, AE title or UID is carried (version and GitHub plumbing otherwise)

import Foundation

// MARK: - Tool Registry Helpers

/// Helpers for managing the CLI tool registry, discovery, and categorization.
public enum ToolRegistryHelpers: Sendable {

  /// Default search paths used when discovering CLI tools on the filesystem.
  public static let defaultSearchPaths: [ToolSearchPath] = [
    .dicomStudioTools,
    .usrLocalBin,
    .homeLocalBin,
    .homebrewPrefix,
    .systemPath
  ]

  /// Names of every shipped `dicom-*` CLI tool (42 total, one per `Sources/dicom-*` target).
  public static let allToolNames: [String] = [
    // Networking (13)
    "dicom-echo", "dicom-query", "dicom-send", "dicom-retrieve",
    "dicom-qr", "dicom-wado", "dicom-mwl", "dicom-mpps",
    "dicom-print", "dicom-printscp", "dicom-jpip", "dicom-gateway", "dicom-server",
    // Viewer & Imaging (3)
    "dicom-viewer", "dicom-image", "dicom-3d",
    // File Inspection (4)
    "dicom-info", "dicom-dump", "dicom-tags", "dicom-diff",
    // File Processing (5)
    "dicom-convert", "dicom-validate", "dicom-anon", "dicom-compress", "dicom-j2k",
    // File Organization (4)
    "dicom-split", "dicom-merge", "dicom-dcmdir", "dicom-archive",
    // Data Exchange (6)
    "dicom-json", "dicom-xml", "dicom-pdf", "dicom-export", "dicom-pixedit", "dicom-video",
    // Clinical (3)
    "dicom-report", "dicom-measure", "dicom-study",
    // Utilities (2)
    "dicom-uid", "dicom-script",
    // Cloud & AI (2)
    "dicom-cloud", "dicom-ai"
  ]

  /// Total number of CLI tools shipped with DICOMKit.
  public static let totalToolCount: Int = 42

  /// Creates a default `ToolInfo` entry for a tool that has not yet been discovered.
  public static func defaultToolInfo(name: String, category: ToolCategory) -> ToolInfo {
    ToolInfo(
      name: name,
      displayName: toolDisplayName(for: name),
      path: "",
      version: "",
      category: category,
      availability: .unavailable,
      toolDescription: toolDescription(for: name)
    )
  }

  /// Returns the full set of 42 default `ToolInfo` entries, one per tool name.
  public static func allDefaultTools() -> [ToolInfo] {
    allToolNames.map { name in
      defaultToolInfo(name: name, category: toolCategory(for: name))
    }
  }

  /// Maps a `dicom-*` tool name to its `ToolCategory`.
  public static func toolCategory(for toolName: String) -> ToolCategory {
    for category in ToolCategory.allCases where category.toolNames.contains(toolName) {
      return category
    }
    return .utilities
  }

  /// Derives a short display name from a `dicom-*` binary name.
  ///
  /// `"dicom-echo"` → `"Echo"`, `"dicom-3d"` → `"3D"`.
  public static func toolDisplayName(for toolName: String) -> String {
    let suffix = toolName.hasPrefix("dicom-")
      ? String(toolName.dropFirst(6))
      : toolName

    if suffix == "3d" { return "3D" }
    if suffix == "j2k" { return "J2K" }
    if suffix == "jpip" { return "JPIP" }
    if suffix == "printscp" { return "Print SCP" }
    if suffix == "ai" { return "AI" }
    if suffix == "qr" { return "QR" }
    if suffix == "uid" { return "UID" }
    if suffix == "xml" { return "XML" }
    if suffix == "json" { return "JSON" }
    if suffix == "pdf" { return "PDF" }
    if suffix == "mwl" { return "MWL" }
    if suffix == "mpps" { return "MPPS" }
    if suffix == "wado" { return "WADO" }
    if suffix == "dcmdir" { return "DCMDIR" }
    if suffix == "pixedit" { return "PixEdit" }

    // Default: capitalise the first letter.
    return suffix.prefix(1).uppercased() + suffix.dropFirst()
  }

  /// Returns a brief, human-readable description for a given tool.
  public static func toolDescription(for toolName: String) -> String {
    switch toolName {
    // Networking
    case "dicom-echo":     return "DICOM echo verification (C-ECHO)"
    case "dicom-query":    return "Query DICOM servers (C-FIND)"
    case "dicom-send":     return "Send DICOM files to servers (C-STORE)"
    case "dicom-retrieve": return "Retrieve from PACS (C-MOVE/C-GET)"
    case "dicom-qr":      return "Combined query and retrieve operations"
    case "dicom-wado":     return "DICOMweb client (WADO-RS, QIDO-RS, STOW-RS, UPS-RS)"
    case "dicom-mwl":      return "Modality Worklist management"
    case "dicom-mpps":     return "Modality Performed Procedure Step"
    case "dicom-print":    return "DICOM print management (Print SCU)"
    case "dicom-printscp": return "DICOM Print SCP (printer emulator)"
    case "dicom-jpip":     return "JPIP (JPEG 2000 Interactive Protocol) streaming"
    case "dicom-gateway":  return "DICOM gateway and proxy service"
    case "dicom-server":   return "DICOM SCP server"

    // Viewer & Imaging
    case "dicom-viewer":   return "Terminal-based DICOM viewing"
    case "dicom-image":    return "Convert standard images to DICOM Secondary Capture"
    case "dicom-3d":       return "3D volume rendering"

    // File Inspection
    case "dicom-info":     return "Display DICOM file metadata"
    case "dicom-dump":     return "Hexadecimal dump with DICOM structure"
    case "dicom-tags":     return "Add, modify, and delete tags in DICOM files"
    case "dicom-diff":     return "Compare DICOM files"

    // File Processing
    case "dicom-convert":  return "Transfer syntax conversion and image export"
    case "dicom-validate": return "DICOM conformance validation"
    case "dicom-anon":     return "DICOM file anonymization"
    case "dicom-compress": return "DICOM compression operations"
    case "dicom-j2k":      return "JPEG 2000 / HTJ2K codestream operations"

    // File Organization
    case "dicom-split":    return "Split multi-frame DICOM files"
    case "dicom-merge":    return "Merge DICOM files into multi-frame"
    case "dicom-dcmdir":   return "DICOMDIR directory file management"
    case "dicom-archive":  return "DICOM archive packaging"

    // Data Exchange
    case "dicom-json":     return "DICOM to/from JSON conversion"
    case "dicom-xml":      return "DICOM to/from XML conversion"
    case "dicom-pdf":      return "Encapsulated PDF operations"
    case "dicom-export":   return "Export DICOM data to external formats"
    case "dicom-pixedit":  return "Pixel data editing and manipulation"
    case "dicom-video":    return "Video to and from DICOM Video IODs"

    // Clinical
    case "dicom-report":   return "Structured report operations"
    case "dicom-measure":  return "Measurement extraction"
    case "dicom-study":    return "Study-level operations"

    // Utilities
    case "dicom-uid":      return "UID generation and lookup"
    case "dicom-script":   return "DICOM scripting engine"

    // Cloud & AI
    case "dicom-cloud":    return "Cloud storage integration"
    case "dicom-ai":       return "AI inference and analysis"

    default:               return "DICOM command-line tool"
    }
  }

  /// Filters a list of tools by a case-insensitive search query matching name or description.
  public static func filterTools(_ tools: [ToolInfo], query: String) -> [ToolInfo] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return tools }
    let lower = trimmed.lowercased()
    return tools.filter { tool in
      tool.name.lowercased().contains(lower)
        || tool.displayName.lowercased().contains(lower)
        || tool.toolDescription.lowercased().contains(lower)
    }
  }

  /// Groups tools by their category, preserving the `ToolCategory.allCases` order.
  public static func toolsByCategory(
    _ tools: [ToolInfo]
  ) -> [(category: ToolCategory, tools: [ToolInfo])] {
    var grouped: [ToolCategory: [ToolInfo]] = [:]
    for tool in tools {
      grouped[tool.category, default: []].append(tool)
    }
    return ToolCategory.allCases.compactMap { cat in
      guard let items = grouped[cat], !items.isEmpty else { return nil }
      return (category: cat, tools: items)
    }
  }
}

// MARK: - Version Helpers

/// Helpers for semantic versioning, compatibility checks, and version reports.
public enum VersionHelpers: Sendable {

  /// The current DICOM Studio version.
  public static let currentStudioVersion = SemanticVersion(major: 2, minor: 0, patch: 0)

  /// Checks the compatibility between a tool version and the studio version.
  public static func checkCompatibility(
    tool: SemanticVersion,
    studio: SemanticVersion
  ) -> VersionCompatibility {
    if tool.major != studio.major {
      return .incompatibleMajor
    }
    if tool.minor != studio.minor {
      return .incompatibleMinor
    }
    return .compatible
  }

  /// Generates a `VersionReport` for the given set of tools.
  public static func generateVersionReport(
    tools: [ToolInfo],
    studioVersion: SemanticVersion
  ) -> VersionReport {
    let entries: [ToolVersionEntry] = tools.map { tool in
      let installed = SemanticVersion(parsing: tool.version)
      let compat: VersionCompatibility
      if tool.availability == .unavailable || tool.version.isEmpty {
        compat = .missingTool
      } else if let ver = installed {
        compat = checkCompatibility(tool: ver, studio: studioVersion)
      } else {
        compat = .unknownVersion
      }
      return ToolVersionEntry(
        toolName: tool.name,
        installedVersion: installed,
        expectedVersion: studioVersion,
        compatibility: compat
      )
    }
    return VersionReport(studioVersion: studioVersion, toolReports: entries)
  }

  /// Formats a `SemanticVersion` as `"vMAJOR.MINOR.PATCH"`.
  public static func formatVersionString(_ version: SemanticVersion) -> String {
    "v\(version.major).\(version.minor).\(version.patch)"
  }

  /// Attempts to parse a version from CLI output such as `"dicom-echo version 2.0.0"`.
  public static func parseVersionOutput(_ output: String) -> SemanticVersion? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

    // Match "version X.Y.Z" anywhere in the string.
    if let range = trimmed.range(
      of: #"(\d+)\.(\d+)\.(\d+)"#,
      options: .regularExpression
    ) {
      return SemanticVersion(parsing: String(trimmed[range]))
    }
    return nil
  }

  /// Returns a one-line summary of a version report.
  public static func versionSummary(for report: VersionReport) -> String {
    let total = report.toolReports.count
    let ok = report.compatibleCount
    let bad = report.incompatibleCount
    let missing = report.missingCount

    if total == 0 { return "No tools found" }
    if ok == total { return "All \(total) tools compatible" }

    var parts: [String] = ["\(ok)/\(total) compatible"]
    if bad > 0 { parts.append("\(bad) incompatible") }
    if missing > 0 { parts.append("\(missing) missing") }
    return parts.joined(separator: ", ")
  }
}

// MARK: - GitHub Release Helpers

/// Helpers for interacting with the GitHub Releases API.
public enum GitHubReleaseHelpers: Sendable {

  /// GitHub repository owner.
  public static let repoOwner: String = "Raster-Lab"

  /// GitHub repository name.
  public static let repoName: String = "DICOMKit"

  /// Base URL for the GitHub REST API.
  public static let apiBaseURL: String = "https://api.github.com"

  /// URL for the latest release endpoint.
  public static var latestReleaseURL: String {
    "\(apiBaseURL)/repos/\(repoOwner)/\(repoName)/releases/latest"
  }

  /// User-Agent header sent with API requests.
  public static let userAgent: String = "DICOMStudio/2.0.0"

  /// Builds the API URL for a release identified by its tag.
  public static func releaseURL(for tag: String) -> String {
    "\(apiBaseURL)/repos/\(repoOwner)/\(repoName)/releases/tags/\(tag)"
  }

  /// Attempts to parse `ReleaseInfo` from GitHub API JSON data.
  ///
  /// > Note: This is a simplified stub. A production implementation would use
  /// > `JSONDecoder` with a custom `CodingKeys` mapping.
  public static func parseReleaseJSON(_ data: Data) -> ReleaseInfo? {
    // Stub – full implementation requires JSONDecoder with GitHub schema mapping.
    nil
  }

  /// Formats a byte count into a human-readable string (e.g. `"14.2 MB"`).
  public static func formatAssetSize(_ bytes: Int64) -> String {
    if bytes < 1_024 {
      return "\(bytes) B"
    } else if bytes < 1_024 * 1_024 {
      let kb = Double(bytes) / 1_024
      return String(format: "%.1f KB", kb)
    } else if bytes < 1_024 * 1_024 * 1_024 {
      let mb = Double(bytes) / (1_024 * 1_024)
      return String(format: "%.1f MB", mb)
    } else {
      let gb = Double(bytes) / (1_024 * 1_024 * 1_024)
      return String(format: "%.2f GB", gb)
    }
  }

  /// Returns `true` when the HTTP status code indicates GitHub API rate limiting.
  public static func isRateLimited(statusCode: Int) -> Bool {
    statusCode == 403 || statusCode == 429
  }

  /// Returns a sample `ReleaseInfo` suitable for previews and tests.
  public static func defaultReleaseInfo() -> ReleaseInfo {
    ReleaseInfo(
      tagName: "2.0.0",
      name: "DICOMKit v2.0.0",
      body: "Initial release of DICOM Studio CLI tools.",
      assets: [
        ReleaseAsset(
          name: "dicom-tools-macos-arm64.tar.gz",
          downloadURL: "https://github.com/Raster-Lab/DICOMKit/releases/download/2.0.0/dicom-tools-macos-arm64.tar.gz",
          size: 15_728_640,
          contentType: "application/gzip",
          checksum: ""
        ),
        ReleaseAsset(
          name: "dicom-tools-macos-x86_64.tar.gz",
          downloadURL: "https://github.com/Raster-Lab/DICOMKit/releases/download/2.0.0/dicom-tools-macos-x86_64.tar.gz",
          size: 16_252_928,
          contentType: "application/gzip",
          checksum: ""
        )
      ],
      publishedAt: Date(timeIntervalSince1970: 1_740_000_000),
      isPrerelease: false,
      htmlURL: "https://github.com/Raster-Lab/DICOMKit/releases/tag/2.0.0"
    )
  }

  /// Filters release assets to those targeting macOS.
  public static func filterMacOSAssets(_ assets: [ReleaseAsset]) -> [ReleaseAsset] {
    assets.filter { asset in
      let lower = asset.name.lowercased()
      return lower.contains("macos") || lower.contains("darwin") || lower.contains("apple")
    }
  }
}

// MARK: - Tool Install Helpers

/// Helpers for installing, verifying, and managing CLI tool binaries.
public enum ToolInstallHelpers: Sendable {

  /// Default directory where tools are installed.
  public static let defaultInstallDirectory: String = "~/.dicomstudio/tools"

  /// Archive formats that the installer can extract.
  public static let supportedArchiveTypes: [String] = [".tar.gz", ".zip"]

  /// Returns the full install path for a tool binary.
  public static func installPath(for toolName: String, directory: String) -> String {
    let dir = directory.hasSuffix("/") ? directory : directory + "/"
    return dir + toolName
  }

  /// Validates that an install directory path looks reasonable.
  public static func validateInstallDirectory(_ path: String) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    // Must be an absolute or home-relative path.
    return trimmed.hasPrefix("/") || trimmed.hasPrefix("~")
  }

  /// Formats a `DownloadProgress` value as a human-readable string.
  public static func formatDownloadProgress(_ progress: DownloadProgress) -> String {
    let percent = Int(progress.fractionCompleted * 100)
    let received = GitHubReleaseHelpers.formatAssetSize(progress.bytesReceived)
    let total = GitHubReleaseHelpers.formatAssetSize(progress.totalBytes)
    return "\(received) / \(total) (\(percent)%)"
  }

  /// Estimates the time remaining for a download.
  ///
  /// Returns `nil` when there is not enough data to estimate.
  public static func estimateTimeRemaining(
    progress: DownloadProgress,
    elapsedSeconds: Double
  ) -> String? {
    guard progress.fractionCompleted > 0, elapsedSeconds > 0 else { return nil }
    let totalEstimate = elapsedSeconds / progress.fractionCompleted
    let remaining = totalEstimate - elapsedSeconds
    guard remaining > 0 else { return nil }

    if remaining < 60 {
      return String(format: "%.0fs remaining", remaining)
    } else if remaining < 3_600 {
      let minutes = Int(remaining / 60)
      let seconds = Int(remaining) % 60
      return "\(minutes)m \(seconds)s remaining"
    } else {
      let hours = Int(remaining / 3_600)
      let minutes = (Int(remaining) % 3_600) / 60
      return "\(hours)h \(minutes)m remaining"
    }
  }

  /// Returns sensible default installation preferences.
  public static func defaultInstallPreferences() -> InstallationPreferences {
    InstallationPreferences(
      installDirectory: "~/.dicomstudio/tools",
      autoUpdateEnabled: true,
      customToolPath: nil
    )
  }

  /// Verifies a data blob against an expected checksum.
  ///
  /// > Note: Stub implementation – always returns `true`. A production version
  /// > would compute SHA-256 of `data` and compare.
  public static func verifyChecksum(_ data: Data, expected: String) -> Bool {
    true
  }
}

// MARK: - Auto-Update Helpers

/// Helpers for the automatic update subsystem.
public enum AutoUpdateHelpers: Sendable {

  /// Default frequency at which the app checks for updates.
  public static let defaultCheckFrequency: UpdateCheckFrequency = .daily

  /// Determines whether an update check should be performed right now.
  public static func shouldCheckForUpdate(
    lastCheck: Date?,
    frequency: UpdateCheckFrequency
  ) -> Bool {
    switch frequency {
    case .never:
      return false
    case .onLaunch:
      return true
    case .daily:
      guard let last = lastCheck else { return true }
      return Date().timeIntervalSince(last) >= 86_400
    case .weekly:
      guard let last = lastCheck else { return true }
      return Date().timeIntervalSince(last) >= 604_800
    }
  }

  /// Returns `true` when `latest` is strictly newer than `current`.
  public static func compareVersions(
    _ current: SemanticVersion,
    _ latest: SemanticVersion
  ) -> Bool {
    latest > current
  }

  /// Returns a concise summary describing the available update.
  public static func updateSummary(
    currentVersion: SemanticVersion,
    availableVersion: String
  ) -> String {
    let current = VersionHelpers.formatVersionString(currentVersion)
    return "Update available: \(current) → v\(availableVersion)"
  }

  /// Returns a human-readable label for an `UpdateState`.
  public static func formatUpdateState(_ state: UpdateState) -> String {
    switch state {
    case .unchecked:
      return "Updates have not been checked yet."
    case .checking:
      return "Checking for updates…"
    case .upToDate:
      return "All tools are up to date."
    case .updateAvailable(let version):
      return "Version \(version) is available for download."
    case .downloading(let progress):
      let percent = Int(progress * 100)
      return "Downloading update… \(percent)%"
    case .readyToInstall(let version):
      return "Version \(version) is ready to install."
    case .failed(let message):
      return "Update failed: \(message)"
    }
  }
}

// MARK: - Launch Coordinator Helpers

/// Helpers for coordinating the app-launch sequence.
public enum LaunchCoordinatorHelpers: Sendable {

  /// Returns a user-facing summary string for a launch phase.
  public static func launchPhaseSummary(_ phase: LaunchPhase) -> String {
    switch phase {
    case .initializing:
      return "Starting DICOM Studio…"
    case .discoveringTools:
      return "Scanning for installed CLI tools…"
    case .checkingVersions:
      return "Verifying tool version compatibility…"
    case .checkingUpdates:
      return "Looking for available updates…"
    case .ready:
      return "DICOM Studio is ready."
    case .setupRequired:
      return "Initial setup is required before continuing."
    case .error(let message):
      return "Launch error: \(message)"
    }
  }

  /// Determines the next launch phase based on completed steps.
  public static func determineNextPhase(
    after current: LaunchPhase,
    toolsDiscovered: Bool,
    versionsChecked: Bool,
    updatesChecked: Bool
  ) -> LaunchPhase {
    switch current {
    case .initializing:
      return .discoveringTools
    case .discoveringTools:
      return toolsDiscovered ? .checkingVersions : .setupRequired
    case .checkingVersions:
      return versionsChecked ? .checkingUpdates : .ready
    case .checkingUpdates:
      return updatesChecked ? .ready : .ready
    case .ready, .setupRequired, .error:
      return current
    }
  }

  /// Returns `true` when the version report suggests the setup assistant should appear.
  public static func shouldShowSetupAssistant(report: VersionReport) -> Bool {
    report.overallStatus == .hasMissing || report.missingCount > report.toolReports.count / 2
  }

  /// Returns `true` when the update banner should be visible.
  public static func shouldShowUpdateBanner(state: UpdateState) -> Bool {
    switch state {
    case .updateAvailable, .readyToInstall:
      return true
    case .unchecked, .checking, .upToDate, .downloading, .failed:
      return false
    }
  }

  /// Formats a launch duration in seconds into a readable string.
  public static func formatLaunchDuration(_ seconds: Double) -> String {
    if seconds < 1.0 {
      let ms = Int(seconds * 1_000)
      return "\(ms)ms"
    }
    return String(format: "%.1fs", seconds)
  }
}
