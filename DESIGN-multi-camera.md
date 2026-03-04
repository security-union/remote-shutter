# Multi-Camera Control: Design Document

## Overview

Support controlling **up to 8 cameras** simultaneously from a single monitor device.
All cameras operate in the **same mode** (photo or video). Commands are **broadcast**
to all connected cameras. The monitor shows a **grid of live previews**.

## Architecture: Broadcast Monitor

```
                         [Monitor Device]
                    ┌─────────────────────┐
                    │   MultiCameraGrid   │
                    │  ┌───┐ ┌───┐ ┌───┐  │
                    │  │ A │ │ B │ │ C │  │
                    │  └───┘ └───┘ └───┘  │
                    │  [Record All] [Flash]│
                    └────────┬────────────┘
                             │
                     MonitorActor (1:N bridge)
                             │
                     RemoteCamSession
                     peers: Set<MCPeerID>
                     frameSenders: [MCPeerID: ActorRef]
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         MCSession.send(toPeers: allPeers)
              │              │              │
         Camera A       Camera B       Camera C
```

## Current vs. Proposed: Key Differences

| Aspect | Current (1:1) | Proposed (1:N) |
|--------|---------------|----------------|
| Peer tracking | `peer: MCPeerID` | `peers: Set<MCPeerID>` |
| State params | Single peer in every state | Peer set shared across states |
| FrameSender | 1 actor | Dictionary: `[MCPeerID: ActorRef]` |
| Disconnect | Pop to scanning | Remove peer from set; pop to scanning only when last peer disconnects |
| Commands | `send(toPeers: [peer])` | `send(toPeers: Array(peers))` |
| Responses | Expect 1 response | Collect N responses (fire-and-forget or wait-for-all) |
| Frame stream | 1 stream displayed | N streams, each in a grid cell |
| Monitor UI | Single preview | Grid layout, shared controls |

## Detailed Design

### Phase 1: Connection & Peer Management

#### 1.1 Scanning State Changes

Currently the scanning state transitions to `connected` on the first peer connection.
Instead:

