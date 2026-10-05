// MainView.swift
// DICOMStudio
//
// DICOM Studio — Main application shell with NavigationSplitView
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (navigation shell and library/presentation-series bookkeeping)

#if canImport(SwiftUI)
import SwiftUI

/// The main application view providing sidebar navigation and detail content.
///
/// Uses `NavigationSplitView` with three columns:
/// - Sidebar: Feature area list with icons
/// - Detail: Content for the selected feature area
@available(macOS 14.0, iOS 17.0, *)
public struct MainView: View {
    @Bindable var viewModel: MainViewModel

    /// The shell owns the split's column visibility so the sidebar is shown on
    /// launch and never disappears by accident. Without this, NavigationSplitView is
    /// free to drop to `.detailOnly` whenever a detail view (e.g. the wide CLI Parity
    /// / network forms) demands more width than the window can spare — and macOS then
    /// persists that collapsed state, so the navigation sidebar goes missing on the
    /// landing page across launches. Defaulting to `.all` (and pinning the sidebar's
    /// column width in SidebarView) keeps it visible while leaving the toolbar toggle
    /// free to collapse it on demand.
    ///
    /// The viewer is the one deliberate exception, driven from `onChange` below.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
        // Launching straight into the viewer — a file opened from the Finder,
        // say — never crosses `onChange`, so the sidebar has to start collapsed
        // rather than be collapsed on arrival.
        _columnVisibility = State(
            initialValue: viewModel.selectedDestination == .viewer ? .detailOnly : .all)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel)
        } detail: {
            if let destination = viewModel.selectedDestination {
                detailView(for: destination)
            } else {
                ContentUnavailableView(
                    "Select a Feature",
                    systemImage: "sidebar.left",
                    description: Text("Choose a feature area from the sidebar to get started.")
                )
            }
        }
        .navigationTitle("DICOM Studio")
        // The viewer reads full-width. Every other screen is a feature being
        // used, and the feature list beside it is how the user got there and
        // where they go next; the viewer is the one screen whose subject is the
        // picture, and the list of everything the app can do is chrome charged
        // against it. So the sidebar steps aside on the way in and comes back on
        // the way out — the toolbar toggle still opens it over the images for
        // anyone who wants it, and that choice survives until the viewer is left.
        .onChange(of: viewModel.selectedDestination) { _, destination in
            columnVisibility = destination == .viewer ? .detailOnly : .all
        }
        .modifier(PresentationSeriesLibrarySync(viewModel: viewModel))
        #if os(macOS)
        // Opening a study clears the print marks, and the print preview window
        // was composed from the study being left — so it comes down with them
        // rather than staying up over a different patient's images.
        //
        // Watched here rather than in the viewer: the study may be opened while
        // the library is on screen, and the viewer that would have seen the
        // signal does not exist until a moment later.
        .onChange(of: viewModel.imageViewerViewModel.printScreenDismissRequests) { _, _ in
            dismissWindow(id: StudioWindowID.printPreview)
        }
        #endif
    }

    @ViewBuilder
    private func detailView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .library:
            StudyBrowserView(viewModel: viewModel.studyBrowserViewModel)
                .id(NavigationDestination.library)
        case .viewer:
            ImageViewerView(viewModel: viewModel.imageViewerViewModel,
                            printViewModel: viewModel.printViewModel)
        case .volumeViewer:
            DICOMVolumeViewerView(viewModel: viewModel.volumeViewerViewModel)
        case .jp3dComparison:
            JP3DComparisonView(viewModel: viewModel.jp3dComparisonViewModel)
        case .aiAnalysis:
            AIAnalysisView(viewModel: viewModel.aiAnalysisViewModel)
        case .networking:
            NetworkingView(viewModel: viewModel.networkingViewModel)
        case .dicomWeb:
            DICOMwebView(viewModel: viewModel.dicomWebViewModel)
        case .cloudIntegration:
            CloudIntegrationView(viewModel: viewModel.cloudIntegrationViewModel)
        case .gateway:
            GatewayView(viewModel: viewModel.gatewayViewModel)
        case .reporting:
            StructuredReportView(viewModel: StructuredReportViewModel())
        case .printing:
            PrintCenterView(viewModel: viewModel.printViewModel)
        case .printSCP:
            // The emulator is a window of its own — this entry raises it.
            PrintSCPLauncherView(viewModel: viewModel.printSCPViewModel)
        case .tools:
            DataExchangeView(viewModel: DataExchangeViewModel())
        case .validation:
            ValidationView(viewModel: viewModel.validationViewModel)
        case .archiveManagement:
            ArchiveManagementView(viewModel: viewModel.archiveManagementViewModel)
        case .cliWorkshop:
            CLIWorkshopView(viewModel: viewModel.cliWorkshopViewModel)
                .onAppear {
                    viewModel.cliWorkshopViewModel.savedServerProfiles = viewModel.networkingViewModel.serverProfiles
                }
        case .networkUtility:
            NetworkUtilityView(viewModel: viewModel.networkUtilityViewModel)
        case .security:
            SecurityView(viewModel: SecurityViewModel())
        case .performanceTools:
            PerformanceToolsView(viewModel: PerformanceToolsViewModel())
        case .macOSEnhancements:
            MacOSEnhancementsView(viewModel: MacOSEnhancementsViewModel())
        case .polishRelease:
            PolishReleaseView(viewModel: PolishReleaseViewModel())
        case .integrationTesting:
            IntegrationTestingView(viewModel: IntegrationTestingViewModel())
        case .j2kTestBench:
            J2KTestBenchView(viewModel: viewModel.j2kTestBenchViewModel)
        case .settings:
            SettingsView(viewModel: SettingsViewModel(settingsService: viewModel.settingsService))
        }
    }
}


/// Keeps the library's index in step with the study's presentation-state series.
///
/// Saving a view in the viewer writes GSPS objects into the study's folder, and
/// deleting one removes them; the library is an in-memory index built at import
/// and knows about neither until it is told. Watched at the shell rather than in
/// the viewer because the library is the shell's, not the viewer's.
///
/// A modifier rather than two `.onChange`s inline on `MainView.body`: the body
/// is already a large view expression, and adding them to it directly pushed the
/// type-checker past its limit.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
private struct PresentationSeriesLibrarySync: ViewModifier {
    @Bindable var viewModel: MainViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.imageViewerViewModel.presentationSeriesPublishRequests) { _, _ in
                guard let published =
                    viewModel.imageViewerViewModel.publishedPresentationSeries else { return }
                viewModel.registerPublishedPresentationSeries(published)
            }
            .onChange(of: viewModel.imageViewerViewModel.presentationSeriesRemovalRequests) { _, _ in
                viewModel.unregisterPresentationStates(
                    sopInstanceUIDs:
                        viewModel.imageViewerViewModel.unpublishedPresentationStateUIDs)
            }
    }
}

#endif
