#!/usr/bin/env python3
"""Diff DICOMStudio (and DICOMStudioApp) against the frozen DICOM DocBook and against the dicom-* CLI contract.

Usage:
    for p in 3 4 5 6 10 11 15 16 18; do python3 Scripts/nema_docbook.py fetch 2026a $p --out DIR; done
    python3 Scripts/diff_studio.py --nema DIR [--group G1] [--only NAME] [--verbose]
    python3 Scripts/diff_studio.py --inventory            # not-standard-touching files (for check_nema_markers.py)
    python3 Scripts/diff_studio.py --list-surface [--tool dicom-anon]   # the Workshop form of each tool
    python3 Scripts/diff_studio.py --emit-parity dicom-anon             # markdown parity table for the report

DICOMStudio is the macOS app over DICOMKit. Most of its 334 files are SwiftUI views, caches and view-model
plumbing that carry no standard-derived value; FILES below records every file with its group and tier:
`ST` (standard-touching: reviewed row by row, carries a NEMA-verified marker), `CR` (confirm-read: incidental
hits only, read once and recorded as NST unless promoted), `NST` (not standard-touching: inventoried, no marker).
`--inventory` prints the NST files so `check_nema_markers.py --inventory` can count them as inventoried.

Checks:
  * generic (every ST file): the DICOMKit literal checks of diff_kit / diff_web — UIDs in PS3.6 Table A-1,
    coded concepts in PS3.16, tag constants, PS3 citations, CS defined terms, photometric terms,
    de-identification rows — re-run over the Studio sources.
  * workshop parity (G1): the CLI Workshop form of each tool the UI offers (CLIWorkshopHelpers.swift
    `rawParameterDefinitions`) is extracted and compared with the real tool's ArgumentParser surface
    (diff_cli.extract_options) and with the contract rows of cli_contracts.CONTRACT: every Workshop flag is a
    real option, defaults agree, picker values are the option's accepted values, and every contract row with a
    standard verdict (not plumbing) is offered. Tools the UI does not offer (dicom-server, gateway, jpip, cloud,
    ai, j2k, report, measure, 3d, viewer, print, printscp, script) are out of scope by the owner's decision.
  * per-group checks added as each group is verified (see DICOMSTUDIO_STANDARD_IMPLEMENTATION.md).

Statuses: `ok`; `FAIL` (Studio contradicts the text or the CLI contract; exit 1); `PEND` (the fix changes public
API and waits for the owner); `DEFR` (the value lives in another module; D-number given).
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCES = os.path.join(ROOT, 'Sources')


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


nd = load('nema_docbook')
dw = load('diff_web')
dk = load('diff_kit')
dc = load('diff_cli')
CONTRACT = load('cli_contracts').CONTRACT

# Findings whose fix changes public API (a Studio enum case, a renamed member) and waits for the owner.
# Key: substring of the finding text; value: P-item name (see the report).
PENDING_API_APPROVAL = {
    'ps315': 'P-STUDIO-ANON-PS315',          # AnonymizationProfile needs a .ps315 case to offer the CLI default
}
# Findings whose cause lives in another module (DEFR, with their D-number).
DEFERRED = {
}
# Workshop flags or CLI options deliberately not mirrored, with the reason (reported as notes, not failures).
EXEMPT = {
}

# --- inventory ------------------------------------------------------------------------------------

GROUPS = {
    'G1': 'CLI Workshop (forms, executors, shell foundation, parameter builder, validation)',
    'G2': 'Viewer and rendering (PS3.4 N.2 pipeline, presentation states, shutters, annotations, codecs, labels)',
    'G3': 'Network and web (DIMSE and print enums, DICOMweb client and model, performance-test data)',
    'G4': 'File, media and DICOMDIR (parser, data exchange profiles, import validation, metadata models)',
    'G5': 'Derived objects, SR and security (SR, terminology, SEG, RT, parametric map, WSI, waveform, hanging protocol, measurements, anonymization)',
    'G6': 'Print (PS3.3 C.13, PS3.4 Annex H: print view models, settings, printer status, Print SCP panes)',
}

# path (under Sources/) -> (group, tier). Tiers: ST standard-touching, CR confirm-read, NST not standard-touching.
FILES = {
    # G1
    'DICOMStudio/Models/IntegratedTerminalModel.swift': ('G1', 'CR'),
    'DICOMStudio/Views/CLIWorkshopView.swift': ('G1', 'CR'),
    'DICOMStudio/Components/IntegrationTestingHelpers.swift': ('G1', 'NST'),
    'DICOMStudio/Services/BrowserNavigationService.swift': ('G1', 'NST'),
    'DICOMStudio/Services/CLIShellFoundationService.swift': ('G1', 'NST'),
    'DICOMStudio/Services/IntegratedTerminalService.swift': ('G1', 'NST'),
    'DICOMStudio/Services/IntegrationTestingService.swift': ('G1', 'NST'),
    'DICOMStudio/Services/ParameterBuilderService.swift': ('G1', 'NST'),
    'DICOMStudio/Services/ShellServerConfigService.swift': ('G1', 'NST'),
    'DICOMStudio/Services/ValidationService.swift': ('G1', 'NST'),
    'DICOMStudio/ViewModels/BrowserNavigationViewModel.swift': ('G1', 'NST'),
    'DICOMStudio/ViewModels/CLIShellFoundationViewModel.swift': ('G1', 'NST'),
    'DICOMStudio/ViewModels/IntegratedTerminalViewModel.swift': ('G1', 'NST'),
    'DICOMStudio/ViewModels/IntegrationTestingViewModel.swift': ('G1', 'NST'),
    'DICOMStudio/ViewModels/ParameterBuilderViewModel.swift': ('G1', 'NST'),
    'DICOMStudio/ViewModels/ShellServerConfigViewModel.swift': ('G1', 'NST'),
    'DICOMStudio/Views/IntegrationTestingView.swift': ('G1', 'NST'),
    'DICOMStudio/Components/BrowserNavigationHelpers.swift': ('G1', 'ST'),
    'DICOMStudio/Components/CLIShellFoundationHelpers.swift': ('G1', 'ST'),
    'DICOMStudio/Components/CLIToolBuilder.swift': ('G1', 'ST'),
    'DICOMStudio/Components/CLIToolTerminalCompare.swift': ('G1', 'ST'),
    'DICOMStudio/Components/CLIWorkshopHelpers.swift': ('G1', 'ST'),
    'DICOMStudio/Components/ImportValidation.swift': ('G1', 'ST'),
    'DICOMStudio/Components/IntegratedTerminalHelpers.swift': ('G1', 'ST'),
    'DICOMStudio/Components/ParameterBuilderHelpers.swift': ('G1', 'ST'),
    'DICOMStudio/Components/ShellServerConfigHelpers.swift': ('G1', 'ST'),
    'DICOMStudio/Models/BrowserNavigationModel.swift': ('G1', 'ST'),
    'DICOMStudio/Models/CLIShellFoundationModel.swift': ('G1', 'ST'),
    'DICOMStudio/Models/CLIWorkshopModel.swift': ('G1', 'ST'),
    'DICOMStudio/Models/IntegrationTestingModel.swift': ('G1', 'ST'),
    'DICOMStudio/Models/ParameterBuilderModel.swift': ('G1', 'ST'),
    'DICOMStudio/Models/ShellServerConfigModel.swift': ('G1', 'ST'),
    'DICOMStudio/Models/ValidationModel.swift': ('G1', 'ST'),
    'DICOMStudio/Services/CLIWorkshopService.swift': ('G1', 'ST'),
    'DICOMStudio/ViewModels/CLIWorkshopViewModel.swift': ('G1', 'ST'),
    'DICOMStudio/ViewModels/ValidationViewModel.swift': ('G1', 'ST'),
    'DICOMStudio/Views/ValidationView.swift': ('G1', 'ST'),
    # G2
    'DICOMStudio/Components/J2KBenchmarkBaseline.swift': ('G2', 'CR'),
    'DICOMStudio/Components/ViewportLayoutHelpers.swift': ('G2', 'CR'),
    'DICOMStudio/Models/MacOSEnhancementsModel.swift': ('G2', 'CR'),
    'DICOMStudio/Models/PatientOverlayText.swift': ('G2', 'CR'),
    'DICOMStudio/Models/ViewerAnnotationCorners.swift': ('G2', 'CR'),
    'DICOMStudio/Models/ViewerHoverGeometry.swift': ('G2', 'CR'),
    'DICOMStudio/Models/ViewerSeriesEntry.swift': ('G2', 'CR'),
    'DICOMStudio/Models/ViewerTileLayout.swift': ('G2', 'CR'),
    'DICOMStudio/Models/ViewportModel.swift': ('G2', 'CR'),
    'DICOMStudio/Services/FrameImageStore.swift': ('G2', 'CR'),
    'DICOMStudio/Services/ThumbnailService.swift': ('G2', 'CR'),
    'DICOMStudio/Services/ViewerTileImageCache.swift': ('G2', 'CR'),
    'DICOMStudio/Services/ViewerTileTextureCache.swift': ('G2', 'CR'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+Annotations.swift': ('G2', 'CR'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+Layout.swift': ('G2', 'CR'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+StudyDownload.swift': ('G2', 'CR'),
    'DICOMStudio/ViewModels/JP3DMPRViewModel.swift': ('G2', 'CR'),
    'DICOMStudio/ViewModels/MultiViewportViewModel.swift': ('G2', 'CR'),
    'DICOMStudio/Views/DICOMVolumeViewerView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/ImageMetadataOverlayView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/ImageViewerView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/J2KTestBenchView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/J2KTestingView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/JP3DComparisonView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/JP3DMPRView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/JP3DVolumeComparisonView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/MacOSEnhancementsView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/ProgressiveImageView.swift': ('G2', 'CR'),
    'DICOMStudio/Views/ViewerAnnotationEditLayer.swift': ('G2', 'CR'),
    'DICOMStudio/Views/ViewerImageSavedViewList.swift': ('G2', 'CR'),
    'DICOMStudio/Views/ViewerTileGridView.swift': ('G2', 'CR'),
    'DICOMStudio/App/StudioWindowCommands.swift': ('G2', 'NST'),
    'DICOMStudio/App/ViewerCommands.swift': ('G2', 'NST'),
    'DICOMStudio/Components/CinePlaybackHelpers.swift': ('G2', 'NST'),
    'DICOMStudio/Components/ClipboardHelper.swift': ('G2', 'NST'),
    'DICOMStudio/Components/GestureHelpers.swift': ('G2', 'NST'),
    'DICOMStudio/Components/ImageCacheHelpers.swift': ('G2', 'NST'),
    'DICOMStudio/Components/InteractiveSurface.swift': ('G2', 'NST'),
    'DICOMStudio/Components/J2KBenchImageRenderer.swift': ('G2', 'NST'),
    'DICOMStudio/Components/J2KTestBenchExporter.swift': ('G2', 'NST'),
    'DICOMStudio/Components/JP3DMPRRenderHelpers.swift': ('G2', 'NST'),
    'DICOMStudio/Components/OutputAccess.swift': ('G2', 'NST'),
    'DICOMStudio/Components/ProjectionHelpers.swift': ('G2', 'NST'),
    'DICOMStudio/Components/ScrollWheelModifier.swift': ('G2', 'NST'),
    'DICOMStudio/Components/StatusIndicator.swift': ('G2', 'NST'),
    'DICOMStudio/Components/SurfaceExtractionHelpers.swift': ('G2', 'NST'),
    'DICOMStudio/Components/TooltipModifier.swift': ('G2', 'NST'),
    'DICOMStudio/Components/VolumeRenderingHelpers.swift': ('G2', 'NST'),
    'DICOMStudioApp/DICOMStudioApp.swift': ('G2', 'NST'),
    'DICOMStudio/Models/SavedViewReference.swift': ('G2', 'NST'),
    'DICOMStudio/Services/AnnotationOverlayTextureCache.swift': ('G2', 'NST'),
    'DICOMStudio/Services/AnnotationTextureBuilder.swift': ('G2', 'NST'),
    'DICOMStudio/Services/ImageCacheService.swift': ('G2', 'NST'),
    'DICOMStudio/Services/J2KTestBenchStore.swift': ('G2', 'NST'),
    'DICOMStudio/Services/MacOSEnhancementsService.swift': ('G2', 'NST'),
    'DICOMStudio/Services/NavigationService.swift': ('G2', 'NST'),
    'DICOMStudio/Services/PatientOverlayTextCache.swift': ('G2', 'NST'),
    'DICOMStudio/Services/SettingsService.swift': ('G2', 'NST'),
    'DICOMStudio/Services/ViewerAnnotationTextCache.swift': ('G2', 'NST'),
    'DICOMStudio/Services/VolumeVisualizationService.swift': ('G2', 'NST'),
    'DICOMStudio/Theme/StudioTheme.swift': ('G2', 'NST'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+DrawnAnnotationEditing.swift': ('G2', 'NST'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+ImageNavigation.swift': ('G2', 'NST'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+Series.swift': ('G2', 'NST'),
    'DICOMStudio/ViewModels/MacOSEnhancementsViewModel.swift': ('G2', 'NST'),
    'DICOMStudio/ViewModels/SettingsViewModel.swift': ('G2', 'NST'),
    'DICOMStudio/ViewModels/VolumeVisualizationViewModel.swift': ('G2', 'NST'),
    'DICOMStudio/Views/CineControlsView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/CodecImageComparisonView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/KeyboardShortcutsLegendView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/MultiViewportView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/PatientIdentificationOverlayView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/SavedViewPromptView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/ScrollWheelHandler.swift': ('G2', 'NST'),
    'DICOMStudio/Views/Settings/AboutView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/Settings/GeneralSettingsView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/Settings/PerformanceSettingsView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/Settings/SettingsView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/SidebarView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/ToolSymbolCursor.swift': ('G2', 'NST'),
    'DICOMStudio/Views/ViewerAnnotationOverlayView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/ViewerPalettePickerView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/ViewerPaneChrome.swift': ('G2', 'NST'),
    'DICOMStudio/Views/ViewerSeriesPaneView.swift': ('G2', 'NST'),
    'DICOMStudio/Views/ViewerSeriesSavedViewList.swift': ('G2', 'NST'),
    'DICOMStudio/Components/AnnotationHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/BlendingHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/CodecInspectorHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ColorLUTHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/EnterpriseRenderHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ICCProfileHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ImageInversion.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ImageMetadataHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/JP3DMPRSliceExtractor.swift': ('G2', 'ST'),
    'DICOMStudio/Components/MPRHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/MacOSEnhancementsHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ModalityIcon.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ModalityPicker.swift': ('G2', 'ST'),
    'DICOMStudio/Components/PresentationStateHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ShutterHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/ThumbnailHelpers.swift': ('G2', 'ST'),
    'DICOMStudio/Components/WindowLevelPresets.swift': ('G2', 'ST'),
    'DICOMStudio/Models/AnnotationModel.swift': ('G2', 'ST'),
    'DICOMStudio/Models/CodecInspectorModel.swift': ('G2', 'ST'),
    'DICOMStudio/Models/J2KTestBenchModels.swift': ('G2', 'ST'),
    'DICOMStudio/Models/PresentationStateModel.swift': ('G2', 'ST'),
    'DICOMStudio/Models/ProgressiveDecodeModel.swift': ('G2', 'ST'),
    'DICOMStudio/Models/ShutterModel.swift': ('G2', 'ST'),
    'DICOMStudio/Models/ViewerAnnotationText.swift': ('G2', 'ST'),
    'DICOMStudio/Models/ViewerContentKind.swift': ('G2', 'ST'),
    'DICOMStudio/Models/ViewerNonImageContent.swift': ('G2', 'ST'),
    'DICOMStudio/Models/VolumeVisualizationModel.swift': ('G2', 'ST'),
    'DICOMStudio/Services/CharLSCLICodec.swift': ('G2', 'ST'),
    'DICOMStudio/Services/FrameRenderer.swift': ('G2', 'ST'),
    'DICOMStudio/Services/FrameSourceCache.swift': ('G2', 'ST'),
    'DICOMStudio/Services/ImageDecodingService.swift': ('G2', 'ST'),
    'DICOMStudio/Services/ImageRenderingService.swift': ('G2', 'ST'),
    'DICOMStudio/Services/J2KTestBenchService.swift': ('G2', 'ST'),
    'DICOMStudio/Services/PresentationStateService.swift': ('G2', 'ST'),
    'DICOMStudio/Services/StudyPresentationStateAdoption.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/CodecInspectorViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/DICOMVolumeViewerViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+PatientOverlay.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+PresentationStates.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/ImageViewerViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/J2KTestBenchViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/J2KTestingViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/JP3DComparisonViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/JP3DVolumeComparisonViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/ViewModels/PresentationStateViewModel.swift': ('G2', 'ST'),
    'DICOMStudio/Views/AnnotationOverlayView.swift': ('G2', 'ST'),
    'DICOMStudio/Views/CodecInspectorView.swift': ('G2', 'ST'),
    'DICOMStudio/Views/MainView.swift': ('G2', 'ST'),
    'DICOMStudio/Views/SavedViewPickerView.swift': ('G2', 'ST'),
    'DICOMStudio/Views/ShutterOverlayView.swift': ('G2', 'ST'),
    'DICOMStudio/Views/ViewerNonImageContentView.swift': ('G2', 'ST'),
    'DICOMStudio/Views/WindowLevelPanel.swift': ('G2', 'ST'),
    # G3
    'DICOMStudio/Models/GatewayModel.swift': ('G3', 'CR'),
    'DICOMStudio/ViewModels/CloudIntegrationViewModel.swift': ('G3', 'CR'),
    'DICOMStudio/ViewModels/GatewayViewModel.swift': ('G3', 'CR'),
    'DICOMStudio/Views/CloudIntegrationView.swift': ('G3', 'CR'),
    'DICOMStudio/Views/GatewayView.swift': ('G3', 'CR'),
    'DICOMStudio/Models/NetworkUtilityModel.swift': ('G3', 'NST'),
    'DICOMStudio/Services/CloudIntegrationService.swift': ('G3', 'NST'),
    'DICOMStudio/Services/DICOMwebServerProfileStorageService.swift': ('G3', 'NST'),
    'DICOMStudio/Services/GatewayService.swift': ('G3', 'NST'),
    'DICOMStudio/Services/NetworkUtilityService+Parsing.swift': ('G3', 'NST'),
    'DICOMStudio/Services/NetworkUtilityService.swift': ('G3', 'NST'),
    'DICOMStudio/Services/PolishReleaseService.swift': ('G3', 'NST'),
    'DICOMStudio/Services/ServerProfileStorageService.swift': ('G3', 'NST'),
    'DICOMStudio/ViewModels/NetworkUtilityViewModel.swift': ('G3', 'NST'),
    'DICOMStudio/ViewModels/PolishReleaseViewModel.swift': ('G3', 'NST'),
    'DICOMStudio/Views/LocalListenerView.swift': ('G3', 'NST'),
    'DICOMStudio/Views/NetworkUtilityView.swift': ('G3', 'NST'),
    'DICOMStudio/Views/PolishReleaseView.swift': ('G3', 'NST'),
    'DICOMStudio/Components/DICOMwebHelpers.swift': ('G3', 'ST'),
    'DICOMStudio/Components/NetworkingHelpers.swift': ('G3', 'ST'),
    'DICOMStudio/Components/PerformanceToolsHelpers.swift': ('G3', 'ST'),
    'DICOMStudio/Components/PolishReleaseHelpers.swift': ('G3', 'ST'),
    'DICOMStudio/Models/CloudIntegrationModel.swift': ('G3', 'ST'),
    'DICOMStudio/Models/DICOMwebModel.swift': ('G3', 'ST'),
    'DICOMStudio/Models/NetworkingModel.swift': ('G3', 'ST'),
    'DICOMStudio/Models/PerformanceToolsModel.swift': ('G3', 'ST'),
    'DICOMStudio/Models/PolishReleaseModel.swift': ('G3', 'ST'),
    'DICOMStudio/Services/DICOMwebClientFactory.swift': ('G3', 'ST'),
    'DICOMStudio/Services/DICOMwebService.swift': ('G3', 'ST'),
    'DICOMStudio/Services/NetworkingService.swift': ('G3', 'ST'),
    'DICOMStudio/Services/PerformanceToolsService.swift': ('G3', 'ST'),
    'DICOMStudio/ViewModels/DICOMwebViewModel.swift': ('G3', 'ST'),
    'DICOMStudio/ViewModels/NetworkingViewModel.swift': ('G3', 'ST'),
    'DICOMStudio/ViewModels/PerformanceToolsViewModel.swift': ('G3', 'ST'),
    'DICOMStudio/Views/DICOMwebView.swift': ('G3', 'ST'),
    'DICOMStudio/Views/NetworkingView.swift': ('G3', 'ST'),
    'DICOMStudio/Views/PerformanceToolsView.swift': ('G3', 'ST'),
    # G4
    'DICOMStudio/Models/LibraryFilter.swift': ('G4', 'CR'),
    'DICOMStudio/Services/StudyFileCleanup.swift': ('G4', 'CR'),
    'DICOMStudio/ViewModels/FileOperationsViewModel.swift': ('G4', 'CR'),
    'DICOMStudio/Views/FileOperationsView.swift': ('G4', 'CR'),
    'DICOMStudio/Views/ImageMetadataPanelView.swift': ('G4', 'CR'),
    'DICOMStudio/Views/ImportedShapeView.swift': ('G4', 'CR'),
    'DICOMStudio/Views/MetadataView.swift': ('G4', 'CR'),
    'DICOMStudio/Views/StudyBrowserView.swift': ('G4', 'CR'),
    'DICOMStudio/Components/DICOMTagView.swift': ('G4', 'NST'),
    'DICOMStudio/Services/ArchiveManagementService.swift': ('G4', 'NST'),
    'DICOMStudio/Services/StorageService.swift': ('G4', 'NST'),
    'DICOMStudio/Components/DICOMDIRParser.swift': ('G4', 'ST'),
    'DICOMStudio/Components/DICOMValueParser.swift': ('G4', 'ST'),
    'DICOMStudio/Components/DataExchangeHelpers.swift': ('G4', 'ST'),
    'DICOMStudio/Components/FileOperationsHelpers.swift': ('G4', 'ST'),
    'DICOMStudio/Components/PrivateTagIdentifier.swift': ('G4', 'ST'),
    'DICOMStudio/Components/StudyBrowserHelpers.swift': ('G4', 'ST'),
    'DICOMStudio/Components/VRBadge.swift': ('G4', 'ST'),
    'DICOMStudio/Models/ArchiveManagementModel.swift': ('G4', 'ST'),
    'DICOMStudio/Models/DataExchangeModel.swift': ('G4', 'ST'),
    'DICOMStudio/Models/FileOperationsModel.swift': ('G4', 'ST'),
    'DICOMStudio/Models/ImportModels.swift': ('G4', 'ST'),
    'DICOMStudio/Models/InstanceModel.swift': ('G4', 'ST'),
    'DICOMStudio/Models/LibraryModel.swift': ('G4', 'ST'),
    'DICOMStudio/Models/MetadataTreeNode.swift': ('G4', 'ST'),
    'DICOMStudio/Models/SeriesModel.swift': ('G4', 'ST'),
    'DICOMStudio/Models/StudyModel.swift': ('G4', 'ST'),
    'DICOMStudio/Models/StudyRowSummary.swift': ('G4', 'ST'),
    'DICOMStudio/Services/DICOMFileService.swift': ('G4', 'ST'),
    'DICOMStudio/Services/DataExchangeService.swift': ('G4', 'ST'),
    'DICOMStudio/Services/FileOperationsService.swift': ('G4', 'ST'),
    'DICOMStudio/Services/ImportService.swift': ('G4', 'ST'),
    'DICOMStudio/Services/LibraryStorageService.swift': ('G4', 'ST'),
    'DICOMStudio/Services/ViewerSeriesCatalog.swift': ('G4', 'ST'),
    'DICOMStudio/ViewModels/ArchiveManagementViewModel.swift': ('G4', 'ST'),
    'DICOMStudio/ViewModels/DataExchangeViewModel.swift': ('G4', 'ST'),
    'DICOMStudio/ViewModels/MainViewModel.swift': ('G4', 'ST'),
    'DICOMStudio/ViewModels/MetadataViewModel.swift': ('G4', 'ST'),
    'DICOMStudio/ViewModels/StudyBrowserViewModel.swift': ('G4', 'ST'),
    'DICOMStudio/Views/ArchiveManagementView.swift': ('G4', 'ST'),
    'DICOMStudio/Views/DICOMInspectorView.swift': ('G4', 'ST'),
    'DICOMStudio/Views/DataExchangeView.swift': ('G4', 'ST'),
    # G5
    'DICOMStudio/Models/MeasurementModel.swift': ('G5', 'NST'),
    'DICOMStudio/Models/ROIModel.swift': ('G5', 'NST'),
    'DICOMStudio/Services/AIAnalysisService.swift': ('G5', 'NST'),
    'DICOMStudio/Services/CalibrationService.swift': ('G5', 'NST'),
    'DICOMStudio/Services/MeasurementService.swift': ('G5', 'NST'),
    'DICOMStudio/ViewModels/MeasurementViewModel.swift': ('G5', 'NST'),
    'DICOMStudio/Components/CADVisualizationHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/CalibrationHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/EncapsulatedDocumentHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/HangingProtocolHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/MeasurementHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/MeasurementPersistenceHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/ParametricMapHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/ROIHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/RTHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/SRBuilderHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/SRTreeHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/SecurityHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/SegmentationHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/TerminologyHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/WaveformHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Components/WholeSlideImagingHelpers.swift': ('G5', 'ST'),
    'DICOMStudio/Models/AIAnalysisModel.swift': ('G5', 'ST'),
    'DICOMStudio/Models/HangingProtocolModel.swift': ('G5', 'ST'),
    'DICOMStudio/Models/SecurityModel.swift': ('G5', 'ST'),
    'DICOMStudio/Models/SpecializedModalityModel.swift': ('G5', 'ST'),
    'DICOMStudio/Models/StructuredReportModel.swift': ('G5', 'ST'),
    'DICOMStudio/Services/HangingProtocolService.swift': ('G5', 'ST'),
    'DICOMStudio/Services/SecurityService.swift': ('G5', 'ST'),
    'DICOMStudio/Services/SpecializedModalityService.swift': ('G5', 'ST'),
    'DICOMStudio/Services/StructuredReportService.swift': ('G5', 'ST'),
    'DICOMStudio/ViewModels/AIAnalysisViewModel.swift': ('G5', 'ST'),
    'DICOMStudio/ViewModels/HangingProtocolViewModel.swift': ('G5', 'ST'),
    'DICOMStudio/ViewModels/SecurityViewModel.swift': ('G5', 'ST'),
    'DICOMStudio/ViewModels/SpecializedModalityViewModel.swift': ('G5', 'ST'),
    'DICOMStudio/ViewModels/StructuredReportViewModel.swift': ('G5', 'ST'),
    'DICOMStudio/Views/AIAnalysisView.swift': ('G5', 'ST'),
    'DICOMStudio/Views/HangingProtocolPanel.swift': ('G5', 'ST'),
    'DICOMStudio/Views/SecurityView.swift': ('G5', 'ST'),
    'DICOMStudio/Views/Settings/PrivacySettingsView.swift': ('G5', 'ST'),
    'DICOMStudio/Views/StructuredReportView.swift': ('G5', 'ST'),
    'DICOMStudio/Views/WaveformChartView.swift': ('G5', 'ST'),
    # G6
    'DICOMStudio/Models/PrintSCPModel.swift': ('G6', 'CR'),
    'DICOMStudio/Models/PrintSelectionModel.swift': ('G6', 'CR'),
    'DICOMStudio/Services/PrintImageNumberCache.swift': ('G6', 'CR'),
    'DICOMStudio/Services/PrintQueueService.swift': ('G6', 'CR'),
    'DICOMStudio/Services/PrintSCPSettingsStorageService.swift': ('G6', 'CR'),
    'DICOMStudio/Services/PrintThumbnailCache.swift': ('G6', 'CR'),
    'DICOMStudio/ViewModels/ImageViewerViewModel+Print.swift': ('G6', 'CR'),
    'DICOMStudio/ViewModels/PrintViewModel+CellSync.swift': ('G6', 'CR'),
    'DICOMStudio/Views/Print/FilmLayoutGalleryView.swift': ('G6', 'CR'),
    'DICOMStudio/Views/Print/PrintCenterView.swift': ('G6', 'CR'),
    'DICOMStudio/Views/Print/PrintProgressView.swift': ('G6', 'CR'),
    'DICOMStudio/Models/PrintAuditEvent.swift': ('G6', 'NST'),
    'DICOMStudio/Models/PrintJobHistoryEntry.swift': ('G6', 'NST'),
    'DICOMStudio/Models/PrintSelectionModel+Annotations.swift': ('G6', 'NST'),
    'DICOMStudio/Services/PrintQueueStorageService.swift': ('G6', 'NST'),
    'DICOMStudio/Services/PrintReportPDF.swift': ('G6', 'NST'),
    'DICOMStudio/Services/PrinterProfileStorageService.swift': ('G6', 'NST'),
    'DICOMStudio/Services/PrinterStatusMonitor.swift': ('G6', 'NST'),
    'DICOMStudio/ViewModels/PrintViewModel+Annotations.swift': ('G6', 'NST'),
    'DICOMStudio/ViewModels/PrintViewModel+CellSelection.swift': ('G6', 'NST'),
    'DICOMStudio/ViewModels/PrintViewModel+ImageRange.swift': ('G6', 'NST'),
    'DICOMStudio/Views/Print/AuditTrailView.swift': ('G6', 'NST'),
    'DICOMStudio/Views/Print/FilmCellAnnotationLayer.swift': ('G6', 'NST'),
    'DICOMStudio/Views/Print/PrintOverlayColor+SwiftUI.swift': ('G6', 'NST'),
    'DICOMStudio/Views/Print/PrintQueueView.swift': ('G6', 'NST'),
    'DICOMStudio/Views/Print/PrintSCPWindow.swift': ('G6', 'NST'),
    'DICOMStudio/Views/Print/PrinterManagementView.swift': ('G6', 'NST'),
    'DICOMStudio/Views/ViewerPrintTrayView.swift': ('G6', 'NST'),
    'DICOMStudio/Components/PrinterStatusPresentation.swift': ('G6', 'ST'),
    'DICOMStudio/Models/PrinterProfile.swift': ('G6', 'ST'),
    'DICOMStudio/Services/PrintCellTextureCache.swift': ('G6', 'ST'),
    'DICOMStudio/Services/PrintService.swift': ('G6', 'ST'),
    'DICOMStudio/ViewModels/PrintSCPViewModel.swift': ('G6', 'ST'),
    'DICOMStudio/ViewModels/PrintViewModel+CellEditing.swift': ('G6', 'ST'),
    'DICOMStudio/ViewModels/PrintViewModel+PresentationStates.swift': ('G6', 'ST'),
    'DICOMStudio/ViewModels/PrintViewModel.swift': ('G6', 'ST'),
    'DICOMStudio/Views/Print/FilmPreviewView.swift': ('G6', 'ST'),
    'DICOMStudio/Views/Print/PrintSCPView.swift': ('G6', 'ST'),
    'DICOMStudio/Views/Print/PrintSettingsView.swift': ('G6', 'ST'),
}

WORKSHOP_TOOLS = {           # Workshop tool id -> CLI tool directory
    'dicom-info': 'dicom-info', 'dicom-dump': 'dicom-dump', 'dicom-tags': 'dicom-tags', 'dicom-diff': 'dicom-diff',
    'dicom-convert': 'dicom-convert', 'dicom-validate': 'dicom-validate', 'dicom-anon': 'dicom-anon',
    'dicom-compress': 'dicom-compress', 'dicom-split': 'dicom-split', 'dicom-merge': 'dicom-merge',
    'dicom-dcmdir': 'dicom-dcmdir', 'dicom-archive': 'dicom-archive', 'dicom-json': 'dicom-json',
    'dicom-xml': 'dicom-xml', 'dicom-pdf': 'dicom-pdf', 'dicom-image': 'dicom-image', 'dicom-export': 'dicom-export',
    'dicom-pixedit': 'dicom-pixedit', 'dicom-video': 'dicom-video', 'dicom-echo': 'dicom-echo',
    'dicom-query': 'dicom-query', 'dicom-send': 'dicom-send', 'dicom-retrieve': 'dicom-retrieve',
    'dicom-qr': 'dicom-qr', 'dicom-mwl': 'dicom-mwl', 'dicom-mpps': 'dicom-mpps',
    'dicom-qido': 'dicom-wado', 'dicom-wado': 'dicom-wado', 'dicom-stow': 'dicom-wado', 'dicom-ups': 'dicom-wado',
    'dicom-study': 'dicom-study', 'dicom-uid': 'dicom-uid', 'dicom-script': 'dicom-script',
}
# dicom-wado is split into four Workshop tools; each sees only its subcommand's options.
WADO_SUBCOMMAND = {'dicom-qido': 'query', 'dicom-wado': 'retrieve', 'dicom-stow': 'store', 'dicom-ups': 'ups'}
# Workshop fields that `CommandBuilderHelpers.buildCommand` folds into the tool's positional endpoint
# (`usesPositionalEndpoint`): the form shows --host / --port, the command gets `host:port`.
POSITIONAL = {t: {'--host': '<host>', '--port': '--port'} for t in
              ('dicom-echo', 'dicom-query', 'dicom-send', 'dicom-retrieve', 'dicom-qr', 'dicom-mwl', 'dicom-mpps')}

HELPERS = os.path.join(SOURCES, 'DICOMStudio', 'Components', 'CLIWorkshopHelpers.swift')


def studio_files(tier=None, group=None):
    out = {}
    for path, (g, t) in FILES.items():
        if (tier and t != tier) or (group and g != group):
            continue
        full = os.path.join(SOURCES, path)
        if os.path.exists(full):
            out[path] = dw.read(full)
    return out


def check_inventory(rep):
    """Every Swift file under Sources/DICOMStudio* is in FILES, and every FILES entry exists."""
    on_disk = set()
    for base in ('DICOMStudio', 'DICOMStudioApp'):
        for dp, _, names in os.walk(os.path.join(SOURCES, base)):
            for n in names:
                if n.endswith('.swift'):
                    on_disk.add(os.path.relpath(os.path.join(dp, n), SOURCES))
    missing = [f'{p}: on disk but not in FILES' for p in sorted(on_disk - set(FILES))]
    gone = [f'{p}: in FILES but not on disk' for p in sorted(set(FILES) - on_disk)]
    tiers = {t: sum(1 for _, (g, tt) in FILES.items() if tt == t) for t in ('ST', 'CR', 'NST')}
    rep.check(f'inventory: {len(on_disk)} Swift files classified (ST {tiers["ST"]}, CR {tiers["CR"]}, NST {tiers["NST"]})',
              len(on_disk & set(FILES)), missing + gone)


# --- Workshop surface -------------------------------------------------------------------------------

STR = re.compile(r'"((?:[^"\\]|\\.)*)"')


def swift_string_list(expr):
    expr = expr.strip()
    if expr.startswith('['):
        return [m.group(1) for m in STR.finditer(expr)], True
    return [], False           # computed (e.g. DICOMConverter.cliTokens)


def parse_definition(call):
    """`CLIParameterDefinition(...)` call text -> dict of its literal arguments."""
    body = call[call.index('(') + 1:-1]
    args, depth, cur, i, n = [], 0, '', 0, len(body)
    while i < n:
        c = body[i]
        if c == '"':
            j = i + 1
            while j < n and body[j] != '"':
                j += 2 if body[j] == '\\' else 1
            cur += body[i:j + 1]
            i = j + 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ',' and depth == 0:
            args.append(cur)
            cur = ''
        else:
            cur += c
        i += 1
    if cur.strip():
        args.append(cur)
    d = {}
    for a in args:
        if ':' not in a:
            continue
        k, v = a.split(':', 1)
        k, v = k.strip(), v.strip()
        if k in ('visibleWhen', 'visibleWhenAll', 'cliMapping'):
            d[k] = v
        elif v.startswith('"'):
            d[k] = STR.match(v).group(1)
        elif v.startswith('['):
            vals, literal = swift_string_list(v)
            d[k] = vals if literal else v
        elif v.startswith('.'):
            d[k] = v[1:]
        else:
            d[k] = v
    return d


def workshop_surface():
    """Workshop tool id -> list of parameter dicts (from `rawParameterDefinitions(for:)` and the helper functions
    it dispatches to: every `case "dicom-…":` arm anywhere in CLIWorkshopHelpers.swift that builds
    CLIParameterDefinition values, up to the next such arm or the end of its function)."""
    src = dw.read(HELPERS)
    # Only the parameter-definition functions: from rawParameterDefinitions to the Command Builder section.
    start = src.index('static func rawParameterDefinitions(for toolID: String)')
    end = src.index('// MARK: - 16.3 Command Builder Helpers', start)
    body = src[start:end]
    arms = list(re.finditer(r'^[ \t]*case ((?:"dicom-[a-z0-9-]+"(?:,\s*)?)+):', body, re.M))
    out = {}
    for idx, m in enumerate(arms):
        ids = re.findall(r'"([^"]+)"', m.group(1))
        nxt = arms[idx + 1].start() if idx + 1 < len(arms) else len(body)
        block = body[m.end():nxt]
        # stop at the end of the enclosing function (a `default:` or the closing of the switch)
        cut = re.search(r'^[ \t]*default:', block, re.M)
        if cut:
            block = block[:cut.start()]
        i = 0
        for t in ids:
            out.setdefault(t, [])
        while True:
            j = block.find('CLIParameterDefinition(', i)
            if j < 0:
                break
            k = dc.balanced(block, j + len('CLIParameterDefinition'))
            d = parse_definition(block[j:k])
            d['line'] = src.count('\n', 0, start + m.end() + j) + 1
            for t in ids:
                out[t].append(d)
            i = k
    return out


def cli_surface(tool):
    files, options, outputs, commands = dc.surface(tool)
    return files, options, outputs, commands


def enum_raw_values(src, name):
    """Raw values of a `enum Name: String` — explicit `case x = "v"` or implicit (`case x` -> "x"), ignoring
    deprecated cases and enums whose raw type is not String."""
    m = re.search(r'enum\s+' + re.escape(name) + r'\s*:\s*([^{]*)\{', src)
    if not m or 'String' not in m.group(1):
        return []
    body = dw.enum_body(src, name)
    body = re.sub(r'@available\([^)]*deprecated[^)]*\)[^\n]*\n[^\n]*case[^\n]*\n', '', body)
    # drop nested types' bodies so their cases are not counted
    out = []
    for cm in re.finditer(r'^\s*(?:public\s+)?case\s+([^\n]+)', body, re.M):
        for part in re.split(r',\s*(?![^"]*"\s*,)', cm.group(1)):
            part = part.strip()
            mm = re.match(r'`?(\w+)`?\s*(?:=\s*"([^"]*)")?', part)
            if mm and not part.startswith('.'):
                out.append(mm.group(2) if mm.group(2) is not None else mm.group(1))
    return out


def cli_accepted_values(tool, files, opt):
    """Accepted raw values of a String-backed enum option type, searched in the tool, then the engine modules."""
    typ = re.sub(r'[?\[\]]', '', opt['type']).strip()
    if not typ or typ in ('String', 'Int', 'Bool', 'Double', 'UInt16', 'UInt32', 'Int64', 'UInt8'):
        return None
    name = typ.split('.')[-1]
    for src in files.values():
        vals = enum_raw_values(src, name)
        if vals:
            return vals
    for mod in ('DICOMKit', 'DICOMNetwork', 'DICOMWeb', 'DICOMCore'):
        for fname, src in dw.read_all(os.path.join(SOURCES, mod)).items():
            vals = enum_raw_values(src, name)
            if vals:
                return vals
    return None


def resolve_swift_default(expr, sources):
    """`MergeSortCriteria.instanceNumber.rawValue` / `.instanceNumber` / `Type.staticLet` -> the literal, when findable."""
    expr = expr.strip()
    m = re.fullmatch(r'(\w+)\.(\w+)\.rawValue', expr)
    if m:
        for src in sources.values():
            body = dw.enum_body(src, m.group(1))
            if body:
                cm = re.search(r'case\s+' + re.escape(m.group(2)) + r'\b\s*(?:=\s*"([^"]*)")?', body)
                if cm:
                    return cm.group(1) if cm.group(1) is not None else m.group(2)
    m = re.fullmatch(r'(?:\w+\.)?(\w+)', expr)
    if m and not expr.islower():
        for src in sources.values():
            mm = re.search(r'static let ' + re.escape(m.group(1)) + r'\s*(?::\s*\w+)?\s*=\s*"([^"]+)"', src)
            if mm:
                return mm.group(1)
    return expr


def normalise_default(v):
    v = (v or '').strip().strip('"')
    return {'true': 'true', 'false': 'false'}.get(v.lower(), v)


def split_pending(items):
    pending = [i for i in items if any(k in i for k in PENDING_API_APPROVAL)]
    deferred = [i for i in items if any(k in i for k in DEFERRED)]
    wrong = [i for i in items if i not in pending and i not in deferred]
    return wrong, pending, deferred


def check_workshop_parity(rep, ws, tool_id):
    tool = WORKSHOP_TOOLS[tool_id]
    files, options, outputs, commands = cli_surface(tool)
    params = ws.get(tool_id, [])
    by_name = {}
    for o in options:
        for n in o['names']:
            by_name[n] = o
    matched, wrong, missing, extra = 0, [], [], []
    offered = set()
    for p in params:
        flag = p.get('flag', '')
        if p.get('isInternal') == 'true' or p.get('parameterType') == 'subcommand' or not flag.startswith('-'):
            if p.get('parameterType') == 'subcommand':
                vals = p.get('allowedValues', [])
                if isinstance(vals, list):
                    bad = [v for v in vals if v not in commands and v not in ('help',)]
                    if bad:
                        wrong.append(f'{tool_id}: subcommand picker offers {bad}, {tool} commands are {commands}')
                    else:
                        matched += 1
            continue
        key = f'{tool_id}: {flag} (CLIWorkshopHelpers.swift:{p["line"]})'
        flag = POSITIONAL.get(tool, {}).get(flag, flag)
        if flag not in by_name:
            if flag in EXEMPT:
                extra.append(f'{key}: not a {tool} option — exempt: {EXEMPT[flag]}')
            else:
                wrong.append(f'{key}: not a {tool} option')
            continue
        o = by_name[flag]
        offered.add(o['names'][-1])
        matched += 1
        neg = p.get('negatedFlag')
        if neg and neg not in by_name:
            wrong.append(f'{key}: negatedFlag {neg} is not a {tool} option')
        # defaults
        wd, cd = normalise_default(p.get('defaultValue')), normalise_default(o['default'])
        if cd.startswith('.'):
            cd = dc.raw_value(files, cd[1:])
        elif re.fullmatch(r'[A-Za-z_.]+', cd):            # `AnonCLI.defaultProfile` -> its literal
            cd = resolve_swift_default(cd, files)
        if re.fullmatch(r'[A-Za-z_.]+', wd) and not wd.islower():   # `MergeSortCriteria.instanceNumber.rawValue`
            engine = {}
            for mod in ('DICOMKit', 'DICOMNetwork', 'DICOMWeb', 'DICOMCore'):
                engine.update({mod + '/' + k: v for k, v in dw.read_all(os.path.join(SOURCES, mod)).items()})
            wd = resolve_swift_default(wd, {**studio_files(), **files, **engine})
        if wd and cd and wd.lower() != cd.lower() and not cd.startswith(('[', 'nil')):
            try:
                same = float(wd) == float(cd)
            except ValueError:
                same = False
            if not same:
                wrong.append(f'{key}: Workshop default {wd!r}, {tool} default {cd!r}')
        # picker values
        vals = p.get('allowedValues')
        if isinstance(vals, list) and vals:
            accepted = cli_accepted_values(tool, files, o)
            if accepted:
                bad = [v for v in vals if v not in accepted]
                lacking = [v for v in accepted if v not in vals]
                if bad:
                    wrong.append(f'{key}: picker offers {bad}, {tool} accepts {sorted(accepted)}')
                if lacking:
                    missing.append(f'{key}: picker lacks {lacking} of {tool}\'s accepted values')
    # contract rows with a standard verdict the Workshop does not offer
    sub = WADO_SUBCOMMAND.get(tool_id)
    for k, row in CONTRACT.get(tool, {}).items():
        verdict = (row + ('', '', '', ''))[3]
        if k.startswith('(') or k.startswith('<') or verdict.startswith('plumbing'):
            continue
        first = k.split()[0]
        if sub and first in WADO_SUBCOMMAND.values() and first != sub:
            continue
        toks = [t for t in re.split(r'[,\s]+', k) if t.startswith('--')]
        if toks and not any(t in offered or t in by_name and by_name[t]['names'][-1] in offered for t in toks):
            if k in EXEMPT:
                extra.append(f'{tool_id}: contract row {k} not offered — exempt: {EXEMPT[k]}')
            else:
                missing.append(f'{tool_id}: contract row {k} ({row[0]}; {row[1]}) is not offered by the Workshop')
    wrong, pending, deferred = split_pending(wrong + missing)
    rep.check(f'{tool_id}: Workshop form mirrors {tool} (flags, defaults, picker values, contract rows)',
              matched, wrong, pending=pending, extra=extra + [f'DEFR {d}' for d in deferred])


def check_generic(rep, parts, files, label):
    tags, local_tags = dk.tag_constants(os.path.join(SOURCES, 'DICOMCore'), files)
    uid_files = {n: re.sub(r'hasPrefix\("1\.2\.840\.10008[\d.]*"\)', 'hasPrefix("")', s) for n, s in files.items()}
    dw.check_uids(rep, parts[6], uid_files)
    dk.check_coded_concepts(rep, parts[16], files)
    dk.check_tag_names(rep, parts[6], files, local_tags)
    dk.check_citations(rep, {n: p for n, p in parts.items() if n in (3, 4, 5, 6, 10, 15, 16)}, files)
    dk.check_cs_literals(rep, parts[3], parts[6], files, tags)
    dk.check_photometric_terms(rep, parts[3], files)
    # dk.check_deidentification is not run: it checks DICOMKit's copy of Table E.1-1, which Studio does not carry.


# --- per-group checks (added as each group is verified) --------------------------------------------

# Each group's row-by-row checks live in Scripts/diff_studio_<g>[_topic].py (so the groups can be verified in
# parallel); a module exports CHECKS = [(name, fn(rep, parts, files, ctx))] and may extend PENDING_API_APPROVAL /
# DEFERRED / EXEMPT through its own dicts of the same names.
import glob as _glob
GROUP_CHECKS = {g: [] for g in GROUPS}
for _g in GROUPS:
    for _path in sorted(_glob.glob(os.path.join(HERE, f'diff_studio_{_g.lower()}*.py'))):
        _mod = load(os.path.basename(_path)[:-3])
        GROUP_CHECKS[_g] += list(getattr(_mod, 'CHECKS', []))
        PENDING_API_APPROVAL.update(getattr(_mod, 'PENDING_API_APPROVAL', {}))
        DEFERRED.update(getattr(_mod, 'DEFERRED', {}))
        EXEMPT.update(getattr(_mod, 'EXEMPT', {}))


# --- report emission ----------------------------------------------------------------------------------

def emit_parity(tool_id):
    ws = workshop_surface()
    tool = WORKSHOP_TOOLS[tool_id]
    files, options, outputs, commands = cli_surface(tool)
    by_name = {n: o for o in options for n in o['names']}
    rows = CONTRACT.get(tool, {})
    print(f'### {tool_id} → {tool}\n')
    print('| Workshop parameter | CLI option | DICOM concept | 2026a reference | Workshop values / default | CLI values / default | Verdict |')
    print('|---|---|---|---|---|---|---|')
    for p in ws.get(tool_id, []):
        flag = p.get('flag', '')
        o = by_name.get(flag)
        row = rows.get(o['names'][-1]) if o else None
        concept, ref = (row[0], row[1]) if row else ('', '')
        wv = p.get('allowedValues') if isinstance(p.get('allowedValues'), list) else []
        wd = p.get('defaultValue', '')
        cd = o['default'] if o else ''
        print(f"| `{p.get('id')}` ({p.get('parameterType')}) | `{flag or '—'}` | {concept} | {ref} | "
              f"{', '.join(wv)}{' / ' if wv and wd else ''}{wd} | `{o['type'] if o else '—'}`{' / ' + cd if cd else ''} | "
              f"{'match' if o else ('internal' if p.get('isInternal') == 'true' else 'not a CLI option')} |")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--nema')
    ap.add_argument('--edition', default='2026a')
    ap.add_argument('--group', choices=sorted(GROUPS))
    ap.add_argument('--tool', action='append', help='Workshop tool id(s) for the parity check')
    ap.add_argument('--only', help='run only checks whose name contains this text')
    ap.add_argument('--verbose', action='store_true')
    ap.add_argument('--inventory', action='store_true', help='print the not-standard-touching files and exit')
    ap.add_argument('--list-surface', action='store_true', help='print the Workshop form of each tool and exit')
    ap.add_argument('--emit-parity', metavar='TOOL', help='print the parity table for one Workshop tool and exit')
    args = ap.parse_args()

    if args.inventory:
        for path, (g, t) in sorted(FILES.items()):
            if t != 'ST':
                print(f'Sources/{path}\t{g}\t{t}')
        return
    if args.list_surface:
        ws = workshop_surface()
        for tool_id in (args.tool or sorted(ws)):
            print(f'== {tool_id}: {len(ws.get(tool_id, []))} parameters')
            for p in ws.get(tool_id, []):
                vals = p.get('allowedValues')
                print(f"   {p.get('parameterType', ''):14} {p.get('flag', ''):28} id={p.get('id', ''):22} "
                      f"default={p.get('defaultValue', '')!r:14} {vals if isinstance(vals, list) else (vals or '')}")
        return
    if args.emit_parity:
        emit_parity(args.emit_parity)
        return
    if not args.nema:
        sys.exit('--nema DIR is required')

    parts = {}
    for n in (3, 4, 5, 6, 10, 11, 15, 16, 18):
        path = os.path.join(args.nema, f'part{n:02d}_{args.edition}.xml')
        if not os.path.exists(path):
            print(f'missing {path} (fetch it); checks needing PS3.{n} are skipped', file=sys.stderr)
            continue
        parts[n] = nd.Part(path)
        if args.edition not in parts[n].subtitle:
            sys.exit(f'{path}: subtitle {parts[n].subtitle!r} does not name {args.edition}')
        print(f'using {path}: {parts[n].subtitle}')

    rep = dw.Report(args.verbose)
    groups = [args.group] if args.group else sorted(GROUPS)
    if not args.only or 'inventory' in args.only:
        check_inventory(rep)
    for g in groups:
        files = studio_files(tier='ST', group=g)
        print(f'\n== {g}: {GROUPS[g]} ({len(files)} standard-touching files)')
        if not args.only or 'generic' in args.only:
            check_generic(rep, parts, files, g)
        if g == 'G1' and (not args.only or 'parity' in args.only):
            ws = workshop_surface()
            for tool_id in (args.tool or sorted(WORKSHOP_TOOLS)):
                check_workshop_parity(rep, ws, tool_id)
        ctx = {'root': ROOT, 'sources': SOURCES, 'dw': dw, 'dk': dk, 'dc': dc, 'nd': nd, 'studio_files': studio_files,
               'workshop_surface': workshop_surface, 'split_pending': split_pending}
        for name, fn in GROUP_CHECKS[g]:
            if args.only and args.only not in name:
                continue
            fn(rep, parts, files, ctx)
    print(f'\n{rep.failed} check(s) with wrong or missing values, {rep.pending} pending owner approval')
    sys.exit(1 if rep.failed else 0)


if __name__ == '__main__':
    main()
