// BrowserNavigationHelpers.swift
// DICOMStudio
//
// DICOM Studio — Helpers for Browser Navigation (Milestone 18)
// NEMA-verified: 2026a, checked 2026-10-05 — the 15 dicomStandardReference citations resolved against the 2026a DocBook section ids and titles (PS3.7 9.1.5 C-ECHO Service, PS3.4 C.4 / B.2 / K.6 / F.7 / H.4, PS3.7 7.1, PS3.3 C.17 / C.18 / C.7, PS3.15, PS3.10): 14 exist, "PS3.18 §6.5" does not exist in PS3.18 2026a (chapter 6 has no subsections) and is now §10 Studies Service; the 15 tool names are Sources/dicom-* targets; shortcuts, menus and layout carry no standard data

import Foundation

// MARK: - Browser Sidebar Helpers

/// Helpers for building and querying the sidebar browser's category / tool lists.
public enum BrowserSidebarHelpers: Sendable {

    /// Accessibility label for the sidebar root element.
    public static let sidebarAccessibilityLabel: String = "Tool Browser Sidebar"

    /// Creates one `BrowserCategory` per `ToolCategory` with its tool count.
    public static func buildCategories(from tools: [ToolInfo]) -> [BrowserCategory] {
        ToolCategory.allCases.map { category in
            let count = tools.filter { $0.category == category }.count
            return BrowserCategory(
                category: category,
                isExpanded: true,
                toolCount: count
            )
        }
    }

    /// Converts `ToolInfo` entries to `BrowserToolItem` entries, marking one as selected.
    public static func buildToolItems(
        from tools: [ToolInfo],
        selectedTool: String?
    ) -> [BrowserToolItem] {
        tools.map { tool in
            BrowserToolItem(
                toolName: tool.name,
                displayName: tool.displayName,
                category: tool.category,
                isAvailable: tool.availability == .available,
                isSelected: tool.name == selectedTool,
                sfSymbol: tool.category.sfSymbol,
                toolDescription: tool.toolDescription
            )
        }
    }

    /// Filters browser tool items to only those belonging to `category`.
    public static func toolsForCategory(
        _ category: ToolCategory,
        tools: [BrowserToolItem]
    ) -> [BrowserToolItem] {
        tools.filter { $0.category == category }
    }

    /// Returns a `CategoryExpansionState` with every category expanded.
    public static func defaultExpansionState() -> CategoryExpansionState {
        CategoryExpansionState()
    }

    /// Number of tools whose `isAvailable` flag is `true`.
    public static func availableToolCount(in tools: [BrowserToolItem]) -> Int {
        tools.filter(\.isAvailable).count
    }

    /// Number of tools whose `isAvailable` flag is `false`.
    public static func unavailableToolCount(in tools: [BrowserToolItem]) -> Int {
        tools.filter { !$0.isAvailable }.count
    }

    /// Summary string for a category, e.g. "4 tools (3 available)".
    public static func categorySummary(
        _ category: ToolCategory,
        tools: [BrowserToolItem]
    ) -> String {
        let categoryTools = toolsForCategory(category, tools: tools)
        let total = categoryTools.count
        let available = categoryTools.filter(\.isAvailable).count
        return "\(total) tool\(total == 1 ? "" : "s") (\(available) available)"
    }
}

// MARK: - Tool Search Helpers

/// Helpers for filtering and highlighting tool search results.
public enum ToolSearchHelpers: Sendable {

    /// Placeholder text for the search field.
    public static let searchPlaceholder: String = "Search tools…"

    /// Minimum query length required to trigger search filtering.
    public static let minSearchLength: Int = 1

    /// Filters `BrowserToolItem` entries by a case-insensitive match on name or description.
    public static func filterToolItems(
        _ items: [BrowserToolItem],
        query: String
    ) -> [BrowserToolItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minSearchLength else { return items }
        let lower = trimmed.lowercased()
        return items.filter { item in
            item.toolName.lowercased().contains(lower)
                || item.displayName.lowercased().contains(lower)
                || item.toolDescription.lowercased().contains(lower)
        }
    }

