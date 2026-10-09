# DICOM Studio — Architecture

## Overview

DICOM Studio is a macOS SwiftUI application showcasing DICOMKit. It follows **MVVM** (Model–View–ViewModel) with a service layer, using Swift 6.2 strict concurrency and the `@Observable` macro.

## Directory Structure

The `@main` entry point is not in this library. It lives in
`Sources/DICOMStudioApp/DICOMStudioApp.swift`, which only the
`DICOMStudio.xcodeproj` app target compiles; it imports this library and
declares the app's windows, menus and Settings scene.

```
Sources/DICOMStudio/
├── App/                        # Menu commands used by the app's scenes
│   ├── StudioWindowCommands.swift  # Window menu: Printer Emulator, Print Preview
│   └── ViewerCommands.swift        # View/Image menu: zoom, fit, overlays, transforms
├── Models/                     # Data models (pure Swift, Sendable)
│   ├── StudyModel.swift        # Study-level DICOM metadata
│   ├── SeriesModel.swift       # Series-level DICOM metadata
│   ├── InstanceModel.swift     # Instance-level DICOM metadata
│   ├── LibraryModel.swift      # In-memory file library/index
│   └── NetworkUtilityModel.swift  # Ping/trace/DNS/port/netstat result types
├── Services/                   # Business logic layer
│   ├── DICOMFileService.swift  # File I/O via DICOMKit
│   ├── ThumbnailService.swift  # Thumbnail generation/caching
│   ├── StorageService.swift    # Local file system management
│   ├── SettingsService.swift   # User preferences
│   ├── NavigationService.swift # Routing and destinations
│   ├── NetworkUtilityService.swift          # Process launch, streaming, parsing
│   └── NetworkUtilityService+Parsing.swift  # Output parsers (ping/trace/DNS/netstat)
├── ViewModels/                 # @Observable ViewModels
│   ├── MainViewModel.swift     # Top-level navigation & state
│   ├── SettingsViewModel.swift # Settings UI state
│   └── NetworkUtilityViewModel.swift  # Network Utility input + result state
├── Views/                      # SwiftUI views (macOS/iOS)
│   ├── MainView.swift          # NavigationSplitView shell
│   ├── SidebarView.swift       # Sidebar navigation list
│   ├── NetworkUtilityView.swift  # Six-tab network diagnostics panel
│   └── Settings/               # Settings tab views
│       ├── SettingsView.swift
│       ├── GeneralSettingsView.swift
│       ├── PrivacySettingsView.swift
│       ├── PerformanceSettingsView.swift
│       └── AboutView.swift
├── Components/                 # Reusable UI components
│   ├── DICOMTagView.swift      # (GGGG,EEEE) tag display
│   ├── VRBadge.swift           # Value Representation badge
│   ├── ModalityIcon.swift      # Modality-specific SF Symbol
│   └── StatusIndicator.swift   # Connection/transfer status
└── Theme/
    └── StudioTheme.swift       # Colors, typography constants
```

## Architecture Layers

### Models (Pure Swift)

All models are `Sendable` value types (`struct`) with no UI dependencies:

- **`StudyModel`** — Patient demographics, study metadata, modality tracking
- **`SeriesModel`** — Series number, modality, body part, transfer syntax
- **`InstanceModel`** — SOP UIDs, file path, image dimensions, multi-frame detection
- **`LibraryModel`** — In-memory index with study → series → instance hierarchy
- **`NetworkUtilityModel`** — Result types for all six network tools (`PingResult`, `PortResult`, `TracerouteResult`, `DNSResult`, `NetworkInterface`, `NetstatResult`), plus input enums (`IPFamily`, `DNSRecordType`, `NetstatMode`, `NetworkUtilityTool`)

### Services (Dependency-Injected)

Services encapsulate business logic and are injected into ViewModels:

| Service | Responsibility | Thread Safety |
|---------|---------------|---------------|
| `DICOMFileService` | Parse DICOM files via DICOMKit | `Sendable` |
| `ThumbnailService` | Generate/cache thumbnails | `Sendable` |
| `StorageService` | Manage directories (import, cache, export) | `Sendable` |
| `SettingsService` | Read/write user preferences | `@unchecked Sendable` (NSLock) |
| `NavigationService` | Define navigation destinations | `Sendable` |
| `NetworkUtilityService` | Spawn system processes (`ping`, `traceroute`, `dig`, `netstat`), stream stdout via `AsyncStream<String>`, parse structured results | `Sendable` (lock-guarded internals) |

### ViewModels (`@Observable`)

ViewModels use the `@Observable` macro (requires macOS 14+ / Swift 5.9+):

- **`MainViewModel`** — Owns all services, manages navigation, library state, status
- **`SettingsViewModel`** — Two-way binding to `SettingsService`, auto-persists changes
- **`NetworkUtilityViewModel`** — Drives all six network-utility tabs; holds `sharedHost` shared by Ping/Port Scanner/Traceroute, per-tool result state, and a `streamGeneration` counter that invalidates streamed chunks from cancelled or superseded runs

### Views (SwiftUI, `#if canImport(SwiftUI)`)

All SwiftUI code is wrapped in `#if canImport(SwiftUI)` for cross-platform library compilation:

