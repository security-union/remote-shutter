import XCTest
import FlatBuffers
@testable import RemoteShutter

/// Round-trip tests for the FlatBuffer framing used over WCSession between the
/// iPhone and the Apple Watch. These lock down the wire format so a schema change
/// that silently breaks decoding (and would otherwise just make the Watch go blank)
/// fails loudly in CI instead.
final class WatchSerializationTests: XCTestCase {

    // MARK: - Command (Watch -> iPhone)

    func testCommandRoundTripPreservesAllFields() throws {
        let data = WatchCommandEncoder.encode(
            action: .setzoom,
            zoomFactor: 2.5,
            lensType: .telephoto,
            timerSeconds: 10
        )
        let decoded = try XCTUnwrap(WatchCommandEncoder.decode(data), "command should decode")
        XCTAssertEqual(decoded.action, .setzoom)
        XCTAssertEqual(decoded.zoomFactor, 2.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.lensType, .telephoto)
        XCTAssertEqual(decoded.timerSeconds, 10)
    }

    func testCommandRoundTripWithDefaults() throws {
        let data = WatchCommandEncoder.encode(action: .requeststate)
        let decoded = try XCTUnwrap(WatchCommandEncoder.decode(data))
        XCTAssertEqual(decoded.action, .requeststate)
        XCTAssertEqual(decoded.zoomFactor, 0, accuracy: 0.0001)
        XCTAssertEqual(decoded.lensType, .wideangle)
        XCTAssertEqual(decoded.timerSeconds, 0)
    }

    /// Every command action survives the round trip (guards the enum mapping).
    func testAllCommandActionsRoundTrip() throws {
        let actions: [RemoteShutter_WatchCommandAction] = [
            .setzoom, .takepicture, .startrecording, .stoprecording,
            .switchlens, .toggleflash, .toggletorch, .togglecamera, .requeststate,
            .setmode
        ]
        for action in actions {
            let decoded = try XCTUnwrap(WatchCommandEncoder.decode(WatchCommandEncoder.encode(action: action)))
            XCTAssertEqual(decoded.action, action)
        }
    }

    func testSetModeCommandRoundTripPreservesMode() throws {
        let data = WatchCommandEncoder.encode(action: .setmode, mode: .video)
        let decoded = try XCTUnwrap(WatchCommandEncoder.decode(data))
        XCTAssertEqual(decoded.action, .setmode)
        XCTAssertEqual(decoded.mode, .video)

        // Commands that don't carry a mode decode with the Unknown default.
        let plain = try XCTUnwrap(WatchCommandEncoder.decode(WatchCommandEncoder.encode(action: .takepicture)))
        XCTAssertEqual(plain.mode, .unknown)
    }

    // MARK: - State (iPhone -> Watch)

    func testStateRoundTripPreservesAllFields() throws {
        let data = WatchStateEncoder.encode(WatchCameraStateSnapshot(
            isReady: true,
            currentZoomFactor: 3.0,
            minZoomFactor: 1.0,
            maxZoomFactor: 12.0,
            isRecording: true,
            currentMode: .video,
            currentLensType: .ultrawide,
            availableLensTypes: [.ultrawide, .wideangle, .telephoto],
            isFlashEnabled: false,
            isTorchEnabled: true,
            zoomStops: [0.5, 1.0, 2.0],
            wideAngleZoomFactor: 2.0,
            lastEvent: "photoTaken"
        ))
        let decoded = try XCTUnwrap(WatchStateEncoder.decode(data), "state should decode")
        XCTAssertTrue(decoded.isReady)
        XCTAssertEqual(decoded.currentZoomFactor, 3.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.minZoomFactor, 1.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.maxZoomFactor, 12.0, accuracy: 0.0001)
        XCTAssertTrue(decoded.isRecording)
        XCTAssertEqual(decoded.currentMode, .video)
        XCTAssertEqual(decoded.currentLensType, .ultrawide)
        XCTAssertEqual(decoded.availableLensTypes, [.ultrawide, .wideangle, .telephoto])
        XCTAssertFalse(decoded.isFlashEnabled)
        XCTAssertTrue(decoded.isTorchEnabled)
        XCTAssertEqual(decoded.zoomStops, [0.5, 1.0, 2.0])
        XCTAssertEqual(decoded.wideAngleZoomFactor, 2.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.lastEvent, "photoTaken")
    }

    /// A nil `lastEvent` decodes back as nil (or empty) — i.e. no spurious event is fired.
    func testStateRoundTripWithNilEvent() throws {
        let data = WatchStateEncoder.encode(WatchCameraStateSnapshot(lastEvent: nil))
        let decoded = try XCTUnwrap(WatchStateEncoder.decode(data))
        XCTAssertTrue(decoded.lastEvent == nil || decoded.lastEvent?.isEmpty == true,
                      "Expected no event, got \(String(describing: decoded.lastEvent))")
    }

    // MARK: - Negative cases (the "ignore undecodable" guard)

    /// Decoding a command buffer as state returns nil rather than fabricating a frame/state.
    func testStateDecodeRejectsCommandBuffer() {
        let commandData = WatchCommandEncoder.encode(action: .takepicture)
        XCTAssertNil(WatchStateEncoder.decode(commandData))
    }

    /// Decoding a state buffer as a command returns nil.
    func testCommandDecodeRejectsStateBuffer() {
        let stateData = WatchStateEncoder.encode(WatchCameraStateSnapshot())
        XCTAssertNil(WatchCommandEncoder.decode(stateData))
    }

    // MARK: - New appended state fields

