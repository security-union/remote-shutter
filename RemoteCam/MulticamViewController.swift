//
//  MulticamViewController.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import MPCCompat
import StoreKit
import SwiftUI
import UIKit

/// Hosts the multicam director screen. Owns the `MulticamController` actor and
/// the `MulticamViewModel`, and bridges the two: controller snapshots become
/// lane updates, and per-lane preview frames are routed to exactly one lane's
/// decoder (the rendering-isolation contract).
///
/// The 1:1 `MonitorViewController` is untouched; this is a parallel screen
/// reached only from a multicam session.
public final class MulticamViewController: UIViewController {

    private let controller: MulticamController
    private let viewModel = MulticamViewModel()
    private var hosting: UIHostingController<MulticamView>?

    /// Rate-limits zoom sends to the focused camera, same as the 1:1 monitor,
    /// so a drag doesn't flood the wire; the trailing edge guarantees the final
    /// value lands.
    private var zoomThrottle = ZoomSendThrottle()
    private var trailingZoomTimer: Timer?

    /// `controller` must already be `install`-ed with its transport + peers by
    /// the caller (the scanner handoff), so lanes light up immediately.
    init(controller: MulticamController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    public override var shouldAutorotate: Bool { true }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // The controller's UI commands are `nonisolated` (they `tell` the
        // single inbox), so the call sites are plain synchronous sends — no
        // `Task { await }` wrappers.
        let multicamView = MulticamView(
            viewModel: viewModel,
            onFocusLane: { [weak self] lane in self?.controller.setFocusedPeer(lane.peerID) },
            onShutter: { [weak self] in self?.triggerShutter() },
            onToggleMode: { [weak self] in
                // The mode is frozen while a shot is in play — recording,
                // collecting acks, or counting down. What you armed is what fires.
                guard let self, !self.viewModel.isRecording, !self.viewModel.isCapturing,
                      self.viewModel.rigSettings.countdown == nil else { return }
                self.viewModel.mode = self.viewModel.mode == .photo ? .video : .photo
                logInfo("director: mode → \(self.viewModel.mode)")
            },
            onAddCamera: { [weak self] in self?.handleAddCameraTapped() },
            onInviteCamera: { [weak self] peer in
                guard let self else { return }
                self.viewModel.showingAddCamera = false
                self.controller.inviteCamera(peer)
            },
            onSetTimer: { [weak self] seconds in self?.controller.setRigTimer(seconds) },
            onSelectVideoQuality: { [weak self] res, fps in
                self?.controller.setVideoQuality(resolution: res, frameRate: fps)
            },
            onAutomaticVideoQuality: { [weak self] in self?.controller.applyAutomaticVideoQuality() },
            onSetPhotoFormat: { [weak self] format in
                self?.controller.setPhotoQuality(format: format,
                                                 hdr: self?.viewModel.rigSettings.activeHDR ?? .off)
            },
            onSetHDR: { [weak self] on in
                self?.controller.setPhotoQuality(
                    format: self?.viewModel.rigSettings.activePhotoFormat ?? .jpeg,
                    hdr: on ? .on : .off)
            },
            onSetAspectRatio: { [weak self] ratio in self?.controller.setAspectRatio(ratio) },
            onSetStandby: { [weak self] on in self?.controller.setRigStandby(on) },
            onOpenSettings: { [weak self] in
                logInfo("director: settings opened")
                self?.showPaywall()
            },
            onOpenHelp: { [weak self] in
                logInfo("director: help opened")
                self?.presentHelpSheet()
            },
            onRetryCollection: { [weak self] lane in self?.controller.retryCollection(for: lane.peerID) },
            onFlipCamera: { [weak self] lane in self?.controller.flipCamera(lane.peerID) },
            onToggleTorch: { [weak self] lane in self?.controller.toggleTorch(on: lane.peerID) },
            onToggleFlash: { [weak self] lane in self?.controller.toggleFlash(on: lane.peerID) },
            onDisconnectCamera: { [weak self] lane in self?.controller.disconnectCamera(lane.peerID) },
            onZoomChange: { [weak self] lane, factor in self?.handleZoomChange(factor, on: lane.peerID) },
            onFocusTap: { [weak self] lane, point in self?.handleFocusTap(point, on: lane.peerID) },
            onBack: { [weak self] in
                logInfo("director: back → scanner")
                self?.navigationController?.popViewController(animated: true)
            })
        hosting = embedSwiftUIView(multicamView)

        Task { await controller.setDisplay(self) }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        syncInterfaceOrientation()
    }

