//
//  MonitorChromeTests.swift
//  RemoteShutterTests
//
//  Pure policy tests for the monitor screen's chrome: where the action cluster
//  docks, how the self-timer cycles, which tiles the tray composes, and which
//  in-flight indicator a session state implies.
//

import XCTest
import CoreGraphics
@testable import RemoteShutter

final class MonitorChromeTests: XCTestCase {

    // MARK: - Derived control state (one stored mode, no thrash)

    /// The REC dot, the timer, and every control enable are lookups off
    /// `uiState` — they CANNOT disagree. This pins the WHOLE derivation
    /// table, every flag in every mode (they were 13 hand-set booleans, and
    /// paths that forgot one left the screen self-contradicting: a ticking
    /// timer with no dot, a dead back button in photo mode).
    func testControlSurfaceDerivationMatrix() {
        // swiftlint:disable:next large_tuple
        let expected: [(MonitorUIState, rec: Bool, timer: Bool, gallery: Bool, back: Bool,
                        flash: Bool, torch: Bool, settings: Bool, toggle: Bool,
                        slider: Bool, segmented: Bool, lens: Bool, zoom: Bool, quality: Bool)] = [
            (.photoMode, rec: false, timer: false, gallery: true, back: true,
             flash: true, torch: true, settings: true, toggle: true,
             slider: true, segmented: true, lens: true, zoom: true, quality: true),
            (.videoMode, rec: false, timer: false, gallery: true, back: true,
             flash: false, torch: true, settings: true, toggle: true,
             slider: true, segmented: true, lens: true, zoom: true, quality: true),
            (.videoRecording, rec: true, timer: true, gallery: false, back: false,
             flash: false, torch: true, settings: false, toggle: false,
             slider: false, segmented: false, lens: true, zoom: true, quality: false),
            (.shortsMode, rec: false, timer: false, gallery: true, back: true,
             flash: false, torch: true, settings: true, toggle: true,
             slider: false, segmented: true, lens: true, zoom: true, quality: false)
        ]

        let model = MonitorViewModel()
        for row in expected {
            model.uiState = row.0
            XCTAssertEqual(model.isRecording, row.rec, "\(row.0) isRecording")
            XCTAssertEqual(model.isShowingRecordingDuration, row.timer, "\(row.0) timer")
            XCTAssertEqual(model.isGalleryEnabled, row.gallery, "\(row.0) gallery")
            XCTAssertEqual(model.isBackEnabled, row.back, "\(row.0) back")
            XCTAssertEqual(model.isFlashButtonEnabled, row.flash, "\(row.0) flash")
            XCTAssertEqual(model.isTorchButtonEnabled, row.torch, "\(row.0) torch")
            XCTAssertEqual(model.isSettingsEnabled, row.settings, "\(row.0) settings")
            XCTAssertEqual(model.isToggleCameraEnabled, row.toggle, "\(row.0) toggleCamera")
            XCTAssertEqual(model.isTimerSliderEnabled, row.slider, "\(row.0) timerSlider")
            XCTAssertEqual(model.isSegmentedControlEnabled, row.segmented, "\(row.0) segmented")
            XCTAssertEqual(model.isLensControlEnabled, row.lens, "\(row.0) lens")
            XCTAssertEqual(model.isZoomSliderEnabled, row.zoom, "\(row.0) zoom")
            XCTAssertEqual(model.isQualityControlEnabled, row.quality, "\(row.0) quality")
            XCTAssertFalse(MonitorViewModel.prompt(for: row.0).isEmpty, "\(row.0) prompt")
        }
    }

    /// Leaving the recording mode voids the camera-driven elapsed with it —
    /// the timer can never show a value against a mode that isn't recording.
    func testLeavingRecordingModeClearsTimerStart() {
        let model = MonitorViewModel()
        model.uiState = .videoRecording
        model.recordingElapsedMillis = 30_000

        model.uiState = .photoMode

        XCTAssertNil(model.recordingElapsedMillis)
        XCTAssertFalse(model.isShowingRecordingDuration)
    }

    // MARK: - Dock

    private func dock(_ size: CGSize,
                      _ orientation: UIInterfaceOrientation = .portrait,
                      _ input: MonitorChromeInput = .touch) -> MonitorChromeDock {
        MonitorChromeLayout.dock(viewSize: size,
                                 interfaceOrientation: orientation,
                                 input: input)
    }

    /// The rail exists so rotation doesn't move the shutter under a thumb. A
    /// pointer-driven window has neither, and Catalyst reports .landscapeRight
    /// permanently — without this it would rail forever.
    func testPointerDrivenWindowAlwaysDocksBottom() {
        XCTAssertEqual(dock(CGSize(width: 1440, height: 900), .landscapeRight, .pointer), .bottom)
        XCTAssertEqual(dock(CGSize(width: 1440, height: 900), .landscapeLeft, .pointer), .bottom)
    }

