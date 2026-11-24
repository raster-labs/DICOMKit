// StudioWindowCommands.swift
// DICOMStudio
//
// DICOM Studio — Window menu entries for the app's auxiliary windows.
//
// The Printer Emulator and the Print Preview are opened from inside the app —
// the sidebar entry, the viewer's print action — and both are declared with
// `.restorationBehavior(.disabled)` and `.defaultLaunchBehavior(.suppressed)`
// so a cold launch shows the study library instead of an emulator nobody asked
// for. That is right at launch, but it also means macOS never brings them back
// on its own: clicking the Dock icon reopens only the main window, and a closed
// emulator has no menu entry to reopen it from. These commands are that entry.
// They sit above the Window menu's own window list, so both windows are always
// one menu away whether they are closed, buried, or on another display.

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

/// Window menu entries that open — or raise, when they already exist — the
/// printer emulator and the print preview.
///
/// `openWindow(id:)` on a single `Window` scene raises the existing window
/// rather than making a second one, so these are both "open" and "bring to
/// front" in one command, which is what the Window menu is for.
@available(macOS 14.0, *)
public struct StudioWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Commands {
        // `.windowList` is the group holding the Window menu's own list of open
        // windows; placing these before it keeps them above that list, next to
        // "Bring All to Front", where a reopen command is looked for.
        CommandGroup(before: .windowList) {
            Button("Printer Emulator") {
                openWindow(id: StudioWindowID.printerEmulator)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Print Preview") {
                openWindow(id: StudioWindowID.printPreview)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Structured Reports") {
                openWindow(id: StudioWindowID.structuredReports)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()
        }
    }
}
#endif
