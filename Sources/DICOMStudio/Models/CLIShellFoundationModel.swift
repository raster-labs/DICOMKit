// CLIShellFoundationModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for CLI Shell Foundation (Milestone 17)
// NEMA-verified: 2026a, checked 2026-10-05 — the standard-derived content is the tool catalogue: the 42 ToolCategory.toolNames are exactly the Sources/dicom-* targets (dicom-j2k, dicom-jpip, dicom-printscp, dicom-video were missing; dicom-qido/stow/ups never existed, they are dicom-wado subcommands), diffed by Scripts/diff_studio_g1_shell.py; no tag, UID, port, AE title or PS3 clause is carried here (version, install and launch state only)

import Foundation

// MARK: - 17.1 Tool Discovery & Registry

/// The 9 browser categories for organizing the 42 `dicom-*` CLI tools (one per `Sources/dicom-*` target).
public enum ToolCategory: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case networking       = "NETWORKING"
    case viewerImaging    = "VIEWER_IMAGING"
    case fileInspection   = "FILE_INSPECTION"
    case fileProcessing   = "FILE_PROCESSING"
    case fileOrganization = "FILE_ORGANIZATION"
    case dataExchange     = "DATA_EXCHANGE"
    case clinical         = "CLINICAL"
    case utilities        = "UTILITIES"
    case cloudAI          = "CLOUD_AI"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .networking:       return "Networking"
        case .viewerImaging:    return "Viewer & Imaging"
        case .fileInspection:   return "File Inspection"
        case .fileProcessing:   return "File Processing"
        case .fileOrganization: return "File Organization"
        case .dataExchange:     return "Data Exchange"
        case .clinical:         return "Clinical"
        case .utilities:        return "Utilities"
        case .cloudAI:          return "Cloud & AI"
        }
    }

    /// SF Symbol name for this category.
    public var sfSymbol: String {
        switch self {
        case .networking:       return "network"
        case .viewerImaging:    return "eye"
        case .fileInspection:   return "doc.text.magnifyingglass"
        case .fileProcessing:   return "gearshape.2"
        case .fileOrganization: return "folder.badge.gearshape"
        case .dataExchange:     return "square.and.arrow.up"
        case .clinical:         return "heart.text.clipboard"
        case .utilities:        return "wrench.and.screwdriver"
        case .cloudAI:          return "cloud"
        }
    }

    /// Brief description of the tools in this category.
    public var categoryDescription: String {
        switch self {
        case .networking:       return "DICOM network operations including echo, query, send, and retrieve"
        case .viewerImaging:    return "Image viewing, rendering, and 3D visualization"
        case .fileInspection:   return "Inspect, dump, tag-lookup, and diff DICOM files"
        case .fileProcessing:   return "Convert, validate, anonymize, compress, and inspect JPEG 2000 codestreams of DICOM files"
        case .fileOrganization: return "Split, merge, create DICOMDIR, and archive files"
        case .dataExchange:     return "Export to JSON, XML, PDF, images, video, and pixel editing"
        case .clinical:         return "Structured reports, measurements, and study-level operations"
        case .utilities:        return "UID generation, scripting, and general-purpose tools"
        case .cloudAI:          return "Cloud storage, DICOMweb, and AI-assisted processing"
        }
    }

    /// The CLI tool executable names belonging to this category.
    public var toolNames: [String] {
        switch self {
        case .networking:
            return [
                "dicom-echo", "dicom-query", "dicom-send", "dicom-retrieve",
                "dicom-qr", "dicom-wado", "dicom-mwl", "dicom-mpps",
                "dicom-print", "dicom-printscp", "dicom-jpip", "dicom-gateway", "dicom-server"
            ]
        case .viewerImaging:
            return ["dicom-viewer", "dicom-image", "dicom-3d"]
        case .fileInspection:
            return ["dicom-info", "dicom-dump", "dicom-tags", "dicom-diff"]
        case .fileProcessing:
            return ["dicom-convert", "dicom-validate", "dicom-anon", "dicom-compress", "dicom-j2k"]
        case .fileOrganization:
            return ["dicom-split", "dicom-merge", "dicom-dcmdir", "dicom-archive"]
        case .dataExchange:
            return ["dicom-json", "dicom-xml", "dicom-pdf", "dicom-export", "dicom-pixedit", "dicom-video"]
        case .clinical:
            return ["dicom-report", "dicom-measure", "dicom-study"]
        case .utilities:
            return ["dicom-uid", "dicom-script"]
        case .cloudAI:
            return ["dicom-cloud", "dicom-ai"]
        }
    }
}

