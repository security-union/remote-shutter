//
//  MonitorChrome.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import CoreGraphics
import Foundation

// MARK: - Chrome dock

/// Where the monitor's action cluster (gallery · shutter · camera switch) sits.
enum MonitorChromeDock: Equatable {
    /// Across the bottom — the screen is taller than it is wide.
    case bottom
    /// Down the trailing edge — the screen is wider than it is tall, so the
    /// bottom is the scarce axis and the side rails are the free space.
    case trailing
}

/// The monitor screen's pure layout policy. Deliberately a function of the
/// view's own shape rather than of size class or platform: an iPhone in
/// landscape is *compact* width on every non-Max phone, so a size-class rule
/// would bottom-dock the exact case this screen exists to serve. Shape covers
/// iPhone rotation, iPad Split View, and a resized Mac window with one rule and
/// no `#if`.
enum MonitorChromeLayout {

    static func dock(viewSize: CGSize) -> MonitorChromeDock {
        viewSize.width > viewSize.height ? .trailing : .bottom
    }
}

// MARK: - Self-timer

/// The self-timer's detented values. Replaces the 0...20 continuous slider: a
/// remote's timer is picked from a handful of useful delays, and a tap-to-cycle
/// glyph costs a fraction of the screen a labelled slider did.
enum MonitorTimer {

    /// Ascending, starting at "off". Mirrors the delays a camera app offers.
    static let stops: [Int] = [0, 3, 5, 10, 20]

    /// The next stop strictly above `value`, wrapping to off at the end.
    ///
    /// Values that are not themselves stops are rounded *up* to the next one,
    /// so a delay restored from an older build's slider (which stored any
    /// integer 0...20 under `timerDefault`) lands on a real stop instead of
    /// being stranded.
    static func next(after value: Int) -> Int {
        stops.first { $0 > value } ?? stops[0]
    }
}

// MARK: - Tray

/// One tile in the capture tray — the controls that leave the viewfinder.
///
/// Each tile's glyph carries its own current value (the timer shows "5", aspect
/// shows "16:9"), which is what lets them live behind a tap instead of
/// occupying a permanent row.
enum MonitorTrayItem: Equatable {
    case timer
    case aspect
    case resolution
    case frameRate
    case format
    case hdr
    case settings
    case help
}

enum MonitorTray {

    /// The tiles for a given mode and set of peer capabilities.
    ///
    /// Capability-driven tiles are omitted rather than disabled: a camera that
    /// cannot do HDR should not show an HDR tile at all. Tiles that exist but
    /// are momentarily unavailable (quality during a recording) stay in the
    /// list and are dimmed by the view — that is enablement, not composition.
    static func items(for state: MonitorUIState,
                      supportsHEIF: Bool,
                      supportsHDR: Bool,
                      resolutionCount: Int,
                      frameRateCount: Int) -> [MonitorTrayItem] {
        var items: [MonitorTrayItem] = []

        // Shorts runs to a fixed duration, so a self-timer has nothing to delay.
        if state != .shortsMode {
            items.append(.timer)
        }
        items.append(.aspect)

        switch state {
        case .videoMode, .videoRecording:
            if resolutionCount > 1 { items.append(.resolution) }
            if frameRateCount > 1 { items.append(.frameRate) }
        case .photoMode:
            if supportsHEIF { items.append(.format) }
            if supportsHDR { items.append(.hdr) }
        case .shortsMode:
            break
        }

        items.append(.settings)
        items.append(.help)
        return items
    }
}

// MARK: - Link health

/// What the monitor can say about the picture it is showing.
///
/// Apple's Camera has no equivalent — its sensor is in your hand, so a frozen
/// preview is impossible. Here the stream can go quiet while the session still
/// believes it is connected, and the old behaviour was silence: the image
/// simply stopped updating with nothing on screen to say so.
enum MonitorLinkState: Equatable {
    /// Frames are arriving. Rendered as a single quiet dot.
    case live
    /// The session is up but frames have stopped — the picture on screen is
    /// stale and must not be trusted for framing.
    case stalled
    /// The peer link itself is being rebuilt.
    case reconnecting

    /// Reconnecting outranks a stall: when the link is down the stall is a
    /// symptom, and naming the cause is more useful than naming the effect.
    static func resolve(link: PeerLinkStatus.Link, isPreviewStale: Bool) -> MonitorLinkState {
        switch link {
        case .reconnecting: return .reconnecting
        case .linked: return isPreviewStale ? .stalled : .live
        }
    }
}

// MARK: - In-flight remote commands

/// What the monitor is waiting on the camera for, right now.
///
/// Derived from the session state at the single `transition(to:)` choke point
/// rather than pushed from each command site, for the reason `PeerLinkStatus`
/// documents about the reconnect overlay: when the indicator is a function of
/// the state, it cannot outlive the thing it describes. The show/dismiss pairs
/// that a pushed indicator needs are exactly what used to leave a modal spinner
/// over the preview.
enum MonitorActivity: Equatable {
    /// Shutter pressed; the camera has not acknowledged yet.
    case capturing
    /// The camera took the shot and the picture is on its way. A distinct state
    /// because it is the moment the subject can stop holding the pose.
    case receivingCapture
    case switchingCamera
    case togglingFlash
    case switchingLens

    /// The activity a state implies, or `nil` when nothing is in flight.
    static func forState(_ state: SessionState) -> MonitorActivity? {
        switch state {
        case .monitorTakingPicture(_, let phase):
            switch phase {
            case .requesting: return .capturing
            case .receiving: return .receivingCapture
            }
        case .monitorTogglingCamera: return .switchingCamera
        case .monitorTogglingFlash: return .togglingFlash
        case .monitorSwitchingLens: return .switchingLens
        default: return nil
        }
    }
}
