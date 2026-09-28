# Correcto Integration

How `SessionCoordinator` becomes a checked state machine without a rewrite and without
betting a shipped app on one. Companion to `Docs/ARCHITECTURE.md` (what the app is) and
`Docs/control-plane.md` (how a remote changes a camera).

Correcto lives at `../correcto`. Its design is in that repo's `docs/DESIGN.md`; shadow
mode, which phase zero below depends on, is in its `docs/SHADOW-MODE.md`.

**Status.** The photo slice is modelled and checked in `SessionModel/`, and the checker
finds both known defects from the rules alone. Start at `SessionModel/README.md`, which
is the onboarding document: how to run it, the machine as a diagram, and how to read a
counterexample. Shadow mode and wiring the app target to the package are next.

## Why

Not theory. Reading the coordinator with a checker's rules in mind, and then writing the
sequences as tests, produced three defects that reproduce on the simulator today. They
are in `RemoteCamTests/RemoteCamSessionTests.swift` under `CorrectoReproductionTests`.

| Defect | Sequence | Effect |
|---|---|---|
| Orphaned alert | capture, then `EndSession` from the peer | "Taking picture" stays on screen; `alertHandle` is never cleared, so a later capture orphans it for good |
| Orphaned alert, second route | capture, then any failed send | same, via `sendOrGoToScanning` |
| Lost photo | capture outlives its 10s watchdog, bytes arrive after | `inCamera` has no `OnPicture` case; the photo is dropped |
| Stale multicam identity | any multicam take, then any later ordinary clip | the clip goes out as `RS_session-_capture-_cam2.mov`, delayed 2s by the old camera index, and the monitor drops it, so the camera never leaves `.cameraTransmittingVideo` |

Two of the three are the same story: one code path learned a lesson its sibling never
did. `pendingSyncMetadata` is cleared in three places and `pendingVideoSyncMetadata` in
none. The Watch saves a late picture on purpose, with a test; the phone drops it. Nothing
prevents that recurring, because the rule was never written where a machine could read it.

## What we already have

The expensive part of adoption is done. Most apps have no single place where events are
serialised; this one has `tell` and one FIFO inbox, so there is somewhere to put a `step`.
`SessionState` is an explicit thirteen-case enum, exhaustively matched. `CameraControlling`
and `MultipeerServiceProtocol` are protocols with fakes. 761 tests are the safety net.

Three things are in the way.

1. **Effects are performed inline.** A handler sends, dismisses an alert and transitions
   in one case. This is the mechanical bulk of the work.
2. **Twenty-two stored properties live outside the enum** and get none of its
   exhaustiveness. Most are plain data and can move as they are. Two, `reconnectRetryTask`
   and `cameraTimerTickTask`, are in-flight `Task` values that can never enter a model,
   and `ctrl`, `lobby` and `alertHandle` are references with lifetimes.
3. **There are three machines, not one.** `SessionCoordinator`, `MulticamController` with
   its own five-case state, and a per-camera `CameraLink`. Correcto's world currently
   holds N instances of one model type, so full coverage of all three is blocked upstream.
   The first slice touches only the first machine and is not blocked.

## Shape

The model is plain data: `Hashable & Codable & Sendable`, no references, no lifetimes.

**Peer identity is already solved, by Stormo.** I expected this to be the hard part and it
is not. `RemoteCam/MultipeerCompatAliases.swift` aliases `MCPeerID` to `Stormo.PeerID`,
which is a struct:

```swift
public struct PeerID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let keyHash: Data        // multihash of the peer's P-256 public key
    public let displayName: String  // display only, excluded from equality
}
```

That is exactly `Hashable & Codable & Sendable`, and its equality is the key hash rather
than object identity, so two sightings of one peer are one peer. Stormo did this for
security, to stop a peer impersonating another by choosing its display name, and it
happens to be precisely what a model needs: stable semantic equality, serialisable into a
trace file, representable in the Rust core.

So a peer goes into the model state directly. `PeerLink` holds nothing but a `PeerID` and
an `Int`, so it can conform and move across whole:

```swift
enum PeerLink: Hashable, Codable, Sendable {
    case none
    case inviting(PeerID, attempt: Int)
    case linked(PeerID)
}
```

No stand-in type, no lookup table. This also removes the reason multicam would have needed
one: the model can name four peers by identity rather than by index.

The rule the constraint expresses still stands for everything else in the coordinator.
`ctrl`, `lobby`, `alertHandle`, `reconnectRetryTask` and `cameraTimerTickTask` have
lifetimes and stay in the effect handler; the model carries the fact that they exist, not
the things themselves.

**Narrowing.** A slice takes the enum cases it needs plus the properties those cases
decide on, reduced to what the logic reads. `pendingSyncMetadata` becomes a `Bool`. The
peer becomes `linked: Bool` for the photo slice, since nothing in it decides on identity.

## Phase zero: shadow mode

Nothing changes behaviour first. The model runs beside the real code and reports where
they disagree.

```swift
func handle(_ message: Message) async {
    let event = SessionModel.event(from: message, in: await shadow.state)
    await legacyHandle(message)                          // reality, untouched
    await shadow.observe(event: event, observed: projectForShadow())
}
```

```swift
extension SessionCoordinator {
    func projectForShadow() -> SessionModel.State {
        SessionModel.State(
            phase: SessionModel.Phase(from: state),
            linked: link.peer != nil,
            hasPendingMetadata: pendingSyncMetadata != nil,
            timeoutGeneration: timeoutGeneration)
    }
}
```

Messages the model does not own yet still reach the shadow with a nil event, or its state
falls behind and every later comparison is noise. After each observation the shadow takes
reality's state as its next starting point, so a wrong prediction costs one report rather
than every report after it.