/// Availability status of a discovered CLI tool.
public enum ToolAvailability: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case available       = "AVAILABLE"
    case unavailable     = "UNAVAILABLE"
    case versionMismatch = "VERSION_MISMATCH"
    case unknown         = "UNKNOWN"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .available:       return "Available"
        case .unavailable:     return "Unavailable"
        case .versionMismatch: return "Version Mismatch"
        case .unknown:         return "Unknown"
        }
    }

    /// SF Symbol name for this availability status.
    public var sfSymbol: String {
        switch self {
        case .available:       return "checkmark.circle.fill"
        case .unavailable:     return "xmark.circle.fill"
        case .versionMismatch: return "exclamationmark.triangle.fill"
        case .unknown:         return "questionmark.circle"
        }
    }
}

/// A single discovered CLI tool with its metadata and availability.
public struct ToolInfo: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Executable name (e.g. `dicom-echo`).
    public let name: String

    /// Human-readable display name (e.g. "DICOM Echo").
    public let displayName: String

    /// Absolute path to the discovered binary.
    public let path: String

    /// Version string reported by `--version` (e.g. "1.0.0").
    public let version: String

    /// Browser category this tool belongs to.
    public let category: ToolCategory

    /// Current availability status.
    public let availability: ToolAvailability

    /// Brief description of what the tool does.
    public let toolDescription: String

    /// Creates a new tool info entry.
    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        path: String,
        version: String,
        category: ToolCategory,
        availability: ToolAvailability,
        toolDescription: String
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.path = path
        self.version = version
        self.category = category
        self.availability = availability
        self.toolDescription = toolDescription
    }
}

// MARK: - 17.2 Version Compatibility Checking

/// A parsed semantic version with major, minor, and patch components.
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Major version component.
    public let major: Int

    /// Minor version component.
    public let minor: Int

    /// Patch version component.
    public let patch: Int

    /// Creates a semantic version from its components.
    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses a version string in `"major.minor.patch"` format.
    ///
    /// Returns `nil` if the string does not match the expected format.
    public init?(parsing string: String) {
        let stripped = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = stripped.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Whether this version is compatible with the given version.
    ///
    /// Two versions are compatible when their major and minor components match.
    public func isCompatible(with other: SemanticVersion) -> Bool {
        major == other.major && minor == other.minor
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    // MARK: Comparable

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Result of comparing a tool's version against the expected version.
public enum VersionCompatibility: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case compatible       = "COMPATIBLE"
    case incompatibleMajor = "INCOMPATIBLE_MAJOR"
    case incompatibleMinor = "INCOMPATIBLE_MINOR"
    case missingTool      = "MISSING_TOOL"
    case unknownVersion   = "UNKNOWN_VERSION"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .compatible:       return "Compatible"
        case .incompatibleMajor: return "Incompatible (Major)"
        case .incompatibleMinor: return "Incompatible (Minor)"
        case .missingTool:      return "Missing"
        case .unknownVersion:   return "Unknown Version"
        }
    }

    /// SF Symbol name for this compatibility result.
    public var sfSymbol: String {
        switch self {
        case .compatible:       return "checkmark.seal.fill"
        case .incompatibleMajor: return "xmark.seal.fill"
        case .incompatibleMinor: return "exclamationmark.triangle.fill"
        case .missingTool:      return "minus.circle.fill"
        case .unknownVersion:   return "questionmark.circle"
        }
    }
}

/// A version check entry for a single tool.
public struct ToolVersionEntry: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Executable name (e.g. `dicom-echo`).
    public let toolName: String

    /// The version currently installed, or `nil` if the tool is missing.
    public let installedVersion: SemanticVersion?

    /// The version expected by DICOM Studio.
    public let expectedVersion: SemanticVersion

    /// Compatibility result.
    public let compatibility: VersionCompatibility

    /// Creates a new tool version entry.
    public init(
        id: UUID = UUID(),
        toolName: String,
        installedVersion: SemanticVersion?,
        expectedVersion: SemanticVersion,
        compatibility: VersionCompatibility
    ) {
        self.id = id
        self.toolName = toolName
        self.installedVersion = installedVersion
        self.expectedVersion = expectedVersion
        self.compatibility = compatibility
    }
}

