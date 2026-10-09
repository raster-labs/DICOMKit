// MacOSEnhancementsHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for macOS-Specific Enhancements (Milestone 14)
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (menu, shortcut, Dock, automation and Quick Look helpers)

import Foundation

// MARK: - 14.1 Multi-Window Helpers

/// Helpers for multi-window management.
public enum MultiWindowHelpers: Sendable {

    /// Returns a human-readable window title.
    public static func windowTitle(for studyUID: String, index: Int) -> String {
        let label = studyUID.count > 16 ? String(studyUID.prefix(16)) + "…" : studyUID
        return "Study Window \(index + 1) — \(label)"
    }

    /// Returns a description of how many windows are open (for Exposé / Mission Control).
    public static func exposéDescription(windowCount: Int) -> String {
        switch windowCount {
        case 0:  return "No windows open"
        case 1:  return "1 window open"
        default: return "\(windowCount) windows open"
        }
    }

    /// Returns true when source and destination are different windows.
    public static func canDragToWindow(source: WindowState, destination: WindowState) -> Bool {
        source.id != destination.id
    }
}

// MARK: - 14.2 Menu Bar Helpers

/// Helpers for building and filtering the macOS menu bar action list.
public enum MenuBarHelpers: Sendable {

    /// Returns the default set of menu actions for all categories.
    public static func defaultMenuActions() -> [MenuActionEntry] {
        var entries: [MenuActionEntry] = []

        // File
        entries.append(MenuActionEntry(category: .file, title: "Open",         keyboardShortcut: "⌘O", actionIdentifier: "file.open"))
        entries.append(MenuActionEntry(category: .file, title: "Import",       keyboardShortcut: "⌘⇧I", actionIdentifier: "file.import"))
        entries.append(MenuActionEntry(category: .file, title: "Export",       keyboardShortcut: "⌘E", actionIdentifier: "file.export"))
        entries.append(MenuActionEntry(category: .file, title: "Print",        keyboardShortcut: "⌘P", actionIdentifier: "file.print"))
        entries.append(MenuActionEntry(category: .file, title: "",             isSeparator: true, actionIdentifier: "file.separator1"))
        entries.append(MenuActionEntry(category: .file, title: "Close Window", keyboardShortcut: "⌘W", actionIdentifier: "file.closeWindow"))

        // Edit
        entries.append(MenuActionEntry(category: .edit, title: "Undo",        keyboardShortcut: "⌘Z",  actionIdentifier: "edit.undo"))
        entries.append(MenuActionEntry(category: .edit, title: "Redo",        keyboardShortcut: "⌘⇧Z", actionIdentifier: "edit.redo"))
        entries.append(MenuActionEntry(category: .edit, title: "",            isSeparator: true,        actionIdentifier: "edit.separator1"))
        entries.append(MenuActionEntry(category: .edit, title: "Preferences", keyboardShortcut: "⌘,",  actionIdentifier: "edit.preferences"))

        // View
        entries.append(MenuActionEntry(category: .view, title: "Zoom In",     keyboardShortcut: "⌘+", actionIdentifier: "view.zoomIn"))
        entries.append(MenuActionEntry(category: .view, title: "Zoom Out",    keyboardShortcut: "⌘-", actionIdentifier: "view.zoomOut"))
        entries.append(MenuActionEntry(category: .view, title: "Actual Size", keyboardShortcut: "⌘0", actionIdentifier: "view.actualSize"))
        entries.append(MenuActionEntry(category: .view, title: "",            isSeparator: true,       actionIdentifier: "view.separator1"))
        entries.append(MenuActionEntry(category: .view, title: "Fullscreen",  keyboardShortcut: "⌘⇧F", actionIdentifier: "view.fullscreen"))

        // Tools
        entries.append(MenuActionEntry(category: .tools, title: "Measurements",  keyboardShortcut: "⌘M", actionIdentifier: "tools.measurements"))
        entries.append(MenuActionEntry(category: .tools, title: "Annotations",   keyboardShortcut: "⌘A", actionIdentifier: "tools.annotations"))
        entries.append(MenuActionEntry(category: .tools, title: "Window/Level",  keyboardShortcut: "⌘L", actionIdentifier: "tools.windowLevel"))

        // Window
        entries.append(MenuActionEntry(category: .window, title: "Tile",     keyboardShortcut: "⌘⇧T", actionIdentifier: "window.tile"))
        entries.append(MenuActionEntry(category: .window, title: "Cascade",  keyboardShortcut: "⌘⇧C", actionIdentifier: "window.cascade"))
        entries.append(MenuActionEntry(category: .window, title: "",         isSeparator: true,         actionIdentifier: "window.separator1"))
        entries.append(MenuActionEntry(category: .window, title: "Minimize", keyboardShortcut: "⌘⇧M", actionIdentifier: "window.minimize"))

        // Help
        entries.append(MenuActionEntry(category: .help, title: "Keyboard Shortcuts", keyboardShortcut: "⌘/", actionIdentifier: "help.keyboardShortcuts"))
        entries.append(MenuActionEntry(category: .help, title: "Documentation",      keyboardShortcut: "",   actionIdentifier: "help.documentation"))
        entries.append(MenuActionEntry(category: .help, title: "About DICOM Studio", keyboardShortcut: "",   actionIdentifier: "help.about"))

        return entries
    }

