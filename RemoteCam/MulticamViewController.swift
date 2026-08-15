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
                guard let self, !self.viewModel.isRecording else { return }
                self.viewModel.mode = self.viewModel.mode == .photo ? .video : .photo
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
            onRetryCollection: { [weak self] lane in self?.controller.retryCollection(for: lane.peerID) },
            onToggleFocusedCamera: { [weak self] in self?.controller.toggleFocusedCamera() })
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
                showPaywall()
            } else {
                viewModel.showingAddCamera = true
            }
        }
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

    private func syncInterfaceOrientation() {
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
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

    func applyShutterState(capturing: Bool, recording: Bool) {
        viewModel.isCapturing = capturing
        viewModel.isRecording = recording
    }

    func applyAvailablePeers(_ peers: [MCPeerID]) {
        viewModel.availablePeers = peers
    }

    func applyRigSettings(_ settings: RigSettingsSnapshot) {
        viewModel.rigSettings = settings
    }

    func exitMulticam() {
        navigationController?.popViewController(animated: true)
    }
}