    func testStateRoundTripPreservesEpochAndFlashMode() throws {
        var snapshot = WatchCameraStateSnapshot()
        snapshot.stateEpochMs = 1_765_000_000_123
        snapshot.flashMode = .auto
        let decoded = try XCTUnwrap(WatchStateEncoder.decode(WatchStateEncoder.encode(snapshot)))
        XCTAssertEqual(decoded.stateEpochMs, 1_765_000_000_123)
        XCTAssertEqual(decoded.flashMode, .auto)
    }

    /// Bytes from a build that predates the appended fields still decode, with
    /// the new fields falling back to their FlatBuffer defaults.
    func testLegacyStateWithoutAppendedFieldsDecodes() throws {
        var fbb = FlatBufferBuilder()
        let start = RemoteShutter_WatchCameraState.startWatchCameraState(&fbb)
        RemoteShutter_WatchCameraState.add(isReady: true, &fbb)
        RemoteShutter_WatchCameraState.add(currentZoomFactor: 2.0, &fbb)
        let state = RemoteShutter_WatchCameraState.endWatchCameraState(&fbb, start: start)
        let msg = RemoteShutter_WatchMessage.createWatchMessage(&fbb, type: .watchstatemsg, stateOffset: state)
        fbb.finish(offset: msg)

        let decoded = try XCTUnwrap(WatchStateEncoder.decode(fbb.data))
        XCTAssertTrue(decoded.isReady)
        XCTAssertEqual(decoded.currentZoomFactor, 2.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.stateEpochMs, 0)
        XCTAssertEqual(decoded.flashMode, .off)
    }

    // MARK: - Command Acks

    func testAckRoundTripAllStatuses() throws {
        let statuses: [RemoteShutter_WatchAckStatus] = [.ok, .notinwatchmode, .busy, .failed]
        for status in statuses {
            let data = WatchAckEncoder.encode(status: status, action: .takepicture, detail: "d")
            let decoded = try XCTUnwrap(WatchAckEncoder.decode(data), "\(status) should decode")
            XCTAssertEqual(decoded.status, status)
            XCTAssertEqual(decoded.action, .takepicture)
            XCTAssertEqual(decoded.detail, "d")
        }
    }

    func testAckDecodeRejectsOtherMessageTypes() {
        XCTAssertNil(WatchAckEncoder.decode(WatchCommandEncoder.encode(action: .takepicture)))
        XCTAssertNil(WatchAckEncoder.decode(WatchStateEncoder.encode(WatchCameraStateSnapshot())))
        XCTAssertNil(WatchStateEncoder.decode(WatchAckEncoder.encode(status: .ok)))
    }

    // MARK: - Connection Phase Derivation

    func testPhaseDerivation() {
        // Session not activated → inactive regardless of anything else.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: false, isPhoneReachable: true, isReady: true,
            phoneNotInWatchMode: false, phoneNotReadyReason: nil), .inactive)

        // Activated but unreachable → connecting.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: false, isReady: false,
            phoneNotInWatchMode: true, phoneNotReadyReason: nil), .connecting)

        // Ready wins.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, isReady: true,
            phoneNotInWatchMode: false, phoneNotReadyReason: nil), .ready)

        // Reachable, not ready, phone said NotInWatchMode → instruction screen.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, isReady: false,
            phoneNotInWatchMode: true, phoneNotReadyReason: nil), .phoneNotInWatchMode)

        // Phone backgrounded beats NotInWatchMode messaging.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, isReady: false,
            phoneNotInWatchMode: false, phoneNotReadyReason: "phoneBackgrounded"), .phoneNotReady)

        // Reachable, no signal yet → still connecting (syncing).
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, isReady: false,
            phoneNotInWatchMode: false, phoneNotReadyReason: nil), .connecting)
    }
}

// MARK: - Zoom Throttle

final class ZoomSendThrottleTests: XCTestCase {

    func testLeadingValueSendsImmediately() {
        var throttle = ZoomSendThrottle(interval: 0.05)
        XCTAssertEqual(throttle.update(value: 2.0, now: Date(timeIntervalSince1970: 100)), .sendNow)
    }

    func testBurstCoalescesAndTrailingCarriesFinalValue() {
        var throttle = ZoomSendThrottle(interval: 0.05)
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(throttle.update(value: 1.0, now: t0), .sendNow)
        // Burst within the interval: each updates the pending value.
        XCTAssertEqual(throttle.update(value: 2.0, now: t0.addingTimeInterval(0.01)), .scheduleTrailing)
        XCTAssertEqual(throttle.update(value: 3.0, now: t0.addingTimeInterval(0.02)), .scheduleTrailing)
        XCTAssertEqual(throttle.update(value: 4.0, now: t0.addingTimeInterval(0.03)), .scheduleTrailing)

        // The trailing flush delivers exactly the final value...
        XCTAssertEqual(throttle.fireTrailing(now: t0.addingTimeInterval(0.08)), 4.0)
        // ...and only once.
        XCTAssertNil(throttle.fireTrailing(now: t0.addingTimeInterval(0.09)))
    }

    func testValueAfterIntervalSendsImmediatelyAndClearsPending() {
        var throttle = ZoomSendThrottle(interval: 0.05)
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(throttle.update(value: 1.0, now: t0), .sendNow)
        XCTAssertEqual(throttle.update(value: 2.0, now: t0.addingTimeInterval(0.01)), .scheduleTrailing)
        // Past the interval: send now, and the stale pending value is dropped.
        XCTAssertEqual(throttle.update(value: 5.0, now: t0.addingTimeInterval(0.06)), .sendNow)
        XCTAssertNil(throttle.fireTrailing(now: t0.addingTimeInterval(0.12)),
                     "pending value superseded by a direct send must not flush")
    }

    func testFireTrailingWithNothingPendingReturnsNil() {
        var throttle = ZoomSendThrottle(interval: 0.05)
        XCTAssertNil(throttle.fireTrailing(now: Date()))
    }
}