    func testPortraitPhoneDocksBottom() {
        XCTAssertEqual(dock(CGSize(width: 393, height: 852)), .bottom)
    }

    /// A `horizontalSizeClass` rule would call iPhone landscape compact and
    /// wrongly dock it at the bottom, crushing the preview.
    func testLandscapePhoneDocksToARail() {
        XCTAssertEqual(dock(CGSize(width: 852, height: 393), .landscapeRight), .trailing)
        XCTAssertEqual(dock(CGSize(width: 852, height: 393), .landscapeLeft), .leading)
    }

    /// The shutter is muscle memory: the two landscapes must dock to opposite
    /// rails, so the cluster stays on the same physical edge as the device turns.
    func testOppositeLandscapesDockToOppositeRails() {
        let size = CGSize(width: 852, height: 393)
        XCTAssertNotEqual(dock(size, .landscapeLeft), dock(size, .landscapeRight))
    }

    /// An iPad in Split View is landscape as a *device* but portrait-shaped as
    /// a view; the layout must follow the view.
    func testNarrowSplitViewDocksBottom() {
        XCTAssertEqual(dock(CGSize(width: 507, height: 1024), .landscapeRight), .bottom)
    }

    func testWideMacWindowDocksTrailing() {
        XCTAssertEqual(dock(CGSize(width: 1440, height: 900)), .trailing)
    }

    /// A resized Mac window can be portrait-shaped; nothing about being a Mac
    /// should force a rail.
    func testNarrowMacWindowDocksBottom() {
        XCTAssertEqual(dock(CGSize(width: 600, height: 900)), .bottom)
    }

    func testSquareDocksBottom() {
        XCTAssertEqual(dock(CGSize(width: 800, height: 800)), .bottom)
    }

    // MARK: - Self-timer

    func testTimerCyclesThroughStopsAndWraps() {
        XCTAssertEqual(MonitorTimer.next(after: 0), 3)
        XCTAssertEqual(MonitorTimer.next(after: 3), 5)
        XCTAssertEqual(MonitorTimer.next(after: 5), 10)
        XCTAssertEqual(MonitorTimer.next(after: 10), 20)
        XCTAssertEqual(MonitorTimer.next(after: 20), 0, "the last stop wraps back to off")
    }

    /// Older builds stored any integer 0...20 under `timerDefault` via the
    /// slider. Such a value must round up onto a real stop, not strand the
    /// cycle.
    func testTimerRoundsLegacySliderValueUpToNextStop() {
        XCTAssertEqual(MonitorTimer.next(after: 7), 10)
        XCTAssertEqual(MonitorTimer.next(after: 1), 3)
        XCTAssertEqual(MonitorTimer.next(after: 19), 20)
    }

    /// Above the top stop there is nowhere to go but off.
    func testTimerBeyondLastStopWrapsToOff() {
        XCTAssertEqual(MonitorTimer.next(after: 25), 0)
    }

    // MARK: - Tray composition

    private func items(_ state: MonitorUIState,
                       supportsHEIF: Bool = false,
                       supportsHDR: Bool = false,
                       supportsCameraStandby: Bool = false,
                       resolutionCount: Int = 1,
                       frameRateCount: Int = 1) -> [MonitorTrayItem] {
        MonitorTray.items(for: state,
                          supportsHEIF: supportsHEIF,
                          supportsHDR: supportsHDR,
                          supportsCameraStandby: supportsCameraStandby,
                          resolutionCount: resolutionCount,
                          frameRateCount: frameRateCount)
    }

    /// A camera with no optional capabilities gets the irreducible tray.
    func testPhotoModeMinimalTray() {
        XCTAssertEqual(items(.photoMode), [.timer, .aspect, .settings, .help])
    }

    func testPhotoModeAddsFormatAndHDRWhenSupported() {
        XCTAssertEqual(items(.photoMode, supportsHEIF: true, supportsHDR: true),
                       [.timer, .aspect, .format, .hdr, .settings, .help])
    }

    /// Photo-only tiles must not leak into video mode, and vice versa.
    func testVideoModeShowsQualityNotPhotoTiles() {
        XCTAssertEqual(items(.videoMode, supportsHEIF: true, supportsHDR: true,
                             resolutionCount: 3, frameRateCount: 2),
                       [.timer, .aspect, .resolution, .frameRate, .settings, .help])
    }

    /// A single choice is not a choice — don't show a tile that cannot change.
    func testSingleResolutionAndFrameRateAreOmitted() {
        XCTAssertEqual(items(.videoMode, resolutionCount: 1, frameRateCount: 1),
                       [.timer, .aspect, .settings, .help])
    }

    /// Quality tiles stay composed while recording; the view dims them. Their
    /// disappearing mid-take would be a layout jump at the worst moment.
    func testRecordingKeepsQualityTiles() {
        XCTAssertEqual(items(.videoRecording, resolutionCount: 3, frameRateCount: 2),
                       [.timer, .aspect, .resolution, .frameRate, .settings, .help])
    }

