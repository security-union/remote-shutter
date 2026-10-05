# SessionModel

The session logic as one state machine: pairing, roles, taking a picture and
recording a clip, for both devices. `sessionStep` is a pure function, the
checker explores it, and `session-runner` lets you walk it by hand.

There is one machine here, not one per role and not a correct copy beside a
broken one. Two devices run the same function and the role splits them, which is
how the app works: both sides are a `SessionCoordinator`.

## Run it first

```bash
make model      # the checker over every world, about three seconds
make runner     # walk the machine yourself
make rig        # a remote and two cameras, nothing paired yet
make demo       # replays pairing, a photo, and a clip
```

`--multicam` starts from a remote that already holds both cameras, which is the
starting point when the question is about a take rather than about how the rig
got assembled.

`make runner` drops you into this:

```
  camera   scanning  camera
  remote   scanning
  budget   invites 1, shutter 1, recordings 1, stops 1, goodbyes 1, drops 0

  you
    1  remote invites camera
```

Every move offered comes from `SessionWorld.choices`, which is the same function
the explorer calls to decide what to try next. So walking this by hand walks the
graph the search walks, one edge at a time. Press `c` at any point and the world
you have reached is handed to the checker, which explores everything reachable
from there.

## The conversation, drawn as you walk

Every move adds a row to a sequence diagram, so the protocol draws itself:

```
     you      remote     camera
      ├──────────▶          │        invite camera  inviting
      │          │          ●        link up with remote
      │          ◀╌╌╌╌╌╌╌╌╌╌┤        peerBecameCamera  queued
      │          ◀──────────┤        peerBecameCamera
      ├──────────▶          │        press the shutter  watchdog#1 armed
      │          ├╌╌╌╌╌╌╌╌╌╌▶        takePic(sendMediaToPeer: true)  queued
      │          ├──────────▶        takePic  alert up, camera: take picture
      │          │          ●        picture captured  alert down, saved
      │          ◀╌╌╌╌╌╌╌╌╌╌┤        takePicAck  queued
      │          ◀──────────┤        takePicAck  ignored
      │          ◀──────────┤        takePicResp(carriesMedia: true)  saved
```

Three things in that picture are deliberate.

**A send and its delivery are two rows.** Dashed when the message is queued,
solid when the receiver actually steps on it. The dashed arrows piling up and
then landing in the order you chose is the checker's whole idea, done by hand.

**The transport's news is a mark on one lifeline**, not an arrow from the peer. A
dropped link is the transport telling one device something; drawing it as an
arrow said the peer sent its own disconnection.

**The notes are what a person would notice**: an alert going up, a photo saved, a
watchdog armed, a message ignored. They are the effects, named in the words of
somebody holding the phone.

`d` prints the whole diagram plus its Mermaid source, which is how a walk ends up
in a document or an issue:

```
sequenceDiagram
    participant you
    participant remote
    participant camera
    you->>remote: press the shutter [watchdog#35;1 armed]
    remote-->>camera: takePic(sendMediaToPeer: true) [queued]
    remote->>camera: takePic(sendMediaToPeer: true) [alert up, camera: take picture]
```

Other keys: `u` undo (the diagram rewinds with it), `r` one random move, `a`
twenty random moves, `h` the history of what you picked, `q` quit.

Two things make a walk worth keeping. `--script "shutter on remote; deliver takePic"` replays one by move name rather than by number, because numbers shift
whenever the model changes and names do not. And random moves run off a seed
that is printed on startup, so `--seed 42` walks the same way twice: an
unrepeatable walk that broke a rule is a story, a seed is a bug report.

## The actors

Three, and the first one is not a machine.

**You** are the environment. The taps are moves the world offers: invite,
shutter, record, stop, leave. Most of the interesting orders in a session are
the world's rather than the app's, so the person belongs on the same list as the
link and the hardware.

**The remote** holds `.connected` with `role: .remote` and drives the camera. In
the app this is the director.

**The camera** holds `.camera` and its capture phases. It is a server: it keeps
its post through a peer drop and settles when the hardware answers. It serves
one remote.

**The other cameras**, with `make rig` or `--multicam`. A remote holds as many
cameras as the person connected, so one shutter tap is a command to each of
them and the take stays outstanding until the last one reports. That is the
only difference between the one-camera case and the rig.

The link, the capture hardware and the ten second watchdog are also in the
environment, which is where the orders nobody enumerated come from.

## What is modelled

| Part of the protocol | What the model carries |
|---|---|
| Pairing | an invite, then each end learning the link came up separately, because in a real session they do; a remote keeps browsing while connected, which is how the second camera joins |
| Roles | the camera announces itself with `peerBecameCamera`; the other side learns it is the remote |
| Photo | shutter, the ten second watchdog with its generation, the capture answering either way, the ack and the response |
| Video | record, stop, and the transmit phase the camera holds until the receiver echoes |
| Leaving | a deliberate goodbye, a send that died on a live link, and a link that went away by itself |

