# Remote Shutter — Architecture

Two Apple devices, one photo shoot: one phone is the **camera**, the other is the
**remote** (monitor). They find each other over peer-to-peer Wi-Fi/Bluetooth
(MultipeerConnectivity), the remote sees a live preview, and every camera control —
shutter, video, zoom, lens, flash, torch, quality — works from across the room.
An Apple Watch can also drive the camera directly (no second phone needed).

## The big picture

```mermaid
flowchart TB
    classDef actor fill:#7c3aed,color:#fff,stroke:#4c1d95,stroke-width:3px
    classDef swiftui fill:#0ea5e9,color:#fff,stroke:#075985
    classDef viewmodel fill:#a5f3fc,color:#0e7490,stroke:#0e7490
    classDef worker fill:#fbbf24,color:#78350f,stroke:#b45309
    classDef plain fill:#e5e7eb,color:#111827,stroke:#6b7280
    classDef transport fill:#4ade80,color:#14532d,stroke:#166534

    subgraph Remote["📱 REMOTE (monitor)"]
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

    MPS1 <== "commands + responses · FlatBuffers, reliable" ==> MPS2
    MPS2 == "preview frames · HEIC/JPEG, unreliable" ==> MPS1

    linkStyle 16,17 stroke:#16a34a,stroke-width:3px
    linkStyle 0,11 stroke:#7c3aed,stroke-dasharray:5
```

| Legend | Meaning |
|:---:|---|
| 🟪 **purple hexagon** | Swift `actor` — serialized by the compiler |
| 🟨 **amber box** | Queue-confined worker (owns the serial queue named in the box) |
| 🟦 **blue box** | SwiftUI view |
| 🩵 **cyan box** | View model (`ObservableObject`, main thread) |
| 🟩 **green box** | Transport |
| ⬜ **gray box** | Plain class |
| ━━ **thick green line** | MultipeerConnectivity radio (FlatBuffers) |
| ┄┄ **dashed purple line** | Message into an actor's FIFO inbox (`tell`) |
| ── **thin line** | Direct method call |

UIKit shells (thin view controllers hosting each SwiftUI view) are omitted for
clarity. Every box owns its state and is driven from exactly one place; the
whole suite runs clean under Thread Sanitizer.

## What happens when you tap the shutter

```mermaid
sequenceDiagram
    actor U as You
    participant MV as MonitorView<br/>(SwiftUI)
    participant SCR as SessionCoordinator<br/>(remote · actor)
    participant MP as MonitorPresenter
    participant W as MultipeerConnectivity<br/>(FlatBuffers)
    participant SCC as SessionCoordinator<br/>(camera · actor)
    participant RIG as CameraRig
    participant ENG as CaptureEngine<br/>(AVFoundation)

    U->>MV: tap shutter
    MV->>SCR: UICmd.TakePicture (tell)
    Note over SCR: state → monitorTakingPicture<br/>alert "Requesting picture"<br/>10s timeout armed
    SCR->>W: RemoteCmd.TakePic (reliable)
    W->>SCC: didReceiveMessage → tell
    SCC->>RIG: takePicture()
    Note over SCC: state → cameraTakingPic<br/>alert "Taking picture"<br/>10s timeout armed
    RIG->>ENG: capturePhoto (sessionQueue → main)
    ENG-->>RIG: onPicture(bytes) — cropped to aspect
    RIG->>SCC: UICmd.OnPicture (tell)
    Note over SCC: save to camera roll (Photos)<br/>dismiss alert
    SCC->>W: TakePicAck (reliable)
    W->>SCR: tell
    Note over SCR: alert → "Receiving picture"
    SCC->>W: TakePicResp + photo bytes (reliable)
    Note over SCC: state → camera<br/>re-binds FrameSender
    W->>SCR: tell
    Note over SCR: save to camera roll (Photos)<br/>dismiss alert · state → monitor
    SCR->>MP: renderPhotoMode()
    MP->>MV: view model update (main thread)
    SCR->>W: RequestFrame — preview resumes
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
