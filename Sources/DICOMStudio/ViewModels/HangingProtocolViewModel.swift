// HangingProtocolViewModel.swift
// DICOMStudio
//
// DICOM Studio — Hanging Protocol ViewModel
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (editing state and protocol selection over HangingProtocolService; the modality it edits is free text)

import Foundation
import Observation

/// ViewModel for managing hanging protocol selection and editing.
///
/// Requires macOS 14+ / iOS 17+ for the `@Observable` macro.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class HangingProtocolViewModel {

    // MARK: - Protocol State

    /// All available protocols (user + built-in).
    public var allProtocols: [HangingProtocolModel] = []

    /// Currently active protocol.
    public var activeProtocol: HangingProtocolModel?

    /// User-defined protocols.
    public var userProtocols: [HangingProtocolModel] = []

    /// Whether a protocol is currently active.
    public var hasActiveProtocol: Bool {
        activeProtocol != nil
    }

    // MARK: - Layout State

    /// Current layout type.
    public var currentLayout: LayoutType = .single

    /// Custom grid columns (for custom layout).
    public var customColumns: Int = 1

    /// Custom grid rows (for custom layout).
    public var customRows: Int = 1

    // MARK: - Editing State

    /// Whether the protocol editor is open.
    public var isEditing: Bool = false

    /// Name for new/edited protocol.
    public var editingName: String = ""

    /// Modality for new/edited protocol.
    public var editingModality: String = ""

    /// Layout type for new/edited protocol.
    public var editingLayoutType: LayoutType = .single

    // MARK: - Services

    /// Hanging protocol service.
    public let hangingProtocolService: HangingProtocolService

    // MARK: - Initialization

    /// Creates a hanging protocol ViewModel.
    public init(hangingProtocolService: HangingProtocolService = HangingProtocolService()) {
        self.hangingProtocolService = hangingProtocolService
        refreshProtocols()
    }

    // MARK: - Protocol Management

    /// Refreshes the list of all available protocols.
    public func refreshProtocols() {
        allProtocols = hangingProtocolService.allProtocols(userProtocols: userProtocols)
    }

    /// Auto-selects the best protocol for a study.
    ///
    /// - Parameters:
    ///   - modality: Study modality.
    ///   - bodyPart: Body part examined.
    ///   - studyDescription: Study description.
    public func autoSelectProtocol(
        modality: String?,
        bodyPart: String? = nil,
        studyDescription: String? = nil
    ) {
        let selected = hangingProtocolService.selectProtocol(
            userProtocols: userProtocols,
            modality: modality,
            bodyPart: bodyPart,
            studyDescription: studyDescription
        )

        if let proto = selected {
            applyProtocol(proto)
        }
    }

    /// Applies a specific hanging protocol.
    ///
    /// - Parameter proto: The protocol to apply.
    public func applyProtocol(_ proto: HangingProtocolModel) {
        activeProtocol = proto
        currentLayout = proto.layoutType
        if proto.layoutType == .custom {
            customColumns = proto.customColumns ?? 1
            customRows = proto.customRows ?? 1
        }
    }

    /// Clears the active protocol and resets to single viewport.
    public func clearProtocol() {
        activeProtocol = nil
        currentLayout = .single
    }

    // MARK: - Layout Management

    /// Sets the layout type directly.
    ///
    /// - Parameter layout: Layout type to set.
    public func setLayout(_ layout: LayoutType) {
        currentLayout = layout
        if activeProtocol?.layoutType != layout {
            activeProtocol = nil
        }
    }

    /// Sets a custom grid layout.
    ///
    /// - Parameters:
    ///   - columns: Number of columns.
    ///   - rows: Number of rows.
    public func setCustomLayout(columns: Int, rows: Int) {
        currentLayout = .custom
        customColumns = max(1, min(4, columns))
        customRows = max(1, min(4, rows))
        activeProtocol = nil
    }

    // MARK: - Protocol Editing

    /// Opens the protocol editor for a new protocol.
    public func startNewProtocol() {
        isEditing = true
        editingName = ""
        editingModality = ""
        editingLayoutType = .single
    }

    /// Opens the protocol editor with existing protocol data.
    ///
    /// - Parameter proto: The protocol to edit.
    public func startEditingProtocol(_ proto: HangingProtocolModel) {
        isEditing = true
        editingName = proto.name
        editingModality = proto.matchingCriteria.modality ?? ""
        editingLayoutType = proto.layoutType
    }

    /// Saves the currently edited protocol.
    ///
    /// - Returns: The created protocol, or nil if invalid.
    @discardableResult
    public func saveEditedProtocol() -> HangingProtocolModel? {
        guard !editingName.isEmpty, !editingModality.isEmpty else { return nil }

        let proto = hangingProtocolService.createUserProtocol(
            name: editingName,
            layoutType: editingLayoutType,
            modality: editingModality,
            description: "User-defined protocol"
        )

        userProtocols.append(proto)
        isEditing = false
        refreshProtocols()
        return proto
    }

    /// Cancels protocol editing.
    public func cancelEditing() {
        isEditing = false
        editingName = ""
        editingModality = ""
        editingLayoutType = .single
    }

    /// Deletes a user-defined protocol.
    ///
    /// - Parameter id: Protocol ID to delete.
    public func deleteUserProtocol(_ id: UUID) {
        userProtocols.removeAll { $0.id == id }
        if activeProtocol?.id == id {
            activeProtocol = nil
        }
        refreshProtocols()
    }

    // MARK: - Display Text

    /// Returns the name of the active protocol.
    public var activeProtocolName: String {
        activeProtocol?.name ?? "None"
    }

    /// Returns the current layout description.
    public var layoutDescription: String {
        if currentLayout == .custom {
            return ViewportLayoutHelpers.layoutDescription(columns: customColumns, rows: customRows)
        }
        return ViewportLayoutHelpers.layoutDescription(for: currentLayout)
    }

    /// Effective columns for the current layout.
    public var effectiveColumns: Int {
        if currentLayout == .custom {
            return max(1, customColumns)
        }
        return currentLayout.columns
    }

    /// Effective rows for the current layout.
    public var effectiveRows: Int {
        if currentLayout == .custom {
            return max(1, customRows)
        }
        return currentLayout.rows
    }

    /// Effective cell count for the current layout.
    public var effectiveCellCount: Int {
        effectiveColumns * effectiveRows
    }
}
