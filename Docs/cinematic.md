# Cinematic Video

Cinematic is Apple's fake shallow depth of field for video. The phone measures
depth on every frame, keeps the subject sharp and blurs the rest, and iOS 26
opened it to apps like ours. This page covers what the hardware does, the two
kinds of file it can produce, and how the director drives it. Companion to
`Docs/control-plane.md` and `Docs/pro-controls.md`.

## What the hardware does

Everything here was measured on an iPhone 14 running iOS 27 with the probe in
`RemoteCamTests/CinematicProbeTests.swift`, not read off a slide.

| Fact | iPhone 14 |
|---|---|
| Cameras with Cinematic formats | back Dual Wide, front TrueDepth. The plain wide and ultra wide have none. |
| Formats | 1080p and 4K, 24 to 30 fps |
| Simulated aperture | f/2 to f/16, default f/2.8 back, f/4.5 front |
| Zoom | pinned: 2.0 on the Dual Wide (its 1x lens), 1.0 on TrueDepth |
| Turning it on | about 0.9 s of pipeline rebuild, then frames flow again |

Two rules bit us and are worth knowing before touching the engine. The
input's `isCinematicVideoCaptureSupported` reads the *committed* session, so
the Cinematic format commits on its own first. And when the effect goes on,
the metadata output's types must already be the required set in the same
commit, or AVFoundation throws.

While the effect is on, `focusMode` belongs to Cinematic. Writing it throws,
so taps become Cinematic tracking focus. Manual exposure is off too: it hops
to a physical lens, and no physical lens has Cinematic formats. Cinematic
returns exposure to Auto and keeps the EV bias.

If the camera the user picked has no Cinematic formats (the front camera the
engine opens is the plain wide one), the session runs on its sibling that
does, the same way Manual exposure hops lenses. The chosen camera stays the
logical one, so the flip, the picker and the state reply never see the hop.
A Pro phone opens the Triple camera; if that has no Cinematic formats the
policy picks the Dual Wide sibling. That choice is table-tested, not yet
measured on a Pro phone.

## Two kinds of file

The example I give people is a printed photo versus its RAW file. A print
looks right everywhere and you can't change it. A RAW keeps what it needs to
be developed again, but only software that understands it can develop it.

Cinematic has the same split, and the director picks one per camera:

- **Blur in video** (the print). Our asset writer records the frames the video
  data output delivers, and those frames already carry the blur. Every player
  shows it: CapCut, Resolve, VLC. Multicam sync, aspect crops and the live
  preview are untouched.
- **Editable in Photos** (the RAW). `AVCaptureMovieFileOutput` records the
  clean video plus a disparity track and two Cinematic metadata tracks. Photos,
  iMovie and Final Cut render the blur and let you move focus after the take.
  Everywhere else the video is sharp. It records 16:9 only, because the
  metadata describes the full frame.

One or the other, never both. Writing two files per take would double the
storage and the transfer for a choice the person already made.

iOS 27 can also write the editable metadata through an asset writer, but the
iPhone 14 reports `isCinematicVideoMetadataCaptureSupported = false` on every
format, so that path is left for hardware that has it.

## The director

A **CINEMATIC** tile appears in the rig tray, in video mode, when the focused
camera reports a `CinematicState`. Turning it on adds the **APERTURE** ruler,
which is the same `RulerPill` as zoom and exposure, and an **EDIT IN PHOTOS**
tile for the editable file. The ruler dims while recording because the camera
refuses aperture changes mid-take.

With Cinematic on, the camera streams what it detects (faces, bodies, pets)
about ten times a second. The director draws a box per subject over the
preview, gold for the one in focus, solid when locked and dashed when the
camera may move on. Tap a box to lock on it, tap anywhere else to track that
spot, long-press to hold focus at that distance. Focus works during a take,
which is the point of a focus pull.

The quality and aspect menus only offer what the camera can do while
Cinematic is on, so the director never asks for something the camera would
refuse. Editable Cinematic holds the rig at 16:9.

On the camera phone a `CINEMATIC f/2.8` chip shows the effect is on, and
"More light needed" appears when the camera reports a dark scene.

## Wire

| Addition | What it carries |
|---|---|
| `SetCinematic = 35` | on/off, aperture (0 = keep), output. Answered with the full state, like every control command. |
| `SetCinematicFocus = 36` | a subject id, a tracked point, or a fixed point. Fire-and-forget like `FocusAtPoint`. |
| `CinematicSubjects = 37` | camera to director, `.unreliable`, only while the effect is on: boxes in upright display space and the light warning. |
| `CinematicState` in `CameraState` | enabled, output, aperture and its range, the resolution/fps pairs Cinematic allows. Present means capable. |

Phase policy: `SetCinematic` applies only when the camera is idle. Focus
applies idle and while recording. `CinematicPolicy` holds the rules both
sides read (aspect per output, qualities while on), so the camera's refusal
and the director's menu can't disagree. The app is 13.2.

## Multicam sync

Both files carry the sync anchor. Both also record `firstFrameOffsetMillis`:
how long after the shared anchor this camera's first frame was captured, from
the first sample's timestamp on the writer path and from the movie output's
`startPTS` on the editable path. An editor trims each angle by that much and
every clip starts at the same instant. The editable file takes its metadata
before recording starts, so its offset lives in the JSON sidecar next to the
clip instead of inside the .mov.

## Hardware tests

`CaptureIntegrationTests` drives the real rig on a phone: enable, aperture,
frames keep flowing, the front flip hops to TrueDepth, photo mode suspends
the effect, the editable output attaches the movie output, and turning it
off restores the quality setting. `CinematicProbeTests` is the raw probe
that produced the table above; run it on new hardware before trusting the
table for that model.