    /// Returns entries filtered by the given category.
    public static func actions(for category: MenuCategory, in actions: [MenuActionEntry]) -> [MenuActionEntry] {
        actions.filter { $0.category == category }
    }
}

// MARK: - 14.3 Keyboard Shortcuts Helpers

/// Helpers for building and querying the keyboard shortcut catalog.
public enum KeyboardShortcutsHelpers: Sendable {

    /// Returns the default set of keyboard shortcuts.
    public static func defaultShortcuts() -> [KeyboardShortcutEntry] {
        var entries: [KeyboardShortcutEntry] = []

        // Global shortcuts
        entries.append(KeyboardShortcutEntry(scope: .global, shortcut: "⌘O",   action: "Open File",           actionIdentifier: "file.open"))
        entries.append(KeyboardShortcutEntry(scope: .global, shortcut: "⌘⇧F",  action: "Toggle Fullscreen",   actionIdentifier: "global.fullscreen"))
        entries.append(KeyboardShortcutEntry(scope: .global, shortcut: "⌘W",   action: "Close Window",        actionIdentifier: "global.closeWindow"))
        entries.append(KeyboardShortcutEntry(scope: .global, shortcut: "⌘,",   action: "Preferences",         actionIdentifier: "global.preferences"))
        entries.append(KeyboardShortcutEntry(scope: .global, shortcut: "⌘/",   action: "Keyboard Shortcuts Help", actionIdentifier: "global.shortcutsHelp"))

        // Viewer shortcuts
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘I",  action: "File Info",            actionIdentifier: "viewer.fileInfo"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘1",  action: "Window Preset 1",      actionIdentifier: "viewer.preset.1"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘2",  action: "Window Preset 2",      actionIdentifier: "viewer.preset.2"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘3",  action: "Window Preset 3",      actionIdentifier: "viewer.preset.3"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘4",  action: "Window Preset 4",      actionIdentifier: "viewer.preset.4"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘5",  action: "Window Preset 5",      actionIdentifier: "viewer.preset.5"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘6",  action: "Window Preset 6",      actionIdentifier: "viewer.preset.6"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘7",  action: "Window Preset 7",      actionIdentifier: "viewer.preset.7"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘8",  action: "Window Preset 8",      actionIdentifier: "viewer.preset.8"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "⌘9",  action: "Window Preset 9",      actionIdentifier: "viewer.preset.9"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "←",   action: "Previous Frame",       actionIdentifier: "viewer.previousFrame"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "→",   action: "Next Frame",           actionIdentifier: "viewer.nextFrame"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "↑",   action: "Previous Series",      actionIdentifier: "viewer.previousSeries"))
        entries.append(KeyboardShortcutEntry(scope: .viewer, shortcut: "↓",   action: "Next Series",          actionIdentifier: "viewer.nextSeries"))

        // Library shortcuts
        entries.append(KeyboardShortcutEntry(scope: .library, shortcut: "⌘F", action: "Search Library",       actionIdentifier: "library.search"))

        return entries
    }

