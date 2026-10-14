// CinePlaybackHelpersTests.swift
// DICOMStudioTests
//
// Tests for CinePlaybackHelpers

import Testing
@testable import DICOMStudio
import Foundation

@Suite("PlaybackState Tests")
struct PlaybackStateTests {

    @Test("PlaybackState raw values")
    func testRawValues() {
        #expect(PlaybackState.stopped.rawValue == "stopped")
        #expect(PlaybackState.playing.rawValue == "playing")
        #expect(PlaybackState.paused.rawValue == "paused")
    }
}

@Suite("PlaybackMode Tests")
struct PlaybackModeTests {

    @Test("PlaybackMode raw values")
    func testRawValues() {
        #expect(PlaybackMode.loop.rawValue == "loop")
        #expect(PlaybackMode.bounce.rawValue == "bounce")
        #expect(PlaybackMode.once.rawValue == "once")
    }

    @Test("PlaybackMode is CaseIterable")
    func testCaseIterable() {
        #expect(PlaybackMode.allCases.count == 3)
    }
}

@Suite("CinePlaybackHelpers Tests")
struct CinePlaybackHelpersTests {

    // MARK: - FPS Constants

    @Test("FPS constants")
    func testFPSConstants() {
        #expect(CinePlaybackHelpers.minFPS == 1.0)
        #expect(CinePlaybackHelpers.maxFPS == 60.0)
        #expect(CinePlaybackHelpers.defaultFPS == 5.0)
    }

    // MARK: - clampFPS

    @Test("Clamp FPS within range")
    func testClampFPSNormal() {
        #expect(CinePlaybackHelpers.clampFPS(30) == 30)
    }

    @Test("Clamp FPS below minimum")
    func testClampFPSBelowMin() {
        #expect(CinePlaybackHelpers.clampFPS(0.5) == 1.0)
    }

    @Test("Clamp FPS above maximum")
    func testClampFPSAboveMax() {
        #expect(CinePlaybackHelpers.clampFPS(100) == 60.0)
    }

    @Test("Clamp FPS at boundaries")
    func testClampFPSBoundaries() {
        #expect(CinePlaybackHelpers.clampFPS(1.0) == 1.0)
        #expect(CinePlaybackHelpers.clampFPS(60.0) == 60.0)
    }

    // MARK: - timerInterval

    @Test("Timer interval at 30 FPS")
    func testTimerInterval30FPS() {
        let interval = CinePlaybackHelpers.timerInterval(for: 30)
        #expect(abs(interval - 1.0 / 30.0) < 0.0001)
    }

    @Test("Timer interval at 1 FPS")
    func testTimerInterval1FPS() {
        #expect(CinePlaybackHelpers.timerInterval(for: 1) == 1.0)
    }

    @Test("Timer interval at 60 FPS")
    func testTimerInterval60FPS() {
        let interval = CinePlaybackHelpers.timerInterval(for: 60)
        #expect(abs(interval - 1.0 / 60.0) < 0.0001)
    }

    // MARK: - nextFrame (loop)

    @Test("Loop mode advances forward")
    func testNextFrameLoop() {
        let result = CinePlaybackHelpers.nextFrame(current: 0, total: 10, mode: .loop, direction: .forward)
        #expect(result.frame == 1)
        #expect(result.direction == .forward)
        #expect(result.shouldStop == false)
    }

    @Test("Loop mode wraps at end")
    func testNextFrameLoopWrap() {
        let result = CinePlaybackHelpers.nextFrame(current: 9, total: 10, mode: .loop, direction: .forward)
        #expect(result.frame == 0)
        #expect(result.shouldStop == false)
    }

    @Test("Loop mode middle frame")
    func testNextFrameLoopMiddle() {
        let result = CinePlaybackHelpers.nextFrame(current: 5, total: 10, mode: .loop, direction: .forward)
        #expect(result.frame == 6)
    }

    // MARK: - nextFrame (bounce)

    @Test("Bounce mode forward advances")
    func testNextFrameBounceForward() {
        let result = CinePlaybackHelpers.nextFrame(current: 3, total: 10, mode: .bounce, direction: .forward)
        #expect(result.frame == 4)
        #expect(result.direction == .forward)
    }

