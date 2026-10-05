import Correcto
import CorrectoCheck
import SessionModel

// The world the devices live in: the link between them, the capture hardware,
// the watchdogs, and budgets on what the people holding the devices may do.
//
// This target is where `CorrectoCheck` is allowed. The app links `SessionModel`
// and never the explorer, so none of this reaches a shipped binary.

/// A hardware call the camera makes and the world answers.
public enum CameraCommand: String, Hashable, Codable, Sendable {
    case takePicture
    case startRecording
    case stopRecording
}

public enum Outcome: String, Hashable, Codable, Sendable {
    case ok
    case failed
}

public struct SessionEnv: Hashable, Codable, Sendable {
    /// Commands in flight between devices. Reliable and in order per pair,
    /// which is what MultipeerConnectivity gives for `.reliable`.
    public var wire = Channel<Wire>()
    /// Armed ten second watchdogs, by generation.
    public var timers = Timers<String>()
    /// Hardware calls the camera is waiting on.
    public var hardware = Oracle<CameraCommand>()
    /// Links the transport is bringing up. Each endpoint learns separately,
    /// because in a real session they do.
    public var connecting: [Pending] = []

    // Budgets. Without these the search does not end.
    public var invites: Int
    public var shutterPresses: Int
    public var recordings: Int
    /// Stops need their own budget. Without one, a person can press stop
    /// forever, each press arms another watchdog, and `timeoutGeneration`
    /// climbs without bound: an infinite state space wearing a finite model's
    /// clothes. The search then stops at its world limit and reports a pass
    /// that proves nothing.
    public var stops: Int
    public var goodbyes: Int
    public var drops: Int

    public struct Pending: Hashable, Codable, Sendable {
        public let told: MachineID
        public let peer: DeviceRef
    }

    public init(invites: Int = 1, shutterPresses: Int = 1,
                recordings: Int = 0, stops: Int? = nil, goodbyes: Int = 0, drops: Int = 0) {
        self.invites = invites
        self.shutterPresses = shutterPresses
        self.recordings = recordings
        self.stops = stops ?? recordings
        self.goodbyes = goodbyes
        self.drops = drops
    }
}

public enum SessionWorld {

    public static func machine(_ device: DeviceRef) -> MachineID { MachineID(device.name) }
    public static func device(_ machine: MachineID) -> DeviceRef { DeviceRef(machine.name) }

    /// Everything the world does with what a device just emitted.
    public static func absorb(
        _ env: inout SessionEnv, from: MachineID, effects: [SessionEffect]
    ) {
        for effect in effects {
            switch effect {
            case let .send(message, to):
                env.wire.send(message, from: from, to: machine(to), mode: .reliable)
            case let .invite(peer):
                // Both ends learn the link came up, separately.
                env.connecting.append(.init(told: from, peer: peer))
                env.connecting.append(.init(told: machine(peer), peer: device(from)))
            case let .armTimeout(generation):
                env.timers.arm("watchdog", generation: generation, owner: from)
            case .takePicture:
                env.hardware.request(.takePicture, from: from)
            case .startRecording:
                env.hardware.request(.startRecording, from: from)
            case .stopRecording:
                env.hardware.request(.stopRecording, from: from)
            case .showAlert, .dismissAlert, .saveToLibrary, .saveClip:
                // Nothing in the world changes. These are what a person sees.
                break
            }
        }
    }