Two hazards specific to this app. The projection must be read with no suspension between
the real handler returning and the comparison; the inbox pumps one message at a time and
awaits each fully, so this holds today and is worth re-checking if the pump changes. And
the shadow must be seeded from a projection, not from the model's initial state.

Shadow mode also checks the rules against observed reality, which needs no correct model
at all. The orphaned alert would have reported from production on the first run.

## Phase one: the photo slice

The photo round trip plus losing the peer. Smallest complete loop, spans both roles, and
it contains two of the three known defects, which makes it ground truth.

```swift
struct PhotoState: Hashable, Codable, Sendable {
    enum Phase: Hashable, Codable, Sendable {
        case camera
        case cameraTakingPic(sendMediaToPeer: Bool, generation: Int)
        case watchCamera
        case watchCameraTakingPic(generation: Int)
        case scanning
    }
    var phase: Phase = .camera
    var linked = false
    var hasPendingMetadata = false
    var alertUp = false
    var timeoutGeneration = 0
}

enum PhotoEvent: Hashable, Codable, Sendable {
    case pressShutter                                  // the person
    case takePicRequest(generation: Int)               // the peer
    case takePicResp(failed: Bool)                     // the peer
    case endSession                                    // the peer
    case pictureCaptured                               // the camera
    case captureFailed                                 // the camera
    case stateTimeout(phase: String, generation: Int)  // the watchdog
    case peerLost                                      // the transport
    case sendFailed                                    // the transport
}

enum PhotoEffect: Hashable, Codable, Sendable {
    case send(PhotoWire, reliable: Bool)
    case armTimeout(phase: String, generation: Int)
    case takePicture(sendToPeer: Bool)
    case saveToLibrary
    case showAlert(String)
    case dismissAlert
}
```

Four event sources, which is where the interleavings come from: the person, the peer, the
camera, the watchdog. `alertUp` is in the state on purpose; it is what makes the orphaned
alert expressible as a rule rather than a cleanup call.

## The rules

In the order they should pay off.

1. A `stateTimeout` whose generation is not the current one changes nothing. A transition
   rule, and the one with the most states to cover.
2. `alertUp` is true only while the phase is `cameraTakingPic`.
3. `hasPendingMetadata` is true only while the phase is `cameraTakingPic`.
4. Every transient phase has exactly one armed timeout carrying its own generation.
5. A `peerLost` or `endSession` from any phase lands in `scanning`, never in a transient
   capture phase.
6. Terminal: when nothing more can happen, no capture is outstanding and unaccounted for.

Rule six is the one that catches the lost photo, and it is worth noting that none of the
first five would have. A list of things that must never be true does not by itself catch
losing data to a message arriving in a state that ignores it.

Budgets to start: one shutter press, one peer loss, one capture outcome per press. Bound
them or the search does not end, and read the line saying whether the run finished or
stopped at a limit before believing a pass.

## Acceptance: passed

The model is not accepted because it compiles. It is accepted when the checker
**independently rediscovers the defects we already found, from the rules alone**. It
does. `SessionModel/` holds the slice; `swift test` there explores it in milliseconds.

Rule 2, an alert is up only while taking a picture:

```
worlds explored: 6, max depth: 2
VIOLATION: an alert is up only while taking a picture
1. press shutter        -> takingPic(generation: 1), alertUp: true
2. peer says goodbye    -> scanning, alertUp: true
```

Rule 6, the terminal one:

```
VIOLATION: when nothing more can happen, no capture is unaccounted for
1. press shutter            -> takingPic, captureOutstanding: true
2. fire watchdog#1          -> camera, captureOutstanding: true
3. capture -> true          -> ignored; the photo is gone
```

Both are the shortest traces that exist, and both match the simulator reproductions in
`CorrectoReproductionTests` step for step. Nobody told the checker which order to try; it
had the rules and the environment.

Two more results worth recording. The generation guard the app already has survives the
same search, as a transition rule, which is the checker agreeing with a decision the team
made years ago. And `PhotoCameraFixed`, the same machine with both defects repaired,
explores 34 worlds to depth 7 with every rule holding and the search finishing rather
than stopping at a limit.

Four tests, 0.003 seconds. That number is the argument for running this in CI on every
commit rather than once.

## After phase one

Each step is chosen for the rule it makes checkable for the first time.

| Step | Adds | Unlocks |
|---|---|---|
| Two: video start and stop | recording phases, `stopGeneration` | only `cameraRecordingVideo` has a tick task armed, the second `if` in `transition(to:)`; and the stale-metadata defect |
| Three: connection lifecycle | `link` cases, retry attempts and delay | a state with no awaited peer never has a reconnect task armed, the first `if` |
| Four: multicam | N peers, collecting, collected peers, invite attempts | the peer-set rules, and the first real pressure on budgets |

Multicam is last because the state space multiplies with peers, so it is where the search
is most likely to stop at a limit. Doing it first would teach the wrong lesson about cost.

Stop after any step and keep what is proved. That is the point of the seam.

## Risks

**The dependency.** Correcto is 0.1.0, unpublished, and its API is expected to move. Pin
to a commit, not a branch. Stay in shadow mode until the model has been quiet for a full
release cycle. Keep the legacy switch until it is provably dead. Abandoning this should
cost one commit, and the seam exists to keep it that way.

**A budget set too small.** A check that passes because it explored four states reads like
a proof and is not one.

**Effects are not compared.** Shadow mode tells you the app reached the state the model
predicted, not that it performed the effects the model returned. Before flipping a slice
live, read its effects against what the legacy handler actually does, by hand.
