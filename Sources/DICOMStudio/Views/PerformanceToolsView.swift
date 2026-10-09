// PerformanceToolsView.swift
// DICOMStudio
//
// DICOM Studio — Performance tools, tag dictionary, and conformance view
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (SwiftUI layout over the view model;
// every tag, UID, VR and SOP Class value it shows comes from PerformanceToolsHelpers.swift, verified there).

#if canImport(SwiftUI)
import SwiftUI

/// Performance tools view providing performance monitoring, cache management,
/// tag dictionary, UID lookup, transfer syntax info, and conformance statement.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct PerformanceToolsView: View {
    @Bindable var viewModel: PerformanceToolsViewModel

    public init(viewModel: PerformanceToolsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabPicker
            Divider()
            tabContent
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .confirmationDialog(
            "Clear All Caches",
            isPresented: $viewModel.isClearCacheConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                viewModel.clearAllCaches()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to clear all caches? This action cannot be undone.")
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PerformanceToolsTab.allCases, id: \.self) { tab in
                    Button {
                        viewModel.activeTab = tab
                    } label: {
                        Label(tab.displayName, systemImage: tab.sfSymbol)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.activeTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.displayName)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .performanceDashboard:
            dashboardContent
        case .cacheManagement:
            cacheContent
        case .tagDictionary:
            tagDictionaryContent
        case .uidLookup:
            uidLookupContent
        case .transferSyntaxInfo:
            transferSyntaxContent
        case .conformanceStatement:
            conformanceContent
        }
    }

    // MARK: - Performance Dashboard

    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    metricCard(title: "Full Parse", value: String(format: "%.1fms", viewModel.metrics.parseFullMs), icon: "doc")
                    metricCard(title: "Metadata Parse", value: String(format: "%.1fms", viewModel.metrics.parseMetadataOnlyMs), icon: "clock")
                    metricCard(title: "Render Time", value: String(format: "%.1fms", viewModel.metrics.renderTimeMs), icon: "photo")
                    metricCard(title: "Cache Hit Rate", value: String(format: "%.0f%%", viewModel.metrics.cacheHitRate * 100), icon: "arrow.triangle.2.circlepath")
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    metricCard(title: "Resident Memory", value: String(format: "%.1f MB", viewModel.metrics.memoryResidentMB), icon: "memorychip")
                    metricCard(title: "Virtual Memory", value: String(format: "%.1f MB", viewModel.metrics.memoryVirtualMB), icon: "memorychip.fill")
                    metricCard(title: "Mapped Files", value: "\(viewModel.metrics.memoryMappedFileCount)", icon: "doc.on.doc")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Benchmarks")
                                .font(.subheadline.bold())
                            Spacer()
                            if viewModel.isRunningBenchmark {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button("Export CSV") {
                                viewModel.exportBenchmarksToCSV()
                            }
                            .disabled(viewModel.benchmarkResults.isEmpty)
                            .accessibilityLabel("Export benchmark results as CSV")
                        }

                        if viewModel.benchmarkResults.isEmpty {
                            Text("No benchmarks run yet. Use the actions below to start.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60)
                        } else {
                            ForEach(viewModel.benchmarkResults, id: \.id) { result in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.type.rawValue)
                                            .font(.body)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "%.2fms", result.durationMs))
                                            .font(.body.monospaced())
                                        Text(result.status.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                }

                HStack {
                    Text("DICOMKit \(viewModel.dicomkitVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("DICOM Standard \(viewModel.dicomStandardVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    // MARK: - Cache Management

    private var cacheContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cache Management")
                    .font(.headline)
                Spacer()
                Picker("Cache Type", selection: $viewModel.selectedCacheType) {
                    ForEach(CacheType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Select cache type")

                Button("Clear Selected") {
                    viewModel.clearCache(for: viewModel.selectedCacheType)
                }
                .accessibilityLabel("Clear selected cache")

                Button("Clear All") {
                    viewModel.isClearCacheConfirmPresented = true
                }
                .accessibilityLabel("Clear all caches")
            }
            .padding()

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.currentCacheStats.itemCount)")
                        .font(.title3.bold())
                }
                Divider().frame(height: 30)
                VStack(spacing: 2) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatBytes(Int64(viewModel.currentCacheStats.currentSizeBytes)))
                        .font(.title3.bold())
                }
                Divider().frame(height: 30)
                VStack(spacing: 2) {
                    Text("Hit Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", viewModel.currentCacheStats.hitRate * 100))
                        .font(.title3.bold())
                }
                Spacer()
            }
            .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            if viewModel.currentCacheItems.isEmpty {
                ContentUnavailableView(
                    "Cache Empty",
                    systemImage: "internaldrive",
                    description: Text("No items in the \(viewModel.selectedCacheType.rawValue) cache.")
                )
            } else {
                List(viewModel.currentCacheItems, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.key)
                                .font(.body.monospaced())
                                .lineLimit(1)
                            Text(formatBytes(Int64(item.sizeBytes)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.lastAccessedAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Tag Dictionary

    private var tagDictionaryContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DICOM Tag Dictionary")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.filteredTagEntries.count) tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tags by name, group, or keyword…", text: Binding(
                    get: { viewModel.tagSearchQuery },
                    set: { viewModel.setTagSearchQuery($0) }
                ))
                .textFieldStyle(.plain)
                .accessibilityLabel("Search DICOM tags")

                if !viewModel.tagSearchQuery.isEmpty {
                    Button {
                        viewModel.setTagSearchQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            Divider()

            if viewModel.filteredTagEntries.isEmpty {
                ContentUnavailableView(
                    "No Tags Found",
                    systemImage: "tag",
                    description: Text("Try a different search term to find DICOM data elements.")
                )
            } else {
                List(viewModel.filteredTagEntries, id: \.id) { entry in
                    HStack {
                        Text(entry.tag)
                            .font(.body.monospaced())
                            .frame(width: 100, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.body)
                            Text("VR: \(entry.vr) • \(entry.keyword)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if entry.isRetired {
                            Text("Retired")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.red.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .accessibilityLabel("\(entry.name), tag \(entry.tag)")
                }
            }
        }
    }

    // MARK: - UID Lookup

    private var uidLookupContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UID Lookup & Generator")
                    .font(.headline)
                Spacer()
            }
            .padding()

            GroupBox("Generate UID") {
                HStack {
                    if viewModel.lastGeneratedUID.isEmpty {
                        Text("Click Generate to create a new DICOM UID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.lastGeneratedUID)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Generate") {
                        viewModel.generateUID()
                    }
                    .accessibilityLabel("Generate new UID")
                }
            }
            .padding(.horizontal)

            GroupBox("Validate UID") {
                HStack {
                    TextField("Enter UID to validate…", text: $viewModel.uidValidationInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .accessibilityLabel("UID validation input")
                        .onSubmit { viewModel.validateUID(viewModel.uidValidationInput) }
                    Button("Validate") {
                        viewModel.validateUID(viewModel.uidValidationInput)
                    }
                    .accessibilityLabel("Validate UID")
                }
                if let result = viewModel.uidValidationResult {
                    HStack {
                        Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.isValid ? .green : .red)
                        if let msg = result.errorMessage {
                            Text(msg)
                                .font(.caption)
                        } else {
                            Text(result.isValid ? "Valid UID" : "Invalid UID")
                                .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search UIDs…", text: Binding(
                    get: { viewModel.uidSearchQuery },
                    set: { viewModel.setUIDSearchQuery($0) }
                ))
                .textFieldStyle(.plain)
                .accessibilityLabel("Search UIDs")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            if viewModel.filteredUIDEntries.isEmpty {
                ContentUnavailableView(
                    "No UIDs Found",
                    systemImage: "magnifyingglass",
                    description: Text("Search for DICOM UIDs to see their definitions.")
                )
            } else {
                List(viewModel.filteredUIDEntries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.body)
                        Text(entry.uid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(entry.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Transfer Syntax Info

    private var transferSyntaxContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfer Syntaxes")
                    .font(.headline)
                Spacer()
            }
            .padding()

            if !viewModel.compatibilityNote.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text(viewModel.compatibilityNote)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            if viewModel.transferSyntaxEntries.isEmpty {
                ContentUnavailableView(
                    "No Transfer Syntaxes",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Transfer syntax information is not available.")
                )
            } else {
                List(viewModel.transferSyntaxEntries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.body)
                        Text(entry.uid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Label(entry.compressionType == .none ? "Uncompressed" : "Compressed",
                                  systemImage: entry.compressionType == .none ? "doc" : "archivebox")
                                .font(.caption)
                            if entry.compressionType == .lossy {
                                Label("Lossy", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Text(entry.supportStatus.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Conformance Statement

    private var conformanceContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conformance Statement")
                    .font(.headline)
                Spacer()
                Picker("Service", selection: Binding(
                    get: { viewModel.conformanceServiceFilter },
                    set: { viewModel.setConformanceServiceFilter($0) }
                )) {
                    ForEach(ConformanceServiceCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Filter by service category")
            }
            .padding()

            Divider()

            if viewModel.sopClassEntries.isEmpty && viewModel.filteredCapabilityEntries.isEmpty {
                ContentUnavailableView(
                    "Conformance Statement",
                    systemImage: "checkmark.seal",
                    description: Text("DICOMKit conformance capabilities are displayed here.")
                )
            } else {
                List {
                    if !viewModel.sopClassEntries.isEmpty {
                        Section("SOP Classes") {
                            ForEach(viewModel.sopClassEntries, id: \.id) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.body)
                                        Text(entry.uid)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                        Text("Role: \(entry.role.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    if !viewModel.filteredCapabilityEntries.isEmpty {
                        Section("Capabilities") {
                            ForEach(viewModel.filteredCapabilityEntries, id: \.id) { entry in
                                HStack {
                                    Image(systemName: entry.status == .supported ? "checkmark.seal.fill" : "xmark.seal")
                                        .foregroundStyle(entry.status == .supported ? .green : .gray)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.serviceName)
                                            .font(.body)
                                        Text(entry.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
#endif