/// Overall status of a version compatibility report.
public enum VersionReportStatus: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case allCompatible  = "ALL_COMPATIBLE"
    case hasIncompatible = "HAS_INCOMPATIBLE"
    case hasMissing     = "HAS_MISSING"
    case offline        = "OFFLINE"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .allCompatible:  return "All Compatible"
        case .hasIncompatible: return "Has Incompatible"
        case .hasMissing:     return "Has Missing"
        case .offline:        return "Offline"
        }
    }

    /// SF Symbol name for this report status.
    public var sfSymbol: String {
        switch self {
        case .allCompatible:  return "checkmark.circle.fill"
        case .hasIncompatible: return "exclamationmark.triangle.fill"
        case .hasMissing:     return "minus.circle.fill"
        case .offline:        return "wifi.slash"
        }
    }
}

/// Aggregated version compatibility report for all tools.
public struct VersionReport: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// The DICOM Studio version used as the compatibility baseline.
    public let studioVersion: SemanticVersion

    /// Individual version check results for each tool.
    public let toolReports: [ToolVersionEntry]

    /// Timestamp when this report was generated.
    public let timestamp: Date

    /// Number of tools that are compatible.
    public var compatibleCount: Int {
        toolReports.filter { $0.compatibility == .compatible }.count
    }

    /// Number of tools that are incompatible (major or minor).
    public var incompatibleCount: Int {
        toolReports.filter {
            $0.compatibility == .incompatibleMajor || $0.compatibility == .incompatibleMinor
        }.count
    }

    /// Number of tools that are missing.
    public var missingCount: Int {
        toolReports.filter { $0.compatibility == .missingTool }.count
    }

    /// Overall status of this report.
    public var overallStatus: VersionReportStatus {
        if missingCount > 0 { return .hasMissing }
        if incompatibleCount > 0 { return .hasIncompatible }
        return .allCompatible
    }

    /// Creates a new version report.
    public init(
        id: UUID = UUID(),
        studioVersion: SemanticVersion,
        toolReports: [ToolVersionEntry],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.studioVersion = studioVersion
        self.toolReports = toolReports
        self.timestamp = timestamp
    }
}

// MARK: - 17.3 GitHub Release Integration

/// Metadata about a GitHub release.
public struct ReleaseInfo: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Git tag name (e.g. `"v1.0.0"`).
    public let tagName: String

    /// Human-readable release title.
    public let name: String

    /// Release notes body (Markdown).
    public let body: String

    /// Downloadable assets attached to this release.
    public let assets: [ReleaseAsset]

    /// Date and time this release was published.
    public let publishedAt: Date

    /// Whether this release is a pre-release.
    public let isPrerelease: Bool

    /// URL for viewing this release on GitHub.
    public let htmlURL: String

    /// Parsed semantic version from the tag name.
    public var version: SemanticVersion? {
        SemanticVersion(parsing: tagName)
    }

    /// Creates a new release info entry.
    public init(
        id: UUID = UUID(),
        tagName: String,
        name: String,
        body: String,
        assets: [ReleaseAsset],
        publishedAt: Date,
        isPrerelease: Bool,
        htmlURL: String
    ) {
        self.id = id
        self.tagName = tagName
        self.name = name
        self.body = body
        self.assets = assets
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
        self.htmlURL = htmlURL
    }
}

/// A downloadable asset from a GitHub release.
public struct ReleaseAsset: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// File name of the asset (e.g. `"dicom-tools-macos-universal.tar.gz"`).
    public let name: String

    /// URL to download the asset.
    public let downloadURL: String

    /// Size of the asset in bytes.
    public let size: Int64

    /// MIME content type (e.g. `"application/gzip"`).
    public let contentType: String

    /// SHA-256 checksum for integrity verification.
    public let checksum: String

    /// Human-readable formatted file size.
    public var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Creates a new release asset entry.
    public init(
        id: UUID = UUID(),
        name: String,
        downloadURL: String,
        size: Int64,
        contentType: String,
        checksum: String
    ) {
        self.id = id
        self.name = name
        self.downloadURL = downloadURL
        self.size = size
        self.contentType = contentType
        self.checksum = checksum
    }
}

