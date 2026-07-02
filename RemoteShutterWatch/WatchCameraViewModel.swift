//
//  WatchCameraViewModel.swift
//  RemoteShutterWatch
//
//  ObservableObject for the Watch remote control UI.
//  Receives FlatBuffer-decoded state from WatchSessionDelegate.
//

import Foundation
import UIKit
import SwiftUI
import WatchKit
import FlatBuffers

class WatchCameraViewModel: ObservableObject {

    // MARK: - Connection State

    @Published var isSessionActive = false
    @Published var isPhoneReachable = false
    /// Latest readiness signal. Snapshot pushes set it; a NotInWatchMode ack
    /// overrides it (the phone answered but left the Watch Remote screen).
    @Published var readiness: RemoteShutter_WatchReadiness = .unknown

    var isConnected: Bool {
        isSessionActive && isPhoneReachable && isReady
    }

    /// What the UI should show. Controls only render in `.ready` — a merely
    /// reachable phone whose app isn't in Watch Remote mode must not present
    /// dead buttons.
    var phase: WatchConnectionPhase {
        WatchConnectionPhase.derive(
            isSessionActive: isSessionActive,
            isPhoneReachable: isPhoneReachable,
            readiness: readiness
        )
    }

    // MARK: - Camera State

    var isReady: Bool { readiness == .ready }
    @Published var currentZoomFactor: Double = 1.0
    @Published var minZoomFactor: Double = 1.0
    @Published var maxZoomFactor: Double = 10.0
    @Published var isRecording = false
    @Published var currentMode: RemoteShutter_RecordingModeEnum = .photo
    @Published var currentLensType: RemoteShutter_CameraLensType = .wideangle
    @Published var availableLensTypes: [RemoteShutter_CameraLensType] = [.wideangle]
    @Published var isFlashEnabled = false
    @Published var isTorchEnabled = false
    @Published var zoomStops: [Double] = [1.0]
    @Published var wideAngleZoomFactor: Double = 1.0

    // MARK: - Live Preview

    /// Latest preview frame, rendered behind the controls. `nil` falls back to the
    /// solid background (e.g. before the first frame, or once disconnected).
    @Published var previewImage: UIImage?
    /// Epoch of the newest preview applied — drops out-of-order frame deliveries.
    private var lastPreviewEpochMs: UInt64 = 0

    /// Applies a freshly-decoded preview frame, ignoring stale (out-of-order) ones.
    func updatePreview(image: UIImage, epochMs: UInt64) {
        if epochMs != 0 && lastPreviewEpochMs != 0 && epochMs <= lastPreviewEpochMs { return }
        lastPreviewEpochMs = max(lastPreviewEpochMs, epochMs)
        previewImage = image
    }

    /// Drops the preview so a stale frame can't linger over a not-connected screen.
    private func clearPreview() {
        previewImage = nil
        lastPreviewEpochMs = 0
    }

    // MARK: - Timer Setting (persisted)

    @Published var timerSeconds: Int = UserDefaults.standard.integer(forKey: "watchTimerSeconds") {
        didSet { UserDefaults.standard.set(timerSeconds, forKey: "watchTimerSeconds") }
    }

    static let timerOptions = [0, 2, 5, 10, 20]

    // MARK: - Events

    @Published var lastEvent: RemoteShutter_WatchEventType?
    @Published var showEventConfirmation = false

    /// Seconds left on an active self-timer, or `nil` when none is counting. Shown
    /// as a steady, cancelable overlay rather than flashing per-tick confirmations.
    @Published var countdownRemaining: Int?

    /// User tapped Cancel: drop the countdown immediately (optimistic) and tell the
    /// phone to abort the pending capture.
    func cancelTimer(send: () -> Void) {
        countdownRemaining = nil
        WKInterfaceDevice.current().play(.click)
        send()
    }

    // MARK: - Digital Crown

    @Published var crownZoomValue: Double = 1.0
    /// Raw 0-1 value from the Digital Crown, mapped to zoom via zoomFromCrown()
    @Published var crownRawValue: Double = 0.0
    /// When the user last turned the crown — suppresses incoming state overwriting the crown
    private var lastCrownInteraction: Date = .distantPast

    private var zoomThrottle = ZoomSendThrottle()
    private var trailingZoomTimer: Timer?

    /// Max display zoom relative to wide angle (e.g. 5x = 5 times the wide angle factor)
    private let maxDisplayZoomMultiplier: Double = 5.0

    /// Clamped max zoom for UI controls
    var clampedMaxZoom: Double {
        min(maxZoomFactor, wideAngleZoomFactor * maxDisplayZoomMultiplier)
    }

    /// Single entry point for user-driven zoom: throttled to 20Hz with a
    /// trailing-edge flush so the final crown position is always delivered.
    func zoomChanged(_ zoom: Double, send: @escaping (Double) -> Void) {
        lastCrownInteraction = Date()
        crownZoomValue = zoom

        switch zoomThrottle.update(value: zoom, now: Date()) {
        case .sendNow:
            send(zoom)
        case .scheduleTrailing:
            trailingZoomTimer?.invalidate()
            trailingZoomTimer = Timer.scheduledTimer(withTimeInterval: zoomThrottle.interval, repeats: false) { [weak self] _ in
                guard let self, let value = self.zoomThrottle.fireTrailing(now: Date()) else { return }
                send(value)
            }
        }
    }

