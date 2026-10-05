// SavedViewPickerView.swift
// DICOMStudio
//
// DICOM Studio — choosing between the default view and the reader's saved ones.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (menu, naming and deletion of saved views; the objects themselves are written by DICOMPrintKit's PresentationStateStore); the user-facing text 'presentation state series' names PS3.3 2026a A.33 objects without claiming attributes
//
// A picture can be read more than one way: a chest CT at a lung window, then a
// bone window, then soft tissue. Those are not revisions of one another — they
// are three legitimate ways of looking at the same slice, and a reader wants to
// move between them without setting each up again.
//
// The picker is therefore a *list*, not a toggle. "Default view" is always the
// first entry and always available: it is the image as the file describes it,
// and a reader must never be unable to get back to it. Saved views follow,
// newest first, and only those covering the image on screen are shown — a view
// saved on other images has nothing to say about this one, and offering it
// would be offering a no-op.
//
// The control hides itself when the study has nothing saved and the current
// view is untouched: there is then only one thing to look at, and a picker
// naming it is furniture.

#if canImport(SwiftUI)
import SwiftUI
import DICOMPrintKit

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct SavedViewPickerView: View {
    @Bindable var viewModel: ImageViewerViewModel

    /// Shown while the reader names a view.
    @State private var isNaming = false
    @State private var draftLabel = ""

    /// The view the reader has asked to delete, held for confirmation.
    ///
    /// Deleting a saved view throws away work that took setting up, so it asks
    /// first — and names what it is about to remove, because the picker is a
    /// list and "are you sure?" alone does not say which row.
    @State private var pendingDeletion: SavedView?

    /// Whether the pointer is over the save button.
    ///
    /// Tracked here rather than through `interactiveControl`, because the
    /// button now draws its own capsule and that modifier's job is to draw a
    /// plate for controls that draw nothing — see `saveButton`.
    @State private var isHoveringSave = false

    private var savedViews: [SavedView] { viewModel.savedViewsForCurrentImage }

    var body: some View {
        // Nothing saved and nothing worth saving: no control at all.
        if !savedViews.isEmpty || viewModel.canSaveCurrentView {
            // The pair is one toolbar item, so macOS draws the group's own
            // boundary immediately after the last thing in it. The save button
            // is that last thing with nothing after it, which put it hard up
            // against — and at toolbar scale, apparently *on* — the divider
            // line. The trailing room is what holds it clear; the centre
            // alignment keeps the two capsules on one midline.
            HStack(alignment: .center, spacing: 6) {
                picker
                saveButton
            }
            .padding(.trailing, Self.groupEdgeInset)
            .alert("Name this view", isPresented: $isNaming) {
                TextField("View name", text: $draftLabel)
                Button("Cancel", role: .cancel) { draftLabel = "" }
                // No `.disabled(trimmedDraft.isEmpty)` on these. An alert's
                // buttons are built once when it is presented, not rebuilt as
                // its text field changes, so a disabled state computed from
                // the draft sticks at whatever the draft was on open — which
                // left every save button permanently greyed out with a name
                // plainly typed in the box. `commitSave` drops an empty name
                // instead, which is the same guard in the one place that does
                // re-run when the reader actually clicks.
                Button("Save for This Image") { commitSave(scope: .currentImage) }
                // The series scope appears only where it would cover more than
                // the image save does — a lone image offering "save for the
                // series" would be a choice without a difference.
                if viewModel.canSaveViewForSeries {
                    Button("Save for This Series") { commitSave(scope: .currentSeries) }
                }
            } message: {
                Text("Saved views keep the window, zoom, pan and orientation "
                     + "of the image on screen. Saving for this series writes "
                     + "the same view onto every image of the series. Saving "
                     + "over a name replaces it."
                     + "\n\nThe view is added to the study as a presentation "
                     + "state series, with a reference ID you can quote.")
            }
            .alert(
                "Added to the study",
                isPresented: Binding(
                    get: { viewModel.publishedPresentationSeries != nil },
                    set: { if !$0 { viewModel.dismissPublishedSeriesConfirmation() } })
            ) {
                Button("OK") { viewModel.dismissPublishedSeriesConfirmation() }
            } message: {
                if let published = viewModel.publishedPresentationSeries {
                    // The reference ID is the point of the message: the series
                    // itself appears in the pane on its own, but the ID is what
                    // a reader writes into a report, and it exists nowhere they
                    // would otherwise look.
                    Text("“\(published.label)” is now series "
                         + "\(published.seriesNumber) (\(published.modality)) "
                         + "of this study.\n\nReference ID: \(published.referenceID)")
                }
            }
            .alert(
                "Delete “\(pendingDeletion?.label ?? "")”?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } })
            ) {
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
                Button("Delete", role: .destructive) {
                    if let pendingDeletion {
                        viewModel.deleteSavedView(label: pendingDeletion.label)
                    }
                    pendingDeletion = nil
                }
            } message: {
                Text("The saved view is removed from every image it covers, "
                     + "along with its presentation states in the study's "
                     + "series. The images themselves are not changed.")
            }
        }
    }

    // MARK: - Picker

    private var picker: some View {
        Menu {
            Button {
                viewModel.applyDefaultView()
            } label: {
                Label(
                    ImageViewerViewModel.defaultViewLabel,
                    systemImage: viewModel.selectedPresentationStateLabel == nil
                        ? "checkmark" : "")
            }

            if !savedViews.isEmpty {
                Divider()
                // Each view is a submenu rather than a plain button: a menu row
                // is a single button in SwiftUI and cannot carry a trailing
                // control, so the way to put delete *on the row* is to make the
                // row open onto its own actions. Applying stays the first item,
                // so the common action is still one keystroke down.
                ForEach(savedViews) { view in
                    Menu {
                        Button("Apply") { viewModel.applySavedView(view) }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            pendingDeletion = view
                        }
                    } label: {
                        Label(
                            // A series view and an image view answer to the
                            // same kind of name, so the reach is said here —
                            // it is the one fact the label cannot carry.
                            view.coveredImageCount > 1
                                ? "\(view.label) — \(view.coveredImageCount) images"
                                : view.label,
                            systemImage: viewModel.selectedPresentationStateLabel == view.label
                                ? "checkmark" : "")
                    } primaryAction: {
                        // Clicking the row itself still just applies the view —
                        // the submenu is for the second action, not a toll on
                        // the first.
                        viewModel.applySavedView(view)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.below.rectangle")
                Text(viewModel.selectedViewLabel)
                    .lineLimit(1)
            }
            // Carried on the label rather than the Menu: a borderless menu
            // draws its own chrome, and a background on the control itself
            // sits behind that chrome instead of around the text.
            .font(.system(size: StudioTypography.captionSize, weight: .medium))
            .foregroundStyle(Self.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Self.tint.opacity(isReadingASavedView ? 0.22 : 0.10),
                        in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    Self.tint.opacity(isReadingASavedView ? 0.85 : 0.35),
                    lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose how this image is displayed")
    }

    /// Room kept between the bookmark and the toolbar group's trailing edge.
    ///
    /// Small on purpose: enough that the badge's own highlight and the
    /// divider never touch, not so much that the pair drifts away from the
    /// items it belongs with.
    private static let groupEdgeInset: CGFloat = 6

    /// The colour that means "presentation state" in the toolbar.
    ///
    /// Deliberately not the accent colour: that already means "this tool is
    /// armed" on the windowing and zoom buttons a few items along, and a
    /// picker wearing it would read as a tool that is currently active. A
    /// colour of its own is what makes the control findable at a glance —
    /// which is the whole point, since a reader who does not spot it never
    /// learns their saved views exist.
    private static let tint = Color.purple

    /// Whether a saved view — rather than the file's own — is on screen.
    ///
    /// The two states share one colour so the control stays recognisable as
    /// the same thing, and differ in weight: a solid fill and a firm border
    /// while a saved reading is showing, a quiet outline at the default view.
    /// The badge would otherwise shout equally when there is nothing to say.
    private var isReadingASavedView: Bool {
        viewModel.selectedPresentationStateLabel != nil
    }

    // MARK: - Saving

    /// The save half of the pair: a tinted capsule carrying a bookmark.
    ///
    /// Shaped like the picker beside it rather than left as a bare glyph. A
    /// bare glyph with `interactiveControl`'s square plate under it was the
    /// problem: at toolbar scale the plate is a white-bordered box that
    /// appears from nowhere around a floating icon, next to a capsule that
    /// highlights as a capsule — two different vocabularies a few points
    /// apart, and the box read as a rendering artefact rather than as the
    /// control lighting up. Giving the button the picker's own capsule means
    /// the hover state is the capsule getting brighter, which is the same
    /// gesture the picker makes and needs no separate plate at all.
    ///
    /// The bookmark itself stays: it has a silhouette nothing else in this
    /// toolbar shares, so the control is found by outline rather than by
    /// squinting at a badge, and "keep this to come back to" is exactly what
    /// saving a view is.
    private var saveButton: some View {
        Button {
            // Offer the applied view's name — even after a tool edit cleared
            // the picker's checkmark — so adjusting a saved view and saving
            // again updates it rather than quietly making a second one.
            draftLabel = viewModel.savePromptLabel
            isNaming = true
        } label: {
            Image(systemName: "bookmark.fill")
                // Sized to the picker's text, so the two capsules come out the
                // same height. A `.body`-weight glyph next to an 11-point
                // label made the pair visibly uneven.
                .font(.system(size: StudioTypography.captionSize, weight: .semibold))
                .foregroundStyle(canSave ? Self.tint : Color.secondary)
                // Squarer than the picker's padding, because the content is a
                // glyph rather than a run of text: equal room either side is
                // what keeps the bookmark centred in its capsule.
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(saveCapsuleFill, in: Capsule())
                .overlay(Capsule().strokeBorder(saveCapsuleBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringSave = $0 }
        // Nothing to notice on the way in; the way out matters, so the capsule
        // fades rather than snapping as the pointer crosses to the picker.
        .animation(.easeOut(duration: 0.12), value: isHoveringSave)
        .animation(.easeOut(duration: 0.12), value: canSave)
        .disabled(!canSave)
        .help(canSave
              ? "Save the current window, zoom and orientation as a named view, "
                + "added to the study as a presentation state series"
              : "Adjust the image before saving a view")
        .accessibilityLabel("Save this view")
    }

    /// Whether there is anything to save. Named once because the button reads
    /// it four times over, and a stale second reading of the same question is
    /// how a control ends up coloured live and acting dead.
    private var canSave: Bool { viewModel.canSaveCurrentView }

    /// The capsule's fill: the picker's resting weight at rest, and the step
    /// it takes when armed used here for hover instead.
    ///
    /// Deliberately the *same* two values the picker moves between, so hovering
    /// the save reads as the same kind of change as reading a saved view — one
    /// vocabulary across the pair. A disabled button gets nothing but a hairline
    /// ghost, where a fill would promise an action that is not on offer.
    private var saveCapsuleFill: Color {
        guard canSave else { return Self.tint.opacity(0.04) }
        return Self.tint.opacity(isHoveringSave ? 0.22 : 0.10)
    }

    private var saveCapsuleBorder: Color {
        guard canSave else { return Color.secondary.opacity(0.25) }
        return Self.tint.opacity(isHoveringSave ? 0.85 : 0.35)
    }

    private var trimmedDraft: String {
        draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitSave(scope: ImageViewerViewModel.SavedViewScope) {
        let label = trimmedDraft
        guard !label.isEmpty else { return }
        if scope == .currentImage {
            // Synchronous, as it always was: the image's identity is in memory.
            viewModel.saveCurrentView(label: label)
        } else {
            // The series scopes read the covered images' headers, so the save
            // runs async and reports through the view model's own error state.
            Task { await viewModel.saveCurrentView(label: label, scope: scope) }
        }
        draftLabel = ""
    }
}
#endif

// MARK: - The on-image list, and where it went
//
// It used to live here as `SavedViewListPopover`, shared with the badge over
// the picture. It is gone: sharing one view between the toolbar and the centre
// panel meant a change made for either could stop the other working, and it
// repeatedly did — the rows lost their hit area to a shared hover modifier's
// default, and the list closed itself through `@Environment(\.dismiss)`, which
// cannot clear an `isPresented` its caller owns, so a row applied its view and
// left the list standing over the image it had just changed.
//
// The badge now opens `ViewerImageSavedViewList`, which owns its rows, its
// hover and its closing, and borrows nothing. This file keeps the toolbar
// picker's own menu, which was never the problem.
