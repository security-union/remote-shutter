//
//  WatchCameraViewModel.swift
//  RemoteShutterWatch
//
//  ObservableObject for the Watch remote control UI.
//  Receives FlatBuffer-decoded state from WatchSessionDelegate.
//

import Foundation
import SwiftUI
import FlatBuffers

class WatchCameraViewModel: ObservableObject {

    // MARK: - Connection State

    @Published var isSessionActive = false
    @Published var isPhoneReachable = false

    var isConnected: Bool {
        isSessionActive && isPhoneReachable && isReady
    }

    // MARK: - Camera State

    @Published var isReady = false
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

    // MARK: - Timer Setting (persisted)

    @Published var timerSeconds: Int = UserDefaults.standard.integer(forKey: "watchTimerSeconds") {
        didSet { UserDefaults.standard.set(timerSeconds, forKey: "watchTimerSeconds") }
    }

    static let timerOptions = [0, 2, 5, 10, 20]

    // MARK: - Events

    @Published var lastEvent: String?
    @Published var showEventConfirmation = false

    // MARK: - Preview

    @Published var previewImageData: Data?

    // MARK: - Digital Crown

    @Published var crownZoomValue: Double = 1.0
    /// Raw 0-1 value from the Digital Crown, mapped to zoom via zoomFromCrown()
    @Published var crownRawValue: Double = 0.0
    private var lastZoomSendTime: Date = .distantPast
    /// When the user last turned the crown — suppresses incoming state overwriting the crown
    private var lastCrownInteraction: Date = .distantPast

    /// Max display zoom relative to wide angle (e.g. 5x = 5 times the wide angle factor)
    private let maxDisplayZoomMultiplier: Double = 5.0

    /// Clamped max zoom for UI controls
    var clampedMaxZoom: Double {
        min(maxZoomFactor, wideAngleZoomFactor * maxDisplayZoomMultiplier)
    }

    /// Returns true if enough time has passed to send another zoom command
    func shouldSendZoom() -> Bool {
        let now = Date()
        lastCrownInteraction = now
        if now.timeIntervalSince(lastZoomSendTime) >= 0.05 {
            lastZoomSendTime = now
            return true
        }
        return false
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

    func update(from state: WatchStateEncoder.DecodedState) {
        isReady = state.isReady
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

        // Handle events
        if let event = state.lastEvent {
            lastEvent = event
            showEventConfirmation = true
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

    // MARK: - Preview Frame

    func updatePreviewFrame(_ data: Data) {
        previewImageData = data
    }
}
