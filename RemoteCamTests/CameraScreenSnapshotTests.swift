import XCTest
import SwiftUI
@testable import RemoteShutter

/// Renders `CameraScreenView` in a real window (hosted test bundle) across its
/// chrome states and attaches PNGs to the test result, so the camera screen —
/// which in the app only exists with a connected peer — can be verified
/// visually without one. Each test also asserts the render is non-blank so a
/// broken layout fails in CI, not just in the attachment gallery.
@MainActor
final class CameraScreenSnapshotTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852)) // iPhone 16
        // Off-screen windows render blank; attach to the test host's scene.
        window.windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func renderScreen(named name: String, configure: (CameraViewModel) -> Void) -> UIImage {
        let model = CameraViewModel()
        configure(model)

        let host = UIHostingController(rootView: CameraScreenView(viewModel: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        // Let SwiftUI commit the first frame (onAppear, published values).
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            // drawHierarchy needs an on-screen window; fall back to rendering
            // the layer tree, which works regardless of screen attachment.
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    /// A screen that failed to render is a uniform fill; a real one has both
    /// dark background and bright chrome. Samples a coarse pixel grid.
    private func assertHasChrome(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            XCTFail("Could not read rendered pixels", file: file, line: line)
            return
        }
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        var sawDark = false, sawBright = false
        for row in stride(from: 0, to: cgImage.height, by: 32) {
            for col in stride(from: 0, to: cgImage.width, by: 32) {
                let offset = row * bytesPerRow + col * bytesPerPixel
                let luminance = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
                if luminance < 40 { sawDark = true }
                if luminance > 180 { sawBright = true }
            }
        }
        XCTAssertTrue(sawDark, "Expected the black camera background", file: file, line: line)
        XCTAssertTrue(sawBright, "Expected bright chrome (text/badge) over the background", file: file, line: line)
    }

    func testIdlePhotoModeChrome() {
        let image = renderScreen(named: "camera-idle-photo") { model in
            model.updateStatus(mode: .Photo, resolution: .hd1080p, frameRate: .fps30,
                               photoFormat: .jpeg, hdrMode: .on)
        }
        assertHasChrome(image)
    }

    func testRecordingChromeShowsBadgeAndTimer() {
        let image = renderScreen(named: "camera-recording") { model in
            model.updateStatus(mode: .Video, resolution: .hd1080p, frameRate: .fps30,
                               photoFormat: .jpeg, hdrMode: .off)
            model.isRecordingIndicatorVisible = true
            model.recordingStartTime = Date().addingTimeInterval(-65)
            model.isRecordingTimerActive = true
        }
        assertHasChrome(image)
    }

    func testCountdownChrome() {
        let image = renderScreen(named: "camera-countdown") { model in
            model.showCountdown(3)
        }
        assertHasChrome(image)
    }

    func testVideoTransferChrome() {
        let image = renderScreen(named: "camera-video-transfer") { model in
            model.startVideoTransfer(totalBytes: 45_800_000)
            model.updateVideoTransferProgress(completedBytes: 15_200_000, totalBytes: 45_800_000)
            model.updateVideoTransferSpeed(2_100_000)
        }
        assertHasChrome(image)
    }
}
