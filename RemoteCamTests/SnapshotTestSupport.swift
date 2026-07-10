import XCTest
import SwiftUI
@testable import RemoteShutter

/// Base class for screen snapshot tests: hosts a SwiftUI screen in a real
/// window inside the hosted test bundle, attaches a PNG of the render to the
/// test result for visual inspection, and offers a non-blank assertion so a
/// broken layout fails in CI, not just in the attachment gallery.
@MainActor
class SnapshotTestCase: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852)) // iPhone 16
        // Off-screen windows render blank; attach to the test host's scene,
        // preferring an active one (CI hosts can hold inactive scenes).
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        window.windowScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    func renderScreen<Screen: View>(named name: String, _ screen: Screen) -> UIImage {
        let host = UIHostingController(rootView: screen)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        // SwiftUI commits its first frame on the runloop, and headless CI
        // simulators take noticeably longer than a local machine — poll until
        // the chrome shows up instead of trusting a fixed delay. On a warm
        // local run the first snapshot already passes.
        var image = snapshot()
        let deadline = Date(timeIntervalSinceNow: 2.5)
        while !hasChrome(image) && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
            CATransaction.flush()
            image = snapshot()
        }

        // On a headless CI runner a second, detached window may never get a
        // display slot, so the layer tree stays empty no matter how long we
        // wait. ImageRenderer draws the SwiftUI tree without any window —
        // UIKit-backed subviews (gif badge, preview layer) are omitted, but
        // every SwiftUI element the assertions look for is not.
        if !hasChrome(image), #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes
            print("SnapshotTestCase: window render blank (scenes: \(scenes.count), "
                  + "states: \(scenes.map { $0.activationState.rawValue })) — "
                  + "falling back to ImageRenderer for \(name)")
            let renderer = ImageRenderer(content: screen)
            renderer.proposedSize = ProposedViewSize(width: window.bounds.width,
                                                     height: window.bounds.height)
            renderer.scale = 3
            if let rendered = renderer.uiImage {
                image = rendered
            }
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    private func snapshot() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { context in
            // drawHierarchy needs an on-screen window; fall back to rendering
            // the layer tree, which works regardless of screen attachment.
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    /// A screen that failed to render is a uniform fill; a real one has both
    /// dark background and bright chrome. Samples a coarse pixel grid.
    func hasChrome(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return false
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
        return sawDark && sawBright
    }

    func assertHasChrome(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(hasChrome(image),
                      "Expected dark background AND bright chrome in the render",
                      file: file, line: line)
    }

    /// A stand-in for the streamed camera frame: a gradient "scene" with a
    /// bright subject, so snapshots show the live-feed area realistically.
    func syntheticCameraFrame(size: CGSize = CGSize(width: 1920, height: 1080)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(red: 0.10, green: 0.30, blue: 0.55, alpha: 1).cgColor,
                          UIColor(red: 0.45, green: 0.20, blue: 0.50, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: [])
            }
            UIColor.white.withAlphaComponent(0.9).setFill()
            let diameter = size.height * 0.4
            context.cgContext.fillEllipse(in: CGRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter))
        }
    }
}
