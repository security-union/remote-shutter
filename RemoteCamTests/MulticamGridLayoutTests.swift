//
//  MulticamGridLayoutTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import XCTest
import SwiftUI
@testable import RemoteShutter

/// Renders the director's grid with a full paid rig and checks the picture:
/// every camera gets a tile where the layout says it should be, and the one
/// spare cell stays empty. The render is attached to the result for a look.
final class MulticamGridLayoutTests: SnapshotTestCase {

    func testEightCamerasFillAThreeByThreeGridOnAnIPad() throws {
        let viewport = CGSize(width: 1180, height: 820) // iPad Air, landscape
        setWindowSize(viewport)

        let cameraCount = StoreManager.maxPaidCameras
        let viewModel = MulticamViewModel()
        viewModel.interfaceOrientation = .landscapeRight
        viewModel.apply((1...cameraCount).map { laneInfo(index: $0) })
        viewModel.displayMode = .grid

        let image = renderScreen(named: "multicam-grid-8-ipad", director(viewModel))
        assertHasChrome(image)

        // Tiles with no frame yet draw a grey placeholder; the empty cell is
        // the black background. Sample each cell left of its centre, clear of
        // the camera glyph, the name chip and the status badge.
        let columns = MultiCamChrome.gridColumnCount(cameraCount: cameraCount)
        let rows = MultiCamChrome.gridRowCount(cameraCount: cameraCount)
        let cell = MultiCamChrome.gridCellSize(cameraCount: cameraCount, in: viewport)
        let step = CGSize(width: cell.width + MultiCamChrome.gridSpacing,
                          height: cell.height + MultiCamChrome.gridSpacing)
        let top = MultiCamChrome.gridPadding

        for index in 0..<(columns * rows) {
            let column = index % columns, row = index / columns
            let point = CGPoint(
                x: MultiCamChrome.gridPadding + CGFloat(column) * step.width + cell.width * 0.2,
                y: top + CGFloat(row) * step.height + cell.height * 0.4)
            let luminance = try XCTUnwrap(luminance(of: image, at: point, viewport: viewport))
            if index < cameraCount {
                XCTAssertGreaterThan(luminance, 40, "camera \(index + 1) should have a tile at row \(row), column \(column)")
            } else {
                XCTAssertLessThan(luminance, 20, "cell \(index + 1) should be empty")
            }
        }
    }

    // MARK: - Helpers

    private func laneInfo(index: Int) -> MulticamLaneInfo {
        MulticamLaneInfo(peerID: MCPeerID(displayName: "Camera \(index)"),
                         displayName: "Camera \(index)",
                         status: .linked, isFocused: index == 1, clockOffsetMillis: nil,
                         captureOutcome: nil, isRecording: false, recordingElapsedMillis: nil,
                         needsQualityRematch: false, collection: .idle, canFlipCamera: false,
                         cameraDevices: [], activeDeviceID: nil,
                         supportsFocusPoint: false, hasTorch: false,
                         zoomFactor: 1, maxZoomFactor: 1, zoomStops: [1], wideAngleZoomFactor: 1,
                         torchOn: false, flashOn: false, inFlight: [], exposure: nil)
    }

    /// The luminance (0–255) at a point in screen coordinates, whatever scale
    /// the render came back at.
    private func luminance(of image: UIImage, at point: CGPoint, viewport: CGSize) -> Int? {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let scale = CGFloat(cgImage.width) / viewport.width
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return nil }
        let offset = y * cgImage.bytesPerRow + x * (cgImage.bitsPerPixel / 8)
        return (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
    }

    private func director(_ viewModel: MulticamViewModel) -> MulticamView {
        MulticamView(viewModel: viewModel,
                     onFocusLane: { _ in }, onShutter: {}, onSelectMode: { _ in },
                     onAddCamera: {}, onInviteCamera: { _ in }, onSetTimer: { _ in },
                     onSelectVideoQuality: { _, _ in }, onAutomaticVideoQuality: {},
                     onSetPhotoFormat: { _ in }, onSetHDR: { _ in }, onSetAspectRatio: { _ in },
                     onSetStandby: { _ in }, onSetExposureControls: { _ in },
                     onExposureChange: { _, _, _ in }, onSetExposureMode: { _, _ in },
                     onApertureChange: { _ in }, onOpenSettings: {}, onOpenHelp: {},
                     onRetryCollection: { _ in }, onFlipCamera: { _ in },
                     onSelectCameraDevice: { _, _ in }, onToggleTorch: { _ in },
                     onToggleFlash: { _ in }, onDisconnectCamera: { _ in },
                     onZoomChange: { _, _ in }, onFocusTap: { _, _ in }, onBack: {})
    }
}
