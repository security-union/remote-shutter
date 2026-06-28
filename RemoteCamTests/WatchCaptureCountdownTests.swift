import XCTest
@testable import RemoteShutter

/// Tests the pure countdown logic that drives Watch-initiated timer captures.
///
/// The regression this guards: the original implementation scheduled its `Timer`
/// on the WCSession background delegate queue (no run loop), so the timer never
/// fired and timed captures silently did nothing. The scheduling now hops to the
/// main run loop, and the per-second transitions live in `WatchCaptureCountdown`
/// so they can be verified here without spinning a run loop.
final class WatchCaptureCountdownTests: XCTestCase {

    /// A 3-second countdown ticks 2, 1, then fires.
    func testThreeSecondCountdownTicksThenFires() {
        var countdown = WatchCaptureCountdown(seconds: 3)
        XCTAssertFalse(countdown.isFinished)
        XCTAssertEqual(countdown.advance(), .tick(2))
        XCTAssertEqual(countdown.advance(), .tick(1))
        XCTAssertEqual(countdown.advance(), .fire)
        XCTAssertTrue(countdown.isFinished)
    }

    /// The full sequence of steps for each supported timer option ends in exactly one `.fire`.
    func testEachTimerOptionFiresExactlyOnce() {
        for seconds in [2, 5, 10, 20] {
            var countdown = WatchCaptureCountdown(seconds: seconds)
            var steps: [WatchCaptureCountdown.Step] = []
            // Advance one extra time to prove it stays fired and never ticks again.
            for _ in 0..<(seconds + 1) {
                steps.append(countdown.advance())
            }
            let ticks = steps.filter { if case .tick = $0 { return true } else { return false } }
            let fires = steps.filter { $0 == .fire }
            XCTAssertEqual(ticks.count, seconds - 1, "Expected \(seconds - 1) ticks for a \(seconds)s timer")
            XCTAssertEqual(fires.count, 2, "Expected fire on completion and to stay fired afterwards")
            // Ticks count down contiguously from seconds-1 to 1.
            XCTAssertEqual(ticks, (1...(seconds - 1)).reversed().map { .tick($0) })
        }
    }

    /// A zero-second timer fires immediately with no ticks.
    func testZeroSecondsFiresImmediately() {
        var countdown = WatchCaptureCountdown(seconds: 0)
        XCTAssertTrue(countdown.isFinished)
        XCTAssertEqual(countdown.advance(), .fire)
    }

    /// Negative input is clamped to zero rather than counting down forever.
    func testNegativeSecondsClampedToZero() {
        var countdown = WatchCaptureCountdown(seconds: -5)
        XCTAssertEqual(countdown.remaining, 0)
        XCTAssertEqual(countdown.advance(), .fire)
    }

    /// Advancing past completion keeps returning `.fire` and never underflows.
    func testAdvancePastCompletionStaysFired() {
        var countdown = WatchCaptureCountdown(seconds: 1)
        XCTAssertEqual(countdown.advance(), .fire)
        XCTAssertEqual(countdown.advance(), .fire)
        XCTAssertEqual(countdown.advance(), .fire)
        XCTAssertEqual(countdown.remaining, 0)
    }
}
