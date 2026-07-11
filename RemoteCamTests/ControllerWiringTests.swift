//
//  ControllerWiringTests.swift
//  RemoteShutterTests
//
//  Characterization tests for the UIKit shell controllers: each screen's
//  contract (SwiftUI hosting, navigation, actor lifecycle) is pinned down
//  here so shell refactors fail loudly instead of silently breaking wiring.
//  These instantiate the REAL view controllers inside the hosted test app.
//

import XCTest
import SwiftUI

@testable import RemoteShutter

class ControllerWiringTests: XCTestCase {

    // MARK: - Helpers

    private func pump(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = 5,
                           _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline { pump(0.02) }
        return condition()
    }

    /// The full-screen SwiftUI host child of a shell controller, if wired.
    private func hostedChild<V: View>(of parent: UIViewController,
                                      hosting: V.Type) -> UIHostingController<V>? {
        parent.children.compactMap { $0 as? UIHostingController<V> }.first
    }

    private func assertHostPinnedToBounds<V: View>(
        _ host: UIHostingController<V>?, in parent: UIViewController,
        file: StaticString = #filePath, line: UInt = #line) {
        guard let host else {
            XCTFail("no UIHostingController<\(V.self)> child", file: file, line: line)
            return
        }
        XCTAssertEqual(host.view.superview, parent.view, file: file, line: line)
        XCTAssertFalse(host.view.translatesAutoresizingMaskIntoConstraints, file: file, line: line)
        parent.view.layoutIfNeeded()
        XCTAssertEqual(host.view.frame, parent.view.bounds, file: file, line: line)
    }

    // MARK: - WelcomeViewController

    func testWelcomeControllerHostsWelcomeView() {
        let welcome = WelcomeViewController()
        _ = welcome.view // triggers viewDidLoad

        assertHostPinnedToBounds(hostedChild(of: welcome, hosting: WelcomeView.self),
                                 in: welcome)
    }

    func testWelcomeContinuePushesRolePicker() {
        let welcome = WelcomeViewController()
        let nav = UINavigationController(rootViewController: welcome)
        _ = welcome.view

        welcome.goToConnectViewController()

        XCTAssertTrue(waitUntil { nav.topViewController is RolePickerController },
                      "continue must push RolePickerController")
    }

    // MARK: - RolePickerController

    func testRolePickerHostsRolePickerView() {
        let picker = RolePickerController()
        _ = picker.view

        assertHostPinnedToBounds(hostedChild(of: picker, hosting: RolePickerView.self),
                                 in: picker)
    }

    func testRolePickerBecomeMonitorPushesScannerWithMonitorRole() {
        let picker = RolePickerController()
        let nav = UINavigationController(rootViewController: picker)
        _ = picker.view

        // becomeMonitor is the permission-free path (camera role gates on
        // PermissionManager and would present a modal in the test host).
        picker.becomeMonitor()

        XCTAssertTrue(waitUntil { nav.topViewController is DeviceScannerViewController })
        let scanner = nav.topViewController as? DeviceScannerViewController
        XCTAssertEqual(scanner?.role, .monitor)
    }

    // MARK: - DeviceScannerViewController

    func testDeviceScannerOwnsSessionAndHostsScannerView() {
        // autoreleasepool so UIKit's autoreleased references to the controller
        // are released and deinit actually runs inside this test.
        autoreleasepool {
            var scanner: DeviceScannerViewController? = DeviceScannerViewController(role: .camera)
            _ = scanner!.view // viewDidLoad wires the coordinator + frame sender

            XCTAssertNotNil(scanner!.remoteCamSession)
            XCTAssertNotNil(scanner!.frameSender)
            XCTAssertEqual(scanner!.scannerViewModel.role, .camera)
            assertHostPinnedToBounds(hostedChild(of: scanner!, hosting: DeviceScannerView.self),
                                     in: scanner!)
            scanner = nil
        }
        // The coordinator and frame sender are owned by the controller and
        // die with it — no shared registry left to assert against.
    }

    // MARK: - MonitorViewController

    func testMonitorControllerWiresPresenterAndHostsMonitorView() {
        let session = SessionCoordinator()
        defer { session.stop() }

        autoreleasepool {
            var monitorVC: MonitorViewController? = MonitorViewController(session: session)
            _ = monitorVC!.view

            assertHostPinnedToBounds(hostedChild(of: monitorVC!, hosting: MonitorView.self),
                                     in: monitorVC!)
            XCTAssertEqual(monitorVC!.viewModel.uiState, .photoMode,
                           "viewDidLoad must configure the view model for photo mode")
            monitorVC = nil
        }
    }
}
