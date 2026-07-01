//
//  WatchSharedTypes.swift
//  RemoteShutter
//
//  FlatBuffer-based serialization for Watch <-> iPhone communication via WCSession.
//  Uses generated types from FlatBufferSchemas.fbs: WatchCommand, WatchCameraState, WatchMessage.
//

import Foundation
import FlatBuffers

// MARK: - Watch -> iPhone Command Encoding

struct WatchCommandEncoder {

    static func encode(action: RemoteShutter_WatchCommandAction,
                       zoomFactor: Double = 0,
                       lensType: RemoteShutter_CameraLensType = .wideangle,
                       timerSeconds: Int32 = 0,
                       mode: RemoteShutter_RecordingModeEnum = .unknown) -> Data {
        var fbb = FlatBufferBuilder()
        let cmd = RemoteShutter_WatchCommand.createWatchCommand(
            &fbb,
            action: action,
            zoomFactor: zoomFactor,
            lensType: lensType,
            timerSeconds: timerSeconds,
            mode: mode
        )
        let msg = RemoteShutter_WatchMessage.createWatchMessage(
            &fbb,
            type: .watchcommandmsg,
            commandOffset: cmd
        )
        fbb.finish(offset: msg)
        return fbb.data
    }

    static func decode(_ data: Data) -> (action: RemoteShutter_WatchCommandAction,
                                         zoomFactor: Double,
                                         lensType: RemoteShutter_CameraLensType,
                                         timerSeconds: Int32,
                                         mode: RemoteShutter_RecordingModeEnum)? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        guard let msg: RemoteShutter_WatchMessage = try? getCheckedRoot(byteBuffer: &buffer) else {
            return nil
        }
        guard msg.type == .watchcommandmsg, let cmd = msg.command else { return nil }
        return (cmd.action, cmd.zoomFactor, cmd.lensType, cmd.timerSeconds, cmd.mode)
    }
}

// MARK: - Camera State Snapshot

/// Plain-value snapshot of everything the Watch UI needs to render.
/// Built on the iPhone, FlatBuffer-encoded by `WatchStateEncoder`, decoded
/// back into the same type on the Watch.
struct WatchCameraStateSnapshot {
    /// Why the phone can or can't capture. `.unknown` means "no signal yet" and
    /// is never treated as ready.
    var readiness: RemoteShutter_WatchReadiness = .unknown
    /// One-shot capture event piggybacked on this push; `.unknown` = no event.
    var event: RemoteShutter_WatchEventType = .unknown
    /// Live self-timer seconds (> 0), or 0 when none is running. Authoritative
    /// in every snapshot — a push without a countdown means no countdown.
    var countdownRemainingSecs: Int32 = 0
    var currentZoomFactor: Double = 1.0
    var minZoomFactor: Double = 1.0
    var maxZoomFactor: Double = 10.0
    var isRecording: Bool = false
    var currentMode: RemoteShutter_RecordingModeEnum = .photo
    var currentLensType: RemoteShutter_CameraLensType = .wideangle
    var availableLensTypes: [RemoteShutter_CameraLensType] = [.wideangle]
    var flashMode: RemoteShutter_FlashMode = .off
    var isTorchEnabled: Bool = false
    var zoomStops: [Double] = [1.0]
    var wideAngleZoomFactor: Double = 1.0
    /// Milliseconds since epoch, stamped at push time. Orders live messages
    /// against (possibly stale) applicationContext deliveries.
    var stateEpochMs: UInt64 = 0
}

extension WatchCameraStateSnapshot {
    var isReady: Bool { readiness == .ready }

    var isFlashEnabled: Bool { flashMode != .off }

    /// Seconds left on an active self-timer, or `nil` when this snapshot carries
    /// no live countdown. A countdown only counts while the phone can capture.
    var activeCountdownSeconds: Int? {
        guard readiness == .ready, countdownRemainingSecs > 0 else { return nil }
        return Int(countdownRemainingSecs)
    }
}

// MARK: - iPhone -> Watch State Encoding

struct WatchStateEncoder {

