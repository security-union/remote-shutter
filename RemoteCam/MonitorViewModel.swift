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

/// The live-preview frame stream, isolated from the rest of the monitor's
/// state: frames arrive ~20×/sec, and publishing them through the main view
/// model re-rendered every control on each frame (the device menu visibly
/// flickered). Only the preview's `LiveFrameView` observes this.
final class FrameDisplayModel: ObservableObject {
    @Published var cameraImage: UIImage?
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
