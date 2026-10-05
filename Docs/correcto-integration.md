# Correcto Integration

How `SessionCoordinator` becomes a checked state machine without a rewrite and without
betting a shipped app on one. Companion to `Docs/ARCHITECTURE.md` (what the app is) and
`Docs/control-plane.md` (how a remote changes a camera).

Correcto lives at `../correcto`. Its design is in that repo's `docs/DESIGN.md`; shadow
mode, which phase zero below depends on, is in its `docs/SHADOW-MODE.md`.

**Status.** One machine, checked, walkable, and running beside the app in Debug builds.

`SessionModel/` holds a single model, `SessionDevice`: pairing, roles, the photo round
trip and the video round trip, for both devices. Two devices run the same function, which
is how the app works. `make model` checks it over every world a person can drive, in about
three seconds. `make runner` lets you walk it by hand, three actors on screen, with the
same moves the checker enumerates; `c` in the runner hands whatever world you reached to
the checker. `SessionModel/README.md` is the onboarding document.

The deliberately broken copy that used to live beside the model is gone. It answered one
question, "can the search find defects we already know about", it did, and that is recorded
below. A second machine in the repository is the drift this method exists to remove.

**Status of phase zero.** Done and switched on. Three defects found, reproduced and
fixed; the photo slice is modelled and checked in `SessionModel/`; and the model now runs
beside the coordinator in every Debug build, attached at the scanner's composition root by
`SessionDebug.attachModelShadow`, deciding nothing. `SessionCoordinator.handle` observes
every message and reports where the model and the app disagree. Start at
`SessionModel/README.md`, the onboarding document: how to run it, the machine as a
diagram, and how to read a counterexample.

It has already paid for itself. A fourth defect, of the same family as the lost photo and
through a door nobody had listed, came out of the shadow disagreeing with the coordinator
rather than out of anyone reading the code. See "What the shadow found" below.

One gap is left before phase one: the shadow is a no-op in Release, so the evidence comes
from development runs and not from App Store sessions.

## Why

Not theory. Reading the coordinator with a checker's rules in mind, and then writing the
sequences as tests, produced three defects that reproduced on the simulator. All three
are fixed in this change; the tests that found them are now regression tests.

| Defect | Sequence | Was | Fix |
|---|---|---|---|
| Orphaned alert | capture, then `EndSession` or any failed send | the modal stayed up, and `alertHandle` was never cleared so a later capture orphaned it for good | `transition(to:)` takes the alert down when leaving `.cameraTakingPic`, whichever door it leaves by |
| Lost photo | capture outlives its 10s watchdog, bytes arrive after | `inCamera` had no `OnPicture` case and the photo was dropped | `inCamera` saves it, the way the Watch path always has |
| Stale multicam identity | any multicam take, then any later ordinary clip | the clip went out as `RS_session-_capture-_cam2.mov`, 2s late from the old camera index, and the monitor dropped it so the camera never left `.cameraTransmittingVideo` | an ordinary recording clears the slot on start, and `popToScanning` clears it when the session ends |
| Lost photo, teardown door | capture, then a goodbye or a failed send, then the bytes arrive | `.scanning` had no handler for a picture, and `popToScanning` cleared `captureOutstanding`, so the app forgot a capture the hardware was still working on | `handleRoot` saves a picture whenever one is outstanding, and the teardown stops clearing the flag |

The first two were the same story: one code path learned a lesson its sibling never did.
`pendingSyncMetadata` was cleared in three places and `pendingVideoSyncMetadata` in none.
The Watch saved a late picture on purpose and the phone dropped it. Writing the rule down
is what stops that recurring, because the rule is now checked rather than remembered.

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

This is the code, as it now stands in `SessionCoordinator.handle`:

```swift
let shadowEvent = shadow == nil ? nil : photoEvent(for: msg)
await handleLegacy(msg)
await shadow?.observe(event: shadowEvent, observed: projectPhotoState())
```

And this is the projection, in `SessionShadow.swift`. The phase needs no mapping at all,
because the coordinator and the model share one `SessionState`; what is left is the handful
of flags the enum does not carry.

