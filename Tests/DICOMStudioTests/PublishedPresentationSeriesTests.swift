// PublishedPresentationSeriesTests.swift
// DICOMStudioTests
//
// Whether a saved view actually becomes a series the reader can see.
//
// Saving writes GSPS objects into the study's folder, but the series pane is
// built from the library's index, not from the folder — so "the objects are on
// disk" and "the reader can see a series" are two different claims. These tests
// cover the second one, end to end: save, file into the index, and check that
// the pane's own catalogue produces a card for it.

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import DICOMPrintKit
import Foundation

@MainActor
@Suite("Published Presentation Series Tests")
struct PublishedPresentationSeriesTests {

    private static let studyUID = "1.2.3.4.5"
    private static let seriesUID = "1.2.3.4.5.6"
    private static let sopUID = "1.2.3.4.5.6.7"

    /// A study that exists on disk and in the library, with one image in it —
    /// which is what makes a study folder to publish into.
    private func makeStudy() throws -> (ImageViewerViewModel, LibraryModel, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublishedSeriesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)

        let elements: [DataElement] = [
            .string(tag: .sopClassUID, vr: .UI, value: "1.2.840.10008.5.1.4.1.1.2"),
            .string(tag: .sopInstanceUID, vr: .UI, value: Self.sopUID),
            .string(tag: .studyInstanceUID, vr: .UI, value: Self.studyUID),
            .string(tag: .seriesInstanceUID, vr: .UI, value: Self.seriesUID),
            .string(tag: .patientName, vr: .PN, value: "DOE^JANE"),
            .string(tag: .windowCenter, vr: .DS, value: "40"),
            .string(tag: .windowWidth, vr: .DS, value: "400")
        ]
        let file = DICOMFile.create(
            dataSet: DataSet(elements: elements),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: Self.sopUID)
        let imagePath = folder.appendingPathComponent("image.dcm")
        try file.write().write(to: imagePath)

        var library = LibraryModel()
        library.addStudy(StudyModel(studyInstanceUID: Self.studyUID))
        library.addSeries(SeriesModel(
            seriesInstanceUID: Self.seriesUID,
            studyInstanceUID: Self.studyUID,
            seriesNumber: 1,
            modality: "CT"))
        library.addInstance(InstanceModel(
            sopInstanceUID: Self.sopUID,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            seriesInstanceUID: Self.seriesUID,
            instanceNumber: 42,
            filePath: imagePath.path))

        let viewModel = ImageViewerViewModel()
        viewModel.dicomFile = file
        viewModel.filePath = imagePath.path
        viewModel.sopInstanceUID = Self.sopUID
        viewModel.studyInstanceUID = Self.studyUID
        viewModel.currentSeriesUID = Self.seriesUID
        viewModel.imageColumns = 512
        viewModel.imageRows = 512
        viewModel.viewContentWidth = 800
        viewModel.viewContentHeight = 600
        viewModel.presentationStateStore = PresentationStateStore(
            root: folder.appendingPathComponent("Store"))
        // The pane's own contents, which is what makes the study's folder
        // discoverable — `studySeriesDirectory` reads it, not `filePath`.
        viewModel.loadStudySeries(
            ViewerSeriesCatalog.entries(forStudy: Self.studyUID, in: library),
            studyUID: Self.studyUID)

