import AVFoundation

/// Manages torch blink/strobe effects during timer countdowns.
/// Single blink for normal ticks (>2s), continuous strobe for final 2 seconds.
final class CameraCountdownTorch {

    private var isBlinking = false
    private var blinkGeneration = 0
    private var strobeTimer: DispatchSourceTimer?
    private var strobeOn = false

    // MARK: - Public API

    /// Single 150ms flash for normal countdown ticks.
    func blinkOnce(device: AVCaptureDevice?) {
        stopStrobe()
        guard !isBlinking else { return }
        guard let device = device, device.hasTorch else { return }
        isBlinking = true
        blinkGeneration += 1
        let gen = blinkGeneration
        setTorch(.on, device: device)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.blinkGeneration == gen else { return }
            self.isBlinking = false
            self.setTorch(.off, device: device)
        }
    }

    /// Continuous rapid strobe (~8Hz) for the final 2 seconds.
    func startStrobe(device: AVCaptureDevice?) {
        stopStrobe()
        blinkGeneration += 1
        guard let device = device, device.hasTorch else { return }
        isBlinking = true
        strobeOn = false

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.12)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.strobeOn.toggle()
            self.setTorch(self.strobeOn ? .on : .off, device: device)
        }
        timer.resume()
        strobeTimer = timer
    }

    /// Stops all blink/strobe activity. Deliberately leaves the torch in whatever state
    /// the strobe last set it to — the caller decides the final torch state (e.g. restoring
    /// the user's torch preference), so a user-enabled torch survives a timer countdown.
    func stop(device: AVCaptureDevice?) {
        stopStrobe()
        isBlinking = false
    }

    // MARK: - Private

    private func stopStrobe() {
        strobeTimer?.cancel()
        strobeTimer = nil
        strobeOn = false
        isBlinking = false
    }

    private func setTorch(_ mode: AVCaptureDevice.TorchMode, device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {}
    }
}
