# Remote Shutter — Architecture

Two Apple devices, one photo shoot: one phone is the **camera**, the other is the
**remote** (monitor). They find each other over peer-to-peer Wi-Fi/Bluetooth
(MultipeerConnectivity), the remote sees a live preview, and every camera control —
shutter, video, zoom, lens, flash, torch, quality — works from across the room.
An Apple Watch can also drive the camera directly (no second phone needed).

## The big picture

```mermaid
flowchart LR
    subgraph Remote["📱 Remote (monitor)"]
        MV[MonitorView<br/>SwiftUI] --> MVM[MonitorViewModel]
        MP[MonitorPresenter] --> MVM
        SC1[SessionCoordinator<br/>Swift actor] --> MP
    end

    subgraph Camera["📱 Camera"]
        SC2[SessionCoordinator<br/>Swift actor] --> RIG[CameraRig]
        RIG --> ENG[CaptureEngine<br/>session + stills + config]
        RIG --> PIPE[RecordingPipeline<br/>asset writer]
        RIG --> STREAM[FrameStreamingCoordinator<br/>preview fan-out]
        STREAM --> FS[FrameSender<br/>back-pressure]
        CS[CameraScreenView<br/>SwiftUI]
    end

    SC1 <-- "FlatBuffers over<br/>MultipeerConnectivity" --> SC2
    FS -- "preview frames<br/>(HEIC/JPEG, unreliable)" --> SC1
```

Every box owns its state and is driven by messages or calls from exactly one
place — there is no shared mutable state between them. The whole suite runs
clean under Thread Sanitizer.

## What happens when you tap the shutter

```mermaid
sequenceDiagram
    participant U as You (remote)
    participant M as SessionCoordinator (remote)
    participant C as SessionCoordinator (camera)
    participant R as CameraRig

    U->>M: TakePicture
    M->>C: TakePic (FlatBuffers, reliable)
    Note over M: → monitorTakingPicture<br/>10s timeout armed
    C->>R: takePicture()
    Note over C: → cameraTakingPic
    R-->>C: OnPicture (photo bytes)
    C->>M: TakePicAck, then TakePicResp + bytes
    Note over C: photo saved to camera roll<br/>→ back to camera state
    M->>M: save to camera roll
    Note over M: → back to monitor state
```

Every command follows this shape: a `UICmd` from the screen, a `RemoteCmd` across
the wire, a state transition on both sides, and a response that pops the transient
state (or a 10-second timeout that pops it anyway).

## The three load-bearing pieces

**`SessionCoordinator`** — a Swift `actor` holding the session state machine as an
enum (~20 states: scanning, connected, camera/monitor families, watch family).
Messages enter a FIFO inbox and are processed one at a time; adding an event the
compiler can't match against every state is a build error. One instance per device;
it owns the transport and routes everything.

**The capture stack** — `CameraRig` bundles three non-UI workers around
`AVCaptureSession`: `CaptureEngine` (configuration + stills, confined to its
`sessionQueue`), `RecordingPipeline` (asset writer + recording state, confined to
the single `dataOutputQueue` that delivers both video and audio frames), and
`FrameStreamingCoordinator` (fans each frame out to the live preview and, while
recording, the pipeline). Queue confinement + a one-way hop rule; the only shared
values are a handful of `Locked<T>` boxes on the per-frame hot path.

**The wire** — `MultipeerService` wraps MultipeerConnectivity; every message is a
FlatBuffers table (`FlatBufferSchemas.fbs`). Control messages ship reliable,
preview frames unreliable with credit-window back-pressure (the camera only sends
when the remote has acked), and finished videos transfer as resources with
progress reporting.

## The screens

Every screen is SwiftUI hosted by a thin `UIViewController` shell (navigation,
permissions, lifecycle only): Welcome → Role picker → Device scanner → then
`MonitorView` or `CameraScreenView`. View models are `@MainActor`-fed
`ObservableObject`s; the camera preview is an `AVCaptureVideoPreviewLayer` backing
a `UIViewRepresentable`.

## Watch mode

The same `SessionCoordinator` runs the watch states with **no transport at all**:
the Watch sends commands over `WCSession`, and instead of responses the phone
pushes a full **state snapshot** after every change (readiness, mode, zoom, lenses,
countdown, events). Snapshots-not-events means a Watch that misses a message is
corrected by the next push.

## Testing in one line each

- **`LoopbackSessionTests`** — two real coordinators wired through an in-process
  transport with real FlatBuffers encode/decode: full two-device flows in CI.
- **Snapshot tests** — both screens rendered to PNGs and pixel-checked.
- **`RecordingPipelineTests`** — synthetic sample buffers through the real frame
  path (including the exactly-one-start-ack guarantee).
- **Thread Sanitizer** — the full suite runs under TSan with zero warnings.

---

*History: how the app got here from a 2015 Objective-C/Theater-actor codebase is
recorded in [MODERNIZATION.md](MODERNIZATION.md) (concurrency) and
[UI_MODERNIZATION.md](UI_MODERNIZATION.md) (UI), kept as worklogs.*
