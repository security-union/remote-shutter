//
//  MonitorChrome.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import CoreGraphics
import Foundation
import UIKit

// MARK: - Chrome dock

/// Which edge the action cluster (gallery · shutter · camera switch) sits on.
enum MonitorChromeDock: Equatable {
    case bottom
    case leading
    case trailing
}

/// How the screen is driven. The rail exists so a rotating device doesn't move
/// the shutter out from under a thumb; a pointer-driven window neither rotates
/// nor has a thumb, so it keeps the conventional bottom bar.
enum MonitorChromeInput: Equatable {
    case touch
    case pointer
}

/// Layout policy. Shape decides whether to dock on a rail — a size-class rule
/// would bottom-dock iPhone landscape, which is compact width. Orientation
/// decides which rail: the cluster stays on the home-indicator edge so the
/// shutter doesn't move under the user's hand when the device turns.
enum MonitorChromeLayout {

    static func dock(viewSize: CGSize,
                     interfaceOrientation: UIInterfaceOrientation,
                     input: MonitorChromeInput = .touch) -> MonitorChromeDock {
        guard input == .touch else { return .bottom }
        guard viewSize.width > viewSize.height else { return .bottom }
        // Interface orientation is the inverse of device orientation.
        return interfaceOrientation == .landscapeLeft ? .leading : .trailing
    }
}

// MARK: - Self-timer

/// The self-timer's detented values.
enum MonitorTimer {

    /// Ascending, starting at "off".
    static let stops: [Int] = [0, 3, 5, 10, 20]

    /// The next stop strictly above `value`, wrapping to off at the end.
    /// Non-stop values round *up*, so a delay persisted as any integer 0...20
    /// under `timerDefault` lands on a real stop rather than being stranded.
    static func next(after value: Int) -> Int {
        stops.first { $0 > value } ?? stops[0]
    }
}

// MARK: - Tray

/// One tile in the capture tray. Each tile's glyph carries its own current
/// value (timer shows "5", aspect "16:9"), which is what lets it live behind a
/// tap rather than occupy a permanent row.
enum MonitorTrayItem: Equatable {
    case timer
    case aspect
    case resolution
    case frameRate
    case format
    case hdr
    /// Puts the peer camera's *local* preview to sleep. It keeps capturing and
    /// keeps streaming here.
    case cameraStandby
    case settings
    case help
}

enum MonitorTray {

    /// Capability-driven tiles are omitted, not disabled: a camera that cannot
    /// do HDR shows no HDR tile. Tiles that merely aren't available right now
    /// (quality mid-recording) stay and are dimmed by the view.
    static func items(for state: MonitorUIState,
                      supportsHEIF: Bool,
                      supportsHDR: Bool,
                      supportsCameraStandby: Bool,
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

        if supportsCameraStandby { items.append(.cameraStandby) }

        items.append(.settings)
        items.append(.help)
        return items
    }
}

// MARK: - Link health

/// What the monitor can say about the picture it is showing. The stream can go
/// quiet while the session still believes it is connected, so a frozen preview
/// needs saying out loud.
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
/// Derived from session state at the single `transition(to:)` choke point
/// rather than pushed from each command site: an indicator that is a function
/// of the state cannot outlive the thing it describes, and needs no
/// show/dismiss pairing to get wrong.
enum MonitorActivity: Equatable {
    /// Shutter pressed; the camera has not acknowledged yet.
    case capturing
    /// The shot is taken and on its way — the moment the subject can stop
    /// holding the pose.
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
        case .monitorStartingVideo: return .capturing
        case .monitorTogglingCamera: return .switchingCamera
        case .monitorTogglingFlash: return .togglingFlash
        case .monitorSwitchingLens: return .switchingLens
        default: return nil
        }
    }
}
