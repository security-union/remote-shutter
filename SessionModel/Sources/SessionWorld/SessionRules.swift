import Correcto
import CorrectoCheck
import SessionModel

// The rules, as sentences. Each one is a thing that must never be true, or a
// thing that must be true once the dust has settled.
//
// The families matter more than the individual sentences. Pairing rules are
// about something held that must be released. Agreement rules are about two
// devices not disagreeing, and they are the ones no unit test can express,
// because a unit test has one object in it.

public enum SessionRules {

    public typealias Rule = WorldInvariant<SessionDevice, SessionEnv>

    /// Pairing. The app enforces this with a cleanup call, and the cleanup was
    /// missing on two of the four doors out of a capture.
    public static let alert = Rule("an alert is up only while taking a picture") { world in
        world.machines.values.allSatisfy { state in
            if case .cameraTakingPic = state.phase { return true }
            return !state.alertUp
        }
    }

    /// Agreement. Two cameras in one session means both devices answer the
    /// shutter and neither shows a preview.
    ///
    /// It is about a pairing, not about the world. The first version of this
    /// sentence counted camera-role devices everywhere and broke immediately on
    /// a rig with two cameras in it, which is a perfectly ordinary thing to own.
    public static let oneCamera = Rule("two paired devices never both hold the camera") { world in
        for (id, state) in world.machines where state.role == .camera {
            for peer in state.peers {
                guard let other = world.machines[MachineID(peer.name)] else { continue }
                if other.role == .camera, other.peers.contains(DeviceRef(id.name)) { return false }
            }
        }
        return true
    }

    /// Agreement, and the reason for the whole exercise: the remote's belief
    /// about the camera has to be true once nothing is in flight.
    public static let recordingAgreement = Rule(
        "no remote believes recording while every camera it holds is idle", when: .quiescent
    ) { world in
        for state in world.machines.values where state.believesRecording {
            let anyRecording = state.peers.contains { peer in
                guard let camera = world.machines[MachineID(peer.name)] else { return false }
                return camera.phase == .cameraRecordingVideo
                    || camera.phase == .cameraTransmittingVideo
            }
            if !anyRecording { return false }
        }
        return true
    }

    /// Terminal. The substitute for liveness, and the only rule on this list
    /// that catches lost work: a photo that arrives in a phase which ignores it
    /// is not something a "must never be true" sentence describes.
    public static let nothingOutstanding = Rule(
        "when nothing more can happen, nothing is left outstanding", when: .quiescent
    ) { world in
        world.machines.values.allSatisfy { $0.settled }
    }

    /// Terminal. The camera holds `.cameraTransmittingVideo` until the receiver
    /// echoes, and every capture command is refused in there. If the echo never
    /// comes the camera is wedged until the link dies, which is the defect that
    /// an inherited clip name used to cause.
    public static let notWedged = Rule(
        "no camera is left waiting to transmit", when: .quiescent
    ) { world in
        world.machines.values.allSatisfy { $0.phase != .cameraTransmittingVideo }
    }

    /// Agreement, for a rig. A camera serves one remote at a time: two remotes
    /// driving one camera means each sees half a session.
    public static let oneRemotePerCamera = Rule("a camera serves one remote") { world in
        world.machines.values.allSatisfy { state in
            state.role != .camera || state.peers.count <= 1
        }
    }

    public static let all: [Rule] = [
        alert, oneCamera, oneRemotePerCamera, recordingAgreement, nothingOutstanding, notWedged
    ]

    /// Transition rules are about a step taken rather than a state reached.
    /// This is the generation guard the team wrote years ago, as a sentence.
    public static let staleTimeout = TransitionInvariant<SessionDevice>(
        "a timeout for a stale generation changes nothing"
    ) { transition in
        guard case let .stateTimeout(fired) = transition.event else { return true }
        guard fired != transition.before.timeoutGeneration else { return true }
        return transition.after == transition.before
    }

    public static let allTransitions: [TransitionInvariant<SessionDevice>] = [staleTimeout]
}