    public override func viewWillTransition(to size: CGSize,
                                            with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.syncInterfaceOrientation() })
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// "Add camera" tapped: at the tier cap, route free users to the paywall
    /// (the same Settings sheet every other gate uses); otherwise open the
    /// discovered-cameras sheet.
    private func handleAddCameraTapped() {
        Task { @MainActor in
            let count = await controller.cameraCount()
            if count >= StoreManager.shared.maxCameras() {
                logInfo("director: add camera tap → paywall (\(count) cameras, at tier cap)")
                showPaywall()
            } else {
                logInfo("director: add camera tap → sheet")
                viewModel.showingAddCamera = true
            }
        }
    }

    /// Tap-to-focus on the camera the tap was rendered over. Gated behind its
    /// own entitlement (mirrors the 1:1); a locked user is routed to the
    /// paywall. The controller additionally drops the command if that peer
    /// never advertised focus support.
    private func handleFocusTap(_ point: CGPoint, on peer: MCPeerID) {
        guard StoreManager.shared.hasTapToFocusFeature() else {
            logInfo("director: focus tap → paywall (feature locked)")
            showPaywall()
            return
        }
        controller.focusCamera(peer, x: Float(point.x), y: Float(point.y))
    }

    /// Reuse the existing Settings/paywall sheet — no bespoke multicam paywall.
    func showPaywall() {
        let ctrl = UIHostingController(rootView: SettingsView())
        ctrl.modalPresentationStyle = .pageSheet
        present(ctrl, animated: true)
    }

    /// Route the shutter: a photo, or record start/stop, per the current mode.
    private func triggerShutter() {
        switch (viewModel.mode, viewModel.isRecording) {
        case (.photo, _): controller.capturePhoto()
        case (.video, false): controller.startRecording()
        case (.video, true): controller.stopRecording()
        }
    }

    /// Throttled zoom, the same leading+trailing pattern the 1:1 monitor uses
    /// so a drag never floods the wire. The target camera rides through the
    /// throttle with the value — the trailing edge lands on the camera the
    /// drag was on, whatever is focused by the time it fires.
    private func handleZoomChange(_ factor: CGFloat, on peer: MCPeerID) {
        switch zoomThrottle.update(value: Double(factor), now: Date()) {
        case .sendNow:
            controller.setZoom(factor, on: peer)
        case .scheduleTrailing:
            trailingZoomTimer?.invalidate()
            trailingZoomTimer = Timer.scheduledTimer(withTimeInterval: zoomThrottle.interval,
                                                     repeats: false) { [weak self] _ in
                guard let self, let pending = self.zoomThrottle.fireTrailing(now: Date()) else { return }
                self.controller.setZoom(CGFloat(pending), on: peer)
            }
        }
    }

    /// Both landscapes are the same shape, so the view can't infer which rail
    /// keeps the shutter on the device's home-indicator edge. Falls back to any
    /// connected scene when the view isn't in a window yet (early lifecycle).
    private func syncInterfaceOrientation() {
        let orientation = view.window?.windowScene?.interfaceOrientation
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
                .first
            ?? .portrait
        if viewModel.interfaceOrientation != orientation {
            viewModel.interfaceOrientation = orientation
        }
    }

    deinit {
        for lane in viewModel.lanes { lane.receiver.invalidate() }
        controller.stop()
    }

    /// Wire a freshly created lane's decoder: its frames drive only its own
    /// `FrameDisplayModel`, and its stall/keyframe recovery targets only its
    /// own peer on the controller.
    private func wire(_ lane: CameraLane) {
        let peer = lane.peerID
        lane.receiver.onImage = { [weak lane] image in
            OperationQueue.main.addOperation { lane?.frames.cameraImage = image }
        }
        lane.receiver.onStall = { [weak self] in
            self?.controller.nudgeFrame(for: peer)
        }
        lane.receiver.onKeyframeNeeded = { [weak self] in
            self?.controller.requestKeyframe(for: peer)
        }
        lane.receiver.start()
        // Hand the controller a sink that feeds only this lane's decoder, so it
        // routes frames actor → closure without touching this view controller.
        // `receive` is queue-hopping and thread-safe; the weak capture lets the
        // lane deallocate freely.
        let receiver = lane.receiver
        Task { await controller.setFrameSink(for: peer) { [weak receiver] frame in
            receiver?.receive(frame)
        } }
    }
}

// MARK: - MulticamDisplay

extension MulticamViewController: MulticamDisplay {

    func applyLanes(_ lanes: [MulticamLaneInfo]) {
        let created = viewModel.apply(lanes)
        for lane in created { wire(lane) }
    }

    func applyShutterState(capturing: Bool, recording: Bool, recordingStartTime: Date?) {
        viewModel.isCapturing = capturing
        viewModel.isRecording = recording
        viewModel.recordingStartTime = recordingStartTime
    }

    func applyAvailablePeers(_ peers: [MCPeerID]) {
        viewModel.availablePeers = peers
    }

    func applyRigSettings(_ settings: RigSettingsSnapshot) {
        viewModel.rigSettings = settings
    }

    func showTransientError(_ message: String) {
        viewModel.transientError = .init(message: message)
    }

    func exitMulticam() {
        navigationController?.popViewController(animated: true)
    }
}
