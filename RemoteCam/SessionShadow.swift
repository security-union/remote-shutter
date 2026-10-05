//
//  SessionShadow.swift
//  RemoteShutter
//
//  The session model running beside the coordinator and deciding nothing. See
//  SessionModel/README.md for how to read what it reports, and
//  Docs/correcto-integration.md for where this is going.
//
//  This is phase zero of the integration. The coordinator is still entirely in
//  charge: the shadow observes what already happened, compares it to what the
//  model would have predicted, and checks the rules against reality. It
//  performs no effects and nothing downstream reads it, so it cannot change
//  what the app does.
//

import Foundation
import MPCCompat
import SessionModel
import Stormo

extension SessionCoordinator {

    /// Build the model's state from the coordinator's own. The phase needs no
    /// mapping, because both share one `SessionState`; what is left is the
    /// handful of flags the enum does not carry. Every one of them has to be
    /// derivable from what the app already keeps, or the shadow cannot
    /// resynchronise it.
    func projectDeviceState() -> DeviceState {
        DeviceState(
            phase: state,
            role: projectedRole,
            // One peer, because this coordinator holds one `link`. A remote
            // driving several cameras is `MulticamController`, a second machine
            // this slice does not own, and the model can hold several peers for
            // the day it does.
            peers: currentPeer.map { [DeviceRef($0.displayName)] } ?? [],
            alertUp: hasCameraAlert,
            captureOutstanding: captureOutstanding,
            // The remote's half of the protocol lives in that second machine
            // too. On a device running the camera role these are zero by
            // construction, and the ownership gate below is what keeps the
            // shadow from claiming otherwise.
            capturesAwaited: 0,
            recordingsAwaited: 0,
            believesRecording: false,
            timeoutGeneration: timeoutGeneration)
    }

    /// The role, from the phase. `isCameraRole` is the app's own answer to the
    /// same question, which is why there is nothing to keep in sync.
    private var projectedRole: Role {
        if state.isCameraRole { return .camera }
        return currentPeer == nil ? .undecided : .remote
    }

    /// Whether the model owns the decisions in this phase.
    ///
    /// Ownership is by phase rather than by message type, and that is not a
    /// detail. `popToScanning` stops at the lobby floor for the lobby and Watch
    /// phases, so a model that owned `EndSession` everywhere would decide
    /// wrongly outside this slice. The phases below are the ones the model has
    /// been checked over.
    var modelOwnsPhase: Bool {
        switch state {
        case .scanning, .connected, .camera, .cameraTakingPic,
             .cameraRecordingVideo, .cameraTransmittingVideo:
            return true
        case .waitingForLobby, .lobby, .reconnecting, .watchCamera,
             .watchCameraTakingPic, .watchCameraStartingVideo, .watchCameraRecordingVideo:
            return false
        }
    }

    /// Map a coordinator message to a model event, or nil when the model does
    /// not own it here. Unowned messages still reach the shadow so its state
    /// keeps up with reality.
    func sessionEvent(for msg: Message) -> SessionEvent? {
        guard modelOwnsPhase else { return nil }
        // A wire event names the peer it came from, because with several
        // cameras connected "the peer" is not a thing. This coordinator holds
        // one, so that is the one.
        let from = currentPeer.map { DeviceRef($0.displayName) }
        switch msg {
        case let pic as RemoteCmd.TakePic:
            guard let from else { return nil }
            return .wire(.takePic(sendMediaToPeer: pic.sendMediaToPeer), from: from)
        case is RemoteCmd.EndSession:
            guard let from else { return nil }
            return .wire(.endSession, from: from)
        case is RemoteCmd.StartRecordingVideo:
            guard let from else { return nil }
            return .wire(.startRecording, from: from)
        case let stop as RemoteCmd.StopRecordingVideo:
            guard let from else { return nil }
            return .wire(.stopRecording(sendMediaToPeer: stop.sendMediaToPeer), from: from)
        case let timeout as UICmd.StateTimeout where timeout.stateName == .cameraTakingPic:
            return .stateTimeout(generation: timeout.generation)
        case let picture as UICmd.OnPicture:
            return picture.pic == nil ? .captureFailed : .pictureCaptured
        default:
            return nil
        }
    }
}
