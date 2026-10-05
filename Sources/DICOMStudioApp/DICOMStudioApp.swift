// DICOMStudioApp.swift
// DICOMStudioApp
//
// DICOM Studio — macOS application entry point

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import DICOMStudio

/// DICOM Studio macOS application entry point.
///
/// Provides the `@main` entry for the macOS SwiftUI app,
/// referencing views and view-models from the DICOMStudio library.
@main
struct DICOMStudioApp: App {
    @State private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
        }
        .defaultSize(width: 1200, height: 800)
        // Window can shrink to the content's minimum and grow without limit,
        // so the app adapts to any display from a small laptop to an
        // ultrawide. `.contentMinSize` keeps only the lower bound enforced.
        .windowResizability(.contentMinSize)
        .commands { ViewerCommands() }
        // The emulator and the preview are suppressed at launch and not
        // restored, so macOS never reopens them on its own — a Dock click
        // brings back only this window. These commands are how both stay
        // reachable once they have been closed or buried.
        .commands { StudioWindowCommands() }

        // The printer emulator is watched while a print is being sent from the
        // main window, so it is a window rather than a detail pane. A single
        // `Window`, not a `WindowGroup`: there is one emulator, and choosing the
        // sidebar entry again raises the window that exists instead of opening a
        // second view onto the same server.
        Window("Printer Emulator", id: StudioWindowID.printerEmulator) {
            PrintSCPView(viewModel: viewModel.printSCPViewModel)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 880)
        .windowResizability(.contentMinSize)
        // Restored at launch it comes up with the server stopped and no films —
        // an emulator nobody asked for, over the study list. A launch shows the
        // library; the emulator opens from the sidebar, when it is wanted.
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        // The print preview is held up against the images it was made from, so
        // it is a window rather than a sheet over the viewer — it can sit beside
        // the viewer or move to a second display. One `Window`, not a
        // `WindowGroup`: there is one print job being composed, and printing
        // again raises the window that already has it.
        Window("Print Preview", id: StudioWindowID.printPreview) {
            PrintSettingsView(viewModel: viewModel.printViewModel,
                              presentation: .window)
        }
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentMinSize)
        // The window belongs to a print job, and a print job does not survive
        // the app: restored at launch it comes up holding no marks at all. It
        // opens when something is sent to it and not before.
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(viewModel: SettingsViewModel(settingsService: viewModel.settingsService))
        }
    }
}
#else
@main
struct DICOMStudioAppLauncher {
    static func main() {
        print("DICOM Studio requires macOS 14.0 or later with SwiftUI support.")
    }
}
#endif
