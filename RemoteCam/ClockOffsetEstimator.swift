//
//  ClockOffsetEstimator.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2026.
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation

/// The millisecond clock both ends of a clock-sync exchange read. Monotonic
/// while the app runs (never jumps with NTP/wall-clock changes), but it
/// pauses in deep sleep and restarts per boot — which is why offsets are
/// re-estimated on every foreground and never persisted.
enum SyncClock {
    static func nowMillis() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }
}

/// One ping/pong exchange reduced to an offset estimate.
struct ClockOffsetSample: Equatable {
    /// camera clock − director clock, in ms. Adding this to a director
    /// timestamp yields the same instant on the camera's clock.
    let offsetMillis: Int64
    /// Round trip of the exchange; smaller = tighter estimate (the error
    /// bound is the RTT asymmetry, at most rtt/2).
    let roundTripMillis: Int64
}

/// NTP-style offset estimation over the session link: keep a short window of
/// exchanges and trust the minimum-RTT one — a queued or retransmitted
/// exchange has a large RTT and an unreliable midpoint, so it should never
/// outvote a clean one.
///
/// Pure value type: callers supply every timestamp, so tests need no clocks.
struct ClockOffsetEstimator {
    static let windowSize = 5

    private(set) var samples: [ClockOffsetSample] = []

    /// Record one exchange: director sent at `t0Millis`, camera stamped
    /// `cameraClockMillis` at receipt, director received the pong at
    /// `t3Millis` (all in each side's own `SyncClock`). Returns the sample,
    /// or nil for a nonsensical exchange (pong before ping — a stale reply
    /// from before a clock reset).
    @discardableResult
    mutating func recordExchange(t0Millis: UInt64,
                                 cameraClockMillis: UInt64,
                                 t3Millis: UInt64) -> ClockOffsetSample? {
        guard t3Millis >= t0Millis else { return nil }
        let rtt = Int64(t3Millis - t0Millis)
        let directorMidpoint = Int64(bitPattern: t0Millis) + rtt / 2
        let sample = ClockOffsetSample(
            offsetMillis: Int64(bitPattern: cameraClockMillis) - directorMidpoint,
            roundTripMillis: rtt)
        samples.append(sample)
        if samples.count > Self.windowSize {
            samples.removeFirst(samples.count - Self.windowSize)
        }
        return sample
    }

    /// The trusted estimate: the minimum-RTT sample in the window.
    var best: ClockOffsetSample? {
        samples.min { $0.roundTripMillis < $1.roundTripMillis }
    }

    /// Drop everything — called when the clocks may have moved under us
    /// (either side backgrounded, or the peer reconnected).
    mutating func reset() {
        samples.removeAll()
    }
}