    /// Returns the original text and the `Range` of the first case-insensitive match, if any.
    public static func highlightMatch(
        in text: String,
        query: String
    ) -> (text: String, matchRange: Range<String.Index>?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (text, nil) }
        let range = text.range(of: trimmed, options: .caseInsensitive)
        return (text, range)
    }

    /// Whether at least one item matches the query.
    public static func hasMatchingTools(
        _ items: [BrowserToolItem],
        query: String
    ) -> Bool {
        !filterToolItems(items, query: query).isEmpty
    }

    /// Number of items matching the query.
    public static func searchResultCount(
        _ items: [BrowserToolItem],
        query: String
    ) -> Int {
        filterToolItems(items, query: query).count
    }
}

// MARK: - Content Layout Helpers

/// Helpers for managing the tabbed content area layout.
public enum ContentLayoutHelpers: Sendable {

    /// Builds `ContentTab` entries from a list of tool names, marking one as active.
    public static func buildContentTabs(
        for tools: [String],
        selectedTool: String?
    ) -> [ContentTab] {
        tools.map { name in
            let display = ToolRegistryHelpers.toolDisplayName(for: name)
            let category = ToolRegistryHelpers.toolCategory(for: name)
            return ContentTab(
                toolName: name,
                displayName: display,
                sfSymbol: category.sfSymbol,
                isActive: name == selectedTool
            )
        }
    }

    /// Returns header information for the given tool name.
    public static func toolHeaderInfo(for toolName: String) -> ToolHeaderInfo {
        let display = ToolRegistryHelpers.toolDisplayName(for: toolName)
        let category = ToolRegistryHelpers.toolCategory(for: toolName)
        let description = ToolRegistryHelpers.toolDescription(for: toolName)
        let standardRef = dicomStandardReference(for: toolName)
        return ToolHeaderInfo(
            toolName: toolName,
            displayName: display,
            briefDescription: description,
            dicomStandardRef: standardRef,
            sfSymbol: category.sfSymbol,
            category: category
        )
    }

    /// The default layout shown when no tool is selected.
    public static func defaultLayout() -> ContentLayout {
        .welcome
    }

    /// Returns `.welcome` when no tool is selected, `.parameterAndTerminal` otherwise.
    public static func layoutForTool(_ toolName: String?) -> ContentLayout {
        guard toolName != nil else { return .welcome }
        return .parameterAndTerminal
    }

    /// Accessibility label describing the content area for the given tool.
    public static func contentAccessibilityLabel(for toolName: String?) -> String {
        guard let name = toolName else {
            return "Welcome screen"
        }
        let display = ToolRegistryHelpers.toolDisplayName(for: name)
        return "\(display) tool content area"
    }

    // MARK: Private

    /// Maps tools to the DICOM 2026a clause they implement (section ids checked by Scripts/diff_studio_g1_shell.py).
    /// dicom-wado is the Studies Service (WADO-RS, QIDO-RS, STOW-RS, PS3.18 §10); its UPS-RS half is §11.
    private static func dicomStandardReference(for toolName: String) -> String? {
        switch toolName {
        case "dicom-echo":     return "PS3.7 §9.1.5"
        case "dicom-query":    return "PS3.4 §C.4"
        case "dicom-send":     return "PS3.4 §B.2"
        case "dicom-retrieve": return "PS3.4 §C.4"
        case "dicom-qr":      return "PS3.4 §C.4"
        case "dicom-wado":     return "PS3.18 §10"
        case "dicom-mwl":      return "PS3.4 §K.6"
        case "dicom-mpps":     return "PS3.4 §F.7"
        case "dicom-print":    return "PS3.4 §H.4"
        case "dicom-gateway":  return "PS3.15"
        case "dicom-server":   return "PS3.7 §7.1"
        case "dicom-validate": return "PS3.10"
        case "dicom-report":   return "PS3.3 §C.17"
        case "dicom-measure":  return "PS3.3 §C.18"
        case "dicom-study":    return "PS3.3 §C.7"
        default:               return nil
        }
    }
}

// MARK: - Welcome View Helpers

/// Helpers for the welcome / empty-state screen.
public enum WelcomeViewHelpers: Sendable {

