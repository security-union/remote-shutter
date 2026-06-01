import XCTest
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
            .switchlens, .toggleflash, .toggletorch, .togglecamera, .requeststate
        ]
        for action in actions {
            let decoded = try XCTUnwrap(WatchCommandEncoder.decode(WatchCommandEncoder.encode(action: action)))
            XCTAssertEqual(decoded.action, action)
        }
    }

    // MARK: - State (iPhone -> Watch)

    func testStateRoundTripPreservesAllFields() throws {
        let data = WatchStateEncoder.encode(
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
        )
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
        let data = WatchStateEncoder.encode(
            isReady: true,
            currentZoomFactor: 1.0,
            minZoomFactor: 1.0,
            maxZoomFactor: 10.0,
            isRecording: false,
            currentMode: .photo,
            currentLensType: .wideangle,
            availableLensTypes: [.wideangle],
            isFlashEnabled: false,
            isTorchEnabled: false,
            zoomStops: [1.0],
            wideAngleZoomFactor: 1.0,
            lastEvent: nil
        )
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
        let stateData = WatchStateEncoder.encode(
            isReady: true, currentZoomFactor: 1, minZoomFactor: 1, maxZoomFactor: 10,
            isRecording: false, currentMode: .photo, currentLensType: .wideangle,
            availableLensTypes: [.wideangle], isFlashEnabled: false, isTorchEnabled: false,
            zoomStops: [1.0], wideAngleZoomFactor: 1.0, lastEvent: nil
        )
        XCTAssertNil(WatchCommandEncoder.decode(stateData))
    }
}
