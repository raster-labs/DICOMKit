// SidebarView.swift
// DICOMStudio
//
// DICOM Studio — Sidebar navigation view

#if canImport(SwiftUI)
import SwiftUI

/// Sidebar navigation listing feature areas grouped into collapsible
/// categories.
///
/// DICOM Studio is imaging-first: the Imaging group is expanded on launch
/// while Network, Data & Tools, and System start collapsed — so the sidebar
/// reads as a viewer with supporting tools rather than a flat list of
/// sixteen equal features. Running a search forces every group open so
/// matches are never hidden behind a collapsed section.
///
/// Two row sizes carry the hierarchy: category headers (and the standalone
/// Network Utility / Settings entries) are tall parent rows; the
/// destinations under a category are shorter child rows. Selection is shown
/// on both levels at once — the parent of the open screen wears the full
/// accent card, the screen itself a lighter tint beneath it.
@available(macOS 14.0, iOS 17.0, *)
struct SidebarView: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(NavigationCategory.allCases) { category in
                    let items = viewModel.filteredDestinations(in: category)
                    if !items.isEmpty {
                        categoryGroup(category, items: items)
                    }
                }

                Divider().padding(.vertical, 6)

                // Network Utility stands outside the category groups — it is a
                // general (non-DICOM) diagnostics tool, so it gets its own
                // top-level entry rather than living under "Data & Tools".
                parentRow(.networkUtility)
                parentRow(.settings)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .searchable(text: $viewModel.searchText, prompt: "Search features")
        .navigationTitle("DICOM Studio")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        #endif
    }

    // MARK: - Rows

    /// One collapsible category: a tall header row, then its child rows
    /// while it is open.
    @ViewBuilder
    private func categoryGroup(_ category: NavigationCategory,
                               items: [NavigationDestination]) -> some View {
        let isOpen = expanded(category)
        // Only a child listed under this header lights it up. Settings and
        // Network Utility nominally belong to a category but render as their
        // own top-level rows, so they must not highlight a header too.
        let holdsSelection = viewModel.selectedDestination.map(items.contains) ?? false

        CategoryHeader(category: category,
                       isExpanded: isOpen,
                       isSelected: holdsSelection)

        if isOpen.wrappedValue {
            // Children sit a full icon-column in from the header, with a thin
            // guide line down the left so the nesting is visible even when no
            // row is selected.
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.leading, 20)
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { destination in
                        childRow(destination)
                    }
                }
                .padding(.leading, 10)
            }
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// A destination under a category — the short row.
    private func childRow(_ destination: NavigationDestination) -> some View {
        let selected = viewModel.selectedDestination == destination
        return Button {
            viewModel.selectedDestination = destination
        } label: {
            HStack(spacing: 8) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 18)
                Text(label(for: destination))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .selectionCard(selected, emphasis: .light, cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: destination))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A standalone destination (Network Utility, Settings) — sized and
    /// styled like a category header so the sidebar's top level lines up.
    private func parentRow(_ destination: NavigationDestination) -> some View {
        let selected = viewModel.selectedDestination == destination
        return Button {
            viewModel.selectedDestination = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 22)
                Text(destination.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .selectionCard(selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Labels

    /// The row's text. Most destinations are simply their own name; Print also
    /// says what its queue is doing, since a job runs on regardless of which
    /// screen is open and a stalled or failed queue is otherwise invisible from
    /// here.
    private func label(for destination: NavigationDestination) -> String {
        guard destination == .printing,
              let state = printQueueState else { return destination.displayName }
        return "\(destination.displayName) — \(state)"
    }

    /// Spells the row out for VoiceOver: the destination's full description,
    /// plus the queue state when there is one.
    private func accessibilityLabel(for destination: NavigationDestination) -> String {
        guard destination == .printing,
              let state = printQueueState else { return destination.accessibilityLabel }
        return "\(destination.accessibilityLabel) — \(state)"
    }

    private var printQueueState: String? {
        viewModel.printViewModel.queue.activitySummary
    }

    /// Disclosure binding for one category. While a search is active the
    /// getter reports `true` for every category so no match stays hidden
    /// behind a collapsed section.
    private func expanded(_ category: NavigationCategory) -> Binding<Bool> {
        Binding(
            get: {
                guard viewModel.searchText.isEmpty else { return true }
                return viewModel.expandedCategories.contains(category)
            },
            set: { isOpen in
                if isOpen {
                    viewModel.expandedCategories.insert(category)
                } else {
                    viewModel.expandedCategories.remove(category)
                }
            }
        )
    }
}

/// A category's header row: icon, title, and a chevron that turns as the
/// group opens. The whole row toggles the group, not just the chevron, and
/// the row wears the full selection card while the open screen is one of
/// its children.
@available(macOS 14.0, iOS 17.0, *)
private struct CategoryHeader: View {
    let category: NavigationCategory
    @Binding var isExpanded: Bool
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 22)

                Text(category.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering && !isSelected ? Color.primary.opacity(0.06) : Color.clear)
            )
            .selectionCard(isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(category.rawValue)
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
