//
//  MonitorDisplay.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import CoreGraphics
import AVFoundation

/// Everything `MonitorActor` needs from the monitor screen.
///
/// `MonitorViewController` is the production implementation; tests drive the
/// actor with a fake. This is the seam that lets the actor outlive the
/// UIKit shell during the SwiftUI migration.
protocol MonitorDisplay: AnyObject {

    var viewModel: MonitorViewModel { get }
    var frameStreamReceiver: FrameStreamReceiver { get }

    func swiftUIConfigurePhotoMode()
    func swiftUIConfigureVideoMode()
    func swiftUIConfigureVideoRecording()
    func swiftUIConfigureShortsMode()

    func updateFlashModeInViewModel(_ flashMode: AVCaptureDevice.FlashMode)
    func updateTorchModeInViewModel(_ torchMode: AVCaptureDevice.TorchMode)
    /// The whole control-plane snapshot (v11) — zoom, lens, exposure and
    /// Cinematic in one value. Replaces the per-field zoom/lens updates.
    func applyControlState(_ state: ControlState)

    /// Leave the monitor screen (e.g. the peer refused the monitor role).
    func exitMonitor()
}
