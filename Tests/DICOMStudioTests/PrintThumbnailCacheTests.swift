// PrintThumbnailCacheTests.swift
// DICOMStudioTests
//
// The film preview renders the actual marked frames, not numbered boxes.

import Testing
@testable import DICOMStudio
import DICOMPrintKit
import Foundation

#if canImport(CoreGraphics)

@MainActor
@Suite("Print Thumbnail Cache Tests")
struct PrintThumbnailCacheTests {

    /// Waits for the cache to settle on a mark: rendering is off the main actor,
    /// so the result lands a few hops later.
    private func waitForSettled(
        _ cache: PrintThumbnailCache,
        _ item: PrintSelectionItem,
        attempts: Int = 200
    ) async {
        for _ in 0..<attempts {
            // The exact arrangement, not the stand-in the cache serves during a
            // gesture — waiting on the stand-in would return before this
            // arrangement had rendered at all.
            if cache.renderedImage(for: item) != nil || cache.didFail(item) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Renders a thumbnail for a marked frame")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRendersThumbnail() async throws {
        let url = try #require(
            try StudioTestFixtures.url(named: "syn-ct.dcm"),
            "syn-ct.dcm fixture should be generated")
        let item = PrintSelectionItem(filePath: url.path)

        let cache = PrintThumbnailCache()
        #expect(cache.image(for: item) == nil, "nothing rendered before refresh")

        cache.refresh(for: [item])
        await waitForSettled(cache, item)

        let image = try #require(cache.image(for: item), "thumbnail should render")
        #expect(cache.didFail(item) == false)
        // Downscaled for the film cell rather than held at full size.
        #expect(max(image.width, image.height) <= 512)
        #expect(image.width > 0 && image.height > 0)
    }

    @Test("An unreadable mark fails once instead of blocking the preview")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testUnreadableMarkFails() async {
        let item = PrintSelectionItem(filePath: "/nonexistent/nope.dcm")
        let cache = PrintThumbnailCache()

        cache.refresh(for: [item])
        await waitForSettled(cache, item)

        #expect(cache.didFail(item))
        #expect(cache.image(for: item) == nil)
    }

    @Test("Unmarked images are evicted on refresh")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEvictsRemovedMarks() async throws {
        let url = try #require(try StudioTestFixtures.url(named: "syn-ct.dcm"))
        let kept = PrintSelectionItem(filePath: url.path)
        let dropped = PrintSelectionItem(filePath: url.path, frameIndex: 0)

        let cache = PrintThumbnailCache()
        cache.refresh(for: [kept])
        await waitForSettled(cache, kept)
        #expect(cache.image(for: kept) != nil)

        // The user unmarks everything; the cached frame must not linger.
        cache.refresh(for: [])
        #expect(cache.image(for: kept) == nil)
        #expect(cache.didFail(dropped) == false)
    }

    @Test("A re-arranged mark is re-rendered, not served from the old cache")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testArrangementInvalidatesThumbnail() async throws {
        let url = try #require(try StudioTestFixtures.url(named: "syn-ct.dcm"))
        let cache = PrintThumbnailCache()

        // The same frame, first unzoomed…
        let plain = PrintSelectionItem(filePath: url.path)
        cache.refresh(for: [plain])
        await waitForSettled(cache, plain)
        let plainImage = try #require(cache.image(for: plain))

        // …then zoomed. Identity is unchanged — file and frame are the same —
        // so a cache keyed on identity alone would serve the unzoomed picture.
        let zoomed = PrintSelectionItem(
            filePath: url.path,
            presentation: ViewerPresentation(
                zoom: 4.0, viewportWidth: 512, viewportHeight: 512))
        #expect(zoomed.id == plain.id, "the two marks are the same file and frame")

        cache.refresh(for: [zoomed])
        await waitForSettled(cache, zoomed)
        let zoomedImage = try #require(cache.image(for: zoomed))

        #expect(zoomedImage.width != plainImage.width
                || zoomedImage.height != plainImage.height,
                "the zoomed mark must render its own cropped picture")
    }

    @Test("A re-windowed cell keeps showing the previous picture while it renders")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testStandsInDuringAnEdit() async throws {
        let url = try #require(try StudioTestFixtures.url(named: "syn-ct.dcm"))
        let cache = PrintThumbnailCache()

        let before = PrintSelectionItem(filePath: url.path, windowCenter: 40, windowWidth: 400)
        cache.refresh(for: [before])
        await waitForSettled(cache, before)
        #expect(cache.renderedImage(for: before) != nil)

        // Mid-drag: a new window, so a new key, and nothing rendered for it yet.
        let during = PrintSelectionItem(filePath: url.path, windowCenter: 41, windowWidth: 400)
        cache.refresh(for: [during])
        #expect(cache.renderedImage(for: during) == nil, "the new window has not rendered yet")
        #expect(cache.image(for: during) != nil, "but the cell still has a picture to show")

        // And it does settle on its own picture rather than keeping the stand-in.
        await waitForSettled(cache, during)
        #expect(cache.renderedImage(for: during) != nil)
    }

    @Test("Clear forgets every thumbnail")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClear() async throws {
        let url = try #require(try StudioTestFixtures.url(named: "syn-ct.dcm"))
        let item = PrintSelectionItem(filePath: url.path)

        let cache = PrintThumbnailCache()
        cache.refresh(for: [item])
        await waitForSettled(cache, item)
        #expect(cache.image(for: item) != nil)

        cache.clear()
        #expect(cache.image(for: item) == nil)
    }
}

#endif
