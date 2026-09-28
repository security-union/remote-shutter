import Correcto

// The photo round trip, as a state machine.
//
// `PhotoCamera` is the model: one pure function, correct, and the coordinator
// now matches it. The two behaviours it used to get wrong are parameters
// rather than a second copy of the machine, so `PhotoCameraBuggy` is the same
// body with both switched off. That variant is a deliberate regression kept
// for one purpose: the checker must rediscover, from the rules alone, the
// defects that `CorrectoReproductionTests` now guards against. A checker that
// cannot find bugs we already fixed should not be believed about new ones.
//
// The peer is the environment rather than a second machine in this slice.
// Nothing here decides on peer identity, only on whether a peer is there, so
// `Stormo.PeerID` is not needed yet.

// MARK: - State

public struct PhotoState: Hashable, Codable, Sendable {
    /// The app's own state enum, not a copy of it.
    public var phase: SessionState
    /// A peer is connected. `SessionCoordinator.link` narrowed to what this
    /// slice decides on.
    public var linked: Bool
    /// The "Taking picture" modal is on screen. In the app this is
    /// `alertHandle != nil`, which lives outside the state enum and is exactly
    /// why nothing can check it.
    public var alertUp: Bool
    /// The hardware was asked for a picture and has not answered yet. The app
    /// has no such field; the capture just happens and its answer may or may
    /// not find a state that wants it.
    public var captureOutstanding: Bool
    public var timeoutGeneration: Int

    public init(phase: SessionState = .camera, linked: Bool = true, alertUp: Bool = false,
                captureOutstanding: Bool = false, timeoutGeneration: Int = 0) {
        self.phase = phase
        self.linked = linked
        self.alertUp = alertUp
        self.captureOutstanding = captureOutstanding
        self.timeoutGeneration = timeoutGeneration
    }
}

// MARK: - Events, grouped by the source that produces them

public enum PhotoEvent: Hashable, Codable, Sendable {
    /// The peer's `TakePic`, or the local shutter.
    case pressShutter(sendMediaToPeer: Bool)
    /// The peer's `EndSession`.
    case endSession
    /// A send could not leave. `sendOrGoToScanning` treats this as a dead link.
    case sendFailed
    /// The capture hardware answered.
    case pictureCaptured
    case captureFailed
    /// The ten second watchdog armed on the way into the capture.
    case stateTimeout(generation: Int)
}

// MARK: - Effects

public enum PhotoEffect: Hashable, Codable, Sendable {
    case takePicture(sendToPeer: Bool)
    case armTimeout(generation: Int)
    case showAlert
    case dismissAlert
    case saveToLibrary
    case sendAck
    case sendTimedOut
}

// MARK: - The machine

/// The two behaviours the coordinator used to get wrong. Both are `true` in
/// the model and in the app; `.buggy` switches them off so the checker can be
/// held to finding them.
public struct PhotoBehaviour: Hashable, Sendable {
    /// Abandoning a capture takes its alert down, whichever door it leaves by.
    public let dismissesAlertOnAbort: Bool
    /// A capture that finished after its watchdog still produced bytes, and
    /// they are saved. The Watch path already does this.
    public let savesLatePicture: Bool

    public static let correct = PhotoBehaviour(dismissesAlertOnAbort: true, savesLatePicture: true)
    public static let buggy = PhotoBehaviour(dismissesAlertOnAbort: false, savesLatePicture: false)
}

// swiftlint:disable:next cyclomatic_complexity
public func photoStep(
    _ state: PhotoState, _ event: PhotoEvent, _ behaviour: PhotoBehaviour
) -> Step<PhotoState, PhotoEffect> {
    var next = state
    switch (state.phase, event) {

    case let (.camera, .pressShutter(send)):
        guard state.linked else { return .ignore(state) }
        next.timeoutGeneration += 1
        next.phase = .cameraTakingPic(sendMediaToPeer: send, generation: next.timeoutGeneration)
        next.alertUp = true
        next.captureOutstanding = true
        return Step(next, [
            .armTimeout(generation: next.timeoutGeneration), .showAlert,
            .takePicture(sendToPeer: send)
        ])

    case (.cameraTakingPic, .pictureCaptured):
        next.phase = .camera
        next.alertUp = false
        next.captureOutstanding = false
        return Step(next, [.dismissAlert, .saveToLibrary, .sendAck])

    case (.cameraTakingPic, .captureFailed):
        next.phase = .camera
        next.alertUp = false
        next.captureOutstanding = false
        return Step(next, [.dismissAlert])

    case let (.cameraTakingPic(_, generation), .stateTimeout(fired)):
        // The generation guard the app already has, and which works.
        guard fired == generation else { return .ignore(state) }
        next.phase = .camera
        next.alertUp = false
        // The hardware is still working; the capture stays outstanding until
        // it answers.
        return Step(next, [.dismissAlert, .sendTimedOut])

    // Abandoning a capture. `popToScanning` and `sendOrGoToScanning` both leave
    // by this door and neither dismisses today.
    case (.cameraTakingPic, .endSession), (.cameraTakingPic, .sendFailed):
        next.phase = .scanning
        next.linked = false
        guard behaviour.dismissesAlertOnAbort else { return Step(next) }
        next.alertUp = false
        return Step(next, [.dismissAlert])

    case (_, .endSession), (_, .sendFailed):
        next.phase = .scanning
        next.linked = false
        return Step(next)

    // The capture answers into a state that was no longer waiting for it,
    // because the watchdog already fired. `inCamera` has no `OnPicture` case.
    case (.camera, .pictureCaptured), (.scanning, .pictureCaptured):
        guard behaviour.savesLatePicture, state.captureOutstanding else { return .ignore(state) }
        next.captureOutstanding = false
        return Step(next, [.saveToLibrary])

    case (.camera, .captureFailed), (.scanning, .captureFailed):
        guard behaviour.savesLatePicture, state.captureOutstanding else { return .ignore(state) }
        next.captureOutstanding = false
        return Step(next)

    default:
        return .ignore(state)
    }
}

/// The model. Every rule in `PhotoSliceTests` holds over every reachable state.
public enum PhotoCamera: Model {
    public static func step(_ state: PhotoState, _ event: PhotoEvent) -> Step<PhotoState, PhotoEffect> {
        photoStep(state, event, .correct)
    }
}

/// A deliberate regression. Not shipped, not intended; it exists so the
/// acceptance tests can prove the checker finds these two defects.
public enum PhotoCameraBuggy: Model {
    public static func step(_ state: PhotoState, _ event: PhotoEvent) -> Step<PhotoState, PhotoEffect> {
        photoStep(state, event, .buggy)
    }
}
