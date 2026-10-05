// ViewerCommands.swift
// DICOMStudio
//
// DICOM Studio — macOS menu bar commands for the image viewer

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - FocusedValues key

extension FocusedValues {
    @Entry var imageViewerViewModel: ImageViewerViewModel? = nil
}

// MARK: - ViewerCommands

@available(macOS 14.0, *)
public struct ViewerCommands: Commands {
    @FocusedValue(\.imageViewerViewModel) private var viewModel: ImageViewerViewModel?

    private var hasImage: Bool { viewModel?.hasImage == true }
    private var hasFile: Bool  { viewModel?.dicomFile != nil }
    private var isMonochrome: Bool { viewModel?.isMonochrome == true }

    public init() {}

    public var body: some Commands {
        // View menu additions (zoom, fit, overlays)
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") { viewModel?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!hasImage)

            Button("Zoom Out") { viewModel?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!hasImage)

            Button("Reset View") { viewModel?.resetView() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!hasImage)

            Button("Fit to View") { viewModel?.fitToView() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!hasImage)

            Divider()

            Toggle("Image Metadata", isOn: Binding(
                get: { viewModel?.showMetadataOverlay ?? false },
                set: { viewModel?.showMetadataOverlay = $0 }
            ))
            .disabled(!hasImage)

            Divider()

            Toggle("DICOM Tag Inspector", isOn: Binding(
                get: { viewModel?.showDICOMInspector ?? false },
                set: { viewModel?.showDICOMInspector = $0 }
            ))
            .disabled(!hasFile)
        }

        // Image menu — transform and inversion
        CommandMenu("Image") {
            Button(viewModel?.isInverted == true ? "Remove Inversion" : "Invert Grayscale") {
                viewModel?.toggleInversion()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!isMonochrome)

            Divider()

            Button("Rotate Clockwise") { viewModel?.rotateClockwise() }
                .disabled(!hasImage)

            Button("Rotate Counter-Clockwise") { viewModel?.rotateCounterClockwise() }
                .disabled(!hasImage)

            Divider()

            Button("Flip Horizontal") { viewModel?.flipHorizontal() }
                .disabled(!hasImage)

            Button("Flip Vertical") { viewModel?.flipVertical() }
                .disabled(!hasImage)

            Divider()

            Button("Reset Transformations") { viewModel?.resetTransformations() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!hasImage)
        }
    }
}
#endif
