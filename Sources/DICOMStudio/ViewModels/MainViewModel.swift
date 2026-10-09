// MainViewModel.swift
// DICOMStudio
//
// DICOM Studio — Main application ViewModel
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (navigation, service wiring and viewer
// hand-off).

import Foundation
import Observation
import DICOMKit
import DICOMPrintKit

/// Main ViewModel for DICOM Studio, managing top-level navigation
/// and application state.
///
/// Uses `@Observable` macro (requires macOS 14+ / Swift 5.9+)
/// for automatic SwiftUI view updates.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
@MainActor
public final class MainViewModel {
    /// Currently selected sidebar navigation destination.
    public var selectedDestination: NavigationDestination?

    /// Sidebar categories that are currently expanded. Imaging starts open;
    /// the others collapse so the app presents as an imaging tool first.
    public var expandedCategories: Set<NavigationCategory> = [.imaging]

    /// Whether the welcome sheet is shown.
    public var showWelcomeSheet: Bool

    /// Current search text in the sidebar.
    public var searchText: String

    /// The local DICOM file library.
    ///
    /// This is a computed passthrough to the study browser's library,
    /// ensuring a single source of truth across the application.
    public var library: LibraryModel {
        get { studyBrowserViewModel.library }
        set { studyBrowserViewModel.library = newValue }
    }

    /// Application settings service.
    public let settingsService: SettingsService

    /// File I/O service.
    public let fileService: DICOMFileService

    /// Navigation service.
    public let navigationService: NavigationService

    /// Storage service.
    public let storageService: StorageService

    /// Thumbnail service.
    public let thumbnailService: ThumbnailService

    /// Status message displayed in the status bar.
    public var statusMessage: String

    /// The library storage service for persistence.
    public let libraryStorageService: LibraryStorageService

    /// Persistent study browser ViewModel — survives tab switches.
    public var studyBrowserViewModel: StudyBrowserViewModel

    /// Persistent image viewer ViewModel — survives tab switches.
    public var imageViewerViewModel: ImageViewerViewModel

    /// Persistent print ViewModel — printers and job history survive tab switches.
    ///
    /// Shares the viewer's mark list, so the standalone Print screen and the
    /// viewer's print sheet always describe the same selection.
    public var printViewModel: PrintViewModel

    /// Persistent Print SCP ViewModel — the printer emulator's listener and the
    /// films it has received must survive tab switches, or navigating away from
    /// the screen would drop an association mid-job.
    public var printSCPViewModel: PrintSCPViewModel

    /// Persistent standalone 3D MPR viewer ViewModel — survives tab switches.
    public var volumeViewerViewModel: DICOMVolumeViewerViewModel

    /// Persistent JP3D volumetric comparison ViewModel — survives tab switches.
    public var jp3dComparisonViewModel: JP3DComparisonViewModel

    /// Persistent J2KSwift frame-by-frame comparison ViewModel — survives tab switches.
    public var volumeComparisonViewModel: JP3DVolumeComparisonViewModel

    /// Persistent networking ViewModel — survives tab switches.
    public var networkingViewModel: NetworkingViewModel

    /// Persistent DICOMweb ViewModel — survives tab switches.
    public var dicomWebViewModel: DICOMwebViewModel

    /// Persistent CLI Workshop ViewModel — survives tab switches.
    public var cliWorkshopViewModel: CLIWorkshopViewModel

    /// Persistent J2K Test Bench ViewModel — survives tab switches.
    public var j2kTestBenchViewModel: J2KTestBenchViewModel

    /// Persistent AI Analysis ViewModel — survives tab switches.
    public var aiAnalysisViewModel: AIAnalysisViewModel

    /// Persistent Cloud Integration ViewModel — survives tab switches.
    public var cloudIntegrationViewModel: CloudIntegrationViewModel

    /// Persistent DICOM Gateway ViewModel — survives tab switches.
    public var gatewayViewModel: GatewayViewModel

    /// Persistent Archive Management ViewModel — survives tab switches.
    public var archiveManagementViewModel: ArchiveManagementViewModel

    /// Persistent Validation ViewModel (dicom-validate parity) — survives tab switches.
    public var validationViewModel: ValidationViewModel

    /// Persistent Network Utility ViewModel (general, non-DICOM network
    /// diagnostics) — survives tab switches.
    public var networkUtilityViewModel: NetworkUtilityViewModel

    /// Creates the main ViewModel with dependency-injected services.
    public init(
        settingsService: SettingsService = SettingsService(),
        fileService: DICOMFileService = DICOMFileService(),
        navigationService: NavigationService = NavigationService(),
        storageService: StorageService = StorageService(),
        thumbnailService: ThumbnailService? = nil,
        libraryStorageService: LibraryStorageService = LibraryStorageService()
    ) {
        self.settingsService = settingsService
        self.fileService = fileService
        self.navigationService = navigationService
        self.storageService = storageService
        self.thumbnailService = thumbnailService ?? ThumbnailService(storageService: storageService)
        self.libraryStorageService = libraryStorageService
        self.selectedDestination = NavigationService.defaultDestination
        self.showWelcomeSheet = settingsService.showWelcomeOnLaunch
        self.searchText = ""
        self.statusMessage = "Ready"

        // Load persisted library from disk so imports survive app restarts.
        let savedLibrary = libraryStorageService.load()

        // Create a single StudyBrowserViewModel that lives for the
        // entire app session — switching tabs no longer destroys it.
        // The `library` computed property on MainViewModel delegates
        // to this ViewModel, keeping a single source of truth.
        let importService = ImportService(
            fileService: fileService,
            copyDirectory: storageService.importDirectory
        )
        self.studyBrowserViewModel = StudyBrowserViewModel(
            library: savedLibrary,
            importService: importService,
            libraryStorageService: libraryStorageService,
            // Deleting a study reclaims the copy import made of it. Without
            // this the browser drops the row and leaves the images on disk.
            fileCleanup: StudyFileCleanup(storageService: storageService)
        )

        let imageViewer = ImageViewerViewModel()
        self.imageViewerViewModel = imageViewer
        // The app's one shared print view model gets the persistent queue —
        // stray instances (previews, standalone viewers) stay off the file.
        self.printViewModel = PrintViewModel(
            selection: imageViewer.printSelection,
            queueStorage: PrintQueueStorageService(storageService: storageService))
        self.printSCPViewModel = PrintSCPViewModel(
            storage: PrintSCPSettingsStorageService(storageService: storageService))
        self.volumeViewerViewModel = DICOMVolumeViewerViewModel()
        self.jp3dComparisonViewModel = JP3DComparisonViewModel()
        self.volumeComparisonViewModel = JP3DVolumeComparisonViewModel()

        let profileStorage = ServerProfileStorageService(storageService: storageService)
        let networkingService = NetworkingService(profileStorage: profileStorage)
        self.networkingViewModel = NetworkingViewModel(service: networkingService)

        self.dicomWebViewModel = DICOMwebViewModel()

        self.cliWorkshopViewModel = CLIWorkshopViewModel()
        self.j2kTestBenchViewModel = J2KTestBenchViewModel(storageService: storageService)
        self.aiAnalysisViewModel = AIAnalysisViewModel()
        self.cloudIntegrationViewModel = CloudIntegrationViewModel()
        self.gatewayViewModel = GatewayViewModel()
        self.archiveManagementViewModel = ArchiveManagementViewModel()
        self.validationViewModel = ValidationViewModel()
        self.networkUtilityViewModel = NetworkUtilityViewModel()
        // Share saved server profiles so CLI Workshop can pick from them.
        self.cliWorkshopViewModel.savedServerProfiles = networkingViewModel.serverProfiles

        // Auto-start the local DICOM SCP so other applications can send C-ECHO/C-STORE
        // to DICOMStudio immediately on launch without any manual configuration.
        Task { [weak self] in
            await self?.cliWorkshopViewModel.startLocalSCP()
        }

        // Wire the CLI workshop's "open in viewer" callbacks.
        self.cliWorkshopViewModel.onOpenInViewer = { [weak self] filePath, scopedURL in
            guard let self else { return }
            self.imageViewerViewModel.loadFile(at: filePath, securityScopedParent: scopedURL)
            self.selectedDestination = .viewer
        }
        self.cliWorkshopViewModel.onOpenSeriesInViewer = { [weak self] files, startIdx, scopedURL in
            guard let self else { return }
            self.imageViewerViewModel.loadSeries(
                files: files,
                startIndex: startIdx,
                securityScopedParent: scopedURL
            )
            self.selectedDestination = .viewer
        }

        // Deleting a study is when the rest of the app has to let go of it:
        // the viewer would otherwise keep showing images whose files are gone,
        // and a queued print job would still try to print them.
        self.studyBrowserViewModel.onStudyRemoved = { [weak self] studyUID, filePaths in
            guard let self else { return }
            self.releaseStudy(studyUID, filePaths: filePaths)
        }

        // Wire the study browser's "open in viewer" callbacks.
        // Series callback (preferred): loads all files in the series with navigation.
        self.studyBrowserViewModel.onOpenSeriesInViewer = { [weak self] files, startIdx in
            guard let self else { return }
            // A different study is a fresh read: the previous one's grid, zoom,
            // window and series pane would otherwise still be on screen behind
            // the new images.
            self.imageViewerViewModel.prepareForNewStudy()
            self.imageViewerViewModel.loadSeries(files: files, startIndex: startIdx)
            self.populateViewerSeriesPane(forFile: files.first)
            self.selectedDestination = .viewer
        }
        // Single-file fallback: kept for API consumers that only set onOpenInViewer.
        self.studyBrowserViewModel.onOpenInViewer = { [weak self] filePath in
            guard let self else { return }
            self.imageViewerViewModel.prepareForNewStudy()
            self.imageViewerViewModel.loadFile(at: filePath)
            self.populateViewerSeriesPane(forFile: filePath)
            self.selectedDestination = .viewer
        }
        // "Print…" from the library: mark the files, open the first one so the
        // user has context, and raise the print sheet in the viewer.
        //
        // The library's files are *added* to the selection, never substituted for
        // it: frames the user ticked in the viewer are deliberate choices and must
        // survive this entry point. Files already marked are skipped, so their
        // captured window/level and film position are preserved.
        self.studyBrowserViewModel.onPrintFiles = { [weak self] files in
            guard let self, !files.isEmpty else { return }
            self.imageViewerViewModel.printSelection.add(
                contentsOf: files.map { PrintSelectionItem(filePath: $0) })
            self.imageViewerViewModel.revealPrintTray()
            self.imageViewerViewModel.loadSeries(files: files, startIndex: 0)
            self.selectedDestination = .viewer
            self.imageViewerViewModel.isPrintSheetPresented = true
        }
    }

    /// Lets go of a study the library no longer holds.
    ///
    /// Called after its files have been deleted. Everything here is about not
    /// pointing at bytes that are gone: the viewer stops showing the study, the
    /// decoded-pixel cache drops it, and queued print jobs for it are withdrawn
    /// rather than left to fail at the printer.
    func releaseStudy(_ studyUID: String, filePaths: [String]) {
        // The viewer, but only if this is the study it is showing. A reader who
        // deleted some other study should not have their images cleared.
        if imageViewerViewModel.studyInstanceUID == studyUID {
            imageViewerViewModel.closeStudy()
            if selectedDestination == .viewer {
                selectedDestination = .library
            }
        }

        // Decoded pixels of the deleted study are still resident otherwise —
        // this cache is keyed by path, and those paths are now gone.
        Task { await FrameSourceCache.shared.clear() }

        // Queued jobs that would print files that no longer exist. Active jobs
        // are left alone: the printer already has them, and `remove` refuses
        // them anyway.
        let deletedPaths = Set(filePaths)
        let doomed = printViewModel.queue.jobs.filter { job in
            !job.state.isActive && job.payload.items.contains { item in
                deletedPaths.contains(item.filePath)
            }
        }
        for job in doomed { printViewModel.queue.remove(job.id) }
    }

    /// Fills the viewer's series pane with every series of the file's study.
    ///
    /// The pane is what lets a reader hang a different series in a tile, so it
    /// follows the study rather than the one series that was opened. Orientation
    /// is not indexed by the library, so it is read from disk afterwards and
    /// folded in — the pane appears at once and settles a moment later.
    func populateViewerSeriesPane(forFile filePath: String?) {
        guard let filePath,
              let studyUID = ViewerSeriesCatalog.studyUID(containing: filePath, in: library)
        else { return }

        // The study's own presentation states go into the store first, so
        // that the pane's badges and the viewer's first offer — both made by
        // `loadStudySeries` — already know about them. A second visit to the
        // same study finds them there and does nothing.
        if let store = imageViewerViewModel.presentationStateStore {
            StudyPresentationStateAdoption.adopt(studyUID: studyUID, in: library, into: store)
        }

        let entries = ViewerSeriesCatalog.entries(forStudy: studyUID, in: library)
        imageViewerViewModel.loadStudySeries(entries, studyUID: studyUID)

        Task { [weak self] in
            // Instance order first: a stale index (numbers never parsed) has
            // the series in file-system order, and every viewer the study
            // travels to sorts by Instance Number — the numbers on screen
            // here have to mean the same slice they mean everywhere else.
            let ordered = await ViewerSeriesCatalog.resolvingInstanceOrder(entries)
            let resolved = await ViewerSeriesCatalog.resolvingOrientations(ordered.entries)
            guard let self, self.imageViewerViewModel.studyInstanceUID == studyUID else { return }
            self.imageViewerViewModel.loadStudySeries(resolved, studyUID: studyUID)
            // The recovered numbers go back into the index, so the repair
            // reads the files once — not on every open of the study.
            guard !ordered.recoveredNumbers.isEmpty else { return }
            for (sopUID, number) in ordered.recoveredNumbers {
                if var instance = self.library.instances[sopUID],
                   instance.instanceNumber == nil {
                    instance.instanceNumber = number
                    self.library.addInstance(instance)
                }
            }
            try? self.libraryStorageService.save(self.library)
        }
    }

    /// Files a just-published presentation-state series into the library.
    ///
    /// Publishing writes the GSPS objects next to the study's own files; the
    /// library is an in-memory index built at import, so it does not know they
    /// are there. Registering them directly rather than re-scanning the folder
    /// is deliberate: a re-scan of a large study to pick up two small objects
    /// would stall the viewer, and everything the index needs is already in the
    /// published description.
    ///
    /// The series pane is refilled afterwards so the new "PR" series appears
    /// without the reader having to reopen the study.
    public func registerPublishedPresentationSeries(
        _ published: PresentationStateStore.PublishedSeries
    ) {
        // A study the library does not hold is one opened from outside it — the
        // objects are on disk beside their images either way, and the next
        // import picks them up. There is simply no index entry to add them to.
        guard library.studies[published.studyInstanceUID] != nil else { return }

        library.addSeries(SeriesModel(
            seriesInstanceUID: published.seriesInstanceUID,
            studyInstanceUID: published.studyInstanceUID,
            seriesNumber: published.seriesNumber,
            modality: published.modality,
            seriesDescription: published.seriesDescription,
            numberOfInstances: published.instances.count))

        for instance in published.instances {
            let size = (try? FileManager.default.attributesOfItem(
                atPath: instance.url.path)[.size] as? Int64) ?? nil
            library.addInstance(InstanceModel(
                sopInstanceUID: instance.sopInstanceUID,
                sopClassUID: instance.sopClassUID,
                seriesInstanceUID: published.seriesInstanceUID,
                instanceNumber: instance.instanceNumber,
                filePath: instance.url.path,
                fileSize: size ?? 0,
                transferSyntaxUID: PresentationStateStore.transferSyntaxUID))
        }

        // Publishing twice must not double the count: the series is shared, so
        // its instance total is whatever the index now holds for it.
        if var series = library.series[published.seriesInstanceUID] {
            series.numberOfInstances =
                library.instancesForSeries(published.seriesInstanceUID).count
            library.addSeries(series)
        }

        try? libraryStorageService.save(library)
        populateViewerSeriesPane(forFile: imageViewerViewModel.filePath)
    }

    /// Takes deleted presentation states back out of the library's index.
    ///
    /// The mirror of ``registerPublishedPresentationSeries(_:)``: the files are
    /// already gone from the study's folder, and an index still listing them
    /// would leave the series pane offering a card whose objects cannot be
    /// opened. A series left with no instances is removed with them, so a study
    /// whose only saved view was deleted stops showing an empty "PR" series.
    public func unregisterPresentationStates(sopInstanceUIDs: [String]) {
        guard !sopInstanceUIDs.isEmpty else { return }

        // The study these objects belonged to, resolved before they are dropped
        // from the index — afterwards there is nothing left to look them up by.
        let studyUIDs = Set(sopInstanceUIDs.compactMap { uid -> String? in
            guard let seriesUID = library.instances[uid]?.seriesInstanceUID else { return nil }
            return library.series[seriesUID]?.studyInstanceUID
        })

        for uid in sopInstanceUIDs {
            library.removeInstance(uid)
        }

        // Every presentation-state series of the affected studies, not only the
        // ones these instances were indexed under. A study can carry more than
        // one PR series — objects imported with the study on one, objects
        // published here on another — and pruning only the series named by the
        // deleted UIDs left the others behind as cards whose files are gone.
        for studyUID in studyUIDs {
            pruneEmptyPresentationSeries(inStudy: studyUID)
        }

        try? libraryStorageService.save(library)
        populateViewerSeriesPane(forFile: imageViewerViewModel.filePath)
    }

    /// Drops a study's presentation-state series that no longer have any file
    /// behind them.
    ///
    /// Emptiness is judged against the disk, not the index: the delete path
    /// removes the `.dcm` files directly, and a series whose instances were
    /// indexed by an import still lists them long after they stopped existing.
    /// Only PR series are considered — an image series with a missing file is a
    /// broken study to report, not a card to silently remove.
    private func pruneEmptyPresentationSeries(inStudy studyUID: String) {
        let fileManager = FileManager.default
        for series in library.seriesForStudy(studyUID) {
            let instances = library.instancesForSeries(series.seriesInstanceUID)
            guard instances.allSatisfy({ Self.isPresentationState($0.sopClassUID) })
            else { continue }
            let missing = instances.filter { !fileManager.fileExists(atPath: $0.filePath) }
            for instance in missing {
                library.removeInstance(instance.sopInstanceUID)
            }
            if library.instancesForSeries(series.seriesInstanceUID).isEmpty {
                library.removeSeries(series.seriesInstanceUID)
            }
        }
    }

    /// Whether a SOP Class is one of the presentation-state IODs this app writes.
    static func isPresentationState(_ sopClassUID: String) -> Bool {
        sopClassUID == GrayscalePresentationStateBuilder.sopClassUID
            || sopClassUID == PseudoColorPresentationStateBuilder.sopClassUID
    }

    /// Opens the first retrieved file from CLI Workshop in the viewer.
    public func openLastRetrievedInViewer() {
        guard let firstFile = cliWorkshopViewModel.lastRetrievedFiles.first else { return }
        imageViewerViewModel.loadFile(
            at: firstFile,
            securityScopedParent: cliWorkshopViewModel.lastRetrievedOutputURL
        )
        selectedDestination = .viewer
    }

    /// Navigates to the specified destination, revealing its sidebar
    /// category if it was collapsed.
    public func navigate(to destination: NavigationDestination) {
        selectedDestination = destination
        expandedCategories.insert(destination.category)
    }

    /// Opens the first displayable instance of the given study in the viewer.
    public func openStudyInViewer(_ studyUID: String) {
        let seriesList = library.seriesForStudy(studyUID)
        for series in seriesList {
            let instances = library.instancesForSeries(series.seriesInstanceUID)
            if let first = instances.first {
                // Same fresh read as the browser's own callbacks: this is a study
                // opened from the library, so nothing of the last one — including
                // its print selection — carries over.
                imageViewerViewModel.prepareForNewStudy()
                // Load the whole first series, not just its first file: the
                // viewer needs a navigation list, and the pane needs the study.
                imageViewerViewModel.loadSeries(
                    files: instances.map(\.filePath), startIndex: 0)
                populateViewerSeriesPane(forFile: first.filePath)
                selectedDestination = .viewer
                return
            }
        }
    }

    /// Returns the primary navigation destinations.
    public var primaryDestinations: [NavigationDestination] {
        NavigationService.primaryDestinations
    }

    /// Filters navigation destinations based on search text.
    public var filteredDestinations: [NavigationDestination] {
        guard !searchText.isEmpty else { return primaryDestinations }
        return primaryDestinations.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Search-aware destinations belonging to a single sidebar category,
    /// in canonical order.
    public func filteredDestinations(in category: NavigationCategory) -> [NavigationDestination] {
        filteredDestinations.filter { $0.category == category }
    }

    /// Updates the status message.
    public func setStatus(_ message: String) {
        statusMessage = message
    }
}