    static func encode(_ snapshot: WatchCameraStateSnapshot) -> Data {
        var fbb = FlatBufferBuilder()

        let lensVec = fbb.createVector(snapshot.availableLensTypes.map { $0.rawValue })
        let stopsVec = fbb.createVector(snapshot.zoomStops)

        let state = RemoteShutter_WatchCameraState.createWatchCameraState(
            &fbb,
            readiness: snapshot.readiness,
            event: snapshot.event,
            countdownRemainingSecs: snapshot.countdownRemainingSecs,
            currentZoomFactor: snapshot.currentZoomFactor,
            minZoomFactor: snapshot.minZoomFactor,
            maxZoomFactor: snapshot.maxZoomFactor,
            isRecording: snapshot.isRecording,
            currentMode: snapshot.currentMode,
            currentLensType: snapshot.currentLensType,
            availableLensTypesVectorOffset: lensVec,
            flashMode: snapshot.flashMode,
            isTorchEnabled: snapshot.isTorchEnabled,
            zoomStopsVectorOffset: stopsVec,
            wideAngleZoomFactor: snapshot.wideAngleZoomFactor,
            stateEpochMs: snapshot.stateEpochMs
        )
        let msg = RemoteShutter_WatchMessage.createWatchMessage(
            &fbb,
            type: .watchstatemsg,
            stateOffset: state
        )
        fbb.finish(offset: msg)
        return fbb.data
    }

    static func decode(_ data: Data) -> WatchCameraStateSnapshot? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        guard let msg: RemoteShutter_WatchMessage = try? getCheckedRoot(byteBuffer: &buffer) else {
            return nil
        }
        guard msg.type == .watchstatemsg, let state = msg.state else { return nil }

        var lenses: [RemoteShutter_CameraLensType] = []
        for i in 0..<state.availableLensTypesCount {
            if let lens = state.availableLensTypes(at: i) {
                lenses.append(lens)
            }
        }

        var stops: [Double] = []
        for i in 0..<state.zoomStopsCount {
            stops.append(state.zoomStops(at: i))
        }

        return WatchCameraStateSnapshot(
            readiness: state.readiness,
            event: state.event,
            countdownRemainingSecs: state.countdownRemainingSecs,
            currentZoomFactor: state.currentZoomFactor,
            minZoomFactor: state.minZoomFactor,
            maxZoomFactor: state.maxZoomFactor,
            isRecording: state.isRecording,
            currentMode: state.currentMode,
            currentLensType: state.currentLensType,
            availableLensTypes: lenses,
            flashMode: state.flashMode,
            isTorchEnabled: state.isTorchEnabled,
            zoomStops: stops,
            wideAngleZoomFactor: state.wideAngleZoomFactor,
            stateEpochMs: state.stateEpochMs
        )
    }
}

// MARK: - Command Acknowledgment (iPhone -> Watch reply)

/// Transport-level ack: the iPhone decoded the command and dispatched it to the
/// camera state machine (or explains why it couldn't). Capture *completion*
/// still arrives separately as a state push event.
struct WatchAckEncoder {

    static func encode(status: RemoteShutter_WatchAckStatus,
                       action: RemoteShutter_WatchCommandAction = .unknown,
                       detail: String? = nil) -> Data {
        var fbb = FlatBufferBuilder()
        let detailOffset: Offset = detail.map { fbb.create(string: $0) } ?? Offset()
        let ack = RemoteShutter_WatchCommandAck.createWatchCommandAck(
            &fbb,
            status: status,
            action: action,
            detailOffset: detailOffset
        )
        let msg = RemoteShutter_WatchMessage.createWatchMessage(
            &fbb,
            type: .watchcommandackmsg,
            ackOffset: ack
        )
        fbb.finish(offset: msg)
        return fbb.data
    }

    static func decode(_ data: Data) -> (status: RemoteShutter_WatchAckStatus,
                                         action: RemoteShutter_WatchCommandAction,
                                         detail: String?)? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        guard let msg: RemoteShutter_WatchMessage = try? getCheckedRoot(byteBuffer: &buffer) else {
            return nil
        }
        guard msg.type == .watchcommandackmsg, let ack = msg.ack else { return nil }
        return (ack.status, ack.action, ack.detail)
    }
}

// MARK: - Live Preview Frame (iPhone -> Watch)