    /// Every nondeterministic thing that could happen next. The explorer tries
    /// all of them; `session-runner` shows them to a person and does one.
    public static func choices(
        _ env: SessionEnv, _ machines: [MachineID: DeviceState]
    ) -> [Choice<SessionDevice, SessionEnv>] {
        var out: [Choice<SessionDevice, SessionEnv>] = []
        let ids = machines.keys.sorted()

        // What the people holding the devices may do.
        for id in ids {
            guard let state = machines[id] else { continue }
            let isRemote = state.phase == .connected && state.role == .remote
            let isIdleCamera = state.phase == .camera

            let canInvite = state.role != .camera
                && (state.phase == .scanning || state.phase == .connected)
            if canInvite, env.invites > 0 {
                for other in ids where other != id && !state.peers.contains(device(other)) {
                    var nextEnv = env
                    nextEnv.invites -= 1
                    out.append(Choice("\(id) invites \(other)",
                                      deliver: .invite(device(other)), to: id, env: nextEnv))
                }
            }
            // Picking the camera role is not a move. It happens on the role
            // picker screen, before a scanner exists, so it is an initial
            // condition of the world. Offering it as a move invented a race
            // the app cannot have, and the checker found it in a minute: both
            // devices claiming the camera while an invite was already in
            // flight. Role configurations are separate worlds, see the tests.
            if isRemote || isIdleCamera, env.shutterPresses > 0 {
                var nextEnv = env
                nextEnv.shutterPresses -= 1
                out.append(Choice("shutter on \(id)",
                                  deliver: .pressShutter(sendMediaToPeer: true),
                                  to: id, env: nextEnv))
            }
            if isRemote || isIdleCamera, env.recordings > 0 {
                var nextEnv = env
                nextEnv.recordings -= 1
                out.append(Choice("record on \(id)", deliver: .pressRecord, to: id, env: nextEnv))
            }
            if state.believesRecording || state.phase == .cameraRecordingVideo, env.stops > 0 {
                var nextEnv = env
                nextEnv.stops -= 1
                out.append(Choice("stop recording on \(id)",
                                  deliver: .pressStop(sendMediaToPeer: true), to: id, env: nextEnv))
            }
            if state.isPaired, env.goodbyes > 0 {
                var nextEnv = env
                nextEnv.goodbyes -= 1
                out.append(Choice("\(id) leaves the session",
                                  deliver: .leaveSession, to: id, env: nextEnv))
            }
            if env.drops > 0 {
                // One link at a time, named: a remote losing one camera is not
                // the same event as losing the session.
                for peer in state.peers {
                    var nextEnv = env
                    nextEnv.drops -= 1
                    out.append(Choice("\(id) loses the link to \(peer)",
                                      deliver: .peerLost(peer), to: id, env: nextEnv))
                }
            }
        }

        // The transport bringing a link up, one end at a time.
        for (index, pending) in env.connecting.enumerated() {
            var nextEnv = env
            nextEnv.connecting.remove(at: index)
            out.append(Choice("link up on \(pending.told)",
                              deliver: .peerConnected(pending.peer),
                              to: pending.told, env: nextEnv))
        }

        // The peer's commands arriving.
        out += env.wire.choices(in: env, at: \.wire) { .wire($0.message, from: device($0.from)) }

        // A watchdog firing. Nothing cancels them, because the app arms a
        // `DispatchQueue.asyncAfter` that always fires and relies on the
        // generation to make a stale one harmless.
        out += env.timers.choices(in: env, at: \.timers) { .stateTimeout(generation: $0.generation) }

        // The hardware answering, every way it can.
        out += env.hardware.choices(
            in: env, at: \.hardware,
            outcomes: { (command: CameraCommand) -> [Outcome] in
                command == .stopRecording ? [.ok] : [.ok, .failed]
            },
            event: { (pending: Oracle<CameraCommand>.Pending, outcome: Outcome) -> SessionEvent in
                switch (pending.command, outcome) {
                case (.takePicture, .ok): return .pictureCaptured
                case (.takePicture, .failed): return .captureFailed
                case (.startRecording, .ok): return .recordingStarted
                case (.startRecording, .failed): return .recordingFailed
                case (.stopRecording, _): return .clipReady
                }
            })

        return out
    }

    public static var environment: Environment<SessionDevice, SessionEnv> {
        Environment(absorb: { env, from, effects in absorb(&env, from: from, effects: effects) },
                    choices: { env, machines in choices(env, machines) })
    }

    // MARK: - Worlds

    public static let remote: MachineID = "remote"
    public static let camera: MachineID = "camera"
    public static let camera2: MachineID = "camera2"

    /// A remote and a camera, both unpaired, roles already picked: that is what
    /// the role picker means. The person is the environment, and the moves it
    /// offers are the taps.
    public static func pair(env: SessionEnv = SessionEnv()) -> World<SessionDevice, SessionEnv> {
        World(machines: [remote: DeviceState(), camera: DeviceState(role: .camera)], env: env)
    }

    /// A remote and two cameras, nothing paired yet. With two invites the
    /// remote can collect both, which is how a rig is assembled.
    public static func rig(
        env: SessionEnv = SessionEnv(invites: 2)
    ) -> World<SessionDevice, SessionEnv> {
        World(machines: [remote: DeviceState(),
                         camera: DeviceState(role: .camera),
                         camera2: DeviceState(role: .camera)], env: env)
    }

    /// Already paired, roles settled. The useful starting point when the
    /// question is about capture rather than about pairing.
    public static func paired(env: SessionEnv = SessionEnv(invites: 0)) -> World<SessionDevice, SessionEnv> {
        World(machines: [
            remote: DeviceState(phase: .connected, role: .remote, peers: [device(camera)]),
            camera: DeviceState(phase: .camera, role: .camera, peers: [device(remote)])
        ], env: env)
    }

    /// A remote with two cameras already connected: one tap, two cameras. The
    /// starting point when the question is about a multicam take rather than
    /// about how the rig got assembled.
    public static func multicam(
        env: SessionEnv = SessionEnv(invites: 0)
    ) -> World<SessionDevice, SessionEnv> {
        World(machines: [
            remote: DeviceState(phase: .connected, role: .remote,
                                peers: [device(camera), device(camera2)]),
            camera: DeviceState(phase: .camera, role: .camera, peers: [device(remote)]),
            camera2: DeviceState(phase: .camera, role: .camera, peers: [device(remote)])
        ], env: env)
    }
}
