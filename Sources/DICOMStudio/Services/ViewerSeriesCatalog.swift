// ViewerSeriesCatalog.swift
// DICOMStudio
//
// DICOM Studio — building the viewer's series pane from the library.
//
// Entries are built from library metadata alone, so opening a study never waits
// on disk. Orientation is the one thing the library does not index; it is read
// from one file per series afterwards and folded in, which is why a card can
// briefly say "Orientation Unavailable" and then settle.
//
// NEMA-verified: 2026a, checked 2026-10-05 — plane label from Image Orientation (Patient) (0020,0037): slice normal
// = row × column direction cosines in the patient (LPS) coordinate system (PS3.3 2026a C.7.6.2.1.1), dominant
// component X→Sagittal, Y→Coronal, Z→Axial, anything more than ~32° off-axis left unlabelled; the plane names are
// clinical convention, not standard terms.

import Foundation
import DICOMCore
import DICOMKit

public enum ViewerSeriesCatalog {

    /// The series of a study, in series-number order, ready for the pane.
    public static func entries(
        forStudy studyUID: String,
        in library: LibraryModel
    ) -> [ViewerSeriesEntry] {
        library.seriesForStudy(studyUID).map { series in
            entry(for: series, in: library)
        }
        .sorted(by: isOrderedBefore)
    }

    /// Series-number order: ascending, unnumbered series last.
    ///
    /// The library's own ordering treats a missing Series Number as 0, which
    /// files unnumbered series *ahead* of series 1. Ties and missing numbers
    /// fall back to title then UID so the pane cannot reshuffle between two
    /// reads of the same study.
    static func isOrderedBefore(_ lhs: ViewerSeriesEntry, _ rhs: ViewerSeriesEntry) -> Bool {
        switch (lhs.seriesNumber, rhs.seriesNumber) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.seriesInstanceUID < rhs.seriesInstanceUID
    }

    private static func entry(
        for series: SeriesModel,
        in library: LibraryModel
    ) -> ViewerSeriesEntry {
        let instances = library.instancesForSeries(series.seriesInstanceUID)
        return ViewerSeriesEntry(
            seriesInstanceUID: series.seriesInstanceUID,
            title: title(for: series),
            seriesNumber: series.seriesNumber,
            modality: series.modality,
            orientation: nil,
            filePaths: instances.map(\.filePath),
            // A multi-frame series has more frames than objects; the pane
            // states both because a 1-object, 358-frame cine and a
            // 358-object stack read very differently.
            frameCount: instances.reduce(0) { $0 + ($1.numberOfFrames ?? 1) },
            // The first instance decides: a series is one SOP Class in
            // practice, and reading every instance to confirm it would make
            // opening a study proportional to its object count.
            // The transfer syntax comes too: a video instance carries an image
            // SOP Class, so without it the pane calls a clip "Images".
            contentKind: ViewerContentKind.kind(
                forSOPClassUID: instances.first?.sopClassUID,
                transferSyntaxUID: instances.first?.transferSyntaxUID),
            // What lets the pane say which slice a saved view is on: a
            // presentation state names its image by UID, and only the library
            // holds that image's Instance Number.
            instanceNumbersBySOPUID: instances.reduce(into: [String: Int]()) { map, instance in
                if let number = instance.instanceNumber {
                    map[instance.sopInstanceUID] = number
                }
            },
            // Per object as well as in total: a series of several cines shows
            // one preview per object, and the card needs each loop's length.
            frameCountsByFilePath: instances.reduce(into: [String: Int]()) { map, instance in
                map[instance.filePath] = instance.numberOfFrames ?? 1
            }
        )
    }

    /// The study a file belongs to, so the viewer can find its own pane contents.
    public static func studyUID(containing filePath: String, in library: LibraryModel) -> String? {
        guard let instance = library.instances.values.first(where: { $0.filePath == filePath })
        else { return nil }
        return library.series[instance.seriesInstanceUID]?.studyInstanceUID
    }

