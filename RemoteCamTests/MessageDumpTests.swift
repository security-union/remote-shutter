import XCTest
@testable import RemoteShutter

/// The debug console's tap-to-inspect view of a message. Reflection-based, so
/// the assertions pin what a reader needs to see for the commands that
/// matter most (capabilities, pro-control intents), not an exact layout.
final class MessageDumpTests: XCTestCase {

    func testControlStateChangedShowsNestedSnapshotFields() {
        // The v11 truth channel: one snapshot with the exposure nested inside.
        let control = ControlState(
            seq: 7, currentLens: .wideAngle, zoomFactor: 1.0,
            exposure: ExposureState(mode: .manual, durationSeconds: 1.0 / 125, iso: 400,
                                    minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 1,
                                    minISO: 32, maxISO: 3200))
        let dump = MessageDump.describe(RemoteCmd.ControlStateChanged(state: control))

        XCTAssertTrue(dump.contains("state:"), dump)
        XCTAssertTrue(dump.contains("seq: 7"), dump)
        XCTAssertTrue(dump.contains("mode: manual"), "the nested exposure opens its own block\n\(dump)")
        XCTAssertTrue(dump.contains("iso: 400.0"), dump)
        XCTAssertTrue(dump.contains("(1/125)"), "shutter reads as a fraction\n\(dump)")
        XCTAssertTrue(dump.contains("cinematic: nil"), dump)
        XCTAssertFalse(dump.contains("sender"), "plumbing is not a field\n\(dump)")
    }

    func testIntentEnumsCarryTheirValues() {
        XCTAssertEqual(MessageDump.describe(RemoteCmd.SetExposure(intent: .manual(durationSeconds: 0.5, iso: 100))),
                       "intent: manual(durationSeconds: 0.5, iso: 100.0)")
        XCTAssertEqual(MessageDump.describe(RemoteCmd.SetCinematic(intent: .on(aperture: 2.8))),
                       "intent: on(aperture: Optional(2.8))")
    }

    func testArraysListCountThenElements() {
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            cameraDevices: [RemoteCmd.CameraDeviceEntry(uniqueID: "id-1", localizedName: "Back Camera",
                                                        positionRaw: 1, isActive: true, isSuspended: false,
                                                        info: nil)],
            error: nil)
        let dump = MessageDump.describe(caps)
        XCTAssertTrue(dump.contains("cameraDevices: [1]"), dump)
        XCTAssertTrue(dump.contains("  [0]:\n"), dump)
        XCTAssertTrue(dump.contains("    localizedName: Back Camera"), dump)
    }

    func testErrorsShowDomainAndCode() {
        let resp = RemoteCmd.ToggleTorchResp(torchMode: nil, error: NSError(domain: "Unsupported", code: 7))
        let dump = MessageDump.describe(resp)
        XCTAssertTrue(dump.contains("error: error(Unsupported 7)"), dump)
    }

    func testMessageWithoutFields() {
        XCTAssertEqual(MessageDump.describe(RemoteCmd.ToggleTorch()), "(no fields)")
    }
}
