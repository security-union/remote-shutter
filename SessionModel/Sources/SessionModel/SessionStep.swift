import Correcto

// The session's logic. One function, no side effects, every role.
//
// Read it as four groups: pairing, the camera's photo path, the camera's video
// path, and the remote's view of both. Everything not listed is ignored, which
// is what makes a slice a slice rather than a half-written app.
//
// A camera holds one remote. A remote holds as many cameras as the person
// connected, so one shutter tap is a command to each of them and the take is
// outstanding until the last one reports. That is the only difference between
// the one-camera case and the rig.

// MARK: - The machine

/// The model. `SessionCoordinator` is meant to run this; the checker explores
/// it; `session-runner` lets a person drive it by hand.
public enum SessionDevice: Model {
    public static func step(
        _ state: DeviceState, _ event: SessionEvent
    ) -> Step<DeviceState, SessionEffect> {
        sessionStep(state, event)
    }
}

// swiftlint:disable:next cyclomatic_complexity function_body_length
public func sessionStep(
    _ state: DeviceState, _ event: SessionEvent
) -> Step<DeviceState, SessionEffect> {
    var next = state

    switch (state.phase, event) {

    // MARK: Pairing

    // The role picker, which happens before anything is paired: the camera
    // advertises and the monitor browses. This is `DeviceScannerViewController
    // (role:)` in the app, and it is why two devices claiming the camera at
    // once is not a race the app can have. Modelling it as a post-pairing
    // claim invented one, and the checker found it inside a minute.
    case (.scanning, .becomeCamera):
        next.role = .camera
        return Step(next)

    // Only a device still looking for a camera browses. A camera advertises.
    case let (.scanning, .invite(peer)):
        guard state.role != .camera else { return .ignore(state) }
        return Step(state, [.invite(peer)])

    // A remote keeps browsing with cameras already connected, which is how the
    // second and third camera join a take.
    case let (.connected, .invite(peer)):
        guard state.role != .camera, !state.peers.contains(peer) else { return .ignore(state) }
        return Step(state, [.invite(peer)])

    case let (.scanning, .peerConnected(peer)):
        next.add(peer: peer)
        guard state.role == .camera else {
            next.phase = .connected
            return Step(next)
        }
        // A camera announces itself on the way in, which is how the other side
        // learns it is the remote.
        next.phase = .camera
        return Step(next, [.send(.peerBecameCamera, to: peer)])

    case let (.connected, .peerConnected(peer)):
        next.add(peer: peer)
        return Step(next)

    // A camera is already serving one remote and does not take another.
    case (.camera, .peerConnected), (.cameraTakingPic, .peerConnected),
         (.cameraRecordingVideo, .peerConnected), (.cameraTransmittingVideo, .peerConnected):
        return .ignore(state)

    case (.connected, .wire(.peerBecameCamera, _)):
        next.role = .remote
        return Step(next)

    // MARK: Leaving

    case (_, .leaveSession):
        guard state.isPaired else { return .ignore(state) }
        let goodbyes = state.peers.map { SessionEffect.send(.endSession, to: $0) }
        return Step(unpaired(state), goodbyes + takeAlertDown(state))

    // A peer said goodbye on purpose. This is the door the orphaned alert used
    // to leave by without taking its modal with it.
    case let (_, .wire(.endSession, from)):
        return Step(dropping(from, in: state), takeAlertDown(state, losing: from))

    // A send that died on a live link. A camera with no peer left drops the
    // message and holds its post instead, which is the role split in
    // `sendOrGoToScanning`.
    case let (_, .sendFailed(peer)):
        if state.role == .camera, !state.peers.contains(peer) { return .ignore(state) }
        return Step(dropping(peer, in: state), takeAlertDown(state, losing: peer))

    // The link went away by itself. A camera is a server: it keeps the role and
    // whatever capture is in flight, and settles when the hardware answers.
    case let (_, .peerLost(peer)):
        next.remove(peer: peer)
        if state.role == .camera {
            next.believesRecording = false
            return Step(next)
        }
        return Step(dropping(peer, in: state), takeAlertDown(state, losing: peer))

    // MARK: The camera's photo path

    case let (.camera, .wire(.takePic(sendMedia), _)):
        return startCapture(next, sendMediaToPeer: sendMedia)

    // The shutter on the camera device itself, which is how a solo take works.
    case let (.camera, .pressShutter(sendMedia)):
        return startCapture(next, sendMediaToPeer: sendMedia && state.isPaired)

    case let (.cameraTakingPic(sendMedia, _), .pictureCaptured):
        next.phase = .camera
        next.alertUp = false
        next.captureOutstanding = false
        var effects: [SessionEffect] = [.dismissAlert, .saveToLibrary]
        for peer in state.peers {
            effects.append(.send(.takePicAck, to: peer))
            effects.append(.send(.takePicResp(failed: false, carriesMedia: sendMedia), to: peer))
        }
        return Step(next, effects)

    case (.cameraTakingPic, .captureFailed):
        next.phase = .camera
        next.alertUp = false
        next.captureOutstanding = false
        return Step(next, [.dismissAlert] + state.peers.map {
            .send(.takePicResp(failed: true, carriesMedia: false), to: $0)
        })

    case let (.cameraTakingPic(_, generation), .stateTimeout(fired)):
        // The generation guard the app has had for years, and which works.
        guard fired == generation else { return .ignore(state) }
        next.phase = .camera
        next.alertUp = false
        // The hardware is still working. The capture stays outstanding until it
        // answers, and the answer is still the person's picture.
        return Step(next, [.dismissAlert] + state.peers.map {
            .send(.takePicResp(failed: true, carriesMedia: false), to: $0)
        })

    // MARK: The camera's video path

    case (.camera, .wire(.startRecording, _)), (.camera, .pressRecord):
        next.phase = .cameraRecordingVideo
        return Step(next, [.startRecording]
                    + state.peers.map { .send(.startRecordingAck, to: $0) })

    case (.cameraRecordingVideo, .recordingFailed):
        next.phase = .camera
        return Step(next, state.peers.map { .send(.stopRecordingResp(failed: true), to: $0) })

    case let (.cameraRecordingVideo, .wire(.stopRecording(sendMedia), _)):
        return stopRecording(next, sendMediaToPeer: sendMedia && state.isPaired)

    case let (.cameraRecordingVideo, .pressStop(sendMedia)):
        return stopRecording(next, sendMediaToPeer: sendMedia && state.isPaired)

    // The transfer is ready to go out. The camera stays put: its own send
    // finishing is not what releases it.
    case (.cameraTransmittingVideo, .clipReady):
        guard let peer = state.peer else {
            // Nobody to send it to, so there is nothing left to wait for.
            next.phase = .camera
            return Step(next)
        }
        return Step(next, [.send(.videoArrived, to: peer)])

    case (.cameraTransmittingVideo, .wire(.videoReceivedEcho, _)):
        next.phase = .camera
        return Step(next, state.peers.map { .send(.stopRecordingResp(failed: false), to: $0) })

    // MARK: The remote's side

    // One tap, every camera. This is the whole of multicam capture: the take is
    // outstanding until the last camera reports, which is what the terminal
    // rule is about.
    case let (.connected, .pressShutter(sendMedia)):
        guard state.role == .remote, state.isPaired else { return .ignore(state) }
        next.capturesAwaited = state.peers.count
        next.timeoutGeneration += 1
        return Step(next, state.peers.map {
            .send(.takePic(sendMediaToPeer: sendMedia), to: $0)
        } + [.armTimeout(generation: next.timeoutGeneration)])

    case (.connected, .wire(.takePicAck, _)):
        // Progress, not an answer. Nothing to decide.
        return .ignore(state)

    case let (.connected, .wire(.takePicResp(failed, carriesMedia), _)):
        next.capturesAwaited = max(0, state.capturesAwaited - 1)
        if !failed, carriesMedia { return Step(next, [.saveToLibrary]) }
        return Step(next)

    case (.connected, .pressRecord):
        guard state.role == .remote, state.isPaired else { return .ignore(state) }
        next.recordingsAwaited = state.peers.count
        next.timeoutGeneration += 1
        return Step(next, state.peers.map { .send(.startRecording, to: $0) }
                    + [.armTimeout(generation: next.timeoutGeneration)])

    case (.connected, .wire(.startRecordingAck, _)):
        next.recordingsAwaited = max(0, state.recordingsAwaited - 1)
        next.believesRecording = true
        return Step(next)

    case let (.connected, .pressStop(sendMedia)):
        guard state.role == .remote, state.believesRecording,
              state.isPaired else { return .ignore(state) }
        next.recordingsAwaited = state.peers.count
        next.timeoutGeneration += 1
        return Step(next, state.peers.map {
            .send(.stopRecording(sendMediaToPeer: sendMedia), to: $0)
        } + [.armTimeout(generation: next.timeoutGeneration)])

    case (.connected, .wire(.stopRecordingResp, _)):
        next.recordingsAwaited = max(0, state.recordingsAwaited - 1)
        if next.recordingsAwaited == 0 { next.believesRecording = false }
        return Step(next)

    case let (.connected, .wire(.videoArrived, from)):
        // Save it and send the echo the camera is waiting for. Forgetting this
        // echo is what wedges the camera in `.cameraTransmittingVideo`.
        return Step(next, [.saveClip, .send(.videoReceivedEcho, to: from)])

    case let (.connected, .stateTimeout(fired)):
        guard fired == state.timeoutGeneration else { return .ignore(state) }
        next.capturesAwaited = 0
        next.recordingsAwaited = 0
        return Step(next)

    // MARK: A capture that answers late, in any phase

    // The watchdog fired, or the session went away under it. The bytes exist
    // and the person asked for them, so they are saved wherever we are. Naming
    // the phases instead of saying "any" is what lost a photo through the
    // teardown door.
    case (_, .pictureCaptured):
        guard state.captureOutstanding else { return .ignore(state) }
        next.captureOutstanding = false
        return Step(next, [.saveToLibrary])

    case (_, .captureFailed):
        guard state.captureOutstanding else { return .ignore(state) }
        next.captureOutstanding = false
        return Step(next)

    default:
        return .ignore(state)
    }
}