- **`MainView`** — `NavigationSplitView` with sidebar + detail
- **`SidebarView`** — Lists 7 feature areas with SF Symbol icons
- **`NetworkUtilityView`** — Six-tab panel (Ping, Port Scanner, Traceroute, DNS Lookup, Interfaces, Netstat) with terminal-style output panels that fill live as each tool streams output
- **Settings views** — Tabbed on macOS, navigation stack on iOS

### Components (Reusable)

Platform-guarded SwiftUI components with full accessibility support:

| Component | Purpose | Accessibility |
|-----------|---------|--------------|
| `DICOMTagView` | Display `(GGGG,EEEE)` tag | Combined label with keyword |
| `VRBadge` | Color-coded VR type | Full VR name spoken |
| `ModalityIcon` | SF Symbol per modality | Full modality name spoken |
| `StatusIndicator` | Status dot + label | Status announced with context |

## Navigation Destinations

| Destination | SF Symbol | Description |
|------------|-----------|-------------|
| Library | `folder` | DICOM file browser (Milestone 2) |
| Viewer | `photo` | Image viewer (Milestone 3); also plays video instances and renders SR / encapsulated documents |
| Networking | `network` | DICOM/DICOMweb hub (Milestone 9–10) |
| Reporting | `doc.text` | Structured reports (Milestone 7) |
| Tools | `wrench.and.screwdriver` | Data exchange tools (Milestone 12–13) |
| CLI Workshop | `terminal` | CLI tools GUI (Milestone 16) |
| Network Utility | `network.badge.shield.half.filled` | General network diagnostics (Ping, Port Scanner, Traceroute, DNS, Interfaces, Netstat) |
| Settings | `gear` | App configuration |

## Theme

### Color Palette

Medical imaging–appropriate colors defined in `StudioColors`:

- **Primary**: Teal blue (`#3899C7`) for navigation and actions
- **Background**: Deep navy (`#0F1219`) for radiology dark mode
- **Modality colors**: CT (blue), MR (purple), US (green), XR (amber)
- **Status colors**: Success (green), Warning (amber), Error (red)

### Typography Scale

Defined in `StudioTypography` using `CGFloat` constants that pair with Dynamic Type:

| Style | Size | Usage |
|-------|------|-------|
| Display | 28pt | Main titles |
| Header | 20pt | Section headers |
| Body | 14pt | Content text |
| Caption | 11pt | Details, labels |
| Mono | 12pt | Tags, UIDs |

## Network Utility — Live Streaming Architecture

The Network Utility feature wraps macOS system binaries (`ping`, `traceroute`, `dig`, `netstat`) and streams their output to the UI as it arrives, giving a terminal-like experience.

### Data flow

```
NetworkUtilityViewModel.runPing() / runTraceroute() / runDNSLookup() / runNetstat()
  │
  ├── seeds an empty result (rawOutput: "")  ← terminal panel renders immediately
  ├── bumps streamGeneration counter         ← invalidates any prior in-flight run
  │
  └── Task { await service.ping(onChunk:) }
        │
        └── NetworkUtilityService.runStreamingProcess()
              │
              ├── spawns Process on DispatchQueue.global
              ├── merges stderr → stdout (same Pipe)  ← preserves natural output order
              ├── AsyncStream<String> yields chunks via availableData loop
              │     └── UTF-8 carry-over buffer handles multibyte scalars split across reads
              ├── watchdog (DispatchWorkItem): SIGTERM + SIGKILL after 3 s grace
              │     └── liveness guard: noop if process already exited at deadline
              └── withTaskCancellationHandler → ProcessKillBox.cancel()
                    └── SIGTERM + SIGKILL after 3 s grace
```

### Run-identity guard (`streamGeneration`)

A quick cancel-then-rerun re-raises `isRunning = true` for the *new* run while the old process may still be draining its pipe.  Using `isRunning` as a guard is therefore unsafe.  Each run captures `let gen = streamGeneration` before launching; `onChunk` and the completion assignment both check `self.streamGeneration == gen` and drop stale deliveries silently.  `cancel()` also bumps the counter so in-flight chunks from the cancelled run are discarded even before the new run starts.

### Port Scanner (`scanPorts`)

Port scanning is different: it probes ports concurrently (up to N parallel Swift Tasks) rather than spawning a single long-lived process.  It uses the same `portScanGeneration` counter pattern, and results append in arrival order for a live log effect.  A final sort by port number is applied only after all probes complete.

## Testing

124 tests across 13 test suites covering:

- **Model tests**: Creation, defaults, display formatting, sorting, hierarchy
- **Service tests**: Settings persistence, storage operations, thumbnail caching
- **ViewModel tests**: Navigation, state management, dependency injection
- **Theme tests**: Color validation, modality mapping, typography scale

## Dependencies

- **DICOMKit** — DICOM file parsing, data sets
- **DICOMCore** — Tags, VR, data elements, transfer syntax
- **DICOMDictionary** — Tag and UID dictionaries
- **Observation** — `@Observable` macro (Swift standard library)
- **SwiftUI** — UI framework (Apple platforms only)

## Platform Support

| Layer | Linux | macOS | iOS | visionOS |
|-------|-------|-------|-----|----------|
| Models | ✅ | ✅ | ✅ | ✅ |
| Services | ✅ | ✅ | ✅ | ✅ |
| ViewModels | ✅ | ✅ | ✅ | ✅ |
| Views | ❌ | ✅ | ✅ | ✅ |
| Components | ❌ | ✅ | ✅ | ✅ |
| Tests | ✅ | ✅ | ✅ | ✅ |