    /// Repairs entries whose instance order was lost, reading it off the files.
    ///
    /// The pane's order comes from the library index, and an index written by
    /// a build that could not read Instance Number — it is an IS, *text*, and
    /// was once read as binary, which always answered nil — files a series in
    /// file-system order forever after: re-imports are skipped as duplicates
    /// by SOP Instance UID, so the stale nils are never refreshed. The symptom
    /// is two viewers disagreeing about which image "17/31" is: this app in
    /// file order, any conformant viewer in acquisition order — and a saved
    /// presentation state, which names its image by UID, then *looks* like it
    /// landed on the wrong slice when it landed exactly where it was made.
    ///
    /// Off the main actor like orientation resolution and for the same reason:
    /// it reads headers, one per object, and a study open must not wait on
    /// them. Only series actually missing numbers are read at all, so a
    /// healthy library costs nothing.
    ///
    /// - Returns: The entries, re-sorted where numbers were recovered, and the
    ///   recovered numbers by SOP Instance UID — what the caller writes back
    ///   into the library so this reads the files once, not once per open.
    public static func resolvingInstanceOrder(
        _ entries: [ViewerSeriesEntry]
    ) async -> (entries: [ViewerSeriesEntry], recoveredNumbers: [String: Int]) {
        await Task.detached(priority: .utility) {
            var recovered: [String: Int] = [:]
            let repaired = entries.map { entry -> ViewerSeriesEntry in
                // Numbers the index already has are trusted; a series is only
                // read back when objects are missing theirs, which is the
                // stale-index shape. A lone object needs no order at all.
                // Video as well as pixels: a series of clips is ordered by
                // Instance Number like any other, and skipping the repair left
                // a stale index playing the recordings in file-system order.
                guard entry.hasPerObjectFrames, entry.filePaths.count > 1,
                      entry.instanceNumbersBySOPUID.count < entry.filePaths.count
                else { return entry }

                var numbersBySOPUID = entry.instanceNumbersBySOPUID
                var numbersByPath: [String: Int] = [:]
                for path in entry.filePaths {
                    guard let file = try? DICOMFile.read(
                              from: URL(fileURLWithPath: path),
                              options: .metadataOnly),
                          let sopUID = file.dataSet.string(for: .sopInstanceUID),
                          let number = DICOMFileService.integerString(
                              in: file.dataSet, tag: .instanceNumber)
                    else { continue }
                    numbersBySOPUID[sopUID] = number
                    numbersByPath[path] = number
                    recovered[sopUID] = number
                }
                guard !numbersByPath.isEmpty else { return entry }

                // The order the study asserts: Instance Number ascending, the
                // path tiebreak keeping unnumbered objects stable at the end —
                // the same rule the library's own sort applies.
                let ordered = entry.filePaths.sorted {
                    let left = numbersByPath[$0] ?? Int.max
                    let right = numbersByPath[$1] ?? Int.max
                    if left != right { return left < right }
                    return $0 < $1
                }
                return ViewerSeriesEntry(
                    seriesInstanceUID: entry.seriesInstanceUID,
                    title: entry.title,
                    seriesNumber: entry.seriesNumber,
                    modality: entry.modality,
                    orientation: entry.orientation,
                    filePaths: ordered,
                    frameCount: entry.frameCount,
                    contentKind: entry.contentKind,
                    instanceNumbersBySOPUID: numbersBySOPUID,
                    frameCountsByFilePath: entry.frameCountsByFilePath)
            }
            return (repaired, recovered)
        }.value
    }

    /// Re-reads orientation for each entry, one file per series.
    ///
    /// Off the main actor and after the pane is already on screen: orientation
    /// is a nicety, and blocking a study open on N file reads is not.
    public static func resolvingOrientations(
        _ entries: [ViewerSeriesEntry]
    ) async -> [ViewerSeriesEntry] {
        await Task.detached(priority: .utility) { () -> [ViewerSeriesEntry] in
            entries.map { entry in
                guard let path = entry.firstFilePath,
                      let orientation = readOrientation(atPath: path) else { return entry }
                return ViewerSeriesEntry(
                    seriesInstanceUID: entry.seriesInstanceUID,
                    title: entry.title,
                    seriesNumber: entry.seriesNumber,
                    modality: entry.modality,
                    orientation: orientation,
                    filePaths: entry.filePaths,
                    frameCount: entry.frameCount,
                    contentKind: entry.contentKind,
                    instanceNumbersBySOPUID: entry.instanceNumbersBySOPUID,
                    frameCountsByFilePath: entry.frameCountsByFilePath)
            }
        }.value
    }

    // MARK: - Helpers

    /// Series Description, falling back to something a reader can still use.
    private static func title(for series: SeriesModel) -> String {
        let description = series.seriesDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty { return description }
        if let number = series.seriesNumber {
            return "\(series.modality) series \(number)"
        }
        return series.modality
    }

    /// "Axial", "Coronal" or "Sagittal" from Image Orientation (Patient).
    ///
    /// Returns `nil` for oblique acquisitions rather than rounding them to the
    /// nearest plane — calling an oblique series "Axial" would be a clinical
    /// falsehood, and no label is better than a wrong one.
    static func readOrientation(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let file = try? DICOMFile.read(from: data, force: true),
              let raw = file.dataSet.string(for: .imageOrientationPatient) else { return nil }

        let values = raw.split(separator: "\\").compactMap { Double($0) }
        guard values.count == 6 else { return nil }

        // The slice normal is the cross product of the row and column cosines;
        // the dominant axis names the plane.
        let row = Array(values[0..<3])
        let column = Array(values[3..<6])
        let normal = [
            row[1] * column[2] - row[2] * column[1],
            row[2] * column[0] - row[0] * column[2],
            row[0] * column[1] - row[1] * column[0]
        ]

        let magnitudes = normal.map { abs($0) }
        guard let maximum = magnitudes.max(), maximum > 0 else { return nil }
        // Anything meaningfully off-axis is oblique, not one of the three planes.
        guard maximum > 0.85 else { return nil }

        switch magnitudes.firstIndex(of: maximum) {
        case 0:  return "Sagittal"
        case 1:  return "Coronal"
        case 2:  return "Axial"
        default: return nil
        }
    }
}
