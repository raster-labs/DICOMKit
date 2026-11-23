// PrintSCPWindow.swift
// DICOMStudio
//
// DICOM Studio — the printer emulator as a window of its own.
//
// The emulator is watched while something else is being done: a print is sent
// from the Print screen, or an SCU is being debugged in another app, and the
// film that comes back has to be visible at the same time. A detail pane inside
// the split view can only ever be the one thing on screen, so the emulator gets
// a real window and the navigation entry becomes the switch that raises it.

#if canImport(SwiftUI)
import SwiftUI

/// Identifiers of the app's auxiliary windows.
public enum StudioWindowID: Sendable {
    /// The printer emulator window.
    public static let printerEmulator = "printer-emulator"

    /// The print preview window.
    ///
    /// The film is judged against what is on screen in the viewer — the layout
    /// it mirrors, the window/level a cell was captured with — and a sheet
    /// covers exactly that. So the preview is a window: it can sit beside the
    /// viewer, be moved to a second display, or be zoomed to fill one.
    public static let printPreview = "print-preview"

    /// The standalone Structured Reports window.
    ///
    /// Opened alongside the Image Viewer so the clinician can inspect images
    /// and author or review a DICOM Structured Report side-by-side.
    public static let structuredReports = "structured-reports"
}

/// What the Printer Emulator navigation entry shows in the main window: a card
/// explaining where the emulator went, and the button that brings it back.
///
/// The window is raised as soon as the entry is chosen, so this is what remains
/// behind it — not a dead end, but the way back when the window has been closed
/// or is buried behind the main one.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct PrintSCPLauncherView: View {
    @Bindable var viewModel: PrintSCPViewModel

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(viewModel: PrintSCPViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(macOS)
        ContentUnavailableView {
            Label("Printer Emulator", systemImage: "printer")
        } description: {
            Text("The emulator runs in its own window so received film stays "
                 + "visible while you work here.\n"
                 + viewModel.statusMessage)
        } actions: {
            Button {
                open()
            } label: {
                Label("Open Emulator Window", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .navigationTitle("Printer Emulator")
        .onAppear { open() }
        #else
        PrintSCPView(viewModel: viewModel)
        #endif
    }

    #if os(macOS)
    private func open() {
        openWindow(id: StudioWindowID.printerEmulator)
    }
    #endif
}
#endif
