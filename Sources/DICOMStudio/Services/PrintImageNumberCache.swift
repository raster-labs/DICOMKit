// PrintImageNumberCache.swift
// DICOMStudio
//
// DICOM Studio — the image numbers of the marked files.
//
// The image range is stated in the numbers a reader quotes — "print 3 to 9" —
// and those are Instance Numbers out of the files themselves. A mark does not
// always carry one: marking a whole series records the paths and the series they
// were reached through, deliberately, because reading two hundred headers to
// label a tray would stall the viewer for a list nobody has looked at yet.
//
// So the numbers are read when a range is actually wanted, once per file, and
// kept. Header only — parsing stops at Instance Number (0020,0013), a few
// hundred bytes in — so this costs a seek per file rather than a decode, and a
// two-hundred-slice CT resolves in the time it takes to open the control.
//
// Without this the range fell back to each mark's *position* in the tray, which
// is the same number only when a series is marked whole, from image one, with
// nothing skipped. Any other selection printed a run the reader did not ask for.
//
// NEMA-verified: 2026a, checked 2026-10-05 — the three tags read — Instance Number (0020,0013), Series Description
// (0008,103E), Modality (0008,0060) — checked against PS3.6 2026a Table 6-1 (names and tags match;
// Scripts/diff_studio_g6.py); the parse stops at Instance Number because it follows the other two in tag order.

import Foundation
import DICOMCore
import DICOMKit

@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
@MainActor
@Observable
public final class PrintImageNumberCache {

    /// Instance Number by file path, for the files that have been read.
    private var numbers: [String: Int] = [:]

    /// Series Description by file path, picked up in the same header read.
    ///
    /// The range control names each series' row, and a mark made without
    /// opening the file carries no description — leaving the row labelled by
    /// the containing folder, which in an export is routinely the Series
    /// Instance UID. The description sits at (0008,103E), *before* Instance
    /// Number in tag order, so the parse that is already running past it keeps
    /// it for free.
    private var descriptions: [String: String] = [:]

    /// Modality (0008,0060) by file path, picked up in the same header read.
    ///
    /// What lets the preset menu offer a CT's presets for a CT cell rather
    /// than every modality's. Like the description, it sits before Instance
    /// Number in tag order, so the parse already passes it.
    private var modalities: [String: String] = [:]

    /// Files read that turned out to carry no Instance Number, so they are not
    /// read again on every look.
    private var unnumbered: Set<String> = []

    private var inFlight: Set<String> = []

    /// Whether a read is in progress — what the range control greys itself out
    /// against, so a reader does not type a range against half the numbers.
    public private(set) var isLoading = false

    public init() {}

    /// The image number for a file, or `nil` if it has none or has not been read.
    public func number(forPath path: String) -> Int? { numbers[path] }

    /// The Series Description read from a file, or `nil` if it has none or has
    /// not been read.
    public func seriesDescription(forPath path: String) -> String? { descriptions[path] }

    /// The Modality read from a file, uppercased, or `nil` if it has none or
    /// has not been read.
    public func modality(forPath path: String) -> String? { modalities[path] }

    /// Whether every one of these files has been looked at.
    public func hasNumbers(for paths: [String]) -> Bool {
        paths.allSatisfy { numbers[$0] != nil || unnumbered.contains($0) }
    }

    /// Reads the image numbers of whatever these files still need.
    ///
    /// Concurrently, and header-only: the files are independent and the parse
    /// stops at the tag being read.
    public func load(paths: [String]) async {
        let wanted = paths.filter {
            numbers[$0] == nil && !unnumbered.contains($0) && !inFlight.contains($0)
        }
        guard !wanted.isEmpty else { return }

        inFlight.formUnion(wanted)
        isLoading = true
        defer {
            inFlight.subtract(wanted)
            isLoading = !inFlight.isEmpty
        }

        let found = await withTaskGroup(of: (String, Int?, String?, String?).self) { group in
            for path in wanted {
                group.addTask(priority: .userInitiated) {
                    let header = Self.readHeader(atPath: path)
                    return (path, header.instanceNumber, header.seriesDescription,
                            header.modality)
                }
            }
            var result: [(String, Int?, String?, String?)] = []
            for await entry in group { result.append(entry) }
            return result
        }

        for (path, number, description, modality) in found {
            if let number {
                numbers[path] = number
            } else {
                unnumbered.insert(path)
            }
            if let description {
                descriptions[path] = description
            }
            if let modality {
                modalities[path] = modality
            }
        }
    }

    /// Forgets everything — e.g. when the marks are cleared.
    public func clear() {
        numbers.removeAll()
        descriptions.removeAll()
        modalities.removeAll()
        unnumbered.removeAll()
        inFlight.removeAll()
        isLoading = false
    }

    /// Reads Instance Number (0020,0013) — and the Series Description and
    /// Modality the parse passes on the way — out of one file, and nothing else.
    private nonisolated static func readHeader(
        atPath path: String
    ) -> (instanceNumber: Int?, seriesDescription: String?, modality: String?) {
        guard let data = FileManager.default.contents(atPath: path) else { return (nil, nil, nil) }
        // Stops at the tag itself: Instance Number sits in the general image
        // module, well before the pixels, so this reads a header rather than a
        // file. `force` because a mark can point at a file with no preamble.
        let options = ParsingOptions(mode: .metadataOnly, stopAfterTag: .instanceNumber)
        guard let file = try? DICOMFile.read(from: data, force: true, options: options) else {
            return (nil, nil, nil)
        }
        let number = file.dataSet.string(for: .instanceNumber)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let description = file.dataSet.string(for: .seriesDescription)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modality = file.dataSet.string(for: Tag(group: 0x0008, element: 0x0060))?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (number.flatMap(Int.init),
                description?.isEmpty == false ? description : nil,
                modality?.isEmpty == false ? modality : nil)
    }
}