/// Progress of an ongoing download.
public struct DownloadProgress: Sendable, Hashable {
    /// Number of bytes received so far.
    public let bytesReceived: Int64

    /// Total expected bytes, or `0` if unknown.
    public let totalBytes: Int64

    /// Fraction completed (0.0–1.0).
    public let fractionCompleted: Double

    /// Creates a new download progress snapshot.
    public init(bytesReceived: Int64, totalBytes: Int64, fractionCompleted: Double) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.fractionCompleted = fractionCompleted
    }
}

// MARK: - 17.4 Tool Installation Manager

/// State of a tool installation workflow.
public enum InstallationState: Sendable, Equatable {
    /// No installation in progress.
    case idle
    /// Downloading the tool binary. The associated value is the progress fraction (0.0–1.0).
    case downloading(Double)
    /// Extracting the downloaded archive.
    case extracting
    /// Verifying the installed binary with `--version`.
    case verifying
    /// Installation completed successfully.
    case completed
    /// Installation failed with a description of the error.
    case failed(String)
    /// Rolling back to the previous version after a failure.
    case rollingBack

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .idle:              return "Idle"
        case .downloading:       return "Downloading"
        case .extracting:        return "Extracting"
        case .verifying:         return "Verifying"
        case .completed:         return "Completed"
        case .failed:            return "Failed"
        case .rollingBack:       return "Rolling Back"
        }
    }

    /// SF Symbol name for this installation state.
    public var sfSymbol: String {
        switch self {
        case .idle:              return "arrow.down.circle"
        case .downloading:       return "arrow.down.circle.dotted"
        case .extracting:        return "archivebox"
        case .verifying:         return "checkmark.shield"
        case .completed:         return "checkmark.circle.fill"
        case .failed:            return "xmark.circle.fill"
        case .rollingBack:       return "arrow.uturn.backward.circle"
        }
    }
}

/// User-configurable installation preferences.
public struct InstallationPreferences: Sendable, Hashable {
    /// Directory where CLI tool binaries are installed.
    public let installDirectory: String

    /// Whether automatic updates are enabled.
    public let autoUpdateEnabled: Bool

    /// Optional custom search path for tool binaries.
    public let customToolPath: String?

    /// Default installation preferences.
    public static var defaultPreferences: InstallationPreferences {
        InstallationPreferences(
            installDirectory: "~/.dicomstudio/tools",
            autoUpdateEnabled: true,
            customToolPath: nil
        )
    }

    /// Creates new installation preferences.
    public init(
        installDirectory: String,
        autoUpdateEnabled: Bool,
        customToolPath: String?
    ) {
        self.installDirectory = installDirectory
        self.autoUpdateEnabled = autoUpdateEnabled
        self.customToolPath = customToolPath
    }
}

// MARK: - 17.5 Self-Update Mechanism

/// How often DICOM Studio checks for updates.
public enum UpdateCheckFrequency: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case onLaunch = "ON_LAUNCH"
    case daily    = "DAILY"
    case weekly   = "WEEKLY"
    case never    = "NEVER"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .onLaunch: return "On Launch"
        case .daily:    return "Daily"
        case .weekly:   return "Weekly"
        case .never:    return "Never"
        }
    }
}

