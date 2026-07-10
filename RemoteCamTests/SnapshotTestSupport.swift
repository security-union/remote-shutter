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
        // Off-screen windows render blank; attach to the test host's scene.
        window.windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
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
    func assertHasChrome(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) {
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
        XCTAssertTrue(sawDark, "Expected the dark screen background", file: file, line: line)
        XCTAssertTrue(sawBright, "Expected bright chrome (text/badge) over the background", file: file, line: line)
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
