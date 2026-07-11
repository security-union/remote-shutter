# Theater Framework Removal & Modernization Plan

## Motivation

Remote Shutter uses the Theater pod -- an actor-model framework -- for thread safety,
state machine management, and message passing. Theater served the project well but has
become a liability:

- **Deadlock-prone** `^{}` operator (synchronous main-thread dispatch from actor mailbox)
- **Crash-prone** `[unowned self]` in every state closure
- **Stringly-typed** actor lookup (`selectActor(actorPath: "RemoteCam/user/...")`)
- **Type-unsafe** message dispatch (runtime `switch`/`case is`, silent `default` fallthrough)
- **Conflicts with SwiftUI migration** (`ViewCtrlActor` couples actors to UIKit VCs)
- **Unmaintained** pre-Swift-concurrency framework with dead code (BLE, WebSocket modules)

The goal is to replace Theater with native Swift concurrency and a type-safe state machine,
enabling easier testing, safer concurrency, and a clean path to SwiftUI.

## Target Architecture

```
SwiftUI Views <-> @MainActor ViewModels <-> SessionCoordinator (Swift actor) <-> MultipeerService
                                            FrameStreamer (Swift actor)       <-/
```

## Phased Migration

### Phase 1: Internalize Theater (PR #57)
**Status: DONE**
**Risk: LOW**

- Copied 7 used Theater source files into `RemoteCam/Theater/`
- Removed Theater and Starscream CocoaPods (2 fewer dependencies)
- Excluded 6 unused modules (BLECentral, BLEMessages, BLEPeripheral,
  BLEPeripheralConnection, WebSocketClientWrapper, WithListeners)
- Full ownership of the Theater source code

### Phase 2: Fix `^{}` Deadlock (PR #57)
**Status: DONE**
**Risk: LOW**

- Changed `^` operator from `waitUntilFinished: true` to `false`
- Eliminates deadlock where actor mailbox blocks on main thread while
  main thread callbacks re-enter mailbox via `mailbox.addOperation`
- Un-skipped 11 tests: 7/18 passing -> 18/18 passing
- `^{}` still dispatches to main thread for UI updates, just doesn't
  block the actor thread

### Phase 3: Extract MultipeerService
**Status: DONE**
**Risk: MEDIUM | Effort: 3-5 days**

Create a standalone `MultipeerService` class that encapsulates all
MultipeerConnectivity logic:

- `MCSession` lifecycle (create, connect, disconnect)
- `MCNearbyServiceBrowser` and `MCAdvertiserAssistant` management
- `MCSessionDelegate` implementation (didReceiveData, didReceiveResource, etc.)
- Message serialization/deserialization (`NSKeyedArchiver`/`NSKeyedUnarchiver`)
- `sendMessage()` and `sendCommandOrGoToScanning()` become methods on this service

This decouples P2P communication from the actor system. The session actor
becomes a consumer of the service rather than owning the transport.

**What moves:**
- `MCSession` property from `RemoteCamSession`
- `MCAdvertiserAssistant` property from `RemoteCamSession`
- `MCSessionDelegate` conformance from `MultipeerDelegates.swift`
- `sendMessage()` and `sendCommandOrGoToScanning()` from `RemoteCamSession`
- `startScanning()` MCSession/advertiser setup from `RemoteCamSession`

**What stays:**
- State machine logic (become/unbecome)
- Message routing to actors
- UI dispatch via `^{}`

**Testing note:** Current 18 tests already mock `sendMessage`/`sendCommandOrGoToScanning`,
so the state machine is tested independently of the transport. These tests will validate
that the extraction doesn't break state machine behavior.

