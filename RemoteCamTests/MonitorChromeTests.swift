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

}
