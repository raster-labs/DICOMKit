// MetadataViewModel.swift
// DICOMStudio
//
// DICOM Studio — Metadata viewer ViewModel
//
// NEMA-verified: 2026a, checked 2026-10-05 — tree nodes carry the tag, the DICOMCore VR (PS3.5 2026a Table 6.2-1, 34
// VRs) and the PS3.6 2026a Table 6-1 name from DICOMDictionary; File Meta Information (PS3.10 2026a Table 7.1-1) is
// listed before the Data Set; `TransferSyntaxDescriptions.describe` now returns the PS3.6 Table A-1 "UID Name" from
// DICOMCore `TransferSyntax.displayName` instead of its own table (13 rows, 5 were not the A-1 names); undefined
// length 0xFFFFFFFF per PS3.5 7.1.2; private groups per PS3.5 7.8.1 (PrivateTagIdentifier).

import Foundation
import Observation
import DICOMKit
import DICOMCore
import DICOMDictionary

/// ViewModel for the DICOM metadata viewer, managing tag display,
/// search, and sequence expansion.
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@Observable
public final class MetadataViewModel {

    /// The tree nodes representing all DICOM data elements.
    public var nodes: [MetadataTreeNode]

    /// Current search text for tag filtering.
    public var searchText: String

    /// The currently loaded file path.
    public var filePath: String?

    /// Transfer syntax information.
    public var transferSyntaxUID: String?

    /// Character set information.
    public var specificCharacterSet: String?

    /// Total number of data elements.
    public var totalElements: Int

    /// Error message if loading failed.
    public var errorMessage: String?

    /// The file service for parsing.
    public let fileService: DICOMFileService

    /// Creates a metadata ViewModel.
    public init(fileService: DICOMFileService = DICOMFileService()) {
        self.fileService = fileService
        self.nodes = []
        self.searchText = ""
        self.filePath = nil
        self.transferSyntaxUID = nil
        self.specificCharacterSet = nil
        self.totalElements = 0
        self.errorMessage = nil
    }

    /// Filtered nodes based on search text.
    public var filteredNodes: [MetadataTreeNode] {
        MetadataTreeBuilder.filter(nodes: nodes, searchText: searchText)
    }

    /// Human-readable transfer syntax description.
    public var transferSyntaxDescription: String {
        guard let uid = transferSyntaxUID else { return "Unknown" }
        return TransferSyntaxDescriptions.describe(uid)
    }

    /// Human-readable character set description.
    public var characterSetDescription: String {
        DICOMValueParser.characterSetDescription(specificCharacterSet ?? "")
    }

    /// Loads metadata from a DICOM file.
    ///
    /// - Parameter url: The file URL to load.
    public func loadFile(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let dicomFile = try DICOMFile.read(from: data)
            filePath = url.path
            transferSyntaxUID = dicomFile.fileMetaInformation.string(for: .transferSyntaxUID)
                ?? dicomFile.dataSet.string(for: .transferSyntaxUID)
            specificCharacterSet = dicomFile.dataSet.string(for: .specificCharacterSet)

            nodes = buildTree(from: dicomFile)
            totalElements = nodes.reduce(0) { $0 + $1.totalNodeCount }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load DICOM file: \(error.localizedDescription)"
            nodes = []
            totalElements = 0
        }
    }

    /// Clears the loaded metadata.
    public func clear() {
        nodes = []
        searchText = ""
        filePath = nil
        transferSyntaxUID = nil
        specificCharacterSet = nil
        totalElements = 0
        errorMessage = nil
    }

    // MARK: - Private Tree Building

    private func buildTree(from dicomFile: DICOMFile) -> [MetadataTreeNode] {
        var allNodes: [MetadataTreeNode] = []

        // Include File Meta Information
        for element in dicomFile.fileMetaInformation.allElements {
            allNodes.append(buildNode(from: element))
        }

        // Include main data set
        for element in dicomFile.dataSet.allElements {
            allNodes.append(buildNode(from: element))
        }

        return allNodes
    }

    private func buildNode(from element: DataElement) -> MetadataTreeNode {
        let group = element.tag.group
        let elementNum = element.tag.element
        let vrString = String(describing: element.vr)
        let isPrivate = PrivateTagIdentifier.isPrivateGroup(group)

        // Look up tag name from dictionary
        let entry = DataElementDictionary.lookup(tag: element.tag)
        let name = entry?.name ?? (isPrivate ? "Private Tag" : "Unknown Tag")

        // Format value
        let displayValue: String
        if element.vr == .SQ {
            let itemCount = element.sequenceItems?.count ?? 0
            displayValue = "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        } else if let stringVal = element.stringValue {
            displayValue = DICOMValueParser.format(value: stringVal, vr: vrString)
        } else {
            let byteCount = element.valueData.count
            displayValue = "[\(byteCount) bytes]"
        }

        // Build children for sequences
        var children: [MetadataTreeNode] = []
        if let items = element.sequenceItems {
            for (index, item) in items.enumerated() {
                let itemChildren = item.elements.values.sorted(by: { $0.tag < $1.tag }).map { buildNode(from: $0) }
                children.append(MetadataTreeNode(
                    group: group,
                    element: elementNum,
                    vr: "SQ",
                    name: "Item #\(index + 1)",
                    value: "\(item.elements.count) elements",
                    length: 0xFFFFFFFF,
                    children: itemChildren
                ))
            }
        }

        // Detect private creator
        let privateCreator: String?
        if isPrivate && PrivateTagIdentifier.isPrivateCreator(group: group, element: elementNum) {
            privateCreator = element.stringValue
        } else {
            privateCreator = nil
        }

        return MetadataTreeNode(
            group: group,
            element: elementNum,
            vr: vrString,
            name: name,
            value: displayValue,
            length: element.length,
            isPrivate: isPrivate,
            privateCreator: privateCreator,
            children: children
        )
    }
}

/// Platform-independent Transfer Syntax descriptions.
public enum TransferSyntaxDescriptions: Sendable {

    /// Returns the PS3.6 Table A-1 "UID Name" of a Transfer Syntax UID, from DICOMCore's
    /// registry (`TransferSyntax.displayName`, verbatim A-1 text), or "Unknown (uid)".
    ///
    /// Before 2026-10-05 this carried its own table of 13 abbreviated names, 5 of which were
    /// not the standard's names (e.g. "JPEG 2000 Lossless Only" for 1.2.840.10008.1.2.4.90).
    public static func describe(_ uid: String) -> String {
        let trimmed = uid.trimmingCharacters(in: .whitespaces)
        if let syntax = TransferSyntax.from(uid: trimmed) {
            return syntax.displayName
        }
        return "Unknown (\(trimmed))"
    }
}
