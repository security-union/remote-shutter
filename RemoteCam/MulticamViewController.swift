//
//  MulticamViewController.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import MPCCompat
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

        let multicamView = MulticamView(
            viewModel: viewModel,
            onFocusLane: { [weak self] lane in
                guard let self else { return }
                Task { await self.controller.setFocusedPeer(lane.peerID) }
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
            Task { await self?.controller.nudgeFrame(for: peer) }
        }
        lane.receiver.onKeyframeNeeded = { [weak self] in
            Task { await self?.controller.requestKeyframe(for: peer) }
        }
        lane.receiver.start()
    }
}

// MARK: - MulticamDisplay

extension MulticamViewController: MulticamDisplay {

    func applyLanes(_ lanes: [MulticamLaneInfo]) {
        let created = viewModel.apply(lanes)
        for lane in created { wire(lane) }
    }

    func receiveFrame(_ frame: RemoteCmd.OnFrame) {
        // Route to exactly the source lane's decoder; a frame for camera B
        // never touches camera A's tile.
        viewModel.lane(for: frame.peerId)?.receiver.receive(frame)
    }

    func exitMulticam() {
        navigationController?.popViewController(animated: true)
    }
}