Not modelled, deliberately: anything with an identity or a lifetime. The camera
rig, the lobby, the alert handle, the two `Task` values, the real metadata. The
model carries the fact that an alert is up; the app carries the alert.

The app has not caught up with the multi-peer part yet: `SessionCoordinator`
holds one `link`, and a remote driving several cameras is `MulticamController`,
a second machine. So the shadow projects a single peer, and the model is ahead
of the app here on purpose. That is the direction this is supposed to run: the
model describes the protocol, the app grows into it a slice at a time.

## The rules

In `Sources/SessionWorld/SessionRules.swift`. Five sentences and one about a
step, in the order they pay off.

| Rule | Catches |
|---|---|
| An alert is up only while taking a picture | the stranded "Taking picture" modal, which had two doors out of a capture that never dismissed it |
| Two paired devices never both hold the camera | both devices answering the shutter and neither showing a preview |
| A camera serves one remote | two remotes driving one camera, where each sees half a session |
| The remote never believes recording while the camera is idle (terminal) | the two devices disagreeing after the dust settles, which no unit test can express |
| When nothing more can happen, nothing is left outstanding (terminal) | a photo that arrives in a phase which ignores it, which is lost data rather than a broken state |
| No camera is left waiting to transmit (terminal) | the camera wedged in `.cameraTransmittingVideo`, where every capture command is refused, because the echo never came |
| A timeout for a stale generation changes nothing (a step) | a late watchdog killing the state that replaced the one it was armed for |

Terminal rules are checked only where nothing more can happen. That is also why
only the first one runs in shadow mode on a device: a running app never reaches
quiescence, so there is no moment at which to ask the others.

## The worlds, and what each costs

Every number here is from `make model`, which asserts them.

| World | Worlds | Depth |
|---|---|---|
| Pairing, one photo, one goodbye | 301 | 12 |
| Two captures in a row | 1,188 | 16 |
| Recording and transmitting | 150 | 11 |
| A photo, a clip, a goodbye and a dropped link | 51,713 | 20 |
| Assembling a rig of two cameras | 139 | 8 |
| One tap, two cameras | 495 | 10 |
| A camera dropping out of a take | 2,613 | 11 |

The role pickers as a configuration space, four worlds, is the one worth
reading:

| Roles | Worlds | Why |
|---|---|---|
| camera and camera | 1 | nothing can happen: a camera advertises, and only a browsing device invites, so two cameras never pair |
| camera and undecided | 301 | the real configuration |
| undecided and undecided | 15 | they can invite each other and no camera ever appears |

## Two things this got wrong, both found by the checker

**A configuration is not a move.** The first version let a device claim the
camera role after pairing, and the checker immediately produced two devices both
holding the camera. In the app the role is a constructor argument to the scanner:
you pick it on the picker screen, before a session exists. Offering it as a move
invented a race the app cannot have. Role configurations are separate worlds now,
which is the right way to check a configuration space.

**Every repeatable action needs a budget, including the ones that look
harmless.** Stop had none. A person could press stop forever, each press arms
another watchdog, `timeoutGeneration` climbs without bound, and an infinite state
space wears a finite model's clothes. The search then stopped at its world limit
and reported that every rule held, which is the one result that must never be
read as a pass. `testAnUnboundedBudgetIsReportedRatherThanPassed` pins that the
report says so, and the runner prints "this is not a proof" in red.

## Changing it

Add a rule when you find yourself writing a comment that says "this must always
be true". That comment is a sentence, and a sentence can be checked.

Keep every field of the state plain data, or worlds cannot be compared and the
search cannot terminate. Keep every environment action bounded, and read the line
saying whether the search finished before believing a pass.

One more constraint, from shadow mode: every field of the state should be
derivable from what the app already holds. A field the app cannot produce cannot
be resynchronised, and a model needing state the app does not keep is usually a
sign the app is deciding on something it never wrote down.

## Shadow mode

`SessionShadow` is the app-facing half: which rules run against reality, how a
divergence reads, and a factory the coordinator calls in one line. The switch is
`SessionDebug.attachModelShadow(to:)`, called from the scanner, Debug builds
only, and `testDeviceScannerSwitchesOnTheModelShadow` keeps it switched on.

Ownership is by phase, not by message type. `popToScanning` stops at the lobby
floor for the lobby and Watch phases, so a model that owned `EndSession`
everywhere would decide wrongly outside this slice. `modelOwnsPhase` is that
list.

It has already paid for itself once: a disagreement about `captureOutstanding`
after a teardown turned out to be a photo being dropped when a session ended
mid-capture, which nobody had found by reading. That story is in
`Docs/correcto-integration.md`.