/// State of the self-update workflow.
public enum UpdateState: Sendable, Equatable {
    /// No update check has been performed.
    case unchecked
    /// Currently checking for updates.
    case checking
    /// The app is up to date.
    case upToDate
    /// An update is available. The associated value is the new version string.
    case updateAvailable(String)
    /// Downloading the update. The associated value is the progress fraction (0.0–1.0).
    case downloading(Double)
    /// The update has been downloaded and is ready to install. The associated value is the version string.
    case readyToInstall(String)
    /// Update check or download failed. The associated value describes the error.
    case failed(String)

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .unchecked:                return "Not Checked"
        case .checking:                 return "Checking"
        case .upToDate:                 return "Up to Date"
        case .updateAvailable(let v):   return "Update Available (\(v))"
        case .downloading:              return "Downloading"
        case .readyToInstall(let v):    return "Ready to Install (\(v))"
        case .failed:                   return "Failed"
        }
    }

    /// SF Symbol name for this update state.
    public var sfSymbol: String {
        switch self {
        case .unchecked:        return "arrow.clockwise.circle"
        case .checking:         return "arrow.triangle.2.circlepath"
        case .upToDate:         return "checkmark.circle.fill"
        case .updateAvailable:  return "arrow.up.circle.fill"
        case .downloading:      return "arrow.down.circle.dotted"
        case .readyToInstall:   return "arrow.down.to.line.circle.fill"
        case .failed:           return "xmark.circle.fill"
        }
    }
}

// MARK: - 17.6 Launch Sequence Orchestration

/// Phase of the startup launch sequence.
public enum LaunchPhase: Sendable, Equatable {
    /// Launch sequence has not started.
    case initializing
    /// Discovering installed CLI tools.
    case discoveringTools
    /// Checking version compatibility of discovered tools.
    case checkingVersions
    /// Checking for application updates.
    case checkingUpdates
    /// All checks passed; ready to use.
    case ready
    /// One or more tools require setup.
    case setupRequired
    /// An error occurred during the launch sequence. The associated value describes the error.
    case error(String)

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .initializing:     return "Initializing"
        case .discoveringTools: return "Discovering Tools"
        case .checkingVersions: return "Checking Versions"
        case .checkingUpdates:  return "Checking Updates"
        case .ready:            return "Ready"
        case .setupRequired:    return "Setup Required"
        case .error:            return "Error"
        }
    }

    /// SF Symbol name for this launch phase.
    public var sfSymbol: String {
        switch self {
        case .initializing:     return "hourglass"
        case .discoveringTools: return "magnifyingglass"
        case .checkingVersions: return "checkmark.shield"
        case .checkingUpdates:  return "arrow.triangle.2.circlepath"
        case .ready:            return "checkmark.circle.fill"
        case .setupRequired:    return "wrench.and.screwdriver"
        case .error:            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - 17.1 Tool Search Paths

/// Well-known directories where CLI tool binaries may be located.
public enum ToolSearchPath: Sendable, Equatable, Hashable {
    /// Directories listed in the `$PATH` environment variable.
    case systemPath
    /// `/usr/local/bin`
    case usrLocalBin
    /// `~/.local/bin`
    case homeLocalBin
    /// Homebrew prefix (e.g. `/opt/homebrew/bin`).
    case homebrewPrefix
    /// DICOM Studio's managed tool directory (`~/.dicomstudio/tools`).
    case dicomStudioTools
    /// A user-specified custom directory.
    case custom(String)

    private static let defaultSystemPath = "/usr/bin:/bin"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .systemPath:       return "System PATH"
        case .usrLocalBin:      return "/usr/local/bin"
        case .homeLocalBin:     return "~/.local/bin"
        case .homebrewPrefix:   return "Homebrew"
        case .dicomStudioTools: return "DICOM Studio Tools"
        case .custom(let dir):  return "Custom: \(dir)"
        }
    }

    /// The user's home directory.
    ///
    /// `homeDirectoryForCurrentUser` is macOS-only — it describes a real user
    /// account, which iOS/tvOS/visionOS do not expose. There `NSHomeDirectory()`
    /// is the app sandbox's home, which is the right root for the same paths.
    private static var homeDirectory: String {
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser.path
        #else
        return NSHomeDirectory()
        #endif
    }

    /// The resolved directory path for this search location.
    public var path: String {
        switch self {
        case .systemPath:
            return ProcessInfo.processInfo.environment["PATH"] ?? Self.defaultSystemPath
        case .usrLocalBin:
            return "/usr/local/bin"
        case .homeLocalBin:
            return "\(Self.homeDirectory)/.local/bin"
        case .homebrewPrefix:
            #if arch(arm64)
            return "/opt/homebrew/bin"
            #else
            return "/usr/local/bin"
            #endif
        case .dicomStudioTools:
            return "\(Self.homeDirectory)/.dicomstudio/tools"
        case .custom(let dir):
            return dir
        }
    }
}