    /// True if the user is actively turning the crown (suppress incoming state sync)
    var isCrownActive: Bool {
        Date().timeIntervalSince(lastCrownInteraction) < 1.0
    }

    /// Maps normalized 0-100 crown value to actual zoom factor
    func zoomFromCrown(_ raw: Double) -> Double {
        let minZ = minZoomFactor
        let maxZ = clampedMaxZoom
        let t = raw / 50.0 // normalize to 0-1
        return minZ + t * (maxZ - minZ)
    }

    /// Maps actual zoom factor back to 0-100 crown value
    func crownFromZoom(_ zoom: Double) -> Double {
        let minZ = minZoomFactor
        let maxZ = clampedMaxZoom
        guard maxZ > minZ else { return 0 }
        return ((zoom - minZ) / (maxZ - minZ)) * 50.0
    }

    // MARK: - Computed Properties

    var displayZoom: String {
        let display = currentZoomFactor / wideAngleZoomFactor
        if display < 1.0 {
            return String(format: "%.1fx", display)
        } else if display == floor(display) {
            return String(format: "%.0fx", display)
        } else {
            return String(format: "%.1fx", display)
        }
    }

    var isPhotoMode: Bool { currentMode.isPhoto }
    var isVideoMode: Bool { currentMode.isVideo }

    // MARK: - Update from FlatBuffer-decoded State

    /// Epoch of the newest state applied — rejects stale applicationContext
    /// deliveries (and duplicate live/context pairs) out of order.
    private var lastStateEpochMs: UInt64 = 0

    func update(from state: WatchCameraStateSnapshot) {
        if state.stateEpochMs != 0 && lastStateEpochMs != 0 && state.stateEpochMs <= lastStateEpochMs {
            return
        }
        lastStateEpochMs = max(lastStateEpochMs, state.stateEpochMs)

        readiness = state.readiness
        if !state.isReady {
            clearPreview()
        }
        currentZoomFactor = state.currentZoomFactor
        minZoomFactor = state.minZoomFactor
        maxZoomFactor = state.maxZoomFactor
        isRecording = state.isRecording
        currentMode = state.currentMode
        currentLensType = state.currentLensType
        availableLensTypes = state.availableLensTypes
        isFlashEnabled = state.isFlashEnabled
        isTorchEnabled = state.isTorchEnabled
        zoomStops = state.zoomStops
        wideAngleZoomFactor = state.wideAngleZoomFactor

        // The snapshot is authoritative for the self-timer: no countdown in the
        // snapshot means no countdown is running. Applying this on every state is
        // what unsticks a stale overlay after missed pushes (locked phone/watch
        // races) — and any interleaved push carries the live value too.
        countdownRemaining = state.activeCountdownSeconds

        // A live countdown gets a steady, cancelable overlay with a per-tick
        // click; a one-shot event flashes a 2s confirmation with its haptic.
        if countdownRemaining != nil {
            WKInterfaceDevice.current().play(.click)
        } else if state.event != .unknown {
            lastEvent = state.event
            showEventConfirmation = true
            playHaptic(for: state.event)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.showEventConfirmation = false
            }
        }

        // Only sync crown if user isn't actively turning it
        if !isCrownActive {
            crownZoomValue = currentZoomFactor
            crownRawValue = crownFromZoom(currentZoomFactor)
        }
    }

    // MARK: - Mode Switching

    /// Switches photo/video optimistically — the UI flips immediately and the
    /// next state push from the phone confirms (or corrects) it. Ignored while
    /// recording; the phone would reject it with `busyRecording` anyway.
    func selectMode(_ mode: RemoteShutter_RecordingModeEnum,
                    send: (RemoteShutter_RecordingModeEnum) -> Void) {
        guard !isRecording, currentMode != mode else { return }
        currentMode = mode
        WKInterfaceDevice.current().play(.click)
        send(mode)
    }

    // MARK: - Local Events (not from a state push)

    /// A command failed to reach the phone (or the phone refused it) — make the
    /// failure tangible instead of silently doing nothing.
    func noteSendFailure() {
        lastEvent = .sendfailed
        showEventConfirmation = true
        WKInterfaceDevice.current().play(.failure)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.showEventConfirmation = false
        }
    }

    func notePhoneNotInWatchMode() {
        readiness = .notinwatchmode
        WKInterfaceDevice.current().play(.failure)
    }

    // MARK: - Haptic Feedback

    private func playHaptic(for event: RemoteShutter_WatchEventType) {
        let type: WKHapticType
        switch event {
        case .phototaken:
            type = .success
        case .recordingstarted:
            type = .start
        case .recordingstopped:
            type = .stop
        case .photoerror, .microphonedenied, .recordingfailed, .sendfailed:
            type = .failure
        case .busy, .busyrecording:
            type = .retry
        case .unknown:
            type = .notification
        }
        WKInterfaceDevice.current().play(type)
    }
}