    /// Shorts runs to a fixed duration, so a self-timer has nothing to delay.
    func testShortsModeHasNoTimer() {
        XCTAssertEqual(items(.shortsMode), [.aspect, .settings, .help])
    }

    // MARK: - Camera standby

    /// A camera that never advertised `supports_preview_mode` would silently
    /// ignore the command, so it must not be offered the control at all — the
    /// same rule the device picker and focus point follow.
    func testStandbyTileIsHiddenWhenPeerDoesNotSupportIt() {
        for state in [MonitorUIState.photoMode, .videoMode, .videoRecording, .shortsMode] {
            XCTAssertFalse(items(state).contains(.cameraStandby),
                           "\(state) offered standby to a peer that can't do it")
        }
    }

    func testStandbyTileAppearsForEveryModeWhenSupported() {
        for state in [MonitorUIState.photoMode, .videoMode, .videoRecording, .shortsMode] {
            XCTAssertTrue(items(state, supportsCameraStandby: true).contains(.cameraStandby),
                          "\(state) is missing the standby tile")
        }
    }

    /// Standby sits with Settings and Help at the end rather than among the
    /// capture settings — it controls the other device, not this shot.
    func testStandbyTileSitsBeforeSettings() {
        let tiles = items(.photoMode, supportsCameraStandby: true)
        XCTAssertEqual(tiles, [.timer, .aspect, .cameraStandby, .settings, .help])
    }

    /// Settings and Help are the tray's floor — they are how the viewfinder
    /// gives up its nav bar.
    func testEveryModeOffersSettingsAndHelp() {
        for state in [MonitorUIState.photoMode, .videoMode, .videoRecording, .shortsMode] {
            let tiles = items(state)
            XCTAssertTrue(tiles.contains(.settings), "\(state) is missing Settings")
            XCTAssertTrue(tiles.contains(.help), "\(state) is missing Help")
        }
    }

    // MARK: - Link health

    func testLiveWhenLinkedAndFramesFlowing() {
        XCTAssertEqual(MonitorLinkState.resolve(link: .linked, isPreviewStale: false), .live)
    }

    /// The bug this exists for: the session still believes it is connected, the
    /// frames have stopped, and the old UI said nothing at all.
    func testStalledWhenLinkedButFramesStopped() {
        XCTAssertEqual(MonitorLinkState.resolve(link: .linked, isPreviewStale: true), .stalled)
    }

    /// A dropped link outranks a stall — the stall is its symptom, and naming
    /// the cause is more useful than naming the effect.
    func testReconnectingOutranksStall() {
        XCTAssertEqual(MonitorLinkState.resolve(link: .reconnecting(peerName: "iPhone"), isPreviewStale: true),
                       .reconnecting)
        XCTAssertEqual(MonitorLinkState.resolve(link: .reconnecting(peerName: "iPhone"), isPreviewStale: false),
                       .reconnecting)
    }

    // MARK: - In-flight activity

    func testTransientMonitorStatesMapToActivities() {
        XCTAssertEqual(MonitorActivity.forState(.monitorTakingPicture(generation: 1, phase: .requesting)),
                       .capturing)
        XCTAssertEqual(MonitorActivity.forState(.monitorTakingPicture(generation: 1, phase: .receiving)),
                       .receivingCapture)
        XCTAssertEqual(MonitorActivity.forState(.monitorTogglingCamera(mode: .photo, generation: 2)),
                       .switchingCamera)
        XCTAssertEqual(MonitorActivity.forState(.monitorTogglingFlash(generation: 3)), .togglingFlash)
        XCTAssertEqual(MonitorActivity.forState(.monitorSwitchingLens(returnTo: .mode(.photo), generation: 4)),
                       .switchingLens)
    }

    /// The whole point of deriving this from state: a settled state has no
    /// activity, so an indicator cannot outlive the command it described.
    func testSettledStatesHaveNoActivity() {
        XCTAssertNil(MonitorActivity.forState(.monitor(mode: .photo)))
        XCTAssertNil(MonitorActivity.forState(.monitor(mode: .video)))
        XCTAssertNil(MonitorActivity.forState(.monitorRecordingVideo))
        XCTAssertNil(MonitorActivity.forState(.connected))
        XCTAssertNil(MonitorActivity.forState(.scanning))
    }

    /// Camera-side states drive the camera screen, never the monitor's chrome.
    func testCameraStatesHaveNoMonitorActivity() {
        XCTAssertNil(MonitorActivity.forState(.camera))
        XCTAssertNil(MonitorActivity.forState(.cameraTakingPic(sendMediaToPeer: true, generation: 1)))
        XCTAssertNil(MonitorActivity.forState(.cameraRecordingVideo))
    }
}
