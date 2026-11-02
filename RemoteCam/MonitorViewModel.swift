import Foundation
import SwiftUI
import Combine

// MARK: - UI State
enum MonitorUIState {
    case photoMode
    case videoMode
    case videoRecording
    case shortsMode
}

// MARK: - Frame Display Model

/// One lane's live-preview frames. Frames go straight to the attached
/// `PreviewSurfaceView`s; SwiftUI observes only `frameSize`, which changes
/// rarely (first frame, rotation, stream tier). Main thread only.
final class FrameDisplayModel: ObservableObject {
    /// Pixel size of the latest frame; `LiveFrameView` lays out the letterbox
    /// and crop overlay from it. Nil until the first frame.
    @Published private(set) var frameSize: CGSize?
    /// The frame on screen, so a surface attached later starts with it.
    private(set) var latest: PreviewFrame?
    private let surfaces = NSHashTable<PreviewSurfaceView>.weakObjects()

    func show(_ frame: PreviewFrame) {
        latest = frame
        for case let surface as PreviewSurfaceView in surfaces.objectEnumerator() { surface.show(frame) }
        let size = frame.pixelSize
        if frameSize != size { frameSize = size }
    }

    func attach(_ surface: PreviewSurfaceView) {
        surfaces.add(surface)
        surface.show(latest)
    }

    func detach(_ surface: PreviewSurfaceView) {
        surfaces.remove(surface)
        surface.show(nil)
    }
}

// MARK: - Camera switch control

/// Which switch control the monitor shows for the peer's cameras.
enum CameraSwitchControl {
    /// One camera — nothing to switch to.
    case hidden
    /// Two usable cameras (or a legacy peer with no device list):
    /// the classic flip button, tap toggles.
    case flipButton
    /// Three or more cameras — or a suspended one worth *seeing* grayed
    /// out: a menu, tap opens the device list.
    case deviceMenu

    /// The one rule for which control a camera's advertised device list earns.
    /// A peer that advertised no list (an iPhone) keeps the flip button.
    static func forDevices(_ devices: [RemoteCmd.CameraDeviceEntry]) -> CameraSwitchControl {
        guard !devices.isEmpty else { return .flipButton }
        let healthy = devices.filter { !$0.isSuspended }
        switch (devices.count, healthy.count) {
        case (1, _): return .hidden
        case (2, 2): return .flipButton
        default: return .deviceMenu
        }
    }
}
