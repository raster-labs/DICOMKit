// ViewerCineAutoPlayTests.swift
// DICOMStudioTests
//
// A multi-frame file opens looping; a single-frame file does not. These run the
// real load path rather than setting `numberOfFrames` by hand, because the
// behaviour under test is a decision made *during* the load, from the header.

import Testing
@testable import DICOMStudio
import Foundation
import DICOMCore
import DICOMKit

@Suite("Viewer cine auto-play")
@MainActor
struct ViewerCineAutoPlayTests {

    // MARK: - Auto-play

    @Test("A multi-frame file opens already looping")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testMultiFrameOpensPlaying() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 12)
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)

        #expect(vm.numberOfFrames == 12)
        #expect(vm.isMultiFrame)
        #expect(vm.playbackState == .playing)
        #expect(vm.playbackMode == .loop)
        #expect(vm.currentFrameIndex == 0)
    }

    @Test("A single-frame file opens stopped")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSingleFrameOpensStopped() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 1)
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)

        #expect(vm.isMultiFrame == false)
        #expect(vm.playbackState == .stopped)
    }

    @Test("Auto-play off leaves a multi-frame file on frame 0")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testAutoPlayCanBeTurnedOff() throws {
        let vm = ImageViewerViewModel()
        vm.autoPlayMultiFrame = false
        let path = try writeTemporaryDICOM(frames: 12)
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)

        #expect(vm.isMultiFrame)
        #expect(vm.playbackState == .stopped)
        #expect(vm.currentFrameIndex == 0)
    }

    // MARK: - Stop and start

    @Test("Stopping a looping file halts it and rewinds")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testStopAfterAutoPlay() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 12)
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        vm.advanceCineFrame()
        vm.advanceCineFrame()
        #expect(vm.currentFrameIndex == 2)

        vm.stopPlayback()
        #expect(vm.playbackState == .stopped)
        #expect(vm.currentFrameIndex == 0)
    }

    @Test("Toggling a looping file pauses it where it stands, then resumes")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testPauseAndResumeAfterAutoPlay() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 12)
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        vm.advanceCineFrame()
        vm.advanceCineFrame()
        vm.advanceCineFrame()

        // Pause holds the frame on screen — unlike stop, which rewinds.
        vm.togglePlayback()
        #expect(vm.playbackState == .paused)
        #expect(vm.currentFrameIndex == 3)

        vm.togglePlayback()
        #expect(vm.playbackState == .playing)
        #expect(vm.currentFrameIndex == 3)
    }

    @Test("The loop wraps from the last frame back to the first")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLoopWraps() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 3)
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        vm.advanceCineFrame()   // 1
        vm.advanceCineFrame()   // 2 — the last frame
        #expect(vm.currentFrameIndex == 2)

        vm.advanceCineFrame()
        #expect(vm.currentFrameIndex == 0)
        #expect(vm.playbackState == .playing)
    }

    // MARK: - Frame rate from the header

    // The rate a file states for itself is recorded but not played at: every
    // file opens at the viewer's own default, because the 24–30 fps most
    // files ask for ran too fast to read.

    @Test("Recommended Display Frame Rate is recorded, and the loop still plays at the default")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testRecommendedDisplayFrameRate() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 12, recommendedDisplayFrameRate: "24")
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        #expect(vm.headerPlaybackFPS == 24.0)
        #expect(vm.playbackFPS == CinePlaybackHelpers.defaultFPS)
    }

    @Test("Cine Rate is read when no display frame rate is stated")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testCineRate() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 12, cineRate: "30")
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        #expect(vm.headerPlaybackFPS == 30.0)
        #expect(vm.playbackFPS == CinePlaybackHelpers.defaultFPS)
    }

    @Test("Frame Time in milliseconds inverts to a rate")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFrameTime() throws {
        let vm = ImageViewerViewModel()
        // 50 ms per frame → 20 fps.
        let path = try writeTemporaryDICOM(frames: 12, frameTime: "50.0")
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        #expect(vm.headerPlaybackFPS == 20.0)
    }

    @Test("Recommended Display Frame Rate wins over the other two")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testFrameRateTagPrecedence() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(
            frames: 12,
            recommendedDisplayFrameRate: "24",
            cineRate: "30",
            frameTime: "50.0")
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        #expect(vm.headerPlaybackFPS == 24.0)
    }

    @Test("A recorded rate outside the supported range is clamped")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testHeaderRateIsClamped() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 12, cineRate: "240")
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        #expect(vm.headerPlaybackFPS == CinePlaybackHelpers.maxFPS)
    }

    @Test("Opening a file resets the rate to the default, even after the reader changed it")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testLoadResetsToDefaultRate() throws {
        let vm = ImageViewerViewModel()
        vm.playbackFPS = 8.0
        let path = try writeTemporaryDICOM(frames: 12)
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        #expect(vm.headerPlaybackFPS == nil)
        #expect(vm.playbackFPS == CinePlaybackHelpers.defaultFPS)
    }

    @Test("A zero or malformed rate is ignored rather than dividing by it")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testMalformedHeaderRateIgnored() throws {
        let vm = ImageViewerViewModel()
        let path = try writeTemporaryDICOM(frames: 12, cineRate: "0", frameTime: "abc")
        defer { try? FileManager.default.removeItem(atPath: path) }

        vm.loadFile(at: path)
        #expect(vm.headerPlaybackFPS == nil)
        #expect(vm.playbackFPS == CinePlaybackHelpers.defaultFPS)
    }

    // MARK: - Helpers

    /// Writes a minimal uncompressed 8-bit grayscale file with `frames` frames.
    private func writeTemporaryDICOM(
        frames: Int,
        recommendedDisplayFrameRate: String? = nil,
        cineRate: String? = nil,
        frameTime: String? = nil
    ) throws -> String {
        let rows = 4, columns = 4
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.\(UUID().uuidString.prefix(8))", for: .sopInstanceUID, vr: .UI)
        ds.setString("US", for: .modality, vr: .CS)
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        if frames > 1 {
            ds.setString(String(frames), for: .numberOfFrames, vr: .IS)
        }
        if let rate = recommendedDisplayFrameRate {
            ds.setString(rate, for: .recommendedDisplayFrameRate, vr: .IS)
        }
        if let rate = cineRate {
            ds.setString(rate, for: .cineRate, vr: .IS)
        }
        if let time = frameTime {
            ds.setString(time, for: .frameTime, vr: .DS)
        }

        // One distinct grey per frame, so a frame index means something visible.
        var pixels = Data()
        for frame in 0..<frames {
            pixels.append(contentsOf: [UInt8](
                repeating: UInt8(truncatingIfNeeded: frame * 8),
                count: rows * columns))
        }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixels)

        var fmi = DataSet()
        fmi.setString("1.2.840.10008.1.2.1", for: Tag(group: 0x0002, element: 0x0010), vr: .UI)
        fmi.setString("1.2.840.10008.5.1.4.1.1.7",
                      for: Tag(group: 0x0002, element: 0x0002), vr: .UI)
        fmi.setString("1.2.3.4.5", for: Tag(group: 0x0002, element: 0x0003), vr: .UI)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cine-\(UUID().uuidString).dcm")
        try DICOMFile(fileMetaInformation: fmi, dataSet: ds).write().write(to: url)
        return url.path
    }
}