    @Test("Bounce mode reverses at end")
    func testNextFrameBounceReverseAtEnd() {
        let result = CinePlaybackHelpers.nextFrame(current: 9, total: 10, mode: .bounce, direction: .forward)
        #expect(result.frame == 8)
        #expect(result.direction == .backward)
    }

    @Test("Bounce mode backward advances")
    func testNextFrameBounceBackward() {
        let result = CinePlaybackHelpers.nextFrame(current: 5, total: 10, mode: .bounce, direction: .backward)
        #expect(result.frame == 4)
        #expect(result.direction == .backward)
    }

    @Test("Bounce mode reverses at start")
    func testNextFrameBounceReverseAtStart() {
        let result = CinePlaybackHelpers.nextFrame(current: 0, total: 10, mode: .bounce, direction: .backward)
        #expect(result.frame == 1)
        #expect(result.direction == .forward)
    }

    // MARK: - nextFrame (once)

    @Test("Once mode advances forward")
    func testNextFrameOnce() {
        let result = CinePlaybackHelpers.nextFrame(current: 0, total: 10, mode: .once, direction: .forward)
        #expect(result.frame == 1)
        #expect(result.shouldStop == false)
    }

    @Test("Once mode stops at end")
    func testNextFrameOnceStopsAtEnd() {
        let result = CinePlaybackHelpers.nextFrame(current: 9, total: 10, mode: .once, direction: .forward)
        #expect(result.frame == 9)
        #expect(result.shouldStop == true)
    }

    // MARK: - nextFrame (single frame)

    @Test("Single frame always stops")
    func testNextFrameSingleFrame() {
        let result = CinePlaybackHelpers.nextFrame(current: 0, total: 1, mode: .loop, direction: .forward)
        #expect(result.frame == 0)
        #expect(result.shouldStop == true)
    }

    // MARK: - previousFrame

    @Test("Previous frame normal")
    func testPreviousFrame() {
        #expect(CinePlaybackHelpers.previousFrame(current: 5, total: 10) == 4)
    }

    @Test("Previous frame wraps at start")
    func testPreviousFrameWrap() {
        #expect(CinePlaybackHelpers.previousFrame(current: 0, total: 10) == 9)
    }

    @Test("Previous frame single frame")
    func testPreviousFrameSingle() {
        #expect(CinePlaybackHelpers.previousFrame(current: 0, total: 1) == 0)
    }

    // MARK: - nextFrameStep

    @Test("Next frame step normal")
    func testNextFrameStep() {
        #expect(CinePlaybackHelpers.nextFrameStep(current: 5, total: 10) == 6)
    }

    @Test("Next frame step wraps at end")
    func testNextFrameStepWrap() {
        #expect(CinePlaybackHelpers.nextFrameStep(current: 9, total: 10) == 0)
    }

    @Test("Next frame step single frame")
    func testNextFrameStepSingle() {
        #expect(CinePlaybackHelpers.nextFrameStep(current: 0, total: 1) == 0)
    }

    // MARK: - modeLabel

    @Test("Mode labels")
    func testModeLabels() {
        #expect(CinePlaybackHelpers.modeLabel(for: .loop) == "Loop")
        #expect(CinePlaybackHelpers.modeLabel(for: .bounce) == "Bounce")
        #expect(CinePlaybackHelpers.modeLabel(for: .once) == "Once")
    }

    // MARK: - modeSystemImage

    @Test("Mode system images")
    func testModeSystemImages() {
        #expect(CinePlaybackHelpers.modeSystemImage(for: .loop) == "repeat")
        #expect(CinePlaybackHelpers.modeSystemImage(for: .bounce) == "repeat.1")
        #expect(CinePlaybackHelpers.modeSystemImage(for: .once) == "arrow.right")
    }

    // MARK: - stateSystemImage

    @Test("State system images")
    func testStateSystemImages() {
        #expect(CinePlaybackHelpers.stateSystemImage(for: .stopped) == "stop.fill")
        #expect(CinePlaybackHelpers.stateSystemImage(for: .playing) == "pause.fill")
        #expect(CinePlaybackHelpers.stateSystemImage(for: .paused) == "play.fill")
    }
}
