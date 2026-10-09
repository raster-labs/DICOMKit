// BrowserNavigationModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Browser Navigation (Milestone 18)
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (sidebar, tab, window, menu and welcome-screen state; the only standard mention is the dicomStandardRef doc example "PS3.7 §9.1.5", which is the C-ECHO Service of PS3.7 2026a); the tool-name values it holds are verified where they are produced (CLIShellFoundationHelpers, BrowserNavigationHelpers)

import Foundation

// MARK: - 18.1 Sidebar Browser

/// A browser category entry that groups tools by their `ToolCategory`.
public struct BrowserCategory: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// The tool category this entry represents.
    public let category: ToolCategory

    /// Whether this category is currently expanded in the sidebar.
    public let isExpanded: Bool

    /// Number of tools belonging to this category.
    public let toolCount: Int

    /// Creates a new browser category entry.
    public init(
        id: UUID = UUID(),
        category: ToolCategory,
        isExpanded: Bool = true,
        toolCount: Int = 0
    ) {
        self.id = id
        self.category = category
        self.isExpanded = isExpanded
        self.toolCount = toolCount
    }
}

/// A single tool item displayed within the sidebar browser.
public struct BrowserToolItem: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Executable name (e.g. `dicom-echo`).
    public let toolName: String

    /// Human-readable display name (e.g. "DICOM Echo").
    public let displayName: String

    /// The category this tool belongs to.
    public let category: ToolCategory

    /// Whether the tool binary is available on the system.
    public let isAvailable: Bool

    /// Whether this tool is currently selected in the sidebar.
    public let isSelected: Bool

    /// SF Symbol name for this tool.
    public let sfSymbol: String

    /// Brief description of what the tool does.
    public let toolDescription: String

    /// Creates a new browser tool item.
    public init(
        id: UUID = UUID(),
        toolName: String,
        displayName: String,
        category: ToolCategory,
        isAvailable: Bool = true,
        isSelected: Bool = false,
        sfSymbol: String,
        toolDescription: String
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.category = category
        self.isAvailable = isAvailable
        self.isSelected = isSelected
        self.sfSymbol = sfSymbol
        self.toolDescription = toolDescription
    }
}

/// Controls which tools are shown in the sidebar.
public enum SidebarDisplayMode: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case allTools       = "ALL_TOOLS"
    case availableOnly  = "AVAILABLE_ONLY"
    case searchResults  = "SEARCH_RESULTS"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .allTools:      return "All Tools"
        case .availableOnly: return "Available Only"
        case .searchResults: return "Search Results"
        }
    }
}

/// Tracks which categories are expanded or collapsed in the sidebar.
public struct CategoryExpansionState: Sendable, Hashable {
    /// Set of raw-value identifiers for expanded categories.
    public var expandedCategoryIDs: Set<String>

    /// Creates a new expansion state.
    ///
    /// By default all categories are expanded.
    public init(expandedCategoryIDs: Set<String>? = nil) {
        self.expandedCategoryIDs = expandedCategoryIDs
            ?? Set(ToolCategory.allCases.map(\.rawValue))
    }

    /// Whether the given category is currently expanded.
    public func isExpanded(_ category: ToolCategory) -> Bool {
        expandedCategoryIDs.contains(category.rawValue)
    }

    /// Toggles the expansion state for the given category.
    public mutating func toggle(_ category: ToolCategory) {
        if expandedCategoryIDs.contains(category.rawValue) {
            expandedCategoryIDs.remove(category.rawValue)
        } else {
            expandedCategoryIDs.insert(category.rawValue)
        }
    }

    /// Expands all categories.
    public mutating func expandAll() {
        expandedCategoryIDs = Set(ToolCategory.allCases.map(\.rawValue))
    }

    /// Collapses all categories.
    public mutating func collapseAll() {
        expandedCategoryIDs.removeAll()
    }
}

// MARK: - 18.2 Tabbed Content Area

