// StudyPresentationStateAdoption.swift
// DICOMStudio
//
// DICOM Studio — taking a study's own presentation states into the store.
//
// NEMA-verified: 2026a, checked 2026-10-05 — reads Referenced Series Sequence (0008,1115) › Referenced Image Sequence (0008,1140) › Referenced SOP Instance UID (0008,1155) as PS3.3 2026a C.11.11 (Presentation State Relationship Module) lays them out, and Rows (0028,0010), Columns (0028,0011), Number of Frames (0028,0008) from image headers; the presentation-state SOP Classes themselves are DICOMPrintKit's PresentationStateStore.presentationStateSOPClasses
//
// A study imported with PR objects in it — a PACS export, a Weasis session
// with its measurements saved — carried them into the library like any other
// series, where the pane could name them and nothing could show them: the
// viewer's saved views come from `PresentationStateStore`, which listed only
// what this app had saved. This is the bridge: on opening a study, every PR
// object the library indexes for it is offered to the store, which copies
// the ones it does not already hold and converts what they draw into the
// app's own annotation channel. GSPS, CSPS and Pseudo-Color alike.
//
// Run from `MainViewModel.populateViewerSeriesPane`, before the viewer is
// told about the study, so its first look already includes them. Idempotent:
// the store keys on SOP Instance UID and a second open is a no-op.

import Foundation
import DICOMCore
import DICOMKit
import DICOMPrintKit

public enum StudyPresentationStateAdoption {

    /// Offers the study's presentation-state objects to the store.
    ///
    /// Cheap when there is nothing to do: the library is consulted first, and
    /// a study with no PR series touches no file. When there is one, the
    /// dimensions of the images it references are taken from the index where
    /// indexed and read from the file header otherwise — one read per
    /// referenced image, never the whole study.
    @discardableResult
    public static func adopt(
        studyUID: String,
        in library: LibraryModel,
        into store: PresentationStateStore
    ) -> PresentationStateStore.AdoptionResult {
        let instances = library.seriesForStudy(studyUID)
            .flatMap { library.instancesForSeries($0.seriesInstanceUID) }

        let presentationStates = instances.filter {
            PresentationStateStore.presentationStateSOPClasses.contains($0.sopClassUID)
        }
        guard !presentationStates.isEmpty else { return PresentationStateStore.AdoptionResult() }

        // Only the images the objects actually name need dimensions — and a
        // header read is only spent on those the index has no size for.
        let referenced = referencedImageUIDs(of: presentationStates)
        var images: [String: PresentationStateStore.AdoptableImage] = [:]
        for instance in instances
        where referenced.contains(instance.sopInstanceUID)
            && !PresentationStateStore.presentationStateSOPClasses.contains(instance.sopClassUID) {
            if let columns = instance.columns, let rows = instance.rows, columns > 0, rows > 0 {
                images[instance.sopInstanceUID] = .init(
                    sopInstanceUID: instance.sopInstanceUID,
                    columns: columns, rows: rows,
                    numberOfFrames: instance.numberOfFrames ?? 1)
            } else if let read = readDimensions(atPath: instance.filePath) {
                images[instance.sopInstanceUID] = .init(
                    sopInstanceUID: instance.sopInstanceUID,
                    columns: read.columns, rows: read.rows,
                    numberOfFrames: instance.numberOfFrames ?? read.frames)
            }
        }

        return store.adopt(
            presentationStateFiles: presentationStates.map { URL(fileURLWithPath: $0.filePath) },
            studyInstanceUID: studyUID,
            images: images)
    }

    /// Every image the given objects reference, read from their Referenced
    /// Series Sequences.
    static func referencedImageUIDs(of presentationStates: [InstanceModel]) -> Set<String> {
        var uids = Set<String>()
        for instance in presentationStates {
            guard let file = try? DICOMFile.read(from: URL(fileURLWithPath: instance.filePath)),
                  let series = file.dataSet.sequence(for: .referencedSeriesSequence) else { continue }
            for item in series {
                for image in item[.referencedImageSequence]?.sequenceItems ?? [] {
                    if let uid = image.string(for: .referencedSOPInstanceUID)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty {
                        uids.insert(uid)
                    }
                }
            }
        }
        return uids
    }

    /// Rows, Columns and Number of Frames from a file's header.
    static func readDimensions(atPath path: String) -> (columns: Int, rows: Int, frames: Int)? {
        guard let file = try? DICOMFile.read(from: URL(fileURLWithPath: path)),
              let rows = file.dataSet.uint16(for: .rows),
              let columns = file.dataSet.uint16(for: .columns),
              rows > 0, columns > 0 else { return nil }
        let frames = file.dataSet.string(for: .numberOfFrames)
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1
        return (Int(columns), Int(rows), max(1, frames))
    }
}
