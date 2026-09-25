# Exposure Controls

Shutter speed, ISO and EV bias, driven from the director. Companion to
`Docs/control-plane.md` (how a control command is answered) and
`Docs/multicam.md` (the rig). Issue #206.

## What the hardware offers

Numbers come from the camera, never from constants:

| Control | API | Range source | Where it applies |
|---|---|---|---|
| EV bias (Auto) | `setExposureTargetBias` | `minExposureTargetBias…maxExposureTargetBias` per device (typically ±8; the ruler shows ±2 like Apple) | photo and video, any device that reports a range |
| Shutter (Manual) | `setExposureModeCustom(duration:iso:)` | `activeFormat.minExposureDuration…maxExposureDuration` (about 1/10000 s to 1/3 s, at most 1 s) | photo; video capped at one frame duration |
| ISO (Manual) | same call | `activeFormat.minISO…maxISO` | photo and video |
| Aperture | none on iPhone; `lensAperture` is a fixed f-number | — | not a control (Cinematic's simulated aperture is, see Docs/cinematic.md) |

Support is asked of the device, per Apple's queries. Manual needs
`isExposureModeSupported(.custom)` on the device or one of its physical
lenses. Bias needs a bias range *and* an auto exposure mode to bias
(`.continuousAutoExposure` or `.autoExpose`); the range alone lies. Measured
2026-09-22 with the probe below on a MacBook Pro camera: it advertises a
bias range of ±8, supports no exposure mode at all, and ignores
`setExposureTargetBias` (the value reads 0 two seconds later). With both
queries false it reports no exposure block, so the director shows no
exposure controls for that camera. As a safety net, after applying a
setting the camera compares the device's value to the request and refuses
with "the camera ignored that exposure setting" when it did not land, so a
reply never claims a change the hardware didn't make.

Two limits stated up front. "Long exposure" in the seconds sense does not
exist; the ruler's top is whatever the format reports. And a shutter longer
than one frame lowers the frame rate, so while recording the policy caps the
shutter at `activeVideoMaxFrameDuration` and the clip's rate never moves
mid-take. In photo mode a long shutter may slow the preview, which is the
photographer's choice.

Manual stills are single-frame captures at the chosen settings, without the
multi-frame merging the stock Camera app does. That is what the person asking
for shutter control expects.

## Modes

Two modes, one intent on the engine (`ExposureIntent`):

- **Auto** with an EV bias. The camera keeps choosing shutter and ISO; the
  bias moves its target by that many stops. Bias 0 is ordinary auto.
- **Manual** with a shutter and an ISO. Both are set together (AVFoundation
  requires it); a value of 0 keeps the camera's current one, so a director
  that changes ISO alone sends `(0, iso)`.

Switching to Manual seeds from the camera's current values, so nothing
jumps. Auto returns the device to continuous exposure and restores the frame
rate the quality setting chose. The intent is cleared when the session ends,
like zoom and torch. Nothing is persisted.

## Camera side

- `ExposurePolicy.resolve` is the pure decision: clamp the intent into the
  format's ranges, cap the shutter at the frame duration while recording,
  fall back to Auto on a device that refuses custom exposure. Table-tested.
- `CaptureEngine.applyExposureIntentLocked` is the one place that touches
  the device's exposure. It runs on a fresh intent and again after every
  device swap and quality change, so the hardware always matches the intent
  and the reported ranges are always the active format's.
- **The virtual-camera hop.** iPhones run the Triple or Dual camera so zoom
  can switch lenses, and those refuse custom exposure. Manual hops the
  session to the physical constituent the virtual device is using (decided
  from `constituentDevices`; `activePrimaryConstituent` is nil before the
  session runs), and Auto hops back. The virtual device stays the *logical*
  camera: the flip decides from it, the picker highlights it, and the state
  reply reports it, so the hop never leaks to the director. Automatic lens
  switching is suspended while Manual is on.
- **Tap to focus** keeps working in both modes. In Manual it moves only the
  focus point; the exposure stays custom.
- **The state reply** carries an `ExposureState` block: mode, bias and its
  range, the meter offset, shutter and ISO with their ranges, the frame
  ceiling, and `supportsManual`. Its presence is the capability. Absent means
  this device offers neither bias nor manual, and the director never sends
  `SetExposure` to it. `supportsManual == false` means bias only.

## Wire

`SetExposure = 34`, payload appended to `CommandParameters`
(`exposure_mode`, `exposure_bias`, `exposure_duration_seconds`,
`exposure_iso`). `ExposureState` appended to `CameraState`. No enum number
or field slot moved. The command is answered like every control command, by
the camera's full state under its own action, with a refusal in `error`.
Phase policy: allowed idle and while recording (the policy caps the shutter),
busy while taking a picture, refused outside the camera screen.

A 13.0 peer decodes the new action as Unknown and drops it, and never sends
the block, so the director's gate keeps the command off the wire to it. The
app is 13.1.

## Director side

`MulticamController.setExposure(_:on:)` goes through `sendControl` like
zoom: counted in flight, answered by the state reply, refusals shown as a
transient error naming the camera. `MulticamLaneInfo.exposure` is the lane's
block, from which the screen derives everything.

Exposure is latest-wins, one at a time. A camera applies a setting in a few
frames (up to half a second at a slow shutter) while a drag asks ten times
a second, so while a `SetExposure` is in flight anything newer waits in
`CameraLink.queuedExposure`, folded into one intent by
`ExposureIntent.coalesced` (a queued shutter and a queued ISO both land).
The reply, or the reply deadline, sends it. The camera never works through
a backlog of stale values, so a drag is at most one round trip behind.

### The screen

Off by default. An **EXPOSURE** tile in the rig tray, beside TIMER and
STANDBY, turns the controls on for the director and remembers the choice
(`ExposureControlsPreference`, like the timer). The tile is offered only
when the focused camera reports a block. Turning it off sends Auto to every
camera that is in Manual first, so no camera is left at a fixed shutter with
nothing on screen to change it.

**Nothing is behind a toggle.** Zoom keeps its pill, and every ruler the
camera offers is on screen beside it: EV in Auto, shutter and ISO in Manual.
A small strip carries the one thing no ruler can say: the **AUTO / MANUAL**
switch and the light meter. The meter is a needle over a ±2 stop scale fed
by the camera's `exposureTargetOffset`, one tick per stop with the metered
target taller, the dot gold within a third of a stop of it, and a METER
caption so it reads as an instrument rather than decoration. Each ruler
shows its own value above its track, so the strip never repeats them.

In landscape the exposure rulers stand vertically, one under each thumb,
inboard of the shutter rail: shutter on the left and ISO on the right in
Manual, EV on the right in Auto. In portrait they stack horizontally above
the zoom pill. Either way the zoom pill never gives up its slot.

Every control is at the iOS minimum touch target: `PillCircleButton` is
44pt, the pill is 64pt tall, and the mode switch is a 44pt capsule. The EV
ruler carries a **0** button that resets the bias, committed through the
pill so the thumb snaps back on the tap instead of waiting for the camera.

The rulers are one component, `RulerPill`, the zoom pill's track extracted
and configured by a `RulerTrack`: log2 for zoom, shutter and ISO, linear for
EV. The EV ruler spans ±2 like Apple's dial even when the device reports ±8.

Zoom is continuous and only pulled onto a lens stop near one. Shutter, ISO
and EV click in ⅓ stops like a camera's dials, with a selection haptic per
click, and a drag inside one click sends nothing. The clicks are computed
from the range the camera reports (`RulerTrack.dial`), on the ⅓-stop grid
through 1 s, ISO 100 and 0 EV, plus the camera's own ends when they fall
off the grid. Photography's names ("1/125" for 2⁻⁷ s, "ISO 320") are labels
only; a value off the grid, such as a camera's ISO 34 floor, reads as
exactly what it is.

Each ruler shows the requested value at once and keeps showing it until the
camera reports a value at the same spot (`RulerTrack.matches`), or a second
passes. Replies arrive one round trip behind, so reconciling to any reply
would flick the thumb back to an older ask. Each ruler has its own send
throttle (`ThrottledValueSender`, the zoom pattern). Shutter and ISO each
send only their own component (0 = keep), so dragging one never disturbs
the other.

On iOS 26 and later every pill and the readout strip is the system's Liquid
Glass (`pillGlass()`, interactive), grouped in a `GlassEffectContainer`
(`PillGlassGroup`) so neighbouring capsules share one glass layer. Earlier
systems draw a dark-tinted material with a hairline edge.

The camera device shows "M 1/125 · ISO 400" on its preview whenever it is in
Manual, regardless of the director's preference, so the operator at the
camera sees what was set. It clears when the session ends.

## Hardware probe

`CaptureIntegrationTests.testExposureProbeAppliesAndReportsTruth` runs on a
real camera and skips elsewhere. It prints the advertised block, applies a
bias, applies Manual at 1/250 and ISO 400, checks frames keep flowing, that
the logical device did not change across the hop, that a focus tap keeps
Manual, and that Auto restores the chosen device. The engine also logs a
`🌗 EXPOSURE PROBE` line per position when it scans the hardware matrix.
Measured 2026-09-23 on an iPhone 14, iOS 27, Back Dual Wide Camera: the
virtual device refuses custom exposure (`custom=false`, `continuous=true`,
bias ±8), so Manual hops to a constituent, and it worked: 1/250 and ISO 400
landed with the logical device unchanged, frames kept flowing in Manual and
back in Auto, and a focus tap kept Manual. The bias applied 157 ms after the
call, which is what the completion wait is for. Ranges at 1080p30: shutter
1/66667 s to 1 s, ISO 34 to 3264, frame ceiling 1/30. Still open: the
ranges at 4K and 60 fps, and the Triple camera on a Pro model.

## Tests

- `ExposurePolicyTests` — the clamp table, the recording cap, bias clamping,
  the unsupported fallback.
- `RemoteCmdSerializationTests` — `SetExposure` both intents, the exposure
  block round-trip and its absence.
- `LoopbackSessionTests` — the reply matrix includes `SetExposure`; the
  happy path lands on the fake and on the lane; the gate never sends to a
  camera without the block, and never sends Manual to a bias-only camera.
- `MulticamControllerTests` — the same gate on the director, and the
  in-flight count.
