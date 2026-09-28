//
//  SessionShadow.swift
//  RemoteShutter
//
//  The photo slice's model, running beside the coordinator and deciding
//  nothing. See SessionModel/README.md for how to read what it reports, and
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

    /// Build the model's state from the coordinator's own. Every field has to
    /// be derivable from what the app already keeps, or the shadow cannot
    /// resynchronise it.
    func projectPhotoState() -> PhotoState {
        PhotoState(
            phase: Self.photoPhase(from: state),
            linked: currentPeer != nil,
            alertUp: hasCameraAlert,
            captureOutstanding: captureOutstanding,
            timeoutGeneration: timeoutGeneration)
    }

    private static func photoPhase(from state: SessionState) -> PhotoPhase {
        switch state {
        case let .cameraTakingPic(sendMediaToPeer, generation):
            return .takingPic(sendMediaToPeer: sendMediaToPeer, generation: generation)
        case .scanning, .reconnecting, .waitingForLobby, .lobby:
            return .scanning
        default:
            return .camera
        }
    }

    /// Map a coordinator message to a model event, or nil when the model does
    /// not own it yet. Unowned messages still reach the shadow so its state
    /// keeps up with reality.
    func photoEvent(for msg: Message) -> PhotoEvent? {
        switch msg {
        case let pic as RemoteCmd.TakePic:
            return .pressShutter(sendMediaToPeer: pic.sendMediaToPeer)
        case is RemoteCmd.EndSession:
            return .endSession
        case let timeout as UICmd.StateTimeout where timeout.stateName == .cameraTakingPic:
            return .stateTimeout(generation: timeout.generation)
        case let picture as UICmd.OnPicture:
            return picture.pic == nil ? .captureFailed : .pictureCaptured
        default:
            return nil
        }
    }
}