// MARK: - The small shared pieces

/// Alone again, with nothing held. `popToScanning` in the app, minus the parts
/// that are effects.
private func unpaired(_ state: DeviceState) -> DeviceState {
    var next = state
    next.phase = .scanning
    next.role = .undecided
    next.peers = []
    next.alertUp = false
    next.capturesAwaited = 0
    next.recordingsAwaited = 0
    next.believesRecording = false
    // `captureOutstanding` is deliberately kept. The session is over; the
    // capture is not, and the hardware still owes an answer.
    return next
}

/// Losing one peer. A remote with cameras left carries on with them, which is
/// the difference between one camera dropping out of a take and the session
/// ending.
private func dropping(_ peer: DeviceRef, in state: DeviceState) -> DeviceState {
    var next = state
    next.remove(peer: peer)
    guard next.peers.isEmpty else {
        next.capturesAwaited = max(0, next.capturesAwaited - 1)
        next.recordingsAwaited = max(0, next.recordingsAwaited - 1)
        return next
    }
    return unpaired(state)
}

/// Leaving a capture takes its alert with it, whichever door it leaves by. A
/// camera only abandons the capture when the peer it was serving is the one
/// that went away.
private func takeAlertDown(_ state: DeviceState, losing peer: DeviceRef? = nil) -> [SessionEffect] {
    guard state.alertUp else { return [] }
    if let peer, state.role == .camera, !state.peers.contains(peer) { return [] }
    return [.dismissAlert]
}

private func startCapture(
    _ state: DeviceState, sendMediaToPeer: Bool
) -> Step<DeviceState, SessionEffect> {
    var next = state
    next.timeoutGeneration += 1
    next.phase = .cameraTakingPic(
        sendMediaToPeer: sendMediaToPeer, generation: next.timeoutGeneration)
    next.alertUp = true
    next.captureOutstanding = true
    return Step(next, [
        .armTimeout(generation: next.timeoutGeneration),
        .showAlert(.takingPicture),
        .takePicture(sendToPeer: sendMediaToPeer)
    ])
}

private func stopRecording(
    _ state: DeviceState, sendMediaToPeer: Bool
) -> Step<DeviceState, SessionEffect> {
    var next = state
    guard sendMediaToPeer else {
        next.phase = .camera
        return Step(next, [.stopRecording]
                    + state.peers.map { .send(.stopRecordingResp(failed: false), to: $0) })
    }
    // Send Media is on, so the camera owes the peer a clip. It holds
    // `.cameraTransmittingVideo`, where capture commands are refused, and
    // deliberately sends no stop response until the echo comes back.
    next.phase = .cameraTransmittingVideo
    return Step(next, [.stopRecording])
}
