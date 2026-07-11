# Remote Shutter — Architecture

Two Apple devices, one photo shoot: one phone is the **camera**, the other is the
**remote** (monitor). They find each other over peer-to-peer Wi-Fi/Bluetooth
(MultipeerConnectivity), the remote sees a live preview, and every camera control —
shutter, video, zoom, lens, flash, torch, quality — works from across the room.
An Apple Watch can also drive the camera directly (no second phone needed).

## The big picture

```mermaid
flowchart LR
    classDef actor fill:#7c3aed,color:#fff,stroke:#4c1d95,stroke-width:3px
    classDef swiftui fill:#0ea5e9,color:#fff,stroke:#075985
    classDef viewmodel fill:#a5f3fc,color:#0e7490,stroke:#0e7490
    classDef worker fill:#fbbf24,color:#78350f,stroke:#b45309
    classDef plain fill:#e5e7eb,color:#111827,stroke:#6b7280
    classDef transport fill:#4ade80,color:#14532d,stroke:#166534

    subgraph Remote["📱 REMOTE (monitor)"]
        direction TB
        MView["MonitorView"]:::swiftui
        MVM["MonitorViewModel"]:::viewmodel
        MPres["MonitorPresenter"]:::plain
        SC1{{"SessionCoordinator"}}:::actor
        MPS1["MultipeerService"]:::transport

        MView -. "taps → UICmd (tell)" .-> SC1
        SC1 -- "method calls" --> MPres
        MPres -- "main-thread updates" --> MVM
        MVM -- "@Published" --> MView
        SC1 --- MPS1
    end

    subgraph Camera["📱 CAMERA"]
        direction TB
        SC2{{"SessionCoordinator"}}:::actor
        RIG["CameraRig"]:::plain
        ENG["CaptureEngine<br/><i>sessionQueue</i>"]:::worker
        PIPE["RecordingPipeline<br/><i>dataOutputQueue</i>"]:::worker
        STR["FrameStreamingCoordinator<br/><i>dataOutputQueue</i>"]:::worker
        FSND["FrameSender<br/><i>own queue</i>"]:::worker
        CVM["CameraViewModel"]:::viewmodel
        CSV["CameraScreenView"]:::swiftui
        MPS2["MultipeerService"]:::transport

        SC2 -- "await ctrl.toggleFlash()…" --> RIG
        RIG -- "config / stills" --> ENG
        RIG -- "start/stop recording" --> PIPE
        ENG -- "sample buffers" --> STR
        STR -- "frames while recording" --> PIPE
        STR -- "preview frames" --> FSND
        PIPE -. "acks/responses (tell)" .-> SC2
        RIG -- "@Published state" --> CVM
        CVM -- "renders" --> CSV
        SC2 --- MPS2
        FSND -- "paced frames" --> MPS2
    end

    MPS1 <== "commands + responses<br/>FlatBuffers, reliable" ==> MPS2
    MPS2 == "preview frames<br/>HEIC/JPEG, unreliable" ==> MPS1

    linkStyle 16,17 stroke:#16a34a,stroke-width:3px
    linkStyle 0,11 stroke:#7c3aed,stroke-dasharray:5
```

**Boxes** — 🟪 purple hexagon: **Swift `actor`** (compiler-serialized) ·
🟨 amber: **queue-confined worker** (owns a serial `DispatchQueue`) ·
🟦 blue: SwiftUI view · 🩵 cyan: view model (`ObservableObject`, main thread) ·
🟩 green: transport · ⬜ gray: plain class.

**Lines** — ━━ **thick green**: MultipeerConnectivity radio (FlatBuffers) ·
┄┄ **dashed purple**: message into the actor's FIFO inbox (`tell`) ·
── thin: direct method call.

UIKit shells (thin view controllers hosting each SwiftUI view) are omitted for
clarity. Every box owns its state and is driven from exactly one place; the
whole suite runs clean under Thread Sanitizer.

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