/// A tab in the content area representing an open tool.
public struct ContentTab: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Executable name of the tool this tab represents.
    public let toolName: String

    /// Human-readable display name shown on the tab.
    public let displayName: String

    /// SF Symbol name for the tab icon.
    public let sfSymbol: String

    /// Whether this tab is the currently active (visible) tab.
    public let isActive: Bool

    /// Creates a new content tab.
    public init(
        id: UUID = UUID(),
        toolName: String,
        displayName: String,
        sfSymbol: String,
        isActive: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.sfSymbol = sfSymbol
        self.isActive = isActive
    }
}

/// Layout options for the tool content area.
public enum ContentLayout: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case parameterAndTerminal = "PARAMETER_AND_TERMINAL"
    case parameterOnly        = "PARAMETER_ONLY"
    case terminalOnly         = "TERMINAL_ONLY"
    case welcome              = "WELCOME"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .parameterAndTerminal: return "Parameter & Terminal"
        case .parameterOnly:        return "Parameter Only"
        case .terminalOnly:         return "Terminal Only"
        case .welcome:              return "Welcome"
        }
    }

    /// SF Symbol name for this layout option.
    public var sfSymbol: String {
        switch self {
        case .parameterAndTerminal: return "rectangle.split.2x1"
        case .parameterOnly:        return "slider.horizontal.3"
        case .terminalOnly:         return "terminal"
        case .welcome:              return "house"
        }
    }
}

/// Header information displayed at the top of a tool's content area.
public struct ToolHeaderInfo: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Executable name (e.g. `dicom-echo`).
    public let toolName: String

    /// Human-readable display name (e.g. "DICOM Echo").
    public let displayName: String

    /// Short description of the tool's purpose.
    public let briefDescription: String

    /// Optional reference to the relevant DICOM standard section (e.g. "PS3.7 §9.1.5").
    public let dicomStandardRef: String?

    /// SF Symbol name for the tool icon.
    public let sfSymbol: String

    /// Category this tool belongs to.
    public let category: ToolCategory

    /// Creates a new tool header info entry.
    public init(
        id: UUID = UUID(),
        toolName: String,
        displayName: String,
        briefDescription: String,
        dicomStandardRef: String? = nil,
        sfSymbol: String,
        category: ToolCategory
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.briefDescription = briefDescription
        self.dicomStandardRef = dicomStandardRef
        self.sfSymbol = sfSymbol
        self.category = category
    }
}

// MARK: - 18.3 Main Window Layout

/// Expansion state of the sidebar.
public enum SidebarState: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case expanded  = "EXPANDED"
    case collapsed = "COLLAPSED"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .expanded:  return "Expanded"
        case .collapsed: return "Collapsed"
        }
    }

    /// Whether the sidebar is in the expanded state.
    public var isExpanded: Bool {
        self == .expanded
    }
}

/// Configuration for the main application window dimensions.
public struct WindowConfiguration: Sendable, Hashable {
    /// Default window width in points.
    public let width: Double

    /// Default window height in points.
    public let height: Double

    /// Minimum allowed window width in points.
    public let minWidth: Double

    /// Minimum allowed window height in points.
    public let minHeight: Double

    /// Default sidebar width in points.
    public let sidebarWidth: Double

    /// Minimum allowed sidebar width in points.
    public let sidebarMinWidth: Double

    /// Creates a new window configuration with sensible defaults.
    public init(
        width: Double = 1400,
        height: Double = 900,
        minWidth: Double = 1024,
        minHeight: Double = 768,
        sidebarWidth: Double = 260,
        sidebarMinWidth: Double = 220
    ) {
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.sidebarWidth = sidebarWidth
        self.sidebarMinWidth = sidebarMinWidth
    }
}

/// A single item in the application menu bar.
public struct AppMenuItem: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Menu item title.
    public let title: String

    /// Optional keyboard shortcut (e.g. "⌘N").
    public let shortcut: String?

    /// Optional SF Symbol name for the menu item icon.
    public let sfSymbol: String?

    /// Optional category for grouping related menu items.
    public let category: String?

    /// Whether this menu item is currently enabled.
    public let isEnabled: Bool

    /// Creates a new app menu item.
    public init(
        id: UUID = UUID(),
        title: String,
        shortcut: String? = nil,
        sfSymbol: String? = nil,
        category: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.sfSymbol = sfSymbol
        self.category = category
        self.isEnabled = isEnabled
    }
}