- **Stay in scanning** when first peer connects — show it in the grid as "connected"
- Add a **"Start Session"** button that the user taps when all cameras are connected
- Or: auto-transition after a timeout / when user navigates to role picker
- The role picker is **removed** — monitor always becomes the monitor, cameras always
  become cameras (since we broadcast, the monitor can't also be a camera)

**New flow:**
```
scanning → (peers connect one by one, grid builds up)
         → user taps "Start" or selects "Monitor" role
         → monitorPhotoMode(peers: Set<MCPeerID>)
```

**Open question:** How do cameras know they should become cameras? Options:
- (a) Monitor sends `PeerBecameMonitor` to all peers → each peer auto-becomes camera
- (b) Each device still picks its role, but the monitor aggregates all camera peers

**Recommendation:** Option (a) — the monitor device drives. When user taps "Start
Session" on monitor, it sends `PeerBecameMonitor` to all connected peers. Each peer
receives it and transitions to camera state automatically.

#### 1.2 PeerContext: Per-Peer State Tracking

```swift
struct PeerContext {
    let peerID: MCPeerID
    var frameSender: ActorRef?         // FrameSender actor for this peer
    var capabilities: CameraCapabilities?  // Lenses, zoom, flash support
    var lastFrame: Data?               // Most recent preview frame
    var isResponding: Bool = true      // Health tracking
}
```

`RemoteCamSession` holds: `var peerContexts: [MCPeerID: PeerContext]`

#### 1.3 Disconnect Handling

```swift
case let c as DisconnectPeer:
    peerContexts.removeValue(forKey: c.peer)
    // Destroy that peer's FrameSender
    if peerContexts.isEmpty {
        self.popAndStartScanning()  // No cameras left
    } else {
        // Notify UI to update grid (remove one cell)
        monitor ! UICmd.PeerDisconnected(peer: c.peer)
    }
```

### Phase 2: State Machine Refactor

#### 2.1 State Function Signatures

Every state function changes from `peer: MCPeerID` to using `self.peerContexts`:

```swift
// BEFORE
func monitorPhotoMode(monitor: ActorRef, peer: MCPeerID, lobby: Weak<DSViewController>) -> Receive

// AFTER
func monitorPhotoMode(monitor: ActorRef, lobby: Weak<DSViewController>) -> Receive
// peers accessed via self.peerContexts
```

This is the **largest single change** — touches all 6+ monitor/camera state files.

#### 2.2 Command Broadcasting

```swift
// BEFORE
self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.TakePic(...))

// AFTER
self.broadcastCommand(msg: RemoteCmd.TakePic(...))

// New helper method:
func broadcastCommand(msg: Actor.Message, mode: MCSessionSendDataMode = .reliable) {
    let allPeers = Array(peerContexts.keys)
    let failedPeers = self.sendMessage(peers: allPeers, msg: msg, mode: mode)
    for peer in failedPeers {
        peerContexts.removeValue(forKey: peer)
        // Notify UI
    }
    if peerContexts.isEmpty {
        self.popToState(name: self.states.scanning)
    }
}
```

#### 2.3 Response Aggregation Strategy

Two strategies depending on the command:

**Fire-and-forget (most commands):**
- Flash toggle, camera toggle, zoom, lens switch
- Send to all, handle each response as it arrives
- Update UI per-camera (e.g., Camera A flash on, Camera B flash failed)

**Collect-all (photo capture):**
- TakePic → wait for TakePicResp from ALL cameras
- Save each photo individually
- Show progress: "Received 2/3 photos"

```swift
// For photo capture:
var pendingPhotoResponses: [MCPeerID: Data?] = [:]

case let resp as RemoteCmd.TakePicResp:
    pendingPhotoResponses[resp.senderPeer] = resp.pic
    if pendingPhotoResponses.count == peerContexts.count {
        // All photos received — save all, unbecome
    }
```

**Note:** This requires tagging responses with sender peer ID. Currently `RemoteCmd`
messages don't carry this. The `MCSessionDelegate.session(_:didReceive:fromPeer:)`
callback provides it, but it's lost by the time the message reaches the state machine.

#### 2.4 Peer-Tagged Messages

Wrap incoming remote messages to preserve sender identity:

```swift
class PeerMessage: Actor.Message {
    let fromPeer: MCPeerID
    let innerMessage: Actor.Message
}
```

In `MultipeerDelegates.swift`:
```swift
func didReceiveMessage(_ message: Actor.Message, from peer: MCPeerID) {
    self.this ! PeerMessage(fromPeer: peer, innerMessage: message)
}
```

State handlers unwrap:
```swift
case let pm as PeerMessage:
    switch pm.innerMessage {
    case let resp as RemoteCmd.TakePicResp:
        handleTakePicResp(resp, from: pm.fromPeer)
    // ...
    }
```

### Phase 3: FrameSender (Multiple Streams)

#### 3.1 One FrameSender Per Camera

```swift
// When peer becomes camera:
func createFrameSender(for peer: MCPeerID) {
    let name = "FrameSender-\(peer.displayName)"
    let sender = RemoteCamSystem.shared.actorOf(name: name, FrameSender.self)
    sender ! FrameSender.SetSession(peer: peer, session: self)
    peerContexts[peer]?.frameSender = sender
}
```

#### 3.2 Bandwidth Considerations

With 8 cameras streaming 30fps JPEG frames:
- Each frame ~50-100KB → ~3-6 MB/s per camera → 24-48 MB/s total
- MultipeerConnectivity may not handle this

**Mitigation strategies:**
- Reduce FPS proportionally: `targetFPS = 30 / connectedCameraCount`
- Reduce JPEG quality for grid thumbnails (lower resolution)
- Only stream full-quality from "focused" camera (tapped grid cell)
- Use `.unreliable` send mode (already done) — dropped frames are fine

#### 3.3 Adaptive Quality

```swift
// In FrameSender or camera state:
let gridFPS = max(5, 30 / peerContexts.count)  // 5-30 FPS
let jpegQuality: CGFloat = peerContexts.count > 4 ? 0.3 : 0.5
```

### Phase 4: Monitor UI (SwiftUI)

#### 4.1 Grid Layout

```swift
struct MultiCameraGridView: View {
    @ObservedObject var viewModel: MultiCameraViewModel

    var body: some View {
        VStack {
            // Camera grid
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(viewModel.cameras) { camera in
                    CameraPreviewCell(camera: camera)
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            Text(camera.displayName)
                                .font(.caption)
                        }
                }
            }

            // Shared controls (same for all cameras)
            ControlBar(
                onTakePicture: viewModel.takePictureAll,
                onToggleFlash: viewModel.toggleFlashAll,
                onRecord: viewModel.toggleRecordingAll,
                mode: viewModel.currentMode
            )
        }
    }

    var gridColumns: [GridItem] {
        let count = viewModel.cameras.count
        let cols = count <= 2 ? count : Int(ceil(sqrt(Double(count))))
        return Array(repeating: GridItem(.flexible(), spacing: 4), count: cols)
    }
}
```

#### 4.2 MultiCameraViewModel

```swift
class MultiCameraViewModel: ObservableObject {
    @Published var cameras: [CameraState] = []  // One entry per connected peer
    @Published var currentMode: RecordingMode = .Photo
    @Published var isRecording: Bool = false

    struct CameraState: Identifiable {
        let id: String  // peer.displayName
        let peerID: MCPeerID
        var previewImage: UIImage?
        var flashMode: String = ""
        var isConnected: Bool = true
        var lastError: String?
    }

    func updateFrame(for peer: MCPeerID, image: UIImage) { ... }
    func updateCapabilities(for peer: MCPeerID, caps: CameraCapabilities) { ... }
    func removePeer(_ peer: MCPeerID) { ... }
}
```

#### 4.3 Reusing MonitorView vs. New View

**Recommendation:** Create a new `MultiCameraGridView` rather than modifying
`MonitorView`. Keep the existing 1:1 MonitorView working — it can be the "single
camera" mode or the "full-screen focused" view when a grid cell is tapped.

### Phase 5: Video Recording (Multi-Camera)

#### 5.1 Broadcast Record Start/Stop

```swift
// Monitor taps record:
broadcastCommand(msg: RemoteCmd.StartRecordingVideo(...))
// All cameras start recording simultaneously

// Monitor taps stop:
broadcastCommand(msg: RemoteCmd.StopRecordingVideo(sendMediaToPeer: true))
// All cameras stop and send video files back
```

#### 5.2 Parallel Video Transfer

Each camera sends its video via `MCSession.sendResource()`. The monitor receives
N parallel resource transfers.

```swift
// Track per-peer video transfer:
var videoTransfers: [MCPeerID: VideoTransferState] = [:]

struct VideoTransferState {
    var progress: Double = 0
    var totalBytes: Int64 = 0
    var completedBytes: Int64 = 0
    var isComplete: Bool = false
}
```

UI shows per-camera progress in the grid cell overlay.

#### 5.3 Saving Videos

Each video saved independently to Photos app. User gets N separate videos
(one per camera angle). Future enhancement: stitch them together.

### Phase 6: Edge Cases & Error Handling

#### 6.1 Camera Capabilities Mismatch

Cameras may have different capabilities (e.g., one has telephoto, another doesn't).

**Strategy: Intersection of capabilities for shared controls**
```swift
var sharedCapabilities: CameraCapabilities {
    // Only show controls that ALL cameras support
    let allCaps = peerContexts.values.compactMap(\.capabilities)
    return CameraCapabilities.intersection(allCaps)
}
```

Or: show all controls, but indicate per-camera support (dimmed for unsupported).

#### 6.2 Partial Failures

- Camera A toggles flash successfully, Camera B fails
- Show per-camera status in grid cell (green checkmark / red X)
- Don't block the UI waiting for all responses

#### 6.3 Late Joiners

- Camera connects after session is already in monitorPhotoMode
- Auto-assign camera role, add to peerContexts, create FrameSender
- Send current mode info so camera configures itself correctly

#### 6.4 Network Saturation

- Monitor bandwidth with frame drop rate
- Auto-reduce quality/FPS if drops exceed threshold
- Priority: keep commands reliable, degrade preview quality

## Implementation Order (Recommended)

1. **PeerContext + multi-peer tracking** — Foundation for everything
2. **PeerMessage wrapper** — Tag incoming messages with sender peer
3. **State machine: replace `peer:` with peer set** — Core refactor
4. **broadcastCommand helper** — Replace sendCommandOrGoToScanning calls
5. **Multiple FrameSenders** — One per camera, adaptive FPS
6. **MultiCameraGridView + ViewModel** — New SwiftUI grid UI
7. **MonitorActor bridge updates** — Route per-peer frames/responses
8. **Video recording broadcast** — Start/stop all cameras
9. **Parallel video transfer** — Per-peer progress tracking
10. **Edge cases** — Capabilities intersection, partial failures, late joiners

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| State machine refactor breaks existing 1:1 | High | Keep old MonitorView as fallback; comprehensive tests |
| Network bandwidth with 8 streams | Medium | Adaptive FPS/quality; tested with 2 cameras first |
| Response aggregation complexity | Medium | Start with fire-and-forget; add collect-all for photos later |
| MC framework 8-peer limit reliability | Low | Apple docs say 8, but real-world may be less stable |
| Timing: all cameras start recording at same frame | Low | Accept small drift; sync via NTP is overkill |

## Files to Modify

**Core (must change):**
- `RemoteCamSession.swift` — PeerContext dict, broadcastCommand, multi-FrameSender
- `RemoteCamConnected.swift` — Multi-peer connected state
- `MonitorPhotoStates.swift` — Broadcast photo commands, collect responses
- `MonitorVideoStates.swift` — Broadcast video commands, parallel transfer
- `MonitorStates.swift` — Broadcast flash/camera/lens toggles
- `MultipeerDelegates.swift` — PeerMessage wrapper, per-peer routing
- `MultipeerService.swift` — Minor: partial disconnect handling
- `FrameSender.swift` — No changes (already per-peer), just instantiate multiple
- `States.swift` — Possibly new states for multi-camera setup

**New files:**
- `MultiCameraGridView.swift` — SwiftUI grid layout
- `MultiCameraViewModel.swift` — Per-camera state tracking
- `PeerContext.swift` — Per-peer context struct

**UI changes:**
- `MonitorViewController.swift` — Host MultiCameraGridView instead of MonitorView
- `MonitorViewController+SwiftUI.swift` — Per-peer update methods
- `DeviceScannerViewController.swift` — Multi-peer connection UI

**Minimal/no changes:**
- `CamStates.swift` — Camera side unchanged (each camera is independent)
- `CameraVideoStates.swift` — Camera side unchanged
- `CameraViewController.swift` — Camera side unchanged
- `RemoteCmds.swift` — No protocol changes needed
- `RemoteCmdFlatBuffers.swift` — No serialization changes
