import Stormo

/// The session's state. One enum, used by `SessionCoordinator` at runtime and
/// by the checker when it explores.
///
/// It lives here rather than in the app because the model cannot import the
/// app, and two enums describing one machine is exactly the drift this whole
/// exercise exists to remove. The conformances are what the checker needs:
/// plain data it can hash, compare and write into a counterexample file.
///
/// `PeerID` is Stormo's, a struct whose equality is the multihash of the
/// peer's public key, so it is plain data too.
public enum SessionState: Hashable, Codable, Sendable {
    case waitingForLobby
    case lobby
    case scanning
    case reconnecting(peer: PeerID)
    case connected
    case camera
    case cameraTakingPic(sendMediaToPeer: Bool, generation: Int)
    case cameraRecordingVideo
    case cameraTransmittingVideo
    case watchCamera
    case watchCameraTakingPic(generation: Int)
    case watchCameraStartingVideo(generation: Int)
    case watchCameraRecordingVideo(stopGeneration: Int?)

    /// The coarse name, for logs, the Watch and the timeout protocol.
    public var name: RemoteCamState {
        switch self {
        case .waitingForLobby: return .idle
        case .lobby: return .idle
        case .scanning: return .scanning
        case .reconnecting: return .reconnecting
        case .connected: return .connected
        case .camera: return .camera
        case .cameraTakingPic: return .cameraTakingPic
        case .cameraRecordingVideo: return .cameraRecordingVideo
        case .cameraTransmittingVideo: return .cameraTransmittingVideo
        case .watchCamera: return .watchRemoteCamera
        case .watchCameraTakingPic: return .watchRemoteCameraTakingPic
        case .watchCameraStartingVideo: return .watchRemoteCameraStartingVideo
        case .watchCameraRecordingVideo: return .watchRemoteCameraRecordingVideo
        }
    }

    /// The peer this state is waiting to come back, if any.
    public var awaitedPeer: PeerID? {
        if case let .reconnecting(peer) = self { return peer }
        return nil
    }

    /// The camera is a server: it holds its post through a peer drop.
    public var isCameraRole: Bool {
        switch self {
        case .camera, .cameraTakingPic, .cameraRecordingVideo, .cameraTransmittingVideo:
            return true
        default:
            return false
        }
    }
}

/// The coarse state name shared with the Watch and carried by `StateTimeout`.
public enum RemoteCamState: String, Hashable, Codable, Sendable {
    case scanning
    case reconnecting
    case idle
    case connected
    case camera
    case cameraTakingPic
    case cameraRecordingVideo
    case cameraTransmittingVideo
    case watchRemoteCamera
    case watchRemoteCameraTakingPic
    case watchRemoteCameraStartingVideo
    case watchRemoteCameraRecordingVideo
}