    /// Maximum number of recent tool entries to keep.
    public static let maxRecentTools: Int = 5

    /// Returns a curated list of keyboard shortcuts for the shortcuts reference.
    public static func defaultKeyboardShortcuts() -> [KeyboardShortcutInfo] {
        [
            // Execution
            KeyboardShortcutInfo(action: "Run Tool", shortcut: "⌘R", category: "Execution"),
            KeyboardShortcutInfo(action: "Stop Execution", shortcut: "⌘.", category: "Execution"),
            KeyboardShortcutInfo(action: "Clear Terminal", shortcut: "⌘K", category: "Execution"),
            // File
            KeyboardShortcutInfo(action: "Open File", shortcut: "⌘O", category: "File"),
            KeyboardShortcutInfo(action: "Save Output", shortcut: "⌘S", category: "File"),
            // Navigation
            KeyboardShortcutInfo(action: "Toggle Sidebar", shortcut: "⌘⇧S", category: "Navigation"),
            KeyboardShortcutInfo(action: "Search Tools", shortcut: "⌘F", category: "Navigation"),
            KeyboardShortcutInfo(action: "Networking", shortcut: "⌘1", category: "Navigation"),
            KeyboardShortcutInfo(action: "Viewer & Imaging", shortcut: "⌘2", category: "Navigation"),
            KeyboardShortcutInfo(action: "File Inspection", shortcut: "⌘3", category: "Navigation"),
            KeyboardShortcutInfo(action: "File Processing", shortcut: "⌘4", category: "Navigation"),
            KeyboardShortcutInfo(action: "File Organization", shortcut: "⌘5", category: "Navigation"),
            KeyboardShortcutInfo(action: "Data Exchange", shortcut: "⌘6", category: "Navigation"),
            KeyboardShortcutInfo(action: "Clinical", shortcut: "⌘7", category: "Navigation"),
            KeyboardShortcutInfo(action: "Utilities", shortcut: "⌘8", category: "Navigation"),
            KeyboardShortcutInfo(action: "Cloud & AI", shortcut: "⌘9", category: "Navigation"),
        ]
    }

    /// Formats a `Date` as a relative description such as "2 hours ago" or "Yesterday".
    public static func formatRecentToolDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        }
        let hours = Int(interval / 3600)
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        let days = Int(interval / 86400)
        if days == 1 {
            return "Yesterday"
        }
        if days < 7 {
            return "\(days) days ago"
        }
        let weeks = days / 7
        if weeks < 4 {
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        }
        let months = days / 30
        if months < 12 {
            return "\(months) month\(months == 1 ? "" : "s") ago"
        }
        let years = days / 365
        return "\(years) year\(years == 1 ? "" : "s") ago"
    }

    /// Default welcome message shown when no tool is selected.
    public static func welcomeMessage() -> String {
        "Select a tool from the sidebar to begin"
    }

    /// Current application version string.
    public static func appVersion() -> String {
        "DICOM Studio v2.0.0"
    }

    /// Trims the list to at most `maxRecentTools`, keeping the most recent entries.
    public static func trimRecentTools(
        _ entries: [RecentToolEntry]
    ) -> [RecentToolEntry] {
        let sorted = entries.sorted { $0.lastUsed > $1.lastUsed }
        return Array(sorted.prefix(maxRecentTools))
    }

    /// Adds a new recent-tool entry and trims to `maxRecentTools`.
    ///
    /// If an entry for the same tool already exists it is replaced with the new timestamp.
    public static func addRecentTool(
        name: String,
        displayName: String,
        sfSymbol: String,
        to entries: [RecentToolEntry]
    ) -> [RecentToolEntry] {
        var updated = entries.filter { $0.toolName != name }
        updated.insert(
            RecentToolEntry(
                toolName: name,
                displayName: displayName,
                sfSymbol: sfSymbol
            ),
            at: 0
        )
        return trimRecentTools(updated)
    }
}

// MARK: - Browser Menu Bar Helpers

/// Helpers for constructing the application menu bar items.
public enum BrowserMenuBarHelpers: Sendable {