/// Top-level menu categories in the browser navigation menu bar.
///
/// Extends the base menu categories with a server-specific entry.
public enum BrowserMenuCategory: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case tools  = "TOOLS"
    case server = "SERVER"
    case view   = "VIEW"
    case edit   = "EDIT"
    case window = "WINDOW"
    case help   = "HELP"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .tools:  return "Tools"
        case .server: return "Server"
        case .view:   return "View"
        case .edit:   return "Edit"
        case .window: return "Window"
        case .help:   return "Help"
        }
    }
}

// MARK: - 18.4 Empty States & Onboarding

/// Actions available on the welcome screen.
public enum WelcomeAction: Sendable, Equatable {
    /// Select a tool from the sidebar.
    case selectTool
    /// Open a recently used tool by name.
    case openRecentTool(String)
    /// Show the keyboard shortcuts reference.
    case showKeyboardShortcuts
    /// Open the DICOM server configuration.
    case openServerConfig

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .selectTool:                return "Select a Tool"
        case .openRecentTool(let name):  return "Open \(name)"
        case .showKeyboardShortcuts:     return "Keyboard Shortcuts"
        case .openServerConfig:          return "Server Configuration"
        }
    }

    /// SF Symbol name for this action.
    public var sfSymbol: String {
        switch self {
        case .selectTool:            return "sidebar.left"
        case .openRecentTool:        return "clock.arrow.circlepath"
        case .showKeyboardShortcuts: return "keyboard"
        case .openServerConfig:      return "server.rack"
        }
    }
}

/// A recently used tool entry for the welcome screen.
public struct RecentToolEntry: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Executable name (e.g. `dicom-echo`).
    public let toolName: String

    /// Human-readable display name (e.g. "DICOM Echo").
    public let displayName: String

    /// Timestamp of when this tool was last used.
    public let lastUsed: Date

    /// SF Symbol name for the tool icon.
    public let sfSymbol: String

    /// Creates a new recent tool entry.
    public init(
        id: UUID = UUID(),
        toolName: String,
        displayName: String,
        lastUsed: Date = Date(),
        sfSymbol: String
    ) {
        self.id = id
        self.toolName = toolName
        self.displayName = displayName
        self.lastUsed = lastUsed
        self.sfSymbol = sfSymbol
    }
}

/// A keyboard shortcut description for the shortcuts reference.
public struct KeyboardShortcutInfo: Sendable, Identifiable, Hashable {
    /// Unique identifier.
    public let id: UUID

    /// Human-readable action name (e.g. "Toggle Sidebar").
    public let action: String

    /// Shortcut key combination (e.g. "⌘⇧S").
    public let shortcut: String

    /// Grouping category (e.g. "Navigation", "Editing").
    public let category: String

    /// Creates a new keyboard shortcut info entry.
    public init(
        id: UUID = UUID(),
        action: String,
        shortcut: String,
        category: String
    ) {
        self.id = id
        self.action = action
        self.shortcut = shortcut
        self.category = category
    }
}

/// Actions offered when a tool is unavailable.
public enum ToolUnavailableAction: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case installNow      = "INSTALL_NOW"
    case openInTerminal  = "OPEN_IN_TERMINAL"
    case skipTool        = "SKIP_TOOL"
    case showAlternative = "SHOW_ALTERNATIVE"

    public var id: String { rawValue }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .installNow:      return "Install Now"
        case .openInTerminal:  return "Open in Terminal"
        case .skipTool:        return "Skip Tool"
        case .showAlternative: return "Show Alternative"
        }
    }

    /// SF Symbol name for this action.
    public var sfSymbol: String {
        switch self {
        case .installNow:      return "arrow.down.circle"
        case .openInTerminal:  return "terminal"
        case .skipTool:        return "forward.end"
        case .showAlternative: return "arrow.triangle.branch"
        }
    }
}
