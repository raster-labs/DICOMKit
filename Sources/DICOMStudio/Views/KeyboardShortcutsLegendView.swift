// KeyboardShortcutsLegendView.swift
// DICOMStudio
//
// DICOM Studio — the keys, written down.
//
// Reading is done with one hand on the keyboard: stepping a stack, windowing,
// marking, paging film. Shortcuts only pay for themselves if they can be found,
// so both screens that have them carry the same legend behind ⌘/ — one list per
// screen, describing what that screen actually binds.
//
// The legend is written by hand rather than derived from the views: SwiftUI does
// not expose what a `keyboardShortcut` was attached to, and a list that silently
// drifts from the bindings would be worse than none. Change a binding, change
// its line here.

#if canImport(SwiftUI)
import SwiftUI

/// A single binding: the keys, and what they do.
struct KeyboardShortcutHint: Identifiable {
    let keys: String
    let action: String

    var id: String { keys + action }

    init(_ keys: String, _ action: String) {
        self.keys = keys
        self.action = action
    }
}

/// A titled group of bindings.
struct KeyboardShortcutGroup: Identifiable {
    let title: String
    let hints: [KeyboardShortcutHint]

    var id: String { title }

    init(_ title: String, _ hints: [KeyboardShortcutHint]) {
        self.title = title
        self.hints = hints
    }
}

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct KeyboardShortcutsLegendView: View {
    let title: String
    let groups: [KeyboardShortcutGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        ForEach(group.hints) { hint in
                            GridRow {
                                Text(hint.keys)
                                    .font(.callout.monospaced())
                                    .gridColumnAlignment(.trailing)
                                Text(hint.action)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The two lists

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
extension KeyboardShortcutsLegendView {

    /// One line per drag tool, taken from the tools themselves.
    ///
    /// The rest of this file is hand-written because SwiftUI will not say what a
    /// `keyboardShortcut` was attached to. The tools are the exception: their
    /// keys, names and descriptions all live on ``ImageViewerDragTool``, and the
    /// buttons that bind them are built from the same list, so deriving these
    /// removes the one part of the legend that could silently go stale.
    static var toolHints: [KeyboardShortcutHint] {
        ImageViewerDragTool.allCases.map { tool in
            KeyboardShortcutHint(
                String(tool.shortcut).uppercased(),
                "\(tool.displayName) tool — \(tool.guidance)")
        }
    }

    /// What the viewer binds.
    static let viewerGroups: [KeyboardShortcutGroup] = [
        KeyboardShortcutGroup("Moving through the study", [
            KeyboardShortcutHint("← / →", "Previous / next image (frames, then files)"),
            KeyboardShortcutHint("↑ / ↓", "Previous / next file — skims past a cine loop"),
            KeyboardShortcutHint("Scroll", "Step through images, one per notch"),
        ]),
        // The tool keys are read off the tools themselves, so arming a tool and
        // reading about it cannot disagree. Everything below them is hand-written
        // like the rest of this file.
        KeyboardShortcutGroup("Choosing what a drag does", toolHints),
        KeyboardShortcutGroup("Annotating", [
            KeyboardShortcutHint("A", "Annotation tool — click to place text, or press "
                                 + "on the target and drag the label out, arrow attached"),
            KeyboardShortcutHint("L", "Length tool — drag between two points to draw a "
                                 + "ruler and display the distance measurement"),
            KeyboardShortcutHint("Drag", "Move an annotation; a selected one's handles "
                                 + "re-aim the arrow or adjust the measured length"),
            KeyboardShortcutHint("⌫", "Delete the selected annotation"),
        ]),
        KeyboardShortcutGroup("The image", [
            KeyboardShortcutHint("V", "Invert greys — monochrome images only"),
            KeyboardShortcutHint("[ / ]", "Flip left-to-right / top-to-bottom"),
            KeyboardShortcutHint("⌘= / ⌘-", "Zoom in / out"),
            KeyboardShortcutHint("F", "Fit image to view"),
            KeyboardShortcutHint("R", "Reset view — undoes every adjustment above"),
        ]),
        KeyboardShortcutGroup("Layout and panes", [
            KeyboardShortcutHint("⌘1 … ⌘4", "1×1, 2×2, 3×3, 4×4 tile grid"),
            KeyboardShortcutHint("S", "Show or hide the series pane"),
            KeyboardShortcutHint("T", "Show or hide the selected-images tray"),
        ]),
        KeyboardShortcutGroup("Printing", [
            KeyboardShortcutHint("M", "Mark or unmark this image for print"),
            KeyboardShortcutHint("⌘P", "Open the print sheet"),
        ]),
        KeyboardShortcutGroup("Help", [
            KeyboardShortcutHint("⌘/", "This list"),
            KeyboardShortcutHint("⌘O", "Open a DICOM file"),
        ]),
    ]

    /// What the print sheet binds. The film takes keyboard focus, so these land
    /// on the film rather than on whichever field was last touched.
    static let printPreviewGroups: [KeyboardShortcutGroup] = [
        KeyboardShortcutGroup("Moving over the film", [
            KeyboardShortcutHint("← / →", "Previous / next cell"),
            KeyboardShortcutHint("↑ / ↓", "Up / down a row"),
            KeyboardShortcutHint("⌥← / ⌥→", "Previous / next film"),
            KeyboardShortcutHint("esc", "Deselect the focused cell"),
        ]),
        KeyboardShortcutGroup("Adjusting a cell", [
            KeyboardShortcutHint("Right-click", "Every tool, on the cell under the pointer"),
            KeyboardShortcutHint("W", "Window/level tool — then drag on a cell"),
            KeyboardShortcutHint("Z", "Zoom tool"),
            KeyboardShortcutHint("P", "Pan tool"),
            KeyboardShortcutHint("Scroll", "Zoom the cell under the pointer"),
            KeyboardShortcutHint("V", "Invert the focused cell"),
            KeyboardShortcutHint(".", "Straighten the focused cell"),
            KeyboardShortcutHint("0", "Reset the focused cell"),
        ]),
        KeyboardShortcutGroup("Annotating", [
            KeyboardShortcutHint("T", "Text tool — click a cell to place text"),
            KeyboardShortcutHint("R", "Arrow tool — drag on a cell to draw one"),
            KeyboardShortcutHint("Drag", "Move an annotation; drag an end to aim an arrow"),
            KeyboardShortcutHint("⌫", "Delete the selected annotation"),
            KeyboardShortcutHint("I", "Patient ID caption on the cells"),
        ]),
        KeyboardShortcutGroup("The sheet", [
            KeyboardShortcutHint("⏎", "Print"),
            KeyboardShortcutHint("⌘.", "Cancel"),
            KeyboardShortcutHint("⌘/", "This list"),
        ]),
    ]
}

// MARK: - The button that shows it

/// A toolbar or header button that reveals the legend for one screen.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct KeyboardShortcutsButton: View {
    let title: String
    let groups: [KeyboardShortcutGroup]

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "keyboard")
        }
        .keyboardShortcut("/", modifiers: .command)
        .accessibilityLabel("Keyboard shortcuts")
        .help("Keyboard shortcuts (⌘/)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            KeyboardShortcutsLegendView(title: title, groups: groups)
        }
    }
}
#endif