    /// Returns shortcuts filtered by scope.
    public static func shortcuts(for scope: KeyboardShortcutScope, in shortcuts: [KeyboardShortcutEntry]) -> [KeyboardShortcutEntry] {
        shortcuts.filter { $0.scope == scope }
    }

    /// Returns the shortcut entry matching the given action identifier, or nil.
    public static func shortcut(for actionIdentifier: String, in shortcuts: [KeyboardShortcutEntry]) -> KeyboardShortcutEntry? {
        shortcuts.first { $0.actionIdentifier == actionIdentifier }
    }
}

// MARK: - 14.4 Dock Integration Helpers

/// Helpers for Dock badge management.
public enum DockIntegrationHelpers: Sendable {

    /// Returns the badge label string (empty when count is zero).
    public static func badgeLabel(for transferCount: Int) -> String {
        transferCount > 0 ? "\(transferCount)" : ""
    }

    /// Returns an accessibility label for the Dock badge.
    public static func badgeAccessibilityLabel(for transferCount: Int) -> String {
        transferCount > 0 ? "\(transferCount) active transfer\(transferCount == 1 ? "" : "s")" : "No active transfers"
    }
}

// MARK: - 14.5 Automation Helpers

/// Helpers for building and formatting automation script samples.
public enum AutomationHelpers: Sendable {

    /// Returns sample automation script entries.
    public static func sampleScriptEntries() -> [AutomationScriptEntry] {
        [
            AutomationScriptEntry(
                name: "Open DICOM File",
                description: "Opens a DICOM file in DICOM Studio using AppleScript.",
                scriptType: .appleScript,
                sampleScript: """
                tell application "DICOM Studio"
                    open POSIX file "/path/to/file.dcm"
                end tell
                """
            ),
            AutomationScriptEntry(
                name: "Batch Import with Shortcuts",
                description: "Imports a folder of DICOM files using the Shortcuts app.",
                scriptType: .shortcuts,
                sampleScript: "Use the 'Import DICOM Folder' action in the Shortcuts app and pass a folder path."
            ),
            AutomationScriptEntry(
                name: "Export Anonymised Files",
                description: "Uses the dicom-anon CLI tool to batch-anonymize files.",
                scriptType: .shellScript,
                sampleScript: """
                #!/bin/bash
                set -euo pipefail
                for f in /input/*.dcm; do
                    dicom-anon "$f" --output /output/
                done
                """
            ),
        ]
    }

    /// Returns the display name for an automation script type.
    public static func formatScriptType(_ type: AutomationScriptType) -> String {
        type.displayName
    }
}

// MARK: - 14.6 Quick Look Helpers

/// Helpers for Quick Look plugin status and guidance.
public enum QuickLookHelpers: Sendable {

    /// Returns the file extensions supported by the DICOM Quick Look plugin.
    public static func supportedExtensions() -> [String] {
        ["dcm", "dicom", "DCM", "DICOM"]
    }

    /// Returns brief installation instructions for the plugin.
    public static func installInstructions() -> String {
        """
        To install the DICOM Quick Look plugin:
        1. Download the DICOMKit QuickLook plugin package.
        2. Copy DICOMQuickLook.qlgenerator to ~/Library/QuickLook/ (user) or /Library/QuickLook/ (system-wide).
        3. Run: qlmanage -r
        4. Restart Finder.
        """
    }

    /// Builds a human-readable description of the current Quick Look state.
    public static func statusDescription(for state: QuickLookState) -> String {
        var parts: [String] = [state.status.description]
        if !state.supportedExtensions.isEmpty {
            parts.append("Supported extensions: \(state.supportedExtensions.joined(separator: ", "))")
        }
        parts.append("Cached thumbnails: \(state.thumbnailCacheCount)")
        if let refresh = state.lastRefreshDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            parts.append("Last refreshed: \(formatter.string(from: refresh))")
        }
        return parts.joined(separator: "\n")
    }
}
