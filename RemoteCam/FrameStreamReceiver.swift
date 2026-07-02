//
//  FrameStreamReceiver.swift
//  RemoteShutter
//
//  Monitor-side streaming pipeline: decodes incoming frames off the actor
//  mailbox on a dedicated queue, watches for stalls (no frame for
//  stallTimeout -> onStall so the state machine re-requests one), recovers on
//  foreground, and logs sequence gaps + per-second stream stats.
//
//  UIImage(data:) sniffs the container from magic bytes, so JPEG and HEIC
//  frames (and frames from legacy peers) all decode through the same path.
//

import UIKit

final class FrameStreamReceiver {

    /// Decoded frame ready for display. Called on the decode queue — hop to
    /// main before touching UI.
    var onImage: ((UIImage) -> Void)?
    /// No frame has arrived for `config.stallTimeout`. Called on the decode
    /// queue, at most once per timeout while the stall persists.
    var onStall: (() -> Void)?

    private let config: StreamingConfig
    private let now: () -> TimeInterval
    let decodeQueue = DispatchQueue(label: "frame stream decode queue", qos: .userInteractive)

    private var timer: DispatchSourceTimer?
    private var foregroundObserver: NSObjectProtocol?

    // State below is confined to decodeQueue.
    private var lastFrameAt: TimeInterval = 0
    private var lastStallReportAt: TimeInterval = 0
    private var lastSequenceNumber: UInt32 = 0
    private(set) var sequenceGapCount = 0
    private var statsFrames = 0
    private var statsBytes = 0
    private var statsWindowStart: TimeInterval = 0

    init(config: StreamingConfig = .default,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
         notificationCenter: NotificationCenter = .default) {
        self.config = config
        self.now = now
        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.decodeQueue.async {
                // iOS may have frozen both peers while backgrounded; the
                // in-flight ping-pong message is likely gone. Re-request
                // immediately instead of waiting for the stall watchdog.
                StreamLog.lifecycle.info("monitor foregrounded — re-requesting frame")
                self.resetStallClock()
                self.onStall?()
            }
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        timer?.cancel()
    }

    /// Arms the stall watchdog. Call once the monitor UI is up.
    func start() {
        decodeQueue.async { self.resetStallClock() }
        let timer = DispatchSource.makeTimerSource(queue: decodeQueue)
        timer.schedule(deadline: .now() + config.stallCheckInterval,
                       repeating: config.stallCheckInterval)
        timer.setEventHandler { [weak self] in self?.checkForStall() }
        timer.resume()
        self.timer = timer
    }

    func invalidate() {
        timer?.cancel()
        timer = nil
    }

    /// Thread-safe entry point: decode + display a received frame.
    func receive(_ frame: RemoteCmd.OnFrame) {
        decodeQueue.async { self.process(frame) }
    }

    // MARK: - decodeQueue

    private func process(_ frame: RemoteCmd.OnFrame) {
        let time = now()
        lastFrameAt = time
        trackSequence(frame)
        trackStats(frame, at: time)

        guard let image = UIImage(data: frame.data) else {
            StreamLog.decode.error(
                "undecodable frame seq=\(frame.sequenceNumber) codec=\(String(describing: frame.codec)) bytes=\(frame.data.count)")
            return
        }
        onImage?(image)
    }

    /// Sequence gaps are expected occasionally (frames ride .unreliable); for
    /// stills the next frame self-heals, so gaps are a debug signal only.
    private func trackSequence(_ frame: RemoteCmd.OnFrame) {
        defer { lastSequenceNumber = frame.sequenceNumber }
        guard frame.sequenceNumber != 0, lastSequenceNumber != 0,
              frame.sequenceNumber > lastSequenceNumber &+ 1 else { return }
        sequenceGapCount += 1
        StreamLog.decode.debug("sequence gap: \(self.lastSequenceNumber) -> \(frame.sequenceNumber)")
    }

    private func trackStats(_ frame: RemoteCmd.OnFrame, at time: TimeInterval) {
        if statsWindowStart == 0 { statsWindowStart = time }
        statsFrames += 1
        statsBytes += frame.data.count
        let elapsed = time - statsWindowStart
        guard elapsed >= 1.0 else { return }
        let fps = Double(statsFrames) / elapsed
        let kbPerFrame = Double(statsBytes) / Double(statsFrames) / 1024.0
        StreamLog.decode.debug(
            """
            stream stats: \(fps, format: .fixed(precision: 1))fps \
            \(kbPerFrame, format: .fixed(precision: 1))KB/frame codec=\(String(describing: frame.codec))
            """)
        statsWindowStart = time
        statsFrames = 0
        statsBytes = 0
    }

    func checkForStall() {
        let time = now()
        guard time - lastFrameAt > config.stallTimeout,
              time - lastStallReportAt > config.stallTimeout else { return }
        lastStallReportAt = time
        StreamLog.transport.info(
            "no frame for \(time - self.lastFrameAt, format: .fixed(precision: 1))s — raising StreamStalled")
        onStall?()
    }

    private func resetStallClock() {
        lastFrameAt = now()
        lastStallReportAt = 0
    }
}