```swift
func projectPhotoState() -> PhotoState {
    PhotoState(
        phase: state,
        linked: currentPeer != nil,
        alertUp: hasCameraAlert,
        captureOutstanding: captureOutstanding,
        timeoutGeneration: timeoutGeneration)
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

### Switching it on

A shadow nobody attaches observes nothing. `startShadowingPhotoSlice` existed for a while
with only tests calling it, so the app carried the machinery and none of the evidence.
`SessionDebug.attachModelShadow(to:)` is the switch, called once from
`DeviceScannerViewController.viewDidLoad`, and `testDeviceScannerSwitchesOnTheModelShadow`
is what keeps it on. The scanner is the only screen that gets it: the Watch path runs
states the slice does not model yet, so a shadow there would report noise on every message.

### What it does not see

**Release builds carry no shadow.** `SessionDebug` is a no-op in Release, like every other
tap in that file, so the cost in a shipped build is exactly zero and so is the evidence.
Development and simulator runs are what report today. Collecting a release cycle of real
sessions needs a Release-safe channel, which is a separate decision rather than a
consequence of this one.

**Release builds carry no shadow** is now the only one left. The other gap, a failed send
the shadow could not see, is closed; how it was closed is worth reading before phase one,
because it is the shape phase one uses.

### Some events are not messages

A handler that sends a reply and finds the link dead has taken a second step, and nothing
delivered it. `sendOrGoToScanning` detects the failure, pops to scanning and returns false
so its caller stops transitioning. The model has a name for that step, `sendFailed`, and it
matters: the orphaned alert left by that door as well as by `EndSession`.

The obvious fix is to make the failure a message through the inbox, and it is wrong. The
pop happens synchronously today and callers depend on the return value in the same breath
(`guard await sendOrGoToScanning(...) else { break }`). Queuing it would let the caller keep
transitioning while the teardown waits its turn, which is a behaviour change, in the failure
path, in a shipped app.

So the failure records itself instead:

```swift
if shadow != nil { inlineModelEvents.append(.sendFailed) }
await popToScanning()
```

and `handle` gives the shadow the message's own event followed by whatever the handler
decided inline:

```swift
let events = (shadowEvent.map { [$0] } ?? []) + inlineModelEvents
await shadow.observe(events: events, observed: projectPhotoState())
```

`ShadowRuntime.observe(events:observed:)` steps them in order and compares once at the end.
Feeding it only the first event would report a disagreement that is really the shadow not
having been told, which is the worst kind of noise: it looks like the model is wrong.

Two things this buys beyond the alert door. The buffer is exactly what phase one needs, and
for the same reason: when the slice goes live, these are the events `step` is given, in this
order. And it generalises, because every inline decision the model names as an event can
record itself the same way, one at a time, with the shadow saying whether the naming was
right.

The assumption it rests on is the one phase zero already rests on: the inbox pumps one
message at a time and awaits each fully, so nothing interleaves between the buffer being
cleared and being read. `SessionCoordinator.init` has the only pump and it is a single
`for await`. Re-check this if that ever changes.

### What the shadow found

The fourth defect in the table is the first one no person found. It came out of a test
asserting the shadow agreed with the coordinator through the failed-send door, which it
did not:

```
model disagreed on sendFailed: predicted scanning, app reached scanning
```

The phases matched. The disagreement was `captureOutstanding`: the model said a capture the
hardware had not answered yet was still outstanding, and `popToScanning` said it was not.
Chasing which one was right is the whole story. `.scanning` had no handler for
`UICmd.OnPicture`, so a goodbye during a capture dropped the person's picture, and the
cleared flag is what made the drop invisible. The watchdog door had been fixed weeks
earlier. The teardown door had not, and it is the same lost photo.

`testPictureArrivingAfterATeardownIsStillSaved` reproduces it on the simulator: saved 0,
expected 1. The fix is one handler in `handleRoot` guarded by `captureOutstanding`, and one
deleted line in `popToScanning`.

Two things worth taking from this.

The model was more general than the app, and being more general is what made it right. It
said "a capture answers in a phase that stopped waiting for it" where the app had listed
the phases it could think of. The model now says it in one case rather than two, because
naming the doors was the mistake.

And the first report was nearly useless: "predicted scanning, app reached scanning" is true
of the phase and silent about the field that differed. `PhotoShadow.differences` now names
every field that disagrees. A shadow whose reports cannot be read is a shadow that gets
ignored, and then the whole exercise is theatre.

The same lesson cost a rule. The shadow's runtime list held "a capture is outstanding only
while taking a picture or just after", which sounds right and is false: a capture outlives
its phase whenever the hardware is slower than the session. Once the app stopped forgetting
in-flight captures, that sentence would have reported on every teardown. It is gone, and
what replaced it is nothing, because the rule that catches a lost photo needs quiescence and
a running app never reaches it. That one belongs to the checker, and the split is worth
knowing before you write a list: a runtime rule has to be true of one state at one instant.

## Walking it by hand

`session-runner` prints the world, lists every move the environment offers, and applies the
one you pick exactly as the explorer's own expansion does: step the model, absorb the
effects, write the world back. Nothing about it is a simulator. It is the checker's edge
set with a person choosing instead of a queue.

```
camera   cameraTakingPic(send: true, gen: 1)  camera  paired with remote  alert up, capture outstanding
remote   connected  remote  paired with camera  awaiting picture
timers   watchdog#1 on remote, watchdog#1 on camera
hardware takePicture on camera
```

Moves are grouped by who causes them: you, the peer, the link, the camera hardware, the
watchdog. That grouping is the point. Most of the orders that break software are the
world's, not the app's, and seeing the person on the same list as the watchdog is the
honest picture.

It also draws the conversation as you walk, because the state of each device is only half
the story and what is in flight between them is the other half:

```
     you      remote     camera
      ├──────────▶          │        press the shutter  watchdog#1 armed
      │          ├╌╌╌╌╌╌╌╌╌╌▶        takePic(sendMediaToPeer: true)  queued
      │          ├──────────▶        takePic  alert up, camera: take picture
      │          │          ●        picture captured  alert down, saved