/// Low-res, heavily-compressed JPEG of the live camera feed so the Watch user can
/// frame the shot. Streamed on the live WCSession channel only (never the durable
/// applicationContext mirror). Entirely separate from the full-quality capture path.
struct WatchPreviewFrameEncoder {

    static func encode(jpeg: Data, epochMs: UInt64) -> Data {
        var fbb = FlatBufferBuilder()
        let jpegVec = fbb.createVector(bytes: jpeg)
        let frame = RemoteShutter_WatchPreviewFrame.createWatchPreviewFrame(
            &fbb,
            jpegVectorOffset: jpegVec,
            epochMs: epochMs
        )
        let msg = RemoteShutter_WatchMessage.createWatchMessage(
            &fbb,
            type: .watchpreviewframemsg,
            previewFrameOffset: frame
        )
        fbb.finish(offset: msg)
        return fbb.data
    }

    static func decode(_ data: Data) -> (jpeg: Data, epochMs: UInt64)? {
        let bytes = [UInt8](data)
        var buffer = ByteBuffer(bytes: bytes)
        guard let msg: RemoteShutter_WatchMessage = try? getCheckedRoot(byteBuffer: &buffer) else {
            return nil
        }
        guard msg.type == .watchpreviewframemsg, let frame = msg.previewFrame else { return nil }
        return (Data(frame.jpeg), frame.epochMs)
    }
}

// MARK: - Zoom Send Throttle

/// Leading + trailing-edge throttle for crown zoom commands. The leading edge
/// keeps zoom responsive; the trailing edge guarantees the *final* crown
/// position is always sent (a plain rate-limit silently dropped it).
struct ZoomSendThrottle {
    let interval: TimeInterval
    private var lastSendTime: Date = .distantPast
    private var pendingValue: Double?

    init(interval: TimeInterval = 0.05) {
        self.interval = interval
    }

    enum Decision: Equatable {
        /// Send this value immediately.
        case sendNow
        /// Hold; arm (or refresh) a trailing timer that flushes via `fireTrailing`.
        case scheduleTrailing
    }

    mutating func update(value: Double, now: Date) -> Decision {
        if now.timeIntervalSince(lastSendTime) >= interval {
            lastSendTime = now
            pendingValue = nil
            return .sendNow
        }
        pendingValue = value
        return .scheduleTrailing
    }

    /// Called when the trailing timer fires. Returns the value to send, or nil
    /// if nothing is pending (it was already flushed or superseded).
    mutating func fireTrailing(now: Date) -> Double? {
        guard let value = pendingValue else { return nil }
        pendingValue = nil
        lastSendTime = now
        return value
    }
}

// MARK: - Application Context Keys

enum WatchContextKeys {
    static let state = "state"
    static let epoch = "epoch"
}

// MARK: - Watch UI Connection Phase

/// What the Watch UI should show, derived from connectivity + camera state.
/// Pure so it can be unit-tested from the iPhone test target.
enum WatchConnectionPhase: Equatable {
    /// WCSession hasn't activated — prompt to open the iPhone app.
    case inactive
    /// Waiting on reachability or the first state push.
    case connecting
    /// iPhone is reachable but its app isn't on the Watch Remote screen.
    case phoneNotInWatchMode
    /// iPhone is in Watch Remote mode but can't capture right now (locked/backgrounded).
    case phoneNotReady
    /// Camera is live — show the controls.
    case ready

    static func derive(isSessionActive: Bool,
                       isPhoneReachable: Bool,
                       readiness: RemoteShutter_WatchReadiness) -> WatchConnectionPhase {
        guard isSessionActive else { return .inactive }
        guard isPhoneReachable else { return .connecting }
        switch readiness {
        case .ready: return .ready
        case .phonebackgrounded: return .phoneNotReady
        case .notinwatchmode: return .phoneNotInWatchMode
        case .unknown: return .connecting
        }
    }
}

// MARK: - Convenience mappings

extension RemoteShutter_CameraLensType {
    var displayName: String {
        switch self {
        case .wideangle: return "1x"
        case .ultrawide: return "0.5"
        case .telephoto: return "2x"
        case .dualcamera: return "Dual"
        }
    }
}

extension RemoteShutter_RecordingModeEnum {
    var isPhoto: Bool { self == .photo || self == .unknown }
    var isVideo: Bool { self == .video }
}
