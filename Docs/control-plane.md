# The Camera Control Plane

Design for consolidating the pro-controls POC (branch `issue-206`, PR #223)
into one coherent API. Companion to `Docs/pro-controls.md`, which covers the
individual controls; this document covers how they compose.

## Why (the lessons the POC taught)

Every field bug on this branch was the same bug wearing different clothes:
**camera control state is one coupled system, but the code treated it as
independent fragments.**

1. **Constraints couple across controls, and the coupling was hand-wired.**
   Cinematic narrows the zoom range and pins focus; a quality change moves the
   exposure ranges; a device swap changes everything. Each coupling today is a
   manually-placed patch (a `SetZoomResp` republished after `SetCinematic`;
   re-apply calls sprinkled through `swapToDeviceLocked` and
   `setVideoQualityLocked`). Forgetting one is invisible until hardware finds
   it — we shipped three of these in one week (zoom dead under Cinematic,
   flip dead under Manual, Cinematic silently refusing).
2. **Truth is scattered on the wire.** The zoom range alone is constructed in
   five engine sites and carried by four message types (`SetZoomResp`,
   `SwitchLensResp`, `ToggleCameraResp`→capabilities, `CameraInfo.zoom_capabilities`).
   Exposure and Cinematic each add a response type plus capabilities fields.
   The 1:1 monitor and the multicam director stitch these partial updates
   together with two different sets of glue.
3. **A refusal must be a message, not a no-op.** Every silently-absorbed
   failure read as "the button is broken".
4. **Device identity needs one answer.** The Manual lens hop split "the camera
   the user chose" from "the device the session runs" — every identity read
   must go through the logical-device function or a control breaks.

## The design

### One truth type: `CameraControlState`

The camera's complete control-plane truth, produced in exactly one place and
consumed everywhere — app objects and wire table have the same shape:

```
CameraControlState {
    seq                  // monotonic, same stale-drop rule as CameraStateReport
    activeDeviceID       // LOGICAL identity (the Manual hop never leaks)
    mode                 // photo | video
    zoom {
        factor
        min, max         // EFFECTIVE range — already Cinematic-aware
        stops[], wideAngleZoomFactor
    }
    exposure?  { mode, durationSeconds, iso, min/max duration, min/max ISO }   // nil = unsupported
    cinematic? { enabled, aperture, min/max/default aperture,
                 apertureLocked, notEnoughLight }                              // nil = unsupported
    focus { supportsPoint, cinematicTracking }
}
```

The example that motivates the shape: *zoom shows the right range under
Cinematic because there is no separate zoom range to go stale.* A monitor
holding the latest snapshot cannot disagree with the camera about any
constraint, because constraints travel together.

### Engine: declarative intents, one reconcile, one snapshot producer

```
CaptureEngine (sessionQueue-confined)
    intents:  ExposureIntent, CinematicIntent          // declarative, survive re-entry
    entry points: setExposure / setCinematic / setZoom / setMode /
                  device swap / quality change
        → mutateControlsLocked { <the change> }        // the ONLY mutation wrapper
            1. run the change
            2. reconcileLocked()                       // fixed order:
                 device identity (Manual hop) → format/Cinematic →
                 exposure → zoom clamp → focus
            3. return controlSnapshotLocked()          // the ONLY snapshot producer
```

Pure, table-tested policies decide; the engine only executes:
- `ExposurePolicy`, `CinematicPolicy` (exist today);
- **`ZoomPolicy.effectiveRange(deviceRange:cinematicRange:cinematicOn:)`**
  (new — the pure core of `effectiveZoomBoundsLocked`).

A refusal is a typed `ControlRefusal` (photo-mode, recording, unsupported,
session-refused) thrown by the reconcile, carried on the wire, and *always*
rendered by the remote (toast on the director, alert on the 1:1 monitor).

### Wire: intents in, snapshots out (append-only; 33/34 are unreleased)

Commands stay small intents — `SetExposure = 33`, `SetCinematic = 34`, and the
long-released `SetZoom`. What changes is the answer:

- **`ControlStateChanged = 35`** (camera → remote) carries the full
  `CameraControlState` plus an optional refusal. It is sent:
  - as the response to 33/34 (replacing `SetExposureResp`/`SetCinematicResp`),
  - unsolicited after any internal event that moves a constraint: device swap,
    quality change, mode change, Cinematic toggle (this deletes the ad-hoc
    zoom republish), recording start/stop (aperture locks).
- Capabilities keep carrying the snapshot so the first exchange seeds it.
- Released peers know nothing of 33–35 (capability-gated), and `SetZoomResp`
  stays for their zoom — no compat cost.

### Remote: one absorb per surface

- 1:1 monitor: `MonitorPresenter.applyControlState(_)` →
  `MonitorViewModel.controlState` (one `@Published`); the per-field fragments
  (`exposure`, `cinematic`, `zoomStops`, `maxZoomFactor`, …) become derived
  reads of it.
- Director: `CameraLink.controlState`, surfaced through `MulticamLaneInfo`.
- All UI derivations are already pure and stay: `MonitorTray.proTiles`,
  `ProSliderScale`, `ZoomScale` — they just read one input. A feature wired
  into the snapshot is automatically on *both* remote screens.

### What this deletes

- 5 `ZoomRange` construction sites → 1 (`controlSnapshotLocked`).
- `SetExposureResp`, `SetCinematicResp`, and the post-Cinematic `SetZoomResp`
  echo.
- The presenter's `updateZoom` / `updateExposure` / `updateCinematic` trio
  (legacy `SetZoomResp` handling stays for released peers).
- Per-field seeding in `seedZoom` / `updateCapabilities` for new peers.

## Tests that pin it

- `ZoomPolicy` table tests (device range × cinematic range × on/off).
- Snapshot FlatBuffers round-trip (+ absent-fields legacy decode).
- Loopback, wire-level: *enable Cinematic → the monitor's zoom scale narrows*
  (the exact field bug, as a regression test); *quality change → exposure
  ranges move on the monitor*; stale `seq` dropped.
- Director: lane absorbs a snapshot; tiles/sliders follow the focused lane.
- Existing policy, tray, and scale tests unchanged.

## Non-goals (tracked, not in this consolidation)

- Torch/flash/timer/aspect migration into the snapshot (settled flows; move
  only when next touched).
- Multicam broadcast of one setting to N cameras.
- Watch surface for pro controls.
