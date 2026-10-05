import Correcto

// The session, as one state machine.
//
// Two devices run this same function. Which one is the camera and which is the
// remote is a role the machine takes on at runtime, exactly as the app works:
// both sides are a `SessionCoordinator`, and `BecomeCamera` is what splits
// them. So a world holds N instances of one model, which is also the only
// shape Correcto's explorer supports.
//
// Nothing here has an identity or a lifetime. A peer is a `DeviceRef`, which is
// a name; the real `MCPeerID`, the camera rig, the alert handle and the tasks
// stay in whatever runs this.

/// A device, by name. The model decides on which peer, never on a peer object.
public struct DeviceRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var description: String { name }
}

/// Which half of the protocol this device is playing.
public enum Role: String, Hashable, Codable, Sendable {
    /// Paired, and nobody has claimed the camera yet.
    case undecided
    /// Holds the camera. A server: it keeps its post through a peer drop.
    case camera
    /// Drives the camera. The director, in the app's words.
    case remote
}

// MARK: - State

public struct DeviceState: Hashable, Codable, Sendable {
    /// The app's own enum, not a copy of it.
    public var phase: SessionState
    public var role: Role
    /// Everyone this device is paired with, in a fixed order.
    ///
    /// A camera holds one remote. A remote holds as many cameras as the person
    /// connected, which is what makes one shutter tap a four-camera take. It is
    /// a sorted array rather than a set because exploration has to be
    /// deterministic, and set iteration order is not.
    public var peers: [DeviceRef]
    /// The "Taking picture" modal is on screen. In the app this is
    /// `alertHandle != nil`, which lives outside the state enum and is exactly
    /// why nothing could check it.
    public var alertUp: Bool
    /// Camera side: the hardware was asked for a picture and owes an answer.
    public var captureOutstanding: Bool
    /// Remote side: how many cameras were told to capture and have not
    /// answered. A count rather than a flag, because a multicam take is
    /// outstanding until the last camera reports.
    public var capturesAwaited: Int
    /// Remote side: how many recording commands are outstanding.
    public var recordingsAwaited: Int
    /// Remote side: this device believes a take is running. The whole point of
    /// several machines is that this can be wrong.
    public var believesRecording: Bool
    public var timeoutGeneration: Int

    public init(phase: SessionState = .scanning, role: Role = .undecided,
                peers: [DeviceRef] = [], alertUp: Bool = false,
                captureOutstanding: Bool = false, capturesAwaited: Int = 0,
                recordingsAwaited: Int = 0, believesRecording: Bool = false,
                timeoutGeneration: Int = 0) {
        self.phase = phase
        self.role = role
        self.peers = peers
        self.alertUp = alertUp
        self.captureOutstanding = captureOutstanding
        self.capturesAwaited = capturesAwaited
        self.recordingsAwaited = recordingsAwaited
        self.believesRecording = believesRecording
        self.timeoutGeneration = timeoutGeneration
    }

    /// The one peer, when there is exactly one. A camera's remote.
    public var peer: DeviceRef? { peers.count == 1 ? peers[0] : nil }

    public var isPaired: Bool { !peers.isEmpty }

    /// Nothing this device was asked to do is still outstanding.
    public var settled: Bool {
        !captureOutstanding && capturesAwaited == 0 && recordingsAwaited == 0
    }

    mutating func add(peer: DeviceRef) {
        guard !peers.contains(peer) else { return }
        peers.append(peer)
        peers.sort { $0.name < $1.name }
    }

    mutating func remove(peer: DeviceRef) {
        peers.removeAll { $0 == peer }
    }
}

// MARK: - What goes over the wire

/// The commands the two devices send each other. `RemoteCmd` in the app,
/// narrowed to this slice of the protocol.
public enum Wire: Hashable, Codable, Sendable {
    case peerBecameCamera
    case takePic(sendMediaToPeer: Bool)
    /// "Working on it." Progress only, and the app sends it before the result.
    case takePicAck
    case takePicResp(failed: Bool, carriesMedia: Bool)
    case startRecording
    case startRecordingAck
    case stopRecording(sendMediaToPeer: Bool)
    case stopRecordingResp(failed: Bool)
    /// The clip reached the other device.
    case videoArrived
    /// The receiver confirms the transfer. `MulticamController` calls this the
    /// 1:1 monitor's contract: the camera holds `.cameraTransmittingVideo`,
    /// where every capture command is refused, until this comes back.
    case videoReceivedEcho
    case endSession
}

// MARK: - Events, grouped by the source that produces them

public enum SessionEvent: Hashable, Codable, Sendable {
    // The person holding the device.
    case invite(DeviceRef)
    case becomeCamera
    case pressShutter(sendMediaToPeer: Bool)
    case pressRecord
    case pressStop(sendMediaToPeer: Bool)
    case leaveSession

    // The transport. Each of these names the peer it is about, because with
    // several cameras connected "the peer" is not a thing.
    case peerConnected(DeviceRef)
    /// The link to this peer went away by itself. A camera holds its post
    /// through it.
    case peerLost(DeviceRef)
    /// A send to this peer could not leave on a live link.
    /// `sendOrGoToScanning` treats that as a dead session.
    case sendFailed(DeviceRef)

    // A peer's command, and which peer sent it.
    case wire(Wire, from: DeviceRef)

    // The capture hardware.
    case pictureCaptured
    case captureFailed
    case recordingStarted
    case recordingFailed
    case clipReady

    // The ten second watchdog.
    case stateTimeout(generation: Int)
}

// MARK: - Effects

public enum Alert: String, Hashable, Codable, Sendable {
    case takingPicture
    case connectionError
}

public enum SessionEffect: Hashable, Codable, Sendable {
    case send(Wire, to: DeviceRef)
    case invite(DeviceRef)
    case armTimeout(generation: Int)
    case takePicture(sendToPeer: Bool)
    case startRecording
    case stopRecording
    case showAlert(Alert)
    case dismissAlert
    case saveToLibrary
    case saveClip
}
