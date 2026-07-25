import XCTest
import SwiftUI
@testable import RemoteShutter

/// Renders `DeviceScannerView` in a real window across its role states and
/// attaches PNGs to the test result. Covers the Wi-Fi guidance banner in both
/// roles, and drives the 15s escalation tip through a real TimelineView tick —
/// the one behavior no synchronous view-model test can observe.
@MainActor
final class DeviceScannerSnapshotTests: SnapshotTestCase {

    // NavigationView deliberately omitted: a UIKit-backed root defeats the
    // headless-CI ImageRenderer fallback (blank render). The scanner screen
    // is light-themed, so assertions check render variance, not dark chrome.
    private func renderScanner(named name: String,
                               configure: (DeviceScannerViewModel) -> Void) -> UIImage {
        let model = DeviceScannerViewModel()
        configure(model)
        let screen = DeviceScannerView(
            viewModel: model,
            onStartScanning: {},
            onStopScanning: {},
            onSelectPeer: { _ in },
            onCancelConnect: {},
            onShareApp: {},
            onOpenSettings: {},
            onHelp: {}
        )
        return renderScreen(named: name, screen)
    }

    func testRemoteModeShowsWifiBanner() throws {
        let image = renderScanner(named: "scanner-remote-wifi-banner") { model in
            model.role = .monitor
        }
        try skipPixelAssertsIfHeadless()
        assertRendered(image)
    }

    func testCameraModeShowsWifiBanner() throws {
        let image = renderScanner(named: "scanner-camera-wifi-banner") { model in
            model.role = .camera
        }
        try skipPixelAssertsIfHeadless()
        assertRendered(image)
    }

    /// End-to-end escalation: start scanning, let the real clock pass the 15s
    /// threshold, and verify the TimelineView surfaces the Wi-Fi tip. Slow by
    /// design (~16s) — it is the only test that exercises the actual
    /// TimelineView wiring rather than the pure function.
    func testEscalationTipAppearsAfterFifteenSeconds() throws {
        let model = DeviceScannerViewModel()
        model.role = .monitor
        model.startedScanning()

        let screen = DeviceScannerView(
            viewModel: model,
            onStartScanning: {},
            onStopScanning: {},
            onSelectPeer: { _ in },
            onCancelConnect: {},
            onShareApp: {},
            onOpenSettings: {},
            onHelp: {}
        )
        _ = renderScreen(named: "scanner-remote-scanning", screen)

        // Let the run loop turn until the threshold has genuinely passed.
        let deadline = Date(timeIntervalSinceNow: 16.5)
        while Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        // Behavioral check first — it must hold on every runner, headless or not.
        XCTAssertTrue(model.shouldShowWifiEscalation(now: Date()),
                      "escalation should be active 16s after scanning started")

        let image = renderScreen(named: "scanner-remote-wifi-escalation", screen)
        try skipPixelAssertsIfHeadless()
        assertRendered(image)
    }
}
