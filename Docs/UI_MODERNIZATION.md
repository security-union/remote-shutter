# UI Modernization Plan

Companion to [MODERNIZATION.md](MODERNIZATION.md) (Theater/actor removal). That doc is about
the concurrency layer; this one is about the UI layer: killing the last UIKit shells,
Objective-C files, and dead code left over from the storyboard era.

Each PR below is a small, independently shippable slice. The **worklog** at the bottom
collects raw material (numbers, before/after, war stories) for a blog post about
modernizing this app with Claude (Fable).

## Where the app actually is (inventory, 2026-07-05)

Better than expected:

- **Zero storyboards, zero xibs.** Launch screen is the `UILaunchScreen` plist dict.
- **UIScene lifecycle fully adopted**; `AppDelegate` is minimal, window built in `SceneDelegate`.
- **Deprecated-API greps come back clean**: no `keyWindow`, `statusBarOrientation`,
  `UIAlertView`, `AVCaptureStillImageOutput`, `openURL(_:)`.
- **Four of five screens are already SwiftUI**, hosted by thin UIKit shells:
  `WelcomeView`, `RolePickerView`, `DeviceScannerView`, `MonitorView`.

What's left:

| Surface | Size | Blocker |
|---|---|---|
| Dead code (old permission system, orphaned IB controller, stubs, unused extensions) | ~10 files | none — delete |
| Objective-C: `CPSoundManager`, `RCTimer` (+ app bridging header) | 3 files | none — trivial ports |
| UIKit shells: `WelcomeViewController`, `RolePickerController` | ~320 lines | thin coordinators |
| `DeviceScannerViewController` | 367 lines | owns actor lifecycle; is `ViewCtrlActor<Self>` target |
| `MonitorViewController` + glue | ~820 lines | `MonitorActor: ViewCtrlActor<MonitorViewController>` calls the concrete VC |
| `CameraViewController` | 1729 lines | AVFoundation capture graph; no SwiftUI view exists |
| `WatchRemoteCameraController` | 322 lines | embeds CameraViewController as child |

The structural blocker for the hard tier is Theater's `ViewCtrlActor<ConcreteVC>` generic
binding — actors are type-welded to UIKit view controllers. That work overlaps with
MODERNIZATION.md Phases 4–5.

## PR sequence

### PR 1: Dead code sweep — **shipped (#122)**
Pure deletion, no behavior change.

Files deleted (all verified zero callers):
- `CameraAccess.swift` — the pre-`PermissionManager` permission system, entirely superseded
- `RolePickerOptionController.swift` — IBOutlet controller whose xib died long ago
- `PopoverController.swift` — SwiftUI "Hello, World!" stub
- `TorchTest.swift` — diagnostic scaffolding
- `UIOrientationHelpers.swift` — literally empty (header comment + import)
- `CGImage.swift` — unused `rotated(by:)`
- `UIViewController.swift` — unused child-VC helpers (call sites use `addChild` directly)
- `UIButton.swift` — `styleButton`, only caller was `RolePickerOptionController`
- `UIView.swift` — `roundCorners`/`styleEmbeddedView`, only caller was `styleButton`
- `UIImage+ImageProcessing.h/.m` — old ObjC frame path, replaced by `JPEGFrameEncoder`/`HEICFrameEncoder`
- `RemoteShutterTests-Bridging-Header.h`, `RemoteShutterUITests-Bridging-Header.h` — empty

Members trimmed from live files:
- `OrientationUtils`: `transformToUIKit`, `transformToUIImage`, `transformOrientationToImage`
- `UIImage+gif`: `gifImageWithURL`

Plus: drop `UIImage+ImageProcessing.h` from the app bridging header, clear the test
targets' `SWIFT_OBJC_BRIDGING_HEADER` settings, fix stale storyboard claims in CLAUDE.md.

### PR 2: Retire the Objective-C — **shipped (#123)**
Port `CPSoundManager` (countdown beeps, `AVAudioPlayer`) and `RCTimer`
(recursive-`dispatch_after` countdown) to small Swift types; delete
`RemoteCam-Bridging-Header.h`. Zero ObjC left in the app target.

