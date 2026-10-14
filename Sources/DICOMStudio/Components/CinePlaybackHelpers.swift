// CinePlaybackHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent cine playback helpers

import Foundation

/// Playback state for multi-frame cine loop.
public enum PlaybackState: String, Sendable, Equatable, Hashable {
    case stopped
    case playing
    case paused
}

/// Playback looping mode.
public enum PlaybackMode: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Play forward continuously.
    case loop
    /// Play forward, then backward (ping-pong).
    case bounce
    /// Play once and stop.
    case once
}

/// Direction of playback for bounce mode.
public enum PlaybackDirection: Sendable, Equatable, Hashable {
    case forward
    case backward
}

/// Platform-independent helpers for cine playback calculations.
///
/// Provides frame stepping, FPS validation, and playback state transition logic.
public enum CinePlaybackHelpers: Sendable {

    /// Minimum allowed frame rate.
    public static let minFPS: Double = 1.0

    /// Maximum allowed frame rate.
    public static let maxFPS: Double = 60.0

    /// Default frame rate.
    ///
    /// Five frames a second is the rate the reader asked for: at the 15 fps
    /// this used to be, and the 24–30 fps that most files state for
    /// themselves, a cine loop ran too fast to follow frame by frame. The
    /// transport bar's slider still goes up to ``maxFPS`` for a reader who
    /// wants it faster.
    public static let defaultFPS: Double = 5.0

    /// Clamps a frame rate to the valid range [1, 60].
    ///
    /// - Parameter fps: Desired frame rate.
    /// - Returns: Clamped frame rate.
    public static func clampFPS(_ fps: Double) -> Double {
        max(minFPS, min(maxFPS, fps))
    }

    /// Calculates the timer interval for a given FPS.
    ///
    /// - Parameter fps: Frames per second.
    /// - Returns: Timer interval in seconds.
    public static func timerInterval(for fps: Double) -> Double {
        1.0 / clampFPS(fps)
    }

    /// Calculates the next frame index based on the playback mode.
    ///
    /// - Parameters:
    ///   - current: Current frame index (0-based).
    ///   - total: Total number of frames.
    ///   - mode: Playback mode.
    ///   - direction: Current playback direction (used for bounce mode).
    /// - Returns: Tuple of (nextFrame, nextDirection).
    public static func nextFrame(
        current: Int,
        total: Int,
        mode: PlaybackMode,
        direction: PlaybackDirection
    ) -> (frame: Int, direction: PlaybackDirection, shouldStop: Bool) {
        guard total > 1 else {
            return (0, .forward, true)
        }

        switch mode {
        case .loop:
            let next = (current + 1) % total
            return (next, .forward, false)

        case .bounce:
            switch direction {
            case .forward:
                if current >= total - 1 {
                    return (current - 1, .backward, false)
                }
                return (current + 1, .forward, false)
            case .backward:
                if current <= 0 {
                    return (current + 1, .forward, false)
                }
                return (current - 1, .backward, false)
            }

        case .once:
            let next = current + 1
            if next >= total {
                return (current, .forward, true)
            }
            return (next, .forward, false)
        }
    }

    /// Calculates the previous frame index (step backward).
    ///
    /// - Parameters:
    ///   - current: Current frame index (0-based).
    ///   - total: Total number of frames.
    /// - Returns: Previous frame index, wrapping to the last frame if at the beginning.
    public static func previousFrame(current: Int, total: Int) -> Int {
        guard total > 1 else { return 0 }
        return current > 0 ? current - 1 : total - 1
    }

    /// Calculates the next frame index (step forward).
    ///
    /// - Parameters:
    ///   - current: Current frame index (0-based).
    ///   - total: Total number of frames.
    /// - Returns: Next frame index, wrapping to 0 if at the end.
    public static func nextFrameStep(current: Int, total: Int) -> Int {
        guard total > 1 else { return 0 }
        return (current + 1) % total
    }

    /// Returns a display label for the playback mode.
    ///
    /// - Parameter mode: Playback mode.
    /// - Returns: Human-readable label.
    public static func modeLabel(for mode: PlaybackMode) -> String {
        switch mode {
        case .loop: return "Loop"
        case .bounce: return "Bounce"
        case .once: return "Once"
        }
    }

    /// Returns an SF Symbol name for the playback mode.
    ///
    /// - Parameter mode: Playback mode.
    /// - Returns: SF Symbol name.
    public static func modeSystemImage(for mode: PlaybackMode) -> String {
        switch mode {
        case .loop: return "repeat"
        case .bounce: return "repeat.1"
        case .once: return "arrow.right"
        }
    }

    /// Returns an SF Symbol name for the playback state.
    ///
    /// - Parameter state: Playback state.
    /// - Returns: SF Symbol name.
    public static func stateSystemImage(for state: PlaybackState) -> String {
        switch state {
        case .stopped: return "stop.fill"
        case .playing: return "pause.fill"
        case .paused: return "play.fill"
        }
    }
}
