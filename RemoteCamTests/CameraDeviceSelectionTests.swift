//
//  CameraDeviceSelectionTests.swift
//  RemoteShutterTests
//
//  The pure device-selection policy: exact ID → same position → first
//  available → nil. Macs expose N cameras (often all `.unspecified`), so the
//  fallbacks are what keep an unplugged-camera request from failing outright.
//

import XCTest
import AVFoundation

@testable import RemoteShutter

final class CameraDeviceSelectionTests: XCTestCase {

    private let backCamera = CameraDeviceDescriptor(
        uniqueID: "back-0", localizedName: "Back Camera",
        position: .back, deviceType: .builtInWideAngleCamera)
    private let frontCamera = CameraDeviceDescriptor(
        uniqueID: "front-0", localizedName: "Front Camera",
        position: .front, deviceType: .builtInWideAngleCamera)
    private let usbCamera = CameraDeviceDescriptor(
        uniqueID: "usb-0", localizedName: "USB Camera",
        position: .unspecified, deviceType: .builtInWideAngleCamera)

    func testExactIDMatchWins() {
        let resolved = CameraDeviceDescriptor.resolveSelection(
            requestedID: "front-0",
            available: [backCamera, frontCamera, usbCamera],
            fallbackPosition: .back)
        XCTAssertEqual(resolved, frontCamera)
    }

    func testVanishedIDFallsBackToSamePosition() {
        let resolved = CameraDeviceDescriptor.resolveSelection(
            requestedID: "gone-camera",
            available: [usbCamera, frontCamera],
            fallbackPosition: .front)
        XCTAssertEqual(resolved, frontCamera)
    }

    func testVanishedIDWithNoPositionMatchFallsBackToFirst() {
        let resolved = CameraDeviceDescriptor.resolveSelection(
            requestedID: "gone-camera",
            available: [usbCamera, frontCamera],
            fallbackPosition: .back)
        XCTAssertEqual(resolved, usbCamera)
    }

    func testUnspecifiedFallbackPositionMatchesUnspecifiedDevice() {
        // Mac-shaped fleet: everything is .unspecified.
        let secondUSB = CameraDeviceDescriptor(
            uniqueID: "usb-1", localizedName: "Other USB Camera",
            position: .unspecified, deviceType: .builtInWideAngleCamera)
        let resolved = CameraDeviceDescriptor.resolveSelection(
            requestedID: "gone-camera",
            available: [usbCamera, secondUSB],
            fallbackPosition: .unspecified)
        XCTAssertEqual(resolved, usbCamera)
    }

    func testEmptyDeviceListResolvesToNil() {
        let resolved = CameraDeviceDescriptor.resolveSelection(
            requestedID: "anything", available: [], fallbackPosition: .back)
        XCTAssertNil(resolved)
    }

    // MARK: - Toggle selection (iOS position flip / Mac device cycle)

    func testFlipTogglesBackToFront() {
        let next = CameraDeviceDescriptor.nextToggleSelection(
            currentID: "back-0", available: [backCamera, frontCamera], flipPosition: true)
        XCTAssertEqual(next, frontCamera)
    }

    func testFlipWithUnknownCurrentReturnsNil() {
        // Mirrors the engine's historical behavior: a flip with no active
        // device is an error, not a silent pick.
        XCTAssertNil(CameraDeviceDescriptor.nextToggleSelection(
            currentID: nil, available: [backCamera, frontCamera], flipPosition: true))
    }

    func testCycleAdvancesInListOrderAndWraps() {
        let devices = [backCamera, frontCamera, usbCamera]
        let afterBack = CameraDeviceDescriptor.nextToggleSelection(
            currentID: "back-0", available: devices, flipPosition: false)
        XCTAssertEqual(afterBack, frontCamera)
        let afterUSB = CameraDeviceDescriptor.nextToggleSelection(
            currentID: "usb-0", available: devices, flipPosition: false)
        XCTAssertEqual(afterUSB, backCamera, "cycle wraps to the first device")
    }

    func testCycleSkipsSuspendedDevices() {
        var suspended = frontCamera
        suspended.isSuspended = true
        let next = CameraDeviceDescriptor.nextToggleSelection(
            currentID: "back-0", available: [backCamera, suspended, usbCamera], flipPosition: false)
        XCTAssertEqual(next, usbCamera, "a clamshell camera must never be cycled onto")
    }

    func testCycleWithUnknownCurrentStartsAtFirstHealthyDevice() {
        var suspended = backCamera
        suspended.isSuspended = true
        let next = CameraDeviceDescriptor.nextToggleSelection(
            currentID: nil, available: [suspended, usbCamera], flipPosition: false)
        XCTAssertEqual(next, usbCamera)
    }

    // MARK: - Suspension (connected but zero frames — clamshell built-in)

    func testSuspendedDeviceIsNeverResolvedEvenWhenRequested() {
        var suspendedBuiltIn = backCamera
        suspendedBuiltIn.isSuspended = true
        let resolved = CameraDeviceDescriptor.resolveSelection(
            requestedID: suspendedBuiltIn.uniqueID,
            available: [suspendedBuiltIn, usbCamera],
            fallbackPosition: .back)
        XCTAssertEqual(resolved, usbCamera, "a suspended camera must never be selected")
    }

    func testAllSuspendedResolvesToNil() {
        var a = backCamera, b = usbCamera
        a.isSuspended = true
        b.isSuspended = true
        XCTAssertNil(CameraDeviceDescriptor.resolveSelection(
            requestedID: "anything", available: [a, b], fallbackPosition: .back))
    }

    func testFakeRejectsExplicitSelectionOfSuspendedDevice() async {
        let fake = FakeCameraControlling()
        fake.availableDevices = [
            CameraDeviceDescriptor(uniqueID: "builtin", localizedName: "Built-in",
                                   position: .unspecified, deviceType: .builtInWideAngleCamera,
                                   isSuspended: true),
            CameraDeviceDescriptor(uniqueID: "usb", localizedName: "USB",
                                   position: .unspecified, deviceType: .builtInWideAngleCamera)
        ]
        fake.activeDeviceID = "usb"
        do {
            _ = try await fake.selectCameraDevice(uniqueID: "builtin")
            XCTFail("selecting a suspended camera must throw")
        } catch {
            XCTAssertTrue(error._domain.contains("unavailable"))
        }
    }

    @MainActor
    func testCameraViewModelPublishesDeviceList() async {
        let model = CameraViewModel()
        model.updateCameraDevices([backCamera, usbCamera], activeID: "usb-0")
        // updateCameraDevices hops to main; suspending lets the main queue drain.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.availableCameraDevices, [backCamera, usbCamera])
        XCTAssertEqual(model.activeCameraDeviceID, "usb-0")
    }

    func testFakeCameraSelectionUpdatesActiveDevice() async throws {
        let fake = FakeCameraControlling()
        let result = try await fake.selectCameraDevice(uniqueID: "fake-front")
        XCTAssertEqual(result.device.uniqueID, "fake-front")
        let current = await fake.currentCameraDevice()
        XCTAssertEqual(current?.uniqueID, "fake-front")
        XCTAssertEqual(fake.deviceSelections, ["fake-front"])
        XCTAssertNil(result.flashMode, "front camera has no flash in the fake")
    }
}
