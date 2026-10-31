// MetadataView.swift
// DICOMStudio
//
// DICOM Studio — DICOM metadata viewer SwiftUI view

#if canImport(SwiftUI)
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

/// Metadata viewer displaying all DICOM data elements in a tree structure.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct MetadataView: View {
    @Bindable var viewModel: MetadataViewModel

    public init(viewModel: MetadataViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            metadataSearchBar

            Divider()

            // Info panel
            if viewModel.filePath != nil {
                metadataInfoPanel
                Divider()
            }

            // Content
            if let error = viewModel.errorMessage {
                errorView(error)
            } else if viewModel.nodes.isEmpty {
                emptyView
            } else {
                tagList
            }
        }
    }

    private var metadataSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search tags by name, group, or keyword...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search DICOM tags")
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear tag search")
            }
            Text("\(viewModel.filteredNodes.count) tags")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var metadataInfoPanel: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transfer Syntax")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.transferSyntaxDescription)
                    .font(.caption)
            }
            Divider().frame(height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Character Set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.characterSetDescription)
                    .font(.caption)
            }
            Divider().frame(height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Elements")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.totalElements)")
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5))
    }

    private var tagList: some View {
        List(viewModel.filteredNodes) { node in
            MetadataTreeRowView(node: node)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No DICOM metadata")
                .font(.headline)
            Text("Select a DICOM file to view its metadata")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No metadata loaded. Select a DICOM file to view its metadata.")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Error")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

/// Row view for a single metadata tree node.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
struct MetadataTreeRowView: View {
    let node: MetadataTreeNode

    var body: some View {
        if node.hasChildren {
            DisclosureGroup {
                ForEach(node.children) { child in
                    MetadataTreeRowView(node: child)
                }
            } label: {
                tagRowContent
            }
        } else {
            tagRowContent
        }
    }

    private var tagRowContent: some View {
        HStack(spacing: 8) {
            // Tag
            Text(node.tagString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(node.isPrivate ? .orange : .primary)

            // VR badge
            Text(node.vr)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(node.isSequence ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            // Name
            Text(node.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            // Value
            Text(node.value)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: 200, alignment: .trailing)

            // Copy button
            Button {
                copyToClipboard(node.copyValue)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy value of \(node.name)")
            .help("Copy value without display formatting")

            // Length
            Text(node.lengthString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name), tag \(node.tagString), value \(node.value)")
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS) || os(visionOS)
        UIPasteboard.general.string = text
        #endif
    }
}
#endif