    /// Builds menu items for the Tools menu, grouped by `ToolCategory`.
    public static func buildToolsMenuItems(
        from tools: [ToolInfo]
    ) -> [AppMenuItem] {
        var items: [AppMenuItem] = []
        let grouped = ToolRegistryHelpers.toolsByCategory(tools)
        for (index, group) in grouped.enumerated() {
            let shortcut = shortcutForCategory(group.category)
            items.append(AppMenuItem(
                title: group.category.displayName,
                shortcut: shortcut,
                sfSymbol: group.category.sfSymbol,
                category: "Tools",
                isEnabled: true
            ))
            for tool in group.tools {
                items.append(AppMenuItem(
                    title: tool.displayName,
                    sfSymbol: tool.category.sfSymbol,
                    category: group.category.displayName,
                    isEnabled: tool.availability == .available
                ))
            }
            if index < grouped.count - 1 {
                items.append(AppMenuItem(
                    title: "---",
                    category: "Tools",
                    isEnabled: false
                ))
            }
        }
        return items
    }

    /// Builds menu items for the Server menu.
    public static func buildServerMenuItems(serverCount: Int) -> [AppMenuItem] {
        [
            AppMenuItem(
                title: "Server Configuration…",
                shortcut: "⌘⇧C",
                sfSymbol: "server.rack",
                category: "Server"
            ),
            AppMenuItem(
                title: "Connect to Server…",
                shortcut: "⌘⇧N",
                sfSymbol: "bolt.horizontal.circle",
                category: "Server"
            ),
            AppMenuItem(title: "---", category: "Server", isEnabled: false),
            AppMenuItem(
                title: "Active Servers (\(serverCount))",
                sfSymbol: "circle.fill",
                category: "Server",
                isEnabled: serverCount > 0
            ),
            AppMenuItem(
                title: "Disconnect All",
                sfSymbol: "xmark.circle",
                category: "Server",
                isEnabled: serverCount > 0
            ),
        ]
    }

    /// Builds menu items for the View menu based on current sidebar state.
    public static func buildViewMenuItems(sidebarState: SidebarState) -> [AppMenuItem] {
        let toggleTitle = sidebarState.isExpanded ? "Hide Sidebar" : "Show Sidebar"
        return [
            AppMenuItem(
                title: toggleTitle,
                shortcut: "⌘⇧S",
                sfSymbol: "sidebar.left",
                category: "View"
            ),
            AppMenuItem(title: "---", category: "View", isEnabled: false),
            AppMenuItem(
                title: "Parameter & Terminal",
                shortcut: "⌘⌥1",
                sfSymbol: ContentLayout.parameterAndTerminal.sfSymbol,
                category: "View"
            ),
            AppMenuItem(
                title: "Parameter Only",
                shortcut: "⌘⌥2",
                sfSymbol: ContentLayout.parameterOnly.sfSymbol,
                category: "View"
            ),
            AppMenuItem(
                title: "Terminal Only",
                shortcut: "⌘⌥3",
                sfSymbol: ContentLayout.terminalOnly.sfSymbol,
                category: "View"
            ),
            AppMenuItem(title: "---", category: "View", isEnabled: false),
            AppMenuItem(
                title: "Increase Font Size",
                shortcut: "⌘+",
                sfSymbol: "textformat.size.larger",
                category: "View"
            ),
            AppMenuItem(
                title: "Decrease Font Size",
                shortcut: "⌘-",
                sfSymbol: "textformat.size.smaller",
                category: "View"
            ),
        ]
    }

    /// Returns the keyboard shortcut for jumping to a category, or `nil` if none.
    ///
    /// Categories are numbered `⌘1` through `⌘9` in `ToolCategory.allCases` order.
    public static func shortcutForCategory(_ category: ToolCategory) -> String? {
        guard let index = ToolCategory.allCases.firstIndex(of: category) else {
            return nil
        }
        let number = index + 1
        guard number <= 9 else { return nil }
        return "⌘\(number)"
    }

    /// Accessibility label for a menu item, incorporating its shortcut if present.
    public static func menuAccessibilityLabel(for item: AppMenuItem) -> String {
        if let shortcut = item.shortcut {
            return "\(item.title), shortcut \(shortcut)"
        }
        return item.title
    }
}
