# The Camera Control Plane

How a remote changes a camera's settings and how it learns what the camera
is doing. Every control command is answered exactly once, with the camera's
whole state; nothing on the remote is guessed from a tap. Companion to
`Docs/multicam.md` (the rig and synced capture) and `Docs/ARCHITECTURE.md`.

## Two properties

1. **One truth per camera.** The director holds one `CameraCapabilitiesResp`
   per lane — what the camera has (devices, lenses, ranges, quality menus)
   and what it is doing (active device, lens, zoom, torch, flash, quality,
   aspect, preview mode). Every displayed control is a pure read of it.
   Recording truth rides its own channel, `CameraStateReport` (elapsed ticks
   the camera drives), and is not part of this document.
2. **One answer per command.** A control command is answered exactly once.
   The remote can always say, for any command it sent: it never left, it was
   applied, it was refused and why, or the camera did not answer in time.

## Messages

| Kind | Direction | Rule |
|---|---|---|
| Control command: `SetZoom`, `SwitchLens`, `ToggleFlash`, `ToggleTorch`, `ToggleCamera`, `SelectCameraDevice`, `SetVideoQuality`, `SetPhotoQuality`, `SetAspectRatio`, `SetCameraPreviewMode` | remote → camera | answered by exactly one `CameraCapabilitiesResp` |
| `CameraCapabilitiesResp` | camera → remote | the camera's full state; `inReplyTo` names the command it answers, `error` says why it was refused (nil = applied) |
| `RequestCameraCapabilities` | either | the remote asks for a push; the rig sends it to its own coordinator to push after a change it made itself |
| `FocusAtPoint`, `TimerCountdown` | remote → camera | fire-and-forget by design: a tap-to-focus already shows its reticle; a countdown tick is a broadcast |

On the wire every reply is a `CameraStateResponse` whose `action` is the
command's own action and whose `current_state` + `capabilities` carry the
state. The same shape under `RequestCapabilities` is the unsolicited push:
link-up, hotplug, watchdog fallback, a local device pick or preview toggle on
the camera. There is no other camera → remote control message.

## Camera side

`SessionCoordinator.handleControl(_:phase:)` is the one handler, reached from
every camera state's `default:` before the root handler, so no control
command can fall into the root handler's silent drop. It answers with
`replyWithState`, which gathers the state once (`gatherCurrentCameraCapabilities`,
one session-queue hop; the cached hardware matrix is refreshed first only for
a device switch) and tags it with the action and the refusal.

The phase policy, `controlRefusal(_:phase:)`, is a table:

| Command | idle | taking picture | recording | transmitting video | not a camera |
|---|---|---|---|---|---|
| SetZoom, SwitchLens, ToggleTorch, SetPhotoQuality, SetAspectRatio, SetCameraPreviewMode | applied | busy | applied | applied | refused |
| ToggleFlash, SetVideoQuality | applied | busy | recording | recording | refused |
| ToggleCamera, SelectCameraDevice | applied | busy | recording | busy | refused |

A refusal still carries the full, unchanged state, so the remote's controls
reset to truth in the same message that explains why. A device switch
confirms frame delivery (up to 4 s) before it answers; landing back on the
previous device after the confirm is answered as a failure, never as a
no-op success.

## Director side

`MulticamController.sendControl(action, msg, to:)` is the one gate every
control command leaves through. The lane (`CameraLink.pending`) counts the
send per action until:

| Event | Effect |
|---|---|
| the transport refuses the send | count unchanged, transient error "couldn't reach the camera" |
| a `CameraCapabilitiesResp` with that `inReplyTo` lands | count − 1; state absorbed; `error` shown as a transient error naming the camera |
| 10 s pass (`MCControlTimeout`) | count − 1; transient error "didn't answer"; last state stands |
| the lane is removed | its counts go with it |

Nothing is remembered from the tap. `MulticamLaneInfo` derives torch, flash
and zoom from the lane's last state, and `inFlight` from the counts; the
focused chrome disables a control while its command is in flight (the switch
control shows its switching state), never pre-tints it. The rig's capture
state machine is untouched by control traffic, so a control command can never
block a take and a take can never block a control.

Rig settings (`activeAspectRatio`, `rigPreviewMode`, the qualities) remain
director intents fanned out to every lane. They are re-applied to a camera
from what it **reports** — a lane whose state shows a different aspect or a
preview mode the rig has set to standby gets the command again — so a reply
that confirms the setting never re-triggers it (no request/reply loop) and a
camera that resets on its own is brought back in line.

Clock probes and preview-tier pushes happen only on an unsolicited state
(`inReplyTo == .requestcapabilities`), i.e. link-up and re-advertisement,
not on every reply.

## Tests that pin it

- `LoopbackSessionTests.testEveryControlCommandIsAnsweredInEveryCameraPhase` —
  the reply matrix: every control command, idle and recording, exactly one
  reply with the policy's outcome.
- `LoopbackSessionTests` happy paths — each command's reply carries the
  camera's value (flash mode, lens, zoom, device list, preview mode) and lands
  on the lane; the pending count returns to zero.
- `MulticamControllerTests.testTorchWaitsForTheCamerasAnswer`,
  `testControlSendFailureIsReportedAndNotLeftInFlight`,
  `testUnansweredControlExpiresWithAnError`,
  `testRigSettingIsReappliedOnlyWhenTheCameraReportsOtherwise`.
- `RemoteCmdSerializationTests.testControlReply_roundTripsActionRefusalAndLiveState`
  plus the 12.0.0 handshake golden bytes, which must never change.

## Wire rules

`CommandAction` numbers and the field slots of `CommandParameters` and
`CameraStateResponse` never move (the version handshake rides them). Retired
fields are `(deprecated)`; flatc requires a deprecated field's type to stay
declared, which is why `ZoomRange` is still in the schema. Everything else
may be deleted. A wire change that older builds cannot follow is an app major
bump: 13.0.0 introduced this contract, and a 12.x peer completes the version
exchange and is told to update.

## Next

Manual exposure and Cinematic video (#206) add one command each and one
optional block each to the state; capability is the block's presence, the
same gate `camera_devices` already is for `SelectCameraDevice`. A rig-wide
photo/video mode command would let Cinematic be refused in photo mode with
the same policy table.
