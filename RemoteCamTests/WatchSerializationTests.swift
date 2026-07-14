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
            .setmode, .canceltimer, .requestpreviewframe
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
            readiness: .ready,
            event: .phototaken,
            countdownRemainingSecs: 4,
            currentZoomFactor: 3.0,
            minZoomFactor: 1.0,
            maxZoomFactor: 12.0,
            isRecording: true,
            currentMode: .video,
            currentLensType: .ultrawide,
            availableLensTypes: [.ultrawide, .wideangle, .telephoto],
            flashMode: .auto,
            isTorchEnabled: true,
            zoomStops: [0.5, 1.0, 2.0],
            wideAngleZoomFactor: 2.0
        ))
        let decoded = try XCTUnwrap(WatchStateEncoder.decode(data), "state should decode")
        XCTAssertEqual(decoded.readiness, .ready)
        XCTAssertEqual(decoded.event, .phototaken)
        XCTAssertEqual(decoded.countdownRemainingSecs, 4)
        XCTAssertEqual(decoded.currentZoomFactor, 3.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.minZoomFactor, 1.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.maxZoomFactor, 12.0, accuracy: 0.0001)
        XCTAssertTrue(decoded.isRecording)
        XCTAssertEqual(decoded.currentMode, .video)
        XCTAssertEqual(decoded.currentLensType, .ultrawide)
        XCTAssertEqual(decoded.availableLensTypes, [.ultrawide, .wideangle, .telephoto])
        XCTAssertEqual(decoded.flashMode, .auto)
        XCTAssertTrue(decoded.isFlashEnabled, "auto flash surfaces as enabled")
        XCTAssertTrue(decoded.isTorchEnabled)
        XCTAssertEqual(decoded.zoomStops, [0.5, 1.0, 2.0])
        XCTAssertEqual(decoded.wideAngleZoomFactor, 2.0, accuracy: 0.0001)
    }

    /// An event-free state decodes back as `.unknown` — no spurious event is fired.
    func testStateRoundTripWithNoEvent() throws {
        let data = WatchStateEncoder.encode(WatchCameraStateSnapshot(event: .unknown))
        let decoded = try XCTUnwrap(WatchStateEncoder.decode(data))
        XCTAssertEqual(decoded.event, .unknown)
    }

    func testAllEventTypesRoundTrip() throws {
        let events: [RemoteShutter_WatchEventType] = [
            .phototaken, .photoerror, .recordingstarted, .recordingstopped,
            .recordingfailed, .microphonedenied, .busy, .busyrecording, .sendfailed
        ]
        for event in events {
            let data = WatchStateEncoder.encode(WatchCameraStateSnapshot(event: event))
            let decoded = try XCTUnwrap(WatchStateEncoder.decode(data), "\(event) should decode")
            XCTAssertEqual(decoded.event, event)
        }
    }

    func testAllReadinessValuesRoundTrip() throws {
        let values: [RemoteShutter_WatchReadiness] = [.unknown, .ready, .phonebackgrounded, .notinwatchmode]
        for readiness in values {
            let data = WatchStateEncoder.encode(WatchCameraStateSnapshot(readiness: readiness))
            let decoded = try XCTUnwrap(WatchStateEncoder.decode(data), "\(readiness) should decode")
            XCTAssertEqual(decoded.readiness, readiness)
        }
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

    // MARK: - Field defaults

    func testStateRoundTripPreservesEpochAndFlashMode() throws {
        var snapshot = WatchCameraStateSnapshot()
        snapshot.stateEpochMs = 1_765_000_000_123
        snapshot.flashMode = .auto
        let decoded = try XCTUnwrap(WatchStateEncoder.decode(WatchStateEncoder.encode(snapshot)))
        XCTAssertEqual(decoded.stateEpochMs, 1_765_000_000_123)
        XCTAssertEqual(decoded.flashMode, .auto)
    }

    /// A state built entirely from FlatBuffer defaults decodes to the safe
    /// zero-values: unknown readiness (never treated as ready), no event, no
    /// countdown.
    func testDefaultStateDecodesToSafeValues() throws {
        var fbb = FlatBufferBuilder()
        let start = RemoteShutter_WatchCameraState.startWatchCameraState(&fbb)
        RemoteShutter_WatchCameraState.add(currentZoomFactor: 2.0, &fbb)
        let state = RemoteShutter_WatchCameraState.endWatchCameraState(&fbb, start: start)
        let msg = RemoteShutter_WatchMessage.createWatchMessage(&fbb, type: .watchstatemsg, stateOffset: state)
        fbb.finish(offset: msg)

        let decoded = try XCTUnwrap(WatchStateEncoder.decode(fbb.data))
        XCTAssertEqual(decoded.readiness, .unknown)
        XCTAssertFalse(decoded.isReady, "unknown readiness must never present as ready")
        XCTAssertEqual(decoded.event, .unknown)
        XCTAssertEqual(decoded.countdownRemainingSecs, 0)
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

    // MARK: - Live Preview Frame (iPhone -> Watch)

    func testPreviewFrameRoundTripPreservesPayloadCodecAndEpoch() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let data = WatchPreviewFrameEncoder.encode(payload: jpeg, codec: .heic, epochMs: 1_765_000_000_999)
        let decoded = try XCTUnwrap(WatchPreviewFrameEncoder.decode(data), "preview frame should decode")
        XCTAssertEqual(decoded.payload, jpeg)
        XCTAssertEqual(decoded.codec, .heic)
        XCTAssertEqual(decoded.epochMs, 1_765_000_000_999)
    }

    func testPreviewFrameRoundTripVP9Codec() throws {
        let decoded = try XCTUnwrap(WatchPreviewFrameEncoder.decode(
            WatchPreviewFrameEncoder.encode(payload: Data([0x9D]), codec: .vp9, epochMs: 7)))
        XCTAssertEqual(decoded.codec, .vp9)
    }

    /// A frame built without the codec field (legacy sender) must decode as
    /// `.unknown`, which the Watch treats as a sniffable still image.
    func testPreviewFrameWithoutCodecDecodesAsUnknown() throws {
        var fbb = FlatBufferBuilder()
        let payloadVec = fbb.createVector(bytes: Data([0x01, 0x02]))
        let frame = RemoteShutter_WatchPreviewFrame.createWatchPreviewFrame(
            &fbb, jpegVectorOffset: payloadVec, epochMs: 5)
        let msg = RemoteShutter_WatchMessage.createWatchMessage(
            &fbb, type: .watchpreviewframemsg, previewFrameOffset: frame)
        fbb.finish(offset: msg)

        let decoded = try XCTUnwrap(WatchPreviewFrameEncoder.decode(fbb.data))
        XCTAssertEqual(decoded.codec, .unknown)
        XCTAssertEqual(decoded.payload, Data([0x01, 0x02]))
    }

    func testPreviewFrameRoundTripEmptyPayload() throws {
        let decoded = try XCTUnwrap(WatchPreviewFrameEncoder.decode(
            WatchPreviewFrameEncoder.encode(payload: Data(), codec: .jpeg, epochMs: 0)))
        XCTAssertTrue(decoded.payload.isEmpty)
        XCTAssertEqual(decoded.epochMs, 0)
    }

    /// A preview frame must not decode as state/ack/command, and vice-versa — the
    /// Watch routes a single live channel purely by message type.
    func testPreviewFrameCrossTypeDecodingIsRejected() {
        let preview = WatchPreviewFrameEncoder.encode(payload: Data([0x01, 0x02]), codec: .jpeg, epochMs: 1)
        XCTAssertNil(WatchStateEncoder.decode(preview))
        XCTAssertNil(WatchCommandEncoder.decode(preview))
        XCTAssertNil(WatchAckEncoder.decode(preview))

        XCTAssertNil(WatchPreviewFrameEncoder.decode(WatchStateEncoder.encode(WatchCameraStateSnapshot())))
        XCTAssertNil(WatchPreviewFrameEncoder.decode(WatchCommandEncoder.encode(action: .takepicture)))
        XCTAssertNil(WatchPreviewFrameEncoder.decode(WatchAckEncoder.encode(status: .ok)))
    }

    // MARK: - Connection Phase Derivation

    func testPhaseDerivation() {
        // Session not activated → inactive regardless of anything else.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: false, isPhoneReachable: true, readiness: .ready), .inactive)

        // Activated but unreachable → connecting, whatever the last verdict was.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: false, readiness: .notinwatchmode), .connecting)

        // Ready → controls.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, readiness: .ready), .ready)

        // Phone left the Watch Remote screen → instruction screen.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, readiness: .notinwatchmode), .phoneNotInWatchMode)

        // Phone backgrounded/locked → "app closed" screen.
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, readiness: .phonebackgrounded), .phoneNotReady)

        // Reachable, no signal yet → still connecting (syncing).
        XCTAssertEqual(WatchConnectionPhase.derive(
            isSessionActive: true, isPhoneReachable: true, readiness: .unknown), .connecting)
    }

    // MARK: - Active Countdown Derivation

    private func snapshot(readiness: RemoteShutter_WatchReadiness = .ready,
                          countdown: Int32 = 0) -> WatchCameraStateSnapshot {
        var snapshot = WatchCameraStateSnapshot()
        snapshot.readiness = readiness
        snapshot.countdownRemainingSecs = countdown
        return snapshot
    }

    func testActiveCountdownReadsPositiveSeconds() {
        XCTAssertEqual(snapshot(countdown: 3).activeCountdownSeconds, 3)
        XCTAssertEqual(snapshot(countdown: 1).activeCountdownSeconds, 1)
    }

    /// The stuck-overlay regression: a snapshot is authoritative — zero (or
    /// negative) countdown means "no countdown running".
    func testSnapshotWithoutCountdownCarriesNoCountdown() {
        XCTAssertNil(snapshot(countdown: 0).activeCountdownSeconds)
        XCTAssertNil(snapshot(countdown: -2).activeCountdownSeconds)
    }

    func testCountdownOnlyCountsWhilePhoneCanCapture() {
        XCTAssertNil(snapshot(readiness: .phonebackgrounded, countdown: 2).activeCountdownSeconds)
        XCTAssertNil(snapshot(readiness: .notinwatchmode, countdown: 2).activeCountdownSeconds)
        XCTAssertNil(snapshot(readiness: .unknown, countdown: 2).activeCountdownSeconds)
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