### Phase 4: Replace RemoteCamSession with SessionCoordinator
**Status: DONE (PR #137)** — `SessionCoordinator` is a Swift actor with a FIFO
`AsyncStream` inbox (Theater's mailbox ordering preserved) and the full
20-state machine as a compiler-checked enum; `CameraControlling` went async
(`async throws` replaced `Try` at the seam); the loopback suite passed as
the behavior gate.

The big rewrite. Replace Theater's `become`/`unbecome`/`popToState` pattern with
a Swift `actor` using an explicit state enum:

```swift
actor SessionCoordinator {
    private(set) var state: SessionState = .scanning

    enum SessionState {
        case scanning
        case connected(peer: MCPeerID)
        case camera(peer: MCPeerID)
        case monitorPhotoMode(peer: MCPeerID)
        case monitorVideoMode(peer: MCPeerID)
        case monitorTakingPicture(peer: MCPeerID)
        case monitorTogglingFlash(peer: MCPeerID)
        case monitorTogglingCamera(peer: MCPeerID)
        case monitorSwitchingLens(peer: MCPeerID)
        case monitorRecordingVideo(peer: MCPeerID)
        // ...
    }

    func handle(_ event: SessionEvent) async {
        switch (state, event) {
        case (.scanning, .peerConnected(let peer)):
            state = .connected(peer: peer)
        case (.connected(let peer), .becameCamera):
            state = .camera(peer: peer)
        // ... exhaustive, compiler-verified
        }
    }
}
```

**Benefits:**
- Compile-time exhaustiveness checking (no silent `default` drops)
- No `[unowned self]` crashes
- `@MainActor` replaces `^{}` without any dispatch ceremony
- Type-safe events replace class-based message hierarchy
- Directly testable (call async methods, check state)

**Prerequisites:**
- Phase 3 complete (MultipeerService extracted)
- Expanded test coverage for camera states, monitor response handling,
  video recording flow, and DisconnectPeer handling in sub-states

### Phase 5: Simplify MonitorActor and RolePickerActor
**Status: DONE (PR #137)** — `MonitorActor` became `MonitorPresenter` (plain
methods, main-hops internally); the role-picker actor path was never
registered, so its forwards were dead sends and were removed.

- `MonitorActor` is a message router dispatching to `OperationQueue.main`.
  Replace with a delegate protocol or direct `@MainActor` ViewModel updates.
- `RolePickerActor` handles exactly 2 messages (`PeerBecameMonitor`,
  `PeerBecameCamera`). Replace with a delegate callback.

### Phase 6: Simplify FrameSender
**Status: DONE (PR #137)** — queue-confined class, same credit-window
back-pressure and ack watchdog.
**Risk: LOW | Effort: 1 day**

Replace Theater actor with a Swift `actor`:

```swift
actor FrameStreamer {
    private var readyToSend = true

    func sendFrame(_ frame: Data) async throws -> Bool {
        guard readyToSend else { return false }
        readyToSend = false
        try await multipeerService.send(frame, to: peer, mode: .unreliable)
        return true
    }

    func ackReceived() {
        readyToSend = true
    }
}
```

### Phase 7: Remove Internalized Theater Code
**Status: DONE (PR #137)** — `RemoteCam/Theater/` deleted; `Try` relocated
to `RemoteCam/Try.swift` (still the `MultipeerServiceProtocol.send` return;
a `Result` conversion is a trivial follow-up).

- Delete `RemoteCam/Theater/` directory (Actor.swift, ActorSystem.swift, etc.)
- Replace `Try<T>`/`Success<T>`/`Failure<T>` with Swift `Result<T, Error>`
- Replace `Weak<T>` with direct `weak` references
- Remove `!` operator, `^`/`^^` operators, `Receive` typealias
- Remove `ActorRef`, `ActorPath`, `ActorSystem`, `TestActorSystem`

## Interlude: capture-stack threading fix (PR #137)

Done ahead of Phase 4 so the rewrite lands on a race-free capture stack:

- `CaptureEngine.sessionQueue` owns ALL session/device configuration and
  engine control state. Synchronous `CameraControlling` entry points hop in
  with `.sync`; nothing on the queue ever syncs back out (asserted with
  `dispatchPrecondition`), so no cycle can form.
- Video AND audio sample buffers deliver on one `dataOutputQueue`, which owns
  every byte of recording state — this structurally eliminated a double
  `StartRecordingVideoAck` race between the old separate delegate queues
  (now pinned by `testRecordingStartAcksExactlyOnce`).
- The only cross-domain values (fps, camera position, rig orientation,
  `isRecording`, camera mode) live in `Locked<T>` boxes; frame routing is by
  output identity instead of reading config-owned connections per frame.
- These boundaries are the pre-actor shape on purpose: `sessionQueue` is the
  isolation domain a future `actor CaptureEngine` formalizes. When Phase 4
  makes the camera states async, the `.sync` wrappers become `await` calls
  and the `Locked` boxes dissolve into actor-isolated state. The per-frame
  trio (fps/position/orientation) stays lock-boxed permanently: the
  AVFoundation delegate path is queue-delivered, and the app is staying
  below the iOS 17 floor that queue-backed actor executors would require.
- Thread Sanitizer runs clean over the FULL suite (Phases 4–7 removed the
  Theater races — `Stack.head()`, `Actor.actorForRef` — that had blocked
  whole-suite TSan).

## Wire Protocol Compatibility

Messages are serialized as FlatBuffers (`RemoteCmdFlatBuffers.swift`,
schemas in `FlatBufferSchemas.fbs`); the wire format is independent of the
actor framework and unaffected by this plan. The loopback test suite passes
every message through the real encode/decode path.

## Key Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Wire protocol breakage | HIGH | Keep RemoteCmd NSCoding classes unchanged |
| State machine regression | HIGH | Expand test coverage before Phase 4 |
| Memory management changes | MEDIUM | Swift actors manage lifetime automatically |
| UI timing changes from async `^{}` | LOW | Validated in Phase 2; main queue is FIFO |

## Current Test Coverage

396 tests. The Phase 4 prerequisites called out by earlier revisions of this
plan are met: the loopback suite (`LoopbackSessionTests`) runs two full
session state machines against each other through the real FlatBuffers
encode/decode — role handshake, the complete two-device photo capture,
flash/camera/zoom/lens round trips, the 3-step video stop protocol, and
peer-disconnect pops — and is the behavior gate for the Phase 4 rewrite.
State tests cover the camera, monitor, and watch state families;
`FrameSenderTests`/`FrameStreamingTests` cover back-pressure; snapshot tests
pin both screens' chrome.