```

A send and its delivery are separate rows, dashed and then solid, which is what makes a
reordering visible rather than described. `d` prints the whole diagram and its Mermaid
source, so a walk can go straight into a document.

Three things it is good for. Driving the protocol to a place you are curious about and
pressing `c`, which explores everything reachable from there. Replaying a sequence by name
with `--script`, which is how a walk goes into a bug report, since names survive changes to
the model and move numbers do not. And watching the rules go red the moment they break.

Two corrections came out of building it, both from the checker rejecting what I had
written.

**A configuration is not a move.** The first version offered "become the camera" as
something a paired device could do, and the checker immediately produced two devices both
holding the camera. In the app the role is a constructor argument to the scanner: you pick
it on the picker screen, before a session exists, so that race cannot happen. Role
combinations are separate worlds now, which is how a configuration space gets checked. The
reading is worth keeping: camera and camera gives one world and depth zero, because two
advertisers never pair.

**Every repeatable action needs a budget, including the harmless looking ones.** Stop had
none, so a person could press stop forever, each press arming another watchdog, and
`timeoutGeneration` climbing without bound. The search stopped at its world limit after
seventeen seconds and reported that every rule held. That is the one result that must never
be read as a pass, and it is now both pinned by a test and printed in red by the runner.

## Phase one: the photo slice

The photo round trip plus losing the peer. Smallest complete loop, spans both roles, and it
contains two of the three known defects, which makes it ground truth.

The model is written and checked, in `SessionModel/Sources/SessionModel/PhotoSlice.swift`.
It differs from the plan above in one way worth recording: there is no private `Phase`
enum. The model's state carries the app's own `SessionState`, so there is one enum for the
coordinator and the checker rather than two that drift.

```swift
public struct PhotoState: Hashable, Codable, Sendable {
    public var phase: SessionState
    public var linked: Bool             // `link` narrowed to what this slice decides on
    public var alertUp: Bool            // `alertHandle != nil`, which lives outside the enum
    public var captureOutstanding: Bool // the app has no such field, and that is the defect
    public var timeoutGeneration: Int
}
```

`alertUp` and `captureOutstanding` are in the state on purpose. They are what make the
orphaned alert and the lost photo expressible as sentences rather than as cleanup calls
somebody has to remember, and neither of them exists in the coordinator as a field today.

Four event sources, which is where the interleavings come from: the person, the peer, the
camera, the watchdog.

What is left before the model decides anything.

1. **One `SessionEffects` performer.** Every `PhotoEffect` needs a home, and the handlers in
   the slice stop calling and start returning. This is the mechanical bulk.
2. **Effects read against the legacy handler by hand.** Shadow mode compares states, not
   effects, so the one thing it cannot catch is checked by a person before the flip.

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