        return (viewModel, library, folder)
    }

    private func cleanUp(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("Saving a view writes a PR series into the study's folder")
    func savingPublishesIntoTheStudyFolder() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))

        let published = try #require(viewModel.publishedPresentationSeries)
        #expect(published.modality == "PR")
        #expect(published.instances.count == 1)

        let url = try #require(published.instances.first?.url)
        #expect(url.deletingLastPathComponent().path == folder.path,
                "the series lands beside the study's own images")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("The published series appears in the series pane")
    func publishedSeriesAppearsInThePane() throws {
        let (viewModel, initialLibrary, folder) = try makeStudy()
        defer { cleanUp(folder) }
        var library = initialLibrary

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))
        let published = try #require(viewModel.publishedPresentationSeries)

        // What the shell does on the publish signal.
        library.addSeries(SeriesModel(
            seriesInstanceUID: published.seriesInstanceUID,
            studyInstanceUID: published.studyInstanceUID,
            seriesNumber: published.seriesNumber,
            modality: published.modality,
            seriesDescription: published.seriesDescription))
        for instance in published.instances {
            library.addInstance(InstanceModel(
                sopInstanceUID: instance.sopInstanceUID,
                sopClassUID: instance.sopClassUID,
                seriesInstanceUID: published.seriesInstanceUID,
                instanceNumber: instance.instanceNumber,
                filePath: instance.url.path))
        }

        let entries = ViewerSeriesCatalog.entries(forStudy: Self.studyUID, in: library)
        let pr = try #require(
            entries.first { $0.seriesInstanceUID == published.seriesInstanceUID },
            "the pane lists the presentation-state series alongside the images")

        #expect(pr.modality == "PR")
        #expect(pr.title == "Presentation States")
        #expect(pr.contentKind == ViewerContentKind.presentationState,
                "so the card draws its own icon rather than waiting on a thumbnail")
        #expect(pr.objectCount == 1)
    }

    @Test("Deleting the view takes its series back out")
    func deletingRemovesThePublishedObjects() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))
        let published = try #require(viewModel.publishedPresentationSeries)
        let url = try #require(published.instances.first?.url)

        viewModel.deleteSavedView(label: "Lung window")

        #expect(!FileManager.default.fileExists(atPath: url.path),
                "the study's copy goes with the saved view")
        #expect(viewModel.unpublishedPresentationStateUIDs
            .contains(published.instances[0].sopInstanceUID),
                "and the shell is told which instances to unfile")
    }

    @Test("A full turn is still a view worth saving")
    func fullTurnIsStillSaveable() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        // Four quarter turns back to upright. The picture is where it started,
        // but the reader chose this orientation and the tool was used, so the
        // view is theirs to name.
        for _ in 0..<4 { viewModel.rotateClockwise() }

        #expect(viewModel.rotationAngle == 0, "a full turn comes back to upright")
        #expect(viewModel.canSaveCurrentView,
                "and is still offerable to save — the reader turned the image")
    }

    @Test("Each quarter turn is saveable on the way round")
    func everyQuarterTurnIsSaveable() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        for turn in 1...4 {
            viewModel.rotateClockwise()
            #expect(viewModel.canSaveCurrentView,
                    "turn \(turn) of 4 is a view the reader can name")
        }
    }

    @Test("An upright view puts a rotated image back upright")
    func uprightViewRestoresUpright() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        // A view of the image the right way up, saved because the window was
        // chosen rather than because anything was turned.
        viewModel.windowCenter = 120
        viewModel.windowWidth = 80
        #expect(viewModel.canSaveCurrentView)
        #expect(viewModel.saveCurrentView(label: "Upright"))

        // The reader then turns the image, and picks the upright view again.
        viewModel.rotateClockwise()
        #expect(viewModel.rotationAngle == 90)
        #expect(viewModel.applySavedView(label: "Upright"))

        #expect(viewModel.rotationAngle == 0,
                "the saved view says upright, so applying it must turn it back")
    }

    @Test("A rotated view survives the round trip through the study")
    func rotationSurvivesTheRoundTrip() throws {
        for turns in 1...4 {
            let (viewModel, _, folder) = try makeStudy()
            defer { cleanUp(folder) }

            for _ in 0..<turns { viewModel.rotateClockwise() }
            let saved = viewModel.rotationAngle
            #expect(viewModel.saveCurrentView(label: "Turned"))

            // Somewhere else entirely, then back to the saved view.
            viewModel.applyDefaultView()
            #expect(viewModel.applySavedView(label: "Turned"))

            #expect(viewModel.rotationAngle == saved,
                    "\(turns) quarter turn(s) saved as \(saved)° must come back")
        }
    }

    @Test("A full turn is upright everywhere — viewer, saved view, and print")
    func fullTurnIsUprightThroughout() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        for _ in 0..<4 { viewModel.rotateClockwise() }

        // The viewer's own angle.
        #expect(viewModel.rotationAngle == 0,
                "four quarter turns wrap to upright, never to 360")

        // What print composes from — the same presentation the film uses.
        #expect(viewModel.currentPresentation.rotationDegrees == 0)
        #expect(viewModel.currentPresentation.quarterTurns == 0)
        #expect(viewModel.currentPresentation.isQuarterTurn,
                "so print takes the exact permute-only path, not a resample")

        // And what the GSPS records.
        #expect(viewModel.saveCurrentView(label: "Full turn"))
        let published = try #require(viewModel.publishedPresentationSeries)
        let url = try #require(published.instances.first?.url)
        let file = try DICOMFile.read(from: url)
        #expect(file.dataSet[.imageRotation]?.uint16Value == 0,
                "0 is enumerated; 360 is not a legal Image Rotation value")
        #expect(file.dataSet[.imageRotation]?.vr == .US,
                "Image Rotation is US per PS3.6 — dcmpschk rejects an IS-valued one")
    }

    @Test("An assigned 360 normalises rather than reaching print")
    func assignedFullTurnNormalises() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        // Straight at the property, bypassing the rotate tool's own snapping.
        viewModel.rotationAngle = 360

        #expect(viewModel.currentPresentation.rotationDegrees == 0,
                "ViewerPresentation normalises on the way in, so nothing downstream can see 360")
    }

    @Test("A view saved on a loose file publishes nowhere")
    func looseFileHasNoStudyFolder() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        // An image the study does not claim: the pane is the authority on what
        // the study consists of, and this is not in it.
        viewModel.filePath = "/tmp/not-part-of-any-study.dcm"
        viewModel.studySeries = []

        #expect(viewModel.studySeriesDirectory == nil)

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"),
                "the view still saves and still appears in the picker")
        #expect(viewModel.publishedPresentationSeries == nil,
                "but nothing is scattered into a folder that is not a study")
        #expect(!FileManager.default.fileExists(
            atPath: "/tmp/not-part-of-any-study.dcm"))
    }

    // MARK: - The pane's per-image list of presentation states

    @Test("The pane lists which image each presentation state is on")
    func paneListsStatesPerImage() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))

        let references = viewModel.savedViewReferences(forSeries: Self.seriesUID)
        let reference = try #require(references.first, "the image series carries one state")

        #expect(references.count == 1)
        #expect(reference.label == "Lung window")
        #expect(reference.imageSOPInstanceUID == Self.sopUID)
        // The *image's* numbers — how a reader finds the slice.
        #expect(reference.imageSeriesNumber == 1)
        #expect(reference.imageInstanceNumber == 42)
        #expect(reference.imageLocationLabel == "Series 1, image 42")
    }

    @Test("A presentation state reports its own series and instance number")
    func stateReportsItsOwnNumbering() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))

        let reference = try #require(
            viewModel.savedViewReferences(forSeries: Self.seriesUID).first)

        // The PR object is its own series — never the image's, which is the
        // whole point of stating both on the row.
        #expect(reference.stateSeriesNumber == 9001)
        #expect(reference.stateSeriesNumber != reference.imageSeriesNumber)
        #expect(reference.stateInstanceNumber == 1)
        #expect(reference.stateLocationLabel == "PR 9001 · 1")
    }

    @Test("The list is keyed by the image series, not the PR series")
    func listIsKeyedByTheImageSeries() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))

        let published = try #require(viewModel.publishedPresentationSeries)
        #expect(viewModel.savedViewReferences(
            forSeries: published.seriesInstanceUID).isEmpty,
                "the PR series' own card describes objects, not images with views")
        #expect(!viewModel.savedViewReferences(forSeries: Self.seriesUID).isEmpty)
    }

    @Test("Two views on one image are both listed")
    func twoViewsOnOneImageBothListed() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))
        viewModel.windowCenter = 40
        viewModel.windowWidth = 400
        #expect(viewModel.saveCurrentView(label: "Bone window"))

        let references = viewModel.savedViewReferences(forSeries: Self.seriesUID)
        #expect(references.count == 2)
        #expect(Set(references.map(\.label)) == ["Lung window", "Bone window"])
        #expect(references.allSatisfy { $0.imageSOPInstanceUID == Self.sopUID })
    }

    @Test("Deleting the last view empties the pane's list")
    func deletingEmptiesTheList() throws {
        let (viewModel, _, folder) = try makeStudy()
        defer { cleanUp(folder) }

        viewModel.zoomLevel = 2.5
        #expect(viewModel.saveCurrentView(label: "Lung window"))
        #expect(!viewModel.savedViewReferences(forSeries: Self.seriesUID).isEmpty)

        viewModel.deleteSavedView(label: "Lung window")

        #expect(viewModel.savedViewReferences(forSeries: Self.seriesUID).isEmpty)
        #expect(!viewModel.seriesHasSavedViews(Self.seriesUID),
                "and the badge goes with the list")
    }

    @Test("Saving a view with SR Report publishes Series 9002 (SR) alongside Series 9001 (PR) and cleans up on delete")
    func savingViewWithStructuredReportPublishesAndDeletesSRSeries() throws {
        let (viewModel, initialLibrary, folder) = try makeStudy()
        defer { cleanUp(folder) }
        var library = initialLibrary

        viewModel.zoomLevel = 2.0
        #expect(viewModel.saveCurrentView(label: "Lesion review", includeStructuredReport: true))

        let publishedPR = try #require(viewModel.publishedPresentationSeries)
        let publishedSR = try #require(viewModel.publishedStructuredReportSeries)
        #expect(publishedPR.seriesNumber == 9001)
        #expect(publishedPR.modality == "PR")
        #expect(publishedSR.seriesNumber == 9002)
        #expect(publishedSR.modality == "SR")
        #expect(publishedSR.referenceID.hasPrefix("SR-"))
        #expect(publishedSR.instances.count == 1)

        let srURL = try #require(publishedSR.instances.first?.url)
        #expect(FileManager.default.fileExists(atPath: srURL.path))

        // Register SR series in the library and verify it appears in the Viewer Series Pane catalog
        library.addSeries(SeriesModel(
            seriesInstanceUID: publishedSR.seriesInstanceUID,
            studyInstanceUID: publishedSR.studyInstanceUID,
            seriesNumber: publishedSR.seriesNumber,
            modality: publishedSR.modality,
            seriesDescription: publishedSR.seriesDescription))
        for instance in publishedSR.instances {
            library.addInstance(InstanceModel(
                sopInstanceUID: instance.sopInstanceUID,
                sopClassUID: instance.sopClassUID,
                seriesInstanceUID: publishedSR.seriesInstanceUID,
                instanceNumber: instance.instanceNumber,
                filePath: instance.url.path))
        }
        let entries = ViewerSeriesCatalog.entries(forStudy: Self.studyUID, in: library)
        #expect(entries.contains { $0.modality == "SR" && $0.seriesNumber == 9002 })

        // Verify the SR file parses as a Comprehensive SR (TID 1500) referencing the PR instance
        let srFile = try DICOMFile.read(from: srURL)
        let srDoc = try SRDocumentParser().parse(dataSet: srFile.dataSet)
        let extracted = PresentationStateSRBridge.extract(from: srDoc)
        #expect(extracted.presentationStateReferences.contains {
            $0.sopInstanceUID == publishedPR.instances.first?.sopInstanceUID
        })

        // Deleting the saved view removes both PR and SR files and reports both UIDs for removal
        let srInstanceUID = try #require(publishedSR.instances.first?.sopInstanceUID)
        viewModel.deleteSavedView(label: "Lesion review")
        #expect(!FileManager.default.fileExists(atPath: srURL.path))
        #expect(viewModel.unpublishedPresentationStateUIDs.contains(srInstanceUID))
    }
}