### PR 3: Test hardening + collapse the easy shells — **shipped (#124)**
Two layers of integration tests written FIRST (against pre-refactor behavior), then
the refactor under them:

**Tests**
- `ControllerWiringTests` — instantiates the real shell controllers in the hosted test
  app and pins their contract: SwiftUI host embedded and pinned, navigation pushes,
  actor registration in viewDidLoad, actor teardown in deinit.
- `LoopbackSessionTests` — two `RemoteCamSession` actors wired through
  `LoopbackMultipeerService`, an in-process transport that passes every message
  through the real FlatBuffers encode/decode. Full protocol round trips across both
  state machines: role handshake, take-picture, toggle-flash, start-recording, zoom,
  peer disconnect.

**Refactor**
- Delete `iAdViewController`/`BaseViewController.swift` (`showError` moved to
  `UIAlertPresenter.swift`; `MonitorViewController` now subclasses `UIViewController`)
- `RemoteCamSystem.shared` moved out of `RolePickerController` into `RemoteCamSystem.swift`
- New `UIViewController+SwiftUIHosting.swift`: `embedSwiftUIView` + `presentHelpSheet`
  replace 5 copies of the embed boilerplate and 4 copies of the help-sheet code
- Dead `connectedPrompt`, `pinchGestureRecognizer`, `lastPinchScale` removed

### PR 4: Decouple MonitorActor from MonitorViewController — **shipped (#125)**
- New `MonitorDisplay` protocol — everything the actor needs from the monitor screen
  (mode configuration, view-model updates, frame routing, exit navigation).
- `MonitorActor` moved out of MonitorViewController.swift into `MonitorActor.swift` and
  rebuilt as a plain `Actor` bound via `SetMonitorDisplay` + a weak display box —
  no longer `ViewCtrlActor<MonitorViewController>`. (Swift won't accept a protocol
  existential as a class-constrained generic argument, and a plain actor matches the
  MODERNIZATION.md Phase 5 target anyway.)
- `MonitorViewController` conforms to `MonitorDisplay`; `navigationController?.pop`
  became `exitMonitor()` on the protocol.
- New `MonitorActorTests` (8) drive the actor against `FakeMonitorDisplay` — the first
  time this actor has ever been testable without a live UIKit controller.
- `RemoteCamSession`'s `ViewCtrlActor<DeviceScannerViewController>` binding is the
  remaining coupling — PR 5.

### PR 5: Camera dead-code sweep — **shipped (#126)**
An audit of CameraViewController (1,729 lines) found it ~65% capture-engine code in a
UIViewController costume, ~25% real UI, ~10% dead/deprecated. This PR is the deletion
slice only: `sendCameraCapabilities()` (superseded by the retry-ladder push in
CamStates.swift), `getCurrentTorchMode()`, `hasTorch()`, `setFlashMode()` (leftovers a
prior migration's own comment claimed were "removed"), the deprecated
`willAnimateRotation` stub, and tombstone comments.

### PR 6: Decouple RemoteCamSession from DeviceScannerViewController — **shipped (#127)**
- New `ScannerLobby` protocol (peerID, role, scanner view model, `goToRole`,
  `returnToLobby`, `presentScanningError`) + `SetScannerLobby` + weak box —
  PR 4's recipe applied to the session.
- `RemoteCamSession` is a plain `Actor` now (carries ViewCtrlActor's
  `popToState`/`popToRootState` stop-at-root behavior with it, same state names).
- Scanning-error alert construction moved from the actor into the VC.
- All state signatures take `WeakScannerLobby`; `TestDeviceScannerViewController`
  (the UIKit-dodging test subclass) is replaced by a plain `FakeScannerLobby`.
- Milestone: no actor is generically bound to a UIKit controller anymore. The one
  remaining UIKit handle in actor code is the `CameraViewController` passed through
  `UICmd.BecomeCamera` into the camera states — that's exactly what PR 7's
  `CaptureEngine` replaces.

### PR 7: CameraControlling protocol seam — **shipped (#128)**
The watch-hardening work had already built the seam (`WatchCameraControlling`,
fake-backed); this PR generalizes it. Renamed `CameraControlling`, moved to its
own file, extended with the nine members the phone camera states need
(`cameraViewModel`, quality/aspect setters, capabilities, countdown chime/torch,
`exitCamera`). `UICmd.BecomeCamera` now carries the protocol; camera/video state
signatures follow; the session's direct `navigationController` pop became
`exitCamera()`. The camera-side `OnPicture` handler now routes through the
`photoLibrarySaver` seam like the watch path always did.

Milestone completed: **no actor code references a UIKit type.** Payoff test:
`testTakePictureHappyPathAcrossTheWire` — a fake camera behind the protocol lets
the loopback harness run the full two-device photo capture (become camera →
become monitor → TakePic → OnPicture → Ack + Resp with bytes → both sides back
to steady state) in CI for the first time.

### PR 8: Extract CaptureEngine (configuration + stills)
Mechanical extraction, no behavior/threading changes: `CaptureEngine` (non-UI,
`NSObject`, the photo-capture delegate) now owns the capture session, device/lens/zoom
discovery, capabilities, flash/torch intent, quality/format/aspect config, and still
capture + crop. The VC keeps the preview layer, overlays, lifecycle, and the whole
recording/sample-buffer pipeline (next PR), reaching the session via engine-exposed
properties. Engine↔UI seams: `onPicture` (actor relay), `onStatusChanged`,
`rotateOutputs(orientation:)` (VC still rotates the preview connection).
Still queued for follow-ups: single owned serial queue (threading fix),
`RotationCoordinator` (iOS 17) and `maxPhotoDimensions` (iOS 16) migrations,
recording pipeline extraction.

### PR 9: Extract RecordingPipeline (video recording) — **this PR**
Same playbook as PR 8 — mechanical move, no behavior/threading changes:
`RecordingPipeline` (non-UI) owns the asset writer and its inputs, the
recording state machine, the writing queue, per-frame write/crop, and
saving/sending the finished movie. The VC stays the sample-buffer delegate
(the frame streamers are live preview, not recording) and keeps the
microphone-permission flow, forwarding recording frames to
`pipeline.processFrame`. Pipeline↔UI seams: `sendMessage` (actor relay for
the start ack, stop response and video resource), `onRecordingStarted`/
`onRecordingStopped` (timer overlay), `onModeChanged` (idle vs recording
chrome), `onError`, `onPhotosAccessDenied`. Still queued for follow-ups:
single owned serial queue (threading fix), `RotationCoordinator` (iOS 17)
and `maxPhotoDimensions` (iOS 16) migrations, frame-streaming extraction.

### PR 10+: Camera SwiftUI chrome
With capture and recording out, the VC is real UI plus the frame streamers:
SwiftUI chrome around a `UIViewRepresentable` preview layer.
`WatchRemoteCameraController` follows.

## Worklog (blog raw material)

### PR 1 — dead code sweep
- Inventory ran as two parallel read-only agents: one walked every view controller,
  the other chased ObjC/bridging headers/deprecated APIs. ~30 min wall clock.
- Expected storyboards to hunt; found none. The docs said "DeviceScannerViewController —
  UIKit + Storyboard, entry point" — the code said otherwise. Docs lie, greps don't.
- Best find: an entire permission system (`CameraAccess.swift`) still compiling,
  fully replaced, zero callers — each method politely apologizing in comments that
  the new system had taken over.
- Dead-code cascade: deleting one orphaned IB controller made `UIButton.swift` dead,
  which made `UIView.swift` dead. Delete one leaf, the branch comes with it.
- Two "dead" files (`PopoverController.swift`, `TorchTest.swift`) turned out not to be
  in the pbxproj at all — orphaned on disk, never even compiling.
- Plot twist: removing `UIImage+ImageProcessing.h` from the bridging header broke the
  build in 10 files that never imported UIKit. Its `#import <UIKit/UIKit.h>` had been
  silently granting UIKit to every Swift file in the target for years. The dead code
  was load-bearing — not for what it did, but for what it imported. Fix: explicit
  `import UIKit` in the 10 files that were freeloading.
- Net: 27 files changed, +143/−557 lines; 13 files deleted; 348/348 tests green.

### PR 2 — retire the Objective-C
- `CPSoundManager` (2012, "Clapmera", `__MyCompanyName__` copyright header) and
  `RCTimer` (2013) were the last app-target ObjC. 139 lines of ObjC across 4 files
  → ~100 lines of Swift in 2 files (`SoundManager`, `CountdownTimer`), same semantics.
- The bridging-header lesson from PR 1 repeated on cue: deleting the header removed the
  free `AVFoundation` import that `CPSoundManager.h` had been granting the whole target —
  `RemoteCmds.swift`/`UICmds.swift` (which serialize `AVCaptureDevice` positions over the
  wire) never imported it. Two more explicit imports.
- `CountdownTimer` is pure Swift now, so it got what the ObjC never had: unit tests
  (tick sequence, zero-duration sync completion, cancel).
- 351/351 tests green (348 + 3 new).

### PR 3 — test hardening + shell collapse
- Wrote the tests FIRST against unrefactored code (characterization), then refactored
  under them. The wiring tests instantiate the app's real view controllers inside the
  hosted test bundle — possible only because PR 1 confirmed everything is programmatic
  (no storyboards to inflate).
- The loopback harness is the fun one: two full session state machines in one process,
  every message crossing a fake wire through the real FlatBuffers encode/decode.
  A take-picture round trip (UICmd → state transition → encode → decode → peer state
  machine → error response → encode → decode → pop + alert) runs in ~0.8s in CI.
  Closest thing to a two-device test without two devices.
- Gotcha: deinit-based teardown assertions need `autoreleasepool {}` around the
  controller's lifetime — UIKit autoreleases references to the VC, so without it
  deinit doesn't run until the test method returns and the assertions read stale state.
- Along the way the docs lied again: CLAUDE.md still said the wire protocol was
  NSCoding/NSKeyedArchiver (it's FlatBuffers) and listed four CocoaPods that no longer
  exist (Theater, Starscream, Google Ads, UMP — actual: SwiftLint + FlatBuffers).
- Net: 14 files changed, +593/−164; 12 new integration tests; 363/363 green, and the
  new tests passed unchanged across the refactor — which was the whole point.

### PR 4 — MonitorActor decoupling
- The plan was to loosen Theater's `ViewCtrlActor<A: UIViewController>` to
  `A: AnyObject` and bind the actor to `any MonitorDisplay`. The compiler said no:
  "'ViewCtrlActor' requires that 'any MonitorDisplay' be a class type" — a
  class-constrained existential still isn't a class type to generics.
- Plan B was better anyway: MonitorActor became a plain `Actor` with an explicit
  `SetMonitorDisplay` message and a hand-rolled weak box. Fewer generics, less
  framework, and exactly what MODERNIZATION.md Phase 5 prescribed.
- The payoff: `MonitorActorTests` drives the full message surface (render modes,
  flash/torch/zoom/lens responses, video-transfer progress, become-monitor-failed)
  against a fake display object. Before this PR that required a live UIKit controller.
- PR 3's wiring + loopback tests passed unchanged across the swap — the safety net
  did its job on the first PR it was built for.

### PR 5 — camera dead-code sweep
- The audit's best find: four torch/flash/capabilities methods that a comment in
  *another file* claimed were already removed ("Legacy setFlashMode and setTorchMode
  functions removed"). The comment was aspirational; the code was still compiling.
- `sendCameraCapabilities()` told the story of its own replacement: it fire-and-forgot
  capabilities through the session actor's root receive, while the live path in
  CamStates.swift pushes with a 4-attempt retry ladder because the capture device
  isn't ready right after setup. The old path lost the race and nobody buried it.
- Also filed for later (not deletions): the unsynchronized three-thread capture-session
  mutation, six-boolean recording state machine, and the iOS 16/17 AVFoundation
  deprecations — all queued for the PR 7 CaptureEngine extraction.

### PR 6 — RemoteCamSession decoupling
- Wider diff than PR 4 (13 signature swaps across 7 state files) but the same shape;
  the actual lobby surface turned out to be tiny — most states only pass it through,
  and only scanning/connected/startScanning ever dereference it.
- The session kept ViewCtrlActor's exact state names ("waitingForCtrl"/"withCtrl9")
  so the state machine's shape — and 60+ existing state tests — didn't move.
- Test scaffolding upgrade as a side effect: `TestDeviceScannerViewController`,
  a subclass whose whole job was dodging UIKit landmines in tests, died; a
  12-line `FakeScannerLobby` took its place.
- 371/371 green on the first full run after the conversion.

### PR 7 — camera protocol seam
- Half the work was already done and hiding in plain sight: the watch-hardening
  effort had built `WatchCameraControlling` — protocol, conformance, and a fake —
  for the watch path only. Generalizing beat inventing.
- The best assertion in the suite so far: a fake camera behind the seam let the
  loopback harness run the complete two-device photo capture — become camera,
  become monitor, TakePic across the wire, capture, Ack, Resp carrying the actual
  bytes, both state machines back to steady state — all in-process, in CI.
  Until now that flow had only ever been verified with two phones on a desk.
- 372/372 green.

### PR 8 — CaptureEngine extraction
- Delegated the mechanical move to a fresh-context agent with an exact boundary
  spec and one objective gate: the full suite green. It came back 376/376
  (4 new engine tests) with an honest deviations list — the kind of report you
  want from a contractor.
- CameraViewController: ~1,670 → ~960 lines. CaptureEngine: 866 lines of capture
  logic with no view code — its only UIKit dependencies are orientation enums and
  `UIImage` for still cropping.
- The one redundancy knowingly introduced: after toggleCamera the preview
  rotation re-runs the (idempotent) output rotation. Faithful beats clever in a
  mechanical-move PR.
- Orientation now lives in two places (VC for preview/UI, engine cache for output
  connections) — flagged as the thing the PR 9 RotationCoordinator migration
  should collapse.
- Coverage follow-up on the same PR: 5 more back-to-back loopback round trips
  (flash mode value, toggle-camera capabilities payload, zoom factor + range echo,
  lens switch, and the full 3-step video stop protocol) — all green first run.
  381 total tests, up from 348 when this series started.
- Bug found while wiring the video test, then fixed in the same PR (failing test
  first — red run captured): the success `StartRecordingVideoAck` carrying
  `recordingStartTime` for the monitor's timer sync was sent to the camera's
  local session actor but never forwarded to the peer — Theater logged "message
  not handled" and the monitor's recording timer never synced the real start
  time on the phone path. The watch path handled the ack explicitly, which is
  why nobody noticed. Fix: one forwarding case in `cameraShootingVideo`.
  The loopback harness caught in an afternoon what shipped unnoticed for years —
  because nobody ever watched both phones' timers at once.

### PR 9 — RecordingPipeline extraction
- The smaller sibling of PR 8: 962 → 632 VC lines; `RecordingPipeline` is 407
  lines with no UIKit at all. The six-boolean recording state machine moved
  intact — extraction first, redesign later (still queued behind the
  single-queue threading fix).
- The delegate split was the only real design decision: the VC stays the
  sample-buffer delegate because `captureOutput` fans out to *two* consumers —
  frame streaming (live preview, stays) and recording (moves). The pipeline
  gets frames forwarded, mirroring how the audio delegate is passed into
  `startRecording` the same way PR 8 passed it into `setupCamera`.
- One seam replaced three actor touchpoints: `sendMessage` relays the start
  ack, stop response and video resource without the pipeline knowing the actor
  system — which also made the no-op guards assertable in tests (inject a
  recorder, assert nothing was sent).
- New device-free coverage: asset-writer input setup including the 4:3
  even-rounded crop rect (1920×1080 → 1440×1080 at x=240) — the "must be even
  for the codec" rounding had never been asserted anywhere.
- 385/385 green (381 + 4 pipeline tests); the loopback video round-trips —
  including the 3-step stop protocol — passed unchanged across the move.
